-- Auction Coach - what to sell from this character's bags, and for how much.

local _, ns = ...
local Util, Compat = ns.Util, ns.Compat

local Sell = {}
ns.Sell = Sell

local ORDER = { POST = 1, HOLD = 2, VENDOR = 3, NO_DATA = 4 }

-- Returns {
--   total = copper after cut for everything worth posting (POST and HOLD),
--   items = { { key, link, count, suggestion, value }, ... }
--           value = suggested price x count after the AH cut
-- } sorted best first: worth posting by value (lowered for items that are
-- contested for the player's seller style), then vendor, then unpriced.
function Sell:List()
    local result = { total = 0, items = {} }
    local char = ns.db and ns.db.characters[ns.charKey]
    if not char then return result end

    for key, count in pairs(char.inventory.bags) do
        local link = ns.db.links[key]
        local suggestion = ns.Rules:SuggestPrice(key, link)
        local value = suggestion.price and Util.AfterCut(suggestion.price) * count or 0
        if suggestion.action == "POST" or suggestion.action == "HOLD" then
            result.total = result.total + value
        end
        table.insert(result.items, {
            key = key, link = link, count = count, suggestion = suggestion, value = value,
        })
    end

    table.sort(result.items, function(a, b)
        local oa, ob = ORDER[a.suggestion.action], ORDER[b.suggestion.action]
        if oa ~= ob then return oa < ob end
        local wa = a.value * ns.Styles.Factor(a.suggestion.contested)
        local wb = b.value * ns.Styles.Factor(b.suggestion.contested)
        if wa ~= wb then return wa > wb end
        return a.key < b.key
    end)
    return result
end

-- First bag slot holding a tradeable stack of this item key, for putting it
-- into the AH sell box.
function Sell:FindInBags(key)
    for _, bagID in ipairs(Compat.Bags.bags) do
        local numSlots = C_Container.GetContainerNumSlots(bagID) or 0
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bagID, slot)
            if info and info.hyperlink and not info.isBound and Util.ItemKeyFromLink(info.hyperlink) == key then
                return bagID, slot
            end
        end
    end
    return nil
end

-- Puts the item into the Auction House sell box (the same thing a right
-- click in the bags does). Returns true when it worked.
function Sell:PutInSellBox(key)
    if not Compat.IsAuctionHouseOpen() or not AuctionHouseFrame.SetPostItem then return false end
    local bagID, slot = self:FindInBags(key)
    if not bagID then return false end
    local location = ItemLocation:CreateFromBagAndSlot(bagID, slot)
    if not C_Item.DoesItemExist(location) then return false end
    AuctionHouseFrame:SetPostItem(location)
    return true
end
