-- Auction Coach - cross-realm flips: items listed cheaply on one of the
-- player's realms that usually sell for more on another of them. Buy on
-- the cheap realm, move the item through the warband bank, post it on
-- the other.
--
-- Only realm-specific items can differ between realms: commodities
-- (reagents, consumables...) share one region-wide AH, so they are never
-- flips. Prices per realm come from the same places as everywhere else:
-- the desktop app's Data.lua (one block per realm the player has
-- characters on) and each realm group's own scans.
--
-- Same rules as Deals for what counts: the buy price was seen recently,
-- the profit after the AH cut is worth the trouble, and the item sells
-- on the other realm. Soulbound items never reach the AH, so whatever is
-- listed can be moved.

local _, ns = ...
local Util = ns.Util

local Flips = {}
ns.Flips = Flips

local MAX_AGE = 3 * 3600
-- Gear sells slower than reagents; one sale every two days is enough for
-- a single item.
local MIN_SALES_PER_DAY = 0.5
local MIN_GAIN = 0.25 -- the other realm must pay at least 25% more
local MAX_FLIPS = 100

local cache, cacheAt

-- The player's realm groups: { { group, realm = a realm name in it } },
-- from every character seen. Needs a realm name to look up Data.lua.
function Flips.PlayerRealms()
    local list, seen = {}, {}
    for charKey, char in pairs(ns.db.characters) do
        local group = char.realmGroup
        local realm = charKey:match("%-(.+)$")
        if group and realm and not seen[group] then
            seen[group] = true
            list[#list + 1] = { group = group, realm = realm }
        end
    end
    table.sort(list, function(a, b) return a.realm < b.realm end)
    return list
end

-- Realm-specific item keys known on a realm: its Data.lua block and its scans.
local function KeysOn(r, data)
    local keys = {}
    local realmID = data and data.realmIndex and data.realmIndex[r.realm]
    local items = realmID and data.realms and data.realms[realmID]
    for key in pairs(items or {}) do keys[key] = true end
    local realm = ns.db.realms[r.group]
    for key in pairs(realm and realm.scans or {}) do
        if not (data and data.commodities and data.commodities[key]) then keys[key] = true end
    end
    return keys
end

-- What the item usually sells for on the sell realm: its usual lowest,
-- or the market value when the market has dropped below that.
local function ResellPrice(price)
    local resell = price.usualMin or price.value
    if price.value and price.usualMin and price.value < price.usualMin then resell = price.value end
    return resell
end

-- One buy realm / sell realm pair for an item. Pure: buy and sell are
-- Prices:Get results. Returns a flip table or nil.
function Flips.Evaluate(key, buy, sell, now, minProfit)
    if not buy or not sell or not buy.min or buy.min <= 0 then return nil end
    if now - (buy.minAt or buy.t or 0) > MAX_AGE then return nil end
    local resell = ResellPrice(sell)
    if not resell or resell <= 0 then return nil end
    if resell < buy.min * (1 + MIN_GAIN) then return nil end
    local profit = Util.AfterCut(resell) - buy.min
    if profit < minProfit then return nil end
    if not sell.salesPerDay or sell.salesPerDay < MIN_SALES_PER_DAY then return nil end
    return {
        key = key, price = buy.min, priceAt = buy.minAt or buy.t, resell = resell,
        profit = profit, salesPerDay = sell.salesPerDay,
    }
end

-- Returns {
--   items  { { key, price, priceAt, resell, profit, salesPerDay,
--              buyRealm, sellRealm }, ... } best profit first
--   realms how many of the player's realm groups were compared
-- }
function Flips:List()
    if cache then return cache end
    local result = { items = {}, realms = 0 }
    if not ns.db then return result end
    local realms = Flips.PlayerRealms()
    result.realms = #realms
    if #realms < 2 then
        cache, cacheAt = result, Util.Now()
        return result
    end

    local data = ns.Prices.ActiveData()
    local now = Util.Now()
    local minProfit = ns.db.settings.dealMinProfit or (5 * 10000)
    local keysOn = {}
    for i, r in ipairs(realms) do keysOn[i] = KeysOn(r, data) end

    -- Best flip per item: the cheapest realm to buy on, the best to sell on.
    local best = {}
    for i, buyRealm in ipairs(realms) do
        for key in pairs(keysOn[i]) do
            -- Grey items never resell.
            if not ns.Rules:IsJunk(key) then
                local buy
                for j, sellRealm in ipairs(realms) do
                    if j ~= i and keysOn[j][key] then
                        buy = buy or ns.Prices:Get(key, buyRealm.group, buyRealm.realm)
                        local sell = ns.Prices:Get(key, sellRealm.group, sellRealm.realm)
                        local flip = Flips.Evaluate(key, buy, sell, now, minProfit)
                        if flip and (not best[key] or flip.profit > best[key].profit) then
                            flip.buyRealm, flip.sellRealm = buyRealm.realm, sellRealm.realm
                            best[key] = flip
                        end
                    end
                end
            end
        end
    end

    for _, flip in pairs(best) do result.items[#result.items + 1] = flip end
    table.sort(result.items, function(a, b)
        if a.profit ~= b.profit then return a.profit > b.profit end
        return a.key < b.key
    end)
    for i = #result.items, MAX_FLIPS + 1, -1 do result.items[i] = nil end
    cache, cacheAt = result, now
    return result
end

function Flips:Invalidate()
    cache = nil
end

function Flips:IsStale()
    return cache ~= nil and Util.Now() - cacheAt > 60
end

for _, event in ipairs({ "AC_SCAN_COMPLETE", "AC_LIVE_PRICE", "AC_INVENTORY_CHANGED", "AC_DATA_CHANGED" }) do
    ns.Events:On(event, function() Flips:Invalidate() end)
end
