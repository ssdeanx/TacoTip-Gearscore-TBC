-- Batch 2 Pawn pins: late-load gate, throttle unification, helper dedup.
--
-- Loads the REAL gearscore.lua + pawn.lua in a sandbox with Pawn ABSENT, then
-- drives absent-then-present without reloading. No new harness patterns: the
-- sandbox, STD allowlist and sandboxedChunk shape follow gearscore_test.lua;
-- the Pawn registry shape follows load_test.lua (one provider, proven names).
-- Usage: lua5.1 batch2_pawn_test.lua (client-independent: no projectId/iface args)

local _hp = ((arg and arg[0]) or "Tests/harness/batch2_pawn_test.lua"):gsub("\\", "/")
local _hd = _hp:match("^(.*)/[^/]*$") or "."
local ROOT = dofile(_hd .. "/root.lua") .. "/"

local unpack = unpack or table.unpack

local STD = {
    os = os, string = string, pairs = pairs, ipairs = ipairs, type = type,
    pcall = pcall, tonumber = tonumber, tostring = tostring, select = select,
    rawget = rawget, rawset = rawset, setmetatable = setmetatable,
    getmetatable = getmetatable, unpack = unpack, assert = assert, error = error,
    math = math, table = table, loadfile = loadfile, print = print, io = io,
}

local checks = {}
local function check(name, cond, detail)
    checks[#checks + 1] = { name, cond and true or false, detail }
end

local SELF_GUID = "Player-1-000000AA"
local ITEM_ID = 99991

local rawCalls = 0
local clock = 1000

local function buildEnv()
    local env = {}
    env._G = env
    for k, v in STD.pairs(STD) do env[k] = v end

    env.GetTime = function() return clock end
    env.time = STD.os.time
    env.strlower = STD.string.lower
    env.print = function() end
    env.CreateFrame = function()
        return { RegisterEvent = function() end, SetScript = function() end }
    end
    env.GetBuildInfo = function()
        return "1.15.9", "69722", "date", 11509, "us", "release"
    end
    env.WOW_PROJECT_MAINLINE = 1
    env.WOW_PROJECT_CLASSIC = 2
    env.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
    env.WOW_PROJECT_WRATH_CLASSIC = 11
    env.WOW_PROJECT_ID = 2

    env.C_PlayerInfo = {
        GUIDIsPlayer = function(g)
            return type(g) == "string" and string.find(g, "Player-", 1, true) == 1
        end,
    }
    env.C_Item = {
        GetItemInfo = function() return nil end,
        RequestLoadItemDataByID = function(id)
            rawCalls = rawCalls + 1
        end,
    }
    env.UnitIsPlayer = function(u) return u == SELF_GUID end
    env.UnitGUID = function(u) if u == "player" then return SELF_GUID end return nil end
    env.GetPlayerInfoByGUID = function() return true, "Tester", "WARRIOR" end

    -- NOTE: no Pawn globals on purpose: the absent-then-present drive below
    -- establishes them AFTER load. A file-scope-only gate (the reverted shape)
    -- leaves TT_PAWN nil here, which is exactly what check 1 bites on.
    env.PawnClassicLastUpdatedVersion = nil
    env.PawnLastUpdatedVersion = nil

    local CI = {}
    function CI:IsClassic() return true end
    function CI:IsTBC() return false end
    function CI:IsWotlk() return false end
    function CI:IsForever() return false end
    function CI:IsRetail() return false end
    function CI:GetLastCacheTime() return clock, clock end
    function CI:GetSpecialization(guid) return 1 end
    function CI:GetSpecializationName(class, spec, short) return "Arms" end
    -- One uncached slot so each GetScore issues exactly one item request.
    -- NOTE the colon-definition arity: `self` is implicit, so the first
    -- declared param after the colon is the guid (see gearscore_test.lua).
    function CI:GetInventoryItemMixin(unitorguid, slot)
        if (slot ~= 1) then return nil end
        return {
            IsItemDataCached = function() return false end,
            GetItemLink = function() return "item:" .. ITEM_ID end,
            GetItemID = function() return ITEM_ID end,
            ContinueOnItemLoad = function() end,
        }
    end

    local libs = {
        ["LibForeverInspector"] = CI,
        ["LibDetours-1.0"] = { Hook = function() end },
    }
    local stub = setmetatable({}, {
        __call = function(_, name, silent)
            local lib = libs[name]
            if (not lib and not silent) then
                error("Cannot find a library instance of " .. tostring(name) .. ".", 2)
            end
            return lib
        end,
    })
    function stub:GetLibrary(name, silent) return self(name, silent) end
    env.LibStub = stub

    env.TacoTip_GSCallback = function() end

    return env
end

STD.setfenv = setfenv
STD.loadstring = loadstring
STD.load = load

local function sandboxedChunk(path, env)
    local fh = assert(io.open(path, "rb"), "cannot open " .. path)
    local src = fh:read("*a")
    fh:close()
    if (STD.setfenv and STD.loadstring) then
        local chunk = assert(STD.loadstring(src, "@" .. path))
        STD.setfenv(chunk, env)
        return chunk
    end
    return assert(STD.load(src, "@" .. path, "t", env))
end

local env = buildEnv()
local ok, err = pcall(sandboxedChunk(ROOT .. "gearscore.lua", env), "TacoTip_Forever")
if (not ok) then
    STD.io.write("BATCH2 PAWN LOAD FAIL gearscore.lua -> " .. tostring(err) .. "\n")
    STD.os.exit(1)
end
local ok2, err2 = pcall(sandboxedChunk(ROOT .. "pawn.lua", env), "TacoTip_Forever")
if (not ok2) then
    STD.io.write("BATCH2 PAWN LOAD FAIL pawn.lua -> " .. tostring(err2) .. "\n")
    STD.io.write("*** FAILURES ***\n")
    STD.os.exit(1)
end

local PAWN = env.TT_PAWN
local GS = env.TT_GS

-- 1. Late-load: the module loads with Pawn absent (no early return).
check("TT_PAWN exists with Pawn absent at load (no file-scope amputation)",
    type(PAWN) == "table", "TT_PAWN=" .. tostring(PAWN))
check("TT_GS shared home exists",
    type(GS) == "table", "TT_GS=" .. tostring(GS))

if (type(PAWN) == "table") then
    check("IsAvailable is exposed as a call-time probe",
        type(PAWN.IsAvailable) == "function")
    check("IsAvailable reports false with Pawn absent",
        PAWN.IsAvailable and PAWN.IsAvailable() == false or PAWN.IsAvailable == nil,
        "available=" .. tostring(PAWN.IsAvailable and PAWN.IsAvailable()))
    check("WasAvailableAtLoad snapshots the absent state",
        PAWN.WasAvailableAtLoad == false,
        "WasAvailableAtLoad=" .. tostring(PAWN.WasAvailableAtLoad))
    -- Call-time gate: GetScore with Pawn absent returns the empty triple
    -- rather than raising or scoring.
    local s0 = PAWN:GetScore(SELF_GUID, false)
    check("GetScore with Pawn absent returns 0 (call-time gate)",
        s0 == 0, "score=" .. tostring(s0))

    -- Absent-then-present WITHOUT a reload: establish the same globals a
    -- late Pawn would (version gate + API + one-provider registry).
    env.PawnClassicLastUpdatedVersion = 2.0538
    env.PawnGetItemData = function() return {} end
    env.PawnGetSingleValueFromItem = function() return nil end
    env.PawnGetScaleColor = function() return 1, 1, 1 end
    env.PawnScaleProviders = { Classic = { Name = "Classic" } }
    env.PawnCommon = { Scales = { ['"Classic":WARRIOR1'] = {} } }

    check("IsAvailable reports true after Pawn appears (no reload)",
        PAWN.IsAvailable and PAWN.IsAvailable() == true,
        "available=" .. tostring(PAWN.IsAvailable and PAWN.IsAvailable()))
    check("...while the load-time snapshot still records the absent state",
        PAWN.WasAvailableAtLoad == false,
        "WasAvailableAtLoad=" .. tostring(PAWN.WasAvailableAtLoad))

    -- 2. Throttle unification: two rapid Pawn-path renders cost one raw request.
    rawCalls = 0
    clock = 5000
    PAWN:GetScore(SELF_GUID, false)
    local afterFirst = rawCalls
    PAWN:GetScore(SELF_GUID, false)
    local afterSecond = rawCalls
    check("first Pawn render issues one raw item request",
        afterFirst == 1, "rawCalls=" .. tostring(afterFirst))
    check("second rapid Pawn render issues no further raw request (2s throttle)",
        afterSecond == 1, "rawCalls=" .. tostring(afterSecond))
    -- Vacuity: the window must expire -- advancing past 2s re-requests.
    clock = 5003
    PAWN:GetScore(SELF_GUID, false)
    check("...and the throttle expires after the window",
        rawCalls == 2, "rawCalls=" .. tostring(rawCalls))

    -- 2b. Batch 3 hunter H6 (Pawn half): a not-ready Pawn score counts the
    -- shared pending-hidden counter instead of reading as absent. The slot 1
    -- mixin above is uncached, so every render here takes the pending path.
    -- Revert map: drop the gs:CountPendingHidden() call in pawn.lua -> still.
    do
        local addonTT = env.TacoTip_Forever
        local pendingBefore = (addonTT and addonTT.ev and addonTT.ev.gsPendingHidden) or 0
        local ps = PAWN:GetScore(SELF_GUID, false)
        check("not-ready Pawn score reads 0", ps == 0, "score=" .. tostring(ps))
        check("...and counts the shared pending-hidden",
            ((addonTT and addonTT.ev and addonTT.ev.gsPendingHidden) or 0) == pendingBefore + 1,
            "gsPendingHidden=" .. tostring(addonTT and addonTT.ev and addonTT.ev.gsPendingHidden))
    end

    -- 4. Batch 4 N2: an unresolvable spec returns no-score/blank, never
    -- spec-1. Revert map: restore `or 1` on the spec line in pawn.lua ->
    -- resolves scale WARRIOR1 and returns the spec-1 name below (red).
    do
        local CI = env.LibStub("LibForeverInspector", true)
        local savedSpec = CI.GetSpecialization
        local savedMixin = CI.GetInventoryItemMixin
        CI.GetSpecialization = function() return nil end
        CI.GetInventoryItemMixin = function(unitorguid, slot)
            if (slot ~= 1) then return nil end
            return {
                IsItemDataCached = function() return true end,
                GetItemLink = function() return "item:" .. ITEM_ID end,
                GetItemID = function() return ITEM_ID end,
                ContinueOnItemLoad = function() end,
            }
        end
        local s, n, c = PAWN:GetScore(SELF_GUID, false)
        check("unresolvable spec returns no Pawn score", s == 0, "score=" .. tostring(s))
        check("...and a blank spec name (never spec-1)",
            n == "", "name=" .. tostring(n))
        check("...and the blank colour",
            c == "|cffffffff", "colour=" .. tostring(c))
        CI.GetSpecialization = savedSpec
        CI.GetInventoryItemMixin = savedMixin
    end

    -- 3. Helper dedup: both paths share one drain implementation.
    if (type(GS) == "table") then
        check("pawn and gearscore share one drain implementation",
            PAWN.DrainItemCache ~= nil and PAWN.DrainItemCache == GS.DrainItemCache,
            "pawn=" .. tostring(PAWN.DrainItemCache) .. " gs=" .. tostring(GS and GS.DrainItemCache))
        check("pawn routes GUID resolution through the shared home",
            type(GS.ResolvePlayerGUID) == "function"
                and GS.ResolvePlayerGUID(SELF_GUID) == SELF_GUID,
            "ResolvePlayerGUID=" .. tostring(GS and GS.ResolvePlayerGUID))
        -- Latch invariant survives the sharing: a duplicate-slot table drains
        -- once no matter which home's reference fires it.
        local fired = 0
        env.TacoTip_GSCallback = function() fired = fired + 1 end
        local tbl = { guid = SELF_GUID, items = { ITEM_ID, ITEM_ID } }
        PAWN.DrainItemCache(tbl, ITEM_ID)
        check("duplicate-slot drain fires the completion callback exactly once",
            fired == 1 and tbl.completed == true,
            "fired=" .. tostring(fired) .. " completed=" .. tostring(tbl.completed))
        PAWN.DrainItemCache(tbl, ITEM_ID)
        check("...and a drained table never refires",
            fired == 1, "fired=" .. tostring(fired))
    end

    -- 5. Batch 5 N3: string-typed version globals neither raise nor
    -- misresolve. The single home (TT_PAWN.IsAvailable) guards the compare
    -- with tonumber(); a non-numeric version reads as absent and falls
    -- through to the API fallback. Revert map: drop the tonumber guard in
    -- pawn.lua -> the non-numeric string compare raises (red on every
    -- interpreter; the numeric-string case raises on 5.4, coerces on
    -- 5.1/LuaJIT, so only the non-numeric checks bite there).
    do
        local savedClassic, savedRetail =
            env.PawnClassicLastUpdatedVersion, env.PawnLastUpdatedVersion
        local savedData, savedSingle, savedColor =
            env.PawnGetItemData, env.PawnGetSingleValueFromItem, env.PawnGetScaleColor
        -- Numeric string resolves: "2.0" meets the 2.0 retail threshold.
        env.PawnClassicLastUpdatedVersion = nil
        env.PawnLastUpdatedVersion = "2.0"
        env.PawnGetItemData, env.PawnGetSingleValueFromItem, env.PawnGetScaleColor = nil, nil, nil
        local okStr, availStr = pcall(PAWN.IsAvailable)
        check("string-typed retail version does not raise", okStr == true,
            "err=" .. tostring(availStr))
        check("...and resolves available (\"2.0\" meets 2.0)",
            availStr == true, "available=" .. tostring(availStr))
        -- Non-numeric string reads as absent, never raises.
        env.PawnLastUpdatedVersion = "2.0.1-beta"
        local okGarb, availGarb = pcall(PAWN.IsAvailable)
        check("non-numeric version string does not raise", okGarb == true,
            "err=" .. tostring(availGarb))
        check("...and resolves unavailable (no API present)",
            availGarb == false, "available=" .. tostring(availGarb))
        -- ...unless the API fallback carries it.
        env.PawnGetItemData = function() return {} end
        env.PawnGetSingleValueFromItem = function() return nil end
        env.PawnGetScaleColor = function() return 1, 1, 1 end
        local okApi, availApi = pcall(PAWN.IsAvailable)
        check("garbage version + live API still resolves available",
            okApi == true and availApi == true,
            "available=" .. tostring(availApi))
        env.PawnClassicLastUpdatedVersion = savedClassic
        env.PawnLastUpdatedVersion = savedRetail
        env.PawnGetItemData, env.PawnGetSingleValueFromItem, env.PawnGetScaleColor =
            savedData, savedSingle, savedColor
    end

    -- 6. Hunter H-NEW3: a nil scaleName external call returns 0 WITHOUT
    -- guessing, and without touching PawnGetSingleValueFromItem (whose
    -- VgerCore.Fail chat path pcall cannot suppress). Revert map: restore a
    -- guessing nil-scaleName path in TT_PAWN:GetItemScore -> the nil call
    -- below attempts a lookup (red). The provided-name path is unchanged:
    -- a proven scale name still resolves.
    do
        local lookups = 0
        local savedSingle6 = env.PawnGetSingleValueFromItem
        env.PawnGetSingleValueFromItem = function(item, name)
            lookups = lookups + 1
            if (name == '"Classic":WARRIOR1') then return nil, 5 end
            return nil
        end
        local nilScore = PAWN:GetItemScore("item:" .. ITEM_ID, "WARRIOR", 1, nil)
        check("nil scaleName returns 0 (resolve-then-call, no guessing)",
            nilScore == 0, "score=" .. tostring(nilScore))
        check("...without a single Pawn lookup (no VgerCore.Fail path)",
            lookups == 0, "lookups=" .. tostring(lookups))
        local provenScore = PAWN:GetItemScore("item:" .. ITEM_ID, "WARRIOR", 1, '"Classic":WARRIOR1')
        check("...while a proven scale name still resolves through Pawn",
            provenScore == 5, "score=" .. tostring(provenScore))
        env.PawnGetSingleValueFromItem = savedSingle6
    end
end

local fails = 0
for _, c in STD.ipairs(checks) do
    if (not c[2]) then
        fails = fails + 1
        STD.io.write(string.format("    FAIL %-50s %s\n", c[1], tostring(c[3] or "")))
    end
end
STD.io.write(string.format("%-12s %s\n", "batch2_pawn",
    (fails == 0) and ("ALL " .. #checks .. " PASS")
        or (fails .. "/" .. #checks .. " FAILED")))
STD.os.exit(fails == 0 and 0 or 1)
