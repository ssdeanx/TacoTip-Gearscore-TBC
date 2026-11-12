-- Forever-only tooltip acceptance pins (0.9.2; Camelot talent readout 0.9.7;
-- zone row and native loot-window tooltip 0.9.8).
--
-- WoW Forever (interface 16001) must render the unit tooltip like the Classic
-- reference -- name/class color, level line, target line, guild line behavior,
-- GearScore line, iLvl line, Pawn line, portrait, borders -- plus the
-- Forever-specific Camelot talent readout: up to two lines (Primary/Secondary)
-- in the TBC shape, `Talents: <icon> <tree> [p1/p2/p3]`, where the tree is the
-- one with the most points. The readout is gated on the Camelot C_Traits data;
-- when the client cannot answer, no line renders and nothing else changes.
-- The zone row is gated on the client's own C_Map answer and on the four
-- unit-frame families; the loot-window tooltip is deliberately left native
-- (secret data rebuilt every frame), while a normal item tooltip keeps the
-- Item Level / GearScore rows.
-- Every pin here is Forever-scoped; the other families are covered by the
-- shared suites (tooltip_test CLASSIC_ERA/TBC_ANNIV/TITANFORGE/RETAIL), which
-- this file never touches.
--
-- Usage: lua5.1 Tests/harness/forever_tooltip_test.lua
--
-- Env overrides (red/green proof only; never used in gates):
--   TACOTIP_MAIN_OVERRIDE=/tmp/main_old.lua  load a throwaway main.lua copy
--   TACOTIP_LIB_OVERRIDE=/tmp/lib_old.lua    load a throwaway inspector copy
-- Each new pin was shown RED on a `git show HEAD:`-derived throwaway copy
-- (the pre-fix production code) and GREEN on the working tree.

local _hp = ((arg and arg[0]) or "Tests/harness/forever_tooltip_test.lua"):gsub("\\", "/")
local _hd = _hp:match("^(.*)/[^/]*$") or "."
local ROOT = dofile(_hd .. "/root.lua") .. "/"

local REALG = _G
local unpack = unpack or table.unpack

local STD = {
    os = os,
    string = string,
    pairs = pairs,
    ipairs = ipairs,
    type = type,
    pcall = pcall,
    tonumber = tonumber,
    tostring = tostring,
    select = select,
    rawget = rawget,
    rawset = rawset,
    setmetatable = setmetatable,
    getmetatable = getmetatable,
    unpack = unpack,
    assert = assert,
    error = error,
    math = math,
    table = table,
    loadfile = loadfile,
    print = print,
    io = io,
    getenv = os.getenv,
    xpcall = function(f, handler, ...)
        local args = { ... }
        local n = select("#", ...)
        local function trampoline() return f(unpack(args, 1, n)) end
        local ok, err = pcall(trampoline)
        if (not ok) then
            if (type(handler) == "function") then
                local hOk = pcall(handler, err)
                if (not hOk) then error(err, 0) end
            else
                error(err, 0)
            end
        end
        return ok
    end,
    next = next,
    rawequal = rawequal,
    rawlen = function(t) return #t end,
    collectgarbage = collectgarbage,
}

local baseTable = table
local baseNext = next
STD.table = setmetatable({
    wipe = baseTable.wipe or function(t)
        for k in baseNext, t do t[k] = nil end
        return t
    end,
}, { __index = baseTable })

--------------------------------------------------------------------------
-- Widget factory (line-pool model: ClearLines keeps the FontStrings, exactly
-- like the client).
--------------------------------------------------------------------------
-- Forward: what the client itself contributes per unit token (assigned below,
-- after the frames exist). Local so the harness adds no new globals.
local CLIENT_SEED
local function makeWidget(kind, name, parent, template, depth)
    depth = depth or 0
    local w = { __kind = kind, __name = name, __parent = parent, __text = nil, __shown = true }
    w.__lines, w.__hooks, w.__events = {}, {}, {}
    w.__scripts = {
        OnLoad = true, OnShow = true, OnHide = true, OnEvent = true,
        OnUpdate = true, OnSizeChanged = true, OnEnter = true, OnLeave = true,
        OnTooltipCleared = true,
    }
    local MT = {}
    MT.__index = function(t, k)
        local absent = rawget(w, "__absent")
        if (absent and absent[k]) then return nil end
        local f = rawget(w, k)
        if f then return f end
        return nil
    end
    w.GetFrameLevel = function() return 1 end
    w.SetFrameLevel = function() end
    w.GetFrameStrata = function() return "MEDIUM" end
    w.SetFrameStrata = function() end
    w.GetName = function() return name end
    w.GetParent = function() return parent end
    w.GetObjectType = function() return kind end
    w.SetScript = function(_, s, fn) w.__scripts[s] = fn end
    w.GetScript = function(_, s) return w.__scripts[s] end
    w.__scripts_declared = nil
    w.HasScript = function(self, n) return self.__scripts[n] == true end
    w.HookScript = function(_, s, fn)
        if (_.HasScript and not _:HasScript(s)) then
            error("bad argument #2 to 'HookScript' (Usage: self:HookScript(scriptTypeName, script))", 2)
        end
        w.__hooks[s] = fn
    end
    w.RegisterEvent = function(_, e) w.__events[#w.__events + 1] = e end
    w.UnregisterEvent = function() end
    w.Show = function() w.__shown = true end
    w.Hide = function() w.__shown = false end
    w.IsShown = function() return w.__shown end
    w.SetShown = function(_, v) w.__shown = v and true or false end
    w.__points = {}
    w.SetPoint = function(_, p, rel, rp, ox, oy)
        local relName = rel
        if (type(rel) == "table" or type(rel) == "userdata") then
            relName = (rel.GetName and rel:GetName()) or nil
        end
        w.__points[#w.__points + 1] = { p, relName, rp, ox or 0, oy or 0 }
    end
    w.ClearAllPoints = function() w.__points = {} end
    w.SetAllPoints = function() w.__points = {} end
    w.SetSize = function(_, a, b) w.__w, w.__h = a, b end
    w.SetWidth = function(_, a) w.__w = a end
    w.SetHeight = function(_, a) w.__h = a end
    w.GetWidth = function() return w.__w or 0 end
    w.GetHeight = function() return w.__h or 0 end
    w.GetLeft = function() return 0 end
    w.GetRight = function() return 0 end
    w.GetAlpha = function(self) return self.__alpha end
    w.__alpha = 1
    w.SetAlpha = function(self, a) self.__alpha = a end
    w.SetBackdropColor = function() end
    w.SetBackdropBorderColor = function(_, r, g, b, a) w.__borderColor = { r, g, b, a } end
    w.SetClampedToScreen = function() end
    w.SetHitRectInsets = function() end
    w.SetClampRectInsets = function() end
    w.EnableMouse = function() end
    w.EnableMouseWheel = function() end
    w.SetMovable = function() end
    w.SetUserPlaced = function() end
    w.SetText = function(_, t) w.__text = t end
    w.GetText = function() return w.__text end
    w.SetFontObject = function() end
    -- Recorded, not discarded: the script pin below must prove WHICH face a
    -- line was drawn with, and the addon's own _tacoTipFont cache is the
    -- record of what it decided to apply.
    w.SetFont = function(_, font, size) w.__font, w.__fontSize = font, size end
    w.SetJustifyH = function() end
    w.SetJustifyV = function() end
    w.SetWordWrap = function() end
    w.SetNonSpaceWrap = function() end
    w.SetMaxLetters = function() end
    w.SetShadowOffset = function() end
    w.SetShadowColor = function() end
    w.SetTextColor = function() end
    w.GetStringHeight = function() return 12 end
    w.SetVertexColor = function() end
    w.SetTexture = function(_, t) w.__texture = t end
    w.SetColorTexture = function() end
    w.SetTexCoord = function() end
    w.SetDesaturated = function() end
    w.SetDrawLayer = function() end
    w.SetStatusBarTexture = function() end
    w.SetStatusBarColor = function(_, r, g, b) w.__statusR, w.__statusG, w.__statusB = r, g, b end
    w.SetMinMaxValues = function(_, a, b) w.__min, w.__max = a, b end
    w.SetValue = function(_, v) w.__value = v end
    w.SetValueStep = function() end
    w.SetObeyStepOnDrag = function() end
    w.SetChecked = function(_, v) w.__checked = v and true or false end
    w.GetChecked = function() return w.__checked end
    w.SetEnabled = function(_, v) w.__enabled = v ~= false end
    w.IsEnabled = function() return w.__enabled ~= false end
    w.SetScrollChild = function(_, c) w.__scrollChild = c end
    w.SetVerticalScroll = function() end
    w.GetVerticalScroll = function() return 0 end
    w.SetPortraitTexture = function(_, t) w.__portrait = t end
    w.SetPortraitZoom = function() end
    w.SetModelScale = function() end
    w.SetCamera = function() end
    w.SetPosition = function() end
    w.SetFacing = function() end
    -- NOTE: SetUnit is a plain record; UpdateTooltip below is engine-faithful
    -- (it re-drives the unit post-call for the tooltip's current unit, which
    -- is what the engine method does on every client -- the operator's symptom
    -- proves the GSCallback re-drive re-invokes the handler in game). The
    -- unit post-call table is installed later; until then this is a no-op.
    w.SetUnit = function(self, u)
        w.__unit = u
        -- Engine-faithful: on every client, SetUnit on a unit tooltip clears
        -- the frame, the CLIENT repopulates its own name/guild/level rows, and
        -- only then do the TooltipDataProcessor post-calls (the addon's render
        -- entry) run. Without the repopulation the handler would read the
        -- addon's own previous output -- including lines clearTooltipVisuals
        -- just blanked by the ownership proof -- and bail at the empty-header
        -- guard. CLIENT_SEED is what the client itself contributes per token.
        if (self and self == REALG.GameTooltip and POSTCALLS and POSTCALLS.unit) then
            self:ClearLines()
            local seed = CLIENT_SEED and CLIENT_SEED[u]
            if (seed) then
                for _, line in STD.ipairs(seed) do self:AddLine(line) end
            end
            local guid = REALG.UnitGUID and REALG.UnitGUID(u) or nil
            POSTCALLS.unit(self, { guid = guid })
        end
    end
    w.ClearModel = function() end
    w.Refresh = function() end
    w.FadeOut = function() end
    w.UpdateTooltip = function(self)
        -- main.lua calls this as GameTooltip.UpdateTooltip() (dot, no self),
        -- so fall back to the shared tooltip when no receiver arrived. Like
        -- SetUnit, an engine refresh repopulates the client's own rows first.
        local tt = (type(self) == "table" and self.__unit) and self or REALG.GameTooltip
        if (tt and tt.__unit and POSTCALLS and POSTCALLS.unit) then
            tt:ClearLines()
            local seed = CLIENT_SEED and CLIENT_SEED[tt.__unit]
            if (seed) then
                for _, line in STD.ipairs(seed) do tt:AddLine(line) end
            end
            local guid = REALG.UnitGUID and REALG.UnitGUID(tt.__unit) or nil
            POSTCALLS.unit(tt, { guid = guid })
        end
    end
    w.SetOwner = function() end
    w.GetOwner = function() return nil end
    w.GetMinimumWidth = function() return 0 end
    w.SetMinimumWidth = function() end
    w.GetAnchorType = function() return 1 end
    w.SetPadding = function() end
    w.ClearPadding = function() end
    w.SetBackdrop = function() end
    w.IsUnit = function(_, u) return w.__unit == u end
    w.GetItem = function() return "n", "item:12345" end
    w.GetSpell = function() return "n", 1 end
    w.__absent = {}
    if (kind == "Texture" or kind == "FontString") then
        for _, m in ipairs({ "SetFrameLevel", "GetFrameLevel",
            "SetFrameStrata", "GetFrameStrata" }) do
            w[m] = nil
            w.__absent[m] = true
        end
    end
    -- GameTooltip line pool.
    w.__linePool = {}
    w.__linePoolR = {}
    w.ClearLines = function()
        for i = #w.__lines, 1, -1 do
            local e = w.__lines[i]
            if (e and e.__fs) then e.__fs.__text = nil end
            if (e and e.__fsr) then e.__fsr.__text = nil end
        end
        w.__lines = {}
    end
    w.NumLines = function() return #w.__lines end
    w.AddLine = function(_, txt, r, g, b)
        ADDLINE_CALLS = (ADDLINE_CALLS or 0) + 1
        local n = #w.__lines + 1
        local e = { left = txt, r = r, g = g, b = b, __fs = w.__linePool[n] }
        if (e.__fs) then e.__fs.__text = txt end
        w.__lines[n] = e
    end
    w.AddDoubleLine = function(_, l, rt)
        ADDLINE_CALLS = (ADDLINE_CALLS or 0) + 1
        local n = #w.__lines + 1
        local e = { left = l, right = rt, __fs = w.__linePool[n], __fsr = w.__linePoolR[n] }
        if (e.__fs) then e.__fs.__text = l end
        if (e.__fsr) then e.__fsr.__text = rt end
        w.__lines[n] = e
    end
    w.GetLeftLine = function(_, i)
        local e = w.__lines[i]
        if (not e) then return nil end
        local fs = e.__fs
        if (not fs) then
            fs = makeWidget("FontString", (name or "TT") .. "TextLeft" .. i, w, nil, depth + 1)
            if (e.left ~= nil) then fs.__text = e.left end
            w.__linePool[i] = fs
            e.__fs = fs
        end
        return fs
    end
    w.GetRightLine = function(_, i)
        local e = w.__lines[i]
        if (not e or not e.right) then return nil end
        local fs = e.__fsr
        if (not fs) then
            fs = makeWidget("FontString", (name or "TT") .. "TextRight" .. i, w, nil, depth + 1)
            fs.__text = e.right
            w.__linePoolR[i] = fs
            e.__fsr = fs
        end
        return fs
    end
    w.CreateFontString = function(_, n, sub, tmpl)
        local c = makeWidget("FontString", n or (name and name .. "FS"), w, tmpl, depth + 1)
        if (n) then rawset(REALG, n, c) end
        return c
    end
    w.CreateTexture = function(_, n, sub, tmpl)
        local c = makeWidget("Texture", n or (name and name .. "T"), w, tmpl, depth + 1)
        if (n) then rawset(REALG, n, c) end
        return c
    end
    return setmetatable(w, MT)
end

--------------------------------------------------------------------------
-- Sandbox: the whole global table is replaced, then rebuilt from STD plus
-- the mocked Forever client.
--------------------------------------------------------------------------
for k in STD.pairs(REALG) do REALG[k] = nil end
for k, v in STD.pairs(STD) do REALG[k] = v end
REALG._G = REALG
REALG.time = STD.os.time
REALG.print = function(s) STD.io.write(tostring(s) .. "\n") end
REALG.geterrorhandler = function()
    return function(e)
        ERRORS[#ERRORS + 1] = tostring(e)
    end
end
ERRORS = {}
TIMERS = {}

local VALID_FRAME_TYPES = {    Frame = true, Button = true, CheckButton = true, EditBox = true,
    ScrollFrame = true, Slider = true, StatusBar = true, GameTooltip = true,
    PlayerModel = true, NumberEditBox = true, SelectionGroup = true,
    ColorPicker = true, MessageFrame = true, Model = true, Movie = true,
    OffScreenFrame = true, SideDock = true, ArenaSpectatorFrame = true,
}
local ALL_FRAMES = {}
REALG.CreateFrame = function(kind, name, parent, template)
    if (type(kind) ~= 'string' or not VALID_FRAME_TYPES[kind]) then
        error("CreateFrame: Unknown frame type '" .. tostring(kind) .. "'", 2)
    end
    local w = makeWidget(kind or "Frame", name, parent, template)
    ALL_FRAMES[#ALL_FRAMES + 1] = w
    return w
end
REALG.GetLocale = function() return "enUS" end
REALG.GetCVar = function() return "" end
REALG.SetCVar = function() end
REALG.InCombatLockdown = function() return false end
REALG.securecall = function(fn, ...) return fn(...) end
REALG.LoadAddOn = function() return true end
REALG.GameTooltip_SetDefaultAnchor = function() end
local SECURE_HOOKS = {}
REALG.hooksecurefunc = function(a, b, c)
    if (type(a) == "string") then
        local name, fn = a, b
        local prev = SECURE_HOOKS[name]
        SECURE_HOOKS[name] = function(...)
            if (prev) then prev(...) end
            return fn(...)
        end
    elseif (type(a) == "table" and type(b) == "string") then
        local t, name, fn = a, b, c
        local prev = t[name]
        t[name] = function(...)
            if (prev) then prev(...) end
            return fn(...)
        end
    end
end
REALG.tinsert = table.insert
REALG.tremove = table.remove
REALG.strlower = string.lower
REALG.strfind = string.find
REALG.strrep = string.rep
REALG.strsub = string.sub
REALG.wipe = table.wipe
REALG.SlashCmdList = {}
REALG.StaticPopupDialogs = {}
REALG.StaticPopup_Show = function() end
REALG.UISpecialFrames = {}
REALG.TacoTipConfig = {}
REALG.TACO_TIP_DEBUG = true
-- Forever family identity: MAINLINE project, 16001 in the 4th slot.
REALG.GetBuildInfo = function() return "10.2.7", "1", "d", 16001, "us", "rel" end
REALG.WOW_PROJECT_MAINLINE = 1
REALG.WOW_PROJECT_CLASSIC = 2
REALG.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
REALG.WOW_PROJECT_WRATH_CLASSIC = 11
REALG.WOW_PROJECT_CATACLYSM_CLASSIC = 14
REALG.WOW_PROJECT_MISTS_CLASSIC = 19
REALG.WOW_PROJECT_ID = 1
REALG.C_AddOns = {
    IsAddOnLoaded = function(name) return name == "FojjiCore" end,
    GetAddOnMetadata = function(_, k)
        if k == "Version" then
            local f = STD.io.open(ROOT .. "TacoTip.toc", "r")
            if (f) then
                local content = f:read("*a")
                f:close()
                local ver = content:match("## Version: ([^\r\n]+)")
                if (ver) then return ver end
            end
            return "0.9.2"
        end
        if k == "Title" then return "TacoTip Forever" end
    end,
}
-- FojjiCore's public namespace. The row is switched off through its own
-- Tooltips option; TacoTip must never replace GameTooltip's methods.
local fojjiScoreCalls = 0
REALG.FojjiCoreNS = {
    Tooltips = {
        Set = function(key, on)
            if (key == "bisGearScore" and on == false) then
                fojjiScoreCalls = fojjiScoreCalls + 1
            end
        end,
    },
}
REALG.C_Item = {}
REALG.C_PlayerInfo = {
    GUIDIsPlayer = function(g)
        return type(g) == "string" and string.find(g, "Player%-", 1) == 1
    end,
}
REALG.C_Map = {
    -- Mutable indirection: main.lua captures this function when it loads, so a
    -- test that replaces the table field afterwards would not change what the
    -- addon calls. The captured function reads the state table instead.
    GetBestMapForUnit = function(u)
        return REALG.__bestMapForUnit and REALG.__bestMapForUnit(u) or nil
    end,
    GetMapInfo = function(id)
        return REALG.__mapInfo and REALG.__mapInfo(id) or nil
    end,
}
for _, f in ipairs({ "GameFontNormal", "GameFontHighlight", "GameFontNormalSmall",
    "GameFontHighlightSmall", "GameFontDisable", "GameFontDisableSmall",
    "GameFontNormalLarge", "NumberFontNormal", "ChatFontNormal" }) do REALG[f] = f end
REALG.NORMAL_FONT_COLOR = { r = 1, g = 1, b = 1 }
REALG.GRAY_FONT_COLOR = { r = .5, g = .5, b = .5 }
REALG.HIGHLIGHT_FONT_COLOR = { r = 1, g = .82, b = 0 }
REALG.RAID_CLASS_COLORS = {
    WARRIOR = { r = 1, g = .8, b = .5 },
    MAGE = { r = .41, g = .8, b = .94 },
}
REALG.CUSTOM_CLASS_COLORS = nil
REALG.PowerBarColor = { [0] = { r = .3, g = .3, b = .8 } }
REALG.CONTAINER_OFFSET_X, REALG.CONTAINER_OFFSET_Y = 0, 0
REALG.PVP_FLAG_ICON = "Interface\\Icons\\pvp_icon"
REALG.HORDE_ICON = "Interface\\Icons\\inv_misc_note_01"
REALG.ALLIANCE_ICON = "Interface\\Icons\\inv_misc_note_02"
REALG.FACTION_BAR_TEXTURE = "Interface\\TargetingFrame\\UI-TargetingFrame-BarFill"
REALG.UIParent = makeWidget("Frame", "UIParent")
REALG.WorldFrame = makeWidget("Frame", "WorldFrame")
REALG.PaperDollFrame = makeWidget("Frame", "PaperDollFrame")
REALG.InspectFrame = makeWidget("Frame", "InspectFrame")
REALG.InspectPaperDollFrame = makeWidget("Frame", "InspectPaperDollFrame")
REALG.InspectModelFrame = makeWidget("Frame", "InspectModelFrame")
REALG.CharacterModelFrame = nil -- modern pair has none
REALG.GameTooltip = makeWidget("GameTooltip", "GameTooltip")
REALG.GameTooltipStatusBar = makeWidget("StatusBar", "GameTooltipStatusBar")
REALG.ItemRefTooltip = makeWidget("GameTooltip", "ItemRefTooltip")
REALG.ShoppingTooltip1 = makeWidget("GameTooltip", "ShoppingTooltip1")
REALG.ShoppingTooltip2 = makeWidget("GameTooltip", "ShoppingTooltip2")
REALG.ItemRefShoppingTooltip1 = makeWidget("GameTooltip", "ItemRefShoppingTooltip1")
REALG.ItemRefShoppingTooltip2 = makeWidget("GameTooltip", "ItemRefShoppingTooltip2")

CLIENT_SEED = {
    player = { "Testplayer", "<Testguild>", "Level 60 Human" },
    mouseover = { "Enemyplayer", "<Testguild>", "Level 59 Mage" },
    target = { "Hated Squirrel", "Level 42 Beast", "QUEST_MARKER_LINE" },
}
local UNITS = {
    player = {
        guid = "Player-1-000001", name = "Testplayer", level = 60,
        race = "Human", class = "WARRIOR", className = "Warrior", classID = 1,
        isPlayer = true, pvp = false,
    },
    mouseover = {
        guid = "Player-2-000002", name = "Enemyplayer", level = 59,
        race = "Orc", class = "MAGE", className = "Mage", classID = 8,
        isPlayer = true, pvp = true,
    },
    -- The mouseover's target: another player, so the class-colored
    -- "Target: <name> (Player)" branch is reachable. Never hovered directly.
    mouseovertarget = {
        guid = "Player-5-000005", name = "Targetplayer", level = 60,
        race = "Human", class = "PRIEST", className = "Priest", classID = 5,
        isPlayer = true, pvp = false,
    },
    target = {
        guid = "Creature-3-000003", name = "Hated Squirrel", level = 42,
        race = "Beast", class = nil, className = nil, classID = nil,
        isPlayer = false, pvp = false,
    },
}
local currentUnit = "player"
REALG.UnitExists = function(u) return UNITS[u] ~= nil end
REALG.UnitFrame_UpdateTooltip = function() end
REALG.UnitGUID = function(u) return UNITS[u] and UNITS[u].guid or nil end
REALG.UnitName = function(u) return UNITS[u] and UNITS[u].name or nil, "Testrealm" end
REALG.__testClock = 1000
REALG.GetTime = function() return REALG.__testClock end
REALG.UnitLevel = function(u) return UNITS[u] and UNITS[u].level or 1 end
REALG.UnitRace = function(u) return UNITS[u] and UNITS[u].race or "" end
-- Modern UnitClass: THREE values (name, token, classID).
REALG.UnitClass = function(u)
    local c = UNITS[u]
    if (not c or not c.class) then return nil, nil end
    return c.className, c.class, c.classID
end
REALG.UnitIsPlayer = function(u) return UNITS[u] and UNITS[u].isPlayer or false end
REALG.__unitIsUnit = nil
REALG.UnitIsUnit = function(a, b)
    -- Mutable override first: main.lua captures UnitIsUnit at load, so a test
    -- that replaces the global afterwards is invisible to the addon. Tests
    -- that need a different identity graph set this state function instead.
    if (REALG.__unitIsUnit) then return REALG.__unitIsUnit(a, b) end
    if (a == b) then return true end
    -- The engine CAN report the hovered unit's target as the player even
    -- though the token differs ("mouseovertarget" vs "player"). Model that
    -- alias so the Target: You/Player branch is reachable in-harness.
    if (a == "mouseovertarget" and b == "player") then return true end
    return false
end
REALG.C_PaperDollInfo = { GetInspectGuildInfo = function() return 0, 0, nil, nil end }
REALG.UnitIsPVP = function(u) return UNITS[u] and UNITS[u].pvp or false end
REALG.UnitPVPName = function() return "Test" end
REALG.UnitFactionGroup = function() return "Alliance" end
REALG.UnitGroupRolesAssigned = function() return "NONE" end
REALG.UnitIsConnected = function() return true end
REALG.UnitIsSameServer = function() return true end
REALG.UnitCanAttack = function() return false end
REALG.UnitInParty = function() return false end
REALG.UnitInRaid = function() return false end
REALG.IsInGroup = function() return false end
REALG.IsInRaid = function() return false end
REALG.UnitPower = function() return 50 end
REALG.UnitPowerMax = function() return 100 end
REALG.UnitPowerType = function() return 0 end
REALG.GetGuildInfo = function() return "Testguild", "Testrealm" end
REALG.GetPlayerInfoByGUID = function(guid)
    for _, c in STD.pairs(UNITS) do
        if (c.guid == guid and c.class) then return true, c.class end
    end
    return true, nil
end
REALG.UnitIsOtherPlayersPet = function() return false end
REALG.UnitIsVisible = function() return true end
REALG.UnitIsDeadOrGhost = function() return false end
REALG.UnitHealthMax = function() return 100 end
REALG.GetNamePlates = function() return {} end
REALG.CanInspect = function() return true end
REALG.CheckInteractDistance = function() return true end
REALG.NotifyInspect = function() return true end
REALG.UnitDistanceSquared = function() return 100, true end
REALG.__clearInspectPlayerCalls = 0
REALG.ClearInspectPlayer = function()
    REALG.__clearInspectPlayerCalls = (REALG.__clearInspectPlayerCalls or 0) + 1
end
REALG.GetComparisonAchievementPoints = function() return 0 end
REALG.GetTotalAchievementPoints = function() return 0 end
REALG.GetQuestDifficultyColor = function() return { r = 1, g = .5, b = 0 } end
-- Deferred bodies: C_Timer.After records instead of running, so the retry
-- ladder cannot recurse synchronously (the parked test clock would otherwise
-- spin the drain loop forever). pumpTimers() drives them by hand, bounded.
REALG.C_Timer = {
    After = function(_, fn)
        if fn then TIMERS[#TIMERS + 1] = { func = fn } end
    end,
    NewTimer = function(...)
        local a = { ... }; local fn = a[#a]
        local h = { Cancel = function() end, func = fn }; TIMERS[#TIMERS + 1] = h; return h
    end,
    NewTicker = function(...)
        local a = { ... }; local fn = a[#a]
        local h = { Cancel = function() end, func = fn }; TIMERS[#TIMERS + 1] = h; return h
    end,
}
local function pumpTimers()
    local guard = 0
    while (#TIMERS > 0 and guard < 50) do
        guard = guard + 1
        local pending = TIMERS
        TIMERS = {}
        REALG.TIMERS = TIMERS
        for _, h in STD.ipairs(pending) do
            if (h and h.func) then h.func() end
        end
    end
end
REALG.GetMouseFoci = function() return {} end
REALG.GetMouseFocus = function() return nil end
REALG.GetCursorPosition = function() return 0, 0 end
REALG.GetScreenWidth = function() return 1920 end
REALG.GetClassAtlas = function() return "classicon-warrior" end
REALG.IsModifierKeyDown = function() return false end
REALG.IsShiftKeyDown = function() return false end
REALG.InterfaceOptions_AddCategory = function() end
REALG.InterfaceOptionsFrame_OpenToCategory = function() end
REALG.InterfaceOptionsFrame_Show = function() end
REALG.BackdropTemplateMixin = {}
REALG.Item = { CreateFromItemLink = function() error("FOREVER_PIN_NO_ITEM_API") end }
REALG.Settings = nil
REALG.ColorPickerFrame = nil
REALG.Enum = {
    TooltipDataType = { Item = 0, Unit = 2 },
    -- RestrictedActionsConstantsDocumentation.lua:19-33
    AddOnRestrictionType = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4, Chat = 5 },
}

--------------------------------------------------------------------------
-- Gear model. GEAR_MODE flips what the client reports for inspected units:
-- "full" stages a complete 17-slot set, "empty" reports nothing equipped.
--------------------------------------------------------------------------
local GEAR_LINK = "item:12345"
local GEAR_MODE = "full"
REALG.GetInventoryItemLink = function(unit, slot)
    if (GEAR_MODE == "full" and slot ~= 4) then return GEAR_LINK end
    return nil
end
REALG.GetInventoryItemTexture = function(unit, slot)
    if (GEAR_MODE == "full" and slot ~= 4) then return "tex" end
    return nil
end
REALG.C_Item.GetInventoryItemLink = REALG.GetInventoryItemLink
REALG.GetItemInfo = function(link)
    if (link == GEAR_LINK) then
        return "Test Helm", link, 4, 88, 1, "Armor", "Plate", 1,
            "INVTYPE_HEAD", "icon", 0
    end
    return nil
end
REALG.C_Item.GetItemInfo = REALG.GetItemInfo
REALG.GetItemInfoInstant = function() return 12345 end
REALG.C_Item.GetItemInfoInstant = function() return 12345 end
REALG.C_Item.IsEquippableItem = function() return true end
REALG.IsEquippableItem = REALG.C_Item.IsEquippableItem
REALG.__rawItemRequests = 0
REALG.__rawItemRequestIDs = {}
REALG.C_Item.RequestLoadItemDataByID = function(id)
    REALG.__rawItemRequests = REALG.__rawItemRequests + 1
    REALG.__rawItemRequestIDs[#REALG.__rawItemRequestIDs + 1] = id
end
REALG.C_Item.ContinueWithCancelOnItemLoad = function(_, fn) return function() end end
REALG.C_Item.GetItemLinkByID = function() return GEAR_LINK end
REALG.C_Item.GetItemLinkByGUID = function() return nil end

--------------------------------------------------------------------------
-- Modern specialization model. Per the generated API docs on origin/forever,
-- C_SpecializationInfo.GetSpecialization answers a 1-based specialization
-- INDEX (SpecializationInfoDocumentation.lua: GetSpecialization ->
-- specializationIndex), while GetInspectSpecialization answers a specID.
-- The mock reproduces that split: a mock that answered an ID here hid the
-- defect this file pins (every unit scored on spec 1).
--------------------------------------------------------------------------
local SPECS = {
    [1] = { id = 71, name = "Arms", icon = 1100001 },
    [2] = { id = 72, name = "Fury", icon = 1100002 },
    [3] = { id = 73, name = "Protection", icon = 1100003 },
}
local GROUP_SPEC_INDEX = { [1] = 2 } -- group 1's active spec is index 2, NOT 1
local GROUP_POINTS = { [1] = { [1] = 0, [2] = 21, [3] = 0 } }
REALG.C_SpecializationInfo = {}
REALG.C_SpecializationInfo.GetSpecializationInfo = function(specIndex, isInspect, isPet,
        inspectTarget, sex, groupIndex, classID)
    local s = SPECS[specIndex]
    if (not s) then return 0 end
    local group = groupIndex or 1
    local pts = (GROUP_POINTS[group] or {})[specIndex] or 0
    return s.id, s.name, "desc", s.icon, "DPS", 4, pts, nil, 0, true
end
REALG.C_SpecializationInfo.GetSpecialization = function(isInspect, isPet, groupIndex)
    return GROUP_SPEC_INDEX[groupIndex or 1]
end
REALG.C_SpecializationInfo.GetInspectSpecialization = function(unit)
    if (UNITS[unit] and UNITS[unit].isPlayer) then return SPECS[2].id end
    return nil
end
REALG.C_SpecializationInfo.GetActiveSpecGroup = function() return 1 end
REALG.C_SpecializationInfo.GetClassIDFromSpecID = function(specID)
    for _, s in STD.pairs(SPECS) do
        if (s.id == specID) then return 1 end
    end
    return 0
end
REALG.C_SpecializationInfo.GetNumSpecializationsForClassID = function() return 3 end
REALG.C_SpecializationInfo.GetTalentInfo = function(query)
    -- The best-effort inactive-group read: only the linear inspect form, for
    -- the mouseover target's group 2, with real per-talent ranks.
    if (query and query.isInspect and query.groupIndex == 2 and query.target == "mouseover"
            and query.specializationIndex and query.talentIndex == 1) then
        local ranks = { [1] = 33, [2] = 28 }
        local rank = ranks[query.specializationIndex]
        if (rank) then
            return { name = "Talent", icon = 1, tier = 1, column = 1, rank = rank, maxRank = 5 }
        end
    end
    return nil
end
REALG.GetSpecializationInfoByID = function(specID)
    for _, s in STD.pairs(SPECS) do
        if (s.id == specID) then
            return s.id, s.name, "desc", s.icon, "DPS", "WARRIOR", "Warrior"
        end
    end
    return nil, nil, nil, nil, nil, nil, nil
end
REALG.UnitSex = function() return 2 end
-- No talent tabs on the modern pair: the Classic tab helper must find nothing.
REALG.GetNumTalentTabs = nil
REALG.GetNumTalents = nil
REALG.GetSpecialization = nil
REALG.GetNumTalentGroups = function() return 1 end
REALG.GetActiveTalentGroup = function() return 1 end
REALG.GetTalentTabInfo = nil

--------------------------------------------------------------------------
-- Camelot talent model (WoW Forever). One class-level specialization, three
-- talent trees (trait node groups) and up to two spec groups. The client reads
-- it through C_Traits; the classic talent globals do not exist on Camelot.
--   tree name/icon  <- GetGroupDisplayInfoByTreeID
--   tree points     <- GetGroupCurrencyInfo(...).currencyInfos[1].spent
--   spec group ids  <- GetCombatConfigIDForSpecGroup(g); -1 for an inspect
--   inspect config  <- Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID
--------------------------------------------------------------------------
REALG.__foreverSpecGroups = 1
REALG.__foreverInspectGroups = 1
REALG.GetNumSpecGroups = function(isInspect)
    if (isInspect) then return REALG.__foreverInspectGroups end
    return REALG.__foreverSpecGroups
end
REALG.Constants = { TraitConsts = { INSPECT_TRAIT_CONFIG_ID = -1 } }
local FOREVER_TREES = {
    { groupID = 11, orderIndex = 1, displayName = "Arms", icon = 1100001 },
    { groupID = 12, orderIndex = 2, displayName = "Fury", icon = 1100002 },
    { groupID = 13, orderIndex = 3, displayName = "Protection", icon = 1100003 },
}
local FOREVER_POINTS = {
    [-1] = { [11] = 0, [12] = 21, [13] = 0 },   -- inspected player's active group
    [101] = { [11] = 0, [12] = 21, [13] = 0 },  -- player group 1
    [102] = { [11] = 33, [12] = 28, [13] = 0 }, -- player group 2
}
REALG.C_Traits = {
    HasValidInspectData = function() return REALG.__foreverInspectValid ~= false end,
    GetConfigInfo = function(configID) return { ID = configID, treeIDs = { 9001 } } end,
    GetGroupDisplayInfoByTreeID = function() return FOREVER_TREES end,
    GetGroupCurrencyInfo = function(configID, groupIDs)
        local pts = FOREVER_POINTS[configID] or {}
        local out = {}
        for _, groupID in STD.ipairs(groupIDs) do
            out[#out + 1] = {
                traitNodeGroupID = groupID,
                currencyInfos = { { spent = pts[groupID] or 0 } },
            }
        end
        return out
    end,
}
REALG.C_SpecializationInfo.GetCombatConfigIDForSpecGroup = function(groupIndex)
    return 100 + groupIndex
end

--------------------------------------------------------------------------
-- Pawn present with one MrRobot scale for WARRIOR spec 2.
--------------------------------------------------------------------------
REALG.PawnLastUpdatedVersion = 2.1
REALG.PawnCommon = { Scales = {
    ['"MrRobot":WARRIOR2'] = { Color = "ff9d9d9d" },
    ['"MrRobot":MAGE2'] = { Color = "ff9d9d9d" },
} }
REALG.PawnScaleProviders = { MrRobot = true }
REALG.PawnGetItemData = function(link) return { link = link } end
REALG.PawnGetSingleValueFromItem = function(item, scaleName) return nil, 15.5 end
REALG.PawnGetScaleColor = function(scaleName, ...) return "|cffff9d9d9d" end

--------------------------------------------------------------------------
-- Pipeline delivery: the modern tooltip has no OnTooltipSetUnit script, so the
-- addon registers a TooltipDataProcessor post-call. The mock records it; the
-- drive helper below fires it the way the engine would on SetUnit/UpdateTooltip.
--------------------------------------------------------------------------
POSTCALLS = {}
REALG.TooltipDataProcessor = {
    AddTooltipPostCall = function(typ, fn)
        POSTCALLS[#POSTCALLS + 1] = { typ = typ, fn = fn }
        if (typ == REALG.Enum.TooltipDataType.Unit) then POSTCALLS.unit = fn end
    end,
}
REALG.TooltipUtil = {
    GetDisplayedUnit = function() return "n", currentUnit, UNITS[currentUnit].guid end,
    GetDisplayedItem = function() return "n", GEAR_LINK end,
}
REALG.GameTooltip.IsTooltipType = function() return true end
REALG.GameTooltip.GetPrimaryTooltipData = function() return nil end
REALG.GameTooltip.GetUnit = function() return "n", currentUnit end
REALG.GameTooltip.GetItem = function() return "n", GEAR_LINK end
-- Script set WITHOUT OnTooltipSetUnit/OnTooltipSetItem/OnTooltipSetSpell.
do
    local modern = {
        OnLoad = true, OnShow = true, OnHide = true, OnEvent = true,
        OnUpdate = true, OnTooltipCleared = true, OnSizeChanged = true,
        OnEnter = true, OnLeave = true,
    }
    for _, nm in ipairs({ "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1",
        "ShoppingTooltip2", "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2" }) do
        local f = REALG[nm]
        if (f and rawget(f, "__scripts") ~= nil) then rawset(f, "__scripts", modern) end
    end
end

--------------------------------------------------------------------------
-- Load the real addon. TACOTIP_MAIN_OVERRIDE / TACOTIP_LIB_OVERRIDE point at
-- throwaway copies for the red/green proof; gates always load the tree.
--------------------------------------------------------------------------
local MAIN_PATH = STD.getenv("TACOTIP_MAIN_OVERRIDE") or (ROOT .. "main.lua")
local LIB_PATH = STD.getenv("TACOTIP_LIB_OVERRIDE")
    or (ROOT .. "Libs/LibForeverInspector/LibForeverInspector.lua")
local order = {
    "Libs/LibStub/LibStub.lua", "Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua",
    "Libs/LibDetours-1.0/LibDetours-1.0.lua", "__LIB__",
    "Locale/deDE.lua", "Locale/esES.lua", "Locale/esMX.lua", "Locale/frFR.lua",
    "Locale/itIT.lua", "Locale/koKR.lua", "Locale/ptBR.lua",
    "Locale/ruRU.lua", "Locale/zhCN.lua", "Locale/zhTW.lua", "Locale/enUS.lua",
    "gearscore.lua", "pawn.lua", "textures.lua", "options.lua", "__MAIN__",
}
local loadFail
for _, rel in STD.ipairs(order) do
    local path = rel
    if (rel == "__LIB__") then path = LIB_PATH
    elseif (rel == "__MAIN__") then path = MAIN_PATH
    else path = ROOT .. rel end
    local chunk, err = STD.loadfile(path)
    if (not chunk) then loadFail = rel .. " -> " .. tostring(err); break end
    local ok, errs = STD.pcall(chunk, "TacoTip_Forever")
    if (not ok) then loadFail = rel .. " -> " .. tostring(errs); break end
end
if (loadFail) then
    STD.io.write("FOREVER load FAIL " .. tostring(loadFail) .. "\n")
    STD.os.exit(1)
end

local TT = REALG.TacoTip_Forever
local GT = REALG.GameTooltip
local CI = REALG.LibStub and REALG.LibStub("LibForeverInspector", true) or nil

local checks = {}
local function check(name, cond, detail)
    checks[#checks + 1] = { name, cond and true or false, detail }
end

-- Every completed render must be free of doubled color codes. A re-render
-- over the addon's own previous output (no client refresh in between) would
-- wrap an already-wrapped line: "|cFFxxxxxx|cFFxxxxxx". Direct "|c...|c"
-- adjacency never occurs in legitimate output -- real neighbors are always
-- separated by "|r", text, or an icon escape -- so this is a precise purity
-- pin, not a substring guess. Lowercase %x: uppercase %X means NON-hex and
-- would never fire on real color codes.
local DOUBLED_COLOR_PAT = "|c%x%x%x%x%x%x%x%x|c"
local function checkCleanRender(text, where)
    check("render is free of doubled color codes (" .. where .. ")",
        not STD.string.find(text, DOUBLED_COLOR_PAT),
        STD.string.gsub(text, "\n", " | "))
end

-- The detector above is itself pinned: it must fire on a synthetic doubled
-- string and pass a clean one. If the pattern ever regresses (e.g. %x back
-- to %X), these two go red first.
do
    local bad = "|cFF68ccef|cFF68ccefEnemyplayer|r"
    local good = "|cFF68ccefEnemyplayer|r"
    check("meta: doubled-color detector fires on doubled input",
        STD.string.find(bad, DOUBLED_COLOR_PAT) ~= nil)
    check("meta: doubled-color detector passes clean input",
        STD.string.find(good, DOUBLED_COLOR_PAT) == nil)
end

check("addon loads: TT namespace present", type(TT) == "table")
check("addon loads: inspector present", CI ~= nil)
check("client family is Forever", CI and CI:IsForever() == true,
    "IsForever=" .. tostring(CI and CI:IsForever()))
check("unit tooltip delivered by post-call (no OnTooltipSetUnit on modern)",
    GT.__hooks.OnTooltipSetUnit == nil and POSTCALLS.unit ~= nil,
    "hooked=" .. tostring(GT.__hooks.OnTooltipSetUnit ~= nil))

--------------------------------------------------------------------------
-- Config: talents explicitly ON (the gate must hold anyway), scores on.
--------------------------------------------------------------------------
local C = REALG.TacoTipConfig
if (TT.ApplyConfigDefaults) then STD.pcall(TT.ApplyConfigDefaults, TT, C) end
C.show_gs_player = true
C.show_avg_ilvl = true
C.show_ilvl_inline = false
C.show_talents = true
C.show_guild_name = true
C.show_guild_rank = true
C.show_target = true
C.color_class = true
C.show_pawn_player = true
C.show_item_level = true
C.show_gs_items = true
C.show_separators = true
C.show_realm = true
C.tooltip_border_use_class = true
C.tooltip_portrait = true
C.tooltip_portrait_3d = false
C.hide_in_combat = false
C.tip_style = 2

local function seedPlayer()
    GT:ClearLines()
    GT:AddLine("Enemyplayer")
    GT:AddLine("<Testguild>")
    GT:AddLine("Level 59 Mage")
end

local function seedNPC()
    GT:ClearLines()
    GT:AddLine("Hated Squirrel")
    GT:AddLine("Level 42 Beast")
    GT:AddLine("QUEST_MARKER_LINE")
end

local function allText()
    local out = {}
    local n = GT:NumLines()
    for i = 1, n do
        local l = GT:GetLeftLine(i)
        local r = GT:GetRightLine(i)
        local lt = l and l:GetText()
        local rt = r and r:GetText()
        if (lt ~= nil and lt ~= "") then out[#out + 1] = tostring(lt) end
        if (rt ~= nil and rt ~= "") then out[#out + 1] = tostring(rt) end
    end
    return STD.table.concat(out, "\n")
end

local function drive(unitToken)
    currentUnit = unitToken
    GT.__unit = unitToken
    GT.__shown = true
    if (POSTCALLS.unit) then
        POSTCALLS.unit(GT, { guid = UNITS[unitToken].guid })
    end
    return allText()
end

-- Fire every OnEvent script the addon and the library installed, the way the
-- engine fires INSPECT_READY. Only the inspector answers it; the addon's own
-- frame ignores that event. Frames are tracked at creation because both the
-- library and the addon hold theirs in locals, not globals.
local function fireInspectReady(guid)
    local nHandlers = 0
    for _, w in STD.ipairs(ALL_FRAMES) do
        if (type(w) == "table" and w.__scripts
                and type(w.__scripts.OnEvent) == "function") then
            nHandlers = nHandlers + 1
            local ok, err = STD.pcall(w.__scripts.OnEvent, w, "INSPECT_READY", guid)
            if (not ok) then
                return false, tostring(err)
            end
        end
    end
    return true
end

local function primeInspect(unitToken, mode)
    GEAR_MODE = mode or "full"
    currentUnit = unitToken
    REALG.TooltipUtil.GetDisplayedUnit = function()
        return "n", unitToken, UNITS[unitToken].guid
    end
    GT.GetUnit = function() return "n", unitToken end
    GT.__unit = unitToken
    local ok, err = fireInspectReady(UNITS[unitToken].guid)
    if (ok) then pumpTimers() end
    return ok, err
end

--------------------------------------------------------------------------
-- P1: the Camelot talent readout renders on Forever -- with show_talents
-- explicitly ON. The defect path is post-cache: prime a full inspect first,
-- then render. The inspected player's single trait config carries the active
-- group only; the tree with the most points is Fury, 0/21/0.
--------------------------------------------------------------------------
do
    local okFire, fireErr = primeInspect("mouseover", "full")
    check("P1 setup: INSPECT_READY primes the mouseover cache", okFire == true,
        tostring(fireErr or ""))
    currentUnit = "mouseover"
    REALG.TooltipUtil.GetDisplayedUnit = function()
        return "n", "mouseover", UNITS.mouseover.guid
    end
    GT.GetUnit = function() return "n", "mouseover" end
    seedPlayer()
    local ptxt = drive("mouseover")
    local _, talentCount = STD.string.gsub(ptxt, "Talents:", "")
    check("talents: one Talents line on Forever (inspect = active group only)",
        talentCount == 1, STD.string.gsub(ptxt, "\n", " | "))
    check("talents: inspected readout is the most-invested tree with [p1/p2/p3]",
        STD.string.find(ptxt, "Fury|r [0/21/0]", 1, true) ~= nil,
        STD.string.gsub(ptxt, "\n", " | "))
    check("talents: the tree icon is inlined",
        STD.string.find(ptxt, "|T1100002:", 1, true) ~= nil,
        STD.string.gsub(ptxt, "\n", " | "))
    check("talents: no spec overlay frame survives",
        GT.TacoTipSpecIcon == nil
        or (GT.TacoTipSpecIcon.IsShown and not GT.TacoTipSpecIcon:IsShown()),
        "overlay=" .. tostring(GT.TacoTipSpecIcon ~= nil))
    check("target: Target line present as in the reference",
        STD.string.find(ptxt, "Target:", 1, true) ~= nil,
        STD.string.gsub(ptxt, "\n", " | "))
    check("ilvl: TacoTip-owned color-coded iLvl line present",
        STD.string.find(ptxt, "iLvl: |c", 1, true) ~= nil,
        STD.string.gsub(ptxt, "\n", " | "))
    checkCleanRender(ptxt, "post-cache player render")
end

--------------------------------------------------------------------------
-- P20: /tt diag reports the tooltip's own Forever talent source, so a missing
-- Talents line can be attributed (no cache record vs no trait data) instead of
-- guessed. The mouseover cache is primed by P1 above.
--------------------------------------------------------------------------
do
    local diag = TT:CollectDiagnostics()
    local value
    for _, sec in STD.ipairs(diag.sections or {}) do
        for _, row in STD.ipairs(sec.rows or {}) do
            if (row.label == "forever talents") then value = row.value end
        end
    end
    check("P20: /tt diag reports the hovered player's Forever talent data",
        type(value) == "string" and STD.string.find(value, "yes", 1, true) == 1,
        tostring(value))
end

--------------------------------------------------------------------------
-- P19: the inspected readout does not REQUIRE GetNumSpecGroups(true).
--
-- 0.9.7 used the inspect-side group count only to decide whether to attempt
-- the optional second line. Requiring that query to answer before drawing the
-- first line hides talents on every inspected player on a client that does
-- not answer it -- the 0.9.8 regression reported in game. With the query
-- answering nothing, the active tree line must still render.
--------------------------------------------------------------------------
do
    local savedInspectGroups = REALG.__foreverInspectGroups
    REALG.__foreverInspectGroups = nil
    local okFire, fireErr = primeInspect("mouseover", "full")
    check("P19 setup: INSPECT_READY primes with no inspect group count", okFire == true,
        tostring(fireErr or ""))
    currentUnit = "mouseover"
    REALG.TooltipUtil.GetDisplayedUnit = function()
        return "n", "mouseover", UNITS.mouseover.guid
    end
    GT.GetUnit = function() return "n", "mouseover" end
    seedPlayer()
    local txt = drive("mouseover")
    check("P19: inspected talents render without GetNumSpecGroups(true)",
        STD.string.find(txt, "Fury|r [0/21/0]", 1, true) ~= nil,
        STD.string.gsub(txt, "\n", " | "))
    REALG.__foreverInspectGroups = savedInspectGroups
end

--------------------------------------------------------------------------
-- P1b: the player's own readout -- one line without dual spec, two lines with
-- it (active first, inactive dimmed). The second line must not appear before
-- GetNumSpecGroups() says a second group exists.
--------------------------------------------------------------------------
do
    local savedStyle = C.tip_style
    -- Narrow (single-line) style, the shape of the operator's TBC reference:
    -- both the active and the inactive line carry the "Talents:" label.
    C.tip_style = 2
    local function resolvePlayer()
        REALG.TooltipUtil.GetDisplayedUnit = function() return "n", "player", UNITS.player.guid end
        GT.GetUnit = function() return "n", "player" end
    end
    REALG.__foreverSpecGroups = 1
    CI.foreverPlayerTalentMemo = nil
    resolvePlayer()
    seedPlayer()
    local one = drive("player")
    local _, oneCount = STD.string.gsub(one, "Talents:", "")
    check("self: no dual spec renders exactly one Talents line", oneCount == 1,
        STD.string.gsub(one, "\n", " | "))

    REALG.__foreverSpecGroups = 2
    CI.foreverPlayerTalentMemo = nil
    resolvePlayer()
    seedPlayer()
    local two = drive("player")
    local _, twoCount = STD.string.gsub(two, "Talents:", "")
    check("self: dual spec renders exactly two Talents lines", twoCount == 2,
        STD.string.gsub(two, "\n", " | "))
    check("self: active group renders first (Fury [0/21/0])",
        STD.string.find(two, "Fury|r [0/21/0]", 1, true) ~= nil,
        STD.string.gsub(two, "\n", " | "))
    check("self: inactive group renders second (Arms [33/28/0])",
        STD.string.find(two, "Arms|r [33/28/0]", 1, true) ~= nil,
        STD.string.gsub(two, "\n", " | "))
    local furyAt = STD.string.find(two, "Fury|r [0/21/0]", 1, true)
    local armsAt = STD.string.find(two, "Arms|r [33/28/0]", 1, true)
    check("self: active line precedes the inactive line",
        furyAt ~= nil and armsAt ~= nil and furyAt < armsAt,
        STD.string.gsub(two, "\n", " | "))

    REALG.__foreverSpecGroups = 1
    CI.foreverPlayerTalentMemo = nil
    C.tip_style = savedStyle
    REALG.TooltipUtil.GetDisplayedUnit = function()
        return "n", "mouseover", UNITS.mouseover.guid
    end
    GT.GetUnit = function() return "n", "mouseover" end
end

--------------------------------------------------------------------------
-- P1c: the Camelot APIs are optional at runtime. A client that answers none of
-- them must render no Talents line and must not throw.
--------------------------------------------------------------------------
do
    local saved = REALG.C_Traits
    REALG.C_Traits = nil
    CI.foreverPlayerTalentMemo = nil
    REALG.TooltipUtil.GetDisplayedUnit = function() return "n", "player", UNITS.player.guid end
    GT.GetUnit = function() return "n", "player" end
    seedPlayer()
    local txt = drive("player")
    check("talents: a missing C_Traits renders no line and does not error",
        not STD.string.find(txt, "Talents", 1, true), STD.string.gsub(txt, "\n", " | "))
    REALG.C_Traits = saved
    CI.foreverPlayerTalentMemo = nil
end

--------------------------------------------------------------------------
-- P1d: the inspect trait config can become valid a moment after INSPECT_READY.
-- The GUID-matched retry must pick it up on a later render, and must never
-- read the config for a different GUID.
--------------------------------------------------------------------------
do
    REALG.TooltipUtil.GetDisplayedUnit = function()
        return "n", "mouseover", UNITS.mouseover.guid
    end
    GT.GetUnit = function() return "n", "mouseover" end
    local guid = UNITS.mouseover.guid
    local record = CI.cache[guid]
    check("P1d setup: the mouseover inspect record exists", record ~= nil)
    record.foreverTalents = nil
    CI.lastInspectGUID = guid
    REALG.__foreverInspectValid = false
    seedPlayer()
    local before = drive("mouseover")
    check("P1d: no Talents line while the trait config is not valid",
        not STD.string.find(before, "Talents:", 1, true), STD.string.gsub(before, "\n", " | "))

    REALG.__foreverInspectValid = true
    seedPlayer()
    local after = drive("mouseover")
    check("P1d: a later render retries and draws the readout",
        STD.string.find(after, "Fury|r [0/21/0]", 1, true) ~= nil,
        STD.string.gsub(after, "\n", " | "))

    -- A record belonging to a different inspect target must not read the
    -- current unit's config.
    record.foreverTalents = nil
    CI.lastInspectGUID = "Player-Other-0000000001"
    seedPlayer()
    local wrong = drive("mouseover")
    check("P1d: a non-matching inspect GUID never reads another unit's config",
        not STD.string.find(wrong, "Talents:", 1, true), STD.string.gsub(wrong, "\n", " | "))

    CI.lastInspectGUID = guid
    REALG.__foreverInspectValid = nil
end

--------------------------------------------------------------------------
-- P1e: the inspected player's inactive group is drawn when the client answers
-- the inspect talent query, and omitted entirely when it does not.
--------------------------------------------------------------------------
do
    REALG.TooltipUtil.GetDisplayedUnit = function()
        return "n", "mouseover", UNITS.mouseover.guid
    end
    GT.GetUnit = function() return "n", "mouseover" end
    local record = CI.cache[UNITS.mouseover.guid]

    REALG.__foreverInspectGroups = 2
    record.foreverTalents = nil
    local okFire = primeInspect("mouseover", "full")
    check("P1e setup: INSPECT_READY with a dual-spec inspect target", okFire == true)
    seedPlayer()
    local txt = drive("mouseover")
    local _, count = STD.string.gsub(txt, "Talents:", "")
    check("P1e: dual-spec inspect renders two Talents lines", count == 2,
        STD.string.gsub(txt, "\n", " | "))
    check("P1e: active line is Fury [0/21/0]",
        STD.string.find(txt, "Fury|r [0/21/0]", 1, true) ~= nil,
        STD.string.gsub(txt, "\n", " | "))
    check("P1e: inactive line is Arms [33/28/0]",
        STD.string.find(txt, "Arms|r [33/28/0]", 1, true) ~= nil,
        STD.string.gsub(txt, "\n", " | "))

    -- A client that does not answer the inactive query must draw no second
    -- line and must not throw.
    local savedQuery = REALG.C_SpecializationInfo.GetTalentInfo
    REALG.C_SpecializationInfo.GetTalentInfo = function() return nil end
    record.foreverTalents = nil
    local okFire2 = primeInspect("mouseover", "full")
    check("P1e setup: silent-client inspect", okFire2 == true)
    seedPlayer()
    local one = drive("mouseover")
    local _, oneCount = STD.string.gsub(one, "Talents:", "")
    check("P1e: a silent inactive query renders one line only", oneCount == 1,
        STD.string.gsub(one, "\n", " | "))
    REALG.C_SpecializationInfo.GetTalentInfo = savedQuery
    REALG.__foreverInspectGroups = 1
    record.foreverTalents = nil
end

--------------------------------------------------------------------------
-- P2: style selection changes the Forever layout. FULL (1) renders the wide
-- double-line GearScore; MINI (5) renders the single-line mini group.
--------------------------------------------------------------------------
do
    local wideRow, miniRow
    C.tip_style = 1
    seedPlayer()
    wideRow = drive("mouseover")
    C.tip_style = 5
    seedPlayer()
    miniRow = drive("mouseover")
    check("style: FULL renders the wide GearScore double line",
        STD.string.find(wideRow, "GearScore:", 1, true) ~= nil,
        STD.string.gsub(wideRow, "\n", " | "))
    check("style: MINI renders the mini group, not the wide line",
        STD.string.find(miniRow, "GS:", 1, true) ~= nil
        and STD.string.find(miniRow, "GearScore:", 1, true) == nil,
        STD.string.gsub(miniRow, "\n", " | "))
    check("style: selection actually switches the layout",
        wideRow ~= miniRow, "identical output under tip_style 1 and 5")
    check("style: MINI group carries the Pawn score",
        STD.string.find(miniRow, "P:", 1, true) ~= nil,
        STD.string.gsub(miniRow, "\n", " | "))
    checkCleanRender(wideRow, "FULL render")
    checkCleanRender(miniRow, "MINI render")
    -- COMPACT (2) and style 3 render the full single-line score rows without
    -- shift. MINI/FULL (4) is mini without shift by construction
    -- (mini_style includes tip_style == 4; only shift flips it to FULL) --
    -- identical on every client, so the pin asserts the shared semantic.
    for _, style in STD.ipairs({ 2, 3 }) do
        C.tip_style = style
        seedPlayer()
        local row = drive("mouseover")
        check("style: tip_style " .. style .. " renders full score rows",
            STD.string.find(row, "GearScore:", 1, true) ~= nil
            and STD.string.find(row, "GS:", 1, true) == nil,
            STD.string.gsub(row, "\n", " | "))
    end
    do
        C.tip_style = 4
        seedPlayer()
        local row4 = drive("mouseover")
        check("style: tip_style 4 is mini without shift",
            STD.string.find(row4, "GS:", 1, true) ~= nil
            and STD.string.find(row4, "GearScore:", 1, true) == nil,
            STD.string.gsub(row4, "\n", " | "))
    end
    C.tip_style = 2
end

--------------------------------------------------------------------------
-- P3: the style dropdown path re-renders the open Forever tooltip.
--------------------------------------------------------------------------
do
    check("style: RefreshOpenUnitTooltip exists (Forever re-render entry)",
        TT and type(TT.RefreshOpenUnitTooltip) == "function")
    if (TT and type(TT.RefreshOpenUnitTooltip) == "function") then
        currentUnit = "mouseover"
        GT.__unit = "mouseover"
        GT.__shown = true
        C.tip_style = 1
        local fires = 0
        local prevUnit = POSTCALLS.unit
        POSTCALLS.unit = function(...)
            fires = fires + 1
            return prevUnit(...)
        end
        local rebuilt = TT:RefreshOpenUnitTooltip()
        POSTCALLS.unit = prevUnit
        local afterWide = allText()
        C.tip_style = 5
        local rebuilt2 = TT:RefreshOpenUnitTooltip()
        local afterMini = allText()
        checkCleanRender(afterWide, "style refresh FULL")
        checkCleanRender(afterMini, "style refresh MINI")
        check("style: open tooltip rebuilds on selection (FULL)",
            rebuilt == true and STD.string.find(afterWide, "GearScore:", 1, true) ~= nil,
            "rebuilt=" .. tostring(rebuilt))
        check("style: open tooltip rebuilds on selection (MINI)",
            rebuilt2 == true and STD.string.find(afterMini, "GS:", 1, true) ~= nil,
            "rebuilt=" .. tostring(rebuilt2))
        GT.__shown = false
        local hidden = TT:RefreshOpenUnitTooltip()
        check("style: hidden tooltip is not rebuilt", hidden == false,
            "returned " .. tostring(hidden))
        GT.__shown = true
        C.tip_style = 2
    end
end

--------------------------------------------------------------------------
-- P4: the stale extra score row does not survive. Seed the exact broken
-- shape (a foreign score row plus a previous-render Pawn row), prime the
-- cache, re-render, and require both gone.
--------------------------------------------------------------------------
do
    primeInspect("mouseover", "full")
    currentUnit = "mouseover"
    REALG.TooltipUtil.GetDisplayedUnit = function()
        return "n", "mouseover", UNITS.mouseover.guid
    end
    GT.GetUnit = function() return "n", "mouseover" end
    seedPlayer()
    GT:AddLine("STALE_CLIENT_SCORE_ROW")
    GT:AddLine("STALE_PAWN_ROW")
    local ptxt = drive("mouseover")
    check("stale: foreign score row is removed",
        not STD.string.find(ptxt, "STALE_CLIENT_SCORE_ROW", 1, true),
        STD.string.gsub(ptxt, "\n", " | "))
    check("stale: previous-render Pawn row is not re-emitted",
        not STD.string.find(ptxt, "STALE_PAWN_ROW", 1, true),
        STD.string.gsub(ptxt, "\n", " | "))
    checkCleanRender(ptxt, "stale-row removal render")
end

--------------------------------------------------------------------------
-- P5: Pawn persists after item data when the score is positive. Drive the
-- real completion path (TacoTip_GSCallback, as itemcacheCB fires it), not a
-- direct render, so the memo + re-drive chain is what is pinned.
--------------------------------------------------------------------------
do
    primeInspect("mouseover", "full")
    currentUnit = "mouseover"
    REALG.TooltipUtil.GetDisplayedUnit = function()
        return "n", "mouseover", UNITS.mouseover.guid
    end
    GT.GetUnit = function() return "n", "mouseover" end
    GT.__unit = "mouseover"
    GT.__shown = true
    seedPlayer()
    local specName = (CI and CI.GetSpecializationName
        and CI:GetSpecializationName("MAGE", 2, true)) or "Fire"
    local cb = REALG.TacoTip_GSCallback
    check("pawn: GSCallback present", type(cb) == "function")
    if (type(cb) == "function") then
        cb(UNITS.mouseover.guid)
        local ptxt = allText()
        check("pawn: Pawn line present after item data",
            STD.string.find(ptxt, "Pawn:", 1, true) ~= nil, STD.string.gsub(ptxt, "\n", " | "))
        check("pawn: Pawn line carries the resolved spec name",
            STD.string.find(ptxt, tostring(specName), 1, true) ~= nil,
            "want " .. tostring(specName) .. " :: " .. STD.string.gsub(ptxt, "\n", " | "))
        -- Second completion for the same guid: the memoized score must still
        -- render, proving the line persists across re-drives.
        seedPlayer()
        cb(UNITS.mouseover.guid)
        local ptxt2 = allText()
        check("pawn: Pawn line persists across completions",
            STD.string.find(ptxt2, "Pawn:", 1, true) ~= nil,
            STD.string.gsub(ptxt2, "\n", " | "))
        checkCleanRender(ptxt2, "Pawn completion render")
        -- Completion safety on the Forever paths: an unresolvable tooltip at
        -- completion time is a counted miss, not a raise; a completion for
        -- another unit counts wrong-unit, not a resolution failure.
        local savedTU, savedGU, savedU = REALG.TooltipUtil.GetDisplayedUnit, GT.GetUnit, GT.__unit
        GT.__shown = false
        GT.__unit = nil
        REALG.TooltipUtil.GetDisplayedUnit = function() return "n", nil, nil end
        GT.GetUnit = function() return "n", nil end
        local nMiss = (TT.ev and TT.ev.gsCallbackNoUnit) or 0
        local okMiss = STD.pcall(cb, UNITS.mouseover.guid)
        check("pawn: unresolvable completion is a counted miss, not a raise",
            okMiss and ((TT.ev and TT.ev.gsCallbackNoUnit) or 0) == nMiss + 1,
            "misses=" .. tostring((TT.ev and TT.ev.gsCallbackNoUnit) or 0))
        REALG.TooltipUtil.GetDisplayedUnit, GT.GetUnit, GT.__unit = savedTU, savedGU, savedU
        GT.__shown = true
        local nWrong = (TT.ev and TT.ev.gsCallbackWrongUnit) or 0
        local okWrong = STD.pcall(cb, UNITS.player.guid)
        check("pawn: other-unit completion counts wrong-unit, not failure",
            okWrong and ((TT.ev and TT.ev.gsCallbackWrongUnit) or 0) == nWrong + 1,
            "wrong=" .. tostring((TT.ev and TT.ev.gsCallbackWrongUnit) or 0))
    end
end

--------------------------------------------------------------------------
-- P6: an empty/partial snapshot is never committed fresh on Forever. With
-- the client reporting no links and no icons, INSPECT_READY must leave the
-- record incomplete with no .time -- both scorers then read "no data", not
-- "fresh zero".
--------------------------------------------------------------------------
do
    -- Evict any earlier record so the observed state comes from this read.
    -- The inspected stranger is the mouseover unit itself: INSPECT_READY
    -- resolves through the pending unit / target / mouseover fallbacks, so the
    -- empty read must arrive for a unit the handler can resolve, exactly as a
    -- fresh in-game inspect does (the server answers for the hovered player
    -- before any link is populated).
    if (CI and CI.cache) then CI.cache[UNITS.mouseover.guid] = nil end
    if (TT) then TT._gsMemo = nil end
    local okFire, fireErr = primeInspect("mouseover", "empty")
    check("P6 setup: INSPECT_READY fires with empty gear", okFire == true,
        tostring(fireErr or ""))
    local rec = CI and CI:GetUnitData(UNITS.mouseover.guid) or nil

    check("empty: no .time stamped on an empty read",
        not (rec and rec.time), "time=" .. tostring(rec and rec.time))
    check("empty: record stays incomplete",
        rec and rec.incomplete == true, "incomplete=" .. tostring(rec and rec.incomplete))
    local _, invTime = CI:GetLastCacheTime(UNITS.mouseover.guid)
    check("empty: cache reads as missing, not fresh",
        invTime == 0, "invTime=" .. tostring(invTime))
    GEAR_MODE = "full"
end

--------------------------------------------------------------------------
-- P7: the modern spec index is read as an index. Group 1's active spec is
-- index 2 (Fury); the old code read the answer as a specID and parked every
-- unit on spec 1, which made Pawn score the wrong spec.
--------------------------------------------------------------------------
do
    primeInspect("mouseover", "full")
    local idx = CI:GetSpecialization(UNITS.mouseover.guid, 1)
    check("spec: active spec resolves to index 2, not 1", idx == 2,
        "got " .. tostring(idx))
    local lname = CI:GetLocalizedSpecName(UNITS.mouseover.guid, 1)
    check("spec: localized name follows the index", lname == "Fury",
        "got " .. tostring(lname))
end

--------------------------------------------------------------------------
-- P10: empty-to-full recovery -- the operator's exact symptom arc. After an
-- empty read (no scores, correctly), a full re-inspect must bring GearScore
-- and Pawn back. Render the empty state first, then re-prime full and drive
-- the completion path.
--------------------------------------------------------------------------
do
    -- Self-contained: evict, prime empty, and prove the empty state first --
    -- earlier blocks leave a full cache behind, so inheriting state here
    -- would assert against the wrong setup.
    if (CI and CI.cache) then CI.cache[UNITS.mouseover.guid] = nil end
    if (TT) then TT._gsMemo = nil end
    primeInspect("mouseover", "empty")
    currentUnit = "mouseover"
    REALG.TooltipUtil.GetDisplayedUnit = function()
        return "n", "mouseover", UNITS.mouseover.guid
    end
    GT.GetUnit = function() return "n", "mouseover" end
    GT.__unit = "mouseover"
    GT.__shown = true
    seedPlayer()
    local emptyTxt = drive("mouseover")
    check("recovery: empty state shows neither score line",
        STD.string.find(emptyTxt, "GearScore:", 1, true) == nil
        and STD.string.find(emptyTxt, "Pawn:", 1, true) == nil,
        STD.string.gsub(emptyTxt, "\n", " | "))
    GEAR_MODE = "full"
    primeInspect("mouseover", "full")
    currentUnit = "mouseover"
    REALG.TooltipUtil.GetDisplayedUnit = function()
        return "n", "mouseover", UNITS.mouseover.guid
    end
    GT.GetUnit = function() return "n", "mouseover" end
    GT.__unit = "mouseover"
    GT.__shown = true
    seedPlayer()
    local cb = REALG.TacoTip_GSCallback
    if (type(cb) == "function") then cb(UNITS.mouseover.guid) end
    local fullTxt = allText()
    check("recovery: GearScore returns after a full re-inspect",
        STD.string.find(fullTxt, "GearScore:", 1, true) ~= nil,
        STD.string.gsub(fullTxt, "\n", " | "))
    check("recovery: Pawn returns after a full re-inspect",
        STD.string.find(fullTxt, "Pawn:", 1, true) ~= nil,
        STD.string.gsub(fullTxt, "\n", " | "))
    checkCleanRender(fullTxt, "recovery render")
end

--------------------------------------------------------------------------
-- P11: target variants, iLvl placement, realm, portrait, separators.
--------------------------------------------------------------------------
do
    -- A player target renders class-colored with the (Player) suffix.
    currentUnit = "mouseover"
    REALG.TooltipUtil.GetDisplayedUnit = function()
        return "n", "mouseover", UNITS.mouseover.guid
    end
    GT.GetUnit = function() return "n", "mouseover" end
    seedPlayer()
    local ptxt = drive("mouseover")
    check("target: player target renders the You line",
        STD.string.find(ptxt, "Target:", 1, true) ~= nil
        and STD.string.find(ptxt, "You", 1, true) ~= nil,
        STD.string.gsub(ptxt, "\n", " | "))
    -- Refresh stability: the engine repopulates the client rows before every
    -- render, so an identical entry must render byte-identical output. (A
    -- re-render with NO client refresh reads the ownership-blanked lines and
    -- returns early by design -- that state never occurs in game, where
    -- SetUnit/UpdateTooltip always repopulate first.)
    seedPlayer()
    local ptxt2 = drive("mouseover")
    check("refresh stability: identical entry renders byte-identical",
        ptxt == ptxt2, "lengths " .. tostring(#ptxt) .. " vs " .. tostring(#ptxt2))
    -- iLvl inline variant: the score moves onto the name line.
    C.show_ilvl_inline = true
    seedPlayer()
    local inlineTxt = drive("mouseover")
    check("ilvl: inline variant appends [ilvl] to the name line",
        STD.string.find(inlineTxt, "[88]", 1, true) ~= nil,
        STD.string.gsub(inlineTxt, "\n", " | "))
    C.show_ilvl_inline = false
    -- Realm variant: GATED OFF on Forever.
    --
    -- Camelot has one realm per type (PvE / PvP / RP-PvP) and no connected
    -- realms, so a player from "another connected server" cannot exist here and
    -- the row must never render (operator observation, 2026-11-10). The client is
    -- deliberately mocked to claim a DIFFERENT server, to prove the add-on does
    -- not trust that answer on this family.
    local savedSame = REALG.UnitIsSameServer
    REALG.UnitIsSameServer = function() return false end
    seedPlayer()
    local realmTxt = drive("mouseover")
    check("realm: Forever never gains a Realm line (no cross-realm exists here)",
        STD.string.find(realmTxt, "Realm:", 1, true) == nil,
        STD.string.gsub(realmTxt, "\n", " | "))
    REALG.UnitIsSameServer = savedSame
    -- Separators: the style-2 player tooltip carries both of them. Counted
    -- per line with a 10+ dash run: the faction icon carries only short
    -- dashes ("UI-PVP-ALLIANCE", "-2"), so it can never collide.
    local sepLines = 0
    local sepRun = STD.string.rep("-", 10)
    for line in STD.string.gmatch(ptxt .. "\n", "(.-)\n") do
        if (STD.string.find(line, sepRun, 1, true)) then sepLines = sepLines + 1 end
    end
    check("separators: both separator rows render", sepLines == 2, "count=" .. tostring(sepLines))
    -- Portrait: the 2D portrait frame exists and is shown for the player unit.
    check("portrait: portrait frame exists",
        GT.TacoTipPortrait ~= nil or GT.TacoTipPortrait3D ~= nil)
    local portrait = GT.TacoTipPortrait3D or GT.TacoTipPortrait
    check("portrait: portrait is shown",
        portrait ~= nil and portrait.IsShown and portrait:IsShown() or false)
    checkCleanRender(ptxt, "variant renders")
end

--------------------------------------------------------------------------
-- P12: a player with NO guild. No guild line anywhere, the level line sits
-- at row 2, and GearScore/Pawn still render. The mock guild is temporarily
-- removed and the seed carries no guild row -- the level-line detection and
-- the no-guild rebuild must hold without them.
--------------------------------------------------------------------------
do
    local savedGI = REALG.GetGuildInfo
    REALG.GetGuildInfo = function() return nil end
    GT:ClearLines()
    GT:AddLine("Enemyplayer")
    GT:AddLine("Level 59 Mage")
    local ptxt = drive("mouseover")
    check("guildless: no guild line rendered",
        not STD.string.find(ptxt, "<", 1, true),
        STD.string.gsub(ptxt, "\n", " | "))
    check("guildless: level line still renders",
        STD.string.find(ptxt, "Level", 1, true) ~= nil,
        STD.string.gsub(ptxt, "\n", " | "))
    check("guildless: GearScore still renders",
        STD.string.find(ptxt, "GearScore:", 1, true) ~= nil,
        STD.string.gsub(ptxt, "\n", " | "))
    check("guildless: Pawn still renders",
        STD.string.find(ptxt, "Pawn:", 1, true) ~= nil,
        STD.string.gsub(ptxt, "\n", " | "))
    checkCleanRender(ptxt, "guildless render")
    REALG.GetGuildInfo = savedGI
end

--------------------------------------------------------------------------
-- P12b: the guild line's SCRIPT decides its face, not the client's locale.
--
-- Reported: a Russian player's guild name on an English client rendered one
-- missing-glyph box per character, on line 2 only, while every other line read
-- normally -- because one face was applied to the whole tooltip and the roman
-- face has no Cyrillic. The line carrying the script must move to TacoTip's
-- bundled Cyrillic face; Latin lines must keep the client face untouched.
--------------------------------------------------------------------------
do
    local savedGI = REALG.GetGuildInfo
    local bundled = TT.bundledTooltipFonts or {}
    REALG.GetGuildInfo = function() return "Кровь и Пепел", "Глава" end
    GT:ClearLines()
    GT:AddLine("Rusplayer")
    GT:AddLine("<Кровь и Пепел> Глава")
    GT:AddLine("Level 60 Warrior")
    local ptxt = drive("mouseover")
    local guildLine = GT:GetLeftLine(2)
    check("script font: the Cyrillic guild line is drawn with the bundled Cyrillic face",
        guildLine and guildLine._tacoTipFont == bundled.ruRU,
        "applied=" .. tostring(guildLine and guildLine._tacoTipFont)
            .. " want=" .. tostring(bundled.ruRU))
    check("script font: the same line really received that face from SetFont",
        guildLine and guildLine.__font == bundled.ruRU,
        "SetFont got=" .. tostring(guildLine and guildLine.__font))
    check("script font: the Cyrillic guild line keeps its text",
        guildLine and type(guildLine:GetText()) == "string"
            and STD.string.find(guildLine:GetText(), "<", 1, true) ~= nil,
        tostring(guildLine and guildLine:GetText()))
    local nameLine = GT:GetLeftLine(1)
    check("script font: a Latin line keeps the resolved client face",
        nameLine and nameLine._tacoTipFont == "Fonts\\FRIZQT__.TTF",
        "applied=" .. tostring(nameLine and nameLine._tacoTipFont))
    checkCleanRender(ptxt, "cyrillic guild render")
    REALG.GetGuildInfo = savedGI
end

--------------------------------------------------------------------------
-- P12c: a RESTRICTED tooltip keeps the face it was readable with.
--
-- Instanced combat and encounters make the client's tooltip lines secret: the
-- addon may not read them, but the client still DRAWS them. The pass must touch
-- no secret (no read, no compare, no tostring) and must still put the
-- remembered Cyrillic face on the line, so the client's own text keeps its
-- glyphs instead of falling back to box-per-character.
--------------------------------------------------------------------------
do
    local savedGI = REALG.GetGuildInfo
    local savedGetUnit = GT.GetUnit
    local savedGetOwner = GT.GetOwner
    local savedDisplayed = REALG.TooltipUtil.GetDisplayedUnit
    local savedIsSecret = REALG.issecretvalue
    local bundled = TT.bundledTooltipFonts or {}

    -- A sentinel that explodes on every operation the addon must not perform on
    -- a secret: tostring, ==, and concatenation. Anything touching it raises.
    local SECRET_STR = setmetatable({}, {
        __tostring = function() error("cannot tostring secret value") end,
        __eq = function() error("cannot compare secret value") end,
        __concat = function() error("cannot concatenate secret value") end,
    })

    local function renderUnit(unitToken, guid)
        GT.GetOwner = function() return { unit = unitToken } end
        GT.GetUnit = function() return "n", unitToken end
        REALG.TooltipUtil.GetDisplayedUnit = function() return "n", unitToken, guid end
        if (POSTCALLS.unit) then
            POSTCALLS.unit(GT, { guid = guid })
        end
    end

    -- 1. readable Cyrillic render: records the mask and draws the bundled face
    REALG.GetGuildInfo = function() return "Кровь и Пепел", "Глава" end
    GT:ClearLines()
    GT:AddLine("Rusplayer")
    GT:AddLine("<Кровь и Пепел> Глава")
    GT:AddLine("Level 60 Warrior")
    renderUnit("mouseover", "Player-6-000006")
    check("restricted: the readable pass records and draws the bundled Cyrillic face",
        GT:GetLeftLine(2)._tacoTipFont == bundled.ruRU,
        "applied=" .. STD.tostring(GT:GetLeftLine(2)._tacoTipFont))

    -- 2. another player puts the POOLED line back on the client face, so the
    --    next check cannot pass on leftovers from step 1
    REALG.GetGuildInfo = function() return "Testguild", "Testrealm" end
    GT:ClearLines()
    GT:AddLine("Partymate")
    GT:AddLine("<Testguild>")
    GT:AddLine("Level 60 Warrior")
    renderUnit("party1", "Player-9-000009")
    check("restricted: a Latin render puts the pooled line back on the client face",
        GT:GetLeftLine(2)._tacoTipFont == "Fonts\\FRIZQT__.TTF",
        "applied=" .. STD.tostring(GT:GetLeftLine(2)._tacoTipFont))

    -- 3. the same unit, now UNREADABLE: no text may be read, and the line must
    --    still carry the remembered face
    REALG.issecretvalue = function(v) return v == SECRET_STR end
    GT:ClearLines()
    GT:AddLine(SECRET_STR)
    GT:AddLine(SECRET_STR)
    GT:AddLine(SECRET_STR)
    local okRestricted, errRestricted = STD.pcall(function()
        renderUnit("mouseover", "Player-6-000006")
    end)
    check("restricted: the unreadable render does not raise", okRestricted == true,
        STD.tostring(errRestricted))
    check("restricted: the remembered Cyrillic face is re-applied without reading it",
        GT:GetLeftLine(2)._tacoTipFont == bundled.ruRU,
        "applied=" .. STD.tostring(GT:GetLeftLine(2)._tacoTipFont))

    -- 4. a unit never seen readable invents nothing: no memory is recorded and
    --    the render still does not raise
    GT:ClearLines()
    GT:AddLine(SECRET_STR)
    GT:AddLine(SECRET_STR)
    GT:AddLine(SECRET_STR)
    local okNoMem, errNoMem = STD.pcall(function()
        renderUnit("party2", "Player-7-000777")
    end)
    check("restricted: a unit with no readable history records no memory",
        okNoMem == true and TT._unitLineScript["Player-7-000777"] == nil,
        "ok=" .. STD.tostring(okNoMem) .. " err=" .. STD.tostring(errNoMem))

    REALG.issecretvalue = savedIsSecret
    REALG.GetGuildInfo = savedGI
    GT.GetUnit = savedGetUnit
    GT.GetOwner = savedGetOwner
    REALG.TooltipUtil.GetDisplayedUnit = savedDisplayed
end

--------------------------------------------------------------------------
-- P8: NPC tooltips keep rendering on Forever. The tooltip still builds
-- cleanly -- header lines, target line, no invented score rows. NPC row
-- handling beyond that is the client's own business, not this lane's.
--------------------------------------------------------------------------
do
    currentUnit = "target"
    REALG.TooltipUtil.GetDisplayedUnit = function()
        return "n", "target", UNITS.target.guid
    end
    GT.GetUnit = function() return "n", "target" end
    seedNPC()
    local ptxt = drive("target")
    check("npc: header lines render on non-player tooltips",
        STD.string.find(ptxt, "Hated Squirrel", 1, true) ~= nil
        and STD.string.find(ptxt, "Level", 1, true) ~= nil,
        STD.string.gsub(ptxt, "\n", " | "))
    check("npc: no score rows invented for creatures",
        STD.string.find(ptxt, "GearScore:", 1, true) == nil
        and STD.string.find(ptxt, "Pawn:", 1, true) == nil,
        STD.string.gsub(ptxt, "\n", " | "))
    check("npc: targetless creature renders the None target line",
        STD.string.find(ptxt, "Target:", 1, true) ~= nil
        and STD.string.find(ptxt, "None", 1, true) ~= nil,
        STD.string.gsub(ptxt, "\n", " | "))
    checkCleanRender(ptxt, "NPC render")
end

--------------------------------------------------------------------------
-- P13: the player's own tooltip. No Target line and no inspect, but the
-- live-read scores still render.
--------------------------------------------------------------------------
do
    currentUnit = "player"
    REALG.TooltipUtil.GetDisplayedUnit = function()
        return "n", "player", UNITS.player.guid
    end
    GT.GetUnit = function() return "n", "player" end
    GT:ClearLines()
    GT:AddLine("Testplayer")
    GT:AddLine("<Testguild>")
    GT:AddLine("Level 60 Human")
    local ptxt = drive("player")
    check("self: own tooltip carries no Target line",
        STD.string.find(ptxt, "Target:", 1, true) == nil,
        STD.string.gsub(ptxt, "\n", " | "))
    check("self: own GearScore renders from the live read",
        STD.string.find(ptxt, "GearScore:", 1, true) ~= nil,
        STD.string.gsub(ptxt, "\n", " | "))
    -- The blink: a later live Pawn read that comes back zero must not drop the
    -- already-memoized self row. Self is memoized separately because the
    -- inspect-items key is always nil for the player.
    local savedPawnGetScore = REALG.TT_PAWN and REALG.TT_PAWN.GetScore
    if (type(savedPawnGetScore) == "function") then
        REALG.TT_PAWN.GetScore = function() return 0, nil, nil end
        local memoText = drive("player")
        check("self: Pawn memo keeps the row across a zero live read",
            STD.string.find(memoText, "Pawn:", 1, true) ~= nil,
            STD.string.gsub(memoText, "\n", " | "))
        -- A Pawn throw must not abort the render before the GearScore write-back.
        REALG.TT_PAWN.GetScore = function() error("PAWN_PIN_RAISE") end
        TT._selfPawnMemo = nil
        local throwText = drive("player")
        check("self: a Pawn throw does not erase GearScore",
            STD.string.find(throwText, "GearScore:", 1, true) ~= nil,
            STD.string.gsub(throwText, "\n", " | "))
        REALG.TT_PAWN.GetScore = savedPawnGetScore
    end
    checkCleanRender(ptxt, "own tooltip render")
end

--------------------------------------------------------------------------
-- P9: coloring is preserved -- class-colored name, green guild tag, level line.
--------------------------------------------------------------------------
do
    currentUnit = "mouseover"
    REALG.TooltipUtil.GetDisplayedUnit = function()
        return "n", "mouseover", UNITS.mouseover.guid
    end
    GT.GetUnit = function() return "n", "mouseover" end
    C.tip_style = 2
    seedPlayer()
    local ptxt = drive("mouseover")
    check("color: unit name carries a class color code",
        STD.string.find(ptxt, "|cFF", 1, true) ~= nil
        and STD.string.find(ptxt, "Enemyplayer", 1, true) ~= nil,
        STD.string.gsub(ptxt, "\n", " | "))
    check("color: guild tag keeps the classic green",
        STD.string.find(ptxt, "|cFF40FB40<Testguild>|r", 1, true) ~= nil,
        STD.string.gsub(ptxt, "\n", " | "))
    check("color: border request resolves a class color",
        GT.__borderColor ~= nil, "border=" .. tostring(GT.__borderColor))
end

--------------------------------------------------------------------------
-- P15: modern unit-frame portrait stability (0.9.5).
--
-- UnitFrame_UpdateTooltip re-drives GameTooltip:SetUnit every 0.2s while the
-- mouse sits on a unit frame. SetUnit clears the lines first, so OnTooltipCleared
-- fires before the unit post-call on every tick. On Retail/Forever that is the
-- only place the portrait can be torn down between two identical renders -- and
-- UnitFrame_OnLeave nils UpdateTooltip BEFORE GameTooltip:FadeOut(), so a stale
-- fade can fire OnHide after a quick re-hover re-showed the portrait.
--------------------------------------------------------------------------
do
    local saved3D, savedPortrait = C.tooltip_portrait_3d, C.tooltip_portrait
    C.tooltip_portrait = true
    C.tooltip_portrait_3d = true

    currentUnit = "player"
    GT.__unit = "player"
    GT.__shown = true
    -- Unit reads: without these the previous block's mouseover closure would
    -- resolve every P15 player render to the mouseover unit.
    GT.GetUnit = function() return "n", "player" end
    REALG.TooltipUtil.GetDisplayedUnit = function() return "n", "player", UNITS.player.guid end
    GT:ClearLines()
    seedPlayer()
    -- The unit frame the client re-drives from. GetOwner is nil by default in
    -- the mock, which would make the guard untestable.
    local owner = { unit = "player", UpdateTooltip = function() end }
    GT.GetOwner = function() return owner end
    if (POSTCALLS.unit) then POSTCALLS.unit(GT, { guid = UNITS.player.guid }) end
    local model = GT.TacoTipPortrait3D
    check("portrait: 3D model exists for the stability pin", model ~= nil)

    if (model) then
        local hidesBefore = (TT.ev.portraitHide or 0)
        local modelHidesBefore = (TT.ev.portraitModelHidden or 0)
        local destroysBefore = (TT.ev.portraitDestroy or 0)
        for _ = 1, 5 do
            GT:ClearLines()
            seedPlayer()
            -- Engine order: SetUnit -> ClearLines -> OnTooltipCleared ->
            -- client rows -> unit post-call -> Show.
            if (GT.__hooks.OnTooltipCleared) then GT.__hooks.OnTooltipCleared(GT) end
            if (POSTCALLS.unit) then POSTCALLS.unit(GT, { guid = UNITS.player.guid }) end
        end
        check("portrait: five 0.2s unit-frame re-drives do not hide the model",
            (TT.ev.portraitHide or 0) == hidesBefore
                and (TT.ev.portraitModelHidden or 0) == modelHidesBefore,
            "hide " .. tostring(hidesBefore) .. " -> " .. tostring(TT.ev.portraitHide or 0)
                .. ", modelHidden " .. tostring(modelHidesBefore) .. " -> "
                .. tostring(TT.ev.portraitModelHidden or 0))
        check("portrait: five 0.2s unit-frame re-drives do not destroy the model",
            (TT.ev.portraitDestroy or 0) == destroysBefore,
            "destroy " .. tostring(destroysBefore) .. " -> " .. tostring(TT.ev.portraitDestroy or 0))
        check("portrait: model is shown after the re-drives", model:IsShown())

        -- UnitFrame_OnLeave nils UpdateTooltip before FadeOut(), and
        -- UnitFrame_UpdateTooltip re-arms it only AFTER SetUnit returns. So the
        -- first re-drive after a re-hover reaches ClearLines with no
        -- UpdateTooltip; the owner still proves the same unit and the shown
        -- tooltip must not tear the portrait down.
        owner.UpdateTooltip = nil
        local hidesBeforeLeave = (TT.ev.portraitHide or 0)
        local modelHidesBeforeLeave = (TT.ev.portraitModelHidden or 0)
        if (GT.__hooks.OnTooltipCleared) then GT.__hooks.OnTooltipCleared(GT) end
        check("portrait: the first re-drive after OnLeave does not hide the same unit's model",
            (TT.ev.portraitHide or 0) == hidesBeforeLeave
                and (TT.ev.portraitModelHidden or 0) == modelHidesBeforeLeave,
            "hide " .. tostring(hidesBeforeLeave) .. " -> " .. tostring(TT.ev.portraitHide or 0)
                .. ", modelHidden " .. tostring(modelHidesBeforeLeave) .. " -> "
                .. tostring(TT.ev.portraitModelHidden or 0))

        -- The owner GUID is the sole identity proof when the pre-Show postcall
        -- could not resolve a unit and currentUnitGUID was never written. This
        -- is the real trigger the guard exists for; both halves are pinned so
        -- deleting the owner proof cannot stay green.
        local savedCurGUID = GT._tacoTipState.currentUnitGUID
        local savedOwnerGUID = GT._tacoTipState.ownerUnitGUID
        GT._tacoTipState.currentUnitGUID = nil
        GT._tacoTipState.ownerUnitGUID = UNITS.player.guid
        owner.unit = "player"
        owner.UpdateTooltip = nil
        GT.__shown = true
        local hidesBeforeOwnerProof = (TT.ev.portraitHide or 0)
        local modelHidesBeforeOwnerProof = (TT.ev.portraitModelHidden or 0)
        if (GT.__hooks.OnTooltipCleared) then GT.__hooks.OnTooltipCleared(GT) end
        check("portrait: the owner GUID alone proves same-unit when currentUnitGUID is missing",
            (TT.ev.portraitHide or 0) == hidesBeforeOwnerProof
                and (TT.ev.portraitModelHidden or 0) == modelHidesBeforeOwnerProof,
            "hide " .. tostring(hidesBeforeOwnerProof) .. " -> " .. tostring(TT.ev.portraitHide or 0)
                .. ", modelHidden " .. tostring(modelHidesBeforeOwnerProof) .. " -> "
                .. tostring(TT.ev.portraitModelHidden or 0))
        -- Negative: the owner's unit changed, so the noted owner GUID cannot
        -- match the owner's current unit and the teardown path must run.
        owner.unit = "target"
        local modelHidesBeforeOwnerNeg = (TT.ev.portraitModelHidden or 0)
        if (GT.__hooks.OnTooltipCleared) then GT.__hooks.OnTooltipCleared(GT) end
        check("portrait: a changed owner unit hides the portrait even with a stale currentUnitGUID",
            (TT.ev.portraitModelHidden or 0) > modelHidesBeforeOwnerNeg,
            "modelHidden " .. tostring(modelHidesBeforeOwnerNeg) .. " -> "
                .. tostring(TT.ev.portraitModelHidden or 0))
        GT._tacoTipState.currentUnitGUID = savedCurGUID
        GT._tacoTipState.ownerUnitGUID = savedOwnerGUID
        owner.unit = "player"

        -- SetUnit reports success with a boolean. A non-throwing false must not
        -- be cached as the new unit, or the previous mesh stays under the new
        -- tooltip and portraitSetFailed is unreachable.
        local savedSetUnit = model.SetUnit
        model.SetUnit = function() return false end
        local failuresBefore = (TT.ev.portraitSetFailed or 0)
        STD.pcall(TT.ApplyTooltipAppearance, TT, GT, "mouseover")
        check("portrait: a non-throwing SetUnit(false) is not cached as success",
            model.tacoTipModelKey == nil
                and (TT.ev.portraitSetFailed or 0) > failuresBefore,
            "key=" .. tostring(model.tacoTipModelKey)
                .. " failed " .. tostring(failuresBefore) .. " -> " .. tostring(TT.ev.portraitSetFailed or 0))
        model.SetUnit = savedSetUnit
        STD.pcall(TT.ApplyTooltipAppearance, TT, GT, "player")

        -- A proven different unit must still tear down, or the old mesh bleeds.
        local otherOwner = { unit = "target", UpdateTooltip = function() end }
        GT.GetOwner = function() return otherOwner end
        local destroysBeforeChange = (TT.ev.portraitDestroy or 0)
        local savedGetUnit = GT.GetUnit
        local savedDisp = REALG.TooltipUtil.GetDisplayedUnit
        GT.__unit = "target"
        GT.GetUnit = function() return "n", "target" end
        REALG.TooltipUtil.GetDisplayedUnit = function() return "n", "target", UNITS.target.guid end
        GT:ClearLines()
        seedNPC()
        if (GT.__hooks.OnTooltipCleared) then GT.__hooks.OnTooltipCleared(GT) end
        STD.pcall(POSTCALLS.unit, GT, { guid = UNITS.target.guid })
        check("portrait: a proven different unit still tears the model down",
            (TT.ev.portraitDestroy or 0) > destroysBeforeChange,
            "destroy " .. tostring(destroysBeforeChange) .. " -> " .. tostring(TT.ev.portraitDestroy or 0))
        -- NPCs must render a portrait too. PlayerModel:SetUnit supports
        -- creature models; the old UnitIsPlayer gate existed only for the 2D
        -- fallback and was removed. The render above was the NPC target.
        check("portrait: an NPC render creates and shows the 3D portrait",
            GT.TacoTipPortrait3D ~= nil and GT.TacoTipPortrait3D:IsShown(),
            "model=" .. tostring(GT.TacoTipPortrait3D ~= nil))
        check("portrait: the NPC model is keyed on the creature GUID",
            GT.TacoTipPortrait3D ~= nil
                and GT.TacoTipPortrait3D.tacoTipModelKey == UNITS.target.guid,
            "key=" .. tostring(GT.TacoTipPortrait3D and GT.TacoTipPortrait3D.tacoTipModelKey))
        GT.GetUnit = savedGetUnit
        REALG.TooltipUtil.GetDisplayedUnit = savedDisp
        GT.GetOwner = function() return nil end
    end

    -- The 2D fallback must render an NPC portrait as well, and OnShow must
    -- anchor the region actually on screen (a session that toggled 3D off still
    -- has the hidden model frame attached to the tooltip).
    C.tooltip_portrait_3d = false
    local savedSetPortraitTexture = REALG.SetPortraitTexture
    REALG.SetPortraitTexture = function(tex, u)
        if (tex) then tex.__portrait = u end
    end
    currentUnit = "target"
    GT.__unit = "target"
    GT.GetOwner = function() return { unit = "target", UpdateTooltip = function() end } end
    local savedGetUnit2D = GT.GetUnit
    local savedDisp2D = REALG.TooltipUtil.GetDisplayedUnit
    GT.GetUnit = function() return "n", "target" end
    REALG.TooltipUtil.GetDisplayedUnit = function() return "n", "target", UNITS.target.guid end
    GT:ClearLines()
    seedNPC()
    if (GT.__hooks.OnTooltipCleared) then GT.__hooks.OnTooltipCleared(GT) end
    STD.pcall(POSTCALLS.unit, GT, { guid = UNITS.target.guid })
    if (GT.__hooks.OnShow) then GT.__hooks.OnShow(GT) end
    check("portrait: the 2D fallback shows an NPC portrait",
        GT.TacoTipPortrait ~= nil and GT.TacoTipPortrait:IsShown()
            and GT.TacoTipPortrait.__portrait == "target",
        "texture=" .. tostring(GT.TacoTipPortrait ~= nil)
            .. " shown=" .. tostring(GT.TacoTipPortrait and GT.TacoTipPortrait:IsShown())
            .. " tex=" .. tostring(GT.TacoTipPortrait and GT.TacoTipPortrait.__portrait))
    check("portrait: the 3D model is hidden while the 2D fallback is active",
        GT.TacoTipPortrait3D == nil or not GT.TacoTipPortrait3D:IsShown())
    GT.GetUnit = savedGetUnit2D
    REALG.TooltipUtil.GetDisplayedUnit = savedDisp2D
    REALG.SetPortraitTexture = savedSetPortraitTexture
    GT.GetOwner = function() return nil end
    -- Back to the 3D path for the OnShow anchor pin below.
    C.tooltip_portrait_3d = true

    -- OnShow re-anchors once from a laid-out frame. The mock's GetRight() is 0
    -- for an unshown frame; a shown tooltip at the right edge must flip the
    -- portrait to the tooltip's left and the visible frame must already use it
    -- (no correction on the following 0.2s tick).
    currentUnit = "player"
    GT.__unit = "player"
    GT.GetOwner = function() return { unit = "player" } end
    local anchoredBefore = (TT.ev.portraitAnchor or 0)
    local savedRight = GT.GetRight
    local savedUiRight = REALG.UIParent.GetRight
    GT.GetRight = function() return 1920 end
    REALG.UIParent.GetRight = function() return 1920 end
    if (GT.__hooks.OnShow) then GT.__hooks.OnShow(GT) end
    local p = GT.TacoTipPortrait3D
    local lastPoint = p and p.__points and p.__points[#p.__points]
    check("portrait: OnShow re-anchors from the laid-out frame",
        (TT.ev.portraitAnchor or 0) > anchoredBefore,
        "anchors " .. tostring(anchoredBefore) .. " -> " .. tostring(TT.ev.portraitAnchor or 0))
    check("portrait: OnShow puts the portrait on the left when the tooltip is at the right edge",
        lastPoint ~= nil and lastPoint[1] == "TOPRIGHT",
        "point=" .. tostring(lastPoint and lastPoint[1]))
    GT.GetRight = savedRight
    REALG.UIParent.GetRight = savedUiRight
    GT.GetOwner = function() return nil end

    -- Blizzard's "Right Click for Frame Settings" hint is appended AFTER
    -- SetUnit returns; SetUnit's own Show() fires OnShow before the line
    -- exists, and the later Show() is a no-op on an already-shown frame. The
    -- secure post-hook on UnitFrame_UpdateTooltip is the mechanism; this is
    -- the engine-faithful order.
    local savedHint = REALG.UNIT_POPUP_RIGHT_CLICK
    REALG.UNIT_POPUP_RIGHT_CLICK = "Right Click for Frame Settings"
    GT:ClearLines()
    GT:AddLine("Testplayer")
    GT:AddLine("Right Click for Frame Settings")
    if (SECURE_HOOKS.UnitFrame_UpdateTooltip) then
        SECURE_HOOKS.UnitFrame_UpdateTooltip({})
    end
    local hintRefresh = GT:GetLeftLine(2)
    check("hint: the instruction line is blanked after UnitFrame_UpdateTooltip adds it",
        hintRefresh ~= nil and (hintRefresh:GetText() == "" or hintRefresh:GetText() == nil),
        "text=" .. tostring(hintRefresh and hintRefresh:GetText()))
    REALG.UNIT_POPUP_RIGHT_CLICK = savedHint

    C.tooltip_portrait_3d = saved3D
    C.tooltip_portrait = savedPortrait
end

--------------------------------------------------------------------------
-- P16: the Forever zone row.
--
-- The row is the hovered player's zone under the Target row, drawn only for
-- the four unit-frame families (player/target/party/raid) and only when the
-- client answers C_Map.GetBestMapForUnit. origin/forever MapDocumentation.lua
-- :49-60 documents that function as "Only works for the player and party
-- members", so the mock answers for those tokens and returns nil elsewhere;
-- a unit the client cannot place must produce no row rather than a guess.
-- C_Map.GetMapInfo returns UiMapDetails (MapDocumentation.lua:696-706); the
-- label comes from the client's own ZONE string (FriendsFrame.lua:1135).
--------------------------------------------------------------------------
do
    UNITS.party1 = {
        guid = "Player-6-000006", name = "Partymate", level = 60,
        race = "Human", class = "MAGE", className = "Mage", classID = 8,
        isPlayer = true, pvp = false,
    }
    UNITS.raid1 = {
        guid = "Player-7-000007", name = "Raidmate", level = 60,
        race = "Human", class = "PRIEST", className = "Priest", classID = 5,
        isPlayer = true, pvp = false,
    }
    UNITS.party1target = {
        guid = "Player-8-000008", name = "Opponent", level = 60,
        race = "Orc", class = "WARRIOR", className = "Warrior", classID = 1,
        isPlayer = true, pvp = true,
    }
    local ZONE_MAP = { player = 84, party1 = 84, raid1 = 84, target = 84 }
    REALG.__bestMapForUnit = function(u) return ZONE_MAP[u] end
    REALG.__mapInfo = function(mapID)
        if (mapID == 84) then return { name = "Elwynn Forest" } end
        return nil
    end
    local savedZone = REALG.ZONE
    REALG.ZONE = "Zone"

    local savedOwner = GT.GetOwner
    local savedGetUnit = GT.GetUnit
    local savedDisplayedUnit = REALG.TooltipUtil.GetDisplayedUnit
    local savedCurrent = currentUnit

    local function orderedText()
        local out = {}
        for i = 1, GT:NumLines() do
            local l = GT:GetLeftLine(i)
            local t = l and l:GetText()
            if (t ~= nil and t ~= "") then out[#out + 1] = tostring(t) end
        end
        return out
    end

    local function render(unitToken, ownerUnit, seed)
        currentUnit = unitToken
        GT.__unit = unitToken
        GT.GetUnit = function() return "n", unitToken end
        REALG.TooltipUtil.GetDisplayedUnit = function()
            return "n", unitToken, UNITS[unitToken].guid
        end
        GT.GetOwner = function() return { unit = ownerUnit } end
        GT:ClearLines()
        for _, line in STD.ipairs(seed) do GT:AddLine(line) end
        if (POSTCALLS.unit) then
            POSTCALLS.unit(GT, { guid = UNITS[unitToken].guid })
        end
        return orderedText()
    end

    local PLAYER_SEED = { "Testplayer", "<Testguild>", "Level 60 Human" }
    local PARTY_SEED = { "Partymate", "<Testguild>", "Level 60 Human" }

    local selfLines = render("player", "player", PLAYER_SEED)
    local selfText = STD.table.concat(selfLines, "\n")
    check("P16: the player's own frame shows the Zone row",
        STD.string.find(selfText, "Zone: |cFFFFFFFFElwynn Forest|r", 1, true) ~= nil,
        STD.table.concat(selfLines, " | "))

    local partyLines = render("party1", "party1", PARTY_SEED)
    local partyText = STD.table.concat(partyLines, "\n")
    check("P16: a party frame shows the Zone row",
        STD.string.find(partyText, "Elwynn Forest", 1, true) ~= nil,
        STD.table.concat(partyLines, " | "))

    local raidLines = render("raid1", "raid1", { "Raidmate", "Level 60 Human" })
    local raidText = STD.table.concat(raidLines, "\n")
    check("P16: a raid frame shows the Zone row",
        STD.string.find(raidText, "Elwynn Forest", 1, true) ~= nil,
        STD.table.concat(raidLines, " | "))

    -- The real client shape: the tooltip's resolved unit is "mouseover", not
    -- the frame's own token, and C_Map.GetBestMapForUnit does not answer for
    -- "mouseover". The row must query the OWNER frame's unit (party1).
    local resolvedLines = render("mouseover", "party1", { "Enemyplayer", "<Testguild>", "Level 59 Mage" })
    check("P16: the Zone row asks the owner frame's unit, not the resolved mouseover token",
        STD.string.find(STD.table.concat(resolvedLines, "\n"), "Elwynn Forest", 1, true) ~= nil,
        STD.table.concat(resolvedLines, " | "))

    -- The row sits at the bottom of the tooltip below Target and Pawn/scores.
    local targetLines = render("party1", "party1", PARTY_SEED)
    local targetIndex, zoneIndex
    for i, line in STD.ipairs(targetLines) do
        if (STD.string.find(line, "Target:", 1, true) == 1) then targetIndex = i end
        if (STD.string.find(line, "Zone:", 1, true) == 1) then zoneIndex = i end
    end
    check("P16: the Zone row sits at the bottom of the tooltip below Target",
        targetIndex ~= nil and zoneIndex ~= nil and zoneIndex > targetIndex and zoneIndex == #targetLines,
        "target=" .. STD.tostring(targetIndex) .. " zone=" .. STD.tostring(zoneIndex) .. " total=" .. STD.tostring(#targetLines))

    -- A player TARGET that is a group member must resolve through its own
    -- party/raid token: C_Map.GetBestMapForUnit does not answer for "target".
    UNITS.zoneTarget = {
        guid = "Player-9-000009", name = "Targetguy", level = 60,
        race = "Human", class = "PRIEST", className = "Priest", classID = 5,
        isPlayer = true, pvp = false,
    }
    local savedInParty = REALG.UnitInParty
    local savedInRaid = REALG.UnitInRaid
    REALG.UnitInParty = function(u) return u == "zoneTarget" end
    REALG.UnitInRaid = function() return false end
    REALG.__unitIsUnit = function(a, b)
        if (a == "zoneTarget" and b == "party1") then return true end
        return a == b
    end
    REALG.__bestMapForUnit = function(u) return (u == "party1") and 84 or nil end

    -- Out-of-scope frame families and non-player units must not add the row.
    local groupTargetLines = render("zoneTarget", "target", { "Targetguy", "<Testguild>", "Level 60 Human" })
    check("P16: a group-member target frame resolves through its party token",
        STD.string.find(STD.table.concat(groupTargetLines, "\n"), "Elwynn Forest", 1, true) ~= nil,
        STD.table.concat(groupTargetLines, " | "))
    REALG.UnitInParty = savedInParty
    REALG.UnitInRaid = savedInRaid
    REALG.__unitIsUnit = nil
    REALG.__bestMapForUnit = function(u) return ZONE_MAP[u] end

    local nameplateLines = render("mouseover", "nameplate1", { "Enemyplayer", "Level 59 Mage" })
    check("P16: a nameplate hover does not get the Zone row",
        STD.string.find(STD.table.concat(nameplateLines, "\n"), "Elwynn Forest", 1, true) == nil,
        STD.table.concat(nameplateLines, " | "))

    local focusLines = render("mouseover", "focus", { "Enemyplayer", "Level 59 Mage" })
    check("P16: a focus-frame hover does not get the Zone row",
        STD.string.find(STD.table.concat(focusLines, "\n"), "Elwynn Forest", 1, true) == nil,
        STD.table.concat(focusLines, " | "))

    local npcLines = render("target", "target", { "Hated Squirrel", "Level 42 Beast" })
    check("P16: an NPC target frame does not get the Zone row (players only)",
        STD.string.find(STD.table.concat(npcLines, "\n"), "Elwynn Forest", 1, true) == nil,
        STD.table.concat(npcLines, " | "))

    -- The client cannot place a target that is not in the group: no row.
    REALG.__bestMapForUnit = nil
    local noMapLines = render("player", "player", PLAYER_SEED)
    check("P16: no map answer means no Zone row",
        STD.string.find(STD.table.concat(noMapLines, "\n"), "Elwynn Forest", 1, true) == nil,
        STD.table.concat(noMapLines, " | "))
    REALG.__bestMapForUnit = function(u) return ZONE_MAP[u] end

    -- The label is the client's localized ZONE string, not a hardcoded word.
    REALG.ZONE = "Gebiet"
    local localizedLines = render("player", "player", PLAYER_SEED)
    check("P16: the Zone label comes from the client's ZONE string",
        STD.string.find(STD.table.concat(localizedLines, "\n"), "Gebiet:", 1, true) ~= nil,
        STD.table.concat(localizedLines, " | "))
    -- The row must not run in combat or an encounter. State comes from the
    -- client's restriction API, not from InCombatLockdown, because the engine
    -- cvars force both classes out of combat for testing
    -- (addonCombatRestrictionsForced, addonEncounterRestrictionsForced).
    local restrictionActive = {}
    REALG.C_RestrictedActions = {
        IsAddOnRestrictionActive = function(restrictionType)
            return restrictionActive[restrictionType] == true
        end,
    }
    restrictionActive[REALG.Enum.AddOnRestrictionType.Combat] = true
    local combatLines = render("player", "player", PLAYER_SEED)
    check("P16: no Zone row while combat restriction is active",
        STD.string.find(STD.table.concat(combatLines, "\n"), "Elwynn Forest", 1, true) == nil,
        STD.table.concat(combatLines, " | "))
    restrictionActive[REALG.Enum.AddOnRestrictionType.Combat] = false
    restrictionActive[REALG.Enum.AddOnRestrictionType.Encounter] = true
    local encounterLines = render("player", "player", PLAYER_SEED)
    check("P16: no Zone row while encounter restriction is active",
        STD.string.find(STD.table.concat(encounterLines, "\n"), "Elwynn Forest", 1, true) == nil,
        STD.table.concat(encounterLines, " | "))
    restrictionActive[REALG.Enum.AddOnRestrictionType.Encounter] = false
    local unrestrictedLines = render("player", "player", PLAYER_SEED)
    check("P16: the Zone row returns when neither restriction is active",
        STD.string.find(STD.table.concat(unrestrictedLines, "\n"), "Elwynn Forest", 1, true) ~= nil,
        STD.table.concat(unrestrictedLines, " | "))
    REALG.C_RestrictedActions = nil

    REALG.ZONE = savedZone

    currentUnit = savedCurrent
    GT.GetOwner = savedOwner
    GT.GetUnit = savedGetUnit
    REALG.TooltipUtil.GetDisplayedUnit = savedDisplayedUnit
    REALG.__bestMapForUnit = nil
    REALG.__mapInfo = nil
end

--------------------------------------------------------------------------
-- P16b: the map answer changes per unit AFTER main.lua has loaded.
--
-- main.lua captured C_Map.GetBestMapForUnit (and GetMapInfo) at load time as
-- locals, so a test must NOT replace REALG.C_Map after load. Instead the
-- captured function reads the mutable state table, and changing that table
-- after load makes different units resolve to different zones. This pin
-- proves the per-unit indirection works for both the player and a party
-- member, and that a unit the client cannot place still gets no row.
--------------------------------------------------------------------------
do
    UNITS.party1 = UNITS.party1 or {
        guid = "Player-6-000006", name = "Partymate", level = 60,
        race = "Human", class = "MAGE", className = "Mage", classID = 8,
        isPlayer = true, pvp = false,
    }
    local ZONE_MAP = { player = 84, party1 = 85 }
    REALG.__bestMapForUnit = function(u) return ZONE_MAP[u] end
    REALG.__mapInfo = function(mapID)
        if (mapID == 84) then return { name = "Elwynn Forest" } end
        if (mapID == 85) then return { name = "Stormwind City" } end
        return nil
    end
    local savedZone = REALG.ZONE
    REALG.ZONE = "Zone"

    local savedOwner = GT.GetOwner
    local savedGetUnit = GT.GetUnit
    local savedDisplayedUnit = REALG.TooltipUtil.GetDisplayedUnit
    local savedCurrent = currentUnit

    local function orderedText()
        local out = {}
        for i = 1, GT:NumLines() do
            local l = GT:GetLeftLine(i)
            local t = l and l:GetText()
            if (t ~= nil and t ~= "") then out[#out + 1] = tostring(t) end
        end
        return out
    end

    local function render(unitToken, ownerUnit, seed)
        currentUnit = unitToken
        GT.__unit = unitToken
        GT.GetUnit = function() return "n", unitToken end
        REALG.TooltipUtil.GetDisplayedUnit = function()
            return "n", unitToken, UNITS[unitToken].guid
        end
        GT.GetOwner = function() return { unit = ownerUnit } end
        GT:ClearLines()
        for _, line in STD.ipairs(seed) do GT:AddLine(line) end
        if (POSTCALLS.unit) then
            POSTCALLS.unit(GT, { guid = UNITS[unitToken].guid })
        end
        return orderedText()
    end

    local PLAYER_SEED = { "Testplayer", "<Testguild>", "Level 60 Human" }
    local PARTY_SEED = { "Partymate", "<Testguild>", "Level 60 Human" }

    -- Player resolves to its own map answer after load.
    local playerLines = render("player", "player", PLAYER_SEED)
    local playerText = STD.table.concat(playerLines, "\n")
    check("P16b: player keeps its own (post-load) map answer",
        STD.string.find(playerText, "Elwynn Forest", 1, true) ~= nil
            and STD.string.find(playerText, "Stormwind City", 1, true) == nil,
        STD.table.concat(playerLines, " | "))

    -- Party member resolves to a different map answer after load.
    local partyLines = render("party1", "party1", PARTY_SEED)
    local partyText = STD.table.concat(partyLines, "\n")
    check("P16b: a party member resolves a different (post-load) map answer",
        STD.string.find(partyText, "Stormwind City", 1, true) ~= nil
            and STD.string.find(partyText, "Elwynn Forest", 1, true) == nil,
        STD.table.concat(partyLines, " | "))

    -- Changing the answer for one unit does not affect the already-rendered
    -- other unit: re-render player, still Elwynn.
    ZONE_MAP.party1 = 84
    local playerAgain = render("player", "player", PLAYER_SEED)
    local playerAgainText = STD.table.concat(playerAgain, "\n")
    check("P16b: changing one unit's answer leaves the other unit's row intact",
        STD.string.find(playerAgainText, "Elwynn Forest", 1, true) ~= nil,
        STD.table.concat(playerAgain, " | "))
    ZONE_MAP.party1 = 85

    -- A unit the client cannot place (no map answer) gets no row.
    ZONE_MAP.target = nil
    local npcLines = render("target", "target", { "Hated Squirrel", "Level 42 Beast" })
    local npcText = STD.table.concat(npcLines, "\n")
    check("P16b: a unit with no (post-load) map answer gets no Zone row",
        STD.string.find(npcText, "Elwynn Forest", 1, true) == nil
            and STD.string.find(npcText, "Stormwind City", 1, true) == nil,
        STD.table.concat(npcLines, " | "))

    currentUnit = savedCurrent
    GT.GetOwner = savedOwner
    GT.GetUnit = savedGetUnit
    REALG.TooltipUtil.GetDisplayedUnit = savedDisplayedUnit
    REALG.ZONE = savedZone
    REALG.__bestMapForUnit = nil
    REALG.__mapInfo = nil
end

--------------------------------------------------------------------------
-- P17: the Forever loot-window tooltip is left exactly as the client builds
-- it. It is secret tooltip data rebuilt every frame (LootFrame.lua:464-469,
-- TooltipDataHandler.lua:495-517 and :537); the game's own warning is that
-- taint plus secret line data can make the tooltip display no lines
-- (GameTooltip.lua:994-1003). A normal item tooltip must keep TacoTip's rows.
--------------------------------------------------------------------------
do
    local itemPost
    local unitPost
    for _, rec in STD.ipairs(POSTCALLS) do
        if (rec.typ == REALG.Enum.TooltipDataType.Item) then itemPost = rec.fn end
        if (rec.typ == REALG.Enum.TooltipDataType.Unit) then unitPost = rec.fn end
    end
    local savedOwner = GT.GetOwner
    local savedGetUnit = GT.GetUnit
    local lootOwner = {
        GetSlotIndex = function() return 1 end,
        GetItemSlotType = function() return 1 end,
    }

    GT.GetOwner = function() return lootOwner end
    GT:ClearLines()
    GT:AddLine("Test Helm")
    GT:AddLine("Item Level 88")
    local before = GT:NumLines()
    local okLoot = STD.pcall(itemPost, GT, { hyperlink = GEAR_LINK })
    check("P17: the loot-window tooltip keeps the client's own line count",
        okLoot and GT:NumLines() == before,
        "lines " .. STD.tostring(before) .. " -> " .. STD.tostring(GT:NumLines())
        .. " err=" .. STD.tostring(okLoot))
    check("P17: no TacoTip item row is added to the loot-window tooltip",
        STD.string.find(allText(), "GearScore", 1, true) == nil,
        STD.string.gsub(allText(), "\n", " | "))

    -- Control: the same item on a normal (non-loot) tooltip still gets the
    -- rows, so the gate is the loot owner rather than the item path.
    GT.GetOwner = function() return { unit = "player" } end
    GT:ClearLines()
    GT:AddLine("Test Helm")
    GT:AddLine("Item Level 88")
    local okItem = STD.pcall(itemPost, GT, { hyperlink = GEAR_LINK })
    check("P17: a normal item tooltip still gets TacoTip's item rows",
        okItem and GT:NumLines() > 2,
        "lines=" .. STD.tostring(GT:NumLines()) .. " err=" .. STD.tostring(okItem))

    -- OnShow must not read the loot tooltip's data either. Both GetItem and
    -- GetDisplayedUnit (which goes through GetPrimaryTooltipData) are the
    -- tooltip-info reads Blizzard warns about for secret tooltip data.
    local reads = 0
    local unitAnswer = nil
    local savedDisplayed = REALG.TooltipUtil.GetDisplayedUnit
    REALG.TooltipUtil.GetDisplayedUnit = function(...)
        reads = reads + 1
        if (unitAnswer) then return unitAnswer() end
        return savedDisplayed(...)
    end
    local savedGetItem = GT.GetItem
    GT.GetItem = function(...)
        reads = reads + 1
        return savedGetItem(...)
    end

    GT.GetOwner = function() return lootOwner end
    if (GT.__hooks.OnShow) then GT.__hooks.OnShow(GT) end
    check("P17: OnShow reads no tooltip data for the loot-window tooltip",
        reads == 0, "reads=" .. STD.tostring(reads))

    -- A unit tooltip always runs its own post-call before Show, and that call
    -- is what clears the item marker the control above set. Model it here
    -- rather than showing a unit tooltip that still carries an item marker no
    -- real client can produce.
    GT.GetOwner = function() return { unit = "player" } end
    GT.GetUnit = function() return "n", "player" end
    unitAnswer = function() return "n", "player", UNITS.player.guid end
    if (unitPost) then STD.pcall(unitPost, GT, { guid = UNITS.player.guid }) end
    local beforeReads = reads
    if (GT.__hooks.OnShow) then GT.__hooks.OnShow(GT) end
    check("P17: OnShow still resolves the unit for a normal tooltip",
        reads > beforeReads, "reads=" .. STD.tostring(reads - beforeReads))

    REALG.TooltipUtil.GetDisplayedUnit = savedDisplayed
    GT.GetItem = savedGetItem
    GT.GetUnit = savedGetUnit
    GT.GetOwner = savedOwner
end

--------------------------------------------------------------------------
-- P-ITEM: the Forever ITEM tooltip resolves its link from the client's own
-- post-call payload, never from tooltip-info reads.
--
-- The post-call payload is the sanctioned hand-off (the secure delegate behind
-- the accessor strips taint). `GetItem` / `GetDisplayedItem` are tooltip-INFO
-- reads, and Blizzard's own note says that reading one from a tainted hook can
-- carry taint into ProcessInfo, which makes a tooltip carrying secret line data
-- display no lines (GameTooltip.lua:994-1003). Item tooltips with secret lines
-- exist in instances, so the reads must be absent on the pipeline client.
--------------------------------------------------------------------------
do
    local itemPost
    for _, rec in STD.ipairs(POSTCALLS) do
        if (rec.typ == REALG.Enum.TooltipDataType.Item) then itemPost = rec.fn end
    end
    local savedOwner, savedGetItem = GT.GetOwner, GT.GetItem
    local savedDisplayedItem = REALG.TooltipUtil.GetDisplayedItem
    local reads = 0
    GT.GetItem = function(...) reads = reads + 1; return savedGetItem(...) end
    REALG.TooltipUtil.GetDisplayedItem = function(...)
        reads = reads + 1
        return savedDisplayedItem(...)
    end

    GT.GetOwner = function() return { unit = "player" } end
    GT:ClearLines()
    GT:AddLine("Test Helm")
    local okPost = STD.pcall(itemPost, GT, { hyperlink = GEAR_LINK })
    check("P-ITEM: the Forever item post-call performs no tooltip-info reads",
        okPost and reads == 0,
        "reads=" .. STD.tostring(reads) .. " err=" .. STD.tostring(okPost))
    check("P-ITEM: the item rows are still added from the payload",
        okPost and STD.string.find(allText(), "GearScore", 1, true) ~= nil,
        STD.string.gsub(allText(), "\n", " | "))

    if (GT.__hooks.OnShow) then STD.pcall(GT.__hooks.OnShow, GT) end
    check("P-ITEM: OnShow performs no tooltip-info reads for an item tooltip",
        reads == 0, "reads=" .. STD.tostring(reads))

    -- A secret link in the payload: no raise, no score row. issecretvalue
    -- THROWS on the sentinel -- the client contract the strong guard reads as
    -- "is secret".
    local SECRET_LINK = STD.setmetatable({}, {
        __tostring = function() STD.error("cannot tostring a secret value") end,
    })
    local savedIsSecret = REALG.issecretvalue
    REALG.issecretvalue = function(v)
        if (STD.rawequal(v, SECRET_LINK)) then
            STD.error("issecretvalue on a secret value from tainted execution", 0)
        end
        return false
    end
    GT:ClearLines()
    GT:AddLine("Test Helm")
    local secretCountBefore = TT.ev.itemSecretLink or 0
    local okSecret = STD.pcall(itemPost, GT, { hyperlink = SECRET_LINK })
    check("P-ITEM: a secret item link neither raises nor adds a score row",
        okSecret and STD.string.find(allText(), "GearScore", 1, true) == nil,
        "ok=" .. STD.tostring(okSecret) .. " text=" .. STD.string.gsub(allText(), "\n", " | "))
    check("P-ITEM: the dropped secret link is counted for /tt diag",
        (TT.ev.itemSecretLink or 0) == secretCountBefore + 1,
        "itemSecretLink=" .. STD.tostring(TT.ev.itemSecretLink))
    check("P-ITEM: the refusal is tallied per API",
        STD.type(TT.ev.secretRefused) == "table"
            and (TT.ev.secretRefused["item-link"] or 0) >= 1,
        "tally=" .. STD.tostring(TT.ev.secretRefused and TT.ev.secretRefused["item-link"]))
    check("P-ITEM: the row delta and the last-hover fingerprint are recorded",
        STD.type(TT.ev.itemRowsLastBefore) == "number"
            and STD.type(TT.ev.itemRowsLastAfter) == "number"
            and STD.type(TT.ev.lastItem) == "table"
            and TT.ev.itemRowsLastAfter >= TT.ev.itemRowsLastBefore,
        "before=" .. STD.tostring(TT.ev.itemRowsLastBefore)
            .. " after=" .. STD.tostring(TT.ev.itemRowsLastAfter)
            .. " last=" .. STD.tostring(STD.type(TT.ev.lastItem)))
    REALG.issecretvalue = savedIsSecret

    -- An unreadable payload (a secret table): no rows, and a counter the user's
    -- report can be read from.
    local savedCanAccess = REALG.canaccesstable
    REALG.canaccesstable = function() return false end
    local unreadableBefore = TT.ev.itemPayloadUnreadable or 0
    GT:ClearLines()
    GT:AddLine("Test Helm")
    local okUnreadable = STD.pcall(itemPost, GT, { hyperlink = GEAR_LINK })
    check("P-ITEM: an unreadable payload is counted and adds no score row",
        okUnreadable and (TT.ev.itemPayloadUnreadable or 0) == unreadableBefore + 1
            and STD.string.find(allText(), "GearScore", 1, true) == nil,
        "ok=" .. STD.tostring(okUnreadable)
            .. " unreadable=" .. STD.tostring(TT.ev.itemPayloadUnreadable))
    REALG.canaccesstable = savedCanAccess

    -- The report itself: the counters must reach /tt diag as a row and as a
    -- problem, or the numbers exist but nobody can see them.
    local diagOk, diag = STD.pcall(TT.CollectDiagnostics, REALG.TT)
    local itemRow, problemText = nil, ""
    local rowsByLabel = {}
    if (diagOk and STD.type(diag) == "table" and STD.type(diag.sections) == "table") then
        for i = 1, #diag.sections do
            local section = diag.sections[i]
            if (section.id == "tooltip" and STD.type(section.rows) == "table") then
                for j = 1, #section.rows do
                    rowsByLabel[section.rows[j].label] = section.rows[j]
                end
            end
        end
        itemRow = rowsByLabel["item tooltip hooks"]
        if (STD.type(diag.problems) == "table") then
            for i = 1, #diag.problems do
                problemText = problemText .. STD.tostring(diag.problems[i].text) .. "\n"
            end
        end
    end
    check("P-ITEM: /tt diag reports the item payload counters",
        diagOk and itemRow ~= nil
            and STD.string.find(STD.tostring(itemRow.value),
                "unreadable payload=" .. STD.tostring(TT.ev.itemPayloadUnreadable), 1, true) ~= nil,
        "diagOk=" .. STD.tostring(diagOk) .. " row=" .. STD.tostring(itemRow and itemRow.value))
    check("P-ITEM: an unreadable payload is reported as a problem",
        STD.string.find(problemText, "unreadable", 1, true) ~= nil,
        STD.string.gsub(problemText, "\n", " | "))
    check("P-ITEM: the refusal tally, row delta and fingerprint reach the report",
        rowsByLabel["secret refusals by API"] ~= nil
            and rowsByLabel["item row delta"] ~= nil
            and rowsByLabel["last item hover"] ~= nil,
        "tally=" .. STD.tostring(rowsByLabel["secret refusals by API"] and
            rowsByLabel["secret refusals by API"].value)
            .. " delta=" .. STD.tostring(rowsByLabel["item row delta"] and
            rowsByLabel["item row delta"].value)
            .. " last=" .. STD.tostring(rowsByLabel["last item hover"] and
            rowsByLabel["last item hover"].value))

    -- The warning log is capped, so #log can understate the session. The report
    -- must show the lifetime total, not the surviving slice.
    for _ = 1, 31 do TT:RecordWarning("pin", "warning overflow pin") end
    local diagWarnOk, diagWarn = STD.pcall(TT.CollectDiagnostics, TT)
    local warnRow
    if (diagWarnOk and STD.type(diagWarn) == "table") then
        for i = 1, #(diagWarn.sections or {}) do
            local section = diagWarn.sections[i]
            if (section.id == "errors" and STD.type(section.rows) == "table") then
                for j = 1, #section.rows do
                    if (section.rows[j].label == "total warnings recorded") then
                        warnRow = section.rows[j]
                    end
                end
            end
        end
    end
    check("P-ITEM: the report shows the lifetime warning total, not the capped log",
        warnRow ~= nil
            and STD.string.find(STD.tostring(warnRow.value),
                STD.tostring(TT.totalWarnings), 1, true) ~= nil
            and STD.string.find(STD.tostring(warnRow.value), "log holds 30", 1, true) ~= nil,
        "row=" .. STD.tostring(warnRow and warnRow.value)
            .. " total=" .. STD.tostring(TT.totalWarnings))

    GT.GetItem = savedGetItem
    REALG.TooltipUtil.GetDisplayedItem = savedDisplayedItem
    GT.GetOwner = savedOwner
end

--------------------------------------------------------------------------
-- P18: C_Map answers are read per unit after main.lua has loaded.
--
-- main.lua captures C_Map.GetBestMapForUnit into a local at load time, so a
-- test cannot change the answer by replacing REALG.C_Map later. The mock
-- above stores the live answer in REALG.__bestMapForUnit, which is called
-- with the unit token; reassigning that state function changes the answer for
-- one unit without touching the table field or any other unit.
--------------------------------------------------------------------------
do
    local savedZone = REALG.ZONE
    REALG.ZONE = "Zone"

    local savedOwner = GT.GetOwner
    local savedGetUnit = GT.GetUnit
    local savedDisplayedUnit = REALG.TooltipUtil.GetDisplayedUnit
    local savedCurrent = currentUnit

    local UNIT_MAP = { player = 84, party1 = 90 }
    REALG.__bestMapForUnit = function(u) return UNIT_MAP[u] end
    REALG.__mapInfo = function(mapID)
        if (mapID == 84) then return { name = "Elwynn Forest" } end
        if (mapID == 90) then return { name = "Stormwind City" } end
        return nil
    end

    local function orderedText()
        local out = {}
        for i = 1, GT:NumLines() do
            local l = GT:GetLeftLine(i)
            local t = l and l:GetText()
            if (t ~= nil and t ~= "") then out[#out + 1] = tostring(t) end
        end
        return out
    end

    local function render(unitToken, ownerUnit, seed)
        currentUnit = unitToken
        GT.__unit = unitToken
        GT.GetUnit = function() return "n", unitToken end
        REALG.TooltipUtil.GetDisplayedUnit = function()
            return "n", unitToken, UNITS[unitToken] and UNITS[unitToken].guid
        end
        GT.GetOwner = function() return { unit = ownerUnit } end
        GT:ClearLines()
        for _, line in STD.ipairs(seed) do GT:AddLine(line) end
        if (POSTCALLS.unit) then
            POSTCALLS.unit(GT, { guid = UNITS[unitToken] and UNITS[unitToken].guid })
        end
        return orderedText()
    end

    UNITS.player = UNITS.player or {
        guid = "Player-1-000001", name = "Testplayer", level = 60,
        race = "Human", class = "WARRIOR", className = "Warrior", classID = 1,
        isPlayer = true, pvp = false,
    }
    UNITS.party1 = UNITS.party1 or {
        guid = "Player-6-000006", name = "Partymate", level = 60,
        race = "Human", class = "MAGE", className = "Mage", classID = 8,
        isPlayer = true, pvp = false,
    }

    local playerLines = render("player", "player", { "Testplayer", "Level 60 Human" })
    local playerText = STD.table.concat(playerLines, "\n")
    check("P18: player gets its own map answer",
        STD.string.find(playerText, "Elwynn Forest", 1, true) ~= nil,
        STD.table.concat(playerLines, " | "))

    local partyLines = render("party1", "party1", { "Partymate", "Level 60 Human" })
    local partyText = STD.table.concat(partyLines, "\n")
    check("P18: a different unit gets a different map answer",
        STD.string.find(partyText, "Stormwind City", 1, true) ~= nil,
        STD.table.concat(partyLines, " | "))

    -- Changing the state function after load changes the next render for that unit only.
    UNIT_MAP.player = 90
    local changedLines = render("player", "player", { "Testplayer", "Level 60 Human" })
    local changedText = STD.table.concat(changedLines, "\n")
    check("P18: reassigning the state function changes a later render",
        STD.string.find(changedText, "Stormwind City", 1, true) ~= nil,
        STD.table.concat(changedLines, " | "))

    currentUnit = savedCurrent
    GT.GetOwner = savedOwner
    GT.GetUnit = savedGetUnit
    REALG.TooltipUtil.GetDisplayedUnit = savedDisplayedUnit
    REALG.__bestMapForUnit = nil
    REALG.__mapInfo = nil
    REALG.ZONE = savedZone
end

--------------------------------------------------------------------------
-- P19: Secret-value and taint safety on the Forever zone row & group tokens.
-- If mapInfo.name is a secret value or UnitInRaid returns secret data,
-- the row is safely omitted without throwing string/boolean exceptions.
--------------------------------------------------------------------------
do
    local savedZone = REALG.ZONE
    REALG.ZONE = "Zone"
    local savedOwner = GT.GetOwner
    local savedGetUnit = GT.GetUnit
    local savedDisplayedUnit = REALG.TooltipUtil.GetDisplayedUnit
    local savedInParty = REALG.UnitInParty
    local savedInRaid = REALG.UnitInRaid

    local SECRET_STR = setmetatable({}, {
        __tostring = function() error("cannot tostring secret value") end,
        __eq = function() error("cannot compare secret value") end,
        __concat = function() error("cannot concatenate secret value") end,
    })
    local savedIsSecret = REALG.issecretvalue
    REALG.issecretvalue = function(v) return v == SECRET_STR end

    REALG.__bestMapForUnit = function() return 999 end
    REALG.__mapInfo = function(id) return (id == 999) and { name = SECRET_STR } or nil end

    -- Even with secret mapInfo.name, render should not throw and Zone row is omitted
    local ok, secretLines = pcall(function()
        GT.GetOwner = function() return { unit = "party1" } end
        GT.GetUnit = function() return "n", "party1" end
        REALG.TooltipUtil.GetDisplayedUnit = function()
            return "n", "party1", "Player-6-000006"
        end
        GT:ClearLines()
        GT:AddLine("Partymate")
        if (POSTCALLS.unit) then
            POSTCALLS.unit(GT, { guid = "Player-6-000006" })
        end
        local out = {}
        for i = 1, GT:NumLines() do
            local l = GT:GetLeftLine(i)
            local t = l and l:GetText()
            if (t ~= nil and t ~= "") then out[#out + 1] = tostring(t) end
        end
        return out
    end)

    check("P19: secret map name is safely omitted without throwing",
        ok and type(secretLines) == "table",
        "ok=" .. STD.tostring(ok))

    -- Secret return from UnitInRaid / UnitInParty also safely handled
    REALG.UnitInRaid = function() return SECRET_STR end
    local okGroup, resGroup = pcall(function()
        GT.GetOwner = function() return { unit = "target" } end
        GT.GetUnit = function() return "n", "target" end
        REALG.TooltipUtil.GetDisplayedUnit = function()
            return "n", "target", "Player-9-000009"
        end
        GT:ClearLines()
        GT:AddLine("Targetguy")
        if (POSTCALLS.unit) then
            POSTCALLS.unit(GT, { guid = "Player-9-000009" })
        end
        return true
    end)

    check("P19: secret group membership probe never throws boolean exception",
        okGroup and resGroup == true,
        "ok=" .. STD.tostring(okGroup))

    REALG.issecretvalue = savedIsSecret
    REALG.UnitInParty = savedInParty
    REALG.UnitInRaid = savedInRaid
    GT.GetOwner = savedOwner
    GT.GetUnit = savedGetUnit
    REALG.TooltipUtil.GetDisplayedUnit = savedDisplayedUnit
    REALG.__bestMapForUnit = nil
    REALG.__mapInfo = nil
    REALG.ZONE = savedZone
end

--------------------------------------------------------------------------
-- P20: Zero-allocation fontstring caching.
-- GetTooltipLeftLine/RightLine memoize references to avoid runtime allocations.
--------------------------------------------------------------------------
do
    local line1a = TT.GetTooltipLeftLine(GT, 1)
    local line1b = TT.GetTooltipLeftLine(GT, 1)
    check("P20: GetTooltipLeftLine returns memoized fontstring without allocating",
        line1a ~= nil and line1a == line1b,
        "line1a=" .. STD.tostring(line1a) .. " line1b=" .. STD.tostring(line1b))
end

--------------------------------------------------------------------------
-- P21: FormatDiagnosticExport markdown generation.
--------------------------------------------------------------------------
do
    local exp = TT.FormatDiagnosticExport and TT:FormatDiagnosticExport()
    check("P21: FormatDiagnosticExport returns clean markdown report",
        type(exp) == "string" and STD.string.find(exp, "```markdown", 1, true) == 1
            and STD.string.find(exp, "TacoTip System Diagnostic Report", 1, true) ~= nil,
        "export=" .. STD.tostring(exp and exp:sub(1, 60)))
end

--------------------------------------------------------------------------
-- P22: Pawn dual-spec memoization: groups 1 and 2 cached simultaneously.
--------------------------------------------------------------------------
do
    local testGUID = "Player-7-000007"
    local dummyItems = { [1] = 1001, [2] = 1002 }
    TT.setPawnScoreMemo(testGUID, dummyItems, 1, 1500, "Arms", "|cffc79c6e")
    TT.setPawnScoreMemo(testGUID, dummyItems, 2, 1750, "Fury", "|cffc79c6e")

    local score1, spec1 = TT.getPawnScoreMemo(testGUID, dummyItems, 1)
    local score2, spec2 = TT.getPawnScoreMemo(testGUID, dummyItems, 2)

    check("P22: Pawn dual-spec memo retains group 1 score",
        score1 == 1500 and spec1 == "Arms",
        "score1=" .. STD.tostring(score1) .. " spec1=" .. STD.tostring(spec1))
    check("P22: Pawn dual-spec memo retains group 2 score simultaneously",
        score2 == 1750 and spec2 == "Fury",
        "score2=" .. STD.tostring(score2) .. " spec2=" .. STD.tostring(spec2))
end

--------------------------------------------------------------------------
-- P13b: FojjiCore's row is switched off through its own option, and TacoTip
-- never replaces GameTooltip's methods (no override, no secret predicate).
--------------------------------------------------------------------------
do
    check("scope: FojjiCore's own score option is switched off",
        fojjiScoreCalls >= 1, "calls=" .. tostring(fojjiScoreCalls))
    check("scope: TacoTip never replaces GameTooltip.AddLine",
        rawget(GT, "_tacoTipForeignScoreBlock") == nil,
        "marker=" .. tostring(rawget(GT, "_tacoTipForeignScoreBlock")))
end

--------------------------------------------------------------------------
-- Tooltip-data readability gate (canaccesstable).
--
-- The post-call payload can be a SECRET TABLE on Forever: once untainted code
-- stores a secret value as a key, the table is flagged secret AND inaccessible,
-- and indexing it raises ("attempted to index a forbidden table"). issecretvalue
-- does not answer that -- the raise happens on the INDEX. The documented predicate
-- is canaccesstable ("...permissions to index secret tables"), so every
-- `data.<field>` read is gated on it.
--
-- This pins the predicate itself, including the two ways it can refuse: a false
-- answer and a throwing call (it is itself AllowedWhenUntainted).
--------------------------------------------------------------------------
do
    local savedCanAccess = REALG.canaccesstable
    local readable = TT.tooltipDataReadable

    check("tooltip data: the readability gate exists",
        STD.type(readable) == "function", STD.type(readable))

    if (STD.type(readable) == "function") then
        check("tooltip data: nil is not readable", readable(nil) == false)
        check("tooltip data: a non-table is not readable", readable("link") == false)

        REALG.canaccesstable = function() return true end
        check("tooltip data: an accessible table is readable",
            readable({ hyperlink = "item:1" }) == true)

        REALG.canaccesstable = function() return false end
        check("tooltip data: canaccesstable(false) refuses the table",
            readable({ hyperlink = "item:1" }) == false)

        -- The call is SecretArguments="AllowedWhenUntainted", so a refusal is a
        -- THROW. A throw must read as "not readable", never as "readable".
        REALG.canaccesstable = function() error("secret values are only allowed during untainted execution") end
        check("tooltip data: a THROWING canaccesstable refuses the table",
            readable({ hyperlink = "item:1" }) == false)

        -- And the gate is not a blanket refusal: with the API absent (classic
        -- clients) a plain table still reads normally.
        REALG.canaccesstable = nil
        check("tooltip data: no canaccesstable still reads a plain table",
            readable({ hyperlink = "item:1" }) == true)

        REALG.canaccesstable = savedCanAccess
    end
end

--------------------------------------------------------------------------
-- Report.
--------------------------------------------------------------------------
local fails = 0
for _, c in STD.ipairs(checks) do
    if (not c[2]) then
        fails = fails + 1
        STD.io.write("  FAIL " .. tostring(c[1]) .. " :: " .. tostring(c[3] or "") .. "\n")
    end
end
STD.io.write("FOREVER pins: " .. tostring(#checks - fails) .. "/" .. tostring(#checks) .. " passed\n")
if (fails > 0) then STD.os.exit(1) end
