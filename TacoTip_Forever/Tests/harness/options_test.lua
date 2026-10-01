-- Executes the options UI build under a mocked client.
-- Usage: lua5.1 options_test.lua <projectId> <iface> <label> [pipeline] [nosettings] [nocolor] [nosharedmedia]

local ROOT = (os.getenv("TACOTIP_TEST_ROOT") or ".") .. "/"

local projectId, iface, label = tonumber(arg[1]), tonumber(arg[2]), arg[3]
local usePipeline  = (arg[4] == "pipeline")
local noSettings   = (arg[5] == "nosettings")
local noColor      = (arg[6] == "nocolor")
local noSharedMedia = (arg[7] == "nosharedmedia")

local REALG = _G
local STD = { os=os, string=string, pairs=pairs, ipairs=ipairs, type=type, pcall=pcall,
    tonumber=tonumber, tostring=tostring, select=select, rawget=rawget, rawset=rawset,
    setmetatable=setmetatable, getmetatable=getmetatable, unpack=unpack, assert=assert,
    error=error, math=math, table=table, loadfile=loadfile, print=print, io=io }

local errors = {}
local function recordErr(where, err)
    errors[#errors + 1] = where .. ": " .. tostring(err)
end

--------------------------------------------------------------------------
-- Mock widget
--------------------------------------------------------------------------
-- Widget methods the addon may call. Anything NOT in this set must read as nil,
-- exactly like a real frame: an unknown field is nil, and indexing it raises.
-- Returning a closure for every key would mask real nil-field bugs (the addon
-- reading tooltip.TacoTipBackdropFrame before it exists, for example).
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
    "SetMaxLetters","SetNonSpaceWrap","SetWordWrap","SetJustifyH","SetJustifyV",
    "SetStatusBarColor","SetStatusBarTexture","SetTexCoord","SetText","SetTexture",
    "SetUnit","SetUserPlaced","SetValue","SetValueStep","SetVerticalScroll","SetWidth",
    "SetWordWrap","Show","StartMoving","StopMovingOrSizing","UnregisterEvent",
    "UpdateScrollChildRect","UpdateTooltip","FadeOut","GetAnchorType","IsEquippedItem",
    "IsOwned","GetOwner","GetSpell","SetItem","SetPlayer","ClearLines","SetModelScale",
    "SetCamera","SetPosition","SetFacing","ClearModel","Refresh","GetDefaultAnchor",
    "SetClampRectInsets","GetMinMaxValues","GetValue","GetValueStep","GetScale",
    "SetChecked","RegisterUnitEvent","GetNumPoints","GetNumChildren","GetChildren",
    "SetClampedToScreen","SetToplevel","SetID","GetID","IsForbidden","SetPassThroughButtons",
}) do WIDGET_METHODS[m] = true end

local created = {}
local function makeWidget(kind, name, parent, template, depth)
    depth = depth or 0
    local w = { __kind = kind, __name = name, __parent = parent, __template = template }
    w.__scripts, w.__hooks, w.__events, w.__points = {}, {}, {}, {}
    w.__text, w.__fontObject, w.__shown = nil, nil, true
    created[#created + 1] = w

    local MT = {}
    MT.__index = function(t, k)
        local f = rawget(w, k)
        if f then return f end
        -- Unknown field => nil, like a real frame. Only known widget methods
        -- resolve to a no-op, so a genuine nil-field read still raises.
        if (WIDGET_METHODS[k]) then
            return function() return nil end
        end
        return nil
    end

    w.GetName        = function() return name end
    w.GetParent      = function() return parent end
    w.GetObjectType  = function() return kind end
    w.IsObjectType   = function(_, t) return kind == t end
    w.SetScript      = function(_, s, fn) w.__scripts[s] = fn end
    w.GetScript      = function(_, s) return w.__scripts[s] end
    w.HookScript     = function(_, s, fn) w.__hooks[s] = fn end
    w.RegisterEvent  = function(_, e) w.__events[#w.__events + 1] = e end
    w.UnregisterEvent = function() end
    w.IsShown        = function() return w.__shown end
    w.SetShown       = function(_, v) w.__shown = v and true or false end
    w.Show           = function() w.__shown = true end
    w.Hide           = function() w.__shown = false end
    w.SetPoint       = function() end
    w.ClearAllPoints = function() end
    w.SetAllPoints   = function() end
    w.SetSize        = function(_, ww, hh) w.__w, w.__h = ww, hh end
    w.SetWidth       = function(_, ww) w.__w = ww end
    w.SetHeight      = function(_, hh) w.__h = hh end
    w.GetWidth       = function() return w.__w or 0 end
    w.GetHeight      = function() return w.__h or 0 end
    w.GetSize        = function() return w.__w or 0, w.__h or 0 end
    w.GetCenter      = function() return 0, 0 end
    w.GetLeft        = function() return 0 end
    w.GetRight       = function() return 0 end
    w.GetTop         = function() return 0 end
    w.GetBottom      = function() return 0 end
    w.GetFrameLevel  = function() return 1 end
    w.GetFrameStrata = function() return "MEDIUM" end
    w.SetFrameLevel  = function() end
    w.SetFrameStrata = function() end
    w.SetAlpha       = function() end
    w.GetAlpha       = function() return 1 end
    w.SetBackdrop    = function() end
    w.SetBackdropColor = function() end
    w.SetBackdropBorderColor = function() end
    w.GetBackdropBorderColor = function() return 1, 1, 1, 1 end
    w.SetClampedToScreen = function() end
    w.SetClampRectInsets = function() end
    w.SetHitRectInsets = function() end
    w.SetClampRectInsets = function() end
    w.EnableMouse    = function() end
    w.EnableMouseWheel = function() end
    w.SetMovable     = function() end
    w.SetUserPlaced  = function() end
    w.RegisterForClicks = function() end
    w.RegisterForDrag = function() end
    w.SetResizable   = function() end
    w.SetMinMaxResize = function() end
    w.StartMoving    = function() end
    w.StopMovingOrSizing = function() end
    w.SetNormalTexture = function() end
    w.SetHighlightTexture = function() end
    w.SetPushedTexture = function() end
    w.SetText        = function(_, t) w.__text = t end
    w.GetText        = function() return w.__text end
    w.SetFontObject  = function(_, f) w.__fontObject = f end
    w.GetFontObject  = function() return w.__fontObject end
    w.SetFont        = function() end
    w.SetJustifyH    = function() end
    w.SetJustifyV    = function() end
    w.SetWordWrap    = function() end
    w.SetNonSpaceWrap = function() end
    w.SetMaxLetters  = function() end
    w.SetShadowOffset = function() end
    w.SetShadowColor = function() end
    w.GetStringHeight = function() return 12 end
    w.SetVertexColor = function() end
    w.SetTexture     = function() end
    w.GetTexture     = function() return 1 end
    w.SetColorTexture = function() end
    w.SetTexCoord    = function() end
    w.SetDesaturated = function() end
    w.SetDrawLayer   = function() end
    w.SetBlendMode   = function() end
    w.SetStatusBarTexture = function() end
    w.SetStatusBarColor   = function() end
    w.SetMinMaxValues = function(_, mn, mx) w.__min, w.__max = mn, mx end
    w.GetMinMaxValues = function() return w.__min or 0, w.__max or 0 end
    w.SetValue       = function(_, v) w.__value = v end
    w.GetValue       = function() return w.__value or 0 end
    w.SetValueStep   = function() end
    w.GetValueStep   = function() return 1 end
    w.SetValueSilently = function() end
    w.SetObeyStepOnDrag = function() end
    w.SetOrientation = function() end
    w.SetThumbTexture = function() end
    w.SetStatusTexture = function() end
    w.SetChecked     = function(_, v) w.__checked = v and true or false end
    w.GetChecked     = function() return w.__checked end
    w.SetEnabled     = function(_, v) w.__enabled = v ~= false end
    w.IsEnabled      = function() return w.__enabled ~= false end
    w.SetDisabled    = function(_, v) w.__enabled = not v end
    w.Enable         = function() w.__enabled = true end
    w.Disable        = function() w.__enabled = false end
    w.SetAutoFocus   = function() end
    w.ClearFocus     = function() end
    w.SetFocus       = function() end
    w.SetScrollChild = function(_, c) w.__scrollChild = c end
    w.GetScrollChild = function() return w.__scrollChild end
    w.SetVerticalScroll = function() end
    w.GetVerticalScroll = function() return 0 end
    w.GetVerticalScrollRange = function() return 100 end
    w.UpdateScrollChildRect = function() end
    w.SetColor       = function(_, r, g, b) w.__color = { r, g, b } end
    w.GetColor       = function() return unpack(w.__color or { 1, 1, 1 }) end
    w.SetColorRGB    = function(_, r, g, b) w.__color = { r, g, b } end
    w.GetColorRGB    = function() return unpack(w.__color or { 1, 1, 1 }) end
    w.SetAlphaChannel = function() end
    w.SetMinMaxValues  = function(_, mn, mx) w.__min, w.__max = mn, mx end
    w.SetPortraitTexture = function() end
    w.SetPortraitZoom = function() end
    w.SetModelScale = function() end
    w.SetCamera     = function() end
    w.SetPosition   = function() end
    w.SetFacing     = function() end
    w.SetUnit       = function() end
    w.ClearModel    = function() end
    -- CreateFontString/CreateTexture register a GLOBAL of that name, exactly as
    -- the real API does. The addon relies on it: main.lua does
    -- CharacterModelFrame:CreateFontString("PersonalGearScore") and then reads
    -- the bare global PersonalGearScore.
    w.CreateFontString = function(_, n, sub, tmpl)
        local c = makeWidget("FontString", n or (name and name .. "FS"), w, tmpl, (depth or 0) + 1)
        if (n) then rawset(REALG, n, c) end
        return c
    end
    w.CreateTexture = function(_, n, sub, tmpl)
        local c = makeWidget("Texture", n or (name and name .. "T"), w, tmpl, (depth or 0) + 1)
        if (n) then rawset(REALG, n, c) end
        return c
    end
    w.CreateAnimation = function() return { SetDuration = function() end, SetFromAlpha = function() end, SetToAlpha = function() end } end
    w.Refresh        = function() end
    w.SetBackdropBorderSize = function() end
    w.GetObjectType_ = nil
    -- Simulate a widget whose named children exist (templates provide these).
    -- Depth-limited: a child must not itself spawn named children, or this
    -- recurses forever.
    if (name and depth < 1) then
        for _, suffix in ipairs({ "Text", "Low", "High", "TextLeft1", "TextRight1",
                                  "Middle", "Left", "Right", "Background" }) do
            if (not rawget(REALG, name .. suffix)) then
                rawset(REALG, name .. suffix, makeWidget("FontString", name .. suffix, w, nil, depth + 1))
            end
        end
    end
    return setmetatable(w, MT)
end

--------------------------------------------------------------------------
-- Environment
--------------------------------------------------------------------------
for k in STD.pairs(REALG) do REALG[k] = nil end
for k, v in STD.pairs(STD) do REALG[k] = v end
REALG._G = REALG
REALG.time = STD.os.time
local printed = {}
REALG.print = function(...) printed[#printed + 1] = STD.table.concat({ ... }, " ") end
REALG.geterrorhandler = function() return function(e) recordErr("errorhandler", e) end end
REALG.CreateFrame = function(kind, name, parent, template)
    return makeWidget(kind or "Frame", name, parent, template)
end
REALG.GetLocale = function() return "enUS" end
REALG.GetCVar = function() return "" end
REALG.SetCVar = function() end
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
REALG.SlashCmdList = {}
REALG.StaticPopupDialogs = {}
REALG.StaticPopup_Show = function() end
REALG.UISpecialFrames = {}
REALG.TacoTipConfig = {}

REALG.GetBuildInfo = function() return "1.15.9", "1", "d", iface, "us", "rel" end
REALG.WOW_PROJECT_MAINLINE = 1
REALG.WOW_PROJECT_CLASSIC = 2
REALG.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
REALG.WOW_PROJECT_WRATH_CLASSIC = 11
REALG.WOW_PROJECT_CATACLYSM_CLASSIC = 14
REALG.WOW_PROJECT_MISTS_CLASSIC = 19
REALG.WOW_PROJECT_ID = projectId

REALG.C_AddOns = { GetAddOnMetadata = function(_, k)
    if k == "Version" then return "0.7.8" end
    if k == "Title" then return "TacoTip Forever" end
    return nil end, IsAddOnLoaded = function() return false end }

for _, f in ipairs({ "GameFontNormal", "GameFontHighlight", "GameFontNormalSmall",
    "GameFontHighlightSmall", "GameFontDisable", "GameFontDisableSmall",
    "GameFontNormalLarge", "NumberFontNormal", "ChatFontNormal" }) do
    REALG[f] = f
end
REALG.NORMAL_FONT_COLOR = { r = 1, g = 1, b = 1 }
REALG.GRAY_FONT_COLOR = { r = .5, g = .5, b = .5 }
REALG.HIGHLIGHT_FONT_COLOR = { r = 1, g = .82, b = 0 }
REALG.RAID_CLASS_COLORS = { WARRIOR = { r = 1, g = .8, b = .5 } }
REALG.PowerBarColor = { [0] = { r = .3, g = .3, b = .8 } }
REALG.CONTAINER_OFFSET_X = 0
REALG.CONTAINER_OFFSET_Y = 0
REALG.PVP_FLAG_ICON = "Interface\\Icons\\pvp_icon"
REALG.HORDE_ICON = "Interface\\Icons\\inv_misc_note_01"
REALG.ALLIANCE_ICON = "Interface\\Icons\\inv_misc_note_02"
REALG.FACTION_BAR_TEXTURE = "Interface\\TargetingFrame\\UI-TargetingFrame-BarFill"
REALG.SAVED_VARIABLES = nil

REALG.UIParent = makeWidget("Frame", "UIParent")
REALG.WorldFrame = makeWidget("Frame", "WorldFrame")
REALG.GameTooltip = makeWidget("GameTooltip", "GameTooltip")
REALG.GameTooltipStatusBar = makeWidget("StatusBar", "GameTooltipStatusBar")
REALG.ItemRefTooltip = makeWidget("GameTooltip", "ItemRefTooltip")
REALG.ShoppingTooltip1 = makeWidget("GameTooltip", "ShoppingTooltip1")
REALG.ShoppingTooltip2 = makeWidget("GameTooltip", "ShoppingTooltip2")
REALG.ItemRefShoppingTooltip1 = makeWidget("GameTooltip", "ItemRefShoppingTooltip1")
REALG.ItemRefShoppingTooltip2 = makeWidget("GameTooltip", "ItemRefShoppingTooltip2")
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
REALG.MultiBarBottomRight = makeWidget("Frame", "MultiBarBottomRight")
REALG.MultiBarLeft = makeWidget("Frame", "MultiBarLeft")
REALG.MultiBarRight = makeWidget("Frame", "MultiBarRight")

for _, fn in ipairs({ "UnitExists", "UnitIsPlayer", "UnitIsUnit", "UnitIsPVP",
    "UnitIsConnected", "UnitIsSameServer", "UnitInParty", "UnitInRaid",
    "IsInGroup", "IsInRaid", "CanInspect", "IsEquippableItem" }) do
    REALG[fn] = function() return false end
end
REALG.UnitLevel = function() return 1 end
REALG.UnitRace = function() return "" end
REALG.UnitGUID = function() return nil end
REALG.UnitClass = function() return "Warrior", "WARRIOR" end
REALG.UnitName = function() return "Test" end
REALG.UnitPower = function() return 0 end
REALG.UnitPowerMax = function() return 100 end
REALG.UnitPowerType = function() return 1 end
REALG.UnitPVPName = function() return "" end
REALG.UnitFactionGroup = function() return "Alliance" end
REALG.UnitGroupRolesAssigned = function() return "NONE" end
REALG.UnitCanAttack = function() return false end
REALG.GetGuildInfo = function() return nil end
REALG.GetPlayerInfoByGUID = function() return true, "Warrior" end
REALG.GetInventoryItemLink = function() return nil end
REALG.GetItemInfo = function() return nil end
REALG.GetItemInfoInstant = function() return nil end
REALG.GetMouseFoci = function() return nil end
REALG.GetMouseFocus = function() return nil end
REALG.GetCursorPosition = function() return 0, 0 end
REALG.GetScreenWidth = function() return 1920 end
REALG.GetClassAtlas = function() return nil end
REALG.IsModifierKeyDown = function() return false end
REALG.IsShiftKeyDown = function() return false end
REALG.NotifyInspect = function() end
REALG.ClearInspectPlayer = function() end
REALG.GetComparisonAchievementPoints = function() return 0 end
REALG.GetTotalAchievementPoints = function() return 0 end
REALG.GetQuestDifficultyColor = function() return { r = 1, g = 1, b = 1 } end

REALG.C_Timer = { After = function() end,
    NewTimer = function(_, _, fn) return { Cancel = function() end, func = fn } end,
    NewTicker = function() return { Cancel = function() end } end }
REALG.C_Item = { GetItemInfo = function() return nil end, IsEquippableItem = function() return true end,
    RequestLoadItemDataByID = function() end, ContinueWithCancelOnItemLoad = function() end,
    GetInventoryItemLink = function() return nil end, GetItemLinkByID = function() return nil end }
REALG.C_PlayerInfo = { GUIDIsPlayer = function() return false end }
REALG.C_Map = { GetBestMapForUnit = function() return nil end }
REALG.C_SpecializationInfo = { GetSpecializationInfo = function() return nil end,
    GetInspectSpecialization = function() return nil end, GetActiveSpecGroup = function() return 1 end }
REALG.Enum = { TooltipDataType = { Item = 0, Unit = 2 } }

-- Client capability switches
if (usePipeline) then
    REALG.TooltipDataProcessor = { AddTooltipPostCall = function() end }
    REALG.TooltipUtil = { GetDisplayedUnit = function() return "n", nil, nil end,
                         GetDisplayedItem = function() return "n", nil end }
    local gt = REALG.GameTooltip
    gt.IsTooltipType = function() return true end
    gt.GetPrimaryTooltipData = function() return nil end
    gt.GetUnit = function() return "n", "mouseover", nil end
else
    REALG.TooltipDataProcessor = nil
    REALG.TooltipUtil = nil
    REALG.GameTooltip.GetUnit = function() return "n", "mouseover" end
end

if (noSettings) then
    REALG.Settings = nil
else
    local registered = {}
    REALG.Settings = {
        RegisterCanvasLayoutCategory = function(_, frame) registered.root = frame; return frame end,
        RegisterCanvasLayoutSubcategory = function(_, frame, parent) registered.sub = frame; registered.parent = parent; return frame end,
        RegisterAddOnCategory = function(_, frame) registered.addon = frame; return frame end,
        OpenToCategory = function(_, id) registered.opened = id end,
    }
    REALG.Settings.__registered = registered
end

if (noColor) then
    REALG.ColorPickerFrame = nil
else
    REALG.ColorPickerFrame = makeWidget("Frame", "ColorPickerFrame")
    REALG.ColorPickerFrame.SetupColorPickerAndShow = function() end
    REALG.ColorPickerFrame.SetColorRGB = function() end
    REALG.ColorPickerFrame.SetColor = function() end
    REALG.ColorPickerFrame.GetColorRGB = function() return 1, 1, 1 end
    REALG.ColorPickerFrame.Hide = function() end
    REALG.ColorPickerFrame.Show = function() end
end

local function installSharedMedia()
    if (noSharedMedia) then return end
    local stub = REALG.LibStub
    if (not stub) then return end
    local registry = { ["Blizzard - Friz Quadrata TT"] = "Fonts\\FRIZQT__.TTF", none = "Interface\\None" }
    local lsm = { MediaType = { FONT = "font", STATUSBAR = "statusbar", BACKGROUND = "background", BORDER = "border" },
        HashTable = function() return registry end,
        List = function() return { "Blizzard - Friz Quadrata TT", "none" } end,
        Fetch = function(_, key) return registry[key] or "Interface\\None" end,
        Register = function() end }
    stub.libs["LibSharedMedia-3.0"] = lsm
    stub.minors["LibSharedMedia-3.0"] = 3
    REALG.LibSharedMedia = lsm
end

-- UIDropDownMenu surface
REALG.UIDropDownMenu_Initialize = function() end
REALG.UIDropDownMenu_AddButton = function() end
REALG.UIDropDownMenu_SetSelectedValue = function() end
REALG.UIDropDownMenu_GetSelectedValue = function() return nil end
REALG.UIDropDownMenu_SetWidth = function() end
REALG.UIDropDownMenu_SetText = function() end
REALG.UIDropDownMenu_EnableDropDown = function() end
REALG.UIDropDownMenu_DisableDropDown = function() end
REALG.UIDropDownMenu_CreateInfo = function() return {} end
REALG.BackdropTemplateMixin = {}
REALG.InterfaceOptions_AddCategory = function() end
REALG.InterfaceOptionsFrame_OpenToCategory = function() end
REALG.InterfaceOptionsFrame_Show = function() end
REALG.Item = nil

--------------------------------------------------------------------------
-- Load + exercise
--------------------------------------------------------------------------
-- LibStub must exist before the optional SharedMedia library can be injected
-- into it, so the libs load first, then SharedMedia, then the rest.
local orderPre = {
    "Libs/LibStub/LibStub.lua",
    "Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua",
    "Libs/LibDetours-1.0/LibDetours-1.0.lua",
    "Libs/LibForeverInspector/LibForeverInspector.lua",
}
local orderPost = {
    "Locale/deDE.lua", "Locale/esES.lua", "Locale/esMX.lua", "Locale/frFR.lua",
    "Locale/itIT.lua", "Locale/koKR.lua", "Locale/ptBR.lua", "Locale/ruRU.lua",
    "Locale/zhCN.lua", "Locale/zhTW.lua", "Locale/enUS.lua",
    "gearscore.lua", "pawn.lua", "textures.lua", "options.lua", "main.lua",
}

local loadFail
local function loadList(list)
    for _, rel in ipairs(list) do
        local ok, err = pcall(function() assert(loadfile(ROOT .. rel))("TacoTip_Forever") end)
        if (not ok) then return rel .. " -> " .. tostring(err) end
    end
    return nil
end
loadFail = loadList(orderPre)
if (not loadFail) then
    installSharedMedia()
    loadFail = loadList(orderPost)
end

local TT = REALG.TacoTip_Forever
local results = {}
local function step(name, fn)
    local ok, err = pcall(fn)
    results[#results + 1] = { name, ok, err }
    if (not ok) then recordErr(name, err) end
end

if (loadFail) then
    STD.io.write(string.format("%-12s LOAD FAIL %s\n", label, loadFail))
    STD.os.exit(1)
end

step("RefreshOptionsUI (builds all 4 pages)", function() TT:RefreshOptionsUI() end)
step("OpenOptionsPanel", function() TT.OpenOptionsPanel() end)
step("GetTooltipFontChoices", function() TT:GetTooltipFontChoices() end)
step("GetTooltipStatusBarTextureChoices", function() TT:GetTooltipStatusBarTextureChoices() end)
step("GetTooltipBackgroundChoices", function() TT:GetTooltipBackgroundChoices() end)
step("GetTooltipBorderChoices", function() TT:GetTooltipBorderChoices() end)
step("InvalidateResolvedMediaCache", function() TT:InvalidateResolvedMediaCache() end)
step("GetResolvedTooltipFont", function() TT:GetResolvedTooltipFont() end)
step("GetResolvedTooltipBorder", function() TT:GetResolvedTooltipBorder() end)
step("GetResolvedTooltipBackground", function() TT:GetResolvedTooltipBackground() end)
step("GetResolvedTooltipStatusBarTexture", function() TT:GetResolvedTooltipStatusBarTexture() end)
step("GetDefaults", function() TT:GetDefaults() end)
step("ApplyConfigDefaults", function() TT:ApplyConfigDefaults(REALG.TacoTipConfig) end)
step("SafeSanitizeConfig", function() TT:SafeSanitizeConfig(REALG.TacoTipConfig) end)
step("ApplyTooltipAppearance(GameTooltip)", function() TT:ApplyTooltipAppearance(REALG.GameTooltip, "player") end)
-- NOTE: TT:InitCharacterFrame / TT:InitInspectFrame are deliberately NOT called
-- directly. They are one-shot initialisers that nil themselves out after running
-- (main.lua:2143, :2261), and the normal refresh path already invokes them, so
-- calling them here would be a harness bug. Their effect is asserted below by
-- checking the globals they create.
step("RefreshCharacterFrame", function() TT:RefreshCharacterFrame() end)
step("SyncTooltipMover", function() TT:SyncTooltipMover() end)
step("GetFormattedSpecializationText", function()
    TT:GetFormattedSpecializationText("WARRIOR", 1, 31, 0, 0, false) end)
step("GetClassIconMarkup", function() TT:GetClassIconMarkup("WARRIOR") end)
step("GetClassColor", function() return TT.GetClassColor("WARRIOR") end)

local fails = 0
for _, r in ipairs(results) do
    if (not r[2]) then
        fails = fails + 1
        STD.io.write(string.format("    FAIL %-42s %s\n", r[1], tostring(r[3])))
    end
end

-- The character/inspect overlays are created by the one-shot initialisers the
-- refresh path triggers. Assert their effect rather than calling them directly.
for _, g in ipairs({ "PersonalGearScore", "PersonalGearScoreText", "PersonalAvgItemLvl",
                     "PersonalAvgItemLvlText", "InspectGearScore", "InspectGearScoreText",
                     "InspectAvgItemLvl", "InspectAvgItemLvlText" }) do
    if (not rawget(REALG, g)) then
        fails = fails + 1
        STD.io.write(string.format("    FAIL character/inspect overlay global missing: %s\n", g))
    end
end

local function flag(s) return s and "on" or "off" end
STD.io.write(string.format("%-12s settings=%-4s color=%-4s lsm=%-4s pipeline=%-4s widgets=%-4d  %s\n",
    label, flag(not noSettings), flag(not noColor), flag(not noSharedMedia),
    flag(usePipeline), #created,
    (fails == 0) and ("ALL " .. #results .. " PASS") or (fails .. "/" .. #results .. " FAILED")))
STD.os.exit(fails == 0 and 0 or 1)
