
local addOnName = ...
local addOnVersion = (GetAddOnMetadata and GetAddOnMetadata(addOnName, "Version")) or (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addOnName, "Version")) or "0.5.5"
local tinsert = tinsert or table.insert

local interfaceVersion = select(4, GetBuildInfo()) or 0
local clientBuildMajor = math.floor(interfaceVersion / 10000)
-- load only on the Classic-era client families TacoTip supports (Vanilla/TBC/Wrath)
if (clientBuildMajor < 1 or clientBuildMajor > 3) then
    return
end

assert(LibStub, "TacoTip requires LibStub")
assert(LibStub:GetLibrary("LibClassicInspector", true), "TacoTip requires LibClassicInspector")
assert(LibStub:GetLibrary("LibDetours-1.0", true), "TacoTip requires LibDetours-1.0")
--assert(LibStub:GetLibrary("LibClassicGearScore", true), "TacoTip requires LibClassicGearScore")

local CI = LibStub("LibClassicInspector")
local Detours = LibStub("LibDetours-1.0")
local GearScore = _G.TT_GS
local L = _G.TACOTIP_LOCALE

TacoTipGSHistory = TacoTipGSHistory or {}
local TT = _G[addOnName]

if (not TT) then
    TT = {}
    rawset(_G, addOnName, TT)
end

local isPawnLoaded = _G.PawnClassicLastUpdatedVersion and _G.PawnClassicLastUpdatedVersion >= 2.0538

local HORDE_ICON = "|TInterface\\TargetingFrame\\UI-PVP-HORDE:16:16:-2:0:64:64:0:38:0:38|t"
local ALLIANCE_ICON = "|TInterface\\TargetingFrame\\UI-PVP-ALLIANCE:16:16:-2:0:64:64:0:38:0:38|t"
local PVP_FLAG_ICON = "|TInterface\\GossipFrame\\BattleMasterGossipIcon:0|t"
local ACHIEVEMENT_ICON = "|TInterface\\AchievementFrame\\UI-Achievement-TinyShield:18:18:0:0:20:20:0:12.5:0:12.5|t"
local GetClassAtlas = _G.GetClassAtlas

local POWERBAR_UPDATE_RATE = 0.2

local NewTicker = _G.C_Timer and _G.C_Timer.NewTicker
local CAfter = _G.C_Timer and _G.C_Timer.After
local GetBestMapForUnit = _G.C_Map and _G.C_Map.GetBestMapForUnit
local GameTooltip_SetDefaultAnchor = _G.GameTooltip_SetDefaultAnchor
local UnitClass = _G.UnitClass
local UnitCanAttack = _G.UnitCanAttack
local UnitExists = _G.UnitExists
local UnitIsPlayer = _G.UnitIsPlayer
local UnitIsUnit = _G.UnitIsUnit
local UnitLevel = _G.UnitLevel
local UnitRace = _G.UnitRace
local GetQuestDifficultyColor = _G.GetQuestDifficultyColor

local playerClass = select(2, UnitClass("player"))

-- Safe-call wrapper. Routes errors through Blizzard's geterrorhandler()
-- global so they are captured by error display addons (BugSack, !Swatter,
-- BugGrabber, etc.) instead of silently breaking the GameTooltip.
-- Usage: safeCall(myHandler, arg1, arg2, ...)
local function safeCall(fn, ...)
    return xpcall(fn, geterrorhandler(), ...)
end

-- TBC Anniversary 2.5.3+ (retail 9.x engine) moved tooltip backdrops from
-- GameTooltip to a NineSlice sub-frame (SharedTooltipTemplates.lua per
-- warcraft.wiki.gg/wiki/2.5.3-Consolidated-UI-Changes).
-- SetBackdrop/SetBackdropBorderColor on the parent has NO visual effect;
-- NineSlice renders the actual backdrop. The apply-backdrop functions below
-- detect NineSlice and use NineSlice:SetBorderColor/SetCenterColor directly.
-- This early Mixin provides a fallback for pre-2.5.3 clients.
do
    local needsMixin = _G.GameTooltip and _G.BackdropTemplateMixin and not _G.GameTooltip.SetBackdrop
    if (needsMixin and _G.Mixin) then
        Mixin(_G.GameTooltip, _G.BackdropTemplateMixin)
    end
end

local function isOtherPlayersPet(unit)
    return _G.UnitIsOtherPlayersPet and _G.UnitIsOtherPlayersPet(unit)
end

local function stopPowerBarTicker()
    if (TacoTipPowerBar and TacoTipPowerBar.updateTicker) then
        TacoTipPowerBar.updateTicker:Cancel()
        TacoTipPowerBar.updateTicker = nil
    end
end

local function setButtonEnabled(button, enabled)
    if (not button) then
        return
    end
    if (enabled) then
        button:Enable()
    else
        button:Disable()
    end
end

local function refreshOptionsUI()
    if (TT and TT.RefreshOptionsUI) then
        TT:RefreshOptionsUI()
    end
end

local function registerSharedMediaCallbacks()
    if (TT and not TT._sharedMediaCallbacksRegistered and LibStub) then
        local media = LibStub("LibSharedMedia-3.0", true)
        if (media and media.RegisterCallback) then
            media.RegisterCallback(TT, "LibSharedMedia_Registered", function(_, mediatype)
                if (mediatype == "font" or mediatype == "statusbar" or mediatype == "background" or mediatype == "border") then
                    refreshOptionsUI()
                end
            end)
            TT._sharedMediaCallbacksRegistered = true
        end
    end
end

local specializationIconCache = {}

local function makeColorCode(r, g, b)
    return string.format("|cFF%02x%02x%02x", (r or 1) * 255, (g or 1) * 255, (b or 1) * 255)
end

local function colorizeText(text, r, g, b)
    if (not text or text == "") then
        return text or ""
    end
    return string.format("%s%s|r", makeColorCode(r, g, b), text)
end

local function escapePattern(text)
    if (not text or text == "") then
        return nil
    end
    return (text:gsub("(%W)", "%%%1"))
end

local function replaceFirstExact(text, needle, replacement)
    local pattern = escapePattern(needle)
    if (not text or not pattern or not replacement) then
        return text
    end
    return string.gsub(text, pattern, replacement, 1)
end

local function getClassIconMarkup(class)
    if (not class or not GetClassAtlas) then
        return ""
    end
    local atlas = GetClassAtlas(class)
    if (atlas and atlas ~= "") then
        return string.format("|A:%s:14:14|a", atlas)
    end
    return ""
end

TT.GetClassIconMarkup = function(self, class)
    return getClassIconMarkup(class)
end

local function getClassColor(class)
    if (not class) then
        return nil
    end
    local color = CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[class]
    if (not color and RAID_CLASS_COLORS) then
        color = RAID_CLASS_COLORS[class]
    end
    return color
end

local function clearTooltipPlayerClassColor(tooltip)
    if (tooltip) then
        tooltip.TacoTipPlayerClassColor = nil
    end
end

local function storeTooltipPlayerClassColor(tooltip, unit)
    if (not tooltip) then
        return nil
    end
    if (not unit) then
        return tooltip.TacoTipPlayerClassColor
    end
    if (not UnitExists or not UnitExists(unit) or not UnitIsPlayer or not UnitIsPlayer(unit)) then
        clearTooltipPlayerClassColor(tooltip)
        return nil
    end

    local _, class = UnitClass(unit)
    local classColor = getClassColor(class)
    if (not classColor) then
        clearTooltipPlayerClassColor(tooltip)
        return nil
    end

    local cachedColor = tooltip.TacoTipPlayerClassColor or {}
    cachedColor.r, cachedColor.g, cachedColor.b = classColor.r, classColor.g, classColor.b
    tooltip.TacoTipPlayerClassColor = cachedColor
    return cachedColor
end

local function getTooltipPlayerClassColor(tooltip, unit)
    local cachedColor = storeTooltipPlayerClassColor(tooltip, unit)
    if (cachedColor) then
        return cachedColor.r, cachedColor.g, cachedColor.b, true
    end
    return 1, 1, 1, false
end

local function getHostileDifficultyColor(unit)
    if (not unit or UnitIsPlayer(unit) or not UnitCanAttack("player", unit) or not GetQuestDifficultyColor) then
        return nil
    end

    local level = UnitLevel(unit)
    if (level and level > 0) then
        return GetQuestDifficultyColor(level)
    end

    return GetQuestDifficultyColor((UnitLevel("player") or 1) + 10)
end

local function colorizeUnitLevelLine(unit, textLine)
    if (not textLine or textLine == "") then
        return textLine
    end

    local color = getHostileDifficultyColor(unit)
    if (not color) then
        return textLine
    end

    local level = UnitLevel(unit)
    local levelToken = (level and level > 0) and tostring(level) or "??"
    local coloredLevel = colorizeText(levelToken, color.r, color.g, color.b)

    if (level and level > 0) then
        return string.gsub(textLine, levelToken, coloredLevel, 1)
    end

    return string.gsub(textLine, "%?%?", coloredLevel, 1)
end

local function getSpecializationIcon(class, specIndex)
    if (not class or not specIndex) then
        return nil
    end

    local cacheKey = class .. ":" .. tostring(specIndex)
    if (specializationIconCache[cacheKey] ~= nil) then
        return specializationIconCache[cacheKey] or nil
    end

    local bestTexture, bestTier = nil, -1
    for talentIndex = 1, 40 do
        local ok, name, iconTexture, tier, _, _, _, isExceptional = pcall(CI.GetTalentInfoByClass, CI, class, specIndex, talentIndex)
        if (not ok) then
            break
        end
        if (name and iconTexture) then
            if (isExceptional) then
                specializationIconCache[cacheKey] = iconTexture
                return iconTexture
            end
            if ((tier or 0) >= bestTier) then
                bestTexture = iconTexture
                bestTier = tier or 0
            end
        end
    end

    specializationIconCache[cacheKey] = bestTexture or false
    return bestTexture
end

local function formatSpecializationText(class, specIndex, p1, p2, p3)
    local specName = class and specIndex and CI:GetSpecializationName(class, specIndex, true) or nil
    if (not specName) then
        return nil
    end

    local iconTexture = getSpecializationIcon(class, specIndex)
    local iconText = iconTexture and string.format("|T%s:14:14:0:0:64:64:4:60:4:60|t ", tostring(iconTexture)) or ""
    local classColor = getClassColor(class)
    local coloredName = classColor and colorizeText(specName, classColor.r, classColor.g, classColor.b) or specName
    return string.format("%s%s [%d/%d/%d]", iconText, coloredName, p1 or 0, p2 or 0, p3 or 0)
end

TT.GetFormattedSpecializationText = function(self, class, specIndex, p1, p2, p3)
    return formatSpecializationText(class, specIndex, p1, p2, p3)
end

local function ensureTooltipPortrait(tooltip)
    if (not tooltip) then
        return nil
    end
    local use3D = TacoTipConfig.tooltip_portrait_3d
    if (use3D) then
        if (not tooltip.TacoTipPortrait3D) then
            local ok, model = pcall(CreateFrame, "PlayerModel", nil, tooltip)
            if (not ok or not model) then
                use3D = false
            else
                tooltip.TacoTipPortrait3D = model
                tooltip.TacoTipPortrait3D:SetFrameLevel(tooltip:GetFrameLevel() + 1)
                tooltip.TacoTipPortrait3D:EnableMouse(false)
            end
        end
        if (tooltip.TacoTipPortrait3D) then
            if (tooltip.TacoTipPortrait) then
                tooltip.TacoTipPortrait:Hide()
            end
            return tooltip.TacoTipPortrait3D
        end
    end
    if (not tooltip.TacoTipPortrait) then
        tooltip.TacoTipPortrait = tooltip:CreateTexture(nil, "ARTWORK")
        tooltip.TacoTipPortrait:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    end
    if (tooltip.TacoTipPortrait3D) then
        tooltip.TacoTipPortrait3D:Hide()
    end
    return tooltip.TacoTipPortrait
end

local function applyTooltipFonts(tooltip)
    if (not tooltip or not tooltip.GetName) then
        return
    end
    local tooltipName = tooltip:GetName()
    if (not tooltipName) then
        return
    end
    local fontPath = (TT.GetResolvedTooltipFont and TT:GetResolvedTooltipFont()) or TacoTipConfig.tooltip_font or "Fonts\\FRIZQT__.TTF"
    local fontSize = TacoTipConfig.tooltip_font_size or 12
    for i = 1, math.max(tooltip:NumLines() + 4, 20) do
        local left = _G[tooltipName .. "TextLeft" .. i]
        local right = _G[tooltipName .. "TextRight" .. i]
        if (left and left.SetFont) then
            left:SetFont(fontPath, fontSize)
        end
        if (right and right.SetFont) then
            right:SetFont(fontPath, fontSize)
        end
    end
end

local function getOrCreateBackdropFrame(tooltip)
    if (not tooltip) then
        return nil, false
    end
    if (tooltip.TacoTipBackdropFrame) then
        return tooltip.TacoTipBackdropFrame, tooltip.TacoTipBackdropFrame.isCustom
    end

    -- 2.5.3+ (NineSlice layout): create a border-only overlay frame.
    -- NineSlice stays visible and provides the default tooltip background.
    -- Our frame only draws the border edge (edgeFile) on top of NineSlice's
    -- own border at frame level 2 — above NineSlice (0), below text (3+).
    if (tooltip.NineSlice) then
        local template = BackdropTemplateMixin and "BackdropTemplate" or nil
        local bf = CreateFrame("Frame", nil, tooltip, template)
        bf:SetAllPoints()
        bf:SetFrameLevel(2)
        bf.isCustom = true
        bf.isBorderOnly = true
        -- Keep NineSlice visible — it provides the default background
        tooltip.TacoTipBackdropFrame = bf
        return bf, true
    end

    -- Pre-2.5.3: ensure the tooltip has SetBackdrop and use it directly
    if (not tooltip.SetBackdrop and BackdropTemplateMixin and Mixin) then
        Mixin(tooltip, BackdropTemplateMixin)
    end
    tooltip.TacoTipBackdropFrame = tooltip
    return tooltip, false
end

local function applyTooltipBackdrop(tooltip)
    local backdrop, isCustom = getOrCreateBackdropFrame(tooltip)
    if (not backdrop or not backdrop.SetBackdrop) then
        return
    end

    local backgroundTexture = (TT.GetResolvedTooltipBackground and TT:GetResolvedTooltipBackground()) or TacoTipConfig.tooltip_background_texture or "Interface\\Tooltips\\UI-Tooltip-Background"
    local borderTexture = (TT.GetResolvedTooltipBorder and TT:GetResolvedTooltipBorder()) or TacoTipConfig.tooltip_border_texture or "Interface\\Tooltips\\UI-Tooltip-Border"
    local hasBorder = borderTexture and borderTexture ~= "" and borderTexture ~= "Interface\\None"

    if (backdrop.isBorderOnly) then
        -- 2.5.3+: border overlay only. NineSlice provides the default
        -- background — we only draw the colored border on top.
        backdrop:SetBackdrop({
            edgeFile = hasBorder and borderTexture or nil,
            edgeSize = hasBorder and (TacoTipConfig.tooltip_border_edge_size or 16) or 0,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
    else
        -- Pre-2.5.3: full backdrop with background + border on the tooltip
        backdrop:SetBackdrop({
            bgFile = backgroundTexture,
            edgeFile = hasBorder and borderTexture or nil,
            tile = true,
            tileSize = 16,
            edgeSize = hasBorder and (TacoTipConfig.tooltip_border_edge_size or 16) or 0,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
    end
end

local function applyTooltipBorderOverlay(tooltip, unit, borderR, borderG, borderB)
    local backdrop = tooltip and tooltip.TacoTipBackdropFrame
    if (not backdrop or not backdrop.SetBackdropBorderColor) then
        return
    end

    local borderTexture = (TT.GetResolvedTooltipBorder and TT:GetResolvedTooltipBorder()) or TacoTipConfig.tooltip_border_texture or "Interface\\Tooltips\\UI-Tooltip-Border"
    local hasBorder = borderTexture and borderTexture ~= "" and borderTexture ~= "Interface\\None"
    if (not hasBorder) then
        return
    end

    backdrop:SetBackdropBorderColor(borderR, borderG, borderB, TacoTipConfig.tooltip_border_alpha or 0.85)
end

local function resolveTooltipUnit(tooltip, unit)
    if (unit and UnitExists and UnitExists(unit)) then
        return unit
    end
    if (tooltip and tooltip.GetUnit) then
        local ok, _, tooltipUnit = pcall(tooltip.GetUnit, tooltip)
        if (ok and tooltipUnit and UnitExists and UnitExists(tooltipUnit)) then
            return tooltipUnit
        end
    end
    return nil
end

function TT:ApplyTooltipAppearance(tooltip, unit)
    if (not tooltip) then
        return
    end

    unit = resolveTooltipUnit(tooltip, unit)

    applyTooltipBackdrop(tooltip)

    local tintR, tintG, tintB, isPlayerTooltip = getTooltipPlayerClassColor(tooltip, unit)
    local bgR = TacoTipConfig.tooltip_background_color_r or 0
    local bgG = TacoTipConfig.tooltip_background_color_g or 0
    local bgB = TacoTipConfig.tooltip_background_color_b or 0
    local borderR = TacoTipConfig.tooltip_border_color_r or 1
    local borderG = TacoTipConfig.tooltip_border_color_g or 1
    local borderB = TacoTipConfig.tooltip_border_color_b or 1

    if (TacoTipConfig.tooltip_background_use_class and isPlayerTooltip) then
        bgR, bgG, bgB = tintR, tintG, tintB
    end
    if ((TacoTipConfig.tooltip_border_use_class or TacoTipConfig.color_class) and isPlayerTooltip) then
        borderR, borderG, borderB = tintR, tintG, tintB
    end

    -- Background color: only apply for pre-2.5.3 (full backdrop mode).
    -- On 2.5.3+ (border-only overlay), NineSlice provides the default
    -- background — tinting the overlay frame does nothing useful.
    local backdrop = tooltip and tooltip.TacoTipBackdropFrame
    if (backdrop and backdrop.SetBackdropColor and not backdrop.isBorderOnly) then
        backdrop:SetBackdropColor(bgR, bgG, bgB, TacoTipConfig.tooltip_background_alpha or 0.85)
    end
    applyTooltipBorderOverlay(tooltip, unit, borderR, borderG, borderB)

    -- Defensive follow-up: re-apply the class-tinted border a short tick
    -- later in case Blizzard or another addon re-sets the backdrop after
    -- this function returns (TBC Anniversary 2026 can refresh the tooltip
    -- frame after OnTooltipSetUnit completes).
    if ((TacoTipConfig.tooltip_border_use_class or TacoTipConfig.color_class) and isPlayerTooltip) then
        CAfter(0.05, function()
            return safeCall(function()
                if (not tooltip or not tooltip:IsShown()) then
                    return
                end
                local refreshed = tooltip.TacoTipPlayerClassColor
                if (not refreshed) then
                    return
                end
                if (not TacoTipConfig.tooltip_border_use_class and not TacoTipConfig.color_class) then
                    return
                end
                applyTooltipBorderOverlay(tooltip, nil, refreshed.r, refreshed.g, refreshed.b)
            end)
        end)
    end

    applyTooltipFonts(tooltip)

    local portrait = ensureTooltipPortrait(tooltip)
    local portraitScale = TacoTipConfig.tooltip_portrait_scale or 1
    local portraitW = math.floor(40 * portraitScale)
    local portraitH = math.floor(56 * portraitScale)
    if (portrait) then
        if (TacoTipConfig.tooltip_portrait and unit) then
            portrait:ClearAllPoints()
            portrait:SetSize(portraitW, portraitH)
            portrait:SetPoint("TOPLEFT", tooltip, "TOPRIGHT", 8, 0)
            local is3D = TacoTipConfig.tooltip_portrait_3d
            if (is3D and portrait.SetUnit) then
                pcall(portrait.SetUnit, portrait, unit)
                pcall(portrait.SetPortraitZoom, portrait, TacoTipConfig.tooltip_portrait_zoom or 0.7)
            else
                _G.SetPortraitTexture(portrait, unit)
            end
            portrait:Show()
        else
            portrait:Hide()
            if (tooltip.TacoTipEliteFrame) then
                tooltip.TacoTipEliteFrame:Hide()
            end
        end
    end

    if (TacoTipConfig.show_elite_frame and unit and TacoTipConfig.tooltip_portrait and not UnitIsPlayer(unit)) then
        local classification = UnitClassification(unit)
        if (classification and classification ~= "normal" and classification ~= "") then
            local eliteFrame = tooltip.TacoTipEliteFrame
            if (not eliteFrame) then
                eliteFrame = tooltip:CreateTexture(nil, "OVERLAY")
                tooltip.TacoTipEliteFrame = eliteFrame
            end
            local portraitSize = portraitW
            eliteFrame:ClearAllPoints()
            if (classification == "worldboss") then
                pcall(eliteFrame.SetAtlas, eliteFrame, "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold-Winged", false)
                eliteFrame:SetSize(portraitSize * 1.4, portraitSize * 1.4)
                eliteFrame:SetPoint("CENTER", portrait, "CENTER")
            elseif (classification == "rareelite") then
                pcall(eliteFrame.SetAtlas, eliteFrame, "ui-hud-unitframe-target-portraiton-boss-rare-silver", false)
                eliteFrame:SetSize(portraitSize * 1.4, portraitSize * 1.4)
                eliteFrame:SetPoint("CENTER", portrait, "CENTER")
            elseif (classification == "elite") then
                pcall(eliteFrame.SetAtlas, eliteFrame, "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold", false)
                eliteFrame:SetSize(portraitSize * 1.4, portraitSize * 1.4)
                eliteFrame:SetPoint("CENTER", portrait, "CENTER")
            elseif (classification == "rare") then
                pcall(eliteFrame.SetAtlas, eliteFrame, "UnitFrame-Target-PortraitOn-Boss-Rare-Star", false)
                eliteFrame:SetSize(16, 16)
                eliteFrame:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", 2, 2)
            end
            eliteFrame:Show()
        end
    end
    if (tooltip.TacoTipEliteFrame and not (TacoTipConfig.show_elite_frame and unit and TacoTipConfig.tooltip_portrait and not UnitIsPlayer(unit))) then
        tooltip.TacoTipEliteFrame:Hide()
    end

    local barTexture = (TT.GetResolvedTooltipStatusBarTexture and TT:GetResolvedTooltipStatusBarTexture()) or TacoTipConfig.tooltip_bar_texture or "Interface\\TargetingFrame\\UI-TargetingFrame-BarFill"
    if (tooltip == GameTooltip and GameTooltipStatusBar and GameTooltipStatusBar.SetStatusBarTexture) then
        GameTooltipStatusBar:SetStatusBarTexture(barTexture)
    end
    if (TacoTipPowerBar and TacoTipPowerBar.SetStatusBarTexture) then
        TacoTipPowerBar:SetStatusBarTexture(barTexture)
    end
end

local function startPowerBarTicker()
    if (TacoTipPowerBar and not TacoTipPowerBar.updateTicker and type(NewTicker) == "function") then
        TacoTipPowerBar.updateTicker = NewTicker(POWERBAR_UPDATE_RATE, function()
            if (TacoTipPowerBar and TacoTipPowerBar:IsShown()) then
                TacoTipPowerBar:Update()
            end
        end)
    end
end

function TacoTip_GSCallback(guid)
    local ttUnit = resolveTooltipUnit(GameTooltip)
    if (ttUnit and UnitGUID(ttUnit) == guid) then
        GameTooltip:SetUnit(ttUnit)
    end
end

local delayedTooltipTimer = nil
local function cancelDelayedTooltip()
    if (delayedTooltipTimer) then
        delayedTooltipTimer:Cancel()
        delayedTooltipTimer = nil
    end
end

local function onTooltipSetUnit(tooltip)
    local name, tooltipUnit = tooltip:GetUnit()
    tooltipUnit = resolveTooltipUnit(tooltip, tooltipUnit)
    if (not tooltipUnit) then
        clearTooltipPlayerClassColor(tooltip)
        return
    end

    storeTooltipPlayerClassColor(tooltip, tooltipUnit)

    if (TacoTipDragButton and TacoTipDragButton:IsShown()) then
        if (not UnitIsUnit(tooltipUnit, "player")) then
            -- Apply appearance for the non-player unit even in mover mode
            -- so the backdrop/border/font from a previous player hover
            -- does not persist on the current tooltip.
            TT:ApplyTooltipAppearance(tooltip, tooltipUnit)
            TacoTipDragButton:ShowExample()
            return
        end
    end

    local guid = UnitGUID(tooltipUnit)

    local wide_style = (TacoTipConfig.tip_style == 1 or ((TacoTipConfig.tip_style == 2 or TacoTipConfig.tip_style == 4) and IsShiftKeyDown()))
    local mini_style = (not wide_style and (TacoTipConfig.tip_style == 4 or TacoTipConfig.tip_style == 5))

    local text = {}
    local linesToAdd = {}

    local numLines = GameTooltip:NumLines()

    for i=1,numLines do
        text[i] = _G["GameTooltipTextLeft"..i]:GetText()
    end
    if (not text[1] or text[1] == "") then return end
    if (not text[2] or text[2] == "") then return end

    text[2] = colorizeUnitLevelLine(tooltipUnit, text[2])

    if (TacoTipConfig.show_target and UnitIsConnected(tooltipUnit) and not UnitIsUnit(tooltipUnit, "player")) then
        local unitTarget = tooltipUnit .. "target"
        local targetName = UnitName(unitTarget)

        if (targetName) then
            if (UnitIsUnit(unitTarget, tooltipUnit)) then
                if (wide_style) then
                    tinsert(linesToAdd, {L["Target"]..":", L["Self"], NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b})
                else
                    tinsert(linesToAdd, {L["Target"]..": |cFFFFFFFF"..L["Self"].."|r"})
                end
            elseif (UnitIsUnit(unitTarget, "player")) then
                if (wide_style) then
                    tinsert(linesToAdd, {L["Target"]..":", L["You"], NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, 1, 1, 0})
                else
                    tinsert(linesToAdd, {L["Target"]..": |cFFFFFF00"..L["You"].."|r"})
                end
            elseif (UnitIsPlayer(unitTarget)) then
                local classc
                if (TacoTipConfig.color_class) then
                    local _, targetClass = UnitClass(unitTarget)
                    if (targetClass) then
                        classc = getClassColor(targetClass)
                    end
                end
                if (classc) then
                    if (wide_style) then
                        local targetLine = string.format("|cFF%02x%02x%02x%s|r (%s)", classc.r*255, classc.g*255, classc.b*255, targetName, L["Player"])
                        tinsert(linesToAdd, {L["Target"]..":", targetLine, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b})
                    else
                        tinsert(linesToAdd, {string.format("%s: |cFF%02x%02x%02x%s|cFFFFFFFF (%s)|r", L["Target"], classc.r*255, classc.g*255, classc.b*255, targetName, L["Player"])})
                    end
                else
                    if (wide_style) then
                        tinsert(linesToAdd, {L["Target"]..":", targetName.." ("..L["Player"]..")", NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b})
                    else
                        tinsert(linesToAdd, {L["Target"]..": |cFFFFFFFF"..targetName.." ("..L["Player"]..")|r"})
                    end
                end
            elseif (UnitIsUnit(unitTarget, "pet") or isOtherPlayersPet(unitTarget)) then
                if (wide_style) then
                    tinsert(linesToAdd, {L["Target"]..":", targetName.." ("..L["Pet"]..")", NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b})
                else
                    tinsert(linesToAdd, {L["Target"]..": |cFFFFFFFF"..targetName.." ("..L["Pet"]..")|r"})
                end
            else
                if (wide_style) then
                    tinsert(linesToAdd, {L["Target"]..":", targetName, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b})
                else
                    tinsert(linesToAdd, {L["Target"]..": |cFFFFFFFF"..targetName.."|r"})
                end
            end
        else
            local inSameMap = true
            if (IsInGroup() and ((IsInRaid() and UnitInRaid(tooltipUnit)) or UnitInParty(tooltipUnit))) then
                if (GetBestMapForUnit) then
                    local unitMap = GetBestMapForUnit(tooltipUnit)
                    local playerMap = GetBestMapForUnit("player")
                    if (unitMap and playerMap and unitMap ~= playerMap) then
                        inSameMap = false
                    end
                end
            end
            if (inSameMap) then
                if (wide_style) then
                    tinsert(linesToAdd, {L["Target"]..":", L["None"], NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, GRAY_FONT_COLOR.r, GRAY_FONT_COLOR.g, GRAY_FONT_COLOR.b})
                else
                    tinsert(linesToAdd, {L["Target"]..": |cFF808080"..L["None"].."|r"})
                end
            end
        end
    end

    if (UnitIsPlayer(tooltipUnit)) then
        local localizedClass, class = UnitClass(tooltipUnit)
        local localizedRace = UnitRace(tooltipUnit)

        if (not TacoTipConfig.show_titles and string.find(text[1], name)) then
            text[1] = name
        end
        if (TacoTipConfig.color_class) then
            if (localizedClass and class) then
                local classc = getClassColor(class)
                if (classc) then
                    --GameTooltipTextLeft1:SetTextColor(classc.r, classc.g, classc.b)
                    text[1] = colorizeText(text[1], classc.r, classc.g, classc.b)
                    local classColoredName = colorizeText(localizedClass, classc.r, classc.g, classc.b)
                    local raceColoredName = localizedRace and colorizeText(localizedRace, classc.r, classc.g, classc.b) or nil
                    for i=2,3 do
                        if (text[i]) then
                            if (localizedRace and raceColoredName) then
                                text[i] = replaceFirstExact(text[i], localizedRace, raceColoredName)
                            end
                            text[i] = replaceFirstExact(text[i], localizedClass, classColoredName)
                        end
                    end
                end
            end
        end
        local guildName, guildRankName = GetGuildInfo(tooltipUnit);
        if (guildName and guildRankName) then
            if (TacoTipConfig.show_guild_name) then
                if (TacoTipConfig.show_guild_rank) then
                    if (TacoTipConfig.guild_rank_alt_style) then
                        text[2] = string.gsub(text[2], guildName, string.format("|cFF40FB40<%s> (%s)|r", guildName, guildRankName), 1)
                    else
                        text[2] = string.gsub(text[2], guildName, string.format("|cFF40FB40"..L["FORMAT_GUILD_RANK_1"].."|r", guildRankName, guildName), 1)
                    end
                else
                    text[2] = string.gsub(text[2], guildName, string.format("|cFF40FB40<%s>|r", guildName), 1)
                end
            else
                text[2] = string.gsub(text[2], guildName, "", 1)
            end
        end
        if (TacoTipConfig.show_realm and UnitIsPlayer(tooltipUnit) and not UnitIsSameServer(tooltipUnit, "player")) then
            local _, realm = UnitName(tooltipUnit)
            if (realm and realm ~= "") then
                if (wide_style) then
                    tinsert(linesToAdd, {(L["Realm"] or "Realm")..":", realm, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b})
                else
                    tinsert(linesToAdd, {string.format("%s: |cFFFFFFFF%s|r", L["Realm"] or "Realm", realm)})
                end
            end
        end
        if (TacoTipConfig.show_honor_rank) then
            local pvpName = UnitPVPName(tooltipUnit)
            if (pvpName and pvpName ~= "" and pvpName ~= name) then
                if (wide_style) then
                    tinsert(linesToAdd, {(L["Honor Rank"] or "Honor Rank")..":", pvpName, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b})
                else
                    tinsert(linesToAdd, {string.format("%s: |cFFFFFFFF%s|r", L["Honor Rank"] or "Honor Rank", pvpName)})
                end
            end
        end
        local nameLineIcons = ""
        if (TacoTipConfig.show_pvp_icon and UnitIsPlayer(tooltipUnit) and UnitIsPVP(tooltipUnit)) then
            nameLineIcons = nameLineIcons .. " " .. PVP_FLAG_ICON
            for i=2,numLines do
                if (text[i]) then
                    text[i] = string.gsub(text[i], "PvP", "", 1)
                end
            end
        end
        if (TacoTipConfig.show_team) then
            nameLineIcons = nameLineIcons .. " " .. (UnitFactionGroup(tooltipUnit) == "Horde" and HORDE_ICON or ALLIANCE_ICON)
        end
        if (TacoTipConfig.show_class_icon and UnitIsPlayer(tooltipUnit)) then
            local _, class = UnitClass(tooltipUnit)
            if (class) then
                nameLineIcons = nameLineIcons .. " " .. getClassIconMarkup(class)
            end
        end
        if (TacoTipConfig.show_role_icon and UnitIsPlayer(tooltipUnit) and IsInGroup()) then
            local role = UnitGroupRolesAssigned(tooltipUnit)
            if (role and role ~= "NONE") then
                local roleIcon
                if (role == "TANK") then
                    roleIcon = "|TInterface\\GroupFrame\\UI-Group-TankIcon:18:18:0:0:16:16:0:16:0:16|t"
                elseif (role == "HEALER") then
                    roleIcon = "|TInterface\\GroupFrame\\UI-Group-HealerIcon:18:18:0:0:16:16:0:16:0:16|t"
                else
                    roleIcon = "|TInterface\\GroupFrame\\UI-Group-DPSIcon:18:18:0:0:16:16:0:16:0:16|t"
                end
                nameLineIcons = nameLineIcons .. " " .. roleIcon
            end
        end
        if (nameLineIcons ~= "") then
            text[1] = text[1] .. nameLineIcons
        end
        if (not TacoTipConfig.hide_in_combat or not InCombatLockdown()) then
            if (TacoTipConfig.show_separators) then
                if (wide_style) then
                    tinsert(linesToAdd, {" ", " ", GRAY_FONT_COLOR.r, GRAY_FONT_COLOR.g, GRAY_FONT_COLOR.b, GRAY_FONT_COLOR.r, GRAY_FONT_COLOR.g, GRAY_FONT_COLOR.b})
                else
                    tinsert(linesToAdd, {"|cFF444444" .. string.rep("-", 30) .. "|r", GRAY_FONT_COLOR.r, GRAY_FONT_COLOR.g, GRAY_FONT_COLOR.b})
                end
            end
            if (TacoTipConfig.show_talents) then
                local x1, x2, x3 = 0,0,0
                local y1, y2, y3 = 0,0,0
                local spec1 = CI:GetSpecialization(guid, 1)
                if (spec1) then
                    x1, x2, x3 = CI:GetTalentPoints(guid, 1)
                end
                local spec2 = CI:GetSpecialization(guid, 2)
                if (spec2) then
                    y1, y2, y3 = CI:GetTalentPoints(guid, 2)
                end

                local active = CI:GetActiveTalentGroup(guid)

                if (active == 2) then
                    if (spec2) then
                        local specText = formatSpecializationText(class, spec2, y1, y2, y3)
                        if (wide_style) then
                            tinsert(linesToAdd, {L["Talents"]..":", specText, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, 1, 1, 1})
                        else
                            tinsert(linesToAdd, {string.format("%s: %s", L["Talents"], specText)})
                        end
                    end
                    -- Only render the inactive spec when it is a genuinely
                    -- different tree. Prevents the same spec being printed
                    -- twice when both dual-spec slots match (e.g. TBC
                    -- Anniversary 2026 inspect data, or the player picked
                    -- the same tree in both slots).
                    if (spec1 and spec1 ~= spec2) then
                        local specText = formatSpecializationText(class, spec1, x1, x2, x3)
                        if (wide_style) then
                            tinsert(linesToAdd, {" ", string.format("|c99ffffff%s|r", specText), NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, GRAY_FONT_COLOR.r, GRAY_FONT_COLOR.g, GRAY_FONT_COLOR.b})
                        else
                            tinsert(linesToAdd, {string.format("      |c99ffffff%s|r", specText)})
                        end
                    end
                elseif (active == 1) then
                    if (spec1) then
                        local specText = formatSpecializationText(class, spec1, x1, x2, x3)
                        if (wide_style) then
                            tinsert(linesToAdd, {L["Talents"]..":", specText, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, 1, 1, 1})
                        else
                            tinsert(linesToAdd, {string.format("%s: %s", L["Talents"], specText)})
                        end
                    end
                    -- Only render the inactive spec when it is a genuinely
                    -- different tree. Prevents the same spec being printed
                    -- twice when both dual-spec slots match.
                    if (spec2 and spec2 ~= spec1) then
                        local specText = formatSpecializationText(class, spec2, y1, y2, y3)
                        if (wide_style) then
                            tinsert(linesToAdd, {" ", string.format("|c99ffffff%s|r", specText), NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, GRAY_FONT_COLOR.r, GRAY_FONT_COLOR.g, GRAY_FONT_COLOR.b})
                        else
                            tinsert(linesToAdd, {string.format("      |c99ffffff%s|r", specText)})
                        end
                    end
                end
            end
            if (TacoTipConfig.show_separators) then
                if (wide_style) then
                    tinsert(linesToAdd, {" ", " ", GRAY_FONT_COLOR.r, GRAY_FONT_COLOR.g, GRAY_FONT_COLOR.b, GRAY_FONT_COLOR.r, GRAY_FONT_COLOR.g, GRAY_FONT_COLOR.b})
                else
                    tinsert(linesToAdd, {"|cFF444444" .. string.rep("-", 30) .. "|r", GRAY_FONT_COLOR.r, GRAY_FONT_COLOR.g, GRAY_FONT_COLOR.b})
                end
            end
            local miniText = ""
            if (TacoTipConfig.show_gs_player) then
                local gearscore, avg_ilvl = GearScore:GetScore(guid, true)
                if (gearscore > 0) then
                    local r, g, b = GearScore:GetQuality(gearscore)
                    local gsDelta = ""
                    if (TacoTipConfig.show_gs_delta and guid and gearscore > 0) then
                        local lastGS = TacoTipGSHistory[guid]
                        if (lastGS and lastGS > 0) then
                            local diff = gearscore - lastGS
                            if (diff > 0) then
                                gsDelta = string.format(" |cFF00FF00▲%d|r", diff)
                            elseif (diff < 0) then
                                gsDelta = string.format(" |cFFFF0000▼%d|r", math.abs(diff))
                            end
                        end
                        TacoTipGSHistory[guid] = gearscore
                    end
                    if (wide_style) then
                        if (r == b and r == g) then
                            tinsert(linesToAdd, {"|cFFFFFFFFGearScore:|r "..gearscore..gsDelta, "|cFFFFFFFF(iLvl:|r "..avg_ilvl.."|cFFFFFFFF)|r", r, g, b, r, g, b})
                        else
                            tinsert(linesToAdd, {"GearScore: "..gearscore..gsDelta, "(iLvl: "..avg_ilvl..")", r, g, b, r, g, b})
                        end
                    elseif (mini_style) then
                        if (r == b and r == g) then
                            miniText = string.format("GS: |cFF%02x%02x%02x%s|r%s  L: |cFF%02x%02x%02x%s|r  ", r*255, g*255, b*255, gearscore, gsDelta, r*255, g*255, b*255, avg_ilvl)
                        else
                            miniText = string.format("|cFF%02x%02x%02xGS: %s%s  L: %s|r  ", r*255, g*255, b*255, gearscore, gsDelta, avg_ilvl)
                        end
                    else
                        if (r == b and r == g) then
                            tinsert(linesToAdd, {"|cFFFFFFFFGearScore:|r "..gearscore..gsDelta, r, g, b})
                        else
                            tinsert(linesToAdd, {"GearScore: "..gearscore..gsDelta, r, g, b})
                        end
                        if (avg_ilvl and avg_ilvl > 0) then
                            if (TacoTipConfig.show_ilvl_inline) then
                                text[1] = text[1] .. string.format(" |cFF%02x%02x%02x[%s]|r", r*255, g*255, b*255, avg_ilvl)
                            else
                                tinsert(linesToAdd, {"iLvl: "..avg_ilvl, r, g, b})
                            end
                        end
                    end
                end
            end
            if (isPawnLoaded and TacoTipConfig.show_pawn_player) then
                local pawnScore, specName, specColor = TT_PAWN:GetScore(guid, not TacoTipConfig.show_gs_player)
                if (pawnScore > 0) then
                    if (wide_style) then
                        tinsert(linesToAdd, {string.format("Pawn: %s%.2f|r", specColor, pawnScore), string.format("%s(%s)|r", specColor, specName), 1, 1, 1, 1, 1, 1})
                    elseif (mini_style) then
                        miniText = miniText .. string.format("P: %s%.1f|r", specColor, pawnScore)
                    else
                        tinsert(linesToAdd, {string.format("Pawn: %s%.2f (%s)|r", specColor, pawnScore, specName), 1, 1, 1})
                    end
                end
            end
            if (miniText ~= "") then
                tinsert(linesToAdd, {miniText, 1, 1, 1})
            end
            if (CI:IsWotlk() and TacoTipConfig.show_achievement_points) then
                local achi_pts = CI:GetTotalAchievementPoints(guid)
                if (achi_pts) then
                    if (wide_style) then
                        tinsert(linesToAdd, {ACHIEVEMENT_ICON.." "..achi_pts, " ", 1, 1, 1, 1, 1, 1})
                    else
                        tinsert(linesToAdd, {ACHIEVEMENT_ICON.." "..achi_pts, 1, 1, 1})
                    end
                end
            end
        end
    end

    local n = 0
    for i=1,numLines do
        if (text[i] and text[i] ~= "") then
            n = n+1
            _G["GameTooltipTextLeft"..n]:SetText(text[i])
        end
    end
    if (wide_style) then
        local anchor = "GameTooltipTextLeft"..n
        while (n < numLines) do
            n = n + 1
            _G["GameTooltipTextLeft"..n]:SetText()
            _G["GameTooltipTextRight"..n]:SetText()
            _G["GameTooltipTextLeft"..n]:Hide()
            _G["GameTooltipTextRight"..n]:Hide()
        end
        for _,v in ipairs(linesToAdd) do
            tooltip:AddDoubleLine(unpack(v))
        end
        if (_G["GameTooltipTextLeft"..(n+1)]) then
            _G["GameTooltipTextLeft"..(n+1)]:SetPoint("TOP", _G[anchor], "BOTTOM", 0, -2)
        end
    else
        for _,v in ipairs(linesToAdd) do
            if (n < numLines) then
                n = n+1
                local txt, r, g, b = unpack(v)
                _G["GameTooltipTextLeft"..n]:SetTextColor(r or NORMAL_FONT_COLOR.r, g or NORMAL_FONT_COLOR.g, b or NORMAL_FONT_COLOR.b)
                _G["GameTooltipTextLeft"..n]:SetText(txt)
            else
                tooltip:AddLine(unpack(v))
            end
        end
        while (n < numLines) do
            n = n + 1
            _G["GameTooltipTextLeft"..n]:SetText()
            _G["GameTooltipTextRight"..n]:SetText()
            _G["GameTooltipTextLeft"..n]:Hide()
            _G["GameTooltipTextRight"..n]:Hide()
        end
    end

    if (not TacoTipConfig.show_hp_bar and GameTooltipStatusBar and GameTooltipStatusBar:IsShown()) then
        GameTooltipStatusBar:Hide()
    end

    if (TacoTipConfig.show_power_bar) then
        if (not TacoTipPowerBar) then
            TacoTipPowerBar = CreateFrame("StatusBar", "TacoTipPowerBar", GameTooltip)
            TacoTipPowerBar:SetSize(0, 8)
            TacoTipPowerBar:SetPoint("TOPLEFT", GameTooltip, "BOTTOMLEFT", 2, -9)
            TacoTipPowerBar:SetPoint("TOPRIGHT", GameTooltip, "BOTTOMRIGHT", -2, -9)
            TacoTipPowerBar:SetStatusBarTexture((TT.GetResolvedTooltipStatusBarTexture and TT:GetResolvedTooltipStatusBarTexture()) or "Interface\\TargetingFrame\\UI-TargetingFrame-BarFill")
            TacoTipPowerBar:SetStatusBarColor(0, 0, 1)
            function TacoTipPowerBar:Update(u)
                if (TacoTipConfig.show_power_bar) then
                    local unit = u or resolveTooltipUnit(GameTooltip)
                    if (unit) then
                        local _, power = UnitPowerType(unit)
                        local color = power and PowerBarColor[power] or {}
                        self:SetStatusBarColor(color.r or 0, color.g or 0, color.b or 1);
                        self:SetMinMaxValues(0, UnitPowerMax(unit))
                        self:SetValue(UnitPower(unit))
                    else
                        self:Hide()
                        stopPowerBarTicker()
                    end
                end
            end
            TacoTipPowerBar:SetScript("OnEvent", function(self, event, unit)
                local ttUnit = resolveTooltipUnit(GameTooltip)
                if (unit and ttUnit and UnitIsUnit(unit, ttUnit)) then
                    self:Update(unit)
                end
            end)
            TacoTipPowerBar:RegisterEvent("UNIT_POWER_UPDATE")
            TacoTipPowerBar:RegisterEvent("UNIT_MAXPOWER")
            TacoTipPowerBar:RegisterEvent("UNIT_DISPLAYPOWER")
            TacoTipPowerBar:RegisterEvent("UNIT_POWER_BAR_SHOW")
            TacoTipPowerBar:RegisterEvent("UNIT_POWER_BAR_HIDE")
        end
        if (UnitPowerMax(tooltipUnit) > 0) then
            if (TacoTipConfig.show_hp_bar) then
                TacoTipPowerBar:SetPoint("TOPLEFT", GameTooltip, "BOTTOMLEFT", 2, -9)
                TacoTipPowerBar:SetPoint("TOPRIGHT", GameTooltip, "BOTTOMRIGHT", -2, -9)
            else
                TacoTipPowerBar:SetPoint("TOPLEFT", GameTooltip, "BOTTOMLEFT", 2, -1)
                TacoTipPowerBar:SetPoint("TOPRIGHT", GameTooltip, "BOTTOMRIGHT", -2, -1)
            end
            TacoTipPowerBar:Update()
            TacoTipPowerBar:Show()
            startPowerBarTicker()
        else
            TacoTipPowerBar:Hide()
            stopPowerBarTicker()
        end
    elseif (TacoTipPowerBar) then
        TacoTipPowerBar:Hide()
        stopPowerBarTicker()
    end

    if (TacoTipConfig.tooltip_max_width and TacoTipConfig.tooltip_max_width > 0) then
        tooltip:SetMinimumWidth(0)
        tooltip:SetMaximumWidth(TacoTipConfig.tooltip_max_width)
    end

    TT:ApplyTooltipAppearance(tooltip, tooltipUnit)
end

GameTooltip:HookScript("OnTooltipSetUnit", function(tooltip, ...)
    cancelDelayedTooltip()
    local delay = TacoTipConfig.tooltip_delay or 0
    if (delay > 0 and tooltip == GameTooltip and not InCombatLockdown()) then
        delayedTooltipTimer = C_Timer.NewTimer(delay, function()
            return safeCall(onTooltipSetUnit, tooltip)
        end)
    else
        return safeCall(onTooltipSetUnit, tooltip, ...)
    end
end)

local function clearTooltipVisuals(tooltip)
    if (not tooltip) then
        return
    end
    clearTooltipPlayerClassColor(tooltip)
    if (tooltip.TacoTipPortrait) then
        tooltip.TacoTipPortrait:Hide()
    end
    if (tooltip.TacoTipPortrait3D) then
        tooltip.TacoTipPortrait3D:Hide()
    end
    if (tooltip.TacoTipEliteFrame) then
        tooltip.TacoTipEliteFrame:Hide()
    end
end

local function itemToolTipHook(self)
    clearTooltipVisuals(self)

    local _, itemLink = self:GetItem()
    if (itemLink and IsEquippableItem(itemLink)) then
        if (TacoTipConfig.show_item_level) then
            local ilvl = select(4, GetItemInfo(itemLink))
            if (ilvl and ilvl > 1) then
                self:AddLine(L["Item Level"].." "..ilvl, 1, 1, 1)
            end
        end
        if (TacoTipConfig.show_gs_items) then
            local gs, _, r, g, b = GearScore:GetItemScore(itemLink)
            if (gs and gs > 1) then
                self:AddLine("GearScore: "..gs, r, g, b)
                if (TacoTipConfig.show_gs_items_hs or IsModifierKeyDown() or playerClass == "HUNTER" or
                    (InspectFrame and InspectFrame:IsShown() and InspectFrame.unit and select(2, UnitClass(InspectFrame.unit)) == "HUNTER")) then
                    local hs, _, hsR, hsG, hsB = GearScore:GetItemHunterScore(itemLink)
                    if (gs ~= hs) then
                        self:AddLine((L["HunterScore"] or "HunterScore")..": "..hs, hsR, hsG, hsB)
                    end
                end
            end
        end
    end

    -- Apply cosmetic appearance (font, backdrop texture, border texture) to
    -- item tooltips so user-selected visual style carries through.  Skip
    -- unit-specific effects (class color, portrait, elite frame, bar texture)
    -- since there is no player unit on an item tooltip.
    applyTooltipFonts(self)
    applyTooltipBackdrop(self)
    local backdrop = self and self.TacoTipBackdropFrame
    if (backdrop and backdrop.SetBackdropColor and not backdrop.isBorderOnly) then
        backdrop:SetBackdropColor(
            TacoTipConfig.tooltip_background_color_r or 0,
            TacoTipConfig.tooltip_background_color_g or 0,
            TacoTipConfig.tooltip_background_color_b or 0,
            TacoTipConfig.tooltip_background_alpha or 0.85
        )
    end
    applyTooltipBorderOverlay(self, nil,
        TacoTipConfig.tooltip_border_color_r or 1,
        TacoTipConfig.tooltip_border_color_g or 1,
        TacoTipConfig.tooltip_border_color_b or 1
    )
end

local function safeItemToolTipHook(self, ...)
    return safeCall(itemToolTipHook, self, ...)
end

GameTooltip:HookScript("OnTooltipSetItem", safeItemToolTipHook)
ShoppingTooltip1:HookScript("OnTooltipSetItem", safeItemToolTipHook)
ShoppingTooltip2:HookScript("OnTooltipSetItem", safeItemToolTipHook)
ItemRefTooltip:HookScript("OnTooltipSetItem", safeItemToolTipHook)

-- Spell tooltips: clear stale unit visuals (portrait, elite frame, class color)
-- when the tooltip is re-purposed from a unit to a spell. GameTooltip is a
-- singleton and SetSpell does not always call Clear() first, so a portrait
-- from a previous unit hover would otherwise persist on the spell tooltip.
local function safeClearTooltipVisuals(tooltip, ...)
    return safeCall(clearTooltipVisuals, tooltip, ...)
end

GameTooltip:HookScript("OnTooltipSetSpell", safeClearTooltipVisuals)
ShoppingTooltip1:HookScript("OnTooltipSetSpell", safeClearTooltipVisuals)
ShoppingTooltip2:HookScript("OnTooltipSetSpell", safeClearTooltipVisuals)
ItemRefTooltip:HookScript("OnTooltipSetSpell", safeClearTooltipVisuals)

-- Catch every remaining OnTooltipSet* event so stale unit visuals
-- (portrait, elite frame, class color) are cleared when the tooltip is
-- repurposed for non-unit content.  Belt-and-suspenders alongside the
-- onTooltipShow safety net — covers the frame where Clear() is not called.
-- OnTooltipSetItem and OnTooltipSetSpell are already hooked above.
local nonUnitSetEvents = {
    "OnTooltipSetAchievement",
    "OnTooltipSetQuest",
    "OnTooltipSetSkill",
    "OnTooltipSetToy",
    "OnTooltipSetRecipeRank",
}
for _, event in ipairs(nonUnitSetEvents) do
    GameTooltip:HookScript(event, safeClearTooltipVisuals)
end

GameTooltip:HookScript("OnTooltipCleared", function(tooltip, ...)
    cancelDelayedTooltip()
    return safeCall(clearTooltipVisuals, tooltip, ...)
end)

ShoppingTooltip1:HookScript("OnTooltipCleared", function(tooltip, ...)
    return safeCall(clearTooltipVisuals, tooltip, ...)
end)

ShoppingTooltip2:HookScript("OnTooltipCleared", function(tooltip, ...)
    return safeCall(clearTooltipVisuals, tooltip, ...)
end)

ItemRefTooltip:HookScript("OnTooltipCleared", function(tooltip, ...)
    return safeCall(clearTooltipVisuals, tooltip, ...)
end)

-- Safety net: whenever the tooltip is shown, check whether it actually
-- shows a unit of any kind.  If it does NOT (character panel buttons,
-- flight points, world map pins, raw text tooltips, etc.), proactively
-- clear any stale unit visuals (portrait, elite frame, class color) that
-- might have lingered from a previous OnTooltipSetUnit.
-- This catches every case where OnTooltipCleared doesn't fire because
-- the content was changed in-place without an explicit Clear() call.
local function onTooltipShow(tooltip)
    local unit = resolveTooltipUnit(tooltip)
    if (not unit) then
        -- No unit at all — clear stale unit visuals.
        clearTooltipVisuals(tooltip)
        return
    end

    -- Player-unit tooltip: re-apply the class-tinted border if another
    -- addon or Blizzard re-set the backdrop after OnTooltipSetUnit.
    -- Deferred to the next frame so it runs AFTER Blizzard's own
    -- OnShow/backdrop setup — otherwise Blizzard's subsequent
    -- SetBackdrop resets the border back to default gray.
    if (UnitIsPlayer(unit)) then
        local cached = tooltip and tooltip.TacoTipPlayerClassColor
        if (not cached) then
            return
        end
        if (not TacoTipConfig.tooltip_border_use_class and not TacoTipConfig.color_class) then
            return
        end

        CAfter(0, function()
            return safeCall(function()
                if (not tooltip or not tooltip:IsShown()) then
                    return
                end
                local refreshed = tooltip.TacoTipPlayerClassColor
                if (not refreshed) then
                    return
                end
                if (not TacoTipConfig.tooltip_border_use_class and not TacoTipConfig.color_class) then
                    return
                end
                applyTooltipBorderOverlay(tooltip, nil, refreshed.r, refreshed.g, refreshed.b)
            end)
        end)
    end
end

GameTooltip:HookScript("OnShow", function(tooltip, ...)
    return safeCall(onTooltipShow, tooltip, ...)
end)

GameTooltip:HookScript("OnHide", function()
    cancelDelayedTooltip()
    clearTooltipVisuals(GameTooltip)
end)

-- Broad catch-all: every time ANY code adds a text line to GameTooltip,
-- check whether the tooltip is currently showing a unit.  If it is NOT,
-- clear any stale unit visuals (portrait, elite frame, class color).
-- This is the most reliable safety net because AddLine is the single
-- lowest-level content method called by virtually every code path that
-- populates GameTooltip, including SetText, SetHyperlink, SetAction,
-- SetMerchantItem, and all other Set* methods.  Unit tooltips also go
-- through AddLine, but at that point GetUnit() already returns the unit
-- so we skip the clear.
local function safeCheckClearOnAddLine(self, ...)
    return safeCall(function()
        local unit = resolveTooltipUnit(self)
        if (not unit) then
            clearTooltipVisuals(self)
        end
    end)
end

-- AddLine is safe to hook via hooksecurefunc on all supported clients.
-- If it is not available on a particular client, the pcall silently
-- skips the hook.
pcall(hooksecurefunc, GameTooltip, "AddLine", safeCheckClearOnAddLine)

local function CreateMouseAnchor()
    TacoTipMouseAnchor = CreateFrame("Frame", nil, UIParent)
    TacoTipMouseAnchor:EnableMouse(false)
    TacoTipMouseAnchor:SetMovable(true)
    TacoTipMouseAnchor:SetUserPlaced(false)
    TacoTipMouseAnchor:SetClampedToScreen(true)
    TacoTipMouseAnchor:SetSize(1,1)
    TacoTipMouseAnchor:SetPoint("CENTER",UIParent,"BOTTOMLEFT",0,0)
    TacoTipMouseAnchor:SetScript("OnUpdate", function(self)
        local cx, cy = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        self:ClearAllPoints()
        self:SetPoint("CENTER",UIParent,"BOTTOMLEFT",cx/scale,cy/scale)
    end)
end

hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip, parent)
    if (TacoTipConfig.anchor_mouse_spells) then
        local parentparent = parent and parent:GetParent()
        if (parent and (parent.action or parent.spellId or (parentparent and parentparent.action) or (parentparent and parentparent.spellId))) then
            if (parentparent == MultiBarBottomRight or parentparent == MultiBarRight or parentparent == MultiBarLeft) then
                tooltip:SetOwner(parent, "ANCHOR_LEFT")
            else
                tooltip:SetOwner(parent, "ANCHOR_RIGHT")
            end
            tooltip:EnableMouse(true)
            return
        end
    end
    if (TacoTipConfig.anchor_mouse) then
        if (not TacoTipConfig.anchor_mouse_world or TT:GetMouseFocus() == WorldFrame) then
            if (not TacoTipMouseAnchor) then
                CreateMouseAnchor()
                ---@diagnostic disable-next-line: cast-local-type
                CreateMouseAnchor = nil  -- self-cleanup: prevent re-creation
            end
            tooltip:SetOwner(TacoTipMouseAnchor,"ANCHOR_NONE")
            tooltip:ClearAllPoints()
            tooltip:SetPoint("BOTTOMLEFT", TacoTipMouseAnchor, "CENTER", 10, 10)
            tooltip:EnableMouse(true)
        else
            tooltip:EnableMouse(true)
        end
    else
        if (TacoTipConfig.custom_pos) then
            if (not TacoTipDragButton and TacoTip_CustomPosEnable) then
                TacoTip_CustomPosEnable(false)
            end
            if (TacoTipDragButton) then
                tooltip:SetOwner(TacoTipDragButton,"ANCHOR_NONE")
                tooltip:ClearAllPoints()
                local anchorPoint = TacoTipConfig.custom_anchor or "TOPLEFT"
                tooltip:SetPoint(anchorPoint, TacoTipDragButton, anchorPoint)
                if (TacoTipDragButton:IsShown()) then
                    tooltip:EnableMouse(true)
                else
                    tooltip:EnableMouse(false)
                end
            end
        elseif (TacoTipConfig.show_hp_bar and TacoTipConfig.show_power_bar) then
            tooltip:ClearAllPoints()
            tooltip:SetPoint("BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -CONTAINER_OFFSET_X-13, CONTAINER_OFFSET_Y+9)
            tooltip:EnableMouse(true)
        else
            tooltip:EnableMouse(true)
        end
    end
end)

local function getDefaultTooltipMoverPosition()
    local anchorPoint = (TacoTipConfig and TacoTipConfig.custom_anchor) or "TOPLEFT"
    return {anchorPoint, anchorPoint, 0, 0}
end

local function syncTooltipMoverPosition(showExample)
    if (not TacoTipDragButton) then
        return
    end

    local pos = (TacoTipConfig and TacoTipConfig.custom_pos) or getDefaultTooltipMoverPosition()
    TacoTipDragButton:ClearAllPoints()
    TacoTipDragButton:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])

    if (showExample and TacoTipDragButton:IsShown() and TacoTipDragButton.ShowExample) then
        TacoTipDragButton:ShowExample()
    end
end

TT.SyncTooltipMover = function(self, showExample)
    syncTooltipMoverPosition(showExample)
end

if (GameTooltipStatusBar) then
    GameTooltipStatusBar:HookScript("OnHide", function()
        if (TacoTipPowerBar) then
            TacoTipPowerBar:Hide()
        end
        stopPowerBarTicker()
    end)
end

local function CreateMover(parent, topkek, bottomright, callbackFunc)
    local mover = CreateFrame("Button", nil, parent)
    mover:SetFrameStrata("TOOLTIP")
    mover:SetFrameLevel(999)
    mover:EnableMouse(true)
    mover:SetMovable(true)
    mover:SetUserPlaced(false)
    mover:SetClampedToScreen(true)
    mover:SetPoint("TOPLEFT",topkek,"TOPLEFT")
    mover:SetPoint("BOTTOMRIGHT",bottomright,"BOTTOMRIGHT")
    mover:RegisterForDrag("LeftButton")
    mover:SetScript("OnDragStart", function(self)
        self:StartMoving()
        self:SetScript("OnUpdate", function(updateFrame)
            local cx, cy = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale()
            local fx, fy = parent:GetRect()
            callbackFunc(cx/scale-fx, cy/scale-fy)
        end)
    end)
    mover:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self:SetScript("OnUpdate", nil)
        mover:ClearAllPoints()
        mover:SetPoint("TOPLEFT",topkek,"TOPLEFT")
        mover:SetPoint("BOTTOMRIGHT",bottomright,"BOTTOMRIGHT")
        refreshOptionsUI()
    end)
    return mover
end

function TT:InitCharacterFrame()
    CharacterModelFrame:CreateFontString("PersonalGearScore")
    PersonalGearScore:SetFont(L["CHARACTER_FRAME_GS_VALUE_FONT"], L["CHARACTER_FRAME_GS_VALUE_FONT_SIZE"])
    PersonalGearScore:SetText("0")
    PersonalGearScore.RefreshPosition = function()
        PersonalGearScore:SetPoint("BOTTOMLEFT",PaperDollFrame,"BOTTOMLEFT",L["CHARACTER_FRAME_GS_VALUE_XPOS"] + (TacoTipConfig.character_gs_offset_x or 0),L["CHARACTER_FRAME_GS_VALUE_YPOS"] + (TacoTipConfig.character_gs_offset_y or 0))
    end
    PersonalGearScore:RefreshPosition()

    CharacterModelFrame:CreateFontString("PersonalGearScoreText")
    PersonalGearScoreText:SetFont(L["CHARACTER_FRAME_GS_TITLE_FONT"], L["CHARACTER_FRAME_GS_TITLE_FONT_SIZE"])
    PersonalGearScoreText:SetText("GearScore")
    PersonalGearScoreText.RefreshPosition = function()
        PersonalGearScoreText:SetPoint("BOTTOMLEFT",PaperDollFrame,"BOTTOMLEFT",L["CHARACTER_FRAME_GS_TITLE_XPOS"] + (TacoTipConfig.character_gs_offset_x or 0),L["CHARACTER_FRAME_GS_TITLE_YPOS"] + (TacoTipConfig.character_gs_offset_y or 0))
    end
    PersonalGearScoreText:RefreshPosition()

    CharacterModelFrame:CreateFontString("PersonalAvgItemLvl")
    PersonalAvgItemLvl:SetFont(L["CHARACTER_FRAME_ILVL_VALUE_FONT"], L["CHARACTER_FRAME_ILVL_VALUE_FONT_SIZE"])
    PersonalAvgItemLvl:SetText("0")
    PersonalAvgItemLvl.RefreshPosition = function()
        PersonalAvgItemLvl:SetPoint("BOTTOMLEFT",PaperDollFrame,"BOTTOMLEFT",L["CHARACTER_FRAME_ILVL_VALUE_XPOS"] + (TacoTipConfig.character_ilvl_offset_x or 0),L["CHARACTER_FRAME_ILVL_VALUE_YPOS"] + (TacoTipConfig.character_ilvl_offset_y or 0))
    end
    PersonalAvgItemLvl:RefreshPosition()

    CharacterModelFrame:CreateFontString("PersonalAvgItemLvlText")
    PersonalAvgItemLvlText:SetFont(L["CHARACTER_FRAME_ILVL_TITLE_FONT"], L["CHARACTER_FRAME_ILVL_TITLE_FONT_SIZE"])
    PersonalAvgItemLvlText:SetText("iLvl")
    PersonalAvgItemLvlText.RefreshPosition = function()
        PersonalAvgItemLvlText:SetPoint("BOTTOMLEFT",PaperDollFrame,"BOTTOMLEFT",L["CHARACTER_FRAME_ILVL_TITLE_XPOS"] + (TacoTipConfig.character_ilvl_offset_x or 0),L["CHARACTER_FRAME_ILVL_TITLE_YPOS"] + (TacoTipConfig.character_ilvl_offset_y or 0))
    end
    PersonalAvgItemLvlText:RefreshPosition()

    PaperDollFrame:HookScript("OnShow", TT.RefreshCharacterFrame)
end

function TT:RefreshCharacterFrame()
    if (TT.InitCharacterFrame) then
        TT:InitCharacterFrame()
        TT.InitCharacterFrame = nil
    end
    local MyGearScore, MyAverageScore, r, g, b = 0,0,0,0,0
    if (TacoTipConfig.show_gs_character or TacoTipConfig.show_avg_ilvl) then
        MyGearScore, MyAverageScore = GearScore:GetScore("player")
        r, g, b = GearScore:GetQuality(MyGearScore)
    end
    if (TacoTipConfig.show_gs_character) then
        PersonalGearScore:SetText(MyGearScore);
        PersonalGearScore:SetTextColor(r, g, b, 1)
        PersonalGearScore:Show()
        PersonalGearScoreText:Show()
        if (TacoTipConfig.unlock_info_position) then
            if (not PersonalGearScoreText.mover) then
                PersonalGearScoreText.mover = CreateMover(PaperDollFrame, PersonalGearScore, PersonalGearScoreText, function(ofx, ofy)
                    TacoTipConfig.character_gs_offset_x = ofx-L["CHARACTER_FRAME_GS_TITLE_XPOS"]
                    TacoTipConfig.character_gs_offset_y = ofy-L["CHARACTER_FRAME_GS_TITLE_YPOS"]
                    PersonalGearScore:RefreshPosition()
                    PersonalGearScoreText:RefreshPosition()
                end)
            end
            PersonalGearScoreText.mover:Show()
        elseif (PersonalGearScoreText.mover) then
            PersonalGearScoreText.mover:Hide()
        end
    else
        PersonalGearScore:Hide()
        PersonalGearScoreText:Hide()
        if (PersonalGearScoreText.mover) then
            PersonalGearScoreText.mover:Hide()
        end
    end
    if (TacoTipConfig.show_avg_ilvl) then
        PersonalAvgItemLvl:SetText(MyAverageScore);
        PersonalAvgItemLvl:SetTextColor(r, g, b, 1)
        PersonalAvgItemLvl:Show()
        PersonalAvgItemLvlText:Show()
        if (TacoTipConfig.unlock_info_position) then
            if (not PersonalAvgItemLvlText.mover) then
                PersonalAvgItemLvlText.mover = CreateMover(PaperDollFrame, PersonalAvgItemLvl, PersonalAvgItemLvlText, function(ofx, ofy)
                    TacoTipConfig.character_ilvl_offset_x = ofx-L["CHARACTER_FRAME_ILVL_TITLE_XPOS"]
                    TacoTipConfig.character_ilvl_offset_y = ofy-L["CHARACTER_FRAME_ILVL_TITLE_YPOS"]
                    PersonalAvgItemLvl:RefreshPosition()
                    PersonalAvgItemLvlText:RefreshPosition()
                end)
            end
            PersonalAvgItemLvlText.mover:Show()
        elseif (PersonalAvgItemLvlText.mover) then
            PersonalAvgItemLvlText.mover:Hide()
        end
    else
        PersonalAvgItemLvl:Hide()
        PersonalAvgItemLvlText:Hide()
        if (PersonalAvgItemLvlText.mover) then
            PersonalAvgItemLvlText.mover:Hide()
        end
    end
end


function TT:InitInspectFrame()
    InspectModelFrame:CreateFontString("InspectGearScore")
    InspectGearScore:SetFont(L["INSPECT_FRAME_GS_VALUE_FONT"], L["INSPECT_FRAME_GS_VALUE_FONT_SIZE"])
    InspectGearScore:SetText("0")
    InspectGearScore.RefreshPosition = function()
        InspectGearScore:SetPoint("BOTTOMLEFT",InspectPaperDollFrame,"BOTTOMLEFT",L["INSPECT_FRAME_GS_VALUE_XPOS"] + (TacoTipConfig.inspect_gs_offset_x or 0),L["INSPECT_FRAME_GS_VALUE_YPOS"] + (TacoTipConfig.inspect_gs_offset_y or 0))
    end
    InspectGearScore:RefreshPosition()

    InspectModelFrame:CreateFontString("InspectGearScoreText")
    InspectGearScoreText:SetFont(L["INSPECT_FRAME_GS_TITLE_FONT"], L["INSPECT_FRAME_GS_TITLE_FONT_SIZE"])
    InspectGearScoreText:SetText("GearScore")
    InspectGearScoreText.RefreshPosition = function()
        InspectGearScoreText:SetPoint("BOTTOMLEFT",InspectPaperDollFrame,"BOTTOMLEFT",L["INSPECT_FRAME_GS_TITLE_XPOS"] + (TacoTipConfig.inspect_gs_offset_x or 0),L["INSPECT_FRAME_GS_TITLE_YPOS"] + (TacoTipConfig.inspect_gs_offset_y or 0))
    end
    InspectGearScoreText:RefreshPosition()

    InspectModelFrame:CreateFontString("InspectAvgItemLvl")
    InspectAvgItemLvl:SetFont(L["INSPECT_FRAME_ILVL_VALUE_FONT"], L["INSPECT_FRAME_ILVL_VALUE_FONT_SIZE"])
    InspectAvgItemLvl:SetText("0")
    InspectAvgItemLvl.RefreshPosition = function()
        InspectAvgItemLvl:SetPoint("BOTTOMLEFT",InspectPaperDollFrame,"BOTTOMLEFT",L["INSPECT_FRAME_ILVL_VALUE_XPOS"] + (TacoTipConfig.inspect_ilvl_offset_x or 0),L["INSPECT_FRAME_ILVL_VALUE_YPOS"] + (TacoTipConfig.inspect_ilvl_offset_y or 0))
    end
    InspectAvgItemLvl:RefreshPosition()

    InspectModelFrame:CreateFontString("InspectAvgItemLvlText")
    InspectAvgItemLvlText:SetFont(L["INSPECT_FRAME_ILVL_TITLE_FONT"], L["INSPECT_FRAME_ILVL_TITLE_FONT_SIZE"])
    InspectAvgItemLvlText:SetText("iLvl")
    InspectAvgItemLvlText.RefreshPosition = function()
        InspectAvgItemLvlText:SetPoint("BOTTOMLEFT",InspectPaperDollFrame,"BOTTOMLEFT",L["INSPECT_FRAME_ILVL_TITLE_XPOS"] + (TacoTipConfig.inspect_ilvl_offset_x or 0),L["INSPECT_FRAME_ILVL_TITLE_YPOS"] + (TacoTipConfig.inspect_ilvl_offset_y or 0))
    end
    InspectAvgItemLvlText:RefreshPosition()

    InspectPaperDollFrame:HookScript("OnShow", TT.RefreshInspectFrame)
    InspectFrame:HookScript("OnHide", function()
        InspectGearScore:Hide()
        InspectAvgItemLvl:Hide()
    end)
end

function TT:RefreshInspectFrame()
    if (InCombatLockdown()) then
        return
    end
    if (TT.InitInspectFrame) then
        if (not InspectModelFrame or not InspectPaperDollFrame) then
            return
        end
        TT:InitInspectFrame()
        TT.InitInspectFrame = nil
    end
    local inspect_gs, inspect_avg, r, g, b = 0,0,0,0,0
    if (TacoTipConfig.show_gs_character or TacoTipConfig.show_avg_ilvl) then
        inspect_gs, inspect_avg = GearScore:GetScore(InspectFrame.unit)
        r, g, b = GearScore:GetQuality(inspect_gs)
    end
    if (TacoTipConfig.show_gs_character) then
        InspectGearScore:SetText(inspect_gs);
        InspectGearScore:SetTextColor(r, g, b, 1)
        InspectGearScore:Show()
        InspectGearScoreText:Show()
        if (TacoTipConfig.unlock_info_position) then
            if (not InspectGearScoreText.mover) then
                InspectGearScoreText.mover = CreateMover(InspectPaperDollFrame, InspectGearScore, InspectGearScoreText, function(ofx, ofy)
                    TacoTipConfig.inspect_gs_offset_x = ofx-L["INSPECT_FRAME_GS_TITLE_XPOS"]
                    TacoTipConfig.inspect_gs_offset_y = ofy-L["INSPECT_FRAME_GS_TITLE_YPOS"]
                    InspectGearScore:RefreshPosition()
                    InspectGearScoreText:RefreshPosition()
                end)
            end
            InspectGearScoreText.mover:Show()
        elseif (InspectGearScoreText.mover) then
            InspectGearScoreText.mover:Hide()
        end
    else
        InspectGearScore:Hide()
        InspectGearScoreText:Hide()
        if (InspectGearScoreText.mover) then
            InspectGearScoreText.mover:Hide()
        end
    end
    if (TacoTipConfig.show_avg_ilvl) then
        InspectAvgItemLvl:SetText(inspect_avg);
        InspectAvgItemLvl:SetTextColor(r, g, b, 1)
        InspectAvgItemLvl:Show()
        InspectAvgItemLvlText:Show()
        if (TacoTipConfig.unlock_info_position) then
            if (not InspectAvgItemLvlText.mover) then
                InspectAvgItemLvlText.mover = CreateMover(InspectPaperDollFrame, InspectAvgItemLvl, InspectAvgItemLvlText, function(ofx, ofy)
                    TacoTipConfig.inspect_ilvl_offset_x = ofx-L["INSPECT_FRAME_ILVL_TITLE_XPOS"]
                    TacoTipConfig.inspect_ilvl_offset_y = ofy-L["INSPECT_FRAME_ILVL_TITLE_YPOS"]
                    InspectAvgItemLvl:RefreshPosition()
                    InspectAvgItemLvlText:RefreshPosition()
                end)
            end
            InspectAvgItemLvlText.mover:Show()
        elseif (InspectAvgItemLvlText.mover) then
            InspectAvgItemLvlText.mover:Hide()
        end
    else
        InspectAvgItemLvl:Hide()
        InspectAvgItemLvlText:Hide()
        if (InspectAvgItemLvlText.mover) then
            InspectAvgItemLvlText.mover:Hide()
        end
    end
end

function TT:GetMouseFocus()
    if (GetMouseFoci) then
        local frames = GetMouseFoci()
        return frames and frames[1]
    end
    return GetMouseFocus()
end

local function onEvent(self, event, ...)
    if (event == "PLAYER_EQUIPMENT_CHANGED") then
        if (PaperDollFrame and PaperDollFrame:IsShown()) then
            TT:RefreshCharacterFrame()
        end
    elseif (event == "MODIFIER_STATE_CHANGED") then
        local unit = resolveTooltipUnit(GameTooltip)
        if (unit and UnitIsPlayer(unit)) then
            GameTooltip:SetUnit(unit)
        end
    elseif (event == "UNIT_TARGET") then
        local unit = ...
        if (unit) then
            local ttUnit = resolveTooltipUnit(GameTooltip)
            if (UnitExists(unit) and ttUnit and UnitIsUnit(unit, ttUnit)) then
                GameTooltip:SetUnit(unit)
            end
        end
    elseif (event == "ADDON_LOADED") then
        local addon = ...
        if (addon == addOnName) then
            self:UnregisterEvent("ADDON_LOADED")
            registerSharedMediaCallbacks()
            if (TT.ApplyConfigDefaults) then
                TT:ApplyConfigDefaults(TacoTipConfig)
            end
            local first_login = (TacoTipConfig.conf_version ~= addOnVersion)
            if (first_login) then
                TacoTipConfig.conf_version = addOnVersion
            end
            if (TacoTipConfig.custom_pos) then
                TacoTip_CustomPosEnable(false)
            end
            if (TacoTipConfig.instant_fade) then
                self:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
                local function safeFadeOut(tooltipFrame)
                    tooltipFrame:Hide()
                end
                Detours:DetourHook(TT, GameTooltip, "FadeOut", function(tooltipFrame, ...)
                    return safeCall(safeFadeOut, tooltipFrame, ...)
                end)
            end
            if (CharacterModelFrame and PaperDollFrame) then
                TT:RefreshCharacterFrame()
            end
            CAfter(3, function()
                print("|cff59f0dcTacoTip v"..addOnVersion.." "..L["TEXT_HELP_WELCOME"])
                if (first_login) then
                    print("|cff59f0dcTacoTip:|r "..L["TEXT_HELP_FIRST_LOGIN"])
                end
            end)
        end
    elseif (event == "UPDATE_MOUSEOVER_UNIT") then
        if (resolveTooltipUnit(GameTooltip)) then
            CAfter(0, function()
                if (not UnitExists("mouseover")) then
                    GameTooltip:Hide()
                end
            end)
        end
    else -- INVENTORY_READY / TALENTS_READY
        if (TT.InitInspectFrame and InspectModelFrame and InspectPaperDollFrame) then
            TT:InitInspectFrame()
            TT.InitInspectFrame = nil
        end
        local guid = ...
        if (guid) then
            local ttUnit = resolveTooltipUnit(GameTooltip)
            if (ttUnit and UnitGUID(ttUnit) == guid) then
                GameTooltip:SetUnit(ttUnit)
            end
            if (event == "INVENTORY_READY") then
                if (InspectFrame and InspectFrame:IsShown()) then
                    TT:RefreshInspectFrame()
                end
            end
        end
    end
end

do
    local f = CreateFrame("Frame")
    f:SetScript("OnEvent", function(self, event, ...)
        return safeCall(onEvent, self, event, ...)
    end)
    f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    f:RegisterEvent("MODIFIER_STATE_CHANGED")
    f:RegisterEvent("UNIT_TARGET")
    f:RegisterEvent("ADDON_LOADED")
    CI.RegisterCallback(addOnName, "INVENTORY_READY", function(...) return safeCall(onEvent, f, ...) end)
    CI.RegisterCallback(addOnName, "TALENTS_READY", function(...) return safeCall(onEvent, f, ...) end)
    TT.frame = f
end


function TacoTip_CustomPosEnable(show)
    if (not TacoTipDragButton) then
        TacoTipDragButton = CreateFrame("Button", nil, UIParent)
        TacoTipDragButton:SetFrameStrata("TOOLTIP")
        TacoTipDragButton:SetFrameLevel(999)
        TacoTipDragButton:EnableMouse(true)
        TacoTipDragButton:SetMovable(true)
        TacoTipDragButton:SetUserPlaced(false)
        TacoTipDragButton:SetClampedToScreen(true)
        TacoTipDragButton:SetSize(32,32)
        TacoTipDragButton:SetNormalTexture("Interface\\MINIMAP\\TempleofKotmogu_ball_green")
        local pos = TacoTipConfig.custom_pos or getDefaultTooltipMoverPosition()
        TacoTipDragButton:SetPoint(pos[1],UIParent,pos[2],pos[3],pos[4])
        TacoTipDragButton:RegisterForDrag("LeftButton")
        TacoTipDragButton:RegisterForClicks("MiddleButtonUp", "RightButtonUp")
        local function onDragButtonDragStop(self)
            self:SetScript("OnUpdate", nil)
            self:StopMovingOrSizing()
            local from, _, to, x, y = self:GetPoint()
            TacoTipConfig.custom_pos = {from, to, x, y}
            syncTooltipMoverPosition(true)
            refreshOptionsUI()
        end
        local function onDragButtonClick(self, button, down)
            if (button == "MiddleButton") then
                if (TacoTipConfig.custom_anchor == "TOPRIGHT") then
                    TacoTipConfig.custom_anchor = "BOTTOMRIGHT"
                elseif (TacoTipConfig.custom_anchor == "BOTTOMRIGHT") then
                    TacoTipConfig.custom_anchor = "BOTTOMLEFT"
                elseif (TacoTipConfig.custom_anchor == "BOTTOMLEFT") then
                    TacoTipConfig.custom_anchor = "CENTER"
                elseif (TacoTipConfig.custom_anchor == "CENTER") then
                    TacoTipConfig.custom_anchor = "TOPLEFT"
                else
                    TacoTipConfig.custom_anchor = "TOPRIGHT"
                end
                TacoTipDragButton:ShowExample()
                refreshOptionsUI()
            elseif (button == "RightButton") then
                rawset(StaticPopupDialogs, "_TacoTipDragButtonConfirm_", {["whileDead"]=1,["hideOnEscape"]=1,["timeout"]=0,["exclusive"]=1,["enterClicksFirstButton"]=1,["text"]=L["TEXT_DLG_CUSTOM_POS_CONFIRM"],
                ["button1"]=SAVE,["button2"]=CANCEL,["button3"]=RESET,["OnAccept"]=function() TacoTipDragButton:_Save() end,["OnAlt"]=function() TacoTipDragButton:_ResetPosition() end})
                StaticPopup_Show("_TacoTipDragButtonConfirm_")
            end
        end
        local function onDragButtonShow(self)
            if (self.ticker) then
                self.ticker:Cancel()
            end
            local function onMoverTick()
                TacoTipDragButton:ShowExample()
            end
            self.ticker = NewTicker(1, function(...)
                return safeCall(onMoverTick, ...)
            end)
            local function onMoverGameTooltipShow(tooltipFrame)
                if (TacoTipDragButton:IsShown()) then
                    local shownUnit = resolveTooltipUnit(tooltipFrame)
                    if (not shownUnit or not UnitIsUnit(shownUnit, "player")) then
                        TacoTipDragButton:ShowExample()
                    end
                end
            end
            local function onMoverGameTooltipHide(tooltipFrame)
                if (TacoTipDragButton:IsShown()) then
                    TacoTipDragButton:ShowExample()
                end
            end
            Detours:ScriptHook(TT, GameTooltip, "OnShow", function(tooltipFrame, ...)
                return safeCall(onMoverGameTooltipShow, tooltipFrame, ...)
            end)
            Detours:ScriptHook(TT, GameTooltip, "OnHide", function(tooltipFrame, ...)
                return safeCall(onMoverGameTooltipHide, tooltipFrame, ...)
            end)
            TacoTipDragButton:ShowExample()
            print("|cff59f0dcTacoTip:|r "..L["TEXT_HELP_MOVER_SHOWN"])
        end
        local function onDragButtonHide(self)
            if (self.ticker) then
                self.ticker:Cancel()
            end
            Detours:ScriptUnhook(TT, GameTooltip, "OnShow")
            Detours:ScriptUnhook(TT, GameTooltip, "OnHide")
        end
        TacoTipDragButton:SetScript("OnDragStart", function(self, ...)
            return safeCall(function()
                self:StartMoving()
                self:SetScript("OnUpdate", function()
                    if (not GameTooltip:IsShown() or not TacoTipConfig.custom_pos) then
                        return
                    end
                    local anchorPoint = TacoTipConfig.custom_anchor or "TOPLEFT"
                    GameTooltip:ClearAllPoints()
                    GameTooltip:SetPoint(anchorPoint, self, anchorPoint)
                end)
            end, ...)
        end)
        TacoTipDragButton:SetScript("OnDragStop", function(self, ...)
            return safeCall(onDragButtonDragStop, self, ...)
        end)
        TacoTipDragButton:SetScript("OnClick", function(self, button, down, ...)
            return safeCall(onDragButtonClick, self, button, down, ...)
        end)
        TacoTipDragButton:SetScript("OnShow", function(self, ...)
            return safeCall(onDragButtonShow, self, ...)
        end)
        TacoTipDragButton:SetScript("OnHide", function(self, ...)
            return safeCall(onDragButtonHide, self, ...)
        end)
        function TacoTipDragButton:ShowExample()
            if (GameTooltip_SetDefaultAnchor) then
                GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
            end
            GameTooltip:SetUnit("player")
            GameTooltip:AddDoubleLine(L["Left-Click"], L["Drag to Move"], 1, 1, 1)
            GameTooltip:AddDoubleLine(L["Middle-Click"], L["Change Anchor"], 1, 1, 1)
            GameTooltip:AddDoubleLine(L["Right-Click"], L["Save Position"], 1, 1, 1)
            GameTooltip:Show()
        end
        function TacoTipDragButton:_Enable()
            local customPositionCheck = _G.TacoTipOptCheckBoxCustomPosition
            local moverButton = _G.TacoTipOptButtonMover
            local anchorMouseCheck = _G.TacoTipOptCheckBoxAnchorMouse
            local anchorMouseWorldCheck = _G.TacoTipOptCheckBoxAnchorMouseWorld
            if (not TacoTipConfig.custom_pos) then
                TacoTipConfig.custom_pos = getDefaultTooltipMoverPosition()
                print("|cff59f0dcTacoTip:|r "..L["Custom tooltip position enabled."])
            end
            syncTooltipMoverPosition(false)
            if (customPositionCheck) then
                customPositionCheck:SetChecked(true)
            end
            if (moverButton) then
                setButtonEnabled(moverButton, true)
            end
            if (anchorMouseCheck) then
                anchorMouseCheck:SetChecked(false)
                anchorMouseCheck:SetDisabled(true)
            end
            if (anchorMouseWorldCheck) then
                anchorMouseWorldCheck:SetDisabled(true)
            end
            TacoTipConfig.anchor_mouse = false
            refreshOptionsUI()
        end
        function TacoTipDragButton:_Save()
            syncTooltipMoverPosition(false)
            GameTooltip:EnableMouse(false)
            TacoTipDragButton:Hide()
            print("|cff59f0dcTacoTip:|r "..L["TEXT_HELP_MOVER_SAVED"])
            refreshOptionsUI()
        end
        function TacoTipDragButton:_ResetPosition()
            TacoTipConfig.custom_pos = getDefaultTooltipMoverPosition()
            syncTooltipMoverPosition(true)
            refreshOptionsUI()
        end
        function TacoTipDragButton:_Disable(preserveAnchor)
            local customPositionCheck = _G.TacoTipOptCheckBoxCustomPosition
            local moverButton = _G.TacoTipOptButtonMover
            local anchorMouseCheck = _G.TacoTipOptCheckBoxAnchorMouse
            TacoTipDragButton:Hide()
            GameTooltip:Hide()
            GameTooltip:ClearAllPoints()
            if (TacoTipConfig.custom_pos) then
                print("|cff59f0dcTacoTip:|r "..L["Custom tooltip position disabled."])
            end
            if (customPositionCheck) then
                customPositionCheck:SetChecked(false)
            end
            if (moverButton) then
                setButtonEnabled(moverButton, false)
            end
            if (anchorMouseCheck) then
                anchorMouseCheck:SetDisabled(false)
            end
            TacoTipConfig.custom_pos = nil
            if (not preserveAnchor) then
                TacoTipConfig.custom_anchor = nil
            end
            refreshOptionsUI()
        end
        TacoTipDragButton:Hide()
    end
    TacoTipDragButton:_Enable()
    if (show) then
        TacoTipDragButton:Show()
    else
        TacoTipDragButton:Hide()
    end
end
