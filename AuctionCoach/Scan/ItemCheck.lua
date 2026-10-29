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
    ns.Undercuts:Observe(ns.realmGroup, key, minPrice, now)
    if sellers then
        ns.Competition:RecordSellers(ns.realmGroup, key, sellers, now)
    end
end

-- Only the player's own listings came back: nobody else sells it, so the
-- lowest price is the player's own. An older, lower price from someone
-- whose listings have since sold or expired no longer counts.
local function OnlyOwn(key, ownMin)
    local now = Util.Now()
    if ownMin then ns.Prices:RecordLivePrice(ns.realmGroup, key, ownMin, now) end
    ns.Undercuts:Observe(ns.realmGroup, key, nil, now)
end

-- Commodities (reagents, consumables...): results are sorted cheapest first.
-- Rows made up only of the player's own listings are skipped, so they
-- never set the price. A row at the same price can mix the player's and
-- others' listings: it counts when others have some of its quantity.
local function CheckCommodity(itemID)
    local key = Util.SimpleItemKey(itemID)
    if not key then return end
    local num = C_AuctionHouse.GetNumCommoditySearchResults(itemID) or 0
    if num == 0 then return end
    -- Other sellers' listings (unit price, quantity), for the sell chance.
    local rows, lowest, ownMin = {}, nil, nil
    for i = 1, num do
        local info = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
        if info and info.unitPrice and info.unitPrice > 0 then
            local own = info.containsOwnerItem or info.containsAccountItem
            local others = (info.quantity or 0) - (own and (info.numOwnerItems or 0) or 0)
            if others > 0 then
                rows[#rows + 1] = { info.unitPrice, others }
                lowest = lowest or info.unitPrice
            elseif own then
                ownMin = ownMin or info.unitPrice
            end
        end
    end
    ns.SellChance:SetLadder(key, rows)
    if lowest then
        RecordSample(key, lowest)
    else
        OnlyOwn(key, ownMin)
    end
end

-- Items (gear, pets, other non-stackables): one search can return several
-- item levels, so results are grouped by our own item key.
local function CheckItem(itemKey)
    local num = C_AuctionHouse.GetNumItemSearchResults(itemKey)
    if not num or num == 0 then return end

    local byKey, ownMin = {}, {}
    for i = 1, num do
        local info = C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
        local key = info and Util.ItemKeyFromLink(info.itemLink)
        -- containsOwnerItem / containsAccountItem: the player's own listings,
        -- left out so they never set the price. buyoutAmount is already the
        -- price of one item, as the AH shows it (unlike a full scan's
        -- buyout, which covers the whole auction): dividing it by the
        -- quantity, as before 0.20.3, made a stack of 4 at 1,404g read 351g.
        local own = info and (info.containsOwnerItem or info.containsAccountItem)
        if key and own and info.buyoutAmount and info.buyoutAmount > 0 then
            local unitPrice = info.buyoutAmount
            if not ownMin[key] or unitPrice < ownMin[key] then ownMin[key] = unitPrice end
        elseif key and not own and info.buyoutAmount and info.buyoutAmount > 0 then
            local unitPrice = info.buyoutAmount
            local entry = byKey[key]
            if not entry then
                entry = { min = unitPrice, owners = {}, rows = {} }
                byKey[key] = entry
            elseif unitPrice < entry.min then
                entry.min = unitPrice
            end
            entry.rows[#entry.rows + 1] = { unitPrice, math.max(1, info.quantity or 1) }
            for _, owner in ipairs(info.owners or {}) do
                entry.owners[owner] = true
            end
        end
    end

    for key, entry in pairs(byKey) do
        local sellers = 0
        for _ in pairs(entry.owners) do sellers = sellers + 1 end
        ns.SellChance:SetLadder(key, entry.rows)
        RecordSample(key, entry.min, sellers > 0 and sellers or nil)
    end
    for key, price in pairs(ownMin) do
        if not byKey[key] then
            ns.SellChance:SetLadder(key, {})
            OnlyOwn(key, price)
        end
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

-- ---------------------------------------------------------------------
-- Own listings check (1.0.7)
-- ---------------------------------------------------------------------
-- When the desktop app's prices are fresh, the AH opening skips the full
-- scan (Scan/FullScan.lua), so undercuts are found the way TSM does it:
-- each item the player has listed is searched once, one at a time at the
-- pace the game allows. The answers land in the handlers above, like any
-- search. It stops when the AH closes, or as soon as anything else
-- searches (the player, Blizzard's own UI or the Auctions tab column), so
-- it never gets in the way.

local OwnCheck = {}
ns.OwnCheck = OwnCheck

local STEP = 1.2
local RECHECK_AFTER = 60 -- items searched this recently are skipped
local SORTS = { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }
local queue, wanted, running, sending = {}, false, false, false

local function Stop()
    wipe(queue)
    running = false
end

local function Ready()
    return not C_AuctionHouse.IsThrottledMessageSystemReady or C_AuctionHouse.IsThrottledMessageSystemReady()
end

local function Step()
    if not running then return end
    if not ns.Compat.IsAuctionHouseOpen() then return Stop() end
    local nextItem = queue[1]
    if not nextItem then
        running = false
        return
    end
    if Ready() then
        table.remove(queue, 1)
        sending = true
        pcall(C_AuctionHouse.SendSearchQuery, nextItem, SORTS, false)
        sending = false
    end
    C_Timer.After(Ready() and STEP or 0.5, Step)
end

local function Start()
    if running or not C_AuctionHouse.SendSearchQuery then return end
    local now, seen = Util.Now(), {}
    wipe(queue)
    for i = 1, C_AuctionHouse.GetNumOwnedAuctions() do
        local info = C_AuctionHouse.GetOwnedAuctionInfo(i)
        if info and info.status == Enum.AuctionStatus.Active and info.itemKey then
            local key = info.itemLink and Util.ItemKeyFromLink(info.itemLink)
                or (info.itemKey.itemID and Util.SimpleItemKey(info.itemKey.itemID))
            local price = key and ns.Prices:Get(key)
            local fresh = price and price.minAt and now - price.minAt < RECHECK_AFTER
            if key and not seen[key] and not fresh then
                seen[key] = true
                queue[#queue + 1] = info.itemKey
            end
        end
    end
    if #queue == 0 then return end
    running = true
    -- Blizzard's AH window searches as soon as it opens: let that go first.
    C_Timer.After(2, Step)
end

-- Asked by the full scan when it skips: runs once the player's auctions
-- arrive (Data/Inventory.lua asks for them when the AH opens).
function OwnCheck:Request()
    wanted = true
end

function OwnCheck:IsRunning()
    return running
end

ns.Events:On("OWNED_AUCTIONS_UPDATED", function()
    if wanted then
        wanted = false
        C_Timer.After(0.5, Start)
    end
end)

ns.Events:On("AUCTION_HOUSE_CLOSED", function()
    wanted = false
    Stop()
end)

-- Any other search means someone else wants the AH: step aside.
for _, name in ipairs({ "SendSearchQuery", "SendBrowseQuery", "SendSellSearchQuery" }) do
    if C_AuctionHouse[name] then
        hooksecurefunc(C_AuctionHouse, name, function()
            if running and not sending then Stop() end
        end)
    end
end
