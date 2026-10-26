-- Auction Coach - the player's own posts and sales.
--
-- Every post is remembered for 48 hours (the longest an auction runs) with
-- its price and quantity. When WoW says "A buyer has been found for your
-- auction of X", the matching post is found and Auction Coach adds what
-- the sale made after the AH cut. The message only names the item, so for
-- a stack (which can sell in parts) the line gives the price each and says
-- the exact amount comes with the mail: the "Auction successful" mail's
-- invoice names how many sold, and the mailbox summary (ScanMail) reports
-- each of those once.
--
--   db.posts[group] = { { k = item key, v = unit price, q = quantity,
--                         p = posted, s = first sale, n = sale messages,
--                         name = item name when posted,
--                         id = auction ID, when Blizzard reported it }, ... }
--
-- Gold on the way: each sale message also starts an hour's wait for the
-- "Auction successful" mail, so My Stuff can show the gold still coming
-- after Blizzard's own "Sold" rows are gone. Sales made while logged out
-- send no message, so they aren't counted.
--   db.mailDue = { { c = character, t = sale time, name = item name,
--                    g = gold after the cut (a stack sale: at least one
--                    item's worth), stack = true for a stack }, ... }

local _, ns = ...
local L, Util = ns.L, ns.Util

local Sales = {}
ns.Sales = Sales

local KEEP = 48 * 3600
local MAX_POSTS = 200

-- In restricted content (instances, combat) the game can hand addons secret
-- strings that error when read; those are skipped.
local function Readable(value)
    return type(value) == "string" and not (issecretvalue and issecretvalue(value))
end

local function Posts(groupKey, create)
    local posts = ns.db.posts[groupKey]
    if not posts and create then
        posts = {}
        ns.db.posts[groupKey] = posts
    end
    return posts
end

-- Called for every post. unitPrice is per item. name comes from the
-- posted item's link, so matching a sale never waits on the item cache.
function Sales:Posted(key, unitPrice, quantity, now, name)
    if not key or not unitPrice or unitPrice <= 0 then return end
    now = now or Util.Now()
    quantity = math.max(1, quantity or 1)
    local posts = Posts(ns.realmGroup, true)
    posts[#posts + 1] = { k = key, v = unitPrice, q = quantity, p = now, name = Sales.PlainName(name) }
    while #posts > MAX_POSTS or (posts[1] and now - posts[1].p > KEEP) do
        table.remove(posts, 1)
    end
    ns.Undercuts:Posted(key, unitPrice, quantity, now)
    ns.SellLists:Posted(key, quantity)
    ns.Repost:Posted(key)
end

-- Item name without colour codes, links or crafting quality icons.
function Sales.PlainName(text)
    if not text then return nil end
    text = text:match("%[(.-)%]") or text
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|A.-|a", ""):gsub("|T.-|t", "")
    return (text:match("^%s*(.-)%s*$"))
end

-- The post a sale message is about: same item name, not fully sold yet.
-- Buyers take the cheapest listing first, so the lowest price wins, then
-- the oldest post.
function Sales:FindPost(itemName, now)
    local posts = Posts(ns.realmGroup, false)
    itemName = Sales.PlainName(itemName)
    if not posts or not itemName or itemName == "" then return nil end
    local best
    for _, post in ipairs(posts) do
        if now - post.p <= KEEP and (post.n or 0) < post.q then
            local itemID = Util.ItemIDFromKey(post.k)
            local name = post.name or (itemID and Sales.PlainName(ns.Compat.GetItemInfo(itemID)))
            if name == itemName then
                if not best or post.v < best.v or (post.v == best.v and post.p < best.p) then
                    best = post
                end
            end
        end
    end
    return best
end

function Sales:Message(post)
    local itemID = Util.ItemIDFromKey(post.k)
    local link = Util.NamedLink(post.k) or post.name or (itemID and ns.Compat.GetItemInfo(itemID)) or post.k
    local money = Util.FormatMoneyIcons
    if post.q == 1 then
        return L.SALE_ONE:format(link, money(Util.AfterCut(post.v)))
    end
    return L.SALE_STACK:format(link, money(post.v))
end

-- The post with this auction ID, if Blizzard reported it when posting.
function Sales:FindPostByID(auctionID)
    local posts = auctionID and Posts(ns.realmGroup, false)
    if not posts then return nil end
    for _, post in ipairs(posts) do
        if post.id == auctionID then return post end
    end
    return nil
end

-- The same sale can arrive as an AH notification and as a chat message.
local lastSale = { name = nil, t = 0 }

function Sales:OnSold(itemName, now, auctionID)
    local name = Sales.PlainName(itemName)
    if name and name == lastSale.name and now - lastSale.t <= 2 then return end
    lastSale.name, lastSale.t = name, now
    local post = self:FindPostByID(auctionID) or self:FindPost(itemName, now)
    if not post or (post.n or 0) >= post.q then return end
    post.n = (post.n or 0) + 1
    if not post.s then
        post.s = now
        ns.Undercuts:SoldPost(post.k, post.p, now)
    end
    self:MailDue(post, now)
    if ns.db.settings.saleMessages then
        Util.Print(self:Message(post))
    end
end

-- ---------------------------------------------------------------------
-- Gold on the way
-- ---------------------------------------------------------------------

local MAIL_DELAY = 3600
-- A due sale with no mail in a fully listed inbox this long after the hour
-- was collected some way the hooks missed, so it goes.
local MAIL_GRACE = 300
-- AH mail is kept 30 days.
local MAIL_KEEP = 31 * 86400

function Sales:MailDue(post, now)
    local due = ns.db.mailDue
    due[#due + 1] = { c = ns.charKey, t = now, name = post.name, g = Util.AfterCut(post.v),
                      stack = post.q > 1 or nil }
    while due[1] and now - due[1].t > MAIL_KEEP do table.remove(due, 1) end
    ns.Events:Fire("AC_MAIL_DUE_CHANGED")
end

-- A sale mail was collected on this character: the oldest sale of that
-- item is no longer on the way.
function Sales:MailCollected(itemName)
    local name = Sales.PlainName(itemName)
    local due = ns.db and ns.db.mailDue
    if not due or not name then return end
    for i, entry in ipairs(due) do
        if entry.c == ns.charKey and entry.name == name then
            table.remove(due, i)
            ns.Events:Fire("AC_MAIL_DUE_CHANGED")
            return
        end
    end
end

-- With every mail listed (the inbox shows at most 50), a sale that should
-- have arrived but has no mail was collected already: drop it.
function Sales:CheckMailDue(now)
    local due = ns.db and ns.db.mailDue
    if not due or #due == 0 or not GetInboxNumItems then return end
    local shown, total = GetInboxNumItems()
    if (total or shown) > shown then return end
    local mails = {}
    for i = 1, shown do
        local invoiceType, itemName = GetInboxInvoiceInfo(i)
        if invoiceType == "seller" and Readable(itemName) then
            local name = Sales.PlainName(itemName)
            mails[name] = (mails[name] or 0) + 1
        end
    end
    local changed = false
    for i = #due, 1, -1 do
        local entry = due[i]
        if entry.c == ns.charKey and now - entry.t > MAIL_DELAY + MAIL_GRACE then
            if (mails[entry.name] or 0) > 0 then
                mails[entry.name] = mails[entry.name] - 1
            else
                table.remove(due, i)
                changed = true
            end
        end
    end
    if changed then ns.Events:Fire("AC_MAIL_DUE_CHANGED") end
end

-- What's on the way, all characters: { coming = { n, gold, more, next },
-- waiting = { n, gold, more }, chars = { [charKey] = { coming, waiting } } }.
-- more: a stack sale is in there, so the gold is at least this much.
function Sales:OnTheWay(now)
    now = now or Util.Now()
    local function Bucket() return { n = 0, gold = 0 } end
    local result = { coming = Bucket(), waiting = Bucket(), chars = {} }
    for _, entry in ipairs(ns.db.mailDue or {}) do
        if now - entry.t <= MAIL_KEEP then
            local arrives = entry.t + MAIL_DELAY
            local kind = arrives > now and "coming" or "waiting"
            local char = result.chars[entry.c]
            if not char then
                char = { coming = Bucket(), waiting = Bucket() }
                result.chars[entry.c] = char
            end
            for _, b in ipairs({ result[kind], char[kind] }) do
                b.n, b.gold = b.n + 1, b.gold + (entry.g or 0)
                if entry.stack then b.more = true end
                if kind == "coming" and (not b.next or arrives < b.next) then b.next = arrives end
            end
        end
    end
    return result
end

-- ---------------------------------------------------------------------
-- The mailbox: exact amounts
-- ---------------------------------------------------------------------

-- Each "Auction successful" mail's invoice names the item, how many sold
-- and (in the mail) the gold after the cut. A mail has no ID, so it is
-- remembered by item, count, gold and when it expires (now + days left,
-- in 15 minute steps, with a step either side for rounding) until it
-- expires: reported once however often the mailbox is opened.

local MAIL_STEP = 900

local function MailSig(name, count, money, step)
    return name .. "|" .. count .. "|" .. money .. "|" .. step
end

-- One line per item for sale mails not reported before. Returns the lines.
function Sales:ScanMail(now)
    if not ns.db or not GetInboxInvoiceInfo or not GetInboxNumItems then return {} end
    now = now or Util.Now()
    ns.db.mailSeen = ns.db.mailSeen or {}
    local seenMail = ns.db.mailSeen
    for sig, expires in pairs(seenMail) do
        if expires < now then seenMail[sig] = nil end
    end
    local order, byItem = {}, {}
    for i = 1, GetInboxNumItems() do
        local invoiceType, itemName, _, _, _, _, _, _, _, _, count = GetInboxInvoiceInfo(i)
        if invoiceType == "seller" and Readable(itemName) then
            local _, _, _, _, money, _, daysLeft = GetInboxHeaderInfo(i)
            money, count = money or 0, math.max(1, count or 1)
            local expires = now + math.floor((daysLeft or 0) * 86400)
            local step = math.floor(expires / MAIL_STEP)
            local known
            for d = -1, 1 do
                if seenMail[MailSig(itemName, count, money, step + d)] then known = true end
            end
            if not known then
                seenMail[MailSig(itemName, count, money, step)] = expires
                local entry = byItem[itemName]
                if not entry then
                    entry = { name = itemName, count = 0, money = 0, mails = 0 }
                    byItem[itemName] = entry
                    order[#order + 1] = entry
                end
                entry.count, entry.money, entry.mails = entry.count + count, entry.money + money, entry.mails + 1
            end
        end
    end
    local lines = {}
    for _, entry in ipairs(order) do
        local gold = Util.FormatMoneyIcons(entry.money)
        if entry.count == 1 then
            lines[#lines + 1] = L.MAIL_SOLD_ONE:format(entry.name, gold)
        else
            local amount = BreakUpLargeNumbers and BreakUpLargeNumbers(entry.count) or tostring(entry.count)
            local text = L.MAIL_SOLD:format(entry.name, amount, gold)
            if entry.mails > 1 then text = text .. " " .. L.MAIL_SALES:format(entry.mails) end
            lines[#lines + 1] = text
        end
    end
    return lines
end

-- How many of an auction sold so far: what was posted (found by auction
-- ID) minus what is still listed. nil when the post isn't known.
function Sales:PostedFor(auctionID)
    local post = self:FindPostByID(auctionID)
    return post and post.q or nil
end

-- ---------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------

-- ERR_AUCTION_SOLD_S is "A buyer has been found for your auction of %s."
-- in the player's language; turned into a pattern that captures the name.
local soldPattern
if type(ERR_AUCTION_SOLD_S) == "string" then
    soldPattern = "^" .. ERR_AUCTION_SOLD_S:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.+)") .. "$"
end

-- Retail reports sales as an AH notification (Blizzard's chat frame
-- prints "A buyer has been found..." from it). The chat message is only a
-- fallback in case a client sends it as plain system text.
local SOLD = Enum.AuctionHouseNotification and Enum.AuctionHouseNotification.AuctionSold


ns.Events:On("AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", function(_, notification, text, auctionID)
    if not ns.db or notification ~= SOLD or not Readable(text) then return end
    Sales:OnSold(text, Util.Now(), auctionID)
end)

-- The mailbox: print what the sale mails say, once each. A short wait
-- lets the inbox finish loading (it fires this several times).
ns.Events:On("MAIL_INBOX_UPDATE", function()
    if not ns.db then return end
    Util.Debounce("mailSales", 1, function()
        Sales:CheckMailDue(Util.Now())
        if not ns.db.settings.saleMessages then return end
        for _, line in ipairs(Sales:ScanMail(Util.Now())) do
            Util.Print(line)
        end
    end)
end)

ns.Events:On("CHAT_MSG_SYSTEM", function(_, message)
    if not soldPattern or not ns.db or not Readable(message) then return end
    local name = message:match(soldPattern)
    if name then Sales:OnSold(name, Util.Now()) end
end)

-- Blizzard confirms each post with its auction ID, in posting order: attach
-- it to the oldest recent post that has none yet, so a sale can be matched
-- exactly even when several items are posted quickly.
ns.Events:On("AUCTION_HOUSE_AUCTION_CREATED", function(_, auctionID)
    local posts = ns.db and auctionID and Posts(ns.realmGroup, false)
    if not posts then return end
    local now = Util.Now()
    for _, post in ipairs(posts) do
        if not post.id and now - post.p <= 30 then
            post.id = auctionID
            return
        end
    end
end)

-- Item key and link of the item being posted.
local function ItemAt(location)
    local ok, link = pcall(C_Item.GetItemLink, location)
    if not ok or not link then return nil, nil end
    return Util.ItemKeyFromLink(link), link
end

ns.Events:On("AC_LOGIN", function()
    if not C_AuctionHouse then return end
    if C_AuctionHouse.PostCommodity then
        hooksecurefunc(C_AuctionHouse, "PostCommodity", function(location, _, quantity, unitPrice)
            local key, link = ItemAt(location)
            Sales:Posted(key, unitPrice, quantity, nil, link)
        end)
    end
    if C_AuctionHouse.PostItem then
        hooksecurefunc(C_AuctionHouse, "PostItem", function(location, _, quantity, _, buyout)
            if buyout and buyout > 0 then
                quantity = math.max(1, quantity or 1)
                local key, link = ItemAt(location)
                Sales:Posted(key, math.floor(buyout / quantity), quantity, nil, link)
            end
        end)
    end
end)

ns:RegisterCommand("sales", function()
    ns.db.settings.saleMessages = not ns.db.settings.saleMessages
    Util.Print(ns.db.settings.saleMessages and L.SALES_ON or L.SALES_OFF)
end, L.HELP_SALES)
