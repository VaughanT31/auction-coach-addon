-- Auction Coach - chance to sell at a given price.
--
-- Buyers take the cheapest listings first. Posting at a price puts the
-- listing behind every other seller's items at or below that price
-- ("ahead"). If buyers arrive at the item's usual rate (sales per day from
-- the server), the chance that the whole stack sells within a window is
-- the chance that at least ahead + quantity sales happen in it, which is a
-- Poisson tail. The listings ahead come from the live search Blizzard runs
-- when an item goes into the sell box (Scan/ItemCheck.lua), so they are
-- exact at posting time. New undercutters after posting are not counted,
-- so this is the chance if nobody undercuts.

local _, ns = ...
local Util = ns.Util

local SellChance = {}
ns.SellChance = SellChance

-- A live list of other sellers' listings older than this is not used.
local FRESH = 15 * 60
SellChance.WINDOW_HOURS = 24

-- Session only: item key -> { t = time, rows = { { unitPrice, quantity }, ... } }
local ladders = {}

-- Other sellers' listings of an item from a live search, any order.
function SellChance:SetLadder(key, rows, now)
    ladders[key] = { t = now or Util.Now(), rows = rows }
end

function SellChance:GetLadder(key)
    local ladder = ladders[key]
    if ladder and Util.Now() - ladder.t <= FRESH then return ladder.rows end
    return nil
end

-- Normal distribution CDF (Abramowitz and Stegun 7.1.26, error < 1.5e-7).
local function NormalCdf(z)
    local x = math.abs(z) / math.sqrt(2)
    local t = 1 / (1 + 0.3275911 * x)
    local erf = 1 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t
        + 0.254829592) * t * math.exp(-x * x)
    return z >= 0 and (1 + erf) / 2 or (1 - erf) / 2
end

-- Chance of at least k events when lambda are expected.
function SellChance.AtLeast(k, lambda)
    if k <= 0 then return 1 end
    if lambda <= 0 then return 0 end
    if lambda > 100 then
        return 1 - NormalCdf((k - 0.5 - lambda) / math.sqrt(lambda))
    end
    if k > lambda + 12 * math.sqrt(lambda) + 30 then return 0 end
    local term = math.exp(-lambda)
    local below = term
    for i = 1, k - 1 do
        term = term * lambda / i
        below = below + term
    end
    return math.max(0, math.min(1, 1 - below))
end

-- Items other sellers have at or below this price.
local function Ahead(rows, price)
    local ahead = 0
    for _, row in ipairs(rows) do
        if row[1] <= price then ahead = ahead + row[2] end
    end
    return ahead
end

-- Chance that quantity items posted at price all sell within the window,
-- or nil without a live listing list or a sales rate.
function SellChance:Chance(key, price, quantity, salesPerDay)
    local rows = self:GetLadder(key)
    if not rows or not salesPerDay or salesPerDay <= 0 or not price then return nil end
    local expected = salesPerDay * self.WINDOW_HOURS / 24
    return SellChance.AtLeast(Ahead(rows, price) + math.max(1, quantity or 1), expected)
end

local SILVER = 100

local function DownToSilver(copper)
    if copper >= SILVER then return math.floor(copper / SILVER) * SILVER end
    return copper
end

-- Up to three prices to compare, from Rules:SuggestPrice's result:
-- the suggested price, just under the next seller up, and the usual price.
-- Returns { { price, chance, label = "SUGGESTED" | "NEXT" | "USUAL" }, ... }
-- or nil when there is nothing to estimate.
function SellChance:Options(key, suggestion, quantity)
    if not suggestion or not suggestion.price then return nil end
    local rows = self:GetLadder(key)
    local rate = suggestion.salesPerDay
    if not rows or not rate or rate <= 0 then return nil end

    local options = {}
    local function Add(price, label)
        if not price or price <= 0 then return end
        for _, o in ipairs(options) do
            -- Skip prices within 2% of one already shown.
            if math.abs(o.price - price) <= o.price * 0.02 then return end
        end
        options[#options + 1] = { price = price, label = label, chance = self:Chance(key, price, quantity, rate) }
    end

    Add(suggestion.price, "SUGGESTED")

    -- The cheapest price clearly above the lowest: undercut that seller instead.
    local lowest = suggestion.lowest or suggestion.price
    local nextPrice
    for _, row in ipairs(rows) do
        if row[1] > lowest * 1.02 and (not nextPrice or row[1] < nextPrice) then nextPrice = row[1] end
    end
    if nextPrice then
        -- Round to silver like other suggestions, unless that would drop
        -- it to the lowest seller's price (cheap items).
        local under = DownToSilver(nextPrice - 1)
        if under <= lowest then under = nextPrice - 1 end
        Add(under, "NEXT")
    end

    if suggestion.usual and suggestion.usual > suggestion.price then
        Add(DownToSilver(suggestion.usual), "USUAL")
    end

    table.sort(options, function(a, b) return a.price < b.price end)
    return options
end
