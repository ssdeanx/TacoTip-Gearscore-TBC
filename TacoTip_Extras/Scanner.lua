local _, namespace = ...

if type(namespace) ~= "table"
    or type(namespace.Scoring) ~= "table"
    or type(namespace.Cache) ~= "table" then
    return
end

local Scoring = namespace.Scoring
local Cache = namespace.Cache
local Scanner = {}
namespace.Scanner = Scanner

local REQUIRED_SLOTS = {
    1, 2, 3, 5, 6, 7, 8, 9, 10,
    11, 12, 13, 14, 15, 16, 17, 18,
}

local SOCKET_PREFIX = "EMPTY_SOCKET_"
local ITEM_CLASS_WEAPON = 2
local WEAPON_SUBCLASS_MAX = 20
local SCOPE_CAPABLE_WEAPON_SUBCLASSES = {
    [2] = true,
    [3] = true,
    [18] = true,
}
local generation = 0
local initialized = false
local pendingItems = {}
local listeners = {}
local currentState = { status = "idle", generation = 0 }
local inspector
local remoteGeneration = 0
local remoteContexts = {}

local function complete(value)
    return { status = "complete", value = value }
end

local function blocked(status, reason)
    return { status = status, reason = reason }
end

local function isFiniteNumber(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function isNonnegativeInteger(value)
    return isFiniteNumber(value) and value >= 0 and value % 1 == 0
end

local function isPositiveInteger(value)
    return isNonnegativeInteger(value) and value > 0
end

local function transition(nextState)
    local pendingItemCount = 0
    for _ in pairs(pendingItems) do
        pendingItemCount = pendingItemCount + 1
    end
    nextState.pendingItemCount = pendingItemCount
    currentState = nextState
    for listener in pairs(listeners) do
        pcall(listener, nextState)
    end
end

local function requestItemData(
    itemID,
    targetGeneration,
    priorPending,
    nextPending
)
    if nextPending[itemID] == targetGeneration then
        return
    end
    nextPending[itemID] = targetGeneration
    if priorPending[itemID] == targetGeneration then
        return
    end

    if type(C_Item) == "table"
        and type(C_Item.RequestLoadItemDataByID) == "function" then
        pcall(C_Item.RequestLoadItemDataByID, itemID)
    end
end

local function capturePlayerIdentity()
    if type(UnitExists) ~= "function"
        or type(UnitIsPlayer) ~= "function"
        or type(UnitGUID) ~= "function"
        or not UnitExists("player")
        or not UnitIsPlayer("player") then
        return nil, "player-validation-failed"
    end

    local guid = UnitGUID("player")
    if type(guid) ~= "string" or guid == "" then
        return nil, "player-guid-unavailable"
    end
    return guid
end

local function capturePlayerCells(unit)
    local classToken
    if type(UnitClass) == "function" then
        local _, token = UnitClass(unit)
        classToken = token
    end

    local level
    if type(UnitLevel) == "function" then
        level = UnitLevel(unit)
    end

    local classCell = blocked("unavailable", "player-class-unavailable")
    if type(classToken) == "string" and classToken ~= "" then
        classCell = complete(classToken)
    end

    local levelCell = blocked("unavailable", "player-level-unavailable")
    if isNonnegativeInteger(level) then
        levelCell = complete(level)
    end
    return classCell, levelCell
end

local function captureTemporaryEffects()
    local unavailable = blocked("unavailable", "temporary-weapon-state-unavailable")
    if type(GetWeaponEnchantInfo) ~= "function" then
        return unavailable, unavailable
    end

    local ok, mainHas, _, _, _, offHas =
        pcall(GetWeaponEnchantInfo)
    if not ok then
        return unavailable, unavailable
    end

    local mainCell = unavailable
    local offCell = unavailable
    if type(mainHas) == "boolean" then
        mainCell = complete(mainHas)
    end
    if type(offHas) == "boolean" then
        offCell = complete(offHas)
    end
    return mainCell, offCell
end

local function readSocketCapacity(nativeLink)
    -- GetItemStats is a MAINLINE-FAMILY API, present on Retail and WoW
    -- Forever and absent from the three Classic clients (it is documented in
    -- Blizzard_APIDocumentationGenerated/ItemDocumentation.lua on origin/live
    -- and origin/forever, and appears nowhere in the Interface tree of
    -- classic_era, classic_anniversary or classic_titan). Feature-detected, so
    -- the Classic clients take the degraded path rather than a wrong number.
    local getItemStats = _G.GetItemStats
    if type(getItemStats) ~= "function" then
        return nil, "socket-capability-unavailable"
    end

    local supplied = {}
    -- NOTE: the second argument matters. GetItemStats(link) without it reports
    -- ONLY the filled sockets on some clients and errors on others; passing an
    -- empty table asks for the full stat set including EMPTY_SOCKET_*.
    local ok, returned = pcall(getItemStats, nativeLink, supplied)
    if not ok then
        return nil, "socket-capacity-unavailable"
    end

    if type(returned) ~= "table" then
        return nil, "socket-capacity-unavailable"
    end
    local stats = returned

    local capacity = 0
    for key, value in pairs(stats) do
        if type(key) == "string"
            and string.sub(key, 1, string.len(SOCKET_PREFIX)) == SOCKET_PREFIX then
            if not isNonnegativeInteger(value) then
                return nil, "socket-capacity-invalid"
            end
            capacity = capacity + value
        end
    end

    if not isNonnegativeInteger(capacity) then
        return nil, "socket-capacity-invalid"
    end
    return capacity
end

local function buildSocketCell(nativeLink, parsed)
    local capacity, reason = readSocketCapacity(nativeLink)
    if capacity == nil then
        return blocked("unavailable", reason)
    end
    if capacity > 3 then
        return blocked("unavailable", "socket-order-unverified-above-three")
    end

    local gemIDs = {}
    for index = 1, capacity do
        gemIDs[index] = parsed.gemIDs[index]
    end
    return complete({ capacity = capacity, gemIDs = gemIDs })
end

local function unavailableMetadata(reason)
    local status = "unavailable"
    return blocked(status, reason), blocked(status, reason), blocked(status, reason),
        blocked(status, reason), blocked(status, reason), blocked(status, reason)
end

local function readMetadata(
    itemID,
    nativeLink,
    targetGeneration,
    priorPending,
    nextPending
)
    if type(C_Item) ~= "table"
        or type(C_Item.GetItemInfo) ~= "function"
        or type(C_Item.GetDetailedItemLevelInfo) ~= "function"
        or type(C_Item.IsItemDataCachedByID) ~= "function" then
        return unavailableMetadata("item-metadata-api-unavailable")
    end

    local cacheOK, cached = pcall(C_Item.IsItemDataCachedByID, itemID)
    if not cacheOK then
        return unavailableMetadata("item-cache-state-unavailable")
    end
    if cached ~= true then
        requestItemData(itemID, targetGeneration, priorPending, nextPending)
        return nil, nil, nil, nil, nil, nil, true
    end

    -- INDEX LAYOUT, and it differs between the two tables below by exactly one.
    --
    -- `{ pcall(f, x) }` builds a table whose element 1 is pcall's success flag,
    -- so everything below is shifted one place right: info[4] is itemQuality,
    -- info[5] itemLevel, info[10] itemEquipLoc, info[13] classID, info[14]
    -- subclassID. That shift is correct for this function's own reads.
    --
    -- TT_GS:GetItemScoreFromInfo does NOT want that table. It indexes the raw
    -- result directly -- scoreFromItemValues(info[2], info[3], info[4], info[9])
    -- for link, quality, level and equipLoc -- so handing it the shifted table
    -- would feed it itemLink for the link field and itemEquipLoc's neighbour for
    -- the equip slot, and every score would come back 0.
    --
    -- So the unshifted result is built separately and carried alongside. The
    -- indices below are the documented C_Item.GetItemInfo return order
    -- (Blizzard_APIDocumentationGenerated/ItemDocumentation.lua):
    --   1 itemName  2 itemLink  3 itemQuality  4 itemLevel  5 itemMinLevel
    --   6 itemType  7 itemSubType  8 itemStackCount  9 itemEquipLoc
    --   10 itemIcon  11 sellPrice  12 classID  13 subclassID
    local info = { pcall(C_Item.GetItemInfo, nativeLink) }
    local detailOK, effectiveItemLevel = pcall(C_Item.GetDetailedItemLevelInfo, nativeLink)
    if not info[1] or not detailOK then
        return unavailableMetadata("item-metadata-read-failed")
    end

    local rawInfo = {}
    for index = 2, #info do
        rawInfo[index - 1] = info[index]
    end

    local quality = info[4]
    local scoringItemLevel = info[5]
    local equipLoc = info[10]
    local itemClassID = info[13]
    local itemSubclassID = info[14]
    if not isNonnegativeInteger(quality)
        or not isFiniteNumber(scoringItemLevel)
        or scoringItemLevel < 0
        or not isFiniteNumber(effectiveItemLevel)
        or effectiveItemLevel < 0
        or type(equipLoc) ~= "string"
        or equipLoc == "" then
        requestItemData(itemID, targetGeneration, priorPending, nextPending)
        return nil, nil, nil, nil, nil, nil, true
    end

    local classCell = blocked("unavailable", "item-class-unavailable")
    if isNonnegativeInteger(itemClassID) then
        classCell = complete(itemClassID)
    end
    local subclassCell = blocked("unavailable", "item-subclass-unavailable")
    if isNonnegativeInteger(itemSubclassID) then
        subclassCell = complete(itemSubclassID)
    end

    -- The unshifted GetItemInfo result travels with the slot so Scoring can hand
    -- it to TT_GS:GetItemScoreFromInfo. That entry point performs no GetItemInfo
    -- call of its own; going through TT_GS:GetItemScore instead would cost one
    -- redundant lookup per item, i.e. 17 per re-scan, on a path that runs on
    -- every equipment change.
    return complete(quality), complete(scoringItemLevel),
        complete(effectiveItemLevel), complete(equipLoc), classCell, subclassCell,
        false, rawInfo
end

local function scopeCapabilityCell(equipLoc, itemClassID, itemSubclassID)
    if type(equipLoc) ~= "table" or equipLoc.status ~= "complete" then
        return blocked("unavailable", "ranged-subtype-unverified")
    end
    if equipLoc.value ~= "INVTYPE_RANGED"
        and equipLoc.value ~= "INVTYPE_RANGEDRIGHT" then
        return complete(false)
    end
    if type(itemClassID) ~= "table"
        or itemClassID.status ~= "complete"
        or itemClassID.value ~= ITEM_CLASS_WEAPON
        or type(itemSubclassID) ~= "table"
        or itemSubclassID.status ~= "complete"
        or not isNonnegativeInteger(itemSubclassID.value)
        or itemSubclassID.value > WEAPON_SUBCLASS_MAX then
        return blocked("unavailable", "ranged-subtype-unverified")
    end
    if SCOPE_CAPABLE_WEAPON_SUBCLASSES[itemSubclassID.value] then
        return complete(true)
    end
    if itemSubclassID.value == 19 then
        return complete(false)
    end
    return blocked("unavailable", "ranged-subtype-unverified")
end

local function temporaryCellForSlot(slotID, mainTemporary, offTemporary)
    if slotID == 16 then
        return mainTemporary
    end
    if slotID == 17 then
        return offTemporary
    end
    return blocked("unavailable", "temporary-weapon-slot-not-applicable")
end

local function buildOccupiedSlot(
    _slotID,
    itemID,
    nativeLink,
    parsed,
    temporaryWeaponEffect,
    targetGeneration,
    priorPending,
    nextPending
)
    local quality, scoringItemLevel, effectiveItemLevel, equipLoc,
        itemClassID, itemSubclassID, isPending, itemInfo =
        readMetadata(
            itemID,
            nativeLink,
            targetGeneration,
            priorPending,
            nextPending
        )

    if isPending then
        return nil, true
    end

    return {
        state = "occupied",
        itemID = complete(itemID),
        nativeLink = complete(nativeLink),
        quality = quality,
        scoringItemLevel = scoringItemLevel,
        effectiveItemLevel = effectiveItemLevel,
        equipLoc = equipLoc,
        itemClassID = itemClassID,
        itemSubclassID = itemSubclassID,
        itemInfoValue = itemInfo,
        permanentEnchantID = complete(parsed.permanentEnchantID),
        scoreGemIDs = complete({
            parsed.gemIDs[1], parsed.gemIDs[2], parsed.gemIDs[3],
        }),
        sockets = buildSocketCell(nativeLink, parsed),
        temporaryWeaponEffect = temporaryWeaponEffect,
        scopeCapablePhysicalRanged = scopeCapabilityCell(
            equipLoc,
            itemClassID,
            itemSubclassID
        ),
    }, false
end

local function captureSlot(
    unit,
    slotID,
    temporaryWeaponEffect,
    targetGeneration,
    priorPending,
    nextPending
)
    local rawItemID = GetInventoryItemID(unit, slotID)
    local nativeLink = GetInventoryItemLink(unit, slotID)

    local effectiveItemID = isPositiveInteger(rawItemID) and rawItemID or nil
    if effectiveItemID == nil and type(nativeLink) == "string" then
        local extracted = string.match(nativeLink, "item:(%d+)")
        local parsedID = extracted and tonumber(extracted) or nil
        if isPositiveInteger(parsedID) then
            effectiveItemID = parsedID
        end
    end

    if effectiveItemID == nil and nativeLink == nil then
        return { state = "confirmed-empty" }, false
    end
    if isPositiveInteger(effectiveItemID) and nativeLink == nil then
        requestItemData(effectiveItemID, targetGeneration, priorPending, nextPending)
        return nil, true
    end
    if not isPositiveInteger(effectiveItemID) or type(nativeLink) ~= "string" then
        return nil, false, "inventory-id-link-contradiction"
    end

    local parsed, parseReason = Scoring.ParseEquippedLink(nativeLink, effectiveItemID)
    if not parsed then
        return nil, false, parseReason or "invalid-native-link"
    end

    local occupied, isPending = buildOccupiedSlot(
        slotID,
        effectiveItemID,
        nativeLink,
        parsed,
        temporaryWeaponEffect,
        targetGeneration,
        priorPending,
        nextPending
    )
    return occupied, isPending
end

local function capture(targetGeneration)
    if targetGeneration ~= generation then
        return
    end

    local startingGUID, identityReason = capturePlayerIdentity()
    if not startingGUID then
        pendingItems = {}
        transition({
            status = "unavailable",
            generation = targetGeneration,
            reason = identityReason,
        })
        return
    end

    local classToken, level = capturePlayerCells("player")
    local mainTemporary, offTemporary = captureTemporaryEffects()
    local priorPending = pendingItems
    local nextPending = {}
    local slots = {}
    local hasPending = false

    for _, slotID in ipairs(REQUIRED_SLOTS) do
        local slot, slotPending, fatalReason = captureSlot(
            "player",
            slotID,
            temporaryCellForSlot(slotID, mainTemporary, offTemporary),
            targetGeneration,
            priorPending,
            nextPending
        )
        if fatalReason then
            pendingItems = {}
            transition({
                status = "unavailable",
                generation = targetGeneration,
                reason = fatalReason,
            })
            return
        end
        if slotPending then
            hasPending = true
        else
            slots[slotID] = slot
        end
    end

    if targetGeneration ~= generation then
        return
    end

    local endingGUID = capturePlayerIdentity()
    if endingGUID ~= startingGUID then
        pendingItems = {}
        transition({
            status = "unavailable",
            generation = targetGeneration,
            reason = "player-identity-changed",
        })
        return
    end

    pendingItems = nextPending
    if hasPending then
        transition({
            status = "pending",
            generation = targetGeneration,
            reason = "item-data-pending",
        })
        return
    end

    local revision = {
        classToken = classToken,
        level = level,
        socketCapability = complete(type(GetItemStats) == "function"),
        slots = slots,
    }
    local result = Scoring.Evaluate(revision)

    if targetGeneration ~= generation then
        return
    end

    pendingItems = {}
    transition({
        status = "complete",
        generation = targetGeneration,
        revision = revision,
        result = result,
    })
end

local function isRemotePlayerGUID(guid)
    if type(guid) ~= "string"
        or not string.match(guid, "^Player%-%d+%-%x+$") then
        return false
    end

    if type(GUIDIsPlayer) == "function" then
        local ok, isPlayer = pcall(GUIDIsPlayer, guid)
        if not ok or not isPlayer then
            return false
        end
    end
    return true
end

local function unitMatchesRemoteGUID(unit, guid)
    if type(unit) ~= "string"
        or unit == ""
        or type(UnitExists) ~= "function"
        or type(UnitIsPlayer) ~= "function"
        or type(UnitGUID) ~= "function" then
        return false
    end

    local existsOK, exists = pcall(UnitExists, unit)
    local playerOK, isPlayer = pcall(UnitIsPlayer, unit)
    local guidOK, unitGUID = pcall(UnitGUID, unit)
    if not existsOK or not exists
        or not playerOK or not isPlayer
        or not guidOK or unitGUID ~= guid then
        return false
    end

    local localOK, localGUID = pcall(UnitGUID, "player")
    return not localOK or localGUID ~= guid
end

local function resolveRemoteUnit(guid, callbackUnit)
    if unitMatchesRemoteGUID(callbackUnit, guid) then
        return callbackUnit
    end

    local inspectFrame = _G.InspectFrame
    if type(inspectFrame) == "table"
        and unitMatchesRemoteGUID(inspectFrame.unit, guid) then
        return inspectFrame.unit
    end

    if type(inspector) ~= "table"
        or type(inspector.PlayerGUIDToUnitToken) ~= "function" then
        return nil
    end

    local ok, resolved = pcall(
        inspector.PlayerGUIDToUnitToken,
        inspector,
        guid
    )
    if ok and unitMatchesRemoteGUID(resolved, guid) then
        return resolved
    end
    return nil
end

local function remoteContextIsCurrent(context)
    return remoteContexts[context.guid] == context
        and Cache.IsCurrentGeneration(context.guid, context.generation)
end

local function failRemote(context, reason)
    if not remoteContextIsCurrent(context) then
        return false
    end
    Cache.PublishUnavailable(context.guid, context.generation, reason)
    remoteContexts[context.guid] = nil
    return true
end

local function captureRemote(context)
    if not remoteContextIsCurrent(context) then
        return false
    end
    if type(GetInventoryItemID) ~= "function"
        or type(GetInventoryItemLink) ~= "function" then
        return failRemote(context, "inventory-api-unavailable")
    end

    local unit = resolveRemoteUnit(context.guid, context.unit)
    if not unit then
        return failRemote(context, "remote-unit-unavailable")
    end
    context.unit = unit

    local classToken, level = capturePlayerCells(unit)
    local priorPending = context.pendingItems
    local nextPending = {}
    local slots = {}
    local hasPending = false
    local remoteTemporary = blocked(
        "unavailable",
        "remote-temporary-weapon-state-unavailable"
    )

    for _, slotID in ipairs(REQUIRED_SLOTS) do
        local callOK, slot, slotPending, fatalReason = pcall(
            captureSlot,
            unit,
            slotID,
            remoteTemporary,
            context.generation,
            priorPending,
            nextPending
        )
        if not callOK then
            return failRemote(context, "inventory-read-failed")
        end
        if fatalReason then
            return failRemote(context, fatalReason)
        end
        if slotPending then
            hasPending = true
        else
            slots[slotID] = slot
        end
    end

    if not remoteContextIsCurrent(context) then
        return false
    end
    if not unitMatchesRemoteGUID(unit, context.guid) then
        return failRemote(context, "remote-identity-changed")
    end

    context.pendingItems = nextPending
    if hasPending then
        Cache.SetPending(
            context.guid,
            context.generation,
            nextPending,
            "item-data-pending"
        )
        return true
    end

    local revision = {
        classToken = classToken,
        level = level,
        socketCapability = complete(type(GetItemStats) == "function"),
        slots = slots,
    }
    local result = Scoring.Evaluate(revision)

    if not remoteContextIsCurrent(context)
        or not unitMatchesRemoteGUID(unit, context.guid) then
        return failRemote(context, "remote-identity-changed")
    end

    local published = Cache.PublishComplete(
        context.guid,
        context.generation,
        revision,
        result
    )
    if published then
        remoteContexts[context.guid] = nil
    end
    return published
end

local function handleRemoteItemDataLoad(itemID, succeeded)
    local matchingGUIDs = {}
    for guid, context in pairs(remoteContexts) do
        if context.pendingItems[itemID] == context.generation
            and remoteContextIsCurrent(context) then
            matchingGUIDs[#matchingGUIDs + 1] = guid
        end
    end
    table.sort(matchingGUIDs)

    local handled = false
    for _, guid in ipairs(matchingGUIDs) do
        local context = remoteContexts[guid]
        if context
            and context.pendingItems[itemID] == context.generation
            and remoteContextIsCurrent(context) then
            handled = true
            if succeeded == false then
                failRemote(context, "item-data-load-failed")
            else
                context.pendingItems[itemID] = nil
                captureRemote(context)
            end
        end
    end
    return handled
end

function Scanner.Initialize(activeInspector)
    initialized = true
    if type(activeInspector) == "table" then
        inspector = activeInspector
    end
end

function Scanner.HandleInventoryReady(event, guid, isInspect, unit)
    if not initialized
        or event ~= "INVENTORY_READY"
        or (isInspect ~= nil and isInspect ~= true)
        or not isRemotePlayerGUID(guid) then
        return false
    end

    local resolved = resolveRemoteUnit(guid, unit)
    if not resolved then
        return false
    end

    remoteGeneration = remoteGeneration + 1
    local context = {
        guid = guid,
        generation = remoteGeneration,
        unit = resolved,
        pendingItems = {},
    }
    remoteContexts[guid] = context

    local began, evictedGUID = Cache.Begin(
        guid,
        context.generation,
        "inventory-ready"
    )
    if evictedGUID then
        remoteContexts[evictedGUID] = nil
    end
    if not began then
        remoteContexts[guid] = nil
        return false
    end

    captureRemote(context)
    return true
end

function Scanner.BeginGeneration(reason)
    generation = generation + 1
    pendingItems = {}
    transition({
        status = "pending",
        generation = generation,
        reason = reason or "scan-requested",
    })
    return generation
end

function Scanner.RunGeneration(targetGeneration)
    if not initialized or targetGeneration ~= generation then
        return false
    end
    capture(targetGeneration)
    return true
end

function Scanner.HandleItemDataLoad(itemID, succeeded)
    if not isPositiveInteger(itemID) then
        return false
    end

    local handled = false
    if pendingItems[itemID] == generation then
        handled = true
        if succeeded == false then
            pendingItems = {}
            transition({
                status = "unavailable",
                generation = generation,
                reason = "item-data-load-failed",
            })
        else
            pendingItems[itemID] = nil
            capture(generation)
        end
    end

    return handleRemoteItemDataLoad(itemID, succeeded) or handled
end

function Scanner.GetCurrent()
    return currentState
end

function Scanner.Subscribe(listener)
    if type(listener) ~= "function" then
        return false
    end
    listeners[listener] = true
    return true
end

function Scanner.Unsubscribe(listener)
    listeners[listener] = nil
end

function Scanner.GetRemote(guid)
    return Cache.Get(guid)
end

function Scanner.GetFreshRemote(guid)
    return Cache.GetFresh(guid)
end

function Scanner.SubscribeRemote(listener)
    return Cache.Subscribe(listener)
end

function Scanner.UnsubscribeRemote(listener)
    Cache.Unsubscribe(listener)
end
