-- Auction Coach - "why isn't it selling?": a plain verdict for one listing
-- (or one item about to be posted), from data the addon already has:
-- sales a day, the usual lowest price, listings ahead in the queue (from the
-- last live search), how long it usually takes to sell, and whether
-- someone is cheaper. Used by the Auctions tab tooltip and the Sell tab.
--
-- Verdict codes, most important first:
--   NO_DATA    no sales data for the item yet
--   UNDERCUT   someone listed it cheaper: buyers take the cheapest first
--   OVERPRICED well over its usual lowest price
--   SLOW       sells less than once a day here
--   QUEUE      a queue of listings ahead that takes days to sell through
--   FRESH      posted more recently than it usually takes to sell
--   FAST       the cheapest, and it sells often: just wait
--   OK         nothing stands out

local _, ns = ...
local L, Util = ns.L, ns.Util

local WhySelling = {}
ns.WhySelling = WhySelling

-- Over the usual lowest price by more than this is "overpriced".
local OVER_USUAL = 1.2
-- At least this many sales a day counts as a fast seller (the author's own
-- rule of thumb is 20+ a day, 100+ for materials).
local FAST = 20

local function Span(seconds)
    if seconds < 3600 then return L.WHY_MINUTES:format(math.max(1, math.floor(seconds / 60 + 0.5))) end
    if seconds < 2 * 86400 then return L.WHY_HOURS:format(math.floor(seconds / 3600 + 0.5)) end
    return L.WHY_DAYS:format(math.floor(seconds / 86400 + 0.5))
end

local function Ahead(rows, price)
    local ahead = 0
    for _, row in ipairs(rows) do
        if row[1] < price then ahead = ahead + row[2] end
    end
    return ahead
end

-- key, unit price, quantity listed, when it was posted (nil = not yet),
-- standing ("CHEAPEST" | "UNDERCUT" | nil, from Auctions.Standing).
-- Returns { code, lines = { sentence, ... } }: the first line is the headline.
function WhySelling.Verdict(key, unit, quantity, postedAt, standing)
    local price = ns.Prices:Get(key)
    local money = Util.FormatMoneyIcons
    local lines, code = {}, nil
    local function Add(c, text)
        code = code or c
        lines[#lines + 1] = text
    end
    local spd = price and price.salesPerDay
    if not price or not spd then
        return { code = "NO_DATA", lines = { L.WHY_NO_DATA } }
    end
    quantity = math.max(1, quantity or 1)

    if standing == "UNDERCUT" and price.min and price.min < unit then
        Add("UNDERCUT", L.WHY_UNDERCUT:format(money(price.min), math.floor((unit / price.min - 1) * 100 + 0.5)))
    end
    local usual = price.usualMin or price.historical
    if usual and usual > 0 and unit > usual * OVER_USUAL then
        Add("OVERPRICED", L.WHY_OVERPRICED:format(math.floor((unit / usual - 1) * 100 + 0.5), money(usual)))
    end
    if spd < 1 then
        Add("SLOW", L.WHY_SLOW)
    end

    -- The queue: listings cheaper than yours sell first. Exact after a live
    -- search; with none, the cheapest listing has nobody ahead.
    local rows = ns.SellChance:GetLadder(key)
    local ahead = rows and Ahead(rows, unit) or (standing == "CHEAPEST" and 0 or nil)
    -- An estimate, added after the reasons; none when the price itself is
    -- the problem (undercut, overpriced, slow), where it would mislead.
    local expect
    if ahead and spd > 0 then
        local seconds = (ahead + quantity) / spd * 86400
        if ahead > 0 and seconds >= 86400 then
            Add("QUEUE", L.WHY_QUEUE:format(BreakUpLargeNumbers(ahead), BreakUpLargeNumbers(math.floor(spd + 0.5)), Span(seconds)))
        elseif spd >= 1 and not code then
            expect = L.WHY_EXPECT:format(Span(seconds))
        end
    end

    local sellTime = price.sharedSell
    if postedAt and sellTime and sellTime.seconds and Util.Now() - postedAt < sellTime.seconds then
        Add("FRESH", L.WHY_FRESH:format(Span(Util.Now() - postedAt), Span(sellTime.seconds)))
    end

    if not code then
        if standing ~= "UNDERCUT" and spd >= FAST then
            Add("FAST", L.WHY_FAST:format(BreakUpLargeNumbers(math.floor(spd + 0.5))))
        else
            code = "OK"
            if spd >= 1 then lines[#lines + 1] = L.WHY_RATE:format(BreakUpLargeNumbers(math.floor(spd + 0.5))) end
        end
    end
    if expect then lines[#lines + 1] = expect end
    return { code = code, lines = lines }
end

-- For one of your auctions (an Auctions:List entry). posts: from
-- Auctions.NewestPosts(), passed in when checking a whole list.
function WhySelling.ForAuction(entry, posts)
    posts = posts or ns.Auctions.NewestPosts()
    local standing = ns.Auctions.Standing(entry.key, entry.unit, posts)
    local post = posts[entry.key]
    return WhySelling.Verdict(entry.key, entry.unit, entry.quantity, post and post.p, standing)
end
