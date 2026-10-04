-- Auction Coach - advice rules.
-- Turns prices, inventory and competition into a short list of advice
-- lines. Deterministic and offline: the same data always gives the same
-- advice.

local _, ns = ...
local Util, Compat, Phrases = ns.Util, ns.Compat, ns.Phrases

local Rules = {}
ns.Rules = Rules

local STALE_AFTER = 3 * 86400

local BIND_ON_PICKUP = 1
local BIND_QUEST = 4

Rules.COLORS = {
    info = { 1, 1, 1 },
    good = { 0.4, 1, 0.4 },
    warn = { 1, 0.65, 0.2 },
    bad = { 1, 0.3, 0.3 },
    muted = { 0.6, 0.6, 0.6 },
}

local COMPETITION_COLORS = {
    LOW = "good",
    MEDIUM = "info",
    HIGH = "warn",
    EXTREME = "bad",
}

-- Returns ahAfterCut, vendorPrice (per item) when the AH pays clearly more
-- than a vendor, otherwise nil. Used by vendor/delete protection and the
-- hidden treasure total.
function Rules:AuctionBeatsVendor(key, link, groupKey, realmName)
    local price = ns.Prices:Get(key, groupKey, realmName)
    if not price or not price.value then return nil end
    local afterCut = Util.AfterCut(price.value)
    local vendor = Compat.GetVendorPrice(link or Util.ItemIDFromKey(key))
    if afterCut > vendor then
        return afterCut, vendor
    end
    return nil
end

-- Like AuctionBeatsVendor, but only when the difference is big enough to
-- interrupt the player over (settings.guardMinGain, and at least double).
function Rules:IsWorthWarning(key, link)
    local afterCut, vendor = self:AuctionBeatsVendor(key, link)
    if not afterCut then return nil end
    if afterCut - vendor >= ns.db.settings.guardMinGain and afterCut >= vendor * 2 then
        return afterCut, vendor
    end
    return nil
end

-- ---------------------------------------------------------------------
-- Selling
-- ---------------------------------------------------------------------

local SILVER = 100
-- Lowest listing this far below the usual price means the market crashed.
local CRASHED_BELOW = 0.8

-- The AH only takes prices in whole silver.
local function DownToSilver(copper)
    return math.floor(copper / SILVER) * SILVER
end

local function UpToSilver(copper)
    return math.ceil(copper / SILVER) * SILVER
end

-- What to do with an item and at what price. Returns {
--   action       "POST" | "HOLD" (market crashed, posting now loses gold)
--                | "VENDOR" (a vendor pays more) | "NO_DATA"
--   price        suggested price per item, whole silver (nil for VENDOR/NO_DATA)
--   lowest       lowest listing per item, and lowestAt when it was seen
--   usual        14-day average (Data.lua), else the market value
--   vendor       vendor price per item
--   salesPerDay  estimated sales per day, when known
--   competition  Competition:Score result, when known
-- }
function Rules:SuggestPrice(key, link)
    local vendor = Compat.GetVendorPrice(link or Util.ItemIDFromKey(key))
    local price = ns.Prices:Get(key)
    if not price or not (price.min or price.value) then
        return { action = "NO_DATA", vendor = vendor }
    end

    local lowest = price.min or price.value
    local result = {
        lowest = lowest,
        lowestAt = price.minAt,
        usual = price.historical or price.value,
        vendor = vendor,
        salesPerDay = price.salesPerDay,
        competition = ns.Competition:Score(key),
    }

    -- Just under the lowest listing. Buyers take the cheapest first, so
    -- matching it means waiting behind everyone else at that price.
    local suggest = DownToSilver(lowest - 1)
    if suggest < SILVER then suggest = math.max(SILVER, lowest) end

    -- Below this, a vendor pays more than the AH after its cut.
    local floor = vendor > 0 and UpToSilver(math.ceil(vendor / (1 - Util.AH_CUT))) or 0
    if vendor > 0 and suggest <= floor then
        result.action = "VENDOR"
        return result
    end

    result.price = suggest
    if result.usual and lowest < result.usual * CRASHED_BELOW then
        result.action = "HOLD"
    else
        result.action = "POST"
    end
    return result
end

-- Advice lines for an item link: { { text = "...", color = "info" }, ... },
-- or nil when there is nothing useful to say (for example soulbound items).
function Rules:ForLink(link)
    local key = Util.ItemKeyFromLink(link)
    if not key then return nil end

    local bindType = Compat.GetBindType(link)
    if bindType == BIND_ON_PICKUP or bindType == BIND_QUEST then
        return nil
    end

    local lines = {}
    local function Add(text, color)
        lines[#lines + 1] = { text = text, color = color or "info" }
    end

    local price = ns.Prices:Get(key)
    if not price or not price.value then
        Add(Phrases.NoPrice(), "muted")
        return lines
    end

    Add(Phrases.Worth(price))
    if Util.Now() - (price.t or 0) > STALE_AFTER then
        Add(Phrases.Stale(price), "warn")
    end

    local afterCut = Util.AfterCut(price.value)
    local count = ns.Inventory:GetCount(key)
    if count > 0 then
        Add(Phrases.YouHave(count, afterCut * count))
    end

    local vendor = Compat.GetVendorPrice(link)
    if vendor > 0 and afterCut <= vendor then
        Add(Phrases.VendorBetter(vendor), "warn")
    elseif vendor > 0 and Compat.IsMerchantOpen() and self:IsWorthWarning(key, link) then
        Add(Phrases.DontVendor(vendor), "bad")
    end

    local score = ns.Competition:Score(key)
    if score then
        Add(Phrases.Competition(score), COMPETITION_COLORS[score.level])
    end

    return lines
end
