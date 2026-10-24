# Changelog

## 0.20.1

- **Flips to your shopping list:** every flip in Other realms has a tick box. Tick the ones you want and press *Add checked to shopping list*. Each goes on at the most you can pay and still make your smallest profit (Options), grouped under *Flip, buy on* the realm to buy it on, so the shopping list tells you when one is cheap enough while you're there.

## 0.20.0

- **Mini gold per hour window:** the gold per hour window has a minimise button beside its X. Minimised, it shows only the gold per hour, time, what you've made, gold looted and items looted, so it takes far less of the screen while you farm. Click it again for the full window with the best items, history and buttons. It remembers which size you left it at.

## 0.19.3

- **Choose how fast flips must sell:** a new *Flips sell at least* option sets how many a day an item must sell on the realm you'd sell it on before Other realms shows it. It was fixed at 1 a day, which let through items that sell once or twice a day. The default is still 1, so nothing changes until you raise it. The line under the Other realms title shows the current setting.

- **Other realms grouped by route:** cross-realm flips now sit under a heading for each route, such as *Buy on Draenor, sell on Quel'Thalas*, so you can see which realm the Buy for and Sells for prices are on. Before, the route was squeezed in after each item's name.

## 0.19.2

- **Clearer empty Deals and Other realms:** both need each item's usual price and how many sell a day, which your own AH scans can't tell, so without them the lists stay empty however much you scan. The messages now say so, and that the free desktop app (Windows) is what fills them. The website's prices string only covers the items you own, so it helps My Stuff and Sell but not these. The old Other realms message wrongly said scanning each realm was enough.

## 0.19.1

- **Refresh checks prices:** opening Blizzard's Auctions tab, or pressing its refresh button, now searches each item you have listed, one at a time at the pace the game allows, and the Status column updates as each answer comes in (*Checking...* until then). Before, refresh only reloaded your own auctions, so an undercut only showed after a full scan or after you searched the item yourself. Items searched in the last minute are skipped, and the check stops as soon as you click an auction or leave the tab, so it never gets in the way of your own searches.
- Fixed: when a search finds only your own listings (the cheaper one sold or expired), you're now the cheapest. Before, the older, lower price was kept, so the item still showed as undercut.

## 0.19.0

- **Cheapest or undercut, right on the Auction House:** Blizzard's Auctions tab gets a *Status* column after Time left. Each of your auctions says *Cheapest*, or *Undercut* with how much lower the cheapest listing is and, in brackets, how many cheaper auctions other sellers have (units, for reagents and other stackables). Hover it for the prices.
- The cheaper count comes from your last search of that item, so click the auction to fill it in. The column uses the same check as Auction Coach's own Auctions tab, so the two always agree.
- Turn it off with *Cheapest or undercut on Blizzard's Auctions tab* in the options.

## 0.18.0

- **Is it worth crafting?** Under every recipe you know, cooking and feasts included, the profession window now shows *To craft* (what one craft's materials cost, each at its cheapest quality) and *Profit* (what it makes at the quality you make, after the AH cut, less the materials), with how many one craft makes and what each sells for. Hover it for the materials one by one.
- **Add to shopping list from the recipe:** the button under it asks how many you want to make, works out the crafts, and puts the materials on your shopping list, less what you already have.
- **Vendor materials count:** Auction Coach now remembers what vendors charge whenever you open one, so recipes with butter, spirits, flux and other vendor materials can be costed. Craft or sell, Today's Plan and Cheapest materials use the vendor's price when it's cheaper than the AH, and the shopping list says to buy those from a vendor instead of adding them. Open the vendor that sells a material once if a recipe says it has no price.
- Turn the recipe lines off with *Cost and profit on the recipe* in the options.

## 0.17.3

- Fixed: with the Auction Coach window open at the Auction House, searching could freeze the game for a moment. Every search (one per item level for gear) redrew the open tab from scratch, several times in the same frame. The window now redraws once for a burst of searches and at most every 5 seconds while you browse; posting, buying and scans still show straight away.

## 0.17.2

- **Pick the click that adds to your shopping list:** if Alt-click already does something for you, like adding items to sell with another addon, choose Ctrl-Alt, Shift-Alt or Ctrl-Shift-click instead in the options (*Add to the shopping list with*), or turn it off. Alt-click is still the default, and the hints show whichever you pick.

## 0.17.1

- **Open with the Auction House:** a new option opens Auction Coach when you open the Auction House and closes it when you leave, unless you already had it open. Off by default.

## 0.17.0

- **A bigger window if you want one:** drag the bottom right corner of the main window to make it bigger. The columns get wider with it, so long names and the Other realms view fit. It never goes smaller than it started, and remembers its size and place.
- **Never suggest an item:** right-click a step in Today's Plan and pick *Never suggest this item*, for the flasks and potions you keep for raid. The plan says how many you've hidden, and *Show them again* in the options brings them back.
- **Leave a character out:** tick *Leave this character's items out* in the options on your main, and Today's Plan stops suggesting selling, vendoring, destroying or crafting with what's in its bags, bank or mail. Deals, the shopping list, reposting what it already listed and the warband bank still count.
- **Other realms says why it's empty:** when there are no cross-realm flips it now shows how many items it compared on your realms and what stopped each one: not listed, a cheap price older than 3 hours (the desktop app isn't running), not enough cheaper, under your minimum profit, too slow or too crowded on the other realm, and any of your realms with no prices yet.
- **Hide tabs you don't use:** untick any of the main window's tabs in the options. Their slash commands still open them.

## 0.16.1

- **Today's Plan is gold for today:** every step that sells something now needs at least an even chance of a sale before you're back. Slow sellers move to their own list under the plan, *post these when you're done*, with the chance of a sale and how many sell a day, and aren't counted in the plan's gold. Click one at the Auction House to post it.
- **No more slow flips or crafts:** deals that wouldn't resell before you're back are left out (the footer says how many), and crafts of items that won't sell today aren't suggested, so the materials get posted instead.
- **Truer gold figures:** expected sales follow the item's sales rate, so a stack of 20 that sells 4 a day counts about 4, and a single item that sells once a week barely counts.
- **No reposting slow sellers:** an undercut listing that's unlikely to sell anyway isn't worth a new deposit, so it's no longer a REPOST step.

## 0.16.0

- **Shopping list without commands:** Alt-click any item in your bags, a chat link or an Auction House result to add it, with a max a little over its usual price already filled in (already on the list: change it instead). The shopping list at the Auction House also has an **Add** button. Turn Alt-click off in the options if it clashes with another addon.
- **Change items instead of removing and re-adding them:** right-click an item on the shopping list (at the Auction House or in Deals > Shopping) for Search, Edit count and max, Remove, and Remove all from the same source.
- **Grouped by where they came from:** the shopping list at the Auction House groups items under *Added by you*, *Patron Planner* and each craft, with a **Clear** button per group.
- **Add a craft's materials:** the **+** on each Cheapest materials row puts that mix's materials on your shopping list, for as many crafts as you type, less what this character already has in bags and banks. Materials already on the list just get their count raised.
- **A clearer shopping panel:** wider, with columns for Need, Lowest, Max and Status, and the mouse wheel scrolls a long list instead of sending you to the Deals tab.

## 0.15.4

- Fixed: the **Gold per hour** window closed when you changed zones or took a portal. It now stays open until you close it with its X, the *Gold per hour* button or Shift-click, so Escape no longer closes it either. If it was open, it also comes back after a /reload or logging in while a session is running. Your session itself was never lost.

## 0.15.3

- **Gold per hour is easier to find:** a *Gold per hour* button sits at the end of the main window's tabs (green while a session is running), and Shift-click on the minimap button or the addons button opens it too. The minimap button's tooltip shows your running session's time and gold per hour. `/ac gph` still works.

## 0.15.2

- **Shopping list fills in how many you need:** clicking an item on the shopping list now sets the Auction House quantity to the amount on your list (*x12* puts 12 in Quantity, with the total price to match). If fewer are listed, it takes all that's there.
- **Bought items come off the shopping list:** buy an item at the Auction House and it's taken off your list. Buy fewer than you need and the count goes down instead (*bought 5, 7 more to go*).
- Fixed: **Cheapest materials** could sit on top of Patron Planner's order queue. It now moves under the queue whenever the queue appears, and back beside the profession window when it closes.
- Fixed: picking a second item from the shopping list while the first one's listings were still open left the Auction House stuck on *Searching...*.

## 0.15.1

- **Your shopping list at the Auction House:** open the AH with items on your list and the list opens beside it: what you need, the lowest listing now against your max, and *Buy now* items first. Click an item to search for it, right-click to take it off. It sits under the price helper while you're selling, the chat line no longer repeats what the panel already shows, and `/ac shop` opens it again if you closed it. Turn it off in the options (Shopping list at the Auction House).

## 0.15.0

- **Other addons can fill your shopping list:** an item can now go on the list with how many you need and who added it. Patron Planner uses this to send what your queued crafting orders still need, and the Deals tab's Shopping view shows the count (*Sunfire Silk x12*) with *You need 12 (added by Patron Planner)* in the tooltip. Auction Coach still tells you when each one is listed at or under your price.
- For addon authors: `AuctionCoachAPI.AddToShoppingList(item, count, maxPrice, note)` and `AuctionCoachAPI.RemoveFromShoppingList(item)`.
- The **Cheapest materials** panel moves under Patron Planner's order queue when both are beside the profession window, instead of covering it.

## 0.14.1

- **Scans that never started:** the Auction House handles one request at a time, and when it opens the game's own window searches straight away. A scan asked for at that moment could be dropped without a reply, and after 2 minutes Auction Coach gave up. The scan now waits until the Auction House is ready and asks again if nothing arrives.
- A scan whose data is still arriving after 2 minutes is no longer stopped.

## 0.14.0

- **Exact amounts at the mailbox:** the game's sale message only names the item, never how many sold, so a stack can't be counted when it sells. Open the mailbox and Auction Coach now says exactly what the sale mails hold, one line per item: *Mailbox: Void-Shrouded Tincture sold 112, 2,021g after the AH cut (3 sales).* Each mail is reported once, however often you open the mailbox.
- **Sold so far on the Auctions tab:** a stack that has partly sold shows how many went, for example *x777 112 sold*, and its tooltip says *112 of 889 sold so far* with the gold after the cut.
- The chat line when a stack sells no longer suggests the whole stack went: it gives the price each and says the mailbox has the exact amount.
- **Deals are judged on what they really resell for:** a few cheap items under a big stack of normal listings now resell just under those listings, not at an inflated "usual" price. The usual price itself is now the typical hour's lowest, so hours when only silly-priced stacks were left no longer push it up (one scroll showed 9,830g profit when it really makes about 125g). The Deals column is now called Resell.
- **With desktop app 0.9:** when something sells while the game is closed, a Windows notification and Discord message say exactly how many sold, for how much after the cut, and how many are still listed. Sales during play stay in the game's chat. Checked against the hourly Auction House snapshot.

## 0.13.0

- **Gold per hour:** type `/ac gph` and press **Start** when you start farming. The window shows your gold per hour, the time, gold looted, what your looted and gathered items are worth, and your best items so far. Only looting and gathering count: quest rewards, vendor and AH sales don't.
- Items are valued at what they sell for on the AH after the cut, or at the vendor when that pays more (or they can't go on the AH), and the value follows the latest prices.
- Started, paused and stopped by hand only, so keys and raids never count; you get a reminder if you enter a dungeon or raid with a session running. A /reload or logout keeps it going without counting the time away.
- **History** lists your last 30 sessions with where you farmed, how long and the gold per hour.

## 0.12.0

- **Cheapest materials:** open one of your recipes and a panel beside the profession window lists each quality you can make, with the cheapest mix of material qualities that gets there, what those materials sell for, and the profit when each quality is its own item. The game itself says which quality each mix makes, so it follows Blizzard's rules exactly.
- **Concentration rows** show up only when concentration reaches a quality with cheaper materials, with how much concentration it costs.
- Hover a row for the materials, how many of each quality. **Use** puts that mix in the recipe. Turn the panel off with "Cheapest materials" in the options.

## 0.11.2

- **Usual prices ignore overpriced walls:** when only a couple of copies were listed at the real price and big overpriced stacks sat above them, the usual price came out near the overpriced stacks. That made cheap listings look like huge deals and crafts look far more profitable than they are. Now a big jump in price after two listings (or two copies) ends the average. Your own AH scans use the new rule straight away; the desktop app's prices follow once the server is updated.

## 0.11.1

- **Craft or sell prices what you'd really get:** a crafted item is valued at the lowest listing when that's below its usual price, since a new post has to undercut it. Items with a few cheap listings and a big overpriced stack looked hugely profitable before (Blood Knight's Armor Kit showed 16,900g when it sells for about 1,000g).
- The Craft view's title no longer gets cut off.

## 0.11.0

- **Deals that actually resell:** an item now has to sell at least 10 a day across the Auction House to count as a deal (change it in the options under Deals: "Sells at least"). Items that sold about once a day showed up before, and they're hard to resell however cheap they are.
- **Counts the competition:** with the desktop app's data, a deal also needs a fair chance of reselling before you're back: the sales expected in that time against the copies already listed at or under the usual price. One sale a day with 30 copies listed is no deal. Each deal now says how many are listed, and Today's Plan uses the same chance for buy steps.
- **Other realms:** flips need at least one sale a day (was one every two days) and the same fair chance of reselling.
- **Updated for patch 12.1.5.**

## 0.10.0

- **Craft steps in Today's Plan:** when a recipe the character you're on knows clearly makes more than selling its materials, and the materials are in your bags, bank or warband bank, the plan says "Craft 2x Flask" with the gold it should bring in. It crafts only as many as should sell before you're back, and the materials it uses aren't suggested for posting as well.
- **Craft or sell knows your quality:** for reagents and consumables, where each quality is its own item, Auction Coach learns which quality each character makes when the profession window is open, and prices that quality instead of the lowest one.
- **Concentration:** when concentration would make the next quality, the Craft view and the plan say how much more it's worth per craft. It's never counted in the profit, since you decide where your concentration goes.

## 0.9.0

- **Craft or sell (new view on the Deals tab):** your characters' recipes, with what one craft's materials sell for against what the crafted item sells for, after the AH cut. Crafts that make money come first; for the rest it says selling the materials makes more. Open each character's profession window once and Auction Coach learns their recipes (the expansion shown there). Hovering a crafted item says what crafting it makes too.
- **Manipulation warnings:** when an item's lowest listing is far above what it usually is and its market value has jumped with it, the tooltip and the post helper say the price looks pushed up (someone may have bought out the cheap listings to reset it), so you don't buy into it or count on that price. Deals whose usual price itself looks pushed up are marked and left out of Today's Plan. Needs the desktop app's price history.
- **Market calendar hints:** Today's Plan notes when today usually means higher or lower prices for consumables and trade goods, and in Darkmoon Faire weeks what the Faire usually does. The post helper says which day consumables or trade goods usually sell best. From the server's price history, through the desktop app; it shows up once there are a few weeks of history.
- **Server:** when more realms are wanted than the server collects, the realms the most players use come first, and realms already being collected keep their place.

## 0.8.1

- **Fixed:** a Lua error that repeated in dungeons and raids when a system message or item tooltip was hidden from addons (Midnight's secret values).

## 0.8.0

- **Shared destroy values:** players who share through the desktop app (0.6.0 or later) now also share what their disenchanting, milling and prospecting gives. Tooltips and Today's Plan use the average from everyone until you have destroyed enough of something yourself, so values show from the start: "Mills into about 38g of materials each (from 4 players' milling)". Your own results take over once you have enough of them. `/ac destroy` shows how many shared values you have.
- **Today's Plan, shopping list:** items on your shopping list that are listed at or below your price now show near the top of the plan as a SHOP step, before the money-making steps. Click it at the Auction House to search for the item. Only items you have the gold for are added.
- **Today's Plan, destroy instead of selling:** when disenchanting, milling or prospecting something in your bags is worth clearly more than selling it, the plan says so in one step per kind ("Mill 40 herbs, about 120g more than selling"), and those items leave the post and vendor steps. Only for what this character can do (Disenchant, Inscription, Jewelcrafting), and only once Auction Coach has learned the item's yield.
- **Settings:** switches for the destroy line on tooltips and for the shopping list chat alerts, in the Auction Coach options.
- **Gold history:** hover a day to see each character's gold and the warband bank's that day. A note shows when gold is still waiting in a mailbox, since sales are counted when you collect them.

## 0.7.0

- **Gold history:** a History button under the gold overview on My Stuff (or `/ac gold`) shows how your gold changed today, this week and this month, with a day-by-day list. AH sales and purchases come from the Auction House's own mails, counted on the day you collect them, with how many items.
- **Shopping list:** add items you want with the most you'll pay (Deals tab > Shopping, or `/ac shop add [item] 12.5`). When one is listed at or below that, the list marks it "Buy now", its tooltip says so and a chat line tells you. Right-click a row to remove it. `/ac shop alerts` turns the chat line off.
- **Cross-realm flips:** Deals tab > Other realms lists items that are cheap on one of your realms and usually sell for more on another, with the profit after the AH cut. Buy, move it through the warband bank, post. Commodities cost the same on every realm, so these are mostly gear, pets and other realm-only items.
- **Destroy values:** tooltips say what an item is worth disenchanted, milled or prospected, and whether that beats selling it. There is no game data for what items destroy into, so Auction Coach learns it from what you get each time you destroy something. Until then the tooltip shows how far along it is, and `/ac destroy` lists everything learned. Herbs and ore milled or prospected straight from your bank or warband bank count too. Soulbound gear gets the disenchant line too.

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
