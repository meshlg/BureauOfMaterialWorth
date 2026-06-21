local addon = BureauOfMaterialWorth
addon.Valuation = addon.Valuation or {}

local Valuation = addon.Valuation
local private = addon.private

-- Hot-path global caching
-- ---------------------------------------------------------------------------
-- The full rescan touches these once per slot across potentially hundreds of
-- slots; bind them to upvalues so the scan is upvalue reads, not _G hash
-- lookups. See the same rationale in BureauOfMaterialWorth.lua.
local GetSlotStackSize          = GetSlotStackSize
local GetItemId                 = GetItemId
local GetItemLink               = GetItemLink
local GetItemLinkItemType       = GetItemLinkItemType
local ZO_GetNextBagSlotIndex    = ZO_GetNextBagSlotIndex
local LibPrice                  = LibPrice

local BAG = BAG_VIRTUAL

local LogDebug = private.LogDebug
local LogInfo = private.LogInfo

-- Category model
-- ---------------------------------------------------------------------------
-- Categories mirror the crafting professions the craft bag is organized by.
-- The id is a stable string key; the nameKey is the localized display string.
-- Order here is the display order in the window. Anything that does not map to
-- a known crafting profession (style/trait/furnishing mats, etc.) lands in
-- "other".
local CATEGORY_DEFINITIONS = {
    { id = "blacksmithing", nameKey = SI_BMW_CATEGORY_BLACKSMITHING },
    { id = "clothier",      nameKey = SI_BMW_CATEGORY_CLOTHIER },
    { id = "woodworking",   nameKey = SI_BMW_CATEGORY_WOODWORKING },
    { id = "jewelry",       nameKey = SI_BMW_CATEGORY_JEWELRY },
    { id = "alchemy",       nameKey = SI_BMW_CATEGORY_ALCHEMY },
    { id = "enchanting",    nameKey = SI_BMW_CATEGORY_ENCHANTING },
    { id = "provisioning",  nameKey = SI_BMW_CATEGORY_PROVISIONING },
    { id = "other",         nameKey = SI_BMW_CATEGORY_OTHER },
}

-- ITEMTYPE -> category id map.
-- ---------------------------------------------------------------------------
-- Built once at load from the game's ITEMTYPE_* constants grouped by
-- profession. We map item types explicitly rather than calling a crafting-type
-- API because there is no global that returns "the item types for this
-- profession" in the live client. Each constant is referenced by name and
-- nil-guarded at build time (see BuildItemTypeMap), so a client build that
-- lacks one of these constants simply leaves that type unmapped -- it falls
-- back to "other" instead of erroring. Initialized empty (not nil) so a lookup
-- before BuildItemTypeMap() runs is a safe miss -> "other".
--
-- The grouping uses raw material + refined material + booster (tempers/tannins/
-- resins/plating) per equipment profession; reagents/solvents for alchemy;
-- runestones for enchanting; ingredients for provisioning. Style materials,
-- trait stones, and furnishing mats intentionally fall through to "other".
local CATEGORY_ITEM_TYPES = {
    blacksmithing = {
        "ITEMTYPE_BLACKSMITHING_RAW_MATERIAL",
        "ITEMTYPE_BLACKSMITHING_MATERIAL",
        "ITEMTYPE_BLACKSMITHING_BOOSTER",
    },
    clothier = {
        "ITEMTYPE_CLOTHIER_RAW_MATERIAL",
        "ITEMTYPE_CLOTHIER_MATERIAL",
        "ITEMTYPE_CLOTHIER_BOOSTER",
    },
    woodworking = {
        "ITEMTYPE_WOODWORKING_RAW_MATERIAL",
        "ITEMTYPE_WOODWORKING_MATERIAL",
        "ITEMTYPE_WOODWORKING_BOOSTER",
    },
    jewelry = {
        "ITEMTYPE_JEWELRYCRAFTING_RAW_MATERIAL",
        "ITEMTYPE_JEWELRYCRAFTING_MATERIAL",
        "ITEMTYPE_JEWELRYCRAFTING_RAW_BOOSTER",
        "ITEMTYPE_JEWELRYCRAFTING_BOOSTER",
    },
    alchemy = {
        "ITEMTYPE_REAGENT",
        "ITEMTYPE_POTION_BASE",
        "ITEMTYPE_POISON_BASE",
    },
    enchanting = {
        "ITEMTYPE_ENCHANTING_RUNE_ASPECT",
        "ITEMTYPE_ENCHANTING_RUNE_ESSENCE",
        "ITEMTYPE_ENCHANTING_RUNE_POTENCY",
    },
    provisioning = {
        "ITEMTYPE_INGREDIENT",
    },
}

-- Initialized empty so a category lookup is always safe even before the map is
-- built; BuildItemTypeMap() fills it on load.
local itemTypeToCategory = {}

local function BuildItemTypeMap()
    ZO_ClearTable(itemTypeToCategory)
    for categoryId, itemTypeNames in pairs(CATEGORY_ITEM_TYPES) do
        for i = 1, #itemTypeNames do
            -- Resolve the ITEMTYPE_* constant by name from the global table and
            -- skip it if this client build does not define it. This keeps a
            -- missing/renamed constant from erroring at load -- the type just
            -- stays unmapped and resolves to "other".
            local itemType = _G[itemTypeNames[i]]
            if itemType ~= nil then
                itemTypeToCategory[itemType] = categoryId
            end
        end
    end
end

local function ResolveCategory(itemLink)
    local itemType = GetItemLinkItemType(itemLink)
    return itemTypeToCategory[itemType] or "other"
end

-- Module state
-- ---------------------------------------------------------------------------
-- slotInfo caches each slot's last computed contribution (value, category,
-- stack size, priced flag) so a single-slot update can be applied
-- incrementally -- subtract the slot's old contribution from the aggregates,
-- recompute just that slot, add it back -- without rescanning the whole bag.
-- priceCache memoizes LibPrice per itemId so each distinct material costs at
-- most one (potentially expensive) LibPrice call per session. categoryStats
-- holds the running per-category aggregates the window reads; the grand* values
-- are the bag-wide rollup. This is the heart of the "no 5-10s freeze" design.
--
-- categoryStats[categoryId] = { gold, stacks, items, unpricedStacks }
--   gold          summed market value of the category
--   stacks        number of occupied slots (a "stack" = one slot)
--   items         summed stack sizes (e.g. one slot of 200 = 200 items)
--   unpricedStacks  occupied slots with no available price
local slotInfo = {}         -- [slotIndex] = { value, category, stack, priced }
local priceCache = {}       -- [itemId] = per-unit gold (false = known-unpriced)
local categoryStats = {}    -- [categoryId] = { gold, stacks, items, unpricedStacks }

local grandGold = 0
local grandStacks = 0
local grandItems = 0
local grandUnpricedStacks = 0

local lastScanTimeMs = nil  -- GetGameTimeMilliseconds() of the last full/partial recompute
local isDirty = true        -- valuation may be stale; rescan on next show
local isBagVisible = false

-- Coalesced refresh: a burst of slot updates (e.g. dumping a 200-item stack,
-- which fires per-slot events) should yield ONE window refresh, not one per
-- event. Mirrors the throttled-save pattern in BAV's QueueSave.
local REFRESH_DELAY_MS = 100
local refreshQueued = false
local REFRESH_TIMER_NAME = addon.name .. "_QueuedRefresh"

local function GetOrCreateCategoryStat(categoryId)
    local stat = categoryStats[categoryId]
    if not stat then
        stat = { gold = 0, stacks = 0, items = 0, unpricedStacks = 0 }
        categoryStats[categoryId] = stat
    end
    return stat
end

-- Per-unit price for an itemId, memoized. Returns a number, or 0 when no price
-- source has data. We cache the "unpriced" verdict as false so a missing price
-- is not re-queried on every rescan within a session.
local function GetUnitPrice(itemId, itemLink)
    local cached = priceCache[itemId]
    if cached ~= nil then
        return cached or 0, cached ~= false
    end

    local gold = LibPrice.ItemLinkToPriceGold(itemLink)
    if gold and gold > 0 then
        priceCache[itemId] = gold
        return gold, true
    end

    priceCache[itemId] = false
    return 0, false
end

-- Compute a single slot's contribution WITHOUT touching the running aggregates.
-- Returns an info record { value, category, stack, priced } for an occupied
-- slot, or nil for an empty/unknown slot. Empty virtual slots (the craft bag
-- keeps slots around after a material is fully removed) have stack size 0 and
-- contribute nothing -- this is the GetItemId/stack guard the user called out.
local function ComputeSlot(slotIndex)
    local stack = GetSlotStackSize(BAG, slotIndex)
    if not stack or stack <= 0 then
        return nil
    end

    local itemId = GetItemId(BAG, slotIndex)
    if not itemId or itemId <= 0 then
        return nil
    end

    local itemLink = GetItemLink(BAG, slotIndex)
    local unitPrice, wasPriced = GetUnitPrice(itemId, itemLink)
    return {
        value = unitPrice * stack,
        category = ResolveCategory(itemLink),
        stack = stack,
        priced = wasPriced,
    }
end

-- Remove a slot's previously-cached contribution from the aggregates. Safe to
-- call for a slot we have never seen (no-op).
local function RemoveSlotFromAggregates(slotIndex)
    local info = slotInfo[slotIndex]
    if info == nil then
        return
    end

    local stat = categoryStats[info.category]
    if stat then
        stat.gold = stat.gold - info.value
        stat.stacks = stat.stacks - 1
        stat.items = stat.items - info.stack
        if not info.priced then
            stat.unpricedStacks = stat.unpricedStacks - 1
        end
        if stat.stacks <= 0 then
            categoryStats[info.category] = nil
        end
    end

    grandGold = grandGold - info.value
    grandStacks = grandStacks - 1
    grandItems = grandItems - info.stack
    if not info.priced then
        grandUnpricedStacks = grandUnpricedStacks - 1
    end

    slotInfo[slotIndex] = nil
end

-- Add a freshly-computed slot contribution into the aggregates and cache it.
local function AddSlotToAggregates(slotIndex, info)
    if info == nil then
        -- Empty/unknown slot: nothing cached, nothing added.
        return
    end

    slotInfo[slotIndex] = info

    local stat = GetOrCreateCategoryStat(info.category)
    stat.gold = stat.gold + info.value
    stat.stacks = stat.stacks + 1
    stat.items = stat.items + info.stack
    if not info.priced then
        stat.unpricedStacks = stat.unpricedStacks + 1
    end

    grandGold = grandGold + info.value
    grandStacks = grandStacks + 1
    grandItems = grandItems + info.stack
    if not info.priced then
        grandUnpricedStacks = grandUnpricedStacks + 1
    end
end

local function ResetAggregates()
    ZO_ClearTable(slotInfo)
    ZO_ClearTable(categoryStats)
    grandGold = 0
    grandStacks = 0
    grandItems = 0
    grandUnpricedStacks = 0
end

-- Full single-pass scan of the craft bag, rebuilding every aggregate from the
-- (memoized) price cache. This is the only O(slots) operation, and it runs at
-- most once per craft-bag open (and only when dirty) or on explicit refresh.
local function FullRescan()
    ResetAggregates()

    local slotIndex = ZO_GetNextBagSlotIndex(BAG)
    local scanned = 0
    while slotIndex do
        AddSlotToAggregates(slotIndex, ComputeSlot(slotIndex))
        scanned = scanned + 1
        slotIndex = ZO_GetNextBagSlotIndex(BAG, slotIndex)
    end

    lastScanTimeMs = GetGameTimeMilliseconds()
    isDirty = false
    LogInfo(SI_BMW_LOG_RESCAN_DONE, scanned, ZO_LocalizeDecimalNumber(grandGold))
end

local function RefreshWindow()
    local window = addon.Window
    if window and isBagVisible then
        window.Update()
    end
end

-- Collapse a burst of slot updates into a single window refresh.
local function QueueWindowRefresh()
    if refreshQueued then
        return
    end
    refreshQueued = true
    EVENT_MANAGER:RegisterForUpdate(REFRESH_TIMER_NAME, REFRESH_DELAY_MS, function()
        EVENT_MANAGER:UnregisterForUpdate(REFRESH_TIMER_NAME)
        refreshQueued = false
        RefreshWindow()
    end)
end

-- EVENT_INVENTORY_SINGLE_SLOT_UPDATE handler (filtered to BAG_VIRTUAL).
-- ---------------------------------------------------------------------------
-- While the bag is closed we do NO work beyond marking the valuation dirty, so
-- background deposits never cost a scan. While the bag is open we update only
-- the one changed slot (O(1) on the aggregates) and coalesce the window
-- refresh. A genuine full inventory update falls back to a dirty flag + rescan.
local function OnSingleSlotUpdate(eventCode, bagId, slotIndex, isNewItem, soundCat, updateReason, stackCountChange)
    if bagId ~= BAG then
        return
    end

    if not isBagVisible then
        isDirty = true
        return
    end

    RemoveSlotFromAggregates(slotIndex)
    local info = ComputeSlot(slotIndex)
    AddSlotToAggregates(slotIndex, info)
    lastScanTimeMs = GetGameTimeMilliseconds()
    LogDebug(SI_BMW_LOG_SLOT_UPDATED, slotIndex, ZO_LocalizeDecimalNumber(info and info.value or 0))

    QueueWindowRefresh()
end

local function OnFullInventoryUpdate(eventCode, bagId)
    if bagId ~= BAG then
        return
    end

    if not isBagVisible then
        isDirty = true
        return
    end

    FullRescan()
    QueueWindowRefresh()
end

-- Public API ----------------------------------------------------------------

function Valuation.Initialize()
    BuildItemTypeMap()

    -- Single-slot updates are the common case (deposit/withdraw one material);
    -- filter to the craft bag so we are never woken by backpack/bank churn.
    EVENT_MANAGER:RegisterForEvent(addon.name, EVENT_INVENTORY_SINGLE_SLOT_UPDATE, OnSingleSlotUpdate)
    EVENT_MANAGER:AddFilterForEvent(addon.name, EVENT_INVENTORY_SINGLE_SLOT_UPDATE,
        REGISTER_FILTER_BAG_ID, BAG)

    -- A full update (e.g. first login population) can't be filtered the same
    -- way; the handler guards on bagId itself.
    EVENT_MANAGER:RegisterForEvent(addon.name, EVENT_INVENTORY_FULL_UPDATE, OnFullInventoryUpdate)
end

-- Called from the fragment StateChange callback when the craft bag is shown.
-- Lazy: only rescans when something marked the valuation dirty since last time.
function Valuation.OnCraftBagShown()
    isBagVisible = true
    if isDirty then
        FullRescan()
    end
end

function Valuation.OnCraftBagHidden()
    isBagVisible = false
end

-- Explicit user-driven refresh (/bmw refresh): drop the price cache so prices
-- re-query (e.g. after MM/TTC finished importing) and rebuild from scratch.
function Valuation.ForceRefresh()
    ZO_ClearTable(priceCache)
    isDirty = true
    if isBagVisible then
        FullRescan()
        RefreshWindow()
    end
end

-- Snapshot consumed by the window. Returns a single table so the window does one
-- call and reads a stable view:
--   {
--     gold, stacks, items, unpricedStacks,   -- bag-wide rollup
--     lastScanTimeMs,                         -- when the data was last computed
--     categories = { { id, name, gold, stacks, items, unpricedStacks }, ... }
--   }
-- Category rows are emitted in the canonical display order, only for categories
-- that currently hold at least one stack.
function Valuation.GetSnapshot()
    local categories = {}
    for index = 1, #CATEGORY_DEFINITIONS do
        local def = CATEGORY_DEFINITIONS[index]
        local stat = categoryStats[def.id]
        if stat and stat.stacks > 0 then
            categories[#categories + 1] = {
                id = def.id,
                name = GetString(def.nameKey),
                gold = stat.gold,
                stacks = stat.stacks,
                items = stat.items,
                unpricedStacks = stat.unpricedStacks,
            }
        end
    end

    return {
        gold = grandGold,
        stacks = grandStacks,
        items = grandItems,
        unpricedStacks = grandUnpricedStacks,
        lastScanTimeMs = lastScanTimeMs,
        categories = categories,
    }
end

function Valuation.GetStatus()
    return grandGold, grandStacks - grandUnpricedStacks, grandUnpricedStacks
end

private.GetValuationSnapshot = Valuation.GetSnapshot
