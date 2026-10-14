local addonName, namespace = ...

if type(namespace) ~= "table" then
    return
end

local Core = {}
namespace.Core = Core

local REQUIRED_SLOTS = {
    1, 2, 3, 5, 6, 7, 8, 9, 10,
    11, 12, 13, 14, 15, 16, 17, 18,
}

local DEBUG_PREFIX = "[TTGSE DEV]"
local eventFrame = CreateFrame("Frame")
local initialized = false
local scheduledGeneration
local database
local futureDatabaseSchema = false
local DEFAULT_MINIMAP_ANGLE = 225
local MAX_EQUIPMENT_POSITION_OFFSET = 4096
local WELCOME_DELAY_SECONDS = 3.1
local welcomeScheduled = false
local welcomePrinted = false

local WELCOME_NAME = "|cffd4a84bTacoTip|r |cffbcc3ccGS|r |cff9a76d2Enhancer|r"
local WELCOME_CREDIT = "|cffbcc3ccv%s - NS|r"
local WELCOME_PUN = "|cffd4a84bMay your upgrades be spicy!|r"

local VALID_TOOLTIP_MODES = {
    Disabled = true,
    Minimal = true,
    Compact = true,
    Detailed = true,
}

local VALID_EQUIPMENT_DISPLAY_MODES = {
    Disabled = true,
    Basic = true,
    Detailed = true,
}

local function defaultBoolean(target, key, value)
    if type(target[key]) ~= "boolean" then
        target[key] = value
    end
end

local function isFiniteNumber(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function copyTable(value, seen)
    if type(value) ~= "table" then
        return value
    end
    seen = seen or {}
    if seen[value] then
        return seen[value]
    end
    local result = {}
    seen[value] = result
    for key, entry in pairs(value) do
        result[copyTable(key, seen)] = copyTable(entry, seen)
    end
    return result
end

local function normalizeEquipmentPosition(value)
    if type(value) ~= "table"
        or not isFiniteNumber(value.x)
        or not isFiniteNumber(value.y)
        or math.abs(value.x) > MAX_EQUIPMENT_POSITION_OFFSET
        or math.abs(value.y) > MAX_EQUIPMENT_POSITION_OFFSET then
        return nil
    end
    return {
        x = value.x,
        y = value.y,
    }
end

local function setFreshEquipmentDisplayDefaults(runtime)
    runtime.equipmentDisplay = {
        mode = "Basic",
        showUnenhanced = false,
        locked = true,
    }
end

local function setMigratedEquipmentDisplayDefaults(runtime)
    runtime.equipmentDisplay = {
        mode = "Disabled",
        showUnenhanced = false,
        locked = true,
    }
end

function Core.GetVersion()
    local addOns = _G.C_AddOns
    if type(addOns) ~= "table"
        or type(addOns.GetAddOnMetadata) ~= "function" then
        return nil
    end
    local ok, value = pcall(
        addOns.GetAddOnMetadata,
        addonName,
        "Version"
    )
    if ok
        and type(value) == "string"
        and string.match(value, "^%d+%.%d+%.%d+$") then
        return value
    end
    return nil
end

local function welcomeCompatibilityValid()
    local adapter = namespace.TacoTipAdapter
    if type(adapter) ~= "table"
        or type(adapter.GetCompatibility) ~= "function" then
        return false
    end
    local compatibilityOK, supported = pcall(adapter.GetCompatibility)
    if not compatibilityOK or supported ~= true then
        return false
    end
    if type(adapter.GetInternalReason) == "function" then
        local reasonOK, reason = pcall(adapter.GetInternalReason)
        if not reasonOK or (type(reason) == "string" and reason ~= "") then
            return false
        end
    end
    return true
end

local function scheduleOneShot(delay, callback)
    local timer = _G.C_Timer
    if not isFiniteNumber(delay)
        or delay < 0
        or type(callback) ~= "function"
        or type(timer) ~= "table"
        or type(timer.After) ~= "function" then
        return false
    end
    return pcall(timer.After, delay, callback)
end

local function scheduleWelcome(runtimeSettings, initializationSucceeded)
    if welcomeScheduled
        or initializationSucceeded ~= true
        or type(runtimeSettings) ~= "table"
        or runtimeSettings.enabled ~= true then
        return false
    end

    welcomeScheduled = true
    local scheduledOK = scheduleOneShot(WELCOME_DELAY_SECONDS, function()
        if welcomePrinted
            or runtimeSettings.enabled ~= true
            or not welcomeCompatibilityValid() then
            return
        end
        local chat = _G.DEFAULT_CHAT_FRAME
        if type(chat) ~= "table" or type(chat.AddMessage) ~= "function" then
            return
        end
        local version = Core.GetVersion()
        if not version then
            return
        end
        local message = WELCOME_NAME .. " "
            .. string.format(WELCOME_CREDIT, version)
            .. " loaded. " .. WELCOME_PUN
        welcomePrinted = true
        pcall(chat.AddMessage, chat, message)
    end)
    if not scheduledOK then
        welcomeScheduled = false
    end
    return scheduledOK
end

local function normalizeSettings(runtime)
    defaultBoolean(runtime, "enabled", true)
    if type(runtime.tooltip) ~= "table" then
        runtime.tooltip = {}
    end

    local tooltipSettings = runtime.tooltip
    if not VALID_TOOLTIP_MODES[tooltipSettings.mode] then
        tooltipSettings.mode = "Compact"
    end
    defaultBoolean(tooltipSettings, "shiftToDetailed", true)
    defaultBoolean(
        tooltipSettings,
        "restrictEnhancementMetricsToLevel70",
        true
    )
    defaultBoolean(tooltipSettings, "warningColors", true)
    if type(tooltipSettings.fields) ~= "table" then
        tooltipSettings.fields = {}
    end

    local fields = tooltipSettings.fields
    defaultBoolean(fields, "gearScore", true)
    defaultBoolean(fields, "baseGS", false)
    defaultBoolean(fields, "potentialGS", true)
    defaultBoolean(fields, "delta", true)
    defaultBoolean(fields, "averageItemLevel", true)
    defaultBoolean(fields, "completion", true)
    if not fields.gearScore
        and not fields.baseGS
        and not fields.potentialGS
        and not fields.delta
        and not fields.averageItemLevel
        and not fields.completion then
        tooltipSettings.mode = "Disabled"
    end

    if type(runtime.minimap) ~= "table" then
        runtime.minimap = {}
    end
    defaultBoolean(runtime.minimap, "show", true)
    if not isFiniteNumber(runtime.minimap.angle) then
        runtime.minimap.angle = DEFAULT_MINIMAP_ANGLE
    else
        runtime.minimap.angle = runtime.minimap.angle % 360
    end

    local equipmentSource = type(runtime.equipmentDisplay) == "table"
        and runtime.equipmentDisplay
        or {}
    local showUnenhanced = false
    if type(equipmentSource.showUnenhanced) == "boolean" then
        showUnenhanced = equipmentSource.showUnenhanced
    end
    local locked = true
    if type(equipmentSource.locked) == "boolean" then
        locked = equipmentSource.locked
    end
    local equipmentDisplay = {
        mode = VALID_EQUIPMENT_DISPLAY_MODES[equipmentSource.mode]
            and equipmentSource.mode
            or "Disabled",
        showUnenhanced = showUnenhanced,
        locked = locked,
        characterPosition = normalizeEquipmentPosition(
            equipmentSource.characterPosition
        ),
        inspectPosition = normalizeEquipmentPosition(
            equipmentSource.inspectPosition
        ),
    }

    if futureDatabaseSchema then
        equipmentDisplay.mode = "Disabled"
    end
    runtime.equipmentDisplay = equipmentDisplay

    return runtime
end

local function initializeDatabase()
    local persistedRoot = _G.TacoTipGearScoreEnhancerDB
    local freshDatabase = type(persistedRoot) ~= "table"
        or next(persistedRoot) == nil

    futureDatabaseSchema = type(persistedRoot) == "table"
        and type(persistedRoot.schema) == "number"
        and persistedRoot.schema > 2

    if futureDatabaseSchema then
        local runtimeRoot = copyTable(persistedRoot)
        if type(runtimeRoot.settings) ~= "table" then
            runtimeRoot.settings = {}
        end
        normalizeSettings(runtimeRoot.settings)
        runtimeRoot.settings.equipmentDisplay.mode = "Disabled"
        database = runtimeRoot
        return runtimeRoot
    end

    local root = persistedRoot
    if freshDatabase then
        root = {}
        _G.TacoTipGearScoreEnhancerDB = root
    end
    if type(root.settings) ~= "table" then
        root.settings = {}
    end

    if freshDatabase then
        setFreshEquipmentDisplayDefaults(root.settings)
    elseif root.schema == 1 then
        setMigratedEquipmentDisplayDefaults(root.settings)
    elseif root.schema ~= 2
        or type(root.settings.equipmentDisplay) ~= "table" then
        setMigratedEquipmentDisplayDefaults(root.settings)
    end

    root.schema = 2
    normalizeSettings(root.settings)
    database = root
    return root
end

function Core.GetSettings()
    local root = database or initializeDatabase()
    return root.settings
end

function Core.ApplySettings()
    local runtime = normalizeSettings(Core.GetSettings())
    if namespace.Tooltips and type(namespace.Tooltips.ApplySettings) == "function" then
        namespace.Tooltips.ApplySettings()
    end
    if namespace.Minimap and type(namespace.Minimap.ApplySettings) == "function" then
        namespace.Minimap.ApplySettings()
    end
    if namespace.Frames and type(namespace.Frames.ApplySettings) == "function" then
        namespace.Frames.ApplySettings()
    end
    if namespace.Options and type(namespace.Options.Refresh) == "function" then
        namespace.Options.Refresh()
    end
    return runtime
end

function Core.ApplyEquipmentSettings()
    local runtime = normalizeSettings(Core.GetSettings())
    if namespace.Frames and type(namespace.Frames.ApplySettings) == "function" then
        namespace.Frames.ApplySettings()
    end
    if namespace.Options and type(namespace.Options.Refresh) == "function" then
        namespace.Options.Refresh()
    end
    return runtime.equipmentDisplay
end

function Core.ResetSettings()
    local runtime = Core.GetSettings()
    for key in pairs(runtime) do
        runtime[key] = nil
    end
    setFreshEquipmentDisplayDefaults(runtime)
    normalizeSettings(runtime)
    if namespace.Frames and type(namespace.Frames.ResetPositions) == "function" then
        namespace.Frames.ResetPositions()
    end
    Core.ApplySettings()
    return runtime
end

function Core.ResetEquipmentPositions()
    local runtime = Core.GetSettings()
    local equipmentDisplay = type(runtime) == "table"
        and runtime.equipmentDisplay
        or nil
    if type(equipmentDisplay) ~= "table" then
        return false
    end
    equipmentDisplay.characterPosition = nil
    equipmentDisplay.inspectPosition = nil
    if namespace.Frames and type(namespace.Frames.ResetPositions) == "function" then
        namespace.Frames.ResetPositions()
    end
    Core.ApplyEquipmentSettings()
    return true
end

function Core.RestoreTacoTipSettings()
    local runtime = Core.GetSettings()
    runtime.tooltip.mode = "Disabled"
    if namespace.Tooltips and type(namespace.Tooltips.ApplySettings) == "function" then
        namespace.Tooltips.ApplySettings()
    elseif namespace.TacoTipAdapter
        and type(namespace.TacoTipAdapter.SetTooltipSurfaceEnabled) == "function" then
        namespace.TacoTipAdapter.SetTooltipSurfaceEnabled(false)
    end
    if namespace.Options and type(namespace.Options.Refresh) == "function" then
        namespace.Options.Refresh()
    end
    return namespace.TacoTipAdapter
        and type(namespace.TacoTipAdapter.IsTooltipSurfaceActive) == "function"
        and not namespace.TacoTipAdapter.IsTooltipSurfaceActive()
end

local function onInventoryReady(event, guid, isInspect, unit)
    if namespace.Scanner
        and type(namespace.Scanner.HandleInventoryReady) == "function" then
        return namespace.Scanner.HandleInventoryReady(
            event,
            guid,
            isInspect,
            unit
        )
    end
end

local function addChatLine(message)
    if DEFAULT_CHAT_FRAME and type(DEFAULT_CHAT_FRAME.AddMessage) == "function" then
        DEFAULT_CHAT_FRAME:AddMessage(DEBUG_PREFIX .. " " .. message)
    end
end

local function cellValue(cell)
    if type(cell) == "table" and cell.status == "complete" then
        return cell.value, true
    end
    return nil, false
end

local function formatNumber(value)
    if type(value) ~= "number" then
        return "unknown"
    end
    if value % 1 == 0 then
        return string.format("%d", value)
    end
    return string.format("%.2f", value)
end

local function metricText(label, metric)
    local status = type(metric) == "table" and metric.status or "unknown"
    if status == "complete" and type(metric.value) == "number" then
        return label .. "=complete:" .. formatNumber(metric.value)
    end
    return label .. "=" .. tostring(status)
end

local function rawSlot(revision, slotID)
    if type(revision) == "table" and type(revision.slots) == "table" then
        return revision.slots[slotID]
    end
    return nil
end

local function rawState(slot)
    if type(slot) == "table" and slot.state == "occupied" then
        return "occupied"
    end
    if type(slot) == "table" and slot.state == "confirmed-empty" then
        return "confirmed-empty"
    end
    return "unknown/pending"
end

local function countRawStates(revision)
    local occupied = 0
    local empty = 0
    local unknown = 0
    for _, slotID in ipairs(REQUIRED_SLOTS) do
        local state = rawState(rawSlot(revision, slotID))
        if state == "occupied" then
            occupied = occupied + 1
        elseif state == "confirmed-empty" then
            empty = empty + 1
        else
            unknown = unknown + 1
        end
    end
    return occupied, empty, unknown
end

local function permanentState(slot)
    local enchantID, known = cellValue(slot and slot.permanentEnchantID)
    if not known or type(enchantID) ~= "number" then
        return "unknown"
    end
    return enchantID > 0 and "present" or "absent"
end

local function installedGemCount(slot)
    local gemIDs, known = cellValue(slot and slot.scoreGemIDs)
    if not known or type(gemIDs) ~= "table" then
        return "unknown"
    end

    local count = 0
    for index = 1, 3 do
        if type(gemIDs[index]) == "number" and gemIDs[index] > 0 then
            count = count + 1
        end
    end
    return tostring(count)
end

local function socketCapacity(slot)
    local sockets, known = cellValue(slot and slot.sockets)
    if known and type(sockets) == "table" and type(sockets.capacity) == "number" then
        return formatNumber(sockets.capacity)
    end
    return "unknown"
end

local function temporaryState(slot)
    local active, known = cellValue(slot and slot.temporaryWeaponEffect)
    if known and type(active) == "boolean" then
        return tostring(active)
    end
    return "unknown"
end

local function weaponText(label, slot)
    local state = rawState(slot)
    if state == "confirmed-empty" then
        return label .. " item=confirmed-empty enchant=absent gems=0 sockets=0 temporary=false"
    end
    if state ~= "occupied" then
        return label .. " item=unknown enchant=unknown gems=unknown sockets=unknown temporary=unknown"
    end

    local itemID, itemKnown = cellValue(slot.itemID)
    return label
        .. " item=" .. (itemKnown and formatNumber(itemID) or "unknown")
        .. " enchant=" .. permanentState(slot)
        .. " gems=" .. installedGemCount(slot)
        .. " sockets=" .. socketCapacity(slot)
        .. " temporary=" .. temporaryState(slot)
end

local function slotText(slotID, slot)
    local state = rawState(slot)
    local line = "slot=" .. slotID .. " state=" .. state
    if state ~= "occupied" then
        return line
    end

    local itemID, itemKnown = cellValue(slot.itemID)
    local equipLoc, equipKnown = cellValue(slot.equipLoc)
    local scoringLevel, scoringKnown = cellValue(slot.scoringItemLevel)
    local effectiveLevel, effectiveKnown = cellValue(slot.effectiveItemLevel)
    return line
        .. " item=" .. (itemKnown and formatNumber(itemID) or "unknown")
        .. " equip=" .. (equipKnown and tostring(equipLoc) or "unknown")
        .. " score-ilvl=" .. (scoringKnown and formatNumber(scoringLevel) or "unknown")
        .. " avg-ilvl=" .. (effectiveKnown and formatNumber(effectiveLevel) or "unknown")
        .. " enchant=" .. permanentState(slot)
        .. " gems=" .. installedGemCount(slot)
        .. " sockets=" .. socketCapacity(slot)
end

local function completionText(metric)
    local status = type(metric) == "table" and metric.status or "unknown"
    local value = status == "complete" and metric.value or nil
    if type(value) ~= "table" then
        return "completion=" .. tostring(status)
            .. " filled=unknown total=unknown percent=unknown category=unknown"
    end

    local percent = type(value.displayPercent) == "number"
        and formatNumber(value.displayPercent) or "n/a"
    return "completion=complete"
        .. " filled=" .. formatNumber(value.filled)
        .. " total=" .. formatNumber(value.opportunities)
        .. " percent=" .. percent
        .. " category=" .. tostring(value.category or "unknown")
end

local function averageText(metric)
    local status = type(metric) == "table" and metric.status or "unknown"
    local value = status == "complete" and metric.value or nil
    if type(value) ~= "table" then
        return "Average iLvl=" .. tostring(status) .. " raw=unknown display=unknown"
    end
    local raw = type(value.raw) == "number" and string.format("%.4f", value.raw)
        or "unknown"
    return "Average iLvl=complete raw=" .. raw
        .. " display=" .. formatNumber(value.display)
end

local function printDebugSnapshot()
    local scanner = namespace.Scanner
    local state = scanner and scanner.GetCurrent and scanner.GetCurrent() or nil
    state = type(state) == "table" and state or { status = "unavailable", generation = 0 }

    local revision = state.revision
    local result = type(state.result) == "table" and state.result or nil
    local metrics = result and result.metrics or {}
    local occupied, empty, unknown = countRawStates(revision)
    local pendingCount = type(state.pendingItemCount) == "number"
        and state.pendingItemCount or 0

    addChatLine("/ttgsdebug local snapshot")
    addChatLine(
        "state=" .. tostring(state.status or "unknown")
            .. " generation=" .. tostring(state.generation or 0)
            .. " reason=" .. tostring(state.reason or "none")
            .. " occupied=" .. occupied
            .. " confirmed-empty=" .. empty
            .. " unknown/pending=" .. unknown
            .. " pending-item-ids=" .. pendingCount
    )
    addChatLine(
        metricText("Unenhanced GS", metrics.baseGS) .. " "
            .. metricText("Current GS", metrics.gearScore) .. " "
            .. metricText("Potential GS", metrics.potentialGS) .. " "
            .. metricText("Delta", metrics.delta)
    )
    addChatLine(completionText(metrics.completion) .. " "
        .. averageText(metrics.averageItemLevel))
    addChatLine(weaponText("main-hand", rawSlot(revision, 16)))
    addChatLine(weaponText("off-hand", rawSlot(revision, 17)))
    for _, slotID in ipairs(REQUIRED_SLOTS) do
        addChatLine(slotText(slotID, rawSlot(revision, slotID)))
    end
end

local function registerDebugCommand()
    if type(SlashCmdList) ~= "table" or SlashCmdList.TTGSEDEBUG ~= nil then
        return
    end
    SLASH_TTGSEDEBUG1 = "/ttgsdebug"
    SlashCmdList.TTGSEDEBUG = printDebugSnapshot
end

local function runScheduledScan(self)
    self:SetScript("OnUpdate", nil)

    local generation = scheduledGeneration
    scheduledGeneration = nil
    if generation and namespace.Scanner then
        namespace.Scanner.RunGeneration(generation)
    end
end

local function scheduleLocalScan(reason)
    local scanner = namespace.Scanner
    if scheduledGeneration
        or type(scanner) ~= "table"
        or type(scanner.BeginGeneration) ~= "function"
        or type(scanner.RunGeneration) ~= "function" then
        return false
    end

    scheduledGeneration = scanner.BeginGeneration(reason)
    if not scheduledGeneration then
        return false
    end
    eventFrame:SetScript("OnUpdate", runScheduledScan)
    return true
end

function Core.RequestLocalScan(reason)
    if type(reason) ~= "string" or reason == "" then
        reason = "equipment-window"
    end
    return scheduleLocalScan(reason)
end

function Core.ScheduleEquipmentExpiry(delay, callback)
    return scheduleOneShot(delay, callback)
end

local function initialize(self)
    if initialized or not namespace.Scanner then
        return
    end

    initialized = true
    local root = initializeDatabase()
    local adapter = namespace.TacoTipAdapter
    local adapterReady = false
    if adapter and type(adapter.Initialize) == "function" then
        adapterReady = adapter.Initialize(root) == true
    end

    local library
    if adapter and type(adapter.GetInspector) == "function" then
        library = adapter.GetInspector()
    end
    namespace.Scanner.Initialize(library)
    local callbackReady = false
    if adapter and type(adapter.RegisterInventoryReady) == "function" then
        callbackReady = adapter.RegisterInventoryReady(onInventoryReady) == true
    end
    registerDebugCommand()
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    self:RegisterEvent("UNIT_INVENTORY_CHANGED")
    self:RegisterEvent("ITEM_DATA_LOAD_RESULT")
    self:RegisterEvent("MODIFIER_STATE_CHANGED")
    self:RegisterEvent("PLAYER_LOGOUT")
    local tooltipsReady = false
    if namespace.Tooltips and type(namespace.Tooltips.Initialize) == "function" then
        tooltipsReady = namespace.Tooltips.Initialize(root.settings) ~= false
    end
    if namespace.Frames and type(namespace.Frames.Initialize) == "function" then
        namespace.Frames.Initialize(root.settings)
    end
    local optionsReady = false
    if namespace.Options and type(namespace.Options.Initialize) == "function" then
        optionsReady = namespace.Options.Initialize(root.settings) ~= false
    end
    local minimapReady = false
    if namespace.Minimap and type(namespace.Minimap.Initialize) == "function" then
        minimapReady = namespace.Minimap.Initialize(root.settings) ~= false
    end
    scheduleWelcome(
        root.settings,
        adapterReady and callbackReady
            and tooltipsReady and optionsReady and minimapReady
    )
end

local function onEvent(self, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == addonName then
            self:UnregisterEvent("ADDON_LOADED")
            initialize(self)
        end
        return
    end

    if event == "PLAYER_LOGOUT" then
        if namespace.Tooltips and type(namespace.Tooltips.Shutdown) == "function" then
            namespace.Tooltips.Shutdown()
        end
        if namespace.Frames and type(namespace.Frames.Shutdown) == "function" then
            namespace.Frames.Shutdown()
        end
        if namespace.TacoTipAdapter
            and type(namespace.TacoTipAdapter.Shutdown) == "function" then
            namespace.TacoTipAdapter.Shutdown()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        scheduleLocalScan("entering-world")
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        scheduleLocalScan("equipment-changed")
    elseif event == "UNIT_INVENTORY_CHANGED" then
        local unit = ...
        if unit == "player" then
            scheduleLocalScan("inventory-changed")
        end
    elseif event == "ITEM_DATA_LOAD_RESULT" and namespace.Scanner then
        namespace.Scanner.HandleItemDataLoad(...)
    elseif event == "MODIFIER_STATE_CHANGED"
        and namespace.Tooltips
        and type(namespace.Tooltips.HandleModifierStateChanged) == "function" then
        namespace.Tooltips.HandleModifierStateChanged(...)
    end
end

eventFrame:SetScript("OnEvent", onEvent)
eventFrame:RegisterEvent("ADDON_LOADED")
