-- Auction Coach - market calendar hints: what the day of the week and the
-- Darkmoon Faire usually do to prices, from the server's calendar numbers in
-- Data.lua (calendar section, desktop app data only). Two item groups:
-- consumables (item class 0) and trade goods (item class 7).
--
-- Only says what has happened before, never a forecast, and only when the
-- effect is big enough to matter (MIN_EFFECT).

local _, ns = ...
local Util, Compat = ns.Util, ns.Compat

local Calendar = {}
ns.Calendar = Calendar

-- Percent changes smaller than this are noise.
local MIN_EFFECT = 2
local GROUP_OF_CLASS = { [0] = "consumables", [7] = "tradegoods" }
local GROUPS = { "consumables", "tradegoods" }

local function Section()
    local data = ns.Prices.ActiveData()
    local calendar = data and data.calendar
    return type(calendar) == "table" and calendar or nil
end

-- 0 = Monday ... 6 = Sunday, by UTC day (the calendar's days are UTC).
function Calendar.Weekday(now)
    local wday = date("!*t", now or Util.Now()).wday -- 1 = Sunday
    return (wday + 5) % 7
end

-- True during a Darkmoon Faire week: from the first Sunday of the month,
-- for 7 days (UTC dates, the same rule the server uses).
function Calendar.FaireWeek(now)
    local t = date("!*t", now or Util.Now())
    local firstDayWday = (t.wday - 1 - (t.day - 1)) % 7 -- 0 = Sunday
    local firstSunday = 1 + (7 - firstDayWday) % 7
    return t.day >= firstSunday and t.day <= firstSunday + 6
end

-- The calendar group of an item ("consumables" / "tradegoods"), or nil.
function Calendar.GroupOf(key, link)
    if not key or key:sub(1, 2) == "p:" then return nil end
    -- The instant lookup works even before the item is cached.
    local classID = select(6, Compat.GetItemInfoInstant(link or Util.ItemIDFromKey(key)))
    return classID and GROUP_OF_CLASS[classID] or nil
end

-- For one group: { today = %, best = weekday, bestPercent = %, faire = % or
-- nil } or nil when the calendar has no weekday numbers for it.
function Calendar:ForGroup(group, now)
    local section = Section()
    local entry = section and group and section[group]
    if type(entry) ~= "table" or type(entry.p) ~= "table" or #entry.p ~= 7 then return nil end
    local best, bestPercent = 0, entry.p[1]
    for i = 2, 7 do
        if entry.p[i] > bestPercent then best, bestPercent = i - 1, entry.p[i] end
    end
    local result = { today = entry.p[self.Weekday(now) + 1], best = best, bestPercent = bestPercent }
    if entry.f and self.FaireWeek(now) and math.abs(entry.f) >= MIN_EFFECT then result.faire = entry.f end
    return result
end

-- What the calendar says about selling one item today, or nil when there's
-- nothing worth saying. { group, today, best, bestPercent, faire,
-- bestToday = true when today is usually the best day }
function Calendar:ForItem(key, link, now)
    local group = self.GroupOf(key, link)
    local info = group and self:ForGroup(group, now)
    if not info then return nil end
    info.group = group
    info.bestToday = info.best == self.Weekday(now)
    local worthSaying = (info.bestToday and info.bestPercent >= MIN_EFFECT)
        or (info.bestPercent - info.today >= MIN_EFFECT + 1)
        or info.faire
    return worthSaying and info or nil
end

-- Lines for Today's Plan: today's weekday effect per group, and the Faire.
function Calendar:PlanNotes(now)
    local Phrases = ns.Phrases
    local notes, today, faire = {}, {}, {}
    for _, group in ipairs(GROUPS) do
        local info = self:ForGroup(group, now)
        if info and math.abs(info.today) >= MIN_EFFECT then today[#today + 1] = { group = group, percent = info.today } end
        if info and info.faire then faire[#faire + 1] = { group = group, percent = info.faire } end
    end
    if #today > 0 then notes[#notes + 1] = Phrases.CalendarToday(self.Weekday(now), today) end
    if #faire > 0 then notes[#notes + 1] = Phrases.CalendarFaire(faire) end
    return notes
end
