GearScoreCalc = {}


GEAR_SCORE_CACHE = {}

-- Create frames for character and inspect windows
scoreFrame = nil
inspectScoreFrame = nil
local _, PLAYER_CLASS = UnitClass("player")

IS_MANUAL_INSPECT_ACTIVE = false
local fontPath = "Fonts\\FRIZQT__.TTF"  -- Standard WoW font
local BRACKET_SIZE = 400  -- TBC bracket size (Classic=200, TBC=400, WotLK=1000)
local MAX_GEAR_SCORE = BRACKET_SIZE * 6 - 1  -- 2399 for TBC
local GS_SCALE = 1.8618  -- GearScoreLite base scale factor
local GS_ENCHANT_MODIFIER = 1.05  -- 5% increase for enchanted items
local GS_GEM_SCORE_PER_GEM = 5    -- Flat score bonus per socketed gem
local TOOLTIP_DETAIL_INDENT = "   "
local SPONSOR_GUILD_NAME = "Everlasting Vendetta"
local SPONSOR_GUILD_RECRUITMENT = "Pala&Druid Heal and shadow priest"
local SPONSOR_NAMEPLATE_TEXT = "Addon Sponsor"
local SPONSOR_NAMEPLATE_RETRY_DELAY = 0.25
local SPONSOR_NAMEPLATE_MAX_RETRIES = 8
local SPONSOR_NAMEPLATES = {}
local MAX_RETRIES = 3
local INSPECT_RETRY_DELAY = 0.2
local INSPECT_RETRIES = {}
local TOTAL_EQUIPPABLE_SLOTS = 17
local ADDON_VERSION = "1.2.0"

print("|cFFFFFF00" .. "GearScoreTBCClassic+ " .. "|r" .. "|cFF00FF00" .. ADDON_VERSION .. "|r" .. "|cFFFFFF00" .. " by " .. "|r" .. "|cFFFFA500" .. "gk646" .. "|r")

local itemTypeInfo = {
    ["INVTYPE_RELIC"] = { 0.3164, false },
    ["INVTYPE_TRINKET"] = { 0.5625, false },
    ["INVTYPE_2HWEAPON"] = { 2.000, true },
    ["INVTYPE_WEAPONMAINHAND"] = { 1.0000, true },
    ["INVTYPE_WEAPONOFFHAND"] = { 1.0000, true },
    ["INVTYPE_RANGED"] = { 0.3164, true },
    ["INVTYPE_THROWN"] = { 0.3164, false },
    ["INVTYPE_RANGEDRIGHT"] = { 0.3164, true },
    ["INVTYPE_SHIELD"] = { 1.0000, true },
    ["INVTYPE_WEAPON"] = { 1.0000, true },
    ["INVTYPE_HOLDABLE"] = { 1.0000, false },
    ["INVTYPE_HEAD"] = { 1.0000, true },
    ["INVTYPE_NECK"] = { 0.5625, false },
    ["INVTYPE_SHOULDER"] = { 0.7500, true },
    ["INVTYPE_CHEST"] = { 1.0000, true },
    ["INVTYPE_ROBE"] = { 1.0000, true },
    ["INVTYPE_WAIST"] = { 0.7500, false },
    ["INVTYPE_LEGS"] = { 1.0000, true },
    ["INVTYPE_FEET"] = { 0.75, true },
    ["INVTYPE_WRIST"] = { 0.5625, true },
    ["INVTYPE_HAND"] = { 0.7500, true },
    ["INVTYPE_FINGER"] = { 0.5625, false },
    ["INVTYPE_CLOAK"] = { 0.5625, true },
    ["INVTYPE_BODY"] = { 0, false },
    ["INVTYPE_TABARD"] = { 0, false },
    ["INVTYPE_AMMO"] = { 0, false },
    ["INVTYPE_BAG"] = { 0, false },
}

local equipmentSlotsByType = {
    ["INVTYPE_HEAD"] = { 1 },
    ["INVTYPE_NECK"] = { 2 },
    ["INVTYPE_SHOULDER"] = { 3 },
    ["INVTYPE_BODY"] = { 4 },
    ["INVTYPE_CHEST"] = { 5 },
    ["INVTYPE_ROBE"] = { 5 },
    ["INVTYPE_WAIST"] = { 6 },
    ["INVTYPE_LEGS"] = { 7 },
    ["INVTYPE_FEET"] = { 8 },
    ["INVTYPE_WRIST"] = { 9 },
    ["INVTYPE_HAND"] = { 10 },
    ["INVTYPE_FINGER"] = { 11, 12 },
    ["INVTYPE_TRINKET"] = { 13, 14 },
    ["INVTYPE_CLOAK"] = { 15 },
    ["INVTYPE_WEAPON"] = { 16, 17 },
    ["INVTYPE_WEAPONMAINHAND"] = { 16 },
    ["INVTYPE_2HWEAPON"] = { 16, 17 },
    ["INVTYPE_WEAPONOFFHAND"] = { 17 },
    ["INVTYPE_SHIELD"] = { 17 },
    ["INVTYPE_HOLDABLE"] = { 17 },
    ["INVTYPE_RANGED"] = { 18 },
    ["INVTYPE_THROWN"] = { 18 },
    ["INVTYPE_RANGEDRIGHT"] = { 18 },
    ["INVTYPE_RELIC"] = { 18 },
    ["INVTYPE_TABARD"] = { 19 },
}

local socketStatKeys = {
    "EMPTY_SOCKET_META",
    "EMPTY_SOCKET_RED",
    "EMPTY_SOCKET_YELLOW",
    "EMPTY_SOCKET_BLUE",
    "EMPTY_SOCKET_PRISMATIC",
}

local enchantableRangedSubclasses = {
    [2] = true,  -- Bows
    [3] = true,  -- Guns
    [18] = true, -- Crossbows
}

-- Single linear formula table (no hard item level breakpoint).
local GS_Formula = {
    [4] = { A = 26.0000, B = 1.2000 },
    [3] = { A = 0.7500, B = 1.8000 },
    [2] = { A = 8.0000, B = 2.0000 },
    [1] = { A = 0.0000, B = 2.2500 },
}

-- GearScoreLite bracket-based color quality table
local GS_Quality = {
    [BRACKET_SIZE * 6] = {
        Red = { A = 0.94, B = BRACKET_SIZE * 5, C = 0.00006, D = 1 },
        Green = { A = 0, B = 0, C = 0, D = 0 },
        Blue = { A = 0.47, B = BRACKET_SIZE * 5, C = 0.00047, D = -1 },
        Description = "Legendary"
    },
    [BRACKET_SIZE * 5] = {
        Red = { A = 0.69, B = BRACKET_SIZE * 4, C = 0.00025, D = 1 },
        Green = { A = 0.97, B = BRACKET_SIZE * 4, C = 0.00096, D = -1 },
        Blue = { A = 0.28, B = BRACKET_SIZE * 4, C = 0.00019, D = 1 },
        Description = "Epic"
    },
    [BRACKET_SIZE * 4] = {
        Red = { A = 0.0, B = BRACKET_SIZE * 3, C = 0.00069, D = 1 },
        Green = { A = 1, B = BRACKET_SIZE * 3, C = 0.00003, D = -1 },
        Blue = { A = 0.5, B = BRACKET_SIZE * 3, C = 0.00022, D = -1 },
        Description = "Superior"
    },
    [BRACKET_SIZE * 3] = {
        Red = { A = 0.12, B = BRACKET_SIZE * 2, C = 0.00012, D = -1 },
        Green = { A = 0, B = BRACKET_SIZE * 2, C = 0.001, D = 1 },
        Blue = { A = 1, B = BRACKET_SIZE * 2, C = 0.00050, D = -1 },
        Description = "Uncommon"
    },
    [BRACKET_SIZE * 2] = {
        Red = { A = 1, B = BRACKET_SIZE, C = 0.00088, D = -1 },
        Green = { A = 1, B = BRACKET_SIZE, C = 0.001, D = -1 },
        Blue = { A = 1, B = 0, C = 0.00000, D = 0 },
        Description = "Common"
    },
    [BRACKET_SIZE] = {
        Red = { A = 0.55, B = 0, C = 0.00045, D = 1 },
        Green = { A = 0.55, B = 0, C = 0.00045, D = 1 },
        Blue = { A = 0.55, B = 0, C = 0.00045, D = 1 },
        Description = "Trash"
    },
}

local DEFAULT_CHAR_POS = { x = 73, y = 240 }
local DEFAULT_INSPECT_POS = { x = 73, y = 145 }
local isUnlocked = false

local function CreateGearScoreFrame(name, parentFrame, defaultX, defaultY)
    local frame = CreateFrame("Frame", name, parentFrame)
    frame:SetSize(220, 50)
    frame:SetPoint("BOTTOMLEFT", parentFrame, "BOTTOMLEFT", defaultX, defaultY)

    -- Highlight shown only while the frame is unlocked for movement.
    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetPoint("LEFT", frame, "LEFT", 5, 0)
    frame.bg:SetPoint("RIGHT", frame, "RIGHT", -5, 0)
    frame.bg:SetHeight(24)
    frame.bg:SetColorTexture(1, 0.82, 0, 0.14)
    frame.bg:Hide()

    frame.scoreValueText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.scoreValueText:SetFont(fontPath, 14)
    frame.scoreValueText:SetTextColor(1, 1, 1)
    frame.scoreValueText:SetPoint("RIGHT", frame, "CENTER", -5, 0)

    frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.text:SetFont(fontPath, 11)
    frame.text:SetTextColor(1, 0.82, 0)
    frame.text:SetPoint("RIGHT", frame.scoreValueText, "LEFT", -4, 0)
    frame.text:SetText("GearScore:")

    frame.avgItemLevelLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.avgItemLevelLabel:SetFont(fontPath, 11)
    frame.avgItemLevelLabel:SetTextColor(1, 0.82, 0)
    frame.avgItemLevelLabel:SetPoint("LEFT", frame, "CENTER", 20, 0)
    frame.avgItemLevelLabel:SetText("iLvl:")

    frame.avgItemLevelText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.avgItemLevelText:SetFont(fontPath, 13)
    frame.avgItemLevelText:SetTextColor(1, 1, 1)
    frame.avgItemLevelText:SetPoint("LEFT", frame.avgItemLevelLabel, "RIGHT", 4, 0)

    -- Draggable setup (mouse disabled by default, enabled via /gs)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(false)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Reanchor relative to parent
        local parent = self:GetParent()
        if parent and parent:GetLeft() and self:GetLeft() then
            local x = self:GetLeft() - parent:GetLeft()
            local y = self:GetBottom() - parent:GetBottom()
            self:ClearAllPoints()
            self:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x, y)
        end
    end)

    return frame
end

scoreFrame = CreateGearScoreFrame("GearScoreDisplay", PaperDollFrame, DEFAULT_CHAR_POS.x, DEFAULT_CHAR_POS.y)
inspectScoreFrame = CreateGearScoreFrame("InspectGearScoreDisplay", InspectFrame, DEFAULT_INSPECT_POS.x, DEFAULT_INSPECT_POS.y)

-- Position management
local function SaveFramePosition(frame, key)
    if not GearScoreTBCClassicDB or not frame:GetLeft() then return end
    local parent = frame:GetParent()
    if not parent or not parent:GetLeft() then return end
    local x = frame:GetLeft() - parent:GetLeft()
    local y = frame:GetBottom() - parent:GetBottom()
    GearScoreTBCClassicDB[key] = { x = x, y = y }
end

local function RestoreFramePosition(frame, key)
    if not GearScoreTBCClassicDB then return end
    local pos = GearScoreTBCClassicDB[key]
    if pos and pos.x and pos.y then
        frame:ClearAllPoints()
        frame:SetPoint("BOTTOMLEFT", frame:GetParent(), "BOTTOMLEFT", pos.x, pos.y)
    end
end

function GearScoreCalc.InitSavedVars()
    if not GearScoreTBCClassicDB then
        GearScoreTBCClassicDB = {}
    end
    if GearScoreTBCClassicDB.showTooltipDetails == nil then
        GearScoreTBCClassicDB.showTooltipDetails = false
    end
    RestoreFramePosition(scoreFrame, "characterPos")
    if inspectScoreFrame and InspectFrame then
        RestoreFramePosition(inspectScoreFrame, "inspectPos")
    end
end

function GearScoreCalc.CreateOptionsPanel()
    if GearScoreTBCClassicOptionsPanel then return end

    local panel = CreateFrame("Frame", "GearScoreTBCClassicOptionsPanel")
    panel.name = "GearScoreTBCClassic"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("GearScoreTBCClassic")

    local description = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    description:SetWidth(600)
    description:SetJustifyH("LEFT")
    description:SetText("Choose how much GearScore information is shown in item tooltips.")

    local checkbox = CreateFrame("CheckButton", "GearScoreTBCClassicShowTooltipDetailsCheckButton", panel,
        "InterfaceOptionsCheckButtonTemplate")
    checkbox:SetPoint("TOPLEFT", description, "BOTTOMLEFT", -2, -16)
    _G[checkbox:GetName() .. "Text"]:SetText("Show detailed item GearScore tooltip")
    checkbox:SetScript("OnClick", function(self)
        GearScoreTBCClassicDB.showTooltipDetails = self:GetChecked() and true or false
    end)

    panel:SetScript("OnShow", function()
        checkbox:SetChecked(GearScoreTBCClassicDB and GearScoreTBCClassicDB.showTooltipDetails)
    end)

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

local function SetUnlocked(unlock)
    isUnlocked = unlock
    local frames = { scoreFrame }
    if inspectScoreFrame then
        table.insert(frames, inspectScoreFrame)
    end
    for _, frame in ipairs(frames) do
        frame:EnableMouse(unlock)
        if unlock then
            frame.bg:Show()
            frame:SetFrameStrata("DIALOG")
        else
            frame.bg:Hide()
            frame:SetFrameStrata("MEDIUM")
        end
    end
    if not unlock then
        SaveFramePosition(scoreFrame, "characterPos")
        if inspectScoreFrame and InspectFrame then
            SaveFramePosition(inspectScoreFrame, "inspectPos")
        end
    end
end

local function ResetPositions()
    scoreFrame:ClearAllPoints()
    scoreFrame:SetPoint("BOTTOMLEFT", PaperDollFrame, "BOTTOMLEFT", DEFAULT_CHAR_POS.x, DEFAULT_CHAR_POS.y)
    if inspectScoreFrame and InspectFrame then
        inspectScoreFrame:ClearAllPoints()
        inspectScoreFrame:SetPoint("BOTTOMLEFT", InspectFrame, "BOTTOMLEFT", DEFAULT_INSPECT_POS.x, DEFAULT_INSPECT_POS.y)
    end
    if GearScoreTBCClassicDB then
        GearScoreTBCClassicDB.characterPos = nil
        GearScoreTBCClassicDB.inspectPos = nil
    end
    print("|cFFFFFF00GearScore:|r Position reset to default.")
end

-- Slash commands
SLASH_GEARSCORE1 = "/gs"
SLASH_GEARSCORE2 = "/gearscore"
SlashCmdList["GEARSCORE"] = function(msg)
    msg = string.lower(strtrim(msg or ""))
    if msg == "reset" then
        ResetPositions()
        if isUnlocked then
            SetUnlocked(false)
        end
    elseif msg == "unlock" or msg == "move" then
        SetUnlocked(true)
        print("|cFFFFFF00GearScore:|r Unlocked. Drag to reposition, then type |cFF00FF00/gs lock|r to save.")
    elseif msg == "lock" then
        SetUnlocked(false)
        print("|cFFFFFF00GearScore:|r Position locked.")
    else
        -- Toggle unlock/lock
        if isUnlocked then
            SetUnlocked(false)
            print("|cFFFFFF00GearScore:|r Position locked.")
        else
            SetUnlocked(true)
            print("|cFFFFFF00GearScore:|r Unlocked. Open character panel and drag to reposition. Type |cFF00FF00/gs|r to lock.")
        end
    end
end


-- GearScoreLite bracket-based color interpolation
local function GetGearScoreColor(gearScore)
    if not gearScore or gearScore <= 0 then
        return 0.55, 0.55, 0.55, "Trash"
    end
    if gearScore > MAX_GEAR_SCORE then
        gearScore = MAX_GEAR_SCORE
    end
    for i = 0, 5 do
        if gearScore > i * BRACKET_SIZE and gearScore <= (i + 1) * BRACKET_SIZE then
            local bracket = GS_Quality[(i + 1) * BRACKET_SIZE]
            local r = bracket.Red.A + ((gearScore - bracket.Red.B) * bracket.Red.C) * bracket.Red.D
            -- Note: Green/Blue swap preserved from original GearScoreLite
            local g = bracket.Blue.A + ((gearScore - bracket.Blue.B) * bracket.Blue.C) * bracket.Blue.D
            local b = bracket.Green.A + ((gearScore - bracket.Green.B) * bracket.Green.C) * bracket.Green.D
            return r, g, b, bracket.Description
        end
    end
    return 0.55, 0.55, 0.55, "Trash"
end

-- Returns in r g b values from 0.0 - 1.0
local function GetColorForGearScore(gearScore)
    local r, g, b = GetGearScoreColor(gearScore)
    return r, g, b
end

-- Returns the color string which can be used in text formatting
local function GetColorForGearScoreText(gearScore)
    local r, g, b = GetGearScoreColor(gearScore)
    return string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
end

-- Tries to find the enchant id from an itemLink
local function GetEnchantIDFromItemLink(itemLink)
    local enchantID = itemLink:match("item:%d+:(%d+)")
    return tonumber(enchantID)  -- Convert to number, will be nil if no enchantment
end

-- Counts the number of gems socketed in an item from its itemLink
-- Item link format: item:itemID:enchantID:gemID1:gemID2:gemID3:gemID4:...
local function GetGemCountFromItemLink(itemLink)
    local gemCount = 0
    local gem1, gem2, gem3 = itemLink:match("item:%d+:%d*:(%d*):(%d*):(%d*)")
    if gem1 and gem1 ~= "" and tonumber(gem1) > 0 then gemCount = gemCount + 1 end
    if gem2 and gem2 ~= "" and tonumber(gem2) > 0 then gemCount = gemCount + 1 end
    if gem3 and gem3 ~= "" and tonumber(gem3) > 0 then gemCount = gemCount + 1 end
    return gemCount
end

local function GetSocketCount(itemLink)
    local itemStats = GetItemStats(itemLink)
    if not itemStats then
        return 0
    end

    local socketCount = 0
    for _, statKey in ipairs(socketStatKeys) do
        socketCount = socketCount + (itemStats[statKey] or 0)
    end
    return socketCount
end

local function GetEnchantPolicy(itemLink, itemEquipLoc, defaultEnchantable)
    -- Ring enchants are profession-only: count an existing enchant, but do not flag one as missing.
    if itemEquipLoc == "INVTYPE_FINGER" then
        return true, false
    end

    if itemEquipLoc == "INVTYPE_RANGED" or itemEquipLoc == "INVTYPE_RANGEDRIGHT" then
        local _, _, _, _, _, itemClassID, itemSubClassID = GetItemInfoInstant(itemLink)
        local canBeScoped = itemClassID == 2 and enchantableRangedSubclasses[itemSubClassID] == true
        return canBeScoped, canBeScoped
    end

    return defaultEnchantable, defaultEnchantable
end

-- Calculates the score of a single individual item (based on GearScoreLite formula)
local function CalculateItemScore(itemLink, classToken)
    if not itemLink then
        return 0, 0, 0, 0, 0, false, false, 0
    end

    local itemName, _, itemRarity, itemLevel, _, _, _, _, itemEquipLoc = GetItemInfo(itemLink)

    -- If data is not ready, retry later
    if not itemName or not itemRarity or not itemLevel or not itemEquipLoc then
        C_Timer.After(0.2, function()
            CalculateItemScore(itemLink, classToken)
        end)
        return 0, 0, 0, 0, 0, false, false, 0
    end

    local slotData = itemTypeInfo[itemEquipLoc]
    if not slotData then
        return 0, 0, 0, 0, 0, false, false, 0
    end

    local slotModifier = slotData[1]
    local supportsEnchant, showMissingEnchant = GetEnchantPolicy(itemLink, itemEquipLoc, slotData[2])

    -- Rarity adjustments (from GearScoreLite)
    local qualityScale = 1
    local isHeirloom = false
    if itemRarity == 5 then        -- Legendary
        qualityScale = 1.3
        itemRarity = 4
    elseif itemRarity == 1 then    -- Common
        qualityScale = 0.005
        itemRarity = 2
    elseif itemRarity == 0 then    -- Poor
        qualityScale = 0.005
        itemRarity = 2
    elseif itemRarity == 7 then    -- Heirloom
        itemRarity = 3
        itemLevel = 187.05
        isHeirloom = true
    end

    local formula = GS_Formula[itemRarity]
    if itemRarity < 2 or itemRarity > 4 or not formula then
        return 0, itemLevel, 0, 0, 0, false, false, 0
    end

    local gearScore = math.floor(
        ((itemLevel - formula.A) / formula.B) * slotModifier * GS_SCALE * qualityScale
    )

    -- Reset heirloom item level for avg calculation
    if isHeirloom then
        itemLevel = 0
    end

    if gearScore < 0 then
        gearScore = 0
    end

    -- Hunter class adjustments (from GearScoreLite)
    if classToken == "HUNTER" then
        if itemEquipLoc == "INVTYPE_2HWEAPON" or itemEquipLoc == "INVTYPE_WEAPONMAINHAND"
            or itemEquipLoc == "INVTYPE_WEAPONOFFHAND" or itemEquipLoc == "INVTYPE_WEAPON"
            or itemEquipLoc == "INVTYPE_HOLDABLE" then
            gearScore = math.floor(gearScore * 0.3164)
        elseif itemEquipLoc == "INVTYPE_RANGED" or itemEquipLoc == "INVTYPE_RANGEDRIGHT" then
            gearScore = math.floor(gearScore * 5.3224)
        end
    end

    local baseGearScore = gearScore

    -- Enchant bonus (addon enhancement)
    local enchantID
    if supportsEnchant then
        enchantID = GetEnchantIDFromItemLink(itemLink)
    end
    local hasEnchant = enchantID ~= nil and enchantID > 0
    if hasEnchant then
        gearScore = math.floor(gearScore * GS_ENCHANT_MODIFIER)
    end
    local enchantBonus = gearScore - baseGearScore

    -- Gem bonus (addon enhancement)
    local gemCount = GetGemCountFromItemLink(itemLink)
    local gemBonus = gemCount * GS_GEM_SCORE_PER_GEM
    gearScore = gearScore + gemBonus
    local socketCount = math.max(GetSocketCount(itemLink), gemCount)

    return gearScore, itemLevel, baseGearScore, enchantBonus, gemCount, hasEnchant, showMissingEnchant, socketCount
end


local function GetEquippedItemScore(slotID)
    local itemLink = GetInventoryItemLink("player", slotID)
    if not itemLink then
        return 0
    end

    local score = CalculateItemScore(itemLink, PLAYER_CLASS)
    return score
end


local function GetEquippedComparisonScore(itemEquipLoc)
    local slots = equipmentSlotsByType[itemEquipLoc]
    if not slots then
        return nil
    end

    local mainHandItemLink = GetInventoryItemLink("player", 16)
    local mainHandEquipLoc
    if mainHandItemLink then
        local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(mainHandItemLink)
        mainHandEquipLoc = equipLoc
    end

    -- A two-hand weapon, or an off-hand equipped beside one, replaces the full weapon setup.
    local replacesBothWeaponSlots = itemEquipLoc == "INVTYPE_2HWEAPON"
        or (mainHandEquipLoc == "INVTYPE_2HWEAPON"
            and (itemEquipLoc == "INVTYPE_WEAPON"
                or itemEquipLoc == "INVTYPE_WEAPONOFFHAND"
                or itemEquipLoc == "INVTYPE_SHIELD"
                or itemEquipLoc == "INVTYPE_HOLDABLE"))

    if replacesBothWeaponSlots then
        return GetEquippedItemScore(16) + GetEquippedItemScore(17)
    end

    if itemEquipLoc == "INVTYPE_WEAPON" and (not CanDualWield or not CanDualWield()) then
        return GetEquippedItemScore(16)
    end

    local equippedScore = GetEquippedItemScore(slots[1])
    for i = 2, #slots do
        equippedScore = math.min(equippedScore, GetEquippedItemScore(slots[i]))
    end

    return equippedScore
end

local function CalculateGearScoreAndAverageItemLevel(unit)
    local totalScore = 0
    local totalItemLevel = 0
    local itemMissing = false
    local _, classToken = UnitClass(unit)
    local mainHandItemLink = nil
    local mainHandItemLevel = 0

    -- Loop through all the equipment slots
    for i = 1, 19 do
        -- Skip the body (shirt, slot 4) and tabard (slot 19)
        if i ~= 4 and i ~= 19 then
            local itemLink = GetInventoryItemLink(unit, i)
            if itemLink then
                local itemScore, iLevel = CalculateItemScore(itemLink, classToken)
                totalScore = totalScore + itemScore
                if iLevel and iLevel > 0 then
                    totalItemLevel = totalItemLevel + iLevel
                end
                if i == 16 then -- Main hand slot
                    mainHandItemLink = itemLink
                    mainHandItemLevel = iLevel or 0
                end
            else
                -- Check if the slot is not legitimately empty
                local itemID = GetInventoryItemID(unit, i)
                if itemID then
                    itemMissing = true
                end
            end
        end
    end

    local offHandItemLink = GetInventoryItemLink(unit, 17)
    if not offHandItemLink and mainHandItemLink and mainHandItemLevel > 0 then
        local _, _, _, _, _, _, _, _, mainHandEquipLoc = GetItemInfo(mainHandItemLink)
        -- Count a two-hand weapon for both weapon slots so avg ilvl stays stable.
        if mainHandEquipLoc == "INVTYPE_2HWEAPON" then
            totalItemLevel = totalItemLevel + mainHandItemLevel
        end
    end

    local avgItemLevel = (totalItemLevel / TOTAL_EQUIPPABLE_SLOTS) or 0
    return totalScore, avgItemLevel, itemMissing
end

local function CalculateAndCacheGearScore(unit)
    local gearScore, avgItemLevel, itemMissing = CalculateGearScoreAndAverageItemLevel(unit)
    local guid = UnitGUID(unit)
    if guid and gearScore and avgItemLevel then
        local cachedData = GEAR_SCORE_CACHE[guid]
        if not cachedData or cachedData[1] ~= gearScore or cachedData[2] ~= avgItemLevel then
            -- Update cache if it's a new entry or if the gear score or avg item level has changed
            GEAR_SCORE_CACHE[guid] = { gearScore, avgItemLevel }
        end
    end
    return gearScore, avgItemLevel, itemMissing
end

function GearScoreCalc.OnInspectFrameShow()
    IS_MANUAL_INSPECT_ACTIVE = true
end

function GearScoreCalc.OnInspectFrameHide()
    IS_MANUAL_INSPECT_ACTIVE = false
end

function GearScoreCalc.UpdateFrame(frame, unit)
    local score, avgItemLevel, _ = CalculateAndCacheGearScore(unit)
    local r, g, b = GetColorForGearScore(score)

    -- Set the numerical gear score with color
    frame.scoreValueText:SetTextColor(r, g, b)
    frame.scoreValueText:SetText(math.floor(score + 0.5))

    -- Set the average item level text
    frame.avgItemLevelText:SetText(math.floor(avgItemLevel + 0.5))
end

function GearScoreCalc.OnPlayerEquipmentChanged()
    GearScoreCalc.UpdateFrame(scoreFrame, "player")
end

function GearScoreCalc.AddGearScoreToTooltip(tooltip, unit)
    if unit then
        local guid = UnitGUID(unit)
        local gearScore, avgItemLevel

        -- Get cached data
        local cachedData = GEAR_SCORE_CACHE[guid]
        if cachedData then
            gearScore, avgItemLevel = unpack(cachedData)
        end

        -- Display the gearscore
        if gearScore and gearScore > 0 then
            local color = GetColorForGearScoreText(gearScore)
            tooltip:AddLine("Gear Score: " .. color .. math.floor(gearScore + 0.5))
            tooltip:Show()  -- Force tooltip to refresh
        end
    end
end

local function IsSponsorGuild(guildName)
    return guildName
        and string.lower(strtrim(guildName)) == string.lower(strtrim(SPONSOR_GUILD_NAME))
end

function GearScoreCalc.AddSponsorToTooltip(tooltip, unit)
    if not tooltip or not unit or not IsSponsorGuild(GetGuildInfo(unit)) then return end

    local unitKey = UnitGUID(unit) or UnitName(unit)
    if unitKey and tooltip.gearScoreSponsorUnit == unitKey then
        return
    end
    tooltip.gearScoreSponsorUnit = unitKey

    tooltip:AddLine("Official Sponsor of GearScoreTBCClassic+", 1, 0.82, 0)
    if SPONSOR_GUILD_RECRUITMENT and strtrim(SPONSOR_GUILD_RECRUITMENT) ~= "" then
        tooltip:AddLine("|cffffd100Currently recruiting:|r " .. strtrim(SPONSOR_GUILD_RECRUITMENT), 1, 1, 1, true)
    end
    tooltip:Show()
end

local function GetSponsorNameplateBadge(namePlate)
    if namePlate.gearScoreSponsorBadge then
        return namePlate.gearScoreSponsorBadge
    end

    local badge = namePlate:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    badge:SetFont(fontPath, 10, "OUTLINE")
    badge:SetTextColor(1, 0.82, 0)
    badge:SetText(SPONSOR_NAMEPLATE_TEXT)
    badge:SetPoint("BOTTOM", namePlate, "TOP", 0, 2)
    badge:Hide()
    namePlate.gearScoreSponsorBadge = badge
    return badge
end

function GearScoreCalc.OnNamePlateUnitAdded(unit, attempt)
    if not unit or not UnitExists(unit) or not UnitIsPlayer(unit) or not C_NamePlate then return end

    local namePlate = C_NamePlate.GetNamePlateForUnit(unit)
    if not namePlate or (namePlate.IsForbidden and namePlate:IsForbidden()) then return end

    SPONSOR_NAMEPLATES[unit] = namePlate
    local badge = GetSponsorNameplateBadge(namePlate)
    local guildName = GetGuildInfo(unit)
    if IsSponsorGuild(guildName) then
        badge:Show()
        return
    end

    badge:Hide()
    attempt = attempt or 0
    if not guildName and attempt < SPONSOR_NAMEPLATE_MAX_RETRIES then
        local guid = UnitGUID(unit)
        C_Timer.After(SPONSOR_NAMEPLATE_RETRY_DELAY, function()
            if SPONSOR_NAMEPLATES[unit] == namePlate and UnitGUID(unit) == guid then
                GearScoreCalc.OnNamePlateUnitAdded(unit, attempt + 1)
            end
        end)
    end
end

function GearScoreCalc.OnNamePlateUnitRemoved(unit)
    local namePlate = SPONSOR_NAMEPLATES[unit]
    if namePlate and namePlate.gearScoreSponsorBadge then
        namePlate.gearScoreSponsorBadge:Hide()
    end
    SPONSOR_NAMEPLATES[unit] = nil
end

function GearScoreCalc.OnInspectReady(inspectGUID)
    if lastInspection and UnitGUID(lastInspection) == inspectGUID then
        local gs, avg, itemMissing = CalculateGearScoreAndAverageItemLevel(lastInspection)

        if itemMissing then
            INSPECT_RETRIES[inspectGUID] = (INSPECT_RETRIES[inspectGUID] or 0) + 1

            if INSPECT_RETRIES[inspectGUID] <= MAX_RETRIES then
                C_Timer.After(INSPECT_RETRY_DELAY, function()
                    if lastInspection then
                        NotifyInspect(lastInspection)
                    end
                end)
            else
                GEAR_SCORE_CACHE[inspectGUID] = { gs, avg }
                GearScoreCalc.AddGearScoreToTooltip(GameTooltip, lastInspection)
                lastInspection = nil
                INSPECT_RETRIES[inspectGUID] = nil
            end
        else
            GEAR_SCORE_CACHE[inspectGUID] = { gs, avg }
            GearScoreCalc.AddGearScoreToTooltip(GameTooltip, lastInspection)
            INSPECT_RETRIES[inspectGUID] = nil
        end
    end
end

function GearScoreCalc.AppendItemScoreToTooltip(tooltip)
    local _, itemLink = tooltip:GetItem()
    if itemLink and IsEquippableItem(itemLink) then
        local score, itemLevel, baseScore, enchantBonus, gemCount, hasEnchant, showMissingEnchant, socketCount =
            CalculateItemScore(itemLink, PLAYER_CLASS)
        local _, _, _, _, _, _, _, _, itemEquipLoc = GetItemInfo(itemLink)
        if score and itemLevel and itemEquipLoc then
            tooltip:AddLine("GearScore: " .. math.floor(score))
            if GearScoreTBCClassicDB and GearScoreTBCClassicDB.showTooltipDetails then
                tooltip:AddLine(TOOLTIP_DETAIL_INDENT .. "Base: " .. math.floor(baseScore) .. " GS")
                if hasEnchant then
                    tooltip:AddLine(TOOLTIP_DETAIL_INDENT .. "Enchant: |cff00ff00+" .. enchantBonus .. " GS|r")
                elseif showMissingEnchant then
                    local missingEnchantBonus = math.floor(baseScore * GS_ENCHANT_MODIFIER) - baseScore
                    tooltip:AddLine(TOOLTIP_DETAIL_INDENT .. "Enchant: |cffff4040-" .. missingEnchantBonus .. " GS (missing)|r")
                end

                if socketCount > 0 then
                    local gemBonus = gemCount * GS_GEM_SCORE_PER_GEM
                    local missingGemCount = socketCount - gemCount
                    if missingGemCount == 0 then
                        tooltip:AddLine(TOOLTIP_DETAIL_INDENT .. "Gems: |cff00ff00+" .. gemBonus .. " GS ("
                            .. gemCount .. " x " .. GS_GEM_SCORE_PER_GEM .. ")|r")
                    elseif gemCount == 0 then
                        local missingGemBonus = missingGemCount * GS_GEM_SCORE_PER_GEM
                        tooltip:AddLine(TOOLTIP_DETAIL_INDENT .. "Gems: |cffff4040-" .. missingGemBonus
                            .. " GS missing (" .. missingGemCount .. " x " .. GS_GEM_SCORE_PER_GEM .. ")|r")
                    else
                        local missingGemBonus = missingGemCount * GS_GEM_SCORE_PER_GEM
                        tooltip:AddLine(TOOLTIP_DETAIL_INDENT .. "Gems: |cff00ff00+" .. gemBonus .. " GS ("
                            .. gemCount .. " x " .. GS_GEM_SCORE_PER_GEM .. ")|r, |cffff4040-" .. missingGemBonus
                            .. " GS missing (" .. missingGemCount .. " x " .. GS_GEM_SCORE_PER_GEM .. ")|r")
                    end
                end
                tooltip:AddLine(TOOLTIP_DETAIL_INDENT .. "iLvl: " .. itemLevel)

                local equippedScore = GetEquippedComparisonScore(itemEquipLoc)
                if equippedScore then
                    local currentTotalScore = CalculateGearScoreAndAverageItemLevel("player")
                    local scoreDifference = score - equippedScore
                    local newTotalScore = currentTotalScore + scoreDifference

                    tooltip:AddLine(TOOLTIP_DETAIL_INDENT .. "Equipped: " .. math.floor(equippedScore) .. " GS")
                    if scoreDifference > 0 then
                        tooltip:AddLine(TOOLTIP_DETAIL_INDENT .. "Upgrade: |cff00ff00+" .. math.floor(scoreDifference) .. " GS|r")
                    elseif scoreDifference < 0 then
                        tooltip:AddLine(TOOLTIP_DETAIL_INDENT .. "Loss: |cffff4040" .. math.floor(scoreDifference) .. " GS|r")
                    else
                        tooltip:AddLine(TOOLTIP_DETAIL_INDENT .. "No change: |cff9d9d9d0 GS|r")
                    end
                    tooltip:AddLine(TOOLTIP_DETAIL_INDENT .. "New total: " .. math.floor(newTotalScore) .. " GS")
                end
            end
            tooltip:Show()
        end
    end
end
