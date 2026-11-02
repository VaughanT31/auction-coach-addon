-- Auction Coach - what multicraft, resourcefulness and ingenuity add to a
-- craft, on average. The game gives each recipe's chance of each stat; what
-- a proc is worth is an approximation, since the game doesn't say:
--   multicraft      extra items, between 1 and a constant times what one
--                   craft makes, so on average the middle of that
--   resourcefulness about 30% of the materials back
--   ingenuity       half of the concentration back
--
-- The constants and the stat names per language are adapted from CraftSim by
-- Florian Schneider (MIT), see ThirdParty/LICENSE-CraftSim.txt.

local _, ns = ...

local CraftStats = {}
ns.CraftStats = CraftStats

local RESOURCEFULNESS_SAVES = 0.30
local INGENUITY_REFUND = 0.5
local MULTICRAFT_CONSTANTS = { [1] = 2.1, [2] = 1.83, [5] = 1.875 }
local MULTICRAFT_DEFAULT = 2.5

-- The stats as the game names them in bonusStats, per client language.
local NAMES = {
    enUS = { "Multicraft", "Resourcefulness", "Ingenuity" },
    enGB = { "Multicraft", "Resourcefulness", "Ingenuity" },
    deDE = { "Mehrfachherstellung", "Einfallsreichtum", "Genialität" },
    esES = { "Multifabricación", "Inventiva", "Ingenio" },
    esMX = { "Fabricación múltiple", "Inventiva", "Ingenio" },
    frFR = { "Fabrication multiple", "Ingéniosité", "Inventivité" },
    itIT = { "Creazione multipla", "Parsimonia" },
    koKR = { "복수 제작", "지혜", "독창성" },
    ptBR = { "Multicriação", "Devolução de recursos", "Engenhosidade" },
    ruRU = { "Перепроизводство", "Находчивость", "Изобретательность" },
    zhCN = { "产能", "充裕", "奇思" },
    zhTW = { "複數製造", "精明" },
}

-- The chances (0 to 1) in a crafting operation's info:
-- multicraft, resourcefulness, ingenuity. A stat a recipe doesn't have is nil.
function CraftStats.Read(info)
    local names = NAMES[GetLocale()] or NAMES.enUS
    local found = {}
    for _, stat in ipairs(type(info) == "table" and info.bonusStats or {}) do
        local name, pct = stat.bonusStatName, stat.ratingPct
        local secret = issecretvalue and (issecretvalue(name) or issecretvalue(pct))
        if not secret and type(name) == "string" and type(pct) == "number" and pct > 0 then
            for i = 1, 3 do
                if names[i] and name:lower() == names[i]:lower() then found[i] = pct / 100 end
            end
        end
    end
    return found[1], found[2], found[3]
end

-- How many extra items one craft makes on average from multicraft.
function CraftStats.ExtraItems(recipe)
    if not recipe.mc then return 0 end
    local made = recipe.q or 1
    local most = (MULTICRAFT_CONSTANTS[made] or MULTICRAFT_DEFAULT) * made
    return recipe.mc * (1 + most) / 2
end

-- What materials resourcefulness saves one craft on average.
function CraftStats.Saved(recipe, cost)
    if not recipe.rs then return 0 end
    return math.floor(cost * recipe.rs * RESOURCEFULNESS_SAVES)
end

-- Concentration a craft costs on average after ingenuity, or nil.
function CraftStats.Concentration(recipe)
    if not recipe.cc then return nil end
    return math.floor(recipe.cc * (1 - (recipe.ing or 0) * INGENUITY_REFUND) + 0.5)
end
