-- Auction Coach - the repost list: items the player posts again and again,
-- and batches to sell once. Each item has a floor (never post below it)
-- and, for stacks, the most to post at once. The panel at the Auction
-- House (UI/RepostPanel.lua) posts them one click at a time at Auction
-- Coach's suggested price.
--
-- Items sit in groups (0.27): your regulars (no group), named groups you
-- make (Herbs, Transmog, ...) and batches. A group switched off is left out
-- of a posting run. A batch is a set of items to sell once: added from the
-- bags, or the items an expired or cancelled auction sent back by mail.
-- Its items are "until sold": each comes off the list once its character
-- has none left in the bags, on the AH or in the mail, and the batch goes
-- when it's empty. Any item can be made until sold from its menu.
--
--   db.repost = { { k = item key, floor = copper, max = items per post (0 = all
--                   in bags), added = time, g = group id or nil (regulars),
--                   u = true until sold, c = its character, posted = last post }, ... }
--   db.repostGroups = { { id, name, off = true, batch = true, c = charKey, at }, ... }
--   db.repostRegularsOff = true when the regulars are switched off
--   char.returned = { [key] = { n = count, at = time } }: items back from the AH by mail

local _, ns = ...
local L, Util = ns.L, ns.Util

local Repost = {}
ns.Repost = Repost

-- A new item's floor: this share of its usual price, so a crashed market
-- isn't followed all the way down. The player can change it.
local DEFAULT_FLOOR = 0.7
local SILVER = 100
-- Items back from the AH are offered for this long.
local RETURNED_KEEP = 3 * 86400

local function List()
    ns.db.repost = ns.db.repost or {}
    return ns.db.repost
end

local function Groups()
    ns.db.repostGroups = ns.db.repostGroups or {}
    return ns.db.repostGroups
end

local function Find(key)
    for i, entry in ipairs(List()) do
        if entry.k == key then return entry, i end
    end
    return nil
end

local function FindGroup(id)
    for i, group in ipairs(Groups()) do
        if group.id == id then return group, i end
    end
    return nil
end

local function Changed()
    ns.Events:Fire("AC_REPOST_CHANGED")
end

local function DefaultFloor(key, link)
    local s = ns.Rules:SuggestPrice(key, link or ns.db.links[key])
    local usual = s.usual or s.lowest
    if usual and usual > 0 then return math.floor(usual * DEFAULT_FLOOR / SILVER) * SILVER end
    return 0
end

function Repost:Has(key)
    return Find(key) ~= nil
end

function Repost:Get(key)
    return (Find(key))
end

-- opts: { g = group id, u = until sold, quiet = no chat line }
function Repost:Add(key, link, opts)
    if not key or Find(key) then return false end
    opts = opts or {}
    if link then ns.db.links[key] = ns.db.links[key] or link end
    local floor = DefaultFloor(key, link)
    table.insert(List(), { k = key, floor = floor, max = 0, added = Util.Now(), g = opts.g,
                           u = opts.u or nil, c = opts.u and ns.charKey or nil })
    if not opts.quiet then
        Util.Print(L.REPOST_ADDED:format(Util.NamedLink(key) or link or key, Util.FormatMoneyIcons(floor)))
    end
    Changed()
    return true
end

-- A batch emptied by removals goes too.
local function DropEmptyBatches()
    local used = {}
    for _, entry in ipairs(List()) do
        if entry.g then used[entry.g] = true end
    end
    local groups = Groups()
    for i = #groups, 1, -1 do
        if groups[i].batch and not used[groups[i].id] then table.remove(groups, i) end
    end
end

function Repost:Remove(key)
    local _, i = Find(key)
    if not i then return end
    table.remove(List(), i)
    DropEmptyBatches()
    Changed()
end

function Repost:Set(key, field, value)
    local entry = Find(key)
    if not entry then return end
    entry[field] = math.max(0, math.floor(value or 0))
    Changed()
end

-- Until sold on (for this character's items) or off.
function Repost:SetUntilSold(key, on)
    local entry = Find(key)
    if not entry then return end
    entry.u = on or nil
    entry.c = on and (entry.c or ns.charKey) or nil
    Changed()
end

-- Moves an item up (-1) or down (+1) within its group: Post next goes in
-- list order.
function Repost:Move(key, step)
    local list = List()
    local entry, i = Find(key)
    if not entry then return end
    local j = i + step
    while list[j] and list[j].g ~= entry.g do j = j + step end
    if not list[j] then return end
    list[i], list[j] = list[j], list[i]
    Changed()
end

-- ---------------------------------------------------------------------
-- Groups
-- ---------------------------------------------------------------------

local nextID = 0
local function NewID()
    nextID = nextID + 1
    return ("g%d.%d"):format(Util.Now(), nextID)
end

-- { { id (nil for the regulars), name, off, batch, count }, ... }: the
-- regulars first, then groups in the order they were made.
function Repost:GroupList()
    local counts = {}
    for _, entry in ipairs(List()) do
        local id = entry.g or ""
        counts[id] = (counts[id] or 0) + 1
    end
    local list = { { id = nil, name = L.REPOST_REGULARS, off = ns.db.repostRegularsOff or false, count = counts[""] or 0 } }
    for _, group in ipairs(Groups()) do
        if not group.batch or group.c == ns.charKey then
            list[#list + 1] = { id = group.id, name = group.name, off = group.off or false, batch = group.batch,
                                count = counts[group.id] or 0 }
        end
    end
    return list
end

function Repost:GroupName(id)
    if not id then return L.REPOST_REGULARS end
    local group = FindGroup(id)
    return group and group.name or L.REPOST_REGULARS
end

function Repost:AddGroup(name, batch)
    name = name and name:match("^%s*(.-)%s*$")
    if not name or name == "" then return nil end
    local group = { id = NewID(), name = name:sub(1, 40), batch = batch or nil, c = batch and ns.charKey or nil, at = Util.Now() }
    table.insert(Groups(), group)
    Changed()
    return group.id
end

-- Its items go back to the regulars, or with a batch, off the list.
function Repost:RemoveGroup(id)
    local group, i = FindGroup(id)
    if not group then return end
    local list = List()
    for j = #list, 1, -1 do
        if list[j].g == id then
            if group.batch then table.remove(list, j) else list[j].g = nil end
        end
    end
    table.remove(Groups(), i)
    Changed()
end

function Repost:ToggleGroup(id)
    if not id then
        ns.db.repostRegularsOff = not ns.db.repostRegularsOff or nil
    else
        local group = FindGroup(id)
        if not group then return end
        group.off = not group.off or nil
    end
    Changed()
end

function Repost:SetGroup(key, id)
    local entry = Find(key)
    if not entry then return end
    entry.g = id
    DropEmptyBatches()
    Changed()
end

-- A batch of { { key, link } } to sell once, as a new group named name.
-- Items already on the list are left where they are. Returns how many went on.
function Repost:AddBatch(name, items)
    local id = self:AddGroup(name, true)
    if not id then return 0 end
    local added = 0
    for _, item in ipairs(items) do
        if self:Add(item.key, item.link, { g = id, u = true, quiet = true }) then added = added + 1 end
    end
    DropEmptyBatches()
    if added > 0 then Util.Print(L.REPOST_BATCH_ADDED:format(added, name)) end
    Changed()
    return added
end

-- ---------------------------------------------------------------------
-- Until sold
-- ---------------------------------------------------------------------

local function Held(char, key)
    local inv = char and char.inventory
    if not inv then return 0 end
    return (inv.bags and inv.bags[key] or 0) + (inv.auctions and inv.auctions[key] or 0) + (inv.mail and inv.mail[key] or 0)
end

-- Called for every post (Data/Sales.lua).
function Repost:Posted(key)
    local entry = Find(key)
    if entry then entry.posted = Util.Now() end
end

-- Until-sold items their character has none of any more come off. An item
-- posted after the last look at the character's auctions is still on the
-- AH as far as we know, so it stays until the AH is seen again.
function Repost:Tidy()
    local list, gone = List(), {}
    for i = #list, 1, -1 do
        local entry = list[i]
        local char = entry.u and entry.c and ns.db.characters[entry.c]
        if char and Held(char, entry.k) == 0 and (entry.posted or 0) <= (char.auctionsAt or 0) then
            table.remove(list, i)
            gone[#gone + 1] = entry.k
        end
    end
    if #gone > 0 then
        DropEmptyBatches()
        for _, key in ipairs(gone) do Util.Print(L.REPOST_SOLD_OFF:format(Util.NamedLink(key) or key)) end
        Changed()
    end
end

-- ---------------------------------------------------------------------
-- What's on it
-- ---------------------------------------------------------------------

-- The list with what to do about each item on this character:
-- { { key, link, count, floor, max, suggestion, price, status, g, u }, ... }
--   READY     in the bags, priced at or above the floor
--   NONE      none in the bags
--   FLOOR     the price today is under the floor: kept, not posted
--   HOLD      prices crashed, worth waiting (Rules:SuggestPrice)
--   VENDOR    a vendor pays more than the AH after its cut
--   NO_PRICE  no price yet: a scan or a search fixes that
-- In group order, each group with a header row { header = true, name,
-- batch, id } when there's more than one. Groups switched off and other
-- characters' until-sold items are left out. Items on this realm's sell
-- list (Data/SellLists.lua) come last, with no floor and at most what the
-- sell list says, marked sellList.
function Repost:Items()
    local items = {}
    local char = ns.db.characters[ns.charKey]
    local bags = char and char.inventory.bags or {}

    local function Item(entry)
        local link = ns.db.links[entry.k]
        local s = ns.Rules:SuggestPrice(entry.k, link)
        local item = { key = entry.k, link = link, count = bags[entry.k] or 0, floor = entry.floor or 0,
                       max = entry.max or 0, suggestion = s, price = s.price, sellList = entry.sellList,
                       g = entry.g, u = entry.u }
        if item.count == 0 then
            item.status = "NONE"
        elseif s.action == "VENDOR" then
            item.status = "VENDOR"
        elseif not s.price then
            item.status = "NO_PRICE"
        elseif s.price < item.floor then
            item.status = "FLOOR"
        elseif s.action == "HOLD" then
            item.status = "HOLD"
        else
            item.status = "READY"
        end
        return item
    end

    local sections = {}
    for _, group in ipairs(self:GroupList()) do
        if not group.off then
            local section = { group = group, items = {} }
            for _, entry in ipairs(List()) do
                if entry.g == group.id and (not entry.u or entry.c == ns.charKey) then
                    section.items[#section.items + 1] = Item(entry)
                end
            end
            if #section.items > 0 then sections[#sections + 1] = section end
        end
    end
    local sell = { group = { name = L.REPOST_SELL_GROUP }, items = {} }
    for key, entry in pairs(ns.SellLists:Here()) do
        if not Find(key) and (bags[key] or 0) > 0 then
            sell.items[#sell.items + 1] = Item({ k = key, floor = 0, max = entry.n, sellList = true })
        end
    end
    if #sell.items > 0 then sections[#sections + 1] = sell end

    for _, section in ipairs(sections) do
        if #sections > 1 then
            items[#items + 1] = { header = true, name = section.group.name, batch = section.group.batch, id = section.group.id }
        end
        for _, item in ipairs(section.items) do items[#items + 1] = item end
    end
    return items
end

-- Items posted in the last 48 hours on this realm, in the bags now and not
-- on the list: likely regulars.
function Repost:Suggestions()
    local found, seen = {}, {}
    local char = ns.db.characters[ns.charKey]
    local bags = char and char.inventory.bags or {}
    for _, post in ipairs(ns.db.posts[ns.realmGroup] or {}) do
        local key = post.k
        if key and not seen[key] and (bags[key] or 0) > 0 and not Find(key) then
            seen[key] = true
            found[#found + 1] = key
        end
    end
    return found
end

function Repost:AddSuggestions()
    for _, key in ipairs(self:Suggestions()) do self:Add(key) end
end

-- What's in the bags worth posting (the Sell tab's Post items), not on the
-- list yet: { { key, link, count, price }, ... }, most valuable first.
function Repost:BagItems()
    local found = {}
    for _, item in ipairs(ns.Sell:List().items) do
        local s = item.suggestion
        if s.action == "POST" and s.price and not Find(item.key) then
            found[#found + 1] = { key = item.key, link = item.link, count = item.count, price = s.price }
        end
    end
    return found
end

-- ---------------------------------------------------------------------
-- Back from the AH by mail (expired or cancelled)
-- ---------------------------------------------------------------------

local function Returned(create)
    local char = ns.db.characters[ns.charKey]
    if not char then return {} end
    if create then char.returned = char.returned or {} end
    return char.returned or {}
end

-- Items back from the AH, still in the bags and not on the list:
-- { { key, link, count }, ... }. Old ones are forgotten.
function Repost:ReturnedItems()
    local returned, now = Returned(false), Util.Now()
    local char = ns.db.characters[ns.charKey]
    local bags = char and char.inventory.bags or {}
    local found = {}
    for key, info in pairs(returned) do
        if now - (info.at or 0) > RETURNED_KEEP then
            returned[key] = nil
        elseif (bags[key] or 0) > 0 and not Find(key) then
            found[#found + 1] = { key = key, link = ns.db.links[key], count = math.min(info.n, bags[key]) }
        end
    end
    table.sort(found, function(a, b) return a.key < b.key end)
    return found
end

function Repost:AddReturned()
    local items = self:ReturnedItems()
    if #items == 0 then return 0 end
    local added = self:AddBatch(L.REPOST_BATCH_RETURNED:format(date("%d %b")), items)
    local returned = Returned(false)
    for _, item in ipairs(items) do returned[item.key] = nil end
    return added
end

local function SubjectPattern(text)
    if type(text) ~= "string" then return nil end
    return "^" .. text:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", ".+") .. "$"
end
local BACK = {}
for _, subject in ipairs({ AUCTION_REMOVED_MAIL_SUBJECT or false, AUCTION_EXPIRED_MAIL_SUBJECT or false }) do
    BACK[#BACK + 1] = SubjectPattern(subject or nil)
end

-- The inbox as it was: [index] = { { key, link, n, attach }, ... } for
-- expired and cancelled AH mail.
local inbox = {}
local collected = 0

ns.Events:On("MAIL_INBOX_UPDATE", function()
    inbox = {}
    for i = 1, GetInboxNumItems() do
        local subject, _, _, _, hasItem = select(4, GetInboxHeaderInfo(i))
        local readable = type(subject) == "string" and not (issecretvalue and issecretvalue(subject))
        local back = false
        for _, p in ipairs(BACK) do
            if readable and subject:find(p) then back = true end
        end
        if back and hasItem then
            local list = {}
            for j = 1, ATTACHMENTS_MAX_RECEIVE or 16 do
                local link = GetInboxItemLink(i, j)
                local key = link and Util.ItemKeyFromLink(link)
                if key then list[#list + 1] = { key = key, link = link, n = select(4, GetInboxItem(i, j)) or 1, attach = j } end
            end
            inbox[i] = list
        end
    end
end)

local function Collect(index, attach)
    local list = inbox[index]
    if not list then return end
    local returned, now = Returned(true), Util.Now()
    for _, item in ipairs(list) do
        if not attach or item.attach == attach then
            local info = returned[item.key]
            if not info or now - (info.at or 0) > RETURNED_KEEP then info = { n = 0 } end
            info.n, info.at = info.n + item.n, now
            returned[item.key] = info
            ns.db.links[item.key] = ns.db.links[item.key] or item.link
            collected = collected + item.n
        end
    end
    if not attach then inbox[index] = nil end
end
if AutoLootMailItem then hooksecurefunc("AutoLootMailItem", function(index) Collect(index) end) end
if TakeInboxItem then hooksecurefunc("TakeInboxItem", function(index, attach) Collect(index, attach) end) end

-- One line when the mailbox closes: what came back and where to find it.
ns.Events:On("MAIL_CLOSED", function()
    if collected > 0 then Util.Print(L.REPOST_RETURNED_NOTE:format(collected)) end
    collected = 0
end)

ns.Events:On("AC_INVENTORY_CHANGED", function()
    if ns.db then Repost:Tidy() end
end)

ns:RegisterCommand("repost", function()
    if ns.RepostPanel then ns.RepostPanel:Open() end
end, L.HELP_REPOST)
