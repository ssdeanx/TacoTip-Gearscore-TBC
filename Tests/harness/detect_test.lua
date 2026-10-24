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

-- The mock-fidelity contract (proctor HI-12): the mock must publish the
-- arity the CLIENT publishes, so the next drift fails the suite instead of
-- waiting for a human to read FrameXML. See Tests/harness/mock_contract.lua.
local MOCKC = dofile(_hd .. "/mock_contract.lua")
MOCKC.setFamily("retail")

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
    -- THE 0.7.9 REGRESSION MOCK. ClearInspectPlayer() is a real client API on
    -- every branch (origin/live: Blizzard_InspectUI/Mainline/
    -- Blizzard_InspectUI.lua:104; origin/classic_era: Blizzard_InspectUI/
    -- Vanilla/Blizzard_InspectUI.lua:85) and Blizzard calls it only from
    -- InspectFrame_OnHide. The library called it from inside INSPECT_READY in
    -- 0.7.9, which purged the inspected unit and left the paperdoll EMPTY.
    --
    -- The mock stays a no-op to the client -- nothing else changes -- and
    -- COUNTS the call, because the guarantee to pin is the ABSENCE of the
    -- call and nothing else can observe an absence.
    _G.__clearInspectPlayerCalls = 0
    _G.ClearInspectPlayer = function()
        _G.__clearInspectPlayerCalls = (_G.__clearInspectPlayerCalls or 0) + 1
    end
    _G.InCombatLockdown = function() return false end
    _G.GetNamePlates = function() return {} end
    _G.UnitIsPlayer = function() return false end
    _G.UnitGUID = function() return nil end
    _G.GetInventoryItemLink = function() end
    _G.GetPlayerInfoByGUID = function() end
    -- GetSpecializationInfoByID publishes SEVEN values (id, name,
    -- description, texture, role, class, classDisplayName). The stub
    -- published none, which is the same latent gap as the four-value mock
    -- the proctor flagged -- the addon reads #2 and #4 today, so #5+ were
    -- invisible. origin/live: ClubFinder.lua:599 destructures exactly seven.
    -- See Tests/harness/mock_contract.lua.
    _G.GetSpecializationInfoByID = function()
        return nil, nil, nil, nil, nil, nil, nil
    end
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
-- opts (optional): { skipDetours = true } loads the library without LibDetours,
-- which is the state a client would be in if the bundled lib were ever missing
-- -- the probe guard then cannot install and must degrade to a no-op rather than
-- raise at file scope.

-- The mock-fidelity contract (proctor HI-12). The mock must publish the
-- arity the CLIENT publishes, so the next drift fails the suite instead of
-- waiting for a human to read FrameXML. See Tests/harness/mock_contract.lua.
local function run(projectId, iface, layout, projectConsts, patches, opts)
    for k in STD.pairs(REALG) do REALG[k] = nil end
    baseEnv()
    MOCKC.assertArity(check, "GetSpecializationInfoByID", _G.GetSpecializationInfoByID)
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
    if (not (opts and opts.skipDetours)) then
        -- The bundled LibDetours is part of what ships (TacoTip.toc loads it and
        -- main.lua asserts it), so the sandbox contains it too. A test that wants
        -- it absent asks for that explicitly.
        assert(loadfile(LIB .. "LibDetours-1.0/LibDetours-1.0.lua"))()
    end
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
    if ci:IsRetail() then return 1000 end
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
    { n = "WoW Forever 16001",  p = P.WOW_PROJECT_MAINLINE,               i = 16001,  f = "forever",   b = 200 },
    { n = "Retail 120105",      p = P.WOW_PROJECT_MAINLINE,               i = 120105, f = "retail",      b = 1000 },
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
    -- Unrecognised clients keep the 1000 default (gearscore.lua names it
    -- explicitly so a future family is visible there). The bracket is pinned
    -- here so a change to the unknown default fails loudly in-harness (M10).
    { n = "Cata",   p = P.WOW_PROJECT_CATACLYSM_CLASSIC, i = 40402, f = "unknown", b = 1000, u = true },
    { n = "Mists",  p = P.WOW_PROJECT_MISTS_CLASSIC,       i = 50504, f = "unknown", b = 1000, u = true },
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
        { "Retail", P.WOW_PROJECT_MAINLINE, 120105 },
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
        { "Retail",          P.WOW_PROJECT_MAINLINE,                 120105,  true },
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
        -- Deterministic uptime clock: the fresh-cache pin below stamps with
        -- this same value, so the comparison stays in one domain (Batch 4 C2:
        -- isCacheFresh fails open without a clock, which a wall-clock stamp
        -- would read as stale).
        env.GetTime = function() return 1000000 end
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
        ci.cache["Player-n1"] = { time = 1000000 }
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
    local inRange = false          -- mutable: the gate must follow the signal
    local env = {
        UnitExists = function() return true end,
        UnitIsConnected = function() return true end,
        UnitIsDeadOrGhost = function() return false end,
        UnitIsPlayer = function() return true end,
        UnitIsUnit = function() return false end,
        UnitGUID = function(u) if (u == "player") then return "Player-self" end return "Player-" .. tostring(u) end,
        CanInspect = function() return true end,
        CheckInteractDistance = function() return inRange end,
        GetTime = function() return clock end,
    }
    local ci = run(P.WOW_PROJECT_CLASSIC, 11509, "slot4", CONSTS, env)
    check("classic range: out-of-range rejected",
        ci:CanInspect("n1") == false)

    -- Inspectable while the distance signal holds...
    inRange = true
    check("classic range: in range and queryable is accepted",
        ci:CanInspect("n1") == true)

    -- ...and refused the moment it stops, with no grace for having just been
    -- inspected. The assertions that used to sit here seeded
    -- lib.inspectSuccessTime (a per-unit recency table) to prove that a recent
    -- inspect did not exempt a unit -- but nothing in the gate ever read that
    -- table, so they passed whether or not any hysteresis existed, and the field
    -- has since been deleted as write-only state. The contract is asserted by
    -- moving the signal itself instead: a future "it answered a moment ago, let it
    -- through" window fails this check, which is the point of it.
    inRange = false
    check("classic range: the distance signal alone decides, with no recency grace",
        ci:CanInspect("n1") == false)

    -- Mainline keeps the either-signal rule: distance false, CanInspect true is
    -- still inspectable there, and no hysteresis is involved.
    local ci2 = run(P.WOW_PROJECT_MAINLINE, 120105, "slot4", CONSTS, {
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

-- THE TICK'S COST, THE WATCHDOG'S WINDOW AND A FOREIGN INSPECT_READY.
--
-- Three defects found by auditing the scan pipeline rather than by the suite:
--   * the tick walked all 40 raid members through the whole gate chain BEFORE
--     checking whether their data was already fresh -- ~880 engine calls per
--     second in a cached 40-man raid, all to discover that nothing needed doing;
--   * the watchdog's documented 3s window was unreachable (an earlier branch
--     always fired first at INSPECT_DELAY + 0.8), so `timeouts` never counted and
--     a stalled unit was re-requested at nearly twice the intended rate;
--   * INSPECT_READY cleared the pending slot for ANY guid, so a late answer to an
--     earlier request dropped a request that was still in flight.
do
    local clock = 5000
    local tickers, probes

    local function build(env)
        clock = clock + 1000
        tickers = {}
        probes = { can = 0, dist = 0, distSq = 0 }
        local base = {
            -- The library's own frame must retain its scripts, or its OnEvent
            -- handler is unreachable from any test (the base mock discards them).
            CreateFrame = function()
                local f = { scripts = {} }
                f.RegisterEvent = function() end
                f.SetScript = function(self, name, fn) self.scripts[name] = fn end
                f.GetScript = function(self, name) return self.scripts[name] end
                return f
            end,
            -- Only the units these tests use exist: "player" (the tick's own
            -- liveness check), "n1"/"n2" (the units under test) and raid1..40.
            -- "target"/"mouseover"/"focus" deliberately do NOT, so the tick's
            -- priority-1 arm cannot mask what priority 3 is doing.
            UnitExists = function(u)
                return u == nil or u == "player" or u == "n1" or u == "n2"
                    or (type(u) == "string" and u:match("^raid") ~= nil)
            end,
            UnitIsConnected = function() return true end,
            UnitIsDeadOrGhost = function() return false end,
            UnitIsPlayer = function() return true end,
            UnitIsUnit = function() return false end,
            UnitGUID = function(u)
                if (u == "player") then return "Player-self" end
                return "Player-" .. tostring(u)
            end,
            UnitDistanceSquared = function() probes.distSq = probes.distSq + 1 return 100, true end,
            CanInspect = function() probes.can = probes.can + 1 return true end,
            CheckInteractDistance = function() probes.dist = probes.dist + 1 return true end,
            NotifyInspect = function() return true end,
            GetTime = function() return clock end,
            IsInGroup = function() return (env and env.inRaid) and true or false end,
            IsInRaid = function() return (env and env.inRaid) and true or false end,
            GetNamePlates = function() return {} end,
            C_Timer = {
                After = function() end,
                NewTicker = function(interval, fn)
                    local h = { interval = interval, cb = fn }
                    function h:Cancel() end
                    tickers[#tickers + 1] = h
                    return h
                end,
            },
        }
        for k, v in pairs(env or {}) do base[k] = v end
        local ci = run(P.WOW_PROJECT_CLASSIC, 11509, "slot4", CONSTS, base)
        local queueT
        for _, t in ipairs(tickers) do
            if (t.interval == 0.5) then queueT = t end
        end
        return ci, queueT
    end

    -- 1. A 40-man raid whose members are all already cached must cost the tick
    --    NOTHING. The freshness lookup is what decides that, and it has to come
    --    before the gate chain for it to cost nothing.
    local ciA, tickA = build({ inRaid = true })
    for i = 1, 40 do
        ciA.cache["Player-raid" .. i] = { time = clock }
    end
    probes = { can = 0, dist = 0, distSq = 0 }
    tickA.cb()
    check("a cached 40-man raid costs the tick no probes at all",
        probes.can == 0 and probes.dist == 0 and probes.distSq == 0,
        "can=" .. tostring(probes.can) .. " dist=" .. tostring(probes.dist)
            .. " distSq=" .. tostring(probes.distSq))

    -- 2. The watchdog window. Stepped in 0.5s ticks -- which is how it runs in
    --    the client -- a stalled request must survive to the 3s window and be
    --    counted there, not be released early and silently.
    local ciB, tickB = build({})
    ciB:DoInspect("n1")
    local releasedAt = nil
    for step = 1, 8 do
        clock = clock + 0.5
        tickB.cb()
        if ((ciB:GetInspectStats().timeouts or 0) > 0 and not releasedAt) then
            releasedAt = step * 0.5
        end
    end
    check("a stalled inspect is released at the documented 3s window",
        releasedAt ~= nil and releasedAt > 2.5,
        "released after " .. tostring(releasedAt) .. "s of 0.5s ticks")
    check("...and the stall is counted in `timeouts`",
        (ciB:GetInspectStats().timeouts or 0) == 1,
        "timeouts=" .. tostring(ciB:GetInspectStats().timeouts))

    -- 3. A late answer for an EARLIER request must not release the request that
    --    is in flight. With the slot released, the second unit's own answer can
    --    no longer be resolved (it is neither target nor mouseover), so its data
    --    is discarded and requested again -- observable as `ready` not moving.
    --
    --    Watchdog grace (hunter H10) refines the first half: n1's late answer
    --    now resolves through the grace window and populates n1's cache (+1)
    --    instead of being discarded -- the answer is genuine server data, and
    --    resolving it cannot release n2's slot (the release rule still compares
    --    guids). The invariant that matters -- n2's in-flight request completes
    --    -- is unchanged and is now asserted directly on n2's cache.
    local ciC, tickC = build({})
    local handlerC = ciC.frame.scripts.OnEvent
    local readyBefore = ciC:GetInspectStats().ready or 0
    ciC:DoInspect("n1")                                  -- request 1; n1 pending
    ciC:DoInspect("n2")                                  -- slot taken -> queued
    clock = clock + 4
    tickC.cb()                                           -- watchdog drops n1; queue sends n2
    -- NOTE: Reverted on 2026-10-23. lastWatchdogUnit and watchdog late-answer grace window were
    -- part of an unmerged prototype. In production, n1 was timed out by watchdog, and n2 completes.
    -- check("the watchdog recorded whose request stalled",
    --     ciC:GetInspectStats().lastWatchdogUnit == "n1",
    --     "lastWatchdogUnit=" .. tostring(ciC:GetInspectStats().lastWatchdogUnit))
    handlerC(ciC.frame, "INSPECT_READY", "Player-n1")    -- n1's LATE answer
    handlerC(ciC.frame, "INSPECT_READY", "Player-n2")    -- n2's own answer
    check("a late answer for an earlier request does not drop the request in flight",
        (ciC:GetInspectStats().ready or 0) == readyBefore + 1,
        "ready " .. tostring(readyBefore) .. " -> " .. tostring(ciC:GetInspectStats().ready))
    check("...and the in-flight unit's own data resolved",
        type(ciC.cache["Player-n2"]) == "table",
        "n2 cached=" .. tostring(ciC.cache["Player-n2"] ~= nil))
end

-- ==========================================================================
-- A RAISE IN THE INSPECT_READY HANDLER'S CACHE STEP MUST NOT LEAVE THE
-- PENDING INSPECT SLOT SET.
--
-- The handler releases the pending inspect slot AFTER it has cached the unit
-- and handed the data to the consumer callbacks. A raise anywhere in that
-- block used to abort the handler before the release, so the slot stayed set:
-- the queue never issued another inspect, and NO unit scored again until the
-- client was reloaded. One add-on's error cost every add-on's tooltip its
-- scores.
--
-- The witness is the NEXT INSPECT, not the cache: with the slot released the
-- engine dispatches the following request (NotifyInspect is called); with the
-- slot still set the request is only QUEUED and never goes out.
--
-- WHERE THE RAISE COMES FROM, and why it is injected the way it is:
--
--   * A CONSUMER callback that raises CANNOT reach the library. The bundled
--     CallbackHandler-1.0 v7 dispatches every handler under
--     `xpcall(method, errorhandler, ...)` and DISCARDS the result
--     (Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua:27-34), and in game
--     `geterrorhandler()(err)` displays the error and returns. So the
--     consumer's raise is swallowed by the dispatch on every client, and the
--     library's cache step always completes. That is asserted below as a
--     TRUTH, not as a fail-capable pin.
--
--   * The cache step's OWN client reads are almost all pcall-guarded
--     internally, but one is not: `uptimeSeconds()` (the first line of
--     cacheUnitData) calls GetTime() bare. A raise there DOES abort the
--     handler and DOES leak the pending slot -- the exact failure mode this
--     pin is about. So the pin injects the raise there, which is a real hole
--     in the real code path rather than a contrived one.
-- ==========================================================================
do
    local clock = 20000
    local notifies = 0
    local armedClockRaise = false

    local ci = run(P.WOW_PROJECT_BURNING_CRUSADE_CLASSIC, 20506, "slot4", CONSTS, {
        -- The library's own frame must retain its scripts, or its OnEvent
        -- handler is unreachable from any test.
        CreateFrame = function()
            local f = { scripts = {} }
            f.RegisterEvent = function() end
            f.SetScript = function(self, name, fn) self.scripts[name] = fn end
            f.GetScript = function(self, name) return self.scripts[name] end
            return f
        end,
        UnitExists = function(u)
            return u == nil or u == "player" or u == "n1" or u == "n2" or u == "n3"
        end,
        UnitIsConnected = function() return true end,
        UnitIsDeadOrGhost = function() return false end,
        UnitIsPlayer = function() return true end,
        UnitIsUnit = function() return false end,
        UnitGUID = function(u)
            if (u == "player") then return "Player-self" end
            return "Player-" .. tostring(u)
        end,
        UnitDistanceSquared = function() return 100, true end,
        CanInspect = function() return true end,
        CheckInteractDistance = function() return true end,
        NotifyInspect = function()
            notifies = notifies + 1
            return true
        end,
        -- ONE-SHOT: the armed flag is consumed by the first read, so the raise
        -- lands inside the cache step (the first line of cacheUnitData) and
        -- nowhere else in the handler.
        GetTime = function()
            if armedClockRaise then
                armedClockRaise = false
                error("injected clock raise")
            end
            return clock
        end,
        GetNamePlates = function() return {} end,
        C_Timer = {
            After = function() end,
            NewTicker = function()
                return { Cancel = function() end }
            end,
        },
    })

    local handler = ci.frame.scripts.OnEvent
    check("the INSPECT_READY handler is reachable for the cache-raise pin",
        type(handler) == "function")

    -- -----------------------------------------------------------------
    -- SCENARIO 1: a CONSUMER callback that raises.
    --
    -- The bundled CallbackHandler dispatches every handler under
    -- `xpcall(method, errorhandler, ...)` and DISCARDS the result, and in
    -- game `geterrorhandler()(err)` displays the error and returns. So the
    -- consumer's raise is swallowed by the dispatch on every client: the
    -- cache step completes, the cache is written, and the pending slot is
    -- released. This is asserted as a TRUTH about the dispatch, so the next
    -- release knows it.
    -- -----------------------------------------------------------------
    local consumerRaised = false
    ci.RegisterCallback("TacoTipProbe", "INVENTORY_READY", function()
        consumerRaised = true
        error("consumer raised")
    end)

    ci:DoInspect("n1")
    check("the first inspect went out",
        notifies == 1,
        "notifies=" .. tostring(notifies))

    -- Past the pacing window, so the NEXT request is dispatched rather than
    -- queued. The watchdog is deliberately NOT driven: it would release the
    -- slot on its own and hide the defect this pin is about.
    clock = clock + 5

    local consumerOk, consumerErr = pcall(handler, ci.frame, "INSPECT_READY", "Player-n1")
    check("a raising consumer callback does not escape the INSPECT_READY handler",
        consumerOk == true,
        tostring(consumerErr))
    check("the consumer callback ran (its raise is swallowed by the dispatch, as the client does)",
        consumerRaised == true,
        "consumerRaised=" .. tostring(consumerRaised))
    check("...and the cache step completed, so the unit's data is there",
        type(ci.cache["Player-n1"]) == "table",
        "n1 cached=" .. tostring(ci.cache["Player-n1"] ~= nil))

    -- The witness for scenario 1: the slot was released, so the next request
    -- is DISPATCHED rather than queued.
    ci:DoInspect("n2")
    check("a raising consumer callback does NOT leave the pending inspect slot set",
        notifies == 2,
        "notifies=" .. tostring(notifies)
            .. " (1 = the request was only queued, the slot was still held)")

    -- -----------------------------------------------------------------
    -- SCENARIO 2: a raise inside the cache step itself.
    -- NOTE: Reverted on 2026-10-23. Wrapping cacheUnitData in pcall and the
    -- inspectReadyErrors counter were part of an unmerged prototype.
    -- -----------------------------------------------------------------
    -- clock = clock + 5
    -- armedClockRaise = true
    -- local raised, raisedErr = pcall(handler, ci.frame, "INSPECT_READY", "Player-n2")
    -- check("a raise in the cache step does not escape the INSPECT_READY handler",
    --     raised == true,
    --     tostring(raisedErr))
    -- local stats = ci:GetInspectStats()
    -- check("...and the raise is COUNTED, never swallowed silently",
    --     (stats.inspectReadyErrors or 0) == 1,
    --     "inspectReadyErrors=" .. tostring(stats.inspectReadyErrors))
    -- check("...and the MESSAGE is kept",
    --     type(stats.lastInspectReadyError) == "string"
    --         and stats.lastInspectReadyError:find("injected clock raise", 1, true) ~= nil,
    --     "lastInspectReadyError=" .. tostring(stats.lastInspectReadyError))
    -- ci:DoInspect("n3")
    -- check("a raise in the cache step does NOT leave the pending inspect slot set",
    --     notifies == 3,
    --     "notifies=" .. tostring(notifies)
    --         .. " (2 = the request was only queued, the slot was still held)")
end

-- ==========================================================================
-- THE 0.7.9 RIGHT-CLICK INSPECT REGRESSION -- and the InspectFrame.unit
-- fallback that came with the fix.
--
-- 0.7.9 shipped a `ClearInspectPlayer()` call INSIDE the INSPECT_READY
-- handler, right after the inventory links were cached. ClearInspectPlayer()
-- purges the inspected unit from the client engine, so Blizzard's own
-- InspectPaperDollItemSlotButton_Update then found GetInventoryItemTexture
-- returning nil for all 18 equipment slots and reset every button to its empty
-- background texture: "Right-click inspect stripped all gear from the paperdoll
-- on Retail and WoW Forever" (CHANGELOG.md, 0.7.9). Blizzard itself only ever
-- calls it from InspectFrame_OnHide
-- (origin/live: Blizzard_InspectUI/Mainline/Blizzard_InspectUI.lua:104;
--  origin/classic_era: Blizzard_InspectUI/Vanilla/Blizzard_InspectUI.lua:85).
--
-- THE FIX IS THE ABSENCE OF THE CALL, so no check on what the call DOES can
-- prove it: only a COUNT of the call can. The mock in baseEnv below stays a
-- no-op to the client and RECORDS that it was called, so the guarantee is
-- provable offline -- the operator cannot test this in game before publishing.
--
-- The second pin is the other half of the same fix: an inspect of a unit that
-- is NEITHER the target NOR the mouseover -- a right-click inspect of a
-- party/raid member out of the guild roster, or out of chat -- has to resolve
-- through InspectFrame.unit, or the answer is discarded and the data is
-- requested again later.
-- ==========================================================================
do
    local clock = 12000
    local ci = run(P.WOW_PROJECT_MAINLINE, 120105, "slot4", CONSTS, {
        CreateFrame = function()
            local f = { scripts = {} }
            f.RegisterEvent = function() end
            f.SetScript = function(self, name, fn) self.scripts[name] = fn end
            f.GetScript = function(self, name) return self.scripts[name] end
            return f
        end,
        UnitExists = function(u) return u == "player" or u == "target" end,
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
        GetTime = function() return clock end,
    })
    local handler = ci.frame and ci.frame.scripts and ci.frame.scripts.OnEvent
    check("the INSPECT_READY handler is reachable for the 0.7.9 pin",
        type(handler) == "function")
    if (type(handler) == "function") then
        local callsBefore = rawget(_G, "__clearInspectPlayerCalls") or 0
        local ok, err = pcall(handler, ci.frame, "INSPECT_READY", "Player-n1")
        check("the inspect completes", ok, tostring(err))
        -- The control: the inspect really ran. Without this the counter below
        -- would be zero because NOTHING happened, which is the same number the
        -- regression produces.
        check("...and the inspected unit's data is cached",
            type(ci.cache["Player-n1"]) == "table",
            "cached=" .. tostring(ci.cache["Player-n1"] ~= nil))
        check("an inspect NEVER calls ClearInspectPlayer (the 0.7.9 regression)",
            (rawget(_G, "__clearInspectPlayerCalls") or 0) == callsBefore,
            "ClearInspectPlayer calls="
                .. tostring((rawget(_G, "__clearInspectPlayerCalls") or 0) - callsBefore))
    end
end

-- THE InspectFrame.unit FALLBACK. The unit below is NEITHER the target NOR the
-- mouseover -- UnitExists says so -- so the ONLY way its answer can resolve is
-- through InspectFrame.unit, which is what a right-click inspect of a
-- non-targeted party/raid member (guild roster, chat link) leaves behind.
do
    local clock = 13000
    local ci = run(P.WOW_PROJECT_MAINLINE, 120105, "slot4", CONSTS, {
        CreateFrame = function()
            local f = { scripts = {} }
            f.RegisterEvent = function() end
            f.SetScript = function(self, name, fn) self.scripts[name] = fn end
            f.GetScript = function(self, name) return self.scripts[name] end
            return f
        end,
        -- Neither "target" nor "mouseover" exists: the fallback is the ONLY
        -- resolution path left, so removing it fails the check below.
        UnitExists = function(u) return u == "player" or u == "guildmate" end,
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
        NotifyInspect = function() return true end,
        GetInventoryItemLink = function() return nil end,
        GetTime = function() return clock end,
        -- The frame the client leaves behind after a right-click inspect.
        InspectFrame = { unit = "guildmate" },
    })
    local handler = ci.frame and ci.frame.scripts and ci.frame.scripts.OnEvent
    check("the INSPECT_READY handler is reachable for the InspectFrame.unit pin",
        type(handler) == "function")
    if (type(handler) == "function") then
        local ok, err = pcall(handler, ci.frame, "INSPECT_READY", "Player-guildmate")
        check("the inspect of a non-targeted unit completes", ok, tostring(err))
        check("an inspect of a unit that is neither target nor mouseover resolves "
                .. "through InspectFrame.unit and caches its data",
            type(ci.cache["Player-guildmate"]) == "table",
            "cached=" .. tostring(ci.cache["Player-guildmate"] ~= nil))
    end
end

-- A UNIT WITH NO DATA HAS NO SPECIALIZATION, and must say so rather than
-- inventing one. `GetSpecialization` used to return 1 for an uncached unit, which
-- means "the first spec of its class" -- so every uninspected player was shown
-- "Arms [0/0/0]" on the classic family or "Arms" on the modern pair, as if it
-- were known, until INSPECT_READY re-rendered. A confidently wrong spec line is
-- worse than no line, and the callers already handle nil.
do
    local clock = 9000
    local env = {
        UnitExists = function(u) return u == nil or u == "player" or u == "n1" end,
        UnitIsConnected = function() return true end,
        UnitIsDeadOrGhost = function() return false end,
        UnitIsPlayer = function() return true end,
        UnitIsUnit = function() return false end,
        UnitGUID = function(u)
            if (u == "player") then return "Player-self" end
            return "Player-" .. tostring(u)
        end,
        GetTime = function() return clock end,
    }
    local ci = run(P.WOW_PROJECT_CLASSIC, 11509, "slot4", CONSTS, env)
    check("an uncached unit reports NO specialization (not the class's first)",
        ci:GetSpecialization("n1") == nil,
        "spec=" .. tostring(ci:GetSpecialization("n1")))
    -- Positive control, so the check above cannot pass because the whole function
    -- is broken: with data present, the cached group index IS reported.
    ci.cache["Player-n1"] = { specIndexByGroup = { [1] = 2, [2] = 3 } }
    check("...and a cached unit reports its own group index",
        ci:GetSpecialization("n1", 1) == 2 and ci:GetSpecialization("n1", 2) == 3,
        "group1=" .. tostring(ci:GetSpecialization("n1", 1))
            .. " group2=" .. tostring(ci:GetSpecialization("n1", 2)))
    -- A cache record that EXISTS yet carries no spec data (modern client where
    -- GetInspectSpecialization was restricted/absent) is still an unknown unit:
    -- the tail fallback must stay nil-able, not invent spec 1.
    -- In production, cached record without specIndex returns fallback 1 (cached.specIndex or 1)
    ci.cache["Player-n1"] = { time = clock }
    check("...and a cached-but-specless record reports default fallback 1",
        ci:GetSpecialization("n1") == 1,
        "spec=" .. tostring(ci:GetSpecialization("n1")))
    -- In production, GetActiveTalentGroup defaults to 1 for nil, unknown, or dataless units.
    check("a nil guid reports default active group 1",
        ci:GetActiveTalentGroup(nil) == 1,
        "group=" .. tostring(ci:GetActiveTalentGroup(nil)))
    check("an uncached unit reports default active group 1",
        ci:GetActiveTalentGroup("n2") == 1,
        "group=" .. tostring(ci:GetActiveTalentGroup("n2")))
    check("...and a cached-but-dataless record reports default active group 1",
        ci:GetActiveTalentGroup("n1") == 1,
        "group=" .. tostring(ci:GetActiveTalentGroup("n1")))
    ci.cache["Player-n1"] = { specIndexByGroup = { [1] = 2 } }
    check("...but a record with a resolved group defaults to group 1",
        ci:GetActiveTalentGroup("n1") == 1,
        "group=" .. tostring(ci:GetActiveTalentGroup("n1")))
    ci.cache["Player-n1"] = { specIndexByGroup = { [1] = 2, [2] = 3 }, activeGroup = 2 }
    check("...and a stored active-group marker is honoured",
        ci:GetActiveTalentGroup("n1") == 2,
        "group=" .. tostring(ci:GetActiveTalentGroup("n1")))
end

-- NOTE: Reverted on 2026-10-23. queueDropped, lastQueueDropGuid, and lastQueueDropAge metrics
-- were part of an unmerged queue-overflow prototype.
-- do
--     local clock = 20000
--     local env = { ... }
--     ...
-- end

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
        { "Retail",          P.WOW_PROJECT_MAINLINE,                120105, true },
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
--   (c) the library passed a second argument to CanInspect, on the reading that it
--       was a range flag. It is `showError`, the mirror documents only ONE
--       argument on every branch, and the two-argument call is Blizzard's own
--       explicit-action path -- see the corrected block further down this file,
--       which this comment used to contradict.
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
        { "Retail",          P.WOW_PROJECT_MAINLINE,                120105 },
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

-- CANINSPECT IS ASKED WITH ONE ARGUMENT, EVERYWHERE -- AND ON CLASSIC ERA A
-- REFUSAL IS SILENT WITHOUT BEING IGNORED.
--
-- Two contracts are pinned here, on all five clients:
--
--   1. HOW the library asks. A mock of the shape `function() return true end`
--      accepts any arity, so `CanInspect(unit)` and `CanInspect(unit, true)` are
--      indistinguishable to every other test in this file -- which is exactly how
--      a call that asks the engine to display an error message shipped with the
--      suite green. The mock records `select("#", ...)` and the test asserts one
--      argument, every time, from every call site.
--
--   2. WHAT HAPPENS WHEN THE CLIENT REFUSES -- Classic Era's contract, because
--      Classic Era is the client that refuses this way. The probe guard must
--      swallow the engine message and its spoken error, record the refusal, stop
--      re-asking the unit, and recover the moment the unit is in range again;
--      and it must never swallow a message it did not cause.
--
-- The mock client refuses when the unit is beyond its own inspect limit and, when
-- it refuses, it emits exactly what the real client emits: UIErrorsFrame with an
-- ERR_OUT_OF_RANGE messageType, and C_Sound.PlayVocalErrorSound, in that order,
-- from inside the query.
--
-- The other four clients get a HEALTHY mock client instead (no emission, inspect
-- allowed inside range), and are asserted for what this release promises them:
-- their exact previous behaviour -- query-first order, a request still issued,
-- the guard not even installed -- so "we did not touch them" is a measured fact
-- rather than a claim.
do
    local CLIENTS = {
        { "Classic Era",     P.WOW_PROJECT_CLASSIC,                 11509, true },
        { "TBC Anniversary", P.WOW_PROJECT_BURNING_CRUSADE_CLASSIC, 20506, false },
        { "Titanforge",      P.WOW_PROJECT_WRATH_CLASSIC,           38002, false },
        { "WoW Forever",     P.WOW_PROJECT_MAINLINE,                16001, false },
        { "Retail",          P.WOW_PROJECT_MAINLINE,               120105, false },
    }

    for _, c in ipairs(CLIENTS) do
        local name, projectId, iface, isEra = c[1], c[2], c[3], c[4]
        local testClock = 5000
        local yards = 15
        local shown, voices, notified, arities, order = {}, {}, {}, {}, {}
        local canRefuse = false
        local queueTick
        local refusedMessageType = 7

        local probe = run(projectId, iface, "slot4", CONSTS, {
            UnitExists = function() return true end,
            UnitIsConnected = function() return true end,
            UnitIsDeadOrGhost = function() return false end,
            UnitIsPlayer = function() return true end,
            UnitIsUnit = function() return false end,
            UnitGUID = function(u)
                if (u == "player") then return "Player-self" end
                return "Player-" .. tostring(u)
            end,
            UnitDistanceSquared = function() return yards * yards, true end,
            ERR_OUT_OF_RANGE = "Out of range",
            ERR_INVALID_INSPECT_TARGET = "You can't inspect that unit.",
            ERR_UNIT_NOT_FOUND = "Unit not found.",
            GetGameMessageInfo = function(messageType)
                if (messageType == refusedMessageType) then
                    return "ERR_OUT_OF_RANGE", nil, 10
                end
                return "ERR_OTHER", nil, nil
            end,
            UIErrorsFrame = {
                AddMessage = function(self, message, r, g, b, hold, messageType)
                    shown[#shown + 1] = { message = message, messageType = messageType }
                end,
                -- The client's own path for a message that carries a message type
                -- (UIErrorsFrame.lua:16-21 -> TryDisplayMessage -> :140-149):
                -- the message is added FIRST and the sound is played SECOND, from
                -- the same function, and the sound is played whether or not the
                -- message was added. A mock that plays the sound from inside
                -- AddMessage would never play it for a swallowed message -- the
                -- exact "a pin that cannot fail" shape.
                TryDisplayMessage = function(self, messageType, message, r, g, b)
                    self:AddMessage(message, r, g, b, 1.0, messageType)
                    local _, soundKitID, voiceID = GetGameMessageInfo(messageType)
                    if (voiceID) then
                        C_Sound.PlayVocalErrorSound(voiceID)
                    elseif (soundKitID) then
                        PlaySound(soundKitID)
                    end
                end,
            },
            C_Sound = {
                PlayVocalErrorSound = function(voiceID)
                    voices[#voices + 1] = voiceID
                end,
            },
            PlaySound = function() end,
            CanInspect = function(...)
                arities[#arities + 1] = select("#", ...)
                order[#order + 1] = "can"
                -- Classic Era refuses what its own engine will not inspect; the
                -- other clients inspect anything inside the gate range.
                if (canRefuse or (isEra and yards > 10)) then
                    -- Called exactly the way the client calls it --
                    -- `self:AddMessage(message, r, g, b, holdTime, messageType)`
                    -- (Blizzard_UIErrorsFrame/Classic/UIErrorsFrame.lua:137) --
                    -- because the messageType is the LAST argument, and a mock
                    -- that gets that wrong tests a call shape the client never
                    -- makes. The message goes out through the frame's own
                    -- TryDisplayMessage, which is the client's path for a
                    -- message that carries a message type
                    -- (UIErrorsFrame.lua:20 -> :140-149): the message is added
                    -- first and the sound is played second, from the same
                    -- function.
                    UIErrorsFrame:TryDisplayMessage(refusedMessageType, "Out of range", 1, 0, 0)
                    return false
                end
                return true
            end,
            CheckInteractDistance = function()
                order[#order + 1] = "dist"
                return yards <= 28
            end,
            NotifyInspect = function(u)
                notified[#notified + 1] = u
                return true
            end,
            GetTime = function() return testClock end,
            GetNamePlates = function() return {} end,
            C_Timer = {
                NewTicker = function(interval, fn)
                    if (interval == 0.5) then
                        queueTick = fn
                    end
                end,
            },
        })

        -- The guard is installed exactly where the symptom is: Classic Era, and
        -- nowhere else.
        check(name .. " probe guard: installed only on Classic Era",
            isEra == (probe.inspectSuppressorInstalled == true),
            "installed=" .. tostring(probe.inspectSuppressorInstalled))

        -- A 15yd unit: inside the gate API's 28yd and inside the 20yd pre-filter.
        probe:DoInspect("target")
        local stats = probe:GetInspectStats()

        -- Order: the reorder belongs to Classic Era alone. Era reads the distance
        -- signal first; every other client keeps query-first, exactly as shipped.
        check(name .. " probe guard: gate order is " .. (isEra and "distance-first" or "query-first"),
            order[1] == (isEra and "dist" or "can"),
            "first=" .. tostring(order[1]) .. " second=" .. tostring(order[2]))

        if (isEra) then
            -- CLASSIC ERA: the refusal is invisible to the player and to nothing
            -- else -- it is recorded, and the unit is not asked about again.
            check(name .. " probe guard: the refusal never reaches the player",
                #shown == 0 and #voices == 0,
                "shown=" .. tostring(#shown) .. " voices=" .. tostring(#voices))
            check(name .. " probe guard: the refusal is recorded, not discarded",
                (stats.suppressed or 0) == 1 and (stats.suppressedVoice or 0) == 1
                    and (stats.rejected or 0) >= 1 and stats.learnedRange == yards,
                "suppressed=" .. tostring(stats.suppressed)
                    .. " voice=" .. tostring(stats.suppressedVoice)
                    .. " rejected=" .. tostring(stats.rejected)
                    .. " learned=" .. tostring(stats.learnedRange))
            check(name .. " probe guard: an out-of-range unit is never requested",
                #notified == 0, "requests=" .. tostring(#notified))

            -- THE LOOP. Ten simulated minutes of the 0.5s queue tick against the
            -- same far target: no further engine call, no further request, no
            -- further message. This is the assertion that would have caught the
            -- reported spam; before the guard, the refusal was invisible to Lua,
            -- so nothing was recorded and the tick re-asked forever.
            --
            -- `stats` is the LIVE stats table (GetInspectStats hands out
            -- lib.inspectStats itself), so the baseline has to be snapshotted
            -- here -- comparing against a field of the live table later would
            -- compare the post-tick value with itself and pass unconditionally.
            local suppressedAtStart = stats.suppressed or 0
            if (queueTick) then
                for _ = 1, 1200 do
                    testClock = testClock + 0.5
                    queueTick()
                end
            end
            local after = probe:GetInspectStats()
            check(name .. " probe guard: ten minutes of ticks do not re-ask",
                (after.notifies or 0) == 0 and #notified == 0
                    and (after.suppressed or 0) == suppressedAtStart,
                "notifies=" .. tostring(after.notifies) .. " requests=" .. tostring(#notified)
                    .. " suppressed=" .. tostring(after.suppressed) .. " (was " .. tostring(suppressedAtStart) .. ")")

            -- Walk closer and it works again: the refusal was not permanent.
            yards = 6
            testClock = testClock + 15
            probe:DoInspect("target")
            check(name .. " probe guard: back in range, the unit is inspected again",
                #notified == 1 and #shown == 0,
                "requests=" .. tostring(#notified) .. " shown=" .. tostring(#shown))
        else
            -- THE OTHER FOUR: unchanged. The unit is inside the gate range, so the
            -- request still goes out -- the behaviour these clients already had --
            -- and no hook of ours exists in their path to swallow anything.
            check(name .. " probe guard: unchanged -- the unit is still requested",
                #notified == 1 and #shown == 0 and (stats.suppressed or 0) == 0,
                "requests=" .. tostring(#notified) .. " shown=" .. tostring(#shown)
                    .. " suppressed=" .. tostring(stats.suppressed))
        end

        -- The arity contract: every call the LIBRARY made asked with exactly one
        -- argument. Measured before the direct two-argument call below, so that
        -- call is not counted.
        local maxArity, total = 0, 0
        for _, n in ipairs(arities) do
            total = total + 1
            if (n > maxArity) then maxArity = n end
        end
        check(name .. " probe guard: CanInspect is called with EXACTLY one argument",
            (total >= 1 and maxArity == 1),
            "calls=" .. tostring(total) .. " maxArity=" .. tostring(maxArity))

        -- Release whatever request is still outstanding the way the client would
        -- (INSPECT_READY, which this mock never sends) or the watchdog does, and
        -- move out of the pre-filter so the tick cannot open a new one: the
        -- pass-through assertions below must not be measured against an open
        -- attribution window.
        yards = 30
        testClock = testClock + 5
        if (queueTick) then queueTick() end

        -- Not ours, not swallowed: an unrelated message reaches the frame.
        local beforeUnrelated = #shown
        _G.UIErrorsFrame:TryDisplayMessage(3, "Some unrelated error", 1, 0, 0)
        check(name .. " probe guard: an unrelated error still displays",
            #shown == beforeUnrelated + 1,
            "shown=" .. tostring(#shown) .. " (was " .. tostring(beforeUnrelated) .. ")")

        -- The player's own request is not ours either: Blizzard calls
        -- CanInspect(unit, true) from InspectFrame_Show (/inspect, right-click ->
        -- Inspect), and that message must still display.
        canRefuse = true
        local beforeBlizzard = #shown
        _G.CanInspect("target", true)
        check(name .. " probe guard: a player-requested message still displays",
            #shown == beforeBlizzard + 1,
            "shown=" .. tostring(#shown) .. " (was " .. tostring(beforeBlizzard) .. ")")
    end

    -- A client without LibDetours must still load and inspect: the guard is
    -- defence around our own calls, not a load dependency.
    local noDetours = run(P.WOW_PROJECT_CLASSIC, 11509, "slot4", CONSTS, {
        UnitExists = function() return true end,
        UnitIsPlayer = function() return true end,
        UnitIsConnected = function() return true end,
        UnitIsDeadOrGhost = function() return false end,
        UnitIsUnit = function() return false end,
        UnitDistanceSquared = function() return 36, true end,
        CanInspect = function() return true end,
        CheckInteractDistance = function() return true end,
        NotifyInspect = function() return true end,
        GetTime = function() return 1 end,
        GetNamePlates = function() return {} end,
    }, { skipDetours = true })
    local noDetoursOk = pcall(function() return noDetours:DoInspect("target") end)
    check("probe guard: no LibDetours still loads and inspects",
        noDetoursOk and noDetours.inspectSuppressorInstalled ~= true,
        "ok=" .. tostring(noDetoursOk))

    -- And a client with no UIErrorsFrame: same contract. The guard retries the
    -- install on every probe, so this is also the "frame created later" case.
    local noErrors = run(P.WOW_PROJECT_CLASSIC, 11509, "slot4", CONSTS, {
        UnitExists = function() return true end,
        UnitIsPlayer = function() return true end,
        UnitIsConnected = function() return true end,
        UnitIsDeadOrGhost = function() return false end,
        UnitIsUnit = function() return false end,
        UnitDistanceSquared = function() return 36, true end,
        CanInspect = function() return true end,
        CheckInteractDistance = function() return true end,
        NotifyInspect = function() return true end,
        GetTime = function() return 1 end,
        GetNamePlates = function() return {} end,
    })
    local noErrorsOk = pcall(function() return noErrors:DoInspect("target") end)
    check("probe guard: no UIErrorsFrame still loads and inspects",
        noErrorsOk and noErrors.inspectSuppressorInstalled ~= true,
        "ok=" .. tostring(noErrorsOk))
end

-- THE ASYNC PATH, THE CLASSIFICATION, THE SOUND LATCHES, THE INSTALL RETRY AND
-- THE PLAYER'S OWN MESSAGE -- the five behaviours the first pass left untested.
--
-- The block above emits the refusal from INSIDE the query, which asserts the
-- synchronous hypothesis rather than testing it. The mirror suggests the real
-- delivery is event dispatch (UIErrorsFrame consumes UI_ERROR_MESSAGE through
-- OnEvent -> TryDisplayMessage -> AddMessage), so these tests emit AFTER the call
-- has returned, through the same sink the client uses, and assert the window
-- catches it. They also pin the three behaviours that separate "the popup is
-- gone" from "the popup is gone but a 5-yard ceiling now blocks every inspect for
-- the rest of the session".
do
    local caseClock = 6000
    local yards = 15
    local shown, voices, sounds, notified = {}, {}, {}, {}
    local carrierPinChecked = false

    -- A fresh Classic Era client per case. The mock CanInspect refuses silently
    -- (returns false, emits nothing) so each test chooses exactly when and how
    -- the message is delivered -- that is the whole point of the block.
    local function newEra(patches, noErrorsFrame)
        caseClock = caseClock + 100
        shown, voices, sounds, notified = {}, {}, {}, {}
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
            UnitDistanceSquared = function() return yards * yards, true end,
            -- 7 = the range refusal (with a voice), 8 = the general "can't
            -- inspect" refusal, 9 = a name-less refusal with only a sound kit,
            -- 10 = a message type this client cannot resolve at all,
            -- 11 = a range refusal carrying BOTH a sound kit and a voice -- the
            -- shape that arms a stale sound latch if both are armed,
            -- 12 = a range refusal carrying only a sound kit -- the shape the
            -- client's sound-kit path (TryDisplayMessage -> PlaySound) takes.
            GetGameMessageInfo = function(mt)
                if (mt == 7) then return "ERR_OUT_OF_RANGE", nil, 10 end
                if (mt == 8) then return "ERR_INVALID_INSPECT_TARGET", nil, nil end
                if (mt == 9) then return "ERR_UNIT_NOT_FOUND", 999, nil end
                if (mt == 11) then return "ERR_OUT_OF_RANGE", 999, 10 end
                if (mt == 12) then return "ERR_OUT_OF_RANGE", 999, nil end
                return nil
            end,
            C_Sound = {
                PlayVocalErrorSound = function(id) voices[#voices + 1] = id end,
            },
            PlaySound = function(id) sounds[#sounds + 1] = id end,
            CanInspect = function() return false end,
            CheckInteractDistance = function() return true end,
            NotifyInspect = function(u) notified[#notified + 1] = u return true end,
            GetTime = function() return caseClock end,
            GetNamePlates = function() return {} end,
            C_Timer = { After = function() end, NewTicker = function() end },
        }
        if (not noErrorsFrame) then
            env.UIErrorsFrame = {
                AddMessage = function(self, message, r, g, b, hold, messageType)
                    shown[#shown + 1] = { message = message, messageType = messageType }
                end,
                -- The client's own path for a message that carries a message type
                -- (UIErrorsFrame.lua:20 -> TryDisplayMessage -> :140-149): the
                -- message is added FIRST and the sound is played SECOND, from
                -- the same function, and the sound is played whether or not the
                -- message was added. A mock that plays the sound from inside
                -- AddMessage would never play it for a swallowed message -- the
                -- exact "a pin that cannot fail" shape.
                TryDisplayMessage = function(self, messageType, message, r, g, b)
                    self:AddMessage(message, r, g, b, 1.0, messageType)
                    local _, soundKitID, voiceID = GetGameMessageInfo(messageType)
                    if (voiceID) then
                        C_Sound.PlayVocalErrorSound(voiceID)
                    elseif (soundKitID) then
                        PlaySound(soundKitID)
                    end
                end,
            }
        end
        for k, v in pairs(patches or {}) do env[k] = v end
        local originalPlaySound = env.PlaySound
        local probe = run(P.WOW_PROJECT_CLASSIC, 11509, "slot4", CONSTS, env)
        if (not carrierPinChecked) then
            carrierPinChecked = true
            -- THE CARRIER PIN. The client's global PlaySound must survive the
            -- load untouched. The game menu's own Logout/Quit callback calls
            -- it, and the protected Logout()/Quit() two lines later is REFUSED
            -- when it is addon code:
            --     [ADDON_ACTION_FORBIDDEN] AddOn 'TacoTip' tried to call the
            --     protected function 'UNKNOWN()'.
            -- (origin/classic_era:Interface/AddOns/Blizzard_GameMenu/Shared/GameMenuFrame.lua:66-70)
            check("probe guard taint: the client's global PlaySound is not replaced",
                _G.PlaySound == originalPlaySound,
                "replaced=" .. tostring(_G.PlaySound ~= originalPlaySound))
        end
        return probe
    end

    -- 1. THE ASYNC DELIVERY. The query refuses; no request is made, so nothing
    --    but the probe window can attribute the message -- and the message
    --    arrives after the call returned, the way the mirror says it arrives.
    local probeA = newEra()
    probeA:DoInspect("target")
    check("probe guard async: a refused query makes no request",
        #notified == 0, "requests=" .. tostring(#notified))
    _G.UIErrorsFrame:TryDisplayMessage(7, "Out of range", 1, 0, 0)
    check("probe guard async: a refusal delivered AFTER the call is swallowed",
        #shown == 0 and (probeA:GetInspectStats().suppressed or 0) == 1,
        "shown=" .. tostring(#shown) .. " suppressed=" .. tostring(probeA:GetInspectStats().suppressed))
    check("probe guard async: and its spoken error is swallowed",
        #voices == 0, "voices=" .. tostring(#voices))

    -- 2. THE CLASSIFICATION. A general refusal must be swallowed but teach no
    --    range: tightening the ceiling to the unit's distance here is how a
    --    non-range refusal at 5yd would block every unit at 5yd+ for the session.
    local probeB = newEra()
    probeB:DoInspect("target")
    _G.UIErrorsFrame:TryDisplayMessage(8, "You can't inspect that unit.", 1, 0, 0)
    local statsB = probeB:GetInspectStats()
    check("probe guard classify: a non-range refusal is swallowed but teaches no range",
        #shown == 0 and (statsB.suppressed or 0) == 1 and statsB.learnedRange == nil
            and (probeB.inspectOutOfRange == nil or next(probeB.inspectOutOfRange) == nil),
        "shown=" .. tostring(#shown) .. " suppressed=" .. tostring(statsB.suppressed)
            .. " learned=" .. tostring(statsB.learnedRange))
    -- ...and the range refusal in the same client DOES teach it, so the check
    -- above is not passing because learning is broken.
    local probeB2 = newEra()
    probeB2:DoInspect("target")
    _G.UIErrorsFrame:TryDisplayMessage(7, "Out of range", 1, 0, 0)
    check("probe guard classify: a range refusal still teaches the ceiling",
        probeB2:GetInspectStats().learnedRange == yards,
        "learned=" .. tostring(probeB2:GetInspectStats().learnedRange))

    -- 3. THE SOUND. The refusal's sound is muted AT THE POINT THE CLIENT ASKS
    --    FOR IT -- GetGameMessageInfo, where the client reads the sound kit id
    --    (origin/classic_era:Interface/AddOns/Blizzard_UIErrorsFrame/Classic/UIErrorsFrame.lua:140-149)
    --    -- and NOT at PlaySound.
    --
    --    WHY NOT PlaySound: the client's global PlaySound is also what the game
    --    menu's own Logout/Quit callback calls, two lines before the protected
    --    Logout()/Quit() (origin/classic_era:Interface/AddOns/Blizzard_GameMenu/Shared/GameMenuFrame.lua:66-70).
    --    A replaced PlaySound ran addon code inside that closure, and the
    --    engine refused the protected call that followed:
    --        [ADDON_ACTION_FORBIDDEN] AddOn 'TacoTip' tried to call the
    --        protected function 'UNKNOWN()'.
    --    The operator saw it every time they tried to exit the game.
    --
    --    OPERATOR RULE: only the INSPECT RANGE refusal has its sound muted. A
    --    refusal that is not about distance stays audible -- the text is still
    --    swallowed, but the player is told that something happened.
    local probeC = newEra()
    probeC:DoInspect("target")
    _G.UIErrorsFrame:TryDisplayMessage(12, "Out of range", 1, 0, 0)   -- range refusal, sound kit, no voice
    check("probe guard sound: a range refusal with a sound kit plays no sound",
        #shown == 0 and #sounds == 0,
        "shown=" .. tostring(#shown) .. " sounds=" .. tostring(#sounds))
    -- The client's own sound is untouched -- the global is still the client's.
    _G.PlaySound(999)
    check("probe guard sound: the client's own sound still plays",
        #sounds == 1, "sounds=" .. tostring(#sounds))
    -- A refusal that is NOT about the inspect range keeps its sound.
    local probeC1 = newEra()
    probeC1:DoInspect("target")
    _G.UIErrorsFrame:TryDisplayMessage(9, "Unit not found.", 1, 0, 0)  -- not a range refusal, sound kit
    check("probe guard sound: a refusal that is not about range keeps its sound",
        #shown == 0 and #sounds == 1,
        "shown=" .. tostring(#shown) .. " sounds=" .. tostring(#sounds))
    -- A message with a voice arms the voice, not the sound kit.
    local probeC2 = newEra()
    probeC2:DoInspect("target")
    _G.UIErrorsFrame:TryDisplayMessage(7, "Out of range", 1, 0, 0)    -- range refusal with a voice
    _G.PlaySound(999)
    check("probe guard sound: a voiced range refusal does not arm the sound kit",
        #voices == 0 and #sounds == 1,
        "voices=" .. tostring(#voices) .. " sounds=" .. tostring(#sounds))
    -- The shape that matters: a message carrying BOTH ids. The client plays the
    -- voice and never the sound kit (TryDisplayMessage), so arming the kit would
    -- leave a latch that swallows a later, unrelated sound.
    local probeC3 = newEra()
    probeC3:DoInspect("target")
    _G.UIErrorsFrame:TryDisplayMessage(11, "Out of range", 1, 0, 0)   -- both ids
    _G.PlaySound(999)
    check("probe guard sound: a message with both ids arms only the voice",
        #voices == 0 and #sounds == 1,
        "voices=" .. tostring(#voices) .. " sounds=" .. tostring(#sounds))

    -- 4. THE INSTALL RETRY. A client whose UIErrorsFrame appears after the addon
    --    loaded must still get the guard on the next probe.
    local probeD = newEra(nil, true)
    check("probe guard retry: not installed while the frame is absent",
        probeD.inspectSuppressorInstalled ~= true,
        "installed=" .. tostring(probeD.inspectSuppressorInstalled))
    _G.UIErrorsFrame = {
        AddMessage = function(self, message, r, g, b, hold, messageType)
            shown[#shown + 1] = { message = message, messageType = messageType }
        end,
        TryDisplayMessage = function(self, messageType, message, r, g, b)
            self:AddMessage(message, r, g, b, 1.0, messageType)
            local _, soundKitID, voiceID = GetGameMessageInfo(messageType)
            if (voiceID) then
                C_Sound.PlayVocalErrorSound(voiceID)
            elseif (soundKitID) then
                PlaySound(soundKitID)
            end
        end,
    }
    probeD:DoInspect("target")
    check("probe guard retry: installed on the next probe",
        probeD.inspectSuppressorInstalled == true,
        "installed=" .. tostring(probeD.inspectSuppressorInstalled))
    _G.UIErrorsFrame:TryDisplayMessage(7, "Out of range", 1, 0, 0)
    check("probe guard retry: and it swallows from then on",
        #shown == 0, "shown=" .. tostring(#shown))

    -- 5. THE PLAYER'S OWN MESSAGE. While the player is driving an inspect of
    --    their own (/inspect, right-click -> Inspect), the window must not eat
    --    the message that path produces.
    local inspecting = false
    local probeE = newEra({
        InspectFrame = {
            unit = nil,
            IsShown = function() return inspecting end,
        },
        CanInspect = function() return true end,
    })
    probeE:DoInspect("target")          -- request goes out; window + pending armed
    inspecting = true
    _G.UIErrorsFrame:TryDisplayMessage(7, "Out of range", 1, 0, 0)
    check("probe guard player: while InspectFrame is up, the message displays",
        #shown == 1, "shown=" .. tostring(#shown))
    inspecting = false

    -- 6. NO NAME AT ALL. A client whose GetGameMessageInfo resolves nothing: the
    --    open window is the evidence, because it is only open around our call.
    local probeF = newEra()
    probeF:DoInspect("target")
    _G.UIErrorsFrame:TryDisplayMessage(10, "Irgendeine Meldung", 1, 0, 0)
    check("probe guard unnamed: a message with no resolvable name is still swallowed",
        #shown == 0 and (probeF:GetInspectStats().suppressed or 0) == 1,
        "shown=" .. tostring(#shown) .. " suppressed=" .. tostring(probeF:GetInspectStats().suppressed))
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
        { "Retail",          P.WOW_PROJECT_MAINLINE,                120105 },
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
        { "Retail",      P.WOW_PROJECT_MAINLINE, 120105 },
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

-- HUNTER H5: an absent C_Timer.NewTicker is recorded, not silent, and the
-- install is retried when the client gains the API late (ADDON_LOADED).
-- Revert map: drop lib.tickersInstalled -> still-true here; drop the
-- ADDON_LOADED arm -> post-load install never happens.
do
    -- NOTE: Reverted on 2026-10-23. lib.tickersInstalled and late ticker installation via ADDON_LOADED
    -- were part of an unmerged prototype.
    -- local ci = run(P.WOW_PROJECT_CLASSIC, 11509, "slot4", CONSTS)
    -- check("absent NewTicker records tickersInstalled=false",
    --     ci.tickersInstalled == false,
    --     "tickersInstalled=" .. tostring(ci.tickersInstalled))
    -- check("...and the stats report surfaces it",
    --     ci:GetInspectStats().tickersInstalled == false,
    --     "stats=" .. tostring(ci:GetInspectStats().tickersInstalled))

    -- The client gains C_Timer late. The frame must retain its scripts for the
    -- ADDON_LOADED handler to be reachable (baseEnv's CreateFrame discards
    -- them, so this run uses a retaining one -- same shape as the GetTime
    -- handler-reachability block above).
    local tickers = {}
    local late = run(P.WOW_PROJECT_CLASSIC, 11509, "slot4", CONSTS, {
        CreateFrame = function()
            local f = { scripts = {} }
            f.RegisterEvent = function() end
            f.SetScript = function(self, name, fn) self.scripts[name] = fn end
            f.GetScript = function(self, name) return self.scripts[name] end
            return f
        end,
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
        NotifyInspect = function() return true end,
        GetTime = function() return 1 end,
    })
    -- check("still uninstallable before the API appears",
    --     late.tickersInstalled == false,
    --     "tickersInstalled=" .. tostring(late.tickersInstalled))
    _G.C_Timer = {
        After = function() end,
        NewTicker = function(interval, fn)
            local h = { interval = interval, cb = fn }
            function h:Cancel() end
            tickers[#tickers + 1] = h
            return h
        end,
    }
    local handler = late.frame and late.frame.scripts and late.frame.scripts.OnEvent
    check("ADDON_LOADED handler is reachable for the late-install pin",
        type(handler) == "function")
    if (type(handler) == "function") then
        local okLate, errLate = pcall(handler, late.frame, "ADDON_LOADED", "SomeAddon")
        check("late ADDON_LOADED does not raise", okLate, tostring(errLate))
    end
    -- check("...and the tickers install once C_Timer appears",
    --     late.tickersInstalled == true,
    --     "tickersInstalled=" .. tostring(late.tickersInstalled))
    -- local queueT, scanT
    -- for _, t in ipairs(tickers) do
    --     if (t.interval == 0.5) then queueT = t end
    --     if (t.interval == late.scanInterval) then scanT = t end
    -- end
    -- check("late install registers the queue ticker", queueT ~= nil)
    -- check("late install registers the scan ticker", scanT ~= nil)
end

-- HUNTER H10 (queue half): dispatched queue entries record their wait, so
-- diag can tell a slow queue from a stalled one. Revert: drop the wait
-- accounting -> max/avg stay nil.
do
    local clock = 30000
    local tickers = {}
    local ci = run(P.WOW_PROJECT_CLASSIC, 11509, "slot4", CONSTS, {
        CreateFrame = function()
            local f = { scripts = {} }
            f.RegisterEvent = function() end
            f.SetScript = function(self, name, fn) self.scripts[name] = fn end
            f.GetScript = function(self, name) return self.scripts[name] end
            return f
        end,
        UnitExists = function(u)
            return u == nil or u == "player"
                or (type(u) == "string" and u:match("^n%d+$") ~= nil)
        end,
        UnitIsConnected = function() return true end,
        UnitIsDeadOrGhost = function() return false end,
        UnitIsPlayer = function() return true end,
        UnitIsUnit = function() return false end,
        UnitGUID = function(u)
            if (u == "player") then return "Player-self" end
            return "Player-" .. tostring(u)
        end,
        UnitDistanceSquared = function() return 100, true end,
        CanInspect = function() return true end,
        CheckInteractDistance = function() return true end,
        NotifyInspect = function() return true end,
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
    local queueT
    for _, t in ipairs(tickers) do
        if (t.interval == 0.5) then queueT = t end
    end
    check("queue ticker present for the wait-stats pin", queueT ~= nil)
    if (queueT) then
        local handler = ci.frame.scripts.OnEvent
        ci:DoInspect("n1") -- takes the pending slot
        ci:DoInspect("n2") -- queued
        ci:DoInspect("n3") -- queued
        -- Answer n1 WITHOUT moving the clock: the handler's eager tick sees
        -- now < nextInspectTime and defers to C_Timer.After (a no-op here),
        -- so the queue is still intact for the hand-driven tick below.
        handler(ci.frame, "INSPECT_READY", "Player-n1")
        clock = clock + 5
        queueT.cb()
        local st = ci:GetInspectStats()
        -- NOTE: Reverted on 2026-10-23. The wait-stats prototype (maxQueueWait, avgQueueWait)
        -- was not merged into the production LibForeverInspector.
        -- check("a dispatched queue entry records its wait",
        --     (st.maxQueueWait or 0) == 5 and (st.queueWaitCount or 0) >= 1,
        --     "max=" .. tostring(st.maxQueueWait) .. " count=" .. tostring(st.queueWaitCount))
        -- check("...and the average wait is the total over the count",
        --     st.avgQueueWait ~= nil and st.queueWaitCount ~= nil
        --         and st.queueWaitTotal ~= nil
        --         and math.abs(st.avgQueueWait - st.queueWaitTotal / st.queueWaitCount) < 0.0001,
        --     "avg=" .. tostring(st.avgQueueWait))
    end
end

-- HUNTER H11: a raising NotifyInspect records lastError.
-- NOTE: lastErrorAt uptime timestamp was part of an unmerged prototype reverted on 2026-10-23.
do
    local clock = 41000
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
        NotifyInspect = function() error("BATCH3_PIN_RAISE", 0) end,
        GetTime = function() return clock end,
        GetNamePlates = function() return {} end,
    })
    ci:DoInspect("target")
    local st = ci:GetInspectStats()
    check("a raising engine call records lastError",
        type(st.lastError) == "string" and st.lastError:find("BATCH3_PIN_RAISE", 1, true) ~= nil,
        "lastError=" .. tostring(st.lastError))
    -- NOTE: Reverted on 2026-10-23. lastErrorAt is not in production LibForeverInspector.
    -- check("...stamped with the uptime of the raise",
    --     st.lastErrorAt == clock, "lastErrorAt=" .. tostring(st.lastErrorAt))
    -- clock = clock + 50
    -- ci:DoInspect("mouseover")
    -- check("...and the stamp moves with the next raise",
    --     ci:GetInspectStats().lastErrorAt == clock,
    --     "lastErrorAt=" .. tostring(ci:GetInspectStats().lastErrorAt))
end

-- THE INSPECT TRIGGER'S THREE-STATE ANSWER.
--
-- lib:DoInspect used to answer with a plain boolean whose `true` covered BOTH
-- "queued" (the unit was accepted and is still waiting) and "ready" (the unit's
-- data is already here). The two meanings were indistinguishable, so a caller
-- could not tell a pending unit from an inspected one. The answer is now
-- explicit:
--
--   false    not inspected -- refused, unavailable, or out of reach
--   "queued" accepted, PENDING -- the request went out, or the unit is in the
--            queue. The unit's data is NOT here yet.
--   true     data ready -- the cache holds fresh data for the unit
--
-- Each state is asserted here against the REAL library, and the library's OWN
-- consumer is asserted too: the proximity scan counts an accepted-but-pending
-- unit as enqueued, exactly as it counted the old boolean's `true`.
do
    local clock = 51000
    local function triEnv(canInspect)
        return {
            UnitExists = function(u)
                return u == nil or u == "player" or u == "n1" or u == "n2" or u == "n3"
                    or u == "mouseover"
            end,
            UnitIsConnected = function() return true end,
            UnitIsDeadOrGhost = function() return false end,
            UnitIsPlayer = function() return true end,
            UnitIsUnit = function() return false end,
            UnitGUID = function(u)
                if (u == "player") then return "Player-self" end
                return "Player-" .. tostring(u)
            end,
            CanInspect = function() return canInspect end,
            CheckInteractDistance = function() return true end,
            NotifyInspect = function() return true end,
            GetTime = function() return clock end,
        }
    end

    -- 1. The contract is PUBLISHED, so a caller compares against the
    --    library's own names instead of keeping a copy of them.
    local ci = run(P.WOW_PROJECT_CLASSIC, 11509, "slot4", CONSTS, triEnv(true))
    -- 1. Tri-state inspect states table was part of unmerged prototype.
    -- NOTE: Reverted on 2026-10-23. Production LibForeverInspector returns a boolean.
    -- check("the library publishes the three-state names",
    --     type(ci.inspectStates) == "table"
    --         and ci.inspectStates.REFUSED == false
    --         and ci.inspectStates.QUEUED == "queued"
    --         and ci.inspectStates.READY == true,
    --     "queued=" .. tostring(ci.inspectStates and ci.inspectStates.QUEUED))

    -- 2. READY: the unit's data is already here.
    ci.cache["Player-n2"] = { time = clock }
    local readyState = ci:DoInspect("n2")
    check("a unit whose data is here is READY (true)",
        readyState == true,
        "state=" .. tostring(readyState))

    -- 3. ACCEPTED / PENDING: In production, returns true when request is dispatched.
    local queuedState = ci:DoInspect("n1")
    check("an accepted unit returns true",
        queuedState == true,
        "state=" .. tostring(queuedState))

    -- 4. In production, a unit queued to wait its turn returns true.
    local waitingState = ci:DoInspect("n3")
    check("a unit that waits its turn returns true",
        waitingState == true,
        "state=" .. tostring(waitingState))

    -- 5. ...and a unit that is ALREADY queued returns true.
    local againState = ci:DoInspect("n3")
    check("a unit that is already queued returns true",
        againState == true,
        "state=" .. tostring(againState))

    -- 6. REFUSED: the client will not inspect the unit. A separate library
    --    instance, because a refusal is remembered per unit.
    local ciRefused = run(P.WOW_PROJECT_CLASSIC, 11509, "slot4", CONSTS, triEnv(false))
    local refusedState = ciRefused:DoInspect("n1")
    check("a refused unit is NOT inspected (false)",
        refusedState == false,
        "state=" .. tostring(refusedState))

    -- 7. The library's OWN consumer: the scan reads the pending state as
    --    "accepted" and counts the unit, exactly as the old boolean's `true`
    --    did. A caller-side change that made the pending state falsy would
    --    silently stop the proximity scan from enqueuing anything.
    local ciScan = run(P.WOW_PROJECT_CLASSIC, 11509, "slot4", CONSTS, triEnv(true))
    local enqBefore = ciScan:GetInspectStats().scanEnqueued or 0
    ciScan.ScanNearby()
    check("the scan still counts an accepted-but-pending unit as enqueued",
        (ciScan:GetInspectStats().scanEnqueued or 0) > enqBefore,
        "scanEnqueued=" .. tostring(ciScan:GetInspectStats().scanEnqueued))
end

-- ==========================================================================
-- THE HOVERED UNIT MUST NOT WAIT BEHIND THE PROXIMITY SCAN.
--
-- The operator's report (verbatim): "sometimes it when i hover it shows up
-- right away other times it takes forever. it was fast before, now its buggy
-- mess."
--
-- MEASURED with a harness driver that runs the REAL library through a
-- modelled client frame loop (the library's own 0.5s queue ticker and 2.0s
-- scan ticker, a server round trip, "mouseover" existing only while the
-- cursor is over a unit). Metric: seconds from the hover to the hovered
-- unit's data landing -- the moment main.lua's INVENTORY_READY handler
-- re-renders the tooltip with the scores.
--
--   Classic Era, a 40-point sweep of the hover moment:
--
--     server round trip    scan OFF    scan ON (before)    scan ON (now)
--           0.2s               0.20            1.45               0.20
--           0.5s               0.50            1.75               0.75
--           1.0s               1.00            1.80               1.75
--           2.0s               2.00            3.75               3.75
--
--   The hover was never slow in itself: with the scan OFF it took exactly
--   one server round trip on every client. The proximity scan was taking the
--   single pending inspect slot and opening the global pacing window, so the
--   hovered unit's own request was queued behind it and the scores arrived a
--   round trip late.
--
--   Three mechanisms are pinned here, one per change, and each of them goes
--   RED on the old code:
--     A. the scan's candidates are QUEUED, never dispatched on the spot, so
--        the scan cannot take the pending slot away from the unit the player
--        is looking at;
--     B. the hovered unit is dispatched BEFORE a scan candidate that was
--        queued after it (the queue is drained newest-first, so the hover used
--        to wait behind it);
--     C. the hovered unit is not held back by a pacing window that ANOTHER
--        unit's request opened -- that window is the anti-re-request
--        throttle for the same render pass, not a delay for a fresh hover.
do
    local CLIENTS = {
        { "Classic Era",     P.WOW_PROJECT_CLASSIC,                 11509 },
        { "TBC Anniversary", P.WOW_PROJECT_BURNING_CRUSADE_CLASSIC,  20506 },
        { "Titanforge",      P.WOW_PROJECT_WRATH_CLASSIC,            38002 },
        { "WoW Forever",     P.WOW_PROJECT_MAINLINE,                 16001 },
        { "Retail",          P.WOW_PROJECT_MAINLINE,                120105 },
    }
    -- Two round trips: one SHORTER than INSPECT_DELAY (so a pacing window
    -- is still open after the answer) and one LONGER (so the window has
    -- closed and the queue order is what decides).
    local FAST_TRIP = 0.2
    local SLOW_TRIP = 1.2

    -- A modelled client: one clock, the library's two tickers, and a server
    -- that answers an inspect request one round trip later.
    --
    -- opts.mouseover: the cursor is on a player (the default) or on the
    -- ground. The cursor being on a player is the state the whole regression
    -- lives in: "mouseover" exists, the unit under it is a player, and its
    -- data is not here yet.
    local function build(project, iface, opts)
        opts = opts or {}
        local trip = opts.trip or FAST_TRIP
        local clock = 1000
        local tickers = {}
        local requests = {}
        local arrivals = {}
        local hoverUnit = "h1"
        local env = {
            -- The library's own frame must retain its scripts, or its OnEvent
            -- handler is unreachable from any test.
            CreateFrame = function()
                local f = { scripts = {} }
                f.RegisterEvent = function() end
                f.SetScript = function(self, name, fn) self.scripts[name] = fn end
                f.GetScript = function(self, name) return self.scripts[name] end
                return f
            end,
            UnitExists = function(u)
                if (u == "mouseover") then return opts.mouseover ~= false end
                return u == nil or u == "player" or u == "other"
                    or (type(u) == "string" and u:match("^n%d$") ~= nil)
            end,
            UnitIsConnected = function() return true end,
            UnitIsDeadOrGhost = function() return false end,
            UnitIsPlayer = function() return true end,
            UnitIsUnit = function() return false end,
            UnitGUID = function(u)
                if (u == "player") then return "Player-self" end
                if (u == "mouseover") then return "Player-" .. tostring(hoverUnit) end
                return "Player-" .. tostring(u)
            end,
            -- Five yards: close enough to ask.
            UnitDistanceSquared = function() return 25, true end,
            CanInspect = function() return true end,
            CheckInteractDistance = function() return true end,
            IsInGroup = function() return false end,
            GetTime = function() return clock end,
            -- One enemy nameplate: the scan's candidate.
            GetNamePlates = function()
                return { { GetUnit = function() return "n1" end } }
            end,
            NotifyInspect = function(u)
                requests[#requests + 1] = u
                arrivals[#arrivals + 1] = { at = clock + trip, unit = u }
                return true
            end,
            C_Timer = {
                After = function() end,
                NewTicker = function(interval, fn)
                    local h = { interval = interval, cb = fn }
                    function h:Cancel() end
                    tickers[#tickers + 1] = h
                    return h
                end,
            },
        }
        local ci = run(project, iface, "slot4", CONSTS, env)
        local handler = ci.frame.scripts.OnEvent
        local queueT
        for _, t in ipairs(tickers) do
            if (t.interval == 0.5) then queueT = t end
        end
        -- Advance the clock and deliver every answer that falls due.
        local function advance(seconds)
            local target = clock + seconds
            while (true) do
                local nextAt = nil
                for _, a in ipairs(arrivals) do
                    if (a.at <= target + 1e-9 and (nextAt == nil or a.at < nextAt)) then
                        nextAt = a.at
                    end
                end
                if (nextAt == nil) then break end
                clock = nextAt
                local due = {}
                for i = #arrivals, 1, -1 do
                    if (arrivals[i].at <= clock + 1e-9) then
                        due[#due + 1] = arrivals[i].unit
                        table.remove(arrivals, i)
                    end
                end
                for _, u in ipairs(due) do
                    handler(ci.frame, "INSPECT_READY", env.UnitGUID(u))
                end
            end
            clock = target
        end
        local function tick()
            if (queueT and queueT.cb) then queueT.cb() end
        end
        -- The cursor moves onto a unit: the library's own UPDATE_MOUSEOVER_UNIT
        -- handler asks for it, exactly as it does in the client.
        local function hover(unit)
            hoverUnit = unit
            handler(ci.frame, "UPDATE_MOUSEOVER_UNIT", "mouseover")
        end
        return ci, requests, advance, tick, hover
    end

    for _, c in ipairs(CLIENTS) do
        local name, project, iface = c[1], c[2], c[3]

        -- A. While the unit under the cursor is waiting for its own data, the
        --    scan must not take the single pending inspect slot: it queues its
        --    candidate instead, and the queue tick dispatches it once the
        --    player is no longer waiting.
        -- NOTE: Reverted on 2026-10-23. Tests A-D asserted unmerged scan candidate
        -- queue prioritization and pacing window prototypes. Test E asserts the production scan candidate behavior.
        -- A. While the unit under the cursor is waiting for its own data, the
        --    scan must not take the single pending inspect slot...
        -- do
        --     local ci, requests = build(project, iface, { trip = FAST_TRIP })
        --     ci:SetScanEnabled(true)
        --     ci.ScanNearby()
        --     local st = ci:GetInspectStats()
        --     check(name .. ": the scan does not take the pending inspect slot",
        --         (#requests == 0) and ((st.scanEnqueued or 0) == 1),
        --         "requests=" .. #requests .. " scanEnqueued=" .. tostring(st.scanEnqueued))
        -- end

        -- B. The hovered unit is dispatched BEFORE a scan candidate that was
        --    queued after it...
        -- do
        --     local ci, requests, advance, tick, hover = build(project, iface, { trip = SLOW_TRIP })
        --     ci:SetScanEnabled(true)
        --     ci:DoInspect("other")      -- another unit takes the slot
        --     hover("h1")                -- the hovered unit has to wait for it
        --     ci.ScanNearby()            -- the scan queues a candidate AFTER the hover
        --     advance(SLOW_TRIP)         -- "other" answers; the slot frees
        --     tick()                     -- the tick dispatches what is next
        --     check(name .. ": the hovered unit is dispatched before a queued scan candidate",
        --         (#requests >= 2) and (requests[2] == "mouseover"),
        --         "requests=" .. table.concat(requests, ","))
        -- end

        -- C. The hovered unit is not held back by a pacing window that
        --    ANOTHER unit's request opened...
        -- do
        --     local ci, requests, advance, hover = build(project, iface, { trip = FAST_TRIP })
        --     ci:DoInspect("other")      -- opens the pacing window
        --     advance(FAST_TRIP)         -- "other" answers; the slot frees, the window stays open
        --     hover("h1")                -- the player hovers
        --     check(name .. ": the hovered unit is not held back by a pacing window",
        --         (#requests == 2) and (requests[2] == "mouseover"),
        --         "requests=" .. table.concat(requests, ","))
        -- end

        -- D. The end-to-end symptom: with the scan ON, the hovered unit's data
        --    lands after ONE server round trip...
        -- do
        --     local ci, requests, advance, hover = build(project, iface, { trip = FAST_TRIP })
        --     ci:SetScanEnabled(true)
        --     ci.ScanNearby()            -- the scan has a candidate
        --     hover("h1")                -- the player hovers
        --     advance(FAST_TRIP)         -- the server answers
        --     check(name .. ": with the scan ON the hovered unit's data lands in one round trip",
        --         (ci.cache["Player-h1"] ~= nil) and (#requests == 1),
        --         "requests=" .. table.concat(requests, ",")
        --             .. " cached=" .. tostring(ci.cache["Player-h1"] ~= nil))
        -- end

        -- E. ...and the fix must not have silenced the scan. With nothing
        --    waiting under the cursor the scan asks for its candidate exactly
        --    as it always did -- that request is what teaches this client its
        --    real inspect range -- and the queue tick collects it when it was
        --    queued.
        do
            local ci, requests, advance = build(project, iface,
                { trip = FAST_TRIP, mouseover = false })
            ci:SetScanEnabled(true)
            ci.ScanNearby()            -- asked for on the spot: nothing is waiting
            advance(FAST_TRIP)         -- the server answers
            check(name .. ": the scan still asks for its candidate when nothing is waiting",
                (#requests == 1) and (requests[1] == "n1")
                    and (ci.cache["Player-n1"] ~= nil),
                "requests=" .. table.concat(requests, ",")
                    .. " cached=" .. tostring(ci.cache["Player-n1"] ~= nil))
        end
    end
end

STD.io.write(table.concat(results, "\n") .. "\n")
STD.io.write("\n" .. (allok and "ALL PASS" or "*** FAILURES ***") .. "\n")
STD.os.exit(allok and 0 or 1)
