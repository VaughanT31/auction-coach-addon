-- Auction Coach - "Deals" tab: items listed well below their usual price.
-- At the AH, clicking a row opens that item's listings. Buying is always
-- left to the player.

local _, ns = ...
local L, Util, Compat, Phrases = ns.L, ns.Util, ns.Compat, ns.Phrases

local ROW_HEIGHT = 22
-- Older than this, the "prices are old" hint replaces the empty message.
local OLD_AFTER = 2 * 3600

-- Column layout: x offset and width, shared by header and rows.
local COLUMNS = {
    name = { 26, 212 },
    price = { 244, 82 },
    usual = { 330, 82 },
    profit = { 416, 82 },
    speed = { 502, 52 },
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
    local deal = row.deal
    if not deal then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    local link = Util.NamedLink(deal.key)
    if link and link:find("item:") then
        GameTooltip:SetHyperlink(link)
    else
        GameTooltip:SetText(link or deal.key)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L.ADDON_TITLE, 1, 0.82, 0)
    for _, line in ipairs(Phrases.Deal(deal)) do
        GameTooltip:AddLine(line, 1, 1, 1, true)
    end
    if Compat.IsAuctionHouseOpen() then
        GameTooltip:AddLine(L.DEALS_SUB_AH, 0.6, 0.8, 1, true)
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
    row.price = Column(row, "price", "GameFontHighlight", "RIGHT")
    row.usual = Column(row, "usual", "GameFontHighlight", "RIGHT")
    row.profit = Column(row, "profit", "GameFontHighlight", "RIGHT")
    row.speed = Column(row, "speed", "GameFontHighlightSmall", "RIGHT")

    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.08)

    row:SetScript("OnEnter", ShowRowTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self)
        local deal = self.deal
        if deal and Compat.ShowAtAuctionHouse(deal.key, Util.NamedLink(deal.key), deal.price) then
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        end
    end)
    return row
end

local function SetRow(row, deal)
    row.deal = deal
    local itemID = Util.ItemIDFromKey(deal.key) or Util.PET_CAGE_ITEM_ID
    row.icon:SetTexture(Compat.GetItemIconByID(itemID))

    row.name:SetText(Util.NamedLink(deal.key) or ("|cff9d9d9d" .. L.ITEM_LOADING .. "|r"))
    row.price:SetText(Util.FormatMoneyIcons(deal.price))
    row.usual:SetText(Util.FormatMoneyIcons(deal.resell))
    row.profit:SetText("|cff66ff66" .. Util.FormatMoneyIcons(deal.profit) .. "|r")
    row.speed:SetText(BreakUpLargeNumbers(math.floor(deal.salesPerDay + 0.5)))
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
        name = L.SELL_COL_ITEM, price = L.DEALS_COL_PRICE, usual = L.DEALS_COL_USUAL,
        profit = L.DEALS_COL_PROFIT, speed = L.SELL_COL_SPEED,
    }) do
        Column(header, col, "GameFontNormalSmall", col == "name" and "LEFT" or "RIGHT"):SetText(label)
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

local function EmptyText(list)
    if not list.hasData then return L.DEALS_NEED_APP end
    if not list.newest then return L.DEALS_NO_PRICES end
    if not list.hasHistory then return L.DEALS_NEED_HISTORY end
    if Util.Now() - list.newest > OLD_AFTER then
        return L.DEALS_OLD:format(Util.FormatAge(list.newest))
    end
    return L.DEALS_EMPTY
end

local function Refresh(panel, reason)
    if reason == "AC_SCAN_PROGRESS" then return end
    if ns.Deals:IsStale() then ns.Deals:Invalidate() end
    local list = ns.Deals:List()
    local minDiscount, minProfit = ns.db.settings.dealMinDiscount, ns.db.settings.dealMinProfit

    panel.title:SetText(L.DEALS_TITLE:format(#list.items))
    panel.sub:SetText(L.DEALS_SUB:format(math.floor(minDiscount * 100 + 0.5), Util.FormatMoneyIcons(minProfit))
        .. (Compat.IsAuctionHouseOpen() and (" " .. L.DEALS_SUB_AH) or ""))
    panel.empty:SetText(#list.items == 0 and EmptyText(list) or "")

    for i, deal in ipairs(list.items) do
        local row = panel.rows[i] or CreateRow(panel.content, i)
        panel.rows[i] = row
        SetRow(row, deal)
    end
    for i = #list.items + 1, #panel.rows do
        panel.rows[i]:Hide()
    end
    panel.content:SetHeight(math.max(1, #list.items * ROW_HEIGHT))
end

ns.MainWindow:AddTab({ name = L.TAB_DEALS, Build = Build, Refresh = Refresh })
ns.MainWindow:RefreshOn("AC_LIVE_PRICE")
