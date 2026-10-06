# Auction Coach (addon)

A plain-English Auction House coach for World of Warcraft (Retail). Auction Coach tells you what your stuff is worth, what to sell and what to keep, without TSM-style groups, operations or price formulas.

**It advises and never automates.** You do all the buying, posting and cancelling yourself.

Website: [auctioncoach.ctrlshiftzed.com](https://auctioncoach.ctrlshiftzed.com)

## Install

### 1. The addon

Pick one:

- **CurseForge app or Wago app:** search for **Auction Coach** and click Install.
- **By hand:** download `AuctionCoach-x.y.z.zip` from this repo's [releases](https://github.com/VaughanT31/auction-coach-addon/releases) and unzip it into `World of Warcraft\_retail_\Interface\AddOns`. You should end up with `AddOns\AuctionCoach\AuctionCoach.toc`.

Log in (or `/reload`), open the Auction House once, and Auction Coach scans it. Tooltips and the window (`/ac`) start giving advice straight away. That is all you need: the desktop app below is optional.

### 2. The desktop app (optional, recommended)

The free Windows app runs in the tray and downloads fresh prices every hour, with 14-day averages, usual prices and sales estimates. These power deals, sell chances and "usually sells for" advice.

1. **Download** `AuctionCoachSetup-0.5.0.exe` from the [desktop app release](https://github.com/VaughanT31/auction-coach-addon/releases/tag/desktop-v0.5.0) on this repo. The release notes list its SHA-256 fingerprint if you want to check the file.
2. **Run it.** Windows may say it protected your PC, because the installer is not code signed yet: click **More info**, then **Run anyway**. It installs for your Windows user only, so no admin prompt.
3. **Where is World of Warcraft?** The app finds your WoW folder on its own; click it, then **Continue**. If it is somewhere unusual, open **Use a different folder** and paste the path to the folder that contains `_retail_`.
4. **Which realms do you play on?** Your characters' realms are ticked for you if you have logged in with the addon before. Check the **Region** (EU or US) and tick any other realms you play, then **Save realms**.
5. **Wait for "Prices are up to date"** (a few seconds), then click **Finish**.
6. **In game, type `/reload`.** Open `/ac`: the top right says "Prices updated ... ago".

From then on the app starts with Windows and keeps prices fresh. WoW only loads new prices at login or `/reload`. If the app stops, Auction Coach says so in chat at login once its prices are over 6 hours old.

To change realms, the WoW folder or settings later, double-click the Auction Coach coin in the Windows tray (or right-click it, **Open Auction Coach**). To remove the app, use Windows **Settings > Apps > Auction Coach**.

### No desktop app?

Paste prices from the website instead: in game, type `/ac export`, paste the string under **My report** on [the website](https://auctioncoach.ctrlshiftzed.com/#/report), copy the prices string it gives back, then `/ac import` in game and paste it. Repeat whenever you want fresher prices.

## What it does

- **Inventory across alts:** bags, bank, reagent bank, warband bank, guild bank tabs you open, mailbox and active auctions. Only tradeable items are counted.
- **Full AH scan:** runs when you open the Auction House, at most once every 15 minutes (Blizzard's limit). You can also start it with `/ac scan` or the **Scan AH** button.
- **Plain-English tooltips:** what an item is worth, how many you have, whether a vendor pays more, and how hard the competition is.
- **Live competition sampling:** every item you search at the AH records the lowest price and the number of sellers. The more often the lowest price changes, the higher the competition.
- **Sale messages:** when one of your auctions sells, a chat line says what it made after the AH cut (for a stack, the price each and what the whole stack makes).
- **Undercut timing:** when you post at the lowest price, Auction Coach notes how long your listing stays the cheapest, from your later AH searches and scans. After a few posts, tooltips and the post helper say how quickly that item usually gets undercut.
- **Hidden treasure (My Stuff tab):** the AH value of everything sellable across all your characters and your warband bank.
- **What to sell (Sell tab):** every tradeable item in your bags with one suggested price, how fast it sells and whether to post, hold or vendor it. At the AH, click a row to put the item in the sell box.
- **Post helper:** when you put an item in the AH sell box, a panel beside it suggests a price. "Use this price" fills it in; you still click Post. With the desktop app's sales data it also shows the chance your stack sells within 24 hours at the suggested price, just under the next seller and at the usual price.
- **Seller styles:** tell Auction Coach how you sell (casual, active or camper) in the options. Items that get undercut faster than you check back are marked "Post (contested)" and ranked lower, and the chance to sell is shown for the time until you are likely back.
- **Deals tab:** items listed well below what their lowest listing normally is, with the profit after the AH cut. At the AH, click a row to open its listings. Buying is up to you.
- **Old price warning:** the main window shows when prices were last updated. At login, a chat line warns when the desktop app's prices are over 6 hours old (the app has probably stopped) or are for another region. Addons cannot talk to the desktop app, so the age of its prices is how Auction Coach notices.
- **Vendor and delete protection:** tooltips at a merchant warn before you sell something valuable. If you sell it anyway, a popup offers to buy it straight back. Deleting a valuable item shows a warning above the confirmation.

## Commands

| Command | What it does |
|---|---|
| `/ac` | Open or close the Auction Coach window |
| `/ac scan` | Scan the Auction House now (it must be open) |
| `/ac tooltip` | Turn the tooltip advice on or off |
| `/ac guard` | Turn vendor and delete protection on or off |
| `/ac options` | Open the options (also Esc > Options > AddOns, or right click the minimap button) |
| `/ac sales` | Turn the sale messages on or off |
| `/ac export` | Copy your items as a string for the website's "My report" |
| `/ac import` | Paste a prices string from the website (instead of the desktop app) |
| `/ac help` | List commands |

You can also open the window with the minimap button (drag it around the minimap edge, hide it in the options) or the addons button next to the minimap. Right click either for the options.

## For other addons

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

To build the zip for CurseForge and Wago, bump `## Version` in `AuctionCoach/AuctionCoach.toc`, then run `package.ps1`. It writes `.release\AuctionCoach-<version>.zip` with only the `AuctionCoach` folder: `AuctionCoach_Data` belongs to the desktop app and must never be shipped (it would wipe players' prices on every update).

Conventions:
- Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/).
- No em dashes anywhere (docs, comments, UI text).
- Every player-facing sentence lives in `Locales/enUS.lua`.
- WoW API calls that Blizzard tends to move go through `Core/Compat.lua`.

## Licence

MIT, see [LICENSE](LICENSE).
