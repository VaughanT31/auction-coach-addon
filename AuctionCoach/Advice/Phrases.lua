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
