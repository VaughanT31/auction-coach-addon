-- Auction Coach - "My Stuff" tab: the hidden treasure view.
-- Total AH value of everything sellable, per character, and the most
-- valuable items with where they are kept.

local _, ns = ...
local L, Util, Compat = ns.L, ns.Util, ns.Compat

local ROW_HEIGHT = 22
local MAX_ROWS = 200

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

local function Build(panel)
    panel.total = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    panel.total:SetPoint("TOPLEFT", 4, -4)
    panel.total:SetJustifyH("LEFT")

    panel.scanButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.scanButton:SetSize(90, 22)
    panel.scanButton:SetPoint("TOPRIGHT", -4, 0)
    panel.scanButton:SetText(L.SCAN_BUTTON)
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

    panel.sub = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.sub:SetPoint("TOPLEFT", panel.total, "BOTTOMLEFT", 0, -6)
    panel.sub:SetPoint("RIGHT", -4, 0)
    panel.sub:SetJustifyH("LEFT")

    panel.owners = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    panel.owners:SetPoint("TOPLEFT", panel.sub, "BOTTOMLEFT", 0, -8)
    panel.owners:SetPoint("RIGHT", -4, 0)
    panel.owners:SetJustifyH("LEFT")

    panel.importButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.importButton:SetSize(80, 20)
    panel.importButton:SetPoint("BOTTOMRIGHT", -4, 0)
    panel.importButton:SetText(L.IMPORT_BUTTON)
    panel.importButton:SetScript("OnClick", function() ns.ShareWindow:ShowImport() end)

    panel.exportButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.exportButton:SetSize(80, 20)
    panel.exportButton:SetPoint("RIGHT", panel.importButton, "LEFT", -4, 0)
    panel.exportButton:SetText(L.EXPORT_BUTTON)
    panel.exportButton:SetScript("OnClick", function() ns.ShareWindow:ShowExport() end)

    panel.note = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.note:SetPoint("BOTTOMLEFT", 4, 4)
    panel.note:SetPoint("RIGHT", panel.exportButton, "LEFT", -8, 0)
    panel.note:SetJustifyH("LEFT")

    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", panel.owners, "BOTTOMLEFT", 0, -10)
    scroll:SetPoint("BOTTOMRIGHT", -26, 26)
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
    panel.empty:SetPoint("RIGHT", -30, 0)
    panel.empty:SetJustifyH("LEFT")
end

local function Refresh(panel, reason)
    UpdateScanButton(panel)
    if reason == "AC_SCAN_PROGRESS" then return end

    local result = ns.Treasure:Compute()

    local numChars = 0
    for _ in pairs(ns.db.characters) do numChars = numChars + 1 end

    panel.total:SetText(L.TREASURE_TOTAL:format(Util.FormatMoneyIcons(result.total)))
    panel.sub:SetText(numChars == 1 and L.TREASURE_SUB_ONE or L.TREASURE_SUB:format(numChars))

    local ownerParts = {}
    for _, o in ipairs(result.owners) do
        table.insert(ownerParts, OwnerName(o.owner) .. " " .. Util.FormatMoneyIcons(o.value))
    end
    -- Labelled, so nobody reads these item values as the characters' gold.
    panel.owners:SetText(#ownerParts > 0 and ("|cffffd100" .. L.TREASURE_BY_OWNER .. "|r  " .. table.concat(ownerParts, "   ")) or "")

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

