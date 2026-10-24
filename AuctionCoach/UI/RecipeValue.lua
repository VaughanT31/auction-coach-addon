-- Auction Coach - cost and profit under the recipe in the profession window,
-- for every recipe you know (cooking and the main professions alike):
--
--   To craft: 412g 30s
--   Profit: 178g 10s
--   Makes 2, 310g each on the AH
--   [Add to shopping list]
--
-- Priced from what the recipe shows (0.20.2): the materials chosen in its
-- slots at what they sell for, or a vendor's price when that's cheaper
-- (Data/VendorPrices.lua), and the item made at the quality those materials
-- reach (Blizzard's Crafting Details), after the AH cut. An empty slot is
-- priced at its cheapest quality. Before 0.20.2 the quality was the one the
-- cheapest materials make, so a 2-star craft was valued as 1-star. For the
-- cheapest mix of qualities that reaches each quality, there's the Cheapest
-- materials panel. The button asks how
-- many to make and puts the materials on the shopping list
-- (UI/ShoppingEditor.lua). Turned off with the "Cost and profit on the
-- recipe" option.

local _, ns = ...
local L, Util, Skin = ns.L, ns.Util, ns.Skin

local Block = {}
ns.RecipeValue = Block

local GREEN = "|cff66dd77"
local RED = "|cffff6666"
local GREY = "|cff999999"

local frame

local function Enabled()
    return ns.db and ns.db.settings.recipeValue ~= false
end

local function Form()
    local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
    return page and page.SchematicForm
end

local function SelectedRecipe()
    local form = Form()
    local info = form and form.GetRecipeInfo and form:GetRecipeInfo()
    return type(info) == "table" and info.recipeID or nil
end

local function ViewingOwn()
    local trade = C_TradeSkillUI
    return not ((trade.IsTradeSkillLinked and trade.IsTradeSkillLinked())
        or (trade.IsTradeSkillGuild and trade.IsTradeSkillGuild())
        or (trade.IsNPCCrafting and trade.IsNPCCrafting()))
end

local function ItemName(itemID)
    return ns.Compat.GetItemInfo(itemID) or ("item " .. itemID)
end

-- A slot's cheapest priced item (slots list each quality of a material):
-- itemID, price, whether it's a vendor's price. The first item, unpriced,
-- when none has a price.
local function Cheapest(slot)
    local bestID, best, bestVendor
    for _, itemID in ipairs(slot.ids) do
        local price = ns.Prices:Get(tostring(itemID))
        local each, fromVendor = ns.VendorPrices.Cheapest(itemID, price and price.value or nil)
        if each and (not best or each < best) then bestID, best, bestVendor = itemID, each, fromVendor end
    end
    return bestID or slot.ids[1], best, bestVendor
end

-- What the recipe form has chosen: { [itemID] = quantity } of the materials
-- in its slots, and the quality they make (what Crafting Details shows),
-- or nil when the form can't say.
local function Chosen(form, recipeID)
    local transaction = form.transaction or (form.GetTransaction and form:GetTransaction())
    if not transaction or not transaction.CreateCraftingReagentInfoTbl then return nil end
    local ok, reagents = pcall(transaction.CreateCraftingReagentInfoTbl, transaction)
    if not ok or type(reagents) ~= "table" then return nil end
    local counts = {}
    for _, r in ipairs(reagents) do
        local itemID = r.itemID or (type(r.reagent) == "table" and r.reagent.itemID)
        if itemID and r.quantity and r.quantity > 0 then counts[itemID] = (counts[itemID] or 0) + r.quantity end
    end
    local op
    if form.GetRecipeOperationInfo then
        local okOp, info = pcall(form.GetRecipeOperationInfo, form)
        if okOp then op = info end
    end
    if type(op) ~= "table" then
        local guid = transaction.GetAllocationItemGUID and transaction:GetAllocationItemGUID() or nil
        local focus = transaction.IsApplyingConcentration and transaction:IsApplyingConcentration() or false
        local okOp, info = pcall(C_TradeSkillUI.GetCraftingOperationInfo, recipeID, reagents, guid, focus)
        if okOp then op = info end
    end
    return counts, type(op) == "table" and tonumber(op.craftingQuality) or nil
end

local function MaterialName(itemID, fromVendor)
    local name = ItemName(itemID)
    local quality = C_TradeSkillUI.GetItemReagentQualityByItemInfo and C_TradeSkillUI.GetItemReagentQualityByItemInfo(itemID)
    if quality then name = L.RV_TIP_QUALITY:format(name, quality) end
    return fromVendor and L.RV_TIP_VENDOR:format(name) or name
end

-- One craft's materials: total cost, the lines for the tooltip, and the
-- names of any material without a price. chosen (from Chosen) prices the
-- materials in the slots; whatever a slot is short of, and every slot
-- without chosen, at its cheapest quality. Chosen optional reagents count
-- when they have a price.
local function Materials(recipe, chosen)
    local cost, lines, missing = 0, {}, {}
    local left = {}
    for itemID, n in pairs(chosen or {}) do left[itemID] = n end
    local function Add(itemID, n, each, fromVendor)
        if each then
            cost = cost + each * n
            lines[#lines + 1] = { n .. "x " .. MaterialName(itemID, fromVendor), Util.FormatMoney(each * n) }
        else
            missing[#missing + 1] = ItemName(itemID)
            lines[#lines + 1] = { n .. "x " .. MaterialName(itemID), GREY .. "?|r" }
        end
    end
    for _, slot in ipairs(recipe.r) do
        local need = slot.n
        for _, itemID in ipairs(slot.ids) do
            local n = math.min(left[itemID] or 0, need)
            if n > 0 then
                local price = ns.Prices:Get(tostring(itemID))
                local each, fromVendor = ns.VendorPrices.Cheapest(itemID, price and price.value or nil)
                Add(itemID, n, each, fromVendor)
                need = need - n
                left[itemID] = nil
            end
        end
        if need > 0 then
            local itemID, each, fromVendor = Cheapest(slot)
            Add(itemID, need, each, fromVendor)
        end
    end
    for itemID, n in pairs(left) do
        local price = ns.Prices:Get(tostring(itemID))
        local each, fromVendor = ns.VendorPrices.Cheapest(itemID, price and price.value or nil)
        if each then Add(itemID, n, each, fromVendor) end
    end
    return math.floor(cost), lines, missing
end

-- What one craft makes at the quality the chosen materials reach: { each,
-- value, quality }, or nil without an AH price. Falls back to the quality
-- the cheapest materials make, then to the recipe's plain output.
local function Made(recipe, quality)
    local candidates = {}
    if quality and recipe.qo and recipe.qo[quality] then candidates[#candidates + 1] = { recipe.qo[quality], quality } end
    local id, q = ns.Crafting.OutputOf(recipe)
    candidates[#candidates + 1] = { id, q }
    candidates[#candidates + 1] = { recipe.o, nil }
    for _, c in ipairs(candidates) do
        local each = ns.Crafting.SellPriceOf(c[1])
        if each then
            return { each = each, value = math.floor(Util.AfterCut(each) * (recipe.q or 1)), quality = c[2] }
        end
    end
end

local function Amount(n)
    return (n == math.floor(n)) and tostring(n) or ("%.1f"):format(n)
end

local function ShowTooltip(self)
    local c = frame.current
    if not c then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L.RV_TIP_TITLE)
    for _, line in ipairs(c.lines) do GameTooltip:AddDoubleLine(line[1], line[2], 1, 1, 1, 1, 1, 1) end
    if c.e then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L.RV_TIP_MAKES:format(Amount(c.recipe.q or 1), Util.FormatMoney(Util.AfterCut(c.e.each))), 1, 1, 1, true)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L.RV_TIP_NOTE, 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
end

local function AddToList()
    local c = frame.current
    if not c then return end
    local items = {}
    for _, slot in ipairs(c.recipe.r) do items[#items + 1] = { itemID = (Cheapest(slot)), n = slot.n } end
    local ok, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, c.recipeID, false)
    local perCraft = ok and type(schematic) == "table" and schematic.quantityMin or 1
    local info = C_TradeSkillUI.GetRecipeInfo(c.recipeID)
    local name = info and info.name or ItemName(c.recipe.o)
    ns.ShoppingEditor:AddCraft(name, items, { name = ItemName(c.recipe.o), perCraft = math.max(1, perCraft) })
end

local function Create(form)
    frame = CreateFrame("Frame", "AuctionCoachRecipeValue", form)
    frame:SetSize(320, 76)
    frame:EnableMouse(true)
    frame:SetScript("OnEnter", ShowTooltip)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local function Line(font, y)
        local fs = frame:CreateFontString(nil, "OVERLAY", font)
        fs:SetPoint("TOPLEFT", 0, y)
        fs:SetPoint("RIGHT", 0, 0)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(true)
        return fs
    end
    frame.cost = Line("GameFontHighlight", 0)
    frame.profit = Line("GameFontHighlight", -18)
    frame.note = Line("GameFontHighlightSmall", -36)
    frame.add = Skin.Button(frame, L.RV_ADD, 150, 22)
    frame.add:SetScript("OnClick", AddToList)
    frame.add:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L.RV_ADD)
        GameTooltip:AddLine(L.RV_ADD_TIP, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame.add:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Changing a material's quality, Use Best Quality Reagents or
    -- concentration changes the cost and the quality made.
    local event = ProfessionsRecipeSchematicFormMixin and ProfessionsRecipeSchematicFormMixin.Event
    if form.RegisterCallback and event then
        for _, name in ipairs({ "AllocationsModified", "UseBestQualityModified" }) do
            if event[name] then
                form:RegisterCallback(event[name], function()
                    Util.Debounce("recipeValue", 0.2, function() Block:Refresh() end)
                end, frame)
            end
        end
    end
end

local function AddOnLoaded(name)
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    return loaded and loaded(name) and true or false
end

-- Auctionator puts its own cost and profit lines straight under the
-- materials, where this block goes, so with it loaded this block sits
-- at the bottom instead, just above Use Best Quality Reagents.
local function BottomAnchor(form)
    local box = form.AllocateBestQualityCheckbox or form.AllocateBestQualityCheckBox
    if box and box:IsShown() then return box end
end

-- Under the materials: the optional reagents when the recipe has them,
-- else the required ones. Both resize to what they hold; if neither has a
-- size yet, the bottom left of the recipe.
local function Place(form)
    local optional = form.OptionalReagents
    local below = (optional and optional:IsShown() and optional:GetHeight() > 10 and optional)
        or (form.Reagents and form.Reagents:IsShown() and form.Reagents:GetHeight() > 10 and form.Reagents)
    frame:ClearAllPoints()
    local bottom = AddOnLoaded("Auctionator") and BottomAnchor(form)
    if bottom then
        frame:SetPoint("BOTTOMLEFT", bottom, "TOPLEFT", 0, 10)
        -- A long list of materials leaves no room down there: then under
        -- Auctionator's lines (about 60 high) instead.
        local top, under = bottom:GetTop(), below and below:GetBottom()
        if top and under and top + 10 + frame:GetHeight() > under - 64 then
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", below, "BOTTOMLEFT", 0, -76)
        end
    elseif below then
        frame:SetPoint("TOPLEFT", below, "BOTTOMLEFT", 0, -16)
    else
        frame:SetPoint("BOTTOMLEFT", form, "BOTTOMLEFT", 24, 40)
    end
end

function Block:Hide()
    if frame then frame:Hide() end
end

function Block:Show(recipeID)
    local form = Form()
    if not Enabled() or not form or not form:IsVisible() or not ViewingOwn() then return self:Hide() end
    local recipe = ns.Recipes.Read(recipeID, nil)
    if not recipe then return self:Hide() end
    if not frame then Create(form) end

    local chosen, quality = Chosen(form, recipeID)
    local cost, lines, missing = Materials(recipe, chosen)
    local e = #missing == 0 and Made(recipe, quality) or nil
    frame.current = { recipeID = recipeID, recipe = recipe, e = e, lines = lines }

    local y = -40
    if #missing > 0 then
        frame.cost:SetText(L.RV_COST:format(GREY .. "?|r"))
        frame.profit:SetText(L.RV_PROFIT:format(GREY .. "?|r"))
        frame.note:SetText(GREY .. L.RV_NO_PRICE:format(table.concat(missing, ", ")) .. "|r")
        y = -38 - math.ceil(frame.note:GetStringHeight())
    elseif not e then
        frame.cost:SetText(L.RV_COST:format(Util.FormatMoney(cost)))
        frame.profit:SetText(L.RV_PROFIT:format(GREY .. "?|r"))
        frame.note:SetText(GREY .. L.RV_NO_SELL .. "|r")
        y = -38 - math.ceil(frame.note:GetStringHeight())
    else
        local profit = e.value - cost
        frame.cost:SetText(L.RV_COST:format(Util.FormatMoney(cost)))
        frame.profit:SetText(L.RV_PROFIT:format((profit >= 0 and GREEN or RED) .. Util.FormatMoney(math.abs(profit))
            .. (profit < 0 and (" " .. L.RV_LOSS) or "") .. "|r"))
        local makes = e.quality and L.RV_MAKES_QUALITY:format(Amount(recipe.q or 1), e.quality, Util.FormatMoney(e.each))
            or L.RV_MAKES:format(Amount(recipe.q or 1), Util.FormatMoney(e.each))
        frame.note:SetText(GREY .. makes .. "|r")
        y = -38 - math.ceil(frame.note:GetStringHeight())
    end
    frame.add:ClearAllPoints()
    frame.add:SetPoint("TOPLEFT", 0, y - 6)
    frame:SetHeight(-y + 34)
    Place(form)
    frame:Show()
end

function Block:Refresh()
    local recipeID = SelectedRecipe()
    if not recipeID then return self:Hide() end
    local ok, err = pcall(self.Show, self, recipeID)
    if not ok then
        self:Hide()
        geterrorhandler()(err)
    end
end

local function RefreshSoon()
    -- After the form has laid out the new recipe's materials.
    Util.Debounce("recipeValue", 0.2, function() Block:Refresh() end)
end

if EventRegistry and EventRegistry.RegisterCallback then
    EventRegistry:RegisterCallback("ProfessionsRecipeListMixin.Event.OnRecipeSelected", RefreshSoon, Block)
end
ns.Events:On("TRADE_SKILL_SHOW", RefreshSoon)
ns.Events:On("TRADE_SKILL_CLOSE", function() Block:Hide() end)
for _, event in ipairs({ "AC_SCAN_COMPLETE", "AC_DATA_CHANGED", "AC_LIVE_PRICE", "MERCHANT_SHOW", "GET_ITEM_INFO_RECEIVED" }) do
    ns.Events:On(event, function() if frame and frame:IsShown() then RefreshSoon() end end)
end
