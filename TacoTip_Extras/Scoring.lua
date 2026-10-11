local _, namespace = ...

local Scoring = {}

if type(namespace) == "table" then
    namespace.Scoring = Scoring
end

local REQUIRED_SLOTS = {
    1, 2, 3, 5, 6, 7, 8, 9, 10,
    11, 12, 13, 14, 15, 16, 17, 18,
}

-- The base GearScore is NOT computed here.
--
-- This file used to carry its own copy of the formula (FORMULAS, QUALITY_RULES,
-- SCORE_SCALE, HUNTER_MELEE/HUNTER_RANGED) and it was WRONG: TacoTip's
-- gearscore.lua selects between formula table B and formula table A above
-- ilvl 120, and this copy only had B. Measured divergence on TBC:
-- HEAD rar 4 ilvl 200 -> ours 310, the reimplementation 269; a 2H at ilvl 200
-- -> ours 621, the reimplementation 539. So the add-on rendered a DIFFERENT
-- number than the tooltip it was attached to.
--
-- The enhancer's genuine value-add over TacoTip is small and must survive:
-- enchant bonus (x1.05), gem bonus (+5 per socket) and the equipped-comparison
-- lines. Those are deltas ON TOP of a score, so they belong here; the score
-- itself belongs to TT_GS. Every base value now comes from
-- TT_GS:GetItemScore / TT_GS:GetItemHunterScore, which is the same call the
-- tooltip makes, so the two can never disagree.
--
-- SLOT_POLICIES keeps only what is about the SLOT rather than the arithmetic:
-- which slots can be enchanted, and for potential purposes whether a physical
-- ranged slot is scope-capable. The `weight` column is gone -- that was the
-- duplicated formula.
local SLOT_POLICIES = {
    INVTYPE_RELIC = { currentEnchant = false, potentialEnchant = false },
    INVTYPE_TRINKET = { currentEnchant = false, potentialEnchant = false },
    INVTYPE_2HWEAPON = { currentEnchant = true, potentialEnchant = true },
    INVTYPE_WEAPONMAINHAND = { currentEnchant = true, potentialEnchant = true },
    INVTYPE_WEAPONOFFHAND = { currentEnchant = true, potentialEnchant = true },
    INVTYPE_RANGED = { currentEnchant = true, potentialEnchant = "conditional" },
    INVTYPE_THROWN = { currentEnchant = false, potentialEnchant = false },
    INVTYPE_RANGEDRIGHT = { currentEnchant = true, potentialEnchant = "conditional" },
    INVTYPE_SHIELD = { currentEnchant = true, potentialEnchant = true },
    INVTYPE_WEAPON = { currentEnchant = true, potentialEnchant = true },
    INVTYPE_HOLDABLE = { currentEnchant = false, potentialEnchant = false },
    INVTYPE_HEAD = { currentEnchant = true, potentialEnchant = true },
    INVTYPE_NECK = { currentEnchant = false, potentialEnchant = false },
    INVTYPE_SHOULDER = { currentEnchant = true, potentialEnchant = true },
    INVTYPE_CHEST = { currentEnchant = true, potentialEnchant = true },
    INVTYPE_ROBE = { currentEnchant = true, potentialEnchant = true },
    INVTYPE_WAIST = { currentEnchant = false, potentialEnchant = false },
    INVTYPE_LEGS = { currentEnchant = true, potentialEnchant = true },
    INVTYPE_FEET = { currentEnchant = true, potentialEnchant = true },
    INVTYPE_WRIST = { currentEnchant = true, potentialEnchant = true },
    INVTYPE_HAND = { currentEnchant = true, potentialEnchant = true },
    INVTYPE_FINGER = { currentEnchant = false, potentialEnchant = false },
    INVTYPE_CLOAK = { currentEnchant = true, potentialEnchant = true },
    INVTYPE_BODY = { currentEnchant = false, potentialEnchant = false },
    INVTYPE_TABARD = { currentEnchant = false, potentialEnchant = false },
    INVTYPE_AMMO = { currentEnchant = false, potentialEnchant = false },
    INVTYPE_BAG = { currentEnchant = false, potentialEnchant = false },
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

-- The one place this add-on obtains a GearScore.
--
-- Three rules govern this function:
--
--   1. It asks TacoTip, never itself. TT_GS:GetItemScore is the same call the
--      tooltip makes, and GetItemHunterScore is the hunter-adjusted variant, so
--      the number rendered here and the number rendered on the tooltip are the
--      same number by construction rather than by agreement between two copies
--      of a formula.
--
--   2. A nil TT_GS is a BLOCKER, not a zero. Scoring "works" without TacoTip
--      only in the sense that every score is a lie; reporting 0 would render
--      confidently and be wrong.
--
--   3. The pre-fetched info table is preferred. GetItemScoreFromInfo performs
--      no GetItemInfo call of its own; GetItemScore does one per item per
--      evaluation, which on a 17-slot re-scan is 17 redundant cache lookups.
--      The Scanner already holds the info it read, so it is carried through.
local function baseScoreFromTacoTip(nativeLink, info, isHunter)
    local gearScore = _G.TT_GS
    if type(gearScore) ~= "table" then
        return nil, "taco-tip-unavailable"
    end

    local score
    if isHunter then
        if type(gearScore.GetItemHunterScore) == "function" then
            local ok, value = pcall(
                gearScore.GetItemHunterScore,
                gearScore,
                nativeLink,
                info
            )
            if not ok then
                return nil, "taco-tip-score-failed"
            end
            score = value
        elseif type(gearScore.GetItemScore) == "function" then
            local ok, value = pcall(
                gearScore.GetItemScore,
                gearScore,
                nativeLink
            )
            if not ok then
                return nil, "taco-tip-score-failed"
            end
            score = value
        else
            return nil, "taco-tip-score-unavailable"
        end
    elseif type(info) == "table" and type(gearScore.GetItemScoreFromInfo) == "function" then
        local ok, value = pcall(gearScore.GetItemScoreFromInfo, gearScore, info)
        if not ok then
            return nil, "taco-tip-score-failed"
        end
        score = value
    elseif type(gearScore.GetItemScore) == "function" then
        local ok, value = pcall(gearScore.GetItemScore, gearScore, nativeLink)
        if not ok then
            return nil, "taco-tip-score-failed"
        end
        score = value
    else
        return nil, "taco-tip-score-unavailable"
    end

    -- GetItemScore answers 0 for an item it cannot score (unrecognised slot,
    -- still-loading data). That is indistinguishable from a genuine zero, so
    -- anything non-integer or negative is treated as a failure to read rather
    -- than silently summed as 0.
    if not isNonnegativeInteger(score) then
        return nil, "taco-tip-score-invalid"
    end
    return score, nil
end

local function calculateBaseItem(item, classToken, classBlocker, equipLoc, equipLocBlocker)
    local blocker = mergeBlocker(classBlocker, equipLocBlocker)
    local slotPolicy = SLOT_POLICIES[equipLoc]
    local nativeLink, linkBlocker = readCell(
        item.nativeLink,
        "native-link",
        function(value) return type(value) == "string" end
    )
    blocker = mergeBlocker(blocker, linkBlocker)
    if blocker then
        return { blocker = blocker }
    end

    if not slotPolicy then
        -- A slot TacoTip does not score (body, tabard, ammo, bag). Not an
        -- error: there is simply nothing to enhance.
        return { value = 0, earlyReturn = true, equipLoc = equipLoc, slotPolicy = slotPolicy }
    end

    local score, scoreReason = baseScoreFromTacoTip(
        nativeLink,
        item.itemInfoValue,
        classToken == "HUNTER"
    )
    if score == nil then
        return {
            blocker = makeBlocker("unavailable", scoreReason or "taco-tip-score-unavailable"),
        }
    end

    return { value = score, earlyReturn = false, equipLoc = equipLoc, slotPolicy = slotPolicy }
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
