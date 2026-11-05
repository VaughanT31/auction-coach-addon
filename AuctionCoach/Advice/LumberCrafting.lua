-- Auction Coach - Lumber Crafting: is a lumber recipe worth crafting?
--
-- Lumber is Warbound, so it has no AH price and isn't counted as a cost.
-- It is the real limit instead: you only have so much of it. So each
-- recipe shows the gold per lumber:
--
--   (the decor's lowest listing after the AH cut - the other materials) / lumber used
--
-- The list is sorted by how many of the decor sell a day, fastest first:
-- what sells is what's worth spending lumber on.
--
-- The other materials are priced like Craft or sell does (Advice/Crafting.lua):
-- the cheapest quality in each slot, at its AH value or a vendor's price.
-- The decor is valued at its lowest listing right now (a search at the AH
-- beats the desktop app's hourly price), since a new post has to match or
-- undercut it. Its usual lowest price is kept to show when someone is
-- selling well under it. Every recipe in Data/LumberRecipes.lua is priced,
-- known or not.
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

-- The lowest listing is this far under the usual lowest: someone undercut hard.
LumberCrafting.UNDERCUT = 0.8

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
    local price = ns.Prices:Get(tostring(recipe.o))
    local each = price and ((price.min and price.min > 0) and price.min or price.value) or nil
    e.each = each
    e.usual = price and (price.usualMin or price.value)
    e.undercut = each and e.usual and each < e.usual * LumberCrafting.UNDERCUT or false
    e.salesPerDay = price and price.salesPerDay
    e.lowestAt = price and price.minAt
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

-- Most sold a day first; no sales data last. Ties: more gold per lumber.
local function Sort(a, b)
    local sa, sb = a.salesPerDay or -1, b.salesPerDay or -1
    if sa ~= sb then return sa > sb end
    local pa, pb = a.perLumber or -math.huge, b.perLumber or -math.huge
    if pa ~= pb then return pa > pb end
    if a.expansion ~= b.expansion then return a.expansion > b.expansion end
    return a.name < b.name
end

-- Every lumber recipe priced, most sold a day first.
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
