local addonName, namespace = ...

if type(namespace) ~= "table" then
    return
end

local Adapter = {}
namespace.TacoTipAdapter = Adapter

-- ---------------------------------------------------------------------------
-- THE COMPATIBILITY CONTRACT
--
-- This file used to pin two constants and compare them for equality. Both pins
-- were measured dead ends against the only TacoTip that exists:
--
--   EXPECTED_VERSION = "0.5.1"
--     TacoTip ships 0.8.0, so every real install reported
--     "tacotip-version-unsupported" and the gate failed closed. It could never
--     succeed in production.
--
--   EXPECTED_INSPECTOR_VERSION = 21
--     Unreachable by any real install. TacoTip ships LibForeverInspector, which
--     registers the "LibClassicInspector" ALIAS at minor 2 and defines no
--     Version() method anywhere in the file -- zero definitions and zero
--     assignments, verified by grep. inspectorVersion() returned nil, the
--     fingerprint read "lci|missing", and the verdict was
--     "inspector-capability-unsupported" -- for a library that had
--     RegisterCallback, PlayerGUIDToUnitToken and GetInventoryItemMixin, which
--     is everything this add-on actually calls.
--
-- What replaces them is a MINIMUM version plus a capability probe: one probe
-- per function this file or TT_GS actually calls. A version string cannot tell
-- "the API I need is absent" from "the counter moved"; a missing function can.
-- The minimum is still enforced, so a genuinely older TacoTip is still refused.
--
-- The TacoTip table is no longer found by hardcoding `_G.TacoTip`. See
-- resolveTacoTipTable below: that global is TacoTip's PRIVATE table, published
-- as _G[addOnName], and addOnName is the add-on's own TOC name -- "TacoTip" once
-- packaged, "TacoTip_Forever" in this development tree. TT_GS, TT_PAWN,
-- TacoTipConfig, TACOTIP_LOCALE and TacoTip_GSCallback are true globals and are
-- used directly; the private table is resolved, not assumed.
-- ---------------------------------------------------------------------------

local MINIMUM_TACOTIP_VERSION = { 0, 8, 0 }

-- The packaged add-on name. The ONLY TacoTip name written down here; the dev
-- tree's folder name is found by the add-on scan instead of being hardcoded, so
-- a future rename stays a one-line change.
local PACKAGED_TACOTIP_NAME = "TacoTip"

-- Inspector functions this add-on calls directly, plus the two that
-- TT_GS:GetScore -- the score we render and therefore delegate to -- calls on
-- our behalf. Probed individually; every one must be a function.
local INSPECTOR_CAPABILITIES = {
    "RegisterCallback",      -- Adapter.RegisterInventoryReady, Scanner refresh
    "UnregisterCallback",    -- paired teardown; absent means a foreign callback lib
    "PlayerGUIDToUnitToken", -- Scanner, Adapter
    "GetInventoryItemMixin", -- TT_GS:GetScore, per-slot scoring
    "GetLastCacheTime",      -- TT_GS:GetScore, remote-player readiness gate
}

-- TacoTip private-table members the TOOLTIP surface needs. GetDefaults is what
-- identifies the table as TacoTip's at all; nothing else in this file is a
-- reliable identity marker on its own.
local TACOTIP_COMMON_CAPABILITIES = {
    "GetDefaults",
}

-- Duck-type markers used ONLY to find the table, never to gate on it: this file
-- calls none of them, so a future TacoTip may rename them without breaking
-- anything and that must not be reported as a lost capability.
local TT_MARKER_METHODS = {
    "ApplyTooltipAppearance",
    "RefreshOptionsUI",
    "RefreshCharacterFrame",
    "RefreshInspectFrame",
}

local MANAGED_KEY = "show_gs_player"
local SURFACE = "tooltip"

-- CallbackHandler owner keys this add-on has used, oldest first. The current
-- one is derived from addonName at the call site; these are the predecessors a
-- stale in-memory registry could still be holding. See RegisterInventoryReady.
local LEGACY_CALLBACK_OWNERS = {
    "TacoTipGearScoreEnhancer",
}

local EQUIPMENT_CONTEXTS = {
    character = {
        initMethod = "InitCharacterFrame",
        refreshMethod = "RefreshCharacterFrame",
        parentNames = { "CharacterModelFrame", "PaperDollFrame" },
        fontParentName = "CharacterModelFrame",
        moverParentName = "PaperDollFrame",
        fontNames = {
            "PersonalGearScore",
            "PersonalGearScoreText",
            "PersonalAvgItemLvl",
            "PersonalAvgItemLvlText",
        },
        moverOwnerNames = {
            "PersonalGearScoreText",
            "PersonalAvgItemLvlText",
        },
    },
    inspect = {
        initMethod = "InitInspectFrame",
        refreshMethod = "RefreshInspectFrame",
        parentNames = { "InspectFrame", "InspectModelFrame", "InspectPaperDollFrame" },
        fontParentName = "InspectModelFrame",
        moverParentName = "InspectPaperDollFrame",
        fontNames = {
            "InspectGearScore",
            "InspectGearScoreText",
            "InspectAvgItemLvl",
            "InspectAvgItemLvlText",
        },
        moverOwnerNames = {
            "InspectGearScoreText",
            "InspectAvgItemLvlText",
        },
    },
}

local database
local inspector
local compatibility
local lease
local surfaceRequested = false
local conflictLocked = false
local internalReason
local callbackRegistered = false
local equipmentCompatibility = {}
local equipmentHookCallbacks = {}
local equipmentDeferredFrame
local equipmentProcessingDeferred = false
local acquireEquipmentLease
local releaseEquipmentLease
local processEquipmentDeferred
local equipmentStates = {
    character = {
        requested = false,
        active = false,
    },
    inspect = {
        requested = false,
        active = false,
    },
}

-- Forward declarations for the TacoTip-table resolver, which is defined much
-- further down. getMetadataVersion and isTacoTipLoaded below both need it, and
-- BOTH ARE ABOVE IT -- a `local` referenced before its `local` declaration does
-- not become a forward reference in Lua, it becomes a read of an undeclared
-- GLOBAL, which is nil, so the call fails with "attempt to call global ... (a
-- nil value)" at run time rather than at load time. These declarations sit
-- above every caller, which is the only position that works.
local resolveTacoTipTable
local resolveTacoTipAddonName

local function isFiniteUnitNumber(value)
    return type(value) == "number"
        and value == value
        and value >= 0
        and value <= 1
        and value ~= math.huge
        and value ~= -math.huge
end

local function getMetadataVersion()
    -- `name` is declared at FUNCTION scope, not inside the first branch. The
    -- two fallbacks below read it again, and a `local` declared inside the
    -- first `if` is out of scope by the time the second branch runs -- which
    -- reads as a nil global at run time, not as a load-time error.
    local name = resolveTacoTipAddonName()
    local addOns = _G.C_AddOns
    if type(addOns) == "table"
        and type(addOns.GetAddOnMetadata) == "function" then
        local ok, value = pcall(addOns.GetAddOnMetadata, name, "Version")
        if ok then
            return value
        end
    end
    if type(_G.GetAddOnMetadata) == "function" then
        local ok, value = pcall(_G.GetAddOnMetadata, name, "Version")
        if ok then
            return value
        end
    end
    return nil
end

local function isTacoTipLoaded()
    local addOns = _G.C_AddOns
    local name = resolveTacoTipAddonName()
    if type(addOns) == "table" and type(addOns.IsAddOnLoaded) == "function" then
        local ok, first, second = pcall(addOns.IsAddOnLoaded, name)
        if ok then
            local loaded = first
            if second ~= nil then
                loaded = second
            end
            return loaded == true
        end
    end
    if type(_G.IsAddOnLoaded) == "function" then
        local ok, first, second = pcall(_G.IsAddOnLoaded, name)
        if ok then
            local loaded = first
            if second ~= nil then
                loaded = second
            end
            return loaded == true
        end
    end
    return false
end

local function findInspector()
    local libStub = _G.LibStub
    if type(libStub) ~= "table" or type(libStub.GetLibrary) ~= "function" then
        return nil
    end
    local ok, library = pcall(
        libStub.GetLibrary,
        libStub,
        "LibClassicInspector",
        true
    )
    if ok and type(library) == "table" then
        return library
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Finding TacoTip's private table without hardcoding its folder name
-- ---------------------------------------------------------------------------

local OWN_ADDON_NAME = addonName

-- Two or more markers means "this is TacoTip's private table". One hit could be
-- any add-on that copied a single function name; zero means it is not TacoTip.
local function looksLikeTacoTipTable(candidate)
    if type(candidate) ~= "table" then
        return false
    end
    local hits = 0
    for index = 1, #TT_MARKER_METHODS do
        local ok, member = pcall(function()
            return candidate[TT_MARKER_METHODS[index]]
        end)
        if ok and type(member) == "function" then
            hits = hits + 1
        end
    end
    return hits >= 2
end

-- Every loaded add-on's name. Uses C_AddOns on modern clients and the bare
-- global on older ones; either may be absent, in which case the global sweep
-- below still runs. No next() anywhere: it is not guaranteed to exist in every
-- environment this file runs in, and a diagnostic path must never be the thing
-- that raises.
local function loadedAddonNames()
    local names = {}
    local addOns = _G.C_AddOns
    if type(addOns) == "table" and type(addOns.GetAddOns) == "function" then
        local ok, list = pcall(addOns.GetAddOns)
        if ok and type(list) == "table" then
            for index = 1, #list do
                if type(list[index]) == "string" then
                    names[#names + 1] = list[index]
                end
            end
        end
    end
    if #names == 0 and type(_G.GetAddOns) == "function" then
        local ok, list = pcall(_G.GetAddOns)
        if ok and type(list) == "table" then
            for index = 1, #list do
                if type(list[index]) == "string" then
                    names[#names + 1] = list[index]
                end
            end
        end
    end
    return names
end

-- Returns tacoTipTable, globalName, label.
--
-- Pass 1 is the packaged name. Pass 2 walks every LOADED add-on's private table,
-- which is what finds "TacoTip_Forever" in the development tree without that
-- string ever appearing here. Pass 3 is a plain global sweep, the last resort
-- for a client whose C_AddOns cannot enumerate.
--
-- More than one match is reported, never guessed at: this add-on must not touch
-- the wrong TacoTip.
local function scanForTacoTipTable()
    local packaged = _G[PACKAGED_TACOTIP_NAME]
    if PACKAGED_TACOTIP_NAME ~= OWN_ADDON_NAME and looksLikeTacoTipTable(packaged) then
        return packaged, PACKAGED_TACOTIP_NAME, PACKAGED_TACOTIP_NAME
    end

    local matches = {}
    local names = loadedAddonNames()
    for index = 1, #names do
        local name = names[index]
        if name ~= OWN_ADDON_NAME and looksLikeTacoTipTable(_G[name]) then
            matches[#matches + 1] = name
        end
    end
    if #matches == 1 then
        local name = matches[1]
        return _G[name], name, name
    end
    if #matches > 1 then
        table.sort(matches)
        return nil, nil, ("ambiguous:%s+%d"):format(matches[1], #matches - 1)
    end

    local found, foundName = nil, nil
    for key, value in pairs(_G) do
        if type(key) == "string"
            and key ~= OWN_ADDON_NAME
            and looksLikeTacoTipTable(value) then
            if foundName ~= nil then
                return nil, nil, ("ambiguous:%s+1"):format(foundName)
            end
            found, foundName = value, key
        end
    end
    if found then
        return found, foundName, foundName
    end
    return nil, nil, "unresolved"
end

local cachedTacoTipTable
local cachedTacoTipGlobal
local cachedTacoTipLabel

-- TacoTip's add-on name is the name its private table is published under, and
-- that is whatever its TOC is called: "TacoTip" once packaged,
-- "TacoTip_Forever" in this development tree. Asking C_AddOns about a hardcoded
-- "TacoTip" therefore returns nil for the add-on that is actually loaded --
-- GetAddOnMetadata("TacoTip", "Version") is nil and IsAddOnLoaded("TacoTip") is
-- false, so the gate could never pass in the dev tree and could not be
-- distinguished from a real failure.
resolveTacoTipAddonName = function()
    local _, globalName = resolveTacoTipTable()
    return globalName or PACKAGED_TACOTIP_NAME
end

resolveTacoTipTable = function()
    if cachedTacoTipTable ~= nil then
        if cachedTacoTipGlobal ~= nil
            and _G[cachedTacoTipGlobal] == cachedTacoTipTable
            and looksLikeTacoTipTable(cachedTacoTipTable) then
            return cachedTacoTipTable, cachedTacoTipGlobal, cachedTacoTipLabel
        end
        cachedTacoTipTable, cachedTacoTipGlobal, cachedTacoTipLabel = nil, nil, nil
    end
    local found, globalName, label = scanForTacoTipTable()
    if type(found) == "table" and type(globalName) == "string" then
        cachedTacoTipTable = found
        cachedTacoTipGlobal = globalName
        cachedTacoTipLabel = label
    end
    return found, globalName, label
end

-- ---------------------------------------------------------------------------
-- Version and capability primitives
-- ---------------------------------------------------------------------------

-- "0.8.0" -> { 0, 8, 0 }. Anything else (nil, a non-string, a non-numeric
-- component) is nil, which every caller treats as NOT satisfying a minimum.
local function parseVersionString(value)
    if type(value) ~= "string" then
        return nil
    end
    local parts = {}
    local cursor = 1
    while true do
        -- plain = true means the needle is matched LITERALLY, so the separator
        -- is "." and not "%.": with plain = true a backslash is a backslash.
        local dot = string.find(value, ".", cursor, true)
        local piece
        if dot then
            piece = string.sub(value, cursor, dot - 1)
            cursor = dot + 1
        else
            piece = string.sub(value, cursor)
            cursor = nil
        end
        if not string.match(piece, "^%d+$") then
            return nil
        end
        parts[#parts + 1] = tonumber(piece)
        if cursor == nil then
            break
        end
    end
    if #parts == 0 then
        return nil
    end
    return parts
end

-- Numeric component-wise comparison; a shorter version is 0-padded, so "0.8"
-- equals "0.8.0". No upper bound on purpose: a NEWER TacoTip is not a reason to
-- refuse to work -- that is exactly what the capability probe is for.
local function versionAtLeast(value, minimum)
    local parsed = parseVersionString(value)
    if not parsed then
        return false
    end
    for index = 1, #minimum do
        local component = parsed[index] or 0
        if component ~= minimum[index] then
            return component > minimum[index]
        end
    end
    return true
end

-- Probes a named list of members. Returns ok, missing, present.
-- A non-table target fails every probe rather than raising.
local function probeCapabilities(target, names)
    local missing = {}
    local present = {}
    if type(target) ~= "table" then
        for index = 1, #names do
            missing[#missing + 1] = names[index]
        end
        return false, missing, present
    end
    for index = 1, #names do
        local name = names[index]
        local ok, member = pcall(function() return target[name] end)
        if ok and type(member) == "function" then
            present[#present + 1] = name
        else
            missing[#missing + 1] = name
        end
    end
    return #missing == 0, missing, present
end

local function joinCapabilities(list)
    if type(list) ~= "table" or #list == 0 then
        return "none"
    end
    local copy = {}
    for index = 1, #list do
        copy[index] = list[index]
    end
    table.sort(copy)
    return table.concat(copy, "+")
end

local function missingSignature(missing)
    return #missing == 0 and "none" or joinCapabilities(missing)
end

-- DIAGNOSTIC ONLY. Never a gate.
--
-- This used to be the gate. It returns nil against the library TacoTip actually
-- ships, because LibForeverInspector defines no Version() method at all -- it
-- registers the LibClassicInspector alias at minor 2 and nothing else. A probe
-- that answers nil for the only library in the field is not a probe, it is a
-- permanent rejection. The value is still reported in diagnostics, so a future
-- library that does publish one becomes visible.
local function inspectorVersion(library)
    if type(library) ~= "table" or type(library.Version) ~= "function" then
        return nil
    end
    local ok, value = pcall(library.Version, library)
    if ok then
        return tonumber(value)
    end
    return nil
end

local function qualityBehaviorValid()
    local gearScore = _G.TT_GS
    if type(gearScore) ~= "table" or type(gearScore.GetQuality) ~= "function" then
        return false
    end
    local ok, red, green, blue, label = pcall(
        gearScore.GetQuality,
        gearScore,
        1
    )
    return ok
        and isFiniteUnitNumber(red)
        and isFiniteUnitNumber(green)
        and isFiniteUnitNumber(blue)
        and type(label) == "string"
end

-- One snapshot of "can this add-on work with the TacoTip that is loaded right
-- now", taken as a set of named capabilities. Nothing here compares a version
-- string for equality, and nothing gates on a library method that was never
-- published.
--
-- The reason ladder is ordered so the FIRST failure is the most actionable one:
-- TacoTip absent -> TacoTip too old -> TacoTip's private table not found -> the
-- table lacks a member we call -> the config/library surface is wrong -> the
-- inspector lacks a function we call.
local function captureCompatibility()
    local config = _G.TacoTipConfig
    local tacoTip, tacoTipGlobal, tacoTipLabel = resolveTacoTipTable()
    local gearScore = _G.TT_GS
    local library = findInspector()
    local rawVersion = getMetadataVersion()
    local version = tostring(rawVersion or "unavailable")
    local loaded = isTacoTipLoaded()
    local versionOK = loaded and versionAtLeast(rawVersion, MINIMUM_TACOTIP_VERSION)
    local pawnNumeric = tonumber(_G.PawnClassicLastUpdatedVersion)
    local pawnEffective = pawnNumeric ~= nil and pawnNumeric >= 2.0538
    local pawnScore = pawnEffective
        and type(_G.TT_PAWN) == "table"
        and type(_G.TT_PAWN.GetScore) == "function"
    local gsScore = type(gearScore) == "table"
        and type(gearScore.GetScore) == "function"
    local gsQuality = type(gearScore) == "table"
        and type(gearScore.GetQuality) == "function"
    local callback = type(_G.TacoTip_GSCallback) == "function"
    local refresh = type(tacoTip) == "table"
        and type(tacoTip.RefreshCharacterFrame) == "function"
        and type(tacoTip.RefreshInspectFrame) == "function"

    local ttCapsOK, ttMissing = probeCapabilities(
        tacoTip,
        TACOTIP_COMMON_CAPABILITIES
    )
    local inspectorCapsOK, inspectorMissing, inspectorPresent =
        probeCapabilities(library, INSPECTOR_CAPABILITIES)

    local common = loaded
        and versionOK
        and type(config) == "table"
        and type(tacoTip) == "table"
        and ttCapsOK
    local tooltipGate = common
        and type(config.show_gs_player) == "boolean"
        and type(config.show_pawn_player) == "boolean"
        and type(config.tip_style) == "number"
        and config.tip_style >= 1
        and config.tip_style <= 5
        and gsScore
        and gsQuality
        and callback
        and qualityBehaviorValid()

    local parts = {
        "tacotip", version,
        "min-ver", table.concat(MINIMUM_TACOTIP_VERSION, "."),
        "surface", SURFACE,
        "gate", tostring(tooltipGate),
        "tt-global", tostring(tacoTipLabel),
        "tt-caps", ttCapsOK and "complete" or missingSignature(ttMissing),
        "lci-caps", inspectorCapsOK and "complete" or missingSignature(inspectorMissing),
        "lci-report", tostring(inspectorVersion(library) or "unpublished"),
        "gs", tostring(gsScore), tostring(gsQuality),
        "callback", tostring(callback),
        "refresh", tostring(refresh),
        "pawn", tostring(pawnEffective), tostring(pawnScore),
        "config-types",
        type(config) == "table" and type(config.show_gs_player) or "missing",
        type(config) == "table" and type(config.show_gs_character) or "missing",
        type(config) == "table" and type(config.show_avg_ilvl) or "missing",
        type(config) == "table" and type(config.show_pawn_player) or "missing",
        type(config) == "table" and type(config.tip_style) or "missing",
    }
    local fingerprint = table.concat(parts, "|")

    local supported = tooltipGate
        and inspectorCapsOK
        and type(config.show_talents) == "boolean"

    local reason
    if not loaded then
        reason = "tacotip-not-loaded"
    elseif not versionOK then
        reason = "tacotip-version-unsupported"
    elseif type(tacoTip) ~= "table" then
        reason = "tacotip-table-unresolved"
    elseif not ttCapsOK then
        reason = "tacotip-capability-unsupported"
    elseif not tooltipGate then
        reason = "tacotip-tooltip-capability-unsupported"
    elseif not inspectorCapsOK then
        reason = "inspector-capability-unsupported"
    elseif type(config.show_talents) ~= "boolean" then
        reason = "tacotip-tooltip-capability-unsupported"
    end

    return {
        supported = supported,
        reason = reason,
        fingerprint = fingerprint,
        inspector = library,
        inspectorCapabilitiesPresent = inspectorPresent,
        inspectorCapabilitiesMissing = inspectorMissing,
        tacoTipCapabilitiesMissing = ttMissing,
        tacoTipGlobal = tacoTipGlobal,
        tacoTipLabel = tacoTipLabel,
        minVersion = table.concat(MINIMUM_TACOTIP_VERSION, "."),
        version = version,
        config = config,
        gearScore = gearScore,
        pawnEffective = pawnEffective,
        pawnScore = pawnScore,
    }
end

local handleEquipmentLifecycle
local invokeEquipmentRefresh

local function readObjectMember(object, member)
    if object == nil then
        return false, nil
    end
    local ok, value = pcall(function()
        return object[member]
    end)
    if not ok then
        return false, nil
    end
    return true, value
end

local function objectMethod(object, methodName)
    local ok, method = readObjectMember(object, methodName)
    if ok and type(method) == "function" then
        return method
    end
    return nil
end

local function objectIsShown(object)
    local method = objectMethod(object, "IsShown")
    if not method then
        return false, nil
    end
    local ok, shown = pcall(method, object)
    if not ok or type(shown) ~= "boolean" then
        return false, nil
    end
    return true, shown
end

local function setObjectShown(object, shown)
    local method = objectMethod(object, shown and "Show" or "Hide")
    if not method then
        return false
    end
    local ok = pcall(method, object)
    if not ok then
        return false
    end
    local read, actual = objectIsShown(object)
    return read and actual == shown
end

local function equipmentConfigValid(config)
    return type(config) == "table"
        and type(config.show_gs_character) == "boolean"
        and type(config.show_avg_ilvl) == "boolean"
        and type(config.unlock_info_position) == "boolean"
end

local function allNamedFontsPresent(spec)
    for index = 1, #spec.fontNames do
        if _G[spec.fontNames[index]] == nil then
            return false
        end
    end
    return true
end

local function captureEquipmentCompatibility(contextKey)
    local spec = EQUIPMENT_CONTEXTS[contextKey]
    local config = _G.TacoTipConfig
    local tacoTip = resolveTacoTipTable()
    local library = findInspector()
    local version = tostring(getMetadataVersion() or "unavailable")
    local libraryVersion = inspectorVersion(library)
    local refresh = type(tacoTip) == "table"
        and type(tacoTip[spec.refreshMethod]) == "function"
    local init = type(tacoTip) == "table"
        and type(tacoTip[spec.initMethod]) == "function"
    local existingFonts = allNamedFontsPresent(spec)
    local initPath = init and "method"
        or (existingFonts and "existing-fonts" or "missing")
    local hook = type(_G.hooksecurefunc) == "function"
    local configValid = equipmentConfigValid(config)
    -- Same probe as the tooltip surface: the functions we call, never a version
    -- number the library never published.
    local inspectorValid, inspectorMissing = probeCapabilities(
        library,
        INSPECTOR_CAPABILITIES
    )
    local common = isTacoTipLoaded()
        and versionAtLeast(getMetadataVersion(), MINIMUM_TACOTIP_VERSION)
        and type(tacoTip) == "table"

    local supported = common
        and configValid
        and refresh
        and initPath ~= "missing"
        and hook
        and inspectorValid

    local reason
    if not isTacoTipLoaded() then
        reason = "tacotip-not-loaded"
    elseif not versionAtLeast(getMetadataVersion(), MINIMUM_TACOTIP_VERSION) then
        reason = "tacotip-version-unsupported"
    elseif type(tacoTip) ~= "table" then
        reason = contextKey .. "-tacotip-table-unsupported"
    elseif not configValid then
        reason = contextKey .. "-config-capability-unsupported"
    elseif not refresh then
        reason = contextKey .. "-refresh-capability-unsupported"
    elseif initPath == "missing" then
        reason = contextKey .. "-init-capability-unsupported"
    elseif not hook then
        reason = contextKey .. "-secure-hook-unsupported"
    elseif not inspectorValid then
        reason = "inspector-capability-unsupported"
    end

    local parts = {
        "tacotip", version,
        "surface", "equipment-" .. contextKey,
        "gate", tostring(supported),
        "refresh", tostring(refresh),
        "init", initPath,
        "existing-fonts", tostring(existingFonts),
        "hook", tostring(hook),
        "lci", tostring(libraryVersion or "unpublished"),
        "lci-caps", inspectorValid and "complete"
            or missingSignature(inspectorMissing),
        "config-types",
        type(config) == "table" and type(config.show_gs_character) or "missing",
        type(config) == "table" and type(config.show_avg_ilvl) or "missing",
        type(config) == "table" and type(config.unlock_info_position) or "missing",
    }

    return {
        supported = supported,
        reason = reason,
        fingerprint = table.concat(parts, "|"),
        config = config,
        tacoTip = tacoTip,
        hookFunction = _G.hooksecurefunc,
        refreshFunction = refresh and tacoTip[spec.refreshMethod] or nil,
        initFunction = init and tacoTip[spec.initMethod] or nil,
        initPath = initPath,
        inspector = library,
        inspectorVersion = libraryVersion,
        refreshHookInstalled = false,
        initHookInstalled = false,
    }
end

local function notifyEquipmentCompatibilityChanged(contextKey)
    local frames = namespace.Frames
    local handler = type(frames) == "table"
        and frames.HandleCompatibilityChanged
    if type(handler) == "function" then
        pcall(handler, contextKey)
    end
end

local function inCombatLockdown()
    if type(_G.InCombatLockdown) ~= "function" then
        return false
    end
    local ok, locked = pcall(_G.InCombatLockdown)
    return ok and locked == true
end

local function equipmentRuntimeValid(contextKey)
    local spec = EQUIPMENT_CONTEXTS[contextKey]
    local captured = equipmentCompatibility[contextKey]
    if type(captured) ~= "table" or not captured.supported then
        return false, captured and captured.reason or "not-initialized"
    end
    if not isTacoTipLoaded()
        or not versionAtLeast(getMetadataVersion(), MINIMUM_TACOTIP_VERSION) then
        return false, "tacotip-version-unsupported"
    end
    local currentInspector = findInspector()
    local inspectorCapsOK = probeCapabilities(currentInspector, INSPECTOR_CAPABILITIES)
    if currentInspector ~= captured.inspector
        or currentInspector ~= inspector
        or not inspectorCapsOK then
        return false, "inspector-capability-changed"
    end
    if not callbackRegistered then
        return false, "inspector-callback-registration-failed"
    end
    if _G.TacoTipConfig ~= captured.config
        or not equipmentConfigValid(_G.TacoTipConfig) then
        return false, contextKey .. "-config-capability-changed"
    end
    local currentTacoTip = resolveTacoTipTable()
    if currentTacoTip ~= captured.tacoTip
        or type(currentTacoTip) ~= "table"
        or currentTacoTip[spec.refreshMethod] ~= captured.refreshFunction then
        return false, contextKey .. "-refresh-capability-changed"
    end
    if not captured.refreshHookInstalled then
        return false, contextKey .. "-refresh-hook-missing"
    end
    local currentInit = currentTacoTip[spec.initMethod]
    if captured.initPath == "method" then
        if currentInit ~= captured.initFunction
            and not (currentInit == nil and allNamedFontsPresent(spec)) then
            return false, contextKey .. "-init-capability-changed"
        end
        if currentInit ~= nil and not captured.initHookInstalled then
            return false, contextKey .. "-init-hook-missing"
        end
    elseif currentInit ~= nil then
        return false, contextKey .. "-init-capability-changed"
    end
    return true, nil
end

local function validateVisibilityObject(object, expectedType, expectedParent)
    local getObjectType = objectMethod(object, "GetObjectType")
    local getParent = objectMethod(object, "GetParent")
    if not getObjectType
        or not getParent
        or not objectMethod(object, "Show")
        or not objectMethod(object, "Hide")
        or not objectMethod(object, "IsShown") then
        return false
    end
    local typeOk, objectType = pcall(getObjectType, object)
    local parentOk, parent = pcall(getParent, object)
    local shownOk = objectIsShown(object)
    return typeOk
        and objectType == expectedType
        and parentOk
        and parent == expectedParent
        and shownOk
end

local function captureEquipmentParents(contextKey)
    local spec = EQUIPMENT_CONTEXTS[contextKey]
    local parents = {}
    for index = 1, #spec.parentNames do
        local name = spec.parentNames[index]
        local parent = _G[name]
        if parent == nil then
            return nil, contextKey == "inspect"
                and "inspect-not-loaded"
                or "character-not-ready"
        end
        parents[name] = parent
    end
    return parents, nil
end

local function captureEquipmentSnapshot(contextKey)
    local spec = EQUIPMENT_CONTEXTS[contextKey]
    local parents, parentReason = captureEquipmentParents(contextKey)
    if not parents then
        return nil, parentReason, true
    end

    local present = 0
    for index = 1, #spec.fontNames do
        if _G[spec.fontNames[index]] ~= nil then
            present = present + 1
        end
    end
    if present ~= #spec.fontNames then
        if present == 0 then
            return nil, contextKey .. "-fontstrings-not-ready", true
        end
        return nil, contextKey .. "-fontstrings-incomplete", false
    end

    local records = {}
    local fonts = {}
    local fontParent = parents[spec.fontParentName]
    for index = 1, #spec.fontNames do
        local name = spec.fontNames[index]
        local object = _G[name]
        if not validateVisibilityObject(object, "FontString", fontParent) then
            return nil, contextKey .. "-fontstring-ownership-invalid", false
        end
        local read, shown = objectIsShown(object)
        if not read then
            return nil, contextKey .. "-fontstring-visibility-invalid", false
        end
        fonts[name] = object
        records[#records + 1] = {
            kind = "font",
            name = name,
            object = object,
            restoreShown = shown,
        }
    end

    local movers = {}
    local moverParent = parents[spec.moverParentName]
    for index = 1, #spec.moverOwnerNames do
        local ownerName = spec.moverOwnerNames[index]
        local owner = fonts[ownerName]
        local memberOk, mover = readObjectMember(owner, "mover")
        if not memberOk then
            return nil, contextKey .. "-mover-capability-invalid", false
        end
        if mover == nil then
            movers[ownerName] = false
        else
            if not validateVisibilityObject(mover, "Button", moverParent) then
                return nil, contextKey .. "-mover-ownership-invalid", false
            end
            for existingOwner, existingMover in pairs(movers) do
                if existingMover == mover and existingOwner ~= ownerName then
                    return nil, contextKey .. "-mover-ownership-invalid", false
                end
            end
            local read, shown = objectIsShown(mover)
            if not read then
                return nil, contextKey .. "-mover-visibility-invalid", false
            end
            movers[ownerName] = mover
            records[#records + 1] = {
                kind = "mover",
                name = ownerName,
                object = mover,
                restoreShown = shown,
            }
        end
    end

    return {
        parents = parents,
        fonts = fonts,
        movers = movers,
        records = records,
        fontCount = #spec.fontNames,
    }, nil, false
end

local function rollbackVisibility(records, states)
    local restored = true
    for index = #records, 1, -1 do
        if not setObjectShown(records[index].object, states[index]) then
            restored = false
        end
    end
    return restored
end

local function hideRecordsAtomic(records)
    local states = {}
    for index = 1, #records do
        local read, shown = objectIsShown(records[index].object)
        if not read then
            return false, nil
        end
        states[index] = shown
    end
    for index = 1, #records do
        if not setObjectShown(records[index].object, false) then
            rollbackVisibility(records, states)
            return false, nil
        end
    end
    return true, states
end

local function restoreRecordsAtomic(records)
    local states = {}
    for index = 1, #records do
        local read, shown = objectIsShown(records[index].object)
        if not read then
            return false
        end
        states[index] = shown
    end
    for index = 1, #records do
        if not setObjectShown(
            records[index].object,
            records[index].restoreShown
        ) then
            rollbackVisibility(records, states)
            return false
        end
    end
    return true
end

local function validateLeasedObjects(contextKey, allowNewMovers)
    local spec = EQUIPMENT_CONTEXTS[contextKey]
    local state = equipmentStates[contextKey]
    local currentLease = state.lease
    if not currentLease then
        return false, contextKey .. "-lease-missing", nil
    end

    for index = 1, #spec.parentNames do
        local name = spec.parentNames[index]
        if _G[name] ~= currentLease.parents[name] then
            return false, contextKey .. "-parent-identity-changed", nil
        end
    end

    local fontParent = currentLease.parents[spec.fontParentName]
    for index = 1, #spec.fontNames do
        local name = spec.fontNames[index]
        local object = currentLease.fonts[name]
        if _G[name] ~= object
            or not validateVisibilityObject(object, "FontString", fontParent) then
            return false, contextKey .. "-fontstring-identity-changed", nil
        end
    end

    local additions = {}
    local moverParent = currentLease.parents[spec.moverParentName]
    for index = 1, #spec.moverOwnerNames do
        local ownerName = spec.moverOwnerNames[index]
        local owner = currentLease.fonts[ownerName]
        local memberOk, mover = readObjectMember(owner, "mover")
        if not memberOk then
            return false, contextKey .. "-mover-capability-changed", nil
        end
        local captured = currentLease.movers[ownerName]
        if captured == false and mover ~= nil then
            if not allowNewMovers then
                return false, contextKey .. "-mover-identity-changed", nil
            end
            if not validateVisibilityObject(mover, "Button", moverParent) then
                return false, contextKey .. "-mover-ownership-invalid", nil
            end
            for capturedOwner, capturedMover in pairs(currentLease.movers) do
                if capturedMover ~= false
                    and capturedMover == mover
                    and capturedOwner ~= ownerName then
                    return false, contextKey .. "-mover-ownership-invalid", nil
                end
            end
            additions[#additions + 1] = {
                kind = "mover",
                name = ownerName,
                object = mover,
            }
        elseif captured ~= false and mover ~= captured then
            return false, contextKey .. "-mover-identity-changed", nil
        elseif captured ~= false
            and not validateVisibilityObject(captured, "Button", moverParent) then
            return false, contextKey .. "-mover-capability-changed", nil
        end
    end

    if #additions > 1 and additions[1].object == additions[2].object then
        return false, contextKey .. "-mover-ownership-invalid", nil
    end
    return true, nil, additions
end

local function hasDeferredEquipmentWork()
    return equipmentStates.character.deferred ~= nil
        or equipmentStates.inspect.deferred ~= nil
end

local function updateDeferredFrameRegistration()
    if not equipmentDeferredFrame then
        return
    end
    local method = objectMethod(
        equipmentDeferredFrame,
        hasDeferredEquipmentWork() and "RegisterEvent" or "UnregisterEvent"
    )
    if method then
        pcall(method, equipmentDeferredFrame, "PLAYER_REGEN_ENABLED")
    end
end

local function ensureDeferredEquipmentFrame()
    if equipmentDeferredFrame or type(_G.CreateFrame) ~= "function" then
        updateDeferredFrameRegistration()
        return
    end
    local ok, frame = pcall(_G.CreateFrame, "Frame")
    if not ok or frame == nil then
        return
    end
    local setScript = objectMethod(frame, "SetScript")
    local registerEvent = objectMethod(frame, "RegisterEvent")
    if not setScript or not registerEvent then
        return
    end
    local scriptOk = pcall(setScript, frame, "OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" and processEquipmentDeferred then
            processEquipmentDeferred()
        end
    end)
    if not scriptOk then
        return
    end
    equipmentDeferredFrame = frame
    updateDeferredFrameRegistration()
end

local function deferEquipmentAction(contextKey, action, reason)
    local state = equipmentStates[contextKey]
    state.deferred = action
    state.reason = reason
    ensureDeferredEquipmentFrame()
end

local function refreshNativeAfterRelease(contextKey)
    local spec = EQUIPMENT_CONTEXTS[contextKey]
    local captured = equipmentCompatibility[contextKey]
    local currentTacoTip = resolveTacoTipTable()
    if not captured
        or currentTacoTip ~= captured.tacoTip
        or type(currentTacoTip) ~= "table"
        or currentTacoTip[spec.refreshMethod] ~= captured.refreshFunction then
        return true
    end
    local ok = pcall(captured.refreshFunction, captured.tacoTip)
    if not ok then
        equipmentStates[contextKey].reason = contextKey .. "-refresh-failed"
        return false
    end
    return true
end

releaseEquipmentLease = function(contextKey, refreshNative, preserveReason)
    local state = equipmentStates[contextKey]
    if not state.lease then
        state.active = false
        if state.deferred == "release" then
            state.deferred = nil
        end
        if not preserveReason then
            state.reason = nil
        end
        updateDeferredFrameRegistration()
        return true
    end
    if inCombatLockdown() then
        deferEquipmentAction(
            contextKey,
            "release",
            contextKey .. "-combat-release-deferred"
        )
        return false
    end
    if not restoreRecordsAtomic(state.lease.records) then
        deferEquipmentAction(
            contextKey,
            "release",
            contextKey .. "-visibility-restore-failed"
        )
        return false
    end

    state.lease = nil
    state.active = false
    state.ready = true
    state.deferred = nil
    if not preserveReason then
        state.reason = nil
    end
    updateDeferredFrameRegistration()
    if refreshNative then
        return refreshNativeAfterRelease(contextKey)
    end
    return true
end

local function invalidateEquipmentContext(contextKey, reason, abandonLease)
    local state = equipmentStates[contextKey]
    local captured = equipmentCompatibility[contextKey]
    local wasActive = state.active == true
    state.requested = false
    state.reason = reason
    state.deferred = nil
    if captured then
        captured.supported = false
        captured.reason = reason
    end
    if state.lease then
        if abandonLease then
            state.lease = nil
            state.active = false
            updateDeferredFrameRegistration()
        else
            releaseEquipmentLease(contextKey, false, true)
            state.reason = reason
        end
    else
        state.active = false
    end
    if wasActive then
        notifyEquipmentCompatibilityChanged(contextKey)
    end
end

local function auditEquipmentLease(contextKey)
    local state = equipmentStates[contextKey]
    if not state.lease or not state.active then
        return false
    end
    local runtimeValid, runtimeReason = equipmentRuntimeValid(contextKey)
    if not runtimeValid then
        invalidateEquipmentContext(contextKey, runtimeReason, false)
        return false
    end
    local objectsValid, objectReason = validateLeasedObjects(contextKey, false)
    if not objectsValid then
        invalidateEquipmentContext(contextKey, objectReason, false)
        return false
    end
    local visibilityConflict = false
    for index = 1, #state.lease.records do
        local record = state.lease.records[index]
        local read, shown = objectIsShown(record.object)
        if not read then
            invalidateEquipmentContext(
                contextKey,
                contextKey .. "-visibility-conflict",
                false
            )
            return false
        end
        if shown then
            record.restoreShown = true
            visibilityConflict = true
        end
    end
    if visibilityConflict then
        invalidateEquipmentContext(
            contextKey,
            contextKey .. "-visibility-conflict",
            false
        )
        return false
    end
    state.reason = nil
    return true
end

acquireEquipmentLease = function(contextKey, allowRefresh)
    local state = equipmentStates[contextKey]
    local captured = equipmentCompatibility[contextKey]
    if not state.requested or not captured or not captured.supported then
        state.reason = captured and captured.reason or "not-initialized"
        return false
    end
    if state.lease then
        if state.deferred == "release" then
            state.deferred = nil
            updateDeferredFrameRegistration()
        end
        return auditEquipmentLease(contextKey)
    end
    local runtimeValid, runtimeReason = equipmentRuntimeValid(contextKey)
    if not runtimeValid then
        invalidateEquipmentContext(contextKey, runtimeReason, false)
        return false
    end
    if inCombatLockdown() then
        deferEquipmentAction(
            contextKey,
            "acquire",
            contextKey .. "-combat-deferred"
        )
        return false
    end

    local snapshot, reason, transient = captureEquipmentSnapshot(contextKey)
    if not snapshot and transient and allowRefresh then
        local parents = captureEquipmentParents(contextKey)
        if parents then
            invokeEquipmentRefresh(contextKey)
            if state.lease then
                return state.active
            end
            snapshot, reason, transient = captureEquipmentSnapshot(contextKey)
        end
    end
    if not snapshot then
        state.ready = false
        state.reason = reason
        state.deferred = nil
        if not transient then
            invalidateEquipmentContext(contextKey, reason, false)
        end
        return false
    end

    local hidden, originalStates = hideRecordsAtomic(snapshot.records)
    if not hidden then
        invalidateEquipmentContext(
            contextKey,
            contextKey .. "-visibility-acquire-failed",
            true
        )
        return false
    end
    for index = 1, #snapshot.records do
        snapshot.records[index].restoreShown = originalStates[index]
    end
    state.lease = snapshot
    state.active = true
    state.ready = true
    state.deferred = nil
    state.reason = nil
    updateDeferredFrameRegistration()
    return true
end

handleEquipmentLifecycle = function(contextKey)
    local state = equipmentStates[contextKey]
    state.hookGeneration = (state.hookGeneration or 0) + 1
    if not state.requested then
        return
    end
    if inCombatLockdown() then
        if state.lease then
            deferEquipmentAction(
                contextKey,
                "rehide",
                contextKey .. "-combat-deferred"
            )
            notifyEquipmentCompatibilityChanged(contextKey)
        else
            deferEquipmentAction(
                contextKey,
                "acquire",
                contextKey .. "-combat-deferred"
            )
        end
        return
    end
    if not state.lease then
        acquireEquipmentLease(contextKey, false)
        return
    end

    local runtimeValid, runtimeReason = equipmentRuntimeValid(contextKey)
    if not runtimeValid then
        invalidateEquipmentContext(contextKey, runtimeReason, false)
        return
    end
    local objectsValid, objectReason, additions = validateLeasedObjects(
        contextKey,
        true
    )
    if not objectsValid then
        invalidateEquipmentContext(contextKey, objectReason, false)
        return
    end

    local records = {}
    for index = 1, #state.lease.records do
        records[#records + 1] = state.lease.records[index]
    end
    for index = 1, #additions do
        records[#records + 1] = additions[index]
    end
    local hidden, latestStates = hideRecordsAtomic(records)
    if not hidden then
        invalidateEquipmentContext(
            contextKey,
            contextKey .. "-visibility-refresh-failed",
            true
        )
        return
    end

    for index = 1, #records do
        records[index].restoreShown = latestStates[index]
    end
    for index = 1, #additions do
        local addition = additions[index]
        state.lease.movers[addition.name] = addition.object
        state.lease.records[#state.lease.records + 1] = addition
    end
    state.active = true
    state.ready = true
    state.deferred = nil
    state.reason = nil
    updateDeferredFrameRegistration()
end

invokeEquipmentRefresh = function(contextKey)
    local state = equipmentStates[contextKey]
    local captured = equipmentCompatibility[contextKey]
    if not state.requested or not captured or not captured.supported then
        return false
    end
    if inCombatLockdown() then
        deferEquipmentAction(
            contextKey,
            state.lease and "rehide" or "acquire",
            contextKey .. "-combat-deferred"
        )
        return false
    end
    local parents, parentReason = captureEquipmentParents(contextKey)
    if not parents then
        state.ready = false
        state.reason = parentReason
        state.deferred = nil
        return false
    end
    local runtimeValid, runtimeReason = equipmentRuntimeValid(contextKey)
    if not runtimeValid then
        invalidateEquipmentContext(contextKey, runtimeReason, false)
        return false
    end

    local generation = state.hookGeneration or 0
    local ok = pcall(captured.refreshFunction, captured.tacoTip)
    if not ok then
        invalidateEquipmentContext(
            contextKey,
            contextKey .. "-refresh-failed",
            false
        )
        return false
    end
    if (state.hookGeneration or 0) == generation and state.requested then
        local callbackOk = pcall(handleEquipmentLifecycle, contextKey)
        if not callbackOk then
            invalidateEquipmentContext(
                contextKey,
                contextKey .. "-refresh-hook-failed",
                false
            )
            return false
        end
    end
    return state.active == true
end

local function installEquipmentHook(contextKey, methodName, hookKind)
    local captured = equipmentCompatibility[contextKey]
    if not captured or not captured.supported then
        return false
    end
    local callback = function()
        local ok = pcall(handleEquipmentLifecycle, contextKey)
        if not ok then
            invalidateEquipmentContext(
                contextKey,
                contextKey .. "-" .. hookKind .. "-hook-failed",
                false
            )
        end
    end
    equipmentHookCallbacks[contextKey] = equipmentHookCallbacks[contextKey] or {}
    equipmentHookCallbacks[contextKey][hookKind] = callback
    local ok, installed = pcall(
        captured.hookFunction,
        captured.tacoTip,
        methodName,
        callback
    )
    if not ok or installed == false then
        captured.supported = false
        captured.reason = contextKey .. "-" .. hookKind .. "-hook-registration-failed"
        equipmentStates[contextKey].reason = captured.reason
        return false
    end
    captured[hookKind .. "HookInstalled"] = true
    return true
end

local function installEquipmentHooks(contextKey)
    local spec = EQUIPMENT_CONTEXTS[contextKey]
    local captured = equipmentCompatibility[contextKey]
    if not captured or not captured.supported then
        return
    end
    if not installEquipmentHook(contextKey, spec.refreshMethod, "refresh") then
        return
    end
    captured.refreshFunction = captured.tacoTip[spec.refreshMethod]

    if type(captured.tacoTip[spec.initMethod]) == "function" then
        if not installEquipmentHook(contextKey, spec.initMethod, "init") then
            return
        end
        captured.initFunction = captured.tacoTip[spec.initMethod]
    end
end

processEquipmentDeferred = function()
    if equipmentProcessingDeferred or inCombatLockdown() then
        return false
    end
    equipmentProcessingDeferred = true
    local contexts = { "character", "inspect" }
    for index = 1, #contexts do
        local contextKey = contexts[index]
        local state = equipmentStates[contextKey]
        local action = state.deferred
        if action then
            state.deferred = nil
            local ok = pcall(function()
                if action == "release" or not state.requested then
                    releaseEquipmentLease(contextKey, true, false)
                elseif action == "rehide" and state.lease then
                    handleEquipmentLifecycle(contextKey)
                else
                    acquireEquipmentLease(contextKey, true)
                end
            end)
            if not ok then
                invalidateEquipmentContext(
                    contextKey,
                    contextKey .. "-deferred-action-failed",
                    false
                )
            end
        end
    end
    equipmentProcessingDeferred = false
    updateDeferredFrameRegistration()
    return not hasDeferredEquipmentWork()
end

local function hasSourceInspectionPath(config)
    if type(config) ~= "table" then
        return false
    end
    if config.show_talents == true then
        return true
    end
    return config.show_pawn_player == true
        and tonumber(_G.PawnClassicLastUpdatedVersion) ~= nil
        and tonumber(_G.PawnClassicLastUpdatedVersion) >= 2.0538
        and type(_G.TT_PAWN) == "table"
        and type(_G.TT_PAWN.GetScore) == "function"
end

local function recoveryRecord()
    if type(database) ~= "table" then
        return nil, nil
    end
    local journal = database.tacoTipRecovery
    local entries = type(journal) == "table" and journal.entries or nil
    local record = type(entries) == "table" and entries[MANAGED_KEY] or nil
    return journal, record
end

local function clearJournal()
    if type(database) == "table" then
        database.tacoTipRecovery = nil
    end
end

local function recoverInterruptedLease()
    local journal, record = recoveryRecord()
    if not journal then
        return true
    end
    if type(journal) ~= "table" then
        conflictLocked = true
        internalReason = "recovery-journal-mismatch"
        return false
    end
    if not compatibility.supported then
        conflictLocked = true
        internalReason = "recovery-compatibility-unsupported"
        return false
    end
    if journal.surface ~= SURFACE
        or journal.fingerprint ~= compatibility.fingerprint
        or type(record) ~= "table"
        or record.owningSurface ~= SURFACE
        or record.forcedValue ~= false
        or type(record.originalValue) ~= "boolean"
        or type(record.owned) ~= "boolean" then
        conflictLocked = true
        internalReason = "recovery-journal-mismatch"
        return false
    end

    local config = _G.TacoTipConfig
    if config ~= compatibility.config then
        conflictLocked = true
        internalReason = "recovery-config-replaced"
        return false
    end
    if config[MANAGED_KEY] ~= record.forcedValue then
        clearJournal()
        conflictLocked = true
        internalReason = "recovery-setting-conflict"
        return false
    end
    if record.owned then
        config[MANAGED_KEY] = record.originalValue
    end
    clearJournal()
    return true
end

local function relinquishForConflict(reason)
    clearJournal()
    lease = nil
    conflictLocked = true
    internalReason = reason
end

local function releaseLease(reason)
    if not lease then
        return true
    end

    local config = _G.TacoTipConfig
    if config ~= lease.configTable then
        relinquishForConflict("tooltip-lease-config-replaced")
        return false
    end
    if config[MANAGED_KEY] ~= lease.forcedValue then
        relinquishForConflict("tooltip-lease-setting-conflict")
        return false
    end

    if lease.owned then
        config[MANAGED_KEY] = lease.originalValue
    end
    clearJournal()
    lease = nil
    if reason ~= "compatibility-failure"
        and reason ~= "inspection-path-unsafe" then
        internalReason = nil
    end
    return true
end

local function runtimeCapabilitiesPresent()
    local config = _G.TacoTipConfig
    local tacoTip = resolveTacoTipTable()
    local gearScore = _G.TT_GS
    if not isTacoTipLoaded()
        or not versionAtLeast(getMetadataVersion(), MINIMUM_TACOTIP_VERSION) then
        return false, "tacotip-version-unsupported"
    end
    if config ~= compatibility.config
        or type(config.show_gs_player) ~= "boolean"
        or type(config.show_pawn_player) ~= "boolean"
        or type(config.show_talents) ~= "boolean"
        or type(config.tip_style) ~= "number"
        or config.tip_style < 1
        or config.tip_style > 5 then
        return false, "tacotip-config-capability-changed"
    end
    if type(tacoTip) ~= "table"
        or not probeCapabilities(tacoTip, TACOTIP_COMMON_CAPABILITIES)
        or type(gearScore) ~= "table"
        or type(gearScore.GetScore) ~= "function"
        or type(gearScore.GetQuality) ~= "function"
        or type(_G.TacoTip_GSCallback) ~= "function"
        or not qualityBehaviorValid() then
        return false, "tacotip-tooltip-capability-changed"
    end
    if inspector ~= compatibility.inspector
        or not probeCapabilities(inspector, INSPECTOR_CAPABILITIES) then
        return false, "inspector-capability-changed"
    end
    if not callbackRegistered then
        return false, "inspector-callback-registration-failed"
    end
    return true, nil
end

local function acquireLease()
    compatibility = captureCompatibility()
    inspector = compatibility.inspector
    if not compatibility.supported then
        internalReason = compatibility.reason
        return false
    end
    if conflictLocked then
        return false
    end
    if not callbackRegistered then
        internalReason = "inspector-callback-registration-failed"
        return false
    end

    local config = compatibility.config
    if not hasSourceInspectionPath(config) then
        internalReason = "tooltip-inspection-path-unsafe"
        return false
    end

    local originalValue = config[MANAGED_KEY]
    local owned = originalValue ~= false
    local record = {
        originalValue = originalValue,
        forcedValue = false,
        owningSurface = SURFACE,
        owned = owned,
    }
    database.tacoTipRecovery = {
        surface = SURFACE,
        fingerprint = compatibility.fingerprint,
        entries = { [MANAGED_KEY] = record },
    }
    lease = {
        configTable = config,
        originalValue = originalValue,
        forcedValue = false,
        owned = owned,
    }
    if owned then
        config[MANAGED_KEY] = false
    end
    internalReason = nil
    return true
end

local function auditLease()
    if not lease then
        return false
    end
    if _G.TacoTipConfig ~= lease.configTable then
        relinquishForConflict("tooltip-lease-config-replaced")
        return false
    end
    if lease.configTable[MANAGED_KEY] ~= lease.forcedValue then
        relinquishForConflict("tooltip-lease-setting-conflict")
        return false
    end

    local valid, reason = runtimeCapabilitiesPresent()
    if not valid then
        releaseLease("compatibility-failure")
        internalReason = reason
        return false
    end
    if not hasSourceInspectionPath(lease.configTable) then
        releaseLease("inspection-path-unsafe")
        internalReason = "tooltip-inspection-path-unsafe"
        return false
    end
    return true
end

function Adapter.Initialize(savedDatabase)
    database = savedDatabase
    compatibility = captureCompatibility()
    inspector = compatibility.inspector
    internalReason = compatibility.reason
    recoverInterruptedLease()
    local contexts = { "character", "inspect" }
    for index = 1, #contexts do
        local contextKey = contexts[index]
        if not equipmentHookCallbacks[contextKey] then
            equipmentCompatibility[contextKey] = captureEquipmentCompatibility(
                contextKey
            )
            local captured = equipmentCompatibility[contextKey]
            if captured.supported then
                local snapshot, readinessReason, transient = captureEquipmentSnapshot(
                    contextKey
                )
                if not snapshot and not transient then
                    captured.supported = false
                    captured.reason = readinessReason
                end
            end
            equipmentStates[contextKey].reason = captured.reason
            installEquipmentHooks(contextKey)
        else
            local captured = equipmentCompatibility[contextKey]
            if captured and captured.supported then
                local runtimeValid, runtimeReason = equipmentRuntimeValid(
                    contextKey
                )
                local readinessReason
                local transient = false
                if runtimeValid then
                    local snapshot
                    snapshot, readinessReason, transient = captureEquipmentSnapshot(
                        contextKey
                    )
                    runtimeValid = snapshot ~= nil or transient
                end
                if not runtimeValid and not transient then
                    local reason = runtimeReason or readinessReason
                    if equipmentStates[contextKey].lease then
                        invalidateEquipmentContext(contextKey, reason, false)
                    else
                        captured.supported = false
                        captured.reason = reason
                        equipmentStates[contextKey].reason = reason
                    end
                end
            end
        end
    end
    return compatibility.supported
end

function Adapter.GetInspector()
    return inspector
end

function Adapter.RegisterInventoryReady(callback)
    if callbackRegistered then
        return true
    end
    if type(callback) ~= "function" then
        internalReason = "inspector-callback-registration-failed"
        return false
    end
    if type(inspector) ~= "table"
        or type(inspector.RegisterCallback) ~= "function" then
        internalReason = "inspector-callback-registration-failed"
        return false
    end
    -- The registration key is `addonName` -- the add-on's OWN name, which is
    -- also the name of its private table and therefore stable across a rebuild.
    --
    -- Phase 1 renamed the folder/TOC from TacoTipGearScoreEnhancer to
    -- TacoTip_Extras, so the key moved. CallbackHandler keys its registry by
    -- owner string, which means a registration left over from a pre-1.0.0
    -- install would sit under the OLD name and never fire again. Rather than
    -- hardcode either name, this clears the known predecessor first: only the
    -- pre-1.0.0 build of THIS add-on could ever have registered under it, and
    -- UnregisterCallback(owner, eventname) drops exactly that one entry.
    --
    -- If a future rename happens, LEGACY_CALLBACK_OWNERS is the single place to
    -- add the previous name to -- `addonName` itself stays derived, so a rename
    -- never needs a second edit to stay correct.
    for index = 1, #LEGACY_CALLBACK_OWNERS do
        local legacy = LEGACY_CALLBACK_OWNERS[index]
        if legacy ~= addonName and type(inspector.UnregisterCallback) == "function" then
            pcall(inspector.UnregisterCallback, legacy, "INVENTORY_READY")
        end
    end
    local ok, registered = pcall(
        inspector.RegisterCallback,
        addonName,
        "INVENTORY_READY",
        callback
    )
    if ok and registered ~= false then
        callbackRegistered = true
        return true
    end
    internalReason = "inspector-callback-registration-failed"
    return false
end

function Adapter.SetTooltipSurfaceEnabled(enabled)
    surfaceRequested = enabled == true
    if not surfaceRequested then
        releaseLease("tooltip-surface-disabled")
        return false
    end
    if lease then
        return auditLease()
    end
    return acquireLease()
end

function Adapter.IsTooltipSurfaceActive()
    if not surfaceRequested then
        return false
    end
    if lease then
        return auditLease()
    end
    return false
end

function Adapter.GetEquipmentSurfaceCompatibility(contextKey)
    if not EQUIPMENT_CONTEXTS[contextKey] then
        return false, "unknown-equipment-surface", nil
    end
    local captured = equipmentCompatibility[contextKey]
    if not captured then
        return false, "not-initialized", nil
    end
    return captured.supported, captured.reason, captured.fingerprint
end

function Adapter.SetEquipmentSurfaceEnabled(contextKey, enabled)
    if not EQUIPMENT_CONTEXTS[contextKey] then
        return false
    end
    local state = equipmentStates[contextKey]
    state.requested = enabled == true
    local captured = equipmentCompatibility[contextKey]
    if state.requested and (not captured or not captured.supported) then
        state.requested = false
        state.reason = captured and captured.reason or "not-initialized"
        return false
    end
    if not state.requested then
        if not state.lease then
            state.active = false
            state.deferred = nil
            state.reason = nil
            updateDeferredFrameRegistration()
            return false
        end
        releaseEquipmentLease(contextKey, true, false)
        return false
    end
    return acquireEquipmentLease(contextKey, true)
end

function Adapter.IsEquipmentSurfaceActive(contextKey)
    if not EQUIPMENT_CONTEXTS[contextKey] then
        return false
    end
    local state = equipmentStates[contextKey]
    if not state.requested or state.deferred == "rehide" then
        return false
    end
    return auditEquipmentLease(contextKey)
end

function Adapter.RefreshEquipmentSurface(contextKey)
    if not EQUIPMENT_CONTEXTS[contextKey] then
        return false
    end
    return invokeEquipmentRefresh(contextKey)
end

function Adapter.AcquireEquipmentContext(contextKey)
    return Adapter.SetEquipmentSurfaceEnabled(contextKey, true)
end

function Adapter.ReleaseEquipmentContext(contextKey)
    if not EQUIPMENT_CONTEXTS[contextKey] then
        return false
    end
    local state = equipmentStates[contextKey]
    state.requested = false
    if not state.lease then
        state.active = false
        state.deferred = nil
        state.reason = nil
        updateDeferredFrameRegistration()
        return true
    end
    return releaseEquipmentLease(contextKey, true, false)
end

function Adapter.IsEquipmentContextActive(contextKey)
    return Adapter.IsEquipmentSurfaceActive(contextKey)
end

function Adapter.GetEquipmentSurfaceReason(contextKey)
    if not EQUIPMENT_CONTEXTS[contextKey] then
        return "unknown-equipment-surface"
    end
    local state = equipmentStates[contextKey]
    local captured = equipmentCompatibility[contextKey]
    if state.reason then
        return state.reason
    end
    if captured then
        return captured.reason
    end
    return "not-initialized"
end

function Adapter.GetEquipmentSurfaceDiagnostics(contextKey)
    local spec = EQUIPMENT_CONTEXTS[contextKey]
    if not spec then
        return nil
    end
    local state = equipmentStates[contextKey]
    local captured = equipmentCompatibility[contextKey]
    local capturedFonts = 0
    local capturedMovers = 0
    if state.lease then
        for index = 1, #state.lease.records do
            if state.lease.records[index].kind == "font" then
                capturedFonts = capturedFonts + 1
            elseif state.lease.records[index].kind == "mover" then
                capturedMovers = capturedMovers + 1
            end
        end
    end
    local ready = state.ready == true
    if not ready and captured and captured.supported then
        local snapshot = captureEquipmentSnapshot(contextKey)
        ready = snapshot ~= nil
    end
    return {
        surface = contextKey,
        supported = captured and captured.supported == true or false,
        reason = Adapter.GetEquipmentSurfaceReason(contextKey),
        fingerprint = captured and captured.fingerprint or nil,
        requested = state.requested == true,
        active = state.requested == true
            and state.active == true
            and state.deferred == nil,
        leaseHeld = state.lease ~= nil,
        deferred = state.deferred,
        ready = ready,
        expectedFontStrings = #spec.fontNames,
        capturedFontStrings = capturedFonts,
        expectedMovers = #spec.moverOwnerNames,
        capturedMovers = capturedMovers,
        inspectorVersion = captured and captured.inspectorVersion or nil,
        inspectorCallbackRegistered = callbackRegistered == true,
        initPath = captured and captured.initPath or nil,
        refreshHookInstalled = captured
            and captured.refreshHookInstalled == true
            or false,
        initHookInstalled = captured
            and captured.initHookInstalled == true
            or false,
    }
end

function Adapter.HandlePlayerRegenEnabled()
    return processEquipmentDeferred()
end

function Adapter.GetEquipmentScoreColor(score)
    if not isTacoTipLoaded()
        or not versionAtLeast(getMetadataVersion(), MINIMUM_TACOTIP_VERSION)
        or not qualityBehaviorValid() then
        return nil
    end
    local gearScore = _G.TT_GS
    local ok, red, green, blue = pcall(
        gearScore.GetQuality,
        gearScore,
        score
    )
    if ok
        and isFiniteUnitNumber(red)
        and isFiniteUnitNumber(green)
        and isFiniteUnitNumber(blue) then
        return red, green, blue
    end
    return nil
end

function Adapter.GetCurrentScoreColor(score)
    if not Adapter.IsTooltipSurfaceActive() then
        return nil
    end
    local gearScore = _G.TT_GS
    if type(gearScore) ~= "table" or type(gearScore.GetQuality) ~= "function" then
        return nil
    end
    local ok, red, green, blue = pcall(
        gearScore.GetQuality,
        gearScore,
        score
    )
    if ok
        and isFiniteUnitNumber(red)
        and isFiniteUnitNumber(green)
        and isFiniteUnitNumber(blue) then
        return red, green, blue
    end
    return nil
end

function Adapter.GetCompatibility()
    if not compatibility then
        return false, "not-initialized", nil
    end
    return compatibility.supported,
        compatibility.reason,
        compatibility.fingerprint
end

function Adapter.GetInternalReason()
    return internalReason
end

-- Exactly what the gate looked at, and what it concluded.
--
-- There is a reason this exists rather than a one-line "supported: true": the
-- two pins this file used to carry could not be satisfied by any real install,
-- and the only way that stayed invisible for a release was that nothing ever
-- printed the inputs. Every probed capability, the TacoTip version against the
-- minimum, and the name the private table was resolved under are all reported
-- here so the verdict can be argued with.
function Adapter.GetCapabilityReport()
    local tacoTip, tacoTipGlobal, tacoTipLabel = resolveTacoTipTable()
    local library = findInspector()
    local _, inspectorMissing, inspectorPresent =
        probeCapabilities(library, INSPECTOR_CAPABILITIES)
    local _, tacoTipMissing = probeCapabilities(
        tacoTip,
        TACOTIP_COMMON_CAPABILITIES
    )
    local rawVersion = getMetadataVersion()
    local supported, reason = false, "not-initialized"
    if compatibility then
        supported, reason = compatibility.supported, compatibility.reason
    end
    return {
        supported = supported,
        reason = reason,
        tacoTipVersion = rawVersion,
        minTacoTipVersion = table.concat(MINIMUM_TACOTIP_VERSION, "."),
        versionAccepted = versionAtLeast(rawVersion, MINIMUM_TACOTIP_VERSION),
        tacoTipLoaded = isTacoTipLoaded(),
        tacoTipGlobal = tacoTipGlobal,
        tacoTipResolvedAs = tacoTipLabel,
        tacoTipCapabilities = TACOTIP_COMMON_CAPABILITIES,
        tacoTipCapabilitiesMissing = tacoTipMissing,
        inspectorCapabilities = INSPECTOR_CAPABILITIES,
        inspectorCapabilitiesPresent = inspectorPresent,
        inspectorCapabilitiesMissing = inspectorMissing,
        inspectorPublishedVersion = inspectorVersion(library),
        fingerprint = compatibility and compatibility.fingerprint or nil,
    }
end

function Adapter.Shutdown()
    surfaceRequested = false
    local tooltipReleased = releaseLease("addon-shutdown")
    local equipmentReleased = true
    local contexts = { "character", "inspect" }
    for index = 1, #contexts do
        local contextKey = contexts[index]
        equipmentStates[contextKey].requested = false
        if not releaseEquipmentLease(contextKey, true, false) then
            equipmentReleased = false
        end
    end
    return tooltipReleased and equipmentReleased
end
