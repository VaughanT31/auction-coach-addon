-- Auction Coach - accounting (0.26): where your gold comes from and goes.
--
-- Every change in a character's gold (PLAYER_MONEY) is put in a category
-- from what caused it, in this order:
--   1. a known action just before it: collecting a mail (an AH sale, an
--      outbid refund, gold from one of your own characters or anyone
--      else), sending one, repairing, a flight, posting or cancelling an
--      auction, the guild bank or the warband bank
--   2. what's open: a trade, the AH, a vendor, a trainer, the barber, the
--      transmogrifier, crafting orders, a quest just handed in, a loot window
--   3. anything else is "other"
-- An action only counts when the gold moves the way it should (a repair
-- can't pay you) and within a few seconds of it, so a stale one is ignored.
--
-- Gold moved between your own characters (the warband bank, mail between
-- them) is a transfer: kept apart, so it never shows as income or spending.
--
--   db.ledger[charKey] = { since = first seen, days = { [YYYY-MM-DD] = { [cat] = { in, out } } },
--       week = { start = weekly reset, c = { [cat] = { in, out } } }, all = { [cat] = { in, out } } }
-- A running gold per hour session gets the same in db.session.ledger.

local _, ns = ...
local Util = ns.Util

local Ledger = {}
ns.Ledger = Ledger

local KEEP_DAYS = 400
-- How long after an action (or a window closing) its gold still counts.
local ACTION_GRACE = 4
local CLOSE_GRACE = 3

-- Categories in display order. sign: +1 income only, -1 spending only, nil both.
Ledger.CATEGORIES = {
    "ahSales", "ahBuy", "ahFees", "vendorSales", "vendorBuy", "repairs", "loot", "quests", "travel",
    "trainers", "transmog", "barber", "craftingOrders", "mail", "trade", "guildBank", "other",
}
Ledger.TRANSFER = "transfer"

-- ---------------------------------------------------------------------
-- Storage
-- ---------------------------------------------------------------------

-- Start of the current week (the last weekly reset), to the nearest 10
-- minutes so it stays the same all week.
function Ledger.WeekStart(now)
    now = now or Util.Now()
    local untilReset = C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset and C_DateAndTime.GetSecondsUntilWeeklyReset()
    if not untilReset then return nil end
    local start = now + untilReset - 7 * 86400
    return math.floor(start / 600 + 0.5) * 600
end

local function GoldDay(now)
    return date("%Y-%m-%d", now)
end

local function Book(charKey)
    ns.db.ledger = ns.db.ledger or {}
    local book = ns.db.ledger[charKey]
    if not book then
        book = { since = Util.Now(), days = {}, all = {} }
        ns.db.ledger[charKey] = book
    end
    return book
end

local function Add(bucket, cat, delta)
    local entry = bucket[cat]
    if not entry then
        entry = { 0, 0 }
        bucket[cat] = entry
    end
    if delta > 0 then entry[1] = entry[1] + delta else entry[2] = entry[2] - delta end
end

-- An outbid refund gives back what a bid took: it lowers spending instead
-- of counting as income.
local function Refund(bucket, cat, amount)
    local entry = bucket[cat]
    if entry and entry[2] >= amount then
        entry[2] = entry[2] - amount
        return true
    end
    return false
end

local function Buckets(book, now)
    local day = GoldDay(now)
    book.days[day] = book.days[day] or {}
    local start = Ledger.WeekStart(now)
    if start and (not book.week or book.week.start ~= start) then book.week = { start = start, c = {} } end
    local list = { book.days[day], book.all }
    if book.week then list[#list + 1] = book.week.c end
    local s = ns.Session and ns.Session:Running() and ns.db.session
    if s then
        s.ledger = s.ledger or {}
        list[#list + 1] = s.ledger
    end
    return list
end

function Ledger:Record(cat, delta, refund)
    if not ns.db or not ns.charKey or delta == 0 then return end
    local now = Util.Now()
    for _, bucket in ipairs(Buckets(Book(ns.charKey), now)) do
        if not (refund and Refund(bucket, cat, delta)) then Add(bucket, cat, delta) end
    end
    ns.Events:Fire("AC_LEDGER_CHANGED")
end

local function Prune()
    local cutoff = GoldDay(Util.Now() - KEEP_DAYS * 86400)
    for _, book in pairs(ns.db.ledger or {}) do
        for key in pairs(book.days) do
            if key < cutoff then book.days[key] = nil end
        end
    end
end

-- ---------------------------------------------------------------------
-- Working out the category
-- ---------------------------------------------------------------------

-- The last action: { cat, sign, at, refund }. Used once.
local action
local function Expect(cat, sign, refund)
    action = { cat = cat, sign = sign, at = GetTime(), refund = refund }
end

-- Open windows: [name] = true while open, or the GetTime() it closed.
local open = {}
local function IsOpen(name)
    local state = open[name]
    return state == true or (state and GetTime() - state <= CLOSE_GRACE) or false
end

local function Watch(name, showEvents, hideEvents)
    for _, event in ipairs(showEvents) do ns.Events:On(event, function() open[name] = true end) end
    for _, event in ipairs(hideEvents) do
        ns.Events:On(event, function() if open[name] == true then open[name] = GetTime() end end)
    end
end

Watch("ah", { "AUCTION_HOUSE_SHOW" }, { "AUCTION_HOUSE_CLOSED" })
Watch("merchant", { "MERCHANT_SHOW" }, { "MERCHANT_CLOSED" })
Watch("trade", { "TRADE_SHOW" }, { "TRADE_CLOSED" })
Watch("trainer", { "TRAINER_SHOW" }, { "TRAINER_CLOSED" })
Watch("barber", { "BARBER_SHOP_OPEN" }, { "BARBER_SHOP_CLOSE" })
Watch("transmog", { "TRANSMOGRIFY_OPEN" }, { "TRANSMOGRIFY_CLOSE" })
Watch("taxi", { "TAXIMAP_OPENED" }, { "TAXIMAP_CLOSED" })
Watch("orders", { "CRAFTINGORDERS_SHOW_CUSTOMER", "CRAFTINGORDERS_SHOW_CRAFTER" },
    { "CRAFTINGORDERS_HIDE_CUSTOMER", "CRAFTINGORDERS_HIDE_CRAFTER" })
Watch("loot", { "LOOT_READY", "LOOT_OPENED" }, { "LOOT_CLOSED" })

-- Newer clients open most of these through the interaction manager.
local INTERACTIONS = {
    Merchant = "merchant", TradePartner = "trade", Trainer = "trainer", Auctioneer = "ah",
    Transmogrifier = "transmog", TaxiNode = "taxi", BlackMarketAuctioneer = "ah",
    ProfessionsCustomerOrder = "orders", ProfessionsCraftingOrder = "orders",
}
local interactionNames = {}
if Enum.PlayerInteractionType then
    for typeName, name in pairs(INTERACTIONS) do
        local id = Enum.PlayerInteractionType[typeName]
        if id then interactionNames[id] = name end
    end
end
ns.Events:On("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(_, id)
    if interactionNames[id] then open[interactionNames[id]] = true end
end)
ns.Events:On("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(_, id)
    local name = interactionNames[id]
    if name and open[name] == true then open[name] = GetTime() end
end)

local questAt, lootMoneyAt = 0, 0
ns.Events:On("QUEST_TURNED_IN", function() questAt = GetTime() end)
ns.Events:On("CHAT_MSG_MONEY", function() lootMoneyAt = GetTime() end)

-- Pure, so it can be tested outside the game: the category for a change of
-- delta copper, given the last action and what's open (IsOpen(name)).
-- Returns cat, refund.
function Ledger.Categorise(delta, last, isOpen, sinceQuest, sinceLootMoney, repairing)
    if last and (not last.sign or last.sign * delta > 0) then return last.cat, last.refund end
    if isOpen("trade") then return "trade" end
    if isOpen("ah") then return delta < 0 and "ahBuy" or "other" end
    if isOpen("merchant") then
        if delta > 0 then return "vendorSales" end
        return repairing and "repairs" or "vendorBuy"
    end
    if delta < 0 then
        if isOpen("trainer") then return "trainers" end
        if isOpen("barber") then return "barber" end
        if isOpen("transmog") then return "transmog" end
        if isOpen("taxi") then return "travel" end
    end
    if isOpen("orders") then return "craftingOrders" end
    if delta > 0 then
        if sinceQuest <= ACTION_GRACE then return "quests" end
        if isOpen("loot") or sinceLootMoney <= ACTION_GRACE then return "loot" end
    end
    return "other"
end

local lastMoney

ns.Events:On("PLAYER_MONEY", function()
    local money = GetMoney()
    if not lastMoney then
        lastMoney = money
        return
    end
    local delta = money - lastMoney
    lastMoney = money
    if delta == 0 then return end
    local now = GetTime()
    local last = action and now - action.at <= ACTION_GRACE and action or nil
    local cat, refund = Ledger.Categorise(delta, last, IsOpen, now - questAt, now - lootMoneyAt,
        InRepairMode and InRepairMode())
    if last and cat == last.cat then action = nil end
    Ledger:Record(cat, delta, refund)
end)

-- ---------------------------------------------------------------------
-- Actions
-- ---------------------------------------------------------------------

-- "Name" or "Name-Realm" from a mail or a send box: one of yours?
function Ledger.IsOwnCharacter(name)
    if type(name) ~= "string" or (issecretvalue and issecretvalue(name)) or name == "" then return false end
    if not name:find("-", 1, true) then name = name .. "-" .. GetNormalizedRealmName() end
    name = name:gsub("%s", "")
    for charKey in pairs(ns.db.characters) do
        if charKey:gsub("%s", "") == name then return true end
    end
    return false
end

local function SubjectPattern(text)
    if type(text) ~= "string" then return nil end
    return "^" .. text:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", ".+") .. "$"
end
local OUTBID = SubjectPattern(AUCTION_OUTBID_MAIL_SUBJECT)

-- The inbox as it was before the player touched it: [index] = { cat, refund }.
local inbox = {}

local function ReadMail(index)
    local _, _, sender, subject, money, cod = GetInboxHeaderInfo(index)
    if (cod or 0) > 0 then return { cat = "mail", sign = -1 } end
    if (money or 0) <= 0 then return nil end
    local invoiceType = GetInboxInvoiceInfo and GetInboxInvoiceInfo(index)
    if invoiceType == "seller" then return { cat = "ahSales", sign = 1 } end
    if OUTBID and type(subject) == "string" and not (issecretvalue and issecretvalue(subject)) and subject:find(OUTBID) then
        return { cat = "ahBuy", sign = 1, refund = true }
    end
    if Ledger.IsOwnCharacter(sender) then return { cat = Ledger.TRANSFER, sign = 1 } end
    return { cat = "mail", sign = 1 }
end

ns.Events:On("MAIL_INBOX_UPDATE", function()
    inbox = {}
    for i = 1, GetInboxNumItems() do inbox[i] = ReadMail(i) end
end)

local function Collect(index)
    local mail = inbox[index]
    if mail then Expect(mail.cat, mail.sign, mail.refund) end
end
for _, name in ipairs({ "TakeInboxMoney", "AutoLootMailItem", "TakeInboxItem" }) do
    if _G[name] then hooksecurefunc(name, Collect) end
end

-- Sending gold or paying postage: gold sent to your own character is a transfer.
if SendMail then
    hooksecurefunc("SendMail", function(recipient)
        local sending = GetSendMailMoney and GetSendMailMoney() or 0
        Expect(sending > 0 and Ledger.IsOwnCharacter(recipient) and Ledger.TRANSFER or "mail", -1)
    end)
end

local function Hook(owner, name, cat, sign)
    if owner and owner[name] then hooksecurefunc(owner, name, function() Expect(cat, sign) end) end
end

Hook(_G, "RepairAllItems", "repairs", -1)
Hook(_G, "TakeTaxiNode", "travel", -1)
Hook(_G, "BuyTrainerService", "trainers", -1)
Hook(_G, "DepositGuildBankMoney", "guildBank", -1)
Hook(_G, "WithdrawGuildBankMoney", "guildBank", 1)
Hook(C_Bank, "DepositMoney", Ledger.TRANSFER, -1)
Hook(C_Bank, "WithdrawMoney", Ledger.TRANSFER, 1)
Hook(C_AuctionHouse, "PostItem", "ahFees", -1)
Hook(C_AuctionHouse, "PostCommodity", "ahFees", -1)
Hook(C_AuctionHouse, "CancelAuction", "ahFees", -1)
Hook(C_AuctionHouse, "PlaceBid", "ahBuy", -1)
Hook(C_AuctionHouse, "ConfirmCommoditiesPurchase", "ahBuy", -1)
Hook(C_CraftingOrders, "PlaceNewOrder", "craftingOrders", -1)
-- A repair paid by the guild bank costs you nothing: no gold change follows.

-- ---------------------------------------------------------------------
-- Reading it back
-- ---------------------------------------------------------------------

-- Characters in a scope: "char" (this one), "realm" (this realm group) or "account".
local function CharsIn(scope)
    local list = {}
    for charKey in pairs(ns.db.ledger or {}) do
        local char = ns.db.characters[charKey]
        if scope == "account" or charKey == ns.charKey
            or (scope == "realm" and char and char.realmGroup == ns.realmGroup) then
            list[#list + 1] = charKey
        end
    end
    return list
end

-- One character's buckets for a period: "today", "week", "month" or "all".
local function PeriodBuckets(book, period, now)
    if period == "all" then return { book.all } end
    if period == "week" then
        local start = Ledger.WeekStart(now)
        return (book.week and book.week.start == start) and { book.week.c } or {}
    end
    if period == "today" then return { book.days[GoldDay(now)] } end
    local month, list = date("%Y-%m", now), {}
    for key, bucket in pairs(book.days) do
        if key:sub(1, 7) == month then list[#list + 1] = bucket end
    end
    return list
end

-- Totals for a period and scope:
--   { income, spending, net, transferIn, transferOut, since,
--     cats = { [cat] = { in, out, chars = { [charKey] = { in, out } } } },
--     topIncome = cat, topCost = cat }
-- Transfers are left out of income, spending and net.
function Ledger:Totals(period, scope, now)
    now = now or Util.Now()
    local result = { income = 0, spending = 0, transferIn = 0, transferOut = 0, cats = {} }
    for _, charKey in ipairs(CharsIn(scope)) do
        local book = ns.db.ledger[charKey]
        if not result.since or book.since < result.since then result.since = book.since end
        for _, bucket in ipairs(PeriodBuckets(book, period, now)) do
            for cat, entry in pairs(bucket or {}) do
                local total = result.cats[cat] or { 0, 0, chars = {} }
                result.cats[cat] = total
                total[1], total[2] = total[1] + entry[1], total[2] + entry[2]
                local per = total.chars[charKey] or { 0, 0 }
                total.chars[charKey] = per
                per[1], per[2] = per[1] + entry[1], per[2] + entry[2]
            end
        end
    end
    local topIn, topOut = 0, 0
    for cat, total in pairs(result.cats) do
        if cat == Ledger.TRANSFER then
            result.transferIn, result.transferOut = total[1], total[2]
        else
            result.income = result.income + total[1]
            result.spending = result.spending + total[2]
            if total[1] > topIn then topIn, result.topIncome = total[1], cat end
            if total[2] > topOut then topOut, result.topCost = total[2], cat end
        end
    end
    result.net = result.income - result.spending
    return result
end

-- Each day's account totals per category, for /ac export (the website's
-- charts): { [YYYY-MM-DD] = { [cat] = { in, out } } }, nil when empty.
function Ledger:ExportDays(days)
    local cutoff = GoldDay(Util.Now() - (days or 120) * 86400)
    local result
    for _, book in pairs(ns.db.ledger or {}) do
        for key, bucket in pairs(book.days) do
            if key >= cutoff then
                for cat, entry in pairs(bucket) do
                    if entry[1] > 0 or entry[2] > 0 then
                        result = result or {}
                        result[key] = result[key] or {}
                        local total = result[key][cat] or { 0, 0 }
                        result[key][cat] = total
                        total[1], total[2] = total[1] + entry[1], total[2] + entry[2]
                    end
                end
            end
        end
    end
    return result
end

ns.Events:On("AC_LOGIN", function()
    lastMoney = GetMoney()
    Book(ns.charKey)
    Prune()
end)
