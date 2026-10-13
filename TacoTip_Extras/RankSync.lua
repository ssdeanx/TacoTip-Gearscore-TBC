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

function RankSync.DeserializeRecord(payload)
    if type(payload) ~= "string" then return nil end
    local parts = {}
    for part in payload:gmatch("([^;]+)") do
        parts[#parts + 1] = part
    end
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

local function onEvent(_, event, arg1, arg2, arg3)
    if event == "CHAT_MSG_ADDON" then
        if arg1 == PREFIX and type(arg2) == "string" then
            local rec = RankSync.DeserializeRecord(arg2)
            if rec and namespace.RankDB and type(namespace.RankDB.StoreRecord) == "function" then
                namespace.RankDB.StoreRecord(rec)
            end
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        registerPrefix()
        local cTimer = rawget(_G, "C_Timer")
        if type(cTimer) == "table" and type(cTimer.After) == "function" then
            cTimer.After(4.0, joinSyncChannel)
        else
            joinSyncChannel()
        end
    end
end

if syncFrame then
    syncFrame:RegisterEvent("CHAT_MSG_ADDON")
    syncFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    syncFrame:SetScript("OnEvent", onEvent)
    syncFrame:SetScript("OnUpdate", function(_, elapsed)
        if #sendQueue > 0 then
            processQueue()
        end
    end)
end
