local _, namespace = ...

local Scoring = {}

if type(namespace) == "table" then
    namespace.Scoring = Scoring
end

local REQUIRED_SLOTS = {
    1, 2, 3, 5, 6, 7, 8, 9, 10,
    11, 12, 13, 14, 15, 16, 17, 18,
}

local FORMULAS = {
    [1] = { offset = 0, divisor = 2.25 },
    [2] = { offset = 8, divisor = 2 },
    [3] = { offset = 0.75, divisor = 1.8 },
    [4] = { offset = 26, divisor = 1.2 },
}

local QUALITY_RULES = {
    [0] = { formulaQuality = 2, scale = 0.005 },
    [1] = { formulaQuality = 2, scale = 0.005 },
    [2] = { formulaQuality = 2, scale = 1 },
    [3] = { formulaQuality = 3, scale = 1 },
    [4] = { formulaQuality = 4, scale = 1 },
    [5] = { formulaQuality = 4, scale = 1.3 },
    [7] = { formulaQuality = 3, scale = 1, scoringItemLevel = 187.05 },
}

local SLOT_POLICIES = {
    INVTYPE_RELIC = { weight = 0.3164, currentEnchant = false, potentialEnchant = false },
    INVTYPE_TRINKET = { weight = 0.5625, currentEnchant = false, potentialEnchant = false },
    INVTYPE_2HWEAPON = { weight = 2, currentEnchant = true, potentialEnchant = true },
    INVTYPE_WEAPONMAINHAND = { weight = 1, currentEnchant = true, potentialEnchant = true },
    INVTYPE_WEAPONOFFHAND = { weight = 1, currentEnchant = true, potentialEnchant = true },
    INVTYPE_RANGED = { weight = 0.3164, currentEnchant = true, potentialEnchant = "conditional" },
    INVTYPE_THROWN = { weight = 0.3164, currentEnchant = false, potentialEnchant = false },
    INVTYPE_RANGEDRIGHT = { weight = 0.3164, currentEnchant = true, potentialEnchant = "conditional" },
    INVTYPE_SHIELD = { weight = 1, currentEnchant = true, potentialEnchant = true },
    INVTYPE_WEAPON = { weight = 1, currentEnchant = true, potentialEnchant = true },
    INVTYPE_HOLDABLE = { weight = 1, currentEnchant = false, potentialEnchant = false },
    INVTYPE_HEAD = { weight = 1, currentEnchant = true, potentialEnchant = true },
    INVTYPE_NECK = { weight = 0.5625, currentEnchant = false, potentialEnchant = false },
    INVTYPE_SHOULDER = { weight = 0.75, currentEnchant = true, potentialEnchant = true },
    INVTYPE_CHEST = { weight = 1, currentEnchant = true, potentialEnchant = true },
    INVTYPE_ROBE = { weight = 1, currentEnchant = true, potentialEnchant = true },
    INVTYPE_WAIST = { weight = 0.75, currentEnchant = false, potentialEnchant = false },
    INVTYPE_LEGS = { weight = 1, currentEnchant = true, potentialEnchant = true },
    INVTYPE_FEET = { weight = 0.75, currentEnchant = true, potentialEnchant = true },
    INVTYPE_WRIST = { weight = 0.5625, currentEnchant = true, potentialEnchant = true },
    INVTYPE_HAND = { weight = 0.75, currentEnchant = true, potentialEnchant = true },
    INVTYPE_FINGER = { weight = 0.5625, currentEnchant = false, potentialEnchant = false },
    INVTYPE_CLOAK = { weight = 0.5625, currentEnchant = true, potentialEnchant = true },
    INVTYPE_BODY = { weight = 0, currentEnchant = false, potentialEnchant = false },
    INVTYPE_TABARD = { weight = 0, currentEnchant = false, potentialEnchant = false },
    INVTYPE_AMMO = { weight = 0, currentEnchant = false, potentialEnchant = false },
    INVTYPE_BAG = { weight = 0, currentEnchant = false, potentialEnchant = false },
}

local HUNTER_MELEE = {
    INVTYPE_2HWEAPON = true,
    INVTYPE_WEAPONMAINHAND = true,
    INVTYPE_WEAPONOFFHAND = true,
    INVTYPE_WEAPON = true,
    INVTYPE_HOLDABLE = true,
}

local HUNTER_RANGED = {
    INVTYPE_RANGED = true,
    INVTYPE_RANGEDRIGHT = true,
}

local SOCKET_DERIVED_ITEM_FIELDS = {
    "emptyScoreBearingSockets",
    "completion",
    "potentialDelta",
}

local LEVEL_GATED_ITEM_FIELDS = {
    "missingEnchant",
    "missingEnchantDelta",
    "emptyScoreBearingSockets",
    "completion",
    "potentialDelta",
}

local STATUS_PRIORITY = {
    unknown = 1,
    pending = 2,
    unavailable = 3,
    stale = 4,
    contradictory = 5,
}

local SCORE_SCALE = 1.8618
local ENCHANT_MULTIPLIER = 1.05
local GEM_BONUS = 5
local MAIN_HAND_SLOT = 16
local OFF_HAND_SLOT = 17

local function isFiniteNumber(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function isInteger(value)
    return isFiniteNumber(value) and value % 1 == 0
end

local function isNonnegativeInteger(value)
    return isInteger(value) and value >= 0
end

local function isPositiveInteger(value)
    return isInteger(value) and value > 0
end

local function makeBlocker(status, reason)
    return { status = status, reason = reason }
end

local function mergeBlocker(current, candidate)
    if not candidate then
        return current
    end
    if not current or STATUS_PRIORITY[candidate.status] > STATUS_PRIORITY[current.status] then
        return candidate
    end
    return current
end

local function readCell(cell, label, validator)
    if type(cell) ~= "table" then
        return nil, makeBlocker("unknown", label .. "-missing")
    end

    if cell.status ~= "complete" then
        if STATUS_PRIORITY[cell.status] then
            return nil, makeBlocker(cell.status, cell.reason or label)
        end
        return nil, makeBlocker("contradictory", label .. "-status")
    end

    if validator and not validator(cell.value) then
        return nil, makeBlocker("contradictory", label .. "-value")
    end

    return cell.value, nil
end

local function completeMetric(value)
    return { status = "complete", value = value }
end

local function blockedMetric(blocker)
    return { status = blocker.status, value = nil, reason = blocker.reason }
end

local function metricFrom(value, blocker)
    if blocker then
        return blockedMetric(blocker)
    end
    return completeMetric(value)
end

local function splitColonFields(payload)
    local fields = {}
    local startIndex = 1

    while true do
        local colonIndex = string.find(payload, ":", startIndex, true)
        if not colonIndex then
            fields[#fields + 1] = string.sub(payload, startIndex)
            break
        end
        fields[#fields + 1] = string.sub(payload, startIndex, colonIndex - 1)
        startIndex = colonIndex + 1
    end

    return fields
end

local function parseEnhancementField(field)
    if field == "" then
        return 0, "blank"
    end
    if not string.match(field, "^%d+$") then
        return nil, nil
    end

    local value = tonumber(field)
    if not isNonnegativeInteger(value) then
        return nil, nil
    end
    if value == 0 then
        return 0, "zero"
    end
    return value, "positive"
end

local function extractPayload(nativeLink)
    if type(nativeLink) ~= "string" or nativeLink == "" then
        return nil
    end
    if string.sub(nativeLink, 1, 5) == "item:" then
        if string.find(nativeLink, "|", 1, true) then
            return nil
        end
        return nativeLink
    end
    local payload = string.match(
        nativeLink,
        "^|c%x%x%x%x%x%x%x%x|H(item:[^|]+)|h[^|]*|h|r$"
    )
    if payload then
        return payload
    end
    return string.match(nativeLink, "^|H(item:[^|]+)|h[^|]*|h$")
end

function Scoring.ParseEquippedLink(nativeLink, expectedItemID)
    if not isPositiveInteger(expectedItemID) then
        return nil, "invalid-expected-item-id"
    end

    local payload = extractPayload(nativeLink)
    if not payload then
        return nil, "missing-item-payload"
    end

    local fields = splitColonFields(payload)
    if #fields ~= 20 or fields[1] ~= "item" or not string.match(fields[2] or "", "^%d+$") then
        return nil, "malformed-item-payload"
    end

    local itemID = tonumber(fields[2])
    if not isPositiveInteger(itemID) then
        return nil, "invalid-item-id"
    end
    if itemID ~= expectedItemID then
        return nil, "item-id-mismatch"
    end

    local permanentEnchantID, permanentEncoding = parseEnhancementField(fields[3])
    if permanentEnchantID == nil then
        return nil, "invalid-permanent-enchant-field"
    end

    local gemIDs = {}
    local gemEncodings = {}
    for index = 1, 3 do
        local gemID, encoding = parseEnhancementField(fields[index + 3])
        if gemID == nil then
            return nil, "invalid-gem-field-" .. index
        end
        gemIDs[index] = gemID
        gemEncodings[index] = encoding
    end

    return {
        itemID = itemID,
        permanentEnchantID = permanentEnchantID,
        permanentEnchantEncoding = permanentEncoding,
        gemIDs = gemIDs,
        gemEncodings = gemEncodings,
        fieldCount = #fields,
    }
end

local function validateThreeIDs(values)
    if type(values) ~= "table" then
        return false
    end
    for index = 1, 3 do
        if not isNonnegativeInteger(values[index]) then
            return false
        end
    end
    for key in pairs(values) do
        if not isInteger(key) or key < 1 or key > 3 then
            return false
        end
    end
    return true
end

local function validateSockets(value)
    if type(value) ~= "table"
        or not isNonnegativeInteger(value.capacity)
        or type(value.gemIDs) ~= "table" then
        return false
    end

    for index = 1, value.capacity do
        if not isNonnegativeInteger(value.gemIDs[index]) then
            return false
        end
    end
    for key in pairs(value.gemIDs) do
        if not isInteger(key) or key < 1 or key > value.capacity then
            return false
        end
    end
    return true
end

local function readLink(item)
    local itemID, itemIDBlocker = readCell(item.itemID, "item-id", isPositiveInteger)
    local nativeLink, linkBlocker = readCell(item.nativeLink, "native-link", function(value)
        return type(value) == "string"
    end)
    local blocker = mergeBlocker(itemIDBlocker, linkBlocker)
    if blocker then
        return nil, blocker
    end

    local parsed, reason = Scoring.ParseEquippedLink(nativeLink, itemID)
    if not parsed then
        return nil, makeBlocker("contradictory", reason)
    end
    return parsed, nil
end

local function readPermanentEnchant(item, parsed, linkBlocker)
    local permanentEnchantID, permanentBlocker = readCell(
        item.permanentEnchantID,
        "permanent-enchant",
        isNonnegativeInteger
    )
    local blocker = mergeBlocker(linkBlocker, permanentBlocker)
    if blocker then
        return nil, blocker
    end
    if permanentEnchantID ~= parsed.permanentEnchantID then
        return nil, makeBlocker("contradictory", "permanent-enchant-mismatch")
    end
    return permanentEnchantID, nil
end

local function readScoreGems(item, parsed, linkBlocker)
    local gemIDs, gemBlocker = readCell(item.scoreGemIDs, "score-gems", validateThreeIDs)
    local blocker = mergeBlocker(linkBlocker, gemBlocker)
    if blocker then
        return nil, blocker
    end
    for index = 1, 3 do
        if gemIDs[index] ~= parsed.gemIDs[index] then
            return nil, makeBlocker("contradictory", "score-gem-mismatch-" .. index)
        end
    end
    return gemIDs, nil
end

local function calculateBaseItem(item, classToken, classBlocker, equipLoc, equipLocBlocker)
    local quality, qualityBlocker = readCell(item.quality, "quality", isNonnegativeInteger)
    local itemLevel, levelBlocker = readCell(item.scoringItemLevel, "scoring-item-level", function(value)
        return isFiniteNumber(value) and value >= 0
    end)
    local blocker = mergeBlocker(classBlocker, equipLocBlocker)
    blocker = mergeBlocker(blocker, qualityBlocker)
    blocker = mergeBlocker(blocker, levelBlocker)
    if blocker then
        return { blocker = blocker }
    end

    local qualityRule = QUALITY_RULES[quality]
    local slotPolicy = SLOT_POLICIES[equipLoc]
    if not qualityRule or not slotPolicy then
        return { value = 0, earlyReturn = true, equipLoc = equipLoc, slotPolicy = slotPolicy }
    end

    local formula = FORMULAS[qualityRule.formulaQuality]
    local formulaLevel = qualityRule.scoringItemLevel or itemLevel
    local value = math.floor(
        ((formulaLevel - formula.offset) / formula.divisor)
            * slotPolicy.weight
            * SCORE_SCALE
            * qualityRule.scale
    )
    if value < 0 then
        value = 0
    end

    if classToken == "HUNTER" then
        if HUNTER_MELEE[equipLoc] then
            value = math.floor(value * 0.3164)
        elseif HUNTER_RANGED[equipLoc] then
            value = math.floor(value * 5.3224)
        end
    end

    return { value = value, earlyReturn = false, equipLoc = equipLoc, slotPolicy = slotPolicy }
end

local function calculateCurrentItem(baseItem, permanentEnchantID, permanentBlocker, gemIDs, gemBlocker)
    if baseItem.blocker then
        return nil, baseItem.blocker
    end
    if baseItem.earlyReturn then
        return 0, nil
    end

    local blocker = mergeBlocker(permanentBlocker, gemBlocker)
    if blocker then
        return nil, blocker
    end

    local value = baseItem.value
    if baseItem.slotPolicy.currentEnchant and permanentEnchantID > 0 then
        value = math.floor(value * ENCHANT_MULTIPLIER)
    end
    for index = 1, 3 do
        if gemIDs[index] > 0 then
            value = value + GEM_BONUS
        end
    end
    return value, nil
end

local function readPotentialEnchantEligibility(item, equipLoc, equipLocBlocker)
    if equipLocBlocker then
        return nil, equipLocBlocker
    end

    local slotPolicy = SLOT_POLICIES[equipLoc]
    if not slotPolicy or slotPolicy.potentialEnchant == false then
        return false, nil
    end
    if slotPolicy.potentialEnchant == true then
        return true, nil
    end

    return readCell(
        item.scopeCapablePhysicalRanged,
        "scope-capable-physical-ranged",
        function(value) return type(value) == "boolean" end
    )
end

local function readSocketEvidence(item, parsed)
    local sockets, socketBlocker = readCell(item.sockets, "sockets", validateSockets)
    if socketBlocker then
        return nil, socketBlocker
    end

    if parsed then
        for index = 1, 3 do
            local socketGemID = 0
            if index <= sockets.capacity then
                socketGemID = sockets.gemIDs[index]
            end
            if socketGemID ~= parsed.gemIDs[index] then
                return nil, makeBlocker("contradictory", "socket-gem-mismatch-" .. index)
            end
        end
    end

    local filled = 0
    local emptyScoreBearing = 0
    for index = 1, sockets.capacity do
        if sockets.gemIDs[index] > 0 then
            filled = filled + 1
        elseif index <= 3 then
            emptyScoreBearing = emptyScoreBearing + 1
        end
    end

    return {
        capacity = sockets.capacity,
        filled = filled,
        emptyScoreBearing = emptyScoreBearing,
    }, nil
end

local function evaluateOccupiedItem(item, classToken, classBlocker)
    local equipLoc, equipLocBlocker = readCell(item.equipLoc, "equip-location", function(value)
        return type(value) == "string" and value ~= ""
    end)
    local baseItem = calculateBaseItem(item, classToken, classBlocker, equipLoc, equipLocBlocker)

    local parsed, linkBlocker = readLink(item)
    local permanentEnchantID, permanentBlocker = readPermanentEnchant(item, parsed, linkBlocker)
    local gemIDs, gemBlocker = readScoreGems(item, parsed, linkBlocker)
    local currentValue, currentBlocker = calculateCurrentItem(
        baseItem,
        permanentEnchantID,
        permanentBlocker,
        gemIDs,
        gemBlocker
    )

    local eligible, eligibilityBlocker = readPotentialEnchantEligibility(item, equipLoc, equipLocBlocker)
    local enchantOpportunityBlocker = eligibilityBlocker
    local missingEnchant = false
    local enchantOpportunity = 0
    local filledEnchantOpportunity = 0

    if not eligibilityBlocker and eligible then
        enchantOpportunityBlocker = mergeBlocker(enchantOpportunityBlocker, permanentBlocker)
        if not enchantOpportunityBlocker then
            enchantOpportunity = 1
            if permanentEnchantID > 0 then
                filledEnchantOpportunity = 1
            else
                missingEnchant = true
            end
        end
    end

    local missingEnchantDeltaBlocker = enchantOpportunityBlocker
    local missingEnchantDelta = 0
    if not missingEnchantDeltaBlocker and missingEnchant then
        missingEnchantDeltaBlocker = mergeBlocker(missingEnchantDeltaBlocker, baseItem.blocker)
        if not missingEnchantDeltaBlocker and not baseItem.earlyReturn then
            missingEnchantDelta = math.floor(baseItem.value * ENCHANT_MULTIPLIER) - baseItem.value
        end
    end

    local socketEvidence, socketBlocker = readSocketEvidence(item, parsed)
    local completionBlocker = mergeBlocker(enchantOpportunityBlocker, socketBlocker)
    local completionValue
    if not completionBlocker then
        completionValue = {
            filled = filledEnchantOpportunity + socketEvidence.filled,
            opportunities = enchantOpportunity + socketEvidence.capacity,
        }
    end

    local potentialDeltaBlocker = mergeBlocker(missingEnchantDeltaBlocker, socketBlocker)
    local potentialDelta
    if not potentialDeltaBlocker then
        potentialDelta = missingEnchantDelta
        if not baseItem.earlyReturn then
            potentialDelta = potentialDelta + socketEvidence.emptyScoreBearing * GEM_BONUS
        end
    end

    return {
        equipLoc = equipLoc,
        equipLocBlocker = equipLocBlocker,
        base = metricFrom(baseItem.value, baseItem.blocker),
        current = metricFrom(currentValue, currentBlocker),
        missingEnchant = metricFrom(missingEnchant, enchantOpportunityBlocker),
        missingEnchantDelta = metricFrom(missingEnchantDelta, missingEnchantDeltaBlocker),
        emptyScoreBearingSockets = metricFrom(
            socketEvidence and socketEvidence.emptyScoreBearing or nil,
            socketBlocker
        ),
        completion = metricFrom(completionValue, completionBlocker),
        potentialDelta = metricFrom(potentialDelta, potentialDeltaBlocker),
    }
end

local function completionValue(filled, opportunities)
    if opportunities == 0 then
        return {
            filled = 0,
            opportunities = 0,
            ratio = nil,
            displayPercent = nil,
            category = "neutral",
        }
    end

    local category
    if filled == opportunities then
        category = "green"
    elseif filled * 10 >= opportunities * 9 then
        category = "yellow"
    elseif filled * 10 >= opportunities * 7 then
        category = "orange"
    else
        category = "red"
    end

    return {
        filled = filled,
        opportunities = opportunities,
        ratio = filled / opportunities,
        displayPercent = math.floor(100 * filled / opportunities + 0.5),
        category = category,
    }
end

local function occupancyBlocker(slot)
    if type(slot) ~= "table" then
        return makeBlocker("unknown", "slot-missing")
    end
    if slot.state == "occupied" or slot.state == "confirmed-empty" then
        return nil
    end
    if slot.state == "unknown" then
        local status = slot.status or "unknown"
        if STATUS_PRIORITY[status] then
            return makeBlocker(status, slot.reason or "occupancy")
        end
        return makeBlocker("contradictory", "occupancy-status")
    end
    return makeBlocker("contradictory", "occupancy-state")
end

local function enhancementPolicy(revision, policy)
    local restrictToLevel70 = true
    if policy ~= nil then
        if type(policy) ~= "table" or (
            policy.restrictEnhancementMetricsToLevel70 ~= nil
            and type(policy.restrictEnhancementMetricsToLevel70) ~= "boolean"
        ) then
            return nil, makeBlocker("contradictory", "enhancement-policy")
        end
        if policy.restrictEnhancementMetricsToLevel70 ~= nil then
            restrictToLevel70 = policy.restrictEnhancementMetricsToLevel70
        end
    end

    if not restrictToLevel70 then
        return false, nil
    end

    local level, levelBlocker = readCell(revision.level, "player-level", isNonnegativeInteger)
    if levelBlocker then
        return nil, levelBlocker
    end
    return level ~= 70, nil
end

local function blockMetricWith(metric, blocker)
    if not blocker then
        return metric
    end
    if blocker.status ~= "suppressed" and metric.status ~= "complete" then
        blocker = mergeBlocker(blocker, metric)
    end
    return blockedMetric(blocker)
end

local function gateItemEnhancementMetrics(result, socketBlocker, policyBlocker)
    for _, slotID in ipairs(REQUIRED_SLOTS) do
        local itemResult = result.items[slotID]
        if itemResult and itemResult.state == "occupied" then
            for _, field in ipairs(SOCKET_DERIVED_ITEM_FIELDS) do
                itemResult[field] = blockMetricWith(itemResult[field], socketBlocker)
            end
            for _, field in ipairs(LEVEL_GATED_ITEM_FIELDS) do
                itemResult[field] = blockMetricWith(itemResult[field], policyBlocker)
            end
        end
    end
end

function Scoring.Evaluate(revision, policy)
    local result = { metrics = {}, items = {} }
    if type(revision) ~= "table" or type(revision.slots) ~= "table" then
        local blocker = makeBlocker("unknown", "revision")
        result.metrics.baseGS = blockedMetric(blocker)
        result.metrics.gearScore = blockedMetric(blocker)
        result.metrics.potentialGS = blockedMetric(blocker)
        result.metrics.delta = blockedMetric(blocker)
        result.metrics.completion = blockedMetric(blocker)
        result.metrics.averageItemLevel = blockedMetric(blocker)
        return result
    end

    local classToken, classBlocker = readCell(revision.classToken, "class-token", function(value)
        return type(value) == "string" and value ~= ""
    end)
    local socketCapability, socketCapabilityBlocker = readCell(
        revision.socketCapability,
        "socket-capability",
        function(value) return type(value) == "boolean" end
    )
    if not socketCapabilityBlocker and not socketCapability then
        socketCapabilityBlocker = makeBlocker("unavailable", "socket-capability")
    end

    local suppressed, enhancementPolicyBlocker = enhancementPolicy(revision, policy)
    local baseBlocker = classBlocker
    local currentBlocker = classBlocker
    local potentialEvidenceBlocker = socketCapabilityBlocker
    local completionBlocker = socketCapabilityBlocker
    local averageBlocker
    local baseTotal = 0
    local currentTotal = 0
    local potentialDeltaTotal = 0
    local filledOpportunities = 0
    local totalOpportunities = 0
    local averageTotal = 0

    for _, slotID in ipairs(REQUIRED_SLOTS) do
        local slot = revision.slots[slotID]
        local slotBlocker = occupancyBlocker(slot)
        if slotBlocker then
            baseBlocker = mergeBlocker(baseBlocker, slotBlocker)
            currentBlocker = mergeBlocker(currentBlocker, slotBlocker)
            potentialEvidenceBlocker = mergeBlocker(potentialEvidenceBlocker, slotBlocker)
            completionBlocker = mergeBlocker(completionBlocker, slotBlocker)
            averageBlocker = mergeBlocker(averageBlocker, slotBlocker)
            result.items[slotID] = { state = slot and slot.state or "unknown" }
        elseif slot.state == "confirmed-empty" then
            result.items[slotID] = { state = "confirmed-empty" }
        else
            local itemResult = evaluateOccupiedItem(slot, classToken, classBlocker)
            itemResult.state = "occupied"
            result.items[slotID] = itemResult

            if itemResult.base.status == "complete" then
                baseTotal = baseTotal + itemResult.base.value
            else
                baseBlocker = mergeBlocker(baseBlocker, itemResult.base)
            end

            if itemResult.current.status == "complete" then
                currentTotal = currentTotal + itemResult.current.value
            else
                currentBlocker = mergeBlocker(currentBlocker, itemResult.current)
            end

            if itemResult.potentialDelta.status == "complete" then
                potentialDeltaTotal = potentialDeltaTotal + itemResult.potentialDelta.value
            else
                potentialEvidenceBlocker = mergeBlocker(potentialEvidenceBlocker, itemResult.potentialDelta)
            end

            if itemResult.completion.status == "complete" then
                filledOpportunities = filledOpportunities + itemResult.completion.value.filled
                totalOpportunities = totalOpportunities + itemResult.completion.value.opportunities
            else
                completionBlocker = mergeBlocker(completionBlocker, itemResult.completion)
            end

            local effectiveItemLevel, averageItemBlocker = readCell(
                slot.effectiveItemLevel,
                "effective-item-level",
                function(value) return isFiniteNumber(value) and value >= 0 end
            )
            if averageItemBlocker then
                averageBlocker = mergeBlocker(averageBlocker, averageItemBlocker)
            else
                averageTotal = averageTotal + effectiveItemLevel
            end

            if slotID == MAIN_HAND_SLOT and itemResult.equipLocBlocker then
                averageBlocker = mergeBlocker(averageBlocker, itemResult.equipLocBlocker)
            end
        end
    end

    local mainHand = revision.slots[MAIN_HAND_SLOT]
    local offHand = revision.slots[OFF_HAND_SLOT]
    if type(mainHand) == "table" and mainHand.state == "occupied" then
        local mainEquipLoc, mainEquipBlocker = readCell(
            mainHand.equipLoc,
            "main-hand-equip-location",
            function(value) return type(value) == "string" and value ~= "" end
        )
        averageBlocker = mergeBlocker(averageBlocker, mainEquipBlocker)
        if not mainEquipBlocker and mainEquipLoc == "INVTYPE_2HWEAPON" then
            if type(offHand) == "table" and offHand.state == "confirmed-empty" then
                local mainEffectiveLevel, mainLevelBlocker = readCell(
                    mainHand.effectiveItemLevel,
                    "main-hand-effective-item-level",
                    function(value) return isFiniteNumber(value) and value >= 0 end
                )
                averageBlocker = mergeBlocker(averageBlocker, mainLevelBlocker)
                if not mainLevelBlocker then
                    averageTotal = averageTotal + mainEffectiveLevel
                end
            elseif type(offHand) == "table" and offHand.state == "occupied" then
                averageBlocker = mergeBlocker(
                    averageBlocker,
                    makeBlocker("contradictory", "two-hand-with-offhand")
                )
            end
        end
    end

    result.metrics.baseGS = metricFrom(baseTotal, baseBlocker)
    result.metrics.gearScore = metricFrom(currentTotal, currentBlocker)

    local potentialBlocker = mergeBlocker(currentBlocker, potentialEvidenceBlocker)
    potentialBlocker = mergeBlocker(potentialBlocker, enhancementPolicyBlocker)
    completionBlocker = mergeBlocker(completionBlocker, enhancementPolicyBlocker)

    if suppressed then
        local levelBlocker = makeBlocker("suppressed", "level-policy")
        result.metrics.potentialGS = blockedMetric(levelBlocker)
        result.metrics.delta = blockedMetric(levelBlocker)
        result.metrics.completion = blockedMetric(levelBlocker)
    else
        local potentialValue
        if not potentialBlocker then
            potentialValue = currentTotal + potentialDeltaTotal
        end
        result.metrics.potentialGS = metricFrom(potentialValue, potentialBlocker)
        result.metrics.delta = metricFrom(potentialDeltaTotal, potentialBlocker)
        result.metrics.completion = metricFrom(
            completionBlocker and nil or completionValue(filledOpportunities, totalOpportunities),
            completionBlocker
        )
    end

    local averageValue
    if not averageBlocker then
        local raw = averageTotal / #REQUIRED_SLOTS
        averageValue = { raw = raw, display = math.floor(raw + 0.5) }
    end
    result.metrics.averageItemLevel = metricFrom(averageValue, averageBlocker)

    local itemPolicyBlocker = enhancementPolicyBlocker
    if suppressed then
        itemPolicyBlocker = makeBlocker("suppressed", "level-policy")
    end
    gateItemEnhancementMetrics(result, socketCapabilityBlocker, itemPolicyBlocker)

    return result
end

return Scoring
