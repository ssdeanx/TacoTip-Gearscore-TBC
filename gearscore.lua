--[[

    TacoTip GearScore module by kebabstorm
    for Classic/TBC/WOTLK

    Based on original GearScoreLite by Mirrikat45 & others

    Module is WIP and currently part of TacoTip, but it will be released as a public module on a later date

--]]

local addOnName = ...

local interfaceVersion = select(4, GetBuildInfo()) or 0
local clientBuildMajor = math.floor(interfaceVersion / 10000)
-- load only on the Classic-era client families TacoTip supports (Vanilla/TBC/Wrath)
if (clientBuildMajor < 1 or clientBuildMajor > 3) then
    return
end

assert(LibStub, "TacoTip requires LibStub")
assert(LibStub:GetLibrary("LibClassicInspector", true), "TacoTip requires LibClassicInspector")
assert(LibStub:GetLibrary("LibDetours-1.0", true), "TacoTip requires LibDetours-1.0")

local CI = LibStub("LibClassicInspector")
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
            print("|cff59f0dcTacoTip:|r "..((L and L["Custom tooltip position disabled."]) or "Custom tooltip position disabled."))
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

local function fallbackGUIDIsPlayer(guid)
    return type(guid) == "string" and string.find(guid, "Player-", 1, true) == 1
end

local GUIDIsPlayer = (_G.C_PlayerInfo and _G.C_PlayerInfo.GUIDIsPlayer) or fallbackGUIDIsPlayer
local RequestLoadItemDataByID = _G.C_Item and _G.C_Item.RequestLoadItemDataByID
local floor = math.floor

_G.TT_GS = {}
local TT_GS = TT_GS

local BRACKET_SIZE = 1000

if (CI:IsWotlk()) then
    BRACKET_SIZE = 1000
elseif (CI:IsTBC()) then
    BRACKET_SIZE = 400
elseif (CI:IsClassic()) then
    BRACKET_SIZE = 200
end

local MAX_SCORE = BRACKET_SIZE * 7

local GS_ItemTypes = {
    ["INVTYPE_RELIC"] = { ["SlotMOD"] = 0.3164, ["ItemSlot"] = 18, ["Enchantable"] = false},
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
    [BRACKET_SIZE]      = { r = 0.50, g = 0.50, b = 0.50, label = "Trash" },
    [BRACKET_SIZE * 2]  = { r = 1.00, g = 1.00, b = 1.00, label = "Common" },
    [BRACKET_SIZE * 3]  = { r = 0.12, g = 0.81, b = 0.04, label = "Uncommon" },
    [BRACKET_SIZE * 4]  = { r = 0.12, g = 0.40, b = 0.83, label = "Superior" },
    [BRACKET_SIZE * 5]  = { r = 0.63, g = 0.20, b = 0.83, label = "Epic" },
    [BRACKET_SIZE * 6]  = { r = 1.00, g = 0.63, b = 0.00, label = "Legendary" },
    [BRACKET_SIZE * 7]  = { r = 0.92, g = 0.10, b = 0.10, label = "Artifact" },
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


function TT_GS:GetItemScore(ItemLink)
    if not (ItemLink) then
        return 0, 0, 0.1, 0.1, 0.1
    end
    local _, itemLinkOut, ItemRarity, ItemLevel, _, _, _, _, ItemEquipLoc = GetItemInfo(ItemLink)
    if (not itemLinkOut and RequestLoadItemDataByID) then
        local itemID = tonumber(string.match(tostring(ItemLink), "item:(%d+)"))
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
            local Red, Green, Blue = TT_GS:GetQuality((floor(((ItemLevel - Table[ItemRarity].A) / Table[ItemRarity].B) * 1 * Scale)) * 11.25)
            GearScore = floor(((ItemLevel - Table[ItemRarity].A) / Table[ItemRarity].B) * GS_ItemTypes[ItemEquipLoc].SlotMOD * Scale * QualityScale)
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

function TT_GS:GetItemHunterScore(ItemLink)
    local GearScore, ItemLevel, Red, Green, Blue, ItemEquipLoc = TT_GS:GetItemScore(ItemLink)
    if ((ItemEquipLoc == "INVTYPE_2HWEAPON") or (ItemEquipLoc == "INVTYPE_WEAPONMAINHAND") or (ItemEquipLoc == "INVTYPE_WEAPONOFFHAND") or (ItemEquipLoc == "INVTYPE_WEAPON") or (ItemEquipLoc == "INVTYPE_HOLDABLE")) then
        GearScore = floor(GearScore * 0.3164)
    elseif ((ItemEquipLoc == "INVTYPE_RANGEDRIGHT") or (ItemEquipLoc == "INVTYPE_RANGED")) then
        GearScore = floor(GearScore * 5.3224)
    end
    return GearScore, ItemLevel, Red, Green, Blue, ItemEquipLoc
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


function TT_GS:GetScore(unitorguid, useCallback)
    local guid = getPlayerGUID(unitorguid)
    if (guid) then
        if (guid ~= UnitGUID("player")) then
            local _, invTime = CI:GetLastCacheTime(guid)
            if(invTime == 0) then
                return 0,0
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
            cb_table = {["guid"] = guid, ["items"] = {}}
        end

        if (mainHandItem) then
            if (mainHandItem:IsItemDataCached()) then
                mainHandLink = mainHandItem:GetItemLink()
            else
                IsReady = false
                local itemID = mainHandItem:GetItemID()
                if (itemID) then
                    if (useCallback) then
                        table.insert(cb_table.items, itemID)
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
                        table.insert(cb_table.items, itemID)
                        offHandItem:ContinueOnItemLoad(function()
                            itemcacheCB(cb_table, itemID)
                        end)
                    elseif (RequestLoadItemDataByID) then
                        RequestLoadItemDataByID(itemID)
                    end
                end
            end
        end

        if (mainHandLink and offHandLink) then
            local ItemEquipLoc = select(9, GetItemInfo(mainHandLink))
            if (ItemEquipLoc == "INVTYPE_2HWEAPON") then
                TitanGrip = 0.5
            end
        end

        if (offHandLink) then
            local ItemEquipLoc = select(9, GetItemInfo(offHandLink))
            if (ItemEquipLoc == "INVTYPE_2HWEAPON") then
                TitanGrip = 0.5
            end
            local TempScore, ItemLevel = TT_GS:GetItemScore(offHandLink)
            if (PlayerEnglishClass == "HUNTER") then
                TempScore = TempScore * 0.3164
            end
            GearScore = GearScore + TempScore * TitanGrip
            ItemCount = ItemCount + 1
            LevelTotal = LevelTotal + ItemLevel
        end

        for i = 1, 18 do
            if ( i ~= 4 ) and ( i ~= 17 ) then
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
                        if ( i == 16 ) then
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
        if (IsReady and GearScore > 0 and ItemCount > 0) then
            return floor(GearScore), floor(LevelTotal/ItemCount)
        end
    end
    return 0,0
end

