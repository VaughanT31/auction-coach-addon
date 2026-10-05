-- Auction Coach - plain-English sentences built from advice data.
-- Rules decide what to say; this file decides how to say it.

local _, ns = ...
local L, Util = ns.L, ns.Util

local Phrases = {}
ns.Phrases = Phrases

function Phrases.Worth(price)
    if price.source == "data" then
        return L.TT_WORTH_DATA:format(Util.FormatMoney(price.value), Util.FormatAge(price.t))
    end
    return L.TT_WORTH_SCAN:format(Util.FormatMoney(price.value), Util.FormatAge(price.t))
end

function Phrases.YouHave(count, totalAfterCut)
    return L.TT_YOU_HAVE:format(BreakUpLargeNumbers(count), Util.FormatMoney(totalAfterCut))
end

function Phrases.Stale(price)
    return L.TT_STALE:format(Util.FormatAge(price.t))
end

function Phrases.VendorBetter(vendorPrice)
    return L.TT_VENDOR_BETTER:format(Util.FormatMoney(vendorPrice))
end

function Phrases.DontVendor(vendorPrice)
    return L.TT_DONT_VENDOR:format(Util.FormatMoney(vendorPrice))
end

function Phrases.Competition(score)
    local text
    if score.level == "HIGH" then
        text = L.TT_COMP_HIGH:format(math.floor(score.rate + 0.5))
    else
        text = L["TT_COMP_" .. score.level]
    end
    if score.sellers and score.sellers > 1 then
        text = text .. " " .. L.TT_SELLERS:format(score.sellers)
    end
    return text
end

-- "12 min", "an hour", "3 hours".
local function Span(seconds)
    if seconds < 3600 then
        return Util.FormatDuration(seconds)
    elseif seconds < 5400 then
        return L.UNDERCUT_HOUR
    end
    return L.UNDERCUT_HOURS:format(math.floor(seconds / 3600 + 0.5))
end

-- Undercuts:Typical result as a sentence.
function Phrases.Undercut(typical)
    if typical.shared then
        if typical.seconds < 60 then return L.UNDERCUT_SHARED_FAST:format(typical.posts) end
        return L.UNDERCUT_SHARED:format(Span(typical.seconds), typical.posts)
    end
    if typical.seconds < 60 then
        return L.UNDERCUT_FAST:format(typical.undercut, typical.posts)
    end
    return L.UNDERCUT_TYPICAL:format(Span(typical.seconds), typical.undercut, typical.posts)
end

-- Typical time to the first sale from shared posts, or nil.
function Phrases.SellTime(sellTime)
    if not sellTime then return nil end
    if sellTime.seconds < 60 then return L.SELLTIME_FAST:format(sellTime.count) end
    return L.SELLTIME:format(Span(sellTime.seconds), sellTime.count)
end

-- Why an item is contested for the player's seller style, or nil.
function Phrases.Contested(s)
    if not s.contested or s.contested == "NONE" or not s.undercutEvery then return nil end
    local text = s.contested == "HEAVY" and L.STYLE_HEAVY or L.STYLE_SOME
    return text:format(Span(s.undercutEvery), L["STYLE_WHO_" .. ns.Styles:Current():upper()])
end

-- SellChance:Options result as sentences, or nil.
function Phrases.SellChances(options, quantity, money)
    if not options or #options == 0 then return nil end
    money = money or Util.FormatMoney
    local hours = ns.Styles:WindowHours()
    local lines = {
        quantity > 1 and L.CHANCE_HEADER_MANY:format(quantity, hours) or L.CHANCE_HEADER_ONE:format(hours),
    }
    for _, o in ipairs(options) do
        local chance
        if o.chance >= 0.955 then
            chance = L.CHANCE_HIGH
        elseif o.chance < 0.045 then
            chance = L.CHANCE_LOW
        else
            chance = L.CHANCE_ABOUT:format(math.floor(o.chance * 20 + 0.5) * 5)
        end
        lines[#lines + 1] = L.CHANCE_LINE:format(money(o.price), L["CHANCE_" .. o.label], chance)
    end
    return lines
end

function Phrases.NoPrice()
    return L.TT_NO_PRICE
end

-- Selling advice from Rules:SuggestPrice, as a list of sentences.
-- money formats copper (plain text by default; the UI passes coin icons).
function Phrases.Sell(s, money)
    money = money or Util.FormatMoney
    local lines = {}
    if s.action == "NO_DATA" then
        lines[1] = L.SELL_NO_DATA
        return lines
    end
    if s.action == "VENDOR" then
        lines[1] = L.SELL_VENDOR:format(money(s.vendor))
        return lines
    end

    if s.action == "HOLD" then
        local percent = math.floor((1 - s.lowest / s.usual) * 100 + 0.5)
        lines[#lines + 1] = L.SELL_HOLD:format(percent, money(s.usual), money(s.price))
    else
        lines[#lines + 1] = L.SELL_POST:format(money(s.price), money(s.lowest))
        if s.usual and s.usual > 0 and math.abs(s.usual - s.lowest) / s.usual > 0.05 then
            lines[#lines + 1] = L.SELL_USUAL:format(money(s.usual))
        end
    end
    lines[#lines + 1] = Phrases.SellTime(s.sellTime)
    if s.salesPerDay then
        if s.salesPerDay < 1 then
            lines[#lines + 1] = L.SELL_SPEED_SLOW
        else
            lines[#lines + 1] = L.SELL_SPEED:format(BreakUpLargeNumbers(math.floor(s.salesPerDay + 0.5)))
        end
    end
    if s.competition then
        lines[#lines + 1] = Phrases.Competition(s.competition)
    end
    if s.undercut then
        lines[#lines + 1] = Phrases.Undercut(s.undercut)
    end
    if s.action == "POST" then
        lines[#lines + 1] = Phrases.Contested(s)
    end
    if s.lowestAt and Util.Now() - s.lowestAt > 2 * 3600 then
        lines[#lines + 1] = L.SELL_CHECK_LIVE:format(Util.FormatAge(s.lowestAt))
    end
    return lines
end

-- One or two words for the Sell tab's advice column.
function Phrases.SellShort(s)
    if s.action == "POST" and s.contested and s.contested ~= "NONE" then
        return L.SELL_SHORT_CONTESTED
    end
    return L["SELL_SHORT_" .. s.action]
end

-- Why a deal is a deal, from Deals:List, as a list of sentences.
function Phrases.Deal(d, money)
    money = money or Util.FormatMoney
    local lines = {
        L.DEAL_LISTED:format(money(d.price), math.floor(d.discount * 100 + 0.5), money(d.resell)),
        L.DEAL_PROFIT:format(money(d.resell), money(d.profit)),
    }
    lines[#lines + 1] = L.SELL_SPEED:format(BreakUpLargeNumbers(math.floor(d.salesPerDay + 0.5)))
    lines[#lines + 1] = L.DEAL_SEEN:format(Util.FormatAge(d.priceAt))
    lines[#lines + 1] = L.DEAL_CHECK
    return lines
end
