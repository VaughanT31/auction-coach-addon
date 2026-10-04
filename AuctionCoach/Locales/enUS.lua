-- Auction Coach - English strings.
-- Every player-facing sentence lives here so the advice stays plain English
-- and other locales can be added later without touching the logic.

local _, ns = ...

local L = {}
ns.L = L

L.ADDON_TITLE = "Auction Coach"

-- Money and time
L.MONEY_GOLD = "%sg"
L.MONEY_GOLD_SILVER = "%dg %ds"
L.MONEY_SILVER = "%ds"
L.MONEY_COPPER = "%dc"
L.AGE_JUST_NOW = "just now"
L.AGE_MINUTES = "%d min ago"
L.AGE_HOURS = "%dh ago"
L.AGE_DAYS = "%d days ago"

-- Slash commands
L.HELP_HEADER = "Commands:"
L.HELP_TOGGLE = "/ac - open or close the Auction Coach window"
L.HELP_SCAN = "/ac scan - scan the Auction House now (it must be open)"
L.HELP_TOOLTIP = "/ac tooltip - turn the tooltip advice on or off"
L.HELP_GUARD = "/ac guard - turn vendor and delete protection on or off"
L.UNKNOWN_COMMAND = "Unknown command \"%s\"."
L.TOOLTIP_ON = "Tooltip advice is on."
L.TOOLTIP_OFF = "Tooltip advice is off."
L.GUARD_ON = "Vendor and delete protection is on."
L.GUARD_OFF = "Vendor and delete protection is off."

-- Full scan
L.SCAN_NEED_AH = "Open the Auction House first, then scan."
L.SCAN_TOO_SOON = "Blizzard allows one full scan every 15 minutes. Next scan in %s."
L.SCAN_STARTED = "Scanning the Auction House. This takes up to a minute."
L.SCAN_DONE = "Scan finished: %s items priced. Hover any item to see what it's worth."
L.SCAN_FAILED = "The scan returned no auctions. Try again in a few minutes."
L.SCAN_BUSY = "A scan is already running."
L.SCAN_PROGRESS = "Scanning... %d%%"
L.SCAN_WAITING = "Waiting for scan data..."
L.SCAN_AUTO_LATER = "Full scans are allowed once every 15 minutes. Auction Coach will scan automatically in %s if the Auction House is still open."
L.SCAN_NO_DATA = "Blizzard sent no scan data after 2 minutes, so the scan was stopped. Full scans are limited to one every 15 minutes, and other auction addons (Auctionator, TSM) can use that up. Try /ac scan again later."
L.SCAN_ERROR = "The scan stopped because of an error: %s"

-- Status
L.HELP_STATUS = "/ac status - show what the scanner is doing"
L.STATUS_WAITING = "Waiting for Blizzard to send the scan data (%d sec so far, %d auctions received)."
L.STATUS_PROCESSING = "Processing the scan: %d%% of %s auctions."
L.STATUS_IDLE = "No scan running."
L.STATUS_LAST_SCAN = "Last full scan: %s, %s items priced."
L.STATUS_NEVER = "No full scan finished yet on this realm."
L.STATUS_NEXT = "Next full scan allowed in %s."
L.STATUS_REALM = "Realm group: %s"
L.STATUS_ERROR = "Last error: %s"
L.STATUS_OTHERS = "Other auction addons loaded: %s. They may use up Blizzard's one full scan per 15 minutes."
L.SCAN_MINUTES = "%d min"
L.SCAN_SECONDS = "%d sec"

-- Tooltip advice
L.TT_WORTH_SCAN = "Worth about %s each on the AH (checked %s)."
L.TT_WORTH_DATA = "Worth about %s each on the AH (price data from %s)."
L.TT_YOU_HAVE = "You have %s across your characters: about %s after the 5%% AH cut."
L.TT_NO_PRICE = "No AH price yet. Open the Auction House and Auction Coach will scan it."
L.TT_STALE = "This price is from %s. Open the Auction House to refresh it."
L.TT_VENDOR_BETTER = "A vendor pays more (%s) than the AH after its cut. Sell this to a vendor."
L.TT_DONT_VENDOR = "Don't sell this to a vendor: it only pays %s. List it on the AH instead."
L.TT_COMP_LOW = "Competition: Low. The lowest price rarely changes."
L.TT_COMP_MEDIUM = "Competition: Medium. The lowest price changes about once an hour."
L.TT_COMP_HIGH = "Competition: High. The lowest price changes about %s times an hour."
L.TT_COMP_EXTREME = "Competition: Extreme. Listings get undercut within minutes."
L.TT_SELLERS = "About %d sellers have this listed right now."

-- Hidden treasure / My Stuff
L.TAB_MY_STUFF = "My Stuff"
L.TREASURE_TOTAL = "Hidden treasure: about %s"
L.TREASURE_SUB = "Sellable items across %d characters and your warband bank, after the 5%% AH cut. Check each item's tooltip before selling."
L.TREASURE_SUB_ONE = "Sellable items on this character and your warband bank, after the 5% AH cut. Log in to your alts to add theirs."
L.ITEM_LOADING = "Loading item..."
L.TREASURE_EMPTY_PRICES = "No prices yet. Open the Auction House and Auction Coach will scan it. That takes about a minute, then come back here."
L.TREASURE_EMPTY_ITEMS = "Nothing sellable found yet. Log in to your other characters and open their banks so Auction Coach can count their items."
L.TREASURE_UNPRICED = "%d items have no AH price yet and are not counted."
L.TREASURE_NOTICE = "Hidden treasure: your characters hold about %s of sellable items. Type /ac to see what."
L.TREASURE_WARBAND = "Warband bank"
L.SCAN_BUTTON = "Scan AH"
L.SCAN_BUTTON_TIP = "Scans the whole Auction House. Allowed once every 15 minutes."

-- Where items are kept
L.WHERE_BAGS = "bags"
L.WHERE_BANK = "bank"
L.WHERE_REAGENT_BANK = "reagent bank"
L.WHERE_MAIL = "mail"
L.WHERE_AUCTIONS = "auctions"

-- Vendor / delete protection
L.GUARD_SOLD_ONE = "You just sold %s to a vendor for %s. It's worth about %s on the AH. Buy it back?"
L.GUARD_SOLD_MANY = "You just sold %d items to a vendor for %s. They're worth about %s on the AH. Buy them back?"
L.GUARD_BUY_BACK = "Buy back"
L.GUARD_KEEP_SOLD = "Keep sold"
L.GUARD_DELETE = "Wait! %s is worth about %s on the Auction House. Sell it instead of deleting it?"
L.GUARD_BOUGHT_BACK = "Bought back %d items."
