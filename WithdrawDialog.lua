local addon = BureauOfMaterialWorth
addon.WithdrawDialog = addon.WithdrawDialog or {}

local WithdrawDialog = addon.WithdrawDialog
local private = addon.private

-- Hot-path / inventory globals cached to upvalues, same rationale as the other
-- modules: the withdrawal stepper touches these every tick across a multi-stack
-- run, and the capacity scan walks the whole backpack.
local GetString              = GetString
local stringformat           = string.format
local mathmin                = math.min
local mathmax                = math.max
local mathfloor              = math.floor
local tonumber               = tonumber
local CallSecureProtected    = CallSecureProtected
local GetSlotStackSize       = GetSlotStackSize
local GetItemId              = GetItemId
local GetNumBagFreeSlots     = GetNumBagFreeSlots
local FindFirstEmptySlotInBag = FindFirstEmptySlotInBag
local ZO_GetNextBagSlotIndex = ZO_GetNextBagSlotIndex

local BAG = BAG_VIRTUAL
local BAG_BACKPACK = BAG_BACKPACK

-- A classic stack is 200 items. Used only for the preset captions ("1 stack" =
-- 200) and the queue's conservative slots-needed estimate; the move engine does
-- NOT chunk by this -- one RequestMoveItem moves the full quantity and the game
-- spreads any overflow across slots itself. Mirrors Valuation.lua's STACK_SIZE.
local STACK_SIZE = 200

-- Quantity presets offered as buttons. Raw item counts, ascending; the captions
-- for the >= one-stack entries are derived ("1 stack", "10 stacks", ...) so the
-- list is the single source of truth -- add a preset by adding a number.
local PRESETS = { 1, 10, 100, 200, 400, 2000, 4000 }

-- Default withdraw quantity proposed when a material is first opened or queued,
-- keyed by item quality (the same colour the game tints the name with). The idea:
-- cheap bulk mats default to a big grab, valuable mats to a small one, so a
-- careless click cannot dump a whole stack of something precious. The user can
-- always raise it (up to the available max) or type an exact value.
--
-- Keyed by ITEM_FUNCTIONAL_QUALITY_* (what Valuation passes as `quality`, from
-- GetItemLinkFunctionalQuality). All tiers start at 10 -- tune per tier here; a
-- common setup is e.g. trash/normal = 200, magic = 100, arcane+ = 10. Resolved
-- through DefaultQuantityForQuality so an unknown/nil quality is safe.
local DEFAULT_QUANTITY_FALLBACK = 1
local DEFAULT_QUANTITY_BY_QUALITY = {
    [ITEM_FUNCTIONAL_QUALITY_TRASH]     = 200, -- grey
    [ITEM_FUNCTIONAL_QUALITY_NORMAL]    = 200, -- white
    [ITEM_FUNCTIONAL_QUALITY_MAGIC]     = 200, -- green
    [ITEM_FUNCTIONAL_QUALITY_ARCANE]    = 200, -- blue
    [ITEM_FUNCTIONAL_QUALITY_ARTIFACT]  = 200, -- purple
    [ITEM_FUNCTIONAL_QUALITY_LEGENDARY] = 1, -- gold
}

local function DefaultQuantityForQuality(quality)
    if quality == nil then
        return DEFAULT_QUANTITY_FALLBACK
    end
    return DEFAULT_QUANTITY_BY_QUALITY[quality] or DEFAULT_QUANTITY_FALLBACK
end

-- Palette (shared house style; see private.COLOR_* in BureauOfMaterialWorth.lua)
local COLOR_ACCENT = private.COLOR_ACCENT
local COLOR_MUTED  = private.COLOR_MUTED
local COLOR_WARN   = private.COLOR_WARN

local Colorize = private.Colorize
local FormatGold = private.FormatGold

local LogDebug = private.LogDebug

-- Layout
-- ---------------------------------------------------------------------------
local POPUP_WIDTH   = 520
local QUEUE_WIDTH   = 520
local PADDING       = 16
local TITLE_HEIGHT  = 30
local LINE          = 24       -- vertical rhythm for info lines
local SECTION_GAP   = 12       -- space between blocks
local BUTTON_HEIGHT = 30
local PROGRESS_HEIGHT = 16
local BG_ALPHA      = 0.94
local QUEUE_ROW_HEIGHT = 30
local QUEUE_MAX_ROWS   = 10

-- Caption for a preset button: a plain number under one stack, otherwise an
-- "N stack(s)" label so 200 reads as "1 stack" and 4000 as "20 stacks".
local function PresetCaption(count)
    if count < STACK_SIZE then
        return ZO_LocalizeDecimalNumber(count)
    end
    local stacks = mathfloor(count / STACK_SIZE)
    local key = stacks == 1 and SI_BMW_WITHDRAW_PRESET_STACK or SI_BMW_WITHDRAW_PRESET_STACKS
    return stringformat(GetString(key), stacks)
end

-- A free backpack slot not already reserved by this run, or nil when none is
-- left. Because a multi-item queue issues all its moves in one synchronous click
-- (before any of them have actually filled their slot), FindFirstEmptySlotInBag
-- would hand back the SAME first empty slot to every move and they would all
-- collide -- only the first lands. So each job claims a distinct slot here and
-- records it in `reserved`, mirroring CraftBagExtended's EmptySlotTracker. The
-- game still distributes a single move's overflow (>200) across further slots on
-- its own; we only need to hand each job its own starting slot.
local function FindFreeBackpackSlot(reserved)
    local slotIndex = FindFirstEmptySlotInBag(BAG_BACKPACK)
    while slotIndex do
        if not reserved[slotIndex] then
            return slotIndex
        end
        slotIndex = ZO_GetNextBagSlotIndex(BAG_BACKPACK, slotIndex)
        -- Skip ahead to the next genuinely empty slot.
        while slotIndex and GetSlotStackSize(BAG_BACKPACK, slotIndex) ~= 0 do
            slotIndex = ZO_GetNextBagSlotIndex(BAG_BACKPACK, slotIndex)
        end
    end
    return nil
end

-- Shared withdrawal engine
-- ---------------------------------------------------------------------------
-- Both the single-material popup and the multi-material queue withdraw through
-- ONE engine. A run is a list of jobs:
--   jobs[i] = { itemId, slotIndex, qty }
-- The single popup builds a one-job list; the queue builds an N-job list.
--
-- IMPORTANT - why this is NOT a timer loop:
-- RequestMoveItem is a PROTECTED function. It must be called via
-- CallSecureProtected AND from a hardware-event callstack (a button click) -- it
-- does NOT work from a RegisterForUpdate timer or an event handler (their
-- callstacks are untrusted). So every move is issued synchronously, inside the
-- click handler that calls StartRun. One call per job moves that job's full
-- quantity; the engine spreads any overflow beyond 200 across backpack slots
-- itself, so there is no per-stack loop.
--
-- The arrival of the moved items is asynchronous, so the (honest) progress bar
-- is advanced by listening to EVENT_INVENTORY_SINGLE_SLOT_UPDATE on the backpack
-- (stack-count increases) until the requested total has landed, then the run
-- finishes. The listener is the only thing that outlives the click, and it is
-- self-cleaning: FinishRun unregisters it, as do Cancel / OnCraftBagHidden.
local MOVE_EVENT_NAME = addon.name .. "_WithdrawMoveWatch"
-- Safety timeout: if the expected items never fully arrive (e.g. a move was
-- partially rejected), end the run anyway so the UI never stays "in progress"
-- forever. Re-armed on every arrival; fires when arrivals go quiet.
local WATCH_TIMEOUT_MS = 2000
local WATCH_TIMER_NAME = addon.name .. "_WithdrawWatchTimeout"

local isWithdrawing = false
local engineMoved = 0           -- items confirmed arrived in the backpack
local engineTotal = 0           -- items the run set out to move
local engineWatchItemIds = nil  -- [itemId] = true for items this run is moving
local engineOnProgress = nil    -- callback(moved, total)
local engineOnFinish = nil      -- callback() when the run ends

-- Call the protected RequestMoveItem safely. Guarded so a client where it is NOT
-- protected still works. Never bind RequestMoveItem to an upvalue -- merely
-- referencing the global at load throws "access a private function".
local function SecureRequestMoveItem(srcBag, srcSlot, destBag, destSlot, quantity)
    if IsProtectedFunction("RequestMoveItem") then
        CallSecureProtected("RequestMoveItem", srcBag, srcSlot, destBag, destSlot, quantity)
    else
        RequestMoveItem(srcBag, srcSlot, destBag, destSlot, quantity)
    end
end

local function StopWatching()
    EVENT_MANAGER:UnregisterForUpdate(WATCH_TIMER_NAME)
    EVENT_MANAGER:UnregisterForEvent(MOVE_EVENT_NAME, EVENT_INVENTORY_SINGLE_SLOT_UPDATE)
end

local function FinishRun()
    StopWatching()
    isWithdrawing = false
    engineWatchItemIds = nil
    local onFinish = engineOnFinish
    engineOnProgress = nil
    engineOnFinish = nil
    if onFinish then
        onFinish()
    end
end

-- Backpack slot-update handler: count stack-count increases for the items this
-- run is moving, advance the progress bar, and finish once the total has landed.
local function OnBackpackSlotUpdate(eventCode, bagId, slotIndex, isNewItem, soundCat, updateReason, stackCountChange)
    if bagId ~= BAG_BACKPACK or not stackCountChange or stackCountChange <= 0 then
        return
    end
    if not engineWatchItemIds then
        return
    end
    local itemId = GetItemId(BAG_BACKPACK, slotIndex)
    if not engineWatchItemIds[itemId] then
        return
    end

    engineMoved = engineMoved + stackCountChange
    if engineOnProgress then
        engineOnProgress(mathmin(engineMoved, engineTotal), engineTotal)
    end

    if engineMoved >= engineTotal then
        FinishRun()
        return
    end

    -- Re-arm the quiet-timeout so a stalled move still ends the run.
    EVENT_MANAGER:UnregisterForUpdate(WATCH_TIMER_NAME)
    EVENT_MANAGER:RegisterForUpdate(WATCH_TIMER_NAME, WATCH_TIMEOUT_MS, FinishRun)
end

-- Begin a run. jobs is a list of { itemId, slotIndex, qty }; totalQty is the sum
-- (for the progress bar). MUST be called synchronously from a click handler so
-- the protected RequestMoveItem calls run in a trusted callstack.
-- onProgress(moved,total) and onFinish() drive the UI.
local function StartRun(jobs, totalQty, onProgress, onFinish)
    if isWithdrawing or totalQty <= 0 then
        return false
    end

    engineMoved = 0
    engineTotal = totalQty
    engineOnProgress = onProgress
    engineOnFinish = onFinish
    engineWatchItemIds = {}
    isWithdrawing = true

    if onProgress then
        onProgress(0, totalQty)
    end

    -- Watch backpack arrivals BEFORE issuing the moves, so we never miss an early
    -- slot event. Filtered to the backpack so craft-bag churn is ignored.
    EVENT_MANAGER:RegisterForEvent(MOVE_EVENT_NAME, EVENT_INVENTORY_SINGLE_SLOT_UPDATE, OnBackpackSlotUpdate)
    EVENT_MANAGER:AddFilterForEvent(MOVE_EVENT_NAME, EVENT_INVENTORY_SINGLE_SLOT_UPDATE,
        REGISTER_FILTER_BAG_ID, BAG_BACKPACK)
    EVENT_MANAGER:RegisterForUpdate(WATCH_TIMER_NAME, WATCH_TIMEOUT_MS, FinishRun)

    -- Issue one protected move per job, synchronously, in this (trusted) click
    -- callstack. Each job claims a distinct free backpack slot (tracked in
    -- `reserved`) so the moves do not all target the same slot and collide -- the
    -- slots have not actually filled yet at this point in the frame.
    local reserved = {}
    local issued = 0
    for i = 1, #jobs do
        local job = jobs[i]
        local srcStack = GetSlotStackSize(BAG, job.slotIndex) or 0
        local moveQty = mathmin(job.qty, srcStack)
        local destSlot = FindFreeBackpackSlot(reserved)
        if moveQty > 0 and destSlot then
            reserved[destSlot] = true
            engineWatchItemIds[job.itemId] = true
            issued = issued + moveQty
            SecureRequestMoveItem(BAG, job.slotIndex, BAG_BACKPACK, destSlot, moveQty)
            if LogDebug then
                LogDebug(SI_BMW_LOG_SLOT_UPDATED, destSlot, ZO_LocalizeDecimalNumber(moveQty))
            end
        end
    end

    -- Nothing actually went out (no free slot / empty source): end immediately so
    -- the UI does not hang waiting for arrivals that will never come.
    if issued <= 0 then
        FinishRun()
        return false
    end

    return true
end

-- ===========================================================================
-- Part A: single-material withdraw popup
-- ===========================================================================
local popup           -- top-level window
local popupTitle, popupIcon
local popupFreeLabel, popupMaxLabel, popupValueLabel
local popupEdit
local popupPresetButtons = {}
local popupConfirm, popupCancel
local popupProgressBar, popupProgressLabel

-- Current material under the popup. The itemId/slot/price/priced fields are read
-- across the popup's lifetime (ComputeMax, RenderPopup, Confirm), so they persist
-- at module scope; the name/icon/quality are only needed to paint the title on
-- open, so they live as locals inside Open rather than lingering here.
local curItemId, curSlotIndex, curUnitPrice, curPriced
local curRequested = 0
local curMax = 0
local suppressEditEvent = false  -- guards the editbox sanitizer against its own SetText

local function ComputeMax()
    local srcStack = GetSlotStackSize(BAG, curSlotIndex) or 0
    local backpackCap = addon.Valuation and addon.Valuation.GetBackpackCapacityFor(curItemId) or 0
    curMax = mathmax(0, mathmin(srcStack, backpackCap))
    return curMax
end

local function RenderPopup()
    popupFreeLabel:SetText(Colorize(COLOR_MUTED,
        stringformat(GetString(SI_BMW_WITHDRAW_FREE_SLOTS), GetNumBagFreeSlots(BAG_BACKPACK))))

    if curMax <= 0 then
        popupMaxLabel:SetText(Colorize(COLOR_WARN, GetString(SI_BMW_WITHDRAW_BACKPACK_FULL)))
    else
        popupMaxLabel:SetText(Colorize(COLOR_MUTED,
            stringformat(GetString(SI_BMW_WITHDRAW_MAX), ZO_LocalizeDecimalNumber(curMax))))
    end

    -- Total value of the working quantity, or a muted dash when unpriced.
    local valueText
    if curPriced and curUnitPrice and curUnitPrice > 0 then
        valueText = FormatGold(curUnitPrice * curRequested)
    else
        valueText = Colorize(COLOR_MUTED, GetString(SI_BMW_DETAIL_GROWTH_NEW))
    end
    popupValueLabel:SetText(Colorize(COLOR_MUTED,
        stringformat(GetString(SI_BMW_WITHDRAW_TOTAL_VALUE), valueText)))

    -- Confirm is only usable when there is something to move.
    local canWithdraw = not isWithdrawing and curRequested > 0 and curRequested <= curMax
    popupConfirm:SetEnabled(canWithdraw)
end

local function SetRequested(qty)
    qty = tonumber(qty) or 0
    qty = mathmax(0, mathmin(qty, curMax))
    curRequested = qty

    -- Reflect the clamped value back into the editbox without re-triggering the
    -- sanitizer (SetText fires OnTextChanged).
    suppressEditEvent = true
    popupEdit:SetText(qty > 0 and tostring(qty) or "")
    suppressEditEvent = false

    RenderPopup()
end

local function OnPopupFinish()
    -- The run ended (completed, backpack full, or cancelled). Recompute the cap
    -- against the now-smaller craft-bag stack and re-enable the controls.
    popupProgressBar:SetHidden(true)
    popupProgressLabel:SetHidden(true)
    for i = 1, #popupPresetButtons do
        popupPresetButtons[i]:SetEnabled(true)
    end
    popupEdit:SetEditEnabled(true)
    popupCancel:SetEnabled(true)

    ComputeMax()
    SetRequested(mathmin(curRequested, curMax))
end

local function OnPopupProgress(moved, total)
    popupProgressBar:SetValue(total > 0 and moved / total or 0)
    popupProgressLabel:SetText(Colorize(COLOR_MUTED,
        stringformat(GetString(SI_BMW_WITHDRAW_PROGRESS), moved, total)))
end

function WithdrawDialog.Confirm()
    if isWithdrawing then
        return
    end
    ComputeMax()
    local qty = mathmin(curRequested, curMax)
    if qty <= 0 then
        RenderPopup()
        return
    end

    -- Lock the inputs for the duration of the run.
    for i = 1, #popupPresetButtons do
        popupPresetButtons[i]:SetEnabled(false)
    end
    popupEdit:SetEditEnabled(false)
    popupConfirm:SetEnabled(false)
    popupProgressBar:SetHidden(false)
    popupProgressBar:SetValue(0)
    popupProgressLabel:SetHidden(false)

    StartRun({ { itemId = curItemId, slotIndex = curSlotIndex, qty = qty } }, qty,
        OnPopupProgress, OnPopupFinish)
end

local function HidePopup()
    if popup then
        popup:SetHidden(true)
    end
end

function WithdrawDialog.CancelPopup()
    if isWithdrawing then
        FinishRun()
    end
    HidePopup()
end

-- Build the singleton popup once. Frame is code-built like the other windows.
local function InitializePopup()
    popup = WINDOW_MANAGER:CreateTopLevelWindow(addon.name .. "_WithdrawPopup")
    popup:SetClampedToScreen(true)
    popup:SetDimensions(POPUP_WIDTH, 260)
    popup:SetHidden(true)
    popup:SetMouseEnabled(true)
    popup:SetMovable(true)
    popup:SetDrawLayer(DL_OVERLAY)
    popup:SetDrawTier(DT_HIGH)

    local backdrop = WINDOW_MANAGER:CreateControl(addon.name .. "_WithdrawBackdrop", popup, CT_BACKDROP)
    backdrop:SetAnchorFill(popup)
    backdrop:SetEdgeTexture("", 1, 1, 1)
    backdrop:SetInsets(2, 2, -2, -2)
    backdrop:SetCenterColor(0.05, 0.05, 0.06, BG_ALPHA)
    backdrop:SetEdgeColor(0.42, 0.40, 0.34, 0.9)

    popupIcon = WINDOW_MANAGER:CreateControl(addon.name .. "_WithdrawIcon", popup, CT_TEXTURE)
    popupIcon:SetDimensions(32, 32)
    popupIcon:SetAnchor(TOPLEFT, popup, TOPLEFT, PADDING, PADDING)

    popupTitle = WINDOW_MANAGER:CreateControl(addon.name .. "_WithdrawTitle", popup, CT_LABEL)
    popupTitle:SetFont("ZoFontWinH4")
    popupTitle:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
    popupTitle:SetVerticalAlignment(TEXT_ALIGN_CENTER)
    popupTitle:SetMaxLineCount(1)
    popupTitle:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
    popupTitle:SetAnchor(LEFT, popupIcon, RIGHT, 10, 0)
    -- Leave room on the right for the close button (icon + title + close).
    popupTitle:SetWidth(POPUP_WIDTH - PADDING * 2 - 32 - 10 - 30)

    local closeButton = WINDOW_MANAGER:CreateControlFromVirtual(
        addon.name .. "_WithdrawClose", popup, "ZO_CloseButton")
    closeButton:SetAnchor(TOPRIGHT, popup, TOPRIGHT, -PADDING, PADDING)
    closeButton:SetHandler("OnClicked", function() WithdrawDialog.CancelPopup() end)

    local innerWidth = POPUP_WIDTH - PADDING * 2
    local y = PADDING + TITLE_HEIGHT + SECTION_GAP

    popupFreeLabel = WINDOW_MANAGER:CreateControl(addon.name .. "_WithdrawFree", popup, CT_LABEL)
    popupFreeLabel:SetFont("ZoFontGame")
    popupFreeLabel:SetWidth(innerWidth)
    popupFreeLabel:SetAnchor(TOPLEFT, popup, TOPLEFT, PADDING, y)
    y = y + LINE

    popupMaxLabel = WINDOW_MANAGER:CreateControl(addon.name .. "_WithdrawMax", popup, CT_LABEL)
    popupMaxLabel:SetFont("ZoFontGame")
    popupMaxLabel:SetWidth(innerWidth)
    popupMaxLabel:SetAnchor(TOPLEFT, popup, TOPLEFT, PADDING, y)
    y = y + LINE

    popupValueLabel = WINDOW_MANAGER:CreateControl(addon.name .. "_WithdrawValue", popup, CT_LABEL)
    popupValueLabel:SetFont("ZoFontGame")
    popupValueLabel:SetWidth(innerWidth)
    popupValueLabel:SetAnchor(TOPLEFT, popup, TOPLEFT, PADDING, y)
    y = y + LINE + SECTION_GAP

    -- Preset buttons, wrapped across rows so they fit the popup width. The button
    -- width is derived from how many fit per row so they span the full width
    -- evenly with no overflow.
    local btnGap = 8
    local presetsPerRow = 4
    local btnWidth = mathfloor((innerWidth - btnGap * (presetsPerRow - 1)) / presetsPerRow)
    for i = 1, #PRESETS do
        local count = PRESETS[i]
        local button = WINDOW_MANAGER:CreateControlFromVirtual(
            addon.name .. "_WithdrawPreset" .. i, popup, "ZO_DefaultButton")
        button:SetDimensions(btnWidth, BUTTON_HEIGHT)
        button:SetText(PresetCaption(count))
        local col = (i - 1) % presetsPerRow
        local rowN = mathfloor((i - 1) / presetsPerRow)
        button:SetAnchor(TOPLEFT, popup, TOPLEFT,
            PADDING + col * (btnWidth + btnGap), y + rowN * (BUTTON_HEIGHT + btnGap))
        button:SetHandler("OnClicked", function() SetRequested(count) end)
        popupPresetButtons[i] = button
    end
    local presetRows = mathfloor((#PRESETS - 1) / presetsPerRow) + 1
    y = y + presetRows * (BUTTON_HEIGHT + btnGap) + SECTION_GAP

    -- Quantity row: label on the left, editbox to its right.
    local qtyLabel = WINDOW_MANAGER:CreateControl(addon.name .. "_WithdrawQtyLabel", popup, CT_LABEL)
    qtyLabel:SetFont("ZoFontGame")
    qtyLabel:SetVerticalAlignment(TEXT_ALIGN_CENTER)
    qtyLabel:SetDimensions(120, BUTTON_HEIGHT)
    qtyLabel:SetAnchor(TOPLEFT, popup, TOPLEFT, PADDING, y)
    qtyLabel:SetText(Colorize(COLOR_MUTED, GetString(SI_BMW_WITHDRAW_QTY_LABEL)))

    local editBg = WINDOW_MANAGER:CreateControlFromVirtual(
        addon.name .. "_WithdrawEditBg", popup, "ZO_DefaultBackdrop")
    editBg:SetDimensions(140, BUTTON_HEIGHT)
    -- ZO_DefaultBackdrop ships with its own anchors; clear them before ours so
    -- this does not become a rejected third anchor.
    editBg:ClearAnchors()
    editBg:SetAnchor(LEFT, qtyLabel, RIGHT, 8, 0)
    -- Clicking anywhere on the backdrop (incl. its padding) focuses the editbox,
    -- so the whole field is the hit target, not just the glyphs. Without this the
    -- box reads as "locked" because a custom (non-dialog) editbox does not grab
    -- focus on click on its own. Mirrors the detail window's search field.
    editBg:SetMouseEnabled(true)
    editBg:SetHandler("OnMouseUp", function()
        if popupEdit then
            popupEdit:TakeFocus()
        end
    end)

    popupEdit = WINDOW_MANAGER:CreateControl(addon.name .. "_WithdrawEdit", editBg, CT_EDITBOX)
    popupEdit:SetAnchor(TOPLEFT, editBg, TOPLEFT, 8, 2)
    popupEdit:SetAnchor(BOTTOMRIGHT, editBg, BOTTOMRIGHT, -8, -2)
    popupEdit:SetFont("ZoFontGame")
    popupEdit:SetMaxInputChars(7)
    popupEdit:SetMouseEnabled(true)
    popupEdit:SetTextType(TEXT_TYPE_NUMERIC)
    -- Take focus on click so typing an exact amount (e.g. 17) works; some custom
    -- editboxes do not auto-focus reliably.
    popupEdit:SetHandler("OnMouseUp", function(self)
        self:TakeFocus()
    end)
    popupEdit:SetHandler("OnTextChanged", function()
        if suppressEditEvent then
            return
        end
        SetRequested(popupEdit:GetText())
    end)
    -- Enter commits the withdrawal, so typing an exact amount and pressing Enter
    -- works without reaching for the Confirm button.
    popupEdit:SetHandler("OnEnter", function(self)
        self:LoseFocus()
        WithdrawDialog.Confirm()
    end)
    y = y + BUTTON_HEIGHT + SECTION_GAP

    -- Progress block: bar + centered label. Reserves its own vertical space ABOVE
    -- the action buttons so the two never overlap while a run is in progress.
    popupProgressBar = WINDOW_MANAGER:CreateControl(addon.name .. "_WithdrawProgress", popup, CT_STATUSBAR)
    popupProgressBar:SetDimensions(innerWidth, PROGRESS_HEIGHT)
    popupProgressBar:SetAnchor(TOPLEFT, popup, TOPLEFT, PADDING, y)
    popupProgressBar:SetMinMax(0, 1)
    popupProgressBar:SetValue(0)
    popupProgressBar:SetColor(0.44, 0.80, 0.62, 1)
    popupProgressBar:SetHidden(true)

    popupProgressLabel = WINDOW_MANAGER:CreateControl(addon.name .. "_WithdrawProgressText", popup, CT_LABEL)
    popupProgressLabel:SetFont("ZoFontGameSmall")
    popupProgressLabel:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
    popupProgressLabel:SetVerticalAlignment(TEXT_ALIGN_CENTER)
    popupProgressLabel:SetDimensions(innerWidth, PROGRESS_HEIGHT)
    popupProgressLabel:SetAnchor(TOPLEFT, popup, TOPLEFT, PADDING, y)
    popupProgressLabel:SetHidden(true)
    y = y + PROGRESS_HEIGHT + SECTION_GAP

    -- Confirm + Cancel at the bottom corners.
    popupConfirm = WINDOW_MANAGER:CreateControlFromVirtual(
        addon.name .. "_WithdrawConfirm", popup, "ZO_DefaultButton")
    popupConfirm:SetDimensions(140, BUTTON_HEIGHT)
    popupConfirm:SetAnchor(TOPLEFT, popup, TOPLEFT, PADDING, y)
    popupConfirm:SetText(GetString(SI_BMW_WITHDRAW_CONFIRM))
    popupConfirm:SetHandler("OnClicked", function() WithdrawDialog.Confirm() end)

    popupCancel = WINDOW_MANAGER:CreateControlFromVirtual(
        addon.name .. "_WithdrawCancelBtn", popup, "ZO_DefaultButton")
    popupCancel:SetDimensions(140, BUTTON_HEIGHT)
    popupCancel:SetAnchor(TOPRIGHT, popup, TOPRIGHT, -PADDING, y)
    popupCancel:SetText(GetString(SI_BMW_WITHDRAW_CANCEL))
    popupCancel:SetHandler("OnClicked", function() WithdrawDialog.CancelPopup() end)

    popup:SetHeight(y + BUTTON_HEIGHT + PADDING)
end

-- Open the popup for a material row (the record from GetCategoryMaterials, now
-- carrying slotIndex). Anchors over the detail window so windows don't scatter.
function WithdrawDialog.Open(materialData)
    if not popup or not materialData then
        return
    end
    if isWithdrawing then
        return  -- don't swap material mid-run
    end

    curItemId = materialData.itemId
    curSlotIndex = materialData.slotIndex
    curUnitPrice = materialData.unitPrice
    curPriced = materialData.priced
    -- Name/icon/quality are only used to paint the title and seed the default
    -- quantity here, so they stay local to this call rather than at module scope.
    local curName = materialData.name
    local curIcon = materialData.icon
    local curQuality = materialData.quality

    popupIcon:SetTexture(curIcon)
    popupTitle:SetText(Colorize(COLOR_ACCENT, stringformat(GetString(SI_BMW_WITHDRAW_TITLE),
        addon.Valuation.ColorizeMaterialName(curName, curQuality))))

    popupProgressBar:SetHidden(true)
    popupProgressLabel:SetHidden(true)

    ComputeMax()
    SetRequested(mathmin(DefaultQuantityForQuality(curQuality), curMax))

    -- Sit the popup just ABOVE the detail window (left edges aligned) so it reads
    -- as belonging to it and never covers the material list. Falls back to
    -- screen-center when the detail window is somehow unavailable.
    popup:ClearAnchors()
    local detailControl = addon.DetailWindow and addon.DetailWindow.GetWindowControl()
    if detailControl then
        popup:SetAnchor(BOTTOMLEFT, detailControl, TOPLEFT, 0, -8)
    else
        popup:SetAnchor(CENTER, GuiRoot, CENTER, 0, 0)
    end

    popup:SetHidden(false)
    popup:BringWindowToTop()
end

-- ===========================================================================
-- Part B: multi-material withdraw queue
-- ===========================================================================
local queueWindow
local queueList
local queueEmptyLabel
local queueSlotsLabel, queueTotalLabel
local queueWithdrawAll, queueClear
local queueProgressBar
local QUEUE_ROW_TYPE = 1

-- Queue entries: ordered list plus an itemId index so a repeat right-click
-- updates the existing entry instead of duplicating it.
local queue = {}            -- array of { itemId, slotIndex, name, icon, quality, unitPrice, priced, qty }
local queueByItemId = {}    -- [itemId] = entry

-- Total backpack slots a quantity needs, derived the same way withdrawals fill:
-- ceil(qty / 200). This is an upper bound (it ignores partial-stack top-ups), so
-- the "needs N / free M" readout is conservative -- it never claims something
-- fits when it might not.
local function SlotsForQuantity(qty)
    if not qty or qty <= 0 then
        return 0
    end
    return mathfloor((qty + STACK_SIZE - 1) / STACK_SIZE)
end

local function RenderQueueFooter()
    local neededSlots, totalValue = 0, 0
    for i = 1, #queue do
        local e = queue[i]
        neededSlots = neededSlots + SlotsForQuantity(e.qty)
        if e.priced and e.unitPrice then
            totalValue = totalValue + e.unitPrice * e.qty
        end
    end

    local free = GetNumBagFreeSlots(BAG_BACKPACK)
    local color = neededSlots > free and COLOR_WARN or COLOR_MUTED
    queueSlotsLabel:SetText(Colorize(color,
        stringformat(GetString(SI_BMW_QUEUE_SLOTS), neededSlots, free)))
    queueTotalLabel:SetText(Colorize(COLOR_MUTED,
        stringformat(GetString(SI_BMW_QUEUE_TOTAL), FormatGold(totalValue))))

    queueWithdrawAll:SetEnabled(not isWithdrawing and #queue > 0)
    queueClear:SetEnabled(not isWithdrawing and #queue > 0)
end

local function PopulateQueueList()
    local dataList = ZO_ScrollList_GetDataList(queueList)
    ZO_ScrollList_Clear(queueList)
    for i = 1, #queue do
        dataList[#dataList + 1] = ZO_ScrollList_CreateDataEntry(QUEUE_ROW_TYPE, queue[i])
    end
    ZO_ScrollList_Commit(queueList)
    queueEmptyLabel:SetHidden(#queue > 0)
end

local function RefreshQueue()
    PopulateQueueList()
    RenderQueueFooter()
end

local function ShowQueueWindow()
    if not queueWindow then
        return
    end
    -- Drop the queue just BELOW the detail window (left edges aligned) so we do
    -- not scatter floating windows; ESO drags the anchored window along with its
    -- relativeTo. The popup sits above the detail window, the queue below it.
    queueWindow:ClearAnchors()
    local detailControl = addon.DetailWindow and addon.DetailWindow.GetWindowControl()
    if detailControl then
        queueWindow:SetAnchor(TOPLEFT, detailControl, BOTTOMLEFT, 0, 8)
    else
        queueWindow:SetAnchor(CENTER, GuiRoot, CENTER, 0, 0)
    end
    queueWindow:SetHidden(false)
end

local function HideQueueWindow()
    if queueWindow then
        queueWindow:SetHidden(true)
    end
end

function WithdrawDialog.AddToQueue(materialData)
    if not materialData or not materialData.itemId then
        return
    end

    local entry = queueByItemId[materialData.itemId]
    if entry then
        -- Already queued: just refresh its source slot, keep the user's quantity.
        entry.slotIndex = materialData.slotIndex
    else
        local srcStack = GetSlotStackSize(BAG, materialData.slotIndex) or 0
        entry = {
            itemId = materialData.itemId,
            slotIndex = materialData.slotIndex,
            name = materialData.name,
            icon = materialData.icon,
            quality = materialData.quality,
            unitPrice = materialData.unitPrice,
            priced = materialData.priced,
            -- Default by quality (cheap bulk mats grab more, valuable mats less),
            -- clamped to what's actually held; the user raises it in the qty box.
            qty = mathmin(DefaultQuantityForQuality(materialData.quality), srcStack),
        }
        queue[#queue + 1] = entry
        queueByItemId[materialData.itemId] = entry
    end

    ShowQueueWindow()
    RefreshQueue()
end

function WithdrawDialog.RemoveFromQueue(itemId)
    if not queueByItemId[itemId] then
        return
    end
    queueByItemId[itemId] = nil
    for i = 1, #queue do
        if queue[i].itemId == itemId then
            table.remove(queue, i)
            break
        end
    end
    RefreshQueue()
    if #queue == 0 then
        HideQueueWindow()
    end
end

function WithdrawDialog.ClearQueue()
    if isWithdrawing then
        return
    end
    queue = {}
    queueByItemId = {}
    RefreshQueue()
    HideQueueWindow()
end

local function OnQueueProgress(moved, total)
    queueProgressBar:SetValue(total > 0 and moved / total or 0)
end

local function OnQueueFinish()
    queueProgressBar:SetHidden(true)
    -- Drop fully-withdrawn entries (source slot now empty); keep partials.
    for i = #queue, 1, -1 do
        local e = queue[i]
        local remainingStack = GetSlotStackSize(BAG, e.slotIndex) or 0
        if remainingStack <= 0 then
            queueByItemId[e.itemId] = nil
            table.remove(queue, i)
        else
            e.qty = mathmin(e.qty, remainingStack)
        end
    end
    RefreshQueue()
    if #queue == 0 then
        HideQueueWindow()
    end
end

function WithdrawDialog.WithdrawAll()
    if isWithdrawing or #queue == 0 then
        return
    end

    local jobs, total = {}, 0
    for i = 1, #queue do
        local e = queue[i]
        local srcStack = GetSlotStackSize(BAG, e.slotIndex) or 0
        local qty = mathmin(e.qty, srcStack)
        if qty > 0 then
            jobs[#jobs + 1] = { itemId = e.itemId, slotIndex = e.slotIndex, qty = qty }
            total = total + qty
        end
    end
    if total <= 0 then
        return
    end

    queueProgressBar:SetHidden(false)
    queueProgressBar:SetValue(0)
    queueWithdrawAll:SetEnabled(false)
    queueClear:SetEnabled(false)
    StartRun(jobs, total, OnQueueProgress, OnQueueFinish)
end

-- One queue row: icon, name, editable qty, value, remove button. Handlers are
-- bound once per recycled control (sentinel) and always read the row's CURRENT
-- data, since ZO_ScrollList reuses a small pool of rows across many entries.
local function SetupQueueRow(rowControl, data)
    rowControl.bmwQueueData = data

    rowControl:GetNamedChild("Icon"):SetTexture(data.icon)

    local nameLabel = rowControl:GetNamedChild("Name")
    nameLabel:SetMaxLineCount(1)
    nameLabel:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
    nameLabel:SetText(addon.Valuation.ColorizeMaterialName(data.name, data.quality))

    local valueLabel = rowControl:GetNamedChild("Value")
    if data.priced and data.unitPrice then
        valueLabel:SetText(FormatGold(data.unitPrice * data.qty))
    else
        valueLabel:SetText(Colorize(COLOR_MUTED, GetString(SI_BMW_DETAIL_GROWTH_NEW)))
    end

    -- The qty editbox is nested inside the QtyBg backdrop (see DetailWindow.xml),
    -- so its name suffix is "QtyBgEdit", not "Qty".
    local edit = rowControl:GetNamedChild("QtyBgEdit")
    rowControl.bmwSuppressEdit = true
    edit:SetText(tostring(data.qty or 0))
    rowControl.bmwSuppressEdit = false

    if not rowControl.bmwBound then
        rowControl.bmwBound = true

        edit:SetHandler("OnTextChanged", function(self)
            if rowControl.bmwSuppressEdit then
                return
            end
            local d = rowControl.bmwQueueData
            if not d then
                return
            end
            local srcStack = GetSlotStackSize(BAG, d.slotIndex) or 0
            local qty = mathmax(0, mathmin(tonumber(self:GetText()) or 0, srcStack))
            d.qty = qty

            -- Reflect the clamped value back into the box so what is shown always
            -- matches what will be withdrawn (and what the slots-needed figure is
            -- based on). Without this, typing more than the craft bag holds leaves
            -- a misleading larger number in the field while the slot count tracks
            -- the real, clamped quantity. Guarded so this SetText does not recurse.
            if tostring(qty) ~= (self:GetText() or "") then
                rowControl.bmwSuppressEdit = true
                self:SetText(tostring(qty))
                rowControl.bmwSuppressEdit = false
            end

            -- Update just this row's value + the footer; avoid a full rebuild so
            -- the editbox keeps focus while typing.
            if d.priced and d.unitPrice then
                valueLabel:SetText(FormatGold(d.unitPrice * qty))
            end
            RenderQueueFooter()
        end)

        local removeButton = rowControl:GetNamedChild("Remove")
        removeButton:SetHandler("OnClicked", function()
            local d = rowControl.bmwQueueData
            if d then
                WithdrawDialog.RemoveFromQueue(d.itemId)
            end
        end)
    end
end

local function InitializeQueueWindow()
    local innerWidth = QUEUE_WIDTH - PADDING * 2

    queueWindow = WINDOW_MANAGER:CreateTopLevelWindow(addon.name .. "_QueueWindow")
    queueWindow:SetClampedToScreen(true)
    queueWindow:SetDimensions(QUEUE_WIDTH, 360)
    queueWindow:SetHidden(true)
    queueWindow:SetMouseEnabled(true)
    queueWindow:SetMovable(true)

    local backdrop = WINDOW_MANAGER:CreateControl(addon.name .. "_QueueBackdrop", queueWindow, CT_BACKDROP)
    backdrop:SetAnchorFill(queueWindow)
    backdrop:SetEdgeTexture("", 1, 1, 1)
    backdrop:SetInsets(2, 2, -2, -2)
    backdrop:SetCenterColor(0.05, 0.05, 0.06, BG_ALPHA)
    backdrop:SetEdgeColor(0.42, 0.40, 0.34, 0.9)

    local title = WINDOW_MANAGER:CreateControl(addon.name .. "_QueueTitle", queueWindow, CT_LABEL)
    title:SetFont("ZoFontWinH4")
    title:SetVerticalAlignment(TEXT_ALIGN_CENTER)
    title:SetDimensions(innerWidth, TITLE_HEIGHT)
    title:SetAnchor(TOPLEFT, queueWindow, TOPLEFT, PADDING, PADDING)
    title:SetText(Colorize(COLOR_ACCENT, GetString(SI_BMW_QUEUE_TITLE)))

    -- Divider under the title, mirroring the detail window's header rule.
    local divider = WINDOW_MANAGER:CreateControl(addon.name .. "_QueueDivider", queueWindow, CT_TEXTURE)
    divider:SetTexture("EsoUI/Art/Miscellaneous/horizontalDivider.dds")
    divider:SetDimensions(innerWidth, 4)
    divider:SetColor(1, 1, 1, 0.4)
    divider:SetAnchor(TOPLEFT, queueWindow, TOPLEFT, PADDING, PADDING + TITLE_HEIGHT)

    local listY = PADDING + TITLE_HEIGHT + SECTION_GAP
    queueList = WINDOW_MANAGER:CreateControlFromVirtual(
        addon.name .. "_QueueListControl", queueWindow, "BureauOfMaterialWorth_WithdrawQueueList")
    queueList:SetDimensions(innerWidth, QUEUE_ROW_HEIGHT * QUEUE_MAX_ROWS)
    queueList:SetAnchor(TOPLEFT, queueWindow, TOPLEFT, PADDING, listY)
    ZO_ScrollList_Initialize(queueList)
    ZO_ScrollList_AddDataType(queueList, QUEUE_ROW_TYPE,
        "BureauOfMaterialWorth_WithdrawQueueRow", QUEUE_ROW_HEIGHT, SetupQueueRow)

    queueEmptyLabel = WINDOW_MANAGER:CreateControl(addon.name .. "_QueueEmpty", queueWindow, CT_LABEL)
    queueEmptyLabel:SetFont("ZoFontGame")
    queueEmptyLabel:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
    queueEmptyLabel:SetVerticalAlignment(TEXT_ALIGN_CENTER)
    queueEmptyLabel:SetDimensions(innerWidth, QUEUE_ROW_HEIGHT * 2)
    queueEmptyLabel:SetAnchor(TOP, queueList, TOP, 0, QUEUE_ROW_HEIGHT)
    queueEmptyLabel:SetText(Colorize(COLOR_MUTED, GetString(SI_BMW_QUEUE_EMPTY)))

    local footerY = listY + QUEUE_ROW_HEIGHT * QUEUE_MAX_ROWS + SECTION_GAP

    -- Footer divider above the summary, balancing the header rule.
    local footerDivider = WINDOW_MANAGER:CreateControl(addon.name .. "_QueueFooterDivider", queueWindow, CT_TEXTURE)
    footerDivider:SetTexture("EsoUI/Art/Miscellaneous/horizontalDivider.dds")
    footerDivider:SetDimensions(innerWidth, 4)
    footerDivider:SetColor(1, 1, 1, 0.4)
    footerDivider:SetAnchor(TOPLEFT, queueWindow, TOPLEFT, PADDING, footerY)
    footerY = footerY + SECTION_GAP

    queueSlotsLabel = WINDOW_MANAGER:CreateControl(addon.name .. "_QueueSlots", queueWindow, CT_LABEL)
    queueSlotsLabel:SetFont("ZoFontGame")
    queueSlotsLabel:SetVerticalAlignment(TEXT_ALIGN_CENTER)
    queueSlotsLabel:SetDimensions(innerWidth * 0.5, LINE)
    queueSlotsLabel:SetAnchor(TOPLEFT, queueWindow, TOPLEFT, PADDING, footerY)

    queueTotalLabel = WINDOW_MANAGER:CreateControl(addon.name .. "_QueueTotalValue", queueWindow, CT_LABEL)
    queueTotalLabel:SetFont("ZoFontGame")
    queueTotalLabel:SetHorizontalAlignment(TEXT_ALIGN_RIGHT)
    queueTotalLabel:SetVerticalAlignment(TEXT_ALIGN_CENTER)
    queueTotalLabel:SetDimensions(innerWidth * 0.5, LINE)
    queueTotalLabel:SetAnchor(TOPRIGHT, queueWindow, TOPRIGHT, -PADDING, footerY)
    footerY = footerY + LINE + SECTION_GAP

    queueProgressBar = WINDOW_MANAGER:CreateControl(addon.name .. "_QueueProgress", queueWindow, CT_STATUSBAR)
    queueProgressBar:SetDimensions(innerWidth, PROGRESS_HEIGHT)
    queueProgressBar:SetAnchor(TOPLEFT, queueWindow, TOPLEFT, PADDING, footerY)
    queueProgressBar:SetMinMax(0, 1)
    queueProgressBar:SetValue(0)
    queueProgressBar:SetColor(0.44, 0.80, 0.62, 1)
    queueProgressBar:SetHidden(true)
    footerY = footerY + PROGRESS_HEIGHT + SECTION_GAP

    queueWithdrawAll = WINDOW_MANAGER:CreateControlFromVirtual(
        addon.name .. "_QueueWithdrawAll", queueWindow, "ZO_DefaultButton")
    queueWithdrawAll:SetDimensions(180, BUTTON_HEIGHT)
    queueWithdrawAll:SetAnchor(TOPLEFT, queueWindow, TOPLEFT, PADDING, footerY)
    queueWithdrawAll:SetText(GetString(SI_BMW_QUEUE_WITHDRAW_ALL))
    queueWithdrawAll:SetHandler("OnClicked", function() WithdrawDialog.WithdrawAll() end)

    queueClear = WINDOW_MANAGER:CreateControlFromVirtual(
        addon.name .. "_QueueClear", queueWindow, "ZO_DefaultButton")
    queueClear:SetDimensions(140, BUTTON_HEIGHT)
    queueClear:SetAnchor(TOPRIGHT, queueWindow, TOPRIGHT, -PADDING, footerY)
    queueClear:SetText(GetString(SI_BMW_QUEUE_CLEAR))
    queueClear:SetHandler("OnClicked", function() WithdrawDialog.ClearQueue() end)

    queueWindow:SetHeight(footerY + BUTTON_HEIGHT + PADDING)

    RefreshQueue()
end

-- ===========================================================================
-- Public lifecycle
-- ===========================================================================
function WithdrawDialog.Initialize()
    if popup then
        return
    end
    InitializePopup()
    InitializeQueueWindow()
end

-- Refresh the open queue list against current stock; called from the detail
-- refresh path so the queue's values track withdrawals/deposits while open.
function WithdrawDialog.Refresh()
    if queueWindow and not queueWindow:IsHidden() then
        RefreshQueue()
    end
end

-- Hard teardown when the craft bag closes: stop any run and hide both windows so
-- nothing lingers and no stepper survives with the bag shut.
function WithdrawDialog.OnCraftBagHidden()
    if isWithdrawing then
        FinishRun()
    end
    HidePopup()
    HideQueueWindow()
end