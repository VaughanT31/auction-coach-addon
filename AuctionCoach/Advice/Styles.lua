-- Auction Coach - seller styles: how often the player checks the AH.
--
--   casual  a few times a day
--   active  about every hour
--   camper  sits at the AH and reposts
--
-- An item is contested when other sellers undercut it faster than the
-- player comes back: the listing then spends most of its time behind
-- cheaper ones. Contested items are ranked lower on the Sell tab and the
-- advice says why. The chance to sell is shown for the time until the
-- player is likely back.

local _, ns = ...

local Styles = {}
ns.Styles = Styles

Styles.ORDER = { "casual", "active", "camper" }

local STYLES = {
    casual = { checkEvery = 8 * 3600, windowHours = 24 },
    active = { checkEvery = 3600, windowHours = 12 },
    camper = { checkEvery = 10 * 60, windowHours = 2 },
}

-- How much a contested item is worth to the player, for ranking.
local FACTOR = { NONE = 1, SOME = 0.7, HEAVY = 0.4 }
-- Undercut this many times between checks: HEAVY.
local HEAVY_RATIO = 4

function Styles:Current()
    local style = ns.db and ns.db.settings.sellerStyle
    return STYLES[style] and style or "casual"
end

function Styles:Get(style)
    return STYLES[style or self:Current()]
end

function Styles:WindowHours()
    return self:Get().windowHours
end

-- Seconds between undercuts: the player's own typical time if known,
-- otherwise from how often the lowest price changes. nil when unknown.
function Styles:UndercutEvery(competition, undercut)
    if undercut and undercut.seconds then return math.max(1, undercut.seconds) end
    if competition and competition.rate and competition.rate > 0 then
        return 3600 / competition.rate
    end
    return nil
end

-- Returns level ("NONE" | "SOME" | "HEAVY"), seconds between undercuts.
function Styles:Contested(competition, undercut)
    local every = self:UndercutEvery(competition, undercut)
    if not every then return "NONE", nil end
    local ratio = self:Get().checkEvery / every
    if ratio > HEAVY_RATIO then return "HEAVY", every end
    if ratio > 1 then return "SOME", every end
    return "NONE", every
end

function Styles.Factor(level)
    return FACTOR[level] or 1
end
