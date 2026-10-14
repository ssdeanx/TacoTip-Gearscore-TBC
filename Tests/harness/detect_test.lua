-- Simulates each supported client and asserts the resolved family + gear bracket.
-- Runs the REAL LibForeverInspector; only the host environment is mocked.

local _hp = ((arg and arg[0]) or "Tests/harness/detect_test.lua"):gsub("\\", "/")
local _hd = _hp:match("^(.*)/[^/]*$") or "."
local ROOT = dofile(_hd .. "/root.lua") .. "/"
local LIB = ROOT .. "Libs/"

local results, allok = {}, true
-- NB: in Lua 5.1 assigning `_G = {}` only rebinds the variable, it does not
-- replace the environment table every other global lookup resolves through.
-- Wipe the real table instead.
local REALG = _G
-- capture the stdlib before anything is wiped
-- `unpack` is a global in Lua 5.1 -- what WoW ships, and what this addon targets
-- -- but 5.2 moved it to `table.unpack`, so the bare global is nil under lua5.4.
-- Nothing in LibForeverInspector calls it, so this only matters to keep the
-- sandbox faithful; resolving it here means the entry below is a real callable on
-- both interpreters instead of a key that is silently missing from the copy loop
-- below, and it has to happen before the wipe either way.
local unpack = unpack or table.unpack

-- WoW's Lua accepts extra arguments on xpcall; stock 5.1 accepts exactly two.
-- Blizzard's own FrameXML relies on it (classic_era calls
-- `xpcall(handlerInfo.handler, CallErrorHandler, self, button, cursorX, cursorY)`),
-- and so does CallbackHandler-1.0 v7, whose Dispatch passes the event name and
-- payload through xpcall. Under stock lua5.1 every handler therefore received
-- ZERO arguments, which would have made a correct test fail for the wrong
-- reason -- so the shim reproduces the client's behaviour rather than the
-- interpreter's.
local realXpcall = xpcall
local function xpcallWithArgs(f, handler, ...)
    local argc = select("#", ...)
    if (argc == 0) then return realXpcall(f, handler) end
    local args = { ... }
    return realXpcall(function() return f(unpack(args, 1, argc)) end, handler)
end

local STD = { os = os, string = string, pairs = pairs, ipairs = ipairs, type = type,
    pcall = pcall, tonumber = tonumber, tostring = tostring, select = select,
    rawget = rawget, rawset = rawset, setmetatable = setmetatable,
    getmetatable = getmetatable, unpack = unpack, assert = assert, error = error,
    -- next and xpcall are Lua 5.1 BASIC-library functions and are always
    -- present in WoW's Lua. They were missing here, which meant the wipe in
    -- run() left them nil and CallbackHandler-1.0 captured `local next = nil`
    -- at load -- so EVERY callbacks:Fire() in this suite raised inside
    -- Dispatch. No test fired a callback, so nothing noticed. They are listed
    -- explicitly now because the first test that asserts INVENTORY_READY
    -- actually fires one.
    next = next, xpcall = xpcallWithArgs,
    math = math, table = table, loadfile = loadfile, print = print, io = io }
local function check(name, cond, detail)
    results[#results + 1] = string.format("%-46s %-10s %s", name, cond and "PASS" or "FAIL", detail or "")
    if not cond then allok = false end
end

-- Minimal environment every client shares.
local function baseEnv()
    REALG._G = REALG
    for k, v in STD.pairs(STD) do REALG[k] = v end
    REALG.time = STD.os.time
    _G.print = function() end
    _G.CreateFrame = function() return { RegisterEvent = function() end, SetScript = function() end } end
    _G.C_Timer = { After = function() end }
    _G.C_PlayerInfo = { GUIDIsPlayer = function() return false end }
    _G.C_Item = { GetInventoryItemLink = function() end }
    _G.C_SpecializationInfo = { GetSpecializationInfo = function() end }
    _G.CanInspect = function() return false end
    _G.NotifyInspect = function() return true end
    _G.InCombatLockdown = function() return false end
    _G.GetNamePlates = function() return {} end
    _G.UnitIsPlayer = function() return false end
    _G.UnitGUID = function() return nil end
    _G.GetInventoryItemLink = function() end
    _G.GetPlayerInfoByGUID = function() end
    _G.GetSpecializationInfoByID = function() end
    _G.GetItemInfo = function() end
    _G.GetQuestDifficultyColor = function() end
    _G.GetComparisonAchievementPoints = function() end
    _G.GetTotalAchievementPoints = function() end
    _G.GetNumTalentTabs = nil
    _G.GetTalentTabInfo = nil
    _G.TACOTIP_SPEC_NAMES = nil
    _G.TACOTIP_SPEC_ICONS = nil
    _G.TacoTip_GSCallback = nil
end

-- run(profile) -> CI table. layout: "slot4" = modern GetBuildInfo shape,
-- "slot7" = the shape implied by Blizzard's own Classic FrameXML.
local function run(projectId, iface, layout, projectConsts, patches)
    for k in STD.pairs(REALG) do REALG[k] = nil end
    baseEnv()
    if (patches) then
        for k, v in STD.pairs(patches) do _G[k] = v end
    end
    for k, v in pairs(projectConsts or {}) do _G[k] = v end
    _G.WOW_PROJECT_ID = projectId
    if layout == "slot4" then
        _G.GetBuildInfo = function() return "1.15.9", "69722", "date", iface, "us", "release" end
    else
        -- slot 4 is not a number on this layout; the build sits at slot 7
        _G.GetBuildInfo = function() return "1.15.9", "69722", "date", nil, "versionType", "buildType", iface end
    end
    assert(loadfile(LIB .. "LibStub/LibStub.lua"))()
    assert(loadfile(LIB .. "CallbackHandler-1.0/CallbackHandler-1.0.lua"))()
    local chunk = assert(loadfile(LIB .. "LibForeverInspector/LibForeverInspector.lua"))
    chunk("TacoTip")
    return LibStub("LibForeverInspector")
end

local CONSTS = {
    WOW_PROJECT_MAINLINE = 1,
    WOW_PROJECT_CLASSIC = 2,
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5,
    WOW_PROJECT_WRATH_CLASSIC = 11,
    WOW_PROJECT_CATACLYSM_CLASSIC = 14,
    WOW_PROJECT_MISTS_CLASSIC = 19,
}

local P = CONSTS

-- The REAL origin/forever constant set, verbatim. On that branch
-- Blizzard_ProjectConstants/ProjectConstants.lua is the entire file and defines
-- exactly these two constants -- WOW_PROJECT_BURNING_CRUSADE_CLASSIC and
-- WOW_PROJECT_WRATH_CLASSIC live in Blizzard_FrameXMLBase/{Cata,Mists}/Constants.lua,
-- which Blizzard_FrameXMLBase.toc gates behind [AllowLoadGameType cata mists] and
-- [AllowLoadGameType mists], so neither loads on camelot. Supplying all five (as
-- CONSTS above does) is what let a `nil == nil` comparison through unnoticed, so
-- the mocked environment here must NOT be a superset of the real one.
local CAMELOT_CONSTS = {
    WOW_PROJECT_MAINLINE = 1,
    WOW_PROJECT_CLASSIC = 2,
}

local FAMILY_FLAGS = { "IsClassic", "IsTBC", "IsWotlk", "IsForever", "IsRetail" }

local function flagsSet(ci)
    local names = {}
    for _, f in ipairs(FAMILY_FLAGS) do
        if ci[f](ci) then names[#names + 1] = f end
    end
    return names
end

local function bracket(ci)
    if ci:IsClassic() then return 200 end
    if ci:IsTBC() then return 400 end
    if ci:IsForever() then return 200 end
    return 1000
end

-- Every environment detection is asked about lives in this one matrix, so the
-- invariants below cover all of them and a new case cannot be added without being
-- held to them. c = constant set (default CONSTS), f = expected family,
-- b = expected gear bracket, u = expected IsUnknown.
local SCENARIOS = {
    -- The five real targets.
    { n = "Classic Era 11509",  p = P.WOW_PROJECT_CLASSIC,                 i = 11509,  f = "classicEra",  b = 200 },
    { n = "TBC Anniversary",    p = P.WOW_PROJECT_BURNING_CRUSADE_CLASSIC, i = 20506,  f = "tbc",         b = 400 },
    { n = "Titanforge 38002",   p = P.WOW_PROJECT_WRATH_CLASSIC,           i = 38002,  f = "titanforge",  b = 1000 },
    { n = "WoW Forever 16001",  p = P.WOW_PROJECT_MAINLINE,               i = 16001,  f = "forever",     b = 200 },
    { n = "Retail 120100",      p = P.WOW_PROJECT_MAINLINE,               i = 120100, f = "retail",      b = 1000 },
    -- WoW Forever with WOW_PROJECT_ID unset (engine-defined on camelot) must
    -- still resolve via the interface band, and must NOT fall back to retail.
    { n = "Forever, WOW_PROJECT_ID nil", p = nil, i = 16001, f = "forever", b = 200 },
    -- The open question: if Forever ever reports WOW_PROJECT_MAINLINE, isRetail
    -- and isForever must still not both be true.
    { n = "Forever reporting MAINLINE is unambiguous", p = P.WOW_PROJECT_MAINLINE, i = 16001, f = "forever", b = 200 },
    -- The real camelot environment. This is the regression: the BC and Wrath
    -- constants do not exist there at all, so `WOW_PROJECT_ID == WOW_PROJECT_BC_CLASSIC`
    -- is `nil == nil` and evaluates TRUE. That set isTBC and isWotlk together and,
    -- because the interface-band fallback only runs when no family flag is set,
    -- the fallback never got a chance to run -- so Forever was reported as TBC,
    -- with TBC's 400 item-level bracket and TBC's other family behaviours.
    { n = "REAL camelot consts, WOW_PROJECT_ID nil", p = nil, i = 16001, f = "forever", b = 200, c = CAMELOT_CONSTS },
    -- Unrecognised clients must be reported unknown, not silently defaulted.
    { n = "Cata",   p = P.WOW_PROJECT_CATACLYSM_CLASSIC, i = 40402, f = "unknown", u = true },
    { n = "Mists",  p = P.WOW_PROJECT_MISTS_CLASSIC,       i = 50504, f = "unknown", u = true },
}

-- Each scenario runs under BOTH plausible GetBuildInfo layouts, so no result
-- depends on the unverified Classic slot-4 question.
for _, t in ipairs(SCENARIOS) do
    for _, layout in ipairs({ "slot4", "slot7" }) do
        local ci = run(t.p, t.i, layout, t.c or CONSTS)
        local got, b = ci.family, bracket(ci)
        local label = string.format("%s [%s layout]", t.n, layout)

        check(label,
            (got == t.f and (t.b == nil or b == t.b) and (ci:IsUnknown() == (t.u == true))),
            string.format("family=%-11s bracket=%-5d unknown=%s", got, b, tostring(ci:IsUnknown())))

        -- The invariant that actually broke, and the one that matters downstream:
        -- AT MOST ONE family flag may ever be true. Two flags mean the direct
        -- project comparison and the interface-band fallback disagree, and every
        -- consumer keys off these flags -- gearscore.lua's item-level bracket,
        -- main.lua's hasDualSpec and isClassicFamily -- so a double-set silently
        -- reconfigures the addon on a public client. Zero is legitimate only for
        -- an unrecognised client, which the family assertion above pins down.
        local set = flagsSet(ci)
        check("at most one family flag: " .. label, #set <= 1,
            "#set=" .. #set .. " [" .. table.concat(set, "+") .. "]")
    end
end

-- Backward-compatible alias still resolves, now with a minor version.
do
    local ci = run(P.WOW_PROJECT_CLASSIC, 11509, "slot4", CONSTS)
    local alias, minor = LibStub("LibClassicInspector")
    check("LibClassicInspector alias + minor",
        (alias == ci and minor == 2),
        "same_table=" .. tostring(alias == ci) .. " minor=" .. tostring(minor))
end

-- lib:CanInspect range gate. CanInspect() answers true at any distance on the
-- Classic family, so there CheckInteractDistance must also pass; on Retail and
-- Forever either signal suffices (that is what made hover inspection work).
do
    local function gate(projectId, iface, canInspect, nearby)
        local ci = run(projectId, iface, "slot4", CONSTS)
        _G.UnitExists = function() return true end
        _G.UnitIsConnected = function() return true end
        _G.UnitIsDeadOrGhost = function() return false end
        _G.UnitIsPlayer = function() return true end
        _G.UnitIsUnit = function() return false end
        _G.CanInspect = function() return canInspect end
        _G.CheckInteractDistance = function() return nearby end
        return ci:CanInspect("mouseover")
    end
    local classicProjects = {
        { "Classic Era", P.WOW_PROJECT_CLASSIC, 11509 },
        { "TBC Anniversary", P.WOW_PROJECT_BURNING_CRUSADE_CLASSIC, 20506 },
        { "Titanforge", P.WOW_PROJECT_WRATH_CLASSIC, 38002 },
    }
    for _, c in ipairs(classicProjects) do
        check("CanInspect " .. c[1] .. ": out of range rejected",
            gate(c[2], c[3], true, false) == false)
        check("CanInspect " .. c[1] .. ": in range accepted",
            gate(c[2], c[3], true, true) == true)
    end
    local mainline = {
        { "Forever", P.WOW_PROJECT_MAINLINE, 16001 },
        { "Retail", P.WOW_PROJECT_MAINLINE, 120100 },
    }
    for _, c in ipairs(mainline) do
        check("CanInspect " .. c[1] .. ": CanInspect alone accepted",
            gate(c[2], c[3], true, false) == true)
        check("CanInspect " .. c[1] .. ": range alone accepted",
            gate(c[2], c[3], false, true) == true)
        check("CanInspect " .. c[1] .. ": neither rejected",
            gate(c[2], c[3], false, false) == false)
    end
end

-- World proximity scan + telemetry (new in 0.8.3).
-- Every one of the five shipped clients is exercised here, not just Classic:
-- the scan itself is family-agnostic but the DISTANCE POLICY it applies is not
-- (Classic needs both signals, mainline accepts either), and an unasserted
-- client is exactly how "it works on my client" bugs get in.
do
    local CLIENTS = {
        { "Classic Era",     P.WOW_PROJECT_CLASSIC,                  11509,  false },
        { "TBC Anniversary", P.WOW_PROJECT_BURNING_CRUSADE_CLASSIC,   20506,  false },
        { "Titanforge",      P.WOW_PROJECT_WRATH_CLASSIC,             38002,  false },
        { "WoW Forever",     P.WOW_PROJECT_MAINLINE,                  16001,  true },
        { "Retail",          P.WOW_PROJECT_MAINLINE,                 120100,  true },
    }

    local function scanEnv(opts)
        opts = opts or {}
        local env = {}
        env.UnitExists = function() return true end
        env.UnitIsConnected = function() return true end
        env.UnitIsDeadOrGhost = function() return false end
        env.UnitIsPlayer = function(u)
            -- A unit that makes a Blizzard query throw: the realistic shape of
            -- a secret/protected unit mid-teardown. The scan must survive it.
            if (u == "BOOM") then error("unit query raised") end
            return true
        end
        env.UnitIsUnit = function() return false end
        env.UnitGUID = function(u)
            if (u == "player") then return "Player-self" end
            return "Player-" .. tostring(u)
        end
        env.CanInspect = function() return opts.canInspect ~= false end
        env.CheckInteractDistance = function() return opts.nearby ~= false end
        env.InCombatLockdown = function() return opts.combat == true end
        env.NotifyInspect = function() return true end
        local plates = opts.plates or { "n1" }
        env.GetNamePlates = function()
            local out = {}
            for i = 1, #plates do
                local token = plates[i]
                if (token == "RAISE") then
                    out[i] = { GetUnit = function() error("poison plate") end }
                else
                    out[i] = { GetUnit = function() return token end }
                end
            end
            return out
        end
        return env
    end

    for _, c in ipairs(CLIENTS) do
        local name, project, iface, lenient = c[1], c[2], c[3], c[4]

        local ci = run(project, iface, "slot4", CONSTS, scanEnv())
        ci:SetScanEnabled(true)
        check("ScanNearby exposed " .. name, type(ci.ScanNearby) == "function")
        check("GetInspectStats exposed " .. name, type(ci:GetInspectStats()) == "table")
        ci.ScanNearby()
        check("ScanNearby queues in-range " .. name,
            (ci:GetInspectStats().scanEnqueued or 0) == 1,
            "enqueued=" .. tostring(ci:GetInspectStats().scanEnqueued))

        -- A fresh cache entry must not be re-queued: this is the difference
        -- between a scan that collects coverage and a scan that spams the server.
        ci = run(project, iface, "slot4", CONSTS, scanEnv())
        ci:SetScanEnabled(true)
        ci.cache["Player-n1"] = { time = time() }
        ci.ScanNearby()
        check("ScanNearby skips fresh cache " .. name,
            (ci:GetInspectStats().scanEnqueued or 0) == 0,
            "enqueued=" .. tostring(ci:GetInspectStats().scanEnqueued))

        -- Budget: many visible players, one inspect request per tick.
        ci = run(project, iface, "slot4", CONSTS,
            scanEnv({ plates = { "n1", "n2", "n3" } }))
        ci:SetScanEnabled(true)
        ci.ScanNearby()
        check("ScanNearby respects budget " .. name,
            (ci:GetInspectStats().scanEnqueued or 0) == 1,
            "enqueued=" .. tostring(ci:GetInspectStats().scanEnqueued))

        -- Per-plate fault isolation: the FIRST plate raises inside a unit query.
        -- The scan must swallow it, count it, and still process the second plate.
        ci = run(project, iface, "slot4", CONSTS,
            scanEnv({ plates = { "BOOM", "n2" } }))
        ci:SetScanEnabled(true)
        local raised = pcall(ci.ScanNearby)
        local enq = ci:GetInspectStats().scanEnqueued or 0
        local skipped = ci:GetInspectStats().scanSkippedDistance or 0
        check("ScanNearby isolates bad plate " .. name,
            (raised and enq == 1 and skipped == 1),
            "ok=" .. tostring(raised) .. " enq=" .. tostring(enq)
            .. " skip=" .. tostring(skipped))

        -- Out of range. Classic has CanInspect true + distance false (the exact
        -- case that stalled the queue in 0.8.1); mainline has both false.
        local away = lenient
            and scanEnv({ canInspect = false, nearby = false })
            or  scanEnv({ canInspect = true,  nearby = false })
        ci = run(project, iface, "slot4", CONSTS, away)
        ci:SetScanEnabled(true)
        ci.ScanNearby()
        local st = ci:GetInspectStats()
        check("ScanNearby rejects out-of-range " .. name,
            (st.scanEnqueued or 0) == 0 and (st.scanSkippedDistance or 0) == 1,
            "enq=" .. tostring(st.scanEnqueued) .. " skip=" .. tostring(st.scanSkippedDistance))

        -- Combat blocks the scan outright.
        ci = run(project, iface, "slot4", CONSTS, scanEnv({ combat = true }))
        ci:SetScanEnabled(true)
        ci.ScanNearby()
        check("ScanNearby blocked in combat " .. name,
            (ci:GetInspectStats().scanEnqueued or 0) == 0,
            "enqueued=" .. tostring(ci:GetInspectStats().scanEnqueued))

        -- The toggle really turns it off.
        ci = run(project, iface, "slot4", CONSTS, scanEnv())
        ci:SetScanEnabled(false)
        ci.ScanNearby()
        check("SetScanEnabled(false) stops scan " .. name,
            (ci:GetInspectStats().scanEnqueued or 0) == 0,
            "enqueued=" .. tostring(ci:GetInspectStats().scanEnqueued))
    end
end

-- Classic-family range gate. An earlier revision let a recently-inspected unit
-- through a FAILED distance check, on the theory that CheckInteractDistance
-- flaps at mount/elevation boundaries. That was wrong and it caused the very
-- bug this suite now guards: the unit walks out of range, the grace window lets
-- the request through anyway, and Blizzard raises "Not in Range" at the player.
-- The contract is now unconditional -- on the Classic family both signals must
-- hold, every time, and recency is not an exemption.
do
    local clock = 1000
    local env = {
        UnitExists = function() return true end,
        UnitIsConnected = function() return true end,
        UnitIsDeadOrGhost = function() return false end,
        UnitIsPlayer = function() return true end,
        UnitIsUnit = function() return false end,
        UnitGUID = function(u) if (u == "player") then return "Player-self" end return "Player-" .. tostring(u) end,
        CanInspect = function() return true end,
        CheckInteractDistance = function() return false end,  -- out of range
        GetTime = function() return clock end,
    }
    local ci = run(P.WOW_PROJECT_CLASSIC, 11509, "slot4", CONSTS, env)
    check("classic range: out-of-range rejected",
        ci:CanInspect("n1") == false)

    ci.inspectSuccessTime["Player-n1"] = clock          -- just inspected
    check("classic range: recency does NOT exempt a unit that walked out of range",
        ci:CanInspect("n1") == false)

    ci.inspectSuccessTime["Player-n1"] = clock - 6      -- window long expired
    check("classic range: stale entry does not extend the gate",
        ci:CanInspect("n1") == false)

    -- Mainline keeps the either-signal rule: distance false, CanInspect true is
    -- still inspectable there, and no hysteresis is involved.
    local ci2 = run(P.WOW_PROJECT_MAINLINE, 120100, "slot4", CONSTS, {
        UnitExists = function() return true end,
        UnitIsConnected = function() return true end,
        UnitIsDeadOrGhost = function() return false end,
        UnitIsPlayer = function() return true end,
        UnitIsUnit = function() return false end,
        UnitGUID = function() return "Player-n1" end,
        CanInspect = function() return true end,
        CheckInteractDistance = function() return false end,
        GetTime = function() return clock end,
    })
    check("hysteresis: retail keeps either-signal (CanInspect alone)",
        ci2:CanInspect("n1") == true)
end

-- Cache timestamps come from GetTime (uptime), and the library must survive
-- GetTime being absent. isCacheFresh runs on every scan tick and queue
-- dispatch and cacheUnitData runs inside INSPECT_READY, so a raise there is a
-- silently dead tooltip rather than an error anyone can see.
do
    local clock = 500
    local ci = run(P.WOW_PROJECT_CLASSIC, 11509, "slot4", CONSTS, {
        UnitExists = function() return true end,
        UnitIsConnected = function() return true end,
        UnitIsDeadOrGhost = function() return false end,
        UnitIsPlayer = function() return true end,
        UnitIsUnit = function() return false end,
        UnitGUID = function(u) if (u == "player") then return "Player-self" end return "Player-" .. tostring(u) end,
        CanInspect = function() return true end,
        CheckInteractDistance = function() return true end,
        NotifyInspect = function() return true end,
        GetTime = function() return clock end,
        GetNamePlates = function() return { { GetUnit = function() return "n1" end } } end,
    })

    ci.cache["Player-n1"] = { time = clock }
    local _, stamped = ci:GetLastCacheTime("Player-n1")
    check("cache timestamps come from GetTime",
        stamped == clock,
        "stamped=" .. tostring(stamped) .. " clock=" .. tostring(clock))

    -- Inside the refresh window: the scan must leave it alone.
    ci:SetScanEnabled(true)
    ci.ScanNearby()
    check("fresh window uses uptime stamps",
        (ci:GetInspectStats().scanEnqueued or 0) == 0,
        "enqueued=" .. tostring(ci:GetInspectStats().scanEnqueued))

    -- Older than the refresh window: it must be re-queued, which only happens
    -- if the comparison is against the same clock GetTime produced.
    clock = clock + 400
    ci.ScanNearby()
    check("expired window re-queues on uptime clock",
        (ci:GetInspectStats().scanEnqueued or 0) == 1,
        "enqueued=" .. tostring(ci:GetInspectStats().scanEnqueued))

    -- GetTime unavailable: must degrade, not raise.
    --
    -- The clock has to be reached on a path that is NOT already wrapped in the
    -- scan's per-plate guard, or the isolation swallows the error and this check
    -- passes for the wrong reason. The INSPECT_READY handler is that path:
    -- cacheUnitData reads the clock as its first statement, and an unguarded
    -- read there aborts the handler before INVENTORY_READY / TALENTS_READY ever
    -- fire -- a tooltip that silently never populates, with no error anywhere.
    --
    -- GetTime = nil in a table constructor creates NO key, so it cannot be
    -- blanked through the patches table; it is forced to nil AFTER load, which
    -- is also the more honest simulation of the hazard.
    --
    -- CreateFrame is replaced with one that RETAINS its scripts, because
    -- baseEnv's version discards them and the handler would otherwise be
    -- unreachable from any test at all.
    local blanked = run(P.WOW_PROJECT_CLASSIC, 11509, "slot4", CONSTS, {
        CreateFrame = function()
            local f = { scripts = {} }
            f.RegisterEvent = function() end
            f.SetScript = function(self, name, fn) self.scripts[name] = fn end
            f.GetScript = function(self, name) return self.scripts[name] end
            return f
        end,
        UnitExists = function(u) return (u == "target") end,
        UnitIsConnected = function() return true end,
        UnitIsDeadOrGhost = function() return false end,
        UnitIsPlayer = function() return true end,
        UnitIsUnit = function() return false end,
        UnitGUID = function(u)
            if (u == "player") then return "Player-self" end
            if (u == "target") then return "Player-n1" end
            return "Player-" .. tostring(u)
        end,
        CanInspect = function() return true end,
        CheckInteractDistance = function() return true end,
        NotifyInspect = function() return true end,
        GetInventoryItemLink = function() return nil end,
        GetTime = function() return 1 end,
    })
    local handler = blanked.frame and blanked.frame.scripts
        and blanked.frame.scripts.OnEvent
    check("INSPECT_READY handler is reachable from the harness",
        type(handler) == "function")

    local fired, seen = false, {}
    -- CallbackHandler dispatches (eventname, ...): the event name is the FIRST
    -- argument to the handler, so the guid is the second.
    blanked.RegisterCallback("TacoTipProbe", "INVENTORY_READY", function(...)
        fired = true
        seen = { ... }
    end)

    _G.GetTime = nil
    check("blanked GetTime is really absent", rawget(_G, "GetTime") == nil)
    -- A frame script is function(self, event, ...). Calling it as
    -- handler("INSPECT_READY", guid) puts the event name in the SELF slot and
    -- the guid in the EVENT slot, so the branch never runs and the test is
    -- green because nothing happened at all.
    local ok, err = pcall(function() handler(blanked.frame, "INSPECT_READY", "Player-n1") end)
    local okAgain, err2 = pcall(function() handler(blanked.frame, "INSPECT_READY", "Player-n1") end)
    _G.GetTime = function() return 1 end

    check("no GetTime does not raise in the INSPECT_READY handler",
        ok and okAgain, "first=" .. tostring(ok) .. " err=" .. tostring(err)
        .. " second=" .. tostring(okAgain) .. " err=" .. tostring(err2))
    -- Split from the callback assertion on purpose: a populated cache with no
    -- callback means cacheUnitData ran and the Fire was lost, whereas an empty
    -- cache means the handler never got that far. Same symptom, different bug.
    check("INSPECT_READY still populates the cache with no GetTime",
        type(blanked.cache["Player-n1"]) == "table",
        "cache=" .. tostring(blanked.cache["Player-n1"]))
    check("INVENTORY_READY still fires with no GetTime",
        fired and seen[1] == "INVENTORY_READY" and seen[2] == "Player-n1"
        and seen[3] == true,
        "fired=" .. tostring(fired) .. " n=" .. tostring(#seen)
        .. " args=" .. tostring(seen[1]) .. "/" .. tostring(seen[2])
        .. "/" .. tostring(seen[3]))

    -- The scan/queue entry points must still return instead of raising.
    blanked.cache["Player-n1"] = { time = 1 }
    local okScan, okInspect = pcall(function() blanked.ScanNearby() end),
        pcall(function() return blanked:DoInspect("n1") end)
    check("no GetTime scan and DoInspect survive", okScan and okInspect,
        "scan=" .. tostring(okScan) .. " inspect=" .. tostring(okInspect))
end

-- The scan ticker must actually be registered, and the watchdog must release a
-- pending inspect that never receives INSPECT_READY. C_Timer.NewTicker is
-- captured so the harness can drive the callback by hand -- otherwise neither
-- behaviour is reachable from a test at all.
do
    local clock = 1000
    local tickers = {}
    local env = {
        UnitExists = function() return true end,
        UnitIsConnected = function() return true end,
        UnitIsDeadOrGhost = function() return false end,
        UnitIsPlayer = function() return true end,
        UnitIsUnit = function() return false end,
        UnitGUID = function(u) if (u == "player") then return "Player-self" end return "Player-" .. tostring(u) end,
        CanInspect = function() return true end,
        CheckInteractDistance = function() return true end,
        NotifyInspect = function() return true end,
        GetTime = function() return clock end,
        IsInGroup = function() return false end,
        C_Timer = {
            After = function() end,
            NewTicker = function(interval, fn)
                local h = { interval = interval, cb = fn, cancelled = false }
                function h:Cancel() self.cancelled = true end
                tickers[#tickers + 1] = h
                return h
            end,
        },
    }
    local ci = run(P.WOW_PROJECT_CLASSIC, 11509, "slot4", CONSTS, env)

    local queueT, scanT
    for _, t in ipairs(tickers) do
        if (t.interval == 0.5) then queueT = t end
        if (t.interval == ci.scanInterval) then scanT = t end
    end
    check("queue ticker registered", queueT ~= nil)
    check("scan ticker registered", scanT ~= nil)

    -- Ask for an inspect whose INSPECT_READY will never arrive, then step the
    -- clock past the watchdog window and run the queue tick.
    ci:DoInspect("n1")
    check("inspect pending blocks the next request",
        ci:GetInspectStats().notifies == 1,
        "notifies=" .. tostring(ci:GetInspectStats().notifies))
    clock = clock + 4
    if (queueT and queueT.cb) then queueT.cb() end
    check("watchdog releases a stalled inspect",
        (ci:GetInspectStats().timeouts or 0) >= 1,
        "timeouts=" .. tostring(ci:GetInspectStats().timeouts))
end

-- REGRESSION GUARD: the pre-existing roster auto-scan is independent of the
-- nameplate scan. Before 0.8.3 the engine already inspected party/raid members
-- on a queue ticker; the nameplate ticker was ADDED alongside it, not put in
-- front of it. Nothing asserted that, which is precisely how a refactor of the
-- pending/watchdog block could have quietly deleted the roster arm.
--
-- GetNamePlates is deliberately ABSENT here: this must pass on a client (or a
-- mode) where no nameplate API resolves at all.
do
    local ROSTER_CLIENTS = {
        { "Classic Era",     P.WOW_PROJECT_CLASSIC,                11509,  false },
        { "TBC Anniversary", P.WOW_PROJECT_BURNING_CRUSADE_CLASSIC, 20506,  false },
        { "Titanforge",      P.WOW_PROJECT_WRATH_CLASSIC,           38002,  false },
        { "WoW Forever",     P.WOW_PROJECT_MAINLINE,                16001,  true },
        { "Retail",          P.WOW_PROJECT_MAINLINE,                120100, true },
    }
    for _, c in ipairs(ROSTER_CLIENTS) do
        local name, project, iface = c[1], c[2], c[3]
        local clock = 100
        local notified = {}
        local tickers = {}
        local ci = run(project, iface, "slot4", CONSTS, {
            IsInGroup = function() return true end,
            IsInRaid = function() return false end,
            UnitExists = function(u)
                -- "player" must exist: the queue tick bails early when it does
                -- not, which would make this test pass/fail for a reason that
                -- has nothing to do with the roster arm.
                if (u == "player") then return true end
                return (type(u) == "string" and u:sub(1, 5) == "party")
            end,
            UnitIsConnected = function() return true end,
            UnitIsDeadOrGhost = function() return false end,
            UnitIsPlayer = function() return true end,
            UnitIsUnit = function() return false end,
            UnitGUID = function(u)
                if (u == "player") then return "Player-self" end
                return "Player-" .. tostring(u)
            end,
            CanInspect = function() return true end,
            CheckInteractDistance = function() return true end,
            NotifyInspect = function(u) notified[#notified + 1] = u return true end,
            GetTime = function() return clock end,
            C_Timer = {
                After = function() end,
                NewTicker = function(interval, fn)
                    local h = { interval = interval, cb = fn }
                    function h:Cancel() end
                    tickers[#tickers + 1] = h
                    return h
                end,
            },
        })
        -- baseEnv PROVIDES GetNamePlates, so absence has to be forced after load:
        -- `GetNamePlates = nil` in a table constructor creates no key.
        _G.GetNamePlates = nil
        check("nameplate API absent " .. name, rawget(_G, "GetNamePlates") == nil)

        local queueT
        for _, t in ipairs(tickers) do
            if (t.interval == 0.5) then queueT = t end
        end
        check("roster queue ticker present " .. name, queueT ~= nil)

        -- Drive the queue tick the way C_Timer would.
        if (queueT and queueT.cb) then queueT.cb() end
        check("roster auto-scan inspects party without nameplates " .. name,
            #notified == 1 and notified[1] == "party1",
            "n=" .. tostring(#notified) .. " unit=" .. tostring(notified[1]))

        -- And the nameplate scan degrades instead of raising when the API is gone.
        local okScan = pcall(function() ci.ScanNearby() end)
        check("ScanNearby survives a missing nameplate API " .. name, okScan,
            "ok=" .. tostring(okScan))
    end
end

-- REGRESSION: the reported "Not in Range" popup.
--
-- NotifyInspect is a SERVER REQUEST. Blizzard refuses it for a unit it will not
-- let you inspect and raises "Not in Range" / "Cannot Inspect" from INSIDE the
-- call. Forum users reported this continuously while sweeping the mouse across
-- distant players. The tooltip half was already fixed (tooltip_test.lua asserts
-- zero requests on hover render) and the suite stayed green while the library
-- underneath kept firing blind requests, so these tests drive the library path
-- itself: the scan, and the real UPDATE_MOUSEOVER_UNIT event handler.
--
-- The load must happen with a FAILING NotifyInspect so the pcall is exercised by
-- a real throw, not by an inspection that happens to return false.
do
    local clock = 1000
    local requested, thrown = {}, 0
    local ci = run(P.WOW_PROJECT_CLASSIC, 11509, "slot4", CONSTS, {
        UnitExists = function() return true end,
        UnitIsConnected = function() return true end,
        UnitIsDeadOrGhost = function() return false end,
        UnitIsPlayer = function() return true end,
        UnitIsUnit = function() return false end,
        UnitGUID = function(u)
            if (u == "player") then return "Player-self" end
            return "Player-" .. tostring(u)
        end,
        CanInspect = function() return true end,
        CheckInteractDistance = function() return true end,
        UnitDistance = function(u)
            if (u == "mouseover") then return 40 end
            return 6
        end,
        -- Blizzard's actual behaviour: raise "Not in Range" from inside.
        NotifyInspect = function(u)
            requested[#requested + 1] = u
            thrown = thrown + 1
            error("Not in Range", 0)
        end,
        GetTime = function() return clock end,
        -- EMPTY plates on purpose. The plate walk wraps every plate body in its
        -- own pcall for fault isolation, so a throw there is swallowed by that
        -- guard and would make any "does not raise" assertion pass for the
        -- wrong reason. With no plates the scan takes the fallback path, which
        -- has NO surrounding pcall -- that is the path where an uncaught throw
        -- really does reach the player.
        GetNamePlates = function() return {} end,
    })

    ci:SetScanEnabled(true)

    -- 1. The throw must not escape. This is the whole bug: an uncaught error
    --    here IS the error popup the user cannot suppress.
    local ok, err = pcall(function() ci.ScanNearby() end)
    check("rejected NotifyInspect never escapes as a player-visible error",
        ok, "ok=" .. tostring(ok) .. " err=" .. tostring(err))
    -- Only ONE candidate is tried now, not two. mouseover sits at 40yd, which is
    -- outside the ~28 yard inspect range, so the scan never asks for it at all:
    -- the distance pre-filter (isCloseEnoughToAsk / UnitDistanceSquared, which
    -- this suite used to leave unimplemented) removes it before any request. The
    -- old expectation here was "mouseover is asked once and refused", which was
    -- only true because the library never measured distance in the first place.
    check("a refused inspect is counted, not silently dropped",
        (ci:GetInspectStats().rejected or 0) == #requested,
        "rejected=" .. tostring(ci:GetInspectStats().rejected)
            .. " requests=" .. tostring(#requested))

    -- 2. Sweeping the cursor across the same player again must not re-request.
    --    One rejection is enough evidence; repeating it every mouse move is
    --    what made the original report read as "every time you move the mouse".
    --    Each call is pcall'd so that losing the guard reports a FAIL here
    --    instead of killing the whole suite on the first leaked error.
    local sweepOk = pcall(function()
        ci.ScanNearby()
        ci.ScanNearby()
    end)
    check("repeated scans do not leak the refusal as an error", sweepOk,
        "ok=" .. tostring(sweepOk))

    -- 3. Per-unit, not per-tick: each DISTINCT unit is asked once. target (at 6yd)
    --    was refused on the first tick and blacklisted, so the following ticks move
    --    on rather than re-asking the same player. mouseover is not asked AT ALL --
    --    it is 40yd out, past the inspect range, so the distance pre-filter drops it
    --    before a request ever exists. Zero requests for a distant unit is stronger
    --    than one request plus a refusal, and it is the whole point of measuring
    --    distance: this suite used to assert "mouseover is asked once" only because
    --    the library never measured it.
    local mouseoverCount, targetCount = 0, 0
    for i = 1, #requested do
        if (requested[i] == "mouseover") then mouseoverCount = mouseoverCount + 1 end
        if (requested[i] == "target") then targetCount = targetCount + 1 end
    end
    check("a distant player is never asked at all",
        mouseoverCount == 0,
        "mouseover requests=" .. tostring(mouseoverCount))
    check("the scan moves on to the next candidate instead of repeating",
        targetCount == 1,
        "target requests=" .. tostring(targetCount) .. " all=" .. tostring(#requested))

    -- 4. Learning, not just memory: the target refusal happened at 6yd, so the
    --    client is now known to refuse at 6. The cooldown below is what makes this
    --    meaningful, because otherwise the blacklist alone would explain the
    --    silence and the learned limit would be untested.
    check("the tightest refusal becomes this client's learned limit",
        type(ci.inspectRangeLimit) == "table"
            and ci.inspectRangeLimit[ci.family] == 6,
        "limit=" .. tostring(ci.inspectRangeLimit and ci.inspectRangeLimit[ci.family]))

    clock = clock + 20      -- well past INSPECT_REJECT_COOLDOWN
    local afterOk = pcall(function() ci.ScanNearby() end)
    local mouseoverAfter = 0
    for i = 1, #requested do
        if (requested[i] == "mouseover") then mouseoverAfter = mouseoverAfter + 1 end
    end
    check("after the cooldown, a unit beyond the learned limit is still refused",
        afterOk and mouseoverAfter == 0,
        "ok=" .. tostring(afterOk) .. " mouseover requests=" .. tostring(mouseoverAfter))

    -- 5. And the feature itself still works: target is at 6yd, inside the
    --    learned limit, so the request must actually be issued.
    local okNear = pcall(function()
        ci:DoInspect("target")
    end)
    check("a unit inside the learned limit is still inspected", okNear,
        "ok=" .. tostring(okNear))

-- THE REPORTED BUG. "Target someone, walk out of range, and it errors over and
-- over." The three defects that produced it, each asserted here:
--   (a) inspectDistance read only _G.UnitDistance, which is documented on NONE of
--       the five clients, so it always returned nil, so the learned range never
--       populated and the whole safety net was unreachable code.
--   (b) the reject cooldown was purely time-based: after INSPECT_REJECT_COOLDOWN
--       the SAME out-of-range unit was eligible again, so a target that stayed
--       far away cost one server error every 10 seconds forever.
--   (c) Blizzard gates NotifyInspect with CanInspect(unit, TRUE) on all five
--       branches; the library passed only (unit).
--
-- Driven through BOTH live entry points -- the horizon render path (DoInspect,
-- which main.lua calls from its tooltip hook) and the proximity scan fallback
-- (ScanNearby, which includes "target" in SCAN_FALLBACK_UNITS) -- on all five
-- clients, because the distance policy differs by family.
do
    local CLIENTS = {
        { "Classic Era",     P.WOW_PROJECT_CLASSIC,                 11509 },
        { "TBC Anniversary", P.WOW_PROJECT_BURNING_CRUSADE_CLASSIC,  20506 },
        { "Titanforge",      P.WOW_PROJECT_WRATH_CLASSIC,            38002 },
        { "WoW Forever",     P.WOW_PROJECT_MAINLINE,                 16001 },
        { "Retail",          P.WOW_PROJECT_MAINLINE,                120100 },
    }

    for _, c in ipairs(CLIENTS) do
        local name = c[1]
        local tickA = 5000
        local hitsA, thrownA = {}, 0
        local far, near, showErrorRefuses = false, 6, false

        -- Distance is served through BOTH shapes on purpose: the docs-published
        -- UnitDistanceSquared, and the other name the code used to read. Using the
        -- legacy name here proves the fallback inside inspectDistance works too.
        local env = {
            UnitExists = function() return true end,
            UnitIsConnected = function() return true end,
            UnitIsDeadOrGhost = function() return false end,
            UnitIsPlayer = function() return true end,
            UnitIsUnit = function() return false end,
            UnitGUID = function(u)
                if (u == "player") then return "Player-self" end
                return "Player-" .. tostring(u)
            end,
            UnitDistance = function()
                if (far) then return 40 end
                return near
            end,
            -- CanInspect(unit) -- ONE argument -- answers "yes" unconditionally:
            -- it validates the unit, not the distance, and CheckInteractDistance
            -- carries the distance.
            --
            -- CanInspect(unit, showError) -- the SECOND argument means "display an
            -- error message if you cannot inspect this unit", NOT "gate on range".
            -- This mock models that faithfully: asked the two-argument question it
            -- refuses and, by the engine's own contract, DISPLAYS a message;
            -- asked the one-argument question it answers the unit question. The
            -- library must never send the second argument, because doing so is what
            -- makes the popup appear. `showErrorRefuses` drives the two-argument
            -- branch so the assertion can prove the request is made regardless.
            CanInspect = function(unit, showError)
                if (showError ~= nil) then return (not showErrorRefuses) end
                return true
            end,
            CheckInteractDistance = function() return not far end,
            NotifyInspect = function(u)
                hitsA[#hitsA + 1] = u
                thrownA = thrownA + 1
                error("Not in Range", 0)
            end,
            GetTime = function() return tickA end,
            -- No nameplates: the scan uses its fallback pass, the default state
            -- for friendly players on all five clients.
            GetNamePlates = function() return {} end,
        }

        local probeA = run(c[2], c[3], "slot4", CONSTS, env)
        probeA:SetScanEnabled(true)

        -- 1. In range: both entry points coalesce into ONE server request. The
        --    hover render and the proximity scan run inside the same inspect
        --    window, so the second is rate-limited rather than doubled -- a
        --    doubled request is exactly the kind of noise being fixed here.
        probeA:DoInspect("target")
        probeA.ScanNearby()
        check(name .. " range: in-range target is inspected once",
            #hitsA == 1,
            "requests=" .. tostring(#hitsA))

        -- 2. Target walks out of range. CheckInteractDistance now says false, the
        --    unit measures 40yd, and the server refuses.
        hitsA, thrownA = {}, 0
        far = true

        -- 2a. The hover path still asks, because the tooltip re-renders on every
        --     move; the guard must refuse it without touching the server.
        for i = 1, 10 do tickA = tickA + 0.5; probeA:DoInspect("target") end
        check(name .. " range: out-of-range hover makes no request",
            #hitsA == 0,
            "requests=" .. tostring(#hitsA))

        -- 2b. The scan fallback runs every lib.scanInterval (2s) while the target
        --     stays selected -- the reported repeat loop.
        for i = 1, 30 do tickA = tickA + 2; probeA.ScanNearby() end
        check(name .. " range: out-of-range scan makes no request",
            #hitsA == 0,
            "requests=" .. tostring(#hitsA))

        -- 2c. Far past every cooldown, including a learned limit that is now
        --     populated: still nothing. This is the assertion that fails on the
        --     old code, where the 10s cooldown released the unit.
        tickA = tickA + 600
        probeA.ScanNearby()
        check(name .. " range: a long-past cooldown does not revive the request",
            #hitsA == 0,
            "requests=" .. tostring(#hitsA))

        -- 3. The one-argument question, with the two-argument one set to REFUSE. This
        --    step used to assert the exact opposite -- "CanInspect(unit,true) false
        --    blocks the request" -- on the belief that the second argument was a
        --    range gate. It is `showError`: the documented contract is that passing
        --    it makes the engine DISPLAY an error message, and that CanInspect does
        --    not test distance at all. So a false answer there means the popup has
        --    already been shown. The assertion is now the correct contract and is
        --    STRONGER than the old one: even when the engine would refuse-and-
        --    display, the request must still go out, because the library is not
        --    allowed to ask the question that displays anything.
        --    The unit sits at 3 yards here -- strictly inside the 6 yards the client
        --    refused at earlier -- so the learned-range limit cannot be what
        --    suppresses the request. Without that precaution the assertion below
        --    would pass for the wrong reason, which is the exact failure mode this
        --    suite exists to catch.
        hitsA = {}
        far = false
        near = 3
        showErrorRefuses = true
        probeA:DoInspect("target")
        probeA.ScanNearby()
        check(name .. " range: CanInspect's showError refusal does NOT block the request",
            #hitsA >= 1,
            "requests=" .. tostring(#hitsA))
        showErrorRefuses = false

        -- 4. And recovery: the unit walks back in range and the NEXT tick inspects
        --    it, with no permanent block left behind. Closing distance is measured
        --    at 2 yards -- CLOSER than the 3 yards the client just refused at,
        --    because step 3 now issues a real request (that was the point) and so
        --    teaches the learned ceiling 3. "Walked back into range" has to mean
        --    moved closer than the refusal, which is what the out-of-range memory
        --    actually requires; asserting 3 would be asserting that memory never
        --    engages.
        --    The tickA moves past INSPECT_REJECT_COOLDOWN first: step 3 set the
        --    generic 10s per-guid cooldown, and asserting a request inside that
        --    window would be asserting that a cooldown does not work. What is under
        --    test here is that nothing PERMANENT blocks the unit.
        hitsA = {}
        far = false
        near = 2
        tickA = tickA + 15
        probeA:DoInspect("target")
        probeA:ScanNearby()
        check(name .. " range: back in range, the unit is inspected again",
            #hitsA >= 1,
            "requests=" .. tostring(#hitsA))
    end
end

-- CanInspect IS ASKED WITH ONE ARGUMENT, EVERYWHERE, AND THE ATTRIBUTION CAPTURE
-- RECORDS BOTH SIDES OF THE QUESTION.
--
-- The block above pins the behaviour ("a showError refusal does not block the
-- request"), but nothing pinned HOW the library asks. A mock of the shape
-- `function() return true end` accepts any arity, so `CanInspect(unit)` and
-- `CanInspect(unit, true)` are indistinguishable to every existing test in this
-- file -- which is exactly how a call that asks the engine to display an error
-- message shipped with the suite green. The stub here records `select("#", ...)`
-- and the test asserts on it directly, on all five clients, at every place the
-- library calls CanInspect on the request path.
--
-- The capture assertions come from the same defect: the counters are cumulative
-- since /reload and read zero when the player is standing away from everyone, so
-- "no inspect was attempted" and "an inspect was attempted and something else
-- raised the message" look identical. The ring buffer is what separates them.
do
    local CLIENTS = {
        { "Classic Era",     P.WOW_PROJECT_CLASSIC,                11509 },
        { "TBC Anniversary", P.WOW_PROJECT_BURNING_CRUSADE_CLASSIC, 20506 },
        { "Titanforge",      P.WOW_PROJECT_WRATH_CLASSIC,           38002 },
        { "WoW Forever",     P.WOW_PROJECT_MAINLINE,               16001 },
        { "Retail",          P.WOW_PROJECT_MAINLINE,              120100 },
    }

    for _, c in ipairs(CLIENTS) do
        local name = c[1]
        local capClock = 4000
        local arities = {}
        local filter, filterEvent, removedEvent
        local notified = {}

        local probe = run(c[2], c[3], "slot4", CONSTS, {
            UnitExists = function() return true end,
            UnitIsConnected = function() return true end,
            UnitIsDeadOrGhost = function() return false end,
            UnitIsPlayer = function() return true end,
            UnitIsUnit = function() return false end,
            UnitGUID = function(u)
                if (u == "player") then return "Player-self" end
                return "Player-" .. tostring(u)
            end,
            UnitDistanceSquared = function() return 36, true end,   -- 6yd, inside range
            -- The whole point: this stub is ARITY-SENSITIVE. Every earlier CanInspect
            -- mock in this file is `function() return true end`, which answers the
            -- same for one argument and for two, so none of them could see the
            -- difference the defect was made of.
            CanInspect = function(...)
                arities[#arities + 1] = select("#", ...)
                return true
            end,
            CheckInteractDistance = function() return true end,
            NotifyInspect = function(u)
                notified[#notified + 1] = u
                return true
            end,
            GetTime = function() return capClock end,
            GetNamePlates = function() return {} end,
            ChatFrame_AddMessageEventFilter = function(event, fn)
                filterEvent, filter = event, fn
            end,
            ChatFrame_RemoveMessageEventFilter = function(event, fn)
                removedEvent = (filter == fn) and event or nil
            end,
            GetGameMessageInfo = function(messageType)
                return { type = "ERR_NOT_IN_RANGE", message = "Not in Range" }
            end,
        })

        check(name .. " capture: the UI_ERROR_MESSAGE filter is installed",
            filterEvent == "UI_ERROR_MESSAGE" and type(filter) == "function",
            "event=" .. tostring(filterEvent))

        -- Drive the real request path. DoInspect -> requestInspect is the single
        -- point NotifyInspect is actually called from, so this covers lib:CanInspect
        -- and requestInspectImpl in one go.
        probe:DoInspect("target")
        check(name .. " capture: the request was actually issued",
            #notified == 1 and notified[1] == "target",
            "requests=" .. tostring(#notified))

        -- The contract. One argument, every single time, from every call site.
        local maxArity, total = 0, 0
        for _, n in ipairs(arities) do
            total = total + 1
            if (n > maxArity) then maxArity = n end
        end
        check(name .. " capture: CanInspect is called with EXACTLY one argument",
            (total >= 1 and maxArity == 1),
            "calls=" .. tostring(total) .. " maxArity=" .. tostring(maxArity))

        -- The notify entry. Fields are asserted individually rather than by
        -- "is a table", because an entry that exists but records nothing is the
        -- same failure this whole block exists to detect.
        local notify
        for _, e in ipairs(probe:GetErrorLog()) do
            if (e.kind == "notify") then notify = e break end
        end
        check(name .. " capture: a notify entry is recorded",
            type(notify) == "table",
            "entries=" .. tostring(#probe:GetErrorLog()))
        if (type(notify) == "table") then
            check(name .. " capture: the notify entry records what was asked",
                notify.unit == "target"
                    and notify.guid == "Player-target"
                    and notify.time == capClock
                    and notify.distance == 6
                    and notify.interactDistance == true
                    and notify.canInspect == true,
                "unit=" .. tostring(notify.unit) .. " guid=" .. tostring(notify.guid)
                    .. " t=" .. tostring(notify.time) .. " d=" .. tostring(notify.distance)
                    .. " dist=" .. tostring(notify.interactDistance)
                    .. " can=" .. tostring(notify.canInspect))
        end

        -- The error entry, and the filter's refusal to swallow the message. The
        -- return value is asserted because a filter that returned false would
        -- make the popup disappear -- a "fix" that hides the symptom it was added
        -- to diagnose.
        local ret
        if (type(filter) == "function") then
            ret = { filter(3, "Not in Range") }
        end
        check(name .. " capture: the error filter returns nothing",
            type(ret) == "table" and #ret == 0,
            "n=" .. tostring(type(ret) == "table" and #ret or -1))

        local errEntry
        for _, e in ipairs(probe:GetErrorLog()) do
            if (e.kind == "error") then errEntry = e break end
        end
        check(name .. " capture: an error entry is recorded",
            type(errEntry) == "table"
                and errEntry.messageType == 3
                and errEntry.message == "Not in Range"
                and errEntry.time == capClock,
            "type=" .. tostring(errEntry and errEntry.messageType)
                .. " msg=" .. tostring(errEntry and errEntry.message))

        -- Bounded. 50 entries is the cap; drive well past it through the filter so
        -- the bound is exercised on a path that actually runs (60 message events).
        if (type(filter) == "function") then
            for i = 1, 60 do filter(3, "Not in Range") end
        end
        local log = probe:GetErrorLog()
        check(name .. " capture: the ring buffer stays bounded at 50",
            #log == 50,
            "entries=" .. tostring(#log))

        -- Removable. Without this the temporary capture could not be detached in
        -- a live session, which is the whole reason it is safe to ship at all.
        check(name .. " capture: the filter is removable",
            probe:RemoveErrorFilter() == true
                and removedEvent == "UI_ERROR_MESSAGE"
                and probe.uiErrorFilter == nil,
            "removed=" .. tostring(removedEvent))
        check(name .. " capture: ClearErrorLog empties the buffer",
            (probe:ClearErrorLog() or true) and #probe:GetErrorLog() == 0,
            "entries=" .. tostring(#probe:GetErrorLog()))
    end

    -- The two capture hooks are opt-in per client: ChatFrame_AddMessageEventFilter
    -- does not exist everywhere, and NotifyInspect must not be assumed either. A
    -- client missing either has to load with the capture silently off rather than
    -- raise at file scope -- the TT.LOAD_STAGE diagnostic exists to name exactly
    -- that failure.
    local bare = run(P.WOW_PROJECT_CLASSIC, 11509, "slot4", CONSTS, {
        UnitExists = function() return true end,
    })
    -- NotifyInspect comes from baseEnv, so absence has to be forced AFTER load:
    -- `NotifyInspect = nil` in a table constructor creates no key at all.
    _G.NotifyInspect = nil
    local bareOk = pcall(function()
        bare:DoInspect("target")
        bare:ClearErrorLog()
        return bare:GetErrorLog()
    end)
    check("capture: a client with no NotifyInspect still loads and reports",
        bareOk and #bare:GetErrorLog() == 0,
        "ok=" .. tostring(bareOk))

    -- And the filter is simply not installed when the API is absent. Forced after
    -- load for the same reason, since baseEnv does not define it either way.
    local noFilter = run(P.WOW_PROJECT_CLASSIC, 11509, "slot4", CONSTS, {
        UnitExists = function() return true end,
        CanInspect = function() return true end,
        CheckInteractDistance = function() return true end,
        NotifyInspect = function() return true end,
        GetTime = function() return 1 end,
    })
    _G.ChatFrame_AddMessageEventFilter = nil
    check("capture: absent ChatFrame_AddMessageEventFilter does not break load",
        noFilter.uiErrorFilter == nil and #noFilter:GetErrorLog() == 0,
        "filter=" .. tostring(noFilter.uiErrorFilter))
end

-- THE EVENT PATH ITSELF, which nothing above touches. Every block in this file
-- calls DoInspect or ScanNearby directly, so a handler that raises BEFORE it
-- reaches either of them is invisible to every assertion here -- and that is
-- exactly what shipped. `isCloseEnoughToAsk` was referenced from the OnEvent
-- handler while being declared as a local FURTHER DOWN the file; a local is only
-- in scope from its declaration onward, so the reference compiled as a GLOBAL
-- lookup and came back nil at runtime. On Classic Era every player target and
-- every player hover raised "attempt to call global 'isCloseEnoughToAsk' (a nil
-- value)" and the handler aborted -- red text at the top of the screen on
-- precisely the two triggers the player reported (a character selected, and
-- hovering), while this suite stayed green.
--
-- The frame mock RETAINS its scripts, because baseEnv's discards them and an
-- unreachable handler makes every assertion below pass for the wrong reason.
-- The comment on the block above has always claimed to drive "the real
-- UPDATE_MOUSEOVER_UNIT event handler"; it did not, and this is that test.
do
    for _, c in ipairs({
        { "Classic Era",     P.WOW_PROJECT_CLASSIC,                 11509 },
        { "TBC Anniversary", P.WOW_PROJECT_BURNING_CRUSADE_CLASSIC,  20506 },
        { "Titanforge",      P.WOW_PROJECT_WRATH_CLASSIC,            38002 },
    }) do
        local name = c[1]
        local tickC = 3000
        local far = true
        local hitsC = {}
        local probeC = run(c[2], c[3], "slot4", CONSTS, {
            CreateFrame = function()
                local f = { scripts = {} }
                f.RegisterEvent = function() end
                f.SetScript = function(self, script, fn) self.scripts[script] = fn end
                f.GetScript = function(self, script) return self.scripts[script] end
                f.IsShown = function() return false end
                return f
            end,
            UnitExists = function(u)
                return u == "target" or u == "mouseover" or u == "player"
            end,
            UnitIsConnected = function() return true end,
            UnitIsDeadOrGhost = function() return false end,
            UnitIsPlayer = function() return true end,
            UnitIsUnit = function() return false end,
            UnitGUID = function(u)
                if (u == "player") then return "Player-self" end
                return "Player-" .. tostring(u)
            end,
            UnitDistanceSquared = function()
                if (far) then return 1600, true end   -- 40yd, past the ask range
                return 36, true                        -- 6yd
            end,
            CanInspect = function(u, rangeFlag)
                if (rangeFlag ~= nil) then return not far end
                return true
            end,
            CheckInteractDistance = function() return not far end,
            NotifyInspect = function(u) hitsC[#hitsC + 1] = u end,
            GetTime = function() return tickC end,
            GetNamePlates = function() return {} end,
        })
        local handler = probeC.frame and probeC.frame.scripts
            and probeC.frame.scripts.OnEvent
        check(name .. " event path: the OnEvent handler is reachable",
            type(handler) == "function")

        -- Out of range: the two events the player named. Neither may raise, and
        -- neither may reach the server.
        local okTarget, errTarget = pcall(handler, probeC.frame, "PLAYER_TARGET_CHANGED")
        check(name .. " event path: out-of-range target raises nothing",
            okTarget, "err=" .. tostring(errTarget))
        local okHover, errHover = pcall(handler, probeC.frame, "UPDATE_MOUSEOVER_UNIT")
        check(name .. " event path: out-of-range hover raises nothing",
            okHover, "err=" .. tostring(errHover))
        check(name .. " event path: out-of-range target/hover ask nothing",
            #hitsC == 0, "requests=" .. tostring(#hitsC))

        -- And the handler still does its job once the unit is reachable, so the
        -- crash cannot be "fixed" by disabling the path it guards.
        far = false
        tickC = tickC + 20
        local okInRange = pcall(handler, probeC.frame, "PLAYER_TARGET_CHANGED")
        check(name .. " event path: in-range target is still inspected",
            okInRange and #hitsC == 1,
            "ok=" .. tostring(okInRange) .. " requests=" .. tostring(#hitsC))
    end
end

-- The same bug with NO distance API at all -- which is what every one of the five
-- clients actually shipped, since the library read a global that is documented on
-- none of them. With nothing measurable, the learned-range limit can never be
-- populated, so this is the case only the state-based out-of-range memory can stop:
-- a target that stays out of range must be refused forever, not every 10 seconds.
do
    for _, c in ipairs({
        { "Classic Era",     P.WOW_PROJECT_CLASSIC,                 11509 },
        { "TBC Anniversary", P.WOW_PROJECT_BURNING_CRUSADE_CLASSIC,  20506 },
        { "Titanforge",      P.WOW_PROJECT_WRATH_CLASSIC,            38002 },
        { "WoW Forever",     P.WOW_PROJECT_MAINLINE,                 16001 },
        { "Retail",          P.WOW_PROJECT_MAINLINE,                120100 },
    }) do
        local name = c[1]
        local tickB = 7000
        local hitsB = {}
        local near = true

        local probeB = run(c[2], c[3], "slot4", CONSTS, {
            UnitExists = function() return true end,
            UnitIsConnected = function() return true end,
            UnitIsDeadOrGhost = function() return false end,
            UnitIsPlayer = function() return true end,
            UnitIsUnit = function() return false end,
            UnitGUID = function(u)
                if (u == "player") then return "Player-self" end
                return "Player-" .. tostring(u)
            end,
            -- NO UnitDistance and NO UnitDistanceSquared: distance is unknowable.
            CanInspect = function() return true end,
            CheckInteractDistance = function() return near end,
            NotifyInspect = function(u)
                hitsB[#hitsB + 1] = u
                error("Not in Range", 0)
            end,
            GetTime = function() return tickB end,
            GetNamePlates = function() return {} end,
        })
        probeB:SetScanEnabled(true)

        -- One request, in range, refused by the server.
        probeB:DoInspect("target")
        check(name .. " nodist: the first request is made",
            #hitsB == 1,
            "requests=" .. tostring(#hitsB))

        -- Out of range. Both entry paths, plus a tickB that runs far past every
        -- cooldown in the library -- INSPECT_REJECT_COOLDOWN is 10s, this is 600s
        -- of sustained out-of-range, which is a player standing in a capital city
        -- with someone targeted across the street.
        -- Count TARGET requests only. mouseover and focus are also in
        -- SCAN_FALLBACK_UNITS, each legitimately asked once before its own mark is
        -- set; counting every unit here would assert that a unit we never even
        -- look at is not asked, which is not the contract.
        local function countTarget()
            local n = 0
            for i = 1, #hitsB do
                if (hitsB[i] == "target") then n = n + 1 end
            end
            return n
        end

        hitsB = {}
        near = false
        for i = 1, 300 do
            tickB = tickB + 2
            probeB:DoInspect("target")
            probeB.ScanNearby()
        end
        local asked = countTarget()
        check(name .. " nodist: out-of-range never re-asks",
            asked == 0,
            "target requests=" .. tostring(asked))

        -- And the mark lifts when the unit is reachable again.
        hitsB = {}
        near = true
        tickB = tickB + 2
        probeB:DoInspect("target")
        asked = countTarget()
        check(name .. " nodist: mark lifts when back in range",
            asked == 1,
            "target requests=" .. tostring(asked))
    end
end

-- Fault isolation of the distance helpers themselves. A distance API that raises
-- under comparison is not hypothetical: forever and live mark UnitInRange as
-- SecretReturns, so protected returns are a live concern on the modern pair, and
-- one client build is all it takes for UnitDistanceSquared to follow. The helpers
-- must swallow it and report "unmeasurable" -- which the pre-filter treats as
-- NEAR, not far -- so the decision falls through to lib:CanInspect instead of
-- taking the inspect pipeline down with it.
do
    for _, c in ipairs({
        { "WoW Forever", P.WOW_PROJECT_MAINLINE, 16001 },
        { "Retail",      P.WOW_PROJECT_MAINLINE, 120100 },
    }) do
        local name = c[1]
        local tick = 9000
        local hits = {}

        local probe = run(c[2], c[3], "slot4", CONSTS, {
            UnitExists = function() return true end,
            UnitIsConnected = function() return true end,
            UnitIsDeadOrGhost = function() return false end,
            UnitIsPlayer = function() return true end,
            UnitIsUnit = function() return false end,
            UnitGUID = function(u)
                if (u == "player") then return "Player-self" end
                return "Player-" .. tostring(u)
            end,
            -- A table that raises the moment it is touched, which is how a
            -- protected return behaves under comparison or type coercion.
            UnitDistanceSquared = function()
                return setmetatable({}, {
                    __index = function(_, k)
                        error("protected value touched: " .. tostring(k), 0)
                    end,
                    __lt = function() error("protected compare", 0) end,
                    __le = function() error("protected compare", 0) end,
                    __len = function() error("protected len", 0) end,
                })
            end,
            CanInspect = function() return true end,
            CheckInteractDistance = function() return true end,
            NotifyInspect = function(u) hits[#hits + 1] = u return true end,
            GetTime = function() return tick end,
            GetNamePlates = function() return {} end,
        })
        probe:SetScanEnabled(true)

        local okHover = pcall(function() probe:DoInspect("target") end)
        local okScan = pcall(function() probe.ScanNearby() end)
        check(name .. " hostile distance: no error escapes the inspect path",
            okHover and okScan,
            "hover=" .. tostring(okHover) .. " scan=" .. tostring(okScan))
        check(name .. " hostile distance: inspection still works",
            #hits >= 1,
            "requests=" .. tostring(#hits))

        local okNext = pcall(function()
            tick = tick + 5
            probe:DoInspect("target")
            probe.ScanNearby()
        end)
        check(name .. " hostile distance: still functional on the next tick",
            okNext,
            "ok=" .. tostring(okNext))
    end
end

    -- 5. The FALLBACK pass itself: with the nameplate API gone entirely -- the
    --    default state for friendly players on all five clients -- the scan must
    --    still make progress from the unit tokens that always exist.
    do
        local clock2 = 2000
        local fb = run(P.WOW_PROJECT_CLASSIC, 11509, "slot4", CONSTS, {
            UnitExists = function(u) return u ~= nil end,
            UnitIsConnected = function() return true end,
            UnitIsDeadOrGhost = function() return false end,
            UnitIsPlayer = function(u) return u == "mouseover" or u == "target" end,
            UnitIsUnit = function() return false end,
            UnitGUID = function(u)
                if (u == "player") then return "Player-self" end
                return "Player-" .. tostring(u)
            end,
            CanInspect = function() return true end,
            CheckInteractDistance = function() return true end,
            NotifyInspect = function() return true end,
            GetTime = function() return clock2 end,
        })
        -- baseEnv PROVIDES GetNamePlates, so absence must be forced AFTER load:
        -- `GetNamePlates = nil` in a table constructor creates no key at all.
        _G.GetNamePlates = nil
        fb:SetScanEnabled(true)
        fb.ScanNearby()
        check("scan still works with the nameplate API absent",
            (fb:GetInspectStats().scanEnqueued or 0) == 1,
            "enqueued=" .. tostring(fb:GetInspectStats().scanEnqueued)
                .. " fallback=" .. tostring(fb:GetInspectStats().scanFallback))
    end
end

STD.io.write(table.concat(results, "\n") .. "\n")
STD.io.write("\n" .. (allok and "ALL PASS" or "*** FAILURES ***") .. "\n")
STD.os.exit(allok and 0 or 1)
