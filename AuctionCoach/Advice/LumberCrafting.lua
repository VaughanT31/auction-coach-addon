-- Auction Coach - Lumber Crafting: is a lumber recipe worth crafting?
--
-- Lumber is Warbound, so it has no AH price and isn't counted as a cost.
-- It is the real limit instead: you only have so much of it. So recipes
-- are ranked by gold per lumber:
--
--   (what the decor sells for after the AH cut - the other materials) / lumber used
--
-- The other materials are priced like Craft or sell does (Advice/Crafting.lua):
-- the cheapest quality in each slot, at its AH value or a vendor's price.
-- The decor is valued at its market value or the lowest listing when that's
-- lower. Every recipe in Data/LumberRecipes.lua is priced, known or not.
--
-- Verdicts:
--   WORTH     makes gold and sells at least once a day
--   SLOW      makes gold but sells less than once a day
--   LOSS      the other materials cost more than it sells for
--   NO_MATS   a material has no price yet
--   NO_PRICE  nobody is selling the decor, so there's no price to go on

local _, ns = ...
local Util = ns.Util

local LumberCrafting = {}
ns.LumberCrafting = LumberCrafting

-- Sells at least this many a day to count as worth it.
LumberCrafting.MIN_SALES = 1

local RANK = { WORTH = 1, SLOW = 2, LOSS = 3, NO_MATS = 4, NO_PRICE = 5 }
LumberCrafting.RANK = RANK

local cache

-- Other materials of one craft: total cost (nil when one has no price) and
-- each slot priced, { { id, n, each }, ... } with the cheapest quality.
function LumberCrafting.Materials(recipe)
    local total, slots = 0, {}
    for _, slot in ipairs(recipe.r or {}) do
        local cheapestID, cheapest
        for _, id in ipairs(slot.ids) do
            local each = ns.Crafting.PriceOf(id)
            if each and (not cheapest or each < cheapest) then cheapestID, cheapest = id, each end
        end
        slots[#slots + 1] = { id = cheapestID or slot.ids[1], n = slot.n, each = cheapest }
        if cheapest and total then
            total = total + cheapest * slot.n
        else
            total = nil
        end
    end
    return total and math.floor(total) or nil, slots
end

-- Status of a recipe for this account: "known" when a character knows it,
-- "learnable" when one has the profession, else "none".
function LumberCrafting.Status(spellID, recipe)
    local knownBy = ns.Lumber.KnownBy(spellID)
    if #knownBy > 0 then return "known", knownBy end
    local could = ns.Lumber.CouldLearn(spellID, recipe.p)
    if #could > 0 then return "learnable", could end
    return "none", {}
end

function LumberCrafting.Evaluate(spellID, recipe)
    local lumberID, lumber = nil, 0
    for _, wood in ipairs(recipe.w) do
        lumberID = lumberID or wood[1]
        lumber = lumber + wood[2]
    end
    local tier = ns.LumberRecipes.tiers[recipe.t] or {}
    local e = {
        spellID = spellID,
        recipe = recipe,
        key = tostring(recipe.o),
        name = recipe.n,
        tierName = tier[1],
        expansion = tier[2] or 0,
        lumberID = lumberID,
        lumber = lumber,
        recipeItem = recipe.s > 0 and recipe.s or nil,
    }
    e.status, e.chars = LumberCrafting.Status(spellID, recipe)
    e.cost, e.materials = LumberCrafting.Materials(recipe)
    local each, price = ns.Crafting.SellPriceOf(recipe.o)
    e.each = each
    e.salesPerDay = price and price.salesPerDay
    if e.recipeItem then
        local recipePrice = ns.Prices:Get(tostring(e.recipeItem))
        e.recipePrice = recipePrice and recipePrice.value
    end
    e.owned = 0
    for _, wood in ipairs(recipe.w) do
        local crafts = math.floor(ns.Lumber.Owned(wood[1]) / wood[2])
        e.crafts = e.crafts and math.min(e.crafts, crafts) or crafts
        if wood[1] == lumberID then e.owned = ns.Lumber.Owned(wood[1]) end
    end

    if not each then
        e.verdict = "NO_PRICE"
    elseif not e.cost then
        e.verdict = "NO_MATS"
    else
        e.value = math.floor(Util.AfterCut(each) * (recipe.q or 1))
        e.profit = e.value - e.cost
        e.perLumber = lumber > 0 and math.floor(e.profit / lumber) or e.profit
        if e.profit <= 0 then
            e.verdict = "LOSS"
        elseif (e.salesPerDay or 0) < LumberCrafting.MIN_SALES then
            e.verdict = "SLOW"
        else
            e.verdict = "WORTH"
        end
    end
    return e
end

local function Sort(a, b)
    if RANK[a.verdict] ~= RANK[b.verdict] then return RANK[a.verdict] < RANK[b.verdict] end
    if (a.perLumber or 0) ~= (b.perLumber or 0) then return (a.perLumber or 0) > (b.perLumber or 0) end
    if a.expansion ~= b.expansion then return a.expansion > b.expansion end
    return a.name < b.name
end

-- Every lumber recipe priced, best gold per lumber first.
function LumberCrafting:All()
    if cache then return cache end
    local list = {}
    for spellID, recipe in pairs(ns.LumberRecipes and ns.LumberRecipes.recipes or {}) do
        list[#list + 1] = LumberCrafting.Evaluate(spellID, recipe)
    end
    table.sort(list, Sort)
    cache = list
    return list
end

-- The list for a view ("known", "learnable" = known or learnable, "all")
-- and lumber type (item ID or nil). Returns the rows and counts
-- { worth, shown, total }.
function LumberCrafting:List(view, lumberID)
    local rows, worth = {}, 0
    local all = self:All()
    for _, e in ipairs(all) do
        local inView = view == "all" or e.status == "known" or (view == "learnable" and e.status == "learnable")
        local uses = not lumberID
        if lumberID then
            for _, wood in ipairs(e.recipe.w) do
                if wood[1] == lumberID then uses = true end
            end
        end
        if inView and uses then
            rows[#rows + 1] = e
            if e.verdict == "WORTH" then worth = worth + 1 end
        end
    end
    return rows, { worth = worth, shown = #rows, total = #all }
end

function LumberCrafting:Invalidate()
    cache = nil
end

for _, event in ipairs({ "AC_SCAN_COMPLETE", "AC_LIVE_PRICE", "AC_DATA_CHANGED", "AC_LUMBER_CHANGED" }) do
    ns.Events:On(event, function() LumberCrafting:Invalidate() end)
end
