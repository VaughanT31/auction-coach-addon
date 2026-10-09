-- Auction Coach - "My Stuff" tab: the hidden treasure view.
-- Total AH value of everything sellable, per character, and the most
-- valuable items with where they are kept.

local _, ns = ...
local L, Util, Compat = ns.L, ns.Util, ns.Compat

local ROW_HEIGHT = 22
local MAX_ROWS = 200
-- Gold overview column on the right.
local GOLD_WIDTH = 170
local GOLD_MAX_CHARS = 10

local LOCATION_LABELS = {
    bags = L.WHERE_BAGS,
    bank = L.WHERE_BANK,
    reagentBank = L.WHERE_REAGENT_BANK,
    mail = L.WHERE_MAIL,
    auctions = L.WHERE_AUCTIONS,
}

local function OwnerName(owner)
    if owner == "warband" then return L.TREASURE_WARBAND end
    local name = owner:match("^[^%-]+") or owner
    local char = ns.db.characters[owner]
    local color = char and RAID_CLASS_COLORS and RAID_CLASS_COLORS[char.class]
    return color and color:WrapTextInColorCode(name) or name
end

local function WhereText(where)
    local parts = {}
    for owner, locations in pairs(where) do
        local locParts = {}
        local total = 0
        for loc, n in pairs(locations) do
            total = total + n
            table.insert(locParts, (LOCATION_LABELS[loc] or loc) .. " " .. n)
        end
        if owner == "warband" then
            table.insert(parts, OwnerName(owner) .. " " .. total)
        else
            table.sort(locParts)
            table.insert(parts, OwnerName(owner) .. " (" .. table.concat(locParts, ", ") .. ")")
        end
    end
    table.sort(parts)
    return table.concat(parts, ", ")
end

local function IconFor(key)
    local itemID = Util.ItemIDFromKey(key) or Util.PET_CAGE_ITEM_ID
    return Compat.GetItemIconByID(itemID)
end

-- ---------------------------------------------------------------------
-- Rows
-- ---------------------------------------------------------------------

local function CreateRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT")
    ns.Skin.RowBand(row)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", 2, 0)

    row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.value:SetPoint("RIGHT", -4, 0)
    row.value:SetJustifyH("RIGHT")
    row.value:SetWidth(80)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetWidth(190)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row.where = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.where:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
    row.where:SetPoint("RIGHT", row.value, "LEFT", -6, 0)
    row.where:SetJustifyH("LEFT")
    row.where:SetWordWrap(false)

    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.08)

    row:SetScript("OnEnter", function(self)
        if not self.link or not self.link:find("|Hitem:") then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(self.link)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

local function SetRow(row, item)
    local link = Util.NamedLink(item.key)
    row.link = link or item.link
    row.icon:SetTexture(IconFor(item.key))
    local name = link or ("|cff9d9d9d" .. L.ITEM_LOADING .. "|r")
    if item.count > 1 then
        name = name .. " x" .. BreakUpLargeNumbers(item.count)
    end
    row.name:SetText(name)
    row.where:SetText(WhereText(item.where))
    row.value:SetText(Util.FormatMoneyIcons(item.value))
    row:Show()
end

-- ---------------------------------------------------------------------
-- Panel
-- ---------------------------------------------------------------------

local function UpdateScanButton(panel)
    local scan = ns.FullScan
    if scan.state == "waiting" then
        panel.scanButton:SetEnabled(false)
        panel.status:SetText(L.SCAN_WAITING)
    elseif scan:IsRunning() then
        panel.scanButton:SetEnabled(false)
        panel.status:SetText(L.SCAN_PROGRESS:format(math.floor(scan.progress * 100)))
    else
        panel.scanButton:SetEnabled(Compat.IsAuctionHouseOpen() and scan:SecondsUntilAllowed() == 0)
        panel.status:SetText("")
    end
end

-- ---------------------------------------------------------------------
-- Gold overview: total gold, each character's gold (most first) and the
-- warband bank, beside the hidden treasure.
-- ---------------------------------------------------------------------

local function BuildGold(panel)
    local box = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    box:SetWidth(GOLD_WIDTH)
    box:SetPoint("TOPRIGHT", panel.scanButton, "BOTTOMRIGHT", 0, -8)
    box:SetPoint("BOTTOM", 0, 26)
    box:EnableMouse(true)
    box:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(L.GOLD_HEADER, 1, 0.82, 0)
        GameTooltip:AddLine(L.GOLD_TIP, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    box:SetScript("OnLeave", function() GameTooltip:Hide() end)

    ns.Skin.Backdrop(box, { 1, 1, 1, 0.025 }, ns.Skin.BORDER)

    box.header = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    box.header:SetPoint("TOPLEFT", 8, -8)
    box.header:SetText(L.GOLD_HEADER)

    box.totalLabel = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    box.totalLabel:SetPoint("TOPLEFT", box.header, "BOTTOMLEFT", 0, -8)
    box.totalLabel:SetText(L.GOLD_TOTAL)
    box.total = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    box.total:SetPoint("TOPLEFT", box.totalLabel, "BOTTOMLEFT", 0, -4)
    box.total:SetPoint("RIGHT", -8, 0)
    box.total:SetJustifyH("LEFT")

    local divider = box:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(1, 1, 1, 0.1)
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", box.total, "BOTTOMLEFT", 0, -8)
    divider:SetPoint("RIGHT", -8, 0)

    -- Names and amounts as two columns of lines, so the amounts line up.
    box.names = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    box.names:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -8)
    box.names:SetJustifyH("LEFT")
    box.names:SetSpacing(4)
    box.amounts = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    box.amounts:SetPoint("TOPRIGHT", divider, "BOTTOMRIGHT", 0, -8)
    box.amounts:SetJustifyH("RIGHT")
    box.amounts:SetSpacing(4)

    -- Gold over time (UI/GoldHistoryWindow.lua).
    box.history = ns.Skin.Button(box, L.GOLD_HISTORY_BUTTON, GOLD_WIDTH - 16, 20)
    box.history:SetPoint("BOTTOM", 0, 8)
    box.history:SetScript("OnClick", function() ns.GoldHistoryWindow:Toggle() end)

    panel.gold = box
end

local function RefreshGold(panel)
    local chars = {}
    local total = 0
    for key, char in pairs(ns.db.characters) do
        local gold = char.gold or 0
        total = total + gold
        if gold > 0 then chars[#chars + 1] = { key = key, gold = gold } end
    end
    table.sort(chars, function(a, b)
        if a.gold ~= b.gold then return a.gold > b.gold end
        return a.key < b.key
    end)

    local names, amounts = {}, {}
    for i = 1, math.min(#chars, GOLD_MAX_CHARS) do
        names[#names + 1] = OwnerName(chars[i].key)
        amounts[#amounts + 1] = Util.FormatMoneyIcons(chars[i].gold)
    end
    if #chars > GOLD_MAX_CHARS then
        local rest = 0
        for i = GOLD_MAX_CHARS + 1, #chars do rest = rest + chars[i].gold end
        names[#names + 1] = "|cff9d9d9d" .. L.GOLD_MORE:format(#chars - GOLD_MAX_CHARS) .. "|r"
        amounts[#amounts + 1] = Util.FormatMoneyIcons(rest)
    end
    local warband = ns.db.warbankGold
    if warband and warband > 0 then
        total = total + warband
        names[#names + 1] = "|cff99ccff" .. L.GOLD_WARBAND .. "|r"
        amounts[#amounts + 1] = Util.FormatMoneyIcons(warband)
    end

    local box = panel.gold
    box.total:SetText(Util.FormatMoneyIcons(total))
    box.names:SetText(table.concat(names, "\n"))
    box.amounts:SetText(table.concat(amounts, "\n"))
end

local function Build(panel)
    panel.total = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    panel.total:SetPoint("TOPLEFT", 4, -4)
    panel.total:SetJustifyH("LEFT")

    panel.scanButton = ns.Skin.Button(panel, L.SCAN_BUTTON, 90, 22)
    panel.scanButton:SetPoint("TOPRIGHT", -4, 0)
    panel.scanButton:SetScript("OnClick", function() ns.FullScan:Start(true) end)
    panel.scanButton:SetMotionScriptsWhileDisabled(true)
    panel.scanButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L.SCAN_BUTTON_TIP, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    panel.scanButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    panel.status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.status:SetPoint("RIGHT", panel.scanButton, "LEFT", -8, 0)

    BuildGold(panel)

    panel.sub = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.sub:SetPoint("TOPLEFT", panel.total, "BOTTOMLEFT", 0, -6)
    panel.sub:SetPoint("RIGHT", panel.gold, "LEFT", -10, 0)
    panel.sub:SetJustifyH("LEFT")

    -- What each character's items are worth, on hover over the total
    -- rather than as a line of its own (it crowded the top of the tab).
    local totalHover = CreateFrame("Frame", nil, panel)
    totalHover:SetAllPoints(panel.total)
    totalHover:EnableMouse(true)
    totalHover:SetScript("OnEnter", function(self)
        local owners = panel.ownerList
        if not owners or #owners == 0 then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetText(L.TREASURE_BY_OWNER, 1, 0.82, 0)
        for _, o in ipairs(owners) do
            GameTooltip:AddDoubleLine(OwnerName(o.owner), Util.FormatMoneyIcons(o.value), 1, 1, 1, 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    totalHover:SetScript("OnLeave", function() GameTooltip:Hide() end)

    panel.importButton = ns.Skin.Button(panel, L.IMPORT_BUTTON, 80, 20)
    panel.importButton:SetPoint("BOTTOMRIGHT", -4, 0)
    panel.importButton:SetScript("OnClick", function() ns.ShareWindow:ShowImport() end)

    panel.exportButton = ns.Skin.Button(panel, L.EXPORT_BUTTON, 80, 20)
    panel.exportButton:SetPoint("RIGHT", panel.importButton, "LEFT", -4, 0)
    panel.exportButton:SetScript("OnClick", function() ns.ShareWindow:ShowExport() end)

    panel.note = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.note:SetPoint("BOTTOMLEFT", 4, 4)
    panel.note:SetPoint("RIGHT", panel.exportButton, "LEFT", -8, 0)
    panel.note:SetJustifyH("LEFT")

    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", panel.sub, "BOTTOMLEFT", 0, -10)
    scroll:SetPoint("BOTTOM", 0, 26)
    scroll:SetPoint("RIGHT", panel.gold, "LEFT", -30, 0)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(self, width)
        content:SetWidth(width)
    end)
    panel.scroll = scroll
    panel.content = content
    panel.rows = {}

    panel.empty = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    panel.empty:SetPoint("TOPLEFT", scroll, "TOPLEFT", 4, -8)
    panel.empty:SetPoint("RIGHT", scroll, "RIGHT", -4, 0)
    panel.empty:SetJustifyH("LEFT")
end

local function Refresh(panel, reason)
    UpdateScanButton(panel)
    if reason == "AC_SCAN_PROGRESS" then return end

    RefreshGold(panel)
    local result = ns.Treasure:Compute()

    local numChars = 0
    for _ in pairs(ns.db.characters) do numChars = numChars + 1 end

    panel.total:SetText(L.TREASURE_TOTAL:format(Util.FormatMoneyIcons(result.total)))
    panel.sub:SetText(numChars == 1 and L.TREASURE_SUB_ONE or L.TREASURE_SUB:format(numChars))

    -- Shown on hover over the total, labelled "Items worth" so nobody reads
    -- these item values as the characters' gold.
    panel.ownerList = result.owners

    if result.unpriced > 0 and result.priced > 0 then
        panel.note:SetText(L.TREASURE_UNPRICED:format(result.unpriced))
    else
        panel.note:SetText("")
    end

    if result.priced == 0 then
        panel.empty:SetText(L.TREASURE_EMPTY_PRICES)
    elseif #result.items == 0 then
        panel.empty:SetText(L.TREASURE_EMPTY_ITEMS)
    else
        panel.empty:SetText("")
    end

    local shown = math.min(#result.items, MAX_ROWS)
    for i = 1, shown do
        local row = panel.rows[i] or CreateRow(panel.content, i)
        panel.rows[i] = row
        SetRow(row, result.items[i])
    end
    for i = shown + 1, #panel.rows do
        panel.rows[i]:Hide()
    end
    panel.content:SetHeight(math.max(1, shown * ROW_HEIGHT))
end

ns.MainWindow:AddTab({ name = L.TAB_MY_STUFF, Build = Build, Refresh = Refresh })

