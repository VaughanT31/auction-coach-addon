-- Auction Coach - Today's Plan: a short, ranked to-do list for the time the
-- player has ("15 min"), with the gold each step should make.
--
-- Steps come from advice that already exists:
--   POST    items in this character's bags worth listing (Sell)
--   REPOST  the player's own listings that someone has undercut (posts)
--   BUY     deals worth flipping (Deals)
--   VENDOR  everything a vendor pays more for, as one step
--   SKIP    items better left alone today (prices crashed, or undercut far
--           faster than the player checks back). Shown, never counted.
--
-- Each step gets an expected gold figure (what should actually come in,
-- not the best case) and a rough time cost. Steps are ranked by gold per
-- minute and taken until the time budget is used up. Getting to the AH
-- costs a minute once, the first time an AH step is picked.
--
-- Plan.Select does the ranking and has no WoW API calls, so it can be
-- tested outside the game.

local _, ns = ...
local Util = ns.Util

local Plan = {}
ns.Plan = Plan

Plan.BUDGETS = { 5, 15, 30, 60 }

-- Rough seconds each kind of step takes the player.
local COST = {
    AH_SETUP = 60,  -- walking to the AH and opening it
    POST = 20,      -- per stack: put it in the sell box, check, post
    REPOST = 40,    -- cancel, wait, post again
    BUY = 45,       -- look at the listings and buy
    VENDOR = 30,    -- one trip to a vendor for everything
}

-- Deals still need reselling, and the cheap listing may be gone.
local BUY_FACTOR = 0.7
-- Without a sales rate, assume about half of what is posted sells in time.
local UNKNOWN_SPEED_FACTOR = 0.5
local MAX_BUYS = 10
local MAX_SKIPS = 3

-- ---------------------------------------------------------------------
-- Ranking (pure: no WoW API)
-- ---------------------------------------------------------------------

-- candidates: { { kind, gold, seconds, ah = true|nil, ... }, ... }
-- Returns steps (picked, best gold per minute first), gold, seconds.
-- A step that does not fit is skipped, so smaller ones later in the
-- ranking can still use the time left.
function Plan.Select(candidates, budgetSeconds, setupSeconds)
    local ranked = {}
    for _, c in ipairs(candidates) do
        if c.gold and c.gold > 0 and c.seconds and c.seconds > 0 then
            ranked[#ranked + 1] = c
        end
    end
    table.sort(ranked, function(a, b)
        local ra, rb = a.gold / a.seconds, b.gold / b.seconds
        if ra ~= rb then return ra > rb end
        if a.gold ~= b.gold then return a.gold > b.gold end
        return (a.id or "") < (b.id or "")
    end)

    local steps, gold, used, atAH = {}, 0, 0, false
    for _, c in ipairs(ranked) do
        local cost = c.seconds
        if c.ah and not atAH then cost = cost + (setupSeconds or 0) end
        if used + cost <= budgetSeconds then
            steps[#steps + 1] = c
            used = used + cost
            gold = gold + c.gold
            if c.ah then atAH = true end
        end
    end
    return steps, gold, used
end

-- ---------------------------------------------------------------------
-- Candidates from the rest of the addon
-- ---------------------------------------------------------------------

-- How many of count should sell before the player is back (seller style
-- window), or nil without a sales rate.
local function ExpectedSold(count, salesPerDay)
    if not salesPerDay or salesPerDay <= 0 then return nil end
    return math.min(count, salesPerDay * ns.Styles:WindowHours() / 24)
end

local function PostCandidate(item)
    local s = item.suggestion
    local unit = Util.AfterCut(s.price)
    local sold = ExpectedSold(item.count, s.salesPerDay)
    local gold
    if sold then
        gold = unit * sold
    else
        gold = unit * item.count * UNKNOWN_SPEED_FACTOR
    end
    gold = math.floor(gold * ns.Styles.Factor(s.contested))
    return {
        id = "POST:" .. item.key, kind = "POST", key = item.key, count = item.count,
        price = s.price, full = item.value, gold = gold, sold = sold,
        seconds = COST.POST, ah = true, suggestion = s,
    }
end

-- The player's newest post of each item on this realm group that has not
-- fully sold, keyed by item key.
local function OpenPosts()
    local open = {}
    local posts = ns.db.posts[ns.realmGroup]
    local now = Util.Now()
    for _, post in ipairs(posts or {}) do
        if now - post.p <= 48 * 3600 and (post.n or 0) < post.q then
            local current = open[post.k]
            if not current or post.p > current.p then open[post.k] = post end
        end
    end
    return open
end

-- Own listings with a lower price seen from someone else since posting.
local function RepostCandidates(list)
    local char = ns.db.characters[ns.charKey]
    local listed = char and char.inventory and char.inventory.auctions
    if not listed then return end
    local posts = OpenPosts()
    for key, quantity in pairs(listed) do
        local post = posts[key]
        local price = post and ns.Prices:Get(key)
        if price and price.min and price.minAt and price.minAt > post.p and price.min < post.v then
            local s = ns.Rules:SuggestPrice(key, ns.db.links[key])
            if s.action == "POST" and s.price then
                local remaining = math.min(quantity, post.q - (post.n or 0))
                local sold = ExpectedSold(remaining, s.salesPerDay)
                local unit = Util.AfterCut(s.price)
                local gold = sold and unit * sold or unit * remaining * UNKNOWN_SPEED_FACTOR
                list[#list + 1] = {
                    id = "REPOST:" .. key, kind = "REPOST", key = key, count = remaining,
                    price = s.price, oldPrice = post.v, lowest = price.min,
                    gold = math.floor(gold * ns.Styles.Factor(s.contested)), sold = sold,
                    seconds = COST.REPOST, ah = true, suggestion = s,
                }
            end
        end
    end
end

local function BuyCandidates(list)
    local deals = ns.Deals:List()
    for i = 1, math.min(#deals.items, MAX_BUYS) do
        local d = deals.items[i]
        list[#list + 1] = {
            id = "BUY:" .. d.key, kind = "BUY", key = d.key, price = d.price,
            resell = d.resell, profit = d.profit, deal = d,
            gold = math.floor(d.profit * BUY_FACTOR), seconds = COST.BUY, ah = true,
        }
    end
end

-- Returns {
--   steps     picked steps, best gold per minute first
--   gold      expected gold from all steps
--   seconds   rough time they take
--   budget    minutes asked for
--   skips     up to MAX_SKIPS { kind = "SKIP", key, count, suggestion } to leave alone
--   left      steps that did not fit in the time
--   elsewhere { { owner, value }, ... } sellable value on other characters
--             and the warband bank, most first
--   hasSpeed  true when sales rates (desktop app data) were available
-- }
function Plan:Build(minutes)
    minutes = minutes or ns.db.settings.planMinutes or 15
    local result = { steps = {}, gold = 0, seconds = 0, budget = minutes, skips = {}, left = 0, elsewhere = {} }
    if not ns.db or not ns.charKey then return result end

    local candidates = {}
    local vendorGold, vendorItems = 0, 0
    for _, item in ipairs(ns.Sell:List().items) do
        local s = item.suggestion
        if s.salesPerDay then result.hasSpeed = true end
        if (s.action == "POST" and s.contested == "HEAVY") or s.action == "HOLD" then
            if #result.skips < MAX_SKIPS then
                result.skips[#result.skips + 1] = {
                    id = "SKIP:" .. item.key, kind = "SKIP", key = item.key, count = item.count, suggestion = s,
                }
            end
        elseif s.action == "POST" then
            candidates[#candidates + 1] = PostCandidate(item)
        elseif s.action == "VENDOR" and s.vendor and s.vendor > 0 then
            vendorGold = vendorGold + s.vendor * item.count
            vendorItems = vendorItems + 1
        end
    end
    if vendorItems > 0 then
        candidates[#candidates + 1] = {
            id = "VENDOR", kind = "VENDOR", count = vendorItems, gold = vendorGold, seconds = COST.VENDOR,
        }
    end
    RepostCandidates(candidates)
    BuyCandidates(candidates)

    result.steps, result.gold, result.seconds = Plan.Select(candidates, minutes * 60, COST.AH_SETUP)
    result.left = #candidates - #result.steps

    for _, o in ipairs(ns.Treasure:Compute().owners) do
        if o.owner ~= ns.charKey and o.value > 0 then
            result.elsewhere[#result.elsewhere + 1] = o
        end
    end
    return result
end

-- ---------------------------------------------------------------------
-- Ticked-off steps: kept until the next full scan, which rebuilds the
-- plan from fresh prices anyway.
-- ---------------------------------------------------------------------

local function DoneTable()
    local realm = ns:GetRealmData()
    local done = ns.db.planDone
    if not done or done.scan ~= realm.lastFullScan or done.char ~= ns.charKey then
        done = { scan = realm.lastFullScan, char = ns.charKey, ids = {} }
        ns.db.planDone = done
    end
    return done.ids
end

function Plan:IsDone(id)
    return DoneTable()[id] == true
end

function Plan:SetDone(id, value)
    DoneTable()[id] = value and true or nil
end
