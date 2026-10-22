-- Auction Coach - adding and changing shopping list items without typing
-- commands (0.16):
--   Item     a small window with the item, how many and the most to pay
--            each. Opened by Alt-clicking any item link (bags, chat, the
--            AH; the click is picked in the options), the
--            shopping panel's Add button, or Edit in a row's menu.
--   Craft    the same window for a recipe's materials (the Cheapest
--            materials panel's + button): how many crafts, then each
--            material goes on the list under the recipe's name, less what
--            this character already has in bags and banks.
--   Menu     right-click a shopping list row: search, edit, remove, or
--            remove everything from the same source.

local _, ns = ...
local L, Util, Skin = ns.L, ns.Util, ns.Skin

local Editor = {}
ns.ShoppingEditor = Editor

local WIDTH = 320
local PAD = 14
local LINE = 16

local frame, state

-- Who added a group of items, for headers and menus.
function Editor.GroupName(note)
    return note or L.SHOP_GROUP_MANUAL
end

-- "12g 50s", for the max box (Shopping.ParsePrice reads it back).
local function PlainMoney(copper)
    copper = math.floor(copper or 0)
    local gold, silver = math.floor(copper / 10000), math.floor(copper % 10000 / 100)
    if gold > 0 and silver > 0 then return ("%dg %ds"):format(gold, silver) end
    if gold > 0 then return ("%dg"):format(gold) end
    return ("%ds"):format(math.max(1, silver))
end

-- What this character has, bags and banks (warband bank too).
local function Owned(itemID)
    if not (C_Item and C_Item.GetItemCount) then return 0 end
    local ok, n = pcall(C_Item.GetItemCount, itemID, true, false, true, true)
    return ok and n or 0
end

local function ItemLink(itemID)
    local _, link = ns.Compat.GetItemInfo(itemID)
    return link
end

local function EditBox(parent, width, placeholder, numeric)
    local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    box:SetSize(width, 22)
    box:SetAutoFocus(false)
    box:SetFontObject(ChatFontNormal)
    box:SetTextInsets(6, 6, 0, 0)
    if numeric then box:SetNumeric(true) box:SetMaxLetters(5) end
    Skin.Backdrop(box, { 0, 0, 0, 0.5 }, Skin.BORDER)
    box.placeholder = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    box.placeholder:SetPoint("LEFT", 6, 0)
    box.placeholder:SetText(placeholder or "")
    box:SetScript("OnTextChanged", function(self)
        self.placeholder:SetShown(self:GetText() == "")
        if self.onChange then self.onChange() end
    end)
    box:SetScript("OnEscapePressed", function() frame:Hide() end)
    box:SetScript("OnEnterPressed", function() Editor:Save() end)
    return box
end

local function Label(text, anchor, y)
    local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", anchor or frame, anchor and "BOTTOMLEFT" or "TOPLEFT", anchor and 0 or PAD, y)
    fs:SetText(text)
    return fs
end

local function Create()
    frame = Skin.Window("AuctionCoachShoppingEditor", WIDTH, 200, "DIALOG")
    frame:SetPoint("CENTER", 0, 120)

    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetSize(22, 22)
    frame.icon:SetPoint("TOPLEFT", PAD, -40)
    frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    frame.name = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.name:SetPoint("LEFT", frame.icon, "RIGHT", 8, 0)
    frame.name:SetPoint("RIGHT", -PAD, 0)
    frame.name:SetJustifyH("LEFT")
    frame.name:SetWordWrap(false)

    -- With no item yet (the panel's Add button): shift-click one in.
    frame.itemBox = EditBox(frame, WIDTH - 2 * PAD, L.SHOP_ADD_ITEM)
    frame.itemBox:SetPoint("TOPLEFT", PAD, -40)
    frame.itemBox.onChange = function()
        local key = Util.ItemKeyFromLink(frame.itemBox:GetText())
        if key and state and state.mode == "item" and not state.key then
            local max = ns.Shopping.SuggestedMax(key)
            if max and frame.maxBox:GetText() == "" then frame.maxBox:SetText(PlainMoney(max)) end
        end
    end
    hooksecurefunc("ChatEdit_InsertLink", function(link)
        if link and frame:IsShown() and frame.itemBox:HasFocus() then frame.itemBox:SetText(link) end
    end)

    -- Craft: the materials, one per line.
    frame.list = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.list:SetPoint("TOPLEFT", PAD, -40)
    frame.list:SetPoint("RIGHT", -PAD, 0)
    frame.list:SetJustifyH("LEFT")
    frame.list:SetSpacing(2)

    frame.countLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.countBox = EditBox(frame, 70, "", true)
    frame.countBox:SetPoint("LEFT", frame.countLabel, "RIGHT", 8, 0)
    frame.countBox.onChange = function() if state and state.mode == "craft" then Editor:ShowMaterials() end end
    frame.maxLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.maxLabel:SetText(L.SHOP_EDIT_MAX)
    frame.maxBox = EditBox(frame, 110, L.SHOP_ADD_PRICE)
    frame.maxBox:SetPoint("LEFT", frame.maxLabel, "RIGHT", 8, 0)

    frame.missing = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    frame.missing:SetSize(22, 22)
    frame.missing.text = frame.missing:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.missing.text:SetPoint("LEFT", frame.missing, "RIGHT", 2, 0)
    frame.missing.text:SetText(L.SHOP_CRAFT_MISSING)
    frame.missing:SetChecked(true)
    frame.missing:SetScript("OnClick", function() Editor:ShowMaterials() end)

    frame.hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.hint:SetPoint("BOTTOMLEFT", PAD, 42)
    frame.hint:SetPoint("RIGHT", -PAD, 0)
    frame.hint:SetJustifyH("LEFT")

    frame.save = Skin.Button(frame, L.SHOP_EDIT_SAVE, 80, 22)
    frame.save:SetPoint("BOTTOMRIGHT", -PAD, 12)
    frame.save:SetScript("OnClick", function() Editor:Save() end)
    frame.cancel = Skin.Button(frame, CANCEL, 80, 22)
    frame.cancel:SetPoint("RIGHT", frame.save, "LEFT", -6, 0)
    frame.cancel:SetScript("OnClick", function() frame:Hide() end)
    frame.remove = Skin.Button(frame, L.SHOP_EDIT_REMOVE, 80, 22)
    frame.remove:SetPoint("BOTTOMLEFT", PAD, 12)
    frame.remove:SetScript("OnClick", function()
        if state and state.key then ns.Shopping:Remove(state.key) end
        frame:Hide()
    end)
end

-- Places the count and max rows under y and sizes the window.
local function Rows(y, showMax)
    frame.countLabel:ClearAllPoints()
    frame.countLabel:SetPoint("TOPLEFT", PAD, y - 4)
    frame.maxLabel:ClearAllPoints()
    frame.maxLabel:SetPoint("TOPLEFT", PAD, y - 36)
    frame.maxLabel:SetShown(showMax)
    frame.maxBox:SetShown(showMax)
    frame.missing:ClearAllPoints()
    frame.missing:SetPoint("TOPLEFT", PAD - 4, y - 30)
    local bottom = y - (showMax and 64 or 58)
    frame:SetHeight(-bottom + 60)
end

local function Open(newState)
    if not frame then Create() end
    state = newState
    frame.hint:SetText("")
    frame.itemBox:SetText("")
    frame.maxBox:SetText("")
    frame.countBox:SetText("")
    local craft = state.mode == "craft"
    frame.icon:SetShown(not craft and state.key ~= nil)
    frame.name:SetShown(not craft and state.key ~= nil)
    frame.itemBox:SetShown(not craft and state.key == nil)
    frame.list:SetShown(craft)
    frame.missing:SetShown(craft)
    frame.remove:SetShown(state.mode == "item" and not state.isNew)
    frame.save:SetText(state.isNew and L.SHOP_EDIT_ADD or L.SHOP_EDIT_SAVE)

    if craft then
        frame.title:SetText(L.SHOP_CRAFT_TITLE)
        frame.countLabel:SetText(L.SHOP_CRAFT_COUNT)
        frame.countBox:SetText("1")
        Editor:ShowMaterials()
    else
        frame.title:SetText(state.isNew and L.SHOP_EDIT_TITLE_ADD or L.SHOP_EDIT_TITLE)
        frame.countLabel:SetText(L.SHOP_EDIT_COUNT)
        if state.key then
            local itemID = Util.ItemIDFromKey(state.key) or Util.PET_CAGE_ITEM_ID
            frame.icon:SetTexture(ns.Compat.GetItemIconByID(itemID))
            frame.name:SetText(Util.NamedLink(state.key) or state.link or state.key)
        end
        if state.need then frame.countBox:SetText(tostring(state.need)) end
        if state.max then frame.maxBox:SetText(PlainMoney(state.max)) end
        Rows(-70, true)
    end
    frame:Show()
    local focus = (not craft and state.key == nil) and frame.itemBox or frame.countBox
    focus:SetFocus()
    focus:HighlightText()
end

-- The craft's materials for the count typed in, and what goes on the list.
function Editor:ShowMaterials()
    if not (state and state.mode == "craft") then return end
    local crafts = math.max(0, tonumber(frame.countBox:GetText()) or 0)
    local onlyMissing = frame.missing:GetChecked()
    local lines, cost = { L.SHOP_CRAFT_FOR:format(state.name) }, 0
    state.adds = {}
    for _, m in ipairs(state.items) do
        local want = m.n * crafts
        local have = onlyMissing and Owned(m.itemID) or 0
        local add = math.max(0, want - have)
        local key = Util.SimpleItemKey(m.itemID) or tostring(m.itemID)
        local each = ns.Shopping.SuggestedMax(key)
        local name = Util.NamedLink(key) or ns.Compat.GetItemInfo(m.itemID) or ("item " .. m.itemID)
        local text = ("%dx %s"):format(want, name)
        if have > 0 then text = text .. " |cff999999" .. L.SHOP_CRAFT_HAVE:format(have) .. "|r" end
        if add == 0 then text = "|cff999999" .. text .. "|r" end
        lines[#lines + 1] = text
        if add > 0 then
            state.adds[#state.adds + 1] = { key = key, itemID = m.itemID, n = add, max = each }
            cost = cost + (ns.MaterialPicker.PriceOf(m.itemID) or 0) * add
        end
    end
    lines[#lines + 1] = " "
    lines[#lines + 1] = #state.adds > 0 and L.SHOP_CRAFT_TOTAL:format(#state.adds, Util.FormatMoney(cost))
        or L.SHOP_CRAFT_NOTHING
    frame.list:SetText(table.concat(lines, "\n"))
    Rows(-40 - math.ceil(frame.list:GetStringHeight()) - 10, false)
end

function Editor:Save()
    if not state then return end
    if state.mode == "craft" then
        local added = 0
        for _, a in ipairs(state.adds or {}) do
            if a.max and ns.Shopping:AddMore(a.key, a.n, a.max, ItemLink(a.itemID), state.note) then added = added + 1 end
        end
        if added > 0 then
            Util.Print(L.SHOP_CRAFT_ADDED:format(added, tonumber(frame.countBox:GetText()) or 0, state.name))
        end
        frame:Hide()
        return
    end

    local key, link = state.key, state.link
    if not key then
        link = frame.itemBox:GetText()
        key = Util.ItemKeyFromLink(link)
    end
    local max = ns.Shopping.ParsePrice(frame.maxBox:GetText())
    if not key or not max or max <= 0 then
        frame.hint:SetText("|cffff8080" .. L.SHOP_ADD_INVALID .. "|r")
        return
    end
    local need = tonumber(frame.countBox:GetText())
    if state.isNew and not ns.Shopping:Get(key) then
        ns.Shopping:Add(key, max, link, need)
        Util.Print(L.SHOP_ADDED:format(Util.NamedLink(key) or link or key, Util.FormatMoney(max)))
    else
        ns.Shopping:Update(key, need, max)
    end
    frame:Hide()
end

-- An item to add, from a link. Already on the list: edit it instead.
function Editor:AddItem(link)
    local key = Util.ItemKeyFromLink(link)
    if not key then return end
    if ns.Shopping:Get(key) then return self:Edit(key) end
    Open({ mode = "item", key = key, link = link, isNew = true, max = ns.Shopping.SuggestedMax(key) })
end

-- The panel's Add button: no item yet.
function Editor:AddNew()
    Open({ mode = "item", isNew = true })
end

function Editor:Edit(key)
    local entry = ns.Shopping:Get(key)
    if not entry then return end
    Open({ mode = "item", key = key, need = entry.need, max = entry.max })
end

-- items = { { itemID, n }, ... } for one craft.
function Editor:AddCraft(recipeName, items)
    local merged, order = {}, {}
    for _, m in ipairs(items) do
        if merged[m.itemID] then
            merged[m.itemID].n = merged[m.itemID].n + m.n
        else
            merged[m.itemID] = { itemID = m.itemID, n = m.n }
            order[#order + 1] = merged[m.itemID]
        end
    end
    Open({ mode = "craft", name = recipeName, items = order, note = L.SHOP_GROUP_CRAFT:format(recipeName) })
end

-- Right-click menu for a shopping list row. Without the menu API (older
-- clients), right-click removes the item as before.
function Editor:RowMenu(owner, item)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        ns.Shopping:Remove(item.key)
        return
    end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(Util.NamedLink(item.key) or item.key)
        if ns.Compat.IsAuctionHouseOpen() then
            root:CreateButton(L.SHOP_MENU_SEARCH, function()
                ns.Compat.ShowAtAuctionHouse(item.key, Util.NamedLink(item.key), item.lowest, item.need)
            end)
        end
        root:CreateButton(L.SHOP_MENU_EDIT, function() Editor:Edit(item.key) end)
        root:CreateButton(L.SHOP_MENU_REMOVE, function() ns.Shopping:Remove(item.key) end)
        root:CreateButton(L.SHOP_MENU_REMOVE_GROUP:format(Editor.GroupName(item.note)), function()
            ns.Shopping:RemoveGroup(item.note)
        end)
    end)
end

-- The modifier keys for each choice of the "Add to the shopping list with"
-- option. Exactly these keys must be held, so Alt-click stays free for other
-- addons when another choice is picked.
Editor.CLICKS = {
    alt = { alt = true },
    ctrlalt = { ctrl = true, alt = true },
    shiftalt = { shift = true, alt = true },
    ctrlshift = { ctrl = true, shift = true },
}
Editor.CLICK_ORDER = { "alt", "ctrlalt", "shiftalt", "ctrlshift", "off" }

-- The picked click. Before the option, a checkbox turned Alt-click off.
function Editor.ClickMode()
    local settings = ns.db and ns.db.settings
    if not settings then return "alt" end
    if settings.shopClick == nil and settings.shopAltClick == false then settings.shopClick = "off" end
    return Editor.CLICKS[settings.shopClick] and settings.shopClick or (settings.shopClick == "off" and "off" or "alt")
end

-- "Alt-click", "Ctrl-Alt-click" ... for the hints, or nil when it's off.
function Editor.ClickName()
    local mode = Editor.ClickMode()
    return mode ~= "off" and L["SHOP_CLICK_" .. mode:upper()] or nil
end

-- A hint with "<click> any item to add it." after it, or without when it's off.
-- clickFormat is the sentence with %s for the click (default L.SHOP_CLICK_HINT).
function Editor.Hint(text, clickFormat)
    local click = Editor.ClickName()
    if not click then return text end
    return text .. " " .. (clickFormat or L.SHOP_CLICK_HINT):format(click)
end

local function ClickHeld()
    local keys = Editor.CLICKS[Editor.ClickMode()]
    return keys ~= nil and IsAltKeyDown() == (keys.alt == true) and IsControlKeyDown() == (keys.ctrl == true)
        and IsShiftKeyDown() == (keys.shift == true)
end

-- The picked click on any item link (bags, chat, the AH) adds it.
if HandleModifiedItemClick then
    hooksecurefunc("HandleModifiedItemClick", function(link)
        if not ns.db or not ClickHeld() then return end
        if type(link) ~= "string" or not (link:find("|Hitem:") or link:find("|Hbattlepet:")) then return end
        Editor:AddItem(link)
    end)
end
