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

local STD = { os = os, string = string, pairs = pairs, ipairs = ipairs, type = type,
    pcall = pcall, tonumber = tonumber, tostring = tostring, select = select,
    rawget = rawget, rawset = rawset, setmetatable = setmetatable,
    getmetatable = getmetatable, unpack = unpack, assert = assert, error = error,
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
    _G.InCombatLockdown = function() return false end
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
local function run(projectId, iface, layout, projectConsts)
    for k in STD.pairs(REALG) do REALG[k] = nil end
    baseEnv()
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

STD.io.write(table.concat(results, "\n") .. "\n")
STD.io.write("\n" .. (allok and "ALL PASS" or "*** FAILURES ***") .. "\n")
STD.os.exit(allok and 0 or 1)
