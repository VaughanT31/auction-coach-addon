-- Auction Coach - craft or sell: which of your characters' recipes make
-- more on the AH than their materials, from the recipes learned in
-- Data/Recipes.lua and current prices.
--
-- Materials are valued at what they sell for, even ones you already own:
-- crafting with them means not selling them. Each slot uses its cheapest
-- quality. The crafted item is valued at its market value after the AH
-- cut, for the quantity one craft makes on average; quality bonuses from
-- skill or concentration aren't counted, so a skilled crafter may do a bit
-- better than shown.

local _, ns = ...
local Util = ns.Util

local Crafting = {}
ns.Crafting = Crafting

local MAX_ITEMS = 100

local cache

local function PriceOf(itemID)
    local price = ns.Prices:Get(tostring(itemID))
    return price and price.value or nil, price
end

-- Cost of one craft's materials, or nil when a material has no price.
local function MaterialCost(recipe)
    local total = 0
    for _, slot in ipairs(recipe.r or {}) do
        local cheapest
        for _, id in ipairs(slot.ids) do
            local each = PriceOf(id)
            if each and (not cheapest or each < cheapest) then cheapest = each end
        end
        if not cheapest then return nil end
        total = total + cheapest * slot.n
    end
    return total
end

-- One recipe priced: { key, recipeID, profession, char, cost, value,
-- profit, salesPerDay } or nil when anything is missing a price.
function Crafting.Evaluate(recipeID, recipe, charKey)
    local key = tostring(recipe.o)
    if ns.Rules:IsJunk(key) then return nil end
    local each, price = PriceOf(recipe.o)
    if not each then return nil end
    local cost = MaterialCost(recipe)
    if not cost then return nil end
    local value = math.floor(Util.AfterCut(each) * (recipe.q or 1))
    return {
        key = key,
        recipeID = recipeID,
        profession = recipe.p,
        char = charKey,
        cost = math.floor(cost),
        value = value,
        profit = value - math.floor(cost),
        salesPerDay = price and price.salesPerDay,
    }
end

-- Every priced recipe of this realm group's characters, best profit first
-- (losses last), one row per crafted item. Returns { items, recipes =
-- how many recipes are known at all }.
function Crafting:List()
    if cache then return cache end
    local result = { items = {}, recipes = 0 }
    if not ns.db or not ns.realmGroup then return result end
    local best = {}
    for charKey, known in pairs(ns.db.recipes or {}) do
        local char = ns.db.characters[charKey]
        if char and char.realmGroup == ns.realmGroup then
            for recipeID, recipe in pairs(known) do
                result.recipes = result.recipes + 1
                local e = Crafting.Evaluate(recipeID, recipe, charKey)
                if e and (not best[e.key] or e.profit > best[e.key].profit) then best[e.key] = e end
            end
        end
    end
    for _, e in pairs(best) do result.items[#result.items + 1] = e end
    table.sort(result.items, function(a, b)
        if a.profit ~= b.profit then return a.profit > b.profit end
        return a.key < b.key
    end)
    for i = #result.items, MAX_ITEMS + 1, -1 do result.items[i] = nil end
    cache = result
    return result
end

-- The best known recipe for a crafted item key, priced, or nil.
function Crafting:ForOutput(key)
    for _, e in ipairs(self:List().items) do
        if e.key == key then return e end
    end
    return nil
end

function Crafting:Invalidate()
    cache = nil
end

for _, event in ipairs({ "AC_SCAN_COMPLETE", "AC_LIVE_PRICE", "AC_DATA_CHANGED", "AC_RECIPES_CHANGED" }) do
    ns.Events:On(event, function() Crafting:Invalidate() end)
end
