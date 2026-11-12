-- Contract pins for the corrected Unit*/Item* call sites (2026-11-10).
--
-- WHY THIS FILE EXISTS. The audits behind version 1.0.0 corrected fourteen
-- main.lua sites, four LibForeverInspector sites, two options.lua sites and two
-- gearscore.lua sites against the CLIENT'S DOCUMENTED RETURN CONTRACT (see
-- bench/audits/2026-11-10-api-contract-ledger.md and workshop.md -> "unit and
-- item return contracts"). Every one of those corrections was proven by hand and
-- then left unpinned. This file is the permanent pin.
--
-- THE MOCK CONTRACT, and why it is the point of the file. The pre-existing
-- secret sentinels in tooltip_test.lua and forever_tooltip_test.lua model
-- issecretvalue as a predicate that NEVER raises. The client contract is the
-- opposite: FrameScriptDocumentation.lua declares
--   issecretvalue -- SecretArguments = "AllowedWhenUntainted"
-- so a call from tainted add-on execution on a secret value THROWS. A predicate
-- that never raises cannot distinguish the strong guard (`not okSecret or
-- isSec == true`) from the weak one, and cannot prove argument-hazard handling
-- either. Every pin here installs a THROWING issecretvalue, and the first pin
-- asserts that the mock does throw -- otherwise the whole file is vacuous.
--
-- SHAPES PINNED (client truth quoted in workshop.md's contract table):
--   * UnitGUID       -- result WOWGUID **Nilable**, SecretWhenUnitIdentityRestricted
--   * UnitInRaid     -- result **luaIndex Nilable**: nil outside a raid, a raid
--                       INDEX (a number) inside one -- never a boolean
--   * UnitClass      -- **MayReturnNothing**; className ConditionalSecret,
--                       classFilename plain
--   * GetItemInfo    -- **MayReturnNothing**: "not loaded yet", not an error
--   * GetItemLink    -- itemLink **Nilable** (nil while the item is unloaded)
--   * UnitPowerMax / UnitPower -- result may be secret; SetMinMaxValues/SetValue
--                       are the documented tainted-safe sink
--   * every Unit* below declares SecretArguments="AllowedWhenUntainted": a
--     secret unit TOKEN is refused at the call, before any pcall protects it.
--
-- THE TWO OPERATOR-REPORTED SURFACES are pinned end-to-end:
--   E  an ITEM tooltip rendered while item data is unloaded; and
--   F  the unit-tooltip GEARSCORE row while the secrecy predicate throws and
--      combat/encounter restrictions are in effect.
--
-- RED/GREEN. `TACOTIP_*_OVERRIDE` points at a throwaway copy for the proof
-- (never set in a gate): TACOTIP_MAIN_OVERRIDE, TACOTIP_LIB_OVERRIDE,
-- TACOTIP_GS_OVERRIDE, TACOTIP_OPTIONS_OVERRIDE. Measured 2026-11-10:
--
--   copy                                         result
--   git show HEAD:main.lua                        3 pins red (UnitPowerMax
--                                                 argument, UnitCanAttack/
--                                                 IsPlayer/Level argument,
--                                                 WarmGearItemData secret link)
--   git show HEAD:.../LibForeverInspector.lua     8 pins red (item wrapper x3,
--                                                 unit GearScore row while
--                                                 unloaded x2, PlayerGUIDToUnit
--                                                 Token x3)
--   git show HEAD:gearscore.lua                   1 pin red (secret weapon
--                                                 receiver was indexed)
--   git show HEAD:options.lua                     1 pin red (no playerGUID
--                                                 helper; bare UnitGUID)
--   defect-shaped main.lua copies (mutation)      one or more pins each, one
--                                                 copy per SHAPE:
--     inraid_mut                                  boolean read of the luaIndex
--     inraid_nilerr_mut                           nil outside a raid = error
--     cls_mut                                     classFilename indexed
--     item_raise_mut                              unguarded MayReturnNothing use
--     guid_nilerr_mut                             nil GUID = error
--     guid_unguarded_mut                          secrecy test dropped
--     guid_nopcall_mut                            the call is not pcall'd
--     guid_asknil_mut                             predicate asked about nil
--   defect-shaped gearscore.lua copy (mutation)  1 pin: nil link counted
--
-- Pins marked RED-AT-HEAD fail on a `git show HEAD:` copy. Pins marked SHAPE
-- are contract pins whose production change was behaviour-neutral for the
-- documented string|nil shape (HEAD's `not guid` and `not inR` are not
-- comparisons), so their red is the defect-shaped copy named in the detail;
-- they pin the RULE a future edit is most likely to forget.
--
-- Usage: lua5.1 Tests/harness/contract_pins_test.lua
-- Forever-scoped (the secrecy API exists only on Forever/Retail); the client
-- mock is Forever-shaped like forever_tooltip_test.lua.

local _hp = ((arg and arg[0]) or "Tests/harness/contract_pins_test.lua"):gsub("\\", "/")
local _hd = _hp:match("^(.*)/[^/]*$") or "."
local ROOT = dofile(_hd .. "/root.lua") .. "/"

local REALG = _G
local unpack = unpack or table.unpack
local DEBUG = rawget(_G, "debug")

local STD = {
    os = os, string = string, pairs = pairs, ipairs = ipairs, type = type,
    pcall = pcall, tonumber = tonumber, tostring = tostring, select = select,
    rawget = rawget, rawset = rawset, setmetatable = setmetatable,
    getmetatable = getmetatable, unpack = unpack, assert = assert, error = error,
    math = math, table = table, loadfile = loadfile, print = print, io = io,
    getenv = os.getenv, debug = DEBUG,
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
    next = next, rawequal = rawequal,
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
    w.SetFont = function() end
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
REALG.Enum = { TooltipDataType = { Item = 0, Unit = 2 } }

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
-- Mutable client answers. main.lua captures UnitClass, UnitCanAttack,
-- UnitIsPlayer, UnitLevel and UnitRace at load, so a pin cannot replace those
-- globals afterwards and be seen: the wrapper exists BEFORE the chunk loads and
-- each pin swaps REALG.__ov[name]. UnitGUID/UnitInRaid/UnitPower* are read as
-- globals at call time, but the same wrapper is used for a uniform model.
--------------------------------------------------------------------------
REALG.__ov = {}
local OV = REALG.__ov
local ORIG = {}
local function overridable(name)
    ORIG[name] = REALG[name]
    local base = REALG[name]
    REALG[name] = function(...)
        local f = OV[name]
        if (f) then return f(...) end
        if (base) then return base(...) end
    end
end
for _, n in STD.ipairs({
    "UnitClass", "UnitCanAttack", "UnitIsPlayer", "UnitLevel", "UnitRace",
    "UnitGUID", "UnitExists", "UnitInRaid", "UnitName", "UnitPower",
    "UnitPowerMax", "UnitPowerType", "UnitPVPName", "UnitIsConnected",
    "UnitIsDeadOrGhost", "UnitIsUnit",
}) do
    if (REALG[n] ~= nil) then overridable(n) end
end

-- Safe rendering for assertion details: a secret sentinel raises on tostring,
-- so a failing pin must never format one.
local describe = function(v)
    if (STD.type(v) == "table") then return "<table>" end
    return STD.tostring(v)
end

--------------------------------------------------------------------------
-- Load the real addon. The four *_OVERRIDE paths exist for the red/green
-- proof only; a gate never sets them.
--------------------------------------------------------------------------
local MAIN_PATH = STD.getenv("TACOTIP_MAIN_OVERRIDE") or (ROOT .. "main.lua")
local LIB_PATH = STD.getenv("TACOTIP_LIB_OVERRIDE")
    or (ROOT .. "Libs/LibForeverInspector/LibForeverInspector.lua")
local GS_PATH = STD.getenv("TACOTIP_GS_OVERRIDE") or (ROOT .. "gearscore.lua")
local OPTIONS_PATH = STD.getenv("TACOTIP_OPTIONS_OVERRIDE") or (ROOT .. "options.lua")

local order = {
    ROOT .. "Libs/LibStub/LibStub.lua",
    ROOT .. "Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua",
    ROOT .. "Libs/LibDetours-1.0/LibDetours-1.0.lua",
    LIB_PATH,
    ROOT .. "Locale/deDE.lua", ROOT .. "Locale/esES.lua", ROOT .. "Locale/esMX.lua",
    ROOT .. "Locale/frFR.lua", ROOT .. "Locale/itIT.lua", ROOT .. "Locale/koKR.lua",
    ROOT .. "Locale/ptBR.lua", ROOT .. "Locale/ruRU.lua", ROOT .. "Locale/zhCN.lua",
    ROOT .. "Locale/zhTW.lua", ROOT .. "Locale/enUS.lua",
    GS_PATH, ROOT .. "pawn.lua", ROOT .. "textures.lua", OPTIONS_PATH, MAIN_PATH,
}
local loadFail
for _, path in STD.ipairs(order) do
    local chunk, err = STD.loadfile(path)
    if (not chunk) then loadFail = path .. " -> " .. tostring(err); break end
    local ok, errs = STD.pcall(chunk, "TacoTip_Forever")
    if (not ok) then loadFail = path .. " -> " .. tostring(errs); break end
end
if (loadFail) then
    STD.io.write("CONTRACT load FAIL " .. tostring(loadFail) .. "\n")
    STD.os.exit(1)
end

local TT = REALG.TacoTip_Forever
local GT = REALG.GameTooltip
local CI = REALG.LibStub and REALG.LibStub("LibForeverInspector", true) or nil
local C = REALG.TacoTipConfig

local checks = {}
local function check(name, cond, detail)
    checks[#checks + 1] = { name, cond and true or false, detail }
end

--------------------------------------------------------------------------
-- The secret-values model.
--
-- A secret value is opaque: the add-on may only ask issecretvalue /
-- canaccessvalue about it, and the tainted answer to that question is a THROW.
-- The sentinel also raises on tostring/concat/arithmetic/index, so an operation
-- the client forbids on a secret value fails the pin loudly instead of being
-- silently tolerated.
--------------------------------------------------------------------------
local SECRET = STD.setmetatable({}, {
    __tostring = function() STD.error("secret value: tostring", 0) end,
    __concat = function() STD.error("secret value: concatenation", 0) end,
    __add = function() STD.error("secret value: arithmetic", 0) end,
    __sub = function() STD.error("secret value: arithmetic", 0) end,
    __mul = function() STD.error("secret value: arithmetic", 0) end,
    __div = function() STD.error("secret value: arithmetic", 0) end,
    __len = function() STD.error("secret value: length", 0) end,
    __index = function() STD.error("secret value: indexed", 0) end,
    __newindex = function() STD.error("secret value: assigned", 0) end,
})

describe = function(v)
    if (STD.rawequal(v, SECRET)) then return "<secret>" end
    if (STD.type(v) == "table") then return "<table>" end
    return STD.tostring(v)
end

-- Breadth-first upvalue search: file-locals are `local`, so the loaded
-- closure graph is the only way to run the SHIPPED helper rather than a copy.
local function upvalueNamed(fn, wanted, depth)
    if (STD.type(fn) ~= "function" or not DEBUG or not DEBUG.getupvalue) then return nil end
    depth = depth or 2
    local seen, queue, head = {}, { { fn, 0 } }, 1
    while head <= #queue do
        local cur, d = queue[head][1], queue[head][2]
        head = head + 1
        if (not seen[cur]) then
            seen[cur] = true
            local i = 1
            while true do
                local name, value = DEBUG.getupvalue(cur, i)
                if (not name) then break end
                if (name == wanted and STD.type(value) == "function") then return value end
                if (d < depth and STD.type(value) == "function") then
                    queue[#queue + 1] = { value, d + 1 }
                end
                i = i + 1
            end
        end
    end
    return nil
end

local secretAsks = 0
local function throwingSecret()
    REALG.issecretvalue = function(v)
        secretAsks = secretAsks + 1
        if (STD.rawequal(v, SECRET)) then
            STD.error("issecretvalue on a secret value from tainted execution", 0)
        end
        return false
    end
end
local function clearSecret()
    REALG.issecretvalue = nil
    REALG.canaccesstable = nil
end

-- Refusal counters for SecretArguments="AllowedWhenUntainted" functions: the
-- client raises at the CALL when the argument is secret, before any pcall
-- around the call can protect the answer.
local refused = {}
local function refusing(name)
    -- NOTE: the parameter is deliberately NOT named `arg`. Lua 5.1 gives every
    -- vararg function an implicit legacy `arg` local, and a parameter of that
    -- name is shadowed by it -- the refusal silently received nil and the whole
    -- argument-hazard pin was vacuous until this was found.
    return function(value, ...)
        if (STD.rawequal(value, SECRET)) then
            refused[name] = (refused[name] or 0) + 1
            STD.error("bad argument #1 to '" .. name
                .. "' (Secret values are only allowed during untainted execution for this argument.)", 0)
        end
        if (ORIG[name]) then return ORIG[name](value, ...) end
    end
end
local REFUSAL_APIS = {
    "UnitExists", "UnitIsPlayer", "UnitIsConnected", "UnitIsDeadOrGhost",
    "UnitCanAttack", "UnitLevel", "UnitGUID", "UnitClass", "UnitPowerMax",
    "UnitPower", "UnitPowerType", "UnitInRaid", "UnitPVPName", "UnitIsUnit",
}
local function installRefusals()
    refused = {}
    for _, name in STD.ipairs(REFUSAL_APIS) do OV[name] = refusing(name) end
end
local function clearRefusals()
    refused = {}
    for _, name in STD.ipairs(REFUSAL_APIS) do OV[name] = nil end
end
local function refusalCount()
    local n = 0
    for _, v in STD.pairs(refused) do n = n + v end
    return n
end

--------------------------------------------------------------------------
-- Loaded-state assertions.
--------------------------------------------------------------------------
check("addon loads on the Forever model", STD.type(TT) == "table")
check("load completed (LOAD_OK, stage complete)", TT and TT.LOAD_OK == true,
    "stage=" .. describe(TT and TT.LOAD_STAGE))
check("inspector and gearscore loaded", CI ~= nil and STD.type(REALG.TT_GS) == "table")
check("unit tooltip delivered by the data post-call", REALG.POSTCALLS
    and (function()
        for _, rec in STD.ipairs(REALG.POSTCALLS) do
            if (rec.typ == REALG.Enum.TooltipDataType.Unit) then return true end
        end
        return false
    end)())

--------------------------------------------------------------------------
-- Config for the surfaces below.
--------------------------------------------------------------------------
if (TT.ApplyConfigDefaults) then STD.pcall(TT.ApplyConfigDefaults, TT, C) end
C.show_gs_player = true
C.show_avg_ilvl = true
C.show_ilvl_inline = false
C.show_talents = false
C.show_guild_name = true
C.show_guild_rank = true
C.show_target = true
C.color_class = true
C.show_pawn_player = false
C.show_item_level = true
C.show_gs_items = true
C.show_separators = false
C.show_realm = false
C.tooltip_border_use_class = false
C.tooltip_portrait = false
C.tooltip_portrait_3d = false
C.hide_in_combat = false
C.show_power_bar = true
C.show_hp_bar = false
C.tip_style = 1

local UNIT_POST, ITEM_POST
for _, rec in STD.ipairs(REALG.POSTCALLS) do
    if (rec.typ == REALG.Enum.TooltipDataType.Unit) then UNIT_POST = rec.fn end
    if (rec.typ == REALG.Enum.TooltipDataType.Item) then ITEM_POST = rec.fn end
end

local function allText()
    local out = {}
    local n = GT:NumLines()
    for i = 1, n do
        local l = GT:GetLeftLine(i)
        local r = GT:GetRightLine(i)
        local lt = l and l:GetText()
        local rt = r and r:GetText()
        if (lt ~= nil and lt ~= "") then out[#out + 1] = describe(lt) end
        if (rt ~= nil and rt ~= "") then out[#out + 1] = describe(rt) end
    end
    return STD.table.concat(out, "\n")
end

local function seedUnit(unitToken)
    GT:ClearLines()
    for _, line in STD.ipairs(CLIENT_SEED[unitToken] or {}) do GT:AddLine(line) end
end

-- Seed the inspector cache for a unit, the record main.lua and gearscore read.
local function seedCache(unitToken, mode)
    local guid = UNITS[unitToken].guid
    local items = {}
    if (mode == "full") then
        for slot = 1, 18 do
            if (slot ~= 4) then items[slot] = GEAR_LINK end
        end
    end
    CI.cache = CI.cache or {}
    CI.cache[guid] = { time = REALG.__testClock, items = items }
end

local function driveUnit(unitToken, data)
    currentUnit = unitToken
    GT.__unit = unitToken
    GT.__shown = true
    GT.GetUnit = function() return "n", unitToken end
    GT.GetOwner = function() return { unit = unitToken } end
    REALG.TooltipUtil.GetDisplayedUnit = function()
        return "n", unitToken, UNITS[unitToken] and UNITS[unitToken].guid or nil
    end
    local before = tonumber(TT.totalErrorsCaught) or 0
    local ok, err = STD.pcall(UNIT_POST, GT, data or { guid = UNITS[unitToken].guid })
    return ok, err, (tonumber(TT.totalErrorsCaught) or 0) - before
end

local function textHas(needle)
    return STD.string.find(allText(), needle, 1, true) ~= nil
end

local ORIG_GETITEMINFO = REALG.C_Item.GetItemInfo
local ORIG_BARE_GETITEMINFO = REALG.GetItemInfo

--------------------------------------------------------------------------
-- META: the mock contract itself, pinned first. If the predicate ever stops
-- throwing, every pin below silently returns to modelling a never-throwing
-- client -- the exact gap this file exists to close.
--------------------------------------------------------------------------
do
    throwingSecret()
    local thrown = STD.pcall(REALG.issecretvalue, SECRET)
    check("meta: the mock issecretvalue THROWS on a secret value (the client's " ..
        "tainted-call contract)", thrown == false, "pcall returned " .. describe(thrown))
    local plainOk, plainValue = STD.pcall(REALG.issecretvalue, "player")
    check("meta: the same mock answers a plain value normally",
        plainOk == true and plainValue == false,
        "ok=" .. describe(plainOk) .. " value=" .. describe(plainValue))
    local guardOk, isSecret = STD.pcall(TT.isSecretValue, SECRET)
    check("meta: the shipped strong guard reads that throw as 'secret'",
        guardOk and isSecret == true, "guard=" .. describe(isSecret))
    local formatted = STD.pcall(function()
        return STD.string.format("%s", SECRET)
    end)
    check("meta: the sentinel raises when a forbidden operation formats it, so a " ..
        "leaked secret fails a pin loudly", formatted == false)
    clearSecret()
end

--------------------------------------------------------------------------
-- A. UnitGUID -- result WOWGUID **Nilable**, SecretWhenUnitIdentityRestricted.
--    Fix: main.lua TT.safeUnitGUID / LFI safeUnitGUID nil test is
--    `type(guid) == "nil"`, never a comparison on a value that may be secret.
-- ---------------------------------------------------------------------------
do
    -- A1: the client's own nil answer ("no such unit") is nil, not an error.
    OV.UnitGUID = function() return nil end
    local ok, guid = STD.pcall(TT.safeUnitGUID, "target")
    check("UnitGUID nil (SHAPE): a nil WOWGUID reads as 'unknown' and never raises",
        ok and guid == nil,
        "red on a copy whose nil test is `guid == nil`; HEAD's `not guid` is "
            .. "behaviourally equivalent for a string|nil return, so this pin owns the RULE")

    -- A2: secret-nil. The answer is nil AND the client refuses to be asked
    -- about it (identity restriction). The nil must be classified by type(),
    -- never handed to the predicate.
    local nilAsks = 0
    REALG.issecretvalue = function(v)
        if (STD.type(v) == "nil") then
            nilAsks = nilAsks + 1
            STD.error("identity-restricted: no secret answers available", 0)
        end
        return false
    end
    OV.UnitGUID = function() return nil end
    ok, guid = STD.pcall(TT.safeUnitGUID, "target")
    check("UnitGUID secret-nil (SHAPE): a nil answer under identity restriction is " ..
        "classified by type(), not by asking the predicate",
        ok and guid == nil and nilAsks == 0,
        "nilAsks=" .. describe(nilAsks) .. "; red on a copy that calls "
            .. "isSecretValue(guid) before the nil test")

    -- A3: a secret GUID is not a GUID. The guard answers "unknown"; the sentinel
    -- raises if the add-on formats, concatenates or indexes it.
    throwingSecret()
    OV.UnitGUID = function() return SECRET end
    ok, guid = STD.pcall(TT.safeUnitGUID, "target")
    check("UnitGUID secret (RED-AT-HEAD for the guard form): an unreadable GUID " ..
        "reads as unknown, never as a value",
        ok and guid == nil, "guid=" .. describe(guid))

    -- A4: a raising UnitGUID (client refusal) is not an error in the helper.
    OV.UnitGUID = function() STD.error("UnitGUID refused", 0) end
    ok, guid = STD.pcall(TT.safeUnitGUID, "target")
    check("UnitGUID raising: a pcall failure reads as unknown", ok and guid == nil)

    -- A5: the argument hazard. A secret unit TOKEN must not reach UnitGUID,
    -- whose argument is SecretArguments="AllowedWhenUntainted".
    local calls = 0
    throwingSecret()
    OV.UnitGUID = function(u) calls = calls + 1; return "Player-1-000001" end
    ok, guid = STD.pcall(TT.safeUnitGUID, SECRET)
    check("UnitGUID argument: a secret unit token is never passed to UnitGUID",
        ok and guid == nil and calls == 0, "calls=" .. describe(calls))

    -- A6: the guard itself. The strong form reads a THROW as "secret"; the weak
    -- form (`okSecret and isSec`) reads the one unverifiable answer as "plain".
    throwingSecret()
    check("secret guard (RED-AT-HEAD for the weak form): a THROWING issecretvalue " ..
        "reads as secret", TT.isSecretValue(SECRET) == true)

    OV.UnitGUID = nil
    clearSecret()
end

--------------------------------------------------------------------------
-- B. UnitInRaid -- result **luaIndex Nilable**: nil outside a raid, a raid
--    INDEX (a number) inside one. Fix: `type(inR) == "number"` is the
--    predicate; a boolean reading drops the player inside a raid.
-- ---------------------------------------------------------------------------
do
    OV.UnitInRaid = function() return nil end
    local ok, inRaid = STD.pcall(TT.safeUnitInRaid, "target")
    check("UnitInRaid nil outside a raid (SHAPE): reads as not-in-a-raid, not a raise",
        ok and inRaid == false, "red on a copy that treats nil as 'unknown error'")

    OV.UnitInRaid = function() return 3 end
    ok, inRaid = STD.pcall(TT.safeUnitInRaid, "target")
    check("UnitInRaid raid index 3 (SHAPE): a luaIndex reads as in-a-raid",
        ok and inRaid == true,
        "red on a copy returning `inR == true`: index 3 is not the boolean true")

    OV.UnitInRaid = function() return 1 end
    ok, inRaid = STD.pcall(TT.safeUnitInRaid, "target")
    check("UnitInRaid raid index 1 (SHAPE): index 1 is in-a-raid too",
        ok and inRaid == true, "the boolean reading misses the first raid slot")

    throwingSecret()
    OV.UnitInRaid = function() return SECRET end
    ok, inRaid = STD.pcall(TT.safeUnitInRaid, "target")
    check("UnitInRaid secret index: an unreadable index reads as not-in-a-raid",
        ok and inRaid == false, "inRaid=" .. describe(inRaid))

    local calls = 0
    throwingSecret()
    OV.UnitInRaid = function() calls = calls + 1; return 2 end
    ok, inRaid = STD.pcall(TT.safeUnitInRaid, SECRET)
    check("UnitInRaid argument: a secret unit token is never passed to UnitInRaid",
        ok and inRaid == false and calls == 0, "calls=" .. describe(calls))

    OV.UnitInRaid = nil
    clearSecret()
end

--------------------------------------------------------------------------
-- C. UnitClass -- **MayReturnNothing**: the client can publish NO values at
--    all. When it does, every return is nil and that is a shape, not a
--    failure. Fix: the pcall ok flag is the call result; the classFilename is
--    nil and no comparison/indexing may assume a published value.
-- ---------------------------------------------------------------------------
do
    check("item tooltip: the item post-call is registered", STD.type(ITEM_POST) == "function")

    -- C1: the InspectFrame hunter check, with UnitClass answering NOTHING.
    REALG.InspectFrame.unit = "mouseover"
    REALG.InspectFrame.__shown = true
    OV.UnitClass = function() return end -- MayReturnNothing
    REALG.C_Item.GetItemInfo = ORIG_GETITEMINFO
    GT.GetOwner = function() return { unit = "player" } end
    GT:ClearLines()
    GT:AddLine("Test Helm")
    GT:AddLine("Item Level 88")
    local errorsBefore = tonumber(TT.totalErrorsCaught) or 0
    local ok, err = STD.pcall(ITEM_POST, GT, { hyperlink = GEAR_LINK })
    check("UnitClass MayReturnNothing (SHAPE): an item tooltip with the InspectFrame " ..
        "open and UnitClass publishing NO values renders without raising",
        ok and (tonumber(TT.totalErrorsCaught) or 0) == errorsBefore,
        "ok=" .. describe(ok) .. " err=" .. describe(err)
            .. " errors=" .. describe((tonumber(TT.totalErrorsCaught) or 0) - errorsBefore)
            .. "; red on a copy that indexes/formats the classFilename")

    -- C2: control -- the add-on actually calls UnitClass there, so C1 is not a
    -- vacuous branch.
    local classCalls = 0
    OV.UnitClass = function(u) classCalls = classCalls + 1; return "Hunter", "HUNTER", 3 end
    GT:ClearLines()
    GT:AddLine("Test Helm")
    GT:AddLine("Item Level 88")
    STD.pcall(ITEM_POST, GT, { hyperlink = GEAR_LINK })
    check("UnitClass control: the InspectFrame hunter check calls UnitClass for the open frame",
        classCalls > 0, "calls=" .. describe(classCalls))
    OV.UnitClass = nil
    REALG.InspectFrame.unit = nil
end

--------------------------------------------------------------------------
-- D. GetItemInfo -- **MayReturnNothing**, and its itemInfo argument is
--    SecretArguments="AllowedWhenUntainted". Returning nothing means "the item
--    is not loaded yet" -- not an error and not "no such item".
-- ---------------------------------------------------------------------------
do
    -- On Forever/Retail the bare GetItemInfo global does not exist: it is the
    -- Blizzard_DeprecatedItemScript alias, and that addon is absent there.
    REALG.GetItemInfo = nil
    C.show_item_level = true
    C.show_gs_items = true
    GT.GetOwner = function() return { unit = "player" } end

    -- D1: the operator surface -- an ITEM tooltip while the item is unloaded.
    REALG.C_Item.GetItemInfo = function() return end -- MayReturnNothing
    REALG.__rawItemRequests = 0
    REALG.__rawItemRequestIDs = {}
    GT:ClearLines()
    GT:AddLine("Test Helm")
    GT:AddLine("Item Level 88")
    local beforeLines = GT:NumLines()
    local errorsBefore = tonumber(TT.totalErrorsCaught) or 0
    local ok, err = STD.pcall(ITEM_POST, GT, { hyperlink = GEAR_LINK })
    check("item tooltip while unloaded (operator surface): renders without raising",
        ok, "err=" .. describe(err))
    check("item tooltip while unloaded (operator surface): no error is recorded",
        (tonumber(TT.totalErrorsCaught) or 0) == errorsBefore,
        "errors=" .. describe((tonumber(TT.totalErrorsCaught) or 0) - errorsBefore))
    check("GetItemInfo nothing (SHAPE): no Item Level / GearScore row is invented " ..
        "from an empty answer", GT:NumLines() == beforeLines,
        "lines " .. describe(beforeLines) .. " -> " .. describe(GT:NumLines()))
    check("item tooltip while unloaded (operator surface): the client is asked to " ..
        "load the item", REALG.__rawItemRequests >= 1
            and REALG.__rawItemRequestIDs[1] == 12345,
        "requests=" .. describe(REALG.__rawItemRequests)
            .. " id=" .. describe(REALG.__rawItemRequestIDs[1]))

    -- D2: a refused GetItemInfo (secret link) raises inside the call; the hook
    -- must still complete and still request the data (the pcall ok flag owns it).
    REALG.C_Item.GetItemInfo = function()
        STD.error("bad argument #1 to 'GetItemInfo' "
            .. "(Secret values are only allowed during untainted execution for this argument.)", 0)
    end
    REALG.__rawItemRequests = 0
    GT:ClearLines()
    GT:AddLine("Test Helm")
    GT:AddLine("Item Level 88")
    beforeLines = GT:NumLines()
    errorsBefore = tonumber(TT.totalErrorsCaught) or 0
    ok, err = STD.pcall(ITEM_POST, GT, { hyperlink = GEAR_LINK })
    check("GetItemInfo refusal (SHAPE): a raising GetItemInfo is the ok flag, not a " ..
        "fatal tooltip error", ok and (tonumber(TT.totalErrorsCaught) or 0) == errorsBefore,
        "ok=" .. describe(ok) .. " errors="
            .. describe((tonumber(TT.totalErrorsCaught) or 0) - errorsBefore))
    check("GetItemInfo refusal (SHAPE): the item load is still requested",
        REALG.__rawItemRequests >= 1,
        "requests=" .. describe(REALG.__rawItemRequests))

    -- D3: control -- a cached item still produces the Item Level and GearScore
    -- rows, so D1's empty answer is the cause of its empty tooltip.
    REALG.C_Item.GetItemInfo = ORIG_GETITEMINFO
    GT:ClearLines()
    GT:AddLine("Test Helm")
    GT:AddLine("Item Level 88")
    STD.pcall(ITEM_POST, GT, { hyperlink = GEAR_LINK })
    check("item tooltip control: a cached item still gets the Item Level row",
        textHas("Item Level 88"), STD.string.gsub(allText(), "\n", " | "))
    check("item tooltip control: a cached item still gets the GearScore row",
        textHas("GearScore:"), STD.string.gsub(allText(), "\n", " | "))

    REALG.GetItemInfo = ORIG_BARE_GETITEMINFO
end

--------------------------------------------------------------------------
-- E. The unit-tooltip GEARSCORE row while the secrecy predicate throws and
--    combat/encounter restrictions are in effect.
--
--    Two corrected sites sit on this surface:
--    * UnitPowerMax / UnitPower can answer SECRET NUMBERS; the old gate
--      compared them (`max ~= nil`) and the comparison raised, taking the bar
--      (and the rest of the render) with it. Fix: `type(v) ~= "nil"` decides
--      presence and the values reach SetMinMaxValues/SetValue untouched.
--    * the unloaded-item path must degrade to "no row + request the data",
--      never to a raise -- and the LibForeverInspector item wrapper is what
--      answers "is this item cached?" on Forever.
-- ---------------------------------------------------------------------------
do
    -- E0: make sure the power bar exists (the unit render creates it).
    seedCache("mouseover", "full")
    seedUnit("mouseover")
    local okUnit, errUnit, errCount = driveUnit("mouseover")
    check("unit tooltip: a normal player render completes", okUnit, describe(errUnit))
    check("unit tooltip: the normal render records no error", errCount == 0,
        "errors=" .. describe(errCount))

    local bar = REALG.TacoTipPowerBar
    check("unit tooltip: the power bar was created by the render", STD.type(bar) == "table")

    -- E1: the secret power values. The bar's Update is the exact code that
    -- used to compare them.
    if (STD.type(bar) == "table" and STD.type(bar.Update) == "function") then
        local minMax, value = nil, nil
        local savedSetMinMax = bar.SetMinMaxValues
        local savedSetValue = bar.SetValue
        bar.SetMinMaxValues = function(_, a, b) minMax = { a, b } end
        bar.SetValue = function(_, v) value = v end

        throwingSecret()
        OV.UnitPowerMax = function() return SECRET end
        OV.UnitPower = function() return SECRET end
        OV.UnitPowerType = function() return 0 end
        local ok, err = STD.pcall(bar.Update, bar, "mouseover")
        check("power bar secret numbers (RED-AT-HEAD: `max ~= nil` raised): the " ..
            "bar update does not raise on a secret power value",
            ok, "err=" .. describe(err))
        check("power bar secret numbers: the secret values reach the tainted-safe " ..
            "sink untouched",
            STD.type(minMax) == "table" and STD.rawequal(minMax[2], SECRET)
                and STD.rawequal(value, SECRET),
            "minMax=" .. describe(minMax and minMax[2]) .. " value=" .. describe(value))

        bar.SetMinMaxValues = savedSetMinMax
        bar.SetValue = savedSetValue
        OV.UnitPowerMax = nil
        OV.UnitPower = nil
        OV.UnitPowerType = nil
        clearSecret()
    end

    -- E2: a unit tooltip render while the current unit's identity is restricted:
    -- the GUID cannot be read, so the GearScore row is unknown. Nothing may
    -- raise, no row may be invented, and no secret token may reach an
    -- AllowedWhenUntainted Unit* call.
    seedCache("mouseovertarget", "full")
    seedUnit("mouseovertarget")
    throwingSecret()
    installRefusals()
    OV.UnitGUID = function(u)
        if (u == "mouseovertarget") then return SECRET end
        return ORIG.UnitGUID(u)
    end
    -- The payload carries no GUID: on a restricted client the tooltip data
    -- cannot be read, so the only GUID source is the (unreadable) unit.
    okUnit, errUnit, errCount = driveUnit("mouseovertarget", {})
    check("unit tooltip under identity restriction (operator surface): the render " ..
        "does not raise and records no error",
        okUnit and errCount == 0,
        "ok=" .. describe(okUnit) .. " errors=" .. describe(errCount)
            .. " err=" .. describe(errUnit))
    check("unit tooltip under identity restriction (operator surface): no GearScore " ..
        "row is invented for an unreadable GUID",
        not textHas("GearScore:"), STD.string.gsub(allText(), "\n", " | "))
    check("unit tooltip under identity restriction: no secret token reaches an " ..
        "AllowedWhenUntainted Unit* argument",
        refusalCount() == 0, "refusals=" .. describe(refusalCount()))
    OV.UnitGUID = nil
    clearRefusals()
    clearSecret()

    -- E3: the unloaded-item GearScore path. A cached inspection whose item data
    -- is not loaded yet must: not raise, register/issue the load request, and
    -- render no fabricated score. On HEAD the LibForeverInspector item wrapper
    -- called the absent bare GetItemInfo global and raised here.
    local savedCache = CI.cache
    seedCache("mouseover", "empty")
    local savedItems = CI.cache[UNITS.mouseover.guid].items
    for slot = 1, 18 do
        if (slot ~= 4) then savedItems[slot] = GEAR_LINK end
    end
    REALG.GetItemInfo = nil
    REALG.C_Item.GetItemInfo = function() return end -- unloaded
    REALG.__rawItemRequests = 0
    REALG.__rawItemRequestIDs = {}
    seedUnit("mouseover")
    okUnit, errUnit, errCount = driveUnit("mouseover")
    check("unit tooltip while item data is unloaded (operator surface, RED-AT-HEAD " ..
        "via the LFI bare-GetItemInfo wrapper): the render does not raise",
        okUnit, describe(errUnit))
    check("unit tooltip while item data is unloaded: no error is recorded",
        errCount == 0, "errors=" .. describe(errCount))
    check("unit tooltip while item data is unloaded: no fabricated GearScore row",
        not textHas("GearScore:"), STD.string.gsub(allText(), "\n", " | "))

    check("unit tooltip while item data is unloaded: the load is requested",
        REALG.__rawItemRequests >= 1,
        "requests=" .. describe(REALG.__rawItemRequests))

    REALG.C_Item.GetItemInfo = ORIG_GETITEMINFO
    REALG.GetItemInfo = ORIG_BARE_GETITEMINFO
    CI.cache = savedCache
end

--------------------------------------------------------------------------
-- E4-E6: the corrected ARGUMENT-HAZARD sites, driven through the SHIPPED
-- closures. UnitPowerMax, UnitCanAttack, UnitIsPlayer, UnitLevel and
-- GetItemInfo all declare SecretArguments="AllowedWhenUntainted": a secret
-- token is refused at CALL time, before any pcall around the call helps. The
-- corrected code tests the token first; the pre-fix code called anyway.
--------------------------------------------------------------------------
do
    local visiblePower = upvalueNamed(UNIT_POST, "tooltipUnitHasVisiblePower", 3)
    local hostColor = upvalueNamed(UNIT_POST, "getHostileDifficultyColor", 3)
    check("argument hazards: the shipped tooltipUnitHasVisiblePower helper is reachable",
        STD.type(visiblePower) == "function",
        "no upvalue named tooltipUnitHasVisiblePower -- it was renamed or restructured")
    check("argument hazards: the shipped getHostileDifficultyColor helper is reachable",
        STD.type(hostColor) == "function",
        "no upvalue named getHostileDifficultyColor -- it was renamed or restructured")

    if (STD.type(visiblePower) == "function") then
        installRefusals()
        throwingSecret()
        local ok, visible = STD.pcall(visiblePower, SECRET)
        check("UnitPowerMax argument (RED-AT-HEAD: pcall(UnitPowerMax, secretToken) was " ..
            "refused at the client): a secret token is refused locally, not at the call",
            ok and visible == false and refusalCount() == 0,
            "ok=" .. describe(ok) .. " visible=" .. describe(visible)
                .. " refusals=" .. describe(refusalCount()))

        -- Control: a plain token still reaches the client query, so the guard
        -- is a token test and not a blanket refusal.
        clearRefusals()
        clearSecret()
        OV.UnitPowerMax = function(u) return (u == "mouseover") and 100 or 0 end
        local okCtrl, visibleCtrl = STD.pcall(visiblePower, "mouseover")
        check("UnitPowerMax control: a plain token still asks the client",
            okCtrl and visibleCtrl == true, describe(visibleCtrl))
        OV.UnitPowerMax = nil
    end

    if (STD.type(hostColor) == "function") then
        installRefusals()
        throwingSecret()
        local ok, color = STD.pcall(hostColor, SECRET)
        check("UnitCanAttack/UnitIsPlayer/UnitLevel argument (RED-AT-HEAD: the three " ..
            "AllowedWhenUntainted queries ran on a secret token): a secret token gets " ..
            "no colour treatment and triggers no refused call",
            ok and color == nil and refusalCount() == 0,
            "ok=" .. describe(ok) .. " color=" .. describe(color)
                .. " refusals=" .. describe(refusalCount()))
        clearRefusals()
        clearSecret()
    end

    -- WarmGearItemData: GetItemInfo's argument is AllowedWhenUntainted. HEAD
    -- called pcall(getItemInfo, secretLink) and then string.match(secretLink).
    local guid = UNITS.mouseover.guid
    CI.cache = CI.cache or {}
    local savedCache = CI.cache[guid]
    CI.cache[guid] = { time = REALG.__testClock, items = { [1] = SECRET } }
    local refusingGetItemInfo = function(link)
        if (STD.rawequal(link, SECRET)) then
            STD.error("bad argument #1 to 'GetItemInfo' (Secret values are only "
                .. "allowed during untainted execution for this argument.)", 0)
        end
        return ORIG_GETITEMINFO(link)
    end
    REALG.C_Item.GetItemInfo = refusingGetItemInfo
    throwingSecret()
    local ok, requested = STD.pcall(TT.WarmGearItemData, TT, guid)
    check("WarmGearItemData secret link (RED-AT-HEAD: the secret link reached " ..
        "GetItemInfo and then string.match): skipped locally, no raise",
        ok and requested == false,
        "ok=" .. describe(ok) .. " requested=" .. describe(requested))
    REALG.C_Item.GetItemInfo = ORIG_GETITEMINFO
    clearSecret()
    CI.cache[guid] = savedCache
end

--------------------------------------------------------------------------
-- F. LibForeverInspector -- the two corrected sites on the item/inspect paths.
-- ---------------------------------------------------------------------------
do
    -- F1: the item wrapper the GearScore path receives for an uncached slot.
    -- Fix: namespace-first resolve + function guard + the pcall ok flag; the
    -- bare global does not exist on Forever/Retail.
    local createItemWrapper = upvalueNamed(CI.GetInventoryItemMixin, "createItemWrapper", 2)
    check("LFI: the file-local createItemWrapper was found in the loaded chunk",
        STD.type(createItemWrapper) == "function",
        "no upvalue named createItemWrapper -- the wrapper was renamed or restructured")

    if (STD.type(createItemWrapper) == "function") then
        REALG.GetItemInfo = nil -- Forever/Retail: no bare global
        REALG.C_Item.GetItemInfo = function() return end -- unloaded, MayReturnNothing
        local wrapper
        local okWrap, errWrap = STD.pcall(function() wrapper = createItemWrapper(GEAR_LINK) end)
        check("LFI item wrapper: an unloaded item builds without raising",
            okWrap and STD.type(wrapper) == "table", describe(errWrap))
        if (STD.type(wrapper) == "table") then
            local ok, cached = STD.pcall(wrapper.IsItemDataCached)
            check("LFI item wrapper (RED-AT-HEAD: bare GetItemInfo raised on Forever): " ..
                "GetItemInfo returning nothing reads as 'not cached', not as an error",
                ok and cached == false,
                "ok=" .. describe(ok) .. " cached=" .. describe(cached))
            check("LFI item wrapper: GetItemLink is the original link (Nilable site)",
                wrapper.GetItemLink() == GEAR_LINK)

            REALG.C_Item.GetItemInfo = function(link)
                return "Test Helm", link, 4, 88
            end
            local okCached, cached2 = STD.pcall(wrapper.IsItemDataCached)
            check("LFI item wrapper: a cached item reads as cached", okCached and cached2 == true,
                "cached=" .. describe(cached2))

            REALG.C_Item.GetItemInfo = function()
                STD.error("bad argument #1 to 'GetItemInfo' (Secret values are only "
                    .. "allowed during untainted execution for this argument.)", 0)
            end
            local okRef, cached3 = STD.pcall(wrapper.IsItemDataCached)
            check("LFI item wrapper: a refused GetItemInfo is the ok flag, not a raise",
                okRef and cached3 == false,
                "ok=" .. describe(okRef) .. " cached=" .. describe(cached3))
        end
        REALG.C_Item.GetItemInfo = ORIG_GETITEMINFO
        REALG.GetItemInfo = ORIG_BARE_GETITEMINFO
    end

    -- F2: PlayerGUIDToUnitToken, the InspectFrame branch. Fix: safeUnitExists
    -- replaces a bare UnitExists whose argument is AllowedWhenUntainted; a
    -- secret InspectFrame.unit used to be refused at the call and raise.
    REALG.InspectFrame.unit = SECRET
    installRefusals()
    throwingSecret()
    local okTok, token = STD.pcall(CI.PlayerGUIDToUnitToken, CI, "<unknown-guid>")
    check("LFI PlayerGUIDToUnitToken (RED-AT-HEAD: bare UnitExists refused a secret " ..
        "InspectFrame.unit): a secret frame unit does not raise",
        okTok, describe(token))
    check("LFI PlayerGUIDToUnitToken: ...and answers no token", okTok and token == nil,
        "token=" .. describe(token))
    check("LFI PlayerGUIDToUnitToken: ...so UnitExists is never handed the secret token",
        refusalCount() == 0, "refusals=" .. describe(refusalCount()))

    -- control: a plain InspectFrame.unit still resolves through the same branch.
    clearRefusals()
    clearSecret()
    REALG.InspectFrame.unit = "target"
    okTok, token = STD.pcall(CI.PlayerGUIDToUnitToken, CI, UNITS.target.guid)
    check("LFI PlayerGUIDToUnitToken control: a plain frame unit still resolves",
        okTok and token == "target", "token=" .. describe(token))
    REALG.InspectFrame.unit = nil
end

--------------------------------------------------------------------------
-- G. gearscore -- the item receivers on the weapon path.
--    Fix: the ItemLocation receivers are secrecy-tested before they are
--    indexed; the methods behind them are C_Item.* with
--    SecretArguments="AllowedWhenUntainted".
-- ---------------------------------------------------------------------------
do
    local guid = UNITS.mouseover.guid
    CI.cache = CI.cache or {}
    CI.cache[guid] = { time = REALG.__testClock, items = {} }
    for slot = 1, 18 do
        if (slot ~= 4) then CI.cache[guid].items[slot] = GEAR_LINK end
    end
    local savedGIMM = CI.GetInventoryItemMixin

    -- G1: a secret weapon receiver is not indexed. HEAD called
    -- mainHandItem:IsItemDataCached() on it; the sentinel raises on index.
    throwingSecret()
    CI.GetInventoryItemMixin = function(_, u, slot)
        if (slot == 16) then return SECRET end
        return savedGIMM(CI, u, slot)
    end
    local ok, score, ilvl = STD.pcall(REALG.TT_GS.GetScore, REALG.TT_GS, guid, false)
    check("gearscore secret main-hand item (RED-AT-HEAD: the receiver was indexed): " ..
        "GetScore does not raise", ok, describe(score))
    CI.GetInventoryItemMixin = savedGIMM
    clearSecret()

    -- G2: GetItemLink is Nilable -- an unloaded item can answer nil even when
    -- IsItemDataCached() said true. A nil link must not be COUNTED: every
    -- scored slot here answers level 88, so a nil link added to ItemCount
    -- without adding a level drags the average down and is visible.
    local fake = {
        IsItemDataCached = function() return true end,
        GetItemLink = function() return nil end,
        GetItemID = function() return 12345 end,
    }
    CI.GetInventoryItemMixin = function(_, u, slot)
        if (slot == 16 or slot == 17) then return fake end
        return savedGIMM(CI, u, slot)
    end
    ok, score, ilvl = STD.pcall(REALG.TT_GS.GetScore, REALG.TT_GS, guid, false)
    check("GetItemLink nil for an unloaded item (SHAPE): a nil weapon link is not " ..
        "counted as an item and does not raise",
        ok and score > 0 and ilvl == 88,
        "ok=" .. describe(ok) .. " score=" .. describe(score) .. " ilvl=" .. describe(ilvl)
            .. "; red on a copy that counts/dereferences the nil link (ilvl 82)")
    CI.GetInventoryItemMixin = savedGIMM
end

--------------------------------------------------------------------------
-- H. options.lua -- the leaderboard's "is this me" read.
--    Fix: the bare `UnitGUID("player")` was compared against cached GUIDs with
--    no secrecy test (a secret raises on `==`). The file-local playerGUID now
--    resolves main.lua's TT.safeUnitGUID, which answers nil when unreadable.
-- ---------------------------------------------------------------------------
do
    local playerGUID
    for _, root in STD.ipairs({ { TT.ShowStandaloneDashboard, "ShowStandaloneDashboard" },
                                { TT.ToggleStandaloneDashboard, "ToggleStandaloneDashboard" },
                                { TT.RefreshOptionsUI, "RefreshOptionsUI" } }) do
        if (STD.type(playerGUID) ~= "function") then
            playerGUID = upvalueNamed(root[1], "playerGUID", 4)
        end
    end
    check("options: the leaderboard's file-local playerGUID helper is in the loaded chunk",
        STD.type(playerGUID) == "function",
        "no upvalue named playerGUID -- the leaderboard went back to a bare UnitGUID("
            .. "'player') and compares a possibly-secret result")

    if (STD.type(playerGUID) == "function") then
        -- The bare global must not be the path. Give it a tripwire that raises.
        local savedGUID = REALG.UnitGUID
        local bareCalls = 0
        REALG.UnitGUID = function() bareCalls = bareCalls + 1; STD.error("options read UnitGUID directly", 0) end
        local safeCalls = 0
        local savedSafe = TT.safeUnitGUID
        TT.safeUnitGUID = function(u) safeCalls = safeCalls + 1; return nil end
        local ok, guid = STD.pcall(playerGUID)
        check("options leaderboard (RED-AT-HEAD: bare UnitGUID compared a secret GUID): " ..
            "the player GUID is resolved through TT.safeUnitGUID",
            ok and guid == nil and safeCalls == 1 and bareCalls == 0,
            "ok=" .. describe(ok) .. " safe=" .. describe(safeCalls)
                .. " bare=" .. describe(bareCalls))
        TT.safeUnitGUID = savedSafe
        REALG.UnitGUID = savedGUID
    end
end

--------------------------------------------------------------------------
-- H. gearscore -- the GetItemInfo choke point (the file-scope wrapper).
--    C_Item.GetItemInfo is MayReturnNothing + SecretArguments =
--    "AllowedWhenUntainted" (ItemDocumentation.lua:626-640 on Forever): the
--    LINK is the gated input and the returns carry no secret predicate. So the
--    wrapper must test the link (a secret link never reaches the call), pcall
--    the call, and answer nil when it refuses -- nil is every caller's existing
--    "not cached" shape, while a raise would abort the item-tooltip post-call.
-- ---------------------------------------------------------------------------
do
    throwingSecret()
    local calls = 0
    local saved = REALG.C_Item.GetItemInfo
    REALG.C_Item.GetItemInfo = function(link)
        calls = calls + 1
        if (STD.rawequal(link, SECRET)) then
            STD.error("bad argument #1 to 'GetItemInfo' (Secret values are only "
                .. "allowed during untainted execution for this argument.)", 0)
        end
        return nil
    end

    local okSecret, secretScore = STD.pcall(REALG.TT_GS.GetItemScore, REALG.TT_GS, SECRET)
    check("gearscore: a secret link never reaches C_Item.GetItemInfo and answers 0",
        okSecret and secretScore == 0 and calls == 0,
        "ok=" .. describe(okSecret) .. " score=" .. describe(secretScore)
            .. " calls=" .. describe(calls))

    REALG.C_Item.GetItemInfo = function() STD.error("refused", 0) end
    local okRefuse, refusedScore = STD.pcall(REALG.TT_GS.GetItemScore, REALG.TT_GS, "item:12345")
    check("gearscore: a refused GetItemInfo answers 0 instead of raising",
        okRefuse and refusedScore == 0,
        "ok=" .. describe(okRefuse) .. " score=" .. describe(refusedScore))

    REALG.C_Item.GetItemInfo = saved
    clearSecret()
end

--------------------------------------------------------------------------
-- Report.
--------------------------------------------------------------------------
local fails = 0
for _, c in STD.ipairs(checks) do
    if (not c[2]) then
        fails = fails + 1
        STD.io.write("  FAIL " .. describe(c[1]) .. " :: " .. describe(c[3] or "") .. "\n")
    end
end
STD.io.write("CONTRACT pins: " .. describe(#checks - fails) .. "/" .. describe(#checks)
    .. " passed\n")
if (fails > 0) then STD.os.exit(1) end
