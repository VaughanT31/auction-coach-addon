-- Auction Coach - the repost list: items the player posts again and again.
-- Each item has a floor (never post below it) and, for stacks, the most to
-- post at once. The panel at the Auction House (UI/RepostPanel.lua) posts
-- them one click at a time at Auction Coach's suggested price.
--
--   db.repost = { { k = item key, floor = copper, max = items per post
--                   (0 = all in bags), added = time }, ... } in list order

local _, ns = ...
local L, Util = ns.L, ns.Util

local Repost = {}
ns.Repost = Repost

-- A new item's floor: this share of its usual price, so a crashed market
-- isn't followed all the way down. The player can change it.
local DEFAULT_FLOOR = 0.7
local SILVER = 100

local function List()
    ns.db.repost = ns.db.repost or {}
    return ns.db.repost
end

local function Find(key)
    for i, entry in ipairs(List()) do
        if entry.k == key then return entry, i end
    end
    return nil
end

function Repost:Has(key)
    return Find(key) ~= nil
end

function Repost:Add(key, link)
    if not key or Find(key) then return false end
    if link then ns.db.links[key] = ns.db.links[key] or link end
    local floor = 0
    local s = ns.Rules:SuggestPrice(key, link or ns.db.links[key])
    local usual = s.usual or s.lowest
    if usual and usual > 0 then floor = math.floor(usual * DEFAULT_FLOOR / SILVER) * SILVER end
    table.insert(List(), { k = key, floor = floor, max = 0, added = Util.Now() })
    Util.Print(L.REPOST_ADDED:format(Util.NamedLink(key) or link or key, Util.FormatMoneyIcons(floor)))
    ns.Events:Fire("AC_REPOST_CHANGED")
    return true
end

function Repost:Remove(key)
    local _, i = Find(key)
    if not i then return end
    table.remove(List(), i)
    ns.Events:Fire("AC_REPOST_CHANGED")
end

function Repost:Set(key, field, value)
    local entry = Find(key)
    if not entry then return end
    entry[field] = math.max(0, math.floor(value or 0))
    ns.Events:Fire("AC_REPOST_CHANGED")
end

-- Moves an item up (-1) or down (+1) the list: Post next goes in list order.
function Repost:Move(key, step)
    local list = List()
    local _, i = Find(key)
    local j = i and i + step
    if not j or j < 1 or j > #list then return end
    list[i], list[j] = list[j], list[i]
    ns.Events:Fire("AC_REPOST_CHANGED")
end

-- The list with what to do about each item on this character:
-- { { key, link, count, floor, max, suggestion, price, status }, ... }
--   READY     in the bags, priced at or above the floor
--   NONE      none in the bags
--   FLOOR     the price today is under the floor: kept, not posted
--   HOLD      prices crashed, worth waiting (Rules:SuggestPrice)
--   VENDOR    a vendor pays more than the AH after its cut
--   NO_PRICE  no price yet: a scan or a search fixes that
function Repost:Items()
    local items = {}
    local char = ns.db.characters[ns.charKey]
    local bags = char and char.inventory.bags or {}
    for _, entry in ipairs(List()) do
        local link = ns.db.links[entry.k]
        local s = ns.Rules:SuggestPrice(entry.k, link)
        local item = { key = entry.k, link = link, count = bags[entry.k] or 0, floor = entry.floor or 0,
                       max = entry.max or 0, suggestion = s, price = s.price }
        if item.count == 0 then
            item.status = "NONE"
        elseif s.action == "VENDOR" then
            item.status = "VENDOR"
        elseif not s.price then
            item.status = "NO_PRICE"
        elseif s.price < item.floor then
            item.status = "FLOOR"
        elseif s.action == "HOLD" then
            item.status = "HOLD"
        else
            item.status = "READY"
        end
        items[#items + 1] = item
    end
    return items
end

-- Items posted in the last 48 hours on this realm, in the bags now and not
-- on the list: likely candidates.
function Repost:Suggestions()
    local found, seen = {}, {}
    local char = ns.db.characters[ns.charKey]
    local bags = char and char.inventory.bags or {}
    for _, post in ipairs(ns.db.posts[ns.realmGroup] or {}) do
        local key = post.k
        if key and not seen[key] and (bags[key] or 0) > 0 and not Find(key) then
            seen[key] = true
            found[#found + 1] = key
        end
    end
    return found
end

function Repost:AddSuggestions()
    for _, key in ipairs(self:Suggestions()) do self:Add(key) end
end

ns:RegisterCommand("repost", function()
    if ns.RepostPanel then ns.RepostPanel:Open() end
end, L.HELP_REPOST)
