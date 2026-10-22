local _, namespace = ...

if type(namespace) ~= "table"
    or type(namespace.Scanner) ~= "table"
    or type(namespace.Cache) ~= "table"
    or type(namespace.TacoTipAdapter) ~= "table" then
    return
end

local Scanner = namespace.Scanner
local Cache = namespace.Cache
local Adapter = namespace.TacoTipAdapter
local Core = namespace.Core
local Tooltips = {}
namespace.Tooltips = Tooltips

-- Bound at file scope. TacoExtrasApplyLocale MUTATES this table rather than
-- replacing it, so the reference stays live across a language change.
local L = _G.TACOEXTRAS_LOCALE or {}

local MODES = {
    Disabled = true,
    Minimal = true,
    Compact = true,
    Detailed = true,
}

local REQUIRED_SLOTS = {
    1, 2, 3, 5, 6, 7, 8, 9, 10,
    11, 12, 13, 14, 15, 16, 17, 18,
}

local settings
local tooltip
local binding
local initialized = false
local rendering = false
local refreshing = false
local localListener
local remoteListener

-- ---------------------------------------------------------------------------
-- Tooltip driver state
-- ---------------------------------------------------------------------------
--
-- driverMode records WHICH hook point this client actually took, so "supported"
-- and "the right branch ran" are two different, separately checkable claims:
--
--   "unit-hook"   GameTooltip declares OnTooltipSetUnit. That script drives
--                 renderPlayerTooltip. This is the Classic family.
--   "poll"        GameTooltip does NOT declare it, so the OnUpdate poll drives
--                 renderPlayerTooltip instead. Mainline: Retail, WoW Forever.
--   "none"        Neither hook point existed, the surface was refused, and
--                 the adapter was released.
--
-- The counters exist so "idempotent" is a measurement and not a claim:
--
--   renders        renderPlayerTooltip calls that got PAST the change gate
--   rows           of those, the ones that actually appended lines
--   pollTicks      times the poll script ran
--   pollWorkTicks  of those, the ones that got past the armed gate
local driverMode = "none"
local pollArmed = false
local renderAttempts = 0
local renderRows = 0
local pollTicks = 0
local pollWorkTicks = 0

-- Stage 5 tooltip session clock (epoch, guarded server-clock read). The
-- freshness line mirrors the browser's W7 ticks: it renders only for rank
-- rows older than the session. 0 means "no session yet" and renders nothing.
-- Hunter L-NEW5: this clock and the browser's browserSessionStart
-- (RankBrowser.lua) are INDEPENDENT module locals, deliberately: each
-- surface defines "this session" as its own first successful
-- GetServerTime-guarded read -- here once at tooltip-surface Initialize
-- (below), there at browser open (markSessionStart). Both derive from the
-- same server epoch and both treat 0 as "no session", so staleness is
-- always relative to the surface that renders it.
local tooltipSessionStart = 0

-- Hunter M-NEW5: RankDB.GetRecord raises swallowed by pcall (display-only
-- suppression is INTENTIONAL -- a rank-store failure must never break the
-- unit tooltip -- but it was invisible). Counted here, surfaced in
-- GetDebugState below; no display change.
local rankRecordErrors = 0
local lastRankRecordError = nil
local function noteRankRecordError(err)
    rankRecordErrors = rankRecordErrors + 1
    lastRankRecordError = tostring(err)
end

-- ---------------------------------------------------------------------------
-- Render error boundary
-- ---------------------------------------------------------------------------
--
-- `rendering` is a LATCH, not a flag: while it is true every later render is
-- refused. It used to be set on entry to renderPlayerTooltip and cleared only
-- on four NORMAL returns, so ANY raise between the set and the clear left it
-- true for the rest of the session: the Extras tooltip surface stopped
-- rendering, with no error, no counter, and no way back short of /reload.
-- The trigger paths are real -- makeRows -> RankDB.GetPlayerRank ->
-- table.sort on a non-numeric timestamp, string.format on a bad field,
-- target:AddLine, Cache.Get's recursive clone.
--
-- The boundary below has the same shape as the main add-on's
-- handlePipelineError (main.lua): the FIRST report of a distinct message goes
-- out in full, a repeat is counted as suppressed, the per-message counts live
-- in a bounded map, and the last few suppressed messages live in a bounded
-- ring. What is ADDED here -- and what the main add-on does not need, because
-- it owns no latch -- is that the latch is cleared on EVERY path out of the
-- render, including the raising one. That is the whole point of it.
--
-- The counters survive a Shutdown on purpose, exactly like the driver
-- counters above: they measure what the driver did, and zeroing them would
-- make a shutdown look like a driver that never ran.
local renderErrors = 0
local renderErrorsSuppressed = 0
local lastRenderError = nil
local reportedRenderErrors = {}
local renderErrorSeen = {}
local renderErrorRing = {}
local RENDER_ERROR_RING_MAX = 5
local RENDER_ERROR_DISTINCT_MAX = 50

local function noteRenderError(message)
    renderErrors = renderErrors + 1
    local text = tostring(message)
    lastRenderError = text

    if reportedRenderErrors[text] then
        -- A repeat of a message already reported. Counted, and the last few
        -- repeats kept in a bounded ring so a wedging surface stays
        -- diagnosable without an unbounded log.
        renderErrorsSuppressed = renderErrorsSuppressed + 1
        renderErrorSeen[text] = (renderErrorSeen[text] or 1) + 1
        if #renderErrorRing < RENDER_ERROR_RING_MAX then
            renderErrorRing[#renderErrorRing + 1] = text
        else
            table.remove(renderErrorRing, 1)
            renderErrorRing[#renderErrorRing + 1] = text
        end
        return text
    end

    -- The FIRST report of a distinct message goes out in full. The set of
    -- reported messages is bounded: past the cap a new distinct message is
    -- still counted and still named in /ttgsdebug, it just does not get its
    -- own chat line every single time.
    local distinct = 0
    for _ in pairs(reportedRenderErrors) do distinct = distinct + 1 end
    if distinct < RENDER_ERROR_DISTINCT_MAX then
        reportedRenderErrors[text] = true
    end
    if type(_G.DEFAULT_CHAT_FRAME) == "table"
        and type(_G.DEFAULT_CHAT_FRAME.AddMessage) == "function" then
        pcall(_G.DEFAULT_CHAT_FRAME.AddMessage, _G.DEFAULT_CHAT_FRAME,
            "|cffff5555TacoTip Extras:|r tooltip render failed: " .. text)
    end
    return text
end

local lastEnhancementStatus = {
    status = "not-observed",
    reason = nil,
    scope = nil,
}

local function setEnhancementStatus(nextStatus)
    lastEnhancementStatus = nextStatus
    local options = namespace.Options
    if type(options) == "table" and type(options.Refresh) == "function" then
        pcall(options.Refresh)
    end
end

local function resetEnhancementStatus()
    setEnhancementStatus({
        status = "not-observed",
        reason = nil,
        scope = nil,
    })
end

local BRAND_RED, BRAND_GREEN, BRAND_BLUE = 0.60, 0.46, 0.82
local GOLD_RED, GOLD_GREEN, GOLD_BLUE = 0.83, 0.66, 0.29
local POSITIVE_RED, POSITIVE_GREEN, POSITIVE_BLUE = 0.35, 0.82, 0.48
local NEUTRAL_RED, NEUTRAL_GREEN, NEUTRAL_BLUE = 0.82, 0.82, 0.82
local COMPACT_DELTA_LABEL = "\206\148"

local function validPlayerGUID(guid)
    if type(guid) ~= "string"
        or not string.match(guid, "^Player%-%d+%-%x+$") then
        return false
    end
    if type(_G.GUIDIsPlayer) == "function" then
        local ok, player = pcall(_G.GUIDIsPlayer, guid)
        if not ok or not player then
            return false
        end
    end
    return true
end

local function currentMode()
    local mode = settings and settings.tooltip and settings.tooltip.mode
    if MODES[mode] then
        return mode
    end
    return "Disabled"
end

local function shiftIsDown()
    if type(_G.IsShiftKeyDown) ~= "function" then
        return false
    end
    local ok, down = pcall(_G.IsShiftKeyDown)
    return ok and down == true
end

local function effectiveMode()
    local mode = currentMode()
    local tooltipSettings = settings and settings.tooltip
    if tooltipSettings
        and tooltipSettings.shiftToDetailed == true
        and shiftIsDown()
        and (mode == "Minimal" or mode == "Compact") then
        return "Detailed"
    end
    return mode
end

local function fieldEnabled(name)
    local fields = settings
        and settings.tooltip
        and settings.tooltip.fields
    return type(fields) == "table" and fields[name] == true
end

local function clearBinding()
    binding = nil
    -- Disarm the poll along with the binding. A tick with no binding must not
    -- build a new one for a tooltip nobody is looking at: that per-frame cost
    -- is the exact thing the poll driver must not have.
    pollArmed = false
    resetEnhancementStatus()
end

local function tooltipUnit(target)
    if type(target) ~= "table" then
        return nil
    end

    local tooltipUtil = _G.TooltipUtil
    if type(tooltipUtil) == "table" and type(tooltipUtil.GetDisplayedUnit) == "function" then
        local ok, _, dispUnit, dispGUID = pcall(tooltipUtil.GetDisplayedUnit, target)
        if ok then
            if type(dispUnit) == "string" and dispUnit ~= "" and type(_G.UnitExists) == "function" and _G.UnitExists(dispUnit) then
                return dispUnit
            end
            if type(dispGUID) == "string" and dispGUID ~= "" and type(_G.UnitGUID) == "function" then
                if _G.UnitGUID("mouseover") == dispGUID then return "mouseover" end
                if _G.UnitGUID("target") == dispGUID then return "target" end
                if _G.UnitGUID("player") == dispGUID then return "player" end
                if _G.UnitGUID("focus") == dispGUID then return "focus" end
            end
        end
    end

    if type(target.GetUnit) == "function" then
        local ok, name, unit, guid = pcall(target.GetUnit, target)
        if ok then
            -- In WoW API, GetUnit() returns (name, unit) on Classic and (name, unit, guid) on modern.
            -- When called via pcall(target.GetUnit, target), the return values are: ok, name, unit, guid.
            if type(unit) == "string" and unit ~= "" and type(_G.UnitExists) == "function" and _G.UnitExists(unit) then
                return unit
            end
            -- If a mock or test returns the unit token as the single/first return value:
            if type(name) == "string" and name ~= "" and type(_G.UnitExists) == "function" and _G.UnitExists(name) then
                return name
            end
            -- If guid matches a known unit token:
            if type(guid) == "string" and guid ~= "" and type(_G.UnitGUID) == "function" then
                if _G.UnitGUID("mouseover") == guid then return "mouseover" end
                if _G.UnitGUID("target") == guid then return "target" end
                if _G.UnitGUID("player") == guid then return "player" end
                if _G.UnitGUID("focus") == guid then return "focus" end
            end
        end
    end

    if type(target.IsUnit) == "function" and type(_G.UnitExists) == "function" and _G.UnitExists("mouseover") then
        local ok, isMouseover = pcall(target.IsUnit, target, "mouseover")
        if ok and isMouseover then
            return "mouseover"
        end
    end

    return nil
end

local function validatePlayerUnit(target)
    local unit = tooltipUnit(target)
    if not unit
        or type(_G.UnitExists) ~= "function"
        or type(_G.UnitIsPlayer) ~= "function"
        or type(_G.UnitGUID) ~= "function" then
        return nil
    end

    local existsOK, exists = pcall(_G.UnitExists, unit)
    local playerOK, player = pcall(_G.UnitIsPlayer, unit)
    local guidOK, guid = pcall(_G.UnitGUID, unit)
    if not existsOK or not exists
        or not playerOK or not player
        or not guidOK or not validPlayerGUID(guid) then
        return nil
    end

    local confirmOK, confirmedGUID = pcall(_G.UnitGUID, unit)
    if not confirmOK or confirmedGUID ~= guid then
        return nil
    end
    return unit, guid
end

local function isLocalGUID(guid)
    if type(_G.UnitGUID) ~= "function" then
        return false
    end
    local ok, playerGUID = pcall(_G.UnitGUID, "player")
    return ok and playerGUID == guid
end

-- One reused table. This used to allocate a fresh eight-field table on every
-- call, and the Mainline poll calls it once per frame -- in an add-on whose
-- stated rule is a zero-allocation tooltip pipeline. Same data, no garbage.
--
-- The contract is that callers consume it SYNCHRONOUSLY: nothing here is
-- retained past the call. The fields that outlive a call are copied into the
-- binding as scalars, and source.revision / source.result are read during the
-- render that immediately follows.
local sourceState = {
    source = nil,
    state = nil,
    generation = 0,
    revisionID = nil,
    revision = nil,
    result = nil,
}

local function readSource(guid)
    if isLocalGUID(guid) then
        local entry = Scanner.GetCurrent()
        if type(entry) ~= "table" then
            sourceState.source = "local"
            sourceState.state = "unavailable"
            sourceState.generation = 0
            sourceState.revisionID = nil
            sourceState.revision = nil
            sourceState.result = nil
            return sourceState
        end
        local complete = entry.status == "complete"
            and type(entry.revision) == "table"
            and type(entry.result) == "table"
        sourceState.source = "local"
        sourceState.state = entry.status or "unavailable"
        sourceState.generation = entry.generation or 0
        sourceState.revisionID = complete and entry.generation or nil
        sourceState.revision = complete and entry.revision or nil
        sourceState.result = complete and entry.result or nil
        return sourceState
    end

    local entry = Cache.Get(guid)
    if type(entry) ~= "table" then
        sourceState.source = "remote"
        sourceState.state = "unavailable"
        sourceState.generation = 0
        sourceState.revisionID = nil
        sourceState.revision = nil
        sourceState.result = nil
        return sourceState
    end
    local complete = entry.state == "complete"
        and type(entry.revision) == "table"
        and type(entry.result) == "table"
    sourceState.source = "remote"
    sourceState.state = entry.state or "unavailable"
    sourceState.generation = entry.generation or 0
    sourceState.revisionID = complete and entry.revisionID or nil
    sourceState.revision = complete and entry.revision or nil
    sourceState.result = complete and entry.result or nil
    return sourceState
end

local function completeMetric(metrics, name)
    local metric = type(metrics) == "table" and metrics[name] or nil
    if type(metric) == "table" and metric.status == "complete" then
        return metric.value, metric
    end
    return nil, metric
end

local function displayNumber(value)
    if type(value) ~= "number" then
        return nil
    end
    if value % 1 == 0 then
        return string.format("%d", value)
    end
    return string.format("%.2f", value)
end

local function signedNumber(value)
    local displayed = displayNumber(value)
    if not displayed then
        return nil
    end
    if value > 0 then
        return "+" .. displayed
    end
    return displayed
end

local function colorText(text, red, green, blue)
    if type(red) ~= "number"
        or type(green) ~= "number"
        or type(blue) ~= "number" then
        return text
    end
    local r = math.floor(math.max(0, math.min(1, red)) * 255 + 0.5)
    local g = math.floor(math.max(0, math.min(1, green)) * 255 + 0.5)
    local b = math.floor(math.max(0, math.min(1, blue)) * 255 + 0.5)
    return string.format("|cff%02x%02x%02x%s|r", r, g, b, text)
end

local function labelText(text)
    return colorText(text, BRAND_RED, BRAND_GREEN, BRAND_BLUE)
end

local function validColor(red, green, blue)
    return type(red) == "number"
        and type(green) == "number"
        and type(blue) == "number"
        and red == red and green == green and blue == blue
        and red >= 0 and red <= 1
        and green >= 0 and green <= 1
        and blue >= 0 and blue <= 1
end

local function playerClassColor(unit)
    if type(_G.UnitClass) == "function" then
        local ok, _, classToken = pcall(_G.UnitClass, unit)
        if ok and type(classToken) == "string" then
            -- The CHAIN lives in Core (Core.GetClassColor), so the tooltip,
            -- the character/inspect frame and the leaderboard row cannot drift
            -- apart. What stays here is this surface's own two rules: the
            -- colour must be three finite numbers in 0..1 (an out-of-range
            -- community colour is refused, not painted), and the fallback is
            -- neutral grey.
            --
            -- Core owns WHERE a colour comes from; this surface owns whether
            -- it is acceptable and what to draw when nothing is.
            local core = namespace.Core
            if type(core) == "table"
                and type(core.GetClassColor) == "function" then
                local red, green, blue = core.GetClassColor(classToken, {
                    accept = validColor,
                })
                if validColor(red, green, blue) then
                    return red, green, blue, classToken
                end
            end
            return NEUTRAL_RED, NEUTRAL_GREEN, NEUTRAL_BLUE, classToken
        end
    end
    return NEUTRAL_RED, NEUTRAL_GREEN, NEUTRAL_BLUE, "unknown"
end

local function currentText(value, label)
    local displayed = displayNumber(value)
    if not displayed then
        return nil
    end
    local red, green, blue
    if type(Adapter.GetCurrentScoreColor) == "function" then
        local ok, r, g, b = pcall(Adapter.GetCurrentScoreColor, value)
        if ok then
            red, green, blue = r, g, b
        end
    end
    if not validColor(red, green, blue) then
        red, green, blue = NEUTRAL_RED, NEUTRAL_GREEN, NEUTRAL_BLUE
    end
    local valueText = colorText(displayed, red, green, blue)
    return labelText(label or "Current GS") .. " " .. valueText
end

local function readLevel(revision)
    local cell = type(revision) == "table" and revision.level or nil
    if type(cell) == "table"
        and cell.status == "complete"
        and type(cell.value) == "number" then
        return cell.value
    end
    return nil
end

-- Is the level-70 rule in force?
--
-- ONE source of truth: the same accessor the scorer is handed
-- (Core.GetEnhancementPolicy). The render gate used to read the settings
-- table directly while the scorer read a policy, which is how the two could
-- disagree -- the scorer restricted the metrics to level 70 while the render
-- gate believed the user had switched the restriction off, and the three
-- metrics then read "Unavailable" instead of showing a value.
local function level70RestrictionEnabled()
    local core = namespace.Core
    if type(core) == "table" and type(core.GetEnhancementPolicy) == "function" then
        local ok, policy = pcall(core.GetEnhancementPolicy)
        if ok and type(policy) == "table"
            and type(policy.restrictEnhancementMetricsToLevel70) == "boolean" then
            return policy.restrictEnhancementMetricsToLevel70
        end
    end
    return settings
        and settings.tooltip
        and settings.tooltip.restrictEnhancementMetricsToLevel70 == true
end

local function enhancementMetricsSuppressed(revision)
    if not level70RestrictionEnabled() then
        return false
    end
    return readLevel(revision) ~= 70
end

local function completionParts(metrics)
    local value, metric = completeMetric(metrics, "completion")
    if type(value) ~= "table"
        or type(value.opportunities) ~= "number"
        or value.opportunities <= 0
        or type(value.displayPercent) ~= "number"
        or type(value.ratio) ~= "number" then
        return nil, metric
    end
    return {
        detailedText = string.format(
            "%d%% (%d/%d)",
            value.displayPercent,
            value.filled,
            value.opportunities
        ),
        compactText = string.format("%d%%", value.displayPercent),
        ratio = value.ratio,
    }, metric
end

local function completionColor(ratio)
    if not (settings
        and settings.tooltip
        and settings.tooltip.warningColors == true) then
        return NEUTRAL_RED, NEUTRAL_GREEN, NEUTRAL_BLUE
    end
    if ratio == 1 then
        return 0.2, 1, 0.2
    end
    if ratio >= 0.9 then
        return 1, 1, 0.2
    end
    if ratio >= 0.7 then
        return 1, 0.55, 0.1
    end
    return 1, 0.2, 0.2
end

local function metricReason(metric)
    if type(metric) ~= "table" or metric.status == "complete" then
        return nil
    end
    if type(metric.reason) == "string"
        and string.match(metric.reason, "^[a-z0-9%-]+$") then
        return metric.reason
    end
    return "unavailable"
end

local function completeItemID(revision, slotID)
    local slot = type(revision) == "table"
        and type(revision.slots) == "table"
        and revision.slots[slotID]
        or nil
    local cell = type(slot) == "table" and slot.itemID or nil
    local value = type(cell) == "table" and cell.status == "complete" and cell.value or nil
    if type(value) == "number" and value > 0 and value % 1 == 0 then
        return value
    end
    return nil
end

local function cellMatchesBlocker(cell, label, status, reason)
    if type(cell) ~= "table" then
        return status == "unknown" and reason == label .. "-missing"
    end
    if cell.status == "complete" then
        return false
    end
    return cell.status == status and (cell.reason or label) == reason
end

local function revisionWideBlocker(revision, status, reason)
    if type(revision) ~= "table" then
        return true
    end
    if cellMatchesBlocker(revision.classToken, "class-token", status, reason)
        or cellMatchesBlocker(revision.level, "player-level", status, reason)
        or cellMatchesBlocker(
            revision.socketCapability,
            "socket-capability",
            status,
            reason
        ) then
        return true
    end
    local socketCapability = revision.socketCapability
    return type(socketCapability) == "table"
        and socketCapability.status == "complete"
        and socketCapability.value == false
        and status == "unavailable"
        and reason == "socket-capability"
end

local function findItemBlocker(revision, result, status, reason)
    if revisionWideBlocker(revision, status, reason) then
        return nil, nil
    end
    local items = type(result) == "table" and result.items or nil
    for _, slotID in ipairs(REQUIRED_SLOTS) do
        local item = type(items) == "table" and items[slotID] or nil
        if type(item) == "table" and item.state == "occupied" then
            for _, field in ipairs({
                "potentialDelta", "completion", "missingEnchant",
                "emptyScoreBearingSockets",
            }) do
                local metric = item[field]
                if type(metric) == "table"
                    and metric.status == status
                    and metricReason(metric) == reason then
                    return slotID, completeItemID(revision, slotID)
                end
            end
        end
    end
    return nil, nil
end

local function updateEnhancementStatus(scope, revision, result, suppressed)
    local metrics = type(result) == "table" and result.metrics or nil
    if suppressed then
        setEnhancementStatus({
            status = "suppressed",
            reason = "level-policy",
            scope = scope,
        })
        return
    end
    for _, name in ipairs({ "potentialGS", "delta", "completion" }) do
        local metric = type(metrics) == "table" and metrics[name] or nil
        local reason = metricReason(metric)
        if reason then
            local slotID, itemID
            if scope == "remote" then
                slotID, itemID = findItemBlocker(
                    revision,
                    result,
                    type(metric) == "table" and metric.status or "missing",
                    reason
                )
            end
            setEnhancementStatus({
                status = "unavailable",
                reason = reason,
                scope = scope,
                slotID = slotID,
                itemID = itemID,
            })
            return
        end
    end
    setEnhancementStatus({
        status = "complete",
        reason = nil,
        scope = scope,
    })
end

local function inlineMetric(label, value, red, green, blue)
    return labelText(label) .. " " .. colorText(value, red, green, blue)
end

local function serverRankEnabled()
    if type(settings) == "table" and type(settings.tooltip) == "table" then
        if settings.tooltip.show_server_rank == false
            or settings.tooltip.showServerRank == false then
            return false
        end
    end
    local g = _G
    local legacyCfg = rawget(g, "TacoTipExtrasConfig")
    if type(legacyCfg) == "table" and legacyCfg.show_server_rank == false then
        return false
    end
    return true
end

local function getRankRow(guid, unit, mode)
    if not serverRankEnabled() then
        return nil
    end
    local rankDB = namespace.RankDB
    if type(rankDB) ~= "table" or type(rankDB.GetPlayerRank) ~= "function" then
        return nil
    end
    local targetGUID = guid
    if not targetGUID and unit then
        local g = _G
        local uGUID = rawget(g, "UnitGUID")
        if type(uGUID) == "function" then
            local ok, id = pcall(uGUID, unit)
            if ok and type(id) == "string" then
                targetGUID = id
            end
        end
    end
    if not targetGUID then
        return nil
    end

    local overall, _, classRank, totalRanked = rankDB.GetPlayerRank(targetGUID)
    if not overall then
        return nil
    end

    local className
    local classFile
    local g = _G
    local uClass = rawget(g, "UnitClass")
    if type(uClass) == "function" and unit then
        local ok, locClass, token = pcall(uClass, unit)
        if ok then
            if type(locClass) == "string" and locClass ~= "" then
                className = locClass
            end
            if type(token) == "string" then
                classFile = token
            end
        end
    end

    -- Both numbers carry the RANKING scale, resolved through the same
    -- Scoring.RankColor the leaderboard's `#` column paints from, so "#1" reads
    -- gold here exactly as it does in the browser. Reading the raw percentile
    -- bands directly made the best possible rank render purple, because purple is
    -- the top of the QUALITY scale, not the top of a standing.
    local scoring = namespace.Scoring
    local function rankColor(rank, total)
        if scoring and type(scoring.RankColor) == "function" then
            local r, gg, b = scoring.RankColor(rank, total)
            if r and gg and b then
                return r, gg, b
            end
        end
        return NEUTRAL_RED, NEUTRAL_GREEN, NEUTRAL_BLUE
    end    local orr, org, orb = rankColor(overall, totalRanked)
    local crr, crg, crb = rankColor(classRank or overall, totalRanked)
    local classRed, classGreen, classBlue = playerClassColor(unit)

    local text
    if classRank and className then
        -- [#2 Warrior] -- square brackets, class rank and name inside, overall
        -- rank outside. Every mode uses the short "GS Rank:" label. The
        -- brackets stay WHITE so they read as punctuation instead of borrowing
        -- whichever number sits next to them. In Compact the class NAME is
        -- replaced by the player's normal 14px class icon, with no class-colour
        -- tint; if the client cannot resolve the class atlas (or GetClassAtlas
        -- is absent) the line degrades to the class name. Detailed and Minimal
        -- keep the class name in its class colour.
        local classDisplay = className
        local classColored = true
        if mode == "Compact" then
            local getAtlas = rawget(g, "GetClassAtlas")
            if type(getAtlas) == "function"
                and type(classFile) == "string" and classFile ~= "" then
                local ok, atlas = pcall(getAtlas, classFile)
                if ok and type(atlas) == "string" and atlas ~= "" then
                    classDisplay = "|A:" .. atlas .. ":14:14|a"
                    classColored = false
                end
            end
        end
        text = labelText(L["TOOLTIP_LABEL_RANK"]) .. " "
            .. colorText("#" .. tostring(overall), orr, org, orb) .. " "
            .. colorText("[", 1, 1, 1)
            .. colorText("#" .. tostring(classRank), crr, crg, crb) .. " "
            .. (classColored
                and colorText(classDisplay, classRed, classGreen, classBlue)
                or classDisplay)
            .. colorText("]", 1, 1, 1)
    else
        text = labelText(L["TOOLTIP_LABEL_RANK"]) .. " "
            .. colorText("#" .. tostring(overall), orr, org, orb)
    end
    return { text = text }
end

-- Stage 5 trailing tooltip line (scope deliberately narrow: one optional
-- muted line behind the existing content, reusing the row-tooltip muted
-- pattern -- never a redesign of the unit tooltip):
--
--   Freshness: "Rank synced <relative>" -- only when the displayed rank
--      row is older than the session (mirrors the W7 tick data, no new
--      source). A fresh row states nothing; no rank row renders the line.
--
-- The input feeds through captureRenderInputs, so the change gate covers
-- it: a line whose input didn't change never repaints.

local function tooltipNow()
    local clock = rawget(_G, "GetServerTime")
    if type(clock) == "function" then
        local okClock, nowClock = pcall(clock)
        if okClock and type(nowClock) == "number" then
            return nowClock
        end
    end
    return 0
end

local function formatRankAge(timestamp, now)
    if not timestamp or timestamp <= 0 then return L["TIME_UNKNOWN"] or "Unknown" end
    local diff = now - timestamp
    if diff < 60 then return L["TIME_JUST_NOW"] or "Just now" end
    if diff < 3600 then
        return string.format(L["TIME_MIN_AGO"] or "%d min ago", math.floor(diff / 60))
    end
    if diff < 86400 then
        return string.format(L["TIME_HOUR_AGO"] or "%d hr ago", math.floor(diff / 3600))
    end
    local days = math.floor(diff / 86400)
    if days == 1 then return L["TIME_YESTERDAY"] or "Yesterday" end
    return string.format(L["TIME_DAY_AGO"] or "%d d ago", days)
end

local function rankLineInputs(guid)
    local inputs = { timestamp = 0 }
    if type(guid) ~= "string" or guid == "" then
        return inputs
    end
    local ranks = namespace.RankDB
    if type(ranks) ~= "table" then
        return inputs
    end
    if type(ranks.GetRecord) == "function" then
        local okRec, record = pcall(ranks.GetRecord, guid)
        if okRec and type(record) == "table" then
            inputs.timestamp = tonumber(record.timestamp) or 0
        elseif not okRec then
            noteRankRecordError(record)
        end
    end
    return inputs
end

-- Debug accessor for the Adapter M-NEW1 score-colour fallback counters
-- (hunter M-NEW1, debug ONLY). Read-only: reports what the adapter counted,
-- changes nothing displayed. Nil adapter state reads as zero/unknown.
function Tooltips.GetDebugState()
    local adapterState = nil
    if (Adapter and type(Adapter.GetDebugState) == "function") then
        local ok, state = pcall(Adapter.GetDebugState)
        if (ok and type(state) == "table") then
            adapterState = state
        end
    end
    return {
        scoreColorFallbacks = (adapterState and adapterState.scoreColorFallbacks) or 0,
        lastScoreColorReason = (adapterState and adapterState.lastScoreColorReason) or nil,
        rankRecordErrors = rankRecordErrors,
        lastRankRecordError = lastRankRecordError,
    }
end

-- The Stage-5 trailing line for one GUID, exposed for the harness: the
-- only new tooltip surface, pinnable without driving a full unit render.
function Tooltips.GetRankExtraLines(guid)
    local lines = {}
    if type(guid) ~= "string" or guid == "" then
        return lines
    end
    local ranks = namespace.RankDB
    if type(ranks) ~= "table" then
        return lines
    end
    local record = nil
    if type(ranks.GetRecord) == "function" then
        local okRec, rec = pcall(ranks.GetRecord, guid)
        if okRec and type(rec) == "table" then
            record = rec
        elseif not okRec then
            noteRankRecordError(rec)
        end
    end
    if type(record) ~= "table" then
        return lines
    end
    local ts = tonumber(record.timestamp) or 0
    if tooltipSessionStart > 0 and ts > 0 and ts < tooltipSessionStart then
        lines[#lines + 1] = {
            text = string.format(L["LB_TIP_RANK_SYNCED"] or "Rank synced: %s",
                formatRankAge(ts, tooltipNow())),
            red = NEUTRAL_RED, green = NEUTRAL_GREEN, blue = NEUTRAL_BLUE,
        }
    end
    return lines
end

local function makeRows(mode, revision, result, unit, scope, guid)
    local rows = {}
    local metrics = result.metrics
    local suppressed = enhancementMetricsSuppressed(revision)
    local classRed, classGreen, classBlue = playerClassColor(unit)
    local current, currentMetric = completeMetric(metrics, "gearScore")
    local iLvlRed, iLvlGreen, iLvlBlue
    if type(Adapter.GetEquipmentScoreColor) == "function" then
        local ok, r, g, b = pcall(Adapter.GetEquipmentScoreColor, current)
        if ok then
            iLvlRed, iLvlGreen, iLvlBlue = r, g, b
        end
    end
    if not validColor(iLvlRed, iLvlGreen, iLvlBlue) then
        iLvlRed, iLvlGreen, iLvlBlue = NEUTRAL_RED, NEUTRAL_GREEN, NEUTRAL_BLUE
    end
    local base, baseMetric = completeMetric(metrics, "baseGS")
    local potential, potentialMetric = completeMetric(metrics, "potentialGS")
    local delta, deltaMetric = completeMetric(metrics, "delta")
    local average, averageMetric = completeMetric(metrics, "averageItemLevel")
    local averageDisplay = type(average) == "table" and average.display or nil
    local completion, completionMetric = completionParts(metrics)
    updateEnhancementStatus(scope, revision, result, suppressed)

    if mode == "Minimal" then
        local parts = {}
        if fieldEnabled("gearScore") and type(current) == "number" then
            parts[#parts + 1] = currentText(current, "GS")
        end
        if fieldEnabled("averageItemLevel") and type(averageDisplay) == "number" then
            parts[#parts + 1] = inlineMetric(
                "iLvl",
                displayNumber(averageDisplay),
                iLvlRed,
                iLvlGreen,
                iLvlBlue
            )
        end
        if #parts > 0 then
            rows[1] = { text = table.concat(parts, "   ") }
        end
        local rankRow = getRankRow(guid, unit, mode)
        if rankRow then
            rows[#rows + 1] = rankRow
        end
        for _, extraLine in ipairs(Tooltips.GetRankExtraLines(guid)) do
            rows[#rows + 1] = extraLine
        end
        return rows
    end

    if mode == "Compact" then
        local primary = {}
        if fieldEnabled("gearScore") and type(current) == "number" then
            primary[#primary + 1] = currentText(current, "GS")
        end
        if fieldEnabled("averageItemLevel") and type(averageDisplay) == "number" then
            primary[#primary + 1] = inlineMetric(
                "iLvl",
                displayNumber(averageDisplay),
                iLvlRed,
                iLvlGreen,
                iLvlBlue
            )
        end
        if #primary > 0 then
            rows[#rows + 1] = { text = table.concat(primary, "   ") }
        end

        local secondary = {}
        if not suppressed
            and fieldEnabled("gearScore")
            and fieldEnabled("potentialGS")
            and fieldEnabled("delta")
            and type(current) == "number"
            and type(potential) == "number"
            and type(delta) == "number"
            and delta > 0 then
            secondary[#secondary + 1] = inlineMetric(
                COMPACT_DELTA_LABEL,
                signedNumber(delta),
                POSITIVE_RED,
                POSITIVE_GREEN,
                POSITIVE_BLUE
            )
        end
        if not suppressed and fieldEnabled("completion") and completion then
            secondary[#secondary + 1] = inlineMetric(
                L["COMPLETE"],
                completion.compactText,
                completionColor(completion.ratio)
            )
        end
        if #secondary > 0 then
            rows[#rows + 1] = { text = table.concat(secondary, "   ") }
        end
        local rankRow = getRankRow(guid, unit, mode)
        if rankRow then
            rows[#rows + 1] = rankRow
        end
        for _, extraLine in ipairs(Tooltips.GetRankExtraLines(guid)) do
            rows[#rows + 1] = extraLine
        end
        return rows
    end

    local unavailableCounts = {}
    local enhancementFields = {
        { name = "potentialGS", metric = potentialMetric },
        { name = "delta", metric = deltaMetric },
        { name = "completion", metric = completionMetric },
    }
    if not suppressed then
        for _, field in ipairs(enhancementFields) do
            if fieldEnabled(field.name) then
                local reason = metricReason(field.metric)
                if reason then
                    unavailableCounts[reason] = (unavailableCounts[reason] or 0) + 1
                end
            end
        end
    end
    local sharedReason
    for reason, count in pairs(unavailableCounts) do
        if count >= 2 then
            sharedReason = reason
            break
        end
    end

    local function addMetric(label, field, value, metric, formatter, red, green, blue)
        if not fieldEnabled(field) then
            return
        end
        if value ~= nil then
            local text = formatter and formatter(value) or displayNumber(value)
            rows[#rows + 1] = {
                text = inlineMetric(label .. ":", text, red, green, blue),
            }
        elseif type(metric) == "table" then
            rows[#rows + 1] = {
                text = labelText(label .. ":") .. " "
                    .. colorText(
                        L["UNAVAILABLE"],
                        NEUTRAL_RED,
                        NEUTRAL_GREEN,
                        NEUTRAL_BLUE
                    ),
            }
        end
    end

    local analysisAdded = false
    local function addUnavailableAnalysis()
        if analysisAdded then
            return
        end
        analysisAdded = true
        rows[#rows + 1] = {
            text = labelText(L["TOOLTIP_LABEL_ENHANCEMENT"]) .. " "
                .. colorText(
                    L["UNAVAILABLE"],
                    NEUTRAL_RED,
                    NEUTRAL_GREEN,
                    NEUTRAL_BLUE
                ),
        }
    end

    if fieldEnabled("gearScore") and type(current) == "number" then
        rows[#rows + 1] = { text = currentText(current, "Current GS:") }
    elseif fieldEnabled("gearScore") and type(currentMetric) == "table" then
        addMetric(
            L["CURRENT_GS"],
            "gearScore",
            nil,
            currentMetric,
            nil,
            NEUTRAL_RED,
            NEUTRAL_GREEN,
            NEUTRAL_BLUE
        )
    end
    if not suppressed then
        if fieldEnabled("potentialGS") then
            if potential ~= nil then
                addMetric(
                    L["POTENTIAL_GS"],
                    "potentialGS",
                    potential,
                    potentialMetric,
                    nil,
                    GOLD_RED,
                    GOLD_GREEN,
                    GOLD_BLUE
                )
            elseif sharedReason and metricReason(potentialMetric) == sharedReason then
                addUnavailableAnalysis()
            else
                addMetric(
                    L["POTENTIAL_GS"],
                    "potentialGS",
                    nil,
                    potentialMetric,
                    nil,
                    NEUTRAL_RED,
                    NEUTRAL_GREEN,
                    NEUTRAL_BLUE
                )
            end
        end

        if fieldEnabled("delta") then
            local potentialUnavailable = fieldEnabled("potentialGS")
                and potential == nil
                and metricReason(potentialMetric) ~= nil
            if delta ~= nil then
                local deltaRed, deltaGreen, deltaBlue = NEUTRAL_RED,
                    NEUTRAL_GREEN,
                    NEUTRAL_BLUE
                if delta > 0 then
                    deltaRed, deltaGreen, deltaBlue = POSITIVE_RED,
                        POSITIVE_GREEN,
                        POSITIVE_BLUE
                end
                addMetric(
                    L["DELTA"],
                    "delta",
                    delta,
                    deltaMetric,
                    signedNumber,
                    deltaRed,
                    deltaGreen,
                    deltaBlue
                )
            elseif sharedReason and metricReason(deltaMetric) == sharedReason then
                addUnavailableAnalysis()
            elseif not potentialUnavailable then
                addMetric(
                    L["DELTA"],
                    "delta",
                    nil,
                    deltaMetric,
                    signedNumber,
                    NEUTRAL_RED,
                    NEUTRAL_GREEN,
                    NEUTRAL_BLUE
                )
            end
        end
    end
    if not suppressed and fieldEnabled("completion") then
        if completion then
            rows[#rows + 1] = {
                text = inlineMetric(
                    L["COMPLETION"] .. ":",
                    completion.detailedText,
                    completionColor(completion.ratio)
                ),
            }
        elseif sharedReason and metricReason(completionMetric) == sharedReason then
            addUnavailableAnalysis()
        elseif type(completionMetric) == "table"
            and completionMetric.status == "complete" then
            rows[#rows + 1] = {
                text = labelText(L["TOOLTIP_LABEL_COMPLETION"]) .. " "
                    .. colorText(
                        L["GEAR_NO_OPPORTUNITIES"],
                        NEUTRAL_RED,
                        NEUTRAL_GREEN,
                        NEUTRAL_BLUE
                    ),
            }
        elseif type(completionMetric) == "table" then
            addMetric(
                L["COMPLETION"],
                "completion",
                nil,
                completionMetric,
                nil,
                NEUTRAL_RED,
                NEUTRAL_GREEN,
                NEUTRAL_BLUE
            )
        end
    end
    addMetric(
        L["AVERAGE_ILVL"],
        "averageItemLevel",
        averageDisplay,
        averageMetric,
        nil,
        iLvlRed,
        iLvlGreen,
        iLvlBlue
    )
    addMetric(
        L["UNENHANCED_GS"],
        "baseGS",
        base,
        baseMetric,
        nil,
        classRed,
        classGreen,
        classBlue
    )
    local rankRow = getRankRow(guid, unit, mode)
    if rankRow then
        rows[#rows + 1] = rankRow
    end
    for _, extraLine in ipairs(Tooltips.GetRankExtraLines(guid)) do
        rows[#rows + 1] = extraLine
    end
    return rows
end

local function numberOfLines(target)
    if type(target.NumLines) ~= "function" then
        return nil
    end
    local ok, value = pcall(target.NumLines, target)
    if ok and type(value) == "number" then
        return value
    end
    return nil
end

local function addRows(target, rows)
    if type(target.AddLine) ~= "function" then
        return false
    end
    for _, row in ipairs(rows) do
        target:AddLine(
            row.text,
            row.red or 1,
            row.green or 1,
            row.blue or 1,
            false
        )
    end
    return true
end

-- Every input renderPlayerTooltip's output depends on, captured as scalar
-- fields on the binding.
--
-- This used to be one string: makeSignature built an eighteen-element table
-- and table.concat'd it on every call. Under the Mainline poll that meant a
-- fresh ~200-byte string PER FRAME, forever, on a tooltip the user was merely
-- looking at -- in the one add-on in this repo whose stated rule is a
-- zero-allocation tooltip pipeline. Comparing stored scalars answers the same
-- question, and answers it with no allocation and no early return that has to
-- be reconstructed after the fact.
local function captureRenderInputs(into, guid, source, mode, unit)
    local classRed, classGreen, classBlue, classToken = playerClassColor(unit)
    into.guid = guid
    into.source = source.source
    into.state = source.state
    into.generation = source.generation
    into.revisionID = source.revisionID
    into.mode = mode
    into.shiftDown = shiftIsDown()
    into.classToken = classToken
    into.classRed = classRed
    into.classGreen = classGreen
    into.classBlue = classBlue
    into.fieldGearScore = fieldEnabled("gearScore")
    into.fieldBaseGS = fieldEnabled("baseGS")
    into.fieldPotentialGS = fieldEnabled("potentialGS")
    into.fieldDelta = fieldEnabled("delta")
    into.fieldAverageItemLevel = fieldEnabled("averageItemLevel")
    into.fieldCompletion = fieldEnabled("completion")
    local t = settings.tooltip or {}
    into.warningColors = t.warningColors == true
    into.restrictToLevel70 = level70RestrictionEnabled()
    into.showServerRank = serverRankEnabled()
    -- Stage 5 trailing line: the rank timestamp.
    -- Same input the line renders from, so a repaint only happens when the
    -- line itself could have changed.
    local lineInputs = rankLineInputs(guid)
    into.rankTimestamp = lineInputs.timestamp
end

local function renderInputsUnchanged(current, target, guid, source, mode, unit)
    if current.tooltip ~= target
        or current.unit ~= unit
        or current.guid ~= guid
        or current.source ~= source.source
        or current.state ~= source.state
        or current.generation ~= source.generation
        or current.revisionID ~= source.revisionID
        or current.mode ~= mode then
        return false
    end

    local classRed, classGreen, classBlue, classToken = playerClassColor(unit)
    local fresh = rankLineInputs(guid)
    return current.shiftDown == shiftIsDown()
        and current.classToken == classToken
        and current.classRed == classRed
        and current.classGreen == classGreen
        and current.classBlue == classBlue
        and current.fieldGearScore == fieldEnabled("gearScore")
        and current.fieldBaseGS == fieldEnabled("baseGS")
        and current.fieldPotentialGS == fieldEnabled("potentialGS")
        and current.fieldDelta == fieldEnabled("delta")
        and current.fieldAverageItemLevel == fieldEnabled("averageItemLevel")
        and current.fieldCompletion == fieldEnabled("completion")
        and current.warningColors == (settings.tooltip.warningColors == true)
        and current.restrictToLevel70 == level70RestrictionEnabled()
        and current.showServerRank == serverRankEnabled()
        and current.rankTimestamp == fresh.timestamp
end

-- The render BODY. It owns no latch: the wrapper below owns that, so the
-- latch cannot be stranded by a raise anywhere in here.
local function renderPlayerTooltipBody(target)
    local unit, guid = validatePlayerUnit(target)
    if not unit or not Adapter.IsTooltipSurfaceActive() then
        clearBinding()
        return false
    end

    local source = readSource(guid)
    local mode = effectiveMode()

    -- The change gate. Every comparison below is a read of a stored scalar, so
    -- a tick on which nothing happened costs nothing: no allocation, no string
    -- building, no tooltip mutation. This is what makes driving the render from
    -- a per-frame script safe rather than a per-frame rewrite.
    if binding and renderInputsUnchanged(binding, target, guid, source, mode, unit) then
        local currentLines = numberOfLines(target)
        if currentLines ~= nil and currentLines == binding.lineCountAfter then
            return true
        end
    end

    renderAttempts = renderAttempts + 1
    resetEnhancementStatus()
    local candidate = { tooltip = target, unit = unit }
    captureRenderInputs(candidate, guid, source, mode, unit)
    binding = candidate

    local rendered = false
    if mode ~= "Disabled"
        and source.state == "complete"
        and type(source.revision) == "table"
        and type(source.result) == "table" then
        local confirmOK, currentGUID = pcall(_G.UnitGUID, unit)
        if not confirmOK or currentGUID ~= guid then
            clearBinding()
            return false
        end
        rendered = addRows(
            target,
            makeRows(mode, source.revision, source.result, unit, source.source, guid)
        )
    elseif mode ~= "Disabled" then
        setEnhancementStatus({
            status = tostring(source.state or "unavailable"),
            reason = "source-not-complete",
            scope = source.source,
        })
    end
    binding.lineCountAfter = numberOfLines(target)
    if rendered then
        renderRows = renderRows + 1
    end
    return rendered
end

-- The render ENTRY. The latch is taken here and released here, so the
-- surface cannot be wedged by a raise: the xpcall handler records the
-- failure, the latch is cleared on the way out, and the next render is
-- allowed to run.
--
-- The failing render also drops its binding: a half-built binding would make
-- the change gate believe the tooltip is already up to date, so the surface
-- would stay blank for a DIFFERENT reason. The poll is deliberately NOT
-- disarmed -- the tooltip is still on screen, and the point of the boundary
-- is that the surface can render again on the very next tick.
local function renderPlayerTooltip(target)
    if not initialized or rendering then
        return false
    end
    rendering = true
    local ok, rendered = xpcall(function()
        return renderPlayerTooltipBody(target)
    end, noteRenderError)
    rendering = false
    if not ok then
        binding = nil
        resetEnhancementStatus()
        return false
    end
    return rendered
end

local function visibleBindingIsCurrent(candidate)
    candidate = candidate or binding
    if not candidate or candidate.tooltip ~= tooltip then
        return false
    end
    if type(tooltip.IsShown) == "function" then
        local ok, shown = pcall(tooltip.IsShown, tooltip)
        if not ok or not shown then
            return false
        end
    end
    local unit, guid = validatePlayerUnit(tooltip)
    return unit == candidate.unit and guid == candidate.guid
end

local function refreshBinding()
    local current = binding
    if refreshing or rendering or not visibleBindingIsCurrent(current) then
        if current and not visibleBindingIsCurrent(current) then
            clearBinding()
        end
        return false
    end
    if type(tooltip.SetUnit) ~= "function" then
        return false
    end

    refreshing = true
    local ok = pcall(tooltip.SetUnit, tooltip, current.unit)
    refreshing = false
    if not ok then
        clearBinding()
    end
    return ok
end

local function localPublished(state)
    if not binding or binding.source ~= "local" or type(state) ~= "table" then
        return
    end
    local generation = state.generation or 0
    if generation < binding.generation then
        return
    end
    local revisionID = state.status == "complete" and generation or nil
    if generation == binding.generation
        and state.status == binding.state
        and revisionID == binding.revisionID then
        return
    end
    refreshBinding()
end

local function remotePublished(guid, state)
    if not binding
        or binding.source ~= "remote"
        or binding.guid ~= guid
        or type(state) ~= "table" then
        return
    end
    local generation = state.generation or 0
    if generation < binding.generation then
        return
    end
    if generation == binding.generation
        and type(binding.revisionID) == "number"
        and type(state.revisionID) == "number"
        and state.revisionID < binding.revisionID then
        return
    end
    if generation == binding.generation
        and state.state == binding.state
        and state.revisionID == binding.revisionID then
        return
    end
    refreshBinding()
end

local function onTooltipSetUnit(target)
    renderPlayerTooltip(target)
end

local function onTooltipCleared()
    -- OnTooltipCleared, OnTooltipSetItem and (through clearBinding) OnHide all
    -- land here: a tooltip that is no longer showing this player must not keep
    -- a binding, and must not leave the poll armed.
    clearBinding()
end

-- Portable driver for the clients whose GameTooltip declares no
-- OnTooltipSetUnit (Mainline: Retail and WoW Forever). OnUpdate is declared on
-- all five clients, so it is the one hook point that exists everywhere.
--
-- Four properties this has to have, and how each is obtained:
--
--   1. IT MUST NOT RUN ON THE CLASSIC FAMILY AT ALL. pollEligible below is
--      computed from HasScript("OnTooltipSetUnit"), not from "the other hook
--      failed". Deciding it from unitHooked instead would let both drivers be
--      live whenever the Classic hook silently did not take, and then the same
--      render could be driven twice. From HasScript there is no such state.
--
--   2. IT MUST COST NOTHING WHEN IDLE. pollArmed gates everything past the
--      counter. A hidden or cleared tooltip disarms through OnHide /
--      OnTooltipCleared, both of which the Mainline GameTooltipTemplate
--      declares, so an idle tooltip costs one boolean test per tick and no
--      tooltip mutation at all.
--
--   3. IT MUST NOT READ LAYOUT-DEPENDENT STATE. This body reads GetUnit and
--      NumLines and writes through AddLine. It never reads GetPoint, GetLeft,
--      GetRight, GetWidth or GetHeight, and it never positions anything.
--      That matters because on Mainline
--      TooltipDataHandlerMixin:InternalProcessInfo runs ProcessLines and the
--      postcalls and only THEN calls self:Show(), so anything that fires
--      DURING a tooltip build sees an unlaid-out frame. This cannot happen
--      here from either end: OnUpdate does not run on a hidden frame, so the
--      tooltip is already shown by the time the first tick happens; and
--      HookScript chains this AFTER GameTooltip_OnUpdate, so every other
--      OnUpdate handler has had its turn before this body runs.
--
--   4. IT MUST BE IDEMPOTENT. renderPlayerTooltip's change gate compares
--      stored scalars, so a tick where nothing happened returns without
--      touching the tooltip.
local function onTooltipUpdatePoll(target)
    pollTicks = pollTicks + 1
    if not initialized or target ~= tooltip or not pollArmed then
        return
    end
    pollWorkTicks = pollWorkTicks + 1
    if type(target.IsShown) == "function" and not target:IsShown() then
        return
    end
    local unit = tooltipUnit(target)
    if not unit then
        return
    end
    renderPlayerTooltip(target)
end

local function onTooltipShow()
    pollArmed = true
end

function Tooltips.GetDriverState()
    return {
        mode = driverMode,
        pollArmed = pollArmed,
        initialized = initialized,
        bound = binding ~= nil,
        renders = renderAttempts,
        rows = renderRows,
        pollTicks = pollTicks,
        pollWorkTicks = pollWorkTicks,
        renderErrors = renderErrors,
        renderErrorsSuppressed = renderErrorsSuppressed,
        lastRenderError = lastRenderError,
        renderErrorRing = renderErrorRing,
    }
end

function Tooltips.Initialize(runtimeSettings)
    if initialized then
        return true
    end
    settings = runtimeSettings
    tooltip = _G.GameTooltip
    if type(tooltip) ~= "table" or type(tooltip.HookScript) ~= "function" then
        Adapter.SetTooltipSurfaceEnabled(false)
        return false
    end

    -- Every hook below is guarded by HasScript, and every guard is load
    -- critical rather than defensive.
    --
    -- HookScript raises "bad argument #2 to 'HookScript'" when the frame does
    -- not already declare that script, and the two FrameXML families disagree
    -- about which ones GameTooltip declares. Verified against the source, not
    -- inferred from a call-site grep. Extracted from the FULL Interface tree
    -- per branch (`git archive origin/<branch> Interface`), because a
    -- character-class git grep returns zero hits on origin/forever and would
    -- have reported the symbols as absent everywhere:
    --
    --   Classic family (Era / TBC Anniversary / Titanforge)   4 occurrences
    --     Blizzard_GameTooltip/Classic/GameTooltip.xml declares
    --     <OnTooltipSetUnit function="GameTooltip_OnTooltipSetUnit" /> (line
    --     22), <OnTooltipSetItem function="GameTooltip_OnTooltipSetItem" />
    --     (line 23), OnTooltipSetSpell, OnUpdate (line 33) and OnHide (25).
    --
    --   Mainline (WoW Forever / Retail)                        1 occurrence
    --     OnTooltipSetUnit and OnTooltipSetItem appear ONLY in
    --     Blizzard_SharedXML/UI.xsd, which is an XML SCHEMA listing the script
    --     names a frame may declare. Blizzard_GameTooltip/Mainline/
    --     GameTooltip.xml declares neither. That file's GameTooltipTemplate
    --     carries mixin="GameTooltipDataMixin" and declares OnLoad, OnHide,
    --     OnTooltipSetDefaultAnchor, OnTooltipCleared, OnEvent and OnSizeChanged;
    --     the non-virtual <GameTooltip name="GameTooltip"> adds OnShow and
    --     <OnUpdate function="GameTooltip_OnUpdate"/>.
    --
    -- This file used to hook OnTooltipSetUnit and OnTooltipSetItem
    -- unguarded, so it raised on two of the five supported clients. The raise
    -- escaped Core's ADDON_LOADED handler, which had no pcall, so every later
    -- step of initialize was skipped and the user lost the minimap button and
    -- the options category with no error message at all.
    --
    -- Guarding alone would leave the tooltip surface DEAD on Mainline, so
    -- there is a portable driver: OnUpdate is declared on all five clients and
    -- renderPlayerTooltip's change gate makes driving it from OnUpdate
    -- idempotent rather than a per-frame rewrite. That keeps the add-on
    -- working where the script does not exist, instead of merely stopping the
    -- crash.
    local SCRIPT_HANDLERS = {
        OnTooltipSetUnit = onTooltipSetUnit,
        OnTooltipSetItem = onTooltipCleared,
        OnTooltipCleared = onTooltipCleared,
        OnHide = onTooltipCleared,
    }

    -- Every handler installed on the SHARED GameTooltip runs contained.
    --
    -- Addon code inside a Blizzard frame's script chain taints that frame, and
    -- the taint reaches the game menu, where the Logout/Quit button -- whose
    -- callback is the engine function, so a reporter can only name it
    -- 'UNKNOWN()' -- is refused:
    --     [ADDON_ACTION_FORBIDDEN] AddOn 'TacoTip' tried to call the protected
    --     function 'UNKNOWN()'.
    -- `securecall` is the engine's own containment primitive and Blizzard uses
    -- it for exactly this shape (Blizzard_BuffFrame/BuffFrame.lua:991
    -- `securecall(self.UpdateDuration, self, self.timeLeft); -- Taint issue
    -- with SecondsToTimeAbbrev`). It is present on every supported client.
    local function contained(fn)
        -- The bounded body is a vararg function on purpose: it forwards the
        -- callback's arguments to `fn` unchanged. A plain closure cannot --
        -- `...` outside a vararg function is a compile error in the Lua 5.1
        -- WoW ships.
        local function bounded(...)
            -- The pcall is INSIDE the containment on purpose: `securecall`
            -- swallows a raise and returns nil, so a pcall outside it would
            -- report the callback as having succeeded and the error counter
            -- would never move. The reporter is the surface's own
            -- (noteRenderError): it counts, keeps the last message, and hands
            -- it to the client's error handler once per distinct message.
            local ok, err = pcall(fn, ...)
            if not ok then
                noteRenderError(err)
            end
        end
        return function(...)
            return Core.RunUntainted(bounded, ...)
        end
    end

    -- Ask ONCE which scripts this client declares. HasScript cannot change
    -- between this read and the hooks below, and the answer decides the poll,
    -- so it must not be re-derived per hook.
    local declares = {}
    for script in pairs(SCRIPT_HANDLERS) do
        declares[script] = type(tooltip.HasScript) ~= "function"
            or tooltip:HasScript(script)
    end
    declares.OnUpdate = type(tooltip.HasScript) ~= "function"
        or tooltip:HasScript("OnUpdate")
    declares.OnShow = type(tooltip.HasScript) ~= "function"
        or tooltip:HasScript("OnShow")

    local unitHooked = false
    for _, script in ipairs({
        "OnTooltipSetUnit", "OnTooltipSetItem", "OnTooltipCleared", "OnHide",
    }) do
        if declares[script] then
            local hooked = pcall(
                tooltip.HookScript, tooltip, script, contained(SCRIPT_HANDLERS[script])
            )
            if hooked and script == "OnTooltipSetUnit" then
                unitHooked = true
            end
        end
    end

    -- The poll is the fallback ONLY for a client whose GameTooltip does not
    -- declare OnTooltipSetUnit at all. See property 1 above.
    local pollHooked = false
    if not declares.OnTooltipSetUnit and declares.OnUpdate then
        pollHooked = pcall(
            tooltip.HookScript, tooltip, "OnUpdate", contained(onTooltipUpdatePoll)
        )
    end

    if not unitHooked and not pollHooked then
        -- Neither hook point exists. Refuse the surface rather than pretend:
        -- Initialize returning false is what Core reports on, and the adapter
        -- stays released so TacoTip's own GearScore is left alone.
        Adapter.SetTooltipSurfaceEnabled(false)
        initialized = false
        driverMode = "none"
        pollArmed = false
        return false
    end

    driverMode = unitHooked and "unit-hook" or "poll"
    if driverMode == "poll" then
        -- Arm on OnShow so an idle tooltip is not polled at all. If OnShow
        -- cannot be hooked, arm now instead and let the poll's own IsShown
        -- test decide: more work per tick, same result.
        if declares.OnShow
            and pcall(tooltip.HookScript, tooltip, "OnShow", contained(onTooltipShow)) then
            pollArmed = false
        else
            pollArmed = true
        end
    end

    initialized = true

    -- Stage 5 session clock for the freshness line (mirrors the browser's W7
    -- session start). Guarded like every other clock read in this file.
    tooltipSessionStart = tooltipNow()

    localListener = localPublished
    remoteListener = remotePublished
    Scanner.Subscribe(localListener)
    Cache.Subscribe(remoteListener)

    if type(_G.TooltipDataProcessor) == "table"
        and type(_G.TooltipDataProcessor.AddTooltipPostCall) == "function"
        and type(_G.Enum) == "table"
        and type(_G.Enum.TooltipDataType) == "table"
        and _G.Enum.TooltipDataType.Unit then
        pcall(
            _G.TooltipDataProcessor.AddTooltipPostCall,
            _G.Enum.TooltipDataType.Unit,
            function(tip)
                if initialized and tip == tooltip then
                    renderPlayerTooltip(tip)
                end
            end
        )
    end

    Tooltips.ApplySettings()
    return true
end

function Tooltips.ApplySettings()
    local active = settings
        and settings.enabled == true
        and currentMode() ~= "Disabled"
    Adapter.SetTooltipSurfaceEnabled(active)
    if binding then
        refreshBinding()
    end
    return Adapter.IsTooltipSurfaceActive()
end

function Tooltips.HandleModifierStateChanged(key)
    if key ~= "LSHIFT" and key ~= "RSHIFT" then
        return false
    end
    if not binding or not visibleBindingIsCurrent(binding) then
        clearBinding()
        return false
    end
    local mode = currentMode()
    if mode ~= "Minimal" and mode ~= "Compact" then
        return false
    end
    if settings.tooltip.shiftToDetailed ~= true then
        return false
    end
    local nowDown = shiftIsDown()
    if binding.shiftDown == nowDown then
        return false
    end
    return refreshBinding()
end

function Tooltips.RefreshVisible()
    return refreshBinding()
end

function Tooltips.GetEnhancementStatus()
    return lastEnhancementStatus.status,
        lastEnhancementStatus.reason,
        lastEnhancementStatus.scope,
        lastEnhancementStatus.slotID,
        lastEnhancementStatus.itemID
end

function Tooltips.Shutdown()
    if localListener then
        Scanner.Unsubscribe(localListener)
    end
    if remoteListener then
        Cache.Unsubscribe(remoteListener)
    end
    localListener = nil
    remoteListener = nil
    clearBinding()
    initialized = false
    -- The counters survive a Shutdown on purpose: they are a measurement of
    -- what the driver did, and zeroing them would make a shutdown look like a
    -- driver that never ran.
    driverMode = "none"
    Adapter.SetTooltipSurfaceEnabled(false)
end
