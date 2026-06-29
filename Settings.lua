local addon = BureauOfMaterialWorth
addon.Settings = addon.Settings or {}

local Settings = addon.Settings
local private = addon.private

local GetString = GetString
local tonumber = tonumber

-- Default account-wide configuration. Kept deliberately small: this addon has
-- no gameplay-affecting state, only presentation/diagnostics.
--   debugMode             chat verbosity (mirrors the core's debugMode contract)
--   showCategoryBreakdown show per-profession subtotals under the grand total
--   showCategoryIcons     draw a profession icon left of each category name
--   colorScaleGold        tint gold figures by magnitude (dim -> hot) instead of flat gold
--   sortByValue           order category rows by descending value (vs profession order)
--   deltaMode             "since last visit" baseline: "visit" (per open) or "session" (until reloadui/logout)
--   showBackground        draw the panel's dark background fill
--   showBorder            draw the panel's border edge
--   windowWidth           panel width in px (see Window MIN/MAX/STEP bounds)
--   windowOffsetX/Y       fine-tune the window position relative to ZO_CraftBag
--   showInGuildStore      show the panel while the guild store is open (shifted clear of the store UI)
--   lastVisitGold         grand total saved on last bag close, for the "since last visit" delta
--   lastVisitItems        total item count saved alongside it, to gate the delta on real stock changes
--   priceHistory          [itemId] = { p = unit price, t = unix timestamp }; baseline for the detail window's price-change column
--   showValueHistory      draw the grand-total sparkline (Craft Bag value over time) in the footer
--   notifyOnVisit         print the bag value (and since-last-visit change) to chat on the first open of each session
--   valueHistory          ring buffer of grand-total samples; { head = <last index, 0 = empty>,
--                         entries = { { t = unix, gold, items }, ... } }. See Valuation's
--                         RecordValuePoint/GetValueHistory for the wrap-around bookkeeping.
--   snapshot              manual single snapshot of bag composition for the detail window's
--                         diff view; nil until "Remember" is pressed (then overwritten). Shape:
--                         { t, gold, items, slots, materials = { [itemId] = { name, icon,
--                         quality, count, unitPrice, gold, priced } } }. See Valuation's
--                         CaptureSnapshot/GetDiffMaterials.
local DEFAULT_SAVED_VARS = {
    debugMode = 1,
    showCategoryBreakdown = true,
    showCategoryIcons = true,
    colorScaleGold = true,
    sortByValue = false,
    deltaMode = "visit",
    showBackground = true,
    showBorder = false,
    showValueHistory = true,
    notifyOnVisit = true,
    showInGuildStore = true,
    windowWidth = 400,
    windowOffsetX = -25,
    windowOffsetY = 0,
    priceHistory = {},
    valueHistory = { head = 0, entries = {} },
}

local function GetSavedVarsOrDefaults()
    return private.savedVars or DEFAULT_SAVED_VARS
end

function Settings.GetSavedVars()
    return private.savedVars
end

function Settings.InitializeSavedVariables()
    private.savedVars = ZO_SavedVars:NewAccountWide(
        addon.savedVariablesName,
        1,
        nil,
        DEFAULT_SAVED_VARS
    )

    -- Adopt the persisted debug level as the live one on load, so the core's
    -- debugMode reflects the saved choice (the slash command can still override
    -- it at runtime).
    local level = tonumber(private.savedVars.debugMode)
    if level and level >= 0 and level <= 4 then
        addon.debugMode = level
    end

    return private.savedVars
end

function Settings.IsCategoryBreakdownEnabled()
    return GetSavedVarsOrDefaults().showCategoryBreakdown ~= false
end

function Settings.SetDebugMode(level, suppressOutput)
    level = tonumber(level) or 0
    if level >= 0 and level <= 4 then
        addon.debugMode = level
        if private.savedVars then
            private.savedVars.debugMode = level
        end
        if not suppressOutput then
            private.ChatInfo(SI_BMW_MSG_DEBUG_MODE_SET, private.GetDebugLevelName(level), level)
        end
        return true
    end

    if not suppressOutput then
        private.ChatError(SI_BMW_MSG_INVALID_DEBUG_LEVEL)
    end
    return false
end

function Settings.RegisterSettingsPanel()
    local lam = LibAddonMenu2
    if not lam then
        private.LogWarn(SI_BMW_LOG_LAM_MISSING)
        return
    end

    local panelIdentifier = addon.name .. "_Settings"
    local debugChoices = {
        private.GetDebugLevelName(0),
        private.GetDebugLevelName(1),
        private.GetDebugLevelName(2),
        private.GetDebugLevelName(3),
        private.GetDebugLevelName(4),
    }

    -- ---------------------------------------------------------------------------
    -- Single source of truth for the panel's read side
    -- ---------------------------------------------------------------------------
    -- Every control's getFunc, the status dashboard, and the breakdown submenu's
    -- gating all read these, so the three can never disagree. Defaults mirror
    -- DEFAULT_SAVED_VARS (the same ~= false / == true sense the window uses).
    local function IsBreakdownOn()    return Settings.IsCategoryBreakdownEnabled() end
    local function IsIconsOn()        return GetSavedVarsOrDefaults().showCategoryIcons ~= false end
    local function IsColorScaleOn()   return GetSavedVarsOrDefaults().colorScaleGold ~= false end
    local function IsSortByValueOn()  return GetSavedVarsOrDefaults().sortByValue == true end
    local function IsValueHistoryOn() return GetSavedVarsOrDefaults().showValueHistory ~= false end
    local function IsNotifyOn()       return GetSavedVarsOrDefaults().notifyOnVisit ~= false end
    local function IsGuildStoreOn()   return GetSavedVarsOrDefaults().showInGuildStore ~= false end
    local function GetDeltaMode()     return GetSavedVarsOrDefaults().deltaMode or DEFAULT_SAVED_VARS.deltaMode end

    -- The icon/color/sort controls only do anything while the breakdown is shown
    -- (see Window.Update, which renders category rows solely inside that branch),
    -- so they gate on this shared condition rather than going dim only globally.
    local function BreakdownDisabled()
        return not IsBreakdownOn()
    end

    -- ---------------------------------------------------------------------------
    -- Live status helpers (panel dashboard + breakdown submenu title tag)
    -- ---------------------------------------------------------------------------
    -- LAM re-reads function-valued `text`/`name` on every setting change and on
    -- panel open (registerForRefresh is set), so these read live each time. The
    -- block reflects the saved configuration, not the live bag value: the
    -- valuation only runs while the Craft Bag is open, so a value readout here
    -- would be stale or zero. On = the shipped green, off = the muted label grey;
    -- mode rows (order/baseline are not on/off) use the neutral label tone.
    local STATUS_COLOR_ON   = "6FCB9F"
    local STATUS_COLOR_OFF  = "8C8A82"
    local STATUS_COLOR_MODE = "C5C29E"

    local function Colorize(colorHex, text)
        return string.format("|c%s%s|r", colorHex, text)
    end

    -- A plain colored on/off word for the dashboard rows.
    local function StatusOnOff(enabled)
        return Colorize(enabled and STATUS_COLOR_ON or STATUS_COLOR_OFF,
            GetString(enabled and SI_BMW_STATUS_ON or SI_BMW_STATUS_OFF))
    end

    -- A bracketed colored tag for a submenu title. `word` is already localized.
    local function StatusTag(enabled, word)
        return Colorize(enabled and STATUS_COLOR_ON or STATUS_COLOR_OFF, "[" .. word .. "]")
    end

    local function BoolTag(enabled)
        return StatusTag(enabled, GetString(enabled and SI_BMW_STATUS_ON or SI_BMW_STATUS_OFF))
    end

    -- A neutral-toned value for the mode rows (sort order / change baseline),
    -- which are a choice between modes rather than an on/off state.
    local function ModeValue(word)
        return Colorize(STATUS_COLOR_MODE, word)
    end

    -- "Label  value" dashboard row; the label is localized, the value pre-colored.
    local function StatusRow(labelKey, valueText)
        return string.format("%s  %s", GetString(labelKey), valueText)
    end

    -- Sort order is a mode, not on/off: show which ordering is in effect.
    local function SortWord()
        return GetString(IsSortByValueOn() and SI_BMW_STATUS_SORT_BY_VALUE
            or SI_BMW_STATUS_SORT_BY_PROFESSION)
    end

    -- The change baseline is a mode (visit/session); reuse the dropdown's own
    -- localized choice strings so the dashboard label matches the control.
    local function DeltaWord()
        return GetString(GetDeltaMode() == "session"
            and SI_BMW_SETTING_DELTA_MODE_SESSION or SI_BMW_SETTING_DELTA_MODE_VISIT)
    end

    -- One "Label  value" row per key feature/state, read through the same getters
    -- the controls below use so the block can never drift from them.
    local function BuildStatusText()
        local rows = {
            StatusRow(SI_BMW_STATUS_LABEL_BREAKDOWN,     StatusOnOff(IsBreakdownOn())),
            StatusRow(SI_BMW_STATUS_LABEL_SORT,          ModeValue(SortWord())),
            StatusRow(SI_BMW_STATUS_LABEL_COLOR_SCALE,   StatusOnOff(IsColorScaleOn())),
            StatusRow(SI_BMW_STATUS_LABEL_VALUE_HISTORY, StatusOnOff(IsValueHistoryOn())),
            StatusRow(SI_BMW_STATUS_LABEL_NOTIFY,        StatusOnOff(IsNotifyOn())),
            StatusRow(SI_BMW_STATUS_LABEL_GUILD_STORE,   StatusOnOff(IsGuildStoreOn())),
            StatusRow(SI_BMW_STATUS_LABEL_DELTA,         ModeValue(DeltaWord())),
        }
        return table.concat(rows, "\n")
    end

    local panelData = {
        type = "panel",
        name = GetString(SI_BMW_PANEL_NAME),
        displayName = GetString(SI_BMW_PANEL_DISPLAY_NAME),
        author = "|c6FCB9Fmeshlg|r",
        version = addon.version,
        slashCommand = "/bmwsettings",
        registerForRefresh = true,
        registerForDefaults = true,
    }

    local optionsData = {
        {
            type = "description",
            text = GetString(SI_BMW_PANEL_INTRO),
            width = "full",
        },
        {
            type = "description",
            text = GetString(SI_BMW_PANEL_OVERVIEW),
            width = "full",
        },
        {
            -- Live at-a-glance dashboard. function-valued text so LAM refreshes it
            -- on panel open and after any setting change (registerForRefresh).
            type = "description",
            title = GetString(SI_BMW_STATUS_TITLE),
            text = BuildStatusText,
            width = "full",
            reference = "BMWSettingsStatusBlock",
        },
        {
            type = "header",
            name = GetString(SI_BMW_HEADER_DISPLAY),
            width = "full",
        },
        {
            -- Category-breakdown cluster. The master "show breakdown" toggle plus
            -- the three controls (icons, color, sort) that only do anything while
            -- it is on, grouped in a submenu whose title carries a live [on]/[off]
            -- tag. The dependent controls gate on BreakdownDisabled so they grey
            -- out together when the breakdown is off.
            type = "submenu",
            name = function()
                return GetString(SI_BMW_SUBMENU_BREAKDOWN_NAME) .. "  " .. BoolTag(IsBreakdownOn())
            end,
            tooltip = GetString(SI_BMW_SUBMENU_BREAKDOWN_DESCRIPTION),
            controls = {
                {
                    type = "description",
                    text = GetString(SI_BMW_SUBMENU_BREAKDOWN_DESCRIPTION),
                    width = "full",
                },
                {
                    type = "checkbox",
                    name = GetString(SI_BMW_SETTING_CATEGORY_BREAKDOWN_NAME),
                    tooltip = GetString(SI_BMW_SETTING_CATEGORY_BREAKDOWN_TOOLTIP),
                    getFunc = function() return IsBreakdownOn() end,
                    setFunc = function(value)
                        private.savedVars.showCategoryBreakdown = value
                        if addon.Window then
                            addon.Window.Update()
                        end
                    end,
                    default = DEFAULT_SAVED_VARS.showCategoryBreakdown,
                    width = "full",
                    reference = "BMWSettingsCategoryBreakdown",
                },
                {
                    type = "checkbox",
                    name = GetString(SI_BMW_SETTING_CATEGORY_ICONS_NAME),
                    tooltip = GetString(SI_BMW_SETTING_CATEGORY_ICONS_TOOLTIP),
                    getFunc = function() return IsIconsOn() end,
                    setFunc = function(value)
                        private.savedVars.showCategoryIcons = value
                        if addon.Window then
                            addon.Window.Update()
                        end
                    end,
                    default = DEFAULT_SAVED_VARS.showCategoryIcons,
                    disabled = BreakdownDisabled,
                    width = "full",
                    reference = "BMWSettingsCategoryIcons",
                },
                {
                    type = "checkbox",
                    name = GetString(SI_BMW_SETTING_COLOR_SCALE_NAME),
                    tooltip = GetString(SI_BMW_SETTING_COLOR_SCALE_TOOLTIP),
                    getFunc = function() return IsColorScaleOn() end,
                    setFunc = function(value)
                        private.savedVars.colorScaleGold = value
                        if addon.Window then
                            addon.Window.Update()
                        end
                    end,
                    default = DEFAULT_SAVED_VARS.colorScaleGold,
                    disabled = BreakdownDisabled,
                    width = "full",
                    reference = "BMWSettingsColorScale",
                },
                {
                    type = "checkbox",
                    name = GetString(SI_BMW_SETTING_SORT_BY_VALUE_NAME),
                    tooltip = GetString(SI_BMW_SETTING_SORT_BY_VALUE_TOOLTIP),
                    getFunc = function() return IsSortByValueOn() end,
                    setFunc = function(value)
                        private.savedVars.sortByValue = value
                        if addon.Window then
                            addon.Window.Update()
                        end
                    end,
                    default = DEFAULT_SAVED_VARS.sortByValue,
                    disabled = BreakdownDisabled,
                    width = "full",
                    reference = "BMWSettingsSortByValue",
                },
            },
        },
        {
            type = "dropdown",
            name = GetString(SI_BMW_SETTING_DELTA_MODE_NAME),
            tooltip = GetString(SI_BMW_SETTING_DELTA_MODE_TOOLTIP),
            choices = { GetString(SI_BMW_SETTING_DELTA_MODE_VISIT), GetString(SI_BMW_SETTING_DELTA_MODE_SESSION) },
            choicesValues = { "visit", "session" },
            getFunc = function() return GetDeltaMode() end,
            setFunc = function(value)
                private.savedVars.deltaMode = value
                if addon.Window then
                    addon.Window.Update()
                end
            end,
            default = DEFAULT_SAVED_VARS.deltaMode,
            width = "full",
        },
        {
            type = "checkbox",
            name = GetString(SI_BMW_SETTING_BACKGROUND_NAME),
            tooltip = GetString(SI_BMW_SETTING_BACKGROUND_TOOLTIP),
            getFunc = function() return GetSavedVarsOrDefaults().showBackground ~= false end,
            setFunc = function(value)
                private.savedVars.showBackground = value
                if addon.Window then
                    addon.Window.ApplyAppearance()
                end
            end,
            default = DEFAULT_SAVED_VARS.showBackground,
            width = "full",
        },
        {
            type = "checkbox",
            name = GetString(SI_BMW_SETTING_BORDER_NAME),
            tooltip = GetString(SI_BMW_SETTING_BORDER_TOOLTIP),
            getFunc = function() return GetSavedVarsOrDefaults().showBorder ~= false end,
            setFunc = function(value)
                private.savedVars.showBorder = value
                if addon.Window then
                    addon.Window.ApplyAppearance()
                end
            end,
            default = DEFAULT_SAVED_VARS.showBorder,
            width = "full",
        },
        {
            type = "checkbox",
            name = GetString(SI_BMW_SETTING_VALUE_HISTORY_NAME),
            tooltip = GetString(SI_BMW_SETTING_VALUE_HISTORY_TOOLTIP),
            getFunc = function() return IsValueHistoryOn() end,
            setFunc = function(value)
                private.savedVars.showValueHistory = value
                if addon.Window then
                    addon.Window.Update()
                end
            end,
            default = DEFAULT_SAVED_VARS.showValueHistory,
            width = "full",
        },
        {
            type = "checkbox",
            name = GetString(SI_BMW_SETTING_NOTIFY_VISIT_NAME),
            tooltip = GetString(SI_BMW_SETTING_NOTIFY_VISIT_TOOLTIP),
            getFunc = function() return IsNotifyOn() end,
            setFunc = function(value)
                private.savedVars.notifyOnVisit = value
            end,
            default = DEFAULT_SAVED_VARS.notifyOnVisit,
            width = "full",
        },
        {
            type = "checkbox",
            name = GetString(SI_BMW_SETTING_GUILD_STORE_NAME),
            tooltip = GetString(SI_BMW_SETTING_GUILD_STORE_TOOLTIP),
            getFunc = function() return IsGuildStoreOn() end,
            setFunc = function(value)
                private.savedVars.showInGuildStore = value
                if addon.Window then
                    addon.Window.Show()
                end
            end,
            default = DEFAULT_SAVED_VARS.showInGuildStore,
            width = "full",
        },
        {
            type = "slider",
            name = GetString(SI_BMW_SETTING_WIDTH_NAME),
            tooltip = GetString(SI_BMW_SETTING_WIDTH_TOOLTIP),
            min = addon.Window and addon.Window.MIN_WIDTH or 400,
            max = addon.Window and addon.Window.MAX_WIDTH or 600,
            step = addon.Window and addon.Window.WIDTH_STEP or 10,
            getFunc = function() return GetSavedVarsOrDefaults().windowWidth or DEFAULT_SAVED_VARS.windowWidth end,
            setFunc = function(value)
                private.savedVars.windowWidth = value
                if addon.Window then
                    addon.Window.ApplyWidth()
                end
            end,
            default = DEFAULT_SAVED_VARS.windowWidth,
            width = "full",
        },
        {
            type = "slider",
            name = GetString(SI_BMW_SETTING_OFFSET_X_NAME),
            tooltip = GetString(SI_BMW_SETTING_OFFSET_X_TOOLTIP),
            min = -400,
            max = 400,
            step = 5,
            getFunc = function() return GetSavedVarsOrDefaults().windowOffsetX or -25 end,
            setFunc = function(value)
                private.savedVars.windowOffsetX = value
                if addon.Window then
                    addon.Window.ApplyAnchor()
                end
            end,
            default = DEFAULT_SAVED_VARS.windowOffsetX,
            width = "full",
        },
        {
            type = "slider",
            name = GetString(SI_BMW_SETTING_OFFSET_Y_NAME),
            tooltip = GetString(SI_BMW_SETTING_OFFSET_Y_TOOLTIP),
            min = -400,
            max = 400,
            step = 5,
            getFunc = function() return GetSavedVarsOrDefaults().windowOffsetY or 0 end,
            setFunc = function(value)
                private.savedVars.windowOffsetY = value
                if addon.Window then
                    addon.Window.ApplyAnchor()
                end
            end,
            default = DEFAULT_SAVED_VARS.windowOffsetY,
            width = "full",
        },
        {
            type = "header",
            name = GetString(SI_BMW_HEADER_DIAGNOSTICS),
            width = "full",
        },
        {
            type = "dropdown",
            name = GetString(SI_BMW_SETTING_DEBUG_MODE_NAME),
            tooltip = GetString(SI_BMW_SETTING_DEBUG_MODE_TOOLTIP),
            choices = debugChoices,
            getFunc = function() return private.GetDebugLevelName(addon.debugMode) end,
            setFunc = function(value)
                for level = 0, 4 do
                    if value == private.GetDebugLevelName(level) then
                        Settings.SetDebugMode(level, true)
                        break
                    end
                end
            end,
            default = private.GetDebugLevelName(DEFAULT_SAVED_VARS.debugMode),
            width = "full",
        },
        {
            type = "button",
            name = GetString(SI_BMW_SETTING_REFRESH_NAME),
            tooltip = GetString(SI_BMW_SETTING_REFRESH_TOOLTIP),
            func = function()
                if addon.Valuation then
                    addon.Valuation.ForceRefresh()
                end
            end,
            width = "full",
        },
    }

    local panel = lam:RegisterAddonPanel(panelIdentifier, panelData)
    lam:RegisterOptionControls(panelIdentifier, optionsData)
    Settings.panel = panel
end

-- Opens the settings panel programmatically (used by the `/bmw settings` slash
-- sub-command). Returns true when the panel was opened, false when the
-- LibAddonMenu dependency is unavailable so the caller can report it.
function Settings.OpenPanel()
    local lam = LibAddonMenu2
    if not lam or not Settings.panel then
        return false
    end

    lam:OpenToPanel(Settings.panel)
    return true
end

addon.SetDebugMode = Settings.SetDebugMode
addon.RegisterSettingsPanel = Settings.RegisterSettingsPanel
addon.OpenSettingsPanel = Settings.OpenPanel
