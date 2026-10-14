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

-- Names published by CreateFrame, so a harness can look a named control up
-- without depending on the global being present for unrelated reasons.
local RAWL = {}
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
    SetAllPoints = noop,
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
    -- C-level engine methods. They have NO Lua definition in FrameXML on any
    -- branch (verified: Blizzard_SharedXML/BindingUtil.lua calls
    -- `selectedHighlight:SetShown(...)` on classic_era and forever alike),
    -- so a source grep for them finds nothing and wrongly suggests absence.
    -- Model them, or a perfectly valid call reads as a widget-method MISS and
    -- a raise -- which is how a mock gap gets reported as a product defect.
    SetShown = function(self, shown)
        self.__shown = shown and true or false
    end,
    Raise = function() end,
    Lower = function() end,
}

local FRAME_EXTRA = {
    -- NOTE: SetScript is REPLACED further down by the validating `patch`ed
    -- version, which stores handlers as `__script_<name>`. Do not define a
    -- competing SetScript here -- the later one wins, and a test reading the
    -- wrong field then fails for reasons that have nothing to do with the
    -- add-on.
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
    SetColorTexture = noop,
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
    Slider = FRAME_EXTRA, EditBox = FRAME_EXTRA, ScrollFrame = FRAME_EXTRA,
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
KINDS.EditBox = merge(FRAME_EXTRA, {
    GetText = function() return "" end, SetText = noop,
    HighlightText = noop, ClearFocus = noop, SetAutoFocus = noop,
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
    OnTextChanged = true, OnEscapePressed = true, OnEnterPressed = true,
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
    GetUnit = function(f)
        local u = rawget(f, "__unit")
        return u and "CharacterName", u, u and "Player-1111-22223333" or nil
    end,
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
buildMethods("StatusBar"); buildMethods("Slider"); buildMethods("EditBox")
buildMethods("ScrollFrame")
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
    -- Named frames are published as globals by the real client, and add-ons
    -- rely on that: a control created as CreateFrame("Button", "MyAddonFoo")
    -- is reachable as _G.MyAddonFoo and as /click MyAddonFoo in-game. This
    -- mock used to discard the name, so any assertion about a NAMED control
    -- read nil and could only ever fail -- which is how "the Options button is
    -- clickable" went untested rather than proven broken.
    REALG.CreateFrame = function(kind, name, parent, template)
        local region = newRegion(kind, name, parent, template)
        if type(name) == "string" and name ~= "" then
            RAWL[name] = region
            REALG[name] = region
        end
        return region
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
    if CLIENT == "retail" or CLIENT == "forever" then
        REALG.CharacterModelFrame = nil
        REALG.CharacterModelScene = newRegion("Frame", "CharacterModelScene", REALG.PaperDollFrame)
    else
        REALG.CharacterModelFrame = newRegion("Frame", "CharacterModelFrame", REALG.PaperDollFrame)
        REALG.CharacterModelScene = nil
    end
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
        local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
        if trimmed ~= "" and trimmed:sub(1, 2) ~= "##" then
            files[#files + 1] = (trimmed:gsub("\\", "/"))
        elseif trimmed:sub(1, 2) == "##" then
            local key, value = trimmed:match("^##%s*([^:]+):%s*(.*)$")
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
check(tocMeta.Version == "1.2.2",
    "TOC ## Version is 1.2.2", "got " .. tostring(tocMeta.Version))
check(tocMeta.Dependencies == "TacoTip",
    "TOC ## Dependencies is TacoTip", "got " .. tostring(tocMeta.Dependencies))
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
local WANTED_INTERFACES = "11509, 20506, 38002, 16001, 120100"
check((tocMeta.Interface or "") == WANTED_INTERFACES or (tocMeta.Interface or "") == "11509, 20506, 38002, 16001, 110002, 110100, 110200, 120000, 120100",
    "TOC ## Interface lists all supported clients",
    "got '" .. tostring(tocMeta.Interface) .. "'")

-- Load order has three invariants, not one:
--
--   * every Locale/*.lua precedes every file that binds
--     `local L = _G.TACOEXTRAS_LOCALE` at file scope (a bound local cannot be
--     rebound, so a locale file loaded afterwards is never seen);
--   * Locale/enUS.lua is LAST among the locales, because it defines
--     TacoExtrasApplyLocale() and performs the initial merge, so it needs every
--     other locale already registered;
--   * the reviewed 12-file addon order is unchanged after that block.
check(tocFiles[1] == "Locale/deDE.lua", "first TOC entry is the first locale file",
    "got " .. tostring(tocFiles[1]))

local ORDER = {
    "Locale/deDE.lua", "Locale/esES.lua", "Locale/esMX.lua", "Locale/frFR.lua",
    "Locale/itIT.lua", "Locale/koKR.lua", "Locale/ptBR.lua", "Locale/ruRU.lua",
    "Locale/zhCN.lua", "Locale/zhTW.lua", "Locale/enUS.lua",
    "Core.lua", "Scoring.lua", "Cache.lua", "RankDB.lua",
    "RankSync.lua", "Scanner.lua", "TacoTipAdapter.lua", "Tooltips.lua",
    "Frames.lua", "RankBrowser.lua", "Minimap.lua", "Options.lua" }
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
check(orderOK, "TOC load order is the 11-locale block followed by the reviewed 12-file order", orderDetail)

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

-- ---------------------------------------------------------------------------
-- Localization
-- ---------------------------------------------------------------------------

out(("\n-- localization --\n"))

local EX = REALG.TACOEXTRAS_LOCALES
local XL = REALG.TACOEXTRAS_LOCALE

check(type(EX) == "table", "TACOEXTRAS_LOCALES registry exists")
check(type(XL) == "table", "TACOEXTRAS_LOCALE merged table exists")
check(type(REALG.TacoExtrasApplyLocale) == "function", "TacoExtrasApplyLocale exposed")
check(type(REALG.TACOEXTRAS_ACTIVE_LOCALE) == "string", "TACOEXTRAS_ACTIVE_LOCALE recorded",
    "got " .. tostring(REALG.TACOEXTRAS_ACTIVE_LOCALE))

-- Every shipped locale must be registered. Read from the toc so the list cannot
-- drift from what actually loads.
local registered, unregistered = {}, {}
for index = 1, #tocFiles do
    local code = tocFiles[index]:match("^Locale/(%a+)%.lua$")
    if code then
        registered[#registered + 1] = code
        if type(EX[code]) ~= "table" then unregistered[#unregistered + 1] = code end
    end
end
check(#registered == 11, "TOC ships 11 locale files",
    "found " .. #registered .. ": " .. table.concat(registered, " "))
check(#unregistered == 0, "every locale in the TOC registered a table",
    "missing: " .. table.concat(unregistered, ", "))

-- Every key the enUS source defines must resolve in the merged table. This is
-- the invariant that matters, not a key count: it fails when a lookup the code
-- performs has nothing behind it.
local unresolved = {}
for key in pairs(EX["enUS"]) do
    if XL[key] == nil then unresolved[#unresolved + 1] = key end
end
check(#unresolved == 0, "every enUS key resolves in the merged table",
    table.concat(unresolved, ", "))

-- Locale parity: a shipped table must not carry a key enUS does not define,
-- which would mean a typo silently replacing a real label with raw text.
local strayByLocale = {}
for index = 1, #registered do
    local code = registered[index]
    local stray = {}
    for key in pairs(EX[code]) do
        if EX["enUS"][key] == nil then stray[#stray + 1] = key end
    end
    if #stray > 0 then
        table.sort(stray)
        strayByLocale[#strayByLocale + 1] = code .. ": " .. table.concat(stray, " ")
    end
end
check(#strayByLocale == 0, "no locale defines a key enUS does not",
    table.concat(strayByLocale, "; "))

-- Format-specifier safety: a translation that drops or invents a %d/%s renders
-- broken output or raises in string.format at the call site.
local specProblems = {}
for index = 1, #registered do
    local code = registered[index]
    for key, value in pairs(EX[code]) do
        local base = EX["enUS"][key]
        if type(base) == "string" and type(value) == "string" then
            local function count(spec)
                local total = 0
                for _ in value:gmatch(spec) do total = total + 1 end
                return total
            end
            local d1, d2 = count("%%?%d"), count("%%?%s")
            local b1, b2 = count("%%?%d"), count("%%?%s")
            if value ~= base and (d1 ~= b1 or d2 ~= b2) then
                specProblems[#specProblems + 1] = code .. "/" .. key
            end
        end
    end
end
check(#specProblems == 0, "translations preserve %d/%s specifier counts",
    table.concat(specProblems, ", "))

-- A shipped translation must actually DIFFER from English. Without this, a file
-- that silently failed to translate would pass every assertion above.
local untranslated = {}
local PROBE = { "MODE_DETAILED", "CURRENT_GS", "AVERAGE_ILVL", "COMPLETION",
    "MINIMAP_HINT_LEFT", "LB_TITLE", "LB_MY_RANK", "CLASS_WARRIOR",
    "HELP_ENABLED_HEADING", "OPT_TOOLTIP_MODE", "TIME_JUST_NOW" }
for index = 1, #registered do
    local code = registered[index]
    if code ~= "enUS" then
        local same = {}
        for _, key in ipairs(PROBE) do
            if EX[code][key] == EX["enUS"][key] then same[#same + 1] = key end
        end
        if #same == #PROBE then
            untranslated[#untranslated + 1] = code
        end
    end
end
check(#untranslated == 0, "each translation differs from English on the probe keys",
    "still identical: " .. table.concat(untranslated, ", "))

-- Script contamination. Key parity, specifier parity and "differs from English"
-- all pass on a translation containing a stray character from the WRONG script,
-- because the string is still non-empty, still has the right key, and still has
-- no format tokens. Mojibake of that shape is invisible to every other check --
-- it reached a Spanish file as a CJK glyph during authoring.
--
-- Rule per family, on DECODED CODEPOINTS, not on UTF-8 lead bytes.
--
-- Lead bytes cannot answer this question. German uses an en-dash, English uses a
-- typographic apostrophe, Russian uses an em-dash: all of those are General
-- Punctuation (U+2000-U+206F) and all of them encode as E2 80 xx -- the exact
-- lead byte CJK uses. A lead-byte rule flags all three as Chinese, and an
-- earlier version of this check did precisely that. So: decode to codepoints,
-- then range-check.
--
--   latin      -> Latin-1, Latin Extended-A and General Punctuation only.
--                 Cyrillic / Greek / Han / Hangul are contamination.
--   cyrillic   -> Cyrillic allowed. Han / Hangul are contamination. Must
--                 actually contain Cyrillic, or it is English with a flag.
--   cjk        -> Han, Hangul and CJK punctuation allowed, and Latin too
--                 (every CJK locale ships "GearScore", "iLvl", "TacoTip"
--                 untranslated). Cyrillic is contamination. Must actually
--                 contain Han or Hangul.
--
-- General Punctuation is allowed everywhere, including enUS: the apostrophe in
-- "player's" is U+2019 and predates this check.
local function decodeCodepoints(text)
    local points, index, length = {}, 1, #text
    while index <= length do
        local lead = text:byte(index)
        local point, width
        if lead < 0x80 then
            point, width = lead, 1
        elseif lead < 0xE0 then
            point = (lead - 0xC0) * 0x40 + ((text:byte(index + 1) or 0) - 0x80)
            width = 2
        elseif lead < 0xF0 then
            point = (lead - 0xE0) * 0x1000
                + (((text:byte(index + 1) or 0) - 0x80) * 0x40)
                + ((text:byte(index + 2) or 0) - 0x80)
            width = 3
        else
            point = (lead - 0xF0) * 0x40000
                + (((text:byte(index + 1) or 0) - 0x80) * 0x1000)
                + (((text:byte(index + 2) or 0) - 0x80) * 0x40)
                + ((text:byte(index + 3) or 0) - 0x80)
            width = 4
        end
        points[#points + 1] = point
        index = index + width
    end
    return points
end

local function inRange(point, low, high)
    return point >= low and point <= high
end

local function classifyPoint(point)
    -- Returns "punct", "latin", "cyrillic", "hangul", "han", or "other".
    if inRange(point, 0x0000, 0x00FF) then return "latin" end
    if inRange(point, 0x0100, 0x017F) then return "latin" end
    if inRange(point, 0x2000, 0x206F) then return "punct" end
    if inRange(point, 0x2070, 0x209F) then return "punct" end
    if inRange(point, 0x20A0, 0x20BF) then return "punct" end
    if inRange(point, 0x0400, 0x052F) then return "cyrillic" end
    if inRange(point, 0x0370, 0x03FF) then return "other" end
    if inRange(point, 0x1100, 0x11FF) then return "hangul" end
    if inRange(point, 0x3130, 0x318F) then return "hangul" end
    if inRange(point, 0xAC00, 0xD7AF) then return "hangul" end
    if inRange(point, 0x3000, 0x303F) then return "han" end
    if inRange(point, 0x3400, 0x4DBF) then return "han" end
    if inRange(point, 0x4E00, 0x9FFF) then return "han" end
    if inRange(point, 0xF900, 0xFAFF) then return "han" end
    if inRange(point, 0xFF00, 0xFFEF) then return "han" end
    -- Script-neutral symbols. Arrows, mathematical operators and geometric
    -- shapes are used as sort and delta markers, and Blizzard's own ▲/▼ sort
    -- arrows live in Geometric Shapes (U+25B2 / U+25BC). They read the same in
    -- every language, so they are legal everywhere and no translation can be
    -- "wrong script" for containing one.
    --
    -- This range check must sit ABOVE the final `return "other"`. A first pass
    -- checked only lead bytes, which cannot tell General Punctuation (U+2000-
    -- U+206F: the em dash, the curly apostrophe, German low quotes) from CJK --
    -- both encode as 0xE2 0x80 xx -- and reported the German and Russian files
    -- as contaminated.
    if inRange(point, 0x2190, 0x21FF) then return "symbol" end   -- Arrows
    if inRange(point, 0x2200, 0x22FF) then return "symbol" end   -- Math operators
    if inRange(point, 0x25A0, 0x25FF) then return "symbol" end   -- Geometric shapes
    if inRange(point, 0x2600, 0x26FF) then return "symbol" end   -- Misc symbols
    if inRange(point, 0x2700, 0x27BF) then return "symbol" end   -- Dingbats
    return "other"
end

-- What each family may legitimately contain.
local SCRIPT_ALLOWED = {
    latin    = { latin = true, punct = true, symbol = true },
    cyrillic = { latin = true, punct = true, symbol = true, cyrillic = true },
    cjk      = { latin = true, punct = true, symbol = true, han = true, hangul = true },
}
-- What each family must actually contain, or it is English wearing a flag.
local SCRIPT_REQUIRED = {
    latin    = nil,
    cyrillic = "cyrillic",
    cjk      = "han",
}
-- Hangul alone satisfies koKR, which has no Han at all.
local SCRIPT_ALT_REQUIRED = { cjk = "hangul" }

local SCRIPT_RULES = {
    deDE = "latin", esES = "latin", esMX = "latin", frFR = "latin",
    itIT = "latin", ptBR = "latin", ruRU = "cyrillic",
    koKR = "cjk", zhCN = "cjk", zhTW = "cjk",
}
local contaminated = {}
for index = 1, #registered do
    local code = registered[index]
    local rule = SCRIPT_RULES[code]
    if rule then
        local allowed = SCRIPT_ALLOWED[rule]
        local bad, seen = {}, {}
        for key, value in pairs(EX[code]) do
            if type(value) == "string" then
                for _, point in ipairs(decodeCodepoints(value)) do
                    local kind = classifyPoint(point)
                    seen[kind] = (seen[kind] or 0) + 1
                    if not allowed[kind] then
                        bad[#bad + 1] = ("%s(U+%04X=%s)"):format(key, point, kind)
                    end
                end
            end
        end
        local needed = SCRIPT_REQUIRED[rule]
        if needed and (not seen[needed])
            and not (SCRIPT_ALT_REQUIRED[rule] and seen[SCRIPT_ALT_REQUIRED[rule]]) then
            bad[#bad + 1] = "no " .. needed .. " anywhere"
        end
        if #bad > 0 then
            local unique, counted = {}, {}
            for _, entry in ipairs(bad) do
                if not counted[entry] then
                    counted[entry] = true
                    unique[#unique + 1] = entry
                end
            end
            table.sort(unique)
            contaminated[#contaminated + 1] = code .. ": " .. table.concat(unique, " ")
        end
    end
end
check(#contaminated == 0,
    "no translation carries a character from the wrong script",
    table.concat(contaminated, "; "))

-- Damaged text, banned in EVERY file including enUS.
--
-- U+FFFD REPLACEMENT CHARACTER is what a decoder writes for a byte it could not
-- read, so it marks mangled text rather than a translation. A zhTW value shipped
-- with "���" where one character belonged, and every other check here was green:
-- the key was present, the format specifiers matched, and U+FFFD lands outside
-- Han so it reads as damage rather than as Chinese.
--
-- "other" is banned for the same reason. Everything WoW needs is Latin,
-- General Punctuation, Cyrillic or Han/Hangul, so an unclassified codepoint is
-- never legitimate in any of these locales.
local damaged = {}
for index = 1, #registered do
    local code = registered[index]
    local bad = {}
    for key, value in pairs(EX[code]) do
        if type(value) == "string" then
            for _, point in ipairs(decodeCodepoints(value)) do
                if point == 0xFFFD then
                    bad[#bad + 1] = ("%s(U+FFFD)"):format(key)
                elseif classifyPoint(point) == "other" then
                    bad[#bad + 1] = ("%s(U+%04X)"):format(key, point)
                end
            end
        end
    end
    if #bad > 0 then
        table.sort(bad)
        damaged[#damaged + 1] = code .. ": " .. table.concat(bad, " ")
    end
end
check(#damaged == 0,
    "no locale file contains damaged or unclassified characters",
    table.concat(damaged, "; "))

-- Scoring.QualityColor -- the function RankBrowser has always called and that
-- did not exist.
--
-- The bug this guards against is specific: `type(scoring.QualityColor) ~= "function"`
-- meant every call fell through a defensive guard to a fallback, so the whole
-- leaderboard rendered in flat white and NOTHING raised. A missing function that
-- a caller guards for cannot fail loudly. So these assertions pin real return
-- values, not merely that the function exists.
do
    local Scoring = namespace.Scoring
    check(type(Scoring) == "table" and type(Scoring.QualityColor) == "function",
        "Scoring.QualityColor exists")

    local function colorAt(fraction)
        local r, g, b = Scoring.QualityColor(fraction)
        return ("%.2f,%.2f,%.2f"):format(r or -1, g or -1, b or -1)
    end

    -- The bands are ordered best-first and must be strictly monotonic: a better
    -- standing can never produce a lower band.
    check(colorAt(1.00) == "0.64,0.21,0.93", "fraction 1.00 is the top band", colorAt(1.00))
    check(colorAt(0.99) == "0.64,0.21,0.93", "fraction 0.99 is still the top band", colorAt(0.99))
    check(colorAt(0.98) ~= colorAt(0.99), "fraction 0.98 drops below the top band", colorAt(0.98))
    check(colorAt(0.95) ~= colorAt(0.94), "the 95% band boundary is honoured")
    check(colorAt(0.90) ~= colorAt(0.89), "the 90% band boundary is honoured")
    check(colorAt(0.75) ~= colorAt(0.74), "the 75% band boundary is honoured")

    -- No data must be muted, never bright: a wrong confident colour is worse
    -- than an obviously missing one.
    check(colorAt(nil) == "0.62,0.62,0.62", "an unknown fraction is muted", colorAt(nil))
    check(colorAt(0.10) == "0.62,0.62,0.62", "below every band is muted", colorAt(0.10))

    -- Out-of-range input clamps rather than returning nonsense.
    check(colorAt(5) == colorAt(1), "a fraction above 1 clamps to the top band")
    check(colorAt(-3) == colorAt(0), "a negative fraction clamps to the bottom")

    -- Percentile: the same rank means different things in different pool sizes.
    -- 1st of 20 is the top 5%; 1st of 2000 is the top 0.05%. Both are #1, but
    -- only the second is in the top 1% band -- this is the whole reason the
    -- scale takes a fraction rather than a rank.
    local r1 = { Scoring.QualityColor(Scoring.RankFraction(1, 20)) }
    local r2 = { Scoring.QualityColor(Scoring.RankFraction(1, 2000)) }
    check(r1[1] ~= nil and r2[1] ~= nil, "RankFraction feeds QualityColor")
    check(Scoring.RankFraction(1, 100) > Scoring.RankFraction(50, 100),
        "a better rank yields a larger fraction")
    check(Scoring.RankFraction(1, 1) == 1, "the only player is the top of the scale")
    check(Scoring.RankFraction(0, 100) == nil, "rank 0 is not a standing")
    check(Scoring.RankFraction(1, 0) == nil, "an empty pool has no percentile")
    check(Scoring.ScoreFraction(700, 700) == 1, "the best score in view is the top of the scale")
    check(Scoring.ScoreFraction(0, 700) == nil, "a zero score has no fraction")
    check(Scoring.ScoreFraction(700, 0) == nil, "an empty view has no fraction")

    -- The RANKING colour, pinned as values. The leaderboard's `#` column and the
    -- tooltip rank line both resolve through Scoring.RankColor, and a shared
    -- scale that drifts is exactly how the two disagreed: the tooltip read the
    -- raw percentile bands, so the best possible rank came out purple while the
    -- leaderboard badged it gold. Formatted like colorAt above, never with
    -- tostring: on Lua 5.3+ an integral float stringifies as "1.0", so a
    -- tostring comparison would pin the interpreter instead of the colour.
    local function rankColorOf(rank, total)
        local r, g, b = Scoring.RankColor(rank, total)
        return ("%.2f,%.2f,%.2f"):format(r or -1, g or -1, b or -1)
    end
    check(rankColorOf(1, 4000) == "1.00,0.84,0.00", "rank 1 is gold", rankColorOf(1, 4000))
    check(rankColorOf(2, 20) == "0.75,0.75,0.78",
        "rank 2 keeps the silver medal even where every place is top 5%", rankColorOf(2, 20))
    check(rankColorOf(3, 20) == "0.80,0.51,0.20",
        "rank 3 keeps the bronze medal", rankColorOf(3, 20))
    check(rankColorOf(4, 100) == "1.00,0.84,0.00",
        "the rest of the top 5% is gold too", rankColorOf(4, 100))
    check(rankColorOf(20, 100) == "1.00,1.00,1.00",
        "mid-pack takes the percentile band", rankColorOf(20, 100))
    check(rankColorOf(100, 100) == "0.62,0.62,0.62",
        "the bottom of a pool is muted, not gold", rankColorOf(100, 100))
    check(Scoring.RankColor(nil, 10) == nil, "an unknown rank has no colour")
    check(Scoring.RankColor(9, 0) == nil, "an empty pool has no colour")
end

-- In-place mutation. Every addon file binds `local L = _G.TACOEXTRAS_LOCALE` at
-- file scope, so a loader that REPLACED the table would leave those locals
-- pointing at a stale copy and the language setting would silently do nothing.
local boundBefore = XL
REALG.TacoTipConfig = REALG.TacoTipConfig or {}
REALG.TacoTipConfig.locale_override = "deDE"
REALG.TacoExtrasApplyLocale()
check(REALG.TACOEXTRAS_LOCALE == boundBefore,
    "ApplyLocale mutates TACOEXTRAS_LOCALE in place rather than replacing it")
check(REALG.TACOEXTRAS_ACTIVE_LOCALE == "deDE", "override selects deDE",
    "got " .. tostring(REALG.TACOEXTRAS_ACTIVE_LOCALE))
check(REALG.TACOEXTRAS_LOCALE["CURRENT_GS"] == EX["deDE"]["CURRENT_GS"],
    "merged table carries the German translation",
    "got " .. tostring(REALG.TACOEXTRAS_LOCALE["CURRENT_GS"]))

-- enGB is served by the enUS table.
REALG.TacoTipConfig.locale_override = "enGB"
REALG.TacoExtrasApplyLocale()
check(REALG.TACOEXTRAS_ACTIVE_LOCALE == "enUS", "enGB resolves to enUS",
    "got " .. tostring(REALG.TACOEXTRAS_ACTIVE_LOCALE))

-- A language we do not ship must fall back to English, never to raw keys.
REALG.TacoTipConfig.locale_override = "xxXX"
REALG.TacoExtrasApplyLocale()
check(REALG.TACOEXTRAS_ACTIVE_LOCALE == "enUS", "unshipped locale falls back to enUS",
    "got " .. tostring(REALG.TACOEXTRAS_ACTIVE_LOCALE))
check(REALG.TACOEXTRAS_LOCALE["CURRENT_GS"] == EX["enUS"]["CURRENT_GS"],
    "fallback yields English text, not nil")

-- A PARTIAL table must degrade key by key, not wholesale.
REALG.TACOEXTRAS_LOCALES["xxXX"] = { CURRENT_GS = "ONLY-ONE-KEY" }
REALG.TacoTipConfig.locale_override = "xxXX"
REALG.TacoExtrasApplyLocale()
check(REALG.TACOEXTRAS_LOCALE["CURRENT_GS"] == "ONLY-ONE-KEY",
    "partial locale supplies the keys it defines")
check(REALG.TACOEXTRAS_LOCALE["COMPLETION"] == EX["enUS"]["COMPLETION"],
    "partial locale inherits English for keys it omits")

-- Restore the client default for the tests that follow.
REALG.TACOEXTRAS_LOCALES["xxXX"] = nil
REALG.TacoTipConfig.locale_override = nil
REALG.TacoExtrasApplyLocale()

out(("\n-- namespace resolution --\n"))
for _, key in ipairs({ "Core", "Scanner", "Scoring", "Cache", "TacoTipAdapter",
    "Tooltips", "Frames", "Minimap", "Options", "RankDB", "RankSync", "RankBrowser" }) do
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
    if type(REALG.TacoTipExtrasDB.settings) == "table" then
        local s = REALG.TacoTipExtrasDB.settings
        check(s.tooltip ~= nil and s.tooltip.mode == "Compact",
            "default tooltip mode is Compact",
            "got " .. tostring(s.tooltip and s.tooltip.mode))
        check(s.equipmentDisplay ~= nil and s.equipmentDisplay.mode == "Detailed",
            "default equipment display mode is Detailed",
            "got " .. tostring(s.equipmentDisplay and s.equipmentDisplay.mode))
    end
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

do
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

local shortLink = "|cffffffff|Hitem:50001:0:41398:0:0:0:0:0:0:0:0:0:0:0:0|h[Short Item]|h|r"
local parsedShort, shortReason = Scoring.ParseEquippedLink(shortLink, 50001)
check(parsedShort ~= nil and parsedShort.itemID == 50001,
    "ParseEquippedLink accepts variable-length modern link (< 20 fields)",
    "reason: " .. tostring(shortReason))

local longLink = "|cffffffff|Hitem:50001:0:41398:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0|h[Long Item]|h|r"
local parsedLong, longReason = Scoring.ParseEquippedLink(longLink, 50001)
check(parsedLong ~= nil and parsedLong.itemID == 50001,
    "ParseEquippedLink accepts variable-length modern link (> 20 fields)",
    "reason: " .. tostring(longReason))

if CLIENT == "retail" then
    local expectedRaw = (200 + 200) / 16
    local expectedDisplay = math.floor(expectedRaw + 0.5)
    check(result.metrics.averageItemLevel.status == "complete"
        and result.metrics.averageItemLevel.value.display == expectedDisplay,
        "Retail averageItemLevel divisor is 16 slots (not 17)",
        "got " .. tostring(result.metrics.averageItemLevel.value and result.metrics.averageItemLevel.value.display)
            .. ", expected " .. tostring(expectedDisplay))
else
    local expectedRaw = (200 + 200) / 17
    local expectedDisplay = math.floor(expectedRaw + 0.5)
    check(result.metrics.averageItemLevel.status == "complete"
        and result.metrics.averageItemLevel.value.display == expectedDisplay,
        "Classic/Forever averageItemLevel divisor is 17 slots",
        "got " .. tostring(result.metrics.averageItemLevel.value and result.metrics.averageItemLevel.value.display)
            .. ", expected " .. tostring(expectedDisplay))
end

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
end

-- ---------------------------------------------------------------------------
-- Remote Inspection / INVENTORY_READY
-- ---------------------------------------------------------------------------

out(("\n-- remote inspection: INVENTORY_READY handling and InspectFrame unit resolution --\n"))

do
local Cache = namespace.Cache
local REMOTE_GUID_A = "Player-9999-00112233"
local REMOTE_GUID_B = "Player-9999-00445566"
local REMOTE_GUID_C = "Player-9999-00778899"

local origUnitExists = REALG.UnitExists
local origUnitIsPlayer = REALG.UnitIsPlayer
local origUnitGUID = REALG.UnitGUID
local origGUIDIsPlayer = REALG.GUIDIsPlayer
local origUnitClass = REALG.UnitClass
local origUnitLevel = REALG.UnitLevel
local origGetInventoryItemID = REALG.GetInventoryItemID
local origGetInventoryItemLink = REALG.GetInventoryItemLink

REALG.UnitExists = function(unit)
    return unit == "player" or unit == "target" or unit == "party1"
end
REALG.UnitIsPlayer = function(unit)
    return unit == "player" or unit == "target" or unit == "party1"
end
REALG.UnitClass = function(unit)
    if unit == "target" or unit == "party1" then
        return "Mage", "MAGE", 8
    end
    return "Warrior", "WARRIOR", 1
end
REALG.UnitLevel = function(unit)
    return (unit == "player" or unit == "target" or unit == "party1") and 70 or 0
end

local remoteUnitMap = {
    target = REMOTE_GUID_A,
    party1 = REMOTE_GUID_C,
}

REALG.UnitGUID = function(unit)
    if unit == "player" then return HARNESS_PLAYER_GUID end
    return remoteUnitMap[unit]
end

REALG.GUIDIsPlayer = function(guid)
    return guid == HARNESS_PLAYER_GUID or guid == REMOTE_GUID_A or guid == REMOTE_GUID_B or guid == REMOTE_GUID_C
end

REALG.GetInventoryItemID = function(unit, slotID)
    if (unit == "player" or unit == "target" or unit == "party1") and slotID == 1 then
        return 50003
    end
    return nil
end

REALG.GetInventoryItemLink = function(unit, slotID)
    if (unit == "player" or unit == "target" or unit == "party1") and slotID == 1 then
        return HARNESS_ITEM_LINK
    end
    return nil
end

-- 1. Omitted isInspect and unit (as LibForeverInspector on Retail/Forever passes)
-- Target currently holds REMOTE_GUID_A.
remoteUnitMap.target = REMOTE_GUID_A
REALG.InspectFrame.unit = "target"
local handledA = Scanner.HandleInventoryReady("INVENTORY_READY", REMOTE_GUID_A)
check(handledA == true,
    "HandleInventoryReady accepts omitted isInspect and resolves unit from target/InspectFrame",
    "got " .. tostring(handledA))
local cachedA = Cache.Get(REMOTE_GUID_A)
check(type(cachedA) == "table" and cachedA.state == "complete",
    "remote scan for REMOTE_GUID_A reached complete state",
    "state=" .. tostring(cachedA and cachedA.state))

-- 2. Explicit isInspect = true and unit = "target" (as LibClassicInspector passes)
remoteUnitMap.target = REMOTE_GUID_B
local handledB = Scanner.HandleInventoryReady("INVENTORY_READY", REMOTE_GUID_B, true, "target")
check(handledB == true,
    "HandleInventoryReady accepts explicit isInspect=true and explicit unit",
    "got " .. tostring(handledB))
local cachedB = Cache.Get(REMOTE_GUID_B)
check(type(cachedB) == "table" and cachedB.state == "complete",
    "remote scan for REMOTE_GUID_B reached complete state",
    "state=" .. tostring(cachedB and cachedB.state))

-- 3. Target is NOT the unit; InspectFrame.unit is "party1" holding REMOTE_GUID_C
remoteUnitMap.target = nil
REALG.InspectFrame.unit = "party1"
local handledC = Scanner.HandleInventoryReady("INVENTORY_READY", REMOTE_GUID_C)
check(handledC == true,
    "HandleInventoryReady resolves unit from InspectFrame.unit when target is empty",
    "got " .. tostring(handledC))
local cachedC = Cache.Get(REMOTE_GUID_C)
check(type(cachedC) == "table" and cachedC.state == "complete",
    "remote scan for REMOTE_GUID_C reached complete state",
    "state=" .. tostring(cachedC and cachedC.state))

-- 4. Explicit isInspect = false is rejected
local rejected = Scanner.HandleInventoryReady("INVENTORY_READY", REMOTE_GUID_A, false, "target")
check(rejected == false,
    "HandleInventoryReady rejects explicit isInspect=false",
    "got " .. tostring(rejected))

-- Restore mocks
REALG.UnitExists = origUnitExists
REALG.UnitIsPlayer = origUnitIsPlayer
REALG.UnitGUID = origUnitGUID
REALG.GUIDIsPlayer = origGUIDIsPlayer
REALG.UnitClass = origUnitClass
REALG.UnitLevel = origUnitLevel
REALG.GetInventoryItemID = origGetInventoryItemID
REALG.GetInventoryItemLink = origGetInventoryItemLink
REALG.InspectFrame.unit = nil
end

-- ---------------------------------------------------------------------------
-- GearScore Server RankDB, P2P Sync & Leaderboard Browser
-- ---------------------------------------------------------------------------

do
    out(("\n-- RankDB: Validation --\n"))
    local RankDB = namespace.RankDB

    -- 1. RankDB: Validation
    local badRecord1 = { guid = "", name = "Test", gs = 1000 }
    local ok1, err1 = RankDB.ValidateRecord(badRecord1)
    check(ok1 == nil and type(err1) == "string",
        "RankDB.ValidateRecord rejects empty GUID",
        "got " .. tostring(ok1))

    local badRecord2 = { guid = "Player-1-001", name = "", gs = 1000 }
    local ok2, err2 = RankDB.ValidateRecord(badRecord2)
    check(ok2 == nil and type(err2) == "string",
        "RankDB.ValidateRecord rejects empty name",
        "got " .. tostring(ok2))

    local badRecord3 = { guid = "Player-1-001", name = "Test", gs = -5 }
    local ok3, err3 = RankDB.ValidateRecord(badRecord3)
    check(ok3 == nil and type(err3) == "string",
        "RankDB.ValidateRecord rejects negative GearScore",
        "got " .. tostring(ok3))

    local badRecord4 = { guid = "Player-1-001", name = "Test", gs = 25000 }
    local ok4, err4 = RankDB.ValidateRecord(badRecord4)
    check(ok4 == nil and type(err4) == "string",
        "RankDB.ValidateRecord rejects excessive GearScore (> 15000)",
        "got " .. tostring(ok4))

    local validRec = {
        guid = "Player-1-001",
        name = "Arthas",
        faction = "Alliance",
        class = "PALADIN",
        classID = 2,
        specName = "Retribution",
        gs = 4500,
        ilvl = 142.5,
        timestamp = 100000,
    }
    local cleanRec = RankDB.ValidateRecord(validRec)
    check(type(cleanRec) == "table" and cleanRec.name == "Arthas" and cleanRec.gs == 4500,
        "RankDB.ValidateRecord accepts and sanitizes valid record",
        "clean=" .. tostring(cleanRec and cleanRec.name))
end

do
    out(("\n-- RankDB: Storage, Sorting & Lookups --\n"))
    local RankDB = namespace.RankDB
    local testRealm = "TestRealm"
    local testNow = REALG.time and REALG.time() or 1000000
    local validRec = {
        guid = "Player-1-001",
        name = "Arthas",
        faction = "Alliance",
        class = "PALADIN",
        classID = 2,
        specName = "Retribution",
        gs = 4500,
        ilvl = 142.5,
        timestamp = testNow - 100,
    }
    local storeOK, storeStatus = RankDB.StoreRecord(validRec, testRealm)
    check(storeOK == true and storeStatus == "stored",
        "RankDB.StoreRecord stores new valid record",
        "status=" .. tostring(storeStatus))

    local olderRec = {
        guid = "Player-1-001",
        name = "Arthas",
        faction = "Alliance",
        class = "PALADIN",
        classID = 2,
        gs = 4000,
        timestamp = testNow - 200,
    }
    local olderOK, olderStatus = RankDB.StoreRecord(olderRec, testRealm)
    check(olderOK == true and olderStatus == "up-to-date",
        "RankDB.StoreRecord enforces last-write-wins (rejects older timestamp)",
        "status=" .. tostring(olderStatus))

    local newerRec = {
        guid = "Player-1-001",
        name = "Arthas",
        faction = "Alliance",
        class = "PALADIN",
        classID = 2,
        gs = 4800,
        timestamp = testNow - 50,
    }
    local newerOK, newerStatus = RankDB.StoreRecord(newerRec, testRealm)
    check(newerOK == true and newerStatus == "stored",
        "RankDB.StoreRecord updates record when newer timestamp arrives",
        "status=" .. tostring(newerStatus))

    -- Populate remaining players
    RankDB.StoreRecord({ guid = "Player-1-002", name = "Uther", faction = "Alliance", class = "PALADIN", gs = 5200, ilvl = 150, timestamp = testNow - 100 }, testRealm)
    RankDB.StoreRecord({ guid = "Player-1-003", name = "Thrall", faction = "Horde", class = "SHAMAN", gs = 5100, ilvl = 148, timestamp = testNow - 100 }, testRealm)
    RankDB.StoreRecord({ guid = "Player-1-004", name = "Sylvanas", faction = "Horde", class = "HUNTER", gs = 5300, ilvl = 155, timestamp = testNow - 100 }, testRealm)
    RankDB.StoreRecord({ guid = "Player-1-005", name = "Jaina", faction = "Alliance", class = "MAGE", gs = 4900, ilvl = 145, timestamp = testNow - 100 }, testRealm)

    local allLeaderboard, allCount = RankDB.GetLeaderboard(testRealm, "all")
    check(allCount == 5, "RankDB.GetLeaderboard('all') returns all 5 players", "got " .. tostring(allCount))
    check(allLeaderboard[1].name == "Sylvanas" and allLeaderboard[2].name == "Uther" and allLeaderboard[5].name == "Arthas",
        "RankDB.GetLeaderboard sorts descending by GearScore",
        "1st=" .. tostring(allLeaderboard[1] and allLeaderboard[1].name) .. ", 5th=" .. tostring(allLeaderboard[5] and allLeaderboard[5].name))

    local allyLeaderboard, allyCount = RankDB.GetLeaderboard(testRealm, "alliance")
    check(allyCount == 3, "RankDB.GetLeaderboard('alliance') returns 3 Alliance players", "got " .. tostring(allyCount))
    check(allyLeaderboard[1].name == "Uther" and allyLeaderboard[2].name == "Jaina" and allyLeaderboard[3].name == "Arthas",
        "RankDB.GetLeaderboard('alliance') sorted correctly",
        "1st=" .. tostring(allyLeaderboard[1] and allyLeaderboard[1].name))

    local hordeLeaderboard, hordeCount = RankDB.GetLeaderboard(testRealm, "horde")
    check(hordeCount == 2, "RankDB.GetLeaderboard('horde') returns 2 Horde players", "got " .. tostring(hordeCount))
    check(hordeLeaderboard[1].name == "Sylvanas" and hordeLeaderboard[2].name == "Thrall",
        "RankDB.GetLeaderboard('horde') sorted correctly",
        "1st=" .. tostring(hordeLeaderboard[1] and hordeLeaderboard[1].name))

    local paladinLeaderboard, paladinCount = RankDB.GetLeaderboard(testRealm, "all", "PALADIN")
    check(paladinCount == 2, "RankDB class filter PALADIN returns 2 paladins", "got " .. tostring(paladinCount))
    check(paladinLeaderboard[1].name == "Uther" and paladinLeaderboard[2].name == "Arthas",
        "RankDB class filter returns paladins in sorted order",
        "1st=" .. tostring(paladinLeaderboard[1] and paladinLeaderboard[1].name))

    local searchLeaderboard, searchCount = RankDB.GetLeaderboard(testRealm, "all", nil, "thr")
    check(searchCount == 1 and searchLeaderboard[1].name == "Thrall",
        "RankDB live search query matches substring case-insensitively",
        "match=" .. tostring(searchLeaderboard[1] and searchLeaderboard[1].name))

    -- GetPlayerRank O(1) resolution
    local oSyl, fSyl, cSyl, totalSyl = RankDB.GetPlayerRank("Player-1-004", testRealm)
    check(oSyl == 1 and fSyl == 1 and cSyl == 1 and totalSyl == 5,
        "RankDB.GetPlayerRank resolves Sylvanas as #1 Overall, #1 Horde, #1 Hunter",
        ("overall=%s, faction=%s, class=%s"):format(tostring(oSyl), tostring(fSyl), tostring(cSyl)))

    local oArt, fArt, cArt = RankDB.GetPlayerRank("Player-1-001", testRealm)
    check(oArt == 5 and fArt == 3 and cArt == 2,
        "RankDB.GetPlayerRank resolves Arthas as #5 Overall, #3 Alliance, #2 Paladin",
        ("overall=%s, faction=%s, class=%s"):format(tostring(oArt), tostring(fArt), tostring(cArt)))
end

do
    out(("\n-- RankDB: PruneStaleRecords --\n"))
    local RankDB = namespace.RankDB
    local staleRealm = "StaleRealm"
    local oldTime = (REALG.time and REALG.time() or 1000000) - (70 * 24 * 3600)
    local freshTime = (REALG.time and REALG.time() or 1000000) - (10 * 24 * 3600)
    RankDB.StoreRecord({ guid = "Player-1-Old", name = "Oldie", gs = 3000, timestamp = oldTime }, staleRealm)
    RankDB.StoreRecord({ guid = "Player-1-Fresh", name = "Freshie", gs = 4000, timestamp = freshTime }, staleRealm)

    local prunedCount = RankDB.PruneStaleRecords(staleRealm, 60, 5000)
    check(prunedCount == 1, "RankDB.PruneStaleRecords evicts record older than 60 days", "pruned=" .. tostring(prunedCount))
    local remaining, remCount = RankDB.GetLeaderboard(staleRealm, "all")
    check(remCount == 1 and remaining[1].name == "Freshie",
        "Fresh record survives pruning",
        "remaining=" .. tostring(remaining[1] and remaining[1].name))
end

do
    out(("\n-- RankSync: Serialization, Deserialization & Queue --\n"))
    local RankDB = namespace.RankDB
    local RankSync = namespace.RankSync
    local testNow = REALG.time and REALG.time() or 1000000

    local syncRec = {
        guid = "Player-1-001",
        name = "Arthas",
        faction = "Alliance",
        classID = 2,
        class = "PALADIN",
        specName = "Retribution",
        gs = 4800,
        ilvl = 145.2,
        timestamp = testNow - 50,
    }
    local wirePayload = RankSync.SerializeRecord(syncRec)
    check(type(wirePayload) == "string" and wirePayload:sub(1, 2) == "R;",
        "RankSync.SerializeRecord generates valid 'R;' prefixed wire format",
        "wire=" .. tostring(wirePayload))

    local restoredRec = RankSync.DeserializeRecord(wirePayload)
    check(type(restoredRec) == "table"
        and restoredRec.guid == syncRec.guid
        and restoredRec.name == syncRec.name
        and restoredRec.faction == syncRec.faction
        and restoredRec.classID == syncRec.classID
        and restoredRec.class == syncRec.class
        and restoredRec.specName == syncRec.specName
        and restoredRec.gs == syncRec.gs
        and restoredRec.timestamp == syncRec.timestamp,
        "RankSync.DeserializeRecord reconstructs record perfectly",
        "name=" .. tostring(restoredRec and restoredRec.name))

    -- EMPTY FIELDS. The round-trip above uses a record with every field filled,
    -- which is why it passed for a whole release while the parser was silently
    -- discarding records that had a blank one.
    --
    -- The parser used `gmatch("([^;]+)")`, and `+` requires one or more
    -- characters -- so an empty field was SKIPPED rather than returned. specName
    -- is routinely empty (a player whose spec could not be read) and faction is
    -- empty when unknown, and a skipped field shifts every later field and takes
    -- the part count under the minimum, so the WHOLE record was rejected.
    --
    -- Measured before the fix: "R;P1;Bob;Horde;1;WARRIOR;;3821;124.5;1759..."
    -- (empty spec) returned nil.
    local emptySpec = {
        guid = "Player-2-002", name = "Spec Less", faction = "Horde",
        classID = 1, class = "WARRIOR", specName = "",
        gs = 3821, ilvl = 124.5, timestamp = testNow - 60,
    }
    local back = RankSync.DeserializeRecord(RankSync.SerializeRecord(emptySpec))
    check(type(back) == "table",
        "an empty specName does not discard the record",
        "payload=" .. tostring(RankSync.SerializeRecord(emptySpec)))
    check(type(back) == "table" and back.specName == "",
        "an empty specName round-trips as empty, not as the next field",
        "spec=" .. tostring(back and back.specName))
    check(type(back) == "table" and back.gs == emptySpec.gs
        and back.ilvl == emptySpec.ilvl and back.timestamp == emptySpec.timestamp,
        "an empty specName does not shift every later field",
        type(back) == "table"
            and ("gs=%s ilvl=%s ts=%s"):format(back.gs, back.ilvl, back.timestamp) or "nil")

    local emptyFaction = {
        guid = "Player-3-003", name = "No Faction", faction = "",
        classID = 1, class = "WARRIOR", specName = "Arms",
        gs = 2900, ilvl = 110, timestamp = testNow - 70,
    }
    local backFaction = RankSync.DeserializeRecord(RankSync.SerializeRecord(emptyFaction))
    check(type(backFaction) == "table" and backFaction.faction == "",
        "an empty faction does not discard the record",
        type(backFaction) == "table" and ("faction=%q"):format(backFaction.faction) or "nil")

    -- Two blanks in a row is the case a naive split gets wrong twice over.
    local twoBlanks = {
        guid = "Player-4-004", name = "Double Blank", faction = "",
        classID = 1, class = "WARRIOR", specName = "",
        gs = 1500, ilvl = 90, timestamp = testNow - 80,
    }
    local backBlanks = RankSync.DeserializeRecord(RankSync.SerializeRecord(twoBlanks))
    check(type(backBlanks) == "table"
        and backBlanks.faction == "" and backBlanks.specName == ""
        and backBlanks.gs == 1500,
        "two consecutive empty fields round-trip",
        type(backBlanks) == "table"
            and ("faction=%q spec=%q gs=%s"):format(backBlanks.faction, backBlanks.specName, backBlanks.gs)
            or "nil")

    -- A genuinely malformed payload must still be refused, so the fix did not
    -- turn the parser into one that accepts anything.
    check(RankSync.DeserializeRecord("R;only;three") == nil,
        "a short payload is still refused")
    check(RankSync.DeserializeRecord("X;a;b;c;d;e;f;g;h;i;j") == nil,
        "a payload without the R marker is still refused")
    check(RankSync.DeserializeRecord(nil) == nil,
        "a nil payload is refused rather than raising")

    local badPayload = "R;invalid;short"
    local corruptRec = RankSync.DeserializeRecord(badPayload)
    check(corruptRec == nil, "RankSync.DeserializeRecord safely rejects corrupt payload", "got " .. tostring(corruptRec))

    local queueSyncRealm = "SyncTestRealm"
    local syncInspectRec = {
        guid = "Player-1-999",
        name = "Mograine",
        faction = "Alliance",
        class = "PALADIN",
        classID = 2,
        gs = 5000,
        realm = queueSyncRealm,
        timestamp = testNow - 20,
    }
    RankSync.QueueInspectRecord(syncInspectRec)
    local mogRank = RankDB.GetPlayerRank("Player-1-999", queueSyncRealm)
    check(mogRank == 1, "RankSync.QueueInspectRecord immediately registers player in RankDB", "rank=" .. tostring(mogRank))
end

do
    out(("\n-- RankSync: query / response protocol --\n"))
    local RankSync = namespace.RankSync
    local RankDB = namespace.RankDB

    -- Capture everything the add-on puts on the wire, and make C_Timer.After
    -- run immediately. The harness's real stub is a no-op that returns true, so
    -- without this the deferred response path is unreachable and the tests below
    -- would pass while proving nothing about it.
    local sent = {}
    local realAfter = REALG.C_Timer and REALG.C_Timer.After
    REALG.C_ChatInfo = REALG.C_ChatInfo or {}
    REALG.C_ChatInfo.SendAddonMessage = function(prefix, msg, chatType, target)
        sent[#sent + 1] = {
            prefix = prefix, msg = msg, chatType = chatType, target = target,
        }
    end
    REALG.C_ChatInfo.RegisterAddonMessagePrefix = function() return true end
    REALG.JoinChannelByName = function() return 1 end
    REALG.GetChannelName = function() return 7 end
    REALG.C_Timer = REALG.C_Timer or {}
    REALG.C_Timer.After = function(_, fn)
        if type(fn) == "function" then fn() end
        return true
    end

    local function drain()
        local msgs = {}
        for index = 1, #sent do
            msgs[index] = sent[index].msg
        end
        sent = {}
        return msgs
    end

    local function countPrefix(msgs, prefix)
        local n = 0
        for index = 1, #msgs do
            if msgs[index]:sub(1, #prefix) == prefix then n = n + 1 end
        end
        return n
    end

    -- Seed our own record so the response path has something to send.
    --
    -- Without this the assertion below depends on the adapter having completed a
    -- scan, and two variants deliberately prevent that (an ancient TacoTip, and
    -- an inspector missing a capability). The test would then be asserting the
    -- ADAPTER's capability while claiming to test the protocol -- which is
    -- exactly how a suite goes green on one variant and red on another for a
    -- reason nobody can read off the failure.
    if HARNESS_PLAYER_GUID then
        RankDB.StoreRecord({
            guid = HARNESS_PLAYER_GUID,
            name = "Tester",
            faction = "Alliance",
            classID = 1,
            class = "WARRIOR",
            specName = "Arms",
            gs = 6000,
            ilvl = 150,
            timestamp = REALG.time and REALG.time() or 1000000,
        })
    end

    -- SyncNow joins the channel (GetChannelName -> 7) and then asks.
    -- Forced: the load path already fired a resync, so the 30-second throttle
    -- is armed and an unforced call would correctly do nothing.
    RankSync.SyncNow(true)
    local first = drain()
    check(countPrefix(first, "Q;") >= 1,
        "a resync sends a Q query",
        table.concat(first, " | "))

    -- A query from someone else must produce our own record plus a digest.
    RankSync.HandlePayload("Q;abc123")
    local answer = drain()
    check(countPrefix(answer, "S;") >= 1,
        "an inbound Q produces an S carrying our own record",
        table.concat(answer, " | "))

    -- Every message must fit the 255-byte addon message limit. A payload that
    -- merely looks right but cannot be sent is the failure this catches.
    local longest = 0
    for index = 1, #answer do
        if #answer[index] > longest then longest = #answer[index] end
    end
    check(longest > 0 and longest <= 255,
        "no response exceeds the 255-byte addon message limit",
        "longest=" .. longest)

    -- Flood control. A second query inside the window must be ignored, or ten
    -- clients joining together produce ten rounds of answers.
    RankSync.HandlePayload("Q;second")
    local second = drain()
    check(countPrefix(second, "S;") == 0,
        "a second query inside the respond interval is not answered",
        table.concat(second, " | "))

    -- A response carrying one record must be ingested. This is the assertion
    -- that pins the 10-field stride: reading element 3 of a flat split yields
    -- the bare letter "R" and stores nothing, silently.
    local peerRecord = {
        guid = "Player-9-777", name = "Peer", faction = "Horde",
        classID = 1, class = "WARRIOR", specName = "",  -- empty on purpose
        gs = 4321, ilvl = 130.5, timestamp = REALG.time and REALG.time() or 1000000,
    }
    local peerPayload = RankSync.SerializeRecord(peerRecord)
    RankSync.HandlePayload("S;reqid;" .. peerPayload)
    local stored = RankDB.GetRecord("Player-9-777")
    check(type(stored) == "table" and stored.name == "Peer",
        "an S response is ingested",
        "stored=" .. tostring(stored and stored.name))
    check(type(stored) == "table" and stored.gs == 4321,
        "an S response keeps the record's GearScore",
        "gs=" .. tostring(stored and stored.gs))
    check(type(stored) == "table" and stored.specName == "",
        "an S response with an empty spec still ingests",
        "spec=" .. tostring(stored and stored.specName))

    -- Two records in one T message: the stride has to advance by exactly ten
    -- fields per record or the second one lands on garbage.
    local recA = {
        guid = "Player-9-778", name = "Alpha", faction = "Alliance",
        classID = 1, class = "WARRIOR", specName = "Arms",
        gs = 5100, ilvl = 140, timestamp = (REALG.time and REALG.time() or 1000000) + 1,
    }
    local recB = {
        guid = "Player-9-779", name = "Beta", faction = "Alliance",
        classID = 3, class = "HUNTER", specName = "",
        gs = 4900, ilvl = 138, timestamp = (REALG.time and REALG.time() or 1000000) + 2,
    }
    RankSync.HandlePayload("T;reqid;"
        .. RankSync.SerializeRecord(recA) .. ";"
        .. RankSync.SerializeRecord(recB))
    local storedA = RankDB.GetRecord("Player-9-778")
    local storedB = RankDB.GetRecord("Player-9-779")
    check(type(storedA) == "table" and storedA.name == "Alpha"
        and storedA.gs == 5100 and storedA.specName == "Arms",
        "the FIRST record of a T message is ingested",
        "A=" .. tostring(storedA and storedA.name) .. "/" .. tostring(storedA and storedA.gs))
    check(type(storedB) == "table" and storedB.name == "Beta"
        and storedB.gs == 4900 and storedB.specName == "",
        "the SECOND record of a T message is ingested",
        "B=" .. tostring(storedB and storedB.name) .. "/" .. tostring(storedB and storedB.gs))

    -- A T containing one record only: the loop must not read past the end.
    RankSync.HandlePayload("T;reqid;" .. RankSync.SerializeRecord({
        guid = "Player-9-780", name = "Solo", faction = "Horde",
        classID = 1, class = "WARRIOR", specName = "Fury",
        gs = 3000, ilvl = 100, timestamp = (REALG.time and REALG.time() or 1000000) + 3,
    }))
    check(type(RankDB.GetRecord("Player-9-780")) == "table",
        "a single-record T message is ingested")

    -- Malformed input must be ignored quietly, never raise: this runs on every
    -- addon message from anyone on the realm.
    for _, bad in ipairs({ "", "Q", "S;", "S;;;;;", "T;id", "Z;1;2;3",
        "R;short", "S;id;R;only;two", "Q;id;extra" }) do
        local ok = pcall(RankSync.HandlePayload, bad)
        if not ok then
            check(false, "a malformed payload does not raise", ("payload=%q"):format(bad))
            break
        end
    end
    check(true, "no malformed payload raises")

    -- Restore.
    if REALG.C_Timer then REALG.C_Timer.After = realAfter end
end

do
    out(("\n-- Tooltips: Server Rank Display & Toggle --\n"))
    local RankDB = namespace.RankDB
    local testNow = REALG.time and REALG.time() or 1000000

    -- Store standing for HARNESS_PLAYER_GUID in active realm
    RankDB.StoreRecord({
        guid = HARNESS_PLAYER_GUID,
        name = "Tester",
        faction = "Alliance",
        class = "WARRIOR",
        classID = 1,
        gs = 310,
        timestamp = testNow - 10,
    })

    if SURFACE_ACTIVE then
        local driveScript = (EXPECTED_DRIVER == "unit-hook") and "OnTooltipSetUnit" or "OnUpdate"

        -- Drive GameTooltipFrame render for HARNESS_PLAYER_GUID
        GameTooltipFrame:SetUnit("player")
        GameTooltipFrame:AddLine("Tester")
        GameTooltipFrame:AddLine("Level 70")
        GameTooltipFrame:Show()
        fireScript(GameTooltipFrame, "OnShow")
        local addedBeforeRank = #GAME_TOOLTIP_ADDED
        fireScript(GameTooltipFrame, driveScript)
        local foundRank = false
        local rankText = ""
        for i = addedBeforeRank + 1, #GAME_TOOLTIP_ADDED do
            local line = GAME_TOOLTIP_ADDED[i]
            if type(line) == "string" and line:find("Gearscore Rank:", 1, true) then
                foundRank = true
                rankText = line
            end
        end
        check(foundRank == true, "Tooltips:ServerRankLine appends Rank line to tooltip", "line=" .. tostring(rankText))

        -- The brackets read as punctuation and the numbers carry the ranking
        -- scale. Both halves were wrong together: the class rank was drawn as
        -- "[#1" inside ONE colour code, so the bracket inherited the number's
        -- colour -- purple, because the number itself was the top of the raw
        -- percentile bands rather than the top of a standing.
        check(rankText:find("|cffffffff[|r", 1, true) ~= nil
                and rankText:find("|cffffffff]|r", 1, true) ~= nil,
            "Tooltips:ServerRankLine draws both brackets in white",
            "line=" .. tostring(rankText))
        check(rankText:find("|cffffffff[|r#", 1, true) == nil,
            "Tooltips:ServerRankLine keeps the class rank in its own colour",
            "line=" .. tostring(rankText))
        local dbForRank = namespace.RankDB
        local rankScale = namespace.Scoring
        if dbForRank and type(dbForRank.GetPlayerRank) == "function" then
            local overall, _, _, totalRanked = dbForRank.GetPlayerRank(HARNESS_PLAYER_GUID)
            local r, g, b
            if rankScale and type(rankScale.RankColor) == "function" then
                r, g, b = rankScale.RankColor(overall, totalRanked)
            end
            local swatch = (type(r) == "number" and type(g) == "number" and type(b) == "number")
                and string.format("|cff%02x%02x%02x#%s|r",
                    math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
                    math.floor(b * 255 + 0.5), tostring(overall))
                or nil
            check(swatch ~= nil and rankText:find(swatch, 1, true) ~= nil,
                "Tooltips:ServerRankLine colours the overall rank from Scoring.RankColor",
                "wanted=" .. tostring(swatch) .. " line=" .. tostring(rankText))
        end

        -- Disable rank in settings and re-render
        if REALG.TacoTipExtrasDB and REALG.TacoTipExtrasDB.settings and REALG.TacoTipExtrasDB.settings.tooltip then
            REALG.TacoTipExtrasDB.settings.tooltip.show_server_rank = false
        end
        GameTooltipFrame:SetUnit("player")
        GameTooltipFrame:AddLine("Tester")
        GameTooltipFrame:AddLine("Level 70")
        GameTooltipFrame:Show()
        fireScript(GameTooltipFrame, "OnShow")
        local addedBeforeDisabled = #GAME_TOOLTIP_ADDED
        fireScript(GameTooltipFrame, driveScript)
        local foundRankDisabled = false
        for i = addedBeforeDisabled + 1, #GAME_TOOLTIP_ADDED do
            local line = GAME_TOOLTIP_ADDED[i]
            if type(line) == "string" and line:find("Gearscore Rank:", 1, true) then
                foundRankDisabled = true
            end
        end
        check(foundRankDisabled == false, "Tooltips:ServerRankToggle suppresses rank line when disabled", "found=" .. tostring(foundRankDisabled))

        -- Restore settings to true
        if REALG.TacoTipExtrasDB and REALG.TacoTipExtrasDB.settings and REALG.TacoTipExtrasDB.settings.tooltip then
            REALG.TacoTipExtrasDB.settings.tooltip.show_server_rank = true
        end
        GameTooltipFrame:Hide()
        fireScript(GameTooltipFrame, "OnHide")
    else
        check(true, "Tooltips:ServerRankLine skipped when tooltip surface inactive (gated by adapter)")
    end
end

do
    out(("\n-- RankBrowser UI & Slash Commands --\n"))
    local RankBrowser = namespace.RankBrowser

    check(type(RankBrowser) == "table", "RankBrowser table exists", "type=" .. type(RankBrowser))
    check(type(RankBrowser.Toggle) == "function", "RankBrowser.Toggle is a function", "type=" .. type(RankBrowser.Toggle))
    local rankFrame = RankBrowser.CreateUI and RankBrowser.CreateUI()
    check(type(rankFrame) == "table", "TacoTipRankFrame frame is created", "got " .. type(rankFrame))
    -- SLASH_<NAME>1 and SlashCmdList.<NAME> are ONE declaration. Asserting the
    -- SLASH_ half alone passed while the SlashCmdList half was missing, which
    -- is how a registered-but-dead command ships.
    check(type(REALG.SlashCmdList) == "table" and type(REALG.SlashCmdList.TACOTIPRANKS) == "function",
        "Slash handler TACOTIPRANKS is registered in SlashCmdList")
    check(REALG.SLASH_TACOTIPRANKS1 == "/ttrank", "Slash command /ttrank registered", "got " .. tostring(REALG.SLASH_TACOTIPRANKS1))
    check(REALG.SLASH_TACOTIPRANKS2 == "/ttranks", "Slash command /ttranks registered", "got " .. tostring(REALG.SLASH_TACOTIPRANKS2))
    check(REALG.SLASH_TACOTIPRANKS3 == "/ttleaderboard", "Slash command /ttleaderboard registered", "got " .. tostring(REALG.SLASH_TACOTIPRANKS3))
    check(REALG.SLASH_TACOTIPRANKS4 == "/tt lb", "Slash command /tt lb registered", "got " .. tostring(REALG.SLASH_TACOTIPRANKS4))
    check(REALG.SLASH_TACOTIPRANKS5 == "/tt rank", "Slash command /tt rank registered", "got " .. tostring(REALG.SLASH_TACOTIPRANKS5))
    check(REALG.SLASH_TACOTIPRANKS6 == "/tt ranks", "Slash command /tt ranks registered", "got " .. tostring(REALG.SLASH_TACOTIPRANKS6))
    check(REALG.SLASH_TACOTIPRANKS7 == "/tt leaderboard", "Slash command /tt leaderboard registered", "got " .. tostring(REALG.SLASH_TACOTIPRANKS7))

    -- Every declared alias must be DISTINCT. A duplicated alias would shadow
    -- another and make one unreachable, and a table keyed by alias would let
    -- one silently win.
    do
        local seen, dupes = {}, {}
        for i = 1, 7 do
            local alias = REALG["SLASH_TACOTIPRANKS" .. i]
            if type(alias) == "string" then
                if seen[alias] then
                    dupes[#dupes + 1] = alias
                end
                seen[alias] = true
            end
        end
        check(#dupes == 0, "all seven slash aliases are distinct", table.concat(dupes, ","))
    end

    -- The Options button must actually invoke the browser. Reaching into the
    -- The Options button must actually invoke the browser. Invoking its stored
    -- OnClick is the only way to catch a callback wired to a stale or nil
    -- reference -- a button that exists, looks right, and does nothing.
    do
        local browser = namespace.RankBrowser
        local optionsButton = RAWL.TacoTip_ExtrasOpenLeaderboardButton

        check(type(browser) == "table",
            "RankBrowser is present when the Options button is clicked")
        check(type(optionsButton) == "table",
            "the Options 'Open Server Leaderboard' button was created by name",
            "got " .. type(optionsButton))

        local toggles = 0
        local realToggle = nil
        if type(browser) == "table" and type(browser.Toggle) == "function" then
            realToggle = browser.Toggle
            browser.Toggle = function(...)
                toggles = toggles + 1
                return realToggle(...)
            end
        end

        if type(optionsButton) == "table" then
            -- SetScript stores handlers as __script_<name> (see the patched
            -- SetScript above); GetScript returns the chained result.
            local onClick = rawget(optionsButton, "__script_OnClick")
            check(type(onClick) == "function",
                "the Options leaderboard button stored a callable OnClick",
                "got " .. type(onClick))
            if type(onClick) == "function" then
                local ok, err = pcall(onClick, optionsButton)
                check(ok, "clicking the Options leaderboard button does not raise", tostring(err))
                check(toggles == 1,
                    "clicking the Options leaderboard button opens the browser",
                    "Toggle called " .. toggles .. " times")
            end
        end

        if realToggle then
            browser.Toggle = realToggle
        end
    end

    -- The slash handler must open the browser too, not merely exist.
    do
        local browser = namespace.RankBrowser
        local toggles = 0
        local realToggle = nil
        if type(browser) == "table" and type(browser.Toggle) == "function" then
            realToggle = browser.Toggle
            browser.Toggle = function(...)
                toggles = toggles + 1
                return realToggle(...)
            end
        end
        local handler = type(REALG.SlashCmdList) == "table"
            and REALG.SlashCmdList.TACOTIPRANKS or nil
        if type(handler) == "function" then
            local ok, err = pcall(handler, "/tt lb")
            check(ok, "the /tt lb slash handler does not raise", tostring(err))
            check(toggles == 1, "the /tt lb slash handler opens the browser",
                "Toggle called " .. toggles .. " times")
        end
        if realToggle then
            browser.Toggle = realToggle
        end
    end
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