-- Auction Coach - "Sell" tab: what to sell from this character's bags,
-- with a suggested price for each. At the AH, clicking a row puts the item
-- into the sell box; the post helper then offers the price.

local _, ns = ...
local L, Util, Compat, Phrases = ns.L, ns.Util, ns.Compat, ns.Phrases

local ROW_HEIGHT = 22
local MAX_ROWS = 150

-- Column layout: x offset and width, shared by header and rows.
local COLUMNS = {
    name = { 26, 190 },
    each = { 222, 82 },
    total = { 308, 82 },
    speed = { 394, 52 },
    advice = { 452, 92 },
}

local ADVICE_COLORS = {
    CONTESTED = { 1, 0.82, 0 },
    POST = { 0.4, 1, 0.4 },
    HOLD = { 1, 0.65, 0.2 },
    VENDOR = { 0.7, 0.7, 0.7 },
    NO_DATA = { 0.5, 0.5, 0.5 },
}

local function Column(parent, name, template, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", template)
    fs:SetPoint("LEFT", COLUMNS[name][1], 0)
    fs:SetWidth(COLUMNS[name][2])
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

local function ShowRowTooltip(row)
    local item = row.item
    if not item then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    local link = Util.NamedLink(item.key) or item.link
    if link and link:find("|Hitem:") then
        GameTooltip:SetHyperlink(link)
    else
        GameTooltip:SetText(item.key)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L.ADDON_TITLE, 1, 0.82, 0)
    for _, line in ipairs(Phrases.Sell(item.suggestion)) do
        GameTooltip:AddLine(line, 1, 1, 1, true)
    end
    if Compat.IsAuctionHouseOpen() then
        GameTooltip:AddLine(L.SELL_SUB_AH, 0.6, 0.8, 1, true)
    end
    GameTooltip:Show()
end

local function CreateRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT")

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", 2, 0)

    row.name = Column(row, "name", "GameFontHighlight")
    row.each = Column(row, "each", "GameFontHighlight", "RIGHT")
    row.total = Column(row, "total", "GameFontHighlight", "RIGHT")
    row.speed = Column(row, "speed", "GameFontHighlightSmall", "RIGHT")
    row.advice = Column(row, "advice", "GameFontHighlightSmall")

    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.08)

    row:SetScript("OnEnter", ShowRowTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self)
        if self.item and ns.Sell:PutInSellBox(self.item.key) then
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        end
    end)
    return row
end

local function SetRow(row, item)
    local s = item.suggestion
    row.item = item
    local itemID = Util.ItemIDFromKey(item.key) or Util.PET_CAGE_ITEM_ID
    row.icon:SetTexture(Compat.GetItemIconByID(itemID))

    local link = Util.NamedLink(item.key)
    local name = link or ("|cff9d9d9d" .. L.ITEM_LOADING .. "|r")
    if item.count > 1 then name = name .. " x" .. item.count end
    row.name:SetText(name)

    row.each:SetText(s.price and Util.FormatMoneyIcons(s.price) or "")
    row.total:SetText(item.value > 0 and Util.FormatMoneyIcons(item.value) or "")
    if s.salesPerDay then
        row.speed:SetText(s.salesPerDay < 1 and "<1" or BreakUpLargeNumbers(math.floor(s.salesPerDay + 0.5)))
    else
        row.speed:SetText("")
    end
    local c = (s.action == "POST" and s.contested and s.contested ~= "NONE") and ADVICE_COLORS.CONTESTED
        or ADVICE_COLORS[s.action]
    row.advice:SetText(Phrases.SellShort(s))
    row.advice:SetTextColor(c[1], c[2], c[3])
    row:Show()
end

local function Build(panel)
    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    panel.title:SetPoint("TOPLEFT", 4, -4)

    panel.sub = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.sub:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -6)
    panel.sub:SetPoint("RIGHT", -4, 0)
    panel.sub:SetJustifyH("LEFT")

    local header = CreateFrame("Frame", nil, panel)
    header:SetHeight(18)
    header:SetPoint("TOPLEFT", panel.sub, "BOTTOMLEFT", 0, -10)
    header:SetPoint("RIGHT", -26, 0)
    for col, label in pairs({
        name = L.SELL_COL_ITEM, each = L.SELL_COL_EACH, total = L.SELL_COL_TOTAL,
        speed = L.SELL_COL_SPEED, advice = L.SELL_COL_ADVICE,
    }) do
        local justify = (col == "each" or col == "total" or col == "speed") and "RIGHT" or "LEFT"
        Column(header, col, "GameFontNormalSmall", justify):SetText(label)
    end

    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", -26, 4)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(_, width) content:SetWidth(width) end)
    panel.content = content
    panel.rows = {}

    panel.empty = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    panel.empty:SetPoint("TOPLEFT", scroll, "TOPLEFT", 4, -8)
    panel.empty:SetPoint("RIGHT", -30, 0)
    panel.empty:SetJustifyH("LEFT")
end

local function Refresh(panel, reason)
    if reason == "AC_SCAN_PROGRESS" then return end
    local list = ns.Sell:List()

    panel.title:SetText(L.SELL_TITLE:format(Util.FormatMoneyIcons(list.total)))
    panel.sub:SetText(L.SELL_SUB .. (Compat.IsAuctionHouseOpen() and (" " .. L.SELL_SUB_AH) or ""))
    panel.empty:SetText(#list.items == 0 and L.SELL_EMPTY or "")

    local shown = math.min(#list.items, MAX_ROWS)
    for i = 1, shown do
        local row = panel.rows[i] or CreateRow(panel.content, i)
        panel.rows[i] = row
        SetRow(row, list.items[i])
    end
    for i = shown + 1, #panel.rows do
        panel.rows[i]:Hide()
    end
    panel.content:SetHeight(math.max(1, shown * ROW_HEIGHT))
end

ns.MainWindow:AddTab({ name = L.TAB_SELL, Build = Build, Refresh = Refresh })
ns.MainWindow:RefreshOn("AC_LIVE_PRICE")
