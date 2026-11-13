local addOnName = ...
local addOnVersion = (GetAddOnMetadata and GetAddOnMetadata(addOnName, "Version")) or
    (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addOnName, "Version")) or "1.0.2"



assert(LibStub, "TacoTip requires LibStub")
assert(LibStub:GetLibrary("LibForeverInspector", true), "TacoTip requires LibForeverInspector")
assert(LibStub:GetLibrary("LibDetours-1.0", true), "TacoTip requires LibDetours-1.0")

local CI = LibStub("LibForeverInspector")
-- Resolved once: every Forever-only branch below reads this, so a client
-- family can never be re-derived inside the render.
local isForever = (CI and CI.IsForever and CI:IsForever()) and true or false
local isRetail = (CI and CI.IsRetail and CI:IsRetail()) and true or false

-- FojjiCore appends its own gear-score / item-level row to GameTooltip after
-- this addon has rendered the unit tooltip. Never override GameTooltip's
-- AddLine/AddDoubleLine to stop it: that replaces methods on a shared, secure
-- frame and taints the tooltip path for every addon on the client. FojjiCore
-- publishes that row as an ordinary Tooltips option, so switch the option off
-- at the source. Nothing but FojjiCore is touched.
local function blockFojjiCoreScoreRow()
    local ns = rawget(_G, "FojjiCoreNS")
    local tooltips = (type(ns) == "table") and ns.Tooltips or nil
    if (type(tooltips) == "table" and type(tooltips.Set) == "function") then
        pcall(tooltips.Set, "bisGearScore", false)
    end
end

if (isForever) then
    blockFojjiCoreScoreRow()
    if (type(CreateFrame) == "function") then
        -- FojjiCore_BiS is a separate addon and can load before or after this
        -- file; apply the option again when it finishes loading.
        local watcher = CreateFrame("Frame")
        watcher:RegisterEvent("ADDON_LOADED")
        watcher:SetScript("OnEvent", function(self, _, name)
            if (name == "FojjiCore" or name == "FojjiCore_BiS") then
                blockFojjiCoreScoreRow()
            end
        end)
    end
end

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
-- main.lua is the LAST file in the toc and 4100 lines long, and it defines
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
-- Session uptime for /tt diag. GetTime is monotonic and resets on /reload,
-- which is the same lifetime as TT; a nil GetTime degrades to "unknown".
TT.loadTime = (type(GetTime) == "function") and GetTime() or 0
local function stage(name)
    TT.LOAD_STAGE = name
end

stage("core")

local safeWipe = _G.wipe or table.wipe or function(t)
    if (type(t) ~= "table") then return t end
    for k in pairs(t) do t[k] = nil end
    return t
end

-- Zero-allocation tooltip line fontstring caches:
-- On Classic Era, TBC, and Titanforge where tooltip.GetLeftLine does not exist,
-- lookups fall back to _G[name .. "TextLeft" .. index]. Caching the resolved
-- FontString objects avoids dozens of string allocations per hover tick.
local tooltipLeftLineCache = setmetatable({}, { __mode = "k" })
local tooltipRightLineCache = setmetatable({}, { __mode = "k" })

function TT.GetTooltipLeftLine(tooltip, index)
    if (not tooltip or not index) then return nil end
    local lines = tooltipLeftLineCache[tooltip]
    if (lines and lines[index]) then
        return lines[index]
    end
    local line
    if (tooltip.GetLeftLine) then
        line = tooltip:GetLeftLine(index)
    else
        local name = tooltip.GetName and tooltip:GetName()
        if (name) then
            line = _G[name .. "TextLeft" .. index]
        end
    end
    if (line) then
        if (not lines) then
            lines = {}
            tooltipLeftLineCache[tooltip] = lines
        end
        lines[index] = line
    end
    return line
end

function TT.GetTooltipRightLine(tooltip, index)
    if (not tooltip or not index) then return nil end
    local lines = tooltipRightLineCache[tooltip]
    if (lines and lines[index]) then
        return lines[index]
    end
    local line
    if (tooltip.GetRightLine) then
        line = tooltip:GetRightLine(index)
    else
        local name = tooltip.GetName and tooltip:GetName()
        if (name) then
            line = _G[name .. "TextRight" .. index]
        end
    end
    if (line) then
        if (not lines) then
            lines = {}
            tooltipRightLineCache[tooltip] = lines
        end
        lines[index] = line
    end
    return line
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

    local leftCap = (type(maxWidth) == "number" and maxWidth > 0) and maxWidth or nil

    -- Walk a little past the current line count: the pooled lines are reused
    -- across hovers, so a line left over from a longer previous tooltip still
    -- carries the old cap and would keep the tooltip wide.
    --
    -- Never call SetWidth(0) on an untouched line when maxWidth == 0, and
    -- never mutate rightLine: on Forever/Retail 12.x C++, TextRight strings are
    -- right-justified single-anchor columns inside AddDoubleLine and SetWidth(0)
    -- collapses their intrinsic width to 0 (rendering "...").
    local scan = math.max(numLines + 4, 20)
    for i = 1, scan do
        local leftLine = getTooltipLeftLine(tooltip, i)
        if (leftLine and type(leftLine.SetWidth) == "function") then
            if (leftCap) then
                if (leftLine._tacoTipMaxWidth ~= leftCap) then
                    pcall(leftLine.SetWidth, leftLine, leftCap)
                    leftLine._tacoTipMaxWidth = leftCap
                end
            elseif (leftLine._tacoTipMaxWidth and leftLine._tacoTipMaxWidth > 0) then
                pcall(leftLine.SetWidth, leftLine, 0)
                leftLine._tacoTipMaxWidth = nil
            end
        end
        local rightLine = getTooltipRightLine(tooltip, i)
        if (rightLine and rightLine._tacoTipMaxWidth ~= nil) then
            rightLine._tacoTipMaxWidth = nil
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
local HORDE_ICON_SPACED = " " .. HORDE_ICON
local ALLIANCE_ICON_SPACED = " " .. ALLIANCE_ICON
local PVP_FLAG_ICON = "|TInterface\\GossipFrame\\BattleMasterGossipIcon:0|t"
local PVP_FLAG_ICON_SPACED = " " .. PVP_FLAG_ICON
local ACHIEVEMENT_ICON = "|TInterface\\AchievementFrame\\UI-Achievement-TinyShield:18:18:0:0:20:20:0:12.5:0:12.5|t"
local SEPARATOR_LINE = "|cFF444444" .. string.rep("-", 30) .. "|r"
local ROLE_ICONS = {
    TANK = " |TInterface\\GroupFrame\\UI-Group-TankIcon:18:18:0:0:16:16:0:16:0:16|t",
    HEALER = " |TInterface\\GroupFrame\\UI-Group-HealerIcon:18:18:0:0:16:16:0:16:0:16|t",
    DAMAGER = " |TInterface\\GroupFrame\\UI-Group-DPSIcon:18:18:0:0:16:16:0:16:0:16|t",
    DPS = " |TInterface\\GroupFrame\\UI-Group-DPSIcon:18:18:0:0:16:16:0:16:0:16|t",
}
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
local GetMapInfo = _G.C_Map and _G.C_Map.GetMapInfo
-- C_Item namespace and Blizzard ObjectAPI
local Item = _G.Item
-- Namespaced on purpose: there is no bare global RequestLoadItemDataByID on any
-- of the five supported clients, only C_Item.RequestLoadItemDataByID.
local RequestLoadItemDataByID = _G.C_Item and _G.C_Item.RequestLoadItemDataByID
local GameTooltip_SetDefaultAnchor = _G.GameTooltip_SetDefaultAnchor
local UnitClass = _G.UnitClass
local UnitCanAttack = _G.UnitCanAttack
---@secret-guard v is-secret
function TT.isSecretValue(v)
    if (type(v) == "nil") then return false end
    if (type(issecretvalue) == "function") then
        local okSecret, isSec = pcall(issecretvalue, v)
        if (not okSecret or isSec == true) then return true end
    end
    local canaccess = rawget(_G, "canaccessvalue")
    if (type(canaccess) == "function") then
        local okAccess, canAcc = pcall(canaccess, v)
        if (not okAccess or canAcc == false) then return true end
    end
    return false
end

---@secret-guard v is-secret
local function isSecretValue(v)
    return TT.isSecretValue(v)
end

function TT.safeEquals(a, b)
    if (type(a) == "nil" or type(b) == "nil" or isSecretValue(a) or isSecretValue(b)) then
        return false
    end
    local ok, eq = pcall(function() return a == b end)
    return ok and eq == true
end

local safeEquals = TT.safeEquals

-- Is a tooltip-data table safe to INDEX?
--
-- The post-call hands us the very payload the client just processed. On WoW
-- Forever that payload can be a SECRET TABLE. From the client/wiki contract: once
-- untainted code stores a secret value as a table KEY, the table is irrevocably
-- flagged both secret AND inaccessible to tainted code, and "any attempt to
-- index, assign, measure, or iterate over such a table will trigger an immediate
-- Lua error" ("attempted to index a forbidden table").
--
-- issecretvalue() does NOT answer that question, and it is the wrong predicate
-- for this job: the raise happens on the INDEX ITSELF, before any isSecretValue()
-- on the result could ever run. The documented predicate is canaccesstable():
--   "Returns true if the immediate calling function has appropriate permissions
--    to index secret tables. This will return false if the caller cannot access
--    the table value itself, or if access to the table contents is disallowed by
--    taint."                                    (FrameScriptDocumentation.lua:48-63)
--
-- It is itself SecretArguments="AllowedWhenUntainted", so it is pcall'd and a
-- refusal is treated exactly like false. Clients that do not expose it (the
-- classic family) simply read the table normally.
--
-- Every `data.<field>` read in this file goes through here first. Presenting no
-- row is the correct outcome when the payload cannot be read -- never a raise.
function TT.tooltipDataReadable(data)
    if (type(data) ~= "table") then return false end
    if (isSecretValue(data)) then return false end
    local canAccess = rawget(_G, "canaccesstable")
    if (type(canAccess) == "function") then
        local ok, can = pcall(canAccess, data)
        if (not ok or can ~= true) then return false end
    end
    return true
end

function TT.safeUnitGUID(unit)
    if (type(unit) == "nil" or isSecretValue(unit) or type(UnitGUID) ~= "function") then return nil end
    local ok, guid = pcall(UnitGUID, unit)
    -- UnitGUID is documented Nilable; type() answers "is nil" without ever
    -- comparing a value that can also arrive secret.
    if (not ok or type(guid) == "nil" or isSecretValue(guid)) then return nil end
    return guid
end

local safeUnitGUID = TT.safeUnitGUID

function TT.safeUnitExists(unit)
    if (type(unit) == "nil" or isSecretValue(unit) or type(UnitExists) ~= "function") then
        return false
    end
    local ok, exists = pcall(UnitExists, unit)
    if (not ok or isSecretValue(exists)) then
        return false
    end
    return exists == true
end

local safeUnitExists = TT.safeUnitExists

function TT.safeUnitIsPlayer(unit)
    if (type(unit) == "nil" or isSecretValue(unit) or type(UnitIsPlayer) ~= "function") then
        return false
    end
    local ok, isP = pcall(UnitIsPlayer, unit)
    if (not ok or isSecretValue(isP)) then
        return false
    end
    return isP == true
end

local safeUnitIsPlayer = TT.safeUnitIsPlayer

function TT.safeUnitIsUnit(u1, u2)
    if (type(u1) == "nil" or type(u2) == "nil" or isSecretValue(u1) or isSecretValue(u2) or type(UnitIsUnit) ~= "function") then
        return false
    end
    local ok, isU = pcall(UnitIsUnit, u1, u2)
    if (not ok or isSecretValue(isU)) then
        return false
    end
    return isU == true
end

local safeUnitIsUnit = TT.safeUnitIsUnit

function TT.safeUnitInParty(unit)
    if (type(unit) == "nil" or isSecretValue(unit) or type(UnitInParty) ~= "function") then
        return false
    end
    local ok, inP = pcall(UnitInParty, unit)
    if (not ok or isSecretValue(inP)) then
        return false
    end
    return inP == true
end

local safeUnitInParty = TT.safeUnitInParty

function TT.safeUnitInRaid(unit)
    if (type(unit) == "nil" or isSecretValue(unit) or type(UnitInRaid) ~= "function") then
        return false
    end
    local ok, inR = pcall(UnitInRaid, unit)
    if (not ok or isSecretValue(inR)) then
        return false
    end
    return type(inR) == "number" or inR == true
end

local safeUnitInRaid = TT.safeUnitInRaid

function TT.safeUnitIsPVP(unit)
    if (type(unit) == "nil" or isSecretValue(unit) or type(UnitIsPVP) ~= "function") then
        return false
    end
    local ok, isPVP = pcall(UnitIsPVP, unit)
    if (not ok or isSecretValue(isPVP)) then
        return false
    end
    return isPVP == true
end

local safeUnitIsPVP = TT.safeUnitIsPVP
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
---@field portraitSide string|nil      -- cached portrait layout side ("LEFT"|"RIGHT")
---@field portraitAnchored boolean|nil -- whether the 3D/2D portrait is anchored to current layout
---@field inspectRenderGUID string|nil -- GUID of the inspected unit when last rendered
---@field inspectRenderTime number|nil -- GetTime() monotonic timestamp of the last inspect render
---@field ownerUnitGUID string|nil     -- GUID of the tooltip owner's unit frame token
---@field ownerUnitToken string|nil    -- Unit token of the tooltip owner's frame (e.g. "party1")

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
        return nilTooltipState --[[@as tacoTipTooltipState]]
    end
    if (not tooltip._tacoTipState) then
        tooltip._tacoTipState = { generation = 0 }
    end
    return tooltip._tacoTipState
end

-- Resolve the owner frame's unit token across player, target, pet, party,
-- and raid frames (handling direct .unit, .displayedUnit, or secure attributes).
local function getTooltipOwnerUnit(tooltip)
    local owner = tooltip and tooltip.GetOwner and tooltip:GetOwner()
    if (not owner) then
        return nil
    end
    local unit = owner.unit or owner.displayedUnit
    if (not unit and type(owner.GetAttribute) == "function") then
        local okA, attr = pcall(owner.GetAttribute, owner, "unit")
        if (okA) then unit = attr end
    end
    if (unit and isSecretValue(unit)) then
        return nil
    end
    return unit
end

-- The owner frame's unit is the strongest identity a unit tooltip has. It is
-- set by UnitFrame_UpdateTooltip before SetUnit and it survives every periodic
-- re-drive, including the first one -- when the modern post-call runs before
-- Show() and the tooltip cannot yet resolve a unit token. Remember it on every
-- unit render so the clear hooks can prove "same unit frame, same unit" without
-- depending on currentUnitGUID, which is only written after a successful
-- resolve.
local function noteOwnerUnitGUID(tooltip)
    local state = getTooltipState(tooltip)
    if (not state) then
        return
    end
    local ownerUnit = getTooltipOwnerUnit(tooltip)
    if (ownerUnit and safeUnitExists(ownerUnit)) then
        state.ownerUnitGUID = safeUnitGUID(ownerUnit)
        state.ownerUnitToken = ownerUnit
    else
        state.ownerUnitGUID = nil
        state.ownerUnitToken = nil
    end
end

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
    local ownerUnitGUID = state and state.ownerUnitGUID
    local ownerUnit = getTooltipOwnerUnit(tooltip)
    local unitGUID
    if (ownerUnit and safeUnitExists(ownerUnit)) then
        unitGUID = safeUnitGUID(ownerUnit)
    end
    -- Two proofs of "still the same unit": the rendered GUID (successful
    -- resolve) and the owner's unit GUID (recorded before resolution ran).
    -- The second exists because the modern post-call runs before Show(), when
    -- the first tick can be unreadable -- and currentUnitGUID is then never
    -- written, so the old check rejected every subsequent tick and tore the
    -- portrait down five times a second while the mouse sat still on a unit
    -- frame. That is the long-standing Retail/Forever blink.
    -- The owner-GUID proof is modern-only: the pre-Show postcall resolution
    -- failure it covers is a modern ordering fact. Classic keeps the old
    -- currentUnitGUID-only test exactly.
    local sameUnit = false
    if (unitGUID ~= nil) then
        sameUnit = safeEquals(unitGUID, curGUID)
            or ((isForever or isRetail) and safeEquals(unitGUID, ownerUnitGUID))
    elseif ((isForever or isRetail) and ownerUnit and state and state.ownerUnitToken
            and safeUnitExists(ownerUnit)
            and safeUnitIsUnit(ownerUnit, state.ownerUnitToken)) then
        sameUnit = true
    end
    if (not sameUnit) then
        return false
    end
    if (owner.UpdateTooltip) then
        return true
    end
    -- UnitFrame_OnLeave nils UpdateTooltip before GameTooltip:FadeOut(), so the
    -- first re-drive after a re-hover reaches ClearLines with no
    -- UpdateTooltip even though the owner still proves the same unit. While
    -- the tooltip is SHOWN that clear is the 0.2s tick and must not tear the
    -- portrait down. A hidden OnHide keeps the normal cleanup path: the parent
    -- already hides its children, so the portrait is not visible there, and
    -- skipping the timer/power-bar cleanup on a real hide would be a different
    -- behaviour change. Classic keeps the old guard exactly.
    return (isForever or isRetail) and (not tooltip.IsShown or tooltip:IsShown()) and true or false
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
local UnitIsPlayer = _G.UnitIsPlayer
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
TT.totalErrorsCaught = TT.totalErrorsCaught or 0
TT.errorLog = TT.errorLog or {}
TT.warningLog = TT.warningLog or {}

function TT:RecordError(subsystem, message, context)
    if (message == nil) then
        return
    end
    local text = tostring(message)
    TT.lastTooltipError = text
    TT.totalErrorsCaught = (TT.totalErrorsCaught or 0) + 1
    local now = (type(GetTime) == "function") and GetTime() or 0
    local fnDebugStack = rawget(_G, "debugstack")
    local stack = (type(fnDebugStack) == "function") and fnDebugStack(2, 8, 8) or nil
    local log = TT.errorLog
    if (type(log) == "table") then
        if (#log >= 15) then
            table.remove(log, 1)
        end
        log[#log + 1] = {
            time = now,
            subsystem = subsystem or "General",
            message = text,
            context = context and tostring(context) or nil,
            stack = stack,
        }
    end
end

function TT:RecordWarning(subsystem, message, context)
    if (message == nil) then
        return
    end
    local text = tostring(message)
    local now = (type(GetTime) == "function") and GetTime() or 0
    -- Lifetime total. The log is capped at 30 and drops the oldest entry, so
    -- #warningLog alone would UNDERSTATE the warnings a session actually hit --
    -- exactly the "the report hid a warning" failure this counter prevents.
    TT.totalWarnings = (TT.totalWarnings or 0) + 1
    local fnDebugStack = rawget(_G, "debugstack")
    local stack = (type(fnDebugStack) == "function") and fnDebugStack(2, 6, 6) or nil
    local log = TT.warningLog
    if (type(log) == "table") then
        if (#log >= 30) then
            table.remove(log, 1)
        end
        log[#log + 1] = {
            time = now,
            subsystem = subsystem or "Warning",
            message = text,
            context = context and tostring(context) or nil,
            stack = stack,
        }
    end
end

-- Per-API tally of refused secret arguments. A refusal is an immediate Lua
-- error from an AllowedWhenUntainted function; the boundary helpers pcall it and
-- read the throw as "secret". Counting it here answers the question the error
-- text cannot: WHICH gate fired, and how often. Keys are literal names, never a
-- value, so the tally itself cannot touch a secret.
function TT:NoteSecretRefusal(api)
    if (type(api) ~= "string") then return end
    local ev = TT.ev
    local tally = ev.secretRefused
    if (type(tally) ~= "table") then
        tally = {}
        ev.secretRefused = tally
    end
    tally[api] = (tally[api] or 0) + 1
end

-- Read-only snapshot of the client's active add-on restriction classes. This is
-- state, not a secret: it answers "was this hover inside combat / an encounter /
-- a restricted map" in the report. Feature-detected and secret-safe throughout;
-- returns "not exposed" when the client has no C_RestrictedActions.
function TT:RestrictionSnapshot()
    local ra = _G.C_RestrictedActions
    local restrictionEnum = _G.Enum and Enum.AddOnRestrictionType
    if (type(ra) ~= "table" or type(ra.IsAddOnRestrictionActive) ~= "function"
            or type(restrictionEnum) ~= "table") then
        return "not exposed"
    end
    local names = { "Combat", "Encounter", "ChallengeMode", "PvPMatch", "Map" }
    local parts = {}
    for i = 1, #names do
        local value = restrictionEnum[names[i]]
        if (value ~= nil) then
            local okActive, active = pcall(ra.IsAddOnRestrictionActive, value)
            local stateText = "?"
            if (okActive) then
                if (isSecretValue(active)) then
                    stateText = "?"
                elseif (active == true) then
                    stateText = "on"
                else
                    stateText = "off"
                end
            end
            parts[#parts + 1] = names[i] .. "=" .. stateText
        end
    end
    if (#parts == 0) then return "not exposed" end
    return table.concat(parts, ", ")
end

local PORTRAIT_TRACE_MAX = 32
TT.portraitTrace = TT.portraitTrace or {}

local function safeDiagValue(val)
    if (type(val) == "nil") then
        return "nil"
    end
    if (isSecretValue(val)) then
        return "<secret>"
    end
    return tostring(val)
end

local function recordPortraitTrace(op, reason, tooltip, portrait, extra)
    if (not tooltip or (tooltip ~= GameTooltip and not tooltip.TacoTipPortrait3D and not tooltip.TacoTipPortrait)) then
        return
    end
    local ring = TT.portraitTrace
    if (type(ring) ~= "table") then
        ring = {}
        TT.portraitTrace = ring
    end
    local head = (ring._head or 0) % PORTRAIT_TRACE_MAX + 1
    ring._head = head
    ring._count = math.min(PORTRAIT_TRACE_MAX, (ring._count or 0) + 1)
    ring._seq = (ring._seq or 0) + 1

    local entry = ring[head]
    if (type(entry) ~= "table") then
        entry = {}
        ring[head] = entry
    end
    local ttShown = (tooltip.IsShown and pcall(tooltip.IsShown, tooltip)) and (tooltip:IsShown() == true) or false
    local p3 = rawget(tooltip, "TacoTipPortrait3D")
    if (type(p3) ~= "table") then p3 = nil end
    local p2 = rawget(tooltip, "TacoTipPortrait")
    if (type(p2) ~= "table") then p2 = nil end
    local p3Shown = (p3 and p3.IsShown and p3:IsShown() == true) or false
    local p2Shown = (p2 and p2.IsShown and p2:IsShown() == true) or false
    local state = rawget(tooltip, "_tacoTipState")

    entry.seq = ring._seq
    entry.time = (type(GetTime) == "function") and GetTime() or 0
    entry.op = tostring(op or "?")
    entry.reason = reason and tostring(reason) or nil
    entry.tooltip = (tooltip.GetName and tooltip:GetName()) or "tooltip"
    entry.ttShown = ttShown
    entry.p3Shown = p3Shown
    entry.p2Shown = p2Shown
    entry.curGUID = safeDiagValue(state and state.currentUnitGUID)
    entry.prevKey = safeDiagValue(extra and extra.prevKey or (portrait and portrait.tacoTipModelKey))
    entry.newKey = safeDiagValue(extra and extra.newKey)
    entry.unit = safeDiagValue(extra and extra.unit)
    entry.keepModel = extra and extra.keepModel and true or false
    entry.retainModel = extra and extra.retainModel and true or false
    entry.outcome = extra and extra.outcome and tostring(extra.outcome) or nil
end

local function getPortraitTraceEntries()
    local ring = TT.portraitTrace
    local out = {}
    if (type(ring) ~= "table") then
        return out
    end
    local count = ring._count or 0
    local head = ring._head or 0
    if (count > 0 and head > 0) then
        local startOffset = count - 1
        for offset = startOffset, 0, -1 do
            local idx = ((head - 1 - offset) % PORTRAIT_TRACE_MAX) + 1
            local e = ring[idx]
            if (type(e) == "table") then
                out[#out + 1] = e
            end
        end
    else
        for i = 1, #ring do
            if (type(ring[i]) == "table") then
                out[#out + 1] = ring[i]
            end
        end
    end
    return out
end

function TT:ClearDiagnosticLogs()
    TT.errorLog = {}
    TT.warningLog = {}
    TT.portraitTrace = {}
    TT.totalWarnings = 0
    TT.totalErrorsCaught = 0
    TT.lastTooltipError = nil
    reportedErrors = {}
    if (TT.ev) then
        TT.ev.pipelineErrorsSuppressed = 0
        TT.ev.resolveTooltipUnitFailed = 0
        TT.ev.portraitSetFailed = 0
        TT.ev.portraitSetAttempts = 0
        TT.ev.portraitSetSucceeded = 0
        TT.ev.portraitCanSetFalse = 0
        TT.ev.portraitKeyHits = 0
        TT.ev.portrait2DSets = 0
        TT.ev.portraitClearModelCalls = 0
        TT.ev.portraitOnHideRan = 0
        TT.ev.portraitOnHideSkipped = 0
        TT.ev.portraitOnClearSkipped = 0
        TT.ev.portraitStateMismatch = 0
    end
end

local function handlePipelineError(message)
    if (message == nil) then
        return
    end
    local text = tostring(message)
    TT:RecordError("Pipeline", text)
    if (not reportedErrors[text]) then
        reportedErrors[text] = true
        if (defaultErrorHandler) then
            defaultErrorHandler(text)
        end
    else
        TT.ev.pipelineErrorsSuppressed = (TT.ev.pipelineErrorsSuppressed or 0) + 1
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

-- UnitIsOtherPlayersPet carries SecretWhenUnitIdentityRestricted, so on a
-- restricted unit the answer is a secret BOOLEAN and the caller's
-- `safeUnitIsUnit(...) or isOtherPlayersPet(...)` is a boolean test on it.
-- Unknown reads as "not another player's pet" -- the pet branch is skipped, which
-- is the safe direction (it only chooses which label to print).
local function isOtherPlayersPet(unit)
    if (type(unit) == "nil" or isSecretValue(unit)
            or type(_G.UnitIsOtherPlayersPet) ~= "function") then
        return false
    end
    local ok, isPet = pcall(_G.UnitIsOtherPlayersPet, unit)
    if (not ok or isSecretValue(isPet)) then
        return false
    end
    return isPet == true
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
        -- UnregisterAllEvents dropped the per-unit subscriptions; the next show
        -- must register them again even for the same unit token.
        TacoTipPowerBar._tacoTipUnit = nil
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

local colorCodeCache = {}
local function makeColorCode(r, g, b)
    local floor = math.floor
    local ir = floor((r or 1) * 255)
    if (ir < 0) then ir = 0 elseif (ir > 255) then ir = 255 end
    local ig = floor((g or 1) * 255)
    if (ig < 0) then ig = 0 elseif (ig > 255) then ig = 255 end
    local ib = floor((b or 1) * 255)
    if (ib < 0) then ib = 0 elseif (ib > 255) then ib = 255 end
    local key = ir * 65536 + ig * 256 + ib
    local cached = colorCodeCache[key]
    if (not cached) then
        cached = string.format("|cFF%02x%02x%02x", ir, ig, ib)
        colorCodeCache[key] = cached
    end
    return cached
end

local function colorizeText(text, r, g, b)
    if (not text or text == "") then
        return text or ""
    end
    return string.format("%s%s|r", makeColorCode(r, g, b), text)
end

local classIconMarkupCache = {}
local function getClassIconMarkup(class)
    if (not class or not GetClassAtlas) then
        return ""
    end
    if (isSecretValue(class)) then
        return ""
    end
    local size = (TacoTipConfig and TacoTipConfig.class_icon_size) or 20
    local sizeCache = classIconMarkupCache[size]
    if (not sizeCache) then
        sizeCache = {}
        classIconMarkupCache[size] = sizeCache
    end
    local cached = sizeCache[class]
    if (cached ~= nil) then
        return cached
    end
    local okAtlas, atlas = pcall(GetClassAtlas, class)
    if (okAtlas and atlas and not isSecretValue(atlas)) then
        if (atlas ~= "") then
            local markup = string.format("|A:%s:%d:%d|a", atlas, size, size)
            sizeCache[class] = markup
            return markup
        end
    end
    sizeCache[class] = ""
    return ""
end

TT.GetClassIconMarkup = function(self, class)
    if (class == nil and type(self) == "string") then
        class = self
    end
    return getClassIconMarkup(class)
end

local SHAMAN_BLUE_COLOR = { r = 0.0, g = 0.44, b = 0.87, colorStr = "ff0070de" }

local function getClassColor(class, optClass)
    if (type(class) == "table" and optClass) then
        class = optClass
    end
    if (not class or isSecretValue(class)) then
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
        local leftText = (left and left.GetText) and left:GetText() or nil
        if (left and left.SetText and safeEquals(leftText, tooltip.TacoTipGuildLineText)) then
            left:SetText()
        end
        tooltip.TacoTipGuildLineIndex = nil
        tooltip.TacoTipGuildLineText = nil
    end
end

local function clearTooltipLevelColorLine(tooltip)
    if (tooltip and tooltip.TacoTipLevelColorLineIndex) then
        local left = getTooltipLeftLine(tooltip, tooltip.TacoTipLevelColorLineIndex)
        local leftText = (left and left.GetText) and left:GetText() or nil
        if (left and left.SetText and safeEquals(leftText, tooltip.TacoTipLevelColorLineText)) then
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
    if (not safeUnitExists(unit) or not safeUnitIsPlayer(unit)) then
        clearTooltipPlayerClassColor(tooltip)
        return nil
    end

    local okC, _, class = pcall(UnitClass, unit)
    if (not okC or not class or isSecretValue(class)) then
        clearTooltipPlayerClassColor(tooltip)
        return nil
    end
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

local questDifficultyColorCache = {}
local lastPlayerLevel = nil
local function getHostileDifficultyColor(unit)
    local GetQuestDifficultyColor = _G.GetQuestDifficultyColor
    -- UnitCanAttack / UnitIsPlayer / UnitLevel below all declare
    -- SecretArguments = "AllowedWhenUntainted": a secret token is refused at the
    -- call, before any pcall around it can protect the answer. A token the
    -- caller cannot name gets no colour treatment -- the line keeps whatever
    -- colour the client gave it.
    if (type(unit) == "nil" or isSecretValue(unit) or type(GetQuestDifficultyColor) ~= "function") then
        return nil
    end

    if (type(UnitCanAttack) == "function" and type(UnitIsPlayer) == "function") then
        local okAtk, canAtk = pcall(UnitCanAttack, "player", unit)
        local okPlr, isPlr = pcall(UnitIsPlayer, unit)
        -- The pcall protects the CALL, not the answer: `canAtk == false` below is a
        -- COMPARISON, and a comparison on a secret boolean raises. The generated
        -- docs annotate UnitCanAttack's return as a plain bool at this pin, but
        -- Forever beta reports list it among the values that can arrive secret,
        -- and a guard is a no-op when the annotation is right while it is a save
        -- when it is not -- so the answer is tested before it is compared.
        if (okAtk and not isSecretValue(canAtk) and canAtk == false
                and okPlr and not isSecretValue(isPlr) and isPlr == true) then
            return nil
        end
    end

    local okPLvl, rawPLvl = pcall(UnitLevel, "player")
    local playerLvl = (okPLvl and rawPLvl and not isSecretValue(rawPLvl)) and rawPLvl or 1
    if (playerLvl ~= lastPlayerLevel) then
        questDifficultyColorCache = {}
        lastPlayerLevel = playerLvl
    end

    local okLvl, rawLvl = pcall(UnitLevel, unit)
    local level = (okLvl and not isSecretValue(rawLvl)) and rawLvl or nil
    local targetLevel = (level and level > 0) and level or (playerLvl + 10)
    local cachedColor = questDifficultyColorCache[targetLevel]
    if (cachedColor == nil) then
        cachedColor = GetQuestDifficultyColor(targetLevel) or false
        questDifficultyColorCache[targetLevel] = cachedColor
    end
    return (cachedColor ~= false and cachedColor) or nil
end

local function colorizeUnitLevelLine(tooltip, unit, textLine, lineIndex)
    -- The token guard is local as well as in getHostileDifficultyColor: both
    -- UnitLevel calls on this unit below declare
    -- SecretArguments = "AllowedWhenUntainted".
    if (type(unit) == "nil" or isSecretValue(unit) or not textLine or isSecretValue(textLine) or textLine == "") then
        return textLine
    end

    local color = getHostileDifficultyColor(unit)
    if (not color) then
        return textLine
    end

    local okLvl, rawLvl = pcall(UnitLevel, unit)
    local level = (okLvl and not isSecretValue(rawLvl)) and rawLvl or nil
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
    if (not icon or isSecretValue(icon)) then
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
local function formatSpecializationText(class, specIndex, p1, p2, p3, dim, engineName, engineIcon, forcePoints)
    local specName
    if (engineName and not isSecretValue(engineName)) then
        if (engineName ~= "") then
            specName = engineName
        end
    end
    if (not specName and class and not isSecretValue(class) and specIndex and not isSecretValue(specIndex)) then
        specName = CI:GetSpecializationName(class, specIndex, true)
    end
    if (not specName or isSecretValue(specName)) then
        return nil
    end

    local iconTexture = engineIcon
    if (not iconTexture or isSecretValue(iconTexture)) then
        if (class and specIndex and not isSecretValue(class) and not isSecretValue(specIndex)) then
            iconTexture = getSpecializationIcon(class, specIndex)
        else
            iconTexture = nil
        end
    end
    local iconText = ""
    if (iconTexture and not isSecretValue(iconTexture)) then
        iconText = string.format("|T%s:14:14:0:0:64:64:4:60:4:60|t ", tostring(iconTexture))
    end
    local classColor = (class and not isSecretValue(class)) and getClassColor(class) or nil
    local coloredName
    if (dim) then
        coloredName = colorizeText(specName, 0.50, 0.50, 0.50)
    else
        coloredName = classColor and colorizeText(specName, classColor.r, classColor.g, classColor.b) or specName
    end
    local isClassicFamily = CI and CI.IsClassic and (CI:IsClassic() or CI:IsTBC() or CI:IsWotlk())
    local hasPoints = false
    if (p1 and p2 and p3 and not isSecretValue(p1) and not isSecretValue(p2) and not isSecretValue(p3)) then
        if (type(p1) == "number" and type(p2) == "number" and type(p3) == "number") then
            if (p1 > 0 or p2 > 0 or p3 > 0 or isClassicFamily or forcePoints) then
                hasPoints = true
            end
        end
    end
    if (hasPoints) then
        return string.format("%s%s [%d/%d/%d]", iconText, coloredName, p1, p2, p3)
    else
        return string.format("%s%s", iconText, coloredName)
    end
end

TT.GetFormattedSpecializationText = function(self, class, specIndex, p1, p2, p3, dim, engineName, engineIcon,
                                             forcePoints)
    return formatSpecializationText(class, specIndex, p1, p2, p3, dim, engineName, engineIcon, forcePoints)
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
                if (type(model.SetScript) == "function") then
                    pcall(model.SetScript, model, "OnModelLoaded", function(self)
                        local zoom = (TacoTipConfig and TacoTipConfig.tooltip_portrait_zoom) or 0.7
                        pcall(self.SetPortraitZoom, self, zoom)
                    end)
                end
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

-- The face ONE tooltip line should be drawn with.
--
-- applyTooltipFonts applies a single path to every line, which is right for the
-- addon's own rows but not for the client's header: a name or a guild name is
-- the hovered player's data, so it can be in a script the resolved face has no
-- glyphs for (a Russian guild name on a roman client renders one box per
-- character). textures.lua owns the coverage table and the bundled faces; this
-- only feeds it the line's text.
--
-- The text is read from the FontString, so it can be a SECRET string on Forever
-- (an item tooltip's client rows carry secret line data). `find` on a secret
-- string raises, and a raise here would abort the rest of the appearance pass
-- (portrait, border, bars) for that render, so the secrecy test comes first --
-- and a text we may not read simply keeps the resolved face.
-- Remembered script masks, per unit GUID and line index.
--
-- A restricted tooltip may not be read, but the client still DRAWS it. So the
-- mask a line carried while it was readable (a bare number, derived from text
-- the addon was allowed to read) is kept, and the restricted pass re-uses it:
-- a Cyrillic guild name keeps its glyphs in instanced combat without a single
-- secret value being touched or compared.
TT._unitLineScript = TT._unitLineScript or {}
TT._unitLineScriptCount = TT._unitLineScriptCount or 0
local UNIT_LINE_SCRIPT_CAP = 256

local function rememberUnitLineScript(guid, index, mask)
    if (type(guid) ~= "string" or type(index) ~= "number" or type(mask) ~= "number") then
        return
    end
    local store = TT._unitLineScript
    local lines = store[guid]
    if (not lines) then
        if ((TT._unitLineScriptCount or 0) >= UNIT_LINE_SCRIPT_CAP) then
            store = {}
            TT._unitLineScript = store
            TT._unitLineScriptCount = 0
        end
        lines = {}
        store[guid] = lines
        TT._unitLineScriptCount = (TT._unitLineScriptCount or 0) + 1
    end
    lines[index] = mask
end

local function unitLineScriptMasks(guid)
    if (type(guid) ~= "string") then return nil end
    local store = TT._unitLineScript
    local lines = store and store[guid]
    if (type(lines) == "table") then
        return lines
    end
    return nil
end

local function lineTooltipFont(basePath, line, index, tooltip)
    if (type(basePath) ~= "string" or basePath == "" or not line
            or type(line.GetText) ~= "function" or not TT.GetScriptFontPath) then
        return basePath
    end
    local text = line:GetText()
    if (type(text) ~= "string") then
        return basePath
    end
    local state = getTooltipState(tooltip)
    local guid = state and state.currentUnitGUID
    if (isSecretValue(text)) then
        -- Unreadable now -- instanced combat, an encounter, a secret line. Use
        -- the mask this unit's line had the last time it WAS readable. Nothing
        -- here reads or compares the secret: only a cached number and a path
        -- from the addon's own table.
        local masks = unitLineScriptMasks(guid)
        return TT.PickScriptFont(basePath, masks and masks[index] or 0)
    end
    local mask = TT.DetectScripts(text)
    if (mask ~= 0) then
        rememberUnitLineScript(guid, index, mask)
    end
    return TT.PickScriptFont(basePath, mask)
end

-- rememberedMasks: optional { [lineIndex] = scriptMask } for a tooltip whose
-- lines may not be read. In that mode no text is read at all -- the face comes
-- from the cached mask, so nothing restricted is touched.
local function applyTooltipFonts(tooltip, rememberedMasks)
    if (not tooltip) then
        return
    end
    local fontPath = (TT.GetResolvedTooltipFont and TT:GetResolvedTooltipFont())
        or (TT.GetLocaleFontPath and TT:GetLocaleFontPath())
        or TacoTipConfig.tooltip_font
        or "Fonts\\FRIZQT__.TTF"
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
            local wantFont = rememberedMasks
                and TT.PickScriptFont(fontPath, rememberedMasks[i] or 0)
                or lineTooltipFont(fontPath, left, i, tooltip)
            if (left._tacoTipFont ~= wantFont or left._tacoTipFontSize ~= lineSize) then
                local okFont = callLabeled("applyTooltipFonts", left, "SetFont", wantFont, lineSize)
                -- SetFont returns false when the path is not loaded (for
                -- example a font the client does not ship). Do not cache that
                -- as success or the line is never retried with a real face.
                if (okFont ~= false) then
                    left._tacoTipFont, left._tacoTipFontSize = wantFont, lineSize
                end
            end
        end
        if (right) then
            local wantFont = rememberedMasks
                and TT.PickScriptFont(fontPath, rememberedMasks[i] or 0)
                or lineTooltipFont(fontPath, right, i, tooltip)
            if (right._tacoTipFont ~= wantFont or right._tacoTipFontSize ~= lineSize) then
                local okFont = callLabeled("applyTooltipFonts", right, "SetFont", wantFont, lineSize)
                if (okFont ~= false) then
                    right._tacoTipFont, right._tacoTipFontSize = wantFont, lineSize
                end
            end
        end
    end
end


-- Re-font a tooltip whose text may not be read, from the masks the same unit
-- recorded while it was readable. Returns false when nothing is remembered.
-- The caller is the unreadable-header path of onTooltipSetUnit, which otherwise
-- leaves the client's own text in whatever face the pooled FontStrings happen
-- to carry.
local function applyRememberedLineFonts(tooltip, guid)
    if (not tooltip or type(guid) ~= "string" or not TT.PickScriptFont) then
        return false
    end
    local masks = unitLineScriptMasks(guid)
    if (not masks) then
        return false
    end
    applyTooltipFonts(tooltip, masks)
    return true
end
-- Reached through TT, never as a captured upvalue: onTooltipSetUnit sits on
-- Lua 5.1's 60-upvalue ceiling (the realm-row comment inside it records the
-- same constraint), and a 61st upvalue makes main.lua fail to LOAD on 5.1 and
-- luajit. TT is already captured there.
TT.ApplyRememberedLineFonts = applyRememberedLineFonts

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
    local alpha = TacoTipConfig.tooltip_border_alpha or 0.85
    if (tooltip and tooltip.NineSlice and type(tooltip.NineSlice.SetBorderColor) == "function") then
        tooltip.NineSlice:SetBorderColor(borderR, borderG, borderB, alpha)
    elseif (tooltip and type(tooltip.SetBackdropBorderColor) == "function") then
        tooltip:SetBackdropBorderColor(borderR, borderG, borderB, alpha)
    end

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

    backdrop:SetBackdropBorderColor(borderR, borderG, borderB, alpha)
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

    local r = TacoTipConfig.tooltip_border_color_r or 1
    local g = TacoTipConfig.tooltip_border_color_g or 1
    local b = TacoTipConfig.tooltip_border_color_b or 1
    local a = TacoTipConfig.tooltip_border_alpha or 0.85

    if (tooltip.NineSlice and type(tooltip.NineSlice.SetBorderColor) == "function") then
        tooltip.NineSlice:SetBorderColor(r, g, b, a)
    elseif (type(tooltip.SetBackdropBorderColor) == "function") then
        tooltip:SetBackdropBorderColor(r, g, b, a)
    end

    local backdrop = tooltip and tooltip.TacoTipBackdropFrame
    if (backdrop) then
        if (backdrop.SetBackdropBorderColor) then
            backdrop:SetBackdropBorderColor(r, g, b, a)
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
    if (not guid or isSecretValue(guid)) then return nil end
    local ownerUnit = getTooltipOwnerUnit(tooltip)
    if (ownerUnit and safeUnitExists(ownerUnit)) then
        if (safeEquals(safeUnitGUID(ownerUnit), guid)) then
            return ownerUnit
        end
    end
    if (safeEquals(safeUnitGUID("player"), guid)) then
        return "player"
    elseif (safeEquals(safeUnitGUID("mouseover"), guid)) then
        return "mouseover"
    elseif (safeEquals(safeUnitGUID("target"), guid)) then
        return "target"
    elseif (safeEquals(safeUnitGUID("pet"), guid)) then
        return "pet"
    elseif (safeEquals(safeUnitGUID("focus"), guid)) then
        return "focus"
    end
    for i = 1, 4 do
        local partyToken = "party" .. i
        if (safeUnitExists(partyToken) and safeEquals(safeUnitGUID(partyToken), guid)) then
            return partyToken
        end
    end
    for i = 1, 40 do
        local raidToken = "raid" .. i
        if (safeUnitExists(raidToken) and safeEquals(safeUnitGUID(raidToken), guid)) then
            return raidToken
        end
    end
    return nil
end

local function resolveTooltipUnit(tooltip, unit)
    if (unit and safeUnitExists(unit)) then
        if (tooltip and tooltip.IsUnit) then
            local ok, isU = pcall(tooltip.IsUnit, tooltip, unit)
            if (ok and not isSecretValue(isU) and isU == true) then
                return unit
            end
        end
        return unit
    end
    if (TooltipUtil and TooltipUtil.GetDisplayedUnit and tooltip) then
        local ok, _, dispUnit, guid = pcall(TooltipUtil.GetDisplayedUnit, tooltip)
        if (ok and dispUnit and safeUnitExists(dispUnit)) then
            return dispUnit
        elseif (ok and guid and not isSecretValue(guid)) then
            local resolved = resolveUnitTokenFromGUID(guid, tooltip)
            if (resolved) then return resolved end
        end
    end
    if (tooltip and tooltip.GetUnit) then
        local ok, _, tooltipUnit, guid = pcall(tooltip.GetUnit, tooltip)
        if (ok and tooltipUnit and safeUnitExists(tooltipUnit)) then
            if (tooltip.IsUnit) then
                local isUOk, isU = pcall(tooltip.IsUnit, tooltip, tooltipUnit)
                if (isUOk and not isSecretValue(isU) and isU == true) then
                    return tooltipUnit
                end
            else
                return tooltipUnit
            end
        elseif (ok and guid and not isSecretValue(guid)) then
            local resolved = resolveUnitTokenFromGUID(guid, tooltip)
            if (resolved) then return resolved end
        end
    end
    if (tooltip and tooltip.GetOwner) then
        local ownerUnit = getTooltipOwnerUnit(tooltip)
        if (ownerUnit and safeUnitExists(ownerUnit)) then
            return ownerUnit
        end
    end
    -- Last resort. Returning "mouseover" unconditionally is wrong whenever the
    -- tooltip is actually showing some other unit -- on the four clients that
    -- lack TooltipUtil (Classic Era, TBC, Titanforge, and possibly Forever) this
    -- branch is reached whenever GetUnit gives a stale token, and the result is
    -- the mouseover unit's class colour, portrait, GearScore and talents painted
    -- onto e.g. the target tooltip. Only accept it when the tooltip really is the
    -- mouseover tooltip.
    if (tooltip and type(tooltip.IsUnit) == "function" and safeUnitExists("mouseover")) then
        local ok, isMouseover = pcall(tooltip.IsUnit, tooltip, "mouseover")
        if (ok and not isSecretValue(isMouseover) and isMouseover == true) then
            return "mouseover"
        end
    end
    return nil
end


local function applyFrameScale(frame, scale)
    if (frame and type(frame) == "table" and frame.SetScale and frame.GetScale) then
        scale = scale or 1
        local current = frame:GetScale()
        if (not current or math.abs(current - scale) > 0.001) then
            frame:SetScale(scale)
        end
    end
end

function TT:ApplyTooltipScale()
    local scale = (TacoTipConfig and TacoTipConfig.tooltip_scale) or 1
    applyFrameScale(GameTooltip, scale)
    applyFrameScale(ItemRefTooltip, scale)
    applyFrameScale(ShoppingTooltip1, scale)
    applyFrameScale(ShoppingTooltip2, scale)
    applyFrameScale(_G["ItemRefShoppingTooltip1"], scale)
    applyFrameScale(_G["ItemRefShoppingTooltip2"], scale)
end

-- Anchors the tooltip portrait on the tooltip's free edge.
--
-- This is a function because of a modern-client ordering fact: on Retail and
-- WoW Forever the unit post-call runs BEFORE GameTooltip:Show(), so the first
-- render sees GetRight() == 0 and the side it picks is a guess. The next 0.2s
-- tick used to re-anchor to the other edge, which is the visible jump on unit
-- frames. OnShow runs before the frame is presented, so the recompute can land
-- on the first visible frame instead of one tick later.
--
-- fromShow = true forces the recompute once per show; otherwise the side is
-- cached and only a scale/invert change or an unanchored shown frame forces it.
local function anchorTooltipPortrait(tooltip, portrait, fromShow)
    if (not tooltip or not portrait) then
        return
    end
    local state = getTooltipState(tooltip)
    local portraitScale = TacoTipConfig.tooltip_portrait_scale or 1
    -- 66 x 88 (was 72 x 96). Still exact 3:4, still exact integers at every
    -- slider stop: 33x44, 66x88, 99x132, 132x176.
    local portraitW = math.floor(66 * portraitScale)
    local portraitH = math.floor(88 * portraitScale)
    local shown = (not tooltip.IsShown) or tooltip:IsShown()
    local invertSide = TacoTipConfig.tooltip_portrait_invert_side and true or false
    local cachedSide = state.portraitSide
    -- Invert is in the cache key for the same reason scale is: without it,
    -- ticking the option does nothing until the next scale change.
    local needsAnchor = (cachedSide == nil
        or portrait._tacoTipScale ~= portraitScale
        or portrait._tacoTipInvert ~= invertSide
        or (shown and not state.portraitAnchored))
    if (fromShow and shown) then
        needsAnchor = true
    end
    if (not needsAnchor) then
        return
    end
    local tooltipRight = tooltip:GetRight() or 0
    if (TacoTipConfig and TacoTipConfig.custom_pos) then
        -- Once the user has positioned their tooltip with the mover, always anchor
        -- on the right. Do not check whether it is off-screen.
        cachedSide = "right"
    else
        -- Unconfigured default (first run, docked to bottom-right corner of screen):
        -- place on the left only if placing on the right would push it off-screen.
        if (tooltipRight > 0) then
            local screenWidth = (UIParent and UIParent:GetRight())
                or (_G["GetScreenWidth"] and _G["GetScreenWidth"]()) or 1000
            local fitsRight = (tooltipRight + portraitW + 8) <= screenWidth
            cachedSide = fitsRight and "right" or "left"
        else
            -- If the frame has not laid out yet (tooltipRight == 0), preserve
            -- the previously anchored/cached side so rapid re-hover does not jump.
            cachedSide = portrait._tacoTipAnchorSide or state.portraitSide or "right"
        end
    end
    -- Inverted before the side-to-anchor mapping below, so that mapping stays
    -- in one place. Off by default, so nobody who never touches it sees change.
    if invertSide then
        cachedSide = (cachedSide == "left") and "right" or "left"
    end

    -- If already anchored to this side, scale, and invert with valid points,
    -- skip ClearAllPoints(): calling ClearAllPoints() on an active 3D PlayerModel
    -- invalidates the camera projection viewport, causing jumping / jitter on rapid re-hover.
    if (portrait._tacoTipAnchorSide == cachedSide
            and portrait._tacoTipScale == portraitScale
            and portrait._tacoTipInvert == invertSide
            and portrait.GetNumPoints and portrait:GetNumPoints() > 0) then
        state.portraitSide = cachedSide
        state.portraitAnchored = true
        return
    end

    state.portraitSide = cachedSide
    -- For custom positions, the frame anchor does not depend on measuring the right screen edge.
    -- For unconfigured default, wait until the frame is laid out (tooltipRight > 0).
    state.portraitAnchored = shown and ((TacoTipConfig and TacoTipConfig.custom_pos ~= nil) or tooltipRight > 0)
    portrait._tacoTipScale = portraitScale
    portrait._tacoTipInvert = invertSide
    portrait._tacoTipAnchorSide = cachedSide
    portrait:ClearAllPoints()
    portrait:SetSize(portraitW, portraitH)
    TT.ev.portraitAnchor = (TT.ev.portraitAnchor or 0) + 1
    if (cachedSide == "left") then
        portrait:SetPoint("TOPRIGHT", tooltip, "TOPLEFT", -8, 0)
    else
        portrait:SetPoint("TOPLEFT", tooltip, "TOPRIGHT", 8, 0)
    end
end

function TT:ApplyTooltipAppearance(tooltip, unit)
    if (not tooltip) then
        return
    end

    local scale = (TacoTipConfig and TacoTipConfig.tooltip_scale) or 1
    applyFrameScale(tooltip, scale)

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
            anchorTooltipPortrait(tooltip, portrait, false)

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
            local hidePortrait = false
            if (is3D and portrait.SetUnit) then
                local uGuid = (unit and safeUnitGUID(unit)) or nil
                local modelKey = (uGuid and not isSecretValue(uGuid)) and uGuid or unit
                if (portrait.tacoTipModelKey ~= modelKey) then
                    local prevKey = portrait.tacoTipModelKey
                    local canSet = true
                    if (type(portrait.CanSetUnit) == "function") then
                        local okCan, allowed = pcall(portrait.CanSetUnit, portrait, unit)
                        if (okCan and allowed == false) then
                            canSet = false
                        end
                    end
                    if (not canSet) then
                        -- CanSetUnit returned false (unit not stream-ready/valid):
                        -- clear any previous character mesh instead of caching the
                        -- incoming modelKey over an unrelated or empty model.
                        if (type(portrait.ClearModel) == "function") then
                            pcall(portrait.ClearModel, portrait)
                            TT.ev.portraitClearModelCalls = (TT.ev.portraitClearModelCalls or 0) + 1
                        end
                        portrait.tacoTipModelKey = nil
                        portrait.tacoTipSetRetries = nil
                        portrait._tacoTipZoom = nil
                        TT.ev.portraitCanSetFalse = (TT.ev.portraitCanSetFalse or 0) + 1
                        hidePortrait = true
                        recordPortraitTrace("canset-false", "appearance", tooltip, portrait, {
                            unit = unit, prevKey = prevKey, newKey = modelKey, outcome = "hidden",
                        })
                    else
                        -- Clear first so the previous character's mesh cannot persist
                        -- while the new one streams in (pcall: ClearModel may be absent
                        -- on some clients).
                        TT.ev.portraitSetAttempts = (TT.ev.portraitSetAttempts or 0) + 1
                        local okClear, errClear = pcall(portrait.ClearModel, portrait)
                        if (okClear) then
                            TT.ev.portraitClearModelCalls = (TT.ev.portraitClearModelCalls or 0) + 1
                        elseif (errClear) then
                            TT:RecordError("Portrait", errClear, "ClearModel")
                        end
                        local okCall, setResult = pcall(portrait.SetUnit, portrait, unit)
                        -- SetUnit reports success with a boolean, so a non-throwing
                        -- false is still a failure. Caching it as the current unit
                        -- would leave the previous character's mesh under the new
                        -- tooltip and make the retry counter unreachable.
                        if (okCall and setResult ~= false) then
                            TT.ev.portraitSetSucceeded = (TT.ev.portraitSetSucceeded or 0) + 1
                            portrait.tacoTipModelKey = modelKey
                            portrait.tacoTipSetRetries = nil
                            -- SetUnit loads a fresh mesh and the camera returns to
                            -- its default; re-apply the configured zoom after it.
                            portrait._tacoTipZoom = nil
                            recordPortraitTrace("setunit-ok", "appearance", tooltip, portrait, {
                                unit = unit, prevKey = prevKey, newKey = modelKey, outcome = "ok",
                            })
                        else
                            local retries = (portrait.tacoTipSetRetries or 0) + 1
                            portrait.tacoTipSetRetries = retries
                            TT.ev.portraitSetFailed = (TT.ev.portraitSetFailed or 0) + 1
                            if (not okCall and setResult) then
                                TT:RecordError("Portrait", setResult, "SetUnit")
                            end
                            if (retries >= 2) then
                                -- Mesh load failed or not available for this unit; stop hammering
                                -- SetUnit on every single frame/render tick for this character.
                                portrait.tacoTipModelKey = modelKey
                            else
                                portrait.tacoTipModelKey = nil
                            end
                            recordPortraitTrace("setunit-fail", "appearance", tooltip, portrait, {
                                unit = unit,
                                prevKey = prevKey,
                                newKey = portrait.tacoTipModelKey,
                                outcome = "retry-" .. tostring(retries),
                            })
                        end
                    end
                else
                    TT.ev.portraitKeyHits = (TT.ev.portraitKeyHits or 0) + 1
                end
                if (not hidePortrait) then
                    local zoom = TacoTipConfig.tooltip_portrait_zoom or 0.7
                    if (portrait._tacoTipZoom ~= zoom) then
                        pcall(portrait.SetPortraitZoom, portrait, zoom)
                        portrait._tacoTipZoom = zoom
                    end
                end
            else
                -- 2D fallback only when 3D model creation failed (portrait is a Texture).
                -- resolveTooltipUnit only returns a token that passed safeUnitExists,
                -- so it is already non-secret; SetPortraitTexture still declares
                -- SecretArguments = "AllowedWhenUntainted", so the token is tested
                -- at the call as well.
                if (type(unit) ~= "nil" and not isSecretValue(unit)) then
                    pcall(_G.SetPortraitTexture, portrait, unit)
                    TT.ev.portrait2DSets = (TT.ev.portrait2DSets or 0) + 1
                    recordPortraitTrace("set-2d", "appearance", tooltip, portrait, {
                        unit = unit, outcome = "2d",
                    })
                end
            end
            -- The portrait keeps its own alpha. It used to be slaved to
            -- tooltip:GetAlpha() every render, plus a permanent 0.05s OnUpdate
            -- that polled the same value -- and on Retail and WoW Forever that
            -- read happens before Blizzard's own Show(), so it sampled a frame
            -- that had never been presented. The portrait was set from that
            -- unusable value and then walked back up by the poll, which is what
            -- read as the portrait dropping into frame. A frame that is not
            -- shown has no meaningful alpha to copy, so it is not copied.
            if (hidePortrait) then
                if (portrait.Hide) then
                    portrait:Hide()
                end
            else
                if (portrait.SetAlpha and (not portrait.GetAlpha or portrait:GetAlpha() ~= 1)) then
                    portrait:SetAlpha(1)
                end
                if (not portrait.IsShown or not portrait:IsShown()) then
                    portrait:Show()
                end
            end
        else
            if (portrait.IsShown and portrait:IsShown()) then
                recordPortraitTrace("hide-disabled", "appearance", tooltip, portrait, {
                    unit = unit, outcome = "hidden",
                })
            end
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

-- Whether a unit's power pool should show the tooltip power bar.
--
-- On Forever and Live, UnitPowerMax is SECRET when the unit's power is
-- restricted (UnitDocumentation.lua: SecretWhenUnitPowerMaxRestricted = true).
-- A secret value cannot be compared, but the status bar's SetMinMaxValues and
-- SetValue accept secret bar values (SecretArguments = "AllowedWhenTainted"
-- with SecretAspect.BarValue), so the bar must be shown and the values passed
-- through untouched. Non-secret clients keep the original "max > 0" gate.
local function tooltipUnitHasVisiblePower(unit)
    -- UnitPowerMax declares SecretArguments = "AllowedWhenUntainted": a secret
    -- token is refused at the call itself, so it is tested here first. An
    -- unknown token reads as "no visible power", which is the same answer the
    -- refused call produced through the pcall below.
    if (type(unit) == "nil" or isSecretValue(unit) or type(UnitPowerMax) ~= "function") then
        return false
    end
    local okMax, maxPower = pcall(UnitPowerMax, unit)
    if (not okMax) then return false end
    if (isSecretValue(maxPower)) then
        return true
    end
    return maxPower ~= nil and maxPower > 0
end

-- Bounded retry gate for GearScore item data.
--
-- GetScore walks the equipped slots and, for every slot whose item data is not
-- cached, registers ContinueOnItemLoad callbacks. On the Classic family the
-- client's own AddCallback asks for that item on EVERY registration, so calling
-- GetScore on every unit render (5x/s) re-registers and re-requests the same
-- item for as long as the tooltip stays up. This gate makes one attempt, then
-- backs off 0.5s -> 1s -> 2s -> 4s -> 8s (capped) until the data arrives. A
-- completion callback or a fresh inspection resets the ladder.
--
-- It is a timestamp, not a state machine: no timer is scheduled and no work is
-- done between attempts. The next due time is checked on the next render.
do
    local GS_RETRY_FIRST = 0.5
    local GS_RETRY_MAX = 8
    local GS_RETRY_CAP = 512

    local function pruneRetryLedger(retries, count, now)
        local remaining = count or 0
        if (remaining < GS_RETRY_CAP) then
            return remaining
        end
        for k, v in pairs(retries) do
            if (type(v) ~= "table" or (now > 0 and (v.at or 0) <= now)) then
                retries[k] = nil
                remaining = math.max(remaining - 1, 0)
            end
        end
        if (remaining >= GS_RETRY_CAP) then
            local targetCount = math.floor(GS_RETRY_CAP / 2)
            for k in pairs(retries) do
                retries[k] = nil
                remaining = math.max(remaining - 1, 0)
                if (remaining <= targetCount) then break end
            end
        end
        return remaining
    end

    local function clearRetryLedger(tableKey, countKey, guid)
        if (not guid or TT.isSecretValue(guid)) then return end
        local retries = TT[tableKey]
        if (retries and retries[guid]) then
            retries[guid] = nil
            TT[countKey] = math.max((TT[countKey] or 0) - 1, 0)
        end
    end

    local function retryLedgerDue(tableKey, guid, now)
        if (not guid or TT.isSecretValue(guid) or type(now) ~= "number" or now <= 0) then
            return true
        end
        local retries = TT[tableKey]
        local entry = retries and retries[guid]
        return (not entry) or now >= entry.at
    end

    local function noteRetryLedger(tableKey, countKey, guid, now)
        if (not guid or TT.isSecretValue(guid) or type(now) ~= "number" or now <= 0) then
            return
        end
        local retries = TT[tableKey]
        if (not retries) then
            retries = {}
            TT[tableKey] = retries
            TT[countKey] = 0
        end
        local entry = retries[guid]
        if (not entry) then
            if ((TT[countKey] or 0) >= GS_RETRY_CAP) then
                TT[countKey] = pruneRetryLedger(retries, TT[countKey] or 0, now)
            end
            entry = { delay = GS_RETRY_FIRST }
            retries[guid] = entry
            TT[countKey] = (TT[countKey] or 0) + 1
        end
        entry.at = now + entry.delay
        entry.delay = math.min(entry.delay * 2, GS_RETRY_MAX)
    end

    function TT.clearGearScoreRetry(guid)
        clearRetryLedger("_gsRetry", "_gsRetryCount", guid)
    end

    function TT.gearScoreRetryDue(guid, now)
        return retryLedgerDue("_gsRetry", guid, now)
    end

    function TT.noteGearScoreRetry(guid, now)
        noteRetryLedger("_gsRetry", "_gsRetryCount", guid, now)
    end

    function TT.clearPawnRetry(guid)
        clearRetryLedger("_pawnRetry", "_pawnRetryCount", guid)
    end

    function TT.pawnRetryDue(guid, now)
        return retryLedgerDue("_pawnRetry", guid, now)
    end

    function TT.notePawnRetry(guid, now)
        noteRetryLedger("_pawnRetry", "_pawnRetryCount", guid, now)
    end
end

-- Positive-score memo. Once every equipped item's data is cached, GetScore is a
-- pure read of the cached links -- but it rebuilds 20 Item wrappers, checks 20
-- item caches and reads 18 item infos on every call, and the unit tooltip calls
-- it five times a second. The cache record's `items` table is replaced wholesale
-- on every complete inspection (LibForeverInspector.lua:3782), so its identity
-- is the invalidation key: the same table means the same gear, so the score
-- cannot have changed. The player is excluded because their inventory is read
-- live and is not in that cache at all.
local GS_SCORE_MEMO_CAP = 512

function TT.getGearScoreMemo(guid, items)
    if (not guid or TT.isSecretValue(guid) or not items) then
        return nil
    end
    local memo = TT._gsMemo
    local entry = memo and memo[guid]
    if (entry and entry.items == items and entry.score) then
        return entry.score, entry.ilvl
    end
    return nil
end

function TT.setGearScoreMemo(guid, items, score, ilvl)
    if (not guid or TT.isSecretValue(guid) or not items or type(score) ~= "number"
            or TT.isSecretValue(score) or score <= 0
            or (ilvl ~= nil and TT.isSecretValue(ilvl))) then
        return
    end
    local memo = TT._gsMemo
    if (not memo) then
        memo = {}
        TT._gsMemo = memo
        TT._gsMemoCount = 0
    end
    if (not memo[guid] and (TT._gsMemoCount or 0) >= GS_SCORE_MEMO_CAP) then
        local target = math.floor(GS_SCORE_MEMO_CAP / 2)
        local remaining = TT._gsMemoCount or 0
        for k in pairs(memo) do
            memo[k] = nil
            remaining = math.max(remaining - 1, 0)
            if (remaining <= target) then break end
        end
        TT._gsMemoCount = remaining
    end
    local entry = memo[guid]
    if (not entry) then
        TT._gsMemoCount = (TT._gsMemoCount or 0) + 1
        entry = { items = items }
        memo[guid] = entry
    elseif (entry.items ~= items) then
        entry = { items = items }
        memo[guid] = entry
    end
    entry.score = score
    entry.ilvl = ilvl
end

function TT.getPawnScoreMemo(guid, items, activeGroup)
    if (not guid or TT.isSecretValue(guid)) then
        return nil
    end
    activeGroup = activeGroup or 1
    -- Self never has an inspect-cache record, so the items-keyed memo below can
    -- never answer for the player. Keep the last live Pawn score under its own
    -- key instead; without this the line was computed on one render and then
    -- missing on the next (the blink).
    if (TT.safeEquals(guid, TT.safeUnitGUID("player"))) then
        local selfMemo = TT._selfPawnMemo
        if (selfMemo) then
            local groupMemo = selfMemo[activeGroup]
            if (groupMemo and groupMemo.pawnScore ~= nil) then
                return groupMemo.pawnScore, groupMemo.pawnSpecName, groupMemo.pawnSpecColor
            end
            if (selfMemo.pawnGroup == activeGroup and selfMemo.pawnScore ~= nil) then
                return selfMemo.pawnScore, selfMemo.pawnSpecName, selfMemo.pawnSpecColor
            end
        end
        return nil
    end
    if (not items) then
        return nil
    end
    local memo = TT._gsMemo
    local entry = memo and memo[guid]
    if (entry and entry.items == items) then
        local groupMemo = entry.pawnScores and entry.pawnScores[activeGroup]
        if (groupMemo and groupMemo.pawnScore ~= nil) then
            return groupMemo.pawnScore, groupMemo.pawnSpecName, groupMemo.pawnSpecColor
        end
        if (entry.pawnGroup == activeGroup and entry.pawnScore ~= nil) then
            return entry.pawnScore, entry.pawnSpecName, entry.pawnSpecColor
        end
    end
    return nil
end

function TT.setPawnScoreMemo(guid, items, activeGroup, pawnScore, specName, specColor)
    if (not guid or TT.isSecretValue(guid) or type(pawnScore) ~= "number"
            or TT.isSecretValue(pawnScore) or pawnScore < 0) then
        return
    end
    if (TT.isSecretValue(specName)) then specName = nil end
    if (TT.isSecretValue(specColor)) then specColor = nil end
    activeGroup = activeGroup or 1
    if (TT.safeEquals(guid, TT.safeUnitGUID("player"))) then
        TT._selfPawnMemo = TT._selfPawnMemo or {}
        TT._selfPawnMemo[activeGroup] = {
            pawnGroup = activeGroup,
            pawnScore = pawnScore,
            pawnSpecName = specName,
            pawnSpecColor = specColor,
        }
        TT._selfPawnMemo.pawnGroup = activeGroup
        TT._selfPawnMemo.pawnScore = pawnScore
        TT._selfPawnMemo.pawnSpecName = specName
        TT._selfPawnMemo.pawnSpecColor = specColor
        return
    end
    if (not items) then
        return
    end
    local memo = TT._gsMemo
    if (not memo) then
        memo = {}
        TT._gsMemo = memo
        TT._gsMemoCount = 0
    end
    if (not memo[guid] and (TT._gsMemoCount or 0) >= GS_SCORE_MEMO_CAP) then
        local target = math.floor(GS_SCORE_MEMO_CAP / 2)
        local remaining = TT._gsMemoCount or 0
        for k in pairs(memo) do
            memo[k] = nil
            remaining = math.max(remaining - 1, 0)
            if (remaining <= target) then break end
        end
        TT._gsMemoCount = remaining
    end
    local entry = memo[guid]
    if (not entry) then
        TT._gsMemoCount = (TT._gsMemoCount or 0) + 1
        entry = { items = items, pawnScores = {} }
        memo[guid] = entry
    elseif (entry.items ~= items) then
        entry = { items = items, pawnScores = {} }
        memo[guid] = entry
    end
    entry.pawnScores = entry.pawnScores or {}
    entry.pawnScores[activeGroup] = {
        pawnGroup = activeGroup,
        pawnScore = pawnScore,
        pawnSpecName = specName,
        pawnSpecColor = specColor,
    }
    entry.pawnGroup = activeGroup
    entry.pawnScore = pawnScore
    entry.pawnSpecName = specName
    entry.pawnSpecColor = specColor
end

function TT.clearGearScoreMemo(guid)
    local memo = TT._gsMemo
    if (memo and guid and memo[guid]) then
        memo[guid] = nil
        TT._gsMemoCount = math.max((TT._gsMemoCount or 0) - 1, 0)
    end
end

-- When the tooltip's owner is a Blizzard UnitFrame (PlayerFrame, TargetFrame,
-- FocusFrame, PartyMemberFrame, CompactUnitFrame), refreshing via
-- UnitFrame_UpdateTooltip(owner) preserves the post-SetUnit lines Blizzard
-- appends on Retail and WoW Forever (blank line + UNIT_POPUP_RIGHT_CLICK in
-- Blizzard_UnitFrame/Mainline/UnitFrame.lua:392-395) so an asynchronous
-- inspect or item-load completion does not make the tooltip jump by two lines
-- until the next 0.2s GameTooltip_OnUpdate tick.
local function refreshUnitTooltip(ttUnit, useTooltipUpdater)
    local owner = (GameTooltip and type(GameTooltip.GetOwner) == "function") and GameTooltip:GetOwner() or nil
    local unitUpdater = _G.UnitFrame_UpdateTooltip
    if (owner and owner.unit == ttUnit and type(unitUpdater) == "function" and owner.UpdateTooltip == unitUpdater) then
        return unitUpdater(owner)
    end
    if (useTooltipUpdater and GameTooltip.UpdateTooltip) then
        return GameTooltip:UpdateTooltip()
    end
    -- Fallthrough: no owner unit-frame updater and no engine updater. A full
    -- SetUnit is the re-drive that clears the client's own rows before the
    -- renderer rebuilds them. (Forever shares this path: its stale-row fix
    -- lives in the unit handler's header drop, which runs on every delivery,
    -- so no family needs its own re-drive shape here.)
    return GameTooltip:SetUnit(ttUnit)
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
    if (not guid or TT.isSecretValue(guid)) then return end
    TT.ev.gsCallback = (TT.ev.gsCallback or 0) + 1
    -- The data this ladder was waiting for has arrived (or the client has just
    -- finished with it); the next render starts from a clean attempt.
    TT.clearGearScoreRetry(guid)
    TT.clearPawnRetry(guid)
    TT.clearGearScoreMemo(guid)
    if (gsCallbackActive) then
        gsCallbackPending = guid
        TT.ev.gsCallbackReentrant = (TT.ev.gsCallbackReentrant or 0) + 1
        return
    end
    local ttUnit = resolveTooltipUnit(GameTooltip)
    if (not ttUnit) then
        -- An item-load completion is not a render. "The tooltip no longer
        -- shows that unit" is a normal state (the cursor moved, the tooltip
        -- hid), so it is counted separately and never as a resolution failure.
        TT.ev.gsCallbackNoUnit = (TT.ev.gsCallbackNoUnit or 0) + 1
        return
    end
    local ttGUID = safeUnitGUID(ttUnit)
    if (not safeEquals(ttGUID, guid)) then
        TT.ev.gsCallbackWrongUnit = (TT.ev.gsCallbackWrongUnit or 0) + 1
        return
    end
    gsCallbackActive = true
    -- pcall both branches and clear the guard unconditionally: this is a global
    -- callback reached from the item-load path, and a throw here would either
    -- leave the guard latched (silently killing every later callback) or
    -- surface as an unrelated error from deep inside a load handler.
    local ok, err = pcall(refreshUnitTooltip, ttUnit, true)
    if (not ok and err) then
        TT:RecordError("GSCallback", err)
    end
    gsCallbackActive = false
    local pending = gsCallbackPending
    gsCallbackPending = nil
    if (pending and not safeEquals(pending, guid)) then
        TacoTip_GSCallback(pending)
    end
end

-- Re-drives the unit tooltip that is on screen right now. Used by the Tooltip
-- Style dropdowns so a selection applies to the open tooltip immediately.
--
-- Forever-only: other families keep their existing behaviour (the option is
-- persisted and applied on the next render, exactly as before). Returns true
-- only when a Forever unit tooltip was actually rebuilt.
function TT:RefreshOpenUnitTooltip()
    if (not isForever) then
        return false
    end
    if (not (GameTooltip and GameTooltip.IsShown and GameTooltip:IsShown())) then
        return false
    end
    local unit = resolveTooltipUnit(GameTooltip)
    if (not unit) then
        local ok, _, retUnit = pcall(GameTooltip.GetUnit, GameTooltip)
        if (ok) then
            unit = retUnit
        end
    end
    if (not safeUnitExists(unit)) then
        return false
    end
    if (type(unit) ~= "string") then
        return false
    end
    local ok, err = pcall(refreshUnitTooltip, unit, true)
    if (not ok and err) then
        TT:RecordError("RefreshOpenUnitTooltip", tostring(err))
    end
    return ok
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
-- Drops the power-bar padding from one tooltip. Padding is a property of the
-- tooltip that is only meaningful while the bar is shown, so it is cleared on
-- every real teardown and whenever the bar is hidden -- and the memo is reset
-- with it, or the power-bar block's `_tacoTipPadding ~= 10` guard would skip
-- the re-apply forever (the 0.8.8 lifecycle bug).
local function clearPowerBarPadding(tooltip)
    if (not tooltip or not tooltip._tacoTipPaddingSet) then
        return
    end
    if (tooltip.ClearPadding) then
        tooltip:ClearPadding()
    elseif (tooltip.SetPadding) then
        tooltip:SetPadding(0, 0, 0, 0)
    end
    tooltip._tacoTipPaddingSet = nil
    tooltip._tacoTipPadding = nil
end

local function clearTooltipVisuals(tooltip, preservePendingItem, keepModel, reason, retainModel)
    if (not tooltip) then
        return
    end
    local state = getTooltipState(tooltip)
    -- Forever: the item post-call marks the tooltip as item content so OnShow
    -- knows not to read its tooltip info (see onTooltipShow). Every recycle
    -- clears it, so a unit, spell or map tooltip never inherits it.
    ---@class tacoTipTooltipState.itemTooltip
    state.itemTooltip = nil
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
        for i = 2, 20 do
            local leftLine = getTooltipLeftLine(tooltip, i)
            if (leftLine and leftLine._tacoTipWideAnchor) then
                leftLine._tacoTipWideAnchor = nil
                local prevLeft = getTooltipLeftLine(tooltip, i - 1)
                if (leftLine.ClearAllPoints and leftLine.SetPoint and prevLeft) then
                    leftLine:ClearAllPoints()
                    leftLine:SetPoint("TOPLEFT", prevLeft, "BOTTOMLEFT", 0, -2)
                end
            end
        end
        clearTooltipPlayerClassColor(tooltip)
        resetTooltipBorderToDefault(tooltip)
        if (tooltip.TacoTipPortrait) then
            tooltip.TacoTipPortrait:Hide()
        end
        if (tooltip.TacoTipSpecIcon) then
            tooltip.TacoTipSpecIcon:Hide()
        end
        if (tooltip == GameTooltip and TacoTipPowerBar) then
            stopPowerBarTicker()
            if (reason ~= "cleared" or not tooltip:IsShown()) then
                TacoTipPowerBar:Hide()
                clearPowerBarPadding(tooltip)
            end
        else
            clearPowerBarPadding(tooltip)
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
        local portrait3D = tooltip.TacoTipPortrait3D
        local prevKey = portrait3D.tacoTipModelKey
        local wasShown = (portrait3D.IsShown and portrait3D:IsShown() == true) or false
        if (not keepModel) then
            portrait3D:Hide()
            TT.ev.portraitModelHidden = (TT.ev.portraitModelHidden or 0) + 1
            if (not retainModel) then
                TT.ev.portraitHide = (TT.ev.portraitHide or 0) + 1
                TT.ev.portraitDestroy = (TT.ev.portraitDestroy or 0) + 1
                if (reason) then
                    TT.ev.teardownBy = TT.ev.teardownBy or {}
                    TT.ev.teardownBy[reason] = (TT.ev.teardownBy[reason] or 0) + 1
                end
                if (portrait3D.ClearModel) then
                    local okClr = pcall(portrait3D.ClearModel, portrait3D)
                    if (okClr) then
                        TT.ev.portraitClearModelCalls = (TT.ev.portraitClearModelCalls or 0) + 1
                    end
                end
                if (portrait3D.SetAlpha) then
                    portrait3D:SetAlpha(1)
                end
                portrait3D.tacoTipModelKey = nil
                portrait3D.tacoTipSetRetries = nil
                portrait3D._tacoTipZoom = nil
                if (wasShown or prevKey ~= nil) then
                    recordPortraitTrace("clear-destroy", reason, tooltip, portrait3D, {
                        prevKey = prevKey, keepModel = false, retainModel = false, outcome = "cleared",
                    })
                end
            elseif (wasShown or prevKey ~= nil) then
                recordPortraitTrace("clear-retain", reason, tooltip, portrait3D, {
                    prevKey = prevKey, keepModel = false, retainModel = true, outcome = "hidden-retained",
                })
            end
        end
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

-- Asks the client to load item data for an inspected player's cached links.
--
-- The scoring path registers ContinueOnItemLoad callbacks for every slot whose
-- item data is not cached yet, but Blizzard's ItemMixin:ContinueOnItemLoad only
-- queues the callback on ITEM_DATA_LOAD_RESULT -- it never asks the client for
-- the data (verified in the FrameXML mirror: the method is an
-- ItemEventListener registration). So for an item the client has never seen,
-- the callback can wait forever and the GearScore line never appears, even
-- though every other part of the tooltip rendered. This issues the request the
-- callbacks are waiting on, paced at the same 2 s per-item interval
-- gearscore.lua uses so a re-render loop cannot flood the item cache.
local GEAR_WARM_COOLDOWN = 2.0
local GEAR_WARM_ENTRY_CAP = 512

function TT:WarmGearItemData(guid)
    if (not guid or isSecretValue(guid)) then return false, 0 end
    if (safeEquals(guid, safeUnitGUID("player"))) then return false, 0 end
    -- Resolved at call time, not captured at load: this keeps tests able to
    -- count requests and tolerates a C_Item namespace that appears late.
    local request = _G.C_Item and _G.C_Item.RequestLoadItemDataByID
    if (type(request) ~= "function") then return false, 0 end
    if (not CI or type(CI.GetUnitData) ~= "function") then return false, 0 end
    local data = CI:GetUnitData(guid)
    local items = data and data.items
    if (type(items) ~= "table") then return false, 0 end
    local getItemInfo = (_G.C_Item and _G.C_Item.GetItemInfo) or _G.GetItemInfo
    if (type(getItemInfo) ~= "function") then return false, 0 end
    local now = (type(GetTime) == "function") and GetTime() or 0
    local warmAt = TT._gearWarmAt
    if (type(warmAt) ~= "table") then
        warmAt = {}
        TT._gearWarmAt = warmAt
        TT._gearWarmCount = 0
    elseif ((TT._gearWarmCount or 0) > GEAR_WARM_ENTRY_CAP) then
        local remaining = TT._gearWarmCount or 0
        for itemID, ts in pairs(warmAt) do
            if (type(ts) ~= "number" or (now > 0 and (now - ts) >= GEAR_WARM_COOLDOWN)) then
                warmAt[itemID] = nil
                remaining = math.max(remaining - 1, 0)
            end
        end
        if (remaining > GEAR_WARM_ENTRY_CAP) then
            local targetCount = math.floor(GEAR_WARM_ENTRY_CAP / 2)
            for itemID in pairs(warmAt) do
                warmAt[itemID] = nil
                remaining = math.max(remaining - 1, 0)
                if (remaining <= targetCount) then break end
            end
        end
        TT._gearWarmCount = remaining
    end
    local requested = 0
    for slot = 1, 18 do
        local link = items[slot]
        -- Slot 4 is the shirt: gearscore.lua skips i == 4, so its item data can
        -- never change a score and a shirt the client cannot resolve must not
        -- add a request. Slot 17 stays: GetScore scores the offhand outside the
        -- slot loop.
        if (type(link) ~= "nil" and not isSecretValue(link) and slot ~= 4) then
            -- GetItemInfo declares SecretArguments = "AllowedWhenUntainted": a
            -- secret link would be refused at the call and then raise again in
            -- the item:(%d+) match below, so the token is tested before either.
            local okInfo, info = pcall(getItemInfo, link)
            if (not okInfo or info == nil) then
                local itemID = tonumber(string.match(link, "item:(%d+)"))
                if (itemID) then
                    local last = warmAt[itemID]
                    -- last == 0 is a real stamp on clients without GetTime, so
                    -- the "not last" test cannot re-request every render there.
                    if (not last or (now > 0 and (now - last) >= GEAR_WARM_COOLDOWN)) then
                        warmAt[itemID] = now
                        TT._gearWarmCount = (TT._gearWarmCount or 0) + 1
                        pcall(request, itemID)
                        requested = requested + 1
                    end
                end
            end
        end
    end
    return requested > 0, requested
end

-- ---------------------------------------------------------------------------
-- Forever / Camelot: unit-frame scope and the player's zone row
-- ---------------------------------------------------------------------------
-- C_Map.GetBestMapForUnit is documented as "Only works for the player and
-- party members" (origin/forever MapDocumentation.lua:49-60), so the zone row
-- is drawn only where the client can actually place the unit. A target that
-- is not in the group, or any unit whose map the client cannot answer for,
-- produces no row -- never a guessed zone.
--
-- Family scope is the four unit-frame families the operator named: player,
-- target, party and raid. The owner frame's own `unit` token identifies
-- them (UnitFrame_Initialize stores it at UnitFrame.lua:30; party and raid
-- frames store it at PartyMemberFrame.lua:148 and CompactUnitFrame.lua:243),
-- so nameplates, focus, pets and target-of-target hovers are excluded even
-- when their unit is a player.
local function isForeverWatchedFrameUnit(unit)
    if (type(unit) ~= "string") then
        return false
    end
    if (unit == "player" or unit == "target") then
        return true
    end
    return string.match(unit, "^party%d+$") ~= nil or string.match(unit, "^raid%d+$") ~= nil
end

-- The target frame's token is "target"; C_Map.GetBestMapForUnit documents the
-- player and party members, and does not answer for the "target" token. When
-- the target is a group member, translate it to its own party/raid token so
-- the documented query can answer. A target that is not in the group has no
-- group token, and the client cannot place a non-group player anyway.
local function resolveGroupTokenFor(unit)
    if (not unit or isSecretValue(unit)) then
        return nil
    end
    local inParty = safeUnitInParty(unit)
    local inRaid = safeUnitInRaid(unit)
    if (not inParty and not inRaid) then
        return nil
    end
    if (inParty) then
        for i = 1, 4 do
            local token = "party" .. i
            if (safeUnitIsUnit(unit, token)) then
                return token
            end
        end
    end
    if (inRaid) then
        for i = 1, 40 do
            local token = "raid" .. i
            if (safeUnitIsUnit(unit, token)) then
                return token
            end
        end
    end
    return nil
end

local mapZoneCache = {}

-- The zone row is not drawn in combat or an instance encounter, and the client
-- refuses the map query for tainted callers in those states anyway. Skip the
-- read instead of asking and discarding the answer.
--
-- State comes from the client's own restriction API, not from a guess about the
-- zone: origin/forever RestrictedActionsDocumentation.lua:55-66 documents
-- IsAddOnRestrictionActive, and RestrictedActionsConstantsDocumentation.lua:19-33
-- gives AddOnRestrictionType.Combat = 0 and .Encounter = 1. A refused call reads
-- as "not restricted" so a client that cannot answer keeps the old behaviour;
-- the classic family has no C_RestrictedActions at all and falls back to
-- InCombatLockdown. Read-only: the add-on never defines or replaces either.
local function isUnitZoneRowRestricted()
    local restrictionTypes = Enum and Enum.AddOnRestrictionType
    if (C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive and restrictionTypes) then
        local okCombat, combatActive = pcall(C_RestrictedActions.IsAddOnRestrictionActive,
            restrictionTypes.Combat)
        if (okCombat and combatActive == true) then
            return true
        end
        local okEncounter, encounterActive = pcall(C_RestrictedActions.IsAddOnRestrictionActive,
            restrictionTypes.Encounter)
        if (okEncounter and encounterActive == true) then
            return true
        end
        return false
    end
    return (InCombatLockdown and InCombatLockdown()) and true or false
end

local function getUnitZoneName(unit)
    if (not unit or isSecretValue(unit) or not GetBestMapForUnit or not GetMapInfo) then
        return nil
    end
    if (isUnitZoneRowRestricted()) then
        return nil
    end
    local okMap, mapID = pcall(GetBestMapForUnit, unit)
    if (not okMap or not mapID or isSecretValue(mapID) or type(mapID) ~= "number") then
        return nil
    end
    local cached = mapZoneCache[mapID]
    if (cached and not isSecretValue(cached)) then
        return cached
    end
    local okInfo, mapInfo = pcall(GetMapInfo, mapID)
    if (not okInfo or type(mapInfo) ~= "table") then
        return nil
    end
    local name = mapInfo.name
    if (isSecretValue(name) or type(name) ~= "string" or name == "") then
        return nil
    end
    mapZoneCache[mapID] = name
    return name
end

-- Forever / Camelot: leave the loot-window tooltip exactly as the client
-- builds it.
--
-- GameTooltip:SetLootItem is a secure tooltip-data accessor delegate around
-- C_TooltipInfo.GetLootItem (origin/forever TooltipDataHandler.lua:495-517,
-- `SetLootItem = "GetLootItem"` at :537). The loot item's data carries secret
-- lines (the item has not been awarded yet), and the loot element re-runs its
-- own OnEnter from the item button's OnUpdate while the tooltip is owned
-- (LootFrame.lua:464-469), so that tooltip is rebuilt every frame. The game's
-- own warning is explicit: taint reaching ProcessInfo plus secret line
-- data/text can make the tooltip display no lines (GameTooltip.lua:994-1003).
-- The reported symptom is exactly the armour-type row disappearing from the
-- loot-window tooltip, so the addon must not touch that tooltip at all.
--
-- The owner is the loot element itself (LootFrameItemElementMixin:OnEnter
-- calls SetOwner(self, ...)), identified by the two slot methods it mixes in
-- rather than by reading the tooltip's tooltip-data table: that read is the
-- one Blizzard guards with securecallfunction.
-- Group loot roll items (GroupLootFrame1..4) similarly use SetLootRollItem
-- with rollID on the frame or its parent and must also stay 100% native.
local function isForeverLootTooltip(tooltip)
    if (not isForever or not tooltip) then
        return false
    end
    local owner = tooltip.GetOwner and tooltip:GetOwner()
    if (not owner or type(owner) ~= "table") then
        return false
    end
    if (type(owner.GetSlotIndex) == "function" and type(owner.GetItemSlotType) == "function") then
        return true
    end
    if (owner.rollID ~= nil) then
        return true
    end
    local parent = type(owner.GetParent) == "function" and owner:GetParent()
    if (parent and type(parent) == "table" and parent.rollID ~= nil) then
        return true
    end
    local ownerName = type(owner.GetName) == "function" and owner:GetName()
    if (ownerName and type(ownerName) == "string") then
        if (string.find(ownerName, "GroupLoot") or string.find(ownerName, "LootFrame")
                or string.find(ownerName, "BonusRoll") or string.find(ownerName, "LootHistory")
                or string.find(ownerName, "MasterLoot")) then
            return true
        end
    end
    local parentName = parent and type(parent.GetName) == "function" and parent:GetName()
    if (parentName and type(parentName) == "string") then
        if (string.find(parentName, "GroupLoot") or string.find(parentName, "LootFrame")
                or string.find(parentName, "BonusRoll") or string.find(parentName, "LootHistory")
                or string.find(parentName, "MasterLoot")) then
            return true
        end
    end
    return false
end

local function onTooltipSetUnit(tooltip, data)
    TT.ev.unitRender = (TT.ev.unitRender or 0) + 1
    noteOwnerUnitGUID(tooltip)
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
    if (not tooltipUnit and TT.tooltipDataReadable(data) and data.guid) then
        tooltipUnit = resolveUnitTokenFromGUID(data.guid, tooltip)
    end
    if (not tooltipUnit) then
        local ownerUnit = getTooltipOwnerUnit(tooltip)
        if (ownerUnit and safeUnitExists(ownerUnit)) then
            tooltipUnit = ownerUnit
        end
    end
    if (not name and tooltipUnit and type(UnitName) == "function") then
        local okN, uName = pcall(UnitName, tooltipUnit)
        if (okN and uName and not isSecretValue(uName)) then
            name = uName
        end
    end
    if (isSecretValue(name)) then
        name = nil
    end
    if (not tooltipUnit) then
        local cause = "unresolved-unit"
        if (not tooltip) then
            cause = "no-tooltip"
        elseif (TT.tooltipDataReadable(data) and data.guid) then
            cause = "unresolved-guid"
        elseif (not name) then
            cause = "no-unit-source"
        end
        -- Only a tooltip that is actually on screen is a render the player is
        -- looking at. A hidden tooltip that could not resolve is not a problem;
        -- counting it was half of the TBC false positive.
        if (tooltip and tooltip.IsShown and tooltip:IsShown()) then
            TT.ev.resolveTooltipUnitFailed = (TT.ev.resolveTooltipUnitFailed or 0) + 1
            TT.ev.resolveTooltipUnitLastCause = cause
        end
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
        local incomingGUID = (TT.tooltipDataReadable(data) and data.guid
            and not TT.isSecretValue(data.guid)) and data.guid or nil
        local changeUnproven = (incomingGUID == nil)
            or TT.safeEquals(incomingGUID, unresolvedState.currentUnitGUID)
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

    local rawGuid = (TT.tooltipDataReadable(data) and data.guid) or safeUnitGUID(tooltipUnit)
    local guid = (rawGuid and not isSecretValue(rawGuid)) and rawGuid or nil
    -- Self has no inspect-cache record: CI:GetUnitData("player") is nil, so the
    -- score memo can never supply a value. The first render registers the
    -- item-load callbacks and TacoTip_GSCallback then clears the retry gate;
    -- without this flag the re-render skipped GetScore entirely and the self
    -- tooltip stayed header-only. Self must always take the live path.
    local isSelf = safeUnitIsUnit(tooltipUnit, "player") or TT.safeEquals(guid, TT.safeUnitGUID("player"))
    -- Resolve the guid BEFORE clearing, so the clear can tell "this unit changed"
    -- from "this is the same unit being re-rendered because a GearScore item load
    -- completed". Only the former may tear down the 3D portrait.
    local previousGUID = getTooltipState(tooltip).currentUnitGUID
    -- keepModel: true means "same character, GearScore item load completing, border
    -- refresh, re-render" -- all of which must be a complete no-op for the
    -- portrait, or it hides and re-shows on an unchanged model. False (the
    -- default, and what other callers get) tears it down, which is also
    -- what a genuinely different unit needs so the previous mesh cannot persist.
    local isSame = TT.safeEquals(previousGUID, guid)
    clearTooltipVisuals(tooltip, nil, isSame, "guid-change", isSame)
    getTooltipState(tooltip).currentUnitGUID = guid
    storeTooltipPlayerClassColor(tooltip, tooltipUnit)

    if (TacoTipDragButton and TacoTipDragButton:IsShown()) then
        if (not safeUnitIsUnit(tooltipUnit, "player")) then
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

    if (CI and guid and safeUnitIsPlayer(tooltipUnit) and not safeUnitIsUnit(tooltipUnit, "player")) then
        if (CI.DoInspect) then
            local okInspect, errInspect = pcall(CI.DoInspect, CI, tooltipUnit)
            if (not okInspect and errInspect) then
                TT:RecordError("Inspect", errInspect, "DoInspect")
            end
        end
    end

    local wide_style = (TacoTipConfig.tip_style == 1 or ((TacoTipConfig.tip_style == 2 or TacoTipConfig.tip_style == 4) and IsShiftKeyDown()))
    local mini_style = (not wide_style and (TacoTipConfig.tip_style == 4 or TacoTipConfig.tip_style == 5))
    safeWipe(pooledTooltipText)
    safeWipe(pooledLinesToAdd)
    linesToAddCount = 0
    local text = pooledTooltipText
    local linesToAdd = pooledLinesToAdd
    local numLines = (tooltip and type(tooltip.NumLines) == "function") and tooltip:NumLines() or 0
    for i = 1, numLines do
        local leftLine = getTooltipLeftLine(tooltip, i)
        text[i] = leftLine and leftLine:GetText()
    end

    if (not text[1] or isSecretValue(text[1]) or text[1] == "") then
        -- The header cannot be read (instanced combat / an encounter on
        -- Forever). Nothing here may look at it, but the face this unit's lines
        -- were last drawn with is remembered, so the client's own text keeps
        -- its glyphs instead of falling back to the box-per-character roman one.
        TT.ApplyRememberedLineFonts(tooltip, guid)
        return
    end
    if (safeUnitIsPlayer(tooltipUnit) and (not text[2] or isSecretValue(text[2]) or text[2] == "")) then
        TT.ApplyRememberedLineFonts(tooltip, guid)
        return
    end

    -- Find the actual level line: players in guilds have the guild on line 2,
    -- so the level text shifts to line 3.
    local levelLineIndex = 2
    if (text[2] and not isSecretValue(text[2]) and string.find(text[2], "<.+>")) then
        if (text[3] and not isSecretValue(text[3]) and text[3] ~= "" and not string.find(text[3], "<.+>")) then
            levelLineIndex = 3
        end
    end
    text[levelLineIndex] = colorizeUnitLevelLine(tooltip, tooltipUnit, text[levelLineIndex], levelLineIndex)

    if (isForever and safeUnitIsPlayer(tooltipUnit)) then
        -- Forever owns the final player tooltip. The client contributes the
        -- name / guild / level header, which was captured above and is
        -- rewritten in place (keeping its client-set colour). Every row past
        -- the header is dropped here so a row the addon did not write in this
        -- render can never be re-emitted through the write-back below.
        --
        -- Players only. Creature tooltips carry the client's own rows past the
        -- level line -- titles, quest markers, trainer/repair tags -- and
        -- nothing in this addon re-emits them, so dropping them here emptied
        -- NPC data.
        if (numLines > levelLineIndex) then
            for i = levelLineIndex + 1, numLines do
                text[i] = nil
            end
        end
    end

    if (TacoTipConfig.show_target and safeUnitExists(tooltipUnit) and not safeUnitIsUnit(tooltipUnit, "player")) then
        local unitTarget = tooltipUnit .. "target"
        local targetName = UnitName(unitTarget)
        if (isSecretValue(targetName)) then
            targetName = _G.UNKNOWN or "Unknown"
        end

        if (targetName) then
            if (safeUnitIsUnit(unitTarget, tooltipUnit)) then
                if (wide_style) then
                    addLineDouble(L["Target"] .. ":", L["Self"], NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g,
                        NORMAL_FONT_COLOR.b,
                        HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
                else
                    addLineSingle(L["Target"] .. ": |cFFFFFFFF" .. L["Self"] .. "|r", 1, 1, 1)
                end
            elseif (safeUnitIsUnit(unitTarget, "player")) then
                if (wide_style) then
                    addLineDouble(L["Target"] .. ":", L["You"], NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g,
                        NORMAL_FONT_COLOR.b, 1, 1, 0)
                else
                    addLineSingle(L["Target"] .. ": |cFFFFFF00" .. L["You"] .. "|r", 1, 1, 1)
                end
            elseif (safeUnitIsPlayer(unitTarget)) then
                local classc
                if (TacoTipConfig.color_class) then
                    -- UnitClass is SecretArguments="AllowedWhenUntainted" and
                    -- SecretWhenUnitIdentityRestricted: on a restricted unit the
                    -- class token comes back secret, so `if (targetClass)` is a
                    -- boolean test on a secret value and throws. Guard the call
                    -- AND the answer; getClassColor re-checks, but it must not be
                    -- handed a secret in the first place.
                    local okClass, _, targetClass = pcall(UnitClass, unitTarget)
                    if (okClass and not isSecretValue(targetClass)
                            and type(targetClass) == "string") then
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
            elseif (safeUnitIsUnit(unitTarget, "pet") or isOtherPlayersPet(unitTarget)) then
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
            -- Both group tests go through the secret-safe helpers: UnitInRaid is
            -- SecretWhenUnitIdentityRestricted and UnitInParty takes a unit token
            -- under SecretArguments = "AllowedWhenUntainted", so a bare call can
            -- hand tainted code an error instead of an answer. A group answer the
            -- client will not give reads as false.
            if (inGroup and (safeUnitInRaid(tooltipUnit) or safeUnitInParty(tooltipUnit))) then
                if (GetBestMapForUnit) then
                    local okU, unitMap = pcall(GetBestMapForUnit, tooltipUnit)
                    local okP, playerMap = pcall(GetBestMapForUnit, "player")
                    if (okU and okP and unitMap and playerMap and not isSecretValue(unitMap) and not isSecretValue(playerMap)) then
                        if (not safeEquals(unitMap, playerMap)) then
                            inSameMap = false
                        end
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

    if (safeUnitIsPlayer(tooltipUnit)) then
        local okC, rawLocClass, rawClass = pcall(UnitClass, tooltipUnit)
        local okR, rawLocRace = pcall(UnitRace, tooltipUnit)
        local okL, rawLevel = pcall(UnitLevel, tooltipUnit)
        local localizedClass = (okC and not isSecretValue(rawLocClass)) and rawLocClass or nil
        local class = (okC and not isSecretValue(rawClass)) and rawClass or nil
        local localizedRace = (okR and not isSecretValue(rawLocRace)) and rawLocRace or nil
        local level = (okL and not isSecretValue(rawLevel)) and rawLevel or nil

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
            local rawGName, rawGRank = GetGuildInfo(tooltipUnit)
            guildName = not isSecretValue(rawGName) and rawGName or nil
            guildRankName = not isSecretValue(rawGRank) and rawGRank or nil
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

        local levelStr = (level and not isSecretValue(level) and level > 0) and tostring(level) or "??"
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

        safeWipe(pooledPlayerText)
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
            if (tooltip) then tooltip.TacoTipGuildLineIndex = 2 end
            if (tooltip) then tooltip.TacoTipLevelColorLineIndex = 3 end
            -- Ownership proof for the clears above: without it they blank line
            -- 2/3 unconditionally and destroy any other addon's line that has
            -- shifted into that slot.
            if (tooltip) then tooltip.TacoTipGuildLineText = newText[2] end
            if (tooltip) then tooltip.TacoTipLevelColorLineText = levelLine end
        else
            newText[2] = levelLine
            if (tooltip) then tooltip.TacoTipGuildLineIndex = nil end
            if (tooltip) then tooltip.TacoTipLevelColorLineIndex = 2 end
            if (tooltip) then tooltip.TacoTipLevelColorLineText = levelLine end
        end

        text = newText

        -- Realm row: "is this unit on a different server than me?" -- answered
        -- only when the client actually answers.
        --
        -- UnitIsSameServer declares SecretArguments = "AllowedWhenUntainted"
        -- (UnitDocumentation.lua:2350-2361 on origin/forever), so a bare call from
        -- this tainted tooltip path can raise instead of returning a bool. The
        -- result carries no SecretWhen annotation; the ARGUMENT is the hazard.
        --
        -- Unknown reads as "not known to be different", so no realm row is drawn.
        -- That is the same rule the zone row follows: a unit the client cannot
        -- place gets no row, never a guessed one.
        --
        -- Deliberately INLINE and not a file-local helper: onTooltipSetUnit is
        -- already at Lua 5.1's 60-upvalue ceiling (a 61st makes main.lua fail to
        -- load with "function at line ... has more than 60 upvalues" on 5.1 and
        -- luajit, while 5.4 keeps working -- so the breakage is client-family
        -- selective and easy to miss). Everything used here is already captured.
        local differentServer = false
        -- GATED OFF on WoW Forever. Camelot has one realm per type (PvE / PvP /
        -- RP-PvP) and no connected realms: every player a tooltip can describe is
        -- already on your own server, so a "from another server" row cannot be
        -- true there and must never be drawn. Operator observation, 2026-11-10 --
        -- which outranks the mirror. This also stops a spurious row if
        -- UnitIsSameServer ever disagrees on that family.
        if (TacoTipConfig.show_realm and not isForever and safeUnitIsPlayer(tooltipUnit)
                and type(_G.UnitIsSameServer) == "function" and not isSecretValue(tooltipUnit)) then
            local okSame, same = pcall(_G.UnitIsSameServer, tooltipUnit)
            differentServer = okSame and not isSecretValue(same) and same == false
        end
        if (differentServer) then
            local okRealm, _, realm = pcall(UnitName, tooltipUnit)
            if (okRealm and realm and not isSecretValue(realm) and realm ~= "") then
                if (wide_style) then
                    addLineDouble((L["Realm"] or "Realm") .. ":", realm, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g,
                        NORMAL_FONT_COLOR.b, HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
                else
                    addLineSingle(string.format("%s: |cFFFFFFFF%s|r", L["Realm"] or "Realm", realm), 1, 1, 1)
                end
            end
        end
        if (TacoTipConfig.show_honor_rank) then
            local okPVP, pvpName = pcall(UnitPVPName, tooltipUnit)
            -- UnitPVPName returns a non-nil string that may be secret, so the
            -- secrecy test is its own step before any comparison runs.
            if (okPVP and pvpName and not isSecretValue(pvpName)) then
                if (pvpName ~= "" and not safeEquals(pvpName, name)) then
                    if (wide_style) then
                        addLineDouble((L["Honor Rank"] or "Honor Rank") .. ":", pvpName, NORMAL_FONT_COLOR.r,
                            NORMAL_FONT_COLOR.g,
                            NORMAL_FONT_COLOR.b, HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
                    else
                        addLineSingle(string.format("%s: |cFFFFFFFF%s|r", L["Honor Rank"] or "Honor Rank", pvpName), 1, 1,
                            1)
                    end
                end
            end
        end
        local nameLineIcons = ""
        if (TacoTipConfig.show_pvp_icon and safeUnitIsPlayer(tooltipUnit) and safeUnitIsPVP(tooltipUnit)) then
            nameLineIcons = nameLineIcons .. PVP_FLAG_ICON_SPACED
            for i = 2, numLines do
                if (text[i] and not isSecretValue(text[i])) then
                    text[i] = string.gsub(text[i], "PvP", "", 1)
                end
            end
        end
        if (TacoTipConfig.show_team and type(UnitFactionGroup) == "function"
                and not isSecretValue(tooltipUnit)) then
            -- UnitFactionGroup takes a cstring under SecretArguments =
            -- "AllowedWhenUntainted", so a secret token is refused. pcall would
            -- swallow that, but the row would then be retried and re-refused on
            -- every render of a restricted unit; testing the token first says
            -- "no faction icon" once, which is the truth.
            local okFact, faction = pcall(UnitFactionGroup, tooltipUnit)
            if (okFact and faction and not isSecretValue(faction)) then
                if (faction == "Horde") then
                    nameLineIcons = nameLineIcons .. HORDE_ICON_SPACED
                elseif (faction == "Alliance") then
                    nameLineIcons = nameLineIcons .. ALLIANCE_ICON_SPACED
                end
            end
        end
        if (TacoTipConfig.show_class_icon and safeUnitIsPlayer(tooltipUnit)) then
            local okClass, _, classFile = pcall(UnitClass, tooltipUnit)
            if (okClass and classFile and not isSecretValue(classFile)) then
                local iconMarkup = getClassIconMarkup(classFile)
                if (iconMarkup and iconMarkup ~= "") then
                    nameLineIcons = nameLineIcons .. " " .. iconMarkup
                end
            end
        end
        if (TacoTipConfig.show_role_icon and safeUnitIsPlayer(tooltipUnit) and type(IsInGroup) == "function" and IsInGroup()) then
            local okRole, role = pcall(UnitGroupRolesAssigned, tooltipUnit)
            if (okRole and role and not isSecretValue(role)) then
                if (role ~= "NONE") then
                    local roleIcon = ROLE_ICONS[role] or ROLE_ICONS.DPS
                    nameLineIcons = nameLineIcons .. roleIcon
                end
            end
        end
        if (nameLineIcons ~= "" and text[1] and not isSecretValue(text[1])) then
            text[1] = text[1] .. nameLineIcons
        end
        if (isForever) then
            -- Talents are not rendered on Forever. Clear any overlay an older
            -- build may have left behind so no icon survives either.
            applySpecializationIcon(tooltip, nil)
        end
        if (not TacoTipConfig.hide_in_combat or not InCombatLockdown()) then
            if (TacoTipConfig.show_separators) then
                if (wide_style) then
                    addLineDouble(" ", " ", GRAY_FONT_COLOR.r, GRAY_FONT_COLOR.g, GRAY_FONT_COLOR.b, GRAY_FONT_COLOR.r,
                        GRAY_FONT_COLOR.g, GRAY_FONT_COLOR.b)
                else
                    addLineSingle(SEPARATOR_LINE, GRAY_FONT_COLOR.r, GRAY_FONT_COLOR.g,
                        GRAY_FONT_COLOR.b)
                end
            end
            if (TacoTipConfig.show_talents and not isForever) then
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
            if (TacoTipConfig.show_talents and isForever) then
                -- Forever / Camelot: deliberately the TBC shape (the tree with
                -- the most points plus [p1/p2/p3]), not the Retail spec name.
                -- The data comes from the library's Camelot path; when it cannot
                -- answer, no line is drawn and nothing else changes. The gate
                -- above stays exactly as it was -- this is a separate branch.
                local foreverTalents = CI and CI.GetForeverTalentData
                    and CI:GetForeverTalentData(tooltipUnit) or nil
                if (foreverTalents and foreverTalents.entries and #foreverTalents.entries > 0) then
                    local activeGroup = foreverTalents.active or 1
                    local ordered = {}
                    for _, entry in ipairs(foreverTalents.entries) do
                        if (entry.index == activeGroup) then
                            ordered[#ordered + 1] = entry
                        end
                    end
                    for _, entry in ipairs(foreverTalents.entries) do
                        if (entry.index ~= activeGroup) then
                            ordered[#ordered + 1] = entry
                        end
                    end
                    for i, entry in ipairs(ordered) do
                        -- forcePoints keeps the [0/0/0] template visible before
                        -- the first point is spent, like the TBC reference.
                        local specText = formatSpecializationText(class, entry.index, entry.p1, entry.p2,
                            entry.p3, i > 1, entry.name, entry.icon, true)
                        if (specText) then
                            if (i > 1) then
                                if (wide_style) then
                                    addLineDouble(" ", specText, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g,
                                        NORMAL_FONT_COLOR.b, 1, 1, 1)
                                else
                                    addLineSingle(string.format("|c00000000%s: |r%s", L["Talents"], specText), 1, 1, 1)
                                end
                            else
                                if (wide_style) then
                                    addLineDouble(L["Talents"] .. ":", specText, NORMAL_FONT_COLOR.r,
                                        NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, 1, 1, 1)
                                else
                                    addLineSingle(string.format("%s: %s", L["Talents"], specText), 1, 1, 1)
                                end
                            end
                        end
                    end
                end
            end
            if (TacoTipConfig.show_separators) then
                if (wide_style) then
                    addLineDouble(" ", " ", GRAY_FONT_COLOR.r, GRAY_FONT_COLOR.g, GRAY_FONT_COLOR.b, GRAY_FONT_COLOR.r,
                        GRAY_FONT_COLOR.g, GRAY_FONT_COLOR.b)
                else
                    addLineSingle(SEPARATOR_LINE, GRAY_FONT_COLOR.r, GRAY_FONT_COLOR.g,
                        GRAY_FONT_COLOR.b)
                end
            end
            local miniText = ""
            local needGsScore = TacoTipConfig.show_gs_player and true or false
            local needPawnScore = (isPawnLoaded and TT_PAWN and TT_PAWN.GetScore and TacoTipConfig.show_pawn_player)
                and true or false
            local scoreData, items, scoreNow, retryDue, pawnDue
            local warmedThisRender = false
            if ((needGsScore or needPawnScore) and guid) then
                scoreData = (CI and type(CI.GetUnitData) == "function") and CI:GetUnitData(guid) or nil
                items = scoreData and scoreData.items or nil
                scoreNow = (type(GetTime) == "function") and GetTime() or 0
                if (needGsScore) then
                    retryDue = TT.gearScoreRetryDue(guid, scoreNow)
                end
                if (needPawnScore) then
                    pawnDue = TT.pawnRetryDue(guid, scoreNow)
                end
            end
            if (needGsScore) then
                local gearscore, avg_ilvl = TT.getGearScoreMemo(guid, items)
                if (not gearscore) then
                    gearscore, avg_ilvl = 0, 0
                    if (retryDue or isSelf) then
                        gearscore, avg_ilvl = GearScore:GetScore(guid, retryDue)
                        if (gearscore > 0) then
                            TT.clearGearScoreRetry(guid)
                            if (not isSelf) then
                                TT.setGearScoreMemo(guid, items, gearscore, avg_ilvl)
                            end
                        else
                            -- GetScore just registered the load callbacks for every
                            -- uncached slot; ask for the data too, then let the
                            -- callback re-drive this render. The gate above keeps a
                            -- stationary hover from re-registering on every render.
                            TT.noteGearScoreRetry(guid, scoreNow)
                            TT:WarmGearItemData(guid)
                            warmedThisRender = true
                        end
                    end
                end
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
            if (needPawnScore) then
                local activeGroup = (CI and CI.GetActiveTalentGroup and CI:GetActiveTalentGroup(guid)) or 1
                local pawnScore, specName, specColor = TT.getPawnScoreMemo(guid, items, activeGroup)
                if (pawnScore == nil) then
                    pawnScore, specName, specColor = 0, nil, nil
                    if (pawnDue or isSelf) then
                        -- Pawn is an external addon. A throw here used to abort
                        -- the whole render before the write-back, taking the
                        -- already-queued GearScore/iLvl lines with it; isolate it.
                        local pawnOk, pScore, pSpec, pColor, pReady = pcall(TT_PAWN.GetScore, TT_PAWN,
                            guid, not needGsScore, activeGroup)
                        if (pawnOk) then
                            pawnScore, specName, specColor = pScore, pSpec, pColor
                            if (type(pawnScore) ~= "number") then pawnScore = 0 end
                        else
                            TT:RecordError("Pawn", pScore, "GetScore")
                            pawnScore = 0
                            pReady = false
                        end
                        if (type(pawnScore) == "number" and pawnScore > 0) then
                            TT.clearPawnRetry(guid)
                            TT.setPawnScoreMemo(guid, items, activeGroup, pawnScore, specName, specColor)

                            -- Dual-spec pre-calculation: if the character has a secondary spec group,
                            -- pre-compute and memoize it without callbacks so switching specs is instantaneous.
                            local numGroups = (CI and CI.GetNumSpecGroups and CI:GetNumSpecGroups(guid)) or 1
                            if (numGroups > 1 and type(TT_PAWN.GetScore) == "function") then
                                local altGroup = (activeGroup == 1) and 2 or 1
                                local altScore = TT.getPawnScoreMemo(guid, items, altGroup)
                                if (altScore == nil) then
                                    local okAlt, aScore, aSpec, aColor, aReady = pcall(TT_PAWN.GetScore, TT_PAWN,
                                        guid, false, altGroup)
                                    if (okAlt and aScore and aScore > 0) then
                                        TT.setPawnScoreMemo(guid, items, altGroup, aScore, aSpec, aColor)
                                    elseif (okAlt and aReady == true) then
                                        TT.setPawnScoreMemo(guid, items, altGroup, 0, aSpec or "", aColor or "|cffffffff")
                                    end
                                end
                            end
                        elseif (pReady == false) then
                            TT.notePawnRetry(guid, scoreNow)
                            if (not warmedThisRender) then
                                TT:WarmGearItemData(guid)
                            end
                        else
                            -- All items were cached locally, but Pawn produced 0 (e.g. no scale for class/spec).
                            -- Memoize 0 so we don't re-run the 18-slot check on every tooltip render tick!
                            TT.clearPawnRetry(guid)
                            TT.setPawnScoreMemo(guid, items, activeGroup, 0, specName or "", specColor or "|cffffffff")
                        end
                    end
                end
                if (pawnScore and pawnScore > 0) then
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
            -- Only Retail has achievement points for now. The options
            -- toggle is disabled elsewhere, but a saved true value must not
            -- leak a row onto a client that does not render it.
            if (TacoTipConfig.show_achievement_points and isRetail) then
                local achi_pts
                if (CI and CI.GetTotalAchievementPoints) then
                    achi_pts = CI:GetTotalAchievementPoints(guid)
                end
                if (not achi_pts and GetTotalAchievementPoints and TT.safeEquals(guid, TT.safeUnitGUID("player"))) then
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
            -- Forever / Camelot: the hovered player's zone, at the bottom of the tooltip below Pawn.
            -- Gated on the four unit-frame families (see isForeverWatchedFrameUnit)
            -- and on the client answering C_Map.GetBestMapForUnit; a unit the client
            -- cannot place produces no row. The map query uses the OWNER frame's unit
            -- token: the tooltip's resolved token is often "mouseover", which the
            -- client does not answer for (C_Map.GetBestMapForUnit documents the player
            -- and party members only, MapDocumentation.lua:49-60). The tooltip unit is
            -- the fallback. The label is the client's own localized ZONE string, so no
            -- locale key is invented here.
            local zoneOwnerUnit = getTooltipOwnerUnit(tooltip)
            if (isForever and isForeverWatchedFrameUnit(zoneOwnerUnit)) then
                local zoneUnit = zoneOwnerUnit
                if (zoneOwnerUnit == "target") then
                    zoneUnit = resolveGroupTokenFor(tooltipUnit) or zoneOwnerUnit
                end
                local zoneName = getUnitZoneName(zoneUnit) or getUnitZoneName(zoneOwnerUnit)
                    or getUnitZoneName(tooltipUnit)
                if (zoneName and not isSecretValue(zoneName)) then
                    local zoneLabel = (ZONE and not isSecretValue(ZONE)) and ZONE or "Zone"
                    if (wide_style) then
                        addLineDouble(zoneLabel .. ":", zoneName, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g,
                            NORMAL_FONT_COLOR.b, HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g,
                            HIGHLIGHT_FONT_COLOR.b)
                    else
                        addLineSingle(string.format("%s: |cFFFFFFFF%s|r", zoneLabel, zoneName), 1, 1, 1)
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
                if (tooltip) then tooltip:AddLine(text[i], 1, 1, 1) end
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
            if (not v) then break end
            if (v.isDouble) then
                if (tooltip) then tooltip:AddDoubleLine(v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8]) end
            else
                if (tooltip) then tooltip:AddLine(v[1], v[2] or 1, v[3] or 1, v[4] or 1) end
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
                if (nextLeft.ClearAllPoints) then
                    nextLeft:ClearAllPoints()
                end
                nextLeft:SetPoint("TOPLEFT", anchorLine, "BOTTOMLEFT", 0, -2)
                nextLeft._tacoTipWideAnchor = anchorLine
            end
        end
    else
        for i = 1, linesToAddCount do
            local v = linesToAdd[i]
            if (not v) then break end
            -- The record shape decides where the colours live: addLineDouble
            -- keeps the right-hand text in [2] and its colours in [3]..[8],
            -- addLineSingle keeps its colours in [2]..[4]. Reading a double
            -- record as a single one therefore hands the right-hand TEXT to a
            -- colour parameter, which the C API refuses.
            --
            -- Testing the flag is not enough on its own either: a record that
            -- matches neither shape must still never reach SetTextColor /
            -- AddLine as a string, so every channel is coerced.
            local txt, r, g, b
            if (v.isDouble) then
                -- Non-wide tooltips have no right column; render the double
                -- record as a single concatenated line instead of AddDoubleLine.
                txt = tostring(v[1])
                if (v[2] ~= nil and v[2] ~= "") then
                    txt = txt .. "  " .. tostring(v[2])
                end
                r, g, b = tonumber(v[3]), tonumber(v[4]), tonumber(v[5])
            else
                txt = v[1]
                r, g, b = tonumber(v[2]), tonumber(v[3]), tonumber(v[4])
            end
            if (not (r and g and b)) then
                r, g, b = 1, 1, 1
            end
            if (n < numLines) then
                n = n + 1
                local left = getTooltipLeftLine(tooltip, n)
                if (left) then
                    left:SetTextColor(r, g, b)
                    left:SetText(txt)
                end
            elseif (tooltip) then
                tooltip:AddLine(txt, r, g, b)
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
                    local unit = u or resolveTooltipUnit(GameTooltip) or self._tacoTipUnit
                    -- UnitPowerType / UnitPowerMax / UnitPower all declare
                    -- SecretArguments = "AllowedWhenUntainted": the token is
                    -- tested here, before any of the three is called, and
                    -- safeUnitExists repeats that test for the existence answer.
                    if (type(unit) ~= "nil" and not isSecretValue(unit) and safeUnitExists(unit)) then
                        local okType, _, power = pcall(UnitPowerType, unit)
                        local color = (okType and power and not isSecretValue(power) and PowerBarColor and PowerBarColor[power]) or
                            FALLBACK_POWER_COLOR
                        self:SetStatusBarColor(color.r or 0, color.g or 0, color.b or 1)
                        local okMax, max = pcall(UnitPowerMax, unit)
                        local okCur, cur = pcall(UnitPower, unit)
                        if (okMax and type(max) ~= "nil") then
                            self:SetMinMaxValues(0, max)
                        end
                        if (okCur and type(cur) ~= "nil") then
                            self:SetValue(cur)
                        end
                        if (self.Text) then
                            if (isSecretValue(cur) or isSecretValue(max)) then
                                self.Text:SetText("")
                            elseif (type(cur) == "number" and type(max) == "number") then
                                self.Text:SetText(string.format("%d / %d", cur, max))
                            end
                        end
                    else
                        if (not GameTooltip or not GameTooltip:IsShown()) then
                            self:Hide()
                            stopPowerBarTicker()
                            clearPowerBarPadding(GameTooltip)
                        end
                    end
                end
            end)

            TacoTipPowerBar:SetScript("OnEvent", function(self, event, unit)
                if (not self:IsShown()) then
                    return
                end
                local ttUnit = resolveTooltipUnit(GameTooltip)
                if (unit and ttUnit and safeUnitIsUnit(unit, ttUnit)) then
                    self:Update(unit)
                end
            end)
        end
        if (tooltipUnitHasVisiblePower(tooltipUnit)) then
            -- Re-anchoring is two SetPoint calls, and this runs on every render.
            -- The anchors only move when the HP bar's own presence flips, so the
            -- offset is remembered on the bar and compared, the same shape as
            -- the tooltip's own anchors a few lines below.
            local barOffsetY = (TacoTipConfig.show_hp_bar and -9) or -1
            if (TacoTipPowerBar._tacoTipAnchorY ~= barOffsetY) then
                TacoTipPowerBar:SetPoint("TOPLEFT", GameTooltip, "BOTTOMLEFT", 2, barOffsetY)
                TacoTipPowerBar:SetPoint("TOPRIGHT", GameTooltip, "BOTTOMRIGHT", -2, barOffsetY)
                TacoTipPowerBar._tacoTipAnchorY = barOffsetY
            end
            -- Update is installed with rawset on the frame a few lines above,
            -- so a static analyser still reads TacoTipPowerBar as a bare
            -- StatusBar and calls the method undefined. The cast is only there
            -- to make that rawset method visible; the runtime object is the
            -- same either way.
            local powerBar = TacoTipPowerBar --[[@as any]]
            if (type(powerBar.Update) == "function") then
                powerBar:Update(tooltipUnit)
            end
            TacoTipPowerBar:Show()
            startPowerBarTicker()
            if (TacoTipPowerBar._tacoTipUnit ~= tooltipUnit) then
                if (TacoTipPowerBar.RegisterUnitEvent) then
                    pcall(TacoTipPowerBar.RegisterUnitEvent, TacoTipPowerBar, "UNIT_POWER_UPDATE", tooltipUnit)
                    pcall(TacoTipPowerBar.RegisterUnitEvent, TacoTipPowerBar, "UNIT_MAXPOWER", tooltipUnit)
                    pcall(TacoTipPowerBar.RegisterUnitEvent, TacoTipPowerBar, "UNIT_DISPLAYPOWER", tooltipUnit)
                else
                    TacoTipPowerBar:RegisterEvent("UNIT_POWER_UPDATE")
                    TacoTipPowerBar:RegisterEvent("UNIT_MAXPOWER")
                    TacoTipPowerBar:RegisterEvent("UNIT_DISPLAYPOWER")
                end
                TacoTipPowerBar._tacoTipUnit = tooltipUnit
            end
            clearPowerBarPadding(tooltip)
        else
            TacoTipPowerBar:Hide()
            stopPowerBarTicker()
            clearPowerBarPadding(tooltip)
        end
    elseif (TacoTipPowerBar) then
        TacoTipPowerBar:Hide()
        stopPowerBarTicker()
        clearPowerBarPadding(tooltip)
    end

    -- Unconditional in the old code: not even a capability check, let alone a
    -- value comparison, on a path that runs at the end of every render.
    if (tooltip and tooltip.SetClampRectInsets and not (type(InCombatLockdown) == "function" and InCombatLockdown())) then
        if (tooltip._tacoTipClampBottom ~= 15) then
            pcall(tooltip.SetClampRectInsets, tooltip, 0, 0, 15, 15)
            tooltip._tacoTipClampBottom = 15
        end
    end

    if (tooltip and tooltip.SetMinimumWidth) then
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

local function resolveTooltipItem(tooltip, data, payloadOnly)
    -- payloadOnly is the data-pipeline client (Forever). The post-call payload
    -- is the client's sanctioned hand-off: the secure delegate behind the
    -- accessor strips taint from it, so we forward it rather than re-derive
    -- anything. `GetItem` / `GetDisplayedItem` are tooltip-INFO reads, and
    -- Blizzard's own comment says reading that from a tainted hook can carry
    -- taint into ProcessInfo, which makes a tooltip with secret line data
    -- display no lines (GameTooltip.lua:994-1003). A pipeline client always
    -- has the payload, so the reads are skipped there; the classic families
    -- have no payload and keep both reads byte-identical.
    if (not payloadOnly and tooltip and tooltip.GetItem) then
        local ok, _, itemLink = pcall(tooltip.GetItem, tooltip)
        if (ok and itemLink and not isSecretValue(itemLink)) then return itemLink end
    end
    if (not payloadOnly and TooltipUtil and TooltipUtil.GetDisplayedItem and tooltip) then
        local ok, _, dispLink = pcall(TooltipUtil.GetDisplayedItem, tooltip)
        if (ok and dispLink and not isSecretValue(dispLink)) then return dispLink end
    end
    if (TT.tooltipDataReadable(data)) then
        -- `hyperlink` is what the post-call actually supplies for an item, so
        -- this is the branch that fires in practice on Retail / WoW Forever.
        if (data.hyperlink and not isSecretValue(data.hyperlink)) then return data.hyperlink end
        if (data.hyperlink) then
            -- A link the client marked secret: dropped before any C_Item call,
            -- and counted so /tt diag can say this is what happened.
            TT.ev.itemSecretLink = (TT.ev.itemSecretLink or 0) + 1
            TT:NoteSecretRefusal("item-link")
        end
        -- GetItemLinkByGUID is documented only on Forever and Retail; on the
        -- Classic branches this whole arm is skipped.
        if (data.guid and not isSecretValue(data.guid) and C_Item and C_Item.GetItemLinkByGUID) then
            local ok, link = pcall(C_Item.GetItemLinkByGUID, data.guid)
            -- itemLink is documented Nilable; type() answers "is nil" without
            -- comparing a value that can also arrive secret.
            if (ok and type(link) ~= "nil" and not isSecretValue(link)) then return link end
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
    -- Forever / Camelot: the loot-window tooltip is secret tooltip data that
    -- the client rebuilds every frame (see isForeverLootTooltip). Any addon
    -- line or restyle applied there can drop the client's own secret rows, so
    -- this hook must leave that tooltip byte-identical to what the client
    -- built. Returning before clearTooltipVisuals also keeps the per-frame
    -- work off a tooltip that is rebuilt many times per second.
    if (isForeverLootTooltip(self)) then
        return
    end
    clearTooltipVisuals(self, nil, nil, "item")

    local state = getTooltipState(self)
    -- Diagnostics for the item path (see /tt diag). Cheap inline counters, the
    -- same shape as TT.ev elsewhere: no allocation beyond the table field, no
    -- client read, nothing that can perturb the render being measured.
    local ev = TT.ev
    ev.itemHook = (ev.itemHook or 0) + 1
    local rowsBefore = (type(self.NumLines) == "function") and self:NumLines() or 0
    local payloadReadable
    if (data == nil) then
        ev.itemPayloadMissing = (ev.itemPayloadMissing or 0) + 1
    else
        payloadReadable = TT.tooltipDataReadable(data)
        if (not payloadReadable) then
            -- The client supplied a payload we are not allowed to index (a
            -- secret table). Rows are skipped rather than read; this counter is
            -- the one a user report needs, because it says whether their
            -- tooltip data was secret at that moment.
            ev.itemPayloadUnreadable = (ev.itemPayloadUnreadable or 0) + 1
            TT:NoteSecretRefusal("tooltip-data")
        end
    end
    -- Forever / Camelot: remember that this tooltip is ITEM content. The
    -- OnShow hook runs right after this post-call and must not read the item
    -- tooltip's info (see resolveTooltipItem and onTooltipShow); this marker is
    -- how it knows, without a tooltip-info read of its own.
    if (isForever) then
        state.itemTooltip = true
    end

    local itemLink = resolveTooltipItem(self, data, isForever)
    if (itemLink == nil) then
        ev.itemNoLink = (ev.itemNoLink or 0) + 1
    end
    if (itemLink and not isSecretValue(itemLink)) then
        state.currentItemLink = itemLink
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
    local isEquippable = false
    if (itemLink and not isSecretValue(itemLink) and (TacoTipConfig.show_item_level or TacoTipConfig.show_gs_items)
            and type(IsEquippableItem) == "function") then
        local okEq, resEq = pcall(IsEquippableItem, itemLink)
        if (okEq and not isSecretValue(resEq) and resEq == true) then
            isEquippable = true
        elseif (not okEq) then
            -- IsEquippableItem is AllowedWhenUntainted: a refusal here is the
            -- argument being secret, not "not equippable". Count it.
            TT:NoteSecretRefusal("IsEquippableItem")
        end
    end
    if (isEquippable) then
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
        local itemInfo = {}
        if (type(getItemInfoFn) == "function") then
            local okInfo, i1, i2, i3, i4, i5, i6, i7, i8, i9, i10, i11, i12, i13, i14 = pcall(getItemInfoFn, itemLink)
            if (okInfo and not isSecretValue(i1)) then
                itemInfo = { i1, i2, i3, i4, i5, i6, i7, i8, i9, i10, i11, i12, i13, i14 }
            elseif (not okInfo) then
                TT:NoteSecretRefusal("GetItemInfo")
            end
        end
        if (not itemInfo[2] or not itemInfo[4]) then
            scheduleItemTooltipRefresh(self, itemLink)
        end
        if (TacoTipConfig.show_item_level) then
            local ilvl = itemInfo[4]
            if (ilvl and not isSecretValue(ilvl) and ilvl > 1) then
                self:AddLine(L["Item Level"] .. " " .. ilvl, 1, 1, 1)
            end
        end
        if (TacoTipConfig.show_gs_items) then
            local gs, _, r, g, b = GearScore:GetItemScoreFromInfo(itemInfo)
            if (gs and not isSecretValue(gs) and gs > 1) then
                self:AddLine("GearScore: " .. gs, r, g, b)
                local inspectIsHunter = false
                if (InspectFrame and InspectFrame:IsShown() and InspectFrame.unit and not isSecretValue(InspectFrame.unit)) then
                    local okCls, _, cls = pcall(UnitClass, InspectFrame.unit)
                    -- cls is the classFilename return; the secrecy test is its own
                    -- step so the comparison is never made on a secret.
                    if (okCls and not isSecretValue(cls)) then
                        if (cls == "HUNTER") then
                            inspectIsHunter = true
                        end
                    end
                end
                if (TacoTipConfig.show_gs_items_hs or IsModifierKeyDown() or playerClass == "HUNTER" or inspectIsHunter) then
                    local hs, _, hsR, hsG, hsB = GearScore:GetItemHunterScore(itemLink, itemInfo)
                    if (hs and not isSecretValue(hs) and gs ~= hs) then
                        self:AddLine((L["HunterScore"] or "HunterScore") .. ": " .. hs, hsR, hsG, hsB)
                    end
                end
            end
        end
    end

    -- Row-count delta: the client's own lines must survive our hook. Record the
    -- last before/after pair and warn if a hover ends with FEWER lines than it
    -- started with -- that is the signature of the reported "client rows went
    -- missing" class, and it must never be silent.
    local rowsAfter = (type(self.NumLines) == "function") and self:NumLines() or 0
    ev.itemRowsLastBefore = rowsBefore
    ev.itemRowsLastAfter = rowsAfter
    if (rowsAfter < rowsBefore) then
        ev.itemRowsRemoved = (ev.itemRowsRemoved or 0) + 1
        TT:RecordWarning("tooltip", string.format(
            "item hook ended with fewer client rows (before=%d after=%d)", rowsBefore, rowsAfter))
    end
    -- Last item hover fingerprint: one report line that says what the last item
    -- tooltip actually was, so a user report does not depend on memory.
    local lastItemID
    if (type(itemLink) == "string" and not isSecretValue(itemLink)) then
        lastItemID = tonumber(string.match(itemLink, "item:(%d+)"))
    end
    ev.lastItem = {
        id = lastItemID,
        rowsAdded = rowsAfter - rowsBefore,
        payload = (data == nil) and "none" or (payloadReadable and "readable" or "unreadable"),
        linkSecret = (ev.itemSecretLink or 0) > 0,
        restrictions = TT:RestrictionSnapshot(),
        at = (type(GetTime) == "function") and GetTime() or 0,
    }

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
    if (not tooltip or not itemLink or isSecretValue(itemLink) or not Item or not Item.CreateFromItemLink) then
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
        local itemID = nil
        if (type(GetItemInfoInstant) == "function") then
            local okInst, instId = pcall(GetItemInfoInstant, itemLink)
            if (okInst and not isSecretValue(instId) and type(instId) == "number") then
                itemID = instId
            end
        end
        if (RequestLoadItemDataByID and itemID and not isSecretValue(itemID)) then
            pcall(RequestLoadItemDataByID, itemID)
        end
        return
    end

    local cachedOk, isCached = pcall(item.IsItemDataCached, item)
    if (not cachedOk or isSecretValue(isCached) or isCached == true) then
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
            -- GameTooltip has no UpdateTooltip method on the data-pipeline
            -- clients (GameTooltip_OnUpdate routes to the OWNER's
            -- UpdateTooltip, then self.RefreshData), so this branch is a silent
            -- no-op on Forever and Retail. It is kept for the clients that do
            -- expose it; it is not a repaint we can rely on there.
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

-- Blizzard's UnitFrame_UpdateTooltip appends the localized UNIT_POPUP_RIGHT_CLICK
-- hint ("Right Click for Frame Settings") AFTER SetUnit returns; SetUnit's own
-- Show() fires OnShow before that, and the later Show() is a no-op on an
-- already-shown frame. So an OnShow hook can never see the line -- the
-- post-hook on UnitFrame_UpdateTooltip is the only place that does, and it
-- covers every 0.2s refresh too. It runs before the frame is drawn. The client
-- adds a blank spacer with the line and the tooltip API has no line-removal
-- call, so one empty row remains.
local function blankUnitFrameInstruction(tooltip)
    if (not (isForever or isRetail)) then
        return
    end
    tooltip = tooltip or GameTooltip
    local instruction = _G.UNIT_POPUP_RIGHT_CLICK
    if (not tooltip or not tooltip.NumLines or type(instruction) ~= "string"
            or instruction == "") then
        return
    end
    local numLines = tooltip:NumLines()
    for i = numLines, math.max(1, numLines - 2), -1 do
        local line = getTooltipLeftLine(tooltip, i)
        if (line and line.GetText) then
            local text = line:GetText()
            if (text and not isSecretValue(text) and text == instruction) then
                if (line.SetText) then
                    line:SetText("")
                end
                return
            end
        end
    end
end

local function onTooltipShow(tooltip)
    local scale = (TacoTipConfig and TacoTipConfig.tooltip_scale) or 1
    applyFrameScale(tooltip, scale)

    local state = getTooltipState(tooltip)
    -- Forever: the item post-call marked this tooltip as item content. Its
    -- tooltip info is the client's payload, which may carry secret line data in
    -- instances; reading it from this tainted hook is exactly what Blizzard
    -- guards (GameTooltip.lua:994-1003). Use the link the post-call already
    -- stored and skip the reads below.
    local itemTooltip = isForever and state.itemTooltip == true
    local shownItemLink
    -- The loot-window tooltip is deliberately not read here: reading its
    -- tooltip info from this tainted OnShow hook is the read Blizzard guards
    -- with securecallfunction (GameTooltip.lua:994-1003), and the tooltip is
    -- left untouched on Forever anyway (see isForeverLootTooltip).
    if (itemTooltip) then
        shownItemLink = state.currentItemLink
    elseif (not isForeverLootTooltip(tooltip) and tooltip and tooltip.GetItem) then
        local itemOk, _, itemLink = pcall(tooltip.GetItem, tooltip)
        shownItemLink = itemLink
        if (not itemOk) then
            shownItemLink = nil
        end
    end
    -- If the same item re-shows (shopping tooltip compare), keep its pending
    -- item-load registration alive instead of tearing it down and re-requesting.
    local preservePendingItem = shownItemLink ~= nil and state.currentItemLink == shownItemLink
    -- Forever loot-window tooltip: do not read its tooltip data at all. Both
    -- resolveTooltipUnit (GetDisplayedUnit -> GetPrimaryTooltipData) and
    -- GetItem are tooltip-info reads from this tainted hook, which is exactly
    -- what Blizzard guards in SetWorldCursor (GameTooltip.lua:994-1003). The
    -- client owns that tooltip's secret lines; the addon only clears the
    -- previous hover's visual state below.
    local lootTooltip = isForeverLootTooltip(tooltip)
    local isUnit = false
    local unit
    if (not lootTooltip and not itemTooltip) then
        if (tooltip) then
            if (tooltip.IsTooltipType and Enum and Enum.TooltipDataType and tooltip:IsTooltipType(Enum.TooltipDataType.Unit)) then
                isUnit = true
            end
        end
        unit = resolveTooltipUnit(tooltip)
        if (unit and safeUnitExists(unit)) then
            isUnit = true
        end
    end

    if (not isUnit) then
        -- F1: When the tooltip shows for non-unit content (items, spells, UI
        -- elements, options hover-help), the portrait from a previous unit
        -- display must be cleared. OnTooltipCleared may not have fired on
        -- this transition path (e.g. ClearLines + Show in showHoverTooltip).
        clearTooltipVisuals(tooltip, preservePendingItem, nil, "show-no-class-cache", true)
        return
    end

    -- Modern clients: the unit post-call runs before Show(), so the portrait
    -- side was decided on a frame whose GetRight() was still 0. OnShow is laid
    -- out and still precedes presentation, so recompute here once per show --
    -- no visible edge flip on the following 0.2s tick.
    if ((isForever or isRetail) and TacoTipConfig.tooltip_portrait) then
        -- Anchor the portrait the config actually renders. A session that
        -- toggled 3D off still has the (hidden) model frame on the tooltip, so
        -- `3D or texture` would anchor the wrong region.
        local portrait
        if (TacoTipConfig.tooltip_portrait_3d) then
            portrait = tooltip.TacoTipPortrait3D
        end
        if (not portrait) then
            portrait = tooltip.TacoTipPortrait or tooltip.TacoTipPortrait3D
        end
        if (portrait) then
            anchorTooltipPortrait(tooltip, portrait, true)
        end
    end

    if (not TacoTipConfig.tooltip_border_use_class and not TacoTipConfig.color_class) then
        return
    end

    -- Only apply class-tinted borders when the tooltip actually shows a
    -- player unit.
    if (not unit or not safeUnitIsPlayer(unit)) then
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

-- Every 0.2s refresh goes through UnitFrame_UpdateTooltip AFTER the addon's
-- post-call, so the OnShow blank above cannot see the re-added line on an
-- already-shown frame. Guarded: the global is present on all five clients, but
-- a missing one must not abort the rest of main.lua at file scope.
stage("tooltip-hooks")
if ((isForever or isRetail) and type(_G.UnitFrame_UpdateTooltip) == "function"
        and type(hooksecurefunc) == "function") then
    hooksecurefunc("UnitFrame_UpdateTooltip", function()
        blankUnitFrameInstruction(GameTooltip)
    end)
end

local function registerTooltipVisualClearing(tooltipFrame)
    if (not tooltipFrame or type(tooltipFrame) ~= "table" or not tooltipFrame.HasScript) then
        return
    end
    if (tooltipFrame:HasScript("OnTooltipCleared")) then
        tooltipFrame:HookScript("OnTooltipCleared", function(tFrame)
            if (isUnitFramePeriodicUpdate(tFrame)) then
                if (tFrame == GameTooltip) then
                    TT.ev.portraitOnClearSkipped = (TT.ev.portraitOnClearSkipped or 0) + 1
                end
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
            -- Only suppress OnHide as a periodic unit-frame update race if the
            -- tooltip is actually still shown (a stale FadeOut finishing after
            -- a quick re-hover); a genuinely hidden tooltip must always reset.
            if (tFrame.IsShown and tFrame:IsShown() and isUnitFramePeriodicUpdate(tFrame)) then
                if (tFrame == GameTooltip) then
                    TT.ev.portraitOnHideSkipped = (TT.ev.portraitOnHideSkipped or 0) + 1
                end
                return
            end
            if (tFrame == GameTooltip) then
                TT.ev.portraitOnHideRan = (TT.ev.portraitOnHideRan or 0) + 1
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
            if (ok and unit and safeUnitExists(unit)) then
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
    if (focus == WorldFrame and safeUnitExists("mouseover")) then
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
            TT.ev.anchorSpellBypass = (TT.ev.anchorSpellBypass or 0) + 1
            return
        end
    end
    if (not isUnitHoverTarget(tooltip, parent)) then
        local parentName = parent and parent.GetName and parent:GetName()
        if (parentName and parentName:find("ContainerFrameItemButton", 1, true)) then
            TT.ev.anchorContainerBypass = (TT.ev.anchorContainerBypass or 0) + 1
        else
            TT.ev.anchorNonUnitBypass = (TT.ev.anchorNonUnitBypass or 0) + 1
        end
        return
    end
    if (TacoTipConfig.anchor_mouse) then
        if (not TacoTipConfig.anchor_mouse_world or TT:GetMouseFocus() == WorldFrame) then
            if (not TacoTipMouseAnchor) then
                CreateMouseAnchor()
            end
            tooltip:ClearAllPoints()
            tooltip:SetPoint("BOTTOMLEFT", TacoTipMouseAnchor, "CENTER", 10, 10)
            TT.ev.anchorMouse = (TT.ev.anchorMouse or 0) + 1
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
                TT.ev.anchorCustomPos = (TT.ev.anchorCustomPos or 0) + 1
            end
        elseif (TacoTipConfig.show_hp_bar and TacoTipConfig.show_power_bar) then
            tooltip:ClearAllPoints()
            tooltip:SetPoint("BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -CONTAINER_OFFSET_X - 13, CONTAINER_OFFSET_Y + 9)
            TT.ev.anchorDefault = (TT.ev.anchorDefault or 0) + 1
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
    local point = tostring(pos[1] or "BOTTOMRIGHT")
    local relPoint = tostring(pos[2] or "BOTTOMRIGHT")
    local xOfs = tonumber(pos[3]) or 0
    local yOfs = tonumber(pos[4]) or 0
    TacoTipDragButton:SetPoint(point, UIParent, relPoint, xOfs, yOfs)

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
        stopPowerBarTicker()
        if (TacoTipPowerBar and (not GameTooltip or not GameTooltip:IsShown())) then
            TacoTipPowerBar:Hide()
        end
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
            if (not updateFrame or not updateFrame:IsShown()) then
                return
            end
            local cx, cy = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale()
            local fx, fy = parent:GetRect()
            if (fx and fy and scale and scale > 0) then
                callbackFunc(cx / scale - fx, cy / scale - fy)
            end
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
    return true
end

function TT:RefreshCharacterFrame()
    local initCharacterFrame = TT.InitCharacterFrame
    if (initCharacterFrame) then
        -- InitCharacterFrame marks itself done, so the nil assignment here is
        -- redundant. It stays out of this path deliberately: on a client with no
        -- character paper doll there are no font strings to update, and running
        -- on would index four nil globals on every refresh.
        if (not initCharacterFrame(TT)) then
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
    TT.InitInspectFrame = nil
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
        return true
    end)
end

function TT:RefreshInspectFrame()
    if (InCombatLockdown()) then
        return
    end
    local initInspectFrame = TT.InitInspectFrame
    if (initInspectFrame) then
        if (not InspectModelFrame or not InspectPaperDollFrame) then
            return
        end
        if (not initInspectFrame(TT)) then
            return
        end
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

-- Reports what the counters mean and how to read them.
--
-- COLLECT vs RENDER. TT:CollectDiagnostics() builds a plain table and never
-- prints or mutates add-on state; TT:PrintDiagnostics() renders that table and
-- does nothing else. The split is what makes the report testable: the harness
-- asserts the table, not chat text.
--
-- A row is { label = string, value = string, status = "ok"|"info"|"warn"|"error" }.
-- Section ids are stable and their order is fixed by DIAG_SECTION_ORDER.
local DIAG_STATUS = { ok = true, info = true, warn = true, error = true }
local DIAG_SECTION_ORDER = {
    "environment", "active-unit", "tooltip", "inspect",
    "events", "inspect-frame", "errors", "problems",
}
local DIAG_MAX_ERROR_ROWS = 10
local DIAG_MAX_PROBLEM_ROWS = 12
local DIAG_ZERO_RENDER_WARN_SECONDS = 120

local function diagValue(value)
    if (value == nil) then return "unknown" end
    return tostring(value)
end

local function diagSection(id, title)
    return { id = tostring(id), title = tostring(title), rows = {}, notes = {} }
end

local function diagRow(section, label, value, status)
    if (not section or type(section.rows) ~= "table") then return end
    if (not DIAG_STATUS[status]) then status = "info" end
    section.rows[#section.rows + 1] = {
        label = tostring(label),
        value = diagValue(value),
        status = status,
    }
end

local function diagUptime()
    local now = (type(GetTime) == "function") and GetTime() or 0
    local started = tonumber(rawget(TT, "loadTime")) or 0
    if (now <= 0 or started <= 0) then return 0, "unknown" end
    local elapsed = now - started
    if (elapsed < 0) then elapsed = 0 end
    local minutes = math.floor(elapsed / 60)
    local seconds = math.floor(elapsed - minutes * 60)
    if (minutes > 0) then
        return elapsed, string.format("%dm %ds", minutes, seconds)
    end
    return elapsed, string.format("%ds", seconds)
end

local function diagRate(count, total)
    count = tonumber(count) or 0
    total = tonumber(total) or 0
    if (total <= 0) then return nil end
    return string.format("%.1f%% (%d of %d)", (count / total) * 100, count, total)
end

-- The only map-derived list in the report. Never render from pairs(): sort by
-- count descending, then key ascending, so two reports of the same state match.
local function diagSortTeardowns(teardownBy)
    local list = {}
    if (type(teardownBy) ~= "table") then return list end
    for reason, count in pairs(teardownBy) do
        list[#list + 1] = { reason = tostring(reason), count = tonumber(count) or 0 }
    end
    table.sort(list, function(a, b)
        if (a.count ~= b.count) then return a.count > b.count end
        return a.reason < b.reason
    end)
    return list
end

local function diagTeardownText(teardownBy)
    local list = diagSortTeardowns(teardownBy)
    if (#list == 0) then return "none" end
    local parts = {}
    for i = 1, #list do
        parts[#parts + 1] = string.format("%s=%d", list[i].reason, list[i].count)
    end
    return table.concat(parts, ", ")
end

local function collectEnvironmentSection()
    local s = diagSection("environment", "environment")
    local elapsed, uptimeText = diagUptime()
    diagRow(s, "session uptime", uptimeText, elapsed >= DIAG_ZERO_RENDER_WARN_SECONDS and "info" or "ok")
    diagRow(s, "version", addOnVersion, "ok")
    diagRow(s, "load OK", TT.LOAD_OK and "yes"
        or ("NO -- main.lua stopped at stage: " .. tostring(TT.LOAD_STAGE)),
        TT.LOAD_OK and "ok" or "error")
    local family = CI and CI.family or "?"
    diagRow(s, "client family", family, (family == "?" or family == "unknown") and "error" or "ok")
    diagRow(s, "interface", CI and CI.interfaceVersion or "?", "ok")
    diagRow(s, "locale", _G.TACOTIP_ACTIVE_LOCALE or "?", "ok")
    local gs = _G.TT_GS
    diagRow(s, "GearScore bracket", gs and gs.BRACKET_SIZE or "none", gs and "ok" or "warn")
    local gt = _G.GameTooltip
    diagRow(s, "tooltip has NineSlice", gt and gt.NineSlice ~= nil, "ok")
    diagRow(s, "TT.HookedTooltipScripts", TT.HookedTooltipScripts
        and ("unit=" .. tostring(TT.HookedTooltipScripts.Unit)
            .. " item=" .. tostring(TT.HookedTooltipScripts.Item)) or "none",
        (TT.HookedTooltipScripts and TT.HookedTooltipScripts.Unit) and "ok" or "error")
    diagRow(s, "TT.HookedDefaultAnchor", tostring(TT.HookedDefaultAnchor or false), "ok")
    if (not TT.LOAD_OK) then
        s.notes[#s.notes + 1] = "An error was raised while loading main.lua at or after the stage above. "
            .. "/reload cannot fix it -- enable Lua error reporting (BugSack/Swatter) and reload."
    end
    return s
end

local function collectProblems()
    local problems = {}
    local function add(severity, text)
        problems[#problems + 1] = { severity = severity, text = tostring(text) }
    end

    if (not TT.LOAD_OK) then
        add("error", "main.lua did not finish loading (stage: " .. tostring(TT.LOAD_STAGE) .. ")")
    end

    if (not CI) then
        add("error", "LibForeverInspector is not available")
    else
        local projectId = rawget(_G, "WOW_PROJECT_ID")
        local iv = CI.interfaceVersion or 0
        if (CI.IsRetail and CI.IsRetail() and CI.IsForever and CI.IsForever()) then
            add("error", "client detected as BOTH Retail and WoW Forever (interface "
                .. tostring(iv) .. ", project " .. tostring(projectId) .. ")")
        elseif (CI.IsUnknown and CI.IsUnknown()) then
            add("error", "client family could not be resolved (interface "
                .. tostring(iv) .. ", project " .. tostring(projectId) .. ")")
        end
        if (projectId and CI.family == "classicEra" and projectId ~= 2) then
            add("error", "Classic Era expects project id 2, got " .. tostring(projectId))
        end
    end

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
            add("warn", "border setting '" .. tostring(value)
                .. "' matches no entry and is being replaced by the per-client default ("
                .. tostring(TT.GetDefaultTooltipBorder and TT:GetDefaultTooltipBorder()) .. ")")
        end
    end

    if (cfg) then
        if (cfg.show_power_bar and _G.UnitPowerType == nil) then
            add("error", "Power Bar is enabled but UnitPowerType is nil -- it cannot update")
        end
        if (cfg.show_hp_bar and _G.UnitHealthMax == nil) then
            add("error", "Health Bar is enabled but UnitHealthMax is nil -- it cannot update")
        end
        if (cfg.show_talents and (CI == nil or type(CI.GetSpecialization) ~= "function")) then
            add("error", "Talents are enabled but the inspector exposes no GetSpecialization")
        end
        if (cfg.custom_pos) then
            local p = cfg.custom_pos
            if (type(p) ~= "table" or type(p[1]) ~= "string"
                    or type(p[3]) ~= "number" or type(p[4]) ~= "number") then
                add("error", "custom_pos table contains corrupted coordinate entries")
            end
        end
    end

    if (TT.HookedTooltipScripts and not TT.HookedTooltipScripts.Unit) then
        add("error", "no unit tooltip delivery path is hooked on this client")
    end

    local totalErrors = tonumber(TT.totalErrorsCaught) or 0
    if (totalErrors > 0) then
        add("error", string.format("%d error(s) caught in pipeline/pcalls (last: '%s')",
            totalErrors, tostring(TT.lastTooltipError or "unknown")))
    end

    local resolveFailed = tonumber(TT.ev and TT.ev.resolveTooltipUnitFailed) or 0
    if (resolveFailed > 0) then
        add("error", string.format("Unit resolution failed %d time(s) since load (last cause: '%s')",
            resolveFailed, tostring(TT.ev.resolveTooltipUnitLastCause or "unknown")))
    end

    if (CI and type(CI.GetInspectStats) == "function") then
        local ok, st = pcall(CI.GetInspectStats, CI)
        if (ok and type(st) == "table") then
            local pendingDuration = tonumber(st.pendingDuration) or 0
            if (st.pendingUnit and pendingDuration > 3.0) then
                add("error", string.format(
                    "Inspect queue in-flight unit '%s' has been waiting %.1fs (stalled)",
                    tostring(st.pendingUnit), pendingDuration))
            end
            local timeouts = tonumber(st.timeouts) or 0
            if (timeouts > 0) then
                local readyCount = tonumber(st.ready) or 0
                local timeoutSev = (readyCount == 0 and timeouts >= 3) and "error" or "warn"
                add(timeoutSev, string.format("Inspect requests timed out %d time(s) without server response",
                    timeouts))
            end
            local rejected = tonumber(st.rejected) or 0
            if (rejected > 0) then
                add("warn", string.format("Inspect requests rejected %d time(s) (last refusal reason: '%s')",
                    rejected, tostring(st.lastRejectedReason or "unknown")))
            end
            if (st.lastError) then
                add("warn", "Last inspect-call error: " .. tostring(st.lastError))
            end
        end
    end

    local portraitFailed = tonumber(TT.ev and TT.ev.portraitSetFailed) or 0
    if (portraitFailed > 0) then
        local attempts = tonumber(TT.ev and TT.ev.portraitSetAttempts) or 0
        if (attempts > 0) then
            add("error", string.format(
                "Portrait model failed to load %d time(s) out of %d attempt(s); the tooltip retries on the next render",
                portraitFailed, attempts))
        else
            add("error", string.format(
                "Portrait model failed to load %d time(s); the tooltip retries on the next render",
                portraitFailed))
        end
    end
    local canSetBlocked = tonumber(TT.ev and TT.ev.portraitCanSetFalse) or 0
    if (canSetBlocked > 0) then
        add("warn", string.format(
            "Portrait CanSetUnit refused %d time(s) (old mesh cleared rather than retained)",
            canSetBlocked))
    end
    if (type(GameTooltip) == "table") then
        local okShow, ttShown = pcall(function() return GameTooltip.IsShown and GameTooltip:IsShown() == true end)
        ttShown = okShow and ttShown or false
        local p3 = rawget(GameTooltip, "TacoTipPortrait3D")
        if (type(p3) ~= "table") then p3 = nil end
        local p2 = rawget(GameTooltip, "TacoTipPortrait")
        if (type(p2) ~= "table") then p2 = nil end
        local p3Shown = (p3 and p3.IsShown and pcall(p3.IsShown, p3) and p3:IsShown() == true) or false
        local p2Shown = (p2 and p2.IsShown and pcall(p2.IsShown, p2) and p2:IsShown() == true) or false
        if ((p3Shown or p2Shown) and not ttShown) then
            add("warn", "Portrait frame is still shown while GameTooltip is hidden (stale reset state)")
        end
        if (p3Shown and p2Shown) then
            add("warn", "Both 3D and 2D portrait frames are shown simultaneously on GameTooltip")
        end
        if ((p3Shown or p2Shown) and cfg and cfg.tooltip_portrait == false) then
            add("warn", "Portrait frame is shown even though tooltip_portrait is disabled")
        end
    end

    local unreadablePayload = tonumber(TT.ev and TT.ev.itemPayloadUnreadable) or 0
    if (unreadablePayload > 0) then
        add("warn", string.format("%d item tooltip(s) supplied an unreadable (secret) payload; "
            .. "TacoTip skipped its rows and left the client's own lines alone", unreadablePayload))
    end
    local secretLinksDropped = tonumber(TT.ev and TT.ev.itemSecretLink) or 0
    if (secretLinksDropped > 0) then
        add("warn", string.format("%d item link(s) arrived secret and were dropped before C_Item.GetItemInfo",
            secretLinksDropped))
    end
    local lostRows = tonumber(TT.ev and TT.ev.itemRowsRemoved) or 0
    if (lostRows > 0) then
        add("warn", string.format("%d item hover(s) ended with FEWER tooltip lines than they started with",
            lostRows))
    end
    local refusedTally = TT.ev and TT.ev.secretRefused
    if (type(refusedTally) == "table") then
        local total, names = 0, {}
        for key, count in pairs(refusedTally) do
            total = total + (tonumber(count) or 0)
            names[#names + 1] = tostring(key)
        end
        table.sort(names)
        if (total > 0) then
            add("warn", string.format(
                "%d secret refusal(s) by API (%s); those calls answered unknown rather than raising",
                total, table.concat(names, ", ")))
        end
    end

    local warningCount = (type(TT.warningLog) == "table") and #TT.warningLog or 0
    if (warningCount > 0) then
        add("warn", string.format("%d warning(s) recorded (%d kept in the log) (last: '%s')",
            tonumber(TT.totalWarnings) or warningCount, warningCount,
            tostring(TT.warningLog[warningCount].message or "unknown")))
    end

    if (type(InCombatLockdown) == "function" and InCombatLockdown()) then
        add("warn", "Player is in combat lockdown; protected UI actions are restricted")
    end

    local elapsed, uptimeText = diagUptime()
    if ((tonumber(TT.ev and TT.ev.unitRender) or 0) == 0 and elapsed >= DIAG_ZERO_RENDER_WARN_SECONDS) then
        add("warn", "No unit renders recorded after " .. tostring(uptimeText)
            .. "; hover a character to exercise the tooltip pipeline")
    end

    return problems
end

local function buildVerdict(problems)
    local count = #problems
    if (count == 0) then
        return { healthy = true, count = 0, severity = "none", text = "HEALTHY -- no problems detected" }
    end
    local highest = "warn"
    local firstText = "unknown"
    if (type(problems[1]) == "table" and problems[1].text) then
        firstText = tostring(problems[1].text)
    end
    for i = 1, count do
        local p = problems[i]
        if (type(p) == "table" and p.severity == "error") then
            highest = "error"
            firstText = tostring(p.text or "unknown")
            break
        end
    end
    if (#firstText > 120) then
        firstText = string.sub(firstText, 1, 117) .. "..."
    end
    local noun = (count == 1) and "problem" or "problems"
    return {
        healthy = false,
        count = count,
        severity = highest,
        text = string.format("%d %s, highest: %s -- %s", count, noun, highest, firstText),
    }
end

local function collectActiveUnitSection()
    local s = diagSection("active-unit", "active unit context")
    local activeUnit = nil
    if (safeUnitExists("mouseover")) then
        activeUnit = "mouseover"
    elseif (safeUnitExists("target")) then
        activeUnit = "target"
    elseif (safeUnitExists("player")) then
        activeUnit = "player"
    end
    if (not activeUnit) then
        diagRow(s, "active unit context", "no active unit found (hover or target a unit)", "info")
        return s
    end

    s.title = "active unit context (" .. tostring(activeUnit) .. ")"
    local fnUnitName = _G.UnitName or UnitName
    local fnUnitGUID = _G.UnitGUID or UnitGUID
    local fnUnitLevel = _G.UnitLevel or UnitLevel
    local fnUnitClass = _G.UnitClass or UnitClass
    local fnUnitRace = _G.UnitRace or UnitRace
    local name = (type(fnUnitName) == "function" and fnUnitName(activeUnit)) or "?"
    if (isSecretValue(name)) then name = "<secret>" end
    local guid = (type(fnUnitGUID) == "function" and fnUnitGUID(activeUnit)) or "?"
    if (isSecretValue(guid)) then guid = "<secret>" end
    local isPlayer = safeUnitIsPlayer(activeUnit)
    local level = (type(fnUnitLevel) == "function" and fnUnitLevel(activeUnit)) or "?"
    if (isSecretValue(level)) then level = "<secret>" end
    local class = (type(fnUnitClass) == "function" and fnUnitClass(activeUnit)) or "?"
    if (isSecretValue(class)) then class = "<secret>" end
    local race = (type(fnUnitRace) == "function" and fnUnitRace(activeUnit)) or ""
    if (isSecretValue(race)) then race = "<secret>" end
    diagRow(s, "unit", string.format("%s (%slevel %s, %s%s)",
        name,
        isPlayer and "Player, " or "NPC, ",
        tostring(level),
        race ~= "" and (race .. " ") or "",
        class), "info")
    diagRow(s, "GUID", guid, "info")
    if (isPlayer) then
        local fnCanInspect = _G.CanInspect or CanInspect
        local fnCheckInteractDistance = _G.CheckInteractDistance or CheckInteractDistance
        local fnUnitIsConnected = _G.UnitIsConnected or UnitIsConnected
        local fnUnitCanAttack = _G.UnitCanAttack or UnitCanAttack
        local okCan, rawCan = pcall(fnCanInspect, activeUnit)
        local canInspect = (type(fnCanInspect) == "function" and okCan) and rawCan or false
        local canInspectStr = isSecretValue(canInspect) and "<secret>" or tostring(canInspect)
        local interactDist = "n/a"
        if (type(fnCheckInteractDistance) == "function" and activeUnit and not isSecretValue(activeUnit)) then
            local okID, idVal = pcall(fnCheckInteractDistance, activeUnit, 1)
            if (okID) then
                interactDist = isSecretValue(idVal) and "<secret>" or tostring(idVal)
            else
                interactDist = "protected"
            end
        end
        local isVisible = false
        if (type(_G.UnitIsVisible) == "function" and activeUnit and not isSecretValue(activeUnit)) then
            local okVis, vis = pcall(_G.UnitIsVisible, activeUnit)
            if (okVis) then isVisible = vis end
        end
        local isVisibleStr = isSecretValue(isVisible) and "<secret>" or tostring(isVisible)
        local isConnected = false
        if (type(fnUnitIsConnected) == "function" and activeUnit and not isSecretValue(activeUnit)) then
            local okConn, conn = pcall(fnUnitIsConnected, activeUnit)
            if (okConn) then isConnected = conn end
        end
        local isConnectedStr = isSecretValue(isConnected) and "<secret>" or tostring(isConnected)
        local canAttack = false
        if (type(fnUnitCanAttack) == "function" and activeUnit and not isSecretValue(activeUnit)) then
            local okAtk, atk = pcall(fnUnitCanAttack, "player", activeUnit)
            if (okAtk) then canAttack = atk end
        end
        local canAttackStr = isSecretValue(canAttack) and "<secret>" or tostring(canAttack)
        diagRow(s, "inspectable",
            string.format("CanInspect=%s | InteractDist(1)=%s | Visible=%s | Connected=%s | Hostile=%s",
                canInspectStr, tostring(interactDist), isVisibleStr, isConnectedStr,
                canAttackStr), "info")
        local distStr = nil
        if (type(_G.UnitDistanceSquared) == "function" and activeUnit and not isSecretValue(activeUnit)) then
            local okDist, d2, chk = pcall(_G.UnitDistanceSquared, activeUnit)
            if (okDist and (isSecretValue(d2) or isSecretValue(chk))) then
                -- Secret test first: the reported distance is never compared,
                -- formatted or converted while it may be restricted.
                distStr = "protected (secret in combat)"
            elseif (okDist and d2 ~= nil) then
                if (chk and type(d2) == "number" and d2 >= 0) then
                    distStr = string.format("~%.1fyd (dist^2: %.1f)", math.sqrt(d2), d2)
                end
            end
        end
        if (not distStr and type(fnCheckInteractDistance) == "function" and activeUnit and not isSecretValue(activeUnit)) then
            -- Fallback tiered range estimation via CheckInteractDistance indices:
            -- 3: Duel (~10yd), 2: Trade (~11yd), 1: Inspect (~28yd)
            local okDuel, inDuel = pcall(fnCheckInteractDistance, activeUnit, 3)
            local okTrade, inTrade = pcall(fnCheckInteractDistance, activeUnit, 2)
            local okInspect, inInspect = pcall(fnCheckInteractDistance, activeUnit, 1)
            if (okDuel and inDuel and not isSecretValue(inDuel)) then
                distStr = "<= 10yd (close/duel range)"
            elseif (okTrade and inTrade and not isSecretValue(inTrade)) then
                distStr = "<= 11yd (trade range)"
            elseif (okInspect and inInspect and not isSecretValue(inInspect)) then
                distStr = "<= 28yd (inspect range)"
            elseif (okInspect and inInspect == false and not isSecretValue(inInspect)) then
                distStr = "> 28yd (out of inspect range)"
            end
        end
        diagRow(s, "distance", distStr or "unknown", "info")
        diagRow(s, "GearScore option",
            (TacoTipConfig and TacoTipConfig.show_gs_player) and "on" or "off", "info")
        -- Self has no inspect-cache record; the tooltip reads it live. Show the
        -- same read here so a missing self line can be attributed to the score
        -- (0 / no scored gear) instead of the render. useCallback=false keeps
        -- the probe from registering completion callbacks; it may still ask the
        -- client for uncached item data, which the hover path already does.
        if (guid ~= "?" and guid ~= "<secret>" and safeEquals(guid, safeUnitGUID("player")) and type(_G.TT_GS) == "table"
                and type(_G.TT_GS.GetScore) == "function") then
            local scoreOk, liveScore, liveIlvl = pcall(_G.TT_GS.GetScore, _G.TT_GS, guid, false)
            local liveText = scoreOk
                and string.format("%s (iLvl %s)", tostring(liveScore), tostring(liveIlvl))
                or ("failed: " .. tostring(liveScore))
            diagRow(s, "live self score", liveText,
                (scoreOk and type(liveScore) == "number" and liveScore > 0) and "ok" or "warn")
        end
        if (CI and type(CI.GetUnitData) == "function") then
            local cached = CI:GetUnitData(guid)
            if (cached) then
                local now = (type(GetTime) == "function") and GetTime() or 0
                local age = (cached.time and cached.time > 0 and now > 0)
                    and string.format("%.1fs ago", now - cached.time) or "unknown"
                local cacheStatus = "info"
                if (cached.incomplete and not cached.retryPending) then cacheStatus = "warn" end
                diagRow(s, "cached data", string.format("yes (age: %s | stale: %s | incomplete: %s)",
                    age, tostring(cached.stale or false), tostring(cached.incomplete or false)), cacheStatus)
                local gs, ilvl, scoreReady = 0, 0, false
                -- Side-effect-free score: only score when every cached link's
                -- item data is ALREADY in the client cache. GetItemInfo never
                -- requests; calling GetScore on a partially cached set would.
                local getItemInfo = (_G.C_Item and _G.C_Item.GetItemInfo) or _G.GetItemInfo
                local anyLink, allCached = false, type(getItemInfo) == "function"
                if (allCached and type(cached.items) == "table") then
                    for slot = 1, 18 do
                        local link = cached.items[slot]
                        -- Same argument contract as WarmGearItemData: GetItemInfo
                        -- declares SecretArguments = "AllowedWhenUntainted", so a
                        -- secret link must be tested before the call.
                        if (type(link) ~= "nil" and not isSecretValue(link)) then
                            anyLink = true
                            local okInfo, info = pcall(getItemInfo, link)
                            if (not okInfo or not info) then
                                allCached = false
                                break
                            end
                        end
                    end
                else
                    allCached = false
                end
                if (anyLink and allCached and GearScore and GearScore.GetScore) then
                    local okScore, score, itemLevel = pcall(GearScore.GetScore, GearScore, guid, false)
                    if (okScore) then
                        gs, ilvl, scoreReady = score or 0, itemLevel or 0, true
                    end
                end
                local spec = (CI.GetLocalizedSpecName and CI:GetLocalizedSpecName(guid)) or nil
                if (not spec and CI.GetSpecialization) then
                    local specIndex = CI:GetSpecialization(guid)
                    local _, classToken
                    if (type(fnUnitClass) == "function") then
                        _, classToken = fnUnitClass(activeUnit)
                    end
                    if (specIndex and classToken and not isSecretValue(classToken) and CI.GetSpecializationName) then
                        spec = CI:GetSpecializationName(classToken, specIndex)
                    end
                end
                if (scoreReady) then
                    diagRow(s, "GearScore / iLvl", string.format("GS=%s | iLvl=%s | Spec=%s",
                        tostring(gs), tostring(ilvl), tostring(spec or "none")), "info")
                else
                    -- Not scored because the client has not cached every link.
                    -- Dashes, never a word that could read as a tooltip state:
                    -- nothing printed here is ever shown on a tooltip, and the
                    -- tooltip omits the line until the real numbers exist.
                    diagRow(s, "GearScore / iLvl", "GS=- | iLvl=- | Spec="
                        .. tostring(spec or "none"), "info")
                    s.notes[#s.notes + 1] = "GearScore needs every equipped item link in the client "
                        .. "item cache. The tooltip requests the missing ones and renders the line "
                        .. "when the data arrives."
                end
            else
                local pending = false
                if (CI.inspectStats and CI.inspectStats.pendingUnit == activeUnit) then
                    pending = true
                end
                diagRow(s, "cached data", pending and "no (inspect in-flight)" or "no (not in cache)", "info")
            end
        end
        -- Forever: the tooltip's own talent source for this unit, so a missing
        -- Talents line is attributable without guessing. No record means the
        -- inspect never completed; a record with no entries means the client
        -- did not answer the inspect trait config (or answered it before the
        -- config was loaded, which the tooltip retries while the GUID matches).
        if (isForever and CI and type(CI.GetForeverTalentData) == "function") then
            local okT, talentData = pcall(CI.GetForeverTalentData, CI, activeUnit)
            if (okT and talentData and talentData.entries and #talentData.entries > 0) then
                diagRow(s, "forever talents", string.format("yes (%d group(s), active %s)",
                    #talentData.entries, tostring(talentData.active)), "ok")
            elseif (okT) then
                local hasRecord = false
                if (type(CI.GetUnitData) == "function") then
                    local okRec, rec = pcall(CI.GetUnitData, CI, guid)
                    hasRecord = okRec and rec ~= nil
                end
                diagRow(s, "forever talents",
                    hasRecord and "no (cached record has no trait data)"
                    or "no (no inspect cache record)", "warn")
            else
                diagRow(s, "forever talents", "read failed: " .. tostring(talentData), "error")
            end
        end
        -- Forever: why the Zone row is or is not drawn for the current hover.
        -- The gate is the tooltip owner's own unit token, so report that token
        -- (not the resolved tooltip token) and the map answer it produced.
        if (isForever) then
            local owner = (GameTooltip and type(GameTooltip.GetOwner) == "function")
                and GameTooltip:GetOwner() or nil
            local ownerUnit = owner and owner.unit
            local watched = isForeverWatchedFrameUnit(ownerUnit)
            local zoneName = getUnitZoneName(ownerUnit) or getUnitZoneName(activeUnit)
            diagRow(s, "zone row", string.format("owner unit=%s | watched=%s | zone=%s",
                    tostring(ownerUnit or "none"), tostring(watched), tostring(zoneName or "none")),
                (watched and zoneName) and "ok" or "warn")
        end
    end
    return s
end

local function collectTooltipSection()
    local s = diagSection("tooltip", "tooltip & anchoring")
    local cfg = _G.TacoTipConfig
    local anchorMode = "Default Screen Corner"
    if (cfg) then
        if (cfg.anchor_mouse) then
            anchorMode = "Mouse Anchor"
        elseif (cfg.custom_pos) then
            anchorMode = "Custom Position (docked to mover)"
        end
    end
    diagRow(s, "anchor mode", anchorMode, "info")
    local customPos = cfg and cfg.custom_pos
    if (type(customPos) == "table") then
        diagRow(s, "custom pos", string.format("[%s, rel=%s, x=%s, y=%s]",
            tostring(customPos[1]), tostring(customPos[2]), tostring(customPos[3]), tostring(customPos[4])), "info")
        diagRow(s, "custom anchor", tostring(cfg.custom_anchor or "TOPLEFT"), "info")
    end
    local ev = TT.ev or {}
    diagRow(s, "anchors executed", string.format("custom=%s, mouse=%s, default=%s",
        tostring(ev.anchorCustomPos or 0),
        tostring(ev.anchorMouse or 0),
        tostring(ev.anchorDefault or 0)), "info")
    diagRow(s, "container bypasses", ev.anchorContainerBypass or 0, "info")
    diagRow(s, "anchor bypasses", string.format("spell=%s, non-unit=%s",
        tostring(ev.anchorSpellBypass or 0), tostring(ev.anchorNonUnitBypass or 0)), "info")
    local renders = tonumber(ev.unitRender) or 0
    local failed = tonumber(ev.resolveTooltipUnitFailed) or 0
    local misses = tonumber(ev.gsCallbackNoUnit) or 0
    diagRow(s, "unit resolves", string.format("renders=%s, failed=%s, gs-callback-misses=%s (last fail cause: %s)",
        tostring(renders), tostring(failed), tostring(misses),
        tostring(ev.resolveTooltipUnitLastCause or "none")), failed > 0 and "warn" or "info")
    local resolutionRate = diagRate(failed, renders)
    if (resolutionRate) then
        diagRow(s, "unit resolution rate", resolutionRate, failed > 0 and "warn" or "ok")
    end
    local callbacks = tonumber(ev.gsCallback) or 0
    local missRate = diagRate(misses, callbacks)
    if (missRate) then
        diagRow(s, "gs-callback miss rate", missRate, "info")
    end
    local portraitDesc = "Disabled"
    if (cfg and cfg.tooltip_portrait) then
        portraitDesc = cfg.tooltip_portrait_3d and "3D Model" or "2D Icon"
    end
    diagRow(s, "portrait mode", portraitDesc, "info")
    if (cfg and cfg.tooltip_portrait_3d) then
        diagRow(s, "portrait zoom", tostring(cfg.tooltip_portrait_zoom or 0.75), "info")
    end
    local portraitFailed = tonumber(ev.portraitSetFailed) or 0
    diagRow(s, "portrait set failures", portraitFailed, portraitFailed > 0 and "warn" or "ok")
    local portraitAttempts = tonumber(ev.portraitSetAttempts) or 0
    local portraitOk = tonumber(ev.portraitSetSucceeded) or 0
    local portraitBlocked = tonumber(ev.portraitCanSetFalse) or 0
    local portraitKeyHits = tonumber(ev.portraitKeyHits) or 0
    local portrait2D = tonumber(ev.portrait2DSets) or 0
    local failRate = (portraitAttempts > 0)
        and ((diagRate(portraitFailed, portraitAttempts) or "0.0% (0 of ") .. tostring(portraitAttempts) .. ")")
        or "n/a"
    diagRow(s, "portrait pipeline", string.format(
            "attempts=%s, ok=%s, fail=%s (%s), canSet=false=%s, key-hits=%s, 2d=%s",
            tostring(portraitAttempts), tostring(portraitOk), tostring(portraitFailed), failRate,
            tostring(portraitBlocked), tostring(portraitKeyHits), tostring(portrait2D)),
        (portraitFailed > 0 or portraitBlocked > 0) and "warn" or "info")
    if (type(GameTooltip) == "table") then
        local okShown, ttShown = pcall(function() return GameTooltip.IsShown and GameTooltip:IsShown() == true end)
        ttShown = okShown and ttShown or false
        local p3 = rawget(GameTooltip, "TacoTipPortrait3D")
        if (type(p3) ~= "table") then p3 = nil end
        local p2 = rawget(GameTooltip, "TacoTipPortrait")
        if (type(p2) ~= "table") then p2 = nil end
        local p3Shown = (p3 and p3.IsShown and pcall(p3.IsShown, p3) and p3:IsShown() == true) or false
        local p2Shown = (p2 and p2.IsShown and pcall(p2.IsShown, p2) and p2:IsShown() == true) or false
        local p3Pts = (p3 and p3.GetNumPoints and pcall(p3.GetNumPoints, p3)) and tostring(p3:GetNumPoints()) or "?"
        local p3Alpha = (p3 and p3.GetAlpha and pcall(p3.GetAlpha, p3)) and
            string.format("%.2f", tonumber(p3:GetAlpha()) or 0) or "?"
        local gState = rawget(GameTooltip, "_tacoTipState")
        local desync = ((p3Shown or p2Shown) and not ttShown) or (p3Shown and p2Shown)
        diagRow(s, "portrait live state", string.format(
                "ttShown=%s | 3d=%s(shown=%s, alpha=%s, key=%s, retries=%s, side=%s, pts=%s) | 2d=%s(shown=%s) | state(cur=%s, owner=%s, anchored=%s)",
                tostring(ttShown),
                tostring(p3 ~= nil), tostring(p3Shown), p3Alpha,
                safeDiagValue(p3 and p3.tacoTipModelKey),
                tostring(p3 and p3.tacoTipSetRetries or 0),
                tostring(p3 and p3._tacoTipAnchorSide or "none"), p3Pts,
                tostring(p2 ~= nil), tostring(p2Shown),
                safeDiagValue(gState and gState.currentUnitGUID),
                safeDiagValue(gState and gState.ownerUnitGUID),
                tostring(gState and gState.portraitAnchored or false)),
            desync and "warn" or "info")
    end
    local traceEntries = getPortraitTraceEntries()
    if (#traceEntries > 0) then
        local last = traceEntries[#traceEntries]
        diagRow(s, "portrait last event", string.format(
            "#%s %s (%s) [tt=%s p3=%s] prev=%s -> new=%s (%s)",
            tostring(last.seq or #traceEntries), tostring(last.op or "?"),
            tostring(last.reason or "-"), tostring(last.ttShown), tostring(last.p3Shown),
            tostring(last.prevKey or "nil"), tostring(last.newKey or "nil"),
            tostring(last.outcome or "-")), "info")
    end
    local itemHooks = tonumber(ev.itemHook) or 0
    if (itemHooks > 0) then
        local unreadablePayload = tonumber(ev.itemPayloadUnreadable) or 0
        local secretLinks = tonumber(ev.itemSecretLink) or 0
        diagRow(s, "item tooltip hooks", string.format(
                "renders=%s, unreadable payload=%s, no payload=%s, secret link=%s, no link=%s",
                tostring(itemHooks), tostring(unreadablePayload),
                tostring(tonumber(ev.itemPayloadMissing) or 0), tostring(secretLinks),
                tostring(tonumber(ev.itemNoLink) or 0)),
            (unreadablePayload + secretLinks) > 0 and "warn" or "info")
    end
    -- Secret restrictions that are active right now. This is the row a user
    -- report needs: it answers "was this reported hover inside combat /
    -- an encounter / a restricted map" without the user having to know, and it
    -- is a read-only client state probe (no addon restrictions applied).
    diagRow(s, "secret restrictions", TT:RestrictionSnapshot(), "info")
    local itemRowsBefore = tonumber(ev.itemRowsLastBefore)
    local itemRowsAfter = tonumber(ev.itemRowsLastAfter)
    if (itemRowsBefore and itemRowsAfter) then
        local lost = tonumber(ev.itemRowsRemoved) or 0
        diagRow(s, "item row delta", string.format(
            "last hover: %s -> %s (ours %+d), hovers that LOST rows=%s",
            tostring(itemRowsBefore), tostring(itemRowsAfter), itemRowsAfter - itemRowsBefore,
            tostring(lost)), lost > 0 and "warn" or "info")
    end
    local refusedTally = ev.secretRefused
    if (type(refusedTally) == "table") then
        local list = {}
        for key, count in pairs(refusedTally) do
            list[#list + 1] = { key = tostring(key), count = tonumber(count) or 0 }
        end
        table.sort(list, function(a, b)
            if (a.count ~= b.count) then return a.count > b.count end
            return a.key < b.key
        end)
        local parts = {}
        for i = 1, #list do
            parts[#parts + 1] = list[i].key .. "=" .. tostring(list[i].count)
        end
        if (#parts > 0) then
            diagRow(s, "secret refusals by API", table.concat(parts, ", "), "warn")
        end
    end
    local lastItem = ev.lastItem
    if (type(lastItem) == "table") then
        diagRow(s, "last item hover", string.format(
            "id=%s, ours=%+d rows, payload=%s, secret link=%s, restrictions=%s, at %ss",
            tostring(lastItem.id or "?"), tonumber(lastItem.rowsAdded) or 0,
            tostring(lastItem.payload), tostring(lastItem.linkSecret),
            tostring(lastItem.restrictions), tostring(tonumber(lastItem.at) or 0)), "info")
    end
    if (portraitFailed > 0 and portraitAttempts == 0) then
        s.notes[#s.notes + 1] = "portraitSetFailed was incremented outside SetUnit instrumentation."
    end
    return s
end

local function collectInspectSection()
    local s = diagSection("inspect", "inspect engine & queue")
    if (not CI or type(CI.GetInspectStats) ~= "function") then
        diagRow(s, "inspect engine", "unavailable (LibForeverInspector did not load)", "error")
        return s
    end
    local ok, st = pcall(CI.GetInspectStats, CI)
    if (not ok or type(st) ~= "table") then
        diagRow(s, "inspect engine", "GetInspectStats failed: " .. tostring(st), "error")
        return s
    end
    local pendingStr = "none (idle)"
    if (st.pendingUnit) then
        pendingStr = string.format("unit='%s' (waiting %.1fs)", tostring(st.pendingUnit),
            tonumber(st.pendingDuration) or 0)
    end
    diagRow(s, "queue state", string.format("queue size: %s | in-flight: %s",
        tostring(st.queueLength or 0), pendingStr), "info")
    diagRow(s, "cache summary", string.format("%s players (%s stale, %s incomplete)",
        tostring(st.cacheCount or 0), tostring(st.staleCount or 0), tostring(st.incompleteCount or 0)), "info")
    local timeouts = tonumber(st.timeouts) or 0
    diagRow(s, "requests / timeouts", string.format("notifies=%s, ready=%s, timeouts=%s, rejected=%s",
        tostring(st.notifies or 0), tostring(st.ready or 0), tostring(timeouts),
        tostring(st.rejected or 0)), timeouts > 0 and "warn" or "info")
    diagRow(s, "queue overflow drops", st.queueOverflowDrops or 0, "info")
    diagRow(s, "queue drain drops", st.queueDrainedDrops or 0, "info")
    if (st.lastRejectedUnit) then
        diagRow(s, "last refusal", string.format("unit='%s', yards=%s, reason='%s'",
            tostring(st.lastRejectedUnit),
            st.lastRejectedDistance and (tostring(st.lastRejectedDistance) .. "yd") or "unknown",
            tostring(st.lastRejectedReason or "unknown")), "info")
    end
    diagRow(s, "learned max range", st.learnedRange and (tostring(st.learnedRange) .. "yd") or "unknown", "info")
    diagRow(s, "probe suppression", string.format("errors=%s, voice=%s, sound=%s",
        tostring(st.suppressed or 0), tostring(st.suppressedVoice or 0), tostring(st.suppressedSound or 0)), "info")
    if (st.lastError) then
        diagRow(s, "last inspect-call error", tostring(st.lastError), "warn")
    end
    diagRow(s, "proximity scan", string.format("enqueued=%s, fallback=%s, skipped_dist=%s",
        tostring(st.scanEnqueued or 0), tostring(st.scanFallback or 0), tostring(st.scanSkippedDistance or 0)), "info")
    return s
end

local function collectEventSection()
    local s = diagSection("events", "event counters (cumulative since /reload)")
    local ev = TT.ev or {}
    local total = (tonumber(ev.unitRender) or 0) + (tonumber(ev.gsCallback) or 0)
        + (tonumber(ev.portraitHide) or 0) + (tonumber(ev.portraitDestroy) or 0)
        + (tonumber(ev.portraitModelHidden) or 0)
    if (total == 0) then
        diagRow(s, "event counters", "no events recorded yet -- hover a character first", "info")
    end
    diagRow(s, "unit renders", ev.unitRender or 0, "info")
    diagRow(s, "GearScore callbacks", string.format("%s (reentrant=%s, wrong unit=%s)",
        tostring(ev.gsCallback or 0),
        tostring(ev.gsCallbackReentrant or 0),
        tostring(ev.gsCallbackWrongUnit or 0)), "info")
    diagRow(s, "GearScore callback misses", ev.gsCallbackNoUnit or 0, "info")
    diagRow(s, "portrait hides (on clear)", ev.portraitModelHidden or 0, "info")
    diagRow(s, "portrait teardowns", string.format("%s (destroys: %s)",
        tostring(ev.portraitHide or 0),
        tostring(ev.portraitDestroy or 0)), "info")
    diagRow(s, "portrait re-anchors", ev.portraitAnchor or 0, "info")
    diagRow(s, "portrait clear/hide ops", string.format(
        "clearModel=%s, onClearSkipped=%s, onHideRan=%s, onHideSkipped=%s",
        tostring(ev.portraitClearModelCalls or 0),
        tostring(ev.portraitOnClearSkipped or 0),
        tostring(ev.portraitOnHideRan or 0),
        tostring(ev.portraitOnHideSkipped or 0)), "info")
    local recentTrace = getPortraitTraceEntries()
    if (#recentTrace > 0) then
        local parts = {}
        local first = math.max(1, #recentTrace - 4)
        for i = first, #recentTrace do
            local t = recentTrace[i]
            parts[#parts + 1] = string.format("%s(%s->%s)",
                tostring(t.op), tostring(t.reason or "-"), tostring(t.outcome or "-"))
        end
        diagRow(s, "portrait last 5 events", table.concat(parts, " -> "), "info")
    end
    diagRow(s, "teardowns by reason", diagTeardownText(ev.teardownBy), "info")
    return s
end

local function collectInspectFrameSection()
    local s = diagSection("inspect-frame", "inspect frame UI")
    diagRow(s, "InspectModelFrame exists", InspectModelFrame ~= nil, "info")
    diagRow(s, "InspectPaperDollFrame exists", InspectPaperDollFrame ~= nil, "info")
    diagRow(s, "guild guard installed", rawget(_G, "_tacoTipInspectGuildGuarded") and true or false, "info")
    diagRow(s, "overlay initialised", TT.InitInspectFrame == nil, "info")
    diagRow(s, "InspectGearScore exists", rawget(_G, "InspectGearScore") ~= nil, "info")
    diagRow(s, "InspectAvgItemLvl exists", rawget(_G, "InspectAvgItemLvl") ~= nil, "info")
    diagRow(s, "InspectFrame exists", InspectFrame ~= nil, "info")
    if (InspectFrame) then
        local okShown, shown = pcall(function() return InspectFrame:IsShown() end)
        -- Do not use the "and value or fallback" idiom here: false is falsy, so a
        -- HIDDEN InspectFrame would report "unknown" instead of "false".
        if (okShown) then
            diagRow(s, "InspectFrame shown", (shown == true) and true or false, "info")
        else
            diagRow(s, "InspectFrame shown", "unknown", "info")
        end
        local inspected = "nil"
        if (InspectFrame.unit ~= nil) then
            inspected = (type(InspectFrame.unit) == "string") and InspectFrame.unit or "set"
        end
        diagRow(s, "InspectFrame.unit", inspected, "info")
    end
    return s
end

local function collectErrorsSection()
    local s = diagSection("errors", "error history")
    diagRow(s, "total errors caught", TT.totalErrorsCaught or 0, "info")
    local warnCount = (type(TT.warningLog) == "table") and #TT.warningLog or 0
    diagRow(s, "total warnings recorded", string.format("%s (log holds %s)",
            tostring(TT.totalWarnings or warnCount), tostring(warnCount)),
        (tonumber(TT.totalWarnings) or warnCount) > 0 and "warn" or "info")
    diagRow(s, "pipeline suppressed", (TT.ev and TT.ev.pipelineErrorsSuppressed) or 0, "info")
    diagRow(s, "last tooltip error", TT.lastTooltipError or "none",
        TT.lastTooltipError and "warn" or "info")
    local log = TT.errorLog
    if (type(log) ~= "table" or #log == 0) then
        diagRow(s, "recent error entries", "none recorded since /reload", "info")
    else
        local startIdx = math.max(1, #log - (DIAG_MAX_ERROR_ROWS - 1))
        local shown = 0
        for i = startIdx, #log do
            local entry = log[i]
            if (type(entry) == "table") then
                shown = shown + 1
                local value = string.format("[%.1fs] [%s] %s%s",
                    tonumber(entry.time) or 0,
                    tostring(entry.subsystem or "Error"),
                    tostring(entry.message or ""),
                    entry.context and (" (" .. tostring(entry.context) .. ")") or "")
                diagRow(s, "recent error " .. shown, value, "error")
            end
        end
        local older = #log - shown
        if (older > 0) then
            diagRow(s, "recent error entries", "...and " .. older .. " older "
                .. (older == 1 and "entry" or "entries"), "info")
        end
    end
    local wlog = TT.warningLog
    if (type(wlog) == "table" and #wlog > 0) then
        local wStart = math.max(1, #wlog - 3)
        local wShown = 0
        for i = wStart, #wlog do
            local entry = wlog[i]
            if (type(entry) == "table") then
                wShown = wShown + 1
                local value = string.format("[%.1fs] [%s] %s%s",
                    tonumber(entry.time) or 0,
                    tostring(entry.subsystem or "Warning"),
                    tostring(entry.message or ""),
                    entry.context and (" (" .. tostring(entry.context) .. ")") or "")
                diagRow(s, "recent warning " .. wShown, value, "warn")
            end
        end
    end
    return s
end

local function collectDiagnosticSections(problems)
    local builders = {
        collectEnvironmentSection,
        collectActiveUnitSection,
        collectTooltipSection,
        collectInspectSection,
        collectEventSection,
        collectInspectFrameSection,
        collectErrorsSection,
    }
    local sections = {}
    for i = 1, #builders do
        local ok, section = pcall(builders[i])
        if (ok and type(section) == "table") then
            sections[#sections + 1] = section
        else
            local id = DIAG_SECTION_ORDER[i] or ("section-" .. i)
            local failed = diagSection(id, id)
            diagRow(failed, "section failed", tostring(section), "error")
            sections[#sections + 1] = failed
            problems[#problems + 1] = {
                severity = "error",
                text = "diagnostics section '" .. tostring(id) .. "' failed: " .. tostring(section),
            }
        end
    end
    return sections
end

local function collectProblemSection(problems)
    local s = diagSection("problems", "problems")
    if (#problems == 0) then
        diagRow(s, "problems", "none detected (system healthy)", "ok")
        return s
    end
    local shown = 0
    for i = 1, #problems do
        if (shown >= DIAG_MAX_PROBLEM_ROWS) then break end
        local p = problems[i]
        shown = shown + 1
        local severity = (type(p) == "table" and p.severity == "error") and "error" or "warn"
        diagRow(s, "problem " .. shown .. " (" .. severity .. ")",
            (type(p) == "table" and p.text) or "unknown", severity)
    end
    local remaining = #problems - shown
    if (remaining > 0) then
        diagRow(s, "problems", "...and " .. remaining .. " more", "info")
    end
    return s
end

function TT:CollectDiagnostics()
    local elapsed, uptimeText = diagUptime()
    local okProblems, rawProblems = pcall(collectProblems)
    local problems
    if (not okProblems or type(rawProblems) ~= "table") then
        problems = { { severity = "error", text = "problem collection failed: " .. tostring(rawProblems) } }
    else
        problems = rawProblems
    end
    local sections = collectDiagnosticSections(problems)
    sections[#sections + 1] = collectProblemSection(problems)
    return {
        version = addOnVersion,
        uptime = elapsed,
        uptimeText = uptimeText,
        verdict = buildVerdict(problems),
        sections = sections,
        problems = problems,
    }
end

local function diagRenderRow(row)
    local label = tostring(row.label or "?")
    local value = tostring(row.value)
    local suffix = ""
    if (row.status == "warn") then
        suffix = " [warn]"
    elseif (row.status == "error") then
        suffix = " [error]"
    end
    print(string.format("|cff59f0dcTacoTip:|r %s: %s%s", label, value, suffix))
end

local function diagRenderSection(section)
    if (type(section) ~= "table") then return end
    print("|cff59f0dc-- " .. tostring(section.title or section.id or "section") .. " --|r")
    local rows = section.rows or {}
    for i = 1, #rows do
        if (type(rows[i]) == "table") then
            diagRenderRow(rows[i])
        end
    end
    local notes = section.notes or {}
    for i = 1, #notes do
        print("|cff59f0dcTacoTip:|r note: " .. tostring(notes[i]))
    end
end

function TT:PrintDiagnostics()
    print("|cff59f0dc===== TacoTip diagnostics (v" .. tostring(addOnVersion) .. ") =====|r")
    local ok, diag = pcall(function() return TT:CollectDiagnostics() end)
    if (not ok or type(diag) ~= "table") then
        local err = tostring(diag)
        print("|cff59f0dcTacoTip:|r verdict: PROBLEMS: diagnostics collection failed -- "
            .. err .. " [error]")
        print("|cff59f0dcTacoTip:|r version: " .. tostring(addOnVersion))
        print("|cff59f0dcTacoTip:|r load OK: " .. (TT.LOAD_OK and "yes"
            or ("NO -- main.lua stopped at stage: " .. tostring(TT.LOAD_STAGE))))
        print("|cff59f0dcTacoTip:|r client family: " .. tostring(CI and CI.family or "?"))
        print("|cff59f0dcTacoTip:|r interface: " .. tostring(CI and CI.interfaceVersion or "?"))
        print("|cff59f0dc================================|r")
        return
    end
    local verdict = diag.verdict or {}
    local verdictStatus = verdict.healthy and "ok" or (verdict.severity or "warn")
    local verdictSuffix = ""
    if (verdictStatus == "warn") then
        verdictSuffix = " [warn]"
    elseif (verdictStatus == "error") then
        verdictSuffix = " [error]"
    end
    print(string.format("|cff59f0dcTacoTip:|r verdict: %s%s",
        tostring(verdict.text or "UNKNOWN"), verdictSuffix))
    local sections = diag.sections or {}
    for i = 1, #sections do
        local okSection, errSection = pcall(diagRenderSection, sections[i])
        if (not okSection) then
            print("|cff59f0dcTacoTip:|r section failed: " .. tostring(errSection) .. " [error]")
        end
    end
    print("|cff59f0dc================================|r")
end

function TT:FormatDiagnosticTraces()
    local lines = {}
    lines[#lines + 1] = "===== TACOTIP DETAILED TRACE & DIAGNOSTICS LOG ====="
    lines[#lines + 1] = "Addon Version: " .. tostring(addOnVersion)
    lines[#lines + 1] = "Client: " ..
        tostring(CI and CI.family or "unknown") ..
        " (Interface: " .. tostring(CI and CI.interfaceVersion or "unknown") .. ")"
    lines[#lines + 1] = "Total Errors Caught: " .. tostring(TT.totalErrorsCaught or 0)
    lines[#lines + 1] = "Pipeline Errors Suppressed: " .. tostring((TT.ev and TT.ev.pipelineErrorsSuppressed) or 0)
    lines[#lines + 1] = ""

    local errLog = TT.errorLog or {}
    lines[#lines + 1] = string.format("--- Captured Errors (%d recorded) ---", #errLog)
    if (#errLog == 0) then
        lines[#lines + 1] = "  (No errors recorded since reload)"
    else
        for i = 1, #errLog do
            local e = errLog[i]
            lines[#lines + 1] = string.format("[%d] Time: %.1fs | Subsystem: %s%s",
                i, tonumber(e.time) or 0, tostring(e.subsystem or "Error"),
                e.context and (" | Context: " .. tostring(e.context)) or "")
            lines[#lines + 1] = "    Message: " .. tostring(e.message or "")
            if (e.stack) then
                lines[#lines + 1] = "    Stack Trace:\n" .. tostring(e.stack)
            end
        end
    end
    lines[#lines + 1] = ""

    local warnLog = TT.warningLog or {}
    lines[#lines + 1] = string.format("--- Captured Warnings (%d recorded) ---", #warnLog)
    if (#warnLog == 0) then
        lines[#lines + 1] = "  (No warnings recorded since reload)"
    else
        for i = 1, #warnLog do
            local w = warnLog[i]
            lines[#lines + 1] = string.format("[%d] Time: %.1fs | Subsystem: %s%s",
                i, tonumber(w.time) or 0, tostring(w.subsystem or "Warning"),
                w.context and (" | Context: " .. tostring(w.context)) or "")
            lines[#lines + 1] = "    Message: " .. tostring(w.message or "")
            if (w.stack) then
                lines[#lines + 1] = "    Trace:\n" .. tostring(w.stack)
            end
        end
    end
    lines[#lines + 1] = ""

    local ev = TT.ev or {}
    lines[#lines + 1] = "--- Event & Pipeline Counters ---"
    lines[#lines + 1] = string.format("  Unit Renders: %s | Unit Resolve Failures: %s (Last cause: %s)",
        tostring(ev.unitRender or 0), tostring(ev.resolveTooltipUnitFailed or 0),
        tostring(ev.resolveTooltipUnitLastCause or "none"))
    lines[#lines + 1] = string.format(
        "  Portrait Teardowns: %s (Destroys: %s, ClearModels: %s, Hidden: %s, Anchors: %s)",
        tostring(ev.portraitHide or 0), tostring(ev.portraitDestroy or 0), tostring(ev.portraitClearModelCalls or 0),
        tostring(ev.portraitModelHidden or 0), tostring(ev.portraitAnchor or 0))
    lines[#lines + 1] = string.format(
        "  Portrait Pipeline: Attempts=%s, Succeeded=%s, SetFailed=%s, CanSetFalse=%s, KeyHits=%s, 2DSets=%s",
        tostring(ev.portraitSetAttempts or 0), tostring(ev.portraitSetSucceeded or 0),
        tostring(ev.portraitSetFailed or 0), tostring(ev.portraitCanSetFalse or 0),
        tostring(ev.portraitKeyHits or 0), tostring(ev.portrait2DSets or 0))
    lines[#lines + 1] = string.format("  Portrait Hooks: OnHideRan=%s, OnHideSkipped=%s, OnClearSkipped=%s",
        tostring(ev.portraitOnHideRan or 0), tostring(ev.portraitOnHideSkipped or 0),
        tostring(ev.portraitOnClearSkipped or 0))
    lines[#lines + 1] = string.format("  GearScore Callbacks: %s (Reentrant: %s, Wrong Unit: %s, Misses: %s)",
        tostring(ev.gsCallback or 0), tostring(ev.gsCallbackReentrant or 0), tostring(ev.gsCallbackWrongUnit or 0),
        tostring(ev.gsCallbackNoUnit or 0))
    if (ev.teardownBy) then
        lines[#lines + 1] = "  Teardown Reasons: " .. diagTeardownText(ev.teardownBy)
    end
    lines[#lines + 1] = ""

    local portraitTrace = getPortraitTraceEntries()
    lines[#lines + 1] = string.format("--- Portrait Lifecycle Trace (%d entries) ---", #portraitTrace)
    if (#portraitTrace == 0) then
        lines[#lines + 1] = "  (No portrait lifecycle events recorded since reload)"
    else
        for i = 1, #portraitTrace do
            local p = portraitTrace[i]
            lines[#lines + 1] = string.format(
                "  [#%s %.2fs] %-12s reason=%-18s tt=%s p3=%s p2=%s cur=%s prevKey=%s newKey=%s keep=%s retain=%s out=%s",
                tostring(p.seq or i), tonumber(p.time) or 0, tostring(p.op or "?"),
                tostring(p.reason or "-"), tostring(p.ttShown), tostring(p.p3Shown), tostring(p.p2Shown),
                tostring(p.curGUID or "nil"), tostring(p.prevKey or "nil"), tostring(p.newKey or "nil"),
                tostring(p.keepModel), tostring(p.retainModel), tostring(p.outcome or "-"))
        end
    end
    lines[#lines + 1] = "================================================="

    return table.concat(lines, "\n")
end

function TT:FormatDiagnosticExport()
    local lines = {}
    lines[#lines + 1] = "```markdown"
    lines[#lines + 1] = "# TacoTip System Diagnostic Report"
    lines[#lines + 1] = string.format("- Addon Version: %s", tostring(addOnVersion))
    lines[#lines + 1] = string.format("- Client Family: %s (Interface: %s)", tostring(CI and CI.family or "unknown"),
        tostring(CI and CI.interfaceVersion or "unknown"))
    lines[#lines + 1] = string.format("- Load Status: %s (Stage: %s)", TT.LOAD_OK and "OK" or "FAILED",
        tostring(TT.LOAD_STAGE or "complete"))
    lines[#lines + 1] = string.format("- Total Errors Caught: %d", tonumber(TT.totalErrorsCaught) or 0)
    lines[#lines + 1] = string.format("- Pipeline Suppressed: %d",
        tonumber(TT.ev and TT.ev.pipelineErrorsSuppressed) or 0)
    lines[#lines + 1] = ""

    local ok, diag = pcall(TT.CollectDiagnostics, TT)
    if (ok and type(diag) == "table") then
        local verdict = diag.verdict or {}
        lines[#lines + 1] = string.format("## System Health: %s", tostring(verdict.text or "UNKNOWN"))
        lines[#lines + 1] = ""
        for _, sec in ipairs(diag.sections or {}) do
            if (type(sec) == "table") then
                lines[#lines + 1] = string.format("### %s", tostring(sec.title or sec.id or "Section"))
                for _, r in ipairs(sec.rows or {}) do
                    if (type(r) == "table") then
                        lines[#lines + 1] = string.format("- **%s**: %s", tostring(r.label or ""),
                            tostring(r.value or ""))
                    end
                end
                lines[#lines + 1] = ""
            end
        end
    end

    local errLog = TT.errorLog or {}
    if (#errLog > 0) then
        lines[#lines + 1] = string.format("## Captured Error Traces (%d)", #errLog)
        for i = 1, #errLog do
            local e = errLog[i]
            lines[#lines + 1] = string.format("[%d] (%.1fs) [%s] %s%s",
                i, tonumber(e.time) or 0, tostring(e.subsystem or "Error"),
                tostring(e.message or ""),
                e.context and (" (" .. tostring(e.context) .. ")") or "")
            if (e.stack) then
                lines[#lines + 1] = tostring(e.stack)
            end
        end
        lines[#lines + 1] = ""
    end

    local warnLog = TT.warningLog or {}
    if (#warnLog > 0) then
        lines[#lines + 1] = string.format("## Captured Warning Traces (%d)", #warnLog)
        for i = 1, #warnLog do
            local w = warnLog[i]
            lines[#lines + 1] = string.format("[%d] (%.1fs) [%s] %s%s",
                i, tonumber(w.time) or 0, tostring(w.subsystem or "Warning"),
                tostring(w.message or ""),
                w.context and (" (" .. tostring(w.context) .. ")") or "")
            if (w.stack) then
                lines[#lines + 1] = tostring(w.stack)
            end
        end
        lines[#lines + 1] = ""
    end

    local portraitTrace = getPortraitTraceEntries()
    if (#portraitTrace > 0) then
        lines[#lines + 1] = string.format("## Portrait Lifecycle Trace (%d)", #portraitTrace)
        for i = 1, #portraitTrace do
            local p = portraitTrace[i]
            lines[#lines + 1] = string.format(
                "- [#%s %.2fs] `%s` (%s) ttShown=%s p3Shown=%s cur=%s prevKey=%s newKey=%s keep=%s retain=%s out=%s",
                tostring(p.seq or i), tonumber(p.time) or 0, tostring(p.op or "?"),
                tostring(p.reason or "-"), tostring(p.ttShown), tostring(p.p3Shown),
                tostring(p.curGUID or "nil"), tostring(p.prevKey or "nil"), tostring(p.newKey or "nil"),
                tostring(p.keepModel), tostring(p.retainModel), tostring(p.outcome or "-"))
        end
        lines[#lines + 1] = ""
    end

    lines[#lines + 1] = "```"
    return table.concat(lines, "\n")
end

-- ============================================================================
-- PROGRESSION & GEAR LEVELING SYSTEM
-- ============================================================================

local GEAR_SLOT_NAMES = {
    [1] = "Head",
    [2] = "Neck",
    [3] = "Shoulder",
    [5] = "Chest",
    [6] = "Waist",
    [7] = "Legs",
    [8] = "Feet",
    [9] = "Wrist",
    [10] = "Hands",
    [11] = "Ring 1",
    [12] = "Ring 2",
    [13] = "Trinket 1",
    [14] = "Trinket 2",
    [15] = "Back",
    [16] = "Main Hand",
    [17] = "Off Hand",
    [18] = "Ranged / Relic",
}

local GEAR_SLOTS_ORDERED = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }

local TROPHY_DEFINITIONS = {
    { id = "first_steps",    name = "First Steps",        desc = "Equip armor in all primary combat slots",         icon = 132646 },
    { id = "level_10",       name = "Rising Star",        desc = "Reach Gear Level 10",                             icon = 134420 },
    { id = "level_20",       name = "Dungeon Delver",     desc = "Reach Gear Level 20",                             icon = 132341 },
    { id = "level_30",       name = "Raid Ready",         desc = "Reach Gear Level 30",                             icon = 132338 },
    { id = "level_40",       name = "Heroic Champion",    desc = "Reach Gear Level 40",                             icon = 132347 },
    { id = "level_50",       name = "Legendary Vanguard", desc = "Reach Gear Level 50",                             icon = 132333 },
    { id = "giant_leap",     name = "Giant Leap",         desc = "Equip an upgrade with +40 or more GearScore",     icon = 132349 },
    { id = "purple_reign",   name = "Purple Reign",       desc = "Equip full Epic or Legendary items in all slots", icon = 132847 },
    { id = "upgrade_hunter", name = "Gear Collector",     desc = "Record 25 equipment upgrades in your chronicle",  icon = 133580 },
    { id = "century_club",   name = "Century Club",       desc = "Record 100 equipment upgrades in your chronicle", icon = 133582 },
}

local function getProgressionCharKey()
    local name = (type(UnitName) == "function" and UnitName("player")) or nil
    local realm = (type(GetRealmName) == "function" and GetRealmName()) or nil
    if (name and not isSecretValue(name) and realm and not isSecretValue(realm) and name ~= "" and realm ~= "") then
        return name .. "-" .. realm
    end
    return "Default-Character"
end

function TT:GetGearLevelStepSize()
    if (CI and CI.IsRetail and CI:IsRetail()) then
        return 150
    elseif (CI and CI.IsWotlk and CI:IsWotlk()) then
        return 100
    elseif (CI and CI.IsTBC and CI:IsTBC()) then
        return 60
    else
        return 25
    end
end

function TT:GetGearLevelInfo(score)
    score = (type(score) == "number" and score > 0) and score or 0
    local step = TT:GetGearLevelStepSize()
    local level = math.floor(score / step) + 1
    local currentFloor = (level - 1) * step
    local nextThreshold = level * step
    local progressInLevel = score - currentFloor
    local percent = math.min(100, math.max(0, math.floor((progressInLevel / step) * 100 + 0.5)))
    local remaining = math.max(0, nextThreshold - score)

    local title, tierColorHex
    if (level <= 5) then
        title = "Novice"
        tierColorHex = "FFFFFFFF"
    elseif (level <= 10) then
        title = "Apprentice"
        tierColorHex = "FF1EFF00"
    elseif (level <= 15) then
        title = "Scout"
        tierColorHex = "FF1EFF00"
    elseif (level <= 20) then
        title = "Adventurer"
        tierColorHex = "FF0070DD"
    elseif (level <= 25) then
        title = "Veteran"
        tierColorHex = "FF0070DD"
    elseif (level <= 30) then
        title = "Gladiator"
        tierColorHex = "FFA335EE"
    elseif (level <= 35) then
        title = "Champion"
        tierColorHex = "FFA335EE"
    elseif (level <= 40) then
        title = "Hero of the Realm"
        tierColorHex = "FFA335EE"
    elseif (level <= 45) then
        title = "Conqueror"
        tierColorHex = "FFFF8000"
    elseif (level <= 50) then
        title = "Warlord"
        tierColorHex = "FFFF8000"
    elseif (level <= 55) then
        title = "Grand Champion"
        tierColorHex = "FFE6CC80"
    else
        title = "Immortal Legend"
        tierColorHex = "FFFFD100"
    end

    return {
        level = level,
        title = title,
        tierColorHex = tierColorHex,
        score = score,
        step = step,
        nextThreshold = nextThreshold,
        currentFloor = currentFloor,
        progress = progressInLevel,
        percent = percent,
        remaining = remaining,
    }
end

function TT:GetTrophyDefinitions()
    return TROPHY_DEFINITIONS
end

function TT:GetPlayerProgression()
    if (not TacoTipConfig) then
        TacoTipConfig = {}
    end
    if (type(TacoTipConfig.progression) ~= "table") then
        TacoTipConfig.progression = {}
    end
    local key = getProgressionCharKey()
    local rec = TacoTipConfig.progression[key]
    if (type(rec) ~= "table") then
        rec = {
            currentScore = 0,
            peakScore = 0,
            peakDate = 0,
            currentLevel = 1,
            snapshots = {},
            history = {},
            trophies = {},
        }
        TacoTipConfig.progression[key] = rec
    end
    if (type(rec.snapshots) ~= "table") then rec.snapshots = {} end
    if (type(rec.history) ~= "table") then rec.history = {} end
    if (type(rec.timeline) ~= "table") then rec.timeline = {} end
    if (type(rec.trophies) ~= "table") then rec.trophies = {} end
    return rec, key
end

function TT:GetGearScoreProgressCap(currentScore, peakScore)
    local gs = TT_GS or GearScore
    local bracketSize = (gs and type(gs.BRACKET_SIZE) == "number" and gs.BRACKET_SIZE > 0) and gs.BRACKET_SIZE or nil
    if (not bracketSize) then
        if (CI and CI.IsTBC and CI:IsTBC()) then
            bracketSize = 400
        elseif (CI and ((CI.IsWotlk and CI:IsWotlk()) or (CI.IsRetail and CI:IsRetail()))) then
            bracketSize = 1000
        else
            bracketSize = 200
        end
    end
    local baseCap = (gs and type(gs.MAX_SCORE) == "number" and gs.MAX_SCORE > 0)
        and gs.MAX_SCORE or (bracketSize * 7)
    local topObserved = math.max(tonumber(currentScore) or 0, tonumber(peakScore) or 0)
    local cap = baseCap
    if (topObserved > cap) then
        cap = math.ceil(topObserved / bracketSize) * bracketSize
    end
    return cap, bracketSize, baseCap
end

function TT:GetProgressionBarSnapshots(maxPins)
    maxPins = maxPins or 18
    local rec = TT:GetPlayerProgression()
    local timeline = rec.timeline
    local history = rec.history
    local cap = TT:GetGearScoreProgressCap(rec.currentScore, rec.peakScore)
    local candidates = {}

    if (type(timeline) == "table" and #timeline > 0) then
        for i = 1, #timeline do
            local e = timeline[i]
            if (type(e) == "table" and (tonumber(e.totalGS) or 0) > 0) then
                candidates[#candidates + 1] = e
            end
        end
    elseif (type(history) == "table" and #history > 0) then
        -- Backfill timeline markers cleanly for characters with existing upgrade logs.
        for i = #history, 1, -1 do
            local h = history[i]
            if (type(h) == "table" and (tonumber(h.totalGS) or 0) > 0) then
                local info = TT:GetGearLevelInfo(h.totalGS)
                candidates[#candidates + 1] = {
                    time = h.time or 0,
                    totalGS = h.totalGS,
                    avgILvl = h.newILvl or rec.avgItemLevel or 0,
                    level = h.level or info.level,
                    title = info.title,
                    tierColorHex = info.tierColorHex,
                    slotName = h.slotName,
                    newLink = h.newLink,
                    deltaGS = h.deltaGS,
                    newGS = h.newGS,
                }
            end
        end
    end

    if (#candidates == 0) then
        return {}, cap
    end

    -- Deduplicate markers too close in GS (~2% of bar width) while preserving
    -- the earliest, highest peak, and latest progression milestones.
    local minGap = math.max(8, math.floor(cap * 0.02))
    local filtered = {}
    local peakIdx, peakVal = 1, tonumber(candidates[1].totalGS) or 0
    for i = 2, #candidates do
        local gsVal = tonumber(candidates[i].totalGS) or 0
        if (gsVal >= peakVal) then
            peakVal = gsVal
            peakIdx = i
        end
    end

    for i = 1, #candidates do
        local c = candidates[i]
        local gsVal = tonumber(c.totalGS) or 0
        local keep = (i == 1 or i == #candidates or i == peakIdx)
        if (not keep) then
            keep = true
            for j = 1, #filtered do
                if (math.abs((tonumber(filtered[j].totalGS) or 0) - gsVal) < minGap) then
                    keep = false
                    break
                end
            end
        end
        if (keep) then
            filtered[#filtered + 1] = c
        end
    end

    if (#filtered > maxPins) then
        local thinned = {}
        local step = (#filtered - 1) / math.max(1, maxPins - 1)
        for p = 0, maxPins - 1 do
            local pick = math.min(#filtered, math.floor(1 + p * step + 0.5))
            if (thinned[#thinned] ~= filtered[pick]) then
                thinned[#thinned + 1] = filtered[pick]
            end
        end
        filtered = thinned
    end

    table.sort(filtered, function(a, b)
        local ga, gb = tonumber(a.totalGS) or 0, tonumber(b.totalGS) or 0
        if (ga ~= gb) then return ga < gb end
        return (tonumber(a.time) or 0) < (tonumber(b.time) or 0)
    end)

    return filtered, cap
end

function TT:CheckTrophies(rec, currentScore, levelInfo, isSilent)
    local newlyUnlocked = {}
    local historyCount = #rec.history

    local allSlotsFilled = true
    local allSlotsEpic = true
    for _, slotID in ipairs(GEAR_SLOTS_ORDERED) do
        local snap = rec.snapshots[slotID]
        if (not snap or not snap.link or snap.link == "") then
            allSlotsFilled = false
            allSlotsEpic = false
        elseif (snap.rarity and snap.rarity < 4) then
            allSlotsEpic = false
        end
    end

    local checks = {
        first_steps = allSlotsFilled,
        level_10 = levelInfo.level >= 10,
        level_20 = levelInfo.level >= 20,
        level_30 = levelInfo.level >= 30,
        level_40 = levelInfo.level >= 40,
        level_50 = levelInfo.level >= 50,
        purple_reign = allSlotsEpic and allSlotsFilled,
        upgrade_hunter = historyCount >= 25,
        century_club = historyCount >= 100,
    }

    local now = (type(GetServerTime) == "function" and GetServerTime()) or time()
    for _, def in ipairs(TROPHY_DEFINITIONS) do
        local earned = checks[def.id]
        if (earned and not rec.trophies[def.id]) then
            rec.trophies[def.id] = {
                unlockedAt = now,
                score = currentScore,
                level = levelInfo.level,
            }
            if (not isSilent) then
                newlyUnlocked[#newlyUnlocked + 1] = def
            end
        end
    end

    return newlyUnlocked
end

function TT:EvaluatePlayerEquipment(isSilent, forceBaseline)
    if (not TT_GS or type(TT_GS.GetScore) ~= "function") then
        return
    end

    local rec, _ = TT:GetPlayerProgression()
    local currentScore, avgILvl = TT_GS:GetScore("player")
    currentScore = tonumber(currentScore) or 0
    avgILvl = tonumber(avgILvl) or 0
    if (currentScore <= 0) then
        return
    end

    local levelInfo = TT:GetGearLevelInfo(currentScore)
    local previousLevel = rec.currentLevel or 1
    local now = (type(GetServerTime) == "function" and GetServerTime()) or time()

    local getLink = _G.GetInventoryItemLink

    local chat = _G.DEFAULT_CHAT_FRAME
    local playSound = _G.PlaySound
    local soundKit = _G.SOUNDKIT

    local historyCountBefore = #rec.history
    local lastChangedSlotName, lastChangedLink, lastDeltaGS

    for _, slotID in ipairs(GEAR_SLOTS_ORDERED) do
        local link = nil
        if (type(getLink) == "function") then
            local okLink, rawLink = pcall(getLink, "player", slotID)
            if (okLink and not isSecretValue(rawLink)) then
                link = rawLink
            end
        end
        local oldSnap = rec.snapshots[slotID]
        local oldLink = oldSnap and oldSnap.link

        local isChange = (link and not isSecretValue(link) and not safeEquals(link, oldLink))
        local isBaseline = (not isSilent and (forceBaseline or historyCountBefore == 0) and link and not isSecretValue(link))

        if (isChange or isBaseline) then
            local slotGS, slotILvl, itemRarity = 0, 0, 1
            if (TT_GS.GetItemScore) then
                local gs, ilvl = TT_GS:GetItemScore(link)
                slotGS = tonumber(gs) or 0
                slotILvl = tonumber(ilvl) or 0
            end
            if (type(GetItemInfo) == "function" and link) then
                local okInfo, _, _, r = pcall(GetItemInfo, link)
                if (okInfo and not isSecretValue(r) and r) then itemRarity = r end
            end

            local oldGS = (oldSnap and not isBaseline) and oldSnap.gs or 0
            local oldILvl = (oldSnap and not isBaseline) and oldSnap.ilvl or 0
            if (isChange or isBaseline) then
                lastChangedSlotName = GEAR_SLOT_NAMES[slotID] or ("Slot " .. slotID)
                lastChangedLink = link
                lastDeltaGS = (oldSnap and oldGS > 0 and not isBaseline) and (slotGS - oldGS) or slotGS
            end

            if (not isSilent and ((oldSnap and slotGS > oldGS) or (not oldSnap and slotGS > 0) or isBaseline)) then
                local deltaGS = (oldSnap and oldGS > 0 and not isBaseline) and (slotGS - oldGS) or slotGS
                local deltaILvl = (oldSnap and oldILvl > 0 and not isBaseline) and math.max(0, slotILvl - oldILvl) or
                    slotILvl
                table.insert(rec.history, 1, {
                    time = now,
                    slotID = slotID,
                    slotName = GEAR_SLOT_NAMES[slotID] or ("Slot " .. slotID),
                    oldLink = isBaseline and nil or oldLink,
                    newLink = link,
                    oldILvl = oldILvl,
                    newILvl = slotILvl,
                    oldGS = oldGS,
                    newGS = slotGS,
                    deltaGS = deltaGS,
                    deltaILvl = deltaILvl,
                    totalGS = currentScore,
                    level = levelInfo.level,
                })

                if (deltaGS >= 40 and not isBaseline and not rec.trophies["giant_leap"]) then
                    rec.trophies["giant_leap"] = {
                        unlockedAt = now,
                        score = currentScore,
                        level = levelInfo.level,
                    }
                    if (TacoTipConfig.progression_chat ~= false and chat and chat.AddMessage) then
                        chat:AddMessage(string.format(
                            "|cFFFFB81C[TacoTip]|r |cFFB4E634🏆 Achievement Unlocked:|r |cFFFFD100Giant Leap|r (+%d GearScore upgrade)!",
                            deltaGS))
                    end
                end

                local maxHist = TacoTipConfig.progression_history_cap or 500
                while (#rec.history > maxHist) do
                    table.remove(rec.history)
                end
            end

            rec.snapshots[slotID] = {
                link = link,
                gs = slotGS,
                ilvl = slotILvl,
                rarity = itemRarity,
            }
        elseif (not link and oldLink and not isBaseline) then
            rec.snapshots[slotID] = nil
        end
    end

    if (not isSilent and #rec.history == 0) then
        for _, slotID in ipairs(GEAR_SLOTS_ORDERED) do
            local snap = rec.snapshots[slotID]
            if (snap and snap.link and (snap.gs or 0) > 0) then
                table.insert(rec.history, {
                    time = now,
                    slotID = slotID,
                    slotName = GEAR_SLOT_NAMES[slotID] or ("Slot " .. slotID),
                    oldLink = nil,
                    newLink = snap.link,
                    oldILvl = 0,
                    newILvl = snap.ilvl or 0,
                    oldGS = 0,
                    newGS = snap.gs or 0,
                    deltaGS = snap.gs or 0,
                    deltaILvl = snap.ilvl or 0,
                    totalGS = currentScore,
                    level = levelInfo.level,
                })
            end
        end
    end

    rec.currentScore = currentScore
    rec.avgItemLevel = avgILvl
    if (currentScore > (rec.peakScore or 0)) then
        rec.peakScore = currentScore
        rec.peakDate = now
    end

    local equippedCount, epicCount = 0, 0
    for _, slotID in ipairs(GEAR_SLOTS_ORDERED) do
        local snap = rec.snapshots[slotID]
        if (snap and snap.link and snap.link ~= "") then
            equippedCount = equippedCount + 1
            if (snap.rarity and snap.rarity >= 4) then
                epicCount = epicCount + 1
            end
        end
    end
    local prevTimeline = rec.timeline[#rec.timeline]
    if ((not prevTimeline) or forceBaseline or math.abs((prevTimeline.totalGS or 0) - currentScore) >= 1) then
        rec.timeline[#rec.timeline + 1] = {
            time = now,
            totalGS = currentScore,
            avgILvl = avgILvl,
            level = levelInfo.level,
            title = levelInfo.title,
            tierColorHex = levelInfo.tierColorHex,
            equippedCount = equippedCount,
            totalSlots = #GEAR_SLOTS_ORDERED,
            epicCount = epicCount,
            slotName = lastChangedSlotName,
            newLink = lastChangedLink,
            deltaGS = lastDeltaGS,
        }
        local maxTimeline = 80
        while (#rec.timeline > maxTimeline) do
            table.remove(rec.timeline, 1)
        end
    end

    -- Level-up detection
    if (not isSilent and levelInfo.level > previousLevel and previousLevel > 0) then
        rec.currentLevel = levelInfo.level
        if (TacoTipConfig.progression_chat ~= false and chat and chat.AddMessage) then
            chat:AddMessage(string.format(
                "|cFFFFB81C[TacoTip]|r |cFFB4E634★ LEVEL UP! ★|r You reached |c%sGear Level %d: %s|r (|cFFFFD100%d GS|r)!",
                levelInfo.tierColorHex or "FFFFD100",
                levelInfo.level, levelInfo.title, currentScore))
        end
        if (TacoTipConfig.progression_sound ~= false and playSound) then
            if (soundKit and soundKit.UI_EPICLOOT_TOAST) then
                pcall(playSound, soundKit.UI_EPICLOOT_TOAST)
            elseif (soundKit and soundKit.LEVEL_UP) then
                pcall(playSound, soundKit.LEVEL_UP)
            else
                pcall(playSound, 888)
            end
        end
    else
        rec.currentLevel = levelInfo.level
    end

    local newlyUnlocked = TT:CheckTrophies(rec, currentScore, levelInfo, isSilent)
    if (not isSilent and #newlyUnlocked > 0 and TacoTipConfig.progression_chat ~= false) then
        for _, trophy in ipairs(newlyUnlocked) do
            if (chat and chat.AddMessage) then
                chat:AddMessage(string.format(
                    "|cFFFFB81C[TacoTip]|r |cFFB4E634🏆 Achievement Unlocked:|r |cFFFFD100%s|r - %s",
                    trophy.name, trophy.desc))
            end
        end
    end

    if (TT.RefreshProgressionDashboard) then
        TT:RefreshProgressionDashboard()
    end
end

function TT:ClearPlayerProgression()
    local rec, _ = TT:GetPlayerProgression()
    rec.history = {}
    rec.timeline = {}
    rec.trophies = {}
    rec.peakScore = rec.currentScore or 0
    rec.peakDate = (type(GetServerTime) == "function" and GetServerTime()) or time()
    TT:EvaluatePlayerEquipment(true)
end

function TT:ExportProgressionReport()
    local rec, key = TT:GetPlayerProgression()
    local info = TT:GetGearLevelInfo(rec.currentScore or 0)
    local lines = {}
    lines[#lines + 1] = string.format("# ⚡ TacoTip Progression Report — %s", tostring(key))
    lines[#lines + 1] = ""
    lines[#lines + 1] = string.format("- **Gear Level:** Level %d (%s)", info.level, info.title)
    lines[#lines + 1] = string.format("- **Current GearScore:** %d", info.score)
    lines[#lines + 1] = string.format("- **All-Time Peak GearScore:** %d", rec.peakScore or info.score)
    lines[#lines + 1] = string.format("- **Average Item Level:** %d", math.floor(rec.avgItemLevel or 0))
    lines[#lines + 1] = string.format("- **Total Upgrades Recorded:** %d", #rec.history)

    local unlockedCount = 0
    for _ in pairs(rec.trophies) do unlockedCount = unlockedCount + 1 end
    lines[#lines + 1] = string.format("- **Trophies Unlocked:** %d / %d", unlockedCount, #TROPHY_DEFINITIONS)
    lines[#lines + 1] = ""
    lines[#lines + 1] = "### 🏆 Unlocked Achievements"
    for _, def in ipairs(TROPHY_DEFINITIONS) do
        local tr = rec.trophies[def.id]
        if (tr) then
            lines[#lines + 1] = string.format("- [x] **%s** — %s", def.name, def.desc)
        else
            lines[#lines + 1] = string.format("- [ ] **%s** — %s", def.name, def.desc)
        end
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = "### 📜 Recent Equipment Upgrades"
    local count = math.min(10, #rec.history)
    if (count == 0) then
        lines[#lines + 1] = "_No upgrades recorded yet._"
    else
        for i = 1, count do
            local h = rec.history[i]
            lines[#lines + 1] = string.format("%d. **%s** (%s) ➔ +%d GS (iLvl %d ➔ %d)",
                i, h.slotName, h.newLink or "Unknown", h.deltaGS, h.oldILvl or 0, h.newILvl or 0)
        end
    end
    lines[#lines + 1] = ""
    return table.concat(lines, "\n")
end

local function onEvent(self, event, ...)
    if (event == "PLAYER_EQUIPMENT_CHANGED") then
        -- Self Pawn is cached live (no inspect record); a gear change makes the
        -- last score stale, so drop it before the next render.
        TT._selfPawnMemo = nil
        if (PaperDollFrame and PaperDollFrame:IsShown()) then
            TT:RefreshCharacterFrame()
        end
        if (TT.EvaluatePlayerEquipment) then
            TT:EvaluatePlayerEquipment(false)
        end
    elseif (event == "MODIFIER_STATE_CHANGED") then
        -- The wide/mini style only reads the shift key (IsShiftKeyDown in
        -- onTooltipSetUnit), so ctrl/alt press and release used to rebuild the
        -- whole unit tooltip for no visual change. The event payload is
        -- (key, down); only the two shift keys matter.
        local key = ...
        if ((key == "LSHIFT" or key == "RSHIFT")
                and GameTooltip and GameTooltip:IsShown()
                and (TacoTipConfig.tip_style == 2 or TacoTipConfig.tip_style == 4)) then
            local unit = resolveTooltipUnit(GameTooltip)
            if (unit and safeUnitIsPlayer(unit)) then
                refreshUnitTooltip(unit)
            end
        end
    elseif (event == "UNIT_TARGET") then
        if (GameTooltip and GameTooltip:IsShown() and TacoTipConfig.show_target) then
            local unit = ...
            if (unit) then
                local ttUnit = resolveTooltipUnit(GameTooltip)
                if (ttUnit and safeUnitExists(unit) and safeUnitIsUnit(unit, ttUnit)) then
                    refreshUnitTooltip(unit)
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
            if (TT.InitMinimapIcon) then
                TT:InitMinimapIcon()
            end
            if (TT.ApplyTooltipScale) then
                TT:ApplyTooltipScale()
            end
            if (TT.EvaluatePlayerEquipment) then
                TT:EvaluatePlayerEquipment(true)
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
            local p = TacoTipConfig.custom_pos
            if (p) then
                if (type(p) ~= "table" or type(p[1]) ~= "string" or type(p[3]) ~= "number" or type(p[4]) ~= "number") then
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
            if (type(TT.InitInspectFrame) == "function" and InspectModelFrame and InspectPaperDollFrame) then
                pcall(TT.InitInspectFrame, TT)
                TT.InitInspectFrame = nil
            end
            CAfter(3, function()
                print("|cff59f0dcTacoTip v" ..
                    addOnVersion .. " " .. L["TEXT_HELP_WELCOME"] .. " (Type |cffffb81c/tt|r to open settings dashboard)")
                if (first_login) then
                    print("|cff59f0dcTacoTip:|r " .. L["TEXT_HELP_FIRST_LOGIN"])
                end
            end)
        elseif (addon == "Blizzard_InspectUI") then
            if (type(TT.InitInspectFrame) == "function" and InspectModelFrame and InspectPaperDollFrame) then
                pcall(TT.InitInspectFrame, TT)
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
                        if (TacoTipConfig.instant_fade and not safeUnitExists("mouseover") and GameTooltip and GameTooltip:IsShown() and ((GameTooltip.IsUnit and GameTooltip:IsUnit("mouseover")) or (GameTooltip.GetUnit and select(2, GameTooltip:GetUnit()) == "mouseover"))) then
                            GameTooltip:Hide()
                        end
                    end)
                end)
                state.fadeTimer = timer
            end
        end
    elseif (event == "INVENTORY_READY" or event == "TALENTS_READY") then
        if (type(TT.InitInspectFrame) == "function" and InspectModelFrame and InspectPaperDollFrame) then
            pcall(TT.InitInspectFrame, TT)
            TT.InitInspectFrame = nil
        end
        local guid = ...
        if (guid and not TT.isSecretValue(guid)) then
            local invData = (CI and type(CI.GetUnitData) == "function") and CI:GetUnitData(guid) or nil
            local rev = invData and invData._itemsRev
            TT._lastItemsRev = TT._lastItemsRev or {}
            local prevRev = TT._lastItemsRev[guid]
            local itemsUpdated = (not invData) or (not invData.incomplete) or (rev ~= nil and rev ~= prevRev)
            -- Only reset GearScore retry/memo when committed gear actually completed or
            -- changed; intermediate incomplete cacheUnitData retries must NOT reset the
            -- exponential backoff ladder or spam WarmGearItemData.
            if (event == "INVENTORY_READY" and itemsUpdated) then
                if (rev ~= nil) then
                    if (TT._lastItemsRev[guid] == nil) then
                        TT._lastItemsRevCount = (TT._lastItemsRevCount or 0) + 1
                        if (TT._lastItemsRevCount > GS_SCORE_MEMO_CAP) then
                            TT._lastItemsRev = {}
                            TT._lastItemsRevCount = 1
                        end
                    end
                    TT._lastItemsRev[guid] = rev
                end
                TT.clearGearScoreRetry(guid)
                TT.clearPawnRetry(guid)
                TT.clearGearScoreMemo(guid)
                TT:WarmGearItemData(guid)
            elseif (event == "TALENTS_READY") then
                TT.clearPawnRetry(guid)
            end
            local ttUnit = resolveTooltipUnit(GameTooltip)
            if (ttUnit and TT.safeEquals(TT.safeUnitGUID(ttUnit), guid)) then
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
                    refreshUnitTooltip(ttUnit)
                end
            end
            if (event == "INVENTORY_READY") then
                if (InspectFrame and InspectFrame:IsShown()) then
                    TT:RefreshInspectFrame()
                end
            end
        end
    elseif (event == "PLAYER_LOGIN") then
        if (TT.EvaluatePlayerEquipment) then
            TT:EvaluatePlayerEquipment(true)
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
    f:RegisterEvent("PLAYER_LOGIN")
    CI.RegisterCallback(addOnName, "INVENTORY_READY", function(...) return safeCall(onEvent, f, ...) end)
    CI.RegisterCallback(addOnName, "TALENTS_READY", function(...) return safeCall(onEvent, f, ...) end)
    TT.frame = f
end

do
    local LDB_ICON_PATH = "Interface\\AddOns\\" .. tostring(addOnName or "TacoTip") .. "\\logo.tga"

    local function ensureMinimapTable()
        if (type(TacoTipConfig) ~= "table") then
            TacoTipConfig = {}
        end
        if (type(TacoTipConfig.minimap) ~= "table") then
            TacoTipConfig.minimap = {}
        end
        local hideFlag = (TacoTipConfig.show_minimap == false)
        TacoTipConfig.minimap.hide = hideFlag
        return TacoTipConfig.minimap
    end

    local function getLibs()
        if (type(LibStub) ~= "function" and type(LibStub) ~= "table") then
            return nil, nil
        end
        local okLdb, ldb = pcall(LibStub, "LibDataBroker-1.1", true)
        local okIcon, icon = pcall(LibStub, "LibDBIcon-1.0", true)
        if (not okLdb or type(ldb) ~= "table") then ldb = nil end
        if (not okIcon or type(icon) ~= "table") then icon = nil end
        return ldb, icon
    end

    function TT:InitMinimapIcon()
        local ldb, icon = getLibs()
        if (not ldb or not icon) then
            return false
        end
        local db = ensureMinimapTable()
        local obj = ldb:GetDataObjectByName("TacoTip")
        if (not obj) then
            obj = ldb:NewDataObject("TacoTip", {
                type = "launcher",
                text = "TacoTip",
                icon = LDB_ICON_PATH,
                OnClick = function(_, button)
                    if (button == "RightButton") then
                        if (TT.ShowStandaloneDashboard) then
                            pcall(TT.ShowStandaloneDashboard, TT, "diagnostics")
                        end
                    elseif (IsShiftKeyDown and IsShiftKeyDown()) then
                        if (SlashCmdList and type(SlashCmdList.TACOTIP) == "function") then
                            pcall(SlashCmdList.TACOTIP, "custom")
                        end
                    else
                        if (TT.ToggleStandaloneDashboard) then
                            pcall(TT.ToggleStandaloneDashboard, TT)
                        end
                    end
                end,
                OnTooltipShow = function(tooltip)
                    if (not tooltip or type(tooltip.AddLine) ~= "function") then
                        return
                    end
                    local clientTag = (CI and CI.GetClientLabel and CI:GetClientLabel()) or "WoW"
                    tooltip:AddLine(string.format("|cff59f0dcTacoTip|r |cffffb81cv%s|r", tostring(addOnVersion or "1.0.2")))
                    tooltip:AddLine("|cff9ca3af" .. tostring(clientTag) .. "|r", 0.7, 0.72, 0.75)
                    if (TT.GetPlayerProgression) then
                        local okProg, rec = pcall(TT.GetPlayerProgression, TT)
                        if (okProg and type(rec) == "table" and (tonumber(rec.currentScore) or 0) > 0) then
                            local gs = math.floor((tonumber(rec.currentScore) or 0) + 0.5)
                            local ilvl = tonumber(rec.avgItemLevel) or 0
                            local tierInfo = (TT.GetGearLevelInfo and TT:GetGearLevelInfo(gs)) or nil
                            local tierStr = (tierInfo and tierInfo.title) and (" |cff" .. (tierInfo.tierColorHex or "b4e634") .. "[" .. tierInfo.title .. "]|r") or ""
                            tooltip:AddLine(" ")
                            if (tooltip.AddDoubleLine) then
                                tooltip:AddDoubleLine("GearScore", string.format("|cffffb81c%d|r%s", gs, tierStr), 0.78, 0.80, 0.84, 1, 1, 1)
                                if (ilvl > 0) then
                                    tooltip:AddDoubleLine("Avg Item Level", string.format("%.1f", ilvl), 0.78, 0.80, 0.84, 0.85, 0.92, 0.98)
                                end
                            else
                                tooltip:AddLine(string.format("GearScore: %d (iLvl %.1f)", gs, ilvl))
                            end
                        end
                    end
                    tooltip:AddLine(" ")
                    tooltip:AddLine("|cffffb81cLeft-Click:|r Open Settings Dashboard", 0.9, 0.9, 0.9)
                    tooltip:AddLine("|cffffb81cRight-Click:|r Open Diagnostics", 0.9, 0.9, 0.9)
                    tooltip:AddLine("|cffffb81cShift-Left-Click:|r Toggle Tooltip Mover", 0.9, 0.9, 0.9)
                    tooltip:AddLine("|cffffb81cDrag:|r Move Minimap Button", 0.75, 0.75, 0.75)
                end,
            })
        end
        if (not icon:IsRegistered("TacoTip")) then
            icon:Register("TacoTip", obj, db)
        else
            icon:Refresh("TacoTip", db)
        end
        return true
    end

    function TT:SetMinimapIconShown(shown)
        local isShown = (shown ~= false)
        if (type(TacoTipConfig) == "table") then
            TacoTipConfig.show_minimap = isShown
        end
        local db = ensureMinimapTable()
        local _, icon = getLibs()
        if (not icon) then
            return false
        end
        if (not icon:IsRegistered("TacoTip")) then
            TT:InitMinimapIcon()
        end
        if (icon:IsRegistered("TacoTip")) then
            icon:Refresh("TacoTip", db)
            if (isShown) then
                icon:Show("TacoTip")
            else
                icon:Hide("TacoTip")
            end
        end
        return true
    end
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
        local point = tostring(pos[1] or "BOTTOMRIGHT")
        local relPoint = tostring(pos[2] or "BOTTOMRIGHT")
        local xOfs = tonumber(pos[3]) or 0
        local yOfs = tonumber(pos[4]) or 0
        TacoTipDragButton:SetPoint(point, UIParent, relPoint, xOfs, yOfs)
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
            if (down) then
                return
            end
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
                    if (not shownUnit or not safeUnitIsUnit(shownUnit, "player")) then
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
            -- Never replace a live unit-frame tooltip with the mover example.
            -- UnitFrame_UpdateTooltip makes the frame the GameTooltip owner, and
            -- the client re-drives it only while that owner is set. SetOwner
            -- below would freeze the unit tooltip on the cached example rows --
            -- the player/pet text the operator sees before Save.
            local owner = (GameTooltip and type(GameTooltip.GetOwner) == "function")
                and GameTooltip:GetOwner() or nil
            if (owner and owner.unit and GameTooltip:IsShown()) then
                return
            end
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
