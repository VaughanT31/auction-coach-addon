-- Auction Coach - undercut timing: how long the player's listings stay the
-- cheapest before another seller posts below them.
--
-- When the player posts at or below the lowest price seen in the last few
-- minutes, a watch starts. Every later look at that item (a search at the
-- AH, or a full scan) either confirms the listing is still the cheapest or
-- finds a lower price from someone else. Checks only happen while the AH
-- is open, so the undercut lies between the last "still cheapest" time and
-- the first "undercut" time; records where that gap is wide are kept but
-- not used for the typical time.
--
-- Stored per realm group and item key, newest last:
--   db.undercuts[group][key] = { { p = posted, v = unit price, q = quantity,
--                                  ok = last seen still cheapest,
--                                  u = first seen undercut, by = that price,
--                                  s = first sale (Data/Sales.lua),
--                                  g = gone from the player's auctions (sold,
--                                      cancelled or expired) }, ... }
-- No character names are stored, so records can be shared as they are.

local _, ns = ...
local Util = ns.Util

local Undercuts = {}
ns.Undercuts = Undercuts

local MAX_RECORDS = 20
local WATCH_FOR = 48 * 3600        -- longest an auction can run
local FRESH = 15 * 60              -- a lowest price this old still counts at post time
local MAX_UNCERTAINTY = 2 * 3600   -- undercut time known to within this, or not used
local MIN_RECORDS = 3              -- undercut records needed for a typical time
local MAX_AGE = 30 * 86400
-- The owned auctions list can lag a fresh post by a moment.
local GONE_GRACE = 60

-- Session only: item key -> time a search showed no listings from others.
local checkedEmpty = {}

local function Records(groupKey, key, create)
    local byGroup = ns.db.undercuts[groupKey]
    if not byGroup then
        if not create then return nil end
        byGroup = {}
        ns.db.undercuts[groupKey] = byGroup
    end
    local list = byGroup[key]
    if not list and create then
        list = {}
        byGroup[key] = list
    end
    return list
end

local function IsOpen(r, now)
    return not r.u and not r.g and now - r.p < WATCH_FOR
end

-- Called by Data/Sales.lua for every post. unitPrice is per item.
function Undercuts:Posted(key, unitPrice, quantity, now)
    if not key or not unitPrice or unitPrice <= 0 then return end
    now = now or Util.Now()

    -- Only a listing that starts as the cheapest can be undercut.
    local price = ns.Prices:Get(key)
    local lowestFresh = price and price.min and price.minAt and now - price.minAt <= FRESH
    local aloneFresh = checkedEmpty[key] and now - checkedEmpty[key] <= FRESH
    if lowestFresh then
        if unitPrice > price.min then return end
    elseif not aloneFresh then
        return
    end

    local list = Records(ns.realmGroup, key, true)
    list[#list + 1] = { p = now, v = unitPrice, q = quantity or 1, ok = now }
    while #list > MAX_RECORDS do table.remove(list, 1) end
end

-- A look at the item's listings from other sellers. otherMin is their
-- lowest unit price, or nil when nobody else has it listed.
function Undercuts:Observe(groupKey, key, otherMin, now)
    if otherMin == nil and groupKey == ns.realmGroup then
        checkedEmpty[key] = now
    end
    local list = Records(groupKey, key, false)
    if not list then return end
    for _, r in ipairs(list) do
        if IsOpen(r, now) and now >= r.p then
            if otherMin and otherMin < r.v then
                r.u, r.by = now, otherMin
            else
                r.ok = now
            end
        end
    end
end

-- One of the player's posts sold (see Data/Sales.lua). Commodities can
-- sell in parts, so the watch stays open until the listing is gone.
function Undercuts:SoldPost(key, postedAt, now)
    local list = Records(ns.realmGroup, key, false)
    if not list then return end
    for _, r in ipairs(list) do
        if r.p == postedAt and not r.s then
            r.s = now
            return
        end
    end
end

-- The player's auction list was refreshed: listings no character on this
-- realm group still has are gone (sold, cancelled or expired).
function Undercuts:CheckGone(now)
    local byGroup = ns.db.undercuts[ns.realmGroup]
    if not byGroup then return end
    local listed = {}
    for _, char in pairs(ns.db.characters) do
        if char.realmGroup == ns.realmGroup and char.inventory and char.inventory.auctions then
            for key in pairs(char.inventory.auctions) do listed[key] = true end
        end
    end
    for key, list in pairs(byGroup) do
        if not listed[key] then
            for _, r in ipairs(list) do
                if IsOpen(r, now) and now - r.p > GONE_GRACE then r.g = now end
            end
        end
    end
end

-- Keys with an open watch on this realm group, for the full scan.
function Undercuts:Watched(groupKey)
    local keys = {}
    local now = Util.Now()
    for key, list in pairs(ns.db.undercuts[groupKey] or {}) do
        for _, r in ipairs(list) do
            if IsOpen(r, now) then
                keys[key] = true
                break
            end
        end
    end
    return keys
end

-- Typical time until the player's listings of this item get undercut.
-- Returns { seconds, undercut = n, posts = n }, or nil without enough data.
function Undercuts:Typical(key, groupKey)
    local list = Records(groupKey or ns.realmGroup, key, false)
    if not list then return nil end
    local now = Util.Now()
    local times, posts = {}, 0
    for _, r in ipairs(list) do
        if r.u then
            posts = posts + 1
            if r.u - r.ok <= MAX_UNCERTAINTY then
                times[#times + 1] = (r.ok + r.u) / 2 - r.p
            end
        elseif not IsOpen(r, now) then
            posts = posts + 1
        end
    end
    if #times < MIN_RECORDS then return nil end
    table.sort(times)
    local mid = math.floor((#times + 1) / 2)
    local median = (#times % 2 == 1) and times[mid] or (times[mid] + times[mid + 1]) / 2
    return { seconds = math.max(0, math.floor(median + 0.5)), undercut = #times, posts = posts }
end

function Undercuts:Prune()
    local cutoff = Util.Now() - MAX_AGE
    for groupKey, byGroup in pairs(ns.db.undercuts) do
        for key, list in pairs(byGroup) do
            while #list > 0 and list[1].p < cutoff do table.remove(list, 1) end
            if #list == 0 then byGroup[key] = nil end
        end
        if next(byGroup) == nil then ns.db.undercuts[groupKey] = nil end
    end
end

ns.Events:On("AC_DB_READY", function()
    Undercuts:Prune()
end)

-- Inventory rescans the owned auctions on the same event first (it loads
-- earlier), so the auctions lists are current here.
ns.Events:On("OWNED_AUCTIONS_UPDATED", function()
    if ns.db then Undercuts:CheckGone(Util.Now()) end
end)
