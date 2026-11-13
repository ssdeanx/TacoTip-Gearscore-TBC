-- The strong secret-value guard, exercised under a THROWING issecretvalue.
--
-- WHY THIS FILE EXISTS. The suite already had two secret sentinels
-- (tooltip_test.lua:2318 `function(v) return v == SECRET_MAX or v == SECRET_POWER end`,
-- forever_tooltip_test.lua:2377 `function(v) return v == SECRET_STR end`), and
-- 140/140 Forever pins stayed green through the audit that found the weak guard.
-- The reason is in the mocks: both model issecretvalue as a predicate that never
-- raises. The client contract the guard exists for is the opposite. On WoW
-- Forever and Retail the generated docs declare
--   Interface/AddOns/Blizzard_APIDocumentationGenerated/FrameScriptDocumentation.lua:287
--     issecretvalue -- { Name = "value", Type = "any", SecretArguments = "AllowedWhenUntainted" }
-- (origin/forever and origin/live; the classic branches carry no secret API).
-- "AllowedWhenUntainted" means a call from TAINTED execution RAISES when the
-- value is secret. That raise is the case the guard is for, and no pin in the
-- tree ever produced it.
--
-- THE TWO FORMS.
--   weak (HEAD, pre-fix):  local okSecret, isSec = pcall(issecretvalue, v)
--                          if (okSecret and isSec) then return true end
--   strong (fixed):        if (not okSecret or isSec == true) then return true end
-- pcall(issecretvalue, v) can only raise for one reason: v is a secret value and
-- this execution is not allowed to ask. So a raise is affirmative evidence of
-- "secret", and the weak form classified the one unverifiable answer as the one
-- provably wrong one -- "not secret" -- then carried v into GUID resolution,
-- cache indexing and comparison. The strong form stops at "unknown".
--
-- HOW IT IS PINNED. Not by matching the source text, and not by re-declaring a
-- copy of the predicate (a copy stays green after the shipped guard regresses).
-- The REAL gearscore.lua, the REAL LibForeverInspector and the REAL pawn.lua are
-- loaded into private sandboxes -- never _G, so nothing here can perturb the rest
-- of the suite -- and the file-local isSecretValue / getPlayerGUID /
-- safeUnitIsUnit are reached through the loaded functions' upvalues. The
-- assertions therefore run the shipped closures against a mocked client contract.
--
-- Env overrides (red/green proof only; never used in gates). Each is a path to a
-- throwaway copy, exactly like forever_tooltip_test.lua's MAIN/LIB overrides:
--   TACOTIP_GS_OVERRIDE=/tmp/gearscore_old.lua            pre-fix gearscore.lua
--   TACOTIP_LFI_OVERRIDE=/tmp/LibForeverInspector_old.lua pre-fix inspector
--   TACOTIP_PAWN_OVERRIDE=/tmp/pawn_old.lua               pre-fix pawn.lua
-- Every pin below was shown RED on `git show HEAD:`-derived copies and GREEN on
-- the working tree; see the header of custompos_test.lua for the sibling pin.
--
-- The pawn section (added with t5's safeUnitIsUnit guard) pins the guard itself:
-- the predicate scenarios, the GUID resolver, and the self-detection path, where
-- the pre-fix file boolean-tests a raw `pcall(UnitIsUnit, ...)` result
-- (pawn.lua HEAD :170-171 `if (okUIU and isUnit == true)`) and never consults the
-- client's C_Secrets.CanCompareUnitTokens pre-check.
--
-- Usage: lua5.1 Tests/harness/secretguard_test.lua
-- Client-independent: the guard is file-local and runs on every client; the
-- sandbox models the Forever/Retail pair, where the secret API exists.

local _hp = ((arg and arg[0]) or "Tests/harness/secretguard_test.lua"):gsub("\\", "/")
local _hd = _hp:match("^(.*)/[^/]*$") or "."
local ROOT = dofile(_hd .. "/root.lua") .. "/"

local REALG = _G
local unpack = unpack or table.unpack
-- Read out of the environment rather than named directly: `debug` is not in
-- .luacheckrc's read_globals, and rawget keeps this file at 0 warnings without
-- teaching the repo's lint config about a global the shipped addon never uses.
local DEBUG = rawget(_G, "debug")

local STD = {
    os = os, string = string, pairs = pairs, ipairs = ipairs, type = type,
    pcall = pcall, tonumber = tonumber, tostring = tostring, select = select,
    rawget = rawget, rawset = rawset, setmetatable = setmetatable,
    getmetatable = getmetatable, unpack = unpack, assert = assert, error = error,
    next = next, math = math, table = table, print = print, io = io,
    load = load, loadstring = loadstring, setfenv = setfenv, debug = DEBUG,
}

local checks = {}
local function check(name, cond, detail)
    checks[#checks + 1] = { name, cond and true or false, detail }
end

-- ---- the mocked client contract ------------------------------------------
--
-- SENTINEL models a secret value as an opaque distinct value: the only thing the
-- addon may do with it is ask issecretvalue / canaccessvalue, and on the
-- Forever/Retail pair the tainted answer is a raise rather than a boolean.
local SENTINEL = {}

-- Distinguishes "call the predicate with nil" from the default "call it with the
-- sentinel" in the scenario table below.
local AS_NIL = {}

local function throwingFor(secretValue)
    return function(v)
        if (v == secretValue) then
            STD.error("issecretvalue on a secret value from tainted execution", 0)
        end
        return false
    end
end

local function accessThrowingFor(secretValue)
    return function(v)
        if (v == secretValue) then
            STD.error("canaccessvalue on a secret value from tainted execution", 0)
        end
        return true
    end
end

-- ---- sandbox plumbing -----------------------------------------------------

local function sandbox(globals)
    local env = {}
    env._G = env
    -- Seed the standard library first, the way a WoW chunk sees it; the client
    -- mocks and this harness's controlled copies of the secret API go on top.
    for k, v in STD.pairs(STD) do env[k] = v end
    for k, v in STD.pairs(globals or {}) do env[k] = v end
    return env
end

local function sandboxChunk(path, env)
    local fh = assert(STD.io.open(path, "rb"), "cannot open " .. path)
    local src = fh:read("*a")
    fh:close()
    if (STD.setfenv and STD.loadstring) then
        local chunk = assert(STD.loadstring(src, "@" .. path))
        STD.setfenv(chunk, env)
        return chunk
    end
    return assert(STD.load(src, "@" .. path, "t", env))
end

-- Reach a file-local through the loaded closures. The guard is `local`, so this
-- is the only way to run the SHIPPED predicate; a text-extracted copy would keep
-- passing after the production guard regressed, which is the defect class this
-- file exists to catch. Search the upvalue graph breadth-first because the
-- predicate is a direct upvalue of GetScore/GetUnitData only by construction.
local function upvalueNamed(fn, wanted, depth)
    if (not STD.debug or STD.type(STD.debug.getupvalue) ~= "function") then return nil end
    depth = depth or 2
    local seen, queue, head = {}, { { fn, 0 } }, 1
    while head <= #queue do
        local cur, d = queue[head][1], queue[head][2]
        head = head + 1
        if (not seen[cur]) then
            seen[cur] = true
            local i = 1
            while true do
                local name, value = STD.debug.getupvalue(cur, i)
                if (not name) then break end
                if (name == wanted and STD.type(value) == "function") then return value end
                if (d < depth and STD.type(value) == "function") then
                    queue[#queue + 1] = { value, d + 1 }
                end
                i = i + 1
            end
        end
    end
    return nil
end

-- ---- the guard scenarios --------------------------------------------------
--
-- Run against one loaded predicate. Each scenario swaps the sandbox's own
-- issecretvalue / canaccessvalue globals, which the predicate reads at call
-- time, and then calls the predicate with the sentinel.
local function guardScenarios(label, env, pred)
    if (not pred) then
        check(label .. ": the file-local isSecretValue was found in the loaded chunk", false,
            "no upvalue named isSecretValue -- the guard was renamed or restructured")
        return
    end

    local function scenario(desc, secretFn, accessFn, value, want)
        if (value == nil) then value = SENTINEL elseif (value == AS_NIL) then value = nil end
        env.issecretvalue = secretFn
        env.canaccessvalue = accessFn
        local ok, got = STD.pcall(pred, value)
        check(label .. ": " .. desc,
            ok and got == want,
            "want=" .. STD.tostring(want) .. " got=" .. STD.tostring(got)
                .. " raised=" .. STD.tostring(not ok))
    end

    -- The audit's case, and the red/green carrier: a raise is the client's
    -- affirmative "this is secret and you may not ask".
    scenario("a THROWING issecretvalue reads as secret", throwingFor(SENTINEL), nil, nil, true)
    -- The client's direct answer.
    scenario("issecretvalue true reads as secret",
        function(v) return v == SENTINEL end, nil, nil, true)
    -- canaccessvalue is the second opinion, and a false answer is a secret.
    scenario("canaccessvalue false reads as secret",
        function() return false end, function(v) return v ~= SENTINEL end, nil, true)
    -- A throwing canaccessvalue is the same evidence as a throwing issecretvalue.
    scenario("a THROWING canaccessvalue reads as secret",
        function() return false end, accessThrowingFor(SENTINEL), nil, true)
    -- ...and the guard must not degrade into "everything is secret": these are
    -- the cases a lazy `return true` would break.
    scenario("a readable non-secret value reads as NOT secret",
        function() return false end, function() return true end, nil, false)
    scenario("no secret API at all reads as NOT secret", nil, nil, nil, false)
    scenario("a non-secret value is NOT secret under the throwing mock",
        throwingFor(SENTINEL), nil, "player", false)
    scenario("nil is NOT secret even with a throwing mock",
        throwingFor(SENTINEL), nil, AS_NIL, false)
end

-- ---- the sentinel's own contract ------------------------------------------
--
-- If the mocked issecretvalue ever stops raising, every scenario above becomes
-- vacuous and the suite silently returns to modelling a never-throwing client --
-- the exact gap this file exists to close. So the sentinel is pinned first.
do
    local env = sandbox({})
    env.issecretvalue = throwingFor(SENTINEL)
    env.canaccessvalue = accessThrowingFor(SENTINEL)
    local secretOk = STD.pcall(env.issecretvalue, SENTINEL)
    check("meta: pcall(issecretvalue, <secret>) FAILS, as the client's tainted contract does",
        secretOk == false, "pcall returned " .. STD.tostring(secretOk))
    local accessOk = STD.pcall(env.canaccessvalue, SENTINEL)
    check("meta: pcall(canaccessvalue, <secret>) FAILS", accessOk == false,
        "pcall returned " .. STD.tostring(accessOk))
    local plainOk, plainValue = STD.pcall(env.issecretvalue, "player")
    check("meta: a non-secret value still answers normally through the same mock",
        plainOk == true and plainValue == false,
        "ok=" .. STD.tostring(plainOk) .. " value=" .. STD.tostring(plainValue))
end

-- ---- gearscore.lua --------------------------------------------------------

local GEARSCORE_PATH = STD.os.getenv("TACOTIP_GS_OVERRIDE") or (ROOT .. "gearscore.lua")

do
    local calls = { unitIsPlayer = 0, unitGUID = 0 }
    local SECRET_GUID = SENTINEL
    local PLAYER_GUID = "Player-1-000000AA"
    local env = sandbox({
        WOW_PROJECT_ID = 1,
        WOW_PROJECT_MAINLINE = 1,
        WOW_PROJECT_CLASSIC = 2,
        WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5,
        GetBuildInfo = function() return "1.15.9", "69722", "date", 16001, "us", "release" end,
        GetTime = function() return 1234567 end,
        strlower = STD.string.lower,
        print = function() end,
        CreateFrame = function()
            return { RegisterEvent = function() end, SetScript = function() end }
        end,
        -- The mocked client contract, installed before the chunk is loaded so
        -- the predicate resolves them at call time.
        issecretvalue = throwingFor(SENTINEL),
    })
    env.C_PlayerInfo = {
        GUIDIsPlayer = function(g)
            return STD.type(g) == "string"
                and STD.string.find(g, "Player-", 1, true) == 1
        end,
    }
    -- A secret unit token cannot be read: record the attempt, then answer with a
    -- secret GUID, which is what the weak guard then carried as a real one.
    env.UnitIsPlayer = function(u)
        if (u == SENTINEL) then calls.unitIsPlayer = calls.unitIsPlayer + 1 end
        return true
    end
    env.UnitGUID = function(u)
        if (u == SENTINEL) then
            calls.unitGUID = calls.unitGUID + 1
            return SECRET_GUID
        end
        return PLAYER_GUID
    end
    env.GetPlayerInfoByGUID = function() return "Warrior", "WARRIOR" end
    -- LibStub carrying the inspector surface GetScore reads. The cache time must
    -- be non-zero or GetScore short-circuits before it touches anything.
    local CI = {}
    function CI:GetLastCacheTime() return 1234567, 1234567 end
    function CI:GetInventoryItemMixin() return nil end
    -- gearscore.lua asserts both libraries at file scope; LibDetours is only
    -- needed to satisfy that assert (the pin never drives a hooked path).
    local LibDetours = { Hook = function() end }
    local libs = { ["LibForeverInspector"] = CI, ["LibDetours-1.0"] = LibDetours }
    local stub = STD.setmetatable({}, {
        __call = function(_, name, silent)
            local found = libs[name]
            if (not found and not silent) then
                STD.error("unexpected library " .. STD.tostring(name), 2)
            end
            return found
        end,
    })
    function stub:NewLibrary() return {} end
    function stub:GetLibrary(name, silent) return stub(name, silent) end
    function stub:IterateLibraries() return 2 end
    env.LibStub = stub

    local loaded, loadErr = STD.pcall(sandboxChunk(GEARSCORE_PATH, env), "TacoTip_Forever")
    check("gearscore.lua loads against the throwing-issecretvalue mock", loaded, STD.tostring(loadErr))
    local GS = loaded and env.TT_GS or nil
    check("gearscore.lua published TT_GS", STD.type(GS) == "table")

    if (STD.type(GS) == "table") then
        local pred = upvalueNamed(GS.GetScore, "isSecretValue")
        guardScenarios("gearscore", env, pred)

        local getGUID = upvalueNamed(GS.GetScore, "getPlayerGUID")
        check("gearscore: the file-local getPlayerGUID was found in the loaded chunk",
            STD.type(getGUID) == "function",
            "no upvalue named getPlayerGUID -- the resolver was renamed or restructured")
        if (STD.type(getGUID) == "function") then
            env.issecretvalue = throwingFor(SENTINEL)
            env.canaccessvalue = nil
            calls.unitIsPlayer, calls.unitGUID = 0, 0
            local ok, guid = STD.pcall(getGUID, SENTINEL)
            check("gearscore: an unverifiable unit is not resolved to a GUID",
                ok and guid == nil,
                "ok=" .. STD.tostring(ok) .. " guid=" .. STD.tostring(guid))
            check("gearscore: ...so the secret value never reaches UnitIsPlayer/UnitGUID",
                calls.unitIsPlayer == 0 and calls.unitGUID == 0,
                "UnitIsPlayer=" .. STD.tostring(calls.unitIsPlayer)
                    .. " UnitGUID=" .. STD.tostring(calls.unitGUID))

            -- The public sink must degrade to "unknown", not raise and not score.
            local okScore, score, ilvl = STD.pcall(GS.GetScore, GS, SENTINEL, false)
            check("gearscore: GetScore on an unverifiable unit does not raise",
                okScore, STD.tostring(score))
            check("gearscore: ...and reports unknown (0, 0) instead of scoring it",
                okScore and score == 0 and ilvl == 0,
                "score=" .. STD.tostring(score) .. " ilvl=" .. STD.tostring(ilvl))
        end
    end
end

-- ---- LibForeverInspector.lua ---------------------------------------------

local LIB_PATH = STD.os.getenv("TACOTIP_LFI_OVERRIDE")
    or (ROOT .. "Libs/LibForeverInspector/LibForeverInspector.lua")

do
    local calls = { unitIsPlayer = 0, unitGUID = 0 }
    local env = sandbox({
        WOW_PROJECT_ID = 1,
        WOW_PROJECT_MAINLINE = 1,
        WOW_PROJECT_CLASSIC = 2,
        WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5,
        GetBuildInfo = function() return "1.15.9", "69722", "date", 16001, "us", "release" end,
        GetLocale = function() return "enUS" end,
        GetTime = function() return 0 end,
        strlower = STD.string.lower,
        print = function() end,
        CreateFrame = function()
            return { RegisterEvent = function() end, SetScript = function() end }
        end,
        issecretvalue = throwingFor(SENTINEL),
    })
    env.UnitIsPlayer = function(u)
        if (u == SENTINEL) then calls.unitIsPlayer = calls.unitIsPlayer + 1 end
        return true
    end
    env.UnitGUID = function(u)
        if (u == SENTINEL) then
            calls.unitGUID = calls.unitGUID + 1
            return SENTINEL
        end
        return "Player-1-000000AA"
    end

    -- The real LibStub and CallbackHandler, in the same sandbox: the library
    -- asserts both before it defines anything.
    local libLoaded = false
    local libErr
    libLoaded, libErr = STD.pcall(sandboxChunk(ROOT .. "Libs/LibStub/LibStub.lua", env))
    if (libLoaded) then
        libLoaded, libErr = STD.pcall(
            sandboxChunk(ROOT .. "Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua", env))
    end
    if (libLoaded) then
        libLoaded, libErr = STD.pcall(
            sandboxChunk(LIB_PATH, env), "TacoTip_Forever")
    end
    check("LibForeverInspector loads against the throwing-issecretvalue mock",
        libLoaded, STD.tostring(libErr))
    local lib = libLoaded and env.LibStub("LibForeverInspector", true) or nil
    check("LibForeverInspector published its library table", STD.type(lib) == "table")

    if (STD.type(lib) == "table") then
        local pred = upvalueNamed(lib.GetUnitData, "isSecretValue")
        guardScenarios("inspector", env, pred)

        local getGUID = upvalueNamed(lib.GetUnitData, "getPlayerGUID")
        check("inspector: the file-local getPlayerGUID was found in the loaded chunk",
            STD.type(getGUID) == "function",
            "no upvalue named getPlayerGUID -- the resolver was renamed or restructured")
        if (STD.type(getGUID) == "function") then
            env.issecretvalue = throwingFor(SENTINEL)
            env.canaccessvalue = nil
            calls.unitIsPlayer, calls.unitGUID = 0, 0
            local ok, guid = STD.pcall(getGUID, SENTINEL)
            check("inspector: an unverifiable unit is not resolved to a GUID",
                ok and guid == nil,
                "ok=" .. STD.tostring(ok) .. " guid=" .. STD.tostring(guid))
            check("inspector: ...so the secret value never reaches UnitIsPlayer/UnitGUID",
                calls.unitIsPlayer == 0 and calls.unitGUID == 0,
                "UnitIsPlayer=" .. STD.tostring(calls.unitIsPlayer)
                    .. " UnitGUID=" .. STD.tostring(calls.unitGUID))

            local okData, data = STD.pcall(lib.GetUnitData, lib, SENTINEL)
            check("inspector: GetUnitData on an unverifiable unit does not raise", okData,
                STD.tostring(data))
            check("inspector: ...and reports no data rather than the secret value",
                okData and data == nil, "data=" .. STD.tostring(data))

            local okFresh, fresh = STD.pcall(lib.IsCacheFresh, lib, SENTINEL)
            check("inspector: IsCacheFresh on an unverifiable unit does not raise", okFresh,
                STD.tostring(fresh))
            check("inspector: ...and reads as not-fresh (unknown), never as the player",
                okFresh and fresh == false, "fresh=" .. STD.tostring(fresh))
        end

        -- ---- the AllowedWhenUntainted unit queries -------------------------
        --
        -- UnitExists, UnitIsPlayer, UnitIsConnected and UnitIsDeadOrGhost each
        -- declare SecretArguments = "AllowedWhenUntainted" on origin/forever
        -- (UnitDocumentation.lua). Add-on execution is always tainted, so a secret
        -- token handed to any of them is refused outright:
        --   bad argument #1 to 'UnitExists' ... Secret values are only allowed
        --   during untainted execution for this argument.
        -- lib:CanInspect is the gate for the whole inspect queue and is reachable
        -- straight from the tooltip render path, so a secret token must be rejected
        -- before ANY of those queries runs -- not merely caught afterwards.
        --
        -- The counters make the difference observable: "returns false" alone would
        -- also pass if the library queried the secret token and swallowed the
        -- raise, which is exactly the defect this pins.
        local query = { exists = 0, isPlayer = 0, connected = 0, dead = 0 }
        env.UnitExists = function()
            query.exists = query.exists + 1
            return true
        end
        env.UnitIsConnected = function()
            query.connected = query.connected + 1
            return true
        end
        env.UnitIsDeadOrGhost = function()
            query.dead = query.dead + 1
            return false
        end
        env.UnitIsPlayer = function()
            query.isPlayer = query.isPlayer + 1
            return true
        end

        check("inspector: CanInspect closes over the safeUnitExists helper",
            STD.type(upvalueNamed(lib.CanInspect, "safeUnitExists")) == "function",
            "no upvalue named safeUnitExists -- CanInspect went back to a bare unit query")

        env.issecretvalue = throwingFor(SENTINEL)
        env.canaccessvalue = nil
        local okCI, refused = STD.pcall(lib.CanInspect, lib, SENTINEL)
        check("inspector: CanInspect on a secret token does not raise", okCI,
            STD.tostring(refused))
        check("inspector: ...refuses it", okCI and refused == false,
            "canInspect=" .. STD.tostring(refused))
        check("inspector: ...without touching any AllowedWhenUntainted unit query",
            query.exists == 0 and query.isPlayer == 0 and query.connected == 0 and query.dead == 0,
            "UnitExists=" .. STD.tostring(query.exists)
                .. " UnitIsPlayer=" .. STD.tostring(query.isPlayer)
                .. " UnitIsConnected=" .. STD.tostring(query.connected)
                .. " UnitIsDeadOrGhost=" .. STD.tostring(query.dead))

        -- And a normal token still gets through the same gate, so the guard is a
        -- token test and not a blanket "always refuse".
        env.issecretvalue = throwingFor(SENTINEL)
        query.exists, query.isPlayer, query.connected, query.dead = 0, 0, 0, 0
        local okNormal, normal = STD.pcall(lib.CanInspect, lib, "target")
        check("inspector: a readable token still reaches the unit queries", okNormal,
            STD.tostring(normal))
        check("inspector: ...and the queries actually ran for it",
            query.exists + query.isPlayer + query.connected + query.dead > 0,
            "UnitExists=" .. STD.tostring(query.exists)
                .. " UnitIsPlayer=" .. STD.tostring(query.isPlayer))
    end
end

-- ---- pawn.lua -------------------------------------------------------------
--
-- t5 gave pawn.lua the same safeUnitIsUnit guard the other consumers carry, but
-- proved it only in a throwaway script. This section makes the proof permanent.
-- pawn.lua returns at file scope unless Pawn's API is present, and GetScore's
-- self-detection is the audited path:
--
--   HEAD pawn.lua:170-171
--     local okUIU, isUnit = pcall(UnitIsUnit, unitorguid, "player")
--     if (okUIU and isUnit == true) then   -- boolean test on a possibly-secret answer
--
-- UnitIsUnit is RequiresComparableUnitTokens / SecretWhenUnitComparisonRestricted:
-- in restricted combat its boolean is itself secret, so the `== true` test is a
-- boolean test on a secret value, and the sanctioned pre-check
-- C_Secrets.CanCompareUnitTokens was never consulted. The fixed file routes the
-- comparison through safeUnitIsUnit, which asks the pre-check first and rejects a
-- secret answer; a comparison that cannot be verified reads as false and the GUID
-- equality check stays authoritative.
--
-- A secret BOOLEAN cannot be built in plain Lua (a table never equals `true`
-- without a metamethod, and the client's secret throws instead of comparing), so
-- the "secret answer" scenario uses the literal `true` AND declares `true` secret
-- through the mocked issecretvalue. That makes the difference observable: the
-- pre-fix inline test trusts the answer and calls it "self"; the guard rejects it
-- and falls through to the GUID comparison.

local PAWN_PATH = STD.os.getenv("TACOTIP_PAWN_OVERRIDE") or (ROOT .. "pawn.lua")

do
    local SELF_GUID = "Player-1-000000AA"
    local OTHER_GUID = "Player-1-000000BB"
    local calls = { unitIsUnit = 0, unitIsPlayer = 0, unitGUID = 0 }
    local cacheCalls = 0
    local playerGUID = SELF_GUID
    local unitIsUnitAnswer = false

    local env = sandbox({
        WOW_PROJECT_ID = 1,
        WOW_PROJECT_MAINLINE = 1,
        WOW_PROJECT_CLASSIC = 2,
        WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5,
        GetBuildInfo = function() return "1.15.9", "69722", "date", 16001, "us", "release" end,
        GetTime = function() return 1234567 end,
        strlower = STD.string.lower,
        print = function() end,
        CreateFrame = function()
            return { RegisterEvent = function() end, SetScript = function() end }
        end,
        issecretvalue = throwingFor(SENTINEL),
        -- pawn.lua returns early at file scope unless Pawn's API (or one of the
        -- version globals) is present; these are the three globals it probes.
        PawnGetItemData = function() return nil end,
        PawnGetSingleValueFromItem = function() return nil end,
        PawnGetScaleColor = function() return nil end,
    })
    env.C_PlayerInfo = {
        GUIDIsPlayer = function(g)
            return STD.type(g) == "string"
                and STD.string.find(g, "Player-", 1, true) == 1
        end,
    }
    env.UnitIsPlayer = function(u)
        if (u == SENTINEL) then calls.unitIsPlayer = calls.unitIsPlayer + 1 end
        return true
    end
    env.UnitGUID = function(u)
        if (u == SENTINEL) then
            calls.unitGUID = calls.unitGUID + 1
            return SENTINEL
        end
        if (u == "player") then return playerGUID end
        return SELF_GUID
    end
    env.UnitIsUnit = function()
        calls.unitIsUnit = calls.unitIsUnit + 1
        if (unitIsUnitAnswer == "throw") then
            STD.error("UnitIsUnit raised in restricted combat", 0)
        end
        return unitIsUnitAnswer
    end
    env.GetPlayerInfoByGUID = function() return "Warrior", "WARRIOR" end

    -- The inspector surface GetScore reads. GetLastCacheTime answers "nothing
    -- cached", so the non-self path returns immediately and the CALL itself is
    -- the observable that separates "self" from "someone else".
    local CI = {}
    function CI:GetLastCacheTime() cacheCalls = cacheCalls + 1; return 0, 0 end
    function CI:GetActiveTalentGroup() return 1 end
    function CI:GetSpecialization() return nil end
    function CI:GetInventoryItemMixin() return nil end
    function CI:GetSpecializationName() return "Warrior" end
    local LibDetours = { Hook = function() end }
    local libs = { ["LibForeverInspector"] = CI, ["LibDetours-1.0"] = LibDetours }
    local stub = STD.setmetatable({}, {
        __call = function(_, name, silent)
            local found = libs[name]
            if (not found and not silent) then
                STD.error("unexpected library " .. STD.tostring(name), 2)
            end
            return found
        end,
    })
    function stub:NewLibrary() return {} end
    function stub:GetLibrary(name, silent) return stub(name, silent) end
    function stub:IterateLibraries() return 2 end
    env.LibStub = stub

    local loaded, loadErr = STD.pcall(sandboxChunk(PAWN_PATH, env), "TacoTip_Forever")
    check("pawn.lua loads against the throwing-issecretvalue mock", loaded, STD.tostring(loadErr))
    local PAWN = loaded and env.TT_PAWN or nil
    check("pawn.lua published TT_PAWN", STD.type(PAWN) == "table")

    if (STD.type(PAWN) == "table") then
        local pred = upvalueNamed(PAWN.GetScore, "isSecretValue")
        guardScenarios("pawn", env, pred)

        env.issecretvalue = throwingFor(SENTINEL)
        env.canaccessvalue = nil
        env.C_Secrets = nil

        local getGUID = upvalueNamed(PAWN.GetScore, "getPlayerGUID")
        check("pawn: the file-local getPlayerGUID was found in the loaded chunk",
            STD.type(getGUID) == "function",
            "no upvalue named getPlayerGUID -- the resolver was renamed or restructured")
        if (STD.type(getGUID) == "function") then
            calls.unitIsPlayer, calls.unitGUID = 0, 0
            local ok, guid = STD.pcall(getGUID, SENTINEL)
            check("pawn: an unverifiable unit is not resolved to a GUID",
                ok and guid == nil,
                "ok=" .. STD.tostring(ok) .. " guid=" .. STD.tostring(guid))
            check("pawn: ...so the secret value never reaches UnitIsPlayer/UnitGUID",
                calls.unitIsPlayer == 0 and calls.unitGUID == 0,
                "UnitIsPlayer=" .. STD.tostring(calls.unitIsPlayer)
                    .. " UnitGUID=" .. STD.tostring(calls.unitGUID))
        end

        local okScore, score, name, colour, ready = STD.pcall(
            PAWN.GetScore, PAWN, SENTINEL, false)
        check("pawn: GetScore on an unverifiable unit does not raise", okScore,
            STD.tostring(score))
        check("pawn: ...and reports unknown (0, '', '|cffffffff', false) instead of scoring it",
            okScore and score == 0 and name == "" and colour == "|cffffffff" and ready == false,
            "score=" .. STD.tostring(score) .. " name=" .. STD.tostring(name)
                .. " colour=" .. STD.tostring(colour) .. " ready=" .. STD.tostring(ready))

        -- The guard itself, reached through GetScore's closure graph. The pre-fix
        -- file has no such local at all: it inlines the pcall and the boolean test.
        local guard = upvalueNamed(PAWN.GetScore, "safeUnitIsUnit")
        check("pawn: GetScore closes over a file-local safeUnitIsUnit guard",
            STD.type(guard) == "function",
            "no upvalue named safeUnitIsUnit -- GetScore calls UnitIsUnit inline (the pre-fix shape)")

        if (STD.type(guard) == "function") then
            env.issecretvalue = throwingFor(SENTINEL)
            env.C_Secrets = nil
            calls.unitIsUnit = 0
            local okRefuse, refused = STD.pcall(guard, SENTINEL, "player")
            check("pawn: the guard refuses a secret unit argument", okRefuse and refused == false,
                "ok=" .. STD.tostring(okRefuse) .. " answer=" .. STD.tostring(refused))
            check("pawn: ...without attempting the comparison", calls.unitIsUnit == 0,
                "UnitIsUnit=" .. STD.tostring(calls.unitIsUnit))

            calls.unitIsUnit = 0
            unitIsUnitAnswer = true
            local okPlain, plain = STD.pcall(guard, SELF_GUID, "player")
            check("pawn: a permitted comparison still reaches UnitIsUnit and answers",
                okPlain and plain == true and calls.unitIsUnit == 1,
                "ok=" .. STD.tostring(okPlain) .. " answer=" .. STD.tostring(plain)
                    .. " UnitIsUnit=" .. STD.tostring(calls.unitIsUnit))
            unitIsUnitAnswer = false
        end

        -- ---- the self-detection path, driven through the real GetScore ------
        --
        -- Each scenario sets three knobs: what UnitIsUnit answers, what the
        -- client's pre-check says (nil = the namespace is absent on this client), and who
        -- the player is. GetLastCacheTime is the observable for isSelf: the
        -- non-self path asks the inspector for a cache time, the self path does
        -- not.
        local function scenario(unitIsUnit, secrets, player)
            calls.unitIsUnit, calls.unitIsPlayer, calls.unitGUID = 0, 0, 0
            cacheCalls = 0
            unitIsUnitAnswer = unitIsUnit
            env.C_Secrets = secrets
            env.issecretvalue = throwingFor(SENTINEL)
            playerGUID = player or SELF_GUID
        end

        local function scoreSelf()
            return STD.pcall(PAWN.GetScore, PAWN, SELF_GUID, false)
        end

        -- The client's sanctioned pre-check answers "not comparable". UnitIsUnit
        -- is mocked to answer TRUE anyway -- a restricted client would answer
        -- with a secret, which the guard also rejects -- so the pin is that the
        -- addon never consults the forbidden comparison at all.
        scenario(true, { CanCompareUnitTokens = function() return false end }, OTHER_GUID)
        local okForbid = scoreSelf()
        check("pawn: a comparison the client forbids is never attempted",
            okForbid and calls.unitIsUnit == 0,
            "UnitIsUnit=" .. STD.tostring(calls.unitIsUnit))
        check("pawn: ...and its answer never decides self (the non-self cache path runs)",
            okForbid and cacheCalls == 1,
            "GetLastCacheTime=" .. STD.tostring(cacheCalls))

        -- The pre-check itself throws (tainted execution). A raise is affirmative
        -- "not permitted", exactly like issecretvalue's tainted raise.
        scenario(true, { CanCompareUnitTokens = function()
            STD.error("CanCompareUnitTokens raised on tainted tokens", 0)
        end }, OTHER_GUID)
        local okThrowPre = scoreSelf()
        check("pawn: a THROWING CanCompareUnitTokens is a refusal, not a permission",
            okThrowPre and calls.unitIsUnit == 0,
            "UnitIsUnit=" .. STD.tostring(calls.unitIsUnit))
        check("pawn: ...so the non-self cache path still runs",
            okThrowPre and cacheCalls == 1,
            "GetLastCacheTime=" .. STD.tostring(cacheCalls))

        -- A THROWING UnitIsUnit must not escape GetScore, and the GUID equality
        -- check stays authoritative: the player's own GUID still reads as self.
        scenario("throw", nil, SELF_GUID)
        local okUnitThrow, unitThrowScore = scoreSelf()
        check("pawn: a THROWING UnitIsUnit does not escape GetScore", okUnitThrow,
            STD.tostring(unitThrowScore))
        check("pawn: ...and the GUID-equality fallback still resolves self",
            okUnitThrow and cacheCalls == 0,
            "GetLastCacheTime=" .. STD.tostring(cacheCalls))

        -- A SECRET UnitIsUnit answer. `true` is declared secret through the mock
        -- because plain Lua cannot build the client's secret boolean; the point
        -- is that the guard must not trust the answer. The GUIDs differ, so if
        -- the secret decided self the cache path would be skipped -- which is
        -- exactly what the pre-fix inline `isUnit == true` does.
        scenario(true, nil, OTHER_GUID)
        env.issecretvalue = function(v)
            if (v == SENTINEL or v == true) then
                STD.error("issecretvalue on a secret value from tainted execution", 0)
            end
            return false
        end
        local okSecretAnswer = scoreSelf()
        check("pawn: a secret UnitIsUnit answer must not decide self",
            okSecretAnswer and cacheCalls == 1,
            "GetLastCacheTime=" .. STD.tostring(cacheCalls)
                .. " UnitIsUnit=" .. STD.tostring(calls.unitIsUnit))

        -- Anti-lazy-fix: the guard must not simply always refuse. A permitted
        -- comparison still resolves self without the cache round-trip.
        scenario(true, { CanCompareUnitTokens = function() return true end }, OTHER_GUID)
        local okPermit = scoreSelf()
        check("pawn: a PERMITTED comparison still resolves self (the guard is not a blanket refusal)",
            okPermit and cacheCalls == 0 and calls.unitIsUnit == 1,
            "GetLastCacheTime=" .. STD.tostring(cacheCalls)
                .. " UnitIsUnit=" .. STD.tostring(calls.unitIsUnit))

        -- The C_Secrets namespace is a capability, not a guarantee: simulate it
        -- being absent and confirm the pcall + predicate still carry the guard.
        scenario(true, nil, OTHER_GUID)
        local okClassic = scoreSelf()
        check("pawn: with no C_Secrets namespace the comparison still runs",
            okClassic and calls.unitIsUnit == 1 and cacheCalls == 0,
            "UnitIsUnit=" .. STD.tostring(calls.unitIsUnit)
                .. " GetLastCacheTime=" .. STD.tostring(cacheCalls))
    end
end

-- ---- inspector & pawn cache secrecy (1.0.2) --------------------------------

do
    local secrets = {}
    local function markSecret(val)
        secrets[val] = true
        return val
    end
    local savedLink = nil
    local env = sandbox({
        WOW_PROJECT_ID = 18,
        WOW_PROJECT_CAMELOT = 18,
        WOW_PROJECT_MAINLINE = 1,
        WOW_PROJECT_CLASSIC = 2,
        WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5,
        GetBuildInfo = function() return "16.0.1", "69722", "date", 16001, "us", "release" end,
        GetTime = function() return 500 end,
        strlower = STD.string.lower,
        print = function() end,
        CreateFrame = function()
            return {
                RegisterEvent = function() end,
                SetScript = function() end,
                HookScript = function() end,
            }
        end,
        issecretvalue = function(v)
            if (secrets[v]) then
                STD.error("secret value read from tainted code", 0)
            end
            return false
        end,
        UnitExists = function(u) return u == "target" or u == "player" end,
        UnitIsPlayer = function() return true end,
        UnitGUID = function(u)
            if (u == "player") then return "Player-1-00000001" end
            if (u == "target") then return "Player-1-00000002" end
            return nil
        end,
        GetInventoryItemLink = function() return savedLink end,
        GetComparisonAchievementPoints = function() return markSecret(9999) end,
        C_SpecializationInfo = {
            GetSpecializationInfo = function()
                return 1, "Shaman", "", markSecret(136048), "", "", 0, nil, 0
            end,
        },
        LibStub = setmetatable({}, {
            __call = function(_, name)
                if (name == "CallbackHandler-1.0") then
                    return { New = function() return { RegisterCallback = function() end, Fire = function() end } end }
                end
                return nil
            end,
            __index = {
                NewLibrary = function() return {} end,
                GetLibrary = function(_, name)
                    if (name == "CallbackHandler-1.0") then
                        return { New = function() return { RegisterCallback = function() end, Fire = function() end } end }
                    end
                    return nil
                end,
            },
        }),
    })
    local lib = { cache = {} }
    env.LibStub.NewLibrary = function(_, name)
        if (name == "LibForeverInspector") then return lib end
        return {}
    end

    local okLoad, loadErr = STD.pcall(sandboxChunk(LIB_PATH, env), "TacoTip_Forever")
    check("inspector 1.0.2 loads for cache-secrecy check", okLoad, STD.tostring(loadErr))
    if (okLoad and lib.frame and lib.frame.scripts and lib.frame.scripts.OnEvent) then
        savedLink = markSecret("|Hitem:12345::::::::70:::::|h[Secret]|h")
        local okEvt = STD.pcall(lib.frame.scripts.OnEvent, lib.frame.scripts, "INSPECT_READY", "Player-1-00000002")
        local cached = lib.cache["Player-1-00000002"]
        check("inspector 1.0.2: INSPECT_READY with secret item/achievements does not raise",
            okEvt and cached ~= nil)
        check("inspector 1.0.2: secret inventory link never enters cache.items",
            cached ~= nil and (cached.items == nil or cached.items[1] == nil))
        check("inspector 1.0.2: secret achievement points never enter cache.achievements",
            cached ~= nil and cached.achievements == nil)

        local okIcon, icon = STD.pcall(lib.GetModernSpecializationIcon, lib, 1, 1, false, markSecret("target"))
        check("inspector 1.0.2: GetModernSpecializationIcon rejects secret target cleanly",
            okIcon and icon == nil)
    end
end

-- ---- report ---------------------------------------------------------------

STD.io.write("secret guard: gearscore=" .. GEARSCORE_PATH .. "\n")
STD.io.write("secret guard: inspector=" .. LIB_PATH .. "\n")
STD.io.write("secret guard: pawn=" .. PAWN_PATH .. "\n")

local fails = 0
for _, c in STD.ipairs(checks) do
    if (not c[2]) then
        fails = fails + 1
        STD.io.write(STD.string.format("    FAIL %-62s %s\n", c[1], STD.tostring(c[3] or "")))
    end
end
STD.io.write(STD.string.format("%-13s %s\n", "secretguard",
    (fails == 0) and ("ALL " .. #checks .. " PASS") or (fails .. "/" .. #checks .. " FAILED")))
STD.os.exit(fails == 0 and 0 or 1)
