-- Simulates each supported client and asserts the resolved family + gear bracket.
-- Runs the REAL LibForeverInspector; only the host environment is mocked.

local LIB = (os.getenv("TACOTIP_TEST_ROOT") or ".") .. "/Libs/"

local results, allok = {}, true
-- NB: in Lua 5.1 assigning `_G = {}` only rebinds the variable, it does not
-- replace the environment table every other global lookup resolves through.
-- Wipe the real table instead.
local REALG = _G
-- capture the stdlib before anything is wiped
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
local function bracket(ci)
    if ci:IsClassic() then return 200 end
    if ci:IsTBC() then return 400 end
    if ci:IsForever() then return 200 end
    return 1000
end

-- The five real targets, each tested under BOTH plausible GetBuildInfo layouts,
-- so the result does not depend on the unverified Classic slot-4 question.
for _, t in ipairs({
    { n = "Classic Era 11509",  p = P.WOW_PROJECT_CLASSIC,                 i = 11509,  f = "classicEra",  b = 200 },
    { n = "TBC Anniversary",    p = P.WOW_PROJECT_BURNING_CRUSADE_CLASSIC, i = 20506,  f = "tbc",         b = 400 },
    { n = "Titanforge 38002",   p = P.WOW_PROJECT_WRATH_CLASSIC,           i = 38002,  f = "titanforge",  b = 1000 },
    { n = "WoW Forever 16001",  p = P.WOW_PROJECT_MAINLINE,               i = 16001,  f = "forever",     b = 200 },
    { n = "Retail 120100",      p = P.WOW_PROJECT_MAINLINE,               i = 120100, f = "retail",      b = 1000 },
}) do
    for _, layout in ipairs({ "slot4", "slot7" }) do
        local ci = run(t.p, t.i, layout, CONSTS)
        local got = ci.family
        local b = bracket(ci)
        check(string.format("%s [%s layout]", t.n, layout),
            (got == t.f and b == t.b and not ci:IsUnknown()),
            string.format("family=%-11s bracket=%-5d unknown=%s", got, b, tostring(ci:IsUnknown())))
    end
end

-- WoW Forever with WOW_PROJECT_ID unset (engine-defined on camelot) must still
-- resolve via the interface band, and must NOT be classified as retail.
do
    local ci = run(nil, 16001, "slot4", CONSTS)
    check("Forever, WOW_PROJECT_ID nil",
        (ci.family == "forever" and not ci:IsRetail() and not ci:IsUnknown()),
        string.format("family=%s isRetail=%s", ci.family, tostring(ci:IsRetail())))
end

-- The open question: if Forever ever reports WOW_PROJECT_MAINLINE, isRetail and
-- isForever must still not both be true.
do
    local ci = run(P.WOW_PROJECT_MAINLINE, 16001, "slot4", CONSTS)
    check("Forever reporting MAINLINE is unambiguous",
        (ci.family == "forever" and not ci:IsRetail()),
        string.format("family=%s isRetail=%s isForever=%s", ci.family, tostring(ci:IsRetail()), tostring(ci:IsForever())))
end

-- Mutual exclusivity across all five.
do
    local _, _, _, _, _ = nil, nil, nil, nil, nil
    for _, t in ipairs({
        { p = P.WOW_PROJECT_CLASSIC, i = 11509 }, { p = P.WOW_PROJECT_BURNING_CRUSADE_CLASSIC, i = 20506 },
        { p = P.WOW_PROJECT_WRATH_CLASSIC, i = 38002 }, { p = P.WOW_PROJECT_MAINLINE, i = 16001 },
        { p = P.WOW_PROJECT_MAINLINE, i = 120100 },
    }) do
        local ci = run(t.p, t.i, "slot4", CONSTS)
        local n = 0
        for _, f in ipairs({ "IsClassic", "IsTBC", "IsWotlk", "IsForever", "IsRetail" }) do
            if ci[f](ci) then n = n + 1 end
        end
        check(string.format("exactly one flag set (iface %d)", t.i), n == 1, "flags_set=" .. n)
    end
end

-- Unrecognised clients must be reported unknown, not silently defaulted.
do
    for _, t in ipairs({ { P.WOW_PROJECT_CATACLYSM_CLASSIC, 40402, "Cata" },
                         { P.WOW_PROJECT_MISTS_CLASSIC, 50504, "Mists" } }) do
        local ci = run(t[1], t[2], "slot4", CONSTS)
        check(string.format("%s reports IsUnknown", t[3]),
            ci:IsUnknown() and ci.family == "unknown",
            "family=" .. ci.family)
    end
end

-- Backward-compatible alias still resolves, now with a minor version.
do
    local ci = run(P.WOW_PROJECT_CLASSIC, 11509, "slot4", CONSTS)
    local alias, minor = LibStub("LibClassicInspector")
    check("LibClassicInspector alias + minor",
        (alias == ci and minor == select(2, LibStub("LibForeverInspector")) and minor > 0),
        "same_table=" .. tostring(alias == ci) .. " minor=" .. tostring(minor))
end

STD.io.write(table.concat(results, "\n") .. "\n")
STD.io.write("\n" .. (allok and "ALL PASS" or "*** FAILURES ***") .. "\n")
STD.os.exit(allok and 0 or 1)
