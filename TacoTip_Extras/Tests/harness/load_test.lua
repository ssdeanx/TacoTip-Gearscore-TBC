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
-- The mock-fidelity contract (proctor HI-12). The shared table lives in the
-- MAIN add-on's harness tree, one level up from this add-on's root; it is
-- loaded LOUDLY, so a missing file raises rather than the assertion quietly
-- disappearing.
local MOCKC = dofile(ROOT .. "/../Tests/harness/mock_contract.lua")

local unpack = unpack or table.unpack

local ADDON_NAME = "TacoTip_Extras"
local CLIENT = (arg[1] or "classic_era"):lower()
local VARIANT = (arg[2] or "ok"):lower()
-- The contract's family drives the per-family mock arities. The Extras
-- clients are the same five the MAIN add-on supports.
MOCKC.setFamily(MOCKC.normaliseFamily(CLIENT))

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
        interface = 120105,
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

-- Swapped-argument guard (Batch 7, item 3).
--
-- The MAIN harnesses call check(name, cond, detail); THIS harness calls
-- check(cond, label, detail). The call SHAPE is identical, so a MAIN-style
-- call copied in here is read the other way round: the string name lands in
-- the CONDITION slot, where it is truthy, so the call passes SILENTLY. The
-- two shapes are unambiguous -- a condition is never a string in this harness
-- and a label is never a boolean -- so "first argument is a string AND second
-- argument is a boolean" can only mean the arguments are the wrong way round.
local function isSwappedCheckArgs(first, second)
    return (type(first) == "string" and type(second) == "boolean")
end

local function check(ok, label, detail)
    if isSwappedCheckArgs(ok, label) then
        -- Loud, and NOT a pass. The failure is recorded so the suite goes
        -- red: a silently-passing swapped call is the whole hazard this
        -- guard exists for. The PASS path is never taken.
        checks = checks + 1
        failures[#failures + 1] = ("SWAPPED CHECK ARGUMENTS: check(\"%s\", %s)")
            :format(ok, tostring(label))
        out(("  FAIL  SWAPPED CHECK ARGUMENTS -- this harness calls check(cond, label, detail), NOT check(name, cond, detail)\n"))
        out(("          got check(\"%s\", %s): the string sits in the CONDITION slot, where it would read as a silent pass\n")
            :format(ok, tostring(label)))
        return false
    end
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

-- The shared contract helper takes the MAIN-suite order
-- (name, cond, detail); THIS harness calls check(cond, label, detail).
-- Adapt once, here, so the contract's own text is not rewritten per call.
-- It is defined AFTER check(), because it closes over it.
local function contractCheck(name, cond, detail)
    return check(cond, name, detail)
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
-- What the options panel's dropdowns are showing.
--
-- The UIDropDownMenu helpers are stubs, but the SELECTED VALUE is how the
-- panel reports the mode it is actually running in, so it is recorded rather
-- than dropped. UIDropDownMenu_GetSelectedValue hands the recorded value
-- back, so a pin can read what the control shows instead of trusting the
-- panel's own source.
local DROPDOWN_SELECTED = {}
local DROPDOWN_TEXT = {}
-- The dropdown's INITIALIZER and the items it builds are RECORDED, not
-- discarded.
--
-- The mock used to make UIDropDownMenu_Initialize a no-op, which meant the
-- MENU a player opens could not be inspected at all: the visible label of
-- the closed control was reachable, the list behind it was not. A dropdown
-- whose ITEMS carry hard-coded English in every language is exactly the
-- defect that hiding the items would let through.
local DROPDOWN_INITIALIZER = {}
local DROPDOWN_ITEMS = {}
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
    -- The text's pixel width. The client measures the real glyphs; the
    -- harness models it at six pixels a character, which is the same model
    -- the browser harness uses (Tests/harness/rankbrowser_test.lua). It is an
    -- APPROXIMATION, and the pins that use it are written so that a cap
    -- rather than a measurement is what decides the outcome.
    GetStringWidth = function(f) return #tostring(rawget(f, "__text") or "") * 6 end,
    GetStringHeight = function() return 12 end,
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
    -- The checked state is RECORDED, not dropped. A checkbox that always
    -- reads back false cannot be pinned: "the control shows the setting the
    -- add-on is actually running on" would be an assertion about nothing.
    SetChecked = function(f, value) rawset(f, "__checked", value == true) end,
    GetChecked = function(f) return rawget(f, "__checked") == true end,
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

-- Templates that carry the BACKDROP API. Only a template that mixes in
-- BackdropTemplateMixin has SetBackdrop / GetBackdrop / SetBackdropColor;
-- every other frame -- a plain one included -- reads nil for them. The
-- client-source citations are in the __index comment of newRegion.
local BACKDROP_TEMPLATES = { BackdropTemplate = true }

-- The templates whose frames publish the client's OWN title text as the
-- global "<FrameName>TitleText".
--
-- Every template in this list inherits a `$parentTitleText` FontString in the
-- client (the citations are on the mock's CreateFrame, below), so a frame
-- created with one of them has a title the add-on can use instead of drawing
-- its own.
local TITLE_TEXT_TEMPLATES = {
    ButtonFrameTemplate = true,
    ButtonFrameBaseTemplate = true,
    PortraitFrameTemplate = true,
    PortraitFrameTemplateNoCloseButton = true,
    PortraitFrameTexturedBaseTemplate = true,
    PortraitFrameBaseTemplate = true,
}

-- The size the CLIENT gives a frame from its template.
--
-- The options page's layout maths is in those coordinates -- the label is
-- anchored to the RIGHT of a 26x26 check button, and the hit rect is the
-- button's rect -- so the mock has to use the same size or the geometry it
-- reports is the wrong geometry.
--
--   origin/classic_era          Interface/AddOns/Blizzard_FrameXML/DeprecatedTemplates.xml:5-6
--   origin/classic_anniversary  Interface/AddOns/Blizzard_FrameXML/DeprecatedTemplates.xml:5-6
--   origin/classic_titan        Interface/AddOns/Blizzard_FrameXML/DeprecatedTemplates.xml:5-6
--   origin/forever              Interface/AddOns/Blizzard_FrameXML/DeprecatedTemplates.xml:5-6
--   origin/live                 Interface/AddOns/Blizzard_FrameXML/DeprecatedTemplates.xml:5-6
--       <CheckButton name="OptionsBaseCheckButtonTemplate" inherits="UICheckButtonTemplate" virtual="true">
--           <Size x="26" y="26"/>
local TEMPLATE_SIZES = {
    InterfaceOptionsCheckButtonTemplate = { w = 26, h = 26 },
}

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
        -- A frame the client creates is VISIBLE. The mock used to create every
        -- frame HIDDEN, and the client does not: Blizzard's own panels carry
        -- `hidden="true"` on the FRAME, never on the template (origin/classic_era
        --   Interface/AddOns/Blizzard_AddOnList/AddonList.xml:120 --
        --   `<Frame name="AddonList" enableMouse="true"
        --           inherits="ButtonFrameTemplate" mixin="AddonListMixin"
        --           hidden="true">`
        --   Interface/AddOns/Blizzard_UIPanels_Game/Blizzard_GameMenu.xml --
        --   GameMenuFrame, likewise hidden="true" on the frame), and Blizzard's
        -- code creates frames and then HIDES them explicitly (origin/classic_era
        --   Interface/AddOns/Blizzard_Calendar/Classic/Blizzard_Calendar.lua --
        --   `eventButton = CreateFrame("Button", ...)` then
        --   `eventButton:Hide();`).
        --
        -- A frame that relies on being born hidden is relying on a default the
        -- client does not have.
        __shown = true,
        __events = {},
        __children = {},
    }
    if type(parent) == "table" and type(parent.__children) == "table" then
        parent.__children[#parent.__children + 1] = self
    end
    if BUTTON_KINDS[kind] then
        for script in pairs(BUTTON_SCRIPTS) do
            self.__scripts[script] = true
        end
    end
    -- The backdrop API is recorded as ABSENT unless the template confers it.
    -- See the __index comment below for the client-source citations.
    local backdropCapable = type(template) == "string"
        and BACKDROP_TEMPLATES[template] == true
    if not backdropCapable then
        self.__absent = {
            SetBackdrop = true,
            GetBackdrop = true,
            SetBackdropColor = true,
        }
    end
    -- The size the template gives the frame, so the mock reports the same
    -- geometry the client would.
    local templateSize = type(template) == "string"
        and TEMPLATE_SIZES[template] or nil
    if templateSize then
        self.__width = templateSize.w
        self.__height = templateSize.h
    end
    local mt = {}
    mt.__index = function(_, key)
        -- The backdrop API is TEMPLATE-DEPENDENT, and the client is the
        -- authority. Only a template that mixes in BackdropTemplateMixin
        -- carries it -- verified on ALL FIVE branches:
        --   origin/classic_era          Interface/AddOns/Blizzard_SharedXML/Backdrop.xml:5
        --   origin/classic_anniversary  Interface/AddOns/Blizzard_SharedXML/Backdrop.xml:5
        --   origin/classic_titan        Interface/AddOns/Blizzard_SharedXML/Backdrop.xml:5
        --   origin/forever              Interface/AddOns/Blizzard_SharedXML/Backdrop.xml:5
        --   origin/live                 Interface/AddOns/Blizzard_SharedXML/Backdrop.xml:5
        --       <Frame name="BackdropTemplate" mixin="BackdropTemplateMixin" virtual="true">
        --   and the mixin, on every one of them:
        --   Interface/AddOns/Blizzard_SharedXML/Backdrop.lua:336 / :354 / :406
        --       SetBackdrop / GetBackdrop / SetBackdropColor
        --
        -- A PLAIN frame has NONE of them, and ButtonFrameTemplate has none
        -- either (it inherits PortraitFrameTemplate ->
        -- PortraitFrameTemplateNoCloseButton -> PortraitFrameBaseTemplate,
        -- whose mixins are PortraitFrameMixin / PortraitFrameTemplateMixin --
        -- SharedUIPanelTemplates.xml:387, :440, :674; it paints its own
        -- background TEXTURE instead).
        --
        -- The mock used to hand the whole set to EVERY frame, so a plain
        -- frame asking for a backdrop looked like it got one. That is how the
        -- Extras' GEAR PANEL shipped transparent: its `if f.SetBackdrop then`
        -- guard was skipped in the real client and the harness could not see
        -- it.
        --
        -- __absent is consulted FIRST, and via rawget: reading t.__absent
        -- through __index would recurse forever. An absent key is NOT counted
        -- as a method miss -- probing a method the client does not have is
        -- the correct guarded behaviour, not a defect.
        local absent = rawget(self, "__absent")
        if absent and key ~= "__absent" and absent[key] then
            return nil
        end
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

-- Geometry is RECORDED, not discarded.
--
-- The options page is a two-column layout of anchored widgets, and the
-- questions that matter about it -- does a long label run into the next
-- column, do two controls' clickable regions overlap -- are questions about
-- COORDINATES. A SetPoint that throws the coordinates away cannot answer
-- either, and a mock that answers "no overlap" because it measured nothing
-- is worse than no pin at all.
patch("SetPoint", function(f, point, relativeTo, relativePoint, x, y)
    rawset(f, "__point", {
        point = point,
        relativeTo = relativeTo,
        relativePoint = relativePoint,
        x = x or 0,
        y = y or 0,
    })
end)
patch("GetPoint", function(f)
    local p = rawget(f, "__point")
    if not p then return "TOPLEFT", "TOPLEFT", 0, 0 end
    return p.point, p.relativeTo, p.relativePoint, p.x, p.y
end)
patch("ClearAllPoints", function(f) rawset(f, "__point", nil) end)
patch("SetSize", function(f, w, h)
    rawset(f, "__width", w or 0)
    rawset(f, "__height", h or 0)
end)
patch("SetWidth", function(f, w) rawset(f, "__width", w or 0) end)
patch("SetHeight", function(f, h) rawset(f, "__height", h or 0) end)
patch("GetWidth", function(f)
    local explicit = rawget(f, "__width")
    if explicit ~= nil then
        return explicit
    end
    -- A FontString with NO explicit width sizes itself to its text, exactly
    -- like the client -- and that is the whole reason an uncapped long label
    -- runs off into the next column. A mock that reported 0 for it would
    -- make the "no label overflows" pin vacuous.
    if rawget(f, "__kind") == "FontString" then
        return #tostring(rawget(f, "__text") or "") * 6
    end
    return 0
end)
patch("GetHeight", function(f) return rawget(f, "__height") or 0 end)
-- The hit rect is the frame's rect adjusted by these insets, and the ORDER is
-- (left, right, top, bottom) -- confirmed in the client source, not guessed:
--   origin/classic_era  Interface/AddOns/Blizzard_APIDocumentationGenerated/
--     SimpleFrameAPIDocumentation.lua:1150-1153
--       { Name = "left" }, { Name = "right" }, { Name = "top" }, { Name = "bottom" }
-- and Blizzard's own calls use the second argument as a RIGHT expansion:
--   origin/classic_era  Interface/AddOns/Blizzard_Calendar/Classic/
--     Blizzard_Calendar.lua:3799
--       self:SetHitRectInsets(0, -CalendarCreateEventAutoApproveCheckText:GetWidth(), 0, 0)
patch("SetHitRectInsets", function(f, left, right, top, bottom)
    rawset(f, "__hitInsets", {
        left = left or 0,
        right = right or 0,
        top = top or 0,
        bottom = bottom or 0,
    })
end)
-- Word wrap is RECORDED. There is no IsWordWrap in the client's API
-- documentation (checked: the only FontString wrap method documented is
-- SetWordWrap, SimpleFontStringAPIDocumentation.lua:666), so a pin cannot
-- ask the widget whether it wraps -- it can only ask whether the code told
-- it to.
patch("SetWordWrap", function(f, wrap)
    rawset(f, "__wordWrap", wrap == true)
end)

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
-- GetScript hands back a handler that runs the ORIGINAL and then the hook,
-- which is what "HookScript chains" means. The mock used to read only
-- __script_*, which made every hooked script invisible to GetScript and would
-- have turned "drive the driver script" into "call nothing and report
-- success"; it then over-corrected by returning the hook ALONE, which is not
-- a chain either. It composes them now, so the mock matches what it claims.
--
-- WHAT IS ASSUMED ABOUT THE CLIENT HERE, and it cannot affect the players:
-- `GetScript` returns the handler registered with SetScript -- Blizzard's own
-- code proves that much
-- (origin/classic_era:Interface/AddOns/Blizzard_CombatLog/Classic/Blizzard_CombatLog.lua:2867
-- `local original_OnEvent = COMBATLOG:GetScript("OnEvent");`, saved and
-- wrapped with SetScript). Whether a HookScript chain is ALSO returned is
-- engine-side and the FrameXML mirror cannot settle it. The shipped add-on
-- never calls GetScript on a frame it hooks -- the CLIENT dispatches its own
-- script chain -- so this uncertainty can only affect how faithful this
-- harness is, never what a player sees.
patch("GetScript", function(f, script)
    local hooked = rawget(f, "__hook_" .. tostring(script))
    local original = rawget(f, "__script_" .. tostring(script))
    if hooked ~= nil and original ~= nil then
        return function(self, ...)
            original(self, ...)
            return hooked(self, ...)
        end
    end
    if hooked ~= nil then
        return hooked
    end
    return original
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
    -- Server time is epoch seconds, the same scale as os.time. Timestamps and
    -- age cutoffs now read GetServerTime, so mock it from the same source and
    -- every existing time-based expectation still holds.
    REALG.GetServerTime = os.time
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
            -- The client publishes the BUTTON FRAME TEMPLATE's own title as a
            -- global named "<FrameName>TitleText", and an add-on that draws
            -- its own title instead has to pay for a title band. The mock
            -- used to publish nothing, so the template title was never
            -- present and the title band was always paid for -- the mock
            -- disagreed with the client about the very thing it exists to
            -- model.
            --
            -- The client declares the title FontString as `$parentTitleText`
            -- with parentKey="TitleText", on all FIVE branches:
            --   origin/classic_era          Interface/AddOns/Blizzard_SharedXML/Classic/SharedUIPanelTemplates.xml:496
            --   origin/classic_anniversary  Interface/AddOns/Blizzard_SharedXML/Classic/SharedUIPanelTemplates.xml:496
            --   origin/classic_titan        Interface/AddOns/Blizzard_SharedXML/Classic/SharedUIPanelTemplates.xml:427
            --   origin/forever              Interface/AddOns/Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml:608
            --   origin/live                 Interface/AddOns/Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml:584
            --       <FontString name="$parentTitleText" ... parentKey="TitleText">
            -- and it is reachable from ButtonFrameTemplate:
            --   classic  :708 ButtonFrameTemplate -> :545 PortraitFrameTemplate
            --            -> :440 PortraitFrameTemplateNoCloseButton -> :496
            --   mainline :684 ButtonFrameTemplate -> :660 ButtonFrameBaseTemplate
            --            -> :544 PortraitFrameBaseTemplate -> :576 TitleContainer
            --            -> :584
            --
            -- That it resolves to "<FrameName>TitleText" is the client's own
            -- behaviour, seen on the same templates:
            --   origin/classic_era  Interface/AddOns/Blizzard_CharacterFrame/Cata/CharacterFrame.xml:282
            --       <Frame name="CharacterFrame" ... inherits="ButtonFrameTemplate">
            --   origin/classic_era  Interface/AddOns/Blizzard_CharacterFrame/Cata/CharacterFrame.lua:115
            --       CharacterFrameTitleText:SetText(displayInfo.title);
            --   origin/live  Interface/AddOns/Blizzard_ItemUpgradeUI/Mists/Blizzard_ItemUpgradeUI.xml:108
            --       <Frame name="ItemUpgradeFrame" inherits="EtherealFrameTemplate" ...>
            --   origin/live  Interface/AddOns/Blizzard_ItemUpgradeUI/Mists/Blizzard_ItemUpgradeUI.lua:29
            --       ItemUpgradeFrameTitleText:SetText(ITEM_UPGRADE);
            if TITLE_TEXT_TEMPLATES[template] then
                local titleName = name .. "TitleText"
                local title = newRegion("FontString", titleName, region, "OVERLAY")
                RAWL[titleName] = title
                REALG[titleName] = title
                region.TitleText = title
            end
        end
        return region
    end
    REALG.UIParent = newRegion("Frame", "UIParent")
    -- `securecall` -- the engine's taint-containment global, present on every
    -- supported client (Blizzard captures it as a local the same way it
    -- captures `forceinsecure`:
    -- Blizzard_FrameXML/SharedPetBattleTemplates.lua:5
    -- `local securecall = securecall;`). The mock counts the calls that went
    -- through it, so a taint pin can tell "addon code ran inside a Blizzard
    -- frame's script chain" from "it ran contained".
    REALG.securecall = function(fn, ...)
        REALG.__secureCalls = (REALG.__secureCalls or 0) + 1
        return fn(...)
    end
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
    -- UnitClass publishes THREE values on the modern pair
    -- (localizedClassName, classToken, classID) and TWO on the Classic
    -- family. The mock published two on every client -- one shape for five
    -- clients. See Tests/harness/mock_contract.lua for the contract and the
    -- branch-qualified citations:
    --   origin/live, origin/forever:
    --     Interface/AddOns/Blizzard_SharedXML/UnitUtil.lua:81
    --       local classID = select(3, UnitClass("player"));
    --   origin/classic_era, origin/classic_anniversary, origin/classic_titan:
    --     Interface/AddOns/Blizzard_InspectUI/Vanilla/InspectPaperDollFrame.lua:10
    --       local classDisplayName, class = UnitClass(InspectFrame.unit);
    REALG.UnitClass = MOCKC.unitClassMock(function() return "Warrior", "WARRIOR" end)
    MOCKC.assertArity(contractCheck, "UnitClass", REALG.UnitClass)
    -- Blizzard ships GetClassAtlas in SharedConstants on all five branches,
    -- which is what the compact rank line's class icon resolves through.
    REALG.GetClassAtlas = function(className) return "classicon-" .. tostring(className) end
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
    REALG.UIDropDownMenu_SetText = function(frame, text)
        DROPDOWN_TEXT[frame] = text
    end
    REALG.UIDropDownMenu_Initialize = function(frame, initFunc)
        DROPDOWN_INITIALIZER[frame] = initFunc
    end
    -- The menu builder. The client publishes both (UIDropDownMenuTemplate in
    -- Interface/AddOns/Blizzard_SharedXML/{Classic,Mainline}/
    -- UIDropDownMenuTemplates.xml on every supported branch), so a mock that
    -- omits them would raise the moment a dropdown is opened.
    REALG.UIDropDownMenu_CreateInfo = function()
        return {}
    end
    REALG.UIDropDownMenu_AddButton = function(info)
        DROPDOWN_ITEMS[#DROPDOWN_ITEMS + 1] = info
    end
    REALG.UIDropDownMenu_SetSelectedValue = function(frame, value)
        DROPDOWN_SELECTED[frame] = value
    end
    REALG.UIDropDownMenu_SetSelected = function() end
    REALG.UIDropDownMenu_GetSelectedValue = function(frame)
        return DROPDOWN_SELECTED[frame]
    end
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
    -- THE FRAMES' OWN SCRIPT SETS. The frame constructor above gives every
    -- frame every script, which is what let an unguarded `HookScript` on a
    -- frame the client does not declare pass the harness: `HookScript` raises
    -- "bad argument #2 to 'HookScript'" for an undeclared script, and that
    -- raise is what aborted the MAIN add-on's whole Retail load in 0.7.8.
    -- These four are corrected to what the client declares.
    --
    --   PaperDollFrame       OnLoad / OnEvent / OnShow / OnHide  (NO OnSizeChanged)
    --   InspectPaperDollFrame OnLoad / OnEvent / OnShow          (NO OnHide, NO OnSizeChanged)
    --   CharacterFrame        OnShow / OnHide                   (hidden at creation)
    --   InspectFrame          OnShow / OnHide                   (hidden at creation)
    --
    -- Classic chain:
    --   origin/classic_era:Interface/AddOns/Blizzard_CharacterFrame/Vanilla/PaperDollFrame.xml:127
    --   origin/classic_era:Interface/AddOns/Blizzard_InspectUI/Classic/InspectPaperDollFrame.xml
    -- The character pane and the inspect pane declare OnShow/OnHide -- proven
    -- in game: the main add-on hooks them unguarded (main.lua:3916, :4169,
    -- :4186) and the add-on loads on Classic Era.
    local function setScripts(frame, names)
        local scripts = rawget(frame, "__scripts")
        for k in pairs(scripts) do scripts[k] = nil end
        for _, n in ipairs(names) do scripts[n] = true end
    end
    setScripts(REALG.PaperDollFrame, { "OnLoad", "OnEvent", "OnShow", "OnHide" })
    setScripts(REALG.InspectPaperDollFrame, { "OnLoad", "OnEvent", "OnShow" })
    setScripts(REALG.CharacterFrame, { "OnLoad", "OnShow", "OnHide" })
    setScripts(REALG.InspectFrame, { "OnLoad", "OnShow", "OnHide" })
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
    --
    -- It is now the socket path's SCOPE GATE and nothing else: the socket
    -- COUNT comes from C_Item.GetItemNumSockets (see the mock below), and
    -- this add-on reads no socket key out of the stat table any more. The
    -- mock therefore publishes the client's stat table WITHOUT socket keys.
    -- The old "EMPTY_SOCKET1..3 = 1" triple is GONE with the code that read
    -- it: it was a fiction -- the same three slots for every link -- and the
    -- stat-table key names are engine-side, so the mirror can neither confirm
    -- them nor say whether they count slots or empties.
    if ITEM_STATS then
        REALG.GetItemStats = function(link, stat)
            if type(link) ~= "string" or type(stat) ~= "table" then
                return nil
            end
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

-- The client's item database: how many sockets each ITEM has.
--
-- The socket count is a property of the item, not of the link -- the client
-- resolves the item ID out of the link and answers from the item's own data,
-- exactly as C_Item.GetItemNumSockets does. So the table is keyed by item ID.
--
-- It is the CLIENT's answer and never the add-on's: the add-on reads it
-- through the documented API and cross-checks it against the item's own gem
-- list, and a client that answered wrongly would show up as a contradiction
-- rather than as a published number.
local ITEM_SOCKETS = {}
local function registerSocketCount(itemID, sockets)
    ITEM_SOCKETS[itemID] = sockets
end

local function itemIDFromLink(link)
    if type(link) ~= "string" then
        return nil
    end
    local digits = string.match(link, "item:(%d+)")
    return digits and tonumber(digits) or nil
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
    REALG.UnitClass = MOCKC.unitClassMock(function() return "Warrior", "WARRIOR" end)
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
        -- C_Item.GetItemNumSockets(itemInfo) -- the DOCUMENTED socket-count
        -- API, and the source of truth for the socket capacity.
        --
        -- The argument is the ITEM LINK, which is the shape Blizzard itself
        -- uses: PaperDollFrame.lua:1728 feeds
        -- GetInventoryItemLink("player", ...) into SetItem, and :2775 passes
        -- that link straight to C_Item.GetItemNumSockets. The generated docs
        -- call the argument "itemInfo" (an opaque item handle) and do not say
        -- how to build one from a link; Blizzard's own call site is what
        -- settles it.
        --
        -- The return is ONE value -- the socket count
        -- (ItemDocumentation.lua:854 on origin/live, :876 on origin/forever,
        -- :586 on origin/classic_era).
        --
        -- It is installed on EVERY client, the three Classic ones included,
        -- because the mirror documents it there too. The add-on's socket path
        -- is gated on GetItemStats, not on this API, and the mock has to be
        -- able to prove that: a mock that simply lacked the API would make
        -- the Classic degradation look like an accident of the model instead
        -- of the gate's doing.
        GetItemNumSockets = function(link)
            local itemID = itemIDFromLink(link)
            if not itemID then
                return 0
            end
            return ITEM_SOCKETS[itemID] or 0
        end,
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
    -- The Harness Helm is a two-socket headpiece in the client's item
    -- database, and its link carries one gem in socket 1.
    --
    -- Two sockets on purpose: the OLD code read the capacity from the stat
    -- table, and the old mock published a FIXED "EMPTY_SOCKET1..3" triple for
    -- every link, so it answered THREE for everything. An item whose real
    -- socket count is 2 is what tells the two sources apart.
    registerSocketCount(50003, 2)
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
check(tocMeta.Version == "1.2.3",
    "TOC ## Version is 1.2.3", "got " .. tostring(tocMeta.Version))
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
local WANTED_INTERFACES = "11509, 20506, 38002, 16001, 120105"
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

-- The socket-count mock publishes ONE value -- the socket count -- and the
-- contract says the client publishes one too
-- (ItemDocumentation.lua:854 on origin/live, :876 on origin/forever, :586 on
-- the Classic family). A mock that published two, or none, would be a drift
-- the socket pins would not catch on their own.
MOCKC.assertArity(
    contractCheck,
    "C_Item.GetItemNumSockets",
    REALG.C_Item and REALG.C_Item.GetItemNumSockets
)

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
--
-- The ORDER of the specifiers matters as much as the count. "%d %d" and "%s %d"
-- both carry two specifiers, but the second raises, or prints a number where a
-- string was promised. So this compares the ORDERED SEQUENCE of conversion
-- specifiers, not a tally.
--
-- It compares the TRANSLATION against enUS. The first version of this check
-- called count() for both sides of the comparison, and count() closed over
-- `value` -- so the "English" side was the translation again and the check
-- could never fail. It passed while all ten non-English locales shipped a
-- leaderboard footer with every one of its % stripped off, and the footer
-- rendered the player's own standing as a literal "#d".
--
-- The pattern captures the WHOLE conversion specifier, flags and precision
-- included ("%d", "%.1f", "%-8s"), because "%.1f" and "%.2f" carry the same
-- first character and a first-character comparison would call them equal.
local function specifierSequence(text)
    local sequence = {}
    for spec in text:gmatch("%%[-+ #0-9%.]*%a") do
        sequence[#sequence + 1] = spec
    end
    return sequence
end

local specProblems = {}
for index = 1, #registered do
    local code = registered[index]
    for key, value in pairs(EX[code]) do
        local base = EX["enUS"][key]
        if type(base) == "string" and type(value) == "string" then
            local got = table.concat(specifierSequence(value), " ")
            local want = table.concat(specifierSequence(base), " ")
            if got ~= want then
                specProblems[#specProblems + 1] = string.format(
                    "%s/%s: got [%s] want [%s]", code, key, got, want)
            end
        end
    end
end
check(#specProblems == 0,
    "every locale's specifier sequence equals enUS's for that key",
    table.concat(specProblems, "; "))

-- The ruRU footer is the one the final hunter named: it rendered the
-- player's own standing as a literal "#d" and the pool size as a literal
-- "d". Render it with REAL numbers and assert the numbers are in the text.
-- Asserting on the rendered string and not on the key's presence is the
-- point: a present-but-corrupted entry passes every key-parity check.
local ruFooter = string.format(EX["ruRU"]["LB_FOOTER_STANDING"], 12, 3, 5, 47)
check(ruFooter:find("#12", 1, true) ~= nil
    and ruFooter:find("#3", 1, true) ~= nil
    and ruFooter:find("#5", 1, true) ~= nil
    and ruFooter:find("47", 1, true) ~= nil
    and ruFooter:find("#d", 1, true) == nil
    and ruFooter:find("%d", 1, true) == nil,
    "the ruRU footer renders the real standing numbers",
    ruFooter)

-- A shipped translation must actually DIFFER from English. Without this, a file
-- that silently failed to translate would pass every assertion above.
--
-- Every probe key here is one the add-on READS. A probe on a key nothing
-- reads would compare nil against nil, call that "identical", and make the
-- check vacuous for that key -- so the two probes this used to carry
-- (LB_MY_RANK and OPT_TOOLTIP_MODE, both dead keys) were replaced with the
-- live keys that replaced them: LB_MY_RANK_ARROW and HELP_MODE_HEADING.
local untranslated = {}
local PROBE = { "MODE_DETAILED", "CURRENT_GS", "AVERAGE_ILVL", "COMPLETION",
    "MINIMAP_HINT_LEFT", "LB_TITLE", "LB_MY_RANK_ARROW", "CLASS_WARRIOR",
    "HELP_ENABLED_HEADING", "HELP_MODE_HEADING", "TIME_JUST_NOW" }
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

-- The "Comfortable rows" option must be localized in EVERY shipped locale.
--
-- The code looks the strings up as HELP_<KEY>_HEADING and HELP_<KEY>_<n>
-- (Options.lua's localizedHelp, and the same helper feeds the checkbox label),
-- so those are the keys that have to exist. A locale that omits them falls
-- back to the English source and the option reads English there -- which is
-- exactly what this pins.
do
    local required = { "HELP_COMFORTABLEROWS_HEADING", "HELP_COMFORTABLEROWS_1" }
    local missing, blank = {}, {}
    for index = 1, #registered do
        local code = registered[index]
        local locale = EX[code]
        for _, key in ipairs(required) do
            local value = locale and locale[key]
            if value == nil then
                missing[#missing + 1] = code .. ":" .. key
            elseif type(value) ~= "string" or value == "" then
                blank[#blank + 1] = code .. ":" .. key
            end
        end
    end
    check(#missing == 0,
        "every shipped locale defines the 'Comfortable rows' help keys",
        table.concat(missing, ", "))
    check(#blank == 0,
        "every shipped locale gives the 'Comfortable rows' help keys a non-empty value",
        table.concat(blank, ", "))

    -- The repo rule: a translated locale may not carry the English string.
    -- A copied English string is non-empty and has the right key, so the two
    -- checks above cannot see it -- this one can.
    local copied = {}
    for index = 1, #registered do
        local code = registered[index]
        if code ~= "enUS" then
            for _, key in ipairs(required) do
                local value = EX[code][key]
                -- A MISSING key is the "defines" check's business, not this
                -- one: nil == nil would otherwise report every absent key as a
                -- copied English string.
                if value ~= nil and value == EX["enUS"][key] then
                    copied[#copied + 1] = code .. ":" .. key
                end
            end
        end
    end
    check(#copied == 0,
        "no translated locale carries the English 'Comfortable rows' strings (ruRU included)",
        table.concat(copied, ", "))
end

-- ---------------------------------------------------------------------------
-- The leaderboard's triangle glyphs
-- ---------------------------------------------------------------------------
--
-- The footer carries "▲ Top" and "▼ My Rank", and the triangles are spelled
-- as BYTES because Lua 5.1 has no \u{} escape. A byte typo does not raise:
-- it renders the wrong character, and the button reads "☐ Top".
--
-- Ten of the eleven locales shipped U+2620 (BALLOT BOX) where the button
-- wanted U+25B2 (BLACK UP-POINTING TRIANGLE). Every other locale check
-- passed: the key was present, non-empty, the right script, and different
-- from English. Only the BYTES were wrong.
--
-- So the bytes are pinned. enUS carries the correct U+25B2 and every other
-- locale must start with the same three bytes; the down arrow is pinned the
-- same way, because it is the sibling of the same button row.
do
    local UP_TRIANGLE = "\226\150\178"     -- U+25B2 BLACK UP-POINTING TRIANGLE
    local DOWN_TRIANGLE = "\226\150\188"   -- U+25BC BLACK DOWN-POINTING TRIANGLE
    local problems = {}
    for index = 1, #registered do
        local code = registered[index]
        local top = EX[code] and EX[code]["LB_TOP"]
        if type(top) ~= "string"
            or top:sub(1, #UP_TRIANGLE) ~= UP_TRIANGLE then
            problems[#problems + 1] = code .. ":LB_TOP=" .. tostring(top)
        end
        local arrow = EX[code] and EX[code]["LB_MY_RANK_ARROW"]
        if type(arrow) ~= "string"
            or arrow:sub(1, #DOWN_TRIANGLE) ~= DOWN_TRIANGLE then
            problems[#problems + 1] = code .. ":LB_MY_RANK_ARROW=" .. tostring(arrow)
        end
    end
    check(#problems == 0,
        "every locale's LB_TOP starts with the same up-triangle bytes as enUS",
        table.concat(problems, ", "))
end

-- ---------------------------------------------------------------------------
-- All eleven locale files define the IDENTICAL key set
-- ---------------------------------------------------------------------------
--
-- The parity check above only proves each locale is a SUBSET of enUS: a
-- locale that LOST a key enUS defines still passes it, because the merged
-- table fills the gap from enUS. A locale missing a key therefore reads
-- ENGLISH in that language and nothing says so.
--
-- The key sets must be identical, not merely compatible.
do
    local problems = {}
    local reference = {}
    for key in pairs(EX["enUS"]) do reference[key] = true end
    for index = 1, #registered do
        local code = registered[index]
        local locale = EX[code]
        local missing, extra = {}, {}
        for key in pairs(reference) do
            if locale[key] == nil then missing[#missing + 1] = key end
        end
        for key in pairs(locale) do
            if not reference[key] then extra[#extra + 1] = key end
        end
        table.sort(missing)
        table.sort(extra)
        if #missing > 0 or #extra > 0 then
            problems[#problems + 1] = code
                .. " missing=[" .. table.concat(missing, " ") .. "]"
                .. " extra=[" .. table.concat(extra, " ") .. "]"
        end
    end
    check(#problems == 0, "every locale defines the same key set as enUS",
        table.concat(problems, "; "))
end

-- ---------------------------------------------------------------------------
-- Every locale key is READ somewhere in the add-on
-- ---------------------------------------------------------------------------
--
-- A key no code path reads is a translation nobody will ever see -- and it
-- is invisible: the file loads, the key-parity checks pass, the add-on runs.
--
-- That is exactly what happened. Thirty-nine keys shipped in all eleven
-- locales -- the OPT_* and SECTION_* families, the INTEGRATION_* and REMOTE_*
-- status strings, the Options-page tab labels -- while the text they were
-- written for was hardcoded English in the sources. The translations were
-- never read; the English was what the player saw.
--
-- So the SOURCES are scanned for the lookups, and every key the locale files
-- define must appear in one of them. The scan resolves each family of lookup
-- the code actually uses:
--
--   L["KEY"]                          a literal key
--   L["HELP_" .. x .. "_HEADING"]     the Options page's help headings
--   L[("HELP_%s_%d"):format(..)]     the Options page's help LINES
--   L["CLASS_" .. token]              the localized class names
--   L[col.label]                      the column headers (COLUMNS table)
--   L[SORTS[currentSort]]             the sort readouts (SORTS table)
--   L[choice.key]                     the mode names (the choice tables)
--
-- The families are resolved FROM THE SOURCES, not from a hand-written list,
-- so a new lookup cannot slip past this check by being forgotten here.
do
    local read = {}

    local function mark(key)
        if type(key) == "string" and key ~= "" then read[key] = true end
    end

    -- The runtime files, in TOC order, minus the locale files themselves.
    local runtimeSources = {}
    for _, relative in ipairs(tocFiles) do
        if relative:match("%.lua$") and not relative:match("^Locale/") then
            runtimeSources[#runtimeSources + 1] = relative
        end
    end
    local sourceText = {}
    for _, relative in ipairs(runtimeSources) do
        sourceText[relative] = readFile(ROOT .. "/" .. relative)
    end

    -- 1. The literal lookups.
    for _, relative in ipairs(runtimeSources) do
        local text = sourceText[relative]
        if type(text) == "string" then
            for key in text:gmatch('L%["([A-Z0-9_]+)"%]') do
                mark(key)
            end
        end
    end

    local optionsText = sourceText["Options.lua"] or ""
    local rankText = sourceText["RankBrowser.lua"] or ""

    -- 2. The Options page's help keys: HELP_<NAME>_HEADING and
    --    HELP_<NAME>_<line>, derived from the HELP table's entry names and
    --    each entry's line count.
    local helpBlock = optionsText:match("local HELP = {(.-)\n}\n")
    if type(helpBlock) == "string" then
        for name, body in helpBlock:gmatch("\n    ([A-Za-z][A-Za-z0-9_]*) = {(.-)\n    },") do
            local upper = name:upper()
            mark("HELP_" .. upper .. "_HEADING")
            local lineCount = 0
            for _ in body:gmatch('\n            "') do
                lineCount = lineCount + 1
            end
            for index = 1, lineCount do
                mark(("HELP_%s_%d"):format(upper, index))
            end
        end
    end

    -- 3. The localized class names: CLASS_<TOKEN> for every token the
    --    leaderboard can produce -- the CLASS_ORDER list, plus the
    --    "UNKNOWN" a row with no class info at all resolves to.
    local classBlock = rankText:match("local CLASS_ORDER = {(.-)\n}")
    if type(classBlock) == "string" then
        for token in classBlock:gmatch('"([A-Z]+)"') do
            mark("CLASS_" .. token)
        end
    end
    if rankText:find('return "UNKNOWN"', 1, true) then
        mark("CLASS_UNKNOWN")
    end

    -- 4. The column headers (the COLUMNS table's labels).
    for label in rankText:gmatch('label = "([A-Z0-9_]+)"') do
        mark(label)
    end

    -- 5. The sort readouts (the SORTS table's values).
    for sortKey in rankText:gmatch('= "(SORT_[A-Z0-9_]+)"') do
        mark(sortKey)
    end

    -- 6. The mode names (the Options page's choice tables' keys).
    for choiceKey in optionsText:gmatch('key = "([A-Z0-9_]+)"') do
        mark(choiceKey)
    end

    local unread = {}
    for key in pairs(EX["enUS"]) do
        if not read[key] then unread[#unread + 1] = key end
    end
    table.sort(unread)
    check(#unread == 0, "every locale key is read somewhere in the add-on",
        table.concat(unread, " "))
end

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

-- The "Comfortable rows" option reads through the MERGED table, so the key
-- has to be in the locale file AND reach the merged table. Applying ruRU and
-- reading the key back is the end-to-end check: a key that is present in the
-- file but never merged, or merged as the English fallback, still shows
-- English on the options page.
REALG.TacoTipConfig.locale_override = "ruRU"
REALG.TacoExtrasApplyLocale()
check(REALG.TACOEXTRAS_ACTIVE_LOCALE == "ruRU", "override selects ruRU",
    "got " .. tostring(REALG.TACOEXTRAS_ACTIVE_LOCALE))
check(REALG.TACOEXTRAS_LOCALE["HELP_COMFORTABLEROWS_HEADING"]
        == EX["ruRU"]["HELP_COMFORTABLEROWS_HEADING"]
    and REALG.TACOEXTRAS_LOCALE["HELP_COMFORTABLEROWS_HEADING"]
        ~= EX["enUS"]["HELP_COMFORTABLEROWS_HEADING"],
    "the merged table carries the Russian 'Comfortable rows' heading",
    "got " .. tostring(REALG.TACOEXTRAS_LOCALE["HELP_COMFORTABLEROWS_HEADING"]))
check(REALG.TACOEXTRAS_LOCALE["HELP_COMFORTABLEROWS_1"]
        == EX["ruRU"]["HELP_COMFORTABLEROWS_1"]
    and REALG.TACOEXTRAS_LOCALE["HELP_COMFORTABLEROWS_1"]
        ~= EX["enUS"]["HELP_COMFORTABLEROWS_1"],
    "the merged table carries the Russian 'Comfortable rows' help text",
    "got " .. tostring(REALG.TACOEXTRAS_LOCALE["HELP_COMFORTABLEROWS_1"]))
REALG.TacoTipConfig.locale_override = "deDE"
REALG.TacoExtrasApplyLocale()

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

-- ---------------------------------------------------------------------------
-- L-6 / M-7: an initialization failure is never silent
-- ---------------------------------------------------------------------------
--
-- Two shapes of "the add-on did not start":
--
--   L-6  a module that is present but NOT CALLABLE. guarded() returned false
--        and said nothing, so a whole surface could be absent with nothing on
--        record and nothing printed.
--   M-7  an incompatible TacoTip. Adapter.Initialize REFUSES by RETURNING
--        false -- a return value, not a raise -- so guarded() never saw it
--        either: the surface was released on purpose (that is the fail-closed
--        contract, and it is not a bug) and the user was told NOTHING at all.
--
-- Both are pinned against a SECOND, ISOLATED Core instance loaded into its
-- own namespace with its own stubs, so the live add-on is untouched and the
-- pin does not depend on which variant this run happens to be.
do
    local freshNamespace = {
        Scanner = {
            Initialize = function() return true end,
            BeginGeneration = function() return 1 end,
            RunGeneration = function() return true end,
            HandleItemDataLoad = function() return false end,
            GetCurrent = function() return nil end,
        },
        TacoTipAdapter = {
            -- The refusal: a return value, not a raise.
            Initialize = function() return false end,
            GetInternalReason = function() return "harness-incompatible-tacotip" end,
        },
        Tooltips = { Initialize = function() return true end },
        Frames = { Initialize = function() return true end },
        Options = { Initialize = function() return true end },
        -- Present, but NOT callable: the L-6 shape.
        Minimap = {},
    }
    local coreChunk, coreLoadErr = loadfile(ROOT .. "/Core.lua")
    local coreLoaded = false
    if coreChunk then
        coreLoaded = pcall(coreChunk, ADDON_NAME, freshNamespace)
    end
    check(coreLoaded and type(freshNamespace.Core) == "table",
        "L-6/M-7: a second, isolated Core instance loads",
        "loadErr=" .. tostring(coreLoadErr))

    if coreLoaded and type(freshNamespace.Core) == "table" then
        -- The isolated Core registered its own event frame on load; it is the
        -- last frame that registered an event.
        local freshFrame = FRAMES_BY_REGISTRATION[#FRAMES_BY_REGISTRATION]
        local chatBefore = #CHAT
        local fired = false
        if type(freshFrame) == "table" and type(freshFrame.GetScript) == "function" then
            local script = freshFrame:GetScript("OnEvent")
            if type(script) == "function" then
                fired = pcall(script, freshFrame, "ADDON_LOADED", ADDON_NAME)
            end
        end
        check(fired,
            "L-6/M-7: the isolated Core's ADDON_LOADED dispatch ran",
            "the isolated Core never initialized")

        local initFailures = freshNamespace.Core.GetInitializeFailures()
        local recorded = {}
        for _, label in ipairs(initFailures) do recorded[label] = true end
        check(recorded["Minimap"] == true,
            "L-6: a module that is not callable is recorded as an initialization failure",
            "failures=" .. table.concat(initFailures, ", "))
        check(recorded["TacoTipAdapter"] == true,
            "M-7: an incompatible TacoTip is recorded as an initialization failure",
            "failures=" .. table.concat(initFailures, ", "))

        -- ONE chat line each -- and the adapter's line names its internal
        -- reason, so the user learns WHY the surface is off.
        local saidMinimap, saidAdapter = false, false
        for index = chatBefore + 1, #CHAT do
            local line = tostring(CHAT[index])
            if line:find("Minimap", 1, true) ~= nil
                and line:find("failed to start", 1, true) ~= nil then
                saidMinimap = true
            end
            if line:find("TacoTipAdapter", 1, true) ~= nil
                and line:find("harness-incompatible-tacotip", 1, true) ~= nil then
                saidAdapter = true
            end
        end
        check(saidMinimap,
            "L-6: the uncallable module is stated in chat",
            "no chat line named Minimap")
        check(saidAdapter,
            "M-7: the chat line names the adapter's internal reason",
            "no chat line named TacoTipAdapter with its reason")
    end
end

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
-- THE CONTAINMENT. The Extras' handler on the shared GameTooltip is addon
-- code inside a BLIZZARD frame's script chain, so it runs inside `securecall`
-- -- the engine's containment primitive, present on every supported client
-- (Blizzard_FrameXML/SharedPetBattleTemplates.lua:5
-- `local securecall = securecall;`). The pin counts the calls that went
-- through it, so it goes RED if the containment is removed.
local secureCallsBefore = REALG.__secureCalls or 0
fireScript(GameTooltipFrame, DRIVE_SCRIPT)
check((REALG.__secureCalls or 0) > secureCallsBefore,
    "the shared GameTooltip's " .. DRIVE_SCRIPT .. " handler runs inside securecall",
    "secureCalls=" .. tostring((REALG.__secureCalls or 0) - secureCallsBefore))
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

-- 10. The render LATCH must survive a raise (final hunter H-2).
--
-- The driver's `rendering` flag is a latch: while it is true every later
-- render is refused. It used to be cleared only on the four NORMAL returns
-- out of the render, so a raise ANYWHERE inside left it true for the rest of
-- the session -- the Extras tooltip surface stopped rendering, with no error,
-- no counter, and no way back short of /reload.
--
-- The failure is injected the way the real ones arrive: the raw engine call
-- the render makes (target:AddLine) raises once. Everything after it must
-- still work.
do
    local methods = rawget(GameTooltipFrame, "__methods")
    local originalAddLine = methods.AddLine
    local injected = false

    -- Put the tooltip back into a state where the next tick really renders:
    -- a unit set, the tooltip shown, and no binding (the item tooltip above
    -- dropped it).
    GameTooltipFrame:SetUnit("player")
    GameTooltipFrame:AddLine("Name")
    GameTooltipFrame:Show()
    fireScript(GameTooltipFrame, "OnShow")

    methods.AddLine = function(f, text)
        if not injected then
            injected = true
            error("harness: injected AddLine raise")
        end
        return originalAddLine(f, text)
    end

    local beforeRaise = driverState()
    local raised = pcall(fireScript, GameTooltipFrame, DRIVE_SCRIPT)
    methods.AddLine = originalAddLine
    local afterRaise = driverState()

    check(raised,
        "a raising render does not escape the driver script",
        "the boundary must absorb it")
    check(afterRaise.renderErrors == (beforeRaise.renderErrors or 0) + 1,
        "a raising render is counted",
        "renderErrors " .. tostring(beforeRaise.renderErrors)
            .. " -> " .. tostring(afterRaise.renderErrors))
    check(type(afterRaise.lastRenderError) == "string"
        and afterRaise.lastRenderError:find("injected AddLine raise", 1, true) ~= nil,
        "a raising render records the message",
        "lastRenderError=" .. tostring(afterRaise.lastRenderError))

    -- The point of the boundary: the surface can STILL render. The latch was
    -- released, so the next tick appends rows again.
    local beforeRecovery = afterRaise
    fireScript(GameTooltipFrame, DRIVE_SCRIPT)
    local afterRecovery = driverState()
    check(afterRecovery.rows > beforeRecovery.rows,
        "the surface renders again after a raising render (the latch was released)",
        "rows " .. tostring(beforeRecovery.rows) .. " -> " .. tostring(afterRecovery.rows)
            .. ", renders " .. tostring(beforeRecovery.renders)
            .. " -> " .. tostring(afterRecovery.renders))
end
end -- SURFACE_ACTIVE

-- ---------------------------------------------------------------------------
-- The socket capacity: the documented API, and the scope gate
-- ---------------------------------------------------------------------------
--
-- The capacity used to be the SUM of the stat table's EMPTY_SOCKET* values.
-- Those key names are ENGINE-side -- the FrameXML mirror has zero occurrences
-- of "EMPTY_SOCKET", in any case, on every branch -- and the only evidence
-- for them was this harness's own mock, which wrote a FIXED
-- "EMPTY_SOCKET1".."EMPTY_SOCKET3" triple for EVERY link. A fixed triple is
-- not a socket count: it is the same three slots for every item, so a
-- one-socket item published three empty sockets and the published Potential
-- GS, Delta and Completion came out above what the item justified.
--
-- The capacity now comes from the DOCUMENTED API, in the call shape Blizzard
-- itself uses: C_Item.GetItemNumSockets(itemLink)
-- (ItemDocumentation.lua:854 on origin/live, :876 on origin/forever, :586 on
-- origin/classic_era), where the argument is the item link -- the generated
-- docs call it "itemInfo" and do not say how to build one from a link, and
-- Blizzard's own call site answers that:
-- PaperDollFrame.lua:1728 feeds GetInventoryItemLink("player", ...) into
-- SetItem, and :2775 passes that link straight into
-- C_Item.GetItemNumSockets.
--
-- The SCOPE GATE is unchanged: GetItemStats is a MAINLINE-FAMILY API
-- (documented on origin/live and origin/forever, absent from all three
-- Classic branches), so the Classic clients keep their documented no-socket
-- degradation. C_Item.GetItemNumSockets is documented on the Classic
-- branches TOO, and the mock installs it on every client -- so this block
-- proves that the GATE, and not the API's absence, is what degrades the
-- Classic clients.
do
    local function driveLocalScan(tag)
        namespace.Core.RequestLocalScan(tag)
        for _, frame in ipairs(FRAMES_BY_REGISTRATION) do
            if type(frame) == "table" and type(frame.GetScript) == "function"
                and type(frame:GetScript("OnUpdate")) == "function" then
                local script = frame:GetScript("OnUpdate")
                if type(script) == "function" then
                    pcall(script, frame)
                end
            end
        end
        return namespace.Scanner.GetCurrent()
    end

    local scanState = driveLocalScan("socket-capacity-pin")
    local scanRevision = scanState and scanState.revision or nil
    local slotOne = scanRevision and scanRevision.slots and scanRevision.slots[1] or nil
    local socketCell = slotOne and slotOne.sockets or nil
    if not ITEM_STATS then
        check(type(socketCell) == "table"
            and socketCell.status == "unavailable"
            and socketCell.reason == "socket-capability-unavailable",
            "without GetItemStats the socket path stays absent (the documented degradation)",
            "socket cell=" .. tostring(socketCell and socketCell.status)
                .. " reason=" .. tostring(socketCell and socketCell.reason))
        -- The socket-count API IS in the model on this client -- it is
        -- documented on the Classic branches too -- and the socket path is
        -- still absent. That is the point: the GATE is the gate, and the
        -- Classic clients' degradation is not an accident of the model.
        check(type(REALG.C_Item) == "table"
            and type(REALG.C_Item.GetItemNumSockets) == "function",
            "the socket-count API is present in the model where the socket path is gated off",
            "GetItemNumSockets="
                .. tostring(type(REALG.C_Item) == "table"
                    and type(REALG.C_Item.GetItemNumSockets)))
    elseif not slotOne then
        -- This run's scanner produced no occupied slot (the adapter refused,
        -- so there was nothing to inspect). The pin does not apply.
        out("   (this run's scan produced no occupied slot, so the socket pin does not apply)\n")
    else
        check(type(socketCell) == "table"
            and socketCell.status == "complete"
            and type(socketCell.value) == "table"
            and socketCell.value.capacity == 2,
            "the scanner reads the socket capacity from C_Item.GetItemNumSockets",
            "socket cell=" .. tostring(socketCell and socketCell.status)
                .. " capacity=" .. tostring(socketCell and socketCell.value
                    and socketCell.value.capacity))
        local scanResult = scanState and scanState.result or nil
        local metrics = scanResult and scanResult.metrics or nil
        local potential = metrics and metrics.potentialGS or nil
        check(potential ~= nil
            and tostring(potential.status) ~= "contradictory"
            and tostring(potential.reason or ""):find("socket-gem-mismatch", 1, true) == nil,
            "the socket capacity no longer contradicts the parsed gem list",
            "potentialGS=" .. tostring(potential and potential.status)
                .. " reason=" .. tostring(potential and potential.reason))
    end

    -- The two items the OLD stat-table sum got wrong. Under the fixed
    -- "EMPTY_SOCKET1..3 = 1" triple BOTH published three empty sockets; the
    -- truth is zero and zero. These are scanned END TO END -- the real
    -- Scanner, the real mock client, the real Scoring.Evaluate -- so the
    -- PUBLISHED count is what is checked, not a fixture.
    local ONE_SOCKET_LINK = "|cffffffff|Hitem:50010:0:41398:0:0"
        .. ":0:0:0:0:0:0:0:0:0:0:0:0:0|h[Harness One-Socket Helm]|h|r"
    local NO_SOCKET_LINK = "|cffffffff|Hitem:50011:0:0:0:0"
        .. ":0:0:0:0:0:0:0:0:0:0:0:0:0|h[Harness Sockless Helm]|h|r"
    registerItem({
        link = ONE_SOCKET_LINK, quality = 4, level = 200, equipLoc = "INVTYPE_HEAD",
    })
    registerItem({
        link = NO_SOCKET_LINK, quality = 4, level = 200, equipLoc = "INVTYPE_HEAD",
    })
    -- The client's item database: a one-socket headpiece, and one with no
    -- sockets at all.
    registerSocketCount(50010, 1)
    registerSocketCount(50011, 0)

    local origItemID = REALG.GetInventoryItemID
    local origItemLink = REALG.GetInventoryItemLink

    local function serveItem(itemID, link)
        REALG.GetInventoryItemID = function(unit, slotID)
            if unit == "player" and slotID == 1 then
                return itemID
            end
            return nil
        end
        REALG.GetInventoryItemLink = function(unit, slotID)
            if unit == "player" and slotID == 1 then
                return link
            end
            return nil
        end
    end

    local function publishedEmptySockets(state)
        local result = state and state.result or nil
        local item = result and result.items and result.items[1] or nil
        return item and item.emptyScoreBearingSockets or nil
    end

    local function scannedCapacity(state)
        local revision = state and state.revision or nil
        local slot = revision and revision.slots and revision.slots[1] or nil
        local cell = slot and slot.sockets or nil
        if type(cell) ~= "table" or cell.status ~= "complete" then
            return nil
        end
        return cell.value and cell.value.capacity or nil
    end

    if ITEM_STATS and slotOne then
        serveItem(50010, ONE_SOCKET_LINK)
        local oneState = driveLocalScan("socket-one-socket-pin")
        check(scannedCapacity(oneState) == 1,
            "a one-socket item is scanned with a capacity of one",
            "capacity=" .. tostring(scannedCapacity(oneState)))
        local oneEmpty = publishedEmptySockets(oneState)
        check(type(oneEmpty) == "table"
            and oneEmpty.status == "complete"
            and oneEmpty.value == 0,
            "a one-socket item with one gem publishes ZERO empty sockets, not the fixed triple's two",
            "empty=" .. tostring(oneEmpty and oneEmpty.value)
                .. " status=" .. tostring(oneEmpty and oneEmpty.status))

        serveItem(50011, NO_SOCKET_LINK)
        local noneState = driveLocalScan("socket-no-socket-pin")
        check(scannedCapacity(noneState) == 0,
            "a sockless item is scanned with a capacity of zero",
            "capacity=" .. tostring(scannedCapacity(noneState)))
        local noneEmpty = publishedEmptySockets(noneState)
        check(type(noneEmpty) == "table"
            and noneEmpty.status == "complete"
            and noneEmpty.value == 0,
            "a sockless item publishes ZERO empty sockets, not the fixed triple's three",
            "empty=" .. tostring(noneEmpty and noneEmpty.value)
                .. " status=" .. tostring(noneEmpty and noneEmpty.status))
    end

    -- Put the harness's own inventory back and re-drive the scan, so the
    -- later phases read exactly the state they would have read.
    REALG.GetInventoryItemID = origItemID
    REALG.GetInventoryItemLink = origItemLink
    driveLocalScan("socket-capacity-restore")
end

-- ---------------------------------------------------------------------------
-- Hunter M-NEW5: swallowed RankDB raises are counted, not just suppressed
-- ---------------------------------------------------------------------------
-- GetRankExtraLines wraps RankDB.GetRecord in pcall so a rank-store failure
-- can never break the unit tooltip (intentional display-only suppression) --
-- but the swallow was invisible. Revert map: delete the noteRankRecordError
-- calls in Tooltips.lua -> the counter below never moves (red).
do
    local RankDBMod = namespace.RankDB
    local realGetRecord = (type(RankDBMod) == "table" and RankDBMod.GetRecord) or nil
    local debugBefore5 = Tooltips.GetDebugState()
    local errsBefore5 = (debugBefore5 and debugBefore5.rankRecordErrors) or 0
    if (type(RankDBMod) == "table") then
        RankDBMod.GetRecord = function() error("MNEW5_PIN_GETRECORD") end
    end
    local okLines5, lines5 = pcall(Tooltips.GetRankExtraLines, "Player-1-00000001")
    if (type(RankDBMod) == "table") then
        RankDBMod.GetRecord = realGetRecord
    end
    local debugAfter5 = Tooltips.GetDebugState()
    local errsAfter5 = (debugAfter5 and debugAfter5.rankRecordErrors) or 0
    check(okLines5 == true and type(lines5) == "table" and #lines5 == 0,
        "a raising RankDB still yields no rank lines (suppression holds)",
        "ok=" .. tostring(okLines5) .. " lines=" .. tostring(lines5 and #lines5))
    check(errsAfter5 == errsBefore5 + 1,
        "the swallowed RankDB raise is counted in debug state",
        "rankRecordErrors=" .. tostring(errsBefore5) .. "->" .. tostring(errsAfter5))
    check(type(debugAfter5 and debugAfter5.lastRankRecordError) == "string",
        "...with the last error named",
        tostring(debugAfter5 and debugAfter5.lastRankRecordError))
end

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

-- ---------------------------------------------------------------------------
-- Options: the enhancement-reason label map
-- ---------------------------------------------------------------------------
--
-- The panel shows a reason CODE to the player when the map has no label for
-- it, so every reason that can OCCUR has to be mapped. Two facts are pinned
-- here, and neither of them is a matter of taste:
--
--   * "socket-capacity-exceeds-gem-list" is the too-large branch of the
--     socket cross-check -- Scoring.lua rejects a capacity the item's own gem
--     list cannot account for, and Scanner.lua withholds the same shape on the
--     socket cell. It OCCURS, so it must map to a plain sentence.
--   * "socket-order-unverified-above-three" labelled a reason the capacity
--     rewrite made unreachable: the capacity is no longer a sum of stat-table
--     keys, so nothing produces that reason any more. The sweep below proves
--     that no shipped file names it at all -- a label for a reason that can
--     never occur is a promise the code can no longer keep.
--
-- The second half renders the panel, because a label that never reaches the
-- screen is not a label: the reason is driven through the Options panel and
-- the RENDERED line has to carry the sentence, in the same shape its mapped
-- neighbours render in.
out(("\n-- options: the enhancement-reason label map --\n"))

local NEW_REASON = "socket-capacity-exceeds-gem-list"
local DEAD_REASON = "socket-order-unverified-above-three"

-- The map is a file-local table, so the shipped source IS the artifact under
-- test: the literal is parsed out of Options.lua and the entries themselves
-- are asserted.
local function parseEnhancementReasons()
    local raw = readFile(ROOT .. "/Options.lua")
    if type(raw) ~= "string" then
        return nil, "Options.lua is unreadable"
    end
    local marker = raw:find("local ENHANCEMENT_REASONS%s*=%s*{")
    if not marker then
        return nil, "no ENHANCEMENT_REASONS table in Options.lua"
    end
    local open = raw:find("{", marker, true)
    if not open then
        return nil, "the ENHANCEMENT_REASONS table has no opening brace"
    end
    local depth = 0
    local close = nil
    for index = open, #raw do
        local char = raw:sub(index, index)
        if char == "{" then
            depth = depth + 1
        elseif char == "}" then
            depth = depth - 1
            if depth == 0 then
                close = index
                break
            end
        end
    end
    if not close then
        return nil, "the ENHANCEMENT_REASONS table is not closed"
    end
    local body = raw:sub(open, close)
    local map = {}
    for key, value in body:gmatch('%["([^"]+)"%]%s*=%s*"([^"]*)"') do
        map[key] = value
    end
    return map
end

local reasonMap, reasonMapError = parseEnhancementReasons()
check(type(reasonMap) == "table",
    "the Options enhancement-reason map parses",
    tostring(reasonMapError))

local mappedLabel = type(reasonMap) == "table" and reasonMap[NEW_REASON] or nil

if type(reasonMap) == "table" then
    check(type(mappedLabel) == "string" and mappedLabel ~= "",
        "the " .. NEW_REASON .. " reason maps to a non-empty label",
        "label=" .. tostring(mappedLabel))
    check(type(mappedLabel) == "string"
        and mappedLabel ~= ""
        and mappedLabel ~= NEW_REASON
        and mappedLabel:find("%s") ~= nil,
        "the label is a plain sentence, not the raw reason code",
        "label=" .. tostring(mappedLabel))
    check(reasonMap[DEAD_REASON] == nil,
        "the dead " .. DEAD_REASON .. " reason is gone from the map",
        "still mapped to " .. tostring(reasonMap[DEAD_REASON]))
end

-- Nothing shipped may still produce the dead reason. The map is one place;
-- this sweep is the other, and it is the one that matters -- a PRODUCER is
-- what makes a reason live, so a producer is what would make the label a
-- promise again.
local SHIPPED_ADDON_FILES = {
    "Core.lua", "Scoring.lua", "Cache.lua", "RankDB.lua", "RankSync.lua",
    "Scanner.lua", "TacoTipAdapter.lua", "Tooltips.lua", "Frames.lua",
    "RankBrowser.lua", "Minimap.lua", "Options.lua",
}
local deadProducers = {}
for _, fileName in ipairs(SHIPPED_ADDON_FILES) do
    local raw = readFile(ROOT .. "/" .. fileName)
    if type(raw) == "string"
        and raw:find(DEAD_REASON, 1, true) ~= nil then
        deadProducers[#deadProducers + 1] = fileName
    end
end
check(#deadProducers == 0,
    "no shipped file names the dead " .. DEAD_REASON .. " reason",
    "named in: " .. table.concat(deadProducers, ", "))

-- The rendered panel line, not just the map.
do
    -- The module table is the one bound at file scope above -- the same table
    -- the add-on reads, so replacing the getter is replacing what the panel
    -- will call.
    local savedGetter = Tooltips.GetEnhancementStatus
    local savedSetText = METHOD_CACHE["Frame"].SetText
    local captured = {}

    patch("SetText", function(f, value)
        rawset(f, "__text", tostring(value or ""))
        captured[#captured + 1] = tostring(value or "")
    end)

    local function render(reason, slotID)
        captured = {}
        Tooltips.GetEnhancementStatus = function()
            return "unavailable", reason, "remote", slotID, 0
        end
        Options.Refresh()
        local remote, blocker = nil, nil
        for _, text in ipairs(captured) do
            if text:find("Remote enhancement analysis:", 1, true) == 1 then
                remote = text
            elseif text:find("Remote enhancement blocker:", 1, true) == 1 then
                blocker = text
            end
        end
        return remote, blocker
    end

    -- Slot 4 is not a DIAGNOSTIC_SLOTS entry (the shirt carries no sockets and
    -- no enchants, so there is nothing to diagnose on it), so the panel takes
    -- the reason branch and shows the LABEL. Slot 16 is a diagnostic slot, so
    -- the panel takes the blocker branch, which carries the raw code for
    -- EVERY reason -- mapped or not.
    local newRemote = render(NEW_REASON, 4)
    local neighbourRemote = render("socket-capacity-unavailable", 4)
    local _, newBlocker = render(NEW_REASON, 16)
    local _, neighbourBlocker = render("socket-capacity-unavailable", 16)

    Tooltips.GetEnhancementStatus = savedGetter
    patch("SetText", savedSetText)

    check(type(newRemote) == "string"
        and type(mappedLabel) == "string"
        and newRemote:find(mappedLabel, 1, true) ~= nil,
        "the panel renders the " .. NEW_REASON .. " reason as its mapped sentence",
        "rendered: " .. tostring(newRemote))
    check(type(newRemote) == "string"
        and newRemote:find(NEW_REASON, 1, true) ~= nil,
        "the rendered line names the raw code beside the sentence, as it does for every mapped reason",
        "rendered: " .. tostring(newRemote))
    check(type(neighbourRemote) == "string"
        and neighbourRemote:find("socket capacity is unavailable", 1, true) ~= nil
        and neighbourRemote:find("socket-capacity-unavailable", 1, true) ~= nil,
        "a mapped neighbour renders in the same shape",
        "rendered: " .. tostring(neighbourRemote))
    check(type(newBlocker) == "string"
        and type(neighbourBlocker) == "string"
        and newBlocker:find(NEW_REASON, 1, true) ~= nil
        and neighbourBlocker:find("socket-capacity-unavailable", 1, true) ~= nil,
        "the diagnostic-slot blocker line names the raw code for the new reason exactly as it does for a neighbour",
        "new=" .. tostring(newBlocker) .. " neighbour=" .. tostring(neighbourBlocker))
end

-- ---------------------------------------------------------------------------
-- Options: the numbered socket-mismatch family
-- ---------------------------------------------------------------------------
--
-- "socket-gem-mismatch-N" is a DYNAMIC code -- the socket position that
-- contradicts the capacity is part of the code itself -- so no exact-key
-- table can hold it, and the panel used to show the raw code to the player.
--
-- Three things are pinned here, and none of them is a matter of taste:
--
--   * EVERY index in the family renders a plain sentence. The family is
--     resolved by a documented prefix rule, so a new index needs no new map
--     entry, and the map must therefore NOT spell the family out one key per
--     index.
--   * The sentence does not carry the index. "2" is an internal socket
--     position, not something a player can act on, so no digit of it may
--     reach the player-facing line, and the raw code may not either.
--   * The raw code is still visible where it belongs -- the diagnostic-slot
--     blocker line -- for the family and for every other reason, and a
--     reason outside the family renders EXACTLY as it did before.
out(("\n-- options: the numbered socket-mismatch family --\n"))

do
    local savedGetter = Tooltips.GetEnhancementStatus
    local savedSetText = METHOD_CACHE["Frame"].SetText
    local captured = {}

    patch("SetText", function(f, value)
        rawset(f, "__text", tostring(value or ""))
        captured[#captured + 1] = tostring(value or "")
    end)

    local function render(reason, slotID)
        captured = {}
        Tooltips.GetEnhancementStatus = function()
            return "unavailable", reason, "remote", slotID, 0
        end
        Options.Refresh()
        local remote, blocker = nil, nil
        for _, text in ipairs(captured) do
            if text:find("Remote enhancement analysis:", 1, true) == 1 then
                remote = text
            elseif text:find("Remote enhancement blocker:", 1, true) == 1 then
                blocker = text
            end
        end
        return remote, blocker
    end

    -- The family the socket cross-check produces: the position that
    -- contradicts the capacity, 1..3 (SOCKET_POSITIONS).
    local FAMILY = {
        "socket-gem-mismatch-1",
        "socket-gem-mismatch-2",
        "socket-gem-mismatch-3",
    }
    -- A reason OUTSIDE the family: the neighbour that must not change.
    local NEIGHBOUR = "socket-capacity-unavailable"
    local NEIGHBOUR_LABEL = "socket capacity is unavailable"
    -- The line the neighbour rendered before the family was touched. It is
    -- pinned whole, because "no behaviour change for any other reason" is
    -- the claim being made.
    local NEIGHBOUR_LINE = "Remote enhancement analysis: unavailable ("
        .. NEIGHBOUR_LABEL .. "; " .. NEIGHBOUR .. ")"

    local familySentence = nil
    local familyOK = true

    for _, reason in ipairs(FAMILY) do
        -- Slot 4 is not a diagnostic slot, so the panel takes the reason
        -- branch and shows the LABEL; slot 16 is a diagnostic slot, so the
        -- panel takes the blocker branch, which carries the raw code.
        local remote = render(reason, 4)
        local _, blocker = render(reason, 16)

        local sentence = type(remote) == "string"
            and remote:match("%(([^()]*)%)") or nil

        check(type(remote) == "string" and type(sentence) == "string"
            and sentence ~= "" and sentence ~= reason,
            reason .. ": the panel renders a plain sentence for the family, not the raw code",
            "rendered: " .. tostring(remote))
        check(type(sentence) == "string"
            and sentence:find("%d") == nil,
            reason .. ": the rendered sentence leaks no index digit",
            "sentence=" .. tostring(sentence))
        check(type(remote) == "string"
            and remote:find(reason, 1, true) == nil,
            reason .. ": the player-facing line carries no raw code",
            "rendered: " .. tostring(remote))
        check(type(sentence) == "string"
            and sentence:find("socket", 1, true) ~= nil
            and sentence:find("gem", 1, true) ~= nil,
            reason .. ": the sentence is about the socket count and the gem list",
            "sentence=" .. tostring(sentence))
        check(type(blocker) == "string"
            and blocker:find(reason, 1, true) ~= nil,
            reason .. ": the diagnostic-slot blocker line still names the raw code",
            "rendered: " .. tostring(blocker))

        if type(sentence) == "string" and sentence ~= "" then
            if familySentence == nil then
                familySentence = sentence
            elseif familySentence ~= sentence then
                familyOK = false
            end
        end
    end

    check(familyOK and type(familySentence) == "string",
        "every index in the family renders the same sentence",
        "sentence=" .. tostring(familySentence))

    -- The family is a PREFIX rule, not one map entry per index.
    local familyKeys = {}
    if type(reasonMap) == "table" then
        for key in pairs(reasonMap) do
            if key:find("socket%-gem%-mismatch") then
                familyKeys[#familyKeys + 1] = key
            end
        end
    end
    check(#familyKeys == 0,
        "the map does not spell the family out one key per index",
        "keys: " .. table.concat(familyKeys, ", "))

    -- A reason outside the family renders exactly as it did before.
    local neighbourRemote = render(NEIGHBOUR, 4)
    local _, neighbourBlocker = render(NEIGHBOUR, 16)

    check(type(neighbourRemote) == "string"
        and neighbourRemote == NEIGHBOUR_LINE,
        "a reason outside the family renders the same line as before",
        "rendered: " .. tostring(neighbourRemote))
    check(type(neighbourBlocker) == "string"
        and neighbourBlocker:find(NEIGHBOUR, 1, true) ~= nil,
        "the diagnostic-slot blocker line for a reason outside the family still names the raw code",
        "rendered: " .. tostring(neighbourBlocker))

    Tooltips.GetEnhancementStatus = savedGetter
    patch("SetText", savedSetText)
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
        check(s.tooltip ~= nil and s.tooltip.mode == "Detailed",
            "default tooltip mode is Detailed",
            "got " .. tostring(s.tooltip and s.tooltip.mode))
        check(s.equipmentDisplay ~= nil and s.equipmentDisplay.mode == "Detailed",
            "default equipment display mode is Detailed",
            "got " .. tostring(s.equipmentDisplay and s.equipmentDisplay.mode))
        -- The WHOLE fresh-profile default, not just the mode: Unenhanced GS
        -- off and the summary positions locked. The two identical
        -- "fresh profile" / "migrated profile" functions were collapsed into
        -- one, so these three values are now written in one place and all
        -- three are pinned here.
        check(s.equipmentDisplay ~= nil
                and s.equipmentDisplay.showUnenhanced == false,
            "default equipment display leaves Unenhanced GS off",
            "got " .. tostring(s.equipmentDisplay and s.equipmentDisplay.showUnenhanced))
        check(s.equipmentDisplay ~= nil and s.equipmentDisplay.locked == true,
            "default equipment display starts with the positions locked",
            "got " .. tostring(s.equipmentDisplay and s.equipmentDisplay.locked))
        check(s.shamanBlue == true,
            "default Shaman Blue setting is on",
            "got " .. tostring(s.shamanBlue))
    end
end

-- ---------------------------------------------------------------------------
-- The tooltip mode default is a FRESH-INSTALL default, not a migration
-- ---------------------------------------------------------------------------
--
-- The saved mode is a plain string. Nothing in the settings table records
-- whether the USER chose it or whether it is only the old default that was
-- written once and never touched, so "Compact" on an existing install is
-- ambiguous: it may be an untouched old default, or a deliberate choice.
--
-- Overwriting a saved "Compact" would silently throw away a deliberate
-- choice, so the add-on does not. This pins both halves of that decision:
-- a saved mode survives untouched, and a MISSING mode resolves to the new
-- Detailed default.
do
    local core = namespace.Core
    local saved = type(REALG.TacoTipExtrasDB) == "table"
        and type(REALG.TacoTipExtrasDB.settings) == "table"
        and type(REALG.TacoTipExtrasDB.settings.tooltip) == "table"
        and REALG.TacoTipExtrasDB.settings.tooltip or nil
    if type(saved) == "table" and type(core) == "table"
        and type(core.ApplySettings) == "function" then
        saved.mode = "Compact"
        core.ApplySettings()
        check(saved.mode == "Compact",
            "an explicitly saved tooltip mode is preserved (no migration overrides it)",
            "got " .. tostring(saved.mode))
        -- Put the mode back the way a fresh install has it, so the rest of
        -- this run exercises the shipped default.
        saved.mode = nil
        core.ApplySettings()
        check(saved.mode == "Detailed",
            "a missing saved tooltip mode resolves to the Detailed default",
            "got " .. tostring(saved.mode))
    end
end

-- ---------------------------------------------------------------------------
-- The options control shows the mode that is actually in effect
-- ---------------------------------------------------------------------------
--
-- The panel's dropdown is not decoration: it is how the player reads and
-- changes the mode the add-on is running in. It has to show the EFFECTIVE
-- mode, so a pin reads the selected value back off the control instead of
-- trusting the panel's own source.
do
    local options = namespace.Options
    local dropdown = REALG.TacoTip_ExtrasTooltipModeDropdown
    if type(options) == "table" and type(options.Refresh) == "function"
        and type(dropdown) == "table" then
        options.Refresh()
        check(REALG.UIDropDownMenu_GetSelectedValue(dropdown) == "Detailed",
            "the tooltip-mode control shows the effective mode (Detailed)",
            "showed " .. tostring(REALG.UIDropDownMenu_GetSelectedValue(dropdown)))
        check(DROPDOWN_TEXT[dropdown] == "Detailed",
            "the tooltip-mode control labels itself with the effective mode",
            "showed " .. tostring(DROPDOWN_TEXT[dropdown]))
    end
end

-- ---------------------------------------------------------------------------
-- The options page's two-column layout (operator's screenshot)
-- ---------------------------------------------------------------------------
--
-- The tooltip page is two columns of checkboxes: the left column at x=16 and
-- the right column at x=290. Three things went wrong and all three are
-- geometry:
--
--   1. The long left label "Restrict Potential, Completion, and warnings to
--      level 70" had no width cap, so it ran straight through the right
--      column's "Show server leaderboard rank" control.
--   2. Every checkbox's hit rect was expanded a flat 240 or 500 pixels to
--      the RIGHT -- the SetHitRectInsets argument order is (left, right,
--      top, bottom), so the second argument is a RIGHT expansion -- which
--      reached across the column gap. A left-column control's clickable
--      region, and the button highlight the client draws over it, landed on
--      the right column's control.
--   3. The columns' LABELS did not line up, because each label was as long
--      as its own text.
--
-- The pins read the geometry the module actually produced. The mock records
-- every anchor, size and hit-rect inset, and the check button's size comes
-- from the template the client gives it (26x26, cited in TEMPLATE_SIZES).
do
    local panel = REALG.TacoTip_ExtrasOptionsPanel
    local RIGHT_COLUMN_X = 290
    local CHECKBOX_SIZE = 26
    local LABEL_GAP = 2

    local function pointOf(widget)
        return rawget(widget, "__point")
    end

    -- The clickable rectangle of a control: its own rect, adjusted by the
    -- hit-rect insets. A NEGATIVE inset expands, so a right inset of -240
    -- puts the right edge 240 pixels further right.
    local function hitRect(widget)
        local p = pointOf(widget)
        if not p then return nil end
        local insets = rawget(widget, "__hitInsets") or {}
        local width = rawget(widget, "__width") or 0
        local height = rawget(widget, "__height") or 0
        local left = p.x - (insets.left or 0)
        local right = p.x + width - (insets.right or 0)
        local top = p.y - (insets.top or 0)
        local bottom = p.y + height - (insets.bottom or 0)
        return {
            left = left, right = right, top = top, bottom = bottom,
            name = rawget(widget, "__name") or "control",
            widget = widget,
        }
    end

    local function overlaps(a, b)
        return a.left < b.right and b.left < a.right
            and a.top < b.bottom and b.top < a.bottom
    end

    if type(panel) == "table" and type(panel.__children) == "table" then
        -- Every checkbox on the tooltip page, with the geometry the client
        -- will lay it out with.
        local boxes = {}
        local labels = {}
        for _, child in ipairs(panel.__children) do
            if rawget(child, "__kind") == "CheckButton" then
                local rect = hitRect(child)
                if rect then
                    boxes[#boxes + 1] = rect
                    labels[#labels + 1] = child
                end
            end
        end
        check(#boxes > 0,
            "the options page builds checkboxes",
            "found " .. tostring(#boxes))

        -- PIN 1: no two controls' hit rects overlap.
        local hitCollisions = {}
        for i = 1, #boxes do
            for j = i + 1, #boxes do
                if overlaps(boxes[i], boxes[j]) then
                    hitCollisions[#hitCollisions + 1] = boxes[i].name
                        .. " / " .. boxes[j].name
                end
            end
        end
        check(#hitCollisions == 0,
            "no two checkbox hit rects overlap",
            table.concat(hitCollisions, ", "))

        -- The clickable region must also stay inside its own column, or it
        -- reaches the other column's control.
        local escapes = {}
        for _, rect in ipairs(boxes) do
            local p = pointOf(rect.widget)
            if p and p.x < RIGHT_COLUMN_X and rect.right > RIGHT_COLUMN_X then
                escapes[#escapes + 1] = rect.name .. " reaches x="
                    .. tostring(rect.right)
            end
        end
        check(#escapes == 0,
            "no checkbox's clickable region reaches into the right column",
            table.concat(escapes, ", "))

        -- PIN 2: no label overflows the next column. The label is capped to
        -- its column's width and wraps inside it.
        local labelOverflows = {}
        local unwrapped = {}
        for _, control in ipairs(labels) do
            local p = pointOf(control)
            local label = rawget(control, "optionLabel")
            if p and type(label) == "table" then
                -- The label's EFFECTIVE width: the explicit cap if it has
                -- one, otherwise the text's own width, because a FontString
                -- with no width sizes itself to its text.
                local labelWidth = label:GetWidth() or 0
                local labelRight = p.x + CHECKBOX_SIZE + LABEL_GAP + labelWidth
                if p.x < RIGHT_COLUMN_X and labelRight > RIGHT_COLUMN_X then
                    labelOverflows[#labelOverflows + 1] = rawget(control, "__name")
                        .. " label reaches x=" .. tostring(labelRight)
                end
                if rawget(label, "__wordWrap") ~= true then
                    unwrapped[#unwrapped + 1] = rawget(control, "__name")
                end
            end
        end
        check(#labelOverflows == 0,
            "no checkbox label overflows into the next column",
            table.concat(labelOverflows, ", "))
        check(#unwrapped == 0,
            "every checkbox label wraps inside its column",
            table.concat(unwrapped, ", "))
    end

    -- PIN 3: every checkbox uses a template the CLIENT has.
    --
    -- The whitelist is the client's own template list, verified in the mirror
    -- on ALL FIVE branches:
    --   InterfaceOptionsCheckButtonTemplate
    --     origin/classic_era          Interface/AddOns/Blizzard_FrameXML/DeprecatedTemplates.xml:34
    --     origin/classic_anniversary  Interface/AddOns/Blizzard_FrameXML/DeprecatedTemplates.xml:34
    --     origin/classic_titan        Interface/AddOns/Blizzard_FrameXML/DeprecatedTemplates.xml:34
    --     origin/forever              Interface/AddOns/Blizzard_FrameXML/DeprecatedTemplates.xml:34
    --     origin/live                 Interface/AddOns/Blizzard_FrameXML/DeprecatedTemplates.xml:34
    --   UIPanelButtonTemplate
    --     origin/classic_era          Interface/AddOns/Blizzard_SharedXML/Classic/SharedUIPanelTemplates.xml
    --     origin/classic_anniversary  Interface/AddOns/Blizzard_SharedXML/Classic/SharedUIPanelTemplates.xml
    --     origin/classic_titan        Interface/AddOns/Blizzard_SharedXML/Classic/SharedUIPanelTemplates.xml
    --     origin/forever              Interface/AddOns/Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml
    --     origin/live                 Interface/AddOns/Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml
    --   UIPanelCloseButton   -- the same two files, all five branches
    --   UIDropDownMenuTemplate
    --     origin/classic_era          Interface/AddOns/Blizzard_SharedXML/Classic/UIDropDownMenuTemplates.xml
    --     origin/classic_anniversary  Interface/AddOns/Blizzard_SharedXML/Classic/UIDropDownMenuTemplates.xml
    --     origin/classic_titan        Interface/AddOns/Blizzard_SharedXML/Classic/UIDropDownMenuTemplates.xml
    --     origin/forever              Interface/AddOns/Blizzard_SharedXML/Mainline/UIDropDownMenuTemplates.xml
    --     origin/live                 Interface/AddOns/Blizzard_SharedXML/Mainline/UIDropDownMenuTemplates.xml
    --
    -- A template the client does not define is not a harmless no-op: the
    -- client RAISES on an unknown template, so the whole page fails to build.
    local CLIENT_TEMPLATES = {
        InterfaceOptionsCheckButtonTemplate = true,
        UIPanelButtonTemplate = true,
        UIPanelCloseButton = true,
        UIDropDownMenuTemplate = true,
    }
    do
        local unknown = {}
        local checked = 0
        for _, child in ipairs(panel and panel.__children or {}) do
            -- A FontString's "template" is a FONT name (GameFontHighlight and
            -- friends) and a Texture's is a LAYER (ARTWORK) -- neither is a
            -- frame template, and both are checked elsewhere.
            local kind = rawget(child, "__kind")
            local template = rawget(child, "__template")
            if kind ~= "FontString" and kind ~= "Texture"
                and type(template) == "string" then
                checked = checked + 1
                if not CLIENT_TEMPLATES[template] then
                    unknown[#unknown + 1] = template
                end
            end
        end
        check(checked > 0,
            "the options page uses templated frames",
            "found " .. tostring(checked))
        check(#unknown == 0,
            "every template the options page uses is one the client defines",
            table.concat(unknown, ", "))
    end

    -- The "Comfortable rows" checkbox is synced to its setting. It was the
    -- one control Options.Refresh never setChecked, so a profile that had the
    -- setting on came up with the box looking off.
    do
        local options = namespace.Options
        local comfortableControl = REALG.TacoTip_ExtrasOptionComfortableRows
        local rootSettings = REALG.TacoTipExtrasDB
            and REALG.TacoTipExtrasDB.settings or nil
        if type(options) == "table" and type(options.Refresh) == "function"
            and type(comfortableControl) == "table"
            and type(rootSettings) == "table" then
            rootSettings.comfortableRows = true
            options.Refresh()
            check(comfortableControl:GetChecked() == true,
                "the Comfortable rows control shows its setting (on)",
                "checked=" .. tostring(comfortableControl:GetChecked()))
            rootSettings.comfortableRows = false
            options.Refresh()
            check(comfortableControl:GetChecked() == false,
                "the Comfortable rows control shows its setting (off)",
                "checked=" .. tostring(comfortableControl:GetChecked()))
            rootSettings.comfortableRows = nil
        end
    end
end

-- ---------------------------------------------------------------------------
-- A plain frame has no backdrop API
-- ---------------------------------------------------------------------------
--
-- Only a template that mixes in BackdropTemplateMixin carries SetBackdrop /
-- GetBackdrop / SetBackdropColor; a plain frame has NONE of them (the
-- client-source citations are in the mock's __index comment).
--
-- The mock used to hand the whole set to every frame, so a plain frame
-- asking for a backdrop LOOKED like it got one. That is exactly how the
-- Extras' GEAR PANEL shipped TRANSPARENT: its `if f.SetBackdrop then` guard
-- was skipped in the real client, and the harness could not see it.
do
    local plain = REALG.CreateFrame("Frame")
    check(type(plain) == "table" and plain.SetBackdrop == nil,
        "a plain frame in this environment has no SetBackdrop",
        "got " .. type(plain and plain.SetBackdrop))
    check(type(plain.__absent) == "table" and plain.__absent.SetBackdrop == true,
        "the plain frame records the backdrop API as absent",
        tostring(plain.__absent and plain.__absent.SetBackdrop))
    -- The mock's default is the CLIENT's default: a frame the client creates
    -- is VISIBLE. Blizzard's own panels carry hidden="true" on the FRAME and
    -- never on the template, and Blizzard's code creates frames and then hides
    -- them explicitly -- the citations are in the mock's newRegion.
    check(plain:IsShown() == true,
        "a frame created in this environment is visible, as in the client",
        "shown=" .. tostring(plain:IsShown()))
    local backdrop = REALG.CreateFrame(
        "Frame",
        "HarnessBackdropProbe",
        nil,
        "BackdropTemplate"
    )
    check(type(backdrop) == "table" and type(backdrop.SetBackdrop) == "function",
        "a BackdropTemplate frame carries the backdrop API",
        "got " .. type(backdrop and backdrop.SetBackdrop))
end

-- ---------------------------------------------------------------------------
-- Shaman Blue: the shared resolver, and the one place it is decided
-- ---------------------------------------------------------------------------
--
-- The class colour is painted in three surfaces -- the unit tooltip, the
-- character/inspect summary frame and the leaderboard row -- and all three
-- read ONE resolver. That is the whole point: a player whose tooltip says
-- blue and whose leaderboard row says pink is a bug report waiting to happen.
--
-- These pins cover the resolver itself, the persistence of the setting and
-- the shape of the shared rule. The RENDERED tooltip is pinned in the Server
-- Rank block above; the rendered leaderboard row is pinned in
-- rankbrowser_test.lua.
do
    out(("\n-- Shaman Blue: the shared resolver --\n"))
    local core = namespace.Core
    local rootSettings = REALG.TacoTipExtrasDB
        and REALG.TacoTipExtrasDB.settings or nil

    if type(core) == "table"
        and type(core.GetClassColorOverride) == "function" then
        -- The blue is the main add-on's SHAMAN_BLUE_COLOR (main.lua), which
        -- is the TBC/Wrath Shaman colour:
        --   origin/classic_era
        --   Interface/AddOns/Blizzard_SharedXML/TBC/ClassColors.lua:9
        --       ["SHAMAN"] = CreateColor(0.0, 0.44, 0.87)
        -- and Classic Era's own is pink:
        --   origin/classic_era
        --   Interface/AddOns/Blizzard_SharedXML/Vanilla/ClassColors.lua:9
        --       ["SHAMAN"] = CreateColor(0.96, 0.55, 0.73)
        if type(rootSettings) == "table" then
            rootSettings.shamanBlue = true
        end
        local red, green, blue = core.GetClassColorOverride("SHAMAN")
        check(red == 0.0 and green == 0.44 and blue == 0.87,
            "the Shaman-blue override is the main add-on's colour (0, 0.44, 0.87)",
            "got " .. tostring(red) .. "," .. tostring(green) .. "," .. tostring(blue))

        -- The rule is Shaman-only.
        local otherRed, otherGreen, otherBlue = core.GetClassColorOverride("WARRIOR")
        check(otherRed == nil and otherGreen == nil and otherBlue == nil,
            "the Shaman-blue override never touches another class",
            "got " .. tostring(otherRed) .. "," .. tostring(otherGreen)
                .. "," .. tostring(otherBlue))

        if type(rootSettings) == "table" then
            rootSettings.shamanBlue = false
        end
        local offRed = core.GetClassColorOverride("SHAMAN")
        check(offRed == nil,
            "the Shaman-blue override is gone when the setting is off",
            "got " .. tostring(offRed))

        -- The main add-on's value is read defensively. Only an explicit
        -- boolean false suppresses the rule; an absent table, a nil value
        -- and a non-boolean all degrade to the Extras' own setting.
        local savedConfig = REALG.TacoTipConfig
        if type(rootSettings) == "table" then
            rootSettings.shamanBlue = true
        end
        local degraded = {}
        REALG.TacoTipConfig = nil
        degraded[#degraded + 1] = core.IsShamanBlueEnabled()
        REALG.TacoTipConfig = {}
        degraded[#degraded + 1] = core.IsShamanBlueEnabled()
        REALG.TacoTipConfig = { shaman_blue = nil }
        degraded[#degraded + 1] = core.IsShamanBlueEnabled()
        REALG.TacoTipConfig = { shaman_blue = "yes" }
        degraded[#degraded + 1] = core.IsShamanBlueEnabled()
        REALG.TacoTipConfig = { shaman_blue = false }
        degraded[#degraded + 1] = core.IsShamanBlueEnabled()
        REALG.TacoTipConfig = savedConfig
        check(degraded[1] == true and degraded[2] == true and degraded[3] == true
                and degraded[4] == true,
            "an absent, nil or non-boolean main add-on value degrades to the Extras' own setting",
            "got " .. tostring(degraded[1]) .. "," .. tostring(degraded[2]) .. ","
                .. tostring(degraded[3]) .. "," .. tostring(degraded[4]))
        check(degraded[5] == false,
            "an explicit false in the main add-on suppresses the rule",
            "got " .. tostring(degraded[5]))

        -- The setting lives in the SavedVariables table, so it survives a
        -- reload. Re-running the normalisation is what a reload does to that
        -- table (Core.ApplySettings normalises it).
        if type(core) == "table" and type(core.ApplySettings) == "function"
            and type(rootSettings) == "table" then
            rootSettings.shamanBlue = false
            core.ApplySettings()
            check(rootSettings.shamanBlue == false,
                "the Shaman Blue setting survives a reload (still off after re-normalising)",
                "got " .. tostring(rootSettings.shamanBlue))
            rootSettings.shamanBlue = nil
            core.ApplySettings()
            check(rootSettings.shamanBlue == true,
                "a missing Shaman Blue setting resolves to the shipped default (on)",
                "got " .. tostring(rootSettings.shamanBlue))
        end
    end

    -- ONE resolver, THREE call sites.
    --
    -- The character/inspect frame's rows are anonymous FontStrings the mock
    -- does not expose, so that surface's rendered text cannot be read back
    -- here. What CAN be pinned -- and is the property that matters -- is that
    -- the rule is decided once and every surface asks for it, instead of each
    -- one resolving the colour for itself and drifting apart.
    --
    -- The resolver is Core.GetClassColor, which owns the WHOLE chain (the
    -- Shaman-blue override, then the community colour table, then the
    -- client's own table). Each surface keeps its OWN accept rule and its OWN
    -- fallback -- that is what keeps the leaderboard's hardcoded class table
    -- and the tooltip's neutral grey exactly as they were -- but the chain
    -- itself is read from ONE place.
    for _, file in ipairs({ "Tooltips.lua", "Frames.lua", "RankBrowser.lua" }) do
        local source = readFile(ROOT .. "/" .. file)
        check(type(source) == "string"
                and source:find("GetClassColor(", 1, true) ~= nil,
            file .. " resolves the class colour through the shared Core resolver",
            "no Core.GetClassColor call in " .. file)
        check(type(source) == "string"
                and source:find("SHAMAN_BLUE_COLOR", 1, true) == nil,
            file .. " carries no second copy of the Shaman blue",
            "a SHAMAN_BLUE_COLOR literal found in " .. file)
        -- The chain itself must exist in exactly one place. A surface that
        -- read the client's colour tables for itself would be a second copy
        -- of the chain, and the two copies could drift again.
        check(type(source) == "string"
                and source:find("CUSTOM_CLASS_COLORS", 1, true) == nil
                and source:find("RAID_CLASS_COLORS", 1, true) == nil,
            file .. " reads no class-colour table of its own",
            "a class-colour table literal found in " .. file)
    end
    do
        local coreSource = readFile(ROOT .. "/Core.lua")
        check(type(coreSource) == "string"
                and coreSource:find("CUSTOM_CLASS_COLORS", 1, true) ~= nil
                and coreSource:find("RAID_CLASS_COLORS", 1, true) ~= nil
                and coreSource:find("function Core.GetClassColor(", 1, true) ~= nil,
            "Core.lua owns the whole class-colour chain",
            "the chain is not in Core.lua")
    end

    -- The chain's BEHAVIOUR, per surface rule.
    --
    -- The three surfaces kept their own accept rule and their own fallback
    -- through the refactor, so this pins both:
    --
    --   the tooltip's rule    a community colour must be three finite
    --                          numbers in 0..1; anything else is refused and
    --                          the surface falls back to neutral grey.
    --   the leaderboard's rule any three numbers are a colour, and the
    --                          leaderboard falls back to its own hardcoded
    --                          13-entry table.
    --
    -- A normal class, an unknown class and an out-of-range community colour
    -- are the three cases that separated the copies, so they are the three
    -- pinned here.
    do
        local chainCore = namespace.Core
        local savedRaid = REALG.RAID_CLASS_COLORS
        local savedCustom = REALG.CUSTOM_CLASS_COLORS
        local strict = function(red, green, blue)
            return type(red) == "number" and red == red and red >= 0 and red <= 1
                and type(green) == "number" and green == green and green >= 0 and green <= 1
                and type(blue) == "number" and blue == blue and blue >= 0 and blue <= 1
        end
        local permissive = function(red, green, blue)
            return type(red) == "number"
                and type(green) == "number"
                and type(blue) == "number"
        end
        check(type(chainCore) == "table" and type(chainCore.GetClassColor) == "function",
            "Core.GetClassColor is published", type(chainCore))
        if type(chainCore) == "table" and type(chainCore.GetClassColor) == "function" then
            REALG.RAID_CLASS_COLORS = { WARRIOR = { r = 1, g = 0.8, b = 0.5 } }
            REALG.CUSTOM_CLASS_COLORS = nil

            -- A class the CLIENT knows: both rules take the client's colour.
            local wr, wg, wb = chainCore.GetClassColor("WARRIOR", { accept = strict })
            check(wr == 1 and wg == 0.8 and wb == 0.5,
                "the chain returns the client's colour for a class the client knows",
                tostring(wr) .. "," .. tostring(wg) .. "," .. tostring(wb))
            local pwr, pwg, pwb = chainCore.GetClassColor("WARRIOR", { accept = permissive })
            check(pwr == 1 and pwg == 0.8 and pwb == 0.5,
                "the permissive rule returns the same colour for a class the client knows",
                tostring(pwr) .. "," .. tostring(pwg) .. "," .. tostring(pwb))

            -- A class the client does NOT know: the chain finds nothing, so
            -- each surface applies its OWN fallback -- neutral grey for the
            -- tooltip and the frame, the leaderboard's own table for the row.
            local ur = chainCore.GetClassColor("ROGUE", { accept = strict })
            check(ur == nil,
                "the chain finds nothing for a class the client does not know",
                tostring(ur))
            local pur = chainCore.GetClassColor("ROGUE", { accept = permissive })
            check(pur == nil,
                "the permissive rule also finds nothing for an unknown class",
                tostring(pur))

            -- A community colour OUTSIDE 0..1: the strict rule refuses it
            -- (the tooltip falls back to neutral grey) and the permissive rule
            -- takes it (the leaderboard has always taken a community colour
            -- at its word).
            REALG.CUSTOM_CLASS_COLORS = { ROGUE = { r = 2, g = 0.5, b = 0.5 } }
            local cr, cg, cb = chainCore.GetClassColor("ROGUE", { accept = strict })
            check(cr == nil,
                "the strict rule refuses a community colour outside 0..1",
                tostring(cr) .. "," .. tostring(cg) .. "," .. tostring(cb))
            local pcr, pcg, pcb = chainCore.GetClassColor("ROGUE", { accept = permissive })
            check(pcr == 2 and pcg == 0.5 and pcb == 0.5,
                "the permissive rule keeps a community colour outside 0..1",
                tostring(pcr) .. "," .. tostring(pcg) .. "," .. tostring(pcb))

            -- A non-table community colour must never raise.
            REALG.CUSTOM_CLASS_COLORS = "junk-string"
            local okChain = pcall(chainCore.GetClassColor, "ROGUE", { accept = permissive })
            check(okChain,
                "a non-table community colour never raises the chain")

            REALG.RAID_CLASS_COLORS = savedRaid
            REALG.CUSTOM_CLASS_COLORS = savedCustom
        end
    end

    -- The option is on the panel, labelled in the player's language, and
    -- showing the setting the add-on is actually running on.
    do
        local shamanCheck = REALG.TacoTip_ExtrasOptionShamanBlue
        local options = namespace.Options
        check(type(shamanCheck) == "table",
            "the Shaman Blue option exists on the panel",
            "got " .. type(shamanCheck))
        local expectedLabel = type(_G.TACOEXTRAS_LOCALE) == "table"
            and _G.TACOEXTRAS_LOCALE["HELP_SHAMANBLUE_HEADING"] or nil
        check(expectedLabel ~= nil and expectedLabel ~= ""
                and type(shamanCheck.optionLabel) == "table"
                and shamanCheck.optionLabel:GetText() == expectedLabel,
            "the Shaman Blue option is labelled with the localized heading",
            "wanted=" .. tostring(expectedLabel) .. " got="
                .. tostring(shamanCheck.optionLabel
                    and shamanCheck.optionLabel:GetText()))
        if type(options) == "table" and type(options.Refresh) == "function"
            and type(shamanCheck) == "table" then
            options.Refresh()
            check(shamanCheck:GetChecked() == true,
                "the Shaman Blue control shows the setting in effect (on by default)",
                "checked=" .. tostring(shamanCheck:GetChecked()))
            -- And it FOLLOWS the setting: a control that always reads "on"
            -- would show the player the opposite of what they last chose.
            local panelSettings = REALG.TacoTipExtrasDB
                and REALG.TacoTipExtrasDB.settings or nil
            if type(panelSettings) == "table" then
                panelSettings.shamanBlue = false
                options.Refresh()
                check(shamanCheck:GetChecked() == false,
                    "the Shaman Blue control shows the setting in effect (off when off)",
                    "checked=" .. tostring(shamanCheck:GetChecked()))
                panelSettings.shamanBlue = true
                options.Refresh()
            end
        end
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

local function occupiedSlot(link, itemID, enchant, g1, g2, g3, capacity, g4)
    -- The socket cell's gemIDs must have EXACTLY `capacity` entries:
    -- Scoring.validateSockets rejects any index past capacity as a
    -- contradiction, which is correct (a socket list longer than its own
    -- capacity is incoherent data) and which a sloppy fixture silently
    -- trips. So the list is trimmed to the capacity here, and the fixture
    -- can model a one-socket or a sockless item.
    local socketGemIDs = {}
    local gemList = { g1, g2, g3, g4 }
    for index = 1, capacity do
        socketGemIDs[index] = gemList[index]
    end
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
        sockets = ITEM_STATS and cell({
            capacity = capacity,
            gemIDs = socketGemIDs,
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

-- The policy is now EXPLICIT. Scoring.Evaluate used to take an optional
-- policy and default a nil one to "restricted to level 70" -- which is what
-- hid the bug this harness now pins: no production call site passed a policy,
-- so the level-70 gate applied to every player on every client. A nil policy
-- is now an explicit failure (see the "no policy" block below), so the
-- scoring assertions below state the policy they run under. The revision's
-- level is 70, so the restriction does not suppress anything here and the
-- numbers are the ones the pre-policy code produced.
local result = Scoring.Evaluate(revision, { restrictEnhancementMetricsToLevel70 = true })
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

-- ---------------------------------------------------------------------------
-- The socket capacity: a reconciling item, and a contradicting one
-- ---------------------------------------------------------------------------
--
-- These drive the REAL Scoring.Evaluate, with the socket cell carrying the
-- capacity the documented API (C_Item.GetItemNumSockets) would have
-- returned for that item.
--
-- (a) RECONCILING -- a two-socket item with one gem. The capacity and the
--     item's own gem list agree, so the published Potential GS, Delta and
--     Completion must equal the hand-derived truth:
--       current   = base + 5 per gem in the LINK
--       delta     = (floor(base x 1.05) - base) + 5 per EMPTY socket
--       potential = current + delta
--       completion= 1 filled socket of (1 enchant opportunity + 2 sockets);
--                   the enchant slot is an OPPORTUNITY, not a filled one,
--                   because this item carries no enchant.
--     The base is the delegated TT_GS number, so the truth is derived from
--     the same source the add-on uses -- it is not copied out of the
--     add-on's own output, which would prove nothing.
--
-- (b) CONTRADICTING, in BOTH directions:
--       too small -- a capacity of 1 on an item whose link carries two gems.
--       too large -- a capacity of 4 on an item whose link carries three gem
--                    positions. An item link carries exactly three gem
--                    positions (Scoring's parser reads the enchant field and
--                    then exactly three gem fields), so a capacity above
--                    three cannot be reconciled with the item's gem list.
--     In both cases the socket-based metrics must be UNAVAILABLE and never a
--     number: a capacity that contradicts the item's own gems may not
--     publish one.
--
-- The pins run where the socket path is ENABLED. Where it is not -- the
-- three Classic clients, and the forced `nostats` variant -- the metrics are
-- unavailable by the capability gate, and a contradiction pin there would
-- pass for the wrong reason.
out(("\n-- socket capacity: reconciling and contradicting items --\n"))

if ITEM_STATS then
    local RECONCILING_LINK = makeLink(50020, 0, 41398, 0, 0)
    local TOO_SMALL_LINK = makeLink(50021, 0, 41398, 41398, 0)
    local TOO_LARGE_LINK = makeLink(50022, 0, 41398, 0, 0)
    registerItem({ link = RECONCILING_LINK, quality = 4, level = 200, equipLoc = "INVTYPE_HEAD" })
    registerItem({ link = TOO_SMALL_LINK, quality = 4, level = 200, equipLoc = "INVTYPE_HEAD" })
    registerItem({ link = TOO_LARGE_LINK, quality = 4, level = 200, equipLoc = "INVTYPE_HEAD" })

    local function singleItemRevision(slot)
        local rev = {
            classToken = cell("WARRIOR"),
            level = cell(70),
            socketCapability = cell(true),
            slots = {},
        }
        for _, slotID in ipairs(REQUIRED_SLOTS) do
            rev.slots[slotID] = { state = "confirmed-empty" }
        end
        rev.slots[1] = slot
        return rev
    end

    local SOCKET_POLICY = { restrictEnhancementMetricsToLevel70 = true }

    -- (a) the reconciling item.
    local reconciled = Scoring.Evaluate(
        singleItemRevision(occupiedSlot(RECONCILING_LINK, 50020, 0, 41398, 0, 0, 2)),
        SOCKET_POLICY
    )
    local truthBase = REALG.TT_GS:GetItemScore(RECONCILING_LINK)
    local truthCurrent = truthBase + 1 * GEM_BONUS
    local truthEnchantDelta = math.floor(truthBase * ENCHANT_MULTIPLIER) - truthBase
    local truthEmptySockets = 1
    local truthDelta = truthEnchantDelta + truthEmptySockets * GEM_BONUS
    local truthPotential = truthCurrent + truthDelta

    out(("   reconciling item: base=%d current=%d delta=%d potential=%d\n")
        :format(truthBase, truthCurrent, truthDelta, truthPotential))

    check(reconciled.metrics.potentialGS.status == "complete"
        and reconciled.metrics.potentialGS.value == truthPotential,
        "a reconciling item publishes the hand-derived Potential GS",
        "got " .. tostring(reconciled.metrics.potentialGS.value)
            .. ", expected " .. tostring(truthPotential))
    check(reconciled.metrics.delta.status == "complete"
        and reconciled.metrics.delta.value == truthDelta,
        "a reconciling item publishes the hand-derived Delta",
        "got " .. tostring(reconciled.metrics.delta.value)
            .. ", expected " .. tostring(truthDelta))
    check(reconciled.metrics.completion.status == "complete"
        and reconciled.metrics.completion.value.filled == 1
        and reconciled.metrics.completion.value.opportunities == 3
        and reconciled.metrics.completion.value.displayPercent == 33,
        "a reconciling item publishes the hand-derived Completion",
        "filled=" .. tostring(reconciled.metrics.completion.value
            and reconciled.metrics.completion.value.filled)
            .. " opportunities=" .. tostring(reconciled.metrics.completion.value
                and reconciled.metrics.completion.value.opportunities)
            .. " percent=" .. tostring(reconciled.metrics.completion.value
                and reconciled.metrics.completion.value.displayPercent))
    check(reconciled.items[1].emptyScoreBearingSockets.status == "complete"
        and reconciled.items[1].emptyScoreBearingSockets.value == truthEmptySockets,
        "a reconciling item counts exactly its one empty socket",
        "got " .. tostring(reconciled.items[1].emptyScoreBearingSockets.value))

    -- (b) a capacity that contradicts the item's own gem list, in EITHER
    -- direction. The metrics must be withheld -- never a number.
    local function assertContradiction(label, slot, expectedReason)
        local contradicted = Scoring.Evaluate(singleItemRevision(slot), SOCKET_POLICY)
        local metrics = contradicted.metrics
        check(metrics.potentialGS.status == "contradictory"
            and metrics.potentialGS.value == nil,
            label .. ": Potential GS is withheld, never a number",
            "status=" .. tostring(metrics.potentialGS.status)
                .. " value=" .. tostring(metrics.potentialGS.value)
                .. " reason=" .. tostring(metrics.potentialGS.reason))
        check(metrics.delta.status == "contradictory"
            and metrics.delta.value == nil,
            label .. ": Delta is withheld, never a number",
            "status=" .. tostring(metrics.delta.status)
                .. " value=" .. tostring(metrics.delta.value)
                .. " reason=" .. tostring(metrics.delta.reason))
        check(metrics.completion.status == "contradictory"
            and metrics.completion.value == nil,
            label .. ": Completion is withheld, never a number",
            "status=" .. tostring(metrics.completion.status)
                .. " value=" .. tostring(metrics.completion.value)
                .. " reason=" .. tostring(metrics.completion.reason))
        check(contradicted.items[1].emptyScoreBearingSockets.status == "contradictory"
            and contradicted.items[1].emptyScoreBearingSockets.value == nil,
            label .. ": the empty-socket count is withheld, never a number",
            "status=" .. tostring(contradicted.items[1].emptyScoreBearingSockets.status)
                .. " value=" .. tostring(
                    contradicted.items[1].emptyScoreBearingSockets.value))
        check(tostring(metrics.potentialGS.reason or "") == expectedReason,
            label .. ": the contradiction names itself",
            "reason=" .. tostring(metrics.potentialGS.reason)
                .. ", expected " .. tostring(expectedReason))
    end

    assertContradiction(
        "a capacity too small for the item's gems",
        occupiedSlot(TOO_SMALL_LINK, 50021, 0, 41398, 41398, 0, 1),
        "socket-gem-mismatch-2"
    )
    assertContradiction(
        "a capacity too large for the item's gem list",
        occupiedSlot(TOO_LARGE_LINK, 50022, 0, 41398, 0, 0, 4, 0),
        "socket-capacity-exceeds-gem-list"
    )
else
    out("   (the socket path is gated off on this client, so the socket capacity\n")
    out("    pins do not apply -- run the `ok` variant on a Mainline client)\n")
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
-- Same contract as the base mock: three values on the modern pair, two on
-- the Classic family (Tests/harness/mock_contract.lua). The classID the
-- modern pair publishes is the real Warrior (1) and Mage (8) class ID.
REALG.UnitClass = MOCKC.unitClassMock(function(unit)
    if unit == "target" or unit == "party1" then
        return "Mage", "MAGE"
    end
    return "Warrior", "WARRIOR"
end, function(_, name)
    return name == "Mage" and 8 or 1
end)
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
        classID = 2,
        specID = 0,
        gs = 4800,
        ilvl = 145.2,
        timestamp = testNow - 50,
    }
    local wirePayload = RankSync.SerializeRecord(syncRec)
    check(type(wirePayload) == "string" and wirePayload:sub(1, 4) == "R;2;",
        "RankSync.SerializeRecord generates valid versioned 'R;2;' wire format",
        "wire=" .. tostring(wirePayload))

    local restoredRec = RankSync.DeserializeRecord(wirePayload)
    check(type(restoredRec) == "table"
        and restoredRec.guid == syncRec.guid
        and restoredRec.name == syncRec.name
        and restoredRec.classID == syncRec.classID
        and restoredRec.class == "PALADIN"
        and restoredRec.specID == 0
        and restoredRec.gs == syncRec.gs
        and restoredRec.timestamp == syncRec.timestamp,
        "RankSync.DeserializeRecord reconstructs the record and derives the class token from classID",
        "name=" .. tostring(restoredRec and restoredRec.name)
            .. " class=" .. tostring(restoredRec and restoredRec.class))

    -- A numeric specID round-trips; the class-name and spec-name strings and
    -- the realm/faction ride OFF the wire, so only the id travels.
    local withSpec = {
        guid = "Player-1-007", name = "Jaina", classID = 8, specID = 577,
        gs = 4900, ilvl = 145, timestamp = testNow - 40,
    }
    local specBack = RankSync.DeserializeRecord(RankSync.SerializeRecord(withSpec))
    check(type(specBack) == "table" and specBack.specID == 577,
        "a numeric specID round-trips through the versioned stride",
        "specID=" .. tostring(specBack and specBack.specID))
    check(type(specBack) == "table" and specBack.class == "MAGE",
        "classID 8 derives the MAGE token at ingest",
        "class=" .. tostring(specBack and specBack.class))
    check(type(specBack) == "table" and specBack.faction == nil
        and specBack.realm == nil and specBack.specName == nil,
        "faction, realm and spec-name ride OFF the wire (absent, not empty)",
        "faction=" .. tostring(specBack and specBack.faction))

    -- EMPTY FIELDS. The round-trip above uses a record with every field
    -- filled, which is why it passed for a whole release while the parser was
    -- silently discarding records that had a blank one.
    --
    -- The parser used `gmatch("([^;]+)")`, and `+` requires one or more
    -- characters -- so an empty field was SKIPPED rather than returned. specID
    -- is empty for every unscanned or spec-less player, and a skipped field
    -- shifts every later field and takes the part count under the minimum, so
    -- the WHOLE record was rejected.
    --
    -- Measured before the fix: "R;1;P1;Bob;1;3821;124.5;1759000000;" (empty
    -- spec) returned nil.
    local emptySpec = {
        guid = "Player-2-002", name = "Spec Less",
        classID = 1, gs = 3821, ilvl = 124.5, timestamp = testNow - 60,
    }
    local back = RankSync.DeserializeRecord(RankSync.SerializeRecord(emptySpec))
    check(type(back) == "table",
        "a missing specID does not discard the record",
        "payload=" .. tostring(RankSync.SerializeRecord(emptySpec)))
    check(type(back) == "table" and back.specID == 0,
        "a missing specID round-trips as 0, not as the next field",
        "specID=" .. tostring(back and back.specID))
    check(type(back) == "table" and back.gs == emptySpec.gs
        and back.ilvl == emptySpec.ilvl and back.timestamp == emptySpec.timestamp,
        "a missing specID does not shift every later field",
        type(back) == "table"
            and ("gs=%s ilvl=%s ts=%s"):format(back.gs, back.ilvl, back.timestamp) or "nil")

    -- An unknown classID still ingests: the token degrades to UNKNOWN, the
    -- numbers survive. A stricter parser would drop the player entirely.
    local unknownClass = {
        guid = "Player-3-003", name = "No Class",
        classID = 99, gs = 2900, ilvl = 110, timestamp = testNow - 70,
    }
    local backClass = RankSync.DeserializeRecord(RankSync.SerializeRecord(unknownClass))
    check(type(backClass) == "table" and backClass.class == "UNKNOWN",
        "an unknown classID degrades to UNKNOWN rather than discarding the record",
        type(backClass) == "table" and ("class=%q"):format(backClass.class) or "nil")
    check(type(backClass) == "table" and backClass.gs == 2900,
        "an unknown classID keeps the record's GearScore",
        type(backClass) == "table" and ("gs=%s"):format(backClass.gs) or "nil")

    -- A genuinely malformed payload must still be refused, so the fix did not
    -- turn the parser into one that accepts anything.
    check(RankSync.DeserializeRecord("R;only;three") == nil,
        "a short payload is still refused")
    check(RankSync.DeserializeRecord("X;a;b;c;d;e;f;g;h") == nil,
        "a payload without the R marker is still refused")
    check(RankSync.DeserializeRecord(nil) == nil,
        "a nil payload is refused rather than raising")

    -- Old and unknown strides: refused cleanly, never raised. Short payloads
    -- refuse by length; full-stride payloads carrying a foreign version token
    -- refuse at the gate AND count for /ttgsdebug -- a silent hole would trade
    -- the noisy fallback for an invisible one. The wire is pre-release, so
    -- there are no compat shims: the ten-field pre-Stage-2 stride, the
    -- eleven-field Stage-2 stride, the diet "1" stride and any unknown
    -- version token all refuse.
    --
    -- Group-pin note: the ten-field and unknown-version refusals below pass
    -- on pre-diet code in isolation (both strides refuse a ten-field payload,
    -- and diet code refuses an unknown token exactly like current code).
    -- Diet-specificity of the GROUP rides on the eleven-field refusal, the
    -- diet-"1" refusal (diet code accepts it) and the versionReject count
    -- below (pre-diet code never counts it) -- each of those fails pre-diet.
    local versionBefore = (RankSync.GetDebugState().outcomes or {}).versionReject or 0
    check(RankSync.DeserializeRecord("R;P1;Bob;Horde;1;WARRIOR;;3821;124.5;1759000000") == nil,
        "a ten-field unversioned payload is refused (group pin with the versionReject count below)")
    check(RankSync.DeserializeRecord("R;P1;Bob;Horde;1;WARRIOR;Arms;3821;124.5;1759000000;Stormrage") == nil,
        "an eleven-field unversioned payload is refused by the versioned stride")
    check(RankSync.DeserializeRecord("R;1;P1;Bob;1;3821;124;1759000000;;;;0;0;0") == nil,
        "the diet version token is refused by the R2 stride")
    check(RankSync.DeserializeRecord("R;9;P1;Bob;1;3821;124;1759000000;;;;0;0;0") == nil,
        "an unknown version token is refused, never raised (group pin with the versionReject count below)")
    local versionAfter = (RankSync.GetDebugState().outcomes or {}).versionReject or 0
    check(versionAfter == versionBefore + 2,
        "refused strides are counted for /ttgsdebug (versionReject: diet-\"1\" + unknown; ten/eleven-field refuse by length, uncounted)",
        ("before=%s after=%s"):format(tostring(versionBefore), tostring(versionAfter)))

    local badPayload = "R;invalid;short"
    local corruptRec = RankSync.DeserializeRecord(badPayload)
    check(corruptRec == nil, "RankSync.DeserializeRecord safely rejects corrupt payload", "got " .. tostring(corruptRec))

    -- Inbound records carry no realm: the wire diet dropped it, so a
    -- scan/inspect record files under the LOCAL realm (the receiver's own
    -- table), never anywhere else.
    local syncInspectRec = {
        guid = "Player-1-999",
        name = "Mograine",
        faction = "Alliance",
        class = "PALADIN",
        classID = 2,
        specID = 0,
        gs = 5000,
        timestamp = testNow - 20,
    }
    RankSync.QueueInspectRecord(syncInspectRec)
    local mogRank = RankDB.GetPlayerRank("Player-1-999")
    check(mogRank == 1, "RankSync.QueueInspectRecord files the player in the LOCAL realm",
        "rank=" .. tostring(mogRank))
    local mogRow = RankDB.GetRecord("Player-1-999")
    check(type(mogRow) == "table" and mogRow.class == "PALADIN"
        and mogRow.classID == 2,
        "the locally filed row keeps its class token and classID",
        "class=" .. tostring(mogRow and mogRow.class))
end

do
    out(("\n-- RankSync: query / response protocol --\n"))

    -- The pins below run through a closure. The earlier test blocks leave the
    -- main chunk near the interpreter's 200-live-local limit and every phase
    -- local in this block stays in scope until the block ends, so declaring
    -- them at chunk scope would exceed it; a closure carries its own budget.
    local runQueryProtocol = (function()
    local RankSync = namespace.RankSync
    local RankDB = namespace.RankDB

    -- Capture everything the add-on puts on the wire, make C_Timer.After run
    -- immediately, and pin the uptime clock. The harness's real delays and
    -- clock stubs were a no-op and an absent GetTime: with the clock frozen at
    -- zero the send token bucket never refills, so any test past the third
    -- send was silently starved rather than exercised -- which is exactly why
    -- the pre-Stage-1 flood-control check below passed for the wrong reason
    -- (starvation, not the respond interval). Stage 1 exposes the send result
    -- (SendAddonMessageResult) through this same capture so probe outcomes
    -- can be scripted.
    local sent = {}
    local sendResultValue = 0
    local realAfter = REALG.C_Timer and REALG.C_Timer.After
    local fakeNow = 1000.0
    local savedCChatInfo = REALG.C_ChatInfo
    local savedJoinChannelByName = REALG.JoinChannelByName
    local savedGetChannelName = REALG.GetChannelName
    local savedGetTime = REALG.GetTime
    local savedIsInGroup = REALG.IsInGroup
    local savedIsInGuild = REALG.IsInGuild
    local savedIsInRaid = REALG.IsInRaid
    local savedIsInInstance = REALG.IsInInstance

    REALG.C_ChatInfo = REALG.C_ChatInfo or {}
    REALG.C_ChatInfo.SendAddonMessage = function(prefix, msg, chatType, target)
        sent[#sent + 1] = {
            prefix = prefix, msg = msg, chatType = chatType, target = target,
        }
        return sendResultValue
    end
    REALG.C_ChatInfo.RegisterAddonMessagePrefix = function() return true end
    REALG.JoinChannelByName = function() return 1 end
    REALG.GetChannelName = function() return 7 end
    REALG.GetTime = function() return fakeNow end
    REALG.IsInGroup = function() return true end
    REALG.IsInGuild = function() return true end
    REALG.IsInRaid = function() return false end
    REALG.IsInInstance = function() return false end
    REALG.C_Timer = REALG.C_Timer or {}
    REALG.C_Timer.After = function(_, fn)
        if type(fn) == "function" then fn() end
        return true
    end

    -- Advance uptime and open a fresh respond window: REFRESH respond interval
    -- is 20 seconds, and the token bucket refills on any elapsed interval.
    local function tick()
        fakeNow = fakeNow + 21
    end
    local function setSendResult(value)
        sendResultValue = value
    end

    local function msgsOf(sends)
        local msgs = {}
        for index = 1, #sends do
            msgs[index] = sends[index].msg
        end
        return msgs
    end

    local function drain()
        local msgs = msgsOf(sent)
        sent = {}
        return msgs
    end

    -- Same as drain() but keeps the transport tags, so checks can assert WHERE
    -- an answer travelled and not just WHAT it said.
    local function drainSends()
        local drops = sent
        sent = {}
        return drops
    end

    -- Phase isolation. Each phase opens its own send window and empties the
    -- queue, so a check never passes or fails on scheduling instead of
    -- behaviour: the window may be exhausted from the previous phase, and the
    -- real game drains leftovers through the frame's OnUpdate, which this
    -- harness does not pump. The ";-flush" item is inert (peers ignore any
    -- first character that is not R/Q/S/T); its Enqueue is what pokes
    -- processQueue, the same trigger any piece of real traffic supplies.
    -- Declared after drain() because its body calls it.
    local function isolationSweep()
        tick()
        RankSync.Enqueue(";-flush", "GUILD")
        drain()
        tick()
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

    -- The first-login hole (review §3.6 / audit §3.1): the QueueInspectRecord
    -- broadcast at the end of the previous block ran while the channel could
    -- not carry (no joined id, no proof), which armed the once-per-session
    -- memory; this block stored our own record before the first sync. When
    -- the probe proves the channel carries -- the first "P;" sends -- the
    -- promise must be honoured on that proven channel, exactly once. On the
    -- pre-Stage-1 code there is no arm, no proof, and no R on this drain.
    local selfFlushSeen = 0
    for index = 1, #first do
        if first[index]:find("R;2;" .. HARNESS_PLAYER_GUID, 1, true) == 1 then
            selfFlushSeen = selfFlushSeen + 1
        end
    end
    check(selfFlushSeen == 1,
        "once the channel is proven live, the local record re-broadcasts onto it",
        table.concat(first, " | "))

    -- A query from someone else must produce our own record plus a digest.
    -- Stage 1: the query names a transport and the answer travels the SAME way
    -- -- the pre-Stage-1 code answered every Q on CHANNEL, which guild- and
    -- party-askers could not consult.
    isolationSweep()
    RankSync.HandlePayload("Q;abc123", "GUILD")
    local answerSends = drainSends()
    local answer = msgsOf(answerSends)
    check(countPrefix(answer, "S;") >= 1,
        "an inbound Q produces an S carrying our own record",
        table.concat(answer, " | "))
    local answerTransport, transportDetail = "GUILD", ""
    for index = 1, #answerSends do
        local tag = answerSends[index].msg:sub(1, 2)
        if tag == "S;" or tag == "T;" then
            if answerSends[index].chatType ~= "GUILD" then
                answerTransport = nil
                transportDetail = "tag=" .. tostring(answerSends[index].chatType)
                    .. " msg=" .. answerSends[index].msg:sub(1, 24)
                break
            end
        end
    end
    check(answerTransport ~= nil,
        "an inbound Q is answered on the query's own transport (GUILD)",
        transportDetail)

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
    RankSync.HandlePayload("Q;second", "GUILD")
    local second = drain()
    check(countPrefix(second, "S;") == 0,
        "a second query inside the respond interval is not answered",
        table.concat(second, " | "))

    -- A response carrying one record must be ingested. This is the assertion
    -- that pins the 9-field versioned stride: reading element 3 of a flat
    -- split yields the bare letter "R" and stores nothing, silently.
    local peerRecord = {
        guid = "Player-9-777", name = "Peer",
        classID = 1,   -- no specID key at all: missing on purpose
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
    check(type(stored) == "table" and stored.class == "WARRIOR",
        "an S response derives the class token from classID",
        "class=" .. tostring(stored and stored.class))
    check(type(stored) == "table" and stored.specID == 0,
        "an S response with no specID still ingests (spec 0, numbers intact)",
        "specID=" .. tostring(stored and stored.specID))

    -- Two records in one T message: the stride has to advance by exactly nine
    -- fields per record or the second one lands on garbage.
    local recA = {
        guid = "Player-9-778", name = "Alpha",
        classID = 1, specID = 71,
        gs = 5100, ilvl = 140, timestamp = (REALG.time and REALG.time() or 1000000) + 1,
    }
    local recB = {
        guid = "Player-9-779", name = "Beta",
        classID = 3,
        gs = 4900, ilvl = 138, timestamp = (REALG.time and REALG.time() or 1000000) + 2,
    }
    RankSync.HandlePayload("T;reqid;"
        .. RankSync.SerializeRecord(recA) .. ";"
        .. RankSync.SerializeRecord(recB))
    local storedA = RankDB.GetRecord("Player-9-778")
    local storedB = RankDB.GetRecord("Player-9-779")
    check(type(storedA) == "table" and storedA.name == "Alpha"
        and storedA.gs == 5100 and storedA.specID == 71,
        "the FIRST record of a T message is ingested with its specID",
        "A=" .. tostring(storedA and storedA.name) .. "/" .. tostring(storedA and storedA.gs)
            .. "/" .. tostring(storedA and storedA.specID))
    check(type(storedB) == "table" and storedB.name == "Beta"
        and storedB.gs == 4900 and storedB.specID == 0,
        "the SECOND record of a T message is ingested",
        "B=" .. tostring(storedB and storedB.name) .. "/" .. tostring(storedB and storedB.gs))

    -- A T containing one record only: the loop must not read past the end.
    RankSync.HandlePayload("T;reqid;" .. RankSync.SerializeRecord({
        guid = "Player-9-780", name = "Solo",
        classID = 1, specID = 71,
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

    -- ------------------------------------------------------------------
    -- Stage 1 additions (expansion audit §6.2 Stage 1). Each check below
    -- fails on the pre-Stage-1 code, which sent CHANNEL-first, ignored the
    -- send result, let throttled sends vanish from the queue, echoed the
    -- whole inbound request id, and had no channel proof at all.
    -- ------------------------------------------------------------------

    -- Items 1 + 4 (part): a digest of two records that no longer fits the
    -- 240-byte door is split into two single-record messages instead of
    -- being enqueued oversize. The fat records below measure ~150 bytes each
    -- (long-but-legal names and guids -- specName no longer rides the wire,
    -- so bulk comes from identity fields), so a pair lands near 320 bytes:
    -- sendable against the engine's 255 only after the split, and refused by
    -- our 240 door as a pair.
    isolationSweep()
    RankDB.StoreRecord({
        guid = "Player-9-781-" .. string.rep("G", 60), name = "FatOne" .. string.rep("N", 58),
        classID = 1, specID = 71,
        gs = 9999, ilvl = 200, timestamp = REALG.time and REALG.time() or 1000000,
    })
    RankDB.StoreRecord({
        guid = "Player-9-782-" .. string.rep("G", 60), name = "FatTwo" .. string.rep("N", 58),
        classID = 1, specID = 72,
        gs = 9998, ilvl = 200, timestamp = REALG.time and REALG.time() or 1000000,
    })
    tick()
    RankSync.HandlePayload("Q;fatdigest", "PARTY")
    local fatSends = drainSends()
    local fatMsg = msgsOf(fatSends)
    local fatLongest = 0
    for index = 1, #fatMsg do
        if #fatMsg[index] > fatLongest then fatLongest = #fatMsg[index] end
    end
    check(fatLongest > 0 and fatLongest <= 240,
        "no response exceeds the 240-byte enqueue door",
        "longest=" .. fatLongest)
    local fatOneHome, fatTwoHome, fatBothInOne = nil, nil, nil
    for index = 1, #fatMsg do
        local hasOne = fatMsg[index]:find("FatOne", 1, true) ~= nil
        local hasTwo = fatMsg[index]:find("FatTwo", 1, true) ~= nil
        if hasOne and hasTwo then
            fatBothInOne = fatMsg[index]:sub(1, 24)
        elseif hasOne then
            fatOneHome = index
        elseif hasTwo then
            fatTwoHome = index
        end
    end
    check(fatOneHome ~= nil and fatTwoHome ~= nil and fatBothInOne == nil,
        "an over-long two-record digest travels as two single-record T messages",
        "one=" .. tostring(fatOneHome and true) .. " two=" .. tostring(fatTwoHome and true)
            .. " both=" .. tostring(fatBothInOne) .. " longest=" .. fatLongest)
    local fatPartyEcho, fatEchoDetail = "PARTY", ""
    for index = 1, #fatSends do
        local tag = fatSends[index].msg:sub(1, 2)
        if tag == "S;" or tag == "T;" then
            if fatSends[index].chatType ~= "PARTY" then
                fatPartyEcho = nil
                fatEchoDetail = "tag=" .. tostring(fatSends[index].chatType)
                    .. " msg=" .. fatSends[index].msg:sub(1, 24)
                break
            end
        end
    end
    check(fatPartyEcho ~= nil,
        "an inbound Q is answered on the query's own transport (PARTY)",
        fatEchoDetail)

    -- Item 4: the request id is capped. An inbound id of 240 characters no
    -- longer rides the response whole: it is echoed at eight characters,
    -- so the S stays under the door ("S;" + 8 + ";" = 11 bytes of framing).
    isolationSweep()
    RankSync.HandlePayload("Q;" .. string.rep("b", 240), "GUILD")
    local longMsg = drain()
    local longIdHard
    for index = 1, #longMsg do
        if longMsg[index]:sub(1, 2) == "S;" then
            longIdHard = longMsg[index]
        end
    end
    local longIdLongest = 0
    for index = 1, #longMsg do
        if #longMsg[index] > longIdLongest then longIdLongest = #longMsg[index] end
    end
    check(longIdLongest > 0 and longIdLongest <= 240,
        "a 240-char request id produces no message longer than 240 bytes",
        "longest=" .. longIdLongest)
    check(longIdHard ~= nil and longIdHard:sub(11, 11) == ";",
        "a long inbound request id is echoed at eight characters",
        "s=" .. tostring(longIdHard and longIdHard:sub(1, 24)))

    -- Item 3 + verification: a client-refused send is COUNTED in the outcome
    -- buckets and stays queued -- pre-Stage-1 code popped the item, so the
    -- message was lost forever while looking identical to a delivered one.
    isolationSweep()
    setSendResult(3)
    RankSync.Enqueue("Q;throttle1", "GUILD")
    drainSends()  -- capture the refused attempt, the item itself stays queued
    local syncInfo = RankSync.GetDebugState()
    check(type(syncInfo) == "table"
            and (syncInfo.outcomes.sendThrottle or 0) >= 1
            and (syncInfo.outcomes.requeued or 0) >= 1,
        "a throttled send is counted (addon-throttle + requeued buckets)",
        "throttle=" .. tostring(syncInfo and syncInfo.outcomes
            and syncInfo.outcomes.sendThrottle))
    setSendResult(0)
    tick()
    RankSync.Enqueue("Q;normal1", "GUILD")
    local throttleRetry = drain()
    local throttleRequeued, throttleNewest = nil, nil
    for index = 1, #throttleRetry do
        if throttleRetry[index] == "Q;throttle1" then
            throttleRequeued = index
        elseif throttleRetry[index] == "Q;normal1" then
            throttleNewest = index
        end
    end
    check(throttleRequeued ~= nil and throttleNewest ~= nil,
        "a throttled send is re-queued and delivered on the next tick",
        table.concat(throttleRetry, " | "))

    -- Item 2: the channel state machine. A channel-flagged send answered by
    -- the client with InvalidChannel=7 proves the channel does not carry
    -- addon traffic here, and every send site must stop aiming at it.
    tick()
    setSendResult(7)
    RankSync.BroadcastRecord({
        guid = HARNESS_PLAYER_GUID, name = "Tester", faction = "Alliance",
        classID = 1, class = "WARRIOR", specName = "Arms", gs = 6000,
        ilvl = 150, timestamp = REALG.time and REALG.time() or 1000000,
    })
    drain()
    local syncDead = RankSync.GetDebugState()
    check(type(syncDead) == "table" and syncDead.channelState == "dead",
        "an InvalidChannel result marks the custom channel dead",
        "state=" .. tostring(syncDead and syncDead.channelState))

    -- Dead-transport queries are a counted silent skip, pin (i): the query's
    -- own transport cannot carry (the channel is dead), so NOTHING is sent on
    -- any transport -- and the skip is counted so the quiet path stays
    -- observable. There is no whisper path anywhere: pre-diet code answered
    -- into the dead channel, and the interim code whispered once. Plain
    -- tick() here, not the isolation sweep: the sweep's double tick would
    -- advance the fake clock past the 120-second re-probe window the coda
    -- below measures from.
    tick()
    setSendResult(0)
    local skipBefore = (RankSync.GetDebugState().outcomes or {}).answerNoTransport or 0
    RankSync.HandlePayload("Q;skip1", "CHANNEL", "Sender-Stormrage")
    local skipSends = drainSends()
    local skipTotal, skipWhisper = 0, 0
    local shapes = ""
    for index = 1, #skipSends do
        skipTotal = skipTotal + 1
        if skipSends[index].chatType == "WHISPER" then
            skipWhisper = skipWhisper + 1
        end
        shapes = shapes .. skipSends[index].chatType .. ","
    end
    local skipAfter = (RankSync.GetDebugState().outcomes or {}).answerNoTransport or 0
    check(skipTotal == 0 and skipWhisper == 0 and skipAfter == skipBefore + 1,
        "a query on a dead channel sends nothing on any transport and counts the skip",
        "sends=" .. skipTotal .. " whispers=" .. skipWhisper
            .. " shapes=" .. shapes
            .. " skip=" .. skipBefore .. "->" .. skipAfter)

    -- Pin (ii): the sender is irrelevant to the skip -- an unresolvable name
    -- on a dead channel is the same counted silence, with no lookup at all.
    tick()
    local skipBefore2 = (RankSync.GetDebugState().outcomes or {}).answerNoTransport or 0
    RankSync.HandlePayload("Q;skip2", "CHANNEL", "Nobody-Somewhere")
    local unresolvedSends = drainSends()
    local unresolvedTotal, unresolvedWhispers = 0, 0
    for index = 1, #unresolvedSends do
        unresolvedTotal = unresolvedTotal + 1
        if unresolvedSends[index].chatType == "WHISPER" then
            unresolvedWhispers = unresolvedWhispers + 1
        end
    end
    local skipAfter2 = (RankSync.GetDebugState().outcomes or {}).answerNoTransport or 0
    check(unresolvedTotal == 0 and unresolvedWhispers == 0
        and skipAfter2 == skipBefore2 + 1,
        "an unresolvable sender on a dead channel sends nothing and counts the skip",
        "sends=" .. tostring(unresolvedTotal) .. " whispers=" .. tostring(unresolvedWhispers))

    -- Pin (iii): a WHISPER query is answered the same way -- with silence.
    -- Same-transport would mean a user-visible whisper event, so even a
    -- whisper that arrives is never answered on WHISPER.
    tick()
    local skipBefore3 = (RankSync.GetDebugState().outcomes or {}).answerNoTransport or 0
    RankSync.HandlePayload("Q;skip3", "WHISPER", "Someone-Somewhere")
    local whisperQuerySends = drainSends()
    local whisperQueryTotal, whisperQueryWhispers = 0, 0
    for index = 1, #whisperQuerySends do
        whisperQueryTotal = whisperQueryTotal + 1
        if whisperQuerySends[index].chatType == "WHISPER" then
            whisperQueryWhispers = whisperQueryWhispers + 1
        end
    end
    local skipAfter3 = (RankSync.GetDebugState().outcomes or {}).answerNoTransport or 0
    check(whisperQueryTotal == 0 and whisperQueryWhispers == 0
        and skipAfter3 == skipBefore3 + 1,
        "a WHISPER query is never answered on WHISPER and counts the skip",
        "sends=" .. tostring(whisperQueryTotal) .. " whispers=" .. tostring(whisperQueryWhispers))

    -- Item 2 coda: a dead channel withholds re-probes until its recheck
    -- window elapses (PROBE_RECHECK_SECONDS), then re-probes on its own.
    local deadKnownAt = fakeNow
    fakeNow = deadKnownAt + 10
    RankSync.SyncNow(true)
    local withheldMsg = drain()
    local withheldProbes = 0
    for index = 1, #withheldMsg do
        if withheldMsg[index]:sub(1, 2) == "P;" then
            withheldProbes = withheldProbes + 1
        end
    end
    local syncWithheld = RankSync.GetDebugState()
    check(withheldProbes == 0 and type(syncWithheld) == "table"
            and syncWithheld.channelState == "dead",
        "a dead channel withholds its re-probe until the recheck window passes",
        "probes=" .. tostring(withheldProbes) .. " state="
            .. tostring(syncWithheld and syncWithheld.channelState))

    fakeNow = deadKnownAt + 121
    setSendResult(0)
    RankSync.SyncNow(true)
    local reprobeSends = drainSends()
    local reprobeMsg = msgsOf(reprobeSends)
    local reprobeSeen, reprobeReruns = 0, 0
    for index = 1, #reprobeMsg do
        if reprobeMsg[index]:sub(1, 2) == "P;" then
            reprobeSeen = reprobeSeen + 1
        end
        if reprobeMsg[index]:find("R;2;" .. HARNESS_PLAYER_GUID, 1, true) == 1 then
            reprobeReruns = reprobeReruns + 1
        end
    end
    local syncReprobe = RankSync.GetDebugState()
    check(reprobeSeen >= 1 and type(syncReprobe) == "table"
            and syncReprobe.channelState == "active"
            and (syncReprobe.outcomes.probes or 0) >= 2,
        "a dead channel re-probes after the recheck window and goes active",
        "seen=" .. tostring(reprobeSeen) .. " state="
            .. tostring(syncReprobe and syncReprobe.channelState))
    check(reprobeReruns == 0 and type(syncReprobe) == "table"
            and (syncReprobe.outcomes.selfRebroadcast or 0) == 1,
        "the self re-broadcast is made at most once per session",
        "reruns=" .. tostring(reprobeReruns) .. " self="
            .. tostring(syncReprobe and syncReprobe.outcomes
                and syncReprobe.outcomes.selfRebroadcast))

    -- Stage 3: the 240-byte door still holds with the fatter stride.
    --
    -- Two fully-expanded TYPICAL records ride one T inside the door; the
    -- "fully-expanded" half is what fails pre-Stage-3 (the guild never
    -- travels), while the size half holds on both sides. The pair is seeded
    -- above every earlier row on purpose: the answer burst is 3 sends (S +
    -- two digest members), so the pair under test must lead the digest or a
    -- leftover fat single from an earlier door test eats the window.
    isolationSweep()
    RankDB.StoreRecord({
        guid = "Player-72-A", name = "TypA",
        class = "WARRIOR", classID = 1, specID = 71,
        gs = 14000, ilvl = 200, timestamp = (REALG.time and REALG.time() or 1000000) - 5,
        guild = "GuildAlpha", level = 80, pvpRank = 5, arena = 1500,
    })
    RankDB.StoreRecord({
        guid = "Player-72-B", name = "TypB",
        class = "MAGE", classID = 8, specID = 62,
        gs = 13999, ilvl = 199, timestamp = (REALG.time and REALG.time() or 1000000) - 6,
        guild = "GuildBeta", level = 80, pvpRank = 0, arena = 0,
    })
    isolationSweep()
    RankSync.HandlePayload("Q;stage3a", "GUILD")
    local typicalSends = drainSends()
    local typicalMsgs = msgsOf(typicalSends)
    local typicalWorst, typicalGuildSeen = 0, false
    for index = 1, #typicalMsgs do
        if #typicalMsgs[index] > typicalWorst then typicalWorst = #typicalMsgs[index] end
        if typicalMsgs[index]:find("GuildAlpha", 1, true) then typicalGuildSeen = true end
    end
    check(typicalWorst <= 240 and typicalGuildSeen,
        "T with two fully-expanded typical records stays \226\137\164240",
        "worst=" .. tostring(typicalWorst) .. " guildSeen=" .. tostring(typicalGuildSeen))

    -- Two VALIDATOR-MAX rows (64-char name, 24-char guild, 128-char guid)
    -- cannot travel even singly: the digest split fires, each single still
    -- trips the 240-byte door, and the door refuses + counts instead of
    -- queueing the unsendable. Pre-Stage-3 the same rows fit (the guild never
    -- travels), so nothing is refused.
    isolationSweep()
    local maxGuild = string.rep("G", 24)
    local maxNameA, maxNameB = string.rep("N", 64), string.rep("M", 64)
    local maxGuidA = "Player-" .. string.rep("A", 121)
    local maxGuidB = "Player-" .. string.rep("B", 121)
    RankDB.StoreRecord({
        guid = maxGuidA, name = maxNameA,
        class = "WARRIOR", classID = 1, specID = 71,
        gs = 14900, ilvl = 200, timestamp = (REALG.time and REALG.time() or 1000000) - 7,
        guild = maxGuild, level = 80, pvpRank = 14, arena = 2400,
    })
    RankDB.StoreRecord({
        guid = maxGuidB, name = maxNameB,
        class = "MAGE", classID = 8, specID = 62,
        gs = 14899, ilvl = 199, timestamp = (REALG.time and REALG.time() or 1000000) - 8,
        guild = maxGuild, level = 80, pvpRank = 0, arena = 0,
    })
    local overBefore = (RankSync.GetDebugState().outcomes or {}).enqueueOversize or 0
    isolationSweep()
    RankSync.HandlePayload("Q;stage3b", "GUILD")
    local maxSends = drainSends()
    local maxMsgs = msgsOf(maxSends)
    local maxWorst = 0
    for index = 1, #maxMsgs do
        if #maxMsgs[index] > maxWorst then maxWorst = #maxMsgs[index] end
    end
    local overAfter = (RankSync.GetDebugState().outcomes or {}).enqueueOversize or 0
    check(maxWorst <= 240 and overAfter > overBefore,
        "validator-max pair still splits-or-refuses",
        "worst=" .. tostring(maxWorst)
            .. " oversize=" .. tostring(overBefore) .. "->" .. tostring(overAfter))

    -- ------------------------------------------------------------------
    -- Stage 4: gear on demand (G/D request/response, sparse slot=itemID
    -- encoding, chunked sequencing, two-tier cache, throttle interplay).
    -- Each check below fails on pre-Stage-4 code: no G/D handling means
    -- zero D sends, zero gear buckets, and no gear table.
    -- ------------------------------------------------------------------

    -- The responder reads session truth through the Scanner: the owner from
    -- the live revision, a peer only from a fresh remote entry. Stub both
    -- (GetCurrent-shaped for the owner, GetFreshRemote-shaped for peers);
    -- the stubs are restored before the Restore epilogue below.
    local gearScanner = namespace.Scanner
    local gearCurrentStub, gearRemoteStub = nil, {}
    local savedGetCurrent = gearScanner.GetCurrent
    local savedGetFreshRemote = gearScanner.GetFreshRemote
    gearScanner.GetCurrent = function() return gearCurrentStub end
    gearScanner.GetFreshRemote = function(guid) return gearRemoteStub[guid] end

    local function gearOutcomes()
        return (RankSync.GetDebugState().outcomes or {})
    end

    local function dTagged(sends)
        local found = {}
        for index = 1, #sends do
            if sends[index].msg:sub(1, 2) == "D;" then
                found[#found + 1] = sends[index]
            end
        end
        return found
    end

    -- 1. A G for the owned guid yields one D on the same transport.
    isolationSweep()
    gearCurrentStub = { status = "complete", revision = { slots = {
        [1] = { itemID = { value = 50003 } },
        [5] = { itemID = { value = 60001 } },
    } } }
    local gearStoredBefore = gearOutcomes().gearStored or 0
    RankSync.HandlePayload("G;2;abc123;" .. HARNESS_PLAYER_GUID, "GUILD", "Peer-One")
    local gearSends = drainSends()
    local oneD = dTagged(gearSends)
    check(#oneD == 1,
        "G for owned guid yields one D on same transport",
        "d=" .. #oneD .. " sends=" .. #gearSends)
    check(oneD[1] ~= nil and oneD[1].chatType == "GUILD",
        "the owned-guid D answers on GUILD (same transport)",
        "chat=" .. tostring(oneD[1] and oneD[1].chatType))
    check(oneD[1] ~= nil and #oneD[1].msg <= 240,
        "the owned-guid D fits under the 240-byte door",
        "len=" .. tostring(oneD[1] and #oneD[1].msg))
    check(oneD[1] ~= nil
        and oneD[1].msg:find("1=50003", 1, true) ~= nil
        and oneD[1].msg:find("5=60001", 1, true) ~= nil
        and oneD[1].msg:find("1/1;", 1, true) ~= nil,
        "the owned-guid D carries the sparse slot=itemID run in one chunk",
        "msg=" .. tostring(oneD[1] and oneD[1].msg))
    do
        local sIndex, dIndex
        for index = 1, #gearSends do
            local tag = gearSends[index].msg:sub(1, 2)
            if tag == "S;" and not sIndex then sIndex = index end
            if tag == "D;" and not dIndex then dIndex = index end
        end
        check(sIndex ~= nil and dIndex ~= nil and sIndex < dIndex,
            "a G-triggered S is enqueued before its D (standings seed first)",
            "s=" .. tostring(sIndex) .. " d=" .. tostring(dIndex))
    end
    -- Loopback: the D just sent stores on ingest, proving the store path.
    RankSync.HandlePayload(oneD[1].msg, "GUILD", "Peer-One")
    check((gearOutcomes().gearStored or 0) == gearStoredBefore + 1,
        "the answered D stores on ingest (gearStored)",
        "stored=" .. tostring(gearOutcomes().gearStored))

    -- 2. Same on PARTY: answers PARTY, never CHANNEL.
    isolationSweep()
    RankSync.HandlePayload("G;2;party1;" .. HARNESS_PLAYER_GUID, "PARTY", "Peer-Two")
    local partySends = drainSends()
    local partyD = dTagged(partySends)
    local partyLeak = nil
    for index = 1, #partySends do
        local tag = partySends[index].msg:sub(1, 2)
        if (tag == "D;" or tag == "S;") and partySends[index].chatType ~= "PARTY" then
            partyLeak = partySends[index].chatType
        end
    end
    check(#partyD == 1 and partyLeak == nil,
        "G on PARTY answers PARTY, never CHANNEL",
        "d=" .. #partyD .. " leak=" .. tostring(partyLeak))

    -- 3. A dead-channel G is a counted skip, never a whisper.
    tick()
    setSendResult(7)
    RankSync.SyncNow(true)
    drain()
    setSendResult(0)
    local deadSkipBefore = gearOutcomes().answerNoTransport or 0
    RankSync.HandlePayload("G;2;deadch;" .. HARNESS_PLAYER_GUID, "CHANNEL", "Peer-Dead")
    local deadSends = drainSends()
    local deadTotal, deadWhisper = 0, 0
    for index = 1, #deadSends do
        deadTotal = deadTotal + 1
        if deadSends[index].chatType == "WHISPER" then
            deadWhisper = deadWhisper + 1
        end
    end
    check(deadTotal == 0 and deadWhisper == 0
        and (gearOutcomes().answerNoTransport or 0) == deadSkipBefore + 1,
        "dead-channel G is a counted skip, no whisper",
        "sends=" .. deadTotal .. " whispers=" .. deadWhisper)
    -- Recover the channel for the checks below (the door tests answer GUILD,
    -- but nothing after this point should inherit a dead channel).
    fakeNow = fakeNow + 121
    RankSync.SyncNow(true)
    drain()

    -- 4. Unknown versions are refused and counted on both types.
    isolationSweep()
    local verBefore = gearOutcomes().versionReject or 0
    RankSync.HandlePayload("G;9;badver;" .. HARNESS_PLAYER_GUID, "GUILD", "Peer-Ver")
    local verSends = drainSends()
    check(#verSends == 0 and (gearOutcomes().versionReject or 0) == verBefore + 1,
        "unknown version G refused and counted",
        "sends=" .. #verSends)
    local storedBefore4 = gearOutcomes().gearStored or 0
    RankSync.HandlePayload("D;9;badver;Player-9-600;100;1/1;1=111", "GUILD", "Peer-Ver")
    check((gearOutcomes().gearStored or 0) == storedBefore4
        and (gearOutcomes().versionReject or 0) == verBefore + 2,
        "unknown version D refused and counted",
        "stored=" .. tostring(gearOutcomes().gearStored))

    -- 5. Unknown and empty guids send nothing; each names its bucket.
    isolationSweep()
    gearRemoteStub = {}
    local noDataBefore = gearOutcomes().gearNoData or 0
    RankSync.HandlePayload("G;2;nodata;Player-9-600", "GUILD", "Peer-NoData")
    local noDataSends = drainSends()
    check(#noDataSends == 0 and (gearOutcomes().gearNoData or 0) == noDataBefore + 1,
        "G for unknown guid sends nothing, counts gearNoData",
        "sends=" .. #noDataSends)
    local badGuidBefore = gearOutcomes().gearBadGuid or 0
    RankSync.HandlePayload("G;2;badguid;", "GUILD", "Peer-NoData")
    local badGuidSends = drainSends()
    check(#badGuidSends == 0 and (gearOutcomes().gearBadGuid or 0) == badGuidBefore + 1,
        "G with empty guid sends nothing, counts gearBadGuid",
        "sends=" .. #badGuidSends)

    -- 6. A validator-long single-D that breaches the door sequences into
    -- 1/2 + 2/2, every chunk under the door.
    isolationSweep()
    local longGuid = "Player-" .. string.rep("L", 57)
    local chunkIDs = { [1] = 111111, [2] = 222222, [3] = 333333,
        [5] = 555555, [6] = 666666, [7] = 777777, [8] = 888888,
        [9] = 999999, [10] = 101010, [11] = 111011, [12] = 121212,
        [13] = 131313, [14] = 141414, [15] = 151515, [16] = 161616,
        [17] = 171717, [18] = 181818 }
    local remoteSlots = {}
    for slot, id in pairs(chunkIDs) do
        remoteSlots[slot] = { itemID = { value = id } }
    end
    gearRemoteStub[longGuid] = { state = "complete", revision = { slots = remoteSlots } }
    RankSync.HandlePayload("G;2;chunk1;" .. longGuid, "GUILD", "Peer-Chunk")
    local chunkSends = dTagged(drainSends())
    check(#chunkSends == 2,
        "oversize single-D sequences into 1/2 + 2/2, both under the door",
        "d=" .. #chunkSends)
    do
        local guids, seqs, ofs, blobs, stamps, worst = {}, {}, {}, {}, {}, 0
        for _, send in ipairs(chunkSends) do
            if #send.msg > worst then worst = #send.msg end
            local guid, stampText, seq, of, blob = send.msg:match("^D;2;chunk1;([^;]+);(%d+);(%d+)/(%d+);(.*)$")
            guids[#guids + 1] = guid
            seqs[#seqs + 1], ofs[#ofs + 1], blobs[#blobs + 1] = seq, of, blob
            stamps[#stamps + 1] = tonumber(stampText)
        end
        local seenSlots, ordered, disjoint = {}, true, true
        for _, blob in ipairs(blobs) do
            local prev = 0
            for pair in (blob or ""):gmatch("[^,]+") do
                local slot = tonumber(pair:match("^(%d+)="))
                if not slot then
                    ordered = false
                elseif slot <= prev then
                    ordered = false
                elseif seenSlots[slot] then
                    disjoint = false
                else
                    seenSlots[slot] = true
                end
                prev = slot or prev
            end
        end
        local full = true
        for _, slot in ipairs({ 1, 2, 3, 5, 6, 7, 8, 9, 10,
            11, 12, 13, 14, 15, 16, 17, 18 }) do
            if not seenSlots[slot] then full = false end
        end
        check(seqs[1] == "1" and seqs[2] == "2" and ofs[1] == "2" and ofs[2] == "2"
            and guids[1] == longGuid and guids[2] == longGuid
            and (stamps[1] or 0) > 0 and stamps[1] == stamps[2]
            and worst > 0 and worst <= 240 and ordered and disjoint and full,
            "both chunks carry disjoint ordered halves of the full set",
            "worst=" .. worst .. " seq=" .. tostring(seqs[1]) .. ","
                .. tostring(seqs[2]) .. " ordered=" .. tostring(ordered)
                .. " disjoint=" .. tostring(disjoint) .. " full=" .. tostring(full))
    end

    -- 7. Past the chunk cap: refused and counted, nothing stored or sent.
    local refusedBefore = gearOutcomes().gearRefused or 0
    local storedBefore7 = gearOutcomes().gearStored or 0
    RankSync.HandlePayload("D;2;capid;Player-9-700;100;5/9;1=111", "GUILD", "Peer-Cap")
    local capSends = drainSends()
    check(#capSends == 0
        and (gearOutcomes().gearStored or 0) == storedBefore7
        and (gearOutcomes().gearRefused or 0) == refusedBefore + 1,
        "four-chunk cap refuses the fifth",
        "sends=" .. #capSends)

    -- 8. Stale D never overwrites newer gear; newer D merges over it.
    RankDB.StoreGear("Player-9-800", 200, "1=111,5=555")
    local staleBefore = gearOutcomes().gearStale or 0
    local storedBefore8 = gearOutcomes().gearStored or 0
    RankSync.HandlePayload("D;2;stale1;Player-9-800;100;1/1;1=999", "GUILD", "Peer-Stale")
    local staleRow = RankDB.GetGear("Player-9-800")
    check(staleRow ~= nil and staleRow.ids == "1=111,5=555"
        and (gearOutcomes().gearStale or 0) == staleBefore + 1,
        "stale D never overwrites newer gear",
        "ids=" .. tostring(staleRow and staleRow.ids))
    RankSync.HandlePayload("D;2;stale2;Player-9-800;300;1/1;1=999", "GUILD", "Peer-Stale")
    local mergedRow = RankDB.GetGear("Player-9-800")
    check(mergedRow ~= nil and mergedRow.ids == "1=999,5=555"
        and (gearOutcomes().gearStored or 0) == storedBefore8 + 1,
        "newer D merges over older gear",
        "ids=" .. tostring(mergedRow and mergedRow.ids))

    -- 9. Starvation-freedom: a G storm neither suppresses S/T nor evicts
    -- rank traffic, and per-sender repeats coalesce.
    isolationSweep()
    for index = 1, 4 do
        local guid = "Player-9-90" .. index
        gearRemoteStub[guid] = { state = "complete", revision = { slots = {
            [1] = { itemID = { value = 400000 + index } },
            [5] = { itemID = { value = 500000 + index } },
        } } }
    end
    local overBefore9, coalBefore9
    RankSync.HandlePayload("Q;starve9", "GUILD")
    local stormSends = drainSends()
    for _ = 1, 10 do
        if (RankSync.GetDebugState().queueDepth or 0) == 0 then break end
        tick()
        RankSync.Enqueue(";-flush", "GUILD")
        local more = drainSends()
        for _, send in ipairs(more) do stormSends[#stormSends + 1] = send end
    end
    -- The G phase starts from a quiet queue: any refusal or coalescing from
    -- here on is gear's own doing, not the digest's (the top-4 digest above
    -- still trips the door on the validator-max singles, as Stage-3 pins).
    overBefore9 = gearOutcomes().enqueueOversize or 0
    coalBefore9 = gearOutcomes().gearCoalesced or 0
    for index = 1, 4 do
        RankSync.HandlePayload("G;2;st" .. index .. ";Player-9-90" .. index,
            "GUILD", "Sender-" .. index)
    end
    for _ = 1, 10 do
        if (RankSync.GetDebugState().queueDepth or 0) == 0 then break end
        tick()
        RankSync.Enqueue(";-flush", "GUILD")
        local more = drainSends()
        for _, send in ipairs(more) do stormSends[#stormSends + 1] = send end
    end
    do
        local firstS, dCount, tCount = nil, 0, 0
        for _, send in ipairs(stormSends) do
            local tag = send.msg:sub(1, 2)
            if tag == "S;" and not firstS then firstS = send.msg end
            if tag == "D;" then dCount = dCount + 1 end
            if tag == "T;" then tCount = tCount + 1 end
        end
        check(firstS ~= nil and firstS:find("starve9", 1, true) ~= nil,
            "starvation-freedom: the Q's S still emits first through a G storm",
            "firstS=" .. tostring(firstS and firstS:sub(1, 32)))
        check(dCount == 4 and tCount >= 1,
            "starvation-freedom: every G's D emits and the digest survives",
            "d=" .. dCount .. " t=" .. tCount)
        check((gearOutcomes().enqueueOversize or 0) == overBefore9
            and (gearOutcomes().gearCoalesced or 0) == coalBefore9,
            "starvation-freedom: distinct senders are never coalesced and gear evicts nothing",
            "oversize=" .. tostring(gearOutcomes().enqueueOversize)
                .. " coalesced=" .. tostring(gearOutcomes().gearCoalesced))
    end
    -- Same sender three times in a row: exactly one D, two coalesced.
    tick()
    gearRemoteStub["Player-9-951"] = { state = "complete", revision = { slots = {
        [1] = { itemID = { value = 951001 } },
    } } }
    local coalBeforeZ = gearOutcomes().gearCoalesced or 0
    RankSync.HandlePayload("G;2;zz1;Player-9-951", "GUILD", "Sender-Z")
    RankSync.HandlePayload("G;2;zz2;Player-9-951", "GUILD", "Sender-Z")
    RankSync.HandlePayload("G;2;zz3;Player-9-951", "GUILD", "Sender-Z")
    local zSends = dTagged(drainSends())
    check(#zSends == 1 and (gearOutcomes().gearCoalesced or 0) == coalBeforeZ + 2,
        "per-sender coalescing: three rapid Gs from one sender yield one D",
        "d=" .. #zSends)

    -- 10. A 240-char G id echoes at eight characters, door intact.
    isolationSweep()
    gearRemoteStub["Player-9-610"] = { state = "complete", revision = { slots = {
        [1] = { itemID = { value = 61001 } },
    } } }
    RankSync.HandlePayload("G;2;" .. string.rep("i", 240) .. ";Player-9-610",
        "GUILD", "Peer-Clamp")
    local clampSends = dTagged(drainSends())
    local echoId = clampSends[1] and clampSends[1].msg:match("^D;2;([^;]*);")
    check(clampSends[1] ~= nil and #clampSends[1].msg <= 240
        and echoId ~= nil and #echoId <= 8,
        "request-id clamp on G echo",
        "len=" .. tostring(clampSends[1] and #clampSends[1].msg)
            .. " idlen=" .. tostring(echoId and #echoId))

    -- 11. A full queue drops the G answer's S without evicting queued rank
    -- traffic (the D leg already dropped; the S leg now mirrors it). Fills
    -- the 50-message FIFO under throttle and fires one G: both legs must
    -- drop (oversize +2, depth stays 50). Pre-fix the S evicts instead of
    -- dropping (oversize +1, depth still 50).
    isolationSweep()
    setSendResult(3)
    for index = 1, 50 do
        RankSync.Enqueue("Q;fill" .. index, "GUILD")
    end
    check((RankSync.GetDebugState().queueDepth or 0) == 50,
        "full-queue G pin seeds a 50-deep FIFO",
        "depth=" .. tostring(RankSync.GetDebugState().queueDepth))
    local fullOverBefore = gearOutcomes().enqueueOversize or 0
    gearRemoteStub["Player-9-9F1"] = { state = "complete", revision = { slots = {
        [1] = { itemID = { value = 99101 } },
    } } }
    RankSync.HandlePayload("G;2;full1;Player-9-9F1", "GUILD", "Sender-Full")
    check(((gearOutcomes().enqueueOversize or 0) - fullOverBefore) == 2
        and (RankSync.GetDebugState().queueDepth or 0) == 50,
        "full-queue G answer drops S without evicting queued traffic",
        "over=" .. tostring(fullOverBefore) .. "->"
            .. tostring(gearOutcomes().enqueueOversize)
            .. " depth=" .. tostring(RankSync.GetDebugState().queueDepth))

    -- M-6: the 50-message cap evicts the OLDEST queued message. It used to do
    -- that with nothing said and nothing counted -- a peer that never appears
    -- was undiagnosable, and the library's own analogous queue counts its
    -- drops. Counted here, with the kind of the evicted message named.
    local evictedBefore = gearOutcomes().queueEvicted or 0
    RankSync.Enqueue("Q;evict1", "GUILD")
    local evictState = RankSync.GetDebugState()
    check((evictState.outcomes.queueEvicted or 0) == evictedBefore + 1,
        "a 51st queued message evicts the oldest, and the eviction is counted",
        "queueEvicted " .. tostring(evictedBefore) .. " -> "
            .. tostring(evictState.outcomes.queueEvicted)
            .. " depth=" .. tostring(evictState.queueDepth))
    check(type(evictState.lastEvictedKind) == "string"
        and evictState.lastEvictedKind ~= "",
        "the eviction names the kind of message that was lost",
        "lastEvictedKind=" .. tostring(evictState.lastEvictedKind))
    -- Drain the seeded FIFO so later checks start clean (same tick +
    -- flush + drain shape as the starvation sequence above; 30 iterations
    -- cover the 50-deep FIFO since each pass nets at least two sends).
    setSendResult(0)
    for _ = 1, 30 do
        if (RankSync.GetDebugState().queueDepth or 0) == 0 then break end
        tick()
        RankSync.Enqueue(";-flush", "GUILD")
        drain()
    end
    gearRemoteStub["Player-9-9F1"] = nil

    -- 16. The snapshot exposes the five gear buckets beside the old ones.
    do
        local dbg = RankSync.GetDebugState()
        local oc = type(dbg) == "table" and dbg.outcomes or {}
        check(oc.gearNoData ~= nil and oc.gearBadGuid ~= nil
            and oc.gearStale ~= nil and oc.gearCoalesced ~= nil
            and oc.gearStored ~= nil,
            "GetDebugState exposes gear buckets alongside existing ones",
            "nodata=" .. tostring(oc.gearNoData) .. " bad=" .. tostring(oc.gearBadGuid)
                .. " stale=" .. tostring(oc.gearStale) .. " coal=" .. tostring(oc.gearCoalesced)
                .. " stored=" .. tostring(oc.gearStored))
        check(oc.answerNoTransport ~= nil and oc.versionReject ~= nil
            and oc.enqueueOversize ~= nil,
            "the pre-existing buckets still enumerate after the G/D edit",
            "skip=" .. tostring(oc.answerNoTransport)
                .. " ver=" .. tostring(oc.versionReject)
                .. " over=" .. tostring(oc.enqueueOversize))
    end

    -- ------------------------------------------------------------------
    -- Stage-1 coverage pins (Oracle §2.1-§2.4 carry-forward). Every arm
    -- below executes in production but never fired in the harness: RAID
    -- and INSTANCE_CHAT answers, the CHANNEL-active answer, the end-to-end
    -- CHAT_MSG_ADDON threading, the legacy-global nil result, the
    -- oversize/other/error/channel-throttle buckets, the /ttgsdebug print
    -- lines, and the outbound id shape. All reuse this block's send
    -- capture, phase isolation and re-arm -- no new production seams.
    -- ------------------------------------------------------------------
    local runStage1Coverage = (function()
    -- RAID: a query naming RAID is answered on RAID, nowhere else.
    local coverageSavedRaid = REALG.IsInRaid
    REALG.IsInRaid = function() return true end
    isolationSweep()
    RankSync.HandlePayload("Q;raidarm", "RAID", "Raid-Sender")
    local raidSends = drainSends()
    local raidST, raidLeak = 0, nil
    for index = 1, #raidSends do
        local tag = raidSends[index].msg:sub(1, 2)
        if tag == "S;" or tag == "T;" then
            raidST = raidST + 1
            if raidSends[index].chatType ~= "RAID" then
                raidLeak = raidSends[index].chatType
            end
        end
    end
    check(raidST >= 1,
        "a query on RAID is answered (RAID arm fires)",
        "answers=" .. raidST)
    check(raidLeak == nil,
        "a query on RAID is answered on RAID, never another transport",
        "leak=" .. tostring(raidLeak))

    -- INSTANCE_CHAT: answer arm plus the broadcast transport. Inside a raid
    -- instance the group channel is INSTANCE_CHAT, not RAID.
    local coverageSavedInstance = REALG.IsInInstance
    REALG.IsInInstance = function() return true, "raid" end
    isolationSweep()
    RankSync.HandlePayload("Q;instarm", "INSTANCE_CHAT", "Inst-Sender")
    local instSends = drainSends()
    local instST, instLeak = 0, nil
    for index = 1, #instSends do
        local tag = instSends[index].msg:sub(1, 2)
        if tag == "S;" or tag == "T;" then
            instST = instST + 1
            if instSends[index].chatType ~= "INSTANCE_CHAT" then
                instLeak = instSends[index].chatType
            end
        end
    end
    check(instST >= 1,
        "a query on INSTANCE_CHAT is answered (INSTANCE_CHAT arm fires)",
        "answers=" .. instST)
    check(instLeak == nil,
        "a query on INSTANCE_CHAT is answered on INSTANCE_CHAT, never another transport",
        "leak=" .. tostring(instLeak))
    local ownRec = HARNESS_PLAYER_GUID and RankDB.GetRecord(HARNESS_PLAYER_GUID) or nil
    RankSync.BroadcastRecord(ownRec or {
        guid = HARNESS_PLAYER_GUID, name = "Tester",
        classID = 1, gs = 6000, timestamp = REALG.time and REALG.time() or 1000000,
    })
    local bcastSends = drainSends()
    local bcastInst = false
    for index = 1, #bcastSends do
        if bcastSends[index].chatType == "INSTANCE_CHAT"
            and bcastSends[index].msg:sub(1, 2) == "R;" then
            bcastInst = true
        end
    end
    check(bcastInst,
        "a broadcast inside a raid instance rides INSTANCE_CHAT",
        "sends=" .. #bcastSends)
    REALG.IsInRaid = coverageSavedRaid
    REALG.IsInInstance = coverageSavedInstance

    -- CHANNEL-active: the arm the dead-channel pins only exercise
    -- negatively -- a query on a live channel is answered on CHANNEL.
    isolationSweep()
    RankSync.HandlePayload("Q;chanarm", "CHANNEL", "Chan-Sender")
    local chanSends = drainSends()
    local chanST, chanLeak, chanTarget = 0, nil, nil
    for index = 1, #chanSends do
        local tag = chanSends[index].msg:sub(1, 2)
        if tag == "S;" or tag == "T;" then
            chanST = chanST + 1
            if chanSends[index].chatType ~= "CHANNEL" then
                chanLeak = chanSends[index].chatType
            else
                chanTarget = chanSends[index].target
            end
        end
    end
    check(chanST >= 1,
        "a query on a live channel is answered (CHANNEL-active arm fires)",
        "answers=" .. chanST)
    check(chanLeak == nil and chanTarget == "7",
        "a query on a live channel is answered on CHANNEL with the joined id",
        "leak=" .. tostring(chanLeak) .. " target=" .. tostring(chanTarget))

    -- End to end: a real CHAT_MSG_ADDON event threads arg3/arg4 (channel /
    -- sender) into a same-transport answer. A swapped arg3/arg4 in onEvent
    -- would answer nothing and count a skip instead -- both halves assert.
    isolationSweep()
    local e2eSkipBefore = (RankSync.GetDebugState().outcomes or {}).answerNoTransport or 0
    fireEvent("CHAT_MSG_ADDON", "TACO_GS_SYNC", "Q;e2e1", "GUILD", "E2E-Sender")
    local e2eSends = drainSends()
    local e2eST, e2eLeak = 0, nil
    for index = 1, #e2eSends do
        local tag = e2eSends[index].msg:sub(1, 2)
        if tag == "S;" or tag == "T;" then
            e2eST = e2eST + 1
            if e2eSends[index].chatType ~= "GUILD" then
                e2eLeak = e2eSends[index].chatType
            end
        end
    end
    local e2eSkipAfter = (RankSync.GetDebugState().outcomes or {}).answerNoTransport or 0
    check(e2eST >= 1,
        "a CHAT_MSG_ADDON query threads arg3/arg4 to an answer (end to end)",
        "answers=" .. e2eST)
    check(e2eLeak == nil and e2eSkipAfter == e2eSkipBefore,
        "the event-threaded answer rides the query's own transport (GUILD), no skip",
        "leak=" .. tostring(e2eLeak)
            .. " skip=" .. tostring(e2eSkipBefore) .. "->" .. tostring(e2eSkipAfter))

    -- Legacy global: with no C_ChatInfo the classic-family SendAddonMessage
    -- returns nothing, which arrives as nil -- counted sendNoInfo, not an
    -- error, and the message still goes on the wire.
    isolationSweep()
    local coverageSavedChat = REALG.C_ChatInfo
    local coverageSavedLegacy = REALG.SendAddonMessage
    REALG.C_ChatInfo = nil
    REALG.SendAddonMessage = function(prefix, msg, chatType, target)
        sent[#sent + 1] = {
            prefix = prefix, msg = msg, chatType = chatType, target = target,
        }
    end
    local noInfoBefore = (RankSync.GetDebugState().outcomes or {}).sendNoInfo or 0
    RankSync.Enqueue("Q;legacy1", "GUILD")
    local legacySends = drainSends()
    local noInfoAfter = (RankSync.GetDebugState().outcomes or {}).sendNoInfo or 0
    check(noInfoAfter == noInfoBefore + 1,
        "the legacy-global nil result is counted (sendNoInfo)",
        "noinfo=" .. tostring(noInfoBefore) .. "->" .. tostring(noInfoAfter))
    check(#legacySends == 1 and legacySends[1].msg == "Q;legacy1",
        "the legacy-global send still puts the message on the wire",
        "sends=" .. #legacySends)
    REALG.C_ChatInfo = coverageSavedChat
    REALG.SendAddonMessage = coverageSavedLegacy

    -- Oversize: a >240 direct Enqueue is refused at the door and counted,
    -- never queued ahead of real traffic.
    isolationSweep()
    local overDirectBefore = (RankSync.GetDebugState().outcomes or {}).enqueueOversize or 0
    RankSync.Enqueue(string.rep("X", 241), "GUILD")
    local overDirectSends = drainSends()
    local overDirectAfter = (RankSync.GetDebugState().outcomes or {}).enqueueOversize or 0
    check(overDirectAfter == overDirectBefore + 1,
        "a >240 direct Enqueue is refused and counted (enqueueOversize)",
        "oversize=" .. tostring(overDirectBefore) .. "->" .. tostring(overDirectAfter))
    check(#overDirectSends == 0,
        "a refused oversize message never reaches any transport",
        "sends=" .. #overDirectSends)

    -- sendOther: an unrecognized result is its own bucket, not success.
    isolationSweep()
    setSendResult(99)
    local otherBefore = (RankSync.GetDebugState().outcomes or {}).sendOther or 0
    RankSync.Enqueue("Q;other1", "GUILD")
    drainSends()
    local otherAfter = (RankSync.GetDebugState().outcomes or {}).sendOther or 0
    check(otherAfter == otherBefore + 1,
        "an unrecognized send result is counted (sendOther)",
        "other=" .. tostring(otherBefore) .. "->" .. tostring(otherAfter))
    setSendResult(0)

    -- sendError: a raising send is counted and puts nothing on the wire.
    isolationSweep()
    local coverageSavedSendFn = REALG.C_ChatInfo.SendAddonMessage
    REALG.C_ChatInfo.SendAddonMessage = function() error("boom") end
    local errBefore = (RankSync.GetDebugState().outcomes or {}).sendError or 0
    RankSync.Enqueue("Q;err1", "GUILD")
    local errSends = drainSends()
    local errAfter = (RankSync.GetDebugState().outcomes or {}).sendError or 0
    check(errAfter == errBefore + 1,
        "a raising send is counted (sendError)",
        "error=" .. tostring(errBefore) .. "->" .. tostring(errAfter))
    check(#errSends == 0,
        "a raising send puts nothing on the wire",
        "sends=" .. #errSends)
    REALG.C_ChatInfo.SendAddonMessage = coverageSavedSendFn

    -- Channel-throttle: same requeue shape as the addon-throttle pin, on its
    -- own bucket -- the transient refusal keeps the item queued, no token
    -- spent, delivered ahead of newer traffic on the next tick.
    isolationSweep()
    setSendResult(8)
    local ctBefore = RankSync.GetDebugState().outcomes or {}
    RankSync.Enqueue("Q;ct1", "GUILD")
    drainSends()
    local ctAfter = RankSync.GetDebugState().outcomes or {}
    check((ctAfter.sendChannelThrottle or 0) == (ctBefore.sendChannelThrottle or 0) + 1
        and (ctAfter.requeued or 0) == (ctBefore.requeued or 0) + 1,
        "a channel-throttled send is counted (channel-throttle + requeued buckets)",
        "ct=" .. tostring(ctBefore.sendChannelThrottle) .. "->" .. tostring(ctAfter.sendChannelThrottle))
    setSendResult(0)
    tick()
    RankSync.Enqueue("Q;ctnormal", "GUILD")
    local ctRetry = drain()
    local ctRequeued, ctNewest = nil, nil
    for index = 1, #ctRetry do
        if ctRetry[index] == "Q;ct1" then
            ctRequeued = index
        elseif ctRetry[index] == "Q;ctnormal" then
            ctNewest = index
        end
    end
    check(ctRequeued ~= nil and ctNewest ~= nil and ctRequeued < ctNewest,
        "a channel-throttled send is re-queued and delivered on the next tick",
        table.concat(ctRetry, " | "))

    -- /ttgsdebug print lines: the buckets are asserted through GetDebugState
    -- above, but the printed lines are what the operator reads -- a renamed
    -- bucket key between Core and RankSync would pass every snapshot check
    -- while printing zeros. Capture what the slash handler actually emits.
    local chatBefore = #CHAT
    REALG.SlashCmdList.TTEXTRASDEBUG()
    local chatJoined = ""
    for index = chatBefore + 1, #CHAT do
        chatJoined = chatJoined .. "\n" .. tostring(CHAT[index])
    end
    check(chatJoined:find("/ttgsdebug rank sync", 1, true) ~= nil,
        "/ttgsdebug prints the rank-sync section",
        "lines=" .. tostring(#CHAT - chatBefore))
    check(chatJoined:find("sends success=", 1, true) ~= nil
        and chatJoined:find("skipped no-transport=", 1, true) ~= nil
        and chatJoined:find("channel=", 1, true) ~= nil,
        "/ttgsdebug prints the outcome buckets and channel state",
        chatJoined:sub(1, 120))

    -- The surfaces block (final hunter H-3).
    --
    -- EVERY diagnostic counter in this add-on used to be reachable only from
    -- this harness: the code comments said "surfaced in GetDebugState below",
    -- and GetDebugState was read by nothing outside the harness. A counter no
    -- user can see is a counter that cannot be acted on.
    --
    -- So the assertion is on the PRINTED TEXT, and against the accessor's own
    -- value: a counter that is renamed on one side of the boundary, or
    -- dropped from the printout, prints something else and goes red. Asserting
    -- on the accessor alone would pass with the surface rotting again.
    do
        local surfacesText = chatJoined
        check(surfacesText:find("/ttgsdebug surfaces", 1, true) ~= nil,
            "/ttgsdebug prints the surfaces block",
            "lines=" .. tostring(#CHAT - chatBefore))

        local driverState = namespace.Tooltips.GetDriverState()
        local tooltipDebugState = namespace.Tooltips.GetDebugState()
        local browserDebugState = namespace.RankBrowser.GetDebugState()
        local cacheDebugState = namespace.Cache.GetDebugState()
        local scannerDebugState = namespace.Scanner.GetDebugState()
        local syncDebugState = namespace.RankSync.GetDebugState()
        local syncCounts = syncDebugState.outcomes or {}
        local framesDebugState = namespace.Frames.GetDebugState()
        local optionsDebugState = namespace.Options.GetDebugState()

        -- Each entry: the LABEL the printout must carry, and the value it must
        -- carry, read from the module's own accessor.
        local printed = {
            { "driver mode", driverState.mode },
            { "renders", driverState.renders },
            { "rows", driverState.rows },
            { "poll-ticks", driverState.pollTicks },
            { "render-errors", driverState.renderErrors },
            { "rank-record-errors", tooltipDebugState.rankRecordErrors },
            { "row-tooltip-errors", browserDebugState.rowTooltipErrors },
            { "score-colour-fallbacks", tooltipDebugState.scoreColorFallbacks },
            { "cache-listener-errors", cacheDebugState.listenerErrors },
            { "scanner-listener-errors", scannerDebugState.listenerErrors },
            { "records-rejected", syncCounts.recordRejected or 0 },
            { "queue-evicted", syncCounts.queueEvicted or 0 },
            { "initialize-failures", #namespace.Core.GetInitializeFailures() },
            { "frame-hook-errors", framesDebugState.hookCallbackErrors },
            { "options-action-failures", optionsDebugState.actionFailures },
        }
        local notPrinted = {}
        for _, entry in ipairs(printed) do
            local needle = entry[1] .. "=" .. tostring(entry[2])
            if surfacesText:find(needle, 1, true) == nil then
                notPrinted[#notPrinted + 1] = needle
            end
        end
        check(#notPrinted == 0,
            "/ttgsdebug prints every diagnostic counter with its live value",
            "not printed: " .. table.concat(notPrinted, ", "))

        -- The "last reason" companions: a count without a reason is not
        -- something a user can act on, so the reason rides along.
        local reasons = {
            { "last-render-error", driverState.lastRenderError },
            { "last-rank-record-error", tooltipDebugState.lastRankRecordError },
            { "last-row-tooltip-error", browserDebugState.lastRowTooltipError },
            { "last-score-colour-reason", tooltipDebugState.lastScoreColorReason },
            { "last-cache-listener-error", cacheDebugState.lastListenerError },
            { "last-scanner-listener-error", scannerDebugState.lastListenerError },
            { "last-record-rejected-reason", syncDebugState.lastRecordRejectedReason },
            { "last-evicted-kind", syncDebugState.lastEvictedKind },
            { "last-frame-hook-error", framesDebugState.lastHookCallbackError },
            { "last-options-action-failure", optionsDebugState.lastActionFailure },
        }
        local missingReasons = {}
        for _, entry in ipairs(reasons) do
            local needle = entry[1] .. "="
            if surfacesText:find(needle, 1, true) == nil then
                missingReasons[#missingReasons + 1] = needle
            end
        end
        check(#missingReasons == 0,
            "/ttgsdebug prints the last reason beside each counter",
            "not printed: " .. table.concat(missingReasons, ", "))
    end

    -- ---------------------------------------------------------------------------
    -- The bounded-callback boundary (final hardening pass).
    --
    -- A raise inside a HookScript handler or a hooksecurefunc post-hook does
    -- NOT stay inside this add-on: it unwinds through the client's own frame
    -- script, so the rest of Blizzard's handler for that frame never runs.
    -- The player sees a broken character pane and the add-on has no idea why.
    --
    -- So every callback the Extras registers is wrapped, and a raise inside
    -- one is caught, counted and named instead of escaping.
    -- ---------------------------------------------------------------------------
    do
        local frames = namespace.Frames
        check(type(frames) == "table" and type(frames.GetDebugState) == "function",
            "the equipment-frame module publishes its diagnostic snapshot",
            "frames=" .. tostring(type(frames)))

        local host = REALG["PaperDollFrame"]
        -- The character PANE's OnShow is the live trigger: the paper doll
        -- carries no `hidden` attribute, so it is shown from the moment it is
        -- created, its OnShow fired long before this add-on loaded, and a hook
        -- on it could never fire again. The pane IS hidden at creation, so
        -- its OnShow fires once per pane open.
        --
        -- The OnSizeChanged hook is the POSITION refresh, and it is hooked
        -- only when the frame declares that script -- the paper doll declares
        -- no OnSizeChanged on any client, and an unguarded HookScript raises
        -- (the failure that aborted the MAIN add-on's Retail load in 0.7.8).
        local characterFrame = REALG["CharacterFrame"]
        local summary = REALG["TacoTip_ExtrasCharacterSummary"]
        local handler = nil
        if type(characterFrame) == "table" and type(characterFrame.GetScript) == "function" then
            handler = characterFrame:GetScript("OnHide")
        end
        check(type(handler) == "function",
            "the character PANE's OnHide hook is registered",
            "frame=" .. tostring(type(characterFrame)) .. " handler=" .. tostring(type(handler)))
        local showHandler = nil
        if type(characterFrame) == "table" and type(characterFrame.GetScript) == "function" then
            showHandler = characterFrame:GetScript("OnShow")
        end
        check(type(showHandler) == "function",
            "the character PANE's OnShow hook is registered (the live trigger)",
            "frame=" .. tostring(type(characterFrame)) .. " handler=" .. tostring(type(showHandler)))
        check(type(host) == "table" and type(host.GetScript) == "function"
            and host:GetScript("OnSizeChanged") == nil,
            "the paper doll's OnSizeChanged hook is NOT registered -- the frame declares no such script",
            "host=" .. tostring(type(host))
                .. " handler=" .. tostring(host and host.GetScript and host:GetScript("OnSizeChanged")))

        local before = namespace.Frames.GetDebugState()
        -- The INJECTION POINT. The block's rows are cleared with an UNGUARDED
        -- SetText when the pane hides (hideRows), so a raise there is exactly a
        -- raise inside a hooked callback. The rows hang off the block, and the
        -- mock registers a child on its parent the way the client does.
        local rows = type(summary) == "table" and rawget(summary, "__children") or nil
        local row = nil
        for _, child in ipairs(rows or {}) do
            if type(child) == "table" and rawget(child, "__methods")
                and rawget(child, "__methods").SetText then
                row = child
                break
            end
        end
        local rowMethods = row and rawget(row, "__methods") or nil
        local originalSetText = rowMethods and rowMethods.SetText or nil
        local raised = false
        if rowMethods and originalSetText then
            rowMethods.SetText = function()
                raised = true
                error("harness: injected row SetText raise")
            end
        end
        local escaped = false
        if type(handler) == "function" then
            local ok = pcall(handler, characterFrame)
            escaped = not ok
        end
        if rowMethods and originalSetText then
            rowMethods.SetText = originalSetText
        end

        check(raised,
            "the injected raise really reached the hooked callback",
            "raised=" .. tostring(raised))
        check(not escaped,
            "a raise inside a hooked callback does not escape into the client",
            "escaped=" .. tostring(escaped))
        local after = namespace.Frames.GetDebugState()
        check(after.hookCallbackErrors == (before.hookCallbackErrors or 0) + 1,
            "a raise inside a hooked callback is counted",
            "hookCallbackErrors " .. tostring(before.hookCallbackErrors)
                .. " -> " .. tostring(after.hookCallbackErrors))
        check(type(after.lastHookCallbackError) == "string"
            and after.lastHookCallbackError:find("injected row SetText raise", 1, true) ~= nil,
            "the hooked callback's failure is named",
            "lastHookCallbackError=" .. tostring(after.lastHookCallbackError))
    end

    -- ---------------------------------------------------------------------------
    -- The counted options-action boundary (final hardening pass).
    --
    -- "Comfortable rows" and "Shaman Blue" wrote their setting and then
    -- DISCARDED the result of RankBrowser.RebuildUI. A raising rebuild left
    -- the player with a ticked box, an unchanged window, and no message and
    -- no count. The result is captured now, the failure is counted, and the
    -- player is told in one plain chat line.
    -- ---------------------------------------------------------------------------
    do
        local options = namespace.Options
        check(type(options) == "table" and type(options.GetDebugState) == "function",
            "the options module publishes its diagnostic snapshot",
            "options=" .. tostring(type(options)))

        local box = REALG["TacoTip_ExtrasOptionComfortableRows"]
        check(type(box) == "table" and type(box.GetScript) == "function",
            "the 'Comfortable rows' checkbox exists",
            "box=" .. tostring(type(box)))
        local click = nil
        if type(box) == "table" and type(box.GetScript) == "function" then
            click = box:GetScript("OnClick")
        end
        check(type(click) == "function",
            "the 'Comfortable rows' checkbox has its click handler",
            "click=" .. tostring(type(click)))

        local browser = namespace.RankBrowser
        local originalRebuild = browser.RebuildUI
        browser.RebuildUI = function()
            error("harness: injected RebuildUI raise")
        end
        local chatLinesBefore = #CHAT
        local escaped = false
        if type(click) == "function" then
            box:SetChecked(true)
            local ok = pcall(click, box)
            escaped = not ok
        end
        browser.RebuildUI = originalRebuild

        check(not escaped,
            "a raising leaderboard rebuild does not escape the checkbox",
            "escaped=" .. tostring(escaped))
        local state = namespace.Options.GetDebugState()
        check(state.actionFailures >= 1,
            "a raising leaderboard rebuild is counted",
            "actionFailures=" .. tostring(state.actionFailures))
        check(type(state.lastActionFailure) == "string"
            and state.lastActionFailure:find("injected RebuildUI raise", 1, true) ~= nil,
            "the failing options action is named",
            "lastActionFailure=" .. tostring(state.lastActionFailure))
        local said = false
        for index = chatLinesBefore + 1, #CHAT do
            if tostring(CHAT[index]):find("could not be rebuilt", 1, true) ~= nil then
                said = true
                break
            end
        end
        check(said,
            "the player is told in one chat line that the window was not rebuilt",
            "chat lines added=" .. tostring(#CHAT - chatLinesBefore))
    end

    -- ---------------------------------------------------------------------------
    -- The counters the surfaces block prints must actually MOVE (final hunter
    -- M-3 / M-5). A printed zero that can never become a one is decoration.
    -- ---------------------------------------------------------------------------
    do
        -- M-3, Cache half: the fan-out is pcall-guarded so one bad listener
        -- cannot stop the others or abort a publish that has already been
        -- committed -- but the guard made the failure invisible: the cache
        -- entry was already mutated when the listener raised, so the update
        -- was lost with nothing said and nothing counted.
        local cacheBefore = namespace.Cache.GetDebugState()
        local raisingCacheListener = function()
            error("harness: injected Cache listener raise")
        end
        namespace.Cache.Subscribe(raisingCacheListener)
        namespace.Cache.Begin("Harness-M3-Cache-Guid", 900001, "harness-m3")
        namespace.Cache.Unsubscribe(raisingCacheListener)
        local cacheAfter = namespace.Cache.GetDebugState()
        check(cacheAfter.listenerErrors == (cacheBefore.listenerErrors or 0) + 1,
            "a raising cache listener is counted",
            "listenerErrors " .. tostring(cacheBefore.listenerErrors)
                .. " -> " .. tostring(cacheAfter.listenerErrors))
        check(type(cacheAfter.lastListenerError) == "string"
            and cacheAfter.lastListenerError:find("injected Cache listener raise", 1, true) ~= nil,
            "the raising cache listener's message is recorded",
            "lastListenerError=" .. tostring(cacheAfter.lastListenerError))

        -- M-3, Scanner half: the same guard on the scan's state fan-out. The
        -- new state was already published when the listener raised, so the
        -- update was lost with nothing said and nothing counted.
        local scannerBefore = namespace.Scanner.GetDebugState()
        local raisingScannerListener = function()
            error("harness: injected Scanner listener raise")
        end
        namespace.Scanner.Subscribe(raisingScannerListener)
        namespace.Scanner.BeginGeneration("harness-m3-listener")
        namespace.Scanner.Unsubscribe(raisingScannerListener)
        local scannerAfter = namespace.Scanner.GetDebugState()
        check(scannerAfter.listenerErrors == (scannerBefore.listenerErrors or 0) + 1,
            "a raising scanner listener is counted",
            "listenerErrors " .. tostring(scannerBefore.listenerErrors)
                .. " -> " .. tostring(scannerAfter.listenerErrors))
        check(type(scannerAfter.lastListenerError) == "string"
            and scannerAfter.lastListenerError:find("injected Scanner listener raise", 1, true) ~= nil,
            "the raising scanner listener's message is recorded",
            "lastListenerError=" .. tostring(scannerAfter.lastListenerError))

        -- Restore: re-drive the local scan so the scanner is COMPLETE again,
        -- exactly where the harness found it. The pin must not leave the
        -- session in a state the later phases would read as a pending scan.
        namespace.Core.RequestLocalScan("harness-m3-restore")
        for _, frame in ipairs(FRAMES_BY_REGISTRATION) do
            if type(frame) == "table" and type(frame.GetScript) == "function"
                and type(frame:GetScript("OnUpdate")) == "function" then
                local script = frame:GetScript("OnUpdate")
                if type(script) == "function" then
                    pcall(script, frame)
                end
            end
        end

        -- M-5: a record that fails RankDB.ValidateRecord used to be dropped
        -- with nothing said and nothing counted -- while the VERSION mismatch
        -- on the very same path WAS counted. A peer whose records are all
        -- refused was undiagnosable.
        --
        -- Both arms are driven: the single-record arm (an "R" payload) and the
        -- digest arm (an "S" payload, whose records ride inside it).
        local rejectedBefore =
            (namespace.RankSync.GetDebugState().outcomes or {}).recordRejected or 0
        -- A well-formed R payload whose gearscore is 0: the wire carries it,
        -- the validator refuses it (a gearscore below 1 is not a gearscore).
        namespace.RankSync.HandlePayload(
            "R;2;Harness-M5-Guid;HarnessM5;1;0;80;1759000000;;Knights;70;;0",
            "GUILD", "Harness-M5-Sender")
        local rejectedSingle = namespace.RankSync.GetDebugState()
        check((rejectedSingle.outcomes.recordRejected or 0) == rejectedBefore + 1,
            "a record the validator refuses is counted",
            "recordRejected " .. tostring(rejectedBefore)
                .. " -> " .. tostring(rejectedSingle.outcomes.recordRejected))
        check(type(rejectedSingle.lastRecordRejectedReason) == "string"
            and rejectedSingle.lastRecordRejectedReason ~= "",
            "the refused record's reason is kept",
            "lastRecordRejectedReason="
                .. tostring(rejectedSingle.lastRecordRejectedReason))

        local digestBefore = (rejectedSingle.outcomes.recordRejected or 0)
        namespace.RankSync.HandlePayload(
            "S;2;R;2;Harness-M5-Digest;HarnessM5D;1;0;80;1759000000;;Knights;70;;0",
            "GUILD", "Harness-M5-Sender")
        local rejectedDigest = namespace.RankSync.GetDebugState()
        check((rejectedDigest.outcomes.recordRejected or 0) == digestBefore + 1,
            "a record the validator refuses inside a digest is counted too",
            "recordRejected " .. tostring(digestBefore)
                .. " -> " .. tostring(rejectedDigest.outcomes.recordRejected))
    end

    -- Outbound id shape: request ids are fixed-width six hex, so no id rides
    -- a response whole.
    isolationSweep()
    RankSync.RequestSync()
    local qSends = drainSends()
    local qCount, qBad = 0, nil
    for index = 1, #qSends do
        local id = qSends[index].msg:match("^Q;([^;]+)$")
        if id then
            qCount = qCount + 1
            if #id ~= 6 or not id:match("^%x+$") then
                qBad = qSends[index].msg:sub(1, 24)
            end
        end
    end
    check(qCount >= 1 and qBad == nil,
        "outbound request ids are fixed-width 6-hex",
        "q=" .. qCount .. " bad=" .. tostring(qBad))
    end)
    runStage1Coverage()

    gearScanner.GetCurrent = savedGetCurrent
    gearScanner.GetFreshRemote = savedGetFreshRemote

    -- Restore.
    setSendResult(0)
    if REALG.C_Timer then REALG.C_Timer.After = realAfter end
    REALG.C_ChatInfo = savedCChatInfo
    REALG.JoinChannelByName = savedJoinChannelByName
    REALG.GetChannelName = savedGetChannelName
    if savedGetTime == nil then REALG.GetTime = nil else REALG.GetTime = savedGetTime end
    if savedIsInGroup == nil then REALG.IsInGroup = nil else REALG.IsInGroup = savedIsInGroup end
    if savedIsInGuild == nil then REALG.IsInGuild = nil else REALG.IsInGuild = savedIsInGuild end
    if savedIsInRaid == nil then REALG.IsInRaid = nil else REALG.IsInRaid = savedIsInRaid end
    if savedIsInInstance == nil then REALG.IsInInstance = nil else REALG.IsInInstance = savedIsInInstance end
    end)
    runQueryProtocol()
end

-- ---------------------------------------------------------------------------
-- Stage 2 -- storage hygiene (storage-expansion audit §6.2 Stage 2).
--
-- Each feature check below fails on the pre-Stage-2 code: no login pass ever
-- ran (so stale rows and dead realm keys stayed forever), rows were written
-- with the dead source/specIcon fields, and SAVED_VARIABLES_TOO_LARGE had no
-- reaction. The wire-stride checks inside this block now pin the wire-DIET
-- stride (versioned nine-field, realm/faction/class-string/spec-name off the
-- wire) rather than the Stage-2 eleven-field stride. The cap-semantics
-- checks are the deliberately preserved contract (oldest timestamp first,
-- exactly MAX_CAPACITY visible, count == visible set) -- identical on both
-- sides of the change, since neither stage moves customer-visible semantics.
--
-- The block runs inside one closure for the chunk's local budget, the same
-- pattern the query-protocol block above uses.
-- ---------------------------------------------------------------------------
do
local runStage2 = (function()
local RankDB = namespace.RankDB
local RankSync = namespace.RankSync
local testNow = REALG.time and REALG.time() or 1000000
local DAY = 24 * 3600
local MAX_CAPACITY = RankDB.MAX_CAPACITY or 20000

if type(REALG.TacoTipExtrasDB) ~= "table" then
    REALG.TacoTipExtrasDB = {}
end
if type(REALG.TacoTipExtrasDB.ranks) ~= "table" then
    REALG.TacoTipExtrasDB.ranks = {}
end
local ranksRoot = REALG.TacoTipExtrasDB.ranks

local function countRows(realmKey)
    local db = ranksRoot[realmKey]
    if type(db) ~= "table" then return 0 end
    local n = 0
    for _ in pairs(db) do n = n + 1 end
    return n
end

local function visibleCount(realmKey)
    local _, shown = RankDB.GetLeaderboard(realmKey, "all")
    return shown or 0
end

out(("\n-- Stage 2: storage hygiene (expansion audit §6.2 Stage 2) --\n"))

-- Item 1: the once-per-session login prune. The base harness's C_Timer.After
-- is a deliberate no-op (:783), so the :2186 PLAYER_ENTERING_WORLD fire
-- scheduled a callback that never ran and left the once-arm unset -- which is
-- exactly why this block can install a SYNCHRONOUS runner (the same pattern
-- the query-protocol block uses) and watch the deferred callback execute.
local savedAfter = REALG.C_Timer and REALG.C_Timer.After
REALG.C_Timer = REALG.C_Timer or {}
REALG.C_Timer.After = function(_, fn)
    if type(fn) == "function" then fn() end
    return true
end

RankDB.StoreRecord({ guid = "Player-21-A1", name = "StaleA", faction = "Horde", class = "WARRIOR", gs = 1000, timestamp = testNow - 70 * DAY }, "PruneA")
RankDB.StoreRecord({ guid = "Player-21-A2", name = "FreshA", faction = "Horde", class = "WARRIOR", gs = 1500, timestamp = testNow - 10 * DAY }, "PruneA")
RankDB.StoreRecord({ guid = "Player-21-B1", name = "Doomed", faction = "Horde", class = "WARRIOR", gs = 1000, timestamp = testNow - 70 * DAY }, "PruneB")

fireEvent("PLAYER_ENTERING_WORLD")

check(RankDB.GetRecord("Player-21-A1", "PruneA") == nil,
    "Stage2: the login prune removes rows older than the 60-day window",
    "stale=" .. tostring(RankDB.GetRecord("Player-21-A1", "PruneA")))
check(type(RankDB.GetRecord("Player-21-A2", "PruneA")) == "table",
    "Stage2: the login prune keeps fresh rows")
check(countRows("PruneA") >= 1,
    "Stage2: the login prune keeps a realm that still holds rows",
    "rows=" .. countRows("PruneA"))
check(ranksRoot["PruneB"] == nil,
    "Stage2: the login prune deletes a realm key the prune emptied",
    "PruneB=" .. tostring(type(ranksRoot["PruneB"])))

-- Once per session: a second PLAYER_ENTERING_WORLD must not re-walk the
-- database -- the arm is set by the first callback that actually runs.
RankDB.StoreRecord({ guid = "Player-21-C1", name = "Late", faction = "Horde", class = "WARRIOR", gs = 1000, timestamp = testNow - 70 * DAY }, "PruneC")
fireEvent("PLAYER_ENTERING_WORLD")
check(type(RankDB.GetRecord("Player-21-C1", "PruneC")) == "table",
    "Stage2: the login prune runs once per session (second event does not re-prune)",
    "late=" .. tostring(RankDB.GetRecord("Player-21-C1", "PruneC")))

-- That second PLAYER_ENTERING_WORLD re-arms the enter-world trigger of the
-- scan exactly like the base harness's own fire does: whatever generation
-- got scheduled must be pumped through eventFrame OnUpdate, or every later
-- Tooltips render sees a pending scan instead of a complete one and drops
-- its rank line. Same drive shape as the base pump, bounded so a wedged
-- scan cannot hang the run.
do
    local pumpBound = 5
    while pumpBound > 0 do
        local current = namespace.Scanner and namespace.Scanner.GetCurrent() or nil
        if type(current) ~= "table" or current.status == "complete" then break end
        for _, frame in ipairs(FRAMES_BY_REGISTRATION) do
            if type(frame) == "table" and type(frame.GetScript) == "function"
                and type(frame:GetScript("OnUpdate")) == "function" then
                fireScript(frame, "OnUpdate")
            end
        end
        pumpBound = pumpBound - 1
    end
end

REALG.C_Timer.After = savedAfter

-- Item 2: the amortized cap. The realm table is seeded directly so the whole
-- 20000-row cost is one write pass, then the cap is crossed ten times and
-- every crossing must evict exactly the one oldest row.
local capRealm = "CapRealm"
ranksRoot[capRealm] = {}
for i = 0, MAX_CAPACITY - 1 do
    ranksRoot[capRealm]["Player-31-" .. i] = {
        guid = "Player-31-" .. i,
        name = "P" .. i,
        faction = "Horde",
        class = "WARRIOR",
        gs = 2000,
        -- Ascending timestamps: row 0 is the oldest. All ~7 days old, i.e.
        -- inside every age window used below.
        timestamp = testNow - 7 * DAY + i,
    }
end

RankDB.StoreRecord({ guid = "Player-31-J1", name = "NewOne", faction = "Alliance", class = "MAGE", gs = 9000, timestamp = testNow - 6 * DAY }, capRealm)
check(RankDB.GetRecord("Player-31-0", capRealm) == nil,
    "Stage2: crossing the cap evicts exactly the oldest timestamped row",
    "row0=" .. tostring(RankDB.GetRecord("Player-31-0", capRealm)))
check(type(RankDB.GetRecord("Player-31-1", capRealm)) == "table"
    and type(RankDB.GetRecord("Player-31-J1", capRealm)) == "table",
    "Stage2: the newest row and the rest of the realm survive the first crossing",
    ("row1=%s new=%s"):format(
        tostring(type(RankDB.GetRecord("Player-31-1", capRealm)) == "table"),
        tostring(type(RankDB.GetRecord("Player-31-J1", capRealm)) == "table")))
check(visibleCount(capRealm) == MAX_CAPACITY and countRows(capRealm) == MAX_CAPACITY,
    "Stage2: at the cap the reported count IS the visible set (exactly MAX_CAPACITY rows)",
    ("visible=%d rows=%d"):format(visibleCount(capRealm), countRows(capRealm)))

for j = 2, 10 do
    RankDB.StoreRecord({
        guid = "Player-31-J" .. j, name = "New" .. j, faction = "Alliance",
        class = "MAGE", gs = 8000 + j,
        timestamp = testNow - 6 * DAY + j,
    }, capRealm)
end
local evictShaped = {}
local goneRows = {}
for i = 0, 10 do
    evictShaped[i] = RankDB.GetRecord("Player-31-" .. i, capRealm) == nil
    if evictShaped[i] then goneRows[#goneRows + 1] = i end
end
check(#goneRows == 10 and not evictShaped[10]
    and type(RankDB.GetRecord("Player-31-J10", capRealm)) == "table",
    "Stage2: the ten oldest timestamps are exactly the rows evicted",
    ("gone=%s row10=%s new=%s"):format(
        table.concat(goneRows, ","),
        tostring(RankDB.GetRecord("Player-31-10", capRealm) ~= nil),
        tostring(RankDB.GetRecord("Player-31-J10", capRealm) ~= nil)))

-- A forward-replace must never evict the newer data: the heap still holds
-- the row's OLD timestamp, so the next crossing pops that stale candidate
-- FIRST -- it re-files with the live timestamp (a store never moves a
-- timestamp backwards, and the heap stays smallest-first, so this converges)
-- instead of evicting newer data, and the genuine next-oldest row evicts on
-- its own store. Running this BEFORE any wholesale prune is what makes the
-- re-file branch real: a prune pass tears the heap down with the table.
RankDB.StoreRecord({
    guid = "Player-31-10", name = "RebornZero", faction = "Alliance",
    class = "WARRIOR", gs = 9999,
    timestamp = testNow - 3 * DAY,      -- very non-decreasing bump of row 10
}, capRealm)
RankDB.StoreRecord({ guid = "Player-31-J11", name = "NewEleven", faction = "Alliance", class = "MAGE", gs = 8100, timestamp = testNow - 5 * DAY + 11 }, capRealm)
check(RankDB.GetRecord("Player-31-11", capRealm) == nil,
    "Stage2: the crossing after a forward-replace re-files the stale candidate and evicts the next-oldest row",
    "row11=" .. tostring(RankDB.GetRecord("Player-31-11", capRealm)))
check(type(RankDB.GetRecord("Player-31-10", capRealm)) == "table",
    "Stage2: the forward-replaced row survives the eviction of its old self",
    "row10=" .. tostring(type(RankDB.GetRecord("Player-31-10", capRealm))))

RankDB.StoreRecord({ guid = "Player-31-J12", name = "NewTwelve", faction = "Alliance", class = "MAGE", gs = 8100, timestamp = testNow - 5 * DAY + 12 }, capRealm)
check(RankDB.GetRecord("Player-31-12", capRealm) == nil,
    "Stage2: the next crossing keeps evicting the next-oldest live row in timestamp order",
    "row12=" .. tostring(RankDB.GetRecord("Player-31-12", capRealm)))
check(type(RankDB.GetRecord("Player-31-J11", capRealm)) == "table"
    and type(RankDB.GetRecord("Player-31-J12", capRealm)) == "table",
    "Stage2: the new rows of the post-replace crossings survive",
    ("J11=%s J12=%s"):format(
        tostring(type(RankDB.GetRecord("Player-31-J11", capRealm))),
        tostring(type(RankDB.GetRecord("Player-31-J12", capRealm)))))
check(visibleCount(capRealm) == MAX_CAPACITY and countRows(capRealm) == MAX_CAPACITY,
    "Stage2: the count identity holds through record replacements and re-crossings",
    ("visible=%d rows=%d"):format(visibleCount(capRealm), countRows(capRealm)))

-- Timestamp ties never seeded above, so the heap's guid-tiebreak arm
-- (heapLess) executes in production but never in the harness. One realm of
-- equal-timestamp rows pins it: the lexicographically smallest guid must
-- evict first.
local tieRealm = "TieRealm"
ranksRoot[tieRealm] = {}
for i = 0, MAX_CAPACITY - 1 do
    ranksRoot[tieRealm][("Player-32-%05d"):format(i)] = {
        guid = ("Player-32-%05d"):format(i),
        name = "T" .. i,
        faction = "Horde",
        class = "WARRIOR",
        gs = 2000,
        timestamp = testNow - 7 * DAY,
    }
end
RankDB.StoreRecord({ guid = "Player-32-New", name = "TieNew", faction = "Alliance",
    class = "MAGE", gs = 9000, timestamp = testNow - 6 * DAY }, tieRealm)
check(RankDB.GetRecord("Player-32-00000", tieRealm) == nil
    and countRows(tieRealm) == MAX_CAPACITY,
    "Stage2: a timestamp tie evicts the lexicographically smallest guid first",
    "row0=" .. tostring(RankDB.GetRecord("Player-32-00000", tieRealm)))
check(type(RankDB.GetRecord("Player-32-19999", tieRealm)) == "table",
    "Stage2: the largest guid survives a tie eviction",
    "row19999=" .. tostring(type(RankDB.GetRecord("Player-32-19999", tieRealm))))

-- Bookkeeping stays exact across the preserved prune path: PruneStaleRecords
-- of 20000 fresh rows down to 19998 evicts the two oldest and the count
-- equality must survive it.
RankDB.PruneStaleRecords(capRealm, 60, 19998)
check(visibleCount(capRealm) == 19998 and countRows(capRealm) == 19998,
    "Stage2: the count identity survives a wholesale prune pass",
    ("visible=%d rows=%d"):format(visibleCount(capRealm), countRows(capRealm)))

out(("\n-- Wire diet: versioned stride, realm/faction/class-string/spec-name OFF the wire --\n"))

-- Only Classic/Forever single-realm traffic needs the wire, and Retail alone
-- is multi-realm -- so the realm field is waste: inbound records always file
-- under the LOCAL realm. Faction is storage-only (local scans); the class
-- name and spec name are render derivations, not wire data; spec rides as a
-- numeric id, then the Stage-3 cheap fields. The versioned stride is
-- R;2;guid;name;classID;gs;ilvl;ts;specID;guild;level;pvpRank;arena.
local dietWire = RankSync.SerializeRecord({
    guid = "Player-41-R1", name = "FromElsewhere",
    classID = 7, specID = 0, gs = 4100, ilvl = 150, timestamp = testNow - 30,
})
local separators = 0
for _ in dietWire:gmatch(";") do separators = separators + 1 end
check(separators == 12,
    "Wirediet: an R record serializes as thirteen fields (twelve separators)",
    "separators=" .. tostring(separators) .. " payload=" .. tostring(dietWire))
check(dietWire == "R;2;Player-41-R1;FromElsewhere;7;4100;150;"
    .. tostring(testNow - 30) .. ";;;0;0;0",
    "Wirediet: the stride is exactly R;2;guid;name;classID;gs;ilvl;ts;specID;guild;level;pvpRank;arena",
    "payload=" .. tostring(dietWire))
local dietBack = RankSync.DeserializeRecord(dietWire)
check(type(dietBack) == "table" and dietBack.classID == 7
    and dietBack.class == "SHAMAN" and dietBack.specID == 0,
    "Wirediet: classID and (empty) specID round-trip, class token derived",
    "class=" .. tostring(dietBack and dietBack.class)
        .. " specID=" .. tostring(dietBack and dietBack.specID))

RankSync.HandlePayload(dietWire, "CHANNEL", "Sender-Other")
check(type(RankDB.GetRecord("Player-41-R1")) == "table",
    "Wirediet: an R record files under the LOCAL realm",
    "local=" .. tostring(type(RankDB.GetRecord("Player-41-R1"))))

local homeWire = RankSync.SerializeRecord({
    guid = "Player-41-P1", name = "HomeBody",
    classID = 2, gs = 3500, timestamp = testNow - 25,
})
RankSync.HandlePayload(homeWire, "GUILD", "Sender-Home")
check(type(RankDB.GetRecord("Player-41-P1")) == "table",
    "Wirediet: an R record with no realm files locally",
    "homeBody=" .. tostring(type(RankDB.GetRecord("Player-41-P1"))))

RankSync.HandlePayload("S;dig;" .. RankSync.SerializeRecord({
    guid = "Player-41-D1", name = "Digest",
    classID = 4, specID = 0,
    gs = 3001, timestamp = testNow - 40,
}), "GUILD", "Sender-Digest")
check(type(RankDB.GetRecord("Player-41-D1")) == "table",
    "Wirediet: an S response files its record locally",
    "digest=" .. tostring(type(RankDB.GetRecord("Player-41-D1"))))
check(RankDB.GetRecord("Player-41-D1")
    and RankDB.GetRecord("Player-41-D1").faction == nil,
    "Wirediet: a wire-filed row carries no faction (storage-only, local scans)",
    "faction=" .. tostring(RankDB.GetRecord("Player-41-D1")
        and RankDB.GetRecord("Player-41-D1").faction))

-- The scan-time gate: a record the client positively identifies as foreign
-- skips the store, counted for /ttgsdebug. Unresolvable units keep filing
-- (the harness defaults -- UnitTokenFromGUID nil -- must behave EXACTLY
-- like the unresolved case, or the immediate-register pin above would break).
local savedResolve = REALG.UnitTokenFromGUID
local savedSameServer = REALG.UnitIsSameServer
REALG.UnitTokenFromGUID = function() return "nameplate1" end
REALG.UnitIsSameServer = function() return false end
local gateBefore = RankSync.GetDebugState().outcomes or {}
RankSync.QueueInspectRecord({
    guid = "Player-41-F1", name = "Foreign", faction = "Horde",
    class = "WARRIOR", gs = 9999, timestamp = testNow - 5,
})
local gateAfter = RankSync.GetDebugState().outcomes or {}
check(RankDB.GetRecord("Player-41-F1") == nil,
    "Stage2: a positively-foreign scan record does not file",
    "filed=" .. tostring(type(RankDB.GetRecord("Player-41-F1")) == "table"))
check((gateAfter.scanForeignRealm or 0) > (gateBefore.scanForeignRealm or 0),
    "Stage2: the foreign-realm skip is counted for /ttgsdebug",
    ("before=%s after=%s"):format(
        tostring(gateBefore.scanForeignRealm),
        tostring(gateAfter.scanForeignRealm)))
REALG.UnitTokenFromGUID = savedResolve
REALG.UnitIsSameServer = savedSameServer

out(("\n-- Wire diet: classID/specID written, source/specIcon still dead (item 3) --\n"))

local storedDeadOK, storedDeadStatus = RankDB.StoreRecord({
    guid = "Player-51-L", name = "OldStyle", faction = "Horde",
    class = "WARRIOR", classID = 1, specName = "Fury", specID = 0,
    specIcon = "Interface\\Icons\\x", source = "syncW",
    gs = 2500, timestamp = testNow - 15,
})
check(storedDeadOK == true and storedDeadStatus == "stored",
    "Wirediet: an inbound record carrying the dead fields is still accepted",
    "status=" .. tostring(storedDeadStatus))
local storedDead = RankDB.GetRecord("Player-51-L")
check(storedDead ~= nil and storedDead.classID == 1 and storedDead.specID == 0
    and storedDead.source == nil and storedDead.specIcon == nil,
    "Wirediet: new rows write classID/specID and still drop source/specIcon",
    ("classID=%s specID=%s source=%s specIcon=%s"):format(
        tostring(storedDead and storedDead.classID),
        tostring(storedDead and storedDead.specID),
        tostring(storedDead and storedDead.source),
        tostring(storedDead and storedDead.specIcon)))

-- specID rides the wire as variable-width text, so only a cap makes the
-- validator-max row a true maximum: a giant value clamps at render width
-- instead of serializing byte-for-byte, with the 240-byte door as backstop.
local boundRec = RankDB.ValidateRecord({
    guid = "Player-51-B", name = "Bounded", class = "WARRIOR",
    gs = 2500, timestamp = testNow - 15, specID = 123456789,
})
check(boundRec ~= nil and boundRec.specID == 9999,
    "Wirediet: an unbounded specID is capped at render width (9999), never stored whole",
    "specID=" .. tostring(boundRec and boundRec.specID))

-- Pre-hygiene rows: written directly, they must keep ranking and keep their
-- dead fields -- no rewrite pass may touch them.
ranksRoot["LegacyRealm"] = {
    ["Player-51-X"] = {
        guid = "Player-51-X", name = "Veteran", faction = "Alliance",
        class = "MAGE", classID = 8, specName = "Frost",
        specIcon = "Interface\\Icons\\frost", gs = 5001, ilvl = 200,
        timestamp = testNow - DAY, source = "manual",
    },
}
local overallV, _, _, totalV = RankDB.GetPlayerRank("Player-51-X", "LegacyRealm")
check(overallV == 1 and totalV == 1,
    "Stage2: pre-hygiene rows keep ranking through the new bookkeeping",
    ("overall=%s total=%s"):format(tostring(overallV), tostring(totalV)))
local veteran = RankDB.GetRecord("Player-51-X", "LegacyRealm")
check(veteran ~= nil and veteran.classID == 8 and veteran.source == "manual",
    "Stage2: pre-hygiene rows keep their dead fields, no rewrite pass touched them",
    ("classID=%s source=%s"):format(
        tostring(veteran and veteran.classID),
        tostring(veteran and veteran.source)))
local vetBack = RankSync.DeserializeRecord(RankSync.SerializeRecord(veteran))
check(vetBack ~= nil and vetBack.classID == 8 and vetBack.class == "MAGE",
    "Wirediet: a legacy row's classID rides the wire and derives its token",
    "classID=" .. tostring(vetBack and vetBack.classID)
        .. " class=" .. tostring(vetBack and vetBack.class))

out(("\n-- Stage 2: the SAVED_VARIABLES_TOO_LARGE response (item 5) --\n"))

-- 10 days old: inside the 60-day window but past the aggressive 7-day one,
-- so ONLY the TOO_LARGE pass could take it.
RankDB.StoreRecord({ guid = "Player-61-A", name = "Aggro", faction = "Horde", class = "WARRIOR", gs = 2000, timestamp = testNow - 10 * DAY }, "AggroRealm")
fireEvent("SAVED_VARIABLES_TOO_LARGE", ADDON_NAME)
-- The key check must precede any GetRecord against the realm: getDB
-- re-creates an emptied realm key on read, so reading the row first would
-- resurrect "AggroRealm" and mask the deletion this check watches for.
check(ranksRoot["AggroRealm"] == nil,
    "Stage2: the TOO_LARGE prune deletes realms it empties",
    "key=" .. tostring(type(ranksRoot["AggroRealm"])))
check(RankDB.GetRecord("Player-61-A", "AggroRealm") == nil,
    "Stage2: SAVED_VARIABLES_TOO_LARGE prunes aggressively past its 7-day window",
    "survived=" .. tostring(RankDB.GetRecord("Player-61-A", "AggroRealm")))

RankDB.StoreRecord({ guid = "Player-61-F", name = "Kept", faction = "Horde", class = "WARRIOR", gs = 2000, timestamp = testNow - 2 * DAY }, "Aggro2Realm")
fireEvent("SAVED_VARIABLES_TOO_LARGE", ADDON_NAME)
check(type(RankDB.GetRecord("Player-61-F", "Aggro2Realm")) == "table",
    "Stage2: the TOO_LARGE prune keeps rows inside its 7-day window")

RankDB.StoreRecord({ guid = "Player-61-B", name = "NotOurProblem", faction = "Horde", class = "WARRIOR", gs = 2000, timestamp = testNow - 10 * DAY }, "Aggro3Realm")
fireEvent("SAVED_VARIABLES_TOO_LARGE", "SomeOtherAddOn")
check(type(RankDB.GetRecord("Player-61-B", "Aggro3Realm")) == "table",
    "Stage2: a TOO_LARGE event for another add-on does not prune")

RankDB.StoreRecord({ guid = "Player-61-C", name = "Again", faction = "Horde", class = "WARRIOR", gs = 2000, timestamp = testNow - 10 * DAY }, "Aggro4Realm")
RankDB.StoreRecord({ guid = "Player-61-C2", name = "AgainTwo", faction = "Horde", class = "WARRIOR", gs = 2000, timestamp = testNow - 10 * DAY }, "Aggro4Realm")
fireEvent("SAVED_VARIABLES_TOO_LARGE", ADDON_NAME)

-- The junk-realm-key arm: a non-table value under ranks is deleted outright
-- (getDB would otherwise paper it over with a fresh table until the end of
-- time). Placed before the row-absence check below on purpose: GetRecord
-- re-creates a realm key on read, so the check itself resurrects the emptied
-- Aggro4Realm key (the same trap the AggroRealm comment above names) -- and
-- a pass run after it would count that resurrection too. Here the aggressive
-- fire just deleted every realm it emptied, so the pass deletes exactly the
-- junk key.
ranksRoot["JunkRealm"] = "not-a-table"
local _, junkRealmsDeleted = RankDB.PruneAllRealms()
check(ranksRoot["JunkRealm"] == nil,
    "Stage2: PruneAllRealms deletes a non-table junk realm key",
    "key=" .. tostring(type(ranksRoot["JunkRealm"])))
check(junkRealmsDeleted == 1,
    "Stage2: the junk-key pass deletes exactly the junk key",
    "deleted=" .. tostring(junkRealmsDeleted))
check(RankDB.GetRecord("Player-61-C", "Aggro4Realm") == nil
    and RankDB.GetRecord("Player-61-C2", "Aggro4Realm") == nil,
    "Stage2: the TOO_LARGE prune is not once-per-session")

out(("\n-- Stage 3: cheap expanded fields (13-field R;2 stride) --\n"))

-- 1. The full stride round-trips every field, positional, empty-safe.
local stage3Full = {
    guid = "Player-71-F", name = "Full",
    classID = 8, specID = 577, gs = 4900, ilvl = 145,
    timestamp = testNow - 40,
    guild = "KnightsOfTheRound", level = 80, pvpRank = 11, arena = 2100,
}
local stage3Wire = RankSync.SerializeRecord(stage3Full)
local stage3Seps = 0
for _ in stage3Wire:gmatch(";") do stage3Seps = stage3Seps + 1 end
local stage3Back = RankSync.DeserializeRecord(stage3Wire)
check(stage3Seps == 12
    and type(stage3Back) == "table"
    and stage3Back.guid == "Player-71-F"
    and stage3Back.specID == 577
    and stage3Back.guild == "KnightsOfTheRound"
    and stage3Back.level == 80
    and stage3Back.pvpRank == 11
    and stage3Back.arena == 2100,
    "R2 round-trips all thirteen fields",
    "payload=" .. tostring(stage3Wire)
        .. " guild=" .. tostring(stage3Back and stage3Back.guild))
RankSync.HandlePayload(stage3Wire, "CHANNEL", "Sender-Stage3")

-- 2. Pre-release single stride: the diet "1" is refused and counted, "2" files.
local verBefore = (RankSync.GetDebugState().outcomes or {}).versionReject or 0
local dietRefused = RankSync.DeserializeRecord(
    "R;1;Player-71-O;Oldie;1;3821;124;1759000000;;;;0;0;0") == nil
local verAfter = (RankSync.GetDebugState().outcomes or {}).versionReject or 0
check(dietRefused and verAfter == verBefore + 1
    and type(RankDB.GetRecord("Player-71-F")) == "table",
    "old version is refused and counted, R2 accepted",
    "refused=" .. tostring(dietRefused)
        .. " rejects=" .. tostring(verBefore) .. "->" .. tostring(verAfter))

-- 5. Guild is the expensive field: sanitized, hard-capped at 24, and ""
-- stays "" (unguilded-or-unknown, never "Unknown"-filled).
local longGuild = "A Very Long Guild Name Indeed!!"
RankDB.StoreRecord({ guid = "Player-71-G", name = "Capped",
    class = "WARRIOR", classID = 1, gs = 2000, timestamp = testNow - 5,
    guild = longGuild })
RankDB.StoreRecord({ guid = "Player-71-E", name = "Empty",
    class = "WARRIOR", classID = 1, gs = 1999, timestamp = testNow - 5,
    guild = "" })
local cappedRow = RankDB.GetRecord("Player-71-G")
local emptyRow = RankDB.GetRecord("Player-71-E")
check(cappedRow ~= nil and cappedRow.guild == longGuild:sub(1, 24)
    and emptyRow ~= nil and emptyRow.guild == "",
    "guild truncates to 24, empty stays empty",
    "capped=" .. tostring(cappedRow and cappedRow.guild)
        .. " empty=" .. tostring(emptyRow and emptyRow.guild))

-- 7. The new fields persist through the store and prune like the rest.
RankDB.StoreRecord({ guid = "Player-71-A", name = "Aged",
    class = "MAGE", classID = 8, gs = 1500, timestamp = testNow - 61 * DAY,
    guild = "OldGuild", level = 70, pvpRank = 3, arena = 1200 })
local freshRow = RankDB.GetRecord("Player-71-F")
check(freshRow ~= nil and freshRow.guild == "KnightsOfTheRound"
    and freshRow.level == 80 and freshRow.pvpRank == 11 and freshRow.arena == 2100,
    "Stage-3 fields persist and prune like the rest",
    "guild=" .. tostring(freshRow and freshRow.guild))
RankDB.PruneStaleRecords(nil, 60, RankDB.MAX_CAPACITY or 20000)
check(RankDB.GetRecord("Player-71-A") == nil
    and type(RankDB.GetRecord("Player-71-F")) == "table",
    "Stage-3 fields persist and prune like the rest (aged row pruned, fresh survives)",
    "aged=" .. tostring(type(RankDB.GetRecord("Player-71-A"))))

-- 8. Old rows without the new fields read blanks, never noise.
local legacyClean = RankDB.ValidateRecord({
    guid = "Player-71-L", name = "Vet3", class = "MAGE",
    gs = 5001, timestamp = testNow - DAY,
})
check(legacyClean ~= nil and legacyClean.guild == ""
    and legacyClean.level == 0 and legacyClean.pvpRank == 0
    and legacyClean.arena == 0,
    "old rows without new fields read blanks",
    "guild=" .. tostring(legacyClean and legacyClean.guild))

-- 12. The stride change must not silently drop telemetry: the counted
-- buckets still enumerate after R2 traffic, and the R2-fed row is present
-- with its fields.
local dbg3 = RankSync.GetDebugState()
local dbgRow = RankDB.GetRecord("Player-71-F")
check(type(dbg3) == "table" and type(dbg3.outcomes) == "table"
    and (dbg3.outcomes.versionReject or 0) >= 1
    and dbg3.queueDepth ~= nil and dbg3.channelState ~= nil
    and dbgRow ~= nil and dbgRow.guild == "KnightsOfTheRound",
    "/ttgsdebug surfaces Stage-3-visible state",
    "versionReject=" .. tostring(dbg3.outcomes and dbg3.outcomes.versionReject))

end)
runStage2()
end

do
local runGearStorage = (function()
local RankDB = namespace.RankDB
local RankSync = namespace.RankSync
local gearScanner = namespace.Scanner
local testNow = REALG.time and REALG.time() or 1000000
local DAY = 24 * 3600

out(("\n-- Stage 4: bounded persisted gear (storage) --\n"))

-- The wire builds pairs in Scanner.REQUIRED_SLOTS order and RankDB
-- validates against its own GEAR_SLOTS copy (the browser harness loads no
-- Scanner, so the store cannot depend on the export). One canonical list:
local scannerOrder = type(gearScanner) == "table" and gearScanner.REQUIRED_SLOTS
local storeOrder = RankDB.GEAR_SLOTS
local parity = type(scannerOrder) == "table" and #scannerOrder == #storeOrder
if parity then
    for index = 1, #storeOrder do
        if scannerOrder[index] ~= storeOrder[index] then
            parity = false
            break
        end
    end
end
check(parity == true,
    "Scanner.REQUIRED_SLOTS and RankDB.GEAR_SLOTS carry one canonical order",
    "scanner=" .. tostring(scannerOrder and #scannerOrder)
        .. " store=" .. tostring(storeOrder and #storeOrder))

local function gearCount(realmKey)
    local root = REALG.TacoTipExtrasDB
    local gear = type(root) == "table" and root.gear or nil
    local db = type(gear) == "table" and gear[realmKey] or nil
    if type(db) ~= "table" then return 0 end
    local n = 0
    for _ in pairs(db) do n = n + 1 end
    return n
end

local function rankCount(realmKey)
    local root = REALG.TacoTipExtrasDB
    local ranks = type(root) == "table" and root.ranks or nil
    local db = type(ranks) == "table" and ranks[realmKey] or nil
    if type(db) ~= "table" then return 0 end
    local n = 0
    for _ in pairs(db) do n = n + 1 end
    return n
end

-- 11. Cap, local exemption, realm scoping.
local capRealm = "GearCapA"
for index = 1, 2005 do
    RankDB.StoreGear("Player-72-G" .. index, testNow - index,
        "1=" .. (100000 + index) .. ",5=" .. (200000 + index), capRealm)
end
RankDB.StoreGear(HARNESS_PLAYER_GUID, testNow - 3000, "1=777001", capRealm)
RankDB.StoreGear("Player-72-O1", testNow - 5, "1=1", "GearCapB")
RankDB.StoreGear("Player-72-O2", testNow - 6, "1=2", "GearCapB")
RankDB.StoreGear("Player-72-O3", testNow - 7, "1=3", "GearCapB")
RankDB.StoreGear("Player-72-O4", testNow - 8, "1=4", "GearCapB")
RankDB.StoreGear("Player-72-O5", testNow - 9, "1=5", "GearCapB")
RankDB.PruneAllRealms()
check(gearCount(capRealm) == 2000
    and type(RankDB.GetGear(HARNESS_PLAYER_GUID, capRealm)) == "table",
    "gear table caps at 2000, local exempt, realm-scoped",
    "count=" .. gearCount(capRealm))
check(RankDB.GetGear("Player-72-G2005", capRealm) == nil
    and RankDB.GetGear("Player-72-G2000", capRealm) == nil
    and type(RankDB.GetGear("Player-72-G1999", capRealm)) == "table",
    "gear eviction takes the oldest-t first",
    "g2005=" .. tostring(RankDB.GetGear("Player-72-G2005", capRealm))
        .. " g1999=" .. tostring(type(RankDB.GetGear("Player-72-G1999", capRealm))))
check(gearCount("GearCapB") == 5,
    "a second realm's gear is untouched by the first realm's cap",
    "other=" .. gearCount("GearCapB"))

-- 11b. The cap is enforced AT INSERT, not only at the next prune.
--
-- The gear table had a documented capacity (2,000 rows per realm) that only
-- the PRUNE pass enforced -- login, or the SAVED_VARIABLES_TOO_LARGE
-- response. Between two prunes the table grew without bound: every inbound
-- D answer added a row, so a session that received many answers could push
-- the persisted gear far past the budget the table is supposed to hold --
-- and that table is the file the client writes synchronously at logout.
--
-- The count below is read WITHOUT any prune in between, so it measures the
-- insert-time enforcement and nothing else.
local insertRealm = "GearInsertCap"
for index = 1, 2005 do
    RankDB.StoreGear("Player-73-I" .. index, testNow - index,
        "1=" .. (400000 + index), insertRealm)
end
check(gearCount(insertRealm) == RankDB.GEAR_MAX_ENTRIES,
    "the gear cap is enforced at INSERT, not only at the next prune",
    "count=" .. gearCount(insertRealm)
        .. " cap=" .. tostring(RankDB.GEAR_MAX_ENTRIES))
check(RankDB.GetGear("Player-73-I2005", insertRealm) == nil
    and type(RankDB.GetGear("Player-73-I1", insertRealm)) == "table",
    "the insert-time gear eviction takes the oldest-t first",
    "i2005=" .. tostring(RankDB.GetGear("Player-73-I2005", insertRealm))
        .. " i1=" .. tostring(type(RankDB.GetGear("Player-73-I1", insertRealm))))
-- The owner's own row is exempt from the count eviction, exactly as the
-- prune pass applies it (it is re-persisted on every own scan).
RankDB.StoreGear(HARNESS_PLAYER_GUID, testNow - 5, "1=888001", insertRealm)
check(gearCount(insertRealm) == RankDB.GEAR_MAX_ENTRIES
    and type(RankDB.GetGear(HARNESS_PLAYER_GUID, insertRealm)) == "table",
    "the insert-time gear eviction keeps the owner's own row",
    "count=" .. gearCount(insertRealm)
        .. " local=" .. tostring(type(RankDB.GetGear(HARNESS_PLAYER_GUID, insertRealm))))

-- 12. Age prune matches the rank age semantics; emptied keys are deleted.
RankDB.StoreGear("Player-72-A1", testNow - 61 * DAY, "1=11", "GearAgeA")
RankDB.StoreGear("Player-72-A2", testNow - 1 * DAY, "1=12", "GearAgeA")
RankDB.StoreGear("Player-72-B1", testNow - 61 * DAY, "1=13", "GearAgeB")
RankDB.PruneAllRealms()
check(RankDB.GetGear("Player-72-A1", "GearAgeA") == nil
    and type(RankDB.GetGear("Player-72-A2", "GearAgeA")) == "table",
    "gear age-prune matches rank age semantics",
    "stale=" .. tostring(RankDB.GetGear("Player-72-A1", "GearAgeA")))
check(type(REALG.TacoTipExtrasDB) == "table"
    and type(REALG.TacoTipExtrasDB.gear) == "table"
    and REALG.TacoTipExtrasDB.gear["GearAgeB"] == nil,
    "the age prune deletes a gear realm key the prune emptied (no orphans)",
    "key=" .. tostring(REALG.TacoTipExtrasDB
        and REALG.TacoTipExtrasDB.gear and REALG.TacoTipExtrasDB.gear["GearAgeB"]))

-- 13. The TOO_LARGE path halves gear (cap) while fresh ranks survive.
local aggroRealm = "AggroGear"
for index = 1, 1500 do
    RankDB.StoreGear("Player-72-H" .. index, testNow - 3 * DAY,
        "1=" .. (300000 + index), aggroRealm)
end
for index = 1, 100 do
    RankDB.StoreRecord({ guid = "Player-72-R" .. index, name = "HR" .. index,
        class = "WARRIOR", gs = 1000 + index, timestamp = testNow - 3 * DAY }, aggroRealm)
end
fireEvent("SAVED_VARIABLES_TOO_LARGE", ADDON_NAME)
check(gearCount(aggroRealm) == 1000,
    "gear aggressive-prune halves before ranks",
    "gear=" .. gearCount(aggroRealm))
check(rankCount(aggroRealm) == 100,
    "ranks inside the aggressive window survive the TOO_LARGE pass",
    "ranks=" .. rankCount(aggroRealm))

-- Same-t chunks of one answer carry disjoint slot sets: equal-t fills the
-- gaps instead of refusing, so reassembly is the union, never a flap.
local mergeStoredBefore = (RankSync.GetDebugState().outcomes or {}).gearStored or 0
RankSync.HandlePayload("D;2;m17;Player-72-M;500;1/2;1=111,5=555", "GUILD", "Peer-Merge")
RankSync.HandlePayload("D;2;m17;Player-72-M;500;2/2;10=1010,16=1616", "GUILD", "Peer-Merge")
local mergedGear = RankDB.GetGear("Player-72-M")
check(mergedGear ~= nil and mergedGear.ids == "1=111,5=555,10=1010,16=1616"
    and ((RankSync.GetDebugState().outcomes or {}).gearStored or 0) == mergeStoredBefore + 2,
    "same-t D chunks merge disjoint slot sets (reassembly)",
    "ids=" .. tostring(mergedGear and mergedGear.ids))

-- F1: a far-future t clamps to the rank-side now+300 bound (ValidateRecord)
-- instead of pinning the row immortal; a later honest D then overwrites it.
-- Pre-fix the far row files at testNow+100000 and the honest D reads stale.
RankDB.StoreGear("Player-72-F1", testNow + 100000, "1=111")
local farRow = RankDB.GetGear("Player-72-F1")
check(farRow ~= nil and farRow.t <= testNow + 300
    and farRow.t < testNow + 100000,
    "far-future gear t clamps to the now+300 bound",
    "t=" .. tostring(farRow and farRow.t))
local okFar = RankDB.StoreGear("Player-72-F1", testNow + 10, "1=222,5=555")
local farOver = RankDB.GetGear("Player-72-F1")
check(okFar == true and farOver ~= nil
    and farOver.ids:find("1=222", 1, true) ~= nil
    and farOver.ids:find("5=555", 1, true) ~= nil,
    "clamped far-future gear is overwritable by a later honest D",
    "ids=" .. tostring(farOver and farOver.ids))

-- F6: duplicate slots keep the FIRST, mirroring ParseGearIDs -- inputs are
-- canonical on both paths (no dupes possible), so this only pins the
-- invariant the mapGearRun alignment now shares.
local dupOrdered, dupCanon = RankDB.ParseGearIDs("1=111,1=999,5=555")
check(dupOrdered ~= nil and dupCanon == "1=111,5=555",
    "duplicate slots keep the first (ParseGearIDs first-wins)",
    "canon=" .. tostring(dupCanon))

-- F4: mixed-t interleave leaves a slot gap (no wrong data) and the next
-- answer heals it. A1 t=100 stores, B1 t=101 merges, A2 t=100 drops as
-- stale (slot 10 missing), then an equal-t 101 answer carrying the missing
-- slot fills it.
RankDB.StoreGear("Player-72-X1", 100, "1=111")
RankDB.StoreGear("Player-72-X1", 101, "5=555")
local okStaleX, statusStaleX = RankDB.StoreGear("Player-72-X1", 100, "10=1010")
local gapRow = RankDB.GetGear("Player-72-X1")
check(okStaleX == false and statusStaleX == "stale"
    and gapRow ~= nil and gapRow.ids:find("10=1010", 1, true) == nil,
    "mixed-t interleave drops the stale chunk (slot gap, never wrong data)",
    "ids=" .. tostring(gapRow and gapRow.ids))
local okHealX = RankDB.StoreGear("Player-72-X1", 101, "10=1010,1=111,5=555")
local healedRow = RankDB.GetGear("Player-72-X1")
check(okHealX == true and healedRow ~= nil
    and healedRow.ids:find("1=111", 1, true) ~= nil
    and healedRow.ids:find("5=555", 1, true) ~= nil
    and healedRow.ids:find("10=1010", 1, true) ~= nil,
    "mixed-t gap self-heals on the next answer",
    "ids=" .. tostring(healedRow and healedRow.ids))

end)
runGearStorage()
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

        -- Re-fire the driver against a freshly rebuilt tooltip and return the
        -- rank line it appended (nil when none). SetUnit rebuilds the mock and
        -- resets its line count, which is what forces the change gate to
        -- re-render even when mode is the only other thing that moved.
        local function renderRankLine()
            GameTooltipFrame:SetUnit("player")
            GameTooltipFrame:AddLine("Tester")
            GameTooltipFrame:AddLine("Level 70")
            GameTooltipFrame:Show()
            fireScript(GameTooltipFrame, "OnShow")
            local before = #GAME_TOOLTIP_ADDED
            fireScript(GameTooltipFrame, driveScript)
            for i = before + 1, #GAME_TOOLTIP_ADDED do
                local line = GAME_TOOLTIP_ADDED[i]
                if type(line) == "string" and line:find("GS Rank:", 1, true) then
                    return line
                end
            end
            return nil
        end

        -- The COMPACT form is exercised here, so the mode is set explicitly
        -- rather than inherited. The shipped default is Detailed (asserted in
        -- the saved-variables block), and a block that leaned on the default
        -- would silently stop testing Compact the moment the default moved.
        if REALG.TacoTipExtrasDB and REALG.TacoTipExtrasDB.settings
            and REALG.TacoTipExtrasDB.settings.tooltip then
            REALG.TacoTipExtrasDB.settings.tooltip.mode = "Compact"
        end

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
            if type(line) == "string" and line:find("GS Rank:", 1, true) then
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

        -- The mode is Compact here (set explicitly above), so the line above
        -- is the compact form: the short label, and the class icon standing
        -- in for the class name. The icon renders normally with no
        -- class-colour tint, and the exact seam between the coloured class
        -- rank, the icon and the white closing bracket is what proves it -- a
        -- colour code wrapped around the icon would break the "|r " prefix or
        -- the "|cffffffff]|r" suffix.
        check(rankText:find("GS Rank:", 1, true) ~= nil,
            "Tooltips:ServerRankLine uses the short GS Rank label in Compact",
            "line=" .. tostring(rankText))
        check(rankText:find("|A:classicon-WARRIOR:14:14|a", 1, true) ~= nil,
            "Tooltips:ServerRankLine draws the 14px class icon in Compact",
            "line=" .. tostring(rankText))
        check(rankText:find("|r |A:classicon-WARRIOR:14:14|a|cffffffff]|r", 1, true) ~= nil,
            "Tooltips:ServerRankLine renders the compact class icon with no class-colour tint and closes it into the white bracket",
            "line=" .. tostring(rankText))
        check(rankText:find("Warrior", 1, true) == nil,
            "Tooltips:ServerRankLine replaces the compact class name with the icon",
            "line=" .. tostring(rankText))

        -- Detailed: the only difference from Compact is the bracket content,
        -- so the class name comes back in its class colour and no icon
        -- appears. The change gate compares mode, so flipping the setting and
        -- re-firing the driver re-renders instead of skipping.
        if REALG.TacoTipExtrasDB and REALG.TacoTipExtrasDB.settings
            and REALG.TacoTipExtrasDB.settings.tooltip then
            REALG.TacoTipExtrasDB.settings.tooltip.mode = "Detailed"
        end
        local warrior = REALG.RAID_CLASS_COLORS and REALG.RAID_CLASS_COLORS.WARRIOR
        local warriorSwatch = (type(warrior) == "table"
                and type(warrior.r) == "number"
                and type(warrior.g) == "number"
                and type(warrior.b) == "number")
            and string.format("|cff%02x%02x%02xWarrior|r",
                math.floor(warrior.r * 255 + 0.5),
                math.floor(warrior.g * 255 + 0.5),
                math.floor(warrior.b * 255 + 0.5))
            or nil
        local detailedRank = renderRankLine()
        check(detailedRank ~= nil and detailedRank:find("GS Rank:", 1, true) ~= nil,
            "Tooltips:ServerRankLine uses the short GS Rank label in Detailed",
            "line=" .. tostring(detailedRank))
        check(detailedRank ~= nil and warriorSwatch ~= nil
                and detailedRank:find(warriorSwatch, 1, true) ~= nil,
            "Tooltips:ServerRankLine keeps the class name in its class colour in Detailed",
            "wanted=" .. tostring(warriorSwatch) .. " line=" .. tostring(detailedRank))
        check(detailedRank ~= nil and detailedRank:find("|A:", 1, true) == nil,
            "Tooltips:ServerRankLine adds no icon in Detailed",
            "line=" .. tostring(detailedRank))

        -- -------------------------------------------------------------------
        -- Shaman Blue: the class name in the tooltip
        -- -------------------------------------------------------------------
        --
        -- Classic Era paints the Shaman PINK. The value is the CLIENT'S own,
        -- read from the mirror rather than guessed:
        --   origin/classic_era
        --   Interface/AddOns/Blizzard_SharedXML/Vanilla/ClassColors.lua:9
        --       ["SHAMAN"] = CreateColor(0.96, 0.55, 0.73)
        -- (Classic Era loads that file: Blizzard_SharedXML_Vanilla.toc:17.)
        -- The blue is the main add-on's SHAMAN_BLUE_COLOR, and it is the
        -- TBC/Wrath Shaman colour:
        --   origin/classic_era
        --   Interface/AddOns/Blizzard_SharedXML/TBC/ClassColors.lua:9
        --       ["SHAMAN"] = CreateColor(0.0, 0.44, 0.87)
        --
        -- The Detailed-mode class NAME is the class-coloured text, so this is
        -- where the colour is visible at all.
        do
            local savedUnitClass = REALG.UnitClass
            local savedColors = REALG.RAID_CLASS_COLORS
            local savedCustom = REALG.CUSTOM_CLASS_COLORS
            local savedConfig = REALG.TacoTipConfig
            local savedShamanBlue = REALG.TacoTipConfig
                and type(REALG.TacoTipConfig.shaman_blue) == "boolean"
                and REALG.TacoTipConfig.shaman_blue or nil
            local rootSettings = REALG.TacoTipExtrasDB
                and REALG.TacoTipExtrasDB.settings or nil
            local tooltipSettings = type(rootSettings) == "table"
                and rootSettings.tooltip or nil

            REALG.RAID_CLASS_COLORS = {
                WARRIOR = { r = 1, g = 0.8, b = 0.5 },
                MAGE = { r = 0.41, g = 0.8, b = 0.94 },
                SHAMAN = { r = 0.96, g = 0.55, b = 0.73 },
            }
            REALG.CUSTOM_CLASS_COLORS = nil
            REALG.UnitClass = MOCKC.unitClassMock(function()
                return "Shaman", "SHAMAN"
            end)
            if type(tooltipSettings) == "table" then
                tooltipSettings.mode = "Detailed"
            end

            local BLUE = "|cff0070de"
            -- The pink swatch is derived from the colour the mock declares,
            -- using the SAME rounding the add-on's own colourText uses, so
            -- the expectation cannot drift from the colour it claims to be.
            local pinkEntry = REALG.RAID_CLASS_COLORS.SHAMAN
            local PINK = string.format("|cff%02x%02x%02x",
                math.floor(pinkEntry.r * 255 + 0.5),
                math.floor(pinkEntry.g * 255 + 0.5),
                math.floor(pinkEntry.b * 255 + 0.5))

            if type(rootSettings) == "table" then
                rootSettings.shamanBlue = true
            end
            local blueLine = renderRankLine()
            check(blueLine ~= nil and blueLine:find(BLUE .. "Shaman|r", 1, true) ~= nil,
                "a Shaman's class name renders blue in Detailed when Shaman Blue is on",
                "wanted=" .. BLUE .. "Shaman|r line=" .. tostring(blueLine))

            -- The setting off: the class name falls back to the client's own
            -- pink, because the client really does paint it pink.
            if type(rootSettings) == "table" then
                rootSettings.shamanBlue = false
            end
            local pinkLine = renderRankLine()
            check(pinkLine ~= nil and pinkLine:find(PINK .. "Shaman|r", 1, true) ~= nil,
                "a Shaman's class name renders the client's pink in Detailed when Shaman Blue is off",
                "wanted=" .. PINK .. "Shaman|r line=" .. tostring(pinkLine))
            check(pinkLine ~= nil and pinkLine:find(BLUE, 1, true) == nil,
                "no blue survives in the tooltip when Shaman Blue is off",
                "line=" .. tostring(pinkLine))

            -- The main add-on's setting wins: it is off, so the Extras follow
            -- and the class colour is the same in both add-ons.
            if type(rootSettings) == "table" then
                rootSettings.shamanBlue = true
            end
            if type(REALG.TacoTipConfig) == "table" then
                REALG.TacoTipConfig.shaman_blue = false
            end
            local vetoLine = renderRankLine()
            check(vetoLine ~= nil and vetoLine:find(PINK .. "Shaman|r", 1, true) ~= nil,
                "the main add-on's Shaman Blue being off wins over the Extras' own setting",
                "wanted=" .. PINK .. "Shaman|r line=" .. tostring(vetoLine))

            -- The main add-on's setting being ON does not force the Extras on:
            -- the Extras' own setting still governs, and only an explicit
            -- false in the main add-on suppresses the rule.
            if type(REALG.TacoTipConfig) == "table" then
                REALG.TacoTipConfig.shaman_blue = true
            end
            local agreeLine = renderRankLine()
            check(agreeLine ~= nil and agreeLine:find(BLUE .. "Shaman|r", 1, true) ~= nil,
                "the main add-on's Shaman Blue being on leaves the Extras' own setting in charge",
                "wanted=" .. BLUE .. "Shaman|r line=" .. tostring(agreeLine))

            -- An unreadable main value (absent, nil or a non-boolean) is not a
            -- decision: it degrades to the Extras' own setting.
            if type(rootSettings) == "table" then
                rootSettings.shamanBlue = false
            end
            if type(REALG.TacoTipConfig) == "table" then
                REALG.TacoTipConfig.shaman_blue = "not-a-boolean"
            end
            local degradedLine = renderRankLine()
            check(degradedLine ~= nil and degradedLine:find(PINK .. "Shaman|r", 1, true) ~= nil,
                "an unreadable main add-on value degrades to the Extras' own setting",
                "wanted=" .. PINK .. "Shaman|r line=" .. tostring(degradedLine))

            -- Restore everything this block moved.
            if type(rootSettings) == "table" then
                rootSettings.shamanBlue = true
            end
            if type(REALG.TacoTipConfig) == "table" then
                REALG.TacoTipConfig.shaman_blue = savedShamanBlue
            end
            REALG.UnitClass = savedUnitClass
            REALG.RAID_CLASS_COLORS = savedColors
            REALG.CUSTOM_CLASS_COLORS = savedCustom
            REALG.TacoTipConfig = savedConfig
            if type(tooltipSettings) == "table" then
                tooltipSettings.mode = "Detailed"
            end
        end

        -- Degrade: with GetClassAtlas removed the compact line must fall back
        -- to the class name -- never to an empty bracket and never to a raise.
        if REALG.TacoTipExtrasDB and REALG.TacoTipExtrasDB.settings
            and REALG.TacoTipExtrasDB.settings.tooltip then
            REALG.TacoTipExtrasDB.settings.tooltip.mode = "Compact"
        end
        local savedGetClassAtlas = REALG.GetClassAtlas
        REALG.GetClassAtlas = nil
        local degradedRank = renderRankLine()
        REALG.GetClassAtlas = savedGetClassAtlas
        check(degradedRank ~= nil and degradedRank:find("Warrior", 1, true) ~= nil,
            "Tooltips:ServerRankLine degrades to the class name when GetClassAtlas is absent",
            "line=" .. tostring(degradedRank))
        check(degradedRank ~= nil and degradedRank:find("|A:", 1, true) == nil,
            "Tooltips:ServerRankLine adds no icon when GetClassAtlas is absent",
            "line=" .. tostring(degradedRank))

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
            if type(line) == "string" and line:find("GS Rank:", 1, true) then
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

    -- The TEMPLATE TITLE, and the title band it saves.
    --
    -- The client publishes the ButtonFrame template's own title as the global
    -- "TacoTipRankFrameTitleText" (the citations are on the mock's
    -- CreateFrame). When it is there, the add-on reuses it and does NOT draw
    -- a title of its own, so the window's title band collapses to zero -- the
    -- template already owns the chrome band.
    --
    -- The mock used to publish nothing, so `hasTemplateTitle` was ALWAYS
    -- false and the 34px title band was ALWAYS paid for: the harness graded
    -- a layout the real client never produces.
    do
        local templateTitle = rawget(REALG, "TacoTipRankFrameTitleText")
        check(type(templateTitle) == "table"
                and type(templateTitle.SetText) == "function",
            "the client publishes the browser frame's template title",
            "got " .. type(templateTitle))
        local bandHeight = type(namespace.RankBrowser) == "table"
            and type(namespace.RankBrowser.GetTitleBandHeight) == "function"
            and namespace.RankBrowser.GetTitleBandHeight() or nil
        check(bandHeight == 0,
            "the title band collapses to 0 when the template provides the title",
            "band=" .. tostring(bandHeight))
        -- The template's title is the one the add-on wrote into, so the
        -- window is not left with BOTH a template title and its own.
        local expectedTitle = type(_G.TACOEXTRAS_LOCALE) == "table"
            and _G.TACOEXTRAS_LOCALE["LB_TITLE"] or nil
        check(type(templateTitle) == "table"
                and type(templateTitle.GetText) == "function"
                and expectedTitle ~= nil
                and templateTitle:GetText() == expectedTitle,
            "the template title carries the window title",
            "wanted=" .. tostring(expectedTitle) .. " got="
                .. tostring(type(templateTitle) == "table"
                    and templateTitle.GetText and templateTitle:GetText()))
    end
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

    -- The main add-on must be able to open the browser WITHOUT reaching into
    -- the client's slash registry, because that registry is a proxy that is
    -- emptied before dispatch.
    --
    -- On every supported client SlashCmdList is a PROXY table:
    --   Blizzard_ChatFrameBase/Shared/ChatFrameSetup.lua:3-4, :11
    --       setmetatable(list, { __index = {} });  AddListProxyTable(_G.SlashCmdList)
    -- and ChatFrameUtil.lua's ImportListToHash (line 717) moves every
    -- registered handler into getmetatable(list).__index (line 732) and then
    -- WIPES the real table (line 735), which happens immediately BEFORE the
    -- handler is dispatched (ChatFrameEditBox.lua:245, 257, 259). So a
    -- rawget(SlashCmdList, "TACOTIPRANKS") at dispatch time returns nil and the
    -- main add-on's "/tt" forwarding never reaches the Extras.
    --
    -- The Extras therefore publishes the SAME function on a plain global. The
    -- identity check below is the point: it is not a copy that could drift
    -- from the registered handler, it IS the registered handler.
    do
        local browser = namespace.RankBrowser
        local published = REALG.TacoTipExtrasToggleLeaderboard

        check(type(published) == "function",
            "TacoTipExtrasToggleLeaderboard is published as a callable global",
            "type=" .. type(published))

        check(type(REALG.SlashCmdList) == "table"
            and type(REALG.SlashCmdList.TACOTIPRANKS) == "function"
            and published == REALG.SlashCmdList.TACOTIPRANKS,
            "the published global is the same function the slash handler invokes")

        -- Model the client's proxy exactly: the handler lives in the
        -- metatable's __index and the real table is empty. A rawget of the
        -- proxy is nil -- which is what the main add-on used to hit -- while
        -- the published global is unaffected.
        local proxy = setmetatable({}, { __index = {} })
        if type(REALG.SlashCmdList) == "table" then
            getmetatable(proxy).__index["TACOTIPRANKS"] = REALG.SlashCmdList.TACOTIPRANKS
        end
        check(rawget(proxy, "TACOTIPRANKS") == nil,
            "model: the client's proxy table is empty at dispatch time",
            "got " .. tostring(rawget(proxy, "TACOTIPRANKS")))
        check(type(published) == "function",
            "the published global survives the proxy wipe")

        -- It must actually open the browser, not merely exist.
        local toggles = 0
        local realToggle = nil
        if type(browser) == "table" and type(browser.Toggle) == "function" then
            realToggle = browser.Toggle
            browser.Toggle = function(...)
                toggles = toggles + 1
                return realToggle(...)
            end
        end
        if type(published) == "function" then
            local ok, err = pcall(published)
            check(ok, "calling the published global does not raise", tostring(err))
            check(toggles == 1, "calling the published global opens the browser",
                "Toggle called " .. toggles .. " times")
        end
        if realToggle then
            browser.Toggle = realToggle
        end
    end
end

-- The debug snapshot must be reachable WITHOUT the client's slash registry,
-- for the same reason the leaderboard toggle is.
--
-- The main add-on owns "/tt" and the client dispatches only the FIRST
-- whitespace-delimited token (ChatFrameEditBox.lua:222 on the Classic
-- branches, :779 on live -- strmatch(text, "^(/[^%s]+)")), so "/ttgsdebug"
-- arrives at the main add-on as the argument "gsdebug" and the Extras' own
-- single-token alias is never dispatched by the client. The Extras therefore
-- publishes the SAME function on a plain global; the identity check below is
-- the point -- it is not a copy that could drift, it IS the registered
-- handler.
do
    local published = REALG.TacoTipExtrasPrintDebugSnapshot

    check(type(published) == "function",
        "TacoTipExtrasPrintDebugSnapshot is published as a callable global",
        "type=" .. type(published))

    check(type(REALG.SlashCmdList) == "table"
        and type(REALG.SlashCmdList.TTEXTRASDEBUG) == "function"
        and published == REALG.SlashCmdList.TTEXTRASDEBUG,
        "the published debug global is the same function the slash handler invokes")

    -- Model the client's proxy exactly: the handler lives in the metatable's
    -- __index and the real table is empty, so a rawget at dispatch time finds
    -- nothing while the published global is unaffected.
    local debugProxy = setmetatable({}, { __index = {} })
    if type(REALG.SlashCmdList) == "table" then
        getmetatable(debugProxy).__index["TTEXTRASDEBUG"] =
            REALG.SlashCmdList.TTEXTRASDEBUG
    end
    check(rawget(debugProxy, "TTEXTRASDEBUG") == nil,
        "model: the client's proxy table is empty at dispatch time",
        "got " .. tostring(rawget(debugProxy, "TTEXTRASDEBUG")))
    check(type(published) == "function",
        "the published debug global survives the proxy wipe")

    -- It must actually print the snapshot, not merely exist.
    local chatBefore = #CHAT
    local ok, err = pcall(published)
    check(ok, "calling the published debug global does not raise", tostring(err))
    local printed = table.concat(CHAT, "\n", chatBefore + 1)
    check(printed:find("/ttgsdebug local snapshot", 1, true) ~= nil,
        "the published debug global prints the snapshot",
        "lines=" .. tostring(#CHAT - chatBefore))
end

-- ---------------------------------------------------------------------------
-- Stage 5: tooltip freshness line (brief check 16).
--
-- Each assertion below fails on pre-Stage-5 code: GetRankExtraLines does not
-- exist, so no line can render. Placement is last (before the summary) so the
-- seeded records cannot shift any earlier pool-size assertion. The enUS-only
-- key resolves through the per-key fallback on every client, including
-- Titanforge. The retired "Gear:" depth line must not render in any state:
-- persisted gear and session revisions are stored/rendered by the gear panel,
-- never counted here.
-- ---------------------------------------------------------------------------
do
    out(("\n-- Stage 5: tooltip freshness line --\n"))
    local Tooltips5 = namespace.Tooltips
    local RankDB5 = namespace.RankDB
    check(type(Tooltips5) == "table"
        and type(Tooltips5.GetRankExtraLines) == "function",
        "freshness line renders only with data (seam exists)",
        type(Tooltips5 and Tooltips5.GetRankExtraLines))
    if type(Tooltips5) == "table"
        and type(Tooltips5.GetRankExtraLines) == "function"
        and type(RankDB5) == "table" then
        local now5 = REALG.time and REALG.time() or 1000000
        RankDB5.StoreRecord({
            guid = "Player-9-T51", name = "OldRankT",
            class = "WARRIOR", classID = 1, gs = 5000, ilvl = 150,
            timestamp = now5 - 3600,
        })
        RankDB5.StoreGear("Player-9-T51", now5 - 1800, "1=111,5=555")
        RankDB5.StoreRecord({
            guid = "Player-9-T52", name = "FreshRankT",
            class = "MAGE", classID = 8, gs = 4900, ilvl = 149,
            timestamp = now5 + 60,
        })

        -- Old rank row: freshness line present and muted; no gear line even
        -- though persisted gear exists for the guid.
        local oldLines = Tooltips5.GetRankExtraLines("Player-9-T51")
        local oldFresh, oldGear = nil, nil
        for _, line in ipairs(oldLines) do
            if type(line.text) == "string"
                and line.text:find("Rank synced", 1, true) ~= nil then
                oldFresh = line
            end
            if type(line.text) == "string"
                and line.text:find("Gear:", 1, true) ~= nil then
                oldGear = line
            end
        end
        check(oldFresh ~= nil,
            "freshness line renders only with data (old row shows freshness)",
            "lines=" .. tostring(#oldLines))
        check(oldFresh ~= nil and oldFresh.red == 0.82
            and oldFresh.green == 0.82 and oldFresh.blue == 0.82,
            "freshness line renders only with data (freshness is muted)",
            oldFresh and (tostring(oldFresh.red) .. "," .. tostring(oldFresh.green)))
        check(oldGear == nil and #oldLines == 1,
            "freshness line renders only with data (no gear line)",
            "lines=" .. tostring(#oldLines))

        -- Fresh row: no freshness line and no gear line either.
        local freshLines = Tooltips5.GetRankExtraLines("Player-9-T52")
        check(#freshLines == 0,
            "freshness line renders only with data (fresh row is silent)",
            "lines=" .. tostring(#freshLines))

        -- No rank row: nothing renders.
        local noLines = Tooltips5.GetRankExtraLines("Player-9-T5X")
        check(#noLines == 0,
            "freshness line renders only with data (no rank is silent)",
            "lines=" .. tostring(#noLines))

        -- Session revision adds no line: complete itemIDs stay panel-only.
        local revLines = Tooltips5.GetRankExtraLines("Player-9-T52", {
            slots = {
                [1] = { itemID = { status = "complete", value = 777 } },
                [2] = { itemID = { status = "complete", value = 888 } },
                [3] = { itemID = { status = "pending" } },
            },
        })
        local revGear = nil
        for _, line in ipairs(revLines) do
            if type(line.text) == "string"
                and line.text:find("Gear:", 1, true) ~= nil then
                revGear = line
            end
        end
        check(revGear == nil and #revLines == 0,
            "freshness line renders only with data (revision adds no line)",
            "n=" .. tostring(#revLines))
    end
end

-- ---------------------------------------------------------------------------
-- The level-70 gate is the USER'S SETTING, and the scorer is told so
-- ---------------------------------------------------------------------------
--
-- The bug: Scoring.Evaluate(revision, policy) took a policy, and NO production
-- call site passed one, so the scorer's own internal default ("restricted to
-- level 70") applied to every player on every client. The Options checkbox
-- only flipped the RENDER gate, so unchecking it made Potential GS / Delta /
-- Completion read "Unavailable" instead of showing a value -- and on Classic
-- Era and WoW Forever (level cap 60) the three metrics never appeared for
-- anybody at all.
--
-- Three things are pinned here:
--
--   (a) the SCORING semantics -- with the restriction OFF a level-60
--       character gets NUMERIC Potential GS / Delta / Completion; with it ON
--       the same character is still restricted;
--   (b) a NIL policy is EXPLICIT -- it no longer silently means "restricted",
--       it blocks with a named reason;
--   (c) the SCANNER passes the user's setting through, and a settings change
--       re-evaluates the CACHED REVISION (no rescan), so the cached result
--       stops answering the old setting.
--
-- Revert map:
--   - Scoring.lua, drop the nil-policy branch -> (b) goes red: the nil policy
--     silently restricts again and the reason reads "level-policy" instead of
--     "enhancement-policy-missing".
--   - Scanner.lua, pass no policy to Scoring.Evaluate -> (c) goes red: the
--     scan's metrics stay "suppressed" whatever the setting says, and the
--     policy stamp never appears.
--   - Scanner.lua, drop Scanner.Reevaluate -> (c) goes red: the cached result
--     keeps answering the old setting.
-- ---------------------------------------------------------------------------
do
out(("\n-- level-70 policy: the setting drives the scorer --\n"))
local ScoringP = namespace.Scoring
local ScannerP = namespace.Scanner
local CoreP = namespace.Core

local function pcell(value) return { status = "complete", value = value } end

-- A head with three EMPTY sockets and no enchant: the fixture that makes
-- every one of the three enhancement metrics meaningful (a missing-enchant
-- delta plus two empty socket bonuses, and a completion of 0/4).
--
-- The socket cell is COMPLETE on every client, unlike the scanning fixture
-- above: the question here is the LEVEL POLICY, not the socket capability,
-- and the socket capability would otherwise mask it on the three Classic
-- clients (where GetItemStats does not exist).
local function pLink(itemID)
    local fields = { "item", itemID, 0, 0, 0, 0 }
    for _ = 7, 20 do fields[#fields + 1] = 0 end
    return "|cffffffff|H" .. table.concat(fields, ":") .. "|h[Policy Helm]|h|r"
end
local POLICY_LINK = pLink(50004)
registerItem({ link = POLICY_LINK, quality = 4, level = 200, equipLoc = "INVTYPE_HEAD" })
local function pInfo(link)
    return { "Item", link, 4, 200, 1, "Armor", "Cloth", 1, "INVTYPE_HEAD" }
end

local function policyRevision(level)
    local revision = {
        classToken = pcell("WARRIOR"),
        level = pcell(level),
        socketCapability = pcell(true),
        slots = {},
    }
    -- The same fixed slot model the scorer scores against (17 slots, shirt
    -- and tabard excluded). Written out here because the copy in the
    -- scoring block above is local to that block.
    for _, slotID in ipairs({ 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }) do
        revision.slots[slotID] = { state = "confirmed-empty" }
    end
    revision.slots[1] = {
        state = "occupied",
        itemID = pcell(50004),
        nativeLink = pcell(POLICY_LINK),
        quality = pcell(4),
        scoringItemLevel = pcell(200),
        effectiveItemLevel = pcell(200),
        equipLoc = pcell("INVTYPE_HEAD"),
        itemClassID = pcell(4),
        itemSubclassID = pcell(1),
        permanentEnchantID = pcell(0),
        scoreGemIDs = pcell({ 0, 0, 0 }),
        sockets = pcell({ capacity = 3, gemIDs = { 0, 0, 0 } }),
        scopeCapablePhysicalRanged = pcell(false),
        itemInfoValue = pInfo(POLICY_LINK),
    }
    return revision
end

-- (a) The restriction OFF: a level-60 character gets NUMERIC metrics.
local openResult = ScoringP.Evaluate(policyRevision(60),
    { restrictEnhancementMetricsToLevel70 = false })
local function metricOf(result, name)
    local metrics = type(result) == "table" and result.metrics or nil
    return type(metrics) == "table" and metrics[name] or nil
end
local openPotential = metricOf(openResult, "potentialGS")
local openDelta = metricOf(openResult, "delta")
local openCompletion = metricOf(openResult, "completion")
check(openPotential ~= nil and openPotential.status == "complete"
    and type(openPotential.value) == "number",
    "level-70 policy: with the restriction OFF a level-60 character gets a NUMERIC Potential GS",
    "status=" .. tostring(openPotential and openPotential.status)
        .. " value=" .. tostring(openPotential and openPotential.value))
check(openDelta ~= nil and openDelta.status == "complete"
    and type(openDelta.value) == "number" and openDelta.value > 0,
    "level-70 policy: with the restriction OFF a level-60 character gets a NUMERIC Delta",
    "status=" .. tostring(openDelta and openDelta.status)
        .. " value=" .. tostring(openDelta and openDelta.value))
check(openCompletion ~= nil and openCompletion.status == "complete"
    and type(openCompletion.value) == "table"
    and type(openCompletion.value.opportunities) == "number"
    and openCompletion.value.opportunities > 0,
    "level-70 policy: with the restriction OFF a level-60 character gets a NUMERIC Completion",
    "status=" .. tostring(openCompletion and openCompletion.status)
        .. " opportunities="
        .. tostring(openCompletion and openCompletion.value
            and openCompletion.value.opportunities))

-- (a) The restriction ON: the SAME character is still restricted.
local shutResult = ScoringP.Evaluate(policyRevision(60),
    { restrictEnhancementMetricsToLevel70 = true })
for _, name in ipairs({ "potentialGS", "delta", "completion" }) do
    local metric = metricOf(shutResult, name)
    check(metric ~= nil and metric.status == "suppressed"
        and metric.reason == "level-policy",
        "level-70 policy: with the restriction ON a level-60 character is still restricted ("
            .. name .. ")",
        "status=" .. tostring(metric and metric.status)
            .. " reason=" .. tostring(metric and metric.reason))
end

-- (b) A NIL policy is explicit: it blocks with a named reason instead of
--     silently restricting, and it is NOT the level gate's own verdict.
local nilResult = ScoringP.Evaluate(policyRevision(60), nil)
for _, name in ipairs({ "potentialGS", "delta", "completion" }) do
    local metric = metricOf(nilResult, name)
    check(metric ~= nil and metric.status ~= "suppressed"
        and metric.reason == "enhancement-policy-missing",
        "level-70 policy: a nil policy is an explicit failure, not a silent restriction ("
            .. name .. ")",
        "status=" .. tostring(metric and metric.status)
            .. " reason=" .. tostring(metric and metric.reason))
end

-- (c) The scanner passes the user's setting through, and a settings change
--     re-evaluates the cached revision.
if type(ScannerP) == "table" and type(CoreP) == "table"
    and type(CoreP.GetSettings) == "function" then
    local runtimeSettings = CoreP.GetSettings()
    local tooltipSettings = type(runtimeSettings) == "table"
        and runtimeSettings.tooltip or nil
    local savedRestriction = tooltipSettings
        and tooltipSettings.restrictEnhancementMetricsToLevel70
    local savedUnitLevel = REALG.UnitLevel
    local function scanNow(scanReason)
        local generation = ScannerP.BeginGeneration(scanReason)
        return ScannerP.RunGeneration(generation)
    end
    local function currentMetrics()
        local state = ScannerP.GetCurrent()
        if type(state) ~= "table" or type(state.result) ~= "table" then
            return nil, nil
        end
        return state.result.metrics, state.result
    end

    -- A level-60 player: the character the level-70 rule exists for.
    REALG.UnitLevel = function(unit)
        return (unit == "player") and 60 or 0
    end

    -- The shipped default is ON: the level-70 rule applies.
    if tooltipSettings then
        tooltipSettings.restrictEnhancementMetricsToLevel70 = true
    end
    scanNow("policy-pin-restricted")
    local restrictedMetrics, restrictedResult = currentMetrics()
    check(restrictedMetrics ~= nil
        and restrictedMetrics.potentialGS ~= nil
        and restrictedMetrics.potentialGS.status == "suppressed",
        "level-70 policy: the scanner honours the shipped default (restricted) for a level-60 player",
        "status=" .. tostring(restrictedMetrics and restrictedMetrics.potentialGS
            and restrictedMetrics.potentialGS.status))
    check(restrictedResult ~= nil and type(restrictedResult.policy) == "table"
        and restrictedResult.policy.restrictEnhancementMetricsToLevel70 == true,
        "level-70 policy: the scan records the policy it was computed under",
        "policy=" .. tostring(restrictedResult and restrictedResult.policy
            and restrictedResult.policy.restrictEnhancementMetricsToLevel70))

    -- The user turns the restriction OFF. The CACHED result still answers the
    -- old setting, so the change is re-evaluated from the cached revision --
    -- no rescan, no re-inspection.
    if tooltipSettings then
        tooltipSettings.restrictEnhancementMetricsToLevel70 = false
    end
    local reevaluated = type(ScannerP.Reevaluate) == "function"
        and ScannerP.Reevaluate() or 0
    local openMetrics, openResultState = currentMetrics()
    check(reevaluated ~= nil and reevaluated > 0,
        "level-70 policy: a settings change re-evaluates the cached revision",
        "re-evaluated=" .. tostring(reevaluated))
    check(openMetrics ~= nil
        and openMetrics.potentialGS ~= nil
        and openMetrics.potentialGS.status ~= "suppressed",
        "level-70 policy: with the restriction OFF the cached result stops being suppressed",
        "status=" .. tostring(openMetrics and openMetrics.potentialGS
            and openMetrics.potentialGS.status))
    check(openResultState ~= nil and type(openResultState.policy) == "table"
        and openResultState.policy.restrictEnhancementMetricsToLevel70 == false,
        "level-70 policy: the re-evaluated result records the NEW policy",
        "policy=" .. tostring(openResultState and openResultState.policy
            and openResultState.policy.restrictEnhancementMetricsToLevel70))
    -- What the level rule must NOT do is block the metric. On the three
    -- Classic clients the socket capability is absent, and on the two
    -- Mainline clients the scan's socket capacity is 0 (the API publishes
    -- "EMPTY_SOCKET1".."EMPTY_SOCKET3" while Scanner.SOCKET_PREFIX is
    -- "EMPTY_SOCKET_", so no key ever matches -- a SEPARATE socket-evidence
    -- defect, out of this harness's scope), so the metric is blocked by the
    -- SOCKET evidence on every client. The point of the pin is that the
    -- reason is no longer the LEVEL rule.
    check(openMetrics ~= nil
        and openMetrics.potentialGS ~= nil
        and openMetrics.potentialGS.status ~= "suppressed"
        and openMetrics.potentialGS.reason ~= "level-policy",
        "level-70 policy: with the restriction OFF the level rule is not what blocks the metric",
        "status=" .. tostring(openMetrics and openMetrics.potentialGS
            and openMetrics.potentialGS.status)
            .. " reason=" .. tostring(openMetrics and openMetrics.potentialGS
                and openMetrics.potentialGS.reason))
    check(openMetrics ~= nil
        and openMetrics.delta ~= nil
        and openMetrics.delta.status ~= "suppressed"
        and openMetrics.delta.reason ~= "level-policy"
        and openMetrics.completion ~= nil
        and openMetrics.completion.status ~= "suppressed"
        and openMetrics.completion.reason ~= "level-policy",
        "level-70 policy: with the restriction OFF the level rule is not what blocks Delta or Completion either",
        "delta=" .. tostring(openMetrics and openMetrics.delta
            and openMetrics.delta.status)
            .. " completion=" .. tostring(openMetrics and openMetrics.completion
                and openMetrics.completion.status))

    -- The accessor the RENDER gate reads is the same one the scorer is
    -- handed: one source of truth, so the two cannot disagree.
    local policyNow = type(CoreP.GetEnhancementPolicy) == "function"
        and CoreP.GetEnhancementPolicy() or nil
    check(policyNow ~= nil
        and policyNow.restrictEnhancementMetricsToLevel70 == false,
        "level-70 policy: the accessor the render gate reads follows the setting",
        "policy=" .. tostring(policyNow
            and policyNow.restrictEnhancementMetricsToLevel70))

    -- The RENDER half: with the restriction OFF the tooltip no longer
    -- suppresses the enhancement rows for the level-60 player, and with it
    -- ON it does. The enhancement status is the tooltip's own statement of
    -- which rule applied.
    if SURFACE_ACTIVE and type(namespace.Tooltips) == "table"
        and type(namespace.Tooltips.GetEnhancementStatus) == "function" then
        -- The driver script for THIS client, named here because the copy in
        -- the tooltip section above is scoped to that block.
        local driveScript = (EXPECTED_DRIVER == "unit-hook")
            and "OnTooltipSetUnit" or "OnUpdate"
        local function renderAndStatus()
            GameTooltipFrame:SetUnit("player")
            GameTooltipFrame:AddLine("Name")
            GameTooltipFrame:Show()
            fireScript(GameTooltipFrame, "OnShow")
            fireScript(GameTooltipFrame, driveScript)
            local status, statusReason = namespace.Tooltips.GetEnhancementStatus()
            return status, statusReason
        end
        local openStatus, openReason = renderAndStatus()
        check(openStatus ~= nil and openStatus ~= "suppressed",
            "level-70 policy: with the restriction OFF the tooltip does not suppress the level-60 player",
            "status=" .. tostring(openStatus) .. " reason=" .. tostring(openReason))
        if tooltipSettings then
            tooltipSettings.restrictEnhancementMetricsToLevel70 = true
        end
        ScannerP.Reevaluate()
        local shutStatus, shutReason = renderAndStatus()
        check(shutStatus == "suppressed" and shutReason == "level-policy",
            "level-70 policy: with the restriction ON the tooltip suppresses the level-60 player",
            "status=" .. tostring(shutStatus) .. " reason=" .. tostring(shutReason))
    else
        out("   (the adapter refused this run, so the tooltip render half does not apply)\n")
    end

    -- Restore: the shipped default, the mock level, and a scan under them, so
    -- nothing downstream sees a level-60 player or a flipped setting.
    if tooltipSettings then
        tooltipSettings.restrictEnhancementMetricsToLevel70 = savedRestriction
    end
    REALG.UnitLevel = savedUnitLevel
    scanNow("policy-pin-restored")
    local restoredMetrics, restoredResult = currentMetrics()
    check(savedRestriction == true
        and restoredResult ~= nil
        and type(restoredResult.policy) == "table"
        and restoredResult.policy.restrictEnhancementMetricsToLevel70 == true,
        "level-70 policy: the restored default is what the next scan is computed under",
        "restriction=" .. tostring(savedRestriction)
            .. " policy=" .. tostring(restoredResult and restoredResult.policy
                and restoredResult.policy.restrictEnhancementMetricsToLevel70))
    check(restoredMetrics ~= nil
        and restoredMetrics.potentialGS ~= nil
        and restoredMetrics.potentialGS.status ~= "suppressed",
        "level-70 policy: the restored level-70 player is not restricted",
        "status=" .. tostring(restoredMetrics and restoredMetrics.potentialGS
            and restoredMetrics.potentialGS.status))
else
    check(false,
        "level-70 policy: the scanner and the settings owner are both present",
        "scanner=" .. type(ScannerP) .. " core=" .. type(CoreP))
end
end

-- ---------------------------------------------------------------------------
-- The recovery journal survives a TacoTip upgrade
-- ---------------------------------------------------------------------------
--
-- The bug: the journal's identity WAS the capability fingerprint, and the
-- fingerprint includes the TacoTip version. So upgrading TacoTip changed the
-- fingerprint, the journal on disk stopped matching, and the adapter latched
-- a conflict that was never cleared -- `conflictLocked` was set in five
-- places and reset in none. /reload does not fire PLAYER_LOGOUT, so the
-- journal stayed on disk and the Extras tooltip surface stayed dead across
-- every reload -- and the main add-on's show_gs_player (which Extras had
-- forced to false) was never restored.
--
-- Two halves are pinned:
--
--   (a) a stale journal + a changed TacoTip version -> the takeover is
--       re-acquired and the forced setting is RESTORED;
--   (b) a journal whose forced value no longer matches -> no restore: the
--       user's own change wins, and the takeover is refused.
--
-- Revert map: put the fingerprint back into the identity check in
-- TacoTipAdapter.lua -> (a) goes red (the takeover is refused and the setting
-- stays forced). Drop the restorative branch -> (b) goes red (the user's
-- change is overwritten).
-- ---------------------------------------------------------------------------
do
out(("\n-- recovery journal: an upgrade does not lock the takeover --\n"))
local Adapter2 = namespace.TacoTipAdapter
local db2 = _G.TacoTipExtrasDB
local config2 = _G.TacoTipConfig

if type(Adapter2) ~= "table" or type(db2) ~= "table"
    or type(config2) ~= "table" then
    check(false,
        "recovery journal: the adapter, the database and the config are all present",
        "adapter=" .. type(Adapter2) .. " db=" .. type(db2)
            .. " config=" .. type(config2))
elseif not (type(Adapter2.GetCompatibility) == "function"
    and (Adapter2.GetCompatibility())) then
    -- This run's adapter REFUSES TacoTip (an old TacoTip, or an inspector
    -- missing a capability), so there is no takeover to recover: the
    -- recovery correctly refuses with "recovery-compatibility-unsupported".
    -- The pin does not apply to a run with no takeover.
    out("   (this run's adapter refuses TacoTip, so the recovery pin does not apply)\n")
else
    -- Release the live lease first, so the adapter is in the state a fresh
    -- session starts in: no lease, and whatever the journal on disk says.
    Adapter2.SetTooltipSurfaceEnabled(false)
    local savedMetadata = type(REALG.C_AddOns) == "table"
        and REALG.C_AddOns.GetAddOnMetadata or nil
    local chatBefore = #CHAT

    -- The journal a session that ended without PLAYER_LOGOUT leaves behind:
    -- the takeover was running, so the setting it forced is still forced.
    --
    -- The original value is a parameter, because the "no restore" half has
    -- to be able to tell a restore from a no-restore: with the original
    -- value DIFFERENT from the value the user set, a restore is visible.
    local function staleJournal(originalValue)
        db2.tacoTipRecovery = {
            surface = "tooltip",
            fingerprint = "tacotip|0.8.0|min-ver|0.8.0|surface|tooltip|OLD-BUILD",
            entries = {
                show_gs_player = {
                    originalValue = originalValue,
                    forcedValue = false,
                    owningSurface = "tooltip",
                    owned = true,
                },
            },
        }
    end

    -- (a) A stale journal and an UPGRADED TacoTip.
    staleJournal(true)
    config2.show_gs_player = false
    if type(REALG.C_AddOns) == "table" then
        REALG.C_AddOns.GetAddOnMetadata = function(name, field)
            if name == TT_GLOBAL and field == "Version" then
                return "0.9.0"
            end
            if name == TT_GLOBAL and field == "Title" then
                return "TacoTip"
            end
            return nil
        end
    end
    local initOK = Adapter2.Initialize(db2)
    local restored = config2.show_gs_player
    local journalCleared = db2.tacoTipRecovery == nil
    local reacquired = Adapter2.SetTooltipSurfaceEnabled(true)
    check(initOK == true,
        "recovery journal: the adapter initialises against a stale journal",
        tostring(initOK))
    check(restored == true,
        "recovery journal: a stale journal + an upgraded TacoTip RESTORES the forced setting",
        "show_gs_player=" .. tostring(restored))
    check(journalCleared,
        "recovery journal: the stale journal is cleared once it has been acted on",
        "journal=" .. tostring(db2.tacoTipRecovery))
    check(reacquired == true,
        "recovery journal: the takeover is re-acquired after an upgrade",
        "re-acquired=" .. tostring(reacquired))

    -- (b) A journal whose forced value no longer matches: the user changed
    --     the setting themselves, so their change wins.
    Adapter2.SetTooltipSurfaceEnabled(false)
    -- The record's original value is FALSE here and the user has set the
    -- setting to TRUE, so a restore would be visible as a change.
    staleJournal(false)
    config2.show_gs_player = true
    Adapter2.Initialize(db2)
    local kept = config2.show_gs_player
    local refused = Adapter2.SetTooltipSurfaceEnabled(true)
    check(kept == true,
        "recovery journal: a journal whose forced value no longer matches does NOT restore",
        "show_gs_player=" .. tostring(kept))
    check(refused == false,
        "recovery journal: the user's own change wins -- the takeover is refused",
        "re-acquired=" .. tostring(refused))

    -- The refusal is never silent: the reason is stated in chat, once.
    local newChat = 0
    local mentionsExtras = false
    for index = chatBefore + 1, #CHAT do
        newChat = newChat + 1
        if type(CHAT[index]) == "string"
            and CHAT[index]:find("TacoTip Extras", 1, true) ~= nil then
            mentionsExtras = true
        end
    end
    check(newChat >= 1 and mentionsExtras,
        "recovery journal: the conflict is stated in chat, so the state is never silent",
        "chat lines=" .. tostring(newChat) .. " mentions=" .. tostring(mentionsExtras))
    local chatAfterFirst = #CHAT
    Adapter2.Initialize(db2)
    check(#CHAT == chatAfterFirst,
        "recovery journal: the reason is stated ONCE, not on every read",
        "chat lines " .. tostring(chatAfterFirst) .. " -> " .. tostring(#CHAT))

    -- Restore: the version the harness reports, the journal, the setting and
    -- the surface, so nothing downstream sees the pin's state.
    if type(REALG.C_AddOns) == "table" and savedMetadata then
        REALG.C_AddOns.GetAddOnMetadata = savedMetadata
    end
    db2.tacoTipRecovery = nil
    config2.show_gs_player = true
    Adapter2.Initialize(db2)
    Adapter2.SetTooltipSurfaceEnabled(true)
end
end

-- ---------------------------------------------------------------------------
-- The inbound flood door: a burst stops spawning timers
-- ---------------------------------------------------------------------------
--
-- A query is a broadcast: every client on the channel hears it and answers
-- it through a jittered C_Timer -- one timer per inbound payload. There was
-- no bound on that, so a flood of Q and G payloads spawned a timer per
-- payload, with nothing downstream but the send queue's own 50-message cap
-- (which bounds the MESSAGES, not the TIMERS).
--
-- The pin drives a burst and reads two things: how many timers were
-- scheduled, and how many refusals the debug state counts. A door that did
-- not exist would schedule one timer per payload and count nothing.
--
-- Revert map: remove the inboundWindowAllows() calls in RankSync.lua -> the
-- timer count goes back to one per payload and the refusal counter stays
-- still.
-- ---------------------------------------------------------------------------
do
out(("\n-- inbound flood door: a burst of queries stops spawning timers --\n"))
local RankSync4 = namespace.RankSync
if type(RankSync4) ~= "table"
    or type(RankSync4.HandlePayload) ~= "function"
    or type(RankSync4.GetDebugState) ~= "function" then
    check(false, "the inbound flood door: RankSync is present", type(RankSync4))
else
    local savedGetTime = REALG.GetTime
    local savedTimer = REALG.C_Timer
    local spawned = 0
    -- A clock, so the window is measurable. (A client with no clock has no
    -- measurable window, so the door stays inert -- the same fail-open
    -- convention every other clock-gated gate in this file follows.)
    --
    -- The clock is set well past every clock the sections above used, so
    -- the window is guaranteed to start empty for this burst rather than
    -- carrying the earlier traffic's count.
    REALG.GetTime = function() return 1000000 end
    REALG.C_Timer = {
        After = function() spawned = spawned + 1 end,
    }
    local limit = RankSync4.INBOUND_WINDOW_MAX or 0
    local burst = limit + 20
    local before = (RankSync4.GetDebugState().outcomes or {}).inboundRateLimited or 0
    for index = 1, burst do
        RankSync4.HandlePayload("Q;burst" .. index, "GUILD", "Flooder")
    end
    local after = (RankSync4.GetDebugState().outcomes or {}).inboundRateLimited or 0
    check(spawned == limit,
        "a burst of inbound queries stops spawning timers past the limit",
        "spawned=" .. tostring(spawned) .. " limit=" .. tostring(limit))
    check(after == before + (burst - limit),
        "the inbound rate limit counts its refusals in the debug state",
        "before=" .. tostring(before) .. " after=" .. tostring(after))
    -- The gear query path is behind the same door.
    local spawnedBeforeGear = spawned
    RankSync4.HandlePayload("G;2;burstg;" .. HARNESS_PLAYER_GUID,
        "GUILD", "Flooder")
    check(spawned == spawnedBeforeGear,
        "a gear query past the limit spawns no timer either",
        "spawned=" .. tostring(spawned))
    REALG.GetTime = savedGetTime
    REALG.C_Timer = savedTimer
end
end

-- ---------------------------------------------------------------------------
-- The bundled inspector does not displace a real LibClassicInspector
-- ---------------------------------------------------------------------------
--
-- The bundled inspector publishes an ALIAS under the name the original
-- library used: "LibClassicInspector". Writing that alias unconditionally
-- DISPLACES a real LibClassicInspector that another add-on already
-- registered, and relabels the minor recorded for it -- a silent downgrade
-- of a shared namespace the bundled file does not own. A caller that then
-- asks LibStub for "LibClassicInspector" gets the port at minor 2 instead of
-- the library it expected, with nothing to say so.
--
-- The REAL bundled file is loaded here, in a sandboxed environment (so the
-- harness's own globals are untouched), against a LibStub that already holds
-- a LibClassicInspector.
--
-- Revert map: make the alias registration unconditional again in
-- Libs/LibForeverInspector/LibForeverInspector.lua -> the pre-existing
-- library is displaced and its minor is downgraded.
-- ---------------------------------------------------------------------------
do
out(("\n-- bundled inspector: the shared alias is not taken by force --\n"))

-- Load a file in a sandboxed environment. Lua 5.1 and LuaJIT have setfenv;
-- 5.2+ have load's environment argument. Both are needed: the harness runs
-- on all three.
local function loadInSandbox(path, env)
    if setfenv then
        local chunk = assert(loadfile(path))
        setfenv(chunk, env)
        return chunk
    end
    local fh = assert(io.open(path, "r"))
    local source = fh:read("*a")
    fh:close()
    return assert(load(source, "@" .. path, "t", env))
end

-- A LibStub with the shape the bundled library expects, and a
-- CallbackHandler-1.0 it can register itself with.
local function newLibStub()
    local stub = { libs = {}, minors = {} }
    function stub:NewLibrary(major, minor)
        local oldminor = self.minors[major]
        if oldminor and oldminor >= minor then return nil end
        self.minors[major], self.libs[major] = minor, self.libs[major] or {}
        return self.libs[major], oldminor
    end
    function stub:GetLibrary(major, silent)
        if not self.libs[major] and not silent then
            error("Cannot find a library instance of " .. tostring(major) .. ".", 2)
        end
        return self.libs[major], self.minors[major]
    end
    setmetatable(stub, {
        __call = function(self, major) return self:GetLibrary(major, true) end,
    })
    stub.libs["CallbackHandler-1.0"] = {
        New = function(_, target) return { target = target } end,
    }
    stub.minors["CallbackHandler-1.0"] = 1
    return stub
end

-- The sandbox the bundled library loads into: the minimum it reads at load
-- time, and nothing else.
local function newSandbox(stub)
    local env = {}
    env._G = env
    env.LibStub = stub
    env.CreateFrame = function()
        return {
            RegisterEvent = function() end,
            UnregisterEvent = function() end,
            SetScript = function() end,
            Show = function() end,
            Hide = function() end,
            IsShown = function() return false end,
            GetName = function() return nil end,
        }
    end
    env.GetTime = function() return 1000 end
    env.C_Timer = {
        After = function() end,
        NewTicker = function() return { Cancel = function() end } end,
    }
    env.GetBuildInfo = function()
        return "1.15.9", "70000", "d", 11509, "us", "rel"
    end
    env.GetLocale = function() return "enUS" end
    env.UnitIsPlayer = function() return false end
    env.UnitGUID = function() return nil end
    env.UnitExists = function() return false end
    env.CanInspect = function() return false end
    env.NotifyInspect = function() end
    env.InCombatLockdown = function() return false end
    env.GetItemInfo = function() end
    env.C_Item = { GetInventoryItemLink = function() end }
    env.C_PlayerInfo = { GUIDIsPlayer = function() return false end }
    env.GetSpecializationInfoByID = function() return nil end
    env.hooksecurefunc = function() end
    env.geterrorhandler = function() return function() end end
    env.print = function() end
    for key, value in pairs({
        os = os, string = string, table = table, math = math,
        pairs = pairs, ipairs = ipairs, type = type, tostring = tostring,
        tonumber = tonumber, pcall = pcall, select = select,
        setmetatable = setmetatable, rawget = rawget, rawset = rawset,
        error = error, assert = assert, next = next, xpcall = xpcall,
        unpack = unpack or table.unpack,
    }) do
        env[key] = value
    end
    return env
end

local INSPECTOR_PATH = ROOT .. "/../Libs/LibForeverInspector/LibForeverInspector.lua"
local inspectorFH = io.open(INSPECTOR_PATH, "r")
if inspectorFH then
    inspectorFH:close()
else
    check(false,
        "the bundled inspector file is where the harness expects it",
        "missing: " .. tostring(INSPECTOR_PATH))
end

-- (a) A pre-existing LibClassicInspector: the bundled alias must not
--     displace it, and must not downgrade the minor recorded for it.
local stubA = newLibStub()
local preExisting = { marker = "the real LibClassicInspector" }
stubA.libs["LibClassicInspector"] = preExisting
stubA.minors["LibClassicInspector"] = 18
local envA = newSandbox(stubA)
envA.LibClassicInspector = preExisting
local loadedA, loadErrA = pcall(function()
    loadInSandbox(INSPECTOR_PATH, envA)("TacoTip")
end)
check(loadedA == true,
    "the bundled inspector loads in a sandbox",
    tostring(loadErrA))
check(stubA.libs["LibClassicInspector"] == preExisting,
    "a pre-existing LibClassicInspector is NOT displaced by the bundled alias",
    "entry=" .. tostring(stubA.libs["LibClassicInspector"]))
check(stubA.minors["LibClassicInspector"] == 18,
    "the pre-existing LibClassicInspector's minor is NOT downgraded",
    "minor=" .. tostring(stubA.minors["LibClassicInspector"]))
check(stubA.libs["LibForeverInspector"] ~= nil,
    "the bundled inspector still registers under its OWN name",
    "entry=" .. tostring(stubA.libs["LibForeverInspector"]))

-- (b) The name free: the alias IS published, so the convenience the alias
--     exists for still works.
local stubB = newLibStub()
local envB = newSandbox(stubB)
local loadedB, loadErrB = pcall(function()
    loadInSandbox(INSPECTOR_PATH, envB)("TacoTip")
end)
check(loadedB == true,
    "the bundled inspector loads in a sandbox with the name free",
    tostring(loadErrB))
check(stubB.libs["LibClassicInspector"] == stubB.libs["LibForeverInspector"]
    and stubB.libs["LibClassicInspector"] ~= nil,
    "the alias is published when the name is free",
    "alias=" .. tostring(stubB.libs["LibClassicInspector"]))
check(stubB.minors["LibClassicInspector"] == 2,
    "the published alias carries the library's own minor",
    "minor=" .. tostring(stubB.minors["LibClassicInspector"]))
end

-- ---------------------------------------------------------------------------
-- Final silent-failure audit (2026-10-20): the nine findings, pinned
-- ---------------------------------------------------------------------------
--
-- Each block below pins ONE finding of the final silent-failure audit, and
-- each pin is written so that REVERTING the fix makes it go red. The
-- reverting was done on COPIES, never in this tree; the quoted reds are in
-- the desk journal.

out("\n-- final silent-failure audit --\n")

-- ---------------------------------------------------------------------------
-- Item 2: a raising scorer is counted and surfaced (Scanner.Reevaluate)
-- ---------------------------------------------------------------------------
--
-- The re-evaluation runs the scorer over the cached revision. A scorer that
-- raises used to leave the cached verdict -- computed under the OLD policy --
-- exactly where it was, and the caller discarded even the pcall's boolean:
-- the checkbox flipped, the setting was written, the metrics kept the old
-- verdict, and nothing said so.
--
-- The scorer is replaced in place (Scanner holds the Scoring TABLE, so
-- replacing the field is replacing what the scanner calls).
do
    local scanner = namespace.Scanner
    local scoring = namespace.Scoring
    if type(scanner) == "table" and type(scanner.Reevaluate) == "function"
        and type(scoring) == "table" and type(scoring.Evaluate) == "function" then
        local before = scanner.GetDebugState()
        local chatBefore = #CHAT
        local savedEvaluate = scoring.Evaluate
        scoring.Evaluate = function()
            error("synthetic scorer raise")
        end
        local callOK, replaced, failed = pcall(scanner.Reevaluate)
        scoring.Evaluate = savedEvaluate
        local after = scanner.GetDebugState()

        check(callOK == true,
            "a raising scorer does not take the re-evaluation down with it",
            tostring(replaced))
        check(type(after.reevaluateErrors) == "number"
            and type(before.reevaluateErrors) == "number"
            and after.reevaluateErrors > before.reevaluateErrors,
            "a raising scorer is COUNTED",
            "before=" .. tostring(before.reevaluateErrors)
                .. " after=" .. tostring(after.reevaluateErrors))
        check(type(after.lastReevaluateError) == "string"
            and after.lastReevaluateError:find("synthetic scorer raise", 1, true) ~= nil,
            "the counted failure NAMES the failure",
            "last=" .. tostring(after.lastReevaluateError))
        check(type(failed) == "number" and failed >= 1,
            "the caller is told the re-evaluation failed (the result is not discarded)",
            "failed=" .. tostring(failed))
        local reported = table.concat(CHAT, "\n", chatBefore + 1)
        check(reported:find("score re-evaluation failed", 1, true) ~= nil,
            "a raising scorer is SURFACED: one line names the failure",
            "lines=" .. tostring(reported):sub(1, 200))
    end
end

-- ---------------------------------------------------------------------------
-- Item 2 (cont.): the counter reaches /ttgsdebug
-- ---------------------------------------------------------------------------
--
-- A counter no user can see is a counter that cannot be acted on -- that is
-- the whole reason the surfaces block exists.
do
    local chatBefore = #CHAT
    local ok = pcall(REALG.SlashCmdList.TTEXTRASDEBUG)
    local printed = table.concat(CHAT, "\n", chatBefore + 1)
    check(ok == true, "/ttgsdebug still runs", "")
    check(printed:find("scanner-reevaluate-errors=", 1, true) ~= nil,
        "/ttgsdebug prints the re-evaluation failure counter",
        printed:sub(1, 300))
end

-- ---------------------------------------------------------------------------
-- Item 4: the tooltip-mode dropdown reads in the player's language
-- ---------------------------------------------------------------------------
--
-- The dropdown carried the English literals in EVERY language. It is the one
-- control the player reads the mode from, so it is checked in a non-English
-- locale: both the CLOSED control's label and the MENU items behind it.
do
    local options = namespace.Options
    local dropdown = REALG.TacoTip_ExtrasTooltipModeDropdown
    if type(options) == "table" and type(options.Refresh) == "function"
        and type(dropdown) == "table" then
        local savedOverride = REALG.TacoTipConfig.locale_override
        local core = namespace.Core
        local tooltip = type(core.GetSettings) == "function"
            and core.GetSettings().tooltip or nil
        local savedMode = type(tooltip) == "table" and tooltip.mode or nil
        -- The dropdown shows the mode in EFFECT, so the mode is pinned to a
        -- known one for the check and restored afterwards.
        if type(tooltip) == "table" then
            tooltip.mode = "Detailed"
        end
        REALG.TacoTipConfig.locale_override = "ruRU"
        REALG.TacoExtrasApplyLocale()
        options.Refresh()

        local russian = EX["ruRU"]["MODE_DETAILED"]
        local english = EX["enUS"]["MODE_DETAILED"]
        check(type(russian) == "string" and russian ~= english,
            "the Russian locale carries its own word for the Detailed mode",
            "ru=" .. tostring(russian))
        check(DROPDOWN_TEXT[dropdown] == russian,
            "the tooltip-mode control labels itself in the player's language",
            "showed " .. tostring(DROPDOWN_TEXT[dropdown]))

        -- The MENU behind the control: the initializer builds it, and the
        -- items are read back.
        local items = {}
        local savedAdd = REALG.UIDropDownMenu_AddButton
        REALG.UIDropDownMenu_AddButton = function(info)
            items[#items + 1] = info
        end
        local initializer = DROPDOWN_INITIALIZER[dropdown]
        if type(initializer) == "function" then
            pcall(initializer, dropdown)
        end
        REALG.UIDropDownMenu_AddButton = savedAdd

        local labels = {}
        for _, item in ipairs(items) do
            labels[#labels + 1] = tostring(item and item.text)
        end
        local detailed = nil
        local untranslatedItems = {}
        for _, item in ipairs(items) do
            if item and item.value == "Detailed" then
                detailed = item.text
            end
            -- EVERY item is checked, not just the one in effect: a menu that
            -- translates three of its four words is still an English menu.
            if item and type(item.value) == "string" and type(item.text) == "string" then
                local key = "MODE_" .. string.upper(item.value)
                local expected = EX["ruRU"][key]
                if type(expected) == "string" and item.text ~= expected then
                    untranslatedItems[#untranslatedItems + 1] = item.value .. "=" .. item.text
                end
            end
        end
        check(#items >= 4,
            "the tooltip-mode menu builds its four choices",
            "items=" .. tostring(#items))
        check(detailed == russian,
            "the tooltip-mode MENU is in the player's language",
            "items=" .. table.concat(labels, " | "))
        check(#untranslatedItems == 0,
            "every tooltip-mode menu item is in the player's language",
            table.concat(untranslatedItems, " | "))

        if type(tooltip) == "table" then
            tooltip.mode = savedMode
        end
        REALG.TacoTipConfig.locale_override = savedOverride
        REALG.TacoExtrasApplyLocale()
        options.Refresh()
    end
end

-- ---------------------------------------------------------------------------
-- Item 5: the two leaderboard keys are localized in every shipped locale
-- ---------------------------------------------------------------------------
--
-- LB_COL_LEVEL (the LEVEL column header) and LB_STAT_STRIP (the summary
-- strip) are read by the live UI in every locale, and ten of the eleven
-- locale files did not define them, so those two surfaces read English
-- everywhere except enUS.
do
    local required = { "LB_COL_LEVEL", "LB_STAT_STRIP" }
    local missing, blank, copied = {}, {}, {}
    for index = 1, #registered do
        local code = registered[index]
        local locale = EX[code]
        for _, key in ipairs(required) do
            local value = locale and locale[key]
            if value == nil then
                missing[#missing + 1] = code .. ":" .. key
            elseif type(value) ~= "string" or value == "" then
                blank[#blank + 1] = code .. ":" .. key
            elseif code ~= "enUS" and value == EX["enUS"][key] then
                -- The repo rule: a translated locale may not carry the English
                -- string. A copied English string is non-empty and has the
                -- right key, so the two checks above cannot see it.
                copied[#copied + 1] = code .. ":" .. key
            end
        end
    end
    check(#missing == 0,
        "every shipped locale defines the leaderboard level column and the summary strip",
        table.concat(missing, ", "))
    check(#blank == 0,
        "every shipped locale gives the leaderboard level column and the summary strip a value",
        table.concat(blank, ", "))
    check(#copied == 0,
        "no translated locale carries the English leaderboard level column or summary strip",
        table.concat(copied, ", "))

    -- The summary strip is a FORMAT string: three numbers. A translation that
    -- drops one renders "Top 0" with no pool size, and the specifier-sequence
    -- check above would already have caught it -- but the rendered form is
    -- asserted here too, because it is the form the player reads.
    --
    -- Guarded: a MISSING key must fail the check above, not abort the suite
    -- here with a raise.
    local ruStripValue = EX["ruRU"]["LB_STAT_STRIP"]
    local ruStrip = type(ruStripValue) == "string"
        and string.format(ruStripValue, 12, 900, 640) or ""
    check(ruStrip:find("12", 1, true) ~= nil
        and ruStrip:find("900", 1, true) ~= nil
        and ruStrip:find("640", 1, true) ~= nil,
        "the Russian summary strip renders the three numbers it is given",
        ruStrip)
end

-- ---------------------------------------------------------------------------
-- Item 6: the checkbox hit rect is re-measured on refresh
-- ---------------------------------------------------------------------------
--
-- The expansion was measured ONCE, at creation, from GetStringWidth(). Two
-- things invalidated it: a FontString measured before its font is loaded
-- measures ZERO (so the label stops being clickable), and a locale change
-- rewrites the label's text in place (so the measurement is stale).
--
-- The pin changes the label's WORDS -- through the locale, the way a
-- language change does -- and asserts that the measured expansion follows.
do
    local options = namespace.Options
    local control = REALG.TacoTip_ExtrasOptionGearScore
    if type(options) == "table" and type(options.Refresh) == "function"
        and type(control) == "table" then
        local function expansionOf(widget)
            local insets = rawget(widget, "__hitInsets") or {}
            return -(insets.right or 0)
        end
        local savedHeading = XL["HELP_GEARSCORE_HEADING"]
        options.Refresh()
        local before = expansionOf(control)
        local label = rawget(control, "optionLabel")
        local textBefore = type(label) == "table" and label:GetText() or nil

        XL["HELP_GEARSCORE_HEADING"] =
            "Show Current GS with a deliberately much longer label than the one before"
        options.Refresh()
        local after = expansionOf(control)
        local textAfter = type(label) == "table" and label:GetText() or nil

        XL["HELP_GEARSCORE_HEADING"] = savedHeading
        options.Refresh()

        check(type(textAfter) == "string" and textAfter ~= textBefore,
            "a refresh re-reads the checkbox label from the locale",
            "before=" .. tostring(textBefore) .. " after=" .. tostring(textAfter))
        check(type(after) == "number" and type(before) == "number"
            and after ~= before,
            "the hit-rect expansion is RECOMPUTED on refresh (it follows the label)",
            "before=" .. tostring(before) .. " after=" .. tostring(after))
        check(type(after) == "number" and after > 0,
            "the recomputed expansion is not zero (the label stays clickable)",
            "after=" .. tostring(after))
        -- The expansion may never reach the next column: the left column's
        -- controls stop at x=290.
        check(type(after) == "number" and after <= 290 - 16 - 26 - 2,
            "the recomputed expansion still stops inside the label's column",
            "after=" .. tostring(after))
    end
end

-- ---------------------------------------------------------------------------
-- Item 7: an action button whose module is missing says so
-- ---------------------------------------------------------------------------
--
-- Both buttons used to guard their call and RETURN, in silence: the player
-- clicked and nothing happened, with no word anywhere.
do
    local browser = namespace.RankBrowser
    local leaderboardButton = REALG.TacoTip_ExtrasOpenLeaderboardButton
    local scanButton = REALG.TacoTip_ExtrasScanNowButton
    if type(browser) == "table" and type(leaderboardButton) == "table"
        and type(scanButton) == "table" then
        namespace.RankBrowser = {}
        local chatBefore = #CHAT
        local okA = pcall(function()
            leaderboardButton.__script_OnClick(leaderboardButton)
        end)
        local okB = pcall(function()
            scanButton.__script_OnClick(scanButton)
        end)
        namespace.RankBrowser = browser
        local printed = table.concat(CHAT, "\n", chatBefore + 1)

        check(okA == true and okB == true,
            "the action buttons survive a missing module", "")
        check(printed:find("RankBrowser.Toggle is missing", 1, true) ~= nil,
            "a missing leaderboard module produces a message naming the missing surface",
            printed:sub(1, 300))
        check(printed:find("RankBrowser.StartScan is missing", 1, true) ~= nil,
            "a missing scan module produces a message naming the missing surface",
            printed:sub(1, 300))
    end
end

-- ---------------------------------------------------------------------------
-- Item 9: unticking every field and ticking one back restores a usable mode
-- ---------------------------------------------------------------------------
--
-- The mode was forced to "Disabled" on EVERY normalise and nothing
-- remembered what it had been, so re-ticking one field left the mode
-- "Disabled" and the tooltip showed nothing until the player picked a mode
-- by hand.
--
-- The rule now lives in ONE place (Core.ApplyTooltipFieldModeRule) and is
-- RECOVERABLE: the mode the player had is remembered and restored.
do
    local core = namespace.Core
    local tooltip = type(core.GetSettings) == "function"
        and core.GetSettings().tooltip or nil
    if type(tooltip) == "table" and type(tooltip.fields) == "table"
        and type(core.ApplyTooltipFieldModeRule) == "function" then
        local fields = tooltip.fields
        local savedMode = tooltip.mode
        local savedFlag = tooltip.modeDisabledByEmptyFields
        local savedBefore = tooltip.modeBeforeEmptyFields

        -- A known starting point: Detailed, with one field enabled.
        tooltip.mode = "Detailed"
        fields.gearScore = true
        fields.baseGS = true
        fields.potentialGS = true
        fields.delta = true
        fields.averageItemLevel = true
        fields.completion = true
        core.ApplyTooltipFieldModeRule()

        -- Un-tick every field.
        for _, key in ipairs({ "gearScore", "baseGS", "potentialGS", "delta",
            "averageItemLevel", "completion" }) do
            fields[key] = false
        end
        core.ApplyTooltipFieldModeRule()
        check(tooltip.mode == "Disabled",
            "an empty field set forces the mode to Disabled",
            "mode=" .. tostring(tooltip.mode))

        -- Tick one field back: the mode comes back with it.
        fields.potentialGS = true
        core.ApplyTooltipFieldModeRule()
        check(tooltip.mode == "Detailed",
            "re-ticking a field after all were unticked restores a usable mode",
            "mode=" .. tostring(tooltip.mode))

        -- And an EXPLICIT "Disabled" the player chose is not mistaken for a
        -- forced one: nothing is restored for it.
        tooltip.mode = "Disabled"
        tooltip.modeDisabledByEmptyFields = nil
        tooltip.modeBeforeEmptyFields = nil
        fields.potentialGS = false
        core.ApplyTooltipFieldModeRule()
        fields.potentialGS = true
        core.ApplyTooltipFieldModeRule()
        check(tooltip.mode == "Disabled",
            "an explicit Disabled is not overwritten when a field is re-enabled",
            "mode=" .. tostring(tooltip.mode))

        -- Put the settings back the way they were.
        tooltip.mode = savedMode
        tooltip.modeDisabledByEmptyFields = savedFlag
        tooltip.modeBeforeEmptyFields = savedBefore
        fields.gearScore = true
        fields.baseGS = false
        fields.potentialGS = true
        fields.delta = true
        fields.averageItemLevel = true
        fields.completion = true
        core.ApplyTooltipFieldModeRule()
    end
end

-- ---------------------------------------------------------------------------
-- Item 9 (cont.): the Options page drives the same rule
-- ---------------------------------------------------------------------------
--
-- The rule has to run when a CHECKBOX changes, not only on a normalise --
-- which does not happen when the player ticks a box. The checkbox's own
-- OnClick handler is fired here, exactly as a click fires it.
do
    local options = namespace.Options
    local control = REALG.TacoTip_ExtrasOptionGearScore
    local core = namespace.Core
    if type(options) == "table" and type(core) == "table"
        and type(control) == "table" and type(core.GetSettings) == "function" then
        local tooltip = core.GetSettings().tooltip
        local fields = tooltip and tooltip.fields
        if type(fields) == "table" then
            local savedMode = tooltip.mode
            local savedFlag = tooltip.modeDisabledByEmptyFields
            local savedBefore = tooltip.modeBeforeEmptyFields
            local savedFields = {}
            for _, key in ipairs({ "gearScore", "baseGS", "potentialGS", "delta",
                "averageItemLevel", "completion" }) do
                savedFields[key] = fields[key]
            end

            tooltip.mode = "Detailed"
            for _, key in ipairs({ "gearScore", "baseGS", "potentialGS", "delta",
                "averageItemLevel", "completion" }) do
                fields[key] = false
            end
            -- Un-tick the last field through the control's own handler.
            control:SetChecked(false)
            control.__script_OnClick(control)
            check(tooltip.mode == "Disabled",
                "un-ticking the last field forces the mode to Disabled",
                "mode=" .. tostring(tooltip.mode))

            -- Tick it back through the same handler.
            control:SetChecked(true)
            control.__script_OnClick(control)
            check(tooltip.mode == "Detailed",
                "re-ticking a field restores the mode the player had",
                "mode=" .. tostring(tooltip.mode))

            tooltip.mode = savedMode
            tooltip.modeDisabledByEmptyFields = savedFlag
            tooltip.modeBeforeEmptyFields = savedBefore
            for key, value in pairs(savedFields) do
                fields[key] = value
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Batch 7 item 3: the swapped-argument guard rejects a MAIN-style call
-- ---------------------------------------------------------------------------
--
-- A deliberately swapped call -- the NAME in the condition slot, exactly the
-- shape a MAIN-style check(name, cond, detail) call has -- must be REJECTED
-- and must never count as a pass. Left unguarded it would read as a green
-- check, because a string is truthy.
--
-- The probe output is captured rather than printed, so a green run never
-- shows a stray FAIL line, and the failure it deliberately records is removed
-- again so the pin itself cannot turn the suite red.
do
    local checksBefore = checks
    local failuresBefore = #failures
    local captured = {}
    local savedOut = out
    out = function(line) captured[#captured + 1] = tostring(line) end
    -- pcall'd: with the guard ABSENT this call does not merely pass -- it
    -- formats a boolean label and raises. The probe must survive that so the
    -- pin can report the difference instead of taking the harness down with
    -- it.
    local probeOK, returned = pcall(check, "deliberately swapped check() call", true)
    out = savedOut
    local loud = table.concat(captured, "\n"):find("SWAPPED CHECK ARGUMENTS", 1, true) ~= nil
    local wasRecorded = (#failures == failuresBefore + 1 and checks == checksBefore + 1)
    -- Undo the deliberate failure: the point being proven is that a swapped
    -- call is rejected, not that this harness should fail.
    for i = #failures, failuresBefore + 1, -1 do failures[i] = nil end
    checks = checksBefore
    check(probeOK == true and returned == false and wasRecorded and loud,
        "a swapped check(cond, label) call is rejected loudly, never counted as a pass",
        "probeOK=" .. tostring(probeOK) .. " returned=" .. tostring(returned)
            .. " recorded=" .. tostring(wasRecorded) .. " loud=" .. tostring(loud))
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

-- ---------------------------------------------------------------------------
-- The scan crash: the shared inspect engine, the Extras' consumer, and the
-- "Scan now" control.
--
-- Three defects, three pins:
--
--   1. A raise inside the Extras' INVENTORY_READY consumer escaped into the
--      LIBRARY's callback dispatch. The library releases its pending inspect
--      slot only AFTER the consumer callbacks have run, so the escape cost
--      the whole session its inspects: the tooltip stopped showing scores
--      until the client was reloaded. The consumer is guarded now, and the
--      failure is COUNTED and PRINTED.
--
--   2. The client reads inside the capture path were not all guarded. Every
--      other client call in Scanner.lua degrades instead of raising; these
--      four were the outliers, and they are the only calls in the path that
--      can raise. They degrade now.
--
--   3. The "Scan now" control promised a scan and delivered a scanner stuck
--      in "pending": it began a generation and never ran it, and it also
--      stole a scan that was already scheduled. It goes through the ONE home
--      for "start a scan" now.
-- ---------------------------------------------------------------------------

do
out(("\n-- the scan crash: engine, consumer and the scan control --\n"))
local CoreX = namespace.Core
local ScannerX = namespace.Scanner
local CacheX = namespace.Cache
local BrowserX = namespace.RankBrowser

-- -------------------------------------------------------------------------
-- 1. The consumer cannot be escaped by an Extras-internal raise.
-- -------------------------------------------------------------------------
local registrations = REALG.LCI_REGISTRATIONS
local inventoryReadyConsumer = registrations
    and registrations["INVENTORY_READY"]
    and registrations["INVENTORY_READY"][ADDON_NAME]
check(type(inventoryReadyConsumer) == "function",
    "the Extras registered an INVENTORY_READY consumer with the library",
    "got " .. type(inventoryReadyConsumer))

if type(inventoryReadyConsumer) == "function" and type(CoreX) == "table"
    and type(CoreX.GetConsumerErrors) == "function" then
    local savedScanner = namespace.Scanner
    local errorsBefore = CoreX.GetConsumerErrors()
    namespace.Scanner = {
        HandleInventoryReady = function()
            error("injected scanner raise")
        end,
    }
    local escaped, escapedErr = pcall(
        inventoryReadyConsumer,
        "INVENTORY_READY",
        "Player-4242-DEADBEEF",
        true,
        "target"
    )
    namespace.Scanner = savedScanner

    check(escaped == true,
        "a raise inside the Extras' inventory-ready consumer does not escape into the library's dispatch",
        tostring(escapedErr))
    check(CoreX.GetConsumerErrors() == errorsBefore + 1,
        "...and the raise is COUNTED",
        "before=" .. tostring(errorsBefore) .. " after=" .. tostring(CoreX.GetConsumerErrors()))
    check(type(CoreX.GetLastConsumerError()) == "string"
        and CoreX.GetLastConsumerError():find("injected scanner raise", 1, true) ~= nil,
        "...and the MESSAGE is kept",
        "last=" .. tostring(CoreX.GetLastConsumerError()))

    -- ...and it is VISIBLE. The repo's rule is that a counter no user can see
    -- is a counter that cannot be acted on, so the diagnostic surface has to
    -- PRINT it, not merely expose it.
    local chatBefore = #CHAT
    if type(REALG.TacoTipExtrasPrintDebugSnapshot) == "function" then
        pcall(REALG.TacoTipExtrasPrintDebugSnapshot)
    end
    local printed = ""
    for index = chatBefore + 1, #CHAT do
        printed = printed .. CHAT[index] .. "\n"
    end
    check(printed:find("inventory-ready-errors=", 1, true) ~= nil,
        "/ttgsdebug PRINTS the consumer-failure counter",
        printed)
    local messageLine = printed:match("last%-inventory%-ready%-error=([^\n]*)")
    check(type(messageLine) == "string"
        and messageLine:find("injected scanner raise", 1, true) ~= nil,
        "/ttgsdebug PRINTS the consumer-failure message",
        printed)
    check(printed:find("inspect-ready-errors=", 1, true) ~= nil,
        "/ttgsdebug PRINTS the ENGINE's own counter for the same boundary",
        printed)
end

-- -------------------------------------------------------------------------
-- 2. A client read that raises degrades the capture instead of taking it
--    down. The behaviour is pinned, not the implementation: the capture
--    still PUBLISHES, and the class reads as unavailable.
-- -------------------------------------------------------------------------
do
    local savedUnitExists = REALG.UnitExists
    local savedUnitIsPlayer = REALG.UnitIsPlayer
    local savedUnitGUID = REALG.UnitGUID
    local savedGUIDIsPlayer = REALG.GUIDIsPlayer
    local savedUnitClass = REALG.UnitClass
    local savedUnitLevel = REALG.UnitLevel
    local savedGetInventoryItemID = REALG.GetInventoryItemID
    local savedGetInventoryItemLink = REALG.GetInventoryItemLink

    local REMOTE_GUID = "Player-5150-0A0B0C0D"
    local REMOTE_UNIT = "crashprobe1"

    REALG.UnitExists = function(unit)
        return unit == "player" or unit == REMOTE_UNIT
    end
    REALG.UnitIsPlayer = function(unit)
        return unit == "player" or unit == REMOTE_UNIT
    end
    REALG.UnitGUID = function(unit)
        if unit == "player" then return "Player-0000-00000000" end
        if unit == REMOTE_UNIT then return REMOTE_GUID end
        return nil
    end
    REALG.GUIDIsPlayer = function() return true end
    REALG.UnitLevel = function() return 70 end
    -- The class read raises. This is the shape the fuzz found: UnitClass was
    -- the one client call in the capture path that was not pcall-guarded.
    REALG.UnitClass = function() error("injected UnitClass raise") end
    REALG.GetInventoryItemID = function(unit, slotID)
        if unit == REMOTE_UNIT and slotID == 1 then return 50003 end
        return nil
    end
    REALG.GetInventoryItemLink = function(unit, slotID)
        if unit == REMOTE_UNIT and slotID == 1 then return HARNESS_ITEM_LINK end
        return nil
    end

    local raised, raisedErr = pcall(function()
        return ScannerX.HandleInventoryReady(
            "INVENTORY_READY", REMOTE_GUID, true, REMOTE_UNIT)
    end)
    check(raised == true,
        "a raising client read in the capture path does not take the capture down",
        tostring(raisedErr))
    local snapshot = CacheX and CacheX.Get(REMOTE_GUID) or nil
    check(type(snapshot) == "table" and snapshot.state == "complete",
        "...and the capture still PUBLISHES a complete entry",
        "state=" .. tostring(snapshot and snapshot.state)
            .. " reason=" .. tostring(snapshot and snapshot.reason))
    local classBlocked = false
    if type(snapshot) == "table" and type(snapshot.result) == "table"
        and type(snapshot.result.metrics) == "table"
        and type(snapshot.result.metrics.gearScore) == "table" then
        local metric = snapshot.result.metrics.gearScore
        classBlocked = (metric.status ~= "complete")
    end
    check(classBlocked,
        "...and the unreadable class is published as UNAVAILABLE, not as a zero",
        "gearScore status=" .. tostring(snapshot and snapshot.result
            and snapshot.result.metrics.gearScore
            and snapshot.result.metrics.gearScore.status))

    REALG.UnitExists = savedUnitExists
    REALG.UnitIsPlayer = savedUnitIsPlayer
    REALG.UnitGUID = savedUnitGUID
    REALG.GUIDIsPlayer = savedGUIDIsPlayer
    REALG.UnitClass = savedUnitClass
    REALG.UnitLevel = savedUnitLevel
    REALG.GetInventoryItemID = savedGetInventoryItemID
    REALG.GetInventoryItemLink = savedGetInventoryItemLink
end

-- -------------------------------------------------------------------------
-- 3. The "Scan now" control leaves the scanner in a state that COMPLETES,
--    and bumps the generation exactly once for that scan.
-- -------------------------------------------------------------------------
do
    -- Clear any scan that is already pending, so the generation this control
    -- bumps is the only one it bumps.
    for _, frame in ipairs(FRAMES_BY_REGISTRATION) do
        if type(frame) == "table" and type(frame.GetScript) == "function"
            and type(frame:GetScript("OnUpdate")) == "function" then
            pcall(frame:GetScript("OnUpdate"), frame)
        end
    end

    local progressBefore = ScannerX.GetProgress()
    local generationBefore = progressBefore and progressBefore.generation or 0
    local started = false
    local startOK, startErr = pcall(function()
        started = BrowserX.StartScan()
    end)
    check(startOK == true,
        "the scan control does not raise",
        tostring(startErr))
    check(started == true,
        "the scan control reports that a scan was started",
        "started=" .. tostring(started))

    local progressAfter = ScannerX.GetProgress()
    local generationAfter = progressAfter and progressAfter.generation or 0
    check(generationAfter == generationBefore + 1,
        "the scan control bumps the generation EXACTLY ONCE for one scan",
        "before=" .. tostring(generationBefore) .. " after=" .. tostring(generationAfter))

    -- Now run the scan the way the client does: the scan is deferred to the
    -- event frame's next OnUpdate tick.
    for _, frame in ipairs(FRAMES_BY_REGISTRATION) do
        if type(frame) == "table" and type(frame.GetScript) == "function"
            and type(frame:GetScript("OnUpdate")) == "function" then
            pcall(frame:GetScript("OnUpdate"), frame)
        end
    end

    local state = ScannerX.GetCurrent()
    check(type(state) == "table" and state.status == "complete",
        "the scan the control started REACHES a COMPLETE state, not a permanent 'pending'",
        "status=" .. tostring(state and state.status)
            .. " reason=" .. tostring(state and state.reason))
    check(type(state) == "table" and state.generation == generationAfter,
        "...on the generation the control bumped",
        "state.generation=" .. tostring(state and state.generation)
            .. " expected=" .. tostring(generationAfter))
end
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