local addOnName = ...
local addOnVersion = (GetAddOnMetadata and GetAddOnMetadata(addOnName, "Version")) or
    (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addOnName, "Version")) or "0.8.4"



-- TT and LOAD_STAGE are established BEFORE any assert or extern call, so a
-- load failure still leaves a stage for /tacotip diag and the mover message.
-- The library asserts below used to run first and abort the whole file with no
-- trace; they are soft aborts instead: stop this file, keep the stage.
local TT = _G[addOnName]

if (not TT) then
    TT = {}
    rawset(_G, addOnName, TT)
end

TT.LOAD_STAGE = "begin"
TT.LOAD_OK = false

if (not LibStub) then
    return
end
TT.LOAD_STAGE = "libs"
if (not LibStub:GetLibrary("LibForeverInspector", true)) then
    return
end
if (not LibStub:GetLibrary("LibDetours-1.0", true)) then
    return
end

local CI = LibStub("LibForeverInspector")
local Detours = LibStub("LibDetours-1.0")
local GearScore = _G.TT_GS
local L = _G.TACOTIP_LOCALE

-- The library's THREE-STATE contract for lib:DoInspect, published by the
-- library (CI.inspectStates) so this file compares against the library's own
-- names instead of keeping a copy of the contract:
--
--   REFUSED (false)  not inspected -- refused, unavailable, or out of reach
--   QUEUED ("queued") accepted, PENDING -- the request went out, or the unit
--                    is in the queue. The unit's data is NOT here yet.
--   READY (true)     data ready -- the cache holds fresh data for the unit
--
-- The contract used to be a plain boolean whose `true` covered BOTH "queued"
-- and "ready", so the two could not be told apart. A library that publishes
-- no names is an older build that answers with that plain boolean, where
-- `true` meant "accepted" -- the request went out, or the unit was queued --
-- and NOT "the data is here"; such an answer is pending here, exactly as it
-- was before the three-state contract existed.
local CI_INSPECT_STATES = (type(CI.inspectStates) == "table") and CI.inspectStates or nil

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
--
-- Hard ceiling: a 0 setting used to mean "no cap at all", so one long guild /
-- talent / Extras row could stretch the tooltip past the screen edge and take
-- the portrait with it. The user cap still wins when set; when it is 0 this
-- ceiling applies so the tooltip always has a maximum.
local TOOLTIP_HARD_MAX_WIDTH = 320
local function getEffectiveTooltipMaxWidth()
    local configured = TacoTipConfig and TacoTipConfig.tooltip_max_width or 0
    if (type(configured) == "number" and configured > 0) then
        return configured
    end
    return TOOLTIP_HARD_MAX_WIDTH
end
local function applyTooltipMaxWidth(tooltip)
    if (not tooltip or type(tooltip.NumLines) ~= "function") then
        return 0
    end

    local maxWidth = getEffectiveTooltipMaxWidth()
    local ok, numLines = pcall(tooltip.NumLines, tooltip)
    if (not ok or type(numLines) ~= "number") then
        return 0
    end

    -- Returns how many lines were (re)capped, so a deferred pass can tell
    -- whether there is anything left that could still be arriving late. The
    -- memo means a settled tooltip costs one scan and zero writes.
    local writes = 0

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
                -- L-1 (final hunter): the pcall's RESULT was thrown away, so a
                -- raising SetWidth left the line uncapped with no trace at all.
                -- The failure is now counted.
                --
                -- Why a counter and not callLabeled: callLabeled RE-RAISES with
                -- the call site named, which would abort the whole enhancement
                -- (the tooltip render runs inside safeCall, so the raise would
                -- be caught at the top and the tooltip would lose every line it
                -- had built). A cosmetic width cap that fails must not cost the
                -- player the GearScore line. The counter is the file's own idiom
                -- for exactly this -- see portraitSetFailed, the discarded
                -- portrait SetUnit at the same kind of call site.
                --
                -- The memo is still written on failure, so the hot path does
                -- not re-issue the failing call on every render: a SetWidth that
                -- raises will keep raising, and the count says how often.
                if (not pcall(leftLine.SetWidth, leftLine, leftCap)) then
                    TT.ev = TT.ev or {}
                    TT.ev.tooltipMaxWidthFailed = (TT.ev.tooltipMaxWidthFailed or 0) + 1
                end
                -- A narrower FontString only narrows the tooltip if the text
                -- wraps instead of overflowing: without word wrap the line's
                -- required width is still the full text and the tooltip still
                -- stretches past the cap. Enabled once per cap change, beside
                -- the width itself; short lines never reach the wrap point and
                -- render exactly as before.
                if (leftLine.SetWordWrap and type(leftLine.SetWordWrap) == "function") then
                    if (not pcall(leftLine.SetWordWrap, leftLine, true)) then
                        TT.ev = TT.ev or {}
                        TT.ev.tooltipMaxWidthFailed = (TT.ev.tooltipMaxWidthFailed or 0) + 1
                    end
                end
                if (leftLine.SetNonSpaceWrap and type(leftLine.SetNonSpaceWrap) == "function") then
                    if (not pcall(leftLine.SetNonSpaceWrap, leftLine, false)) then
                        TT.ev = TT.ev or {}
                        TT.ev.tooltipMaxWidthFailed = (TT.ev.tooltipMaxWidthFailed or 0) + 1
                    end
                end
                leftLine._tacoTipMaxWidth = leftCap
                writes = writes + 1
            end
        end
        local rightLine = getTooltipRightLine(tooltip, i)
        if (rightLine and type(rightLine.SetWidth) == "function") then
            if (rightLine._tacoTipMaxWidth ~= rightCap) then
                if (not pcall(rightLine.SetWidth, rightLine, rightCap)) then
                    TT.ev = TT.ev or {}
                    TT.ev.tooltipMaxWidthFailed = (TT.ev.tooltipMaxWidthFailed or 0) + 1
                end
                -- Same wrap reasoning as the left lines above: the right column
                -- must wrap, not overflow, or it stretches the tooltip past the
                -- cap on its own.
                if (rightLine.SetWordWrap and type(rightLine.SetWordWrap) == "function") then
                    if (not pcall(rightLine.SetWordWrap, rightLine, true)) then
                        TT.ev = TT.ev or {}
                        TT.ev.tooltipMaxWidthFailed = (TT.ev.tooltipMaxWidthFailed or 0) + 1
                    end
                end
                if (rightLine.SetNonSpaceWrap and type(rightLine.SetNonSpaceWrap) == "function") then
                    if (not pcall(rightLine.SetNonSpaceWrap, rightLine, false)) then
                        TT.ev = TT.ev or {}
                        TT.ev.tooltipMaxWidthFailed = (TT.ev.tooltipMaxWidthFailed or 0) + 1
                    end
                end
                rightLine._tacoTipMaxWidth = rightCap
                writes = writes + 1
            end
        end
    end
    return writes
end

-- Pawn version thresholds. Single home for this file's two probes (the
-- file-scope snapshot below and the live re-probe beside it).
--
-- Batch 7: the comparison used to be a RAW `pawnClassicVer >= 2.0538`. Pawn's
-- version globals are not guaranteed to be numbers -- a string-typed value
-- raises "attempt to compare string with number", and because the snapshot
-- probe runs at FILE SCOPE that raise aborts the whole add-on load, not just
-- the probe. pawn.lua already routes its own probe through a `tonumber`-
-- guarded helper (`pawn.lua:27-30`, `pawnVersionAtLeast`) with exactly these
-- two thresholds; the semantics are copied verbatim: a non-numeric version is
-- treated as ABSENT, so the probe falls through to the API-present fallback
-- instead of raising.
--
-- Why a local helper rather than the pawn module's one: `pawnVersionAtLeast`
-- is file-local in pawn.lua and is NOT exposed on `TT_PAWN` (only
-- `WasAvailableAtLoad` / `IsAvailable` are), and pawn.lua is outside this
-- batch's scope. main.lua also loads last (TacoTip.toc: gearscore -> pawn ->
-- textures -> options -> main) but pawn.lua can fail to load on its own
-- (`assert(LibStub)`, `pawn.lua:47-49`), so depending on TT_PAWN here would
-- be less safe, not more. A local helper keeps this file self-contained.
local PAWN_CLASSIC_MIN_VERSION = 2.0538
local PAWN_RETAIL_MIN_VERSION = 2.0
local function pawnVersionAtLeast(raw, threshold)
    local v = tonumber(raw)
    return v ~= nil and v >= threshold
end

-- Pawn detection: check PawnClassicLastUpdatedVersion, PawnLastUpdatedVersion, or public API functions.
local pawnClassicVer = rawget(_G, "PawnClassicLastUpdatedVersion")
local pawnRetailVer = rawget(_G, "PawnLastUpdatedVersion")
local pawnApiPresent = type(_G.PawnGetItemData) == "function" and type(_G.PawnGetSingleValueFromItem) == "function" and
    type(_G.PawnGetScaleColor) == "function"
local isPawnLoaded = pawnVersionAtLeast(pawnClassicVer, PAWN_CLASSIC_MIN_VERSION)
    or pawnVersionAtLeast(pawnRetailVer, PAWN_RETAIL_MIN_VERSION)
    or pawnApiPresent

-- Live re-probe for diagnostics ONLY (hunter C3). The render gate at
-- `isPawnLoaded and TT_PAWN ...` above stays on the file-scope snapshot, so a
-- Pawn that appears after load is reported as "until reload" rather than
-- silently changing render behaviour mid-session.
local function isPawnAvailableNow()
    local classicVer = rawget(_G, "PawnClassicLastUpdatedVersion")
    local retailVer = rawget(_G, "PawnLastUpdatedVersion")
    local apiPresent = type(_G.PawnGetItemData) == "function" and
        type(_G.PawnGetSingleValueFromItem) == "function" and
        type(_G.PawnGetScaleColor) == "function"
    return pawnVersionAtLeast(classicVer, PAWN_CLASSIC_MIN_VERSION)
        or pawnVersionAtLeast(retailVer, PAWN_RETAIL_MIN_VERSION)
        or apiPresent
end

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
-- C2 clock probe (load-time): GetTime and C_Timer.After must BOTH be present
-- for any timestamp or pacing decision. When absent, time-gated paths below
-- fail OPEN (coalesce skipped) instead of wedging on a memoised 0, and
-- reportSilentFailures names the fact. Never memoise 0 as a timestamp.
local clockAvailable = (type(GetTime) == "function")
    and (type(_G.C_Timer) == "table" and type(_G.C_Timer.After) == "function")
TT.ClockAvailable = clockAvailable
local GetBestMapForUnit = _G.C_Map and _G.C_Map.GetBestMapForUnit
-- C_Item namespace and Blizzard ObjectAPI
local Item = _G.Item
-- Namespaced on purpose: there is no bare global RequestLoadItemDataByID on any
-- of the five supported clients, only C_Item.RequestLoadItemDataByID.
--
-- Batch 7: the raw C_Item function is kept as the FALLBACK only. The request
-- itself now goes through the shared 2s-per-item throttle in gearscore.lua
-- (TT_GS.RequestLoadItemDataByID, gearscore.lua:102-144), which this file
-- bypassed: it called C_Item.RequestLoadItemDataByID directly, so every
-- cold-path hover re-requested the same uncached item. TT_GS is resolved at
-- CALL time (not captured at file scope) so the shared home is honoured
-- whenever it is present; the raw call runs only when TT_GS is absent, which
-- means gearscore.lua failed to load -- not a valid state.
local rawRequestLoadItemDataByID = _G.C_Item and _G.C_Item.RequestLoadItemDataByID
local function RequestLoadItemDataByID(itemID)
    local gs = rawget(_G, "TT_GS")
    local shared = gs and gs.RequestLoadItemDataByID
    if (type(shared) == "function") then
        return shared(itemID)
    end
    if (rawRequestLoadItemDataByID) then
        return rawRequestLoadItemDataByID(itemID)
    end
end
-- Item-ID resolver for the cold-path item-data request. Namespaced form
-- preferred, for the same reason the request above is.
--
-- The bare global GetItemInfoInstant exists ONLY on the three Classic-family
-- branches, where Blizzard_DeprecatedItemScript aliases it
-- (Interface/AddOns/Blizzard_DeprecatedItemScript/Deprecated_ItemScript.lua:10
-- -- "GetItemInfoInstant = C_Item.GetItemInfoInstant;"). That file is ABSENT on
-- origin/forever and origin/live, so on Retail and WoW Forever the bare global
-- does not exist at all: the old read produced a nil itemID and the cold-path
-- request NEVER fired there. Blizzard itself never calls the bare global on any
-- branch -- all call sites are namespaced (0 bare vs 11-21 namespaced per
-- branch), e.g. Blizzard_AuctionHouseSharedTemplates.lua:366
-- ("local itemID = C_Item.GetItemInfoInstant(itemLink);") and ItemMixin:GetItemID
-- (Blizzard_ObjectAPI/Classic/Item.lua:98-100). The FIRST return is the item
-- ID. The bare global is kept as a fallback for a client that has no C_Item
-- namespace at all.
local CItemGetItemInfoInstant = _G.C_Item and _G.C_Item.GetItemInfoInstant
local function getItemInfoInstantID(itemLink)
    local fn = CItemGetItemInfoInstant or _G.GetItemInfoInstant
    if (type(fn) ~= "function") then
        return nil
    end
    local ok, id = pcall(fn, itemLink)
    if (ok and type(id) == "number") then
        return id
    end
    return nil
end
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
---@field inspectState string|nil       -- last inspect answer for this tooltip's unit:
---                                       "ready" (data here), "queued" (accepted,
---                                       PENDING), "refused" (not inspected), or nil
---                                       (nothing known yet). The library's
---                                       three-state answer, kept rather than
---                                       discarded; it describes the unit
---                                       currently rendered and is cleared when
---                                       a different unit is rendered.

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

-- Player class is resolved per call for the same reason (hunter M9): a
-- file-scope latch reads nil when UnitClass is not yet populated at load and
-- then disables the HunterScore gate for the whole session.
local function getPlayerClass()
    local _, class = UnitClass("player")
    return class
end

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
    TT.ev = TT.ev or {}
    if (not reportedErrors[text]) then
        reportedErrors[text] = true
        -- Per-message first-seen count for the bounded top-5 ring below.
        -- Bounded: at most 25 distinct messages tracked; beyond that the total
        -- still reports via the handler but no new per-message key is added.
        TT.ev.pipelineErrorSeen = TT.ev.pipelineErrorSeen or {}
        local seenCount = 0
        for _ in pairs(TT.ev.pipelineErrorSeen) do seenCount = seenCount + 1 end
        if (TT.ev.pipelineErrorSeen[text] or seenCount < 25) then
            TT.ev.pipelineErrorSeen[text] = 1
        end
        if (defaultErrorHandler) then
            defaultErrorHandler(text)
        end
    else
        -- Cold path only: a repeat of an already-reported message. Counts the
        -- dedup blindness (hunter H3) without allocating on the hot path --
        -- numbers and at most five strings per session.
        TT.ev.pipelineErrorsSuppressed = (TT.ev.pipelineErrorsSuppressed or 0) + 1
        TT.ev.pipelineErrorSeen = TT.ev.pipelineErrorSeen or {}
        TT.ev.pipelineErrorSeen[text] = (TT.ev.pipelineErrorSeen[text] or 1) + 1
        TT.ev.pipelineSuppressedRing = TT.ev.pipelineSuppressedRing or {}
        if (#TT.ev.pipelineSuppressedRing < 5) then
            TT.ev.pipelineSuppressedRing[#TT.ev.pipelineSuppressedRing + 1] = text
        end
    end
end

local function safeCall(fn, ...)
    return xpcall(fn, handlePipelineError, ...)
end

--- Runs a function so that it cannot taint the frame whose script chain it
--- executes in.
---
--- WHY THIS EXISTS. `securecall` is the engine's own containment primitive and
--- Blizzard uses it for exactly this shape:
---   - `Interface/AddOns/Blizzard_BuffFrame/BuffFrame.lua:991`
---     `securecall(self.UpdateDuration, self, self.timeLeft); -- Taint issue
---      with SecondsToTimeAbbrev`
---     -- an addon-overridable function called from a Blizzard frame's own
---     script chain, contained so the frame is not tainted.
---   - `Interface/AddOns/Blizzard_CommunitiesSecure/CommunitiesAddDialogOutbound.lua:9`
---     `securecall("GameTooltip_SetBasicTooltip", GameTooltip, text, x, y, wrap);`
---   - `Interface/AddOns/Blizzard_CatalogShop/Blizzard_CatalogShop_Outbound.lua:17`
---     `securecall("GameTooltip_Hide");`
---   - `Interface/AddOns/Blizzard_Menu/Menu.lua:1129`
---     "the factoryArgs table can be passed to securecallfunction without
---      tainting execution."
---
--- `securecall` is an engine global on every supported client -- Blizzard
--- captures it as a local the same way it captures `forceinsecure`
--- (`Interface/AddOns/Blizzard_FrameXML/SharedPetBattleTemplates.lua:5`
--- `local securecall = securecall;`).
---
--- WHAT IT IS FOR HERE. Every callback this add-on installs into a BLIZZARD
--- frame's script chain runs as addon code inside that chain, and the client
--- taints the frame when that happens. On the Classic family the unit tooltip
--- has no secure dispatch at all -- the modern pair routes the unit callback
--- through the client's own attribute delegate
--- (`Interface/AddOns/Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua:181-201`,
--- `InsecureCallback` -> `forceinsecure()`), so the raw `HookScript` handler
--- runs inside the UNIT FRAME's script chain instead and taints that frame.
--- The taint reaches the game menu, and the Logout/Quit button -- whose
--- callback is the engine function `Logout`/`Quit`, so the reporter can only
--- name it `'UNKNOWN()'` -- is refused with `ADDON_ACTION_FORBIDDEN`.
---
--- The hook itself is the problem, not what it does: a `hooksecurefunc`
--- post-hook does not replace the hooked function, but its BODY still runs as
--- addon code inside the caller's script chain. That is why replacing the
--- `GameTooltip.FadeOut` detour with a secure post-hook did NOT close the
--- exit-game block (0.8.4): the body still ran inside
--- `Interface/AddOns/Blizzard_UnitFrame/Classic/UnitFrame.lua:447`
--- (`GameTooltip:FadeOut();` inside `UnitFrame_OnLeave`).
---
--- `securecall` swallows an error raised by the callee and returns nil for
--- it, so every call site below keeps its own error handling: the tooltip
--- pipeline reports through `safeCall`, the pane hooks through their own
--- `pcall`, and the anchor post-hook has an explicit `pcall` with a counter.
local secureCallFn = nil
if (type(securecall) == "function") then
    -- Probe it ONCE, at load. `securecall` is an engine global on every
    -- supported client (Blizzard captures it as a local the same way it
    -- captures `forceinsecure`:
    -- Blizzard_FrameXML/SharedPetBattleTemplates.lua:5
    -- `local securecall = securecall;`), and Blizzard calls it from
    -- addon-facing code paths. The probe proves the engine actually RUNS a
    -- function through it FROM THIS ADD-ON'S CONTEXT: if a build ever refused
    -- addon code to call it, every tooltip event would raise, and one probe
    -- at load turns that into a documented fallback instead of a broken
    -- tooltip on every client.
    local probeRan = false
    local probeOk = pcall(securecall, function() probeRan = true end)
    if (probeOk and probeRan) then
        secureCallFn = securecall
    end
end

local function runUntainted(fn, ...)
    if (secureCallFn) then
        return secureCallFn(fn, ...)
    end
    -- No securecall on this client: run the callback directly. Every call
    -- site still has its own error containment, so the fallback degrades to
    -- "the taint guard is missing", never to "the add-on raises".
    return fn(...)
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
    -- THE CROSS-ADD-ON MAPPING, because the ONE setting has TWO spellings and
    -- a reader looking for either has to find the other:
    --
    --   main add-on (TacoTip)   TacoTipConfig["shaman_blue"]           snake_case
    --   Extras add-on           TacoTipExtrasDB.settings["shamanBlue"]  camelCase
    --
    -- The Extras reads the same rule and the same value (TacoTip_Extras/
    -- Core.lua, IsShamanBlueEnabled). Only an explicit boolean `false` in
    -- EITHER turns it off, so a player who turns Shaman Blue off in one
    -- add-on does not get pink in one and blue in the other.
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
local TOOLTIP_NAME_FONT_SIZE_DELTA = 1

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
    -- The last-resort edge size is the SHIPPED default (options.lua
    -- DEFAULTS.tooltip_border_edge_size = 20). It was a literal 16 here, which
    -- disagreed with the default a fresh profile resolves to. The config value
    -- still wins above it, so an existing profile's border does not change.
    local edgeSize = hasBorder and ((TT.GetResolvedTooltipBorderEdgeSize
            and TT:GetResolvedTooltipBorderEdgeSize())
        or TacoTipConfig.tooltip_border_edge_size or 20) or 0
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
        -- M-1 (final hunter): this arm used to probe the tooltip with an
        -- UNGUARDED `tooltip:IsUnit(unit)` and then THROW THE ANSWER AWAY --
        -- both branches returned `unit` -- so the call could only ever cost
        -- something and never buy anything.
        --
        -- What it cost: on a client whose IsUnit is a shim over a not-yet-loaded
        -- namespace it RAISES, and the raise escaped every caller. Five of the
        -- six call sites are inside the tooltip pipeline, but
        -- TacoTip_GSCallback is a GLOBAL callback reached from the engine's
        -- item-load handler and is NOT inside a safeCall, so there the raise
        -- killed the whole callback. The file's own invariant ("tooltip:GetUnit()
        -- (and equally IsUnit) must never be called unguarded", below) says
        -- exactly this.
        --
        -- Why the call is GONE rather than guarded: the answer was discarded,
        -- so no caller can be relying on it. The rejection it looked like it
        -- wanted -- "refuse a unit the tooltip is not about" -- is deliberately
        -- NOT implemented here: every caller passes a unit the tooltip is
        -- already about (onTooltipSetUnit passes the token it just read from
        -- tooltip:GetUnit(); ApplyTooltipAppearance passes an already-resolved
        -- unit), so refusing a "mismatching" unit would CHANGE THE RESULT for
        -- a valid state, which this fix must not do. The disagreement chain the
        -- GetUnit arm below describes (GetUnit token -> IsUnit disagreement ->
        -- GetOwner -> "mouseover") is handled there, with a pcall-guarded
        -- IsUnit -- the same idiom as tooltipIsMouseover.
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
        -- The third return is read for symmetry with the TooltipUtil arm above,
        -- but it is ALWAYS nil on a real client: GameTooltip:GetUnit publishes
        -- NAME and UNIT and nothing else. Verified in the FrameXML mirror on
        -- all five branches -- every Blizzard call site destructures exactly
        -- two (`local name, unit = self:GetUnit()`,
        -- Blizzard_PTRFeedback_Tooltips.lua:87 on origin/classic_era,
        -- origin/classic_anniversary and origin/classic_titan, :105 on
        -- origin/forever and origin/live), and no call site anywhere
        -- destructures three. The GUID comes from the SIBLING resolver,
        -- TooltipUtil.GetDisplayedUnit (`return name, unit, guid;`,
        -- Blizzard_SharedXMLGame/Tooltip/TooltipUtil.lua:40), and that
        -- namespace does not exist on the Classic family at all.
        --
        -- So the `elseif (ok and guid)` arm below is UNREACHABLE on every
        -- supported client: it can only run when GetUnit published no token,
        -- and in that case there is no guid to read either. The real Classic
        -- chain is GetUnit token -> IsUnit disagreement -> GetOwner ->
        -- "mouseover", and that is the chain the offline harness drives.
        -- The arm is left in place because it is harmless and because a
        -- future client that DID publish a third value would want it -- but
        -- it is not something any current client can reach.
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
    -- Cold path only: every success above returned without touching TT.ev.
    -- Per-cause counters (M2) so /tacotip diag can name WHY the unit was lost
    -- instead of collapsing all failures to one nil.
    TT.ev = TT.ev or {}
    local cause = "unresolved"
    if (not tooltip) then
        cause = "no-tooltip"
        TT.ev.resolveFailNoTooltip = (TT.ev.resolveFailNoTooltip or 0) + 1
    elseif ((TooltipUtil == nil or TooltipUtil.GetDisplayedUnit == nil) and
        (tooltip.GetUnit == nil) and (tooltip.GetOwner == nil)) then
        cause = "no-source"
        TT.ev.resolveFailNoSource = (TT.ev.resolveFailNoSource or 0) + 1
    else
        TT.ev.resolveFailUnresolved = (TT.ev.resolveFailUnresolved or 0) + 1
    end
    TT.ev.resolveTooltipUnitFailed = (TT.ev.resolveTooltipUnitFailed or 0) + 1
    TT.ev.resolveTooltipUnitLastCause = cause
    return nil
end

-- Guarded counterpart of the mouseover-tooltip check used by the instant-fade
-- path. `tooltip:GetUnit()` (and equally `IsUnit`) must never be called
-- unguarded (AGENTS.md invariant): on clients where it is a shim over a
-- not-yet-loaded namespace it raises and silently kills the branch. Every read
-- here goes through pcall.
local function tooltipIsMouseover(tooltip)
    if (not tooltip) then
        return false
    end
    if (type(tooltip.IsUnit) == "function") then
        local ok, isU = pcall(tooltip.IsUnit, tooltip, "mouseover")
        if (ok and isU == true) then
            return true
        end
        if (ok and isU == false) then
            return false
        end
        -- Cold path only: the engine probe raised (shim over a not-yet-loaded
        -- namespace). Count the guarded failure (M1); the false below is the
        -- documented safe default, not a silent success.
        if (not ok) then
            TT.ev = TT.ev or {}
            TT.ev.tooltipIsMouseoverGuarded = (TT.ev.tooltipIsMouseoverGuarded or 0) + 1
        end
    end
    if (type(tooltip.GetUnit) == "function") then
        local ok, _, tooltipUnit = pcall(tooltip.GetUnit, tooltip)
        if (ok and tooltipUnit == "mouseover") then
            return true
        end
        if (not ok) then
            TT.ev = TT.ev or {}
            TT.ev.tooltipIsMouseoverGuarded = (TT.ev.tooltipIsMouseoverGuarded or 0) + 1
        end
    end
    return false
end


-- THE SAVED TOOLTIP POSITION, applied when the unit is actually known.
--
-- The SetDefaultAnchor post-hook cannot own this on every client: the client
-- calls GameTooltip_SetDefaultAnchor(GameTooltip, self) IMMEDIATELY BEFORE
-- GameTooltip:SetUnit(...) (origin/classic_era:
-- Blizzard_UnitFrame/Classic/UnitFrame.lua; origin/live:
-- Mainline/UnitFrame.lua:390-391), so at hook time the tooltip still describes
-- the PREVIOUS unit and IsUnit answers about that one. A world/mouseover unit
-- therefore reads as "menu", the hook returns untouched, and the tooltip stays
-- where the client put it -- the bottom-right corner. That is the "it resets my
-- position" report.
--
-- The unit render runs after SetUnit, so the answer here is meaningful. The
-- post-hook keeps its own paths (mouse anchor, two-bar layout, frames); this is
-- the one that makes a saved position stick.
local function applyCustomTooltipAnchor(tooltip, unit)
    if (not tooltip or type(unit) ~= "string" or unit == "") then
        return false
    end
    if (not TacoTipConfig or TacoTipConfig.anchor_mouse) then
        return false
    end
    local saved = TacoTipConfig.custom_pos
    -- Same shape the load-time sanitizer accepts; anything else is not a
    -- position and must not reach SetPoint.
    if (type(saved) ~= "table" or type(saved[1]) ~= "string") then
        return false
    end
    if (not TacoTipDragButton and type(TacoTip_CustomPosEnable) == "function") then
        TacoTip_CustomPosEnable(false)
    end
    if (not TacoTipDragButton) then
        return false
    end
    local anchorPoint = TacoTipConfig.custom_anchor or "TOPLEFT"
    tooltip:ClearAllPoints()
    tooltip:SetPoint(anchorPoint, TacoTipDragButton, anchorPoint)
    return true
end

-- THE RIGHT EDGE THE PORTRAIT SIDE DECISION MUST BELIEVE.
--
-- Reading tooltip:GetRight() for that decision is wrong the moment this addon
-- owns the position: while the decision is made the tooltip is still where the
-- CLIENT put it (classic_era GameTooltip_SetDefaultAnchor, GameTooltip.lua:
-- 109-114, anchors BOTTOMRIGHT of UIParent), and the saved anchor is only
-- applied at the END of ApplyTooltipAppearance. So the side was chosen from the
-- DEFAULT position -- almost always "right" -- and the save then moved the
-- tooltip to the edge, leaving the portrait hanging outside the screen. That is
-- the "it used to flip to the left when it went off screen, now it just pulls it
-- off screen" report.
--
-- The anchor target is known, so the edge it will produce is known too: the
-- tooltip is pinned at custom_anchor on that same point of the handle.
--
-- Second return: whether the edge came from the anchor target. Only that edge may
-- be a cache key. The cursor follower moves the tooltip every frame, so keying on
-- its GetRight() would re-anchor the portrait on every render -- exactly the
-- per-render anchor that 0.7.9 removed.
local function getPortraitSideRightEdge(tooltip)
    local effectiveMax = getEffectiveTooltipMaxWidth()
    local custom = TacoTipConfig and TacoTipConfig.custom_pos
    if (type(custom) == "table" and not TacoTipConfig.anchor_mouse and TacoTipDragButton
            and type(TacoTipDragButton.GetLeft) == "function"
            and type(TacoTipDragButton.GetWidth) == "function") then
        local handleLeft = TacoTipDragButton:GetLeft()
        if (handleLeft) then
            local handleWidth = TacoTipDragButton:GetWidth() or 0
            local tipWidth = (type(tooltip.GetWidth) == "function" and tooltip:GetWidth()) or 0
            if (tipWidth > effectiveMax) then
                tipWidth = effectiveMax
            end
            local anchorPoint = TacoTipConfig.custom_anchor
            if (type(anchorPoint) ~= "string") then
                anchorPoint = "TOPLEFT"
            end
            if (string.find(anchorPoint, "RIGHT", 1, true)) then
                local rightEdge = handleLeft + handleWidth
                return rightEdge, true, rightEdge - tipWidth
            end
            if (string.find(anchorPoint, "LEFT", 1, true)) then
                return handleLeft + tipWidth, true, handleLeft
            end
            -- CENTER, and any TOP/BOTTOM point: the two centres coincide.
            local centerRight = handleLeft + handleWidth / 2 + tipWidth / 2
            return centerRight, true, centerRight - tipWidth
        end
    end
    local unmanagedRight = ((type(tooltip.GetRight) == "function" and tooltip:GetRight()) or 0)
    local unmanagedW = (type(tooltip.GetWidth) == "function" and tooltip:GetWidth()) or 0
    if (unmanagedW > effectiveMax) then
        unmanagedW = effectiveMax
    end
    local unmanagedLeft = (unmanagedRight > 0 and unmanagedW > 0) and (unmanagedRight - unmanagedW) or nil
    return unmanagedRight, false, unmanagedLeft
end

-- Decide and apply the portrait's side.
--
-- Called from the unit render AND from the tooltip's OnShow. The render can run
-- before the client has laid the tooltip out (on Retail and WoW Forever the whole
-- unit handler runs from the TooltipDataProcessor post-call, and TooltipDataHandler
-- fires that BEFORE its own self:Show(): ProcessLines(), postcalls, then Show()),
-- and it can run before add-ons that append rows have appended them -- so a side
-- chosen only there is chosen from a narrower tooltip than the one that ends up on
-- screen. OnShow is the last moment at which every line is in and the frame has a
-- rect.
--
-- Anchor once per side, not once per render: the side is cached on the tooltip
-- and only recomputed when something that can genuinely change it happens -- a
-- scale change, the invert option, the first shown frame, or a change in the
-- right edge the decision is made from.
local function applyTooltipPortraitSide(tooltip, portrait)
    if (not tooltip or not portrait) then
        return
    end
    local state = getTooltipState(tooltip)
    local portraitScale = TacoTipConfig.tooltip_portrait_scale or 1
    -- 66 x 88 (was 72 x 96). Still exact 3:4, still exact integers at every
    -- slider stop: 33x44, 66x88, 99x132, 132x176.
    local portraitW = math.floor(66 * portraitScale)
    local portraitH = math.floor(88 * portraitScale)
    local cachedSide = state.portraitSide
    local shown = (not tooltip.IsShown) or tooltip:IsShown()
    local invertSide = TacoTipConfig.tooltip_portrait_invert_side and true or false
    -- Invert is in the cache key for the same reason scale is: without it,
    -- ticking the option does nothing until the next scale change.
    --
    -- The right edge is in the key too. It is what the decision reads, so a change
    -- in it -- a wider tooltip from an extra row, a longer name, a different
    -- anchor point -- is exactly a reason to decide again. A re-render that
    -- changes nothing keeps the key and does not touch the portrait.
    local tooltipRight, edgeIsManaged, tooltipLeft = getPortraitSideRightEdge(tooltip)
    local edgeKey = edgeIsManaged and (math.floor(tooltipRight + 0.5) .. "x" .. math.floor((tooltipLeft or 0) + 0.5)) or nil
    if (not edgeIsManaged) then
        -- Leaving the saved position (mouse anchor) must not leave a stale edge
        -- behind: the next managed render then decides again instead of matching
        -- the value an earlier mode left there.
        state.portraitRightEdge = nil
    end
    if (cachedSide == nil or portrait._tacoTipScale ~= portraitScale
            or portrait._tacoTipInvert ~= invertSide
            or (edgeKey ~= nil and state.portraitRightEdge ~= edgeKey)
            or (shown and not state.portraitAnchored)) then
        local screenWidth = (UIParent and UIParent:GetRight())
            or (_G["GetScreenWidth"] and _G["GetScreenWidth"]()) or 1000
        -- Guard: the portrait itself must stay on screen, not just the tooltip.
        -- The old test (tooltip edge past the screen) misses the common case:
        -- the tooltip fits but tooltip + 8 + portrait does not. The extents below
        -- are where the portrait's outer edge would land on each side.
        local gap = 8
        local rightExtent = tooltipRight + gap + portraitW
        local leftExtent = (tooltipLeft ~= nil) and (tooltipLeft - gap - portraitW) or nil
        local rightFits = rightExtent <= screenWidth
        local leftFits = (leftExtent ~= nil) and (leftExtent >= 0) or false
        if (tooltipRight > 0 and tooltipRight >= screenWidth) then
            cachedSide = "left"
        elseif (not rightFits and leftFits) then
            cachedSide = "left"
        elseif (leftExtent ~= nil and not leftFits and rightFits) then
            cachedSide = "right"
        elseif (leftExtent ~= nil and not rightFits and not leftFits) then
            local spaceRight = screenWidth - tooltipRight
            cachedSide = (tooltipLeft > spaceRight) and "left" or "right"
        else
            cachedSide = "right"
        end
        -- Inverted before the side-to-anchor mapping below, so that mapping stays
        -- in one place. Off by default, so nobody who never touches the option
        -- sees any change.
        if invertSide then
            cachedSide = (cachedSide == "left") and "right" or "left"
        end
        ---@diagnostic disable-next-line: inject-field
        state.portraitSide = cachedSide
        ---@diagnostic disable-next-line: inject-field
        state.portraitAnchored = shown
        ---@diagnostic disable-next-line: inject-field
        state.portraitRightEdge = edgeKey
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
end

-- Post-layout guard: the ACTUAL portrait rect, measured after layout, wins over
-- every prediction.
--
-- Why this exists: the side above is decided during the render, when the width
-- is stale (the modern post-call runs before Show; the saved anchor is applied
-- at the end of the render; Extras rows land after our hook), and the side cache
-- (portraitSide/portraitRightEdge) treats "same predicted edge" as "nothing
-- changed". Then GearScore item loads and inspect results complete
-- ASYNCHRONOUSLY after Show -- TacoTip_GSCallback re-drives UpdateTooltip/SetUnit
-- for the same unit, the tooltip widens past what was measured, and nothing
-- re-checks: the first second looks right, then the portrait is pushed off the
-- screen. A fresh hover after an idle clears the side cache
-- (OnTooltipCleared/OnHide reset it), so the same sequence replays -- the
-- "didn't hover for a bit and it was back" half.
--
-- This closes all of those at once by measuring reality instead of predicting
-- it: 0.05s after the render/show, when every line is in and the client has laid
-- the frame out, the portrait's own outer edge is read against the screen. Off
-- the right edge it goes left; off the left edge it goes right; off both (a
-- tooltip wider than the screen) it takes the roomier side. Anything that
-- widens the tooltip -- our async lines, Extras rows, a third-party addon
-- appending after Show -- is corrected the same way, because the trigger is the
-- measured overflow, not the source. When nothing overflows it is a silent
-- no-op: no SetPoint, no counter, no churn -- the 0.7.9 per-render anchor stays
-- dead.
--
-- Throttled to one outstanding timer per tooltip: renders arrive in bursts
-- during item-load completion, and each would otherwise schedule its own check.
-- The timer carries the generation and unit guid; a recycle or a unit change
-- before it fires makes it a no-op, and clear/hide cancels it outright, so it
-- can never flip a later tooltip.
--
-- Forward-declared: the guard below schedules its own bounded follow-up, but
-- the scheduler is defined after it. A file-local call would resolve to a
-- global (nil) here -- the exact crash the harness caught.
local schedulePortraitGuard
local function guardTooltipPortraitOnScreen(tooltip, isFinal)
    if (not tooltip or not TacoTipConfig.tooltip_portrait) then
        return false
    end
    local portrait = tooltip.TacoTipPortrait3D or tooltip.TacoTipPortrait
    if (not portrait or not portrait.IsShown or not portrait:IsShown()) then
        return false
    end
    if (not tooltip.IsShown or not tooltip:IsShown()) then
        return false
    end
    -- Late lines escape the render-time and Show-time caps: any addon hooked
    -- after us (Questie-style NPC lines, id addons -- "NpcID"/"Alive"/"Target"
    -- in the operator's screenshot are not ours, verified by whole-tree grep)
    -- appends after applyTooltipMaxWidth already ran, and when the tooltip is
    -- already shown there is no second OnShow to catch them. This deferred pass
    -- runs after every same-frame hook regardless of registration order, so it
    -- caps whatever is actually there -- including third-party lines -- before
    -- the rect below is measured. Idempotent (memoized per line), so a tooltip
    -- with nothing new costs one scan and no writes.
    --
    -- Returns whether this pass changed anything (capped a late line, or flipped
    -- the side): the scheduler uses it to decide if one bounded follow-up is
    -- worth it for content that arrives even later (slow async appends). It
    -- returns rather than looping so there is no path that re-arms forever.
    local capped = applyTooltipMaxWidth(tooltip) or 0
    if (type(portrait.GetRight) ~= "function" or type(portrait.GetLeft) ~= "function") then
        return capped > 0
    end
    local okR, pRight = pcall(portrait.GetRight, portrait)
    local okL, pLeft = pcall(portrait.GetLeft, portrait)
    if (not okR or not okL or type(pRight) ~= "number" or type(pLeft) ~= "number") then
        return capped > 0
    end
    local screenWidth = (UIParent and UIParent:GetRight())
        or (_G["GetScreenWidth"] and _G["GetScreenWidth"]()) or 1000
    local offRight = pRight > screenWidth
    local offLeft = pLeft < 0
    -- The follow-up below is UNCONDITIONAL (not only when this pass did work):
    -- a slow async append can land after a clean first pass -- render cap too
    -- early, OnShow cap too early, first guard pass too early -- and with no
    -- follow-up nothing would ever re-check until the next hover. That is the
    -- "first hover fine, second hover stretched" shape: the second unit's
    -- third-party data simply arrives later than 0.05s. Two passes max per
    -- show, the second final, so there is still no chain.
    if (not offRight and not offLeft) then
        if (not isFinal) then
            schedulePortraitGuard(tooltip, 0.5, true)
        end
        return capped > 0
    end
    local state = getTooltipState(tooltip)
    local newSide
    if (offRight and not offLeft) then
        newSide = "left"
    elseif (offLeft and not offRight) then
        newSide = "right"
    else
        -- Wider than the screen: take the roomier side rather than churning.
        local tooltipRight = (type(tooltip.GetRight) == "function" and tooltip:GetRight()) or pRight
        local spaceRight = screenWidth - tooltipRight
        local tooltipLeft = (type(tooltip.GetLeft) == "function" and tooltip:GetLeft()) or pLeft
        newSide = (tooltipLeft > spaceRight) and "left" or "right"
    end
    if (newSide == state.portraitSide) then
        if (not isFinal) then
            schedulePortraitGuard(tooltip, 0.5, true)
        end
        return capped > 0
    end
    state.portraitSide = newSide
    state.portraitAnchored = true
    portrait:ClearAllPoints()
    if (newSide == "left") then
        portrait:SetPoint("TOPRIGHT", tooltip, "TOPLEFT", -8, 0)
    else
        portrait:SetPoint("TOPLEFT", tooltip, "TOPRIGHT", 8, 0)
    end
    TT.ev = TT.ev or {}
    TT.ev.portraitGuardFlip = (TT.ev.portraitGuardFlip or 0) + 1
    if (not isFinal) then
        schedulePortraitGuard(tooltip, 0.5, true)
    end
    return true
end

schedulePortraitGuard = function(tooltip, delaySec, isFinal)
    if (type(NewTimer) ~= "function") then
        return
    end
    if (not tooltip) then
        return
    end
    local state = getTooltipState(tooltip)
    if (state.portraitGuardTimer) then
        return
    end
    local gen = state.generation
    local guid = state.currentUnitGUID
    local delay = (type(delaySec) == "number" and delaySec > 0) and delaySec or 0.05
    local timer
    timer = NewTimer(delay, function()
        if (state.portraitGuardTimer == timer) then
            state.portraitGuardTimer = nil
        end
        safeCall(function()
            if (state.generation ~= gen) then
                return
            end
            if (not tooltip or not tooltip.IsShown or not tooltip:IsShown()) then
                return
            end
            if (state.currentUnitGUID ~= guid) then
                return
            end
            guardTooltipPortraitOnScreen(tooltip, isFinal)
        end)
    end)
    state.portraitGuardTimer = timer
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
    if (portrait) then
        if (TacoTipConfig.tooltip_portrait and unit) then
            applyTooltipPortraitSide(tooltip, portrait)
            -- Post-layout backstop for async widening (item loads, inspect):
            -- the deferred guard measures the real rect and flips only if the
            -- portrait is actually off screen. One outstanding timer per
            -- tooltip, cancelled on recycle, so bursts converge on one check.
            schedulePortraitGuard(tooltip)
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
                    --
                    -- L1: the pcall's result used to be discarded, so a raising
                    -- ClearModel left no trace at all. Counted, like every other
                    -- discarded cold-path pcall.
                    if (not pcall(portrait.ClearModel, portrait)) then
                        TT.ev.portraitClearModelFailed = (TT.ev.portraitClearModelFailed or 0) + 1
                    end
                    if (pcall(portrait.SetUnit, portrait, unit)) then
                        portrait.tacoTipModelKey = modelKey
                    else
                        -- SetUnit failed: leave the cache empty so the next render
                        -- retries rather than believing a model is loaded.
                        -- Cold path only (M4): count the discarded failure.
                        TT.ev.portraitSetFailed = (TT.ev.portraitSetFailed or 0) + 1
                        portrait.tacoTipModelKey = nil
                    end
                end
                -- THE ZOOM.
                --
                -- SetPortraitZoom is a REAL client API on the CharacterModelBase
                -- template (mirror: Blizzard_APIDocumentationGenerated/
                -- FrameAPICharacterModelBaseDocumentation.lua:206 on
                -- classic_era and :219 on live; Blizzard calls it itself in
                -- Blizzard_SharedXML/Classic/ModelFrames.lua:125 and
                -- Blizzard_FrameXML/QuestNPCModelFrameMixin.lua:8 with 0.6),
                -- and the operator has verified in game that the tooltip
                -- portrait honours it.
                --
                -- The VALUE comes from the ONE default (options.lua's DEFAULTS,
                -- published as TT.TooltipPortraitZoomDefault). It used to
                -- repeat a different literal here (0.7) while the shipped
                -- default was 0.75, so a config with no saved zoom rendered a
                -- DIFFERENT portrait from the number the options slider
                -- showed: the number the player saw was not the number they
                -- got. The zoom is applied exactly as it is set -- no cap, no
                -- clamp, no range change.
                local zoom = TacoTipConfig.tooltip_portrait_zoom
                if (type(zoom) ~= "number") then
                    zoom = TT.TooltipPortraitZoomDefault
                end
                -- H1/L1: the pcall's result used to be thrown away, so a
                -- raising SetPortraitZoom (or a client without the method) was
                -- invisible: no counter, no diag line, nothing. Counted in the
                -- same idiom as its sibling portraitSetFailed.
                if (type(zoom) == "number") then
                    if (not pcall(portrait.SetPortraitZoom, portrait, zoom)) then
                        TT.ev.portraitZoomFailed = (TT.ev.portraitZoomFailed or 0) + 1
                    end
                else
                    -- No published default: the zoom cannot be applied at all.
                    -- Said, not swallowed.
                    TT.ev.portraitZoomUnsupported = (TT.ev.portraitZoomUnsupported or 0) + 1
                end
            else
                -- 2D fallback only when 3D model creation failed (portrait is a Texture).
                -- Cold path only (M4): a raising SetPortraitTexture was a silent discard.
                if (not pcall(_G.SetPortraitTexture, portrait, unit)) then
                    TT.ev.portraitSetFailed = (TT.ev.portraitSetFailed or 0) + 1
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

    -- Last, so nothing above can re-anchor the tooltip afterwards. See
    -- applyCustomTooltipAnchor for why this cannot be the SetDefaultAnchor hook.
    applyCustomTooltipAnchor(tooltip, unit)
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

-- The character pane's overlay repaint budget.
--
-- The overlay lives INSIDE CharacterFrame (PaperDollFrame is its child on every
-- branch, and the Classic family nests the model frame inside that), so a
-- repaint while the pane is closed is invisible work: one full inventory walk
-- of 18 slots for a number nobody can see.
--
-- The 0.8.2 bug was a refresh that ran EIGHT inventory walks -- about 144
-- GetItemInfo calls -- for ONE pane open. The budget is how that is prevented
-- from coming back through the pending->ready path: the pane open spends one
-- refresh, and the pending->ready repaint may take ONE more. Past that the
-- panel is repainted by PLAYER_EQUIPMENT_CHANGED, which is the player's own
-- action and cannot storm.
--
-- Set to 1 by the character pane's OnShow hook; spent by the pending->ready
-- repaint below.
local characterPaneReadyBudget = 0

-- Repaint the character pane's overlay, but only while the pane is OPEN.
--
-- Returns true when a repaint actually ran. The pane is opened by the player
-- (CharacterFrame:Show()), so the open state is the player's own signal that
-- the number is wanted on screen.
local function refreshCharacterPaneIfOpen()
    local pane = _G.CharacterFrame
    if (not pane or not pane.IsShown or not pane:IsShown()) then
        return false
    end
    if (not TT.RefreshCharacterFrame) then
        return false
    end
    if (characterPaneReadyBudget <= 0) then
        return false
    end
    characterPaneReadyBudget = characterPaneReadyBudget - 1
    -- L-4 (final hunter): this call was UNGUARDED, and this function is reached
    -- from TacoTip_GSCallback -> itemcacheCB -> the engine's item-load
    -- callback, which is NOT inside a safeCall. A raise here therefore escaped
    -- into the engine's load handler: an error the player sees attributed to
    -- an item load, and a repaint that silently never happened.
    --
    -- The guard keeps the raise off the engine's callback and COUNTS it, so a
    -- broken repaint is visible in /tacotip diag instead of being invisible.
    -- The budget is spent either way: a failed repaint must not be retried on
    -- every item-load callback that follows.
    local ok = pcall(TT.RefreshCharacterFrame, TT)
    if (not ok) then
        TT.ev = TT.ev or {}
        TT.ev.characterPaneRefreshFailed = (TT.ev.characterPaneRefreshFailed or 0) + 1
        return false
    end
    return true
end

function TacoTip_GSCallback(guid)
    TT.ev.gsCallback = (TT.ev.gsCallback or 0) + 1
    -- The player's OWN score becoming ready must repaint the OPEN character
    -- pane (arbiter H1). The overlay is initialised with "0" and is only
    -- repainted when the pane opens, so a pane opened before the player's
    -- items were cached kept reading 0 for the rest of the session.
    --
    -- This callback is the pending->ready signal for the player's own set:
    -- the tooltip pipeline calls GearScore:GetScore(guid, true) for the unit it
    -- renders, and the completed item load calls back with that unit's guid.
    --
    -- It is placed BEFORE the re-entrancy guard on purpose. The guard drops a
    -- nested call for the guid already being serviced, and the pending value
    -- is only replayed when it names a DIFFERENT guid -- so a nested player
    -- callback would be dropped and the pane would keep its stale 0. The
    -- repaint cannot re-enter the tooltip pipeline (GetScore registers
    -- callbacks, it does not fire them), so it does not deepen the nesting
    -- the guard exists to stop.
    --
    -- Nothing here touches the tooltip pipeline: the unit check below still
    -- drops every guid that is not the tooltip's unit, unchanged.
    if (guid and guid == UnitGUID("player")) then
        refreshCharacterPaneIfOpen()
    end
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
    local ok, err
    if (GameTooltip.UpdateTooltip) then
        ok, err = pcall(GameTooltip.UpdateTooltip, GameTooltip)
    else
        ok, err = pcall(GameTooltip.SetUnit, GameTooltip, ttUnit)
    end
    if (not ok) then
        handlePipelineError(err)
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
    cancelTooltipTimer(tooltip, "portraitGuardTimer")
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
        --   hide    -- must happen whenever the unit is not being re-rendered
        --              and the frame is still shown, or a previous character's
        --              portrait bleeds onto an item or spell tooltip;
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
            -- Hide() and its counter are gated on the frame actually being
            -- shown. Hide() on an already-hidden frame is an engine no-op, and
            -- those no-ops dominated the counter against unitRender: live
            -- /tt diag read hides 1045 against renders 99, which was Hide()
            -- firing on frames no render had ever brought back (repeated
            -- OnTooltipCleared/OnHide on a frame already taken away).
            --
            -- The gate reads the frame; a widget without IsShown is treated as
            -- shown, so a trimmed environment or a mock cannot silently stop
            -- the hide from happening.
            local portraitShown = (not tooltip.TacoTipPortrait3D.IsShown)
                or tooltip.TacoTipPortrait3D:IsShown()
            if (portraitShown) then
                tooltip.TacoTipPortrait3D:Hide()
                -- Hide() gets a counter of its own, here, on every hide that
                -- actually happened.
                --
                -- TT.ev.portraitHide sits inside the retainModel guard below,
                -- so it counts teardowns and cannot see this call at all --
                -- and the two assertions named for the portrait blink read
                -- portraitHide, so moving this Hide() out of its guard left the
                -- whole suite green. A counter that cannot observe the call it
                -- is named after is worse than none: it reads as evidence and
                -- is not. This one observes the call, and now observes it only
                -- when the call does something.
                TT.ev.portraitModelHidden = (TT.ev.portraitModelHidden or 0) + 1
            end
            if (not retainModel) then
                -- The destroy half is gated on the loaded-unit cache, NOT on
                -- visibility: tacoTipModelKey names the mesh currently loaded,
                -- and retainModel callers (OnTooltipCleared/OnHide) leave a
                -- frame hidden with its mesh still resident. Keying this gate
                -- on visibility would leak that mesh; keying it on the cache is
                -- what lets a later genuine teardown release it.
                --
                -- ClearModel on a frame with no model loaded is an engine
                -- no-op too, and counting those inflated destroys against real
                -- teardowns: live /tt diag read destroys 310 against renders 99,
                -- most of them item-to-item recycles where the first item had
                -- already released the mesh.
                if (tooltip.TacoTipPortrait3D.tacoTipModelKey ~= nil) then
                    TT.ev.portraitHide = (TT.ev.portraitHide or 0) + 1
                    TT.ev.portraitDestroy = (TT.ev.portraitDestroy or 0) + 1
                    -- WHICH path let go of the model. portraitHide alone could
                    -- not distinguish them, and a wrong fix shipped on top of
                    -- that: the unresolved-unit path was patched and the blink
                    -- stayed, because a different call site was the one
                    -- actually firing.
                    if (reason) then
                        TT.ev.teardownBy = TT.ev.teardownBy or {}
                        TT.ev.teardownBy[reason] = (TT.ev.teardownBy[reason] or 0) + 1
                    end
                    if (tooltip.TacoTipPortrait3D.ClearModel) then
                        -- L1: the second discarded ClearModel pcall. Counted on
                        -- its own so the diag can tell the render path's failure
                        -- from the teardown path's.
                        if (not pcall(tooltip.TacoTipPortrait3D.ClearModel, tooltip.TacoTipPortrait3D)) then
                            TT.ev.portraitTeardownClearModelFailed =
                                (TT.ev.portraitTeardownClearModelFailed or 0) + 1
                        end
                    end
                end
                -- SetAlpha and the cache drop stay OUTSIDE the loaded-model
                -- gate: they reset frame state, they are not evidence a mesh
                -- existed, and neither is counted. The cache drop is the
                -- invariant the next render relies on -- an empty key makes
                -- ApplyTooltipAppearance reload rather than trust a mesh that
                -- was just let go -- so it runs on every teardown decision.
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
    if (previousGUID ~= guid) then
        -- The inspect state describes the unit this tooltip renders, so a
        -- DIFFERENT unit starts with no state: a state left over from the
        -- previous character would describe a unit that is no longer on screen.
        getTooltipState(tooltip).inspectState = nil
    end
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
            -- L-3 (final hunter): the pcall's RESULT was thrown away, so a
            -- raise in the inspect trigger was invisible: the library counts its
            -- own notifies and refusals, but a raise HERE -- in the caller's
            -- copy of the trigger -- was lost entirely. Cold path only: count
            -- the failure beside the other cold-path counters.
            --
            -- The result is NOT thrown away any more. lib:DoInspect answers
            -- with the three states documented at the top of this file (the
            -- library's own names are CI.inspectStates):
            --
            --   false    not inspected -- refused, unavailable, out of reach
            --   "queued" accepted, PENDING -- the request went out, or the unit
            --            is in the queue. The unit's data is NOT here yet.
            --   true     data ready -- the cache holds fresh data
            --
            -- The old boolean said `true` for BOTH "queued" and "ready", so the
            -- two could not be told apart. They can now, and they are treated
            -- apart: a queued unit is PENDING, never ready. What the player
            -- sees does not change -- a queued unit and a ready unit lead to
            -- the same outcome they always had (the library's own queue and
            -- the GearScore callback own the rest), and a refused unit was
            -- never inspected either way -- but the state is KNOWN here now
            -- instead of lost, and it is recorded on the tooltip.
            local inspectOk, inspectState = pcall(CI.DoInspect, CI, tooltipUnit)
            local outcome
            if (not inspectOk) then
                -- A raise in the trigger: counted (L-3), and nothing is known
                -- about the unit.
                TT.ev = TT.ev or {}
                TT.ev.inspectTriggerFailed = (TT.ev.inspectTriggerFailed or 0) + 1
                outcome = nil
            elseif (CI_INSPECT_STATES) then
                if (inspectState == CI_INSPECT_STATES.READY) then
                    outcome = "ready"
                elseif (inspectState == CI_INSPECT_STATES.QUEUED) then
                    outcome = "queued"
                else
                    outcome = "refused"
                end
            elseif (inspectState == true) then
                -- An older library that answers with the plain boolean, whose
                -- `true` meant "accepted" -- request out, or unit queued -- and
                -- NOT "the data is here". Pending, exactly as before.
                outcome = "queued"
            else
                outcome = "refused"
            end
            getTooltipState(tooltip).inspectState = outcome
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
                -- C_Map.GetBestMapForUnit is NOT modern-only: it is documented
                -- and used by Blizzard on every branch
                -- (origin/classic_era, origin/classic_anniversary,
                -- origin/classic_titan, origin/forever, origin/live all carry
                -- it in Interface/AddOns/Blizzard_APIDocumentationGenerated/
                -- MapDocumentation.lua, and
                -- Interface/AddOns/Blizzard_FrameXMLUtil/Classic/MapUtil.lua:57
                -- calls it on the Classic branches).
                --
                -- What IS true on every branch is its DOCUMENTED contract:
                -- "Only works for the player and party members." So the
                -- "the target is on another map" suppression below can only
                -- ever fire for a group or raid member -- for any other target
                -- the call returns nil and the suppression stays inert. A
                -- maintainer must not read the nil guard below as a
                -- Classic-family workaround: it is the documented behaviour of
                -- the API on all five clients.
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
            -- Guard with fallback (hunter M5): a failed unit-event registration
            -- used to be discarded by bare pcalls, freezing the bar with no
            -- trace. Fall back to the plain events so the bar still updates
            -- (the OnEvent handler filters by unit), and count the failure for
            -- diag. Fallback chosen over diag-only because diag cannot unfreeze
            -- the bar.
            local unitRegsOk = false
            if (TacoTipPowerBar.RegisterUnitEvent) then
                local ok1 = pcall(TacoTipPowerBar.RegisterUnitEvent, TacoTipPowerBar, "UNIT_POWER_UPDATE", tooltipUnit)
                local ok2 = pcall(TacoTipPowerBar.RegisterUnitEvent, TacoTipPowerBar, "UNIT_MAXPOWER", tooltipUnit)
                local ok3 = pcall(TacoTipPowerBar.RegisterUnitEvent, TacoTipPowerBar, "UNIT_DISPLAYPOWER", tooltipUnit)
                unitRegsOk = ok1 and ok2 and ok3
                if (not unitRegsOk) then
                    TT.ev = TT.ev or {}
                    TT.ev.powerBarRegFailed = (TT.ev.powerBarRegFailed or 0) + 1
                end
            end
            if (not unitRegsOk) then
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
            -- runUntainted: this handler is addon code inside a Blizzard
            -- frame's script chain. On the Classic family the unit tooltip
            -- has no secure dispatch, so this runs inside the UNIT FRAME's
            -- chain and taints it; the taint reaches the game menu and the
            -- Logout/Quit button is refused. See runUntainted.
            frame:HookScript(scriptName, function(...)
                return runUntainted(handler, ...)
            end)
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
        -- GetItemLinkByGUID is DOCUMENTED only on Forever and Retail -- the
        -- classic branches' generated API docs are an incomplete set, so
        -- "not in the docs" is not "not in the client" (Blizzard calls the
        -- API unguarded on Classic Era, at
        -- origin/classic_era:Interface/AddOns/Blizzard_SharedXMLGame/Tooltip/TooltipUtil.lua:14).
        -- The arm is still skipped wherever the API is absent, and the guard
        -- is the RUNTIME probe, not the documentation.
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
                if (TacoTipConfig.show_gs_items_hs or IsModifierKeyDown() or getPlayerClass() == "HUNTER" or
                        (InspectFrame and InspectFrame:IsShown() and InspectFrame.unit and select(2, UnitClass(InspectFrame.unit)) == "HUNTER")) then
                    local hs, _, hsR, hsG, hsB = GearScore:GetItemHunterScore(itemLink, itemInfo)
                    if (gs ~= hs) then
                        -- OPERATOR DECISION (arbiter H2): the HunterScore line
                        -- intentionally uses the GEARSCORE BAND COLOUR. It is
                        -- not a defect and must not be "fixed".
                        --
                        -- GetItemHunterScore returns the hunter-adjusted NUMBER
                        -- but the colour of the item's GearScore band
                        -- (gearscore.lua:406-420 -- Red/Green/Blue are the
                        -- values GetItemScoreFromInfo produced, and only the
                        -- score itself is rescaled for a hunter). The line
                        -- therefore reads as the hunter's counterpart to the
                        -- iLvl line: the same band, the hunter's own number.
                        --
                        -- Recorded here so the next audit does not re-raise it
                        -- as a colour-mismatch bug.
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
        --
        -- Cold path only (hunter H8): count the fire-and-forget, then schedule
        -- ONE bounded repaint when the platform has a timer. The repaint is
        -- generation-bounded (a clear/hide in between invalidates it) and
        -- single-shot (no ticker, no retry loop). 0.5s matches the inspect
        -- queue tick cadence -- long enough for the data to land, short enough
        -- to read as a refresh. Without a timer the path stays known-degraded:
        -- the request is sent and the next natural refresh paints it.
        TT.ev = TT.ev or {}
        TT.ev.itemRefreshFireAndForget = (TT.ev.itemRefreshFireAndForget or 0) + 1
        -- Batch 7: the item ID comes from the namespaced C_Item resolver
        -- (first return is the ID). The bare global is only a fallback for a
        -- client with no C_Item namespace -- see getItemInfoInstantID at the
        -- top of this file, which carries the mirror evidence.
        local itemID = getItemInfoInstantID(itemLink)
        if (itemID) then
            -- Batch 7: routed through the shared 2s-per-item throttle
            -- (TT_GS.RequestLoadItemDataByID) so this path cannot re-request
            -- the same uncached item on every hover. The raw C_Item call is
            -- the fallback for the gearscore-missing invalid state only.
            pcall(RequestLoadItemDataByID, itemID)
        end
        if (type(NewTimer) == "function") then
            local fireState = getTooltipState(tooltip)
            local fireGeneration = fireState.generation
            local fireLink = itemLink
            NewTimer(0.5, function()
                safeCall(function()
                    if (fireState.generation ~= fireGeneration
                            or fireState.currentItemLink ~= fireLink
                            or not tooltip:IsShown()) then
                        return
                    end
                    if (tooltip.UpdateTooltip) then
                        -- L1: a raising repaint used to be discarded silently.
                        if (not pcall(tooltip.UpdateTooltip, tooltip)) then
                            TT.ev.tooltipRepaintFailed = (TT.ev.tooltipRepaintFailed or 0) + 1
                        end
                    end
                end)
            end)
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
            -- L1: the second discarded repaint pcall (the item-load callback
            -- path). Counted apart from the timer path's.
            if (not pcall(tooltip.UpdateTooltip, tooltip)) then
                TT.ev.tooltipRepaintCallbackFailed =
                    (TT.ev.tooltipRepaintCallbackFailed or 0) + 1
            end
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
        -- L1: the third discarded cold-path pcall. A raising registration
        -- meant the repaint never happened, and nothing said so.
        if (not pcall(item.ContinueOnItemLoad, item, callback)) then
            TT.ev.itemLoadCallbackFailed = (TT.ev.itemLoadCallbackFailed or 0) + 1
        end
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

    -- The portrait's side, re-decided at the one moment the layout is final.
    --
    -- The render can run against a tooltip the client has not laid out yet (the
    -- modern post-call runs before Show) and before add-ons that append rows --
    -- TacoTip Extras among them -- have appended them, so the width it measured
    -- is the narrow one. The cap is re-applied first so those late rows wrap
    -- instead of stretching the tooltip, then the side is re-decided after every
    -- line is in and the frame has a rect. The side function only mutates the
    -- add-on's own portrait frame, and is a cache hit unless something it
    -- depends on changed.
    applyTooltipMaxWidth(tooltip)
    if (TacoTipConfig.tooltip_portrait) then
        local showPortrait = ensureTooltipPortrait(tooltip)
        if (showPortrait) then
            applyTooltipPortraitSide(tooltip, showPortrait)
            schedulePortraitGuard(tooltip)
        end
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
            -- The whole body is inside runUntainted: even the read-only early
            -- return is addon code running in the tooltip's script chain.
            --
            -- It is inside safeCall as well, so the containment path and the
            -- no-securecall fallback behave the SAME: a raise is caught and
            -- REPORTED in both, instead of being swallowed silently by the
            -- containment and propagating out of the client's own script
            -- chain in the fallback.
            return runUntainted(safeCall, function()
                if (isUnitFramePeriodicUpdate(tFrame)) then
                    return
                end
                cancelDelayedTooltip(tFrame)
                return clearTooltipVisuals(tFrame, nil, nil, "cleared", true)
            end)
        end)
    end
    if (tooltipFrame:HasScript("OnShow")) then
        tooltipFrame:HookScript("OnShow", function(tFrame, ...)
            return runUntainted(safeCall, onTooltipShow, tFrame, ...)
        end)
    end
    if (tooltipFrame:HasScript("OnHide")) then
        tooltipFrame:HookScript("OnHide", function(tFrame)
            return runUntainted(safeCall, function()
                if (isUnitFramePeriodicUpdate(tFrame)) then
                    return
                end
                cancelDelayedTooltip(tFrame)
                -- Same reasoning as OnTooltipCleared: a hide is not proof the
                -- character changed, and the model is already hidden.
                return clearTooltipVisuals(tFrame, nil, nil, "hide", true)
            end)
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
--
-- Recorded the same way as the unit and item hooks so /tacotip diag reports
-- spell coverage. nil is the expected value on Retail and WoW Forever, whose
-- template does not declare the script; spell clearing there runs through the
-- OnTooltipCleared hooks registered above.
TT.HookedTooltipScripts.Spell = TT.HookedTooltipScripts.Spell
    or hookTooltipScripts("OnTooltipSetSpell", function(tooltip)
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

-- GameMenu-quit taint guard for the SetDefaultAnchor post-hook.
-- This hook runs for EVERY tooltip (units, items, spells, menus, popups).
-- Mutating GameTooltip here while secure menu code is on the stack taints the
-- quit path (ADDON_ACTION_FORBIDDEN via tainted GameTooltip), so unmanaged
-- owners must pass through without a single SetOwner/SetPoint/ClearAllPoints
-- or EnableMouse call. Addon frames are never managed here; the mover's
-- ShowExample owns that path.
local function isAddonAnchorFrame(frame)
    return frame ~= nil and (frame == TacoTipDragButton or frame == TacoTipMouseAnchor)
end

-- Lightweight managed-owner probe. Deliberately NOT resolveTooltipUnit: that
-- helper records TT.ev failure counters, and this hook fires for every menu
-- and item hover where "unresolved" is the correct answer, not an event.
--
-- Hunter M-NEW2: the two silent unmanaged shapes are now told apart for diag.
-- Returns managed (boolean) plus a skip kind: "addon" (our own frames,
-- managed elsewhere -- uncounted), "menu" (no unit signal anywhere: menus,
-- popups, item/spell surfaces passing through by design) or "unresolved"
-- (something unit-like was present -- battle pets, mouseover-less or exotic
-- owners -- but UnitExists failed everywhere). The counts are neutral
-- passthrough tallies, not failure events: a menu hover is supposed to skip.
local function isManagedAnchorTarget(tooltip, parent)
    if (isAddonAnchorFrame(parent)) then
        return false, "addon"
    end
    if (TacoTipConfig and TacoTipConfig.anchor_mouse_spells) then
        -- Hunter H-NEW4: parent:GetParent() is a raw call inside a
        -- hooksecurefunc post-hook that runs for EVERY tooltip. A parent
        -- without GetParent (or whose GetParent raises) aborts the hook and
        -- the unit gate below never runs. Type-check + pcall, mirroring the
        -- unit probe idiom below; a failure reads as "no grandparent".
        local parentparent = nil
        if (parent and type(parent.GetParent) == "function") then
            local okPP, pp = pcall(parent.GetParent, parent)
            if (okPP) then
                parentparent = pp
            end
        end
        if (parent and (parent.action or parent.spellId or (parentparent and (parentparent.action or parentparent.spellId)))) then
            return true
        end
    end
    -- Hunter M-NEW2: sawUnitSignal tracks whether anything unit-like was
    -- present. A signal that never resolves (battle pet, exotic owner) reads
    -- "unresolved"; no signal at all (menu/popup/item surface) reads "menu".
    local sawUnitSignal = false
    if (type(UnitExists) == "function") then
        if (TooltipUtil and type(TooltipUtil.GetDisplayedUnit) == "function" and tooltip) then
            local ok, _, dispUnit = pcall(TooltipUtil.GetDisplayedUnit, tooltip)
            if (ok and dispUnit) then
                sawUnitSignal = true
                local okExists, exists = pcall(UnitExists, dispUnit)
                if (okExists and exists) then
                    return true
                end
            end
        end
        if (tooltip and type(tooltip.GetUnit) == "function") then
            local ok, _, tooltipUnit = pcall(tooltip.GetUnit, tooltip)
            if (ok and tooltipUnit) then
                sawUnitSignal = true
                local okExists, exists = pcall(UnitExists, tooltipUnit)
                if (okExists and exists) then
                    return true
                end
            end
        end
        if (tooltip and type(tooltip.GetOwner) == "function") then
            local ok, owner = pcall(tooltip.GetOwner, tooltip)
            if (ok and owner and owner.unit) then
                sawUnitSignal = true
                local okExists, exists = pcall(UnitExists, owner.unit)
                if (okExists and exists) then
                    return true
                end
            end
        end
        if (parent and parent.unit) then
            sawUnitSignal = true
            local okExists, exists = pcall(UnitExists, parent.unit)
            if (okExists and exists) then
                return true
            end
        end
    end
    -- The classic-era shape. On the classic family the unit tooltip is the
    -- OLD one: no GetUnit, no TooltipDataProcessor, no owner.unit -- but it
    -- does answer IsUnit, which is how Blizzard's own
    -- GameTooltip_OnTooltipSetUnit identifies it
    -- (origin/classic_era:Interface/AddOns/Blizzard_GameTooltip/Classic/GameTooltip.lua:498-503).
    -- Without this the gate reads a classic unit tooltip as "menu", the
    -- post-hook returns early, and the tooltip is never re-anchored to the
    -- saved custom position -- it stays where the client put it, which is
    -- the bottom-right corner.
    if (tooltip and type(tooltip.IsUnit) == "function") then
        local okMouseover, isMouseover = pcall(tooltip.IsUnit, tooltip, "mouseover")
        if (okMouseover and isMouseover) then
            return true
        end
        local okTarget, isTarget = pcall(tooltip.IsUnit, tooltip, "target")
        if (okTarget and isTarget) then
            return true
        end
        local okPlayer, isPlayer = pcall(tooltip.IsUnit, tooltip, "player")
        if (okPlayer and isPlayer) then
            return true
        end
        local okFocus, isFocus = pcall(tooltip.IsUnit, tooltip, "focus")
        if (okFocus and isFocus) then
            return true
        end
    end
    if (sawUnitSignal) then
        return false, "unresolved"
    end
    return false, "menu"
end

local function onGameTooltipSetDefaultAnchor(tooltip, parent)
    if (not tooltip) then
        return
    end
    if (isAddonAnchorFrame(parent) or isAddonAnchorFrame(tooltip)) then
        return
    end
    if (TacoTipConfig.anchor_mouse_spells) then
        -- Hunter H-NEW4: same guard as above. This is the raw call the audit
        -- flagged: a parent without GetParent raised out of the post-hook and
        -- the unit gate below never ran.
        local parentparent = nil
        if (parent and type(parent.GetParent) == "function") then
            local okPP, pp = pcall(parent.GetParent, parent)
            if (okPP) then
                parentparent = pp
            end
        end
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
    -- Unit gate: menus, popups and item/spell tooltips this addon does not
    -- manage pass through untouched, so this post-hook never taints secure
    -- menu code with a reposition. Spell/action owners already returned above;
    -- everything below here is unit-only by construction.
    -- Hunter M-NEW2: count the passthrough by kind (menu-by-design vs
    -- unit-like-but-unresolved). Neutral tallies, not failure events.
    local managedAnchor, anchorSkipKind = isManagedAnchorTarget(tooltip, parent)
    if (not managedAnchor) then
        TT.ev = TT.ev or {}
        if (anchorSkipKind == "menu") then
            TT.ev.anchorSkippedMenu = (TT.ev.anchorSkippedMenu or 0) + 1
        elseif (anchorSkipKind == "unresolved") then
            TT.ev.anchorSkippedUnresolved = (TT.ev.anchorSkippedUnresolved or 0) + 1
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
--
-- Hunter M-NEW3 (accepted, no change): LibDBIcon is out of this hook's blast
-- radius by construction. It owns a SEPARATE GameTooltip frame
-- (LibDBIconTooltip, Libs/LibDBIcon-1.0/LibDBIcon-1.0.lua:21) and mutates
-- only it (SetOwner ANCHOR_NONE + SetPoint, :80-83/:111-114), never the
-- shared GameTooltip. The instant-fade post-hook targets the GameTooltip
-- FadeOut identity only, and this post-hook passes non-unit owners through
-- without a single SetOwner/SetPoint call -- so a minimap-icon hover can
-- neither taint the quit path nor be repositioned by it.
if (type(_G.GameTooltip_SetDefaultAnchor) == "function") then
    hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip, parent)
        -- runUntainted: this post-hook BODY is addon code that runs inside
        -- the caller's script chain -- the unit frame's OnEnter ->
        -- GameTooltip:SetOwner -> GameTooltip_SetDefaultAnchor -> here. A
        -- hooksecurefunc does not replace the hooked function, but its body
        -- still runs as addon code in that chain, which taints the unit
        -- frame; the taint reaches the game menu, and the Logout/Quit
        -- button -- whose callback is the engine function Logout/Quit, so a
        -- reporter can only name it 'UNKNOWN()' -- is refused with
        -- ADDON_ACTION_FORBIDDEN. The 0.8.4 quit-menu fix removed the
        -- DETOUR here and left the body; this closes the body.
        --
        -- The explicit pcall keeps a raise visible: securecall swallows it
        -- and returns nil, so without this the failure would be silent.
        return runUntainted(function()
            local ok, err = pcall(onGameTooltipSetDefaultAnchor, tooltip, parent)
            if (not ok) then
                TT.ev = TT.ev or {}
                TT.ev.anchorHookFailed = (TT.ev.anchorHookFailed or 0) + 1
                TT.ev.lastAnchorHookError = tostring(err)
            end
        end)
    end)
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

--- Hook a script on a Blizzard frame without risking the file-scope load.
---
--- `Frame:HookScript` raises "bad argument #2 to 'HookScript'" for a script the
--- frame does not already declare — that is the failure that aborted this
--- add-on's whole Retail load in 0.7.8 (`main.lua`'s tooltip-hook comment
--- above), and every tooltip hook has been `HasScript`-guarded since.
---
--- The tooltip status bar is the one frame here whose script set cannot justify
--- a `HasScript` gate: it declares NO `OnHide` on ANY of the five clients. The
--- classic chain declares exactly `<OnValueChanged>`
--- (origin/classic_era:Interface/AddOns/Blizzard_SharedXML/Classic/GameTooltipTemplate.xml:138-148)
--- and the modern pair declares `<OnLoad>`, `<OnUpdate>` and `<OnValueChanged>`
--- (origin/live and origin/forever:Interface/AddOns/Blizzard_GameTooltip/Mainline/GameTooltip.xml:9-23).
--- A gate would therefore skip the hook on every client — a behaviour change,
--- not a safety measure.
---
--- So the primitive here is the pcall, not the predicate: the hook installs
--- exactly where the client accepts it (which is today's behaviour on the only
--- client observed in game, Classic Era), and a refusal becomes a counted skip
--- instead of an abort of the rest of `main.lua`.
local function hookSafely(frame, scriptName, handler)
    if (type(frame) ~= "table" or type(frame.HookScript) ~= "function") then
        return false
    end
    local ok = pcall(frame.HookScript, frame, scriptName, handler)
    if (not ok) then
        TT.ev = TT.ev or {}
        TT.ev.statusBarHookRefused = (TT.ev.statusBarHookRefused or 0) + 1
    end
    return ok
end

-- The status bar IS a live global on every client (the `$parent` naming rule).
-- Its teardown is belt-and-braces with the tooltip's own OnHide, which calls
-- `clearTooltipVisuals` — so a refused hook costs nothing, and the counter
-- makes the refusal visible in `/tacotip diag` rather than silent.
if (GameTooltipStatusBar) then
    hookSafely(GameTooltipStatusBar, "OnHide", function()
        -- runUntainted: addon code inside a Blizzard frame's script chain
        -- taints that frame, and the taint reaches the game menu. See
        -- runUntainted.
        return runUntainted(function()
            if (TacoTipPowerBar) then
                TacoTipPowerBar:Hide()
            end
            stopPowerBarTicker()
        end)
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

    -- The pane that actually fires OnShow.
    --
    -- PaperDollFrame carries NO `hidden` attribute on any of the five branches,
    -- so it is shown from the moment it is created -- its OnShow fired long
    -- before this addon loaded, and the hook this line replaced could never
    -- fire again. The overlay therefore never repainted when the player
    -- opened the character pane, and it could sit on the "0" it was
    -- initialised with.
    --
    -- Mirror evidence (all five branches -- origin/classic_era,
    -- origin/classic_anniversary, origin/classic_titan, origin/forever,
    -- origin/live):
    --   <Frame name="PaperDollFrame" setAllPoints="true" ...>       (no hidden)
    --   <Frame name="CharacterFrame" toplevel="true" ... hidden="true" ...>
    --
    -- CharacterFrame IS hidden at creation on every branch, so ITS OnShow
    -- fires exactly once per pane open -- which is the refresh the overlay
    -- needed. One hook, one refresh, one inventory walk per open.
    --
    -- The handler is an adapter, not TT.RefreshCharacterFrame itself: a
    -- HookScript handler is called as handler(frame), so the method would
    -- have received the FRAME as `self`.
    if (_G.CharacterFrame and _G.CharacterFrame.HookScript) then
        -- Unguarded deliberately: CharacterFrame declares OnShow on all five
        -- branches (classic_era Vanilla and live Mainline verified), so a
        -- HasScript gate would be a no-op in game. The harness reason not to
        -- add one is in the note above the InspectFrame OnHide hook below.
        _G.CharacterFrame:HookScript("OnShow", function()
            -- runUntainted: addon code inside a Blizzard frame's script chain
            -- taints that frame, and the taint reaches the game menu.
            return runUntainted(function()
                characterPaneReadyBudget = 1
                -- A raise in here would unwind through the CLIENT's own
                -- CharacterFrame OnShow dispatch, so the rest of Blizzard's
                -- handler for that frame would never run and the pane would be
                -- left half drawn. The call is bounded and counted on the same
                -- idiom as the item-load path: the raise stays off the engine's
                -- callback and the count is visible in /tacotip diag.
                local ok, err = pcall(TT.RefreshCharacterFrame, TT)
                if (not ok) then
                    TT.ev = TT.ev or {}
                    TT.ev.characterPaneOnShowFailed = (TT.ev.characterPaneOnShowFailed or 0) + 1
                    TT.ev.lastCharacterPaneOnShowError = tostring(err)
                end
            end)
        end)
    end
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
--
-- M-2 (final hunter): the wrapper used to claim it was "deliberately narrow"
-- when it was not -- it pcalled the WHOLE of Blizzard's Update, so ANY error
-- inside it was swallowed AND counted as `inspectGuildGuardCaught`, a name
-- that asserts the error was the guild-nil case. It was not: a raise from
-- anywhere else in the function was filed under a cause we had not checked,
-- and the rest of the inspect update was lost with no trace of why.
--
-- The guard now says what it actually does:
--
--   * It still swallows every error from the wrapped function. That is the
--     POINT of the guard: the player must never get an engine error out of a
--     frame we wrapped, and the wrapped function is Blizzard's, so its raise
--     is not something we can re-raise usefully.
--   * It COUNTS the two cases separately, so the count names the cause:
--       inspectGuildGuardCaught  -- the known Blizzard defect (below)
--       inspectUpdateErrors      -- anything else, with the message kept
--
-- The classification does NOT guess from the error text. The wording of a
-- C-API argument error varies by client and by locale, and a text match would
-- file an unrelated raise under a cause we had not proved. It asks the
-- CLIENT'S OWN DATA instead: the guild realm name is nil exactly when the
-- inspected player has no guild, and that nil is what Blizzard's guild block
-- formats -- so "the realm name is nil" IS the precondition of the defect.
--
-- Which guild value is the unguarded nil depends on the variant, and the
-- precondition is the same either way:
--   origin/live, Mainline/InspectGuildFrame.lua:18-22 -- the realm name:
--     InspectGuildFrame.guildRealmName:SetFormattedText(INSPECT_GUILD_REALM, guildRealmName)
--   origin/forever, Camelot/InspectGuildFrame.lua:17-23 -- the same global
--     without the realm line; the guild NAME is the nil the block formats.
--
-- The probe is the same API Blizzard's own Update calls first
-- (C_PaperDollInfo.GetInspectGuildInfo, four values: achievement points,
-- member count, guild name, realm name -- PaperDollInfoDocumentation.lua:95
-- on origin/live and :104 on origin/forever), and it is pcall-guarded: if it
-- cannot run, the error is filed in the honest bucket, because a case that
-- cannot be proved is not a case that may be claimed.
local function isKnownGuildRealmDefect()
    local api = rawget(_G, "C_PaperDollInfo")
    if (type(api) ~= "table" or type(api.GetInspectGuildInfo) ~= "function") then
        return false
    end
    local frame = rawget(_G, "InspectFrame")
    local unit = frame and frame.unit
    if (not unit) then
        return false
    end
    local ok, _, _, _, realmName = pcall(api.GetInspectGuildInfo, unit)
    if (not ok) then
        return false
    end
    return realmName == nil
end

local function guardBlizzardInspectGuildFrame()
    local update = rawget(_G, "InspectGuildFrame_Update")
    if (type(update) ~= "function") then return false end
    if (rawget(_G, "_tacoTipInspectGuildGuarded")) then return true end
    rawset(_G, "_tacoTipInspectGuildGuarded", true)
    rawset(_G, "InspectGuildFrame_Update", function(...)
        local ok, err = pcall(update, ...)
        if (ok) then
            return
        end
        TT.ev = TT.ev or {}
        if (isKnownGuildRealmDefect()) then
            -- The known Blizzard defect: the inspected player has no guild, so
            -- the realm line raised. Swallowed on purpose -- the player's
            -- inspect must survive a defect that is not ours.
            TT.ev.inspectGuildGuardCaught = (TT.ev.inspectGuildGuardCaught or 0) + 1
        else
            -- Anything else. Still swallowed (see above), but NO LONGER counted
            -- as a guild-guard catch: this bucket, with its message, says what
            -- actually went wrong.
            TT.ev.inspectUpdateErrors = (TT.ev.inspectUpdateErrors or 0) + 1
            TT.ev.lastInspectUpdateError = tostring(err)
        end
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

    -- The pane that actually fires OnShow.
    --
    -- InspectPaperDollFrame carries NO `hidden` attribute on any of the five
    -- branches, so it is shown from creation and its OnShow fired before this
    -- addon loaded -- the hook on it could never fire. InspectFrame IS hidden
    -- at creation on every branch, so ITS OnShow fires once per inspect
    -- open, which is the refresh the overlay needed.
    --
    -- Mirror evidence (all five branches -- origin/classic_era,
    -- origin/classic_anniversary, origin/classic_titan, origin/forever,
    -- origin/live):
    --   <Frame name="InspectPaperDollFrame" setAllPoints="true" ...>  (no hidden)
    --   <Frame name="InspectFrame" toplevel="true" ... hidden="true" ...>
    --
    -- The handler is an adapter, not TT.RefreshInspectFrame itself: a
    -- HookScript handler is called as handler(frame), so the method would
    -- have received the FRAME as `self`.
    if (_G.InspectFrame and _G.InspectFrame.HookScript) then
        _G.InspectFrame:HookScript("OnShow", function()
            -- runUntainted: addon code inside a Blizzard frame's script chain
            -- taints that frame, and the taint reaches the game menu.
            return runUntainted(function()
                -- Bounded and counted, for the same reason as the character pane
                -- hook above: a raise in here unwinds through the client's own
                -- InspectFrame OnShow dispatch and leaves the inspect pane half
                -- drawn.
                local ok, err = pcall(TT.RefreshInspectFrame, TT)
                if (not ok) then
                    TT.ev = TT.ev or {}
                    TT.ev.inspectPaneOnShowFailed = (TT.ev.inspectPaneOnShowFailed or 0) + 1
                    TT.ev.lastInspectPaneOnShowError = tostring(err)
                end
            end)
        end)
    end
    -- Deliberately unguarded — not an oversight. `InspectFrame` declares
    -- OnShow AND OnHide on all five branches (classic_era Vanilla and live
    -- Mainline both verified), so a `HasScript` gate here is a no-op in game.
    --
    -- It is also load-bearing for the 0.7.9 guildless-inspect pin: that pin
    -- re-runs `TT:InitInspectFrame` from the ADDON_LOADED handler, and it can
    -- only do so because THIS call raises on the test's stub `InspectFrame`
    -- (a bare table with no `HookScript`) and short-circuits the lazy-init in
    -- `TT:RefreshInspectFrame` before it can nil the flag. Guarding this call
    -- makes the init complete, the flag disappear, and the pin unobservable —
    -- verified by bisect: guarding OnShow alone leaves the pin green, guarding
    -- OnHide alone turns it red. So it stays exactly as shipped in 0.7.9.
    InspectFrame:HookScript("OnHide", function()
        return runUntainted(function()
            InspectGearScore:Hide()
            InspectAvgItemLvl:Hide()
        end)
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
        + (ev.optionsPanelOpenFailed or 0) + (ev.optionsPanelShowFailed or 0)
        + (ev.moverSaveSkipped or 0) + (ev.moverSaveFailed or 0)
        + (ev.moverDisableFailed or 0) + (ev.configRepairs or 0)
        + (ev.characterPaneOnShowFailed or 0) + (ev.inspectPaneOnShowFailed or 0)
        + (ev.anchorHookFailed or 0) + (ev.statusBarHookRefused or 0)
    if (total == 0) then
        line("event counters", "no events recorded yet -- hover a character first")
        return
    end
    print("|cff59f0dc-- event counters (cumulative since /reload) --|r")
    line("unit renders", ev.unitRender or 0)
    line("GearScore callbacks", ev.gsCallback or 0)
    line("  of those, dropped as re-entrant", ev.gsCallbackReentrant or 0)
    line("  of those, wrong unit", ev.gsCallbackWrongUnit or 0)
    -- Labels here MUST name what is counted. TT.ev.portraitHide counts
    -- teardowns that released a loaded model, not Hide() calls, and printing it
    -- as "portrait hide" made it look like the hide was being measured when
    -- nothing could observe that call. Hence the separate portraitModelHidden
    -- counter, which counts every Hide() that actually ran in
    -- clearTooltipVisuals -- and, since the no-op guard, only the ones that ran
    -- because the frame was still shown. Hide() on an already-hidden frame is
    -- not called any more, so this is the number to read for "a clear took the
    -- frame away", with no engine no-ops mixed in.
    --
    -- The "(on clear)" in the label is load-bearing, not decoration:
    -- TT:ApplyTooltipAppearance has its own Hide(), on the branch taken when
    -- the portrait option is off or the unit is nil, and that one is NOT
    -- counted here. A label reading plain "Hide() calls" would claim to see a
    -- call it cannot.
    line("portrait Hide() calls (on clear)", ev.portraitModelHidden or 0)
    -- portraitHide and portraitDestroy are incremented in the same two lines
    -- and therefore always equal; both are kept so the older name still reads.
    -- Both -- and teardownBy below -- count only teardowns where the
    -- loaded-unit cache still named a model: a teardown of a frame with no mesh
    -- is the engine no-op that inflated destroys 310 against 99 renders, and it
    -- no longer records as a teardown at all.
    line("portrait teardowns (hide + ClearModel)", ev.portraitHide or 0)
    line("portrait destroys (ClearModel)", ev.portraitDestroy or 0)
    line("portrait re-anchor", ev.portraitAnchor or 0)
    line("portrait guard flips (measured off-screen)", ev.portraitGuardFlip or 0)
    line("portrait set failures", ev.portraitSetFailed or 0)
    -- H1 / L1: the calls whose pcall result used to be discarded outright.
    -- Each names the CALL SITE it counts, so a rising number can be acted on.
    line("portrait zoom failures", ev.portraitZoomFailed or 0)
    line("portrait zoom unsupported (no published default)", ev.portraitZoomUnsupported or 0)
    line("portrait ClearModel failures (render path)", ev.portraitClearModelFailed or 0)
    line("portrait ClearModel failures (teardown path)", ev.portraitTeardownClearModelFailed or 0)
    line("tooltip repaint failures (timer path)", ev.tooltipRepaintFailed or 0)
    line("tooltip repaint failures (item-load callback)", ev.tooltipRepaintCallbackFailed or 0)
    line("item-load callback registration failures", ev.itemLoadCallbackFailed or 0)
    line("mouseover guard hits", ev.tooltipIsMouseoverGuarded or 0)
    -- Hunter M-NEW2: neutral passthrough tallies from the secure anchor gate
    -- (not failure events -- a menu hover is supposed to skip). Split so a
    -- rising "unresolved" is distinguishable from routine menu traffic.
    line("anchor passthrough (menu/popup surface)", ev.anchorSkippedMenu or 0)
    line("anchor passthrough (unit-like, unresolved)", ev.anchorSkippedUnresolved or 0)
    -- The anchor post-hook is the one callback that runs inside a Blizzard
    -- call (GameTooltip_SetDefaultAnchor) and mutates a Blizzard frame, so it
    -- is counted where a raise would otherwise be invisible: the containment
    -- swallows it (securecall) and the pcall inside it counts it here.
    line("anchor hook failures", ev.anchorHookFailed or 0)
    if (ev.anchorHookFailed and ev.anchorHookFailed > 0) then
        line("  last anchor hook error", ev.lastAnchorHookError or "?")
    end
    -- The tooltip status bar declares no OnHide on any of the five clients, so
    -- the teardown hook is installed under a pcall. Zero is the healthy value;
    -- a non-zero count means this client refused it.
    if (ev.statusBarHookRefused and ev.statusBarHookRefused > 0) then
        line("tooltip status-bar hook refused", ev.statusBarHookRefused)
    end
    line("not-ready scores hidden (pending)", ev.gsPendingHidden or 0)
    line("item refresh fire-and-forget", ev.itemRefreshFireAndForget or 0)
    line("power-bar unit-reg fallbacks", ev.powerBarRegFailed or 0)
    line("resolve failures", ev.resolveTooltipUnitFailed or 0)
    if (ev.resolveTooltipUnitFailed and ev.resolveTooltipUnitFailed > 0) then
        line("  last resolve cause", ev.resolveTooltipUnitLastCause or "?")
        line("  no-tooltip", ev.resolveFailNoTooltip or 0)
        line("  no-source", ev.resolveFailNoSource or 0)
        line("  unresolved", ev.resolveFailUnresolved or 0)
    end
    line("inspect guild guard caught (no-guild realm nil)", ev.inspectGuildGuardCaught or 0)
    -- The two inspect-frame buckets, kept apart on purpose (M-2). The first
    -- counts the KNOWN Blizzard defect -- the inspected player has no guild,
    -- so Blizzard's own realm line raises. The second counts every OTHER
    -- error the wrapped function produced, with its message, because a count
    -- that says "the guild case" for a cause nobody checked is worse than no
    -- count at all.
    line("  inspect update errors (other)", ev.inspectUpdateErrors or 0)
    if (ev.inspectUpdateErrors and ev.inspectUpdateErrors > 0) then
        line("  last inspect update error", ev.lastInspectUpdateError or "?")
    end
    -- Cold-path counters added by the final hunter: each names a call whose
    -- failure used to be swallowed with no trace.
    line("tooltip width cap failures", ev.tooltipMaxWidthFailed or 0)
    line("inspect trigger failures", ev.inspectTriggerFailed or 0)
    line("character pane refresh failures", ev.characterPaneRefreshFailed or 0)
    -- The options panel and the tooltip mover's slash commands (final
    -- hardening pass). Each of these used to be a silent no-op: the command
    -- was typed, nothing happened, and nothing was counted.
    line("options panel open failures", ev.optionsPanelOpenFailed or 0)
    line("options panel show failures", ev.optionsPanelShowFailed or 0)
    line("/tacotip save skipped (mover not shown)", ev.moverSaveSkipped or 0)
    line("/tacotip save failures", ev.moverSaveFailed or 0)
    line("/tacotip default failures", ev.moverDisableFailed or 0)
    -- The corrupt-saved-data ledger: how many settings the sanitiser had to
    -- repair on the last pass, and which one it repaired first.
    line("corrupt saved settings repaired", ev.configRepairs or 0)
    -- The two pane OnShow hooks (final hardening pass). A raise in either one
    -- used to unwind through the CLIENT's own frame script, so the rest of
    -- Blizzard's handler never ran and the pane was left half drawn.
    line("character pane OnShow refresh failures", ev.characterPaneOnShowFailed or 0)
    line("inspect pane OnShow refresh failures", ev.inspectPaneOnShowFailed or 0)
    -- Name the path that let the model go. A single portrait-hide count could
    -- not distinguish them, and a fix aimed at the wrong one shipped on top of
    -- that -- the unresolved-unit path was patched and the blink stayed, because
    -- a different call site was the one actually firing. Only teardowns that
    -- actually released a model are recorded, matching the counters above.
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
            -- suppressed` climbed beside it. hunter H11: the overlap is
            -- documented in the label, and the error carries its own uptime
            -- timestamp (lastErrorAt) so staleness is decidable. No counters
            -- are merged: refusals and raises stay separate by design.
            if (st.lastError) then
                line("  last inspect-call error (raise only; refusals counted above, not here)",
                    tostring(st.lastError))
                line("  last error at (uptime)", st.lastErrorAt or "?")
            end
            -- Watchdog attribution (hunter H10): which unit the 3s watchdog
            -- gave up on, and how long queued units wait before dispatch.
            if (st.lastWatchdogUnit) then
                line("  last watchdog drop", tostring(st.lastWatchdogUnit))
            end
            line("  max queue wait", st.maxQueueWait or 0)
            line("  avg queue wait", st.avgQueueWait or 0)
            -- Engine availability (hunter H5): without C_Timer.NewTicker the
            -- whole inspect engine is inert. The library records the install
            -- state; the retry rides ADDON_LOADED.
            if (st.tickersInstalled == false) then
                line("  tickers installed", false)
            end
            line("  learned max range", st.learnedRange and (tostring(st.learnedRange) .. "yd") or "unknown")
            line("  scan enqueued", st.scanEnqueued or 0)
            line("  scan via fallback", st.scanFallback or 0)
            line("  scan skipped (range)", st.scanSkippedDistance or 0)
            -- Queue overflow is silent by design (the oldest queued inspect is
            -- discarded to make room), so the count is the only trace. The last
            -- evicted guid and its queue age say WHO was dropped and how long
            -- they had waited.
            line("  queue dropped (overflow)", st.queueDropped or 0)
            if (st.lastQueueDropGuid) then
                line("  last queue drop", tostring(st.lastQueueDropGuid)
                    .. " after " .. tostring(st.lastQueueDropAge or "?") .. "s queued")
            end
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
    --
    -- Hunter M6: the border had this diag; font, bar and background resolved
    -- through the same silent-fallback shape and had none. All four now report
    -- the same way.
    local cfg = _G.TacoTipConfig
    local mediaChecks = {
        { key = "tooltip_border_texture", choicesFn = TT.GetTooltipBorderChoices,
            def = TT.GetDefaultTooltipBorder and TT:GetDefaultTooltipBorder() },
        { key = "tooltip_font", choicesFn = TT.GetTooltipFontChoices,
            def = "Fonts\\FRIZQT__.TTF" },
        { key = "tooltip_bar_texture", choicesFn = TT.GetTooltipStatusBarTextureChoices,
            def = "Interface\\TargetingFrame\\UI-TargetingFrame-BarFill" },
        { key = "tooltip_background_texture", choicesFn = TT.GetTooltipBackgroundChoices,
            def = "Interface\\Tooltips\\UI-Tooltip-Background" },
    }
    if (cfg) then
        for _, mc in ipairs(mediaChecks) do
            local value = cfg[mc.key]
            local getChoices = mc.choicesFn
            if (value and type(getChoices) == "function") then
                local matched = false
                local ok, choices = pcall(getChoices, TT)
                if (ok and choices) then
                    for _, entry in ipairs(choices) do
                        if (entry.value == value or entry.text == value) then
                            matched = true
                            break
                        end
                    end
                end
                if (not matched) then
                    problems[#problems + 1] = tostring(mc.key) .. " setting '" .. tostring(value)
                        .. "' matches no entry and is being replaced by the per-client default ("
                        .. tostring(mc.def) .. ")"
                end
            end
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

    -- Pawn late-load vs no-scale (hunter C3). The render gate stays on the
    -- file-scope snapshot, so a Pawn that appears after load is a fact the
    -- player can act on (reload) rather than a silent absence. Read live here
    -- so diag names it; no state is changed.
    if (not isPawnLoaded and isPawnAvailableNow()) then
        problems[#problems + 1] = "Pawn detected after load -- scores unavailable until reload"
    end

    -- Options-side failures (hunter H7): registration and scan-apply errors
    -- are recorded by options.lua into TT.optionsRegErrors, one chat line per
    -- distinct failure, and surfaced here. Read-only: no state is changed.
    if (TT.optionsRegErrors) then
        for _, e in ipairs(TT.optionsRegErrors) do
            problems[#problems + 1] = tostring(e)
        end
    end

    -- Options load leg (hunter H-NEW2): the six LoadAddOn probes in
    -- options.lua are counted with the last error kept (TT.ev). Any failure
    -- leaves the corresponding options surface missing with no other trace,
    -- so it is named here. Read-only: no state is changed.
    if (TT.ev and TT.ev.optionsLoadFailures and TT.ev.optionsLoadFailures > 0) then
        problems[#problems + 1] = "options load failures: " .. tostring(TT.ev.optionsLoadFailures)
            .. " (last: " .. tostring(TT.ev.lastOptionsLoadError or "?") .. ")"
    end

    -- The options panel itself (final hardening pass).
    --
    -- options.lua opened the panel through three protected calls whose
    -- RESULTS were discarded, so a raising one left the player with a typed
    -- command, no panel, and no message and no count. The failures are
    -- counted with the last error kept, and named here. Read-only: no state
    -- is changed.
    if (TT.ev and TT.ev.optionsPanelOpenFailed and TT.ev.optionsPanelOpenFailed > 0) then
        problems[#problems + 1] = "options panel open failures: "
            .. tostring(TT.ev.optionsPanelOpenFailed)
            .. " (last: " .. tostring(TT.ev.lastOptionsPanelError or "?") .. ")"
    end
    if (TT.ev and TT.ev.optionsPanelShowFailed and TT.ev.optionsPanelShowFailed > 0) then
        problems[#problems + 1] = "options panel show failures: "
            .. tostring(TT.ev.optionsPanelShowFailed)
            .. " (last: " .. tostring(TT.ev.lastOptionsPanelError or "?") .. ")"
    end
    -- The tooltip mover's slash commands. "/tacotip save" did NOTHING and said
    -- nothing when the mover was not open, and a raising save was swallowed
    -- by the abort. Both are counted now, so the report can say that the
    -- command was a dead end rather than leaving the player guessing.
    if (TT.ev and TT.ev.moverSaveSkipped and TT.ev.moverSaveSkipped > 0) then
        problems[#problems + 1] = "/tacotip save skipped (the tooltip mover was not shown): "
            .. tostring(TT.ev.moverSaveSkipped)
    end
    if (TT.ev and TT.ev.moverSaveFailed and TT.ev.moverSaveFailed > 0) then
        problems[#problems + 1] = "/tacotip save failures: "
            .. tostring(TT.ev.moverSaveFailed)
    end
    if (TT.ev and TT.ev.moverDisableFailed and TT.ev.moverDisableFailed > 0) then
        problems[#problems + 1] = "/tacotip default failures (the mover could not be disabled): "
            .. tostring(TT.ev.moverDisableFailed)
    end

    -- The corrupt-saved-data ledger (final hardening pass).
    --
    -- A hand-edited TacoTipConfig fails closed and recovers to the shipped
    -- defaults -- but the repair was SILENT, so a player whose settings had
    -- been reset had no way to learn that one of their options had changed
    -- under them. The number of repaired settings is counted and the first one
    -- is named here.
    if (TT.ev and TT.ev.configRepairs and TT.ev.configRepairs > 0) then
        problems[#problems + 1] = "corrupt saved settings repaired: "
            .. tostring(TT.ev.configRepairs)
            .. " (first: " .. tostring(TT.ev.lastConfigRepair or "?") .. ")"
    end

    -- M1: the TacoTip Extras forward ledger.
    --
    -- gearscore.lua counts a raise inside an Extras handler, keeps the last
    -- command and the last error, and prints ONE actionable chat line. The
    -- counters were never read by anything, so /tacotip diag answered
    -- "problems: none detected" while the Extras forward was broken -- the
    -- pointer to the report was a lie. The count, the last command and the
    -- last error are all named here, so the report is true.
    if (TT.ev and TT.ev.extrasForwardFailed and TT.ev.extrasForwardFailed > 0) then
        problems[#problems + 1] = "TacoTip Extras forward failures: "
            .. tostring(TT.ev.extrasForwardFailed)
            .. " (last command: " .. tostring(TT.ev.extrasForwardLastCommand or "?")
            .. ", last error: " .. tostring(TT.ev.extrasForwardLastError or "?") .. ")"
    end

    -- L2: TacoTip Extras' own failure counters. The Extras counts the calls
    -- whose failures it used to discard (a slash-command registration that
    -- returned false, an options panel that could not open) and publishes
    -- them for this diagnostic, so a degraded Extras is visible from the main
    -- add-on's report and not only from "/ttgsdebug".
    local extrasCounters = nil
    local extrasCounterGetter = rawget(_G, "TacoTipExtrasGetFailureCounters")
    if (type(extrasCounterGetter) == "function") then
        local ok, counters = pcall(extrasCounterGetter)
        if (ok and type(counters) == "table") then
            extrasCounters = counters
        end
    end
    if (extrasCounters) then
        -- Sorted, so the report reads the same way twice.
        local names = {}
        for name in pairs(extrasCounters) do
            names[#names + 1] = name
        end
        table.sort(names)
        for _, name in ipairs(names) do
            local count = extrasCounters[name]
            if (type(count) == "number" and count > 0) then
                problems[#problems + 1] = "TacoTip Extras failure: " .. tostring(name)
                    .. " (" .. tostring(count) .. ")"
            end
        end
    end

    -- Engine availability (hunter H5): without C_Timer.NewTicker the inspect
    -- engine never ticks. The library records the install state and retries
    -- on ADDON_LOADED; here it is a fact the player can act on (client
    -- without the timer API), not a silent dead scan.
    if (CI and CI.tickersInstalled == false) then
        problems[#problems + 1] = "inspect engine tickers not installed (no C_Timer.NewTicker) -- proximity scan and queue are inert"
    end

    -- C2 clock availability (load-time probe): without GetTime/C_Timer.After
    -- every throttle, cooldown, guard window and queue pacing above is
    -- bypassed fail-open instead of wedged on a memoised 0. Read-only: no
    -- state is changed.
    do
        local gsClock = _G.TT_GS and _G.TT_GS.ClockAvailable
        local libClock = CI and CI.clockAvailable
        if (clockAvailable == false or libClock == false or gsClock == false) then
            problems[#problems + 1] = "system clock unavailable (GetTime/C_Timer.After missing) -- throttles, cooldowns and queue pacing are bypassed (fail-open)"
        end
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
    -- Which fade path this client can actually take (arbiter N2).
    -- GameTooltip.FadeOut exists only on the modern pair (origin/live and
    -- origin/forever); the Classic family has no such method, so the option
    -- degrades there. Without this line the mode was recorded in
    -- TT.InstantFadeMode and printed nowhere, so "the toggle does nothing"
    -- was indistinguishable from "the toggle is off".
    --   secure-hook   -- the FadeOut post-hook is installed (instant fade on)
    --   standard-fade -- the option is off, the client fades normally
    --   unsupported   -- this client has no GameTooltip.FadeOut at all
    line("instant fade", TT.InstantFadeMode or "not recorded")
    line("instant fade API", type(gt and gt.FadeOut))
    line("TT.HookedTooltipScripts", TT.HookedTooltipScripts
        and ("unit=" .. tostring(TT.HookedTooltipScripts.Unit)
            .. " item=" .. tostring(TT.HookedTooltipScripts.Item)
            .. " spell=" .. tostring(TT.HookedTooltipScripts.Spell)) or "none")
    -- A C API argument error carries no Lua stack, so this is the only place it
    -- can be named. Reported once per distinct message; see handlePipelineError.
    line("last tooltip error", TT.lastTooltipError or "none")
    line("pipeline errors suppressed", TT.ev and TT.ev.pipelineErrorsSuppressed or 0)
    if (TT.ev and TT.ev.pipelineSuppressedRing and #TT.ev.pipelineSuppressedRing > 0) then
        line("  suppressed (up to 5)", table.concat(TT.ev.pipelineSuppressedRing, " ;; "))
    end
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
                -- GameMenu-quit taint fix: never replace GameTooltip.FadeOut.
                -- The old Detours:DetourHook swapped the Blizzard method for
                -- addon code, so any secure path that faded the tooltip ran
                -- tainted code (ADDON_ACTION_FORBIDDEN). A hooksecurefunc
                -- post-hook preserves the original function identity and hides
                -- after the genuine fade starts, which reads as instant.
                -- Toggle and default (off) unchanged.
                if (GameTooltip and type(GameTooltip.FadeOut) == "function") then
                    Detours:SecureHook(TT, GameTooltip, "FadeOut", function(tooltipFrame)
                        -- runUntainted: a hooksecurefunc post-hook does not
                        -- replace the hooked function, but its BODY still runs
                        -- as addon code inside the caller's script chain --
                        -- here, the unit frame's OnLeave
                        -- (Blizzard_UnitFrame/Classic/UnitFrame.lua:447
                        -- `GameTooltip:FadeOut();`). That taints the unit
                        -- frame, the taint reaches the game menu, and the
                        -- Logout/Quit button is refused. Replacing the
                        -- DETOUR (the 0.8.3 shape) fixed the method identity
                        -- but not the body; this fixes the body.
                        return runUntainted(safeCall, function()
                            if (TacoTipConfig and TacoTipConfig.instant_fade and tooltipFrame) then
                                tooltipFrame:Hide()
                            end
                        end)
                    end)
                    TT.InstantFadeMode = "secure-hook"
                else
                    -- No FadeOut to hook: degrade to the standard fade rather
                    -- than tainting anything to reinvent it.
                    --
                    -- GameTooltip.FadeOut is an ENGINE method with no Lua
                    -- definition on any branch, so a whole-tree sweep cannot
                    -- prove it absent -- and Blizzard's own call sites say it
                    -- is present on all five:
                    --   origin/classic_era, origin/classic_anniversary,
                    --   origin/classic_titan:
                    --     Interface/AddOns/Blizzard_UnitFrame/Classic/UnitFrame.lua:447
                    --   origin/forever:
                    --     Interface/AddOns/Blizzard_UnitFrame/Mainline/UnitFrame.lua:393
                    --   origin/live:
                    --     Interface/AddOns/Blizzard_UnitFrame/Mainline/UnitFrame.lua:386
                    -- On the Classic family that handler is wired to the OnLeave
                    -- of PlayerFrame.xml:374 and TargetFrame.xml:380, so the
                    -- call runs on every mouse-out. This branch is the
                    -- capability guard for a client that genuinely lacks the
                    -- method, not the expected path on any supported client.
                    --
                    -- "unsupported" is recorded rather than "standard-fade" so
                    -- /tacotip diag can say the client CANNOT do it, not
                    -- merely that it is off.
                    TT.InstantFadeMode = "unsupported"
                end
            else
                -- The option is off: the client fades normally. Recorded so
                -- diag can distinguish "off" from "cannot be done".
                TT.InstantFadeMode = "standard-fade"
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
        if (TacoTipConfig.instant_fade and GameTooltip and GameTooltip:IsShown() and tooltipIsMouseover(GameTooltip)) then
            cancelFadeTimer(GameTooltip)
            local state = getTooltipState(GameTooltip)
            local timer
            if (type(NewTimer) == "function") then
                timer = NewTimer(0, function()
                    if (state.fadeTimer == timer) then
                        state.fadeTimer = nil
                    end
                    safeCall(function()
                        if (TacoTipConfig.instant_fade and not UnitExists("mouseover") and GameTooltip and GameTooltip:IsShown() and tooltipIsMouseover(GameTooltip)) then
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
                -- C2 fail-open: without a clock there is no coalesce window to
                -- measure, so every render rebuilds (never memoise 0, never
                -- suppress a genuine update on now-renderTime == 0).
                if (clockAvailable and type(GetTime) == "function") then
                    local now = GetTime()
                    local duplicate = (st.inspectRenderGUID == guid
                        and st.inspectRenderTime ~= nil
                        and (now - st.inspectRenderTime) < INSPECT_RENDER_COALESCE)
                    if (not duplicate) then
                        st.inspectRenderGUID = guid
                        st.inspectRenderTime = now
                        GameTooltip:SetUnit(ttUnit)
                    end
                else
                    st.inspectRenderGUID = guid
                    st.inspectRenderTime = nil
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

-- Secure-menu taint guard (hunter H-NEW1). ShowExample mutates the shared
-- GameTooltip (SetOwner/ClearAllPoints/SetPoint/SetUnit/Show) from a 1s
-- ticker plus OnShow/OnHide post-hooks whenever the mover is shown. Running
-- any of that while GameMenu owns the screen taints the quit path
-- (ADDON_ACTION_FORBIDDEN), the same class the instant-fade fix removed.
-- The guard is one helper so the ticker, both hooks, ShowExample itself,
-- the drag OnUpdate and the right-click confirm cannot drift apart again.
--
-- The dialog pool is exactly StaticPopup1..4 (hunter M-NEW4). Verified on ALL
-- FIVE branches of the FrameXML mirror (wow-ui-source), file
-- Interface/AddOns/Blizzard_StaticPopup_Game/GameDialog.xml:
--   origin/classic_era          GameDialog.xml:334-349  (StaticPopup1..4, ids 1..4)
--   origin/classic_anniversary  GameDialog.xml:334-349  (StaticPopup1..4, ids 1..4)
--   origin/classic_titan        GameDialog.xml:334-349  (StaticPopup1..4, ids 1..4)
--   origin/live                 GameDialog.xml:334-349  (StaticPopup1..4, ids 1..4)
--   origin/forever              GameDialog.xml:339-354  (StaticPopup1..4, ids 1..4)
-- Those four named frames are the whole pool on every branch, and "StaticPopup5"
-- matches NOWHERE in any of the five -- so the loop bound below is named, not
-- magic.
local MAX_STATIC_POPUP_DIALOGS = 4
local function isSecureMenuBusy()
    local gameMenu = rawget(_G, "GameMenuFrame")
    if (gameMenu and type(gameMenu.IsShown) == "function") then
        local okMenu, menuShown = pcall(gameMenu.IsShown, gameMenu)
        if (okMenu and menuShown) then
            return true
        end
    end
    for i = 1, MAX_STATIC_POPUP_DIALOGS do
        local popup = _G["StaticPopup" .. i]
        if (popup and type(popup.IsShown) == "function") then
            local okShown, shown = pcall(popup.IsShown, popup)
            if (okShown and shown) then
                return true
            end
        end
    end
    return false
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
                -- A nil read here is transient: the frame's rect is not valid in
                -- the same frame the drag ends. Storing the DEFAULT at that
                -- moment is what made a just-dragged handle snap back to the
                -- corner and lose the user's position -- keep whatever was
                -- saved, and count it so /tacotip diag names the failure.
                TT.ev = TT.ev or {}
                TT.ev.moverSaveFailed = (TT.ev.moverSaveFailed or 0) + 1
                print("|cff59f0dcTacoTip:|r The tooltip position could not be saved.")
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
                -- Zero-risk taint guard: never stack our confirm while any
                -- secure/static dialog owns the screen. The mover stays open
                -- for retry, so skipping loses nothing.
                if (isSecureMenuBusy()) then
                    return
                end
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
                if (isSecureMenuBusy()) then
                    return
                end
                TacoTipDragButton:ShowExample()
            end
            self.ticker = NewTicker(1, function(...)
                safeCall(onMoverTick, ...)
            end)
            local function onMoverGameTooltipShow(tooltipFrame)
                if (isSecureMenuBusy()) then
                    return
                end
                if (TacoTipDragButton:IsShown()) then
                    local shownUnit = resolveTooltipUnit(tooltipFrame)
                    if (not shownUnit or not UnitIsUnit(shownUnit, "player")) then
                        TacoTipDragButton:ShowExample()
                    end
                end
            end
            local function onMoverGameTooltipHide(tooltipFrame)
                if (isSecureMenuBusy()) then
                    return
                end
                if (TacoTipDragButton:IsShown()) then
                    TacoTipDragButton:ShowExample()
                end
            end
            -- runUntainted: both hooks put addon code inside the shared
            -- GameTooltip's script chain. The tooltip is reached from the
            -- unit frames' own chains, so that taint lands on the unit frame
            -- and reaches the game menu.
            Detours:ScriptHook(TT, GameTooltip, "OnShow", function(tooltipFrame, ...)
                return runUntainted(safeCall, onMoverGameTooltipShow, tooltipFrame, ...)
            end)
            Detours:ScriptHook(TT, GameTooltip, "OnHide", function(tooltipFrame, ...)
                return runUntainted(safeCall, onMoverGameTooltipHide, tooltipFrame, ...)
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
                    -- Zero-risk taint guard: never reposition the tooltip while
                    -- the secure menu owns the screen. Dragging the mover with
                    -- GameMenu open has no valid use; skipping is a no-op.
                    if (isSecureMenuBusy()) then
                        return
                    end
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
            -- Defense in depth (hunter H-NEW1): every caller above already
            -- guards, but ShowExample itself must never mutate the shared
            -- GameTooltip while secure menu code is on the stack.
            if (isSecureMenuBusy()) then
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
