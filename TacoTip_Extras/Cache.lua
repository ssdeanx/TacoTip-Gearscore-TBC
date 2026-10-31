local _, namespace = ...

if type(namespace) ~= "table" then
    return
end

local Cache = {}
namespace.Cache = Cache

local MAX_ENTRIES = 32
-- Matches LibForeverInspector CACHE_REFRESH_DELAY (300s): the library re-inspects
-- on that cadence, so remote results must stay renderable for the same window.
-- At 10s the tooltip rows expired and vanished seconds after appearing.
local FRESHNESS_SECONDS = 300
local entries = {}
local listeners = {}
local accessSequence = 0
local revisionSequence = 0
local entryCount = 0

Cache.MAX_ENTRIES = MAX_ENTRIES
Cache.FRESHNESS_SECONDS = FRESHNESS_SECONDS

local function isPositiveInteger(value)
    return type(value) == "number"
        and value == value
        and value > 0
        and value % 1 == 0
        and value ~= math.huge
end

local function validGUID(guid)
    return type(guid) == "string" and guid ~= ""
end

local function clock()
    if type(GetTime) == "function" then
        local ok, value = pcall(GetTime)
        if ok and type(value) == "number" and value == value then
            return value
        end
    end
    return 0
end

local function clone(value, seen)
    if type(value) ~= "table" then
        return value
    end

    seen = seen or {}
    if seen[value] then
        return seen[value]
    end

    local copy = {}
    seen[value] = copy
    for key, child in pairs(value) do
        copy[key] = clone(child, seen)
    end
    return copy
end

local function sortedPending(pending)
    local itemIDs = {}
    for itemID in pairs(pending or {}) do
        if isPositiveInteger(itemID) then
            itemIDs[#itemIDs + 1] = itemID
        end
    end
    table.sort(itemIDs)
    return itemIDs
end

local function touch(entry)
    accessSequence = accessSequence + 1
    entry.accessOrder = accessSequence
end

local function makeSnapshot(entry)
    if type(entry) ~= "table" then
        return nil
    end

    local snapshot = {
        state = entry.state,
        generation = entry.generation,
        revisionID = entry.revisionID,
        startedAt = entry.startedAt,
        updatedAt = entry.updatedAt,
        completedAt = entry.completedAt,
        expiresAt = entry.expiresAt,
        pendingItemIDs = sortedPending(entry.pendingItemIDs),
        reason = entry.reason,
    }
    if entry.state == "complete" then
        snapshot.revision = clone(entry.revision)
        snapshot.result = clone(entry.result)
    end
    return snapshot
end

-- Listener fan-out failures (final hunter M-3).
--
-- The fan-out is pcall-guarded on purpose: a raising listener must not stop
-- the other listeners, and it must not abort the publish that is already
-- committed. But the guard made the failure INVISIBLE, and the cache entry
-- was already mutated when the listener raised -- so the update was lost with
-- nothing said and nothing counted. Counted here with the last message kept,
-- and printed by /ex debug (Core.lua).
local listenerErrors = 0
local lastListenerError = nil

local function notify(guid, snapshot)
    for listener in pairs(listeners) do
        local ok, err = pcall(listener, guid, clone(snapshot))
        if not ok then
            listenerErrors = listenerErrors + 1
            lastListenerError = tostring(err)
        end
    end
end

local function publishState(guid, entry)
    touch(entry)
    notify(guid, makeSnapshot(entry))
end

local function evictIfNeeded()
    if entryCount <= MAX_ENTRIES then
        return nil
    end

    local evictedGUID
    local evictedOrder
    for guid, entry in pairs(entries) do
        if evictedOrder == nil
            or entry.accessOrder < evictedOrder
            or (entry.accessOrder == evictedOrder and guid < evictedGUID) then
            evictedGUID = guid
            evictedOrder = entry.accessOrder
        end
    end

    if evictedGUID then
        local evicted = entries[evictedGUID]
        entries[evictedGUID] = nil
        entryCount = entryCount - 1
        notify(evictedGUID, {
            state = "unavailable",
            generation = evicted.generation,
            revisionID = evicted.revisionID,
            updatedAt = clock(),
            pendingItemIDs = {},
            reason = "cache-entry-evicted",
        })
    end
    return evictedGUID
end

local function expireIfNeeded(guid, entry)
    if entry.state ~= "complete" or clock() <= entry.expiresAt then
        return false
    end

    entry.state = "stale"
    entry.updatedAt = clock()
    entry.reason = "freshness-expired"
    entry.pendingItemIDs = {}
    publishState(guid, entry)
    return true
end

function Cache.Begin(guid, generation, reason)
    if not validGUID(guid) or not isPositiveInteger(generation) then
        return false
    end

    local at = clock()
    local entry = entries[guid]
    if entry and generation <= entry.generation then
        return false
    end
    if not entry then
        entry = {}
        entries[guid] = entry
        entryCount = entryCount + 1
    end

    entry.state = "pending"
    entry.generation = generation
    entry.revisionID = nil
    entry.startedAt = at
    entry.updatedAt = at
    entry.completedAt = nil
    entry.expiresAt = nil
    entry.revision = nil
    entry.result = nil
    entry.pendingItemIDs = {}
    entry.reason = reason or "scan-requested"
    publishState(guid, entry)
    return true, evictIfNeeded()
end

function Cache.SetPending(guid, generation, pendingItemIDs, reason)
    local entry = entries[guid]
    if not entry
        or entry.generation ~= generation
        or entry.state ~= "pending" then
        return false
    end

    entry.state = "pending"
    entry.updatedAt = clock()
    entry.completedAt = nil
    entry.expiresAt = nil
    entry.revision = nil
    entry.result = nil
    entry.pendingItemIDs = clone(pendingItemIDs or {})
    entry.reason = reason or "item-data-pending"
    publishState(guid, entry)
    return true
end

function Cache.PublishComplete(guid, generation, revision, result)
    local entry = entries[guid]
    if not entry
        or entry.generation ~= generation
        or entry.state ~= "pending"
        or type(revision) ~= "table"
        or type(result) ~= "table" then
        return false
    end

    local immutableRevision = clone(revision)
    local immutableResult = clone(result)
    local at = clock()
    revisionSequence = revisionSequence + 1

    entry.state = "complete"
    entry.revisionID = revisionSequence
    entry.updatedAt = at
    entry.completedAt = at
    entry.expiresAt = at + FRESHNESS_SECONDS
    entry.revision = immutableRevision
    entry.result = immutableResult
    entry.pendingItemIDs = {}
    entry.reason = nil
    publishState(guid, entry)
    return true
end

function Cache.PublishUnavailable(guid, generation, reason)
    local entry = entries[guid]
    if not entry
        or entry.generation ~= generation
        or entry.state ~= "pending" then
        return false
    end

    entry.state = "unavailable"
    entry.updatedAt = clock()
    entry.completedAt = nil
    entry.expiresAt = nil
    entry.revision = nil
    entry.result = nil
    entry.pendingItemIDs = {}
    entry.reason = reason or "scan-unavailable"
    publishState(guid, entry)
    return true
end

function Cache.IsCurrentGeneration(guid, generation)
    local entry = entries[guid]
    return entry ~= nil and entry.generation == generation
end

function Cache.Get(guid)
    local entry = entries[guid]
    if not entry then
        return nil
    end

    expireIfNeeded(guid, entry)
    touch(entry)
    return makeSnapshot(entry)
end

function Cache.GetFresh(guid)
    local snapshot = Cache.Get(guid)
    if snapshot and snapshot.state == "complete" then
        return snapshot
    end
    return nil
end

-- Re-evaluate every COMPLETE entry's stored revision and replace its result.
--
-- The level-70 gate is part of the SCORED result, not of the render, so a
-- settings change cannot be honoured by re-rendering what is already cached:
-- the cached result was computed under the old policy and would keep reading
-- the old verdict. The revision is the immutable INPUT, so re-running the
-- scorer over it is the honest way to answer the new setting -- no rescan, no
-- re-inspection, no new item data.
--
-- The evaluator is a function taking a revision and returning a new result.
-- Entries that are not complete, or whose revision is missing, are left
-- alone; an evaluator that raises leaves that entry alone too. Returns the
-- number of results replaced.
--
-- The access order is deliberately NOT touched: a settings change is not a
-- read, and moving the LRU order would evict an entry the user is looking at
-- for a reason that has nothing to do with freshness.
function Cache.ReevaluateAll(evaluator)
    if type(evaluator) ~= "function" then
        return 0
    end
    local replaced = 0
    for guid, entry in pairs(entries) do
        if entry.state == "complete" and type(entry.revision) == "table" then
            local ok, result = pcall(evaluator, entry.revision)
            if ok and type(result) == "table" then
                entry.result = clone(result)
                replaced = replaced + 1
                notify(guid, makeSnapshot(entry))
            end
        end
    end
    return replaced
end

function Cache.Subscribe(listener)
    if type(listener) ~= "function" then
        return false
    end
    listeners[listener] = true
    return true
end

function Cache.Unsubscribe(listener)
    listeners[listener] = nil
end

-- Debug accessor for the listener fan-out counter above (read-only). Printed
-- by /ex debug (Core.lua) and read by the harness.
function Cache.GetDebugState()
    return {
        listenerErrors = listenerErrors,
        lastListenerError = lastListenerError,
    }
end
