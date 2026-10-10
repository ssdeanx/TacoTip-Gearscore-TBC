--[[

    TacoTip Pawn Score module
    for WoW Forever & Retail

--]]

local pawnApiPresent = type(PawnGetItemData) == "function" and type(PawnGetSingleValueFromItem) == "function" and
    type(PawnGetScaleColor) == "function"
local pawnClassicVer = rawget(_G, "PawnClassicLastUpdatedVersion")
local pawnRetailVer = rawget(_G, "PawnLastUpdatedVersion")
local isPawnLoaded = (pawnClassicVer and pawnClassicVer >= 2.0538) or (pawnRetailVer and pawnRetailVer >= 2.0) or pawnApiPresent

if (not isPawnLoaded) then
    return
end

assert(LibStub, "TacoTip requires LibStub")
assert(LibStub:GetLibrary("LibForeverInspector", true), "TacoTip requires LibForeverInspector")
assert(LibStub:GetLibrary("LibDetours-1.0", true), "TacoTip requires LibDetours-1.0")

local CI = LibStub("LibForeverInspector")

local function fallbackGUIDIsPlayer(guid)
    return type(guid) == "string" and string.find(guid, "Player-", 1, true) == 1
end

local GUIDIsPlayer = (_G.C_PlayerInfo and _G.C_PlayerInfo.GUIDIsPlayer) or fallbackGUIDIsPlayer
local RequestLoadItemDataByID = _G.C_Item and _G.C_Item.RequestLoadItemDataByID

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

local function getPlayerGUID(arg)
    if (arg) then
        if (GUIDIsPlayer(arg)) then
            return arg
        elseif (UnitIsPlayer(arg)) then
            return UnitGUID(arg)
        end
    end
    return nil
end

function TT_PAWN:GetItemScore(itemLink, class, specIndex, scaleName)
    if (itemLink and class and specIndex) then
        if (type(PawnGetItemData) == "function") then
            local ok, item = pcall(PawnGetItemData, itemLink)
            if (ok and item and type(PawnGetSingleValueFromItem) == "function") then
                if (not scaleName) then
                    scaleName = "\"MrRobot\":" .. class .. specIndex
                    local okScore, _, score = pcall(PawnGetSingleValueFromItem, item, scaleName)
                    if (okScore and score and tonumber(score)) then
                        return tonumber(score) or 0
                    end
                    scaleName = "\"Classic\":" .. class .. specIndex
                end
                local okScore, _, score = pcall(PawnGetSingleValueFromItem, item, scaleName)
                if (okScore and score) then
                    return tonumber(score) or 0
                end
            end
        end
    end
    return 0
end

local function itemcacheCB(tbl, id)
    if (not tbl or not tbl.items or tbl.completed) then
        return
    end
    -- Iterate backward: table.remove shifts later elements left, so a
    -- forward sweep would skip the element right after a removed match.
    for i = #tbl.items, 1, -1 do
        if (id == tbl.items[i]) then
            table.remove(tbl.items, i)
        end
    end
    -- Latch so a duplicate-slot registration for an already-drained list
    -- cannot fire TacoTip_GSCallback twice (two identical rings = two
    -- ContinueOnItemLoad closures for one pending id).
    if (#tbl.items == 0 and not tbl.completed) then
        tbl.completed = true
        if (TacoTip_GSCallback) then
            TacoTip_GSCallback(tbl.guid)
        end
    end
end


function TT_PAWN:GetScore(unitorguid, useCallback)
    local guid = getPlayerGUID(unitorguid)
    if (guid) then
        if (guid ~= UnitGUID("player")) then
            local _, invTime = CI:GetLastCacheTime(guid)
            if (invTime == 0) then
                return 0, "", "|cffffffff"
            end
        end

        local spec = CI:GetSpecialization(guid) or 1
        local ppOk, _, PlayerEnglishClass = pcall(GetPlayerInfoByGUID, guid)
        local class = ppOk and PlayerEnglishClass or nil
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
                                elseif (RequestLoadItemDataByID) then
                                    RequestLoadItemDataByID(itemID)
                                end
                            end
                        end
                    end
                end
            end
            if (not IsReady) then
                pawnScore = 0
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
