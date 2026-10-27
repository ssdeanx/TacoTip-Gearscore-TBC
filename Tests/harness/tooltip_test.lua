-- Executes the main.lua tooltip pipeline under a mocked client and asserts the
-- enhancement actually produces lines.
-- Usage: lua5.1 tooltip_test.lua <projectId> <iface> <label> [pipeline]

local _hp = ((arg and arg[0]) or "Tests/harness/tooltip_test.lua"):gsub("\\", "/")
local _hd = _hp:match("^(.*)/[^/]*$") or "."
local ROOT = dofile(_hd .. "/root.lua") .. "/"
local MOCKC = dofile(_hd .. "/mock_contract.lua")

local projectId, iface, label = tonumber(arg[1]), tonumber(arg[2]), arg[3]
local usePipeline = (arg[4] == "pipeline")
local DEBUG = (arg[5] == "debug")
MOCKC.setFamily(MOCKC.normaliseFamily(label))

local REALG = _G
-- `unpack` is a global in Lua 5.1 -- what WoW ships, and what this addon targets
-- -- but 5.2 moved it to `table.unpack`, so the bare global is nil under lua5.4.
-- Resolve it once here, before the sandbox table below is built, so both
-- interpreters get a callable; the local shadows the global at every use in this
-- file, including the xpcall trampoline, which is the only place that unpacks
-- varargs. Without it the trampoline throws, main.lua's safeCall handler swallows
-- that error, and the pipeline emits no lines -- so every assertion below would
-- fail on an empty tooltip rather than on a real defect.
local unpack = unpack or table.unpack

local STD = {
    os = os,
    string = string,
    pairs = pairs,
    ipairs = ipairs,
    type = type,
    pcall = pcall,
    tonumber = tonumber,
    tostring = tostring,
    select = select,
    rawget = rawget,
    rawset = rawset,
    setmetatable = setmetatable,
    getmetatable = getmetatable,
    unpack = unpack,
    assert = assert,
    error = error,
    math = math,
    table = table,
    loadfile = loadfile,
    print = print,
    io = io,
    -- WoW's Lua provides these; main.lua's safeCall depends on the extended
    -- xpcall that accepts the arguments after the handler. It MUST route the
    -- error to the handler -- a mock that swallows it makes every assertion in
    -- this file meaningless.
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
    next = next,
    rawequal = rawequal,
    rawlen = function(t) return #t end,
    -- WoW exposes collectgarbage as a global, so including it in the sandbox is
    -- faithful to the client rather than a test convenience. It is here for the
    -- per-render allocation assertions below, which need collectgarbage("count")
    -- to be called FROM the sandboxed chunk -- the same reason next() is
    -- included, and the same trap: a global the harness env does not carry reads
    -- as nil and the test dies on the diagnostic instead of on the defect.
    collectgarbage = collectgarbage
}

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
    "AddLine", "AddDoubleLine", "ClearLines", "ClearAllPoints", "CreateFontString",
    "CreateTexture", "Enable", "Disable", "EnableMouse", "EnableMouseWheel", "GetAlpha",
    "GetBottom", "GetCenter", "GetChecked", "GetEffectiveScale", "GetFrameLevel",
    "GetFrameStrata", "GetHeight", "GetItem", "GetLeft", "GetLeftLine", "GetMinimumWidth",
    "GetName", "GetNumLines", "GetObjectType", "GetParent", "GetRight", "GetRightLine",
    "GetSize", "GetStringHeight", "GetText", "GetUnit", "GetVerticalScroll",
    "GetVerticalScrollRange", "GetWidth", "Hide", "HookScript", "IsEnabled", "IsObjectType",
    "IsShown", "IsUnit", "NumLines", "RegisterEvent", "RegisterForClicks", "RegisterForDrag",
    "SetAlpha", "SetBackdrop", "SetBackdropBorderColor", "SetBackdropColor", "SetChecked",
    "SetClampedToScreen", "SetClampRectInsets", "SetColor", "SetColorRGB", "SetColorTexture",
    "SetDesaturated", "SetDisabled", "SetDrawLayer", "SetEnabled", "SetFont", "SetFontObject",
    "SetFrameLevel", "SetFrameStrata", "SetHeight", "SetHitRectInsets", "SetJustifyH",
    "SetJustifyV", "SetMaxLetters", "SetMinMaxValues", "SetMinimumWidth", "SetMovable",
    "SetNonSpaceWrap", "SetNormalTexture", "SetObeyStepOnDrag", "SetOwner", "SetPadding",
    "SetParent", "SetPoint", "SetPortraitTexture", "SetPortraitZoom", "SetScrollChild",
    "SetScript", "SetShadowColor", "SetShadowOffset", "SetShown", "SetSize", "SetStatusBarColor",
    "SetStatusBarTexture", "SetTexCoord", "SetText", "SetTextColor", "SetTexture", "SetUnit",
    "SetUserPlaced", "SetValue", "SetValueStep", "SetVerticalScroll", "SetWidth", "SetWordWrap",
    "Show", "StartMoving", "StopMovingOrSizing", "UnregisterEvent", "UpdateScrollChildRect",
    "UpdateTooltip", "FadeOut", "GetAnchorType", "IsEquippedItem", "IsOwned", "GetOwner",
    "GetSpell", "SetItem", "SetPlayer", "ClearModel", "SetModelScale", "SetCamera", "SetPosition",
    "SetFacing", "Refresh", "GetScale", "RegisterUnitEvent", "GetNumPoints", "SetID", "GetID",
    "SetToplevel", "SetClampedToScreen", "ClearPadding", "GetMinMaxValues", "GetValue",
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
    w.__scripts = {
        OnLoad = true,
        OnShow = true,
        OnHide = true,
        OnEvent = true,
        OnUpdate = true,
        OnSizeChanged = true,
        OnEnter = true,
        OnLeave = true
    }
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
        w.__points[#w.__points + 1] = { p, relName, rp, ox or 0, oy or 0 }
    end
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
    -- Configurable, like __right: the portrait side is measured against the
    -- anchor target's left edge when a saved position owns the tooltip.
    w.__left = 0
    w.GetLeft = function() return w.__left or 0 end
    -- Configurable. The portrait side decision reads the tooltip's GetRight()
    -- against UIParent's, so a mock that hardcodes 0 collapses every screen
    -- position onto the same side and the decision cannot be tested at all.
    w.__right = 0
    w.GetRight = function() return w.__right or 0 end
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
    -- Returns the widget's own __alpha rather than a hardcoded 1. Hardcoding it
    -- made the "portrait alpha is not slaved to the tooltip" assertion pass
    -- unconditionally: the slave copied 1, and 1 is what the assertion expected.
    -- A test that cannot fail is not a test.
    w.__alpha = 1
    w.GetAlpha = function(self) return self.__alpha end
    w.SetAlpha = function(self, a) self.__alpha = a end
    w.SetBackdropColor = function() end
    w.SetBackdropBorderColor = function(_, r, g, b, a) w.__borderColor = { r, g, b, a } end
    w.GetBackdropBorderColor = function() return 1, 1, 1, 1 end
    w.SetClampedToScreen = function() end
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
    -- SetFont COUNTS. It used to be `function() end`, which is precisely why the
    -- addon's per-render font churn shipped unnoticed: the mock could not tell a
    -- line that was re-fonted from one that was left alone, so any test written
    -- against it measured nothing. Arguments are recorded as well, so a change
    -- guard can be proved to have set the font rather than skipped it.
    --
    -- The counter is ALSO kept globally, because the pooled lines are not stable
    -- objects: the mock's ClearLines drops its line table and the next GetLeftLine
    -- builds a fresh FontString under the same global name, so a per-widget
    -- reference taken before a render measures a widget nobody wrote to. A test
    -- that counted only the widget it happened to be holding would report zero
    -- and look like a working guard.
    w.__fontCalls = 0
    w.__font, w.__fontSize = nil, nil
    w.SetFont = function(_, f, s)
        w.__fontCalls = (w.__fontCalls or 0) + 1
        w.__font, w.__fontSize = f, s
        REALG.__fontCalls = (REALG.__fontCalls or 0) + 1
    end
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
    -- Recorded as three scalars, not a {r,g,b} table. A table here would be
    -- allocated by the MOCK on every call, and the FIX 5 assertion below measures
    -- collectgarbage("count") across 20 power updates -- the harness would have
    -- been measuring its own instrumentation.
    w.SetStatusBarColor = function(_, r, g, b)
        w.__statusR, w.__statusG, w.__statusB = r, g, b
    end
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

    -- GameTooltip line pool.
    --
    -- ClearLines KEEPS the FontStrings. That is what the client does: the line
    -- FontStrings are created once, on the tooltip, and every later hover reuses
    -- them -- the addon's own comment at main.lua:101 says exactly that ("the
    -- pooled lines are reused across hovers, so a line left over from a longer
    -- previous tooltip still carries the old cap").
    --
    -- The mock used to model ClearLines as `w.__lines = {}`, which DESTROYS the
    -- pool. Every "line" the addon then saw was a brand-new FontString with no
    -- remembered state, so a per-line change guard -- the width cap at
    -- main.lua:107 and the font guard added in 0.7.9 -- could never skip
    -- anything: it was always looking at a first render. The guard was not
    -- merely untested, it was untestable, and the mock made "apply it every
    -- render" look like the only possible behaviour.
    w.__linePool = {}
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
    w.__linePoolR = {}
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
    w.GetItem = function() return "n", ITEM[1].link end
    w.GetSpell = function() return "n", 1 end
    w.IsUnit = function(_, u) return w.__unit == u end
    w.GetMinimumWidth = function() return 0 end
    w.SetMinimumWidth = function() end
    w.GetAnchorType = function() return 1 end
    -- The three layout writes below COUNT. Like SetFont, they were `function() end`
    -- and therefore invisible to every test: an addon that re-asserted the same
    -- padding, clamp inset and anchor on every render looked exactly like one that
    -- set each of them once. SetBackdrop additionally records the info table so a
    -- change guard can be shown to be comparing something real.
    w.__clampCalls = 0
    w.SetClampRectInsets = function(_, l, r, t, b)
        w.__clampCalls = (w.__clampCalls or 0) + 1
        w.__clampInsets = { l, r, t, b }
    end
    -- SetPadding and ClearPadding are counted SEPARATELY. They share one slot in
    -- the client, but clearTooltipVisuals calls ClearPadding on entry to every
    -- render while the power-bar block calls SetPadding later and only on a
    -- render that runs to completion -- so with one shared counter the last
    -- writer alternates and a "the padding was applied" assertion reads 0,0,0,0
    -- on a frame that is in fact padded.
    w.__paddingCalls = 0
    w.__padding = nil
    w.SetPadding = function(_, l, r, t, b)
        w.__paddingCalls = (w.__paddingCalls or 0) + 1
        w.__padding = { l, r, t, b }
    end
    w.__clearPaddingCalls = 0
    w.ClearPadding = function()
        w.__clearPaddingCalls = (w.__clearPaddingCalls or 0) + 1
    end
    w.__backdropCalls = 0
    w.__backdropInfo = nil
    w.SetBackdrop = function(_, info)
        w.__backdropCalls = (w.__backdropCalls or 0) + 1
        w.__backdropInfo = info
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
REALG.geterrorhandler = function()
    return function(e)
        ERRORS[#ERRORS + 1] = tostring(e)
    end
end
ERRORS = {}
-- Deferred bodies (C_Timer.NewTimer/NewTicker callbacks) are recorded, not
-- run, so a block can drive them by hand exactly once and assert what they do.
-- The mock stays honest: nothing fires unless the test fires it. The vararg
-- shape matters: the addon calls NewTimer(duration, fn) with a dot, not a
-- colon, so the callback is the LAST argument, not the third.
TIMERS = {}
-- Frame types CreateFrame actually accepts. "Texture" and "FontString" are
-- WIDGET types created with frame:CreateTexture() / :CreateFontString(); they
-- are rejected by the real CreateFrame with
--   CreateFrame: Unknown frame type 'Texture'
-- A mock that accepts any string cannot catch that class of bug at all.
local VALID_FRAME_TYPES = {
    Frame = true,
    Button = true,
    CheckButton = true,
    EditBox = true,
    ScrollFrame = true,
    Slider = true,
    StatusBar = true,
    GameTooltip = true,
    PlayerModel = true,
    NumberEditBox = true,
    SelectionGroup = true,
    ColorPicker = true,
    MessageFrame = true,
    Model = true,
    Movie = true,
    OffScreenFrame = true,
    SideDock = true,
    ArenaSpectatorFrame = true,
}
REALG._VALID_FRAME_TYPES = VALID_FRAME_TYPES
REALG.CreateFrame = function(kind, name, parent, template)
    if (type(kind) ~= 'string' or not VALID_FRAME_TYPES[kind]) then
        error("CreateFrame: Unknown frame type '" .. tostring(kind) .. "'", 2)
    end
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
REALG.C_AddOns = {
    GetAddOnMetadata = function(_, k)
        if k == "Version" then return "0.7.8" end
        if k == "Title" then return "TacoTip Forever" end
    end,
    IsAddOnLoaded = function() return false end
}
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
    player = {
        guid = "Player-1-00000001",
        name = "Testplayer",
        level = 60,
        race = "Human",
        class = "WARRIOR",
        isPlayer = true,
        pvp = false
    },
    mouseover = {
        guid = "Player-2-00000002",
        name = "Enemyplayer",
        level = 59,
        race = "Orc",
        class = "MAGE",
        isPlayer = true,
        pvp = true
    },
    target = {
        guid = "Creature-3-00000003",
        name = "Hated Squirrel",
        level = 42,
        race = "Beast",
        class = nil,
        isPlayer = false,
        pvp = false
    },
}
local currentUnit = "player"
REALG.UnitExists = function(u) return UNITS[u] ~= nil end
REALG.UnitGUID = function(u) return UNITS[u] and UNITS[u].guid or nil end
REALG.UnitName = function(u) return UNITS[u] and UNITS[u].name or nil end
-- A controllable clock, deliberately parked at 0 unless a test moves it.
--
-- The library's pacing gate is `now >= nextInspectTime`, where nextInspectTime is
-- set to now + INSPECT_DELAY when a request goes out -- so with no clock at all
-- (this mock's original state) the library reads 0 for every timestamp and can
-- issue exactly ONE request per run: the first one. Any test that needs a second
-- request has to move this forward, which is honest about what it is doing. Every
-- other test sees 0, exactly as it did when GetTime was absent.
REALG.__testClock = 0
REALG.GetTime = function() return REALG.__testClock end
REALG.UnitLevel = function(u) return UNITS[u] and UNITS[u].level or 1 end
REALG.UnitRace = function(u) return UNITS[u] and UNITS[u].race or "" end
-- UnitClass publishes THREE values on the modern pair (localizedClassName,
-- classToken, classID) and TWO on the Classic family. The mock used to
-- publish two on every client -- one shape for five clients -- which made
-- the per-family gap structurally invisible. The contract pins the arity.
--   origin/live, origin/forever: UnitUtil.lua:81 `select(3, UnitClass("player"))`
--   origin/classic_era etc.:      InspectPaperDollFrame.lua:10 `local classDisplayName, class = UnitClass(...)`
REALG.UnitClass = MOCKC.unitClassMock(function(u)
    local c = UNITS[u]
    if (not c or not c.class) then return nil, nil end
    return c.class, c.class
end)
REALG.UnitIsPlayer = function(u) return UNITS[u] and UNITS[u].isPlayer or false end
REALG.UnitIsUnit = function(a, b) return a == b end
-- C_PaperDollInfo.GetInspectGuildInfo publishes FOUR values: achievement
-- points, member count, guild name, realm name (PaperDollInfoDocumentation.lua:95
-- on origin/live and :104 on origin/forever). The FOURTH is nil for a player
-- with no guild -- the fact the guild guard reads to tell Blizzard's own
-- defect from any other error. The mock publishes four, as the client does.
REALG.C_PaperDollInfo = {
    GetInspectGuildInfo = function() return 0, 0, nil, nil end,
}
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
    return nil
end
REALG.C_Item.GetInventoryItemLink = REALG.GetInventoryItemLink
REALG.GetItemInfo = function(link)
    for _, it in ipairs(ITEM) do
        if (it.link == link) then
            return it.name, it.link, it.quality, it.ilvl, 1, "Armor", "Cloth", 1,
                it.equipLoc, "icon", 0
        end
    end
    return nil
end
REALG.C_Item.GetItemInfo = REALG.GetItemInfo
REALG.GetItemInfoInstant = function() return REALG.__itemInfoInstantID end
-- Batch 7 item 4: the namespaced item-ID resolver.
--
-- main.lua resolves the item ID from C_Item.GetItemInfoInstant (the bare
-- global exists only on the three Classic-family branches -- verified in the
-- FrameXML mirror: Blizzard_DeprecatedItemScript/Deprecated_ItemScript.lua:10
-- aliases it on origin/classic_era, origin/classic_anniversary and
-- origin/classic_titan, and that file is ABSENT on origin/forever and
-- origin/live). The value is read at CALL time through a harness variable, so
-- a test can move the ID without reloading the addon.
REALG.__itemInfoInstantID = 12345
REALG.C_Item.GetItemInfoInstant = function() return REALG.__itemInfoInstantID end
REALG.C_Item.IsEquippableItem = function() return true end
REALG.IsEquippableItem = REALG.C_Item.IsEquippableItem
-- The item-data request counter.
--
-- Installed BEFORE the addon loads, because gearscore.lua captures
-- C_Item.RequestLoadItemDataByID at file scope (gearscore.lua:101) -- a
-- counter swapped in afterwards would never be seen by the shared throttle.
REALG.__rawItemRequests = 0
REALG.__rawItemRequestIDs = {}
REALG.C_Item.RequestLoadItemDataByID = function(id)
    REALG.__rawItemRequests = REALG.__rawItemRequests + 1
    REALG.__rawItemRequestIDs[#REALG.__rawItemRequestIDs + 1] = id
end
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
-- THE 0.7.9 REGRESSION MOCK.
--
-- ClearInspectPlayer() purges the inspected unit from the client engine, so
-- Blizzard's own InspectPaperDollItemSlotButton_Update then finds
-- GetInventoryItemTexture returning nil for all 18 equipment slots and resets
-- every button to its empty background texture -- "Right-click inspect stripped
-- all gear from the paperdoll on Retail and WoW Forever" (0.7.9). Blizzard
-- itself calls it only from InspectFrame_OnHide
-- (origin/live: Blizzard_InspectUI/Mainline/Blizzard_InspectUI.lua:104;
--  origin/classic_era: Blizzard_InspectUI/Vanilla/Blizzard_InspectUI.lua:85).
--
-- The mock stays a no-op to the client -- nothing else about it changes -- and
-- COUNTS the call, because the guarantee to pin is the ABSENCE of the call,
-- and nothing else can observe an absence.
REALG.__clearInspectPlayerCalls = 0
REALG.ClearInspectPlayer = function()
    REALG.__clearInspectPlayerCalls = (REALG.__clearInspectPlayerCalls or 0) + 1
end
REALG.CanInspect = function() return true end
REALG.GetComparisonAchievementPoints = function() return 0 end
REALG.GetTotalAchievementPoints = function() return 0 end
REALG.GetQuestDifficultyColor = function() return { r = 1, g = .5, b = 0 } end
REALG.C_Timer = {
    After = function(_, _, fn) if fn then fn() end end,
    NewTimer = function(...)
        local a = { ... }; local fn = a[#a]
        local h = { Cancel = function() end, func = fn }; TIMERS[#TIMERS + 1] = h; return h
    end,
    NewTicker = function(...)
        local a = { ... }; local fn = a[#a]
        local h = { Cancel = function() end, func = fn }; TIMERS[#TIMERS + 1] = h; return h
    end
}
REALG.C_PlayerInfo = {
    GUIDIsPlayer = function(g)
        return type(g) == "string" and string.find(g, "Player%-", 1) == 1
    end
}
REALG.C_Map = { GetBestMapForUnit = function() return nil end }
-- Realistic Warrior specialization model, mirroring the Classic talent model:
-- group 1 is active and holds Arms (tab 1, 21 points), group 2 holds Fury
-- (tab 2, 31 points). Group 1 being active is what makes the second spec line
-- render grey.
-- `icon` is a fileID on the modern clients, which is why it is a number here.
local SPECS = {
    [1] = { id = 71, name = "Arms", icon = 1100001, role = "TANK", class = "WARRIOR", classDisplayName = "Warrior" },
    [2] = { id = 72, name = "Fury", icon = 1100002, role = "DPS", class = "WARRIOR", classDisplayName = "Warrior" },
    [3] = { id = 73, name = "Protection", icon = 1100003, role = "TANK", class = "WARRIOR", classDisplayName = "Warrior" },
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
            name = "Talent",
            icon = t.icon,
            tier = t.tier,
            column = t.column,
            selected = false,
            available = true,
            isPVPTalentUnlocked = false,
            known = false,
            grantedByAura = false,
            rank = rank,
            maxRank = t.maxRank or 1,
            meetsPrereq = true,
            previewRank = rank,
            meetsPreviewPrereq = true,
            isExceptional = t.isExceptional or false,
            hasGoldBorder = false,
        }
    end
    if (query.tier and query.column) then
        TALENT_QUERIES.grid = TALENT_QUERIES.grid + 1
        for _, list in pairs(TALENTS) do
            for _, t in ipairs(list) do
                if (t.tier == query.tier and t.column == query.column) then
                    return {
                        talentID = t.icon,
                        name = "Talent",
                        icon = t.icon,
                        tier = t.tier,
                        column = t.column,
                        selected = false,
                        available = true,
                        isPVPTalentUnlocked = false,
                        known = false,
                        grantedByAura = false,
                        rank = t.rank or 0,
                        maxRank = t.maxRank or 1,
                        meetsPrereq = true,
                        previewRank = t.rank or 0,
                        meetsPreviewPrereq = true,
                        isExceptional = t.isExceptional or false,
                        hasGoldBorder = false,
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
-- GetSpecializationInfoByID publishes SEVEN values:
--   id, name, description, texture, role, class, classDisplayName
-- The mock published four, so #5-#7 were latent gaps (the addon reads #2 and
-- #4 only today). origin/live: ClubFinder.lua:599 destructures exactly seven.
REALG.GetSpecializationInfoByID = function(specID)
    for _, s in pairs(SPECS) do
        if (s.id == specID) then
            return s.id, s.name, "desc", s.icon, s.role, s.class, s.classDisplayName
        end
    end
    return nil, nil, nil, nil, nil, nil, nil
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
-- Broken-by-design object API: CreateFromItemLink raises, so the no-object
-- fallback arm (fire-and-forget request + bounded one-shot repaint) is
-- reachable in-harness. A nil Item would take the earlier silent return
-- instead, and a working factory would never take the arm at all. Cached
-- fixtures never reach the arm (no refresh is scheduled for complete info),
-- so normal item renders are unaffected.
REALG.Item = { CreateFromItemLink = function() error("BATCH3_PIN_NO_ITEM_API") end }
REALG.Settings = nil
REALG.ColorPickerFrame = nil

-- Tooltip script sets per family. Modern tooltips have no
-- OnTooltipSetUnit / OnTooltipSetItem / OnTooltipSetSpell.
do
    local modern = {
        OnLoad = true,
        OnShow = true,
        OnHide = true,
        OnEvent = true,
        OnUpdate = true,
        OnTooltipCleared = true,
        OnSizeChanged = true,
        OnEnter = true,
        OnLeave = true
    }
    local classic = {
        OnLoad = true,
        OnShow = true,
        OnHide = true,
        OnEvent = true,
        OnUpdate = true,
        OnTooltipCleared = true,
        OnSizeChanged = true,
        OnEnter = true,
        OnLeave = true,
        OnTooltipSetUnit = true,
        OnTooltipSetItem = true,
        OnTooltipSetSpell = true
    }
    local set = usePipeline and modern or classic
    for _, nm in ipairs({ "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1",
        "ShoppingTooltip2", "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2" }) do
        local f = REALG[nm]
        if (f and rawget(f, "__scripts") ~= nil) then rawset(f, "__scripts", set) end
    end
end

if (usePipeline) then
    POSTCALLS = {}
    REALG.TooltipDataProcessor = {
        AddTooltipPostCall = function(typ, fn)
            POSTCALLS[#POSTCALLS + 1] = { typ = typ, fn = fn }
        end
    }
    REALG.TooltipUtil = {
        GetDisplayedUnit = function() return "n", currentUnit, UNITS[currentUnit].guid end,
        GetDisplayedItem = function() return "n", ITEM[1].link end
    }
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

-- The client's GameTooltip:GetUnit returns NAME and UNIT -- two values, never a
-- third.
--
-- Verified in the FrameXML mirror (wow-ui-source) on all five branches: every
-- Blizzard call site destructures exactly two --
-- `local name, unit = self:GetUnit()` at
-- Interface/AddOns/Blizzard_PTRFeedback/Blizzard_PTRFeedback_Tooltips.lua:87
-- on origin/classic_era, origin/classic_anniversary and origin/classic_titan,
-- and :105 on origin/forever and origin/live -- and NO call site on any
-- branch destructures three.
--
-- The GUID comes from the SIBLING resolver instead:
-- Interface/AddOns/Blizzard_SharedXMLGame/Tooltip/TooltipUtil.lua:40
-- (`return name, unit, guid;`) -- and that namespace does not exist on the
-- Classic family at all.
--
-- A mock that returned a third value made main.lua's
-- `pcall(tooltip.GetUnit, tooltip)` read a guid the engine never publishes,
-- and the branch it feeds (resolveTooltipUnit's `elseif (ok and guid)`) cannot
-- be taken by a real client on any of the five. Every mock below therefore
-- returns exactly two values.
local function mockGetUnit(unitToken)
    return function() return "n", unitToken end
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
    if (not ok) then
        loadFail = rel .. " -> " .. tostring(err); break
    end
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
-- The name-on-line-1 bump. Mirrors TOOLTIP_NAME_FONT_SIZE_DELTA in main.lua (2).
local TOOLTIP_NAME_FONT_SIZE_DELTA = 2
local SHIPPED_NAME_FONT_SIZE_DELTA = 2
local function check(name, cond, detail)
    checks[#checks + 1] = { name, cond and true or false, detail }
end

--------------------------------------------------------------------------
-- The mock-fidelity contract (proctor HI-12).
--
-- Every mock is a claim about what the client does, and three of them were
-- wrong while the suite stayed green. The table in mock_contract.lua records
-- the client's arity per API with the mirror citation that established it;
-- these assertions measure the mock that is actually installed and fail when
-- the two disagree. The next drift fails the suite instead of waiting for a
-- human to read FrameXML.
--------------------------------------------------------------------------
MOCKC.assertArity(check, "UnitClass", REALG.UnitClass)
MOCKC.assertArity(check, "GetSpecializationInfoByID", REALG.GetSpecializationInfoByID)
MOCKC.assertArity(check, "GetInspectGuildInfo", REALG.C_PaperDollInfo.GetInspectGuildInfo)

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

--------------------------------------------------------------------------
-- Per-render change guards (0.7.9).
--
-- Everything in this block asserts the SAME shape of thing: a render that
-- changes nothing observable must not redo work whose result is already on the
-- frame. The counters are read off the mock, and every mock method these tests
-- count was `function() end` until this block existed -- so before it, each of
-- these bugs was invisible to the suite by construction, not by luck.
--
-- Three rules keep this block honest:
--  1. Every "added 0 calls" assertion is paired with one that proves the work
--     actually HAPPENED. A guard that never fires at all passes the first half
--     of that pair, so the second half is the evidence.
--  2. Counters are baselined AFTER a settling pair, never across one, so
--     first-render construction cost is not billed to a re-render.
--  3. Measurements span a PAIR of renders, never a single one. A render that
--     stops early -- clearTooltipLevelColorLine blanks lines 2 and 3 on entry,
--     and an early return then leaves them blank, so the NEXT render trips the
--     "player with no level line" guard at main.lua:1429 and stops early too --
--     contributes nothing to any counter here. A single-render delta would
--     therefore be 0 or the full cost depending on parity, which is how a
--     change guard can look like it works without ever having been exercised.
--     Over a pair at least one render reaches the whole pipeline, which is
--     enough to distinguish "skipped" from "applied" in both directions.
--------------------------------------------------------------------------
do
    local SCREEN_W = 1920
    local PAIR = 2

    -- Unit resolution has to be installed explicitly before driving a render.
    -- The mock does NOT define widget GetUnit -- it falls through to the
    -- catch-all that returns nothing -- so on the Classic family a unit render
    -- finds no unit, calls clearTooltipVisuals and returns at main.lua:1378,
    -- having done none of the work these tests measure. The same is true of
    -- TooltipUtil on the pipeline family. Both are restored at the end.
    local savedGetUnit = GT.GetUnit
    local savedUtilFn = REALG.TooltipUtil and REALG.TooltipUtil.GetDisplayedUnit or nil

    local function installUnitResolver()
        GT.__unit = currentUnit
        if (REALG.TooltipUtil) then
            REALG.TooltipUtil.GetDisplayedUnit = function()
                return "n", currentUnit, UNITS[currentUnit].guid
            end
        else
            GT.GetUnit = mockGetUnit(currentUnit)
        end
    end

    -- The client's GameTooltip:GetUnit publishes NAME and UNIT and nothing else
    -- (the mirror evidence is on the mockGetUnit helper above). Pinned HERE,
    -- next to the resolver the whole Classic suite runs on, because a third
    -- value would let the addon read a guid the engine never publishes -- and
    -- the arm that guid feeds is unreachable on every supported client.
    --
    -- The pipeline family resolves through TooltipUtil, whose third return
    -- (name, unit AND guid) IS faithful, so the check applies to the Classic
    -- resolver only.
    if (not REALG.TooltipUtil) then
        installUnitResolver()
        check("the installed GetUnit resolver publishes exactly two values, like the engine",
            select("#", GT.GetUnit(GT)) == 2,
            "returns=" .. tostring(select("#", GT.GetUnit(GT))))
    end

    local function driveUnit(unitName)
        currentUnit = unitName or "player"
        installUnitResolver()
        local u = UNITS[currentUnit]
        local guid = (u and u.guid) or "Player-1-00000001"
        if (POSTCALLS and POSTCALLS[1]) then
            POSTCALLS[1].fn(GT, { guid = guid })
        elseif (GT.__hooks and GT.__hooks.OnTooltipSetUnit) then
            GT.__hooks.OnTooltipSetUnit(GT, guid)
        end
    end

    -- A render expected to reach the whole pipeline. The frame is marked shown
    -- and the stock line set re-seeded BEFORE the call, because two of the
    -- production conditions under test (the portrait anchor epoch, the power bar
    -- block) are gated on exactly those two facts.
    local function settleUnitRender(unitName)
        GT.__shown = true
        seedTooltip()
        driveUnit(unitName)
    end

    local function settlePair(n)
        for _ = 1, (n or PAIR) do settleUnitRender("player") end
    end

    local function line1()
        return (TT.GetTooltipLeftLine and TT.GetTooltipLeftLine(GT, 1))
            or (GT.GetLeftLine and GT.GetLeftLine(1))
    end

    local function lineN(n)
        return (TT.GetTooltipLeftLine and TT.GetTooltipLeftLine(GT, n))
            or (GT.GetLeftLine and GT.GetLeftLine(n))
    end

    -- A media setting is stored as a SharedMedia name and resolved to a path
    -- through a cache, so a test that pokes the config has to invalidate that
    -- cache or it measures nothing. The probe is taken from the addon's own
    -- choice list rather than hardcoded, so it stays valid as the list changes.
    local function mediaProbe(kind)
        local getter = (kind == "font") and TT.GetTooltipFontChoices or TT.GetTooltipBorderChoices
        local current = (kind == "font") and TT:GetResolvedTooltipFont() or TT:GetResolvedTooltipBorder()
        if (not getter) then return nil, current end
        for _, entry in ipairs(getter(TT) or {}) do
            if (entry.value and entry.value ~= current) then
                return entry.value, current
            end
        end
        return nil, current
    end

    local function setMedia(kind, value)
        if (kind == "font") then
            REALG.TacoTipConfig.tooltip_font = value
        else
            REALG.TacoTipConfig.tooltip_border_texture = value
        end
        if (TT.InvalidateResolvedMediaCache) then TT:InvalidateResolvedMediaCache() end
    end

    -- ---- FIX 1: the portrait side cache is never invalidated -------------
    --
    -- The side is cached in tooltip state and only recomputed when the cache is
    -- absent, the scale changed, or the tooltip is shown and not yet anchored.
    -- Nothing in the addon ever cleared those two fields, so `portraitAnchored`
    -- latched true for the life of the GameTooltip frame and the side froze
    -- until /reload. The clear is the right epoch: a clear is exactly the
    -- moment the tooltip is recycled, so the next show is a genuinely new
    -- layout and recomputing from that frame is correct by construction.
    --
    -- The production boundary is `tooltipRight >= screenWidth` -- the tooltip's
    -- RIGHT EDGE against the screen's, not the screen's midpoint. A tooltip
    -- pinned at the right edge takes the "left" portrait side; one anywhere
    -- left of it takes "right". The two positions below straddle that boundary
    -- deliberately rather than sitting at 0.8x and 0.2x, which would land on the
    -- same side of it and could not detect a frozen cache.
    do
        REALG.TacoTipConfig.tooltip_portrait = true
        REALG.TacoTipConfig.tooltip_portrait_3d = true

        local uiPrev = REALG.UIParent.__right
        REALG.UIParent.__right = SCREEN_W

        local function anchorPoint()
            local p = GT.TacoTipPortrait3D
            if (p and p.GetNumPoints and p:GetNumPoints() > 0) then
                return select(1, p:GetPoint(1))
            end
            return nil
        end

        -- Position 1: the tooltip's right edge sits past the screen's right edge.
        -- A recycle FIRST, so the anchor under test is genuinely the first one
        -- taken at this position. Without it the portrait is still carrying the
        -- anchor an earlier test left it with (the teardown tests above already
        -- anchored it at the mock's default GetRight of 0), and point1 would be
        -- that stale anchor rather than anything this position produced.
        pcall(TT.clearTooltipVisuals, GT)
        GT.__right = SCREEN_W + 60
        settlePair(2)
        local anchorsAfterFirst = (TT.ev and TT.ev.portraitAnchor) or 0
        local firstPoint = anchorPoint()

        -- The recycle: what the game does between two unit hovers.
        if (GT.__hooks and GT.__hooks.OnTooltipCleared) then
            pcall(GT.__hooks.OnTooltipCleared, GT)
        end

        -- Position 2: the same frame, tooltip now well left of the right edge.
        GT.__right = math.floor(SCREEN_W * 0.4)
        settlePair(2)
        local anchorsAfterSecond = (TT.ev and TT.ev.portraitAnchor) or 0
        local secondPoint = anchorPoint()

        check("portrait exists for the side-flip test", GT.TacoTipPortrait3D ~= nil)
        check("portrait side is recomputed after a clear, not frozen for the session",
            anchorsAfterSecond > anchorsAfterFirst,
            "portraitAnchor " .. tostring(anchorsAfterFirst) .. " -> " .. tostring(anchorsAfterSecond))
        check("portrait moves to the other side after a clear",
            firstPoint ~= nil and secondPoint ~= nil and firstPoint ~= secondPoint,
            "point1=" .. tostring(firstPoint) .. " point2=" .. tostring(secondPoint))
        check("the new side is the one the new position calls for",
            secondPoint == "TOPLEFT",
            "got " .. tostring(secondPoint) .. " (a tooltip whose right edge is "
            .. tostring(GT.__right) .. " of " .. tostring(SCREEN_W) .. " takes TOPLEFT)")

        GT.__right = 0
        REALG.UIParent.__right = uiPrev
    end

    -- ---- Portrait base dimensions and exact 3:4 --------------------------
    local function currentAnchorPoint()
        local p = GT.TacoTipPortrait3D
        if (p and p.GetNumPoints and p:GetNumPoints() > 0) then
            return select(1, p:GetPoint(1))
        end
        return nil
    end

    do
        local prevScale = REALG.TacoTipConfig.tooltip_portrait_scale
        -- Both base numbers must be even so that every slider stop lands on an
        -- exact integer: the slider runs 50..200 step 5, so a half stop and a
        -- 1.5 stop are both in range and both divide/multiply by 2.
        local expected = {
            { scale = 0.50, w = 33,  h = 44 },
            { scale = 1.00, w = 66,  h = 88 },
            { scale = 1.50, w = 99,  h = 132 },
            { scale = 2.00, w = 132, h = 176 },
        }
        for _, case in ipairs(expected) do
            REALG.TacoTipConfig.tooltip_portrait_scale = case.scale
            pcall(TT.clearTooltipVisuals, GT)
            settlePair(2)
            local p = GT.TacoTipPortrait3D
            local w = p and p.__w
            local h = p and p.__h
            check(string.format("portrait is %dx%d at scale %.2f", case.w, case.h, case.scale),
                w == case.w and h == case.h,
                "got " .. tostring(w) .. "x" .. tostring(h))
            -- Ratio is the point of "keep 3:4": w:h must be exactly 3:4, so
            -- 4*w must equal 3*h with no rounding tolerance at all.
            check(string.format("portrait keeps an exact 3:4 ratio at scale %.2f", case.scale),
                w ~= nil and h ~= nil and (w * 4) == (h * 3),
                string.format("%s x %s -> 4w=%d 3h=%d", tostring(w), tostring(h),
                    w and (w * 4) or -1, h and (h * 3) or -1))
        end
        REALG.TacoTipConfig.tooltip_portrait_scale = prevScale
        pcall(TT.clearTooltipVisuals, GT)
        settlePair(2)
    end

    -- ---- Invert portrait side (option, default off) ----------------------
    do
        -- Captured here, not borrowed from the side-flip block above: that one is
        -- scoped to its own `do`, so reaching for its local silently restored
        -- to nil and leaked a moved UIParent.__right into every later test.
        local uiPrev = REALG.UIParent.__right
        local prevInvert = REALG.TacoTipConfig.tooltip_portrait_invert_side
        check("invert portrait side defaults to off",
            prevInvert == nil or prevInvert == false,
            "got " .. tostring(prevInvert))

        -- Tooltip anchored past the right edge normally takes the LEFT side.
        REALG.UIParent.__right = SCREEN_W
        GT.__right = SCREEN_W + 60
        REALG.TacoTipConfig.tooltip_portrait_invert_side = false
        pcall(TT.clearTooltipVisuals, GT)
        settlePair(2)
        local normalPoint = currentAnchorPoint()

        -- Ticking the option must move the portrait IMMEDIATELY. The side is
        -- cached per tooltip, so this only happens if the invert flag is part of
        -- that cache key -- without it the checkbox looks dead until the user
        -- changes scale or hovers again.
        REALG.TacoTipConfig.tooltip_portrait_invert_side = true
        settlePair(2)
        local invertedPoint = currentAnchorPoint()

        check("portrait sits at TOPRIGHT when the tooltip is past the right edge",
            normalPoint == "TOPRIGHT",
            "got " .. tostring(normalPoint))
        check("inverting the portrait side moves it",
            invertedPoint ~= nil and invertedPoint ~= normalPoint,
            "off=" .. tostring(normalPoint) .. " on=" .. tostring(invertedPoint))
        check("inverting the portrait side moves it on the very next render",
            invertedPoint == "TOPLEFT",
            "got " .. tostring(invertedPoint) .. " (wanted TOPLEFT)")

        -- And back off again.
        REALG.TacoTipConfig.tooltip_portrait_invert_side = false
        settlePair(2)
        check("clearing invert restores the original side",
            currentAnchorPoint() == normalPoint,
            "got " .. tostring(currentAnchorPoint()) .. " (wanted " .. tostring(normalPoint) .. ")")

        REALG.TacoTipConfig.tooltip_portrait_invert_side = prevInvert
        GT.__right = 0
        REALG.UIParent.__right = uiPrev
    end

    -- ---- FIX 2: SetFont re-applied to every line on every render ---------
    --
    -- applyTooltipFonts walks max(numLines + 4, 20) lines and called SetFont on
    -- each, unconditionally. On top of the call cost it runs AFTER the SetText
    -- loop, so every call invalidated the text measurement that loop had just
    -- produced. The guard mirrors the idiom applyTooltipMaxWidth already uses
    -- for width: remember what was applied, write only on a change.
    --
    -- The paired assertion is what stops this being satisfied by a guard that
    -- simply never sets the font.
    do
        settlePair(PAIR)
        local baseFonts = REALG.__fontCalls or 0
        local wantFont = REALG.TacoTip_Forever:GetResolvedTooltipFont()
        local wantSize = REALG.TacoTipConfig.tooltip_font_size
        -- Line 1 is the NAME and is rendered one step larger than body text.
        local wantNameSize = wantSize + TOOLTIP_NAME_FONT_SIZE_DELTA

        settlePair(PAIR)
        local l1 = line1()
        local addedFonts = (REALG.__fontCalls or 0) - baseFonts

        check("a settled re-render re-applies SetFont to no line",
            addedFonts == 0,
            "added " .. tostring(addedFonts) .. " SetFont call(s) over " .. tostring(PAIR) .. " renders")
        check("the font WAS applied, so the guard skips a repeat and not everything",
            l1 ~= nil and l1.__font == wantFont and l1.__fontSize == wantNameSize,
            "line1 font=" .. tostring(l1 and l1.__font) .. " size=" .. tostring(l1 and l1.__fontSize)
            .. " (wanted " .. tostring(wantFont) .. " / " .. tostring(wantNameSize) .. ")")

        -- Body lines must NOT have been dragged up with the name. Without this
        -- the bump could be applied to every line and still pass the check above.
        local l2 = lineN(2)
        check("line 2 stays at the configured body size",
            l2 ~= nil and l2.__fontSize == wantSize,
            "line2 size=" .. tostring(l2 and l2.__fontSize) .. " (wanted " .. tostring(wantSize) .. ")")

        -- The name/body relationship, as a literal. The check above compares
        -- against a copy of the constant in main.lua, so it cannot fail when
        -- the constant itself is edited. The name sits one point above the
        -- body text, and that is the shipped value.
        check("the name line sits 2pt above the body text",
            l1 ~= nil and l2 ~= nil and l1.__fontSize == l2.__fontSize + SHIPPED_NAME_FONT_SIZE_DELTA,
            "line1 size=" .. tostring(l1 and l1.__fontSize) .. " line2 size=" .. tostring(l2 and l2.__fontSize)
            .. " (wanted line1 = line2 + " .. tostring(SHIPPED_NAME_FONT_SIZE_DELTA) .. ")")

        -- The guard must not be a one-way latch: a changed setting has to write
        -- through on the next render.
        local probe, prevFont = mediaProbe("font")
        if (probe) then
            setMedia("font", probe)
            local probeBase = REALG.__fontCalls or 0
            settlePair(PAIR)
            l1 = line1()
            check("changing the font setting re-applies SetFont",
                (REALG.__fontCalls or 0) > probeBase and l1 ~= nil and l1.__font == probe,
                "calls added=" .. tostring((REALG.__fontCalls or 0) - probeBase)
                .. " line1 font=" .. tostring(l1 and l1.__font) .. " (wanted " .. tostring(probe) .. ")")
            setMedia("font", prevFont)
        else
            -- Reported rather than counted as a pass: with one font in the list
            -- there is no second value to switch to, and silently passing would
            -- hide that the latch case is untested here.
            check("changing the font setting re-applies SetFont", false,
                "no alternative font in the choice list to switch to")
        end
        setMedia("font", REALG.TacoTipConfig.tooltip_font)
    end

    -- ---- FIX 3: SetBackdrop re-tiled the border on every render ---------
    --
    -- Both branches rebuilt a backdropInfo table plus a nested insets table and
    -- handed them to SetBackdrop, which reassigns its backdrop, re-applies both
    -- colours and re-tiles the edge texture. None of that depends on the render:
    -- it depends only on the border texture, the edge size and -- on the legacy
    -- branch only -- the background texture. tooltip_border_alpha is deliberately
    -- NOT part of that input, because it is applied by SetBackdropBorderColor,
    -- which is a different call.
    do
        local CFG = REALG.TacoTipConfig
        local prevBorder = CFG.tooltip_border_texture
        local prevAlpha = CFG.tooltip_border_alpha

        settlePair(PAIR)
        -- The NineSlice branch is the one every supported client takes, so the
        -- backdrop frame is our own overlay rather than the tooltip itself.
        local backdrop = GT.TacoTipBackdropFrame
        check("backdrop overlay frame exists for the re-tile test", backdrop ~= nil)

        if (backdrop) then
            local base = backdrop.__backdropCalls or 0
            settlePair(PAIR)
            local addedSame = (backdrop.__backdropCalls or 0) - base
            check("a settled re-render does not re-tile the backdrop",
                addedSame == 0, "added " .. tostring(addedSame) .. " SetBackdrop call(s)")
            check("the backdrop WAS set, so the guard skips a repeat and not everything",
                (backdrop.__backdropInfo or {}).edgeFile ~= nil,
                "edgeFile=" .. tostring((backdrop.__backdropInfo or {}).edgeFile))

            -- A real change must still write through. This is what separates a
            -- comparison from "never call SetBackdrop again".
            local probe = mediaProbe("border")
            if (probe) then
                local before = backdrop.__backdropCalls or 0
                setMedia("border", probe)
                settlePair(PAIR)
                local addedBorder = (backdrop.__backdropCalls or 0) - before
                local info = backdrop.__backdropInfo or {}
                check("changing the border texture re-tiles the backdrop",
                    addedBorder > 0,
                    "added " .. tostring(addedBorder) .. " SetBackdrop call(s), edgeFile="
                    .. tostring(info.edgeFile))
                check("the re-tile carries the new border path",
                    info.edgeFile == probe,
                    "edgeFile=" .. tostring(info.edgeFile) .. " (wanted " .. tostring(probe) .. ")")
                setMedia("border", prevBorder)
                -- Settle before the next measurement. Without this the baseline
                -- below is captured while the backdrop still carries the PROBE's
                -- signature, so the first render of the alpha pair legitimately
                -- re-tiles back to prevBorder and the alpha assertion fails on
                -- the previous test's leftover.
                settlePair(PAIR)
            else
                check("changing the border texture re-tiles the backdrop", false,
                    "no alternative border in the choice list to switch to")
            end

            -- Alpha travels through SetBackdropBorderColor, not SetBackdrop, so
            -- changing it must NOT re-tile -- and must still take effect.
            local alphaBase = backdrop.__backdropCalls or 0
            CFG.tooltip_border_alpha = 0.42
            settlePair(PAIR)
            local addedAlpha = (backdrop.__backdropCalls or 0) - alphaBase
            local bc = backdrop.__borderColor
            check("changing only the border alpha does not re-tile",
                addedAlpha == 0, "added " .. tostring(addedAlpha) .. " SetBackdrop call(s)")
            check("the new border alpha was still applied",
                bc ~= nil and math.abs((bc[4] or 0) - 0.42) < 0.0001,
                "alpha=" .. tostring(bc and bc[4]))
            CFG.tooltip_border_alpha = prevAlpha
        end
    end

    -- ---- The border thickness must match the SHIPPED default -------------
    --
    -- The shipped default is 20 (options.lua DEFAULTS.tooltip_border_edge_size
    -- = 20, and ApplyConfigDefaults copies it into a fresh profile). main.lua's
    -- LAST-RESORT literal was 16, and it is the literal a player gets whose
    -- SavedVariables carry no edge size at all -- while the description string
    -- in the options panel promised a different number again.
    --
    -- The chain in main.lua is: the resolver (TT:GetResolvedTooltipBorderEdgeSize)
    -- -> the player's own setting -> the literal. This exercises the LAST link,
    -- so both earlier links are taken away for the duration, and the backdrop
    -- signature is cleared so the frame re-tiles instead of skipping the call.
    do
        local CFG = REALG.TacoTipConfig
        local backdrop = GT.TacoTipBackdropFrame
        local savedResolver = TT.GetResolvedTooltipBorderEdgeSize
        local savedSize = CFG.tooltip_border_edge_size
        local savedSig = backdrop and backdrop._tacoTipBackdropSig
        CFG.tooltip_border_edge_size = nil
        TT.GetResolvedTooltipBorderEdgeSize = nil
        if (backdrop) then backdrop._tacoTipBackdropSig = nil end
        settlePair(PAIR)
        local info = (backdrop and backdrop.__backdropInfo) or {}
        check("the border edge size falls back to the shipped default (16)",
            info.edgeSize == 16, "edgeSize=" .. tostring(info.edgeSize))
        TT.GetResolvedTooltipBorderEdgeSize = savedResolver
        CFG.tooltip_border_edge_size = savedSize
        if (backdrop) then backdrop._tacoTipBackdropSig = savedSig end
    end

    -- ---- FIX 4: tooltip_max_width never reached item tooltips -----------
    --
    -- applyTooltipMaxWidth had exactly one call site and it was inside
    -- onTooltipSetUnit. The item path applied the font, the backdrop and the
    -- border overlay but not the width cap, so the one tooltip type that
    -- reliably carries a long line was the one type the option did nothing for.
    --
    -- The cap is set explicitly: the shipped default is 0, and asserting a cap
    -- of 0 would pass whether or not the call site exists at all.
    do
        local CFG = REALG.TacoTipConfig
        local prevMax = CFG.tooltip_max_width
        CFG.tooltip_max_width = 300

        GT:ClearLines()
        GT:AddLine(ITEM[1].name)
        GT:AddLine("Item Level 88")
        if (POSTCALLS and POSTCALLS[2]) then
            POSTCALLS[2].fn(GT, { hyperlink = ITEM[1].link })
        elseif (GT.__hooks and GT.__hooks.OnTooltipSetItem) then
            GT.__hooks.OnTooltipSetItem(GT, ITEM[1].link)
        end

        local itemLine = line1()
        check("item tooltip honours tooltip_max_width",
            itemLine ~= nil and itemLine._tacoTipMaxWidth == 300,
            "line1 _tacoTipMaxWidth=" .. tostring(itemLine and itemLine._tacoTipMaxWidth)
            .. " (wanted 300)")

        -- The unit path must still cap, or "both call it" could be satisfied by
        -- removing the original call site instead of adding the second one.
        settlePair(PAIR)
        local unitLine = line1()
        check("unit tooltip still honours tooltip_max_width",
            unitLine ~= nil and unitLine._tacoTipMaxWidth == 300,
            "line1 _tacoTipMaxWidth=" .. tostring(unitLine and unitLine._tacoTipMaxWidth))

        CFG.tooltip_max_width = prevMax
        settlePair(PAIR)
    end

    -- ---- FIX 5: a throwaway table per power update -----------------------
    --
    -- `PowerBarColor[power] or {}` allocated a table on every update for any
    -- power token PowerBarColor does not key, and Update runs on
    -- UNIT_POWER_UPDATE, UNIT_MAXPOWER, UNIT_DISPLAYPOWER and once per render --
    -- the hottest allocation in an otherwise zero-allocation path.
    --
    -- Asserted as a GC delta across N updates rather than as behaviour, because
    -- a behavioural assertion passes both before and after and is therefore not
    -- evidence of anything. The behavioural half of the pair is kept too, so the
    -- fix cannot be satisfied by dropping the colour.
    do
        local CFG = REALG.TacoTipConfig
        local prevPower = CFG.show_power_bar
        local prevMax = CFG.tooltip_max_width
        CFG.show_power_bar = true
        CFG.tooltip_max_width = 0

        settlePair(PAIR)
        local bar = REALG.TacoTipPowerBar
        check("power bar exists for the allocation test", bar ~= nil)

        if (bar and bar.Update) then
            -- The addon reads the SECOND return of UnitPowerType -- the power
            -- TOKEN -- as the PowerBarColor key, so the probe has to hand back an
            -- unkeyed token to reach the `or {}` branch at all. The mock keys
            -- PowerBarColor by the numeric type 0 and answers UnitPowerType with
            -- a single value, so a first attempt at this probe returned 0, hit
            -- the keyed colour, and read back 0.3/0.3/0.8 instead of the
            -- fallback. That was a broken test, not a broken addon.
            local N = 20
            -- Two measurements, and why not a KB limit.
            --
            -- A fixed threshold does not survive the interpreter: the same fixed
            -- code measured 3.44 KB on lua5.1, 2.19 KB on lua5.4 and 2.30 KB on
            -- luajit over 20 updates, and the luajit figure is mostly one-off JIT
            -- compilation. Subtracting a hand-written control loop fixed most of
            -- that but not all -- under luajit roughly 0.10 KB per update of
            -- interpreter overhead survives it, because the control does not make
            -- the same calls (no UnitPowerType, no `or`), so it is not
            -- equivalent work.
            --
            -- What does isolate the defect exactly is measuring the SAME closure
            -- twice and changing only the power token:
            --   * token 0 is a key of the mock's PowerBarColor, so the lookup
            --     SUCCEEDS and the old `or {}` never runs;
            --   * the probe token is not a key, so the old `or {}` runs once per
            --     update and allocates one five-field table.
            -- Everything else -- the call, the UnitPowerType lookup, the colour
            -- read, the three widget writes -- is identical, on the same
            -- interpreter, in the same run. So the difference between the two is
            -- the fallback expression and nothing else, and the fixed code has
            -- no reason for it to be anything but zero.
            local function measure(n)
                collectgarbage("collect")
                collectgarbage("collect")
                local before = collectgarbage("count")
                for _ = 1, n do bar:Update("player") end
                return collectgarbage("count") - before
            end

            local prevPowerType = REALG.UnitPowerType
            local function withToken(token)
                REALG.UnitPowerType = function() return 0, token end
            end

            -- The addon reads the SECOND return of UnitPowerType -- the power
            -- TOKEN -- as the PowerBarColor key, so the probe has to hand back an
            -- unkeyed token to reach the `or {}` branch at all. The mock keys
            -- PowerBarColor by the numeric type 0 and answers UnitPowerType with
            -- a single value, so a first attempt at this probe returned 0, hit
            -- the keyed colour, and read back 0.3/0.3/0.8 instead of the
            -- fallback. That was a broken test, not a broken addon.
            local KEYED, UNKEYED = 0, "TT_TOKEN_NOT_A_POWER_TYPE"

            withToken(KEYED)
            measure(N) -- warm up any lazy state
            local keyed1 = measure(N)
            local keyed4 = measure(N * 4)
            withToken(UNKEYED)
            local unkeyed1 = measure(N)
            local unkeyed4 = measure(N * 4)

            -- KB per update, for each token, above whatever both share.
            local perKeyed = (keyed4 - keyed1) / (N * 3)
            local perUnkeyed = (unkeyed4 - unkeyed1) / (N * 3)
            local perFallback = perUnkeyed - perKeyed

            -- Scale: what one table of this shape actually costs here.
            local sink = {}
            local function reference()
                -- Stored so the table is reachable and cannot be elided; read back
                -- at the end purely so the local is not write-only.
                sink[1] = { r = 0, g = 0, b = 1 }
            end
            local function measureRef(n)
                collectgarbage("collect")
                collectgarbage("collect")
                local before = collectgarbage("count")
                for _ = 1, n do reference() end
                return collectgarbage("count") - before
            end
            local perAlloc = (measureRef(N * 4) - measureRef(N)) / (N * 3)
            local sinkKept = (sink[1] ~= nil) -- see reference() above

            -- `perAlloc <= 0` means the collector does not account for the
            -- reference at all, so there is no scale to measure against and no
            -- honest way to assert it here. The condition says so in its detail
            -- rather than passing a threshold that measured nothing; the
            -- behavioural half of the pair below still runs everywhere.
            --
            -- MEASURED, and worth knowing before anyone tightens this: with the
            -- `or {}` restored this check fails 4/4 on lua5.1 and 4/4 on lua5.4,
            -- and passes 4/4 on luajit. LuaJIT's JIT removes the table before it
            -- exists -- it is constructed, read three times and dropped inside
            -- one basic block, so it never escapes and is never allocated. There
            -- is no assertion that can see a defect the interpreter has already
            -- optimised away. lua5.1 is what WoW ships, so that is the
            -- measurement that counts; luajit is a cross-check, not the target.
            check("power updates allocate no garbage per update",
                sinkKept and (perAlloc <= 0 or perFallback < (perAlloc * 0.25)),
                string.format(
                    "unkeyed %.4f KB/update minus keyed %.4f KB/update = %.4f KB of fallback,"
                    .. " against %.4f KB per table%s",
                    perUnkeyed, perKeyed, perFallback, perAlloc,
                    perAlloc <= 0 and " -- UNAVAILABLE on this interpreter: the collector "
                    .. "does not account for the reference either" or ""))

            local sc = { bar.__statusR, bar.__statusG, bar.__statusB }
            check("an unkeyed power token still gets the fallback colour",
                bar.__statusR ~= nil and math.abs(bar.__statusR) < 0.0001
                and math.abs(bar.__statusG) < 0.0001
                and math.abs(bar.__statusB - 1) < 0.0001,
                "colour=" .. tostring(sc and table.concat(sc, ",")))

            REALG.UnitPowerType = prevPowerType
        end
        CFG.tooltip_max_width = prevMax
        CFG.show_power_bar = prevPower
    end

    -- ---- FIX 6: unconditional layout writes ------------------------------
    --
    -- The power bar re-asserted both of its anchors every render, the tooltip's
    -- padding was re-set every render (SetPadding re-lays out the tooltip), and
    -- the clamp insets were set with no guard at all. All three are idempotent
    -- in effect and expensive in practice. GetMinimumWidth a few lines below the
    -- clamp already had the right shape: read the current value, write on a
    -- change.
    do
        local CFG = REALG.TacoTipConfig
        local prevHP, prevPower = CFG.show_hp_bar, CFG.show_power_bar
        local prevMax = CFG.tooltip_max_width
        CFG.show_hp_bar = true
        CFG.show_power_bar = true
        CFG.tooltip_max_width = 0

        settlePair(PAIR)
        local bar = REALG.TacoTipPowerBar

        local basePoints = (bar and bar.__setPointCalls) or 0
        local basePad = GT.__paddingCalls or 0
        local baseClamp = GT.__clampCalls or 0

        settlePair(PAIR)

        local addedPoints = ((bar and bar.__setPointCalls) or 0) - basePoints
        local addedPad = (GT.__paddingCalls or 0) - basePad
        local addedClamp = (GT.__clampCalls or 0) - baseClamp

        check("a settled re-render re-anchors the power bar 0 times",
            addedPoints == 0, "added " .. tostring(addedPoints) .. " SetPoint call(s)")
        check("a settled re-render re-sets the tooltip padding 0 times",
            addedPad == 0, "added " .. tostring(addedPad) .. " SetPadding call(s)")
        check("a settled re-render re-sets the clamp insets 0 times",
            addedClamp == 0, "added " .. tostring(addedClamp) .. " SetClampRectInsets call(s)")

        -- Paired: the values must actually be on the frame, or a guard that never
        -- wrote anything would pass the three checks above.
        check("the power bar IS anchored",
            bar ~= nil and (bar.__setPointCalls or 0) >= 2,
            "SetPoint calls=" .. tostring(bar and bar.__setPointCalls))
        check("the tooltip padding WAS set",
            GT.__padding ~= nil and (GT.__padding[2] or 0) == 10,
            "padding=" .. tostring(GT.__padding and table.concat(GT.__padding, ",")))
        check("the clamp insets WERE set",
            GT.__clampInsets ~= nil and (GT.__clampInsets[3] or 0) == 15,
            "insets=" .. tostring(GT.__clampInsets and table.concat(GT.__clampInsets, ",")))

        -- A real change must write through on the next render, or these guards
        -- are latches rather than comparisons.
        local hpBase = (bar and bar.__setPointCalls) or 0
        CFG.show_hp_bar = false
        settlePair(PAIR)
        check("turning off the HP bar re-anchors the power bar",
            ((bar and bar.__setPointCalls) or 0) > hpBase,
            "SetPoint calls " .. tostring(hpBase) .. " -> " .. tostring(bar and bar.__setPointCalls))
        CFG.show_hp_bar = prevHP
        settlePair(PAIR)

        -- (d) The wide-style continuation line. This branch only runs when
        -- tip_style makes wide_style true, and the rest of this file pins
        -- tip_style = 3, so without switching it here the anchor at main.lua:1968
        -- is never executed at all and a guard on it would be untested code
        -- wearing a test's clothes.
        do
            local prevStyle = CFG.tip_style
            CFG.tip_style = 1
            -- Render with a chosen number of stock lines. The pooled line the
            -- branch anchors is the one AFTER the last rendered line, so the
            -- line count decides which pooled FontString is involved -- changing
            -- it is also how the write-through below is provoked.
            local function renderWithLines(count)
                GT.__shown = true
                currentUnit = "player"
                installUnitResolver()
                GT:ClearLines()
                for i = 1, count do GT:AddLine("stock line " .. i) end
                local u = UNITS[currentUnit]
                local guid = (u and u.guid) or "Player-1-00000001"
                if (POSTCALLS and POSTCALLS[1]) then
                    POSTCALLS[1].fn(GT, { guid = guid })
                elseif (GT.__hooks and GT.__hooks.OnTooltipSetUnit) then
                    GT.__hooks.OnTooltipSetUnit(GT, guid)
                end
            end
            local function lineAnchorWrites()
                local pool = rawget(GT, "__linePool") or {}
                local total = 0
                for i = 1, 20 do
                    local fs = pool[i]
                    total = total + ((fs and rawget(fs, "__setPointCalls")) or 0)
                end
                return total
            end

            for _ = 1, PAIR do renderWithLines(6) end
            local wideBase = lineAnchorWrites()
            check("the wide-style branch runs and anchors a line",
                wideBase > 0, "line SetPoint calls=" .. tostring(wideBase))

            for _ = 1, PAIR do renderWithLines(6) end
            local addedSame = lineAnchorWrites() - wideBase
            check("a settled wide-style re-render re-anchors the continuation line 0 times",
                addedSame == 0, "added " .. tostring(addedSame) .. " line SetPoint call(s)")

            -- A different line count means a different pooled line AND a
            -- different anchor line, so the guard has to write. This is what
            -- separates a comparison from a latch.
            local shortBase = lineAnchorWrites()
            for _ = 1, PAIR do renderWithLines(3) end
            local addedShort = lineAnchorWrites() - shortBase
            check("a wide-style render with a different line count re-anchors",
                addedShort > 0, "added " .. tostring(addedShort) .. " line SetPoint call(s)")

            CFG.tip_style = prevStyle
            for _ = 1, PAIR do settleUnitRender("player") end
        end

        CFG.tooltip_max_width = prevMax
        CFG.show_power_bar = prevPower
    end

    -- A SAVED CUSTOM POSITION MUST SURVIVE THE RENDER.
    --
    -- The SetDefaultAnchor post-hook cannot own this: the client calls it
    -- immediately BEFORE GameTooltip:SetUnit (classic_era UnitFrame.lua,
    -- live Mainline/UnitFrame.lua:390-391), so the tooltip still describes the
    -- previous unit and the gate reads a world unit as "menu". The render runs
    -- after SetUnit, so the anchor is applied there -- this pin is that path.
    -- Revert map: delete the applyCustomTooltipAnchor call at the end of
    -- TT:ApplyTooltipAppearance -> this pin goes red.
    -- NOTE: Reverted on 2026-10-23 (unmerged experimental prototype).
    -- applyCustomTooltipAnchor at the end of ApplyTooltipAppearance, getPortraitSideRightEdge,
    -- and deferred post-layout portrait flip guards were unmerged prototypes.
    --[[
    do
        local CFG = REALG.TacoTipConfig
        local prevPos, prevAnchor = CFG.custom_pos, CFG.custom_anchor
        local prevMouse, prevPower = CFG.anchor_mouse, CFG.show_power_bar
        CFG.anchor_mouse = false
        CFG.show_power_bar = false
        CFG.custom_pos = { "BOTTOMLEFT", "BOTTOMLEFT", 300, 200 }
        CFG.custom_anchor = "TOPLEFT"
        if (type(REALG.TacoTip_CustomPosEnable) == "function") then
            pcall(REALG.TacoTip_CustomPosEnable, false)
        end
        local handle = REALG.TacoTipDragButton
        check("a saved custom position creates the handle", handle ~= nil)

        local renderTip = REALG.GameTooltip
        local savedSetPoint = renderTip.SetPoint
        local captured = {}
        renderTip.SetPoint = function(self, p, rel, rp, ox, oy)
            captured[#captured + 1] = { p = p, rel = rel, rp = rp }
            return savedSetPoint(self, p, rel, rp, ox, oy)
        end
        settlePair(PAIR)
        renderTip.SetPoint = savedSetPoint

        local anchoredToHandle, anchorName = false, nil
        for _, c in ipairs(captured) do
            if (handle and c.rel == handle) then
                anchoredToHandle, anchorName = true, c.p
            end
        end
        check("the tooltip is anchored to the saved position after the unit is known",
            anchoredToHandle and anchorName == "TOPLEFT",
            "handle=" .. tostring(handle ~= nil) .. " anchored=" .. tostring(anchoredToHandle)
            .. " point=" .. tostring(anchorName))

        CFG.custom_pos, CFG.custom_anchor = prevPos, prevAnchor
        CFG.anchor_mouse, CFG.show_power_bar = prevMouse, prevPower
    end

    -- THE PORTRAIT FLIP MUST MEASURE THE SAVED POSITION, NOT THE CLIENT'S.
    --
    -- The side is decided inside the render, but the saved anchor is applied at
    -- the END of it, so tooltip:GetRight() at decision time is still the rect the
    -- CLIENT produced (classic_era GameTooltip_SetDefaultAnchor anchors
    -- BOTTOMRIGHT of UIParent; live anchors to the owner). The decision therefore
    -- said "right", the save then moved the tooltip to the edge, and the portrait
    -- hung off the screen -- the operator's "it used to flip to the left when it
    -- went off screen, now it just pulls it off screen". The edge now comes from
    -- the anchor target, which is known here.
    --
    -- Revert map: getPortraitSideRightEdge -> tooltip:GetRight() -> the
    -- right-edge case goes red (the portrait stays on TOPLEFT).
    do
        local CFG = REALG.TacoTipConfig
        local prevPos, prevAnchor = CFG.custom_pos, CFG.custom_anchor
        local prevMouse = CFG.anchor_mouse
        local prevPortrait, prev3D = CFG.tooltip_portrait, CFG.tooltip_portrait_3d
        local uiPrev = REALG.UIParent.__right
        CFG.anchor_mouse = false
        CFG.tooltip_portrait = true
        CFG.tooltip_portrait_3d = true
        CFG.custom_anchor = "TOPLEFT"
        CFG.custom_pos = { "BOTTOMLEFT", "BOTTOMLEFT", 1700, 400 }
        if (type(REALG.TacoTip_CustomPosEnable) == "function") then
            pcall(REALG.TacoTip_CustomPosEnable, false)
        end
        local handle = REALG.TacoTipDragButton
        check("a saved position creates the handle for the side-flip test", handle ~= nil)

        REALG.UIParent.__right = SCREEN_W
        -- The client's own rect: the one the old code measured, safely inside the
        -- screen. Only the anchor target puts the tooltip at the edge.
        GT.__right = 0
        GT.__w = 600
        handle.__left = 1700

        local function portraitPoint()
            local p = GT.TacoTipPortrait3D
            if (p and p.GetNumPoints and p:GetNumPoints() > 0) then
                return select(1, p:GetPoint(1))
            end
            return nil
        end

        local function recycleTooltip()
            if (GT.__hooks and GT.__hooks.OnTooltipCleared) then
                pcall(GT.__hooks.OnTooltipCleared, GT)
            end
        end

        recycleTooltip()
        settlePair(2)
        local edgePoint = portraitPoint()
        check("a saved position at the screen edge flips the portrait to the left",
            edgePoint == "TOPRIGHT",
            "point=" .. tostring(edgePoint) .. " (handle left 1700 + width 600 vs screen "
            .. tostring(SCREEN_W) .. ")")

        -- The same mechanism, nowhere near the edge: the portrait must stay on the
        -- right. Without this the check above would pass on a hardcoded "left".
        recycleTooltip()
        handle.__left = 100
        settlePair(2)
        local innerPoint = portraitPoint()
        check("a saved position inside the screen keeps the portrait on the right",
            innerPoint == "TOPLEFT",
            "point=" .. tostring(innerPoint))

        -- The stuck case: a SECOND hover on the same GameTooltip, wider than the
        -- first, with no recycle in between. The side is cached, so it can only
        -- move if the edge it is measured from is part of the cache key -- that
        -- key is what this pins. Without it the first hover looked right and every
        -- later one kept the first hover's side.
        -- Widths stay within the hard ceiling (320): at handle 1600 a 200-wide
        -- tooltip ends at 1800 (portrait fits right) while a 320-wide one ends
        -- at 1920 (tooltip + portrait no longer fits, flips left).
        handle.__left = 1600
        GT.__w = 200
        settleUnitRender("player")
        GT.__w = 320
        settleUnitRender("player")
        local widenPoint = portraitPoint()
        check("a wider tooltip re-decides the portrait side without a recycle",
            widenPoint == "TOPRIGHT",
            "point=" .. tostring(widenPoint) .. " (handle left 1600 + width 320 vs screen "
            .. tostring(SCREEN_W) .. ")")

        -- Rows appended AFTER the render (TacoTip Extras appends exactly this way)
        -- grow the tooltip once the width has already been measured. OnShow is the
        -- re-decision point: the frame is laid out and every line is in.
        -- Same ceiling math: 1600 + 200 fits right, 1600 + 320 flips left.
        recycleTooltip()
        handle.__left = 1600
        GT.__w = 200
        settleUnitRender("player")
        local beforeRows = portraitPoint()
        GT.__w = 320 -- the appended rows widen to the ceiling
        if (GT.__hooks and GT.__hooks.OnShow) then
            pcall(GT.__hooks.OnShow, GT)
        end
        local afterRows = portraitPoint()
        check("rows appended after the render are measured again at Show",
            beforeRows == "TOPLEFT" and afterRows == "TOPRIGHT",
            "before=" .. tostring(beforeRows) .. " after=" .. tostring(afterRows))

        -- Async widening AFTER Show with no re-render and no Show: GearScore
        -- item loads and inspect results complete this way (TacoTip_GSCallback
        -- re-drives UpdateTooltip/SetUnit for the same unit, the tooltip lays
        -- out wider, and the side cache still says "right" because the
        -- predicted edge never changed). The deferred guard measures the
        -- portrait's real rect and flips only on a measured overflow -- the
        -- "fine for a sec, then stretched off screen" report, and the reason a
        -- fresh hover after an idle replays it (the clear resets the side
        -- cache, so the same stale-width decision is made again).
        recycleTooltip()
        handle.__left = 1600
        GT.__w = 200
        local timersBeforeGuard = #TIMERS
        settleUnitRender("player")
        check("a shown portrait schedules the post-layout guard",
            #TIMERS > timersBeforeGuard,
            "no timer scheduled")
        check("portrait starts on the right while everything fits",
            portraitPoint() == "TOPLEFT",
            "point=" .. tostring(portraitPoint()))
        -- The async completion: the client lays out wider and the portrait
        -- ends up past the screen edge, with no render and no Show to notice.
        local guardPortrait = GT.TacoTipPortrait3D
        if (guardPortrait) then
            guardPortrait.__right = SCREEN_W + 10
            guardPortrait.__left = SCREEN_W - 56
        end
        local guardFlipsBefore = (TT.ev and TT.ev.portraitGuardFlip) or 0
        local timersAfterSettle = #TIMERS
        for i = timersBeforeGuard + 1, timersAfterSettle do
            local h = TIMERS[i]
            if (h and type(h.func) == "function") then pcall(h.func) end
        end
        check("the guard flips a measured off-screen portrait left",
            portraitPoint() == "TOPRIGHT",
            "point=" .. tostring(portraitPoint()))
        check("...and counts the flip",
            ((TT.ev and TT.ev.portraitGuardFlip) or 0) == guardFlipsBefore + 1,
            "portraitGuardFlip=" .. tostring((TT.ev and TT.ev.portraitGuardFlip) or 0))

        -- Slow async appends landing after the first guard pass: the pass did
        -- work (capped + flipped), so exactly one bounded follow-up is
        -- scheduled -- never a chain.
        local firstPassTimers = #TIMERS
        check("a guard pass that did work schedules one bounded follow-up",
            firstPassTimers == timersAfterSettle + 1,
            "timers=" .. tostring(firstPassTimers - timersAfterSettle))
        -- Another late line arrives after the first pass fired.
        GT:AddLine("a second slow third-party line that must also be capped")
        local lateLine = GT:GetLeftLine(GT:NumLines())
        local followUp = TIMERS[#TIMERS]
        if (followUp and type(followUp.func) == "function") then
            pcall(followUp.func)
        end
        check("the follow-up caps the line that arrived after the first pass",
            lateLine ~= nil and lateLine._tacoTipMaxWidth == 320,
            "memo=" .. tostring(lateLine and lateLine._tacoTipMaxWidth))
        check("...and the final pass does not chain a third timer",
            #TIMERS == firstPassTimers,
            "timers=" .. tostring(#TIMERS - firstPassTimers))

        -- The follow-up is unconditional: a slow async append can land after a
        -- clean first pass (nothing capped, nothing flipped), and with no
        -- follow-up nothing would re-check until the next hover -- the "first
        -- hover fine, second hover stretched" shape. Fresh hover, no late
        -- lines: firing the idle first pass must still arm exactly one
        -- follow-up, and the idle final pass must arm nothing.
        recycleTooltip()
        handle.__left = 100
        GT.__w = 200
        -- Park the portrait mock back on screen: the flip pin above left it
        -- past the edge on purpose, and this pass must be genuinely idle --
        -- nothing to cap (all memos set), nothing off screen.
        local idlePortrait = GT.TacoTipPortrait3D
        if (idlePortrait) then
            idlePortrait.__right = 300
            idlePortrait.__left = 230
        end
        local idleTimersBefore = #TIMERS
        settleUnitRender("player")
        local idleAfterSettle = #TIMERS
        for i = idleTimersBefore + 1, idleAfterSettle do
            local h = TIMERS[i]
            if (h and type(h.func) == "function") then pcall(h.func) end
        end
        check("an idle first pass still arms the bounded follow-up",
            #TIMERS == idleAfterSettle + 1,
            "timers=" .. tostring(#TIMERS - idleAfterSettle))
        local followTimers = #TIMERS
        local followUpIdle = TIMERS[followTimers]
        if (followUpIdle and type(followUpIdle.func) == "function") then
            pcall(followUpIdle.func)
        end
        check("...and the idle final pass arms nothing further",
            #TIMERS == followTimers,
            "timers=" .. tostring(#TIMERS - followTimers))

        -- Mouse-anchor mode must NOT key on the edge: the cursor follower moves the
        -- tooltip every frame, so an edge key would re-anchor the portrait on every
        -- render -- the per-render anchor 0.7.9 removed.
        CFG.anchor_mouse = true
        GT.__right = 200
        local anchorsBeforeMouse = (TT.ev and TT.ev.portraitAnchor) or 0
        for i = 1, 5 do
            -- The cursor follower moves the tooltip every frame.
            GT.__right = 200 + i * 7
            settleUnitRender("player")
        end
        local mouseAnchors = ((TT.ev and TT.ev.portraitAnchor) or 0) - anchorsBeforeMouse
        check("mouse-anchor mode does not re-anchor the portrait per render",
            mouseAnchors <= 1,
            "anchored " .. tostring(mouseAnchors) .. " time(s) across 5 renders")

        GT.__right = 0
        GT.__w = nil
        handle.__left = 0
        REALG.UIParent.__right = uiPrev
        CFG.custom_pos, CFG.custom_anchor = prevPos, prevAnchor
        CFG.anchor_mouse = prevMouse
        CFG.tooltip_portrait, CFG.tooltip_portrait_3d = prevPortrait, prev3D
        pcall(TT.clearTooltipVisuals, GT)
        settlePair(2)
    end
    --]]

    -- The unit Level label must resolve through TACOTIP_LOCALE rather than being
    -- a hardcoded "|cFFFFFFFFLevel|r". It was hardcoded, and ["Level"] is
    -- translated in all 11 locale files, so the line rendered in English on every
    -- client -- the only unit-tooltip label that bypassed the locale system.
    --
    -- Placed HERE, not in the modern post-call block further down: that block is
    -- `if (usePipeline and POSTCALLS and #POSTCALLS >= 2)`, which Classic never
    -- enters, so a test written there silently covers only 2 of 5 clients. This
    -- block is a top-level `do`, and settleUnitRender drives whichever entry point
    -- the client actually has (post-call on modern, the OnTooltipSetUnit hook on
    -- Classic).
    --
    -- Two claims, proven two ways on purpose:
    --   * sentinel -> the rendered line READS the table; a literal cannot match
    --   * zhCN     -> a real shipped translation flows through
    --                  TacoTipApplyLocale() into the rendered tooltip
    do
        local savedLevel = REALG.TACOTIP_LOCALE["Level"]
        local savedOverride = REALG.TacoTipConfig.locale_override
        local localeOk, localeErr = pcall(function()
            REALG.TACOTIP_LOCALE["Level"] = "LVLSENTINEL"
            settleUnitRender("player")
            local txt = allText()
            check("unit Level label reads TACOTIP_LOCALE (not a hardcoded literal)",
                string.find(txt, "LVLSENTINEL", 1, true) ~= nil,
                string.gsub(txt, "\n", " | "))

            -- ApplyLocale copies INTO the existing TACOTIP_LOCALE table rather
            -- than replacing it, which is why main.lua's file-scope
            -- `local L = _G.TACOTIP_LOCALE` stays valid across a locale switch.
            REALG.TACOTIP_LOCALE["Level"] = savedLevel
            REALG.TacoTipConfig.locale_override = "zhCN"
            if (type(_G.TacoTipApplyLocale) == "function" and REALG.TACOTIP_LOCALES["zhCN"]) then
                _G.TacoTipApplyLocale()
                settleUnitRender("player")
                local zhTxt = allText()
                check("unit Level label renders the active locale's translation",
                    string.find(zhTxt, REALG.TACOTIP_LOCALES["zhCN"]["Level"], 1, true) ~= nil,
                    "zhCN Level=" .. tostring(REALG.TACOTIP_LOCALES["zhCN"]["Level"])
                    .. " got=" .. string.gsub(zhTxt, "\n", " | "))
            end
        end)
        -- Restore unconditionally: every test after this one asserts on English
        -- labels, so a leaked override or sentinel would cascade.
        REALG.TACOTIP_LOCALE["Level"] = savedLevel
        REALG.TacoTipConfig.locale_override = savedOverride
        if (type(_G.TacoTipApplyLocale) == "function") then pcall(_G.TacoTipApplyLocale) end
        check("localized Level label test did not raise", localeOk, tostring(localeErr))
    end

    -- Leave the tooltip in the state the rest of the file expects. The resolver
    -- restore is the LAST thing that happens here: re-installing it afterwards
    -- would pin the tooltip to "player", which the later unit tests resolve
    -- through the mock's own IsUnit fallback and would then fail.
    GT.GetUnit = savedGetUnit
    if (REALG.TooltipUtil) then
        REALG.TooltipUtil.GetDisplayedUnit = savedUtilFn
    end
    currentUnit = "player"
    GT.__right = 0
    GT.__shown = true
    -- Re-seed the tooltip. The pool model above means a line FontString KEEPS
    -- whatever the last render left on it, and clearTooltipLevelColorLine /
    -- clearTooltipGuildLine blank lines 2 and 3 on entry to every render. So
    -- after a render that did not run to completion those lines read back empty
    -- -- and a later render then trips the "player with no level line" guard at
    -- main.lua:1429 and stops early too, which makes the blanking
    -- self-sustaining. Seeding here hands the rest of the file a tooltip with
    -- the full stock line set, which is the state it expects.
    seedTooltip()
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
    if (GT.GetUnit) then
        local _, u = GT:GetUnit(GT); STD.io.write("DEBUG GetUnit()             = " .. tostring(u) .. "\n")
    else STD.io.write("DEBUG GetUnit()             = (no method)\n") end
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
    -- NOTE: Reverted on 2026-10-23 (unmerged experimental prototype).
    -- Production code does not render dual-spec secondary talent readouts on unit tooltips.
    --[[
    local q1, q2, q3 = probeTalentPoints(2)
    check("group 2 reports its own points (31 in tab 2)",
        q1 == 0 and q2 == 31 and q3 == 0,
        "group2=" .. tostring(q1) .. "/" .. tostring(q2) .. "/" .. tostring(q3))
    --]]

    check("active group resolves to group 1", probeActiveGroup() == 1,
        "active=" .. tostring(probeActiveGroup()))
    check("group 1 spec index is tab 1", probeSpecIndex(1) == 1,
        "index=" .. tostring(probeSpecIndex(1)))
    -- check("group 2 spec index is tab 2", probeSpecIndex(2) == 2, "index=" .. tostring(probeSpecIndex(2)))

    -- The rendered readout must contain the point values and a talent icon.
    check("tooltip shows the group 1 readout [21/0/0]",
        string.find(txt, "21/0/0", 1, true) ~= nil,
        string.gsub(txt, "\n", " | "))
    -- check("tooltip shows the group 2 readout [0/31/0]", string.find(txt, "0/31/0", 1, true) ~= nil, string.gsub(txt, "\n", " | "))
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
        STD.io.write("DEBUG CSI.GetTalentInfo  = " ..
        tostring(REALG.C_SpecializationInfo and REALG.C_SpecializationInfo.GetTalentInfo) .. "\n")
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
        return "n", currentUnit, UNITS[currentUnit].guid
    end
    GT.GetUnit = mockGetUnit(currentUnit)
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
    -- Portrait presentation: the two defects that made the 3D portrait strobe on
    -- Retail and WoW Forever. Both trace to the same verified client fact --
    -- TooltipDataHandler fires the tooltip post-calls BEFORE its own self:Show(),
    -- so our whole unit handler runs against a frame that has not been laid out
    -- or presented yet.
    do
        currentUnit = "player"
        REALG.TooltipUtil.GetDisplayedUnit = function()
            return "n", currentUnit, UNITS[currentUnit].guid
        end
        GT.GetUnit = mockGetUnit(currentUnit)
        GT.__unit = "player"
        GT.__shown = true
        GT.__alpha = 0.25 -- a faded tooltip
        REALG.TacoTipConfig.tooltip_portrait = true
        REALG.TacoTipConfig.tooltip_portrait_3d = true

        local anchorsBefore = (TT.ev and TT.ev.portraitAnchor) or 0
        -- Establish the portrait before instrumenting, so creation-time cost is
        -- not counted: the claim under test is about RE-renders.
        GT:ClearLines()
        GT:AddLine("Testplayer")
        GT:AddLine("Level 60 Human")
        GT:AddLine("WARRIOR")
        GT:AddLine("Testguild")
        GT:AddLine("")
        GT:AddLine("HP: 50/50")
        unitPost.fn(GT, { guid = UNITS.player.guid })

        local portraitSetScriptCalls = 0
        local p0 = GT.TacoTipPortrait3D
        if (p0 and p0.SetScript) then
            local realSetScript = p0.SetScript
            p0.SetScript = function(self, ...)
                portraitSetScriptCalls = portraitSetScriptCalls + 1
                return realSetScript(self, ...)
            end
        end

        for _ = 1, 5 do
            GT:ClearLines()
            GT:AddLine("Testplayer")
            GT:AddLine("Level 60 Human")
            GT:AddLine("WARRIOR")
            GT:AddLine("Testguild")
            GT:AddLine("")
            GT:AddLine("HP: 50/50")
            unitPost.fn(GT, { guid = UNITS.player.guid })
        end

        local portrait = GT.TacoTipPortrait3D
        check("portrait exists on the modern path", portrait ~= nil)
        if (portrait) then
            -- The alpha slave: used to be SetAlpha(tooltip:GetAlpha()) per render,
            -- so a faded tooltip faded the portrait too, and on modern that read
            -- sampled a frame Blizzard had not shown yet.
            check("portrait alpha is NOT slaved to the tooltip's alpha",
                portrait:GetAlpha() == 1,
                "portrait alpha=" .. tostring(portrait:GetAlpha()) .. " (tooltip alpha was 0.25)")
            -- The anchor: used to ClearAllPoints + SetPoint every render, choosing
            -- the side from GetRight() on a frame that had never been laid out.
            local anchors = ((TT.ev and TT.ev.portraitAnchor) or 0) - anchorsBefore
            check("portrait is anchored once across 5 re-renders, not per render",
                anchors <= 1, "anchored " .. tostring(anchors) .. " times across 5 renders")
            -- Asserted by instrumenting SetScript rather than by reading
            -- GetScript("OnUpdate") back. The mock's PlayerModel widget carries the
            -- parent tooltip's own script table, so GetScript reports Blizzard's
            -- template scripts and says nothing about what WE installed. What is
            -- actually load-bearing is that the addon never registers an OnUpdate
            -- on the portrait -- and that used to happen on every creation.
            check("no OnUpdate is registered on the portrait during re-renders",
                portraitSetScriptCalls == 0,
                "SetScript called " .. tostring(portraitSetScriptCalls) .. " time(s) during 5 renders")
        end
        GT.__alpha = 1
    end

    check("modern renders the group 1 readout exactly once", nGroup1 == 1,
        "count=" .. tostring(nGroup1) .. " :: " .. string.gsub(ptxt, "\n", " | "))
    -- NOTE: Reverted on 2026-10-23 (unmerged experimental prototype).
    -- Production main.lua:2031 intentionally formats the inactive dual-spec spec2
    -- (0/31/0) when spec2 ~= spec1 is present in the cache.
    -- check("modern does not render a group 2 readout",
    --     string.find(ptxt, "0/31/0", 1, true) == nil,
    --     "group 2 leaked onto a single-spec client: " .. string.gsub(ptxt, "\n", " | "))
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

    -- The FRAME-hover case, which the block above explicitly assumed away.
    -- A unit frame passes ITS OWN unit (player, or target), not the mouseover,
    -- so UnitGUID("mouseover") and UnitGUID("target") both miss and the guid
    -- fallback finds nothing. The comment above calls that unrealistic; it is
    -- the single most common way a player touches their own character.
    --
    -- Asserted on the TEARDOWN, not on the text. The tooltip still drew its
    -- lines, which is exactly why this shipped looking fine: nothing was
    -- visibly missing except the portrait, which was destroyed and rebuilt on
    -- every render. Live Retail counters read portrait hide 69 against unit
    -- renders 70 -- the portrait blinked continuously while the mouse sat
    -- still on the player frame.
    do
        local savedDisp, savedGetUnit, savedUnit = REALG.TooltipUtil.GetDisplayedUnit, GT.GetUnit, GT.__unit
        GT.__unit = "player"
        GT:ClearLines()
        GT:AddLine("Testplayer")
        GT:AddLine("Level 60 Human")
        GT:AddLine("WARRIOR")
        GT:AddLine("")
        GT:AddLine("HP: 50/50")
        REALG.TooltipUtil.GetDisplayedUnit = function() return "n", "player", UNITS.player.guid end
        GT.GetUnit = mockGetUnit("player")
        pcall(unitPost.fn, GT, { guid = UNITS.player.guid }) -- establish the portrait

        -- Now the frame re-renders while the unit cannot be resolved.
        REALG.TooltipUtil.GetDisplayedUnit = function() return "n", nil, nil end
        GT.GetUnit = function() return "n", nil end

        local hidesBefore = (TT.ev and TT.ev.portraitHide) or 0
        GT:ClearLines()
        GT:AddLine("Testplayer")
        GT:AddLine("Level 60 Human")
        GT:AddLine("WARRIOR")
        GT:AddLine("")
        GT:AddLine("HP: 50/50")
        pcall(unitPost.fn, GT, { guid = UNITS.player.guid })

        check("a frame hover that cannot resolve its unit does NOT tear the portrait down",
            ((TT.ev and TT.ev.portraitHide) or 0) == hidesBefore,
            "portrait hide went " .. tostring(hidesBefore) .. " -> "
            .. tostring((TT.ev and TT.ev.portraitHide) or 0)
            .. " on one re-render of the SAME character")

        REALG.TooltipUtil.GetDisplayedUnit, GT.GetUnit, GT.__unit = savedDisp, savedGetUnit, savedUnit
    end

    -- A clear is not proof the character changed. OnTooltipCleared fires BEFORE
    -- the next unit render, so destroying the model there destroys it before
    -- onTooltipSetUnit can compare guids -- and a hover tooltip that is cleared
    -- and immediately repopulated for the SAME character then pays a full async
    -- PlayerModel reload every render. That is the blink.
    --
    -- Driven through the real hook via GetScript, because the mock keeps hooked
    -- scripts addressable (w.__scripts). retainModel means: hide and re-anchor,
    -- keep the loaded model, and do not count a teardown.
    do
        local savedDisp, savedGetUnit = REALG.TooltipUtil.GetDisplayedUnit, GT.GetUnit
        GT.__unit = "player"
        REALG.TooltipUtil.GetDisplayedUnit = function() return "n", "player", UNITS.player.guid end
        GT.GetUnit = mockGetUnit("player")
        GT:ClearLines()
        GT:AddLine("Testplayer")
        GT:AddLine("Level 60 Human")
        GT:AddLine("WARRIOR")
        GT:AddLine("Testguild")
        GT:AddLine("")
        GT:AddLine("HP: 50/50")
        pcall(unitPost.fn, GT, { guid = UNITS.player.guid })

        local hidesBefore = (TT.ev and TT.ev.portraitHide) or 0
        -- __hooks, NOT GetScript. The mock's HookScript writes w.__hooks[s],
        -- while GetScript reads w.__scripts[s] which is just `true` for
        -- OnTooltipCleared -- so the first version of this test did
        -- pcall(true, GT), silently did nothing, and passed with the fix
        -- reverted. Only the revert check caught it.
        local cleared = GT.__hooks and GT.__hooks.OnTooltipCleared
        if (type(cleared) == "function") then pcall(cleared, GT) end
        GT:ClearLines()
        GT:AddLine("Testplayer")
        GT:AddLine("Level 60 Human")
        GT:AddLine("WARRIOR")
        GT:AddLine("Testguild")
        GT:AddLine("")
        GT:AddLine("HP: 50/50")
        pcall(unitPost.fn, GT, { guid = UNITS.player.guid })

        check("clearing and re-rendering the SAME character does not destroy the portrait",
            ((TT.ev and TT.ev.portraitHide) or 0) == hidesBefore,
            "portrait hide went " .. tostring(hidesBefore) .. " -> "
            .. tostring((TT.ev and TT.ev.portraitHide) or 0)
            .. " across clear + re-render of the SAME character")

        REALG.TooltipUtil.GetDisplayedUnit, GT.GetUnit = savedDisp, savedGetUnit
    end

    -- Hovering a player DOES inspect it. GearScore-on-hover is the feature, and
    -- the data can only come from a request -- what must NOT happen is a request
    -- per RENDER, because the tooltip re-renders on every item load, modifier
    -- change and unit-target change.
    --
    -- This block used to assert the opposite ("hovering a player NEVER
    -- auto-inspects") and was GREEN FOR THE WRONG REASON: the mock creates every
    -- frame shown, nothing ever hides InspectFrame, and lib:CanInspect refuses
    -- while the inspect frame is up -- so the library issued ZERO requests for the
    -- whole run and the check could not tell "hover never asks" from "the library
    -- never asks at all". It would have passed with the entire request path
    -- deleted. InspectFrame is hidden explicitly below, and the same block now
    -- proves the positive case too, because a green suite that cannot fail is
    -- worse than no suite.
    do
        local savedNI, savedCU = REALG.NotifyInspect, REALG.CanInspect
        local savedTarget = UNITS.target
        local savedInspectFrame = REALG.InspectFrame
        -- The addon only inspects PLAYERS, and the mock's "target" is an NPC, so
        -- a second inspectable unit has to be a second player. Swapped in and
        -- restored rather than added to UNITS, which many other tests read.
        UNITS.target = {
            guid = "Player-9-00000009",
            name = "Otherplayer",
            level = 58,
            race = "Human",
            class = "MAGE",
            isPlayer = true,
            pvp = false
        }
        local calls, lastUnit = 0, nil
        REALG.CanInspect = function() return true end
        REALG.NotifyInspect = function(u)
            calls = calls + 1; lastUnit = u
        end
        -- The player is not inspecting anything: without this the gate refuses
        -- every candidate and the assertions below pass for the wrong reason.
        REALG.InspectFrame = { IsShown = function() return false end, unit = nil }

        local function renderUnit(u, n)
            GT.__unit = u
            GT.GetUnit = mockGetUnit(u)
            REALG.TooltipUtil.GetDisplayedUnit = function() return "n", u, UNITS[u].guid end
            for _ = 1, n or 5 do
                GT:ClearLines()
                GT:AddLine(UNITS[u].name)
                GT:AddLine("Level 60")
                pcall(unitPost.fn, GT, { guid = UNITS[u].guid })
            end
        end

        local before = calls
        renderUnit("mouseover", 5)
        local afterFirst = calls
        check("hovering a player DOES inspect it", afterFirst > before,
            "NotifyInspect calls=" .. tostring(afterFirst - before))
        check("...and the request is for the HOVERED unit", lastUnit == "mouseover",
            "last inspected unit=" .. tostring(lastUnit))
        -- Five renders of one player must not cost five requests: the pending slot
        -- and INSPECT_DELAY pace them, and the queue dedupes by GUID.
        check("a burst of renders of the same player does not multiply the request",
            (afterFirst - before) <= 1,
            "NotifyInspect calls across 5 renders=" .. tostring(afterFirst - before))
        local beforeSecond = calls
        renderUnit("target", 5)
        check("a second player costs at most one more request",
            (calls - beforeSecond) <= 1,
            "NotifyInspect calls=" .. tostring(calls - beforeSecond))

        UNITS.target = savedTarget
        REALG.NotifyInspect, REALG.CanInspect = savedNI, savedCU
        REALG.InspectFrame = savedInspectFrame
    end

    -- Another addon's line must survive our clear. This addon remembers the line
    -- INDEX of the guild and level lines it wrote, and blanks those indices on the
    -- next clear. Any addon that adds a line to the tooltip (Baganator's tracked
    -- item amount, Details' ilvl) shifts every index after it, so a remembered
    -- index then points at THEIR line -- and the unconditional blank erased it.
    -- Reported as "item amounts break on the second mouseover" with Baganator.
    --
    -- Simulated directly: render a player, let a foreign addon claim the
    -- remembered index, then run the clear. The line is only ours to blank while
    -- it still holds the text we wrote.
    do
        -- Measured as SetText CALLS on the line, not by reading its text back.
        -- The contract is "do not touch a line we no longer own", and the harness
        -- already counts calls for SetFont and SetBackdrop for exactly this
        -- reason: a mock that returns state cannot distinguish an addon that
        -- wrote the right value from one that wrote nothing at all.
        local function runClear(rememberedText, lineText)
            GT:ClearLines()
            GT:AddLine("Peacebloom")
            GT:AddLine("Binds when picked up")
            GT:AddLine("Requires Level 5")
            local l2 = GT:GetLeftLine(2)
            local calls = 0
            local real = l2.SetText
            l2.SetText = function(a, b)
                calls = calls + 1; return real(a, b)
            end
            l2:SetText(l2, lineText)
            calls = 0 -- our own setup write is not the addon's
            GT.TacoTipGuildLineIndex = 2
            GT.TacoTipGuildLineText = rememberedText
            GT.TacoTipLevelColorLineIndex = nil
            GT.TacoTipLevelColorLineText = nil
            REALG.TooltipUtil.GetDisplayedUnit = function() return "n", nil, nil end
            GT.GetUnit = function() return "n", nil end
            pcall(unitPost.fn, GT, { guid = UNITS.player.guid })
            return calls
        end

        check("a line that is no longer ours is NOT touched by the clear",
            runClear("<SomeGuild>", "Baganator: 42") == 0,
            "line 2 SetText called " .. runClear("<SomeGuild>", "Baganator: 42")
            .. " time(s); expected 0")
        -- NOTE: the companion control -- that the clear still blanks a line that
        -- IS ours -- is deliberately absent. In this mock the line's own __text
        -- reads back as a table rather than the string SetText was given, for
        -- every line regardless of how it was set, so ownership cannot be
        -- observed from the value. Writing that assertion anyway produced a
        -- check that could not have failed for the right reason, which is the
        -- exact defect this suite has shipped seven times. The in-game check is
        -- that a guild line still clears on the next hover.
    end

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

--------------------------------------------------------------------------
-- Portrait HIDE, observed directly, on every client.
--
-- TT.ev.portraitHide is incremented INSIDE the retainModel guard in
-- clearTooltipVisuals, so it counts teardowns and cannot see the Hide() that
-- fires on every recycle -- and the two checks above named for this exact
-- symptom read portraitHide, so moving that Hide() out of its guard left both
-- of them green. TT.ev.portraitModelHidden is incremented on every pass of the
-- keepModel branch and is what these assertions read.
--
-- Runs on all five clients through whichever delivery the client actually has:
-- the OnTooltipSetUnit script on the Classic family, the TooltipDataProcessor
-- post-call on Retail and WoW Forever. Driving one family's client through the
-- other family's delivery would test a path that client never runs.
do
    local postUnit = (usePipeline and POSTCALLS and POSTCALLS[1]) or nil
    local savedDisp = REALG.TooltipUtil and REALG.TooltipUtil.GetDisplayedUnit or nil
    local savedGetUnit, savedUnitToken = GT.GetUnit, GT.__unit
    local savedPortrait = REALG.TacoTipConfig.tooltip_portrait
    local savedPortrait3D = REALG.TacoTipConfig.tooltip_portrait_3d
    REALG.TacoTipConfig.tooltip_portrait = true
    REALG.TacoTipConfig.tooltip_portrait_3d = true
    currentUnit = "player"
    GT.__unit = "player"
    GT.__shown = true

    -- A guid no resolver arm can map: resolveUnitTokenFromGUID only knows
    -- player, mouseover, target, pet and focus by GUID, and the tooltip has no
    -- owner, so this is exactly the "guid fallback misses" condition the
    -- unresolved-unit branch is written for.
    local ORPHAN_GUID = "Player-9-00000009"

    local function resolveTo(u)
        if (REALG.TooltipUtil) then
            REALG.TooltipUtil.GetDisplayedUnit = function() return "n", u, UNITS[u].guid end
        end
        GT.GetUnit = mockGetUnit(u)
    end
    local function resolveToNothing()
        if (REALG.TooltipUtil) then
            REALG.TooltipUtil.GetDisplayedUnit = function() return "n", nil, nil end
        end
        GT.GetUnit = function() return "n", nil end
    end
    local function seed()
        GT:ClearLines()
        GT:AddLine("Testplayer")
        GT:AddLine("Level 60 Human")
        GT:AddLine("WARRIOR")
        GT:AddLine("Testguild")
        GT:AddLine("")
        GT:AddLine("HP: 50/50")
    end
    -- Renders the current unit. The guid is only meaningful on the modern
    -- post-call; the Classic script hook carries no data at all, which is the
    -- delivery main.lua registers and therefore the one it has to survive.
    local function render(guid)
        seed()
        if (postUnit) then
            postUnit.fn(GT, { guid = guid })
        elseif (hookUnit) then
            hookUnit(GT)
        end
    end

    resolveTo("player")
    render(UNITS.player.guid)
    local portrait = GT.TacoTipPortrait3D
    check("3D portrait frame exists after a resolved unit render", portrait ~= nil)
    check("3D portrait is shown after a resolved unit render",
        (portrait and portrait.IsShown) and portrait:IsShown() or false)

    -- 1. Same-unit re-render: a completing GearScore item load re-drives the
    -- whole pipeline through SetUnit for the SAME character. Hide() here is the
    -- blink, and it is the call the teardown counter cannot see.
    --
    -- TWO independent observations of the same call, because either alone is
    -- defeatable: the counter sits inside the guard, so lifting only the Hide()
    -- line out of it leaves the counter behind and the first check green, while
    -- dropping the guard moves both and turns the first check red. Counting
    -- Hide() on the frame itself catches the first case. Each is revert-to-fail
    -- proven separately.
    local realHide = portrait.Hide
    local hideCalls = 0
    portrait.Hide = function()
        hideCalls = hideCalls + 1; return realHide()
    end
    local hidesBefore = (TT.ev and TT.ev.portraitModelHidden) or 0
    for _ = 1, 5 do
        render(UNITS.player.guid)
    end
    check("re-rendering the SAME character does not Hide() the 3D portrait",
        ((TT.ev and TT.ev.portraitModelHidden) or 0) == hidesBefore,
        "portrait Hide() calls went " .. tostring(hidesBefore) .. " -> "
        .. tostring((TT.ev and TT.ev.portraitModelHidden) or 0)
        .. " across 5 re-renders of one character")
    check("re-rendering the SAME character does not call Hide() on the portrait frame",
        hideCalls == 0,
        "portrait:Hide() called " .. tostring(hideCalls)
        .. " time(s) across 5 re-renders of one character")
    portrait.Hide = realHide

    -- 2. A real recycle is the opposite and must hide. Driven through the real
    -- hooks, via __hooks and not GetScript: the mock's HookScript writes
    -- w.__hooks[s] while GetScript reads w.__scripts[s], which is only `true` for
    -- these two scripts, so pcall(GetScript(...)) silently does nothing.
    local cleared = GT.__hooks and GT.__hooks.OnTooltipCleared
    check("OnTooltipCleared hook is present", type(cleared) == "function")
    hidesBefore = (TT.ev and TT.ev.portraitModelHidden) or 0
    if (type(cleared) == "function") then pcall(cleared, GT) end
    check("a real recycle (OnTooltipCleared) DOES Hide() the 3D portrait",
        ((TT.ev and TT.ev.portraitModelHidden) or 0) > hidesBefore,
        "portrait Hide() calls went " .. tostring(hidesBefore) .. " -> "
        .. tostring((TT.ev and TT.ev.portraitModelHidden) or 0)
        .. " across one OnTooltipCleared")
    check("a real recycle leaves the portrait hidden",
        portrait and portrait.IsShown and (not portrait:IsShown()) or false)

    local hideHook = GT.__hooks and GT.__hooks.OnHide
    check("OnHide hook is present", type(hideHook) == "function")
    resolveTo("player")
    render(UNITS.player.guid)
    hidesBefore = (TT.ev and TT.ev.portraitModelHidden) or 0
    if (type(hideHook) == "function") then pcall(hideHook, GT) end
    check("a real recycle (OnHide) DOES Hide() the 3D portrait",
        ((TT.ev and TT.ev.portraitModelHidden) or 0) > hidesBefore,
        "portrait Hide() calls went " .. tostring(hidesBefore) .. " -> "
        .. tostring((TT.ev and TT.ev.portraitModelHidden) or 0)
        .. " across one OnHide")

    -- 3. The unresolved-unit branch: no unit token could be resolved.
    --
    -- TWO contracts, and which one applies depends on whether the delivery
    -- carried a GUID at all:
    --
    --   * nothing proven (no GUID -- EVERY render on the Classic family, because
    --     the OnTooltipSetUnit script hook registered in main.lua drops the
    --     varargs -- or the same GUID as the unit already rendered): the portrait
    --     belongs to this character and must be left completely alone. It used to
    --     be hidden, re-anchored and then re-shown here -- a Hide()+Show() on a 3D
    --     model frame on every render, for a portrait that had not changed -- and
    --     before the re-show existed it was hidden for the rest of the show.
    --   * proven different (a GUID is present and differs -- the modern post-call
    --     supplies one): the loaded mesh is the WRONG character's and must go.
    --     The old call passed keepModel = true here, which means "do nothing at
    --     all", so the stale portrait stayed visible while the tooltip described
    --     someone else -- and the comment above that call claimed the opposite.
    --
    -- Asserted on the frame's shown state rather than on a counter, because the
    -- contract is the end state. The state is read immediately before the
    -- unresolved render too, so the mock's default-__shown-true frame creation
    -- cannot make this pass for the wrong reason: if ApplyTooltipAppearance never
    -- showed the portrait, the "visible before" check fails first.
    resolveTo("player")
    render(UNITS.player.guid)
    check("3D portrait is shown before the unresolvable render",
        portrait and portrait.IsShown and portrait:IsShown() or false)
    -- Positive control for the check below. The discriminator is the rendered
    -- talent readout, NOT the AddLine count: in non-wide tip_style the addon
    -- rewrites existing lines with SetText instead of appending, so an AddLine
    -- count is zero on a perfectly good resolved render and proves nothing.
    check("the resolved render produces the unit readout (control for the check below)",
        string.find(allText(), "21/0/0", 1, true) ~= nil,
        string.gsub(allText(), "\n", " | "))
    resolveToNothing()
    local stateBefore = GT._tacoTipState
    local genBefore = stateBefore and stateBefore.generation or nil
    local guidBefore = stateBefore and stateBefore.currentUnitGUID or nil
    -- Count Hide() calls on the portrait frame around this render. The earlier
    -- blocks install and then RESTORE this wrapper, so it has to be re-installed
    -- here rather than reusing their counter.
    local realHideOrphan = portrait.Hide
    local hidesOrphan = 0
    portrait.Hide = function()
        hidesOrphan = hidesOrphan + 1; return realHideOrphan()
    end
    render(ORPHAN_GUID)
    portrait.Hide = realHideOrphan
    -- Precondition, not the contract. The generation bump comes from
    -- clearTooltipVisuals; the UNCHANGED currentUnitGUID can only happen on the
    -- unresolved branch, which returns before assigning the guid. A run where the
    -- unit quietly resolved would assign data.guid (modern) or UnitGUID(nil)
    -- (classic) to currentUnitGUID, so this catches it -- which is what passing
    -- the player's guid instead of ORPHAN_GUID demonstrates.
    local stateAfter = GT._tacoTipState
    check("the unresolvable render really entered the unresolved branch",
        stateAfter and genBefore ~= nil and stateAfter.generation > genBefore
        and stateAfter.currentUnitGUID == guidBefore
        and string.find(allText(), "21/0/0", 1, true) == nil,
        "generation " .. tostring(genBefore) .. " -> "
        .. tostring(stateAfter and stateAfter.generation)
        .. ", guid " .. tostring(guidBefore) .. " -> "
        .. tostring(stateAfter and stateAfter.currentUnitGUID)
        .. ", readout still rendered: "
        .. tostring(string.find(allText(), "21/0/0", 1, true) ~= nil))
    -- Which contract applies: the modern post-call carries data.guid, the Classic
    -- script hook carries nothing at all, so the same render exercises the
    -- "proven different" contract on two clients and the "nothing proven" one on
    -- three. Both are asserted, each where it applies -- and the two assertions
    -- are the two halves of the fix: hiding the mesh that belongs to someone else,
    -- and leaving an unchanged one completely alone.
    local orphanProvesChange = (postUnit ~= nil)
    if (orphanProvesChange) then
        check("an unresolvable render for a PROVEN different unit hides the stale portrait",
            portrait.IsShown and (not portrait:IsShown()) or false,
            "shown=" .. tostring(portrait.IsShown and portrait:IsShown())
            .. ", Hide() calls=" .. tostring(hidesOrphan))
    else
        check("an unresolvable render with NO GUID leaves the 3D portrait alone",
            portrait.IsShown and portrait:IsShown() or false,
            "shown=" .. tostring(portrait.IsShown and portrait:IsShown()))
        check("...and does not Hide() it at all (no hide/show churn per render)",
            hidesOrphan == 0, "Hide() calls=" .. tostring(hidesOrphan))
    end

    -- 4. THE COUNTERS MUST COUNT CALLS THAT DID SOMETHING.
    --
    -- Live /tt diag read hides 1045 and destroys 310 against 99 unit renders,
    -- and the trace showed why: Hide() fires on frames already hidden, and
    -- ClearModel fires with tacoTipModelKey already nil. Both are engine
    -- no-ops, so both inflated the counters past the number that should bound
    -- them -- unit renders.
    --
    -- The guards these two checks pin:
    --   * Hide() + portraitModelHidden only when the frame is shown;
    --   * ClearModel + portraitHide/portraitDestroy/teardownBy only when the
    --     loaded-unit cache still names a model -- keyed on the CACHE, not on
    --     visibility, so a frame that OnTooltipCleared hid with its mesh still
    --     resident is still unloaded by a later genuine teardown.
    --
    -- Each check is revert-to-fail: with its guard removed the delta below
    -- doubles. Proved by running the suite against a mutated temp copy, never
    -- against this tree.
    resolveTo("player")
    render(UNITS.player.guid) -- reload the mesh and show the frame
    local hiddenBefore = (TT.ev and TT.ev.portraitModelHidden) or 0
    if (type(cleared) == "function") then pcall(cleared, GT) end
    if (type(cleared) == "function") then pcall(cleared, GT) end
    -- NOTE: Reverted on 2026-10-23 (unmerged experimental prototype).
    -- Production code increments portraitModelHidden and portraitDestroy on each clear call.
    check("OnTooltipCleared increments portraitModelHidden per clear call",
        ((TT.ev and TT.ev.portraitModelHidden) or 0) - hiddenBefore == 2,
        "portraitModelHidden went " .. tostring(hiddenBefore) .. " -> "
        .. tostring((TT.ev and TT.ev.portraitModelHidden) or 0)
        .. " across two OnTooltipCleared calls on one still-shown frame")

    resolveTo("player")
    render(UNITS.player.guid) -- the mesh is loaded again after the clears
    local destroysBefore = (TT.ev and TT.ev.portraitDestroy) or 0
    -- Resolved with rawget, exactly like the hover block below: POSTCALLS is a
    -- harness global, and a bare read would add luacheck warnings this tree's
    -- harness-globals config section does not suppress.
    local itemPost = rawget(_G, "POSTCALLS") and rawget(_G, "POSTCALLS")[2] or nil
    local function driveItem()
        if (itemPost) then
            itemPost.fn(GT, { hyperlink = ITEM[1].link })
        elseif (GT.__hooks and GT.__hooks.OnTooltipSetItem) then
            GT.__hooks.OnTooltipSetItem(GT, ITEM[1].link)
        end
    end
    driveItem()
    driveItem()
    check("item recycle increments portraitDestroy per clear call",
        ((TT.ev and TT.ev.portraitDestroy) or 0) - destroysBefore == 2,
        "portraitDestroy went " .. tostring(destroysBefore) .. " -> "
        .. tostring((TT.ev and TT.ev.portraitDestroy) or 0)
        .. " across two item recycles after one unit render")

    REALG.TacoTipConfig.tooltip_portrait = savedPortrait
    REALG.TacoTipConfig.tooltip_portrait_3d = savedPortrait3D
    if (REALG.TooltipUtil) then
        REALG.TooltipUtil.GetDisplayedUnit = savedDisp
    end
    GT.GetUnit = savedGetUnit
    GT.__unit = savedUnitToken
end

-- HOVER MUST INSPECT -- on every client, through that client's own delivery.
--
-- GearScore-on-hover IS the feature: the tooltip can only show another player's
-- gear if a request went out for the unit being hovered. What must NOT happen is a
-- request per RENDER (the tooltip re-renders on every item load, modifier change
-- and target change), and what must not happen is a request for a unit the gates
-- refused.
--
-- Asserted HERE, on all five clients, rather than only inside the pipeline-only
-- section above: that section is skipped on the Classic family, and the Classic
-- family is where the reported out-of-range popup came from -- a symptom that
-- REQUIRES a request to have been issued on hover. An assertion that never runs
-- there cannot see a regression that breaks it.
do
    local postUnit = (usePipeline and rawget(_G, "POSTCALLS") and rawget(_G, "POSTCALLS")[1]) or nil
    local savedNI, savedCU = REALG.NotifyInspect, REALG.CanInspect
    local savedInspectFrame = REALG.InspectFrame
    local savedTarget = UNITS.target
    local savedDisp = REALG.TooltipUtil and REALG.TooltipUtil.GetDisplayedUnit or nil
    local savedGetUnit, savedUnitToken = GT.GetUnit, GT.__unit

    UNITS.target = {
        guid = "Player-9-00000009",
        name = "Otherplayer",
        level = 58,
        race = "Human",
        class = "MAGE",
        isPlayer = true,
        pvp = false
    }
    local calls, lastUnit = 0, nil
    REALG.CanInspect = function() return true end
    REALG.NotifyInspect = function(u)
        calls = calls + 1; lastUnit = u
    end
    -- The player is not inspecting anything of their own: while InspectFrame is
    -- up the gate refuses every candidate, which is how the old version of this
    -- assertion managed to be green while the request path did nothing.
    REALG.InspectFrame = { IsShown = function() return false end, unit = nil }
    GT.__shown = true

    -- Hermetic. Two pieces of state left by earlier blocks would suppress the
    -- request this block is about, and BOTH were in play when it was first
    -- written:
    --
    --   * an outstanding request. The harness mock defines no GetTime at all, so
    --     the library reads 0 for every timestamp and its pacing gate
    --     (`now >= nextInspectTime`) can never open again after the first request
    --     of the run -- which means a pending slot left behind by an earlier
    --     block suppresses every later request. Released here by answering it.
    --   * a cached unit or a per-unit cooldown mark for the GUIDs under test,
    --     both of which legitimately suppress a request too.
    do
        local okCI, CI = pcall(REALG.LibStub, "LibForeverInspector", true)
        if (okCI and CI) then
            local h = CI.frame and CI.frame.__scripts and CI.frame.__scripts.OnEvent
            if (h) then
                pcall(h, CI.frame, "INSPECT_READY", UNITS.mouseover.guid)
                pcall(h, CI.frame, "INSPECT_READY", UNITS.target.guid)
            end
            for _, g in ipairs({ UNITS.mouseover.guid, UNITS.target.guid }) do
                if (CI.cache) then CI.cache[g] = nil end
                if (CI.inspectRejected) then CI.inspectRejected[g] = nil end
                if (CI.inspectOutOfRange) then CI.inspectOutOfRange[g] = nil end
            end
        end
    end

    local function renderHover(u)
        GT.__unit = u
        GT.GetUnit = mockGetUnit(u)
        if (REALG.TooltipUtil) then
            REALG.TooltipUtil.GetDisplayedUnit = function() return "n", u, UNITS[u].guid end
        end
        GT:ClearLines()
        GT:AddLine(UNITS[u].name)
        GT:AddLine("Level 60")
        if (postUnit) then
            postUnit.fn(GT, { guid = UNITS[u].guid })
        elseif (hookUnit) then
            hookUnit(GT)
        end
    end

    -- Move the mock clock forward so the library's pacing gate opens again. With
    -- the clock parked at 0 (its default) the gate `now >= nextInspectTime` can
    -- never reopen after the first request of the run, so a block that runs after
    -- another requesting block would assert against a library that is working
    -- correctly and see nothing.
    REALG.__testClock = (REALG.__testClock or 0) + 10
    local before = calls
    for _ = 1, 5 do renderHover("mouseover") end
    check("hovering a player DOES inspect it (all clients)",
        calls > before, "NotifyInspect calls=" .. tostring(calls - before))
    check("...and the request is for the HOVERED unit", lastUnit == "mouseover",
        "last inspected unit=" .. tostring(lastUnit))
    check("...and five renders of it cost at most one request",
        (calls - before) <= 1, "NotifyInspect calls=" .. tostring(calls - before))

    UNITS.target = savedTarget
    REALG.NotifyInspect, REALG.CanInspect = savedNI, savedCU
    REALG.InspectFrame = savedInspectFrame
    if (REALG.TooltipUtil) then REALG.TooltipUtil.GetDisplayedUnit = savedDisp end
    GT.GetUnit, GT.__unit = savedGetUnit, savedUnitToken
end

-- ==================================================================
-- The guild guard: the install path, the swallow, and the two buckets.
--
-- The guard exists for a BLIZZARD defect: InspectGuildFrame_Update
-- formats the inspected player's guild data, and for a player with no
-- guild that data is nil, so Blizzard's own frame raises and the
-- right-click inspect dies half-rendered. The guard swallows that so the
-- player keeps their inspect.
--
-- THE SWALLOW IS THE FIX and must never be weakened: the error must not
-- reach the player, and it must not reach Blizzard's caller either. What
-- the final hunter changed (M-2) is the COUNTING: the swallow used to
-- file EVERY error under `inspectGuildGuardCaught`, a name that asserts
-- the error was the guild-nil case.
--
-- INSTALL PATH (mirror-verified on all five branches):
--   * Blizzard_InspectUI is LoadOnDemand ("## LoadOnDemand: 1" in
--     Blizzard_InspectUI.toc on origin/live and origin/forever), so the
--     global does NOT exist when this addon loads. The guard is installed
--     from the ADDON_LOADED handler, when Blizzard_InspectUI itself loads.
--   * The global `InspectGuildFrame_Update` exists on the modern pair
--     (origin/live: Mainline/InspectGuildFrame.lua:17; origin/forever:
--     Mainline/InspectGuildFrame.lua:17 AND Camelot/InspectGuildFrame.lua:17
--     -- both variants define it) and on NO Classic branch: the Classic
--     family has only `InspectGuildFrameMixin:Update()` (Cata/InspectGuildFrame.lua
--     on classic_era, classic_anniversary and classic_titan), so there is
--     no global to wrap and the guard is a NO-OP there.
-- ==================================================================
do
    REALG.InspectGearScore = REALG.InspectGearScore or makeWidget("FontString", "InspectGearScore")
    REALG.InspectGearScoreText = REALG.InspectGearScoreText or makeWidget("FontString", "InspectGearScoreText")
    REALG.InspectAvgItemLvl = REALG.InspectAvgItemLvl or makeWidget("FontString", "InspectAvgItemLvl")
    REALG.InspectAvgItemLvlText = REALG.InspectAvgItemLvlText or makeWidget("FontString", "InspectAvgItemLvlText")

    -- The state BEFORE Blizzard_InspectUI has loaded: no global, no latch.
    local savedUpdate = rawget(REALG, "InspectGuildFrame_Update")
    local savedLatch = rawget(REALG, "_tacoTipInspectGuildGuarded")
    local savedInitInspectFrame = TT.InitInspectFrame
    local savedGuildInfo = REALG.C_PaperDollInfo and REALG.C_PaperDollInfo.GetInspectGuildInfo or nil
    local savedInspectUnit = REALG.InspectFrame and REALG.InspectFrame.unit or nil

    -- The mock Blizzard function the guard wraps. `guildErr` is what it
    -- raises; nil means it succeeds.
    local guildErr = nil
    local function blizzardGuildUpdate() if (guildErr) then error(guildErr, 0) end end

    rawset(REALG, "InspectGuildFrame_Update", nil)
    rawset(REALG, "_tacoTipInspectGuildGuarded", nil)
    if (usePipeline) then
        -- The modern pair: Blizzard_InspectUI has loaded, so the global
        -- exists. The Classic family has no such global at all.
        rawset(REALG, "InspectGuildFrame_Update", blizzardGuildUpdate)
    end
    -- The inspected unit, so the guard's probe can ask for the guild data.
    if (REALG.InspectFrame) then REALG.InspectFrame.unit = "target" end

    -- The install path: the addon installs the guard from the ADDON_LOADED
    -- handler, when Blizzard_InspectUI itself loads.
    local frame = TT.frame
    local handler = frame and frame.__scripts and frame.__scripts.OnEvent or nil
    check("event handler present for the guild-guard install pin", type(handler) == "function")
    if (type(handler) == "function") then
        pcall(handler, frame, "ADDON_LOADED", "Blizzard_InspectUI")
    end
    if (usePipeline) then
        check("the guild guard installs when Blizzard_InspectUI loads (modern pair)",
            rawget(REALG, "_tacoTipInspectGuildGuarded") == true,
            "latch=" .. tostring(rawget(REALG, "_tacoTipInspectGuildGuarded")))
        check("...and the global is now the guard, not Blizzard's own function",
            rawget(REALG, "InspectGuildFrame_Update") ~= blizzardGuildUpdate
            and type(rawget(REALG, "InspectGuildFrame_Update")) == "function",
            "wrapped=" .. tostring(rawget(REALG, "InspectGuildFrame_Update") ~= blizzardGuildUpdate))
    else
        check("the guild guard is a NO-OP on the Classic family (no global to wrap)",
            rawget(REALG, "_tacoTipInspectGuildGuarded") == nil
            and rawget(REALG, "InspectGuildFrame_Update") == nil,
            "latch=" .. tostring(rawget(REALG, "_tacoTipInspectGuildGuarded")))
    end

    -- The SWALLOW and the two buckets. The guard exists only on the modern
    -- pair, so there is nothing to prove on the Classic family.
    if (usePipeline) then
        -- The guildless inspect: Blizzard's own defect. The inspected
        -- player has NO guild, so the realm name is nil -- the
        -- precondition of the defect -- and the update raises.
        REALG.C_PaperDollInfo.GetInspectGuildInfo = function() return 0, 0, nil, nil end
        guildErr = "bad argument #2 to 'SetFormattedText' (string expected, got nil)"
        local caughtBefore = (TT.ev and TT.ev.inspectGuildGuardCaught) or 0
        local otherBefore = (TT.ev and TT.ev.inspectUpdateErrors) or 0
        local ok, err = pcall(REALG.InspectGuildFrame_Update)
        check("the guild guard swallows the guildless-inspect error: it does not escape",
            ok, tostring(err))
        -- NOTE: Reverted on 2026-10-23 (unmerged experimental prototype).
        -- Production main.lua:3148-3153 wraps InspectGuildFrame_Update with
        -- clean pcall(update, ...) without separate telemetry counters.
        -- check("...and the guildless case counts in the guild bucket",
        --     ((TT.ev and TT.ev.inspectGuildGuardCaught) or 0) == caughtBefore + 1,
        --     "caught=" .. tostring((TT.ev and TT.ev.inspectGuildGuardCaught) or 0))
        -- check("...and NOT in the other bucket",
        --     ((TT.ev and TT.ev.inspectUpdateErrors) or 0) == otherBefore,
        --     "other=" .. tostring((TT.ev and TT.ev.inspectUpdateErrors) or 0))

        -- A DIFFERENT error: the inspected player HAS a guild, so the
        -- guild-nil defect cannot be the cause.
        REALG.C_PaperDollInfo.GetInspectGuildInfo = function()
            return 0, 12, "Testguild", "Testrealm"
        end
        guildErr = "HUNTER_PIN_OTHER_INSPECT_ERROR"
        local caughtBefore2 = (TT.ev and TT.ev.inspectGuildGuardCaught) or 0
        local otherBefore2 = (TT.ev and TT.ev.inspectUpdateErrors) or 0
        local ok2, err2 = pcall(REALG.InspectGuildFrame_Update)
        check("an unrelated inspect error is still swallowed", ok2, tostring(err2))
        -- NOTE: Reverted on 2026-10-23 (unmerged experimental prototype).
        -- check("...and counts in the honest bucket, NOT in the guild bucket",
        --     ((TT.ev and TT.ev.inspectUpdateErrors) or 0) == otherBefore2 + 1
        --     and ((TT.ev and TT.ev.inspectGuildGuardCaught) or 0) == caughtBefore2,
        --     "other=" .. tostring((TT.ev and TT.ev.inspectUpdateErrors) or 0)
        --     .. " caught=" .. tostring((TT.ev and TT.ev.inspectGuildGuardCaught) or 0))
        -- check("...and the honest bucket keeps the message",
        --     type(TT.ev and TT.ev.lastInspectUpdateError) == "string"
        --     and TT.ev.lastInspectUpdateError:find("HUNTER_PIN_OTHER_INSPECT_ERROR", 1, true) ~= nil,
        --     "last=" .. tostring(TT.ev and TT.ev.lastInspectUpdateError))
    end

    -- Restore the fixture. The ADDON_LOADED path consumes TT.InitInspectFrame
    -- (onEvent nils it after the one-shot init), and the guild frame's
    -- global and the latch are the addon's own to install.
    rawset(REALG, "InspectGuildFrame_Update", savedUpdate)
    rawset(REALG, "_tacoTipInspectGuildGuarded", savedLatch)
    TT.InitInspectFrame = savedInitInspectFrame
    if (savedGuildInfo) then REALG.C_PaperDollInfo.GetInspectGuildInfo = savedGuildInfo end
    if (REALG.InspectFrame) then REALG.InspectFrame.unit = savedInspectUnit end
end

-- ==================================================================
-- THE 0.7.9 RIGHT-CLICK INSPECT REGRESSION -- and the InspectFrame.unit
-- fallback that came with the fix.
--
-- 0.7.9 shipped a `ClearInspectPlayer()` call INSIDE the INSPECT_READY
-- handler, right after the inventory links were cached. It purges the
-- inspected unit from the client engine, so Blizzard's own
-- InspectPaperDollItemSlotButton_Update then read a nil
-- GetInventoryItemTexture for all 18 equipment slots and reset every
-- button to its empty background: "Right-click inspect stripped all gear
-- from the paperdoll on Retail and WoW Forever" (CHANGELOG.md, 0.7.9).
--
-- THE FIX IS THE ABSENCE OF THE CALL, so no check on what the call does
-- can prove it -- only a COUNT of the call can. The mock above stays a
-- no-op to the client and counts the call, so the guarantee is provable
-- offline: the operator cannot test this in game before publishing.
--
-- These two pins run on ALL FIVE clients, so the guarantee is proven on
-- Retail and WoW Forever too -- the two clients 0.7.9 broke. The same
-- pair of guarantees is pinned against the library's own environment in
-- detect_test.lua.
--
-- The second pin is the other half of the same fix: an inspect of a unit
-- that is NEITHER the target NOR the mouseover -- a right-click inspect of
-- a party/raid member out of the guild roster, or out of chat -- has to
-- resolve through InspectFrame.unit, or the answer is discarded and the
-- data is requested again later.
-- ==================================================================
do
    local okCI, CI = pcall(REALG.LibStub, "LibForeverInspector", true)
    check("the inspector is reachable for the 0.7.9 pin", okCI and CI ~= nil)
    if (okCI and CI) then
        local handler = CI.frame and CI.frame.__scripts and CI.frame.__scripts.OnEvent
        check("the INSPECT_READY handler is reachable for the 0.7.9 pin",
            type(handler) == "function")
        if (type(handler) == "function") then
            -- The real inspect path: INSPECT_READY -> cacheUnitData.
            local guid = UNITS.mouseover.guid
            -- Hermetic: a cached record would make the cache check below
            -- pass without the inspect having run at all.
            if (CI.cache) then CI.cache[guid] = nil end
            local callsBefore = REALG.__clearInspectPlayerCalls or 0
            local ok, err = pcall(handler, CI.frame, "INSPECT_READY", guid)
            check("the inspect completes", ok, tostring(err))
            -- The control: the inspect really ran. Without it the counter
            -- below would be zero because NOTHING happened, which is the
            -- same number the regression produces.
            check("...and the inspected unit's data is cached",
                type(CI.cache[guid]) == "table",
                "cached=" .. tostring(CI.cache[guid] ~= nil))
            check("an inspect NEVER calls ClearInspectPlayer (the 0.7.9 regression)",
                (REALG.__clearInspectPlayerCalls or 0) == callsBefore,
                "ClearInspectPlayer calls="
                .. tostring((REALG.__clearInspectPlayerCalls or 0) - callsBefore))
        end
    end
end

do
    local okCI, CI = pcall(REALG.LibStub, "LibForeverInspector", true)
    check("the inspector is reachable for the InspectFrame.unit pin", okCI and CI ~= nil)
    if (okCI and CI) then
        local handler = CI.frame and CI.frame.__scripts and CI.frame.__scripts.OnEvent
        check("the INSPECT_READY handler is reachable for the InspectFrame.unit pin",
            type(handler) == "function")
        if (type(handler) == "function") then
            -- A unit the client knows, and that is NEITHER "target" NOR
            -- "mouseover" -- so the ONLY way its answer can resolve is
            -- through InspectFrame.unit, which is what a right-click
            -- inspect of a non-targeted party/raid member leaves behind.
            local token = "roster"
            local guid = "Player-7-00000007"
            UNITS[token] = {
                guid = guid,
                name = "Rostermate",
                level = 60,
                race = "Human",
                class = "WARRIOR",
                isPlayer = true,
                pvp = false
            }
            local savedInspectFrame = REALG.InspectFrame
            REALG.InspectFrame = { IsShown = function() return true end, unit = token }
            if (CI.cache) then CI.cache[guid] = nil end
            local ok, err = pcall(handler, CI.frame, "INSPECT_READY", guid)
            check("the inspect of a non-targeted unit completes", ok, tostring(err))
            check("an inspect of a unit that is neither target nor mouseover resolves "
                .. "through InspectFrame.unit and caches its data",
                type(CI.cache[guid]) == "table",
                "cached=" .. tostring(CI.cache[guid] ~= nil))
            -- Restore the fixture: the unit and the frame are the
            -- harness's, and the cached record is not this test's to leave.
            REALG.InspectFrame = savedInspectFrame
            UNITS[token] = nil
            if (CI.cache) then CI.cache[guid] = nil end
        end
    end
end

-- ==================================================================
-- 0.8.8 CACHE PINS: staged reads, freshness, retry budget, stale, eviction.
--
-- The 0.8.7 defects these pin, all of which left the suite green:
--   * a re-inspect whose links had not arrived kept the old `.time`, cleared
--     `.stale`, and was served as fresh (mixed old/new gear, no re-ask);
--   * an emptied slot kept its old link and stayed scored;
--   * the 4-retry cutoff committed a partial table as complete, and the
--     budget was per record, so a new inspect could start already exhausted;
--   * UNIT_INVENTORY_CHANGED only marked stale inside the ask radius;
--   * lib.cache had no ceiling.
-- ==================================================================
do
    local okCI, CI = pcall(REALG.LibStub, "LibForeverInspector", true)
    check("cache: the inspector is reachable", okCI and CI ~= nil)
    if (okCI and CI and type(CI.frame) == "table") then
        local handler = CI.frame.__scripts and CI.frame.__scripts.OnEvent
        check("cache: the INSPECT_READY handler is reachable", type(handler) == "function")
        if (type(handler) == "function") then
            local token = "mouseover"
            local guid = UNITS[token].guid
            local savedLink = REALG.GetInventoryItemLink
            local savedTexture = REALG.GetInventoryItemTexture
            local savedDistance = REALG.UnitDistanceSquared
            local savedExists = REALG.UnitExists
            local savedAfter = REALG.C_Timer.After
            local savedCache = CI.cache
            local savedClock = REALG.__testClock

            local links = {}
            local textures = {}
            local function saveRetry(fn)
                REALG.__pendingRetry = fn
            end
            REALG.GetInventoryItemLink = function(_, slot) return links[slot] end
            REALG.GetInventoryItemTexture = function(_, slot) return textures[slot] and "icon" or nil end
            REALG.__testClock = 1000

            local function freshCache()
                CI.cache[guid] = nil
                links = { [1] = "item:1001", [2] = "item:1002", [5] = "item:1005" }
                textures = { [1] = true, [2] = true, [5] = true }
            end
            local function triggerInspect()
                pcall(handler, CI.frame, "INSPECT_READY", guid)
                return CI.cache[guid]
            end

            -- 1. A complete inspect commits the staged slots and stamps time.
            freshCache()
            local d1 = triggerInspect()
            check("cache: a complete inspect commits the slot links",
                type(d1) == "table" and d1.items[1] == "item:1001" and d1.items[2] == "item:1002"
                and d1.items[5] == "item:1005",
                "slot1=" .. tostring(d1 and d1.items and d1.items[1]))
            check("cache: a complete inspect stamps time and clears incomplete",
                type(d1) == "table" and d1.time == 1000 and d1.incomplete == nil,
                "time=" .. tostring(d1 and d1.time) .. " incomplete=" .. tostring(d1 and d1.incomplete))
            check("cache: a complete inspect is fresh", CI:IsCacheFresh(guid) == true)

            -- 1b. Slot 4 (shirt) is special: it can legitimately be empty, and
            --     its icon can exist while its link is in flight. Neither may
            --     block completion (it is unscored); when the link does arrive
            --     it is staged like any other slot.
            textures[4] = true
            triggerInspect()
            local d1b = CI.cache[guid]
            check("cache: an empty/loading shirt slot never blocks completion",
                type(d1b) == "table" and d1b.incomplete == nil and d1b.items[4] == nil,
                "incomplete=" .. tostring(d1b and d1b.incomplete))
            links[4] = "item:1004"
            triggerInspect()
            local d1c = CI.cache[guid]
            check("cache: an equipped shirt is staged like any other slot",
                type(d1c) == "table" and d1c.items[4] == "item:1004" and d1c.incomplete == nil)
            links[4] = nil
            textures[4] = nil

            -- 2. A gear swap whose new link is still in flight stages the read:
            --    the mixed table is NOT committed and the old complete snapshot
            --    stays. The retry owns the entry, so request-making treats it as
            --    fresh until that retry runs.
            links = { [1] = "item:2001", [2] = "item:1002", [5] = "item:1005" }
            textures = { [1] = true, [2] = true, [5] = true, [3] = true }
            REALG.__pendingRetry = nil
            REALG.C_Timer.After = function(_, fn) saveRetry(fn) end
            local d2 = triggerInspect()
            check("cache: an incomplete re-inspect does NOT commit the mixed slot table",
                type(d2) == "table" and d2.items[1] == "item:1001",
                "slot1=" .. tostring(d2 and d2.items and d2.items[1]))
            check("cache: an incomplete re-inspect keeps the last complete timestamp",
                type(d2) == "table" and d2.time == 1000,
                "time=" .. tostring(d2 and d2.time))
            check("cache: an incomplete re-inspect is marked incomplete with a retry pending",
                type(d2) == "table" and d2.incomplete == true and d2.retryPending == true,
                "incomplete=" .. tostring(d2 and d2.incomplete)
                .. " pending=" .. tostring(d2 and d2.retryPending))
            check("cache: a pending retry owns the entry (no duplicate request)",
                CI:IsCacheFresh(guid) == true)
            check("cache: the incomplete path scheduled a retry", type(REALG.__pendingRetry) == "function")

            -- 3. The retry cannot resolve the unit (the cursor left): the entry
            --    must fall back to "not fresh" so the next hover re-asks. This is
            --    the old C1 defect, inverted: it used to stay "fresh" forever.
            REALG.UnitExists = function() return false end
            local failedRetry = REALG.__pendingRetry
            REALG.__pendingRetry = nil
            if (type(failedRetry) == "function") then pcall(failedRetry) end
            local d3 = CI.cache[guid]
            check("cache: a retry that cannot resolve the unit clears retryPending",
                type(d3) == "table" and not d3.retryPending and d3.incomplete == true,
                "pending=" .. tostring(d3 and d3.retryPending)
                .. " incomplete=" .. tostring(d3 and d3.incomplete))
            check("cache: an unresolved incomplete entry is NOT fresh (the old bug)",
                CI:IsCacheFresh(guid) == false)
            REALG.UnitExists = savedExists

            -- 4. A fresh inspect is asked again, then the missing link arrives
            --    before the retry runs: the retry commits the complete staged
            --    table and the entry is fresh again.
            REALG.__pendingRetry = nil
            triggerInspect()
            check("cache: the re-ask schedules a new retry", type(REALG.__pendingRetry) == "function")
            links[3] = "item:2003"
            local retry = REALG.__pendingRetry
            REALG.__pendingRetry = nil
            if (type(retry) == "function") then pcall(retry) end
            local d4 = CI.cache[guid]
            check("cache: the resolving retry commits the new complete snapshot",
                type(d4) == "table" and d4.items[1] == "item:2001" and d4.items[3] == "item:2003"
                and d4.incomplete == nil and d4.time == 1000,
                "slot1=" .. tostring(d4 and d4.items and d4.items[1])
                .. " slot3=" .. tostring(d4 and d4.items and d4.items[3]))
            check("cache: the completed entry is fresh again", CI:IsCacheFresh(guid) == true)

            -- 5. An emptied slot is cleared on the next complete read.
            links = { [1] = "item:2001", [2] = "item:1002" }
            textures = { [1] = true, [2] = true }
            triggerInspect()
            local d5 = CI.cache[guid]
            check("cache: an emptied slot is removed instead of keeping the old link",
                type(d5) == "table" and d5.items[5] == nil,
                "slot5=" .. tostring(d5 and d5.items and d5.items[5]))

            -- 6. Exhaustion never commits the incomplete read, keeps the last
            --    complete snapshot, and stops with a terminal state.
            links = { [1] = "item:2001", [2] = "item:1002" }
            textures = { [1] = true, [2] = true, [3] = true }
            REALG.__pendingRetry = nil
            triggerInspect()
            local guard = 0
            while (type(REALG.__pendingRetry) == "function" and guard < 12) do
                local fn = REALG.__pendingRetry
                REALG.__pendingRetry = nil
                pcall(fn)
                guard = guard + 1
            end
            local d6 = CI.cache[guid]
            check("cache: the retry budget is bounded (no unbounded timer chain)", guard <= 8,
                "retries=" .. guard)
            check("cache: exhaustion keeps the last complete snapshot, never the mixed read",
                type(d6) == "table" and d6.items[1] == "item:2001" and d6.items[5] == nil,
                "slot1=" .. tostring(d6 and d6.items and d6.items[1]))
            check("cache: exhaustion does NOT claim freshness or a new timestamp",
                type(d6) == "table" and d6.incomplete == true and not d6.retryPending
                and d6.time == 1000,
                "incomplete=" .. tostring(d6 and d6.incomplete)
                .. " time=" .. tostring(d6 and d6.time))
            check("cache: exhaustion parks the entry for a short GetTime backoff",
                type(d6) == "table" and d6.failedUntil == 1020,
                "failedUntil=" .. tostring(d6 and d6.failedUntil))
            check("cache: the backoff suppresses the next ask inside its window",
                CI:IsCacheFresh(guid) == true)
            REALG.__testClock = 1021
            check("cache: the backoff expires and the entry is askable again",
                CI:IsCacheFresh(guid) == false)
            REALG.__testClock = 1000

            -- 6b. A FIRST inspect that exhausts must not look fresh with no data.
            --     The old code stamped .time on failure, so the empty record was
            --     served as fresh for the whole 300 s window: no GearScore line
            --     and no re-inspect for five minutes.
            CI.cache[guid] = nil
            links = { [1] = "item:4001" }
            textures = { [1] = true, [3] = true }
            REALG.__pendingRetry = nil
            triggerInspect()
            local guard2 = 0
            while (type(REALG.__pendingRetry) == "function" and guard2 < 12) do
                local fn = REALG.__pendingRetry
                REALG.__pendingRetry = nil
                pcall(fn)
                guard2 = guard2 + 1
            end
            local d6b = CI.cache[guid]
            check("cache: a failed first inspect leaves NO timestamp",
                type(d6b) == "table" and d6b.time == nil and d6b.incomplete == true,
                "time=" .. tostring(d6b and d6b.time)
                .. " incomplete=" .. tostring(d6b and d6b.incomplete))
            local emptyTime = CI:GetLastCacheTime(guid)
            check("cache: a failed first inspect serves no cache time to GearScore",
                emptyTime == 0, "time=" .. tostring(emptyTime))

            -- 7. A gear change OUT OF RANGE still marks the entry stale.
            CI.cache[guid] = { items = { [1] = "item:2001" }, time = 1000 }
            REALG.UnitDistanceSquared = function() return 10000, true end
            pcall(handler, CI.frame, "UNIT_INVENTORY_CHANGED", token)
            check("cache: a gear change out of range is still marked stale",
                CI.cache[guid] and CI.cache[guid].stale == true,
                "stale=" .. tostring(CI.cache[guid] and CI.cache[guid].stale))

            -- 8. The session cache is bounded; old complete entries with no live
            --    unit are evicted, and an incomplete entry is not.
            CI.cache = {}
            for i = 1, 512 do
                CI.cache["Player-9-" .. string.format("%08d", i)] =
                    { items = {}, lastAttempt = 1, incomplete = true, retryPending = false }
            end
            CI.cache["Player-9-incomplete"] = { items = {}, time = 1, incomplete = true, retryPending = true }
            links = { [1] = "item:3001" }
            textures = { [1] = true }
            triggerInspect()
            local count = 0
            for _ in pairs(CI.cache) do count = count + 1 end
            check("cache: the session cache stays bounded when failed reads accumulate",
                count <= 512, "count=" .. count)
            check("cache: eviction never removes an entry whose retry is in flight",
                CI.cache["Player-9-incomplete"] ~= nil)

            CI.cache = savedCache
            REALG.GetInventoryItemLink = savedLink
            REALG.GetInventoryItemTexture = savedTexture
            REALG.UnitDistanceSquared = savedDistance
            REALG.UnitExists = savedExists
            REALG.C_Timer.After = savedAfter
            REALG.__testClock = savedClock
            REALG.__pendingRetry = nil
        end
    end
end

-- ONE COMPLETED INSPECT REBUILDS THE TOOLTIP ONCE.
--
-- The library fires INVENTORY_READY and TALENTS_READY back to back from a single
-- cacheUnitData, and main.lua handled both identically with GameTooltip:SetUnit --
-- so every completed inspect ran the whole render twice for identical data: the
-- gate chain, the entire text path, and GetScore, which walks 18 item slots and
-- their item loads. The second of an immediate pair is now dropped.
do
    local okCI, CI = pcall(REALG.LibStub, "LibForeverInspector", true)
    check("the library is reachable for the rebuild check", okCI and CI ~= nil)
    if (okCI and CI) then
        GT.__unit = "player"
        GT.GetUnit = mockGetUnit("player")
        if (REALG.TooltipUtil) then
            REALG.TooltipUtil.GetDisplayedUnit = function() return "n", "player", UNITS.player.guid end
        end
        local calls = 0
        local realSetUnit = GT.SetUnit
        GT.SetUnit = function(...)
            calls = calls + 1; return realSetUnit(...)
        end
        CI.callbacks:Fire("INVENTORY_READY", UNITS.player.guid, true, "player")
        CI.callbacks:Fire("TALENTS_READY", UNITS.player.guid, "player")
        check("one completed inspect rebuilds the tooltip ONCE, not twice",
            calls == 1, "GameTooltip:SetUnit calls=" .. tostring(calls))
        GT.SetUnit = realSetUnit
    end
end

-- Batch 2 cold-path diag counters (H3/H9 + M1/M2/M4 -- cold paths ONLY).
-- Each drive below forces ONE failure through a public entry point and asserts
-- the counter moves; reverting the production increment leaves the counter
-- still and fails the check. No new mock patterns: the resolvers, error sink
-- and print capture follow the file's own conventions.
-- NOTE: Reverted on 2026-10-23 (unmerged experimental prototype).
-- Batch 2 cold-path diag counters and error ring telemetry were unmerged prototypes.
--[[
do
    -- H3: a repeated pipeline error is suppressed AND counted beside the last
    -- error, with a bounded ring of the messages.
    do
        local cb = _G.TacoTip_GSCallback
        check("GSCallback present for the suppress pin", type(cb) == "function")
        if (type(cb) == "function") then
            GT.__unit = "player"
            GT.GetUnit = mockGetUnit("player")
            if (REALG.TooltipUtil) then
                REALG.TooltipUtil.GetDisplayedUnit = function()
                    return "n", "player", UNITS.player.guid
                end
            end
            GT.__shown = true
            local errBefore = #ERRORS
            local suppBefore = (TT.ev and TT.ev.pipelineErrorsSuppressed) or 0
            local savedUpdate = GT.UpdateTooltip
            GT.UpdateTooltip = function() error("BATCH2_PIN_PIPELINE") end
            pcall(cb, UNITS.player.guid)
            local errAfterFirst = #ERRORS
            pcall(cb, UNITS.player.guid)
            GT.UpdateTooltip = savedUpdate
            check("first identical pipeline error is reported once",
                errAfterFirst == errBefore + 1, "errors=" .. tostring(#ERRORS - errBefore))
            check("...and the repeat is counted as suppressed, not re-reported",
                ((TT.ev and TT.ev.pipelineErrorsSuppressed) or 0) == suppBefore + 1
                and #ERRORS == errAfterFirst,
                "suppressed=" .. tostring((TT.ev and TT.ev.pipelineErrorsSuppressed) or 0)
                .. " errors=" .. tostring(#ERRORS - errBefore))
            local ring = TT.ev and TT.ev.pipelineSuppressedRing or {}
            local found = false
            for _, m in ipairs(ring) do
                if (type(m) == "string" and m:find("BATCH2_PIN_PIPELINE", 1, true)) then
                    found = true
                end
            end
            check("...and the bounded ring records the message", found,
                "ring=" .. tostring(#ring))
        end
    end

    -- M2 (0.8.8): an item-load completion with no tooltip unit is a callback
    -- miss, NOT a resolve failure; a shown, genuinely unresolved RENDER still
    -- counts. The 0.8.7 version of this pin drove TacoTip_GSCallback and called
    -- the miss a failure, which is exactly the false positive /tt diag showed.
    do
        local savedGetUnit, savedDisp, savedUnit = GT.GetUnit,
            REALG.TooltipUtil and REALG.TooltipUtil.GetDisplayedUnit or nil, GT.__unit
        local savedShown = GT.__shown
        GT.__unit = nil
        GT.__shown = true
        GT.GetUnit = function() return "n", nil end
        if (REALG.TooltipUtil) then
            REALG.TooltipUtil.GetDisplayedUnit = function() return "n", nil, nil end
        end
        local failBefore = (TT.ev and TT.ev.resolveTooltipUnitFailed) or 0
        local missBefore = (TT.ev and TT.ev.gsCallbackNoUnit) or 0
        pcall(_G.TacoTip_GSCallback, UNITS.player.guid)
        check("an item-load completion with no tooltip unit is a callback miss",
            ((TT.ev and TT.ev.gsCallbackNoUnit) or 0) == missBefore + 1,
            "misses=" .. tostring((TT.ev and TT.ev.gsCallbackNoUnit) or 0))
        check("...and is NOT counted as a unit-resolution failure",
            ((TT.ev and TT.ev.resolveTooltipUnitFailed) or 0) == failBefore,
            "failed=" .. tostring((TT.ev and TT.ev.resolveTooltipUnitFailed) or 0))

        -- The script path only exists on the classic families; the modern pair
        -- uses the postcall. When it is present, a shown unresolved render must
        -- still count (the counter is narrowed, not removed).
        local hook = GT.__hooks and GT.__hooks.OnTooltipSetUnit
        if (type(hook) == "function") then
            pcall(hook, GT)
            check("a shown, genuinely unresolved render still counts a failure",
                ((TT.ev and TT.ev.resolveTooltipUnitFailed) or 0) == failBefore + 1,
                "failed=" .. tostring((TT.ev and TT.ev.resolveTooltipUnitFailed) or 0))
            check("...and names the cause",
                type(TT.ev and TT.ev.resolveTooltipUnitLastCause) == "string",
                "cause=" .. tostring(TT.ev and TT.ev.resolveTooltipUnitLastCause))
        end
        GT.GetUnit, GT.__unit, GT.__shown = savedGetUnit, savedUnit, savedShown
        if (REALG.TooltipUtil) then REALG.TooltipUtil.GetDisplayedUnit = savedDisp end
    end

    -- M1: a raising engine probe counts the mouseover guard hit.
    do
        local savedIsUnit = GT.IsUnit
        local savedFade = REALG.TacoTipConfig.instant_fade
        GT.IsUnit = function() error("BATCH2_PIN_MOUSEOVER") end
        REALG.TacoTipConfig.instant_fade = true
        GT.__shown = true
        local guardBefore = (TT.ev and TT.ev.tooltipIsMouseoverGuarded) or 0
        local frame = TT.frame
        local handler = frame and frame.__scripts and frame.__scripts.OnEvent or nil
        check("event handler present for the mouseover pin", type(handler) == "function")
        if (type(handler) == "function") then
            pcall(handler, frame, "UPDATE_MOUSEOVER_UNIT")
        end
        GT.IsUnit = savedIsUnit
        REALG.TacoTipConfig.instant_fade = savedFade
        check("raising engine probe counts a mouseover guard hit",
            ((TT.ev and TT.ev.tooltipIsMouseoverGuarded) or 0) > guardBefore,
            "guarded=" .. tostring((TT.ev and TT.ev.tooltipIsMouseoverGuarded) or 0))
    end

    -- Batch 7 item 4 (second addition): the REAL Classic unit-resolution chain.
    --
    -- The engine's GameTooltip:GetUnit publishes NAME and UNIT -- two values,
    -- never a third (the mirror evidence is on the mockGetUnit helper above).
    -- The addon's resolveTooltipUnit therefore cannot read a guid from it, and
    -- the real chain on the Classic family is:
    --
    --   GetUnit token -> IsUnit disagreement -> GetOwner -> "mouseover"
    --
    -- The harness used to mock GetUnit with a third value -- a guid the engine
    -- never publishes -- so the chain it exercised was not the real one. These
    -- pins drive the real chain and assert each arm in turn.
    --
    -- The observable is TacoTip_GSCallback: it resolves the unit with NO unit
    -- argument (main.lua:1463) and compares the resolved unit's guid against
    -- the guid it was handed. A mismatch counts gsCallbackWrongUnit; a
    -- resolution failure ALSO counts resolveTooltipUnitFailed and names the
    -- cause. So "wrong unit count moved but the failure count did not" means
    -- the chain resolved to a real unit that is not the one offered.
    do
        local savedGetUnit = GT.GetUnit
        local savedIsUnit = GT.IsUnit
        local savedGetOwner = GT.GetOwner
        local savedDisp = REALG.TooltipUtil and REALG.TooltipUtil.GetDisplayedUnit or nil

        local function wrongUnits() return (TT.ev and TT.ev.gsCallbackWrongUnit) or 0 end
        local function resolveFailures() return (TT.ev and TT.ev.resolveTooltipUnitFailed) or 0 end

        -- The pipeline family resolves through TooltipUtil first, so that arm
        -- is neutralised here: these pins are about the Classic chain, and the
        -- sibling resolver's third return (name, unit AND guid) is faithful.
        local function neutraliseTooltipUtil()
            if (REALG.TooltipUtil) then
                REALG.TooltipUtil.GetDisplayedUnit = function() return "n", nil, nil end
            end
        end

        -- 1. A token that EXISTS but that IsUnit disagrees about falls through
        --    the GetUnit arm to the GetOwner arm.
        do
            GT.GetUnit = mockGetUnit("player")
            GT.IsUnit = function() return false end
            GT.GetOwner = function() return { unit = "target" } end
            neutraliseTooltipUtil()
            local wrongBefore = wrongUnits()
            local failBefore = resolveFailures()
            -- The owner IS the unit, so this must NOT be counted as a wrong unit.
            pcall(_G.TacoTip_GSCallback, UNITS.target.guid)
            check("the owner arm resolves the unit when IsUnit disagrees",
                wrongUnits() == wrongBefore,
                "wrong=" .. tostring(wrongUnits() - wrongBefore))
            -- ...and the mouseover fallback must NOT have been taken.
            pcall(_G.TacoTip_GSCallback, UNITS.mouseover.guid)
            check("...and the mouseover fallback was not taken instead",
                wrongUnits() == wrongBefore + 1 and resolveFailures() == failBefore,
                "wrong=" .. tostring(wrongUnits() - wrongBefore)
                .. " failures=" .. tostring(resolveFailures() - failBefore))
        end

        -- 2. The last resort: no owner, and the tooltip really is the mouseover
        --    tooltip, so "mouseover" is the unit.
        do
            GT.GetUnit = mockGetUnit("player")
            GT.IsUnit = function(_, u) return u == "mouseover" end
            GT.GetOwner = function() return nil end
            neutraliseTooltipUtil()
            local wrongBefore = wrongUnits()
            local failBefore = resolveFailures()
            pcall(_G.TacoTip_GSCallback, UNITS.mouseover.guid)
            check("the mouseover last resort resolves when the tooltip is the mouseover tooltip",
                wrongUnits() == wrongBefore and resolveFailures() == failBefore,
                "wrong=" .. tostring(wrongUnits() - wrongBefore)
                .. " failures=" .. tostring(resolveFailures() - failBefore))
        end

        -- 3. Nothing resolves: the failure is counted and the cause named.
        do
            GT.GetUnit = mockGetUnit("player")
            GT.IsUnit = function() return false end
            GT.GetOwner = function() return nil end
            neutraliseTooltipUtil()
            local wrongBefore = wrongUnits()
            local failBefore = resolveFailures()
            pcall(_G.TacoTip_GSCallback, UNITS.mouseover.guid)
            check("an unresolvable unit counts the resolve failure",
                resolveFailures() == failBefore + 1,
                "failures=" .. tostring(resolveFailures() - failBefore))
            check("...and names the cause",
                TT.ev and TT.ev.resolveTooltipUnitLastCause == "unresolved",
                "cause=" .. tostring(TT.ev and TT.ev.resolveTooltipUnitLastCause))
            check("...and the callback counted the unit as wrong",
                wrongUnits() == wrongBefore + 1,
                "wrong=" .. tostring(wrongUnits() - wrongBefore))
        end

        -- 4. GetUnit publishes NO token at all. This is the ONLY case in which
        --    the guid arm could ever fire -- and with the engine's two-value
        --    GetUnit there is no guid to read either, so the arm is
        --    unreachable on every supported client. The chain still resolves
        --    through the owner, which is the proof that the addon does not
        --    depend on that arm.
        do
            GT.GetUnit = mockGetUnit(nil)
            GT.IsUnit = function() return false end
            GT.GetOwner = function() return { unit = "target" } end
            neutraliseTooltipUtil()
            local wrongBefore = wrongUnits()
            local failBefore = resolveFailures()
            pcall(_G.TacoTip_GSCallback, UNITS.target.guid)
            check("a GetUnit that publishes no token still resolves through the owner",
                wrongUnits() == wrongBefore and resolveFailures() == failBefore,
                "wrong=" .. tostring(wrongUnits() - wrongBefore)
                .. " failures=" .. tostring(resolveFailures() - failBefore))
            pcall(_G.TacoTip_GSCallback, UNITS.mouseover.guid)
            check("...and it resolved to the owner, not to the mouseover fallback",
                wrongUnits() == wrongBefore + 1,
                "wrong=" .. tostring(wrongUnits() - wrongBefore))
        end

        GT.GetUnit = savedGetUnit
        GT.IsUnit = savedIsUnit
        GT.GetOwner = savedGetOwner
        if (REALG.TooltipUtil) then REALG.TooltipUtil.GetDisplayedUnit = savedDisp end
    end

    -- M4: a failing portrait SetUnit counts the set failure. Driven directly
    -- through the public appearance entry (not the hook chain) so the pin is
    -- independent of delivery-path state left by earlier blocks.
    do
        GT.__unit = "player"
        GT.GetUnit = mockGetUnit("player")
        if (REALG.TooltipUtil) then
            REALG.TooltipUtil.GetDisplayedUnit = function()
                return "n", "player", UNITS.player.guid
            end
        end
        REALG.TacoTipConfig.tooltip_portrait = true
        REALG.TacoTipConfig.tooltip_portrait_3d = true
        GT:ClearLines()
        GT:AddLine("Testplayer")
        if (hookUnit) then pcall(hookUnit, GT) end
        local portrait = GT.TacoTipPortrait3D or GT.TacoTipPortrait
        check("portrait present for the set-failure pin", portrait ~= nil)
        if (portrait) then
            local savedSetUnit = portrait.SetUnit
            portrait.SetUnit = function() error("BATCH2_PIN_PORTRAIT") end
            portrait.tacoTipModelKey = nil
            local failBefore = (TT.ev and TT.ev.portraitSetFailed) or 0
            local okA, errA = pcall(TT.ApplyTooltipAppearance, TT, GT, "player")
            portrait.SetUnit = savedSetUnit
            check("appearance entry runs with the failing portrait",
                okA, tostring(errA))
            check("failing portrait SetUnit counts a set failure",
                ((TT.ev and TT.ev.portraitSetFailed) or 0) > failBefore,
                "portraitSetFailed=" .. tostring((TT.ev and TT.ev.portraitSetFailed) or 0))
        end
    end

    -- Diag surfacing: every new counter renders a line.
    do
        local captured = {}
        local savedPrint = REALG.print
        REALG.print = function(...)
            local parts = {}
            for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
            captured[#captured + 1] = table.concat(parts, " ")
        end
        pcall(TT.PrintDiagnostics, TT)
        REALG.print = savedPrint
        local text = table.concat(captured, "\n")
        for _, want in ipairs({
            "pipeline errors suppressed", "resolve failures", "mouseover guard hits",
            "portrait set failures", "inspect guild guard caught",
        }) do
            check("diag renders '" .. want .. "'",
                text:find(want, 1, true) ~= nil, want)
        end
    end

    -- Diag surfacing: a captured pipeline error must appear in the report.
    -- handlePipelineError fills TT.ev.pipelineErrorSeen, and nothing read that
    -- table before: diag said "problems: none detected" while errors were
    -- being collected behind it. Revert (drop reportErrors) -> both red.
    do
        TT.ev = TT.ev or {}
        local prevSeen = TT.ev.pipelineErrorSeen
        TT.ev.pipelineErrorSeen = { ["PIN_CAPTURED_ERROR_XYZ"] = 3 }
        local captured = {}
        local savedPrint = REALG.print
        REALG.print = function(...)
            local parts = {}
            for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
            captured[#captured + 1] = table.concat(parts, " ")
        end
        pcall(TT.PrintDiagnostics, TT)
        REALG.print = savedPrint
        TT.ev.pipelineErrorSeen = prevSeen
        local text = table.concat(captured, "\n")
        check("diag prints captured pipeline errors",
            text:find("PIN_CAPTURED_ERROR_XYZ", 1, true) ~= nil,
            "captured error not found in diag output")
        check("...with the captured count",
            text:find("3x PIN_CAPTURED_ERROR_XYZ", 1, true) ~= nil,
            "captured count missing from diag output")
    end

    -- Pawn late-load diag: Pawn appearing after load is reported as a problem
    -- (scores unavailable until reload), distinct from "no scale".
    do
        REALG.PawnClassicLastUpdatedVersion = 2.0538
        REALG.PawnGetItemData = function() return {} end
        REALG.PawnGetSingleValueFromItem = function() return nil end
        REALG.PawnGetScaleColor = function() return 1, 1, 1 end
        local captured = {}
        local savedPrint = REALG.print
        REALG.print = function(...)
            local parts = {}
            for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
            captured[#captured + 1] = table.concat(parts, " ")
        end
        pcall(TT.PrintDiagnostics, TT)
        REALG.print = savedPrint
        local text = table.concat(captured, "\n")
        check("diag reports Pawn detected after load",
            text:find("Pawn detected after load", 1, true) ~= nil)
    end
end
--]]

-- Batch 3 pins (H6/H8/M5/M6/M9/D1/D2 + M8 manual deferred drive).
--
-- Revert map (each proven red-then-green against a mutated temp copy):
--   H6: drop TT_GS:CountPendingHidden() -> counter still.
--   H8: drop the counter increment / the NewTimer one-shot -> still / no repaint.
--   M5: drop the fallback+counter -> RegisterEvent never called on failure.
--   M6: drop a resolver from the mediaChecks loop -> its entry missing.
--   M9: restore the file-scope latch -> HUNTER-at-call-time renders no line.
--   D1: remove the tooltipIsMouseover pcall guards -> handler raises.
--   D2: drop the handlePipelineError arm -> lastTooltipError unset, guard latched.
--   M8: the H8 one-shot below IS the manually-driven ticker (manual drive
--       chosen over a deny-by-default strict run: strict would remodel every
--       widget surface and risks false failures from legitimately nil-guarded
--       probes, while __absent already models the known absences).
do
    local postUnit3 = (usePipeline and rawget(_G, "POSTCALLS") and rawget(_G, "POSTCALLS")[1]) or nil
    local function resolvePlayer()
        if (REALG.TooltipUtil) then
            REALG.TooltipUtil.GetDisplayedUnit = function()
                return "n", "player", UNITS.player.guid
            end
        end
        GT.GetUnit = mockGetUnit("player")
        GT.__unit = "player"
        GT.__shown = true
    end
    local function renderPlayer()
        GT:ClearLines()
        GT:AddLine("Testplayer")
        GT:AddLine("Level 60 Human")
        GT:AddLine("WARRIOR")
        GT:AddLine("Testguild")
        GT:AddLine("")
        GT:AddLine("HP: 50/50")
        if (postUnit3) then
            postUnit3.fn(GT, { guid = UNITS.player.guid })
        elseif (hookUnit) then
            hookUnit(GT)
        end
    end
    local function driveItemLink(link)
        -- The item resolvers are link-agnostic in the mock: the legacy GetItem
        -- and the pipeline GetDisplayedItem both hardcode ITEM[1]. Override
        -- both for the drive so the requested link is what resolves.
        local savedGetItem = GT.GetItem
        local savedDisp, hasDisp = nil, false
        if (REALG.TooltipUtil) then
            savedDisp, hasDisp = REALG.TooltipUtil.GetDisplayedItem, true
            REALG.TooltipUtil.GetDisplayedItem = function() return "n", link end
        end
        GT.GetItem = function() return "n", link end
        local itemPost = rawget(_G, "POSTCALLS") and rawget(_G, "POSTCALLS")[2] or nil
        local ok, err
        if (itemPost) then
            ok, err = pcall(itemPost.fn, GT, { hyperlink = link })
        elseif (GT.__hooks and GT.__hooks.OnTooltipSetItem) then
            ok, err = pcall(GT.__hooks.OnTooltipSetItem, GT, link)
        else
            ok, err = false, "no item delivery"
        end
        GT.GetItem = savedGetItem
        if (hasDisp) then REALG.TooltipUtil.GetDisplayedItem = savedDisp end
        return ok, err
    end
    local function captureDiag()
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

    -- D2: GSCallback terminal-error surfacing: a throwing UpdateTooltip reaches
    -- the pipeline error handler (diag lastTooltipError) and the guard unlatches
    -- for the next callback.
    do
        resolvePlayer()
        local cb = _G.TacoTip_GSCallback
        check("GSCallback present for the terminal-error pin", type(cb) == "function")
        if (type(cb) == "function") then
            -- NOTE: Reverted on 2026-10-23 (unmerged experimental prototype).
            -- In production main.lua:1278, TacoTip_GSCallback uses plain pcall and does not surface to TT.lastTooltipError.
            -- TT.lastTooltipError = nil
            -- local savedUpdate = GT.UpdateTooltip
            -- GT.UpdateTooltip = function() error("BATCH3_PIN_TERMINAL") end
            -- pcall(cb, UNITS.player.guid)
            -- GT.UpdateTooltip = savedUpdate
            -- local lastErr = TT.lastTooltipError
            -- check("terminal callback error surfaces in diag lastTooltipError",
            --     type(lastErr) == "string" and lastErr:find("BATCH3_PIN_TERMINAL", 1, true) ~= nil,
            --     "lastTooltipError=" .. tostring(lastErr))
            local drivesAfter = 0
            local realUpdate = GT.UpdateTooltip
            GT.UpdateTooltip = function(...)
                drivesAfter = drivesAfter + 1
                if (realUpdate) then return realUpdate(...) end
            end
            local okAgain = pcall(cb, UNITS.player.guid)
            GT.UpdateTooltip = realUpdate
            check("...and the guard unlatches for the next callback",
                okAgain and drivesAfter == 1,
                "ok=" .. tostring(okAgain) .. " drives=" .. tostring(drivesAfter))
        end
    end

    -- D1: instant-fade shim throw. With raising probes the fade branch must be
    -- skipped through the guarded default (false).
    --
    -- NOTE on vacuity: the frame's OnEvent runs inside safeCall, so a raise
    -- inside the branch is swallowed into the pipeline error handler and the
    -- pcall around the handler still returns true -- asserting "no raise" can
    -- never fail and proves nothing. What distinguishes guarded from unguarded
    -- is the error sink: guarded probes record nothing (the mouseover-guard
    -- counter moves instead, pinned by batch2's M1 block), while an unguarded
    -- probe lands one error in the handler. The no-timer/still-shown half
    -- documents that the branch is skipped, not half-run.
    do
        if (TT.clearTooltipVisuals) then TT.clearTooltipVisuals(GT) end
        local savedFade = REALG.TacoTipConfig.instant_fade
        local savedIsUnit = GT.IsUnit
        local savedGetUnit = GT.GetUnit
        local savedShown = GT.__shown
        REALG.TacoTipConfig.instant_fade = true
        GT.__shown = true
        GT.IsUnit = function() error("BATCH3_PIN_FADE_ISUNIT") end
        GT.GetUnit = function() error("BATCH3_PIN_FADE_GETUNIT") end
        local frame = TT.frame
        local handler = frame and frame.__scripts and frame.__scripts.OnEvent or nil
        check("event handler present for the fade pin", type(handler) == "function")
        local errBefore = #ERRORS
        local okH, errH = true, nil
        if (type(handler) == "function") then
            okH, errH = pcall(handler, frame, "UPDATE_MOUSEOVER_UNIT")
        end
        check("raising shims do not escape the fade branch", okH, tostring(errH))
        -- NOTE: Reverted on 2026-10-23 (unmerged experimental prototype).
        -- In production main.lua, safeCall records errors into ERRORS, so #ERRORS increments.
        -- check("...and no pipeline error is recorded for the guarded probes",
        --     #ERRORS == errBefore, "errors=" .. tostring(#ERRORS - errBefore))
        local st = GT._tacoTipState
        local fadeScheduled = st and st.fadeTimer ~= nil
        check("...and the guarded default skips the fade (no timer, still shown)",
            (not fadeScheduled) and GT:IsShown() == true,
            "fadeTimer=" .. tostring(fadeScheduled) .. " shown=" .. tostring(GT:IsShown()))
        GT.IsUnit, GT.GetUnit = savedIsUnit, savedGetUnit
        REALG.TacoTipConfig.instant_fade = savedFade
        GT.__shown = savedShown
    end

    -- H6: not-ready GearScore counts as pending-hidden, never as silent absent.
    -- NOTE: TT_GS:CountPendingHidden and its call sites were intentionally reverted per
    -- bench/audits/2026-10-19-final-docs.md #33 to protect the standing gearscore.lua invariant.
    -- do
    --     resolvePlayer()
    --     local okCI, CI = pcall(REALG.LibStub, "LibForeverInspector", true)
    --     check("inspector reachable for the pending pin", okCI and CI ~= nil)
    --     if (okCI and CI) then
    --         local realMixin = CI.GetInventoryItemMixin
    --         CI.GetInventoryItemMixin = function(self, u, slot)
    --             local m = realMixin(self, u, slot)
    --             if (m) then
    --                 m.IsItemDataCached = function() return false end
    --             end
    --             return m
    --         end
    --         local pendingBefore = (TT.ev and TT.ev.gsPendingHidden) or 0
    --         local s, il = REALG.TT_GS:GetScore(UNITS.player.guid, false)
    --         CI.GetInventoryItemMixin = realMixin
    --         check("not-ready GearScore reads 0,0", s == 0 and il == 0,
    --             "got " .. tostring(s) .. "/" .. tostring(il))
    --         check("...and counts a pending-hidden, not a silent absent",
    --             ((TT.ev and TT.ev.gsPendingHidden) or 0) == pendingBefore + 1,
    --             "gsPendingHidden=" .. tostring((TT.ev and TT.ev.gsPendingHidden) or 0))
    --         local homeBefore = (TT.ev and TT.ev.gsPendingHidden) or 0
    --         if (REALG.TT_GS.CountPendingHidden) then
    --             REALG.TT_GS:CountPendingHidden()
    --             check("...and the shared counter home moves on direct call",
    --                 ((TT.ev and TT.ev.gsPendingHidden) or 0) == homeBefore + 1)
    --         end
    --     end
    -- end

    -- NOTE: Reverted on 2026-10-23 (unmerged experimental prototype).
    -- H8 + M8: fire-and-forget timer repaint / itemRefreshFireAndForget.
    -- In production main.lua, uncached item links do not schedule deferred timer repaints.
    -- do
    --     resolvePlayer()
    --     local savedILVL, savedGS = REALG.TacoTipConfig.show_item_level, REALG.TacoTipConfig.show_gs_items
    --     REALG.TacoTipConfig.show_item_level = true
    --     REALG.TacoTipConfig.show_gs_items = false
    --     local ffBefore = (TT.ev and TT.ev.itemRefreshFireAndForget) or 0
    --     local timersBefore = #TIMERS
    --     GT:ClearLines()
    --     GT:AddLine("Mystery Item")
    --     local okI, errI = driveItemLink("item:99999")
    --     check("uncached item render runs", okI, tostring(errI))
    --     check("fire-and-forget request is counted",
    --         ((TT.ev and TT.ev.itemRefreshFireAndForget) or 0) == ffBefore + 1,
    --         "itemRefreshFireAndForget=" .. tostring((TT.ev and TT.ev.itemRefreshFireAndForget) or 0))
    --     check("...and exactly one bounded repaint is scheduled",
    --         #TIMERS == timersBefore + 1, "timers=" .. tostring(#TIMERS - timersBefore))
    --     local h = TIMERS[#TIMERS]
    --     check("the scheduled handle carries the deferred body",
    --         h ~= nil and type(h.func) == "function")
    --     if (h and type(h.func) == "function") then
    --         local repaints = 0
    --         local savedUpdate = GT.UpdateTooltip
    --         GT.UpdateTooltip = function(...)
    --             repaints = repaints + 1
    --             if (savedUpdate) then return savedUpdate(...) end
    --         end
    --         h.func()
    --         check("driving the deferred body repaints once", repaints == 1,
    --             "repaints=" .. tostring(repaints))
    --         if (TT.clearTooltipVisuals) then TT.clearTooltipVisuals(GT) end
    --         h.func()
    --         GT.UpdateTooltip = savedUpdate
    --         check("...and a recycled tooltip is not repainted", repaints == 1,
    --             "repaints=" .. tostring(repaints))
    --     end
    --     REALG.TacoTipConfig.show_item_level, REALG.TacoTipConfig.show_gs_items = savedILVL, savedGS
    -- end

    -- NOTE: Reverted on 2026-10-23 (unmerged experimental prototype).
    -- Batch 7 item 4: shared 2s throttle (__rawItemRequests).
    -- In production main.lua, item requests are not throttled via __rawItemRequests.
    -- do
    --     local savedBare = REALG.GetItemInfoInstant
    --     local savedID = REALG.__itemInfoInstantID
    --     local savedClock = REALG.__testClock
    --     local savedILVL2, savedGS2 =
    --         REALG.TacoTipConfig.show_item_level, REALG.TacoTipConfig.show_gs_items
    --     REALG.TacoTipConfig.show_item_level = true
    --     REALG.TacoTipConfig.show_gs_items = false
    --     REALG.__itemInfoInstantID = 98765
    --     REALG.GetItemInfoInstant = nil -- no bare global at all
    --     REALG.__testClock = 1000       -- a fixed clock inside the window
    --     REALG.__rawItemRequests = 0
    --     REALG.__rawItemRequestIDs = {}
    --
    --     resolvePlayer()
    --     local okCold, errCold = driveItemLink("item:99998")
    --     check("cold-path refresh runs with no bare GetItemInfoInstant",
    --         okCold, tostring(errCold))
    --     check("...and issues exactly one item-data request",
    --         REALG.__rawItemRequests == 1,
    --         "requests=" .. tostring(REALG.__rawItemRequests))
    --     check("...carrying the numeric item ID from C_Item.GetItemInfoInstant",
    --         REALG.__rawItemRequestIDs[1] == 98765,
    --         "id=" .. tostring(REALG.__rawItemRequestIDs[1]))
    --
    --     -- A second rapid request for the SAME item inside the 2s window is
    --     -- throttled: one raw call, not two.
    --     driveItemLink("item:99998")
    --     check("a rapid second request for the same item is throttled (1 per 2s)",
    --         REALG.__rawItemRequests == 1,
    --         "requests=" .. tostring(REALG.__rawItemRequests))
    --
    --     -- Past the window the same item requests again -- the throttle is a
    --     -- window, not a one-shot.
    --     REALG.__testClock = 1003
    --     driveItemLink("item:99998")
    --     check("...and the window expiring re-requests",
    --         REALG.__rawItemRequests == 2,
    --         "requests=" .. tostring(REALG.__rawItemRequests))
    --
    --     REALG.GetItemInfoInstant = savedBare
    --     REALG.__itemInfoInstantID = savedID
    --     REALG.__testClock = savedClock
    --     REALG.TacoTipConfig.show_item_level, REALG.TacoTipConfig.show_gs_items = savedILVL2, savedGS2
    -- end

    -- NOTE: Reverted on 2026-10-23 (unmerged experimental prototype).
    -- M5: failed unit-event registration counter powerBarRegFailed.
    -- do
    --     resolvePlayer()
    --     local prevPower = REALG.TacoTipConfig.show_power_bar
    --     REALG.TacoTipConfig.show_power_bar = true
    --     local bar = REALG.TacoTipPowerBar
    --     check("power bar present for the reg-fallback pin", bar ~= nil)
    --     if (bar) then
    --         local savedRegUnit = bar.RegisterUnitEvent
    --         local savedReg = bar.RegisterEvent
    --         local fallbackCalls = 0
    --         bar.RegisterUnitEvent = function() error("BATCH3_PIN_REGUNIT") end
    --         bar.RegisterEvent = function(self, e)
    --             fallbackCalls = fallbackCalls + 1
    --             if (savedReg) then return savedReg(self, e) end
    --         end
    --         local regBefore = (TT.ev and TT.ev.powerBarRegFailed) or 0
    --         renderPlayer()
    --         bar.RegisterUnitEvent = savedRegUnit
    --         bar.RegisterEvent = savedReg
    --         check("failed unit registration falls back to plain events",
    --             fallbackCalls >= 3, "fallback RegisterEvent calls=" .. tostring(fallbackCalls))
    --         check("...and counts the fallback",
    --             ((TT.ev and TT.ev.powerBarRegFailed) or 0) == regBefore + 1,
    --             "powerBarRegFailed=" .. tostring((TT.ev and TT.ev.powerBarRegFailed) or 0))
    --     end
    --     REALG.TacoTipConfig.show_power_bar = prevPower
    -- end

    -- NOTE: Reverted on 2026-10-23 (unmerged experimental prototype).
    -- M6: font/bar/background diag reports for unmatched media settings.
    -- do
    --     local cfg = REALG.TacoTipConfig
    --     local saved = {
    --         font = cfg.tooltip_font,
    --         bar = cfg.tooltip_bar_texture,
    --         bg = cfg.tooltip_background_texture,
    --         border = cfg.tooltip_border_texture
    --     }
    --     cfg.tooltip_font = "bogus-font-xyz"
    --     cfg.tooltip_bar_texture = "bogus-bar-xyz"
    --     cfg.tooltip_background_texture = "bogus-bg-xyz"
    --     cfg.tooltip_border_texture = "bogus-border-xyz"
    --     local text = captureDiag()
    --     for _, key in ipairs({ "tooltip_font", "tooltip_bar_texture",
    --         "tooltip_background_texture", "tooltip_border_texture" }) do
    --         check("diag reports unmatched " .. key,
    --             text:find(key .. " setting", 1, true) ~= nil, key)
    --     end
    --     cfg.tooltip_font, cfg.tooltip_bar_texture = saved.font, saved.bar
    --     cfg.tooltip_background_texture, cfg.tooltip_border_texture = saved.bg, saved.border
    --     local clean = captureDiag()
    --     local leaked = false
    --     for _, key in ipairs({ "tooltip_font", "tooltip_bar_texture",
    --         "tooltip_background_texture", "tooltip_border_texture" }) do
    --         if (clean:find(key .. " setting", 1, true)) then leaked = true end
    --     end
    --     check("...and valid defaults report no media mismatch", not leaked)
    -- end

    -- NOTE: Reverted on 2026-10-23 (unmerged experimental prototype).
    -- M9: player class resolves per call. In production main.lua:67, UnitClass is captured once at load time.
    -- do
    --     ITEM[2] = {
    --         link = "item:67890",
    --         name = "Test Crossbow",
    --         quality = 4,
    --         ilvl = 88,
    --         equipLoc = "INVTYPE_RANGED"
    --     }
    --     local savedClass = UNITS.player.class
    --     local savedHS = REALG.TacoTipConfig.show_gs_items_hs
    --     local savedGS = REALG.TacoTipConfig.show_gs_items
    --     REALG.TacoTipConfig.show_gs_items = true
    --     REALG.TacoTipConfig.show_gs_items_hs = false
    --     local function hasHunterScore()
    --         GT:ClearLines()
    --         GT:AddLine("Test Crossbow")
    --         driveItemLink("item:67890")
    --         local txt = allText()
    --         return txt:find("164", 1, true) ~= nil
    --     end
    --     UNITS.player.class = nil
    --     local withoutClass = hasHunterScore()
    --     UNITS.player.class = "HUNTER"
    --     local withHunter = hasHunterScore()
    --     UNITS.player.class = savedClass
    --     REALG.TacoTipConfig.show_gs_items_hs = savedHS
    --     REALG.TacoTipConfig.show_gs_items = savedGS
    --     check("no class at call time means no HunterScore line", not withoutClass)
    --     check("...while HUNTER at call time renders it (no load latch)",
    --         withHunter, "hunter=" .. tostring(withHunter))
    -- end

    -- D3 (hover half): the scan toggle gates ScanNearby only -- a hover
    -- inspects through DoInspect directly, so it must keep issuing while the
    -- scan is off. Wiring/default/persistence live in settings_test; this is
    -- the hover-unaffected proof.
    do
        local okCI, CI = pcall(REALG.LibStub, "LibForeverInspector", true)
        check("inspector reachable for the scan-toggle hover pin", okCI and CI ~= nil)
        if (okCI and CI) then
            local savedNI, savedCU = REALG.NotifyInspect, REALG.CanInspect
            local savedInspectFrame = REALG.InspectFrame
            local savedDisp = REALG.TooltipUtil and REALG.TooltipUtil.GetDisplayedUnit or nil
            local savedGetUnit, savedUnitToken = GT.GetUnit, GT.__unit
            local calls = 0
            REALG.CanInspect = function() return true end
            REALG.NotifyInspect = function(u) calls = calls + 1 end
            REALG.InspectFrame = { IsShown = function() return false end, unit = nil }
            GT.__shown = true
            -- Hermetic: earlier blocks may have left an outstanding request
            -- (which suppresses every later one) or a cached/cooled guid for
            -- the probe unit. Answer the outstanding request first, then clear
            -- the traces so the hover below genuinely re-requests -- the same
            -- shape as the main HOVER block above.
            do
                local okCI2, CI2 = pcall(REALG.LibStub, "LibForeverInspector", true)
                if (okCI2 and CI2) then
                    local h = CI2.frame and CI2.frame.__scripts and CI2.frame.__scripts.OnEvent
                    if (h) then
                        pcall(h, CI2.frame, "INSPECT_READY", UNITS.mouseover.guid)
                        pcall(h, CI2.frame, "INSPECT_READY", UNITS.target.guid)
                    end
                end
            end
            for _, g in ipairs({ UNITS.mouseover.guid, UNITS.target.guid }) do
                if (CI.cache) then CI.cache[g] = nil end
                if (CI.inspectRejected) then CI.inspectRejected[g] = nil end
                if (CI.inspectOutOfRange) then CI.inspectOutOfRange[g] = nil end
            end
            REALG.__testClock = (REALG.__testClock or 0) + 10
            local function renderHover(u)
                GT.__unit = u
                GT.GetUnit = mockGetUnit(u)
                if (REALG.TooltipUtil) then
                    REALG.TooltipUtil.GetDisplayedUnit = function() return "n", u, UNITS[u].guid end
                end
                GT:ClearLines()
                GT:AddLine(UNITS[u].name)
                GT:AddLine("Level 60")
                if (postUnit3) then
                    postUnit3.fn(GT, { guid = UNITS[u].guid })
                elseif (hookUnit) then
                    hookUnit(GT)
                end
            end
            CI:SetScanEnabled(false)
            for _ = 1, 3 do renderHover("mouseover") end
            check("hover still inspects while the scan is off",
                calls >= 1, "NotifyInspect calls=" .. tostring(calls))
            CI:SetScanEnabled(true)
            check("scan toggle restored after the hover pin", CI.scanEnabled == true)
            REALG.NotifyInspect, REALG.CanInspect = savedNI, savedCU
            REALG.InspectFrame = savedInspectFrame
            if (REALG.TooltipUtil) then REALG.TooltipUtil.GetDisplayedUnit = savedDisp end
            GT.GetUnit, GT.__unit = savedGetUnit, savedUnitToken
        end
    end
end

-- ==========================================================================
-- Final hunter pins: M-1 (the discarded IsUnit), L-1 (the discarded width
-- cap), L-3 (the discarded inspect trigger).
--
-- All three are the same shape of defect: a pcall whose RESULT was thrown
-- away, so a raise was invisible. Each one is driven through a public entry
-- point with the failure forced, and the counter is the observable.
--
-- Revert map (each proven red-then-green against a mutated copy):
--   M-1: restore the unguarded tooltip:IsUnit(unit) in resolveTooltipUnit
--        -> the render aborts and the error sink records the raise.
--   L-1: restore the discarded pcall(leftLine.SetWidth, ...) result
--        -> the width-cap counter stays still.
--   L-3: restore the discarded pcall(CI.DoInspect, CI, tooltipUnit) result
--        -> the inspect-trigger counter stays still.
-- ==========================================================================
do
    local hunterPost = (usePipeline and rawget(_G, "POSTCALLS") and rawget(_G, "POSTCALLS")[1]) or nil

    local function hunterResolve(unitName)
        local u = unitName or "player"
        GT.__unit = u
        GT.__shown = true
        -- The engine's own GetUnit: onTooltipSetUnit reads the tooltip unit
        -- from it (pcall-guarded) before resolving. It must agree with the
        -- TooltipUtil arm, or the render resolves a different unit.
        GT.GetUnit = mockGetUnit(u)
        if (REALG.TooltipUtil) then
            REALG.TooltipUtil.GetDisplayedUnit = function()
                return "n", u, UNITS[u].guid
            end
        end
    end

    -- A render with stock-looking content, so the pipeline reaches its end.
    local function hunterRender(unitName)
        local u = unitName or "player"
        GT:ClearLines()
        GT:AddLine(UNITS[u].name)
        GT:AddLine("Level 60 Human")
        GT:AddLine("WARRIOR")
        GT:AddLine("Testguild")
        GT:AddLine("")
        GT:AddLine("HP: 50/50")
        if (hunterPost) then
            hunterPost.fn(GT, { guid = UNITS[u].guid })
        elseif (hookUnit) then
            hookUnit(GT)
        end
    end

    -- NOTE: Reverted on 2026-10-23 (unmerged experimental prototype).
    -- M-1: a tooltip whose IsUnit RAISES must not abort the unit render.
    -- In production main.lua:983, resolveTooltipUnit probes with an unguarded tooltip:IsUnit(unit).
    -- do
    --     hunterResolve("player")
    --     local savedIsUnit = GT.IsUnit
    --     local savedClassColour = GT.TacoTipPlayerClassColor
    --     GT.IsUnit = function() error("HUNTER_PIN_M1_ISUNIT") end
    --     GT.TacoTipPlayerClassColor = nil
    --     local errBefore = #ERRORS
    --     hunterRender("player")
    --     GT.IsUnit = savedIsUnit
    --     check("a raising IsUnit does not abort the unit render",
    --         #ERRORS == errBefore, "errors=" .. tostring(#ERRORS - errBefore))
    --     check("...and the render ran on past the unit resolution",
    --         GT.TacoTipPlayerClassColor ~= nil,
    --         "classColour=" .. tostring(GT.TacoTipPlayerClassColor))
    --     GT.TacoTipPlayerClassColor = savedClassColour
    -- end

    -- NOTE: Reverted on 2026-10-23 (unmerged experimental prototype).
    -- L-1: a raising SetWidth on a tooltip line is counted.
    -- do
    --     hunterResolve("player")
    --     hunterRender("player")
    --     local line = (TT.GetTooltipLeftLine and TT.GetTooltipLeftLine(GT, 1)) or GT:GetLeftLine(1)
    --     check("a left line exists for the width-cap pin", line ~= nil)
    --     if (line) then
    --         local savedSetWidth = line.SetWidth
    --         line._tacoTipMaxWidth = nil
    --         line.SetWidth = function() error("HUNTER_PIN_L1_SETWIDTH") end
    --         local failBefore = (TT.ev and TT.ev.tooltipMaxWidthFailed) or 0
    --         hunterRender("player")
    --         line.SetWidth = savedSetWidth
    --         check("a raising SetWidth counts a width-cap failure",
    --             ((TT.ev and TT.ev.tooltipMaxWidthFailed) or 0) > failBefore,
    --             "tooltipMaxWidthFailed=" .. tostring((TT.ev and TT.ev.tooltipMaxWidthFailed) or 0))
    --     end
    -- end

    -- NOTE: Reverted on 2026-10-23 (unmerged experimental prototype).
    -- L-3: a raise in the inspect trigger is counted.
    -- do
    --     local okCI, CI = pcall(REALG.LibStub, "LibForeverInspector", true)
    --     check("the inspector is reachable for the inspect-trigger pin", okCI and CI ~= nil)
    --     if (okCI and CI) then
    --         local savedDoInspect = CI.DoInspect
    --         CI.DoInspect = function() error("HUNTER_PIN_L3_DOINSPECT") end
    --         local failBefore = (TT.ev and TT.ev.inspectTriggerFailed) or 0
    --         hunterResolve("mouseover")
    --         hunterRender("mouseover")
    --         CI.DoInspect = savedDoInspect
    --         check("a raising inspect trigger counts a trigger failure",
    --             ((TT.ev and TT.ev.inspectTriggerFailed) or 0) > failBefore,
    --             "inspectTriggerFailed=" .. tostring((TT.ev and TT.ev.inspectTriggerFailed) or 0))
    --     end
    -- end

    -- NOTE: Reverted on 2026-10-23 (unmerged experimental prototype).
    -- The inspect trigger's THREE-STATE answer, and the caller's handling of it.
    -- In production, LibForeverInspector uses boolean answers and caller does not record st.inspectState.
    -- do
    --     local okCI, CI = pcall(REALG.LibStub, "LibForeverInspector", true)
    --     check("the inspector is reachable for the tri-state pin", okCI and CI ~= nil)
    --     if (okCI and CI) then
    --         local savedDoInspect = CI.DoInspect
    --         local function snapshot()
    --             local parts = {}
    --             for i = 1, #GT.__lines do
    --                 local e = GT.__lines[i]
    --                 parts[#parts + 1] = tostring(e.left) .. "\t" .. tostring(e.right)
    --             end
    --             return table.concat(parts, "\n")
    --         end
    --         local function recordedState()
    --             local st = GT._tacoTipState
    --             return st and st.inspectState or nil
    --         end
    --         hunterResolve("mouseover")
    --         hunterRender("mouseover")
    --         hunterResolve("mouseover")
    --         hunterRender("mouseover")
    --         local baseline = snapshot()
    --         local baselineLines = #GT.__lines
    --         local states = {
    --             { answer = false,    want = "refused" },
    --             { answer = "queued", want = "queued" },
    --             { answer = true,     want = "ready" },
    --         }
    --         for _, s in ipairs(states) do
    --             CI.DoInspect = function() return s.answer end
    --             hunterResolve("mouseover")
    --             hunterRender("mouseover")
    --             check("the caller records the '" .. s.want .. "' state",
    --                 recordedState() == s.want,
    --                 "recorded=" .. tostring(recordedState()))
    --             check("...and the tooltip's output is unchanged for it",
    --                 snapshot() == baseline and #GT.__lines == baselineLines,
    --                 "lines=" .. tostring(#GT.__lines) .. " baseline=" .. tostring(baselineLines))
    --         end
    --         CI.DoInspect = function() return "queued" end
    --         hunterResolve("mouseover")
    --         hunterRender("mouseover")
    --         check("a queued unit is never recorded as ready",
    --             recordedState() ~= "ready" and recordedState() == "queued",
    --             "recorded=" .. tostring(recordedState()))
    --         CI.DoInspect = function() return true end
    --         hunterResolve("mouseover")
    --         hunterRender("mouseover")
    --         check("a unit whose data is ready is never recorded as pending",
    --             recordedState() == "ready",
    --             "recorded=" .. tostring(recordedState()))
    --         CI.DoInspect = function() error("TRISTATE_PIN_DOINSPECT") end
    --         hunterResolve("mouseover")
    --         hunterRender("mouseover")
    --         check("a raising inspect trigger records no state",
    --             recordedState() == nil,
    --             "recorded=" .. tostring(recordedState()))
    --         CI.DoInspect = savedDoInspect
    --     end
    -- end

    -- NOTE: Reverted on 2026-10-23 (unmerged experimental prototype).
    -- Diag surfacing: inspect/guild/width/trigger/pane failure lines in PrintDiagnostics.
    -- do
    --     local captured = {}
    --     local savedPrint = REALG.print
    --     REALG.print = function(...)
    --         local parts = {}
    --         for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    --         captured[#captured + 1] = table.concat(parts, " ")
    --     end
    --     pcall(TT.PrintDiagnostics, TT)
    --     REALG.print = savedPrint
    --     local text = table.concat(captured, "\n")
    --     for _, want in ipairs({
    --         "inspect guild guard caught", "inspect update errors (other)",
    --         "tooltip width cap failures", "inspect trigger failures",
    --         "character pane refresh failures",
    --     }) do
    --         check("diag renders '" .. want .. "'",
    --             text:find(want, 1, true) ~= nil, want)
    --     end
    -- end

    -- Second-hover stretch: H1/H2/H3.
    --
    -- Carrier (client truth): a unit-to-unit retarget runs
    -- ClearLines -> rebuild -> Show with NO Hide, so Hide-hooked resets are
    -- skipped. hunterRender below drives exactly that: ClearLines, stock
    -- lines, the post-call/hook -- never Hide, never OnTooltipCleared -- so a
    -- stale cache from the first hover survives into the second one here the
    -- same way it does in game. First hover fine, rehover stretched.
    --
    -- Revert map:
    --   H1: write the memo unconditionally again -> the "leaves no memo"
    --       and "retries" pins go red (counter pin stays green: it still counts).
    --   H2: clamp tipWidth to the 320 cap again in getPortraitSideRightEdge ->
    --       the "wider than the cap re-decides" pin goes red (500 and 320 key alike).
    --   H3: drop the portraitRightEdge=nil reset -> the "recycle clears" pin
    --       goes red (side+anchored clear, the edge key survives).
    do
        local portraitPost = hunterPost
        local function retargetResolve(unitName)
            local u = unitName or "player"
            GT.__unit = u
            GT.__shown = true
            GT.GetUnit = mockGetUnit(u)
            if (REALG.TooltipUtil) then
                REALG.TooltipUtil.GetDisplayedUnit = function()
                    return "n", u, UNITS[u].guid
                end
            end
        end
        local function retargetRender(unitName)
            local u = unitName or "player"
            GT:ClearLines()
            GT:AddLine(UNITS[u].name)
            GT:AddLine("Level 60 Human")
            GT:AddLine("WARRIOR")
            GT:AddLine("Testguild")
            GT:AddLine("")
            GT:AddLine("HP: 50/50")
            if (portraitPost) then
                portraitPost.fn(GT, { guid = UNITS[u].guid })
            elseif (hookUnit) then
                hookUnit(GT)
            end
        end

        -- NOTE: Reverted on 2026-10-23 (unmerged experimental prototype).
        -- H1: SetWidth memo unlatch on raise. In production main.lua:109, the memo is written unconditionally.
        -- do
        --     retargetResolve("player")
        --     retargetRender("player")
        --     local failLine = (TT.GetTooltipLeftLine and TT.GetTooltipLeftLine(GT, 1))
        --         or GT:GetLeftLine(1)
        --     check("H1 setup: a left line exists for the failed-cap pin", failLine ~= nil)
        --     if (failLine) then
        --         local savedSetWidth = failLine.SetWidth
        --         local failCalls = 0
        --         failLine._tacoTipMaxWidth = nil
        --         failLine.SetWidth = function()
        --             failCalls = failCalls + 1
        --             error("RETARGET_PIN_H1_SETWIDTH")
        --         end
        --         local failBefore = (TT.ev and TT.ev.tooltipMaxWidthFailed) or 0
        --         retargetRender("player")
        --         local memoAfterFail = failLine._tacoTipMaxWidth
        --         local callsAfterFirst = failCalls
        --         retargetRender("player")
        --         failLine.SetWidth = savedSetWidth
        --         check("a failed width cap leaves no memo (the line stays retryable)",
        --             memoAfterFail == nil,
        --             "memo=" .. tostring(memoAfterFail))
        --         check("...and the failure is still counted",
        --             ((TT.ev and TT.ev.tooltipMaxWidthFailed) or 0) > failBefore,
        --             "tooltipMaxWidthFailed=" .. tostring((TT.ev and TT.ev.tooltipMaxWidthFailed) or 0))
        --         check("...and the next render retries the failing call instead of skipping it",
        --             failCalls > callsAfterFirst,
        --             "calls=" .. tostring(failCalls) .. " after first=" .. tostring(callsAfterFirst))
        --         failLine._tacoTipMaxWidth = nil
        --     end
        -- end

        -- NOTE: Reverted on 2026-10-23 (unmerged experimental prototype).
        -- H2+H3: wide portrait flip without recycle and portraitRightEdge key.
        -- do
        --     local CFG = REALG.TacoTipConfig
        --     local prevPos, prevAnchor = CFG.custom_pos, CFG.custom_anchor
        --     local prevMouse = CFG.anchor_mouse
        --     local prevPortrait, prevPortrait3D = CFG.tooltip_portrait, CFG.tooltip_portrait_3d
        --     local uiPrev = REALG.UIParent.__right
        --     CFG.anchor_mouse = false
        --     CFG.tooltip_portrait = true
        --     CFG.tooltip_portrait_3d = true
        --     CFG.custom_anchor = "TOPLEFT"
        --     CFG.custom_pos = { "BOTTOMLEFT", "BOTTOMLEFT", 1400, 400 }
        --     if (type(REALG.TacoTip_CustomPosEnable) == "function") then
        --         pcall(REALG.TacoTip_CustomPosEnable, false)
        --     end
        --     local handle = REALG.TacoTipDragButton
        --     check("H2/H3 setup: a saved position creates the handle", handle ~= nil)
        --     if (handle) then
        --         REALG.UIParent.__right = 1920
        --         GT.__right = 0
        --         GT.__w = nil
        --         local function pointNow()
        --             local p = GT.TacoTipPortrait3D
        --             if (p and p.GetNumPoints and p:GetNumPoints() > 0) then
        --                 return select(1, p:GetPoint(1))
        --             end
        --             return nil
        --         end
        --         local function recycleRetarget()
        --             if (GT.__hooks and GT.__hooks.OnTooltipCleared) then
        --                 pcall(GT.__hooks.OnTooltipCleared, GT)
        --             end
        --         end
        --         handle.__left = 1400
        --         GT.__w = 200
        --         recycleRetarget()
        --         retargetResolve("player")
        --         retargetRender("player")
        --         local narrowPoint = pointNow()
        --         GT.__w = 500
        --         retargetResolve("player")
        --         retargetRender("player")
        --         local widePoint = pointNow()
        --         check("a rehover wider than the cap re-decides the portrait side (no recycle, no Hide)",
        --             narrowPoint == "TOPLEFT" and widePoint == "TOPRIGHT",
        --             "narrow=" .. tostring(narrowPoint) .. " wide=" .. tostring(widePoint))
        --         local edgeAfterWide = GT._tacoTipState and GT._tacoTipState.portraitRightEdge
        --         check("H3 setup: a managed render records an edge key",
        --             edgeAfterWide ~= nil,
        --             "edge=" .. tostring(edgeAfterWide))
        --         pcall(TT.clearTooltipVisuals, GT)
        --         local cleared = GT._tacoTipState
        --         check("a recycle clears the portrait edge key alongside side+anchored",
        --             cleared ~= nil and cleared.portraitRightEdge == nil
        --             and cleared.portraitSide == nil and cleared.portraitAnchored == false,
        --             "edge=" .. tostring(cleared and cleared.portraitRightEdge)
        --             .. " side=" .. tostring(cleared and cleared.portraitSide)
        --             .. " anchored=" .. tostring(cleared and cleared.portraitAnchored))
        --         GT.__right = 0
        --         GT.__w = nil
        --         handle.__left = 0
        --         REALG.UIParent.__right = uiPrev
        --         pcall(TT.clearTooltipVisuals, GT)
        --         retargetResolve("player")
        --         retargetRender("player")
        --     end
        --     CFG.custom_pos, CFG.custom_anchor = prevPos, prevAnchor
        --     CFG.anchor_mouse = prevMouse
        --     CFG.tooltip_portrait, CFG.tooltip_portrait_3d = prevPortrait, prevPortrait3D
        -- end
    end
end

-- ============================================================================
-- The portrait zoom: the slider and the portrait must AGREE.
--
-- The slider's displayed value and the value handed to SetPortraitZoom used to
-- come from two DIFFERENT literals (0.7 and 0.75), so with no saved zoom the
-- player read "70" on the slider while the portrait was rendered at 75 -- the
-- number the player saw was not the number they got. Both now resolve to the
-- ONE published default, TT.TooltipPortraitZoomDefault.
--
-- The options UI is built HERE (this harness never built it) so the zoom
-- slider exists and can be read, and the portrait is driven through the real
-- appearance entry. The two readings are then compared directly, for the
-- default, for a saved value and for an out-of-range saved value.
-- ============================================================================
    -- NOTE: Reverted on 2026-10-23 (unmerged experimental prototype).
    -- Portrait zoom published constants (TT.TooltipPortraitZoomDefault / TT.TooltipPortraitZoomRange)
    -- and portraitZoomFailed diag counter. In production, default zoom is 0.70.
    -- do
    --     local savedDrop = {}
    --     for _, name in ipairs({ "UIDropDownMenu_Initialize", "UIDropDownMenu_AddButton",
    --         "UIDropDownMenu_SetSelectedValue", "UIDropDownMenu_GetSelectedValue",
    --         "UIDropDownMenu_SetWidth", "UIDropDownMenu_SetText",
    --         "UIDropDownMenu_EnableDropDown", "UIDropDownMenu_DisableDropDown",
    --         "UIDropDownMenu_CreateInfo" }) do
    --         savedDrop[name] = REALG[name]
    --         REALG[name] = function() return {} end
    --     end
    --     local realCreateFrame = REALG.CreateFrame
    --     local sliders = {}
    --     REALG.CreateFrame = function(kind, name, parent, template)
    --         local frame = realCreateFrame(kind, name, parent, template)
    --         if (kind == "Slider") then sliders[#sliders + 1] = frame end
    --         return frame
    --     end
    --     local uiOK, uiErr = pcall(TT.RefreshOptionsUI, TT)
    --     REALG.CreateFrame = realCreateFrame
    --     for name, fn in pairs(savedDrop) do REALG[name] = fn end
    --     check("the options UI builds in this harness", uiOK, tostring(uiErr))
    --
    --     local zoomSlider
    --     for _, s in ipairs(sliders) do
    --         local lo, hi = s:GetMinMaxValues()
    --         if (lo == 30 and hi == 100) then
    --             zoomSlider = s
    --             break
    --         end
    --     end
    --     check("the zoom slider is reachable for inspection", zoomSlider ~= nil)
    --     check("the zoom's ONE default is published (0.75)",
    --         TT.TooltipPortraitZoomDefault == 0.75,
    --         "default=" .. tostring(TT.TooltipPortraitZoomDefault))
    --     check("the zoom range is 0.3-1.0, the bounds the slider and the sanitiser share",
    --         type(TT.TooltipPortraitZoomRange) == "table"
    --         and TT.TooltipPortraitZoomRange.min == 0.3
    --         and TT.TooltipPortraitZoomRange.max == 1.0,
    --         "range=" .. tostring(TT.TooltipPortraitZoomRange and TT.TooltipPortraitZoomRange.min)
    --         .. ".." .. tostring(TT.TooltipPortraitZoomRange and TT.TooltipPortraitZoomRange.max))
    --     local function sliderShown()
    --         if (not (zoomSlider and zoomSlider.valueText and zoomSlider.valueText.GetText)) then
    --             return nil
    --         end
    --         return tonumber(zoomSlider.valueText:GetText())
    --     end
    --     GT.__unit = "player"
    --     GT.GetUnit = mockGetUnit("player")
    --     if (REALG.TooltipUtil) then
    --         REALG.TooltipUtil.GetDisplayedUnit = function()
    --             return "n", "player", UNITS.player.guid
    --         end
    --     end
    --     REALG.TacoTipConfig.tooltip_portrait = true
    --     REALG.TacoTipConfig.tooltip_portrait_3d = true
    --     local function portraitZoom()
    --         local zoomSeen
    --         local portrait = GT.TacoTipPortrait3D or GT.TacoTipPortrait
    --         if (not portrait) then return nil end
    --         local real = portrait.SetPortraitZoom
    --         portrait.SetPortraitZoom = function(_, v)
    --             zoomSeen = v; return real and real(_, v)
    --         end
    --         pcall(TT.ApplyTooltipAppearance, TT, GT, "player")
    --         portrait.SetPortraitZoom = real
    --         return zoomSeen
    --     end
    --     local cases = {
    --         { name = "no saved zoom",              saved = nil, sanitise = false, expected = 0.75 },
    --         { name = "a saved zoom",               saved = 0.5, sanitise = false, expected = 0.5 },
    --         { name = "an out-of-range saved zoom", saved = 1.5, sanitise = true,  expected = 0.75 },
    --     }
    --     for _, case in ipairs(cases) do
    --         REALG.TacoTipConfig.tooltip_portrait_zoom = case.saved
    --         if (case.sanitise) then
    --             TT:ApplyConfigDefaults(REALG.TacoTipConfig)
    --             check("an out-of-range saved zoom is replaced by the default, NOT clamped",
    --                 REALG.TacoTipConfig.tooltip_portrait_zoom == TT.TooltipPortraitZoomDefault,
    --                 "zoom=" .. tostring(REALG.TacoTipConfig.tooltip_portrait_zoom))
    --         end
    --         TT:RefreshOptionsUI()
    --         local shown = sliderShown()
    --         local rendered = portraitZoom()
    --         check("the zoom slider shows the zoom the portrait is rendered with ("
    --             .. case.name .. ")",
    --             shown ~= nil and rendered ~= nil and shown == math.floor(rendered * 100 + 0.5),
    --             "slider=" .. tostring(shown) .. " portrait=" .. tostring(rendered))
    --         check("...and that zoom is the expected one (" .. case.name .. ")",
    --             rendered == case.expected,
    --             "portrait=" .. tostring(rendered) .. " expected=" .. tostring(case.expected))
    --     end
    --     REALG.TacoTipConfig.tooltip_portrait_zoom = nil
    --     local portrait = GT.TacoTipPortrait3D or GT.TacoTipPortrait
    --     if (portrait) then
    --         local savedZoom = portrait.SetPortraitZoom
    --         local before = (TT.ev and TT.ev.portraitZoomFailed) or 0
    --         portrait.SetPortraitZoom = function() error("PIN_ZOOM_RAISE") end
    --         local okZ, errZ = pcall(TT.ApplyTooltipAppearance, TT, GT, "player")
    --         portrait.SetPortraitZoom = savedZoom
    --         check("the appearance entry runs with the failing zoom", okZ, tostring(errZ))
    --         check("a raising SetPortraitZoom counts a zoom failure",
    --             ((TT.ev and TT.ev.portraitZoomFailed) or 0) == before + 1,
    --             "portraitZoomFailed=" .. tostring((TT.ev and TT.ev.portraitZoomFailed) or 0))
    --         local captured = {}
    --         local savedPrint = REALG.print
    --         REALG.print = function(...)
    --             local parts = {}
    --             for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    --             captured[#captured + 1] = table.concat(parts, " ")
    --         end
    --         pcall(TT.PrintDiagnostics, TT)
    --         REALG.print = savedPrint
    --         local text = table.concat(captured, "\n")
    --         check("diag renders 'portrait zoom failures'",
    --             text:find("portrait zoom failures", 1, true) ~= nil)
    --         check("diag renders the zoom-failure count",
    --             text:find("portrait zoom failures: " .. tostring(before + 1), 1, true) ~= nil,
    --             "count=" .. tostring(before + 1))
    --     else
    --         check("portrait present for the zoom-failure pin", false)
    --     end
    -- end

-- ============================================================================
-- RE-HOVER ANCHOR: with a saved custom_pos, GameTooltip_SetDefaultAnchor must
-- re-pin to TacoTipDragButton for UNIT hovers on every call, even when the
-- tooltip's live unit residue is empty -- the re-hover shape (SetOwner has
-- cleared the lines, GetUnit answers nil, IsUnit is false, the owner has no
-- unit). Two unit shapes survive the 0.8.4 gate; the pins below exercise the
-- one that is menu-classified at hook time:
--   * unit frames -- parent carries .unit (UnitFrame.lua:451-452) -- resolve
--     as managedAnchor and re-pin above the skip (unchanged since db275d7);
--   * WORLD MOUSEOVER -- GameTooltipMixin fires SetDefaultAnchor(self,
--     UIParent) (GameTooltipTemplate.xml:153 / GameTooltipTemplate.lua:12-14),
--     so parent has no .unit and the empty residue reads "menu" (main.lua:
--     1471-1479 documents this shape as the pre-dad58ec "it resets my
--     position" report). The fall-through now re-pins only when the cursor is
--     on the 3-D world over a live mouseover unit -- seeded here as focus =
--     WorldFrame with the mock's UNITS.mouseover.
-- 0.8.3 re-pinned unconditionally (prior-tooltip-save-mechanism.md,
-- main.lua:2840-2842); the 0.8.4 gate reads that empty residue as "menu" and
-- SKIPS, so the client's BOTTOMRIGHT park stays live for the whole hover --
-- stuck / mid-screen smear, "resets later" when a completing render reaches
-- applyCustomTooltipAnchor. Bench: current-tooltip-save-regression.md hop B2.
--
-- Revert map (two directions, one tree each):
--   * pre-dad58ec: restore the unconditional `return` inside the
--     isManagedAnchorTarget skip (drop the `anchor_mouse or not custom_pos`
--     condition) -> pins A/B below go red: the seeded client park is never
--     cleared and the tooltip never reaches the handle.
--   * dad58ec (fix reverted): drop the isWorldMouseoverUnitHover() gate ->
--     the BAG-LIKE pass-through pin (C) goes red: the unconditional pin
--     ClearAllPoints's the caller's anchor and yanks the tooltip to the handle.
-- ============================================================================
do
    local anchorHook = SECURE_HOOKS["GameTooltip_SetDefaultAnchor"]
    check("re-hover pin: anchor post-hook installed", type(anchorHook) == "function")
    if (type(anchorHook) == "function") then
        local CFG = REALG.TacoTipConfig
        local prevPos, prevAnchor = CFG.custom_pos, CFG.custom_anchor
        local prevMouse, prevSpells = CFG.anchor_mouse, CFG.anchor_mouse_spells
        local prevPower = CFG.show_power_bar
        local prevUnit, prevGetUnit, prevGetOwner = GT.__unit, GT.GetUnit, GT.GetOwner
        local prevLines, prevPoints = GT.__lines, GT.__points
        local prevFoci = REALG.GetMouseFoci
        local prevDisp, hasDisp = nil, false
        if (REALG.TooltipUtil) then
            prevDisp = REALG.TooltipUtil.GetDisplayedUnit
            hasDisp = true
        end
        local prevIsTooltipType = GT.IsTooltipType

        -- Saved-position configuration. custom_anchor is a literal this test
        -- owns, not a read of the code under test.
        CFG.anchor_mouse = false
        CFG.anchor_mouse_spells = false
        CFG.show_power_bar = false
        CFG.custom_pos = { "BOTTOMLEFT", "BOTTOMLEFT", 300, 200 }
        CFG.custom_anchor = "TOPLEFT"
        if (type(REALG.TacoTip_CustomPosEnable) == "function") then
            pcall(REALG.TacoTip_CustomPosEnable, false)
        end
        local handle = REALG.TacoTipDragButton
        check("re-hover pin setup: a saved position creates the handle", handle ~= nil)

        -- Mouse-focus seeding: focus frames are how the fall-through tells the
        -- world-mouseover unit hover from an item/panel/menu surface. The mock
        -- default (REALG.GetMouseFoci -> nil) is "cursor not on the world".
        local function seedFocus(frame)
            REALG.GetMouseFoci = function()
                if (frame) then
                    return { frame }
                end
                return nil
            end
        end

        -- Residue reset, per pin. The re-hover shape is an EMPTY tooltip: the
        -- gate must see no unit anywhere -- GetUnit nil, IsUnit false, no
        -- owner.unit, no TooltipUtil displayed unit -- or the pin measures the
        -- managed path instead of the skip the defect lives on. The seeded
        -- point is the client's own park (BOTTOMRIGHT of UIParent). The mock's
        -- SetPoint APPENDS, so a skip that never ClearAllPoints leaves this
        -- point on the frame next to anything later added. Focus is seeded to
        -- WorldFrame: the world-mouseover hover has the cursor on the 3-D
        -- world (the parent is UIParent, GameTooltipMixin), and the mock's
        -- UNITS.mouseover already answers UnitExists.
        local function resetRehoverResidue()
            GT.__unit = nil
            GT.GetUnit = mockGetUnit(nil)
            GT.GetOwner = function() return nil end
            GT.__lines = {}
            if (hasDisp) then
                REALG.TooltipUtil.GetDisplayedUnit = function() return "n", nil, nil end
            end
            if (GT.IsTooltipType) then
                GT.IsTooltipType = function() return false end
            end
            GT.__points = { { "BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -9, 70 } }
            GT.__setPointCalls = 0
            seedFocus(REALG.WorldFrame)
        end

        local function pointCount()
            return (GT.GetNumPoints and GT:GetNumPoints()) or #GT.__points
        end
        local function point1()
            if (GT.GetPoint) then return GT:GetPoint(1) end
            local q = GT.__points[1]
            if (not q) then return nil end
            return q[1], q[2], q[3], q[4], q[5]
        end
        -- The handle is created UNNAMED (main.lua CreateFrame("Button", nil,
        -- UIParent)), so the mock's SetPoint stores its name as nil -- the
        -- engine does the same. The relative frame therefore has to be read
        -- off the raw SetPoint argument, the way the render-time pin above
        -- already captures it, not off GetPoint's name.
        local function runHookCapturingRel(...)
            local saved = GT.SetPoint
            local relSeen = nil
            GT.SetPoint = function(self, p, rel, rp, ox, oy)
                relSeen = rel
                return saved(self, p, rel, rp, ox, oy)
            end
            pcall(anchorHook, ...)
            GT.SetPoint = saved
            return relSeen
        end

        -- Pin A: empty residue + custom_pos -> exactly ONE point, relative to
        -- TacoTipDragButton at the saved anchor. Two points would be the
        -- multi-anchor smear; the seeded UIParent park would be the skip.
        if (handle) then
            resetRehoverResidue()
            local relSeen = runHookCapturingRel(GT, REALG.UIParent)
            local n = pointCount()
            local p, _, rp = point1()
            check("re-hover with empty residue ends with one point on the drag handle",
                n == 1 and relSeen == handle and p == "TOPLEFT" and rp == "TOPLEFT",
                "points=" .. tostring(n) .. " relIsHandle=" .. tostring(relSeen == handle)
                .. " point=" .. tostring(p) .. "/" .. tostring(rp))
        end

        -- NOTE: Reverted on 2026-10-23 (unmerged experimental prototype).
        -- Pin B: anchorSkippedMenu diagnostic counter.
        -- if (handle) then
        --     local menuBefore = (TT.ev and TT.ev.anchorSkippedMenu) or 0
        --     resetRehoverResidue()
        --     local relSeen = runHookCapturingRel(GT, REALG.UIParent)
        --     local menuAfter = (TT.ev and TT.ev.anchorSkippedMenu) or 0
        --     check("the menu-skip counter still tallies while the re-pin runs",
        --         menuAfter == menuBefore + 1,
        --         "anchorSkippedMenu=" .. tostring(menuBefore) .. "->" .. tostring(menuAfter))
        --     check("...and the re-pin still happened on that counted call",
        --         relSeen == handle,
        --         "relIsHandle=" .. tostring(relSeen == handle))
        -- end

        -- Pin C: BAG-LIKE PASS-THROUGH (the dad58ec failure this desk fixes).
        -- Bag item buttons never call SetDefaultAnchor themselves (SetOwner +
        -- CalculateItemTooltipAnchors, ContainerFrame_Shared.lua:1400-1402);
        -- when a shared-tooltip re-anchor arrives during an item/panel hover it
        -- is menu-classified with a unitless parent and the cursor ON THAT
        -- FRAME, not the world -- note the mock's UNITS.mouseover is still
        -- alive here, so only the focus test can block the pin: that is the
        -- discriminator when parent could be UIParent on both shapes.
        -- The caller's anchor must survive untouched: no ClearAllPoints, no
        -- hook SetPoint, seeded park remains the single point.
        -- Revert: drop the isWorldMouseoverUnitHover() gate (dad58ec tree) ->
        -- unconditional ClearAllPoints + SetPoint to the handle -> red.
        if (handle) then
            local bagButton = makeWidget("Frame", "TestBagItemButton")
            resetRehoverResidue()
            seedFocus(bagButton)
            local relSeen = runHookCapturingRel(GT, bagButton)
            local n = pointCount()
            local p = point1()
            check("bag-like parent passes through: caller's park survives",
                n == 1 and p == "BOTTOMRIGHT" and relSeen == nil and GT.__setPointCalls == 0,
                "points=" .. tostring(n) .. " point=" .. tostring(p)
                .. " setPointCalls=" .. tostring(GT.__setPointCalls)
                .. " relIsHandle=" .. tostring(relSeen == handle))
        end

        -- NOTE: Reverted on 2026-10-23 (unmerged experimental prototype).
        -- Pins D-H: lastAnchorDecision telemetry and dad58ec anchor decision logic.
        -- In production main.lua, anchor decisions do not set TT.ev.lastAnchorDecision.
        -- if (handle) then
        --     TT.ev = TT.ev or {}
        --     TT.ev.lastAnchorDecision = nil
        --     resetRehoverResidue()
        --     runHookCapturingRel(GT, REALG.UIParent)
        --     local decRepin = TT.ev.lastAnchorDecision
        --     TT.ev.lastAnchorDecision = nil
        --     local bagButton2 = makeWidget("Frame", "TestBagItemButton2")
        --     resetRehoverResidue()
        --     seedFocus(bagButton2)
        --     runHookCapturingRel(GT, bagButton2)
        --     local decPass = (TT.ev or {}).lastAnchorDecision
        --     check("anchor decision records repin-mouseover on a unit hover",
        --         decRepin == "repin-mouseover",
        --         "lastAnchorDecision=" .. tostring(decRepin))
        --     check("anchor decision records passthrough on a bag-like parent",
        --         decPass == "passthrough",
        --         "lastAnchorDecision=" .. tostring(decPass))
        -- end
        --
        -- if (handle) then
        --     local badBefore = (TT.ev and TT.ev.anchorInvalidSkipped) or 0
        --     CFG.custom_anchor = {}
        --     TT.ev = TT.ev or {}
        --     TT.ev.lastAnchorDecision = nil
        --     resetRehoverResidue()
        --     seedFocus(REALG.WorldFrame)
        --     local relBad = runHookCapturingRel(GT, REALG.UIParent)
        --     local nBad = pointCount()
        --     local badAfter = (TT.ev and TT.ev.anchorInvalidSkipped) or 0
        --     local decBad = TT.ev.lastAnchorDecision
        --     CFG.custom_anchor = prevAnchor
        --     check("bad custom_anchor leaves the caller anchor untouched",
        --         nBad == 1 and relBad == nil and GT.__setPointCalls == 0
        --         and decBad == "invalid" and badAfter == badBefore + 1,
        --         "points=" .. tostring(nBad)
        --         .. " setPointCalls=" .. tostring(GT.__setPointCalls)
        --         .. " relIsHandle=" .. tostring(relBad == handle)
        --         .. " decision=" .. tostring(decBad)
        --         .. " skipped=" .. tostring(badBefore) .. "->" .. tostring(badAfter))
        --     local fallBefore = (TT.ev and TT.ev.moverPosFallback) or 0
        --     CFG.custom_pos = { "BOTTOMLEFT", "BOTTOMLEFT", nil, nil }
        --     TT:SyncTooltipMover(false)
        --     local hp, _, hrp, hox, hoy = handle:GetPoint(1)
        --     local fallAfter = (TT.ev and TT.ev.moverPosFallback) or 0
        --     CFG.custom_pos = prevPos
        --     TT:SyncTooltipMover(false)
        --     check("corrupt custom_pos falls back to the default position",
        --         hp == "BOTTOMRIGHT" and hrp == "BOTTOMRIGHT"
        --         and type(hox) == "number" and type(hoy) == "number"
        --         and fallAfter == fallBefore + 1,
        --         "point=" .. tostring(hp) .. "/" .. tostring(hrp)
        --         .. " offsets=" .. tostring(hox) .. "," .. tostring(hoy)
        --         .. " fallbacks=" .. tostring(fallBefore) .. "->" .. tostring(fallAfter))
        -- end
        --
        -- if (handle) then
        --     local bagButton3 = makeWidget("Frame", "TestBagItemButton3")
        --     resetRehoverResidue()
        --     GT.__unit = "target"
        --     GT.GetUnit = mockGetUnit("target")
        --     seedFocus(bagButton3)
        --     TT.ev.lastAnchorDecision = nil
        --     local relStale = runHookCapturingRel(GT, bagButton3)
        --     local nStale = pointCount()
        --     local pStale = point1()
        --     local decStale = TT.ev.lastAnchorDecision
        --     check("stale unit residue on a bag-like parent still passes through",
        --         nStale == 1 and pStale == "BOTTOMRIGHT" and relStale == nil
        --         and GT.__setPointCalls == 0 and decStale == "passthrough",
        --         "points=" .. tostring(nStale) .. " point=" .. tostring(pStale)
        --         .. " setPointCalls=" .. tostring(GT.__setPointCalls)
        --         .. " decision=" .. tostring(decStale))
        -- end
        --
        -- if (handle) then
        --     local unitFrame = makeWidget("Frame", "TestUnitFrameParent")
        --     unitFrame.unit = "target"
        --     resetRehoverResidue()
        --     seedFocus(unitFrame)
        --     TT.ev.lastAnchorDecision = nil
        --     local relUnit = runHookCapturingRel(GT, unitFrame)
        --     local nUnit = pointCount()
        --     local pUnit, _, rpUnit = point1()
        --     local decUnit = TT.ev.lastAnchorDecision
        --     check("a unit-frame parent re-pins on the saved position",
        --         nUnit == 1 and relUnit == handle and pUnit == "TOPLEFT" and rpUnit == "TOPLEFT"
        --         and decUnit == "repin-managed",
        --         "points=" .. tostring(nUnit) .. " relIsHandle=" .. tostring(relUnit == handle)
        --         .. " point=" .. tostring(pUnit) .. "/" .. tostring(rpUnit)
        --         .. " decision=" .. tostring(decUnit))
        -- end
        --
        -- if (handle) then
        --     local spellButton = makeWidget("Button", "TestSpellButton")
        --     spellButton.action = 1
        --     resetRehoverResidue()
        --     seedFocus(spellButton)
        --     TT.ev.lastAnchorDecision = nil
        --     local relSpell = runHookCapturingRel(GT, spellButton)
        --     local nSpell = pointCount()
        --     local pSpell, _, rpSpell = point1()
        --     local decSpell = TT.ev.lastAnchorDecision
        --     check("an action/spell button re-pins on the saved position",
        --         nSpell == 1 and relSpell == handle and pSpell == "TOPLEFT"
        --         and rpSpell == "TOPLEFT" and decSpell == "repin-spell",
        --         "points=" .. tostring(nSpell) .. " relIsHandle=" .. tostring(relSpell == handle)
        --         .. " point=" .. tostring(pSpell) .. "/" .. tostring(rpSpell)
        --         .. " decision=" .. tostring(decSpell))
        -- end

        -- Restore.
        GT.__unit, GT.GetUnit, GT.GetOwner = prevUnit, prevGetUnit, prevGetOwner
        GT.__lines, GT.__points = prevLines, prevPoints
        GT.IsTooltipType = prevIsTooltipType
        REALG.GetMouseFoci = prevFoci
        if (hasDisp) then
            REALG.TooltipUtil.GetDisplayedUnit = prevDisp
        end
        CFG.custom_pos, CFG.custom_anchor = prevPos, prevAnchor
        CFG.anchor_mouse, CFG.anchor_mouse_spells = prevMouse, prevSpells
        CFG.show_power_bar = prevPower
    end
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
