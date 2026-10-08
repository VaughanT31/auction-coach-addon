# Changelog

## 0.6.0

- **A new look** matching the other CtrlShift_Zed addons: flat dark windows, flat tabs with a gold line under the open one, flat buttons and faint row bands. The post helper beside the Auction House keeps its gold border.
- **Auctions tab (new):** every auction you have listed on this character, your price next to the lowest one, and what to do about each: keep it, repost it at a new price, cancel it because a vendor now pays more, or let it run because reposting isn't worth it today. At the Auction House, click a row to see its listings. `/ac auctions` opens it.
- **Gold overview on My Stuff:** your total gold, each character's gold and the warband bank's, beside your hidden treasure.
- **Today's Plan, more steps:** collect your mailbox first (gold from sales, expired items), post expired items straight from the mail, and cancel listings a vendor now pays more for. Gold waiting in the mailbox counts toward the deals the plan can afford.
- Reposting advice now uses your real listings and their prices, so it also covers auctions posted before Auction Coach was installed.

## 0.5.1

- **Grey items are vendor trash.** Real players hardly buy grey items on the AH: most of their listings are gold sellers moving gold, so their AH prices are not real. Tooltips now say to vendor them, and they no longer count toward hidden treasure, show up as deals or trigger the vendor warning.
- **Today's Plan includes your bank and warband bank:** items worth posting there become "take out of the bank, then post" steps, counting the walk to the banker once. Other characters' items are still listed below the plan.
- **More realistic deals in the plan:** a deal only counts as much as the chance it resells before you are back, and the plan never spends more gold than the character has.
- Several cheap items with the same name are one step instead of a row each, with a reminder to check each one.
- The plan's title no longer runs into the time buttons; how long the plan takes is now in the line below.
- My Stuff: the per-character amounts are now labelled "Items worth", so they are not mistaken for each character's gold.

## 0.5.0

- **Today's Plan (new Today tab):** pick how much time you have (5, 15, 30 or 60 minutes) and get a short to-do list, best gold per minute first: what to post, which of your undercut listings to repost, which deals to buy and what to sell to a vendor, with the gold each step should make. Items better left alone today (prices crashed, or undercut faster than you check back) are listed separately.
- Gold figures are what should actually come in: how many will sell before you are back (from the desktop app's sales data and your seller style), after the AH cut.
- Click a step at the Auction House to start it, and tick steps off as you go. Ticks clear after the next full scan.
- The plan says how much is waiting on your other characters and the warband bank.
- `/ac plan` opens it. Set the default time in the options.

## 0.4.0 (first public release)

Everything so far, in one go:

- **What's it worth:** tooltips say in plain English what an item is worth, how many you have across your characters, whether a vendor pays more and how hard the competition is.
- **Hidden treasure (My Stuff tab):** the AH value of everything sellable across all your characters and your warband bank.
- **What to sell (Sell tab):** every tradeable item in your bags with a suggested price and whether to post, hold or vendor it.
- **Post helper:** suggests a price when you put an item in the AH sell box, with the chance it sells in time.
- **Deals tab:** items listed well below their usual lowest price, with the profit after the AH cut.
- **Undercut timing:** learns how long your listings stay the cheapest before someone posts lower.
- **Seller styles:** casual, active or camper. Advice changes with how often you check the AH, and items that get undercut faster than you check back are marked as contested.
- **Sale messages:** a chat line says what each sale made after the AH cut.
- **Vendor and delete protection:** warns before you sell or delete something valuable, and offers to buy back a valuable item you just sold.
- **Export and import strings:** your items for the website's My report, and prices from the website for players without the desktop app.
- **Old price warning:** the main window shows when prices were last updated, and at login a chat line warns when the desktop app's prices are over 6 hours old (the app has probably stopped) or are for another region. Can be turned off in the options.
- **Options page and minimap button.**
- **Public price API** (`AuctionCoachAPI`) for other addons.

Works on its own with its own AH scans. The free desktop app adds hourly prices, 14-day averages and sales estimates for your realm.
