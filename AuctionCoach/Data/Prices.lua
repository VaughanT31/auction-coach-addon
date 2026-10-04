-- Auction Coach - prices from two sources:
--   scan  the in-game full scan (Scan/FullScan.lua), per connected-realm group
--   data  AuctionCoachData, written into AuctionCoach_Data/Data.lua by the
--         desktop app (format documented in that file), or the same format
--         pasted in as an import string (Data/Share.lua); the newer is used
-- When both have a price, the newer one wins.

local _, ns = ...
local Util = ns.Util

local Prices = {}
ns.Prices = Prices

-- Market value from a list of { price, quantity } listings (unit prices).
-- Averages the cheapest 15% of quantity, extending to 30% while prices stay
-- within 20% of the previous listing. Troll listings at silly prices sit
-- far above that chunk, so they never move the market value.
-- Old items can have so few real listings that troll stacks hold most of
-- the quantity, so the average also stops at a cliff: a price more than
-- CLIFF times the previous one, once CLIFF_MIN_LISTINGS listings are in.
-- One cheap listing alone never counts as the market (it may be a deal).
-- Must stay identical to market_value in the platform (shared/pricing.py).
local CLIFF, CLIFF_MIN_LISTINGS = 5, 3

function Prices.MarketValue(listings)
    -- Same order as Python's sorted(): price, then quantity.
    table.sort(listings, function(a, b)
        if a[1] ~= b[1] then return a[1] < b[1] end
        return a[2] < b[2]
    end)

    local totalQty = 0
    for i = 1, #listings do
        totalQty = totalQty + listings[i][2]
    end
    if totalQty == 0 then return nil end

    local lowTarget = math.max(1, totalQty * 0.15)
    local highTarget = totalQty * 0.30
    local sumValue, sumQty, lastPrice = 0, 0, nil

    for i = 1, #listings do
        local price, qty = listings[i][1], listings[i][2]
        if i > CLIFF_MIN_LISTINGS and price > lastPrice * CLIFF then
            break
        end
        if sumQty >= lowTarget then
            if sumQty >= highTarget or price > lastPrice * 1.2 then
                break
            end
        end
        sumValue = sumValue + price * qty
        sumQty = sumQty + qty
        lastPrice = price
    end

    return math.floor(sumValue / sumQty + 0.5)
end

-- Saves the results of a full scan. results[itemKey] = { min, market, qty, auctions }.
-- Items missing from this scan keep their old row, so their age shows how
-- long ago they were last listed.
function Prices:RecordFullScan(groupKey, results, timestamp)
    local realm = ns:GetRealmData(groupKey)
    local scans = realm.scans
    local count = 0
    for key, r in pairs(results) do
        scans[key] = { t = timestamp, min = r.min, mkt = r.market, qty = r.qty, n = r.auctions }
        count = count + 1
    end
    realm.lastFullScan = timestamp
    return count
end

-- Saves a live price seen while browsing one item. When a full scan row
-- exists, only its lowest price is refreshed: the market value and its
-- timestamp still describe the last full scan.
function Prices:RecordLivePrice(groupKey, key, minPrice, timestamp)
    local scans = ns:GetRealmData(groupKey).scans
    local row = scans[key]
    if row then
        row.min = minPrice
    else
        row = { t = timestamp, min = minPrice, mkt = minPrice, qty = 0, n = 0 }
        scans[key] = row
    end
    -- lt: when the lowest price was last seen live.
    row.lt = timestamp
    ns.Events:Fire("AC_LIVE_PRICE", key)
end

local function Usable(data)
    return type(data) == "table" and data.format == 1 and (data.generatedAt or 0) > 0
end

-- The server price data in use: Data.lua or an imported string, whichever
-- is newer. nil when there is neither.
function Prices.ActiveData()
    local file = Usable(AuctionCoachData) and AuctionCoachData or nil
    local imported = ns.db and Usable(ns.db.imported) and ns.db.imported or nil
    if file and imported then
        return imported.generatedAt > file.generatedAt and imported or file
    end
    return file or imported
end

-- Call after replacing the imported price data.
function Prices:DataChanged()
    ns.Events:Fire("AC_DATA_CHANGED")
end

local function FromData(key, realmName)
    local data = Prices.ActiveData()
    if not data then return nil end

    local row
    if data.commodities then
        row = data.commodities[key]
    end
    if not row and data.realmIndex and data.realms and realmName then
        local realmID = data.realmIndex[realmName]
        local realmItems = realmID and data.realms[realmID]
        row = realmItems and realmItems[key]
    end
    if not row then return nil end

    return {
        value = row.m or row.n,
        min = row.n,
        historical = row.h,
        usualMin = row.l,
        salesPerDay = row.s,
        t = row.t or data.generatedAt or 0,
        source = "data",
    }
end

local function FromScan(key, groupKey)
    local realm = ns.db.realms[groupKey]
    local row = realm and realm.scans[key]
    if not row then return nil end
    return {
        value = row.mkt or row.min,
        min = row.min,
        minAt = math.max(row.t or 0, row.lt or 0),
        qty = row.qty,
        t = row.t,
        source = "scan",
    }
end

-- Price info for an item key, or nil when nothing is known.
-- groupKey and realmName default to the current character's.
-- Returns {
--   value        market value per item (copper), from the newer source
--   t, source    when and where value came from ("scan" or "data")
--   min, minAt   lowest listing, from whichever source saw it most recently
--                (a live AH search beats both full scans and Data.lua)
--   historical   14-day average market value (Data.lua only)
--   usualMin     what the lowest listing normally is: 7-day average of the
--                hourly lowest price (Data.lua only)
--   salesPerDay  estimated sales per day (Data.lua only)
-- }
function Prices:Get(key, groupKey, realmName)
    if not key or not ns.db then return nil end
    groupKey = groupKey or ns.realmGroup
    realmName = realmName or GetNormalizedRealmName()

    local scan = groupKey and FromScan(key, groupKey)
    local data = FromData(key, realmName)
    if not (scan and data) then
        local only = scan or data
        if only and not only.minAt then only.minAt = only.t end
        return only
    end

    local newer = (data.t > scan.t) and data or scan
    local result = {
        value = newer.value,
        t = newer.t,
        source = newer.source,
        historical = data.historical,
        usualMin = data.usualMin,
        salesPerDay = data.salesPerDay,
        qty = scan.qty,
    }
    if (scan.minAt or 0) >= data.t then
        result.min, result.minAt = scan.min, scan.minAt
    else
        result.min, result.minAt = data.min, data.t
    end
    return result
end

function Prices:GetForLink(link)
    return self:Get(Util.ItemKeyFromLink(link))
end
