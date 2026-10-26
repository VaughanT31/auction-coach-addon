-- Auction Coach - sell lists beside the bank (Data/SellLists.lua).
--
--  +-- Sell lists ---------------------------------------- x -+
--  |  To sell here on Draenor                                 |
--  |  [i] Gunshoes          2 in the warband bank  [Take out] |
--  |  [ Take all out ]                                        |
--  |  For your other realms                                   |
--  |  [i] Spider's Silk     to Silvermoon, 1 in bags  [Put in]|
--  |  [ Put all in the warband bank ]                         |
--  |  Taking out 2 of 3...                                    |
--  +----------------------------------------------------------+
--
-- On the realm that planned the sale, items headed elsewhere go into the
-- warband bank; on the realm that sells them, they come out into the bags,
-- where the repost list at the AH picks them up. Moves happen one stack at
-- a time, waiting for the bags to update before the next, and stop when
-- the bags (or the warband bank) are full.

local _, ns = ...
local L, Util, Compat = ns.L, ns.Util, ns.Compat

local SellListPanel = {}
ns.SellListPanel = SellListPanel

local WIDTH = 330
local ROW = 22
-- After the bags update, a short pause before the next move.
local STEP_DELAY = 0.3
local STEP_TIMEOUT = 3

local panel
local bankOpen = false
local queue                 -- { moves = { { bag, slot, deposit } }, done, total, timer, label }

local function FreeBagSlots()
    local free = 0
    for bag = 0, NUM_BAG_SLOTS or 4 do
        free = free + (C_Container.GetContainerNumFreeSlots(bag) or 0)
    end
    return free
end

-- Stacks of key in some containers: { { bag, slot, count } }.
local function Stacks(bags, key)
    local found = {}
    for _, bag in ipairs(bags) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.hyperlink and not info.isBound and Util.ItemKeyFromLink(info.hyperlink) == key then
                found[#found + 1] = { bag = bag, slot = slot, count = info.stackCount or 1 }
            end
        end
    end
    return found
end

local function Sum(stacks)
    local n = 0
    for _, s in ipairs(stacks) do n = n + s.count end
    return n
end

-- What can be moved right now: { here = { { key, n, stacks } }, away = { { key, group, n, stacks } } }.
--   here  this realm's list, found in the warband bank (to take out)
--   away  other realms' lists, found in the bags (to put in)
local function Read()
    local result = { here = {}, away = {} }
    local bagIDs = {}
    for bag = 0, NUM_BAG_SLOTS or 4 do bagIDs[#bagIDs + 1] = bag end
    for key, entry in pairs(ns.SellLists:Here()) do
        local stacks = Stacks(Compat.Bags.warband, key)
        if #stacks > 0 then
            result.here[#result.here + 1] = { key = key, n = math.min(entry.n, Sum(stacks)), stacks = stacks }
        end
    end
    for _, item in ipairs(ns.SellLists:Elsewhere()) do
        local stacks = Stacks(bagIDs, item.key)
        if #stacks > 0 then
            result.away[#result.away + 1] = { key = item.key, group = item.group,
                                              n = math.min(item.n, Sum(stacks)), stacks = stacks }
        end
    end
    local function ByName(a, b) return (Util.NamedLink(a.key) or a.key) < (Util.NamedLink(b.key) or b.key) end
    table.sort(result.here, ByName)
    table.sort(result.away, ByName)
    return result
end

-- The stacks to move for up to n items.
local function MovesFor(item, deposit, moves)
    local left = item.n
    for _, s in ipairs(item.stacks) do
        if left <= 0 then break end
        moves[#moves + 1] = { bag = s.bag, slot = s.slot, deposit = deposit }
        left = left - s.count
    end
end

-- ---------------------------------------------------------------------
-- Moving
-- ---------------------------------------------------------------------

local function SetStatus(text)
    if panel then panel.status:SetText(text or "") end
end

local function Stop(message)
    if queue and queue.timer then queue.timer:Cancel() end
    queue = nil
    SetStatus(message)
    SellListPanel:Refresh()
end

local Step

local function After(delay)
    if queue.timer then queue.timer:Cancel() end
    queue.timer = C_Timer.NewTimer(delay, function()
        if queue then queue.timer = nil; Step() end
    end)
end

Step = function()
    if not queue then return end
    if not bankOpen then return Stop() end
    local move = table.remove(queue.moves, 1)
    if not move then return Stop(L.SELLP_DONE:format(queue.done)) end
    if not move.deposit and FreeBagSlots() == 0 then
        return Stop(L.SELLP_BAGS_FULL:format(queue.done))
    end
    local info = C_Container.GetContainerItemInfo(move.bag, move.slot)
    if not info then return Step() end -- moved or used since: skip it
    queue.done = queue.done + 1
    SetStatus(queue.label:format(queue.done, queue.total))
    if move.deposit then
        -- Into the warband bank, whichever bank tab is showing.
        C_Container.UseContainerItem(move.bag, move.slot, nil, Enum.BankType and Enum.BankType.Account)
    else
        C_Container.UseContainerItem(move.bag, move.slot)
    end
    After(STEP_TIMEOUT)
end

local function Start(moves, label)
    if queue or #moves == 0 then return end
    queue = { moves = moves, done = 0, total = #moves, label = label }
    Step()
end

function SellListPanel:TakeOut(item)
    local moves = {}
    if item then MovesFor(item, false, moves) else
        for _, it in ipairs(Read().here) do MovesFor(it, false, moves) end
    end
    Start(moves, L.SELLP_TAKING)
end

function SellListPanel:PutIn(item)
    local moves = {}
    if item then MovesFor(item, true, moves) else
        for _, it in ipairs(Read().away) do MovesFor(it, true, moves) end
    end
    Start(moves, L.SELLP_PUTTING)
end

ns.Events:On("BAG_UPDATE_DELAYED", function()
    if queue then After(STEP_DELAY) end
    if panel and panel:IsShown() then Util.Debounce("sellListPanel", 0.2, function() SellListPanel:Refresh() end) end
end)

ns.Events:On("UI_ERROR_MESSAGE", function(_, _, message)
    if queue and (message == ERR_INV_FULL or message == ERR_BANK_FULL) then
        Stop(L.SELLP_FULL:format(math.max(0, queue.done - 1)))
    end
end)

-- ---------------------------------------------------------------------
-- Panel
-- ---------------------------------------------------------------------

local function CreateRow()
    local row = CreateFrame("Frame", nil, panel)
    row:SetHeight(ROW)
    ns.Skin.RowBand(row)
    row:EnableMouse(true)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("LEFT", 2, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.button = ns.Skin.Button(row, "", 76, 18)
    row.button:SetPoint("RIGHT", -2, 0)
    row.button:SetScript("OnClick", function()
        if not row.item then return end
        if row.here then SellListPanel:TakeOut(row.item) else SellListPanel:PutIn(row.item) end
    end)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
    row.name:SetPoint("RIGHT", row.button, "LEFT", -6, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row:SetScript("OnEnter", function(self)
        if not self.item then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local link = Util.NamedLink(self.item.key)
        if link and link:find("item:") then GameTooltip:SetHyperlink(link) else GameTooltip:SetText(link or self.item.key) end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(self.here and L.SELLP_HERE_TIP or L.SELLP_AWAY_TIP:format(ns.SellLists.RealmOf(self.item.group)),
            1, 1, 1, true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

local function Header(text)
    local fs = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    return fs
end

local function Create()
    panel = CreateFrame("Frame", "AuctionCoachSellListPanel", UIParent, "BackdropTemplate")
    panel:SetWidth(WIDTH)
    panel:SetFrameStrata("HIGH")
    panel:EnableMouse(true)
    ns.Skin.Backdrop(panel, ns.Skin.BG, { 0.88, 0.65, 0.15, 0.9 })

    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    panel.title:SetPoint("TOPLEFT", 10, -10)
    panel.title:SetText(L.SELLP_TITLE)

    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)
    close:SetScript("OnClick", function() panel:Hide() end)

    panel.hereHeader = Header("")
    panel.awayHeader = Header(L.SELLP_AWAY)
    panel.takeAll = ns.Skin.Button(panel, L.SELLP_TAKE_ALL, WIDTH - 20, 22)
    panel.takeAll:SetScript("OnClick", function() SellListPanel:TakeOut() end)
    panel.putAll = ns.Skin.Button(panel, L.SELLP_PUT_ALL, WIDTH - 20, 22)
    panel.putAll:SetScript("OnClick", function() SellListPanel:PutIn() end)

    panel.status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.status:SetJustifyH("LEFT")
    panel.status:SetWordWrap(false)

    panel.rows = {}
    panel:Hide()
end

-- Beside the bank window, or beside the bags when the bank frame is hidden
-- by a bag addon.
local function Place()
    panel:ClearAllPoints()
    local bank = _G.BankFrame
    if bank and bank:IsShown() then
        panel:SetPoint("TOPLEFT", bank, "TOPRIGHT", 4, 0)
    else
        panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 420, -120)
    end
end

function SellListPanel:Refresh()
    if not bankOpen or not ns.db or ns.db.settings.sellListPanel == false then
        if panel then panel:Hide() end
        return
    end
    local lists = Read()
    if #lists.here == 0 and #lists.away == 0 and not queue then
        if panel then panel:Hide() end
        return
    end
    if not panel then Create() end

    local y = -38
    local used = 0
    local function Put(region, height, x)
        region:ClearAllPoints()
        region:SetPoint("TOPLEFT", panel, "TOPLEFT", x or 10, y)
        region:SetPoint("RIGHT", panel, "RIGHT", -10, 0)
        y = y - height
    end
    local function Rows(list, here)
        for _, item in ipairs(list) do
            used = used + 1
            local row = panel.rows[used] or CreateRow()
            panel.rows[used] = row
            row.item, row.here = item, here
            local itemID = Util.ItemIDFromKey(item.key) or Util.PET_CAGE_ITEM_ID
            row.icon:SetTexture(Compat.GetItemIconByID(itemID))
            local name = Util.NamedLink(item.key) or ("|cff9d9d9d" .. L.ITEM_LOADING .. "|r")
            local where = here and L.SELLP_IN_WARBAND:format(item.n)
                or L.SELLP_TO_REALM:format(ns.SellLists.RealmOf(item.group), item.n)
            row.name:SetText(name .. " |cff9d9d9d" .. where .. "|r")
            row.button:SetText(here and L.SELLP_TAKE or L.SELLP_PUT)
            row.button:SetEnabled(not queue)
            Put(row, ROW)
            row:Show()
        end
    end

    panel.hereHeader:SetShown(#lists.here > 0)
    panel.takeAll:SetShown(#lists.here > 0)
    if #lists.here > 0 then
        panel.hereHeader:SetText(L.SELLP_HERE:format(GetRealmName()))
        Put(panel.hereHeader, 18)
        Rows(lists.here, true)
        y = y - 4
        Put(panel.takeAll, 28)
        panel.takeAll:SetEnabled(not queue)
    end
    panel.awayHeader:SetShown(#lists.away > 0)
    panel.putAll:SetShown(#lists.away > 0)
    if #lists.away > 0 then
        if #lists.here > 0 then y = y - 6 end
        Put(panel.awayHeader, 18)
        Rows(lists.away, false)
        y = y - 4
        Put(panel.putAll, 28)
        panel.putAll:SetEnabled(not queue)
    end
    for i = used + 1, #panel.rows do panel.rows[i]:Hide() end
    Put(panel.status, 16)
    panel:SetHeight(-y + 8)
    SellListPanel.Place()
    panel:Show()
end

function SellListPanel.Place()
    if panel then Place() end
end

ns.Events:On("BANKFRAME_OPENED", function()
    bankOpen = true
    -- The bank fills its slots over the next moment.
    C_Timer.After(0.3, function() SellListPanel:Refresh() end)
end)

ns.Events:On("BANKFRAME_CLOSED", function()
    bankOpen = false
    if queue then Stop() end
    if panel then panel:Hide() end
end)

ns.Events:On("AC_SELL_LISTS_CHANGED", function()
    if bankOpen then SellListPanel:Refresh() end
end)
