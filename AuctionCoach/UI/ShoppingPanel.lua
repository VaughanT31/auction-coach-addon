-- Auction Coach - the shopping list beside the Auction House.
-- Opens by itself when the AH opens and the list has items (unless turned
-- off in the options), so the list is in front of the player while they
-- shop instead of a chat line. Items are grouped by who added them (you,
-- Patron Planner, a craft), items listed at or under the max first in each.
--
--  +-- Shopping list: 3 items, 1 to buy now -------- [Add] [x] -+
--  |  Item                     Need   Lowest    Max     Status   |
--  |  Added by you                                      Clear    |
--  |  [i] Sunfire Silk          12    9g 80s    11g    Buy now   |
--  |  Patron Planner                                    Clear    |
--  |  [i] Bright Linen          40    1g 20s     1g   Too high   |
--  |  Right-click an item for more. Alt-click any item to add.   |
--  +-------------------------------------------------------------+
--
-- Click an item to search for it (with the count filled in), right-click
-- for search, edit, remove and remove group (UI/ShoppingEditor.lua). The
-- mouse wheel scrolls a long list. When the post helper is open (selling),
-- this sits under it.

local _, ns = ...
local L, Util, Compat = ns.L, ns.Util, ns.Compat

local ShoppingPanel = {}
ns.ShoppingPanel = ShoppingPanel

local WIDTH = 380
local ROW = 20
local LINES = 16
local TOP = -52                     -- first line, under the column headings

-- Columns from the right edge: { right offset, width }.
local COL = {
    status = { -4, 58 },
    max = { -66, 58 },
    lowest = { -128, 62 },
    need = { -194, 34 },
}

local STATUS_COLORS = {
    BUY = "|cff66ff66",
    WAIT = "|cffcccccc",
    OLD = "|cffffaa33",
    UNKNOWN = "|cff9d9d9d",
}

local panel, rows
local lines = {}                    -- what's drawn: { header = group } or { item = item }
local offset = 0
local closedThisVisit = false

local function Enabled()
    return ns.db and ns.db.settings.shoppingPanel ~= false
end

local function Cell(row, col, font)
    local fs = row:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    fs:SetPoint("RIGHT", row, "RIGHT", COL[col][1], 0)
    fs:SetWidth(COL[col][2])
    fs:SetJustifyH("RIGHT")
    fs:SetWordWrap(false)
    return fs
end

local function ShowItemTooltip(row, item)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    local link = Util.NamedLink(item.key)
    if link and link:find("item:") then GameTooltip:SetHyperlink(link) else GameTooltip:SetText(link or item.key) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L.ADDON_TITLE, 1, 0.82, 0)
    for _, line in ipairs(ns.Phrases.Shop(item)) do GameTooltip:AddLine(line, 1, 1, 1, true) end
    GameTooltip:AddLine(L.SHOP_PANEL_CLICK, 0.6, 0.8, 1, true)
    GameTooltip:AddLine(L.SHOP_MENU_TIP, 0.6, 0.8, 1, true)
    GameTooltip:Show()
end

local function CreateRow(index)
    local row = CreateFrame("Button", nil, panel)
    row:SetHeight(ROW)
    row:SetPoint("TOPLEFT", 8, TOP - (index - 1) * ROW)
    row:SetPoint("RIGHT", -8, 0)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.band = ns.Skin.RowBand(row)
    row:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
    row:GetHighlightTexture():SetVertexColor(1, 0.82, 0.15, 0.08)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("LEFT", 2, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.status = Cell(row, "status")
    row.max = Cell(row, "max")
    row.lowest = Cell(row, "lowest")
    row.need = Cell(row, "need")
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
    row.name:SetPoint("RIGHT", row.need, "LEFT", -6, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    -- Group header: the source's name and a Clear button.
    row.group = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.group:SetPoint("LEFT", 2, 0)
    row.group:SetPoint("RIGHT", -70, 0)
    row.group:SetJustifyH("LEFT")
    row.clear = ns.Skin.Button(row, L.SHOP_GROUP_CLEAR, 56, 16)
    row.clear:SetPoint("RIGHT", -2, 0)
    row.clear:SetScript("OnClick", function()
        local group = row.line and row.line.header
        if group then ns.Shopping:RemoveGroup(group.note) end
    end)

    row:SetScript("OnClick", function(self, mouse)
        local item = self.line and self.line.item
        if not item then return end
        if mouse == "RightButton" then
            GameTooltip:Hide()
            ns.ShoppingEditor:RowMenu(self, item)
        else
            Compat.ShowAtAuctionHouse(item.key, Util.NamedLink(item.key), item.lowest, item.need)
        end
    end)
    row:SetScript("OnEnter", function(self)
        local item = self.line and self.line.item
        if item then ShowItemTooltip(self, item) end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

local function Create()
    panel = CreateFrame("Frame", "AuctionCoachShoppingPanel", AuctionHouseFrame, "BackdropTemplate")
    panel:SetWidth(WIDTH)
    ns.Skin.Backdrop(panel, ns.Skin.BG, { 0.88, 0.65, 0.15, 0.9 })
    panel:EnableMouse(true)
    panel:EnableMouseWheel(true)
    panel:SetScript("OnMouseWheel", function(_, delta)
        local most = math.max(0, #lines - LINES)
        local new = math.min(most, math.max(0, offset - delta * 3))
        if new ~= offset then
            offset = new
            ShoppingPanel:Draw()
        end
    end)

    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.title:SetPoint("TOPLEFT", 12, -12)
    panel.title:SetPoint("RIGHT", -96, 0)
    panel.title:SetJustifyH("LEFT")
    panel.title:SetWordWrap(false)

    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButtonNoScripts")
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", -3, -3)
    close:SetScript("OnClick", function()
        closedThisVisit = true
        panel:Hide()
    end)

    local add = ns.Skin.Button(panel, L.SHOP_PANEL_ADD, 60, 18)
    add:SetPoint("RIGHT", close, "LEFT", -4, 0)
    add:SetScript("OnClick", function() ns.ShoppingEditor:AddNew() end)
    add:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L.SHOP_PANEL_ADD)
        GameTooltip:AddLine(L.SHOP_PANEL_ADD_TIP, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    add:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Column headings, lined up with the cells.
    local heads = CreateFrame("Frame", nil, panel)
    heads:SetHeight(16)
    heads:SetPoint("TOPLEFT", 8, -34)
    heads:SetPoint("RIGHT", -8, 0)
    local function Head(text, col)
        local fs = heads:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        if col then
            fs:SetPoint("RIGHT", heads, "RIGHT", COL[col][1], 0)
            fs:SetWidth(COL[col][2])
            fs:SetJustifyH("RIGHT")
        else
            fs:SetPoint("LEFT", 2, 0)
        end
        fs:SetText(text)
    end
    Head(L.SHOP_COL_ITEM)
    Head(L.SHOP_COL_NEED, "need")
    Head(L.SHOP_COL_LOWEST_SHORT, "lowest")
    Head(L.SHOP_COL_MAX_SHORT, "max")
    Head(L.SHOP_COL_STATUS, "status")

    panel.footer = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.footer:SetPoint("BOTTOMLEFT", 12, 9)
    panel.footer:SetPoint("RIGHT", -12, 0)
    panel.footer:SetJustifyH("LEFT")

    rows = {}
    for i = 1, LINES do rows[i] = CreateRow(i) end
    panel:Hide()
end

-- Under the post helper while that's open (PostHelper calls this when it
-- shows or hides), otherwise beside the AH.
function ShoppingPanel:Place()
    if not panel then return end
    panel:ClearAllPoints()
    local helper = _G.AuctionCoachPostHelper
    if helper and helper:IsShown() then
        panel:SetPoint("TOPLEFT", helper, "BOTTOMLEFT", 0, -6)
    else
        panel:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 4, -24)
    end
end

function ShoppingPanel:IsShown()
    return panel ~= nil and panel:IsShown()
end

local function SetItem(row, item)
    row.icon:Show()
    row.group:Hide()
    row.clear:Hide()
    row.band:Show()
    local itemID = Util.ItemIDFromKey(item.key) or Util.PET_CAGE_ITEM_ID
    row.icon:SetTexture(Compat.GetItemIconByID(itemID))
    row.name:SetText(Util.NamedLink(item.key) or ("|cff9d9d9d" .. L.ITEM_LOADING .. "|r"))
    row.need:SetText(item.need and tostring(item.need) or "|cff9d9d9d-|r")
    row.lowest:SetText(item.lowest and Util.FormatMoneyIcons(item.lowest) or "|cff9d9d9d-|r")
    row.max:SetText(Util.FormatMoneyIcons(item.max))
    row.status:SetText(STATUS_COLORS[item.status] .. L["SHOP_STATUS_" .. item.status] .. "|r")
end

local function SetHeader(row, group)
    row.icon:Hide()
    row.band:Hide()
    for _, fs in ipairs({ row.name, row.need, row.lowest, row.max, row.status }) do fs:SetText("") end
    row.group:Show()
    row.clear:Show()
    row.group:SetText(L.SHOP_GROUP_HEADER:format(ns.ShoppingEditor.GroupName(group.note), #group.items))
end

-- Draws the lines from the scroll offset.
function ShoppingPanel:Draw()
    for i, row in ipairs(rows) do
        local line = lines[offset + i]
        row.line = line
        row:SetShown(line ~= nil)
        row:EnableMouse(line ~= nil and line.item ~= nil)
        if line and line.item then SetItem(row, line.item) elseif line then SetHeader(row, line.header) end
    end
    local hidden = math.max(0, #lines - LINES)
    panel.footer:SetText(hidden > 0 and L.SHOP_PANEL_SCROLL or L.SHOP_PANEL_HINT)
end

function ShoppingPanel:Refresh()
    if not Enabled() or closedThisVisit or not Compat.IsAuctionHouseOpen() then
        if panel then panel:Hide() end
        return
    end
    local items = ns.Shopping:Items()
    if #items == 0 then
        if panel then panel:Hide() end
        return
    end
    if not panel then Create() end

    local buy = 0
    for _, item in ipairs(items) do
        if item.status == "BUY" then buy = buy + 1 end
    end
    panel.title:SetText(L.SHOP_TITLE:format(#items, buy))

    wipe(lines)
    for _, group in ipairs(ns.Shopping.Groups(items)) do
        lines[#lines + 1] = { header = group }
        for _, item in ipairs(group.items) do lines[#lines + 1] = { item = item } end
    end
    offset = math.min(offset, math.max(0, #lines - LINES))
    self:Draw()

    panel:SetHeight(-TOP + math.min(#lines, LINES) * ROW + 28)
    self:Place()
    panel:Show()
end

local function Soon()
    Util.Debounce("shoppingPanel", 0.3, function() ShoppingPanel:Refresh() end)
end

ns.Events:On("AUCTION_HOUSE_SHOW", function()
    closedThisVisit = false
    offset = 0
    -- Blizzard builds its frame first; draw on the next frame.
    C_Timer.After(0, function() ShoppingPanel:Refresh() end)
end)
ns.Events:On("AUCTION_HOUSE_CLOSED", function()
    if panel then panel:Hide() end
end)
for _, event in ipairs({ "AC_SHOPPING_CHANGED", "AC_SCAN_COMPLETE", "AC_LIVE_PRICE", "AC_DATA_CHANGED" }) do
    ns.Events:On(event, Soon)
end

-- /ac shop with nothing after it opens the panel again at the AH.
function ShoppingPanel:Open()
    closedThisVisit = false
    self:Refresh()
    return self:IsShown()
end
