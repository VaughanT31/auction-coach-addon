-- Auction Coach - thin wrappers around WoW APIs.
-- Blizzard renames and moves APIs between patches. Keeping every lookup
-- here means a patch-day fix is usually a one-line change in this file.

local _, ns = ...

local Compat = {}
ns.Compat = Compat

Compat.GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

-- The player's region as the server names it: "EU", "US", "KR", "TW" or "CN".
-- "" when the client does not say (should not happen on Retail).
local REGIONS = { [1] = "US", [2] = "KR", [3] = "EU", [4] = "TW", [5] = "CN" }
function Compat.RegionCode()
    return REGIONS[GetCurrentRegion and GetCurrentRegion() or 0] or ""
end
Compat.GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
Compat.GetDetailedItemLevelInfo = (C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo
Compat.GetItemIconByID = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
Compat.RequestLoadItemDataByID = (C_Item and C_Item.RequestLoadItemDataByID) or function() end

-- Vendor sell price in copper, or 0 when unknown or unsellable.
function Compat.GetVendorPrice(itemIDOrLink)
    if not itemIDOrLink then return 0 end
    local sellPrice = select(11, Compat.GetItemInfo(itemIDOrLink))
    return sellPrice or 0
end

-- Bind type: 0 none, 1 on pickup, 2 on equip, 3 on use, 4 quest, nil if uncached.
function Compat.GetBindType(itemIDOrLink)
    return select(14, Compat.GetItemInfo(itemIDOrLink))
end

-- ---------------------------------------------------------------------
-- Containers
--
-- Bag IDs are sorted into groups by their Enum.BagIndex names instead of
-- hardcoded numbers. The bank has been reworked several times (bank bags,
-- reagent bank, bank tabs), so whichever names exist on this client are
-- used and the rest are skipped.
-- ---------------------------------------------------------------------

local BAG_GROUPS = {
    { group = "bags", patterns = { "^backpack$", "^bag_%d+$", "^reagentbag$" } },
    { group = "bank", patterns = { "^bank$", "^bankbag_%d+$", "^characterbanktab_%d+$" } },
    { group = "reagentBank", patterns = { "^reagentbank$" } },
    { group = "warband", patterns = { "^accountbanktab_%d+$" } },
}

Compat.Bags = { bags = {}, bank = {}, reagentBank = {}, warband = {} }

for name, id in pairs(Enum.BagIndex or {}) do
    local lower = name:lower()
    for _, def in ipairs(BAG_GROUPS) do
        local matched = false
        for _, pattern in ipairs(def.patterns) do
            if lower:match(pattern) then matched = true break end
        end
        if matched then
            table.insert(Compat.Bags[def.group], id)
            break
        end
    end
end

for _, list in pairs(Compat.Bags) do
    table.sort(list)
end

-- Calls fn(info) for every occupied slot. info is the table returned by
-- C_Container.GetContainerItemInfo (hyperlink, stackCount, isBound, ...).
function Compat.ForEachContainerItem(bagID, fn)
    local numSlots = C_Container.GetContainerNumSlots(bagID)
    if not numSlots or numSlots == 0 then return end
    for slot = 1, numSlots do
        local info = C_Container.GetContainerItemInfo(bagID, slot)
        if info and info.hyperlink then
            fn(info, bagID, slot)
        end
    end
end

-- ---------------------------------------------------------------------
-- Realms
-- ---------------------------------------------------------------------

-- Connected realms share one Auction House, but the client exposes no
-- connected-realm ID. Use the alphabetically first realm of the group
-- as a stable key so alts on any realm of the group share scan data.
function Compat.GetRealmGroupKey()
    local own = GetNormalizedRealmName()
    local best = own
    local connected = GetAutoCompleteRealms and GetAutoCompleteRealms()
    if connected then
        for _, realm in ipairs(connected) do
            local normalized = realm:gsub("[%s%-]", "")
            if best == nil or normalized < best then
                best = normalized
            end
        end
    end
    return best
end

-- ---------------------------------------------------------------------
-- Auction House
-- ---------------------------------------------------------------------

function Compat.IsAuctionHouseOpen()
    return AuctionHouseFrame ~= nil and AuctionHouseFrame:IsShown()
end

-- Opens this item's listings at the Auction House, the same as clicking
-- it in the browse results. If Blizzard's frame has changed, or the item
-- is not cached yet, searches for its name instead. Returns true when
-- something was shown.
function Compat.ShowAtAuctionHouse(key, link, minPrice)
    if not Compat.IsAuctionHouseOpen() then return false end
    local Util = ns.Util

    local itemKey
    local species, level = key:match("^p:(%d+):(%d+)")
    if species then
        itemKey = C_AuctionHouse.MakeItemKey(Util.PET_CAGE_ITEM_ID, tonumber(level), 0, tonumber(species))
    else
        local itemLevel = 0
        if link and key:find(":b") then
            itemLevel = Compat.GetDetailedItemLevelInfo(link) or 0
        end
        itemKey = C_AuctionHouse.MakeItemKey(Util.ItemIDFromKey(key), itemLevel)
    end

    if AuctionHouseFrame.SelectBrowseResult and C_AuctionHouse.GetItemKeyInfo(itemKey) then
        local ok = pcall(AuctionHouseFrame.SelectBrowseResult, AuctionHouseFrame,
            { itemKey = itemKey, minPrice = minPrice })
        if ok then return true end
    end

    local name = link and link:match("%[(.-)%]")
    if name then name = name:gsub("|A.-|a", ""):gsub("|T.-|t", ""):match("^%s*(.-)%s*$") end
    local searchBar = AuctionHouseFrame.SearchBar
    if not name or name == "" or not (searchBar and searchBar.SearchBox and searchBar.StartSearch) then
        return false
    end
    if AuctionHouseFrame.SetDisplayMode and AuctionHouseFrameDisplayMode then
        pcall(AuctionHouseFrame.SetDisplayMode, AuctionHouseFrame, AuctionHouseFrameDisplayMode.Buy)
    end
    searchBar.SearchBox:SetText(name)
    return pcall(searchBar.StartSearch, searchBar)
end

function Compat.IsMerchantOpen()
    return MerchantFrame ~= nil and MerchantFrame:IsShown()
end

-- Fields of one replicate (full scan) entry that Auction Coach uses.
-- owner may be nil until the client has loaded the seller's name.
function Compat.GetReplicateItem(index)
    local _, _, count, _, _, _, _, _, _, buyout, _, _, _, owner, ownerFullName, _, itemID, hasAllInfo =
        C_AuctionHouse.GetReplicateItemInfo(index)
    return count, buyout, itemID, hasAllInfo, ownerFullName or owner
end
