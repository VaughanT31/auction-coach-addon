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

-- ---------------------------------------------------------------------
-- Craft or sell (Advice/Crafting.lua)
-- ---------------------------------------------------------------------

local function SignedMoney(copper, money)
    money = money or Util.FormatMoney
    return copper < 0 and ("-" .. money(-copper)) or money(copper)
end
Phrases.SignedMoney = SignedMoney

-- Tooltip line on a crafted item.
function Phrases.CraftTooltip(c)
    local who = Util.ShortName(c.char)
    if c.profit > 0 then
        return L.CRAFT_TT_PROFIT:format(who, Util.FormatMoney(c.cost), Util.FormatMoney(c.profit))
    end
    return L.CRAFT_TT_LOSS:format(who, Util.FormatMoney(c.cost), Util.FormatMoney(c.value))
end

-- Why, for the Deals tab's craft view.
function Phrases.Craft(c, money)
    money = money or Util.FormatMoney
    local lines = {
        L.CRAFT_WHO:format(Util.ShortName(c.char), c.profession or "?"),
        L.CRAFT_COST:format(money(c.cost)),
        L.CRAFT_VALUE:format(money(c.value)),
    }
    if c.profit > 0 then
        lines[#lines + 1] = L.CRAFT_VERDICT_CRAFT:format(money(c.profit))
    else
        lines[#lines + 1] = L.CRAFT_VERDICT_SELL:format(money(-c.profit))
    end
    if c.salesPerDay then
        lines[#lines + 1] = c.salesPerDay < 1 and L.SELL_SPEED_SLOW
            or L.SELL_SPEED:format(BreakUpLargeNumbers(math.floor(c.salesPerDay + 0.5)))
    end
    lines[#lines + 1] = L.CRAFT_NOTE
    return lines
end

-- ---------------------------------------------------------------------
-- Market calendar (Advice/Calendar.lua)
-- ---------------------------------------------------------------------

local function Percent(p)
    return math.floor(math.abs(p) + 0.5)
end

local function Effect(p)
    return (p >= 0 and L.CAL_ABOVE or L.CAL_BELOW):format(Percent(p))
end

-- "Today (Wednesday) consumables usually sell 3% above their weekly
-- average, trade goods 2% below."
function Phrases.CalendarToday(weekday, groups)
    local parts = {}
    for i, g in ipairs(groups) do
        local name = L["CAL_GROUP_" .. g.group:upper()]
        parts[#parts + 1] = (i == 1) and L.CAL_FIRST:format(name:lower(), Effect(g.percent))
            or L.CAL_NEXT:format(name:lower(), Effect(g.percent))
    end
    return L.CAL_TODAY:format(L["WEEKDAY_" .. weekday], table.concat(parts, ", "))
end

function Phrases.CalendarFaire(groups)
    local parts = {}
    for _, g in ipairs(groups) do
        parts[#parts + 1] = L.CAL_FAIRE_PART:format(L["CAL_GROUP_" .. g.group:upper()]:lower(),
            (g.percent >= 0 and L.CAL_HIGHER or L.CAL_LOWER):format(Percent(g.percent)))
    end
    return L.CAL_FAIRE:format(table.concat(parts, ", "))
end

-- One line for the sell advice: the usual best day, or that it's today.
function Phrases.CalendarItem(c)
    local name = L["CAL_GROUP_" .. c.group:upper()]
    local text
    if c.bestToday then
        text = L.CAL_ITEM_TODAY:format(name:lower(), Percent(c.bestPercent))
    else
        text = L.CAL_ITEM_BEST:format(name, L["WEEKDAY_" .. c.best], Percent(c.bestPercent), Effect(c.today))
    end
    if c.faire then
        text = text .. " " .. L.CAL_ITEM_FAIRE:format((c.faire >= 0 and L.CAL_HIGHER or L.CAL_LOWER):format(Percent(c.faire)))
    end
    return text
end

-- Rules.Pushed result: the lowest listing is far above its usual.
function Phrases.Pushed(p, money)
    money = money or Util.FormatMoney
    return L.TT_PUSHED:format(Util.FormatRatio(p.ratio), money(p.usual))
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

-- Grey items: vendor trash, whatever the AH says (Rules:IsJunk).
function Phrases.Junk(vendor, money)
    money = money or Util.FormatMoney
    if vendor and vendor > 0 then
        return L.JUNK_VENDOR:format(money(vendor))
    end
    return L.JUNK
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
    if s.junk then
        lines[1] = Phrases.Junk(s.vendor, money)
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
    if s.pushed then
        lines[#lines + 1] = L.SELL_PUSHED:format(Util.FormatRatio(s.pushed.ratio), money(s.pushed.usual))
    end
    if s.calendar then
        lines[#lines + 1] = Phrases.CalendarItem(s.calendar)
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
    if d.shaky then lines[#lines + 1] = L.DEAL_SHAKY end
    lines[#lines + 1] = L.DEAL_SEEN:format(Util.FormatAge(d.priceAt))
    lines[#lines + 1] = L.DEAL_CHECK
    return lines
end

-- ---------------------------------------------------------------------
-- Today's Plan
-- ---------------------------------------------------------------------

-- "3", "about 2.5" or "less than one" items.
local function Amount(n)
    if n < 1 then return L.PLAN_LESS_THAN_ONE end
    if math.abs(n - math.floor(n + 0.5)) < 0.05 then return BreakUpLargeNumbers(math.floor(n + 0.5)) end
    return L.PLAN_ABOUT:format(n)
end

-- Short reason for a plan row.
function Phrases.PlanShort(step, money)
    money = money or Util.FormatMoney
    local kind = step.kind
    if kind == "POST" then
        if step.from == "warband" then
            return L.PLAN_SHORT_POST_WARBAND:format(money(step.price))
        elseif step.from == "mail" then
            return L.PLAN_SHORT_POST_MAIL:format(money(step.price))
        elseif step.from == "bank" then
            return L.PLAN_SHORT_POST_BANK:format(money(step.price))
        elseif step.suggestion.contested == "SOME" then
            return L.PLAN_SHORT_POST_CONTESTED:format(money(step.price))
        end
        return L.PLAN_SHORT_POST:format(money(step.price))
    elseif kind == "REPOST" then
        return L.PLAN_SHORT_REPOST:format(money(step.price))
    elseif kind == "CANCEL" then
        return L.PLAN_SHORT_CANCEL:format(money(step.gold))
    elseif kind == "MAIL" then
        if step.mailGold and step.mailGold > 0 then
            return L.PLAN_SHORT_MAIL_GOLD:format(money(step.mailGold))
        end
        return L.PLAN_SHORT_MAIL
    elseif kind == "BUY" then
        return L.PLAN_SHORT_BUY:format(money(step.price), money(step.resell))
    elseif kind == "VENDOR" then
        return L.PLAN_SHORT_VENDOR
    elseif kind == "SHOP" then
        return L.PLAN_SHORT_SHOP:format(money(step.price), money(step.max))
    elseif kind == "DESTROY" then
        return L.PLAN_SHORT_DESTROY:format(money(step.gain))
    elseif kind == "SKIP" then
        local s = step.suggestion
        if s.action == "HOLD" then
            return L.PLAN_SHORT_HOLD:format(math.floor((1 - s.lowest / s.usual) * 100 + 0.5))
        end
        return L.PLAN_SHORT_CONTESTED
    end
    return ""
end

-- Tooltip lines explaining a plan row.
function Phrases.PlanDetails(step, money)
    money = money or Util.FormatMoney
    local lines = {}
    local kind = step.kind
    if kind == "POST" then
        if step.from == "warband" then
            lines[#lines + 1] = L.PLAN_WHY_WARBAND
        elseif step.from == "bank" then
            lines[#lines + 1] = L.PLAN_WHY_BANK
        elseif step.from == "mail" then
            lines[#lines + 1] = L.PLAN_WHY_MAIL_ITEM
        end
        lines[#lines + 1] = L.SELL_POST:format(money(step.price), money(step.suggestion.lowest))
        if step.sold then
            lines[#lines + 1] = L.PLAN_WHY_SOLD:format(Amount(step.sold), BreakUpLargeNumbers(step.count),
                ns.Styles:WindowHours(), money(step.gold))
        else
            lines[#lines + 1] = L.PLAN_WHY_UNKNOWN:format(money(step.full))
        end
        lines[#lines + 1] = Phrases.Contested(step.suggestion)
    elseif kind == "REPOST" then
        lines[#lines + 1] = L.PLAN_WHY_REPOST:format(money(step.oldPrice), money(step.lowest), money(step.price))
        lines[#lines + 1] = L.PLAN_WHY_DEPOSIT
        if step.sold then
            lines[#lines + 1] = L.PLAN_WHY_SOLD:format(Amount(step.sold), BreakUpLargeNumbers(step.count),
                ns.Styles:WindowHours(), money(step.gold))
        end
    elseif kind == "CANCEL" then
        lines[#lines + 1] = L.PLAN_WHY_CANCEL:format(money(step.oldPrice), money(step.vendor), money(step.gold))
        lines[#lines + 1] = L.PLAN_WHY_DEPOSIT_CANCEL
    elseif kind == "MAIL" then
        lines[#lines + 1] = L.PLAN_WHY_MAIL
        if step.mailGold and step.mailGold > 0 then
            lines[#lines + 1] = L.PLAN_WHY_MAIL_GOLD:format(money(step.mailGold))
        end
    elseif kind == "BUY" then
        if step.count > 1 then
            lines[#lines + 1] = L.PLAN_WHY_BUY_SAME_NAME:format(step.count, money(step.spend))
        end
        for _, line in ipairs(Phrases.Deal(step.deal, money)) do lines[#lines + 1] = line end
        lines[#lines + 1] = L.PLAN_WHY_BUY:format(money(step.gold), math.floor(step.chance * 100 + 0.5),
            ns.Styles:WindowHours())
    elseif kind == "VENDOR" then
        lines[#lines + 1] = L.PLAN_WHY_VENDOR:format(step.count, money(step.gold))
    elseif kind == "SHOP" then
        lines[#lines + 1] = L.PLAN_WHY_SHOP:format(money(step.price), money(step.max))
    elseif kind == "DESTROY" then
        lines[#lines + 1] = L["PLAN_WHY_DESTROY_" .. step.destroyKind]:format(money(step.gain), money(step.value))
        local names = {}
        for i, item in ipairs(step.items) do
            if i > 6 then
                names[#names + 1] = L.PLAN_DESTROY_MORE:format(#step.items - 6)
                break
            end
            local link = Util.NamedLink(item.key)
            names[#names + 1] = (link or item.key) .. (item.count > 1 and (" x" .. item.count) or "")
        end
        lines[#lines + 1] = table.concat(names, ", ")
        lines[#lines + 1] = L.PLAN_WHY_DESTROY_COUNTED:format(money(step.gold))
    elseif kind == "SKIP" then
        for _, line in ipairs(Phrases.Sell(step.suggestion, money)) do lines[#lines + 1] = line end
    end
    if step.seconds then
        lines[#lines + 1] = L.PLAN_TAKES:format(Util.FormatDuration(step.seconds))
    end
    return lines
end

-- ---------------------------------------------------------------------
-- 0.7.0: destroy values, shopping list, cross-realm flips
-- ---------------------------------------------------------------------

-- Destroy:Value as a sentence. afterCut is what selling one makes, or nil
-- for items that can't be sold (soulbound gear).
function Phrases.Destroy(d, afterCut, money)
    money = money or Util.FormatMoney
    local text
    if d.players then
        text = L["DESTROY_SHARED_" .. d.kind]:format(money(d.value), d.players)
    else
        text = L["DESTROY_" .. d.kind]:format(money(d.value), d.used)
    end
    if afterCut and afterCut > 0 then
        if d.value > afterCut then
            text = text .. " " .. L.DESTROY_BETTER
        else
            text = text .. " " .. L.DESTROY_WORSE
        end
    end
    return text
end

-- Destroy:Progress as a sentence: still learning, no value yet.
function Phrases.DestroyProgress(p)
    return L["DESTROY_PROGRESS_" .. p.kind]:format(p.used, p.needed)
end

-- Tooltip line for an item on the shopping list.
function Phrases.ShopTooltip(max, price, money)
    money = money or Util.FormatMoney
    local status = ns.Shopping.Evaluate({ max = max }, price, Util.Now())
    if status == "BUY" then
        return L.SHOP_TT_BUY:format(money(price.min), money(max))
    end
    return L.SHOP_TT:format(money(max))
end

-- A shopping list row's tooltip.
function Phrases.Shop(item, money)
    money = money or Util.FormatMoney
    local lines = { L.SHOP_TT:format(money(item.max)) }
    if item.status == "BUY" then
        lines[#lines + 1] = L.SHOP_WHY_BUY:format(money(item.lowest), Util.FormatAge(item.lowestAt))
    elseif item.status == "WAIT" then
        lines[#lines + 1] = L.SHOP_WHY_WAIT:format(money(item.lowest))
    elseif item.status == "OLD" then
        lines[#lines + 1] = L.SHOP_WHY_OLD:format(money(item.lowest), Util.FormatAge(item.lowestAt))
    else
        lines[#lines + 1] = L.SHOP_WHY_UNKNOWN
    end
    return lines
end

-- Why a cross-realm flip is worth it, from Flips:List.
function Phrases.Flip(f, money)
    money = money or Util.FormatMoney
    return {
        L.FLIP_BUY:format(f.buyRealm, money(f.price), Util.FormatAge(f.priceAt)),
        L.FLIP_SELL:format(f.sellRealm, money(f.resell), money(f.profit)),
        L.SELL_SPEED:format(f.salesPerDay < 1 and "<1" or BreakUpLargeNumbers(math.floor(f.salesPerDay + 0.5))),
        L.FLIP_HOW,
        L.DEAL_CHECK,
    }
end
