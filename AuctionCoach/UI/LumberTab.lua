-- Auction Coach - "Lumber" tab (Lumber Crafting): every recipe that uses
-- lumber, known or not, with what its other materials cost, what the decor
-- sells for and the gold each lumber makes (Advice/LumberCrafting.lua).
-- Filters: Known, Known + can learn, All; and one lumber type. Clicking a
-- row at the AH opens the decor's listings.

local _, ns = ...
local L, Util, Compat = ns.L, ns.Util, ns.Compat

local ROW_HEIGHT = 24

local COLUMNS = {
    name = { 24, 124, 0.5 },
    lumber = { 152, 36 },
    cost = { 192, 64 },
    sells = { 260, 64 },
    per = { 328, 64 },
    day = { 396, 40 },
    verdict = { 442, 66, 0.25 },
    status = { 512, 70, 0.25 },
}

local VERDICT_COLORS = {
    WORTH = { 0.4, 1, 0.4 },
    SLOW = { 1, 0.82, 0 },
    LOSS = { 1, 0.5, 0.35 },
    NO_MATS = { 0.6, 0.6, 0.6 },
    NO_PRICE = { 0.6, 0.6, 0.6 },
}

local STATUS_COLORS = {
    known = { 0.4, 1, 0.4 },
    learnable = { 0.6, 0.75, 1 },
    none = { 0.6, 0.6, 0.6 },
}

local VIEWS = { "known", "learnable", "all" }

local Column = ns.Skin.Columns(COLUMNS)

-- The recipe last clicked: kept highlighted, and scrolled back into view when
-- a fresh price (from searching it at the AH) moves it in the list.
-- shownAt is the place it had last time, so scrolling by hand isn't undone.
local selected, shownAt
local ScrollToSelected

local function CharName(charKey)
    return (charKey:match("^[^-]+")) or charKey
end

local function Names(list)
    local names = {}
    for i, charKey in ipairs(list) do names[i] = CharName(charKey) end
    return table.concat(names, ", ")
end

local function ItemName(itemID, fallback)
    return Util.NamedLink(tostring(itemID)) or fallback or ("|cff9d9d9d" .. L.ITEM_LOADING .. "|r")
end

-- Sales a day: whole numbers from 10 up, one decimal below, "-" when unknown.
local function Rate(perDay)
    if not perDay then return "|cff9d9d9d-|r" end
    if perDay >= 10 then return BreakUpLargeNumbers(math.floor(perDay + 0.5)) end
    if perDay > 0 and perDay < 0.1 then return "<0.1" end
    return string.format("%.1f", perDay)
end

local function Money(copper)
    if not copper then return "|cff9d9d9d-|r" end
    if copper < 0 then return "|cffff7f50-" .. Util.FormatMoneyIcons(-copper) .. "|r" end
    return Util.FormatMoneyIcons(copper)
end

-- ---------------------------------------------------------------------
-- Tooltip
-- ---------------------------------------------------------------------

local function AddSource(e)
    local tip = GameTooltip
    if e.status == "known" then
        tip:AddLine(L.LUMBER_KNOWN_BY:format(Names(e.chars)), 0.4, 1, 0.4, true)
        return
    end
    local text = ns.Lumber.SourceText(e.spellID)
    if text then
        tip:AddLine(L.LUMBER_SOURCE:format(text), 1, 1, 1, true)
    elseif e.recipeItem then
        tip:AddLine(L.LUMBER_SOURCE_ITEM:format(ItemName(e.recipeItem, "")), 1, 1, 1, true)
    else
        tip:AddLine(L.LUMBER_SOURCE_TRAINER:format(e.tierName or ""), 1, 1, 1, true)
    end
    if e.recipeItem and e.recipePrice then
        tip:AddLine(L.LUMBER_RECIPE_ON_AH:format(Util.FormatMoney(e.recipePrice)), 0.75, 0.75, 0.75)
    end
    if e.status == "learnable" then
        tip:AddLine(L.LUMBER_CAN_LEARN:format(Names(e.chars)), 0.6, 0.75, 1, true)
    else
        tip:AddLine(L.LUMBER_NO_ONE, 0.6, 0.6, 0.6, true)
    end
end

local function ShowRowTooltip(row)
    local e = row.entry
    if not e then return end
    local tip = GameTooltip
    tip:SetOwner(row, "ANCHOR_RIGHT")
    local link = Util.NamedLink(e.key)
    if link and link:find("item:") then
        tip:SetHyperlink(link)
        tip:AddLine(" ")
        tip:AddLine(L.ADDON_TITLE, 1, 0.82, 0)
    else
        tip:SetText(e.name, 1, 0.82, 0)
    end
    tip:AddLine(e.tierName or "", 0.75, 0.75, 0.75)
    tip:AddLine(L["LUMBER_WHY_" .. e.verdict], 1, 1, 1, true)

    tip:AddLine(" ")
    tip:AddLine(L.LUMBER_MATERIALS, 1, 0.82, 0)
    for _, wood in ipairs(e.recipe.w) do
        tip:AddDoubleLine(L.LUMBER_MAT_ROW:format(wood[2], ItemName(wood[1], "")), L.LUMBER_WARBOUND, 1, 1, 1, 0.6, 0.6, 0.6)
    end
    for _, m in ipairs(e.materials) do
        tip:AddDoubleLine(L.LUMBER_MAT_ROW:format(m.n, ItemName(m.id, "")),
            m.each and Util.FormatMoney(m.each * m.n) or L.LUMBER_NO_PRICE_SHORT, 1, 1, 1, 1, 1, 1)
    end
    if e.cost then tip:AddDoubleLine(L.LUMBER_MAT_TOTAL, Util.FormatMoney(e.cost), 0.75, 0.75, 0.75, 1, 1, 1) end
    if e.each then
        tip:AddDoubleLine(L.LUMBER_LOWEST_NOW, Util.FormatMoney(e.each), 0.75, 0.75, 0.75, 1, 1, 1)
    end
    if e.usual and e.usual ~= e.each then
        tip:AddDoubleLine(L.LUMBER_USUAL, Util.FormatMoney(e.usual), 0.75, 0.75, 0.75, 1, 1, 1)
    end
    if e.undercut then tip:AddLine(L.LUMBER_UNDERCUT, 1, 0.82, 0, true) end
    if e.value then
        tip:AddDoubleLine(L.LUMBER_SELLS_AFTER_CUT, Util.FormatMoney(e.value), 0.75, 0.75, 0.75, 1, 1, 1)
    end
    if e.salesPerDay then
        tip:AddLine(L.LUMBER_SALES:format(Rate(e.salesPerDay)), 0.75, 0.75, 0.75)
    end

    if e.lowestAt and e.lowestAt > 0 then
        tip:AddLine(L.LUMBER_LOWEST_SEEN:format(Util.FormatAge(e.lowestAt)), 0.75, 0.75, 0.75)
    end

    tip:AddLine(" ")
    tip:AddLine(L.LUMBER_OWNED:format(BreakUpLargeNumbers(e.owned), ItemName(e.lumberID, ""), BreakUpLargeNumbers(e.crafts or 0)),
        0.75, 0.75, 0.75, true)
    local essence = ns.Lumber.Owned(ns.Lumber.ESSENCE_ID)
    if essence > 0 then
        tip:AddLine(L.LUMBER_ESSENCE_LINE:format(BreakUpLargeNumbers(essence),
            BreakUpLargeNumbers(essence * ns.Lumber.ESSENCE_LUMBER)), 0.6, 0.75, 1, true)
    end
    AddSource(e)
    tip:Show()
end

-- ---------------------------------------------------------------------
-- Rows
-- ---------------------------------------------------------------------

local function CreateRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row.index = index
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT")
    ns.Skin.RowBand(row)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", 2, 0)
    row.name = Column(row, "name", "GameFontHighlight")
    row.lumber = Column(row, "lumber", "GameFontHighlight", "RIGHT")
    row.cost = Column(row, "cost", "GameFontHighlight", "RIGHT")
    row.sells = Column(row, "sells", "GameFontHighlight", "RIGHT")
    row.per = Column(row, "per", "GameFontHighlight", "RIGHT")
    row.day = Column(row, "day", "GameFontHighlight", "RIGHT")
    row.verdict = Column(row, "verdict", "GameFontHighlightSmall")
    row.status = Column(row, "status", "GameFontHighlightSmall")

    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.08)
    row.selected = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.selected:SetAllPoints()
    row.selected:SetColorTexture(1, 0.82, 0, 0.12)

    row:SetScript("OnEnter", ShowRowTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self)
        local e = self.entry
        if not e then return end
        selected, shownAt = e.spellID, self.index
        if Compat.ShowAtAuctionHouse(e.key, Util.NamedLink(e.key), e.each) then
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        end
        ns.MainWindow:Refresh()
    end)
    return row
end

local function SetRow(row, e)
    row.entry = e
    row.icon:SetTexture(Compat.GetItemIconByID(e.recipe.o))
    row.name:SetText(ItemName(e.recipe.o, e.name))
    local icon = Compat.GetItemIconByID(e.lumberID)
    row.lumber:SetText(e.lumber .. (icon and (" |T" .. icon .. ":14:14|t") or ""))
    row.cost:SetText(Money(e.cost))
    row.sells:SetText(Money(e.each))
    if e.undercut then row.sells:SetTextColor(1, 0.82, 0) else row.sells:SetTextColor(1, 1, 1) end
    row.per:SetText(Money(e.perLumber))
    row.day:SetText(Rate(e.salesPerDay))
    if e.salesPerDay and e.salesPerDay < ns.LumberCrafting.MIN_SALES then
        row.day:SetTextColor(1, 0.82, 0)
    else
        row.day:SetTextColor(1, 1, 1)
    end
    local vc = VERDICT_COLORS[e.verdict]
    row.verdict:SetText(L["LUMBER_VERDICT_" .. e.verdict])
    row.verdict:SetTextColor(vc[1], vc[2], vc[3])
    local sc = STATUS_COLORS[e.status]
    row.status:SetText(L["LUMBER_STATUS_" .. e.status:upper()])
    row.status:SetTextColor(sc[1], sc[2], sc[3])
    row.selected:SetShown(e.spellID == selected)
    row:Show()
end

-- ---------------------------------------------------------------------
-- Filters
-- ---------------------------------------------------------------------

local function ViewMenu(owner)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(L.LUMBER_VIEW_TITLE)
        for _, view in ipairs(VIEWS) do
            root:CreateRadio(L["LUMBER_VIEW_" .. view:upper()], function() return ns.db.settings.lumberView == view end,
                function()
                    ns.db.settings.lumberView = view
                    ns.MainWindow:Refresh()
                end)
        end
    end)
end

local function TypeMenu(owner)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(L.LUMBER_TYPE_TITLE)
        local function Pick(itemID)
            return function()
                ns.db.settings.lumberType = itemID
                ns.MainWindow:Refresh()
            end
        end
        root:CreateRadio(L.LUMBER_TYPE_ALL, function() return ns.db.settings.lumberType == nil end, Pick(nil))
        -- Newest expansion first.
        local lumber = ns.LumberRecipes and ns.LumberRecipes.lumber or {}
        for i = #lumber, 1, -1 do
            local itemID = lumber[i]
            local owned = ns.Lumber.Owned(itemID)
            local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID) or tostring(itemID)
            root:CreateRadio(L.LUMBER_TYPE_ROW:format(name, BreakUpLargeNumbers(owned)),
                function() return ns.db.settings.lumberType == itemID end, Pick(itemID))
        end
    end)
end

-- ---------------------------------------------------------------------
-- Panel
-- ---------------------------------------------------------------------

local function Build(panel)
    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    panel.title:SetPoint("TOPLEFT", 4, -4)
    panel.title:SetPoint("RIGHT", -4, 0)
    panel.title:SetJustifyH("LEFT")

    panel.sub = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.sub:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -8)
    panel.sub:SetPoint("RIGHT", -4, 0)
    panel.sub:SetJustifyH("LEFT")

    local bar = CreateFrame("Frame", nil, panel)
    bar:SetHeight(20)
    bar:SetPoint("TOPLEFT", panel.sub, "BOTTOMLEFT", 0, -8)
    bar:SetPoint("RIGHT", -4, 0)
    bar.view = ns.Skin.Button(bar, nil, 190, 20)
    bar.view:SetPoint("LEFT", 0, 0)
    bar.view:SetScript("OnClick", ViewMenu)
    bar.type = ns.Skin.Button(bar, nil, 220, 20)
    bar.type:SetPoint("LEFT", bar.view, "RIGHT", 6, 0)
    bar.type:SetScript("OnClick", TypeMenu)
    panel.bar = bar

    local header = CreateFrame("Frame", nil, panel)
    header:SetHeight(18)
    header:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -10)
    header:SetPoint("RIGHT", -26, 0)
    for name, key in pairs({ name = "DECOR", lumber = "LUMBER", cost = "COST", sells = "SELLS", per = "PER",
        day = "DAY", verdict = "VERDICT", status = "STATUS" }) do
        local justify = (name == "lumber" or name == "cost" or name == "sells" or name == "per" or name == "day")
            and "RIGHT" or "LEFT"
        Column(header, name, "GameFontNormalSmall", justify):SetText(L["LUMBER_HEAD_" .. key])
    end

    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", -26, 4)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(_, width) content:SetWidth(width) end)
    panel.scroll = scroll
    panel.content = content
    panel.rows = {}

    panel.empty = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    panel.empty:SetPoint("TOPLEFT", scroll, "TOPLEFT", 4, -8)
    panel.empty:SetPoint("RIGHT", -30, 0)
    panel.empty:SetJustifyH("LEFT")
end

-- Brings the clicked recipe back into view when the list re-sorts and moves it.
ScrollToSelected = function(panel, rows)
    if not selected then return end
    local index
    for i, e in ipairs(rows) do
        if e.spellID == selected then index = i break end
    end
    if not index or index == shownAt then return end
    shownAt = index
    -- The scroll range only updates after the content's new height is laid out.
    C_Timer.After(0, function()
        local scroll = panel.scroll
        local top = (index - 1) * ROW_HEIGHT
        local now, height = scroll:GetVerticalScroll(), scroll:GetHeight()
        if top < now or top + ROW_HEIGHT > now + height then
            scroll:SetVerticalScroll(math.min(math.max(0, top - ROW_HEIGHT * 2), scroll:GetVerticalScrollRange()))
        end
    end)
end

local function Refresh(panel, reason)
    if reason == "AC_SCAN_PROGRESS" then return end
    local s = ns.db.settings
    local view = s.lumberView or "all"
    local rows, counts = ns.LumberCrafting:List(view, s.lumberType)

    panel.title:SetText(L.LUMBER_TITLE:format(counts.worth, counts.shown))
    panel.sub:SetText(L.LUMBER_SUB)
    panel.bar.view:SetText(L.LUMBER_VIEW_BUTTON:format(L["LUMBER_VIEW_" .. view:upper()]))
    local typeName = s.lumberType and C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(s.lumberType)
    panel.bar.type:SetText(L.LUMBER_TYPE_BUTTON:format(typeName or L.LUMBER_TYPE_ALL))
    if #rows == 0 then
        panel.empty:SetText(view == "known" and L.LUMBER_EMPTY_KNOWN or L.LUMBER_EMPTY)
    else
        panel.empty:SetText("")
    end

    for i, e in ipairs(rows) do
        local row = panel.rows[i] or CreateRow(panel.content, i)
        panel.rows[i] = row
        SetRow(row, e)
    end
    for i = #rows + 1, #panel.rows do
        panel.rows[i]:Hide()
    end
    panel.content:SetHeight(math.max(1, #rows * ROW_HEIGHT))
    ScrollToSelected(panel, rows)
end

ns.MainWindow:AddTab({ name = L.TAB_LUMBER, Build = Build, Refresh = Refresh })
ns.MainWindow:RefreshOn("AC_LUMBER_CHANGED")

ns:RegisterCommand("lumber", function() ns.MainWindow:ShowTab(L.TAB_LUMBER) end, L.HELP_LUMBER)
