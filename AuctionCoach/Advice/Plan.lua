-- Auction Coach - Today's Plan: a short, ranked to-do list for the time the
-- player has ("15 min"), with the gold each step should make.
--
-- Steps come from advice that already exists:
--   MAIL    collect the mailbox (gold from sales, expired or cancelled
--           items). Pinned first when there is anything waiting, and its
--           time is taken off the budget before ranking; it makes no new
--           gold itself.
--   POST    items worth listing (Sell), from this character's bags, its
--           bank, the warband bank or the mailbox (from = "bank" |
--           "warband" | "mail"; expired auctions come back by mail)
--   REPOST  the player's own listings that someone has undercut
--           (Advice/Auctions.lua)
--   CANCEL  own listings a vendor now pays more for: cancel, then vendor
--   BUY     deals worth flipping (Deals); deals for items with the same
--           name are one step
--   VENDOR  everything in the bags a vendor pays more for, as one step
--   SKIP    items better left alone today (prices crashed, or undercut far
--           faster than the player checks back). Shown, never counted.
--
-- Each step gets an expected gold figure (what should actually come in,
-- not the best case) and a rough time cost. Steps are ranked by gold per
-- minute and taken until the time budget is used up. Getting to the AH or
-- the bank costs time once, the first time a step needs it. Buys also
-- need the gold to pay for them.
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
    POST = 20,      -- per stack: put it in the sell box, check, post
    WITHDRAW = 10,  -- per stack: take it out of the bank
    REPOST = 40,    -- cancel, wait, post again
    BUY = 45,       -- look at the listings and buy
    BUY_MORE = 20,  -- each further item in a same-name group
    VENDOR = 30,    -- one trip to a vendor for everything
    MAIL = 30,      -- take everything from the mailbox
    CANCEL = 70,    -- cancel, collect it from the mail, sell to a vendor
}

-- Places a step may need to walk to first, and how long that takes.
local SETUP = {
    ah = 60,        -- walking to the AH and opening it
    bank = 45,      -- walking to a banker
    mailbox = 30,   -- walking to a mailbox (only for the pinned MAIL step)
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

-- candidates: { { kind, gold, seconds, spend = copper, ah = true, bank = true, ... }, ... }
-- setups: { place = seconds }, added once for the first step with that flag.
-- money: copper the player can spend, or nil for no limit.
-- Returns steps (picked, best gold per minute first), gold, seconds, and
-- how many steps were left out because they cost more than the money left.
-- A step that does not fit is skipped, so smaller ones later in the
-- ranking can still use the time left.
function Plan.Select(candidates, budgetSeconds, setups, money)
    setups = setups or {}
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

    local steps, gold, used, visited, unaffordable = {}, 0, 0, {}, 0
    for _, c in ipairs(ranked) do
        local cost = c.seconds
        for place, seconds in pairs(setups) do
            if c[place] and not visited[place] then cost = cost + seconds end
        end
        local spend = c.spend or 0
        if money and spend > money then
            unaffordable = unaffordable + 1
        elseif used + cost <= budgetSeconds then
            steps[#steps + 1] = c
            used = used + cost
            gold = gold + c.gold
            if money then money = money - spend end
            for place in pairs(setups) do
                if c[place] then visited[place] = true end
            end
        end
    end
    return steps, gold, used, unaffordable
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

-- item: { key, count, suggestion, value, from = nil | "bank" | "warband" }
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
    local fromBank = item.from == "bank" or item.from == "warband"
    return {
        id = "POST:" .. (item.from and (item.from .. ":") or "") .. item.key,
        kind = "POST", key = item.key, count = item.count, from = item.from,
        price = s.price, full = item.value, gold = gold, sold = sold,
        seconds = COST.POST + (fromBank and COST.WITHDRAW or 0),
        ah = true, bank = fromBank or nil, suggestion = s,
    }
end

-- Items in this character's bank (and reagent bank) and the warband bank,
-- as Sell:List-style items with from = "bank" | "warband". Only what the
-- addon saw the last time a bank was open.
local function BankItems()
    local items = {}
    local function Add(from, list)
        local merged = {}
        for key, count in pairs(list or {}) do merged[key] = (merged[key] or 0) + count end
        for key, count in pairs(merged) do
            local link = ns.db.links[key]
            local s = ns.Rules:SuggestPrice(key, link)
            items[#items + 1] = {
                key = key, link = link, count = count, suggestion = s, from = from,
                value = s.price and Util.AfterCut(s.price) * count or 0,
            }
        end
    end
    local char = ns.db.characters[ns.charKey]
    local inv = char and char.inventory
    if inv then
        local own = {}
        for _, list in ipairs({ inv.bank or {}, inv.reagentBank or {} }) do
            for key, count in pairs(list) do own[key] = (own[key] or 0) + count end
        end
        Add("bank", own)
    end
    Add("warband", ns.db.warbank)
    return items
end

-- Items waiting in this character's mailbox that are worth posting, as
-- Sell:List-style items with from = "mail". Only what the addon saw the
-- last time the mailbox was open.
local function MailItems()
    local items = {}
    local char = ns.db.characters[ns.charKey]
    local mail = char and char.inventory and char.inventory.mail
    for key, count in pairs(mail or {}) do
        local link = ns.db.links[key]
        local s = ns.Rules:SuggestPrice(key, link)
        items[#items + 1] = {
            key = key, link = link, count = count, suggestion = s, from = "mail",
            value = s.price and Util.AfterCut(s.price) * count or 0,
        }
    end
    return items
end

-- The pinned "collect your mailbox" step, or nil when nothing is waiting.
local function MailStep()
    local char = ns.db.characters[ns.charKey]
    if not char then return nil end
    local items = 0
    for _, count in pairs(char.inventory and char.inventory.mail or {}) do items = items + count end
    local gold = char.mailGold or 0
    if items == 0 and gold <= 0 then return nil end
    return {
        id = "MAIL", kind = "MAIL", count = items, mailGold = gold,
        seconds = COST.MAIL + SETUP.mailbox,
    }
end

-- Own listings someone has undercut (REPOST), or that a vendor now pays
-- more for (CANCEL), from Advice/Auctions.lua.
local function AuctionCandidates(list)
    for _, entry in ipairs(ns.Auctions:List().items) do
        local s = entry.suggestion
        if entry.action == "REPOST" then
            local sold = ExpectedSold(entry.quantity, s.salesPerDay)
            local unit = Util.AfterCut(entry.newPrice)
            local gold = sold and unit * sold or unit * entry.quantity * UNKNOWN_SPEED_FACTOR
            list[#list + 1] = {
                id = "REPOST:" .. entry.key .. "@" .. entry.unit, kind = "REPOST", key = entry.key,
                count = entry.quantity, price = entry.newPrice, oldPrice = entry.unit, lowest = entry.lowest,
                gold = math.floor(gold * ns.Styles.Factor(s.contested)), sold = sold,
                seconds = COST.REPOST * entry.auctions, ah = true, suggestion = s,
            }
        elseif entry.action == "CANCEL" then
            list[#list + 1] = {
                id = "CANCEL:" .. entry.key .. "@" .. entry.unit, kind = "CANCEL", key = entry.key,
                count = entry.quantity, oldPrice = entry.unit, vendor = s.vendor,
                gold = entry.vendorGold, seconds = COST.CANCEL * entry.auctions, ah = true,
            }
        end
    end
end

-- Chance one bought item resells before the player is back: its sales
-- per day spread over the seller style's window, at most certain.
local function ResellChance(salesPerDay)
    return math.min(1, (salesPerDay or 0) * ns.Styles:WindowHours() / 24)
end

-- Deals, one step per item name: several different items that share a
-- name and are all listed cheaply are one decision for the player.
local function BuyCandidates(list)
    local groups, order = {}, {}
    for _, d in ipairs(ns.Deals:List().items) do
        local link = Util.NamedLink(d.key)
        local name = link and ns.Sales.PlainName(link) or d.key
        local group = groups[name]
        if not group then
            if #order >= MAX_BUYS then break end
            group = {}
            groups[name] = group
            order[#order + 1] = name
        end
        group[#group + 1] = d
    end

    for _, name in ipairs(order) do
        local deals = groups[name]
        local best = deals[1]
        local gold, spend, chance = 0, 0, 0
        for _, d in ipairs(deals) do
            local c = ResellChance(d.salesPerDay)
            gold = gold + d.profit * BUY_FACTOR * c
            spend = spend + d.price
            chance = math.max(chance, c)
        end
        list[#list + 1] = {
            id = "BUY:" .. best.key, kind = "BUY", key = best.key, count = #deals,
            price = best.price, resell = best.resell, profit = best.profit, deal = best,
            chance = chance, gold = math.floor(gold), spend = spend,
            seconds = COST.BUY + COST.BUY_MORE * (#deals - 1), ah = true,
        }
    end
end

-- Returns {
--   steps        picked steps, best gold per minute first
--   gold         expected gold from all steps
--   seconds      rough time they take
--   budget       minutes asked for
--   skips        up to MAX_SKIPS { kind = "SKIP", key, count, suggestion } to leave alone
--   left         steps that did not fit in the time
--   unaffordable buys left out because they cost more than the gold on hand
--   money        gold on this character
--   elsewhere    { { owner, value }, ... } sellable value on other
--                characters, most first
--   hasSpeed     true when sales rates (desktop app data) were available
-- }
function Plan:Build(minutes)
    local result = { steps = {}, gold = 0, seconds = 0, skips = {}, left = 0, unaffordable = 0, elsewhere = {} }
    if not ns.db or not ns.charKey then
        result.budget = minutes or 15
        return result
    end
    minutes = minutes or ns.db.settings.planMinutes or 15
    result.budget = minutes

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
    -- Bank items worth posting. Crashed or contested ones are left out
    -- quietly: the "leave alone" list is about what is in the bags.
    for _, item in ipairs(BankItems()) do
        local s = item.suggestion
        if s.salesPerDay then result.hasSpeed = true end
        if s.action == "POST" and s.contested ~= "HEAVY" then
            candidates[#candidates + 1] = PostCandidate(item)
        end
    end
    -- Mail items worth posting. The pinned MAIL step collects them, so
    -- they need no extra walk.
    local mailStep = MailStep()
    if mailStep then
        for _, item in ipairs(MailItems()) do
            local s = item.suggestion
            if s.salesPerDay then result.hasSpeed = true end
            if s.action == "POST" and s.contested ~= "HEAVY" then
                candidates[#candidates + 1] = PostCandidate(item)
            end
        end
    end
    if vendorItems > 0 then
        candidates[#candidates + 1] = {
            id = "VENDOR", kind = "VENDOR", count = vendorItems, gold = vendorGold, seconds = COST.VENDOR,
        }
    end
    AuctionCandidates(candidates)
    BuyCandidates(candidates)

    -- Mailbox gold is spendable once collected, so deals can use it.
    result.money = GetMoney() + (mailStep and mailStep.mailGold or 0)
    local budget = minutes * 60 - (mailStep and mailStep.seconds or 0)
    local setups = {}
    for place, seconds in pairs(SETUP) do
        if place ~= "mailbox" then setups[place] = seconds end
    end
    result.steps, result.gold, result.seconds, result.unaffordable =
        Plan.Select(candidates, math.max(0, budget), setups, result.money)
    result.left = #candidates - #result.steps - result.unaffordable
    if mailStep then
        table.insert(result.steps, 1, mailStep)
        result.seconds = result.seconds + mailStep.seconds
    end

    for _, o in ipairs(ns.Treasure:Compute().owners) do
        if o.owner ~= ns.charKey and o.owner ~= "warband" and o.value > 0 then
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
