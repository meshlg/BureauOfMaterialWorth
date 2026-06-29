-- Addon namespace
local ADDON_NAME = "BureauOfMaterialWorth"
local SAVED_VARIABLES_NAME = "BureauOfMaterialWorth_SavedVariables"

BureauOfMaterialWorth = {
    name = ADDON_NAME,
    savedVariablesName = SAVED_VARIABLES_NAME,
    version = "1.5.29062155",
    debugMode = 1,  -- 0=off, 1=errors, 2=warnings, 3=info, 4=verbose
}

local private = {}
BureauOfMaterialWorth.private = private

-- Hot-path global caching
-- ---------------------------------------------------------------------------
-- In Lua, every reference to a global is a hash lookup in _G. The craft-bag
-- scan touches the ESO inventory API and the standard library once per slot,
-- across potentially hundreds of slots, so those functions are bound to locals
-- (upvalues) once at load time. This turns repeated global lookups into cheap
-- upvalue reads without changing behaviour. Keep this block above the first
-- function definition so the closures below capture these locals.
local GetString     = GetString
local d             = d
local select        = select
local type          = type
local tonumber      = tonumber
local stringformat  = string.format
local stringgmatch  = string.gmatch
local stringlower   = string.lower
local tableinsert   = table.insert
local mathmax       = math.max
local mathmin       = math.min

-- Localization/chat helpers
local CHAT_PREFIX = "|c6FCB9F[Bureau Of Material Worth]|r: "
local CHAT_ERROR_PREFIX = "|cFF0000[Bureau Of Material Worth]|r: "

local DEBUG_LEVEL_STRING_IDS = {
    SI_BMW_DEBUG_LEVEL_OFF,
    SI_BMW_DEBUG_LEVEL_ERRORS,
    SI_BMW_DEBUG_LEVEL_WARNINGS,
    SI_BMW_DEBUG_LEVEL_INFO,
    SI_BMW_DEBUG_LEVEL_VERBOSE,
}

local function ResolveLocalizedText(message)
    if type(message) == "number" then
        return GetString(message)
    end

    return tostring(message)
end

local function FormatLocalizedText(message, ...)
    local localizedText = ResolveLocalizedText(message)
    if select("#", ...) > 0 then
        return stringformat(localizedText, ...)
    end
    return localizedText
end

local function GetLocalizedBoolean(value)
    return GetString(value and SI_BMW_BOOL_TRUE or SI_BMW_BOOL_FALSE)
end

local function GetDebugLevelName(level)
    level = mathmax(0, mathmin(4, tonumber(level) or 0))
    return GetString(DEBUG_LEVEL_STRING_IDS[level + 1] or DEBUG_LEVEL_STRING_IDS[1])
end

local function ChatInfo(message, ...)
    d(CHAT_PREFIX .. FormatLocalizedText(message, ...))
end

local function ChatError(message, ...)
    d(CHAT_ERROR_PREFIX .. FormatLocalizedText(message, ...))
end

-- Debug logging system
-- ---------------------------------------------------------------------------
-- Log levels are defined once here. The numeric values double as the
-- debugMode thresholds (emit when debugMode >= level), so this enum is the
-- single source of truth for both the public debugMode contract and the
-- generated Log* helpers below.
local LOG_LEVEL = {
    ERROR = 1,
    WARN  = 2,
    INFO  = 3,
    DEBUG = 4,
}

-- String id per level. Kept as ids (not resolved strings) so GetString is
-- only ever called at log time -- this file stays independent of the
-- localization load order.
local LOG_LEVEL_STRING_IDS = {
    [LOG_LEVEL.ERROR] = SI_BMW_LOG_LEVEL_ERROR,
    [LOG_LEVEL.WARN]  = SI_BMW_LOG_LEVEL_WARN,
    [LOG_LEVEL.INFO]  = SI_BMW_LOG_LEVEL_INFO,
    [LOG_LEVEL.DEBUG] = SI_BMW_LOG_LEVEL_DEBUG,
}

local function Log(level, message, ...)
    if BureauOfMaterialWorth.debugMode < level then
        return
    end

    local stringId = LOG_LEVEL_STRING_IDS[level]
    local prefix = stringId and (GetString(stringId) .. " ") or ""
    d(CHAT_PREFIX .. prefix .. FormatLocalizedText(message, ...))
end

-- Level-specific helpers (LogError/LogWarn/LogInfo/LogDebug) are generated
-- from LOG_LEVEL so adding a level needs no extra boilerplate. They are
-- forward-declared as locals first, so closures defined later in the file
-- capture them as upvalues and tooling still resolves each name.
local LogError, LogWarn, LogInfo, LogDebug
do
    local generated = {}
    for name, level in pairs(LOG_LEVEL) do
        generated[name] = function(...) Log(level, ...) end
    end
    LogError = generated.ERROR
    LogWarn  = generated.WARN
    LogInfo  = generated.INFO
    LogDebug = generated.DEBUG
end

-- Shared helpers exposed to the other modules (Valuation/Window/Settings) via
-- the private table, so each module routes chat/log output through the same
-- localized, prefixed path instead of touching d() directly.
private.ChatInfo = ChatInfo
private.ChatError = ChatError
private.GetLocalizedBoolean = GetLocalizedBoolean
private.GetDebugLevelName = GetDebugLevelName
private.LogError = LogError
private.LogWarn = LogWarn
private.LogInfo = LogInfo
private.LogDebug = LogDebug

-- Local state
local savedVars = {}

local function GetSettingsModule()
    return BureauOfMaterialWorth.Settings
end

local function GetValuationModule()
    return BureauOfMaterialWorth.Valuation
end

local function GetWindowModule()
    return BureauOfMaterialWorth.Window
end

local function GetDetailWindowModule()
    return BureauOfMaterialWorth.DetailWindow
end

local function GetWithdrawDialogModule()
    return BureauOfMaterialWorth.WithdrawDialog
end

-- Craft-bag visibility wiring
-- ---------------------------------------------------------------------------
-- The window is only meaningful while the craft bag is on screen, and -- per
-- the performance design -- we do no scanning work while it is closed. The
-- craft-bag fragment's StateChange callback is the single authority on
-- visibility: showing it triggers a (lazy, dirty-gated) rescan and reveals the
-- window; hiding it just hides the window. Inventory updates that arrive while
-- the bag is closed only mark the valuation dirty (handled in Valuation).
local function OnCraftBagFragmentStateChange(oldState, newState)
    local valuation = GetValuationModule()
    local window = GetWindowModule()

    if newState == SCENE_FRAGMENT_SHOWN then
        LogDebug(SI_BMW_LOG_CRAFTBAG_SHOWN)
        if valuation then
            valuation.OnCraftBagShown()
        end
        if window then
            window.Show()
        end
    elseif newState == SCENE_FRAGMENT_HIDDEN then
        LogDebug(SI_BMW_LOG_CRAFTBAG_HIDDEN)
        if valuation then
            valuation.OnCraftBagHidden()
        end
        if window then
            window.Hide()
        end
        local detail = GetDetailWindowModule()
        if detail then
            detail.OnCraftBagHidden()
        end
        local withdraw = GetWithdrawDialogModule()
        if withdraw then
            withdraw.OnCraftBagHidden()
        end
    end
end

-- Event handler for EVENT_ADD_ON_LOADED
local function OnAddonLoaded(event, addonName)
    if addonName ~= BureauOfMaterialWorth.name then
        return
    end

    EVENT_MANAGER:UnregisterForEvent(BureauOfMaterialWorth.name, EVENT_ADD_ON_LOADED)
    LogInfo(SI_BMW_LOG_ONADDONLOADED_LOADING, BureauOfMaterialWorth.version)

    -- LibPrice is the core dependency: without a price source there is nothing
    -- to sum. It is declared as a hard DependsOn, but guard anyway so a broken
    -- install fails loudly in chat instead of erroring deep in the scan.
    if not LibPrice then
        ChatError(SI_BMW_MSG_LIBPRICE_MISSING)
        return
    end

    -- Initialize the settings module and SavedVariables
    savedVars = GetSettingsModule().InitializeSavedVariables()
    private.savedVars = savedVars

    -- Build the window and the valuation engine now that SavedVariables exist.
    if GetWindowModule() then
        GetWindowModule().Initialize()
    end
    if GetDetailWindowModule() then
        GetDetailWindowModule().Initialize()
    end
    if GetWithdrawDialogModule() then
        GetWithdrawDialogModule().Initialize()
    end
    if GetValuationModule() then
        GetValuationModule().Initialize()
    end

    -- Visibility drives all scan work: register the craft-bag fragment callback.
    CRAFT_BAG_FRAGMENT:RegisterCallback("StateChange", OnCraftBagFragmentStateChange)

    BureauOfMaterialWorth.RegisterSettingsPanel()

    LogInfo(SI_BMW_LOG_ADDON_LOADED)
end

EVENT_MANAGER:RegisterForEvent(BureauOfMaterialWorth.name, EVENT_ADD_ON_LOADED, OnAddonLoaded)

-- Diagnostics / slash command surface
-- ---------------------------------------------------------------------------
local function DumpStatus()
    local valuation = GetValuationModule()
    ChatInfo(SI_BMW_MSG_VERSION_DEBUG,
        BureauOfMaterialWorth.version,
        GetDebugLevelName(BureauOfMaterialWorth.debugMode), BureauOfMaterialWorth.debugMode)

    if not valuation then
        return
    end

    local grandTotal, pricedSlots, unpricedSlots = valuation.GetStatus()
    -- grandTotal is a sum of (unit price * stack) and can be fractional;
    -- ZO_LocalizeDecimalNumber errors on non-integers, so round before formatting.
    ChatInfo(SI_BMW_MSG_STATUS_TOTAL, ZO_LocalizeDecimalNumber(zo_round(grandTotal or 0)))
    ChatInfo(SI_BMW_MSG_STATUS_SLOTS, pricedSlots or 0, unpricedSlots or 0)
end

local function SetDebugMode(level, suppressOutput)
    return GetSettingsModule().SetDebugMode(level, suppressOutput)
end

local function OpenSettingsPanel()
    return GetSettingsModule().OpenPanel()
end

function BureauOfMaterialWorth.RegisterSettingsPanel()
    return GetSettingsModule().RegisterSettingsPanel()
end

private.DumpStatus = DumpStatus

-- Comprehensive slash command
-- ---------------------------------------------------------------------------
-- Sub-commands are looked up in a dispatch table instead of an if/elseif
-- ladder: adding a command is a single table entry, lookup is O(1), and each
-- handler receives the parsed, lower-cased argument list. Unknown actions fall
-- through to the shared error handler.
local SLASH_HELP_STRING_IDS = {
    SI_BMW_MSG_HELP_TITLE,
    SI_BMW_MSG_HELP_STATUS,
    SI_BMW_MSG_HELP_REFRESH,
    SI_BMW_MSG_HELP_SETTINGS,
    SI_BMW_MSG_HELP_DEBUG,
    SI_BMW_MSG_HELP_HELP,
}

local SLASH_COMMAND_HANDLERS = {
    status = function(args)
        DumpStatus()
    end,
    refresh = function(args)
        local valuation = GetValuationModule()
        if valuation then
            valuation.ForceRefresh()
            ChatInfo(SI_BMW_MSG_REFRESH_DONE)
        end
    end,
    debug = function(args)
        SetDebugMode(args[2])
    end,
    settings = function(args)
        if not OpenSettingsPanel() then
            ChatError(SI_BMW_MSG_SETTINGS_UNAVAILABLE)
        end
    end,
    help = function(args)
        for index = 1, #SLASH_HELP_STRING_IDS do
            ChatInfo(SLASH_HELP_STRING_IDS[index])
        end
    end,
}

-- Convenience aliases so `/bmw ui` and `/bmw panel` also open the settings
-- window, mirroring the primary `settings` sub-command.
SLASH_COMMAND_HANDLERS.ui = SLASH_COMMAND_HANDLERS.settings
SLASH_COMMAND_HANDLERS.panel = SLASH_COMMAND_HANDLERS.settings

SLASH_COMMANDS["/bmw"] = function(cmd)
    local args = {}
    for word in stringgmatch(cmd, "%S+") do
        tableinsert(args, stringlower(word))
    end

    local action = args[1] or "status"
    local handler = SLASH_COMMAND_HANDLERS[action]
    if handler then
        handler(args)
    else
        ChatError(SI_BMW_MSG_UNKNOWN_COMMAND)
    end
end
