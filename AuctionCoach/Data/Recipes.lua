-- Auction Coach - the recipes each character knows, learned when their
-- profession window is open (the game only lists recipes then).
--
--   ns.db.recipes[charKey] = {
--     [recipeID] = {
--       o  output item ID
--       q  how many one craft makes (average of min and max)
--       r  { { ids = { itemID, ... }, n = quantity }, ... }  required
--          reagents per slot; ids are the slot's quality versions
--       p  profession name (the expansion line, "Midnight Tailoring")
--       For recipes whose quality changes the item made (reagents,
--       consumables), when the game says:
--       qo { [quality] = itemID }  the item made at each quality
--       bq quality this character makes with the cheapest materials
--       cq quality with concentration, when that's higher
--       cc concentration it costs
--       v  Recipes.VERSION when read
--     },
--   }
--
-- Only the recipes of the expansion shown in the window are kept (the
-- newest by default), so SavedVariables stay small. Viewing someone else's
-- profession (a link or the guild list) is ignored. Recipes with no output
-- item (recrafts, salvage, gathering) aren't kept. Enchants are kept as the
-- scroll they make (Data/EnchantScrolls.lua).

local _, ns = ...

local Recipes = {}
ns.Recipes = Recipes

-- Bumped when how recipes are read changes. Before 2, materials that come
-- in qualities could be read as the Spark and left out of the cost.
Recipes.VERSION = 2

-- A recipe read before the Spark fix may be missing materials from its
-- cost, so it isn't priced until the profession window is opened again.
function Recipes.Stale(recipe)
    return recipe.sp ~= nil and (recipe.v or 1) < 2
end

local function Call(fn, ...)
    if not fn then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
    return nil
end

local function ViewingOwn()
    local trade = C_TradeSkillUI
    if not trade or not Call(trade.IsTradeSkillReady) then return false end
    if Call(trade.IsTradeSkillLinked) or Call(trade.IsTradeSkillGuild) or Call(trade.IsNPCCrafting) then return false end
    return true
end

-- A season's Spark: the required slot you pick a "modifying" reagent into
-- (the Spark slot on crafted gear), rather than a basic material. Sparks
-- come with the season, so they're never counted as a crafting cost.
-- Midnight's basic materials that come in qualities (Sunfire Silk and the
-- like) are also "modified reagent" slots, so the slot's reagent type
-- decides when the game gives one.
function Recipes.IsSpark(slot)
    if slot.required ~= true then return false end
    local modifying = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Modifying
    if slot.reagentType ~= nil and modifying ~= nil then return slot.reagentType == modifying end
    local modified = Enum and Enum.TradeskillSlotDataType and Enum.TradeskillSlotDataType.ModifiedReagent
    return modified ~= nil and slot.dataSlotType == modified
end

-- Required reagent slots of a schematic: { { ids, n }, ... }, or nil when a
-- required slot can't be read. Second: the Spark, { ids, n }, or nil.
function Recipes.ReadSlots(schematic)
    local slots, spark = {}, nil
    local basic = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic
    for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
        local required = slot.required
        if required == nil then required = basic ~= nil and slot.reagentType == basic end
        if Recipes.IsSpark(slot) then
            spark = spark or { ids = {}, n = 0 }
            spark.n = spark.n + (slot.quantityRequired or 1)
            for _, reagent in ipairs(slot.reagents or {}) do
                if reagent.itemID then spark.ids[#spark.ids + 1] = reagent.itemID end
            end
        elseif required then
            local ids = {}
            for _, reagent in ipairs(slot.reagents or {}) do
                if reagent.itemID then ids[#ids + 1] = reagent.itemID end
            end
            -- Currency or other non-item costs can't be priced.
            if #ids == 0 then return nil end
            slots[#slots + 1] = { ids = ids, n = slot.quantityRequired or 1 }
        end
    end
    return slots, spark
end

-- One recipe as stored, or nil when it isn't worth keeping.
function Recipes.Read(recipeID, professionName)
    local trade = C_TradeSkillUI
    local info = Call(trade.GetRecipeInfo, recipeID)
    if type(info) ~= "table" or not info.learned then return nil end
    if info.isRecraft or info.isSalvageRecipe or info.isGatheringRecipe or info.isDummyRecipe then return nil end
    local schematic = Call(trade.GetRecipeSchematic, recipeID, false)
    if type(schematic) ~= "table" then return nil end
    -- Enchants make no item; the scroll they make on Enchanting Vellum is
    -- what sells (1.0.11, Data/EnchantScrolls.lua).
    local scrolls = not schematic.outputItemID and info.isEnchantingRecipe and Recipes.EnchantScrolls(recipeID)
    if not schematic.outputItemID and not scrolls then return nil end
    local slots, spark = Recipes.ReadSlots(schematic)
    if not slots or #slots == 0 then return nil end
    local qMin = schematic.quantityMin or 1
    local qMax = schematic.quantityMax or qMin
    local recipe = { o = schematic.outputItemID or scrolls[1], q = (qMin + qMax) / 2, r = slots, p = professionName,
                     sp = spark, v = Recipes.VERSION }
    if scrolls then
        Recipes.ApplyQuality(recipeID, recipe, scrolls)
    else
        Recipes.ReadQuality(recipeID, recipe)
    end
    return recipe
end

-- The scrolls an enchant recipe makes, one per quality, or nil when it
-- isn't in the table (or isn't an enchant that makes one).
function Recipes.EnchantScrolls(recipeID)
    local op = Call(C_TradeSkillUI.GetCraftingOperationInfo, recipeID, {}, nil, false)
    local id = type(op) == "table" and op.craftingDataID or nil
    return id and ns.EnchantScrolls and ns.EnchantScrolls[id] or nil
end

-- Which quality this character makes, with and without concentration, and
-- which item each quality is. Only kept when the qualities are different
-- items (gear keeps one item ID, so its quality can't be priced apart).
function Recipes.ReadQuality(recipeID, recipe)
    local trade = C_TradeSkillUI
    local qualities = Call(trade.GetQualitiesForRecipe, recipeID)
    if type(qualities) ~= "table" or #qualities < 2 then return end
    local outputs = {}
    for i, qualityID in ipairs(qualities) do
        local data = Call(trade.GetRecipeOutputItemData, recipeID, nil, nil, qualityID)
        outputs[i] = type(data) == "table" and data.itemID or nil
    end
    Recipes.ApplyQuality(recipeID, recipe, outputs)
end

-- outputs: { [quality] = item ID }. Sets qo, bq and, with concentration, cq
-- and cc.
function Recipes.ApplyQuality(recipeID, recipe, outputs)
    local trade = C_TradeSkillUI
    local distinct, seen = 0, {}
    for _, itemID in pairs(outputs) do
        if not seen[itemID] then
            seen[itemID] = true
            distinct = distinct + 1
        end
    end
    if distinct < 2 then return end
    local base = Call(trade.GetCraftingOperationInfo, recipeID, {}, nil, false)
    local quality = type(base) == "table" and tonumber(base.craftingQuality) or nil
    if not quality or not outputs[quality] then return end
    recipe.qo, recipe.bq = outputs, quality
    local focused = Call(trade.GetCraftingOperationInfo, recipeID, {}, nil, true)
    local better = type(focused) == "table" and tonumber(focused.craftingQuality) or nil
    if better and better > quality and outputs[better] then
        recipe.cq = better
        recipe.cc = tonumber(focused.concentrationCost) or tonumber(base.concentrationCost)
    end
end

-- Reads every recipe of the expansion shown in the profession window.
function Recipes:Learn()
    if not ns.db or not ns.charKey or not ViewingOwn() then return 0 end
    local trade = C_TradeSkillUI
    local child = Call(trade.GetChildProfessionInfo)
    local lineID = type(child) == "table" and child.professionID or nil
    if not lineID then return 0 end
    local name = child.professionName or child.parentProfessionName

    local known = ns.db.recipes[ns.charKey] or {}
    ns.db.recipes[ns.charKey] = known
    local count = 0
    for _, recipeID in ipairs(Call(trade.GetAllRecipeIDs) or {}) do
        local line = Call(trade.GetTradeSkillLineForRecipe, recipeID)
        if line == lineID then
            local recipe = Recipes.Read(recipeID, name)
            if recipe then
                known[recipeID] = recipe
                count = count + 1
            end
        end
    end
    if count > 0 then ns.Events:Fire("AC_RECIPES_CHANGED") end
    return count
end

-- The window fills its list in steps, so learning waits for it to settle.
local learnTimer
local function LearnSoon()
    if learnTimer then learnTimer:Cancel() end
    learnTimer = C_Timer.NewTimer(1, function()
        learnTimer = nil
        Recipes:Learn()
    end)
end

ns.Events:On("TRADE_SKILL_SHOW", LearnSoon)
ns.Events:On("TRADE_SKILL_LIST_UPDATE", LearnSoon)
