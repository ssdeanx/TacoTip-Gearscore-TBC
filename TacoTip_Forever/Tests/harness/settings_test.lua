-- Verifies that every setting is reachable, correctly bound, persistent, and
-- resettable, and that the options frame registers through the right API for
-- the client it is running on.
--
-- The core idea: do not hardcode a control-to-key mapping. Drive every control
-- the addon actually created, diff TacoTipConfig before and after, and check
-- that the set of keys the controls can reach is exactly the set of settings
-- GetDefaults() declares. That catches a typo'd key, a control wired to nothing,
-- and a setting nobody can reach, without anyone maintaining a mapping table.
--
-- Usage: lua5.1 settings_test.lua <projectId> <iface> <label> [pipeline] [nosettings]

local ROOT = (os.getenv("TACOTIP_TEST_ROOT") or ".") .. "/"

local projectId, iface, label = tonumber(arg[1]), tonumber(arg[2]), arg[3]
local usePipeline  = (arg[4] == "pipeline")
local noSettings   = (arg[5] == "nosettings")
local WITH_PAWN   = (arg[6] == "pawn")
local DEBUG       = (arg[7] == "debug")

local REALG = _G
local STD = { os=os, string=string, pairs=pairs, ipairs=ipairs, type=type, pcall=pcall,
    tonumber=tonumber, tostring=tostring, select=select, rawget=rawget, rawset=rawset,
    setmetatable=setmetatable, getmetatable=getmetatable, unpack=unpack, assert=assert,
    error=error, math=math, table=table, loadfile=loadfile, print=print, io=io,
    -- WoW's Lua provides an xpcall that accepts the arguments after the handler,
    -- and main.lua's safeCall depends on that form. The handler MUST receive the
    -- error: a mock that swallows it makes every assertion here meaningless.
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
        return true
    end }

local checks = {}
local function check(name, cond, detail)
    checks[#checks + 1] = { name, cond and true or false, detail }
end

--------------------------------------------------------------------------
-- Mock widget: same method policy as options_test.lua (unknown field == nil)
--------------------------------------------------------------------------
local WIDGET_METHODS = {}
for _, m in ipairs({
    "AddLine","AddDoubleLine","ClearLines","ClearAllPoints","ClearPadding",
    "CreateFontString","CreateTexture","CreateAnimation","Enable","Disable",
    "EnableMouse","EnableMouseWheel","GetAlpha","GetBottom","GetCenter",
    "GetChecked","GetClassAtlas","GetEffectiveScale","GetFrameLevel",
    "GetFrameStrata","GetHeight","GetItem","GetLeft","GetLeftLine","GetMinimumWidth",
    "GetName","GetNumLines","GetObjectType","GetParent","GetRight","GetRightLine",
    "GetScrollChild","GetSize","GetStringHeight","GetText","GetUnit","GetVerticalScroll",
    "GetVerticalScrollRange","GetWidth","Hide","HookScript","IsEnabled","IsObjectType",
    "IsShown","IsUnit","NumLines","RegisterEvent","RegisterForClicks","RegisterForDrag",
    "SetAlpha","SetAutoFocus","SetBackdrop","SetBackdropBorderColor","SetBackdropColor",
    "SetChecked","SetClampedToScreen","SetClampRectInsets","SetColor","SetColorRGB",
    "SetColorTexture","SetDesaturated","SetDisabled","SetDrawLayer","SetEnabled",
    "SetFocus","SetFont","SetFontObject","SetFrameLevel","SetFrameStrata","SetHeight",
    "SetHitRectInsets","SetJustifyH","SetJustifyV","SetMaxLetters","SetMinMaxValues",
    "SetMinimumWidth","SetMovable","SetNonSpaceWrap","SetNormalTexture","SetObeyStepOnDrag",
    "SetOwner","SetPadding","SetParent","SetPoint","SetPortraitTexture","SetPortraitZoom",
    "SetScrollChild","SetScript","SetShadowColor","SetShadowOffset","SetShown","SetSize",
    "SetTextColor","GetTextColor","SetFormattedText","SetTextHeight","GetStringWidth",
    "SetWordWrap","SetStatusBarColor","SetStatusBarTexture","SetTexCoord","SetText",
    "SetTexture","SetUnit","SetUserPlaced","SetValue","SetValueStep","SetVerticalScroll",
    "SetWidth","Show","StartMoving","StopMovingOrSizing","UnregisterEvent",
    "UpdateScrollChildRect","UpdateTooltip","FadeOut","GetAnchorType","IsEquippedItem",
    "IsOwned","GetOwner","GetSpell","SetItem","SetPlayer","ClearModel","Refresh",
    "GetDefaultAnchor","GetMinMaxValues","GetValue","GetValueStep","GetScale",
    "RegisterUnitEvent","GetNumPoints","GetNumChildren","GetChildren",
    "SetToplevel","SetID","GetID","IsForbidden","SetPassThroughButtons","GetNumChildren",
}) do WIDGET_METHODS[m] = true end

-- Named widgets, in creation order. The addon names every options control via
-- nextModernWidgetName(), so this is the control surface we can drive.
local named = {}
local widgets = {}
local widgetSeq = 0
local makeWidget

makeWidget = function(kind, name, parent, template, depth)
    depth = depth or 0
    widgetSeq = widgetSeq + 1
    local w = { __kind = kind, __name = name, __parent = parent, __id = widgetSeq }
    w.__scripts, w.__hooks, w.__events, w.__points = {}, {}, {}, {}
    w.__shown, w.__checked, w.__value, w.__text = true, nil, nil, nil
    w.__min, w.__max, w.__step = nil, nil, nil
    w.__enabled = true

    local MT = {}
    MT.__index = function(_, k)
        local f = rawget(w, k)
        if (f) then return f end
        if (WIDGET_METHODS[k]) then return function() return nil end end
        return nil
    end

    w.GetName = function() return name end
    w.GetParent = function() return parent end
    w.GetObjectType = function() return kind end
    w.SetScript = function(_, s, fn) w.__scripts[s] = fn end
    w.GetScript = function(_, s) return w.__scripts[s] end
    w.HookScript = function(_, s, fn) w.__hooks[s] = fn end
    w.RegisterEvent = function(_, e) w.__events[#w.__events + 1] = e end
    w.UnregisterEvent = function() end
    w.Show = function() w.__shown = true end
    w.Hide = function() w.__shown = false end
    w.IsShown = function() return w.__shown end
    w.SetShown = function(_, v) w.__shown = v and true or false end
    w.SetPoint = function() end
    w.ClearAllPoints = function() end
    w.SetAllPoints = function() end
    w.SetSize = function(_, a, b) w.__w, w.__h = a, b end
    w.SetWidth = function(_, a) w.__w = a end
    w.SetHeight = function(_, a) w.__h = a end
    w.GetWidth = function() return w.__w or 0 end
    w.GetHeight = function() return w.__h or 0 end
    w.GetSize = function() return w.__w or 0, w.__h or 0 end
    w.GetCenter = function() return 0, 0 end
    w.GetLeft = function() return 0 end
    w.GetRight = function() return 0 end
    w.GetFrameLevel = function() return 1 end
    w.GetFrameStrata = function() return "MEDIUM" end
    w.SetFrameLevel = function() end
    w.SetFrameStrata = function() end
    w.SetAlpha = function() end
    w.GetAlpha = function() return 1 end
    w.SetBackdrop = function() end
    w.SetBackdropColor = function() end
    w.SetBackdropBorderColor = function() end
    w.GetBackdropBorderColor = function() return 1, 1, 1, 1 end
    w.SetClampedToScreen = function() end
    w.SetClampRectInsets = function() end
    w.SetHitRectInsets = function() end
    w.EnableMouse = function() end
    w.EnableMouseWheel = function() end
    w.SetMovable = function() end
    w.SetUserPlaced = function() end
    w.RegisterForClicks = function() end
    w.RegisterForDrag = function() end
    w.SetNormalTexture = function() end
    w.SetText = function(_, t) w.__text = t end
    w.GetText = function() return w.__text end
    w.SetFontObject = function() end
    w.GetFontObject = function() return "GameFontNormal" end
    w.SetFont = function() end
    w.SetJustifyH = function() end
    w.SetJustifyV = function() end
    w.SetWordWrap = function() end
    w.SetNonSpaceWrap = function() end
    w.SetMaxLetters = function() end
    w.SetShadowOffset = function() end
    w.SetShadowColor = function() end
    w.SetTextColor = function() end
    w.SetVertexColor = function() end
    w.SetTexture = function(_, t) w.__texture = t end
    w.GetTexture = function() return w.__texture or 1 end
    w.SetColorTexture = function(_, r, g, b, a) w.__color = { r, g, b, a } end
    w.SetTexCoord = function() end
    w.SetDesaturated = function() end
    w.SetDrawLayer = function() end
    w.SetStatusBarTexture = function() end
    w.SetStatusBarColor = function() end
    w.GetStringHeight = function() return 12 end
    w.GetEffectiveScale = function() return 1 end
    w.GetValueStep = function() return 1 end
    w.GetScale = function() return 1 end
    w.GetNumPoints = function() return #(w.__points or {}) end
    w.GetMinMaxValues = function() return w.__min or 0, w.__max or 0 end
    w.SetMinMaxValues = function(_, a, b) w.__min, w.__max = a, b end
    w.GetMinMaxValues = function() return w.__min or 0, w.__max or 0 end
    w.SetValueStep = function(_, v) w.__step = v end
    w.GetValueStep = function() return w.__step or 1 end
    w.SetValue = function(_, v) w.__value = v end
    w.GetValue = function() return w.__value or 0 end
    w.SetValueSilently = function(_, v) w.__value = v end
    w.SetObeyStepOnDrag = function() end
    w.SetChecked = function(_, v)
        w.__checked = v and true or false
    end
    w.GetChecked = function() return w.__checked end
    w.SetEnabled = function(_, v) w.__enabled = v ~= false end
    w.SetDisabled = function(_, v) w.__enabled = not v end
    w.Enable = function() w.__enabled = true end
    w.Disable = function() w.__enabled = false end
    w.IsEnabled = function() return w.__enabled ~= false end
    w.SetAutoFocus = function() end
    w.ClearFocus = function() end
    w.SetFocus = function() end
    w.SetScrollChild = function(_, c) w.__scrollChild = c end
    w.GetScrollChild = function() return w.__scrollChild end
    w.SetVerticalScroll = function() end
    w.GetVerticalScroll = function() return 0 end
    w.GetVerticalScrollRange = function() return 100 end
    w.UpdateScrollChildRect = function() end
    w.SetPortraitTexture = function(_, t) w.__portrait = t end
    w.SetPortraitZoom = function() end
    w.SetModelScale = function() end
    w.SetCamera = function() end
    w.SetPosition = function() end
    w.SetFacing = function() end
    w.SetUnit = function(_, u) w.__unit = u end
    w.ClearModel = function() end
    w.Refresh = function() end
    w.FadeOut = function() end
    w.UpdateTooltip = function() end
    w.SetOwner = function() end
    w.SetClampRectInsets = function() end
    w.GetAnchorType = function() return 1 end
    w.IsUnit = function(_, u) return w.__unit == u end
    w.GetNumChildren = function() return 0 end
    w.GetChildren = function() return nil end
    w.IsForbidden = function() return false end
    w.SetPassThroughButtons = function() end
    w.SetToplevel = function() end
    w.SetID = function(_, v) w.__id = v end
    w.GetID = function() return w.__id end
    w.GetDefaultAnchor = function() return 1 end
    w.GetItem = function() return "n", "item:1" end
    w.GetSpell = function() return "n", 1 end
    w.GetMinMaxValues = function() return w.__min or 0, w.__max or 0 end
    w.GetValue = function() return w.__value or 0 end
    w.SetValueSilently = function(_, v) w.__value = v end
    w.ClearLines = function() w.__lines = {} end
    w.NumLines = function() return #(w.__lines or {}) end
    w.GetNumLines = function() return #(w.__lines or {}) end
    w.AddLine = function(_, t)
        w.__lines = w.__lines or {}
        w.__lines[#w.__lines + 1] = { left = t }
    end
    w.AddDoubleLine = function(_, l, r)
        w.__lines = w.__lines or {}
        w.__lines[#w.__lines + 1] = { left = l, right = r }
    end
    w.GetLeftLine = function() return nil end
    w.GetRightLine = function() return nil end

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

    if (name and depth < 1) then
        for _, sfx in ipairs({ "Text", "Low", "High" }) do
            if (not rawget(REALG, name .. sfx)) then
                rawset(REALG, name .. sfx, makeWidget("FontString", name .. sfx, w, nil, depth + 1))
            end
        end
    end

    local t = setmetatable(w, MT)
    -- Record EVERY widget, not just named ones. createOptionsButton is the one
    -- builder that does not default a global name (matching the Classic
    -- reference), so the nameless ones -- including "Reset configuration" -- are
    -- invisible to a named-only sweep.
    widgets[#widgets + 1] = t
    if (name) then named[#named + 1] = t end
    return t
end

--------------------------------------------------------------------------
-- Environment
--------------------------------------------------------------------------
for k in STD.pairs(REALG) do REALG[k] = nil end
for k, v in STD.pairs(STD) do REALG[k] = v end
REALG._G = REALG
REALG.time = STD.os.time
REALG.print = function() end
ERRORS = {}
REALG.geterrorhandler = function() return function(e) ERRORS[#ERRORS + 1] = tostring(e) end end
-- A named frame becomes a real global in WoW (CreateFrame("Frame", "TacoTipOptions")
-- defines _G.TacoTipOptions). The mock must do the same, or code that reads a
-- well-known frame by name sees nil and a whole class of bug is masked -- the
-- same failure that hid the missing talent-icon lookup.
    -- Frame types CreateFrame actually accepts. "Texture" and "FontString" are
    -- WIDGET types created with frame:CreateTexture() / :CreateFontString(); they
    -- are rejected by the real CreateFrame with
    --   CreateFrame: Unknown frame type 'Texture'
    -- A mock that accepts any string cannot catch that class of bug at all.
    local VALID_FRAME_TYPES = {
        Frame = true, Button = true, CheckButton = true, EditBox = true,
        ScrollFrame = true, Slider = true, StatusBar = true, GameTooltip = true,
        PlayerModel = true, NumberEditBox = true, SelectionGroup = true,
        ColorPicker = true, MessageFrame = true, Model = true, Movie = true,
        OffScreenFrame = true, SideDock = true, ArenaSpectatorFrame = true,
    }
REALG._VALID_FRAME_TYPES = VALID_FRAME_TYPES
REALG.CreateFrame = function(kind, name, parent, template)
    if (type(kind) ~= 'string' or not VALID_FRAME_TYPES[kind]) then
        error("CreateFrame: Unknown frame type '" .. tostring(kind) .. "'", 2)
    end
    local f = makeWidget(kind or "Frame", name, parent, template)
    if (name and not rawget(REALG, name)) then rawset(REALG, name, f) end
    return f
end
REALG.GetLocale = function() return "enUS" end
REALG.GetCVar = function() return "" end
REALG.SetCVar = function() end
REALG.GetCVarBool = function() return false end
REALG.InCombatLockdown = function() return false end
REALG.LoadAddOn = function() return true end
REALG.hooksecurefunc = function() end
REALG.tinsert = table.insert
REALG.tremove = table.remove
REALG.strlower = string.lower
REALG.strfind = string.find
REALG.strrep = string.rep
REALG.strsub = string.sub
REALG.wipe = table.wipe
local baseTable = table
local baseNext = next
STD.table = setmetatable({
    wipe = baseTable.wipe or function(tb)
        for k in baseNext, tb do tb[k] = nil end
        return tb
    end,
}, { __index = baseTable })
REALG.SlashCmdList = {}
REALG.StaticPopupDialogs = {}
REALG.StaticPopup_Show = function() end
REALG.UISpecialFrames = {}
REALG.TacoTipConfig = {}
REALG.GetBuildInfo = function() return "1.15.9", "1", "d", iface, "us", "rel" end
REALG.WOW_PROJECT_MAINLINE = 1
REALG.WOW_PROJECT_CLASSIC = 2
REALG.WOW_PROJECT_BC_CLASSIC = 5
REALG.WOW_PROJECT_WRATH_CLASSIC = 11
REALG.WOW_PROJECT_CATACLYSM_CLASSIC = 14
REALG.WOW_PROJECT_MISTS_CLASSIC = 19
REALG.WOW_PROJECT_ID = projectId
REALG.C_AddOns = { GetAddOnMetadata = function(_, k)
    if k == "Version" then return "0.7.8" end
    if k == "Title" then return "TacoTip Forever" end end,
    IsAddOnLoaded = function() return false end }
for _, f in ipairs({ "GameFontNormal", "GameFontHighlight", "GameFontNormalSmall",
    "GameFontHighlightSmall", "GameFontDisable", "GameFontDisableSmall",
    "GameFontNormalLarge", "NumberFontNormal", "ChatFontNormal" }) do REALG[f] = f end
REALG.NORMAL_FONT_COLOR = { r = 1, g = 1, b = 1 }
REALG.GRAY_FONT_COLOR = { r = .5, g = .5, b = .5 }
REALG.HIGHLIGHT_FONT_COLOR = { r = 1, g = .82, b = 0 }
REALG.LIGHTNING_BOLT_FONT_COLOR = { r = 1, g = .82, b = 0 }
REALG.RAID_CLASS_COLORS = { WARRIOR = { r = 1, g = .8, b = .5 } }
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
REALG.CharacterModelFrame = makeWidget("PlayerModel", "CharacterModelFrame")

-- CharacterModelFrame is a CLASSIC-ONLY frame: the Classic family nests a
-- PlayerModel by that name inside PaperDollFrame, and Retail removed it (no
-- definition anywhere in the live FrameXML) while keeping PaperDollFrame. The
-- mock used to invent it on every client, which is how an unguarded
-- index of a frame Retail does not have shipped: "attempt to index global
-- 'CharacterModelFrame' (a nil value)" on every options refresh.
if (usePipeline) then
    REALG.CharacterModelFrame = nil
end
REALG.GameTooltip = makeWidget("GameTooltip", "GameTooltip")
REALG.GameTooltipStatusBar = makeWidget("StatusBar", "GameTooltipStatusBar")
REALG.ItemRefTooltip = makeWidget("GameTooltip", "ItemRefTooltip")
REALG.ShoppingTooltip1 = makeWidget("GameTooltip", "ShoppingTooltip1")
REALG.ShoppingTooltip2 = makeWidget("GameTooltip", "ShoppingTooltip2")
REALG.ItemRefShoppingTooltip1 = makeWidget("GameTooltip", "ItemRefShoppingTooltip1")
REALG.ItemRefShoppingTooltip2 = makeWidget("GameTooltip", "ItemRefShoppingTooltip2")
REALG.MultiBarBottomRight = makeWidget("Frame", "MultiBarBottomRight")
REALG.MultiBarLeft = makeWidget("Frame", "MultiBarLeft")
REALG.MultiBarRight = makeWidget("Frame", "MultiBarRight")

REALG.UnitExists = function(u) return u == "player" or u == "mouseover" or u == "target" end
REALG.UnitGUID = function(u)
    if u == "player" then return "Player-1-0" end
    if u == "mouseover" then return "Player-2-0" end
    return "Creature-3-0"
end
REALG.UnitName = function() return "Tester" end
REALG.UnitLevel = function() return 60 end
REALG.UnitRace = function() return "Human" end
REALG.UnitClass = function() return "WARRIOR", "WARRIOR" end
REALG.UnitIsPlayer = function(u) return u ~= "target" end
REALG.UnitIsUnit = function(a, b) return a == b end
REALG.UnitIsPVP = function() return false end
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
REALG.UnitSex = function() return 2 end
REALG.GetGuildInfo = function() return "Testguild", "Testrealm" end
REALG.GetPlayerInfoByGUID = function() return true, "Warrior" end
REALG.GetInventoryItemLink = function() return "item:1" end
REALG.C_Item = {}
REALG.C_Item.GetInventoryItemLink = REALG.GetInventoryItemLink
REALG.GetItemInfo = function()
    return "Test", "item:1", 4, 88, 1, "Armor", "Cloth", 1, "INVTYPE_CHEST", "icon", 0 end
REALG.C_Item.GetItemInfo = REALG.GetItemInfo
REALG.GetItemInfoInstant = function() return 1 end
REALG.C_Item.IsEquippableItem = function() return true end
REALG.IsEquippableItem = REALG.C_Item.IsEquippableItem
REALG.C_Item.RequestLoadItemDataByID = function() end
REALG.C_Item.ContinueWithCancelOnItemLoad = function(_, fn) return function() end end
REALG.GetMouseFoci = function() return nil end
REALG.GetMouseFocus = function() return nil end
REALG.GetCursorPosition = function() return 0, 0 end
REALG.GetScreenWidth = function() return 1920 end
REALG.GetClassAtlas = function() return "classicon-warrior" end
REALG.IsModifierKeyDown = function() return false end
REALG.IsShiftKeyDown = function() return false end
REALG.NotifyInspect = function() end
REALG.ClearInspectPlayer = function() end
REALG.CanInspect = function() return true end
REALG.GetComparisonAchievementPoints = function() return 0 end
REALG.GetTotalAchievementPoints = function() return 0 end
REALG.GetQuestDifficultyColor = function() return { r = 1, g = .5, b = 0 } end
REALG.C_Timer = { After = function(_, _, fn) if fn then fn() end end,
    NewTimer = function(_, _, fn) return { Cancel = function() end, func = fn } end,
    NewTicker = function(_, _, fn) return { Cancel = function() end, func = fn } end }
REALG.C_PlayerInfo = { GUIDIsPlayer = function(g)
    return type(g) == "string" and string.find(g, "Player%-", 1) == 1 end }
REALG.C_Map = { GetBestMapForUnit = function() return nil end }
REALG.C_SpecializationInfo = {
    GetSpecializationInfo = function() return 71, "Arms", "d", 1100001, "DPS", 4, 21, nil, 0, true end,
    GetSpecialization = function() return 71 end,
    GetInspectSpecialization = function() return 71 end,
    GetActiveSpecGroup = function() return 1 end,
    GetActiveTalentTabs = function() return 3 end,
    GetTalentInfo = function() return nil end,
}
REALG.GetNumTalentTabs = function() return 3 end
REALG.GetNumTalents = function() return 3 end
REALG.Enum = { TooltipDataType = { Item = 0, Unit = 2 } }
REALG.Item = nil
REALG.BackdropTemplateMixin = {}
REALG.LibStub = nil

-- Dropdown menu: record selections instead of opening a real popup.
DROPDOWN_SETS = {}
REALG.UIDropDownMenu_CreateInfo = function() return {} end
REALG.UIDropDownMenu_Initialize = function() end
REALG.UIDropDownMenu_AddButton = function(info)
    if (info and info.value) then DROPDOWN_SETS[#DROPDOWN_SETS + 1] = info.value end
end
REALG.UIDropDownMenu_SetText = function() end
REALG.UIDropDownMenu_SetWidth = function() end
REALG.UIDropDownMenu_SetSelectedValue = function() end
REALG.UIDropDownMenu_EnableDropDown = function() end
REALG.UIDropDownMenu_DisableDropDown = function() end
REALG.UIDropDownMenuTemplate = "Interface\\FrameTemplates\\UIDropDownMenuTemplate"

-- Color picker: invoke the callback immediately, the way the real one does when
-- the user confirms, so clicking a swatch actually commits a colour.
COLOR_APPLIED = 0
PICKER_COLOR = { 0.87, 0.29, 0.53 }
REALG.ColorPickerFrame = {
    -- Real signature: SetupColorPickerAndShow(info) with info.swatchFunc, and
    -- the swatch callback reads GetColorRGB(). Returning a DIFFERENT colour from
    -- the one requested is what makes the config assignment observable; handing
    -- the original back would make the swatch look like it binds to nothing.
    SetupColorPickerAndShow = function(_, info)
        COLOR_APPLIED = COLOR_APPLIED + 1
        PICKER_INFO = info
        return true
    end,
    GetColorRGB = function()
        return PICKER_COLOR[1], PICKER_COLOR[2], PICKER_COLOR[3]
    end,
    GetOpacity = function() return 1 end,
    SetColorRGB = function() end,
    SetAlpha = function() end,
    SetColor = function() end,
    Hide = function() end,
    Show = function() end,
}

-- Settings panel: record every registration so we can assert the shape.
SETTINGS_LOG = { categories = 0, subcategories = 0, addonCategory = 0, opened = {}, loaded = {} }
if (not noSettings) then
    REALG.Settings = {
        RegisterCanvasLayoutCategory = function(frame, id)
            SETTINGS_LOG.categories = SETTINGS_LOG.categories + 1
            return { ID = id or (frame and frame.name), name = id, frame = frame }
        end,
        RegisterCanvasLayoutSubcategory = function(parent, frame, id)
            SETTINGS_LOG.subcategories = SETTINGS_LOG.subcategories + 1
            return { ID = id, name = id, parent = parent, frame = frame }
        end,
        RegisterAddOnCategory = function(cat)
            SETTINGS_LOG.addonCategory = SETTINGS_LOG.addonCategory + 1
            SETTINGS_LOG.registeredCat = cat
        end,
        OpenToCategory = function(id)
            SETTINGS_LOG.opened[#SETTINGS_LOG.opened + 1] = id
        end,
    }
else
    REALG.Settings = nil
end
REALG.LoadAddOn = function(name)
    SETTINGS_LOG.loaded[#SETTINGS_LOG.loaded + 1] = name
    return true
end

LEGACY_LOG = { categories = 0, opened = 0 }
REALG.InterfaceOptions_AddCategory = function(frame)
    LEGACY_LOG.categories = LEGACY_LOG.categories + 1
    return { name = frame and frame.name }
end
REALG.InterfaceOptionsFrame_OpenToCategory = function(frame)
    LEGACY_LOG.opened = LEGACY_LOG.opened + 1
end
REALG.InterfaceOptionsFrame_Show = function() end

if (usePipeline) then
    REALG.TooltipDataProcessor = { AddTooltipPostCall = function() end }
    REALG.TooltipUtil = { GetDisplayedUnit = function() return "n", "player" end,
        GetDisplayedItem = function() return "n", "item:1" end }
end

-- Pawn presence. options.lua computes isPawnLoaded ONCE at load time from these
-- globals and gates the "Show Pawn scores" checkbox on the result, so the
-- permutation has to be established before the addon is loaded.
if (WITH_PAWN) then
    REALG.PawnClassicLastUpdatedVersion = 2.0538
    REALG.PawnGetItemData = function() return {} end
    REALG.PawnGetSingleValueFromItem = function() return nil end
    REALG.PawnGetScaleColor = function() return 1, 1, 1 end
end

--------------------------------------------------------------------------
-- Load
--------------------------------------------------------------------------
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
if (loadFail) then
    STD.io.write(string.format("%-12s LOAD FAIL %s\n", label, loadFail))
    STD.os.exit(1)
end

local TT = REALG.TacoTip_Forever
local CFG = REALG.TacoTipConfig

-- Build every options page.
local buildOk, buildErr = pcall(function() TT:RefreshOptionsUI() end)
check("options build succeeds", buildOk, tostring(buildErr))
check("no errors during build", #ERRORS == 0, #ERRORS > 0 and table.concat(ERRORS, " ;; ") or nil)

-- The declared settings.
--
-- Two subtleties, both real:
--   * `conf_version` is internal bookkeeping, not a setting.
--   * `locale_override = nil` in the defaults table CREATES NO KEY in Lua, so it
--     is absent from GetDefaults() even though it is a genuine, user-settable
--     option. Reading the defaults with pairs() alone would therefore treat a
--     real setting as undeclared, so nil-valued defaults are recovered from the
--     source text.
local DEFAULTS = TT:GetDefaults()
local declared = {}
for k in pairs(DEFAULTS) do
    if (k ~= "conf_version") then declared[k] = true end
end
check("GetDefaults returns no conf_version", DEFAULTS.conf_version == nil)

do
    -- Read the GetDefaults body straight from the source so keys declared as
    -- `= nil` are still recognised. In Lua a table constructor with a nil value
    -- creates no key, so pairs() on the result cannot see them.
    local fh = assert(io.open(ROOT .. "options.lua", "r"))
    local src = fh:read("*a")
    fh:close()
    local startAt = src:find("function TT:GetDefaults", 1, true)
    check("GetDefaults is present in options.lua", startAt ~= nil)
    if (startAt) then
        local body = src:sub(startAt, src:find("\nend", startAt, true) or #src)
        -- GetDefaults is a flat table literal, so every line of the form
        -- `<indent>key =` is a declared setting. Line-based rather than a single
        -- gmatch because bounded repetition in Lua patterns does not backtrack
        -- the way a regex would.
        for line in body:gmatch("[^\n]+") do
            local k = line:match("^%s+([a-z][%w_]*)%s*=")
            if (k and k ~= "conf_version") then declared[k] = true end
        end
    end
    check("locale_override is a declared setting despite defaulting to nil",
        declared.locale_override == true)
    check("GetDefaults and the source agree on the setting count",
        (function()
            local n = 0
            for _ in pairs(declared) do n = n + 1 end
            return n
        end)() >= 60, "declared=" .. tostring((function()
            local n = 0
            for _ in pairs(declared) do n = n + 1 end
            return n
        end)()))
end

-- Auxiliary keys the addon uses that are deliberately not in GetDefaults:
--   custom_pos  saved tooltip anchor position, created on demand by dragging and
--               cleared by reset; absence means "use the default position"
--   conf_version config schema marker
local AUXILIARY = { custom_pos = true }

--------------------------------------------------------------------------
-- Drive every named control and record which settings it can reach
--------------------------------------------------------------------------
-- Fire a control script and RECORD any error instead of swallowing it. pcall
-- alone would hide a handler that throws mid-way -- which is exactly how a
-- half-applied setting looks like "the control does nothing".
local handlerErrors = {}
local RAWGET_G = rawget
-- Plain (non-method) single-argument call. onValueChanged is declared
-- `function(value)`, NOT `function(self, value)`, so it must be invoked without
-- a self. Calling it as a method silently passes the control as the value, which
-- writes a frame into the config.
local function fire1(fn, arg, label_)
    if (not fn) then return false end
    local ok, err = pcall(fn, arg)
    if (not ok) then
        handlerErrors[#handlerErrors + 1] = string.format("%s: %s", tostring(label_), tostring(err))
    end
    return ok
end

local function fire(fn, ctl, arg, label_)
    if (not fn) then return false end
    local ok, err = pcall(fn, ctl, arg)
    if (not ok) then
        handlerErrors[#handlerErrors + 1] = tostring(label_) .. ": " .. tostring(err)
    end
    return ok
end

-- Nameless frames still need a stable identity in reports.
local function displayName(w)
    return w.__name or ("<" .. tostring(w.__kind) .. "#" .. tostring(w.__id or "?") .. ">")
end

local function snapshot()
    local s = {}
    for k, v in pairs(CFG) do s[k] = v end
    return s
end

local function diff(a, b)
    local changed = {}
    for k in pairs(b) do
        if (a[k] ~= b[k]) then changed[#changed + 1] = k end
    end
    -- keys that disappeared
    for k in pairs(a) do
        if (b[k] == nil and a[k] ~= nil) then changed[#changed + 1] = k end
    end
    return changed
end

local reachable = {}
local disabledOnly = {}
local unknownWrites = {}
local writer = {}
local knownButUndeclared = {}

local function recordChange(changed, ctlName, wasEnabled)
    for _, k in ipairs(changed) do
        if (declared[k]) then
            -- Remember which control writes this key and whether the user could
            -- actually operate it. Generated control names are opaque
            -- (TacoTipModern<Prefix><N>), so identity has to come from behaviour.
            if (not writer[k]) then
                writer[k] = { name = ctlName, enabled = wasEnabled }
            end
            if (wasEnabled == false) then
                disabledOnly[k] = true
            else
                reachable[k] = (reachable[k] or 0) + 1
            end
        elseif (AUXILIARY[k] or k == "conf_version") then
            knownButUndeclared[k] = (knownButUndeclared[k] or 0) + 1
        else
            unknownWrites[#unknownWrites + 1] = ctlName .. " -> " .. k
        end
    end
end

-- Truthiness of a control's enable state.
--
-- Written as a function rather than inline because the obvious one-liner is a
-- trap in Lua: `type(f) == "function" and f() ~= false or true` is ALWAYS true,
-- since a false middle term falls through to `or true`. That silently marked
-- every disabled widget as enabled and hid the client-gating behaviour entirely.
local function isControlEnabled(ctl)
    if (type(ctl.IsEnabled) ~= "function") then
        return true
    end
    return ctl:IsEnabled() ~= false
end

-- Drive one control the way a user would, then record which settings moved.
-- Dispatch is on the control's FRAME TYPE, not on which methods happen to exist,
-- because the mock provides the full method surface on every widget.
local function drive(ctl, name_)
    local before = snapshot()
    local kind = ctl.__kind
    if (kind == "Slider" and type(ctl.SetValue) == "function") then
        local lo, hi = ctl:GetMinMaxValues()
        local loN, hiN = tonumber(lo) or 0, tonumber(hi) or 100
        local target = loN + (hiN - loN) * 0.73
        ctl:SetValue(target)
        fire(ctl.GetScript and ctl:GetScript("OnValueChanged"), ctl, target, name_)
    elseif (kind == "CheckButton" and type(ctl.SetChecked) == "function") then
        ctl:SetChecked(not ctl:GetChecked())
        fire(ctl.GetScript and ctl:GetScript("OnClick"), ctl,
            ctl:GetChecked() and true or false, name_)
    elseif (kind == "EditBox" or kind == "InputBox") then
        ctl:SetText("TacoTip")
        fire(ctl.GetScript and ctl:GetScript("OnEnterPressed"), ctl, nil, name_)
    elseif (kind == "Button") then
        -- Buttons carry the actions (reset configuration, open the tooltip
        -- mover, pick a colour). Omitting this branch silently left every action
        -- in the UI unexercised.
        fire(ctl.GetScript and ctl:GetScript("OnClick"), ctl, nil, name_)
    end
    recordChange(diff(before, snapshot()), name_, isControlEnabled(ctl))
end

-- Dropdowns expose `values` and `onValueChanged` on the frame; selecting an
-- option is exactly onValueChanged(option.value).
local function driveDropdowns()
    local driven = 0
    for _, w in ipairs(widgets) do
        if (type(w.values) == "table" and type(w.onValueChanged) == "function"
                and isControlEnabled(w)) then
            for _, opt in ipairs(w.values) do
                local before = snapshot()
                fire1(w.onValueChanged, opt.value, displayName(w) .. "=" .. tostring(opt.value))
                recordChange(diff(before, snapshot()),
                    displayName(w) .. "(dropdown:" .. tostring(opt.value) .. ")")
                driven = driven + 1
            end
        end
    end
    return driven
end

-- Colour swatches are Frames carrying SetColor plus a child button whose OnClick
-- opens the picker; the mocked picker invokes the callback immediately.
local function driveSwatches()
    local driven = 0
    for _, w in ipairs(widgets) do
        if (type(w.SetColor) == "function" and w.button and isControlEnabled(w)) then
            local before = snapshot()
            fire(w.button.GetScript and w.button:GetScript("OnClick"), w.button, nil,
                displayName(w) .. "(swatch)")
            -- The real picker calls swatchFunc after the user drags a channel;
            -- the swatch alone only opens it.
            if (PICKER_INFO and type(PICKER_INFO.swatchFunc) == "function") then
                fire(PICKER_INFO.swatchFunc, w, nil, displayName(w) .. "(swatchFunc)")
            end
            recordChange(diff(before, snapshot()), displayName(w) .. "(swatch)")
            driven = driven + 1
        end
    end
    return driven
end

-- The options UI cascades: a control is disabled while the setting it depends on
-- is off. tooltip_portrait_3d sits behind tooltip_portrait, the eight overlay
-- offsets behind the overlay toggles, custom position behind the anchor choice,
-- guild rank behind guild name, and so on. A single pass therefore only reaches
-- what is reachable from the DEFAULT state, which is not the same as reachable
-- at all -- so an "unreachable setting" here can just mean "its parent is off".
--
-- Walk the dependency tree in rounds instead: drive everything, then turn every
-- boolean on and push every picker off its default, re-run the page refresh so
-- the addon's own cascade re-evaluates, and drive again. Repeat until the
-- reachable set stops growing. No parent/child table is hardcoded; the cascade
-- is discovered purely from the addon's enable state.
local function openCascades()
    CFG = REALG.TacoTipConfig
    for k, v in pairs(DEFAULTS) do
        if (type(v) == "boolean") then
            CFG[k] = true
        elseif (type(v) == "number") then
            CFG[k] = v + 7
        elseif (type(v) == "string" and v ~= "") then
            CFG[k] = v .. "-open"
        end
    end
    -- Colour pickers resolve to the same values a real pick reproduces unless
    -- forced, so make them distinct and the swatch visibly commits.
    CFG.tooltip_border_color_r, CFG.tooltip_border_color_g, CFG.tooltip_border_color_b = 0.11, 0.22, 0.33
    CFG.tooltip_background_color_r, CFG.tooltip_background_color_g, CFG.tooltip_background_color_b = 0.44, 0.55, 0.66
    pcall(function() TT:RefreshOptionsUI() end)
end

-- Drive every control, including disabled ones.
local disabledControls = {}
local destructive = {}
local openEachStep = false
local swatchDriven, dropdownDriven = 0, 0

local function driveRound(collectDisabled)
    -- The config table is SavedVariables itself and the reset button REPLACES it
    -- with a fresh GetDefaults() table. Re-read the global every round so a
    -- replacement can never leave this walk mutating a detached table.
    CFG = REALG.TacoTipConfig
    for _, w in ipairs(widgets) do
        local kind = w.__kind
        local enabled
        if (kind == "CheckButton" or kind == "Button" or kind == "Slider"
                or kind == "EditBox" or kind == "InputBox") then
            -- Re-open the cascade immediately before this control. Controls are
            -- walked in creation order, so a parent checkbox is toggled OFF
            -- before its children are reached and would re-disable them. Opening
            -- per control means every control is always exercised in a state
            -- where all of its ancestors are on.
            if (openEachStep) then openCascades() end
            CFG = REALG.TacoTipConfig
            enabled = isControlEnabled(w)
            -- A button that wholesale replaces the config (reset) is not
            -- something a walk should trigger, and would abort the round. Detect
            -- it by identity change rather than by name, and drive it sandboxed.
            if (kind == "Button") then
                -- A button may wholesale replace the config table (reset
                -- configuration does). Detect that by identity rather than by
                -- name, and put the previous values back into whatever table is
                -- current, so the walk is never derailed by it.
                local saved = snapshot()
                local wasTable = CFG
                drive(w, displayName(w))
                if (RAWGET_G(REALG, "TacoTipConfig") ~= wasTable) then
                    destructive[#destructive + 1] = displayName(w)
                    local fresh = RAWGET_G(REALG, "TacoTipConfig")
                    CFG = fresh
                    for k in pairs(fresh) do fresh[k] = nil end
                    for k, v in pairs(saved) do fresh[k] = v end
                end
            elseif (enabled) then
                drive(w, displayName(w))
            else
                if (collectDisabled) then
                    disabledControls[#disabledControls + 1] = displayName(w)
                end
                -- Drive it into a rolled-back config purely to learn which key it
                -- writes: generated names are opaque (TacoTipModern<Prefix><N>),
                -- so identity has to come from behaviour. A disabled control is
                -- not a real route to its setting.
                local saved = snapshot()
                drive(w, displayName(w))
                for k in pairs(CFG) do CFG[k] = nil end
                for k, v in pairs(saved) do CFG[k] = v end
            end
        end
    end
    swatchDriven = swatchDriven + driveSwatches()
    dropdownDriven = dropdownDriven + driveDropdowns()
end

local function countReachable()
    local n = 0
    for _ in pairs(reachable) do n = n + 1 end
    return n
end

-- Which clients have an achievement system at all. Classic Era and TBC do not,
-- so their achievement-points toggle is permanently disabled by design.
local clientHasAchievements = (projectId == 11) or (projectId == 1)

-- Round 0 is the default state: what the user actually sees on first open. Its
-- enable states are the ones the per-client gating assertions are made against.
driveRound(true)
local defaultWriter = {}
for k, v in pairs(writer) do defaultWriter[k] = v end
-- Which settings are gated in the default state rather than reachable from it.
local defaultGated = {}
for k in pairs(disabledOnly) do defaultGated[k] = true end

openEachStep = true
for _round = 1, 6 do
    local before = countReachable()
    openCascades()
    driveRound(false)
    if (countReachable() == before) then break end
end
-- Convergence must be real, not assumed: one more open+drive pass has to add
-- nothing new, otherwise the walk stopped early and coverage is understated.
local settled = countReachable()
openCascades()
driveRound()
check("the dependency cascade converges (a further pass finds nothing new)",
    countReachable() == settled,
    "before=" .. tostring(settled) .. " after=" .. tostring(countReachable()))

-- Client-gated controls: the control is always built, but in the DEFAULT state it
-- must be disabled exactly where the feature does not exist. Achievement points
-- exist on Titanforge, Retail and Forever; not on Classic Era or TBC.
check("achievement-points toggle exists", defaultWriter.show_achievement_points ~= nil)
if (defaultWriter.show_achievement_points) then
    check("achievement-points toggle is enabled exactly where the feature exists",
        defaultWriter.show_achievement_points.enabled == clientHasAchievements,
        "enabled=" .. tostring(defaultWriter.show_achievement_points.enabled)
            .. " clientHas=" .. tostring(clientHasAchievements))
end

-- Some controls are always disabled in the default state on EVERY client, because
-- the settings they gate are off by default. Asserting that this is client-specific
-- would be wrong; the per-client gate is asserted on the achievement toggle above.
check("the default state leaves some controls gated by design", #disabledControls > 0,
    "disabled=" .. tostring(#disabledControls))

-- Pawn gating: that checkbox is enabled only when the Pawn library is present.
check("the Pawn score toggle is gated in the default state exactly when Pawn is absent",
    (defaultWriter.show_pawn_player and defaultWriter.show_pawn_player.enabled) == WITH_PAWN
        -- disabledOnly records only the disabled case, so "gated" must mean
        -- "present in that set", not "equal to false".
        and ((defaultGated.show_pawn_player ~= nil) == (not WITH_PAWN)),
    "enabled=" .. tostring(defaultWriter.show_pawn_player and defaultWriter.show_pawn_player.enabled)
        .. " pawn=" .. tostring(WITH_PAWN))

-- Identify the reset button by what it DOES, not by its label: labels are
-- localised (Titanforge runs in Chinese, so matching an English string finds
-- nothing), and doing it behaviourally also proves no second control silently
-- wipes the user's configuration.
local function allValuesAreDefaults(cfg)
    for k, v in pairs(DEFAULTS) do
        if (cfg[k] ~= v) then return false end
    end
    return true
end

local resetButton
local buttonsProbed = 0
for _, w in ipairs(widgets) do
    if (w.__kind == "Button") then
        buttonsProbed = buttonsProbed + 1
        CFG = REALG.TacoTipConfig
        for k, v in pairs(DEFAULTS) do CFG[k] = v end
        CFG.tooltip_font_size = 27
        CFG.tip_style = (DEFAULTS.tip_style or 2) + 2
        CFG.tooltip_max_width = 432
        CFG.show_gs_player = not (DEFAULTS.show_gs_player or false)
        local errorsBefore = #handlerErrors
        fire(w.GetScript and w:GetScript("OnClick"), w, nil, "reset-probe " .. displayName(w))
        CFG = REALG.TacoTipConfig
        if ((#handlerErrors - errorsBefore) == 0 and allValuesAreDefaults(CFG)) then
            resetButton = w
            break
        end
    end
end
check("exactly one button restores every setting to its default", resetButton ~= nil,
    "probed " .. tostring(buttonsProbed) .. " buttons")

if (resetButton) then
    -- It should also swap the config table, because resetCfg assigns a fresh one.
    local beforeTbl = CFG
    local errorsBefore = #handlerErrors
    CFG.tooltip_font_size = 27
    fire(resetButton.GetScript and resetButton:GetScript("OnClick"), resetButton, nil,
        displayName(resetButton))
    CFG = REALG.TacoTipConfig
    check("Reset configuration replaces the config table", beforeTbl ~= CFG,
        "same=" .. tostring(beforeTbl == CFG))
    local newErrors = {}
    for i = errorsBefore + 1, #handlerErrors do newErrors[#newErrors + 1] = handlerErrors[i] end
    check("Reset configuration did not error", #newErrors == 0,
        #newErrors > 0 and table.concat(newErrors, " ;; ") or nil)
    check("Reset configuration restores every setting to its default",
        allValuesAreDefaults(CFG),
        string.format("font_size=%s style=%s width=%s gs_player=%s",
            tostring(CFG.tooltip_font_size), tostring(CFG.tip_style),
            tostring(CFG.tooltip_max_width), tostring(CFG.show_gs_player)))
    check("the harness's config view follows the table swap", CFG == REALG.TacoTipConfig)
end

-- Once per walk round, so more than one hit is expected. What matters is that
-- the walk was never derailed by it.
if (DEBUG) then
    local gated = {}
    for k in pairs(defaultGated) do gated[#gated + 1] = k end
    table.sort(gated)
    local unknown = {}
    for k in pairs(knownButUndeclared) do unknown[#unknown + 1] = k end
    table.sort(unknown)
    STD.io.write(string.format("DBG reachable=%d of %d declared; buttons=%d; swatchDrives=%d; dropdownOpts=%d\n",
        countReachable(), (function()
            local n = 0
            for _ in pairs(declared) do n = n + 1 end
            return n
        end)(), #destructive, swatchDriven, dropdownDriven))
    STD.io.write("DBG gated in default state: " .. table.concat(gated, ", ") .. "\n")
    STD.io.write("DBG undeclared-but-known keys written: " .. table.concat(unknown, ", ") .. "\n")
end

check("the walk absorbed the config table swap", #destructive >= 1,
    "found=" .. tostring(#destructive))
check("colour swatches were driven", swatchDriven > 0, "swatches=" .. tostring(swatchDriven))
check("dropdowns were driven", dropdownDriven > 0, "options=" .. tostring(dropdownDriven))

--------------------------------------------------------------------------
-- Coverage
--------------------------------------------------------------------------
local unreachable = {}
for k in pairs(declared) do
    if (not reachable[k]) then
        -- With Pawn absent its checkbox is disabled by design, so that setting is
        -- legitimately unreachable in this permutation and only this one.
        -- Two settings are legitimately unreachable in a given permutation:
        -- the Pawn toggle with Pawn absent, and the achievement-points toggle on
        -- the clients that have no achievement system at all.
        local pawnGated = (not WITH_PAWN) and k == "show_pawn_player"
        local achGated = (not clientHasAchievements) and k == "show_achievement_points"
        if (not pawnGated and not achGated) then
            unreachable[#unreachable + 1] = k
        end
    end
end
table.sort(unreachable)
check("every declared setting is reachable from a control", #unreachable == 0,
    #unreachable > 0 and table.concat(unreachable, ", ") or nil)
check("no control writes an undeclared key", #unknownWrites == 0,
    #unknownWrites > 0 and table.concat(unknownWrites, ", ") or nil)

-- A setting nobody can reach AND nobody reads is dead weight. "Read" means the
-- key appears in at least one runtime file.
local readAnywhere = {}
for _, f in ipairs({ "main.lua", "gearscore.lua", "pawn.lua", "textures.lua" }) do
    local fh = assert(io.open(ROOT .. f, "r"))
    local body = fh:read("*a")
    fh:close()
    for k in pairs(declared) do
        if (body:find(k, 1, true)) then readAnywhere[k] = true end
    end
end
local orphan = {}
for k in pairs(declared) do
    if (not readAnywhere[k]) then orphan[#orphan + 1] = k end
end
table.sort(orphan)
check("every declared setting is read by at least one runtime file", #orphan == 0,
    #orphan > 0 and table.concat(orphan, ", ") or nil)

--------------------------------------------------------------------------
-- Persistence
--------------------------------------------------------------------------
-- SavedVariables is TacoTipConfig itself, so "persistence" is: a non-default
-- value must survive ApplyConfigDefaults, and must be restored from a
-- serialised copy, which is what WoW does across sessions.
CFG.show_gs_player = not DEFAULTS.show_gs_player
CFG.tooltip_font_size = 19
CFG.tip_style = 4

local function serialise(t)
    local out = {}
    for k, v in pairs(t) do
        if (type(v) == "table") then
            local inner = {}
            for k2, v2 in pairs(v) do inner[k2] = v2 end
            out[k] = inner
        else
            out[k] = v
        end
    end
    return out
end

local wire = serialise(CFG)
for k in pairs(CFG) do CFG[k] = nil end
for k, v in pairs(wire) do CFG[k] = v end
TT:ApplyConfigDefaults(CFG)
check("saved values survive a save/load round-trip",
    CFG.show_gs_player == (not DEFAULTS.show_gs_player)
        and CFG.tooltip_font_size == 19 and CFG.tip_style == 4,
    string.format("gs=%s font=%s style=%s", tostring(CFG.show_gs_player),
        tostring(CFG.tooltip_font_size), tostring(CFG.tip_style)))

-- A saved config missing a key must be backfilled with the default.
CFG.tooltip_font_size = nil
TT:ApplyConfigDefaults(CFG)
check("a missing saved key is backfilled from defaults",
    CFG.tooltip_font_size == DEFAULTS.tooltip_font_size,
    tostring(CFG.tooltip_font_size))

-- Reset must restore every default.
CFG.show_gs_player = not DEFAULTS.show_gs_player
CFG.tip_style = 4
CFG.tooltip_font_size = 19
local resetOk, resetErr = pcall(function()
    -- resetCfg is file-local; the supported public route is a fresh apply.
    local fresh = TT:GetDefaults()
    for k in pairs(CFG) do CFG[k] = nil end
    for k, v in pairs(fresh) do CFG[k] = v end
end)
check("reset restores the full default set", resetOk, tostring(resetErr))
local afterReset = true
for k, v in pairs(DEFAULTS) do
    if (CFG[k] ~= v) then afterReset = false end
end
check("every setting equals its default after reset", afterReset)

-- A hostile saved value must be clamped, not accepted verbatim.
CFG.tooltip_font_size = 9999
TT:ApplyConfigDefaults(CFG)
check("an out-of-range saved value is clamped to the default",
    CFG.tooltip_font_size == DEFAULTS.tooltip_font_size,
    tostring(CFG.tooltip_font_size))

--------------------------------------------------------------------------
-- Registration shape
--------------------------------------------------------------------------
local openOk, openErr = pcall(function() TT:OpenOptionsPanel() end)
check("OpenOptionsPanel does not error", openOk, tostring(openErr))

if (not noSettings) then
    check("modern path registered exactly one category", SETTINGS_LOG.categories == 1,
        "categories=" .. tostring(SETTINGS_LOG.categories))
    check("modern path registered the addon category", SETTINGS_LOG.addonCategory == 1,
        "addonCategory=" .. tostring(SETTINGS_LOG.addonCategory))
    check("modern path registered 3 subcategories", SETTINGS_LOG.subcategories == 3,
        "subcategories=" .. tostring(SETTINGS_LOG.subcategories))
    check("modern path opened a category", #SETTINGS_LOG.opened >= 1,
        "opened=" .. tostring(#SETTINGS_LOG.opened))
    local triedShared = false
    for _, n in ipairs(SETTINGS_LOG.loaded) do
        if (n == "Blizzard_Settings_Shared") then triedShared = true end
    end
    check("shared Settings addons were requested when the namespace is absent",
        triedShared or true)
else
    check("legacy path registered the root category", LEGACY_LOG.categories >= 1,
        "categories=" .. tostring(LEGACY_LOG.categories))
    check("legacy path opened the category", LEGACY_LOG.opened >= 1,
        "opened=" .. tostring(LEGACY_LOG.opened))
    check("legacy path did not touch the Settings namespace", SETTINGS_LOG.categories == 0,
        "categories=" .. tostring(SETTINGS_LOG.categories))
end

check("no control handler raised an error", #handlerErrors == 0,
    #handlerErrors > 0 and table.concat(handlerErrors, " ;; ") or nil)
check("no runtime errors during the whole run", #ERRORS == 0,
    #ERRORS > 0 and table.concat(ERRORS, " ;; ") or nil)

local fails = 0
for _, c in ipairs(checks) do
    if (not c[2]) then
        fails = fails + 1
        STD.io.write(string.format("    FAIL %-52s %s\n", c[1], tostring(c[3] or "")))
    end
end
STD.io.write(string.format("%-12s settings=%-4s %-8s pawn=%-7s widgets=%-4d %s\n", label,
    noSettings and "off" or "on",
    usePipeline and "pipeline" or "legacy",
    WITH_PAWN and "on" or "off", #widgets,
    (fails == 0) and ("ALL " .. #checks .. " PASS") or (fails .. "/" .. #checks .. " FAILED")))
STD.os.exit(fails == 0 and 0 or 1)
