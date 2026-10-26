-- Auction Coach - the repost list beside the Auction House.
--
--  +-- Repost list: 6 items, 3 ready --------------------- x -+
--  |  [i] Sunfire Silk          x20     9g 80s      Ready      |
--  |  [i] Bright Linen          x200    1g 20s      Ready      |
--  |  [i] Mithril Ore            -        -         None here  |
--  |  Next: Sunfire Silk x20 at 9g 80s each                    |
--  |  [          Post next          ]  [ Skip ]                |
--  |  Drag an item here to add it. Right-click an item for more.|
--  +-----------------------------------------------------------+
--
-- Blizzard allows one post per click, so Post next posts the next ready
-- item in list order at Auction Coach's suggested price (never under the
-- item's floor), then moves on. When the price is more than a few minutes
-- old, the first click checks it on the AH and the next click posts.
-- Posts go through C_AuctionHouse like Blizzard's own Post button, so sale
-- tracking sees them as usual.
--
-- It stacks under the post helper and the shopping list when those are
-- open, so the panels beside the AH never overlap.

local _, ns = ...
local L, Util, Compat = ns.L, ns.Util, ns.Compat

local RepostPanel = {}
ns.RepostPanel = RepostPanel

local WIDTH = 360
local ROW = 20
local LINES = 10
local TOP = -34
-- A price older than this is checked on the AH before posting.
local FRESH = 5 * 60
-- After a check with no listings, post at the known price anyway.
local CHECK_WAIT = 60

-- Columns from the right edge: { right offset, width }.
local COL = {
    status = { -4, 74 },
    price = { -82, 72 },
    count = { -158, 40 },
}

local STATUS_COLORS = {
    READY = "|cff66ff66", NONE = "|cff9d9d9d", FLOOR = "|cffffaa33", HOLD = "|cffffaa33",
    VENDOR = "|cffcccccc", NO_PRICE = "|cff9d9d9d",
}

local panel, rows
local items = {}
local offset = 0
local closedThisVisit = false
local skipped = {}          -- [key] = true: skipped this AH visit
local checked = {}          -- [key] = when its price was last searched
local confirm               -- a post the AH asked to confirm: { fn, args, name }

local function Enabled()
    return ns.db and ns.db.settings.repostPanel ~= false
end

local function Name(item)
    return Util.NamedLink(item.key) or item.link or ("|cff9d9d9d" .. L.ITEM_LOADING .. "|r")
end

local function SetStatus(text)
    if panel then panel.status:SetText(text or "") end
end

-- ---------------------------------------------------------------------
-- Posting
-- ---------------------------------------------------------------------

local function NextItem()
    for _, item in ipairs(items) do
        if item.status == "READY" and not skipped[item.key] then return item end
    end
    return nil
end

local function NeedsCheck(item)
    local now = Util.Now()
    return (item.suggestion.lowestAt or 0) < now - FRESH and (checked[item.key] or 0) < now - CHECK_WAIT
end

local function Ready()
    return not C_AuctionHouse.IsThrottledMessageSystemReady or C_AuctionHouse.IsThrottledMessageSystemReady()
end

local function Post(item)
    local bagID, slot = ns.Sell:FindInBags(item.key)
    if not bagID then
        skipped[item.key] = true
        return SetStatus(L.REPOST_NOT_FOUND:format(Name(item)))
    end
    local location = ItemLocation:CreateFromBagAndSlot(bagID, slot)
    if not C_Item.DoesItemExist(location) or not C_AuctionHouse.IsSellItemValid(location, false) then
        skipped[item.key] = true
        return SetStatus(L.REPOST_CANT_SELL:format(Name(item)))
    end

    if NeedsCheck(item) then
        local itemKey = C_AuctionHouse.GetItemKeyFromItem(location)
        if itemKey then
            checked[item.key] = Util.Now()
            C_AuctionHouse.SendSearchQuery(itemKey,
                { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }, true)
            return SetStatus(L.REPOST_CHECKING:format(Name(item)))
        end
    end

    local duration = tonumber(ns.db.settings.repostDuration) or 2
    local price = item.price
    local commodity = C_AuctionHouse.GetItemCommodityStatus(location) == Enum.ItemCommodityStatus.Commodity
    local quantity, fn, confirmFn, args
    if commodity then
        quantity = item.count
        if item.max > 0 then quantity = math.min(quantity, item.max) end
        fn, confirmFn = C_AuctionHouse.PostCommodity, C_AuctionHouse.ConfirmPostCommodity
        args = { location, duration, quantity, price }
    else
        quantity = C_Item.GetStackCount(location) or 1
        fn, confirmFn = C_AuctionHouse.PostItem, C_AuctionHouse.ConfirmPostItem
        args = { location, duration, quantity, nil, price * quantity }
    end
    confirm = { fn = confirmFn, args = args, name = Name(item), quantity = quantity, price = price }
    SetStatus(L.REPOST_POSTING:format(confirm.name, quantity, Util.FormatMoneyIcons(price)))
    fn(unpack(args, 1, 5))
end

function RepostPanel:PostNext()
    if not Compat.IsAuctionHouseOpen() then return end
    if not Ready() then return SetStatus(L.REPOST_BUSY) end
    if confirm and confirm.waiting then
        -- The AH warned about this post (a price far under the usual): this
        -- click is the player's confirmation.
        local c = confirm
        confirm = nil
        SetStatus(L.REPOST_POSTED:format(c.name, c.quantity, Util.FormatMoneyIcons(c.price)))
        return c.fn(unpack(c.args, 1, 5))
    end
    local item = NextItem()
    if not item then return SetStatus(L.REPOST_NOTHING) end
    Post(item)
end

function RepostPanel:Skip()
    local item = NextItem()
    if item then
        skipped[item.key] = true
        confirm = nil
        SetStatus(L.REPOST_SKIPPED:format(Name(item)))
        self:Refresh()
    end
end

ns.Events:On("AUCTION_HOUSE_POST_WARNING", function()
    if confirm then
        confirm.waiting = true
        SetStatus(L.REPOST_CONFIRM:format(confirm.name))
        RepostPanel:Draw()
    end
end)

ns.Events:On("AUCTION_HOUSE_AUCTION_CREATED", function()
    if confirm and not confirm.waiting then
        SetStatus(L.REPOST_POSTED:format(confirm.name, confirm.quantity, Util.FormatMoneyIcons(confirm.price)))
        confirm = nil
    end
end)

-- ---------------------------------------------------------------------
-- Editing: floor, most per post
-- ---------------------------------------------------------------------

local function EditBoxOf(dialog)
    return dialog.editBox or dialog.EditBox or (dialog.GetEditBox and dialog:GetEditBox())
end

local function Ask(which, text, value, onAccept)
    StaticPopupDialogs[which] = StaticPopupDialogs[which] or {
        button1 = OKAY, button2 = CANCEL, hasEditBox = true, timeout = 0, whileDead = true,
        hideOnEscape = true, preferredIndex = 3,
        OnShow = function(self, data)
            local box = EditBoxOf(self)
            if box then box:SetText(data.value or ""); box:HighlightText() end
        end,
        OnAccept = function(self, data) local box = EditBoxOf(self); data.accept(box and box:GetText() or "") end,
        EditBoxOnEnterPressed = function(self, data)
            data.accept(self:GetText() or "")
            self:GetParent():Hide()
        end,
        EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    }
    StaticPopupDialogs[which].text = text
    StaticPopup_Show(which, nil, nil, { value = value, accept = onAccept })
end

-- "12g 50s", for the floor box (Shopping.ParsePrice reads it back).
local function PlainMoney(copper)
    copper = math.floor(copper or 0)
    local gold, silver = math.floor(copper / 10000), math.floor(copper % 10000 / 100)
    if gold > 0 and silver > 0 then return ("%dg %ds"):format(gold, silver) end
    if gold > 0 then return ("%dg"):format(gold) end
    return ("%ds"):format(silver)
end

local function RowMenu(owner, item)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        ns.Repost:Remove(item.key)
        return
    end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(Name(item))
        if item.sellList then
            -- From the sell list (Data/SellLists.lua): no floor or order of its own.
            root:CreateButton(L.REPOST_MENU_KEEP, function() ns.Repost:Add(item.key, item.link) end)
            root:CreateButton(L.REPOST_MENU_SELL_REMOVE, function() ns.SellLists:Remove(ns.realmGroup, item.key) end)
            return
        end
        root:CreateButton(L.REPOST_MENU_FLOOR:format(Util.FormatMoneyIcons(item.floor)), function()
            Ask("AUCTIONCOACH_REPOST_FLOOR", L.REPOST_ASK_FLOOR, PlainMoney(item.floor), function(text)
                local copper = ns.Shopping.ParsePrice(text)
                if copper then ns.Repost:Set(item.key, "floor", copper) end
            end)
        end)
        root:CreateButton(item.max > 0 and L.REPOST_MENU_MAX:format(item.max) or L.REPOST_MENU_MAX_ALL, function()
            Ask("AUCTIONCOACH_REPOST_MAX", L.REPOST_ASK_MAX, tostring(item.max), function(text)
                ns.Repost:Set(item.key, "max", tonumber(text) or 0)
            end)
        end)
        root:CreateButton(L.REPOST_MENU_UP, function() ns.Repost:Move(item.key, -1) end)
        root:CreateButton(L.REPOST_MENU_DOWN, function() ns.Repost:Move(item.key, 1) end)
        if skipped[item.key] then
            root:CreateButton(L.REPOST_MENU_UNSKIP, function() skipped[item.key] = nil; RepostPanel:Refresh() end)
        end
        root:CreateButton(L.REPOST_MENU_REMOVE, function() ns.Repost:Remove(item.key) end)
    end)
end

-- An item dropped on the panel goes on the list.
local function TakeCursorItem()
    local kind, _, link = GetCursorInfo()
    if kind ~= "item" or not link then return end
    local key = Util.ItemKeyFromLink(link)
    if key then
        ns.Repost:Add(key, link)
        ClearCursor()
    end
end

-- ---------------------------------------------------------------------
-- Panel
-- ---------------------------------------------------------------------

local function Cell(row, col)
    local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("RIGHT", row, "RIGHT", COL[col][1], 0)
    fs:SetWidth(COL[col][2])
    fs:SetJustifyH("RIGHT")
    fs:SetWordWrap(false)
    return fs
end

local function CreateRow(index)
    local row = CreateFrame("Button", nil, panel)
    row:SetHeight(ROW)
    row:SetPoint("TOPLEFT", 8, TOP - (index - 1) * ROW)
    row:SetPoint("RIGHT", -8, 0)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    ns.Skin.RowBand(row)
    row:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
    row:GetHighlightTexture():SetVertexColor(1, 0.82, 0.15, 0.08)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("LEFT", 2, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.status = Cell(row, "status")
    row.price = Cell(row, "price")
    row.count = Cell(row, "count")
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
    row.name:SetPoint("RIGHT", row.count, "LEFT", -6, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row:SetScript("OnClick", function(self, mouse)
        if not self.item then return end
        if GetCursorInfo() then return TakeCursorItem() end
        if mouse == "RightButton" then
            GameTooltip:Hide()
            RowMenu(self, self.item)
        else
            -- Into Blizzard's sell box, to post it by hand instead.
            ns.Sell:PutInSellBox(self.item.key)
        end
    end)
    row:SetScript("OnReceiveDrag", TakeCursorItem)
    row:SetScript("OnEnter", function(self)
        local item = self.item
        if not item then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local link = Util.NamedLink(item.key)
        if link and link:find("item:") then GameTooltip:SetHyperlink(link) else GameTooltip:SetText(Name(item)) end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L.ADDON_TITLE, 1, 0.82, 0)
        GameTooltip:AddLine(L["REPOST_WHY_" .. item.status]:format(Util.FormatMoneyIcons(item.floor)), 1, 1, 1, true)
        GameTooltip:AddLine(L.REPOST_FLOOR_LINE:format(Util.FormatMoneyIcons(item.floor)), 0.8, 0.8, 0.8)
        if item.max > 0 then GameTooltip:AddLine(L.REPOST_MAX_LINE:format(item.max), 0.8, 0.8, 0.8) end
        GameTooltip:AddLine(L.REPOST_ROW_TIP, 0.6, 0.8, 1, true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

local function Create()
    panel = CreateFrame("Frame", "AuctionCoachRepostPanel", AuctionHouseFrame, "BackdropTemplate")
    panel:SetWidth(WIDTH)
    panel:EnableMouse(true)
    panel:EnableMouseWheel(true)
    ns.Skin.Backdrop(panel, ns.Skin.BG, { 0.88, 0.65, 0.15, 0.9 })
    panel:SetScript("OnReceiveDrag", TakeCursorItem)
    panel:SetScript("OnMouseUp", function() if GetCursorInfo() then TakeCursorItem() end end)
    panel:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, math.min(offset - delta, math.max(0, #items - LINES)))
        RepostPanel:Draw()
    end)

    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.title:SetPoint("TOPLEFT", 10, -10)
    panel.title:SetPoint("RIGHT", -30, 0)
    panel.title:SetJustifyH("LEFT")

    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)
    close:SetScript("OnClick", function()
        closedThisVisit = true
        panel:Hide()
    end)

    rows = {}
    for i = 1, LINES do rows[i] = CreateRow(i) end

    panel.empty = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.empty:SetPoint("TOPLEFT", 10, TOP - 4)
    panel.empty:SetPoint("RIGHT", -10, 0)
    panel.empty:SetJustifyH("LEFT")
    panel.empty:SetText(L.REPOST_EMPTY)

    panel.hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.hint:SetPoint("BOTTOMLEFT", 10, 8)
    panel.hint:SetPoint("RIGHT", -10, 0)
    panel.hint:SetJustifyH("LEFT")
    panel.hint:SetSpacing(2)
    panel.hint:SetText(L.REPOST_HINT)

    -- The buttons sit above the hint, however many lines it wraps to.
    panel.post = ns.Skin.Button(panel, L.REPOST_POST, WIDTH - 16 - 74, 24)
    panel.post:SetPoint("BOTTOMLEFT", panel.hint, "TOPLEFT", -2, 8)

    panel.skip = ns.Skin.Button(panel, L.REPOST_SKIP, 70, 24)
    panel.skip:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, 0)
    panel.skip:SetPoint("BOTTOM", panel.post, "BOTTOM")
    panel.skip:SetScript("OnClick", function() RepostPanel:Skip() end)
    panel.post:SetScript("OnClick", function() RepostPanel:PostNext() end)
    panel.post:SetMotionScriptsWhileDisabled(true)
    panel.post:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L.REPOST_POST_TIP, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    panel.post:SetScript("OnLeave", function() GameTooltip:Hide() end)

    panel.suggest = ns.Skin.Button(panel, "", WIDTH - 16, 20)
    panel.suggest:SetPoint("BOTTOMLEFT", panel.post, "TOPLEFT", 0, 20)
    panel.suggest:SetScript("OnClick", function() ns.Repost:AddSuggestions() end)

    panel.status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.status:SetPoint("BOTTOMLEFT", panel.post, "TOPLEFT", 2, 5)
    panel.status:SetPoint("RIGHT", -10, 0)
    panel.status:SetJustifyH("LEFT")
    panel.status:SetWordWrap(false)

    panel:Hide()
end

local function SetRow(row, item)
    local itemID = Util.ItemIDFromKey(item.key) or Util.PET_CAGE_ITEM_ID
    row.icon:SetTexture(Compat.GetItemIconByID(itemID))
    local name = Name(item)
    if skipped[item.key] then name = "|cff9d9d9d" .. ns.Sales.PlainName(name) .. "|r" end
    if item.sellList then name = name .. " |cff99ccff" .. L.REPOST_SELL_TAG .. "|r" end
    row.name:SetText(name)
    row.count:SetText(item.count > 0 and ("x" .. BreakUpLargeNumbers(item.count)) or "|cff9d9d9d-|r")
    row.price:SetText(item.price and Util.FormatMoneyIcons(item.price) or "|cff9d9d9d-|r")
    local status = skipped[item.key] and "|cff9d9d9d" .. L.REPOST_STATUS_SKIPPED .. "|r"
        or (STATUS_COLORS[item.status] .. L["REPOST_STATUS_" .. item.status] .. "|r")
    row.status:SetText(status)
end

function RepostPanel:Draw()
    if not panel then return end
    for i, row in ipairs(rows) do
        local item = items[offset + i]
        row.item = item
        row:SetShown(item ~= nil)
        if item then SetRow(row, item) end
    end
    panel.empty:SetShown(#items == 0)

    local nextItem = NextItem()
    if confirm and confirm.waiting then
        panel.post:SetText(L.REPOST_CONFIRM_BUTTON)
        panel.post:SetEnabled(true)
    elseif nextItem then
        local label = NeedsCheck(nextItem) and L.REPOST_CHECK_BUTTON or L.REPOST_POST_BUTTON
        panel.post:SetText(label:format(ns.Sales.PlainName(Name(nextItem))))
        panel.post:SetEnabled(true)
    else
        panel.post:SetText(L.REPOST_POST)
        panel.post:SetEnabled(false)
    end
    panel.skip:SetEnabled(nextItem ~= nil)

    local suggestions = #ns.Repost:Suggestions()
    panel.suggest:SetShown(suggestions > 0)
    panel.suggest:SetText(L.REPOST_SUGGEST:format(suggestions))
end

function RepostPanel:Refresh()
    if not Enabled() or closedThisVisit or not Compat.IsAuctionHouseOpen() then
        if panel then panel:Hide() end
        return
    end
    items = ns.Repost:Items()
    -- Opens by itself only when something on the list is in the bags;
    -- /ac repost or adding an item opens it anyway.
    local any = false
    for _, item in ipairs(items) do if item.count > 0 then any = true end end
    if not any and not self.forced then
        if panel then panel:Hide() end
        return
    end
    if not panel then Create() end
    local ready = 0
    for _, item in ipairs(items) do
        if item.status == "READY" and not skipped[item.key] then ready = ready + 1 end
    end
    panel.title:SetText(L.REPOST_TITLE:format(#items, ready))
    offset = math.min(offset, math.max(0, #items - LINES))
    self:Draw()
    -- From the real text heights, so wrapped lines never overlap.
    local list = #items > 0 and math.min(#items, LINES) * ROW or (panel.empty:GetStringHeight() + 8)
    local extra = panel.suggest:IsShown() and 26 or 0
    panel:SetHeight(-TOP + list + 6 + extra + 20 + 24 + 8 + panel.hint:GetStringHeight() + 10)
    self:Place()
    panel:Show()
end

-- Under the post helper or the shopping list, whichever is lowest and
-- open, so the panels beside the AH stack instead of overlapping. Hooks
-- them once they exist, to follow when they open, close or move.
local hookedFrames = {}

function RepostPanel:Place()
    if not panel then return end
    for _, name in ipairs({ "AuctionCoachPostHelper", "AuctionCoachShoppingPanel" }) do
        local f = _G[name]
        if f and not hookedFrames[name] then
            hookedFrames[name] = true
            f:HookScript("OnShow", function() RepostPanel:Place() end)
            f:HookScript("OnHide", function() RepostPanel:Place() end)
        end
    end
    panel:ClearAllPoints()
    local shopping, helper = _G.AuctionCoachShoppingPanel, _G.AuctionCoachPostHelper
    if shopping and shopping:IsShown() then
        panel:SetPoint("TOPLEFT", shopping, "BOTTOMLEFT", 0, -6)
    elseif helper and helper:IsShown() then
        panel:SetPoint("TOPLEFT", helper, "BOTTOMLEFT", 0, -6)
    else
        panel:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 4, -24)
    end
end

-- /ac repost: open it at the AH, even when nothing is on the list yet.
function RepostPanel:Open()
    if not Compat.IsAuctionHouseOpen() then
        Util.Print(L.REPOST_NEED_AH)
        return
    end
    closedThisVisit = false
    self.forced = true
    self:Refresh()
end

local function Soon()
    Util.Debounce("repostPanel", 0.3, function() RepostPanel:Refresh() end)
end

for _, event in ipairs({ "AC_REPOST_CHANGED", "AC_SELL_LISTS_CHANGED", "AC_INVENTORY_CHANGED", "AC_LIVE_PRICE", "AC_SCAN_COMPLETE",
                         "AC_DATA_CHANGED" }) do
    ns.Events:On(event, function() if panel or event == "AC_REPOST_CHANGED" then Soon() end end)
end

ns.Events:On("AUCTION_HOUSE_SHOW", function()
    closedThisVisit, offset, confirm = false, 0, nil
    RepostPanel.forced = false
    wipe(skipped)
    -- After the shopping list, which draws on the next frame.
    C_Timer.After(0.1, function() RepostPanel:Refresh() end)
end)

ns.Events:On("AUCTION_HOUSE_CLOSED", function()
    confirm = nil
    if panel then panel:Hide() end
end)
