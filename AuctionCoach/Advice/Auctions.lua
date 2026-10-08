-- Auction Coach - what to do with each of your own auctions.
-- Used by the Auctions tab and by Today's Plan (REPOST and CANCEL steps),
-- so both always give the same advice.
--
-- Reads char.auctionList, saved by Data/Inventory.lua whenever Blizzard
-- sends the owned auctions (opening the AH, posting, cancelling). Auctions
-- of the same item at the same price are one entry.
--
-- Each entry gets an action:
--   KEEP    still the cheapest (or tied), nothing to do
--   REPOST  someone listed lower: cancel and post again at a new price
--   CANCEL  undercut, and a vendor now pays more than the AH would: cancel,
--           collect it from the mail and sell it to a vendor
--   WAIT    undercut, but reposting is not worth it today (prices crashed,
--           or it gets undercut faster than the player checks back): let it
--           run, it comes back by mail if it does not sell
--   UNKNOWN no price for this item yet

local _, ns = ...
local Util = ns.Util

local Auctions = {}
ns.Auctions = Auctions

-- Display order: things to do first.
local ORDER = { REPOST = 1, CANCEL = 2, WAIT = 3, KEEP = 4, UNKNOWN = 5 }

-- The player's newest post of each item on this realm group, from
-- Data/Sales.lua, so a lower price seen before posting is not taken as an
-- undercut.
local function NewestPosts()
    local newest = {}
    for _, post in ipairs(ns.db.posts[ns.realmGroup] or {}) do
        local current = newest[post.k]
        if not current or post.p > current.p then newest[post.k] = post end
    end
    return newest
end

local function Advise(entry, posts)
    local price = ns.Prices:Get(entry.key)
    local s = ns.Rules:SuggestPrice(entry.key, ns.db.links[entry.key])
    entry.suggestion = s
    if not price or not price.min then
        entry.action = "UNKNOWN"
        return
    end
    entry.lowest, entry.lowestAt = price.min, price.minAt

    local post = posts[entry.key]
    local seenSincePost = not post or (price.minAt or 0) > post.p
    if price.min >= entry.unit or not seenSincePost then
        entry.action = "KEEP"
    elseif s.action == "VENDOR" and s.vendor and s.vendor > 0 then
        entry.action = "CANCEL"
        entry.vendorGold = s.vendor * entry.quantity
    elseif s.action == "POST" and s.price and s.price < entry.unit and s.contested ~= "HEAVY" then
        entry.action = "REPOST"
        entry.newPrice = s.price
    else
        entry.action = "WAIT"
    end
end

-- Returns {
--   items      { { key, unit, quantity, auctions, left, action, lowest,
--                  lowestAt, newPrice, vendorGold, suggestion }, ... },
--              things to do first, then by value
--   undercut   how many entries are REPOST, CANCEL or WAIT
--   at         when the auctions were last read (nil = never)
-- }
function Auctions:List()
    local result = { items = {}, undercut = 0 }
    local char = ns.db and ns.charKey and ns.db.characters[ns.charKey]
    if not char or not char.auctionList then return result end
    result.at = char.auctionsAt

    local groups = {}
    for _, a in ipairs(char.auctionList) do
        local id = a.k .. "@" .. a.v
        local entry = groups[id]
        if not entry then
            entry = { key = a.k, unit = a.v, quantity = 0, auctions = 0 }
            groups[id] = entry
            result.items[#result.items + 1] = entry
        end
        entry.quantity = entry.quantity + a.q
        entry.auctions = entry.auctions + 1
        -- The soonest to expire, so "time left" never overstates.
        if a.left and (not entry.left or a.left < entry.left) then entry.left = a.left end
    end

    local posts = NewestPosts()
    for _, entry in ipairs(result.items) do
        Advise(entry, posts)
        if entry.action == "REPOST" or entry.action == "CANCEL" or entry.action == "WAIT" then
            result.undercut = result.undercut + 1
        end
    end

    table.sort(result.items, function(a, b)
        if ORDER[a.action] ~= ORDER[b.action] then return ORDER[a.action] < ORDER[b.action] end
        local va, vb = a.unit * a.quantity, b.unit * b.quantity
        if va ~= vb then return va > vb end
        return a.key < b.key
    end)
    return result
end

-- Seconds left as "12h", "40m" or "<1m"; nil when unknown.
function Auctions.FormatLeft(seconds)
    if not seconds then return nil end
    if seconds >= 3600 then return math.floor(seconds / 3600) .. "h" end
    if seconds >= 60 then return math.floor(seconds / 60) .. "m" end
    return "<1m"
end

-- What a listing makes after the AH cut if all of it sells.
function Auctions.ListedValue(entry)
    return Util.AfterCut(entry.unit * entry.quantity)
end
