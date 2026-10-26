-- Auction Coach - "Accounting" tab (0.26): where your gold came from and
-- went (Data/Ledger.lua). Pick a period (today, this week from the weekly
-- reset, this month, all time) and who (this character, your characters
-- on this realm, the whole account). Net and the biggest income and cost
-- on top, then income and spending by category, each with a bar.
-- Hovering a category in the realm or account view splits it by character.

local _, ns = ...
local L, Util, Skin = ns.L, ns.Util, ns.Skin

local ROW_HEIGHT = 18
local MAX_ROWS = 15
local CHOICE_HEIGHT = 20

local PERIODS = {
    { key = "today", label = "LEDGER_TODAY", phrase = "LEDGER_IN_TODAY" },
    { key = "week", label = "LEDGER_WEEK", phrase = "LEDGER_IN_WEEK" },
    { key = "month", label = "LEDGER_MONTH", phrase = "LEDGER_IN_MONTH" },
    { key = "all", label = "LEDGER_ALL", phrase = "LEDGER_IN_ALL" },
}
local SCOPES = {
    { key = "char", label = "LEDGER_CHAR" },
    { key = "realm", label = "LEDGER_REALM" },
    { key = "account", label = "LEDGER_ACCOUNT" },
}

local GREEN, RED = { 0.4, 1, 0.4 }, { 1, 0.4, 0.4 }

local function Setting(name, default)
    return ns.db.settings[name] or default
end

local function Signed(copper)
    if copper == 0 then return "|cffcccccc0|r" end
    local text = Util.FormatMoneyIcons(math.abs(copper))
    return copper > 0 and ("|cff66ff66+" .. text .. "|r") or ("|cffff6666-" .. text .. "|r")
end

local function CatName(cat)
    return L["LEDGER_CAT_" .. cat] or cat
end

-- A row of flat tabs choosing one of options; setting is saved by key.
local function Choices(panel, options, width, setting, default)
    local buttons = {}
    for i, option in ipairs(options) do
        local tab = Skin.Tab(panel, L[option.label], width, CHOICE_HEIGHT)
        tab.key = option.key
        tab:SetScript("OnClick", function()
            ns.db.settings[setting] = option.key
            panel.Refresh()
        end)
        buttons[i] = tab
    end
    function buttons.Update()
        local current = Setting(setting, default)
        for _, tab in ipairs(buttons) do tab:SetActive(tab.key == current) end
    end
    return buttons
end

local function ShowRowTooltip(row)
    local entry = row.entry
    if not entry then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(CatName(entry.cat), 1, 0.82, 0)
    GameTooltip:AddLine(Util.FormatMoneyIcons(entry.amount), 1, 1, 1)
    if entry.total > 0 then
        GameTooltip:AddLine(L.LEDGER_SHARE:format(math.floor(entry.amount / entry.total * 100 + 0.5)), 0.8, 0.8, 0.8)
    end
    local chars = {}
    for charKey, per in pairs(entry.chars) do
        local amount = per[entry.side]
        if amount > 0 then chars[#chars + 1] = { charKey, amount } end
    end
    if Setting("ledgerScope", "account") ~= "char" and #chars > 0 then
        table.sort(chars, function(a, b) return a[2] > b[2] end)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L.LEDGER_TIP_CHARS, 1, 0.82, 0)
        for _, c in ipairs(chars) do
            GameTooltip:AddDoubleLine(c[1], Util.FormatMoneyIcons(c[2]), 1, 1, 1, 1, 1, 1)
        end
    end
    GameTooltip:Show()
end

local function CreateRow(column, index)
    local row = CreateFrame("Frame", nil, column)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT")
    Skin.RowBand(row)
    row.bar = row:CreateTexture(nil, "BACKGROUND")
    row.bar:SetPoint("TOPLEFT", 0, -1)
    row.bar:SetPoint("BOTTOMLEFT", 0, 1)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", 6, 0)
    row.name:SetJustifyH("LEFT")
    row.amount = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.amount:SetPoint("RIGHT", -6, 0)
    row.amount:SetJustifyH("RIGHT")
    row:EnableMouse(true)
    row:SetScript("OnEnter", ShowRowTooltip)
    row:SetScript("OnLeave", GameTooltip_Hide)
    return row
end

-- One side (income or spending): a header with the total and a row per category.
local function CreateColumn(panel)
    local column = CreateFrame("Frame", nil, panel)
    column.title = column:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    column.title:SetPoint("BOTTOMLEFT", column, "TOPLEFT", 2, 4)
    column.total = column:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    column.total:SetPoint("BOTTOMRIGHT", column, "TOPRIGHT", -6, 4)
    column.rows = {}
    -- Bars are a share of the column's width, which isn't known until it's laid out.
    column:SetScript("OnSizeChanged", function(self, width)
        for _, row in ipairs(self.rows) do row.bar:SetWidth(math.max(1, width * (row.fraction or 0))) end
    end)
    return column
end

local function FillColumn(column, title, entries, total, color)
    column.title:SetText(title)
    column.total:SetText(Util.FormatMoneyIcons(total))
    local width = column:GetWidth()
    local most = entries[1] and entries[1].amount or 0
    for i = 1, math.min(#entries, MAX_ROWS) do
        local row = column.rows[i] or CreateRow(column, i)
        column.rows[i] = row
        local entry = entries[i]
        row.entry = entry
        row.name:SetText(CatName(entry.cat))
        row.amount:SetText(Util.FormatMoneyIcons(entry.amount))
        row.bar:SetColorTexture(color[1], color[2], color[3], 0.16)
        row.fraction = entry.amount / math.max(1, most)
        row.bar:SetWidth(math.max(1, width * row.fraction))
        row:Show()
    end
    for i = math.min(#entries, MAX_ROWS) + 1, #column.rows do column.rows[i]:Hide() end
end

-- Categories on one side, biggest first. side 1 = income, 2 = spending.
local function Entries(totals, side, sum)
    local list = {}
    for cat, entry in pairs(totals.cats) do
        if cat ~= ns.Ledger.TRANSFER and entry[side] > 0 then
            list[#list + 1] = { cat = cat, amount = entry[side], side = side, chars = entry.chars, total = sum }
        end
    end
    table.sort(list, function(a, b)
        if a.amount ~= b.amount then return a.amount > b.amount end
        return a.cat < b.cat
    end)
    return list
end

local function Build(panel)
    panel.periods = Choices(panel, PERIODS, 80, "ledgerPeriod", "week")
    for i, tab in ipairs(panel.periods) do tab:SetPoint("TOPLEFT", 4 + (i - 1) * 84, -2) end
    panel.scopes = Choices(panel, SCOPES, 76, "ledgerScope", "account")
    for i, tab in ipairs(panel.scopes) do tab:SetPoint("TOPRIGHT", -4 - (#SCOPES - i) * 80, -2) end

    panel.who = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.who:SetPoint("TOPLEFT", 6, -CHOICE_HEIGHT - 10)

    panel.net = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    panel.net:SetPoint("TOPLEFT", panel.who, "BOTTOMLEFT", 0, -6)

    panel.headline = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    panel.headline:SetPoint("TOPLEFT", panel.net, "BOTTOMLEFT", 0, -6)
    panel.headline:SetPoint("RIGHT", -6, 0)
    panel.headline:SetJustifyH("LEFT")

    panel.income = CreateColumn(panel)
    panel.income:SetPoint("TOPLEFT", panel.headline, "BOTTOMLEFT", -2, -30)
    panel.income:SetPoint("BOTTOMRIGHT", panel, "BOTTOM", -6, 52)
    panel.spending = CreateColumn(panel)
    panel.spending:SetPoint("TOPLEFT", panel.income, "TOPRIGHT", 12, 0)
    panel.spending:SetPoint("BOTTOMRIGHT", -4, 52)

    panel.transfers = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.transfers:SetPoint("BOTTOMLEFT", 6, 26)
    panel.transfers:SetPoint("RIGHT", -6, 0)
    panel.transfers:SetJustifyH("LEFT")

    panel.note = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.note:SetPoint("BOTTOMLEFT", 6, 6)
    panel.note:SetPoint("RIGHT", -6, 0)
    panel.note:SetJustifyH("LEFT")
    panel.note:SetWordWrap(false)

    -- The how-it-works text on hovering the net line.
    local hover = CreateFrame("Frame", nil, panel)
    hover:SetAllPoints(panel.net)
    hover:EnableMouse(true)
    hover:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetText(L.TAB_ACCOUNTING, 1, 0.82, 0)
        GameTooltip:AddLine(L.LEDGER_HOW, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    hover:SetScript("OnLeave", GameTooltip_Hide)
end

local function PeriodOf(key)
    for _, p in ipairs(PERIODS) do
        if p.key == key then return p end
    end
    return PERIODS[2]
end

local function Refresh(panel, reason)
    if reason == "AC_SCAN_PROGRESS" or reason == "AC_LIVE_PRICE" then return end
    panel.Refresh = function() Refresh(panel) end
    panel.periods.Update()
    panel.scopes.Update()

    local period = PeriodOf(Setting("ledgerPeriod", "week"))
    local scope = Setting("ledgerScope", "account")
    local t = ns.Ledger:Totals(period.key, scope)
    local phrase = L[period.phrase]

    panel.who:SetText(scope == "char" and L.LEDGER_SCOPE_CHAR:format(ns.charKey or "")
        or scope == "realm" and L.LEDGER_SCOPE_REALM or L.LEDGER_SCOPE_ACCOUNT)
    panel.net:SetText(L.LEDGER_NET:format(phrase, Signed(t.net)))

    local lines = {}
    if t.income == 0 and t.spending == 0 then
        lines[1] = L.LEDGER_NOTHING:format(phrase)
    else
        if t.topIncome then
            lines[#lines + 1] = L.LEDGER_TOP_INCOME:format(CatName(t.topIncome), Util.FormatMoneyIcons(t.cats[t.topIncome][1]))
        end
        if t.topCost then
            lines[#lines + 1] = L.LEDGER_TOP_COST:format(CatName(t.topCost), Util.FormatMoneyIcons(t.cats[t.topCost][2]), phrase)
        end
    end
    panel.headline:SetText(table.concat(lines, "  "))

    FillColumn(panel.income, L.LEDGER_INCOME, Entries(t, 1, t.income), t.income, GREEN)
    FillColumn(panel.spending, L.LEDGER_SPENDING, Entries(t, 2, t.spending), t.spending, RED)

    local moved = t.transferIn > 0 or t.transferOut > 0
    panel.transfers:SetText(moved and L.LEDGER_TRANSFERS:format(Util.FormatMoneyIcons(t.transferIn),
        Util.FormatMoneyIcons(t.transferOut)) or "")
    panel.note:SetText(t.since and L.LEDGER_SINCE:format(date("%d %b %Y", t.since)) or "")
end

ns.MainWindow:AddTab({ name = L.TAB_ACCOUNTING, Build = Build, Refresh = Refresh })
ns.MainWindow:RefreshOn("AC_LEDGER_CHANGED")
ns:RegisterCommand("accounting", function() ns.MainWindow:ShowTab(L.TAB_ACCOUNTING) end, L.HELP_ACCOUNTING)
