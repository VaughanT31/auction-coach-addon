-- Auction Coach - "Cheapest materials" beside the profession window (0.12).
--
-- Select one of your recipes and this panel lists each quality you can make
-- with the cheapest mix of material qualities that reaches it
-- (Advice/MaterialPicker.lua), what the materials cost at what they sell
-- for, and the profit when each quality is its own item. Rows with
-- concentration show how much it costs, and only when concentration gets
-- there with cheaper materials.
--   Hover a row   the materials, how many of each quality
--   Use           puts that mix in the recipe's material slots
-- Turned off with the "Cheapest materials" option.

local _, ns = ...
local L, Util, Skin = ns.L, ns.Util, ns.Skin

local Panel = {}
ns.MaterialPanel = Panel

local WIDTH = 330
local ROW_HEIGHT = 22
local MAX_ROWS = 10
local SUB_Y = -34

local GREEN = "|cff66dd77"
local RED = "|cffff6666"
local GREY = "|cff999999"

local frame, rows, subText, headers
local current            -- { recipeID, plan, values, tiers }

local function Enabled()
    return ns.db and ns.db.settings.materialPicker ~= false
end

local function AtlasMarkup(atlas)
    if type(atlas) == "string" and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        return CreateAtlasMarkup(atlas, 18, 18)
    end
    return nil
end

local function Try(fn, ...)
    if not fn then return nil end
    local ok, result = pcall(fn, ...)
    return ok and result or nil
end

-- The game's own icon for an item's quality, when this client can say:
-- Midnight's two qualities (a silver and a gold star) look different from
-- the older three and five.
local function ItemQualityIcon(itemID, reagent)
    if not itemID or not C_TradeSkillUI then return nil end
    local get = reagent and C_TradeSkillUI.GetItemReagentQualityInfo or C_TradeSkillUI.GetItemCraftedQualityInfo
    local info = Try(get, itemID)
    if type(info) == "table" then
        return AtlasMarkup(info.iconSmall) or AtlasMarkup(info.iconChat) or AtlasMarkup(info.iconInventory)
    end
    return nil
end

-- A quality icon: the item's own when known, else by how many qualities
-- the recipe has (2 = Midnight's stars).
local function QualityIcon(quality, itemID, tiers, reagent)
    if not quality then return "" end
    local own = ItemQualityIcon(itemID, reagent)
    if own then return own end
    local names
    if tiers == 2 then
        names = { "Professions-Icon-Quality-12-Tier" .. quality .. "-Small", "Professions-ChatIcon-Quality-12-Tier" .. quality,
            "Professions-Icon-Quality-12-Tier" .. quality }
    else
        names = { "Professions-Icon-Quality-Tier" .. quality .. "-Small", "Professions-ChatIcon-Quality-Tier" .. quality }
    end
    for _, atlas in ipairs(names) do
        local markup = AtlasMarkup(atlas)
        if markup then return markup end
    end
    if tiers == 2 then return quality == 1 and L.MAT_SILVER or L.MAT_GOLD end
    return "R" .. quality
end

local function ReagentQuality(itemID)
    return Try(C_TradeSkillUI and C_TradeSkillUI.GetItemReagentQualityByItemInfo, itemID)
end

local function ItemName(itemID)
    local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
    return name or ("item " .. itemID)
end

-- The open recipe form and its materials, or nil.
local function Form()
    local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
    return page and page.SchematicForm
end

-- Puts a mix into the recipe's material slots. Returns true when it worked.
local function Apply(entry)
    local form = Form()
    local transaction = form and (form.transaction or (form.GetTransaction and form:GetTransaction()))
    if not transaction or not transaction.ClearAllocations or not transaction.OverwriteAllocation then return false end
    local bySlot = {}
    for _, m in ipairs(entry.mix) do
        bySlot[m.slot] = bySlot[m.slot] or {}
        table.insert(bySlot[m.slot], m)
    end
    local ok = pcall(function()
        if transaction.SetManuallyAllocated then transaction:SetManuallyAllocated(true) end
        for slot, list in pairs(bySlot) do
            transaction:ClearAllocations(slot)
            for _, m in ipairs(list) do
                local make = Professions and Professions.CreateCraftingReagentByItemID
                local reagent = make and make(m.itemID) or { itemID = m.itemID }
                transaction:OverwriteAllocation(slot, reagent, m.n)
            end
        end
        if transaction.SetApplyConcentration then transaction:SetApplyConcentration(entry.concentration ~= nil) end
        local event = ProfessionsRecipeSchematicFormMixin and ProfessionsRecipeSchematicFormMixin.Event
        if form.TriggerEvent and event and event.AllocationsModified then form:TriggerEvent(event.AllocationsModified) end
        if form.UpdateAllSlots then form:UpdateAllSlots() end
        if form.UpdateDetailsStats then form:UpdateDetailsStats() end
    end)
    return ok
end

local function ShowRowTooltip(row)
    local entry = row.entry
    if not entry then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(L.MAT_TIP_TITLE:format(row.icon or QualityIcon(entry.quality)), 1, 1, 1)
    for _, m in ipairs(entry.mix) do
        local each = ns.MaterialPicker.PriceOf(m.itemID) or 0
        GameTooltip:AddDoubleLine(("%dx %s %s"):format(m.n, ItemName(m.itemID), QualityIcon(ReagentQuality(m.itemID), m.itemID, nil, true)),
            Util.FormatMoney(each * m.n), 1, 1, 1, 0.8, 0.8, 0.8)
    end
    if current and current.plan.fixed > 0 then
        GameTooltip:AddDoubleLine(L.MAT_TIP_OTHER, Util.FormatMoney(current.plan.fixed), 0.8, 0.8, 0.8, 0.8, 0.8, 0.8)
    end
    if entry.concentration then
        GameTooltip:AddLine(L.MAT_TIP_CONC:format(entry.concentration), 1, 0.82, 0.15, true)
    end
    GameTooltip:AddLine(L.MAT_TIP_USE, 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
end

local function CreateRow(index)
    local row = CreateFrame("Frame", nil, frame)
    row:SetHeight(ROW_HEIGHT)
    row:EnableMouse(true)
    Skin.RowBand(row)
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.06)
    local function Cell(x, w, justify)
        local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", x, 0)
        fs:SetWidth(w)
        fs:SetJustifyH(justify or "LEFT")
        fs:SetWordWrap(false)
        return fs
    end
    row.quality = Cell(4, 90)
    row.cost = Cell(96, 76, "RIGHT")
    row.profit = Cell(176, 76, "RIGHT")
    row.use = Skin.Button(row, L.MAT_USE, 44, 18)
    row.use:SetPoint("RIGHT", -2, 0)
    row.use:SetScript("OnClick", function()
        if row.entry and not Apply(row.entry) then Util.Print(L.MAT_USE_FAILED) end
    end)
    row:SetScript("OnEnter", ShowRowTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

local function Create()
    frame = Skin.Window("AuctionCoachMaterialPanel", WIDTH, 120)
    frame.title:SetText(L.MAT_TITLE)
    subText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    subText:SetPoint("TOPLEFT", 14, -34)
    subText:SetPoint("RIGHT", -14, 0)
    subText:SetJustifyH("LEFT")
    subText:SetWordWrap(true)
    headers = {}
    local columns = { { 16, 90, L.MAT_COL_QUALITY }, { 108, 76, L.MAT_COL_COST, "RIGHT" }, { 188, 76, L.MAT_COL_PROFIT, "RIGHT" } }
    for _, h in ipairs(columns) do
        local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs.x = h[1]
        headers[#headers + 1] = fs
        fs:SetWidth(h[2])
        fs:SetJustifyH(h[4] or "LEFT")
        fs:SetText(h[3])
    end
    rows = {}
    for i = 1, MAX_ROWS do rows[i] = CreateRow(i) end
    if ProfessionsFrame then ProfessionsFrame:HookScript("OnHide", function() frame:Hide() end) end
end

-- Puts the headings and rows under the description, however many lines it
-- wraps to. Returns the y where the rows end.
local function Layout(count)
    local y = SUB_Y - math.ceil(subText:GetStringHeight()) - 10
    for _, fs in ipairs(headers) do
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", fs.x, y)
        fs:SetShown(count > 0)
    end
    y = y - 18
    for i, row in ipairs(rows) do
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 12, y - (i - 1) * ROW_HEIGHT)
        row:SetPoint("RIGHT", frame, "RIGHT", -12, 0)
    end
    return y - count * ROW_HEIGHT
end

function Panel:Hide()
    if frame then frame:Hide() end
end

function Panel:Show(recipeID)
    if not Enabled() or not ProfessionsFrame or not ProfessionsFrame:IsShown() then return self:Hide() end
    local trade = C_TradeSkillUI
    if (trade.IsTradeSkillLinked and trade.IsTradeSkillLinked()) or (trade.IsTradeSkillGuild and trade.IsTradeSkillGuild())
        or (trade.IsNPCCrafting and trade.IsNPCCrafting()) then
        return self:Hide()
    end
    local info = trade.GetRecipeInfo(recipeID)
    if type(info) ~= "table" or not info.learned or info.isRecraft then return self:Hide() end
    local ok, schematic = pcall(trade.GetRecipeSchematic, recipeID, false)
    if not ok then return self:Hide() end
    local plan, reason = ns.MaterialPicker.Plan(recipeID, schematic)
    if not frame then Create() end
    if not plan then
        if reason ~= "noprice" then return self:Hide() end
        current = nil
        subText:SetText(L.MAT_NO_PRICE)
        for _, row in ipairs(rows) do row:Hide() end
        frame:SetHeight(-Layout(0) + 4)
    else
        local recipe = ns.Recipes.Read(recipeID, nil)
        local qualities = Try(trade.GetQualitiesForRecipe, recipeID)
        current = { recipeID = recipeID, plan = plan, values = ns.MaterialPicker.Values(recipe),
            tiers = type(qualities) == "table" and #qualities or nil }
        subText:SetText(current.values and L.MAT_SUB or L.MAT_SUB_GEAR)
        local shown = math.min(#plan.qualities, MAX_ROWS)
        for i, row in ipairs(rows) do
            local entry = plan.qualities[i]
            row.entry = entry
            row:SetShown(entry ~= nil)
            if entry then
                row.icon = QualityIcon(entry.quality, recipe and recipe.qo and recipe.qo[entry.quality], current.tiers)
                local label = row.icon
                if entry.concentration then label = label .. " " .. GREY .. L.MAT_CONC:format(entry.concentration) .. "|r" end
                row.quality:SetText(label)
                row.cost:SetText(Util.FormatMoney(entry.cost))
                local value = current.values and current.values[entry.quality]
                if value then
                    local profit = value - entry.cost
                    row.profit:SetText((profit >= 0 and GREEN or RED) .. Util.FormatMoney(math.abs(profit)) .. (profit < 0 and (" " .. L.MAT_LOSS) or "") .. "|r")
                else
                    row.profit:SetText(GREY .. "-|r")
                end
            end
        end
        frame:SetHeight(-Layout(shown) + 12)
    end
    Panel:Place()
    frame:Show()
end

-- Beside the profession window, or under Patron Planner's order queue when
-- that's showing there too (it moves again when the queue opens or closes).
local hookedQueue
function Panel:Place()
    if not frame then return end
    local queue = _G.PatronPlannerQueuePanel
    if queue and not hookedQueue then
        hookedQueue = true
        queue:HookScript("OnShow", function() Panel:Place() end)
        queue:HookScript("OnHide", function() Panel:Place() end)
    end
    frame:ClearAllPoints()
    if queue and queue:IsShown() then
        frame:SetPoint("TOPLEFT", queue, "BOTTOMLEFT", 0, -6)
    else
        frame:SetPoint("TOPLEFT", ProfessionsFrame, "TOPRIGHT", 6, 0)
    end
end

-- The recipe the profession window is showing.
local function SelectedRecipe()
    local form = Form()
    local info = form and form.GetRecipeInfo and form:GetRecipeInfo()
    return type(info) == "table" and info.recipeID or nil
end

local function Refresh()
    local recipeID = SelectedRecipe()
    if recipeID then
        local ok, err = pcall(Panel.Show, Panel, recipeID)
        if not ok then
            Panel:Hide()
            geterrorhandler()(err)
        end
    else
        Panel:Hide()
    end
end

local function RefreshSoon()
    Util.Debounce("materialPanel", 0.2, Refresh)
end

if EventRegistry and EventRegistry.RegisterCallback then
    EventRegistry:RegisterCallback("ProfessionsRecipeListMixin.Event.OnRecipeSelected", RefreshSoon, Panel)
end
ns.Events:On("TRADE_SKILL_SHOW", RefreshSoon)
ns.Events:On("TRADE_SKILL_CLOSE", function() Panel:Hide() end)
ns.Events:On("AC_SCAN_COMPLETE", function() if frame and frame:IsShown() then RefreshSoon() end end)
