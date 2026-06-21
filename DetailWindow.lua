local addon = BureauOfMaterialWorth
addon.DetailWindow = addon.DetailWindow or {}

local DetailWindow = addon.DetailWindow
local private = addon.private

local GetString = GetString
local stringformat = string.format
local zo_round = zo_round
local mathabs = math.abs

-- Palette (shared house style with Window.lua). Kept as a local copy rather than
-- reaching into Window.lua's locals so the two presentation modules stay
-- decoupled; these values are stable brand colors.
local COLOR_ACCENT = "6FCB9F"  -- brand green: title
local COLOR_MUTED  = "8C8A82"  -- dim grey: headers / secondary
local COLOR_GOLD   = "F4D03F"  -- soft gold: gold figures
local COLOR_GAIN   = "8FCB9F"  -- green: positive price change
local COLOR_LOSS   = "D08A8A"  -- soft red: negative price change

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

-- Populate one recycled row from its material record. Mirrors the column
-- geometry declared in DetailWindow.xml.
local function SetupRow(rowControl, data)
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
    titleLabel:SetAnchor(TOPLEFT, windowControl, TOPLEFT, PADDING, PADDING)

    -- Close button (built-in virtual) anchored top-right.
    local closeButton = WINDOW_MANAGER:CreateControlFromVirtual(
        addon.name .. "_DetailClose", windowControl, "ZO_CloseButton")
    closeButton:SetAnchor(TOPRIGHT, windowControl, TOPRIGHT, -PADDING, PADDING)
    closeButton:SetHandler("OnClicked", function()
        DetailWindow.Hide()
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

-- Rebuild the scroll list from the current category's materials. Separate from
-- Show so a future live refresh can reuse it.
local function Populate(categoryId)
    local materials = addon.Valuation.GetCategoryMaterials(categoryId)

    local dataList = ZO_ScrollList_GetDataList(listControl)
    ZO_ScrollList_Clear(listControl)

    for i = 1, #materials do
        dataList[#dataList + 1] = ZO_ScrollList_CreateDataEntry(ROW_TYPE_ID, materials[i])
    end

    -- Commit is what triggers (re)layout of the visible rows; without it the
    -- list renders blank.
    ZO_ScrollList_Commit(listControl)

    local isEmpty = #materials == 0
    emptyLabel:SetHidden(not isEmpty)
end

function DetailWindow.Show(categoryId, categoryName)
    if not windowControl then
        return
    end

    currentCategoryId = categoryId
    titleLabel:SetText(Colorize(COLOR_ACCENT,
        stringformat(GetString(SI_BMW_DETAIL_TITLE), categoryName or "")))

    Populate(categoryId)
    windowControl:SetHidden(false)
    windowControl:BringWindowToTop()
end

function DetailWindow.Hide()
    if windowControl then
        windowControl:SetHidden(true)
    end
end

-- Hide the detail window when the craft bag closes, so it doesn't linger over
-- the rest of the UI with stale data. Called from the fragment wiring.
function DetailWindow.OnCraftBagHidden()
    DetailWindow.Hide()
end
