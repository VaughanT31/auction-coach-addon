-- Auction Coach - gold per hour (0.13): what a farming session makes.
--
-- Started, paused and stopped by hand (/ac gph, or the window's buttons), so
-- keys, raids and AFK time never count. Only looting and gathering count:
--   - gold looted: money that arrives while a loot window is open (mobs,
--     chests, your share of group loot); quest rewards, vendor, mail and AH
--     gold don't count.
--   - items looted or gathered: "You receive loot" lines in chat. Items
--     pushed into your bags (quest rewards, crafting) don't count.
-- Items are kept as counts and valued when shown, so the value follows the
-- latest prices: what they sell for on the AH after the 5% cut (the usual
-- price, or the lowest listing when that's lower), or the vendor price when
-- that's more or the item can't go on the AH.
--
-- A /reload or logout keeps a running session; the time while logged out
-- isn't counted.
--
--   db.session  = { elapsed, since, money, items = { [key] = count },
--                   links = { [key] = link }, zones = { [zone] = loots }, startedAt }
--   db.sessions = { { at, duration, money, value, items, zone, top = { { key, count, value } } }, ... }

local _, ns = ...
local Util, Compat = ns.Util, ns.Compat

local Session = {}
ns.Session = Session

local KEEP = 30                     -- finished sessions kept
local TOP = 8
local LOOT_GRACE = 2                -- seconds after a loot window closes that money still counts

local lootOpen, lootClosedAt = false, 0
local lastMoney

local function Secret(v)
    return issecretvalue and v ~= nil and issecretvalue(v)
end

local function Now() return Util.Now() end

function Session:Current()
    return ns.db and ns.db.session
end

function Session:Running()
    local s = self:Current()
    return s ~= nil and s.since ~= nil
end

-- Seconds counted so far.
function Session:Elapsed(s, now)
    s = s or self:Current()
    if not s then return 0 end
    return (s.elapsed or 0) + (s.since and math.max(0, (now or Now()) - s.since) or 0)
end

function Session:Start()
    if self:Current() then return self:Resume() end
    ns.db.session = { elapsed = 0, since = Now(), startedAt = Now(), money = 0, items = {}, links = {}, zones = {} }
    lastMoney = GetMoney()
    ns.Events:Fire("AC_SESSION_CHANGED")
    return true
end

function Session:Pause()
    local s = self:Current()
    if not s or not s.since then return false end
    s.elapsed = self:Elapsed(s)
    s.since = nil
    ns.Events:Fire("AC_SESSION_CHANGED")
    return true
end

function Session:Resume()
    local s = self:Current()
    if not s or s.since then return false end
    s.since = Now()
    lastMoney = GetMoney()
    ns.Events:Fire("AC_SESSION_CHANGED")
    return true
end

-- What one looted item is worth now: AH (after the cut) or vendor,
-- whichever is more. Returns copper each, and "ah", "vendor" or nil.
function Session.ValueOf(key, link)
    local itemID = Util.ItemIDFromKey(key)
    local vendor = Compat.GetVendorPrice(link or itemID) or 0
    local ah
    local bind = Compat.GetBindType(link or itemID)
    if bind ~= 1 and bind ~= 4 then
        local price = ns.Prices:Get(key)
        if price and price.value then
            local each = price.value
            if price.min and price.min > 0 and price.min < each then each = price.min end
            ah = math.floor(Util.AfterCut(each))
        end
    end
    if ah and ah >= vendor then return ah, "ah" end
    if vendor > 0 then return vendor, "vendor" end
    return 0, nil
end

-- A session's totals: { seconds, money, value, items, perHour, top, zone }.
function Session:Totals(s, now)
    s = s or self:Current()
    if not s then return nil end
    local seconds = self:Elapsed(s, now)
    local list, value, count = {}, 0, 0
    for key, n in pairs(s.items) do
        local each = Session.ValueOf(key, s.links[key])
        value = value + each * n
        count = count + n
        list[#list + 1] = { key = key, count = n, value = each * n, link = s.links[key] }
    end
    table.sort(list, function(a, b)
        if a.value ~= b.value then return a.value > b.value end
        return a.key < b.key
    end)
    for i = #list, TOP + 1, -1 do list[i] = nil end
    local zone, most = nil, 0
    for name, n in pairs(s.zones or {}) do
        if n > most then zone, most = name, n end
    end
    local total = s.money + value
    return {
        seconds = seconds, money = s.money, value = value, total = total, items = count, top = list, zone = zone,
        perHour = seconds >= 60 and math.floor(total / seconds * 3600) or nil,
    }
end

function Session:Stop()
    local s = self:Current()
    if not s then return nil end
    local t = self:Totals(s)
    ns.db.session = nil
    if t.seconds >= 60 and t.total > 0 then
        local top = {}
        for i = 1, math.min(3, #t.top) do top[i] = { key = t.top[i].key, count = t.top[i].count, value = t.top[i].value } end
        table.insert(ns.db.sessions, 1, {
            at = s.startedAt, duration = t.seconds, money = t.money, value = t.value, items = t.items, zone = t.zone, top = top,
        })
        for i = #ns.db.sessions, KEEP + 1, -1 do ns.db.sessions[i] = nil end
    end
    ns.Events:Fire("AC_SESSION_CHANGED")
    return t
end

function Session:History()
    return ns.db and ns.db.sessions or {}
end

-- Recording ------------------------------------------------------------------

local function Pattern(format)
    if type(format) ~= "string" then return nil end
    local p = format:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    p = p:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
    return "^" .. p .. "$"
end

-- Multiple first: "You receive loot: [Ore]x5." also matches the single one.
local LOOT_PATTERNS = {}
for _, name in ipairs({ "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_SELF" }) do
    local p = Pattern(_G[name])
    if p then LOOT_PATTERNS[#LOOT_PATTERNS + 1] = p end
end
Session.LOOT_PATTERNS = LOOT_PATTERNS

-- The item link and count from a loot chat line, or nil.
function Session.ParseLoot(text)
    if type(text) ~= "string" or Secret(text) then return nil end
    for _, p in ipairs(LOOT_PATTERNS) do
        local link, n = text:match(p)
        if link then return link, tonumber(n) or 1 end
    end
    return nil
end

function Session:AddItem(link, count)
    local s = self:Current()
    if not s or not s.since then return false end
    local key = Util.ItemKeyFromLink(link)
    if not key then return false end
    s.items[key] = (s.items[key] or 0) + count
    s.links[key] = s.links[key] or link
    local zone = GetRealZoneText and GetRealZoneText()
    if zone and zone ~= "" and not Secret(zone) then s.zones[zone] = (s.zones[zone] or 0) + 1 end
    ns.Events:Fire("AC_SESSION_CHANGED")
    return true
end

function Session:AddMoney(copper)
    local s = self:Current()
    if not s or not s.since or not copper or copper <= 0 then return false end
    s.money = s.money + copper
    ns.Events:Fire("AC_SESSION_CHANGED")
    return true
end

function Session.Looting()
    return lootOpen or (GetTime() - lootClosedAt) <= LOOT_GRACE
end

ns.Events:On("LOOT_READY", function() lootOpen = true end)
ns.Events:On("LOOT_OPENED", function() lootOpen = true end)
ns.Events:On("LOOT_CLOSED", function()
    lootOpen = false
    lootClosedAt = GetTime()
end)

ns.Events:On("PLAYER_MONEY", function()
    local money = GetMoney()
    if lastMoney and money > lastMoney and Session.Looting() then Session:AddMoney(money - lastMoney) end
    lastMoney = money
end)

ns.Events:On("CHAT_MSG_LOOT", function(_, text, _, _, _, _, _, _, _, _, _, _, guid)
    if not Session:Running() then return end
    if guid and not Secret(guid) and guid ~= UnitGUID("player") then return end
    local link, count = Session.ParseLoot(text)
    if link then Session:AddItem(link, count) end
end)

-- A /reload or logout keeps it running, but the time away isn't counted:
-- the moment you left is saved and skipped at the next login. Entering a
-- dungeon or raid with it running gets a reminder.
ns.Events:On("PLAYER_LOGOUT", function()
    local s = Session:Current()
    if s and s.since then s.leftAt = Now() end
end)
ns.Events:On("PLAYER_LOGIN", function()
    local s = Session:Current()
    if s and s.since and s.leftAt then
        s.elapsed = (s.elapsed or 0) + math.max(0, s.leftAt - s.since)
        s.since = Now()
    end
    if s then s.leftAt = nil end
end)
ns.Events:On("PLAYER_ENTERING_WORLD", function()
    lastMoney = GetMoney()
    local _, kind = IsInInstance()
    if Session:Running() and (kind == "party" or kind == "raid") then
        Util.Print(ns.L.GPH_INSTANCE_REMINDER)
    end
end)

ns.Events:On("AC_DB_READY", function()
    ns.db.sessions = ns.db.sessions or {}
end)
