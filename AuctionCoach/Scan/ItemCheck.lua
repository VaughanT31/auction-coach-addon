-- Auction Coach - live checks while the player browses the Auction House.
-- Every item search the player makes gives a fresh lowest price (and, for
-- non-commodity items, the list of sellers). These feed the competition
-- score and keep prices current between full scans.

local _, ns = ...
local Util = ns.Util

local function RecordSample(key, minPrice, sellers)
    local now = Util.Now()
    ns.Prices:RecordLivePrice(ns.realmGroup, key, minPrice, now)
    ns.Competition:Sample(ns.realmGroup, key, minPrice, now)
    if sellers then
        ns.Competition:RecordSellers(ns.realmGroup, key, sellers, now)
    end
end

-- Commodities (reagents, consumables...): results are sorted cheapest first.
local function CheckCommodity(itemID)
    local key = Util.SimpleItemKey(itemID)
    if not key then return end
    if C_AuctionHouse.GetNumCommoditySearchResults(itemID) == 0 then return end
    local first = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, 1)
    if first and first.unitPrice and first.unitPrice > 0 then
        RecordSample(key, first.unitPrice)
    end
end

-- Items (gear, pets, other non-stackables): one search can return several
-- item levels, so results are grouped by our own item key.
local function CheckItem(itemKey)
    local num = C_AuctionHouse.GetNumItemSearchResults(itemKey)
    if not num or num == 0 then return end

    local byKey = {}
    for i = 1, num do
        local info = C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
        local key = info and Util.ItemKeyFromLink(info.itemLink)
        -- containsOwnerItem / containsAccountItem: the player's own listings,
        -- left out so they never set the price.
        local own = info and (info.containsOwnerItem or info.containsAccountItem)
        if key and not own and info.buyoutAmount and info.buyoutAmount > 0 then
            local unitPrice = math.floor(info.buyoutAmount / math.max(1, info.quantity or 1))
            local entry = byKey[key]
            if not entry then
                entry = { min = unitPrice, owners = {} }
                byKey[key] = entry
            elseif unitPrice < entry.min then
                entry.min = unitPrice
            end
            for _, owner in ipairs(info.owners or {}) do
                entry.owners[owner] = true
            end
        end
    end

    for key, entry in pairs(byKey) do
        local sellers = 0
        for _ in pairs(entry.owners) do sellers = sellers + 1 end
        RecordSample(key, entry.min, sellers > 0 and sellers or nil)
    end
end

-- Results arrive in pages, so wait for them to settle before sampling.
ns.Events:On("COMMODITY_SEARCH_RESULTS_UPDATED", function(_, itemID)
    if not itemID then return end
    Util.Debounce("commodity:" .. itemID, 1, function() CheckCommodity(itemID) end)
end)

ns.Events:On("ITEM_SEARCH_RESULTS_UPDATED", function(_, itemKey)
    if not itemKey or not itemKey.itemID then return end
    local id = itemKey.itemID .. ":" .. (itemKey.itemLevel or 0) .. ":" .. (itemKey.battlePetSpeciesID or 0)
    Util.Debounce("item:" .. id, 1, function() CheckItem(itemKey) end)
end)
