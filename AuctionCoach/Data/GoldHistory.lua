-- Auction Coach - gold tracking: your gold and AH sales over time.
--
-- Two records, both per calendar day (the player's local date):
--   - Gold: the latest total of every character's gold plus the warband
--     bank, taken whenever any of it changes. Characters keep the gold
--     they had when last seen, so the total covers the whole account.
--   - AH sales and purchases, from the Auction House's own mails
--     (GetInboxInvoiceInfo), counted when the player collects them: the
--     gold a sale paid, and what each purchase cost, with item counts.
--     Collecting is the one moment each mail is seen exactly once: the
--     inbox only lists 50 mails, and identical commodity sales can't be
--     told apart by reading it.
--
--   db.goldDays[YYYY-MM-DD] = { total = copper, warband = copper,
--       chars = { [charKey] = copper }, sales = copper, sold = items,
--       bought = copper, boughtItems = items }

local _, ns = ...
local Util = ns.Util

local GoldHistory = {}
ns.GoldHistory = GoldHistory

local KEEP_DAYS = 120

function GoldHistory.DayKey(t)
    return date("%Y-%m-%d", t or Util.Now())
end

local function Days()
    ns.db.goldDays = ns.db.goldDays or {}
    return ns.db.goldDays
end

local function Day(key)
    local days = Days()
    local day = days[key]
    if not day then
        day = { total = 0, warband = 0, chars = {}, sales = 0, sold = 0, bought = 0, boughtItems = 0 }
        days[key] = day
    end
    return day
end

-- Account total right now, from every character's last known gold.
function GoldHistory:CurrentTotal()
    local total, chars = 0, {}
    for key, char in pairs(ns.db.characters) do
        local gold = char.gold or 0
        total = total + gold
        if gold > 0 then chars[key] = gold end
    end
    local warband = ns.db.warbankGold or 0
    return total + warband, chars, warband
end

function GoldHistory:Snapshot()
    if not ns.db then return end
    local total, chars, warband = self:CurrentTotal()
    if total <= 0 then return end
    local day = Day(GoldHistory.DayKey())
    day.total, day.chars, day.warband = total, chars, warband
end

local function Prune()
    local cutoff = GoldHistory.DayKey(Util.Now() - KEEP_DAYS * 86400)
    for key in pairs(Days()) do
        if key < cutoff then Days()[key] = nil end
    end
    -- 0.7.0 test builds deduplicated mails by ID; no longer needed.
    ns.db.invoicesSeen = nil
end

-- ---------------------------------------------------------------------
-- AH mails
-- ---------------------------------------------------------------------

-- One AH mail as a sale or purchase, or nil. Pure, so it can be tested
-- outside the game. money is the gold attached to the mail: for a sale
-- that is exactly what the player receives (price plus deposit back,
-- minus the AH cut). A purchase mail is about what was paid (bid).
function GoldHistory.ReadInvoice(invoiceType, itemName, bid, count, money)
    if invoiceType == "seller" then
        if not money or money <= 0 then return nil end
        return { kind = "sale", amount = money, count = math.max(1, count or 1), item = itemName }
    elseif invoiceType == "buyer" then
        if not bid or bid <= 0 then return nil end
        return { kind = "buy", amount = bid, count = math.max(1, count or 1), item = itemName }
    end
    return nil
end

-- Adds a collected sale or purchase to today.
function GoldHistory:Record(invoice)
    local day = Day(GoldHistory.DayKey())
    if invoice.kind == "sale" then
        day.sales = day.sales + invoice.amount
        day.sold = day.sold + invoice.count
    else
        day.bought = day.bought + invoice.amount
        day.boughtItems = day.boughtItems + invoice.count
    end
    ns.Events:Fire("AC_GOLD_HISTORY_CHANGED")
end

-- The inbox as it was before the player touched it: [index] = invoice.
-- Rebuilt on every MAIL_INBOX_UPDATE, so a collect hook reads the mail as
-- it was even if the game has already started removing it.
local inbox = {}

function GoldHistory:ReadInbox()
    inbox = {}
    if not GetInboxInvoiceInfo then return end
    for i = 1, GetInboxNumItems() do
        local invoiceType, itemName, _, bid, _, _, _, _, _, _, count = GetInboxInvoiceInfo(i)
        if invoiceType == "seller" or invoiceType == "buyer" then
            local money = select(5, GetInboxHeaderInfo(i))
            inbox[i] = GoldHistory.ReadInvoice(invoiceType, itemName, bid, count, money)
        end
    end
end

-- A mail at index is being collected: count it, once.
function GoldHistory:Collect(index)
    local invoice = ns.db and inbox[index]
    if not invoice or invoice.counted then return end
    invoice.counted = true
    self:Record(invoice)
end

-- ---------------------------------------------------------------------
-- Reading it back
-- ---------------------------------------------------------------------

-- The last n days, newest first: { { key, total, change, sales, sold,
-- bought, boughtItems }, ... }. Days with no snapshot carry the last known
-- total forward, so a quiet day shows no change rather than a gap.
function GoldHistory:Recent(n)
    local days = Days()
    local list = {}
    local now = Util.Now()
    for i = n - 1, 0, -1 do
        local key = GoldHistory.DayKey(now - i * 86400)
        list[#list + 1] = { key = key, day = days[key] }
    end
    -- Oldest first to carry totals forward, then reverse.
    local last
    for _, entry in ipairs(list) do
        local day = entry.day
        entry.total = (day and day.total and day.total > 0) and day.total or last
        entry.change = (entry.total and last) and (entry.total - last) or nil
        if entry.total then last = entry.total end
        entry.sales = day and day.sales or 0
        entry.sold = day and day.sold or 0
        entry.bought = day and day.bought or 0
        entry.boughtItems = day and day.boughtItems or 0
    end
    local reversed = {}
    for i = #list, 1, -1 do reversed[#reversed + 1] = list[i] end
    return reversed
end

-- Gold change and AH sales over the last n days (today included):
-- change is nil when there is no total from before that period.
function GoldHistory:Summary(n)
    local recent = self:Recent(n + 1)
    local now, before = recent[1].total, recent[#recent].total
    local sales, bought = 0, 0
    for i = 1, n do
        sales = sales + recent[i].sales
        bought = bought + recent[i].bought
    end
    return {
        change = (now and before) and (now - before) or nil,
        sales = sales, bought = bought,
    }
end

-- ---------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------

ns.Events:On("AC_LOGIN", function()
    Prune()
    GoldHistory:Snapshot()
end)

ns.Events:On("AC_INVENTORY_CHANGED", function()
    Util.Debounce("goldSnapshot", 2, function() GoldHistory:Snapshot() end)
end)

ns.Events:On("MAIL_INBOX_UPDATE", function()
    GoldHistory:ReadInbox()
end)

-- Every way to collect a mail ends in one of these, whether from the
-- mail frame, its Open All button or another mail addon. A sale's gold
-- comes with TakeInboxMoney or AutoLootMailItem; a purchase's items with
-- TakeInboxItem or AutoLootMailItem.
for _, name in ipairs({ "TakeInboxMoney", "AutoLootMailItem", "TakeInboxItem" }) do
    if _G[name] then
        hooksecurefunc(name, function(index) GoldHistory:Collect(index) end)
    end
end
