# Bureau of Material Worth

A lightweight inventory addon for *The Elder Scrolls Online*. It sums the
**market value of everything in your Craft Bag** and shows the total — with an
optional breakdown by crafting profession — in a small panel beside the bag.
The game itself only knows the worthless vendor price; this addon reads real
trading prices through **LibPrice**, which transparently pulls from whichever
price source you have installed (Master Merchant, Tamriel Trade Centre, or
Arkadius' Trade Tools).

> **Compatibility:** API: LIVE 101050 · Requires [LibPrice](https://www.esoui.com/downloads/info2753.html)
> (and a price source such as Master Merchant or Tamriel Trade Centre to read
> prices from) and [LibAddonMenu-2.0](https://www.esoui.com/downloads/info7-LibAddonMenu.html)
> (>= 43) for the settings panel.

---

## What it does

Open your Craft Bag and a slim panel appears beside it: a prominent **grand
total** in gold at the top, a subtitle with the total stack and item counts, then
a **per-profession breakdown** (Blacksmithing, Clothier, Woodworking, Jewelry,
Alchemy, Enchanting, Provisioning, and an "Other" bucket). Hover any category for
its value, stack count, item count, and how many stacks have no price. A footer
shows **how long ago** the figures were computed and whether **every stack has a
price**. As you deposit or withdraw materials the total updates on its own.
That's the whole addon — no gameplay changes, just an answer to "how much is all
of this actually worth?".

---

## Features

### Craft Bag valuation
- Sums the LibPrice market value of every stack in the Craft Bag, accounting for
  stack sizes (price × count per stack).
- A **prominent grand total** with a subtitle showing total stacks and items.
- A **per-profession breakdown** beneath it, which you can turn off to show just
  the total.
- **Hover tooltips** on each category reveal its value, stack count, item count
  (one stack can hold up to 200 items), and how many of its stacks have no price.
- Values are formatted with thousands separators and the gold icon, so the panel
  reads at a glance.

### Honest about its data
- A footer line shows **when the value was last computed** ("just now", "5m ago",
  …), refreshed live while the bag is open.
- A second footer line reports **price coverage**: either "all stacks priced" or
  how many stacks LibPrice has no data for. Categories with gaps are flagged with
  a subtle marker, so the total never silently pretends to be complete.
- `/bmw refresh` re-queries prices — handy after Master Merchant or Tamriel Trade
  Centre finishes importing fresh data.

### Lives with the Craft Bag
- The panel is anchored to the Craft Bag and is only on screen while the bag is
  open. The configurable horizontal/vertical offset lets you nudge it to taste.

### Settings & localization
- A clean **LibAddonMenu** panel: toggle the category breakdown, adjust the
  panel offset, set chat-debug verbosity, and force a price refresh.
- Full **English and Russian** localization.
- Slash commands for everything (see below).

---

## Why it's built well — the performance story

The Craft Bag can hold **hundreds of distinct material stacks**, and a market
price lookup is not free. The naïve approach — loop every slot and query the
price addon, on every inventory event — is exactly what causes the multi-second
freezes you may have seen elsewhere. This addon is built specifically to avoid
that:

- **Zero work while the bag is closed.** Inventory changes that arrive while the
  Craft Bag is shut do nothing but mark the valuation *dirty*. No scanning, no
  price lookups, no UI work happens in the background.
- **Lazy, one-shot scan on open.** A full rescan runs only when the bag becomes
  visible *and* something changed since last time. If nothing changed, opening
  the bag costs nothing.
- **One price lookup per material, per session.** Each distinct item's price is
  cached by item id (including a cached "no price available" verdict), so a
  given material costs **at most one** LibPrice call for the whole session.
  Repeat opens are effectively instant.
- **Incremental updates.** Depositing or withdrawing a stack while the bag is
  open updates only *that one slot's* contribution to the running total — an
  O(1) adjustment, never a full rescan.
- **Coalesced refreshes.** A burst of slot updates (e.g. dumping a 200-item
  stack, which fires many per-slot events) collapses into a single window
  redraw via a short debounce timer.
- **Empty-slot safe.** The Craft Bag keeps a slot around after its material is
  fully removed; every slot is guarded on stack size *and* item id before any
  pricing, so emptied slots never cause errors or phantom values.

### Robust categorization

Items are mapped to a crafting profession by their `ITEMTYPE_*`, resolved from
the game's own constants at load. Each constant is looked up by name and skipped
if a given client build doesn't define it, so an unexpected client never crashes
the addon — an unmapped material simply falls into "Other".

---

## Architecture at a glance

The addon is split into small, single-responsibility modules under one global
namespace, mirroring the structure of its sibling *Bureau of Acceptable Views*.

```
            Settings.lua          UI + SavedVariables
                 │
   BureauOfMaterialWorth.lua      Core: logging, chat, event wiring, slash command
                 │
        ┌────────┴────────┐
        ▼                 ▼
    Valuation.lua      Window.lua
  scan · price cache   the anchored panel
  category aggregates  (reads totals only)
```

- **`Valuation.lua`** owns all scanning, the per-item price cache, the per-slot
  contribution cache, and the running category/grand totals. It is the only
  module that touches LibPrice or the Craft Bag contents.
- **`Window.lua`** is pure presentation: it reads already-computed totals and
  lays out the panel. It never scans or prices anything.
- The **core** wires the Craft Bag fragment's visibility to the valuation and
  window, filters the inventory update event to the Craft Bag, and exposes the
  `/bmw` slash command via an O(1) dispatch table.

---

## Module overview

| Module | Responsibility |
| --- | --- |
| `BureauOfMaterialWorth.lua` | Core: logging, chat, event wiring, Craft Bag visibility, slash commands. |
| `Valuation.lua` | Craft Bag scan, LibPrice integration, price/slot caches, category aggregation. |
| `Window.lua` | The panel anchored to the Craft Bag; renders the total and category rows. |
| `Settings.lua` | SavedVariables, defaults, and the LibAddonMenu panel. |

---

## Slash commands

Everything the settings panel does is also reachable from chat.

```
/bmw                  Quick status (current Craft Bag value, debug level)
/bmw status           Same as above
/bmw refresh          Clear cached prices and recompute the value
/bmw settings         Open the settings panel  (aliases: /bmw ui, /bmw panel)
/bmw debug <0-4>      Set debug verbosity (off → verbose)
/bmw help             List all commands
```

---

## A note on AI assistance

During the development of this addon, the AI assistant Claude Opus 4.8 was
utilized in a strictly technical capacity. Its role was limited to debugging,
Lua optimization, performance tuning, and preventing potential memory leaks or
unsafe code practices. All AI-assisted code has been manually reviewed, tested,
and verified by the developer.

**P.S.** If the mere mention of AI makes you panic, this addon might not be for
you. Otherwise, rest assured: stability and performance are polished to the
highest standard, ensuring zero noticeable impact on your FPS or game memory.
