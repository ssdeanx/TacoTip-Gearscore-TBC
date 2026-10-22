-- Batch 8 pins for the MAIN add-on: the character / inspect pane overlays and
-- the instant-fade mode.
--
-- Usage: lua5.1 batch8_pane_test.lua <projectId> <iface> <label> [pipeline]
--
-- WHY THIS FILE EXISTS (arbiter H1 and N2, bench/audits/
-- 2026-10-19-main-addon-arbiter-audit.md).
--
-- H1: the character and inspect pane overlays could sit on "0". PaperDollFrame
-- and InspectPaperDollFrame carry NO `hidden` attribute on any of the five
-- branches -- they are shown from the moment they are created, so their
-- OnShow fired long before this addon loaded and the hooks on them could
-- never fire again. CharacterFrame and InspectFrame DO carry hidden="true",
-- so THEIR OnShow fires once per pane open. The overlays now hang off those.
--
-- The mirror evidence (all five branches -- origin/classic_era,
-- origin/classic_anniversary, origin/classic_titan, origin/forever,
-- origin/live):
--   <Frame name="PaperDollFrame" setAllPoints="true" ...>        (no hidden)
--   <Frame name="InspectPaperDollFrame" setAllPoints="true" ...> (no hidden)
--   <Frame name="CharacterFrame" toplevel="true" ... hidden="true" ...>
--   <Frame name="InspectFrame" toplevel="true" ... hidden="true" ...>
--
-- N2: the instant-fade mode was recorded in TT.InstantFadeMode and printed
-- NOWHERE, so "the toggle does nothing" and "the toggle is off" looked
-- identical to the player. /tacotip diag now prints the mode.
--
-- The environment follows taint_test.lua (the same sandbox, the same mocked
-- client, the same ADDON_LOADED drive), because the pins need the real
-- ADDON_LOADED path: the overlay's one-shot initialiser runs there.
--
-- Pin (a): GameTooltip.FadeOut is never replaced when instant_fade is on.
-- The old Detours:DetourHook swapped the Blizzard method for addon code, so
-- any secure path that faded the tooltip ran tainted code. The fix uses a
-- hooksecurefunc post-hook, which preserves the original function identity.
-- Asserts: TT.detours has no FadeOut entry (detour absent), TT.hooks has the
-- secure entry, and the GT.FadeOut reference is identical before/after.
-- Pin (b): the GameTooltip_SetDefaultAnchor post-hook no-ops on non-unit
-- owners. Menu/popup hovers must pass through without a single
-- SetOwner/SetPoint/ClearAllPoints/EnableMouse call; unit owners still
-- reposition (no valid-state behaviour change).

local _hp = ((arg and arg[0]) or "Tests/harness/taint_test.lua"):gsub("\\", "/")
local _hd = _hp:match("^(.*)/[^/]*$") or "."
local ROOT = dofile(_hd .. "/root.lua") .. "/"
local MOCKC = dofile(_hd .. "/mock_contract.lua")

local projectId, iface, label = tonumber(arg[1]), tonumber(arg[2]), arg[3]
MOCKC.setFamily(MOCKC.normaliseFamily(label))
local usePipeline = (arg[4] == "pipeline")

local REALG = _G
local unpack = unpack or table.unpack

local STD = { os=os, string=string, pairs=pairs, ipairs=ipairs, type=type, pcall=pcall,
    tonumber=tonumber, tostring=tostring, select=select, rawget=rawget, rawset=rawset,
    setmetatable=setmetatable, getmetatable=getmetatable, unpack=unpack, assert=assert,
    error=error, math=math, table=table, loadfile=loadfile, print=print, io=io,
    xpcall=function(f, handler, ...)
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
    next=next }

local baseTable = table
local baseNext = next
STD.table = setmetatable({
    wipe = baseTable.wipe or function(t)
        for k in baseNext, t do t[k] = nil end
        return t
    end,
}, { __index = baseTable })

-- Post-hook registries. Table-form hooksecurefunc (SecureHook) is modelled
-- faithfully: the method itself is NEVER replaced, post-hooks run from inside
-- the stable dispatcher. String-form (anchor hook) chains the same way.
local TABLE_HOOKS = {}
local SECURE_HOOKS = {}

local function newFrame(kind, name, parent)
    local f = { __kind = kind, __name = name, __parent = parent }
    f.__scripts = { OnLoad = true, OnShow = true, OnHide = true,
        OnEvent = true, OnUpdate = true, OnSizeChanged = true, OnEnter = true, OnLeave = true }
    f.__events = {}
    f.HasScript = function(self, n) return self.__scripts[n] == true end
    f.SetScript = function(self, n, fn)
        self.__scripts[n] = true
        self["__script_" .. n] = fn
        return true
    end
    f.GetScript = function(self, n) return self["__script_" .. n] end
    f.HookScript = function(self, s, fn)
        if (self.HasScript and not self:HasScript(s)) then
            error("bad argument #2 to 'HookScript'", 2)
        end
        self["__hook_" .. tostring(s)] = fn
    end
    f.__points = {}
    f.__setPointCalls = 0
    f.__clearCalls = 0
    f.__setOwnerCalls = 0
    f.__enableMouseCalls = 0
    f.SetPoint = function(_, p, rel, rp, ox, oy)
        f.__setPointCalls = f.__setPointCalls + 1
        local relName = rel
        if (type(rel) == "table") then
            relName = (rel.GetName and rel:GetName()) or nil
        end
        f.__points[#f.__points + 1] = { p, relName, rp, ox or 0, oy or 0 }
    end
    f.ClearAllPoints = function()
        f.__clearCalls = f.__clearCalls + 1
        f.__points = {}
    end
    f.GetNumPoints = function() return #f.__points end
    f.GetPoint = function(_, i)
        local q = f.__points[i or 1]
        if (not q) then return nil end
        return q[1], q[2], q[3], q[4], q[5]
    end
    f.GetName = function() return name end
    f.GetParent = function() return parent end
    f.GetObjectType = function() return kind end
    f.IsObjectType = function(_, t) return t == kind end
    f.Show = function() f.__shown = true end
    f.Hide = function() f.__shown = false end
    f.IsShown = function() return f.__shown and true or false end
    f.SetShown = function(_, v) f.__shown = v and true or false end
    f.EnableMouse = function()
        f.__enableMouseCalls = f.__enableMouseCalls + 1
    end
    f.SetOwner = function()
        f.__setOwnerCalls = f.__setOwnerCalls + 1
    end
    f.RegisterEvent = function(_, e)
        f.__events = f.__events or {}
        f.__events[#f.__events + 1] = e
    end
    f.UnregisterEvent = function() end
    -- Text state is REAL, not a no-op: the overlay pins read the score the
    -- pane painted, and a mock whose SetText discards its argument would make
    -- every one of those assertions vacuously true.
    f.__text = nil
    f.SetText = function(_, t) f.__text = t end
    f.GetText = function() return f.__text end
    f.SetFont = function() end
    f.SetFontObject = function() end
    f.SetTextColor = function() end
    f.GetTextColor = function() return 1, 1, 1 end
    f.CreateFontString = function(_, n)
        local c = newFrame("FontString", n, f)
        if (n) then rawset(REALG, n, c) end
        return c
    end
    f.CreateTexture = function(_, n)
        local c = newFrame("Texture", n, f)
        if (n) then rawset(REALG, n, c) end
        return c
    end
    local mt = {}
    mt.__index = function(t, k)
        -- __absent is consulted FIRST, and via rawget: reading t.__absent
        -- through this same __index would recurse. A mock that gives every
        -- widget every method cannot model a client that does NOT have a
        -- method -- and "this client has no GameTooltip.FadeOut" is exactly
        -- the case the N2 pin needs. (Same order as tooltip_test.lua.)
        local absent = rawget(t, "__absent")
        if (absent and absent[k]) then return nil end
        local v = rawget(t, k)
        if (v ~= nil) then return v end
        -- Data fields must read as nil, not as a no-op function: the anchor
        -- hook tests parent.action / parent.spellId / owner.unit for
        -- presence, and a function there is truthy, which would make every
        -- menu look like an action button.
        if (k == "action" or k == "spellId" or k == "unit") then return nil end
        return function() return nil end
    end
    return setmetatable(f, mt)
end

for k in STD.pairs(REALG) do REALG[k] = nil end
for k, v in STD.pairs(STD) do REALG[k] = v end
REALG._G = REALG
REALG.time = STD.os.time
REALG.CreateFrame = function(kind, name, parent, template)
    return newFrame(kind, name, parent)
end
REALG.print = function() end
REALG.geterrorhandler = function() return function() end end
REALG.GetLocale = function() return "enUS" end
REALG.GetCVar = function() return "" end
REALG.SetCVar = function() end
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
REALG.LoadAddOn = function() return true end
REALG.GetBuildInfo = function() return "1.15.9", "1", "d", iface, "us", "rel" end
REALG.WOW_PROJECT_MAINLINE = 1
REALG.WOW_PROJECT_CLASSIC = 2
REALG.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
REALG.WOW_PROJECT_WRATH_CLASSIC = 11
REALG.WOW_PROJECT_CATACLYSM_CLASSIC = 14
REALG.WOW_PROJECT_MISTS_CLASSIC = 19
REALG.WOW_PROJECT_ID = projectId
REALG.C_AddOns = { GetAddOnMetadata = function() return nil end, IsAddOnLoaded = function() return false end }
REALG.C_Item = { GetItemInfo = function() return nil end, IsEquippableItem = function() return true end,
    RequestLoadItemDataByID = function() end, ContinueWithCancelOnItemLoad = function() end,
    GetInventoryItemLink = function() return nil end }
REALG.C_PlayerInfo = { GUIDIsPlayer = function(g)
    return type(g) == "string" and string.find(g, "Player-", 1, true) == 1
end }
REALG.C_Map = { GetBestMapForUnit = function() return nil end }
REALG.C_SpecializationInfo = { GetSpecializationInfo = function() return nil end,
    GetInspectSpecialization = function() return nil end,
    GetActiveSpecGroup = function() return 1 end }
REALG.CAfter = function() end
REALG.C_Timer = { After = function() end, NewTimer = function() return { Cancel = function() end } end,
    NewTicker = function(_, fn) return { Cancel = function() end, func = fn } end }
REALG.Enum = { TooltipDataType = { Item = 0, Unit = 2 } }
if (usePipeline) then
    REALG.TooltipDataProcessor = { AddTooltipPostCall = function() end }
    REALG.TooltipUtil = { GetDisplayedUnit = function() return "n", nil, nil end,
        GetDisplayedItem = function() return "n", nil end }
else
    REALG.TooltipDataProcessor = nil
    REALG.TooltipUtil = nil
end
REALG.UIParent = newFrame("Frame", "UIParent")
REALG.WorldFrame = newFrame("Frame", "WorldFrame")
REALG.PaperDollFrame = newFrame("Frame", "PaperDollFrame")
REALG.InspectFrame = newFrame("Frame", "InspectFrame")
REALG.InspectPaperDollFrame = newFrame("Frame", "InspectPaperDollFrame")
REALG.InspectModelFrame = newFrame("Frame", "InspectModelFrame")
REALG.CharacterModelFrame = usePipeline and nil or newFrame("PlayerModel", "CharacterModelFrame")
-- CharacterFrame is the pane the player OPENS. It carries hidden="true" on
-- every branch, so it starts hidden and its OnShow fires once per open.
REALG.CharacterFrame = newFrame("Frame", "CharacterFrame")
-- PaperDollFrame and InspectPaperDollFrame carry NO hidden attribute on any
-- branch: they are SHOWN from creation. The mock's frames start hidden
-- (newFrame leaves __shown unset, and IsShown() reads that as false), so
-- they are shown explicitly here -- otherwise the mock would model a client
-- that has no paper doll at all.
REALG.PaperDollFrame:Show()
REALG.InspectPaperDollFrame:Show()
if (REALG.CharacterModelFrame) then REALG.CharacterModelFrame:Show() end
REALG.GameTooltipStatusBar = newFrame("StatusBar", "GameTooltipStatusBar")
REALG.ItemRefTooltip = newFrame("GameTooltip", "ItemRefTooltip")
REALG.ShoppingTooltip1 = newFrame("GameTooltip", "ShoppingTooltip1")
REALG.ShoppingTooltip2 = newFrame("GameTooltip", "ShoppingTooltip2")
REALG.MultiBarBottomRight = newFrame("Frame", "MultiBarBottomRight")
REALG.MultiBarLeft = newFrame("Frame", "MultiBarLeft")
REALG.MultiBarRight = newFrame("Frame", "MultiBarRight")

-- Tracked GameTooltip: FadeOut is a STABLE dispatcher that runs the original
-- body then any table-form post-hooks, exactly like the real engine (which
-- never replaces the method for hooksecurefunc). A DetourHook replacement
-- would swap this reference, which pin (a) detects.
local GT = newFrame("GameTooltip", "GameTooltip")
GT.__shown = true
GT.__fadeCalls = 0
GT.__unit = nil
GT.GetUnit = function() return "n", GT.__unit end
GT.IsUnit = function(_, u) return GT.__unit == u end
GT.GetOwner = function() return nil end
GT.FadeOut = function(self)
    self.__fadeCalls = (self.__fadeCalls or 0) + 1
    local hooks = TABLE_HOOKS["GameTooltip__FadeOut"]
    if (hooks) then
        for _, fn in ipairs(hooks) do fn(self) end
    end
end
REALG.GameTooltip = GT

-- Controllable unit model: only "player" exists unless a test adds more.
local VALID_UNITS = { player = true }
REALG.UnitExists = function(u) return VALID_UNITS[u] == true end
REALG.UnitIsPlayer = function(u) return u == "player" end
REALG.UnitIsUnit = function(a, b) return a == b end
-- The player's guid is shaped like a real one ("Player-1-..."), because the
-- library and gearscore.lua both resolve a unit TOKEN to a guid through
-- their own getPlayerGUID, and that resolver recognises a guid by its
-- "Player-" prefix. With the flat "GUID-player" this harness used before,
-- getPlayerGUID returned nil for the resolved guid and every inventory read
-- came back empty -- so the score was 0 and the overlay pins would have
-- passed on a zero.
REALG.UnitGUID = function(u)
    if (u == "player") then return "Player-1-00000001" end
    return u and ("GUID-" .. u) or nil
end
REALG.UnitLevel = function() return 60 end
REALG.UnitRace = function() return "Human" end
-- UnitClass publishes THREE values on the modern pair (localizedClassName,
-- classToken, classID) and TWO on the Classic family; the mock published two
-- on every client. See Tests/harness/mock_contract.lua for the citations.
REALG.UnitClass = MOCKC.unitClassMock(function() return "Warrior", "WARRIOR" end)
REALG.UnitName = function() return "Test" end
REALG.UnitPower = function() return 0 end
REALG.UnitPowerMax = function() return 100 end
REALG.UnitPowerType = function() return 1 end
REALG.UnitPVPName = function() return "" end
REALG.UnitIsPVP = function() return false end
REALG.UnitFactionGroup = function() return "Alliance" end
REALG.UnitIsConnected = function() return false end
REALG.UnitIsSameServer = function() return true end
REALG.UnitGroupRolesAssigned = function() return "NONE" end
REALG.UnitInParty = function() return false end
REALG.UnitInRaid = function() return false end
REALG.IsInGroup = function() return false end
REALG.IsInRaid = function() return false end
REALG.UnitCanAttack = function() return false end
REALG.CanInspect = function() return false end
REALG.NotifyInspect = function() end
REALG.ClearInspectPlayer = function() end
REALG.GetPlayerInfoByGUID = function() return true, "Warrior" end
-- The player's own equipment. ONE slot is enough: GetScore walks 18 slots
-- and returns the score only when every slot it finds is cached, so a mock
-- with no equipment at all would make every score assertion vacuously true
-- on 0 -- the exact class of false pass this harness exists to catch.
--
-- The item data is CACHED or PENDING, and the pending->ready pin flips it:
-- that IS the transition the character pane has to survive.
local ITEM_LINK = "item:98765"
local ITEM_QUALITY, ITEM_ILVL = 4, 88
local ITEM_LOC = "INVTYPE_CHEST"
local itemDataCached = false
REALG.GetInventoryItemLink = function(_, slot)
    if (slot == 16) then return ITEM_LINK end
    return nil end
REALG.GetItemInfo = function(link)
    if (not itemDataCached) then return nil end
    if (link ~= ITEM_LINK) then return nil end
    -- The client's order: name, link, quality, level, minLevel, type,
    -- subType, stackCount, equipLoc, texture, ... (19 values).
    return "Test Chest", ITEM_LINK, ITEM_QUALITY, ITEM_ILVL, 1, "Armor", "Cloth", 1,
        ITEM_LOC, "icon", 0, 0, 0, 0, 0, 0, 0, 0, 0
end
REALG.C_Item.GetItemInfo = REALG.GetItemInfo
REALG.GetItemInfoInstant = function() return nil end
REALG.GetMouseFoci = function() return nil end
REALG.GetMouseFocus = function() return nil end
REALG.GetCursorPosition = function() return 0, 0 end
REALG.GetScreenWidth = function() return 1920 end
REALG.GetClassAtlas = function() return nil end
REALG.GetGuildInfo = function() return nil end

-- Faithful hooksecurefunc: string form records a post-hook chain without
-- touching the global; table form records without replacing the method.
-- Both THROW on an absent target, like the real one.
REALG.hooksecurefunc = function(a, b, c)
    if (type(a) == "string") then
        local name, fn = a, b
        if (type(rawget(REALG, name)) ~= "function") then
            error("hooksecurefunc: no such global '" .. name .. "'", 2)
        end
        local prev = SECURE_HOOKS[name]
        SECURE_HOOKS[name] = function(...)
            if (prev) then prev(...) end
            return fn(...)
        end
    elseif (type(a) == "table" and type(b) == "string") then
        local t, name, fn = a, b, c
        if (type(t[name]) ~= "function") then
            error("hooksecurefunc: no such method '" .. name .. "'", 2)
        end
        local key = (t.GetName and t:GetName() or tostring(t)) .. "__" .. name
        TABLE_HOOKS[key] = TABLE_HOOKS[key] or {}
        TABLE_HOOKS[key][#TABLE_HOOKS[key] + 1] = fn
    else
        error("hooksecurefunc: bad arguments", 2)
    end
end

REALG.GameTooltip_SetDefaultAnchor = function() end
REALG.TacoTipConfig = {}
REALG.SlashCmdList = {}
-- Secure-menu fixtures for the H-NEW1/M-NEW4 pins. This mock resolves any
-- absent field to a no-op function and leaves __shown unset, which reads as
-- shown -- so the initial hidden state is set explicitly, matching the
-- client (GameMenu and StaticPopups are hidden until opened).
REALG.GameMenuFrame = newFrame("Frame", "GameMenuFrame")
REALG.GameMenuFrame:Hide()
for _spi = 1, 4 do
    REALG["StaticPopup" .. _spi] = newFrame("Frame", "StaticPopup" .. _spi)
    REALG["StaticPopup" .. _spi]:Hide()
end
REALG.StaticPopupDialogs = {}
REALG.StaticPopup_Show = function() end
REALG.UISpecialFrames = {}
REALG.strlower = string.lower
REALG.strfind = string.find
REALG.strrep = string.rep
REALG.strsub = string.sub
REALG.tinsert = table.insert
REALG.tremove = table.remove
REALG.wipe = table.wipe
REALG.GameFontNormal = "GameFontNormal"
REALG.GameFontHighlight = "GameFontHighlight"
REALG.GameFontNormalSmall = "GameFontNormalSmall"
REALG.GameFontHighlightSmall = "GameFontHighlightSmall"
REALG.GameFontDisable = "GameFontDisable"
REALG.GameFontDisableSmall = "GameFontDisableSmall"
REALG.GameFontNormalLarge = "GameFontNormalLarge"
REALG.NumberFontNormal = "NumberFontNormal"
REALG.ChatFontNormal = "ChatFontNormal"
REALG.NORMAL_FONT_COLOR = { r = 1, g = 1, b = 1 }
REALG.GRAY_FONT_COLOR = { r = .5, g = .5, b = .5 }
REALG.HIGHLIGHT_FONT_COLOR = { r = 1, g = .82, b = 0 }
REALG.RAID_CLASS_COLORS = { WARRIOR = { r = 1, g = .8, b = .5 } }
REALG.PowerBarColor = {}
REALG.CONTAINER_OFFSET_X = 0
REALG.CONTAINER_OFFSET_Y = 0
REALG.BackdropTemplateMixin = { SetBackdrop = function() end }
REALG.Mixin = function(object, mixin)
    for k, v in pairs(mixin) do object[k] = v end
end
REALG.Item = nil
REALG.Settings = nil
REALG.InterfaceOptions_AddCategory = function() end
REALG.InterfaceOptionsFrame_OpenToCategory = function() end
REALG.InterfaceOptionsFrame_Show = function() end
REALG.ColorPickerFrame = nil
REALG.LibSharedMedia = nil
REALG.PawnClassicLastUpdatedVersion = 2.0538
REALG.PawnLastUpdatedVersion = 2.1
REALG.PawnGetItemData = function() return {} end
REALG.PawnGetSingleValueFromItem = function() return nil end
REALG.PawnGetScaleColor = function() return 1, 1, 1 end

local order = {
    "Libs/LibStub/LibStub.lua", "Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua",
    "Libs/LibDetours-1.0/LibDetours-1.0.lua", "Libs/LibForeverInspector/LibForeverInspector.lua",
    "Locale/deDE.lua", "Locale/esES.lua", "Locale/esMX.lua", "Locale/frFR.lua",
    "Locale/itIT.lua", "Locale/koKR.lua", "Locale/ptBR.lua", "Locale/ruRU.lua",
    "Locale/zhCN.lua", "Locale/zhTW.lua", "Locale/enUS.lua",
    "gearscore.lua", "pawn.lua", "textures.lua", "options.lua", "main.lua",
}
local loadFail
for _, rel in ipairs(order) do
    local ok, err = pcall(function() assert(loadfile(ROOT .. rel))("TacoTip_Forever") end)
    if (not ok) then loadFail = rel .. " -> " .. tostring(err); break end
end

local checks = {}
local function check(name, cond, detail)
    checks[#checks + 1] = { name, cond and true or false, detail }
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
MOCKC.assertArity(check, "UnitClass", REALG.UnitClass)

if (loadFail) then
    STD.io.write(string.format("%-12s BATCH8 LOAD FAIL %s\n", label or "?", loadFail))
    STD.os.exit(1)
end

local TT = REALG.TacoTip_Forever
check("addon loaded", TT ~= nil and TT.LOAD_OK == true,
    "LOAD_OK=" .. tostring(TT and TT.LOAD_OK) .. " stage=" .. tostring(TT and TT.LOAD_STAGE))

--------------------------------------------------------------------------
-- Drive the real ADDON_LOADED path. It is the only place the overlay's
-- one-shot initialiser runs, and the only place the instant-fade mode is
-- recorded, so both pins have to go through it.
--------------------------------------------------------------------------
local frame = TT.frame
local handler = (frame and frame.GetScript) and frame:GetScript("OnEvent") or nil
check("OnEvent handler present for the ADDON_LOADED drive", type(handler) == "function")
if (type(handler) == "function") then
    pcall(handler, frame, "ADDON_LOADED", "TacoTip_Forever")
end

-- Count the inventory walks.
--
-- The 0.8.2 bug was a refresh that ran EIGHT inventory walks -- about 144
-- GetItemInfo calls -- for ONE pane open. The walk count is therefore the
-- metric this harness has to defend: one pane open, one walk.
local gs = REALG.TT_GS
local walkCount = 0
local realGetScore = gs and gs.GetScore
if (type(realGetScore) == "function") then
    gs.GetScore = function(self, unit, useCallback)
        walkCount = walkCount + 1
        return realGetScore(self, unit, useCallback)
    end
end
check("the GearScore module is loaded and countable", type(realGetScore) == "function")

--------------------------------------------------------------------------
-- H1: the character pane.
--
-- The overlay hangs off CharacterFrame, which carries hidden="true" on every
-- branch, so its OnShow fires exactly once per pane open. PaperDollFrame
-- carries NO hidden attribute, so its OnShow fired before this addon loaded
-- and the hook that used to live there could never fire again.
--------------------------------------------------------------------------
do
    check("the character pane's OnShow hook is installed on CharacterFrame",
        type(rawget(REALG.CharacterFrame, "__hook_OnShow")) == "function",
        "hook=" .. type(rawget(REALG.CharacterFrame, "__hook_OnShow")))
    check("...and NOT on PaperDollFrame, whose OnShow can never fire",
        rawget(REALG.PaperDollFrame, "__hook_OnShow") == nil,
        "hook=" .. type(rawget(REALG.PaperDollFrame, "__hook_OnShow")))
    check("the character overlay's font strings exist after ADDON_LOADED",
        REALG.PersonalGearScore ~= nil and REALG.PersonalAvgItemLvl ~= nil,
        "gs=" .. tostring(REALG.PersonalGearScore) .. " ilvl=" .. tostring(REALG.PersonalAvgItemLvl))

    -- Scenario 1: the player's items are already cached when the pane opens.
    itemDataCached = true
    local walksBefore = walkCount
    REALG.CharacterFrame:Show()
    if (type(rawget(REALG.CharacterFrame, "__hook_OnShow")) == "function") then
        pcall(REALG.CharacterFrame.__hook_OnShow, REALG.CharacterFrame)
    end
    local walks = walkCount - walksBefore
    check("opening the character pane runs EXACTLY ONE inventory walk",
        walks == 1, "walks=" .. tostring(walks))
    local painted = tonumber(REALG.PersonalGearScore and REALG.PersonalGearScore:GetText())
    check("...and the overlay is painted with the CURRENT score",
        painted ~= nil and painted > 0,
        "painted=" .. tostring(REALG.PersonalGearScore and REALG.PersonalGearScore:GetText()))

    -- Scenario 2: the pane opens while the player's items are still loading.
    -- The overlay is initialised with "0" and the pending->ready transition
    -- has to repaint the OPEN pane -- TacoTip_GSCallback used to drop the
    -- player's own guid because the tooltip was showing something else.
    itemDataCached = false
    REALG.CharacterFrame:Hide()
    walksBefore = walkCount
    REALG.CharacterFrame:Show()
    if (type(rawget(REALG.CharacterFrame, "__hook_OnShow")) == "function") then
        pcall(REALG.CharacterFrame.__hook_OnShow, REALG.CharacterFrame)
    end
    check("a pane opened before the items are cached reads 0",
        tonumber(REALG.PersonalGearScore:GetText()) == 0,
        "painted=" .. tostring(REALG.PersonalGearScore:GetText()))
    -- The item data arrives: this is the pending->ready signal.
    itemDataCached = true
    if (type(REALG.TacoTip_GSCallback) == "function") then
        pcall(REALG.TacoTip_GSCallback, REALG.UnitGUID("player"))
    end
    local repainted = tonumber(REALG.PersonalGearScore:GetText())
    check("the pending->ready transition repaints the OPEN pane",
        repainted ~= nil and repainted > 0,
        "repainted=" .. tostring(REALG.PersonalGearScore:GetText()))
    check("...and the repaint took exactly ONE more inventory walk",
        (walkCount - walksBefore) == 2,
        "walks=" .. tostring(walkCount - walksBefore))
    -- A second callback for the same guid must not walk again: the budget is
    -- one pending->ready repaint per pane open.
    local walksAfterReady = walkCount
    if (type(REALG.TacoTip_GSCallback) == "function") then
        pcall(REALG.TacoTip_GSCallback, REALG.UnitGUID("player"))
    end
    check("a second pending->ready callback does NOT walk the inventory again",
        walkCount == walksAfterReady,
        "walks=" .. tostring(walkCount - walksAfterReady))

    -- L-4 (final hunter): a raising character-pane refresh is COUNTED and does
    -- not escape into the engine's item-load callback.
    --
    -- refreshCharacterPaneIfOpen runs inside TacoTip_GSCallback, which is
    -- reached from the engine's item-load callback (itemcacheCB) and is NOT
    -- inside a safeCall. The refresh used to be called UNGUARDED, so a raise
    -- there escaped into the engine's load handler: an error the player sees
    -- attributed to an item load, and a repaint that silently never happened.
    --
    -- The pane is opened again first: the OnShow hook is what sets the
    -- pending->ready budget to 1.
    do
        REALG.CharacterFrame:Show()
        if (type(rawget(REALG.CharacterFrame, "__hook_OnShow")) == "function") then
            pcall(REALG.CharacterFrame.__hook_OnShow, REALG.CharacterFrame)
        end
        local savedRefresh = TT.RefreshCharacterFrame
        TT.RefreshCharacterFrame = function() error("HUNTER_PIN_L4_PANE_REFRESH") end
        local failBefore = (TT.ev and TT.ev.characterPaneRefreshFailed) or 0
        local ok, err = true, nil
        if (type(REALG.TacoTip_GSCallback) == "function") then
            ok, err = pcall(REALG.TacoTip_GSCallback, REALG.UnitGUID("player"))
        end
        TT.RefreshCharacterFrame = savedRefresh
        check("a raising character-pane refresh does not escape into the item-load callback",
            ok, tostring(err))
        check("...and is counted",
            ((TT.ev and TT.ev.characterPaneRefreshFailed) or 0) == failBefore + 1,
            "characterPaneRefreshFailed=" .. tostring((TT.ev and TT.ev.characterPaneRefreshFailed) or 0))
    end
end

--------------------------------------------------------------------------
-- H1: the inspect pane.
--
-- InspectFrame carries hidden="true" on every branch, so its OnShow fires
-- once per inspect open; InspectPaperDollFrame carries no hidden attribute,
-- so the hook that used to live there could never fire.
--------------------------------------------------------------------------
do
    check("the inspect pane's OnShow hook is installed on InspectFrame",
        type(rawget(REALG.InspectFrame, "__hook_OnShow")) == "function",
        "hook=" .. type(rawget(REALG.InspectFrame, "__hook_OnShow")))
    check("...and NOT on InspectPaperDollFrame, whose OnShow can never fire",
        rawget(REALG.InspectPaperDollFrame, "__hook_OnShow") == nil,
        "hook=" .. type(rawget(REALG.InspectPaperDollFrame, "__hook_OnShow")))
    check("the inspect overlay's font strings exist after ADDON_LOADED",
        REALG.InspectGearScore ~= nil and REALG.InspectAvgItemLvl ~= nil,
        "gs=" .. tostring(REALG.InspectGearScore))
    check("the inspect pane keeps its OnHide hook",
        type(rawget(REALG.InspectFrame, "__hook_OnHide")) == "function",
        "hook=" .. type(rawget(REALG.InspectFrame, "__hook_OnHide")))

    REALG.InspectFrame.unit = "target"
    -- The InCombatLockdown guard is load-bearing: the refresh must not run
    -- while the player is in combat.
    REALG.InspectGearScore:SetText(-1)
    local savedLock = REALG.InCombatLockdown
    REALG.InCombatLockdown = function() return true end
    if (type(rawget(REALG.InspectFrame, "__hook_OnShow")) == "function") then
        pcall(REALG.InspectFrame.__hook_OnShow, REALG.InspectFrame)
    end
    check("the inspect refresh does not run while InCombatLockdown() is true",
        REALG.InspectGearScore:GetText() == -1,
        "text=" .. tostring(REALG.InspectGearScore:GetText()))
    REALG.InCombatLockdown = savedLock
    if (type(rawget(REALG.InspectFrame, "__hook_OnShow")) == "function") then
        pcall(REALG.InspectFrame.__hook_OnShow, REALG.InspectFrame)
    end
    check("...and does run once the lock is gone",
        REALG.InspectGearScore:GetText() ~= -1,
        "text=" .. tostring(REALG.InspectGearScore:GetText()))
end

--------------------------------------------------------------------------
-- The two pane OnShow hooks are BOUNDED (final hardening pass).
--
-- A raise inside a HookScript handler does not stay inside this add-on: it
-- unwinds through the CLIENT's own frame script, so the rest of Blizzard's
-- handler for that frame never runs. The character pane and the inspect pane
-- are both opened by the PLAYER, so a raise in either hook leaves a
-- half-drawn pane. Both calls are bounded and counted now.
--------------------------------------------------------------------------
do
    -- The character pane.
    local charHook = rawget(REALG.CharacterFrame, "__hook_OnShow")
    check("the character pane's OnShow hook is still installed",
        type(charHook) == "function",
        "hook=" .. type(charHook))
    local savedCharRefresh = TT.RefreshCharacterFrame
    TT.RefreshCharacterFrame = function() error("HUNTER_PIN_PANE_ONSHOW_RAISE") end
    local charBefore = (TT.ev and TT.ev.characterPaneOnShowFailed) or 0
    local charOK, charErr = true, nil
    if (type(charHook) == "function") then
        charOK, charErr = pcall(charHook, REALG.CharacterFrame)
    end
    TT.RefreshCharacterFrame = savedCharRefresh
    check("a raising character-pane OnShow refresh does not escape into the client",
        charOK, tostring(charErr))
    check("...and is counted",
        ((TT.ev and TT.ev.characterPaneOnShowFailed) or 0) == charBefore + 1,
        "characterPaneOnShowFailed="
            .. tostring((TT.ev and TT.ev.characterPaneOnShowFailed) or 0))
    check("...and the error is named",
        type(TT.ev and TT.ev.lastCharacterPaneOnShowError) == "string"
            and TT.ev.lastCharacterPaneOnShowError:find(
                "HUNTER_PIN_PANE_ONSHOW_RAISE", 1, true) ~= nil,
        "lastCharacterPaneOnShowError="
            .. tostring(TT.ev and TT.ev.lastCharacterPaneOnShowError))
end

do
    -- The inspect pane.
    local inspectHook = rawget(REALG.InspectFrame, "__hook_OnShow")
    check("the inspect pane's OnShow hook is still installed",
        type(inspectHook) == "function",
        "hook=" .. type(inspectHook))
    local savedInspectRefresh = TT.RefreshInspectFrame
    TT.RefreshInspectFrame = function() error("HUNTER_PIN_INSPECT_ONSHOW_RAISE") end
    local inspectBefore = (TT.ev and TT.ev.inspectPaneOnShowFailed) or 0
    local inspectOK, inspectErr = true, nil
    if (type(inspectHook) == "function") then
        inspectOK, inspectErr = pcall(inspectHook, REALG.InspectFrame)
    end
    TT.RefreshInspectFrame = savedInspectRefresh
    check("a raising inspect-pane OnShow refresh does not escape into the client",
        inspectOK, tostring(inspectErr))
    check("...and is counted",
        ((TT.ev and TT.ev.inspectPaneOnShowFailed) or 0) == inspectBefore + 1,
        "inspectPaneOnShowFailed="
            .. tostring((TT.ev and TT.ev.inspectPaneOnShowFailed) or 0))
    check("...and the error is named",
        type(TT.ev and TT.ev.lastInspectPaneOnShowError) == "string"
            and TT.ev.lastInspectPaneOnShowError:find(
                "HUNTER_PIN_INSPECT_ONSHOW_RAISE", 1, true) ~= nil,
        "lastInspectPaneOnShowError="
            .. tostring(TT.ev and TT.ev.lastInspectPaneOnShowError))
end

--------------------------------------------------------------------------
-- N2: the instant-fade mode is printed by /tacotip diag.
--
-- The mode was recorded in TT.InstantFadeMode and printed NOWHERE, so "the
-- toggle does nothing on this client" and "the toggle is off" looked the
-- same to the player.
--------------------------------------------------------------------------
local function diagText()
    local captured = {}
    local savedPrint = REALG.print
    REALG.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
        captured[#captured + 1] = table.concat(parts, " ")
    end
    pcall(TT.PrintDiagnostics, TT)
    REALG.print = savedPrint
    return table.concat(captured, "\n")
end

do
    -- The option is off by default: the client fades normally.
    check("the instant-fade mode is recorded with the option off",
        TT.InstantFadeMode == "standard-fade", "mode=" .. tostring(TT.InstantFadeMode))
    local text = diagText()
    check("/tacotip diag prints the instant-fade line",
        text:find("instant fade", 1, true) ~= nil,
        "diag=" .. text:sub(1, 200))
    check("...and it prints the current mode",
        text:find("standard-fade", 1, true) ~= nil,
        "diag=" .. text:sub(1, 200))
end

local savedFadeOut = GT.FadeOut
do
    -- A client with NO GameTooltip.FadeOut: the mode must say the client
    -- CANNOT do it, not merely that the option is off.
    REALG.TacoTipConfig.instant_fade = true
    -- The raw field has to go as well as the __absent entry: a key that
    -- exists on the table never reaches the metatable's __index at all, so
    -- __absent alone would NOT mask an explicitly-assigned method.
    GT.FadeOut = nil
    GT.__absent = { FadeOut = true }
    if (type(handler) == "function") then
        pcall(handler, frame, "ADDON_LOADED", "TacoTip_Forever")
    end
    check("a client with no GameTooltip.FadeOut records the mode as unsupported",
        TT.InstantFadeMode == "unsupported", "mode=" .. tostring(TT.InstantFadeMode))
    local text = diagText()
    check("...and /tacotip diag prints 'unsupported'",
        text:find("unsupported", 1, true) ~= nil,
        "diag=" .. text:sub(1, 200))
    check("...and the diag reports the API as absent",
        text:find("instant fade API", 1, true) ~= nil,
        "diag=" .. text:sub(1, 200))
end

do
    -- With the API present and the option on, the mode is the secure hook.
    -- (This is the state of every supported client: GameTooltip.FadeOut is
    -- an engine method and Blizzard calls it on all five branches.)
    GT.__absent = nil
    GT.FadeOut = savedFadeOut
    if (type(handler) == "function") then
        pcall(handler, frame, "ADDON_LOADED", "TacoTip_Forever")
    end
    check("with GameTooltip.FadeOut present the mode is the secure hook",
        TT.InstantFadeMode == "secure-hook", "mode=" .. tostring(TT.InstantFadeMode))
    local text = diagText()
    check("...and /tacotip diag prints 'secure-hook'",
        text:find("secure-hook", 1, true) ~= nil,
        "diag=" .. text:sub(1, 200))
    REALG.TacoTipConfig.instant_fade = false
end

local failed = 0
for _, c in ipairs(checks) do
    if (not c[2]) then
        failed = failed + 1
        STD.io.write(string.format("%-12s FAIL %s (%s)\n", label or "?", c[1], tostring(c[3])))
    end
end
if (failed > 0) then
    STD.io.write(string.format("%-12s %d/%d batch8 pane checks failed\n", label or "?", failed, #checks))
    STD.os.exit(1)
end
STD.io.write(string.format("%-12s batch8 pane pins ok (%d checks)\n", label or "?", #checks))
