-- Auction Coach - prices from two sources:
--   scan  the in-game full scan (Scan/FullScan.lua), per connected-realm group
--   data  AuctionCoachData, written into AuctionCoach_Data/Data.lua by the
--         desktop app (format documented in that file)
-- When both have a price, the newer one wins.

local _, ns = ...
local Util = ns.Util

local Prices = {}
ns.Prices = Prices

-- Market value from a list of { price, quantity } listings (unit prices).
-- Averages the cheapest 15% of quantity, extending to 30% while prices stay
-- within 20% of the previous listing. Troll listings at silly prices sit
-- far above that chunk, so they never move the market value.
function Prices.MarketValue(listings)
    table.sort(listings, function(a, b) return a[1] < b[1] end)

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
        scans[key] = { t = timestamp, min = minPrice, mkt = minPrice, qty = 0, n = 0 }
    end
end

local function FromData(key, realmName)
    local data = AuctionCoachData
    if type(data) ~= "table" or data.format ~= 1 then return nil end

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
        qty = row.qty,
        t = row.t,
        source = "scan",
    }
end

-- Price info for an item key, or nil when nothing is known.
-- groupKey and realmName default to the current character's.
-- Returns { value, min, t, source, ... }, where value is the market value
-- in copper per item.
function Prices:Get(key, groupKey, realmName)
    if not key or not ns.db then return nil end
    groupKey = groupKey or ns.realmGroup
    realmName = realmName or GetNormalizedRealmName()

    local scan = groupKey and FromScan(key, groupKey)
    local data = FromData(key, realmName)
    if scan and data then
        return (data.t > scan.t) and data or scan
    end
    return scan or data
end

function Prices:GetForLink(link)
    return self:Get(Util.ItemKeyFromLink(link))
end
