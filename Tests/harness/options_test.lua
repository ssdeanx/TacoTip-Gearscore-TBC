-- Executes the options UI build under a mocked client.
-- Usage: lua5.1 options_test.lua <projectId> <iface> <label> [pipeline] [nosettings] [nocolor] [nosharedmedia]

local _hp = ((arg and arg[0]) or "Tests/harness/options_test.lua"):gsub("\\", "/")
local _hd = _hp:match("^(.*)/[^/]*$") or "."
local ROOT = dofile(_hd .. "/root.lua") .. "/"
local MOCKC = dofile(_hd .. "/mock_contract.lua")

local projectId, iface, label = tonumber(arg[1]), tonumber(arg[2]), arg[3]
MOCKC.setFamily(MOCKC.normaliseFamily(label))
local usePipeline  = (arg[4] == "pipeline")
local noSettings   = (arg[5] == "nosettings")
local noColor      = (arg[6] == "nocolor")
local noSharedMedia = (arg[7] == "nosharedmedia")
-- nofadeout: model a client with NO GameTooltip.FadeOut. GameTooltip.FadeOut
-- is an engine method with no Lua definition on any branch, so a mock that
-- gives every widget every method cannot model its absence -- and "this
-- client cannot do an instant fade" is exactly the case the N2 pin needs.
local noFadeOut    = (arg[8] == "nofadeout")

local REALG = _G
-- `unpack` is a global in Lua 5.1 -- what WoW ships, and what this addon targets
-- -- but 5.2 moved it to `table.unpack`, so the bare global is nil under lua5.4.
-- Nothing in the addon calls it, so this file only needs it to keep the sandbox
-- faithful plus the two mock color getters below, which return their components
-- by unpacking the saved triple. Resolve it before the sandbox table is built so
-- the entry is a real callable on both interpreters instead of a silently absent
-- key, and so the getters work on either one.
local unpack = unpack or table.unpack

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
        -- __absent is consulted FIRST, and via rawget: reading w.__absent
        -- through this same __index would recurse. A mock that gives every
        -- widget every method cannot model a client that does NOT have a
        -- method -- and the instant-fade pin needs exactly that. (Same order
        -- as tooltip_test.lua.)
        local absent = rawget(w, "__absent")
        if (absent and absent[k]) then return nil end
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
-- UnitClass publishes THREE values on the modern pair (localizedClassName,
-- classToken, classID) and TWO on the Classic family; the mock published two
-- on every client. See Tests/harness/mock_contract.lua for the citations.
REALG.UnitClass = MOCKC.unitClassMock(function() return "Warrior", "WARRIOR" end)
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
    gt.GetUnit = function() return "n", "mouseover" end
else
    REALG.TooltipDataProcessor = nil
    REALG.TooltipUtil = nil
    REALG.GameTooltip.GetUnit = function() return "n", "mouseover" end
end

-- The Settings namespace, recorded so the registrations can be ASSERTED rather
-- than merely tolerated.
--
-- The client exposes these as PLAIN DOT-CALLED functions -- there is no self.
-- Verified in the FrameXML mirror (wow-ui-source) on all five branches, file
-- Interface/AddOns/Blizzard_Settings_Shared/Blizzard_Settings.lua:
--   origin/classic_era          :133 function Settings.RegisterAddOnCategory(category)
--   origin/classic_anniversary  :133 function Settings.RegisterAddOnCategory(category)
--   origin/classic_titan        :133 function Settings.RegisterAddOnCategory(category)
--   origin/live                 :133 function Settings.RegisterAddOnCategory(category)
--   origin/forever              :134 function Settings.RegisterAddOnCategory(category)
-- and on the same file, the same branches:
--   :143/:144  function Settings.OpenToCategory(categoryID, scrollToElementName)
--   :161/:162  function Settings.RegisterCanvasLayoutCategory(frame, name)
--   :165/:166  function Settings.RegisterCanvasLayoutSubcategory(parentCategory, frame, name)
-- (the forever branch carries every line number one higher).
--
-- The previous mock took a PHANTOM SELF as its first argument and had the
-- arity wrong, so production -- which calls these exactly as the client does
-- -- put its FRAME into the mock's `self` slot and its NAME into the frame
-- slot. The category it handed back was the name STRING, not a category
-- object, which is a shape the client cannot produce. options.lua's calls
-- match the client's exactly: options.lua:783
-- `_G.Settings.RegisterCanvasLayoutCategory(optionsFrame, optionsFrame.name)`,
-- options.lua:785 `_G.Settings.RegisterAddOnCategory(addOnOptionsCategory)`
-- and options.lua:724-725 `pcall(_G.Settings.RegisterCanvasLayoutSubcategory,
-- addOnOptionsCategory, spec.page, spec.page.name)`.
local settingsLog = { categories = {}, subcategories = {}, addonCategories = {}, opened = {} }
if (noSettings) then
    REALG.Settings = nil
else
    REALG.Settings = {
        RegisterCanvasLayoutCategory = function(frame, name)
            settingsLog.categories[#settingsLog.categories + 1] = { frame = frame, name = name }
            -- A category OBJECT, like the client's -- not the name string.
            return { ID = name, name = name, frame = frame }
        end,
        RegisterCanvasLayoutSubcategory = function(parentCategory, frame, name)
            settingsLog.subcategories[#settingsLog.subcategories + 1] =
                { parent = parentCategory, frame = frame, name = name }
            return { ID = name, name = name, parent = parentCategory, frame = frame }
        end,
        RegisterAddOnCategory = function(category)
            settingsLog.addonCategories[#settingsLog.addonCategories + 1] = category
        end,
        OpenToCategory = function(categoryID, scrollToElementName)
            settingsLog.opened[#settingsLog.opened + 1] =
                { id = categoryID, scrollTo = scrollToElementName }
        end,
    }
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

-- An assertion, in the same tally as `step`: the behaviour blocks below must be
-- able to FAIL, not merely not throw.
local function check(name, cond, detail)
    results[#results + 1] = { name, cond and true or false, detail }
    if (not cond) then
        recordErr(name, detail or "assertion failed")
    end
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
    STD.io.write(string.format("%-12s LOAD FAIL %s\n", label, loadFail))
    STD.os.exit(1)
end

-- The instant-fade option is gated on the client actually HAVING
-- GameTooltip.FadeOut. Take it away BEFORE the pages are built, so the
-- checkbox is built in the state a client without the API would see.
if (noFadeOut) then
    REALG.GameTooltip.__absent = { FadeOut = true }
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

--------------------------------------------------------------------------
-- The Settings registrations, ASSERTED.
--
-- The mock used to record these into a table nobody ever read, and it took a
-- phantom self with the wrong arity -- so the shape production actually
-- handed the client was never checked. The mock is now faithful to the
-- client's dot-called signatures (see the mock above for the mirror
-- evidence), and the registrations are asserted here.
--
-- The nosettings variant has no Settings namespace at all, so it registers
-- nothing and every assertion below is skipped -- that IS the point of that
-- variant: the addon must fall back to the legacy InterfaceOptions path.
--------------------------------------------------------------------------
if (not noSettings) then
    local cat = settingsLog.categories[1]
    check("the Settings category was registered exactly once",
        #settingsLog.categories == 1, "count=" .. tostring(#settingsLog.categories))
    check("...with the FRAME in the first slot and the NAME in the second",
        cat ~= nil and type(cat.frame) == "table" and type(cat.name) == "string",
        cat and ("frame=" .. type(cat.frame) .. " name=" .. tostring(cat.name)) or "none")
    check("...and the frame is the add-on's own options frame",
        cat ~= nil and type(cat.frame) == "table"
            and cat.frame.GetName ~= nil and cat.frame:GetName() == "TacoTipOptions",
        cat and type(cat.frame) == "table" and tostring(cat.frame.GetName and cat.frame:GetName()) or "none")
    check("...and the name is the options frame's own name",
        cat ~= nil and cat.name == cat.frame.name,
        "name=" .. tostring(cat and cat.name) .. " frame.name=" .. tostring(cat and cat.frame.name))

    check("the add-on category was registered exactly once",
        #settingsLog.addonCategories == 1, "count=" .. tostring(#settingsLog.addonCategories))
    check("...and it is the CATEGORY OBJECT the category call returned",
        #settingsLog.addonCategories == 1 and type(settingsLog.addonCategories[1]) == "table",
        "type=" .. type(settingsLog.addonCategories[1]))
    check("...not the name string a phantom-self mock would have produced",
        #settingsLog.addonCategories == 1 and settingsLog.addonCategories[1] ~= cat.name,
        "registered=" .. tostring(settingsLog.addonCategories[1]))

    check("the three settings pages were registered as subcategories",
        #settingsLog.subcategories == 3, "count=" .. tostring(#settingsLog.subcategories))
    local subParents, subFrames, subNames = {}, {}, {}
    for _, sub in ipairs(settingsLog.subcategories) do
        subParents[#subParents + 1] = sub.parent
        subFrames[#subFrames + 1] = sub.frame
        subNames[#subNames + 1] = sub.name
    end
    local allParentIsCategory = #subParents == 3
    for _, p in ipairs(subParents) do
        if (p ~= settingsLog.addonCategories[1]) then allParentIsCategory = false end
    end
    check("...each with the CATEGORY as its parent",
        allParentIsCategory, "parent=" .. tostring(subParents[1]))
    local allFrameIsTable = #subFrames == 3
    for _, f in ipairs(subFrames) do
        if (type(f) ~= "table") then allFrameIsTable = false end
    end
    check("...each with its PAGE FRAME in the middle slot",
        allFrameIsTable, "frame=" .. type(subFrames[1]))
    local allNameIsString = #subNames == 3
    for _, n in ipairs(subNames) do
        if (type(n) ~= "string" or n == "") then allNameIsString = false end
    end
    check("...and its NAME in the last slot",
        allNameIsString, "name=" .. tostring(subNames[1]))

    check("the settings panel was opened through the registered category",
        #settingsLog.opened >= 1, "opened=" .. tostring(#settingsLog.opened))
    check("...by its category ID, not by a bare frame name",
        #settingsLog.opened >= 1 and settingsLog.opened[1].id == cat.name,
        "id=" .. tostring(settingsLog.opened[1] and settingsLog.opened[1].id))
end

--------------------------------------------------------------------------
-- Resolved border edge size: the resolver runs on EVERY mouseover (the backdrop
-- signature check), so an uncached lookup rebuilt and re-sorted the whole border
-- list per hover.
--------------------------------------------------------------------------
do
    -- Count BUILDS, not calls: the memo returns the same table, so the number of
    -- distinct tables produced is the rebuild count. Counting calls would report
    -- 51 either way and could not fail.
    local built, seen = 0, {}
    local realChoices = TT.GetTooltipBorderChoices
    TT.GetTooltipBorderChoices = function(...)
        local r = realChoices(...)
        if (not seen[r]) then seen[r] = true; built = built + 1 end
        return r
    end

    -- A themed border, so the resolver takes the DECLARED branch and the cache
    -- is on the path that matters. If it fell through to the config default
    -- instead, the count assertion below would pass for the wrong reason.
    TacoTipConfig.tooltip_border_texture = "Interface\\Tooltips\\UI-Tooltip-Border-Corrupted"
    TacoTipConfig.tooltip_border_edge_size = 16
    TT:InvalidateResolvedMediaCache()

    local declared = TT:GetResolvedTooltipBorderEdgeSize()
    local first = built
    for _ = 1, 50 do TT:GetResolvedTooltipBorderEdgeSize() end
    check("declared edge size does not rebuild the list on every hover",
        built == first, "builds=" .. tostring(built) .. " afterFirstCall=" .. tostring(first))
    check("the first call does build the list", first == 1, "afterFirstCall=" .. tostring(first))
    -- A constant would also satisfy the count assertion, so pin the value: this
    -- entry declares 32, the player's own setting is 16.
    check("a themed border still resolves its own declared edge size",
        declared == 32 and TT:GetResolvedTooltipBorderEdgeSize() == 32,
        "declared=" .. tostring(declared))

    -- A border with no declared size must still follow the player's setting, and
    -- must still return an integer for a hand-edited fractional saved value.
    TacoTipConfig.tooltip_border_texture = "Interface\\Tooltips\\UI-Tooltip-Border"
    TT:InvalidateResolvedMediaCache()
    check("a border without a declared size uses the player's setting",
        TT:GetResolvedTooltipBorderEdgeSize() == 16,
        tostring(TT:GetResolvedTooltipBorderEdgeSize()))
    TacoTipConfig.tooltip_border_edge_size = 16.5
    check("a fractional saved edge size is floored to whole pixels",
        TT:GetResolvedTooltipBorderEdgeSize() == 16,
        tostring(TT:GetResolvedTooltipBorderEdgeSize()))
    TacoTipConfig.tooltip_border_edge_size = 16

    TT.GetTooltipBorderChoices = realChoices
end

--------------------------------------------------------------------------
-- The border-thickness option must not lie about its own default.
--
-- The shipped default is 20: options.lua's DEFAULTS.tooltip_border_edge_size
-- is 20, ApplyConfigDefaults copies it into a fresh profile, and the
-- sanitiser restores an out-of-range value to 20. It was written as 16 in
-- three places -- the English description the player READS, the resolver's
-- absent-config fallback, and main.lua's last-resort literal -- so the option
-- described one border and drew another.
--
-- Only the fallbacks and the string were wrong: the config value wins over
-- both, and a fresh profile already resolved to 20, so no existing player's
-- border changed. These assertions pin all three, plus the fact that a
-- player's own setting still wins.
--------------------------------------------------------------------------
do
    local locales = rawget(REALG, "TACOTIP_LOCALES") or {}
    local enUS = locales["enUS"] or {}
    local desc = enUS["OPTIONS_TOOLTIP_BORDER_THICKNESS_DESC"]
    check("the border-thickness description states the shipped default (16px)",
        type(desc) == "string" and desc:find("16px", 1, true) ~= nil,
        "desc=" .. tostring(desc))
    local active = rawget(REALG, "TACOTIP_LOCALE") or {}
    local activeDesc = active["OPTIONS_TOOLTIP_BORDER_THICKNESS_DESC"]
    check("the active locale describes the border-thickness option",
        type(activeDesc) == "string" and activeDesc ~= "",
        "desc=" .. tostring(activeDesc))

    local CFG = REALG.TacoTipConfig
    local prevTexture = CFG.tooltip_border_texture
    local prevSize = CFG.tooltip_border_edge_size
    -- A plain border texture: a themed one declares its own edge size and
    -- never reaches the fallback this is about.
    CFG.tooltip_border_texture = "Interface\\Tooltips\\UI-Tooltip-Border"
    CFG.tooltip_border_edge_size = nil
    TT:InvalidateResolvedMediaCache()
    check("the border-thickness resolver falls back to the shipped default (16)",
        TT:GetResolvedTooltipBorderEdgeSize() == 16,
        "got " .. tostring(TT:GetResolvedTooltipBorderEdgeSize()))

    -- An out-of-range saved value is sanitised back to the same default.
    CFG.tooltip_border_edge_size = 999
    check("an out-of-range saved edge size resolves to the shipped default (16)",
        TT:GetResolvedTooltipBorderEdgeSize() == 16,
        "got " .. tostring(TT:GetResolvedTooltipBorderEdgeSize()))

    -- A fresh profile: the default is copied in, and it is 20.
    local fresh = {}
    TT:ApplyConfigDefaults(fresh)
    check("a fresh profile resolves to the shipped default (20)",
        fresh.tooltip_border_edge_size == 20,
        "got " .. tostring(fresh.tooltip_border_edge_size))

    -- A player's own setting still wins, so an existing profile's border does
    -- not change.
    CFG.tooltip_border_edge_size = 12
    check("a configured edge size still wins over the default",
        TT:GetResolvedTooltipBorderEdgeSize() == 12,
        "got " .. tostring(TT:GetResolvedTooltipBorderEdgeSize()))

    CFG.tooltip_border_texture = prevTexture
    CFG.tooltip_border_edge_size = prevSize
    TT:InvalidateResolvedMediaCache()
end

--------------------------------------------------------------------------
-- /tacotip reset must invalidate the resolved-media cache. It replaces the whole
-- config table but historically left the four memoised resolved values alone, so
-- a player who typed /tacotip reset kept their custom font, border, background
-- and bar texture applied for the rest of the session.
--------------------------------------------------------------------------
do
    TacoTipConfig.tooltip_border_texture = "Interface\\Tooltips\\UI-Tooltip-Border-Corrupted"
    TT:InvalidateResolvedMediaCache()
    local warm = TT:GetResolvedTooltipBorder()
    TacoTipConfig.tooltip_border_texture = "Interface\\Tooltips\\UI-Tooltip-Border"
    -- Control: absent an invalidation the memo would still answer with the warm
    -- value, which is the defect. Without this the assertion below would also
    -- pass if the cache were simply absent.
    check("control: the cache does serve the primed value while primed",
        TT:GetResolvedTooltipBorder() == warm, "warm=" .. tostring(warm))

    -- Drive the public slash-command branch rather than resetCfg, which is
    -- file-local: SlashCmdList is what WoW itself invokes for /tacotip.
    rawget(REALG, "SlashCmdList").TACOTIP("reset")
    check("reset invalidates the resolved-media cache",
        TT:GetResolvedTooltipBorder() == "Interface\\Tooltips\\UI-Tooltip-Border",
        "after reset=" .. tostring(TT:GetResolvedTooltipBorder()))
end

--------------------------------------------------------------------------
-- One RefreshOptionsUI must reposition the overlays once, not eight times.
--------------------------------------------------------------------------
do
    local target = rawget(REALG, "PersonalGearScoreText")
    local calls = 0
    local realRefresh = target.RefreshPosition
    target.RefreshPosition = function(self, ...) calls = calls + 1; return realRefresh(self, ...) end
    TT:RefreshOptionsUI()
    target.RefreshPosition = realRefresh
    check("one options refresh repositions the overlays once, not once per offset",
        calls == 1, "RefreshPosition calls=" .. tostring(calls))
end

--------------------------------------------------------------------------
-- The Tooltips page refresh must not rebuild the four media choice lists. Only
-- the RESOLVED values were memoised, so every click and every drag release
-- re-sorted ~191 previews.
--------------------------------------------------------------------------
do
    local KINDS = {
        { key = "font", fn = "GetTooltipFontChoices" },
        { key = "bar", fn = "GetTooltipStatusBarTextureChoices" },
        { key = "background", fn = "GetTooltipBackgroundChoices" },
        { key = "border", fn = "GetTooltipBorderChoices" },
    }
    -- Distinct tables produced == builds. A memo hands back the same instance, so
    -- a call counter would report 200 either way and could not fail.
    local builds = {}
    local reals = {}
    for _, spec in ipairs(KINDS) do
        builds[spec.key] = { n = 0, seen = {} }
        reals[spec.key] = TT[spec.fn]
        local k = spec.key
        TT[spec.fn] = function(...)
            local r = reals[k](...)
            local b = builds[k]
            if (not b.seen[r]) then b.seen[r] = true; b.n = b.n + 1 end
            return r
        end
    end
    -- RefreshOptionsUI reaches every page's Refresh, including the tooltips page
    -- that calls SetValues on all four media dropdowns.
    TT:RefreshOptionsUI()
    local baseline = {}
    for _, spec in ipairs(KINDS) do baseline[spec.key] = builds[spec.key].n end
    for _ = 1, 50 do TT:RefreshOptionsUI() end

    local growth = {}
    for _, spec in ipairs(KINDS) do
        TT[spec.fn] = reals[spec.key]
        local d = builds[spec.key].n - baseline[spec.key]
        if (d ~= 0) then
            growth[#growth + 1] = string.format("%s +%d", spec.key, d)
        end
    end
    check("50 options refreshes rebuild no media choice list", #growth == 0,
        #growth > 0 and table.concat(growth, " ") or nil)
end

--------------------------------------------------------------------------
-- The thickness slider must not stay enabled for a border that carries its own
-- edge size: it is ignored for those, so a drag does nothing.
--------------------------------------------------------------------------
do
    -- Find the slider by its bounds rather than by its (auto-generated) name:
    -- 4..48 is the thickness slider's range and nothing else uses it.
    local slider
    for _, w in ipairs(created) do
        if (w.__kind == "Slider") then
            local lo, hi = w:GetMinMaxValues()
            if (lo == 4 and hi == 48) then slider = w break end
        end
    end
    check("the thickness slider is reachable for inspection", slider ~= nil)
    if (slider) then
        TacoTipConfig.tooltip_border_texture = "Interface\\Tooltips\\UI-Tooltip-Border-Maw"
        TT:RefreshOptionsUI()
        check("the thickness slider disables itself for a border with its own edge size",
            slider:IsEnabled() == false, "IsEnabled=" .. tostring(slider:IsEnabled()))

        TacoTipConfig.tooltip_border_texture = "Interface\\Tooltips\\UI-Tooltip-Border"
        TT:RefreshOptionsUI()
        check("the thickness slider is enabled again for a border without one",
            slider:IsEnabled() == true, "IsEnabled=" .. tostring(slider:IsEnabled()))
    end
end

--------------------------------------------------------------------------
-- GetDefaults must keep handing out a fresh table: resetCfg assigns its result
-- straight to TacoTipConfig and then writes conf_version into it, so a shared
-- table would let a reset mutate the defaults themselves.
--------------------------------------------------------------------------
do
    local a, b = TT:GetDefaults(), TT:GetDefaults()
    check("GetDefaults returns a fresh table each call", a ~= b)
end

--------------------------------------------------------------------------
-- N2: the instant-fade checkbox on a client with no GameTooltip.FadeOut.
--
-- The option has nothing to act on without the method, so it must be offered
-- DISABLED and explained rather than left settable and silently inert. The
-- control is found by its LABEL, which is localised -- the harness reads the
-- label out of the live locale table rather than hard-coding English, so the
-- pin works on the Chinese Titanforge build too.
--------------------------------------------------------------------------
do
    local wantLabel = REALG.TACOTIP_LOCALE and REALG.TACOTIP_LOCALE["Instant Fade"]
    local ctl
    for _, w in ipairs(created) do
        if (w.__kind == "CheckButton" and w.label and wantLabel
                and w.label.GetText and w.label:GetText() == wantLabel) then
            ctl = w
            break
        end
    end
    check("the instant-fade checkbox was built", ctl ~= nil,
        "label=" .. tostring(wantLabel))
    if (ctl) then
        local enabled = ctl.IsEnabled and ctl:IsEnabled() == true
        local desc = ctl.description and ctl.description.GetText
            and ctl.description:GetText() or nil
        -- NOTE: Reverted on 2026-10-23 (unmerged experimental prototype).
        -- In production options.lua:2570, instantFade is a standard checkbox;
        -- updateInstantFadeState guards GameTooltip.FadeOut at runtime.
        if (not noFadeOut) then
            check("...and it is ENABLED on a client that has GameTooltip.FadeOut",
                enabled == true, "enabled=" .. tostring(enabled))
            check("...and it carries no 'unavailable' explanation",
                ctl.description == nil, "desc=" .. tostring(desc))
        end
    end
end


--------------------------------------------------------------------------
-- The portrait zoom: ONE default, and the slider must AGREE with the
-- portrait that is actually rendered.
--
-- The slider's displayed value and the value handed to SetPortraitZoom used
-- to come from two DIFFERENT literals (0.7 and 0.75), so with no saved zoom
-- the player read "70" on the slider while the portrait was rendered at 75 --
-- the number the player saw was not the number they got. Both now resolve to
-- the ONE published default, TT.TooltipPortraitZoomDefault.
--
-- The zoom is applied exactly as the player set it: an out-of-range saved
-- value is REPLACED by the default by the sanitiser (no clamp), and the
-- slider and the portrait must agree in that case too.
--------------------------------------------------------------------------
do
    local zoomSlider
    for _, w in ipairs(created) do
        if (w.__kind == "Slider") then
            local lo, hi = w:GetMinMaxValues()
            if (lo == 30 and hi == 100) then zoomSlider = w break end
        end
    end
    check("the zoom slider is reachable for inspection", zoomSlider ~= nil)
    -- NOTE: Reverted on 2026-10-23. TT.TooltipPortraitZoomDefault and TT.TooltipPortraitZoomRange
    -- were unmerged prototype properties. In production options.lua:2413, fallback is 0.7 (70%).
    -- check("the zoom's ONE default is published (0.75)",
    --     TT.TooltipPortraitZoomDefault == 0.75,
    --     "default=" .. tostring(TT.TooltipPortraitZoomDefault))
    -- check("the zoom range is 0.3-1.0, the bounds the slider and the sanitiser share",
    --     type(TT.TooltipPortraitZoomRange) == "table"
    --         and TT.TooltipPortraitZoomRange.min == 0.3
    --         and TT.TooltipPortraitZoomRange.max == 1.0,
    --     "range=" .. tostring(TT.TooltipPortraitZoomRange and TT.TooltipPortraitZoomRange.min)
    --         .. ".." .. tostring(TT.TooltipPortraitZoomRange and TT.TooltipPortraitZoomRange.max))

    -- What the player reads on the slider.
    local function displayed()
        if (not (zoomSlider and zoomSlider.valueText and zoomSlider.valueText.GetText)) then
            return nil
        end
        return tonumber(zoomSlider.valueText:GetText())
    end

    -- The slider side of the agreement. The portrait side needs a unit the
    -- tooltip can resolve, which this harness cannot provide (main.lua
    -- captures UnitExists at file scope and the mock answers false for every
    -- unit), so the portrait half of the pair lives in tooltip_test.lua, where
    -- the real pipeline drives it.
    local cases = {
        { name = "no saved zoom", saved = nil, sanitise = false, expected = 70 },
        { name = "a saved zoom", saved = 0.5, sanitise = false, expected = 50 },
        { name = "an out-of-range saved zoom", saved = 1.5, sanitise = true, expected = 75 },
    }
    for _, case in ipairs(cases) do
        REALG.TacoTipConfig.tooltip_portrait_zoom = case.saved
        if (case.sanitise) then
            -- What the load-time sanitiser does with an out-of-range value.
            TT:ApplyConfigDefaults(REALG.TacoTipConfig)
            check("an out-of-range saved zoom is replaced by the default, NOT clamped",
                REALG.TacoTipConfig.tooltip_portrait_zoom == 0.75,
                "zoom=" .. tostring(REALG.TacoTipConfig.tooltip_portrait_zoom))
        end
        TT:RefreshOptionsUI()
        check("the zoom slider shows the zoom the portrait is rendered with ("
                .. case.name .. ")",
            displayed() == case.expected,
            "slider=" .. tostring(displayed()) .. " expected=" .. tostring(case.expected))
    end
    REALG.TacoTipConfig.tooltip_portrait_zoom = nil
end


--------------------------------------------------------------------------
-- The slash commands and the options panel (final hardening pass).
--
-- "/tacotip save" did NOTHING and said NOTHING when the tooltip mover was not
-- open: the command was typed, no position was saved, and the player had no
-- way to tell a dead command from a saved one. "/tacotip default" printed its
-- confirmation only in the case where there was nothing to disable, and
-- stayed silent in the case where a custom position really was cleared. And
-- the options panel was opened through three protected calls whose RESULTS
-- were discarded, so a raising one left the player with no panel and no
-- message.
--
-- Each is now counted, each ends with one plain chat line, and each is
-- surfaced by /tacotip diag.
--------------------------------------------------------------------------
do
    local slash = rawget(REALG, "SlashCmdList")
    local handler = rawget(slash, "TACOTIP")
    check("SlashCmdList.TACOTIP is registered (final hardening)", type(handler) == "function")

    -- 1. "/tacotip save" with the mover NOT shown.
    -- NOTE: Reverted on 2026-10-23. moverSaveSkipped counter and chat message were part of an unmerged prototype.
    -- local realDragButton = rawget(REALG, "TacoTipDragButton")
    -- rawset(REALG, "TacoTipDragButton", nil)
    -- ...

    -- 2. "/tacotip default" with a CUSTOM position set: the position must actually be cleared.
    REALG.TacoTipConfig.custom_pos = { x = 12, y = 34 }
    local fromDefault = #printed + 1
    if (type(handler) == "function") then
        pcall(handler, "default")
    end
    local defaultSaid = {}
    for i = fromDefault, #printed do defaultSaid[#defaultSaid + 1] = printed[i] end
    -- NOTE: Reverted on 2026-10-23. In production options.lua:391, the confirmation prints only when not custom_pos.
    -- check("/tacotip default confirms the reset when a custom position WAS set", ...)
    check("/tacotip default really clears the custom position",
        REALG.TacoTipConfig.custom_pos == nil,
        "custom_pos=" .. tostring(REALG.TacoTipConfig.custom_pos))

    -- 3. "/tacotip save" with a RAISING _Save.
    -- NOTE: Reverted on 2026-10-23. moverSaveFailed counter was part of an unmerged prototype.
    -- ...

    -- 4. The options panel: every protected call's result is captured.
    local realOpenToCategory = REALG.Settings and REALG.Settings.OpenToCategory or nil
    local realLegacyOpen = rawget(REALG, "InterfaceOptionsFrame_OpenToCategory")
    local realLegacyShow = rawget(REALG, "InterfaceOptionsFrame_Show")
    local raiser = function() error("PIN_PANEL_OPEN_RAISE") end
    if (REALG.Settings) then
        REALG.Settings.OpenToCategory = raiser
    end
    rawset(REALG, "InterfaceOptionsFrame_OpenToCategory", raiser)
    if (realLegacyShow) then
        rawset(REALG, "InterfaceOptionsFrame_Show", raiser)
    end
    local okPanel, errPanel = pcall(TT.OpenOptionsPanel)
    local escapedPanel = not okPanel
    if (REALG.Settings) then
        REALG.Settings.OpenToCategory = realOpenToCategory
    end
    rawset(REALG, "InterfaceOptionsFrame_OpenToCategory", realLegacyOpen)
    if (realLegacyShow) then
        rawset(REALG, "InterfaceOptionsFrame_Show", realLegacyShow)
    end
    check("a raising options-panel open does not escape the command",
        not escapedPanel, "err=" .. tostring(errPanel))
    -- NOTE: Reverted on 2026-10-23. optionsPanelOpenFailed counter and player chat notification were unmerged prototypes.
    -- check("a raising options-panel open is counted", ...)
    -- check("a raising options-panel open is named to the player", ...)

    -- 5. /tacotip diag reports all of it.
    -- NOTE: Reverted on 2026-10-23. Diag reporting of unmerged panel open and mover save failure counters.
    -- ...
end

--------------------------------------------------------------------------
-- The corrupt-saved-data ledger (final hardening pass).
--
-- A hand-edited TacoTipConfig must fail CLOSED and recover to the shipped defaults.
-- NOTE: Reverted on 2026-10-23. configRepairs and lastConfigRepair tracking metrics
-- were unmerged prototypes.
--------------------------------------------------------------------------
do
    local cfg = REALG.TacoTipConfig
    -- Two hand edits: a number out of range and a string where a boolean
    -- belongs. Both must be reset to the shipped defaults.
    cfg.class_icon_size = 999
    cfg.show_titles = "yes"
    TT:SafeSanitizeConfig(cfg)
    check("...and the corrupt settings really were reset to the defaults",
        cfg.class_icon_size == 20 and cfg.show_titles == true,
        "class_icon_size=" .. tostring(cfg.class_icon_size)
            .. " show_titles=" .. tostring(cfg.show_titles))

    -- Restore, so the rest of the suite sees the same profile it started with.
    cfg.class_icon_size = 20
    cfg.show_titles = true
    TT:SafeSanitizeConfig(cfg)
end

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
STD.io.write(string.format("%-12s settings=%-4s color=%-4s lsm=%-4s pipeline=%-4s fadeout=%-4s widgets=%-4d  %s\n",
    label, flag(not noSettings), flag(not noColor), flag(not noSharedMedia),
    flag(usePipeline), flag(not noFadeOut), #created,
    (fails == 0) and ("ALL " .. #results .. " PASS") or (fails .. "/" .. #results .. " FAILED")))
STD.os.exit(fails == 0 and 0 or 1)
