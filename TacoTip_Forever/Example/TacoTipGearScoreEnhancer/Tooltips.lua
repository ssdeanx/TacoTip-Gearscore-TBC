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
    resetEnhancementStatus()
end

local function tooltipUnit(target)
    if type(target) ~= "table" or type(target.GetUnit) ~= "function" then
        return nil
    end
    local ok, _, unit = pcall(target.GetUnit, target)
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

local function readSource(guid)
    if isLocalGUID(guid) then
        local state = Scanner.GetCurrent()
        if type(state) ~= "table" then
            return {
                source = "local",
                state = "unavailable",
                generation = 0,
            }
        end
        local complete = state.status == "complete"
            and type(state.revision) == "table"
            and type(state.result) == "table"
        return {
            source = "local",
            state = state.status or "unavailable",
            generation = state.generation or 0,
            revisionID = complete and state.generation or nil,
            revision = complete and state.revision or nil,
            result = complete and state.result or nil,
        }
    end

    local state = Cache.Get(guid)
    if type(state) ~= "table" then
        return {
            source = "remote",
            state = "unavailable",
            generation = 0,
        }
    end
    local complete = state.state == "complete"
        and type(state.revision) == "table"
        and type(state.result) == "table"
    return {
        source = "remote",
        state = state.state or "unavailable",
        generation = state.generation or 0,
        revisionID = complete and state.revisionID or nil,
        revision = complete and state.revision or nil,
        result = complete and state.result or nil,
    }
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

local function makeSignature(guid, source, mode, unit)
    local fieldSettings = settings.tooltip.fields
    local classRed, classGreen, classBlue, classToken = playerClassColor(unit)
    local parts = {
        guid,
        source.source,
        tostring(source.state),
        tostring(source.generation),
        tostring(source.revisionID or "none"),
        mode,
        tostring(shiftIsDown()),
        tostring(fieldSettings.gearScore),
        tostring(fieldSettings.baseGS),
        tostring(fieldSettings.potentialGS),
        tostring(fieldSettings.delta),
        tostring(fieldSettings.averageItemLevel),
        tostring(fieldSettings.completion),
        tostring(settings.tooltip.warningColors),
        tostring(settings.tooltip.restrictEnhancementMetricsToLevel70),
        tostring(classToken),
        tostring(classRed),
        tostring(classGreen),
        tostring(classBlue),
    }
    return table.concat(parts, "|")
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
    local signature = makeSignature(guid, source, mode, unit)
    local currentLines = numberOfLines(target)
    if binding
        and binding.tooltip == target
        and binding.unit == unit
        and binding.guid == guid
        and binding.renderedSignature == signature
        and currentLines ~= nil
        and currentLines == binding.lineCountAfter then
        rendering = false
        return true
    end

    resetEnhancementStatus()
    binding = {
        tooltip = target,
        unit = unit,
        guid = guid,
        source = source.source,
        state = source.state,
        generation = source.generation,
        revisionID = source.revisionID,
        shiftDown = shiftIsDown(),
        renderedSignature = signature,
    }

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
    clearBinding()
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

    initialized = true
    tooltip:HookScript("OnTooltipSetUnit", onTooltipSetUnit)
    tooltip:HookScript("OnTooltipCleared", onTooltipCleared)
    tooltip:HookScript("OnTooltipSetItem", onTooltipCleared)
    tooltip:HookScript("OnHide", onTooltipCleared)

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
    if not (settings.tooltip.shiftToDetailed == true) then
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
    Adapter.SetTooltipSurfaceEnabled(false)
end
