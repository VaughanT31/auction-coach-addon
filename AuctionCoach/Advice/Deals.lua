-- Auction Coach - deals: items listed well below their usual price.
--
-- An item is a deal when its lowest listing is well below what the lowest
-- listing normally is (Prices usualMin), the profit after the AH cut is
-- worth the trouble, the item actually sells, and the price was seen
-- recently. Needs server data (Data.lua or an import string) for usual
-- prices and sales.
-- Gear is left out: each bonus ID combination has only a listing or two,
-- so its "usual" price is just one seller's asking price. Comparing lowest
-- with usual lowest, not with the market value, means a cheap listing
-- that sits unsold for days turns into the usual price instead of a
-- "deal", and troll stacks above the real listings never make one.

local _, ns = ...
local Util = ns.Util

local Deals = {}
ns.Deals = Deals

-- Lowest prices older than this have probably been bought already.
-- Server data is up to about 90 minutes old when it arrives.
local MAX_AGE = 3 * 3600
-- Items that sell less often than this are hard to resell.
local MIN_SALES_PER_DAY = 1
local MAX_DEALS = 100

local cache, cacheAt

local function Settings()
    local s = ns.db.settings
    return s.dealMinDiscount or 0.3, s.dealMinProfit or 5 * 10000
end

-- Keys of everything that might be a deal, using the raw rows only, so
-- the full price lookup runs on a few hundred items instead of 50,000+.
-- Also returns whether any item has a usual lowest price yet, and the
-- time of the newest price seen.
local function Candidates(minDiscount)
    local keys = {}
    local ratio = 1 - minDiscount
    local hasHistory, newest = false, nil

    local function Seen(t)
        if t and (not newest or t > newest) then newest = t end
    end

    local function Check(key, low, usual)
        if low and usual and low > 0 and low < usual * ratio and not key:find(":b") then
            keys[key] = true
        end
    end

    -- Usual lowest from Data.lua, which beats the scan's own running average.
    local dataUsual = {}
    local data = ns.Prices.ActiveData()
    if data then
        local realmID = data.realmIndex and data.realmIndex[GetNormalizedRealmName()]
        local realmItems = realmID and data.realms and data.realms[realmID]
        for _, items in ipairs({ data.commodities or {}, realmItems or {} }) do
            for key, row in pairs(items) do
                if row.l then
                    hasHistory = true
                    dataUsual[key] = row.l
                end
                Seen(row.t or data.generatedAt)
                Check(key, row.n, row.l)
            end
        end
    end

    -- Scan rows: full scans, and live prices from AH searches that can be
    -- newer than Data.lua.
    local realm = ns.db.realms[ns.realmGroup]
    for key, row in pairs(realm and realm.scans or {}) do
        Seen(math.max(row.t or 0, row.lt or 0))
        Check(key, row.min, dataUsual[key])
    end
    return keys, hasHistory, newest
end

-- Keys the player is selling right now on any character. Server data
-- includes the player's own listings, which are never a deal for them.
local function OwnListings()
    local own = {}
    for _, char in pairs(ns.db.characters) do
        if char.realmGroup == ns.realmGroup and char.inventory and char.inventory.auctions then
            for key in pairs(char.inventory.auctions) do own[key] = true end
        end
    end
    return own
end

local function Evaluate(key, price, now, minDiscount, minProfit)
    local low = price.min
    if not low or low <= 0 then return nil end
    if now - (price.minAt or 0) > MAX_AGE then return nil end

    -- Relisting means matching the usual lowest price, unless the whole
    -- market has dropped below it.
    local resell = price.usualMin
    if not resell or resell <= 0 then return nil end
    if price.value and price.value > low and price.value < resell then
        resell = price.value
    end

    local discount = 1 - low / resell
    local profit = Util.AfterCut(resell) - low
    if discount < minDiscount or profit < minProfit then return nil end
    if not price.salesPerDay or price.salesPerDay < MIN_SALES_PER_DAY then return nil end

    return {
        key = key,
        price = low,
        priceAt = price.minAt,
        resell = resell,
        discount = discount,
        profit = profit,
        salesPerDay = price.salesPerDay,
    }
end

-- Returns {
--   items = { { key, price, priceAt, resell, discount, profit, salesPerDay }, ... }
--           best profit first, at most MAX_DEALS
--   newest = time of the newest price seen, nil when there are none
--   hasData = true when Data.lua with prices is loaded
--   hasHistory = true once Data.lua has usual lowest prices (about a day
--                after the server starts collecting)
-- }
function Deals:List()
    if cache then return cache end
    local result = { items = {}, hasData = ns.Prices.ActiveData() ~= nil }
    if not ns.db or not ns.realmGroup then return result end

    local now = Util.Now()
    local minDiscount, minProfit = Settings()
    local own = OwnListings()

    local candidates
    candidates, result.hasHistory, result.newest = Candidates(minDiscount)
    for key in pairs(candidates) do
        local price = not own[key] and ns.Prices:Get(key)
        if price then
            local deal = Evaluate(key, price, now, minDiscount, minProfit)
            if deal then table.insert(result.items, deal) end
        end
    end

    table.sort(result.items, function(a, b)
        if a.profit ~= b.profit then return a.profit > b.profit end
        return a.key < b.key
    end)
    for i = #result.items, MAX_DEALS + 1, -1 do
        result.items[i] = nil
    end

    -- Deals age out, so even unchanged data is looked at again after a while.
    cache, cacheAt = result, now
    return result
end

function Deals:Invalidate()
    cache = nil
end

function Deals:IsStale()
    return cache ~= nil and Util.Now() - cacheAt > 60
end

for _, event in ipairs({ "AC_SCAN_COMPLETE", "AC_LIVE_PRICE", "AC_INVENTORY_CHANGED", "AC_DATA_CHANGED" }) do
    ns.Events:On(event, function() Deals:Invalidate() end)
end

