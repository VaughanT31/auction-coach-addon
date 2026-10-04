-- Auction Coach - shared helpers: money and age formatting, item keys, timers.

local _, ns = ...
local L = ns.L

local Util = {}
ns.Util = Util

local COPPER_PER_SILVER = 100
local COPPER_PER_GOLD = 10000

-- Blizzard keeps 5% of every Auction House sale.
Util.AH_CUT = 0.05

-- Item ID of the generic "Pet Cage" item that caged battle pets list under.
Util.PET_CAGE_ITEM_ID = 82800

function Util.Now()
    return GetServerTime()
end

function Util.Print(msg)
    print("|cffffd100" .. L.ADDON_TITLE .. ":|r " .. msg)
end

-- Plain money text: "1,250g", "12g 50s", "75s", "8c".
-- Above 10g the silver is dropped because nobody cares about it at that size.
function Util.FormatMoney(copper)
    copper = math.floor(tonumber(copper) or 0)
    if copper >= 10 * COPPER_PER_GOLD then
        local gold = math.floor(copper / COPPER_PER_GOLD + 0.5)
        return L.MONEY_GOLD:format(BreakUpLargeNumbers(gold))
    elseif copper >= COPPER_PER_GOLD then
        local gold = math.floor(copper / COPPER_PER_GOLD)
        local silver = math.floor((copper % COPPER_PER_GOLD) / COPPER_PER_SILVER)
        if silver == 0 then
            return L.MONEY_GOLD:format(gold)
        end
        return L.MONEY_GOLD_SILVER:format(gold, silver)
    elseif copper >= COPPER_PER_SILVER then
        return L.MONEY_SILVER:format(math.floor(copper / COPPER_PER_SILVER))
    end
    return L.MONEY_COPPER:format(copper)
end

function Util.FormatAge(timestamp)
    local age = Util.Now() - (timestamp or 0)
    if age < 120 then
        return L.AGE_JUST_NOW
    elseif age < 3600 then
        return L.AGE_MINUTES:format(math.floor(age / 60))
    elseif age < 2 * 86400 then
        return L.AGE_HOURS:format(math.floor(age / 3600))
    end
    return L.AGE_DAYS:format(math.floor(age / 86400))
end

function Util.FormatDuration(seconds)
    if seconds >= 60 then
        return L.SCAN_MINUTES:format(math.ceil(seconds / 60))
    end
    return L.SCAN_SECONDS:format(math.max(1, math.ceil(seconds)))
end

-- What the seller actually receives after the AH cut.
function Util.AfterCut(copper)
    return math.floor((copper or 0) * (1 - Util.AH_CUT))
end

-- ---------------------------------------------------------------------
-- Item keys
--
-- Items are keyed by more than the item ID so different versions of the
-- same item are priced separately:
--   "12345"         most items (reagents, consumables, crafting qualities
--                   already have their own item IDs)
--   "12345:i639"    gear, keyed by item level
--   "p:1234:25"     caged battle pets, keyed by species and level
-- IDs only, never names, so keys work in every client language.
-- ---------------------------------------------------------------------

local GEAR_CLASSES = {
    [Enum.ItemClass.Weapon] = true,
    [Enum.ItemClass.Armor] = true,
}
if Enum.ItemClass.Profession then
    GEAR_CLASSES[Enum.ItemClass.Profession] = true
end

-- True for items whose value depends on item level. Uses instant item info
-- so it works for items the client has not cached yet.
function Util.IsGear(itemID)
    local _, _, _, equipLoc, _, classID = ns.Compat.GetItemInfoInstant(itemID)
    if not classID or not GEAR_CLASSES[classID] then return false end
    return equipLoc ~= nil and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE"
end

-- Returns itemKey, itemID (itemID is nil for battle pets).
function Util.ItemKeyFromLink(link)
    if not link then return nil end

    local species, level = link:match("battlepet:(%d+):(%d+)")
    if species then
        return "p:" .. species .. ":" .. level, nil
    end

    local itemID = tonumber(link:match("item:(%d+)"))
    if not itemID then return nil end

    if Util.IsGear(itemID) then
        local ilvl = ns.Compat.GetDetailedItemLevelInfo(link)
        if ilvl and ilvl > 0 then
            return itemID .. ":i" .. ilvl, itemID
        end
    end
    return tostring(itemID), itemID
end

-- Key for an item that has no gear or pet variants. Returns nil when the
-- item needs a full link to be keyed correctly.
function Util.SimpleItemKey(itemID)
    if not itemID or itemID == Util.PET_CAGE_ITEM_ID or Util.IsGear(itemID) then
        return nil
    end
    return tostring(itemID)
end

function Util.ItemIDFromKey(key)
    if not key or key:sub(1, 2) == "p:" then return nil end
    return tonumber(key:match("^(%d+)"))
end

-- ---------------------------------------------------------------------
-- Timers
-- ---------------------------------------------------------------------

local debounceTimers = {}

-- Runs fn once, delay seconds after the last call with the same id.
function Util.Debounce(id, delay, fn)
    local existing = debounceTimers[id]
    if existing then existing:Cancel() end
    debounceTimers[id] = C_Timer.NewTimer(delay, function()
        debounceTimers[id] = nil
        fn()
    end)
end
