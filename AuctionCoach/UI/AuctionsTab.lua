-- Auction Coach - "Auctions" tab: the player's own listings and what to do
-- with each (Advice/Auctions.lua): keep, repost, cancel or let it run.
-- At the AH, clicking a row opens that item's listings. Cancelling stays a
-- manual step in Blizzard's Auctions tab (no automated cancelling).

local _, ns = ...
local L, Util, Compat = ns.L, ns.Util, ns.Compat

local ROW_HEIGHT = 24

-- Column layout: x offset and width, shared by header and rows.
local COLUMNS = {
    name = { 24, 200 },
    yours = { 230, 86 },
    lowest = { 322, 86 },
    advice = { 420, 160 },
}

local ACTION_COLORS = {
    KEEP = { 0.4, 1, 0.4 },
    REPOST = { 1, 0.82, 0 },
    CANCEL = { 1, 0.5, 0.35 },
    WAIT = { 0.7, 0.7, 0.7 },
    UNKNOWN = { 0.55, 0.55, 0.55 },
}

local function Column(parent, name, template, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", template)
    fs:SetPoint("LEFT", COLUMNS[name][1], 0)
    fs:SetWidth(COLUMNS[name][2])
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

local function AdviceText(entry)
    if entry.action == "REPOST" then
        return L.AUCTIONS_REPOST:format(Util.FormatMoneyIcons(entry.newPrice))
    end
    return L["AUCTIONS_" .. entry.action]
end

local function WhyText(entry)
    local money = Util.FormatMoney
    local action = entry.action
    if action == "REPOST" then
        return L.AUCTIONS_WHY_REPOST:format(money(entry.lowest), money(entry.newPrice))
    elseif action == "CANCEL" then
        return L.AUCTIONS_WHY_CANCEL:format(money(entry.vendorGold))
    elseif action == "WAIT" then
        local s = entry.suggestion
        if s.action == "HOLD" and s.usual and s.lowest then
            return L.AUCTIONS_WHY_WAIT_HOLD:format(math.floor((1 - s.lowest / s.usual) * 100 + 0.5))
        end
        return L.AUCTIONS_WHY_WAIT_CONTESTED
    end
    return L["AUCTIONS_WHY_" .. action]
end

local function ShowRowTooltip(row)
    local entry = row.entry
    if not entry then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    local link = Util.NamedLink(entry.key)
    if link and link:find("item:") then
        GameTooltip:SetHyperlink(link)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L.ADDON_TITLE, 1, 0.82, 0)
    else
        GameTooltip:SetText(L.ADDON_TITLE, 1, 0.82, 0)
    end
    GameTooltip:AddLine(WhyText(entry), 1, 1, 1, true)
    if entry.lowestAt then
        GameTooltip:AddLine(L.AUCTIONS_LOWEST_AGE:format(Util.FormatAge(entry.lowestAt)), 0.75, 0.75, 0.75)
    end
    if entry.auctions > 1 then
        GameTooltip:AddLine(L.AUCTIONS_COUNT:format(entry.auctions), 0.75, 0.75, 0.75)
    end
    local left = ns.Auctions.FormatLeft(entry.left)
    if left then GameTooltip:AddLine(L.AUCTIONS_TIME_LEFT:format(left), 0.75, 0.75, 0.75) end
    GameTooltip:AddLine(L.AUCTIONS_LISTED_VALUE:format(Util.FormatMoney(ns.Auctions.ListedValue(entry))), 0.75, 0.75, 0.75)
    GameTooltip:Show()
end

local function CreateRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT")
    ns.Skin.RowBand(row)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", 2, 0)
    row.name = Column(row, "name", "GameFontHighlight")
    row.yours = Column(row, "yours", "GameFontHighlight", "RIGHT")
    row.lowest = Column(row, "lowest", "GameFontHighlight", "RIGHT")
    row.advice = Column(row, "advice", "GameFontHighlightSmall")

    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.08)

    row:SetScript("OnEnter", ShowRowTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self)
        local entry = self.entry
        if entry and Compat.ShowAtAuctionHouse(entry.key, Util.NamedLink(entry.key), entry.lowest) then
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        end
    end)
    return row
end

local function SetRow(row, entry)
    row.entry = entry
    local itemID = Util.ItemIDFromKey(entry.key) or Util.PET_CAGE_ITEM_ID
    row.icon:SetTexture(Compat.GetItemIconByID(itemID))
    local name = Util.NamedLink(entry.key) or ("|cff9d9d9d" .. L.ITEM_LOADING .. "|r")
    if entry.quantity > 1 then name = name .. " x" .. BreakUpLargeNumbers(entry.quantity) end
    row.name:SetText(name)
    row.yours:SetText(Util.FormatMoneyIcons(entry.unit))

    if entry.lowest then
        local cheaper = entry.lowest < entry.unit
        row.lowest:SetText((cheaper and "|cffff7f50" or "") .. Util.FormatMoneyIcons(entry.lowest) .. (cheaper and "|r" or ""))
    else
        row.lowest:SetText("|cff9d9d9d-|r")
    end

    local color = ACTION_COLORS[entry.action]
    row.advice:SetText(AdviceText(entry))
    row.advice:SetTextColor(color[1], color[2], color[3])
    row:Show()
end

local function Build(panel)
    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    panel.title:SetPoint("TOPLEFT", 4, -4)
    panel.title:SetPoint("RIGHT", -4, 0)
    panel.title:SetJustifyH("LEFT")

    panel.sub = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.sub:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -8)
    panel.sub:SetPoint("RIGHT", -4, 0)
    panel.sub:SetJustifyH("LEFT")

    local header = CreateFrame("Frame", nil, panel)
    header:SetHeight(18)
    header:SetPoint("TOPLEFT", panel.sub, "BOTTOMLEFT", 0, -10)
    header:SetPoint("RIGHT", -26, 0)
    for name, key in pairs({ name = "ITEM", yours = "YOURS", lowest = "LOWEST", advice = "ADVICE" }) do
        local justify = (name == "yours" or name == "lowest") and "RIGHT" or "LEFT"
        Column(header, name, "GameFontNormalSmall", justify):SetText(L["AUCTIONS_HEAD_" .. key])
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
    local list = ns.Auctions:List()

    if #list.items > 0 then
        panel.title:SetText(L.AUCTIONS_TITLE:format(#list.items, list.undercut))
    else
        panel.title:SetText(L.AUCTIONS_TITLE_NONE)
    end
    panel.sub:SetText(list.at and L.AUCTIONS_SUB:format(Util.FormatAge(list.at)) or L.AUCTIONS_SUB_NEVER)
    panel.empty:SetText((list.at and #list.items == 0) and L.AUCTIONS_EMPTY or "")

    for i, entry in ipairs(list.items) do
        local row = panel.rows[i] or CreateRow(panel.content, i)
        panel.rows[i] = row
        SetRow(row, entry)
    end
    for i = #list.items + 1, #panel.rows do
        panel.rows[i]:Hide()
    end
    panel.content:SetHeight(math.max(1, #list.items * ROW_HEIGHT))
end

ns.MainWindow:AddTab({ name = L.TAB_AUCTIONS, Build = Build, Refresh = Refresh })
ns.MainWindow:RefreshOn("AC_LIVE_PRICE")
ns.MainWindow:RefreshOn("OWNED_AUCTIONS_UPDATED")

ns:RegisterCommand("auctions", function() ns.MainWindow:ShowTab(L.TAB_AUCTIONS) end, L.HELP_AUCTIONS)
