-- Auction Coach - craft or sell: which of your characters' recipes make
-- more on the AH than their materials, from the recipes learned in
-- Data/Recipes.lua and current prices.
--
-- Materials are valued at what they sell for, even ones you already own:
-- crafting with them means not selling them, or at what a vendor charges
-- when that's cheaper (Data/VendorPrices.lua). Each slot uses its cheapest
-- quality. The crafted item is valued at what it would sell for after the
-- AH cut, for the quantity one craft makes on average: its market value,
-- or the lowest listing when that's lower, since a new post has to undercut
-- it. (An item with a few cheap listings and a big overpriced stack has a
-- market value far above what anything actually sells for.)
--
-- Quality: when the game told Data/Recipes.lua which quality the character
-- makes (reagents and consumables, where each quality is its own item),
-- that quality's item is the one priced. If concentration makes a better
-- quality, what that's worth is worked out too, but never counted in the
-- profit: concentration is limited and the player decides where it goes.
-- Gear keeps one item ID for every quality, so it is priced as one item.

local _, ns = ...
local Util = ns.Util

local Crafting = {}
ns.Crafting = Crafting

local MAX_ITEMS = 100

local cache

-- What a material costs: its AH value, or the vendor's price when cheaper.
local function PriceOf(itemID)
    local price = ns.Prices:Get(tostring(itemID))
    return (ns.VendorPrices.Cheapest(itemID, price and price.value or nil))
end
Crafting.PriceOf = PriceOf

-- What a crafted item sells for: its market value, or the lowest listing
-- when that's lower.
local function SellPriceOf(itemID)
    local price = ns.Prices:Get(tostring(itemID))
    if not price or not price.value then return nil, price end
    local each = price.value
    if price.min and price.min > 0 and price.min < each then each = price.min end
    return each, price
end
Crafting.SellPriceOf = SellPriceOf

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

-- The item this character makes: the quality item when known, else the
-- recipe's output.
function Crafting.OutputOf(recipe)
    if recipe.qo and recipe.bq and recipe.qo[recipe.bq] then return recipe.qo[recipe.bq], recipe.bq end
    return recipe.o, nil
end

-- One recipe priced: { key, recipeID, profession, char, cost, value,
-- profit, each, salesPerDay, quality, concentration = { quality, cost, extra } }
-- or nil when anything is missing a price.
function Crafting.Evaluate(recipeID, recipe, charKey)
    local outputID, quality = Crafting.OutputOf(recipe)
    local key = tostring(outputID)
    if ns.Rules:IsJunk(key) then return nil end
    local each, price = SellPriceOf(outputID)
    -- A quality item nobody has priced yet: fall back to the recipe's
    -- output rather than showing nothing.
    if not each and outputID ~= recipe.o then
        outputID, quality = recipe.o, nil
        key = tostring(outputID)
        each, price = SellPriceOf(outputID)
    end
    if not each then return nil end
    local cost = MaterialCost(recipe)
    if not cost then return nil end
    local made = recipe.q or 1
    local value = math.floor(Util.AfterCut(each) * made)
    local e = {
        key = key,
        recipeID = recipeID,
        recipe = recipe,
        profession = recipe.p,
        char = charKey,
        cost = math.floor(cost),
        value = value,
        profit = value - math.floor(cost),
        each = each,
        salesPerDay = price and price.salesPerDay,
        quality = quality,
    }
    if quality and recipe.cq and recipe.qo[recipe.cq] then
        local better = SellPriceOf(recipe.qo[recipe.cq])
        if better and better > each then
            e.concentration = {
                quality = recipe.cq,
                cost = recipe.cc,
                extra = math.floor(Util.AfterCut(better - each) * made),
            }
        end
    end
    return e
end

-- Every item key a recipe can make, so the tooltip on any quality of it
-- finds the recipe.
local function OutputKeys(recipe)
    local keys = { [tostring(recipe.o)] = true }
    for _, itemID in pairs(recipe.qo or {}) do keys[tostring(itemID)] = true end
    return keys
end

-- Every priced recipe of this realm group's characters, best profit first
-- (losses last), one row per crafted item. Returns { items, recipes =
-- how many recipes are known at all }.
function Crafting:List()
    if cache then return cache end
    local result = { items = {}, recipes = 0, byKey = {} }
    if not ns.db or not ns.realmGroup then return result end
    local best = {}
    for charKey, known in pairs(ns.db.recipes or {}) do
        local char = ns.db.characters[charKey]
        if char and char.realmGroup == ns.realmGroup then
            for recipeID, recipe in pairs(known) do
                result.recipes = result.recipes + 1
                local e = Crafting.Evaluate(recipeID, recipe, charKey)
                if e and (not best[e.key] or e.profit > best[e.key].profit) then
                    best[e.key] = e
                    e.outputs = OutputKeys(recipe)
                end
            end
        end
    end
    for _, e in pairs(best) do result.items[#result.items + 1] = e end
    table.sort(result.items, function(a, b)
        if a.profit ~= b.profit then return a.profit > b.profit end
        return a.key < b.key
    end)
    for i = #result.items, MAX_ITEMS + 1, -1 do result.items[i] = nil end
    for _, e in ipairs(result.items) do
        for key in pairs(e.outputs) do
            if not result.byKey[key] then result.byKey[key] = e end
        end
    end
    cache = result
    return result
end

-- The best known recipe for a crafted item key (any of its qualities),
-- priced, or nil.
function Crafting:ForOutput(key)
    return self:List().byKey[key]
end

-- One character's recipes, priced, best profit first: for Today's Plan,
-- which can only suggest what the character you're on can craft.
function Crafting:ForCharacter(charKey)
    local list = {}
    for recipeID, recipe in pairs(ns.db and ns.db.recipes and ns.db.recipes[charKey] or {}) do
        local e = Crafting.Evaluate(recipeID, recipe, charKey)
        if e then list[#list + 1] = e end
    end
    table.sort(list, function(a, b)
        if a.profit ~= b.profit then return a.profit > b.profit end
        return a.key < b.key
    end)
    return list
end

-- How many crafts the materials in have = { [key] = count } allow, using
-- the cheapest quality of each slot first. Returns the count and the
-- materials it uses, { [key] = count }.
function Crafting.Possible(recipe, have)
    local crafts = math.huge
    for _, slot in ipairs(recipe.r or {}) do
        local owned = 0
        for _, id in ipairs(slot.ids) do owned = owned + (have[tostring(id)] or 0) end
        crafts = math.min(crafts, math.floor(owned / slot.n))
    end
    if crafts == math.huge or crafts <= 0 then return 0, {} end
    return crafts, Crafting.Uses(recipe, crafts, have)
end

-- The materials crafts of a recipe take from have, cheapest quality first.
function Crafting.Uses(recipe, crafts, have)
    local uses = {}
    for _, slot in ipairs(recipe.r or {}) do
        local need = slot.n * crafts
        local ids = {}
        for _, id in ipairs(slot.ids) do ids[#ids + 1] = id end
        table.sort(ids, function(a, b)
            local pa, pb = PriceOf(a) or math.huge, PriceOf(b) or math.huge
            if pa ~= pb then return pa < pb end
            return a < b
        end)
        for _, id in ipairs(ids) do
            local key = tostring(id)
            local take = math.min(need, (have[key] or 0) - (uses[key] or 0))
            if take > 0 then
                uses[key] = (uses[key] or 0) + take
                need = need - take
            end
            if need <= 0 then break end
        end
    end
    return uses
end

function Crafting:Invalidate()
    cache = nil
end

for _, event in ipairs({ "AC_SCAN_COMPLETE", "AC_LIVE_PRICE", "AC_DATA_CHANGED", "AC_RECIPES_CHANGED" }) do
    ns.Events:On(event, function() Crafting:Invalidate() end)
end
