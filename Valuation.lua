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

-- A "classic" inventory stack is 200 identical items. The craft bag itself has
-- no such limit (one material = one unbounded slot), so we report two distinct
-- figures that must never be conflated:
--   slots  -- occupied craft-bag slots == number of distinct materials
--   stacks -- ceil(items / STACK_SIZE), how many 200-item stacks the volume is
-- The slot count is what the incremental aggregates track; the stack count is
-- derived from the item total at snapshot time (see GetSnapshot).
local STACK_SIZE = 200

local zo_ceil = zo_ceil

-- Number of classic 200-item stacks a raw item count occupies. 0 items -> 0
-- stacks; any partial stack rounds up to a whole one.
local function ItemsToStacks(items)
    if not items or items <= 0 then
        return 0
    end
    return zo_ceil(items / STACK_SIZE)
end

local LogDebug = private.LogDebug
local LogInfo = private.LogInfo

-- Human-readable names for LibPrice source keys (the second return of
-- ItemLinkToPriceGold). LibPrice has no built-in display-name map, so we keep
-- our own; an unknown key falls back to its raw string rather than erroring.
local SOURCE_DISPLAY_NAMES = {
    mm    = "Master Merchant",
    att   = "Arkadius' Trade Tools",
    ttc   = "Tamriel Trade Centre",
    furc  = "Furniture Catalogue",
    crown = "Crown Store",
    rolis = "Rolis Hlaalu",
    npc   = "NPC Vendor",
}

-- Compact source labels for the tight footer value column, where the full names
-- above would not fit. Falls back to the raw key (upper-cased) for unknowns.
local SOURCE_SHORT_NAMES = {
    mm    = "MM",
    att   = "ATT",
    ttc   = "TTC",
    furc  = "FurC",
    crown = "Crown",
    rolis = "Rolis",
    npc   = "NPC",
}

local function SourceDisplayName(sourceKey)
    if not sourceKey then
        return nil
    end
    return SOURCE_DISPLAY_NAMES[sourceKey] or sourceKey
end

local function SourceShortName(sourceKey)
    if not sourceKey then
        return nil
    end
    return SOURCE_SHORT_NAMES[sourceKey] or string.upper(sourceKey)
end

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
-- categoryStats[categoryId] = { gold, slots, items, unpricedSlots }
--   gold          summed market value of the category
--   slots         number of occupied craft-bag slots (== distinct materials)
--   items         summed slot sizes (e.g. one slot of 350000 = 350000 items)
--   unpricedSlots occupied slots with no available price
-- The classic 200-item stack count is NOT stored here; it is derived from
-- `items` via ItemsToStacks() at snapshot time so the two figures can never
-- drift out of sync.
local slotInfo = {}         -- [slotIndex] = { value, category, stack, priced, source }
local priceCache = {}       -- [itemId] = per-unit gold (false = known-unpriced)
local priceSource = {}      -- [itemId] = LibPrice source key ("mm"/"ttc"/...) when priced
local categoryStats = {}    -- [categoryId] = { gold, slots, items, unpricedSlots }
local sourceCounts = {}     -- [sourceKey] = number of priced slots sourced from it

local grandGold = 0
local grandSlots = 0
local grandItems = 0
local grandUnpricedSlots = 0

-- "Since last visit" delta shown in the footer, recomputed once per bag open.
-- Two baselines feed it depending on the user's deltaMode setting:
--   "visit"   -- compare against the previous bag open; baseline persists in
--                savedVars (lastVisitGold/Items) so it survives a restart.
--   "session" -- compare against the first open after UI load; baseline lives in
--                the memory upvalues below and resets on /reloadui or logout.
-- In both modes the gold delta is gated on the item count changing, so a pure
-- price drift (restart + price reimport, same stock) reports no delta.
local deltaSinceLastVisit = nil
local sessionBaseGold = nil   -- session-mode baseline: gold at first open this session
local sessionBaseItems = nil  -- session-mode baseline: item count alongside it

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
        stat = { gold = 0, slots = 0, items = 0, unpricedSlots = 0 }
        categoryStats[categoryId] = stat
    end
    return stat
end

-- Per-unit price for an itemId, memoized. Returns the per-unit gold (or 0 when
-- no source has data), a priced flag, and the LibPrice source key the price came
-- from ("mm"/"ttc"/"att"/...) or nil when unpriced. We cache the "unpriced"
-- verdict as false so a missing price is not re-queried on every rescan within a
-- session; the source key is memoized alongside it.
local function GetUnitPrice(itemId, itemLink)
    local cached = priceCache[itemId]
    if cached ~= nil then
        return cached or 0, cached ~= false, priceSource[itemId]
    end

    local gold, sourceKey = LibPrice.ItemLinkToPriceGold(itemLink)
    if gold and gold > 0 then
        priceCache[itemId] = gold
        priceSource[itemId] = sourceKey
        return gold, true, sourceKey
    end

    priceCache[itemId] = false
    priceSource[itemId] = nil
    return 0, false, nil
end

-- Compute a single slot's contribution WITHOUT touching the running aggregates.
-- Returns an info record { value, category, stack, priced, source } for an
-- occupied slot, or nil for an empty/unknown slot. Empty virtual slots (the
-- craft bag keeps slots around after a material is fully removed) have stack
-- size 0 and contribute nothing -- this is the GetItemId/stack guard the user
-- called out.
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
    local unitPrice, wasPriced, sourceKey = GetUnitPrice(itemId, itemLink)
    return {
        value = unitPrice * stack,
        category = ResolveCategory(itemLink),
        stack = stack,
        priced = wasPriced,
        source = sourceKey,
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
        stat.slots = stat.slots - 1
        stat.items = stat.items - info.stack
        if not info.priced then
            stat.unpricedSlots = stat.unpricedSlots - 1
        end
        if stat.slots <= 0 then
            categoryStats[info.category] = nil
        end
    end

    grandGold = grandGold - info.value
    grandSlots = grandSlots - 1
    grandItems = grandItems - info.stack
    if not info.priced then
        grandUnpricedSlots = grandUnpricedSlots - 1
    end

    -- Drop this slot from the per-source tally so the footer's "Prices: X"
    -- reflects only currently-occupied priced slots.
    if info.source then
        local count = sourceCounts[info.source]
        if count then
            count = count - 1
            sourceCounts[info.source] = count > 0 and count or nil
        end
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
    stat.slots = stat.slots + 1
    stat.items = stat.items + info.stack
    if not info.priced then
        stat.unpricedSlots = stat.unpricedSlots + 1
    end

    grandGold = grandGold + info.value
    grandSlots = grandSlots + 1
    grandItems = grandItems + info.stack
    if not info.priced then
        grandUnpricedSlots = grandUnpricedSlots + 1
    end

    if info.source then
        sourceCounts[info.source] = (sourceCounts[info.source] or 0) + 1
    end
end

local function ResetAggregates()
    ZO_ClearTable(slotInfo)
    ZO_ClearTable(categoryStats)
    ZO_ClearTable(sourceCounts)
    grandGold = 0
    grandSlots = 0
    grandItems = 0
    grandUnpricedSlots = 0
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

    -- "Since last visit" delta, computed once per open so incremental updates
    -- during the visit don't move it under the user. The baseline depends on the
    -- configured mode; in both, the gold delta is gated on the item count
    -- changing so a pure price drift (restart + reimport, same stock) shows
    -- nothing rather than a misleading "+2M".
    local sv = private.savedVars
    local mode = (sv and sv.deltaMode) or "visit"

    if mode == "session" then
        -- Compare against the first open of this session; baseline lives in
        -- memory and resets on reloadui/logout. Establish it on first open.
        if sessionBaseGold ~= nil and sessionBaseItems ~= nil and sessionBaseItems ~= grandItems then
            deltaSinceLastVisit = grandGold - sessionBaseGold
        else
            deltaSinceLastVisit = nil
        end
        if sessionBaseGold == nil then
            sessionBaseGold = grandGold
            sessionBaseItems = grandItems
        end
    elseif sv then
        -- Visit mode: compare against the previous open, then advance the
        -- persisted baseline so the next visit measures from here.
        local previousGold = sv.lastVisitGold
        local previousItems = sv.lastVisitItems
        if previousGold ~= nil and previousItems ~= nil and previousItems ~= grandItems then
            deltaSinceLastVisit = grandGold - previousGold
        else
            deltaSinceLastVisit = nil
        end
        sv.lastVisitGold = grandGold
        sv.lastVisitItems = grandItems
    else
        deltaSinceLastVisit = nil
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

-- The price source covering the most priced slots, as a display name, plus a
-- flag for whether more than one source contributed. Lets the footer read
-- "Prices: Master Merchant" (or "... (+others)") so the user knows where the
-- figures came from. Returns nil when nothing is priced.
local function GetDominantSource()
    local bestKey, bestCount = nil, 0
    local distinct = 0
    for sourceKey, count in pairs(sourceCounts) do
        distinct = distinct + 1
        if count > bestCount then
            bestKey, bestCount = sourceKey, count
        end
    end
    if not bestKey then
        return nil, nil, false
    end
    return SourceDisplayName(bestKey), SourceShortName(bestKey), distinct > 1
end

-- Snapshot consumed by the window. Returns a single table so the window does one
-- call and reads a stable view:
--   {
--     gold, slots, stacks, items, unpricedSlots,  -- bag-wide rollup
--     delta,                                       -- gold change since last visit (or nil)
--     sourceName, sourceHasOthers,                 -- dominant price source for the footer
--     lastScanTimeMs,                              -- when the data was last computed
--     categories = { { id, name, gold, slots, stacks, items, unpricedSlots }, ... }
--   }
-- `slots` is occupied craft-bag slots (distinct materials); `stacks` is the
-- derived count of classic 200-item stacks (ceil(items / 200)). Category rows
-- are emitted in canonical display order, or sorted by descending value when the
-- caller passes sortByValue.
function Valuation.GetSnapshot(sortByValue)
    local categories = {}
    for index = 1, #CATEGORY_DEFINITIONS do
        local def = CATEGORY_DEFINITIONS[index]
        local stat = categoryStats[def.id]
        if stat and stat.slots > 0 then
            categories[#categories + 1] = {
                id = def.id,
                name = GetString(def.nameKey),
                gold = stat.gold,
                slots = stat.slots,
                stacks = ItemsToStacks(stat.items),
                items = stat.items,
                unpricedSlots = stat.unpricedSlots,
            }
        end
    end

    -- Optional: order categories by descending value so the biggest holdings
    -- float to the top. Stable tie-break on name keeps the order deterministic.
    if sortByValue then
        table.sort(categories, function(a, b)
            if a.gold ~= b.gold then
                return a.gold > b.gold
            end
            return a.name < b.name
        end)
    end

    local sourceName, sourceShort, sourceHasOthers = GetDominantSource()

    return {
        gold = grandGold,
        slots = grandSlots,
        stacks = ItemsToStacks(grandItems),
        items = grandItems,
        unpricedSlots = grandUnpricedSlots,
        delta = deltaSinceLastVisit,
        deltaMode = (private.savedVars and private.savedVars.deltaMode) or "visit",
        sourceName = sourceName,
        sourceShort = sourceShort,
        sourceHasOthers = sourceHasOthers,
        lastScanTimeMs = lastScanTimeMs,
        categories = categories,
    }
end

function Valuation.GetStatus()
    return grandGold, grandSlots - grandUnpricedSlots, grandUnpricedSlots
end

private.GetValuationSnapshot = Valuation.GetSnapshot
