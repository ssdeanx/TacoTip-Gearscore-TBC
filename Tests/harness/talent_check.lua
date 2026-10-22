-- Verifies the ported static talent table (from the working LibClassicInspector) resolves
-- real icons per expansion, without loading the whole addon.
-- Usage: lua5.1 talent_check.lua <projectId> <iface> <label>
-- Verifies the ported static talent table resolves icons the same way the
-- working LibClassicInspector does, without loading the whole addon.
local _hp = ((arg and arg[0]) or "Tests/harness/talent_check.lua"):gsub("\\", "/")
local _hd = _hp:match("^(.*)/[^/]*$") or "."
local D = dofile(_hd .. "/root.lua") .. "/"
local MOCKC = dofile(_hd .. "/mock_contract.lua")
local PROJ = tonumber(arg[1]) or 2
local IFACE = tonumber(arg[2]) or 11509
local LABEL = arg[3] or "CLASSIC_ERA"
MOCKC.setFamily(MOCKC.normaliseFamily(LABEL))
local REALG = _G
local out = print

REALG.CreateFrame = function()
    return {
        SetScript = function() end,
        RegisterEvent = function() end,
        UnregisterEvent = function() end,
        IsShown = function() return false end,
        RegisterUnitEvent = function() end,
    }
end
REALG.GetBuildInfo = function() return "1.15.9", "1", "d", IFACE, "us", "rel" end
-- `securecall` -- the engine's taint-containment global, present on every
-- supported client (Blizzard captures it as a local the same way it captures
-- `forceinsecure`: Blizzard_FrameXML/SharedPetBattleTemplates.lua:5
-- `local securecall = securecall;`). The mock counts the calls that went
-- through it, so a taint pin can tell "addon code ran inside a Blizzard
-- frame's script chain" from "it ran contained".
REALG.securecall = function(fn, ...)
    REALG.__secureCalls = (REALG.__secureCalls or 0) + 1
    return fn(...)
end
REALG.WOW_PROJECT_MAINLINE = 1
REALG.WOW_PROJECT_CLASSIC = 2
-- The real global is WOW_PROJECT_BURNING_CRUSADE_CLASSIC; this mock used to
-- declare WOW_PROJECT_BC_CLASSIC, which exists in no Blizzard source.
REALG.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
REALG.WOW_PROJECT_WRATH_CLASSIC = 11
REALG.WOW_PROJECT_ID = PROJ
-- UnitClass publishes THREE values on the modern pair and TWO on the
-- Classic family. See Tests/harness/mock_contract.lua.
REALG.UnitClass = MOCKC.unitClassMock(function() return "WARRIOR", "WARRIOR" end)
REALG.UnitExists = function() return true end
REALG.UnitIsPlayer = function() return true end
REALG.UnitGUID = function() return "Player-1-0" end
REALG.wipe = table.wipe

for _, f in ipairs({
    "Libs/LibStub/LibStub.lua",
    "Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua",
    "Libs/LibDetours-1.0/LibDetours-1.0.lua",
    "Libs/LibForeverInspector/LibForeverInspector.lua",
}) do
    local ok, err = pcall(function() assert(loadfile(D .. f))("T") end)
    if not ok then
        out("LOAD FAIL " .. f .. ": " .. tostring(err))
        os.exit(1)
    end
end

local lib = LibStub("LibForeverInspector", true)
out("== " .. LABEL .. " (projectId=" .. PROJ .. ", iface=" .. IFACE .. ") family=" .. tostring(lib.family))
out("GetTalentInfoByClass= " .. type(lib.GetTalentInfoByClass))
out("GetNumTalentsByClass= " .. type(lib.GetNumTalentsByClass))

-- The mock-fidelity contract (proctor HI-12): the UnitClass mock must
-- publish the arity the CLIENT publishes on this family. This harness has no
-- pass/fail tally of its own, so a mismatch is reported and made fatal here
-- rather than printed among the informational lines.
do
    local want = MOCKC.expected("UnitClass", "mockArity")
    local got = MOCKC.measure(REALG.UnitClass, "player")
    if (got ~= want) then
        out("CONTRACT FAIL: UnitClass mock publishes " .. tostring(got)
            .. " values, the client publishes " .. tostring(want))
        os.exit(1)
    end
    out("mock contract: UnitClass publishes " .. tostring(want) .. " values, as the client does")
end

-- Spot-check a known record straight from the working table.
local probe = 26
while true do
    local n = lib.GetTalentInfoByClass(lib, "WARRIOR", 1, probe)
    if n or probe <= 1 then break end
    probe = probe - 1
end
local name, tex, tier, col, _, maxR, exc =
    lib.GetTalentInfoByClass(lib, "WARRIOR", 1, probe)
out(string.format("WARRIOR tab1 #%-2d     = %-18s tex=%s tier=%s col=%s maxR=%s exc=%s",
    probe, tostring(name), tostring(tex), tostring(tier), tostring(col), tostring(maxR), tostring(exc)))
out("numTalents WARRIOR 1 = " .. tostring(lib:GetNumTalentsByClass("WARRIOR", 1)))

-- Replay main.lua's getSpecializationIcon loop verbatim for a few classes.
for _, class in ipairs({ "WARRIOR", "MAGE", "ROGUE", "DRUID", "DEATHKNIGHT" }) do
    local best, bestTier = nil, -1
    for i = 1, 40 do
        local ok2, n2, tex2, ti2, _, _, _, exc2 =
            pcall(lib.GetTalentInfoByClass, lib, class, 1, i)
        if not ok2 then break end
        if n2 and tex2 then
            if exc2 then
                best, bestTier = tex2, math.huge
            elseif (ti2 or 0) >= bestTier then
                best, bestTier = tex2, ti2 or 0
            end
        end
    end
    out(string.format("icon %-12s tab1 = %s", class, tostring(best)))
end
