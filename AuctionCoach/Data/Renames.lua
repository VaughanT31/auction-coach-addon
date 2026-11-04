-- Auction Coach - renamed characters.
--
-- Everything per character is saved under "Name-Realm", so after a rename
-- the old name stays behind as a second character, and its gold counts
-- twice. A rename keeps the character's GUID, so on login an older entry
-- with the same GUID is folded into the new name: its ledger and gold
-- history carry on under the new name and the old entry goes.
--
-- Entries saved before 1.2.2 have no GUID. For those, "/ac renamed OldName"
-- on the renamed character does the same by hand.

local _, ns = ...
local L = ns.L
local Util = ns.Util

local Renames = {}
ns.Renames = Renames

local function AddPairs(into, from)
    for cat, entry in pairs(from or {}) do
        local mine = into[cat]
        if mine then
            mine[1] = (mine[1] or 0) + (entry[1] or 0)
            mine[2] = (mine[2] or 0) + (entry[2] or 0)
        else
            into[cat] = { entry[1] or 0, entry[2] or 0 }
        end
    end
end

local function MergeLedger(old, new)
    local ledger = ns.db.ledger
    if not ledger or not ledger[old] then return end
    local from, into = ledger[old], ledger[new]
    ledger[old] = nil
    if not into then
        ledger[new] = from
        return
    end
    into.since = math.min(into.since or from.since or 0, from.since or into.since or 0)
    into.days = into.days or {}
    for day, cats in pairs(from.days or {}) do
        into.days[day] = into.days[day] or {}
        AddPairs(into.days[day], cats)
    end
    into.all = into.all or {}
    AddPairs(into.all, from.all)
    if from.week then
        if not into.week or (from.week.start or 0) > (into.week.start or 0) then
            into.week = from.week
        elseif from.week.start == into.week.start then
            AddPairs(into.week.c, from.week.c)
        end
    end
end

-- Past days keep the old name's gold under the new name. A day with both
-- (the day of the rename) keeps the new one, so it isn't counted twice.
local function MergeGoldDays(old, new)
    for _, day in pairs(ns.db.goldDays or {}) do
        local chars = day.chars
        if chars and chars[old] then
            if chars[new] then
                day.total = (day.total or 0) - chars[old]
            else
                chars[new] = chars[old]
            end
            chars[old] = nil
        end
    end
end

function Renames:Fold(old, new)
    local db = ns.db
    local from, into = db.characters[old], db.characters[new]
    if from and not into then
        db.characters[new] = from
    elseif from and into then
        -- The new name's own scans are newer; keep the old one's only where
        -- the new name has nothing yet (professions until they're opened).
        for key, value in pairs(from) do
            if into[key] == nil then into[key] = value end
        end
    end
    db.characters[old] = nil

    if db.recipes and db.recipes[old] then
        db.recipes[new] = db.recipes[new] or db.recipes[old]
        db.recipes[old] = nil
    end
    local skip = db.settings and db.settings.planSkipChars
    if skip and skip[old] then
        skip[new] = true
        skip[old] = nil
    end
    MergeLedger(old, new)
    MergeGoldDays(old, new)
end

-- Runs on login before anything else reads the characters.
function Renames:OnLogin()
    local guid = UnitGUID("player")
    if not guid or not ns.db or not ns.charKey then return end
    for key, char in pairs(ns.db.characters) do
        if key ~= ns.charKey and char.guid == guid then
            self:Fold(key, ns.charKey)
            Util.Print(L.RENAMED_AUTO:format(Util.ShortName(key), Util.ShortName(ns.charKey)))
        end
    end
    local me = ns.db.characters[ns.charKey]
    if me then me.guid = guid end
end

-- "/ac renamed OldName" or "/ac renamed OldName-Realm".
local function Find(input)
    local wanted = input:lower():gsub("%s", "")
    local matches = {}
    for key in pairs(ns.db.characters) do
        local lower = key:lower():gsub("%s", "")
        if lower == wanted then return key end
        if (lower:match("^[^%-]+") or lower) == wanted then matches[#matches + 1] = key end
    end
    if #matches == 1 then return matches[1] end
    return nil, #matches
end

ns:RegisterCommand("renamed", function(args)
    if not ns.db or not ns.charKey then return end
    if not args or args == "" then
        Util.Print(L.RENAMED_USAGE)
        return
    end
    local key, count = Find(args)
    if not key then
        Util.Print(count and count > 1 and L.RENAMED_MANY:format(args) or L.RENAMED_NONE:format(args))
        return
    end
    if key == ns.charKey then
        Util.Print(L.RENAMED_SELF)
        return
    end
    Renames:Fold(key, ns.charKey)
    if ns.GoldHistory then ns.GoldHistory:Snapshot() end
    Util.Print(L.RENAMED_DONE:format(key, Util.ShortName(ns.charKey)))
    ns.Events:Fire("AC_INVENTORY_CHANGED")
end, L.HELP_RENAMED)
