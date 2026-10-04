-- Auction Coach - public API for other addons (CraftSim, WeakAuras, ...).
--
-- All prices are copper per item. Functions return nil when Auction Coach
-- has no data for the item (never 0, so callers can fall back cleanly).
-- `item` can be an item link, an item ID, or a TSM-style "i:12345" string.
-- Gear only has prices per version, so pass a link for gear.
--
--   AuctionCoachAPI.version                  1, raised only on breaking changes
--   AuctionCoachAPI.IsReady()                true once prices can be read
--   AuctionCoachAPI.GetMarketValue(item)     typical price (cheapest 15-30% of listings)
--   AuctionCoachAPI.GetMinBuyout(item)       lowest listing, newest of scan / server data
--   AuctionCoachAPI.GetHistorical(item)      14-day average market value (server data)
--   AuctionCoachAPI.GetSaleRate(item)        estimated sales per day (server data)
--   AuctionCoachAPI.GetPriceInfo(item)       table with all of the above plus updated, source
--   AuctionCoachAPI.GetSuggestedPrice(item)  price to post at, and the action:
--                                            "POST" | "HOLD" | "VENDOR" | "NO_DATA"

local _, ns = ...
local Util = ns.Util

local function KeyFor(item)
    if type(item) == "number" then
        return Util.SimpleItemKey(item) or tostring(item), nil
    end
    if type(item) ~= "string" then return nil end
    local tsmID = item:match("^i:(%d+)$")
    if tsmID then
        return KeyFor(tonumber(tsmID))
    end
    if item:match("^%d+$") then
        return KeyFor(tonumber(item))
    end
    return Util.ItemKeyFromLink(item), item
end

local function Info(item)
    if not ns.db or not ns.realmGroup then return nil end
    local key = KeyFor(item)
    return key and ns.Prices:Get(key) or nil
end

local API = { version = 1 }

function API.IsReady()
    return ns.db ~= nil and ns.realmGroup ~= nil
end

function API.GetMarketValue(item)
    local info = Info(item)
    return info and info.value or nil
end

function API.GetMinBuyout(item)
    local info = Info(item)
    return info and (info.min or info.value) or nil
end

function API.GetHistorical(item)
    local info = Info(item)
    return info and info.historical or nil
end

function API.GetSaleRate(item)
    local info = Info(item)
    return info and info.salesPerDay or nil
end

function API.GetPriceInfo(item)
    local info = Info(item)
    if not info then return nil end
    -- A copy, so callers cannot change Auction Coach's own data.
    return {
        market = info.value,
        min = info.min or info.value,
        historical = info.historical,
        salesPerDay = info.salesPerDay,
        updated = info.t,
        source = info.source,
    }
end

function API.GetSuggestedPrice(item)
    if not API.IsReady() then return nil, "NO_DATA" end
    local key, link = KeyFor(item)
    if not key then return nil, "NO_DATA" end
    local s = ns.Rules:SuggestPrice(key, link)
    return s.price, s.action
end

AuctionCoachAPI = API
