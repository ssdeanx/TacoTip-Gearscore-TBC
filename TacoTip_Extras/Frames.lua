local addonName, namespace = ...

if type(namespace) ~= "table"
    or type(namespace.Scanner) ~= "table"
    or type(namespace.Cache) ~= "table"
    or type(namespace.TacoTipAdapter) ~= "table" then
    return
end

local Scanner = namespace.Scanner
local Cache = namespace.Cache
local Adapter = namespace.TacoTipAdapter
local Frames = {}
namespace.Frames = Frames

local MODES = {
    Disabled = true,
    Basic = true,
    Detailed = true,
}

local ROW_SPACING = 14
local MINIMUM_WIDTH = 150
local MAXIMUM_WIDTH = 210
local HANDLE_HEIGHT = 14
local POSITION_LIMIT = 4096

local BRAND_RED, BRAND_GREEN, BRAND_BLUE = 0.60, 0.46, 0.82
local GOLD_RED, GOLD_GREEN, GOLD_BLUE = 0.83, 0.66, 0.29
local POSITIVE_RED, POSITIVE_GREEN, POSITIVE_BLUE = 0.35, 0.82, 0.48
local NEUTRAL_RED, NEUTRAL_GREEN, NEUTRAL_BLUE = 0.82, 0.82, 0.82
local MUTED_RED, MUTED_GREEN, MUTED_BLUE = 0.58, 0.56, 0.64

local settings
local initialized = false
local eventFrame
local localListener
local remoteListener
local secureHooks = {}

local CONTEXTS = {
    character = {
        key = "character",
        hostName = "PaperDollFrame",
        modelName = "CharacterModelFrame",
        positionKey = "characterPosition",
        defaultX = 72,
        defaultY = 320,
        fallbackBounds = { left = 72, right = 270, bottom = 220, top = 420 },
        leftSlots = {
            "CharacterHeadSlot", "CharacterNeckSlot", "CharacterShoulderSlot",
            "CharacterBackSlot", "CharacterChestSlot", "CharacterShirtSlot",
            "CharacterTabardSlot", "CharacterWristSlot",
        },
        rightSlots = {
            "CharacterHandsSlot", "CharacterWaistSlot", "CharacterLegsSlot",
            "CharacterFeetSlot", "CharacterFinger0Slot", "CharacterFinger1Slot",
            "CharacterTrinket0Slot", "CharacterTrinket1Slot",
        },
        bottomSlots = {
            "CharacterMainHandSlot", "CharacterSecondaryHandSlot",
            "CharacterRangedSlot",
        },
    },
    inspect = {
        key = "inspect",
        hostName = "InspectPaperDollFrame",
        modelName = "InspectModelFrame",
        positionKey = "inspectPosition",
        defaultX = 72,
        defaultY = 180,
        fallbackBounds = { left = 62, right = 270, bottom = 92, top = 350 },
        leftSlots = {
            "InspectHeadSlot", "InspectNeckSlot", "InspectShoulderSlot",
            "InspectBackSlot", "InspectChestSlot", "InspectShirtSlot",
            "InspectTabardSlot", "InspectWristSlot",
        },
        rightSlots = {
            "InspectHandsSlot", "InspectWaistSlot", "InspectLegsSlot",
            "InspectFeetSlot", "InspectFinger0Slot", "InspectFinger1Slot",
            "InspectTrinket0Slot", "InspectTrinket1Slot",
        },
        bottomSlots = {
            "InspectMainHandSlot", "InspectSecondaryHandSlot", "InspectRangedSlot",
        },
    },
}

local function isFiniteNumber(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function validOffset(value)
    return isFiniteNumber(value) and math.abs(value) <= POSITION_LIMIT
end

local function equipmentSettings()
    local value = type(settings) == "table" and settings.equipmentDisplay or nil
    if type(value) == "table" then
        return value
    end
    return nil
end

local function currentMode()
    local equipment = equipmentSettings()
    local mode = equipment and equipment.mode
    if MODES[mode] then
        return mode
    end
    return "Disabled"
end

local function featureRequested()
    return type(settings) == "table"
        and settings.enabled == true
        and currentMode() ~= "Disabled"
end

local function frameVisible(frame)
    if type(frame) ~= "table" then
        return false
    end
    if type(frame.IsVisible) == "function" then
        local ok, visible = pcall(frame.IsVisible, frame)
        if ok then
            return visible == true
        end
    end
    if type(frame.IsShown) == "function" then
        local ok, shown = pcall(frame.IsShown, frame)
        return ok and shown == true
    end
    return false
end

local function cancelDrag(context)
    context.drag = nil
    if context.handle and type(context.handle.SetScript) == "function" then
        context.handle:SetScript("OnUpdate", nil)
    end
end

local function cancelInspectExpiry(context)
    if context.key == "inspect" then
        context.expiryToken = nil
    end
end

local function validPlayerGUID(guid)
    if type(guid) ~= "string" or guid == "" then
        return false
    end
    if type(_G.GUIDIsPlayer) == "function" then
        local ok, player = pcall(_G.GUIDIsPlayer, guid)
        if not ok or player ~= true then
            return false
        end
    elseif not string.match(guid, "^Player%-%d+%-%x+$") then
        return false
    end
    return true
end

local function validateUnit(unit)
    if type(unit) ~= "string" or unit == ""
        or type(_G.UnitExists) ~= "function"
        or type(_G.UnitIsPlayer) ~= "function"
        or type(_G.UnitGUID) ~= "function" then
        return nil
    end
    local existsOK, exists = pcall(_G.UnitExists, unit)
    local playerOK, player = pcall(_G.UnitIsPlayer, unit)
    local guidOK, guid = pcall(_G.UnitGUID, unit)
    if not existsOK or exists ~= true
        or not playerOK or player ~= true
        or not guidOK or not validPlayerGUID(guid) then
        return nil
    end
    local confirmOK, confirmed = pcall(_G.UnitGUID, unit)
    if not confirmOK or confirmed ~= guid then
        return nil
    end
    return guid
end

local function validHostIdentity(context)
    local host = _G[context.hostName]
    local model = _G[context.modelName]
    if not model and context.key == "character" then
        model = _G.CharacterModelScene
    end
    if type(host) ~= "table" or type(model) ~= "table"
        or type(host.HookScript) ~= "function"
        or type(host.CreateFontString) ~= "function"
        or type(host.GetRect) ~= "function"
        or type(model.GetParent) ~= "function" then
        return nil, nil, "blizzard-equipment-frame-mismatch"
    end
    local parentOK, parent = pcall(model.GetParent, model)
    if not parentOK or parent ~= host then
        return nil, nil, "blizzard-equipment-parent-mismatch"
    end
    return host, model, nil
end

local function boundContextIdentityValid(context)
    local host, model, reason = validHostIdentity(context)
    if not host or host ~= context.host or model ~= context.model then
        return false, reason or "blizzard-equipment-identity-changed"
    end
    if context.key == "inspect"
        and (_G.InspectFrame ~= context.inspectFrame
            or type(context.inspectFrame) ~= "table"
            or type(context.inspectFrame.HookScript) ~= "function") then
        return false, "blizzard-inspect-frame-identity-changed"
    end
    return true, nil
end

local function colorText(text, red, green, blue)
    if type(text) ~= "string"
        or not isFiniteNumber(red)
        or not isFiniteNumber(green)
        or not isFiniteNumber(blue) then
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

local function displayNumber(value)
    if not isFiniteNumber(value) then
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
    if value >= 0 then
        return "+" .. displayed
    end
    return displayed
end

local function validColor(red, green, blue)
    return isFiniteNumber(red) and red >= 0 and red <= 1
        and isFiniteNumber(green) and green >= 0 and green <= 1
        and isFiniteNumber(blue) and blue >= 0 and blue <= 1
end

local function classColor(unit)
    if type(_G.UnitClass) == "function" then
        local ok, _, classToken = pcall(_G.UnitClass, unit)
        if ok and type(classToken) == "string" then
            local colors = _G.CUSTOM_CLASS_COLORS
            local entry = type(colors) == "table" and colors[classToken] or nil
            if type(entry) ~= "table" or not validColor(entry.r, entry.g, entry.b) then
                colors = _G.RAID_CLASS_COLORS
                entry = type(colors) == "table" and colors[classToken] or nil
            end
            if type(entry) == "table" and validColor(entry.r, entry.g, entry.b) then
                return entry.r, entry.g, entry.b
            end
        end
    end
    return NEUTRAL_RED, NEUTRAL_GREEN, NEUTRAL_BLUE
end

local function currentScoreColor(value)
    local reader = Adapter.GetEquipmentScoreColor
    if type(reader) ~= "function" then
        reader = Adapter.GetCurrentScoreColor
    end
    if type(reader) == "function" then
        local ok, red, green, blue = pcall(reader, value)
        if ok and validColor(red, green, blue) then
            return red, green, blue
        end
    end
    return NEUTRAL_RED, NEUTRAL_GREEN, NEUTRAL_BLUE
end

local function completeMetric(metrics, name)
    local metric = type(metrics) == "table" and metrics[name] or nil
    if type(metric) == "table" and metric.status == "complete" then
        return metric.value, metric
    end
    return nil, metric
end

local function metricRow(label, value, formatter, red, green, blue)
    local text = formatter and formatter(value) or displayNumber(value)
    if not text then
        return nil
    end
    return labelText(label .. ":") .. " " .. colorText(text, red, green, blue)
end

local function completionRow(value)
    if type(value) ~= "table"
        or not isFiniteNumber(value.filled)
        or not isFiniteNumber(value.opportunities) then
        return nil
    end
    if value.opportunities == 0 then
        return labelText("Completion:") .. " "
            .. colorText(
                "no eligible opportunities",
                NEUTRAL_RED,
                NEUTRAL_GREEN,
                NEUTRAL_BLUE
            )
    end
    if not isFiniteNumber(value.displayPercent) or not isFiniteNumber(value.ratio) then
        return nil
    end
    local red, green, blue = NEUTRAL_RED, NEUTRAL_GREEN, NEUTRAL_BLUE
    local warningColors = settings
        and settings.tooltip
        and settings.tooltip.warningColors == true
    if warningColors then
        if value.ratio == 1 then
            red, green, blue = 0.2, 1, 0.2
        elseif value.ratio >= 0.9 then
            red, green, blue = 1, 1, 0.2
        elseif value.ratio >= 0.7 then
            red, green, blue = 1, 0.55, 0.1
        else
            red, green, blue = 1, 0.2, 0.2
        end
    end
    local text = string.format(
        "%d%% (%d/%d)",
        value.displayPercent,
        value.filled,
        value.opportunities
    )
    return labelText("Completion:") .. " " .. colorText(text, red, green, blue)
end

local function enhancementSuppressed(metrics)
    for _, name in ipairs({ "potentialGS", "delta", "completion" }) do
        local metric = type(metrics) == "table" and metrics[name] or nil
        if type(metric) ~= "table" or metric.status ~= "suppressed" then
            return false
        end
    end
    return true
end

local function makeRows(mode, result, unit)
    local rows = {}
    local metrics = type(result) == "table" and result.metrics or nil
    if type(metrics) ~= "table" then
        return rows
    end

    local current = completeMetric(metrics, "gearScore")
    local average = completeMetric(metrics, "averageItemLevel")
    local averageDisplay = type(average) == "table" and average.display or nil
    local classRed, classGreen, classBlue = classColor(unit)

    if type(current) == "number" then
        local red, green, blue = currentScoreColor(current)
        rows[#rows + 1] = metricRow(
            "Current GS",
            current,
            nil,
            red,
            green,
            blue
        )
    end

    if mode == "Detailed" then
        local potential, potentialMetric = completeMetric(metrics, "potentialGS")
        local delta, deltaMetric = completeMetric(metrics, "delta")
        local completion, completionMetric = completeMetric(metrics, "completion")
        local completionText = completionRow(completion)
        local suppressed = enhancementSuppressed(metrics)
        local analysisComplete = type(potential) == "number"
            and type(delta) == "number"
            and type(completionText) == "string"
        if not suppressed and analysisComplete then
            rows[#rows + 1] = metricRow(
                "Potential GS",
                potential,
                nil,
                GOLD_RED,
                GOLD_GREEN,
                GOLD_BLUE
            )
            local deltaRed, deltaGreen, deltaBlue = NEUTRAL_RED,
                NEUTRAL_GREEN,
                NEUTRAL_BLUE
            if delta > 0 then
                deltaRed, deltaGreen, deltaBlue = POSITIVE_RED,
                    POSITIVE_GREEN,
                    POSITIVE_BLUE
            end
            rows[#rows + 1] = metricRow(
                "Delta",
                delta,
                signedNumber,
                deltaRed,
                deltaGreen,
                deltaBlue
            )
            rows[#rows + 1] = completionText
        elseif not suppressed then
            local hasEvidence = type(potentialMetric) == "table"
                or type(deltaMetric) == "table"
                or type(completionMetric) == "table"
            if hasEvidence then
                rows[#rows + 1] = labelText("Enhancement analysis:") .. " "
                    .. colorText(
                        "Unavailable",
                        MUTED_RED,
                        MUTED_GREEN,
                        MUTED_BLUE
                    )
            end
        end
    end

    if type(averageDisplay) == "number" then
        local avgRed, avgGreen, avgBlue = currentScoreColor(current)
        if not validColor(avgRed, avgGreen, avgBlue) then
            avgRed, avgGreen, avgBlue = NEUTRAL_RED, NEUTRAL_GREEN, NEUTRAL_BLUE
        end
        rows[#rows + 1] = metricRow(
            "Average iLvl",
            averageDisplay,
            nil,
            avgRed,
            avgGreen,
            avgBlue
        )
    end

    local equipment = equipmentSettings()
    if mode == "Detailed" and equipment and equipment.showUnenhanced == true then
        local base = completeMetric(metrics, "baseGS")
        if type(base) == "number" then
            rows[#rows + 1] = metricRow(
                "Unenhanced GS",
                base,
                nil,
                classRed,
                classGreen,
                classBlue
            )
        end
    end
    return rows
end

local function hideRegion(region)
    if type(region) == "table" and type(region.Hide) == "function" then
        pcall(region.Hide, region)
    end
end

local function showRegion(region)
    if type(region) == "table" and type(region.Show) == "function" then
        pcall(region.Show, region)
    end

end

local function hideRows(context)
    for _, row in ipairs(context.rows or {}) do
        if type(row.SetText) == "function" then
            row:SetText("")
        end
        hideRegion(row)
    end
    context.rowCount = 0
end

local function setOutlineVisible(context, visible)
    for _, texture in ipairs(context.outline or {}) do
        if visible then
            showRegion(texture)
        else
            hideRegion(texture)
        end
    end
end

local function positionValue(context)
    local equipment = equipmentSettings()
    local saved = equipment and equipment[context.positionKey]
    if type(saved) == "table" and validOffset(saved.x) and validOffset(saved.y) then
        return saved.x, saved.y
    end
    return context.defaultX, context.defaultY
end

local function readRect(frame)
    if type(frame) ~= "table" or type(frame.GetRect) ~= "function" then
        return nil
    end
    local ok, left, bottom, width, height = pcall(frame.GetRect, frame)
    if not ok or not isFiniteNumber(left) or not isFiniteNumber(bottom)
        or not isFiniteNumber(width) or width <= 0
        or not isFiniteNumber(height) or height <= 0 then
        return nil
    end
    return left, bottom, width, height
end

local function frameEdge(frame, method)
    local reader = type(frame) == "table" and frame[method] or nil
    if type(reader) ~= "function" then
        return nil
    end
    local ok, value = pcall(reader, frame)
    if ok and isFiniteNumber(value) then
        return value
    end
    return nil
end

local function safeBounds(context)
    local fallback = context.fallbackBounds
    local bounds = {
        left = fallback.left,
        right = fallback.right,
        bottom = fallback.bottom,
        top = fallback.top,
    }
    local hostLeft, hostBottom = readRect(context.host)
    if not hostLeft then
        return bounds
    end

    local modelLeft = frameEdge(context.model, "GetLeft")
    local modelRight = frameEdge(context.model, "GetRight")
    local modelBottom = frameEdge(context.model, "GetBottom")
    local modelTop = frameEdge(context.model, "GetTop")
    if modelLeft and modelRight and modelBottom and modelTop then
        bounds.left = modelLeft - hostLeft + 8
        bounds.right = modelRight - hostLeft - 8
        bounds.bottom = modelBottom - hostBottom + 8
        bounds.top = modelTop - hostBottom - 8
    end

    for _, name in ipairs(context.leftSlots) do
        local right = frameEdge(_G[name], "GetRight")
        if right then
            bounds.left = math.max(bounds.left, right - hostLeft + 8)
        end
    end
    for _, name in ipairs(context.rightSlots) do
        local left = frameEdge(_G[name], "GetLeft")
        if left then
            bounds.right = math.min(bounds.right, left - hostLeft - 8)
        end
    end
    for _, name in ipairs(context.bottomSlots) do
        local top = frameEdge(_G[name], "GetTop")
        if top then
            bounds.bottom = math.max(bounds.bottom, top - hostBottom + 8)
        end
    end
    if bounds.right <= bounds.left or bounds.top <= bounds.bottom then
        return {
            left = fallback.left,
            right = fallback.right,
            bottom = fallback.bottom,
            top = fallback.top,
        }
    end
    return bounds
end

local function clampPosition(context, x, y)
    local bounds = safeBounds(context)
    local width = context.width or MINIMUM_WIDTH
    local height = context.height or ROW_SPACING
    local maximumX = bounds.right - width
    local minimumY = bounds.bottom + height
    local equipment = equipmentSettings()
    local maximumY = bounds.top
    if equipment and equipment.locked == false then
        maximumY = maximumY - HANDLE_HEIGHT - 2
    end
    if maximumX < bounds.left then
        maximumX = bounds.left
    end
    if minimumY > maximumY then
        minimumY = maximumY
    end
    x = math.max(bounds.left, math.min(maximumX, x))
    y = math.max(minimumY, math.min(maximumY, y))
    return x, y
end

local function applyPosition(context, x, y)
    if not context.block then
        return false
    end
    x, y = clampPosition(context, x, y)
    context.currentX = x
    context.currentY = y
    context.block:ClearAllPoints()
    context.block:SetPoint("TOPLEFT", context.host, "BOTTOMLEFT", x, y)
    return true
end

local function measureRows(context, rows)
    local width = MINIMUM_WIDTH
    for index, text in ipairs(rows) do
        local row = context.rows[index]
        if row then
            row:SetText(text)
            if type(row.GetStringWidth) == "function" then
                local ok, measured = pcall(row.GetStringWidth, row)
                if ok and isFiniteNumber(measured) then
                    width = math.max(width, measured + 4)
                end
            end
        end
    end
    local bounds = safeBounds(context)
    local availableWidth = bounds.right - bounds.left
    if availableWidth > 0 then
        width = math.min(width, MAXIMUM_WIDTH, availableWidth)
    else
        width = MINIMUM_WIDTH
    end
    return width, math.max(ROW_SPACING, #rows * ROW_SPACING)
end

local function setRows(context, rows)
    hideRows(context)
    if #rows == 0 then
        return false
    end
    local width, height = measureRows(context, rows)
    context.width = width
    context.height = height
    context.block:SetSize(width, height)
    for index, text in ipairs(rows) do
        local row = context.rows[index]
        row:SetWidth(width)
        row:SetText(text)
        showRegion(row)
    end
    context.rowCount = #rows
    applyPosition(context, context.currentX or context.defaultX, context.currentY or context.defaultY)
    return true
end

local function setStateRow(context, text)
    return setRows(context, {
        colorText(text, MUTED_RED, MUTED_GREEN, MUTED_BLUE),
    })
end

local function setInteractiveState(context)
    local equipment = equipmentSettings()
    local unlocked = equipment and equipment.locked == false
    local active = unlocked and context.block and frameVisible(context.block)
    if context.block and type(context.block.EnableMouse) == "function" then
        context.block:EnableMouse(false)
    end
    if context.handle then
        if active then
            showRegion(context.handle)
        else
            cancelDrag(context)
            hideRegion(context.handle)
        end
    end
    setOutlineVisible(context, active)
end

local function equipmentContextActive(context)
    local checker = Adapter.IsEquipmentContextActive
    if type(checker) == "function" then
        local ok, active = pcall(checker, context.key)
        return ok and active == true
    end
    checker = Adapter.IsEquipmentSurfaceActive
    if type(checker) == "function" then
        local ok, active = pcall(checker, context.key)
        return ok and active == true
    end
    return false
end

local function acquireEquipmentContext(context)
    local acquire = Adapter.AcquireEquipmentContext
    if type(acquire) == "function" then
        local ok, active = pcall(acquire, context.key)
        return ok and active == true
    end
    local setter = Adapter.SetEquipmentSurfaceEnabled
    if type(setter) == "function" then
        local ok, active = pcall(setter, context.key, true)
        if ok and active == true then
            return true
        end
    end
    return equipmentContextActive(context)
end

local function releaseEquipmentContext(context, reason)
    local release = Adapter.ReleaseEquipmentContext
    if type(release) == "function" then
        pcall(release, context.key, reason)
        return
    end
    local setter = Adapter.SetEquipmentSurfaceEnabled
    if type(setter) == "function" then
        pcall(setter, context.key, false)
    end
end

local function hideContext(context, reason, preserveIdentity, retainLeaseRequest)
    cancelDrag(context)
    cancelInspectExpiry(context)
    hideRows(context)
    hideRegion(context.handle)
    setOutlineVisible(context, false)
    hideRegion(context.block)
    context.visible = false
    context.state = reason or "hidden"
    if context.key == "character" and not retainLeaseRequest then
        context.guid = nil
        context.generation = nil
        context.revisionID = nil
        context.localScanNeeded = nil
    end
    if context.key == "inspect" and not preserveIdentity then
        context.guid = nil
        context.unit = nil
        context.minimumGeneration = nil
        context.generation = nil
        context.revisionID = nil
    end
    if not retainLeaseRequest then
        releaseEquipmentContext(context, reason or "context-hidden")
    end
end

local function equipmentFailureReason(context, fallback)
    local reader = Adapter.GetEquipmentSurfaceReason
    if type(reader) == "function" then
        local ok, reason = pcall(reader, context.key)
        if ok and type(reason) == "string" and reason ~= "" then
            return reason
        end
    end
    return fallback or "equipment-compatibility-unsupported"
end

local function hideForEquipmentFailure(context, fallback)
    local reason = equipmentFailureReason(context, fallback)
    local deferred = reason == context.key .. "-combat-deferred"
    hideContext(
        context,
        reason,
        deferred and context.key == "inspect",
        deferred
    )
    return false
end

local function showContextBlock(context)
    showRegion(context.block)
    context.visible = true
    setInteractiveState(context)
end

local function renderComplete(context, result, unit)
    local rows = makeRows(currentMode(), result, unit)
    if #rows == 0 then
        setStateRow(context, "Equipment data unavailable")
        context.state = "unavailable"
    else
        setRows(context, rows)
        context.state = "complete"
    end
    showContextBlock(context)
end

local function renderState(context, state)
    cancelInspectExpiry(context)
    if state == "pending" or state == "idle" then
        setStateRow(context, "Scanning equipment...")
        context.state = "pending"
    else
        setStateRow(context, "Equipment data unavailable")
        context.state = "unavailable"
    end
    showContextBlock(context)
end

local function renderLocal(state)
    local context = CONTEXTS.character
    if not context.bound or not frameVisible(context.host) or not featureRequested() then
        return false
    end
    local identityValid, identityReason = boundContextIdentityValid(context)
    if not identityValid then
        hideContext(context, identityReason)
        return false
    end
    local guid = validateUnit("player")
    if not guid or guid ~= context.guid then
        hideContext(context, "invalid-player")
        return false
    end
    if not equipmentContextActive(context) and not acquireEquipmentContext(context) then
        return hideForEquipmentFailure(context, "equipment-compatibility-unsupported")
    end
    state = type(state) == "table" and state or Scanner.GetCurrent()
    if type(state) ~= "table" then
        renderState(context, "unavailable")
        return false
    end
    local generation = isFiniteNumber(state.generation) and state.generation or 0
    if context.generation and generation < context.generation then
        return false
    end
    context.generation = generation
    if state.status == "complete"
        and type(state.revision) == "table"
        and type(state.result) == "table" then
        context.revisionID = generation
        renderComplete(context, state.result, "player")
        return true
    end
    context.revisionID = nil
    renderState(context, state.status)
    return true
end

local function inspectUnit()
    local frame = _G.InspectFrame
    local unit = type(frame) == "table" and frame.unit or nil
    if type(unit) ~= "string" or unit == "" then
        return nil, nil
    end
    return unit, validateUnit(unit)
end

local function inspectPaperDollActive(context)
    if not frameVisible(context.host) then
        return false
    end
    local selected
    if type(_G.PanelTemplates_GetSelectedTab) == "function"
        and type(_G.InspectFrame) == "table" then
        local ok, value = pcall(_G.PanelTemplates_GetSelectedTab, _G.InspectFrame)
        if ok then
            selected = value
        end
    end
    return selected == nil or selected == 1
end

local function remoteSnapshotAllowed(context, snapshot)
    if type(snapshot) ~= "table" then
        return false
    end
    local generation = snapshot.generation
    if not isFiniteNumber(generation) then
        return false
    end
    if context.minimumGeneration and generation < context.minimumGeneration then
        return false
    end
    if context.generation and generation < context.generation then
        return false
    end
    if context.generation and generation == context.generation
        and context.revisionID and isFiniteNumber(snapshot.revisionID)
        and snapshot.revisionID < context.revisionID then
        return false
    end
    return true
end

local renderRemote

local function keepVisibleCompletedSnapshot(context, snapshot)
    return context.state == "complete"
        and type(snapshot) == "table"
        and snapshot.state == "stale"
        and snapshot.reason == "freshness-expired"
        and snapshot.generation == context.generation
        and snapshot.revisionID == context.revisionID
end

renderRemote = function(snapshot)
    local context = CONTEXTS.inspect
    if not context.bound or not inspectPaperDollActive(context) or not featureRequested() then
        return false
    end
    local identityValid, identityReason = boundContextIdentityValid(context)
    if not identityValid then
        hideContext(context, identityReason)
        return false
    end
    local unit, guid = inspectUnit()
    if not unit or not guid or guid ~= context.guid then
        hideContext(context, "invalid-inspect-player")
        return false
    end
    if not equipmentContextActive(context) and not acquireEquipmentContext(context) then
        return hideForEquipmentFailure(context, "equipment-compatibility-unsupported")
    end
    snapshot = type(snapshot) == "table" and snapshot or Cache.Get(guid)
    -- Cache freshness limits whether a result may be reused for a later
    -- inspection. They must not erase an already-rendered, identity-matched
    -- snapshot while the same Inspect PaperDoll remains continuously open.
    if keepVisibleCompletedSnapshot(context, snapshot) then
        cancelInspectExpiry(context)
        return true
    end
    if not remoteSnapshotAllowed(context, snapshot) then
        if not context.generation then
            renderState(context, "pending")
        end
        return false
    end
    context.generation = snapshot.generation
    context.minimumGeneration = nil
    context.revisionID = snapshot.revisionID
    if snapshot.state == "complete"
        and isFiniteNumber(snapshot.revisionID)
        and type(snapshot.revision) == "table"
        and type(snapshot.result) == "table" then
        cancelInspectExpiry(context)
        renderComplete(context, snapshot.result, unit)
        return true
    end
    renderState(context, snapshot.state)
    return true
end

local function requestLocalScan()
    local core = namespace.Core
    if type(core) == "table" and type(core.RequestLocalScan) == "function" then
        local ok = pcall(core.RequestLocalScan, "character-shown")
        return ok
    end
    return false
end

local function onCharacterShow()
    local context = CONTEXTS.character
    local host, model, reason = validHostIdentity(context)
    if not host or host ~= context.host or model ~= context.model then
        hideContext(context, reason or "blizzard-equipment-identity-changed")
        return
    end
    local guid = validateUnit("player")
    if not guid then
        hideContext(context, "invalid-player")
        return
    end
    if not featureRequested() then
        hideContext(context, "equipment-summary-disabled")
        return
    end
    context.guid = guid
    context.generation = nil
    context.revisionID = nil
    context.localScanNeeded = true
    if not acquireEquipmentContext(context) then
        hideForEquipmentFailure(context, "equipment-compatibility-unsupported")
        return
    end
    renderState(context, "pending")
    if requestLocalScan() then
        context.localScanNeeded = false
    end
end

local function bindInspectUnit(expectNewGeneration, acceptedSnapshot)
    local context = CONTEXTS.inspect
    local identityValid, identityReason = boundContextIdentityValid(context)
    if not identityValid then
        hideContext(context, identityReason)
        return false
    end

    local unit, guid = inspectUnit()
    if not unit or not guid then
        hideContext(context, "invalid-inspect-player")
        return false
    end

    -- InspectFrame_Show and InspectFrame_UnitChanged can both run for one
    -- inspection. Rebinding the same GUID must be idempotent; otherwise each
    -- post-hook can discard a result that completed between the two hooks and
    -- demand a generation that will never arrive.
    if context.guid == guid then
        context.unit = unit
        if inspectPaperDollActive(context) and featureRequested() then
            if not equipmentContextActive(context)
                and not acquireEquipmentContext(context) then
                return hideForEquipmentFailure(
                    context,
                    "equipment-compatibility-unsupported"
                )
            end
            renderRemote(
                type(acceptedSnapshot) == "table"
                    and acceptedSnapshot
                    or Cache.Get(guid)
            )
        end
        return true
    end

    hideRows(context)
    hideRegion(context.block)
    cancelInspectExpiry(context)
    context.visible = false
    releaseEquipmentContext(context, "inspect-unit-changing")
    context.unit = unit
    context.guid = guid
    context.generation = nil
    context.revisionID = nil
    context.minimumGeneration = nil

    if type(acceptedSnapshot) == "table"
        and isFiniteNumber(acceptedSnapshot.generation) then
        context.minimumGeneration = acceptedSnapshot.generation
    elseif expectNewGeneration then
        local prior = Cache.Get(guid)
        local priorGeneration = type(prior) == "table" and prior.generation or 0
        if isFiniteNumber(priorGeneration) then
            context.minimumGeneration = priorGeneration + 1
        end
    end

    if inspectPaperDollActive(context) and featureRequested() then
        if not acquireEquipmentContext(context) then
            return hideForEquipmentFailure(
                context,
                "equipment-compatibility-unsupported"
            )
        end
        if type(acceptedSnapshot) == "table" then
            renderRemote(acceptedSnapshot)
        elseif expectNewGeneration then
            renderState(context, "pending")
        else
            renderRemote(Cache.Get(guid))
        end
    end
    return true
end

local function onInspectShow()
    local context = CONTEXTS.inspect
    local host, model, reason = validHostIdentity(context)
    if not host or host ~= context.host or model ~= context.model
        or _G.InspectFrame ~= context.inspectFrame then
        hideContext(context, reason or "blizzard-equipment-identity-changed")
        return
    end
    local unit, guid = inspectUnit()
    if not unit or not guid then
        hideContext(context, "invalid-inspect-player")
        return
    end
    if context.guid ~= guid then
        bindInspectUnit(true)
        return
    end
    if not featureRequested() then
        hideContext(context, "equipment-summary-disabled")
    elseif not equipmentContextActive(context)
        and not acquireEquipmentContext(context) then
        hideForEquipmentFailure(context, "equipment-compatibility-unsupported")
    else
        -- Always re-check the exact-GUID cache. A publication can complete
        -- between Blizzard's Inspect hooks; minimumGeneration is enforced by
        -- renderRemote rather than by blindly forcing the pending row here.
        renderRemote(Cache.Get(guid))
    end
end

local function createOutline(context)
    if type(context.block.CreateTexture) ~= "function" then
        return
    end
    local definitions = {
        { "TOPLEFT", "TOPRIGHT", 1 },
        { "BOTTOMLEFT", "BOTTOMRIGHT", 1 },
        { "TOPLEFT", "BOTTOMLEFT", 1 },
        { "TOPRIGHT", "BOTTOMRIGHT", 1 },
    }
    context.outline = {}
    for index, definition in ipairs(definitions) do
        local texture = context.block:CreateTexture(nil, "OVERLAY")
        if type(texture.SetColorTexture) == "function" then
            texture:SetColorTexture(BRAND_RED, BRAND_GREEN, BRAND_BLUE, 0.55)
        elseif type(texture.SetTexture) == "function" then
            texture:SetTexture(BRAND_RED, BRAND_GREEN, BRAND_BLUE, 0.55)
        end
        local startPoint, endPoint, thickness = definition[1], definition[2], definition[3]
        texture:SetPoint(startPoint, context.block, startPoint, 0, 0)
        texture:SetPoint(endPoint, context.block, endPoint, 0, 0)
        if index <= 2 then
            texture:SetHeight(thickness)
        else
            texture:SetWidth(thickness)
        end
        hideRegion(texture)
        context.outline[#context.outline + 1] = texture
    end
end

local function cursorInParentUnits(context)
    if type(_G.GetCursorPosition) ~= "function" then
        return nil, nil
    end
    local ok, x, y = pcall(_G.GetCursorPosition)
    if not ok or not isFiniteNumber(x) or not isFiniteNumber(y) then
        return nil, nil
    end
    local scale = 1
    if type(context.host.GetEffectiveScale) == "function" then
        local scaleOK, value = pcall(context.host.GetEffectiveScale, context.host)
        if scaleOK and isFiniteNumber(value) and value > 0 then
            scale = value
        end
    end
    return x / scale, y / scale
end

local function updateDrag(context)
    local x, y = cursorInParentUnits(context)
    if not x or not context.drag then
        return
    end
    applyPosition(
        context,
        context.drag.startX + (x - context.drag.cursorX),
        context.drag.startY + (y - context.drag.cursorY)
    )
end

local function stopDrag(context)
    if not context.drag then
        return
    end
    cancelDrag(context)
    local equipment = equipmentSettings()
    if equipment and validOffset(context.currentX) and validOffset(context.currentY) then
        equipment[context.positionKey] = {
            x = context.currentX,
            y = context.currentY,
        }
    end
end

local function startDrag(context)
    local equipment = equipmentSettings()
    if not equipment or equipment.locked ~= false
        or not frameVisible(context.host)
        or not frameVisible(context.block) then
        return
    end
    local identityValid = boundContextIdentityValid(context)
    if not identityValid then
        hideContext(context, "blizzard-equipment-identity-changed")
        return
    end
    local cursorX, cursorY = cursorInParentUnits(context)
    if not cursorX then
        return
    end
    context.drag = {
        cursorX = cursorX,
        cursorY = cursorY,
        startX = context.currentX,
        startY = context.currentY,
    }
    context.handle:SetScript("OnUpdate", function()
        updateDrag(context)
    end)
end

local function createContextFrames(context)
    local block = CreateFrame(
        "Frame",
        addonName .. (context.key == "character" and "CharacterSummary" or "InspectSummary"),
        context.host
    )
    block:SetSize(MINIMUM_WIDTH, ROW_SPACING)
    block:EnableMouse(false)
    context.block = block
    context.rows = {}
    for index = 1, 6 do
        local row = block:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row:SetJustifyH("LEFT")
        row:SetWidth(MINIMUM_WIDTH)
        if type(row.SetWordWrap) == "function" then
            row:SetWordWrap(false)
        end
        row:SetPoint("TOPLEFT", block, "TOPLEFT", 0, -(index - 1) * ROW_SPACING)
        hideRegion(row)
        context.rows[index] = row
    end
    createOutline(context)

    local handle = CreateFrame(
        "Button",
        addonName .. (context.key == "character" and "CharacterSummaryHandle" or "InspectSummaryHandle"),
        block,
        "UIPanelButtonTemplate"
    )
    handle:SetSize(42, HANDLE_HEIGHT)
    handle:SetPoint("BOTTOMRIGHT", block, "TOPRIGHT", 0, 2)
    handle:SetText("Drag")
    handle:RegisterForDrag("LeftButton")
    handle:SetScript("OnDragStart", function()
        startDrag(context)
    end)
    handle:SetScript("OnDragStop", function()
        stopDrag(context)
    end)
    hideRegion(handle)
    context.handle = handle

    context.width = MINIMUM_WIDTH
    context.height = ROW_SPACING
    local x, y = positionValue(context)
    context.currentX, context.currentY = x, y
    applyPosition(context, x, y)
    hideRegion(block)
end

local function bindCharacter()
    local context = CONTEXTS.character
    if context.bound then
        return true
    end
    local host, model, reason = validHostIdentity(context)
    if not host then
        context.state = reason
        return false
    end
    context.host = host
    context.model = model
    createContextFrames(context)
    host:HookScript("OnShow", onCharacterShow)
    host:HookScript("OnHide", function()
        hideContext(context, "character-hidden")
    end)
    host:HookScript("OnSizeChanged", function()
        if context.block then
            applyPosition(context, context.currentX, context.currentY)
        end
    end)
    context.bound = true
    context.state = "bound"
    if frameVisible(host) then
        onCharacterShow()
    end
    return true
end

local function safeSecureHook(target, method, callback, key)
    if secureHooks[key] or type(_G.hooksecurefunc) ~= "function" then
        return secureHooks[key] == true
    end
    local ok
    if type(target) == "table" then
        ok = pcall(_G.hooksecurefunc, target, method, callback)
    else
        ok = pcall(_G.hooksecurefunc, method, callback)
    end
    if ok then
        secureHooks[key] = true
    end
    return ok
end

local function bindInspect()
    local context = CONTEXTS.inspect
    if context.bound then
        return true
    end
    local host, model, reason = validHostIdentity(context)
    local inspectFrame = _G.InspectFrame
    if not host or type(inspectFrame) ~= "table"
        or type(inspectFrame.HookScript) ~= "function" then
        context.state = reason or "blizzard-inspect-frame-mismatch"
        return false
    end
    context.host = host
    context.model = model
    context.inspectFrame = inspectFrame
    createContextFrames(context)
    host:HookScript("OnShow", onInspectShow)
    host:HookScript("OnHide", function()
        hideContext(context, "inspect-paperdoll-hidden", true)
    end)
    host:HookScript("OnSizeChanged", function()
        if context.block then
            applyPosition(context, context.currentX, context.currentY)
        end
    end)
    inspectFrame:HookScript("OnShow", function()
        if inspectPaperDollActive(context) then
            onInspectShow()
        end
    end)
    inspectFrame:HookScript("OnHide", function()
        hideContext(context, "inspect-hidden")
    end)
    safeSecureHook(nil, "InspectFrame_Show", function()
        bindInspectUnit(true)
    end, "InspectFrame_Show")
    safeSecureHook(nil, "InspectFrame_UnitChanged", function()
        bindInspectUnit(true)
    end, "InspectFrame_UnitChanged")
    safeSecureHook(nil, "InspectSwitchTabs", function(newID)
        if newID == 1 then
            onInspectShow()
        else
            hideContext(context, "inspect-tab-hidden", true)
        end
    end, "InspectSwitchTabs")
    context.bound = true
    context.state = "bound"
    if inspectPaperDollActive(context) then
        bindInspectUnit(false)
    end
    return true
end

local function localPublished(state)
    renderLocal(state)
end

local function remotePublished(guid, snapshot)
    local context = CONTEXTS.inspect
    if not context.bound then
        return
    end

    local unit, currentGUID = inspectUnit()
    if not unit then
        return
    end
    if currentGUID ~= guid then
        if context.guid == guid then
            hideContext(context, "inspect-identity-changed")
        end
        return
    end

    -- LibClassicInspector can publish after InspectFrame.unit changes but
    -- before Blizzard's outer InspectFrame_Show post-hook runs. Adopt that
    -- exact-GUID publication now so the later duplicate hook is harmless.
    if context.guid ~= guid then
        bindInspectUnit(false, snapshot)
        return
    end

    renderRemote(snapshot)
end

local function reapplyPositions()
    for _, context in pairs(CONTEXTS) do
        if context.bound and context.block then
            applyPosition(context, context.currentX, context.currentY)
            setInteractiveState(context)
        end
    end
end

local function onEvent(_, event, ...)
    if event == "ADDON_LOADED" then
        local loaded = ...
        if loaded == "Blizzard_CharacterUI" then
            bindCharacter()
            Frames.ApplySettings()
        elseif loaded == "Blizzard_InspectUI" then
            bindInspect()
            Frames.ApplySettings()
        end
    elseif event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
        reapplyPositions()
    elseif event == "PLAYER_REGEN_ENABLED" then
        local resume = Adapter.HandlePlayerRegenEnabled
        if type(resume) == "function" then
            pcall(resume)
        end
        Frames.ApplySettings()
    end
end

function Frames.Initialize(runtimeSettings)
    if type(runtimeSettings) ~= "table" then
        return false
    end
    settings = runtimeSettings
    if initialized then
        Frames.ApplySettings()
        return true
    end
    initialized = true
    localListener = localPublished
    remoteListener = remotePublished
    Scanner.Subscribe(localListener)
    Cache.Subscribe(remoteListener)
    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", onEvent)
    eventFrame:RegisterEvent("ADDON_LOADED")
    eventFrame:RegisterEvent("UI_SCALE_CHANGED")
    eventFrame:RegisterEvent("DISPLAY_SIZE_CHANGED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    bindCharacter()
    local addOns = _G.C_AddOns
    local inspectLoaded = false
    if type(addOns) == "table" and type(addOns.IsAddOnLoaded) == "function" then
        local ok, first, second = pcall(addOns.IsAddOnLoaded, "Blizzard_InspectUI")
        if ok then
            inspectLoaded = (second ~= nil and second or first) == true
        end
    elseif type(_G.IsAddOnLoaded) == "function" then
        local ok, first, second = pcall(_G.IsAddOnLoaded, "Blizzard_InspectUI")
        if ok then
            inspectLoaded = (second ~= nil and second or first) == true
        end
    end
    if inspectLoaded or type(_G.InspectFrame) == "table" then
        bindInspect()
    end
    Frames.ApplySettings()
    return true
end

function Frames.ApplySettings()
    if not initialized then
        return false
    end
    local requested = featureRequested()
    if not requested then
        hideContext(CONTEXTS.character, "equipment-summary-disabled")
        hideContext(CONTEXTS.inspect, "equipment-summary-disabled")
        return false
    end
    bindCharacter()
    if frameVisible(CONTEXTS.character.host) then
        local context = CONTEXTS.character
        local x, y = positionValue(context)
        if not context.visible then
            context.currentX, context.currentY = x, y
        end
        if context.guid ~= validateUnit("player") or context.localScanNeeded then
            onCharacterShow()
        else
            renderLocal(Scanner.GetCurrent())
        end
    end
    if CONTEXTS.inspect.bound and inspectPaperDollActive(CONTEXTS.inspect) then
        local context = CONTEXTS.inspect
        local x, y = positionValue(context)
        if not context.visible then
            context.currentX, context.currentY = x, y
        end
        local _, guid = inspectUnit()
        if guid ~= context.guid then
            bindInspectUnit(false)
        else
            renderRemote(Cache.Get(guid))
        end
    end
    reapplyPositions()
    return true
end

function Frames.ResetPositions()
    local equipment = equipmentSettings()
    if not equipment then
        return false
    end
    equipment.characterPosition = nil
    equipment.inspectPosition = nil
    for _, context in pairs(CONTEXTS) do
        cancelDrag(context)
        context.currentX = context.defaultX
        context.currentY = context.defaultY
        if context.block then
            applyPosition(context, context.currentX, context.currentY)
        end
    end
    return true
end

function Frames.HandleCompatibilityChanged(contextKey)
    local context = CONTEXTS[contextKey]
    if not context then
        return false
    end
    hideForEquipmentFailure(context, "equipment-compatibility-changed")
    return true
end

function Frames.RefreshContext(contextKey)
    if contextKey == "character" then
        return renderLocal(Scanner.GetCurrent())
    elseif contextKey == "inspect" then
        local context = CONTEXTS.inspect
        return context.guid and renderRemote(Cache.Get(context.guid)) or false
    end
    return false
end

function Frames.GetContextStatus(contextKey)
    local context = CONTEXTS[contextKey]
    if not context then
        return nil
    end
    return context.state,
        context.guid,
        context.generation,
        context.revisionID,
        context.currentX,
        context.currentY
end

function Frames.Shutdown()
    if localListener then
        Scanner.Unsubscribe(localListener)
    end
    if remoteListener then
        Cache.Unsubscribe(remoteListener)
    end
    localListener = nil
    remoteListener = nil
    hideContext(CONTEXTS.character, "addon-shutdown")
    hideContext(CONTEXTS.inspect, "addon-shutdown")
    initialized = false
end
