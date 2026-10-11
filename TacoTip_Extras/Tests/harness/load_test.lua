-- TacoTip_Extras offline harness.
--
--   lua5.1 load_test.lua <client> <variant>
--
--   client    classic_era | tbc | titanforge | forever | retail
--   variant   ok (default) | devname | older | nocaps | nostats
--
-- It loads the real add-on files, from the real TOC, in the real order, against
-- a mocked client, and asserts three things that have each been wrong before:
--
--   1. THE ADD-ON LOADS. No file raises, and no sub-initializer raises. Two
--      unguarded HookScript calls used to abort this on every client; those
--      assertions used to be a printed reminder under a "KNOWN GAPS" banner
--      rather than a failure, which is exactly how a known crash shipped.
--   2. THE ADAPTER RESOLVES ON ALL FIVE CLIENTS. It used to pin a version
--      string for equality against a library that publishes no version at all,
--      so it failed closed on every real install.
--   3. SCORING DELEGATES. The base GearScore must equal TT_GS's number for the
--      same item, with the enchant and gem bonuses ADDITIVE on top. Scoring
--      used to carry its own copy of the formula and it was wrong.
--
-- Three rules this harness holds itself to, because each has already cost this
-- project a bug:
--
--   - The environment models ONE real client at a time, with the exact
--     constants that client's branch defines. A constant the branch does not
--     define makes `WOW_PROJECT_ID == WOW_PROJECT_BC_CLASSIC` evaluate as
--     nil == nil, i.e. TRUE, and silently mis-detects the client.
--   - Widgets are per-kind and read as nil for a method they do not have.
--     A permissive mock hands every widget every method and cannot catch an
--     unguarded hook; that is how the crash below survived a green suite.
--   - Every fix is reverted to confirm the test fails. A test that has only
--     ever passed is not evidence.

local _hp = ((arg and arg[0]) or "Tests/harness/load_test.lua"):gsub("\\", "/")
local _hd = _hp:match("^(.*)/[^/]*$") or "."
local ROOT = dofile(_hd .. "/root.lua")

local unpack = unpack or table.unpack

local ADDON_NAME = "TacoTip_Extras"
local CLIENT = (arg[1] or "classic_era"):lower()
local VARIANT = (arg[2] or "ok"):lower()

-- ---------------------------------------------------------------------------
-- The five clients
-- ---------------------------------------------------------------------------
--
-- `constants` is NOT a guess and NOT a superset. It is exactly what the branch's
-- own FrameXML defines, verified by reading which Constants.lua each client's
-- TOC actually loads (`git show origin/<branch>:...`) and then reading those
-- files:
--
--   Classic family  Each client has its OWN Blizzard_FrameXMLBase_<Family>.toc
--       (there is no single Blizzard_FrameXMLBase.toc on these branches):
--         classic_era          -> Blizzard_FrameXMLBase_Vanilla.toc
--                                  loads Classic\, Shared\, Vanilla\Constants.lua
--         classic_anniversary  -> Blizzard_FrameXMLBase_TBC.toc
--                                  loads Classic\, Shared\, TBC\Constants.lua
--         classic_titan        -> Blizzard_FrameXMLBase_Wrath.toc
--                                  loads Classic\, Shared\, Wrath\Constants.lua
--       Classic\Constants.lua and Shared\Constants.lua define NO WOW_PROJECT_*
--       constant at all (verified: zero grep hits). The per-family file defines
--       all six AND assigns WOW_PROJECT_ID. So Era / TBC / Titanforge all
--       define the same six, with WOW_PROJECT_ID = 2 / 5 / 11.
--
--   WoW Forever     ONE Blizzard_FrameXMLBase.toc, with
--                       [Family]\Constants.lua [ExcludeLoadGameType camelot]
--                       [Game]\Constants.lua    [AllowLoadGameType camelot]
--       so on camelot it loads only Shared\, [Game]\ and the top-level
--       Constants.lua. Camelot/Constants.lua defines NO WOW_PROJECT_* constant
--       (verified: zero grep hits). The two that survive come from
--       Blizzard_ProjectConstants/ProjectConstants.lua, which is
--       "## AllowLoad: Both" and defines exactly WOW_PROJECT_MAINLINE = 1 and
--       WOW_PROJECT_CLASSIC = 2. Nothing else. WOW_PROJECT_ID is never
--       assigned by FrameXML on this branch.
--
--   Retail          the same two, same file, same TOC shape. Verified by
--       reading ProjectConstants.lua on origin/live.
--
-- Supplying the BC/Wrath constants on camelot is the documented trap in this
-- project: it makes `WOW_PROJECT_ID == WOW_PROJECT_BC_CLASSIC` evaluate as
-- nil == nil, i.e. TRUE, and silently mis-detects the client.
local CLASSIC_SIX = {
    WOW_PROJECT_MAINLINE = 1,
    WOW_PROJECT_CLASSIC = 2,
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5,
    WOW_PROJECT_WRATH_CLASSIC = 11,
    WOW_PROJECT_CATACLYSM_CLASSIC = 14,
    WOW_PROJECT_MISTS_CLASSIC = 19,
}

-- Exactly what WoW Forever and Retail define. No more.
local MAINLINE_TWO = {
    WOW_PROJECT_MAINLINE = 1,
    WOW_PROJECT_CLASSIC = 2,
}

-- Which branch each client takes, asserted rather than described.
--
--   driver      "unit-hook" when Blizzard_GameTooltip/Classic/GameTooltip.xml
--               declares <OnTooltipSetUnit function="GameTooltip_OnTooltipSetUnit" />
--               (line 22 on classic_era AND classic_anniversary),
--               "poll" when it does not.
--   itemStats   whether the client has GetItemStats.
--
-- Both columns below were WRONG in the phase-2 harness and are corrected here.
-- OnTooltipSetUnit/OnTooltipSetItem: counted over the FULL Interface tree per
-- branch rather than by a character-class git grep (which returns zero hits on
-- origin/forever and would have reported every symbol as absent everywhere):
--
--     classic_era          OnTooltipSetUnit 4   OnTooltipSetItem 13
--     classic_anniversary  OnTooltipSetUnit 4   OnTooltipSetItem 13
--     classic_titan        OnTooltipSetUnit 4   OnTooltipSetItem 13
--     live                 OnTooltipSetUnit 1   OnTooltipSetItem 1
--     forever              OnTooltipSetUnit 1   OnTooltipSetItem 1
--
-- The single hit on live and forever is
-- Interface/AddOns/Blizzard_SharedXML/UI.xsd -- an XML SCHEMA listing the
-- script names a frame MAY declare. It is not a declaration. Every occurrence
-- on the three Classic branches is either the XML declaration or a real call
-- site.
--
-- GetItemStats: phase 2 documented it as "WoW Forever only". That is wrong. It
-- is a Mainline-family API and is present on Retail too. Verified on both
-- branches: the only file on either that mentions it at all is
-- Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua,
-- which documents it as { Name = "GetItemStats", Type = "Function" }. The
-- three Classic branches have ZERO hits across the whole tree.
local CLIENTS = {
    classic_era = {
        label = "Classic Era",
        interface = 11509,
        project = 2, -- WOW_PROJECT_CLASSIC
        constants = CLASSIC_SIX,
        driver = "unit-hook",
        tooltip = "classic",
        itemStats = false,
    },
    tbc = {
        label = "TBC Anniversary",
        interface = 20506,
        project = 5, -- WOW_PROJECT_BURNING_CRUSADE_CLASSIC
        constants = CLASSIC_SIX,
        driver = "unit-hook",
        tooltip = "classic",
        itemStats = false,
    },
    titanforge = {
        label = "Titanforge",
        interface = 38002,
        project = 11, -- WOW_PROJECT_WRATH_CLASSIC
        constants = CLASSIC_SIX,
        driver = "unit-hook",
        tooltip = "classic",
        itemStats = false,
    },
    forever = {
        label = "WoW Forever",
        interface = 16001,
        -- WOW_PROJECT_ID is engine-defined on camelot and is NOT in the
        -- FrameXML constants; the harness leaves it unset, which is the case
        -- TacoTip_Forever/Tests/harness/detect_test.lua explicitly covers.
        project = nil,
        constants = MAINLINE_TWO,
        driver = "poll",
        tooltip = "mainline",
        itemStats = true,
    },
    retail = {
        label = "Retail",
        interface = 120100,
        project = nil,
        constants = MAINLINE_TWO,
        driver = "poll",
        tooltip = "mainline",
        -- Phase 2 modelled Retail as NOT having GetItemStats. It does.
        itemStats = true,
    },
}

local CLIENT_PROFILE = CLIENTS[CLIENT]
if not CLIENT_PROFILE then
    io.write("unknown client '" .. CLIENT .. "'; expected one of: "
        .. "classic_era, tbc, titanforge, forever, retail\n")
    os.exit(2)
end

-- ---------------------------------------------------------------------------
-- The two column values, written out a SECOND time, independently
-- ---------------------------------------------------------------------------
--
-- This looks like duplication and is the whole point. CLIENTS[].itemStats and
-- CLIENTS[].driver are the MODEL; these two tables are the ORACLE, transcribed
-- from the FrameXML evidence quoted above and maintained separately. A harness
-- that only ever compared the model against itself would have kept modelling
-- Retail as "no GetItemStats" for as long as the model was wrong -- which is
-- exactly what phase 2 did, and exactly what the phase-1 to phase-2 review
-- failed to catch. Duplicated on purpose: the add-on's own constants are
-- duplicated here for the same reason (GATE_MIN_VERSION, and the five probed
-- inspector capabilities).
--
-- OnTooltipSetUnit is declared in Blizzard_GameTooltip/Classic/GameTooltip.xml
-- line 22 on classic_era, classic_anniversary and classic_titan, and in NO
-- frame file on origin/live or origin/forever.
local BRANCH_DECLARES_TOOLTIP_SET_UNIT = {
    classic_era = true,
    tbc = true,
    titanforge = true,
    forever = false,
    retail = false,
}

-- GetItemStats is documented in Blizzard_APIDocumentationGenerated on
-- origin/live and origin/forever, and appears nowhere on the three Classic
-- branches.
local BRANCH_HAS_GET_ITEM_STATS = {
    classic_era = false,
    tbc = false,
    titanforge = false,
    forever = true,
    retail = true,
}

-- ---------------------------------------------------------------------------
-- Variants
-- ---------------------------------------------------------------------------
local VARIANTS = {
    -- Everything real: TacoTip 0.8.0, the real LibForeverInspector shape, the
    -- TacoTip private table published under its packaged name.
    ok = {},
    -- The private table is published as "TacoTip_Forever" -- the dev tree's
    -- folder/TOC name -- and is listed by C_AddOns.GetAddOns, while _G.TacoTip
    -- is nil. This is the run that proves the resolver finds it without the
    -- folder name appearing anywhere in the add-on's source.
    devname = { ttGlobal = "TacoTip_Forever", tacotipVersion = "0.8.0" },
    -- A genuinely older TacoTip. The capability gate must still refuse it: a
    -- minimum is a minimum.
    older = { tacotipVersion = "0.7.0" },
    -- The inspector is missing GetInventoryItemMixin, one of the five probed
    -- capabilities. Note it STILL has no Version() method -- the real shape.
    nocaps = { dropInspector = "GetInventoryItemMixin" },
    -- GetItemStats removed even on a client that has it, so the gem/socket
    -- degradation is exercised on every one of the five.
    nostats = { forceNoItemStats = true },
    -- Settings removed from the environment entirely, so Options.Initialize has
    -- to fall back to InterfaceOptions_AddCategory and the legacy
    -- childFrame.parent wiring. Settings.RegisterCanvasLayoutCategory is
    -- present on all four required clients today, so this arm is not reachable
    -- on a real install -- which is exactly why a fail-closed `return false`
    -- there would have shipped unexercised.
    nosettings = { dropSettings = true },
}

local VARIANT_PROFILE = VARIANTS[VARIANT]
if not VARIANT_PROFILE then
    io.write("unknown variant '" .. VARIANT .. "'\n")
    os.exit(2)
end

local TACOTIP_VERSION = VARIANT_PROFILE.tacotipVersion or "0.8.0"
local TT_GLOBAL = VARIANT_PROFILE.ttGlobal or "TacoTip"
local TOOLTIP_SHAPE = CLIENT_PROFILE.tooltip
local EXPECTED_DRIVER = CLIENT_PROFILE.driver
local ITEM_STATS = CLIENT_PROFILE.itemStats and not VARIANT_PROFILE.forceNoItemStats

-- The minimum the adapter enforces. Duplicated here on purpose: a harness that
-- reads the add-on's own constant cannot catch someone lowering it.
local GATE_MIN_VERSION = "0.8.0"

-- The five inspector capabilities the adapter probes. Also duplicated here.
local GATE_INSPECTOR_CAPABILITIES = {
    "RegisterCallback", "UnregisterCallback", "PlayerGUIDToUnitToken",
    "GetInventoryItemMixin", "GetLastCacheTime",
}

-- Which variants the adapter is expected to ACCEPT. Declared here rather than
-- next to the gate assertions because the driver section above also needs it:
-- a correctly-refused run releases the tooltip surface, and a harness that
-- drove the driver anyway would be asserting that a refusal renders rows.
local EXPECT_SUPPORTED = (VARIANT == "ok" or VARIANT == "devname"
    or VARIANT == "nostats" or VARIANT == "nosettings")

local out = io.write
local failures = {}
local checks = 0

local function check(ok, label, detail)
    checks = checks + 1
    if ok then
        out(("  ok    %s\n"):format(label))
    else
        failures[#failures + 1] = label
        out(("  FAIL  %s\n"):format(label))
        if detail then
            out(("          %s\n"):format(tostring(detail)))
        end
    end
    return ok
end

-- No next() anywhere in this harness. It is absent from some environments this
-- code runs in, and a diagnostic path must never be the thing that raises.
local function sortedKeys(t)
    local list = {}
    for k in pairs(t) do
        list[#list + 1] = k
    end
    table.sort(list, function(a, b) return tostring(a) < tostring(b) end)
    return list
end

-- ---------------------------------------------------------------------------
-- Mocked WoW client
-- ---------------------------------------------------------------------------

local REALG = _G
local STD = {
    os = os, string = string, pairs = pairs, ipairs = ipairs, type = type,
    pcall = pcall, tonumber = tonumber, tostring = tostring, select = select,
    rawget = rawget, rawset = rawset, setmetatable = setmetatable,
    getmetatable = getmetatable, unpack = unpack, assert = assert,
    error = error, math = math, table = table, loadfile = loadfile,
    print = print, io = io, loadstring = loadstring,
}

local METHOD_MISSES = {}
local MISS_COUNT = 0

local CHAT = {}
local FRAMES_CREATED = 0
local EVENT_REGISTRY = {}
local HOOK_LOG = {}
local FRAMES_BY_REGISTRATION = {}
local LEGACY_CATEGORIES = {}
local LEGACY_OPENED = {}

local function noop() return nil end
local newRegion

local REGION = {
    GetName = function() return nil end,
    GetObjectType = function() return nil end,
    GetParent = function() return nil end,
    SetParent = noop,
    GetPoint = function() return nil end,
    SetPoint = noop,
    ClearAllPoints = noop,
    GetNumPoints = function() return 0 end,
    SetSize = noop, SetWidth = noop, SetHeight = noop,
    GetWidth = function() return 0 end,
    GetHeight = function() return 0 end,
    SetScale = noop, GetScale = function() return 1 end,
    GetEffectiveScale = function() return 1 end,
    SetAlpha = noop, GetAlpha = function() return 1 end,
    Show = noop, Hide = noop,
    IsShown = function() return false end,
    IsVisible = function() return false end,
    InRegionOfInterest = function() return false end,
    SetFrameStrata = noop, GetFrameStrata = function() return "MEDIUM" end,
    SetFrameLevel = noop, GetFrameLevel = function() return 1 end,
    SetDrawLayer = noop, GetDrawLayer = function() return "BACKGROUND" end,
    SetClampedToScreen = noop,
    GetLeft = function() return 0 end,
    GetRight = function() return 0 end,
    GetTop = function() return 0 end,
    GetBottom = function() return 0 end,
    GetCenter = function() return 0, 0 end,
    GetRect = function() return 0, 0, 0, 0 end,
    SetID = noop, GetID = function() return nil end,
    SetHitRectInsets = noop,
    SetPropagateMouseInput = noop,
}

local FRAME_EXTRA = {
    SetScript = function() end,
    GetScript = function() return nil end,
    HasScript = function() return false end,
    -- HookScript raises on an undeclared script, exactly like the real one. A
    -- permissive mock cannot catch an unguarded hook, and an unguarded hook is
    -- how a renamed template aborts a load half-way with no visible error.
    HookScript = function() error("HookScript on an undeclared script", 2) end,
    RegisterEvent = function() end,
    UnregisterEvent = noop,
    UnregisterAllEvents = noop,
    IsEventRegistered = function() return false end,
    EnableMouse = noop, EnableMouseMove = noop, EnableMouseWheel = noop,
    IsMouseOver = function() return false end,
    Enable = noop, Disable = noop, IsEnabled = function() return true end,
    SetEnabled = function() end,
    RegisterForDrag = noop, RegisterForClicks = noop,
    StartMoving = noop, StopMovingOrSizing = noop,
    SetMovable = noop, IsMovable = function() return false end,
    SetUserPlaced = noop, IsUserPlaced = function() return false end,
    SetToplevel = noop,
    SetFocus = noop, ClearFocus = noop, SetKeyFocus = noop,
    GetNumChildren = function() return 0 end,
    GetChildren = function() return {} end,
    CreateTexture = function(f, name, layer) return newRegion("Texture", name, f, layer) end,
    CreateFontString = function(f, name, layer, template)
        return newRegion("FontString", name, f, template or layer)
    end,
    SetBackdrop = noop, GetBackdrop = function() return nil end,
    SetBackdropColor = noop, SetBackdropBorderColor = noop,
}

local FONTSTRING_EXTRA = {
    SetText = function() end, GetText = function() return "" end,
    SetFormattedText = function() end,
    SetFontObject = noop, GetFontObject = function() return nil end,
    SetFont = noop,
    SetJustifyH = noop, SetJustifyV = noop,
    SetTextColor = noop,
    GetStringWidth = function() return 0 end,
    GetStringHeight = function() return 0 end,
    SetNonSpaceWrap = noop, SetWordWrap = noop,
    SetShadowColor = noop, SetShadowOffset = noop,
}

local TEXTURE_EXTRA = {
    SetTexture = noop, GetTexture = function() return nil end,
    SetTexCoord = noop, GetTexCoord = function() return 0, 0, 1, 1 end,
    SetVertexColor = noop, GetVertexColor = function() return 1, 1, 1, 1 end,
    SetDesaturated = noop, SetBlendMode = noop, SetAllDesaturated = noop,
}

local BUTTON_EXTRA = {
    SetText = function() end, GetText = function() return "" end,
    SetNormalTexture = noop, GetNormalTexture = function() return nil end,
    SetHighlightTexture = noop, SetPushedTexture = noop,
    SetDisabledTexture = noop,
    Click = noop, Press = noop, SetPushed = noop, IsPushed = function() return false end,
    SetState = noop, GetState = function() return "NORMAL" end,
    SetHighlightTextOffset = noop,
}

local function merge(...)
    local result = {}
    for index = 1, select("#", ...) do
        local source = select(index, ...)
        if source then
            for k, v in pairs(source) do result[k] = v end
        end
    end
    return result
end

local CHECK_EXTRA = {
    SetChecked = noop, GetChecked = function() return false end,
    SetCheckImageTexture = noop, SetUncheckedImageTexture = noop,
}

local KINDS = {
    Frame = FRAME_EXTRA, Button = FRAME_EXTRA, StatusBar = FRAME_EXTRA,
    Slider = FRAME_EXTRA,
    CheckButton = merge(FRAME_EXTRA, CHECK_EXTRA),
    FontString = FONTSTRING_EXTRA, Texture = TEXTURE_EXTRA,
}

KINDS.StatusBar = merge(FRAME_EXTRA, {
    SetMinMaxValues = noop, GetMinMaxValues = function() return 0, 100 end,
    SetValue = noop, GetValue = function() return 0 end,
    SetStatusBarTexture = noop, GetStatusBarTexture = function() return nil end,
    SetStatusBarColor = noop, SetOrientation = noop, SetReverseFill = noop,
})
KINDS.Slider = merge(FRAME_EXTRA, {
    SetMinMaxValues = noop, GetMinMaxValues = function() return 0, 1 end,
    SetValue = noop, GetValue = function() return 0 end,
    SetValueStep = noop, SetObeyStepOnDrag = noop, SetThumbTexture = noop,
})

local METHOD_CACHE = {}

local function buildMethods(kind)
    kind = kind or "Frame"
    local cached = METHOD_CACHE[kind]
    if cached then return cached end
    local methods = {}
    for k, v in pairs(REGION) do methods[k] = v end
    local extra = KINDS[kind]
    if extra then
        for k, v in pairs(extra) do methods[k] = v end
    end
    for k, v in pairs(BUTTON_EXTRA) do methods[k] = methods[k] or v end
    METHOD_CACHE[kind] = methods
    return methods
end

local function patch(name, fn)
    for _, methods in pairs(METHOD_CACHE) do
        methods[name] = fn
    end
end

-- A Button-shaped widget really declares these (Button/UIButtonTemplate.xml).
-- A Frame declares only OnLoad/OnShow/OnHide/OnEvent/OnUpdate. Giving every
-- kind the button set would hide a real unguarded hook -- which is exactly the
-- Options.attachHelp bug this harness now guards.
local BUTTON_SCRIPTS = {
    OnClick = true, OnEnter = true, OnLeave = true, OnMouseDown = true,
    OnMouseUp = true, OnDragStart = true, OnDragStop = true,
    OnReceiveDrag = true, OnPressed = true, OnDisable = true, OnEnable = true,
}

local BUTTON_KINDS = {
    Button = true, CheckButton = true, StatusBar = true, Slider = true,
    EditBox = true,
}

-- Every string the add-on ever handed GameTooltip, in order. The driver
-- assertions count lines and check that a second tick added none.
--
-- Declared ABOVE GAME_TOOLTIP_EXTRA on purpose: a `local` referenced before its
-- own `local` declaration does not become a forward reference in Lua, it
-- becomes a read of an undeclared GLOBAL -- nil -- and the call site fails at
-- RUN time with "attempt to call global", not at load time.
local GAME_TOOLTIP_ADDED = {}

-- GameTooltip gets its OWN kind rather than borrowing Frame's, because the
-- driver test has to drive a real unit tooltip: SetUnit / GetUnit / NumLines /
-- AddLine / ClearLines. A shared permissive Frame would hand every widget
-- these methods too, and then "the driver worked" would prove nothing about
-- which methods the add-on actually reaches for.
--
-- NumLines deliberately counts ADDED lines and knows nothing about geometry,
-- which is what the real one does: it is the number of tooltip regions in
-- play, not a measurement of the laid-out frame.
local GAME_TOOLTIP_EXTRA = {
    SetUnit = function(f, unit)
        -- The real SetUnit clears and rebuilds. Modelling that is what makes
        -- the idempotence test mean something: after a rebuild the line count
        -- moves, so a change gate that ignored it would skip the re-render.
        rawset(f, "__unit", unit)
        rawset(f, "__lines", 0)
        return true
    end,
    GetUnit = function(f) return rawget(f, "__unit") end,
    SetOwner = function(f, owner) rawset(f, "__owner", owner) end,
    GetOwner = function(f) return rawget(f, "__owner") end,
    NumLines = function(f) return rawget(f, "__lines") or 0 end,
    AddLine = function(f, text)
        rawset(f, "__lines", (rawget(f, "__lines") or 0) + 1)
        local n = rawget(f, "__lines")
        rawset(f, "__lastLine", tostring(text or ""))
        GAME_TOOLTIP_ADDED[#GAME_TOOLTIP_ADDED + 1] = tostring(text or "")
        return n
    end,
    AddDoubleLine = function(f, left)
        rawset(f, "__lines", (rawget(f, "__lines") or 0) + 1)
        GAME_TOOLTIP_ADDED[#GAME_TOOLTIP_ADDED + 1] = tostring(left or "")
    end,
    ClearLines = function(f) rawset(f, "__lines", 0) end,
    IsTooltipType = function() return false end,
    GetPrimaryTooltipData = function() return nil end,
}

KINDS.GameTooltip = merge(FRAME_EXTRA, GAME_TOOLTIP_EXTRA)

newRegion = function(kind, name, parent, template)
    FRAMES_CREATED = FRAMES_CREATED + 1
    kind = kind or "Frame"
    local self = {
        __kind = kind,
        __name = name,
        __parent = parent,
        __template = template,
        __methods = buildMethods(kind),
        __scripts = { OnLoad = true, OnShow = true, OnHide = true,
            OnEvent = true, OnUpdate = true, OnSizeChanged = true },
        __shown = false,
        __events = {},
    }
    if BUTTON_KINDS[kind] then
        for script in pairs(BUTTON_SCRIPTS) do
            self.__scripts[script] = true
        end
    end
    local mt = {}
    mt.__index = function(_, key)
        local m = rawget(self, "__methods")
        local hit = m[key]
        if hit ~= nil then
            return hit
        end
        METHOD_MISSES[key] = (METHOD_MISSES[key] or 0) + 1
        MISS_COUNT = MISS_COUNT + 1
        return nil
    end
    return setmetatable(self, mt)
end

buildMethods("Frame"); buildMethods("Button"); buildMethods("CheckButton")
buildMethods("StatusBar"); buildMethods("Slider")
buildMethods("FontString"); buildMethods("Texture")
-- Before the patch() calls below, so a shared patch (HasScript, HookScript,
-- SetScript, Show/Hide) also lands on GameTooltip. Patching it afterwards
-- would leave it with a permissive default HookScript that never raises, which
-- is precisely the mock defect this harness exists to avoid.
buildMethods("GameTooltip")

patch("GetName", function(f) return rawget(f, "__name") end)
patch("GetObjectType", function(f) return rawget(f, "__kind") end)
patch("GetParent", function(f) return rawget(f, "__parent") end)
patch("SetParent", function(f, p) rawset(f, "__parent", p) end)
patch("IsShown", function(f) return rawget(f, "__shown") == true end)
patch("IsVisible", function(f) return rawget(f, "__shown") == true end)
patch("Show", function(f) rawset(f, "__shown", true) end)
patch("Hide", function(f) rawset(f, "__shown", false) end)
patch("SetText", function(f, value) rawset(f, "__text", tostring(value or "")) end)
patch("GetText", function(f) return rawget(f, "__text") or "" end)

local function hasScript(f, script)
    local s = rawget(f, "__scripts")
    return (s and s[script] == true) or false
end

patch("SetScript", function(f, script, fn)
    if type(script) ~= "string" or script == "" then
        error("bad argument #2 to 'SetScript' (Usage: self:SetScript(scriptTypeName [, script]))", 2)
    end
    local scripts = rawget(f, "__scripts")
    if scripts then scripts[script] = true end
    rawset(f, "__script_" .. script, fn)
    return true
end)
-- GetScript returns the HOOKED handler when one exists. That is what the real
-- API does: HookScript chains, so the handler GetScript hands back runs the
-- original and then the hook. The mock used to read only __script_*, which
-- made every hooked script invisible to GetScript and would have turned
-- "drive the driver script" into "call nothing and report success".
patch("GetScript", function(f, script)
    local hooked = rawget(f, "__hook_" .. tostring(script))
    if hooked ~= nil then
        return hooked
    end
    return rawget(f, "__script_" .. tostring(script))
end)
patch("HasScript", hasScript)
patch("HookScript", function(f, script, fn)
    if not hasScript(f, script) then
        error("bad argument #2 to 'HookScript' (Usage: self:HookScript(scriptTypeName, script))", 2)
    end
    HOOK_LOG[#HOOK_LOG + 1] = tostring(rawget(f, "__name") or rawget(f, "__kind"))
        .. ":" .. tostring(script)
    rawset(f, "__hook_" .. tostring(script), fn)
    return true
end)
patch("RegisterEvent", function(f, event)
    local e = rawget(f, "__events")
    e[tostring(event)] = true
    EVENT_REGISTRY[#EVENT_REGISTRY + 1] = tostring(event)
    FRAMES_BY_REGISTRATION[#FRAMES_BY_REGISTRATION + 1] = f
    return true
end)
patch("UnregisterEvent", function(f, event)
    local e = rawget(f, "__events")
    e[tostring(event)] = nil
end)
patch("IsEventRegistered", function(f, event)
    local e = rawget(f, "__events")
    return e[tostring(event)] == true
end)

-- The mocked GameTooltip's declared script set is client-specific and the
-- difference is load-critical, so it is modelled from the real XML rather than
-- from a grep. Read with `git show origin/<branch>:<path>` and matched on `<On`
-- so the block forms (`<OnHide> ... </OnHide>`) are counted too -- a
-- self-closing-only pattern misses them and produces a table that looks
-- plausible and is wrong:
--
--   Classic family   Blizzard_GameTooltip/Classic/GameTooltip.xml
--       line 15  <OnLoad>
--       line 22  <OnTooltipSetUnit function="GameTooltip_OnTooltipSetUnit" />
--       line 23  <OnTooltipSetItem function="GameTooltip_OnTooltipSetItem" />
--       line 24  <OnTooltipSetSpell function="GameTooltip_OnTooltipSetSpell" />
--       line 25  <OnHide>
--       line 33  <OnUpdate function="GameTooltip_OnUpdate"/>
--       line 57  <OnShow>
--       line 111 <OnSizeChanged>
--     Identical on classic_era and classic_anniversary. NOTE: no
--     OnTooltipCleared and no OnEvent on the Classic GameTooltip -- so the
--     add-on's OnTooltipCleared hook is correctly skipped there, and this mock
--     has to say so or it would be testing a hook the client cannot take.
--
--   Mainline         Blizzard_GameTooltip/Mainline/GameTooltip.xml
--       GameTooltipTemplate (mixin="GameTooltipDataMixin", virtual)
--         line 26  <OnLoad inherit="prepend" function="GameTooltip_OnLoad"/>
--         line 27  <OnHide function="GameTooltip_OnHide"/>
--         line 28  <OnTooltipSetDefaultAnchor>
--         line 31  <OnTooltipCleared>
--         line 35  <OnEvent method="OnEvent"/>
--       <GameTooltip name="GameTooltip" inherits="GameTooltipTemplate"> (the
--       non-virtual instance _G.GameTooltip points at)
--         line 270 <OnLoad method="OnLoad"/>
--         line 271 <OnShow function="GameTooltip_OnShow"/>
--         line 272 <OnUpdate function="GameTooltip_OnUpdate"/>
--     and NO OnTooltipSetUnit, NO OnTooltipSetItem anywhere. Identical on
--     origin/live and origin/forever.
local function buildGameTooltip()
    local tooltip = newRegion("GameTooltip", "GameTooltip")
    local scripts = rawget(tooltip, "__scripts")
    for name in pairs({
        OnLoad = true, OnShow = true, OnHide = true, OnUpdate = true,
        OnSizeChanged = true,
    }) do
        scripts[name] = true
    end
    if TOOLTIP_SHAPE == "mainline" then
        scripts.OnEvent = true
        scripts.OnTooltipCleared = true
        scripts.OnTooltipSetDefaultAnchor = true
    else
        -- The base seed gives every frame an OnEvent, but the real Classic
        -- GameTooltip does not declare one. Clearing it keeps HasScript honest
        -- about this frame in particular.
        scripts.OnEvent = nil
        scripts.OnTooltipSetUnit = true
        scripts.OnTooltipSetItem = true
        scripts.OnTooltipSetSpell = true
    end
    return tooltip
end

local function baseEnv()
    REALG._G = REALG
    for k, v in pairs(STD) do REALG[k] = v end
    REALG.arg = arg
    REALG.time = os.time
    REALG.date = os.date
    REALG.CreateFrame = function(kind, name, parent, template)
        return newRegion(kind, name, parent, template)
    end
    REALG.UIParent = newRegion("Frame", "UIParent")
    REALG.DEFAULT_CHAT_FRAME = {
        AddMessage = function(_, line) CHAT[#CHAT + 1] = tostring(line) end,
    }
    REALG.SlashCmdList = {}
    REALG.C_Timer = {
        After = function() return true end,
        NewTicker = function() return { Cancel = noop } end,
    }
    REALG.hooksecurefunc = function(target, method)
        HOOK_LOG[#HOOK_LOG + 1] = "secure:" .. tostring(method or target)
        return true
    end
    REALG.geterrorhandler = function() return function() end end

    -- The client's WOW_PROJECT_* constants, and ONLY those. Anything not in
    -- this client's set is left undefined, which is the whole point.
    for key in pairs(REALG) do
        -- WOW_PROJECT_ID shares the WOW_PROJECT_ prefix but is a separate
        -- concept: the enum constants below come from the client's
        -- Constants.lua, WOW_PROJECT_ID is set separately (and is NOT set at
        -- all on the two Mainline clients, whose FrameXML never assigns it).
        if type(key) == "string" and string.sub(key, 1, 12) == "WOW_PROJECT_"
            and key ~= "WOW_PROJECT_ID" then
            REALG[key] = nil
        end
    end
    for key, value in pairs(CLIENT_PROFILE.constants) do
        REALG[key] = value
    end
    REALG.WOW_PROJECT_ID = CLIENT_PROFILE.project

    REALG.UnitExists = function() return false end
    REALG.UnitGUID = function() return nil end
    REALG.UnitIsPlayer = function() return false end
    REALG.UnitClass = function() return "Warrior", "WARRIOR" end
    REALG.UnitName = function() return "Smoke", nil end
    REALG.UnitRace = function() return "Human" end
    REALG.UnitLevel = function() return 70 end
    REALG.UnitFactionGroup = function() return "Alliance" end
    REALG.UnitCanAttack = function() return false end
    REALG.UnitIsConnected = function() return false end
    REALG.UnitIsSameServer = function() return true end
    REALG.UnitTokenFromGUID = function() return nil end
    REALG.GUIDIsPlayer = function() return false end
    REALG.CanInspect = function() return false end
    REALG.NotifyInspect = function() return nil end
    REALG.ClearInspectPlayer = noop
    REALG.GetInventoryItemLink = function() return nil end
    REALG.GetInventoryItemID = function() return nil end
    REALG.GetInventoryItemTexture = function() return nil end
    REALG.GetItemInfo = function() return nil end
    REALG.GetItemInfoInstant = function() return nil end
    REALG.GetItemCount = function() return 0 end
    REALG.GetItemQualityColor = function() return 1, 1, 1, "white" end
    REALG.GetWeaponEnchantInfo = function() return nil end
    REALG.IsEquippableItem = function() return false end
    REALG.IsEquipped = function() return false end
    REALG.GetSpecialization = function() return nil end
    REALG.GetSpecializationInfo = function() return nil end
    REALG.GetTalentInfoByTalentID = function() return nil end
    REALG.GetGuildInfo = function() return nil, nil end
    REALG.GetCursorPosition = function() return 0, 0 end
    REALG.GetScreenWidth = function() return 1920 end
    REALG.GetScreenHeight = function() return 1080 end
    REALG.GetCVar = function() return "" end
    REALG.GetCVarBool = function() return false end
    REALG.InCombatLockdown = function() return false end
    REALG.IsShiftKeyDown = function() return false end
    REALG.GetLocale = function() return "enUS" end
    REALG.GetBuildInfo = function()
        return "1.15.9", "70000", "d", CLIENT_PROFILE.interface, "us", "rel"
    end
    REALG.RAID_CLASS_COLORS = {
        WARRIOR = { r = 1, g = 0.8, b = 0.5 },
        MAGE = { r = 0.41, g = 0.8, b = 0.94 },
    }
    REALG.CUSTOM_CLASS_COLORS = nil
    REALG.NORMAL_FONT_COLOR = { r = 1, g = 1, b = 1 }
    REALG.GRAY_FONT_COLOR = { r = 0.5, g = 0.5, b = 0.5 }
    REALG.HIGHLIGHT_FONT_COLOR = { r = 1, g = 0.82, b = 0 }
    REALG.NORMAL_FONT_SIZE = 12
    REALG.GameFontNormal = {}
    REALG.GameFontHighlight = {}
    REALG.GameFontHighlightSmall = {}
    REALG.GameFontNormalLarge = {}
    REALG.GameFontDisableSmall = {}
    REALG.GameFontHighlightSmallWhite = {}
    REALG.GameFontNormalHuge = {}
    -- The UIDropDownMenu helpers Options.lua builds its media selectors from.
    -- All of them exist on every supported branch; omitting them is a mock gap,
    -- not an add-on defect, and it surfaces as an unrelated raise that buries
    -- the real signal.
    REALG.UIDropDownMenu_SetWidth = function() end
    REALG.UIDropDownMenu_SetText = function() end
    REALG.UIDropDownMenu_Initialize = function() end
    REALG.UIDropDownMenu_SetSelectedValue = function() end
    REALG.UIDropDownMenu_SetSelected = function() end
    REALG.UIDropDownMenu_GetSelectedValue = function() return nil end
    REALG.UIDropDownMenu_CreateFrame = function(_, name)
        return newRegion("Frame", name)
    end
    REALG.UIDropDownMenu_OnHide = noop
    REALG.UIDropDownMenu_Refresh = noop
    REALG.StaticPopupDialogs = {}
    REALG.StaticPopup_Show = function() end
    REALG.PlaySound = noop
    REALG.PlaySoundFile = noop
    REALG.ChatFrame_AddMessageEventFilter = function() return false end
    REALG.InterfaceOptions_AddCategory = function() end
    -- The modern Settings API. It is NOT optional on any supported client:
    -- Blizzard_Settings_Shared/Blizzard_Settings.lua defines
    -- Settings.RegisterCanvasLayoutCategory on origin/classic_era AND on
    -- origin/live, and the three Classic branches all ship the same
    -- Blizzard_Settings_Shared add-on. Modelling it as absent (as the phase-1
    -- harness did) sent Options.Initialize down its early `return false` path,
    -- which is a MOCK artefact dressed up as a finding: it hid the fact that
    -- the options category was never actually being exercised.
    REALG.Settings = {
        RegisterCanvasLayoutCategory = function() return { ID = 1, name = "mock" } end,
        RegisterCanvasLayoutSubcategory = function() return { ID = 2, name = "mock" } end,
        RegisterAddOnCategory = function() return true end,
        OpenToCategory = function() return true end,
    }
    REALG.UIPanelButtonTemplate = {}
    REALG.GameTooltip = buildGameTooltip()
    REALG.Minimap = newRegion("Frame", "Minimap")
    REALG.PaperDollFrame = newRegion("Frame", "PaperDollFrame")
    REALG.CharacterModelFrame = newRegion("Frame", "CharacterModelFrame")
    REALG.CharacterFrame = newRegion("Frame", "CharacterFrame")
    REALG.InspectFrame = newRegion("Frame", "InspectFrame")
    REALG.InspectModelFrame = newRegion("Frame", "InspectModelFrame")
    REALG.InspectPaperDollFrame = newRegion("Frame", "InspectPaperDollFrame")
    REALG.SettingsPanel = nil
    REALG.SetCVar = noop

    -- The legacy options API, present on every client and the fallback the
    -- nosettings variant exercises. Recorder, not a no-op: a no-op mock would
    -- let registerLegacyCategory "succeed" while registering nothing.
    REALG.InterfaceOptions_AddCategory = function(frame)
        LEGACY_CATEGORIES[#LEGACY_CATEGORIES + 1] = frame
        return true
    end
    REALG.InterfaceOptionsFrame = newRegion("Frame", "InterfaceOptionsFrame")
    -- The legacy frame's own surface. Without these the Options.Toggle probe
    -- records a widget-method MISS, and a miss is exactly the signal this
    -- harness uses to tell "the add-on reached for something the client does
    -- not have" from "the mock is incomplete".
    local legacyOptionsFrame = REALG.InterfaceOptionsFrame
    legacyOptionsFrame.OpenToCategory = function(_, key)
        LEGACY_OPENED[#LEGACY_OPENED + 1] = key
        return true
    end
    legacyOptionsFrame.GetCurrentCategory = function()
        return rawget(legacyOptionsFrame, "__currentCategory")
    end
    legacyOptionsFrame.Close = function()
        return true
    end
    REALG.InterfaceOptionsFrame_OpenToCategory = function(frame)
        LEGACY_OPENED[#LEGACY_OPENED + 1] = frame
        return true
    end
    -- Settings.RegisterCanvasLayoutCategory is defined on origin/classic_era,
    -- origin/classic_anniversary, origin/classic_titan, origin/live and
    -- origin/forever, so modelling it as present is the real world. The
    -- nosettings variant removes it to exercise the fallback.
    if VARIANT_PROFILE.dropSettings then
        REALG.Settings = nil
    end

    -- GetItemStats is a MAINLINE-FAMILY API. It is documented in
    -- Blizzard_APIDocumentationGenerated/ItemDocumentation.lua on origin/live
    -- (Retail) AND on origin/forever, and has zero hits anywhere in the
    -- Interface tree of classic_era, classic_anniversary and classic_titan.
    -- Phase 2's comments and README said "WoW Forever only"; that was wrong
    -- and it had the Retail harness run modelling a client without it. The
    -- add-on feature-detects it either way, so only the model and the docs
    -- were wrong -- but the model being wrong means the degraded path was
    -- never exercised on the one client where the capability probe would
    -- actually find it.
    if ITEM_STATS then
        REALG.GetItemStats = function(link, stat)
            if type(link) ~= "string" or type(stat) ~= "table" then
                return nil
            end
            -- Three sockets, matching the SOCKET_PREFIX accounting in
            -- Scanner.readSocketCapacity.
            stat.EMPTY_SOCKET1 = 1
            stat.EMPTY_SOCKET2 = 1
            stat.EMPTY_SOCKET3 = 1
            return stat
        end
    else
        REALG.GetItemStats = nil
    end
end

-- ---------------------------------------------------------------------------
-- Mocked TT_GS -- transcribed from TacoTip_Forever/gearscore.lua
-- ---------------------------------------------------------------------------
--
-- The delegation assertions only mean something if this mock is the real
-- algorithm, so it is transcribed rather than invented: GS_ItemTypes and
-- GS_Formula from gearscore.lua:141-183, scoreFromItemValues from
-- gearscore.lua:248-304. That includes the part the old Scoring copy was
-- missing -- the selection of formula table A above ilvl 120.
local GS_ITEM_TYPES = {
    INVTYPE_HEAD = { SlotMOD = 1.0 },
    INVTYPE_CHEST = { SlotMOD = 1.0 },
    INVTYPE_SHOULDER = { SlotMOD = 0.75 },
    INVTYPE_LEGS = { SlotMOD = 1.0 },
    INVTYPE_FEET = { SlotMOD = 0.75 },
    INVTYPE_WRIST = { SlotMOD = 0.5625 },
    INVTYPE_HAND = { SlotMOD = 0.75 },
    INVTYPE_CLOAK = { SlotMOD = 0.5625 },
    INVTYPE_NECK = { SlotMOD = 0.5625 },
    INVTYPE_FINGER = { SlotMOD = 0.5625 },
    INVTYPE_TRINKET = { SlotMOD = 0.5625 },
    INVTYPE_2HWEAPON = { SlotMOD = 2.0 },
    INVTYPE_WEAPONMAINHAND = { SlotMOD = 1.0 },
    INVTYPE_WEAPONOFFHAND = { SlotMOD = 1.0 },
    INVTYPE_WEAPON = { SlotMOD = 1.0 },
    INVTYPE_SHIELD = { SlotMOD = 1.0 },
    INVTYPE_HOLDABLE = { SlotMOD = 1.0 },
    INVTYPE_RANGED = { SlotMOD = 0.3164 },
    INVTYPE_RANGEDRIGHT = { SlotMOD = 0.3164 },
    INVTYPE_THROWN = { SlotMOD = 0.3164 },
    INVTYPE_RELIC = { SlotMOD = 0.3164 },
    INVTYPE_BODY = { SlotMOD = 0 },
}

local GS_FORMULA = {
    A = { [4] = { A = 91.4500, B = 0.6500 }, [3] = { A = 81.3750, B = 0.8125 },
        [2] = { A = 73.0000, B = 1.0000 } },
    B = { [4] = { A = 26.0000, B = 1.2000 }, [3] = { A = 0.7500, B = 1.8000 },
        [2] = { A = 8.0000, B = 2.0000 }, [1] = { A = 0.0000, B = 2.2500 } },
    C = { [4] = { A = 0.2500, B = 1.6275 } },
}

local floor = math.floor

local function scoreFromItemValues(itemLinkOut, ItemRarity, ItemLevel, ItemEquipLoc)
    if (itemLinkOut and ItemRarity and ItemLevel and ItemEquipLoc
        and GS_ITEM_TYPES[ItemEquipLoc]) then
        local QualityScale = 1
        local GearScore
        local Scale = 1.8618
        if (ItemRarity == 5) then
            QualityScale = 1.3
            ItemRarity = 4
        elseif (ItemRarity == 1) then
            QualityScale = 0.005
            ItemRarity = 2
        elseif (ItemRarity == 0) then
            QualityScale = 0.005
            ItemRarity = 2
        elseif (ItemRarity == 7) then
            ItemRarity = 3
            ItemLevel = 187.05
        end
        local Table
        if (ItemLevel < 100 and ItemRarity == 4) then
            Table = GS_FORMULA.C
        elseif (ItemLevel < 168 and ItemRarity == 4) then
            Table = GS_FORMULA.B
        elseif (ItemLevel < 148 and ItemRarity == 3) then
            Table = GS_FORMULA.B
        elseif (ItemLevel < 138 and ItemRarity == 2) then
            Table = GS_FORMULA.B
        elseif (ItemLevel <= 120) then
            Table = GS_FORMULA.B
        else
            Table = GS_FORMULA.A
        end
        if ((ItemRarity >= 2) and (ItemRarity <= 4)) then
            GearScore = floor(((ItemLevel - Table[ItemRarity].A) / Table[ItemRarity].B)
                * GS_ITEM_TYPES[ItemEquipLoc].SlotMOD * Scale * QualityScale)
            if (GearScore < 0) then
                GearScore = 0
            end
            return GearScore, ItemLevel
        end
    end
    return 0, 0
end

local GS_BRACKET = (CLIENT == "tbc") and 400 or
    ((CLIENT == "titanforge" or CLIENT == "retail") and 1000 or 200)
local GS_MAX = GS_BRACKET * 7

-- An item registry so the mock answers from a link the way the real one does.
local ITEMS = {}
local function registerItem(spec)
    ITEMS[spec.link] = spec
end

local function installTacoTip()
    -- The private table, published as _G[addOnName]. TacoTip's own main.lua
    -- does `local TT = _G[addOnName]`, and addOnName is the TOC name, so in the
    -- development tree this global is "TacoTip_Forever", not "TacoTip". The
    -- addon must find it either way.
    local TT = {}
    function TT.GetDefaults() return {} end
    function TT.RefreshCharacterFrame() return true end
    function TT.InitCharacterFrame() return true end
    function TT.RefreshInspectFrame() return true end
    function TT.InitInspectFrame() return true end
    function TT.RefreshOptionsUI() return true end
    function TT.ApplyTooltipAppearance() return true end
    REALG[TT_GLOBAL] = TT

    REALG.TT_GS = {
        BRACKET_SIZE = GS_BRACKET,
        MAX_SCORE = GS_MAX,
        GetItemScoreFromInfo = function(_, info)
            if type(info) ~= "table" then return 0, 0 end
            return scoreFromItemValues(info[2], info[3], info[4], info[9])
        end,
        GetItemScore = function(_, link)
            local spec = ITEMS[link]
            if not spec then return 0, 0 end
            return scoreFromItemValues(link, spec.quality, spec.level, spec.equipLoc)
        end,
        GetItemHunterScore = function(self, link, info)
            local score, level
            if info then
                score, level = self.GetItemScoreFromInfo(self, info)
            else
                score, level = self.GetItemScore(self, link)
            end
            local equipLoc = info and info[9] or (ITEMS[link] and ITEMS[link].equipLoc)
            if equipLoc == "INVTYPE_2HWEAPON" or equipLoc == "INVTYPE_WEAPONMAINHAND"
                or equipLoc == "INVTYPE_WEAPONOFFHAND" or equipLoc == "INVTYPE_WEAPON"
                or equipLoc == "INVTYPE_HOLDABLE" then
                score = floor(score * 0.3164)
            elseif equipLoc == "INVTYPE_RANGEDRIGHT" or equipLoc == "INVTYPE_RANGED" then
                score = floor(score * 5.3224)
            end
            return score, level
        end,
        GetScore = function() return 0, 0 end,
        GetQuality = function()
            return 0.5, 0.5, 0.5, "Trash"
        end,
    }
    REALG.TT_PAWN = { GetScore = function() return 0 end }
    REALG.TacoTipConfig = {
        show_gs_player = true,
        show_gs_character = true,
        show_avg_ilvl = true,
        show_pawn_player = true,
        show_talents = true,
        unlock_info_position = true,
        tip_style = 3,
    }
    REALG.TacoTip_GSCallback = function() end
    REALG.TacoTipDragButton = newRegion("Frame", "TacoTipDragButton")
    REALG.TacoTip_CustomPosEnable = false
    REALG.TACOTIP_LOCALE = {}
    REALG.TACOTIP_LOCALES = {}
    REALG.PawnClassicLastUpdatedVersion = 2.0538
    REALG.PawnLastUpdatedVersion = 2.1

    local loadedAddons = { TT_GLOBAL, ADDON_NAME, "SomeOtherAddon" }
    REALG.C_AddOns = {
        GetAddOnMetadata = function(name, field)
            if name == TT_GLOBAL and field == "Version" then
                return TACOTIP_VERSION
            end
            -- TacoTip_Forever/options.lua line 4 reads ## Title and line 452
            -- assigns it to its root options frame, so the legacy
            -- childFrame.parent value Extras has to match is this string.
            if name == TT_GLOBAL and field == "Title" then
                return "TacoTip"
            end
            if name == ADDON_NAME and field == "Version" then
                return "1.0.0"
            end
            return nil
        end,
        IsAddOnLoaded = function(name)
            return name == TT_GLOBAL or name == ADDON_NAME
        end,
        GetAddOns = function() return loadedAddons end,
    }
    REALG.GetAddOnMetadata = REALG.C_AddOns.GetAddOnMetadata
    REALG.IsAddOnLoaded = REALG.C_AddOns.IsAddOnLoaded
    REALG.GetAddOns = REALG.C_AddOns.GetAddOns
end

-- ---------------------------------------------------------------------------
-- One equipped item, so a real render produces real rows
-- ---------------------------------------------------------------------------
--
-- The driver assertions need a render that actually appends something; a scan
-- that completes with every metric blocked would make "no second render"
-- indistinguishable from "nothing was ever rendered", which is the exact shape
-- of green-but-vacuous this project has been bitten by.
--
-- This is the minimum a complete local scan needs:
--   UnitExists / UnitGUID / UnitIsPlayer / UnitClass / UnitLevel for "player"
--   GetInventoryItemID + GetInventoryItemLink for one slot, nil elsewhere
--   C_Item.IsItemDataCachedByID, C_Item.GetItemInfo, C_Item.GetDetailedItemLevelInfo
-- Every other slot answers nil/nil, which Scanner treats as confirmed-empty.
local HARNESS_PLAYER_GUID = "Player-1111-22223333"
-- Scoring.ParseEquippedLink requires EXACTLY 20 colon-separated fields with
-- "item" first, then id, permanent enchant, three gems and fourteen trailing
-- fields. A short link is not a near miss, it is "missing-item-payload" and
-- the whole scan goes unavailable -- which is what happened the first time
-- this was written without counting the fields.
local HARNESS_ITEM_LINK = "|cffffffff|Hitem:50003:0:41398:0:0"
    .. ":0:0:0:0:0:0:0:0:0:0:0:0:0:0|h[Harness Helm]|h|r"

local function installPlayerInventory()
    REALG.UnitExists = function(unit) return unit == "player" end
    REALG.UnitIsPlayer = function(unit) return unit == "player" end
    REALG.UnitGUID = function(unit)
        return unit == "player" and HARNESS_PLAYER_GUID or nil
    end
    REALG.GUIDIsPlayer = function(guid)
        return guid == HARNESS_PLAYER_GUID
    end
    REALG.UnitClass = function()
        return "Warrior", "WARRIOR", 1
    end
    REALG.UnitLevel = function(unit)
        return unit == "player" and 70 or 0
    end
    REALG.GetInventoryItemID = function(unit, slotID)
        if unit == "player" and slotID == 1 then
            return 50003
        end
        return nil
    end
    REALG.GetInventoryItemLink = function(unit, slotID)
        if unit == "player" and slotID == 1 then
            return HARNESS_ITEM_LINK
        end
        return nil
    end
    REALG.GetWeaponEnchantInfo = function() return nil end
    REALG.C_Item = {
        IsItemDataCachedByID = function() return true end,
        GetDetailedItemLevelInfo = function() return 200 end,
        -- The documented C_Item.GetItemInfo return order (see Scanner.lua's
        -- readMetadata): 1 name 2 link 3 quality 4 level 5 minLevel 6 type
        -- 7 subtype 8 stackCount 9 equipLoc 10 icon 11 sellPrice 12 classID
        -- 13 subclassID. Getting this order wrong makes every score read 0, so
        -- it is written out rather than abbreviated.
        GetItemInfo = function(link)
            return "Harness Helm", link, 4, 200, 1, 4, 1, 1, "INVTYPE_HEAD",
                "Interface\\Icons\\INV_Misc_Helm_01", 0, 4, 1
        end,
    }
    registerItem({
        link = HARNESS_ITEM_LINK,
        quality = 4,
        level = 200,
        equipLoc = "INVTYPE_HEAD",
    })
end

-- The inspector shape TacoTip ACTUALLY ships.
-- LibForeverInspector registers the "LibClassicInspector" alias at minor 2 and
-- defines NO Version() method anywhere in the file -- zero definitions, zero
-- assignments. That is why a gate which compared Version() to 21 could never
-- pass against the only library in the field.
local function installLibStubAndInspector()
    local LibStub = { libs = {}, minors = {}, minor = 2 }
    function LibStub:NewLibrary(major, minor)
        local oldminor = self.minors[major]
        if oldminor and oldminor >= minor then return nil end
        self.minors[major], self.libs[major] = minor, self.libs[major] or {}
        return self.libs[major], oldminor
    end
    function LibStub:GetLibrary(major, silent)
        if not self.libs[major] and not silent then
            error("Cannot find a library instance of " .. tostring(major) .. ".", 2)
        end
        return self.libs[major], self.minors[major]
    end
    setmetatable(LibStub, { __call = LibStub.GetLibrary })
    REALG.LibStub = LibStub

    local registrations = {}
    local lib = {
        RegisterCallback = function(owner, event, method)
            registrations[event] = registrations[event] or {}
            registrations[event][owner] = method
            return true
        end,
        UnregisterCallback = function(owner, event)
            if registrations[event] then
                registrations[event][owner] = nil
            end
            return true
        end,
        PlayerGUIDToUnitToken = function() return "player" end,
        GetInventoryItemMixin = function() return nil end,
        GetLastCacheTime = function() return 0, 0 end,
        CanInspect = function() return false end,
        GetTalentPoints = function() return 0 end,
    }
    -- Deliberately NO Version(): that is the real library's shape.
    local dropped = VARIANT_PROFILE.dropInspector
    if dropped then
        lib[dropped] = nil
    end
    REALG.LCI_REGISTRATIONS = registrations

    LibStub.libs["LibForeverInspector"] = lib
    LibStub.minors["LibForeverInspector"] = 2
    LibStub.libs["LibClassicInspector"] = lib
    LibStub.minors["LibClassicInspector"] = 2
end

-- ---------------------------------------------------------------------------
-- TOC
-- ---------------------------------------------------------------------------

local function readFile(path)
    local fh = io.open(path, "rb")
    if not fh then return nil end
    local data = fh:read("*a")
    fh:close()
    return data
end

local function parseToc(path)
    local raw = readFile(path)
    if type(raw) ~= "string" then return nil, nil end
    local meta, files = {}, {}
    for line in (raw .. "\n"):gmatch("(.-)\r?\n") do
        line = line:gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" and line:sub(1, 2) ~= "##" then
            files[#files + 1] = (line:gsub("\\", "/"))
        elseif line:sub(1, 2) == "##" then
            local key, value = line:match("^##%s*([^:]+):%s*(.*)$")
            if key then
                meta[key:gsub("%s+$", "")] = value
            end
        end
    end
    return meta, files
end

out(("== TacoTip_Extras harness ==\n"))
out(("   client                     : %s (%s), interface %s\n")
    :format(CLIENT_PROFILE.label, CLIENT, tostring(CLIENT_PROFILE.interface)))
out(("   variant                    : %s\n"):format(VARIANT))
out(("   TacoTip version reported   : %s\n"):format(TACOTIP_VERSION))
out(("   TacoTip private global     : %s\n"):format(TT_GLOBAL))
out(("   GameTooltip script set     : %s\n"):format(TOOLTIP_SHAPE))
out(("   GetItemStats installed     : %s\n"):format(tostring(ITEM_STATS)))
local tocMeta, tocFiles = parseToc(ROOT .. "/" .. ADDON_NAME .. ".toc")
if not check(type(tocMeta) == "table" and type(tocFiles) == "table",
    "TOC parses", "no " .. ADDON_NAME .. ".toc at " .. ROOT) then
    out("\n1 failed of 1 check\n")
    os.exit(1)
end

check(REALG.io.open(ROOT .. "/" .. ADDON_NAME .. ".toc", "r") ~= nil,
    "TOC filename equals add-on folder name",
    "WoW requires it; a mismatch means the add-on never loads at all")
check(tocMeta.Version == "1.0.0",
    "TOC ## Version is 1.0.0", "got " .. tostring(tocMeta.Version))
check(tocMeta.Dependencies == "TacoTip_Forever, TacoTip" or tocMeta.Dependencies == "TacoTip_Forever" or tocMeta.Dependencies == "TacoTip",
    "TOC ## Dependencies includes TacoTip_Forever", "got " .. tostring(tocMeta.Dependencies))
check(tocMeta.SavedVariables == "TacoTipExtrasDB",
    "TOC ## SavedVariables is TacoTipExtrasDB",
    "got " .. tostring(tocMeta.SavedVariables))
check(type(tocMeta.IconTexture) == "string"
    and tocMeta.IconTexture:find("Interface\\AddOns\\TacoTip_Extras\\", 1, true) ~= nil,
    "TOC ## IconTexture points at Interface\\AddOns\\TacoTip_Extras\\",
    "got " .. tostring(tocMeta.IconTexture))

-- Compare the raw value. Do not fold whitespace through gsub() into the
-- comparison: a call inside an operator expression is not reliably truncated
-- to one value, and comparing the substitution COUNT to a string is a test
-- that can never pass for the right reason.
local WANTED_INTERFACES = "11509, 20506, 38002, 16001, 110002, 110100, 110200, 120000, 120100"
check((tocMeta.Interface or "") == WANTED_INTERFACES,
    "TOC ## Interface lists all supported clients",
    "got '" .. tostring(tocMeta.Interface) .. "'")

check(tocFiles[1] == "Core.lua", "Core.lua is first in the TOC",
    "got " .. tostring(tocFiles[1]))
local ORDER = { "Core.lua", "Scoring.lua", "Cache.lua", "Scanner.lua",
    "TacoTipAdapter.lua", "Tooltips.lua", "Frames.lua", "Minimap.lua",
    "Options.lua" }
local orderOK, orderDetail = true, ""
for index = 1, #tocFiles do
    local expected = ORDER[index]
    if expected == nil then
        orderOK, orderDetail = false,
            ("unexpected extra file at position %d: %s"):format(index, tostring(tocFiles[index]))
        break
    end
    if tocFiles[index] ~= expected then
        orderOK, orderDetail = false,
            ("position %d: want %s, got %s"):format(index, expected, tostring(tocFiles[index]))
        break
    end
end
check(orderOK, "TOC load order is the reviewed 9-file order", orderDetail)

-- ---------------------------------------------------------------------------
-- Load
-- ---------------------------------------------------------------------------

out(("\n-- load every TOC file, in TOC order --\n"))

baseEnv()
installTacoTip()
installLibStubAndInspector()
installPlayerInventory()

out(("\n-- environment fidelity --\n"))

-- The mocked client must model what the branch ACTUALLY declares. These are
-- the two facts the whole four-client matrix turns on, so each one is asserted
-- against the mock itself rather than trusted: a mock that silently kept the
-- old model would let every driver and socket assertion below pass for the
-- wrong reason.
check((TOOLTIP_SHAPE == "classic")
        == (rawget(REALG.GameTooltip, "__scripts").OnTooltipSetUnit == true),
    "mocked GameTooltip declares OnTooltipSetUnit iff this client is Classic-family",
    "tooltip shape=" .. TOOLTIP_SHAPE
        .. " declared=" .. tostring(rawget(REALG.GameTooltip, "__scripts").OnTooltipSetUnit))
check((TOOLTIP_SHAPE == "classic")
        == (rawget(REALG.GameTooltip, "__scripts").OnTooltipSetItem == true),
    "mocked GameTooltip declares OnTooltipSetItem iff this client is Classic-family",
    "tooltip shape=" .. TOOLTIP_SHAPE)
check((rawget(REALG.GameTooltip, "__scripts").OnTooltipCleared == true)
        == (TOOLTIP_SHAPE == "mainline"),
    "mocked GameTooltip declares OnTooltipCleared iff this client is Mainline",
    "tooltip shape=" .. TOOLTIP_SHAPE
        .. " declared="
        .. tostring(rawget(REALG.GameTooltip, "__scripts").OnTooltipCleared))
check(rawget(REALG.GameTooltip, "__scripts").OnUpdate == true,
    "mocked GameTooltip declares OnUpdate on every client (the portable hook point)")
check(CLIENT_PROFILE.itemStats == BRANCH_HAS_GET_ITEM_STATS[CLIENT],
    "the client's GetItemStats model matches the FrameXML evidence",
    "model says " .. tostring(CLIENT_PROFILE.itemStats)
        .. ", FrameXML says " .. tostring(BRANCH_HAS_GET_ITEM_STATS[CLIENT])
        .. " -- GetItemStats is documented on origin/live AND origin/forever")
check((CLIENT_PROFILE.driver == "unit-hook")
        == BRANCH_DECLARES_TOOLTIP_SET_UNIT[CLIENT],
    "the client's driver model matches the GameTooltip.xml evidence",
    "model says '" .. tostring(CLIENT_PROFILE.driver)
        .. "', GameTooltip.xml declares OnTooltipSetUnit = "
        .. tostring(BRANCH_DECLARES_TOOLTIP_SET_UNIT[CLIENT]))
check((type(REALG.GetItemStats) == "function") == ITEM_STATS,
    "mocked GetItemStats presence matches the branch, not the old 'Forever only' model",
    "branch has it=" .. tostring(CLIENT_PROFILE.itemStats)
        .. " variant removes it=" .. tostring(VARIANT_PROFILE.forceNoItemStats == true))

-- Self-check on the mock: the constants present must be EXACTLY the client's.
local expectedConstants = {}
for key in pairs(CLIENT_PROFILE.constants) do expectedConstants[key] = true end
local actualConstants, unexpectedConstants = {}, {}
for key in pairs(REALG) do
    if type(key) == "string" and string.sub(key, 1, 12) == "WOW_PROJECT_"
        and key ~= "WOW_PROJECT_ID" then
        actualConstants[key] = true
        if not expectedConstants[key] then
            unexpectedConstants[#unexpectedConstants + 1] = key
        end
    end
end
check(#unexpectedConstants == 0,
    "environment defines no WOW_PROJECT_* constant this client does not",
    "extra: " .. table.concat(unexpectedConstants, " ")
        .. " (a client that does not define a constant makes nil == nil true)")
local missingConstants = {}
for key in pairs(expectedConstants) do
    if not actualConstants[key] then
        missingConstants[#missingConstants + 1] = key
    end
end
check(#missingConstants == 0,
    "environment defines every WOW_PROJECT_* constant this client does",
    "missing: " .. table.concat(missingConstants, " "))


check(type(REALG.GetItemStats) == "function" or not ITEM_STATS,
    "GetItemStats presence matches the client profile",
    "client has it=" .. tostring(CLIENT_PROFILE.itemStats)
        .. " variant removes it=" .. tostring(VARIANT_PROFILE.forceNoItemStats == true))

-- The options-registration API this run is supposed to exercise. A harness
-- that always modelled Settings would never reach the legacy arm, and an
-- arm that is never reached is an arm that ships untested.
check((type(REALG.Settings) == "table") ~= (VARIANT_PROFILE.dropSettings == true),
    "mocked Settings API matches what this variant asked for",
    "dropSettings=" .. tostring(VARIANT_PROFILE.dropSettings == true)
        .. " Settings=" .. type(REALG.Settings))

local RESERVED = {
    TacoTip = true, TT = true, TT_GS = true, TT_PAWN = true,
    TacoTipConfig = true, TACOTIP_LOCALE = true, TacoTipDragButton = true,
    TacoTip_CustomPosEnable = true, TacoTip_GSCallback = true,
    SlashCmdList = true, [TT_GLOBAL] = true,
}
local reservedBefore = {}
for key in pairs(RESERVED) do
    reservedBefore[key] = REALG[key]
end

local namespace = {}
local loadErrors = {}

for index, relative in ipairs(tocFiles) do
    local path = ROOT .. "/" .. relative
    local chunk, loadErr = loadfile(path)
    if not chunk then
        loadErrors[#loadErrors + 1] = relative .. ": " .. tostring(loadErr)
        check(false, "load " .. relative)
    else
        local ok, runErr = pcall(chunk, ADDON_NAME, namespace)
        if ok then
            check(true, ("load %-22s (#%d/%d)"):format(relative, index, #tocFiles))
        else
            loadErrors[#loadErrors + 1] = relative .. ": " .. tostring(runErr)
            check(false, "load " .. relative, runErr)
        end
    end
end
check(#loadErrors == 0, "no TOC file raised during load",
    table.concat(loadErrors, "\n          "))

out(("\n-- namespace resolution --\n"))
for _, key in ipairs({ "Core", "Scanner", "Scoring", "Cache", "TacoTipAdapter",
    "Tooltips", "Frames", "Minimap", "Options" }) do
    check(type(namespace[key]) == "table", "namespace." .. key .. " resolved",
        "got " .. type(namespace[key]))
end

out(("\n-- global collision audit --\n"))
local collisions = {}
for key in pairs(RESERVED) do
    if REALG[key] ~= reservedBefore[key] then
        collisions[#collisions + 1] = key
    end
end
check(#collisions == 0, "add-on replaced none of TacoTip's reserved globals",
    "replaced: " .. table.concat(collisions, ", "))

out(("\n-- saved variables (pre-ADDON_LOADED) --\n"))
check(REALG.TacoTipExtrasDB == nil,
    "TacoTipExtrasDB absent until ADDON_LOADED (as the client supplies it)",
    "got " .. type(REALG.TacoTipExtrasDB))
check(REALG.TacoTipGearScoreEnhancerDB == nil,
    "legacy TacoTipGearScoreEnhancerDB not written",
    "still set: " .. type(REALG.TacoTipGearScoreEnhancerDB))

-- ---------------------------------------------------------------------------
-- Fire ADDON_LOADED
-- ---------------------------------------------------------------------------

out(("\n-- ADDON_LOADED (initialize) --\n"))

local Adapter = namespace.TacoTipAdapter

local dispatched = 0
local initErrors = {}

local function fireEvent(event, ...)
    local seen = {}
    for _, frame in ipairs(FRAMES_BY_REGISTRATION) do
        if type(frame) == "table" and not seen[frame] then
            seen[frame] = true
            if type(frame.IsEventRegistered) == "function"
                and frame:IsEventRegistered(event) then
                dispatched = dispatched + 1
                local script = frame:GetScript("OnEvent")
                if type(script) == "function" then
                    local ok, err = pcall(script, frame, event, ...)
                    if not ok then
                        initErrors[#initErrors + 1] = event .. ": " .. tostring(err)
                    end
                end
            end
        end
    end
end

out(("   (frames created while loading: %d)\n"):format(FRAMES_CREATED))
local okInit = pcall(fireEvent, "ADDON_LOADED", ADDON_NAME)

-- Each sub-initializer is re-entered directly, under pcall, so the harness sees
-- all of them rather than only the first. With the guards in place this is a
-- reachability probe, not a crash report -- but it must now be silent, and any
-- message it produces is a FAILURE, not a banner.
out(("\n-- sub-initializers (must all reach without raising) --\n"))

local settings = (type(REALG.TacoTipExtrasDB) == "table")
    and REALG.TacoTipExtrasDB.settings or nil
local probeFailures = {}
for _, name in ipairs({ "Tooltips", "Frames", "Options", "Minimap" }) do
    local module = namespace[name]
    if type(module) ~= "table" or type(module.Initialize) ~= "function" then
        probeFailures[#probeFailures + 1] = name .. ": no Initialize"
        out(("   RAISE %-10s (no Initialize)\n"):format(name))
    else
        local ok, err = pcall(module.Initialize, settings)
        if ok and err ~= false then
            out(("   ok    %-10s -> %s\n"):format(name, tostring(err)))
        else
            local message = tostring(err)
            probeFailures[#probeFailures + 1] = name .. ": " .. message
            out(("   RAISE %-10s -> %s\n"):format(name, message))
        end
    end
end

out(("\n-- initialize dispatch --\n"))

check(okInit, "ADDON_LOADED dispatch itself did not raise",
    table.concat(initErrors, "\n          "))
check(dispatched > 0, "at least one frame handled ADDON_LOADED",
    "dispatched=" .. tostring(dispatched))

-- THE REGRESSION GUARD THAT REPLACES THE "KNOWN GAPS" BANNER.
--
-- Two unguarded HookScript calls used to be printed here under a banner and
-- the run still passed:
--   Tooltips.lua:981  GameTooltip:HookScript("OnTooltipSetUnit"/"OnTooltipSetItem")
--                     -- those scripts exist only on the Classic family.
--   Options.lua:334   attachHelp -> owner:HookScript("OnEnter"/"OnLeave") on a
--                     bare Frame, which declares only OnEvent/OnHide/OnLoad/
--                     OnShow/OnUpdate. EVERY client.
-- Both are now guarded, so an empty set is the ONLY acceptable answer. A
-- reminder that prints the defect and still reports green is how a known crash
-- shipped in the first place.
local allRaises = {}
for _, message in ipairs(initErrors) do
    allRaises[#allRaises + 1] = message
end
for _, failure in ipairs(probeFailures) do
    allRaises[#allRaises + 1] = failure
end
check(#allRaises == 0,
    "no sub-initializer raised on " .. CLIENT_PROFILE.label
        .. " / " .. TOOLTIP_SHAPE .. " tooltip",
    table.concat(allRaises, "\n          "))
check(#initErrors == 0, "the ADDON_LOADED handler itself raised nothing",
    table.concat(initErrors, "\n          "))

-- The surface has to WORK on both families, not merely avoid crashing.
--
-- Guarding the hooks is only half the fix: on Mainline, GameTooltip declares
-- neither OnTooltipSetUnit nor OnTooltipSetItem -- the single occurrence of
-- either name on origin/live and origin/forever is
-- Blizzard_SharedXML/UI.xsd, an XML SCHEMA listing the script names a frame
-- MAY declare -- so a guard alone would leave the tooltip surface silently
-- dead on two of the five clients while every load assertion stayed green.
--
-- So assert the hook that was actually taken, per family, from the add-on's own
-- report rather than from the absence of a crash. "Did not raise" is not
-- evidence the feature works; this is.
local hookedScripts = {}
for _, entry in ipairs(HOOK_LOG) do
    if type(entry) == "string" then
        local frameName, script = entry:match("^([^:]+):(.+)$")
        if frameName == "GameTooltip" and script then
            hookedScripts[script] = true
        end
    end
end

do
    local driver = type(namespace.Tooltips) == "table"
        and type(namespace.Tooltips.GetDriverState) == "function"
        and namespace.Tooltips.GetDriverState() or nil
    out(("   tooltip driver            : mode=%s armed=%s\n")
        :format(tostring(driver and driver.mode), tostring(driver and driver.pollArmed)))
    out(("   GameTooltip hooks taken   : %s\n")
        :format(table.concat(sortedKeys(hookedScripts), ", ")))

    if EXPECTED_DRIVER == "unit-hook" then
        check(hookedScripts.OnTooltipSetUnit == true,
            "Classic family: OnTooltipSetUnit is hooked (the script the client declares)",
            "hooks taken: " .. table.concat(sortedKeys(hookedScripts), ", "))
        check(hookedScripts.OnUpdate == nil,
            "Classic family: the OnUpdate poll is NOT even hooked",
            "hooks taken: " .. table.concat(sortedKeys(hookedScripts), ", ")
                .. " -- both drivers live at once would be able to double-apply")
        check(driver ~= nil and driver.mode == "unit-hook",
            "Classic family: the add-on reports the unit-hook driver",
            "got " .. tostring(driver and driver.mode))
        check(driver ~= nil and driver.pollArmed == false,
            "Classic family: the poll is disarmed",
            "armed=" .. tostring(driver and driver.pollArmed))
    else
        check(hookedScripts.OnTooltipSetUnit == nil,
            "Mainline: OnTooltipSetUnit is NOT hooked (the client does not declare it)",
            "hooks taken: " .. table.concat(sortedKeys(hookedScripts), ", ")
                .. " -- hooking it would have raised on a real client")
        check(hookedScripts.OnTooltipSetItem == nil,
            "Mainline: OnTooltipSetItem is NOT hooked either",
            "hooks taken: " .. table.concat(sortedKeys(hookedScripts), ", "))
        check(hookedScripts.OnUpdate == true,
            "Mainline: the portable OnUpdate driver IS hooked instead",
            "hooks taken: " .. table.concat(sortedKeys(hookedScripts), ", "))
        check(driver ~= nil and driver.mode == "poll",
            "Mainline: the add-on reports the poll driver",
            "got " .. tostring(driver and driver.mode))
    end

    check(hookedScripts.OnHide == true,
        "OnHide is hooked on both families (it is the poll's disarm signal)",
        "hooks taken: " .. table.concat(sortedKeys(hookedScripts), ", "))
    if EXPECTED_DRIVER == "poll" then
        check(hookedScripts.OnShow == true,
            "Mainline: OnShow is hooked (it is what arms the poll)",
            "hooks taken: " .. table.concat(sortedKeys(hookedScripts), ", "))
        check(hookedScripts.OnTooltipCleared == true,
            "Mainline: OnTooltipCleared is hooked (second disarm signal)",
            "hooks taken: " .. table.concat(sortedKeys(hookedScripts), ", "))
    else
        -- The Classic GameTooltip declares no OnTooltipCleared, so the add-on
        -- must skip it rather than raise.
        check(hookedScripts.OnTooltipCleared == nil,
            "Classic family: OnTooltipCleared is skipped (that client does not declare it)",
            "hooks taken: " .. table.concat(sortedKeys(hookedScripts), ", "))
    end
end

-- ---------------------------------------------------------------------------
-- Driving the tooltip surface end to end
-- ---------------------------------------------------------------------------
--
-- Everything below drives the REAL add-on: a real local scan through the real
-- Scanner, a real tooltip through the real driver script, against the real
-- mocked client. Nothing here reaches into module internals to fake a result.
out(("\n-- driving the tooltip surface --\n"))

local GameTooltipFrame = REALG.GameTooltip
local Tooltips = namespace.Tooltips
local Scanner = namespace.Scanner

local function fireScript(frame, scriptName, ...)
    local handler = frame:GetScript(scriptName)
    if type(handler) ~= "function" then
        return false
    end
    local ok, err = pcall(handler, frame, ...)
    check(ok, "script " .. scriptName .. " ran without raising", err)
    return true
end

-- 1. Publish a complete local scan. Core.RequestLocalScan defers the scan to
--    the event frame's OnUpdate, so that is what has to be driven too.
--
--    Everything below this point is gated on the adapter having ACCEPTED
--    TacoTip. In the `older` and `nocaps` runs it correctly refuses, the
--    tooltip surface is released, and there is nothing to drive -- so driving
--    it anyway would assert that a correctly-refused run renders rows.
local SURFACE_ACTIVE = Adapter.IsTooltipSurfaceActive()
check(EXPECT_SUPPORTED == SURFACE_ACTIVE,
    "the tooltip surface is active exactly when the adapter gate accepts",
    "expected supported=" .. tostring(EXPECT_SUPPORTED)
        .. ", IsTooltipSurfaceActive=" .. tostring(SURFACE_ACTIVE))

if not SURFACE_ACTIVE then
    out("   (the gate refuses this run, so the driver render assertions below\n")
    out("    do not apply -- the surface is released by design)\n")
end

if SURFACE_ACTIVE then
local scheduled = false
fireEvent("PLAYER_ENTERING_WORLD")
for _, frame in ipairs(FRAMES_BY_REGISTRATION) do
    if type(frame) == "table" and type(frame.GetScript) == "function"
        and type(frame:GetScript("OnUpdate")) == "function" then
        fireScript(frame, "OnUpdate")
        scheduled = true
    end
end
check(scheduled, "the deferred local scan was driven")

local current = type(Scanner) == "table" and Scanner.GetCurrent()
    and Scanner.GetCurrent() or nil
check(type(current) == "table" and current.status == "complete",
    "the local scan reached a COMPLETE state",
    "status=" .. tostring(current and current.status)
        .. " reason=" .. tostring(current and current.reason))

-- 2. Show the tooltip for that player, the way the client does: SetUnit
--    clears and rebuilds the lines, then the client adds its own, then Show.
--    Order matters. On Mainline TooltipDataHandlerMixin:InternalProcessInfo
--    runs ProcessLines and the postcalls and only THEN calls Show, and
--    OnUpdate does not fire on a hidden frame -- which is precisely why the
--    poll driver can never see a never-laid-out tooltip.
GameTooltipFrame:SetUnit("player")
GameTooltipFrame:AddLine("Name")
GameTooltipFrame:AddLine("Level 70")
GameTooltipFrame:Show()
fireScript(GameTooltipFrame, "OnShow")

-- 3. Drive whichever driver this client selected, twice.
local UNIT_SCRIPT = "OnTooltipSetUnit"
local DRIVE_SCRIPT = (EXPECTED_DRIVER == "unit-hook") and UNIT_SCRIPT or "OnUpdate"

local function driverState()
    return Tooltips.GetDriverState()
end

local beforeFirst = driverState()
local addedBefore = #GAME_TOOLTIP_ADDED
fireScript(GameTooltipFrame, DRIVE_SCRIPT)
local afterFirst = driverState()
local addedAfterFirst = #GAME_TOOLTIP_ADDED
local linesAfterFirst = GameTooltipFrame:NumLines()

check(afterFirst.renders > beforeFirst.renders,
    "first " .. DRIVE_SCRIPT .. " tick rendered",
    "renders " .. tostring(beforeFirst.renders) .. " -> " .. tostring(afterFirst.renders))
check(afterFirst.rows > beforeFirst.rows,
    "the render actually appended rows (not just a no-op render)",
    "rows " .. tostring(beforeFirst.rows) .. " -> " .. tostring(afterFirst.rows)
        .. ", lines added " .. tostring(addedAfterFirst - addedBefore))
check(linesAfterFirst > 2,
    "the tooltip gained more than the two lines the client added",
    "NumLines=" .. tostring(linesAfterFirst))

-- 4. Idempotence: five more ticks with nothing changed.
fireScript(GameTooltipFrame, DRIVE_SCRIPT)
fireScript(GameTooltipFrame, DRIVE_SCRIPT)
fireScript(GameTooltipFrame, DRIVE_SCRIPT)
fireScript(GameTooltipFrame, DRIVE_SCRIPT)
fireScript(GameTooltipFrame, DRIVE_SCRIPT)
local afterRepeat = driverState()

check(afterRepeat.renders == afterFirst.renders,
    "five unchanged ticks cause NO second render",
    "renders " .. tostring(afterFirst.renders) .. " -> " .. tostring(afterRepeat.renders))
check(#GAME_TOOLTIP_ADDED == addedAfterFirst,
    "five unchanged ticks add NO further lines",
    "lines added " .. tostring(addedAfterFirst) .. " -> " .. tostring(#GAME_TOOLTIP_ADDED))

-- 5. The gate must not be vacuous. A tick after an EXTERNAL line lands must
--    render again, or "no second render" would be true because the gate never
--    fires at all.
GameTooltipFrame:AddLine("some other add-on added this")
local addedBeforeExternal = #GAME_TOOLTIP_ADDED
fireScript(GameTooltipFrame, DRIVE_SCRIPT)
local afterExternal = driverState()
check(afterExternal.renders == afterFirst.renders + 1,
    "the change gate is not vacuous: an externally added line forces a re-render",
    "renders " .. tostring(afterFirst.renders) .. " -> " .. tostring(afterExternal.renders)
        .. ", lines " .. tostring(addedBeforeExternal) .. " -> " .. tostring(#GAME_TOOLTIP_ADDED))

-- 6. Hide.
local workBeforeHide = afterExternal.pollWorkTicks
local rendersBeforeHide = afterExternal.renders
GameTooltipFrame:Hide()
fireScript(GameTooltipFrame, "OnHide")
local afterHide = driverState()
check(afterHide.bound == false,
    "hiding the tooltip drops the binding (no stale player binding survives)",
    "bound=" .. tostring(afterHide.bound))
if EXPECTED_DRIVER == "poll" then
    check(afterHide.pollArmed == false,
        "hiding the tooltip disarms the poll",
        "armed=" .. tostring(afterHide.pollArmed))
    fireScript(GameTooltipFrame, DRIVE_SCRIPT)
    fireScript(GameTooltipFrame, DRIVE_SCRIPT)
    fireScript(GameTooltipFrame, DRIVE_SCRIPT)
    local afterHiddenTicks = driverState()
    check(afterHiddenTicks.renders == rendersBeforeHide,
        "no render after hide",
        "renders " .. tostring(rendersBeforeHide)
            .. " -> " .. tostring(afterHiddenTicks.renders))
    check(afterHiddenTicks.pollWorkTicks == workBeforeHide,
        "a hidden tooltip costs no work at all (the armed gate holds)",
        "pollWorkTicks " .. tostring(workBeforeHide)
            .. " -> " .. tostring(afterHiddenTicks.pollWorkTicks)
            .. " (pollTicks " .. tostring(afterHiddenTicks.pollTicks) .. ")")
else
    -- The Classic family has no poll to disarm: OnTooltipSetUnit fires when a
    -- unit tooltip is built, which on a real client is BEFORE Show(). Driving
    -- it on a hidden tooltip is not a sequence that occurs, so the guarantee
    -- here is the dropped binding, checked above.
    --
    -- Drive OnUpdate anyway. Nothing hooked it, so fireScript finds no handler
    -- -- and the assertion is that the poll body is simply not reachable on
    -- this client, rather than merely idle.
    local rendersBeforeStray = afterHide.renders
    fireScript(GameTooltipFrame, "OnUpdate")
    local afterStray = driverState()
    check(afterStray.renders == rendersBeforeStray,
        "driving OnUpdate on the Classic family renders nothing",
        "renders " .. tostring(rendersBeforeStray)
            .. " -> " .. tostring(afterStray.renders))
    check(afterStray.pollTicks == 0,
        "the poll body never executed a single tick on the Classic family",
        "pollTicks=" .. tostring(afterStray.pollTicks))
end

-- 7. Clear. On Mainline this is the second disarm signal, and it is a script
--    the Mainline GameTooltipTemplate really does declare. The Classic
--    GameTooltip does NOT declare OnTooltipCleared, so there is nothing to
--    hook there and the guarantee it buys Mainline simply cannot be bought on
--    Classic -- which the harness states rather than papers over.
if EXPECTED_DRIVER == "poll" then
    GameTooltipFrame:Show()
    fireScript(GameTooltipFrame, "OnShow")
    GameTooltipFrame:ClearLines()
    fireScript(GameTooltipFrame, "OnTooltipCleared")
    local afterClear = driverState()
    check(afterClear.pollArmed == false,
        "Clear() disarms the poll through OnTooltipCleared",
        "armed=" .. tostring(afterClear.pollArmed))
    local rendersBeforeClearTicks = afterClear.renders
    local workBeforeClearTicks = afterClear.pollWorkTicks
    fireScript(GameTooltipFrame, DRIVE_SCRIPT)
    fireScript(GameTooltipFrame, DRIVE_SCRIPT)
    local afterClearTicks = driverState()
    check(afterClearTicks.renders == rendersBeforeClearTicks,
        "no render after Clear()",
        "renders " .. tostring(rendersBeforeClearTicks)
            .. " -> " .. tostring(afterClearTicks.renders))
    check(afterClearTicks.pollWorkTicks == workBeforeClearTicks,
        "a cleared tooltip costs no work at all",
        "pollWorkTicks " .. tostring(workBeforeClearTicks)
            .. " -> " .. tostring(afterClearTicks.pollWorkTicks))
else
    check(hookedScripts.OnTooltipCleared == nil,
        "Classic family: nothing hooks OnTooltipCleared, because that client "
            .. "declares no such script",
        "the Classic GameTooltip.xml has no OnTooltipCleared element")
end

-- 8. Re-show and re-drive: the surface must come back, which is the show /
--    hide / clear / re-show cycle the brief asks about.
GameTooltipFrame:SetUnit("player")
GameTooltipFrame:AddLine("Name")
GameTooltipFrame:Show()
fireScript(GameTooltipFrame, "OnShow")
local beforeReshow = driverState()
if EXPECTED_DRIVER == "poll" then
    check(beforeReshow.pollArmed == true,
        "re-showing re-arms the poll",
        "armed=" .. tostring(beforeReshow.pollArmed))
end
fireScript(GameTooltipFrame, DRIVE_SCRIPT)
local afterReshow = driverState()
check(afterReshow.rows > beforeReshow.rows,
    "the surface renders again after a show/hide/clear/re-show cycle",
    "rows " .. tostring(beforeReshow.rows) .. " -> " .. tostring(afterReshow.rows))

-- 9. An item tooltip must not inherit the player binding.
local rowsBeforeItem = afterReshow.rows
GameTooltipFrame:ClearLines()
GameTooltipFrame:AddLine("Some Item")
GameTooltipFrame:SetUnit(nil)
if fireScript(GameTooltipFrame, "OnTooltipSetItem", GameTooltipFrame) then
    local afterItem = driverState()
    check(afterItem.rows == rowsBeforeItem,
        "an item tooltip adds no enhancer rows",
        "rows " .. tostring(rowsBeforeItem) .. " -> " .. tostring(afterItem.rows))
    check(afterItem.bound == false,
        "an item tooltip drops the player binding",
        "bound=" .. tostring(afterItem.bound))
end
end -- SURFACE_ACTIVE

-- ---------------------------------------------------------------------------
-- Options registration
-- ---------------------------------------------------------------------------
out(("\n-- options registration --\n"))

local Options = namespace.Options
check(type(Options) == "table" and type(Options.Initialize) == "function",
    "namespace.Options resolved")

local legacyMode = VARIANT_PROFILE.dropSettings == true
local openedBefore = #LEGACY_OPENED
local openOK = Options.Open()
check(openOK == true,
    "Options.Open() reaches a category on " .. (legacyMode and "legacy" or "modern") .. " registration",
    "Open returned " .. tostring(openOK))
check(Options.Toggle() ~= false,
    "Options.Toggle() is usable on " .. (legacyMode and "legacy" or "modern") .. " registration")

if legacyMode then
    check(#LEGACY_CATEGORIES == 2,
        "the legacy path registered BOTH pages",
        "registered " .. tostring(#LEGACY_CATEGORIES))
    local mainPage = LEGACY_CATEGORIES[1]
    local equipmentPage = LEGACY_CATEGORIES[2]
    check(mainPage ~= nil and mainPage.name == "TacoTip Extras",
        "the main legacy page is named 'TacoTip Extras'",
        "name=" .. tostring(mainPage and mainPage.name))
    check(mainPage ~= nil and equipmentPage ~= nil
        and mainPage.parent == "TacoTip",
        "the main legacy page is parented to TacoTip's category",
        "parent=" .. tostring(mainPage and mainPage.parent))
    check(equipmentPage ~= nil and equipmentPage.parent == "TacoTip Extras",
        "the equipment legacy page is parented to this add-on's main page",
        "parent=" .. tostring(equipmentPage and equipmentPage.parent))
    check(#LEGACY_OPENED > openedBefore,
        "the legacy open path actually called InterfaceOptionsFrame_OpenToCategory",
        "open calls " .. tostring(#LEGACY_OPENED))
    check(LEGACY_OPENED[#LEGACY_OPENED] == mainPage,
        "the legacy open path opens THIS add-on's main page",
        "opened=" .. tostring(LEGACY_OPENED[#LEGACY_OPENED] and LEGACY_OPENED[#LEGACY_OPENED].name))
    check(type(mainPage.GetScript) == "function"
        and type(mainPage:GetScript("OnShow")) == "function"
        and type(equipmentPage:GetScript("OnShow")) == "function",
        "both legacy pages are usable panels (OnShow wired, so they refresh)")
    check(Options.Refresh() == true,
        "the legacy panel's controls refresh against real settings")
else
    check(#LEGACY_CATEGORIES == 0,
        "the modern path does not touch InterfaceOptions_AddCategory",
        "legacy registrations " .. tostring(#LEGACY_CATEGORIES))
end

out(("\n-- saved variables (post-ADDON_LOADED) --\n"))
check(type(REALG.TacoTipExtrasDB) == "table",
    "TacoTipExtrasDB created from an absent SavedVariables table",
    "got " .. type(REALG.TacoTipExtrasDB))
if type(REALG.TacoTipExtrasDB) == "table" then
    check(REALG.TacoTipExtrasDB.schema == 2,
        "TacoTipExtrasDB schema normalised to 2",
        "got " .. tostring(REALG.TacoTipExtrasDB.schema))
end
check(REALG.TacoTipGearScoreEnhancerDB == nil,
    "legacy TacoTipGearScoreEnhancerDB still never written")

-- ---------------------------------------------------------------------------
-- Adapter
-- ---------------------------------------------------------------------------

out(("\n-- adapter: capability gate --\n"))

local report = type(Adapter) == "table" and Adapter.GetCapabilityReport
    and Adapter.GetCapabilityReport() or nil
local supported, reason, fingerprint = "n/a", "n/a", "n/a"
if type(Adapter) == "table" and type(Adapter.GetCompatibility) == "function" then
    supported, reason, fingerprint = Adapter.GetCompatibility()
end

out(("   GetInternalReason()  = %s\n")
    :format(tostring(Adapter and Adapter.GetInternalReason and Adapter.GetInternalReason())))
out(("   resolved as          = %s\n")
    :format(tostring(report and report.tacoTipResolvedAs)))
out(("   tacoTip version      = %s (min %s)\n")
    :format(tostring(report and report.tacoTipVersion),
        tostring(report and report.minTacoTipVersion)))
out(("   missing capabilities = tt:[%s] lci:[%s]\n")
    :format(tostring(report and table.concat(report.tacoTipCapabilitiesMissing, ",")),
        tostring(report and table.concat(report.inspectorCapabilitiesMissing, ","))))

-- The resolver must find the private table under whatever name this run used,
-- including the development-tree name it must NOT have hardcoded.
check(report ~= nil and report.tacoTipGlobal == TT_GLOBAL,
    "adapter resolved the TacoTip private table as '" .. TT_GLOBAL .. "'",
    "got " .. tostring(report and report.tacoTipGlobal))
if VARIANT == "devname" then
    check(REALG.TacoTip == nil,
        "devname run really has no _G.TacoTip, so the scan did the work",
        "_G.TacoTip is " .. type(REALG.TacoTip))
end

check(report ~= nil and report.inspectorPublishedVersion == nil,
    "the real inspector still publishes no Version(), and the gate ignores it",
    "got " .. tostring(report and report.inspectorPublishedVersion))

if EXPECT_SUPPORTED then
    check(supported == true,
        "gate accepts TacoTip " .. TACOTIP_VERSION .. " with the real inspector",
        "reason was " .. tostring(reason))
    check(reason == nil, "accepted gate reports no reason",
        "reason was " .. tostring(reason))
    check(report ~= nil and #report.tacoTipCapabilitiesMissing == 0,
        "no TacoTip capability missing", "some are missing")
    check(report ~= nil and #report.inspectorCapabilitiesMissing == 0,
        "all " .. #GATE_INSPECTOR_CAPABILITIES .. " probed inspector capabilities present",
        "missing: " .. tostring(report
            and table.concat(report.inspectorCapabilitiesMissing, ",")))
    check(report ~= nil and report.versionAccepted == true,
        "reported version satisfies the minimum " .. GATE_MIN_VERSION)
elseif VARIANT == "older" then
    check(supported == false and reason == "tacotip-version-unsupported",
        "gate refuses TacoTip " .. TACOTIP_VERSION .. " (below minimum "
            .. GATE_MIN_VERSION .. ")",
        "got " .. tostring(supported) .. ", " .. tostring(reason))
elseif VARIANT == "nocaps" then
    check(supported == false and reason == "inspector-capability-unsupported",
        "gate refuses an inspector missing "
            .. tostring(VARIANT_PROFILE.dropInspector),
        "got " .. tostring(supported) .. ", " .. tostring(reason))
    check(report ~= nil
        and table.concat(report.inspectorCapabilitiesMissing, ",")
            == VARIANT_PROFILE.dropInspector,
        "the capability report names exactly the missing function",
        "missing: " .. tostring(report
            and table.concat(report.inspectorCapabilitiesMissing, ",")))
end

-- The mock must be able to answer differently, or the assertions above prove
-- nothing.
check(REALG.C_AddOns.GetAddOnMetadata(TT_GLOBAL, "Version") == TACOTIP_VERSION,
    "mock GetAddOnMetadata reports the version this run was asked for",
    "a mock that cannot vary cannot prove the gate reads it")

-- ---------------------------------------------------------------------------
-- Scoring: delegation to TT_GS
-- ---------------------------------------------------------------------------

out(("\n-- scoring: base score is TT_GS's, deltas are additive --\n"))

local Scoring = namespace.Scoring

local function cell(value) return { status = "complete", value = value } end
local function blocked(status, blockedReason)
    return { status = status, value = nil, reason = blockedReason }
end

-- A 20-field item link: item, id, enchant, 3 gems, then 14 trailing fields.
local function makeLink(itemID, enchant, g1, g2, g3)
    local fields = { "item", itemID, enchant, g1, g2, g3 }
    for _ = 7, 20 do fields[#fields + 1] = 0 end
    return "|cffffffff|H" .. table.concat(fields, ":") .. "|h[Item]|h|r"
end

local ENCHANT_MULTIPLIER = 1.05
local GEM_BONUS = 5

-- Two HEAD items at ilvl 200, quality 4 -- above the ilvl 120 line where
-- TacoTip switches from formula table B to table A, which is exactly the
-- region the old in-file formula got wrong.
local LINK_ENCHANTED = makeLink(50001, 3789, 0, 0, 0)
local LINK_GEMMED = makeLink(50002, 0, 41398, 41398, 0)
registerItem({ link = LINK_ENCHANTED, quality = 4, level = 200, equipLoc = "INVTYPE_HEAD" })
registerItem({ link = LINK_GEMMED, quality = 4, level = 200, equipLoc = "INVTYPE_HEAD" })

-- The unshifted GetItemInfo result TT_GS expects.
local function makeInfo(link, quality, level, equipLoc)
    return { "Item", link, quality, level, 1, "Armor", "Cloth", 1, equipLoc }
end

local REQUIRED_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }

local function occupiedSlot(link, itemID, enchant, g1, g2, g3, capacity)
    return {
        state = "occupied",
        itemID = cell(itemID),
        nativeLink = cell(link),
        quality = cell(4),
        scoringItemLevel = cell(200),
        effectiveItemLevel = cell(200),
        equipLoc = cell("INVTYPE_HEAD"),
        itemClassID = cell(4),
        itemSubclassID = cell(1),
        permanentEnchantID = cell(enchant),
        scoreGemIDs = cell({ g1, g2, g3 }),
        -- gemIDs must have EXACTLY `capacity` entries: Scoring.validateSockets
        -- rejects any index past capacity as a contradiction, which is correct
        -- (a socket list longer than its own capacity is incoherent data) and
        -- which a sloppy fixture silently trips.
        sockets = ITEM_STATS and cell({
            capacity = capacity,
            gemIDs = { g1, g2, g3 },
        }) or blocked("unavailable", "socket-capability-unavailable"),
        scopeCapablePhysicalRanged = cell(false),
        itemInfoValue = makeInfo(link, 4, 200, "INVTYPE_HEAD"),
    }
end

local revision = {
    classToken = cell("WARRIOR"),
    level = cell(70),
    socketCapability = cell(ITEM_STATS),
    slots = {},
}
for _, slotID in ipairs(REQUIRED_SLOTS) do
    revision.slots[slotID] = { state = "confirmed-empty" }
end
revision.slots[1] = occupiedSlot(LINK_ENCHANTED, 50001, 3789, 0, 0, 0, 3)
revision.slots[2] = occupiedSlot(LINK_GEMMED, 50002, 0, 41398, 41398, 0, 3)

local result = Scoring.Evaluate(revision, nil)
local enchanted = result.items[1]
local gemmed = result.items[2]

local expectedBase = REALG.TT_GS:GetItemScore(LINK_ENCHANTED)
local expectedGemmBase = REALG.TT_GS:GetItemScore(LINK_GEMMED)

out(("   TT_GS base(head ilvl200)   = %d\n"):format(expectedBase))
out(("   TT_GS base(head gemmed)    = %d\n"):format(expectedGemmBase))

check(enchanted.base.status == "complete"
    and enchanted.base.value == expectedBase,
    "Scoring's base for an item equals TT_GS:GetItemScore for the same item",
    "scoring=" .. tostring(enchanted.base.value)
        .. " TT_GS=" .. tostring(expectedBase))

-- A tripwire on the formula itself: at ilvl 200 TacoTip is on table A. The old
-- in-file copy only had table B and answered 269 here against TacoTip's 310.
-- If the numbers ever converge the harness mock has drifted from the library
-- and this test is measuring nothing.
check(expectedBase == 310,
    "mock TT_GS reproduces TacoTip's table-A score (310) at ilvl 200",
    "got " .. tostring(expectedBase)
        .. " -- if this changed, re-derive GS_FORMULA from gearscore.lua")

local expectedEnchanted = math.floor(expectedBase * ENCHANT_MULTIPLIER)
check(enchanted.current.status == "complete"
    and enchanted.current.value == expectedEnchanted,
    "enchant bonus is ADDITIVE on top of TT_GS's number (x1.05)",
    "got " .. tostring(enchanted.current.value)
        .. ", expected " .. tostring(expectedEnchanted))

local expectedGemmed = expectedGemmBase + 2 * GEM_BONUS
check(gemmed.current.status == "complete"
    and gemmed.current.value == expectedGemmed,
    "gem bonus is ADDITIVE on top of TT_GS's number (+5 per socket)",
    "got " .. tostring(gemmed.current.value)
        .. ", expected " .. tostring(expectedGemmed))

check(enchanted.missingEnchant.value == false
    and gemmed.missingEnchant.value == true,
    "missing-enchant detection still distinguishes the two items",
    "enchanted=" .. tostring(enchanted.missingEnchant.value)
        .. " gemmed=" .. tostring(gemmed.missingEnchant.value))

local expectedMissingDelta = expectedEnchanted - expectedBase
check(gemmed.missingEnchantDelta.status == "complete"
    and gemmed.missingEnchantDelta.value == expectedMissingDelta,
    "potential enchant delta = floor(base x 1.05) - base",
    "got " .. tostring(gemmed.missingEnchantDelta.value)
        .. ", expected " .. tostring(expectedMissingDelta))

check(result.metrics.baseGS.status == "complete"
    and result.metrics.baseGS.value == expectedBase + expectedGemmBase,
    "character base total is the sum of the delegated per-item scores",
    "got " .. tostring(result.metrics.baseGS.value)
        .. ", expected " .. tostring(expectedBase + expectedGemmBase))

check(result.metrics.gearScore.status == "complete"
    and result.metrics.gearScore.value == expectedEnchanted + expectedGemmed,
    "character current total adds every delta to the delegated base",
    "got " .. tostring(result.metrics.gearScore.value)
        .. ", expected " .. tostring(expectedEnchanted + expectedGemmed))

-- ---------------------------------------------------------------------------
-- Socket degradation where GetItemStats does not exist
-- ---------------------------------------------------------------------------

out(("\n-- socket path without GetItemStats --\n"))

if ITEM_STATS then
    check(gemmed.emptyScoreBearingSockets.status == "complete"
        and gemmed.emptyScoreBearingSockets.value == 1,
        "with GetItemStats, one empty socket is counted",
        "got " .. tostring(gemmed.emptyScoreBearingSockets.value))
    check(result.metrics.potentialGS.status == "complete",
        "with GetItemStats the potential total is complete",
        "status " .. tostring(result.metrics.potentialGS.status))
    out("   (this client has GetItemStats; run the nostats variant for the degraded path)\n")
else
    check(gemmed.current.status == "complete",
        "gem count still scores where GetItemStats is absent",
        "status " .. tostring(gemmed.current.status))
    check(gemmed.current.value == expectedGemmed,
        "the gem bonus is still applied from the item LINK without GetItemStats",
        "got " .. tostring(gemmed.current.value)
            .. ", expected " .. tostring(expectedGemmed))
    check(gemmed.emptyScoreBearingSockets.status ~= "complete",
        "empty socket count is omitted, not guessed",
        "status " .. tostring(gemmed.emptyScoreBearingSockets.status))
    check(gemmed.completion.status ~= "complete",
        "completion is omitted rather than reported as a wrong number",
        "status " .. tostring(gemmed.completion.status))
    check(result.metrics.potentialGS.status ~= "complete",
        "potential total is suppressed rather than wrong",
        "status " .. tostring(result.metrics.potentialGS.status))
    check(result.metrics.gearScore.status == "complete",
        "current total survives the degradation",
        "status " .. tostring(result.metrics.gearScore.status))
end

-- ---------------------------------------------------------------------------
-- Summary
-- ---------------------------------------------------------------------------

out(("\n-- summary --\n"))
out(("   fingerprint : %s\n"):format(tostring(fingerprint)))

local distinctEvents, eventSeen = 0, {}
for _, event in ipairs(EVENT_REGISTRY) do
    if not eventSeen[event] then
        eventSeen[event] = true
        distinctEvents = distinctEvents + 1
    end
end
out(("   frames created          : %d\n"):format(FRAMES_CREATED))
out(("   distinct events hooked  : %d\n"):format(distinctEvents))
out(("   chat lines emitted      : %d\n"):format(#CHAT))
for index = 1, math.min(#CHAT, 3) do
    out(("     %s\n"):format(tostring(CHAT[index])))
end

local missKeys = sortedKeys(METHOD_MISSES)
out(("   widget-method misses    : %d distinct\n"):format(#missKeys))
if #missKeys > 0 then
    local parts = {}
    for _, key in ipairs(missKeys) do
        parts[#parts + 1] = ("%s(x%d)"):format(tostring(key), METHOD_MISSES[key])
    end
    out(("     %s\n"):format(table.concat(parts, ", ")))
end

out(("\n-------------------------------------------------------------\n"))
if #failures == 0 then
    out(("%d checks, 0 failed\n"):format(checks))
    out(("  MATRIX: %s / %s / TacoTip %s / tt-global %s / supported=%s reason=%s\n")
        :format(CLIENT_PROFILE.label, VARIANT, TACOTIP_VERSION, TT_GLOBAL,
            tostring(supported), tostring(reason)))
    out("-------------------------------------------------------------\n")
    os.exit(0)
end

out(("%d checks, %d FAILED\n"):format(checks, #failures))
for _, name in ipairs(failures) do
    out(("  failed: %s\n"):format(name))
end
out("-------------------------------------------------------------\n")
os.exit(1)