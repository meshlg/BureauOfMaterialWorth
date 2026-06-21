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

-- Expose the width bounds so the settings slider stays in sync with the layout.
Window.DEFAULT_WIDTH = DEFAULT_WINDOW_WIDTH
Window.MIN_WIDTH = MIN_WINDOW_WIDTH
Window.MAX_WIDTH = MAX_WINDOW_WIDTH
Window.WIDTH_STEP = WINDOW_WIDTH_STEP

local GOLD_ICON = "|t16:16:EsoUI/Art/currency/currency_gold.dds|t"

local function Colorize(hex, text)
    return stringformat("|c%s%s|r", hex, text)
end

-- Format a gold amount with thousands separators + the gold icon, matching the
-- presentation used in LibPrice's own example output.
local function FormatGold(amount)
    return Colorize(COLOR_GOLD, ZO_LocalizeDecimalNumber(zo_round(amount or 0))) .. " " .. GOLD_ICON
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

-- Runtime control references, created once in Initialize().
local windowControl   -- top-level container
local backdrop        -- background + border fill (toggled by appearance settings)
local titleLabel      -- "Craft Bag Worth"
local totalLabel      -- prominent grand-total gold figure
local subtitleLabel   -- "<n> slots · <n> stacks · <n> items"
local dividerTop      -- line under the header block
local dividerBottom   -- line above the footer
local footerUpdated   -- "Updated <ago>"
local footerPrices    -- price-availability note (+ dominant source)
local footerDelta     -- "since last visit" gold change
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
    end)
    container:SetHandler("OnMouseExit", function()
        ClearTooltip(InformationTooltip)
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

    local sv = GetSavedVars()
    windowControl:SetAnchor(TOPRIGHT, ZO_CraftBag, TOPLEFT,
        sv.windowOffsetX or -25, sv.windowOffsetY or 0)

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

    totalLabel = WINDOW_MANAGER:CreateControl(addon.name .. "_Total", windowControl, CT_LABEL)
    totalLabel:SetFont("ZoFontWinH1")
    totalLabel:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
    totalLabel:SetAnchor(TOPLEFT, titleLabel, BOTTOMLEFT, 0, SECTION_GAP)

    subtitleLabel = WINDOW_MANAGER:CreateControl(addon.name .. "_Subtitle", windowControl, CT_LABEL)
    subtitleLabel:SetFont("ZoFontGameSmall")
    subtitleLabel:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
    subtitleLabel:SetAnchor(TOPLEFT, totalLabel, BOTTOMLEFT, 0, 2)

    dividerTop = CreateDivider(addon.name .. "_DividerTop")
    dividerBottom = CreateDivider(addon.name .. "_DividerBottom")

    footerUpdated = WINDOW_MANAGER:CreateControl(addon.name .. "_FooterUpdated", windowControl, CT_LABEL)
    footerUpdated:SetFont("ZoFontGameSmall")
    footerUpdated:SetHorizontalAlignment(TEXT_ALIGN_LEFT)

    footerPrices = WINDOW_MANAGER:CreateControl(addon.name .. "_FooterPrices", windowControl, CT_LABEL)
    footerPrices:SetFont("ZoFontGameSmall")
    footerPrices:SetHorizontalAlignment(TEXT_ALIGN_LEFT)

    footerDelta = WINDOW_MANAGER:CreateControl(addon.name .. "_FooterDelta", windowControl, CT_LABEL)
    footerDelta:SetFont("ZoFontGameSmall")
    footerDelta:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
end

-- Render just the footer text from the cached snapshot. Split out so the
-- low-frequency tick can refresh the "updated X ago" line without re-laying-out
-- the whole window.
local function RenderFooter()
    if not lastSnapshot then
        return
    end

    footerUpdated:SetText(Colorize(COLOR_MUTED,
        stringformat(GetString(SI_BMW_FOOTER_UPDATED), FormatTimeAgo(lastSnapshot.lastScanTimeMs))))

    -- Price-coverage line, always suffixed with the dominant source when one is
    -- known ("... · Master Merchant"), so the figures stay attributable even
    -- when some slots are unpriced (the common case -- style mats etc. rarely
    -- have a price). The one exception is the low-coverage warning: when more
    -- than half the slots are unpriced the total is unreliable, so we keep that
    -- line loud and drop the source as noise.
    local slots = lastSnapshot.slots or 0
    local unpriced = lastSnapshot.unpricedSlots or 0

    local function WithSource(text)
        if lastSnapshot.sourceName then
            local source = stringformat(GetString(SI_BMW_FOOTER_PRICES_FROM), lastSnapshot.sourceName)
            if lastSnapshot.sourceHasOthers then
                source = source .. " " .. GetString(SI_BMW_FOOTER_PRICES_OTHERS)
            end
            return text .. " · " .. source
        end
        return text
    end

    if unpriced > 0 then
        local lowCoverage = slots > 0 and (unpriced * 2 > slots)
        if lowCoverage then
            footerPrices:SetText(Colorize(COLOR_WARN,
                stringformat(GetString(SI_BMW_FOOTER_LOW_COVERAGE), unpriced, slots)))
        else
            footerPrices:SetText(
                Colorize(COLOR_WARN, stringformat(GetString(SI_BMW_FOOTER_SOME_UNPRICED), unpriced, slots))
                .. Colorize(COLOR_MUTED, WithSource("")))
        end
    elseif lastSnapshot.sourceName then
        footerPrices:SetText(Colorize(COLOR_MUTED,
            WithSource(GetString(SI_BMW_FOOTER_ALL_PRICED))))
    else
        footerPrices:SetText(Colorize(COLOR_MUTED, GetString(SI_BMW_FOOTER_ALL_PRICED)))
    end

    -- Value-change delta. Hidden when there is no baseline yet or the total is
    -- unchanged, so the line only appears when it says something. The label
    -- depends on the configured baseline mode (per-visit vs per-session).
    local delta = lastSnapshot.delta
    if delta and delta ~= 0 then
        local color = delta > 0 and COLOR_GAIN or COLOR_LOSS
        local sign = delta > 0 and "+" or "-"
        local magnitude = ZO_LocalizeDecimalNumber(zo_round(mathabs(delta)))
        local labelKey = lastSnapshot.deltaMode == "session"
            and SI_BMW_FOOTER_DELTA_SESSION or SI_BMW_FOOTER_DELTA
        footerDelta:SetHidden(false)
        footerDelta:SetText(Colorize(color,
            stringformat(GetString(labelKey), sign .. magnitude)))
    else
        footerDelta:SetHidden(true)
        footerDelta:SetText("")
    end
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
    if showBreakdown then
        local rows = snapshot.categories
        local grandTotal = snapshot.gold
        for i = 1, #rows do
            local data = rows[i]
            local row = AcquireRow(i)
            row.data = data
            -- Name + the category's share of the grand total, so it reads
            -- "Blacksmithing 42%" at a glance. Guard against a zero total (an
            -- all-unpriced bag) so the share is simply omitted rather than NaN.
            local nameText = Colorize(COLOR_NAME, data.name)
            if grandTotal and grandTotal > 0 then
                local percent = zo_round(data.gold / grandTotal * 100)
                nameText = nameText .. " " .. Colorize(COLOR_MUTED,
                    stringformat(GetString(SI_BMW_ROW_PERCENT), percent))
            end
            row.name:SetText(nameText)
            -- Flag categories that have unpriced slots with a subtle marker so
            -- the total reads honestly at a glance, detail is in the tooltip.
            local goldText = FormatGold(data.gold)
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

    -- Footer block: bottom divider + the two info lines.
    y = y + SECTION_GAP
    dividerBottom:ClearAnchors()
    dividerBottom:SetAnchor(TOPLEFT, windowControl, TOPLEFT, PADDING, y)
    y = y + DIVIDER_GAP

    footerUpdated:ClearAnchors()
    footerUpdated:SetAnchor(TOPLEFT, windowControl, TOPLEFT, PADDING, y)
    y = y + FOOTER_LINE

    footerPrices:ClearAnchors()
    footerPrices:SetAnchor(TOPLEFT, windowControl, TOPLEFT, PADDING, y)
    y = y + FOOTER_LINE

    -- Optional since-last-visit delta line. Only reserves vertical space when it
    -- will actually be shown (a known, non-zero delta), so the panel doesn't grow
    -- an empty gap on the first visit.
    footerDelta:ClearAnchors()
    footerDelta:SetAnchor(TOPLEFT, windowControl, TOPLEFT, PADDING, y)
    local delta = snapshot.delta
    if delta and delta ~= 0 then
        y = y + FOOTER_LINE
    end

    RenderFooter()

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
function Window.ApplyAnchor()
    if not windowControl then
        return
    end
    local sv = GetSavedVars()
    windowControl:ClearAnchors()
    windowControl:SetAnchor(TOPRIGHT, ZO_CraftBag, TOPLEFT,
        sv.windowOffsetX or -25, sv.windowOffsetY or 0)
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
    if dividerBottom then
        dividerBottom:SetWidth(innerWidth)
    end

    if rowPool then
        for i = 1, #rowPool do
            local row = rowPool[i]
            row.container:SetWidth(innerWidth)
            row.name:SetWidth(width * 0.5)
            row.gold:SetWidth(width * 0.5 - PADDING)
        end
    end

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

