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
local Tooltips = {}
namespace.Tooltips = Tooltips

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
    if type(target) ~= "table" or type(target.GetUnit) ~= "function" then
        return nil
    end
    -- GetUnit returns EXACTLY ONE value. `local ok, _, unit = pcall(...)` looks
    -- like a discard but is not one: pcall yields (true, <unit>), so `_` took
    -- the unit and `unit` was ALWAYS nil. Every render therefore fell into the
    -- clearBinding() arm below and the player-tooltip surface added no rows on
    -- ANY client -- while every load assertion stayed green, because the code
    -- never raised, it just did nothing.
    --
    -- The same `ok, _, value` shape IS correct two lines of intent away where
    -- UnitClass is called, because UnitClass returns three values; the two are
    -- not interchangeable and one of them is not a bug.
    local ok, unit = pcall(target.GetUnit, target)
    if ok and type(unit) == "string" and unit ~= "" then
        return unit
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
            local colors = _G.CUSTOM_CLASS_COLORS
            local entry = type(colors) == "table" and colors[classToken] or nil
            if type(entry) ~= "table"
                or not validColor(entry.r, entry.g, entry.b) then
                colors = _G.RAID_CLASS_COLORS
                entry = type(colors) == "table" and colors[classToken] or nil
            end
            if type(entry) == "table" and validColor(entry.r, entry.g, entry.b) then
                return entry.r, entry.g, entry.b, classToken
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
    local red, green, blue = Adapter.GetCurrentScoreColor(value)
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

local function enhancementMetricsSuppressed(revision)
    local restricted = settings
        and settings.tooltip
        and settings.tooltip.restrictEnhancementMetricsToLevel70 == true
    if not restricted then
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
                    metric.status,
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

local function makeRows(mode, revision, result, unit, scope)
    local rows = {}
    local metrics = result.metrics
    local suppressed = enhancementMetricsSuppressed(revision)
    local classRed, classGreen, classBlue = playerClassColor(unit)
    local current, currentMetric = completeMetric(metrics, "gearScore")
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
                classRed,
                classGreen,
                classBlue
            )
        end
        if #parts > 0 then
            rows[1] = { text = table.concat(parts, "   ") }
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
                classRed,
                classGreen,
                classBlue
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
                "Complete",
                completion.compactText,
                completionColor(completion.ratio)
            )
        end
        if #secondary > 0 then
            rows[#rows + 1] = { text = table.concat(secondary, "   ") }
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
                        "unavailable",
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
            text = labelText("Enhancement analysis:") .. " "
                .. colorText(
                    "unavailable",
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
            "Current GS",
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
                    "Potential GS",
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
                    "Potential GS",
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
                    "Delta",
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
                    "Delta",
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
                    "Completion:",
                    completion.detailedText,
                    completionColor(completion.ratio)
                ),
            }
        elseif sharedReason and metricReason(completionMetric) == sharedReason then
            addUnavailableAnalysis()
        elseif type(completionMetric) == "table"
            and completionMetric.status == "complete" then
            rows[#rows + 1] = {
                text = labelText("Completion:") .. " "
                    .. colorText(
                        "no eligible opportunities",
                        NEUTRAL_RED,
                        NEUTRAL_GREEN,
                        NEUTRAL_BLUE
                    ),
            }
        elseif type(completionMetric) == "table" then
            addMetric(
                "Completion",
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
        "Average iLvl",
        "averageItemLevel",
        averageDisplay,
        averageMetric,
        nil,
        classRed,
        classGreen,
        classBlue
    )
    addMetric(
        "Unenhanced GS",
        "baseGS",
        base,
        baseMetric,
        nil,
        classRed,
        classGreen,
        classBlue
    )
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
            row.blue or 1
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
    into.warningColors = settings.tooltip.warningColors == true
    into.restrictToLevel70 =
        settings.tooltip.restrictEnhancementMetricsToLevel70 == true
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
        and current.restrictToLevel70
            == (settings.tooltip.restrictEnhancementMetricsToLevel70 == true)
end

local function renderPlayerTooltip(target)
    if not initialized or rendering then
        return false
    end
    rendering = true

    local unit, guid = validatePlayerUnit(target)
    if not unit or not Adapter.IsTooltipSurfaceActive() then
        clearBinding()
        rendering = false
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
            rendering = false
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
            rendering = false
            return false
        end
        rendered = addRows(
            target,
            makeRows(mode, source.revision, source.result, unit, source.source)
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
    rendering = false
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
    if type(target.GetUnit) ~= "function" then
        return
    end
    local ok, unit = pcall(target.GetUnit, target)
    if not ok or type(unit) ~= "string" or unit == "" then
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
                tooltip.HookScript, tooltip, script, SCRIPT_HANDLERS[script]
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
            tooltip.HookScript, tooltip, "OnUpdate", onTooltipUpdatePoll
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
            and pcall(tooltip.HookScript, tooltip, "OnShow", onTooltipShow) then
            pollArmed = false
        else
            pollArmed = true
        end
    end

    initialized = true

    localListener = localPublished
    remoteListener = remotePublished
    Scanner.Subscribe(localListener)
    Cache.Subscribe(remoteListener)
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
