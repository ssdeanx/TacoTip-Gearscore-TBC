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

-- 1. Pawn absent: production pawn.lua safely early-returns (lines 14-16).
check("pawn.lua returns early when Pawn absent at load",
    PAWN == nil, "PAWN=" .. tostring(PAWN))
check("TT_GS shared home exists",
    type(GS) == "table", "TT_GS=" .. tostring(GS))

-- 2. Pawn present: pawn.lua loads and initializes TT_PAWN
local envWithPawn = buildEnv()
envWithPawn.PawnClassicLastUpdatedVersion = 2.0538
envWithPawn.PawnGetItemData = function() return {} end
envWithPawn.PawnGetSingleValueFromItem = function() return nil end
envWithPawn.PawnGetScaleColor = function() return 1, 1, 1 end
pcall(sandboxedChunk(ROOT .. "gearscore.lua", envWithPawn), "TacoTip_Forever")
local okPawn, errPawn = pcall(sandboxedChunk(ROOT .. "pawn.lua", envWithPawn), "TacoTip_Forever")
check("pawn.lua loads cleanly when Pawn is present", okPawn, tostring(errPawn))
local activePawn = envWithPawn.TT_PAWN
check("TT_PAWN is initialized when Pawn is present", type(activePawn) == "table")
if (type(activePawn) == "table") then
    check("TT_PAWN:GetItemScore is callable", type(activePawn.GetItemScore) == "function")
    check("TT_PAWN:GetScore is callable", type(activePawn.GetScore) == "function")
end

-- NOTE: Prototypes for TT_PAWN.IsAvailable / TT_PAWN.DrainItemCache / late-load
-- were unmerged and reverted on 2026-10-23 in favor of the production early return.

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
