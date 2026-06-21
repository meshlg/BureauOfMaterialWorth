local addon = BureauOfMaterialWorth
addon.Window = addon.Window or {}

local Window = addon.Window
local private = addon.private

local GetString = GetString
local stringformat = string.format
local zo_round = zo_round

-- Palette (shared with the rest of the Bureau house style)
-- ---------------------------------------------------------------------------
local COLOR_ACCENT   = "6FCB9F"  -- brand green: title + grand total
local COLOR_MUTED    = "8C8A82"  -- dim grey: subtitle + footer
local COLOR_NAME     = "DBD9D0"  -- near-white: category names
local COLOR_GOLD     = "F4D03F"  -- soft gold: gold figures
local COLOR_WARN     = "D0905E"  -- amber: "missing price" hint

-- Layout constants
-- ---------------------------------------------------------------------------
-- A slim panel anchored beside the craft bag. It sizes itself to its content:
-- a title, a prominent grand total, a subtitle, a divider, one row per non-empty
-- category, another divider, then a two-line footer. Category rows are two
-- columns (name left, gold right) so the figures line up.
local WINDOW_WIDTH   = 260
local PADDING        = 12
local TITLE_HEIGHT   = 22
local TOTAL_HEIGHT   = 30
local SUBTITLE_HEIGHT = 18
local ROW_HEIGHT     = 22
local DIVIDER_GAP    = 10   -- vertical space a divider occupies
local FOOTER_LINE    = 16
local SECTION_GAP    = 6    -- small gap between blocks
local BG_ALPHA       = 0.82

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
local titleLabel      -- "Craft Bag Worth"
local totalLabel      -- prominent grand-total gold figure
local subtitleLabel   -- "<n> stacks · <n> items"
local dividerTop      -- line under the header block
local dividerBottom   -- line above the footer
local footerUpdated   -- "Updated <ago>"
local footerPrices    -- price-availability note
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

local function CreateDivider(name)
    local divider = WINDOW_MANAGER:CreateControl(name, windowControl, CT_TEXTURE)
    divider:SetTexture("EsoUI/Art/Miscellaneous/horizontalDivider.dds")
    divider:SetWidth(WINDOW_WIDTH - PADDING * 2)
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
    container:SetWidth(WINDOW_WIDTH - PADDING * 2)
    container:SetHeight(ROW_HEIGHT)
    container:SetMouseEnabled(true)

    local nameLabel = WINDOW_MANAGER:CreateControl(nil, container, CT_LABEL)
    nameLabel:SetFont("ZoFontGame")
    nameLabel:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
    nameLabel:SetVerticalAlignment(TEXT_ALIGN_CENTER)
    nameLabel:SetAnchor(LEFT, container, LEFT, 0, 0)
    nameLabel:SetWidth(WINDOW_WIDTH * 0.5)

    local goldLabel = WINDOW_MANAGER:CreateControl(nil, container, CT_LABEL)
    goldLabel:SetFont("ZoFontGame")
    goldLabel:SetHorizontalAlignment(TEXT_ALIGN_RIGHT)
    goldLabel:SetVerticalAlignment(TEXT_ALIGN_CENTER)
    goldLabel:SetAnchor(RIGHT, container, RIGHT, 0, 0)
    goldLabel:SetWidth(WINDOW_WIDTH * 0.5 - PADDING)

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
        InformationTooltip:AddLine(stringformat(GetString(SI_BMW_TOOLTIP_STACKS),
            data.stacks), "ZoFontGame", 0.86, 0.85, 0.78)
        InformationTooltip:AddLine(stringformat(GetString(SI_BMW_TOOLTIP_ITEMS),
            ZO_LocalizeDecimalNumber(data.items)), "ZoFontGame", 0.86, 0.85, 0.78)
        if data.unpricedStacks > 0 then
            InformationTooltip:AddLine(stringformat(GetString(SI_BMW_TOOLTIP_UNPRICED),
                data.unpricedStacks), "ZoFontGame", 0.82, 0.56, 0.37)
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
    windowControl:SetDimensions(WINDOW_WIDTH, 120)
    windowControl:SetHidden(true)
    windowControl:SetMouseEnabled(true)  -- so category rows can receive hover

    local sv = GetSavedVars()
    windowControl:SetAnchor(TOPRIGHT, ZO_CraftBag, TOPLEFT,
        sv.windowOffsetX or -10, sv.windowOffsetY or 0)

    local backdrop = WINDOW_MANAGER:CreateControl(addon.name .. "_Backdrop", windowControl, CT_BACKDROP)
    backdrop:SetAnchorFill(windowControl)
    backdrop:SetCenterColor(0.05, 0.05, 0.06, BG_ALPHA)
    backdrop:SetEdgeColor(0.42, 0.40, 0.34, 0.9)
    backdrop:SetEdgeTexture("", 1, 1, 1)
    backdrop:SetInsets(2, 2, -2, -2)

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

    if lastSnapshot.unpricedStacks > 0 then
        footerPrices:SetText(Colorize(COLOR_WARN,
            stringformat(GetString(SI_BMW_FOOTER_SOME_UNPRICED),
                lastSnapshot.unpricedStacks, lastSnapshot.stacks)))
    else
        footerPrices:SetText(Colorize(COLOR_MUTED, GetString(SI_BMW_FOOTER_ALL_PRICED)))
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
    local snapshot = valuation.GetSnapshot()
    lastSnapshot = snapshot

    -- Header block: prominent total + subtitle counts.
    totalLabel:SetText(FormatGold(snapshot.gold))

    if snapshot.stacks > 0 then
        subtitleLabel:SetHidden(false)
        subtitleLabel:SetText(Colorize(COLOR_MUTED, stringformat(
            GetString(SI_BMW_WINDOW_SUBTITLE),
            snapshot.stacks, ZO_LocalizeDecimalNumber(snapshot.items))))
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
        for i = 1, #rows do
            local data = rows[i]
            local row = AcquireRow(i)
            row.data = data
            row.name:SetText(Colorize(COLOR_NAME, data.name))
            -- Flag categories that have unpriced stacks with a subtle marker so
            -- the total reads honestly at a glance, detail is in the tooltip.
            local goldText = FormatGold(data.gold)
            if data.unpricedStacks > 0 then
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
        sv.windowOffsetX or -10, sv.windowOffsetY or 0)
end

