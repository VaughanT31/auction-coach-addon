-- Auction Coach - how old the server prices are.
--
-- An addon cannot talk to the desktop app: the app writes Data.lua and WoW
-- reads it at login or /reload. So the only sign the app has stopped (closed,
-- crashed, PC changed) is prices that stop getting newer. This warns once per
-- session when they are old, and when the app's file is for another region.
-- Players without the app or an imported string are never warned: their
-- prices come from their own scans.

local _, ns = ...
local L, Util = ns.L, ns.Util

local Freshness = {}
ns.Freshness = Freshness

-- The desktop app updates hourly, so 6 hours means it is not running.
local STALE_AFTER = 6 * 3600
local CHECK_DELAY = 8   -- seconds after login, so the line is not lost in the login spam

-- { at = unix time, source = "app" | "import", old = bool } or nil when
-- there are no server prices (own scans only).
function Freshness:Info()
    local data = ns.Prices.ActiveData()
    if not data or not data.generatedAt then return nil end
    return {
        at = data.generatedAt,
        source = data == AuctionCoachData and "app" or "import",
        old = Util.Now() - data.generatedAt > STALE_AFTER,
    }
end

-- The region of a Data.lua the addon ignored because it is for another
-- region, or nil.
function Freshness:OtherRegion()
    local data = AuctionCoachData
    local mine = ns.Compat.RegionCode()
    if type(data) ~= "table" or not data.region or mine == "" then return nil end
    local theirs = tostring(data.region):upper()
    return theirs ~= mine and theirs or nil
end

-- One line for the main window.
function Freshness:StatusText()
    local info = self:Info()
    if not info then return L.STATUS_PRICES_SCANS, false end
    local text = info.source == "app" and L.STATUS_PRICES_APP or L.STATUS_PRICES_IMPORT
    return text:format(Util.FormatAge(info.at)), info.old
end

function Freshness:Check()
    if not ns.db or not ns.db.settings.staleWarning then return end
    local other = self:OtherRegion()
    if other then
        Util.Print(L.PRICES_WRONG_REGION:format(other, ns.Compat.RegionCode()))
        return
    end
    local info = self:Info()
    if not info or not info.old then return end
    local line = info.source == "app" and L.PRICES_OLD_APP or L.PRICES_OLD_IMPORT
    Util.Print(line:format(Util.FormatAge(info.at)))
end

ns.Events:On("AC_LOGIN", function()
    C_Timer.After(CHECK_DELAY, function() Freshness:Check() end)
end)
