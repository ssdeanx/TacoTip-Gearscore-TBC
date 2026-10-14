local addOnName = ...
local addOnVersion = (GetAddOnMetadata and GetAddOnMetadata(addOnName, "Version")) or
    (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addOnName, "Version")) or "0.7.7"

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

local TT = _G[addOnName]

if (not TT) then
    TT = {}
    rawset(_G, addOnName, TT)
end

function TT.GetTooltipLeftLine(tooltip, index)
    if (not tooltip or not index) then return nil end
    if (tooltip.GetLeftLine) then
        return tooltip:GetLeftLine(index)
    end
    local name = tooltip.GetName and tooltip:GetName()
    if (name) then
        return _G[name .. "TextLeft" .. index]
    end
    return nil
end

function TT.GetTooltipRightLine(tooltip, index)
    if (not tooltip or not index) then return nil end
    if (tooltip.GetRightLine) then
        return tooltip:GetRightLine(index)
    end
    local name = tooltip.GetName and tooltip:GetName()
    if (name) then
        return _G[name .. "TextRight" .. index]
    end
    return nil
end

local getTooltipLeftLine = TT.GetTooltipLeftLine
local getTooltipRightLine = TT.GetTooltipRightLine

-- SoD-era Pawn does not expose PawnClassicLastUpdatedVersion, so the old
-- version-only gate made the whole module return early and Pawn never loaded.
-- Also accept the presence of Pawn's public API functions as proof of load.
local pawnApiPresent = type(_G.PawnGetItemData) == "function" and type(_G.PawnGetSingleValueFromItem) == "function" and
    type(_G.PawnGetScaleColor) == "function"
local isPawnLoaded = (_G.PawnClassicLastUpdatedVersion and _G.PawnClassicLastUpdatedVersion >= 2.0538) or pawnApiPresent

local HORDE_ICON = "|TInterface\\TargetingFrame\\UI-PVP-HORDE:16:16:-2:0:64:64:0:38:0:38|t"
local ALLIANCE_ICON = "|TInterface\\TargetingFrame\\UI-PVP-ALLIANCE:16:16:-2:0:64:64:0:38:0:38|t"
local PVP_FLAG_ICON = "|TInterface\\GossipFrame\\BattleMasterGossipIcon:0|t"
local ACHIEVEMENT_ICON = "|TInterface\\AchievementFrame\\UI-Achievement-TinyShield:18:18:0:0:20:20:0:12.5:0:12.5|t"
local GetClassAtlas = _G.GetClassAtlas

local POWERBAR_UPDATE_RATE = 0.2

local NewTicker = _G.C_Timer and _G.C_Timer.NewTicker
local NewTimer = _G.C_Timer and _G.C_Timer.NewTimer
local CAfter = _G.C_Timer and _G.C_Timer.After
local GetBestMapForUnit = _G.C_Map and _G.C_Map.GetBestMapForUnit
-- C_Item namespace (Classic Era 1.15.x, TBC Anniversary 2.5.x and Wrath 3.4.x
-- all publish it via Blizzard_ObjectAPI; verified against wow-ui-source).
local Item = _G.Item
local RequestLoadItemDataByID = _G.C_Item and _G.C_Item.RequestLoadItemDataByID
local GameTooltip_SetDefaultAnchor = _G.GameTooltip_SetDefaultAnchor
local UnitClass = _G.UnitClass
local UnitCanAttack = _G.UnitCanAttack
-- v0.7.4: per-tooltip state. Every timer/generation/refresh handle now lives
-- on the tooltip frame itself, so clearing/hiding one tooltip can never cancel
-- or stale-out another tooltip's pending work (the pre-0.7.4 module-level
-- locals were shared by GameTooltip, ShoppingTooltip1/2, ItemRefTooltip,
-- WorldMapTooltip and SmallTextTooltip — clearing a shopping tooltip could
-- cancel the main tooltip's delayed-appearance timer).

-- Per-tooltip lifecycle state, stored on the frame as tooltip._tacoTipState.
-- All handles are cleared or invalidated by clearTooltipVisuals on every
-- clear/hide transition.
---@class tacoTipTooltipState
---@field generation integer           -- clear/hide epoch; stale callbacks bail on mismatch
---@field currentUnitGUID string|nil   -- GUID of the unit currently rendered
---@field currentItemLink string|nil   -- item link currently rendered
---@field itemLoadCancel function|nil  -- C_Item.ContinueWithCancelOnItemLoad canceler
---@field delayedTooltipTimer table|nil -- cancellable NewTimer handle (unit-tooltip delay)
---@field borderDeferTimer table|nil    -- cancellable NewTimer handle (defensive border re-apply)
---@field classBorderDeferTimer table|nil -- cancellable NewTimer handle (OnShow class-border re-apply)
---@field fadeTimer table|nil           -- cancellable NewTimer handle (instant fade)

-- Inert fallback state for getTooltipState(nil): keeps the documented
-- "state is always a table" contract so no call site needs a nil check.
-- Nothing ever reads this table's fields back (no real tooltip owns it),
-- except the generation counter which is stateless by design.
local nilTooltipState = { generation = 0 }

---Return the per-tooltip state table, creating it on first use. When
---tooltip is nil, returns a shared inert fallback state (generation
---counter still increments) so callers can index state fields without
---nil-checks — writes there are simply never read by any real tooltip.
---@param tooltip table|nil WoW tooltip frame (or any frame used as tooltip)
---@return tacoTipTooltipState
local function getTooltipState(tooltip)
    if (not tooltip) then
        return nilTooltipState
    end
    if (not tooltip._tacoTipState) then
        tooltip._tacoTipState = { generation = 0 }
    end
    return tooltip._tacoTipState
end

local function cancelTooltipTimer(tooltip, field)
    local state = getTooltipState(tooltip)
    local timer = state and state[field]
    if (timer) then
        timer:Cancel()
        state[field] = nil
    end
end

local function cancelItemLoadRefresh(tooltip)
    local state = getTooltipState(tooltip)
    local cancel = state and state.itemLoadCancel
    if (cancel) then
        pcall(cancel)
        state.itemLoadCancel = nil
    end
end
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

-- Modern tooltip templates (GameTooltipTemplate -> TooltipBackdropTemplate)
-- attach a NineSlice child frame that renders the actual backdrop; this is
-- verified present on Classic Era, TBC Anniversary AND Wrath (the era
-- SharedTooltipTemplates.xml ships it, not just the 2.5.3+ UI consolidation).
-- SetBackdrop/SetBackdropBorderColor on the parent has NO visual effect when
-- NineSlice renders the backdrop. The apply-backdrop functions below detect
-- the NineSlice child at runtime and use NineSlice:SetBorderColor/
-- SetCenterColor directly. This early Mixin provides a fallback for any
-- client whose tooltip template lacks NineSlice.
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
    if (TacoTipPowerBar) then
        if (TacoTipPowerBar.updateTicker) then
            TacoTipPowerBar.updateTicker:Cancel()
            TacoTipPowerBar.updateTicker = nil
        end
        if (TacoTipPowerBar.UnregisterAllEvents) then
            TacoTipPowerBar:UnregisterAllEvents()
        end
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
                    if (TT.InvalidateResolvedMediaCache) then
                        TT:InvalidateResolvedMediaCache()
                    end
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

local function getClassIconMarkup(class)
    if (not class or not GetClassAtlas) then
        return ""
    end
    local atlas = GetClassAtlas(class)
    if (atlas and atlas ~= "") then
        local size = TacoTipConfig.class_icon_size or 20
        return string.format("|A:%s:%d:%d|a", atlas, size, size)
    end
    return ""
end

TT.GetClassIconMarkup = function(self, class)
    return getClassIconMarkup(class)
end

local SHAMAN_BLUE_COLOR = { r = 0.0, g = 0.44, b = 0.87, colorStr = "ff0070de" }

local function getClassColor(class)
    if (not class) then
        return nil
    end
    if (class == "SHAMAN" and (not TacoTipConfig or TacoTipConfig.shaman_blue ~= false)) then
        return SHAMAN_BLUE_COLOR
    end
    local color = CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[class]
    if (not color and RAID_CLASS_COLORS) then
        color = RAID_CLASS_COLORS[class]
    end
    return color
end

TT.GetClassColor = getClassColor

local function clearTooltipPlayerClassColor(tooltip)
    if (tooltip) then
        tooltip.TacoTipPlayerClassColor = nil
    end
end

local function clearTooltipGuildLine(tooltip)
    if (tooltip and tooltip.TacoTipGuildLineIndex) then
        local left = getTooltipLeftLine(tooltip, tooltip.TacoTipGuildLineIndex)
        if (left) then
            left:SetText()
        end
        tooltip.TacoTipGuildLineIndex = nil
    end
end

local function clearTooltipLevelColorLine(tooltip)
    if (tooltip and tooltip.TacoTipLevelColorLineIndex) then
        local left = getTooltipLeftLine(tooltip, tooltip.TacoTipLevelColorLineIndex)
        if (left) then
            left:SetText()
        end
        tooltip.TacoTipLevelColorLineIndex = nil
    end
end

local function storeTooltipPlayerClassColor(tooltip, unit)
    if (not tooltip) then
        return nil
    end
    -- Any unit we cannot resolve to a real player must invalidate the cached
    -- class color.  Returning the stale cache here is what let a previous
    -- player's class color bleed onto an enemy tooltip during frame recycle.
    if (not unit or not UnitExists or not UnitExists(unit) or not UnitIsPlayer or not UnitIsPlayer(unit)) then
        clearTooltipPlayerClassColor(tooltip)
        return nil
    end

    local _, class = UnitClass(unit)
    local classColor = getClassColor(class)
    if (not classColor) then
        clearTooltipPlayerClassColor(tooltip)
        return nil
    end

    local cachedColor = tooltip._tacoTipClassColorTable
    if (not cachedColor) then
        cachedColor = {}
        tooltip._tacoTipClassColorTable = cachedColor
    end
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
    if (not unit or not GetQuestDifficultyColor) then
        return nil
    end

    if (UnitCanAttack and not UnitCanAttack("player", unit) and UnitIsPlayer and UnitIsPlayer(unit)) then
        return nil
    end

    local level = UnitLevel(unit)
    if (level and level > 0) then
        return GetQuestDifficultyColor(level)
    end

    return GetQuestDifficultyColor((UnitLevel("player") or 1) + 10)
end

local function colorizeUnitLevelLine(tooltip, unit, textLine, lineIndex)
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

    if (tooltip and lineIndex) then
        tooltip.TacoTipLevelColorLineIndex = lineIndex
    end

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
        local ok, name, iconTexture, tier, _, _, _, isExceptional = pcall(CI.GetTalentInfoByClass, CI, class, specIndex,
            talentIndex)
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

local function formatSpecializationText(class, specIndex, p1, p2, p3, dim)
    -- Prefer TacoTip's own per-locale spec-name table (Locale/*.lua); it
    -- follows the saved addon-language override, which the library's
    -- GetLocale()-derived table cannot. Fall back to the library's
    -- localized table when TacoTip's locale hasn't shipped that class.
    local specName
    if (class and specIndex) then
        local tacoNames = _G.TACOTIP_SPEC_NAMES
        local tacoRow = tacoNames and tacoNames[class]
        if (tacoRow) then
            specName = tacoRow[specIndex]
        end
        if (not specName) then
            specName = CI:GetSpecializationName(class, specIndex, true)
        end
    end
    if (not specName) then
        return nil
    end

    local iconTexture = getSpecializationIcon(class, specIndex)
    local iconText = iconTexture and string.format("|T%s:14:14:0:0:64:64:4:60:4:60|t ", tostring(iconTexture)) or ""
    local classColor = getClassColor(class)
    -- Inactive dual-spec run: spec name is greyed out using lowest GearScore
    -- quality color (0.50, 0.50, 0.50 / GRAY_FONT_COLOR), while the active
    -- spec uses class color. The color code is applied strictly to specName
    -- so talent numbers [p1/p2/p3] remain clean white for both specs.
    local coloredName
    if (dim) then
        coloredName = colorizeText(specName, 0.50, 0.50, 0.50)
    else
        coloredName = classColor and colorizeText(specName, classColor.r, classColor.g, classColor.b) or specName
    end
    return string.format("%s%s [%d/%d/%d]", iconText, coloredName, p1 or 0, p2 or 0, p3 or 0)
end

TT.GetFormattedSpecializationText = function(self, class, specIndex, p1, p2, p3, dim)
    return formatSpecializationText(class, specIndex, p1, p2, p3, dim)
end

local function onPortraitModelUpdate(self, elapsed)
    self.ttElapsed = (self.ttElapsed or 0) + (elapsed or 0)
    if (self.ttElapsed < 0.05) then
        return
    end
    self.ttElapsed = 0
    local parent = self:GetParent()
    if (parent and parent.GetAlpha) then
        local a = parent:GetAlpha()
        if (self:GetAlpha() ~= a) then
            self:SetAlpha(a)
        end
    end
end

local function ensureTooltipPortrait(tooltip)
    if (not tooltip) then
        return nil
    end
    local use3D = TacoTipConfig.tooltip_portrait_3d
    if (use3D) then
        if (not tooltip.TacoTipPortrait3D) then
            local ok, model = pcall(CreateFrame, "PlayerModel", nil, tooltip)
            if (ok and model) then
                tooltip.TacoTipPortrait3D = model
                tooltip.TacoTipPortrait3D:SetFrameLevel(tooltip:GetFrameLevel() + 1)
                tooltip.TacoTipPortrait3D:EnableMouse(false)
                tooltip.TacoTipPortrait3D:SetScript("OnUpdate", onPortraitModelUpdate)
            end
        elseif (tooltip.TacoTipPortrait3D.SetScript and not tooltip.TacoTipPortrait3D:GetScript("OnUpdate")) then
            tooltip.TacoTipPortrait3D:SetScript("OnUpdate", onPortraitModelUpdate)
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
    if (not tooltip) then
        return
    end
    local fontPath = (TT.GetResolvedTooltipFont and TT:GetResolvedTooltipFont()) or TacoTipConfig.tooltip_font or
        "Fonts\\FRIZQT__.TTF"
    local fontSize = TacoTipConfig.tooltip_font_size or 12
    local numLines = (tooltip.NumLines and tooltip:NumLines()) or 0
    for i = 1, math.max(numLines + 4, 20) do
        local left = getTooltipLeftLine(tooltip, i)
        local right = getTooltipRightLine(tooltip, i)
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

    -- NineSlice-equipped tooltips (verified on all supported clients):
    -- create a border-only overlay frame.
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

    -- Legacy fallback (tooltip without a NineSlice child): ensure the
    -- tooltip has SetBackdrop and use it directly
    if (not tooltip.SetBackdrop and BackdropTemplateMixin and Mixin) then
        Mixin(tooltip, BackdropTemplateMixin)
    end
    tooltip.TacoTipBackdropFrame = tooltip
    return tooltip, false
end

local function applyTooltipBackdrop(tooltip)
    local backdrop = getOrCreateBackdropFrame(tooltip)
    if (not backdrop or not backdrop.SetBackdrop) then
        return
    end

    local backgroundTexture = (TT.GetResolvedTooltipBackground and TT:GetResolvedTooltipBackground()) or
        TacoTipConfig.tooltip_background_texture or "Interface\\Tooltips\\UI-Tooltip-Background"
    local borderTexture = (TT.GetResolvedTooltipBorder and TT:GetResolvedTooltipBorder()) or
        TacoTipConfig.tooltip_border_texture or "Interface\\Tooltips\\UI-Tooltip-Border"
    local hasBorder = borderTexture and borderTexture ~= "" and borderTexture ~= "Interface\\None"

    if (backdrop.isBorderOnly) then
        -- NineSlice-equipped tooltip: border overlay only. NineSlice provides
        -- the default background — we only draw the colored border on top.
        backdrop:SetBackdrop({
            edgeFile = hasBorder and borderTexture or nil,
            edgeSize = hasBorder and (TacoTipConfig.tooltip_border_edge_size or 14) or 0,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
    else
        -- Legacy full backdrop: background + border on the tooltip itself
        backdrop:SetBackdrop({
            bgFile = backgroundTexture,
            edgeFile = hasBorder and borderTexture or nil,
            tile = true,
            tileSize = 16,
            edgeSize = hasBorder and (TacoTipConfig.tooltip_border_edge_size or 14) or 0,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
    end
end

local function applyTooltipBorderOverlay(tooltip, unit, borderR, borderG, borderB)
    local backdrop = tooltip and tooltip.TacoTipBackdropFrame
    if (not backdrop or not backdrop.SetBackdropBorderColor) then
        return
    end

    local borderTexture = (TT.GetResolvedTooltipBorder and TT:GetResolvedTooltipBorder()) or
        TacoTipConfig.tooltip_border_texture or "Interface\\Tooltips\\UI-Tooltip-Border"
    local hasBorder = borderTexture and borderTexture ~= "" and borderTexture ~= "Interface\\None"
    if (not hasBorder) then
        return
    end

    backdrop:SetBackdropBorderColor(borderR, borderG, borderB, TacoTipConfig.tooltip_border_alpha or 0.85)
end

-- Reset the tooltip border to the user's configured base (non-class) color.
-- Called at the tooltip-recycle boundary (OnTooltipCleared / non-unit OnShow)
-- so a previous player's class-colored border cannot bleed onto item, spell,
-- minimap, or world-map POI tooltips that reuse GameTooltip.
-- NOTE: This deliberately bypasses applyTooltipBorderOverlay because that
-- function checks borderTexture and returns early when the texture is nil or
-- "Interface\\None", leaving the stale class-colored border in place.  The
-- direct frame write below is not subject to the texture guard so it always
-- resets the colour, regardless of the configured border texture.
local function resetTooltipBorderToDefault(tooltip)
    if (not tooltip) then
        return
    end

    local backdrop = tooltip and tooltip.TacoTipBackdropFrame
    if (backdrop) then
        if (backdrop.SetBackdropBorderColor) then
            backdrop:SetBackdropBorderColor(
                TacoTipConfig.tooltip_border_color_r or 1,
                TacoTipConfig.tooltip_border_color_g or 1,
                TacoTipConfig.tooltip_border_color_b or 1,
                TacoTipConfig.tooltip_border_alpha or 0.85
            )
        end
        if (backdrop.SetBackdropColor and not backdrop.isBorderOnly) then
            backdrop:SetBackdropColor(
                TacoTipConfig.tooltip_background_color_r or 0,
                TacoTipConfig.tooltip_background_color_g or 0,
                TacoTipConfig.tooltip_background_color_b or 0,
                TacoTipConfig.tooltip_background_alpha or 0.85
            )
        end
    end
end

local function resolveTooltipUnit(tooltip, unit)
    if (unit and UnitExists and UnitExists(unit)) then
        if (tooltip and tooltip.IsUnit and tooltip:IsUnit(unit)) then
            return unit
        end
        return unit
    end
    if (tooltip and tooltip.GetUnit) then
        local ok, _, tooltipUnit = pcall(tooltip.GetUnit, tooltip)
        if (ok and tooltipUnit and UnitExists and UnitExists(tooltipUnit)) then
            if (tooltip.IsUnit) then
                local isUOk, isU = pcall(tooltip.IsUnit, tooltip, tooltipUnit)
                if (isUOk and isU) then
                    return tooltipUnit
                end
            else
                return tooltipUnit
            end
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

    local bgAlpha = TacoTipConfig.tooltip_background_alpha or 0.85
    local backdrop = tooltip and tooltip.TacoTipBackdropFrame
    if (backdrop and backdrop.SetBackdropColor and not backdrop.isBorderOnly) then
        backdrop:SetBackdropColor(bgR, bgG, bgB, bgAlpha)
    end
    applyTooltipBorderOverlay(tooltip, unit, borderR, borderG, borderB)

    -- Defensive follow-up: re-apply the class-tinted border a short tick
    -- later in case Blizzard or another addon re-sets the backdrop after
    -- this function returns (TBC Anniversary 2026 can refresh the tooltip
    -- frame after OnTooltipSetUnit completes).
    if ((TacoTipConfig.tooltip_border_use_class or TacoTipConfig.color_class) and isPlayerTooltip) then
        local state = getTooltipState(tooltip)
        cancelTooltipTimer(tooltip, "borderDeferTimer")
        local deferralGen = state.generation
        -- Always use a cancellable C_Timer.NewTimer handle so the follow-up
        -- can be cancelled by cancelDeferredAppearance() on tooltip clear /
        -- show. An uncancellable C_Timer.After here could fire on a later
        -- non-unit tooltip (bleed-through) or on a stale unit after rapid
        -- hover churn.
        local timer
        timer = NewTimer(0.05, function()
            if (state.borderDeferTimer == timer) then
                state.borderDeferTimer = nil
            end
            safeCall(function()
                if (state.generation ~= deferralGen) then
                    return
                end
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
        state.borderDeferTimer = timer
    end

    applyTooltipFonts(tooltip)

    local portrait = ensureTooltipPortrait(tooltip)
    local portraitScale = TacoTipConfig.tooltip_portrait_scale or 1
    local portraitW = math.floor(72 * portraitScale)
    local portraitH = math.floor(96 * portraitScale)
    if (portrait) then
        if (TacoTipConfig.tooltip_portrait and unit) then
            portrait:ClearAllPoints()
            portrait:SetSize(portraitW, portraitH)
            local tooltipRight = tooltip:GetRight() or 0
            local screenWidth = (UIParent and UIParent:GetRight()) or (_G["GetScreenWidth"] and _G["GetScreenWidth"]()) or 1000
            if (tooltipRight >= screenWidth) then
                portrait:SetPoint("TOPRIGHT", tooltip, "TOPLEFT", -8, 0)
            else
                portrait:SetPoint("TOPLEFT", tooltip, "TOPRIGHT", 8, 0)
            end
            local is3D = TacoTipConfig.tooltip_portrait_3d
            -- 3D PlayerModel renders BOTH players and NPCs/enemies via SetUnit.
            -- The old UnitIsPlayer gate sent NPCs to SetPortraitTexture, which is
            -- a no-op on a Model frame and left the previous model visible (bleed).
            -- ClearModel forces a clean reload of the new unit's mesh so the prior
            -- portrait cannot persist across unit changes (pcall: ClearModel may be
            -- absent on some clients).
            if (is3D and portrait.SetUnit) then
                pcall(portrait.ClearModel, portrait)
                pcall(portrait.SetUnit, portrait, unit)
                pcall(portrait.SetPortraitZoom, portrait, TacoTipConfig.tooltip_portrait_zoom or 0.7)
            else
                -- 2D fallback only when 3D model creation failed (portrait is a Texture).
                pcall(_G.SetPortraitTexture, portrait, unit)
            end
            if (portrait.SetAlpha and tooltip.GetAlpha) then
                portrait:SetAlpha(tooltip:GetAlpha() or 1)
            end
            portrait:Show()
        else
            portrait:Hide()
        end
    end

    local barTexture = (TT.GetResolvedTooltipStatusBarTexture and TT:GetResolvedTooltipStatusBarTexture()) or
        TacoTipConfig.tooltip_bar_texture or "Interface\\TargetingFrame\\UI-TargetingFrame-BarFill"
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
        if (GameTooltip.UpdateTooltip) then
            pcall(GameTooltip.UpdateTooltip, GameTooltip)
        else
            GameTooltip:SetUnit(ttUnit)
        end
    end
end

local function cancelDelayedTooltip(tooltip)
    cancelTooltipTimer(tooltip, "delayedTooltipTimer")
end

-- F3: track the deferred border re-apply timers so a fast tooltip recycle
-- (map/minimap POI cycling) cannot paint a stale class border one frame late.
-- Both the class-tinted border deferral (onTooltipShow) and the defensive
-- backdrop re-apply (ApplyTooltipAppearance) schedule a cancellable
-- C_Timer.NewTimer handle — cancelDelayedTooltip() only cancels the unit
-- tooltip timer, so these must also be cancelled explicitly on every
-- clear/show so a stale follow-up can never fire on a later non-unit tooltip.
-- (borderDeferTimer / classBorderDeferTimer are per-tooltip state fields.)
local function cancelDeferredAppearance(tooltip)
    cancelTooltipTimer(tooltip, "borderDeferTimer")
    cancelTooltipTimer(tooltip, "classBorderDeferTimer")
end

local function cancelFadeTimer(tooltip)
    cancelTooltipTimer(tooltip, "fadeTimer")
end

local function clearTooltipVisuals(tooltip, preservePendingItem)
    if (not tooltip) then
        return
    end
    local state = getTooltipState(tooltip)
    if (not preservePendingItem) then
        state.generation = state.generation + 1
        cancelItemLoadRefresh(tooltip)
        state.currentItemLink = nil
    end

    cancelDelayedTooltip(tooltip)
    cancelDeferredAppearance(tooltip)
    cancelFadeTimer(tooltip)
    clearTooltipPlayerClassColor(tooltip)
    resetTooltipBorderToDefault(tooltip)
    clearTooltipGuildLine(tooltip)
    clearTooltipLevelColorLine(tooltip)
    if (tooltip.TacoTipPortrait) then
        tooltip.TacoTipPortrait:Hide()
    end
    if (tooltip.TacoTipPortrait3D) then
        tooltip.TacoTipPortrait3D:Hide()
        if (tooltip.TacoTipPortrait3D.ClearModel) then
            pcall(tooltip.TacoTipPortrait3D.ClearModel, tooltip.TacoTipPortrait3D)
        end
        if (tooltip.TacoTipPortrait3D.SetAlpha) then
            tooltip.TacoTipPortrait3D:SetAlpha(1)
        end
    end
    -- The power bar hangs off GameTooltip's status bar only; hiding it from a
    -- clearing/hiding of any OTHER tooltip frame would also kill it while the
    -- main tooltip is still open.
    if (tooltip == GameTooltip and TacoTipPowerBar) then
        TacoTipPowerBar:Hide()
        stopPowerBarTicker()
    end
    if (tooltip._tacoTipPaddingSet) then
        if (tooltip.ClearPadding) then
            tooltip:ClearPadding()
        elseif (tooltip.SetPadding) then
            tooltip:SetPadding(0, 0, 0, 0)
        end
        tooltip._tacoTipPaddingSet = nil
    end
end
TT.clearTooltipVisuals = clearTooltipVisuals

local scheduleItemTooltipRefresh
local pooledTooltipText = {}
local pooledPlayerText = {}
local pooledLinesToAdd = {}
local pooledLineRecords = {}
local linesToAddCount = 0

local function addLineDouble(left, right, lr, lg, lb, rr, rg, rb)
    linesToAddCount = linesToAddCount + 1
    local rec = pooledLineRecords[linesToAddCount]
    if (not rec) then
        rec = {}
        pooledLineRecords[linesToAddCount] = rec
    end
    rec.isDouble = true
    rec[1] = left
    rec[2] = right
    rec[3] = lr
    rec[4] = lg
    rec[5] = lb
    rec[6] = rr
    rec[7] = rg
    rec[8] = rb
    pooledLinesToAdd[linesToAddCount] = rec
end

local function addLineSingle(txt, r, g, b)
    linesToAddCount = linesToAddCount + 1
    local rec = pooledLineRecords[linesToAddCount]
    if (not rec) then
        rec = {}
        pooledLineRecords[linesToAddCount] = rec
    end
    rec.isDouble = false
    rec[1] = txt
    rec[2] = r
    rec[3] = g
    rec[4] = b
    rec[5] = nil
    rec[6] = nil
    rec[7] = nil
    rec[8] = nil
    pooledLinesToAdd[linesToAddCount] = rec
end

local function onTooltipSetUnit(tooltip)
    local name, tooltipUnit = tooltip:GetUnit()
    tooltipUnit = resolveTooltipUnit(tooltip, tooltipUnit)
    if (not tooltipUnit) then
        clearTooltipVisuals(tooltip)
        return
    end

    clearTooltipVisuals(tooltip)
    getTooltipState(tooltip).currentUnitGUID = UnitGUID(tooltipUnit)
    storeTooltipPlayerClassColor(tooltip, tooltipUnit)

    if (TacoTipDragButton and TacoTipDragButton:IsShown()) then
        if (not UnitIsUnit(tooltipUnit, "player")) then
            -- Apply appearance for the non-player unit even in mover mode
            -- so the backdrop/border/font from a previous player hover
            -- does not persist on the current tooltip.
            TT:ApplyTooltipAppearance(tooltip, tooltipUnit)
            if (TacoTipDragButton.ShowExample) then
                TacoTipDragButton:ShowExample()
            end
            return
        end
    end

    local guid = UnitGUID(tooltipUnit)

    if (CI and guid and UnitIsPlayer(tooltipUnit) and not UnitIsUnit(tooltipUnit, "player")) then
        if (CI.DoInspect) then
            pcall(CI.DoInspect, CI, tooltipUnit)
        end
    end

    local wide_style = (TacoTipConfig.tip_style == 1 or ((TacoTipConfig.tip_style == 2 or TacoTipConfig.tip_style == 4) and IsShiftKeyDown()))
    local mini_style = (not wide_style and (TacoTipConfig.tip_style == 4 or TacoTipConfig.tip_style == 5))
    wipe(pooledTooltipText)
    wipe(pooledLinesToAdd)
    linesToAddCount = 0
    local text = pooledTooltipText
    local linesToAdd = pooledLinesToAdd
    local numLines = tooltip:NumLines()
    for i = 1, numLines do
        local leftLine = getTooltipLeftLine(tooltip, i)
        text[i] = leftLine and leftLine:GetText()
    end

    if (not text[1] or text[1] == "") then return end
    if (UnitIsPlayer(tooltipUnit) and (not text[2] or text[2] == "")) then return end

    -- Find the actual level line: players in guilds have the guild on line 2,
    -- so the level text shifts to line 3.
    local levelLineIndex = 2
    if (text[2] and string.find(text[2], "<.+>")) then
        if (text[3] and text[3] ~= "" and not string.find(text[3], "<.+>")) then
            levelLineIndex = 3
        end
    end
    text[levelLineIndex] = colorizeUnitLevelLine(tooltip, tooltipUnit, text[levelLineIndex], levelLineIndex)

    if (TacoTipConfig.show_target and UnitIsConnected(tooltipUnit) and not UnitIsUnit(tooltipUnit, "player")) then
        local unitTarget = tooltipUnit .. "target"
        local targetName = UnitName(unitTarget)

        if (targetName) then
            if (UnitIsUnit(unitTarget, tooltipUnit)) then
                if (wide_style) then
                    addLineDouble(L["Target"] .. ":", L["Self"], NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b,
                        HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
                else
                    addLineSingle(L["Target"] .. ": |cFFFFFFFF" .. L["Self"] .. "|r", 1, 1, 1)
                end
            elseif (UnitIsUnit(unitTarget, "player")) then
                if (wide_style) then
                    addLineDouble(L["Target"] .. ":", L["You"], NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, 1, 1, 0)
                else
                    addLineSingle(L["Target"] .. ": |cFFFFFF00" .. L["You"] .. "|r", 1, 1, 1)
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
                        local targetLine = string.format("|cFF%02x%02x%02x%s|r (%s)", classc.r * 255, classc.g * 255,
                            classc.b * 255, targetName, L["Player"])
                        addLineDouble(L["Target"] .. ":", targetLine, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b,
                            HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
                    else
                        addLineSingle(string.format("%s: |cFF%02x%02x%02x%s|r (%s)", L["Target"], classc.r * 255,
                            classc.g * 255, classc.b * 255, targetName, L["Player"]), 1, 1, 1)
                    end
                else
                    if (wide_style) then
                        addLineDouble(L["Target"] .. ":", targetName .. " (" .. L["Player"] .. ")", NORMAL_FONT_COLOR.r,
                            NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g,
                            HIGHLIGHT_FONT_COLOR.b)
                    else
                        addLineSingle(L["Target"] .. ": |cFFFFFFFF" .. targetName .. " (" .. L["Player"] .. ")|r", 1, 1, 1)
                    end
                end
            elseif (UnitIsUnit(unitTarget, "pet") or isOtherPlayersPet(unitTarget)) then
                if (wide_style) then
                    addLineDouble(L["Target"] .. ":", targetName .. " (" .. L["Pet"] .. ")", NORMAL_FONT_COLOR.r,
                        NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g,
                        HIGHLIGHT_FONT_COLOR.b)
                else
                    addLineSingle(L["Target"] .. ": |cFFFFFFFF" .. targetName .. " (" .. L["Pet"] .. ")|r", 1, 1, 1)
                end
            else
                if (wide_style) then
                    addLineDouble(L["Target"] .. ":", targetName, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b,
                        HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
                else
                    addLineSingle(L["Target"] .. ": |cFFFFFFFF" .. targetName .. "|r", 1, 1, 1)
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
                    addLineDouble(L["Target"] .. ":", L["None"], NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b,
                        GRAY_FONT_COLOR.r, GRAY_FONT_COLOR.g, GRAY_FONT_COLOR.b)
                else
                    addLineSingle(L["Target"] .. ": |cFF808080" .. L["None"] .. "|r", 1, 1, 1)
                end
            end
        end
    end

    if (UnitIsPlayer(tooltipUnit)) then
        local localizedClass, class = UnitClass(tooltipUnit)
        local localizedRace = UnitRace(tooltipUnit)
        local level = UnitLevel(tooltipUnit)

        if (not TacoTipConfig.show_titles and name and string.find(text[1], name, 1, true)) then
            text[1] = name
        end
        if (TacoTipConfig.color_class and localizedClass and class) then
            local classc = getClassColor(class)
            if (classc) then
                text[1] = colorizeText(text[1], classc.r, classc.g, classc.b)
            end
        end

        local guildName, guildRankName = GetGuildInfo(tooltipUnit)
        if (not guildName) then
            for i = 2, #text do
                if (text[i]) then
                    local gName, gRank = string.match(text[i], "^<([^>]+)>%s*(.*)$")
                    if (gName) then
                        guildName = gName
                        if (gRank and gRank ~= "") then
                            guildRankName = gRank
                        end
                        break
                    end
                end
            end
        end

        local levelStr = (level and level > 0) and tostring(level) or "??"
        local diffColor = getHostileDifficultyColor(tooltipUnit)
        if (diffColor) then
            levelStr = colorizeText(levelStr, diffColor.r, diffColor.g, diffColor.b)
        else
            levelStr = colorizeText(levelStr, 1, 1, 1)
        end

        local displayClass = localizedClass
        local displayRace = localizedRace
        if (TacoTipConfig.color_class and class) then
            local classc = getClassColor(class)
            if (classc) then
                if (displayClass) then
                    displayClass = colorizeText(displayClass, classc.r, classc.g, classc.b)
                end
                if (displayRace) then
                    displayRace = colorizeText(displayRace, classc.r, classc.g, classc.b)
                end
            end
        end

        local levelLine
        if (displayRace and displayClass) then
            levelLine = string.format("|cFFFFFFFFLevel|r %s %s %s", levelStr, displayRace, displayClass)
        elseif (displayClass) then
            levelLine = string.format("|cFFFFFFFFLevel|r %s %s", levelStr, displayClass)
        else
            levelLine = string.format("|cFFFFFFFFLevel|r %s", levelStr)
        end

        wipe(pooledPlayerText)
        local newText = pooledPlayerText
        newText[1] = text[1]

        if (guildName and TacoTipConfig.show_guild_name) then
            local guildTag = string.format("|cFF40FB40<%s>|r", guildName)
            if (TacoTipConfig.show_guild_rank and guildRankName and guildRankName ~= "") then
                local rankText = string.format("|cFFFFFFFF%s|r", guildRankName)
                if (TacoTipConfig.guild_rank_alt_style) then
                    newText[2] = string.format("%s %s", guildTag, rankText)
                else
                    newText[2] = string.format(L["FORMAT_GUILD_RANK_1"], guildTag, rankText)
                end
            else
                newText[2] = guildTag
            end
            newText[3] = levelLine
            tooltip.TacoTipGuildLineIndex = 2
            tooltip.TacoTipLevelColorLineIndex = 3
        else
            newText[2] = levelLine
            tooltip.TacoTipGuildLineIndex = nil
            tooltip.TacoTipLevelColorLineIndex = 2
        end

        text = newText

        if (TacoTipConfig.show_realm and UnitIsPlayer(tooltipUnit) and not UnitIsSameServer(tooltipUnit)) then
            local _, realm = UnitName(tooltipUnit)
            if (realm and realm ~= "") then
                if (wide_style) then
                    addLineDouble((L["Realm"] or "Realm") .. ":", realm, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g,
                        NORMAL_FONT_COLOR.b, HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
                else
                    addLineSingle(string.format("%s: |cFFFFFFFF%s|r", L["Realm"] or "Realm", realm), 1, 1, 1)
                end
            end
        end
        if (TacoTipConfig.show_honor_rank) then
            local pvpName = UnitPVPName(tooltipUnit)
            if (pvpName and pvpName ~= "" and pvpName ~= name) then
                if (wide_style) then
                    addLineDouble((L["Honor Rank"] or "Honor Rank") .. ":", pvpName, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g,
                        NORMAL_FONT_COLOR.b, HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
                else
                    addLineSingle(string.format("%s: |cFFFFFFFF%s|r", L["Honor Rank"] or "Honor Rank", pvpName), 1, 1, 1)
                end
            end
        end
        local nameLineIcons = ""
        if (TacoTipConfig.show_pvp_icon and UnitIsPlayer(tooltipUnit) and UnitIsPVP(tooltipUnit)) then
            nameLineIcons = nameLineIcons .. " " .. PVP_FLAG_ICON
            for i = 2, numLines do
                if (text[i]) then
                    text[i] = string.gsub(text[i], "PvP", "", 1)
                end
            end
        end
        if (TacoTipConfig.show_team) then
            nameLineIcons = nameLineIcons ..
                " " .. (UnitFactionGroup(tooltipUnit) == "Horde" and HORDE_ICON or ALLIANCE_ICON)
        end
        if (TacoTipConfig.show_class_icon and UnitIsPlayer(tooltipUnit)) then
            local _, classFile = UnitClass(tooltipUnit)
            if (classFile) then
                nameLineIcons = nameLineIcons .. " " .. getClassIconMarkup(classFile)
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
                    addLineDouble(" ", " ", GRAY_FONT_COLOR.r, GRAY_FONT_COLOR.g, GRAY_FONT_COLOR.b, GRAY_FONT_COLOR.r,
                        GRAY_FONT_COLOR.g, GRAY_FONT_COLOR.b)
                else
                    addLineSingle("|cFF444444" .. string.rep("-", 30) .. "|r", GRAY_FONT_COLOR.r, GRAY_FONT_COLOR.g,
                        GRAY_FONT_COLOR.b)
                end
            end
            if (TacoTipConfig.show_talents) then
                local x1, x2, x3 = 0, 0, 0
                local y1, y2, y3 = 0, 0, 0
                local spec1 = CI:GetSpecialization(guid, 1)
                if (spec1) then
                    x1, x2, x3 = CI:GetTalentPoints(guid, 1)
                end
                local spec2 = CI:GetSpecialization(guid, 2)
                if (spec2) then
                    y1, y2, y3 = CI:GetTalentPoints(guid, 2)
                end

                local active = CI:GetActiveTalentGroup(guid) or 1

                if (active == 2) then
                    if (spec2) then
                        local specText = formatSpecializationText(class, spec2, y1, y2, y3)
                        if (wide_style) then
                            addLineDouble(L["Talents"] .. ":", specText, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g,
                                NORMAL_FONT_COLOR.b, 1, 1, 1)
                        else
                            addLineSingle(string.format("%s: %s", L["Talents"], specText), 1, 1, 1)
                        end
                    end
                    if (spec1 and spec1 ~= spec2) then
                        -- Inactive spec: spec name rendered in lowest GearScore
                        -- quality grey (0.50, 0.50, 0.50 / GRAY_FONT_COLOR)
                        -- inside formatSpecializationText, with talent numbers
                        -- remaining clean white.
                        local specText = formatSpecializationText(class, spec1, x1, x2, x3, true)
                        if (wide_style) then
                            addLineDouble(" ", specText, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, 1, 1, 1)
                        else
                            addLineSingle(string.format("|c00000000%s: |r%s", L["Talents"], specText), 1, 1, 1)
                        end
                    end
                elseif (active == 1) then
                    if (spec1) then
                        local specText = formatSpecializationText(class, spec1, x1, x2, x3)
                        if (wide_style) then
                            addLineDouble(L["Talents"] .. ":", specText, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g,
                                NORMAL_FONT_COLOR.b, 1, 1, 1)
                        else
                            addLineSingle(string.format("%s: %s", L["Talents"], specText), 1, 1, 1)
                        end
                    end
                    -- Only render the inactive spec when it is a genuinely
                    -- different tree. Prevents the same spec being printed
                    -- twice when both dual-spec slots match.
                    if (spec2 and spec2 ~= spec1) then
                        -- Inactive spec: spec name rendered in lowest GearScore
                        -- quality grey (0.50, 0.50, 0.50 / GRAY_FONT_COLOR)
                        -- inside formatSpecializationText, with talent numbers
                        -- remaining clean white.
                        local specText = formatSpecializationText(class, spec2, y1, y2, y3, true)
                        if (wide_style) then
                            addLineDouble(" ", specText, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, 1, 1, 1)
                        else
                            addLineSingle(string.format("|c00000000%s: |r%s", L["Talents"], specText), 1, 1, 1)
                        end
                    end
                end
            end
            if (TacoTipConfig.show_separators) then
                if (wide_style) then
                    addLineDouble(" ", " ", GRAY_FONT_COLOR.r, GRAY_FONT_COLOR.g, GRAY_FONT_COLOR.b, GRAY_FONT_COLOR.r,
                        GRAY_FONT_COLOR.g, GRAY_FONT_COLOR.b)
                else
                    addLineSingle("|cFF444444" .. string.rep("-", 30) .. "|r", GRAY_FONT_COLOR.r, GRAY_FONT_COLOR.g,
                        GRAY_FONT_COLOR.b)
                end
            end
            local miniText = ""
            if (TacoTipConfig.show_gs_player) then
                local gearscore, avg_ilvl = GearScore:GetScore(guid, true)
                if (gearscore > 0) then
                    local r, g, b = GearScore:GetQuality(gearscore)
                    if (wide_style) then
                        addLineDouble("GearScore: " .. gearscore, "(iLvl: " .. avg_ilvl .. ")", r, g, b, r, g, b)
                    elseif (mini_style) then
                        miniText = string.format("|cFF%02x%02x%02xGS: %s  L: %s|r  ", r * 255, g * 255, b * 255,
                            gearscore, avg_ilvl)
                    else
                        addLineSingle(string.format("GearScore: |cFF%02x%02x%02x%s|r", r * 255, g * 255, b * 255, gearscore),
                            1, 1, 1)
                        if (avg_ilvl and avg_ilvl > 0) then
                            if (TacoTipConfig.show_ilvl_inline) then
                                text[1] = text[1] ..
                                    string.format(" |cFF%02x%02x%02x[%s]|r", r * 255, g * 255, b * 255, avg_ilvl)
                            else
                                addLineSingle(string.format("iLvl: |cFF%02x%02x%02x%s|r", r * 255, g * 255, b * 255, avg_ilvl), 1, 1, 1)
                            end
                        end
                    end
                end
            end
            if (isPawnLoaded and TacoTipConfig.show_pawn_player) then
                local pawnScore, specName, specColor = TT_PAWN:GetScore(guid, not TacoTipConfig.show_gs_player)
                if (pawnScore > 0) then
                    if (wide_style) then
                        addLineDouble(string.format("Pawn: %s%.2f|r", specColor, pawnScore), string.format("%s(%s)|r", specColor,
                            specName), 1, 1, 1, 1, 1, 1)
                    elseif (mini_style) then
                        miniText = miniText .. string.format("P: %s%.1f|r", specColor, pawnScore)
                    else
                        addLineSingle(string.format("Pawn: %s%.2f (%s)|r", specColor, pawnScore, specName), 1, 1, 1)
                    end
                end
            end
            if (miniText ~= "") then
                addLineSingle(miniText, 1, 1, 1)
            end
            if (CI:IsWotlk() and TacoTipConfig.show_achievement_points) then
                local achi_pts = CI:GetTotalAchievementPoints(guid)
                if (achi_pts) then
                    if (wide_style) then
                        addLineDouble(ACHIEVEMENT_ICON .. " " .. achi_pts, " ", 1, 1, 1, 1, 1, 1)
                    else
                        addLineSingle(ACHIEVEMENT_ICON .. " " .. achi_pts, 1, 1, 1)
                    end
                end
            end
        end
    end

    local n = 0
    local maxTextLines = math.max(numLines, #text)
    for i = 1, maxTextLines do
        if (text[i] and text[i] ~= "") then
            n = n + 1
            if (n <= numLines) then
                local line = getTooltipLeftLine(tooltip, n)
                if (line) then
                    line:SetText(text[i])
                end
            else
                tooltip:AddLine(text[i], 1, 1, 1)
            end
        end
    end
    if (wide_style) then
        local anchorLine = getTooltipLeftLine(tooltip, n)
        while (n < numLines) do
            n = n + 1
            local left = getTooltipLeftLine(tooltip, n)
            local right = getTooltipRightLine(tooltip, n)
            if (left) then
                left:SetText()
                left:Hide()
            end
            if (right) then
                right:SetText()
                right:Hide()
            end
        end
        for i = 1, linesToAddCount do
            local v = linesToAdd[i]
            if (v.isDouble) then
                tooltip:AddDoubleLine(v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8])
            else
                tooltip:AddLine(v[1], v[2] or 1, v[3] or 1, v[4] or 1)
            end
        end
        local nextLeft = getTooltipLeftLine(tooltip, n + 1)
        if (nextLeft and anchorLine) then
            nextLeft:SetPoint("TOP", anchorLine, "BOTTOM", 0, -2)
        end
    else
        for i = 1, linesToAddCount do
            local v = linesToAdd[i]
            local txt = v[1]
            local r, g, b = v[2], v[3], v[4]
            if (n < numLines) then
                n = n + 1
                local left = getTooltipLeftLine(tooltip, n)
                if (left) then
                    left:SetTextColor(r or 1, g or 1, b or 1)
                    left:SetText(txt)
                end
            else
                if (r and g and b) then
                    tooltip:AddLine(txt, r, g, b)
                else
                    tooltip:AddLine(txt, 1, 1, 1)
                end
            end
        end
        while (n < numLines) do
            n = n + 1
            local left = getTooltipLeftLine(tooltip, n)
            local right = getTooltipRightLine(tooltip, n)
            if (left) then
                left:SetText()
                left:Hide()
            end
            if (right) then
                right:SetText()
                right:Hide()
            end
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
            TacoTipPowerBar:SetStatusBarTexture((TT.GetResolvedTooltipStatusBarTexture and TT:GetResolvedTooltipStatusBarTexture()) or
                "Interface\\TargetingFrame\\UI-TargetingFrame-BarFill")
            TacoTipPowerBar:SetStatusBarColor(0, 0, 1)
            function TacoTipPowerBar:Update(u)
                if (TacoTipConfig.show_power_bar) then
                    local unit = u or resolveTooltipUnit(GameTooltip)
                    if (unit) then
                        local _, power = UnitPowerType(unit)
                        local color = PowerBarColor and PowerBarColor[power] or {}
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
                if (not self:IsShown()) then
                    return
                end
                local ttUnit = resolveTooltipUnit(GameTooltip)
                if (unit and ttUnit and UnitIsUnit(unit, ttUnit)) then
                    self:Update(unit)
                end
            end)
        end
        if (UnitPowerMax(tooltipUnit) > 0) then
            if (TacoTipConfig.show_hp_bar) then
                TacoTipPowerBar:SetPoint("TOPLEFT", GameTooltip, "BOTTOMLEFT", 2, -9)
                TacoTipPowerBar:SetPoint("TOPRIGHT", GameTooltip, "BOTTOMRIGHT", -2, -9)
            else
                TacoTipPowerBar:SetPoint("TOPLEFT", GameTooltip, "BOTTOMLEFT", 2, -1)
                TacoTipPowerBar:SetPoint("TOPRIGHT", GameTooltip, "BOTTOMRIGHT", -2, -1)
            end
            TacoTipPowerBar:Update(tooltipUnit)
            TacoTipPowerBar:Show()
            startPowerBarTicker()
            if (TacoTipPowerBar.RegisterUnitEvent) then
                pcall(TacoTipPowerBar.RegisterUnitEvent, TacoTipPowerBar, "UNIT_POWER_UPDATE", tooltipUnit)
                pcall(TacoTipPowerBar.RegisterUnitEvent, TacoTipPowerBar, "UNIT_MAXPOWER", tooltipUnit)
                pcall(TacoTipPowerBar.RegisterUnitEvent, TacoTipPowerBar, "UNIT_DISPLAYPOWER", tooltipUnit)
            else
                TacoTipPowerBar:RegisterEvent("UNIT_POWER_UPDATE")
                TacoTipPowerBar:RegisterEvent("UNIT_MAXPOWER")
                TacoTipPowerBar:RegisterEvent("UNIT_DISPLAYPOWER")
            end
            if (tooltip.SetPadding) then
                tooltip:SetPadding(0, 10, 0, 0)
                tooltip._tacoTipPaddingSet = true
            end
        else
            TacoTipPowerBar:Hide()
            stopPowerBarTicker()
        end
    elseif (TacoTipPowerBar) then
        TacoTipPowerBar:Hide()
        stopPowerBarTicker()
    end

    if (tooltip.SetClampRectInsets) then
        tooltip:SetClampRectInsets(0, 0, 15, 15)
    end

    if (tooltip.SetMinimumWidth) then
        local currentMin = (tooltip.GetMinimumWidth and tooltip:GetMinimumWidth()) or -1
        if (currentMin ~= 0) then
            tooltip:SetMinimumWidth(0)
        end
    end


    if (tooltip.SetMaximumWidth) then
        if (TacoTipConfig.tooltip_max_width and TacoTipConfig.tooltip_max_width > 0) then
            tooltip:SetMaximumWidth(TacoTipConfig.tooltip_max_width)
        else
            tooltip:SetMaximumWidth(0)
        end
    end

    TT:ApplyTooltipAppearance(tooltip, tooltipUnit)
end

GameTooltip:HookScript("OnTooltipSetUnit", function(tooltip, ...)
    cancelDelayedTooltip(tooltip)
    local delay = TacoTipConfig.tooltip_delay or 0
    if (delay > 0 and tooltip == GameTooltip and not InCombatLockdown() and type(NewTimer) == "function") then
        local state = getTooltipState(tooltip)
        local timer
        timer = NewTimer(delay, function()
            if (state.delayedTooltipTimer == timer) then
                state.delayedTooltipTimer = nil
            end
            safeCall(onTooltipSetUnit, tooltip)
        end)
        state.delayedTooltipTimer = timer
    else
        safeCall(onTooltipSetUnit, tooltip, ...)
    end
end)

local function itemToolTipHook(self)
    clearTooltipVisuals(self)

    local _, itemLink = self:GetItem()
    if (itemLink) then
        getTooltipState(self).currentItemLink = itemLink
    end
    -- Both item features off: skip the IsEquippableItem/GetItemInfo work
    -- entirely instead of fetching data no line will ever display.
    if (itemLink and (TacoTipConfig.show_item_level or TacoTipConfig.show_gs_items) and IsEquippableItem(itemLink)) then
        -- Single GetItemInfo fetch per hover, shared by the ilvl line,
        -- GearScore and HunterScore below (F3 hot-path fix). If Blizzard
        -- has not cached the item yet, request its data and re-render this
        -- exact tooltip when the load lands rather than leaving it blank.
        local itemInfo = { GetItemInfo(itemLink) }
        if (not itemInfo[2] or not itemInfo[4]) then
            scheduleItemTooltipRefresh(self, itemLink)
        end
        if (TacoTipConfig.show_item_level) then
            local ilvl = itemInfo[4]
            if (ilvl and ilvl > 1) then
                self:AddLine(L["Item Level"] .. " " .. ilvl, 1, 1, 1)
            end
        end
        if (TacoTipConfig.show_gs_items) then
            local gs, _, r, g, b = GearScore:GetItemScoreFromInfo(itemInfo)
            if (gs and gs > 1) then
                self:AddLine("GearScore: " .. gs, r, g, b)
                if (TacoTipConfig.show_gs_items_hs or IsModifierKeyDown() or playerClass == "HUNTER" or
                        (InspectFrame and InspectFrame:IsShown() and InspectFrame.unit and select(2, UnitClass(InspectFrame.unit)) == "HUNTER")) then
                    local hs, _, hsR, hsG, hsB = GearScore:GetItemHunterScore(itemLink, itemInfo)
                    if (gs ~= hs) then
                        self:AddLine((L["HunterScore"] or "HunterScore") .. ": " .. hs, hsR, hsG, hsB)
                    end
                end
            end
        end
    end

    -- Apply cosmetic appearance (font, backdrop texture, border texture) to
    -- item tooltips so user-selected visual style carries through.  Skip
    -- unit-specific effects (class color, portrait, bar texture)
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

scheduleItemTooltipRefresh = function(tooltip, itemLink)
    if (not tooltip or not itemLink or not Item or not Item.CreateFromItemLink) then
        return
    end

    local itemOk, item = pcall(Item.CreateFromItemLink, Item, itemLink)
    if (not itemOk or not item or not item.IsItemDataCached or not item.ContinueWithCancelOnItemLoad) then
        -- No C_Item object API on this client: fall back to a plain data
        -- request without a completion callback (cue is re-rendered by the
        -- caller's next natural refresh instead).
        local itemID = GetItemInfoInstant and GetItemInfoInstant(itemLink)
        if (RequestLoadItemDataByID and itemID) then
            pcall(RequestLoadItemDataByID, itemID)
        end
        return
    end

    local cachedOk, isCached = pcall(item.IsItemDataCached, item)
    if (not cachedOk or isCached) then
        return
    end

    local state = getTooltipState(tooltip)
    local generation = state.generation
    local cancel
    local callback = function()
        if (state.itemLoadCancel == cancel) then
            state.itemLoadCancel = nil
        end
        -- Only repaint if this exact tooltip still shows this exact item
        -- (generation bump on clear/hide invalidates stale callbacks).
        if (state.generation ~= generation or state.currentItemLink ~= itemLink
                or not tooltip:IsShown()) then
            return
        end
        if (tooltip.UpdateTooltip) then
            pcall(tooltip.UpdateTooltip, tooltip)
        end
    end
    local callbackOk, canceler = pcall(item.ContinueWithCancelOnItemLoad, item, callback)
    if (callbackOk and type(canceler) == "function") then
        cancel = canceler
        state.itemLoadCancel = cancel
    end
end

GameTooltip:HookScript("OnTooltipSetItem", safeItemToolTipHook)
ShoppingTooltip1:HookScript("OnTooltipSetItem", safeItemToolTipHook)
ShoppingTooltip2:HookScript("OnTooltipSetItem", safeItemToolTipHook)
ItemRefTooltip:HookScript("OnTooltipSetItem", safeItemToolTipHook)

-- Re-apply the class-tinted border whenever the tooltip shows, in case a
-- re-show skipped OnTooltipSetUnit (e.g. anchor re-fire with cached text)
-- and left SetBackdrop's default 0.5/0.5/0.5 gray border in place. Deferred
-- to the next frame so it runs AFTER Blizzard finishes its own internal
-- OnShow/backdrop setup - otherwise Blizzard's subsequent SetBackdrop on
-- the same frame resets the border back to default gray.
local function onTooltipShow(tooltip)
    local state = getTooltipState(tooltip)
    local shownItemLink
    if (tooltip and tooltip.GetItem) then
        local itemOk, _, itemLink = pcall(tooltip.GetItem, tooltip)
        shownItemLink = itemLink
        if (not itemOk) then
            shownItemLink = nil
        end
    end
    -- If the same item re-shows (shopping tooltip compare), keep its pending
    -- item-load registration alive instead of tearing it down and re-requesting.
    local preservePendingItem = shownItemLink ~= nil and state.currentItemLink == shownItemLink
    local cached = tooltip and tooltip.TacoTipPlayerClassColor
    if (not cached) then
        -- F1: When the tooltip shows for non-unit content (items, spells, UI
        -- elements, options hover-help), the portrait from a previous unit
        -- display must be cleared. OnTooltipCleared may not have fired on
        -- this transition path (e.g. ClearLines + Show in showHoverTooltip).
        clearTooltipVisuals(tooltip, preservePendingItem)
        return
    end
    if (not TacoTipConfig.tooltip_border_use_class and not TacoTipConfig.color_class) then
        return
    end

    -- Only apply class-tinted borders when the tooltip actually shows a
    -- player unit. Map icons, items, and other non-unit tooltips should
    -- never inherit a stale class border.
    local unit = resolveTooltipUnit(tooltip)
    if (not unit or not UnitIsPlayer(unit)) then
        -- Non-player / non-unit tooltip (items, spells, minimap or world-map
        -- POI icons). Clear ALL player-specific visuals left by the previous
        -- hover — border, portrait, 3D portrait, power bar —
        -- so none of them bleed through onto this tooltip. This is broader
        -- than just resetTooltipBorderToDefault because ClearLines() (used by
        -- map POI tooltips) does not fire OnTooltipCleared, so the portrait
        -- from a previous player hover otherwise persists on the quest NPC.
        clearTooltipVisuals(tooltip)
        return
    end

    cancelTooltipTimer(tooltip, "classBorderDeferTimer")
    local deferralGen = state.generation
    -- Always use a cancellable C_Timer.NewTimer handle so the follow-up
    -- can be cancelled by cancelDeferredAppearance() on tooltip clear /
    -- show. An uncancellable C_Timer.After here could fire on a later
    -- non-unit tooltip (bleed-through) or on a stale unit after rapid
    -- hover churn.
    local timer
    timer = NewTimer(0, function()
        if (state.classBorderDeferTimer == timer) then
            state.classBorderDeferTimer = nil
        end
        safeCall(function()
            if (state.generation ~= deferralGen) then
                return
            end
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
    state.classBorderDeferTimer = timer
end

local function registerTooltipVisualClearing(tooltipFrame)
    if (not tooltipFrame or type(tooltipFrame) ~= "table" or not tooltipFrame.HasScript) then
        return
    end
    if (tooltipFrame:HasScript("OnTooltipCleared")) then
        tooltipFrame:HookScript("OnTooltipCleared", function(tFrame)
            cancelDelayedTooltip(tFrame)
            return safeCall(clearTooltipVisuals, tFrame)
        end)
    end
    if (tooltipFrame:HasScript("OnShow")) then
        tooltipFrame:HookScript("OnShow", function(tFrame, ...)
            return safeCall(onTooltipShow, tFrame, ...)
        end)
    end
    if (tooltipFrame:HasScript("OnHide")) then
        tooltipFrame:HookScript("OnHide", function(tFrame)
            cancelDelayedTooltip(tFrame)
            return safeCall(clearTooltipVisuals, tFrame)
        end)
    end
end

for _, ttFrame in ipairs({
    GameTooltip,
    ShoppingTooltip1,
    ShoppingTooltip2,
    ItemRefTooltip,
    _G["ItemRefShoppingTooltip1"],
    _G["ItemRefShoppingTooltip2"],
    _G["WorldMapTooltip"],
    _G["WorldMapCompareTooltip1"],
    _G["WorldMapCompareTooltip2"],
    _G["SmallTextTooltip"]
}) do
    registerTooltipVisualClearing(ttFrame)
end

-- Ensure all visuals are cleared when the tooltip shows non-unit content
-- like spells/buffs or custom non-unit lines. No varargs: a forwarded
-- second arg would land in clearTooltipVisuals' preservePendingItem
-- parameter and skip the generation bump / item-load teardown on clear.
GameTooltip:HookScript("OnTooltipSetSpell", function(tooltip)
    return safeCall(clearTooltipVisuals, tooltip)
end)


local function CreateMouseAnchor()
    TacoTipMouseAnchor = CreateFrame("Frame", nil, UIParent)
    TacoTipMouseAnchor:EnableMouse(false)
    TacoTipMouseAnchor:SetMovable(true)
    TacoTipMouseAnchor:SetUserPlaced(false)
    TacoTipMouseAnchor:SetClampedToScreen(true)
    TacoTipMouseAnchor:SetSize(1, 1)
    TacoTipMouseAnchor:SetPoint("CENTER", UIParent, "BOTTOMLEFT", 0, 0)
    TacoTipMouseAnchor:SetScript("OnUpdate", function(self)
        -- The anchor persists for the whole session once created; skip all
        -- work while mouse anchoring is disabled or the tooltip is hidden
        -- so the per-frame cursor read and point mutation only run while
        -- a tooltip is actively visible and consuming it.
        if (not TacoTipConfig.anchor_mouse or not GameTooltip or not GameTooltip:IsShown()) then
            return
        end
        local cx, cy = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx / scale, cy / scale)
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
            if (tooltip.EnableMouse) then
                tooltip:EnableMouse(false)
            end
            return
        end
    end
    if (TacoTipConfig.anchor_mouse) then
        if (not TacoTipConfig.anchor_mouse_world or TT:GetMouseFocus() == WorldFrame) then
            if (not TacoTipMouseAnchor) then
                CreateMouseAnchor()
            end
            tooltip:ClearAllPoints()
            tooltip:SetPoint("BOTTOMLEFT", TacoTipMouseAnchor, "CENTER", 10, 10)
        end
    else
        if (TacoTipConfig.custom_pos) then
            if (not TacoTipDragButton and TacoTip_CustomPosEnable) then
                TacoTip_CustomPosEnable(false)
            end
            if (TacoTipDragButton) then
                tooltip:ClearAllPoints()
                local anchorPoint = TacoTipConfig.custom_anchor or "TOPLEFT"
                tooltip:SetPoint(anchorPoint, TacoTipDragButton, anchorPoint)
            end
        elseif (TacoTipConfig.show_hp_bar and TacoTipConfig.show_power_bar) then
            tooltip:ClearAllPoints()
            tooltip:SetPoint("BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -CONTAINER_OFFSET_X - 13, CONTAINER_OFFSET_Y + 9)
        end
    end
    if (tooltip.EnableMouse) then
        tooltip:EnableMouse(false)
    end
end)

local function getDefaultTooltipMoverPosition()
    -- BOTTOMRIGHT = bottom-right corner of the screen.
    -- This is the STARTING position of the green dot ONLY.
    -- It is independent of custom_anchor (which controls where the
    -- tooltip appears relative to the dot, not where the dot sits).
    return { "BOTTOMRIGHT", "BOTTOMRIGHT", 0, 0 }
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
    mover:SetPoint("TOPLEFT", topkek, "TOPLEFT")
    mover:SetPoint("BOTTOMRIGHT", bottomright, "BOTTOMRIGHT")
    mover:RegisterForDrag("LeftButton")
    mover:SetScript("OnDragStart", function(self)
        self:StartMoving()
        self:SetScript("OnUpdate", function(updateFrame)
            local cx, cy = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale()
            local fx, fy = parent:GetRect()
            callbackFunc(cx / scale - fx, cy / scale - fy)
        end)
    end)
    mover:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self:SetScript("OnUpdate", nil)
        mover:ClearAllPoints()
        mover:SetPoint("TOPLEFT", topkek, "TOPLEFT")
        mover:SetPoint("BOTTOMRIGHT", bottomright, "BOTTOMRIGHT")
        refreshOptionsUI()
    end)
    return mover
end

function TT:InitCharacterFrame()
    CharacterModelFrame:CreateFontString("PersonalGearScore")
    PersonalGearScore:SetFont(L["CHARACTER_FRAME_GS_VALUE_FONT"], L["CHARACTER_FRAME_GS_VALUE_FONT_SIZE"])
    PersonalGearScore:SetText("0")
    rawset(PersonalGearScore, "RefreshPosition", function()
        PersonalGearScore:SetPoint("BOTTOMLEFT", PaperDollFrame, "BOTTOMLEFT",
            L["CHARACTER_FRAME_GS_VALUE_XPOS"] + (TacoTipConfig.character_gs_offset_x or 0),
            L["CHARACTER_FRAME_GS_VALUE_YPOS"] + (TacoTipConfig.character_gs_offset_y or 0))
    end)
    PersonalGearScore:RefreshPosition()

    CharacterModelFrame:CreateFontString("PersonalGearScoreText")
    PersonalGearScoreText:SetFont(L["CHARACTER_FRAME_GS_TITLE_FONT"], L["CHARACTER_FRAME_GS_TITLE_FONT_SIZE"])
    PersonalGearScoreText:SetText("GearScore")
    rawset(PersonalGearScoreText, "RefreshPosition", function()
        PersonalGearScoreText:SetPoint("BOTTOMLEFT", PaperDollFrame, "BOTTOMLEFT",
            L["CHARACTER_FRAME_GS_TITLE_XPOS"] + (TacoTipConfig.character_gs_offset_x or 0),
            L["CHARACTER_FRAME_GS_TITLE_YPOS"] + (TacoTipConfig.character_gs_offset_y or 0))
    end)
    PersonalGearScoreText:RefreshPosition()

    CharacterModelFrame:CreateFontString("PersonalAvgItemLvl")
    PersonalAvgItemLvl:SetFont(L["CHARACTER_FRAME_ILVL_VALUE_FONT"], L["CHARACTER_FRAME_ILVL_VALUE_FONT_SIZE"])
    PersonalAvgItemLvl:SetText("0")
    rawset(PersonalAvgItemLvl, "RefreshPosition", function()
        PersonalAvgItemLvl:SetPoint("BOTTOMLEFT", PaperDollFrame, "BOTTOMLEFT",
            L["CHARACTER_FRAME_ILVL_VALUE_XPOS"] + (TacoTipConfig.character_ilvl_offset_x or 0),
            L["CHARACTER_FRAME_ILVL_VALUE_YPOS"] + (TacoTipConfig.character_ilvl_offset_y or 0))
    end)
    PersonalAvgItemLvl:RefreshPosition()

    CharacterModelFrame:CreateFontString("PersonalAvgItemLvlText")
    PersonalAvgItemLvlText:SetFont(L["CHARACTER_FRAME_ILVL_TITLE_FONT"], L["CHARACTER_FRAME_ILVL_TITLE_FONT_SIZE"])
    PersonalAvgItemLvlText:SetText("iLvl")
    rawset(PersonalAvgItemLvlText, "RefreshPosition", function()
        PersonalAvgItemLvlText:SetPoint("BOTTOMLEFT", PaperDollFrame, "BOTTOMLEFT",
            L["CHARACTER_FRAME_ILVL_TITLE_XPOS"] + (TacoTipConfig.character_ilvl_offset_x or 0),
            L["CHARACTER_FRAME_ILVL_TITLE_YPOS"] + (TacoTipConfig.character_ilvl_offset_y or 0))
    end)
    PersonalAvgItemLvlText:RefreshPosition()

    PaperDollFrame:HookScript("OnShow", TT.RefreshCharacterFrame)
end

function TT:RefreshCharacterFrame()
    if (TT.InitCharacterFrame) then
        TT:InitCharacterFrame()
        TT.InitCharacterFrame = nil
    end
    local MyGearScore, MyAverageScore, r, g, b = 0, 0, 0, 0, 0
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
                PersonalGearScoreText.mover = CreateMover(PaperDollFrame, PersonalGearScore, PersonalGearScoreText,
                    function(ofx, ofy)
                        TacoTipConfig.character_gs_offset_x = ofx - L["CHARACTER_FRAME_GS_TITLE_XPOS"]
                        TacoTipConfig.character_gs_offset_y = ofy - L["CHARACTER_FRAME_GS_TITLE_YPOS"]
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
                PersonalAvgItemLvlText.mover = CreateMover(PaperDollFrame, PersonalAvgItemLvl, PersonalAvgItemLvlText,
                    function(ofx, ofy)
                        TacoTipConfig.character_ilvl_offset_x = ofx - L["CHARACTER_FRAME_ILVL_TITLE_XPOS"]
                        TacoTipConfig.character_ilvl_offset_y = ofy - L["CHARACTER_FRAME_ILVL_TITLE_YPOS"]
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
    rawset(InspectGearScore, "RefreshPosition", function()
        InspectGearScore:SetPoint("BOTTOMLEFT", InspectPaperDollFrame, "BOTTOMLEFT",
            L["INSPECT_FRAME_GS_VALUE_XPOS"] + (TacoTipConfig.inspect_gs_offset_x or 0),
            L["INSPECT_FRAME_GS_VALUE_YPOS"] + (TacoTipConfig.inspect_gs_offset_y or 0))
    end)
    InspectGearScore:RefreshPosition()

    InspectModelFrame:CreateFontString("InspectGearScoreText")
    InspectGearScoreText:SetFont(L["INSPECT_FRAME_GS_TITLE_FONT"], L["INSPECT_FRAME_GS_TITLE_FONT_SIZE"])
    InspectGearScoreText:SetText("GearScore")
    rawset(InspectGearScoreText, "RefreshPosition", function()
        InspectGearScoreText:SetPoint("BOTTOMLEFT", InspectPaperDollFrame, "BOTTOMLEFT",
            L["INSPECT_FRAME_GS_TITLE_XPOS"] + (TacoTipConfig.inspect_gs_offset_x or 0),
            L["INSPECT_FRAME_GS_TITLE_YPOS"] + (TacoTipConfig.inspect_gs_offset_y or 0))
    end)
    InspectGearScoreText:RefreshPosition()

    InspectModelFrame:CreateFontString("InspectAvgItemLvl")
    InspectAvgItemLvl:SetFont(L["INSPECT_FRAME_ILVL_VALUE_FONT"], L["INSPECT_FRAME_ILVL_VALUE_FONT_SIZE"])
    InspectAvgItemLvl:SetText("0")
    rawset(InspectAvgItemLvl, "RefreshPosition", function()
        InspectAvgItemLvl:SetPoint("BOTTOMLEFT", InspectPaperDollFrame, "BOTTOMLEFT",
            L["INSPECT_FRAME_ILVL_VALUE_XPOS"] + (TacoTipConfig.inspect_ilvl_offset_x or 0),
            L["INSPECT_FRAME_ILVL_VALUE_YPOS"] + (TacoTipConfig.inspect_ilvl_offset_y or 0))
    end)
    InspectAvgItemLvl:RefreshPosition()

    InspectModelFrame:CreateFontString("InspectAvgItemLvlText")
    InspectAvgItemLvlText:SetFont(L["INSPECT_FRAME_ILVL_TITLE_FONT"], L["INSPECT_FRAME_ILVL_TITLE_FONT_SIZE"])
    InspectAvgItemLvlText:SetText("iLvl")
    rawset(InspectAvgItemLvlText, "RefreshPosition", function()
        InspectAvgItemLvlText:SetPoint("BOTTOMLEFT", InspectPaperDollFrame, "BOTTOMLEFT",
            L["INSPECT_FRAME_ILVL_TITLE_XPOS"] + (TacoTipConfig.inspect_ilvl_offset_x or 0),
            L["INSPECT_FRAME_ILVL_TITLE_YPOS"] + (TacoTipConfig.inspect_ilvl_offset_y or 0))
    end)
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
    local inspect_gs, inspect_avg, r, g, b = 0, 0, 0, 0, 0
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
                InspectGearScoreText.mover = CreateMover(InspectPaperDollFrame, InspectGearScore, InspectGearScoreText,
                    function(ofx, ofy)
                        TacoTipConfig.inspect_gs_offset_x = ofx - L["INSPECT_FRAME_GS_TITLE_XPOS"]
                        TacoTipConfig.inspect_gs_offset_y = ofy - L["INSPECT_FRAME_GS_TITLE_YPOS"]
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
                InspectAvgItemLvlText.mover = CreateMover(InspectPaperDollFrame, InspectAvgItemLvl, InspectAvgItemLvlText,
                    function(ofx, ofy)
                        TacoTipConfig.inspect_ilvl_offset_x = ofx - L["INSPECT_FRAME_ILVL_TITLE_XPOS"]
                        TacoTipConfig.inspect_ilvl_offset_y = ofy - L["INSPECT_FRAME_ILVL_TITLE_YPOS"]
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
        -- Shift re-render (wide/mini style toggle via IsShiftKeyDown in
        -- onTooltipSetUnit) only matters when a player tooltip is actually
        -- on screen AND the configured tip_style reads the shift key
        -- (styles 2/4). Everything else would be a full SetUnit rebuild on
        -- every modifier press AND release for no visual change.
        if (GameTooltip and GameTooltip:IsShown()
                and (TacoTipConfig.tip_style == 2 or TacoTipConfig.tip_style == 4)) then
            local unit = resolveTooltipUnit(GameTooltip)
            if (unit and UnitIsPlayer(unit)) then
                GameTooltip:SetUnit(unit)
            end
        end
    elseif (event == "UNIT_TARGET") then
        if (GameTooltip and GameTooltip:IsShown() and TacoTipConfig.show_target) then
            local unit = ...
            if (unit) then
                local ttUnit = resolveTooltipUnit(GameTooltip)
                if (ttUnit and UnitExists(unit) and UnitIsUnit(unit, ttUnit)) then
                    GameTooltip:SetUnit(unit)
                end
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
                -- Migrate the old default dot position (TOPLEFT, TOPLEFT, 0, 0)
                -- to the new default (BOTTOMRIGHT) on version upgrade so the
                -- green dot moves to the bottom-right corner of the screen.
                if (TacoTipConfig.custom_pos
                        and TacoTipConfig.custom_pos[1] == "TOPLEFT"
                        and TacoTipConfig.custom_pos[2] == "TOPLEFT"
                        and TacoTipConfig.custom_pos[3] == 0
                        and TacoTipConfig.custom_pos[4] == 0) then
                    TacoTipConfig.custom_pos = nil
                end
            end
            -- Sanitize custom_pos: the old GetPoint()-after-drag-stop bug
            -- could have stored {nil, nil, nil, nil} which passes the
            -- "table is not nil" check below but has nil entries that
            -- crash SetPoint.  Clear it if any entry is invalid.
            if (TacoTipConfig.custom_pos) then
                local p = TacoTipConfig.custom_pos
                if (type(p[1]) ~= "string" or type(p[3]) ~= "number" or type(p[4]) ~= "number") then
                    TacoTipConfig.custom_pos = nil
                end
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
                print("|cff59f0dcTacoTip v" .. addOnVersion .. " " .. L["TEXT_HELP_WELCOME"])
                if (first_login) then
                    print("|cff59f0dcTacoTip:|r " .. L["TEXT_HELP_FIRST_LOGIN"])
                end
            end)
        end
    elseif (event == "UPDATE_MOUSEOVER_UNIT") then
        if (TacoTipConfig.instant_fade and GameTooltip and GameTooltip:IsShown() and ((GameTooltip.IsUnit and GameTooltip:IsUnit("mouseover")) or (GameTooltip.GetUnit and select(2, GameTooltip:GetUnit()) == "mouseover"))) then
            cancelFadeTimer(GameTooltip)
            local state = getTooltipState(GameTooltip)
            local timer
            timer = NewTimer(0, function()
                if (state.fadeTimer == timer) then
                    state.fadeTimer = nil
                end
                safeCall(function()
                    if (TacoTipConfig.instant_fade and not UnitExists("mouseover") and GameTooltip and GameTooltip:IsShown() and ((GameTooltip.IsUnit and GameTooltip:IsUnit("mouseover")) or (GameTooltip.GetUnit and select(2, GameTooltip:GetUnit()) == "mouseover"))) then
                        GameTooltip:Hide()
                    end
                end)
            end)
            state.fadeTimer = timer
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
        TacoTipDragButton:SetSize(32, 32)
        TacoTipDragButton:SetNormalTexture("Interface\\MINIMAP\\TempleofKotmogu_ball_green")
        local pos = TacoTipConfig.custom_pos or getDefaultTooltipMoverPosition()
        -- Safety: corrupted custom_pos (nil entries from old GetPoint bug)
        -- would crash SetPoint.  Fall back to default if invalid.
        if (type(pos[1]) ~= "string" or type(pos[2]) ~= "string") then
            pos = getDefaultTooltipMoverPosition()
        end
        TacoTipDragButton:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
        TacoTipDragButton:RegisterForDrag("LeftButton")
        TacoTipDragButton:RegisterForClicks("MiddleButtonUp", "RightButtonUp")
        local function onDragButtonDragStop(self)
            self:SetScript("OnUpdate", nil)
            self:StopMovingOrSizing()
            -- GetPoint() is unreliable after StopMovingOrSizing() — WoW's
            -- drag system leaves the frame's anchor state in an intermediate
            -- state where GetPoint() can return nil anchor values.  Use
            -- pixel-position getters relative to UIParent's BOTTOMLEFT origin
            -- (the WoW screen coordinate origin) instead.
            local left = self:GetLeft()
            local bottom = self:GetBottom()
            if (left and bottom) then
                TacoTipConfig.custom_pos = { "BOTTOMLEFT", "BOTTOMLEFT", left, bottom }
            else
                TacoTipConfig.custom_pos = getDefaultTooltipMoverPosition()
            end
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
                rawset(StaticPopupDialogs, "_TacoTipDragButtonConfirm_",
                    {
                        ["whileDead"] = 1,
                        ["hideOnEscape"] = 1,
                        ["timeout"] = 0,
                        ["exclusive"] = 1,
                        ["enterClicksFirstButton"] = 1,
                        ["text"] = L["TEXT_DLG_CUSTOM_POS_CONFIRM"],
                        ["button1"] = SAVE,
                        ["button2"] = CANCEL,
                        ["button3"] = RESET,
                        ["OnAccept"] = function() TacoTipDragButton:_Save() end,
                        ["OnAlt"] = function() TacoTipDragButton:_ResetPosition() end
                    })
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
                safeCall(onMoverTick, ...)
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
            print("|cff59f0dcTacoTip:|r " .. L["TEXT_HELP_MOVER_SHOWN"])
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
                    if (not GameTooltip or not GameTooltip:IsShown()) then
                        return
                    end
                    if (not TacoTipConfig.custom_pos) then
                        TacoTipConfig.custom_pos = getDefaultTooltipMoverPosition()
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
            -- When custom_pos is set, the GameTooltip is already anchored
            -- to TacoTipDragButton (a UIParent child) via the hook at
            -- line 1244.  Calling GameTooltip_SetDefaultAnchor here to
            -- re-anchor to UIParent creates a circular anchor family
            -- (GameTooltip → TacoTipDragButton → UIParent tries to
            -- become GameTooltip → UIParent while still in the drag
            -- button's tree), which Blizzard rejects as a family cycle.
            -- Anchor directly to the drag button instead.
            if (TacoTipConfig.custom_pos) then
                GameTooltip:SetOwner(TacoTipDragButton, "ANCHOR_NONE")
                GameTooltip:ClearAllPoints()
                local anchorPoint = TacoTipConfig.custom_anchor or "TOPLEFT"
                GameTooltip:SetPoint(anchorPoint, TacoTipDragButton, anchorPoint)
            elseif (GameTooltip_SetDefaultAnchor) then
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
                TacoTipConfig.custom_anchor = "TOPLEFT"
                print("|cff59f0dcTacoTip:|r " .. L["Custom tooltip position enabled."])
            end
            if (not TacoTipConfig.custom_anchor) then
                TacoTipConfig.custom_anchor = "TOPLEFT"
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
            print("|cff59f0dcTacoTip:|r " .. L["TEXT_HELP_MOVER_SAVED"])
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
                print("|cff59f0dcTacoTip:|r " .. L["Custom tooltip position disabled."])
            end
            if (customPositionCheck) then
                customPositionCheck:SetChecked(false)
            end
            if (moverButton) then
                setButtonEnabled(moverButton, true)
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
