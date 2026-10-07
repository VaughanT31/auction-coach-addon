# Auction Coach for developers

## Using Auction Coach as a price source

Auction Coach exposes its prices through the global `AuctionCoachAPI`, so other addons can use it as a price source. Prices are copper per item, and functions return `nil` when there is no data. `item` is an item link, an item ID or a TSM-style `"i:12345"`; pass a link for gear.

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
  Advice/              rules, plain-English phrases, hidden treasure, Today's Plan
  UI/                  tooltip, main window, vendor/delete guard
  Locales/             player-facing text
AuctionCoach_Data/     helper addon; its Data.lua is overwritten by the desktop app
Docs/                  screenshots and this file
```

`AuctionCoach_Data` is installed and updated by the Auction Coach desktop app, which downloads hourly prices, 14-day averages and sales estimates. The addon works without it, using its own scans.

## Development

Link both folders into your AddOns folder (run in an elevated Command Prompt, and adjust the paths):

```
mklink /J "C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\AuctionCoach" "F:\AuctionCoach\auction-coach-addon\AuctionCoach"
mklink /J "C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\AuctionCoach_Data" "F:\AuctionCoach\auction-coach-addon\AuctionCoach_Data"
```

Then `/reload` in game after each change.

To build the zip for CurseForge and Wago, bump `## Version` in `AuctionCoach/AuctionCoach.toc`, then run `package.ps1`. It writes `.release\AuctionCoach-<version>.zip` with only the `AuctionCoach` folder: `AuctionCoach_Data` belongs to the desktop app and must never be shipped (it would wipe players' prices on every update).

Conventions:
- Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/).
- No em dashes anywhere (docs, comments, UI text).
- Every player-facing sentence lives in `Locales/enUS.lua`.
- WoW API calls that Blizzard tends to move go through `Core/Compat.lua`.

## All commands

| Command | What it does |
|---|---|
| `/ac` | Open or close the Auction Coach window |
| `/ac plan` | Open Today's Plan |
| `/ac scan` | Scan the Auction House now (it must be open) |
| `/ac status` | Show what the scanner is doing |
| `/ac tooltip` | Turn the tooltip advice on or off |
| `/ac guard` | Turn vendor and delete protection on or off |
| `/ac options` | Open the options |
| `/ac sales` | Turn the sale messages on or off |
| `/ac export` | Copy your items as a string for the website's "My report" |
| `/ac import` | Paste a prices string from the website (instead of the desktop app) |
| `/ac help` | List commands |
