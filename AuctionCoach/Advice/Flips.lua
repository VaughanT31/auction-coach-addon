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
-- Gear sells slower than reagents, so flips keep a lower bar than deals,
-- but the item still has to sell daily and not be buried in listings.
local MIN_CHANCE = 0.5
local MIN_GAIN = 0.25 -- the other realm must pay at least 25% more
local MAX_FLIPS = 100

local cache, cacheAt
local ownCache, ownAt
-- A live AH price only rebuilds the list when the last build is older than
-- this: searching item after item (Auctionator's searches count too) used to
-- rebuild it on every search.
local LIVE_REBUILD_AFTER = 15

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
-- or the market value when the market has dropped below that, and never
-- above where the next listings up start (the wall).
local function ResellPrice(price)
    local resell = price.usualMin or price.value
    if price.value and price.usualMin and price.value < price.usualMin then resell = price.value end
    if resell and price.wall and price.wall < resell then resell = price.wall end
    return resell
end

-- Why a pair isn't a flip, in the order the checks run: the further an
-- item got, the closer it was. The Other realms view counts these when it
-- has nothing to show, so an empty list says why.
Flips.REASONS = { "NOBUY", "OLD", "NORESELL", "GAIN", "PROFIT", "SLOW", "CROWDED" }
local STAGE = {}
for i, reason in ipairs(Flips.REASONS) do STAGE[reason] = i end

-- One buy realm / sell realm pair for an item. Pure: buy and sell are
-- Prices:Get results; minSales is the fewest sales a day on the sell realm
-- (Options, default 1). Returns a flip table, or nil and the reason.
function Flips.Evaluate(key, buy, sell, now, minProfit, minSales)
    if not buy or not sell or not buy.min or buy.min <= 0 then return nil, "NOBUY" end
    if now - (buy.minAt or buy.t or 0) > MAX_AGE then return nil, "OLD" end
    local resell = ResellPrice(sell)
    if not resell or resell <= 0 then return nil, "NORESELL" end
    if resell < buy.min * (1 + MIN_GAIN) then return nil, "GAIN" end
    local profit = Util.AfterCut(resell) - buy.min
    if profit < minProfit then return nil, "PROFIT" end
    if not sell.salesPerDay or sell.salesPerDay < (minSales or 1) then return nil, "SLOW" end
    local chance = ns.Deals.ResellChance(sell.salesPerDay, sell.listed)
    if chance < MIN_CHANCE then return nil, "CROWDED" end
    return {
        key = key, price = buy.min, priceAt = buy.minAt or buy.t, resell = resell,
        profit = profit, salesPerDay = sell.salesPerDay, listed = sell.listed, chance = chance,
    }
end

-- Returns {
--   items  { { key, price, priceAt, resell, profit, salesPerDay,
--              buyRealm, sellRealm }, ... } best profit first
--   realms how many of the player's realm groups were compared
--   compared  items found on at least two of them
--   why       { [reason] = items } for the items that aren't flips, each
--             counted once at the furthest check it reached (Flips.REASONS)
--   noPrices  names of the player's realms with no prices at all
-- }
function Flips:List()
    if cache then return cache end
    local result = { items = {}, realms = 0, compared = 0, why = {}, noPrices = {} }
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
    local minSales = ns.db.settings.flipMinSales or 1
    local keysOn = {}
    for i, r in ipairs(realms) do
        keysOn[i] = KeysOn(r, data)
        if next(keysOn[i]) == nil then result.noPrices[#result.noPrices + 1] = r.realm end
    end
    local closest, counted = {}, {}
    local function Closest(key, why)
        if not closest[key] or STAGE[why] > STAGE[closest[key]] then closest[key] = why end
    end

    -- Each realm's raw rows, read directly: four realms hold some 160,000
    -- items, and running the full price lookup (Prices:Get, a few tables per
    -- call) on every item against every other realm lagged the game. The
    -- raw rows rule out almost all of them first, generously (the lowest of
    -- either source, the highest resale), so no real flip is missed.
    local raw = {}
    for i, r in ipairs(realms) do
        local realmID = data and data.realmIndex and data.realmIndex[r.realm]
        local realm = ns.db.realms[r.group]
        raw[i] = { data = (realmID and data.realms and data.realms[realmID]) or {}, scans = realm and realm.scans or {} }
    end
    local function RawLow(i, key)
        local d, s = raw[i].data[key], raw[i].scans[key]
        local low = d and d.n
        if s and s.min and s.min > 0 and (not low or s.min < low) then low = s.min end
        return low
    end
    local function RawHigh(j, key)
        local d, s = raw[j].data[key], raw[j].scans[key]
        local high = d and math.max(d.l or 0, d.m or 0) or 0
        if s and s.mkt and s.mkt > high then high = s.mkt end
        return high > 0 and high or nil
    end
    -- Sales a day only come from Data.lua, so this one is exact.
    local function RawSales(j, key)
        local d = raw[j].data[key]
        return d and d.s
    end

    -- Best flip per item: the cheapest realm to buy on, the best to sell on.
    local best = {}
    for i, buyRealm in ipairs(realms) do
        for key in pairs(keysOn[i]) do
            local low = RawLow(i, key)
            local buy
            for j, sellRealm in ipairs(realms) do
                if j ~= i and keysOn[j][key] then
                    if not counted[key] then
                        counted[key] = true
                        result.compared = result.compared + 1
                    end
                    local high = RawHigh(j, key)
                    if not low then
                        Closest(key, "NOBUY")
                    elseif not high then
                        Closest(key, "NORESELL")
                    elseif high < low * (1 + MIN_GAIN) then
                        Closest(key, "GAIN")
                    elseif Util.AfterCut(high) - low < minProfit then
                        Closest(key, "PROFIT")
                    elseif (RawSales(j, key) or 0) < minSales then
                        Closest(key, "SLOW")
                    -- Grey items never resell (checked late: it asks the item cache).
                    elseif not ns.Rules:IsJunk(key) then
                        buy = buy or ns.Prices:Get(key, buyRealm.group, buyRealm.realm)
                        local sell = ns.Prices:Get(key, sellRealm.group, sellRealm.realm)
                        local flip, why = Flips.Evaluate(key, buy, sell, now, minProfit, minSales)
                        if why then Closest(key, why) end
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
    for key, why in pairs(closest) do
        if not best[key] then result.why[why] = (result.why[why] or 0) + 1 end
    end
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
    ownCache = nil
end

-- ---------------------------------------------------------------------
-- Your own items on a better realm (0.20.6)
-- ---------------------------------------------------------------------

-- Where an item you have would sell for clearly more than on the realm it's
-- on: another of your realms, where it resells for at least 25% more, your
-- smallest profit more after the AH cut, and sells often enough (the flip
-- rules). Commodities cost the same everywhere, so they never are.
-- Returns { realm, here, there, gain, salesPerDay } (here and there after
-- the AH cut, each), or nil and why not: { reason, realm, ... } for the
-- realm that came closest (reasons in WHY_ORDER), which the tooltip shows
-- with Shift held, so a missing line can be explained.
local WHY_ORDER = { COMMODITY = 0, NOREALMS = 0, NOHERE = 0, NOTHERE = 1, GAIN = 2, PROFIT = 3, SLOW = 4, CROWDED = 5 }
Flips.WHY_ORDER = WHY_ORDER

function Flips.BetterRealm(key, group, realmName)
    if not ns.db or not key then return nil end
    group = group or ns.realmGroup
    realmName = realmName or GetNormalizedRealmName()
    local data = ns.Prices.ActiveData()
    if data and data.commodities and data.commodities[key] then return nil, { reason = "COMMODITY" } end
    local herePrice = ns.Prices:Get(key, group, realmName)
    local hereResell = herePrice and ResellPrice(herePrice)
    if not hereResell or hereResell <= 0 then return nil, { reason = "NOHERE" } end
    local here = Util.AfterCut(hereResell)
    local minProfit = ns.db.settings.dealMinProfit or (5 * 10000)
    local minSales = ns.db.settings.flipMinSales or 1
    local best, why
    local function Why(w)
        if not why or WHY_ORDER[w.reason] > WHY_ORDER[why.reason] then why = w end
    end
    for _, r in ipairs(Flips.PlayerRealms()) do
        if r.group ~= group then
            local price = ns.Prices:Get(key, r.group, r.realm)
            local resell = price and ResellPrice(price)
            if not resell or resell <= 0 then
                Why({ reason = "NOTHERE", realm = r.realm })
            elseif resell < hereResell * (1 + MIN_GAIN) then
                Why({ reason = "GAIN", realm = r.realm, percent = math.floor((resell / hereResell - 1) * 100) })
            elseif Util.AfterCut(resell) - here < minProfit then
                Why({ reason = "PROFIT", realm = r.realm, gain = Util.AfterCut(resell) - here, need = minProfit })
            elseif (price.salesPerDay or 0) < minSales then
                Why({ reason = "SLOW", realm = r.realm, sales = price.salesPerDay or 0, need = minSales })
            elseif ns.Deals.ResellChance(price.salesPerDay, price.listed) < MIN_CHANCE then
                Why({ reason = "CROWDED", realm = r.realm, listed = price.listed or 0 })
            else
                local there = Util.AfterCut(resell)
                local gain = there - here
                if not best or gain > best.gain then
                    best = { realm = r.realm, here = here, there = there, gain = gain, salesPerDay = price.salesPerDay }
                end
            end
        end
    end
    if best then return best end
    return nil, why or { reason = "NOREALMS" }
end

-- Your items (this character's bags, bank and reagent bank, and the warband
-- bank) that sell for clearly more on another of your realms, as rows for
-- the Other realms view: { key, count, price = here each, resell = there
-- each, profit = gain for all of them, salesPerDay, buyRealm = this realm,
-- sellRealm, own = true }, most gained first.
function Flips:YourItems()
    if ownCache and Util.Now() - ownAt < 60 then return ownCache end
    local items = {}
    if ns.db and ns.charKey and #Flips.PlayerRealms() >= 2 then
        local here = GetNormalizedRealmName()
        for key, entry in pairs(ns.Inventory:GetTotals()) do
            local mine = entry.where[ns.charKey]
            local count = (entry.where.warband and entry.where.warband.bank or 0)
            if mine then count = count + (mine.bags or 0) + (mine.bank or 0) + (mine.reagentBank or 0) end
            if count > 0 and not ns.Rules:IsJunk(key) then
                local better = Flips.BetterRealm(key)
                if better then
                    items[#items + 1] = {
                        key = key, count = count, price = better.here, resell = better.there,
                        profit = better.gain * count, salesPerDay = better.salesPerDay,
                        buyRealm = here, sellRealm = better.realm, own = true,
                    }
                end
            end
        end
        table.sort(items, function(a, b)
            if a.profit ~= b.profit then return a.profit > b.profit end
            return a.key < b.key
        end)
    end
    ownCache, ownAt = items, Util.Now()
    return items
end

function Flips:IsStale()
    return cache ~= nil and Util.Now() - cacheAt > 60
end

-- Bags and listings don't change flips, so inventory changes no longer
-- rebuild the list.
for _, event in ipairs({ "AC_SCAN_COMPLETE", "AC_DATA_CHANGED" }) do
    ns.Events:On(event, function() Flips:Invalidate() end)
end
-- Your items do depend on your bags.
ns.Events:On("AC_INVENTORY_CHANGED", function() ownCache = nil end)
ns.Events:On("AC_LIVE_PRICE", function()
    if cache and Util.Now() - cacheAt > LIVE_REBUILD_AFTER then cache = nil end
end)
