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
--     },
--   }
--
-- Only the recipes of the expansion shown in the window are kept (the
-- newest by default), so SavedVariables stay small. Viewing someone else's
-- profession (a link or the guild list) is ignored. Recipes with no output
-- item (enchants, recrafts, salvage, gathering) aren't kept.

local _, ns = ...

local Recipes = {}
ns.Recipes = Recipes

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

-- Required reagent slots of a schematic: { { ids, n }, ... }, or nil when a
-- required slot can't be read.
function Recipes.ReadSlots(schematic)
    local slots = {}
    local basic = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic
    for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
        local required = slot.required
        if required == nil then required = basic ~= nil and slot.reagentType == basic end
        if required then
            local ids = {}
            for _, reagent in ipairs(slot.reagents or {}) do
                if reagent.itemID then ids[#ids + 1] = reagent.itemID end
            end
            -- Currency or other non-item costs can't be priced.
            if #ids == 0 then return nil end
            slots[#slots + 1] = { ids = ids, n = slot.quantityRequired or 1 }
        end
    end
    return slots
end

-- One recipe as stored, or nil when it isn't worth keeping.
function Recipes.Read(recipeID, professionName)
    local trade = C_TradeSkillUI
    local info = Call(trade.GetRecipeInfo, recipeID)
    if type(info) ~= "table" or not info.learned then return nil end
    if info.isRecraft or info.isSalvageRecipe or info.isGatheringRecipe or info.isDummyRecipe then return nil end
    local schematic = Call(trade.GetRecipeSchematic, recipeID, false)
    if type(schematic) ~= "table" or not schematic.outputItemID then return nil end
    local slots = Recipes.ReadSlots(schematic)
    if not slots or #slots == 0 then return nil end
    local qMin = schematic.quantityMin or 1
    local qMax = schematic.quantityMax or qMin
    local recipe = { o = schematic.outputItemID, q = (qMin + qMax) / 2, r = slots, p = professionName }
    Recipes.ReadQuality(recipeID, recipe)
    return recipe
end

-- Which quality this character makes, with and without concentration, and
-- which item each quality is. Only kept when the qualities are different
-- items (gear keeps one item ID, so its quality can't be priced apart).
function Recipes.ReadQuality(recipeID, recipe)
    local trade = C_TradeSkillUI
    local qualities = Call(trade.GetQualitiesForRecipe, recipeID)
    if type(qualities) ~= "table" or #qualities < 2 then return end
    local outputs, distinct, seen = {}, 0, {}
    for i, qualityID in ipairs(qualities) do
        local data = Call(trade.GetRecipeOutputItemData, recipeID, nil, nil, qualityID)
        local itemID = type(data) == "table" and data.itemID or nil
        if itemID then
            outputs[i] = itemID
            if not seen[itemID] then
                seen[itemID] = true
                distinct = distinct + 1
            end
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
