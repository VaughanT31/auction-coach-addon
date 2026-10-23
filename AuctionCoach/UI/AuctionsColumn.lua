-- Auction Coach - a Status column on Blizzard's Auctions tab, after Time
-- left, for each of the player's auctions:
--
--   Cheapest           nobody has listed it lower since it was posted
--   Undercut 3g (2)    the lowest is 3g below it, and 2 auctions from
--                      other sellers are cheaper (units, for reagents and
--                      other commodities)
--
-- Uses the same test as the Auctions tab (Advice/Auctions.lua), so both
-- always agree. The cheaper count comes from the last search of the item
-- (Scan/ItemCheck.lua), so it shows once the item has been searched in
-- the last 15 minutes: clicking the auction in the list does that.
--
-- Blizzard builds the list's columns with a layout function; this wraps
-- it and adds one column at the end. Turned off with the "Cheapest or
-- undercut on Blizzard's Auctions tab" option.
--
-- The cell template is UI/AuctionsColumn.xml, loaded after this file.

local _, ns = ...
local L, Util = ns.L, ns.Util

local Column = {}
ns.AuctionsColumn = Column

local WIDTH = 120
local GREEN = "|cff66dd77"
local RED = "|cffff6666"
local GREY = "|cff999999"

local installed

local function Enabled()
    return ns.db and ns.db.settings.auctionsColumn ~= false
end

local function List()
    local frame = AuctionHouseFrame and AuctionHouseFrame.AuctionsFrame
    return frame and frame.AllAuctionsList, frame
end

-- The player's newest posts, read once per frame rather than once per row.
local postsAt, posts
local function Posts()
    local now = GetTime()
    if now ~= postsAt then
        postsAt, posts = now, ns.Auctions.NewestPosts()
    end
    return posts
end

-- Item key and unit price of an owned auction, the same way
-- Data/Inventory.lua reads them.
local function KeyAndUnit(info)
    local key
    if info.itemLink then
        key = Util.ItemKeyFromLink(info.itemLink)
    elseif info.itemKey and info.itemKey.itemID then
        key = Util.SimpleItemKey(info.itemKey.itemID)
    end
    local unit = info.buyoutAmount
    if unit and info.itemLink then unit = math.floor(unit / math.max(1, info.quantity or 1)) end
    return key, unit
end

-- Other sellers' auctions (or units, for commodities) cheaper than unit,
-- from the last search of the item. nil when it hasn't been searched lately.
local function CheaperCount(key, unit, commodity)
    local rows = ns.SellChance:GetLadder(key)
    if not rows then return nil end
    local count = 0
    for _, row in ipairs(rows) do
        if row[1] < unit then count = count + (commodity and row[2] or 1) end
    end
    return count
end

-- What the cell shows for one row, or nil for sold auctions and bids.
local function Describe(info)
    if not info or info.status ~= Enum.AuctionStatus.Active or not ns.db or not ns.Auctions then return nil end
    local key, unit = KeyAndUnit(info)
    if not key or not unit or unit <= 0 then return nil end
    local standing, price = ns.Auctions.Standing(key, unit, Posts())
    local d = { standing = standing, unit = unit, commodity = info.itemLink == nil }
    if price then d.lowest, d.lowestAt = price.min, price.minAt end
    if standing == "UNDERCUT" then
        d.by = unit - price.min
        d.cheaper = CheaperCount(key, unit, d.commodity)
    end
    return d
end

local function CellText(d)
    if d.standing == "CHEAPEST" then return GREEN .. L.AHCOL_CHEAPEST .. "|r" end
    if d.standing == "UNDERCUT" then
        local by = Util.FormatMoney(d.by)
        if d.cheaper and d.cheaper > 0 then
            return RED .. L.AHCOL_UNDERCUT_COUNT:format(by, BreakUpLargeNumbers(d.cheaper)) .. "|r"
        end
        return RED .. L.AHCOL_UNDERCUT:format(by) .. "|r"
    end
    return GREY .. L.AHCOL_NO_PRICE .. "|r"
end

-- ---------------------------------------------------------------------
-- Cell (mixin for AuctionCoachAuctionStatusCellTemplate)
-- ---------------------------------------------------------------------

-- The row calls OnLineEnter and OnLineLeave on every cell, so the base
-- cell mixin is needed.
AuctionCoachAuctionStatusCellMixin = CreateFromMixins(TableBuilderCellMixin)
local Cell = AuctionCoachAuctionStatusCellMixin

function Cell:Init(owner)
    self.owner = owner
    -- Hover for the tooltip, but clicks go through to the row so it can
    -- still be selected.
    if self.SetMouseClickEnabled then self:SetMouseClickEnabled(false) end
end

function Cell:Populate(rowData)
    self.info = Describe(rowData)
    self.Text:SetText(self.info and CellText(self.info) or "")
end

function Cell:OnEnter()
    ExecuteFrameScript(self:GetParent(), "OnEnter")
    local d = self.info
    if not d then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if d.standing == "CHEAPEST" then
        GameTooltip:SetText(L.AHCOL_CHEAPEST, 0.4, 0.87, 0.47)
        GameTooltip:AddLine(L.AUCTIONS_WHY_KEEP, 1, 1, 1, true)
    elseif d.standing == "UNDERCUT" then
        GameTooltip:SetText(L.AHCOL_TIP_UNDERCUT:format(Util.FormatMoney(d.by)), 1, 0.4, 0.4)
        GameTooltip:AddLine(L.AHCOL_TIP_PRICES:format(Util.FormatMoney(d.lowest), Util.FormatMoney(d.unit)), 1, 1, 1, true)
        if d.cheaper then
            local text = d.commodity and L.AHCOL_TIP_CHEAPER_UNITS or L.AHCOL_TIP_CHEAPER
            GameTooltip:AddLine(text:format(BreakUpLargeNumbers(d.cheaper)), 1, 1, 1, true)
        else
            GameTooltip:AddLine(L.AHCOL_TIP_SEARCH, 0.75, 0.75, 0.75, true)
        end
        GameTooltip:AddLine(L.AHCOL_TIP_ADVICE, 0.75, 0.75, 0.75, true)
    else
        GameTooltip:SetText(L.AHCOL_NO_PRICE, 0.6, 0.6, 0.6)
        GameTooltip:AddLine(L.AUCTIONS_WHY_UNKNOWN, 1, 1, 1, true)
    end
    if d.lowestAt then
        GameTooltip:AddLine(L.AUCTIONS_LOWEST_AGE:format(Util.FormatAge(d.lowestAt)), 0.75, 0.75, 0.75)
    end
    GameTooltip:Show()
end

function Cell:OnLeave()
    ExecuteFrameScript(self:GetParent(), "OnLeave")
    GameTooltip_Hide()
end

-- ---------------------------------------------------------------------
-- Column
-- ---------------------------------------------------------------------

local function Install()
    if installed or not AuctionHouseTableBuilder or not AuctionHouseTableBuilder.GetAllAuctionsLayout then return end
    local list, owner = List()
    if not list or not list.SetTableBuilderLayout then return end
    installed = true
    local blizzard = AuctionHouseTableBuilder.GetAllAuctionsLayout(owner, list)
    Column.layout = function(tableBuilder)
        blizzard(tableBuilder)
        if Enabled() then
            tableBuilder:AddUnsortableFixedWidthColumn(owner, 0, WIDTH, 8, 4, L.AHCOL_HEAD, "AuctionCoachAuctionStatusCellTemplate")
        end
    end
    list:SetTableBuilderLayout(Column.layout)
end

-- Rebuilds the columns, after the option changes.
function Column:Refresh()
    local list = List()
    if installed and list then list:SetTableBuilderLayout(Column.layout) end
end

-- Redraws the rows with fresh prices, when the list is showing.
local function Redraw()
    local list = List()
    if installed and Enabled() and list and list:IsVisible() and list.RefreshScrollFrame then
        Util.Debounce("auctionsColumn", 0.3, function()
            if list:IsVisible() then list:RefreshScrollFrame() end
        end)
    end
end

ns.Events:On("ADDON_LOADED", function(_, name)
    if name == "Blizzard_AuctionHouseUI" then Install() end
end)

ns.Events:On("AUCTION_HOUSE_SHOW", Install)

-- A search gave a fresh lowest price and cheaper count.
ns.Events:On("AC_LIVE_PRICE", Redraw)
