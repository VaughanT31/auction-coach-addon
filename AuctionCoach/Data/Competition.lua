-- Auction Coach - competition sampling.
-- Records the lowest price of an item over time and how often it changes.
-- A lowest price that changes many times an hour means sellers are
-- constantly undercutting each other.
--
-- Samples come from full scans (only for items the player owns, to keep
-- SavedVariables small) and from every item the player browses at the AH.

local _, ns = ...
local Util = ns.Util

local Competition = {}
ns.Competition = Competition

local MAX_SAMPLES = 16
local MIN_SAMPLE_GAP = 60          -- ignore repeat samples within a minute
local MAX_PAIR_GAP = 2 * 3600      -- samples further apart say nothing about undercuts
local MIN_OBSERVED = 30 * 60       -- need at least 30 minutes of watching
local MAX_AGE = 7 * 86400          -- forget samples older than a week

Competition.LEVELS = { "LOW", "MEDIUM", "HIGH", "EXTREME" }

local function GetEntry(groupKey, key)
    local comp = ns:GetRealmData(groupKey).competition
    local entry = comp[key]
    if not entry then
        -- s is a flat list of time, price pairs: { t1, p1, t2, p2, ... }
        entry = { s = {} }
        comp[key] = entry
    end
    return entry
end

function Competition:Sample(groupKey, key, minPrice, timestamp)
    if not minPrice or minPrice <= 0 then return end
    local s = GetEntry(groupKey, key).s
    local n = #s
    if n >= 2 and timestamp - s[n - 1] < MIN_SAMPLE_GAP and s[n] == minPrice then
        return
    end
    s[n + 1] = timestamp
    s[n + 2] = minPrice
    while #s > MAX_SAMPLES * 2 do
        table.remove(s, 1)
        table.remove(s, 1)
    end
end

-- Number of different sellers seen in the latest live check.
function Competition:RecordSellers(groupKey, key, sellers, timestamp)
    local entry = GetEntry(groupKey, key)
    entry.sellers = sellers
    entry.sellersAt = timestamp
end

-- Returns { level = "LOW".."EXTREME", rate = changes per hour, sellers = n|nil },
-- or nil when there is not enough data yet.
function Competition:Score(key, groupKey)
    groupKey = groupKey or ns.realmGroup
    local realm = ns.db and ns.db.realms[groupKey]
    local entry = realm and realm.competition[key]
    if not entry then return nil end

    local s = entry.s
    local observed, changes = 0, 0
    for i = 3, #s, 2 do
        local gap = s[i] - s[i - 2]
        if gap > 0 and gap <= MAX_PAIR_GAP then
            observed = observed + gap
            if s[i + 1] ~= s[i - 1] then
                changes = changes + 1
            end
        end
    end
    if observed < MIN_OBSERVED then return nil end

    local rate = changes / (observed / 3600)
    local level
    if rate < 0.5 then
        level = "LOW"
    elseif rate < 1.5 then
        level = "MEDIUM"
    elseif rate < 4 then
        level = "HIGH"
    else
        level = "EXTREME"
    end

    local sellers
    if entry.sellersAt and Util.Now() - entry.sellersAt < 86400 then
        sellers = entry.sellers
    end
    return { level = level, rate = rate, sellers = sellers }
end

-- Drop old samples so SavedVariables does not grow forever.
function Competition:Prune()
    local cutoff = Util.Now() - MAX_AGE
    for _, realm in pairs(ns.db.realms) do
        for key, entry in pairs(realm.competition) do
            local s = entry.s
            while #s >= 2 and s[1] < cutoff do
                table.remove(s, 1)
                table.remove(s, 1)
            end
            if #s == 0 and not (entry.sellersAt and entry.sellersAt >= cutoff) then
                realm.competition[key] = nil
            end
        end
    end
end

ns.Events:On("AC_DB_READY", function()
    Competition:Prune()
end)
