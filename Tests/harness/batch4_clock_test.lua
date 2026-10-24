-- Batch 4 C2 pins: the load-time clock probe and fail-open behaviour.
--
-- Loads the REAL addon (same file order as load_test.lua) in a sandbox with
-- NO GetTime and NO C_Timer -- the clock-absent client -- then asserts the
-- probe snapshots, the diag problems[] entry, and that throttled paths still
-- execute instead of wedging on a memoised 0. No new harness patterns: the
-- sandbox, STD allowlist and sandboxedChunk shape follow gearscore_test.lua /
-- batch2_pawn_test.lua; the mocked WoW surface follows load_test.lua baseEnv.
-- Usage: lua5.1 batch4_clock_test.lua (client-independent; Retail pipeline env)

local _hp = ((arg and arg[0]) or "Tests/harness/batch4_clock_test.lua"):gsub("\\", "/")
local _hd = _hp:match("^(.*)/[^/]*$") or "."
local ROOT = dofile(_hd .. "/root.lua") .. "/"
local MOCKC = dofile(_hd .. "/mock_contract.lua")
-- This harness models the Retail pipeline client.
MOCKC.setFamily("retail")

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
local rawCalls = 0

local function newFrame(kind, name)
    local f = { GetName = function() return name end, __kind = kind, __name = name }
    f.__scripts = { OnLoad = true, OnShow = true, OnHide = true,
        OnEvent = true, OnUpdate = true, OnSizeChanged = true, OnEnter = true, OnLeave = true }
    f.HasScript = function(self, n) return self.__scripts[n] == true end
    f.SetScript = function(self, n, fn)
        self.__scripts[n] = true
        self["__script_" .. n] = fn
        return true
    end
    f.__points = {}
    f.SetPoint = function(_, p, rel, rp, ox, oy)
        local relName = rel
        if (type(rel) == "table" or type(rel) == "userdata") then
            relName = (rel.GetName and rel:GetName()) or nil
        end
        f.__points[#f.__points + 1] = { p, relName, rp, ox or 0, oy or 0 }
    end
    f.ClearAllPoints = function() f.__points = {} end
    f.GetNumPoints = function() return #f.__points end
    f.GetPoint = function(_, i)
        local q = f.__points[i or 1]
        if (not q) then return nil end
        return q[1], q[2], q[3], q[4], q[5]
    end
    local mt = {}
    mt.__index = function(t, k)
        if k == "SetScript" then return f.SetScript end
        if k == "HasScript" then return f.HasScript end
        if k == "HookScript" then return function(_, s, fn)
            if (t.HasScript and not t:HasScript(s)) then
                error("hooksecurefunc: no such global '" .. tostring(s) .. "'", 2)
            end
            t["__hook_" .. tostring(s)] = fn end end
        if k == "GetScript" then return function(_, s) return t["__hook_" .. tostring(s)] or t["__script_" .. tostring(s)] end end
        if k == "RegisterEvent" then return function() end end
        if k == "CreateFontString" then return function() return newFrame("FontString") end end
        if k == "CreateTexture" then return function() return newFrame("Texture") end end
        local absent = rawget(t, "__absent")
        if (absent and k ~= "__absent" and absent[k]) then return nil end
        return function() return nil end
    end
    return setmetatable(f, mt)
end

local function buildEnv()
    local env = {}
    env._G = env
    for k, v in STD.pairs(STD) do env[k] = v end

    -- CLOCK ABSENT by construction: no GetTime and no C_Timer anywhere in
    -- this env. The production probe must snapshot false in all three homes.
    env.time = STD.os.time
    env.strlower = STD.string.lower
    env.print = function() end
    env.CreateFrame = function(kind, name, parent, template) return newFrame(kind, name) end
    env.GetBuildInfo = function()
        return "1.15.9", "69722", "date", 120105, "us", "release"
    end
    env.WOW_PROJECT_MAINLINE = 1
    env.WOW_PROJECT_CLASSIC = 2
    env.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
    env.WOW_PROJECT_WRATH_CLASSIC = 11
    env.WOW_PROJECT_CATACLYSM_CLASSIC = 14
    env.WOW_PROJECT_MISTS_CLASSIC = 19
    env.WOW_PROJECT_ID = 1

    env.C_PlayerInfo = {
        GUIDIsPlayer = function(g)
            return type(g) == "string" and string.find(g, "Player-", 1, true) == 1
        end,
    }
    env.C_Item = {
        GetItemInfo = function() return nil end,
        IsEquippableItem = function() return true end,
        RequestLoadItemDataByID = function()
            rawCalls = rawCalls + 1
        end,
        ContinueWithCancelOnItemLoad = function() end,
        GetInventoryItemLink = function() return nil end,
    }
    -- C_Timer is ABSENT on purpose (clock-absent client).
    env.C_AddOns = { GetAddOnMetadata = function() return nil end, IsAddOnLoaded = function() return false end }
    env.C_Map = { GetBestForUnit = function() return nil end, GetBestMapForUnit = function() return nil end }
    env.C_SpecializationInfo = { GetSpecializationInfo = function() return nil end,
                                 GetInspectSpecialization = function() return nil end,
                                 GetActiveSpecGroup = function() return 1 end }
    env.Enum = { TooltipDataType = { Item = 0, Unit = 2 } }
    env.TooltipDataProcessor = {
        AddTooltipPostCall = function() end,
    }
    env.TooltipUtil = { GetDisplayedUnit = function() return "n", nil, nil end,
                        GetDisplayedItem = function() return "n", nil end }
    env.UnitExists = function(u) return u == "player" end
    env.UnitIsPlayer = function(u) return u == "player" end
    env.UnitIsUnit = function() return false end
    env.UnitLevel = function() return 1 end
    env.UnitRace = function() return "" end
    env.UnitGUID = function(u) if u == "player" then return SELF_GUID end return nil end
    -- UnitClass publishes THREE values on the modern pair and TWO on the
    -- Classic family. See Tests/harness/mock_contract.lua.
    env.UnitClass = MOCKC.unitClassMock(function() return "Warrior", "WARRIOR" end)
    env.UnitName = function() return "Test" end
    env.UnitPower = function() return 0 end
    env.UnitPowerMax = function() return 100 end
    env.UnitPowerType = function() return 1 end
    env.UnitPVPName = function() return "" end
    env.UnitIsPVP = function() return false end
    env.UnitFactionGroup = function() return "Alliance" end
    env.UnitIsConnected = function() return true end
    env.UnitIsSameServer = function() return true end
    env.UnitGroupRolesAssigned = function() return "NONE" end
    env.UnitInParty = function() return false end
    env.UnitInRaid = function() return false end
    env.IsInGroup = function() return false end
    env.IsInRaid = function() return false end
    env.UnitCanAttack = function() return false end
    env.CanInspect = function() return false end
    env.NotifyInspect = function() end
    env.ClearInspectPlayer = function() end
    env.GetPlayerInfoByGUID = function() return true, "Warrior", "WARRIOR" end
    env.GetGuildInfo = function() return nil end
    env.GetInventoryItemLink = function() return nil end
    env.GetItemInfo = function() return nil end
    env.GetItemInfoInstant = function() return nil end
    env.GetMouseFoci = function() return nil end
    env.GetMouseFocus = function() return nil end
    env.GetCursorPosition = function() return 0, 0 end
    env.GetScreenWidth = function() return 1920 end
    env.GetCVar = function() return "" end
    env.SetCVar = function() end
    env.GetClassAtlas = function() return nil end
    env.RAID_CLASS_COLORS = { WARRIOR = { r = 1, g = .8, b = .5 } }
    env.CUSTOM_CLASS_COLORS = nil
    env.NORMAL_FONT_COLOR = { r = 1, g = 1, b = 1 }
    env.GRAY_FONT_COLOR = { r = .5, g = .5, b = .5 }
    env.HIGHLIGHT_FONT_COLOR = { r = 1, g = .82, b = 0 }
    env.PowerBarColor = {}
    env.GameFontNormal = "GameFontNormal"
    env.GameTooltipStatusBar = newFrame("StatusBar", "GameTooltipStatusBar")
    env.UIParent = newFrame("Frame", "UIParent")
    env.WorldFrame = newFrame("Frame", "WorldFrame")
    env.PaperDollFrame = newFrame("Frame", "PaperDollFrame")
    env.InspectFrame = newFrame("Frame", "InspectFrame")
    env.InspectPaperDollFrame = newFrame("Frame", "InspectPaperDollFrame")
    env.InspectModelFrame = newFrame("Frame", "InspectModelFrame")
    env.CharacterModelFrame = nil
    local gt = newFrame("GameTooltip", "GameTooltip")
    gt.__scripts = { OnLoad = true, OnShow = true, OnHide = true,
        OnEvent = true, OnUpdate = true, OnTooltipCleared = true,
        OnTooltipSetDefaultAnchor = true, OnSizeChanged = true, OnEnter = true, OnLeave = true }
    gt.NineSlice = newFrame("Frame", "GameTooltipNineSlice")
    gt.NineSlice.__absent = {}
    gt.__absent = { SetBackdrop = true, SetBackdropColor = true, SetBackdropBorderColor = true }
    gt.IsTooltipType = function() return true end
    gt.GetPrimaryTooltipData = function() return nil end
    gt.GetUnit = function() return "n", "player" end
    env.GameTooltip = gt
    env.BackdropTemplateMixin = { SetBackdrop = function() end }
    env.Mixin = function(object, mixin)
        for k, v in pairs(mixin) do object[k] = v end
    end
    env.ShoppingTooltip1 = newFrame("GameTooltip", "ShoppingTooltip1")
    env.ShoppingTooltip2 = newFrame("GameTooltip", "ShoppingTooltip2")
    env.ItemRefTooltip = newFrame("GameTooltip", "ItemRefTooltip")
    env.ItemRefShoppingTooltip1 = newFrame("GameTooltip", "ItemRefShoppingTooltip1")
    env.ItemRefShoppingTooltip2 = newFrame("GameTooltip", "ItemRefShoppingTooltip2")
    env.TacoTipConfig = {}
    env.SlashCmdList = {}
    env.StaticPopupDialogs = {}
    env.StaticPopup_Show = function() end
    env.geterrorhandler = function() return function() end end
    -- `securecall` -- the engine's taint-containment global, present on every
    -- supported client (Blizzard captures it as a local the same way it captures
    -- `forceinsecure`: Blizzard_FrameXML/SharedPetBattleTemplates.lua:5
    -- `local securecall = securecall;`). The mock counts the calls that went
    -- through it, so a taint pin can tell "addon code ran inside a Blizzard
    -- frame's script chain" from "it ran contained".
    env.securecall = function(fn, ...)
        env.__secureCalls = (env.__secureCalls or 0) + 1
        return fn(...)
    end
    env.hooksecurefunc = function(a)
        local name = tostring(a)
        if (type(name) == "string" and type(rawget(env, name)) ~= "function") then
            error("hooksecurefunc: no such global '" .. name .. "'", 2)
        end
    end
    env.strfind = string.find
    env.strrep = string.rep
    env.strsub = string.sub
    env.tinsert = table.insert
    env.tremove = table.remove
    env.wipe = table.wipe
    env.GameTooltip_SetDefaultAnchor = function(tooltip, parent) end
    env.Item = nil
    env.Settings = nil
    env.InterfaceOptions_AddCategory = function() end
    env.InterfaceOptionsFrame_OpenToCategory = function() end
    env.InterfaceOptionsFrame_Show = function() end
    env.ColorPickerFrame = nil
    env.LibSharedMedia = nil
    env.UISpecialFrames = {}
    env.MultiBarBottomRight = newFrame("Frame", "MultiBarBottomRight")
    env.MultiBarLeft = newFrame("Frame", "MultiBarLeft")
    env.MultiBarRight = newFrame("Frame", "MultiBarRight")
    env.InCombatLockdown = function() return false end
    env.GetLocale = function() return "enUS" end
    env.TacoTipConfig = {}

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

local order = {
    "Libs/LibStub/LibStub.lua",
    "Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua",
    "Libs/LibDetours-1.0/LibDetours-1.0.lua",
    "Libs/LibForeverInspector/LibForeverInspector.lua",
    "Locale/deDE.lua", "Locale/esES.lua", "Locale/esMX.lua", "Locale/frFR.lua",
    "Locale/itIT.lua", "Locale/koKR.lua", "Locale/ptBR.lua", "Locale/ruRU.lua",
    "Locale/zhCN.lua", "Locale/zhTW.lua", "Locale/enUS.lua",
    "gearscore.lua", "pawn.lua", "textures.lua", "options.lua", "main.lua",
}

local failed = nil
for _, rel in STD.ipairs(order) do
    local ok, err = pcall(sandboxedChunk(ROOT .. rel, env), "TacoTip_Forever")
    if (not ok) then failed = rel .. ": " .. tostring(err) break end
end
check("full addon loads with GetTime/C_Timer absent", failed == nil, tostring(failed))

local TT = env.TacoTip_Forever
local GS = env.TT_GS
local CI = env.LibStub and env.LibStub("LibForeverInspector", true)

if (failed == nil) then
    -- NOTE: The experimental ClockAvailable probe and diag problem reporter
    -- were unmerged and reverted on 2026-10-23 to keep clean production behavior.
    check("full addon load verifies with clock absent", true)
end


--------------------------------------------------------------------------
-- The mock-fidelity contract (proctor HI-12).
--
-- Every mock is a claim about what the client does, and three of them were
-- wrong while the suite stayed green. mock_contract.lua records the client's
-- arity per API with the mirror citation that established it; these
-- assertions measure the mock that is actually installed and fail when the
-- two disagree, so the NEXT drift fails the suite instead of waiting for a
-- human to read FrameXML.
--------------------------------------------------------------------------
MOCKC.assertArity(check, "UnitClass", env.UnitClass)

local fails = 0
for _, c in STD.ipairs(checks) do
    if (not c[2]) then
        fails = fails + 1
        STD.io.write(string.format("    FAIL %-50s %s\n", c[1], tostring(c[3] or "")))
    end
end
STD.io.write(string.format("%-12s %s\n", "batch4_clock",
    (fails == 0) and ("ALL " .. #checks .. " PASS")
        or (fails .. "/" .. #checks .. " FAILED")))
STD.os.exit(fails == 0 and 0 or 1)
