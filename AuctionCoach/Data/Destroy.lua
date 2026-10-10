-- Auction Coach - destroy values: is an item worth more disenchanted,
-- milled or prospected than sold as it is?
--
-- The game has no API for what an item destroys into, and the yields
-- change every expansion, so Auction Coach learns them from what the
-- player actually gets:
--   - Milling, prospecting and other salvage recipes in the profession
--     window: the item and how many were used (C_TradeSkillUI.CraftSalvage
--     and the bag count), and every result (TRADE_SKILL_ITEM_CRAFTED_RESULT).
--   - Disenchanting: the bags before and after the Disenchant spell, the
--     gear piece that left and the materials that arrived.
-- What gear disenchants into depends on its quality and expansion, not
-- the item itself, so gear is grouped as "dx:<quality>:<expansion>";
-- everything else is learned per item. (0.7.0 test builds grouped by
-- item level band as "de:..."; those are dropped on load.)
--
--   db.destroy[sourceKey] = { kind = "DE" | "MILL" | "PROSPECT" | "SALVAGE",
--       used = items destroyed, out = { [itemKey] = quantity received } }
--
-- A value is only given once enough has been destroyed to average over.
-- Until then, the desktop app's Data.lua may carry the average from players
-- who share (destroy[sourceKey] = { k, n = players, u = used, o = { [key] =
-- quantity per item } }), which is used instead.

local _, ns = ...
local Util, Compat = ns.Util, ns.Compat

local Destroy = {}
ns.Destroy = Destroy

local MIN_USED = { DE = 3, MILL = 10, PROSPECT = 10, SALVAGE = 5 }
local DISENCHANT = { [13262] = true }
-- Trade goods subclasses: herbs are milled, metal and stone prospected.
local TRADEGOODS, HERB, METAL_STONE = 7, 9, 7

-- ---------------------------------------------------------------------
-- Keys
-- ---------------------------------------------------------------------

-- The key yields are learned under: a gear band for gear, the item key
-- otherwise. nil when the link can't be read yet.
function Destroy.SourceKey(key, link)
    local itemID = Util.ItemIDFromKey(key)
    if not itemID then return nil end
    if Util.IsGear(itemID) then
        if not link then return nil end
        local _, _, quality, _, _, _, _, _, _, _, _, _, _, _, expansion = Compat.GetItemInfo(link)
        if not quality or not expansion then return nil end
        return ("dx:%d:%d"):format(quality, expansion)
    end
    return key
end

local function SalvageKind(itemID)
    local _, _, _, _, _, classID, subclassID = Compat.GetItemInfoInstant(itemID)
    if classID == TRADEGOODS and subclassID == HERB then return "MILL" end
    if classID == TRADEGOODS and subclassID == METAL_STONE then return "PROSPECT" end
    return "SALVAGE"
end

-- ---------------------------------------------------------------------
-- Learning (pure apart from the db)
-- ---------------------------------------------------------------------

-- Adds one destroy session: used source items gave out = { [key] = qty }.
function Destroy:Learn(sourceKey, kind, used, out)
    if not sourceKey or not used or used <= 0 or not next(out) then return end
    local entry = ns.db.destroy[sourceKey]
    if not entry then
        entry = { kind = kind, used = 0, out = {} }
        ns.db.destroy[sourceKey] = entry
    end
    entry.used = entry.used + used
    for key, qty in pairs(out) do
        entry.out[key] = (entry.out[key] or 0) + qty
    end
    ns.Events:Fire("AC_DESTROY_LEARNED", sourceKey)
end

-- The shared average for a source from Data.lua, or nil.
function Destroy.Shared(sourceKey)
    local data = ns.Prices and ns.Prices.ActiveData and ns.Prices.ActiveData()
    local entry = sourceKey and data and type(data.destroy) == "table" and data.destroy[sourceKey]
    if type(entry) ~= "table" or not MIN_USED[entry.k] or type(entry.o) ~= "table" then return nil end
    return entry
end

-- What one source item is worth destroyed, after the AH cut on the
-- materials, or nil when not enough is known yet. The player's own yields
-- once there are enough of them, otherwise the shared average.
-- Returns { value = copper per item, kind, used, unpriced = outputs with no
-- price, players = how many players for a shared value (nil for own) }.
-- price(key) returns a market value per item or nil (defaults to Prices).
function Destroy:Value(key, link, price)
    if not ns.db then return nil end
    local sourceKey = Destroy.SourceKey(key, link)
    if not sourceKey then return nil end
    local entry = ns.db.destroy[sourceKey]
    local perItem, kind, used, players
    if entry and entry.used >= (MIN_USED[entry.kind] or 5) then
        perItem, kind, used = {}, entry.kind, entry.used
        for outKey, qty in pairs(entry.out) do perItem[outKey] = qty / entry.used end
    else
        local shared = Destroy.Shared(sourceKey)
        if not shared then return nil end
        perItem, kind, used, players = shared.o, shared.k, shared.u, shared.n
    end
    price = price or function(k)
        local p = ns.Prices:Get(k)
        return p and p.value
    end
    local value, unpriced = 0, 0
    for outKey, qty in pairs(perItem) do
        local each = price(outKey)
        if each then
            value = value + Util.AfterCut(each) * qty
        else
            unpriced = unpriced + 1
        end
    end
    if value <= 0 then return nil end
    return { value = math.floor(value), kind = kind, used = used, unpriced = unpriced, players = players }
end

-- How far along learning an item is, for items without a value yet:
-- { kind, used, needed }, or nil when nothing has been destroyed.
function Destroy:Progress(key, link)
    if not ns.db then return nil end
    local sourceKey = Destroy.SourceKey(key, link)
    local entry = sourceKey and ns.db.destroy[sourceKey]
    if not entry then return nil end
    local needed = MIN_USED[entry.kind] or 5
    if entry.used >= needed then return nil end
    return { kind = entry.kind, used = entry.used, needed = needed }
end

-- ---------------------------------------------------------------------
-- Salvage recipes (milling, prospecting...)
-- ---------------------------------------------------------------------

local salvage -- { key, itemID, kind, before, out }

-- Crafting takes reagents from the bank and warband bank too, so count
-- everywhere: an item milled straight from the warband bank never leaves
-- the bags.
local function CountEverywhere(itemID)
    return C_Item.GetItemCount(itemID, true, false, true, true) or 0
end

local function FinishSalvage()
    local s = salvage
    salvage = nil
    if not s then return end
    Destroy:Learn(s.key, s.kind, s.before - CountEverywhere(s.itemID), s.out)
end

local watchingSalvage = false

ns.Events:On("AC_LOGIN", function()
    if not (C_TradeSkillUI and C_TradeSkillUI.CraftSalvage) then return end
    watchingSalvage = true
    hooksecurefunc(C_TradeSkillUI, "CraftSalvage", function(_, _, itemTarget)
        local ok, link = pcall(C_Item.GetItemLink, itemTarget)
        local key = ok and link and Util.ItemKeyFromLink(link)
        local itemID = key and Util.ItemIDFromKey(key)
        if not itemID then return end
        -- "Create all" and repeat crafts of the same item are one session.
        if salvage and salvage.key == key then return end
        FinishSalvage()
        salvage = { key = key, itemID = itemID, kind = SalvageKind(itemID),
            before = CountEverywhere(itemID), out = {} }
    end)
end)

ns.Events:On("TRADE_SKILL_ITEM_CRAFTED_RESULT", function(_, result)
    if not salvage or type(result) ~= "table" then return end
    local key = result.hyperlink and Util.ItemKeyFromLink(result.hyperlink)
        or (result.itemID and tostring(result.itemID))
    if key and (result.quantity or 0) > 0 then
        salvage.out[key] = (salvage.out[key] or 0) + result.quantity
    end
    -- Results stop coming once the crafting stops.
    Util.Debounce("salvageDone", 4, FinishSalvage)
end)

-- ---------------------------------------------------------------------
-- Disenchanting
-- ---------------------------------------------------------------------

-- The materials go straight into the bags (or through the loot window),
-- so compare the bags before the cast with the bags after it: the gear
-- piece that left is the source, the stacks that grew are the materials.

local before      -- { slots = [bag:slot] = link, counts = [key] = qty } at cast start
local pending     -- { at, slots, counts } after a successful cast
local WAIT = 30   -- seconds to wait for the materials (loot window left open)

local function SnapshotBags()
    local slots, counts = {}, {}
    for _, bagID in ipairs(Compat.Bags.bags) do
        Compat.ForEachContainerItem(bagID, function(info, bag, slot)
            slots[bag .. ":" .. slot] = info.hyperlink
            local key = Util.ItemKeyFromLink(info.hyperlink)
            if key then counts[key] = (counts[key] or 0) + (info.stackCount or 1) end
        end)
    end
    return { slots = slots, counts = counts }
end

ns.Events:On("UNIT_SPELLCAST_START", function(_, unit, _, spellID)
    if unit == "player" and DISENCHANT[spellID] then before = SnapshotBags() end
end)

ns.Events:On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID)
    if unit == "player" and DISENCHANT[spellID] and before then
        pending = { at = GetTime(), slots = before.slots, counts = before.counts }
        before = nil
    end
end)

-- Pure: the gear link that left the bags and the materials that arrived,
-- or nil while the materials have not shown up yet.
function Destroy.DiffDisenchant(old, now)
    local source
    for slot, link in pairs(old.slots) do
        if now.slots[slot] ~= link then
            local itemID = tonumber(link:match("item:(%d+)"))
            if itemID and Util.IsGear(itemID) then
                source = link
                break
            end
        end
    end
    if not source then return nil end
    local out = {}
    for key, qty in pairs(now.counts) do
        local gained = qty - (old.counts[key] or 0)
        if gained > 0 then out[key] = gained end
    end
    if not next(out) then return nil end
    return source, out
end

ns.Events:On("BAG_UPDATE_DELAYED", function()
    if not pending then return end
    if GetTime() - pending.at > WAIT then
        pending = nil
        return
    end
    local source, out = Destroy.DiffDisenchant(pending, SnapshotBags())
    if not source then return end
    pending = nil
    local key = Util.ItemKeyFromLink(source)
    local sourceKey = key and Destroy.SourceKey(key, source)
    if sourceKey then Destroy:Learn(sourceKey, "DE", 1, out) end
end)

-- ---------------------------------------------------------------------
-- /ac destroy: what has been learned so far
-- ---------------------------------------------------------------------

ns.Events:On("AC_DB_READY", function()
    for sourceKey in pairs(ns.db.destroy) do
        if sourceKey:find("^de:") then ns.db.destroy[sourceKey] = nil end
    end
end)

local function SourceName(sourceKey)
    local quality, expansion = sourceKey:match("^dx:(%d+):(%d+)$")
    if quality then
        return ns.L.DESTROY_LIST_GEAR:format(_G["ITEM_QUALITY" .. quality .. "_DESC"] or quality,
            _G["EXPANSION_NAME" .. expansion] or expansion)
    end
    local itemID = Util.ItemIDFromKey(sourceKey)
    return (itemID and select(2, Compat.GetItemInfo(itemID))) or sourceKey
end

local function PrintList()
    local L = ns.L
    Util.Print(watchingSalvage and L.DESTROY_LIST_WATCHING or L.DESTROY_LIST_NOT_WATCHING)
    local data = ns.Prices.ActiveData()
    local shared = 0
    for _ in pairs(data and type(data.destroy) == "table" and data.destroy or {}) do shared = shared + 1 end
    if shared > 0 then Util.Print(L.DESTROY_LIST_SHARED:format(shared)) end
    local keys = {}
    for sourceKey in pairs(ns.db.destroy) do keys[#keys + 1] = sourceKey end
    table.sort(keys)
    if #keys == 0 then
        Util.Print(L.DESTROY_LIST_EMPTY)
        return
    end
    for _, sourceKey in ipairs(keys) do
        local entry = ns.db.destroy[sourceKey]
        local outputs = 0
        for _ in pairs(entry.out) do outputs = outputs + 1 end
        Util.Print(L.DESTROY_LIST_ROW:format(SourceName(sourceKey), entry.kind, entry.used,
            MIN_USED[entry.kind] or 5, outputs))
    end
end

-- Item names the game hasn't loaded yet print as numbers, so ask for
-- them first and print a moment later.
ns:RegisterCommand("destroy", function()
    local waiting = false
    for sourceKey in pairs(ns.db.destroy) do
        local itemID = not sourceKey:find("^dx:") and Util.ItemIDFromKey(sourceKey)
        if itemID and not Compat.GetItemInfo(itemID) then
            Compat.RequestLoadItemDataByID(itemID)
            waiting = true
        end
    end
    if waiting then C_Timer.After(1, PrintList) else PrintList() end
end, ns.L.HELP_DESTROY)
