-- Taint pins for the GameMenu quit-block fix (ADDON_ACTION_FORBIDDEN via
-- tainted GameTooltip).
-- Usage: lua5.1 taint_test.lua <projectId> <iface> <label> [pipeline]
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
        local v = rawget(t, k)
        if (v ~= nil) then return v end
        local absent = rawget(t, "__absent")
        if (absent and absent[k]) then return nil end
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
REALG.C_PlayerInfo = { GUIDIsPlayer = function() return false end }
REALG.C_Map = { GetBestMapForUnit = function() return nil end }
REALG.C_SpecializationInfo = { GetSpecializationInfo = function() return nil end,
    GetInspectSpecialization = function() return nil end,
    GetActiveSpecGroup = function() return 1 end }
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
REALG.UnitGUID = function(u) return u and ("GUID-" .. u) or nil end
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
REALG.GetInventoryItemLink = function() return nil end
REALG.GetItemInfo = function() return nil end
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
    STD.io.write(string.format("%-12s TAINT LOAD FAIL %s\n", label or "?", loadFail))
    STD.os.exit(1)
end

local TT = REALG.TacoTip_Forever
check("addon loaded", TT ~= nil and TT.LOAD_OK == true,
    "LOAD_OK=" .. tostring(TT and TT.LOAD_OK) .. " stage=" .. tostring(TT and TT.LOAD_STAGE))

-- Pin (a): instant_fade on must not replace GameTooltip.FadeOut.
do
    local origFade = GT.FadeOut
    local C = REALG.TacoTipConfig
    if (TT.ApplyConfigDefaults) then pcall(TT.ApplyConfigDefaults, TT, C) end
    C.instant_fade = true
    -- Drive the same ADDON_LOADED path the client takes: the frame created in
    -- main.lua owns the OnEvent handler.
    local frame = TT.frame
    local handler = frame and frame.GetScript and frame:GetScript("OnEvent") or nil
    check("OnEvent handler present for the fade pin", type(handler) == "function")
    if (type(handler) == "function") then
        pcall(handler, frame, "ADDON_LOADED", "TacoTip_Forever")
    end
    local detourFound = false
    if (TT.detours) then
        for k in pairs(TT.detours) do
            if (type(k) == "string" and k:find("FadeOut", 1, true)) then
                detourFound = true
            end
        end
    end
    check("detour absent: TT.detours holds no FadeOut replacement",
        detourFound == false, "detourFound=" .. tostring(detourFound))
    check("original FadeOut identity preserved after instant_fade on",
        GT.FadeOut == origFade, "replaced=" .. tostring(GT.FadeOut ~= origFade))
    -- The secure post-hook still delivers instant hide: FadeOut runs the
    -- original body (fade counter) then hides.
    GT.__shown = true
    GT.__fadeCalls = 0
    pcall(function() GT:FadeOut() end)
    check("secure post-hook keeps instant behaviour (original ran + hidden)",
        GT.__fadeCalls == 1 and GT:IsShown() == false,
        "fadeCalls=" .. tostring(GT.__fadeCalls) .. " shown=" .. tostring(GT:IsShown()))
end

-- Pin (b): anchor hook no-ops on non-unit owners, still works for units.
do
    local anchorHook = SECURE_HOOKS["GameTooltip_SetDefaultAnchor"]
    check("anchor post-hook installed", type(anchorHook) == "function")
    if (type(anchorHook) == "function") then
        local C = REALG.TacoTipConfig
        -- Force a repositioning configuration so a missing guard WOULD mutate.
        C.anchor_mouse = true
        C.anchor_mouse_world = false
        C.custom_pos = nil
        local function resetCounts()
            GT.__setPointCalls = 0
            GT.__clearCalls = 0
            GT.__setOwnerCalls = 0
            GT.__enableMouseCalls = 0
            GT.__points = {}
        end
        -- Menu/popup owner: plain frame, no unit/action/spellId anywhere.
        local menuOwner = newFrame("Frame", "GameMenu")
        GT.__unit = nil
        GT.GetUnit = function() return "n", nil end
        GT.GetOwner = function() return nil end
        resetCounts()
        pcall(anchorHook, GT, menuOwner)
        check("menu owner passes through (no SetOwner)",
            GT.__setOwnerCalls == 0, "setOwner=" .. tostring(GT.__setOwnerCalls))
        check("menu owner passes through (no SetPoint)",
            GT.__setPointCalls == 0, "setPoint=" .. tostring(GT.__setPointCalls))
        check("menu owner passes through (no ClearAllPoints)",
            GT.__clearCalls == 0, "clear=" .. tostring(GT.__clearCalls))
        check("menu owner passes through (no EnableMouse)",
            GT.__enableMouseCalls == 0, "enableMouse=" .. tostring(GT.__enableMouseCalls))
        -- Unit owner: the same configuration MUST still reposition.
        GT.__unit = "player"
        GT.GetUnit = function() return "n", "player" end
        resetCounts()
        pcall(anchorHook, GT, REALG.UIParent)
        check("unit owner still repositions (SetPoint ran)",
            GT.__setPointCalls >= 1, "setPoint=" .. tostring(GT.__setPointCalls))
    end
end

-- Pin (g): THE CONTAINMENT. Every addon callback this add-on installs into a
-- BLIZZARD frame's script chain runs inside `securecall`, so the client does
-- not taint that frame. Uncontained, the taint reaches the game menu and the
-- Logout/Quit button -- whose callback is the engine function, so a reporter
-- can only name it 'UNKNOWN()' -- is refused:
--     [ADDON_ACTION_FORBIDDEN] AddOn 'TacoTip' tried to call the protected
--     function 'UNKNOWN()'.
--
-- `securecall` is the engine's own containment primitive, and Blizzard uses it
-- for exactly this shape (Blizzard_BuffFrame/BuffFrame.lua:991
-- `securecall(self.UpdateDuration, self, self.timeLeft); -- Taint issue with
-- SecondsToTimeAbbrev`). It is an engine global on every supported client
-- (Blizzard captures it as a local: Blizzard_FrameXML/SharedPetBattleTemplates.lua:5
-- `local securecall = securecall;`).
--
-- Revert map: unwrap any one of these handlers from runUntainted -> the
-- counter does not move for that handler (red).
do
    local function secureCalls()
        return REALG.__secureCalls or 0
    end
    local showHook = GT.__hook_OnShow
    local hideHook = GT.__hook_OnHide
    check("containment: the shared GameTooltip's OnShow hook is installed",
        type(showHook) == "function")
    check("containment: the shared GameTooltip's OnHide hook is installed",
        type(hideHook) == "function")
    if (type(showHook) == "function") then
        local before = secureCalls()
        pcall(showHook, GT)
        check("containment: the GameTooltip's OnShow hook runs inside securecall",
            secureCalls() > before,
            "secureCalls=" .. tostring(secureCalls() - before))
    end
    if (type(hideHook) == "function") then
        local before = secureCalls()
        pcall(hideHook, GT)
        check("containment: the GameTooltip's OnHide hook runs inside securecall",
            secureCalls() > before,
            "secureCalls=" .. tostring(secureCalls() - before))
    end
    local anchorHook = SECURE_HOOKS["GameTooltip_SetDefaultAnchor"]
    check("containment: the anchor post-hook is installed",
        type(anchorHook) == "function")
    if (type(anchorHook) == "function") then
        local before = secureCalls()
        pcall(anchorHook, GT, REALG.UIParent)
        check("containment: the anchor post-hook body runs inside securecall",
            secureCalls() > before,
            "secureCalls=" .. tostring(secureCalls() - before))
    end
    -- The tooltip's STATUS BAR is a live global on every client: the classic
    -- chain declares it as `<StatusBar name="$parentStatusBar" .../>` inside
    -- GameTooltipTemplate (classic_era:Blizzard_SharedXML/Classic/GameTooltipTemplate.xml:138)
    -- and the modern one the same way (forever/live:Blizzard_GameTooltip/Mainline/GameTooltip.xml:9).
    -- The `$parent` prefix makes the child's global the parent's name plus the
    -- child's -- the same rule the add-on relies on for `$parentTextLeft1` ->
    -- `GameTooltipTextLeft1`. So this hook is always on, and it is addon code
    -- inside a Blizzard frame's script chain.
    local statusBar = REALG.GameTooltipStatusBar
    check("containment: the tooltip status bar exists (it is a live global)",
        type(statusBar) == "table")
    local statusHook = statusBar and statusBar.__hook_OnHide
    check("containment: the status bar's OnHide hook is installed",
        type(statusHook) == "function")
    if (type(statusHook) == "function") then
        local before = secureCalls()
        pcall(statusHook, statusBar)
        check("containment: the status bar's OnHide hook runs inside securecall",
            secureCalls() > before,
            "secureCalls=" .. tostring(secureCalls() - before))
    end
end

-- Pin (c): mover ticker + OnShow/OnHide hooks + ShowExample skip while a
-- secure menu owns the screen (hunter H-NEW1). Revert map: delete the
-- isSecureMenuBusy() early-returns in onMoverTick,
-- onMoverGameTooltipShow/Hide and ShowExample -> every menu-shown fire below
-- mutates (red). The StaticPopup5 leg pins the M-NEW4 loop bound: the pool
-- is exactly 1..4, so a fifth dialog must NOT suppress.
do
    -- Isolate the mover/taint behaviour from the options UI: Refresh walks
    -- dropdown and colour-picker globals this mock never declares, so the
    -- enable path raises here while it cannot in game. Restored below.
    local realRefresh = TT.RefreshOptionsUI
    TT.RefreshOptionsUI = function() end
    local restored = false
    local function restoreRefresh()
        if (not restored) then
            restored = true
            TT.RefreshOptionsUI = realRefresh
        end
    end
    local mover = nil
    local tickFn = nil
    check("mover entry point present", type(REALG.TacoTip_CustomPosEnable) == "function")
    if (type(REALG.TacoTip_CustomPosEnable) == "function") then
        local okEnable = pcall(REALG.TacoTip_CustomPosEnable, true)
        check("mover enable does not raise", okEnable == true)
        mover = REALG.TacoTipDragButton
        check("mover button exists after enable", mover ~= nil)
        if (mover ~= nil) then
            check("mover is shown after enable(true)", mover:IsShown() == true)
            local onShowFn = mover.GetScript and mover:GetScript("OnShow") or nil
            check("mover OnShow script installed", type(onShowFn) == "function")
            if (type(onShowFn) == "function") then
                -- Mock accommodation: this mock resolves ANY absent field to a
                -- no-op function, so the fresh button reads self.ticker as a
                -- (truthy) function and self.ticker:Cancel() indexes it. In
                -- game the field starts nil and the branch is skipped. Seed a
                -- cancellable ticker, the legitimate "previous ticker" state.
                mover.ticker = { Cancel = function() end }
                local okShow = pcall(onShowFn, mover)
                check("mover OnShow does not raise", okShow == true)
            end
            -- rawget: the mock __index fabricates functions for absent keys,
            -- so a plain read can never observe "no ticker".
            local rawTicker = rawget(mover, "ticker")
            tickFn = (type(rawTicker) == "table" and rawTicker.func) or nil
            check("mover ticker captured", type(tickFn) == "function")
        end
    end
    if (mover ~= nil and type(tickFn) == "function") then
        local function resetMoverCounts()
            GT.__setPointCalls = 0
            GT.__clearCalls = 0
            GT.__setOwnerCalls = 0
            GT.__enableMouseCalls = 0
        end
        local function fireMover()
            pcall(tickFn)
            local hookShow = GT.__hook_OnShow
            if (type(hookShow) == "function") then pcall(hookShow, GT) end
            local hookHide = GT.__hook_OnHide
            if (type(hookHide) == "function") then pcall(hookHide, GT) end
        end
        -- Control: secure screen clear -> the example renders via the
        -- custom_pos _Enable installs (the SetOwner branch).
        resetMoverCounts()
        fireMover()
        check("control: mover fire with no menu renders (SetOwner ran)",
            GT.__setOwnerCalls >= 1, "setOwner=" .. tostring(GT.__setOwnerCalls))
        -- Menu shown: ticker + both hooks must all no-op.
        REALG.GameMenuFrame:Show()
        resetMoverCounts()
        fireMover()
        check("menu shown: ticker+hooks cause no SetOwner",
            GT.__setOwnerCalls == 0, "setOwner=" .. tostring(GT.__setOwnerCalls))
        check("menu shown: ticker+hooks cause no SetPoint",
            GT.__setPointCalls == 0, "setPoint=" .. tostring(GT.__setPointCalls))
        -- Defense in depth: ShowExample itself refuses too.
        resetMoverCounts()
        pcall(function() mover:ShowExample() end)
        check("menu shown: direct ShowExample causes no SetOwner",
            GT.__setOwnerCalls == 0, "setOwner=" .. tostring(GT.__setOwnerCalls))
        check("menu shown: direct ShowExample causes no SetPoint",
            GT.__setPointCalls == 0, "setPoint=" .. tostring(GT.__setPointCalls))
        REALG.GameMenuFrame:Hide()
        -- Popup leg: a shown StaticPopup1 suppresses as well.
        REALG.StaticPopup1:Show()
        resetMoverCounts()
        pcall(function() mover:ShowExample() end)
        check("popup shown: ShowExample causes no SetOwner",
            GT.__setOwnerCalls == 0, "setOwner=" .. tostring(GT.__setOwnerCalls))
        REALG.StaticPopup1:Hide()
        -- M-NEW4 loop bound: a fifth dialog is outside the 1..4 pool and
        -- must NOT suppress.
        REALG.StaticPopup5 = newFrame("Frame", "StaticPopup5")
        REALG.StaticPopup5:Show()
        resetMoverCounts()
        pcall(function() mover:ShowExample() end)
        check("StaticPopup5 shown: ShowExample still renders (pool is 1..4)",
            GT.__setOwnerCalls >= 1, "setOwner=" .. tostring(GT.__setOwnerCalls))
        REALG.StaticPopup5 = nil
        -- Restore: menu clear renders again.
        resetMoverCounts()
        pcall(function() mover:ShowExample() end)
        check("menu clear: ShowExample renders again",
            GT.__setOwnerCalls >= 1, "setOwner=" .. tostring(GT.__setOwnerCalls))
        pcall(REALG.TacoTip_CustomPosEnable, false)
    end
    restoreRefresh()
end

-- Pin (d): the anchor spell branch tolerates a parent without GetParent
-- (hunter H-NEW4). Revert map: restore the raw
-- `parent and parent:GetParent()` call -> the pcall below returns false
-- (red) instead of passing through to the unit gate.
do
    local anchorHook = SECURE_HOOKS["GameTooltip_SetDefaultAnchor"]
    check("anchor post-hook installed (spell-branch pin)", type(anchorHook) == "function")
    if (type(anchorHook) == "function") then
        local C = REALG.TacoTipConfig
        C.anchor_mouse = true
        C.anchor_mouse_world = false
        C.anchor_mouse_spells = true
        C.custom_pos = nil
        GT.__setPointCalls = 0
        GT.__clearCalls = 0
        GT.__setOwnerCalls = 0
        GT.__enableMouseCalls = 0
        GT.__unit = nil
        GT.GetUnit = function() return "n", nil end
        GT.GetOwner = function() return nil end
        -- A parent with neither action/spellId nor GetParent: no spell leg,
        -- no raise, straight to the unit gate (menu passthrough).
        local okHook = pcall(anchorHook, GT, {})
        check("parent without GetParent does not raise",
            okHook == true, "ok=" .. tostring(okHook))
        check("...and passes through without SetOwner",
            GT.__setOwnerCalls == 0, "setOwner=" .. tostring(GT.__setOwnerCalls))
        check("...and without SetPoint",
            GT.__setPointCalls == 0, "setPoint=" .. tostring(GT.__setPointCalls))
        -- A parent whose GetParent raises is the same shape, not a new one.
        local raisingParent = {
            GetParent = function() error("HNEW4_PIN_RAISING_PARENT") end,
        }
        GT.__setOwnerCalls = 0
        GT.__setPointCalls = 0
        local okRaise = pcall(anchorHook, GT, raisingParent)
        check("parent with raising GetParent does not raise",
            okRaise == true, "ok=" .. tostring(okRaise))
        check("...and passes through without SetOwner",
            GT.__setOwnerCalls == 0, "setOwner=" .. tostring(GT.__setOwnerCalls))
        C.anchor_mouse_spells = nil
    end
end

-- Pin (e): the anchor unit gate splits silent passthroughs for diag (hunter
-- M-NEW2) -- menu-by-design vs unit-like-but-unresolved. Revert map: delete
-- the TT.ev.anchorSkippedMenu/Unresolved increments in
-- onGameTooltipSetDefaultAnchor -> the counters below never move (red).
do
    local anchorHook = SECURE_HOOKS["GameTooltip_SetDefaultAnchor"]
    check("anchor post-hook installed (skip-split pin)", type(anchorHook) == "function")
    if (type(anchorHook) == "function") then
        local C = REALG.TacoTipConfig
        C.anchor_mouse = true
        C.anchor_mouse_world = false
        C.anchor_mouse_spells = nil
        C.custom_pos = nil
        GT.__unit = nil
        GT.GetUnit = function() return "n", nil end
        GT.GetOwner = function() return nil end
        local TT2 = REALG.TacoTip_Forever
        local function skips()
            local ev = TT2 and TT2.ev or {}
            return ev.anchorSkippedMenu or 0, ev.anchorSkippedUnresolved or 0
        end
        -- No unit signal anywhere: menu-by-design passthrough.
        local menuBefore, unresBefore = skips()
        local menuOwner = newFrame("Frame", "SkipMenuOwner")
        pcall(anchorHook, GT, menuOwner)
        local menuAfter, unresAfter = skips()
        check("menu-surface passthrough counts as menu-skipped",
            menuAfter == menuBefore + 1, "menu=" .. menuBefore .. "->" .. menuAfter)
        check("...and not as unresolved",
            unresAfter == unresBefore, "unresolved=" .. unresBefore .. "->" .. unresAfter)
        -- A unit signal that resolves nowhere (no such unit in this mock):
        -- the exotic/battle-pet shape, counted as unresolved.
        local exoticParent = { unit = "some-unresolvable-token" }
        pcall(anchorHook, GT, exoticParent)
        local menuFinal, unresFinal = skips()
        check("unresolvable-unit passthrough counts as unresolved",
            unresFinal == unresAfter + 1, "unresolved=" .. unresAfter .. "->" .. unresFinal)
        check("...and not as menu",
            menuFinal == menuAfter, "menu=" .. menuAfter .. "->" .. menuFinal)
    end
end

-- Pin (f): the CLASSIC ERA unit tooltip. On the classic family the tooltip has
-- no GetUnit, no TooltipDataProcessor and no owner.unit -- Blizzard identifies
-- it with IsUnit (origin/classic_era
-- Interface/AddOns/Blizzard_GameTooltip/Classic/GameTooltip.lua:498-503). The
-- gate that 0.8.4 added read such a tooltip as "menu" and skipped it, so the
-- saved custom position was never applied and the tooltip stayed in the
-- bottom-right corner while the mover could not save it back.
-- Revert map: drop the IsUnit probe from isManagedAnchorTarget -> the hook
-- returns early and the setPoint count stays at 0 (red).
do
    local anchorHook = SECURE_HOOKS["GameTooltip_SetDefaultAnchor"]
    if (type(anchorHook) == "function") then
        local C = REALG.TacoTipConfig
        C.anchor_mouse = true
        C.anchor_mouse_world = false
        C.anchor_mouse_spells = nil
        C.custom_pos = nil
        -- The classic shape: the tooltip IS the mouseover tooltip, but the
        -- unit cannot be read through the modern APIs.
        GT.__unit = "mouseover"
        GT.GetUnit = function() return "n", "mouseover" end
        GT.GetOwner = function() return nil end
        local classicParent = newFrame("Frame", "ClassicEraOwner")
        GT.__setPointCalls = 0
        pcall(anchorHook, GT, classicParent)
        check("a classic-era unit tooltip is still repositioned (the saved position applies)",
            GT.__setPointCalls >= 1, "setPoint=" .. tostring(GT.__setPointCalls))
    end
end

local failed = 0
for _, c in ipairs(checks) do
    if (not c[2]) then
        failed = failed + 1
        STD.io.write(string.format("%-12s FAIL %s (%s)\n", label or "?", c[1], tostring(c[3])))
    end
end
if (failed > 0) then
    STD.io.write(string.format("%-12s %d/%d taint checks failed\n", label or "?", failed, #checks))
    STD.os.exit(1)
end
STD.io.write(string.format("%-12s taint pins ok (%d checks)\n", label or "?", #checks))
