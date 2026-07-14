--[[

    TacoTip Pawn Score module by kebabstorm
    for Classic/TBC/WOTLK
    Requires: Pawn 2.5.38+

--]]

local interfaceVersion = select(4, GetBuildInfo()) or 0
local clientBuildMajor = math.floor(interfaceVersion / 10000)
-- load only on the Classic-era client families TacoTip supports (Vanilla/TBC/Wrath)
if (clientBuildMajor < 1 or clientBuildMajor > 3) then
    return
end

-- SoD-era Pawn does not expose PawnClassicLastUpdatedVersion, so the old
-- version-only gate made the whole module return early and Pawn never loaded.
-- Also accept the presence of Pawn's public API functions as proof of load.
local pawnApiPresent = type(PawnGetItemData) == "function" and type(PawnGetSingleValueFromItem) == "function" and type(PawnGetScaleColor) == "function"
local isPawnLoaded = (PawnClassicLastUpdatedVersion and PawnClassicLastUpdatedVersion >= 2.0538) or pawnApiPresent

if (not isPawnLoaded) then
    return
end

assert(LibStub, "TacoTip requires LibStub")
assert(LibStub:GetLibrary("LibClassicInspector", true), "TacoTip requires LibClassicInspector")
assert(LibStub:GetLibrary("LibDetours-1.0", true), "TacoTip requires LibDetours-1.0")

local CI = LibStub("LibClassicInspector")

local function fallbackGUIDIsPlayer(guid)
    return type(guid) == "string" and string.find(guid, "Player-", 1, true) == 1
end

local GUIDIsPlayer = (_G.C_PlayerInfo and _G.C_PlayerInfo.GUIDIsPlayer) or fallbackGUIDIsPlayer
local RequestLoadItemDataByID = _G.C_Item and _G.C_Item.RequestLoadItemDataByID

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

function TT_PAWN:GetItemScore(itemLink, class, specIndex)
    if (itemLink and class and specIndex) then
        local item = PawnGetItemData(itemLink)
        if (item) then
            return tonumber(select(2,PawnGetSingleValueFromItem(item,"\"Classic\":"..class..specIndex))) or 0
        end
    end
    return 0
end

local function itemcacheCB(tbl, id)
    for i=1,#tbl.items do
        if (id == tbl.items[i]) then
            table.remove(tbl.items, i)
        end
    end
    if (#tbl.items == 0) then
        TacoTip_GSCallback(tbl.guid)
    end
end


function TT_PAWN:GetScore(unitorguid, useCallback)
    local guid = getPlayerGUID(unitorguid)
    if (guid) then
        if (guid ~= UnitGUID("player")) then
            local _, invTime = CI:GetLastCacheTime(guid)
            if(invTime == 0) then
                return 0, "", "|cffffffff"
            end
        end

        -- SoD runes replace talent trees, so GetSpecialization can return nil.
        -- Fall back to the primary spec (1) so Pawn still scores instead of
        -- producing a malformed scale name ("Classic":CLASS..nil) and 0.
        local spec = CI:GetSpecialization(guid) or 1
        local _, class = GetPlayerInfoByGUID(guid)
        local pawnScore = 0
        local IsReady = true

        if (spec and class) then
            local scaleName = "\"Classic\":"..class..spec
            local cb_table
            if (useCallback) then
                cb_table = {["guid"] = guid, ["items"] = {}}
            end
            for i = 1, 18 do
                if (i ~= 4) then
                    local item = CI:GetInventoryItemMixin(guid, i)
                    if (item) then
                        if (item:IsItemDataCached()) then
                            local tempScore = TT_PAWN:GetItemScore(item:GetItemLink(),class,spec)
                            pawnScore = pawnScore + tempScore
                        else
                            IsReady = false
                            local itemID = item:GetItemID()
                            if (itemID) then
                                if (useCallback) then
                                    table.insert(cb_table.items, itemID)
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
            if (_TacoTipPawnReady) then
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

-- Deferred Pawn readiness check.  On SoD (Classic Era) Pawn's scale data is
-- not available until a few ticks after ADDON_LOADED.  Probing too early
-- triggers Pawn's internal error which prints to chat even through pcall.
-- We wait 3 seconds, then probe once.  Until this probe succeeds every
-- tooltip show returns a nil colour — no call to PawnGetScaleColor, no error.
if (C_Timer and C_Timer.After) then
    _TacoTipPawnReady = false
    C_Timer.After(3, function()
        local pcOk = pcall(PawnGetScaleColor, "\"Classic\":ROGUE1", true)
        _TacoTipPawnReady = pcOk
        if (not pcOk) then
            -- One more chance in 5 more seconds (very slow client / Pawn version)
            C_Timer.After(5, function()
                local pcOk2 = pcall(PawnGetScaleColor, "\"Classic\":ROGUE1", true)
                _TacoTipPawnReady = pcOk2
            end)
        end
    end)
end
