local addOnName = ...
local addOnVersion = (GetAddOnMetadata and GetAddOnMetadata(addOnName, "Version")) or
    (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addOnName, "Version")) or "0.8.6"



assert(LibStub, "TacoTip requires LibStub")
assert(LibStub:GetLibrary("LibForeverInspector", true), "TacoTip requires LibForeverInspector")
assert(LibStub:GetLibrary("LibDetours-1.0", true), "TacoTip requires LibDetours-1.0")

local CI = LibStub("LibForeverInspector")
local Detours = LibStub("LibDetours-1.0")
local GearScore = _G.TT_GS
local L = _G.TACOTIP_LOCALE

local TT = _G[addOnName]

if (not TT) then
    TT = {}
    rawset(_G, addOnName, TT)
end

-- Load-progress marker.
--
-- main.lua is the LAST file in the toc and 2800 lines long, and it defines
-- TacoTip_CustomPosEnable only at the very end. A single error at file scope
-- therefore aborts everything after it: the tooltip hooks, the mover, the
-- overlays. The mover's call sites in options.lua then take their "not ready"
-- branch, which used to tell the user to /reload -- advice that cannot help,
-- because the cause is a load-time error rather than a timing one.
--
-- Recording the last stage reached turns that silence into a fact: `/tacotip
-- diag` names the region where loading stopped. Stages are plain table fields,
-- so whatever was set before the error survives it.
TT.LOAD_STAGE = "begin"
TT.LOAD_OK = false
local function stage(name)
    TT.LOAD_STAGE = name
end

stage("core")

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

-- Real implementation of the tooltip_max_width option.
--
-- GameTooltip has no SetMaximumWidth method on ANY of the five supported clients:
-- on all five branches SetMaximumWidth belongs only to BaseMenuDescriptionMixin
-- (Blizzard_Menu/Menu.lua:347) and Calendar's rootDescription, never to the
-- tooltip widget. The previous `if (tooltip.SetMaximumWidth) then` block was
-- therefore dead code everywhere and the slider was a silent no-op.
--
-- GameTooltip auto-sizes to its widest rendered line, so the way to bound it is
-- to cap the width of the line FontStrings: a FontString narrower than its text
-- wraps, one wider than its text renders exactly as before and contributes
-- nothing to the tooltip's width. Capping is therefore non-destructive for short
-- lines and only kicks in once content actually exceeds the limit.
local function applyTooltipMaxWidth(tooltip)
    if (not tooltip or type(tooltip.NumLines) ~= "function") then
        return
    end

    local maxWidth = TacoTipConfig.tooltip_max_width or 0
    local ok, numLines = pcall(tooltip.NumLines, tooltip)
    if (not ok or type(numLines) ~= "number") then
        return
    end

    local leftCap, rightCap = 0, 0
    if (maxWidth > 0) then
        leftCap = maxWidth
        rightCap = math.floor(maxWidth * 0.5)
    end

    -- Walk a little past the current line count: the pooled lines are reused
    -- across hovers, so a line left over from a longer previous tooltip still
    -- carries the old cap and would keep the tooltip wide.
    local scan = math.max(numLines + 4, 20)
    for i = 1, scan do
        local leftLine = getTooltipLeftLine(tooltip, i)
        if (leftLine and type(leftLine.SetWidth) == "function") then
            if (leftLine._tacoTipMaxWidth ~= leftCap) then
                pcall(leftLine.SetWidth, leftLine, leftCap)
                leftLine._tacoTipMaxWidth = leftCap
            end
        end
        local rightLine = getTooltipRightLine(tooltip, i)
        if (rightLine and type(rightLine.SetWidth) == "function") then
            if (rightLine._tacoTipMaxWidth ~= rightCap) then
                pcall(rightLine.SetWidth, rightLine, rightCap)
                rightLine._tacoTipMaxWidth = rightCap
            end
        end
    end
end

-- Pawn detection: check PawnClassicLastUpdatedVersion, PawnLastUpdatedVersion, or public API functions.
local pawnClassicVer = rawget(_G, "PawnClassicLastUpdatedVersion")
local pawnRetailVer = rawget(_G, "PawnLastUpdatedVersion")
local pawnApiPresent = type(_G.PawnGetItemData) == "function" and type(_G.PawnGetSingleValueFromItem) == "function" and
    type(_G.PawnGetScaleColor) == "function"
local isPawnLoaded = (pawnClassicVer and pawnClassicVer >= 2.0538) or (pawnRetailVer and pawnRetailVer >= 2.0) or
    pawnApiPresent

local HORDE_ICON = "|TInterface\\TargetingFrame\\UI-PVP-HORDE:16:16:-2:0:64:64:0:38:0:38|t"
local ALLIANCE_ICON = "|TInterface\\TargetingFrame\\UI-PVP-ALLIANCE:16:16:-2:0:64:64:0:38:0:38|t"
local PVP_FLAG_ICON = "|TInterface\\GossipFrame\\BattleMasterGossipIcon:0|t"
local ACHIEVEMENT_ICON = "|TInterface\\AchievementFrame\\UI-Achievement-TinyShield:18:18:0:0:20:20:0:12.5:0:12.5|t"
local GetClassAtlas = _G.GetClassAtlas

local POWERBAR_UPDATE_RATE = 0.2

-- Window in which the second of the library's back-to-back completion callbacks
-- (INVENTORY_READY then TALENTS_READY, both fired by one cacheUnitData) is treated
-- as a duplicate of the first and skipped. 0.1s is far shorter than any genuine
-- second update -- a later inspect of the same unit, an item load completing, or a
-- stale refresh all arrive much later -- and long enough to cover the two events
-- that are fired in the same frame.
local INSPECT_RENDER_COALESCE = 0.1

local NewTicker = _G.C_Timer and _G.C_Timer.NewTicker
local NewTimer = _G.C_Timer and _G.C_Timer.NewTimer
local CAfter = _G.C_Timer and _G.C_Timer.After
local GetBestMapForUnit = _G.C_Map and _G.C_Map.GetBestMapForUnit
-- C_Item namespace and Blizzard ObjectAPI
local Item = _G.Item
-- Namespaced on purpose: there is no bare global RequestLoadItemDataByID on any
-- of the five supported clients, only C_Item.RequestLoadItemDataByID.
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
---@field itemLoadCancel function|nil  -- ItemMixin:ContinueWithCancelOnItemLoad canceler
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
-- NOTE: GetQuestDifficultyColor is deliberately NOT cached here. On the Classic
-- family it is a Lua global defined by Blizzard_UIParent (Classic/TBC/Wrath
-- UIParent.lua), whose toc declares LoadFirst: 1. TacoTip declares no LoadFirst,
-- so caching it at file scope can latch nil for the whole session and silently
-- disable hostile level colouring. It is resolved per call instead.

local playerClass = select(2, UnitClass("player"))

-- Safe-call wrapper. Routes errors through Blizzard's geterrorhandler()
-- global so they are captured by error display addons (BugSack, !Swatter,
-- BugGrabber, etc.) instead of silently breaking the GameTooltip.
-- Usage: safeCall(myHandler, arg1, arg2, ...)
-- Error handling for the tooltip pipeline.
--
-- This used to be plain `xpcall(fn, geterrorhandler(), ...)`, and that is what
-- put a red message in the chat frame every time anything in the pipeline raised.
-- On a unit frame the pipeline runs many times a second, so a single C API
-- argument error -- which carries no Lua stack, so BugSack shows it with no
-- trace -- was reprinted endlessly and buried the chat.
--
-- The default handler still runs, but only ONCE per distinct message for the
-- session. A real defect stays visible; a per-frame repeat does not. The most
-- recent message is recorded so `/tacotip diag` can name it, which is the only
-- way to identify a C API error that has no stack to report.
local defaultErrorHandler = (type(geterrorhandler) == "function") and geterrorhandler() or nil
local reportedErrors = {}
TT.lastTooltipError = nil

local function handlePipelineError(message)
    if (message == nil) then
        return
    end
    local text = tostring(message)
    TT.lastTooltipError = text
    if (not reportedErrors[text]) then
        reportedErrors[text] = true
        if (defaultErrorHandler) then
            defaultErrorHandler(text)
        end
    end
end

local function safeCall(fn, ...)
    return xpcall(fn, handlePipelineError, ...)
end

-- Calls a widget method and, if it raises, re-raises with the call site named.
--
-- A C API argument error ("... must be the name of an existing scale") carries no
-- Lua stack, so the handler receives the message with nothing identifying which
-- call produced it. Every string-taking call in the tooltip render path goes
-- through here, so one reported message names the exact call and argument class
-- instead of forcing a bisect through the whole pipeline.
local function callLabeled(label, obj, method, ...)
    local fn = obj and obj[method]
    if (type(fn) ~= "function") then
        return nil
    end
    local ok, err = pcall(fn, obj, ...)
    if (not ok) then
        error(label .. "/" .. method .. ": " .. tostring(err), 0)
    end
    return err
end

-- Modern tooltip templates (GameTooltipTemplate -> TooltipBackdropTemplate)
-- attach a NineSlice child frame that renders the actual backdrop.
-- SetBackdrop/SetBackdropBorderColor on the parent has NO visual effect when
-- NineSlice renders the backdrop. The apply-backdrop functions below detect
-- the NineSlice child at runtime and use NineSlice:SetBorderColor/
-- SetCenterColor directly. This early Mixin provides a fallback for any
-- client whose tooltip template lacks NineSlice.
do
    -- The signal has to be NineSlice, NOT SetBackdrop. On Retail and WoW
    -- Forever the tooltip template is SharedTooltipArtTemplate, which provides
    -- a NineSlice child and does NOT mix in BackdropTemplateMixin -- so
    -- GameTooltip.SetBackdrop is nil there even though the tooltip renders
    -- correctly. Testing SetBackdrop therefore ran this Mixin on precisely the
    -- two clients that must not have it, grafting 16 unused backdropInfo-based
    -- methods (SetBackdrop, SetBackdropColor, ApplyBackdrop, ClearBackdrop, ...)
    -- onto the live GameTooltip. Require BOTH "no NineSlice" and "no
    -- SetBackdrop" so it only fires for a genuinely legacy template.
    local needsMixin = _G.GameTooltip
        and not _G.GameTooltip.NineSlice
        and _G.BackdropTemplateMixin
        and not _G.GameTooltip.SetBackdrop
    if (needsMixin and _G.Mixin) then
        Mixin(_G.GameTooltip, _G.BackdropTemplateMixin)
    end
    stage("backdrop-mixin")
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
    local floor = math.floor
    return string.format("|cFF%02x%02x%02x", floor((r or 1) * 255), floor((g or 1) * 255), floor((b or 1) * 255))
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

local function getClassColor(class, optClass)
    if (type(class) == "table" and optClass) then
        class = optClass
    end
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
        -- Blank the line ONLY if it is still ours. The index is remembered
        -- across hovers, but any other addon adding a line to the tooltip --
        -- Baganator's tracked item amount, Details' ilvl -- shifts every index
        -- after it, so line 2 of an item tooltip is not the guild line this
        -- index was recorded for. Blanking it unconditionally erased the other
        -- addon's line instead, reported as "item amounts break on the second
        -- mouseover". The text is the only proof of ownership we have.
        if (left and left.GetText and left:GetText() == tooltip.TacoTipGuildLineText) then
            left:SetText()
        end
        tooltip.TacoTipGuildLineIndex = nil
        tooltip.TacoTipGuildLineText = nil
    end
end

local function clearTooltipLevelColorLine(tooltip)
    if (tooltip and tooltip.TacoTipLevelColorLineIndex) then
        local left = getTooltipLeftLine(tooltip, tooltip.TacoTipLevelColorLineIndex)
        if (left and left.GetText and left:GetText() == tooltip.TacoTipLevelColorLineText) then
            left:SetText()
        end
        tooltip.TacoTipLevelColorLineIndex = nil
        tooltip.TacoTipLevelColorLineText = nil
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
    local GetQuestDifficultyColor = _G.GetQuestDifficultyColor
    if (not unit or type(GetQuestDifficultyColor) ~= "function") then
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
        tooltip.TacoTipLevelColorLineText = coloredLevel
    end

    if (level and level > 0) then
        return string.gsub(textLine, levelToken, coloredLevel, 1)
    end

    return string.gsub(textLine, "%?%?", coloredLevel, 1)
end

-- Specialization icon texture overlay. MODERN CLIENTS ONLY.
--
-- On Retail and WoW Forever the specialization icon is a fileID, and a |T
-- escape accepts only a texture path or an atlas, so the icon is drawn with a
-- Texture instead (Texture:SetTexture takes a fileID or a path -- this is what
-- Blizzard does via SetItemButtonTexture).
--
-- The Classic path is untouched: formatSpecializationText still resolves the
-- icon with the original lookup below and inlines it as a |T escape.
local function getOrCreateSpecIconFrame(tooltip)
    if (not tooltip) then
        return nil
    end
    if (tooltip.TacoTipSpecIcon) then
        return tooltip.TacoTipSpecIcon
    end
    -- :CreateTexture(), NOT CreateFrame("Texture", ...). "Texture" is a widget
    -- type, not a frame type, so CreateFrame rejects it outright:
    --   CreateFrame: Unknown frame type 'Texture'
    -- That threw on every unit tooltip on Retail and WoW Forever -- the only two
    -- clients that take this overlay path, since useIconOverlay is Retail/Forever
    -- only -- and because it fired inside the tooltip hook it aborted the rest of
    -- the enhancement, so nothing at all was added. Classic never reached it.
    local tex = tooltip:CreateTexture(nil, "ARTWORK")
    tex:SetSize(14, 14)
    tex:SetPoint("RIGHT", tooltip, "LEFT", -2, 0)
    -- Frame level is a FRAME method, and on Retail / WoW Forever a Texture is a
    -- Region, not a Frame. SetSize and SetPoint above are Region methods and work
    -- there; SetFrameLevel simply does not exist, so calling it raised
    -- "attempt to call a nil value" on every unit tooltip. Confirmed in game:
    -- lines above this one execute, this one throws.
    --
    -- Only Texture is affected. PlayerModel, Frame and Button are Frames on every
    -- client, which is why the other SetFrameLevel call sites in this file are
    -- safe. This overlay is modern-clients-only in any case, so the guarded
    -- branch changes nothing on the Classic family.
    --
    -- On modern clients the texture keeps the ARTWORK draw layer CreateTexture
    -- already gave it, which is the Region-side equivalent of the frame level the
    -- Classic branch sets.
    if (tex.SetFrameLevel) then
        tex:SetFrameLevel((tooltip.GetFrameLevel and tooltip:GetFrameLevel()) or 1)
    end
    tex:Hide()
    tooltip.TacoTipSpecIcon = tex
    return tex
end

local function applySpecializationIcon(tooltip, icon)
    if (not icon) then
        -- Do not create the frame just to hide it: the Classic family never uses
        -- the overlay, and creating it there would be a behaviour change.
        if (tooltip and tooltip.TacoTipSpecIcon) then
            tooltip.TacoTipSpecIcon:Hide()
        end
        return
    end
    local tex = getOrCreateSpecIconFrame(tooltip)
    if (not tex) then
        return
    end
    -- pcall: SetTexture is secret-argument-gated on Retail for tainted values.
    local ok = pcall(tex.SetTexture, tex, icon)
    if (not ok) then
        tex:Hide()
        return
    end
    tex:ClearAllPoints()
    tex:SetPoint("RIGHT", tooltip, "LEFT", -2, 0)
    tex:Show()
end

-- Returns the raw icon value (a texture path or a fileID) for a specialization
-- index, or nil. Delegates to the library, which owns the per-client query
-- form and the cache. MODERN CLIENTS ONLY -- the library hard-gates on family.
local function getModernSpecializationIcon(specIndex, groupIndex, isInspect, target)
    if (not specIndex or not CI or not CI.GetModernSpecializationIcon) then
        return nil
    end
    local ok, icon = pcall(CI.GetModernSpecializationIcon, CI, specIndex, groupIndex, isInspect, target)
    if (not ok) then
        return nil
    end
    return icon
end

TT.GetModernSpecializationIcon = getModernSpecializationIcon

-- Original, known-working Classic icon lookup. Left exactly as it was.
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

-- engineName / engineIcon are the values the client itself reports for this
-- unit's active specialization. On Retail and WoW Forever they are already
-- localized, so they take priority over the library's built-in English
-- spec_table; on the Classic family they are nil and the table is used.
local function formatSpecializationText(class, specIndex, p1, p2, p3, dim, engineName, engineIcon)
    local specName
    if (engineName and engineName ~= "") then
        specName = engineName
    elseif (class and specIndex) then
        -- Specialization name resolution.
        --
        -- The old code consulted _G.TACOTIP_SPEC_NAMES here "because it follows
        -- the saved addon-language override" -- but nothing ever wrote that
        -- global, so the lookup was always nil and every spec name silently
        -- fell through to the library's built-in table. The dead branch and the
        -- comment describing it are removed; GetSpecializationName is now the
        -- single source and already checks its own table.
        specName = CI:GetSpecializationName(class, specIndex, true)
    end
    if (not specName) then
        return nil
    end

    -- Icon source. The Classic lookup returns a numeric fileID (the static
    -- talent table's `texture` field), and the working addon inlines it with
    -- tostring() because a |T escape accepts a fileID as well as a texture
    -- path. Requiring type() == "string" here silently dropped every fileID,
    -- which is why no specialization icon rendered.
    local iconTexture = engineIcon
    if (not iconTexture) then
        iconTexture = getSpecializationIcon(class, specIndex)
    end
    local iconText = ""
    if (iconTexture) then
        iconText = string.format("|T%s:14:14:0:0:64:64:4:60:4:60|t ", tostring(iconTexture))
    end
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
    local isClassicFamily = CI and CI.IsClassic and (CI:IsClassic() or CI:IsTBC() or CI:IsWotlk())
    if (p1 and p2 and p3 and (p1 > 0 or p2 > 0 or p3 > 0 or isClassicFamily)) then
        return string.format("%s%s [%d/%d/%d]", iconText, coloredName, p1 or 0, p2 or 0, p3 or 0)
    else
        return string.format("%s%s", iconText, coloredName)
    end
end

TT.GetFormattedSpecializationText = function(self, class, specIndex, p1, p2, p3, dim, engineName, engineIcon)
    return formatSpecializationText(class, specIndex, p1, p2, p3, dim, engineName, engineIcon)
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
                -- No OnUpdate. It used to run every 0.05s forever, on every
                -- tooltip frame, for one job: copying the parent's alpha. The
                -- portrait no longer mirrors the tooltip's alpha, so the script
                -- had nothing left to do and was pure per-frame cost.
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

-- Line 1 is the NAME (player on a unit tooltip, item on an item tooltip); the
-- rest is body. This used to apply one size to every line, flattening the name
-- to body size.
local TOOLTIP_NAME_FONT_SIZE_DELTA = 2

local function applyTooltipFonts(tooltip)
    if (not tooltip) then
        return
    end
    local fontPath = (TT.GetResolvedTooltipFont and TT:GetResolvedTooltipFont()) or TacoTipConfig.tooltip_font or
        "Fonts\\FRIZQT__.TTF"
    local fontSize = TacoTipConfig.tooltip_font_size or 12
    local nameSize = fontSize + TOOLTIP_NAME_FONT_SIZE_DELTA
    local numLines = (tooltip.NumLines and tooltip:NumLines()) or 0
    for i = 1, math.max(numLines + 4, 20) do
        local left = getTooltipLeftLine(tooltip, i)
        local right = getTooltipRightLine(tooltip, i)
        -- Guard on what was applied, not on a dirty flag. This is the same
        -- idiom applyTooltipMaxWidth uses for the line width cap, and it is the
        -- only thing that makes this loop affordable: the floor is 20 lines, so
        -- an unguarded call costs 20 widget lookups, 20 pcall()s and 20 SetFont
        -- C calls on EVERY render -- and it does so on the item path too, once
        -- per hover. Worse, this runs after the SetText loop, so each SetFont
        -- invalidates the text measurement that loop just computed.
        --
        -- No invalidation hook is needed for new lines: a FontString that has
        -- not been fonted yet carries a nil field, which never compares equal
        -- to a font, so a line the pool has just handed out is picked up on the
        -- next render by itself.
        local lineSize = (i == 1) and nameSize or fontSize
        if (left) then
            if (left._tacoTipFont ~= fontPath or left._tacoTipFontSize ~= lineSize) then
                callLabeled("applyTooltipFonts", left, "SetFont", fontPath, lineSize)
                left._tacoTipFont, left._tacoTipFontSize = fontPath, lineSize
            end
        end
        if (right) then
            if (right._tacoTipFont ~= fontPath or right._tacoTipFontSize ~= lineSize) then
                callLabeled("applyTooltipFonts", right, "SetFont", fontPath, lineSize)
                right._tacoTipFont, right._tacoTipFontSize = fontPath, lineSize
            end
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

-- Shared insets for applyTooltipBackdrop. Allocated once: the backdrop info was
-- rebuilt on every render, and the nested insets table with it, so two table
-- allocations per hover bought nothing -- SetBackdrop does not retain the insets
-- table, it reads four numbers out of it and copies them.
local TOOLTIP_BACKDROP_INSETS = { left = 4, right = 4, top = 4, bottom = 4 }

-- Colour for a power type PowerBarColor does not key. Shared and read-only: the
-- consumer only reads .r/.g/.b, and one table for the whole session replaces the
-- per-update throwaway this replaced. See the power-bar Update closure.
local FALLBACK_POWER_COLOR = { r = 0, g = 0, b = 1 }

local function applyTooltipBackdrop(tooltip)
    local backdrop = getOrCreateBackdropFrame(tooltip)
    if (not backdrop or not backdrop.SetBackdrop) then
        return
    end

    local backgroundTexture = (TT.GetResolvedTooltipBackground and TT:GetResolvedTooltipBackground()) or
        TacoTipConfig.tooltip_background_texture
        or (TT.GetDefaultTooltipBackground and TT:GetDefaultTooltipBackground())
        or "Interface\\Tooltips\\UI-Tooltip-Background"
    -- Per-client default: the modern pair is built around the BackdropTextures set
    -- and the Classic family around UI-Tooltip-Border, so a single hardcoded
    -- fallback points at the wrong art on one side of the split. See
    -- TT:GetDefaultTooltipBorder in textures.lua.
    local borderTexture = (TT.GetResolvedTooltipBorder and TT:GetResolvedTooltipBorder()) or
        TacoTipConfig.tooltip_border_texture
        or (TT.GetDefaultTooltipBorder and TT:GetDefaultTooltipBorder())
        or "Interface\\Tooltips\\UI-Tooltip-Border"
    local hasBorder = borderTexture and borderTexture ~= ""

    -- Resolve what this branch will actually draw, then compare. SetBackdrop
    -- reassigns the backdrop, re-applies both colours and re-tiles the edge
    -- texture, none of which depends on the render -- so on a re-render with
    -- unchanged settings it was pure cost. The signature covers exactly the
    -- inputs the ACTIVE branch reads:
    --
    --  * edgeFile/edgeSize always, and bgFile only on the legacy branch, which
    --    is the only one that draws a background. Including bgFile in the
    --    border-only signature would re-tile whenever the background setting
    --    changed, for a pixel that branch never draws.
    --  * NOT tooltip_border_alpha. That is applied by SetBackdropBorderColor in
    --    applyTooltipBorderOverlay -- a different call on a different path -- so
    --    an alpha change must not drag a re-tile along with it.
    --
    -- tostring() rather than concatenation, because edgeFile is nil when
    -- hasBorder is false and "nil" has to be distinguishable from a real path.
    local edgeFile = hasBorder and borderTexture or nil
    local edgeSize = hasBorder and ((TT.GetResolvedTooltipBorderEdgeSize
            and TT:GetResolvedTooltipBorderEdgeSize())
        or TacoTipConfig.tooltip_border_edge_size or 16) or 0
    local signature = tostring(edgeFile) .. "|" .. tostring(edgeSize)
    if (not backdrop.isBorderOnly) then
        signature = signature .. "|" .. tostring(backgroundTexture) .. "|tile16"
    end
    if (backdrop._tacoTipBackdropSig == signature) then
        return
    end
    backdrop._tacoTipBackdropSig = signature

    if (backdrop.isBorderOnly) then
        -- NineSlice-equipped tooltip: border overlay only. NineSlice provides
        -- the default background — we only draw the colored border on top.
        callLabeled("applyTooltipBackdrop", backdrop, "SetBackdrop", {
            edgeFile = edgeFile,
            edgeSize = edgeSize,
            insets = TOOLTIP_BACKDROP_INSETS
        })
    else
        -- Legacy full backdrop: background + border on the tooltip itself
        callLabeled("applyTooltipBackdrop", backdrop, "SetBackdrop", {
            bgFile = backgroundTexture,
            edgeFile = edgeFile,
            tile = true,
            tileSize = 16,
            edgeSize = edgeSize,
            insets = TOOLTIP_BACKDROP_INSETS
        })
    end
end

local function applyTooltipBorderOverlay(tooltip, unit, borderR, borderG, borderB)
    local backdrop = tooltip and tooltip.TacoTipBackdropFrame
    if (not backdrop or not backdrop.SetBackdropBorderColor) then
        return
    end

    local borderTexture = (TT.GetResolvedTooltipBorder and TT:GetResolvedTooltipBorder()) or
        TacoTipConfig.tooltip_border_texture
        or (TT.GetDefaultTooltipBorder and TT:GetDefaultTooltipBorder())
        or "Interface\\Tooltips\\UI-Tooltip-Border"
    local hasBorder = borderTexture and borderTexture ~= ""
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
-- function checks borderTexture and returns early when the texture is empty,
-- leaving the stale class-colored border in place. The direct frame write
-- below is not subject to the texture guard so it always resets the colour,
-- regardless of the configured border texture.
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

local function resolveUnitTokenFromGUID(guid, tooltip)
    if (not guid) then return nil end
    local owner = tooltip and tooltip.GetOwner and tooltip:GetOwner()
    if (owner and owner.unit and UnitExists and UnitExists(owner.unit) and UnitGUID(owner.unit) == guid) then
        return owner.unit
    end
    if (UnitGUID("player") == guid) then
        return "player"
    elseif (UnitGUID("mouseover") == guid) then
        return "mouseover"
    elseif (UnitGUID("target") == guid) then
        return "target"
    elseif (UnitGUID("pet") == guid) then
        return "pet"
    elseif (UnitGUID("focus") == guid) then
        return "focus"
    end
    return nil
end

local function resolveTooltipUnit(tooltip, unit)
    if (unit and UnitExists and UnitExists(unit)) then
        if (tooltip and tooltip.IsUnit and tooltip:IsUnit(unit)) then
            return unit
        end
        return unit
    end
    if (TooltipUtil and TooltipUtil.GetDisplayedUnit and tooltip) then
        local ok, _, dispUnit, guid = pcall(TooltipUtil.GetDisplayedUnit, tooltip)
        if (ok and dispUnit and UnitExists and UnitExists(dispUnit)) then
            return dispUnit
        elseif (ok and guid) then
            local resolved = resolveUnitTokenFromGUID(guid, tooltip)
            if (resolved) then return resolved end
        end
    end
    if (tooltip and tooltip.GetUnit) then
        local ok, _, tooltipUnit, guid = pcall(tooltip.GetUnit, tooltip)
        if (ok and tooltipUnit and UnitExists and UnitExists(tooltipUnit)) then
            if (tooltip.IsUnit) then
                local isUOk, isU = pcall(tooltip.IsUnit, tooltip, tooltipUnit)
                if (isUOk and isU) then
                    return tooltipUnit
                end
            else
                return tooltipUnit
            end
        elseif (ok and guid) then
            local resolved = resolveUnitTokenFromGUID(guid, tooltip)
            if (resolved) then return resolved end
        end
    end
    if (tooltip and tooltip.GetOwner) then
        local owner = tooltip:GetOwner()
        if (owner and owner.unit and UnitExists and UnitExists(owner.unit)) then
            return owner.unit
        end
    end
    -- Last resort. Returning "mouseover" unconditionally is wrong whenever the
    -- tooltip is actually showing some other unit -- on the four clients that
    -- lack TooltipUtil (Classic Era, TBC, Titanforge, and possibly Forever) this
    -- branch is reached whenever GetUnit gives a stale token, and the result is
    -- the mouseover unit's class colour, portrait, GearScore and talents painted
    -- onto e.g. the target tooltip. Only accept it when the tooltip really is the
    -- mouseover tooltip.
    if (tooltip and type(tooltip.IsUnit) == "function" and UnitExists and UnitExists("mouseover")) then
        local ok, isMouseover = pcall(tooltip.IsUnit, tooltip, "mouseover")
        if (ok and isMouseover) then
            return "mouseover"
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
    -- later in case the tooltip frame backdrop is refreshed after tooltip set.
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
        if (type(NewTimer) == "function") then
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
    end

    applyTooltipFonts(tooltip)

    local portrait = ensureTooltipPortrait(tooltip)
    local portraitScale = TacoTipConfig.tooltip_portrait_scale or 1
    -- 66 x 88 (was 72 x 96). Still exact 3:4, still exact integers at every
    -- slider stop: 33x44, 66x88, 99x132, 132x176.
    local portraitW = math.floor(66 * portraitScale)
    local portraitH = math.floor(88 * portraitScale)
    if (portrait) then
        if (TacoTipConfig.tooltip_portrait and unit) then
            -- Anchor once per side, not once per render.
            --
            -- The side is read from tooltip:GetRight() against the screen width.
            -- On Retail and WoW Forever our whole unit handler runs from the
            -- TooltipDataProcessor post-call, and TooltipDataHandler fires that
            -- BEFORE its own self:Show() -- the order is ProcessLines(), postcalls,
            -- then Show(). So the tooltip has never been laid out when we get
            -- here, and GetRight() is 0 on an unshown frame. That made the
            -- side-flip decide from garbage, re-evaluated on every render, and
            -- unanchor and re-anchor the portrait each time.
            --
            -- The side is therefore cached on the tooltip and only recomputed
            -- when something that can genuinely change it happens: a scale
            -- change, or the tooltip actually being shown. Cached first, then
            -- recomputed once from a laid-out frame, so the first anchor of a
            -- tooltip is still correct.
            local cachedSide = getTooltipState(tooltip).portraitSide
            local shown = (not tooltip.IsShown) or tooltip:IsShown()
            local invertSide = TacoTipConfig.tooltip_portrait_invert_side and true or false
            -- Invert is in the cache key for the same reason scale is: without
            -- it, ticking the option does nothing until the next scale change.
            if (cachedSide == nil or portrait._tacoTipScale ~= portraitScale
                    or portrait._tacoTipInvert ~= invertSide
                    or (shown and not getTooltipState(tooltip).portraitAnchored)) then
                local tooltipRight = tooltip:GetRight() or 0
                local screenWidth = (UIParent and UIParent:GetRight())
                    or (_G["GetScreenWidth"] and _G["GetScreenWidth"]()) or 1000
                -- An unshown frame reports 0. 0 < screenWidth, so it resolves to
                -- the left-hand side, which is the correct default for a tooltip
                -- anchored on the right of the screen.
                cachedSide = (tooltipRight > 0 and tooltipRight >= screenWidth) and "left" or "right"
                -- Inverted before the side-to-anchor mapping below, so that
                -- mapping stays in one place. Off by default, so nobody who
                -- never touches the option sees any change.
                if invertSide then
                    cachedSide = (cachedSide == "left") and "right" or "left"
                end
                ---@diagnostic disable-next-line: inject-field
                getTooltipState(tooltip).portraitSide = cachedSide
                ---@diagnostic disable-next-line: inject-field
                getTooltipState(tooltip).portraitAnchored = shown
                portrait._tacoTipScale = portraitScale
                ---@diagnostic disable-next-line: inject-field
                portrait._tacoTipInvert = invertSide
                portrait:ClearAllPoints()
                portrait:SetSize(portraitW, portraitH)
                TT.ev.portraitAnchor = (TT.ev.portraitAnchor or 0) + 1
                if (cachedSide == "left") then
                    portrait:SetPoint("TOPRIGHT", tooltip, "TOPLEFT", -8, 0)
                else
                    portrait:SetPoint("TOPLEFT", tooltip, "TOPRIGHT", 8, 0)
                end
            end
            local is3D = TacoTipConfig.tooltip_portrait_3d
            -- 3D PlayerModel renders BOTH players and NPCs/enemies via SetUnit.
            -- The old UnitIsPlayer gate sent NPCs to SetPortraitTexture, which is
            -- a no-op on a Model frame and left the previous model visible (bleed).
            --
            -- The model must only be torn down when the unit actually CHANGED.
            -- SetUnit loads a mesh asynchronously, so clearing and reloading on
            -- every render blanks the portrait until the load resolves. This
            -- function runs at the end of EVERY successful unit render, and
            -- GearScore item loads complete asynchronously and re-drive it many
            -- times for the same unit, so an unconditional reload here strobed
            -- the model for as long as loads kept arriving.
            --
            -- The cache is keyed on the unit's GUID rather than the unit token:
            -- "mouseover" and "target" are different tokens for the same
            -- character, and a token-keyed cache would reload a model that is
            -- already showing the right person. UnitGUID is the identity that
            -- actually decides which mesh is correct.
            if (is3D and portrait.SetUnit) then
                local modelKey = (unit and UnitGUID and UnitGUID(unit)) or unit
                if (portrait.tacoTipModelKey ~= modelKey) then
                    -- Clear first so the previous character's mesh cannot persist
                    -- while the new one streams in (pcall: ClearModel may be absent
                    -- on some clients).
                    pcall(portrait.ClearModel, portrait)
                    if (pcall(portrait.SetUnit, portrait, unit)) then
                        portrait.tacoTipModelKey = modelKey
                    else
                        -- SetUnit failed: leave the cache empty so the next render
                        -- retries rather than believing a model is loaded.
                        portrait.tacoTipModelKey = nil
                    end
                end
                pcall(portrait.SetPortraitZoom, portrait, TacoTipConfig.tooltip_portrait_zoom or 0.7)
            else
                -- 2D fallback only when 3D model creation failed (portrait is a Texture).
                pcall(_G.SetPortraitTexture, portrait, unit)
            end
            -- The portrait keeps its own alpha. It used to be slaved to
            -- tooltip:GetAlpha() every render, plus a permanent 0.05s OnUpdate
            -- that polled the same value -- and on Retail and WoW Forever that
            -- read happens before Blizzard's own Show(), so it sampled a frame
            -- that had never been presented. The portrait was set from that
            -- unusable value and then walked back up by the poll, which is what
            -- read as the portrait dropping into frame. A frame that is not
            -- shown has no meaningful alpha to copy, so it is not copied.
            if (portrait.SetAlpha) then
                portrait:SetAlpha(1)
            end
            portrait:Show()
        else
            portrait:Hide()
        end
    end

    local barTexture = (TT.GetResolvedTooltipStatusBarTexture and TT:GetResolvedTooltipStatusBarTexture()) or
        TacoTipConfig.tooltip_bar_texture or "Interface\\TargetingFrame\\UI-TargetingFrame-BarFill"
    if (tooltip == GameTooltip and GameTooltipStatusBar and GameTooltipStatusBar.SetStatusBarTexture) then
        callLabeled("tooltipHPBar", GameTooltipStatusBar, "SetStatusBarTexture", barTexture)
    end
    if (TacoTipPowerBar and TacoTipPowerBar.SetStatusBarTexture) then
        callLabeled("tooltipPowerBar", TacoTipPowerBar, "SetStatusBarTexture", barTexture)
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

-- Re-entrancy guard for the GearScore completion callback.
--
-- itemcacheCB (gearscore.lua) and its Pawn twin fire this once an item load
-- completes. The call below re-drives the tooltip, which re-runs the whole
-- pipeline: our unit post-call recomputes GearScore, which registers further
-- item loads, which complete and call straight back in here. That nesting is
-- unbounded, and on a unit frame it shows as the tooltip resetting over and over
-- in the same spot -- the anchor never changes, only the content is rebuilt,
-- many times a second, for as long as the mouse rests there.
--
-- A nested call for the guid we are already servicing is satisfied by the call
-- in progress, so it is dropped. A nested call for a DIFFERENT guid is deferred
-- and run once after we unwind, so no work is lost. The common, non-nested case
-- is unchanged.
local gsCallbackActive = false
local gsCallbackPending = nil

function TacoTip_GSCallback(guid)
    TT.ev.gsCallback = (TT.ev.gsCallback or 0) + 1
    if (gsCallbackActive) then
        gsCallbackPending = guid
        TT.ev.gsCallbackReentrant = (TT.ev.gsCallbackReentrant or 0) + 1
        return
    end
    local ttUnit = resolveTooltipUnit(GameTooltip)
    if (not (ttUnit and UnitGUID(ttUnit) == guid)) then
        TT.ev.gsCallbackWrongUnit = (TT.ev.gsCallbackWrongUnit or 0) + 1
        return
    end
    gsCallbackActive = true
    -- pcall both branches and clear the guard unconditionally: this is a global
    -- callback reached from the item-load path, and a throw here would either
    -- leave the guard latched (silently killing every later callback) or
    -- surface as an unrelated error from deep inside a load handler.
    if (GameTooltip.UpdateTooltip) then
        pcall(GameTooltip.UpdateTooltip, GameTooltip)
    else
        pcall(GameTooltip.SetUnit, GameTooltip, ttUnit)
    end
    gsCallbackActive = false
    local pending = gsCallbackPending
    gsCallbackPending = nil
    if (pending and pending ~= guid) then
        TacoTip_GSCallback(pending)
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

-- keepModel, not destroyModel, and the default is TEAR-DOWN.
--
-- A GearScore item load completes asynchronously and re-enters the whole
-- pipeline through TacoTip_GSCallback -> GameTooltip:SetUnit for the SAME unit.
-- That is not a unit change, but the teardown used to Hide() the portrait on it
-- regardless, because the Hide() sat OUTSIDE the destroy guard. The model
-- survived; the FRAME did not. So the portrait was hidden and re-shown once per
-- item that finished loading, on an unchanged character, and with a
-- tooltip_delay or the border deferral in flight the re-show lands after the
-- hide -- the drop-and-slide, on a model that never needed to change.
--
-- Only onTooltipSetUnit can prove the unit did not change, and it is the single
-- caller that passes this argument. Every other caller -- item, spell, quest,
-- map POI, and a unit tooltip with no unit resolved -- defaults to teardown:
-- those tooltips have no unit at all, so a character model is meaningless there
-- and is freed rather than left resident and hidden.
local function clearTooltipVisuals(tooltip, preservePendingItem, keepModel, reason, retainModel)
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
    -- The portrait side cache is per-SHOW, not per-session -- but only where
    -- "show" means a real recycle.
    --
    -- applyTooltipAppearance recomputes the side only when the cache is absent,
    -- the scale changed, or the frame is shown and not yet anchored, and it
    -- latches portraitAnchored to true. Nothing else in the addon ever wrote
    -- either field, so once anchored the side stayed whatever the first hover
    -- decided -- for the life of the GameTooltip frame, i.e. until /reload. With
    -- anchor_mouse on, hovering a unit on the far side of the screen then left
    -- the portrait hanging off the wrong edge.
    --
    -- The reset is keyed on keepModel rather than placed unconditionally, and
    -- that is not a detail. clearTooltipVisuals runs on EVERY successful unit
    -- render, not only on a recycle: onTooltipSetUnit calls it at :1392 with
    -- keepModel = (previousGUID ~= nil and previousGUID == guid). An
    -- unconditional reset here therefore cleared the latch on every re-render
    -- too, and since a GearScore item load re-drives the render many times for
    -- one character, that put back the per-render anchor this cache exists to
    -- avoid -- the exact regression 0.7.9 fixed, and the existing
    -- "anchored once across 5 re-renders" assertion caught it.
    --
    -- keepModel is the precise discriminator, and it is already the addon's:
    -- true means "same character, re-rendered" (a completing item load, a border
    -- refresh), which is the one case where the layout has not changed. False
    -- means a genuine recycle or a genuine unit change, and both are a new
    -- layout, so the next shown frame is the right thing to recompute from.
    if (not keepModel) then
        state.portraitSide = nil
        state.portraitAnchored = false
        clearTooltipPlayerClassColor(tooltip)
        resetTooltipBorderToDefault(tooltip)
        if (tooltip.TacoTipPortrait) then
            tooltip.TacoTipPortrait:Hide()
        end
        if (tooltip.TacoTipSpecIcon) then
            tooltip.TacoTipSpecIcon:Hide()
        end
        if (tooltip == GameTooltip and TacoTipPowerBar) then
            TacoTipPowerBar:Hide()
            stopPowerBarTicker()
        end
    end
    clearTooltipGuildLine(tooltip)
    clearTooltipLevelColorLine(tooltip)
    -- The 3D portrait frame is ALWAYS hidden here, but the loaded model is
    -- only destroyed when the caller says the unit actually changed.
    --
    -- Hiding and destroying are different things and conflating them caused a
    -- visible flash. SetUnit loads a mesh asynchronously, so every destroy is
    -- followed by a blank interval before the model reappears.
    --
    -- Why the default is teardown, and why Hide() lives inside the guard rather
    -- than beside it:
    --
    -- Five call sites reach this function. Only onTooltipSetUnit passes a third
    -- argument, because only it can compare the incoming unit's GUID against the
    -- one already rendered. The other four -- itemToolTipHook, both non-unit
    -- branches of onTooltipShow, and a unit tooltip with no unit resolved -- have
    -- no unit knowledge at all, so they take the default.
    --
    -- Those four are non-unit tooltips. There is no unit behind an item, a spell,
    -- a quest or a map POI, so a character model is meaningless there and is
    -- destroyed rather than left resident and merely hidden. A hidden frame still
    -- carries a loaded PlayerModel, and retained state is how this addon has bled
    -- one tooltip's visuals onto another before.
    --
    -- The Hide() used to sit OUTSIDE the guard, which is what caused the reported
    -- blink and why preserving the model never fixed it. A GearScore item load
    -- completes asynchronously and re-enters the pipeline through
    -- TacoTip_GSCallback -> GameTooltip:SetUnit for the SAME character, so
    -- onTooltipSetUnit correctly asked to keep the model -- but the frame was
    -- hidden anyway and re-shown by the next ApplyTooltipAppearance. The mesh
    -- never changed; the frame vanished and came back once per item that finished
    -- loading. With a tooltip_delay or the border deferral in flight the re-show
    -- lands after the hide, which is why it read as a drop and a slide rather
    -- than a flicker.
    --
    -- So hide, destroy and drop the loaded-unit cache together, in one branch,
    -- and only when the model is genuinely being let go.
    if (tooltip.TacoTipPortrait3D) then
        -- THREE separate decisions, previously collapsed into keepModel:
        --   hide    -- must happen whenever the unit is not being re-rendered,
        --              or a previous character's portrait bleeds onto an item or
        --              spell tooltip;
        --   destroy -- only when the character demonstrably changed;
        --   anchor  -- must recompute whenever the tooltip may have moved,
        --              which includes every clear and hide.
        --
        -- keepModel   = same character, re-rendered: do nothing at all.
        -- retainModel = character unproven: hide and re-anchor, but keep the
        --               loaded model so an unchanged character does not pay an
        --               async reload (and a visible blank) for every render.
        -- neither      = genuine teardown.
        --
        -- Passing keepModel=true for a retain case was a real bug: it also
        -- suppressed state.portraitAnchored, freezing the portrait side, and
        -- three Classic assertions caught it.
        if (not keepModel) then
            tooltip.TacoTipPortrait3D:Hide()
            -- Hide() gets a counter of its own, here, on EVERY hide.
            --
            -- TT.ev.portraitHide sits inside the retainModel guard two lines
            -- below, so it counts teardowns and cannot see this call at all --
            -- and the two assertions named for the portrait blink read
            -- portraitHide, so moving this Hide() out of its guard left the whole
            -- suite green. A counter that cannot observe the call it is named
            -- after is worse than none: it reads as evidence and is not.
            TT.ev.portraitModelHidden = (TT.ev.portraitModelHidden or 0) + 1
            if (not retainModel) then
                TT.ev.portraitHide = (TT.ev.portraitHide or 0) + 1
                TT.ev.portraitDestroy = (TT.ev.portraitDestroy or 0) + 1
                -- WHICH path let go of the model. portraitHide alone could not
                -- distinguish them, and a wrong fix shipped on top of that: the
                -- unresolved-unit path was patched and the blink stayed, because
                -- a different call site was the one actually firing.
                if (reason) then
                    TT.ev.teardownBy = TT.ev.teardownBy or {}
                    TT.ev.teardownBy[reason] = (TT.ev.teardownBy[reason] or 0) + 1
                end
                if (tooltip.TacoTipPortrait3D.ClearModel) then
                    pcall(tooltip.TacoTipPortrait3D.ClearModel, tooltip.TacoTipPortrait3D)
                end
                if (tooltip.TacoTipPortrait3D.SetAlpha) then
                    tooltip.TacoTipPortrait3D:SetAlpha(1)
                end
                -- The loaded-unit cache MUST be dropped alongside the model.
                -- ApplyTooltipAppearance only reloads when the cached key
                -- differs from the incoming unit, so leaving it set here would
                -- make the next unit tooltip -- very often the SAME character,
                -- re-hovered after passing over something else -- skip the
                -- reload and show a permanently blank portrait.
                tooltip.TacoTipPortrait3D.tacoTipModelKey = nil
            end
        end
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

local function onTooltipSetUnit(tooltip, data)
    TT.ev.unitRender = (TT.ev.unitRender or 0) + 1
    -- Guarded: on some clients this method is a Lua shim that dereferences a
    -- namespace which may not be loaded, and an unguarded call here throws
    -- before any of the enhancement runs. The safeCall wrapping this function
    -- would swallow that error, silently dropping the entire unit tooltip.
    local name, tooltipUnit
    if (tooltip and type(tooltip.GetUnit) == "function") then
        local ok, retName, retUnit = pcall(tooltip.GetUnit, tooltip)
        if (ok) then
            name, tooltipUnit = retName, retUnit
        end
    end
    tooltipUnit = resolveTooltipUnit(tooltip, tooltipUnit)
    if (not tooltipUnit and data and data.guid) then
        tooltipUnit = resolveUnitTokenFromGUID(data.guid, tooltip)
    end
    name = name or (tooltipUnit and UnitName(tooltipUnit))
    if (not tooltipUnit) then
        -- The unit did not resolve. That is NOT the same as "the unit changed".
        --
        -- This path is reached whenever GetUnit and TooltipUtil both come up
        -- empty and the data.guid fallback misses -- and the fallback only knows
        -- "mouseover" and "target". Hovering a UNIT FRAME passes that frame's
        -- own unit (player, target), which is not necessarily the mouseover, so
        -- both comparisons miss and resolution fails on a completely ordinary
        -- hover of your own character. On Retail and WoW Forever the post-call
        -- runs before the client's own Show(), which is when those two reads are
        -- least reliable, so it failed on nearly every frame-hover render.
        --
        -- Calling clearTooltipVisuals with no keepModel defaults it to false,
        -- which hides the portrait, clears the PlayerModel and drops the loaded
        -- unit cache -- and the next render rebuilds all three. The tooltip text
        -- survived, because the already-rendered lines are not cleared here, so
        -- nothing looked broken except a portrait that blinked forever. Live
        -- counters read portrait hide 69 against unit renders 70.
        --
        -- So compare guids rather than guess a unit token from one: when
        -- data.guid matches the unit already rendered, nothing has changed and
        -- the model must survive. A genuinely different guid, or no guid at all,
        -- still tears down as before. Real recycle (OnTooltipCleared/OnHide)
        -- calls clearTooltipVisuals separately and is unaffected.
        --
        -- "no guid at all" is the case that had no home. On Retail and WoW
        -- Forever the postcall supplies data.guid, so "no guid" is rare. On the
        -- CLASSIC FAMILY it is EVERY render: the OnTooltipSetUnit script hook
        -- registered below wraps the handler as
        --   function(tooltip, ...) handleTooltipSetUnit(tooltip) end
        -- which drops the varargs, so `data` is nil and incomingGUID is nil
        -- here every single time. keepModel was therefore always false, so the
        -- retain path (hide, keep the mesh) was always taken -- and this
        -- function RETURNS without reaching TT:ApplyTooltipAppearance, which is
        -- the only place in the addon that calls portrait:Show() at :1209. The
        -- portrait was hidden and nothing in the pipeline could bring it back
        -- for the rest of that show.
        --
        -- The retain path is documented at clearTooltipVisuals as "hide and
        -- re-anchor, but keep the loaded model", written on the assumption that
        -- the caller goes on to re-show. This branch used to take it and then
        -- re-show two lines later -- a Hide()+Show() on a 3D model frame on every
        -- single render for a portrait that had not changed. It no longer takes it:
        -- an unproven change is a complete no-op, and a proven change tears the
        -- mesh down and leaves it down.
        local unresolvedState = getTooltipState(tooltip)
        local incomingGUID = data and data.guid or nil
        local changeUnproven = (incomingGUID == nil)
            or (incomingGUID == unresolvedState.currentUnitGUID)
        -- keepModel and retainModel both = changeUnproven, and the old call had
        -- both wrong in opposite directions:
        --
        --   unproven (no guid at all -- EVERY Classic render, because the
        --   OnTooltipSetUnit script hook drops the varargs -- or the same guid):
        --   the same character. keepModel=false hid the model, re-anchored it and
        --   relied on the re-show below to put it back; now it is a no-op.
        --
        --   proven different (a guid is present AND differs): the loaded mesh
        --   belongs to the wrong character and must go. keepModel=true means "do
        --   nothing at all", so the stale portrait stayed visible while the
        --   tooltip described someone else -- the exact bleed the contract above
        --   says must not happen. Now it is a full teardown, and nothing re-shows
        --   it: TT:ApplyTooltipAppearance is the only place that shows a portrait,
        --   and it is only reached for a resolved unit.
        clearTooltipVisuals(tooltip, nil, changeUnproven, "unresolved-unit", changeUnproven)
        return
    end

    local guid = (data and data.guid) or UnitGUID(tooltipUnit)
    -- Resolve the guid BEFORE clearing, so the clear can tell "this unit changed"
    -- from "this is the same unit being re-rendered because a GearScore item load
    -- completed". Only the former may tear down the 3D portrait.
    local previousGUID = getTooltipState(tooltip).currentUnitGUID
    -- keepModel: the ONLY call site that can prove the unit did not change.
    -- True here means "same character, GearScore item load completing, border
    -- refresh, re-render" -- all of which must be a complete no-op for the
    -- portrait, or it hides and re-shows on an unchanged model. False (the
    -- default, and what every other caller gets) tears it down, which is also
    -- what a genuinely different unit needs so the previous mesh cannot persist.
    clearTooltipVisuals(tooltip, nil, (previousGUID ~= nil and previousGUID == guid), "guid-change")
    getTooltipState(tooltip).currentUnitGUID = guid
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

    if (CI and guid and UnitIsPlayer(tooltipUnit) and not UnitIsUnit(tooltipUnit, "player")) then
        if (CI.DoInspect) then
            pcall(CI.DoInspect, CI, tooltipUnit)
        end
    end

    local wide_style = (TacoTipConfig.tip_style == 1 or ((TacoTipConfig.tip_style == 2 or TacoTipConfig.tip_style == 4) and IsShiftKeyDown()))
    local mini_style = (not wide_style and (TacoTipConfig.tip_style == 4 or TacoTipConfig.tip_style == 5))
    table.wipe(pooledTooltipText)
    table.wipe(pooledLinesToAdd)
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
                    addLineDouble(L["Target"] .. ":", L["Self"], NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g,
                        NORMAL_FONT_COLOR.b,
                        HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
                else
                    addLineSingle(L["Target"] .. ": |cFFFFFFFF" .. L["Self"] .. "|r", 1, 1, 1)
                end
            elseif (UnitIsUnit(unitTarget, "player")) then
                if (wide_style) then
                    addLineDouble(L["Target"] .. ":", L["You"], NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g,
                        NORMAL_FONT_COLOR.b, 1, 1, 0)
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
                    local colorCode = makeColorCode(classc.r, classc.g, classc.b)
                    if (wide_style) then
                        local targetLine = string.format("%s%s|r (%s)", colorCode, targetName, L["Player"])
                        addLineDouble(L["Target"] .. ":", targetLine, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g,
                            NORMAL_FONT_COLOR.b,
                            HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
                    else
                        addLineSingle(string.format("%s: %s%s|r (%s)", L["Target"], colorCode, targetName, L["Player"]),
                            1, 1, 1)
                    end
                else
                    if (wide_style) then
                        addLineDouble(L["Target"] .. ":", targetName .. " (" .. L["Player"] .. ")", NORMAL_FONT_COLOR.r,
                            NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g,
                            HIGHLIGHT_FONT_COLOR.b)
                    else
                        addLineSingle(L["Target"] .. ": |cFFFFFFFF" .. targetName .. " (" .. L["Player"] .. ")|r", 1, 1,
                            1)
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
                    addLineDouble(L["Target"] .. ":", targetName, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g,
                        NORMAL_FONT_COLOR.b,
                        HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
                else
                    addLineSingle(L["Target"] .. ": |cFFFFFFFF" .. targetName .. "|r", 1, 1, 1)
                end
            end
        else
            local inSameMap = true
            local inGroup = (type(IsInGroup) == "function" and IsInGroup())
            if (inGroup and (((type(IsInRaid) == "function" and IsInRaid() and UnitInRaid and UnitInRaid(tooltipUnit))) or (UnitInParty and UnitInParty(tooltipUnit)))) then
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
                    addLineDouble(L["Target"] .. ":", L["None"], NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g,
                        NORMAL_FONT_COLOR.b,
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

        local guildName, guildRankName
        if (GetGuildInfo) then
            guildName, guildRankName = GetGuildInfo(tooltipUnit)
        end
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

        -- Localized label. Every other unit-tooltip label below already resolves
        -- through TACOTIP_LOCALE (Target, Guild, Rank, Talents, Pet, Player...);
        -- this one was a hardcoded "|cFFFFFFFFLevel|r", so it rendered in English
        -- on every client even though ["Level"] is translated in all 11 locales.
        -- The `or "Level"` fallback keeps the line safe if a future locale file
        -- omits the key before ApplyLocale's merge can backfill it.
        local levelLabel = L["Level"] or "Level"
        local levelLine
        if (displayRace and displayClass) then
            levelLine = string.format("|cFFFFFFFF%s|r %s %s %s", levelLabel, levelStr, displayRace, displayClass)
        elseif (displayClass) then
            levelLine = string.format("|cFFFFFFFF%s|r %s %s", levelLabel, levelStr, displayClass)
        else
            levelLine = string.format("|cFFFFFFFF%s|r %s", levelLabel, levelStr)
        end

        table.wipe(pooledPlayerText)
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
            -- Ownership proof for the clears above: without it they blank line
            -- 2/3 unconditionally and destroy any other addon's line that has
            -- shifted into that slot.
            tooltip.TacoTipGuildLineText = newText[2]
            tooltip.TacoTipLevelColorLineText = levelLine
        else
            newText[2] = levelLine
            tooltip.TacoTipGuildLineIndex = nil
            tooltip.TacoTipLevelColorLineIndex = 2
            tooltip.TacoTipLevelColorLineText = levelLine
        end

        text = newText

        if (TacoTipConfig.show_realm and UnitIsPlayer(tooltipUnit)
                and type(_G.UnitIsSameServer) == "function" and not UnitIsSameServer(tooltipUnit)) then
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
                    addLineDouble((L["Honor Rank"] or "Honor Rank") .. ":", pvpName, NORMAL_FONT_COLOR.r,
                        NORMAL_FONT_COLOR.g,
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
        if (TacoTipConfig.show_role_icon and UnitIsPlayer(tooltipUnit) and type(IsInGroup) == "function" and IsInGroup()) then
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
                -- Clear the overlay icon FIRST, so any path through this block
                -- that does not end up setting a real icon leaves it hidden.
                --
                -- Previously the only clear sat in the `else` branch (when the
                -- active talent group is neither 1 nor 2), so a unit with no
                -- talent data -- spec1 and spec2 both nil, which is the normal
                -- state for a player you have never inspected -- never cleared
                -- it, and the PREVIOUS character's icon stayed on screen. That
                -- is the stray icon, and it is why the wrong portrait survived a
                -- hover rather than simply being absent.
                --
                -- Clears any overlay left over from a previous render. The icon is
                -- now inlined on every client, so an overlay should never exist --
                -- this is belt-and-braces, and is what a tooltip rendered by an
                -- older build would need.
                applySpecializationIcon(tooltip, nil)
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
                -- Per spec group, so the two dual-spec lines do not both end up
                -- wearing group 1's name.
                local name1 = CI:GetLocalizedSpecName(guid, 1)
                local icon1 = CI:GetLocalizedSpecIcon(guid, 1)
                local name2 = CI:GetLocalizedSpecName(guid, 2)
                local icon2 = CI:GetLocalizedSpecIcon(guid, 2)

                -- Specialization icons are INLINED on every client, including
                -- Retail and WoW Forever. A separate Texture overlay used to be
                -- drawn outside the tooltip's left edge on those two clients as
                -- well, so the same specialization was rendered twice: once as the
                -- |T escape inside formatSpecializationText, once as the overlay.
                -- The overlay was introduced on the belief that a |T escape cannot
                -- render a fileID, but formatSpecializationText passes the value
                -- through tostring(), and |T accepts a fileID in that form -- the
                -- same correction the Classic path needed, and the inline icon
                -- demonstrably renders on modern.
                --
                -- The applySpecializationIcon(tooltip, nil) calls are kept: a
                -- no-op on a tooltip that never had an overlay, and a clear on one
                -- that somehow does.
                local active = CI:GetActiveTalentGroup(guid) or 1

                if (active == 2) then
                    if (spec2) then
                        local specText = formatSpecializationText(class, spec2, y1, y2, y3, nil, name2, icon2)
                        -- overlay removed: the icon is inlined by formatSpecializationText above
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
                        local specText = formatSpecializationText(class, spec1, x1, x2, x3, true, name1, icon1)
                        if (wide_style) then
                            addLineDouble(" ", specText, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, 1,
                                1, 1)
                        else
                            addLineSingle(string.format("|c00000000%s: |r%s", L["Talents"], specText), 1, 1, 1)
                        end
                    end
                elseif (active == 1) then
                    if (spec1) then
                        local specText = formatSpecializationText(class, spec1, x1, x2, x3, nil, name1, icon1)
                        -- overlay removed: the icon is inlined by formatSpecializationText above
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
                        local specText = formatSpecializationText(class, spec2, y1, y2, y3, true, name2, icon2)
                        if (wide_style) then
                            addLineDouble(" ", specText, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, 1,
                                1, 1)
                        else
                            addLineSingle(string.format("|c00000000%s: |r%s", L["Talents"], specText), 1, 1, 1)
                        end
                    end
                else
                    applySpecializationIcon(tooltip, nil)
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
                        local gsColor = makeColorCode(r, g, b)
                        miniText = string.format("%sGS: %s  L: %s|r  ", gsColor, gearscore, avg_ilvl)
                    else
                        local gsColor = makeColorCode(r, g, b)
                        addLineSingle(string.format("GearScore: %s%s|r", gsColor, gearscore), 1, 1, 1)
                        if (avg_ilvl and avg_ilvl > 0) then
                            if (TacoTipConfig.show_ilvl_inline) then
                                text[1] = text[1] .. string.format(" %s[%s]|r", gsColor, avg_ilvl)
                            else
                                addLineSingle(string.format("iLvl: %s%s|r", gsColor, avg_ilvl), 1, 1, 1)
                            end
                        end
                    end
                end
            end
            if (isPawnLoaded and TT_PAWN and TT_PAWN.GetScore and TacoTipConfig.show_pawn_player) then
                local pawnScore, specName, specColor = TT_PAWN:GetScore(guid, not TacoTipConfig.show_gs_player)
                if (pawnScore > 0) then
                    if (wide_style) then
                        addLineDouble(string.format("Pawn: %s%.2f|r", specColor, pawnScore),
                            string.format("%s(%s)|r", specColor,
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
            if (TacoTipConfig.show_achievement_points) then
                local achi_pts
                if (CI and CI.GetTotalAchievementPoints) then
                    achi_pts = CI:GetTotalAchievementPoints(guid)
                end
                if (not achi_pts and GetTotalAchievementPoints and guid == UnitGUID("player")) then
                    achi_pts = GetTotalAchievementPoints()
                end
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
            -- Compare the line we anchored last time rather than re-asserting
            -- unconditionally: both are pooled FontStrings, so on a re-render of
            -- the same shape they are the same two objects and the point is
            -- already exactly right. Comparing the anchor object (not a "done"
            -- flag) is what makes this correct when n moves -- a different pair
            -- is a different anchor and has to be written.
            --
            -- GetNumPoints/GetPoint would read the anchor back more directly,
            -- but a FontString is a Region and has neither on a real client, so
            -- that check would hold in the harness and do nothing in game.
            if (nextLeft._tacoTipWideAnchor ~= anchorLine) then
                nextLeft:SetPoint("TOP", anchorLine, "BOTTOM", 0, -2)
                nextLeft._tacoTipWideAnchor = anchorLine
            end
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
            rawset(TacoTipPowerBar, "Update", function(self, u)
                if (TacoTipConfig.show_power_bar) then
                    local unit = u or resolveTooltipUnit(GameTooltip)
                    if (unit) then
                        local _, power = UnitPowerType(unit)
                        -- No throwaway table. This runs on UNIT_POWER_UPDATE,
                        -- UNIT_MAXPOWER and UNIT_DISPLAYPOWER as well as once
                        -- per render, and `PowerBarColor[power] or {}` allocated
                        -- a fresh five-field table on every one of those for any
                        -- power token PowerBarColor does not key, then dropped
                        -- it on the next line. It was the only bare table literal
                        -- left in a pipeline that is otherwise built on pooled
                        -- buffers, and it sat on the hottest path in the render.
                        --
                        -- A module-level constant is the right shape: the colour
                        -- is read-only, so one shared table is safe to hand to
                        -- SetStatusBarColor, and the fallback (0, 0, 1) is
                        -- preserved exactly -- including the `or 1` on blue,
                        -- which is what made an unkeyed power type render blue
                        -- rather than black.
                        local color = (PowerBarColor and PowerBarColor[power]) or FALLBACK_POWER_COLOR
                        self:SetStatusBarColor(color.r or 0, color.g or 0, color.b or 1);
                        self:SetMinMaxValues(0, UnitPowerMax(unit))
                        self:SetValue(UnitPower(unit))
                    else
                        self:Hide()
                        stopPowerBarTicker()
                    end
                end
            end)

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
            -- Re-anchoring is two SetPoint calls, and this runs on every render.
            -- The anchors only move when the HP bar's own presence flips, so the
            -- offset is remembered on the bar and compared, the same shape as
            -- the tooltip's own anchors a few lines below.
            local barOffsetY = (TacoTipConfig.show_hp_bar and 9) or -1
            if (TacoTipPowerBar._tacoTipAnchorY ~= barOffsetY) then
                TacoTipPowerBar:SetPoint("TOPLEFT", GameTooltip, "BOTTOMLEFT", 2, barOffsetY)
                TacoTipPowerBar:SetPoint("TOPRIGHT", GameTooltip, "BOTTOMRIGHT", -2, barOffsetY)
                TacoTipPowerBar._tacoTipAnchorY = barOffsetY
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
            -- SetPadding re-lays out the tooltip, and this ran on every render
            -- with only `tooltip.SetPadding` as a guard -- i.e. never skipped.
            -- The value is constant, so comparing it costs nothing and the
            -- layout pass happens once per session instead of once per hover.
            if (tooltip.SetPadding) then
                if (tooltip._tacoTipPadding ~= 10) then
                    tooltip:SetPadding(0, 10, 0, 0)
                    tooltip._tacoTipPadding = 10
                end
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

    -- Unconditional in the old code: not even a capability check, let alone a
    -- value comparison, on a path that runs at the end of every render.
    if (tooltip.SetClampRectInsets) then
        if (tooltip._tacoTipClampBottom ~= 15) then
            tooltip:SetClampRectInsets(0, 0, 15, 15)
            tooltip._tacoTipClampBottom = 15
        end
    end

    if (tooltip.SetMinimumWidth) then
        local currentMin = (tooltip.GetMinimumWidth and tooltip:GetMinimumWidth()) or -1
        if (currentMin ~= 0) then
            tooltip:SetMinimumWidth(0)
        end
    end


    applyTooltipMaxWidth(tooltip)

    TT:ApplyTooltipAppearance(tooltip, tooltipUnit)
end

-- Tells whether a tooltip actually runs the modern data pipeline, as opposed to
-- merely having the processor globals defined.
--
-- TBC Anniversary and WotLK Titanforge BOTH define TooltipDataProcessor and
-- Enum.TooltipDataType (Blizzard_SharedXMLGame.toc excludes only "vanilla"), but
-- their GameTooltip mixes in GameTooltipMixin alone -- never
-- TooltipDataHandlerMixin. ProcessTooltipPostCalls is a file-local in
-- TooltipDataHandler.lua reached only through TooltipDataHandlerMixin:ProcessInfo,
-- so on those clients an AddTooltipPostCall registration succeeds and the callback
-- is never invoked. Testing for the mixin's own methods (:408 GetPrimaryTooltipData,
-- :418 IsTooltipType) is the only presence test that actually discriminates.
stage("unit-hook")

local function dataPipelineActive(tooltip)
    return (tooltip
        and type(tooltip.IsTooltipType) == "function"
        and type(tooltip.GetPrimaryTooltipData) == "function"
        and TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
        and Enum and Enum.TooltipDataType)
end

local function handleTooltipSetUnit(tooltip, data)
    cancelDelayedTooltip(tooltip)
    local delay = TacoTipConfig.tooltip_delay or 0
    if (delay > 0 and tooltip == GameTooltip and not InCombatLockdown() and type(NewTimer) == "function") then
        local state = getTooltipState(tooltip)
        local timer
        timer = NewTimer(delay, function()
            if (state.delayedTooltipTimer == timer) then
                state.delayedTooltipTimer = nil
            end
            safeCall(onTooltipSetUnit, tooltip, data)
        end)
        state.delayedTooltipTimer = timer
    else
        safeCall(onTooltipSetUnit, tooltip, data)
    end
end

-- Register BOTH paths. On a correctly-detected client exactly one fires; on a
-- client where the probe is wrong, having both registered is strictly better than
-- having registered only the one that never runs. handleTooltipSetUnit cancels
-- any pending tooltip work first, so a duplicate delivery is a no-op.
--
-- EVERY HookScript below is guarded with HasScript, and that is load-critical, not
-- defensive tidiness. HookScript raises
--   bad argument #2 to 'HookScript' (Usage: self:HookScript(scriptTypeName, script))
-- when the frame does not already declare that script. Retail and WoW Forever
-- changed their tooltip template: SharedTooltipTemplate declares only OnShow,
-- OnHide, OnLoad, OnTooltipSetDefaultAnchor and OnTooltipCleared. The Classic
-- template additionally declares OnTooltipSetUnit, OnTooltipSetItem and
-- OnTooltipSetSpell. Hooking one of those unconditionally therefore threw at FILE
-- SCOPE on Retail, which aborted the remainder of main.lua -- no item hooks, no
-- visual clearing, no anchor hook, no overlays and no tooltip mover, while
-- options.lua (loaded earlier) kept working and the mover reported itself "not
-- ready". That was the whole Retail failure.
-- Hooks `scriptName` on every frame in `frames` that declares it, and returns a
-- comma-separated list of "<label>" for each frame actually hooked, or nil when
-- none were.
--
-- EVERY frame in the list is attempted. An earlier success must never stop the
-- rest: the first version of this helper used a short-circuiting `or` chain, so
-- on the Classic family -- where GameTooltip is first and does declare
-- OnTooltipSetItem -- ShoppingTooltip1, ShoppingTooltip2 and ItemRefTooltip
-- were silently never hooked. That is a regression on the three clients that
-- previously worked, traded for a fix on the two that did not.
local function hookTooltipScripts(scriptName, handler, frames)
    local hooked = {}
    for i = 1, #frames do
        local frame, label = frames[i][1], frames[i][2]
        if (frame and type(frame) == "table" and frame.HasScript
                and frame:HasScript(scriptName)) then
            frame:HookScript(scriptName, handler)
            hooked[#hooked + 1] = label
        end
    end
    if (#hooked == 0) then
        return nil
    end
    return table.concat(hooked, ",")
end
TT.HookedTooltipScripts = TT.HookedTooltipScripts or {}

if (dataPipelineActive(GameTooltip)) then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, handleTooltipSetUnit)
    TT.HookedTooltipScripts.Unit = "postcall"
end
TT.HookedTooltipScripts.Unit = TT.HookedTooltipScripts.Unit
    or hookTooltipScripts("OnTooltipSetUnit",
        function(tooltip, ...)
            handleTooltipSetUnit(tooltip)
        end,
        { { GameTooltip, "GameTooltip" } })

local function resolveTooltipItem(tooltip, data)
    if (tooltip and tooltip.GetItem) then
        local ok, _, itemLink = pcall(tooltip.GetItem, tooltip)
        if (ok and itemLink) then return itemLink end
    end
    if (TooltipUtil and TooltipUtil.GetDisplayedItem and tooltip) then
        local ok, _, dispLink = pcall(TooltipUtil.GetDisplayedItem, tooltip)
        if (ok and dispLink) then return dispLink end
    end
    if (data and type(data) == "table") then
        -- `hyperlink` is what the post-call actually supplies for an item, so
        -- this is the branch that fires in practice on Retail / WoW Forever.
        if (data.hyperlink) then return data.hyperlink end
        -- GetItemLinkByGUID is documented only on Forever and Retail; on the
        -- Classic branches this whole arm is skipped.
        if (data.guid and C_Item and C_Item.GetItemLinkByGUID) then
            local ok, link = pcall(C_Item.GetItemLinkByGUID, data.guid)
            if (ok and link) then return link end
        end
        -- There is deliberately no itemID -> link fallback. C_Item.GetItemLink
        -- takes an ItemLocation, not an itemID, and no documented C_Item
        -- function accepts a bare itemID. An earlier `C_Item.GetItemLinkByID`
        -- arm looked plausible but has zero call sites on any of the five
        -- clients, so it was dead code on every one of them.
    end
    return nil
end

local function itemToolTipHook(self, data)
    clearTooltipVisuals(self, nil, nil, "item")

    local itemLink = resolveTooltipItem(self, data)
    if (itemLink) then
        getTooltipState(self).currentItemLink = itemLink
    end
    -- Both item features off: skip the IsEquippableItem/GetItemInfo work
    -- entirely instead of fetching data no line will ever display.
    --
    -- Prefer the C_Item namespace over the bare global: the global is created by
    -- Blizzard_DeprecatedItemScript, which early-returns unless the
    -- loadDeprecationFallbacks CVar is set. Calling it unguarded raises on every
    -- item hover when that CVar is off, and safeItemToolTipHook would swallow
    -- the error into geterrorhandler, killing the iLvl/GearScore lines.
    local IsEquippableItem = (_G.C_Item and _G.C_Item.IsEquippableItem) or _G.IsEquippableItem
    if (itemLink and (TacoTipConfig.show_item_level or TacoTipConfig.show_gs_items)
            and type(IsEquippableItem) == "function" and IsEquippableItem(itemLink)) then
        -- Single GetItemInfo fetch per hover, shared by the ilvl line,
        -- GearScore and HunterScore below (F3 hot-path fix). If Blizzard
        -- has not cached the item yet, request its data and re-render this
        -- exact tooltip when the load lands rather than leaving it blank.
        --
        -- Resolved namespace-first and nil-guarded, matching gearscore.lua. Both
        -- the bare global and C_Item.GetItemInfo are still documented on the live
        -- branch, so this is hardening rather than a fix: a client exposing
        -- neither now degrades to an empty result instead of raising inside
        -- safeCall, which would abort the rest of this hook -- the item iLvl,
        -- GearScore and HunterScore lines and everything after them.
        local getItemInfoFn = (_G.C_Item and _G.C_Item.GetItemInfo) or _G.GetItemInfo
        local itemInfo = getItemInfoFn and { getItemInfoFn(itemLink) } or {}
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
    -- The width cap belongs here too. It had exactly one call site, inside
    -- onTooltipSetUnit, so the item path applied the font, the backdrop and the
    -- border overlay but not the cap -- and the item tooltip is the one that
    -- reliably carries a line long enough to need it. Called after the lines
    -- above are in place, because the cap walks the pooled lines by index and
    -- the iLvl / GearScore / HunterScore lines were added above.
    applyTooltipMaxWidth(self)
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
        -- RequestLoadItemDataByID only exists as C_Item.RequestLoadItemDataByID
        -- on all five clients -- there is no bare global (verified against
        -- Blizzard_ObjectAPI on classic_era/anniversary/titanforge/forever/live).
        -- The file-scope local at the top of this file already resolves the
        -- namespaced form; reading a bare global here made this branch no-op.
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
    -- Prefer the cancelable form. ItemMixin provides it on all five clients
    -- (Blizzard_ObjectAPI/.../Item.lua), but fall back to the fire-and-forget
    -- ContinueOnItemLoad rather than dropping the repaint entirely if some
    -- object only implements the non-cancelable variant.
    if (item.ContinueWithCancelOnItemLoad) then
        local callbackOk, canceler = pcall(item.ContinueWithCancelOnItemLoad, item, callback)
        if (callbackOk and type(canceler) == "function") then
            cancel = canceler
            state.itemLoadCancel = cancel
        end
    elseif (item.ContinueOnItemLoad) then
        pcall(item.ContinueOnItemLoad, item, callback)
    end
end

-- Same dual registration as the unit hook above; see dataPipelineActive for why
-- the presence of TooltipDataProcessor proves nothing on TBC/Titanforge.
if (dataPipelineActive(GameTooltip)) then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, safeItemToolTipHook)
    TT.HookedTooltipScripts.Item = "postcall"
end
TT.HookedTooltipScripts.Item = TT.HookedTooltipScripts.Item
    or hookTooltipScripts("OnTooltipSetItem", safeItemToolTipHook, {
        { GameTooltip,      "GameTooltip" },
        { ShoppingTooltip1, "ShoppingTooltip1" },
        { ShoppingTooltip2, "ShoppingTooltip2" },
        { ItemRefTooltip,   "ItemRefTooltip" },
    })

-- Re-apply the class-tinted border whenever the tooltip shows, in case a
-- re-show skipped OnTooltipSetUnit (e.g. anchor re-fire with cached text)
-- and left SetBackdrop's default 0.5/0.5/0.5 gray border in place. Deferred
-- to the next frame so it runs AFTER Blizzard finishes its own internal
-- OnShow/backdrop setup - otherwise Blizzard's subsequent SetBackdrop on
-- the same frame resets the border back to default gray.
stage("item-hooks")

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
    local isUnit = false
    if (tooltip) then
        if (tooltip.IsTooltipType and Enum and Enum.TooltipDataType and tooltip:IsTooltipType(Enum.TooltipDataType.Unit)) then
            isUnit = true
        end
    end
    local unit = resolveTooltipUnit(tooltip)
    if (unit and UnitExists and UnitExists(unit)) then
        isUnit = true
    end

    if (not isUnit) then
        -- F1: When the tooltip shows for non-unit content (items, spells, UI
        -- elements, options hover-help), the portrait from a previous unit
        -- display must be cleared. OnTooltipCleared may not have fired on
        -- this transition path (e.g. ClearLines + Show in showHoverTooltip).
        clearTooltipVisuals(tooltip, preservePendingItem, nil, "show-no-class-cache", true)
        return
    end

    if (not TacoTipConfig.tooltip_border_use_class and not TacoTipConfig.color_class) then
        return
    end

    -- Only apply class-tinted borders when the tooltip actually shows a
    -- player unit.
    if (not unit or not UnitIsPlayer(unit)) then
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
    if (type(NewTimer) == "function") then
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
end

stage("tooltip-hooks")

local function isUnitFramePeriodicUpdate(tooltip)
    if (not tooltip) then
        return false
    end
    local owner = tooltip.GetOwner and tooltip:GetOwner()
    if (not owner) then
        return false
    end
    local state = getTooltipState(tooltip)
    local curGUID = state and state.currentUnitGUID
    if (not curGUID) then
        return false
    end
    if (owner.UpdateTooltip and owner.unit and UnitExists and UnitExists(owner.unit)) then
        local uGUID = UnitGUID(owner.unit)
        if (uGUID and uGUID == curGUID) then
            return true
        end
    end
    return false
end

local function registerTooltipVisualClearing(tooltipFrame)
    if (not tooltipFrame or type(tooltipFrame) ~= "table" or not tooltipFrame.HasScript) then
        return
    end
    if (tooltipFrame:HasScript("OnTooltipCleared")) then
        tooltipFrame:HookScript("OnTooltipCleared", function(tFrame)
            if (isUnitFramePeriodicUpdate(tFrame)) then
                return
            end
            cancelDelayedTooltip(tFrame)
            return safeCall(clearTooltipVisuals, tFrame, nil, nil, "cleared", true)
        end)
    end
    if (tooltipFrame:HasScript("OnShow")) then
        tooltipFrame:HookScript("OnShow", function(tFrame, ...)
            return safeCall(onTooltipShow, tFrame, ...)
        end)
    end
    if (tooltipFrame:HasScript("OnHide")) then
        tooltipFrame:HookScript("OnHide", function(tFrame)
            if (isUnitFramePeriodicUpdate(tFrame)) then
                return
            end
            cancelDelayedTooltip(tFrame)
            -- Same reasoning as OnTooltipCleared: a hide is not proof the
            -- character changed, and the model is already hidden.
            return safeCall(clearTooltipVisuals, tFrame, nil, nil, "hide", true)
        end)
    end
end

-- pairs, not ipairs: this table contains guaranteed nils (WorldMapTooltip,
-- WorldMapCompareTooltip1/2 and SmallTextTooltip do not exist on Retail 12.1,
-- and WorldMapTooltip does not exist on some other clients). ipairs stops at the
-- first hole, so every frame after the first nil silently loses its
-- OnTooltipCleared/OnShow/OnHide hooks and therefore its clearTooltipVisuals
-- call -- which is exactly the class-border / portrait / power-bar bleed-through
-- that clearTooltipVisuals exists to prevent.
stage("visual-clearing")

for _, ttFrame in pairs({
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
--
-- Guarded for the same reason as the unit and item hooks: Retail's tooltip
-- template no longer declares OnTooltipSetSpell, so an unguarded hook here
-- aborts the rest of main.lua at file scope.
hookTooltipScripts("OnTooltipSetSpell", function(tooltip)
    return safeCall(clearTooltipVisuals, tooltip)
end, { { GameTooltip, "GameTooltip" } })


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

stage("anchor-hook")

local function isUnitHoverTarget(tooltip, parent)
    if (parent == UIParent or parent == nil or parent == WorldFrame) then
        return true
    end
    if (parent and (parent.unit or (type(parent.GetAttribute) == "function" and parent:GetAttribute("unit")))) then
        return true
    end
    local owner = tooltip and tooltip.GetOwner and tooltip:GetOwner()
    if (owner and (owner.unit or (type(owner.GetAttribute) == "function" and owner:GetAttribute("unit")))) then
        return true
    end
    if (tooltip) then
        if (tooltip.IsTooltipType and Enum and Enum.TooltipDataType and tooltip:IsTooltipType(Enum.TooltipDataType.Unit)) then
            return true
        end
        if (tooltip.GetUnit) then
            local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
            if (ok and unit and type(UnitExists) == "function" and UnitExists(unit)) then
                return true
            end
        end
        if (resolveTooltipUnit and resolveTooltipUnit(tooltip)) then
            return true
        end
    end
    local focus
    if (TT and type(TT.GetMouseFocus) == "function") then
        focus = TT:GetMouseFocus()
    elseif (type(GetMouseFoci) == "function") then
        local foci = GetMouseFoci()
        focus = foci and foci[1]
    elseif (type(GetMouseFocus) == "function") then
        focus = GetMouseFocus()
    end
    if (focus == WorldFrame and type(UnitExists) == "function" and UnitExists("mouseover")) then
        return true
    end
    return false
end

local function onGameTooltipSetDefaultAnchor(tooltip, parent)
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
    if (not isUnitHoverTarget(tooltip, parent)) then
        return
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
end

-- Anchoring the tooltip for spells and actions is a pure optimisation: it only
-- chooses which side the tooltip opens on. hooksecurefunc THROWS when its target
-- global does not exist, and this call sits at file scope, so an unguarded target
-- that is absent on some build would abort the rest of main.lua -- no tooltip
-- hooks, no mover, no overlays -- while the options frame, loaded earlier, kept
-- working. GameTooltip_SetDefaultAnchor comes from Blizzard_SharedXML, which is
-- not LoadOnDemand, so it is present on all five supported clients; guarding it
-- costs one branch and not guarding it costs the whole addon.
if (type(_G.GameTooltip_SetDefaultAnchor) == "function") then
    hooksecurefunc("GameTooltip_SetDefaultAnchor", onGameTooltipSetDefaultAnchor)
    TT.HookedDefaultAnchor = true
else
    -- Only the spell-anchor side selection is lost. Every other anchoring path
    -- below is unaffected, so a failure here degrades rather than disables.
    TT.HookedDefaultAnchor = false
end

local function getDefaultTooltipMoverPosition()
    -- BOTTOMRIGHT = bottom-right corner of the screen.
    -- This is the STARTING position of the green dot ONLY.
    -- It is independent of custom_anchor (which controls where the
    -- tooltip appears relative to the dot, not where the dot sits).
    --
    -- Do NOT change this to suit the handle's placement. The handle IS the
    -- tooltip's anchor point, so this value decides where the TOOLTIP sits; an
    -- earlier attempt to move the handle to the bottom-left silently relocated
    -- every unconfigured user's tooltip to the left of the screen.
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

stage("status-bar")

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

-- Host frame for the character-pane GearScore / iLvl font strings.
--
-- The Classic family nests a PlayerModel named CharacterModelFrame inside
-- PaperDollFrame (Blizzard_CharacterFrame/{Vanilla,TBC,Wrath}/PaperDollFrame.xml).
-- Retail removed that model frame and has no equivalent, keeping only
-- PaperDollFrame (Blizzard_UIPanels_Game/Mainline/PaperDollFrame.xml), so
-- indexing the missing global raised
--   attempt to index global 'CharacterModelFrame' (a nil value)
-- on every character-pane refresh -- including the one the options UI triggers,
-- which is why opening the tooltip mover threw.
--
-- Classic behaviour is unchanged: CharacterModelFrame is preferred and exists
-- there, so the font strings keep the same parent and the same positions. On
-- Retail the strings are parented to PaperDollFrame instead, so the feature
-- works rather than silently disappearing.
local characterFrameHost = _G.CharacterModelFrame or _G.PaperDollFrame

-- Returns true when the font strings exist. Marks itself done either way, so a
-- client with no character paper doll is not retried on every refresh.
function TT:InitCharacterFrame()
    TT.InitCharacterFrame = nil
    if (not characterFrameHost) then
        return false
    end
    characterFrameHost:CreateFontString("PersonalGearScore")
    PersonalGearScore:SetFont(L["CHARACTER_FRAME_GS_VALUE_FONT"], L["CHARACTER_FRAME_GS_VALUE_FONT_SIZE"])
    PersonalGearScore:SetText("0")
    rawset(PersonalGearScore, "RefreshPosition", function()
        PersonalGearScore:SetPoint("BOTTOMLEFT", PaperDollFrame, "BOTTOMLEFT",
            L["CHARACTER_FRAME_GS_VALUE_XPOS"] + (TacoTipConfig.character_gs_offset_x or 0),
            L["CHARACTER_FRAME_GS_VALUE_YPOS"] + (TacoTipConfig.character_gs_offset_y or 0))
    end)
    PersonalGearScore:RefreshPosition()

    characterFrameHost:CreateFontString("PersonalGearScoreText")
    PersonalGearScoreText:SetFont(L["CHARACTER_FRAME_GS_TITLE_FONT"], L["CHARACTER_FRAME_GS_TITLE_FONT_SIZE"])
    PersonalGearScoreText:SetText("GearScore")
    rawset(PersonalGearScoreText, "RefreshPosition", function()
        PersonalGearScoreText:SetPoint("BOTTOMLEFT", PaperDollFrame, "BOTTOMLEFT",
            L["CHARACTER_FRAME_GS_TITLE_XPOS"] + (TacoTipConfig.character_gs_offset_x or 0),
            L["CHARACTER_FRAME_GS_TITLE_YPOS"] + (TacoTipConfig.character_gs_offset_y or 0))
    end)
    PersonalGearScoreText:RefreshPosition()

    characterFrameHost:CreateFontString("PersonalAvgItemLvl")
    PersonalAvgItemLvl:SetFont(L["CHARACTER_FRAME_ILVL_VALUE_FONT"], L["CHARACTER_FRAME_ILVL_VALUE_FONT_SIZE"])
    PersonalAvgItemLvl:SetText("0")
    rawset(PersonalAvgItemLvl, "RefreshPosition", function()
        PersonalAvgItemLvl:SetPoint("BOTTOMLEFT", PaperDollFrame, "BOTTOMLEFT",
            L["CHARACTER_FRAME_ILVL_VALUE_XPOS"] + (TacoTipConfig.character_ilvl_offset_x or 0),
            L["CHARACTER_FRAME_ILVL_VALUE_YPOS"] + (TacoTipConfig.character_ilvl_offset_y or 0))
    end)
    PersonalAvgItemLvl:RefreshPosition()

    characterFrameHost:CreateFontString("PersonalAvgItemLvlText")
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
        -- InitCharacterFrame marks itself done, so the nil assignment here is
        -- redundant. It stays out of this path deliberately: on a client with no
        -- character paper doll there are no font strings to update, and running
        -- on would index four nil globals on every refresh.
        if (not TT:InitCharacterFrame()) then
            return
        end
    end
    if (not _G.PersonalGearScore) then
        return
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

-- Blizzard's own InspectGuildFrame has an unguarded nil. Verified on
-- origin/live, Interface/AddOns/Blizzard_InspectUI/Mainline/InspectGuildFrame.lua:
--
--   local guildPoints, guildNumMembers, guildName, guildRealmName =
--       C_PaperDollInfo.GetInspectGuildInfo(InspectFrame.unit)
--   InspectGuildFrame.guildRealmName:SetFormattedText(INSPECT_GUILD_REALM, guildRealmName)
--   if (guildFactionName and guildNumMembers) then   <-- these two ARE guarded
--
-- guildRealmName is nil for any player with no guild, and SetFormattedText
-- raises on a nil argument, so the frame dies mid-update and the inspected
-- player renders blank. This is a Blizzard defect, not ours -- vanilla Retail
-- does it too -- but the addon inspects on hover, so it fires far more often
-- than a player would otherwise meet it.
--
-- Only the modern global form is wrapped. The Classic clients reach the same
-- frame through the Cata branch, whose Update guards every value it formats,
-- so there is nothing to fix there and nothing here should pretend otherwise.
local function guardBlizzardInspectGuildFrame()
    local update = rawget(_G, "InspectGuildFrame_Update")
    if (type(update) ~= "function") then return false end
    if (rawget(_G, "_tacoTipInspectGuildGuarded")) then return true end
    rawset(_G, "_tacoTipInspectGuildGuarded", true)
    rawset(_G, "InspectGuildFrame_Update", function(...)
        -- Deliberately narrow: the frame's own guild block is the only thing
        -- that throws, and it throwing must not cost the player the rest of
        -- their inspect.
        pcall(update, ...)
    end)
    return true
end

function TT:InitInspectFrame()
    guardBlizzardInspectGuildFrame()
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
        if (frames and frames[1]) then
            return frames[1]
        end
        return WorldFrame
    end
    return GetMouseFocus()
end

-- Human-readable load report, bound to /tacotip diag.
--
-- The point is to make a partial load diagnosable without a bug reporter. If
-- LOAD_OK is false, LOAD_STAGE names the last point main.lua reached, which is
-- the region containing the error; if LOAD_OK is true but something is still
-- inert, the per-item lines below say which.
-- ============================================================================
-- Event counters, for /tt diag.
--
-- The 3D portrait flickered on Retail and WoW Forever and not on the Classic
-- family, only while hovering the player's own character frame. Nothing readable
-- in the source settles it, because every portrait call site is client-agnostic
-- and the candidates are about how OFTEN things run, not what runs. Static
-- reading cannot observe call frequency, so this counts instead.
--
-- Design constraints:
--   * A plain table, not a table with metatable __index -- this file runs on
--     clients as old as 1.15 and the whole point is to avoid raising on the way
--     to a report the player needs.
--   * Incremented with an inline `or 0`, so no per-call function call on a path
--     that fires many times per second.
--   * Never reset, so the numbers mean "since load", which is exactly the window
--     the user needs. Stating the window in the label avoids having to explain it.
--   * Reading them is read-only and cannot perturb what is being measured.
-- ============================================================================
TT.ev = TT.ev or {}

-- Reports what the counters mean and how to read them. Kept separate from
-- PrintDiagnostics so the report stays a report and this stays a policy.
local function reportEventCounters(line)
    local ev = TT.ev
    -- Totalled arithmetically rather than tested with next(). next is a Lua
    -- standard, but the diagnostic must not be the thing that fails: this code
    -- runs from a slash handler on any client, including any whose global
    -- environment has been trimmed. A missing standard function inside a
    -- diagnostic is reported by the error handler the user just enabled, which
    -- is not a useful outcome.
    local total = (ev.unitRender or 0) + (ev.gsCallback or 0) + (ev.portraitHide or 0)
        + (ev.portraitDestroy or 0) + (ev.portraitModelHidden or 0)
    if (total == 0) then
        line("event counters", "no events recorded yet -- hover a character first")
        return
    end
    print("|cff59f0dc-- event counters (cumulative since /reload) --|r")
    line("unit renders", ev.unitRender or 0)
    line("GearScore callbacks", ev.gsCallback or 0)
    line("  of those, dropped as re-entrant", ev.gsCallbackReentrant or 0)
    line("  of those, wrong unit", ev.gsCallbackWrongUnit or 0)
    -- Labels here MUST name what is counted. TT.ev.portraitHide is incremented
    -- inside the retainModel guard at :1431, so it counts teardowns, not
    -- Hide() calls, and printing it as "portrait hide" made it look like the
    -- hide was being measured when nothing could observe that call. Hence the
    -- separate portraitModelHidden counter, which is incremented on EVERY
    -- clearTooltipVisuals Hide() and is the number to read for "a clear took
    -- the frame away".
    --
    -- The "(on clear)" in the label is load-bearing, not decoration:
    -- TT:ApplyTooltipAppearance has its own Hide() at :1211, on the branch taken
    -- when the portrait option is off or the unit is nil, and that one is NOT
    -- counted here. A label reading plain "Hide() calls" would claim to see a
    -- call it cannot.
    line("portrait Hide() calls (on clear)", ev.portraitModelHidden or 0)
    -- portraitHide and portraitDestroy are incremented in the same two lines
    -- and therefore always equal; both are kept so the older name still reads.
    line("portrait teardowns (hide + ClearModel)", ev.portraitHide or 0)
    line("portrait destroys (ClearModel)", ev.portraitDestroy or 0)
    line("portrait re-anchor", ev.portraitAnchor or 0)
    -- Name the path that let the model go. A single portrait-hide count could
    -- not distinguish them, and a fix aimed at the wrong one shipped on top of
    -- that -- the unresolved-unit path was patched and the blink stayed, because
    -- a different call site was the one actually firing.
    if (ev.teardownBy) then
        print("|cff59f0dc-- teardown path (which call site released the model) --|r")
        for reason, count in pairs(ev.teardownBy) do
            line("  " .. reason, count)
        end
    end
    -- Inspect frame health. An empty paperdoll is reported as a gear bug, but
    -- the overlay missing alongside it points at our own init aborting, and
    -- those two need different fixes. Reporting both in one command is the
    -- difference between a measurement and a guess.
    print("|cff59f0dc-- inspect frame --|r")
    line("  InspectModelFrame exists", InspectModelFrame ~= nil)
    line("  InspectPaperDollFrame exists", InspectPaperDollFrame ~= nil)
    line("  guild guard installed", rawget(_G, "_tacoTipInspectGuildGuarded") and true or false)
    line("  overlay initialised", TT.InitInspectFrame == nil)
    line("  InspectGearScore exists", rawget(_G, "InspectGearScore") ~= nil)
    line("  InspectAvgItemLvl exists", rawget(_G, "InspectAvgItemLvl") ~= nil)
    if (InspectFrame) then
        line("  InspectFrame shown", InspectFrame:IsShown() and true or false)
        line("  InspectFrame.unit", InspectFrame.unit and tostring(InspectFrame.unit) or "nil")
    end
    -- LibForeverInspector range/scan diagnostics.
    if (CI and type(CI.GetInspectStats) == "function") then
        local ok, st = pcall(CI.GetInspectStats, CI)
        if (ok and type(st) == "table") then
            print("|cff59f0dc-- inspect range / proximity scan --|r")
            line("  notifies", st.notifies or 0)
            line("  inspect ready", st.ready or 0)
            line("  timeouts", st.timeouts or 0)
            -- A refusal is the client saying "I will not inspect that unit". On
            -- Classic Era it arrives as an engine UI error and is swallowed by
            -- the probe guard, so the player never sees or hears it: a rising
            -- `refusals recorded` with `probe errors suppressed` beside it is the
            -- client teaching us its real range, silently. `learned max range` is
            -- the number it taught -- the tightest distance this client has
            -- refused at -- and is the value the next release should set the
            -- pre-filter from instead of a hardcoded yardage.
            line("  refusals recorded", st.rejected or 0)
            line("  probe errors suppressed", st.suppressed or 0)
            line("  error speech suppressed", st.suppressedVoice or 0)
            line("  error sound suppressed", st.suppressedSound or 0)
            -- NOT the refusal. lastError is set only when the engine CALL raises a
            -- Lua error out of NotifyInspect, which is a different event from a
            -- refusal delivered as a UI error. The label used to read "last
            -- refusal", so on a client whose refusals never raise the line was
            -- permanently empty and read as "no refusals" while `probe errors
            -- suppressed` climbed beside it.
            if (st.lastError) then
                line("  last inspect-call error", tostring(st.lastError))
            end
            line("  learned max range", st.learnedRange and (tostring(st.learnedRange) .. "yd") or "unknown")
            line("  scan enqueued", st.scanEnqueued or 0)
            line("  scan via fallback", st.scanFallback or 0)
            line("  scan skipped (range)", st.scanSkippedDistance or 0)
        end
    end
    -- The old text here read "portrait destroy should be ~1 for a character and
    -- 0 for a re-hover of the same one". That is only true for the FIRST unit
    -- rendered after a /reload: state.currentUnitGUID is assigned at :1586 and
    -- is NEVER cleared, so it always holds the unit rendered most recently --
    -- which character you hover first is arbitrary. Re-hovering the same one
    -- does not destroy, but only when it is the one still recorded; A, then B,
    -- then A again is three destroys, not two.
    print("|cff59f0dcTo read a rate: note the numbers, hover one frame for 5s,|r")
    print("|cff59f0dcrun /tt diag again and subtract. Portrait Hide() calls (on clear)|r")
    print("|cff59f0dcmust not run AHEAD of unit renders: a steady hover of one|r")
    print("|cff59f0dccharacter adds renders and no hides. Destroys are 1 for the first|r")
    print("|cff59f0dcunit after a /reload, plus 1 for every change to a different unit|r")
    print("|cff59f0dcor a non-unit tooltip; re-rendering the unit already on screen adds none.|r")
end

-- Silent-failure checks.
--
-- Everything a Lua error handler can see is, by definition, a raised error.
-- The failures that cost the most to diagnose in this addon were the opposite
-- kind: no error, a plausible-looking tooltip, and a feature quietly absent or
-- pointed at the wrong thing. So this reports states that are internally
-- inconsistent -- each one is a claim the addon makes about itself that is false,
-- which is checkable without reproducing the user's symptom.
--
-- Read-only: reads config and globals, creates no widget, and calls no setter.
-- A diagnostic that changes the thing it measures is worse than none.
local function reportSilentFailures(line)
    local problems = {}

    -- Client detection must be unambiguous. Forever and Retail SHARE
    -- WOW_PROJECT_MAINLINE, so only the interface band separates them -- and
    -- three of the five shipped clients are NEITHER Retail nor Forever BY
    -- DESIGN. The old condition here flagged "is not mainline", so every
    -- /tacotip diag on Classic Era, TBC Anniversary and Titanforge opened a red
    -- PROBLEMS section with a false alarm. The signal worth flagging is
    -- "the family resolved to NOTHING": when that happens every family-only path
    -- silently switches off and nothing raises.
    if (CI) then
        local projectId = select(2, _G.GetBuildInfo and _G.GetBuildInfo())
        local iv = CI.interfaceVersion or 0
        if (CI.IsRetail and CI.IsRetail() and CI.IsForever and CI.IsForever()) then
            problems[#problems + 1] = "client detected as BOTH Retail and WoW Forever (interface "
                .. tostring(iv) .. ", project " .. tostring(projectId) .. ")"
        elseif (CI.IsUnknown and CI.IsUnknown()) then
            problems[#problems + 1] = "client family could not be resolved ("
                .. "interface " .. tostring(iv) .. ", project " .. tostring(projectId) .. ")"
        end
        -- projectId is the 2nd return of GetBuildInfo on Classic but the 4th on
        -- modern, so it can legitimately read nil here. Only flag a value that is
        -- present AND inconsistent with the family.
        if (projectId and CI.family == "classicEra" and projectId ~= 2) then
            problems[#problems + 1] = "Classic Era expects project id 2, got "
                .. tostring(projectId)
        end
    end

    -- A configured border texture that matches no entry in the list resolves to
    -- the per-client default instead. That is correct behaviour but INVISIBLE, so
    -- a player who picked a border that has since disappeared would see the
    -- fallback and have no way to tell why.
    local cfg = _G.TacoTipConfig
    if (cfg and cfg.tooltip_border_texture and TT.GetTooltipBorderChoices) then
        local value = cfg.tooltip_border_texture
        local matched = false
        local ok, choices = pcall(function() return TT:GetTooltipBorderChoices() end)
        if (ok and choices) then
            for _, entry in ipairs(choices) do
                if (entry.value == value or entry.text == value) then
                    matched = true
                    break
                end
            end
        end
        if (not matched) then
            problems[#problems + 1] = "border setting '" .. tostring(value)
                .. "' matches no entry and is being replaced by the per-client default ("
                .. tostring(TT.GetDefaultTooltipBorder and TT:GetDefaultTooltipBorder()) .. ")"
        end
    end

    -- Feature flags that are on but whose backing API is absent: the feature
    -- renders as if enabled and simply does nothing.
    if (cfg) then
        if (cfg.show_power_bar and _G.UnitPowerType == nil) then
            problems[#problems + 1] = "Power Bar is enabled but UnitPowerType is nil -- it cannot update"
        end
        if (cfg.show_hp_bar and _G.UnitHealthMax == nil) then
            problems[#problems + 1] = "Health Bar is enabled but UnitHealthMax is nil -- it cannot update"
        end
        if (cfg.show_talents and (CI == nil or type(CI.GetSpecialization) ~= "function")) then
            problems[#problems + 1] = "Talents are enabled but the inspector exposes no GetSpecialization"
        end
    end

    -- Hook coverage. A script the addon needs but that this client does not
    -- declare means a code path is dead on this client -- silently.
    if (TT.HookedTooltipScripts and not TT.HookedTooltipScripts.Unit) then
        problems[#problems + 1] = "no unit tooltip delivery path is hooked on this client"
    end

    -- The tooltip surface the border code depends on. GameTooltip.SetBackdrop is
    -- nil on all five clients; if a future client ever supplies it, the border
    -- takes the legacy full-backdrop branch and the background texture starts
    -- being drawn, which would be a visible regression.
    local gt = _G.GameTooltip
    if (gt and gt.SetBackdrop) then
        problems[#problems + 1] = "GameTooltip.SetBackdrop now EXISTS -- the legacy full-backdrop "
            .. "border branch would activate and start drawing the background texture"
    end

    if (#problems == 0) then
        line("problems", "none detected")
        return
    end
    print("|cffff8080-- PROBLEMS (no Lua error is raised for these) --|r")
    for i, p in ipairs(problems) do
        print("|cffff8080" .. i .. ". " .. p .. "|r")
    end
end

function TT:PrintDiagnostics()
    local function line(label, value)
        print(string.format("|cff59f0dcTacoTip:|r %s: %s", label, tostring(value)))
    end
    print("|cff59f0dc===== TacoTip diagnostics =====|r")
    line("version", addOnVersion)
    line("load OK", TT.LOAD_OK and "yes" or "NO -- main.lua stopped at stage: " .. tostring(TT.LOAD_STAGE))
    line("client family", CI and CI.family or "?")
    line("interface", CI and CI.interfaceVersion or "?")
    -- Which widget surface this client actually presents. These three facts
    -- select the tooltip code paths, so reporting them makes a "looks wrong on
    -- client X" report answerable without guesswork. Read-only: no widget is
    -- created, so running the diagnostic has no side effects.
    local gt = _G.GameTooltip
    line("tooltip has NineSlice", gt and gt.NineSlice ~= nil)
    line("tooltip has SetBackdrop", type(gt and gt.SetBackdrop))
    line("tooltip has OnTooltipSetUnit", (gt and gt.HasScript) and gt:HasScript("OnTooltipSetUnit") or "?")
    line("TT.HookedTooltipScripts", TT.HookedTooltipScripts
        and ("unit=" .. tostring(TT.HookedTooltipScripts.Unit)
            .. " item=" .. tostring(TT.HookedTooltipScripts.Item)) or "none")
    -- A C API argument error carries no Lua stack, so this is the only place it
    -- can be named. Reported once per distinct message; see handlePipelineError.
    line("last tooltip error", TT.lastTooltipError or "none")
    if (not TT.LOAD_OK) then
        print("|cff59f0dcIf the stage is not \"complete\", an error was raised while|r")
        print("|cff59f0dclloading main.lua at or after that point. /reload cannot fix|r")
        print("|cff59f0dcit -- enable Lua error reporting (BugSack/Swatter) and reload.|r")
    end
    line("TacoTip_CustomPosEnable", type(_G.TacoTip_CustomPosEnable))
    line("TT.ApplyTooltipAppearance", type(TT.ApplyTooltipAppearance))
    line("TT.OpenOptionsPanel", type(TT.OpenOptionsPanel))
    line("TT.RefreshOptionsUI", type(TT.RefreshOptionsUI))
    line("TT.SyncTooltipMover", type(TT.SyncTooltipMover))
    local gs = _G.TT_GS
    line("GearScore bracket", gs and gs.BRACKET_SIZE or "none")
    line("locale", _G.TACOTIP_ACTIVE_LOCALE or "?")
    reportEventCounters(line)
    reportSilentFailures(line)
    print("|cff59f0dc================================|r")
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
                if (GameTooltip and type(GameTooltip.FadeOut) == "function") then
                    Detours:SecureHook(TT, GameTooltip, "FadeOut", function(tooltipFrame)
                        if (tooltipFrame and type(tooltipFrame.Hide) == "function") then
                            tooltipFrame:Hide()
                        end
                    end)
                end
            end
            -- characterFrameHost, not CharacterModelFrame: Retail has no model
            -- frame but does have PaperDollFrame, and the font strings are
            -- parented to it there, so the initial paint applies on all five
            -- clients instead of being skipped on the two that lack the model.
            if (characterFrameHost) then
                TT:RefreshCharacterFrame()
            end
            if (TT.InitInspectFrame and InspectModelFrame and InspectPaperDollFrame) then
                TT:InitInspectFrame()
                TT.InitInspectFrame = nil
            end
            CAfter(3, function()
                print("|cff59f0dcTacoTip v" .. addOnVersion .. " " .. L["TEXT_HELP_WELCOME"])
                if (first_login) then
                    print("|cff59f0dcTacoTip:|r " .. L["TEXT_HELP_FIRST_LOGIN"])
                end
            end)
        elseif (addon == "Blizzard_InspectUI") then
            if (TT.InitInspectFrame and InspectModelFrame and InspectPaperDollFrame) then
                TT:InitInspectFrame()
                TT.InitInspectFrame = nil
            end
        end
    elseif (event == "UPDATE_MOUSEOVER_UNIT") then
        if (TacoTipConfig.instant_fade and GameTooltip and GameTooltip:IsShown() and ((GameTooltip.IsUnit and GameTooltip:IsUnit("mouseover")) or (GameTooltip.GetUnit and select(2, GameTooltip:GetUnit()) == "mouseover"))) then
            cancelFadeTimer(GameTooltip)
            local state = getTooltipState(GameTooltip)
            local timer
            if (type(NewTimer) == "function") then
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
                -- The library fires INVENTORY_READY and TALENTS_READY back to back
                -- for ONE completed inspect. Rebuilding on both ran the entire
                -- render twice for identical data -- the gate chain, the whole text
                -- path, and GetScore, which walks 18 item slots and their item
                -- loads. The second of an immediate pair is dropped, keyed on the
                -- GUID with a short window, so a genuine later update still
                -- rebuilds. GetTime is the same monotonic clock the library uses.
                local st = getTooltipState(GameTooltip)
                local now = (type(GetTime) == "function") and GetTime() or 0
                local duplicate = (st.inspectRenderGUID == guid
                    and st.inspectRenderTime ~= nil
                    and (now - st.inspectRenderTime) < INSPECT_RENDER_COALESCE)
                if (not duplicate) then
                    st.inspectRenderGUID = guid
                    st.inspectRenderTime = now
                    GameTooltip:SetUnit(ttUnit)
                end
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


stage("mover-defined")

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
        rawset(TacoTipDragButton, "ShowExample", function(self)
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
        end)

        rawset(TacoTipDragButton, "_Enable", function(self)
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
        end)

        rawset(TacoTipDragButton, "_Save", function(self)
            syncTooltipMoverPosition(false)
            GameTooltip:EnableMouse(false)
            TacoTipDragButton:Hide()
            print("|cff59f0dcTacoTip:|r " .. L["TEXT_HELP_MOVER_SAVED"])
            refreshOptionsUI()
        end)

        rawset(TacoTipDragButton, "_ResetPosition", function(self)
            TacoTipConfig.custom_pos = getDefaultTooltipMoverPosition()
            syncTooltipMoverPosition(true)
            refreshOptionsUI()
        end)

        rawset(TacoTipDragButton, "_Disable", function(self, preserveAnchor)
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
        end)

        TacoTipDragButton:Hide()
    end
    TacoTipDragButton:_Enable()
    if (show) then
        TacoTipDragButton:Show()
    else
        TacoTipDragButton:Hide()
    end
end

-- Slash commands are NOT registered here, and must never be.
--
-- They already exist. gearscore.lua installs an early bootstrap handler behind a
-- guard; options.lua loads later and deliberately replaces it with the final
-- handler, which owns custom / save / default. Anything assigned to
-- SlashCmdList.TACOTIP from THIS file would overwrite that final handler, because
-- main.lua is last in the toc, and the player would silently lose every existing
-- subcommand. The "diag" subcommand therefore lives in options.lua's handler.
--
-- Recorded because the first attempt got this exactly wrong: grepping only
-- main.lua for SLASH_ found nothing, which read as "no slash command is
-- registered anywhere" and led to a duplicate registration being written here.
-- When a symbol is absent from one file, check the others before concluding it
-- does not exist.

-- Loading reached the end of the file. Anything after this point is a runtime
-- problem, not a load-order one.
stage("complete")
TT.LOAD_OK = true
