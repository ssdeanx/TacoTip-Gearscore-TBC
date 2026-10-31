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

-- The outbound size door. An addon message dies at 255 bytes on the engine
-- side, and the audit re-measured a 319-byte S and a 327-byte record once the
-- planned fields land (expansion audit §3.2). 240 leaves the "S;<id>;" /
-- "T;<id>;" framing real headroom and is enforced at ENQUEUE time: a message
-- that cannot be sent must never enter the queue, because a queued too-long
-- message is a send failure discovered only after it evicts real traffic (the
-- queue is FIFO with a 50-message cap).
local MAX_PAYLOAD_BYTES = 240

-- SendAddonMessageResult values rawSend reacts to. Verified identical on all
-- five client branches at
-- /home/sam/wow-ui-source/Interface/AddOns/Blizzard_APIDocumentationGenerated/
-- ChatConstantsDocumentation.lua:151-163 (forever branch :154-166):
--   0 Success, 3 AddonMessageThrottle, 7 InvalidChannel, 8 ChannelThrottle.
-- Everything else is counted as sendOther; a nil result is the classic-family
-- legacy SendAddonMessage global that returns nothing at all.
local RESULT_SUCCESS = 0
local RESULT_THROTTLE = 3
local RESULT_INVALID_CHANNEL = 7
local RESULT_CHANNEL_THROTTLE = 8

local sendQueue = {}
local tokens = MAX_BURST
local lastTokenTime = 0

-- Channel transport state machine. "channelID is a number" used to be the only
-- fact carried (one global, set once at join); but on the Classic family the
-- join can succeed and addon traffic on the channel can still fail -- so
-- whether the channel CARRIES is a different, separately-verified fact
-- (expansion audit §6.2 Stage 1 item 2; Blizzard removed addon traffic on
-- channels there). The state is proven by a real send of a one-line probe
-- whose payload kind peers ignore silently.
local channel = {
    state = "idle",          -- idle (never probed) | probing | active | dead
    id = nil,                -- resolved GetChannelName number, or nil
    failures = 0,            -- consecutive throttle strikes observed on probes
    nextProbeAt = 0,         -- uptime after which a dead channel may re-probe
}
local PROBE_RECHECK_SECONDS = 120
local PROBE_MAX_THROTTLE_STRIKES = 3
local probeCounter = 0

-- Outcome counters, surfaced through /ex debug (audit §6.2 Stage 1 item 3).
-- Lazy keys: every bucket starts empty and only appears once it fires.
local outcomes = {}

-- The last reason a peer record was refused, and the last kind of message the
-- send queue evicted (final hunter M-5 / M-6). Both are the "why", and a
-- count without a reason is not something a user can act on.
local lastRecordRejectedReason = nil
local lastEvictedKind = nil

-- The first-login hole (earlier review §3.6, expansion audit §3.1): the local
-- record only ever travels when gear CHANGES. A fresh install joined the sync
-- channel with nothing on the wire, so peers who logged in after it had no way
-- to ever see that player on their board. The fix is a memory: whenever a
-- record broadcast runs while the channel cannot carry, remember it, and the
-- moment the channel is shown to carry again, push the local record ONCE
-- (audit §6.2 Stage 1 item 5).
local pendingSelfBroadcast = false
local selfBroadcastDone = false

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

local function countOutcome(name)
    outcomes[name] = (outcomes[name] or 0) + 1
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
    -- Re-resolve from zero every join instead of layering onto the last good
    -- value: a join that lands without effect (GetChannelName still 0/nil) used
    -- to leave the STALE id live, so addon traffic kept being aimed at a
    -- channel we were no longer in.
    local resolved = nil
    local getChan = rawget(g, "GetChannelName")
    if type(getChan) == "function" then
        local ok, id = pcall(getChan, CHANNEL_NAME)
        if ok and type(id) == "number" and id > 0 then
            resolved = id
        end
    end
    channel.id = resolved
    if resolved then
        suppressChannelFromChat(CHANNEL_NAME)
    end
end

-- The channel participates only while its id is known and the state machine
-- has not killed it. Every send site routes through this one gate.
local function channelSendTarget()
    if not (channel.id and channel.id > 0) then return nil end
    if channel.state == "dead" then return nil end
    return tostring(channel.id)
end

-- Class token by numeric id, the inverse of Scanner's CLASS_IDS. The wire
-- carries classID (canonical, language-independent); the class-name string
-- stays OFF the wire. Ingest derives the token so storage, indices and the
-- tooltip keep working; render prefers the same map with the stored string
-- as fallback.
local CLASS_TOKEN_BY_ID = {
    [1] = "WARRIOR", [2] = "PALADIN", [3] = "HUNTER", [4] = "ROGUE",
    [5] = "PRIEST", [6] = "DEATHKNIGHT", [7] = "SHAMAN", [8] = "MAGE",
    [9] = "WARLOCK", [10] = "MONK", [11] = "DRUID", [12] = "DEMONHUNTER",
    [13] = "EVOKER",
}

local function classTokenFromID(classID)
    return CLASS_TOKEN_BY_ID[classID] or "UNKNOWN"
end

-- The wire carries twelve fields per R record under an explicit version token:
--   R;<ver>;<guid>;<name>;<classID>;<gs>;<ilvl>;<timestamp>;<specID>;<guild>;<level>;<pvpRank>;<arena>
--
-- (wire diet, pre-release: faction, realm, the class-name string and the
-- spec-name string all ride OFF the wire. Spec rides as a numeric id, empty
-- when unknown, with its icon+name derived at render; the class token is
-- derived from classID at ingest so storage and the tooltip never see a gap.
-- Stage 3 appends the cheap row fields: guild (sanitized, hard-truncated to
-- 24 chars, "" when unknown -- never "Unknown"-filled), level (0 unknown),
-- pvpRank (Classic Era honor rank number, 0 none/unknown) and arena
-- (TBC/Wrath inspectable best, 0 none/unknown; Retail/Forever always 0).)
local WIRE_VERSION = "2"

function RankSync.SerializeRecord(rec)
    if type(rec) ~= "table" then return nil end
    local specID = math.floor(tonumber(rec.specID) or 0)
    local level = math.floor(tonumber(rec.level) or 0)
    if level < 0 then level = 0 end
    local pvpRank = math.floor(tonumber(rec.pvpRank) or 0)
    if pvpRank < 0 then pvpRank = 0 end
    local arena = math.floor(tonumber(rec.arena) or 0)
    if arena < 0 then arena = 0 end
    local parts = {
        "R",
        WIRE_VERSION,
        rec.guid or "",
        rec.name or "",
        tostring(rec.classID or 0),
        tostring(rec.gs or 0),
        tostring(rec.ilvl or 0),
        tostring(rec.timestamp or 0),
        (specID > 0) and tostring(specID) or "",
        rec.guild or "",
        tostring(level),
        tostring(pvpRank),
        tostring(arena),
    }
    return table.concat(parts, ";")
end

-- Fields per serialized record, counting the leading "R" and the version
-- token.
--
-- Duplicated from SerializeRecord's layout on purpose (the wire format is the
-- more stable of the two; see recordFromParts below for why it is not
-- shared). Any stride change ships under a NEW version token, never by
-- reusing this one: a record that does not carry the version this client
-- writes is refused rather than inferred.
local RECORD_FIELDS = 13

-- Split on ";" keeping EMPTY fields.
--
-- The obvious implementation is `payload:gmatch("([^;]+)")`, and it is wrong:
-- `+` requires at least one character, so an empty field is skipped instead of
-- returned. "a;;b" yields two parts, not three.
--
-- That silently discarded real records. specID is frequently empty (an
-- unscanned or spec-less player has no numeric spec), and a dropped field
-- shifts every later field and takes the part count below the minimum -- so
-- the ENTIRE record was rejected and the player never synced.
-- Measured: payload "R;1;P1;Bob;1;3821;124.5;1759000000;" (an empty
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
    if #parts < RECORD_FIELDS or parts[1] ~= "R" then
        return nil
    end
    if parts[2] ~= WIRE_VERSION then
        -- Old unversioned strides (pre-diet 10- and 11-field) and any unknown
        -- future version: refused cleanly, never raised, counted for
        -- /ex debug. The wire is pre-release, so there are no compat shims.
        countOutcome("versionReject")
        return nil
    end
    local classID = tonumber(parts[5]) or 0
    return {
        guid = parts[3],
        name = parts[4],
        classID = classID,
        class = classTokenFromID(classID),
        specID = tonumber(parts[9]) or 0,
        gs = tonumber(parts[6]) or 0,
        ilvl = tonumber(parts[7]) or 0,
        timestamp = tonumber(parts[8]) or 0,
        -- Stage-3 cheap fields. Guild rides through as the raw string (the
        -- store sanitizes + truncates; "" is unguilded-or-unknown, never
        -- "Unknown"-filled). Level/pvpRank/arena are 0 when unknown.
        guild = parts[10] or "",
        level = tonumber(parts[11]) or 0,
        pvpRank = tonumber(parts[12]) or 0,
        arena = tonumber(parts[13]) or 0,
        source = "sync",
    }
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

-- A boolean-ish read of a client global that may not exist on this client.
-- Handles real clients where IsInGuild() returns 1 rather than true.
local function flagIsOn(name)
    local fn = rawget(_G, name)
    return type(fn) == "function" and fn() and true or false
end

-- Send one message, capture the outcome, and bucket it.
--
-- C_ChatInfo.SendAddonMessage returns a SendAddonMessageResult on modern
-- clients (ChatInfoDocumentation.lua:358-372); the classic-family legacy
-- SendAddonMessage global returns nothing, which arrives here as nil -- counted
-- sendNoInfo rather than an error, because a nil result usually means "sent".
-- The pre-Stage-1 code pcall'd and ignored the result entirely, so a throttled
-- or refused send was indistinguishable from a delivered one.
local function rawSend(msg, chatType, target)
    local g = _G
    local result
    local cChat = rawget(g, "C_ChatInfo")
    if type(cChat) == "table" and type(cChat.SendAddonMessage) == "function" then
        local ok, r = pcall(cChat.SendAddonMessage, PREFIX, msg, chatType, target)
        if not ok then
            countOutcome("sendError")
            return "sendError"
        end
        result = r
    elseif type(rawget(g, "SendAddonMessage")) == "function" then
        local ok = pcall(g["SendAddonMessage"], PREFIX, msg, chatType, target)
        if not ok then
            countOutcome("sendError")
            return "sendError"
        end
        result = nil
    else
        countOutcome("sendError")
        return "sendError"
    end

    local outcome
    if result == RESULT_SUCCESS then
        outcome = "sendSuccess"
    elseif result == RESULT_THROTTLE then
        outcome = "sendThrottle"
    elseif result == RESULT_INVALID_CHANNEL then
        outcome = "sendInvalidChannel"
    elseif result == RESULT_CHANNEL_THROTTLE then
        outcome = "sendChannelThrottle"
    elseif result == nil then
        outcome = "sendNoInfo"
    else
        outcome = "sendOther"
    end
    countOutcome(outcome)
    return outcome
end

-- One group transport per broadcast. RAID does not deliver inside raid
-- instances and battlegrounds the way the group expects -- the instance
-- partitions the raid channel -- and INSTANCE_CHAT is the documented chat type
-- for the group inside an instance (warcraft.wiki.gg/wiki/
-- API_C_ChatInfo.SendAddonMessage, chat types; expansion audit §6.2 item 2).
local function groupChatType()
    local g = _G
    local inGroup = rawget(g, "IsInGroup")
    if type(inGroup) ~= "function" or not inGroup() then return nil end
    local inRaid = rawget(g, "IsInRaid")
    if not (type(inRaid) == "function" and inRaid()) then
        return "PARTY"
    end
    local instanceType
    local inInstance = rawget(g, "IsInInstance")
    if type(inInstance) == "function" then
        local ok, inInst, kind = pcall(inInstance)
        if ok and inInst and type(kind) == "string" then
            instanceType = kind
        end
    end
    if instanceType == "raid" or instanceType == "pvp" or instanceType == "arena" then
        return "INSTANCE_CHAT"
    end
    return "RAID"
end

-- The once-per-session self re-broadcast. Guards: only while armed, only once,
-- only when the channel is currently carryable, and only if we hold a record
-- for our own GUID. When the record is missing the arm stays set so the next
-- channel-visible moment can still satisfy the promise.
local function flushSelfBroadcast()
    if not pendingSelfBroadcast or selfBroadcastDone then return end
    local target = channelSendTarget()
    if not target then return end
    local guid = ownGUID()
    local db = namespace.RankDB
    local rec = guid and type(db) == "table" and type(db.GetRecord) == "function"
        and db.GetRecord(guid) or nil
    if type(rec) ~= "table" then return end
    local payload = RankSync.SerializeRecord(rec)
    if not payload then return end
    selfBroadcastDone = true
    pendingSelfBroadcast = false
    countOutcome("selfRebroadcast")
    RankSync.Enqueue(payload, "CHANNEL", target)
end

-- Probe state transitions. A probe is the proof: the send result of a real tiny
-- message tells us how the channel treats addon traffic right now.
local function markChannelDead(now)
    channel.state = "dead"
    channel.failures = 0
    channel.nextProbeAt = now + PROBE_RECHECK_SECONDS
end

local function noteProbeOutcome(outcome, now)
    if outcome == "sendSuccess" or outcome == "sendNoInfo" then
        channel.state = "active"
        channel.failures = 0
        flushSelfBroadcast()
    elseif outcome == "sendInvalidChannel" then
        -- InvalidChannel=7: this client family does not carry addon traffic on
        -- custom channels at all. Dead, until a later recheck says otherwise.
        markChannelDead(now)
    elseif outcome == "sendThrottle" or outcome == "sendChannelThrottle" then
        -- Transient refusals cannot kill the channel by themselves, but
        -- sustained ones mean it is unusable for now: count strikes.
        channel.failures = channel.failures + 1
        if channel.failures >= PROBE_MAX_THROTTLE_STRIKES then
            markChannelDead(now)
        end
    end
    -- Any other outcome proves nothing either way; leave the state as-is and
    -- let the next join re-probe.
end

-- A probe rides the same queue as real traffic but is inert to peers: any
-- payload whose first character is not R/Q/S/T/G/D is ignored by
-- handlePayload. It never evicts queued real traffic, and it is skipped
-- while a queue cap is already full.
local function enqueueChannelProbe()
    probeCounter = probeCounter + 1
    countOutcome("probes")
    if #sendQueue >= 50 then return end
    sendQueue[#sendQueue + 1] = {
        msg = "P;" .. tostring(probeCounter),
        chatType = "CHANNEL",
        target = tostring(channel.id),
        isProbe = true,
    }
end

local function armChannelProbe()
    if not (channel.id and channel.id > 0) then return end
    if channel.state == "active" then return end
    local now = getClock()
    if channel.state == "dead" and now < channel.nextProbeAt then return end
    channel.state = "probing"
    enqueueChannelProbe()
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
        local item = sendQueue[1]
        local outcome = rawSend(item.msg, item.chatType, item.target)
        if outcome == "sendThrottle" or outcome == "sendChannelThrottle" then
            -- The client refused to put this message on the wire, so it lives
            -- on in the queue: the pre-Stage-1 code popped the item and lost it
            -- (a permanent, silent send loss -- audit §6.2, "a throttled send
            -- is counted and re-queued"). No token is spent, and the next
            -- processQueue tick -- with its refilled bucket -- retries it.
            countOutcome("requeued")
            break
        end
        table.remove(sendQueue, 1)
        tokens = tokens - 1
        if item.isProbe then
            noteProbeOutcome(outcome, now)
        elseif item.chatType == "CHANNEL"
            and outcome == "sendInvalidChannel" then
            -- A real send also learns the channel is dead; react like a probe.
            markChannelDead(now)
        end
    end
end

function RankSync.Enqueue(msg, chatType, target)
    if type(msg) ~= "string" or msg == "" then return end
    -- 240-byte door: refuse instead of enqueueing what the wire cannot take.
    -- The digest path compacts its own message to a single record first; only
    -- messages with no shorter form survive here and are counted.
    if #msg > MAX_PAYLOAD_BYTES then
        countOutcome("enqueueOversize")
        return
    end
    if #sendQueue >= 50 then
        -- M-6: the 50-message cap used to evict the oldest queued message
        -- with nothing said and nothing counted -- a peer that never appears
        -- was undiagnosable. Counted, with the kind of the evicted message
        -- kept so the loss can be named.
        local evicted = table.remove(sendQueue, 1)
        countOutcome("queueEvicted")
        lastEvictedKind = (evicted and evicted.chatType) or "unknown"
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

    -- 1. Broadcast to Group (PARTY / RAID / INSTANCE_CHAT, one transport).
    local chan = groupChatType()
    if chan then
        RankSync.Enqueue(payload, chan)
    end

    -- 2. Broadcast to Guild
    if flagIsOn("IsInGuild") then
        RankSync.Enqueue(payload, "GUILD")
    end

    -- 3. Broadcast to the hidden custom channel, only while it carries. When it
    --    cannot, arm the once-per-session self re-broadcast -- peers who log in
    --    later would otherwise have no path to ever learn this record, because
    --    the record only travels on gear change (first-login hole).
    local target = channelSendTarget()
    if target then
        selfBroadcastDone = true
        pendingSelfBroadcast = false
        RankSync.Enqueue(payload, "CHANNEL", target)
    else
        pendingSelfBroadcast = true
    end
end

-- Scan-time realm gate (storage-expansion audit §6.2 Stage 2 item 4).
--
-- A scanned player can be someone the client sees across a realm boundary --
-- battleground, arena, cross-realm party. Filing that record into the LOCAL
-- realm table would put a foreign player on our board with a standing they
-- did not earn on this realm, which is exactly what realm-keyed standings
-- exist to prevent. Two passes:
--
--   * our own GUID (the self-scan) always files, and
--   * any other guid must resolve to a unit known to be on this server
--     (UnitTokenFromGUID -> the global UnitIsSameServer; both documented on
--     the clients that have them -- UnitDocumentation.lua:1925/:2350 forever,
--     :2261 live -- and UnitIsSameServer is exercised in shipping UI on
--     classic_era, UnitPopupSharedButtonMixins.lua:2272).
--
-- Anything the APIs cannot decide (missing on this client, unit not
-- resolvable, verdict not decidable) files the record, KEEPING the existing
-- behaviour -- feature-detect means degrade, never silently stop syncing;
-- only a positive "different server" verdict skips. Which is also why the
-- harness mocks (UnitIsSameServer true, UnitTokenFromGUID nil) behave
-- exactly like the unresolved case that passes.
local function recordIsSameRealm(record)
    local guid = type(record) == "table" and type(record.guid) == "string"
        and record.guid or nil
    if not guid then
        return true
    end
    local mine = ownGUID()
    if mine and guid == mine then
        return true
    end
    local resolve = rawget(_G, "UnitTokenFromGUID")
    local sameServer = rawget(_G, "UnitIsSameServer")
    if type(resolve) ~= "function" or type(sameServer) ~= "function" then
        return true
    end
    local ok, unit = pcall(resolve, guid)
    if not ok or type(unit) ~= "string" or unit == "" then
        return true
    end
    local okSame, verdict = pcall(sameServer, unit)
    if not okSame or type(verdict) ~= "boolean" then
        return true
    end
    return verdict
end

function RankSync.QueueInspectRecord(record)
    if type(record) ~= "table" then return end
    if not recordIsSameRealm(record) then
        -- Counted skip: a scanned foreign-realm player never reaches the
        -- store, so the board keeps its realm purity without guessing.
        countOutcome("scanForeignRealm")
        return
    end
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
--   G  a gear query: "send me gear for <guid>"
--      (G;<ver>;<reqID>;<guid>)
--   D  a gear answer: one or more chunks carrying a sparse slot=itemID run
--      (D;<ver>;<reqID>;<guid>;<t>;<seq>/<of>;<blob>)
--      where <t> is the sender's server-time stamp for the gear (the dedup
--      clock -- older D never overwrites, equal-t fills gaps only), and the
--      blob packs REQUIRED_SLOTS-order pairs ("1=123,5=456", empty slots
--      omitted, IDs only). G/D ride the same version token as R (field 2),
--      the same 240-byte door, the same queue and token bucket, and the same
--      transport rule: answered on the query's own transport, counted silent
--      skip when it cannot carry, never a whisper.
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

-- ≤8 hex characters by design (audit §6.2 Stage 1 item 4): the id rides in
-- every response and the outbound budget is 240 bytes, so a request id spends
-- no more than eight. "%04x%02x" is a FIXED width -- exactly six characters,
-- distinguishability-of-concurrent-requests is all it needs to do.
local function makeRequestId()
    requestCounter = (requestCounter + 1) % 65521
    local seconds = math.floor(getClock())
    return ("%04x%02x"):format(seconds % 0xFFFF, requestCounter % 0x100)
end

local function broadcastToAll(msg)
    -- Group (PARTY / RAID / INSTANCE_CHAT), Guild, and -- while the state
    -- machine says it carries -- the hidden custom channel.
    local chan = groupChatType()
    if chan then
        RankSync.Enqueue(msg, chan)
    end
    if flagIsOn("IsInGuild") then
        RankSync.Enqueue(msg, "GUILD")
    end
    local target = channelSendTarget()
    if target then
        RankSync.Enqueue(msg, "CHANNEL", target)
    end
end

-- Ask the channel to re-send. Safe to call often: it is one short message, and
-- peers throttle their answers themselves.
function RankSync.RequestSync()
    local id = makeRequestId()
    broadcastToAll("Q;" .. id)
    return id
end

-- ---------------------------------------------------------------------------
-- Same-transport answering
-- ---------------------------------------------------------------------------
--
-- A query names a transport (CHAT_MSG_ADDON's arg3: GUILD, PARTY, RAID,
-- CHANNEL, INSTANCE_CHAT -- argument order per Blizzard's generated
-- docs, ChatInfoDocumentation.lua:617-628). Pre-Stage-1 code answered
-- everything on CHANNEL, so guild- and party-askers were heard only by the
-- channel members. The answer now goes back the way the question came --
-- with the channel gated by the same state machine as broadcasts, because
-- "the query arrived on the channel" does not mean "the channel can carry an
-- answer back" on the Classic family. There is no whisper path anywhere: a
-- background sync must never print user-visible chat noise.
local function answerForQuery(chatType)
    if chatType == "CHANNEL" then
        local target = channelSendTarget()
        if target then return "CHANNEL", target end
    elseif chatType == "GUILD" then
        if flagIsOn("IsInGuild") then return "GUILD", nil end
    elseif chatType == "PARTY" or chatType == "RAID" or chatType == "INSTANCE_CHAT" then
        if flagIsOn("IsInGroup") then return chatType, nil end
    end
    return nil
end

-- The sender's own record, sent unconditionally. It is the one record we are
-- certain is current, and it is what makes "everyone shows up on the board"
-- work -- each client contributes itself. Shared by the Q responder (S first,
-- digest after) and the G responder (S first, gear after): the record that
-- seeds standings always rides ahead of detail. The G leg drops (never
-- evicts) at the 50-message cap, like the D leg below; the Q leg keeps the
-- shared Enqueue evict.
local function enqueueOwnRecord(requestId, answerType, answerTarget, dropAtCap)
    local db = namespace.RankDB
    if type(db) ~= "table" then
        return false
    end
    local guid = ownGUID()
    local mine = guid and type(db.GetRecord) == "function" and db.GetRecord(guid) or nil
    if type(mine) ~= "table" then
        return false
    end
    local payload = RankSync.SerializeRecord(mine)
    if not payload then
        return false
    end
    if answerType then
        if dropAtCap and #sendQueue >= 50 then
            countOutcome("enqueueOversize")
            return false
        end
        RankSync.Enqueue("S;" .. requestId .. ";" .. payload,
            answerType, answerTarget)
    else
        -- The query's transport cannot carry the answer (a dead or
        -- unjoined channel, or not in the group/guild it names): a
        -- counted silent skip. There is deliberately no whisper
        -- fallback anywhere -- a background sync must never print
        -- user-visible chat noise -- so dead-transport queries stay
        -- observable (answerNoTransport) without sending anything.
        countOutcome("answerNoTransport")
    end
    return true
end

-- ---------------------------------------------------------------------------
-- The inbound flood door
-- ---------------------------------------------------------------------------
--
-- A query is a broadcast: every client on the channel hears it, and every
-- one of them answers it -- through a jittered C_Timer, one timer per inbound
-- payload. There was no bound on that. A peer (or a channel that echoes)
-- could push a flood of Q and G payloads and every client would spawn a
-- timer for each one, with nothing downstream but the send queue's own
-- 50-message cap -- which bounds the MESSAGES, not the TIMERS.
--
-- The door is a fixed window over the inbound rate: at most
-- INBOUND_WINDOW_MAX queries are honoured per INBOUND_WINDOW_SECONDS. A
-- payload past the door is REFUSED before any timer is scheduled, and the
-- refusal is COUNTED, so it is visible in /ex debug rather than silent.
--
-- The window is measured on the client's UPTIME clock (GetTime), the same
-- clock the respond interval uses. A client with no clock has no measurable
-- window, so the door stays inert -- the same fail-open convention every
-- other clock-gated gate in this file follows.
--
-- The limit is deliberately generous: a mass join really does produce one
-- query per joining client, and refusing a peer's query costs that peer
-- this client's record on its board until the next broadcast. The door
-- exists to bound the work, not to ration the answers -- and the answer
-- itself is separately limited to one per RESPOND_INTERVAL.
local INBOUND_WINDOW_SECONDS = 10
local INBOUND_WINDOW_MAX = 64
local inboundWindowStart = 0
local inboundWindowCount = 0

-- Is there room in the inbound window for one more query?
--
-- True when the payload may proceed, false when it is refused. A refusal is
-- counted in the outcome buckets, which /ex debug publishes, so a flood is
-- visible rather than silent.
local function inboundWindowAllows()
    local now = getClock()
    if now <= 0 then
        -- No clock: no measurable window, so the door stays inert.
        return true
    end
    if now - inboundWindowStart >= INBOUND_WINDOW_SECONDS then
        inboundWindowStart = now
        inboundWindowCount = 0
    end
    if inboundWindowCount >= INBOUND_WINDOW_MAX then
        countOutcome("inboundRateLimited")
        return false
    end
    inboundWindowCount = inboundWindowCount + 1
    return true
end

local function respondToQuery(requestId, chatType, _sender)
    local now = getClock()
    if lastRespondAt > 0 and (now - lastRespondAt) < RESPOND_INTERVAL then
        return false
    end
    lastRespondAt = now

    local db = namespace.RankDB
    if type(db) ~= "table" then
        return false
    end

    -- Inbound ids are clamped at the door; this is the second gate for any
    -- path that hands us a request id directly.
    requestId = (type(requestId) == "string" and requestId or ""):sub(1, 8)

    local answerType, answerTarget = answerForQuery(chatType)

    enqueueOwnRecord(requestId, answerType, answerTarget)

    -- A short digest of the best records we hold, so a fresh client learns the
    -- top of the ladder without waiting for every holder to broadcast. Capped at
    -- two per message and four in total: the point is to seed, not to mirror the
    -- database over the wire. A digest rides only when the query's own
    -- transport can carry an answer (answerType non-nil); a dead transport
    -- skips both the S and the digest and counts the skip. A two-record
    -- digest that no longer fits the 240-byte door travels as two
    -- single-record messages instead of being dropped (audit §3.2 measured
    -- a 319-byte S against this exact shape).
    if type(db.GetTopRecords) == "function" and answerType then
        local top = db.GetTopRecords(4)
        if type(top) == "table" and #top > 0 then
            for index = 1, #top, 2 do
                local first = RankSync.SerializeRecord(top[index])
                local second = top[index + 1] and RankSync.SerializeRecord(top[index + 1]) or nil
                if first then
                    local head = "T;" .. requestId .. ";"
                    local paired = second
                        and (head .. first .. ";" .. second) or nil
                    if paired and #paired <= MAX_PAYLOAD_BYTES then
                        RankSync.Enqueue(paired, answerType, answerTarget)
                    else
                        -- Over the 240-byte door: the pair travels as TWO
                        -- single-record messages rather than one oversize
                        -- enqueue or one skipped member. Dropping the second
                        -- record here was the bug the fat-digest check caught:
                        -- the split has to split BOTH directions of the pair.
                        RankSync.Enqueue(head .. first, answerType, answerTarget)
                        if second then
                            RankSync.Enqueue(head .. second, answerType, answerTarget)
                        end
                    end
                end
            end
        end
    end
    return true
end

-- ---------------------------------------------------------------------------
-- Gear on demand (Stage 4)
-- ---------------------------------------------------------------------------
--
-- Only the owner of a character reliably holds its current gear: peers keep
-- gear for at most 32 characters for 300 s (Cache 32/300, frozen inputs).
-- So a gear query is answered live from session truth -- the owner from
-- Scanner.GetCurrent().revision, a peer only from a FRESH remote entry --
-- and every answer is persisted by the RECEIVER into the bounded RankDB gear
-- table the panel renders dimmed when no fresh scan exists.
--
-- G/D framing (the version sits in field 2 for every type, so one gate
-- covers all): G;<ver>;<reqID>;<guid> and
-- D;<ver>;<reqID>;<guid>;<t>;<seq>/<of>;<blob>. <t> is the SENDER's
-- server-time stamp for the gear -- not in the brief's §1.1 sketch, but §3
-- dedup ("store iff incoming.t > stored.t", "missing t treated as 0") and
-- the stale-D check need a sender clock on the wire, and nothing else can
-- carry it. The blob is the §2.2 run (slot=itemID, REQUIRED_SLOTS order,
-- empties omitted, IDs only); it never contains ";", so fields rejoin
-- safely. of is capped at 4: a full 17-pair ID set needs at most two, so
-- four is headroom, and anything past it is refused + counted, never
-- truncated.
--
-- Throttle: gear shares the bucket, the queue and the token spend -- no
-- second bucket, no direct Enqueue from the G path. Flood control for gear
-- is per-SENDER (lastGearAnswerAt ring, same 20 s value as the Q gate):
-- different senders are never coalesced against each other, but a repeat
-- from the same sender inside the window is. The shared Q lastRespondAt is
-- deliberately NOT armed by gear answers -- a G storm must never suppress
-- rank sync (the starvation-freedom the harness pins). Priority within one
-- G: S (own record) enqueues before any D chunk.

local GEAR_MAX_CHUNKS = 4
local GEAR_RING_BOUND = 64

-- Per-sender last-answer ring: module-local, session-only, bounded (the
-- deleted whisper ring's size is the precedent only).
local lastGearAnswerAt = {}
local lastGearOrder = {}

-- Canonical slot order: the Scanner export when loaded, the RankDB copy
-- when it is not (the browser harness loads no Scanner). Both lists carry
-- the same members; a parity check pins them together.
local function gearSlotOrder()
    local scanner = namespace.Scanner
    if type(scanner) == "table" and type(scanner.REQUIRED_SLOTS) == "table" then
        return scanner.REQUIRED_SLOTS
    end
    local db = namespace.RankDB
    if type(db) == "table" and type(db.GEAR_SLOTS) == "table" then
        return db.GEAR_SLOTS
    end
    return { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }
end

-- Build the sparse §2.2 run from a Scanner revision slot table
-- ({slotID -> {itemID = {value = n}, ...}}; confirmed-empty cells carry no
-- itemID and are omitted, like non-positive ids). Ascending canonical
-- order, so chunk splits and dedup comparisons are deterministic. Empty
-- gear (nothing equipped) is nil -- an empty blob is never sent.
function RankSync.BuildGearBlob(slots)
    if type(slots) ~= "table" then
        return nil
    end
    local order = gearSlotOrder()
    local allowed = {}
    for _, slotID in ipairs(order) do
        allowed[slotID] = true
    end
    local bySlot = {}
    for slotID, cell in pairs(slots) do
        if allowed[slotID] and type(cell) == "table" then
            local value = cell.itemID and cell.itemID.value or nil
            if value == nil then
                value = tonumber(cell)
            end
            value = tonumber(value)
            if value and value > 0 and value == math.floor(value) then
                bySlot[slotID] = value
            end
        end
    end
    local out = {}
    for _, slotID in ipairs(order) do
        if bySlot[slotID] then
            out[#out + 1] = slotID .. "=" .. bySlot[slotID]
        end
    end
    if #out == 0 then
        return nil
    end
    return table.concat(out, ",")
end

-- Chunk the pair-run at pair boundaries, greediest-first. This EXTENDS the
-- digest-split machinery (paired single-record messages, above) rather than
-- duplicating it: a digest is two independent records, but a gear blob is
-- one ordered run, so the split point moves INSIDE the run. Each chunk plus
-- full framing stays at or under the door; a single pair always fits (max
-- ~10 bytes of pair against a ~157-byte worst-case head), so the loop always
-- makes progress. More chunks than the cap refuses the whole answer.
local function chunkGearRun(headLen, pairStrings)
    local budget = MAX_PAYLOAD_BYTES - headLen
    local chunks, current, currentLen = {}, {}, 0
    for _, pair in ipairs(pairStrings) do
        local add = #pair + (#current > 0 and 1 or 0)
        if #current > 0 and currentLen + add > budget then
            chunks[#chunks + 1] = table.concat(current, ",")
            current, currentLen = {}, 0
            add = #pair
        end
        current[#current + 1] = pair
        currentLen = currentLen + add
    end
    if #current > 0 then
        chunks[#chunks + 1] = table.concat(current, ",")
    end
    if #chunks > GEAR_MAX_CHUNKS then
        return nil
    end
    return chunks
end

local function cleanGearGuid(raw)
    if type(raw) ~= "string" then
        return nil
    end
    local clean = raw:gsub("[%c;]", ""):match("^%s*(.-)%s*$") or ""
    if clean == "" or #clean > 128 then
        return nil
    end
    return clean
end

local function serverClock()
    local clockFn = rawget(_G, "GetServerTime")
    if type(clockFn) ~= "function" then
        return 0
    end
    local ok, now = pcall(clockFn)
    if ok and type(now) == "number" and now == now
        and now < math.huge and now > 0 then
        return math.floor(now)
    end
    return 0
end

local function noteGearAnswer(senderKey)
    lastGearAnswerAt[senderKey] = getClock()
    lastGearOrder[#lastGearOrder + 1] = senderKey
    if #lastGearOrder > GEAR_RING_BOUND then
        local evict = table.remove(lastGearOrder, 1)
        local stillListed = false
        for _, key in ipairs(lastGearOrder) do
            if key == evict then
                stillListed = true
                break
            end
        end
        if not stillListed then
            lastGearAnswerAt[evict] = nil
        end
    end
end

-- A repeat from the same sender while its answer is still queued or the
-- window has not passed coalesces: counted, no second enqueue. A queued
-- scan covers the "still queued" half (an answer sitting in the FIFO past
-- the window must still suppress its own duplicate); the ring covers the
-- "recent" half.
local function gearAnswerRecent(senderKey)
    local at = lastGearAnswerAt[senderKey]
    if at and (getClock() - at) < RESPOND_INTERVAL then
        return true
    end
    for index = 1, #sendQueue do
        if sendQueue[index].gearSender == senderKey then
            return true
        end
    end
    return false
end

-- A full queue (50) drops the GEAR chunk, never the probe and never by
-- evicting an older queued message: channel-liveness proof outranks item
-- detail, and so does already-queued rank traffic. Counted adjacent to
-- enqueueOversize (the door bucket), per the brief.
local function enqueueGearChunk(msg, chatType, target, senderKey)
    if #sendQueue >= 50 then
        countOutcome("enqueueOversize")
        return false
    end
    sendQueue[#sendQueue + 1] = {
        msg = msg,
        chatType = chatType,
        target = target,
        gearSender = senderKey,
    }
    processQueue()
    return true
end

-- Parse one inbound D. Returns the gear triple or nil. Every failure names
-- its bucket at the call site: unknown version reuses versionReject (no
-- gearVersionReject -- the debug contract stays shape-stable), an
-- unsanitary guid counts gearBadGuid like the G path, an impossible
-- sequence counts gearRefused, and an empty blob is ignored (never sent).
local function parseGearMessage(payload)
    local parts = splitFields(payload)
    if #parts < 7 or parts[1] ~= "D" then
        return nil
    end
    if parts[2] ~= WIRE_VERSION then
        countOutcome("versionReject")
        return nil, "version"
    end
    local guid = cleanGearGuid(parts[4])
    if not guid then
        countOutcome("gearBadGuid")
        return nil, "guid"
    end
    local stamp = math.floor(tonumber(parts[5]) or 0)
    if stamp ~= stamp or stamp < 0 or stamp == math.huge then
        stamp = 0
    end
    local seq, of = (parts[6] or ""):match("^(%d+)/(%d+)$")
    seq, of = tonumber(seq), tonumber(of)
    if not seq or not of or of < 1 or of > GEAR_MAX_CHUNKS
        or seq < 1 or seq > of then
        countOutcome("gearRefused")
        return nil, "refused"
    end
    local blobParts = {}
    for index = 7, #parts do
        blobParts[#blobParts + 1] = parts[index]
    end
    local blob = table.concat(blobParts, ";")
    if blob == "" then
        return nil
    end
    return { guid = guid, t = stamp, blob = blob }
end

local function ingestGearMessage(parsed)
    local db = namespace.RankDB
    if type(db) ~= "table"
        or type(db.ParseGearIDs) ~= "function"
        or type(db.StoreGear) ~= "function" then
        return
    end
    local ordered, canonical = db.ParseGearIDs(parsed.blob)
    if not ordered then
        return
    end
    local ok, status = db.StoreGear(parsed.guid, parsed.t, canonical)
    if ok and (status == "stored" or status == "merged" or status == "filled") then
        countOutcome("gearStored")
    elseif not ok and status == "stale" then
        countOutcome("gearStale")
    end
end

-- Answer one G through the gated responder -- never a direct Enqueue from
-- the dispatch path. Reads session truth only (owner: live revision; peer:
-- fresh remote entry), enqueues S before D, chunks at pair boundaries, and
-- counts every failure. Shared lastRespondAt is deliberately not armed:
-- gear answers pace through per-sender coalescing plus the shared token
-- bucket, so a G storm can never suppress rank sync.
local function respondToGear(requestId, chatType, sender, guid)
    requestId = (type(requestId) == "string" and requestId or ""):sub(1, 8)
    local senderKey = (type(sender) == "string" and sender ~= "") and sender or "?"
    local cleanGuid = cleanGearGuid(guid)
    if not cleanGuid then
        countOutcome("gearBadGuid")
        return false
    end

    local answerType, answerTarget = answerForQuery(chatType)
    if not answerType then
        -- Dead transport: the same counted silent skip as S/T, never a
        -- reroute and never a whisper.
        countOutcome("answerNoTransport")
        return false
    end

    local slots = nil
    local scanner = namespace.Scanner
    if type(scanner) == "table" then
        local mine = ownGUID()
        if mine and cleanGuid == mine and type(scanner.GetCurrent) == "function" then
            local ok, current = pcall(scanner.GetCurrent)
            if ok and type(current) == "table" then
                local state = current.status or current.state
                if state == "complete" and type(current.revision) == "table" then
                    slots = current.revision.slots
                end
            end
        elseif type(scanner.GetFreshRemote) == "function" then
            local ok, fresh = pcall(scanner.GetFreshRemote, cleanGuid)
            if ok and type(fresh) == "table" then
                local state = fresh.state or fresh.status
                if state == "complete" and type(fresh.revision) == "table" then
                    slots = fresh.revision.slots
                end
            end
        end
    end
    local blob = RankSync.BuildGearBlob(slots)
    if not blob then
        -- Missing, pending, unavailable, or freshness-expired: silence with
        -- a counter, exactly like the harness-era unknown-GUID rule.
        countOutcome("gearNoData")
        return false
    end

    if gearAnswerRecent(senderKey) then
        countOutcome("gearCoalesced")
        return false
    end

    -- The G answer's S drops (never evicts) at the cap, like every D
    -- chunk below: channel-liveness proof and already-queued traffic outrank
    -- a redundant own-record copy.
    enqueueOwnRecord(requestId, answerType, answerTarget, true)

    local pairStrings = {}
    for pair in blob:gmatch("[^,]+") do
        pairStrings[#pairStrings + 1] = pair
    end
    -- seq/of is always three characters ("1/1".."4/4": of never exceeds the
    -- cap), so the head length is exact before the chunk count is known.
    local stampText = tostring(serverClock())
    local headLen = 4 + (#requestId + 1) + (#cleanGuid + 1) + (#stampText + 1) + 4
    local chunks = chunkGearRun(headLen, pairStrings)
    if not chunks then
        countOutcome("gearRefused")
        return false
    end
    local served = false
    for seq = 1, #chunks do
        local msg = "D;" .. WIRE_VERSION .. ";" .. requestId .. ";" .. cleanGuid
            .. ";" .. stampText .. ";" .. seq .. "/" .. #chunks .. ";" .. chunks[seq]
        if enqueueGearChunk(msg, answerType, answerTarget, senderKey) then
            served = true
        end
    end
    if served then
        noteGearAnswer(senderKey)
    end
    return served
end

-- Rebuild one record from a run of already-split fields.
--
-- The field order MUST match SerializeRecord exactly: R, version token,
-- guid, name, classID, gs, ilvl, timestamp, specID, guild, level, pvpRank,
-- arena. It is duplicated rather than shared because the wire format is the
-- more stable of the two: if the serializer's field order ever changes, BOTH
-- functions have to change together and a reader needs to see that, which a
-- shared helper would hide. A run that does not carry this client's version
-- is refused and counted (versionReject), never inferred.
local function recordFromParts(parts, start)
    if parts[start] ~= "R" then
        return nil
    end
    if parts[start + 1] ~= WIRE_VERSION then
        countOutcome("versionReject")
        return nil
    end
    local classID = tonumber(parts[start + 4]) or 0
    return {
        guid = parts[start + 2],
        name = parts[start + 3],
        classID = classID,
        class = classTokenFromID(classID),
        specID = tonumber(parts[start + 8]) or 0,
        gs = tonumber(parts[start + 5]) or 0,
        ilvl = tonumber(parts[start + 6]) or 0,
        timestamp = tonumber(parts[start + 7]) or 0,
        guild = parts[start + 9] or "",
        level = tonumber(parts[start + 10]) or 0,
        pvpRank = tonumber(parts[start + 11]) or 0,
        arena = tonumber(parts[start + 12]) or 0,
        source = "sync",
    }
end

-- Store every record carried by an S or T payload.
--
-- The payload is NOT a list of "R;..." strings -- the records share the outer
-- ";" delimiter, so a record is a RUN OF THIRTEEN FIELDS inside one flat split,
-- not a single element. Splitting and reading element 3 would yield the bare
-- letter "R" and silently store nothing, which is the failure this comment
-- exists to prevent. Hence the fixed stride, and hence RECORD_FIELDS being
-- derived from SerializeRecord's layout rather than guessed.
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
            local storedOK, storeReason = namespace.RankDB.StoreRecord(record)
            if storedOK then
                stored = stored + 1
            else
                -- M-5: a record that fails RankDB.ValidateRecord used to be
                -- dropped with nothing said and nothing counted -- while the
                -- VERSION mismatch on the very same path WAS counted. A peer
                -- whose records are all refused was undiagnosable. Counted
                -- here, with the refusal reason kept.
                countOutcome("recordRejected")
                lastRecordRejectedReason = tostring(storeReason or "unknown")
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
--
-- chatType and sender come from CHAT_MSG_ADDON (arg3 channel / chat type,
-- arg4 sender). A query whose transport cannot carry an answer is a counted
-- silent skip (answerNoTransport) -- never a guessed broadcast, and never a
-- whisper: there is no whisper path anywhere.
local function handlePayload(payload, chatType, sender)
    local kind = payload:sub(1, 1)

    if kind == "R" then
        local rec = RankSync.DeserializeRecord(payload)
        if rec and namespace.RankDB
            and type(namespace.RankDB.StoreRecord) == "function" then
            local storedOK, storeReason = namespace.RankDB.StoreRecord(rec)
            if not storedOK then
                -- M-5, the single-record arm: same count, same reason.
                countOutcome("recordRejected")
                lastRecordRejectedReason = tostring(storeReason or "unknown")
            end
        end
        return
    end

    if kind == "Q" then
        -- The inbound flood door: past the window the payload is refused
        -- BEFORE any timer is scheduled, so a burst cannot spawn a timer
        -- per payload.
        if not inboundWindowAllows() then
            return
        end
        -- Clamp BEFORE anything downstream can echo it back whole: an inbound
        -- "Q" with hundreds of id bytes would otherwise ride the response and
        -- eat the record budget byte for byte.
        local requestId = (payload:match("^Q;([^;]+)") or ""):sub(1, 8)
        -- Jittered, so ten clients joining together do not answer in the same
        -- instant and evict each other through the send queue's cap.
        local delay = RESPOND_JITTER_MIN
            + math.random() * (RESPOND_JITTER_MAX - RESPOND_JITTER_MIN)
        local cTimer = rawget(_G, "C_Timer")
        if type(cTimer) == "table" and type(cTimer.After) == "function" then
            cTimer.After(delay, function()
                respondToQuery(requestId, chatType)
            end)
        else
            respondToQuery(requestId, chatType)
        end
        return
    end

    if kind == "S" or kind == "T" then
        ingestRecords(payload)
        return
    end

    if kind == "G" then
        -- G;<ver>;<reqID>;<guid>. The version sits in field 2 like every
        -- other type, so the diet's single versionReject gate covers gear
        -- queries too -- an old (or future) client hears silence, exactly
        -- like an old R. The id is clamped at the door (a hundreds-of-bytes
        -- G id must never ride the D answer byte-for-byte), and the answer
        -- runs jittered through the gated responder, never a direct Enqueue.
        local parts = splitFields(payload)
        if parts[2] ~= WIRE_VERSION then
            countOutcome("versionReject")
            return
        end
        local requestId = (parts[3] or ""):sub(1, 8)
        local guid = parts[4] or ""
        -- The same inbound flood door as the Q path: a gear query spawns a
        -- timer exactly like a record query does.
        if not inboundWindowAllows() then
            return
        end
        local delay = RESPOND_JITTER_MIN
            + math.random() * (RESPOND_JITTER_MAX - RESPOND_JITTER_MIN)
        local cTimer = rawget(_G, "C_Timer")
        if type(cTimer) == "table" and type(cTimer.After) == "function" then
            cTimer.After(delay, function()
                respondToGear(requestId, chatType, sender, guid)
            end)
        else
            respondToGear(requestId, chatType, sender, guid)
        end
        return
    end

    if kind == "D" then
        local parsed = parseGearMessage(payload)
        if parsed then
            ingestGearMessage(parsed)
        end
        return
    end
end

RankSync.HandlePayload = handlePayload
RankSync.RESPOND_INTERVAL = RESPOND_INTERVAL
RankSync.INBOUND_WINDOW_MAX = INBOUND_WINDOW_MAX
RankSync.INBOUND_WINDOW_SECONDS = INBOUND_WINDOW_SECONDS

-- Join the channel and then ASK. A query sent before the join lands reaches
-- nobody, and GetChannelName can lag the join by a frame or two, so the first
-- attempt is retried once rather than fired into a channel id that is still nil.
local function joinThenQuery()
    joinSyncChannel()
    armChannelProbe()
    if channel.id and channel.id > 0 then
        RankSync.RequestSync()
        return
    end
    local cTimer = rawget(_G, "C_Timer")
    if type(cTimer) == "table" and type(cTimer.After) == "function" then
        cTimer.After(4.0, function()
            joinSyncChannel()
            armChannelProbe()
            if channel.id and channel.id > 0 then
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
    -- This throttle measures elapsed time inside one session, never a calendar
    -- date: the value is compared only against lastSyncAt and is not persisted.
    -- Uptime is the correct clock here. Server epoch can be adjusted under us,
    -- while GetTime() cannot, and it is the same clock the send token bucket
    -- above already uses.
    local now = getClock()
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

-- /ex debug reads this (Core.lua), per audit §6.2 Stage 1 item 3: sends
-- bucketed by client-declared outcome, queue pressure, the channel machine,
-- and the counted-skip buckets (dead-transport answers, version rejects).
-- It is a snapshot copy, not a live reference.
function RankSync.GetDebugState()
    local copy = {}
    for key, value in pairs(outcomes) do
        copy[key] = value
    end
    return {
        outcomes = copy,
        channelState = channel.state,
        channelId = channel.id,
        channelFailures = channel.failures,
        queueDepth = #sendQueue,
        tokenBucket = tokens,
        selfBroadcastPending = pendingSelfBroadcast,
        lastRecordRejectedReason = lastRecordRejectedReason,
        lastEvictedKind = lastEvictedKind,
    }
end

-- CHAT_MSG_ADDON argument order (source:
-- /home/sam/wow-ui-source/.../Blizzard_APIDocumentationGenerated/
-- ChatInfoDocumentation.lua:617-628): arg1 prefix, arg2 text, arg3 channel
-- (chat type), arg4 sender. The pre-Stage-1 handler read only arg1/arg2 -- the
-- reason every answer could be channel-only -- so arg3 and arg4 are threaded
-- into the payload dispatch now.
local function onEvent(_, event, arg1, arg2, arg3, arg4)
    if event == "CHAT_MSG_ADDON" then
        if arg1 == PREFIX and type(arg2) == "string" then
            handlePayload(arg2, arg3, arg4)
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
