-- Auction Coach - the player's own posts and sales.
--
-- Every post is remembered for 48 hours (the longest an auction runs) with
-- its price and quantity. When WoW says "A buyer has been found for your
-- auction of X", the matching post is found and Auction Coach adds what
-- the sale made after the AH cut. The message only names the item, so for
-- a stack (which can sell in parts) the line gives the price each and what
-- the whole stack makes.
--
--   db.posts[group] = { { k = item key, v = unit price, q = quantity,
--                         p = posted, s = first sale, n = sale messages,
--                         name = item name when posted,
--                         id = auction ID, when Blizzard reported it }, ... }

local _, ns = ...
local L, Util = ns.L, ns.Util

local Sales = {}
ns.Sales = Sales

local KEEP = 48 * 3600
local MAX_POSTS = 200

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
    return L.SALE_STACK:format(link, money(post.v), post.q, money(Util.AfterCut(post.v * post.q)))
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
    if ns.db.settings.saleMessages then
        Util.Print(self:Message(post))
    end
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
    if not ns.db or notification ~= SOLD or type(text) ~= "string" then return end
    Sales:OnSold(text, Util.Now(), auctionID)
end)

ns.Events:On("CHAT_MSG_SYSTEM", function(_, message)
    if not soldPattern or not ns.db or type(message) ~= "string" then return end
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
