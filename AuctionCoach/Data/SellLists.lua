-- Auction Coach - sell lists: items to sell on another of the player's
-- realms. Planned on realm A (your own items in the Other realms view that
-- pay more on B), moved through the warband bank (UI/SellListPanel.lua),
-- and posted on B through the repost list (Data/Repost.lua), coming off the
-- list as they're posted.
--
--   db.sellLists[realmGroup] = { [key] = { n = how many, added = time,
--                                          from = realm planned on } }

local _, ns = ...
local Util = ns.Util

local SellLists = {}
ns.SellLists = SellLists

local function Lists()
    ns.db.sellLists = ns.db.sellLists or {}
    return ns.db.sellLists
end

-- The realm group of one of the player's realms, from its name.
function SellLists.GroupOf(realmName)
    for _, r in ipairs(ns.Flips.PlayerRealms()) do
        if r.realm == realmName then return r.group end
    end
    return nil
end

-- A realm name in a group, for showing it.
function SellLists.RealmOf(group)
    for _, r in ipairs(ns.Flips.PlayerRealms()) do
        if r.group == group then return r.realm end
    end
    return group
end

-- Adds count of key to the list of the realm group that should sell it.
function SellLists:Add(group, key, count)
    if not group or not key or (count or 0) <= 0 then return false end
    local list = Lists()[group] or {}
    Lists()[group] = list
    local entry = list[key]
    if entry then
        entry.n = math.max(entry.n, count)
    else
        list[key] = { n = count, added = Util.Now(), from = GetNormalizedRealmName() }
    end
    ns.Events:Fire("AC_SELL_LISTS_CHANGED")
    return true
end

function SellLists:Remove(group, key)
    local list = Lists()[group]
    if list and list[key] then
        list[key] = nil
        if not next(list) then Lists()[group] = nil end
        ns.Events:Fire("AC_SELL_LISTS_CHANGED")
    end
end

-- This realm's list: { [key] = entry } (empty table when none).
function SellLists:Here()
    return Lists()[ns.realmGroup] or {}
end

-- Items on other realms' lists: { { group, key, n } }.
function SellLists:Elsewhere()
    local result = {}
    for group, list in pairs(Lists()) do
        if group ~= ns.realmGroup then
            for key, entry in pairs(list) do
                result[#result + 1] = { group = group, key = key, n = entry.n }
            end
        end
    end
    return result
end

function SellLists:Count(group)
    local n = 0
    for _ in pairs(Lists()[group or ns.realmGroup] or {}) do n = n + 1 end
    return n
end

-- A post on this realm: what's posted comes off its list (Data/Sales.lua).
function SellLists:Posted(key, quantity)
    local list = Lists()[ns.realmGroup]
    local entry = list and list[key]
    if not entry then return end
    entry.n = entry.n - math.max(1, quantity or 1)
    if entry.n <= 0 then
        list[key] = nil
        if not next(list) then Lists()[ns.realmGroup] = nil end
    end
    ns.Events:Fire("AC_SELL_LISTS_CHANGED")
end
