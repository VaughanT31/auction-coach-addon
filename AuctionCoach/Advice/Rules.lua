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
