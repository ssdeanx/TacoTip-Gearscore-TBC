--[[

    TacoTip Pawn Score module
    for WoW Forever & Retail

--]]

-- Single home for the Pawn version thresholds (Batch 5 N3): both consumers
-- (this file's call-time gate and options.lua's Refresh probe) route here via
-- TT_PAWN.IsAvailable. The thresholds lived in two places with an unguarded
-- compare, so a string-typed version global raised `attempt to compare ...`
-- on every probe instead of resolving. tonumber() treats a non-numeric
-- version as absent (falls through to the API fallback); numeric input
-- resolves exactly as before.
--
-- Hunter L-NEW4 provenance: Pawn publishes exactly one version global per
-- game type -- PawnClassicLastUpdatedVersion on Classic clients (2.0538 is
-- the Classic scale-library schema the shipped Pawn reports; anything at or
-- above it carries the provider registry this file reads) and
-- PawnLastUpdatedVersion on mainline (2.0 is the mainline floor with the
-- same registry shape). Either global at/above its floor, or the live
-- PawnGetItemData/PawnGetSingleValueFromItem/PawnGetScaleColor trio when
-- both are absent, means "Pawn is usable". Below floor (or non-numeric)
-- means "not yet loaded or not this game type", never an error.
local PAWN_CLASSIC_MIN_VERSION = 2.0538
local PAWN_RETAIL_MIN_VERSION = 2.0
local function pawnVersionAtLeast(raw, threshold)
    local v = tonumber(raw)
    return v ~= nil and v >= threshold
end

local function pawnAvailableNow()
    local classicVer = rawget(_G, "PawnClassicLastUpdatedVersion")
    local retailVer = rawget(_G, "PawnLastUpdatedVersion")
    local apiPresent = type(PawnGetItemData) == "function" and type(PawnGetSingleValueFromItem) == "function" and
        type(PawnGetScaleColor) == "function"
    return pawnVersionAtLeast(classicVer, PAWN_CLASSIC_MIN_VERSION)
        or pawnVersionAtLeast(retailVer, PAWN_RETAIL_MIN_VERSION)
        or apiPresent
end

-- Snapshot for diagnostics: distinguishes "Pawn appeared after this file
-- loaded" from "no scale for this class/spec". The module itself no longer
-- returns early (hunter C3); the gate lives at call time in GetScore below.
local isPawnLoadedAtLoad = pawnAvailableNow() and true or false

assert(LibStub, "TacoTip requires LibStub")
assert(LibStub:GetLibrary("LibForeverInspector", true), "TacoTip requires LibForeverInspector")
assert(LibStub:GetLibrary("LibDetours-1.0", true), "TacoTip requires LibDetours-1.0")

local CI = LibStub("LibForeverInspector")

-- GUID + throttle + drain helpers live in ONE home (TT_GS, gearscore.lua --
-- arbiter #4/#5). Pawn routes to them at call time; the inline fallbacks below
-- run only when TT_GS is absent (gearscore failed to load -- not a valid
-- state) and preserve the original behaviour exactly.
local function fallbackGUIDIsPlayer(guid)
    return type(guid) == "string" and string.find(guid, "Player-", 1, true) == 1
end

local function pawnRequestLoadItemDataByID(itemID)
    local gs = rawget(_G, "TT_GS")
    local fn = gs and gs.RequestLoadItemDataByID
    if (type(fn) == "function") then
        return fn(itemID)
    end
    local raw = _G.C_Item and _G.C_Item.RequestLoadItemDataByID
    if (raw and itemID) then
        return raw(itemID)
    end
end

-- Pawn scale libraries.
--
-- Pawn ships exactly two scale providers and Pawn.toc gates them by game type, so
-- exactly one of them exists on any given client:
--     AskMrRobot.lua     [AllowLoadGameType mainline]   Retail, WoW Forever
--     ClassicHawsJon.lua [AllowLoadGameType classic]   Vanilla, TBC, Wrath
-- The prefix must therefore follow the client. Hardcoding either one is wrong on
-- the other half of the supported set.
--
-- The obvious implementation -- build a name, ask Pawn whether it exists, fall
-- back to the other -- cannot work here, and that is the whole bug:
-- PawnIsScaleVisible and PawnGetScaleColor report an unknown name through
-- VgerCore.Fail, and Fail does NOT raise a Lua error. It calls VgerCore.Message,
-- which writes straight to DEFAULT_CHAT_FRAME. pcall cannot suppress that, so a
-- "guarded" probe still printed "ScaleName must be the name of an existing scale,
-- and is case-sensitive." to chat on every single tooltip render.
--
-- PawnScaleProviders and PawnCommon are plain globals, so the same question is
-- answered by reading Pawn's own registries, which is completely silent.
-- PawnCommon.Scales is the exact table PawnGetScaleColor consults, so a name that
-- is present in it is guaranteed not to hit the Fail path.
local SCALE_LIBRARIES = {
    { provider = "MrRobot", prefix = "\"MrRobot\":" },
    { provider = "Classic",  prefix = "\"Classic\":" },
}

-- Returns a scale name proven to exist in PawnCommon.Scales, or nil.
-- Returns nil (rather than a guessed name) while Pawn is still initialising, and
-- on a client whose provider has no scale for this class/spec -- in both cases
-- the caller simply skips the colour, which is cosmetic. It must never return a
-- name Pawn does not have.
local function pawnLoadedScaleName(class, spec)
    local scales = PawnCommon and PawnCommon.Scales
    if ((not scales) or (not class) or (not spec)) then
        return nil
    end
    local suffix = class .. tostring(spec)
    for _, library in ipairs(SCALE_LIBRARIES) do
        local name = library.prefix .. suffix
        if ((PawnScaleProviders and PawnScaleProviders[library.provider]) and scales[name]) then
            return name
        end
    end
    return nil
end

TT_PAWN = {}
local TT_PAWN = TT_PAWN

TT_PAWN.WasAvailableAtLoad = isPawnLoadedAtLoad
TT_PAWN.IsAvailable = pawnAvailableNow

local function getPlayerGUID(arg)
    local gs = rawget(_G, "TT_GS")
    local fn = gs and gs.ResolvePlayerGUID
    if (type(fn) == "function") then
        return fn(arg)
    end
    if (arg) then
        local isPlayer = (_G.C_PlayerInfo and _G.C_PlayerInfo.GUIDIsPlayer) or fallbackGUIDIsPlayer
        if (isPlayer(arg)) then
            return arg
        elseif (UnitIsPlayer(arg)) then
            return UnitGUID(arg)
        end
    end
    return nil
end

function TT_PAWN:GetItemScore(itemLink, class, specIndex, scaleName)
    if (itemLink and class and specIndex) then
        -- Hunter H-NEW3: a nil scaleName means "no proven scale for this
        -- class/spec" and must return 0 WITHOUT guessing. The old code built
        -- "MrRobot:"/"Classic:" names blindly; an unknown name routes through
        -- VgerCore.Fail -> DEFAULT_CHAT_FRAME (documented above), which pcall
        -- cannot suppress, so every external nil-scaleName call spammed chat
        -- once per tooltip render. The internal GetScore caller only ever
        -- passes a pawnLoadedScaleName-proven name (or skips the call), so
        -- the provided-name path below is unchanged.
        if (not scaleName) then
            return 0
        end
        if (type(PawnGetItemData) == "function") then
            local ok, item = pcall(PawnGetItemData, itemLink)
            if (ok and item and type(PawnGetSingleValueFromItem) == "function") then
                local okScore, _, score = pcall(PawnGetSingleValueFromItem, item, scaleName)
                if (okScore and score) then
                    return tonumber(score) or 0
                end
            end
        end
    end
    return 0
end

-- Single home (arbiter #5): alias the gearscore implementation at load time
-- (toc order guarantees gearscore.lua ran first). The fallback below runs
-- only when TT_GS is absent -- gearscore failed to load, not a valid state --
-- and preserves the same dedupe/latch invariants.
local gsAtLoad = rawget(_G, "TT_GS")
local itemcacheCB
if (gsAtLoad and type(gsAtLoad.DrainItemCache) == "function") then
    itemcacheCB = gsAtLoad.DrainItemCache
else
    itemcacheCB = function(tbl, id)
        if (not tbl or not tbl.items or tbl.completed) then
            return
        end
        for i = #tbl.items, 1, -1 do
            if (id == tbl.items[i]) then
                table.remove(tbl.items, i)
            end
        end
        if (#tbl.items == 0 and not tbl.completed) then
            tbl.completed = true
            if (TacoTip_GSCallback) then
                TacoTip_GSCallback(tbl.guid)
            end
        end
    end
end

TT_PAWN.DrainItemCache = itemcacheCB


function TT_PAWN:GetScore(unitorguid, useCallback)
    if (not pawnAvailableNow()) then
        return 0, "", "|cffffffff"
    end
    local guid = getPlayerGUID(unitorguid)
    if (guid) then
        if (guid ~= UnitGUID("player")) then
            local _, invTime = CI:GetLastCacheTime(guid)
            if (invTime == 0) then
                return 0, "", "|cffffffff"
            end
        end

        local spec = CI:GetSpecialization(guid)
        local ppOk, _, PlayerEnglishClass = pcall(GetPlayerInfoByGUID, guid)
        local class = ppOk and PlayerEnglishClass or nil
        if (not (spec and class)) then
            return 0, "", "|cffffffff"
        end
        local pawnScore = 0
        local IsReady = true

        if (spec and class) then
            -- nil when Pawn has not finished loading, or has no scale for this
            -- class/spec. Both are silent, and both simply mean "no Pawn colour"
            -- rather than an error.
            --
            -- A nil scaleName means Pawn has no scale for this class/spec. GetScore then
            -- skips the score entirely: pawnScore stays 0, which is what both
            -- attempts already returned, and the tooltip gates on pawnScore > 0.
            -- Calling anyway cost two guaranteed-to-fail PawnGetSingleValueFromItem
            -- calls per item -- and re-introduced the guessed-name pattern this
            -- helper exists to eliminate, including the VgerCore.Fail chat path.
            local scaleName = pawnLoadedScaleName(class, spec)
            local cb_table
            if (useCallback) then
                cb_table = { ["guid"] = guid, ["items"] = {} }
            end
            for i = 1, 18 do
                if (i ~= 4) then
                    local item = CI:GetInventoryItemMixin(guid, i)
                    if (item) then
                        if (item:IsItemDataCached()) then
                            if (scaleName) then
                                local tempScore = TT_PAWN:GetItemScore(item:GetItemLink(), class, spec, scaleName)
                                pawnScore = pawnScore + tempScore
                            end
                        else
                            IsReady = false
                            local itemID = item:GetItemID()
                            if (itemID) then
                                if (useCallback) then
                                    -- Dedupe identical item ids before
                                    -- registering; see gearscore.lua for the
                                    -- duplicate-slot rationale.
                                    local alreadyPending = false
                                    for _, pendingID in ipairs(cb_table.items) do
                                        if (pendingID == itemID) then
                                            alreadyPending = true
                                            break
                                        end
                                    end
                                    if (not alreadyPending) then
                                        table.insert(cb_table.items, itemID)
                                    end
                                    item:ContinueOnItemLoad(function()
                                        itemcacheCB(cb_table, itemID)
                                    end)
                                else
                                    pawnRequestLoadItemDataByID(itemID)
                                end
                            end
                        end
                    end
                end
            end
            if (not IsReady) then
                pawnScore = 0
                -- Cold path only (hunter H6): shared pending counter, counted
                -- beside the GearScore one in diag. No loading-row UI change.
                -- Routed through the TT_GS home (missing only if gearscore
                -- failed to load, in which case there is no score to hide).
                local gs = rawget(_G, "TT_GS")
                if (gs and type(gs.CountPendingHidden) == "function") then
                    gs:CountPendingHidden()
                end
            end
            local pawnColor
            -- Only ever called with a name pawnLoadedScaleName proved is in
            -- PawnCommon.Scales, so this cannot reach the VgerCore.Fail branch.
            -- This replaces a deferred readiness probe that called
            -- PawnGetScaleColor("Classic":ROGUE1) blindly: on Retail, where Pawn
            -- has no "Classic" library at all, that probe printed the ScaleName
            -- error to chat by itself.
            if (scaleName and type(PawnGetScaleColor) == "function") then
                local pcOk, pcResult = pcall(PawnGetScaleColor, scaleName, true)
                pawnColor = pcOk and pcResult or nil
            else
                pawnColor = nil
            end
            return pawnScore, CI:GetSpecializationName(class, spec, true), pawnColor or "|cffffffff"
        end
    end
    return 0, "", "|cffffffff"
end
