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
--   windowOffsetX/Y       fine-tune the window position relative to ZO_CraftBag
local DEFAULT_SAVED_VARS = {
    debugMode = 1,
    showCategoryBreakdown = true,
    windowOffsetX = -10,
    windowOffsetY = 0,
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
            type = "header",
            name = GetString(SI_BMW_HEADER_DISPLAY),
            width = "full",
        },
        {
            type = "checkbox",
            name = GetString(SI_BMW_SETTING_CATEGORY_BREAKDOWN_NAME),
            tooltip = GetString(SI_BMW_SETTING_CATEGORY_BREAKDOWN_TOOLTIP),
            getFunc = function() return Settings.IsCategoryBreakdownEnabled() end,
            setFunc = function(value)
                private.savedVars.showCategoryBreakdown = value
                if addon.Window then
                    addon.Window.Update()
                end
            end,
            default = DEFAULT_SAVED_VARS.showCategoryBreakdown,
            width = "full",
        },
        {
            type = "slider",
            name = GetString(SI_BMW_SETTING_OFFSET_X_NAME),
            tooltip = GetString(SI_BMW_SETTING_OFFSET_X_TOOLTIP),
            min = -400,
            max = 400,
            step = 5,
            getFunc = function() return GetSavedVarsOrDefaults().windowOffsetX or -10 end,
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
