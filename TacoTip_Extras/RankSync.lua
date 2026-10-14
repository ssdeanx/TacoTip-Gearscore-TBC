local _, namespace = ...

if type(namespace) ~= "table" then
    return
end

local RankSync = {}
namespace.RankSync = RankSync

local PREFIX = "TACO_GS_SYNC"
local CHANNEL_NAME = "ttgssync"
local THROTTLE_INTERVAL = 1.5
local MAX_BURST = 3

local sendQueue = {}
local tokens = MAX_BURST
local lastTokenTime = 0
local channelID = nil

local syncFrame = rawget(_G, "CreateFrame") and _G.CreateFrame("Frame")

local function getClock()
    local g = _G
    if type(g["GetTime"]) == "function" then
        local ok, t = pcall(g["GetTime"])
        if ok and type(t) == "number" then
            return t
        end
    end
    return 0
end

local function registerPrefix()
    local cChat = rawget(_G, "C_ChatInfo")
    if type(cChat) == "table" and type(cChat.RegisterAddonMessagePrefix) == "function" then
        pcall(cChat.RegisterAddonMessagePrefix, PREFIX)
    elseif type(rawget(_G, "RegisterAddonMessagePrefix")) == "function" then
        pcall(_G["RegisterAddonMessagePrefix"], PREFIX)
    end
end

local function suppressChannelFromChat(cName)
    local g = _G
    local removeGroup = rawget(g, "ChatFrame_RemoveChannelGroup")
    if type(removeGroup) ~= "function" then return end
    for i = 1, 10 do
        local frameName = "ChatFrame" .. tostring(i)
        local cf = rawget(g, frameName)
        if cf then
            pcall(removeGroup, cf, cName)
        end
    end
end

local function joinSyncChannel()
    local g = _G
    local joinFunc = rawget(g, "JoinChannelByName")
    if type(joinFunc) == "function" then
        pcall(joinFunc, CHANNEL_NAME, nil, nil)
    end
    local getChan = rawget(g, "GetChannelName")
    if type(getChan) == "function" then
        local ok, id = pcall(getChan, CHANNEL_NAME)
        if ok and type(id) == "number" and id > 0 then
            channelID = id
            suppressChannelFromChat(CHANNEL_NAME)
        end
    end
end

function RankSync.SerializeRecord(rec)
    if type(rec) ~= "table" then return nil end
    local parts = {
        "R",
        rec.guid or "",
        rec.name or "",
        rec.faction or "Unknown",
        tostring(rec.classID or 0),
        tostring(rec.class or "UNKNOWN"),
        tostring(rec.specName or ""),
        tostring(rec.gs or 0),
        tostring(rec.ilvl or 0),
        tostring(rec.timestamp or 0),
    }
    return table.concat(parts, ";")
end

-- Split on ";" keeping EMPTY fields.
--
-- The obvious implementation is `payload:gmatch("([^;]+)")`, and it is wrong:
-- `+` requires at least one character, so an empty field is skipped instead of
-- returned. "a;;b" yields two parts, not three.
--
-- That silently discarded real records. specName is frequently empty (an
-- unscanned or spec-less player) and faction is empty when unknown, and a
-- dropped field shifts every later field and takes the part count below the
-- minimum -- so the ENTIRE record was rejected and the player never synced.
-- Measured: payload "R;P1;Bob;Horde;1;WARRIOR;;3821;124.5;1759000000" (an empty
-- spec) returned nil and was thrown away.
--
-- This is why the format is parsed by position and every field is optional in
-- the middle: an empty string is data, not absence.
local function splitFields(payload)
    local fields, start, length = {}, 1, #payload
    while true do
        local separator = payload:find(";", start, true)
        if not separator then
            fields[#fields + 1] = payload:sub(start, length)
            break
        end
        fields[#fields + 1] = payload:sub(start, separator - 1)
        start = separator + 1
    end
    return fields
end

function RankSync.DeserializeRecord(payload)
    if type(payload) ~= "string" then return nil end
    local parts = splitFields(payload)
    if #parts < 10 or parts[1] ~= "R" then
        return nil
    end
    return {
        guid = parts[2],
        name = parts[3],
        faction = parts[4],
        classID = tonumber(parts[5]) or 0,
        class = parts[6],
        specName = parts[7],
        gs = tonumber(parts[8]) or 0,
        ilvl = tonumber(parts[9]) or 0,
        timestamp = tonumber(parts[10]) or 0,
        source = "sync",
    }
end

local function rawSend(msg, chatType, target)
    local g = _G
    local cChat = rawget(g, "C_ChatInfo")
    if type(cChat) == "table" and type(cChat.SendAddonMessage) == "function" then
        pcall(cChat.SendAddonMessage, PREFIX, msg, chatType, target)
    elseif type(rawget(g, "SendAddonMessage")) == "function" then
        pcall(g["SendAddonMessage"], PREFIX, msg, chatType, target)
    end
end

local function processQueue()
    local now = getClock()
    local elapsed = now - lastTokenTime
    if elapsed > THROTTLE_INTERVAL then
        local newTokens = math.floor(elapsed / THROTTLE_INTERVAL)
        tokens = math.min(MAX_BURST, tokens + newTokens)
        lastTokenTime = now
    end

    while tokens > 0 and #sendQueue > 0 do
        local item = table.remove(sendQueue, 1)
        rawSend(item.msg, item.chatType, item.target)
        tokens = tokens - 1
    end
end

function RankSync.Enqueue(msg, chatType, target)
    if type(msg) ~= "string" or msg == "" then return end
    if #sendQueue >= 50 then
        table.remove(sendQueue, 1)
    end
    sendQueue[#sendQueue + 1] = {
        msg = msg,
        chatType = chatType or "GUILD",
        target = target,
    }
    processQueue()
end

function RankSync.BroadcastRecord(record)
    if type(record) ~= "table" then return end
    local payload = RankSync.SerializeRecord(record)
    if not payload then return end

    local g = _G
    -- 1. Broadcast to Group
    local inGroup = rawget(g, "IsInGroup")
    if type(inGroup) == "function" and inGroup() then
        local inRaid = rawget(g, "IsInRaid")
        local chan = (type(inRaid) == "function" and inRaid()) and "RAID" or "PARTY"
        RankSync.Enqueue(payload, chan)
    end

    -- 2. Broadcast to Guild
    local inGuild = rawget(g, "IsInGuild")
    if type(inGuild) == "function" and inGuild() then
        RankSync.Enqueue(payload, "GUILD")
    end

    -- 3. Broadcast to Hidden Custom Channel
    if channelID and channelID > 0 then
        RankSync.Enqueue(payload, "CHANNEL", tostring(channelID))
    end
end

function RankSync.QueueInspectRecord(record)
    if type(record) ~= "table" then return end
    if namespace.RankDB and type(namespace.RankDB.StoreRecord) == "function" then
        local ok = namespace.RankDB.StoreRecord(record)
        if ok then
            RankSync.BroadcastRecord(record)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Query and response
-- ---------------------------------------------------------------------------
--
-- Until this existed, a client only ever received what other clients HAPPENED
-- to broadcast -- which is when their own gear changed. A fresh install
-- therefore stayed empty until enough people changed gear near it, and the
-- leaderboard looked broken on a server where nobody was re-gearing.
--
-- Message types now:
--
--   R  a record, unsolicited (gear changed) -- the original behaviour
--   Q  a query: "re-send what you know", sent on every resync
--   S  a response carrying the sender's OWN record
--   T  a response carrying up to two of the sender's BEST records
--
-- Sized against the hard limit. An addon message caps at 255 bytes and a
-- serialized record is roughly 90, so "T;<request>;<rec>;<rec>" lands near 210
-- and fits. Three records would not, which is why the digest is two.
--
-- Flood control is the interesting problem: a query is a broadcast, so every
-- client on the channel hears it and every one of them would answer at once.
-- Two guards, and both are needed:
--
--   * RESPOND_INTERVAL -- a client answers at most one query per 20 seconds,
--     so a burst of joins produces one round of answers rather than one per
--     joiner.
--   * JITTER -- answers are delayed by a random 1-4s, so fifty clients do not
--     all enqueue at the same instant and blow through the token bucket.
--
-- Without the interval, ten people logging in together is ten times the traffic;
-- without the jitter, the queue's 50-message cap evicts most of it and the
-- responses are simply lost.
local RESPOND_INTERVAL = 20
local RESPOND_JITTER_MIN, RESPOND_JITTER_MAX = 1.0, 4.0

local lastRespondAt = 0
local requestCounter = 0

-- Short by design: it rides in every response, and the 255-byte budget is spent
-- on records, not on identity. Four hex characters distinguish concurrent
-- requests, which is all it has to do -- it is not a durable identifier.
local function makeRequestId()
    requestCounter = (requestCounter + 1) % 65521
    local seconds = math.floor(getClock())
    return ("%x%x"):format(seconds % 0xFFFF, requestCounter % 0xFF)
end

local function broadcastToAll(msg)
    local g = _G
    local inGroup = rawget(g, "IsInGroup")
    if type(inGroup) == "function" and inGroup() then
        local inRaid = rawget(g, "IsInRaid")
        local chan = (type(inRaid) == "function" and inRaid()) and "RAID" or "PARTY"
        RankSync.Enqueue(msg, chan)
    end
    local inGuild = rawget(g, "IsInGuild")
    if type(inGuild) == "function" and inGuild() then
        RankSync.Enqueue(msg, "GUILD")
    end
    if channelID and channelID > 0 then
        RankSync.Enqueue(msg, "CHANNEL", tostring(channelID))
    end
end

local function ownGUID()
    local g = _G
    local fn = rawget(g, "UnitGUID")
    if type(fn) ~= "function" then
        return nil
    end
    local ok, guid = pcall(fn, "player")
    if ok and type(guid) == "string" and guid ~= "" then
        return guid
    end
    return nil
end

-- Ask the channel to re-send. Safe to call often: it is one short message, and
-- peers throttle their answers themselves.
function RankSync.RequestSync()
    local id = makeRequestId()
    broadcastToAll("Q;" .. id)
    return id
end

local function respondToQuery(requestId)
    local now = getClock()
    if lastRespondAt > 0 and (now - lastRespondAt) < RESPOND_INTERVAL then
        return false
    end
    lastRespondAt = now

    local db = namespace.RankDB
    if type(db) ~= "table" then
        return false
    end

    -- Our own record, sent unconditionally. It is the one record we are certain
    -- is current, and it is what makes "everyone shows up on the board"
    -- work -- each client contributes itself.
    local guid = ownGUID()
    local mine = guid and type(db.GetRecord) == "function" and db.GetRecord(guid) or nil
    if type(mine) == "table" then
        local payload = RankSync.SerializeRecord(mine)
        if payload then
            RankSync.Enqueue("S;" .. requestId .. ";" .. payload, "CHANNEL",
                channelID and tostring(channelID) or nil)
        end
    end

    -- A short digest of the best records we hold, so a fresh client learns the
    -- top of the ladder without waiting for every holder to broadcast. Capped at
    -- two per message and four in total: the point is to seed, not to mirror the
    -- database over the wire.
    if type(db.GetTopRecords) == "function" then
        local top = db.GetTopRecords(4)
        if type(top) == "table" and #top > 0 then
            for index = 1, #top, 2 do
                local first = RankSync.SerializeRecord(top[index])
                local second = top[index + 1] and RankSync.SerializeRecord(top[index + 1]) or nil
                if first then
                    local msg = "T;" .. requestId .. ";" .. first
                    if second then
                        msg = msg .. ";" .. second
                    end
                    RankSync.Enqueue(msg, "CHANNEL",
                        channelID and tostring(channelID) or nil)
                end
            end
        end
    end
    return true
end

-- Rebuild one record from a run of already-split fields.
--
-- The field order MUST match SerializeRecord exactly. It is duplicated rather
-- than shared because the wire format is the more stable of the two: if the
-- serializer's field order ever changes, BOTH functions have to change together
-- and a reader needs to see that, which a shared helper would hide.
local function recordFromParts(parts, start)
    if parts[start] ~= "R" then
        return nil
    end
    local specName = parts[start + 6] or ""
    local class = parts[start + 5] or "UNKNOWN"
    if class == "" then class = "UNKNOWN" end
    return {
        guid = parts[start + 1],
        name = parts[start + 2],
        faction = parts[start + 3],
        classID = tonumber(parts[start + 4]) or 0,
        class = class,
        specName = specName,
        gs = tonumber(parts[start + 7]) or 0,
        ilvl = tonumber(parts[start + 8]) or 0,
        timestamp = tonumber(parts[start + 9]) or 0,
        source = "sync",
    }
end

-- Fields per serialized record, counting the leading "R".
local RECORD_FIELDS = 10

-- Store every record carried by an S or T payload.
--
-- The payload is NOT a list of "R;..." strings -- the records share the outer
-- ";" delimiter, so a record is a RUN OF TEN FIELDS inside one flat split, not a
-- single element. Splitting and reading element 3 would yield the bare letter
-- "R" and silently store nothing, which is the failure this comment exists to
-- prevent. Hence the fixed stride, and hence RECORD_FIELDS being derived from
-- SerializeRecord's layout rather than guessed.
local function ingestRecords(payload)
    local parts = splitFields(payload)
    local stored, seen = 0, 0
    local index = 3
    while index + RECORD_FIELDS - 1 <= #parts do
        if parts[index] ~= "R" then
            break
        end
        seen = seen + 1
        local record = recordFromParts(parts, index)
        if record and namespace.RankDB
            and type(namespace.RankDB.StoreRecord) == "function" then
            if namespace.RankDB.StoreRecord(record) then
                stored = stored + 1
            end
        end
        index = index + RECORD_FIELDS
    end
    return stored, seen
end

-- Dispatch one inbound payload by its leading type character.
--
-- Published as RankSync.HandlePayload because the event handler is only
-- reachable through a real frame in game, and a protocol that can only be
-- exercised by logging in is a protocol nothing verifies.
local function handlePayload(payload)
    local kind = payload:sub(1, 1)

    if kind == "R" then
        local rec = RankSync.DeserializeRecord(payload)
        if rec and namespace.RankDB
            and type(namespace.RankDB.StoreRecord) == "function" then
            namespace.RankDB.StoreRecord(rec)
        end
        return
    end

    if kind == "Q" then
        local requestId = payload:match("^Q;([^;]+)") or ""
        -- Jittered, so ten clients joining together do not answer in the same
        -- instant and evict each other through the send queue's cap.
        local delay = RESPOND_JITTER_MIN
            + math.random() * (RESPOND_JITTER_MAX - RESPOND_JITTER_MIN)
        local cTimer = rawget(_G, "C_Timer")
        if type(cTimer) == "table" and type(cTimer.After) == "function" then
            cTimer.After(delay, function() respondToQuery(requestId) end)
        else
            respondToQuery(requestId)
        end
        return
    end

    if kind == "S" or kind == "T" then
        ingestRecords(payload)
        return
    end
end

RankSync.HandlePayload = handlePayload
RankSync.RESPOND_INTERVAL = RESPOND_INTERVAL

-- Join the channel and then ASK. A query sent before the join lands reaches
-- nobody, and GetChannelName can lag the join by a frame or two, so the first
-- attempt is retried once rather than fired into a channel id that is still nil.
local function joinThenQuery()
    joinSyncChannel()
    if channelID and channelID > 0 then
        RankSync.RequestSync()
        return
    end
    local cTimer = rawget(_G, "C_Timer")
    if type(cTimer) == "table" and type(cTimer.After) == "function" then
        cTimer.After(4.0, function()
            joinSyncChannel()
            if channelID and channelID > 0 then
                RankSync.RequestSync()
            end
        end)
    end
end

-- Sync is re-driven on every transition that can change who is around you.
--
-- PLAYER_ENTERING_WORLD alone covers login, /reload and leaving an instance --
-- Blizzard fires it for each of those -- but it does NOT fire on a loading
-- screen caused by zoning into a new open-world area, and it fires BEFORE the
-- channel prefix is registered on a cold login. Those two gaps are why the
-- leaderboard looked like it only synced sometimes:
--
--   PLAYER_LOGIN            earliest point the prefix can be registered, so
--                           broadcasts from other players are not dropped while
--                           we are still waiting for the world to load
--   PLAYER_ENTERING_WORLD   login, /reload, instance enter and exit
--   ZONE_CHANGED_NEW_AREA   open-world zone changes, which fire no other event
--
-- Every one of them funnels through one throttled path: a loading-screen burst
-- fires these in quick succession, and an unthrottled re-broadcast would put
-- three identical messages on the channel in a second.
local SYNC_THROTTLE_SECONDS = 30
local lastSyncAt = 0

-- `force` bypasses the throttle. The automatic triggers must never bypass it --
-- that is the whole point of the throttle -- but a user-initiated refresh is a
-- different thing: the player asked, so waiting 30 seconds for a throttle they
-- cannot see would read as broken. The event handler passes nothing.
local function syncNow(force)
    local now = time and time() or 0
    if not force and now > 0 and lastSyncAt > 0
        and (now - lastSyncAt) < SYNC_THROTTLE_SECONDS then
        return false
    end
    lastSyncAt = now

    registerPrefix()
    local cTimer = rawget(_G, "C_Timer")
    if type(cTimer) == "table" and type(cTimer.After) == "function" then
        cTimer.After(4.0, joinThenQuery)
    else
        joinThenQuery()
    end
    return true
end

RankSync.SyncNow = syncNow
RankSync.SYNC_THROTTLE_SECONDS = SYNC_THROTTLE_SECONDS

local function onEvent(_, event, arg1, arg2)
    if event == "CHAT_MSG_ADDON" then
        if arg1 == PREFIX and type(arg2) == "string" then
            handlePayload(arg2)
        end
    elseif event == "PLAYER_LOGIN" then
        registerPrefix()
    elseif event == "PLAYER_ENTERING_WORLD"
        or event == "ZONE_CHANGED_NEW_AREA" then
        syncNow()
    end
end

if syncFrame then
    syncFrame:RegisterEvent("CHAT_MSG_ADDON")
    syncFrame:RegisterEvent("PLAYER_LOGIN")
    syncFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    syncFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    syncFrame:SetScript("OnEvent", onEvent)
    syncFrame:SetScript("OnUpdate", function()
        if #sendQueue > 0 then
            processQueue()
        end
    end)
end
