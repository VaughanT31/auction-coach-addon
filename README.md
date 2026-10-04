# Auction Coach (addon)

A plain-English Auction House coach for World of Warcraft (Retail). Auction Coach tells you what your stuff is worth, what to sell and what to keep, without TSM-style groups, operations or price formulas.

**It advises and never automates.** You do all the buying, posting and cancelling yourself.

## What it does

- **Inventory across alts:** bags, bank, reagent bank, warband bank, guild bank tabs you open, mailbox and active auctions. Only tradeable items are counted.
- **Full AH scan:** runs when you open the Auction House, at most once every 15 minutes (Blizzard's limit). You can also start it with `/ac scan` or the **Scan AH** button.
- **Plain-English tooltips:** what an item is worth, how many you have, whether a vendor pays more, and how hard the competition is.
- **Live competition sampling:** every item you search at the AH records the lowest price and the number of sellers. The more often the lowest price changes, the higher the competition.
- **Hidden treasure (My Stuff tab):** the AH value of everything sellable across all your characters and your warband bank.
- **What to sell (Sell tab):** every tradeable item in your bags with one suggested price, how fast it sells and whether to post, hold or vendor it. At the AH, click a row to put the item in the sell box.
- **Post helper:** when you put an item in the AH sell box, a panel beside it suggests a price. "Use this price" fills it in; you still click Post.
- **Deals tab:** items listed well below what their lowest listing normally is, with the profit after the AH cut. At the AH, click a row to open its listings. Buying is up to you.
- **Vendor and delete protection:** tooltips at a merchant warn before you sell something valuable. If you sell it anyway, a popup offers to buy it straight back. Deleting a valuable item shows a warning above the confirmation.

## Commands

| Command | What it does |
|---|---|
| `/ac` | Open or close the Auction Coach window |
| `/ac scan` | Scan the Auction House now (it must be open) |
| `/ac tooltip` | Turn the tooltip advice on or off |
| `/ac guard` | Turn vendor and delete protection on or off |
| `/ac help` | List commands |

You can also open the window from the addon compartment button next to the minimap.

## For other addons

Auction Coach exposes its prices through the global `AuctionCoachAPI` (CraftSim uses it as a price source). Prices are copper per item, and functions return `nil` when there is no data. `item` is an item link, an item ID or a TSM-style `"i:12345"`; pass a link for gear.

| Function | Returns |
|---|---|
| `AuctionCoachAPI.IsReady()` | `true` once prices can be read (after login) |
| `AuctionCoachAPI.GetMarketValue(item)` | Typical price (cheapest 15-30% of listings) |
| `AuctionCoachAPI.GetMinBuyout(item)` | Lowest listing |
| `AuctionCoachAPI.GetHistorical(item)` | 14-day average market value (needs the desktop app) |
| `AuctionCoachAPI.GetSaleRate(item)` | Estimated sales per day (needs the desktop app) |
| `AuctionCoachAPI.GetPriceInfo(item)` | Table: `market`, `min`, `historical`, `salesPerDay`, `updated`, `source` |
| `AuctionCoachAPI.GetSuggestedPrice(item)` | Price to post at, and `"POST"`, `"HOLD"`, `"VENDOR"` or `"NO_DATA"` |

`AuctionCoachAPI.version` is 1 and only goes up on breaking changes.

## Repo layout

```
AuctionCoach/          the addon
  Core/                bootstrap, events, helpers, API wrappers
  Data/                inventory, prices, competition
  Scan/                full AH scan and live item checks
  Advice/              rules, plain-English phrases, hidden treasure
  UI/                  tooltip, main window, vendor/delete guard
  Locales/             player-facing text
AuctionCoach_Data/     helper addon; its Data.lua is overwritten by the desktop app
```

`AuctionCoach_Data` is installed and updated by the Auction Coach desktop app, which downloads hourly prices, 14-day averages and sales estimates. The addon works without it, using its own scans.

## Development

Link both folders into your AddOns folder (run in an elevated Command Prompt, and adjust the paths):

```
mklink /J "C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\AuctionCoach" "F:\AuctionCoach\auction-coach-addon\AuctionCoach"
mklink /J "C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\AuctionCoach_Data" "F:\AuctionCoach\auction-coach-addon\AuctionCoach_Data"
```

Then `/reload` in game after each change.

Conventions:
- Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/).
- No em dashes anywhere (docs, comments, UI text).
- Every player-facing sentence lives in `Locales/enUS.lua`.
- WoW API calls that Blizzard tends to move go through `Core/Compat.lua`.

## Licence

MIT, see [LICENSE](LICENSE).
