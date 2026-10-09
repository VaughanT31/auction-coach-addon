-- Auction Coach - gold tracking: your gold and AH sales over time.
--
-- Two records, both per calendar day (the player's local date):
--   - Gold: the latest total of every character's gold plus the warband
--     bank, taken whenever any of it changes. Characters keep the gold
--     they had when last seen, so the total covers the whole account.
--   - AH sales and purchases, read from the Auction House's own mails
--     (GetInboxInvoiceInfo): what a sale paid after the cut and how many
--     items, and what each purchase cost. Mails are counted once, the
--     first time any character sees them in a mailbox, on the day they
--     were sent.
--
--   db.goldDays[YYYY-MM-DD] = { total = copper, warband = copper,
--       chars = { [charKey] = copper }, sales = copper, sold = items,
--       bought = copper, boughtItems = items }
--   db.invoicesSeen[id] = unix time sent (pruned after KEEP_INVOICE_IDS)

local _, ns = ...
local Util = ns.Util

local GoldHistory = {}
ns.GoldHistory = GoldHistory

local KEEP_DAYS = 120
-- AH mails last 30 days, so an ID older than that can't be seen again.
local KEEP_INVOICE_IDS = 31 * 86400
-- Days a mail with this many days left was sent: AH mails last 30 days.
local MAIL_DAYS = 30

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
    local seen = ns.db.invoicesSeen or {}
    local now = Util.Now()
    for id, sent in pairs(seen) do
        if now - sent > KEEP_INVOICE_IDS then seen[id] = nil end
    end
end

-- ---------------------------------------------------------------------
-- AH mails
-- ---------------------------------------------------------------------

-- One AH mail as a sale or purchase, or nil. Pure, so it can be tested
-- outside the game: invoiceType, itemName, amount (copper the mail is
-- about), count, daysLeft, now.
-- The ID combines what the mail says with the minute it was sent (from
-- its days left), so the same mail always gets the same ID while two
-- sales of the same item at the same price normally don't.
function GoldHistory.ReadInvoice(invoiceType, itemName, amount, count, daysLeft, now)
    if invoiceType ~= "seller" and invoiceType ~= "buyer" then return nil end
    if not itemName or not amount or amount <= 0 or not daysLeft then return nil end
    local sent = now - math.max(0, MAIL_DAYS - daysLeft) * 86400
    local minute = math.floor(sent / 60)
    return {
        kind = invoiceType == "seller" and "sale" or "buy",
        id = table.concat({ invoiceType, itemName, amount, count or 1, minute }, "|"),
        amount = amount, count = math.max(1, count or 1), sent = sent,
    }
end

-- Adds a read invoice to its day, once. Returns true when it was new.
function GoldHistory:Record(invoice)
    local seen = ns.db.invoicesSeen or {}
    ns.db.invoicesSeen = seen
    -- A minute either side: days left is rounded, so the computed minute
    -- can move by one between mailbox visits.
    local base, minute = invoice.id:match("^(.*)|(%-?%d+)$")
    minute = tonumber(minute)
    for m = minute - 1, minute + 1 do
        if seen[base .. "|" .. m] then return false end
    end
    seen[invoice.id] = invoice.sent
    local day = Day(GoldHistory.DayKey(invoice.sent))
    if invoice.kind == "sale" then
        day.sales = day.sales + invoice.amount
        day.sold = day.sold + invoice.count
    else
        day.bought = day.bought + invoice.amount
        day.boughtItems = day.boughtItems + invoice.count
    end
    return true
end

function GoldHistory:ScanInbox()
    if not ns.db or not GetInboxInvoiceInfo then return end
    local now = Util.Now()
    local changed = false
    for i = 1, GetInboxNumItems() do
        local invoiceType, itemName, _, bid, _, deposit, consignment, _, _, _, count = GetInboxInvoiceInfo(i)
        if invoiceType == "seller" or invoiceType == "buyer" then
            local daysLeft = select(7, GetInboxHeaderInfo(i))
            -- A sale pays the price plus the deposit back, minus the AH cut;
            -- a purchase mail is about what was paid.
            local amount = invoiceType == "seller"
                and (bid or 0) + (deposit or 0) - (consignment or 0)
                or (bid or 0)
            local invoice = GoldHistory.ReadInvoice(invoiceType, itemName, amount, count, daysLeft, now)
            if invoice and self:Record(invoice) then changed = true end
        end
    end
    if changed then ns.Events:Fire("AC_GOLD_HISTORY_CHANGED") end
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
    Util.Debounce("invoiceScan", 0.5, function() GoldHistory:ScanInbox() end)
end)
