-- Auction Coach - "don't throw that away" protection.
--
-- Vendor: a sale cannot be stopped without tainting Blizzard's bag code, so
-- the guard works in two steps. Before the sale, item tooltips at a
-- merchant warn in red (Advice/Rules.lua). After the sale, a popup offers
-- to buy the items straight back from the merchant's buyback tab.
--
-- Delete: when the delete confirmation opens for a valuable item, a warning
-- appears above it. The player still decides.

local _, ns = ...
local L, Util, Compat, Rules = ns.L, ns.Util, ns.Compat, ns.Rules

local soldBatch = {}

local DELETE_POPUPS = { "DELETE_ITEM", "DELETE_GOOD_ITEM", "DELETE_QUEST_ITEM", "DELETE_GOOD_QUEST_ITEM" }

local function Enabled()
    return ns.db and ns.db.settings.vendorGuard
end

-- ---------------------------------------------------------------------
-- Vendor buyback
-- ---------------------------------------------------------------------

local function ItemIDOf(link)
    return link and tonumber(link:match("item:(%d+)"))
end

local function BuyBack(items)
    local bought = 0
    -- The buyback list updates after the server answers, so remember which
    -- slots were already used in this pass.
    local used = {}
    for _, item in ipairs(items) do
        -- Newest sales are at the end of the buyback list.
        for i = GetNumBuybackItems(), 1, -1 do
            if not used[i] and ItemIDOf(GetBuybackItemLink(i)) == ItemIDOf(item.link) then
                BuybackItem(i)
                used[i] = true
                bought = bought + 1
                break
            end
        end
    end
    if bought > 0 then
        Util.Print(L.GUARD_BOUGHT_BACK:format(bought))
    end
end

StaticPopupDialogs.AUCTIONCOACH_BUYBACK = {
    text = "%s",
    button1 = L.GUARD_BUY_BACK,
    button2 = L.GUARD_KEEP_SOLD,
    OnAccept = function(_, data)
        if Compat.IsMerchantOpen() then BuyBack(data) end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function ShowSoldPopup()
    local items = soldBatch
    soldBatch = {}
    if #items == 0 or not Compat.IsMerchantOpen() then return end

    local vendorTotal, ahTotal = 0, 0
    for _, item in ipairs(items) do
        vendorTotal = vendorTotal + item.vendor * item.count
        ahTotal = ahTotal + item.afterCut * item.count
    end

    local text
    if #items == 1 then
        text = L.GUARD_SOLD_ONE:format(items[1].link, Util.FormatMoney(vendorTotal), Util.FormatMoney(ahTotal))
    else
        text = L.GUARD_SOLD_MANY:format(#items, Util.FormatMoney(vendorTotal), Util.FormatMoney(ahTotal))
    end
    StaticPopup_Show("AUCTIONCOACH_BUYBACK", text, nil, items)
end

-- Runs after the default UI uses (and so sells) a bag item. The item is
-- still in the slot, locked, while the server processes the sale.
hooksecurefunc(C_Container, "UseContainerItem", function(bagID, slot)
    if not Enabled() or not Compat.IsMerchantOpen() then return end
    local info = C_Container.GetContainerItemInfo(bagID, slot)
    if not info or not info.hyperlink or info.isBound then return end

    local key = Util.ItemKeyFromLink(info.hyperlink)
    local afterCut, vendor = Rules:IsWorthWarning(key, info.hyperlink)
    if not afterCut or vendor == 0 then return end

    table.insert(soldBatch, {
        link = info.hyperlink,
        count = info.stackCount or 1,
        afterCut = afterCut,
        vendor = vendor,
    })
    -- Group quick multi-sells (or sell-junk addons) into one popup.
    Util.Debounce("vendorGuard", 0.6, ShowSoldPopup)
end)

-- ---------------------------------------------------------------------
-- Delete warning
-- ---------------------------------------------------------------------

local warning

local function FindDeletePopup()
    if not StaticPopup_FindVisible then return nil end
    for _, which in ipairs(DELETE_POPUPS) do
        local popup = StaticPopup_FindVisible(which)
        if popup then return popup end
    end
    return nil
end

local function GetWarningFrame()
    if warning then return warning end
    warning = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    warning:SetSize(360, 60)
    warning:SetFrameStrata("DIALOG")
    warning:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    warning:SetBackdropColor(0.25, 0, 0, 0.95)
    warning:SetBackdropBorderColor(1, 0.3, 0.3)
    warning.text = warning:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    warning.text:SetPoint("TOPLEFT", 10, -10)
    warning.text:SetPoint("BOTTOMRIGHT", -10, 10)
    warning.text:SetJustifyH("CENTER")
    warning:SetScript("OnUpdate", function(self)
        if self.anchor and not self.anchor:IsShown() then
            self:Hide()
        end
    end)
    warning:Hide()
    return warning
end

ns.Events:On("DELETE_ITEM_CONFIRM", function()
    if not Enabled() then return end
    local cursorType, _, link = GetCursorInfo()
    if cursorType ~= "item" or not link then return end

    local key = Util.ItemKeyFromLink(link)
    local afterCut = Rules:IsWorthWarning(key, link)
    if not afterCut then return end

    local frame = GetWarningFrame()
    frame.text:SetText(L.GUARD_DELETE:format(link, Util.FormatMoney(afterCut)))
    frame:ClearAllPoints()
    -- The popup is shown on the same frame as this event, so look it up
    -- on the next frame.
    C_Timer.After(0, function()
        local popup = FindDeletePopup()
        frame.anchor = popup
        if popup then
            frame:SetPoint("BOTTOM", popup, "TOP", 0, 6)
        else
            frame:SetPoint("CENTER", UIParent, "CENTER", 0, 180)
            C_Timer.After(10, function() if frame.anchor == nil then frame:Hide() end end)
        end
        frame:Show()
    end)
    Util.Print(L.GUARD_DELETE:format(link, Util.FormatMoney(afterCut)))
end)

ns:RegisterCommand("guard", function()
    local settings = ns.db.settings
    settings.vendorGuard = not settings.vendorGuard
    Util.Print(settings.vendorGuard and L.GUARD_ON or L.GUARD_OFF)
end, L.HELP_GUARD)
