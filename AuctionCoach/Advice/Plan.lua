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
--   SHOP    shopping list items listed at or below the player's max.
--           Pinned after MAIL (the player asked for them), not ranked; their
--           time and price come off the budget and the gold first.
--   DESTROY items in the bags worth more disenchanted, milled or prospected
--           than sold (Data/Destroy.lua), one step per kind, only for what
--           this character can do. Those items leave the POST and VENDOR steps.
--   CRAFT   recipes this character knows that clearly make more than
--           selling their materials (Advice/Crafting.lua), when the
--           materials are in the bags, bank or warband bank. As many
--           crafts as should sell before the player is back. The materials
--           they use leave the POST steps.
--   SKIP    items better left alone today (prices crashed, or undercut far
--           faster than the player checks back). Shown, never counted.
--   SLOW    items worth posting but unlikely to sell before the player is
--           back (less than FAST_ENOUGH chance of even one sale). Shown
--           after the plan as "post when you're done", never counted, so
--           the plan is the gold that should actually come in today.
--
-- Each step gets an expected gold figure (what should actually come in,
-- not the best case) and a rough time cost. Sales arrive at the item's
-- sales rate (a Poisson guess), so a stack of 20 that sells 4 a day counts
-- about 4, and a single item that sells once a week barely counts at all.
-- Selling steps, crafts and buys must have an even chance of a sale
-- before the player is back (FAST_ENOUGH), or they aren't plan steps. Steps are ranked by gold per
-- minute and taken until the time budget is used up. Getting to the AH or
-- the bank costs time once, the first time a step needs it. Buys also
-- need the gold to pay for them.
--
-- Fast sellers (0.28): items that sell at least FAST_SALES a day on the
-- realm (FAST_MATERIALS for region-wide materials) are marked fast on
-- POST, REPOST and CRAFT steps, and rank as if they made FAST_BONUS more,
-- so a near tie goes to the sale that's surer to happen. Under the plan,
-- "Sells fast here" lists the items that sell the most gold a day on this
-- realm, worth farming or crafting, marking those your characters can craft.
--
-- Items the player hid (settings.planHidden[key], right-click a step) are
-- never suggested. A character left out (settings.planSkipChars[charKey])
-- gets no selling, vendoring, destroying or crafting from its own bags,
-- bank or mail, for a main keeping its raid consumables; deals, shopping,
-- reposts of what it already listed and the warband bank still count.
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
    SHOP = 40,      -- find it and buy it
    DESTROY = 15,   -- open the profession or target the item
    DESTROY_CAST = 3, -- per disenchant, or per mill/prospect of five
    CRAFT = 35,     -- open the profession, find the recipe, post what it made
    CRAFT_EACH = 4, -- per craft
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
local MAX_SLOW = 5
-- A step that sells something needs at least this chance of one sale
-- before the player is back, or it's a slow seller, not part of today.
local FAST_ENOUGH = 0.5
Plan.FAST_ENOUGH = FAST_ENOUGH
-- Destroying is suggested only when the materials beat selling by this
-- much, and the materials still need posting, so count part of their value.
local DESTROY_MARGIN = 1.1
local DESTROY_FACTOR = 0.8
local DESTROY_KINDS = { DE = true, MILL = true, PROSPECT = true }
-- A craft is suggested only when it clearly beats selling the materials:
-- by this share of their value and at least this much per craft.
local CRAFT_MARGIN = 0.15
local CRAFT_MIN_PROFIT = 10000
local MAX_CRAFT_STEPS = 3
-- Without a sales rate, craft only a few.
local UNKNOWN_CRAFTS = 5
-- Fast sellers: sales a day on the realm, and for region-wide materials.
local FAST_SALES = 20
local FAST_MATERIALS = 100
local FAST_BONUS = 1.1
local MAX_FAST_LIST = 5
Plan.FAST_SALES, Plan.FAST_MATERIALS = FAST_SALES, FAST_MATERIALS

-- True when an item sells fast: at least FAST_SALES a day, FAST_MATERIALS
-- for commodities.
function Plan.IsFast(salesPerDay, commodity)
    return salesPerDay ~= nil and salesPerDay >= (commodity and FAST_MATERIALS or FAST_SALES)
end

local function Fast(key, salesPerDay)
    local price = salesPerDay and ns.Prices:Get(key)
    return Plan.IsFast(salesPerDay, price and price.commodity) or nil
end

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
        local ra = a.gold * (a.fast and FAST_BONUS or 1) / a.seconds
        local rb = b.gold * (b.fast and FAST_BONUS or 1) / b.seconds
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

-- How many of count should sell in hours when sales arrive at
-- salesPerDay, and the chance at least one does, or nil without a sales
-- rate. Expected sales of a stack: the sum over k of the chance of at
-- least k sales.
function Plan.Odds(count, salesPerDay, hours)
    if not salesPerDay or salesPerDay <= 0 then return nil end
    local lambda = salesPerDay * hours / 24
    local first = 1 - math.exp(-lambda)
    if count == math.huge or count > 2000 then return math.min(count, lambda), first end
    local sold = 0
    for k = 1, count do
        local p = ns.SellChance.AtLeast(k, lambda)
        if p < 0.0005 then break end
        sold = sold + p
    end
    return sold, first
end

-- Items the player hid from the plan (right-click a step).
local function HiddenItems()
    return ns.db.settings.planHidden or {}
end

-- Plan.Odds for the time until the player is back (seller style window).
local function ExpectedSold(count, salesPerDay)
    return Plan.Odds(count, salesPerDay, ns.Styles:WindowHours())
end

-- item: { key, count, suggestion, value, from = nil | "bank" | "warband" }
local function PostCandidate(item)
    local s = item.suggestion
    local unit = Util.AfterCut(s.price)
    local sold, first = ExpectedSold(item.count, s.salesPerDay)
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
        price = s.price, full = item.value, gold = gold, sold = sold, first = first,
        slow = first ~= nil and first < FAST_ENOUGH or nil,
        seconds = COST.POST + (fromBank and COST.WITHDRAW or 0),
        ah = true, bank = fromBank or nil, suggestion = s, fast = Fast(item.key, s.salesPerDay),
    }
end

-- A posting candidate into the plan, or onto the slow list (one row per
-- item, counts from bags, bank and mail added up).
local function AddPost(result, candidates, item)
    local c = PostCandidate(item)
    if not c.slow then
        candidates[#candidates + 1] = c
        return
    end
    for _, slow in ipairs(result.slow) do
        if slow.key == c.key then
            slow.count = slow.count + c.count
            slow.value = slow.value + Util.AfterCut(c.price) * c.count
            return
        end
    end
    result.slow[#result.slow + 1] = {
        id = "SLOW:" .. c.key, kind = "SLOW", key = c.key, count = c.count, price = c.price,
        value = Util.AfterCut(c.price) * c.count, first = c.first, suggestion = c.suggestion,
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
    local hidden = HiddenItems()
    for _, entry in ipairs(ns.Auctions:List().items) do
      if not hidden[entry.key] then
        local s = entry.suggestion
        local sold, first = ExpectedSold(entry.quantity, s.salesPerDay)
        if entry.action == "REPOST" and first and first < FAST_ENOUGH then
            -- Slow: reposting costs a deposit for a sale that likely won't come.
        elseif entry.action == "REPOST" then
            local unit = Util.AfterCut(entry.newPrice)
            local gold = sold and unit * sold or unit * entry.quantity * UNKNOWN_SPEED_FACTOR
            list[#list + 1] = {
                id = "REPOST:" .. entry.key .. "@" .. entry.unit, kind = "REPOST", key = entry.key,
                count = entry.quantity, price = entry.newPrice, oldPrice = entry.unit, lowest = entry.lowest,
                gold = math.floor(gold * ns.Styles.Factor(s.contested)), sold = sold,
                seconds = COST.REPOST * entry.auctions, ah = true, suggestion = s,
                fast = Fast(entry.key, s.salesPerDay),
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
end

-- Chance one bought item resells before the player is back, counting
-- the copies already listed at that price (Deals.ResellChance).
local function ResellChance(deal)
    return ns.Deals.ResellChance(deal.salesPerDay, deal.listed)
end

-- Deals, one step per item name: several different items that share a
-- name and are all listed cheaply are one decision for the player.
local function BuyCandidates(list)
    local groups, order = {}, {}
    -- A deal whose resell price may be pushed up is never a plan step.
    local safe = {}
    -- A flip has to resell soon to be gold today, not gold stuck in the AH.
    local slow = 0
    for _, d in ipairs(ns.Deals:List().items) do
        if not d.shaky and not HiddenItems()[d.key] then
            if ResellChance(d) >= FAST_ENOUGH then safe[#safe + 1] = d else slow = slow + 1 end
        end
    end
    for _, d in ipairs(safe) do
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
            local c = ResellChance(d)
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
    return slow
end

-- An item in the bags worth more destroyed than sold, or nil: returns the
-- Destroy:Value result and what selling one makes (AH after cut, or vendor).
local function DestroyInstead(item)
    local d = ns.Destroy and ns.Destroy:Value(item.key, item.link)
    if not d or not DESTROY_KINDS[d.kind] or not ns.Compat.CanDestroy(d.kind) then return nil end
    local s = item.suggestion
    local sellEach = (s.action == "POST" or s.action == "HOLD") and s.price and Util.AfterCut(s.price) or (s.vendor or 0)
    if d.value <= sellEach * DESTROY_MARGIN then return nil end
    return d, sellEach
end

-- Destroy candidates: one step per kind from the grouped items.
local function DestroyCandidates(groups, list)
    for kind, g in pairs(groups) do
        local casts = kind == "DE" and g.units or math.ceil(g.units / 5)
        list[#list + 1] = {
            id = "DESTROY:" .. kind, kind = "DESTROY", destroyKind = kind, key = g.items[1].key,
            count = #g.items, units = g.units, items = g.items, value = g.value, gain = g.gain,
            gold = math.floor(g.value * DESTROY_FACTOR), seconds = COST.DESTROY + COST.DESTROY_CAST * casts,
        }
    end
end

-- Materials this character can craft with: bags, bank, reagent bank and
-- the warband bank, as { [key] = count }.
local function CraftingMaterials()
    local have = {}
    local char = ns.db.characters[ns.charKey]
    local inv = char and char.inventory or {}
    for _, list in ipairs({ inv.bags or {}, inv.bank or {}, inv.reagentBank or {}, ns.db.warbank or {} }) do
        for key, count in pairs(list) do have[key] = (have[key] or 0) + count end
    end
    return have
end

-- Whether a character's own items are left out of the plan.
function Plan:CharacterLeftOut(charKey)
    local skip = ns.db.settings.planSkipChars
    return skip ~= nil and skip[charKey or ns.charKey] == true
end

function Plan:Hide(key)
    if not key then return end
    ns.db.settings.planHidden = ns.db.settings.planHidden or {}
    ns.db.settings.planHidden[key] = true
end

function Plan:HiddenCount()
    local n = 0
    for _ in pairs(HiddenItems()) do n = n + 1 end
    return n
end

function Plan:ShowHidden()
    ns.db.settings.planHidden = {}
end

-- Craft candidates for this character, and the materials they use
-- ({ [key] = count }), which then aren't posted.
function Plan.CraftCandidates(list)
    local reserved = {}
    if not ns.Crafting or not ns.db.recipes or not ns.db.recipes[ns.charKey] then return reserved end
    if Plan:CharacterLeftOut() then return reserved end
    local hidden = HiddenItems()
    local left = CraftingMaterials()
    local steps = 0
    for _, e in ipairs(ns.Crafting:ForCharacter(ns.charKey)) do
        if steps >= MAX_CRAFT_STEPS then break end
        if not hidden[e.key] and e.profit >= math.max(CRAFT_MIN_PROFIT, e.cost * CRAFT_MARGIN) then
            local crafts = ns.Crafting.Possible(e.recipe, left)
            local made = e.recipe.q or 1
            local wanted, first = ExpectedSold(math.huge, e.salesPerDay)
            -- Crafting something that won't sell today only turns
            -- materials that sell into an item that sits.
            if first and first < FAST_ENOUGH then crafts = 0 end
            if crafts > 0 then
                if wanted then
                    crafts = math.min(crafts, math.max(1, math.floor(wanted / made)))
                else
                    crafts = math.min(crafts, UNKNOWN_CRAFTS)
                end
                local uses = ns.Crafting.Uses(e.recipe, crafts, left)
                for key, count in pairs(uses) do
                    left[key] = left[key] - count
                    reserved[key] = (reserved[key] or 0) + count
                end
                local total = crafts * made
                local sold = ExpectedSold(total, e.salesPerDay)
                local each = e.value / made
                steps = steps + 1
                list[#list + 1] = {
                    id = "CRAFT:" .. tostring(e.recipeID), kind = "CRAFT", key = e.key, recipeID = e.recipeID,
                    count = crafts, made = total, sold = sold, craft = e,
                    gain = e.profit * crafts, value = e.value * crafts,
                    gold = math.floor(each * (sold or total * UNKNOWN_SPEED_FACTOR)),
                    seconds = COST.CRAFT + COST.CRAFT_EACH * crafts, ah = true,
                    fast = Fast(e.key, e.salesPerDay),
                }
            end
        end
    end
    return reserved
end

-- What's left of an item once crafting has taken its share: a copy with
-- the smaller count, or nil when it's all used.
local function AfterCrafting(item, reserved)
    local take = reserved[item.key]
    if not take or take <= 0 then return item end
    local used = math.min(take, item.count)
    reserved[item.key] = take - used
    if used >= item.count then return nil end
    local copy = {}
    for k, v in pairs(item) do copy[k] = v end
    copy.count = item.count - used
    copy.value = item.value and math.floor(item.value * copy.count / item.count) or nil
    return copy
end

-- Shopping list items to buy now, pinned: { step, ... } that fit the gold.
local function ShopSteps(money)
    local steps, spend = {}, 0
    if not ns.Shopping then return steps, 0 end
    for _, item in ipairs(ns.Shopping:Items()) do
        if item.status == "BUY" and (not money or spend + item.lowest <= money) then
            spend = spend + item.lowest
            steps[#steps + 1] = {
                id = "SHOP:" .. item.key, kind = "SHOP", key = item.key, price = item.lowest, max = item.max,
                spend = item.lowest, seconds = COST.SHOP, ah = true,
            }
        end
    end
    return steps, spend
end

-- Item IDs any of your characters can craft (recipes seen in their
-- profession windows, every quality).
local function Craftable()
    local ids = {}
    for _, recipes in pairs(ns.db.recipes or {}) do
        for _, recipe in pairs(recipes) do
            if recipe.o then ids[recipe.o] = true end
            for _, itemID in pairs(recipe.qo or {}) do ids[itemID] = true end
        end
    end
    return ids
end

-- Pure: the best fast sellers from Data.lua rows, by gold a day after the
-- cut. rows: { [key] = row } per source, commodity: whether they're
-- region-wide. Returns { { key, salesPerDay, price, perDay, commodity }, ... }.
function Plan.RankFast(sources, limit, afterCut, skip)
    local found = {}
    for _, source in ipairs(sources) do
        for key, row in pairs(source.rows or {}) do
            local price = row.m or row.n
            if price and price > 0 and Plan.IsFast(row.s, source.commodity) and not (skip and skip[key]) then
                found[#found + 1] = { key = key, salesPerDay = row.s, price = price,
                                      perDay = afterCut(price) * row.s, commodity = source.commodity }
            end
        end
    end
    table.sort(found, function(a, b)
        if a.perDay ~= b.perDay then return a.perDay > b.perDay end
        return a.key < b.key
    end)
    for i = #found, limit + 1, -1 do found[i] = nil end
    return found
end

-- "Sells fast here": FAST steps (shown, never counted), cached per price
-- data and realm, since a realm has thousands of rows.
local fastCache = {}
function Plan:FastSellers()
    local data = ns.Prices.ActiveData()
    if not data then return {} end
    local realm = GetNormalizedRealmName()
    local realmID = data.realmIndex and data.realmIndex[realm]
    local stamp = tostring(data.generatedAt) .. ":" .. tostring(realmID)
    if fastCache.stamp ~= stamp then
        fastCache.stamp = stamp
        fastCache.list = Plan.RankFast({
            { rows = realmID and data.realms and data.realms[realmID], commodity = false },
            { rows = data.commodities, commodity = true },
        }, MAX_FAST_LIST * 3, Util.AfterCut)
    end
    local hidden, craftable, steps = HiddenItems(), Craftable(), {}
    for _, f in ipairs(fastCache.list) do
        if #steps >= MAX_FAST_LIST then break end
        if not hidden[f.key] then
            local itemID = Util.ItemIDFromKey(f.key)
            steps[#steps + 1] = {
                id = "FAST:" .. f.key, kind = "FAST", key = f.key, price = f.price, salesPerDay = f.salesPerDay,
                perDay = f.perDay, commodity = f.commodity, craftable = itemID and craftable[itemID] or nil,
            }
        end
    end
    return steps
end

-- Returns {
--   steps        picked steps, best gold per minute first
--   gold         expected gold from all steps
--   seconds      rough time they take
--   budget       minutes asked for
--   skips        up to MAX_SKIPS { kind = "SKIP", key, count, suggestion } to leave alone
--   slow         up to MAX_SLOW { kind = "SLOW", key, count, price, value, first }:
--                worth posting, unlikely to sell before the player is back
--   slowDeals    deals left out because they wouldn't resell in time
--   left         steps that did not fit in the time
--   unaffordable buys left out because they cost more than the gold on hand
--   money        gold on this character
--   elsewhere    { { owner, value }, ... } sellable value on other
--                characters, most first
--   hasSpeed     true when sales rates (desktop app data) were available
--   hidden       how many items the player hid from the plan
--   leftOut      true when this character's own items are left out
--   fast         up to MAX_FAST_LIST { kind = "FAST", key, price, salesPerDay,
--                perDay, craftable }: what sells fast here (Plan:FastSellers)
-- }
function Plan:Build(minutes)
    local result = { steps = {}, gold = 0, seconds = 0, skips = {}, slow = {}, slowDeals = 0, left = 0,
        unaffordable = 0, elsewhere = {}, fast = {} }
    if not ns.db or not ns.charKey then
        result.budget = minutes or 15
        return result
    end
    minutes = minutes or ns.db.settings.planMinutes or 15
    result.budget = minutes

    local candidates = {}
    local vendorGold, vendorItems = 0, 0
    local destroyGroups = {}
    local hidden = HiddenItems()
    local leftOut = Plan:CharacterLeftOut()
    result.leftOut = leftOut
    result.hidden = Plan:HiddenCount()
    -- Crafts first: the materials they use aren't posted as well.
    local reserved = Plan.CraftCandidates(candidates)
    for _, listed in ipairs(leftOut and {} or ns.Sell:List().items) do
      local item = not hidden[listed.key] and AfterCrafting(listed, reserved)
      if item then
        local s = item.suggestion
        if s.salesPerDay then result.hasSpeed = true end
        local d, sellEach = DestroyInstead(item)
        if d then
            local g = destroyGroups[d.kind]
            if not g then
                g = { items = {}, units = 0, value = 0, gain = 0 }
                destroyGroups[d.kind] = g
            end
            g.items[#g.items + 1] = { key = item.key, count = item.count }
            g.units = g.units + item.count
            g.value = g.value + d.value * item.count
            g.gain = g.gain + (d.value - sellEach) * item.count
        elseif (s.action == "POST" and s.contested == "HEAVY") or s.action == "HOLD" then
            if #result.skips < MAX_SKIPS then
                result.skips[#result.skips + 1] = {
                    id = "SKIP:" .. item.key, kind = "SKIP", key = item.key, count = item.count, suggestion = s,
                }
            end
        elseif s.action == "POST" then
            AddPost(result, candidates, item)
        elseif s.action == "VENDOR" and s.vendor and s.vendor > 0 then
            vendorGold = vendorGold + s.vendor * item.count
            vendorItems = vendorItems + 1
        end
      end
    end
    -- Bank items worth posting. Crashed or contested ones are left out
    -- quietly: the "leave alone" list is about what is in the bags.
    for _, listed in ipairs(BankItems()) do
        local item = not hidden[listed.key] and not (leftOut and listed.from == "bank")
            and AfterCrafting(listed, reserved)
        local s = item and item.suggestion
        if s and s.salesPerDay then result.hasSpeed = true end
        if s and s.action == "POST" and s.contested ~= "HEAVY" then
            AddPost(result, candidates, item)
        end
    end
    -- Mail items worth posting. The pinned MAIL step collects them, so
    -- they need no extra walk.
    local mailStep = MailStep()
    if mailStep then
        for _, item in ipairs(leftOut and {} or MailItems()) do
          if not hidden[item.key] then
            local s = item.suggestion
            if s.salesPerDay then result.hasSpeed = true end
            if s.action == "POST" and s.contested ~= "HEAVY" then
                AddPost(result, candidates, item)
            end
          end
        end
    end
    if vendorItems > 0 then
        candidates[#candidates + 1] = {
            id = "VENDOR", kind = "VENDOR", count = vendorItems, gold = vendorGold, seconds = COST.VENDOR,
        }
    end
    AuctionCandidates(candidates)
    result.slowDeals = BuyCandidates(candidates)
    -- Most valuable slow sellers first, a few of them.
    table.sort(result.slow, function(a, b)
        if a.value ~= b.value then return a.value > b.value end
        return a.key < b.key
    end)
    for i = #result.slow, MAX_SLOW + 1, -1 do result.slow[i] = nil end
    DestroyCandidates(destroyGroups, candidates)

    -- Mailbox gold is spendable once collected, so deals can use it.
    result.money = GetMoney() + (mailStep and mailStep.mailGold or 0)
    local budget = minutes * 60 - (mailStep and mailStep.seconds or 0)
    local setups = {}
    for place, seconds in pairs(SETUP) do
        if place ~= "mailbox" then setups[place] = seconds end
    end
    -- Shopping list buys come first after the mailbox: their time, the walk
    -- to the AH and their price are taken before anything is ranked.
    local shopSteps, shopSpend = ShopSteps(result.money)
    local pinnedSeconds = 0
    if #shopSteps > 0 then
        pinnedSeconds = SETUP.ah
        for _, step in ipairs(shopSteps) do pinnedSeconds = pinnedSeconds + step.seconds end
        setups.ah = nil
    end
    result.steps, result.gold, result.seconds, result.unaffordable =
        Plan.Select(candidates, math.max(0, budget - pinnedSeconds), setups, result.money - shopSpend)
    result.left = #candidates - #result.steps - result.unaffordable
    for i = #shopSteps, 1, -1 do table.insert(result.steps, 1, shopSteps[i]) end
    result.seconds = result.seconds + pinnedSeconds
    if mailStep then
        table.insert(result.steps, 1, mailStep)
        result.seconds = result.seconds + mailStep.seconds
    end

    for _, o in ipairs(ns.Treasure:Compute().owners) do
        if o.owner ~= ns.charKey and o.owner ~= "warband" and o.value > 0 and not Plan:CharacterLeftOut(o.owner) then
            result.elsewhere[#result.elsewhere + 1] = o
        end
    end
    result.fast = Plan:FastSellers()
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
