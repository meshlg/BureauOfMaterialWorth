local addon = BureauOfMaterialWorth
addon.DetailWindow = addon.DetailWindow or {}

local DetailWindow = addon.DetailWindow
local private = addon.private

local GetString = GetString
local stringformat = string.format
local zo_round = zo_round
local mathabs = math.abs
local tablesort = table.sort

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

local GOLD_ICON = "|t16:16:EsoUI/Art/currency/currency_gold.dds|t"
-- Same sort-arrow textures Window.lua uses for its delta, for the same reason:
-- the ESO UI font doesn't render the Unicode triangles reliably.
local ARROW_UP = "|t16:16:EsoUI/Art/Miscellaneous/list_sortUp.dds|t"
local ARROW_DOWN = "|t16:16:EsoUI/Art/Miscellaneous/list_sortDown.dds|t"

-- Layout
-- ---------------------------------------------------------------------------
local WINDOW_WIDTH = 720
local PADDING      = 12
local TITLE_HEIGHT = 26
local HEADER_HEIGHT = 20
local DIVIDER_GAP  = 10
local ROW_HEIGHT   = 26
local LIST_MAX_ROWS = 16   -- beyond this the list scrolls instead of growing
local BG_ALPHA     = 0.92

-- Single row data type id for the scroll list (we only have one kind of row).
local ROW_TYPE_ID = 1

local function Colorize(hex, text)
    return stringformat("|c%s%s|r", hex, text)
end

local function FormatGold(amount)
    return Colorize(COLOR_GOLD, ZO_LocalizeDecimalNumber(zo_round(amount or 0))) .. " " .. GOLD_ICON
end

-- Runtime control references, created once in Initialize().
local windowControl   -- top-level container
local backdrop        -- background + border
local titleLabel      -- "<Category> - materials"
local headerName, headerQty, headerValue, headerChange  -- column headers
local divider
local listControl     -- ZO_ScrollList
local emptyLabel      -- shown when the category has no materials
local currentCategoryId  -- remembered so a refresh can rebuild the same view
local currentCategoryName  -- remembered so the title can restore after a search
local searchBox       -- the search editbox
local searchQuery = ""  -- current search text; "" means "show the category"
local suppressSearchEvent = false  -- guards the search box against its own SetText

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

    rowControl:GetNamedChild("Qty"):SetText(
        Colorize(COLOR_MUTED, ZO_LocalizeDecimalNumber(data.count or 0)))

    rowControl:GetNamedChild("Value"):SetText(FormatGold(data.gold))

    -- Price-change column: an up/down arrow (the texture carries the direction)
    -- plus a colored magnitude, matching Window.lua's footer-delta idiom. A
    -- material with no recorded baseline yet, or no price at all, shows an
    -- em-dash instead.
    local changeLabel = rowControl:GetNamedChild("Change")
    if data.priced and not data.isNew and data.growthPercent ~= nil then
        local gain = data.growthDir
        local color = gain and COLOR_GAIN or COLOR_LOSS
        local arrow = gain and ARROW_UP or ARROW_DOWN
        local magnitude = stringformat("%.1f", mathabs(data.growthPercent))
        changeLabel:SetText(arrow .. " " .. Colorize(color,
            stringformat(GetString(SI_BMW_DETAIL_GROWTH), magnitude)))
    else
        changeLabel:SetText(Colorize(COLOR_MUTED, GetString(SI_BMW_DETAIL_GROWTH_NEW)))
    end

    -- Bind the interaction handlers once per recycled control (sentinel), then
    -- let them read rowControl.bmwData at event time. Left click opens the
    -- withdraw popup for this material; right click adds it to the withdraw
    -- queue. A hover tooltip spells out both, matching Window.lua's affordance.
    if not rowControl.bmwClickBound then
        rowControl.bmwClickBound = true

        rowControl:SetHandler("OnMouseUp", function(self, button, upInside)
            if not upInside then
                return
            end
            local rowData = self.bmwData
            local withdraw = addon.WithdrawDialog
            if not rowData or not withdraw then
                return
            end
            if button == MOUSE_BUTTON_INDEX_LEFT then
                withdraw.Open(rowData)
            elseif button == MOUSE_BUTTON_INDEX_RIGHT then
                withdraw.AddToQueue(rowData)
            end
        end)

        rowControl:SetHandler("OnMouseEnter", function(self)
            InitializeTooltip(InformationTooltip, self, BOTTOM, 0, -2, TOP)
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
    -- Stop the title before the search box so a long category name does not run
    -- under it (search box 220 wide + close button + paddings to the right).
    titleLabel:SetDimensions(WINDOW_WIDTH - PADDING * 2 - 220 - 32 - 16, TITLE_HEIGHT)

    -- Close button (built-in virtual) anchored top-right.
    local closeButton = WINDOW_MANAGER:CreateControlFromVirtual(
        addon.name .. "_DetailClose", windowControl, "ZO_CloseButton")
    closeButton:SetAnchor(TOPRIGHT, windowControl, TOPRIGHT, -PADDING, PADDING)
    closeButton:SetHandler("OnClicked", function()
        DetailWindow.Hide()
    end)

    -- Search box (whole-bag), to the left of the close button. Typing here
    -- switches the list to materials matching the query across every category;
    -- clearing it returns to the opened category. The title column is sized to
    -- leave room for it.
    local SEARCH_WIDTH = 220
    local searchBg = WINDOW_MANAGER:CreateControlFromVirtual(
        addon.name .. "_DetailSearchBg", windowControl, "ZO_DefaultBackdrop")
    searchBg:SetDimensions(SEARCH_WIDTH, TITLE_HEIGHT)
    searchBg:ClearAnchors()
    searchBg:SetAnchor(TOPRIGHT, windowControl, TOPRIGHT, -PADDING - 32, PADDING)
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
            UpdateTitle()
            Populate()
        end
        searchHint:SetHidden((searchBox:GetText() or "") ~= "")
    end)
    -- Escape clears the search and drops focus, returning to the category view.
    searchBox:SetHandler("OnEscape", function(self)
        self:SetText("")
        self:LoseFocus()
    end)

    -- Column headers, aligned to the same geometry as the XML row template.
    local headerY = PADDING + TITLE_HEIGHT

    headerChange = WINDOW_MANAGER:CreateControl(addon.name .. "_DetailHeaderChange", windowControl, CT_LABEL)
    headerChange:SetFont("ZoFontGameSmall")
    headerChange:SetHorizontalAlignment(TEXT_ALIGN_RIGHT)
    headerChange:SetDimensions(90, HEADER_HEIGHT)
    headerChange:SetAnchor(TOPRIGHT, windowControl, TOPRIGHT, -PADDING - 4, headerY)
    headerChange:SetText(Colorize(COLOR_MUTED, GetString(SI_BMW_DETAIL_COL_CHANGE)))

    headerValue = WINDOW_MANAGER:CreateControl(addon.name .. "_DetailHeaderValue", windowControl, CT_LABEL)
    headerValue:SetFont("ZoFontGameSmall")
    headerValue:SetHorizontalAlignment(TEXT_ALIGN_RIGHT)
    headerValue:SetDimensions(150, HEADER_HEIGHT)
    headerValue:SetAnchor(TOPRIGHT, headerChange, TOPLEFT, -6, 0)
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

    windowControl:SetHeight(listY + ROW_HEIGHT * LIST_MAX_ROWS + PADDING)
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

-- Rebuild the scroll list for the current view: the whole-bag search results
-- when a query is active, otherwise the current category. Centralized so the
-- search box, a category open, and the live refresh all route through one place.
function Populate()
    local materials
    if searchQuery ~= "" then
        materials = addon.Valuation.GetMaterialsMatching(searchQuery)
    elseif currentCategoryId then
        materials = addon.Valuation.GetCategoryMaterials(currentCategoryId)
    else
        materials = {}
    end

    SortMaterials(materials)
    FillList(materials)
end

-- Keep the title in step with the view: the searched-across-bag label while a
-- query is active, otherwise the category name.
function UpdateTitle()
    if searchQuery ~= "" then
        titleLabel:SetText(Colorize(COLOR_ACCENT, GetString(SI_BMW_DETAIL_SEARCH_TITLE)))
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
end

function DetailWindow.Show(categoryId, categoryName)
    if not windowControl then
        return
    end

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

    UpdateHeaders()
    UpdateTitle()
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
