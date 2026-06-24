local strings = {
    -- Settings panel
    SI_BMW_PANEL_NAME = "Bureau of Material Worth",
    SI_BMW_PANEL_DISPLAY_NAME = "|c6FCB9FBureau|r of Material Worth",
    SI_BMW_PANEL_INTRO = "|c6FCB9FCraft Bag value at a glance.|r Bureau of Material Worth sums the market value of everything in your Craft Bag and shows it in a small panel beside the bag, with an optional breakdown by crafting profession.",
    SI_BMW_PANEL_OVERVIEW = "|c8C8A82• Uses LibPrice (Master Merchant / Tamriel Trade Centre / Arkadius' Trade Tools)\n• Computes lazily, only while the Craft Bag is open\n• Updates incrementally as you deposit or withdraw materials|r",

    SI_BMW_HEADER_DISPLAY = "|cC5C29EDisplay|r",
    SI_BMW_HEADER_DIAGNOSTICS = "|cC5C29EDiagnostics|r",

    SI_BMW_SETTING_CATEGORY_BREAKDOWN_NAME = "Show category breakdown",
    SI_BMW_SETTING_CATEGORY_BREAKDOWN_TOOLTIP = "Show per-profession subtotals (Blacksmithing, Alchemy, Provisioning, and so on) beneath the grand total. When off, only the grand total is shown.",
    SI_BMW_SETTING_CATEGORY_ICONS_NAME = "Show category icons",
    SI_BMW_SETTING_CATEGORY_ICONS_TOOLTIP = "Show a small profession icon to the left of each category name, so the rows are quicker to scan. \"Other\" has no profession and shows no icon.",
    SI_BMW_SETTING_COLOR_SCALE_NAME = "Color gold by value",
    SI_BMW_SETTING_COLOR_SCALE_TOOLTIP = "Tint each category's gold figure by how large it is - dim for small amounts up to a hot color for the biggest - so your most valuable categories stand out at a glance. When off, all figures use the same gold tone.",
    SI_BMW_SETTING_SORT_BY_VALUE_NAME = "Sort categories by value",
    SI_BMW_SETTING_SORT_BY_VALUE_TOOLTIP = "Order the category rows by descending gold value, so your most valuable holdings are always on top. When off, they follow the fixed profession order.",
    SI_BMW_SETTING_DELTA_MODE_NAME = "\"Since last visit\" baseline",
    SI_BMW_SETTING_DELTA_MODE_TOOLTIP = "What the footer's value-change line compares against. \"Each visit\": the previous time you opened the Craft Bag (persists across restarts). \"Each session\": the first time you opened it after logging in or reloading the UI, so the change accumulates until you log out or /reloadui. In both modes a pure price change (same materials, refreshed prices) shows no delta.",
    SI_BMW_SETTING_DELTA_MODE_VISIT = "Each visit",
    SI_BMW_SETTING_DELTA_MODE_SESSION = "Each session",
    SI_BMW_SETTING_BACKGROUND_NAME = "Show background",
    SI_BMW_SETTING_BACKGROUND_TOOLTIP = "Draw the dark panel background behind the text. Turn off for plain floating text over the Craft Bag.",
    SI_BMW_SETTING_BORDER_NAME = "Show border",
    SI_BMW_SETTING_BORDER_TOOLTIP = "Draw the panel's border edge. Turn off for a cleaner, frameless look.",
    SI_BMW_SETTING_VALUE_HISTORY_NAME = "Show value history",
    SI_BMW_SETTING_VALUE_HISTORY_TOOLTIP = "Draw a small sparkline of your Craft Bag's total value over time at the bottom of the panel. One point is recorded each time you open the Craft Bag (at most once every few hours), keeping the last 90 points. Hover the sparkline for the oldest, newest, and net-change figures.",
    SI_BMW_SETTING_NOTIFY_VISIT_NAME = "Announce value in chat",
    SI_BMW_SETTING_NOTIFY_VISIT_TOOLTIP = "Print your Craft Bag's value to chat the first time you open it each session, along with how much it changed since your last visit (when the stock changed). Turn off for no chat output.",
    SI_BMW_SETTING_WIDTH_NAME = "Window width",
    SI_BMW_SETTING_WIDTH_TOOLTIP = "Width of the value panel in pixels. Increase it if long category names or large gold figures look cramped.",
    SI_BMW_SETTING_OFFSET_X_NAME = "Horizontal offset",
    SI_BMW_SETTING_OFFSET_X_TOOLTIP = "Fine-tune the window's horizontal position relative to the Craft Bag panel.",
    SI_BMW_SETTING_OFFSET_Y_NAME = "Vertical offset",
    SI_BMW_SETTING_OFFSET_Y_TOOLTIP = "Fine-tune the window's vertical position relative to the Craft Bag panel.",
    SI_BMW_SETTING_DEBUG_MODE_NAME = "Debug mode",
    SI_BMW_SETTING_DEBUG_MODE_TOOLTIP = "Controls how much diagnostic output the addon prints to chat.",
    SI_BMW_SETTING_REFRESH_NAME = "Refresh prices now",
    SI_BMW_SETTING_REFRESH_TOOLTIP = "Clear the cached prices and recompute the Craft Bag value. Useful after Master Merchant or Tamriel Trade Centre finishes importing fresh data.",

    -- Window
    SI_BMW_WINDOW_TITLE = "Craft Bag Worth",
    -- %d = occupied slots (distinct materials), %s = classic 200-item stacks,
    -- %s = total item count.
    SI_BMW_WINDOW_SUBTITLE = "%d slots · %s stacks · %s items",
    SI_BMW_WINDOW_EMPTY = "Craft Bag is empty",
    -- Category row: the category's share of the grand total. %d = percent.
    SI_BMW_ROW_PERCENT = "%d%%",

    -- Window: per-category hover tooltip
    SI_BMW_TOOLTIP_VALUE = "Value: %s gold",
    SI_BMW_TOOLTIP_SLOTS = "Slots (distinct materials): %d",
    SI_BMW_TOOLTIP_STACKS = "Stacks of 200: %s",
    SI_BMW_TOOLTIP_ITEMS = "Items: %s",
    SI_BMW_TOOLTIP_UNPRICED = "Without price: %d slots",
    SI_BMW_TOOLTIP_CLICK_HINT = "Click for the full material list",

    -- Detail window: per-category material table (opened by clicking a row)
    SI_BMW_DETAIL_TITLE = "%s - materials",
    SI_BMW_DETAIL_COL_NAME = "Material",
    SI_BMW_DETAIL_COL_QTY = "Qty",
    SI_BMW_DETAIL_COL_VALUE = "Value",
    -- Cumulative-share column: running % of the list's total value, read top-down
    -- (the "what to sell" Pareto cue). Header kept short for the 70px column; the
    -- hover tooltip on the header spells the meaning out in full.
    SI_BMW_DETAIL_COL_CUM = "Cumul. %",
    SI_BMW_DETAIL_CUM = "%d%%",
    SI_BMW_DETAIL_CUM_TOOLTIP_TITLE = "Cumulative share",
    SI_BMW_DETAIL_CUM_TOOLTIP_BODY = "Each material's share of this list's total value, added up from the most valuable downward - so it stays the same no matter how you sort the table. Read it on the default |cFFF897by value|r view: the rows down to roughly 80% are the few stacks that hold most of the worth, so sell those first and skip the long tail. The trailing 100% always lands on the cheapest material. Unpriced materials are left out and show a dash.",
    SI_BMW_DETAIL_COL_CHANGE = "Change",
    -- Price-change magnitude; the sign is carried by an up/down arrow + color.
    -- %s = the percentage (one decimal place).
    SI_BMW_DETAIL_GROWTH = "%s%%",
    -- Shown when a material has no recorded price baseline yet, or no price.
    SI_BMW_DETAIL_GROWTH_NEW = "-",
    SI_BMW_DETAIL_EMPTY = "No materials in this category.",
    -- Search box (whole craft bag) in the detail window.
    SI_BMW_DETAIL_SEARCH_HINT = "Search...",
    SI_BMW_DETAIL_SEARCH_TITLE = "Search results",

    -- Snapshot + diff view (detail window). "Remember" freezes the current bag
    -- composition; "Changes" diffs the live bag against it. One snapshot, manual,
    -- overwritten on each Remember - the tooltips spell that out since it is not
    -- otherwise discoverable.
    SI_BMW_DETAIL_BTN_REMEMBER = "Remember",
    SI_BMW_DETAIL_BTN_REMEMBER_TOOLTIP_TITLE = "Remember composition",
    SI_BMW_DETAIL_BTN_REMEMBER_TOOLTIP_BODY = "Manually save a snapshot of the Craft Bag's current contents. Press \"Changes\" later to see what was added, removed, or changed since. There is one snapshot - pressing this again overwrites it.",
    SI_BMW_DETAIL_BTN_CHANGES = "Changes",
    SI_BMW_DETAIL_BTN_CHANGES_TOOLTIP_TITLE = "Changes since snapshot",
    SI_BMW_DETAIL_BTN_CHANGES_TOOLTIP_BODY = "Show how the Craft Bag has changed since your saved snapshot: which materials were added, removed, or changed in quantity, and the gold value of each move. Press \"Remember\" first to take a snapshot.",
    -- In the diff view the "Changes" button becomes a "Back" toggle that returns
    -- to the material list.
    SI_BMW_DETAIL_BTN_BACK = "Back",
    SI_BMW_DETAIL_BTN_BACK_TOOLTIP_TITLE = "Back to materials",
    SI_BMW_DETAIL_BTN_BACK_TOOLTIP_BODY = "Return from the changes view to the material list.",
    -- Diff title; %s = relative time of the snapshot (e.g. "5m ago").
    SI_BMW_DETAIL_DIFF_TITLE = "Changes since %s",
    SI_BMW_DETAIL_DIFF_EMPTY = "Nothing changed since the snapshot.",
    SI_BMW_DETAIL_NO_SNAPSHOT = "No snapshot yet. Press Remember.",
    -- Diff column headers. ASCII "+/-" rather than a Unicode delta glyph, which
    -- the UI font will not render (same reason the addon uses arrow textures).
    SI_BMW_DETAIL_COL_QTY_DELTA = "Qty +/-",
    SI_BMW_DETAIL_COL_VALUE_DELTA = "Value +/-",
    SI_BMW_DETAIL_COL_SHARE = "Share",
    SI_BMW_DETAIL_COL_STATUS = "Status",
    -- Per-row status word in the diff's repurposed Change column.
    SI_BMW_DETAIL_STATUS_NEW = "new",
    SI_BMW_DETAIL_STATUS_GONE = "gone",
    SI_BMW_DETAIL_STATUS_CHANGED = "changed",
    -- Signed integer for the Qty delta column; %s carries the sign (+/-).
    SI_BMW_DETAIL_QTY_DELTA = "%s%s",

    -- Withdraw dialog: opened by clicking a material row, moves the material out
    -- of the Craft Bag into the backpack.
    SI_BMW_WITHDRAW_TITLE = "Withdraw %s",
    SI_BMW_WITHDRAW_FREE_SLOTS = "Free backpack slots: %d",
    SI_BMW_WITHDRAW_MAX = "Max withdrawable: %s",
    -- %s already carries the gold icon (see FormatGold).
    SI_BMW_WITHDRAW_TOTAL_VALUE = "Total value: %s",
    SI_BMW_WITHDRAW_QTY_LABEL = "Quantity",
    -- Preset buttons. The plain counts (1/10/100) show the number itself; the
    -- stack presets use these so "200" reads as "1 stack", "2000" as "10 stacks".
    SI_BMW_WITHDRAW_PRESET_STACK = "%d stack",
    SI_BMW_WITHDRAW_PRESET_STACKS = "%d stacks",
    SI_BMW_WITHDRAW_CONFIRM = "Withdraw",
    SI_BMW_WITHDRAW_CANCEL = "Cancel",
    SI_BMW_WITHDRAW_BACKPACK_FULL = "Backpack is full",
    -- Live progress while a multi-stack withdrawal runs. %d / %d = moved / total.
    SI_BMW_WITHDRAW_PROGRESS = "Withdrawing... %d / %d",
    -- Hint shown when hovering a detail row: how the two mouse buttons act.
    SI_BMW_WITHDRAW_HINT = "LMB: withdraw    RMB: add to queue",

    -- Withdraw queue: the multi-material list, anchored beside the detail window.
    SI_BMW_QUEUE_TITLE = "Withdraw queue",
    SI_BMW_QUEUE_EMPTY = "Right-click materials to queue them.",
    -- Footer summary. %d = slots the queue needs, %d = free backpack slots.
    SI_BMW_QUEUE_SLOTS = "Needs %d slots / %d free",
    SI_BMW_QUEUE_TOTAL = "Queue value: %s",
    SI_BMW_QUEUE_WITHDRAW_ALL = "Withdraw all",
    SI_BMW_QUEUE_CLEAR = "Clear",

    -- Window: footer (two-column label -> value rows)
    SI_BMW_FOOTER_UPDATED_LABEL = "Updated",
    SI_BMW_FOOTER_COVERAGE_LABEL = "Coverage",
    SI_BMW_FOOTER_COVERAGE_VALUE = "%d/%d priced",
    SI_BMW_FOOTER_LOW_COVERAGE = "%d/%d unpriced!",
    SI_BMW_FOOTER_DELTA_LABEL = "This visit",
    SI_BMW_FOOTER_DELTA_LABEL_SESSION = "This session",
    SI_BMW_FOOTER_DELTA_VALUE = "%s gold",
    -- Value-history sparkline caption + hover tooltip.
    SI_BMW_FOOTER_HISTORY_LABEL = "Value history",
    SI_BMW_HISTORY_TOOLTIP_POINTS = "Recorded points: %d",
    SI_BMW_HISTORY_TOOLTIP_OLDEST = "Oldest: %s gold",
    SI_BMW_HISTORY_TOOLTIP_NEWEST = "Newest: %s gold",
    SI_BMW_HISTORY_TOOLTIP_CHANGE = "Change: %s gold",

    -- Window: relative time
    SI_BMW_TIME_NEVER = "never",
    SI_BMW_TIME_JUST_NOW = "just now",
    SI_BMW_TIME_SECONDS = "%ds ago",
    SI_BMW_TIME_MINUTES = "%dm ago",
    SI_BMW_TIME_HOURS = "%dh ago",

    -- Material categories
    SI_BMW_CATEGORY_BLACKSMITHING = "Blacksmithing",
    SI_BMW_CATEGORY_CLOTHIER = "Clothier",
    SI_BMW_CATEGORY_WOODWORKING = "Woodworking",
    SI_BMW_CATEGORY_JEWELRY = "Jewelry Crafting",
    SI_BMW_CATEGORY_ALCHEMY = "Alchemy",
    SI_BMW_CATEGORY_ENCHANTING = "Enchanting",
    SI_BMW_CATEGORY_PROVISIONING = "Provisioning",
    SI_BMW_CATEGORY_OTHER = "Other",

    -- Booleans
    SI_BMW_BOOL_TRUE = "true",
    SI_BMW_BOOL_FALSE = "false",

    -- Debug level names (index = level)
    SI_BMW_DEBUG_LEVEL_OFF = "Off",
    SI_BMW_DEBUG_LEVEL_ERRORS = "Errors",
    SI_BMW_DEBUG_LEVEL_WARNINGS = "Warnings",
    SI_BMW_DEBUG_LEVEL_INFO = "Info",
    SI_BMW_DEBUG_LEVEL_VERBOSE = "Verbose",

    -- Log level prefixes
    SI_BMW_LOG_LEVEL_ERROR = "|cFF0000[ERROR]|r",
    SI_BMW_LOG_LEVEL_WARN = "|cFFAA00[WARN]|r",
    SI_BMW_LOG_LEVEL_INFO = "|c00FF00[INFO]|r",
    SI_BMW_LOG_LEVEL_DEBUG = "|c999999[DEBUG]|r",

    -- Log messages
    SI_BMW_LOG_ONADDONLOADED_LOADING = "Loading version %s...",
    SI_BMW_LOG_ADDON_LOADED = "Addon loaded.",
    SI_BMW_LOG_CRAFTBAG_SHOWN = "Craft Bag shown.",
    SI_BMW_LOG_CRAFTBAG_HIDDEN = "Craft Bag hidden.",
    SI_BMW_LOG_RESCAN_DONE = "Full rescan complete: %d slots, total %s gold.",
    SI_BMW_LOG_SLOT_UPDATED = "Slot %d updated (contribution %s gold).",
    SI_BMW_LOG_LAM_MISSING = "LibAddonMenu-2.0 not found; settings panel unavailable.",

    -- Chat messages
    SI_BMW_MSG_LIBPRICE_MISSING = "LibPrice is not installed. Bureau of Material Worth needs LibPrice (and a price source such as Master Merchant or Tamriel Trade Centre) to work.",
    SI_BMW_MSG_VERSION_DEBUG = "Version %s | Debug: %s (%d)",
    SI_BMW_MSG_STATUS_TOTAL = "Craft Bag value: %s gold.",
    SI_BMW_MSG_STATUS_SLOTS = "Priced slots: %d | unpriced slots: %d.",
    -- First-open-of-session announcement. _DELTA: %s sign (+/-), %s change
    -- magnitude, %s current total. _TOTAL: %s current total (no known change).
    SI_BMW_MSG_VISIT_DELTA = "Craft Bag is worth %s gold (%s%s since last visit).",
    SI_BMW_MSG_VISIT_TOTAL = "Craft Bag is worth %s gold.",
    SI_BMW_MSG_REFRESH_DONE = "Prices refreshed.",
    SI_BMW_MSG_DEBUG_MODE_SET = "Debug mode set to %s (%d).",
    SI_BMW_MSG_INVALID_DEBUG_LEVEL = "Invalid debug level. Use a number from 0 to 4.",
    SI_BMW_MSG_SETTINGS_UNAVAILABLE = "Settings panel is unavailable (LibAddonMenu-2.0 not found).",
    SI_BMW_MSG_UNKNOWN_COMMAND = "Unknown command. Type /bmw help for the command list.",

    -- Slash command help
    SI_BMW_MSG_HELP_TITLE = "|cC5C29EBureau of Material Worth commands:|r",
    SI_BMW_MSG_HELP_STATUS = "|cFFFFFF/bmw status|r - show the current Craft Bag value.",
    SI_BMW_MSG_HELP_REFRESH = "|cFFFFFF/bmw refresh|r - clear cached prices and recompute.",
    SI_BMW_MSG_HELP_SETTINGS = "|cFFFFFF/bmw settings|r - open the settings panel.",
    SI_BMW_MSG_HELP_DEBUG = "|cFFFFFF/bmw debug <0-4>|r - set chat debug verbosity.",
    SI_BMW_MSG_HELP_HELP = "|cFFFFFF/bmw help|r - show this command list.",
}

for stringId, value in pairs(strings) do
    ZO_CreateStringId(stringId, value)
end
