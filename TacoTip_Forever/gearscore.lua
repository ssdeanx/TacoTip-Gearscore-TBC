--[[

    TacoTip GearScore module
    for WoW Forever & Retail

--]]

local addOnName = ...

assert(LibStub, "TacoTip requires LibStub")
assert(LibStub:GetLibrary("LibForeverInspector", true), "TacoTip requires LibForeverInspector")
assert(LibStub:GetLibrary("LibDetours-1.0", true), "TacoTip requires LibDetours-1.0")

local CI = LibStub("LibForeverInspector")
local TT = _G[addOnName]
local L = _G.TACOTIP_LOCALE

if (not TT) then
    TT = {}
    rawset(_G, addOnName, TT)
end

local function registerBootstrapSlash()
    local slashCmdList = rawget(_G, "SlashCmdList")
    if (not slashCmdList) then
        slashCmdList = {}
        rawset(_G, "SlashCmdList", slashCmdList)
    end
    if (slashCmdList.TACOTIP) then
        return
    end

    SLASH_TACOTIP1 = "/tacotip"
    SLASH_TACOTIP2 = "/tooltip"
    SLASH_TACOTIP3 = "/tip"
    SLASH_TACOTIP4 = "/tt"
    SLASH_TACOTIP5 = "/gs"
    SLASH_TACOTIP6 = "/gearscore"
    SLASH_TACOTIP7 = "/taco"

    rawset(slashCmdList, "TACOTIP", function(msg)
        local cmd = strlower((msg or "")):gsub("^%s+", ""):gsub("%s+$", "")

        if (cmd == "custom" or cmd == "unlock" or cmd == "move" or cmd == "mover") then
            if (TacoTip_CustomPosEnable) then
                TacoTip_CustomPosEnable(true)
            else
                print("|cff59f0dcTacoTip:|r Loaded, but the tooltip mover is not ready yet.")
            end
        elseif (cmd == "save") then
            if (TacoTipDragButton and TacoTipDragButton.IsShown and TacoTipDragButton:IsShown()) then
                TacoTipDragButton:_Save()
            else
                print("|cff59f0dcTacoTip:|r Tooltip mover is not currently shown.")
            end
        elseif (cmd == "default") then
            if (TacoTipDragButton and TacoTipDragButton._Disable) then
                TacoTipDragButton:_Disable(true)
            end
            if (TacoTipConfig) then
                TacoTipConfig.custom_pos = nil
            end
            print("|cff59f0dcTacoTip:|r " ..
                ((L and L["Custom tooltip position disabled."]) or "Custom tooltip position disabled."))
        elseif (TT and TT.OpenOptionsPanel) then
            TT.OpenOptionsPanel()
        else
            print("|cff59f0dcTacoTip:|r Slash commands are loaded.")
            print("|cff59f0dcTacoTip:|r /tacotip custom - show the tooltip mover")
            print("|cff59f0dcTacoTip:|r /tacotip default - clear the custom tooltip position")
        end
    end)
end

registerBootstrapSlash()

-- Re-run locale selection once SavedVariables are readable.
--
-- The per-locale files cannot honour TacoTipConfig.locale_override themselves:
-- addon files execute BEFORE WoW populates SavedVariables, so TacoTipConfig is
-- still an empty table while Locale/*.lua runs and the selection necessarily
-- falls back to GetLocale(). Re-applying here -- after ADDON_LOADED, when the
-- override is actually readable -- is what makes the language dropdown do
-- anything. TacoTipApplyLocale mutates _G.TACOTIP_LOCALE in place, so the
-- `local L` bindings in this file, main.lua and options.lua pick the change up.
if (TacoTipConfig) then
    local localeLoader = CreateFrame("Frame")
    localeLoader:RegisterEvent("ADDON_LOADED")
    localeLoader:SetScript("OnEvent", function(_, _, addonName)
        if (addonName == addOnName and _G.TacoTipApplyLocale) then
            _G.TacoTipApplyLocale()
        end
    end)
end

local function fallbackGUIDIsPlayer(guid)
    return type(guid) == "string" and string.find(guid, "Player-", 1, true) == 1
end

local GUIDIsPlayer = (_G.C_PlayerInfo and _G.C_PlayerInfo.GUIDIsPlayer) or fallbackGUIDIsPlayer
local RequestLoadItemDataByID = _G.C_Item and _G.C_Item.RequestLoadItemDataByID
local function GetItemInfo(...)
    if not ... then return nil end
    local fn = (_G.C_Item and _G.C_Item.GetItemInfo) or _G.GetItemInfo
    if fn then
        return fn(...)
    end
end
local floor = math.floor

_G.TT_GS = {}
local TT_GS = _G.TT_GS

-- Quality bracket per client family.
--
-- This is purely a mapping: GS_Quality below is keyed off BRACKET_SIZE at load
-- time and scoreFromItemValues passes ItemLevel through raw, so selecting the
-- right bracket restores that client's colour ramp and leaves the iLvl average
-- untouched. No formula change is involved.
--
--   Classic Era / WoW Forever  200   level cap 60, Classic-like item levels
--   TBC Anniversary            400
--   Titanforge / Retail       1000
--
-- WoW Forever used to fall through to the 1000 default, which inflated every
-- score 5x and collapsed the whole ramp into the "Common" white band. It is
-- called out explicitly rather than left to a default so that an unrecognised
-- client is visible instead of silently inheriting a value.
local BRACKET_SIZE = 1000

if (CI.IsClassic and CI:IsClassic()) then
    BRACKET_SIZE = 200
elseif (CI.IsTBC and CI:IsTBC()) then
    BRACKET_SIZE = 400
elseif (CI.IsForever and CI:IsForever()) then
    BRACKET_SIZE = 200
end

local MAX_SCORE = BRACKET_SIZE * 7

TT_GS.BRACKET_SIZE = BRACKET_SIZE
TT_GS.MAX_SCORE = MAX_SCORE

local GS_ItemTypes = {
    ["INVTYPE_RELIC"] = { ["SlotMOD"] = 0.3164, ["ItemSlot"] = 18, ["Enchantable"] = false },
    ["INVTYPE_TRINKET"] = { ["SlotMOD"] = 0.5625, ["ItemSlot"] = 33, ["Enchantable"] = false },
    ["INVTYPE_2HWEAPON"] = { ["SlotMOD"] = 2.000, ["ItemSlot"] = 16, ["Enchantable"] = true },
    ["INVTYPE_WEAPONMAINHAND"] = { ["SlotMOD"] = 1.0000, ["ItemSlot"] = 16, ["Enchantable"] = true },
    ["INVTYPE_WEAPONOFFHAND"] = { ["SlotMOD"] = 1.0000, ["ItemSlot"] = 17, ["Enchantable"] = true },
    ["INVTYPE_RANGED"] = { ["SlotMOD"] = 0.3164, ["ItemSlot"] = 18, ["Enchantable"] = true },
    ["INVTYPE_THROWN"] = { ["SlotMOD"] = 0.3164, ["ItemSlot"] = 18, ["Enchantable"] = false },
    ["INVTYPE_RANGEDRIGHT"] = { ["SlotMOD"] = 0.3164, ["ItemSlot"] = 18, ["Enchantable"] = false },
    ["INVTYPE_SHIELD"] = { ["SlotMOD"] = 1.0000, ["ItemSlot"] = 17, ["Enchantable"] = true },
    ["INVTYPE_WEAPON"] = { ["SlotMOD"] = 1.0000, ["ItemSlot"] = 36, ["Enchantable"] = true },
    ["INVTYPE_HOLDABLE"] = { ["SlotMOD"] = 1.0000, ["ItemSlot"] = 17, ["Enchantable"] = false },
    ["INVTYPE_HEAD"] = { ["SlotMOD"] = 1.0000, ["ItemSlot"] = 1, ["Enchantable"] = true },
    ["INVTYPE_NECK"] = { ["SlotMOD"] = 0.5625, ["ItemSlot"] = 2, ["Enchantable"] = false },
    ["INVTYPE_SHOULDER"] = { ["SlotMOD"] = 0.7500, ["ItemSlot"] = 3, ["Enchantable"] = true },
    ["INVTYPE_CHEST"] = { ["SlotMOD"] = 1.0000, ["ItemSlot"] = 5, ["Enchantable"] = true },
    ["INVTYPE_ROBE"] = { ["SlotMOD"] = 1.0000, ["ItemSlot"] = 5, ["Enchantable"] = true },
    ["INVTYPE_WAIST"] = { ["SlotMOD"] = 0.7500, ["ItemSlot"] = 6, ["Enchantable"] = false },
    ["INVTYPE_LEGS"] = { ["SlotMOD"] = 1.0000, ["ItemSlot"] = 7, ["Enchantable"] = true },
    ["INVTYPE_FEET"] = { ["SlotMOD"] = 0.75, ["ItemSlot"] = 8, ["Enchantable"] = true },
    ["INVTYPE_WRIST"] = { ["SlotMOD"] = 0.5625, ["ItemSlot"] = 9, ["Enchantable"] = true },
    ["INVTYPE_HAND"] = { ["SlotMOD"] = 0.7500, ["ItemSlot"] = 10, ["Enchantable"] = true },
    ["INVTYPE_FINGER"] = { ["SlotMOD"] = 0.5625, ["ItemSlot"] = 31, ["Enchantable"] = false },
    ["INVTYPE_CLOAK"] = { ["SlotMOD"] = 0.5625, ["ItemSlot"] = 15, ["Enchantable"] = true },
    ["INVTYPE_BODY"] = { ["SlotMOD"] = 0, ["ItemSlot"] = 4, ["Enchantable"] = false },
}

local GS_Formula = {
    ["A"] = {
        [4] = { ["A"] = 91.4500, ["B"] = 0.6500 },
        [3] = { ["A"] = 81.3750, ["B"] = 0.8125 },
        [2] = { ["A"] = 73.0000, ["B"] = 1.0000 }
    },
    ["B"] = {
        [4] = { ["A"] = 26.0000, ["B"] = 1.2000 },
        [3] = { ["A"] = 0.7500, ["B"] = 1.8000 },
        [2] = { ["A"] = 8.0000, ["B"] = 2.0000 },
        [1] = { ["A"] = 0.0000, ["B"] = 2.2500 }
    },
    ["C"] = {
        [4] = { ["A"] = 0.2500, ["B"] = 1.6275 }
    },
}

local GS_Quality = {
    [BRACKET_SIZE]     = { r = 0.50, g = 0.50, b = 0.50, label = "Trash" },
    [BRACKET_SIZE * 2] = { r = 1.00, g = 1.00, b = 1.00, label = "Common" },
    [BRACKET_SIZE * 3] = { r = 0.12, g = 0.81, b = 0.04, label = "Uncommon" },
    [BRACKET_SIZE * 4] = { r = 0.12, g = 0.40, b = 0.83, label = "Superior" },
    [BRACKET_SIZE * 5] = { r = 0.63, g = 0.20, b = 0.83, label = "Epic" },
    [BRACKET_SIZE * 6] = { r = 1.00, g = 0.63, b = 0.00, label = "Legendary" },
    [BRACKET_SIZE * 7] = { r = 0.92, g = 0.10, b = 0.10, label = "Artifact" },
}

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

function TT_GS:GetQuality(ItemScore)
    ItemScore = tonumber(ItemScore)
    if (not ItemScore) then
        return 0.5, 0.5, 0.5, "Trash"
    end
    if (ItemScore > MAX_SCORE) then
        ItemScore = MAX_SCORE
    end
    for i = 0, 6 do
        if ((ItemScore > i * BRACKET_SIZE) and (ItemScore <= ((i + 1) * BRACKET_SIZE))) then
            local qColors = GS_Quality[(i + 1) * BRACKET_SIZE]
            return qColors.r, qColors.g, qColors.b, qColors.label
        end
    end
    return 0.5, 0.5, 0.5, "Trash"
end

-- Item colour band scale.
--
-- The colour of an ITEM tooltip must be a pure function of the number printed
-- beside it. It used not to be: the band was computed from the slot-mod-FREE
-- base -- the hardcoded `* 1` stood in for SlotMOD -- while the score shown to
-- the user multiplied that base by GS_ItemTypes[].SlotMOD. A 2H and a head of
-- identical item level therefore shared a colour while displaying different
-- scores, so the band never described the number next to it. Upstream GearScore
-- 3.1.20 decouples them the same way with 12.25; the constant change to 11.25
-- is ours, and the decoupling was carried over with it.
--
-- The ~11x rescale is kept deliberately. Applied to the raw score, a trinket at
-- a current item level would read as "Trash" -- the bands are sized for a
-- character total, and per-item scores are a different, smaller domain. Same
-- reason the character TOTAL in main.lua is passed to GetQuality unrescaled:
-- totals and items are separate domains and are NOT unified.
local ITEM_BAND_SCALE = 11.25

-- Resolves the raw item data GearScore needs from a pre-fetched GetItemInfo
-- result table. Callers that already hold the info (e.g. tooltip hooks) MUST
-- prefer TT_GS:GetItemScoreFromInfo so one hover performs exactly one
-- GetItemInfo call instead of one per scoring consumer.
-- @param info result of GetItemInfo(itemLink) (may be nil while uncached)
local function scoreFromItemValues(itemLinkOut, ItemRarity, ItemLevel, ItemEquipLoc, itemLinkFallback)
    if (not itemLinkOut and itemLinkFallback and RequestLoadItemDataByID) then
        local itemID = tonumber(string.match(itemLinkFallback, "item:(%d+)"))
        if (itemID) then
            pcall(RequestLoadItemDataByID, itemID)
        end
    end
    if (itemLinkOut and ItemRarity and ItemLevel and ItemEquipLoc and GS_ItemTypes[ItemEquipLoc]) then
        local Table
        local QualityScale = 1
        local GearScore
        local Scale = 1.8618
        if (ItemRarity == 5) then
            QualityScale = 1.3
            ItemRarity = 4
        elseif (ItemRarity == 1) then
            QualityScale = 0.005
            ItemRarity = 2
        elseif (ItemRarity == 0) then
            QualityScale = 0.005
            ItemRarity = 2
        elseif (ItemRarity == 7) then
            ItemRarity = 3
            ItemLevel = 187.05
        end
        if (ItemLevel < 100 and ItemRarity == 4) then
            Table = GS_Formula["C"]
        elseif (ItemLevel < 168 and ItemRarity == 4) then
            Table = GS_Formula["B"]
        elseif (ItemLevel < 148 and ItemRarity == 3) then
            Table = GS_Formula["B"]
        elseif (ItemLevel < 138 and ItemRarity == 2) then
            Table = GS_Formula["B"]
        elseif (ItemLevel <= 120) then
            Table = GS_Formula["B"]
        else
            Table = GS_Formula["A"]
        end
        if ((ItemRarity >= 2) and (ItemRarity <= 4)) then
            GearScore = floor(((ItemLevel - Table[ItemRarity].A) / Table[ItemRarity].B) *
                GS_ItemTypes[ItemEquipLoc].SlotMOD * Scale * QualityScale)
            -- Band from the score actually displayed, so the two can never
            -- disagree. Order matters: the clamp below rewrites GearScore, and
            -- the band is taken from the clamped value.
            local Red, Green, Blue = TT_GS:GetQuality(GearScore * ITEM_BAND_SCALE)
            if (ItemLevel == 187.05) then
                ItemLevel = 0
            end
            if (GearScore < 0) then
                GearScore = 0
                Red, Green, Blue = TT_GS:GetQuality(1)
            end
            return GearScore, ItemLevel, Red, Green, Blue, ItemEquipLoc
        end
    end
    return 0, 0, 0.1, 0.1, 0.1, 0
end

-- Resolves the raw item data GearScore needs from a pre-fetched GetItemInfo
-- result table. Callers that already hold the info (e.g. tooltip hooks) MUST
-- prefer TT_GS:GetItemScoreFromInfo so one hover performs exactly one
-- GetItemInfo call instead of one per scoring consumer.
-- @param info result of GetItemInfo(itemLink) (may be nil while uncached)
-- @return number gearScore, number itemLevel, number r, number g, number b, string|nil equipLoc
local function scoreFromItemInfo(info, itemLinkFallback)
    if (not info or type(info) ~= "table") then
        if (itemLinkFallback and RequestLoadItemDataByID) then
            local itemID = tonumber(string.match(itemLinkFallback, "item:(%d+)"))
            if (itemID) then
                pcall(RequestLoadItemDataByID, itemID)
            end
        end
        return 0, 0, 0.1, 0.1, 0.1, 0
    end
    return scoreFromItemValues(info[2], info[3], info[4], info[9], itemLinkFallback)
end

-- Public entry: score from a caller-provided GetItemInfo result table.
-- Performs no GetItemInfo call of its own; see scoreFromItemInfo.
function TT_GS:GetItemScoreFromInfo(info)
    return scoreFromItemInfo(info)
end

-- Public entry: score directly from an item link. Retained for callers
-- (frame overlays, tests) that do not already hold a GetItemInfo result.
function TT_GS:GetItemScore(ItemLink)
    if not (ItemLink) then
        return 0, 0, 0.1, 0.1, 0.1
    end
    local _, itemLinkOut, itemRarity, itemLevel, _, _, _, _, itemEquipLoc = GetItemInfo(ItemLink)
    return scoreFromItemValues(itemLinkOut, itemRarity, itemLevel, itemEquipLoc, ItemLink)
end

-- Hunter-adjusted score. Accepts an optional pre-fetched GetItemInfo table
-- so item-tooltip callers reuse one fetch across ilvl/GearScore/HunterScore.
function TT_GS:GetItemHunterScore(ItemLink, info)
    -- NOTE: no `info and A(...) or B(...)` shortcut here — and/or yields a
    -- single value, which would leave every score field after GearScore nil.
    local GearScore, ItemLevel, Red, Green, Blue, ItemEquipLoc
    if (info) then
        GearScore, ItemLevel, Red, Green, Blue, ItemEquipLoc = TT_GS:GetItemScoreFromInfo(info)
    else
        GearScore, ItemLevel, Red, Green, Blue, ItemEquipLoc = TT_GS:GetItemScore(ItemLink)
    end
    if (not GearScore or GearScore == 0) then
        return 0, ItemLevel or 0, Red or 0.1, Green or 0.1, Blue or 0.1, ItemEquipLoc
    end
    if ((ItemEquipLoc == "INVTYPE_2HWEAPON") or (ItemEquipLoc == "INVTYPE_WEAPONMAINHAND") or (ItemEquipLoc == "INVTYPE_WEAPONOFFHAND") or (ItemEquipLoc == "INVTYPE_WEAPON") or (ItemEquipLoc == "INVTYPE_HOLDABLE")) then
        GearScore = floor(GearScore * 0.3164)
    elseif ((ItemEquipLoc == "INVTYPE_RANGEDRIGHT") or (ItemEquipLoc == "INVTYPE_RANGED") or (ItemEquipLoc == "INVTYPE_THROWN")) then
        GearScore = floor(GearScore * 5.3224)
    end
    return GearScore, ItemLevel, Red, Green, Blue, ItemEquipLoc
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


function TT_GS:GetScore(unitorguid, useCallback)
    local guid = getPlayerGUID(unitorguid)
    if (guid) then
        if (guid ~= UnitGUID("player")) then
            local _, invTime = CI:GetLastCacheTime(guid)
            if (invTime == 0) then
                return 0, 0
            end
        end

        local ppOk, _, PlayerEnglishClass = pcall(GetPlayerInfoByGUID, guid)
        if (not ppOk) then
            PlayerEnglishClass = ""
        end
        local GearScore = 0
        local ItemCount = 0
        local LevelTotal = 0
        local TitanGrip = 1
        local IsReady = true

        local mainHandItem = CI:GetInventoryItemMixin(guid, 16)
        local offHandItem = CI:GetInventoryItemMixin(guid, 17)
        local mainHandLink
        local offHandLink

        local cb_table

        if (useCallback) then
            cb_table = { ["guid"] = guid, ["items"] = {} }
        end

        if (mainHandItem) then
            if (mainHandItem:IsItemDataCached()) then
                mainHandLink = mainHandItem:GetItemLink()
            else
                IsReady = false
                local itemID = mainHandItem:GetItemID()
                if (itemID) then
                    if (useCallback) then
                        -- Dedupe on insert: identical item ids (e.g. two
                        -- identical rings) must not occupy two list slots,
                        -- or the first callback drains both matches and the
                        -- second slot's callback completes on a drained list.
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
                        mainHandItem:ContinueOnItemLoad(function()
                            itemcacheCB(cb_table, itemID)
                        end)
                    elseif (RequestLoadItemDataByID) then
                        RequestLoadItemDataByID(itemID)
                    end
                end
            end
        end
        if (offHandItem) then
            if (offHandItem:IsItemDataCached()) then
                offHandLink = offHandItem:GetItemLink()
            else
                IsReady = false
                local itemID = offHandItem:GetItemID()
                if (itemID) then
                    if (useCallback) then
                        -- Same dedupe rule as the main-hand registration.
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
                        offHandItem:ContinueOnItemLoad(function()
                            itemcacheCB(cb_table, itemID)
                        end)
                    elseif (RequestLoadItemDataByID) then
                        RequestLoadItemDataByID(itemID)
                    end
                end
            end
        end

        -- Titan Grip: In WotLK, Fury Warriors can dual-wield 2-handed weapons.
        -- When an offhand item is equipped alongside a 2H weapon (or both are 2H),
        -- each 2H weapon is scaled by 0.5 (reducing SlotMOD from 2.0 to 1.0) so
        -- dual-wielding 2H weapons balances with 1H dual wielders (1.0 + 1.0 = 2.0).
        -- Standalone 2H weapons (no offhand equipped) retain full 2.0x weight.
        local OffHandTitanGrip = 1
        if (mainHandLink and offHandLink) then
            local mhEquipLoc = select(9, GetItemInfo(mainHandLink))
            local ohEquipLoc = select(9, GetItemInfo(offHandLink))
            if (mhEquipLoc == "INVTYPE_2HWEAPON") then
                TitanGrip = 0.5
            end
            if (ohEquipLoc == "INVTYPE_2HWEAPON") then
                OffHandTitanGrip = 0.5
            end
        end

        if (offHandLink) then
            local TempScore, ItemLevel = TT_GS:GetItemScore(offHandLink)
            if (PlayerEnglishClass == "HUNTER") then
                TempScore = TempScore * 0.3164
            end
            GearScore = GearScore + TempScore * OffHandTitanGrip
            ItemCount = ItemCount + 1
            LevelTotal = LevelTotal + ItemLevel
        end

        for i = 1, 18 do
            if (i ~= 4) and (i ~= 17) then
                local item = CI:GetInventoryItemMixin(guid, i)
                if (item) then
                    if (item:IsItemDataCached()) then
                        local TempScore, ItemLevel = TT_GS:GetItemScore(item:GetItemLink())
                        if (PlayerEnglishClass == "HUNTER") then
                            if (i == 16) then
                                TempScore = TempScore * 0.3164
                            elseif (i == 18) then
                                TempScore = TempScore * 5.3224
                            end
                        end
                        if (i == 16) then
                            TempScore = TempScore * TitanGrip
                        end
                        GearScore = GearScore + TempScore
                        ItemCount = ItemCount + 1
                        LevelTotal = LevelTotal + ItemLevel
                    else
                        IsReady = false
                        local itemID = item:GetItemID()
                        if (itemID) then
                            if (useCallback) then
                                -- Same dedupe rule as the weapon-slot
                                -- registrations above.
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
        if (IsReady and GearScore > 0 and ItemCount > 0) then
            return floor(GearScore), floor(LevelTotal / ItemCount)
        end
    end
    return 0, 0
end
