-- Auction Coach - "hidden treasure": the AH value of everything sellable
-- across all characters and the warband bank.
-- An item only counts when the AH pays more than a vendor after the cut.

local _, ns = ...
local L, Util = ns.L, ns.Util

local Treasure = {}
ns.Treasure = Treasure

local NOTICE_INTERVAL = 86400

local function RealmOf(owner)
    if owner == "warband" then return nil, nil end
    local char = ns.db.characters[owner]
    return char and char.realmGroup, owner:match("%-(.+)$")
end

-- Returns {
--   total = copper after cut,
--   owners = { { owner, value }, ... } sorted by value,
--   items = { { key, link, count, value, where }, ... } sorted by value,
--   unpriced = number of item keys with no price,
--   priced = number of item keys with a price,
-- }
function Treasure:Compute()
    local result = { total = 0, owners = {}, items = {}, unpriced = 0, priced = 0 }
    local ownerValues = {}

    for key, entry in pairs(ns.Inventory:GetTotals()) do
        local link = ns.db.links[key]
        local itemValue, counted = 0, 0
        local hasPrice = false

        for owner, locations in pairs(entry.where) do
            -- Price each owner's items on their own realm group, falling
            -- back to the current one (always the case for the warband bank).
            local groupKey, realmName = RealmOf(owner)
            local afterCut = ns.Rules:AuctionBeatsVendor(key, link, groupKey, realmName)
            if not afterCut and groupKey then
                afterCut = ns.Rules:AuctionBeatsVendor(key, link)
            end
            if afterCut then
                hasPrice = true
                local count = 0
                for _, n in pairs(locations) do count = count + n end
                local value = afterCut * count
                itemValue = itemValue + value
                counted = counted + count
                ownerValues[owner] = (ownerValues[owner] or 0) + value
            elseif ns.Prices:Get(key, groupKey, realmName) or ns.Prices:Get(key) then
                hasPrice = true
            end
        end

        if itemValue > 0 then
            result.total = result.total + itemValue
            table.insert(result.items, {
                key = key, link = link, count = counted, value = itemValue, where = entry.where,
            })
        end
        if hasPrice then
            result.priced = result.priced + 1
        else
            result.unpriced = result.unpriced + 1
        end
    end

    for owner, value in pairs(ownerValues) do
        table.insert(result.owners, { owner = owner, value = value })
    end
    table.sort(result.owners, function(a, b) return a.value > b.value end)
    table.sort(result.items, function(a, b) return a.value > b.value end)
    return result
end

-- After a scan, tell the player once a day what their stuff is worth.
ns.Events:On("AC_SCAN_COMPLETE", function()
    if not ns.db.settings.treasureNotice then return end
    if Util.Now() - (ns.db.treasureNoticeAt or 0) < NOTICE_INTERVAL then return end
    local result = Treasure:Compute()
    if result.total > 0 then
        ns.db.treasureNoticeAt = Util.Now()
        Util.Print(L.TREASURE_NOTICE:format(Util.FormatMoney(result.total)))
    end
end)
