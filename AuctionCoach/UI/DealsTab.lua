-- Auction Coach - "Deals" tab, four views:
--   Deals         items listed well below their usual price on this realm
--   Other realms  cross-realm flips between the player's realms (Advice/Flips.lua)
--   Shopping      the shopping list, with what each item is listed at now
--                 (Data/Shopping.lua); items are added from the bar below
--   Craft         craft or sell: your recipes' profit over their materials
--                 (Advice/Crafting.lua)
-- At the AH, clicking a row opens that item's listings. Buying is always
-- left to the player.

local _, ns = ...
local L, Util, Compat, Phrases = ns.L, ns.Util, ns.Compat, ns.Phrases

local DealsTab = {}
ns.DealsTab = DealsTab

local ROW_HEIGHT = 22
-- Older than this, the "prices are old" hint replaces the empty message.
local OLD_AFTER = 2 * 3600
local MODES = { "deals", "flips", "shopping", "craft" }
local MODE_WIDTH, MODE_HEIGHT = 86, 20
local ADD_BAR_HEIGHT = 30

-- Column layout: x offset, width and share of extra window width, shared
-- by header and rows.
local COLUMNS = {
    name = { 26, 212, 0.55 },
    price = { 244, 82, 0.15 },
    usual = { 330, 82, 0.15 },
    profit = { 416, 82, 0.15 },
    speed = { 502, 52 },
}

local HEADERS = {
    deals = { price = "DEALS_COL_PRICE", usual = "DEALS_COL_USUAL", profit = "DEALS_COL_PROFIT", speed = "SELL_COL_SPEED" },
    flips = { price = "FLIPS_COL_BUY", usual = "FLIPS_COL_SELL", profit = "DEALS_COL_PROFIT", speed = "SELL_COL_SPEED" },
    shopping = { price = "SHOP_COL_LOWEST", usual = "SHOP_COL_MAX", profit = "SHOP_COL_STATUS", speed = nil },
    craft = { price = "CRAFT_COL_COST", usual = "CRAFT_COL_VALUE", profit = "DEALS_COL_PROFIT", speed = "SELL_COL_SPEED" },
}

local STATUS_COLORS = {
    BUY = "|cff66ff66",
    WAIT = "|cffcccccc",
    OLD = "|cffffaa33",
    UNKNOWN = "|cff9d9d9d",
}

local panelRef
local mode = "deals"
-- Ticked rows, by FlipID: flips for "Add flips to shopping list", your own
-- items (Flips:YourItems) for "Add yours to sell lists".
local checked = {}
local UpdateFlipBar

local function FlipID(flip)
    return (flip.own and "own:" or "") .. flip.key .. " > " .. flip.buyRealm
end

local function Tickable(entry)
    return not entry.heading
end

-- Whether your own item is on the sell list of the realm it sells better on.
local function OnSellList(entry)
    local group = entry.own and ns.SellLists.GroupOf(entry.sellRealm)
    local list = group and ns.db.sellLists and ns.db.sellLists[group]
    return list and list[entry.key] ~= nil
end

local Column = ns.Skin.Columns(COLUMNS)

local function TooltipLines(row)
    if row.kind == "flips" then return Phrases.Flip(row.entry) end
    if row.kind == "shopping" then return Phrases.Shop(row.entry) end
    if row.kind == "craft" then return Phrases.Craft(row.entry) end
    return Phrases.Deal(row.entry)
end

local function ShowRowTooltip(row)
    local entry = row.entry
    if not entry then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    local link = Util.NamedLink(entry.key)
    if link and link:find("item:") then
        GameTooltip:SetHyperlink(link)
    else
        GameTooltip:SetText(link or entry.key)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L.ADDON_TITLE, 1, 0.82, 0)
    for _, line in ipairs(TooltipLines(row)) do
        GameTooltip:AddLine(line, 1, 1, 1, true)
    end
    if row.kind == "shopping" then
        GameTooltip:AddLine(L.SHOP_MENU_TIP, 0.6, 0.8, 1, true)
    end
    if Compat.IsAuctionHouseOpen() and row.kind ~= "flips" then
        GameTooltip:AddLine(L.DEALS_SUB_AH, 0.6, 0.8, 1, true)
    end
    if row.kind == "flips" and entry.own then
        GameTooltip:AddLine(OnSellList(entry) and L.SELL_ON_LIST:format(entry.sellRealm)
            or L.SELL_TICK_TIP:format(entry.sellRealm), 0.6, 0.8, 1, true)
    end
    GameTooltip:Show()
end

local function CreateRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT")
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    ns.Skin.RowBand(row)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", 2, 0)

    -- Flips only: a tick box where the icon goes.
    row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.check:SetSize(22, 22)
    row.check:SetPoint("LEFT", 0, 0)
    row.check:Hide()
    row.check:SetScript("OnClick", function(self)
        if row.flipID then checked[row.flipID] = self:GetChecked() or nil end
        UpdateFlipBar()
    end)

    row.name = Column(row, "name", "GameFontHighlight")
    row.price = Column(row, "price", "GameFontHighlight", "RIGHT")
    row.usual = Column(row, "usual", "GameFontHighlight", "RIGHT")
    row.profit = Column(row, "profit", "GameFontHighlight", "RIGHT")
    row.speed = Column(row, "speed", "GameFontHighlightSmall", "RIGHT")

    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.08)

    row:SetScript("OnEnter", ShowRowTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self, button)
        local entry = self.entry
        if not entry then return end
        if button == "RightButton" then
            if self.kind == "shopping" then
                GameTooltip:Hide()
                ns.ShoppingEditor:RowMenu(self, entry)
            end
            return
        end
        -- Flips are bought on another realm, so there is nothing to open here.
        if self.kind ~= "flips" and Compat.ShowAtAuctionHouse(entry.key, Util.NamedLink(entry.key), entry.lowest or entry.price) then
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        end
    end)
    return row
end

local function Speed(salesPerDay)
    if not salesPerDay then return "" end
    if salesPerDay < 1 then return "<1" end
    return BreakUpLargeNumbers(math.floor(salesPerDay + 0.5))
end

-- A route heading over a group of flips: only its text, no tooltip or click.
local function SetHeading(row, text)
    row.entry, row.kind, row.flipID = nil, nil, nil
    row.icon:Hide()
    row.check:Hide()
    row.name:SetFontObject("GameFontNormal")
    row.name:SetText(text)
    row.price:SetText("")
    row.usual:SetText("")
    row.profit:SetText("")
    row.speed:SetText("")
    row:Show()
end

local function SetRow(row, entry, kind)
    if entry.heading then return SetHeading(row, entry.heading) end
    row.entry, row.kind = entry, kind
    row.flipID = kind == "flips" and Tickable(entry) and FlipID(entry) or nil
    row.icon:SetShown(not row.flipID)
    row.check:SetShown(row.flipID ~= nil)
    if row.flipID then row.check:SetChecked(checked[row.flipID] == true) end
    row.name:SetFontObject("GameFontHighlight")
    local itemID = Util.ItemIDFromKey(entry.key) or Util.PET_CAGE_ITEM_ID
    row.icon:SetTexture(Compat.GetItemIconByID(itemID))
    local name = Util.NamedLink(entry.key) or ("|cff9d9d9d" .. L.ITEM_LOADING .. "|r")

    if kind == "shopping" then
        if entry.need then name = name .. " |cff9d9d9dx" .. entry.need .. "|r" end
        if entry.note then name = name .. " |cff9d9d9d(" .. entry.note .. ")|r" end
        row.name:SetText(name)
        row.price:SetText(entry.lowest and Util.FormatMoneyIcons(entry.lowest) or "|cff9d9d9d-|r")
        row.usual:SetText(Util.FormatMoneyIcons(entry.max))
        row.profit:SetText(STATUS_COLORS[entry.status] .. L["SHOP_STATUS_" .. entry.status] .. "|r")
        row.speed:SetText("")
    elseif kind == "craft" then
        row.name:SetText(name .. " |cff9d9d9d" .. Util.ShortName(entry.char) .. "|r")
        row.price:SetText(Util.FormatMoneyIcons(entry.cost))
        row.usual:SetText(Util.FormatMoneyIcons(entry.value))
        row.profit:SetText((entry.profit > 0 and "|cff66ff66" or "|cffff7070")
            .. Phrases.SignedMoney(entry.profit, Util.FormatMoneyIcons) .. "|r")
        row.speed:SetText(Speed(entry.salesPerDay))
    else
        if entry.own and OnSellList(entry) then name = name .. " |cff99ccff" .. L.SELL_TAG .. "|r" end
        row.name:SetText(name)
        row.price:SetText(Util.FormatMoneyIcons(entry.price))
        row.usual:SetText(Util.FormatMoneyIcons(entry.resell))
        row.profit:SetText("|cff66ff66" .. Util.FormatMoneyIcons(entry.profit) .. "|r")
        row.speed:SetText(Speed(entry.salesPerDay))
    end
    row:Show()
end

-- ---------------------------------------------------------------------
-- Shopping list add bar
-- ---------------------------------------------------------------------

local function EditBox(parent, width, placeholder)
    local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    box:SetSize(width, 20)
    box:SetAutoFocus(false)
    box:SetFontObject(ChatFontNormal)
    box:SetTextInsets(6, 6, 0, 0)
    ns.Skin.Backdrop(box, { 0, 0, 0, 0.5 }, ns.Skin.BORDER)
    box.placeholder = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    box.placeholder:SetPoint("LEFT", 6, 0)
    box.placeholder:SetText(placeholder)
    box:SetScript("OnTextChanged", function(self) self.placeholder:SetShown(self:GetText() == "") end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return box
end

local function AddFromBar(bar)
    local text = bar.item:GetText()
    local key = Util.ItemKeyFromLink(text)
    local price = ns.Shopping.ParsePrice(bar.price:GetText())
    if not key or not price then
        bar.hint:SetText("|cffff8080" .. L.SHOP_ADD_INVALID .. "|r")
        return
    end
    ns.Shopping:Add(key, price, text)
    bar.item:SetText("")
    bar.price:SetText("")
    bar.item:ClearFocus()
    bar.price:ClearFocus()
    bar.hint:SetText("")
end

local function BuildAddBar(panel)
    local bar = CreateFrame("Frame", nil, panel)
    bar:SetHeight(ADD_BAR_HEIGHT - 6)
    bar:SetPoint("BOTTOMLEFT", 0, 0)
    bar:SetPoint("BOTTOMRIGHT", 0, 0)

    bar.label = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bar.label:SetPoint("LEFT", 4, 0)
    bar.label:SetText(L.SHOP_ADD_LABEL)

    bar.item = EditBox(bar, 230, L.SHOP_ADD_ITEM)
    bar.item:SetPoint("LEFT", bar.label, "RIGHT", 8, 0)
    bar.price = EditBox(bar, 80, L.SHOP_ADD_PRICE)
    bar.price:SetPoint("LEFT", bar.item, "RIGHT", 6, 0)
    bar.add = ns.Skin.Button(bar, L.SHOP_ADD_BUTTON, 60, 20)
    bar.add:SetPoint("LEFT", bar.price, "RIGHT", 6, 0)
    bar.add:SetScript("OnClick", function() AddFromBar(bar) end)

    bar.item:SetScript("OnEnterPressed", function() bar.price:SetFocus() end)
    bar.item:SetScript("OnTabPressed", function() bar.price:SetFocus() end)
    bar.price:SetScript("OnEnterPressed", function() AddFromBar(bar) end)

    bar.hint = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.hint:SetPoint("LEFT", bar.add, "RIGHT", 8, 0)
    bar.hint:SetPoint("RIGHT", -4, 0)
    bar.hint:SetJustifyH("LEFT")
    bar.hint:SetWordWrap(false)

    -- Shift-clicking an item while the item box has focus puts its link in.
    hooksecurefunc("ChatEdit_InsertLink", function(link)
        if link and bar.item:HasFocus() then bar.item:SetText(link) end
    end)

    panel.addBar = bar
end

-- Adds the ticked flips to the shopping list, each at the most the player
-- can pay and still make their smallest profit (never below today's price),
-- noted with the realm to buy on so the list groups them.
local function AddChecked()
    local minProfit = ns.db.settings.dealMinProfit or (5 * 10000)
    local added = 0
    for _, flip in ipairs(ns.Flips:List().items) do
        local id = FlipID(flip)
        if checked[id] then
            checked[id] = nil
            local max = math.max(flip.price, Util.AfterCut(flip.resell) - minProfit)
            if ns.Shopping:Add(flip.key, max, Util.NamedLink(flip.key), nil, L.FLIPS_SHOP_NOTE:format(flip.buyRealm)) then
                added = added + 1
            end
        end
    end
    if added > 0 then Util.Print(L.FLIPS_ADDED:format(added)) end
    if panelRef then ns.MainWindow:Refresh() end
end

-- Adds your ticked items to the sell list of the realm each sells better
-- on (Data/SellLists.lua), and says how to get them there.
local function AddCheckedToSellLists()
    local added, realms = 0, {}
    for _, item in ipairs(ns.Flips:YourItems()) do
        local id = FlipID(item)
        if checked[id] then
            checked[id] = nil
            if ns.SellLists:Add(ns.SellLists.GroupOf(item.sellRealm), item.key, item.count) then
                added = added + 1
                if not realms[item.sellRealm] then
                    realms[item.sellRealm] = true
                    realms[#realms + 1] = item.sellRealm
                end
            end
        end
    end
    if added > 0 then Util.Print(L.SELL_ADDED:format(added, table.concat(realms, ", "))) end
    if panelRef then ns.MainWindow:Refresh() end
end

local function BuildFlipBar(panel)
    local bar = CreateFrame("Frame", nil, panel)
    bar:SetHeight(ADD_BAR_HEIGHT - 6)
    bar:SetPoint("BOTTOMLEFT", 0, 0)
    bar:SetPoint("BOTTOMRIGHT", 0, 0)

    bar.add = ns.Skin.Button(bar, L.FLIPS_ADD_CHECKED, 190, 20)
    bar.add:SetPoint("LEFT", 4, 0)
    bar.add:SetScript("OnClick", AddChecked)
    bar.sell = ns.Skin.Button(bar, L.SELL_ADD_CHECKED, 170, 20)
    bar.sell:SetPoint("LEFT", bar.add, "RIGHT", 6, 0)
    bar.sell:SetScript("OnClick", AddCheckedToSellLists)
    bar.sell:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L.SELL_ADD_TIP, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    bar.sell:SetScript("OnLeave", function() GameTooltip:Hide() end)
    bar.clear = ns.Skin.Button(bar, L.FLIPS_CLEAR, 60, 20)
    bar.clear:SetPoint("LEFT", bar.sell, "RIGHT", 6, 0)
    bar.clear:SetScript("OnClick", function()
        wipe(checked)
        ns.MainWindow:Refresh()
    end)

    bar.hint = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.hint:SetPoint("LEFT", bar.clear, "RIGHT", 8, 0)
    bar.hint:SetPoint("RIGHT", -4, 0)
    bar.hint:SetJustifyH("LEFT")
    bar.hint:SetWordWrap(false)
    panel.flipBar = bar
end

function UpdateFlipBar()
    local bar = panelRef and panelRef.flipBar
    if not bar then return end
    local count, own = 0, 0
    for id in pairs(checked) do
        count = count + 1
        if id:find("^own:") then own = own + 1 end
    end
    bar.add:SetEnabled(count - own > 0)
    bar.sell:SetEnabled(own > 0)
    bar.clear:SetEnabled(count > 0)
    bar.hint:SetText(count > 0 and L.FLIPS_CHECKED:format(count) or L.FLIPS_CHECK_HINT)
end

-- ---------------------------------------------------------------------
-- Other realms filters (1.0.7): category, smallest profit, sales a day
-- ---------------------------------------------------------------------

local GOLD = 10000
local PROFIT_STEPS = { 1, 5, 10, 25, 50, 100, 250, 500, 1000 } -- gold
local SALES_STEPS = { 1, 2, 3, 5, 10, 20, 50 }

-- The same settings as Options, so both stay in step.
local function SetSetting(field, value)
    ns.db.settings[field] = value
    ns.Deals:Invalidate()
    ns.Flips:Invalidate()
    ns.MainWindow:Refresh()
end

local function StepMenu(owner, title, note, field, steps, toValue, label)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(title)
        for _, step in ipairs(steps) do
            local value = toValue(step)
            root:CreateRadio(label(step), function() return ns.db.settings[field] == value end,
                function() SetSetting(field, value) end)
        end
        root:CreateTitle(note)
    end)
end

local function CategoryMenu(owner)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(L.FLIPS_FILTER_CATEGORY_TITLE)
        local function Pick(classID)
            return function()
                ns.db.settings.flipCategory = classID
                ns.MainWindow:Refresh()
            end
        end
        root:CreateRadio(L.FLIPS_FILTER_ALL, function() return ns.db.settings.flipCategory == nil end, Pick(nil))
        for _, c in ipairs(ns.Flips.Categories(ns.Flips:List().items, ns.Flips:YourItems())) do
            root:CreateRadio(L.FLIPS_FILTER_CATEGORY_ROW:format(c.name, c.count),
                function() return ns.db.settings.flipCategory == c.classID end, Pick(c.classID))
        end
    end)
end

local function BuildFilterBar(panel)
    local bar = CreateFrame("Frame", nil, panel)
    bar:SetHeight(20)
    bar:SetPoint("TOPLEFT", panel.sub, "BOTTOMLEFT", 0, -8)
    bar:SetPoint("RIGHT", -4, 0)

    bar.category = ns.Skin.Button(bar, nil, 200, 20)
    bar.category:SetPoint("LEFT", 0, 0)
    bar.category:SetScript("OnClick", CategoryMenu)
    bar.profit = ns.Skin.Button(bar, nil, 130, 20)
    bar.profit:SetPoint("LEFT", bar.category, "RIGHT", 6, 0)
    bar.profit:SetScript("OnClick", function(self)
        StepMenu(self, L.FLIPS_FILTER_PROFIT_TITLE, L.FLIPS_FILTER_PROFIT_NOTE, "dealMinProfit", PROFIT_STEPS,
            function(gold) return gold * GOLD end, function(gold) return L.OPT_GOLD:format(gold) end)
    end)
    bar.sales = ns.Skin.Button(bar, nil, 140, 20)
    bar.sales:SetPoint("LEFT", bar.profit, "RIGHT", 6, 0)
    bar.sales:SetScript("OnClick", function(self)
        StepMenu(self, L.FLIPS_FILTER_SALES_TITLE, L.FLIPS_FILTER_SALES_NOTE, "flipMinSales", SALES_STEPS,
            function(count) return count end, function(count) return L.OPT_PER_DAY:format(count) end)
    end)
    panel.filterBar = bar
end

local function UpdateFilterBar(panel)
    local bar, s = panel.filterBar, ns.db.settings
    bar.category:SetText(L.FLIPS_FILTER_CATEGORY:format(ns.Flips.CategoryName(s.flipCategory) or L.FLIPS_FILTER_ALL))
    bar.profit:SetText(L.FLIPS_FILTER_PROFIT:format(Util.FormatMoneyIcons(s.dealMinProfit)))
    bar.sales:SetText(L.FLIPS_FILTER_SALES:format(BreakUpLargeNumbers(s.flipMinSales or 1)))
end

-- ---------------------------------------------------------------------
-- Panel
-- ---------------------------------------------------------------------

local function SetMode(panel, newMode)
    mode = newMode
    for name, button in pairs(panel.modeButtons) do button:SetActive(name == mode) end
    -- Other realms has its filters between the line under the title and
    -- the column headers.
    panel.filterBar:SetShown(mode == "flips")
    panel.header:ClearAllPoints()
    panel.header:SetPoint("TOPLEFT", mode == "flips" and panel.filterBar or panel.sub, "BOTTOMLEFT", 0, -10)
    panel.header:SetPoint("RIGHT", -26, 0)
    for col, label in pairs(panel.headers) do
        local key = HEADERS[mode][col]
        label:SetText(key and L[key] or "")
    end
    panel.addBar:SetShown(mode == "shopping")
    panel.flipBar:SetShown(mode == "flips")
    local bar = mode == "shopping" or mode == "flips"
    panel.scroll:SetPoint("BOTTOMRIGHT", -26, bar and ADD_BAR_HEIGHT or 4)
    if panel.content then panel.scroll:SetVerticalScroll(0) end
end

local function Build(panel)
    panelRef = panel
    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    panel.title:SetPoint("TOPLEFT", 4, -4)

    panel.modeButtons = {}
    local previous
    for i = #MODES, 1, -1 do
        local name = MODES[i]
        local button = ns.Skin.Tab(panel, L["DEALS_MODE_" .. name:upper()], MODE_WIDTH, MODE_HEIGHT)
        if previous then
            button:SetPoint("RIGHT", previous, "LEFT", -4, 0)
        else
            button:SetPoint("TOPRIGHT", -4, -2)
        end
        button:SetScript("OnClick", function()
            SetMode(panel, name)
            ns.MainWindow:Refresh()
        end)
        panel.modeButtons[name] = button
        previous = button
    end

    panel.sub = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.sub:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -10)
    panel.sub:SetPoint("RIGHT", -4, 0)
    panel.sub:SetJustifyH("LEFT")
    BuildFilterBar(panel)

    local header = CreateFrame("Frame", nil, panel)
    header:SetHeight(18)
    header:SetPoint("TOPLEFT", panel.sub, "BOTTOMLEFT", 0, -10)
    header:SetPoint("RIGHT", -26, 0)
    panel.header = header
    panel.headers = {}
    Column(header, "name", "GameFontNormalSmall", "LEFT"):SetText(L.SELL_COL_ITEM)
    for _, col in ipairs({ "price", "usual", "profit", "speed" }) do
        panel.headers[col] = Column(header, col, "GameFontNormalSmall", "RIGHT")
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

    BuildAddBar(panel)
    BuildFlipBar(panel)
    SetMode(panel, mode)
end

local function DealsEmptyText(list)
    if not list.hasData then return L.DEALS_NEED_APP end
    if not list.newest then return L.DEALS_NO_PRICES end
    if not list.hasHistory then return L.DEALS_NEED_HISTORY end
    if Util.Now() - list.newest > OLD_AFTER then
        return L.DEALS_OLD:format(Util.FormatAge(list.newest))
    end
    return L.DEALS_EMPTY
end

-- Flips grouped by route, each group under a heading naming the realm to
-- buy on and the one to sell on. Groups keep the best profit first, by
-- their best flip, and so do the flips in each.
local function ByRoute(items)
    local groups, order = {}, {}
    for _, flip in ipairs(items) do
        local route = (flip.own and "own > " or "") .. flip.buyRealm .. " > " .. flip.sellRealm
        if not groups[route] then
            local heading = flip.own and L.OWN_GROUP:format(flip.sellRealm, flip.buyRealm)
                or L.FLIPS_GROUP:format(flip.buyRealm, flip.sellRealm)
            groups[route] = { { heading = heading } }
            order[#order + 1] = route
        end
        table.insert(groups[route], flip)
    end
    local entries = {}
    for _, route in ipairs(order) do
        for _, entry in ipairs(groups[route]) do entries[#entries + 1] = entry end
    end
    return entries
end

-- Your items worth moving to another realm first, then the flips.
local function OwnThenFlips(own, flips)
    local all = {}
    for _, item in ipairs(own) do all[#all + 1] = item end
    for _, flip in ipairs(flips) do all[#all + 1] = flip end
    return all
end

-- title, sub, empty text, entries for the current mode.
local function ModeContent()
    local s = ns.db.settings
    local minProfit = Util.FormatMoneyIcons(s.dealMinProfit)
    if mode == "flips" then
        local list, yours = ns.Flips:List(), ns.Flips:YourItems()
        -- The best 100 of the category picked, of each list.
        local flips = ns.Flips.InCategory(list.items, s.flipCategory)
        local own = ns.Flips.InCategory(yours, s.flipCategory)
        local empty = ""
        if list.realms < 2 then
            empty = L.FLIPS_NEED_REALMS
        elseif #list.items == 0 and #yours == 0 then
            empty = ns.Prices.ActiveData() and Phrases.FlipsWhy(list, minProfit) or L.FLIPS_NEED_APP
        elseif #flips == 0 and #own == 0 then
            empty = L.FLIPS_EMPTY_CATEGORY:format(ns.Flips.CategoryName(s.flipCategory))
        end
        return L.FLIPS_TITLE:format(#flips), L.FLIPS_SUB:format(minProfit, BreakUpLargeNumbers(s.flipMinSales or 1)), empty, ByRoute(OwnThenFlips(own, flips))
    elseif mode == "craft" then
        local list = ns.Crafting:List()
        local worth = 0
        for _, item in ipairs(list.items) do
            if item.profit > 0 then worth = worth + 1 end
        end
        local empty = ""
        if list.recipes == 0 then
            empty = L.CRAFT_NEED_RECIPES
        elseif #list.items == 0 then
            empty = L.CRAFT_NO_PRICES
        end
        return L.CRAFT_TITLE:format(worth, #list.items), L.CRAFT_SUB, empty, list.items
    elseif mode == "shopping" then
        local items = ns.Shopping:Items()
        local buy = 0
        for _, item in ipairs(items) do
            if item.status == "BUY" then buy = buy + 1 end
        end
        return L.SHOP_TITLE:format(#items, buy), ns.ShoppingEditor.Hint(L.SHOP_SUB), #items == 0 and L.SHOP_EMPTY or "", items
    end
    local list = ns.Deals:List()
    local sub = L.DEALS_SUB:format(math.floor(s.dealMinDiscount * 100 + 0.5), s.dealMinSales or 10, minProfit)
        .. (Compat.IsAuctionHouseOpen() and (" " .. L.DEALS_SUB_AH) or "")
    return L.DEALS_TITLE:format(#list.items), sub, #list.items == 0 and DealsEmptyText(list) or "", list.items
end

local function Refresh(panel, reason)
    if reason == "AC_SCAN_PROGRESS" then return end
    if ns.Deals:IsStale() then ns.Deals:Invalidate() end
    if ns.Flips:IsStale() then ns.Flips:Invalidate() end

    local title, sub, empty, entries = ModeContent()
    panel.title:SetText(title)
    panel.sub:SetText(sub)
    panel.empty:SetText(empty)

    -- Forget ticks on flips that have left the list.
    if mode == "flips" then
        UpdateFilterBar(panel)
        local shown = {}
        for _, entry in ipairs(entries) do
            if Tickable(entry) then shown[FlipID(entry)] = true end
        end
        for id in pairs(checked) do
            if not shown[id] then checked[id] = nil end
        end
        UpdateFlipBar()
    end

    for i, entry in ipairs(entries) do
        local row = panel.rows[i] or CreateRow(panel.content, i)
        panel.rows[i] = row
        SetRow(row, entry, mode)
    end
    for i = #entries + 1, #panel.rows do
        panel.rows[i]:Hide()
    end
    panel.content:SetHeight(math.max(1, #entries * ROW_HEIGHT))
end

-- Opens the Deals tab on one view ("deals", "flips", "shopping" or "craft").
function DealsTab:ShowMode(newMode)
    ns.MainWindow:ShowTab(L.TAB_DEALS)
    if panelRef then
        SetMode(panelRef, newMode)
        ns.MainWindow:Refresh()
    end
end

ns.MainWindow:AddTab({ name = L.TAB_DEALS, Build = Build, Refresh = Refresh })
ns.MainWindow:RefreshOn("AC_LIVE_PRICE")
ns.MainWindow:RefreshOn("AC_SHOPPING_CHANGED")
ns.MainWindow:RefreshOn("AC_RECIPES_CHANGED")
