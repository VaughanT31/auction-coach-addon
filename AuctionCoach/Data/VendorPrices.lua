-- Auction Coach - what vendors charge for the items they sell, noted each
-- time a vendor window opens, so recipes that use vendor materials (cooking
-- spirits, butter, flux and the like) can be costed. Kept for the account,
-- one price per item: what one unit costs in gold. Items sold for currency
-- or other items aren't kept.
--
--   ns.db.vendorPrices = { [itemID] = copper per unit }

local _, ns = ...

local VendorPrices = {}
ns.VendorPrices = VendorPrices

local function Prices()
    ns.db.vendorPrices = ns.db.vendorPrices or {}
    return ns.db.vendorPrices
end

-- One merchant item: price (for the whole stack), stack size, and whether
-- it also costs a currency or item.
local function ReadItem(index)
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local ok, info = pcall(C_MerchantFrame.GetItemInfo, index)
        if ok and type(info) == "table" then
            return info.price, info.stackCount, info.hasExtendedCost
        end
    end
    if GetMerchantItemInfo then
        local _, _, price, quantity, _, _, _, extendedCost = GetMerchantItemInfo(index)
        return price, quantity, extendedCost
    end
    return nil
end

function VendorPrices:Scan()
    if not ns.db or not GetMerchantNumItems or not GetMerchantItemID then return end
    local prices = Prices()
    for index = 1, GetMerchantNumItems() or 0 do
        local itemID = GetMerchantItemID(index)
        local price, stack, extended = ReadItem(index)
        if itemID and price and price > 0 and not extended then
            prices[itemID] = math.floor(price / math.max(1, stack or 1) + 0.5)
        end
    end
end

function VendorPrices.Get(itemID)
    return ns.db and ns.db.vendorPrices and ns.db.vendorPrices[tonumber(itemID)] or nil
end

-- The cheaper of an AH price and the vendor's, and whether it's the
-- vendor's. Either can be nil.
function VendorPrices.Cheapest(itemID, ahPrice)
    local vendor = VendorPrices.Get(itemID)
    if vendor and (not ahPrice or vendor <= ahPrice) then return vendor, true end
    return ahPrice, false
end

ns.Events:On("MERCHANT_SHOW", function() VendorPrices:Scan() end)
-- The item list can fill in a moment after the window opens.
ns.Events:On("MERCHANT_UPDATE", function()
    ns.Util.Debounce("vendorPrices", 0.5, function() VendorPrices:Scan() end)
end)
