-- Auction Coach - the cheapest mix of material qualities for each quality a
-- recipe can make (0.12).
--
-- The game decides the quality of a craft from your skill plus a bonus for
-- higher-quality materials, and C_TradeSkillUI.GetCraftingOperationInfo
-- says what quality any mix of materials gives. Auction Coach never works
-- the rules out itself; it asks the game:
--
--   1. Every quality slot at its lowest quality: the starting skill.
--   2. Each slot filled with each higher quality in turn: how much skill one
--      unit of that quality adds. The bonus grows evenly with the number of
--      units, so this is all it needs to know.
--   3. Every way of mixing qualities in each slot, priced at what the
--      materials sell for, keeping the cheapest mix for each amount of
--      skill. Only mixes that add skill for more gold are kept.
--   4. For each quality, a binary search along those mixes, asking the game
--      each time, finds the cheapest one that reaches it. With concentration
--      too, since concentration can reach a quality with cheaper materials.
--
-- Slots that have only one quality are always needed, so they're added to
-- the cost as they are. Materials count at what they sell for, even ones
-- you own, as in Craft or sell.
--
-- Picker.Plan returns:
--   { qualities = { { quality, cost, mix, concentration }, ... }, fixed,
--     fixedItems = { { itemID, n }, ... }, baseQuality, maxQuality }
--   mix = { { slot, itemID, n }, ... } (slot is the schematic's slot index)
-- or nil and a reason ("noquality", "noprice", "noinfo").

local _, ns = ...

local Picker = {}
ns.MaterialPicker = Picker

local SCALE = 10                    -- skill is kept in tenths
local MAX_COMBOS = 4000             -- mixes tried per slot, so a huge slot can't stall the game

-- A material's AH value, or the vendor's price when that's cheaper.
local function PriceOf(itemID)
    local price = ns.Prices and ns.Prices:Get(tostring(itemID))
    return (ns.VendorPrices.Cheapest(itemID, price and price.value or nil))
end
Picker.PriceOf = PriceOf

local function Call(fn, ...)
    if not fn then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
    return nil
end

-- One material for GetCraftingOperationInfo, in whichever shape this client
-- builds them.
local function ReagentInfo(itemID, dataSlotIndex, quantity)
    local make = Professions and Professions.CreateCraftingReagentInfo
    local made = make and Call(make, itemID, dataSlotIndex, quantity)
    if type(made) == "table" then return made end
    return { itemID = itemID, reagent = { itemID = itemID }, dataSlotIndex = dataSlotIndex, quantity = quantity }
end

-- The game's answer for a mix: quality, total skill, concentration cost.
-- Replaced by the tests.
function Picker.Ask(recipeID, reagents, concentration)
    local list = {}
    for _, r in ipairs(reagents) do list[#list + 1] = ReagentInfo(r.itemID, r.dataSlotIndex, r.n) end
    local info = Call(C_TradeSkillUI.GetCraftingOperationInfo, recipeID, list, nil, concentration == true)
    if type(info) ~= "table" then return nil end
    local quality = tonumber(info.craftingQuality)
    if not quality then return nil end
    local skill = (tonumber(info.baseSkill) or 0) + (tonumber(info.bonusSkill) or 0)
    return quality, skill, tonumber(info.concentrationCost)
end

-- The schematic's required slots: quality slots ({ index, d, n, tiers =
-- { { itemID, price }, ... } } lowest quality first) and the fixed cost of
-- the rest, and the rest as { { itemID, n }, ... } (for the shopping list).
-- nil when a material has no price.
function Picker.Slots(schematic)
    local basic = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic
    local slots, fixed, fixedItems = {}, 0, {}
    for index, slot in ipairs(schematic.reagentSlotSchematics or {}) do
        local required = slot.required
        if required == nil then required = basic ~= nil and slot.reagentType == basic end
        -- A season's Spark is never a cost (Data/Recipes.lua).
        if required and not ns.Recipes.IsSpark(slot) then
            local n = slot.quantityRequired or 1
            local tiers = {}
            for _, reagent in ipairs(slot.reagents or {}) do
                if reagent.itemID then tiers[#tiers + 1] = { itemID = reagent.itemID, price = PriceOf(reagent.itemID) } end
            end
            if #tiers == 0 then return nil, "noprice" end
            if #tiers == 1 then
                if not tiers[1].price then return nil, "noprice" end
                fixed = fixed + tiers[1].price * n
                fixedItems[#fixedItems + 1] = { itemID = tiers[1].itemID, n = n }
            else
                -- The lowest quality has to be priced; a higher one without a
                -- price is just never picked.
                if not tiers[1].price then return nil, "noprice" end
                slots[#slots + 1] = { index = index, d = slot.dataSlotIndex or index, n = n, tiers = tiers }
            end
        end
    end
    return slots, fixed, fixedItems
end

local function BaseMix(slots)
    local mix = {}
    for _, slot in ipairs(slots) do
        mix[#mix + 1] = { slot = slot.index, dataSlotIndex = slot.d, itemID = slot.tiers[1].itemID, n = slot.n }
    end
    return mix
end

-- Every way to split n units over the tiers 2..k (the rest stay lowest):
-- calls fn(counts) with counts[t] for t >= 2.
local function EachSplit(n, k, fn)
    local counts, tried = {}, 0
    local function Go(t, left)
        if tried >= MAX_COMBOS then return end
        if t > k then
            tried = tried + 1
            fn(counts)
            return
        end
        for c = 0, left do
            counts[t] = c
            Go(t + 1, left - c)
        end
        counts[t] = 0
    end
    Go(2, n)
end

-- Steps 2 and 3: the cheapest mix for each amount of extra skill, as a
-- list rising in both skill and cost:
-- { { skill, cost, picks = { [slotNumber] = counts } }, ... }
function Picker.Frontier(recipeID, slots)
    local base = BaseMix(slots)
    local _, baseSkill = Picker.Ask(recipeID, base, false)
    if not baseSkill then return nil end
    -- Skill per unit of each higher tier, in tenths.
    for s, slot in ipairs(slots) do
        slot.gain = {}
        for t = 2, #slot.tiers do
            if slot.tiers[t].price then
                local mix = BaseMix(slots)
                mix[s].itemID = slot.tiers[t].itemID
                local _, skill = Picker.Ask(recipeID, mix, false)
                if not skill then return nil end
                slot.gain[t] = (skill - baseSkill) * SCALE / slot.n
            end
        end
    end
    -- states[skill] = { cost, picks }
    local states = { [0] = { cost = 0, picks = {} } }
    for s, slot in ipairs(slots) do
        local options = {}
        EachSplit(slot.n, #slot.tiers, function(counts)
            local gain, cost = 0, 0
            for t = 2, #slot.tiers do
                local c = counts[t] or 0
                if c > 0 then
                    if not slot.gain[t] then return end
                    gain = gain + c * slot.gain[t]
                    cost = cost + c * (slot.tiers[t].price - slot.tiers[1].price)
                end
            end
            gain = math.floor(gain + 0.5)
            local best = options[gain]
            if not best or cost < best.cost then
                local copy = {}
                for t = 2, #slot.tiers do copy[t] = counts[t] or 0 end
                options[gain] = { cost = cost, counts = copy }
            end
        end)
        local nextStates = {}
        for skill, state in pairs(states) do
            for gain, option in pairs(options) do
                local total, cost = skill + gain, state.cost + option.cost
                local known = nextStates[total]
                if not known or cost < known.cost then
                    local picks = {}
                    for k, v in pairs(state.picks) do picks[k] = v end
                    picks[s] = option.counts
                    nextStates[total] = { cost = cost, picks = picks }
                end
            end
        end
        states = nextStates
    end
    local skills = {}
    for skill in pairs(states) do skills[#skills + 1] = skill end
    table.sort(skills)
    -- Keep a mix only if no mix with more skill is as cheap or cheaper.
    local frontier, cheapestAbove = {}, math.huge
    for i = #skills, 1, -1 do
        local state = states[skills[i]]
        if state.cost < cheapestAbove then
            cheapestAbove = state.cost
            table.insert(frontier, 1, { skill = skills[i], cost = state.cost, picks = state.picks })
        end
    end
    return frontier
end

-- A frontier entry as materials: { { slot, dataSlotIndex, itemID, n }, ... }
function Picker.MixOf(slots, entry)
    local mix = {}
    for s, slot in ipairs(slots) do
        local counts = entry.picks[s] or {}
        local low = slot.n
        for t = #slot.tiers, 2, -1 do
            local c = counts[t] or 0
            if c > 0 then
                mix[#mix + 1] = { slot = slot.index, dataSlotIndex = slot.d, itemID = slot.tiers[t].itemID, n = c }
                low = low - c
            end
        end
        if low > 0 then
            mix[#mix + 1] = { slot = slot.index, dataSlotIndex = slot.d, itemID = slot.tiers[1].itemID, n = low }
        end
    end
    return mix
end

-- Step 4.
function Picker.Plan(recipeID, schematic)
    if type(schematic) ~= "table" then return nil, "noinfo" end
    local slots, fixed, fixedItems = Picker.Slots(schematic)
    if not slots then return nil, fixed end
    if #slots == 0 then return nil, "noquality" end
    local frontier = Picker.Frontier(recipeID, slots)
    if not frontier or #frontier == 0 then return nil, "noinfo" end

    local mixes, answers = {}, { [false] = {}, [true] = {} }
    local function Mix(i)
        mixes[i] = mixes[i] or Picker.MixOf(slots, frontier[i])
        return mixes[i]
    end
    local function Quality(i, focused)
        local known = answers[focused][i]
        if not known then
            local quality, _, cost = Picker.Ask(recipeID, Mix(i), focused)
            known = { quality = quality or 0, cost = cost }
            answers[focused][i] = known
        end
        return known.quality, known.cost
    end
    -- The first mix along the frontier that makes at least quality q.
    local function Cheapest(q, focused)
        local lo, hi = 1, #frontier
        if Quality(hi, focused) < q then return nil end
        while lo < hi do
            local mid = math.floor((lo + hi) / 2)
            if Quality(mid, focused) >= q then hi = mid else lo = mid + 1 end
        end
        return lo
    end

    -- Frontier costs are what the upgrades add on top of every slot at its
    -- lowest quality.
    local base = fixed
    for _, slot in ipairs(slots) do base = base + slot.n * slot.tiers[1].price end
    local plan = { qualities = {}, fixed = fixed, fixedItems = fixedItems }
    plan.baseQuality = Quality(1, false)
    plan.maxQuality = Quality(#frontier, false)
    local focusedMax = Quality(#frontier, true)
    local top = math.max(plan.maxQuality, focusedMax)
    for q = plan.baseQuality, top do
        local plain = q <= plan.maxQuality and Cheapest(q, false) or nil
        if plain then
            local quality = Quality(plain, false)
            if quality == q then
                plan.qualities[#plan.qualities + 1] = { quality = q, cost = base + frontier[plain].cost, mix = Mix(plain) }
            end
        end
        -- With concentration: only worth showing when it's cheaper than
        -- reaching the quality without it, or the only way there.
        local focused = Cheapest(q, true)
        if focused and (not plain or frontier[focused].cost < frontier[plain].cost) and Quality(focused, true) == q then
            local _, concentration = Quality(focused, true)
            plan.qualities[#plan.qualities + 1] = {
                quality = q, cost = base + frontier[focused].cost, mix = Mix(focused),
                concentration = concentration or 0,
            }
        end
    end
    if #plan.qualities == 0 then return nil, "noinfo" end
    return plan
end

-- What each quality sells for, when the qualities are different items:
-- { [quality] = sell price after the AH cut for one craft }, from
-- Data/Recipes.lua's reading of the recipe (qo, q).
function Picker.Values(recipe)
    if not recipe or not recipe.qo then return nil end
    local values = {}
    for quality, itemID in pairs(recipe.qo) do
        local price = ns.Prices:Get(tostring(itemID))
        if price and price.value then
            local each = price.value
            if price.min and price.min > 0 and price.min < each then each = price.min end
            values[quality] = math.floor(ns.Util.AfterCut(each) * (recipe.q or 1))
        end
    end
    return values
end
