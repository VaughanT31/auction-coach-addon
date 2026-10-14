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
--       ["12345:b6652.12817"] = { m = 0, n = 0, h = 0, l = 0, s = 0, t = 0, u = 0, un = 0, w = 0, wn = 0 },
--     },
--   },
--   commodities = {                    -- region-wide items (reagents, consumables...)
--     ["190396"] = { m = 0, n = 0, h = 0, l = 0, s = 0, t = 0, u = 0, un = 0, w = 0, wn = 0 },
--   },
--   calendar = {                       -- what the weekday and the Darkmoon Faire do to prices
--     consumables = { p = { 1.2, 0.4, -0.8, 0, -0.5, 0.3, -0.6 }, s = { 15, 14, 13, 14, 14, 15, 15 }, f = 3.1, fw = 2 },
--   },
--   destroy = {                        -- what items destroy into, from players who share
--     ["236761"] = { k = "MILL", n = 4, u = 380, o = { ["245807"] = 0.45 } },
--     ["dx:3:11"] = { k = "DE", n = 2, u = 40, o = { ["243599"] = 1.3 } },
--   },
-- }
--
-- Item fields (prices in copper per item):
--   m  market value (average of the cheapest chunk of listings)
--   n  lowest price
--   h  14-day average market value
--   l  usual lowest price: 7-day average of the hourly lowest price
--   u  typical seconds until a listing posted at the lowest price gets undercut,
--      from players who share their posts (opt-in); un = how many posts
--   w  typical seconds until such a listing first sells; wn = how many sales
--      (u/un and w/wn only appear once at least 3 posts back them)
--   s  estimated sales per day
--   c  units listed right now at or below the usual lowest price (or the
--      market value when there is no usual lowest yet)
--   t  unix time of the snapshot this row came from (optional, defaults to generatedAt)
-- Destroy fields (optional, desktop app 0.8 and later): per source, an item key
-- or a gear group "dx:<quality>:<expansion>":
--   k  DE | MILL | PROSPECT | SALVAGE
--   n  how many players' destroying it is averaged from (at least 2)
--   u  how many items they destroyed in all
--   o  quantity of each material per item destroyed
-- Calendar fields (optional, per item group: consumables, tradegoods):
--   p   price % against each item's own average, per weekday (1 = Monday,
--       UTC days), from the region's most sold items of the last 8 weeks
--   s   share of the week's sales per weekday, in %
--   f   % change in Darkmoon Faire weeks over the week before; fw = how many
--       Faire weeks that is averaged from
-- Item keys follow the addon's format, see AuctionCoach/Core/Util.lua.

AuctionCoachData = {
    format = 1,
    generatedAt = 0,
    region = "EU",
    realmIndex = {},
    realms = {},
    commodities = {},
}
