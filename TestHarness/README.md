# Test Harness

A fake Grow A Garden interface, written in Lua, that runs inside your own Roblox
Studio place. It exists so you can develop and debug the macro without joining
the live game: no ban risk, no waiting five minutes for a restock, and a HUD that
tells you what the macro actually clicked.

## Setup

1. Open Roblox Studio, **New > Baseplate**.
2. In the Explorer, expand **StarterPlayer > StarterPlayerScripts**.
3. Right-click **StarterPlayerScripts > Insert Object > LocalScript**.
4. Delete the placeholder line and paste in all of `MockGarden.client.lua`.
5. Press **F5** to play. Press **F11** for fullscreen, so screen pixels line up
   with what `constantsPositions.py` expects.

## Harness hotkeys

These are harness controls, not game inputs:

| Key | Effect |
|---|---|
| `F5` | Force a restock immediately, instead of waiting for the 5-minute mark |
| `F6` | Toggle fast hatch (10s to 2s) |
| `F7` | Reset the HUD counters |

## What it reproduces

Layout is positioned from the same design coordinates as
`Constants/constantsPositions.py`, expressed as fractions of 1920x1080:

| Element | Coordinates | Used by |
|---|---|---|
| Seeds button | 680, 135 | `buySeedShop.moveToSeedShop` |
| Garden button | 960, 137 | `main.returnToGarden` |
| Shop window | 555,225 -> 1360,980 | the screenshot region in `buy.buy` |
| X button | 1290, 265 | `closeGearShop` / `closeSeedShop` |
| Dialogue options | 960,515 -> 1700,700 | `moveToGearShop` |

Behaviour:

- **Full gear shop path.** Pressing `3` equips the recall wrench, a click
  teleports you, `e` opens the vendor dialogue with three differently worded
  options (mirroring the three `showGearShopImagePaths` templates), and clicking
  one opens the shop.
- **Seed shop path.** Clicking Seeds then pressing `e` opens the seed shop.
- **The "Stock" header**, so the `shopOpenPath` check has something to match.
- **Price below item name.** Each row puts the item name on top and the money
  symbol underneath, which is what makes the `moneySymbolCoords[1] > newCoords[1]`
  check in `buy.py:48` meaningful. Get the layout wrong and that check is what
  catches it.
- **Real stock counts.** Each item restocks to a random 1-8. Buying decrements it;
  at zero the money symbol disappears, exactly like the real shop, so there is
  nothing left for the macro to match.
- **Scrolling.** The item list is a `ScrollingFrame`, so `autoit.mouse_wheel`
  works and the scroll-and-search loop in `buy.py` gets properly exercised.
- **Restock on the clock.** The harness restocks when `minute % 5 == 0`, the same
  condition as `main.isFiveMinMark()`, so `main.py` triggers on its own.
- **Eggs and hatching.** The Eggs button opens an egg shop. Buying an egg puts it
  in a hotbar; clicking the hotbar then the garden places it; after a countdown
  the plot reads `Ready to Hatch` and shows a `Hatch` button; clicking it turns
  the plot into `Pet: <name>`. That is the full loop a `hatchEggs.py` would drive.

## The wasted-click counter

The HUD counts every click the money symbol received and how many landed after
stock hit zero. `buy.py` fires 40 clicks per item unconditionally, so against an
item with 3 in stock you should see 37 wasted. That number is the measurement
behind the `TODO` on `buy.py:51` — it tells you what to replace the hardcoded 40
with, and whether clicks are being dropped for being too fast.

## What this does NOT test

**Your real templates.** The harness draws text with Roblox's own fonts, not the
game's item icons, so the PNGs in `Screenshots/` will not match it. To drive the
macro against the harness you need a separate set of templates cropped from
harness screenshots.

So the split is:

- **Harness** validates logic: the state machine, the scroll-and-search loop, the
  price-position check, click counts, timing, the restock cycle, Discord
  notifications.
- **Live game** validates recognition: whether your templates still match after a
  game update, and whether the camera angle holds.

The harness is where you iterate quickly; the live game is the final check.
