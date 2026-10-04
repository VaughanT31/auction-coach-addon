-- Auction Coach Data
-- The Auction Coach desktop app overwrites this file with fresh prices.
-- WoW only reads it on login or /reload. Do not edit by hand.
--
-- Format 1:
-- AuctionCoachData = {
--   format = 1,
--   generatedAt = 1759564800,          -- unix time the data was built
--   region = "EU",
--   realmIndex = {                     -- realm name (no spaces) -> connected realm ID
--     ["Draenor"] = "1403",
--   },
--   realms = {                         -- realm-specific items (gear, pets...)
--     ["1403"] = {
--       ["12345:b6652.12817"] = { m = 0, n = 0, h = 0, l = 0, s = 0, t = 0 },
--     },
--   },
--   commodities = {                    -- region-wide items (reagents, consumables...)
--     ["190396"] = { m = 0, n = 0, h = 0, l = 0, s = 0, t = 0 },
--   },
-- }
--
-- Item fields (prices in copper per item):
--   m  market value (average of the cheapest chunk of listings)
--   n  lowest price
--   h  14-day average market value
--   l  usual lowest price: 7-day average of the hourly lowest price
--   s  estimated sales per day
--   t  unix time of the snapshot this row came from (optional, defaults to generatedAt)
-- Item keys follow the addon's format, see AuctionCoach/Core/Util.lua.

AuctionCoachData = {
    format = 1,
    generatedAt = 0,
    region = "EU",
    realmIndex = {},
    realms = {},
    commodities = {},
}
