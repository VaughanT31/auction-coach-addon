-- Auction Coach - options page in Esc > Options > AddOns, built with
-- Blizzard's Settings API. Each option reads and writes ns.db.settings
-- through a proxy, so values keep the units the rest of the addon uses
-- (copper, fractions) while the sliders show gold and percent.

local _, ns = ...
local L = ns.L

local Options = {}
ns.Options = Options

local category

local function Changed()
    if ns.Deals then ns.Deals:Invalidate() end
    if ns.MainWindow then ns.MainWindow:Refresh() end
end

-- A checkbox for ns.db.settings[field]. invert shows "on" when the stored
-- value is false (used for "hide" style settings).
local function Checkbox(field, name, tooltip, default, onChange, invert)
    local function Get()
        local value = ns.db.settings[field] and true or false
        if invert then return not value end
        return value
    end
    local function Set(value)
        if invert then value = not value end
        ns.db.settings[field] = value
        if onChange then onChange(value) end
    end
    local setting = Settings.RegisterProxySetting(category, "AuctionCoach_" .. field,
        Settings.VarType.Boolean, name, default, Get, Set)
    Settings.CreateCheckbox(category, setting, tooltip)
end

-- A slider shown in display units. toDisplay / fromDisplay convert between
-- the stored value and the slider value.
local function Slider(field, name, tooltip, default, min, max, step, toDisplay, fromDisplay, label)
    local function Get() return toDisplay(ns.db.settings[field]) end
    local function Set(value)
        ns.db.settings[field] = fromDisplay(value)
        Changed()
    end
    local setting = Settings.RegisterProxySetting(category, "AuctionCoach_" .. field,
        Settings.VarType.Number, name, toDisplay(default), Get, Set)
    local options = Settings.CreateSliderOptions(min, max, step)
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, label)
    Settings.CreateSlider(category, setting, options, tooltip)
end

-- Section headings are a nicety: skipped if this client lacks the helpers.
-- A dropdown for ns.db.settings[field]. choices = { { value, label }, ... }
local function Dropdown(field, name, tooltip, default, choices, onChange)
    if not (Settings.CreateDropdown and Settings.CreateControlTextContainer) then return end
    local function Get() return ns.db.settings[field] or default end
    local function Set(value)
        ns.db.settings[field] = value
        if onChange then onChange(value) end
    end
    local setting = Settings.RegisterProxySetting(category, "AuctionCoach_" .. field,
        Settings.VarType.String, name, default, Get, Set)
    local function Choices()
        local container = Settings.CreateControlTextContainer()
        for _, choice in ipairs(choices) do container:Add(choice[1], choice[2]) end
        return container:GetData()
    end
    Settings.CreateDropdown(category, setting, Choices, tooltip)
end

local function Header(text)
    if not (SettingsPanel and SettingsPanel.GetLayout and CreateSettingsListSectionHeaderInitializer) then
        return
    end
    pcall(function()
        SettingsPanel:GetLayout(category):AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
    end)
end

local GOLD = 10000

local function Build()
    if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterProxySetting) then
        return
    end
    category = Settings.RegisterVerticalLayoutCategory(L.ADDON_TITLE)

    Header(L.OPT_GENERAL)
    Dropdown("sellerStyle", L.OPT_STYLE, L.OPT_STYLE_TIP, "casual", {
        { "casual", L.OPT_STYLE_CASUAL },
        { "active", L.OPT_STYLE_ACTIVE },
        { "camper", L.OPT_STYLE_CAMPER },
    }, Changed)
    Checkbox("tooltip", L.OPT_TOOLTIP, L.OPT_TOOLTIP_TIP, true)
    Checkbox("autoScan", L.OPT_AUTOSCAN, L.OPT_AUTOSCAN_TIP, true)
    Checkbox("saleMessages", L.OPT_SALES, L.OPT_SALES_TIP, true)
    Checkbox("treasureNotice", L.OPT_TREASURE, L.OPT_TREASURE_TIP, true)
    Checkbox("staleWarning", L.OPT_STALE, L.OPT_STALE_TIP, true)
    Checkbox("minimapHide", L.OPT_MINIMAP, L.OPT_MINIMAP_TIP, true, function()
        if ns.MinimapButton then ns.MinimapButton:Update() end
    end, true)

    Checkbox("destroyTooltip", L.OPT_DESTROY_TOOLTIP, L.OPT_DESTROY_TOOLTIP_TIP, true)
    Checkbox("shoppingAlerts", L.OPT_SHOP_ALERTS, L.OPT_SHOP_ALERTS_TIP, true)

    Header(L.PLAN_TITLE_EMPTY)
    Slider("planMinutes", L.OPT_PLAN, L.OPT_PLAN_TIP, 15, 5, 60, 5,
        function(minutes) return minutes or 15 end,
        function(minutes) return minutes end,
        function(minutes) return L.OPT_MINUTES:format(minutes) end)

    Header(L.OPT_PROTECTION)
    Checkbox("vendorGuard", L.OPT_GUARD, L.OPT_GUARD_TIP, true)
    Slider("guardMinGain", L.OPT_GUARD_GAIN, L.OPT_GUARD_GAIN_TIP, 10 * GOLD, 1, 500, 1,
        function(copper) return math.floor((copper or 0) / GOLD + 0.5) end,
        function(gold) return gold * GOLD end,
        function(gold) return L.OPT_GOLD:format(gold) end)

    Header(L.OPT_DEALS)
    Slider("dealMinDiscount", L.OPT_DEAL_DISCOUNT, L.OPT_DEAL_DISCOUNT_TIP, 0.3, 10, 80, 5,
        function(fraction) return math.floor((fraction or 0) * 100 + 0.5) end,
        function(percent) return percent / 100 end,
        function(percent) return L.OPT_PERCENT:format(percent) end)
    Slider("dealMinProfit", L.OPT_DEAL_PROFIT, L.OPT_DEAL_PROFIT_TIP, 5 * GOLD, 1, 1000, 1,
        function(copper) return math.floor((copper or 0) / GOLD + 0.5) end,
        function(gold) return gold * GOLD end,
        function(gold) return L.OPT_GOLD:format(gold) end)

    Settings.RegisterAddOnCategory(category)
end

function Options:Open()
    if category and Settings.OpenToCategory then
        Settings.OpenToCategory(category:GetID())
    end
end

ns.Events:On("AC_DB_READY", function()
    local ok, err = pcall(Build)
    if not ok then geterrorhandler()(err) end
end)

ns:RegisterCommand("options", function() Options:Open() end, L.HELP_OPTIONS)
