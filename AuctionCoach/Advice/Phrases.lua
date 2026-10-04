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
    if s.lowestAt and Util.Now() - s.lowestAt > 2 * 3600 then
        lines[#lines + 1] = L.SELL_CHECK_LIVE:format(Util.FormatAge(s.lowestAt))
    end
    return lines
end

-- One or two words for the Sell tab's advice column.
function Phrases.SellShort(s)
    return L["SELL_SHORT_" .. s.action]
end
