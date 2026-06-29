local addon = BureauOfMaterialWorth
addon.Window = addon.Window or {}

local Window = addon.Window
local private = addon.private

local GetString = GetString
local stringformat = string.format
local zo_round = zo_round
local mathabs = math.abs

-- Palette (shared with the rest of the Bureau house style)
-- ---------------------------------------------------------------------------
local COLOR_ACCENT   = "6FCB9F"  -- brand green: title + grand total
local COLOR_MUTED    = "8C8A82"  -- dim grey: subtitle + footer
local COLOR_NAME     = "DBD9D0"  -- near-white: category names
local COLOR_GOLD     = "F4D03F"  -- soft gold: gold figures
local COLOR_WARN     = "D0905E"  -- amber: "missing price" hint
local COLOR_GAIN     = "8FCB9F"  -- green: positive since-last-visit delta
local COLOR_LOSS     = "D08A8A"  -- soft red: negative since-last-visit delta

-- Layout constants
-- ---------------------------------------------------------------------------
-- A slim panel anchored beside the craft bag. It sizes itself to its content:
-- a title, a prominent grand total, a subtitle, a divider, one row per non-empty
-- category, another divider, then a two-line footer. Category rows are two
-- columns (name left, gold right) so the figures line up.
--
-- The width is user-configurable (see Settings); DEFAULT_WINDOW_WIDTH is the
-- fallback when no value is saved, and MIN/MAX/STEP bound the slider. Every
-- width-dependent control reads CurrentWidth() so a width change can be
-- re-applied at runtime without recreating controls.
local DEFAULT_WINDOW_WIDTH = 400
local MIN_WINDOW_WIDTH = 400
local MAX_WINDOW_WIDTH = 600
local WINDOW_WIDTH_STEP = 10
local PADDING        = 12
local TITLE_HEIGHT   = 22
local TOTAL_HEIGHT   = 30
local SUBTITLE_HEIGHT = 18
local ROW_HEIGHT     = 22
local DIVIDER_GAP    = 10   -- vertical space a divider occupies
local FOOTER_LINE    = 16
local SECTION_GAP    = 6    -- small gap between blocks
local BG_ALPHA       = 0.82
local EDGE_ALPHA     = 0.9  -- border opacity when the border is shown

-- Value-history area chart geometry. The chart is a filled silhouette: one
-- vertical bar per sample, drawn edge-to-edge (no gap) so the samples read as a
-- continuous shape rather than separate bars. Bars are CT_BACKDROP fills -- the
-- same primitive the window background uses -- because the UI font can't render
-- the Unicode block glyphs a text chart would need (see the arrow note above).
-- The whole fill is tinted by the series' overall direction (green when the
-- newest sample sits above the oldest, red when below), with the newest bar
-- brightened so "now" stands out. A head line above carries the current value +
-- trend arrow; a scale line below carries the series min and max. SPARK_MIN_BAR_H
-- keeps the lowest sample a visible sliver rather than nothing.
local SPARK_HEIGHT     = 40  -- area-strip height in px (head line above, scale below)
local SPARK_MIN_BAR_H  = 2   -- floor height so the minimum sample still draws
local SPARK_SCALE_GAP  = 2   -- gap between the strip and the min/max scale line
-- Area fill + "now" highlight, tinted by trend. RGBA floats (CT_BACKDROP wants
-- components, not the hex the labels use). The fill is semi-transparent so it
-- reads as an area wash; the newest bar is opaque and brighter to mark "now".
local SPARK_AREA_UP       = { 0.42, 0.62, 0.47, 0.80 }  -- rising: green fill
local SPARK_AREA_UP_NOW   = { 0.56, 0.85, 0.62, 1.00 }
local SPARK_AREA_DOWN     = { 0.62, 0.42, 0.42, 0.80 }  -- falling: red fill
local SPARK_AREA_DOWN_NOW = { 0.85, 0.56, 0.56, 1.00 }

-- Expose the width bounds so the settings slider stays in sync with the layout.
Window.DEFAULT_WIDTH = DEFAULT_WINDOW_WIDTH
Window.MIN_WIDTH = MIN_WINDOW_WIDTH
Window.MAX_WIDTH = MAX_WINDOW_WIDTH
Window.WIDTH_STEP = WINDOW_WIDTH_STEP

local GOLD_ICON = "|t16:16:EsoUI/Art/currency/currency_gold.dds|t"

-- Guild-store selling fees live in the core (private.FEE_*), the single source of
-- truth shared with the detail window. Bound to locals here for the grand-total
-- "net if sold" hover; see private.NetAfterFees for the rationale and rates.
local FEE_LISTING_RATE = private.FEE_LISTING_RATE
local FEE_SALES_RATE   = private.FEE_SALES_RATE

-- Up/down arrows for the value-change delta. We use the game's own sort-arrow
-- textures rather than the Unicode ▲/▼ glyphs because the ESO UI font does not
-- render those reliably (they often show as blank or tofu). Inline textures
-- always draw, matching how the gold icon is embedded above.
local ARROW_UP = "|t16:16:EsoUI/Art/Miscellaneous/list_sortUp.dds|t"
local ARROW_DOWN = "|t16:16:EsoUI/Art/Miscellaneous/list_sortDown.dds|t"

-- Per-category profession icons, keyed by the category ids in Valuation's
-- CATEGORY_DEFINITIONS. We use the game's "mapkey" crafting icons (the same set
-- the crafting-writ addons use), which are clean monochrome glyphs that read
-- well at small sizes. "other" is not a profession, so it gets the generic
-- craft-bag icon rather than being left blank.
local CATEGORY_ICONS = {
    blacksmithing = "esoui/art/icons/mapkey/mapkey_smithy.dds",
    clothier      = "esoui/art/icons/mapkey/mapkey_clothier.dds",
    woodworking   = "esoui/art/icons/mapkey/mapkey_woodworker.dds",
    jewelry       = "esoui/art/icons/mapkey/mapkey_jewelrycrafting.dds",
    alchemy       = "esoui/art/icons/mapkey/mapkey_alchemist.dds",
    enchanting    = "esoui/art/icons/mapkey/mapkey_enchanter.dds",
    provisioning  = "esoui/art/icons/mapkey/mapkey_inn.dds",
    other         = "esoui/art/inventory/inventory_tabicon_craftbag_up.dds",
}

-- Inline icon markup for a category, or empty string when it has none.
local function CategoryIcon(categoryId)
    local path = CATEGORY_ICONS[categoryId]
    if not path then
        return ""
    end
    return "|t18:18:" .. path .. "|t "
end

local function Colorize(hex, text)
    return stringformat("|c%s%s|r", hex, text)
end

-- Magnitude tint for gold figures. Deliberately SUBTLE: every tier stays within
-- the gold family and only shifts brightness/warmth a touch, so larger amounts
-- read as a slightly richer gold rather than changing color outright (no red).
-- A value lands in the highest tier whose floor it meets.
local GOLD_SCALE = {
    { floor = 10000000, color = "FFE9A0" },  -- 10M+  : bright warm gold
    { floor =  1000000, color = "F7DA63" },  -- 1M+   : rich gold
    { floor =   100000, color = "F4D03F" },  -- 100k+ : base gold tone
    { floor =    10000, color = "D8BF52" },  -- 10k+  : slightly muted gold
    { floor =        0, color = "B6A668" },  -- <10k  : dim gold
}

local function GoldScaleColor(amount)
    amount = amount or 0
    for i = 1, #GOLD_SCALE do
        if amount >= GOLD_SCALE[i].floor then
            return GOLD_SCALE[i].color
        end
    end
    return COLOR_GOLD
end

-- Format a gold amount with thousands separators + the gold icon, matching the
-- presentation used in LibPrice's own example output. An optional hex color
-- overrides the default gold tone (used by the magnitude color scale).
local function FormatGold(amount, colorOverride)
    return Colorize(colorOverride or COLOR_GOLD,
        ZO_LocalizeDecimalNumber(zo_round(amount or 0))) .. " " .. GOLD_ICON
end

-- "How long ago" for the footer, from a game-time-ms stamp to a short localized
-- phrase. Coarse buckets (now / seconds / minutes / hours) -- this is a feel,
-- not a stopwatch.
local function FormatTimeAgo(stampMs)
    if not stampMs then
        return GetString(SI_BMW_TIME_NEVER)
    end

    local deltaMs = GetGameTimeMilliseconds() - stampMs
    local seconds = zo_round(deltaMs / 1000)
    if seconds < 5 then
        return GetString(SI_BMW_TIME_JUST_NOW)
    elseif seconds < 60 then
        return stringformat(GetString(SI_BMW_TIME_SECONDS), seconds)
    elseif seconds < 3600 then
        return stringformat(GetString(SI_BMW_TIME_MINUTES), zo_round(seconds / 60))
    else
        return stringformat(GetString(SI_BMW_TIME_HOURS), zo_round(seconds / 3600))
    end
end

-- The account-and-character identity shown on the right of the title line. The
-- Craft Bag is account-wide, so the @account handle is the identity the bag
-- actually belongs to; the current character name is appended for a touch of
-- profile flavor. Both are stable for the session, so this is read once on the
-- first render and cached. GetDisplayName returns the "@handle"; GetUnitName
-- ("player") the character. A "·" joins them, matching the addon's separator.
local cachedProfileText
local function GetProfileText()
    if cachedProfileText then
        return cachedProfileText
    end
    local account = GetDisplayName() or ""
    local character = zo_strformat(SI_UNIT_NAME, GetUnitName("player")) or ""
    if account ~= "" and character ~= "" then
        cachedProfileText = stringformat(GetString(SI_BMW_PROFILE_ACCOUNT_CHAR), account, character)
    else
        -- Fall back to whichever is available rather than an empty/orphaned "·".
        cachedProfileText = account ~= "" and account or character
    end
    return cachedProfileText
end

-- Runtime control references, created once in Initialize().
local windowControl   -- top-level container
local backdrop        -- background + border fill (toggled by appearance settings)
local titleLabel      -- "Craft Bag Worth"
local profileLabel    -- "@account · Character" on the right of the title line
local totalLabel      -- prominent grand-total gold figure
local subtitleLabel   -- "<n> slots · <n> stacks · <n> items"
local dividerTop      -- line under the header block
local dividerBottom   -- line above the footer
-- Footer rows are two-column (muted label left, value right), mirroring the
-- category rows above. Each is a { container, label, value } record.
local footerUpdatedRow  -- "Updated" -> "<ago>"
local footerPricesRow   -- "Coverage" -> "<n>/<n> · <source>" (or a warning)
local footerDeltaRow    -- "This visit"/"This session" -> "▲ <gold>" (hidden when none)
-- Value-history area chart: a caption label, a head line (current value + trend
-- arrow) on the right of the caption, a container holding pooled bar controls
-- that form the filled silhouette, and a scale line beneath carrying the series
-- min and max. Bars are created on demand and reused across renders (like the
-- category rows), so a refresh re-points them instead of churning controls.
local sparkCaption      -- muted "Value history" caption above the strip
local sparkHeadLabel    -- current value + trend arrow, right-aligned on the caption row
local sparkContainer    -- holds the filled strip; anchors the per-sample bars
local sparkScaleLabel   -- "min … max" scale line beneath the strip
local sparkBars = {}    -- pooled CT_BACKDROP bars, index 1..N
local rowPool         -- reusable category rows { container, name, gold, data }

-- Footer "updated X ago" should feel live even when nothing else changes, so a
-- low-frequency tick re-renders just the footer text while the window is shown.
-- It runs ONLY while visible and touches one label, so the cost is negligible
-- and there is nothing on the per-frame path.
local FOOTER_TICK_MS = 5000
local FOOTER_TIMER_NAME = addon.name .. "_FooterTick"
local lastSnapshot  -- cached snapshot so the footer tick can re-read counts/time

local function GetSavedVars()
    return private.savedVars or {}
end

-- The window anchors to the left edge of the Craft Bag. In the guild store the
-- trading house's own browse pane (ZO_TradingHouseBrowseItemsLeftPane, ~265px)
-- sits in exactly that space, so the panel lands on top of it. When the trading
-- house scene is up we shift the window an extra amount left so it clears that
-- pane: the pane width plus a small gap, on top of the user's configured offset.
local GUILD_STORE_OFFSET_X = -375

local function IsGuildStoreShowing()
    return TRADING_HOUSE_SCENE ~= nil and TRADING_HOUSE_SCENE:IsShowing()
end

-- The configured window width, clamped to the supported range and snapped to the
-- slider step, with a safe fallback when nothing is saved yet. Every
-- width-dependent control reads this so a settings change re-flows consistently.
local function CurrentWidth()
    local width = GetSavedVars().windowWidth or DEFAULT_WINDOW_WIDTH
    if width < MIN_WINDOW_WIDTH then
        width = MIN_WINDOW_WIDTH
    elseif width > MAX_WINDOW_WIDTH then
        width = MAX_WINDOW_WIDTH
    end
    return width
end

local function CreateDivider(name)
    local divider = WINDOW_MANAGER:CreateControl(name, windowControl, CT_TEXTURE)
    divider:SetTexture("EsoUI/Art/Miscellaneous/horizontalDivider.dds")
    divider:SetWidth(CurrentWidth() - PADDING * 2)
    divider:SetHeight(4)
    divider:SetColor(1, 1, 1, 0.4)
    return divider
end

-- Build a two-column footer row (muted label left, value right), mirroring the
-- category-row layout so the footer reads as part of the same table. Returns a
-- { container, label, value } record; widths track CurrentWidth() and are
-- re-applied by Window.ApplyWidth().
local function CreateFooterRow(name)
    local container = WINDOW_MANAGER:CreateControl(name, windowControl, CT_CONTROL)
    container:SetWidth(CurrentWidth() - PADDING * 2)
    container:SetHeight(FOOTER_LINE)

    local label = WINDOW_MANAGER:CreateControl(nil, container, CT_LABEL)
    label:SetFont("ZoFontGameSmall")
    label:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
    label:SetVerticalAlignment(TEXT_ALIGN_CENTER)
    label:SetAnchor(LEFT, container, LEFT, 0, 0)
    label:SetWidth(CurrentWidth() * 0.4)

    local value = WINDOW_MANAGER:CreateControl(nil, container, CT_LABEL)
    value:SetFont("ZoFontGameSmall")
    value:SetHorizontalAlignment(TEXT_ALIGN_RIGHT)
    value:SetVerticalAlignment(TEXT_ALIGN_CENTER)
    value:SetAnchor(RIGHT, container, RIGHT, 0, 0)
    value:SetWidth(CurrentWidth() * 0.6 - PADDING)

    return { container = container, label = label, value = value }
end

-- Build (or fetch from the pool) the Nth category row. Each row is a mouse-
-- enabled container with a left name label and a right gold label; the
-- container carries the row's data and shows a detail tooltip on hover. Rows
-- are pooled and reused across renders so a refresh never churns controls.
local function AcquireRow(index)
    local existing = rowPool[index]
    if existing then
        return existing
    end

    local container = WINDOW_MANAGER:CreateControl(
        addon.name .. "_Row" .. index, windowControl, CT_CONTROL)
    container:SetWidth(CurrentWidth() - PADDING * 2)
    container:SetHeight(ROW_HEIGHT)
    container:SetMouseEnabled(true)

    local nameLabel = WINDOW_MANAGER:CreateControl(nil, container, CT_LABEL)
    nameLabel:SetFont("ZoFontGame")
    nameLabel:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
    nameLabel:SetVerticalAlignment(TEXT_ALIGN_CENTER)
    nameLabel:SetAnchor(LEFT, container, LEFT, 0, 0)
    nameLabel:SetWidth(CurrentWidth() * 0.5)

    local goldLabel = WINDOW_MANAGER:CreateControl(nil, container, CT_LABEL)
    goldLabel:SetFont("ZoFontGame")
    goldLabel:SetHorizontalAlignment(TEXT_ALIGN_RIGHT)
    goldLabel:SetVerticalAlignment(TEXT_ALIGN_CENTER)
    goldLabel:SetAnchor(RIGHT, container, RIGHT, 0, 0)
    goldLabel:SetWidth(CurrentWidth() * 0.5 - PADDING)

    local row = { container = container, name = nameLabel, gold = goldLabel }

    -- Hover: a standard InformationTooltip with the per-category detail. Anchored
    -- to the left of the row since the window itself sits left of the craft bag.
    container:SetHandler("OnMouseEnter", function(self)
        local data = row.data
        if not data then
            return
        end
        InitializeTooltip(InformationTooltip, self, TOPRIGHT, -6, 0, BOTTOMRIGHT)
        InformationTooltip:AddLine(data.name, "ZoFontHeader2",
            ZO_NORMAL_TEXT:UnpackRGB())
        ZO_Tooltip_AddDivider(InformationTooltip)
        InformationTooltip:AddLine(stringformat(GetString(SI_BMW_TOOLTIP_VALUE),
            ZO_LocalizeDecimalNumber(zo_round(data.gold))), "ZoFontGame", 1, 0.82, 0.25)
        -- Net if sold through a guild trader (after the 1% + 7% fees). Only shown
        -- when there's a value to net down; the muted green marks it as the
        -- take-home figure, matching the grand-total hover.
        if data.gold and data.gold > 0 then
            InformationTooltip:AddLine(stringformat(GetString(SI_BMW_TOOLTIP_NET),
                ZO_LocalizeDecimalNumber(zo_round(private.NetAfterFees(data.gold)))),
                "ZoFontGame", 0.44, 0.80, 0.62)
        end
        InformationTooltip:AddLine(stringformat(GetString(SI_BMW_TOOLTIP_SLOTS),
            data.slots), "ZoFontGame", 0.86, 0.85, 0.78)
        InformationTooltip:AddLine(stringformat(GetString(SI_BMW_TOOLTIP_STACKS),
            ZO_LocalizeDecimalNumber(data.stacks)), "ZoFontGame", 0.86, 0.85, 0.78)
        InformationTooltip:AddLine(stringformat(GetString(SI_BMW_TOOLTIP_ITEMS),
            ZO_LocalizeDecimalNumber(data.items)), "ZoFontGame", 0.86, 0.85, 0.78)
        if data.unpricedSlots > 0 then
            InformationTooltip:AddLine(stringformat(GetString(SI_BMW_TOOLTIP_UNPRICED),
                data.unpricedSlots), "ZoFontGame", 0.82, 0.56, 0.37)
        end
        -- Hint that the row is clickable for the full per-material breakdown.
        ZO_Tooltip_AddDivider(InformationTooltip)
        InformationTooltip:AddLine(GetString(SI_BMW_TOOLTIP_CLICK_HINT),
            "ZoFontGameSmall", 0.55, 0.79, 0.62)
    end)
    container:SetHandler("OnMouseExit", function()
        ClearTooltip(InformationTooltip)
    end)

    -- Click opens the per-category material detail window. CT_CONTROL containers
    -- don't fire OnClicked, so use OnMouseUp gated on the release landing inside.
    container:SetHandler("OnMouseUp", function(self, button, upInside)
        if button ~= MOUSE_BUTTON_INDEX_LEFT or not upInside then
            return
        end
        local data = row.data
        if not data then
            return
        end
        local detail = addon.DetailWindow
        if detail then
            detail.Show(data.id, data.name)
        end
    end)

    rowPool[index] = row
    return row
end

function Window.Initialize()
    if windowControl then
        return
    end

    rowPool = {}

    windowControl = WINDOW_MANAGER:CreateTopLevelWindow(addon.name .. "_Window")
    windowControl:SetClampedToScreen(true)
    windowControl:SetDimensions(CurrentWidth(), 120)
    windowControl:SetHidden(true)
    windowControl:SetMouseEnabled(true)  -- so category rows can receive hover

    Window.ApplyAnchor()

    backdrop = WINDOW_MANAGER:CreateControl(addon.name .. "_Backdrop", windowControl, CT_BACKDROP)
    backdrop:SetAnchorFill(windowControl)
    backdrop:SetEdgeTexture("", 1, 1, 1)
    backdrop:SetInsets(2, 2, -2, -2)
    Window.ApplyAppearance()

    titleLabel = WINDOW_MANAGER:CreateControl(addon.name .. "_Title", windowControl, CT_LABEL)
    titleLabel:SetFont("ZoFontWinH4")
    titleLabel:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
    titleLabel:SetAnchor(TOPLEFT, windowControl, TOPLEFT, PADDING, PADDING)
    titleLabel:SetText(Colorize(COLOR_ACCENT, GetString(SI_BMW_WINDOW_TITLE)))

    -- Account/character identity on the right of the title line, in the gap beside
    -- the short title. Right-aligned and ellipsized so a long handle never collides
    -- with the title; vertically centered on the title's row. Filled and shown/
    -- hidden by Window.Update per the showProfile setting.
    profileLabel = WINDOW_MANAGER:CreateControl(addon.name .. "_Profile", windowControl, CT_LABEL)
    profileLabel:SetFont("ZoFontGameSmall")
    profileLabel:SetHorizontalAlignment(TEXT_ALIGN_RIGHT)
    profileLabel:SetVerticalAlignment(TEXT_ALIGN_CENTER)
    profileLabel:SetMaxLineCount(1)
    profileLabel:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
    profileLabel:SetAnchor(TOPRIGHT, windowControl, TOPRIGHT, -PADDING, PADDING)
    -- Leave room for the title on the left so the two never overlap; the title is
    -- short ("Craft Bag Worth"), so the right ~55% is free for the handle.
    profileLabel:SetWidth(CurrentWidth() * 0.55)
    profileLabel:SetHeight(TITLE_HEIGHT)

    totalLabel = WINDOW_MANAGER:CreateControl(addon.name .. "_Total", windowControl, CT_LABEL)
    totalLabel:SetFont("ZoFontWinH1")
    totalLabel:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
    totalLabel:SetAnchor(TOPLEFT, titleLabel, BOTTOMLEFT, 0, SECTION_GAP)
    -- Hover the grand total for the "net if sold" breakdown: the guild-store
    -- listing fee (1%) and sales tax (7%) itemized, then the gold left after both.
    -- The Craft Bag total is valued at market/list price, so this answers "what
    -- would I actually pocket selling all of this through a guild trader".
    totalLabel:SetMouseEnabled(true)
    totalLabel:SetHandler("OnMouseEnter", function(self)
        local gross = lastSnapshot and lastSnapshot.gold or 0
        if gross <= 0 then
            return
        end
        local listing = gross * FEE_LISTING_RATE
        local sales = gross * FEE_SALES_RATE
        local net = gross - listing - sales

        InitializeTooltip(InformationTooltip, self, TOPLEFT, 0, 6, BOTTOMLEFT)
        InformationTooltip:AddLine(GetString(SI_BMW_NET_TOOLTIP_TITLE), "ZoFontHeader2",
            ZO_NORMAL_TEXT:UnpackRGB())
        ZO_Tooltip_AddDivider(InformationTooltip)
        -- Gross (list price), then each fee as a negative, then the net.
        InformationTooltip:AddLine(stringformat(GetString(SI_BMW_NET_TOOLTIP_GROSS),
            ZO_LocalizeDecimalNumber(zo_round(gross))), "ZoFontGame", 0.86, 0.85, 0.78)
        InformationTooltip:AddLine(stringformat(GetString(SI_BMW_NET_TOOLTIP_LISTING),
            ZO_LocalizeDecimalNumber(zo_round(listing))), "ZoFontGame", 0.82, 0.56, 0.37)
        InformationTooltip:AddLine(stringformat(GetString(SI_BMW_NET_TOOLTIP_SALES),
            ZO_LocalizeDecimalNumber(zo_round(sales))), "ZoFontGame", 0.82, 0.56, 0.37)
        ZO_Tooltip_AddDivider(InformationTooltip)
        InformationTooltip:AddLine(stringformat(GetString(SI_BMW_NET_TOOLTIP_NET),
            ZO_LocalizeDecimalNumber(zo_round(net))), "ZoFontGame", 0.44, 0.80, 0.62)
    end)
    totalLabel:SetHandler("OnMouseExit", function()
        ClearTooltip(InformationTooltip)
    end)

    subtitleLabel = WINDOW_MANAGER:CreateControl(addon.name .. "_Subtitle", windowControl, CT_LABEL)
    subtitleLabel:SetFont("ZoFontGameSmall")
    subtitleLabel:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
    subtitleLabel:SetAnchor(TOPLEFT, totalLabel, BOTTOMLEFT, 0, 2)

    dividerTop = CreateDivider(addon.name .. "_DividerTop")
    dividerBottom = CreateDivider(addon.name .. "_DividerBottom")

    footerUpdatedRow = CreateFooterRow(addon.name .. "_FooterUpdated")
    footerPricesRow = CreateFooterRow(addon.name .. "_FooterPrices")
    footerDeltaRow = CreateFooterRow(addon.name .. "_FooterDelta")

    -- Value-history area chart: a muted caption with a filled strip beneath it,
    -- a current-value + trend head on the caption row, and a min/max scale line
    -- below. The bars themselves are created lazily by RenderSparkline so the
    -- strip is sized to whatever data exists.
    sparkCaption = WINDOW_MANAGER:CreateControl(addon.name .. "_SparkCaption", windowControl, CT_LABEL)
    sparkCaption:SetFont("ZoFontGameSmall")
    sparkCaption:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
    sparkCaption:SetVerticalAlignment(TEXT_ALIGN_CENTER)

    -- Current value + trend arrow, right-aligned to sit opposite the caption.
    sparkHeadLabel = WINDOW_MANAGER:CreateControl(addon.name .. "_SparkHead", windowControl, CT_LABEL)
    sparkHeadLabel:SetFont("ZoFontGameSmall")
    sparkHeadLabel:SetHorizontalAlignment(TEXT_ALIGN_RIGHT)
    sparkHeadLabel:SetVerticalAlignment(TEXT_ALIGN_CENTER)

    sparkContainer = WINDOW_MANAGER:CreateControl(addon.name .. "_SparkStrip", windowControl, CT_CONTROL)
    sparkContainer:SetHeight(SPARK_HEIGHT)
    sparkContainer:SetMouseEnabled(true)

    -- Min/max scale line beneath the strip: the series value range, centered so
    -- it reads as a caption for the whole silhouette rather than hugging one edge.
    sparkScaleLabel = WINDOW_MANAGER:CreateControl(addon.name .. "_SparkScale", windowControl, CT_LABEL)
    sparkScaleLabel:SetFont("ZoFontGameSmall")
    sparkScaleLabel:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
    sparkScaleLabel:SetVerticalAlignment(TEXT_ALIGN_CENTER)

    -- Hover: summarize the series (oldest -> newest value and the change) so the
    -- bars get exact figures on demand without crowding the strip with text.
    sparkContainer:SetHandler("OnMouseEnter", function(self)
        local valuation = addon.Valuation
        local points = (valuation and valuation.GetValueHistory) and valuation.GetValueHistory() or {}
        if #points < 2 then
            return
        end
        local first, last = points[1], points[#points]
        InitializeTooltip(InformationTooltip, self, TOPRIGHT, -6, 0, BOTTOMRIGHT)
        InformationTooltip:AddLine(GetString(SI_BMW_FOOTER_HISTORY_LABEL), "ZoFontHeader2",
            ZO_NORMAL_TEXT:UnpackRGB())
        ZO_Tooltip_AddDivider(InformationTooltip)
        InformationTooltip:AddLine(stringformat(GetString(SI_BMW_HISTORY_TOOLTIP_POINTS), #points),
            "ZoFontGame", 0.86, 0.85, 0.78)
        InformationTooltip:AddLine(stringformat(GetString(SI_BMW_HISTORY_TOOLTIP_OLDEST),
            ZO_LocalizeDecimalNumber(zo_round(first.gold or 0))), "ZoFontGame", 0.86, 0.85, 0.78)
        InformationTooltip:AddLine(stringformat(GetString(SI_BMW_HISTORY_TOOLTIP_NEWEST),
            ZO_LocalizeDecimalNumber(zo_round(last.gold or 0))), "ZoFontGame", 1, 0.82, 0.25)
        -- Net change across the recorded window, colored by direction.
        local change = (last.gold or 0) - (first.gold or 0)
        local r, g, b = 0.55, 0.79, 0.62
        if change < 0 then
            r, g, b = 0.82, 0.54, 0.54
        end
        InformationTooltip:AddLine(stringformat(GetString(SI_BMW_HISTORY_TOOLTIP_CHANGE),
            ZO_LocalizeDecimalNumber(zo_round(change))), "ZoFontGame", r, g, b)
    end)
    sparkContainer:SetHandler("OnMouseExit", function()
        ClearTooltip(InformationTooltip)
    end)
end

-- Render just the footer text from the cached snapshot. Split out so the
-- low-frequency tick can refresh the "updated X ago" line without re-laying-out
-- the whole window. Each footer row is two columns: a muted label on the left
-- and the value on the right, matching the category rows above.
local function RenderFooter()
    if not lastSnapshot then
        return
    end

    -- Updated <ago>
    footerUpdatedRow.label:SetText(Colorize(COLOR_MUTED, GetString(SI_BMW_FOOTER_UPDATED_LABEL)))
    footerUpdatedRow.value:SetText(Colorize(COLOR_MUTED, FormatTimeAgo(lastSnapshot.lastScanTimeMs)))

    -- Coverage -> "<priced>/<slots> · <source>", or a warning when unpriced.
    -- The source is shown compactly (MM/TTC/ATT) to fit the value column; when
    -- more than half the slots are unpriced the total is unreliable, so the row
    -- turns amber and drops the source as noise.
    local slots = lastSnapshot.slots or 0
    local unpriced = lastSnapshot.unpricedSlots or 0
    local priced = slots - unpriced

    local function SourceSuffix()
        if lastSnapshot.sourceShort then
            local s = " · " .. lastSnapshot.sourceShort
            if lastSnapshot.sourceHasOthers then
                s = s .. "+"
            end
            return s
        end
        return ""
    end

    footerPricesRow.label:SetText(Colorize(COLOR_MUTED, GetString(SI_BMW_FOOTER_COVERAGE_LABEL)))
    if unpriced > 0 and slots > 0 and (unpriced * 2 > slots) then
        -- Low coverage: loud warning in place of the usual count.
        footerPricesRow.value:SetText(Colorize(COLOR_WARN,
            stringformat(GetString(SI_BMW_FOOTER_LOW_COVERAGE), unpriced, slots)))
    else
        local countColor = unpriced > 0 and COLOR_WARN or COLOR_MUTED
        local countText = stringformat(GetString(SI_BMW_FOOTER_COVERAGE_VALUE), priced, slots)
        footerPricesRow.value:SetText(
            Colorize(countColor, countText) .. Colorize(COLOR_MUTED, SourceSuffix()))
    end

    -- Value-change delta. Hidden when there is no baseline yet or the total is
    -- unchanged. The label reflects the configured baseline mode; the value is
    -- an arrow (direction) + colored magnitude.
    local delta = lastSnapshot.delta
    if delta and delta ~= 0 then
        local gain = delta > 0
        local color = gain and COLOR_GAIN or COLOR_LOSS
        local arrow = gain and ARROW_UP or ARROW_DOWN
        local magnitude = ZO_LocalizeDecimalNumber(zo_round(mathabs(delta)))
        local labelKey = lastSnapshot.deltaMode == "session"
            and SI_BMW_FOOTER_DELTA_LABEL_SESSION or SI_BMW_FOOTER_DELTA_LABEL
        footerDeltaRow.container:SetHidden(false)
        footerDeltaRow.label:SetText(Colorize(COLOR_MUTED, GetString(labelKey)))
        -- The arrow texture carries the direction; the number is colored, the
        -- texture left outside Colorize since textures aren't tinted.
        footerDeltaRow.value:SetText(arrow .. " " .. Colorize(color,
            stringformat(GetString(SI_BMW_FOOTER_DELTA_VALUE), magnitude)))
    else
        footerDeltaRow.container:SetHidden(true)
    end
end

-- Acquire (or create) the Nth chart bar, a CT_BACKDROP fill bottom-anchored in
-- the strip so its height grows upward. Pooled and reused across renders so a
-- refresh re-points existing bars instead of creating new controls.
local function AcquireSparkBar(index)
    local bar = sparkBars[index]
    if bar then
        return bar
    end

    bar = WINDOW_MANAGER:CreateControl(
        addon.name .. "_SparkBar" .. index, sparkContainer, CT_BACKDROP)
    bar:SetEdgeColor(0, 0, 0, 0)        -- no border, just the fill
    bar:SetInsets(0, 0, 0, 0)
    sparkBars[index] = bar
    return bar
end

-- Draw the value-history area chart from the recorded samples. Each sample is one
-- vertical bar whose height is its gold value normalized between the series
-- min/max; bars are drawn edge-to-edge (no gap) so they read as a filled
-- silhouette rather than separate bars. The whole fill is tinted by the series'
-- overall direction (green when the newest sample is at or above the oldest, red
-- when below), with the newest bar brightened so "now" stands out. The head label
-- (current value + trend arrow) and the min/max scale line are filled here too,
-- so the chart carries scale and direction the old bar strip lacked. Returns the
-- total height consumed (strip + scale line, 0 when hidden or there's nothing
-- meaningful to show) so the caller can advance its layout cursor. A flat series
-- (min == max) draws all bars at full height rather than dividing by zero.
local function RenderSparkline(innerWidth)
    local valuation = addon.Valuation
    local points = (valuation and valuation.GetValueHistory) and valuation.GetValueHistory() or {}

    -- Need at least two points for a trend to mean anything; below that hide the
    -- whole block (caption + head + strip + scale) and report zero consumed height.
    if #points < 2 then
        sparkCaption:SetHidden(true)
        sparkHeadLabel:SetHidden(true)
        sparkContainer:SetHidden(true)
        sparkScaleLabel:SetHidden(true)
        for i = 1, #sparkBars do
            sparkBars[i]:SetHidden(true)
        end
        return 0
    end

    sparkCaption:SetHidden(false)
    sparkHeadLabel:SetHidden(false)
    sparkContainer:SetHidden(false)
    sparkScaleLabel:SetHidden(false)
    sparkCaption:SetText(Colorize(COLOR_MUTED, GetString(SI_BMW_FOOTER_HISTORY_LABEL)))

    local count = #points
    local minGold, maxGold = points[1].gold or 0, points[1].gold or 0
    for i = 2, count do
        local g = points[i].gold or 0
        if g < minGold then minGold = g end
        if g > maxGold then maxGold = g end
    end
    local span = maxGold - minGold

    -- Overall trend across the recorded window decides the fill tint: the newest
    -- sample at or above the oldest reads as a gain (green), below as a loss (red).
    local firstGold = points[1].gold or 0
    local lastGold = points[count].gold or 0
    local rising = lastGold >= firstGold
    local fillColor = rising and SPARK_AREA_UP or SPARK_AREA_DOWN
    local nowColor = rising and SPARK_AREA_UP_NOW or SPARK_AREA_DOWN_NOW

    -- Bars fill the strip edge-to-edge so the series reads as one shape. Width is
    -- the exact per-sample slot; left edges are placed at rounded slot boundaries
    -- and each bar is widened to meet the next so rounding leaves no seams.
    local slot = innerWidth / count

    for i = 1, count do
        local bar = AcquireSparkBar(i)
        local gold = points[i].gold or 0
        -- Normalize 0..1 within the series; a flat series pins to full height.
        local frac = span > 0 and (gold - minGold) / span or 1
        local height = SPARK_MIN_BAR_H + frac * (SPARK_HEIGHT - SPARK_MIN_BAR_H)

        local color = (i == count) and nowColor or fillColor
        bar:SetCenterColor(color[1], color[2], color[3], color[4])

        -- Edge-to-edge: this bar spans from its slot boundary to the next, so the
        -- rounded left edges abut with no gap.
        local left = zo_round((i - 1) * slot)
        local right = zo_round(i * slot)
        local barWidth = right - left
        if barWidth < 1 then
            barWidth = 1
        end
        bar:SetWidth(barWidth)
        bar:SetHeight(zo_round(height))
        bar:ClearAnchors()
        -- Bottom-aligned so taller bars rise from a shared baseline.
        bar:SetAnchor(BOTTOMLEFT, sparkContainer, BOTTOMLEFT, left, 0)
        bar:SetHidden(false)
    end

    -- Hide any pooled bars left from a previous (longer) series.
    for i = count + 1, #sparkBars do
        sparkBars[i]:SetHidden(true)
    end

    -- Head: current value + trend arrow + gold icon, colored by direction. The
    -- arrow and gold icon are textures (left outside Colorize, since textures
    -- aren't tinted); only the number is colored. Matches FormatGold's idiom.
    local headColor = rising and COLOR_GAIN or COLOR_LOSS
    local headArrow = rising and ARROW_UP or ARROW_DOWN
    sparkHeadLabel:SetText(headArrow .. " " ..
        Colorize(headColor, ZO_LocalizeDecimalNumber(zo_round(lastGold))) .. " " .. GOLD_ICON)

    -- Scale line: the series value range as "min - max" (plain hyphen), centered
    -- under the strip. Stated as a range rather than edge-pinned labels because
    -- the leftmost/rightmost bars are the oldest/newest samples, not necessarily
    -- the min/max.
    sparkScaleLabel:SetText(Colorize(COLOR_MUTED, stringformat(GetString(SI_BMW_HISTORY_SCALE),
        ZO_LocalizeDecimalNumber(zo_round(minGold)),
        ZO_LocalizeDecimalNumber(zo_round(maxGold)))))

    return SPARK_HEIGHT + SPARK_SCALE_GAP + FOOTER_LINE
end

-- Re-render the window from the current valuation. Pure presentation: it reads
-- the already-computed snapshot (no scanning here) and lays out only the rows
-- it needs, resizing the window to fit. Cheap enough to call on every coalesced
-- refresh.
function Window.Update()
    if not windowControl then
        return
    end

    local valuation = addon.Valuation
    if not valuation then
        return
    end

    local sv = GetSavedVars()
    local snapshot = valuation.GetSnapshot(sv.sortByValue == true)
    lastSnapshot = snapshot

    -- Header block: prominent total + subtitle counts.
    totalLabel:SetText(FormatGold(snapshot.gold))

    -- Account/character identity on the title line (optional). The Craft Bag is
    -- account-wide, so the @account handle names whose bag this is; the character
    -- is profile flavor. Text is cached (stable per session), so this is cheap.
    if sv.showProfile ~= false then
        profileLabel:SetHidden(false)
        profileLabel:SetText(Colorize(COLOR_MUTED, GetProfileText()))
    else
        profileLabel:SetHidden(true)
    end

    if snapshot.slots > 0 then
        subtitleLabel:SetHidden(false)
        subtitleLabel:SetText(Colorize(COLOR_MUTED, stringformat(
            GetString(SI_BMW_WINDOW_SUBTITLE),
            snapshot.slots,
            ZO_LocalizeDecimalNumber(snapshot.stacks),
            ZO_LocalizeDecimalNumber(snapshot.items))))
    else
        subtitleLabel:SetHidden(false)
        subtitleLabel:SetText(Colorize(COLOR_MUTED, GetString(SI_BMW_WINDOW_EMPTY)))
    end

    local y = PADDING + TITLE_HEIGHT + SECTION_GAP + TOTAL_HEIGHT + SUBTITLE_HEIGHT

    -- Divider under the header.
    y = y + SECTION_GAP
    dividerTop:ClearAnchors()
    dividerTop:SetAnchor(TOPLEFT, windowControl, TOPLEFT, PADDING, y)
    y = y + DIVIDER_GAP

    -- Category rows (optional). Each shows name + gold; hover reveals the detail.
    local rowCount = 0
    local showBreakdown = sv.showCategoryBreakdown ~= false
    local showIcons = sv.showCategoryIcons ~= false
    local colorScale = sv.colorScaleGold ~= false
    if showBreakdown then
        local rows = snapshot.categories
        local grandTotal = snapshot.gold
        for i = 1, #rows do
            local data = rows[i]
            local row = AcquireRow(i)
            row.data = data
            -- Optional profession icon + name + the category's share of the grand
            -- total, so it reads "[icon] Blacksmithing 42%" at a glance. Guard
            -- against a zero total (an all-unpriced bag) so the share is simply
            -- omitted rather than NaN.
            local nameText = Colorize(COLOR_NAME, data.name)
            if showIcons then
                nameText = CategoryIcon(data.id) .. nameText
            end
            if grandTotal and grandTotal > 0 then
                local percent = zo_round(data.gold / grandTotal * 100)
                nameText = nameText .. " " .. Colorize(COLOR_MUTED,
                    stringformat(GetString(SI_BMW_ROW_PERCENT), percent))
            end
            row.name:SetText(nameText)
            -- Flag categories that have unpriced slots with a subtle marker so
            -- the total reads honestly at a glance, detail is in the tooltip.
            local goldText = FormatGold(data.gold, colorScale and GoldScaleColor(data.gold) or nil)
            if data.unpricedSlots > 0 then
                goldText = goldText .. " " .. Colorize(COLOR_WARN, "*")
            end
            row.gold:SetText(goldText)
            row.container:ClearAnchors()
            row.container:SetAnchor(TOPLEFT, windowControl, TOPLEFT, PADDING, y)
            row.container:SetHidden(false)
            y = y + ROW_HEIGHT
            rowCount = i
        end
    end

    -- Hide any pooled rows left over from a previous (larger) render.
    for i = rowCount + 1, #rowPool do
        rowPool[i].container:SetHidden(true)
    end

    dividerTop:SetHidden(not showBreakdown or rowCount == 0)
    if not showBreakdown or rowCount == 0 then
        -- Collapse the header divider's gap when there is no breakdown to show.
        y = PADDING + TITLE_HEIGHT + SECTION_GAP + TOTAL_HEIGHT + SUBTITLE_HEIGHT + SECTION_GAP
    end

    -- Footer block: bottom divider + the info rows (two-column label -> value).
    y = y + SECTION_GAP
    dividerBottom:ClearAnchors()
    dividerBottom:SetAnchor(TOPLEFT, windowControl, TOPLEFT, PADDING, y)
    y = y + DIVIDER_GAP

    footerUpdatedRow.container:ClearAnchors()
    footerUpdatedRow.container:SetAnchor(TOPLEFT, windowControl, TOPLEFT, PADDING, y)
    y = y + FOOTER_LINE

    footerPricesRow.container:ClearAnchors()
    footerPricesRow.container:SetAnchor(TOPLEFT, windowControl, TOPLEFT, PADDING, y)
    y = y + FOOTER_LINE

    -- Optional value-change row. Only reserves vertical space when it will
    -- actually be shown (a known, non-zero delta), so the panel doesn't grow an
    -- empty gap on the first visit.
    footerDeltaRow.container:ClearAnchors()
    footerDeltaRow.container:SetAnchor(TOPLEFT, windowControl, TOPLEFT, PADDING, y)
    local delta = snapshot.delta
    if delta and delta ~= 0 then
        y = y + FOOTER_LINE
    end

    RenderFooter()

    -- Value-history area chart (optional). Sits below the footer rows; the
    -- caption + head + filled strip + scale line only consume space when there's
    -- enough history to draw, and the whole block is skipped when the setting is
    -- off.
    if sv.showValueHistory ~= false then
        y = y + SECTION_GAP
        local innerWidth = CurrentWidth() - PADDING * 2

        -- Caption (left) and current-value head (right) share one row.
        sparkCaption:ClearAnchors()
        sparkCaption:SetAnchor(TOPLEFT, windowControl, TOPLEFT, PADDING, y)
        sparkHeadLabel:ClearAnchors()
        sparkHeadLabel:SetAnchor(TOPRIGHT, windowControl, TOPRIGHT, -PADDING, y)

        -- Filled strip beneath the caption row.
        sparkContainer:ClearAnchors()
        sparkContainer:SetAnchor(TOPLEFT, windowControl, TOPLEFT, PADDING, y + FOOTER_LINE)
        sparkContainer:SetWidth(innerWidth)

        -- Scale line (min … max) beneath the strip.
        sparkScaleLabel:ClearAnchors()
        sparkScaleLabel:SetAnchor(TOPLEFT, windowControl, TOPLEFT, PADDING,
            y + FOOTER_LINE + SPARK_HEIGHT + SPARK_SCALE_GAP)
        sparkScaleLabel:SetWidth(innerWidth)

        local consumed = RenderSparkline(innerWidth)
        if consumed > 0 then
            y = y + FOOTER_LINE + consumed
        end
    else
        sparkCaption:SetHidden(true)
        sparkHeadLabel:SetHidden(true)
        sparkContainer:SetHidden(true)
        sparkScaleLabel:SetHidden(true)
    end

    windowControl:SetHeight(y + PADDING)
end

local function StartFooterTick()
    EVENT_MANAGER:RegisterForUpdate(FOOTER_TIMER_NAME, FOOTER_TICK_MS, function()
        RenderFooter()
    end)
end

local function StopFooterTick()
    EVENT_MANAGER:UnregisterForUpdate(FOOTER_TIMER_NAME)
end

function Window.Show()
    if not windowControl then
        return
    end
    -- Only meaningful while the Craft Bag is on screen. The fragment callback
    -- only fires Show() when it is, but the settings toggle also calls Show() to
    -- refresh visibility, and that can happen with the bag closed.
    if not (CRAFT_BAG_FRAGMENT and CRAFT_BAG_FRAGMENT:IsShowing()) then
        Window.Hide()
        return
    end
    -- Suppressed in the guild store when the user has opted out: the panel would
    -- otherwise sit over the trading house UI, and not everyone wants it there.
    if IsGuildStoreShowing() and GetSavedVars().showInGuildStore == false then
        Window.Hide()
        return
    end
    -- Re-anchor on each show: the correct offset depends on whether the guild
    -- store is up, which is only known now (not at Initialize time).
    Window.ApplyAnchor()
    Window.Update()
    windowControl:SetHidden(false)
    StartFooterTick()
end

function Window.Hide()
    if windowControl then
        windowControl:SetHidden(true)
    end
    StopFooterTick()
end

-- Re-apply the configured anchor offset after the settings panel changes it.
-- The window hangs off the left edge of the Craft Bag; in the guild store an
-- extra leftward shift keeps it clear of the trading house's browse pane.
function Window.ApplyAnchor()
    if not windowControl then
        return
    end
    local sv = GetSavedVars()
    local offsetX = sv.windowOffsetX or -25
    if IsGuildStoreShowing() then
        offsetX = offsetX + GUILD_STORE_OFFSET_X
    end
    windowControl:ClearAnchors()
    windowControl:SetAnchor(TOPRIGHT, ZO_CraftBag, TOPLEFT,
        offsetX, sv.windowOffsetY or 0)
end

-- Re-apply the configured width to the window and every width-dependent control
-- (dividers + pooled rows and their two columns), then re-lay-out. Called when
-- the width slider changes; safe before Initialize (no-op) and when rows have
-- not been created yet.
function Window.ApplyWidth()
    if not windowControl then
        return
    end

    local width = CurrentWidth()
    windowControl:SetWidth(width)

    local innerWidth = width - PADDING * 2
    if dividerTop then
        dividerTop:SetWidth(innerWidth)
    end
    -- The profile label's width tracks the window so a wider panel gives the handle
    -- more room before it ellipsizes.
    if profileLabel then
        profileLabel:SetWidth(width * 0.55)
    end
    if dividerBottom then
        dividerBottom:SetWidth(innerWidth)
    end
    -- The sparkline strip spans the inner width; its bars are re-laid-out by the
    -- Window.Update() call at the end of this function.
    if sparkContainer then
        sparkContainer:SetWidth(innerWidth)
    end

    if rowPool then
        for i = 1, #rowPool do
            local row = rowPool[i]
            row.container:SetWidth(innerWidth)
            row.name:SetWidth(width * 0.5)
            row.gold:SetWidth(width * 0.5 - PADDING)
        end
    end

    -- Footer rows share the same two-column geometry (40/60 split).
    local function ResizeFooterRow(row)
        if not row then
            return
        end
        row.container:SetWidth(innerWidth)
        row.label:SetWidth(width * 0.4)
        row.value:SetWidth(width * 0.6 - PADDING)
    end
    ResizeFooterRow(footerUpdatedRow)
    ResizeFooterRow(footerPricesRow)
    ResizeFooterRow(footerDeltaRow)

    Window.Update()
end

-- Re-apply the configured background/border appearance. When the background is
-- off the center color is fully transparent; when the border is off the edge
-- color is too, so the panel can be reduced to plain floating text.
function Window.ApplyAppearance()
    if not backdrop then
        return
    end

    local sv = GetSavedVars()
    local showBackground = sv.showBackground ~= false
    local showBorder = sv.showBorder ~= false

    if showBackground then
        backdrop:SetCenterColor(0.05, 0.05, 0.06, BG_ALPHA)
    else
        backdrop:SetCenterColor(0, 0, 0, 0)
    end

    if showBorder then
        backdrop:SetEdgeColor(0.42, 0.40, 0.34, EDGE_ALPHA)
    else
        backdrop:SetEdgeColor(0, 0, 0, 0)
    end
end

