-- Auction Coach - gold history window (/ac gold, or History on My Stuff):
-- how the account's gold has changed today, this week and this month,
-- and a day-by-day list with AH sales and purchases (Data/GoldHistory.lua).

local _, ns = ...
local L, Util = ns.L, ns.Util

local GoldHistoryWindow = {}
ns.GoldHistoryWindow = GoldHistoryWindow

local WIDTH, HEIGHT = 520, 470
local DAYS = 30
local ROW_HEIGHT = 20
local TILE_HEIGHT = 64

local COLUMNS = {
    date = { 6, 96 },
    total = { 106, 100 },
    change = { 210, 90 },
    sales = { 304, 90 },
    bought = { 398, 90 },
}

local frame

local function Column(parent, name, template, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", template)
    fs:SetPoint("LEFT", COLUMNS[name][1], 0)
    fs:SetWidth(COLUMNS[name][2])
    fs:SetJustifyH(justify or "RIGHT")
    fs:SetWordWrap(false)
    return fs
end

-- "+1,250g" in green, "-300g" in red, "-" when unknown.
local function Signed(copper)
    if not copper then return "|cff9d9d9d-|r" end
    if copper == 0 then return "|cffcccccc0|r" end
    local text = Util.FormatMoneyIcons(math.abs(copper))
    if copper > 0 then return "|cff66ff66+" .. text .. "|r" end
    return "|cffff6666-" .. text .. "|r"
end

local function DayLabel(key)
    if key == ns.GoldHistory.DayKey() then return L.GOLDHIST_TODAY end
    local y, m, d = key:match("^(%d+)-(%d+)-(%d+)$")
    local t = time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
    return date("%a %d %b", t)
end

local function CreateTile(parent, index, label)
    local tile = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    tile:SetSize((WIDTH - 32 - 16) / 3, TILE_HEIGHT)
    tile:SetPoint("TOPLEFT", 16 + (index - 1) * ((WIDTH - 32 - 16) / 3 + 8), -44)
    ns.Skin.Backdrop(tile, { 1, 1, 1, 0.025 }, ns.Skin.BORDER)
    tile.label = tile:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tile.label:SetPoint("TOPLEFT", 8, -8)
    tile.label:SetText(label)
    tile.change = tile:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    tile.change:SetPoint("TOPLEFT", tile.label, "BOTTOMLEFT", 0, -6)
    tile.sales = tile:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tile.sales:SetPoint("TOPLEFT", tile.change, "BOTTOMLEFT", 0, -4)
    tile.sales:SetPoint("RIGHT", -6, 0)
    tile.sales:SetJustifyH("LEFT")
    tile.sales:SetWordWrap(false)
    return tile
end

-- Mouseover on a day: each character's gold and the warband bank's that day.
local function ShowDayTooltip(row)
    local day = row.day
    if not day then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(DayLabel(day.key), 1, 0.82, 0)
    local saved = day.day
    if not saved or not saved.chars or not next(saved.chars) then
        GameTooltip:AddLine(L.GOLDHIST_NO_SNAPSHOT, 0.8, 0.8, 0.8, true)
    else
        local chars = {}
        for charKey, gold in pairs(saved.chars) do chars[#chars + 1] = { charKey, gold } end
        table.sort(chars, function(a, b) return a[2] > b[2] end)
        for _, c in ipairs(chars) do
            GameTooltip:AddDoubleLine(c[1], Util.FormatMoneyIcons(c[2]), 1, 1, 1, 1, 1, 1)
        end
        if (saved.warband or 0) > 0 then
            GameTooltip:AddDoubleLine(L.GOLDHIST_WARBAND, Util.FormatMoneyIcons(saved.warband), 0.6, 0.8, 1, 1, 1, 1)
        end
    end
    GameTooltip:Show()
end

local function CreateRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT")
    ns.Skin.RowBand(row)
    row.date = Column(row, "date", "GameFontHighlightSmall", "LEFT")
    row.total = Column(row, "total", "GameFontHighlightSmall")
    row.change = Column(row, "change", "GameFontHighlightSmall")
    row.sales = Column(row, "sales", "GameFontHighlightSmall")
    row.bought = Column(row, "bought", "GameFontHighlightSmall")
    row:EnableMouse(true)
    row:SetScript("OnEnter", ShowDayTooltip)
    row:SetScript("OnLeave", GameTooltip_Hide)
    return row
end

local function Create()
    frame = ns.Skin.Window("AuctionCoachGoldHistory", WIDTH, HEIGHT, "DIALOG")
    frame:SetPoint("CENTER", 60, 0)
    frame.title:SetText(L.GOLDHIST_TITLE)

    frame.tiles = {
        CreateTile(frame, 1, L.GOLDHIST_TILE_TODAY),
        CreateTile(frame, 2, L.GOLDHIST_TILE_WEEK),
        CreateTile(frame, 3, L.GOLDHIST_TILE_MONTH),
    }

    local header = CreateFrame("Frame", nil, frame)
    header:SetHeight(18)
    header:SetPoint("TOPLEFT", 16, -44 - TILE_HEIGHT - 14)
    header:SetPoint("RIGHT", -40, 0)
    for col, key in pairs({ date = "GOLDHIST_COL_DATE", total = "GOLDHIST_COL_TOTAL", change = "GOLDHIST_COL_CHANGE",
        sales = "GOLDHIST_COL_SALES", bought = "GOLDHIST_COL_BOUGHT" }) do
        Column(header, col, "GameFontNormalSmall", col == "date" and "LEFT" or "RIGHT"):SetText(L[key])
    end

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", -40, 62)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(_, width) content:SetWidth(width) end)
    frame.content = content
    frame.rows = {}

    frame.note = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.note:SetPoint("BOTTOMLEFT", 16, 14)
    frame.note:SetPoint("RIGHT", -16, 0)
    frame.note:SetJustifyH("LEFT")
    frame.note:SetText(L.GOLDHIST_NOTE)

    -- AH gold still sitting in mailboxes isn't counted until it's collected.
    frame.mailNote = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.mailNote:SetPoint("BOTTOMLEFT", 16, 44)
    frame.mailNote:SetPoint("RIGHT", -16, 0)
    frame.mailNote:SetJustifyH("LEFT")
    frame.mailNote:SetTextColor(1, 0.75, 0.3)

    frame:HookScript("OnShow", function() GoldHistoryWindow:Refresh() end)
end

function GoldHistoryWindow:Refresh()
    if not frame or not frame:IsShown() then return end
    local GH = ns.GoldHistory
    for i, n in ipairs({ 1, 7, 30 }) do
        local s = GH:Summary(n)
        local tile = frame.tiles[i]
        tile.change:SetText(Signed(s.change))
        tile.sales:SetText(L.GOLDHIST_TILE_SALES:format(Util.FormatMoneyIcons(s.sales)))
    end

    local recent = GH:Recent(DAYS)
    for i, day in ipairs(recent) do
        local row = frame.rows[i] or CreateRow(frame.content, i)
        frame.rows[i] = row
        row.day = day
        row.date:SetText(DayLabel(day.key))
        row.total:SetText(day.total and Util.FormatMoneyIcons(day.total) or "|cff9d9d9d-|r")
        row.change:SetText(Signed(day.change))
        row.sales:SetText(day.sales > 0 and (Util.FormatMoneyIcons(day.sales) .. " |cff9d9d9d(" .. day.sold .. ")|r") or "|cff9d9d9d-|r")
        row.bought:SetText(day.bought > 0 and (Util.FormatMoneyIcons(day.bought) .. " |cff9d9d9d(" .. day.boughtItems .. ")|r") or "|cff9d9d9d-|r")
        row:Show()
    end
    frame.content:SetHeight(#recent * ROW_HEIGHT)

    local waiting, chars = 0, 0
    for _, char in pairs(ns.db.characters) do
        if (char.mailGold or 0) > 0 then
            waiting = waiting + char.mailGold
            chars = chars + 1
        end
    end
    frame.mailNote:SetText(waiting > 0 and L.GOLDHIST_MAIL_WAITING:format(Util.FormatMoneyIcons(waiting), chars) or "")
end

function GoldHistoryWindow:Toggle()
    if not ns.db then return end
    if not frame then Create() end
    frame:SetShown(not frame:IsShown())
end

for _, event in ipairs({ "AC_GOLD_HISTORY_CHANGED", "AC_INVENTORY_CHANGED" }) do
    ns.Events:On(event, function()
        Util.Debounce("goldHistoryWindow", 2.5, function() GoldHistoryWindow:Refresh() end)
    end)
end

ns:RegisterCommand("gold", function() GoldHistoryWindow:Toggle() end, L.HELP_GOLD)
