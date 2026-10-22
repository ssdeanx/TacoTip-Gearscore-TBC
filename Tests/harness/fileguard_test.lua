-- File-scope soft aborts: a missing library must stop the load with a stage
-- recorded, not raise past the guard.
--
-- main.lua is the last file in the toc and defines the mover at its very end,
-- so a file-scope raise aborts everything after it. The guards at the top of
-- main.lua therefore return early instead of asserting, leaving TT.LOAD_STAGE
-- behind for /tacotip diag. Likewise the library must survive a missing
-- GetBuildInfo by defaulting to family-unknown (which diag already reports)
-- instead of raising at file scope.
-- Usage: lua5.1 fileguard_test.lua (client-independent: no projectId/iface args)

local _hp = ((arg and arg[0]) or "Tests/harness/fileguard_test.lua"):gsub("\\", "/")
local _hd = _hp:match("^(.*)/[^/]*$") or "."
local ROOT = dofile(_hd .. "/root.lua") .. "/"
local LIB = ROOT .. "Libs/"

local results, allok = {}, true
local REALG = _G
local unpack = unpack or table.unpack

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
    next = next, xpcall = xpcallWithArgs,
    math = math, table = table, loadfile = loadfile, print = print, io = io }
local function check(name, cond, detail)
    results[#results + 1] = string.format("%-46s %-10s %s", name, cond and "PASS" or "FAIL", detail or "")
    if not cond then allok = false end
end

-- The mock-fidelity contract (proctor HI-12). See
-- Tests/harness/mock_contract.lua.
local MOCKC = dofile(_hd .. "/mock_contract.lua")
MOCKC.setFamily("retail")

-- Fresh sandbox per case. `withLibs` selects which libraries main.lua sees:
-- "none" (LibStub absent), "bare" (LibStub present, no libraries registered),
-- or "full" (both libraries registered).

-- The mock-fidelity contract (proctor HI-12). The mock must publish the
-- arity the CLIENT publishes, so the next drift fails the suite instead of
-- waiting for a human to read FrameXML. See Tests/harness/mock_contract.lua.
local function mainEnv(withLibs)
    for k in STD.pairs(REALG) do REALG[k] = nil end
    for k, v in STD.pairs(STD) do REALG[k] = v end
    REALG._G = REALG
    if (withLibs == "bare" or withLibs == "full") then
        local registered = {}
        if (withLibs == "full") then
            registered["LibForeverInspector"] = {}
            registered["LibDetours-1.0"] = {}
        end
        local stub = {}
        stub.GetLibrary = function(_, name, silent) return registered[name] end
        REALG.LibStub = STD.setmetatable(stub, {
            __call = function(_, name) return registered[name] end,
        })
    end
end

local function loadMain()
    local chunk, loadErr = STD.loadfile(ROOT .. "main.lua")
    if (not chunk) then return false, "loadfile: " .. STD.tostring(loadErr) end
    local ok, runErr = STD.pcall(chunk, "TacoTip_Forever")
    if (not ok) then return false, "raise: " .. STD.tostring(runErr) end
    return true, nil
end

-- Case 1: LibStub absent. The old file-scope asserts raised here with no TT
-- and no stage; now the load stops at "begin" with LOAD_OK unset.
do
    mainEnv("none")
    local ok, err = loadMain()
    local TT = REALG.TacoTip_Forever
    check("main.lua without LibStub loads without raising", ok, err)
    check("...and records stage begin",
        type(TT) == "table" and TT.LOAD_STAGE == "begin",
        "stage=" .. tostring(TT and TT.LOAD_STAGE))
    check("...and does not claim a complete load",
        type(TT) == "table" and not TT.LOAD_OK,
        "LOAD_OK=" .. tostring(TT and TT.LOAD_OK))
end

-- Case 2: LibStub present but LibForeverInspector absent. Stops at "libs".
do
    mainEnv("bare")
    local ok, err = loadMain()
    local TT = REALG.TacoTip_Forever
    check("main.lua without LibForeverInspector loads without raising", ok, err)
    check("...and records stage libs",
        type(TT) == "table" and TT.LOAD_STAGE == "libs",
        "stage=" .. tostring(TT and TT.LOAD_STAGE))
    check("...and does not claim a complete load",
        type(TT) == "table" and not TT.LOAD_OK,
        "LOAD_OK=" .. tostring(TT and TT.LOAD_OK))
end

-- Case 3: GetBuildInfo absent. The old bare call raised at library file
-- scope; now the library loads with family unknown and interfaceVersion 0,
-- which /tacotip diag already reports through the IsUnknown problem.
do
    for k in STD.pairs(REALG) do REALG[k] = nil end
    for k, v in STD.pairs(STD) do REALG[k] = v end
    REALG._G = REALG
    REALG.CreateFrame = function() return { RegisterEvent = function() end, SetScript = function() end } end
    REALG.C_Timer = { After = function() end }
    REALG.C_PlayerInfo = { GUIDIsPlayer = function() return false end }
    REALG.C_Item = { GetInventoryItemLink = function() end }
    REALG.C_SpecializationInfo = { GetSpecializationInfo = function() end }
    REALG.CanInspect = function() return false end
    REALG.NotifyInspect = function() return true end
    REALG.InCombatLockdown = function() return false end
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
    REALG.GetNamePlates = function() return {} end
    REALG.UnitIsPlayer = function() return false end
    REALG.UnitGUID = function() return nil end
    REALG.GetInventoryItemLink = function() end
    REALG.GetPlayerInfoByGUID = function() end
    -- GetSpecializationInfoByID publishes SEVEN values (id, name,
    -- description, texture, role, class, classDisplayName). The stub
    -- published none, which is the same latent gap as the four-value mock
    -- the proctor flagged -- the addon reads #2 and #4 today, so #5+ were
    -- invisible. origin/live: ClubFinder.lua:599 destructures exactly seven.
    -- See Tests/harness/mock_contract.lua.
    REALG.GetSpecializationInfoByID = function()
        return nil, nil, nil, nil, nil, nil, nil
    end
    -- The mock-fidelity contract (proctor HI-12): the mock must publish the
    -- arity the CLIENT publishes. See Tests/harness/mock_contract.lua.
    MOCKC.assertArity(check, "GetSpecializationInfoByID", REALG.GetSpecializationInfoByID)
    REALG.GetItemInfo = function() end
    REALG.GetNumTalentTabs = nil
    REALG.GetTalentTabInfo = nil
    -- NOTE: no GetBuildInfo on purpose -- this is the case under test.
    check("GetBuildInfo is absent from this sandbox", REALG.GetBuildInfo == nil)
    REALG.WOW_PROJECT_MAINLINE = 1
    REALG.WOW_PROJECT_CLASSIC = 2
    REALG.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
    REALG.WOW_PROJECT_WRATH_CLASSIC = 11
    REALG.WOW_PROJECT_CATACLYSM_CLASSIC = 14
    REALG.WOW_PROJECT_MISTS_CLASSIC = 19
    REALG.WOW_PROJECT_ID = 14
    -- Real library stack, unpatched: LibStub + CallbackHandler + Detours.
    local okLib, errLib = STD.pcall(function()
        STD.assert(STD.loadfile(LIB .. "LibStub/LibStub.lua"))()
        STD.assert(STD.loadfile(LIB .. "CallbackHandler-1.0/CallbackHandler-1.0.lua"))()
        STD.assert(STD.loadfile(LIB .. "LibDetours-1.0/LibDetours-1.0.lua"))()
        STD.assert(STD.loadfile(LIB .. "LibForeverInspector/LibForeverInspector.lua"))("TacoTip")
    end)
    check("library without GetBuildInfo loads without raising", okLib, errLib)
    if (okLib) then
        local ci = REALG.LibStub("LibForeverInspector", true)
        check("...and the client resolves to family unknown",
            ci and ci.family == "unknown",
            "family=" .. tostring(ci and ci.family))
        check("...with interfaceVersion defaulted to 0",
            ci and ci.interfaceVersion == 0,
            "interfaceVersion=" .. tostring(ci and ci.interfaceVersion))
        check("...while GetInspectStats stays callable",
            ci and type(ci:GetInspectStats()) == "table",
            "stats=" .. tostring(ci and ci:GetInspectStats()))
    end
end

STD.io.write(STD.table.concat(results, "\n") .. "\n")
STD.io.write("\n" .. (allok and "ALL PASS" or "*** FAILURES ***") .. "\n")
STD.os.exit(allok and 0 or 1)
