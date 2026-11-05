-- Auction Coach - Lumber Crafting data: how much lumber each character and
-- the warband bank hold, which lumber recipes each character knows, and the
-- game's own "where to learn it" text. The recipes themselves come from
-- Data/LumberRecipes.lua (built from the game's tables by
-- tools/lumber_recipes.py), so recipes nobody knows are listed too.
--
--   ns.db.lumber = {
--     chars   { [charKey] = { [lumberID] = count } }  bags, bank, reagent bank
--     warband { [lumberID] = count }  read while a bank is open
--     known   { [charKey] = { [spellID] = true } }
--     read    { [charKey] = { [professionID] = time } }  when the window was last read
--     sources { [spellID] = text }  the game's source text for unlearned recipes
--   }
--
-- Lumber is Warbound: it never goes on the AH, so it is counted here rather
-- than by Data/Inventory.lua, which only records tradeable items.

local _, ns = ...
local Util = ns.Util

local Lumber = {}
ns.Lumber = Lumber

local bankOpen = false

local function Call(fn, ...)
    if not fn then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
    return nil
end

local function Data()
    return ns.LumberRecipes or { lumber = {}, tiers = {}, recipes = {} }
end

-- Recipes by profession skill line, built once: { [professionID] = { spellID, ... } }.
local byProfession
function Lumber.ByProfession()
    if byProfession then return byProfession end
    byProfession = {}
    for spellID, recipe in pairs(Data().recipes) do
        local list = byProfession[recipe.p] or {}
        byProfession[recipe.p] = list
        list[#list + 1] = spellID
    end
    return byProfession
end

-- ---------------------------------------------------------------------
-- Lumber counts
-- ---------------------------------------------------------------------

local function Count(itemID, accountBank)
    local count = C_Item and C_Item.GetItemCount and Call(C_Item.GetItemCount, itemID, true, false, true, accountBank)
    return tonumber(count) or 0
end

function Lumber:ScanCounts()
    if not ns.db or not ns.charKey then return end
    local data = ns.db.lumber
    local mine = {}
    for _, itemID in ipairs(Data().lumber) do
        local own = Count(itemID, false)
        if own > 0 then mine[itemID] = own end
        -- The warband bank's count is only sure while a bank is open.
        if bankOpen then
            local warband = math.max(0, Count(itemID, true) - own)
            data.warband[itemID] = warband > 0 and warband or nil
        end
    end
    data.chars[ns.charKey] = mine
    ns.Events:Fire("AC_LUMBER_CHANGED")
end

-- Lumber of one type held across characters and the warband bank.
function Lumber.Owned(itemID)
    local data = ns.db and ns.db.lumber
    if not data then return 0 end
    local total = data.warband[itemID] or 0
    for _, counts in pairs(data.chars) do total = total + (counts[itemID] or 0) end
    return total
end

-- ---------------------------------------------------------------------
-- Known recipes, read when a profession window is open
-- ---------------------------------------------------------------------

function Lumber:ReadProfession()
    if not ns.db or not ns.charKey or not ns.Recipes.ViewingOwn() then return 0 end
    local trade = C_TradeSkillUI
    local base = Call(trade.GetBaseProfessionInfo)
    local professionID = type(base) == "table" and base.professionID or nil
    if not professionID then
        local child = Call(trade.GetChildProfessionInfo)
        professionID = type(child) == "table" and child.parentProfessionID or nil
    end
    local spells = professionID and Lumber.ByProfession()[professionID]
    if not spells then return 0 end

    local data = ns.db.lumber
    local known = data.known[ns.charKey] or {}
    local count = 0
    for _, spellID in ipairs(spells) do
        local info = Call(trade.GetRecipeInfo, spellID)
        if type(info) == "table" then
            count = count + 1
            if info.learned then
                known[spellID] = true
            else
                known[spellID] = nil
                local text = Call(trade.GetRecipeSourceText, spellID)
                if type(text) == "string" and text ~= "" then data.sources[spellID] = text end
            end
        end
    end
    if count == 0 then return 0 end
    data.known[ns.charKey] = known
    data.read[ns.charKey] = data.read[ns.charKey] or {}
    data.read[ns.charKey][professionID] = Util.Now()
    ns.Events:Fire("AC_LUMBER_CHANGED")
    return count
end

-- Characters (keys) who know a recipe.
function Lumber.KnownBy(spellID)
    local who = {}
    for charKey, known in pairs(ns.db and ns.db.lumber.known or {}) do
        if known[spellID] then who[#who + 1] = charKey end
    end
    table.sort(who)
    return who
end

-- Characters (keys) who have a profession but don't know the recipe.
function Lumber.CouldLearn(spellID, professionID)
    local who = {}
    for charKey, char in pairs(ns.db and ns.db.characters or {}) do
        local known = ns.db.lumber.known[charKey]
        if not (known and known[spellID]) then
            for _, prof in ipairs(char.professions or {}) do
                if prof.skillLine == professionID then
                    who[#who + 1] = charKey
                    break
                end
            end
        end
    end
    table.sort(who)
    return who
end

-- The game's source text, one line, without colour codes.
function Lumber.SourceText(spellID)
    local text = ns.db and ns.db.lumber.sources[spellID]
    if not text then return nil end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|n", "  "):gsub("|T.-|t", "")
    return (text:gsub("%s+$", ""))
end

-- ---------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------

local function CountSoon()
    Util.Debounce("lumberCounts", 1, function() Lumber:ScanCounts() end)
end

local readTimer
local function ReadSoon()
    if readTimer then readTimer:Cancel() end
    readTimer = C_Timer.NewTimer(1.5, function()
        readTimer = nil
        Lumber:ReadProfession()
    end)
end

ns.Events:On("AC_LOGIN", CountSoon)
ns.Events:On("BAG_UPDATE_DELAYED", CountSoon)
ns.Events:On("BANKFRAME_OPENED", function()
    bankOpen = true
    CountSoon()
end)
ns.Events:On("BANKFRAME_CLOSED", function()
    Lumber:ScanCounts()
    bankOpen = false
end)
ns.Events:On("PLAYERBANKSLOTS_CHANGED", CountSoon)
ns.Events:On("TRADE_SKILL_SHOW", ReadSoon)
ns.Events:On("TRADE_SKILL_LIST_UPDATE", ReadSoon)
