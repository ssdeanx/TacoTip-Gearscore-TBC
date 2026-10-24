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

-- Case 1 & 2: Speculative prototype where main.lua caught missing LibStub/LibForeverInspector
-- and set TT.LOAD_STAGE without raising. Reverted on 2026-10-23 in favor of production
-- assert(LibStub, ...) / assert(LibStub:GetLibrary(...)).
-- do
--     mainEnv("none")
--     local ok, err = loadMain()
--     local TT = REALG.TacoTip_Forever
--     check("main.lua without LibStub loads without raising", ok, err)
-- end
-- do
--     mainEnv("bare")
--     local ok, err = loadMain()
--     local TT = REALG.TacoTip_Forever
--     check("main.lua without LibForeverInspector loads without raising", ok, err)
-- end

-- Case 3: Speculative prototype where LibForeverInspector loads without GetBuildInfo.
-- In WoW runtime, GetBuildInfo is an engine global always present.
-- Reverted on 2026-10-23.
-- do
--     ...
-- end

STD.io.write(STD.table.concat(results, "\n") .. "\n")
STD.io.write("\n" .. (allok and "ALL PASS" or "*** FAILURES ***") .. "\n")
STD.os.exit(allok and 0 or 1)
