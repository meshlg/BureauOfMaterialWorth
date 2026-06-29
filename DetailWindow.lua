local addon = BureauOfMaterialWorth
addon.DetailWindow = addon.DetailWindow or {}

local DetailWindow = addon.DetailWindow
local private = addon.private

local GetString = GetString
local stringformat = string.format
local zo_round = zo_round
local zo_floor = zo_floor
local mathabs = math.abs
local tablesort = table.sort
local GetTimeStamp = GetTimeStamp

-- Palette (shared house style with Window.lua). Kept as a local copy rather than
-- reaching into Window.lua's locals so the two presentation modules stay
-- decoupled; these values are stable brand colors.
local COLOR_ACCENT = "6FCB9F"  -- brand green: title
local COLOR_MUTED  = "8C8A82"  -- dim grey: headers / secondary
local COLOR_GOLD   = "F4D03F"  -- soft gold: gold figures
local COLOR_GAIN   = "8FCB9F"  -- green: positive price change
local COLOR_LOSS   = "D08A8A"  -- soft red: negative price change

-- COLOR_MUTED (8C8A82) as normalized RGB, for the column headers. They are sort
-- toggles whose tone is set via SetColor rather than an inline |c code, so the
-- hover handlers can brighten one to white without fighting an embedded color.
local HEADER_MUTED_R = 0.549
local HEADER_MUTED_G = 0.541
local HEADER_MUTED_B = 0.510

-- Cumulative-share column coloring. The figure marks the Pareto "knee": rows up
-- to CUM_CORE_THRESHOLD make up the bulk of the value (the stacks worth hauling),
-- everything past it is the long tail. We make that readable at a glance:
--   * 0 .. threshold  : ramp from a dim tone to a vivid hot one, so the core rows
--                       that build toward the knee read as "warm = keep". The
--                       endpoints are spread WIDE in brightness on purpose - a
--                       narrow ramp is invisible on small text over a dark panel,
--                       and the value distribution often bunches the core rows
--                       into the upper part of the range.
--   * past threshold  : NOT colored - it falls back to the muted grey of the rest
--                       of the secondary text, so the long tail recedes and the
--                       eye is drawn to the warm core. (A red tail would collide
--                       with the price-change column, where red means "price
--                       fell"; de-emphasis, not warning, is the right signal.)
-- Endpoints are normalized RGB triples; the ramp interpolates between CORE_LO and
-- CORE_HI.
local CUM_CORE_THRESHOLD = 80   -- percent; the Pareto cut between core and tail
local CUM_CORE_LO  = { 0.50, 0.48, 0.42 }  -- dim warm grey: low % (top, most value)
local CUM_CORE_HI  = { 1.00, 0.80, 0.20 }  -- vivid gold: approaching the threshold

-- Build a "RRGGBB" hex string from a normalized RGB triple, for inline |c codes.
local function RGBToHex(r, g, b)
    return stringformat("%02X%02X%02X",
        zo_round(r * 255), zo_round(g * 255), zo_round(b * 255))
end

-- Pick the cumulative-share color for a given percent: a dim->vivid ramp across
-- the core (0..threshold), or COLOR_MUTED for the past-threshold tail so it reads
-- as plain de-emphasized text. Returns a hex string ready for Colorize.
local function CumulativeColor(percent)
    if percent > CUM_CORE_THRESHOLD then
        return COLOR_MUTED
    end
    local frac = percent / CUM_CORE_THRESHOLD  -- 0 at top, 1 at the knee
    local r = CUM_CORE_LO[1] + frac * (CUM_CORE_HI[1] - CUM_CORE_LO[1])
    local g = CUM_CORE_LO[2] + frac * (CUM_CORE_HI[2] - CUM_CORE_LO[2])
    local b = CUM_CORE_LO[3] + frac * (CUM_CORE_HI[3] - CUM_CORE_LO[3])
    return RGBToHex(r, g, b)
end

local GOLD_ICON = "|t16:16:EsoUI/Art/currency/currency_gold.dds|t"
-- Same sort-arrow textures Window.lua uses for its delta, for the same reason:
-- the ESO UI font doesn't render the Unicode triangles reliably.
local ARROW_UP = "|t16:16:EsoUI/Art/Miscellaneous/list_sortUp.dds|t"
local ARROW_DOWN = "|t16:16:EsoUI/Art/Miscellaneous/list_sortDown.dds|t"

-- Layout
-- ---------------------------------------------------------------------------
local WINDOW_WIDTH = 800   -- widened from 720 for the cumulative-share column
local PADDING      = 12
local TITLE_HEIGHT = 26
local HEADER_HEIGHT = 20
local DIVIDER_GAP  = 10
local ROW_HEIGHT   = 26
local LIST_MAX_ROWS = 16   -- beyond this the list scrolls instead of growing
local FOOTER_HEIGHT = 18   -- summary line beneath the list (divider + this label)
local BG_ALPHA     = 0.92

-- Single row data type id for the scroll list (we only have one kind of row).
local ROW_TYPE_ID = 1

-- Identifier for the "clear snapshot?" confirmation dialog, registered once in
-- Initialize. Clearing is destructive (one snapshot, no undo), so a stray click
-- on the toolbar button must not wipe the baseline without a confirm.
local CLEAR_SNAPSHOT_DIALOG = "BUREAU_OF_MATERIAL_WORTH_CLEAR_SNAPSHOT"

local function Colorize(hex, text)
    return stringformat("|c%s%s|r", hex, text)
end

local function FormatGold(amount)
    return Colorize(COLOR_GOLD, ZO_LocalizeDecimalNumber(zo_round(amount or 0))) .. " " .. GOLD_ICON
end

-- "How long ago" for the diff title, from a unix timestamp (GetTimeStamp) to a
-- short localized phrase. Note this works off the unix clock, NOT
-- GetGameTimeMilliseconds like Window's footer: the snapshot persists across
-- sessions, so its age must survive a restart. Unlike the footer (game-time, so
-- never more than a session old) this can span days, so it composes the largest
-- non-zero unit plus the next smaller one - "5d 3h", "3h 20m", "45m" - instead
-- of an unbounded hour count like "123h". The _AGO wrapper keeps word order
-- localizable.
local function FormatSnapshotAge(stampSeconds)
    if not stampSeconds then
        return GetString(SI_BMW_TIME_NEVER)
    end

    local seconds = GetTimeStamp() - stampSeconds
    if seconds < 5 then
        return GetString(SI_BMW_TIME_JUST_NOW)
    elseif seconds < 60 then
        return stringformat(GetString(SI_BMW_TIME_SECONDS), seconds)
    end

    local totalMinutes = zo_floor(seconds / 60)
    local days = zo_floor(totalMinutes / (60 * 24))
    local hours = zo_floor((totalMinutes - days * 60 * 24) / 60)
    local minutes = totalMinutes - days * 60 * 24 - hours * 60

    -- Largest non-zero unit + the immediately smaller one (when non-zero), capped
    -- at two parts so the phrase stays compact and never jumps a zero unit.
    local parts = {}
    if days > 0 then
        parts[1] = stringformat(GetString(SI_BMW_TIME_UNIT_DAYS), days)
        if hours > 0 then
            parts[2] = stringformat(GetString(SI_BMW_TIME_UNIT_HOURS), hours)
        end
    elseif hours > 0 then
        parts[1] = stringformat(GetString(SI_BMW_TIME_UNIT_HOURS), hours)
        if minutes > 0 then
            parts[2] = stringformat(GetString(SI_BMW_TIME_UNIT_MINUTES), minutes)
        end
    else
        parts[1] = stringformat(GetString(SI_BMW_TIME_UNIT_MINUTES), minutes)
    end

    return stringformat(GetString(SI_BMW_TIME_AGO), table.concat(parts, " "))
end

-- Runtime control references, created once in Initialize().
local windowControl   -- top-level container
local backdrop        -- background + border
local titleLabel      -- "<Category> - materials"
local headerName, headerQty, headerValue, headerCum, headerChange  -- column headers
local divider
local listControl     -- ZO_ScrollList
local footerDivider   -- rule above the summary line
local footerLabel     -- summary beneath the list (count/value/share, or diff net)
local emptyLabel      -- shown when the category has no materials
local currentCategoryId  -- remembered so a refresh can rebuild the same view
local currentCategoryName  -- remembered so the title can restore after a search
local searchBox       -- the search editbox
local changesButton   -- toolbar button; toggles between "Changes" and "Back"
local searchQuery = ""  -- current search text; "" means "show the category"
local suppressSearchEvent = false  -- guards the search box against its own SetText
local currentResultCount = 0  -- rows in the list just built by Populate; feeds the
                              -- search-result counter in the title

-- Which list the window is showing. "category" is the normal per-category table
-- (with the whole-bag search as a sub-state, driven by searchQuery); "diff" is
-- the snapshot comparison, where the Qty/Value/Cum/Change columns are repurposed
-- to signed deltas / share-of-change / status (see SetupRow and UpdateHeaders).
local viewMode = "category"  -- "category" | "diff"

-- Column sort state. The list is re-sorted in Populate() before it fills, so it
-- applies equally to a category view, the whole-bag search, and a live refresh.
-- Default to value-descending: the practical "what to sell right now" order, so
-- the stacks that make up most of the bag's worth sit at the top on open.
--   sortKey: "name" | "qty" | "value" | "change"
--   sortAsc: ascending when true. Numeric columns default to descending (biggest
--            first); the name column defaults to ascending (A->Z).
local sortKey = "value"
local sortAsc = false

-- Forward declarations so the search-box handlers built in Initialize can
-- capture these as upvalues; they are defined (as plain assignments) further
-- down, after Initialize.
local FillList, Populate, UpdateTitle, UpdateHeaders

-- Build the colored price-change text for a material row: an up/down arrow (the
-- texture carries the direction) plus a colored magnitude, matching Window.lua's
-- footer-delta idiom. Returns nil when there is no comparable change (no price,
-- no baseline yet, or no recorded percent) so the caller can fall back to a dash.
-- Shared by the Change column and the row hover tooltip so the two never drift.
local function FormatGrowthText(data)
    if data.priced and not data.isNew and data.growthPercent ~= nil then
        local gain = data.growthDir
        local color = gain and COLOR_GAIN or COLOR_LOSS
        local arrow = gain and ARROW_UP or ARROW_DOWN
        local magnitude = stringformat("%.1f", mathabs(data.growthPercent))
        return arrow .. " " .. Colorize(color,
            stringformat(GetString(SI_BMW_DETAIL_GROWTH), magnitude))
    end
    return nil
end

-- Render the Qty / Value / Cumulative / Change columns for a normal material row
-- (category view or whole-bag search). Split out of SetupRow so the diff view can
-- repurpose the same four controls without threading a mode flag through each.
local function SetupMaterialColumns(rowControl, data)
    rowControl:GetNamedChild("Qty"):SetText(
        Colorize(COLOR_MUTED, ZO_LocalizeDecimalNumber(data.count or 0)))

    rowControl:GetNamedChild("Value"):SetText(FormatGold(data.gold))

    -- Cumulative-share column: this row's running share of the displayed list's
    -- total value, assigned in Populate after the sort. Read top-down on the
    -- default value-descending view it answers "the top stacks down to here make
    -- up N% of the bag's worth" - the Pareto "what to sell" cue. Unpriced rows
    -- (and any view where the figure is meaningless) carry nil and show a dash.
    local cumLabel = rowControl:GetNamedChild("Cum")
    if data.cumPercent ~= nil then
        cumLabel:SetText(Colorize(CumulativeColor(data.cumPercent),
            stringformat(GetString(SI_BMW_DETAIL_CUM), data.cumPercent)))
    else
        cumLabel:SetText(Colorize(COLOR_MUTED, GetString(SI_BMW_DETAIL_GROWTH_NEW)))
    end

    -- Price-change column: an up/down arrow (the texture carries the direction)
    -- plus a colored magnitude, matching Window.lua's footer-delta idiom. A
    -- material with no recorded baseline yet, or no price at all, shows a dash.
    local changeLabel = rowControl:GetNamedChild("Change")
    local growthText = FormatGrowthText(data)
    if growthText then
        changeLabel:SetText(growthText)
    else
        changeLabel:SetText(Colorize(COLOR_MUTED, GetString(SI_BMW_DETAIL_GROWTH_NEW)))
    end
end

-- Map a diff status to its localized word. Four states: new (added since the
-- snapshot), gone (removed entirely), added (quantity went up), reduced (quantity
-- went down).
local DIFF_STATUS_STRING = {
    new = SI_BMW_DETAIL_STATUS_NEW,
    gone = SI_BMW_DETAIL_STATUS_GONE,
    added = SI_BMW_DETAIL_STATUS_ADDED,
    reduced = SI_BMW_DETAIL_STATUS_REDUCED,
}

-- Render the same four columns for a diff row, repurposed:
--   Qty    -> signed count delta (green up / red down)
--   Value  -> arrow + colored signed gold delta + gold icon (Change-column idiom);
--             a dash when the material is unpriced
--   Cum    -> share of total absolute change, assigned in Populate (else dash)
--   Change -> colored status word (new / gone / added / reduced)
-- A positive delta is a gain (deposited/added), negative a loss (withdrawn/gone),
-- colored with the same green/red the price-change column uses.
local function SetupDiffColumns(rowControl, data)
    local up = (data.countDelta or 0) >= 0
    local deltaColor = up and COLOR_GAIN or COLOR_LOSS
    local arrow = up and ARROW_UP or ARROW_DOWN
    local sign = up and "+" or "-"

    -- Qty delta: signed integer, colored by direction.
    rowControl:GetNamedChild("Qty"):SetText(Colorize(deltaColor,
        stringformat(GetString(SI_BMW_DETAIL_QTY_DELTA), sign,
            ZO_LocalizeDecimalNumber(mathabs(data.countDelta or 0)))))

    -- Value delta: arrow + colored magnitude + gold icon, or a dash when the
    -- material has no price to value the move with.
    local valueLabel = rowControl:GetNamedChild("Value")
    if data.priced and data.goldDelta ~= nil then
        local magnitude = ZO_LocalizeDecimalNumber(zo_round(mathabs(data.goldDelta)))
        valueLabel:SetText(arrow .. " " .. Colorize(deltaColor, magnitude) .. " " .. GOLD_ICON)
    else
        valueLabel:SetText(Colorize(COLOR_MUTED, GetString(SI_BMW_DETAIL_GROWTH_NEW)))
    end

    -- Cum -> share of the list's total movement (abs gold delta), assigned in
    -- Populate. Reuses the same warm gradient as the category view. Dash fallback.
    local cumLabel = rowControl:GetNamedChild("Cum")
    if data.cumPercent ~= nil then
        cumLabel:SetText(Colorize(CumulativeColor(data.cumPercent),
            stringformat(GetString(SI_BMW_DETAIL_CUM), data.cumPercent)))
    else
        cumLabel:SetText(Colorize(COLOR_MUTED, GetString(SI_BMW_DETAIL_GROWTH_NEW)))
    end

    -- Change -> status word, colored by direction: gains (new / added) green,
    -- losses (gone / reduced) red. The Qty/Value columns carry the magnitude.
    local changeLabel = rowControl:GetNamedChild("Change")
    local statusStringId = DIFF_STATUS_STRING[data.status]
    local statusColor = COLOR_MUTED
    if data.status == "new" or data.status == "added" then
        statusColor = COLOR_GAIN
    elseif data.status == "gone" or data.status == "reduced" then
        statusColor = COLOR_LOSS
    end
    if statusStringId then
        changeLabel:SetText(Colorize(statusColor, GetString(statusStringId)))
    else
        changeLabel:SetText(Colorize(COLOR_MUTED, GetString(SI_BMW_DETAIL_GROWTH_NEW)))
    end
end

-- Populate one recycled row from its material record. Mirrors the column
-- geometry declared in DetailWindow.xml.
local function SetupRow(rowControl, data)
    -- Stash the current record on the control so the click handlers (bound once
    -- below) always act on the freshest data; ZO_ScrollList recycles a small
    -- pool of rows across many materials.
    rowControl.bmwData = data

    rowControl:GetNamedChild("Icon"):SetTexture(data.icon)

    local nameLabel = rowControl:GetNamedChild("Name")
    -- The name column is a fixed width (anchored both sides), so long material
    -- names would be silently clipped mid-word. Ellipsize instead so it reads
    -- "Decorative Wax Sea…" and the truncation is visible. The full name is
    -- always available in the game's own item tooltip.
    nameLabel:SetMaxLineCount(1)
    nameLabel:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
    nameLabel:SetText(addon.Valuation.ColorizeMaterialName(data.name, data.quality))

    -- Diff rows repurpose the four numeric/status columns; a category/search row
    -- renders them as the normal Qty / Value / Cumulative / Change. Branch once on
    -- the diff flag rather than threading mode through every column.
    if data.diff then
        SetupDiffColumns(rowControl, data)
    else
        SetupMaterialColumns(rowControl, data)
    end

    -- Bind the interaction handlers once per recycled control (sentinel), then
    -- let them read rowControl.bmwData at event time. Left click opens the
    -- withdraw popup for this material; right click adds it to the withdraw
    -- queue. A hover tooltip spells out both, matching Window.lua's affordance.
    -- Diff rows carry no source slot (a removed material has none at all), so the
    -- withdraw actions and hint are guarded on the diff flag at event time.
    if not rowControl.bmwClickBound then
        rowControl.bmwClickBound = true

        rowControl:SetHandler("OnMouseUp", function(self, button, upInside)
            if not upInside then
                return
            end
            local rowData = self.bmwData
            local withdraw = addon.WithdrawDialog
            if not rowData or rowData.diff or not withdraw then
                return
            end
            if button == MOUSE_BUTTON_INDEX_LEFT then
                withdraw.Open(rowData)
            elseif button == MOUSE_BUTTON_INDEX_RIGHT then
                withdraw.AddToQueue(rowData)
            end
        end)

        rowControl:SetHandler("OnMouseEnter", function(self)
            local rowData = self.bmwData
            -- Diff rows carry a different shape (deltas/status, no source slot) and
            -- no withdraw affordance, so they get no hover tooltip.
            if not rowData or rowData.diff then
                return
            end

            InitializeTooltip(InformationTooltip, self, BOTTOM, 0, -2, TOP)

            -- Title: the quality-colored material name (the |c codes are carried in
            -- the string itself, so the AddLine r,g,b is just the uncolored base).
            InformationTooltip:AddLine(
                addon.Valuation.ColorizeMaterialName(rowData.name, rowData.quality),
                "ZoFontHeader2", 0.86, 0.85, 0.78)
            ZO_Tooltip_AddDivider(InformationTooltip)

            -- The figures already computed for the columns, spelled out. Quantity
            -- always applies; the price lines only when the material is priced,
            -- otherwise a single "no price" line so the row never looks broken.
            InformationTooltip:AddLine(stringformat(GetString(SI_BMW_ROW_TOOLTIP_QTY),
                ZO_LocalizeDecimalNumber(rowData.count or 0)), "ZoFontGame", 0.78, 0.77, 0.72)

            if rowData.priced and rowData.unitPrice and rowData.unitPrice > 0 then
                InformationTooltip:AddLine(stringformat(GetString(SI_BMW_ROW_TOOLTIP_UNIT),
                    FormatGold(rowData.unitPrice)), "ZoFontGame", 0.78, 0.77, 0.72)
                InformationTooltip:AddLine(stringformat(GetString(SI_BMW_ROW_TOOLTIP_TOTAL),
                    FormatGold(rowData.gold)), "ZoFontGame", 0.78, 0.77, 0.72)
                local sourceName = rowData.source and addon.Valuation.GetSourceDisplayName(rowData.source)
                if sourceName then
                    InformationTooltip:AddLine(stringformat(GetString(SI_BMW_ROW_TOOLTIP_SOURCE),
                        sourceName), "ZoFontGame", 0.78, 0.77, 0.72)
                end
                -- Price-change line, only when there's a comparable figure (shares
                -- the arrow+color idiom of the Change column via FormatGrowthText).
                local growthText = FormatGrowthText(rowData)
                if growthText then
                    InformationTooltip:AddLine(stringformat(GetString(SI_BMW_ROW_TOOLTIP_CHANGE),
                        growthText), "ZoFontGame", 0.78, 0.77, 0.72)
                end
            else
                InformationTooltip:AddLine(GetString(SI_BMW_ROW_TOOLTIP_UNPRICED),
                    "ZoFontGame", 0.82, 0.56, 0.37)
            end

            -- Interaction hint last, set off by a divider so it reads as a footer.
            ZO_Tooltip_AddDivider(InformationTooltip)
            InformationTooltip:AddLine(GetString(SI_BMW_WITHDRAW_HINT),
                "ZoFontGameSmall", 0.55, 0.79, 0.62)
        end)
        rowControl:SetHandler("OnMouseExit", function()
            ClearTooltip(InformationTooltip)
        end)
    end
end

function DetailWindow.Initialize()
    if windowControl then
        return
    end

    local innerWidth = WINDOW_WIDTH - PADDING * 2

    windowControl = WINDOW_MANAGER:CreateTopLevelWindow(addon.name .. "_DetailWindow")
    windowControl:SetClampedToScreen(true)
    windowControl:SetDimensions(WINDOW_WIDTH, 200)
    windowControl:SetHidden(true)
    windowControl:SetMouseEnabled(true)
    windowControl:SetMovable(true)
    -- Center on first show; the user can drag it from there.
    windowControl:SetAnchor(CENTER, GuiRoot, CENTER, 0, 0)

    -- Confirmation dialog for the destructive "Clear snapshot" action. Registered
    -- once; the accept callback does the actual clear so a stray button click only
    -- opens the prompt. Uses the standard two-button ESO dialog so it matches the
    -- game's look and the cancel path needs no custom wiring.
    ZO_Dialogs_RegisterCustomDialog(CLEAR_SNAPSHOT_DIALOG, {
        title = { text = GetString(SI_BMW_DETAIL_CLEAR_CONFIRM_TITLE) },
        mainText = { text = GetString(SI_BMW_DETAIL_CLEAR_CONFIRM_BODY) },
        buttons = {
            {
                text = GetString(SI_BMW_DETAIL_CLEAR_CONFIRM_ACCEPT),
                callback = function()
                    addon.Valuation.ClearSnapshot()
                    private.ChatInfo(SI_BMW_MSG_SNAPSHOT_CLEARED)
                    -- Refresh the diff view in place so it drops to the "press
                    -- Remember" empty state immediately after the clear.
                    if viewMode == "diff" then
                        Populate()
                    end
                end,
            },
            {
                text = GetString(SI_BMW_DETAIL_CLEAR_CONFIRM_CANCEL),
            },
        },
    })

    backdrop = WINDOW_MANAGER:CreateControl(addon.name .. "_DetailBackdrop", windowControl, CT_BACKDROP)
    backdrop:SetAnchorFill(windowControl)
    backdrop:SetEdgeTexture("", 1, 1, 1)
    backdrop:SetInsets(2, 2, -2, -2)
    backdrop:SetCenterColor(0.05, 0.05, 0.06, BG_ALPHA)
    backdrop:SetEdgeColor(0.42, 0.40, 0.34, 0.9)

    titleLabel = WINDOW_MANAGER:CreateControl(addon.name .. "_DetailTitle", windowControl, CT_LABEL)
    titleLabel:SetFont("ZoFontWinH4")
    titleLabel:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
    titleLabel:SetVerticalAlignment(TEXT_ALIGN_CENTER)
    titleLabel:SetMaxLineCount(1)
    titleLabel:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
    titleLabel:SetAnchor(TOPLEFT, windowControl, TOPLEFT, PADDING, PADDING)
    -- The title now has its own row (only the close button shares it), so it can
    -- run the full width up to the close button. The buttons + search sit on a
    -- second toolbar row below (see TOOLBAR_GAP / toolbarY).
    titleLabel:SetDimensions(WINDOW_WIDTH - PADDING * 2 - 32 - 8, TITLE_HEIGHT)

    -- Close button (built-in virtual) anchored top-right.
    local closeButton = WINDOW_MANAGER:CreateControlFromVirtual(
        addon.name .. "_DetailClose", windowControl, "ZO_CloseButton")
    closeButton:SetAnchor(TOPRIGHT, windowControl, TOPRIGHT, -PADDING, PADDING)
    closeButton:SetHandler("OnClicked", function()
        DetailWindow.Hide()
    end)

    -- Second toolbar row, below the title/close row: snapshot buttons on the left,
    -- the whole-bag search box on the right. Splitting these off the title row
    -- gives each element room to breathe (the single-row layout was cramped at
    -- width 800). TOOLBAR_GAP is the vertical air between the two rows.
    local TOOLBAR_GAP = 6
    local toolbarY = PADDING + TITLE_HEIGHT + TOOLBAR_GAP

    -- Search box (whole-bag). Typing here switches the list to materials matching
    -- the query across every category; clearing it returns to the opened category.
    local SEARCH_WIDTH = 240
    local searchBg = WINDOW_MANAGER:CreateControlFromVirtual(
        addon.name .. "_DetailSearchBg", windowControl, "ZO_DefaultBackdrop")
    searchBg:SetDimensions(SEARCH_WIDTH, TITLE_HEIGHT)
    searchBg:ClearAnchors()
    searchBg:SetAnchor(TOPRIGHT, windowControl, TOPRIGHT, -PADDING, toolbarY)
    -- Clicking anywhere on the backdrop (incl. its padding) focuses the editbox,
    -- so the hit target is the whole field, not just the text glyphs.
    searchBg:SetMouseEnabled(true)
    searchBg:SetHandler("OnMouseUp", function()
        if searchBox then
            searchBox:TakeFocus()
        end
    end)

    -- Faint placeholder shown only while the box is empty. Created BEFORE the
    -- editbox (so the editbox is the top-most sibling for mouse hits) and with
    -- mouse explicitly disabled so it never intercepts clicks meant for the box.
    local searchHint = WINDOW_MANAGER:CreateControl(addon.name .. "_DetailSearchHint", searchBg, CT_LABEL)
    searchHint:SetFont("ZoFontGame")
    searchHint:SetVerticalAlignment(TEXT_ALIGN_CENTER)
    searchHint:SetAnchor(LEFT, searchBg, LEFT, 8, 0)
    searchHint:SetMouseEnabled(false)
    searchHint:SetText(Colorize(COLOR_MUTED, GetString(SI_BMW_DETAIL_SEARCH_HINT)))

    searchBox = WINDOW_MANAGER:CreateControl(addon.name .. "_DetailSearch", searchBg, CT_EDITBOX)
    searchBox:SetAnchor(TOPLEFT, searchBg, TOPLEFT, 8, 2)
    searchBox:SetAnchor(BOTTOMRIGHT, searchBg, BOTTOMRIGHT, -8, -2)
    searchBox:SetFont("ZoFontGame")
    searchBox:SetMaxInputChars(50)
    searchBox:SetMouseEnabled(true)
    searchBox:SetText("")
    -- Clicking the box should focus it for typing. Some custom (non-dialog)
    -- editboxes do not auto-focus reliably, so take focus explicitly.
    searchBox:SetHandler("OnMouseUp", function(self)
        self:TakeFocus()
    end)

    searchBox:SetHandler("OnTextChanged", function()
        -- suppressSearchEvent guards against the SetText we issue on a category
        -- open (which would otherwise re-trigger this and clobber the view).
        if not suppressSearchEvent then
            searchQuery = searchBox:GetText() or ""
            Populate()
        end
        searchHint:SetHidden((searchBox:GetText() or "") ~= "")
    end)
    -- Escape clears the search and drops focus, returning to the category view.
    searchBox:SetHandler("OnEscape", function(self)
        self:SetText("")
        self:LoseFocus()
    end)

    -- Snapshot buttons on the left of the toolbar row. "Remember" freezes the
    -- current composition; "Changes" switches to the diff view. ZO_DefaultButton's
    -- virtual height (~30) is taller than the 26px row, so force the height. Each
    -- gets a title+body hover tooltip (the headerCum idiom) since the
    -- manual-snapshot model is not self-evident.
    local BUTTON_WIDTH = 100
    local function WireButtonTooltip(button, titleId, bodyId)
        button:SetHandler("OnMouseEnter", function(self)
            InitializeTooltip(InformationTooltip, self, BOTTOM, 0, -2, TOP)
            InformationTooltip:AddLine(GetString(titleId), "ZoFontWinH5", 0.44, 0.80, 0.62)
            ZO_Tooltip_AddDivider(InformationTooltip)
            InformationTooltip:AddLine(GetString(bodyId), "ZoFontGame", 0.78, 0.77, 0.72)
        end)
        button:SetHandler("OnMouseExit", function()
            ClearTooltip(InformationTooltip)
        end)
    end

    local rememberButton = WINDOW_MANAGER:CreateControlFromVirtual(
        addon.name .. "_DetailRemember", windowControl, "ZO_DefaultButton")
    rememberButton:SetDimensions(BUTTON_WIDTH, TITLE_HEIGHT)
    rememberButton:SetAnchor(TOPLEFT, windowControl, TOPLEFT, PADDING, toolbarY)
    rememberButton:SetText(GetString(SI_BMW_DETAIL_BTN_REMEMBER))
    rememberButton:SetHandler("OnClicked", function()
        local snapshot = addon.Valuation.CaptureSnapshot()
        -- Confirm the save in chat with what was captured, so the action has
        -- visible feedback even when the diff view isn't open to show the reset.
        if snapshot then
            private.ChatInfo(SI_BMW_MSG_SNAPSHOT_SAVED, snapshot.slots or 0,
                ZO_LocalizeDecimalNumber(zo_round(snapshot.gold or 0)))
        end
        -- If the diff view is open, refresh it so it reflects the new baseline
        -- (it will now read "nothing changed"); otherwise just leave it.
        if viewMode == "diff" then
            Populate()
        end
    end)
    WireButtonTooltip(rememberButton, SI_BMW_DETAIL_BTN_REMEMBER_TOOLTIP_TITLE,
        SI_BMW_DETAIL_BTN_REMEMBER_TOOLTIP_BODY)

    changesButton = WINDOW_MANAGER:CreateControlFromVirtual(
        addon.name .. "_DetailChanges", windowControl, "ZO_DefaultButton")
    changesButton:SetDimensions(BUTTON_WIDTH, TITLE_HEIGHT)
    changesButton:SetAnchor(TOPLEFT, rememberButton, TOPRIGHT, 8, 0)
    changesButton:SetText(GetString(SI_BMW_DETAIL_BTN_CHANGES))
    -- This button is a toggle: in the material views it opens the diff ("Changes");
    -- in the diff view it returns to the material list ("Back"). The label is kept
    -- in step by UpdateChangesButton (called from each Show*). Its action and
    -- tooltip read viewMode at event time so the single bound handler covers both.
    changesButton:SetHandler("OnClicked", function()
        if viewMode == "diff" then
            DetailWindow.ShowMaterials()
        else
            DetailWindow.ShowDiff()
        end
    end)
    changesButton:SetHandler("OnMouseEnter", function(self)
        local titleId, bodyId
        if viewMode == "diff" then
            titleId, bodyId = SI_BMW_DETAIL_BTN_BACK_TOOLTIP_TITLE, SI_BMW_DETAIL_BTN_BACK_TOOLTIP_BODY
        else
            titleId, bodyId = SI_BMW_DETAIL_BTN_CHANGES_TOOLTIP_TITLE, SI_BMW_DETAIL_BTN_CHANGES_TOOLTIP_BODY
        end
        InitializeTooltip(InformationTooltip, self, BOTTOM, 0, -2, TOP)
        InformationTooltip:AddLine(GetString(titleId), "ZoFontWinH5", 0.44, 0.80, 0.62)
        ZO_Tooltip_AddDivider(InformationTooltip)
        InformationTooltip:AddLine(GetString(bodyId), "ZoFontGame", 0.78, 0.77, 0.72)
    end)
    changesButton:SetHandler("OnMouseExit", function()
        ClearTooltip(InformationTooltip)
    end)

    -- "Clear" forgets the saved snapshot. Sits after "Changes" on the toolbar.
    -- No modal confirm: "Remember" already overwrites the snapshot without one, so
    -- requiring confirmation only here would be inconsistent; the hover tooltip
    -- carries the "cannot be undone" warning. When the diff view is open, clearing
    -- refreshes it so it drops to the "press Remember" empty state immediately.
    local clearButton = WINDOW_MANAGER:CreateControlFromVirtual(
        addon.name .. "_DetailClear", windowControl, "ZO_DefaultButton")
    clearButton:SetDimensions(BUTTON_WIDTH, TITLE_HEIGHT)
    clearButton:SetAnchor(TOPLEFT, changesButton, TOPRIGHT, 8, 0)
    clearButton:SetText(GetString(SI_BMW_DETAIL_BTN_CLEAR))
    clearButton:SetHandler("OnClicked", function()
        -- Destructive and not undoable, so confirm before clearing. The dialog's
        -- accept callback (registered below) does the actual clear + chat notice.
        ZO_Dialogs_ShowDialog(CLEAR_SNAPSHOT_DIALOG)
    end)
    WireButtonTooltip(clearButton, SI_BMW_DETAIL_BTN_CLEAR_TOOLTIP_TITLE,
        SI_BMW_DETAIL_BTN_CLEAR_TOOLTIP_BODY)

    -- Column headers, aligned to the same geometry as the XML row template. They
    -- sit below the toolbar row.
    local headerY = toolbarY + TITLE_HEIGHT + TOOLBAR_GAP

    headerChange = WINDOW_MANAGER:CreateControl(addon.name .. "_DetailHeaderChange", windowControl, CT_LABEL)
    headerChange:SetFont("ZoFontGameSmall")
    headerChange:SetHorizontalAlignment(TEXT_ALIGN_RIGHT)
    headerChange:SetDimensions(90, HEADER_HEIGHT)
    headerChange:SetAnchor(TOPRIGHT, windowControl, TOPRIGHT, -PADDING - 4, headerY)
    headerChange:SetText(Colorize(COLOR_MUTED, GetString(SI_BMW_DETAIL_COL_CHANGE)))

    -- Cumulative-share header. Unlike the others it is NOT a sort toggle (sorting
    -- by cumulative share would be identical to sorting by value), so it is a
    -- plain muted label and is skipped by WireHeaderSort/UpdateHeaders below.
    headerCum = WINDOW_MANAGER:CreateControl(addon.name .. "_DetailHeaderCum", windowControl, CT_LABEL)
    headerCum:SetFont("ZoFontGameSmall")
    headerCum:SetHorizontalAlignment(TEXT_ALIGN_RIGHT)
    headerCum:SetDimensions(70, HEADER_HEIGHT)
    headerCum:SetAnchor(TOPRIGHT, headerChange, TOPLEFT, -6, 0)
    headerCum:SetText(Colorize(COLOR_MUTED, GetString(SI_BMW_DETAIL_COL_CUM)))

    -- The column abbreviation can't carry its full meaning, so a hover tooltip on
    -- the header spells it out: a bold title line, a divider, then the
    -- explanation. Matches the (text, font, r, g, b) AddLine idiom used by the
    -- row tooltip below; InformationTooltip wraps a long line to its own width.
    headerCum:SetMouseEnabled(true)
    headerCum:SetHandler("OnMouseEnter", function(self)
        InitializeTooltip(InformationTooltip, self, TOP, 0, 4, BOTTOM)
        InformationTooltip:AddLine(GetString(SI_BMW_DETAIL_CUM_TOOLTIP_TITLE),
            "ZoFontWinH5", 0.44, 0.80, 0.62)
        ZO_Tooltip_AddDivider(InformationTooltip)
        InformationTooltip:AddLine(GetString(SI_BMW_DETAIL_CUM_TOOLTIP_BODY),
            "ZoFontGame", 0.78, 0.77, 0.72)
    end)
    headerCum:SetHandler("OnMouseExit", function()
        ClearTooltip(InformationTooltip)
    end)

    headerValue = WINDOW_MANAGER:CreateControl(addon.name .. "_DetailHeaderValue", windowControl, CT_LABEL)
    headerValue:SetFont("ZoFontGameSmall")
    headerValue:SetHorizontalAlignment(TEXT_ALIGN_RIGHT)
    headerValue:SetDimensions(150, HEADER_HEIGHT)
    headerValue:SetAnchor(TOPRIGHT, headerCum, TOPLEFT, -6, 0)
    headerValue:SetText(Colorize(COLOR_MUTED, GetString(SI_BMW_DETAIL_COL_VALUE)))

    headerQty = WINDOW_MANAGER:CreateControl(addon.name .. "_DetailHeaderQty", windowControl, CT_LABEL)
    headerQty:SetFont("ZoFontGameSmall")
    headerQty:SetHorizontalAlignment(TEXT_ALIGN_RIGHT)
    headerQty:SetDimensions(70, HEADER_HEIGHT)
    headerQty:SetAnchor(TOPRIGHT, headerValue, TOPLEFT, -6, 0)
    headerQty:SetText(Colorize(COLOR_MUTED, GetString(SI_BMW_DETAIL_COL_QTY)))

    headerName = WINDOW_MANAGER:CreateControl(addon.name .. "_DetailHeaderName", windowControl, CT_LABEL)
    headerName:SetFont("ZoFontGameSmall")
    headerName:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
    headerName:SetAnchor(TOPLEFT, windowControl, TOPLEFT, PADDING + 2, headerY)
    headerName:SetText(Colorize(COLOR_MUTED, GetString(SI_BMW_DETAIL_COL_NAME)))

    -- Make each header a sort toggle. Clicking the active column flips its
    -- direction; clicking another switches to it with a sensible default (A->Z
    -- for the name, biggest-first for the numeric columns - that is what a
    -- player scanning for "what to sell" wants). Numeric columns default to
    -- descending; the name column to ascending. The headers are plain labels, so
    -- enable mouse and bind OnMouseUp directly; the existing right-aligned
    -- geometry already gives each a generous hit box.
    local function WireHeaderSort(headerControl, key, defaultAsc)
        headerControl:SetMouseEnabled(true)
        headerControl:SetHandler("OnMouseUp", function(_, button, upInside)
            -- Headers do not sort in diff mode (the order is fixed); ignore clicks.
            if viewMode == "diff" then
                return
            end
            if not upInside or button ~= MOUSE_BUTTON_INDEX_LEFT then
                return
            end
            if sortKey == key then
                sortAsc = not sortAsc
            else
                sortKey = key
                sortAsc = defaultAsc
            end
            UpdateHeaders()
            Populate()
        end)
        headerControl:SetHandler("OnMouseEnter", function(self)
            -- No brighten-on-hover affordance when the header isn't clickable.
            if viewMode == "diff" then
                return
            end
            self:SetColor(1, 1, 1, 1)
        end)
        headerControl:SetHandler("OnMouseExit", function()
            UpdateHeaders()
        end)
    end
    WireHeaderSort(headerName, "name", true)
    WireHeaderSort(headerQty, "qty", false)
    WireHeaderSort(headerValue, "value", false)
    WireHeaderSort(headerChange, "change", false)
    UpdateHeaders()

    -- Divider under the headers.
    local dividerY = headerY + HEADER_HEIGHT
    divider = WINDOW_MANAGER:CreateControl(addon.name .. "_DetailDivider", windowControl, CT_TEXTURE)
    divider:SetTexture("EsoUI/Art/Miscellaneous/horizontalDivider.dds")
    divider:SetDimensions(innerWidth, 4)
    divider:SetColor(1, 1, 1, 0.4)
    divider:SetAnchor(TOPLEFT, windowControl, TOPLEFT, PADDING, dividerY)

    -- Scroll list, instantiated from the XML virtual so its rows can be
    -- recycled. Sized to LIST_MAX_ROWS; longer categories scroll.
    local listY = dividerY + DIVIDER_GAP
    listControl = WINDOW_MANAGER:CreateControlFromVirtual(
        addon.name .. "_DetailListControl", windowControl, "BureauOfMaterialWorth_DetailList")
    listControl:SetDimensions(innerWidth, ROW_HEIGHT * LIST_MAX_ROWS)
    listControl:SetAnchor(TOPLEFT, windowControl, TOPLEFT, PADDING, listY)

    ZO_ScrollList_Initialize(listControl)
    ZO_ScrollList_AddDataType(listControl, ROW_TYPE_ID,
        "BureauOfMaterialWorth_DetailRow", ROW_HEIGHT, SetupRow)

    emptyLabel = WINDOW_MANAGER:CreateControl(addon.name .. "_DetailEmpty", windowControl, CT_LABEL)
    emptyLabel:SetFont("ZoFontGame")
    emptyLabel:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
    emptyLabel:SetAnchor(TOPLEFT, listControl, TOPLEFT, 0, 0)
    emptyLabel:SetAnchor(TOPRIGHT, listControl, TOPRIGHT, 0, 0)
    emptyLabel:SetText(Colorize(COLOR_MUTED, GetString(SI_BMW_DETAIL_EMPTY)))
    emptyLabel:SetHidden(true)

    -- Summary line beneath the list, mirroring the main panel's footer so the two
    -- windows read as one family. A divider sets it off from the list; the label
    -- itself is filled by UpdateFooter for the active view (category/search count +
    -- value + bag share, or the diff's net movement). Right-aligned so the figure
    -- sits under the value columns.
    local footerDividerY = listY + ROW_HEIGHT * LIST_MAX_ROWS + DIVIDER_GAP
    footerDivider = WINDOW_MANAGER:CreateControl(addon.name .. "_DetailFooterDivider", windowControl, CT_TEXTURE)
    footerDivider:SetTexture("EsoUI/Art/Miscellaneous/horizontalDivider.dds")
    footerDivider:SetDimensions(innerWidth, 4)
    footerDivider:SetColor(1, 1, 1, 0.4)
    footerDivider:SetAnchor(TOPLEFT, windowControl, TOPLEFT, PADDING, footerDividerY)

    footerLabel = WINDOW_MANAGER:CreateControl(addon.name .. "_DetailFooter", windowControl, CT_LABEL)
    footerLabel:SetFont("ZoFontGameSmall")
    footerLabel:SetHorizontalAlignment(TEXT_ALIGN_RIGHT)
    footerLabel:SetVerticalAlignment(TEXT_ALIGN_CENTER)
    footerLabel:SetDimensions(innerWidth, FOOTER_HEIGHT)
    footerLabel:SetAnchor(TOPLEFT, windowControl, TOPLEFT, PADDING, footerDividerY + DIVIDER_GAP)

    windowControl:SetHeight(footerDividerY + DIVIDER_GAP + FOOTER_HEIGHT + PADDING)
end

-- Fill the scroll list from a prebuilt materials array.
function FillList(materials)
    local dataList = ZO_ScrollList_GetDataList(listControl)
    ZO_ScrollList_Clear(listControl)

    for i = 1, #materials do
        dataList[#dataList + 1] = ZO_ScrollList_CreateDataEntry(ROW_TYPE_ID, materials[i])
    end

    -- Commit is what triggers (re)layout of the visible rows; without it the
    -- list renders blank.
    ZO_ScrollList_Commit(listControl)

    emptyLabel:SetHidden(#materials > 0)
end

-- Re-sort the material rows in place by the active column. The Valuation getters
-- already return rows sorted by name; this overrides that with the user's chosen
-- column. Name ties (and ties on any numeric column) fall back to name then
-- itemId so the order is stable across rebuilds and the value/change views read
-- alphabetically within equal figures.
--
-- Unpriced rows carry gold = 0 and growthPercent = nil. On the numeric columns
-- they always sink to the bottom regardless of direction, so toggling a column
-- never buries a real figure beneath the priceless ones.
local function SortMaterials(materials)
    -- Diff mode has a fixed order: biggest absolute gold movement first, so the
    -- materials that moved the most value sit on top. Secondary by absolute count
    -- delta so a large unpriced add/remove (no gold figure) still surfaces, then
    -- name/itemId for stability. The column headers do not sort in this mode.
    if viewMode == "diff" then
        tablesort(materials, function(a, b)
            local ag, bg = mathabs(a.goldDelta or 0), mathabs(b.goldDelta or 0)
            if ag ~= bg then
                return ag > bg
            end
            local ac, bc = mathabs(a.countDelta or 0), mathabs(b.countDelta or 0)
            if ac ~= bc then
                return ac > bc
            end
            if a.name ~= b.name then
                return a.name < b.name
            end
            return a.itemId < b.itemId
        end)
        return
    end

    if sortKey == "name" then
        tablesort(materials, function(a, b)
            if a.name ~= b.name then
                if sortAsc then return a.name < b.name end
                return a.name > b.name
            end
            return a.itemId < b.itemId
        end)
        return
    end

    tablesort(materials, function(a, b)
        local av, bv
        if sortKey == "qty" then
            av, bv = a.count or 0, b.count or 0
        elseif sortKey == "change" then
            -- Unpriced or no-baseline rows have no comparable change; treat as
            -- the lowest so they sink. nil < any real percentage.
            av = (a.priced and not a.isNew) and a.growthPercent or nil
            bv = (b.priced and not b.isNew) and b.growthPercent or nil
        else  -- "value"
            av, bv = a.gold or 0, b.gold or 0
        end

        -- Push nils to the bottom irrespective of sort direction.
        if av == nil or bv == nil then
            if av == bv then
                return a.name < b.name
            end
            return bv == nil
        end

        if av ~= bv then
            if sortAsc then return av < bv end
            return av > bv
        end
        -- Stable tie-break: alphabetical, then itemId.
        if a.name ~= b.name then
            return a.name < b.name
        end
        return a.itemId < b.itemId
    end)
end

-- Assign each row its cumulative share (percent) of the list's total value.
-- Deliberately decoupled from the active sort: accumulation ALWAYS proceeds from
-- the most valuable material downward, so a row's figure is a stable property -
-- "this material plus everything worth more is N% of the list's value" - that
-- does not change when the user re-sorts by name or quantity. On the default
-- value-descending view it then reads cleanly top-down 0->100. The useful signal
-- is where the top rows cross ~80% (the few stacks holding most of the worth),
-- not the trailing 100%, which by definition lands on the cheapest priced row.
-- Rows with no value are left nil so they show a dash. A zero-value list leaves
-- every row nil.
local function AssignCumulativeShare(materials)
    -- The weight each row contributes: its value in the category/search view, or
    -- the magnitude of its gold movement in the diff view. Both read top-down as
    -- "the rows down to here are N% of the total".
    local function weightOf(row)
        if viewMode == "diff" then
            return mathabs(row.goldDelta or 0)
        end
        return row.gold or 0
    end

    local total = 0
    for i = 1, #materials do
        total = total + weightOf(materials[i])
    end

    if total <= 0 then
        for i = 1, #materials do
            materials[i].cumPercent = nil
        end
        return
    end

    -- Rank by descending weight, independent of how the list is displayed. The
    -- tie-break (name, then itemId) mirrors SortMaterials so equal-weight rows
    -- accumulate in a stable order. We sort an index list rather than the
    -- materials array so the caller's chosen display order is untouched.
    local order = {}
    for i = 1, #materials do
        order[i] = i
    end
    tablesort(order, function(ia, ib)
        local a, b = materials[ia], materials[ib]
        local av, bv = weightOf(a), weightOf(b)
        if av ~= bv then
            return av > bv
        end
        if a.name ~= b.name then
            return a.name < b.name
        end
        return a.itemId < b.itemId
    end)

    local running = 0
    for rank = 1, #order do
        local mat = materials[order[rank]]
        local weight = weightOf(mat)
        if weight > 0 then
            running = running + weight
            mat.cumPercent = zo_round(running / total * 100)
        else
            mat.cumPercent = nil
        end
    end
end

-- Fill the summary line beneath the list from the just-built materials array.
-- Mirrors the main panel's footer so the two windows read as one family.
--   category/search : "Materials: N · <total> · M% of bag" - the count, the summed
--                     value of the shown rows, and that value's share of the whole
--                     bag (omitted when the bag total is zero / unavailable).
--   diff            : "Net: <signed gold> · X up · Y down" - the net gold movement
--                     and how many materials rose vs fell.
-- Records the row count for the title's search counter as a side effect, so the
-- two always agree. An empty list shows a plain count (or net of zero) rather than
-- blanking, so the line never looks broken.
local function UpdateFooter(materials)
    currentResultCount = #materials

    if viewMode == "diff" then
        local net, up, down = 0, 0, 0
        for i = 1, #materials do
            local delta = materials[i].goldDelta or 0
            net = net + delta
            -- Count direction by the quantity move, not the gold figure, so an
            -- unpriced add/remove (goldDelta 0) is still tallied.
            if (materials[i].countDelta or 0) >= 0 then
                up = up + 1
            else
                down = down + 1
            end
        end

        local gain = net >= 0
        local color = gain and COLOR_GAIN or COLOR_LOSS
        local arrow = gain and ARROW_UP or ARROW_DOWN
        local netText = arrow .. " " .. Colorize(color,
            ZO_LocalizeDecimalNumber(zo_round(mathabs(net)))) .. " " .. GOLD_ICON
        local parts = {
            Colorize(COLOR_MUTED, GetString(SI_BMW_DETAIL_FOOTER_NET)) .. " " .. netText,
            Colorize(COLOR_GAIN, stringformat(GetString(SI_BMW_DETAIL_FOOTER_GAINED), up)),
            Colorize(COLOR_LOSS, stringformat(GetString(SI_BMW_DETAIL_FOOTER_LOST), down)),
        }
        footerLabel:SetText(table.concat(parts, Colorize(COLOR_MUTED, "  ·  ")))
        return
    end

    -- Category / search view: count + summed value + share of the whole bag.
    local total = 0
    for i = 1, #materials do
        total = total + (materials[i].gold or 0)
    end

    local parts = {
        Colorize(COLOR_MUTED, stringformat(GetString(SI_BMW_DETAIL_FOOTER_COUNT), #materials)),
        FormatGold(total),
    }

    -- Share of the whole bag's value, when the grand total is known and non-zero.
    -- GetStatus returns the live grand total cheaply (no category rebuild).
    local grandGold = addon.Valuation.GetStatus()
    if grandGold and grandGold > 0 then
        local share = zo_round(total / grandGold * 100)
        parts[#parts + 1] = Colorize(COLOR_MUTED,
            stringformat(GetString(SI_BMW_DETAIL_FOOTER_SHARE), share))
    end

    footerLabel:SetText(table.concat(parts, Colorize(COLOR_MUTED, "  ·  ")))
end

-- Rebuild the scroll list for the current view. Three sources route through here:
-- the diff list (viewMode == "diff"), the whole-bag search results (a query is
-- active), or the current category. Centralized so the search box, a category
-- open, the diff buttons, and the live refresh all share one path. Also sets the
-- empty-state label to match the mode, since FillList only toggles its
-- visibility, not its text.
function Populate()
    local materials
    if viewMode == "diff" then
        if not addon.Valuation.HasSnapshot() then
            -- No snapshot to diff against: show the "press Remember" prompt.
            emptyLabel:SetText(Colorize(COLOR_MUTED, GetString(SI_BMW_DETAIL_NO_SNAPSHOT)))
            FillList({})
            UpdateFooter({})
            UpdateTitle()
            return
        end
        materials = addon.Valuation.GetDiffMaterials()
        emptyLabel:SetText(Colorize(COLOR_MUTED, GetString(SI_BMW_DETAIL_DIFF_EMPTY)))
    else
        if searchQuery ~= "" then
            materials = addon.Valuation.GetMaterialsMatching(searchQuery)
        elseif currentCategoryId then
            materials = addon.Valuation.GetCategoryMaterials(currentCategoryId)
        else
            materials = {}
        end
        emptyLabel:SetText(Colorize(COLOR_MUTED, GetString(SI_BMW_DETAIL_EMPTY)))
    end

    SortMaterials(materials)
    AssignCumulativeShare(materials)
    FillList(materials)
    UpdateFooter(materials)
    -- The title's search counter reflects what was just built, so refresh it here
    -- (after UpdateFooter set the count) rather than at each call site. This also
    -- keeps the live Refresh path's counter truthful as stock changes.
    UpdateTitle()
end

-- Keep the title in step with the view: the diff label while comparing, the
-- searched-across-bag label while a query is active, otherwise the category name.
function UpdateTitle()
    if viewMode == "diff" then
        local info = addon.Valuation.GetSnapshotInfo()
        local whenText
        if info and info.t then
            whenText = FormatSnapshotAge(info.t)
        else
            whenText = GetString(SI_BMW_TIME_NEVER)
        end
        titleLabel:SetText(Colorize(COLOR_ACCENT,
            stringformat(GetString(SI_BMW_DETAIL_DIFF_TITLE), whenText)))
    elseif searchQuery ~= "" then
        -- Search title carries the match count (set by UpdateFooter, which runs
        -- just before this in Populate) so the user sees how many rows matched.
        titleLabel:SetText(Colorize(COLOR_ACCENT,
            stringformat(GetString(SI_BMW_DETAIL_SEARCH_TITLE), currentResultCount)))
    else
        titleLabel:SetText(Colorize(COLOR_ACCENT,
            stringformat(GetString(SI_BMW_DETAIL_TITLE), currentCategoryName or "")))
    end
end

-- Re-label the four column headers, appending a sort arrow to the active one so
-- the player can see which column orders the list and in which direction. The
-- arrow textures match the price-change column's idiom (the UI font won't render
-- the Unicode triangles). Tone is driven by SetColor (not an inline |c code) so
-- the hover handlers can brighten a header without fighting an embedded color.
-- Called after any sort-state change and on each open.
function UpdateHeaders()
    -- Diff mode relabels the four columns to their delta/status meaning and shows
    -- no sort arrow (the order is fixed to abs-gold-desc). The name header keeps
    -- its label. Cum is repurposed to "Share".
    if viewMode == "diff" then
        headerName:SetText(GetString(SI_BMW_DETAIL_COL_NAME))
        headerQty:SetText(GetString(SI_BMW_DETAIL_COL_QTY_DELTA))
        headerValue:SetText(GetString(SI_BMW_DETAIL_COL_VALUE_DELTA))
        headerCum:SetText(GetString(SI_BMW_DETAIL_COL_SHARE))
        headerChange:SetText(GetString(SI_BMW_DETAIL_COL_STATUS))
        headerName:SetColor(HEADER_MUTED_R, HEADER_MUTED_G, HEADER_MUTED_B, 1)
        headerQty:SetColor(HEADER_MUTED_R, HEADER_MUTED_G, HEADER_MUTED_B, 1)
        headerValue:SetColor(HEADER_MUTED_R, HEADER_MUTED_G, HEADER_MUTED_B, 1)
        headerCum:SetColor(HEADER_MUTED_R, HEADER_MUTED_G, HEADER_MUTED_B, 1)
        headerChange:SetColor(HEADER_MUTED_R, HEADER_MUTED_G, HEADER_MUTED_B, 1)
        return
    end

    local arrow = sortAsc and ARROW_UP or ARROW_DOWN
    local function apply(headerControl, stringId, key)
        local text = GetString(stringId)
        if sortKey == key then
            text = text .. " " .. arrow
        end
        headerControl:SetText(text)
        headerControl:SetColor(HEADER_MUTED_R, HEADER_MUTED_G, HEADER_MUTED_B, 1)
    end
    apply(headerName, SI_BMW_DETAIL_COL_NAME, "name")
    apply(headerQty, SI_BMW_DETAIL_COL_QTY, "qty")
    apply(headerValue, SI_BMW_DETAIL_COL_VALUE, "value")
    apply(headerChange, SI_BMW_DETAIL_COL_CHANGE, "change")
    -- The Cum header is non-sortable; restore its plain label (UpdateHeaders may
    -- be returning from diff mode, which overwrote it with "Share").
    headerCum:SetText(GetString(SI_BMW_DETAIL_COL_CUM))
    headerCum:SetColor(HEADER_MUTED_R, HEADER_MUTED_G, HEADER_MUTED_B, 1)
end

-- Keep the toggle button's label in step with the mode: "Back" while the diff is
-- shown, "Changes" otherwise. The action and tooltip read viewMode at event time
-- (see Initialize), so only the label needs refreshing here.
local function UpdateChangesButton()
    if not changesButton then
        return
    end
    if viewMode == "diff" then
        changesButton:SetText(GetString(SI_BMW_DETAIL_BTN_BACK))
    else
        changesButton:SetText(GetString(SI_BMW_DETAIL_BTN_CHANGES))
    end
end

function DetailWindow.Show(categoryId, categoryName)
    if not windowControl then
        return
    end

    viewMode = "category"
    currentCategoryId = categoryId
    currentCategoryName = categoryName

    -- A fresh category open clears any prior search so the user sees the category
    -- they clicked, not stale search results.
    searchQuery = ""
    suppressSearchEvent = true
    searchBox:SetText("")
    suppressSearchEvent = false

    -- Start every open from the value-descending default - the "what to sell
    -- right now" order - regardless of how the previous view was sorted.
    sortKey = "value"
    sortAsc = false

    UpdateChangesButton()
    UpdateHeaders()
    Populate()
    windowControl:SetHidden(false)
    windowControl:BringWindowToTop()
end

-- Return from the diff view to the material list, restoring the category that was
-- open before (remembered in currentCategoryId). Reached via the toolbar toggle,
-- which reads "Back" in diff mode. Leaves the window open; only the mode flips.
function DetailWindow.ShowMaterials()
    if not windowControl then
        return
    end

    viewMode = "category"
    searchQuery = ""
    suppressSearchEvent = true
    searchBox:SetText("")
    suppressSearchEvent = false

    -- Back to the default value-descending order, matching a fresh category open.
    sortKey = "value"
    sortAsc = false

    UpdateChangesButton()
    UpdateHeaders()
    Populate()
end

-- Switch the window to the snapshot-diff view. Reachable from the "Changes"
-- button; when no snapshot exists Populate shows the "press Remember" prompt
-- rather than a list, so this is always safe to call. Reuses whatever category
-- context is loaded so leaving the diff (the "Back" toggle) restores it.
function DetailWindow.ShowDiff()
    if not windowControl then
        return
    end

    viewMode = "diff"
    -- The diff spans the whole bag, so any active search is irrelevant here.
    searchQuery = ""
    suppressSearchEvent = true
    searchBox:SetText("")
    suppressSearchEvent = false

    UpdateChangesButton()
    UpdateHeaders()
    Populate()
    windowControl:SetHidden(false)
    windowControl:BringWindowToTop()
end

function DetailWindow.Hide()
    if windowControl then
        windowControl:SetHidden(true)
    end
end

-- Re-render the current view in place. Called from Valuation's coalesced refresh
-- after a slot change (e.g. a withdrawal shrank a stack) so the Qty/Value columns
-- stay truthful, and respects an active search. A no-op when the window is hidden.
function DetailWindow.Refresh()
    if not windowControl or windowControl:IsHidden() then
        return
    end
    Populate()
end

-- The top-level control, exposed so the withdraw popup/queue can anchor to it
-- (centered popup, queue magnetized to its right edge) rather than scattering
-- floating windows. Returns nil before Initialize.
function DetailWindow.GetWindowControl()
    return windowControl
end

-- Hide the detail window when the craft bag closes, so it doesn't linger over
-- the rest of the UI with stale data. Called from the fragment wiring.
function DetailWindow.OnCraftBagHidden()
    DetailWindow.Hide()
end
