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

local GOLD_ICON = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t"
local SILVER_ICON = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t"
local COPPER_ICON = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t"

-- Same rounding as FormatMoney, with the game's coin icons instead of letters.
function Util.FormatMoneyIcons(copper)
    copper = math.floor(tonumber(copper) or 0)
    if copper >= 10 * COPPER_PER_GOLD then
        return BreakUpLargeNumbers(math.floor(copper / COPPER_PER_GOLD + 0.5)) .. GOLD_ICON
    elseif copper >= COPPER_PER_GOLD then
        local gold = math.floor(copper / COPPER_PER_GOLD)
        local silver = math.floor((copper % COPPER_PER_GOLD) / COPPER_PER_SILVER)
        if silver == 0 then return gold .. GOLD_ICON end
        return gold .. GOLD_ICON .. " " .. silver .. SILVER_ICON
    elseif copper >= COPPER_PER_SILVER then
        return math.floor(copper / COPPER_PER_SILVER) .. SILVER_ICON
    end
    return copper .. COPPER_ICON
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
--   "12345:b6652.12817"  gear, keyed by its bonus IDs (sorted). These
--                   decide item level, sockets and tertiary stats, and the
--                   Blizzard API reports the same IDs, so keys match the
--                   Auction Coach server exactly.
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

-- True for items whose value depends on their bonus IDs. Uses instant item info
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
        local bonuses = Util.BonusIDs(link)
        if #bonuses > 0 then
            return itemID .. ":b" .. table.concat(bonuses, "."), itemID
        end
    end
    return tostring(itemID), itemID
end

-- Bonus IDs from an item link, sorted. Link fields after "item:":
--   1 itemID, 2 enchant, 3-6 gems, 7 suffix, 8 unique, 9 link level,
--   10 spec, 11 modifiers mask, 12 item context, 13 number of bonus IDs,
--   14... the bonus IDs, then modifiers.
function Util.BonusIDs(link)
    local bonuses = {}
    local body = link and link:match("item:([%-%d:]+)")
    if not body then return bonuses end
    local fields = {}
    for field in (body .. ":"):gmatch("([^:]*):") do
        fields[#fields + 1] = field
    end
    local count = tonumber(fields[13]) or 0
    for i = 14, 13 + count do
        local id = tonumber(fields[i])
        if id then bonuses[#bonuses + 1] = id end
    end
    table.sort(bonuses)
    return bonuses
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

-- True when the link's display name has real text in it. Links of items
-- the client has not loaded yet have an empty name, sometimes with only a
-- crafting quality icon left inside the brackets ("[|A:...|a]").
function Util.LinkHasName(link)
    if not link then return false end
    local name = link:match("|h%[(.-)%]|h")
    if not name then return false end
    name = name:gsub("|A.-|a", ""):gsub("|T.-|t", ""):gsub("%s+", "")
    return name ~= ""
end

-- A link with a name in it for this item key, or nil while the item is
-- still loading. Asks the client to load it and stores the complete link
-- once available. Callers redraw on AC_ITEM_NAMES_LOADED.
local namesPending = false

-- An item string for a key, for items never seen in the player's bags
-- (deals, for example). Gear gets its bonus IDs in field 13 onwards, so
-- the name and item level come out right. nil for battle pets.
function Util.ItemStringFromKey(key)
    local itemID = Util.ItemIDFromKey(key)
    if not itemID then return nil end
    local bonuses = key:match(":b([%d%.]+)$")
    if not bonuses then return "item:" .. itemID end
    local list = { strsplit(".", bonuses) }
    return "item:" .. itemID .. string.rep(":", 12) .. #list .. ":" .. table.concat(list, ":")
end

-- A coloured "[Name]" for a battle pet key, or nil while unknown.
local function PetName(key)
    local species = tonumber(key:match("^p:(%d+)"))
    local name = species and C_PetJournal and C_PetJournal.GetPetInfoBySpeciesID(species)
    if type(name) ~= "string" or name == "" then return nil end
    return "|cff0070dd[" .. name .. "]|r"
end

function Util.NamedLink(key)
    local link = ns.db and ns.db.links[key]
    if Util.LinkHasName(link) then return link end
    if key and key:sub(1, 2) == "p:" then return PetName(key) end
    link = link or Util.ItemStringFromKey(key)
    if link and link:find("item:") then
        local _, fresh = ns.Compat.GetItemInfo(link)
        if Util.LinkHasName(fresh) then
            ns.db.links[key] = fresh
            return fresh
        end
    end
    local itemID = Util.ItemIDFromKey(key)
    if itemID then
        ns.Compat.RequestLoadItemDataByID(itemID)
        namesPending = true
    end
    return nil
end

function Util.NamesPending()
    return namesPending
end

function Util.ClearNamesPending()
    namesPending = false
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
