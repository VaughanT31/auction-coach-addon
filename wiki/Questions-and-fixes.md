# Questions and fixes

*Answers to the things people ask most.*

**Does it post or buy for me?**

No, never. It only gives advice. Every click is yours.

**Do I need the desktop app?**

No. The addon works on its own from its own Auction House scans. The app adds price history and sales estimates, which make the advice much better.

**The Auction House scan is slow or doesn't start.**

Blizzard allows one full scan every 15 minutes, shared by all addons. If another auction addon just scanned, the automatic scan waits until the 15 minutes are up. `/ac scan` asks anyway: if Blizzard still says no, it stops after a short wait and tells you. A scan that got no data, for example when you closed the Auction House straight away, doesn't start the 15 minutes. `/ac status` shows what the scanner is doing.

**The desktop app updated its prices. Do I need to scan?**

No. Type `/reload` (or log in) and the app's prices load for every character on your account. While they're under 2 hours old, opening the Auction House skips the full scan and only searches the items you have listed, for undercuts. `/ac scan` still scans whenever you want every live price, and the **Full scan even with fresh app prices** option scans every time, as before.

**Windows says it protected my PC when I run the installer.**

The installer isn't code signed yet. Click **More info**, then **Run anyway**.

**The window says prices are old.**

The desktop app isn't running or can't download. Double-click the tray coin to check it, then `/reload` in game.

**Which regions work?**

EU and US.

**It warned me before I sold something to a vendor.**

That's vendor and delete protection: it warns before you vendor or delete something valuable, and offers to buy it straight back. Turn it off with `/ac guard`.

**Grey items show "vendor" even though they're on the AH.**

Most grey listings on the AH are used to move gold around, so their prices aren't real. Vendoring is the honest price.

**Can my addon use Auction Coach prices?**

Yes. Addon developers can read Auction Coach as a price source; see `Docs/DEVELOPERS.md` on [GitHub](https://github.com/VaughanT31/auction-coach-addon).

---

Previous: [Commands](Commands.md) | [Wiki home](Home.md)

Didn't find your answer? Ask in the [CtrlShiftZed Discord](https://discord.gg/wz7fw6jM9Z).
