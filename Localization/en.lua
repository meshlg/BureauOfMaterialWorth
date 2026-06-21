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
    SI_BMW_SETTING_COLOR_SCALE_TOOLTIP = "Tint each category's gold figure by how large it is — dim for small amounts up to a hot color for the biggest — so your most valuable categories stand out at a glance. When off, all figures use the same gold tone.",
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

    -- Window: footer (two-column label -> value rows)
    SI_BMW_FOOTER_UPDATED_LABEL = "Updated",
    SI_BMW_FOOTER_COVERAGE_LABEL = "Coverage",
    SI_BMW_FOOTER_COVERAGE_VALUE = "%d/%d priced",
    SI_BMW_FOOTER_LOW_COVERAGE = "%d/%d unpriced!",
    SI_BMW_FOOTER_DELTA_LABEL = "This visit",
    SI_BMW_FOOTER_DELTA_LABEL_SESSION = "This session",
    SI_BMW_FOOTER_DELTA_VALUE = "%s gold",

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
