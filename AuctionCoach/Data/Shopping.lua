-- Auction Coach - shopping list: items the player wants, each with the
-- most they'll pay. When one is listed at or below that on this realm's
-- AH (full scan, live search or desktop app prices), the Deals tab's
-- Shopping view shows it, its tooltip says so, and a chat line points it
-- out (once per item per ALERT_EVERY).
--
--   db.shopping[itemKey] = { max = copper each, added = unix time }
--
-- Buying is always left to the player.

local _, ns = ...
local L, Util = ns.L, ns.Util

local Shopping = {}
ns.Shopping = Shopping

-- A lowest price older than this has probably been bought already.
local MAX_AGE = 3 * 3600
local ALERT_EVERY = 30 * 60

local alertedAt = {}

local function List()
    ns.db.shopping = ns.db.shopping or {}
    return ns.db.shopping
end

function Shopping:Add(key, maxPrice, link)
    if not key or not maxPrice or maxPrice <= 0 then return false end
    List()[key] = { max = math.floor(maxPrice), added = Util.Now() }
    if link and not Util.LinkHasName(ns.db.links[key]) then ns.db.links[key] = link end
    alertedAt[key] = nil
    ns.Events:Fire("AC_SHOPPING_CHANGED")
    return true
end

function Shopping:Remove(key)
    if not key or not List()[key] then return false end
    List()[key] = nil
    ns.Events:Fire("AC_SHOPPING_CHANGED")
    return true
end

function Shopping:Get(key)
    return key and ns.db and ns.db.shopping and ns.db.shopping[key]
end

-- One entry's state on this realm. Pure apart from the price passed in:
-- price is Prices:Get's result or nil.
--   status "BUY"      listed at or below the max, seen recently
--          "WAIT"     listed, but above the max
--          "OLD"      at or below the max, but not seen for a while
--          "UNKNOWN"  no price on this realm yet
function Shopping.Evaluate(entry, price, now)
    if not price or not price.min or price.min <= 0 then return "UNKNOWN" end
    if price.min > entry.max then return "WAIT" end
    if now - (price.minAt or price.t or 0) > MAX_AGE then return "OLD" end
    return "BUY"
end

-- Every item on the list: { { key, max, lowest, lowestAt, status }, ... },
-- items to buy now first, then cheapest compared with the max.
function Shopping:Items()
    local items = {}
    if not ns.db then return items end
    local now = Util.Now()
    for key, entry in pairs(List()) do
        local price = ns.Prices:Get(key)
        items[#items + 1] = {
            key = key, max = entry.max,
            lowest = price and price.min, lowestAt = price and (price.minAt or price.t),
            status = Shopping.Evaluate(entry, price, now),
        }
    end
    local ORDER = { BUY = 1, OLD = 2, WAIT = 3, UNKNOWN = 4 }
    table.sort(items, function(a, b)
        if a.status ~= b.status then return ORDER[a.status] < ORDER[b.status] end
        local ra = a.lowest and a.lowest / a.max or math.huge
        local rb = b.lowest and b.lowest / b.max or math.huge
        if ra ~= rb then return ra < rb end
        return a.key < b.key
    end)
    return items
end

function Shopping:CountToBuy()
    local n = 0
    for _, item in ipairs(self:Items()) do
        if item.status == "BUY" then n = n + 1 end
    end
    return n
end

-- Chat line for items that just became buyable.
local function Alert()
    if not ns.db or not ns.realmGroup or ns.db.settings.shoppingAlerts == false then return end
    local now = Util.Now()
    for _, item in ipairs(Shopping:Items()) do
        if item.status == "BUY" and now - (alertedAt[item.key] or 0) > ALERT_EVERY then
            alertedAt[item.key] = now
            local link = Util.NamedLink(item.key) or item.key
            Util.Print(L.SHOP_ALERT:format(link, Util.FormatMoneyIcons(item.lowest), Util.FormatMoneyIcons(item.max)))
        end
    end
end

for _, event in ipairs({ "AC_SCAN_COMPLETE", "AC_LIVE_PRICE", "AC_DATA_CHANGED", "AUCTION_HOUSE_SHOW" }) do
    ns.Events:On(event, function()
        Util.Debounce("shoppingAlert", 1, Alert)
    end)
end

-- ---------------------------------------------------------------------
-- /ac shop
-- ---------------------------------------------------------------------

-- "12", "12.5", "12g 50s", "12g", "50s" -> copper, or nil.
function Shopping.ParsePrice(text)
    if not text then return nil end
    text = text:lower():gsub(",", "")
    local gold = tonumber(text:match("^%s*([%d%.]+)%s*$"))
    if gold then return math.floor(gold * 10000 + 0.5) end
    local g = tonumber(text:match("([%d%.]+)%s*g"))
    local s = tonumber(text:match("(%d+)%s*s"))
    if not g and not s then return nil end
    return math.floor((g or 0) * 10000 + (s or 0) * 100 + 0.5)
end

ns:RegisterCommand("shop", function(args)
    local action, rest = (args or ""):match("^(%S*)%s*(.-)$")
    action = (action or ""):lower()
    if action == "add" then
        -- A shift-clicked link (coloured or bare), then the price.
        local s, e = rest:find("|c.-|h|r")
        if not s then s, e = rest:find("|H.-|h.-|h") end
        local link = s and rest:sub(s, e)
        local priceText = e and rest:sub(e + 1)
        local key = link and Util.ItemKeyFromLink(link)
        local price = Shopping.ParsePrice(priceText)
        if not key or not price then
            Util.Print(L.SHOP_USAGE)
            return
        end
        Shopping:Add(key, price, link)
        Util.Print(L.SHOP_ADDED:format(link, Util.FormatMoneyIcons(price)))
    elseif action == "remove" then
        local key = Util.ItemKeyFromLink(rest)
        if Shopping:Remove(key) then
            Util.Print(L.SHOP_REMOVED:format(rest))
        else
            Util.Print(L.SHOP_USAGE)
        end
    elseif action == "alerts" then
        ns.db.settings.shoppingAlerts = ns.db.settings.shoppingAlerts == false
        Util.Print(ns.db.settings.shoppingAlerts and L.SHOP_ALERTS_ON or L.SHOP_ALERTS_OFF)
    elseif ns.DealsTab then
        ns.DealsTab:ShowMode("shopping")
    end
end, L.HELP_SHOP)
