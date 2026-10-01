-- Executes the main.lua tooltip pipeline under a mocked client and asserts the
-- enhancement actually produces lines.
-- Usage: lua5.1 tooltip_test.lua <projectId> <iface> <label> [pipeline]

local ROOT = (os.getenv("TACOTIP_TEST_ROOT") or ".") .. "/"

local projectId, iface, label = tonumber(arg[1]), tonumber(arg[2]), arg[3]
local usePipeline = (arg[4] == "pipeline")
local DEBUG = (arg[5] == "debug")

local REALG = _G
local STD = { os=os, string=string, pairs=pairs, ipairs=ipairs, type=type, pcall=pcall,
    tonumber=tonumber, tostring=tostring, select=select, rawget=rawget, rawset=rawset,
    setmetatable=setmetatable, getmetatable=getmetatable, unpack=unpack, assert=assert,
    error=error, math=math, table=table, loadfile=loadfile, print=print, io=io,
    -- WoW's Lua provides these; main.lua's safeCall depends on the extended
    -- xpcall that accepts the arguments after the handler. It MUST route the
    -- error to the handler -- a mock that swallows it makes every assertion in
    -- this file meaningless.
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
    next=next, rawequal=rawequal, rawlen=function(t) return #t end }

-- WoW extends the standard `table` library with wipe(); it is present on all
-- five supported clients (28-37 Blizzard call sites each). Plain Lua 5.1 has no
-- table.wipe, so without this every main.lua path that pools buffers dies at the
-- first table.wipe -- and the failure looks like a silent early return.
local baseTable = table
local baseNext = next
STD.table = setmetatable({
    wipe = baseTable.wipe or function(t)
        for k in baseNext, t do t[k] = nil end
        return t
    end,
}, { __index = baseTable })

local WM = {}
for _, m in ipairs({
    "AddLine","AddDoubleLine","ClearLines","ClearAllPoints","CreateFontString",
    "CreateTexture","Enable","Disable","EnableMouse","EnableMouseWheel","GetAlpha",
    "GetBottom","GetCenter","GetChecked","GetEffectiveScale","GetFrameLevel",
    "GetFrameStrata","GetHeight","GetItem","GetLeft","GetLeftLine","GetMinimumWidth",
    "GetName","GetNumLines","GetObjectType","GetParent","GetRight","GetRightLine",
    "GetSize","GetStringHeight","GetText","GetUnit","GetVerticalScroll",
    "GetVerticalScrollRange","GetWidth","Hide","HookScript","IsEnabled","IsObjectType",
    "IsShown","IsUnit","NumLines","RegisterEvent","RegisterForClicks","RegisterForDrag",
    "SetAlpha","SetBackdrop","SetBackdropBorderColor","SetBackdropColor","SetChecked",
    "SetClampedToScreen","SetClampRectInsets","SetColor","SetColorRGB","SetColorTexture",
    "SetDesaturated","SetDisabled","SetDrawLayer","SetEnabled","SetFont","SetFontObject",
    "SetFrameLevel","SetFrameStrata","SetHeight","SetHitRectInsets","SetJustifyH",
    "SetJustifyV","SetMaxLetters","SetMinMaxValues","SetMinimumWidth","SetMovable",
    "SetNonSpaceWrap","SetNormalTexture","SetObeyStepOnDrag","SetOwner","SetPadding",
    "SetParent","SetPoint","SetPortraitTexture","SetPortraitZoom","SetScrollChild",
    "SetScript","SetShadowColor","SetShadowOffset","SetShown","SetSize","SetStatusBarColor",
    "SetStatusBarTexture","SetTexCoord","SetText","SetTextColor","SetTexture","SetUnit",
    "SetUserPlaced","SetValue","SetValueStep","SetVerticalScroll","SetWidth","SetWordWrap",
    "Show","StartMoving","StopMovingOrSizing","UnregisterEvent","UpdateScrollChildRect",
    "UpdateTooltip","FadeOut","GetAnchorType","IsEquippedItem","IsOwned","GetOwner",
    "GetSpell","SetItem","SetPlayer","ClearModel","SetModelScale","SetCamera","SetPosition",
    "SetFacing","Refresh","GetScale","RegisterUnitEvent","GetNumPoints","SetID","GetID",
    "SetToplevel","SetClampedToScreen","ClearPadding","GetMinMaxValues","GetValue",
}) do WM[m] = true end

-- item data the mocked C_Item reports
local ITEM = {
    { link = "item:12345", name = "Test Helm", quality = 4, ilvl = 88, equipLoc = "INVTYPE_HEAD" },
}

local function makeWidget(kind, name, parent, template, depth)
    depth = depth or 0
    local w = { __kind = kind, __name = name, __parent = parent, __text = nil, __shown = true }
    -- Scripts the frame declares. Per-family tooltip sets are applied later; this
    -- is the generic widget baseline. Must be initialised here rather than lazily
    -- inside HookScript, because an empty table is truthy and would defeat it.
    w.__lines, w.__hooks, w.__events = {}, {}, {}
    w.__scripts = { OnLoad = true, OnShow = true, OnHide = true, OnEvent = true,
        OnUpdate = true, OnSizeChanged = true, OnEnter = true, OnLeave = true }
    local MT = {}
    MT.__index = function(t, k)
        -- __absent is consulted first, and via rawget: reading w.__absent through
        -- this same __index would recurse. Without this check the catch-all WM
        -- table below would hand back a frame-level method that the client does
        -- not have on a Region, which is the exact bug being modelled.
        local absent = rawget(w, "__absent")
        if (absent and absent[k]) then return nil end
        local f = rawget(w, k)
        if f then return f end
        if (WM[k]) then return function() return nil end end
        return nil
    end
    w.GetName = function() return name end
    w.GetParent = function() return parent end
    w.GetObjectType = function() return kind end
    w.SetScript = function(_, s, fn) w.__scripts[s] = fn end
    w.GetScript = function(_, s) return w.__scripts[s] end
    -- Per-family script sets. Retail / WoW Forever tooltips do NOT declare
    -- OnTooltipSetUnit, OnTooltipSetItem or OnTooltipSetSpell; the Classic
    -- tooltips do. HookScript raises "bad argument #2 to 'HookScript'" for a
    -- script the frame does not declare, so a permissive mock hides the abort.
    w.__scripts.OnTooltipCleared = true
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
    -- Anchor state is tracked for real. The anchor hook is idempotent by reading
    -- the current anchor back with GetNumPoints/GetPoint, so a mock with no-op
    -- anchors would make every call look "changed" and could never observe the
    -- skip.
    w.__points = {}
    w.__setPointCalls = 0
    w.SetPoint = function(_, p, rel, rp, ox, oy)
        w.__setPointCalls = (w.__setPointCalls or 0) + 1
        -- The real SetPoint resolves a frame argument to its NAME (and an
        -- unnamed frame to nil); GetPoint returns that name. Storing the raw
        -- argument would not match the engine's behaviour and would make the
        -- idempotence check untestable.
        local relName = rel
        if (type(rel) == "table" or type(rel) == "userdata") then
            relName = (rel.GetName and rel:GetName()) or nil
        end
        w.__points[#w.__points + 1] = { p, relName, rp, ox or 0, oy or 0 } end
    w.ClearAllPoints = function() w.__points = {} end
    w.GetNumPoints = function() return #w.__points end
    w.GetPoint = function(_, i)
        local q = w.__points[i or 1]
        if (not q) then return nil end
        return q[1], q[2], q[3], q[4], q[5]
    end
    w.SetAllPoints = function() w.__points = {} end
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

    -- Frame level and frame strata are FRAME methods. On Retail and WoW Forever a
    -- Texture is a Region, not a Frame, so these do not exist on it -- verified in
    -- game, where GetFrameLevel raised "attempt to call a nil value" on the
    -- specialisation-icon texture while SetSize/SetPoint on the adjacent lines
    -- worked fine. The mock used to hand every widget every method, which is why
    -- that shipped: a mock that is more permissive than the client cannot see the
    -- bug. Only the frame-level pair is removed, because that is the split the
    -- client actually demonstrated; a wider speculative removal would be
    -- unverified and would only manufacture false failures.
    w.__absent = {}
    if (kind == "Texture" or kind == "FontString") then
        for _, m in ipairs({ "SetFrameLevel", "GetFrameLevel",
            "SetFrameStrata", "GetFrameStrata" }) do
            w[m] = nil
            w.__absent[m] = true
        end
    end
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
    w.SetHighlightTexture = function() end
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
    w.GetStringHeight = function() return 12 end
    w.SetVertexColor = function() end
    w.SetTexture = function(_, t)
        w.__texture = t
    end
    w.GetTexture = function() return 1 end
    w.SetColorTexture = function() end
    w.SetTexCoord = function() end
    w.SetDesaturated = function() end
    w.SetDrawLayer = function() end
    w.SetStatusBarTexture = function() end
    w.SetStatusBarColor = function() end
    w.SetMinMaxValues = function(_, a, b) w.__min, w.__max = a, b end
    w.GetMinMaxValues = function() return w.__min or 0, w.__max or 0 end
    w.SetValue = function(_, v) w.__value = v end
    w.GetValue = function() return w.__value or 0 end
    w.SetValueStep = function() end
    w.SetValueSilently = function() end
    w.SetObeyStepOnDrag = function() end
    w.SetChecked = function(_, v) w.__checked = v and true or false end
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
    w.SetScrollChild = function(_, c) w.__scrollChild = c end

    -- GameTooltip line pool
    w.ClearLines = function() w.__lines = {} end
    w.NumLines = function() return #w.__lines end
    w.AddLine = function(_, txt, r, g, b)
        ADDLINE_CALLS = (ADDLINE_CALLS or 0) + 1
        w.__lines[#w.__lines + 1] = { left = txt, r = r, g = g, b = b }
    end
    w.AddDoubleLine = function(_, l, rt)
        ADDLINE_CALLS = (ADDLINE_CALLS or 0) + 1
        w.__lines[#w.__lines + 1] = { left = l, right = rt }
    end
    w.GetLeftLine = function(_, i)
        local e = w.__lines[i]
        if (not e) then return nil end
        local fs = e.__fs
        if (not fs) then
            fs = makeWidget("FontString", (name or "TT") .. "TextLeft" .. i, w, nil, depth + 1)
            fs.__text = e.left
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
            e.__fsr = fs
        end
        return fs
    end
    w.GetItem = function() return "n", ITEM[1].link end
    w.GetSpell = function() return "n", 1 end
    w.IsUnit = function(_, u) return w.__unit == u end
    w.GetMinimumWidth = function() return 0 end
    w.SetMinimumWidth = function() end
    w.SetClampRectInsets = function() end
    w.GetAnchorType = function() return 1 end
    w.SetBackdrop = function() end

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
        for _, sfx in ipairs({ "Text", "Low", "High", "Middle", "Left", "Right" }) do
            if (not rawget(REALG, name .. sfx)) then
                rawset(REALG, name .. sfx, makeWidget("FontString", name .. sfx, w, nil, depth + 1))
            end
        end
    end
    return setmetatable(w, MT)
end

--------------------------------------------------------------------------
for k in STD.pairs(REALG) do REALG[k] = nil end
for k, v in STD.pairs(STD) do REALG[k] = v end
REALG._G = REALG
REALG.time = STD.os.time
REALG.print = function() end
REALG.geterrorhandler = function() return function(e)
    ERRORS[#ERRORS + 1] = tostring(e) end end
ERRORS = {}
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
    return makeWidget(kind or "Frame", name, parent, template) end
REALG.GetLocale = function() return "enUS" end
REALG.GetCVar = function() return "" end
REALG.SetCVar = function() end
REALG.InCombatLockdown = function() return false end
REALG.LoadAddOn = function() return true end
-- Real hooksecurefunc. It was a no-op here, which is the blind spot that let the
-- tooltip anchor hook go untested: nothing installed it, so nothing could call
-- it, so the fact that it re-anchored on every single
-- GameTooltip_SetDefaultAnchor call was invisible. Installs are recorded so a
-- test can drive the hooked function the way the game would.
local SECURE_HOOKS = {}
-- Present on all five clients (Blizzard_SharedXML is not LoadOnDemand). The
-- addon guards the hook on its existence, so the mock must provide it or the
-- hook is never installed and cannot be tested at all.
REALG.GameTooltip_SetDefaultAnchor = function() end

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
REALG.print = function(s) STD.io.write(tostring(s) .. "\n") end
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
    if k == "Title" then return "TacoTip Forever" end end, IsAddOnLoaded = function() return false end }
REALG.C_Item = {}
REALG.C_PlayerInfo = {}
REALG.C_Map = {}
REALG.C_SpecializationInfo = {}
for _, f in ipairs({ "GameFontNormal", "GameFontHighlight", "GameFontNormalSmall",
    "GameFontHighlightSmall", "GameFontDisable", "GameFontDisableSmall",
    "GameFontNormalLarge", "NumberFontNormal", "ChatFontNormal" }) do REALG[f] = f end
REALG.NORMAL_FONT_COLOR = { r = 1, g = 1, b = 1 }
REALG.GRAY_FONT_COLOR = { r = .5, g = .5, b = .5 }
REALG.HIGHLIGHT_FONT_COLOR = { r = 1, g = .82, b = 0 }
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

-- unit model
local UNITS = {
    player = { guid = "Player-1-00000001", name = "Testplayer", level = 60, race = "Human",
               class = "WARRIOR", isPlayer = true, pvp = false },
    mouseover = { guid = "Player-2-00000002", name = "Enemyplayer", level = 59, race = "Orc",
               class = "MAGE", isPlayer = true, pvp = true },
    target = { guid = "Creature-3-00000003", name = "Hated Squirrel", level = 42, race = "Beast",
               class = nil, isPlayer = false, pvp = false },
}
local currentUnit = "player"
REALG.UnitExists = function(u) return UNITS[u] ~= nil end
REALG.UnitGUID = function(u) return UNITS[u] and UNITS[u].guid or nil end
REALG.UnitName = function(u) return UNITS[u] and UNITS[u].name or nil end
REALG.UnitLevel = function(u) return UNITS[u] and UNITS[u].level or 1 end
REALG.UnitRace = function(u) return UNITS[u] and UNITS[u].race or "" end
REALG.UnitClass = function(u)
    local c = UNITS[u]
    if (not c or not c.class) then return nil, nil end
    return c.class, c.class end
REALG.UnitIsPlayer = function(u) return UNITS[u] and UNITS[u].isPlayer or false end
REALG.UnitIsUnit = function(a, b) return a == b end
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
REALG.GetPlayerInfoByGUID = function() return true, "Warrior" end
REALG.GetInventoryItemLink = function(_, slot)
    if (slot == 16) then return ITEM[1].link end
    return nil end
REALG.C_Item.GetInventoryItemLink = REALG.GetInventoryItemLink
REALG.GetItemInfo = function(link)
    for _, it in ipairs(ITEM) do
        if (it.link == link) then
            return it.name, it.link, it.quality, it.ilvl, 1, "Armor", "Cloth", 1,
                it.equipLoc, "icon", 0
        end
    end
    return nil end
REALG.C_Item.GetItemInfo = REALG.GetItemInfo
REALG.GetItemInfoInstant = function() return 12345 end
REALG.C_Item.IsEquippableItem = function() return true end
REALG.IsEquippableItem = REALG.C_Item.IsEquippableItem
REALG.C_Item.RequestLoadItemDataByID = function() end
REALG.C_Item.ContinueWithCancelOnItemLoad = function(_, fn) return function() end end
REALG.C_Item.GetItemLinkByID = function() return ITEM[1].link end
REALG.C_Item.GetItemLinkByGUID = function() return nil end
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
-- Realistic Warrior specialization model, mirroring the Classic talent model:
-- group 1 is active and holds Arms (tab 1, 21 points), group 2 holds Fury
-- (tab 2, 31 points). Group 1 being active is what makes the second spec line
-- render grey.
-- `icon` is a fileID on the modern clients, which is why it is a number here.
local SPECS = {
    [1] = { id = 71, name = "Arms", icon = 1100001 },
    [2] = { id = 72, name = "Fury", icon = 1100002 },
    [3] = { id = 73, name = "Protection", icon = 1100003 },
}

-- C_SpecializationInfo.GetSpecializationInfo has the same 10-value return on
-- all five clients: specId, name, description, icon, role, primaryStat,
-- pointsSpent, background, previewPointsSpent, isUnlocked.
--
-- Group-aware: `groupIndex` (6th arg) selects which specialization group is
-- being read, exactly as the real API does. The modern talent path reads
-- through this call, so a mock that ignored the group would make both groups
-- resolve to the same spec and the inactive spec line would be suppressed.
local function makeSpecializationInfo(modern)
    return function(specIndex, isInspect, isPet, inspectTarget, sex, groupIndex, classID)
        local s = SPECS[specIndex]
        if (not s) then
            return 0
        end
        local group = groupIndex or 1
        local pts = (TALENT_GROUP_POINTS[group] or {})[specIndex] or 0
        return s.id, s.name, "desc", s.icon, "DPS", 4, pts, nil, 0, true
    end
end

REALG.C_SpecializationInfo = { GetSpecializationInfo = makeSpecializationInfo(true) }
REALG.C_SpecializationInfo.GetActiveSpecGroup = function() return 1 end

-- Talent tree model with real per-talent RANKS, because that is what the
-- Classic path now sums: talentPoints[tab] = sum of each talent's rank.
--
-- Modeled as the harness Warrior with two assigned specs:
--   group 1 -> Arms  (tab 1), 21 points
--   group 2 -> Fury  (tab 2), 31 points
-- Group 1 is active, so tab 1 renders coloured and tab 2 renders grey.
--
-- `icon` values are 6-digit fileIDs, deliberately unlike `rank`, so a test can
-- tell the two apart: if the tooltip ever prints the icon as a point value again
-- the harness catches it.
TALENTS = {
    [1] = { -- Arms
        { rank = 5, maxRank = 5, tier = 1, column = 1, icon = 132040 },
        { rank = 3, maxRank = 5, tier = 1, column = 2, icon = 132041 },
        { rank = 5, maxRank = 5, tier = 1, column = 3, icon = 132042 },
        { rank = 5, maxRank = 5, tier = 2, column = 1, icon = 132043 },
        { rank = 3, maxRank = 5, tier = 2, column = 2, icon = 132044 },
    },
    [2] = { -- Fury
        { rank = 5, maxRank = 5, tier = 1, column = 1, icon = 132050 },
        { rank = 5, maxRank = 5, tier = 1, column = 2, icon = 132051 },
        { rank = 5, maxRank = 5, tier = 1, column = 3, icon = 132052 },
        { rank = 5, maxRank = 5, tier = 2, column = 1, icon = 132053 },
        { rank = 5, maxRank = 5, tier = 2, column = 2, icon = 132054 },
        { rank = 5, maxRank = 5, tier = 2, column = 3, icon = 132055 },
        { rank = 1, maxRank = 1, tier = 3, column = 2, icon = 132056, isExceptional = true },
    },
    [3] = { -- Protection, unassigned
        { rank = 0, maxRank = 5, tier = 1, column = 1, icon = 132060 },
    },
}
-- Points per [group][tab], derived from the ranks above.
TALENT_GROUP_POINTS = {
    [1] = { [1] = 21, [2] = 0, [3] = 0 },
    [2] = { [1] = 0, [2] = 31, [3] = 0 },
}
TALENT_ACTIVE_GROUP = 1
TALENT_QUERIES = { linear = 0, grid = 0, other = 0 }

REALG.GetNumTalents = function(specIndex)
    return #(TALENTS[specIndex] or {})
end
REALG.GetNumTalentGroups = function() return 2 end
REALG.GetActiveTalentGroup = function() return TALENT_ACTIVE_GROUP end
REALG.C_SpecializationInfo.GetActiveSpecGroup = function(isInspect)
    return TALENT_ACTIVE_GROUP
end

-- GetTalentInfo answers only the query form the real client answers. The mock
-- refuses the wrong one, exactly as the engine would for an unknown shape.
--
-- Form A (Classic family, Vanilla\TalentFrameBase.lua):
--   { specializationIndex, talentIndex }
--   -> rank comes from the per-group model, so the Classic sum is real.
-- Form B (Retail / WoW Forever, Mainline\TalentFrameBase.lua):
--   { tier, column, target }
REALG.C_SpecializationInfo.GetTalentInfo = function(query)
    if (type(query) ~= "table") then return nil end
    if (query.specializationIndex and query.talentIndex) then
        TALENT_QUERIES.linear = TALENT_QUERIES.linear + 1
        local specIndex = query.specializationIndex
        local t = (TALENTS[specIndex] or {})[query.talentIndex]
        if (not t) then return nil end
        -- rank is per-group: a tab the player has not invested in reports 0 for
        -- every talent, so summing ranks yields that group's tab total.
        local group = query.groupIndex or 1
        local invested = (TALENT_GROUP_POINTS[group] or {})[specIndex] or 0
        local rank = (invested > 0) and (t.rank or 0) or 0
        return {
            talentID = specIndex * 1000 + query.talentIndex,
            name = "Talent", icon = t.icon, tier = t.tier, column = t.column,
            selected = false, available = true, isPVPTalentUnlocked = false,
            known = false, grantedByAura = false, rank = rank, maxRank = t.maxRank or 1,
            meetsPrereq = true, previewRank = rank, meetsPreviewPrereq = true,
            isExceptional = t.isExceptional or false, hasGoldBorder = false,
        }
    end
    if (query.tier and query.column) then
        TALENT_QUERIES.grid = TALENT_QUERIES.grid + 1
        for _, list in pairs(TALENTS) do
            for _, t in ipairs(list) do
                if (t.tier == query.tier and t.column == query.column) then
                    return {
                        talentID = t.icon, name = "Talent", icon = t.icon,
                        tier = t.tier, column = t.column, selected = false,
                        available = true, isPVPTalentUnlocked = false, known = false,
                        grantedByAura = false, rank = t.rank or 0, maxRank = t.maxRank or 1,
                        meetsPrereq = true, previewRank = t.rank or 0, meetsPreviewPrereq = true,
                        isExceptional = t.isExceptional or false, hasGoldBorder = false,
                    }
                end
            end
        end
        return nil
    end
    TALENT_QUERIES.other = TALENT_QUERIES.other + 1
    return nil
end
REALG.C_SpecializationInfo.GetClassIDFromSpecID = function(specID)
    for i, s in pairs(SPECS) do
        if (s.id == specID) then return 1 end
    end
    return 0
end
REALG.C_SpecializationInfo.GetNumSpecializationsForClassID = function() return 3 end
REALG.GetSpecializationInfoByID = function(specID)
    for _, s in pairs(SPECS) do
        if (s.id == specID) then
            return s.id, s.name, "desc", s.icon
        end
    end
    return nil
end
REALG.UnitSex = function() return 2 end

-- The talent-tab globals exist ONLY on the Classic family. Verified: 3 call-site
-- files on each of classic_era / classic_anniversary / classic_titan, 0 on
-- forever and live. Modelling them on the modern clients made the harness
-- exercise the talent-tab path on Retail and hide the fact that the modern
-- path produced no talent data at all.
REALG.GetTalentTabInfo = function(tabIndex, isInspect, isPet, groupIndex)
    local s = SPECS[tabIndex]
    if (not s) then return nil end
    -- Blizzard's deprecation shim returns 8 values with pointsSpent at position 5.
    return s.id, s.name, "desc", s.icon, s.points, nil, 0, true
end
REALG.Enum = { TooltipDataType = { Item = 0, Unit = 2 } }
REALG.InterfaceOptions_AddCategory = function() end
REALG.InterfaceOptionsFrame_OpenToCategory = function() end
REALG.InterfaceOptionsFrame_Show = function() end
REALG.BackdropTemplateMixin = {}
REALG.Item = nil
REALG.Settings = nil
REALG.ColorPickerFrame = nil

-- Tooltip script sets per family. Modern tooltips have no
-- OnTooltipSetUnit / OnTooltipSetItem / OnTooltipSetSpell.
do
    local modern = { OnLoad = true, OnShow = true, OnHide = true, OnEvent = true,
        OnUpdate = true, OnTooltipCleared = true, OnSizeChanged = true,
        OnEnter = true, OnLeave = true }
    local classic = { OnLoad = true, OnShow = true, OnHide = true, OnEvent = true,
        OnUpdate = true, OnTooltipCleared = true, OnSizeChanged = true,
        OnEnter = true, OnLeave = true,
        OnTooltipSetUnit = true, OnTooltipSetItem = true, OnTooltipSetSpell = true }
    local set = usePipeline and modern or classic
    for _, nm in ipairs({ "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1",
            "ShoppingTooltip2", "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2" }) do
        local f = REALG[nm]
        if (f and rawget(f, "__scripts") ~= nil) then rawset(f, "__scripts", set) end
    end
end

if (usePipeline) then
    POSTCALLS = {}
    REALG.TooltipDataProcessor = { AddTooltipPostCall = function(typ, fn)
        POSTCALLS[#POSTCALLS + 1] = { typ = typ, fn = fn } end }
    REALG.TooltipUtil = {
        GetDisplayedUnit = function() return "n", currentUnit, UNITS[currentUnit].guid end,
        GetDisplayedItem = function() return "n", ITEM[1].link end }
    -- The GameTooltip on a pipeline client mixes in TooltipDataHandlerMixin,
    -- which is where IsTooltipType / GetPrimaryTooltipData come from. Without
    -- these two the addon's liveness probe correctly reports "no pipeline" and
    -- the post-calls are never registered.
    REALG.GameTooltip.IsTooltipType = function() return true end
    REALG.GameTooltip.GetPrimaryTooltipData = function() return nil end

    -- Modern-only specialization surface. On Retail and WoW Forever:
    --   * GetNumTalentTabs does not exist at all
    --   * GetSpecialization() returns a specID, not an index
    --   * GetInspectSpecialization is the only way to read another unit's spec
    REALG.GetNumTalentTabs = nil
    -- Group-aware: the active specialization of the requested group.
    REALG.GetSpecialization = function(isInspect, isPet, groupIndex)
        return SPECS[groupIndex or 1].id
    end
    REALG.C_SpecializationInfo.GetSpecialization = function(isInspect, isPet, groupIndex)
        return SPECS[groupIndex or 1].id
    end
    REALG.C_SpecializationInfo.GetInspectSpecialization = function(unit)
        if (UNITS[unit] and UNITS[unit].isPlayer) then
            return SPECS[1].id
        end
        return nil
    end
else
    REALG.TooltipDataProcessor = nil
    REALG.TooltipUtil = nil
    -- Classic family: talent tabs exist, and GetInspectSpecialization does not.
    REALG.GetNumTalentTabs = function() return 3 end
    REALG.GetSpecialization = nil
    REALG.C_SpecializationInfo.GetSpecialization = nil
    REALG.C_SpecializationInfo.GetInspectSpecialization = nil
    REALG.C_SpecializationInfo.GetClassIDFromSpecID = nil
    REALG.C_SpecializationInfo.GetNumSpecializationsForClassID = nil
    -- Titanforge is the Chinese WotLK build. It DOES have
    -- C_SpecializationInfo.GetTalentInfo and GetNumTalents: verified in the
    -- generated C_SpecializationInfo docs on classic_titan, which list
    -- GetTalentInfo and TalentInfoQuery/TalentInfoResult, and GetNumTalents has
    -- 3 real call sites on every Classic branch. An earlier version of this
    -- harness wrongly nil'd both for Titanforge, which zeroed its talent
    -- points.
    -- What Titanforge lacks is the modern spec surface (GetSpecialization,
    -- GetInspectSpecialization, GetClassIDFromSpecID,
    -- GetNumSpecializationsForClassID), which is already nil'd above.
    -- Classic-family GameTooltip: no mixin, C++-style GetUnit returning 2 values
    REALG.GameTooltip.GetUnit = function() return "n", currentUnit end
    REALG.GameTooltip.GetItem = function() return "n", ITEM[1].link end
end

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
local GT = REALG.GameTooltip

-- Seed the tooltip with stock Blizzard-style content so the addon has lines to
-- read and rewrite, exactly as it would in game.
local function seedTooltip()
    GT:ClearLines()
    GT.__unit = currentUnit
    local u = UNITS[currentUnit]
    GT:AddLine(u.name)
    GT:AddLine("Level " .. u.level .. " " .. (u.race or ""))
    if (u.class) then GT:AddLine(u.class) end
    GT:AddLine("Testguild")
    GT:AddLine("")
    GT:AddLine("HP: 50/50")
end

-- Read the tooltip the way the game renders it: through the line FontStrings.
-- In non-wide tip_style the addon REWRITES existing lines with
-- left:SetText(...) rather than appending new ones, so reading the backing
-- line records would miss everything it wrote.
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
    return table.concat(out, "\n")
end

local checks = {}
local function check(name, cond, detail)
    checks[#checks + 1] = { name, cond and true or false, detail }
end

-- Direct probe of the library so a wrong value is reported even if the tooltip
-- line happens to render something plausible.
local function probeSpecIndex(group)
    local ok, CI = pcall(REALG.LibStub, "LibForeverInspector", true)
    if (not ok or not CI) then return nil end
    local ok2, idx = pcall(CI.GetSpecialization, CI, "player", group or 1)
    if (not ok2) then return nil end
    return idx
end

local function probeTalentPoints(group)
    local ok, CI = pcall(REALG.LibStub, "LibForeverInspector", true)
    if (not ok or not CI) then return nil end
    local ok2, a, b, c = pcall(CI.GetTalentPoints, CI, "player", group or 1)
    if (not ok2) then return nil end
    return a, b, c
end

local function probeActiveGroup()
    local ok, CI = pcall(REALG.LibStub, "LibForeverInspector", true)
    if (not ok or not CI) then return nil end
    local ok2, g = pcall(CI.GetActiveTalentGroup, CI, "player")
    if (not ok2) then return nil end
    return g
end

-- 1. unit tooltip, self.
-- Configure AFTER load: the addon runs its own config reset at load time and
-- replaces _G.TacoTipConfig, so anything written before loading is discarded.
-- ApplyConfigDefaults also guarantees the real key names from GetDefaults().
currentUnit = "player"
local C = REALG.TacoTipConfig
if (TT.ApplyConfigDefaults) then pcall(TT.ApplyConfigDefaults, TT, C) end
C.show_gs_player = true
C.show_avg_ilvl = true
C.show_talents = true
C.show_guild_name = true
C.show_guild_rank = true
C.show_hp_bar = true
C.show_power_bar = true
C.show_item_level = true
C.show_gs_items = true
C.show_target = true
C.color_class = true
C.tooltip_border_use_class = true
C.tooltip_portrait = true
C.tip_style = 3
seedTooltip()
-- Which delivery path exists is client-specific. Retail and WoW Forever tooltips
-- do not declare OnTooltipSetUnit at all (their template dropped it), so the
-- addon installs NO such hook there and the post-call is the only path. The hook
-- is the live path only on the Classic family.
local hookUnit = GT.__hooks.OnTooltipSetUnit
if (usePipeline) then
    check("usePipeline tooltip has no OnTooltipSetUnit script to hook",
        hookUnit == nil, "hooked=" .. tostring(hookUnit ~= nil))
    check("unit tooltip delivered by post-call", POSTCALLS and #POSTCALLS >= 1,
        "postcalls=" .. tostring(POSTCALLS and #POSTCALLS))
else
    check("OnTooltipSetUnit hook registered", hookUnit ~= nil)
end

-- 3D portrait teardown. GearScore item loads complete ASYNCHRONOUSLY, so each
-- completion re-drives the tooltip for the SAME unit. Tearing the PlayerModel
-- down on those drives reloads it every time, and the portrait strobes for as
-- long as loads keep arriving. The model must survive a re-render of the same
-- unit, and must still be cleared when the unit actually changes.
do
    REALG.TacoTipConfig.tooltip_portrait = true
    REALG.TacoTipConfig.tooltip_portrait_3d = true
    local g = REALG.UnitGUID and REALG.UnitGUID("player") or "PLAYER-GUID"
    -- Delivery path is client-specific: the post-call on Retail / WoW Forever,
    -- the OnTooltipSetUnit script hook on the Classic family. Drive whichever
    -- one this client actually uses, or the test would silently no-op there.
    local function driveSameUnit(guidOverride)
        local payload = { guid = guidOverride or g }
        if (POSTCALLS and POSTCALLS[1]) then
            POSTCALLS[1].fn(GT, payload)
        elseif (GT.__hooks and GT.__hooks.OnTooltipSetUnit) then
            GT.__hooks.OnTooltipSetUnit(GT, payload.guid)
        end
    end
    -- The portrait is created lazily by the first drive, so establish the unit
    -- before instrumenting.
    driveSameUnit()
    local m = GT.TacoTipPortrait3D
    if (m) then
        local clears = 0
        local prevClear = m.ClearModel
        m.ClearModel = function(...)
            clears = clears + 1
            if (prevClear) then return prevClear(...) end
        end
        -- Three more drives of the SAME unit: each stands for a GearScore item
        -- load completing asynchronously.
        for _ = 1, 3 do driveSameUnit() end
        check("same-unit re-render does not reload the 3D model", clears == 0,
            "ClearModel calls=" .. tostring(clears))
        -- A real unit change must still tear the model down. The unit is changed
        -- on the tooltip itself rather than via the guid payload: the Classic
        -- script hook forwards no guid, so a payload-only change would be a
        -- no-op there and the test would pass for the wrong reason.
        local prevGetUnit = GT.GetUnit
        GT.GetUnit = function() return "n", "target" end
        driveSameUnit()
        check("unit change DOES clear the 3D model", clears >= 1,
            "ClearModel calls=" .. tostring(clears))
        GT.GetUnit = prevGetUnit
        m.ClearModel = prevClear
    else
        check("3D portrait present for the model-teardown test", false,
            "no TacoTipPortrait3D on the tooltip")
    end
end

-- The 3D portrait must not be reloaded on every render. This is the actual
-- flicker path, and it is NOT covered by the test above.
--
-- TT:ApplyTooltipAppearance runs at the end of every successful unit render and
-- used to call ClearModel + SetUnit unconditionally. PlayerModel:SetUnit loads
-- a mesh asynchronously, so an unconditional reload blanks the portrait until
-- the load resolves. GearScore item loads complete asynchronously and re-drive
-- the render many times for the SAME unit, so the model strobed for as long as
-- loads kept arriving.
--
-- This test drives ApplyTooltipAppearance DIRECTLY. Driving the unit hook
-- cannot test this: onTooltipSetUnit early-returns when the tooltip has no text
-- lines, which is true in the mock after the first render but never true in
-- game -- so the hook path silently never reached the reload, and the test
-- above passed for the wrong reason.
do
    REALG.TacoTipConfig.tooltip_portrait = true
    REALG.TacoTipConfig.tooltip_portrait_3d = true

    local m, clears, setUnits, prevClear, prevSetUnit

    -- First drive establishes the portrait and its loaded-unit cache entry.
    pcall(TT.ApplyTooltipAppearance, TT, GT, "player")
    m = GT.TacoTipPortrait3D

    if (m) then
        clears, setUnits = 0, {}
        prevClear, prevSetUnit = m.ClearModel, m.SetUnit
        m.ClearModel = function(...)
            clears = clears + 1
            if (prevClear) then return prevClear(...) end
        end
        m.SetUnit = function(_, u)
            setUnits[#setUnits + 1] = u
            if (prevSetUnit) then return prevSetUnit(m, u) end
        end

        local base = #setUnits

        -- Three re-renders of the SAME unit: each stands for a GearScore item
        -- load completing asynchronously.
        for _ = 1, 3 do
            pcall(TT.ApplyTooltipAppearance, TT, GT, "player")
        end
        check("same-unit re-render does not reload the 3D model", clears == 0 and #setUnits == base,
            "ClearModel=" .. tostring(clears) .. " SetUnit=" .. tostring(#setUnits - base))

        -- The SAME character reached through a different unit token must not
        -- reload: "mouseover" and "target" are different tokens for one person,
        -- and the cache is keyed on the GUID precisely so this cannot blank the
        -- model. Stub UnitGUID so both tokens report the same identity.
        local prevGUID = REALG.UnitGUID
        REALG.UnitGUID = function(u)
            if (u == "player" or u == "target") then
                return "Player-1-00000001"
            end
            return prevGUID and prevGUID(u) or nil
        end
        pcall(TT.ApplyTooltipAppearance, TT, GT, "target")
        check("same character via a different unit token does not reload",
            clears == 0 and #setUnits == base,
            "ClearModel=" .. tostring(clears) .. " SetUnit=" .. tostring(#setUnits - base))
        REALG.UnitGUID = prevGUID

        -- A genuinely different character MUST reload, or the previous
        -- character's mesh would persist.
        pcall(TT.ApplyTooltipAppearance, TT, GT, "mouseover")
        check("unit change DOES reload the 3D model", clears >= 1 and #setUnits > base,
            "ClearModel=" .. tostring(clears) .. " SetUnit=" .. tostring(#setUnits - base))

        m.ClearModel, m.SetUnit = prevClear, prevSetUnit
    else
        check("3D portrait present for the reload test", false,
            "no TacoTipPortrait3D on the tooltip")
    end
end

-- NON-UNIT tooltips must tear the 3D portrait down, and a same-unit re-render
-- must be a complete no-op for it.
--
-- The in-game blink was NOT a model reload. The model cache is keyed on the
-- unit's GUID and a GearScore item load re-renders the SAME character, so
-- nothing about the mesh needed to change. What happened is that the Hide() in
-- clearTooltipVisuals sat OUTSIDE the destroy guard, so every caller hid the
-- frame regardless of whether the model was being kept. The portrait therefore
-- disappeared and came back once per item that finished loading, on an
-- unchanged model -- and with a tooltip_delay or the border deferral in flight
-- the re-show landed after the hide, which is why it read as a drop and a slide
-- rather than a flicker.
--
-- The contract these tests pin:
--   1. A caller with no unit knowledge (item, spell, quest, map POI, and a unit
--      tooltip with no unit resolved) TEARS DOWN. Those tooltips have no unit at
--      all, so a character model is meaningless there and must not be left
--      resident and merely hidden.
--   2. onTooltipSetUnit passes keepModel=true ONLY when the GUID is unchanged,
--      and that path must touch nothing at all.
do
    REALG.TacoTipConfig.tooltip_portrait = true
    REALG.TacoTipConfig.tooltip_portrait_3d = true

    local m, clears, prevClear, prevHide

    pcall(TT.ApplyTooltipAppearance, TT, GT, "player")
    m = GT.TacoTipPortrait3D

    if (m and TT.clearTooltipVisuals) then
        clears = 0
        prevClear, prevHide = m.ClearModel, m.Hide
        m.ClearModel = function(...)
            clears = clears + 1
            if (prevClear) then return prevClear(...) end
        end
        m.Hide = function(...)
            if (prevHide) then return prevHide(...) end
        end

        -- A non-unit tooltip recycles with no arguments, exactly as
        -- itemToolTipHook and the non-unit branch of onTooltipShow do. It has no
        -- unit, so the model must be destroyed, not hidden and retained.
        for _ = 1, 3 do
            pcall(TT.clearTooltipVisuals, GT)
        end
        check("non-unit tooltip tears the 3D portrait down", clears >= 1,
            "ClearModel calls=" .. tostring(clears))
        check("non-unit tooltip hides the 3D portrait frame", not m:IsShown(),
            "portrait visible after a non-unit recycle")

        -- keepModel=true is the same-unit case: it must be a complete no-op, or
        -- the portrait blinks on a character that never changed.
        --
        -- Render FIRST, then start counting. The render above legitimately cleared
        -- once, because the preceding teardown dropped the loaded-unit cache and
        -- ApplyTooltipAppearance must reload when the key is absent. Counting
        -- across that would measure the reload rather than the recycle, which is
        -- exactly the confusion that let the original bug through.
        pcall(TT.ApplyTooltipAppearance, TT, GT, "player")
        clears = 0
        pcall(TT.clearTooltipVisuals, GT, nil, true)
        check("same-unit keepModel does not destroy or hide the model",
            clears == 0 and m:IsShown(),
            "ClearModel=" .. tostring(clears) .. " shown=" .. tostring(m:IsShown()))

        m.ClearModel, m.Hide = prevClear, prevHide
    else
        check("3D portrait present for the teardown test", false,
            "no TacoTipPortrait3D on the tooltip")
    end
end



-- Specialization overlay icon: Retail / WoW Forever ONLY.
--
-- Reported in game as a "stray" icon to the LEFT of the tooltip -- the hovering
-- player's own spec icon appearing on other characters, e.g. a warrior's arms
-- while hovering someone else. Two independent causes, both fixed:
--
--   B. The library's icon lookup fell back to
--      C_SpecializationInfo.GetSpecializationInfo(specIndex) when the talent
--      grid pass found nothing. That API is called with NO unit argument, so it
--      always answers for the LOCAL player. For a player you have not
--      inspected the grid pass always finds nothing, so the fallback always
--      fired -- which is why the stray icon appeared specifically on other
--      characters and looked reliable rather than intermittent.
--
--   A. The overlay was only cleared in the `else` branch of the talent block,
--      so a unit with no talent data never cleared it and the previous
--      character's icon simply stayed on screen.
--
-- C is also pinned here: a miss for an inspect target must not be cached, or
-- "no icon" would stick all session and never appear once their talents load.
do
    local okCI, CI = pcall(REALG.LibStub, "LibForeverInspector", true)
    local modern = okCI and CI and CI.IsRetail and (CI:IsRetail() or CI:IsForever())

    if (not modern) then
        -- Classic family: the overlay must never be created at all. Its icon is
        -- inlined by formatSpecializationText from GetLocalizedSpecIcon, so a
        -- created overlay here would mean the Classic path had been altered.
        pcall(TT.clearTooltipVisuals, GT)
        pcall(TT.ApplyTooltipAppearance, TT, GT, currentUnit or "player")
        check("Classic never creates the specialization overlay frame",
            GT.TacoTipSpecIcon == nil,
            "overlay frame was created on a Classic client")
    elseif (not okCI or not CI) then
        check("inspector library available for the spec-icon test", false,
            "LibStub LibForeverInspector unavailable")
    else
        local LOCAL_ICON = 999111
        local REALG_ = REALG
        local savedGetTalentInfo = REALG_.C_SpecializationInfo.GetTalentInfo
        local savedSpecInfo = REALG_.C_SpecializationInfo.GetSpecializationInfo

        -- Simulate "no talent data for this unit": the engine API the grid pass
        -- needs is absent, so it cannot possibly find an icon.
        REALG_.C_SpecializationInfo.GetTalentInfo = nil
        -- And make the local-player fallback loud and unmistakable, so a
        -- regression cannot be mistaken for "no data".
        REALG_.C_SpecializationInfo.GetSpecializationInfo = function(specIndex)
            return specIndex, "LocalPlayerSpec", "", LOCAL_ICON
        end

        if (CI.InvalidateModernSpecializationIconCache) then
            pcall(CI.InvalidateModernSpecializationIconCache, CI)
        end

        -- B: an inspect target with no data must get NO icon. Before the fix
        -- this returned LOCAL_ICON -- the hovering player's own spec icon.
        local inspected = CI:GetModernSpecializationIcon(1, 1, true, "target")
        check("un-inspected target does not get the local player's spec icon",
            inspected == nil,
            "got " .. tostring(inspected) .. " (expected nil)")

        -- The local player's own icon must still work: the fallback is still
        -- correct when isInspect is false, and this is the path that makes the
        -- overlay work for you at all.
        local own = CI:GetModernSpecializationIcon(1, 1, false, nil)
        check("local player still resolves a spec icon",
            own == LOCAL_ICON,
            "got " .. tostring(own) .. " (expected " .. tostring(LOCAL_ICON) .. ")")

        -- C: the miss must not have been cached. Restore real talent data and
        -- ask again -- if `false` had been written to the cache this returns nil
        -- forever and the icon would never appear for anyone.
        REALG_.C_SpecializationInfo.GetTalentInfo = savedGetTalentInfo
        REALG_.C_SpecializationInfo.GetSpecializationInfo = savedSpecInfo
        if (CI.InvalidateModernSpecializationIconCache) then
            pcall(CI.InvalidateModernSpecializationIconCache, CI)
        end
        local afterData = CI:GetModernSpecializationIcon(1, 1, true, "target")
        check("spec icon appears once the target's talents are available",
            type(afterData) == "number" and afterData ~= LOCAL_ICON and afterData ~= 0,
            "got " .. tostring(afterData))

        -- A: the overlay must be hidden whenever the talent block runs without
        -- a real icon, so a previous character's icon cannot survive a hover.
        pcall(TT.clearTooltipVisuals, GT)
        if (GT.TacoTipSpecIcon) then
            GT.TacoTipSpecIcon:Show()
            pcall(TT.ApplyTooltipAppearance, TT, GT, "mouseover")
            local shown = GT.TacoTipSpecIcon:IsShown()
            -- Only assert the clear when the render produced no icon of its own.
            if (CI:GetModernSpecializationIcon(1, 1, true, "mouseover") == nil) then
                check("talent render with no icon hides the stale overlay",
                    not shown,
                    "overlay still visible after a data-less render")
            end
        end
    end
end

-- GearScore completion re-entrancy. itemcacheCB fires TacoTip_GSCallback when an
-- item load completes; the callback re-drives the tooltip, which re-runs the
-- pipeline and can register further item loads that call straight back in. Left
-- unbounded, the tooltip rebuilds many times a second for as long as the mouse
-- rests on a unit frame. The callback must therefore service a nested call for
-- the same guid exactly once, and must not re-enter for it.
do
    local cb = _G.TacoTip_GSCallback
    check("TacoTip_GSCallback present", type(cb) == "function")
    if (type(cb) == "function") then
        local drives = 0
        local g = REALG.UnitGUID and REALG.UnitGUID("player") or "PLAYER-GUID"
        REALG.TacoTipConfig.tooltip_delay = 0
        -- Count how many times the pipeline is actually driven, and re-enter from
        -- inside the drive the way a completing item load would.
        local prevUpdate = GT.UpdateTooltip
        GT.UpdateTooltip = function(...)
            drives = drives + 1
            if (drives < 4) then
                cb(g) -- nested completion for the same unit
            end
            if (prevUpdate) then return prevUpdate(...) end
        end
        local ok = pcall(cb, g)
        GT.UpdateTooltip = prevUpdate
        check("nested GearScore callback does not re-enter", ok and drives == 1,
            "drives=" .. tostring(drives))
        check("nested callback did not blow the stack", ok,
            ok and "" or "callback raised")
    end
end


if (DEBUG) then
    local l1 = TT.GetTooltipLeftLine and TT.GetTooltipLeftLine(GT, 1)
    STD.io.write("DEBUG config.show_gs_player = " .. tostring(REALG.TacoTipConfig.show_gs_player) .. "\n")
    STD.io.write("DEBUG config.tip_style      = " .. tostring(REALG.TacoTipConfig.tip_style) .. "\n")
    STD.io.write("DEBUG NumLines              = " .. tostring(GT:NumLines()) .. "\n")
    STD.io.write("DEBUG GetLeftLine(1)        = " .. tostring(l1) .. "\n")
    STD.io.write("DEBUG GetText()             = " .. tostring(l1 and l1:GetText()) .. "\n")
    local g = REALG.TT_GS
    if (g) then
        local gs, il = g:GetScore("Player-1-00000001", false)
        STD.io.write("DEBUG GetScore(player)      = " .. tostring(gs) .. ", ilvl=" .. tostring(il) .. "\n")
    else
        STD.io.write("DEBUG GetScore(player)      = TT_GS missing\n")
    end
    if (GT.GetUnit) then local _, u = GT:GetUnit(GT); STD.io.write("DEBUG GetUnit()             = " .. tostring(u) .. "\n") else STD.io.write("DEBUG GetUnit()             = (no method)\n") end
    STD.io.write("DEBUG _tacoTipState         = " .. tostring(GT._tacoTipState) .. "\n")
    STD.io.write("DEBUG NewTimer global       = " .. tostring(REALG.NewTimer) .. "\n")
    STD.io.write("DEBUG C_Timer.NewTimer      = " .. tostring(REALG.C_Timer and REALG.C_Timer.NewTimer) .. "\n")
    STD.io.write("DEBUG tooltip_delay         = " .. tostring(REALG.TacoTipConfig.tooltip_delay) .. "\n")
end

if (hookUnit) then
    local before = #GT.__lines
    ADDLINE_CALLS = 0
    local ok, err = pcall(hookUnit, GT)
    check("OnTooltipSetUnit(self) runs", ok, tostring(err))
    if (DEBUG) then
        STD.io.write("DEBUG lines before/after   = " .. before .. " / " .. #GT.__lines .. "\n")
        STD.io.write("DEBUG AddLine calls         = " .. tostring(ADDLINE_CALLS) .. "\n")
        STD.io.write("DEBUG _tacoTipState AFTER  = " .. tostring(GT._tacoTipState) .. "\n")
        if (GT._tacoTipState) then
            STD.io.write("DEBUG   currentUnitGUID    = " .. tostring(GT._tacoTipState.currentUnitGUID) .. "\n")
        end
        STD.io.write("DEBUG captured errors      = " .. #ERRORS .. "\n")
        for i, e in ipairs(ERRORS) do STD.io.write("        ERR " .. e .. "\n") end
    end
    local txt = allText()
    check("self tooltip has GearScore line", string.find(txt, "GearScore", 1, true) ~= nil,
        string.gsub(txt, "\n", " | "))
    check("self tooltip has spec/talent text",
        string.find(txt, "Arms", 1, true) ~= nil
            or string.find(txt, "Fury", 1, true) ~= nil
            or string.find(txt, "Protection", 1, true) ~= nil,
        string.gsub(txt, "\n", " | "))
    -- Point values must be small integers, never 6-digit fileIDs. The icon
    -- values in the model are deliberately 6-digit, so this is the invariant
    -- that catches "the tooltip printed icon fileIDs as talent points".
    local p1, p2, p3 = probeTalentPoints(1)
    check("talent points are small integers, not fileIDs",
        p1 and p1 < 200 and p2 and p2 < 200 and p3 and p3 < 200,
        "group1=" .. tostring(p1) .. "/" .. tostring(p2) .. "/" .. tostring(p3))
    check("group 1 points match the investment (21 in tab 1)",
        p1 == 21 and p2 == 0 and p3 == 0,
        "got " .. tostring(p1) .. "/" .. tostring(p2) .. "/" .. tostring(p3))
    local q1, q2, q3 = probeTalentPoints(2)
    check("group 2 reports its own points (31 in tab 2)",
        q1 == 0 and q2 == 31 and q3 == 0,
        "group2=" .. tostring(q1) .. "/" .. tostring(q2) .. "/" .. tostring(q3))

    check("active group resolves to group 1", probeActiveGroup() == 1,
        "active=" .. tostring(probeActiveGroup()))
    check("group 1 spec index is tab 1", probeSpecIndex(1) == 1,
        "index=" .. tostring(probeSpecIndex(1)))
    check("group 2 spec index is tab 2", probeSpecIndex(2) == 2,
        "index=" .. tostring(probeSpecIndex(2)))

    -- The rendered readout must contain the point values and a talent icon.
    check("tooltip shows the group 1 readout [21/0/0]",
        string.find(txt, "21/0/0", 1, true) ~= nil,
        string.gsub(txt, "\n", " | "))
    check("tooltip shows the group 2 readout [0/31/0]",
        string.find(txt, "0/31/0", 1, true) ~= nil,
        string.gsub(txt, "\n", " | "))
    -- The talent icon comes from the ported STATIC talent table (numeric
    -- fileIDs like 132355), not from this model, so assert that a |T escape is
    -- inlined on the talent line rather than matching a specific value.
    check("talent line carries an inline |T icon",
        string.find(txt, "|T", 1, true) ~= nil,
        string.gsub(txt, "\n", " | "))

    local iconTex = GT.TacoTipSpecIcon
    -- The overlay is gone on EVERY client, not just the Classic family. The icon
    -- is inlined by formatSpecializationText everywhere, so a created overlay
    -- meant the same specialization was drawn twice on the modern pair.
    --
    -- These two assertions used to be split -- "classic clients do not create the
    -- icon overlay" and "modern clients draw the spec icon overlay" -- and the
    -- modern half was unreachable dead code: this whole block sits inside
    -- `if (hookUnit)`, and hookUnit is the OnTooltipSetUnit script, which only
    -- exists on the Classic family. Modern runs the TooltipDataProcessor
    -- postcall path, so the modern assertions could never run on a modern client.
    -- A check that cannot execute is not coverage.
    check("no client creates the spec icon overlay frame", iconTex == nil,
        "overlay=" .. tostring(iconTex))
    if (usePipeline) then
        -- On the modern clients the spec index is unambiguous: the old code
        -- returned GetSpecialization(), a specID such as 72, where every caller
        -- needs a 1-based index into spec_table. A real type mismatch, not a
        -- return-shape guess.
        check("modern spec resolves to an index, not a specID",
            probeSpecIndex(1) == 1,
            "index=" .. tostring(probeSpecIndex(1)) .. " (a specID would be 72)")
    end
    check("no malformed talent queries were sent", TALENT_QUERIES.other == 0,
        "other=" .. tostring(TALENT_QUERIES.other))

    if (DEBUG) then
        local _, CI = pcall(REALG.LibStub, "LibForeverInspector", true)
        STD.io.write("DEBUG lib                 = " .. tostring(CI) .. "\n")
        STD.io.write("DEBUG hasIconMethod      = "
            .. tostring(CI and type(CI.GetModernSpecializationIcon)) .. "\n")
        STD.io.write("DEBUG isRetail/isForever = " .. tostring(CI and CI:IsRetail()) .. "/"
            .. tostring(CI and CI:IsForever()) .. "\n")
        local _, icon = pcall(CI and CI.GetModernSpecializationIcon, CI, 2, 1, false, nil)
        STD.io.write("DEBUG GetModSpecIcon(2,1)   = " .. tostring(icon) .. "\n")
        STD.io.write("DEBUG CSI.GetTalentInfo  = " .. tostring(REALG.C_SpecializationInfo and REALG.C_SpecializationInfo.GetTalentInfo) .. "\n")
        STD.io.write("DEBUG talent queries     = linear=" .. tostring(TALENT_QUERIES.linear)
            .. " grid=" .. tostring(TALENT_QUERIES.grid) .. " other=" .. tostring(TALENT_QUERIES.other) .. "\n")
    end

    check("self tooltip has iLvl", string.find(txt, "iLvl", 1, true) ~= nil
        or string.find(txt, "Item Level", 1, true) ~= nil)

    if (DEBUG) then
        -- Dump the rendered specialization line so the harness output shows what
        -- the tooltip actually looks like, not just whether a substring matched.
        -- Filtered on the spec name, not the "Talents" label, because the label
        -- is localized (Chinese on Titanforge).
        STD.io.write("DEBUG active locale         = " .. tostring(REALG.TACOTIP_ACTIVE_LOCALE) .. "\n")
        for line in STD.string.gmatch(txt, "[^\n]+") do
            -- Match on the point readout, not the label: the label is localized
            -- (Chinese on Titanforge), the readout is not.
            if STD.string.find(line, "/0]", 1, true) or STD.string.find(line, "/31/0", 1, true) then
                STD.io.write("RENDERED: " .. line .. "\n")
            end
        end
    end
end

-- 2. unit tooltip, other player (guild/class colour/level path)
currentUnit = "mouseover"
seedTooltip()
if (hookUnit) then
    local ok, err = pcall(hookUnit, GT)
    check("OnTooltipSetUnit(other player) runs", ok, tostring(err))
    local txt = allText()
    check("other-player tooltip gained lines", #GT.__lines >= 5,
        "lines=" .. #GT.__lines)
    -- Non-wide style rewrites existing lines, so assert on rendered text
    -- rather than on the line count alone.
    check("other-player tooltip still renders text", string.find(txt, "Enemyplayer", 1, true) ~= nil,
        string.gsub(txt, "\n", " | "))
end

-- 3. unit tooltip, hostile NPC (difficulty colour path)
currentUnit = "target"
seedTooltip()
if (hookUnit) then
    local ok, err = pcall(hookUnit, GT)
    check("OnTooltipSetUnit(hostile NPC) runs", ok, tostring(err))
end

-- 4. non-unit content must not leave stale overlays
if (GT.__hooks.OnTooltipCleared) then
    local ok, err = pcall(GT.__hooks.OnTooltipCleared, GT)
    check("OnTooltipCleared runs", ok, tostring(err))
end
if (GT.__hooks.OnTooltipSetSpell) then
    local ok, err = pcall(GT.__hooks.OnTooltipSetSpell, GT)
    check("OnTooltipSetSpell runs", ok, tostring(err))
end

-- 5. item tooltip
local hookItem = GT.__hooks.OnTooltipSetItem
if (usePipeline) then
    check("pipeline tooltip has no OnTooltipSetItem script to hook", hookItem == nil,
        "hooked=" .. tostring(hookItem ~= nil))
else
    check("OnTooltipSetItem hook registered", hookItem ~= nil)
end
if (hookItem) then
    GT:ClearLines()
    GT:AddLine(ITEM[1].name)
    GT:AddLine("Item Level 88")
    local ok, err = pcall(hookItem, GT)
    check("OnTooltipSetItem runs", ok, tostring(err))
    local txt = allText()
    check("item tooltip shows GearScore", string.find(txt, "GearScore", 1, true) ~= nil,
        string.gsub(txt, "\n", " | "))
end

-- 6. unit resolution: a tooltip whose GetUnit returns nil must NOT be forced
--    onto "mouseover" when it is not the mouseover tooltip.
currentUnit = "target"
if (usePipeline) then
    REALG.TooltipUtil.GetDisplayedUnit = function() return "n", nil, nil end
else
    GT.GetUnit = function() return "n", nil end
end
seedTooltip()
if (hookUnit) then
    local ok = pcall(hookUnit, GT)
    check("tooltip with unresolvable unit does not error", ok)
end

-- 7. errors surfaced through geterrorhandler
check("no runtime errors captured", #ERRORS == 0,
    #ERRORS > 0 and table.concat(ERRORS, " ;; ") or nil)

-- 8. On the pipeline clients the real delivery path is the post-call, invoked
--    by Blizzard with (tooltip, data). The script hook is NOT fired there, so
--    exercise the post-call directly -- including the data.guid branch of unit
--    resolution, which the script path never reaches.
if (usePipeline and POSTCALLS and #POSTCALLS >= 2) then
    local unitPost, itemPost = POSTCALLS[1], POSTCALLS[2]
    check("Unit post-call registered for TooltipDataType.Unit", unitPost ~= nil)
    check("Item post-call registered for TooltipDataType.Item", itemPost ~= nil)

    currentUnit = "player"
    -- Restore the pipeline resolvers: step 6 above deliberately broke them to
    -- test the unresolvable case, and they must be put back or every later
    -- assertion inherits the broken state.
    REALG.TooltipUtil.GetDisplayedUnit = function()
        return "n", currentUnit, UNITS[currentUnit].guid end
    GT.GetUnit = function() return "n", currentUnit, UNITS[currentUnit].guid end
    GT.__unit = "player"
    GT.__shown = true
    GT:ClearLines()
    GT:AddLine("Testplayer")
    GT:AddLine("Level 60 Human")
    GT:AddLine("WARRIOR")
    GT:AddLine("Testguild")
    GT:AddLine("")
    GT:AddLine("HP: 50/50")
    local ok, err = pcall(unitPost.fn, GT, { guid = UNITS.player.guid })
    check("Unit post-call runs with data", ok, tostring(err))
    if (DEBUG) then
        STD.io.write("DEBUG postcall errors = " .. #ERRORS .. "\n")
        for i, e in ipairs(ERRORS) do STD.io.write("        ERR " .. e .. "\n") end
        STD.io.write("DEBUG postcall NumLines = " .. tostring(GT:NumLines()) .. "\n")
        STD.io.write("DEBUG postcall guid     = "
            .. tostring(GT._tacoTipState and GT._tacoTipState.currentUnitGUID) .. "\n")
        STD.io.write("DEBUG show_gs_player    = " .. tostring(REALG.TacoTipConfig.show_gs_player) .. "\n")
        local g = REALG.TT_GS
        if (g) then
            local a, b = g:GetScore("Player-1-00000001", true)
            STD.io.write("DEBUG GetScore(cb=true) = " .. tostring(a) .. " ilvl=" .. tostring(b) .. "\n")
        end
    end
    local ptxt = allText()
    check("post-call path yields GearScore", string.find(ptxt, "GearScore", 1, true) ~= nil
        or string.find(ptxt, "GS:", 1, true) ~= nil, string.gsub(ptxt, "\n", " | "))

    -- Modern single-specification rendering. Both of these live HERE, inside the
    -- pipeline block, because this is the only place the modern tooltip is
    -- actually rendered. The equivalent assertions that used to sit in the
    -- hookUnit block were unreachable on modern.
    --
    -- Two separate defects are pinned here:
    --  1. hasDualSpec was true on the modern pair, because the ported predicate
    --     tested C_SpecializationInfo and GetNumTalentGroups, both of which exist
    --     on Retail and WoW Forever. Group 2 then echoed group 1, drawing a
    --     second identical specialization line and a second icon.
    --  2. The specialization icon was drawn twice: once inlined by
    --     formatSpecializationText, and once on a Texture overlay outside the
    --     tooltip's left edge.
    local _, nGroup1 = string.gsub(ptxt, "21/0/0", "")
    check("modern renders the group 1 readout exactly once", nGroup1 == 1,
        "count=" .. tostring(nGroup1) .. " :: " .. string.gsub(ptxt, "\n", " | "))
    check("modern does not render a group 2 readout",
        string.find(ptxt, "0/31/0", 1, true) == nil,
        "group 2 leaked onto a single-spec client: " .. string.gsub(ptxt, "\n", " | "))
    check("modern creates no spec icon overlay frame", GT.TacoTipSpecIcon == nil,
        "overlay=" .. tostring(GT.TacoTipSpecIcon))
    check("modern still inlines the specialization icon", string.find(ptxt, "|T", 1, true) ~= nil,
        string.gsub(ptxt, "\n", " | "))

    -- data-gated resolution: GetUnit and TooltipUtil both return nothing, so
    -- only data.guid can save it. NOTE the addon deliberately maps data.guid to
    -- mouseover/target ONLY -- resolving an arbitrary unit from a guid would be
    -- a guess, which is exactly the bug that was fixed in resolveTooltipUnit.
    -- So the realistic case is a hover, where data.guid is the mouseover.
    currentUnit = "mouseover"
    REALG.TooltipUtil.GetDisplayedUnit = function() return "n", nil, nil end
    GT.GetUnit = function() return "n", nil end
    GT.__unit = nil
    GT:ClearLines()
    GT:AddLine("Enemyplayer")
    GT:AddLine("Level 59 Orc")
    local ok2 = pcall(unitPost.fn, GT, { guid = UNITS.mouseover.guid })
    check("data.guid resolves the unit when GetUnit cannot", ok2)
    check("data.guid path produced output",
        string.find(allText(), "GearScore", 1, true) ~= nil
            or string.find(allText(), "GS:", 1, true) ~= nil
            or #GT.__lines >= 2, string.gsub(allText(), "\n", " | "))

    GT:ClearLines()
    GT:AddLine(ITEM[1].name)
    GT:AddLine("Item Level 88")
    local ok3, err3 = pcall(itemPost.fn, GT, { hyperlink = ITEM[1].link })
    check("Item post-call runs with data", ok3, tostring(err3))
    check("post-call item path yields GearScore",
        string.find(allText(), "GearScore", 1, true) ~= nil)
elseif (usePipeline) then
    check("pipeline clients registered both post-calls", false,
        "got " .. tostring(POSTCALLS and #POSTCALLS))
end

local fails = 0
for _, c in ipairs(checks) do
    if (not c[2]) then
        fails = fails + 1
        STD.io.write(string.format("    FAIL %-40s %s\n", c[1], tostring(c[3] or "")))
    end
end
STD.io.write(string.format("%-12s %-9s lines=%-3d  %s\n", label,
    usePipeline and "pipeline" or "legacy", #GT.__lines,
    (fails == 0) and ("ALL " .. #checks .. " PASS") or (fails .. "/" .. #checks .. " FAILED")))
STD.os.exit(fails == 0 and 0 or 1)
