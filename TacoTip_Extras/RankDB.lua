local _, namespace = ...

if type(namespace) ~= "table" then
    return
end

local RankDB = {}
namespace.RankDB = RankDB

local MAX_CAPACITY = 5000
local MAX_AGE_SECONDS = 60 * 24 * 3600 -- 60 days
local MAX_GEARSCORE = 15000
local MAX_ILVL = 1500

RankDB.MAX_CAPACITY = MAX_CAPACITY
RankDB.MAX_AGE_SECONDS = MAX_AGE_SECONDS

local dirtyFlags = {}
local cachedIndices = {}
local cachedLookups = {}

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

function RankDB.ValidateRecord(record)
    if type(record) ~= "table" then
        return nil, "record must be a table"
    end

    local guid = sanitizeString(record.guid, 128)
    if not guid then
        return nil, "invalid or missing GUID"
    end

    local name = sanitizeString(record.name, 64)
    if not name then
        return nil, "invalid or missing name"
    end

    local gs = sanitizeNumber(record.gs, 1, MAX_GEARSCORE)
    if not gs then
        return nil, "invalid gearscore"
    end

    local ilvl = sanitizeNumber(record.ilvl, 1, MAX_ILVL) or 0
    local now = time and time() or 0
    local timestamp = sanitizeNumber(record.timestamp, 0, now + 300) or now

    local faction = sanitizeString(record.faction, 16) or "Unknown"
    if faction ~= "Alliance" and faction ~= "Horde" then
        faction = "Unknown"
    end

    local class = sanitizeString(record.class, 32) or "UNKNOWN"
    local classID = sanitizeNumber(record.classID, 1, 32) or 0
    local specName = sanitizeString(record.specName, 64) or ""
    local specIcon = record.specIcon
    if type(specIcon) ~= "string" and type(specIcon) ~= "number" then
        specIcon = nil
    end

    return {
        guid = guid,
        name = name,
        faction = faction,
        class = class,
        classID = classID,
        specName = specName,
        specIcon = specIcon,
        gs = math.floor(gs + 0.5),
        ilvl = math.floor(ilvl * 10 + 0.5) / 10,
        timestamp = math.floor(timestamp),
        source = sanitizeString(record.source, 16) or "sync",
    }
end

function RankDB.StoreRecord(record, realm)
    local clean, err = RankDB.ValidateRecord(record)
    if not clean then
        return false, err
    end

    local db, realmKey = getDB(realm or record.realm)
    local existing = db[clean.guid]

    if existing and type(existing.timestamp) == "number" and existing.timestamp >= clean.timestamp then
        return true, "up-to-date"
    end

    db[clean.guid] = clean
    dirtyFlags[realmKey] = true

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

    local now = time and time() or 0
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

function RankDB.GetLeaderboard(realm, tab, classFilter, searchQuery)
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

    if not hasClass and not hasQuery then
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
    local now = time and time() or 0
    local cutoff = now > ageLimit and (now - ageLimit) or 0

    local removed = 0
    local remaining = {}

    for guid, entry in pairs(db) do
        if type(entry) == "table" and (entry.timestamp or 0) < cutoff then
            db[guid] = nil
            removed = removed + 1
        else
            remaining[#remaining + 1] = { guid = guid, timestamp = entry.timestamp or 0 }
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

    return removed
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
    return count
end
