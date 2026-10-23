-- Auction Coach - cost and profit under the recipe in the profession window,
-- for every recipe you know (cooking and the main professions alike):
--
--   To craft: 412g 30s
--   Profit: 178g 10s
--   Makes 2, 310g each on the AH
--   [Add to shopping list]
--
-- Priced like Craft or sell (Advice/Crafting.lua): materials at what they
-- sell for, or a vendor's price when that's cheaper (Data/VendorPrices.lua),
-- each at its cheapest quality, and what one craft makes on average after
-- the AH cut, at the quality you make. For the cheapest mix of qualities
-- that reaches each quality, there's the Cheapest materials panel. The button asks how
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

-- One craft's materials: total cost, the lines for the tooltip, and the
-- names of any material without a price.
local function Materials(recipe)
    local cost, lines, missing = 0, {}, {}
    for _, slot in ipairs(recipe.r) do
        local itemID, each, fromVendor = Cheapest(slot)
        local name = ItemName(itemID)
        if each then
            cost = cost + each * slot.n
            lines[#lines + 1] = { slot.n .. "x " .. (fromVendor and L.RV_TIP_VENDOR:format(name) or name), Util.FormatMoney(each * slot.n) }
        else
            missing[#missing + 1] = name
            lines[#lines + 1] = { slot.n .. "x " .. name, GREY .. "?|r" }
        end
    end
    return math.floor(cost), lines, missing
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
end

-- Under the materials: the optional reagents when the recipe has them,
-- else the required ones. Both resize to what they hold; if neither has a
-- size yet, the bottom left of the recipe.
local function Place(form)
    local optional = form.OptionalReagents
    local below = (optional and optional:IsShown() and optional:GetHeight() > 10 and optional)
        or (form.Reagents and form.Reagents:IsShown() and form.Reagents:GetHeight() > 10 and form.Reagents)
    frame:ClearAllPoints()
    if below then
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

    local cost, lines, missing = Materials(recipe)
    local e = #missing == 0 and ns.Crafting.Evaluate(recipeID, recipe) or nil
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
        frame.note:SetText(GREY .. L.RV_MAKES:format(Amount(recipe.q or 1), Util.FormatMoney(e.each)) .. "|r")
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
