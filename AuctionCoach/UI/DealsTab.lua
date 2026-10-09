-- Auction Coach - "Deals" tab, three views:
--   Deals         items listed well below their usual price on this realm
--   Other realms  cross-realm flips between the player's realms (Advice/Flips.lua)
--   Shopping      the shopping list, with what each item is listed at now
--                 (Data/Shopping.lua); items are added from the bar below
-- At the AH, clicking a row opens that item's listings. Buying is always
-- left to the player.

local _, ns = ...
local L, Util, Compat, Phrases = ns.L, ns.Util, ns.Compat, ns.Phrases

local DealsTab = {}
ns.DealsTab = DealsTab

local ROW_HEIGHT = 22
-- Older than this, the "prices are old" hint replaces the empty message.
local OLD_AFTER = 2 * 3600
local MODES = { "deals", "flips", "shopping" }
local MODE_WIDTH, MODE_HEIGHT = 92, 20
local ADD_BAR_HEIGHT = 30

-- Column layout: x offset and width, shared by header and rows.
local COLUMNS = {
    name = { 26, 212 },
    price = { 244, 82 },
    usual = { 330, 82 },
    profit = { 416, 82 },
    speed = { 502, 52 },
}

local HEADERS = {
    deals = { price = "DEALS_COL_PRICE", usual = "DEALS_COL_USUAL", profit = "DEALS_COL_PROFIT", speed = "SELL_COL_SPEED" },
    flips = { price = "FLIPS_COL_BUY", usual = "FLIPS_COL_SELL", profit = "DEALS_COL_PROFIT", speed = "SELL_COL_SPEED" },
    shopping = { price = "SHOP_COL_LOWEST", usual = "SHOP_COL_MAX", profit = "SHOP_COL_STATUS", speed = nil },
}

local STATUS_COLORS = {
    BUY = "|cff66ff66",
    WAIT = "|cffcccccc",
    OLD = "|cffffaa33",
    UNKNOWN = "|cff9d9d9d",
}

local panelRef
local mode = "deals"

local function Column(parent, name, template, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", template)
    fs:SetPoint("LEFT", COLUMNS[name][1], 0)
    fs:SetWidth(COLUMNS[name][2])
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

local function TooltipLines(row)
    if row.kind == "flips" then return Phrases.Flip(row.entry) end
    if row.kind == "shopping" then return Phrases.Shop(row.entry) end
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
        GameTooltip:AddLine(L.SHOP_REMOVE_TIP, 0.6, 0.8, 1, true)
    end
    if Compat.IsAuctionHouseOpen() and row.kind ~= "flips" then
        GameTooltip:AddLine(L.DEALS_SUB_AH, 0.6, 0.8, 1, true)
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
            if self.kind == "shopping" and ns.Shopping:Remove(entry.key) then
                GameTooltip:Hide()
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

local function SetRow(row, entry, kind)
    row.entry, row.kind = entry, kind
    local itemID = Util.ItemIDFromKey(entry.key) or Util.PET_CAGE_ITEM_ID
    row.icon:SetTexture(Compat.GetItemIconByID(itemID))
    local name = Util.NamedLink(entry.key) or ("|cff9d9d9d" .. L.ITEM_LOADING .. "|r")

    if kind == "shopping" then
        row.name:SetText(name)
        row.price:SetText(entry.lowest and Util.FormatMoneyIcons(entry.lowest) or "|cff9d9d9d-|r")
        row.usual:SetText(Util.FormatMoneyIcons(entry.max))
        row.profit:SetText(STATUS_COLORS[entry.status] .. L["SHOP_STATUS_" .. entry.status] .. "|r")
        row.speed:SetText("")
    else
        if kind == "flips" then
            name = name .. " |cff9d9d9d" .. L.FLIPS_ROUTE:format(entry.buyRealm, entry.sellRealm) .. "|r"
        end
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

-- ---------------------------------------------------------------------
-- Panel
-- ---------------------------------------------------------------------

local function SetMode(panel, newMode)
    mode = newMode
    for name, button in pairs(panel.modeButtons) do button:SetActive(name == mode) end
    for col, label in pairs(panel.headers) do
        local key = HEADERS[mode][col]
        label:SetText(key and L[key] or "")
    end
    panel.addBar:SetShown(mode == "shopping")
    panel.scroll:SetPoint("BOTTOMRIGHT", -26, mode == "shopping" and ADD_BAR_HEIGHT or 4)
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

    local header = CreateFrame("Frame", nil, panel)
    header:SetHeight(18)
    header:SetPoint("TOPLEFT", panel.sub, "BOTTOMLEFT", 0, -10)
    header:SetPoint("RIGHT", -26, 0)
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

-- title, sub, empty text, entries for the current mode.
local function ModeContent()
    local s = ns.db.settings
    local minProfit = Util.FormatMoneyIcons(s.dealMinProfit)
    if mode == "flips" then
        local list = ns.Flips:List()
        local empty = ""
        if list.realms < 2 then
            empty = L.FLIPS_NEED_REALMS
        elseif #list.items == 0 then
            empty = ns.Prices.ActiveData() and L.FLIPS_EMPTY or L.FLIPS_NEED_APP
        end
        return L.FLIPS_TITLE:format(#list.items), L.FLIPS_SUB:format(minProfit), empty, list.items
    elseif mode == "shopping" then
        local items = ns.Shopping:Items()
        local buy = 0
        for _, item in ipairs(items) do
            if item.status == "BUY" then buy = buy + 1 end
        end
        return L.SHOP_TITLE:format(#items, buy), L.SHOP_SUB, #items == 0 and L.SHOP_EMPTY or "", items
    end
    local list = ns.Deals:List()
    local sub = L.DEALS_SUB:format(math.floor(s.dealMinDiscount * 100 + 0.5), minProfit)
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

-- Opens the Deals tab on one view ("deals", "flips" or "shopping").
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
