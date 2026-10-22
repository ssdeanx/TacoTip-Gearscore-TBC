local _, namespace = ...

if type(namespace) ~= "table" then
    return
end

local RankDB = {}
namespace.RankDB = RankDB

-- 20000 players per realm, measured rather than guessed.
--
-- A stored record serialises to ~276 bytes as WoW writes SavedVariables (Lua
-- table source, so every key name, quote and comma counts). The field limits in
-- ValidateRecord are guid 128, name 64, specName 64, class 32, faction 16:
--
--      5000 records ->  1.3 MB   (the old cap)
--     20000 records ->  5.3 MB   (this cap)
--     50000 records -> 13.2 MB
--
-- 5 MB is a deliberate ceiling, not an accident. WoW writes the whole file
-- synchronously at logout and reads it at login, so an unbounded leaderboard
-- trades a slow login for standings nobody will scroll to. 20000 covers a full
-- Classic realm population with room to spare and keeps the file at a size
-- every client handles without a hitch.
local MAX_CAPACITY = 20000
local MAX_AGE_SECONDS = 60 * 24 * 3600 -- 60 days
local MAX_GEARSCORE = 15000
local MAX_ILVL = 1500

RankDB.MAX_CAPACITY = MAX_CAPACITY
RankDB.MAX_AGE_SECONDS = MAX_AGE_SECONDS

-- Stage 4: bounded persisted gear (storage-expansion §6.2 Stage 4, §2.2).
--
-- TacoTipExtrasDB.gear = { [realmKey] = { [guid] = { t = <server-time>,
-- ids = "1=123,5=456" } } } -- the sparse §2.2 run, ascending REQUIRED_SLOTS
-- order, empty slots omitted. Created lazily (absent = no gear; nothing
-- migrates, nothing rewrites). Cap: 2,000 entries realm-scoped + the same
-- 60-day age prune as ranks (~0.3 MiB at ~150 bytes/row, inside the ≤0.5 MiB
-- gear budget). No heap: a 2,000-row table needs no amortized machinery, so
-- eviction counts its pairs once per prune pass (O(2k) at login, not O(20k)
-- per insert) and never threads through entryCount/oldestHeap -- coupling two
-- lifecycles with different caps would break the visible-set invariant the
-- Stage-2 checks pin. The owner's own guid is exempt from COUNT eviction
-- (re-persisted on every own scan) but not from the age prune.
RankDB.GEAR_MAX_ENTRIES = 2000

-- The wire/panel slot set. Same members and order as Scanner.REQUIRED_SLOTS
-- (shirt 4 and tabard 19 excluded, matching the scorer input); a parity check
-- pins the two lists together, and RankSync prefers the Scanner export when
-- it is loaded, falling back to this copy when it is not.
RankDB.GEAR_SLOTS = {
    1, 2, 3, 5, 6, 7, 8, 9, 10,
    11, 12, 13, 14, 15, 16, 17, 18,
}

local dirtyFlags = {}
local cachedIndices = {}
local cachedLookups = {}

-- Amortized capacity bookkeeping (storage-expansion audit §6.2 Stage 2 item 2).
--
-- The per-insert enforcement this replaces walked the whole realm table with a
-- pairs() scan plus a defensive table.sort on EVERY store, to answer one
-- question it could have remembered: which rows are oldest when the cap is
-- crossed. Measured on a full 20000-row table that scan made each store pay
-- ~21.5 ms. The replacement keeps the identical caller contract -- age
-- pruning stays in PruneStaleRecords, the visible set never exceeds
-- MAX_CAPACITY, evictions always take the oldest timestamp first -- while
-- paying O(log n) per store for two per-realm structures:
--
--   * entryCount[realmKey] -- the exact row count, seeded once per session
--     with a single pairs() count and then maintained: +1 on a new guid,
--     -1 on every eviction, and rewritten by the functions that remove rows
--     wholesale (PruneStaleRecords, PurgeDatabase, the realm deletions here
--     in PruneAllRealms).
--   * oldestHeap[realmKey] -- a lazy binary min-heap of {ts, guid} pairs,
--     ordered oldest-timestamp-first with the guid as a stable tiebreak,
--     heapified the first time a realm needs an eviction in this session and
--     kept maintained from then on. A settlement that never nears the cap --
--     the overwhelming majority -- never builds the heap at all.
--
-- A replace (same guid, non-decreasing timestamp) never shrinks the visible
-- set and never makes a row older, so a heap entry only has to be checked
-- against the live row when it is popped ("stale entry" handling below).
local entryCount = {}
local oldestHeap = {}

-- Drop every trace of one realm's bookkeeping. Called whenever the realm
-- table is emptied wholesale or the realm key itself is deleted; the next
-- store into that realm re-seeds a correct count from the table it finds.
local function forgetRowBookkeeping(realmKey)
    entryCount[realmKey] = nil
    oldestHeap[realmKey] = nil
end

-- Delete one realm key AND forget every cache side it ever built. The dirty
-- flag goes with it: there is nothing left for an index rebuild to see.
local function forgetRealm(realmKey)
    dirtyFlags[realmKey] = nil
    cachedIndices[realmKey] = nil
    cachedLookups[realmKey] = nil
    forgetRowBookkeeping(realmKey)
end

local function heapLess(a, b)
    if a.ts ~= b.ts then
        return a.ts < b.ts
    end
    return a.guid < b.guid
end

local function heapUp(heap, index)
    while index > 1 do
        local parent = math.floor(index / 2)
        if heapLess(heap[index], heap[parent]) then
            heap[index], heap[parent] = heap[parent], heap[index]
            index = parent
        else
            break
        end
    end
end

local function heapDown(heap, index)
    local size = #heap
    while true do
        local child = index * 2
        if child > size then
            break
        end
        if child + 1 <= size and heapLess(heap[child + 1], heap[child]) then
            child = child + 1
        end
        if heapLess(heap[child], heap[index]) then
            heap[index], heap[child] = heap[child], heap[index]
            index = child
        else
            break
        end
    end
end

-- Build the heap from the live rows: one pairs() walk, at most once per
-- session per realm plus once after each wholesale removal. Every key gets
-- exactly one candidate, so the loop below cannot run away on it.
local function ensureOldestHeap(realmKey, db)
    local heap = oldestHeap[realmKey]
    if heap then
        return heap
    end
    heap = {}
    for guid, entry in pairs(db) do
        heap[#heap + 1] = {
            ts = (type(entry) == "table" and tonumber(entry.timestamp) or 0),
            guid = guid,
        }
    end
    for i = math.floor(#heap / 2), 1, -1 do
        heapDown(heap, i)
    end
    oldestHeap[realmKey] = heap
    return heap
end

local function getRealmKey(customRealm)
    if type(customRealm) == "string" and customRealm ~= "" then
        return customRealm
    end
    local getNorm = rawget(_G, "GetNormalizedRealmName")
    if type(getNorm) == "function" then
        local ok, r = pcall(getNorm)
        if ok and type(r) == "string" and r ~= "" then
            return r
        end
    end
    local getRealm = rawget(_G, "GetRealmName")
    if type(getRealm) == "function" then
        local ok, r = pcall(getRealm)
        if ok and type(r) == "string" and r ~= "" then
            return r
        end
    end
    return "DefaultRealm"
end

local function getDB(realm)
    local realmKey = getRealmKey(realm)
    local g = _G
    if type(g["TacoTipExtrasDB"]) ~= "table" then
        g["TacoTipExtrasDB"] = {}
    end
    local root = g["TacoTipExtrasDB"]
    if type(root["ranks"]) ~= "table" then
        root["ranks"] = {}
    end
    if type(root["ranks"][realmKey]) ~= "table" then
        root["ranks"][realmKey] = {}
    end
    return root["ranks"][realmKey], realmKey
end

local function sanitizeString(val, maxLen)
    if type(val) ~= "string" then return nil end
    local s = val:gsub("[%c;]", ""):match("^%s*(.-)%s*$")
    if s == "" then return nil end
    if maxLen and #s > maxLen then
        s = s:sub(1, maxLen)
        -- Never cut inside a UTF-8 multibyte sequence; drop stray
        -- continuation bytes from the tail.
        while #s > 0 do
            local b = s:byte(#s)
            if b >= 0x80 and b < 0xC0 then
                s = s:sub(1, #s - 1)
            else
                break
            end
        end
    end
    return s
end

local function sanitizeNumber(val, minVal, maxVal)
    local n = tonumber(val)
    if not n or n ~= n or n == math.huge or n == -math.huge then
        return nil
    end
    if minVal and n < minVal then return nil end
    if maxVal and n > maxVal then return nil end
    return n
end

-- A string the client will RENDER.
--
-- sanitizeString answers "is this a safe string to STORE"; this one answers
-- "is this a safe string to DISPLAY", and the difference is WoW markup. A
-- FontString renders `|cff00ff00` as a colour, so a name or a guild that
-- arrived over the wire could repaint another player's leaderboard row,
-- their row tooltip and their gear-panel title with a colour of their
-- choosing -- the row's own class colour included.
--
-- The markup is REMOVED rather than escaped, and the reason matters: a
-- literal pipe has no universally safe escape in the client's markup
-- parser, and a doubled pipe is only safe if the parser treats `||` as an
-- escape -- an assumption this add-on does not get to make. What is left is
-- the name's own text, rendered as text. The percent sign goes the same
-- way, because string.format treats it as a conversion character and a
-- name is only ever a format ARGUMENT here (so a doubled percent would
-- show as a doubled percent) -- removing it costs nothing, because the
-- client allows neither character in a character name.
--
-- The GUID is deliberately NOT sanitised this way: it is a key, it has to
-- round-trip byte for byte, and it is never rendered.
local function sanitizeDisplayString(val, maxLen)
    local s = sanitizeString(val, maxLen)
    if s == nil then
        return nil
    end
    s = s:gsub("|H.-|h", "")           -- hyperlink
    s = s:gsub("|T.-|t", "")           -- texture
    s = s:gsub("|A.-|a", "")           -- atlas
    s = s:gsub("|c%x%x%x%x%x%x%x%x", "") -- colour
    s = s:gsub("|r", "")               -- colour reset
    s = s:gsub("|n", "")               -- newline
    s = s:gsub("|", "")                -- any escape character left over
    s = s:gsub("%%", "")               -- string.format's conversion character
    s = s:match("^%s*(.-)%s*$")
    if s == "" then
        return nil
    end
    return s
end

function RankDB.ValidateRecord(record)
    if type(record) ~= "table" then
        return nil, "record must be a table"
    end

    local guid = sanitizeString(record.guid, 128)
    if not guid then
        return nil, "invalid or missing GUID"
    end

    local name = sanitizeDisplayString(record.name, 64)
    if not name then
        return nil, "invalid or missing name"
    end

    local gs = sanitizeNumber(record.gs, 1, MAX_GEARSCORE)
    if not gs then
        return nil, "invalid gearscore"
    end

    local ilvl = sanitizeNumber(record.ilvl, 1, MAX_ILVL) or 0
    local now = GetServerTime and GetServerTime() or 0
    local timestamp = sanitizeNumber(record.timestamp, 0, now + 300) or now

    local factionRaw = sanitizeString(record.faction, 16)
    -- Faction is storage-only and optional, written from local scans only
    -- (UnitFactionGroup): only a positive Alliance/Horde verdict is kept.
    -- Anything else -- absent, "Unknown", a legacy value -- stores as nil,
    -- and the row tooltip renders the faction line only when present.
    local faction = nil
    if factionRaw == "Alliance" or factionRaw == "Horde" then
        faction = factionRaw
    end

    local class = sanitizeDisplayString(record.class, 32) or "UNKNOWN"
    local specName = sanitizeDisplayString(record.specName, 64) or ""

    -- classID and specID are the canonical render keys (class token and spec
    -- identity derive from them at render). Stored as floor'd non-negative
    -- numbers, 0 when unknown; legacy rows without them read tolerant and
    -- fall back to the class/specName strings.
    local function sanitizeID(value, maxVal)
        local n = tonumber(value)
        if not n or n ~= n or n == math.huge or n == -math.huge or n < 0 then
            return 0
        end
        local floored = math.floor(n)
        if maxVal and floored > maxVal then
            return maxVal
        end
        return floored
    end
    local classID = sanitizeID(record.classID)
    -- specID rides the wire as variable-width text, so an unbounded value
    -- serializes byte-for-byte and the validator-max row has no true maximum
    -- without a cap. 9999 sits far above every assigned specID (observed ids
    -- stay in the low thousands) while keeping the largest sanitized row a
    -- fixed size; the 240-byte enqueue door stays as the backstop for every
    -- other oversize shape.
    local specID = sanitizeID(record.specID, 9999)
    -- Stage-3 cheap row fields (additive: old rows without them read blanks).
    -- Guild is the expensive one: sanitized like every other string field and
    -- hard-truncated to 24 chars; "" is unguilded-or-unknown, never fill.
    local guild = sanitizeDisplayString(record.guild, 24) or ""
    local level = sanitizeID(record.level)
    local pvpRank = sanitizeID(record.pvpRank)
    local arena = sanitizeID(record.arena)
    -- specIcon / source are NOT written any more (audit §2.2: dead
    -- fields). Inbound records that carry them stay accepted as-is -- the
    -- values are simply ignored here, and old pre-hygiene rows keep rendering
    -- until the row is refreshed or pruned. Readers remain tolerant of their
    -- presence.
    return {
        guid = guid,
        name = name,
        faction = faction,
        class = class,
        classID = classID,
        specID = specID,
        specName = specName,
        guild = guild,
        level = level,
        pvpRank = pvpRank,
        arena = arena,
        gs = math.floor(gs + 0.5),
        ilvl = math.floor(ilvl * 10 + 0.5) / 10,
        timestamp = math.floor(timestamp),
    }
end

function RankDB.StoreRecord(record, realm)
    local clean, err = RankDB.ValidateRecord(record)
    if not clean then
        return false, err
    end

    -- the realm argument names the table directly: the wire carries no
    -- realm, so inbound sync records file under the local realm through the
    -- default routing below (an explicit realm is a direct caller naming a
    -- table, never a record arriving with its own).
    local db, realmKey = getDB(realm)
    local existing = db[clean.guid]

    if existing and type(existing.timestamp) == "number" and existing.timestamp > clean.timestamp then
        return true, "up-to-date"
    end

    -- Seed the per-realm row count BEFORE the write, so the adjustment below
    -- is +1 exactly when this store adopts a new guid and 0 when it replaces
    -- (replacing one row with another does not change the row count).
    if entryCount[realmKey] == nil then
        local seeded = 0
        for _ in pairs(db) do
            seeded = seeded + 1
        end
        entryCount[realmKey] = seeded
    end

    local isNewRow = existing == nil

    db[clean.guid] = clean
    dirtyFlags[realmKey] = true

    if isNewRow then
        entryCount[realmKey] = entryCount[realmKey] + 1
    end

    -- Enforce the documented capacity without changing the caller-visible
    -- pruning semantics (age pruning stays in PruneStaleRecords, where direct
    -- calls and the 60-day default remain testable): the amortized count and
    -- the lazy oldest-heap replace the per-insert pairs() scan + sort that
    -- previously rebuilt the oldest-order on every store (storage-expansion
    -- audit §6.2 Stage 2 item 2). Same semantics: oldest timestamp first,
    -- never more than MAX_CAPACITY visible rows.
    if entryCount[realmKey] > MAX_CAPACITY then
        local heapExisted = oldestHeap[realmKey] ~= nil
        local heap = ensureOldestHeap(realmKey, db)
        -- A heap built right now already walked the table that contains this
        -- new row; only a heap that survived from an earlier insert needs the
        -- push (and skipping it would let the newest row leak into the
        -- oldest-first eviction twice over).
        if isNewRow and heapExisted then
            heap[#heap + 1] = { ts = clean.timestamp, guid = clean.guid }
            heapUp(heap, #heap)
        end
        -- Pop the oldest candidates until the realm is at capacity. Each
        -- popped candidate is validated against the live row: absent means it
        -- already left the table (prune, purge) and the entry is skip; a
        -- different timestamp means the row was replaced by a newer one, so
        -- the candidate re-files with the live timestamp instead of evicting
        -- newer data (a store never moves a timestamp backwards, and the heap
        -- stays smallest-first, so this converges); a match evicts.
        while entryCount[realmKey] > MAX_CAPACITY do
            if #heap == 0 then
                oldestHeap[realmKey] = nil
                heap = ensureOldestHeap(realmKey, db)
                if #heap == 0 then
                    -- The count claims over capacity but no rows remain to
                    -- evict: the bookkeeping is wrong, not the data. Re-measure
                    -- and stop -- correctness here is self-healing, never
                    -- unbounded.
                    local measured = 0
                    for _ in pairs(db) do
                        measured = measured + 1
                    end
                    entryCount[realmKey] = measured
                    break
                end
            end
            -- Pop the root: swap it with the last leaf, drop the leaf, and
            -- sift the new root down. (table.remove(heap, 1) would be the
            -- same result but shifts the whole table on every pop.)
            local last = #heap
            local oldest = heap[1]
            heap[1] = heap[last]
            heap[last] = nil
            if last > 1 then
                heapDown(heap, 1)
            end

            local row = db[oldest.guid]
            if row ~= nil then
                local rowTs = type(row) == "table"
                    and tonumber(row.timestamp) or nil
                if rowTs == nil then
                    -- Not a row this file could have written (non-table junk
                    -- or a timestamp-less row cannot rank into oldest-order).
                    -- Drop it and keep the count honest.
                    db[oldest.guid] = nil
                    entryCount[realmKey] = entryCount[realmKey] - 1
                elseif rowTs ~= oldest.ts then
                    -- Forward-replaced row: re-file the candidate with the
                    -- live timestamp rather than evicting newer data.
                    heap[#heap + 1] = { ts = rowTs, guid = oldest.guid }
                    heapUp(heap, #heap)
                else
                    db[oldest.guid] = nil
                    entryCount[realmKey] = entryCount[realmKey] - 1
                end
            end
            -- row == nil: a stale entry -- the row already left the table
            -- through a prune or a purge. Nothing to do but keep popping.
        end
    end

    return true, "stored"
end

local function sortComparator(a, b)
    if a.gs ~= b.gs then
        return a.gs > b.gs
    end
    if a.ilvl ~= b.ilvl then
        return a.ilvl > b.ilvl
    end
    if a.timestamp ~= b.timestamp then
        return a.timestamp > b.timestamp
    end
    return a.name < b.name
end

function RankDB.BuildSortedIndices(realm)
    local db, realmKey = getDB(realm)

    if not dirtyFlags[realmKey] and cachedIndices[realmKey] and cachedLookups[realmKey] then
        return cachedIndices[realmKey], cachedLookups[realmKey]
    end

    local allList = {}
    local allianceList = {}
    local hordeList = {}
    local classLists = {}

    local now = GetServerTime and GetServerTime() or 0
    local cutoff = now > MAX_AGE_SECONDS and (now - MAX_AGE_SECONDS) or 0

    for _, entry in pairs(db) do
        if type(entry) == "table" and type(entry.gs) == "number" and (entry.timestamp or 0) >= cutoff then
            allList[#allList + 1] = entry
            if entry.faction == "Alliance" then
                allianceList[#allianceList + 1] = entry
            elseif entry.faction == "Horde" then
                hordeList[#hordeList + 1] = entry
            end
            local c = entry.class or "UNKNOWN"
            if not classLists[c] then
                classLists[c] = {}
            end
            local cList = classLists[c]
            cList[#cList + 1] = entry
        end
    end

    table.sort(allList, sortComparator)
    table.sort(allianceList, sortComparator)
    table.sort(hordeList, sortComparator)
    for _, list in pairs(classLists) do
        table.sort(list, sortComparator)
    end

    local lookups = {}
    for rank, entry in ipairs(allList) do
        if not lookups[entry.guid] then
            lookups[entry.guid] = {}
        end
        lookups[entry.guid].overallRank = rank
    end

    for rank, entry in ipairs(allianceList) do
        if lookups[entry.guid] then
            lookups[entry.guid].factionRank = rank
        end
    end

    for rank, entry in ipairs(hordeList) do
        if lookups[entry.guid] then
            lookups[entry.guid].factionRank = rank
        end
    end

    for _, list in pairs(classLists) do
        for rank, entry in ipairs(list) do
            if lookups[entry.guid] then
                lookups[entry.guid].classRank = rank
            end
        end
    end

    local indices = {
        all = allList,
        alliance = allianceList,
        horde = hordeList,
        byClass = classLists,
        total = #allList,
    }

    cachedIndices[realmKey] = indices
    cachedLookups[realmKey] = lookups
    dirtyFlags[realmKey] = false

    return indices, lookups
end

function RankDB.GetPlayerRank(guid, realm)
    if not guid or guid == "" then
        return nil, nil, nil, 0
    end

    local indices, lookups = RankDB.BuildSortedIndices(realm)
    local lk = lookups[guid]
    if not lk then
        return nil, nil, nil, indices.total or 0
    end

    return lk.overallRank, lk.factionRank, lk.classRank, indices.total or 0
end

-- The raw stored record for one GUID, or nil.
--
-- Needed by the sync engine: a query asks peers to re-send what they know, and
-- the most useful thing we can send back is our OWN record (we always have it,
-- it is always current, and it costs one message) plus a short digest of the
-- best few we hold. The rank indices cannot supply that -- they carry ranks,
-- not records.
function RankDB.GetRecord(guid, realm)
    if type(guid) ~= "string" or guid == "" then
        return nil
    end
    local db = getDB(realm)
    local entry = db[guid]
    if type(entry) ~= "table" then
        return nil
    end
    return entry
end

-- The highest-GearScore records we hold, newest first on a tie.
--
-- `limit` is clamped: this feeds a network digest where every record costs
-- roughly 90 of the 255 bytes an addon message allows, so an unbounded call
-- would build a payload that cannot be sent. The clamp is the contract, not a
-- courtesy.
function RankDB.GetTopRecords(limit, realm)
    local count = tonumber(limit) or 0
    if count <= 0 then
        return {}
    end
    if count > 10 then
        count = 10
    end
    local list = RankDB.GetLeaderboard(realm, "All", "ALL", nil)
    local top = {}
    for index = 1, math.min(count, #(list or {})) do
        local entry = list[index]
        if type(entry) == "table" then
            top[#top + 1] = entry
        end
    end
    return top
end

function RankDB.GetLeaderboard(realm, tab, classFilter, searchQuery, guildFilter)
    local indices = RankDB.BuildSortedIndices(realm)
    local sourceList

    local t = type(tab) == "string" and tab:lower() or "all"
    if t == "alliance" then
        sourceList = indices.alliance
    elseif t == "horde" then
        sourceList = indices.horde
    else
        sourceList = indices.all
    end

    local hasClass = type(classFilter) == "string" and classFilter ~= "" and classFilter ~= "ALL"
    local hasQuery = type(searchQuery) == "string" and searchQuery:match("%S") ~= nil
    local queryPattern = hasQuery and searchQuery:lower() or nil
    -- Guild text filter (Stage 3): substring, case-insensitive plain find --
    -- the same shape as the name search above. Optional-positional: nil (or
    -- blank) means unchanged behaviour and every existing caller keeps
    -- working. Unguilded ("") rows survive whenever no filter is active.
    local hasGuild = type(guildFilter) == "string" and guildFilter:match("%S") ~= nil
    local guildPattern = hasGuild and guildFilter:lower() or nil

    if not hasClass and not hasQuery and not hasGuild then
        return sourceList, #sourceList
    end

    local filtered = {}
    for i = 1, #sourceList do
        local entry = sourceList[i]
        local match = true
        if hasClass and entry.class ~= classFilter then
            match = false
        end
        if match and queryPattern then
            local n = (entry.name or ""):lower()
            if not n:find(queryPattern, 1, true) then
                match = false
            end
        end
        if match and guildPattern then
            local g = (entry.guild or ""):lower()
            if not g:find(guildPattern, 1, true) then
                match = false
            end
        end
        if match then
            filtered[#filtered + 1] = entry
        end
    end

    return filtered, #filtered
end

function RankDB.PruneStaleRecords(realm, maxAgeDays, maxCapacity)
    local db, realmKey = getDB(realm)
    local ageLimit = (maxAgeDays or 60) * 24 * 3600
    local cap = maxCapacity or MAX_CAPACITY
    local now = GetServerTime and GetServerTime() or 0
    local cutoff = now > ageLimit and (now - ageLimit) or 0

    local removed = 0
    local remaining = {}

    for guid, entry in pairs(db) do
        if type(entry) == "table" and (entry.timestamp or 0) < cutoff then
            db[guid] = nil
            removed = removed + 1
        else
            remaining[#remaining + 1] = {
                guid = guid,
                timestamp = (type(entry) == "table" and tonumber(entry.timestamp) or 0),
            }
        end
    end

    if #remaining > cap then
        table.sort(remaining, function(a, b)
            return a.timestamp < b.timestamp
        end)
        local toEvict = #remaining - cap
        for i = 1, toEvict do
            db[remaining[i].guid] = nil
            removed = removed + 1
        end
    end

    if removed > 0 then
        dirtyFlags[realmKey] = true
    end

    -- Keep the amortized bookkeeping exact. The survivors of this pass are
    -- exactly min(#remaining, cap) rows, and the heap snapshot is stale by
    -- definition of a removal pass -- PruneAllRealms reads the count here to
    -- decide whether the realm key itself is dead.
    entryCount[realmKey] = math.min(#remaining, cap)
    oldestHeap[realmKey] = nil

    return removed
end

-- ---------------------------------------------------------------------------
-- Stage 4: bounded persisted gear
-- ---------------------------------------------------------------------------

local function getGearDB(realm)
    local realmKey = getRealmKey(realm)
    local g = _G
    if type(g["TacoTipExtrasDB"]) ~= "table" then
        g["TacoTipExtrasDB"] = {}
    end
    local root = g["TacoTipExtrasDB"]
    if type(root["gear"]) ~= "table" then
        root["gear"] = {}
    end
    if type(root["gear"][realmKey]) ~= "table" then
        root["gear"][realmKey] = {}
    end
    return root["gear"][realmKey], realmKey
end

-- Amortized capacity bookkeeping for the GEAR table, in the same shape as the
-- rank table's bookkeeping above.
--
-- The gear table had a documented capacity (2,000 rows per realm) but only
-- ENFORCED it at prune time -- login, or the SAVED_VARIABLES_TOO_LARGE
-- response. Between two prunes the table grew without bound: every inbound D
-- answer added a row, so a session that received many answers could push the
-- persisted gear far past the budget the table is supposed to hold, and that
-- table is the file the client writes synchronously at logout.
--
-- The enforcement therefore happens AT INSERT, and it mirrors the rank
-- table's: an exact per-realm count, and a lazy binary min-heap of
-- {ts, guid} candidates so the oldest row can be found without walking the
-- table on every insert. The heap is built at most once per realm per
-- session, and only when a realm is actually over its cap -- a settlement
-- that never nears the cap never builds it at all.
local gearEntryCount = {}
local gearOldestHeap = {}

-- Drop every trace of one realm's gear bookkeeping. Called whenever the gear
-- table is emptied wholesale or the realm key itself is deleted; the next
-- store into that realm re-seeds a correct count from the table it finds.
local function forgetGearBookkeeping(realmKey)
    gearEntryCount[realmKey] = nil
    gearOldestHeap[realmKey] = nil
end

-- Build the gear heap from the live rows: one pairs() walk, at most once per
-- session per realm plus once after each wholesale removal.
local function ensureGearOldestHeap(realmKey, db)
    local heap = gearOldestHeap[realmKey]
    if heap then
        return heap
    end
    heap = {}
    for guid, entry in pairs(db) do
        heap[#heap + 1] = {
            ts = (type(entry) == "table" and tonumber(entry.t) or 0),
            guid = guid,
        }
    end
    for i = math.floor(#heap / 2), 1, -1 do
        heapDown(heap, i)
    end
    gearOldestHeap[realmKey] = heap
    return heap
end

local function localPlayerGUID()
    local unitGuid = rawget(_G, "UnitGUID")
    if type(unitGuid) ~= "function" then
        return nil
    end
    local ok, guid = pcall(unitGuid, "player")
    if ok and type(guid) == "string" and guid ~= "" then
        return guid
    end
    return nil
end

local function gearSlotAllowed()
    local allowed = {}
    for _, slot in ipairs(RankDB.GEAR_SLOTS) do
        allowed[slot] = true
    end
    return allowed
end

-- Parse a sparse slot=itemID run into canonical order. Strict per pair:
-- decimal slot and id, slot a REQUIRED_SLOTS member, id a positive integer;
-- anything else skips the pair (a ";" inside a blob can never match, so a
-- framing smuggler degrades to a dropped pair, never a shifted stride).
-- Duplicate slots keep the FIRST (stable -- the equal-t fill-gaps path and
-- the multi-chunk path both depend on it). Returns the ordered pair list and
-- the canonical string, or nil when no pair survives.
function RankDB.ParseGearIDs(ids)
    if type(ids) ~= "string" or ids == "" then
        return nil
    end
    local allowed = gearSlotAllowed()
    local seen = {}
    for pair in ids:gmatch("[^,]+") do
        local slotText, itemText = pair:match("^(%d+)=(%d+)$")
        local slot, item = tonumber(slotText), tonumber(itemText)
        if slot and item and allowed[slot] and item > 0
            and item == math.floor(item) and seen[slot] == nil then
            seen[slot] = item
        end
    end
    local ordered = {}
    for _, slot in ipairs(RankDB.GEAR_SLOTS) do
        if seen[slot] then
            ordered[#ordered + 1] = slot .. "=" .. seen[slot]
        end
    end
    if #ordered == 0 then
        return nil
    end
    return ordered, table.concat(ordered, ",")
end

-- Read-only by design: unlike getDB/getGearDB, a read never creates a realm
-- table, so probing for gear cannot orphan one.
function RankDB.GetGear(guid, realm)
    if type(guid) ~= "string" or guid == "" then
        return nil
    end
    local g = _G
    if type(g["TacoTipExtrasDB"]) ~= "table" then
        return nil
    end
    local gear = g["TacoTipExtrasDB"].gear
    if type(gear) ~= "table" then
        return nil
    end
    local db = gear[getRealmKey(realm)]
    if type(db) ~= "table" then
        return nil
    end
    local row = db[guid]
    if type(row) ~= "table" or type(row.ids) ~= "string" then
        return nil
    end
    return { t = tonumber(row.t) or 0, ids = row.ids }
end

local function rebuildGearRun(slotMap)
    local ordered = {}
    for _, slot in ipairs(RankDB.GEAR_SLOTS) do
        if slotMap[slot] then
            ordered[#ordered + 1] = slot .. "=" .. slotMap[slot]
        end
    end
    return table.concat(ordered, ",")
end

local function mapGearRun(ids)
    -- Canonical-run splitter only (stored ids, equal-t ordered lists): no
    -- validation, only splitting. Duplicate slots keep the FIRST, mirroring
    -- ParseGearIDs above -- inputs are canonical on both paths (no dupes
    -- possible), so this only pins the invariant.
    local slotMap = {}
    for pair in ids:gmatch("[^,]+") do
        local slotText, itemText = pair:match("^(%d+)=(%d+)$")
        local slot, item = tonumber(slotText), tonumber(itemText)
        if slot and item and slotMap[slot] == nil then
            slotMap[slot] = item
        end
    end
    return slotMap
end

-- Store one gear row. Dedup on the sender timestamp: an older D never
-- overwrites (stale), an equal-t D fills only slots it does not already hold
-- (first wins on ties -- and the multi-chunk path depends on it, since every
-- chunk of one answer carries the same t with a disjoint slot set), a newer
-- D overwrites slot-by-slot and keeps unmentioned stored slots (partial
-- delivery never loses data; staleness is bounded by the age prune). A
-- missing t stamps 0, which never overwrites an existing row but still files
-- when nothing is stored yet.
function RankDB.StoreGear(guid, t, ids, realm)
    if type(guid) ~= "string" then
        return false, "bad-guid"
    end
    local clean = guid:gsub("[%c;]", ""):match("^%s*(.-)%s*$") or ""
    if clean == "" or #clean > 128 then
        return false, "bad-guid"
    end
    local stamp = math.floor(tonumber(t) or 0)
    if stamp ~= stamp or stamp < 0 or stamp == math.huge then
        stamp = 0
    end
    -- Future-t clamp mirrors the rank timestamp bound (ValidateRecord
    -- sanitizeNumber(record.timestamp, 0, now + 300)): a far-future D would
    -- otherwise pin the row nearly immortal (stale forever, age-prune never
    -- collects, count eviction takes it last). Values past now+300 file as
    -- now, so a later honest D is equal-or-newer, never permanently stale.
    do
        local now = GetServerTime and GetServerTime() or 0
        if stamp > now + 300 then
            stamp = now
        end
    end
    local ordered = RankDB.ParseGearIDs(ids)
    if not ordered then
        return false, "empty"
    end
    local db, realmKey = getGearDB(realm)
    local existing = db[clean]
    if type(existing) == "table" and type(existing.t) == "number" then
        if stamp < existing.t then
            return false, "stale"
        end
        if stamp == existing.t and type(existing.ids) == "string" then
            local slotMap = mapGearRun(existing.ids)
            local changed = false
            for _, pair in ipairs(ordered) do
                local slotText, itemText = pair:match("^(%d+)=(%d+)$")
                local slot = tonumber(slotText)
                if slotMap[slot] == nil then
                    slotMap[slot] = tonumber(itemText)
                    changed = true
                end
            end
            if not changed then
                return true, "unchanged"
            end
            existing.ids = rebuildGearRun(slotMap)
            return true, "filled"
        end
    end
    local slotMap = {}
    if type(existing) == "table" and type(existing.ids) == "string" then
        slotMap = mapGearRun(existing.ids)
    end
    for _, pair in ipairs(ordered) do
        local slotText, itemText = pair:match("^(%d+)=(%d+)$")
        slotMap[tonumber(slotText)] = tonumber(itemText)
    end
    -- Enforce the documented capacity AT INSERT, not only at the next prune.
    --
    -- The same amortized shape as the rank table: the exact row count is
    -- seeded once per realm and then maintained, and the oldest-first
    -- eviction runs off a lazy heap instead of a per-insert pairs() scan.
    -- The semantics are the ones the prune pass already applies: oldest
    -- timestamp first, never more than GEAR_MAX_ENTRIES rows per realm, and
    -- the owner's own guid exempt from COUNT eviction (it is re-persisted
    -- on every own scan) but never from the age prune.
    --
    -- The count is seeded BEFORE the write, exactly as the rank table does
    -- it: seeding after the write would count the new row twice and evict
    -- one row too many.
    if gearEntryCount[realmKey] == nil then
        local seeded = 0
        for _ in pairs(db) do
            seeded = seeded + 1
        end
        gearEntryCount[realmKey] = seeded
    end
    local isNewRow = existing == nil
    if isNewRow then
        gearEntryCount[realmKey] = gearEntryCount[realmKey] + 1
    end

    db[clean] = { t = stamp, ids = rebuildGearRun(slotMap) }

    if gearEntryCount[realmKey] > RankDB.GEAR_MAX_ENTRIES then
        local heapExisted = gearOldestHeap[realmKey] ~= nil
        local heap = ensureGearOldestHeap(realmKey, db)
        -- A heap built right now already walked the table that contains this
        -- new row; only a heap that survived from an earlier insert needs the
        -- push.
        if isNewRow and heapExisted then
            heap[#heap + 1] = { ts = stamp, guid = clean }
            heapUp(heap, #heap)
        end
        local localGuid = localPlayerGUID()
        while gearEntryCount[realmKey] > RankDB.GEAR_MAX_ENTRIES do
            if #heap == 0 then
                gearOldestHeap[realmKey] = nil
                heap = ensureGearOldestHeap(realmKey, db)
                if #heap == 0 then
                    -- The count claims over capacity but no rows remain to
                    -- evict: the bookkeeping is wrong, not the data.
                    -- Re-measure and stop -- correctness here is self-healing,
                    -- never unbounded.
                    local measured = 0
                    for _ in pairs(db) do
                        measured = measured + 1
                    end
                    gearEntryCount[realmKey] = measured
                    break
                end
            end
            -- Pop the root: swap it with the last leaf, drop the leaf, and
            -- sift the new root down.
            local last = #heap
            local oldest = heap[1]
            heap[1] = heap[last]
            heap[last] = nil
            if last > 1 then
                heapDown(heap, 1)
            end

            local row = db[oldest.guid]
            if row ~= nil then
                local rowTs = type(row) == "table" and tonumber(row.t) or nil
                if rowTs == nil then
                    -- Not a row this file could have written (non-table junk
                    -- or a timestamp-less row cannot rank into oldest-order).
                    -- Drop it and keep the count honest.
                    db[oldest.guid] = nil
                    gearEntryCount[realmKey] = gearEntryCount[realmKey] - 1
                elseif rowTs ~= oldest.ts then
                    -- Forward-replaced row: re-file the candidate with the
                    -- live timestamp rather than evicting newer data.
                    heap[#heap + 1] = { ts = rowTs, guid = oldest.guid }
                    heapUp(heap, #heap)
                elseif oldest.guid ~= localGuid then
                    db[oldest.guid] = nil
                    gearEntryCount[realmKey] = gearEntryCount[realmKey] - 1
                end
            end
            -- row == nil: a stale entry -- the row already left the table
            -- through a prune or a purge. Nothing to do but keep popping.
        end
    end

    if existing then
        return true, "merged"
    end
    return true, "stored"
end

-- One realm's gear prune: the age window first, then oldest-t-first count
-- eviction down to the cap. The owner's own guid is exempt from COUNT
-- eviction (it is re-persisted on every own scan) but never from the age
-- prune -- a 60-day-absent local row is correctly dead. Returns removals.
local function pruneGearRealm(realmKey, gearRoot, maxAgeDays, cap)
    local db = gearRoot[realmKey]
    if type(db) ~= "table" then
        return 0
    end
    local now = GetServerTime and GetServerTime() or 0
    local ageLimit = (maxAgeDays or 60) * 24 * 3600
    local cutoff = now > ageLimit and (now - ageLimit) or 0
    local localGuid = nil
    local unitGuid = rawget(_G, "UnitGUID")
    if type(unitGuid) == "function" then
        local ok, guid = pcall(unitGuid, "player")
        if ok and type(guid) == "string" and guid ~= "" then
            localGuid = guid
        end
    end

    local removed = 0
    local survivors = {}
    for guid, row in pairs(db) do
        local stamp = type(row) == "table" and tonumber(row.t) or 0
        if (stamp or 0) < cutoff then
            db[guid] = nil
            removed = removed + 1
        else
            survivors[#survivors + 1] = { guid = guid, t = stamp or 0 }
        end
    end

    if #survivors > cap then
        table.sort(survivors, function(a, b)
            return a.t < b.t
        end)
        local over = #survivors - cap
        for _, candidate in ipairs(survivors) do
            if over <= 0 then
                break
            end
            if candidate.guid ~= localGuid then
                db[candidate.guid] = nil
                removed = removed + 1
                over = over - 1
            end
        end
    end
    return removed
end

-- Every gear realm with the same window as ranks and a tenth of the row cap
-- (defaults 60 days / 2,000; the aggressive pass arrives as 7 / 1,000, so
-- gear halves before ranks do). Emptied realm keys are deleted, never
-- orphaned. Returns total gear removals; the caller folds realm deletions
-- into its own counter.
local function pruneAllGear(gearRoot, maxAgeDays, maxCapacity)
    local ageDays = maxAgeDays or 60
    local cap = math.floor((maxCapacity or MAX_CAPACITY) / 10)
    if cap < 1 then
        cap = 1
    end
    local removed = 0
    local realmKeys = {}
    for key in pairs(gearRoot) do
        realmKeys[#realmKeys + 1] = key
    end
    for _, realmKey in ipairs(realmKeys) do
        if type(gearRoot[realmKey]) ~= "table" then
            gearRoot[realmKey] = nil
            forgetGearBookkeeping(realmKey)
        else
            removed = removed + pruneGearRealm(realmKey, gearRoot, ageDays, cap)
            -- The prune removed rows wholesale, so the amortized count and the
            -- heap snapshot are stale by definition. Forget them: the next
            -- store into this realm re-seeds a correct count from the table
            -- it finds. (The same self-healing rule the rank table uses.)
            forgetGearBookkeeping(realmKey)
            if next(gearRoot[realmKey]) == nil then
                gearRoot[realmKey] = nil
            end
        end
    end
    return removed
end

-- Prune every realm we know about, and reclaim obsolete realm tables.
--
-- Stage 2's login pass (audit §6.2 item 1). Nothing iterated
-- TacoTipExtrasDB.ranks before this existed, so a realm table outlived its
-- last active member forever -- including the old key a realm transfer leaves
-- behind. The pass prunes each realm with the given limits and deletes a
-- realm key the prune left empty (plus any non-table junk, which getDB would
-- otherwise paper over with a fresh table until the end of time).
--
-- Defaults match PruneStaleRecords: 60 days and MAX_CAPACITY. Returns the
-- number of rows removed and the number of realm keys deleted.
function RankDB.PruneAllRealms(maxAgeDays, maxCapacity)
    local g = _G
    if type(g["TacoTipExtrasDB"]) ~= "table" then
        return 0, 0, 0
    end
    local root = g["TacoTipExtrasDB"]

    local removedTotal = 0
    local realmsDeleted = 0

    if type(root["ranks"]) == "table" then
        -- Snapshot the keys: this pass deletes some of them.
        local realmKeys = {}
        for key in pairs(root["ranks"]) do
            realmKeys[#realmKeys + 1] = key
        end

        for _, realmKey in ipairs(realmKeys) do
            if type(root["ranks"][realmKey]) ~= "table" then
                root["ranks"][realmKey] = nil
                forgetRealm(realmKey)
                realmsDeleted = realmsDeleted + 1
            else
                removedTotal = removedTotal
                    + RankDB.PruneStaleRecords(realmKey, maxAgeDays, maxCapacity)
                -- PruneStaleRecords leaves the bookkeeping exact, so it is the
                -- row count of record here.
                if (entryCount[realmKey] or 0) == 0 then
                    root["ranks"][realmKey] = nil
                    forgetRealm(realmKey)
                    realmsDeleted = realmsDeleted + 1
                end
            end
        end
    end

    -- Stage 4: the same pass prunes the gear side table with the same age
    -- window and a tenth of the row cap (default 60 days / 2,000 rows;
    -- aggressive 7 days / 1,000 -- gear halves before ranks do). Rank return
    -- values are untouched; gear removals ride a third return so no caller
    -- changes shape.
    local gearRemoved = 0
    if type(root["gear"]) == "table" then
        gearRemoved = pruneAllGear(root["gear"], maxAgeDays, maxCapacity)
    end

    return removedTotal, realmsDeleted, gearRemoved
end

-- The SAVED_VARIABLES_TOO_LARGE response (audit §6.2 Stage 2 item 5).
-- Whatever write failed has to stop being too large before the NEXT logout,
-- or the client will refuse the file again.
local AGGRESSIVE_MAX_AGE_DAYS = 7
local AGGRESSIVE_MAX_CAPACITY = math.floor(MAX_CAPACITY / 2)

function RankDB.PruneAggressive()
    return RankDB.PruneAllRealms(AGGRESSIVE_MAX_AGE_DAYS, AGGRESSIVE_MAX_CAPACITY)
end

function RankDB.PurgeDatabase(realm)
    local db, realmKey = getDB(realm)
    local count = 0
    for k in pairs(db) do
        db[k] = nil
        count = count + 1
    end
    dirtyFlags[realmKey] = true
    cachedIndices[realmKey] = nil
    cachedLookups[realmKey] = nil
    forgetRowBookkeeping(realmKey)
    return count
end
