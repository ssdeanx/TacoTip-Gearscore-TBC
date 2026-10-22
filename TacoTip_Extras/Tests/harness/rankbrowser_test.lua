-- TacoTip_Extras focused harness: the server leaderboard browser.
--
--   lua5.1 rankbrowser_test.lua
--
-- WHY A SEPARATE HARNESS, when load_test.lua already loads this file:
--
--   load_test.lua asserts that RankBrowser.CreateUI() CONSTRUCTS without
--   raising. That is the class of assertion that once passed 30/30 invocations
--   while the add-on added no rows at all -- "did not raise" proves nothing
--   about behaviour. It also cannot reach any rendering path: its mock answers
--   IsShown() == false unconditionally, so RankBrowser.UpdateUI returns on its
--   first line and every render is dead code as far as that harness is
--   concerned.
--
--   So this harness supplies its OWN environment -- deliberately different
--   from load_test's -- where Show/Hide drive real IsShown() state, and then
--   DRIVES the surface and asserts what came out: which ranks, which names,
--   which colours, which scroll offset.
--
-- It pins the behaviours that were the point of the rewrite, each of which can
-- silently regress:
--     - the window opens ON THE PLAYER, not on row 1;
--     - the scrollbar thumb and frame.offset move TOGETHER (FauxScrollFrame_
--       SetOffset alone leaves them desynced, and FauxScrollFrame_Update reads
--       the thumb, not frame.offset);
--     - closing and reopening re-centres rather than keeping a stale offset;
--     - "Top" returns to row 1 and "My Rank" re-centres, through the real
--       button OnClick handlers rather than the API directly;
--     - faction, class and search filters change the rendered set;
--     - rank / GearScore / iLvl / name colours are actually applied;
--     - the player's own row is flagged, highlighted and badged.

local scriptPath = ((arg and arg[0]) or "Tests/harness/rankbrowser_test.lua"):gsub("\\", "/")
local harnessDir = scriptPath:match("^(.*)/[^/]*$") or "."
local ROOT = dofile(harnessDir .. "/root.lua")

local PASS, FAIL = 0, 0
local failures = {}

local function out(line)
    io.write(line, "\n")
end

-- Swapped-argument guard (Batch 7, item 3).
--
-- The MAIN harnesses call check(name, cond, detail); THIS harness calls
-- check(condition, label, detail). The call SHAPE is identical, so a MAIN-style
-- call copied in here is read the other way round: the string name lands in
-- the CONDITION slot, where it is truthy, so the call passes SILENTLY. The
-- two shapes are unambiguous -- a condition is never a string in this harness
-- and a label is never a boolean -- so "first argument is a string AND second
-- argument is a boolean" can only mean the arguments are the wrong way round.
local function isSwappedCheckArgs(first, second)
    return (type(first) == "string" and type(second) == "boolean")
end

local function check(condition, label, detail)
    if isSwappedCheckArgs(condition, label) then
        -- Loud, and NOT a pass. The failure is recorded so the suite goes
        -- red: a silently-passing swapped call is the whole hazard this
        -- guard exists for. The PASS counter is never advanced.
        FAIL = FAIL + 1
        failures[#failures + 1] = ("SWAPPED CHECK ARGUMENTS: check(\"%s\", %s)")
            :format(condition, tostring(label))
        out("  FAIL  SWAPPED CHECK ARGUMENTS -- this harness calls check(condition, label, detail), NOT check(name, cond, detail)")
        out("          got check(\"" .. tostring(condition) .. "\", " .. tostring(label)
            .. "): the string sits in the CONDITION slot, where it would read as a silent pass")
        return false
    end
    if condition then
        PASS = PASS + 1
        out("  ok    " .. label)
    else
        FAIL = FAIL + 1
        failures[#failures + 1] = label
        out("  FAIL  " .. label .. (detail and ("  [" .. tostring(detail) .. "]") or ""))
    end
    return condition
end

local function near(a, b)
    return math.abs((tonumber(a) or 0) - (tonumber(b) or 0)) < 1e-6
end

-- ---------------------------------------------------------------------------
-- The mock-fidelity contract (proctor HI-12).
--
-- The shared table in Tests/harness/mock_contract.lua records, per API, how
-- many values the CLIENT publishes and how many the mock is expected to
-- publish, with the mirror citation that established the client's number.
-- The proctor audit recorded FauxScrollFrame_Update as returning NOTHING and
-- the mock as "returning a value the real function never returns"; the
-- mirror says the opposite on both counts --
-- Interface/AddOns/Blizzard_SharedXML/SecureScrollTemplates.lua:224 ends
-- the function with `return showScrollBar;` on ALL five branches -- so the
-- mock was already faithful and the CONTRACT is what was corrected. This
-- assertion is what stops the question being reopened on the next audit.
--
-- This harness's check() takes (condition, label, detail); the shared helper
-- takes the MAIN-suite order, so adapt once, here.
--
-- The contract table lives in the MAIN add-on's harness tree, one level up
-- from this add-on's root. It is loaded LOUDLY: if the file is missing the
-- dofile raises and the suite stops, rather than the assertion quietly
-- disappearing -- the same rule root.lua follows for the add-on root.
-- ---------------------------------------------------------------------------
local MOCKC = dofile(ROOT .. "/../Tests/harness/mock_contract.lua")
MOCKC.setFamily("retail")
local function contractCheck(name, cond, detail)
    return check(cond, name, detail)
end

-- Read a widget's text colour.
--
-- `colorOf(fs:GetTextColor())` would truncate the triple to its first value,
-- because a multi-value call in a final argument position keeps one result.
-- Taking the widget and indexing it inside the helper avoids that trap, which
-- is the same `select`-truncation family as the project's pcall-arity notes.
local function colorOf(widget)
    local r, g, b = widget:GetTextColor()
    return tonumber(r) or 0, tonumber(g) or 0, tonumber(b) or 0
end

-- ---------------------------------------------------------------------------
-- Minimal environment
-- ---------------------------------------------------------------------------

-- Templates that carry the BACKDROP API, and the API itself.
--
-- Only a template that mixes in BackdropTemplateMixin has SetBackdrop /
-- GetBackdrop / SetBackdropColor. Verified in the client source on ALL FIVE
-- branches:
--   origin/classic_era          Interface/AddOns/Blizzard_SharedXML/Backdrop.xml:5
--   origin/classic_anniversary  Interface/AddOns/Blizzard_SharedXML/Backdrop.xml:5
--   origin/classic_titan        Interface/AddOns/Blizzard_SharedXML/Backdrop.xml:5
--   origin/forever              Interface/AddOns/Blizzard_SharedXML/Backdrop.xml:5
--   origin/live                 Interface/AddOns/Blizzard_SharedXML/Backdrop.xml:5
--       <Frame name="BackdropTemplate" mixin="BackdropTemplateMixin" virtual="true">
--   and the mixin itself, on every one of those branches:
--   Interface/AddOns/Blizzard_SharedXML/Backdrop.lua:336 / :354 / :406
--       SetBackdrop / GetBackdrop / SetBackdropColor
--
-- A PLAIN frame has NONE of them. The mock used to hand the whole set to
-- every frame, so a plain frame asking for a backdrop LOOKED like it got one.
-- That is exactly how the GEAR PANEL shipped TRANSPARENT: its
-- `if f.SetBackdrop then` guard was skipped in the real client, and the
-- harness could not see it because the mock always said yes.
--
-- ButtonFrameTemplate is NOT backdrop-capable either. It inherits
-- PortraitFrameTemplate -> PortraitFrameTemplateNoCloseButton ->
-- PortraitFrameBaseTemplate, whose mixins are PortraitFrameMixin /
-- PortraitFrameTemplateMixin (SharedUIPanelTemplates.xml:387, :440, :674) --
-- it paints its own background TEXTURE instead. That is why the browser frame
-- looks right without the backdrop API, and why modelling the absence does
-- not make the browser transparent.
local BACKDROP_TEMPLATES = { BackdropTemplate = true }
local BACKDROP_METHODS = {
    SetBackdrop = true,
    GetBackdrop = true,
    SetBackdropColor = true,
}

local function newRegion(kind, name, parent, template)
    local region = {
        __kind = kind,
        __name = name,
        __parent = parent,
        __template = template,
        -- A frame the client creates is VISIBLE. The mock used to create every
        -- frame HIDDEN, and the client does not: Blizzard's own panels carry
        -- `hidden="true"` on the FRAME, never on the template (origin/classic_era
        --   Interface/AddOns/Blizzard_AddOnList/AddonList.xml:120
        --     <Frame name="AddonList" ... inherits="ButtonFrameTemplate"
        --             mixin="AddonListMixin" hidden="true">
        --   Interface/AddOns/Blizzard_UIPanels_Game/Blizzard_GameMenu.xml
        --     (GameMenuFrame, likewise hidden="true" on the frame)), and
        -- Blizzard's code creates frames and then HIDES them explicitly
        -- (origin/classic_era
        --   Interface/AddOns/Blizzard_Calendar/Classic/Blizzard_Calendar.lua
        --     eventButton = CreateFrame("Button", ...);
        --     eventButton:Hide();).
        --
        -- The disagreement mattered: RankBrowser.Toggle() branches on
        -- f:IsShown(), so a mock that started hidden took the SHOW branch on
        -- the first toggle while a real frame -- visible from creation -- took
        -- the HIDE branch. A "the first toggle does nothing" bug could not be
        -- caught with the mock disagreeing with the client.
        __shown = true,
        __text = "",
        __textColor = { r = 1, g = 1, b = 1, a = 1 },
        __alpha = 1,
        __colorTexture = nil,
        __children = {},
        __scripts = {},
    }
    if type(parent) == "table" and parent.__children then
        parent.__children[#parent.__children + 1] = region
    end

    -- EVERY method takes `self` first, exactly like the real API.
    --
    -- The obvious mistake here is to write `R.SetText = function(t) ... end`.
    -- Colon calls pass the receiver, so `fs:SetText("#1")` binds `t = fs` and
    -- the fontstring TABLE gets stored as the text -- which then fails deep
    -- inside a comparison with "attempt to compare number with table", a long
    -- way from the missing `self`. load_test.lua's mock takes `f` first for
    -- this reason; so does every method below.
    local R = {}
    function R.GetName() return region.__name end
    function R.GetObjectType() return kind end
    function R.GetParent() return region.__parent end
    function R.SetParent(_, p)
        -- Reparenting moves the frame, mirroring the client: adoptGearParent
        -- depends on the panel leaving its old parent's child list.
        local old = region.__parent
        if type(old) == "table" and type(old.__children) == "table" then
            for i, child in ipairs(old.__children) do
                if child == region then
                    table.remove(old.__children, i)
                    break
                end
            end
        end
        region.__parent = p
        if type(p) == "table" then
            p.__children = p.__children or {}
            p.__children[#p.__children + 1] = region
        end
    end
    function R.GetChildren() return region.__children end
    function R.GetNumChildren() return #region.__children end

    function R.SetScript(_, script, fn) region.__scripts[script] = fn end
    function R.GetScript(_, script) return region.__scripts[script] end
    function R.HasScript(_, script) return region.__scripts[script] ~= nil end
    function R.HookScript(_, script, fn)
        if region.__scripts[script] == nil then
            error("HookScript on undeclared script: " .. tostring(script), 2)
        end
        local prev = region.__scripts[script]
        region.__scripts[script] = function(...) prev(...) fn(...) end
    end
    -- Fire a stored script. This is a HARNESS helper, not a client method, so
    -- it is called with DOT syntax (`region.Fire("OnClick")`) and therefore
    -- must NOT declare a leading self: doing so silently puts the script name
    -- in the self slot and leaves `script` nil, so the click does nothing at
    -- all -- a green suite that never clicked anything.
    function R.Fire(script, ...)
        local fn = region.__scripts[script]
        if fn then return fn(region, ...) end
        return nil
    end

    -- Real shown-state, unlike load_test's always-false mock.
    function R.Show() region.__shown = true end
    function R.Hide() region.__shown = false end
    function R.SetShown(_, yes) region.__shown = yes and true or false end
    function R.IsShown() return region.__shown end
    function R.IsVisible() return region.__shown end

    function R.GetText() return region.__text end
    function R.SetText(_, t) region.__text = t end
    function R.SetFormattedText(_, ...) region.__text = table.concat({ ... }, "") end
    function R.SetTextColor(_, r, g, b, a) region.__textColor = { r = r, g = g, b = b, a = a or 1 } end
    function R.GetTextColor() return region.__textColor.r, region.__textColor.g, region.__textColor.b end

    function R.SetFontObject() end
    function R.GetFontObject() return nil end
    function R.SetFont() end
    function R.SetJustifyH() end
    function R.SetJustifyV() end
    function R.SetNonSpaceWrap() end
    function R.SetWordWrap() end
    function R.SetShadowColor() end
    function R.SetShadowOffset() end
    function R.GetStringWidth() return #tostring(region.__text) * 6 end
    function R.GetStringHeight() return 12 end

    function R.SetAllPoints() end
    function R.ClearAllPoints() region.__point = nil end
    -- The anchor is RECORDED. The panel's vertical layout is a stack of
    -- bands, and "the sort readout has a band of its own and cannot land on
    -- the column headers" is a statement about geometry -- it cannot be
    -- checked against a SetPoint that throws the geometry away.
    function R.SetPoint(_, point, relativeTo, relativePoint, x, y)
        region.__point = {
            point = point,
            relativeTo = relativeTo,
            relativePoint = relativePoint,
            x = x or 0,
            y = y or 0,
        }
    end
    function R.GetPoint()
        local p = region.__point
        if not p then return "TOPLEFT", "TOPLEFT", 0, 0 end
        return p.point, p.relativeTo, p.relativePoint, p.x, p.y
    end
    function R.GetNumPoints() return 0 end
    function R.SetSize(_, w, h) region.__width, region.__height = w, h end
    function R.SetWidth(_, w) region.__width = w end
    function R.SetHeight(_, h) region.__height = h end
    function R.GetWidth() return region.__width or 0 end
    -- A FontString with no explicit height is as tall as one line of text.
    -- Without it every text band would measure zero tall and the "no two
    -- bands share vertical space" pin would be measuring nothing.
    function R.GetHeight()
        if region.__height then return region.__height end
        if region.__kind == "FontString" then return 12 end
        return 0
    end

    function R.SetAlpha(_, a) region.__alpha = a end
    function R.GetAlpha() return region.__alpha end
    function R.SetColorTexture(_, r, g, b, a) region.__colorTexture = { r = r, g = g, b = b, a = a } end
    function R.SetVertexColor(_, r, g, b, a) region.__colorTexture = { r = r, g = g, b = b, a = a } end
    function R.SetTexture(_, t) region.__texture = t end
    function R.GetTexture() return region.__texture end
    function R.SetTexCoord() end
    function R.GetTexCoord() return 0, 0, 1, 1 end
    function R.SetDesaturated() end
    function R.SetBlendMode() end

    function R.SetScale() end
    function R.GetScale() return 1 end
    function R.SetFrameStrata(_, s) region.__strata = s end
    function R.GetFrameStrata() return region.__strata or "MEDIUM" end
    function R.SetFrameLevel(_, l) region.__level = l end
    function R.GetFrameLevel() return region.__level or 1 end
    function R.SetDrawLayer() end
    function R.GetDrawLayer() return "BACKGROUND" end
    function R.SetClampedToScreen() end
    function R.SetMovable() end
    function R.IsMovable() return false end
    function R.SetToplevel(_, t) region.__toplevel = t end
    function R.SetUserPlaced() end
    function R.IsUserPlaced() return false end
    function R.Raise() end
    function R.StartMoving() end
    function R.StopMovingOrSizing() end
    function R.SetID() end
    function R.GetID() return nil end
    function R.SetHitRectInsets() end
    function R.SetFocus() end
    function R.ClearFocus() end
    function R.SetAutoFocus() end
    function R.SetMaxLetters() end
    function R.SetPropagateMouseInput() end

    function R.EnableMouse() end
    function R.EnableMouseWheel() end
    function R.EnableMouseMove() end
    function R.IsMouseOver() return false end
    function R.Enable() end
    function R.Disable() end
    function R.IsEnabled() return true end
    function R.SetEnabled() end
    function R.RegisterForDrag() end
    function R.RegisterForClicks() end
    function R.RegisterEvent() end
    function R.UnregisterEvent() end
    function R.IsEventRegistered() return false end

    function R.SetNormalTexture() end
    function R.SetHighlightTexture(_, tex, mode)
        region.__highlightTexture = tex
        region.__highlightMode = mode
    end
    function R.SetAtlas(_, atlas) region.__atlas = atlas end
    function R.SetPushedTexture() end
    function R.SetBackdrop(_, bd) region.__backdrop = bd end
    function R.GetBackdrop() return region.__backdrop end
    function R.SetBackdropColor(_, r, g, b, a)
        region.__backdropColor = { r = r, g = g, b = b, a = a }
    end

    function R.CreateTexture(_, tname, layer) return newRegion("Texture", tname, region, layer) end
    function R.CreateFontString(_, fname, layer, ftemplate)
        return newRegion("FontString", fname, region, ftemplate or layer)
    end

    -- StatusBar primitives: the scan progress rails on the browser and on the
    -- Options panel are real StatusBars, so a gap here crashes CreateUI before
    -- any behaviour is checked.
    function R.SetMinMaxValues(_, low, high) region.__min, region.__max = low, high end
    function R.GetMinMaxValues() return region.__min or 0, region.__max or 1 end
    function R.SetValue(_, value) region.__value = value end
    function R.GetValue() return region.__value or 0 end
    function R.SetStatusBarTexture() end
    function R.GetStatusBarTexture() return nil end
    function R.SetStatusBarColor(_, r, g, b) region.__statusColor = { r = r, g = g, b = b } end
    function R.SetOrientation() end
    function R.SetReverseFill() end
    function R.SetStatusBarColor(_, r, g, b) region.__statusColor = { r = r, g = g, b = b } end

    -- The backdrop API is TEMPLATE-DEPENDENT, so it is copied only onto a
    -- frame whose template confers it. A frame without it reads nil for
    -- SetBackdrop, exactly as a plain client frame does -- and the `__absent`
    -- table records the absence, the same mechanism the MAIN harness uses
    -- (Tests/harness/load_test.lua: `__absent` is consulted first, and via
    -- rawget, because reading t.__absent through __index would recurse).
    local backdropCapable = type(template) == "string"
        and BACKDROP_TEMPLATES[template] == true
    for k, v in pairs(R) do
        if backdropCapable or not BACKDROP_METHODS[k] then
            region[k] = v
        end
    end
    if not backdropCapable then
        region.__absent = {
            SetBackdrop = true,
            GetBackdrop = true,
            SetBackdropColor = true,
        }
    end
    return region
end

-- Globals, written into the real global table because the modules read _G.
_G.time = os.time
-- RankDB stamps and validates records with server epoch seconds now, so the
-- browser harness must model the same global the real client exposes.
_G.GetServerTime = os.time
_G.UnitGUID = function(unit)
    if unit == "player" then return "Player-0-0000000A" end
    return nil
end
_G.GetNormalizedRealmName = function() return "TestRealm" end
_G.GetRealmName = function() return "TestRealm" end

-- ---------------------------------------------------------------------------
-- The client's own slot-label strings (Batch 7, item 1)
-- ---------------------------------------------------------------------------
--
-- The gear panel labels every row with the CLIENT's INVTYPE_* string, so the
-- panel reads in the player's language without this add-on being translated.
-- These are the globals the client publishes, verified in the FrameXML mirror
-- on ALL FIVE branches (origin/classic_era, origin/classic_anniversary,
-- origin/classic_titan, origin/forever, origin/live): INVTYPE_HAND is the hand
-- slot's name on every one of them, and INVTYPE_HANDS exists in NONE of them.
--
-- The marker values stand in for the client's translated strings. They are
-- deliberately NOT a real language: this harness must never invent a
-- translation, and a marker cannot be mistaken for one.
--
-- 15 distinct globals cover the panel's 17 rows (FINGER and TRINKET are each
-- named twice).
local CLIENT_SLOT_LABELS = {
    INVTYPE_HEAD = "SLOTLABEL_HEAD",
    INVTYPE_NECK = "SLOTLABEL_NECK",
    INVTYPE_SHOULDER = "SLOTLABEL_SHOULDER",
    INVTYPE_CLOAK = "SLOTLABEL_CLOAK",
    INVTYPE_CHEST = "SLOTLABEL_CHEST",
    INVTYPE_WRIST = "SLOTLABEL_WRIST",
    INVTYPE_HAND = "SLOTLABEL_HAND",
    INVTYPE_WAIST = "SLOTLABEL_WAIST",
    INVTYPE_LEGS = "SLOTLABEL_LEGS",
    INVTYPE_FEET = "SLOTLABEL_FEET",
    INVTYPE_FINGER = "SLOTLABEL_FINGER",
    INVTYPE_TRINKET = "SLOTLABEL_TRINKET",
    INVTYPE_WEAPONMAINHAND = "SLOTLABEL_WEAPONMAINHAND",
    INVTYPE_WEAPONOFFHAND = "SLOTLABEL_WEAPONOFFHAND",
    INVTYPE_RANGED = "SLOTLABEL_RANGED",
}
for _slotName, _slotValue in pairs(CLIENT_SLOT_LABELS) do
    _G[_slotName] = _slotValue
end

_G.UIParent = newRegion("Frame", "UIParent")

-- Escape dispatch, modelled per client family.
--
-- The Classic family does NOT use KEY_ESCAPE -- Blizzard's own classic_era
-- FrameXML contains zero occurrences of it. It uses the OnEscapePressed frame
-- script and the engine-recognised UISpecialFrames list instead. Both exist on
-- all five clients, so the harness models BOTH and additionally models
-- UISpecialFrames only on the modern pair in the "classic" scenario, proving the
-- browser does not depend on the event that Classic never fires.
local SCENARIO = ((arg and arg[1]) or "classic"):lower()
local IS_CLASSIC = (SCENARIO ~= "retail" and SCENARIO ~= "forever")

-- Classic's escape list is a plain table of frame names; the engine closes them.
_G.UISpecialFrames = { "SomeBlizzardFrame" }

if not IS_CLASSIC then
    -- Modern pair additionally honours the KEY_ESCAPE event.
    _G.KEY_ESCAPE_FIRES = true
else
    _G.KEY_ESCAPE_FIRES = false
end

-- Did the browser register itself with the engine's special-frames list?
function _G.__isSpecialFrame(frameName)
    for _, entry in ipairs(_G.UISpecialFrames) do
        if entry == frameName then return true end
    end
    return false
end

-- FauxScrollFrame primitives modelled on Blizzard_SharedXML/
-- SecureScrollTemplates.lua, so frame.offset and the thumb value stay
-- consistent -- the exact desync this harness exists to catch.
local scrollbarValue = {}
_G.FauxScrollFrame_GetOffset = function(frame) return frame.offset or 0 end
_G.FauxScrollFrame_SetOffset = function(frame, offset) frame.offset = offset end
_G.FauxScrollFrame_Update = function(frame, numItems, numToDisplay, buttonHeight)
    frame.numItems = numItems or 0
    frame.numToDisplay = numToDisplay or 0
    frame.buttonHeight = buttonHeight or 1
    return (numItems or 0) > (numToDisplay or 0) and 1 or nil
end
-- The mock-fidelity contract: the mock must publish the arity the CLIENT
-- publishes (SecureScrollTemplates.lua:224 -- `return showScrollBar;`, one
-- value, on all five branches). See Tests/harness/mock_contract.lua.
MOCKC.assertArity(contractCheck, "FauxScrollFrame_Update", _G.FauxScrollFrame_Update)
_G.FauxScrollFrame_OnVerticalScroll = function(frame, value, itemHeight)
    scrollbarValue[frame] = value or 0
    frame.offset = math.floor(((value or 0) / (itemHeight or 1)) + 0.5)
end
local function thumbValue(frame) return scrollbarValue[frame] or 0 end

-- Resolve templates by name the way the client does, so an unknown template is
-- an error rather than a silently different widget.
local TEMPLATES = {
    BackdropTemplate = true,
    ButtonFrameTemplate = true,
    SearchBoxTemplate = true,
    UIPanelButtonTemplate = true,
    UIPanelCloseButton = true,
    InputBoxTemplate = true,
    FauxScrollFrameTemplate = true,
    UIDropDownMenuTemplate = true,
}
for name in pairs(TEMPLATES) do _G[name] = {} end
for _, name in ipairs({
    "GameFontNormal", "GameFontHighlight", "GameFontHighlightSmall",
    "GameFontNormalLarge", "GameFontDisableSmall", "GameFontHighlightSmallWhite",
}) do _G[name] = {} end

_G.CreateFrame = function(kind, name, parent, template)
    if type(template) == "string" and not TEMPLATES[template] then
        error("unknown template: " .. template, 2)
    end
    return newRegion(kind, name, parent or _G.UIParent, template)
end

-- Dropdown shims. The initializer is recorded so the test can run it and then
-- drive a real selection through the real entry.func, exactly as a click does.
local dropdownInitializers = {}
local dropdownEntries = {}
_G.UIDropDownMenu_Initialize = function(frame, initFunc)
    dropdownInitializers[frame] = initFunc
end
_G.UIDropDownMenu_AddButton = function(info)
    dropdownEntries[#dropdownEntries + 1] = info
end
_G.UIDropDownMenu_SetText = function(frame, text) frame.__text = text end
_G.UIDropDownMenu_SetWidth = function() end
_G.UIDropDownMenu_OnHide = function() end
_G.UIDropDownMenu_Refresh = function() end

-- ---------------------------------------------------------------------------
-- Load the modules under test, as the TOC loads them
-- ---------------------------------------------------------------------------

local namespace = {}

local function loadFile(name)
    local chunk, err = loadfile(ROOT .. "/" .. name)
    if not chunk then
        error("failed to load " .. name .. ": " .. tostring(err), 0)
    end
    return chunk(name, namespace)
end

-- Locale/enUS.lua runs BEFORE RankBrowser in the real TOC (TacoTip_Extras.toc
-- lines 11-21 versus 32), so in game the browser binds its live L table to the
-- REAL English locale, not to the empty fallback. Loading it here reproduces
-- that, which is what lets this harness pin RESOLVED strings -- localized
-- class names (A5/G4), the translated empty-state keys (A1/G1) -- instead of
-- only the code-side English fallbacks.
--
-- Core.lua is loaded FIRST, as the TOC loads it (TacoTip_Extras.toc:22, the
-- first runtime file). The class-colour chain lives in Core, so a harness that
-- left Core out graded a leaderboard whose rows were coloured by a fallback
-- path the real client never takes.
loadFile("Locale/enUS.lua")
loadFile("Core.lua")
loadFile("RankDB.lua")
loadFile("RankSync.lua")
loadFile("RankBrowser.lua")

-- Deterministic, obviously-fake quality ramp so colour assertions can pin
-- exact values instead of "roughly warm".
namespace.Scoring = loadFile("Scoring.lua")

local RankDB = namespace.RankDB
local RankBrowser = namespace.RankBrowser

-- ---------------------------------------------------------------------------
-- Seed a leaderboard deep enough to make scrolling meaningful
-- ---------------------------------------------------------------------------

local now = _G.time()
local PLAYER_GUID = "Player-0-0000000A"
local PLAYER_RANK = 20

-- Must match RankBrowser's NUM_ROWS. Hardcoded here on purpose: if the browser
-- grows or shrinks its visible page, this test must be revisited, not
-- silently re-tuned to whatever the new value happens to be.
--
-- REVISITED on 2026-10-20, deliberately: the operator asked for the
-- leaderboard window to get TALLER so the list shows more players without
-- scrolling, and RankBrowser.NUM_ROWS went from 12 to 16. The centring maths
-- below is written in terms of this constant, so it followed.
local NUM_ROWS = 16
check(true, "harness assumes 16 visible rows (matches RankBrowser.NUM_ROWS)")

local NAMES = {
    "Aardvark", "Bloodfang", "Cinder", "Duskblade", "Emberlyn",
    "Frostbane", "Grimtusk", "Holloway", "Ironvale", "Jadis",
    "Kaelstrom", "Lunareth", "Mournblade", "Nightfall", "Oakenshield",
    "Pyrelight", "Quillshot", "Ravenmoor", "Silverblade", "Thornwake",
    "Umbrafox", "Vandriel", "Wardenly", "Xal'atath", "Ysendra",
    "Zenkari", "Aerwynd", "Blackmoor", "Crestfall", "Duskwhisper",
    "Elorien", "Falstrider", "Galewick", "Hawthorne", "Ironsong",
}
local CLASSES = { "WARRIOR", "MAGE", "ROGUE", "PRIEST", "HUNTER", "DRUID" }

for i, name in ipairs(NAMES) do
    RankDB.StoreRecord({
        guid = "Player-1-" .. string.format("%08d", i),
        name = name,
        faction = (i % 2 == 0) and "Alliance" or "Horde",
        class = CLASSES[((i - 1) % #CLASSES) + 1],
        gs = 700 - (i * 10),          -- strictly descending: order == index
        ilvl = 60 + (i % 40),
        timestamp = now - (i * 60),
    })
end

-- The seeded NPCs span gs 690..350, so a player on 500 lands at overall rank
-- 20 of 36 -- past the first page, which makes "opens on row 1" and "opens on
-- the player" provably different states.
RankDB.StoreRecord({
    guid = PLAYER_GUID,
    name = "Tester",
    faction = "Alliance",
    class = "MAGE",
    specName = "Fire",
    gs = 505,
    ilvl = 71.5,
    timestamp = now - 30,
})

-- ---------------------------------------------------------------------------
-- Reach into the constructed window
-- ---------------------------------------------------------------------------

local frame = RankBrowser.CreateUI()
local scrollFrame = frame and frame.scrollFrame

local function childrenOf(region, kind)
    local result = {}
    for _, child in ipairs((region and region.__children) or {}) do
        if kind == nil or child.__kind == kind then
            result[#result + 1] = child
        end
    end
    return result
end

-- Rows are the Buttons carrying a rankText; they were created in order.
local rows = {}
for _, child in ipairs(childrenOf(frame, "Button")) do
    if type(child.rankText) == "table" then
        rows[#rows + 1] = child
    end
end

local function visibleRankTexts()
    local out_ = {}
    for i, row in ipairs(rows) do
        if row:IsShown() then
            out_[i] = row.rankText:GetText() .. " " .. row.nameText:GetText()
        end
    end
    return table.concat(out_, " | ")
end

local function findPlayerRow()
    for _, row in ipairs(rows) do
        if row.isPlayer then return row end
    end
    return nil
end

out("")
out("-- TacoTip_Extras focused harness: server leaderboard --")

check(type(frame) == "table", "CreateUI returns a frame", type(frame))
check(frame ~= nil and frame:GetName() == "TacoTipRankFrame",
    "the window is named TacoTipRankFrame", frame and tostring(frame:GetName()))
check(type(scrollFrame) == "table", "the window owns a FauxScrollFrame", type(scrollFrame))
check(#rows > 0, "row widgets were created", "rows=" .. #rows)

-- ---------------------------------------------------------------------------
-- 0. Escape closes the window -- on Classic's terms, not Retail's
-- ---------------------------------------------------------------------------

check(type(_G.__isSpecialFrame) == "function", "the escape scenario is configured")
check(_G.__isSpecialFrame("TacoTipRankFrame") == true,
    "the browser registered itself in UISpecialFrames",
    "scenario=" .. SCENARIO)

-- ---------------------------------------------------------------------------
-- The FIRST toggle shows the browser, and the second hides it
-- ---------------------------------------------------------------------------
--
-- The client leaves a newly created frame VISIBLE, and this harness's mock now
-- models that: Blizzard's own panels carry `hidden="true"` on the FRAME and
-- never on the template (origin/classic_era
--   Interface/AddOns/Blizzard_AddOnList/AddonList.xml:120 --
--   `<Frame name="AddonList" enableMouse="true" inherits="ButtonFrameTemplate"
--           mixin="AddonListMixin" hidden="true">`), and Blizzard's own code
-- creates frames and then HIDES them explicitly (origin/classic_era
--   Interface/AddOns/Blizzard_Calendar/Classic/Blizzard_Calendar.lua --
--   `eventButton = CreateFrame("Button", ...)` then `eventButton:Hide();`).
--
-- So the add-on has to hide the window itself. If it does not, the first
-- toggle HIDES a window that was already on screen and the player sees
-- nothing happen -- and the harness, with a mock that disagreed with the
-- client, could not have caught it.
check(_G.CreateFrame("Frame"):IsShown() == true,
    "a frame created in this environment is visible, as in the client")
check(frame:IsShown() == false,
    "a newly created browser window is hidden before the first toggle",
    "shown=" .. tostring(frame:IsShown()))
RankBrowser.Toggle()
check(frame:IsShown() == true,
    "the FIRST toggle shows the browser",
    "shown=" .. tostring(frame:IsShown()))
RankBrowser.Toggle()
check(frame:IsShown() == false,
    "the second toggle hides the browser",
    "shown=" .. tostring(frame:IsShown()))

-- The OnEscapePressed script is the route that fires on ALL five clients.
RankBrowser.Toggle()
check(frame:IsShown(), "the window is open before the escape check")
local escFrame = nil
for _, child in ipairs(childrenOf(_G.UIParent, "Frame")) do
    if child:GetName() == "TacoTipRankEscFrame" then
        escFrame = child
        break
    end
end
check(type(escFrame) == "table", "an escape listener frame exists", type(escFrame))
if escFrame then
    local onEscape = escFrame:GetScript("OnEscapePressed")
    check(type(onEscape) == "function",
        "the escape listener registered an OnEscapePressed handler", type(onEscape))
    if type(onEscape) == "function" then
        onEscape(escFrame)
        check(not frame:IsShown(), "OnEscapePressed closes the browser (Classic route)")

        -- Prove it again through the modern event too, so both routes are
        -- exercised; on the Classic scenario KEY_ESCAPE_FIRES is false, which
        -- is exactly why the Classic route above is the one that matters.
        RankBrowser.Toggle()
        check(frame:IsShown(), "the window reopened for the KEY_ESCAPE check")
        local onEvent = escFrame:GetScript("OnEvent")
        if type(onEvent) == "function" then
            onEvent(escFrame, "KEY_ESCAPE")
            check(not frame:IsShown(), "the KEY_ESCAPE handler closes the browser")
        end
    end
end

-- Leave the window CLOSED for the section below, which asserts what the first
-- open does. ScrollToTop would re-open a hidden window (it toggles), which
-- silently inverts the very next assertion.
if frame:IsShown() then
    frame:Hide()
end

-- ---------------------------------------------------------------------------
-- 1. Opening lands on the player, not on row 1
-- ---------------------------------------------------------------------------

local unfiltered, totalAll = RankDB.GetLeaderboard(nil, "All", "ALL", "")
local resolvedIndex = nil
for i = 1, totalAll do
    if unfiltered[i].guid == PLAYER_GUID then
        resolvedIndex = i
        break
    end
end
check(resolvedIndex == PLAYER_RANK,
    "the seeded player really is rank 20 (test premise holds)",
    "got " .. tostring(resolvedIndex))
check(resolvedIndex ~= nil and resolvedIndex > 12,
    "the player is past the first page, so open-at-top is observably wrong",
    "index=" .. tostring(resolvedIndex))

RankBrowser.Toggle()
check(frame:IsShown(), "Toggle shows the window when it was closed")

local offset = _G.FauxScrollFrame_GetOffset(scrollFrame)
check(offset > 0, "the window opens scrolled down, not at row 1", "offset=" .. tostring(offset))

-- Centred, not merely "somewhere on the page": the player must land on visible
-- row floor(NUM_ROWS/2). With 12 rows the centre sits between 6 and 7, so the
-- jump targets 6 -- the row the browser actually puts them on.
local centreRow = math.floor(NUM_ROWS / 2)
check(resolvedIndex - offset == centreRow,
    "the player lands on the centred visible row",
    "index=" .. tostring(resolvedIndex) .. " offset=" .. tostring(offset)
        .. " expected visible row " .. centreRow)
check(rows[1] and rows[1].rankText:GetText() == "#" .. tostring(resolvedIndex - centreRow + 1),
    "the top visible row is consistent with that offset",
    rows[1] and rows[1].rankText:GetText())

-- The thumb must have moved WITH frame.offset. Setting offset alone leaves the
-- thumb at 0 and FauxScrollFrame_Update reads the thumb, so the rows move while
-- the scrollbar claims to be at the top.
local thumb = thumbValue(scrollFrame)
check(thumb == offset * (rows[1] and 26 or 26),
    "the scrollbar thumb tracks frame.offset (no desync)",
    "thumb=" .. tostring(thumb) .. " expected=" .. tostring(offset * 26))

local playerRow = findPlayerRow()
check(playerRow ~= nil, "the player's row is flagged isPlayer")
check(playerRow ~= nil and playerRow.overlay:GetAlpha() > 0,
    "the player's row is highlighted", playerRow and playerRow.overlay:GetAlpha())
check(playerRow ~= nil and playerRow.youTag ~= nil and playerRow.youTag:IsShown(),
    "the player's row shows the YOU marker")
check(playerRow ~= nil and playerRow.nameText:GetText() == "Tester",
    "the flagged row is really the player's row",
    playerRow and playerRow.nameText:GetText())

-- Reopening must re-centre, not keep a stale offset.
RankBrowser.Toggle()  -- close
check(not frame:IsShown(), "Toggle hides the window when it was open")
scrollFrame.offset = 999
RankBrowser.Toggle()  -- reopen
offset = _G.FauxScrollFrame_GetOffset(scrollFrame)
check(offset > 0 and offset < 999, "reopening re-centres instead of keeping a stale offset",
    "offset=" .. tostring(offset))

-- ---------------------------------------------------------------------------
-- 2. Top / My Rank buttons, through their real OnClick handlers
-- ---------------------------------------------------------------------------

-- Matched on the word, not the glyph: Lua 5.1 has no \u{XXXX} escape, so
-- writing "\u{25B2} Top" would silently compare against the literal text
-- "\u{25B2} Top" and never match, turning a real regression check into a
-- check that can only fail.
local function buttonContaining(word)
    for _, child in ipairs(childrenOf(frame, "Button")) do
        if type(child.GetText) == "function" then
            local label = child:GetText()
            if type(label) == "string" and label:find(word, 1, true) then
                return child, label
            end
        end
    end
    return nil, nil
end

local topButton, topLabel = buttonContaining("Top")
local meButton, meLabel = buttonContaining("My Rank")
check(topButton ~= nil, "the Top button exists", tostring(topLabel))
check(meButton ~= nil, "the My Rank button exists", tostring(meLabel))

if topButton then
    topButton.Fire("OnClick")
    offset = _G.FauxScrollFrame_GetOffset(scrollFrame)
    check(offset == 0, "clicking Top scrolls to row 1", "offset=" .. tostring(offset))
    check(rows[1] and rows[1].rankText:GetText() == "#1",
        "the top row is rank #1 after clicking Top", rows[1] and rows[1].rankText:GetText())
    check(findPlayerRow() == nil, "no row is flagged as the player at the top")
end

if meButton then
    meButton.Fire("OnClick")
    offset = _G.FauxScrollFrame_GetOffset(scrollFrame)
    check(offset > 0, "clicking My Rank re-centres on the player", "offset=" .. tostring(offset))
    check(resolvedIndex - offset == math.floor(NUM_ROWS / 2),
        "the player is re-centred after clicking My Rank",
        "index=" .. tostring(resolvedIndex) .. " offset=" .. tostring(offset))
end

-- ScrollToTop as an API must behave identically.
RankBrowser.ScrollToTop()
check(_G.FauxScrollFrame_GetOffset(scrollFrame) == 0, "ScrollToTop() also returns to row 1")

-- ---------------------------------------------------------------------------
-- 3. Filters change the rendered set
-- ---------------------------------------------------------------------------

RankBrowser.ScrollToTop()
check(rows[1] and rows[1].nameText:GetText() == "Aardvark",
    "the unfiltered top entry is the highest GearScore",
    rows[1] and rows[1].nameText:GetText())

-- Whole-realm scope: no faction filter may exist, and both factions must be
-- present in the SAME list. A faction split is the thing most likely to creep
-- back in, and it would silently hide half the realm.
do
    local whole = RankDB.GetLeaderboard(nil, "All", "ALL", "")
    local allianceCount, hordeCount = 0, 0
    for _, entry in ipairs(whole) do
        if entry.faction == "Alliance" then allianceCount = allianceCount + 1
        elseif entry.faction == "Horde" then hordeCount = hordeCount + 1 end
    end
    check(allianceCount > 0 and hordeCount > 0,
        "the whole-realm list contains both factions",
        "alliance=" .. allianceCount .. " horde=" .. hordeCount)

    local factionButtons = {}
    for _, child in ipairs(childrenOf(frame, "Button")) do
        local label = child:GetText()
        if label == "Alliance" or label == "Horde" or label == "All Realm" then
            factionButtons[#factionButtons + 1] = label
        end
    end
    check(#factionButtons == 0,
        "no faction filter buttons exist (whole-server ranking)", table.concat(factionButtons, ","))
end

-- Class filter, driven through the real dropdown initializer and entry.func.
local classDD = nil
for _, child in ipairs(childrenOf(frame, "Frame")) do
    if child:GetName() == "TacoTipRankClassFilter" then
        classDD = child
        break
    end
end
check(classDD ~= nil, "the class filter dropdown exists")
check(type(dropdownInitializers[classDD]) == "function",
    "the class dropdown registered an initializer")

if classDD then
    dropdownEntries = {}
    dropdownInitializers[classDD](classDD)
    check(#dropdownEntries == 14,
        "the class menu lists All plus 13 classes", "entries=" .. #dropdownEntries)

    local mageEntry = nil
    for _, entry in ipairs(dropdownEntries) do
        -- Matched on the entry's canonical `value`, not its text: the text is
        -- now the LOCALIZED class name (A5/G4), so a text match would pin the
        -- display language instead of the selection.
        if entry.value == "MAGE" then mageEntry = entry end
    end
    check(mageEntry ~= nil and type(mageEntry.func) == "function",
        "the MAGE entry carries a selection handler")
    check(mageEntry ~= nil and mageEntry.text == "Mage",
        "the MAGE entry renders its localized class name",
        mageEntry and tostring(mageEntry.text))

    local evokerEntry = nil
    for _, entry in ipairs(dropdownEntries) do
        if entry.value == "EVOKER" then evokerEntry = entry end
    end
    check(evokerEntry ~= nil and evokerEntry.text == "Evoker",
        "the EVOKER entry renders its localized class name",
        evokerEntry and tostring(evokerEntry.text))

    if mageEntry then
        mageEntry.func()
        local mages, mageCount = RankDB.GetLeaderboard(nil, "All", "MAGE", "")
        check(mageCount > 0, "selecting MAGE narrows the leaderboard", "count=" .. tostring(mageCount))
        local visibleClass = rows[1] and rows[1].specText:GetText() or ""
        check(rows[1] and rows[1].nameText:GetText() == mages[1].name,
            "the filtered view renders the MAGE leader",
            rows[1] and rows[1].nameText:GetText())
        check(visibleClass ~= nil, "the filtered view still renders spec text", tostring(visibleClass))
        -- The seeded MAGE leader carries no specName, so the Spec column falls
        -- back to the localized class name (A5/G4) -- "Mage", not the raw
        -- token the dropdown used to show.
        check(rows[1] ~= nil and rows[1].specText:GetText() == "Mage",
            "the Spec column falls back to the localized class name",
            rows[1] and rows[1].specText:GetText())
        check(classDD:GetText() == "MAGE", "the dropdown label reflects the selection",
            classDD:GetText())

        -- Back to All Classes so later assertions run unfiltered.
        for _, entry in ipairs(dropdownEntries) do
            if entry.text == "All Classes" then entry.func() end
        end
        check(classDD:GetText() == "All Classes",
            "the dropdown label resets to All Classes", classDD:GetText())
    end
end

-- Search filter, through the real OnTextChanged handler.
local searchBox = childrenOf(frame, "EditBox")[1]
check(type(searchBox) == "table", "the search box exists", type(searchBox))
if searchBox then
    searchBox:SetText("Vale")
    searchBox.Fire("OnTextChanged", searchBox)
    local filtered, filteredCount = RankDB.GetLeaderboard(nil, "All", "ALL", "Vale")
    check(filteredCount == 1, "the search narrows to one match", "count=" .. tostring(filteredCount))
    check(rows[1] and rows[1].nameText:GetText() == filtered[1].name,
        "the search renders the matching player", rows[1] and rows[1].nameText:GetText())

    -- A search that matches nobody must hide every row.
    searchBox:SetText("zzzz-no-such-player")
    searchBox.Fire("OnTextChanged", searchBox)
    local anyShown = false
    for _, row in ipairs(rows) do
        if row:IsShown() then anyShown = true break end
    end
    check(not anyShown, "every row hides when the search matches nobody", visibleRankTexts())

    searchBox:SetText("")
    searchBox.Fire("OnTextChanged", searchBox)
end

-- ---------------------------------------------------------------------------
-- 4. Colours
-- ---------------------------------------------------------------------------

RankBrowser.ScrollToTop()

-- Rank 1 is the best in view, so its fraction is 1.0 -> the epic band.
local gr, gg, gb = rows[1].gsText:GetTextColor()
check(near(gr, 0.64) and near(gg, 0.21) and near(gb, 0.93),
    "the leader's GearScore uses the legendary colour",
    tostring(gr) .. "," .. tostring(gg) .. "," .. tostring(gb))

-- iLvl must share the GearScore colour; it used to be class-coloured.
local ir, ig, ib = rows[1].ilvlText:GetTextColor()
check(near(gr, ir) and near(gg, ig) and near(gb, ib),
    "iLvl shares the GearScore colour (not the class colour)",
    "gs=" .. tostring(gr) .. "," .. tostring(gg) .. "," .. tostring(gb)
        .. " ilvl=" .. tostring(ir) .. "," .. tostring(ig) .. "," .. tostring(ib))

-- Rank 1 is gold in the podium ramp, not the muted default.
local rr = colorOf(rows[1].rankText)
check(rr > 0.95 and rows[1].rankText:GetText() == "#1",
    "rank #1 is badged gold", rows[1].rankText:GetText())

-- Name is class-coloured and the left class bar agrees with it.
local nr, ng, nb = rows[1].nameText:GetTextColor()
local bar = rows[1].classBar.__colorTexture
check(bar ~= nil and near(nr, bar.r) and near(ng, bar.g) and near(nb, bar.b),
    "the class bar matches the name colour",
    "name=" .. tostring(nr) .. "," .. tostring(ng) .. "," .. tostring(nb))

-- Spec and last-seen are muted, i.e. secondary to the name.
local sr = colorOf(rows[1].specText)
check(near(sr, 0.62), "the spec column is muted", tostring(sr))

-- ---------------------------------------------------------------------------
-- 5. Sorting
-- ---------------------------------------------------------------------------
--
-- The `#` column must stay the GearScore rank no matter how the list is sorted.
-- That is the whole point of keeping a separate rank map: a leaderboard whose
-- rank numbers reshuffle when you sort by iLvl reads as though standing moved.

local function headerButton(word)
    for _, child in ipairs(childrenOf(frame, "Button")) do
        if child:GetName() == nil and type(child.GetText) == "function" then
            local label = child:GetText()
            if type(label) == "string" and label == word then
                return child
            end
        end
    end
    return nil
end

local gsHeader = headerButton("GEARSCORE")
local ilvlHeader = headerButton("iLVL")
local seenHeader = headerButton("LAST SEEN")
check(gsHeader ~= nil, "the GEARSCORE header is a clickable button")
check(ilvlHeader ~= nil, "the iLVL header is a clickable button")
check(seenHeader ~= nil, "the LAST SEEN header is a clickable button")

-- The sort hint ("Sorted by %s <arrow>") is the window's only statement of
-- DIRECTION, so A2/G2 asserts it flips on a repeat click. The arrows are
-- UTF-8 byte sequences; rather than spelling those bytes here (Lua 5.1 has no
-- \u{} escape, and a byte typo would go unnoticed), the tests compare the
-- hint's last whitespace-delimited TOKEN against the token the default order
-- ships with.
local function sortHintText()
    for _, child in ipairs(childrenOf(frame, "FontString")) do
        local text = child.GetText and child:GetText()
        if type(text) == "string" and text:find("Sorted by ", 1, true) == 1 then
            return text
        end
    end
    return nil
end

local function hintArrow(text)
    if type(text) ~= "string" then return nil end
    return text:match("(%S+)$")
end

-- Default order is GearScore descending.
RankBrowser.ScrollToTop()
local gsHint = sortHintText()
check(gsHint ~= nil and gsHint:find("Sorted by GEARSCORE", 1, true) == 1,
    "the sort hint names the default GearScore order", tostring(gsHint))
local gsOrder = {}
for i, row in ipairs(rows) do
    if row:IsShown() then gsOrder[i] = row.gsText:GetText() end
end
local descending = true
for i = 2, #gsOrder do
    if tonumber(gsOrder[i]) and tonumber(gsOrder[i - 1]) then
        if tonumber(gsOrder[i]) > tonumber(gsOrder[i - 1]) then descending = false end
    end
end
check(descending, "the default order is GearScore descending", table.concat(gsOrder, ","))

if ilvlHeader then
    ilvlHeader.Fire("OnClick")
    local ilvlOrder = {}
    for i, row in ipairs(rows) do
        if row:IsShown() then ilvlOrder[i] = tonumber(row.ilvlText:GetText()) end
    end
    local ilvlDescending = true
    for i = 2, #ilvlOrder do
        if ilvlOrder[i] and ilvlOrder[i - 1] and ilvlOrder[i] > ilvlOrder[i - 1] then
            ilvlDescending = false
        end
    end
    check(#ilvlOrder > 1, "sorting by iLVL renders rows", "count=" .. #ilvlOrder)
    check(ilvlDescending, "sorting by iLVL orders iLVL descending")

    -- The rank column must be the PLAYER's GearScore rank, not the row's
    -- position. After an iLvl re-sort the top row is a different person, so
    -- the correct invariant is that the displayed number matches that person's
    -- GearScore rank -- which is emphatically NOT 1.
    check(rows[1] ~= nil and rows[1].rankText:GetText() == "#" .. tostring(rows[1].gsRank),
        "the # column matches each row's own GearScore rank after sorting by iLVL",
        rows[1] and (rows[1].rankText:GetText() .. " vs gsRank=" .. tostring(rows[1].gsRank)))
    check(rows[1] ~= nil and rows[1].gsRank ~= 1,
        "the # column did NOT follow the iLVL re-sort into row positions",
        rows[1] and tostring(rows[1].gsRank))

    -- A2/G2: a repeat click on the ACTIVE column flips the direction. The
    -- label must not change, only the arrow -- and it must become the
    -- OPPOSITE of the descending arrow the default order shows above.
    local ilvlHintDesc = sortHintText()
    check(ilvlHintDesc ~= nil and ilvlHintDesc:find("Sorted by iLVL", 1, true) == 1,
        "the sort hint follows the iLVL click", tostring(ilvlHintDesc))
    check(hintArrow(ilvlHintDesc) ~= nil and hintArrow(ilvlHintDesc) == hintArrow(gsHint),
        "the descending arrow matches the default order's arrow",
        tostring(ilvlHintDesc) .. " vs " .. tostring(gsHint))

    ilvlHeader.Fire("OnClick")
    local ilvlAsc = {}
    for i, row in ipairs(rows) do
        if row:IsShown() then ilvlAsc[i] = tonumber(row.ilvlText:GetText()) end
    end
    local ilvlAscending = true
    for i = 2, #ilvlAsc do
        if ilvlAsc[i] and ilvlAsc[i - 1] and ilvlAsc[i] < ilvlAsc[i - 1] then
            ilvlAscending = false
        end
    end
    check(ilvlAscending, "a repeat iLVL click orders iLVL ascending")
    local ilvlHintAsc = sortHintText()
    check(ilvlHintAsc ~= nil and ilvlHintAsc:find("Sorted by iLVL", 1, true) == 1,
        "the ascending hint keeps the iLVL label", tostring(ilvlHintAsc))
    check(ilvlHintDesc ~= nil and ilvlHintAsc ~= nil
        and hintArrow(ilvlHintAsc) ~= hintArrow(ilvlHintDesc),
        "the sort-hint arrow flips on the repeat click",
        tostring(ilvlHintDesc) .. " -> " .. tostring(ilvlHintAsc))
    -- The `#`-column invariant must survive BOTH directions: rank stays the
    -- GearScore rank, not a row position, in ascending order too.
    check(rows[1] ~= nil and rows[1].rankText:GetText() == "#" .. tostring(rows[1].gsRank),
        "the # column still matches each row's own GearScore rank in ascending order",
        rows[1] and (rows[1].rankText:GetText() .. " vs gsRank=" .. tostring(rows[1].gsRank)))

    -- And the jump must still find the player.
    RankBrowser.TrackToPlayer()
    local playerRowAfterSort = findPlayerRow()
    check(playerRowAfterSort ~= nil, "the player is still found after sorting by iLVL")
end

if gsHeader then
    gsHeader.Fire("OnClick")
    RankBrowser.ScrollToTop()
    check(rows[1] and rows[1].rankText:GetText() == "#1",
        "switching back to GearScore restores rank order",
        rows[1] and rows[1].rankText:GetText())
end

if seenHeader then
    seenHeader.Fire("OnClick")
    local anyVisible = false
    for _, row in ipairs(rows) do
        if row:IsShown() then anyVisible = true break end
    end
    check(anyVisible, "sorting by LAST SEEN still renders rows")
    gsHeader.Fire("OnClick")
    RankBrowser.ScrollToTop()
end

-- ---------------------------------------------------------------------------
-- 6. Row tooltip on hover
-- ---------------------------------------------------------------------------

local tooltipOwner, tooltipLines = nil, {}
_G.GameTooltip = {
    SetOwner = function(_, owner) tooltipOwner = owner end,
    ClearLines = function() tooltipLines = {} end,
    AddLine = function(_, text) tooltipLines[#tooltipLines + 1] = tostring(text) end,
    Hide = function() tooltipOwner = nil tooltipLines = {} end,
}
check(type(_G.GameTooltip) == "table", "the harness models GameTooltip")

local hoverRow = nil
for _, row in ipairs(rows) do
    if row:IsShown() and row.entry then hoverRow = row break end
end
check(hoverRow ~= nil, "a visible row carries its entry for the tooltip")

if hoverRow then
    hoverRow.Fire("OnEnter")
    check(tooltipOwner == hoverRow, "hovering a row owns the GameTooltip",
        tostring(tooltipOwner))
    check(#tooltipLines >= 4,
        "the row tooltip carries the detail lines", "lines=" .. #tooltipLines)
    local joined = table.concat(tooltipLines, " | ")
    check(joined:find("GearScore:", 1, true) ~= nil, "the tooltip states the GearScore", joined)
    check(joined:find("Average iLvl:", 1, true) ~= nil, "the tooltip states Average iLvl", joined)
    check(joined:find("Last seen:", 1, true) ~= nil, "the tooltip states last-seen", joined)
    check(joined:find("Click to view gear", 1, true) ~= nil,
        "the tooltip hints that clicking opens the gear panel (A3/G7b)", joined)

    hoverRow.Fire("OnLeave")
    check(tooltipOwner == nil, "leaving the row hides the GameTooltip")
    check(#tooltipLines == 0, "leaving the row clears the tooltip lines")
end

-- ---------------------------------------------------------------------------
-- Hunter M-NEW6: corrupt entry numerics count instead of truncating the card
-- ---------------------------------------------------------------------------
-- showRowTooltip validates numerics once BEFORE ClearLines: a corrupt entry
-- counts rowTooltipErrors and returns with the tooltip untouched, instead of
-- clearing the card and raising halfway through string.format. Revert map:
-- delete the numerics validation in RankBrowser.lua -> the corrupt hover
-- raises (and ClearLines runs), so both checks below go red.
do
    local debugBefore6 = RankBrowser.GetDebugState()
    local errsBefore6 = (debugBefore6 and debugBefore6.rowTooltipErrors) or 0
    local clearCalls6 = 0
    local realClear6 = _G.GameTooltip.ClearLines
    _G.GameTooltip.ClearLines = function() clearCalls6 = clearCalls6 + 1 end
    local savedEntry6 = hoverRow and hoverRow.entry or nil
    if hoverRow then
        hoverRow.entry = { name = "Corrupt", faction = "Alliance", class = "MAGE",
            specName = "Fire", gs = "not-a-number", ilvl = 71.5,
            timestamp = 1000000 }
    end
    local okHover6 = pcall(function() if hoverRow then hoverRow.Fire("OnEnter") end end)
    if hoverRow then
        hoverRow.entry = savedEntry6
    end
    _G.GameTooltip.ClearLines = realClear6
    local debugAfter6 = RankBrowser.GetDebugState()
    local errsAfter6 = (debugAfter6 and debugAfter6.rowTooltipErrors) or 0
    check(okHover6 == true,
        "a corrupt-numerics row hover does not raise",
        "ok=" .. tostring(okHover6))
    check(clearCalls6 == 0 and tooltipOwner == nil,
        "...and leaves the tooltip untouched (no ClearLines, no owner)",
        "clearCalls=" .. tostring(clearCalls6)
            .. " owner=" .. tostring(tooltipOwner))
    check(errsAfter6 == errsBefore6 + 1,
        "...while counting the validation failure in debug state",
        "rowTooltipErrors=" .. tostring(errsBefore6) .. "->" .. tostring(errsAfter6))
    check(type(debugAfter6 and debugAfter6.lastRowTooltipError) == "string",
        "...with the last error named",
        tostring(debugAfter6 and debugAfter6.lastRowTooltipError))
end

-- ---------------------------------------------------------------------------
-- 7. Spec icon degrades safely when absent
-- ---------------------------------------------------------------------------

do
    local iconRow = rows[1]
    check(iconRow ~= nil and iconRow.specIconTexture ~= nil,
        "rows own a spec icon texture")
    if iconRow and iconRow.specIconTexture then
        -- The seeded records carry no specIcon, so the icon must be hidden
        -- rather than drawing an empty box or raising.
        check(iconRow.specIconTexture:IsShown() == false,
            "a record with no spec icon hides the icon texture")
    end
end

-- ---------------------------------------------------------------------------
-- 8. Empty state and footer
-- ---------------------------------------------------------------------------

local realGetLeaderboard = RankDB.GetLeaderboard
RankDB.GetLeaderboard = function() return {}, 0 end
RankBrowser.UpdateUI()
local allHidden = true
for _, row in ipairs(rows) do
    if row:IsShown() then allHidden = false break end
end
check(allHidden, "every row hides when the filter matches nobody", visibleRankTexts())

-- A1/G1: the state line must DISTINGUISH first-run from no-match, using the
-- keys that already ship translated in every locale (only the choice among
-- them is new). The class filter is All and the search box empty at this
-- point in the run, so an empty database reads as "no records yet".
local emptyState = frame.emptyStateText
check(emptyState ~= nil, "the window exposes the state line", type(emptyState))
if emptyState then
    check(emptyState:IsShown(), "the state line shows when the database is empty")
    check(emptyState:GetText() == "No records yet. Scores sync while you play.",
        "an empty database with no filters reads as first-run (LB_EMPTY)",
        emptyState:GetText())

    -- Same empty database, but now the search filter is active: no-match.
    searchBox:SetText("zzzz-no-such-player")
    searchBox.Fire("OnTextChanged", searchBox)
    check(emptyState:GetText() == "No players match the current filters.",
        "an empty match with active filters reads as no-match (LB_EMPTY_FILTERS)",
        emptyState:GetText())

    -- A database that holds ONLY the player gets its own line (LB_ONLY_YOU),
    -- and only while no filter is narrowing the view.
    searchBox:SetText("")
    searchBox.Fire("OnTextChanged", searchBox)
    local playerOnly = {
        { guid = PLAYER_GUID, name = "Tester", faction = "Alliance", class = "MAGE",
          specName = "Fire", gs = 505, ilvl = 71.5, timestamp = now },
    }
    RankDB.GetLeaderboard = function() return playerOnly, 1 end
    RankBrowser.UpdateUI()
    check(emptyState:IsShown(), "the state line shows when only the player is registered")
    check(emptyState:GetText() == "Only your own character is registered on this realm so far.",
        "a one-player database reads as only-you (LB_ONLY_YOU)", emptyState:GetText())
end

RankDB.GetLeaderboard = realGetLeaderboard
RankBrowser.UpdateUI()
if emptyState then
    check(not emptyState:IsShown(), "the state line hides once records return")
end

check(frame.footerText ~= nil and frame.footerText:GetText():find("Your Standing") ~= nil,
    "the footer reports the player's standing",
    frame.footerText and frame.footerText:GetText())
check(frame.footerText:GetText():find("#" .. PLAYER_RANK .. " Overall") ~= nil,
    "the footer carries the player's overall rank",
    frame.footerText:GetText())

-- ---------------------------------------------------------------------------
-- 9. My Rank with no record (G8/A4)
-- ---------------------------------------------------------------------------

-- Same stub shape as section 8: a database that does not contain the player.
-- Clicking My Rank must land on row 1 AND say why, instead of the silent jump
-- that used to read as a broken button.
RankDB.GetLeaderboard = function() return {}, 0 end

-- This first pass deliberately runs WITHOUT C_Timer: the transient note's
-- timer is feature-detected, so its absence must cost the note its auto-restore, never an error.
check(rawget(_G, "C_Timer") == nil,
    "the harness omits C_Timer, exercising the timer guard by absence")

meButton.Fire("OnClick")
offset = _G.FauxScrollFrame_GetOffset(scrollFrame)
check(offset == 0, "My Rank falls back to row 1 when the player has no record",
    "offset=" .. tostring(offset))
check(frame.footerText:GetText():find("Not ranked yet", 1, true) ~= nil,
    "the footer states that the player is not ranked yet (LB_NOT_ESTABLISHED)",
    frame.footerText:GetText())

-- Where timers DO exist, the note schedules its own restore and then gets out
-- of the way. The fake C_Timer records the scheduling instead of running it,
-- so the restore is asserted, not awaited.
local scheduledTimers = {}
_G.C_Timer = {
    -- C_Timer.After(seconds, callback) is a DOT call: no self argument.
    After = function(delay, fn)
        scheduledTimers[#scheduledTimers + 1] = { delay = delay, fn = fn }
    end,
}
meButton.Fire("OnClick")
check(#scheduledTimers == 1, "the transient note schedules its own restore",
    "timers=" .. #scheduledTimers)
check(scheduledTimers[1] ~= nil and scheduledTimers[1].delay == 2,
    "the restore is scheduled for about two seconds",
    scheduledTimers[1] and tostring(scheduledTimers[1].delay))

-- Records return; running the timer must land back on the real footer.
RankDB.GetLeaderboard = realGetLeaderboard
if scheduledTimers[1] then scheduledTimers[1].fn() end
check(frame.footerText:GetText():find("Your Standing", 1, true) ~= nil,
    "the footer restores the standing line once the note expires",
    frame.footerText:GetText())
_G.C_Timer = nil

-- ---------------------------------------------------------------------------
-- 10. Scan-complete edge feedback (G6/A6)
-- ---------------------------------------------------------------------------

-- The focused harness loads no Scanner.lua, so this section installs one:
-- first with the sound system ABSENT -- the guard-friendly path a missing
-- PlaySound/SOUNDKIT must survive -- then with recorders that prove the
-- guarded branch plays exactly once, and only on the completion EDGE.
check(rawget(_G, "PlaySound") == nil, "the harness omits PlaySound (sound guard exercised by absence)")
check(rawget(_G, "SOUNDKIT") == nil, "the harness omits SOUNDKIT (sound guard exercised by absence)")

local progressState = { active = false, percent = 0, done = 0, total = 0 }
namespace.Scanner = {
    GetProgress = function() return progressState end,
}

check(frame.scanStatus ~= nil, "the window owns a scan-status line", type(frame.scanStatus))
if frame.scanStatus then
    check(not frame.scanStatus:IsShown(), "the scan-status line starts hidden")

    -- A scan runs: polling is alive, and nothing may claim completion yet.
    progressState = { active = true, percent = 0.5, done = 5, total = 10 }
    RankBrowser.RefreshProgress()
    check(frame.scanning == true, "RefreshProgress tracks an active scan")
    check(not frame.scanStatus:IsShown(), "no completion line while the scan is running")

    -- The scan finishes: active -> inactive is the edge. With no
    -- PlaySound/SOUNDKIT installed, the completion TEXT must still appear --
    -- the silent degradation G6 prescribes.
    progressState = { active = false, percent = 1, done = 10, total = 10 }
    RankBrowser.RefreshProgress()
    check(frame.scanning == false, "RefreshProgress sees the scan go inactive")
    check(frame.scanStatus:IsShown(), "the completion line appears on the active->inactive edge")
    check(frame.scanStatus:GetText():find("Scan complete", 1, true) ~= nil,
        "the completion line says the scan is complete", frame.scanStatus:GetText())
    -- "Players tracked" is the RankDB pool size (35 seeded + the player), not
    -- the scanner's slot count.
    check(frame.scanStatus:GetText():find("36 players tracked", 1, true) ~= nil,
        "the completion line reports the tracked-player pool", frame.scanStatus:GetText())

    -- Now the sound side. The recorders must fire exactly once per edge; a
    -- refresh that is still active (or still inactive) may not replay it.
    local playedSounds = {}
    _G.PlaySound = function(id) playedSounds[#playedSounds + 1] = id end
    _G.SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 4321 }

    progressState = { active = true, percent = 0.2, done = 2, total = 10 }
    RankBrowser.RefreshProgress()
    check(#playedSounds == 0, "an active scan does not replay the completion sound")
    check(not frame.scanStatus:IsShown(), "a new scan clears the previous completion line")

    progressState = { active = false, percent = 1, done = 10, total = 10 }
    RankBrowser.RefreshProgress()
    check(#playedSounds == 1, "the completion edge plays the sound exactly once",
        "plays=" .. #playedSounds)
    check(playedSounds[1] == 4321,
        "the sound is SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON", tostring(playedSounds[1]))
    check(frame.scanStatus:IsShown(), "the completion line reappears on the second edge")
    _G.PlaySound = nil
    _G.SOUNDKIT = nil

    -- The line is a flash, not chrome: where timers exist it hides itself.
    scheduledTimers = {}
    _G.C_Timer = {
        After = function(delay, fn)
            scheduledTimers[#scheduledTimers + 1] = { delay = delay, fn = fn }
        end,
    }
    progressState = { active = true, percent = 0.1, done = 1, total = 10 }
    RankBrowser.RefreshProgress()
    progressState = { active = false, percent = 1, done = 10, total = 10 }
    RankBrowser.RefreshProgress()
    check(#scheduledTimers == 1 and scheduledTimers[1].delay == 5,
        "the completion line schedules its own short auto-hide",
        "timers=" .. #scheduledTimers)
    if scheduledTimers[1] then scheduledTimers[1].fn() end
    check(not frame.scanStatus:IsShown(), "the auto-hide timer clears the completion line")
    _G.C_Timer = nil
end

-- Restore the environment: no Scanner again, so the next RefreshProgress must
-- take the scanner-absent path -- bar hidden, no raise.
namespace.Scanner = nil
RankBrowser.RefreshProgress()
check(frame.scanning == false, "RefreshProgress degrades safely when the Scanner is gone")

-- ---------------------------------------------------------------------------
-- 11. Wire-diet render fallbacks: specID and classID derive at render
-- ---------------------------------------------------------------------------

-- A synced row carries ONLY what the versioned wire keeps: numeric ids, no
-- class string, no spec name, no faction. A second row carries both ids and
-- strings, so the engine path and the stored fallbacks can be told apart.
RankDB.StoreRecord({
    guid = "Player-9-900", name = "SyncedMage",
    classID = 8, specID = 577,
    gs = 100, ilvl = 60, timestamp = now - 5,
})
RankDB.StoreRecord({
    guid = "Player-9-901", name = "StoredWarrior",
    class = "WARRIOR", classID = 1, specName = "StoredSpec", specID = 71,
    faction = "Alliance",
    gs = 90, ilvl = 59, timestamp = now - 6,
})

-- The engine resolves a numeric specID to a localized name + icon on all five
-- branches (SharedXML/UnitUtil.lua calls the global GetSpecializationInfoByID
-- on every one). Mocked here; removed again below to pin the silent degrade.
--
-- The client publishes SEVEN values -- id, name, description, texture, role,
-- class, classDisplayName (origin/live:
-- Interface/AddOns/Blizzard_Communities/ClubFinder.lua:599 destructures
-- exactly seven). The mock published four, so #5-#7 were latent gaps. See
-- Tests/harness/mock_contract.lua for the contract and its citation.
_G.GetSpecializationInfoByID = function(specID)
    return specID, "MockSpec" .. tostring(specID), "", "Interface\\Icons\\MockSpec",
        "DPS", "MAGE", "Mage"
end
MOCKC.assertArity(contractCheck, "GetSpecializationInfoByID", _G.GetSpecializationInfoByID)

searchBox:SetText("SyncedMage")
searchBox.Fire("OnTextChanged", searchBox)
check(rows[1] ~= nil and rows[1].entry and rows[1].entry.guid == "Player-9-900",
    "the search narrows to the synced row", visibleRankTexts())
if rows[1] ~= nil and rows[1].entry then
    check(rows[1].specText:GetText() == "MockSpec577",
        "a numeric specID resolves to the engine's localized spec name",
        tostring(rows[1].specText:GetText()))
    check(rows[1].specIconTexture:IsShown() == true,
        "a numeric specID shows the engine's spec icon")
    local cr, cg, cb = rows[1].nameText:GetTextColor()
    check(near(cr, 0.41) and near(cg, 0.80) and near(cb, 0.94),
        "the name colour derives from classID with no class string",
        ("r=%s g=%s b=%s"):format(tostring(cr), tostring(cg), tostring(cb)))
    rows[1].Fire("OnEnter")
    local dietJoined = table.concat(tooltipLines, " | ")
    check(dietJoined:find("MockSpec577", 1, true) ~= nil,
        "the row tooltip shows the engine-resolved spec name", dietJoined)
    check(dietJoined:find("Alliance", 1, true) == nil
        and dietJoined:find("Horde", 1, true) == nil
        and dietJoined:find("Unknown", 1, true) == nil,
        "a faction-less row omits the faction line", dietJoined)
    rows[1].Fire("OnLeave")
end

-- A faction-carrying row still states it: the line renders when present.
searchBox:SetText("StoredWarrior")
searchBox.Fire("OnTextChanged", searchBox)
check(rows[1] ~= nil and rows[1].entry and rows[1].entry.guid == "Player-9-901",
    "the search narrows to the stored row", visibleRankTexts())
if rows[1] ~= nil and rows[1].entry then
    check(rows[1].specText:GetText() == "MockSpec71",
        "the engine path wins over the stored specName while present",
        tostring(rows[1].specText:GetText()))
    rows[1].Fire("OnEnter")
    local storedJoined = table.concat(tooltipLines, " | ")
    check(storedJoined:find("Alliance", 1, true) ~= nil,
        "a faction-carrying row keeps the faction line", storedJoined)
    rows[1].Fire("OnLeave")
end

-- Without the engine the same rows degrade silently: stored specName first,
-- then the localized class name -- never a raise, never a blank where data
-- exists. Classic-family clients have no equivalent API, so this absence path
-- is the one they always take.
_G.GetSpecializationInfoByID = nil
RankBrowser.UpdateUI()
searchBox:SetText("SyncedMage")
searchBox.Fire("OnTextChanged", searchBox)
check(rows[1] ~= nil and rows[1].entry and rows[1].entry.guid == "Player-9-900",
    "the search re-narrows after the engine is removed", visibleRankTexts())
if rows[1] ~= nil and rows[1].entry then
    check(rows[1].specText:GetText() == "Mage",
        "with no spec engine a classID-only row falls back to the localized class name",
        tostring(rows[1].specText:GetText()))
    check(rows[1].specIconTexture:IsShown() == false,
        "with no spec engine the icon hides instead of drawing a broken box")
end
searchBox:SetText("StoredWarrior")
searchBox.Fire("OnTextChanged", searchBox)
check(rows[1] ~= nil and rows[1].entry and rows[1].entry.guid == "Player-9-901",
    "the stored row is found again without the engine", visibleRankTexts())
if rows[1] ~= nil and rows[1].entry then
    check(rows[1].specText:GetText() == "StoredSpec",
        "with no spec engine a row falls back to its stored specName",
        tostring(rows[1].specText:GetText()))
end
searchBox:SetText("")
searchBox.Fire("OnTextChanged", searchBox)

-- ---------------------------------------------------------------------------
-- 12. Stage-3 wire-to-render: specID 0 renders class fallback, nonzero localizes
-- ---------------------------------------------------------------------------

-- The rows arrive through the R2 wire (S response), not by direct seeding:
-- pre-Stage-3 the version gate refuses them and nothing renders.
local RankSync = namespace.RankSync
local wire6a = RankSync.SerializeRecord({
    guid = "Player-9-910", name = "SpecZero",
    classID = 1, specID = 0, gs = 80, ilvl = 58, timestamp = now - 4,
})
local wire6b = RankSync.SerializeRecord({
    guid = "Player-9-911", name = "SpecIDd",
    classID = 1, specID = 71, gs = 79, ilvl = 58, timestamp = (now or 0) - 5,
})
RankSync.HandlePayload("S;spec6;" .. (wire6a or ""), "GUILD", "WirePeer")
RankSync.HandlePayload("S;spec6;" .. (wire6b or ""), "GUILD", "WirePeer")

-- The engine resolves a numeric specID; re-mock it (section 11 removed it).
-- Seven values, as the client publishes -- see the contract table.
_G.GetSpecializationInfoByID = function(specID)
    return specID, "MockSpec" .. tostring(specID), "", "Interface\\Icons\\MockSpec",
        "DPS", "MAGE", "Mage"
end
MOCKC.assertArity(contractCheck, "GetSpecializationInfoByID", _G.GetSpecializationInfoByID)
RankBrowser.UpdateUI()
searchBox:SetText("SpecZero")
searchBox.Fire("OnTextChanged", searchBox)
check(rows[1] ~= nil and rows[1].entry and rows[1].entry.guid == "Player-9-910",
    "the R2-fed specID-0 row reaches the browser", visibleRankTexts())
if rows[1] ~= nil and rows[1].entry then
    check(rows[1].specText:GetText() == "Warrior",
        "specID 0 renders class fallback, nonzero localizes (fallback half)",
        tostring(rows[1].specText:GetText()))
end
searchBox:SetText("SpecIDd")
searchBox.Fire("OnTextChanged", searchBox)
check(rows[1] ~= nil and rows[1].entry and rows[1].entry.guid == "Player-9-911",
    "the R2-fed nonzero-specID row reaches the browser", visibleRankTexts())
if rows[1] ~= nil and rows[1].entry then
    check(rows[1].specText:GetText() == "MockSpec71",
        "specID 0 renders class fallback, nonzero localizes (localized half)",
        tostring(rows[1].specText:GetText()))
end
searchBox:SetText("")
searchBox.Fire("OnTextChanged", searchBox)

-- ---------------------------------------------------------------------------
-- 13. Stage-3 guild text filter
-- ---------------------------------------------------------------------------

RankDB.StoreRecord({
    guid = "Player-9-920", name = "GuildedA",
    class = "WARRIOR", classID = 1, gs = 70, ilvl = 57, timestamp = now - 7,
    guild = "Ember Covenant",
})
RankDB.StoreRecord({
    guid = "Player-9-921", name = "GuildedB",
    class = "MAGE", classID = 8, gs = 69, ilvl = 57, timestamp = now - 8,
    guild = "Ember Covenant",
})

-- The DB predicate first: a guild substring narrows, and clearing restores.
local _, narrowedCount = RankDB.GetLeaderboard(nil, "All", "ALL", "", "ember")
local _, wideCount = RankDB.GetLeaderboard(nil, "All", "ALL", "")
check(narrowedCount == 2 and wideCount > narrowedCount,
    "guild text filter narrows, empty guild rows survive unfiltered",
    "narrowed=" .. tostring(narrowedCount) .. " wide=" .. tostring(wideCount))

-- Then through the real filter box: the second EditBox in the control row.
local boxes = childrenOf(frame, "EditBox")
local guildBox = boxes[2]
check(type(guildBox) == "table",
    "the guild filter box exists beside the search box", "boxes=" .. tostring(#boxes))
if guildBox then
    guildBox:SetText("ember")
    guildBox.Fire("OnTextChanged", guildBox)
    check(rows[1] and rows[1].nameText:GetText() == "GuildedA"
        and rows[2] and rows[2].nameText:GetText() == "GuildedB",
        "the guild filter renders only the matching guild", visibleRankTexts())
    guildBox:SetText("")
    guildBox.Fire("OnTextChanged", guildBox)
    check(rows[1] and rows[1].nameText:GetText() == "Aardvark",
        "clearing the guild filter restores the full list", visibleRankTexts())
    -- Unguilded rows render blank, not hidden, with no filter active.
    searchBox:SetText("SyncedMage")
    searchBox.Fire("OnTextChanged", searchBox)
    check(rows[1] ~= nil and rows[1].entry
        and rows[1].entry.guild ~= nil and rows[1].entry.guild == "",
        "unguilded rows carry a blank guild, not a hidden one",
        rows[1] and tostring(rows[1].entry and rows[1].entry.guild))
    rows[1].Fire("OnEnter")
    local guildJoined = table.concat(tooltipLines, " | ")
    check(guildJoined:find("Ember Covenant", 1, true) == nil
        and guildJoined:find("Unknown", 1, true) == nil,
        "an unguilded row shows no guild and no Unknown noise", guildJoined)
    rows[1].Fire("OnLeave")
    searchBox:SetText("")
    searchBox.Fire("OnTextChanged", searchBox)
    searchBox:SetText("GuildedA")
    searchBox.Fire("OnTextChanged", searchBox)
    rows[1].Fire("OnEnter")
    local covenantJoined = table.concat(tooltipLines, " | ")
    check(covenantJoined:find("Ember Covenant", 1, true) ~= nil,
        "a guilded row shows its guild in the tooltip", covenantJoined)
    rows[1].Fire("OnLeave")
    searchBox:SetText("")
    searchBox.Fire("OnTextChanged", searchBox)
end

-- ---------------------------------------------------------------------------
-- 14. Stage-3 level column: renders, sorts, # invariant holds
-- ---------------------------------------------------------------------------

RankDB.StoreRecord({
    guid = "Player-9-930", name = "LevelHigh",
    class = "WARRIOR", classID = 1, gs = 60, ilvl = 56, timestamp = now - 9,
    level = 80,
})
RankDB.StoreRecord({
    guid = "Player-9-931", name = "LevelLow",
    class = "WARRIOR", classID = 1, gs = 59, ilvl = 56, timestamp = now - 10,
    level = 1,
})

check(rows[1] ~= nil and rows[1].levelText ~= nil,
    "level column renders, sort flips, # invariant holds (column exists)")
if rows[1] ~= nil and rows[1].levelText ~= nil then
    -- Old rows without a level render blank, never "0".
    searchBox:SetText("SyncedMage")
    searchBox.Fire("OnTextChanged", searchBox)
    check(rows[1].levelText:GetText() == "",
        "a row without a level renders blank, not 0",
        "level=" .. tostring(rows[1].levelText:GetText()))
    searchBox:SetText("")
    searchBox.Fire("OnTextChanged", searchBox)

    -- Isolate the two level rows, then sort by LEVEL through the real header.
    searchBox:SetText("Level")
    searchBox.Fire("OnTextChanged", searchBox)
    local levelHeader = nil
    for _, child in ipairs(childrenOf(frame, "Button")) do
        if type(child.GetText) == "function" and child:GetText() == "LEVEL" then
            levelHeader = child
            break
        end
    end
    check(levelHeader ~= nil, "the LEVEL header is sortable", tostring(levelHeader))
    if levelHeader then
        levelHeader.Fire("OnClick")
        check(rows[1] and rows[1].levelText:GetText() == "80"
            and rows[2] and rows[2].levelText:GetText() == "1",
            "level sort descending puts 80 first",
            (rows[1] and rows[1].levelText:GetText() or "?") .. "/"
                .. (rows[2] and rows[2].levelText:GetText() or "?"))
        check(rows[1] and rows[1].rankText:GetText() == "#1"
            and rows[2] and rows[2].rankText:GetText() == "#2",
            "the # column stays the GearScore rank under level sort",
            visibleRankTexts())
        levelHeader.Fire("OnClick")
        check(rows[1] and rows[1].levelText:GetText() == "1"
            and rows[2] and rows[2].levelText:GetText() == "80",
            "level sort flips ascending on repeat click",
            (rows[1] and rows[1].levelText:GetText() or "?") .. "/"
                .. (rows[2] and rows[2].levelText:GetText() or "?"))
        check(rows[1] and rows[1].rankText:GetText() == "#2"
            and rows[2] and rows[2].rankText:GetText() == "#1",
            "the # column stays the GearScore rank when the direction flips",
            visibleRankTexts())
    end
    searchBox:SetText("")
    searchBox.Fire("OnTextChanged", searchBox)
end

-- ---------------------------------------------------------------------------
-- 15. Stage-3 PvP: retail self-rating never comes from sync
-- ---------------------------------------------------------------------------

RankDB.StoreRecord({
    guid = "Player-9-940", name = "ModernArena",
    class = "MAGE", classID = 8, gs = 50, ilvl = 55, timestamp = now - 11,
    arena = 2100,
})

-- Modern rated surface present: the synced rating must NOT render.
_G.C_PaperDollInfo = {
    GetInspectRatedBGData = function() return {} end,
}
RankBrowser.UpdateUI()
searchBox:SetText("ModernArena")
searchBox.Fire("OnTextChanged", searchBox)
check(rows[1] ~= nil and rows[1].entry and rows[1].entry.guid == "Player-9-940",
    "the arena-carrying row is found on the modern profile", visibleRankTexts())
if rows[1] ~= nil and rows[1].entry then
    rows[1].Fire("OnEnter")
    local modernJoined = table.concat(tooltipLines, " | ")
    check(modernJoined:find("2100", 1, true) == nil,
        "retail self-rating never comes from sync (modern surface hides it)", modernJoined)
    rows[1].Fire("OnLeave")
end

-- Classic surface (no rated API): the same synced value renders as inspected.
_G.C_PaperDollInfo = nil
RankBrowser.UpdateUI()
searchBox:SetText("ModernArena")
searchBox.Fire("OnTextChanged", searchBox)
if rows[1] ~= nil and rows[1].entry then
    rows[1].Fire("OnEnter")
    local classicJoined = table.concat(tooltipLines, " | ")
    check(classicJoined:find("2100", 1, true) ~= nil,
        "retail self-rating never comes from sync (classic surface shows it)", classicJoined)
    rows[1].Fire("OnLeave")
end
-- The rated-BG API is NOT the family marker: a classic client can expose the
-- modern API as a stub. Identity decides; the API probe is only the fallback.
-- Revert map: make Core.UsesModernPvPSurface consult only the API again -- the
-- classic-identity pin below goes red.
do
    local savedAdapter = namespace.TacoTipAdapter
    local savedPaperDoll = _G.C_PaperDollInfo

    -- (a) classic identity + the modern API present: the arena data must still
    -- render, because the family is classic whatever the stub answers.
    namespace.TacoTipAdapter = {
        GetInspector = function()
            return { IsClassic = function() return true end }
        end,
    }
    _G.C_PaperDollInfo = { GetInspectRatedBGData = function() return {} end }
    RankBrowser.UpdateUI()
    searchBox:SetText("ModernArena")
    searchBox.Fire("OnTextChanged", searchBox)
    if rows[1] ~= nil and rows[1].entry then
        rows[1].Fire("OnEnter")
        local joined = table.concat(tooltipLines, " | ")
        check(joined:find("2100", 1, true) ~= nil,
            "classic identity wins over the modern API stub (arena renders)", joined)
        rows[1].Fire("OnLeave")
    end

    -- (b) mainline identity + no rated API: identity alone must hide it.
    namespace.TacoTipAdapter = {
        GetInspector = function()
            return { IsClassic = function() return false end }
        end,
    }
    _G.C_PaperDollInfo = nil
    RankBrowser.UpdateUI()
    searchBox:SetText("ModernArena")
    searchBox.Fire("OnTextChanged", searchBox)
    if rows[1] ~= nil and rows[1].entry then
        rows[1].Fire("OnEnter")
        local joined = table.concat(tooltipLines, " | ")
        check(joined:find("2100", 1, true) == nil,
            "mainline identity hides the synced rating even without the API", joined)
        rows[1].Fire("OnLeave")
    end

    namespace.TacoTipAdapter = savedAdapter
    _G.C_PaperDollInfo = savedPaperDoll
end
searchBox:SetText("")
searchBox.Fire("OnTextChanged", searchBox)

-- ---------------------------------------------------------------------------
-- 16. Stage-4 gear panel: fresh session > persisted gear > not-scanned
-- ---------------------------------------------------------------------------

local function findGearPanel()
    -- A RECURSIVE search from the UIParent.
    --
    -- The panel is a child of the browser (above the rows by construction),
    -- and the browser is rebuilt from time to time -- RebuildUI discards the
    -- frame and creates a new one, and the panel follows it. A search that
    -- only looked at the ORIGINAL browser's children would stop finding the
    -- panel after the first rebuild, which is exactly when the panel's
    -- lifetime matters.
    local function walk(region)
        if type(region) ~= "table" then
            return nil
        end
        if rawget(region, "__name") == "TacoTipGearPanel" then
            return region
        end
        for _, child in ipairs((region.__children) or {}) do
            local found = walk(child)
            if found then
                return found
            end
        end
        return nil
    end
    return walk(_G.UIParent)
end

local function gearPanelText()
    local panel = findGearPanel()
    if panel == nil then
        return nil
    end
    local texts = {}
    for _, child in ipairs(childrenOf(panel, "FontString")) do
        texts[#texts + 1] = child:GetText()
    end
    return table.concat(texts, " | ")
end

-- Session cache serves first (Cache-shaped revision, item-ID-only cells).
namespace.Scanner = {
    GetRemote = function(guid)
        if guid == "Player-9-960" then
            return { revision = { slots = {
                [1] = { itemID = { value = 12345 } },
                [5] = { itemID = { value = 23456 } },
            } } }
        end
        return nil
    end,
}
check(RankBrowser.ShowGear({ guid = "Player-9-960", name = "CachedGear" }) == true,
    "gear panel opens for a cached entry")
local cachedOK
do
    local joined = gearPanelText()
    cachedOK = joined ~= nil
        and joined:find("item:12345", 1, true) ~= nil
        and joined:find("item:23456", 1, true) ~= nil
        and joined:find("has not been scanned", 1, true) == nil
end

-- The gear panel's GEOMETRY, to the pixel.
--
-- The row positions and the two enhancement dots on each row were the same
-- arithmetic written out twice, twelve lines apart, with the panel's own
-- sizes as loose numbers. They are named constants now, and this pins the
-- numbers they resolve to: the refactor was a RENAME, so every offset here
-- must be the offset the panel always had.
--
--   panel      400 x 470
--   row n      x 18, y -(46 + (n - 1) * 22)      (row 1: -46, row 17: -398)
--   row width  318
--   dots       x 344 (enchant) and 356 (sockets), y = the row's y - 7, 8 x 8
--   note       x 18, y 16 from the bottom, 360 wide
do
    local panel = findGearPanel()
    check(type(panel) == "table", "the gear panel exists for the geometry pin",
        type(panel))
    if type(panel) == "table" then
        check(panel:GetWidth() == 400 and panel:GetHeight() == 470,
            "the gear panel is 400 x 470",
            tostring(panel:GetWidth()) .. "x" .. tostring(panel:GetHeight()))
        local gearRows = panel.rows or {}
        local expectedY = { -46, -68, -90 }
        local geometryBad = {}
        for index = 1, 3 do
            local row = gearRows[index]
            if type(row) ~= "table" then
                geometryBad[#geometryBad + 1] = "row " .. index .. " missing"
            else
                local _, _, _, x, y = row:GetPoint()
                if x ~= 18 or y ~= expectedY[index] then
                    geometryBad[#geometryBad + 1] = ("row %d at %s,%s"):format(
                        index, tostring(x), tostring(y))
                end
                if row:GetWidth() ~= 318 then
                    geometryBad[#geometryBad + 1] = ("row %d width %s"):format(
                        index, tostring(row:GetWidth()))
                end
            end
        end
        -- The last row: 46 + 16 * 22 = 398 below the top.
        local last = gearRows[#gearRows]
        if type(last) == "table" then
            local _, _, _, x, y = last:GetPoint()
            if x ~= 18 or y ~= -398 then
                geometryBad[#geometryBad + 1] = ("last row at %s,%s"):format(
                    tostring(x), tostring(y))
            end
        else
            geometryBad[#geometryBad + 1] = "last row missing"
        end
        check(#geometryBad == 0, "every gear panel row sits where it always sat",
            table.concat(geometryBad, "; "))

        -- The dots hang off the SAME row positions, seven pixels lower.
        local dotBad = {}
        local dots = { panel.dotEnchant or {}, panel.dotSocket or {} }
        local dotX = { 344, 356 }
        for side = 1, 2 do
            for index = 1, 3 do
                local dot = dots[side][index]
                if type(dot) ~= "table" then
                    dotBad[#dotBad + 1] = "dot " .. side .. "/" .. index .. " missing"
                else
                    local _, _, _, x, y = dot:GetPoint()
                    local wantY = expectedY[index] - 7
                    if x ~= dotX[side] or y ~= wantY then
                        dotBad[#dotBad + 1] = ("dot %d/%d at %s,%s"):format(
                            side, index, tostring(x), tostring(y))
                    end
                    if dot:GetWidth() ~= 8 or dot:GetHeight() ~= 8 then
                        dotBad[#dotBad + 1] = ("dot %d/%d size %sx%s"):format(
                            side, index, tostring(dot:GetWidth()),
                            tostring(dot:GetHeight()))
                    end
                end
            end
        end
        check(#dotBad == 0, "every gear panel dot sits where it always sat",
            table.concat(dotBad, "; "))

        local note = panel.note
        local noteOK = false
        if type(note) == "table" then
            local _, _, _, x, y = note:GetPoint()
            noteOK = (x == 18 and y == 16 and note:GetWidth() == 360)
        end
        check(noteOK, "the gear panel's note sits where it always sat",
            type(note) == "table" and (tostring(select(4, note:GetPoint())) .. ","
                .. tostring(select(5, note:GetPoint())) .. " w="
                .. tostring(note:GetWidth())) or "no note")
    end
end

-- Persisted gear (no session entry) renders dimmed with a last-synced note.
RankDB.StoreGear("Player-9-961", now - 3600, "1=777888,16=999000")
check(RankBrowser.ShowGear({ guid = "Player-9-961", name = "PersistedGear" }) == true,
    "gear panel opens for a persisted-only entry")
local persistedOK
do
    local joined = gearPanelText()
    persistedOK = joined ~= nil
        and joined:find("item:777888", 1, true) ~= nil
        and joined:find("item:999000", 1, true) ~= nil
        and joined:find("|cff808080", 1, true) ~= nil
        and joined:find("Last synced", 1, true) ~= nil
end

-- Neither session nor persisted: the honest not-scanned note, never blank
-- rows mistaken for data.
check(RankBrowser.ShowGear({ guid = "Player-9-962", name = "NeverScanned" }) == true,
    "gear panel opens for an unscanned entry")
local unscannedOK
do
    local joined = gearPanelText()
    unscannedOK = joined ~= nil
        and joined:find("has not been scanned", 1, true) ~= nil
end
namespace.Scanner = nil

check(cachedOK and persistedOK and unscannedOK,
    "gear panel renders cached IDs, uncached shows not-scanned",
    "cached=" .. tostring(cachedOK) .. " persisted=" .. tostring(persistedOK)
        .. " unscanned=" .. tostring(unscannedOK))

-- ---------------------------------------------------------------------------
-- Batch 7 item 1: the slot labels come from the CLIENT's INVTYPE_* strings
-- ---------------------------------------------------------------------------
--
-- The panel resolves each row's label through the client global, so it reads
-- in the player's language without this add-on being translated. The table
-- used to name the hand row "INVTYPE_HANDS" -- a name that exists in NONE of
-- the five supported clients (verified in the FrameXML mirror on
-- origin/classic_era, origin/classic_anniversary, origin/classic_titan,
-- origin/forever and origin/live), so that row silently fell back to the
-- English literal in every client and every language.
--
-- Three things are pinned here:
--   (a) the client's global is used when it is present;
--   (b) the English fallback is used when it is absent;
--   (c) all 17 rows name the global they are supposed to name, so a typo in
--       one name fails the suite instead of degrading that one row to
--       English with nothing to show for it.
do
    -- (c) the 17 rows, in order, with the global each one must name.
    local EXPECTED_ROWS = {
        { slot = 1,  global = "INVTYPE_HEAD",           fallback = "Head" },
        { slot = 2,  global = "INVTYPE_NECK",           fallback = "Neck" },
        { slot = 3,  global = "INVTYPE_SHOULDER",       fallback = "Shoulder" },
        { slot = 15, global = "INVTYPE_CLOAK",          fallback = "Back" },
        { slot = 5,  global = "INVTYPE_CHEST",          fallback = "Chest" },
        { slot = 9,  global = "INVTYPE_WRIST",          fallback = "Wrist" },
        { slot = 10, global = "INVTYPE_HAND",           fallback = "Hand" },
        { slot = 6,  global = "INVTYPE_WAIST",          fallback = "Waist" },
        { slot = 7,  global = "INVTYPE_LEGS",           fallback = "Legs" },
        { slot = 8,  global = "INVTYPE_FEET",           fallback = "Feet" },
        { slot = 11, global = "INVTYPE_FINGER",         fallback = "Finger" },
        { slot = 12, global = "INVTYPE_FINGER",         fallback = "Finger" },
        { slot = 13, global = "INVTYPE_TRINKET",        fallback = "Trinket" },
        { slot = 14, global = "INVTYPE_TRINKET",        fallback = "Trinket" },
        { slot = 16, global = "INVTYPE_WEAPONMAINHAND", fallback = "Main Hand" },
        { slot = 17, global = "INVTYPE_WEAPONOFFHAND",  fallback = "Off Hand" },
        { slot = 18, global = "INVTYPE_RANGED",         fallback = "Ranged" },
    }
    local slotRows = (type(RankBrowser.GetSlotRows) == "function")
        and RankBrowser.GetSlotRows() or nil
    check(type(slotRows) == "table" and #slotRows == 17,
        "the gear panel exposes all 17 slot rows for pinning",
        "rows=" .. tostring(slotRows and #slotRows))
    if (type(slotRows) == "table") then
        local wrongName, wrongFallback, wrongSlot = nil, nil, nil
        for i = 1, #EXPECTED_ROWS do
            local got = slotRows[i]
            local want = EXPECTED_ROWS[i]
            if (not got) then
                wrongName = "row " .. i .. " missing"
                break
            end
            if (got.global ~= want.global) then
                wrongName = ("row %d global=%s want=%s"):format(i, tostring(got.global), want.global)
                break
            end
            if (got.fallback ~= want.fallback) then
                wrongFallback = ("row %d fallback=%s want=%s"):format(i, tostring(got.fallback), want.fallback)
                break
            end
            if (got.slot ~= want.slot) then
                wrongSlot = ("row %d slot=%s want=%s"):format(i, tostring(got.slot), tostring(want.slot))
                break
            end
            -- Every row must name a global the client actually publishes.
            -- A name outside the verified set is a typo that would degrade
            -- that one row to English forever.
            if (not CLIENT_SLOT_LABELS[got.global]) then
                wrongName = ("row %d names %s, which no client publishes")
                    :format(i, tostring(got.global))
                break
            end
        end
        check(wrongName == nil,
            "all 17 rows name a global the client publishes (INVTYPE_HAND, not INVTYPE_HANDS)",
            tostring(wrongName))
        check(wrongFallback == nil,
            "...and each row keeps its English fallback",
            tostring(wrongFallback))
        check(wrongSlot == nil,
            "...and each row keeps its equipment slot",
            tostring(wrongSlot))
        local handRow = slotRows[7]
        check(handRow ~= nil and handRow.global == "INVTYPE_HAND"
                and handRow.slot == 10 and handRow.fallback == "Hand",
            "the hand row names INVTYPE_HAND and falls back to \"Hand\"",
            handRow and (tostring(handRow.global) .. "/" .. tostring(handRow.slot)
                .. "/" .. tostring(handRow.fallback)) or "missing")
    end

    -- (a) and (b): render the panel and read the labels back.
    namespace.Scanner = {
        GetRemote = function(guid)
            if guid == "Player-9-970" then
                return { revision = { slots = {
                    [1] = { itemID = { value = 1111 } },
                    [10] = { itemID = { value = 2222 } },
                } } }
            end
            return nil
        end,
    }
    check(RankBrowser.ShowGear({ guid = "Player-9-970", name = "LabelGear" }) == true,
        "gear panel opens for the slot-label pin")
    local translated = gearPanelText()
    -- The rendered cell carries Blizzard's colour codes around the item id
    -- ("|cffffffffitem:2222|r"), so the row is read as LABEL + ":  " + a
    -- window of text, not as one fixed literal.
    local function rowCarries(joined, label, needle)
        if (joined == nil) then return false end
        local at = joined:find(label .. ":  ", 1, true)
        if (at == nil) then return false end
        return joined:sub(at, at + 80):find(needle, 1, true) ~= nil
    end
    check(rowCarries(translated, "SLOTLABEL_HAND", "item:2222"),
        "(a) the hand row uses the client's translated global when it is present",
        tostring(translated and translated:sub(1, 120)))
    local missingMarker = nil
    for name, marker in pairs(CLIENT_SLOT_LABELS) do
        if (translated == nil or translated:find(marker, 1, true) == nil) then
            missingMarker = name
            break
        end
    end
    check(missingMarker == nil,
        "...and every row of the panel takes its own client global",
        tostring(missingMarker))
    check(translated ~= nil and translated:find("SLOTLABEL_FINGER", 1, true) ~= nil,
        "...including the two rows that share a global",
        "finger=" .. tostring(translated and translated:find("SLOTLABEL_FINGER", 1, true)))

    -- (b) the English fallback when the client global is absent.
    local savedHand = _G.INVTYPE_HAND
    _G.INVTYPE_HAND = nil
    check(RankBrowser.ShowGear({ guid = "Player-9-970", name = "LabelGear" }) == true,
        "gear panel re-opens for the fallback half")
    local fallback = gearPanelText()
    check(rowCarries(fallback, "Hand", "item:2222"),
        "(b) the hand row falls back to the English \"Hand\" when the global is absent",
        tostring(fallback and fallback:sub(1, 120)))
    check(fallback ~= nil and fallback:find("SLOTLABEL_HAND", 1, true) == nil,
        "...and does not keep the stale client string",
        "leftover=" .. tostring(fallback and fallback:find("SLOTLABEL_HAND", 1, true)))
    _G.INVTYPE_HAND = savedHand
    namespace.Scanner = nil
end

-- ---------------------------------------------------------------------------
-- 17. Stage-4 D ingest updates the panel without a rescan
-- ---------------------------------------------------------------------------

RankDB.StoreGear("Player-9-950", now - 100, "1=111111")
RankSync.HandlePayload("D;2;d15;Player-9-950;" .. (now + 50) .. ";1/1;1=222222,5=333333",
    "GUILD", "WirePeer")
check(RankBrowser.ShowGear({ guid = "Player-9-950", name = "Ingested" }) == true,
    "gear panel opens for a D-ingested entry")
do
    local joined = gearPanelText()
    check(joined ~= nil
        and joined:find("item:222222", 1, true) ~= nil
        and joined:find("item:333333", 1, true) ~= nil
        and joined:find("item:111111", 1, true) == nil
        and joined:find("has not been scanned", 1, true) == nil,
        "D ingest updates panel without rescan",
        tostring(joined and joined:sub(1, 160)))
end

-- ---------------------------------------------------------------------------
-- 18. Stage 5 slice 5a: search, icons, colour, strip (brief checks 1-8)
-- ---------------------------------------------------------------------------
--
-- Each check below fails on pre-Stage-5 code: the widget is absent, so an
-- assertion on its surface cannot pass. State is reset at every check (search
-- and guild filters cleared, class All, GearScore descending, scrolled top)
-- and every stub the check installs is removed before the next check.

local function stage5Reset()
    _G.C_Timer = nil
    searchBox:SetText("")
    searchBox.Fire("OnTextChanged", searchBox)
    local filterBoxes = childrenOf(frame, "EditBox")
    local stage5GuildBox = filterBoxes[2]
    if stage5GuildBox then
        stage5GuildBox:SetText("")
        stage5GuildBox.Fire("OnTextChanged", stage5GuildBox)
    end
    -- Deterministic sort restore without reading sort state: landing on LEVEL
    -- first makes the GEARSCORE click always select it fresh (descending),
    -- whatever the previous column or direction was.
    local levelHead = headerButton("LEVEL")
    if levelHead then levelHead.Fire("OnClick") end
    local gsHead = headerButton("GEARSCORE")
    if gsHead then gsHead.Fire("OnClick") end
    RankBrowser.ScrollToTop()
end

local function refetchBrowser()
    frame = RankBrowser.CreateUI()
    for k in pairs(rows) do rows[k] = nil end
    for _, child in ipairs(childrenOf(frame, "Button")) do
        if type(child.rankText) == "table" then
            rows[#rows + 1] = child
        end
    end
    searchBox = childrenOf(frame, "EditBox")[1]
    return frame
end

local function ensureBrowserOpen()
    if frame == nil then refetchBrowser() end
    if not frame:IsShown() then
        RankBrowser.Toggle()
    end
    return frame
end

-- ---------------------------------------------------------------------------
-- Escape closes the GEAR PANEL and leaves the leaderboard up
-- ---------------------------------------------------------------------------
--
-- The gear panel does NOT own an escape route of its own. The browser owns
-- them -- RegisterEscapeClose registers ONE owner and the browser registers
-- first -- and the owner's handler closes the PANEL FIRST, leaving the
-- leaderboard up, and closes the browser only when no panel is open.
--
-- The panel used to call RegisterEscapeClose as well. That call was a NO-OP
-- (the owner was already set) but the comment beside it claimed the panel
-- had "the same three-route registration the browser uses", which was not
-- true. Registering the panel would ALSO have put it into UISpecialFrames,
-- where the engine hides the topmost special frame -- which would have
-- taken the browser down with the panel.
--
-- So the panel is not registered, the browser's handler closes it, and the
-- comment in the source now says exactly that.
do
    ensureBrowserOpen()
    local esc = nil
    for _, child in ipairs(childrenOf(_G.UIParent, "Frame")) do
        if child:GetName() == "TacoTipRankEscFrame" then
            esc = child
            break
        end
    end
    check(type(esc) == "table",
        "an escape listener frame exists for the gear panel check", type(esc))
    check(RankBrowser.ShowGear({ guid = "Player-9-960", name = "EscapeGear" }) == true,
        "the gear panel opens for the escape check")
    local panel = findGearPanel()
    check(type(panel) == "table" and panel:IsShown(),
        "the gear panel is open before the escape check", "got " .. type(panel))
    check(_G.__isSpecialFrame("TacoTipGearPanel") == false,
        "the gear panel is not registered in UISpecialFrames",
        "the panel must be closed by the browser's handler, not by the engine")
    if type(esc) == "table" and type(panel) == "table" then
        local onEscape = esc:GetScript("OnEscapePressed")
        check(type(onEscape) == "function",
            "the escape listener has an OnEscapePressed handler", type(onEscape))
        if type(onEscape) == "function" then
            onEscape(esc)
            check(not panel:IsShown(),
                "Escape closes the gear panel",
                "shown=" .. tostring(panel:IsShown()))
            check(frame:IsShown(),
                "Escape leaves the leaderboard up while the panel was open",
                "shown=" .. tostring(frame:IsShown()))
            -- With no panel open, the SAME handler closes the browser.
            onEscape(esc)
            check(not frame:IsShown(),
                "Escape closes the browser once the panel is gone",
                "shown=" .. tostring(frame:IsShown()))
        end
    end
    ensureBrowserOpen()
end

-- Check 1: search box builds on SearchBoxTemplate, falls back without it.
ensureBrowserOpen()
check(searchBox ~= nil and searchBox.__template == "SearchBoxTemplate",
    "search box builds on SearchBoxTemplate, falls back without it (template half)",
    searchBox and tostring(searchBox.__template))
do
    local savedTemplate = TEMPLATES.SearchBoxTemplate
    TEMPLATES.SearchBoxTemplate = nil
    if frame:IsShown() then RankBrowser.Toggle() end
    RankBrowser.RebuildUI()
    refetchBrowser()
    if not frame:IsShown() then RankBrowser.Toggle() end
    check(searchBox ~= nil and searchBox.__template == "InputBoxTemplate",
        "search box builds on SearchBoxTemplate, falls back without it (fallback half)",
        searchBox and tostring(searchBox.__template))
    stage5Reset()
    check(rows[1] ~= nil and rows[1].nameText:GetText() == "Aardvark",
        "search box builds on SearchBoxTemplate, falls back without it (filter still works)",
        visibleRankTexts())
    TEMPLATES.SearchBoxTemplate = savedTemplate
    if frame:IsShown() then RankBrowser.Toggle() end
    RankBrowser.RebuildUI()
    refetchBrowser()
    if not frame:IsShown() then RankBrowser.Toggle() end
end

-- m2: both-templates-absent degrades to a plain EditBox instead of raising.
-- Mirrors the Backdrop precedent's three-level pcall shape (ButtonFrame ->
-- Backdrop -> plain); the harness raises on unknown templates exactly like a
-- client without either template would.
do
    local savedSearchBox = TEMPLATES.SearchBoxTemplate
    local savedInputBox = TEMPLATES.InputBoxTemplate
    TEMPLATES.SearchBoxTemplate = nil
    TEMPLATES.InputBoxTemplate = nil
    if frame:IsShown() then RankBrowser.Toggle() end
    local okRebuild, rebuildErr = pcall(RankBrowser.RebuildUI)
    if okRebuild then
        refetchBrowser()
        if not frame:IsShown() then RankBrowser.Toggle() end
    end
    check(okRebuild and searchBox ~= nil,
        "search box degrades to a plain EditBox when both templates are absent (m2 fallback)",
        okRebuild and tostring(searchBox and searchBox.__template) or ("raised: " .. tostring(rebuildErr)))
    TEMPLATES.SearchBoxTemplate = savedSearchBox
    TEMPLATES.InputBoxTemplate = savedInputBox
    if frame:IsShown() then RankBrowser.Toggle() end
    RankBrowser.RebuildUI()
    refetchBrowser()
    if not frame:IsShown() then RankBrowser.Toggle() end
end

-- Check 2: dropdown entries carry class icons, rows carry class atlas.
ensureBrowserOpen()
stage5Reset()
do
    local seenAtlas = {}
    _G.GetClassAtlas = function(class)
        seenAtlas[#seenAtlas + 1] = class
        return "classicon-" .. tostring(class)
    end
    RankBrowser.UpdateUI()
    check(rows[1] ~= nil and rows[1].classIconTexture ~= nil
        and rows[1].classIconTexture.__atlas == "classicon-WARRIOR",
        "dropdown entries carry class icons, rows carry class atlas (row half)",
        rows[1] and tostring(rows[1].classIconTexture and rows[1].classIconTexture.__atlas))
    dropdownEntries = {}
    dropdownInitializers[classDD](classDD)
    local mageIcon, evokerIcon = nil, nil
    for _, entry in ipairs(dropdownEntries) do
        if entry.value == "MAGE" then mageIcon = entry.icon end
        if entry.value == "EVOKER" then evokerIcon = entry.icon end
    end
    check(mageIcon == "classicon-MAGE" and evokerIcon == "classicon-EVOKER",
        "dropdown entries carry class icons, rows carry class atlas (menu half)",
        "mage=" .. tostring(mageIcon) .. " evoker=" .. tostring(evokerIcon))
    check(seenAtlas[1] ~= nil,
        "dropdown entries carry class icons, rows carry class atlas (atlas consulted)",
        "calls=" .. tostring(#seenAtlas))
    _G.GetClassAtlas = nil
    RankBrowser.UpdateUI()
    local hiddenIcon = rows[1] ~= nil and rows[1].classIconTexture ~= nil
        and rows[1].classIconTexture:IsShown() == false
    local wr2, wg2, wb2 = rows[1].nameText:GetTextColor()
    local bar2 = rows[1].classBar.__colorTexture
    check(hiddenIcon,
        "dropdown entries carry class icons, rows carry class atlas (icons hide without the API)")
    check(bar2 ~= nil and near(wr2, bar2.r) and near(wg2, bar2.g) and near(wb2, bar2.b),
        "dropdown entries carry class icons, rows carry class atlas (bar and name unchanged)",
        "name=" .. tostring(wr2) .. "," .. tostring(wg2) .. "," .. tostring(wb2))
end

-- Check 3: hover highlight texture set, player overlay intact.
ensureBrowserOpen()
stage5Reset()
do
    local anyHighlight = false
    for _, row in ipairs(rows) do
        if row.__highlightTexture == "Interface\\QuestFrame\\UI-QuestTitleHighlight" then
            anyHighlight = true
            break
        end
    end
    check(anyHighlight,
        "hover highlight texture set, player overlay intact (highlight half)")
    RankBrowser.TrackToPlayer()
    local prow = findPlayerRow()
    check(prow ~= nil and prow.overlay:GetAlpha() > 0,
        "hover highlight texture set, player overlay intact (player half)")
end

-- Check 4: colour chain prefers RAID_CLASS_COLORS, falls back to hard table.
ensureBrowserOpen()
stage5Reset()
do
    _G.RAID_CLASS_COLORS = { WARRIOR = { r = 0.11, g = 0.22, b = 0.33 } }
    RankBrowser.UpdateUI()
    local wr, wg, wb = rows[1].nameText:GetTextColor()
    check(near(wr, 0.11) and near(wg, 0.22) and near(wb, 0.33),
        "colour chain prefers RAID_CLASS_COLORS, falls back to hard table (live half)",
        tostring(wr) .. "," .. tostring(wg) .. "," .. tostring(wb))
    _G.RAID_CLASS_COLORS = nil
    _G.CUSTOM_CLASS_COLORS = "junk-string"
    local okChain = pcall(RankBrowser.UpdateUI)
    local hr, hg, hb = rows[1].nameText:GetTextColor()
    check(okChain and near(hr, 0.78) and near(hg, 0.61) and near(hb, 0.43),
        "colour chain prefers RAID_CLASS_COLORS, falls back to hard table (fallback half)",
        "ok=" .. tostring(okChain) .. " " .. tostring(hr) .. "," .. tostring(hg) .. "," .. tostring(hb))
    _G.CUSTOM_CLASS_COLORS = nil
end

-- Check 4b: Shaman Blue reaches the leaderboard row.
--
-- The class colour is painted in three surfaces -- the unit tooltip, the
-- character/inspect summary frame and this row -- and all three read ONE
-- resolver in Core. A player whose tooltip says blue and whose row says pink
-- is the bug this pins.
--
-- Classic Era paints the Shaman PINK, and that is the CLIENT's own value,
-- read from the mirror rather than guessed:
--   origin/classic_era
--   Interface/AddOns/Blizzard_SharedXML/Vanilla/ClassColors.lua:9
--       ["SHAMAN"] = CreateColor(0.96, 0.55, 0.73)
-- The blue is the one the main add-on uses (main.lua: SHAMAN_BLUE_COLOR),
-- and it is the TBC/Wrath Shaman colour:
--   origin/classic_era
--   Interface/AddOns/Blizzard_SharedXML/TBC/ClassColors.lua:9
--       ["SHAMAN"] = CreateColor(0.0, 0.44, 0.87)
--
-- The REAL Core is loaded for this check -- it is the FIRST runtime file in
-- the TOC, loaded at the top of this harness -- so the resolver under test is
-- the shipped one and not a stub.
ensureBrowserOpen()
do
    local Core = namespace.Core
    local coreSettings = Core.GetSettings()

    local savedColors = _G.RAID_CLASS_COLORS
    local savedCustom = _G.CUSTOM_CLASS_COLORS
    local savedConfig = _G.TacoTipConfig
    _G.RAID_CLASS_COLORS = { SHAMAN = { r = 0.96, g = 0.55, b = 0.73 } }
    _G.CUSTOM_CLASS_COLORS = nil

    RankDB.StoreRecord({
        guid = "Player-9-990", name = "ShamanRow",
        class = "SHAMAN", classID = 7, gs = 42, ilvl = 50, timestamp = _G.time() - 10,
    })
    searchBox:SetText("ShamanRow")
    searchBox.Fire("OnTextChanged", searchBox)

    local function shamanRow()
        for _, row in ipairs(rows) do
            if row.entry and row.entry.class == "SHAMAN" then
                return row
            end
        end
        return nil
    end

    local PINK = { r = 0.96, g = 0.55, b = 0.73 }
    local BLUE = { r = 0.0, g = 0.44, b = 0.87 }

    coreSettings.shamanBlue = true
    RankBrowser.UpdateUI()
    local row = shamanRow()
    -- NOTE: `row and colorOf(row.nameText) or nil` would truncate the triple
    -- to ONE value -- an `and`/`or` expression always yields exactly one --
    -- and the green and blue would read nil. The helper is called on its own
    -- line for the same reason `colorOf` exists.
    local r1, g1, b1 = 0, 0, 0
    if row then r1, g1, b1 = colorOf(row.nameText) end
    check(row ~= nil and near(r1, BLUE.r) and near(g1, BLUE.g) and near(b1, BLUE.b),
        "the leaderboard row paints a Shaman blue when Shaman Blue is on",
        tostring(r1) .. "," .. tostring(g1) .. "," .. tostring(b1))

    coreSettings.shamanBlue = false
    RankBrowser.UpdateUI()
    row = shamanRow()
    local r2, g2, b2 = 0, 0, 0
    if row then r2, g2, b2 = colorOf(row.nameText) end
    check(near(r2, PINK.r) and near(g2, PINK.g) and near(b2, PINK.b),
        "the leaderboard row paints a Shaman the client's pink when Shaman Blue is off",
        tostring(r2) .. "," .. tostring(g2) .. "," .. tostring(b2))

    -- The main add-on's setting being off wins, so the class colour is the
    -- same in TacoTip and in the Extras.
    coreSettings.shamanBlue = true
    _G.TacoTipConfig = { shaman_blue = false }
    RankBrowser.UpdateUI()
    row = shamanRow()
    local r3, g3, b3 = 0, 0, 0
    if row then r3, g3, b3 = colorOf(row.nameText) end
    check(near(r3, PINK.r) and near(g3, PINK.g) and near(b3, PINK.b),
        "the main add-on's Shaman Blue being off wins over the Extras' own setting",
        tostring(r3) .. "," .. tostring(g3) .. "," .. tostring(b3))

    -- An unreadable main value is not a decision: it degrades to the Extras'
    -- own setting.
    coreSettings.shamanBlue = true
    _G.TacoTipConfig = { shaman_blue = "not-a-boolean" }
    RankBrowser.UpdateUI()
    row = shamanRow()
    local r4, g4, b4 = 0, 0, 0
    if row then r4, g4, b4 = colorOf(row.nameText) end
    check(near(r4, BLUE.r) and near(g4, BLUE.g) and near(b4, BLUE.b),
        "an unreadable main add-on value degrades to the Extras' own setting",
        tostring(r4) .. "," .. tostring(g4) .. "," .. tostring(b4))

    -- Restore everything this check moved.
    coreSettings.shamanBlue = true
    _G.TacoTipConfig = savedConfig
    _G.RAID_CLASS_COLORS = savedColors
    _G.CUSTOM_CLASS_COLORS = savedCustom
    searchBox:SetText("")
    searchBox.Fire("OnTextChanged", searchBox)
end

-- Check 5: debounced search renders after flush, not on keystroke.
ensureBrowserOpen()
stage5Reset()
do
    local timers = {}
    _G.C_Timer = {
        After = function(delay, fn)
            timers[#timers + 1] = { delay = delay, fn = fn }
        end,
    }
    local before = rows[1] and rows[1].nameText:GetText() or ""
    searchBox:SetText("zzzz-no-such-player")
    searchBox.Fire("OnTextChanged", searchBox)
    check(rows[1] ~= nil and rows[1].nameText:GetText() == before
        and rows[1]:IsShown(),
        "debounced search renders after flush, not on keystroke (no render yet)",
        "before=" .. tostring(before) .. " timers=" .. tostring(#timers))
    check(#timers == 1 and timers[1].delay == 0.2,
        "debounced search renders after flush, not on keystroke (0.2s flush scheduled)",
        "timers=" .. tostring(#timers))
    if timers[1] then timers[1].fn() end
    local anyShown = false
    for _, row in ipairs(rows) do
        if row:IsShown() then anyShown = true break end
    end
    check(not anyShown,
        "debounced search renders after flush, not on keystroke (flush lands)",
        visibleRankTexts())
    _G.C_Timer = nil
    searchBox:SetText("Vale")
    searchBox.Fire("OnTextChanged", searchBox)
    check(rows[1] ~= nil and rows[1].nameText:GetText() == "Ironvale",
        "debounced search renders after flush, not on keystroke (no-timer sync)",
        rows[1] and rows[1].nameText:GetText())
    searchBox:SetText("")
    searchBox.Fire("OnTextChanged", searchBox)
end

-- Check 6: summary strip hides on empty pool, shows pool/top/avg otherwise.
ensureBrowserOpen()
stage5Reset()
do
    local strip = frame.statStrip
    check(strip ~= nil, "summary strip hides on empty pool, shows pool/top/avg otherwise (exists)")
    if strip then
        local _, poolCount = RankDB.GetLeaderboard(nil, "All", "ALL", "")
        check(strip:IsShown()
            and strip:GetText():find(tostring(poolCount), 1, true) ~= nil
            and strip:GetText():find("690", 1, true) ~= nil,
            "summary strip hides on empty pool, shows pool/top/avg otherwise (content half)",
            strip:GetText())
        local realLB = RankDB.GetLeaderboard
        RankDB.GetLeaderboard = function() return {}, 0 end
        RankBrowser.UpdateUI()
        check(not strip:IsShown(),
            "summary strip hides on empty pool, shows pool/top/avg otherwise (empty half)")
        RankDB.GetLeaderboard = realLB
        RankBrowser.UpdateUI()
        check(strip:IsShown()
            and rows[1] ~= nil
            and rows[1].rankText:GetText() == "#" .. tostring(rows[1].gsRank),
            "summary strip hides on empty pool, shows pool/top/avg otherwise (# invariant holds)",
            rows[1] and rows[1].rankText:GetText())
    end
end

-- Check 7: fresh-row tick only for session-new rows.
ensureBrowserOpen()
do
    if frame:IsShown() then RankBrowser.Toggle() end
    RankBrowser.Toggle()
    local sessionNow = _G.time()
    RankDB.StoreRecord({
        guid = "Player-9-970", name = "FreshTickA",
        class = "WARRIOR", classID = 1, gs = 40, ilvl = 50, timestamp = sessionNow + 60,
    })
    RankDB.StoreRecord({
        guid = "Player-9-971", name = "OldTickB",
        class = "WARRIOR", classID = 1, gs = 41, ilvl = 50, timestamp = sessionNow - 3600,
    })
    searchBox:SetText("FreshTickA")
    searchBox.Fire("OnTextChanged", searchBox)
    check(rows[1] ~= nil and rows[1].entry and rows[1].entry.guid == "Player-9-970"
        and rows[1].freshTick ~= nil and rows[1].freshTick:IsShown(),
        "fresh-row tick only for session-new rows (fresh half)",
        visibleRankTexts())
    searchBox:SetText("OldTickB")
    searchBox.Fire("OnTextChanged", searchBox)
    check(rows[1] ~= nil and rows[1].entry and rows[1].entry.guid == "Player-9-971"
        and rows[1].freshTick ~= nil and not rows[1].freshTick:IsShown(),
        "fresh-row tick only for session-new rows (old half)",
        visibleRankTexts())
    searchBox:SetText("")
    searchBox.Fire("OnTextChanged", searchBox)
    RankBrowser.ScrollToTop()
    local strayTicks = 0
    for _, row in ipairs(rows) do
        if row:IsShown() and row.freshTick and row.freshTick:IsShown() then
            strayTicks = strayTicks + 1
        end
    end
    check(strayTicks == 0,
        "fresh-row tick only for session-new rows (all-old half)",
        "ticks=" .. tostring(strayTicks))
end

-- Check 8: level/guild columns survive sortAsc flip with # invariant.
ensureBrowserOpen()
do
    searchBox:SetText("")
    searchBox.Fire("OnTextChanged", searchBox)
    local filterBoxes = childrenOf(frame, "EditBox")
    local stage5GuildBox = filterBoxes[2]
    check(type(stage5GuildBox) == "table",
        "level/guild columns survive sortAsc flip with # invariant (guild box present)")
    if stage5GuildBox then
        stage5GuildBox:SetText("ember")
        stage5GuildBox.Fire("OnTextChanged", stage5GuildBox)
        check(rows[1] and rows[1].nameText:GetText() == "GuildedA"
            and rows[2] and rows[2].nameText:GetText() == "GuildedB",
            "level/guild columns survive sortAsc flip with # invariant (filter half)",
            visibleRankTexts())
        local gsHead = headerButton("GEARSCORE")
        check(gsHead ~= nil,
            "level/guild columns survive sortAsc flip with # invariant (header present)")
        if gsHead then
            -- Deterministic start: landing on LEVEL first makes the GEARSCORE
            -- click always select it fresh (descending), whatever the shared
            -- sort state was on entry.
            local levelHead = headerButton("LEVEL")
            if levelHead then levelHead.Fire("OnClick") end
            gsHead.Fire("OnClick")
            local descOK = rows[1] and rows[1].rankText:GetText() == "#1"
                and rows[2] and rows[2].rankText:GetText() == "#2"
                and rows[1].levelText:GetText() == ""
            check(descOK,
                "level/guild columns survive sortAsc flip with # invariant (descending half)",
                visibleRankTexts())
            gsHead.Fire("OnClick")
            local ascOK = rows[1] and rows[1].nameText:GetText() == "GuildedB"
                and rows[2] and rows[2].nameText:GetText() == "GuildedA"
                and rows[1].rankText:GetText() == "#2"
                and rows[2].rankText:GetText() == "#1"
            check(ascOK,
                "level/guild columns survive sortAsc flip with # invariant (ascending half)",
                visibleRankTexts())
            gsHead.Fire("OnClick")
        end
        stage5GuildBox:SetText("")
        stage5GuildBox.Fire("OnTextChanged", stage5GuildBox)
    end
    RankBrowser.ScrollToTop()
end

-- ---------------------------------------------------------------------------
-- 19. Stage 5 slice 5b: chrome, density, gear richness (brief checks 10, 11,
--     13-15, 17). Check 16 (tooltip lines) lives in load_test.lua, where
--     Tooltips is loaded; check 12 (virtualization) is NOT-APPLICABLE --
--     W12 ships only on measured realm need (brief default: do not ship).
-- ---------------------------------------------------------------------------

-- Check 10: ButtonFrame chrome keeps every behaviour.
ensureBrowserOpen()
stage5Reset()
do
    check(frame ~= nil and frame.__template == "ButtonFrameTemplate",
        "ButtonFrame chrome keeps every behaviour (template half)",
        frame and tostring(frame.__template))
    local savedTemplate = TEMPLATES.ButtonFrameTemplate
    TEMPLATES.ButtonFrameTemplate = nil
    if frame:IsShown() then RankBrowser.Toggle() end
    RankBrowser.RebuildUI()
    refetchBrowser()
    if not frame:IsShown() then RankBrowser.Toggle() end
    local fallbackOK = frame ~= nil and frame.__template == "BackdropTemplate"
    stage5Reset()
    local rowsOK = rows[1] ~= nil and rows[1].nameText:GetText() == "Aardvark"
    check(fallbackOK,
        "ButtonFrame chrome keeps every behaviour (fallback half)",
        frame and tostring(frame.__template))
    check(rowsOK,
        "ButtonFrame chrome keeps every behaviour (rows render on fallback)",
        visibleRankTexts())
    TEMPLATES.ButtonFrameTemplate = savedTemplate
    if frame:IsShown() then RankBrowser.Toggle() end
    RankBrowser.RebuildUI()
    refetchBrowser()
    if not frame:IsShown() then RankBrowser.Toggle() end
    stage5Reset()
end

-- Check 11: density toggle rebuilds rows, default is today's geometry.
ensureBrowserOpen()
stage5Reset()
do
    check(rows[1] ~= nil and rows[1]:GetHeight() == 26,
        "density toggle rebuilds rows, default is today's geometry (compact half)",
        rows[1] and tostring(rows[1]:GetHeight()))
    local savedCore = namespace.Core
    namespace.Core = { GetSettings = function() return { comfortableRows = true } end }
    if frame:IsShown() then RankBrowser.Toggle() end
    RankBrowser.RebuildUI()
    refetchBrowser()
    if not frame:IsShown() then RankBrowser.Toggle() end
    stage5Reset()
    check(rows[1] ~= nil and rows[1]:GetHeight() == 32,
        "density toggle rebuilds rows, default is today's geometry (comfortable half)",
        rows[1] and tostring(rows[1]:GetHeight()))
    check(rows[1] ~= nil and rows[1].nameText:GetText() == "Aardvark",
        "density toggle rebuilds rows, default is today's geometry (content identical)",
        visibleRankTexts())
    namespace.Core = { GetSettings = function() return { comfortableRows = false } end }
    if frame:IsShown() then RankBrowser.Toggle() end
    RankBrowser.RebuildUI()
    refetchBrowser()
    if not frame:IsShown() then RankBrowser.Toggle() end
    stage5Reset()
    check(rows[1] ~= nil and rows[1]:GetHeight() == 26,
        "density toggle rebuilds rows, default is today's geometry (toggle back)",
        rows[1] and tostring(rows[1]:GetHeight()))
    namespace.Core = savedCore
end

-- Check 13: session revision renders iLvl suffix, persisted renders none.
ensureBrowserOpen()
stage5Reset()
do
    _G.C_Item = {
        GetItemInfo = function(id)
            if id == 12345 then
                return "Mock Helm", "item:12345", 4, 213, 1, 4, 1, 1,
                    "INVTYPE_HEAD", "Interface\\Icons\\Mock", 0, 4, 1
            end
            return nil
        end,
    }
    namespace.Scanner = {
        GetRemote = function(guid)
            if guid == "Player-9-96S" then
                return { revision = { slots = {
                    [1] = { itemID = { value = 12345 } },
                    [5] = { itemID = { value = 99999 } },
                } } }
            end
            return nil
        end,
    }
    check(RankBrowser.ShowGear({ guid = "Player-9-96S", name = "SessionSuffix" }) == true,
        "session revision renders iLvl suffix, persisted renders none (session opens)")
    local sessionJoined = gearPanelText()
    check(sessionJoined ~= nil
        and sessionJoined:find("item:12345", 1, true) ~= nil
        and sessionJoined:find("(213)", 1, true) ~= nil,
        "session revision renders iLvl suffix, persisted renders none (suffix half)",
        tostring(sessionJoined and sessionJoined:sub(1, 200)))
    check(sessionJoined ~= nil
        and sessionJoined:find("item:99999", 1, true) ~= nil
        and sessionJoined:find("(99999)", 1, true) == nil
        and sessionJoined:find("...", 1, true) == nil,
        "session revision renders iLvl suffix, persisted renders none (uncached half)",
        tostring(sessionJoined and sessionJoined:sub(1, 200)))
    namespace.Scanner = nil
    RankDB.StoreGear("Player-9-96P", _G.time() - 3600, "1=777888,16=999000")
    check(RankBrowser.ShowGear({ guid = "Player-9-96P", name = "PersistedPlain" }) == true,
        "session revision renders iLvl suffix, persisted renders none (persisted opens)")
    local persistedJoined = gearPanelText()
    check(persistedJoined ~= nil
        and persistedJoined:find("item:777888", 1, true) ~= nil
        and persistedJoined:find("%(%d+%)") == nil
        and persistedJoined:find("Last synced", 1, true) ~= nil,
        "session revision renders iLvl suffix, persisted renders none (persisted half)",
        tostring(persistedJoined and persistedJoined:sub(1, 200)))
    check(RankBrowser.ShowGear({ guid = "Player-9-96N", name = "NeverGear" }) == true,
        "session revision renders iLvl suffix, persisted renders none (unscanned opens)")
    check(gearPanelText() ~= nil
        and gearPanelText():find("has not been scanned", 1, true) ~= nil,
        "session revision renders iLvl suffix, persisted renders none (unscanned half)",
        tostring(gearPanelText() and gearPanelText():sub(1, 120)))
    _G.C_Item = nil
end

-- Check 14: enhancement dots follow session cells only.
ensureBrowserOpen()
stage5Reset()
do
    namespace.Scanner = {
        GetRemote = function(guid)
            if guid == "Player-9-96E" then
                return { revision = { slots = {
                    [1] = {
                        itemID = { value = 111 },
                        nativeLink = { value = "item:111" },
                        permanentEnchantID = { status = "complete", value = 5678 },
                        sockets = { status = "complete",
                            value = { capacity = 2, gemIDs = { 1111, 2222 } } },
                    },
                    [5] = {
                        itemID = { value = 222 },
                        permanentEnchantID = { status = "complete", value = 0 },
                        sockets = { status = "complete",
                            value = { capacity = 0, gemIDs = {} } },
                    },
                } } }
            end
            return nil
        end,
    }
    check(RankBrowser.ShowGear({ guid = "Player-9-96E", name = "DottedGear" }) == true,
        "enhancement dots follow session cells only (session opens)")
    local panel = findGearPanel()
    check(panel ~= nil and panel.dotEnchant ~= nil and panel.dotSocket ~= nil,
        "enhancement dots follow session cells only (dots exist)",
        type(panel and panel.dotEnchant))
    if panel and panel.dotEnchant and panel.dotSocket then
        check(panel.dotEnchant[1]:IsShown() and panel.dotSocket[1]:IsShown(),
            "enhancement dots follow session cells only (filled half)")
        check(not panel.dotEnchant[5]:IsShown()
            and not panel.dotSocket[5]:IsShown(),
            "enhancement dots follow session cells only (empty half)")
    end
    namespace.Scanner = nil
    RankDB.StoreGear("Player-9-96Q", _G.time() - 100, "1=333222")
    check(RankBrowser.ShowGear({ guid = "Player-9-96Q", name = "PersistedDots" }) == true,
        "enhancement dots follow session cells only (persisted opens)")
    local panel2 = findGearPanel()
    check(panel2 ~= nil
        and not panel2.dotEnchant[1]:IsShown()
        and not panel2.dotSocket[1]:IsShown(),
        "enhancement dots follow session cells only (persisted half)")
end

-- Check 15: D ingest updates the panel without rescan (Stage-4 path guard).
ensureBrowserOpen()
stage5Reset()
do
    RankSync.HandlePayload("D;2;d96;Player-9-96D;" .. (_G.time() - 50)
        .. ";1/1;1=444444,5=555555", "GUILD", "Peer96")
    check(RankBrowser.ShowGear({ guid = "Player-9-96D", name = "DIngested" }) == true,
        "D ingest updates the panel without rescan (opens)")
    local joined = gearPanelText()
    check(joined ~= nil
        and joined:find("item:444444", 1, true) ~= nil
        and joined:find("item:555555", 1, true) ~= nil
        and joined:find("has not been scanned", 1, true) == nil,
        "D ingest updates the panel without rescan (IDs half)",
        tostring(joined and joined:sub(1, 200)))
    check(joined ~= nil
        and joined:find("|cff808080", 1, true) ~= nil
        and joined:find("Last synced", 1, true) ~= nil,
        "D ingest updates the panel without rescan (persisted-leg half)",
        tostring(joined and joined:sub(1, 200)))
end

-- Check 17: no new GetDebugState keys, existing keys enumerate.
--
-- `channel.id` is nil when no channel is joined (this harness never joins),
-- so `pairs` omits it the same way it does on pre-Stage-5 code: absence of a
-- nil-valued key is not a shape change. The load-bearing half is extras --
-- any Stage-5 counter would appear there.
do
    local state = RankSync.GetDebugState()
    local want = {
        outcomes = true, channelState = true, channelId = true,
        channelFailures = true, queueDepth = true, tokenBucket = true,
        selfBroadcastPending = true,
    }
    local extra = nil
    for key in pairs(state) do
        if not want[key] then extra = key break end
    end
    local stableMissing = nil
    for _, key in ipairs({ "outcomes", "channelState", "channelFailures",
        "queueDepth", "tokenBucket", "selfBroadcastPending" }) do
        if state[key] == nil then stableMissing = key break end
    end
    -- Outcomes half: every counted bucket must be one the wire/storage stages
    -- own. A Stage-5 counter (a new display-only failure mode) would surface
    -- here the moment any browser path counts it -- this harness drives all of
    -- them. The set below is the verbatim union of countOutcome literals in
    -- RankSync.lua; anything outside it fails.
    local knownBuckets = {
        answerNoTransport = true, enqueueOversize = true, gearBadGuid = true,
        gearCoalesced = true, gearNoData = true, gearRefused = true,
        gearStale = true, gearStored = true, inboundRateLimited = true,
        probes = true, requeued = true,
        scanForeignRealm = true, selfRebroadcast = true, sendError = true,
        versionReject = true,
    }
    local strangeBucket = nil
    if type(state.outcomes) == "table" then
        for key in pairs(state.outcomes) do
            if not knownBuckets[key] then strangeBucket = key break end
        end
    end
    check(extra == nil and stableMissing == nil and strangeBucket == nil,
        "no new GetDebugState keys, existing keys enumerate",
        "extra=" .. tostring(extra) .. " missing=" .. tostring(stableMissing)
            .. " bucket=" .. tostring(strangeBucket))
end

-- ---------------------------------------------------------------------------
-- 20. Stage 5 slice 5c: keyboard navigation (brief check 9).
--
-- W12 (HybridScrollFrame virtualization) is NOT shipped and has no check
-- here: it is recorded NOT-APPLICABLE in the dispatch message with the Q1
-- evidence (no realm-size measurement shows the fixed-12 FauxScrollFrame list
-- dropping frames; sort cost dominates and is shared either way).
-- ---------------------------------------------------------------------------
ensureBrowserOpen()
stage5Reset()
do
    local realShowGear = RankBrowser.ShowGear
    local shownEntry = "untouched"
    RankBrowser.ShowGear = function(entry)
        shownEntry = entry
        return realShowGear(entry)
    end
    frame.Fire("OnKeyDown", "Down")
    frame.Fire("OnKeyDown", "Enter")
    check(type(shownEntry) == "table"
        and shownEntry.guid == "Player-1-00000001",
        "keyboard Down/Enter opens the focused row's gear (first row)",
        shownEntry ~= "untouched" and tostring(shownEntry.guid))
    frame.Fire("OnKeyDown", "Down")
    frame.Fire("OnKeyDown", "Enter")
    check(type(shownEntry) == "table"
        and shownEntry.guid == "Player-1-00000002",
        "keyboard Down/Enter opens the focused row's gear (second row)",
        shownEntry ~= "untouched" and tostring(shownEntry.guid))
    frame.Fire("OnKeyDown", "Up")
    frame.Fire("OnKeyDown", "Enter")
    check(type(shownEntry) == "table"
        and shownEntry.guid == "Player-1-00000001",
        "keyboard Down/Enter opens the focused row's gear (Up returns)",
        shownEntry ~= "untouched" and tostring(shownEntry.guid))
    -- Empty list: keys no-op, no error, no gear panel.
    shownEntry = "untouched"
    searchBox:SetText("zzzz-no-such-player")
    searchBox.Fire("OnTextChanged", searchBox)
    frame.Fire("OnKeyDown", "Down")
    frame.Fire("OnKeyDown", "Enter")
    check(shownEntry == "untouched",
        "keyboard Down/Enter opens the focused row's gear (empty list no-op)",
        tostring(shownEntry))
    searchBox:SetText("")
    searchBox.Fire("OnTextChanged", searchBox)
    -- Re-sort after focus: the focus re-anchors to the ENTRY, never a stale
    -- row index (index 1 after an iLvl re-sort is Hawthorne, not Aardvark).
    frame.Fire("OnKeyDown", "Down")
    local ilvlHead = headerButton("iLVL")
    check(ilvlHead ~= nil,
        "keyboard Down/Enter opens the focused row's gear (iLVL header present)")
    if ilvlHead then
        ilvlHead.Fire("OnClick")
        frame.Fire("OnKeyDown", "Enter")
        check(type(shownEntry) == "table"
            and shownEntry.guid == "Player-1-00000001",
            "keyboard Down/Enter opens the focused row's gear (survives re-sort)",
            shownEntry ~= "untouched" and tostring(shownEntry.guid))
    end
    RankBrowser.ShowGear = realShowGear
    stage5Reset()
end
-- ---------------------------------------------------------------------------
-- 21. Browser above the Settings canvas; gear panel above the browser rows
-- ---------------------------------------------------------------------------
ensureBrowserOpen()
stage5Reset()
do
    -- Blizzard evidence (Gethe/wow-ui-source): classic_era
    -- Blizzard_GameMenu/Shared/GameMenuFrame.xml is toplevel DIALOG; live
    -- Blizzard_Settings_Shared/Blizzard_SettingsPanel.xml is toplevel HIGH.
    -- One strata above DIALOG wins against both while staying below TOOLTIP.
    check(frame:GetFrameStrata() == "FULLSCREEN_DIALOG",
        "the browser opens above DIALOG settings surfaces (FULLSCREEN_DIALOG)",
        tostring(frame:GetFrameStrata()))
    check(frame:GetFrameLevel() == 100,
        "the browser keeps its documented level",
        tostring(frame:GetFrameLevel()))
    check(frame.__toplevel == true,
        "the browser is toplevel within its strata")

    -- The Toggle show path (not just CreateUI) applies the placement, so a
    -- reopen keeps it too.
    if frame:IsShown() then RankBrowser.Toggle() end
    RankBrowser.Toggle()
    check(frame:IsShown() and frame:GetFrameStrata() == "FULLSCREEN_DIALOG",
        "reopening keeps the browser above the settings surfaces",
        tostring(frame:GetFrameStrata()))

    namespace.Scanner = nil
    check(RankBrowser.ShowGear({ guid = "Player-9-962", name = "NeverScanned" }) == true,
        "gear panel opens for the strata check")
    local panel = findGearPanel()
    check(panel ~= nil, "the gear panel is found under its new parent")
    if panel then
        check(panel:GetParent() == frame,
            "the gear panel is a child of the browser (above the rows by construction)")
        check(panel:GetFrameStrata() == "FULLSCREEN_DIALOG",
            "the gear panel shares the above-settings strata",
            tostring(panel:GetFrameStrata()))
        check(panel:GetFrameLevel() == 200
            and panel:GetFrameLevel() > frame:GetFrameLevel(),
            "the gear panel levels above the browser (200 > 100)",
            tostring(panel:GetFrameLevel()))
        check(panel.__toplevel == true,
            "the gear panel is toplevel within its strata")

        -- The gear panel carries an EXPLICIT backdrop, black at 0.9 alpha:
        -- opaque and readable on all five clients.
        --
        -- The browser frame does NOT use the backdrop API, and that is not a
        -- gap in the browser: ButtonFrameTemplate is not a backdrop template
        -- (its chain's mixins are PortraitFrameMixin /
        -- PortraitFrameTemplateMixin, not BackdropTemplateMixin), so the
        -- `if f.SetBackdrop then` guard skips in the real client too. The
        -- browser's opaque surface is the template's own background texture.
        -- The gear panel has no template of its own, which is exactly why it
        -- used to render TRANSPARENT.
        local browserBD, panelBD = frame.__backdropColor, panel.__backdropColor
        check(type(panelBD) == "table",
            "the gear panel paints an explicit backdrop color",
            "got " .. tostring(panelBD))
        check(browserBD == nil,
            "the browser frame has no backdrop API (ButtonFrameTemplate paints its own background)",
            "browser backdrop colour=" .. tostring(browserBD))
        if type(panelBD) == "table" then
            check(near(panelBD.a, 0.9),
                "the gear panel's backdrop is 0.9 alpha (opaque-readable)",
                "gear=" .. tostring(panelBD.a))
            check(panelBD.r == 0 and panelBD.g == 0 and panelBD.b == 0,
                "the gear panel's backdrop is black")
        end
    end

    -- ---------------------------------------------------------------------------
    -- The gear panel's backdrop, and the environment it is judged in
    -- ---------------------------------------------------------------------------
    --
    -- The bug (operator's Classic Era screenshot): the panel was created as a
    -- PLAIN frame, so the client gave it no SetBackdrop, the
    -- `if f.SetBackdrop then` guard skipped, and the panel rendered
    -- TRANSPARENT with unreadable text.
    --
    -- The environment has to be honest for any of this to mean anything: a
    -- plain frame in the CLIENT has no SetBackdrop, so a plain frame here has
    -- none either. The mock used to hand the whole backdrop API to every
    -- frame, which is how a transparent panel passed as an opaque one.
    do
        local plain = _G.CreateFrame("Frame")
        check(type(plain) == "table" and plain.SetBackdrop == nil,
            "a plain frame in this environment has no SetBackdrop",
            "got " .. type(plain and plain.SetBackdrop))
        check(type(plain.__absent) == "table" and plain.__absent.SetBackdrop == true,
            "the plain frame records the backdrop API as absent",
            tostring(plain.__absent and plain.__absent.SetBackdrop))

        local gear = findGearPanel()
        check(gear ~= nil and type(gear.SetBackdrop) == "function",
            "the gear panel is backdrop-capable",
            "got " .. type(gear and gear.SetBackdrop))
        check(gear ~= nil and type(gear.__backdrop) == "table",
            "the gear panel's backdrop is applied",
            "got " .. type(gear and gear.__backdrop))
        if gear ~= nil and type(gear.__backdrop) == "table" then
            local bd = gear.__backdrop
            check(bd.bgFile == "Interface\\DialogFrame\\UI-DialogBox-Background-Dark"
                    and bd.edgeFile == "Interface\\DialogFrame\\UI-DialogBox-Border"
                    and bd.tile == true,
                "the gear panel paints the dark dialog background and its border",
                tostring(bd.bgFile) .. " / " .. tostring(bd.edgeFile))
        end
        check(gear ~= nil and type(gear.__backdropColor) == "table"
                and near(gear.__backdropColor.a, 0.9)
                and gear.__backdropColor.r == 0
                and gear.__backdropColor.g == 0
                and gear.__backdropColor.b == 0,
            "the gear panel's backdrop is opaque black (0.9 alpha)",
            gear and tostring(gear.__backdropColor and gear.__backdropColor.a))
    end

    -- ---------------------------------------------------------------------------
    -- The window's vertical layout: every band owns its own space
    -- ---------------------------------------------------------------------------
    --
    -- The operator's screenshot showed the window too small, the
    -- "Sorted by GEARSCORE" readout drawn through the column headers and
    -- crowded against the summary strip, the filter row running into the
    -- headers, and the footer crowding the progress rail.
    --
    -- The layout is now a STACK of bands whose offsets are derived from the
    -- frame's own height, and the pins below read the GEOMETRY the window
    -- actually built -- the anchors the module set, not the numbers it
    -- declared -- and check that no two bands share vertical space.
    do
        local gear = findGearPanel()
        local frameHeight = frame:GetHeight() or 0
        check(frame:GetWidth() > 720 and frameHeight > 520,
            "the leaderboard frame is taller and wider than 720x520",
            tostring(frame:GetWidth()) .. "x" .. tostring(frameHeight))
        -- The gear panel keeps its own size: enlarging the window must not
        -- stretch the gear panel with it.
        check(gear ~= nil and gear:GetWidth() == 400 and gear:GetHeight() == 470,
            "the gear panel keeps its own 400x470 size",
            gear and (tostring(gear:GetWidth()) .. "x" .. tostring(gear:GetHeight())))

        -- A widget's vertical range, as distances BELOW the frame's top, read
        -- off the anchor the module actually set. A TOPLEFT anchor gives the
        -- top edge; a BOTTOMLEFT anchor gives the bottom edge.
        local function verticalRange(widget)
            local p = widget and widget.__point
            if type(p) ~= "table" or type(p.y) ~= "number" then
                return nil
            end
            local height = widget:GetHeight() or 0
            if p.point == "BOTTOMLEFT" or p.point == "BOTTOMRIGHT" then
                local bottom = frameHeight - p.y
                return bottom - height, bottom
            end
            local top = -p.y
            return top, top + height
        end

        -- The header row as one band: the union of the header widgets.
        local headerTop, headerBottom
        for _, header in ipairs(frame.headerWidgets or {}) do
            local top, bottom = verticalRange(header)
            if top then
                if not headerTop or top < headerTop then headerTop = top end
                if not headerBottom or bottom > headerBottom then headerBottom = bottom end
            end
        end
        -- The table as one band: the first row's top to the last row's bottom.
        local tableTop, tableBottom
        for _, row in ipairs(rows) do
            local top, bottom = verticalRange(row)
            if top then
                if not tableTop or top < tableTop then tableTop = top end
                if not tableBottom or bottom > tableBottom then tableBottom = bottom end
            end
        end

        local function bandOf(name, widget)
            local top, bottom = verticalRange(widget)
            return { name = name, top = top, bottom = bottom }
        end
        local bands = {
            bandOf("stat strip", frame.statStrip),
            bandOf("sort readout", frame.sortHint),
            { name = "column headers", top = headerTop, bottom = headerBottom },
            { name = "table", top = tableTop, bottom = tableBottom },
            bandOf("progress rail", frame.progressBar),
            bandOf("footer", frame.footerText),
        }
        local measured = 0
        for _, band in ipairs(bands) do
            if band.top then measured = measured + 1 end
        end
        check(measured == #bands,
            "every layout band has a measurable vertical range",
            "measured " .. tostring(measured) .. " of " .. tostring(#bands))

        -- No two bands share vertical space.
        local clashes = {}
        for i = 1, #bands do
            for j = i + 1, #bands do
                local a, b = bands[i], bands[j]
                if a.top and b.top and a.top < b.bottom and b.top < a.bottom then
                    clashes[#clashes + 1] = a.name .. " / " .. b.name
                end
            end
        end
        check(#clashes == 0,
            "no two layout bands share vertical space",
            table.concat(clashes, ", "))

        -- And they are stacked in order, top to bottom: stat strip, sort
        -- readout, column headers, table, progress rail, footer.
        local misordered = {}
        for i = 2, #bands do
            local previous, current = bands[i - 1], bands[i]
            if previous.top and current.top and current.top < previous.bottom then
                misordered[#misordered + 1] = current.name .. " above " .. previous.name
            end
        end
        check(#misordered == 0,
            "the layout bands are stacked in order, top to bottom",
            table.concat(misordered, ", "))

        -- The last table row must not reach the progress rail.
        local railTop = verticalRange(frame.progressBar)
        check(tableBottom ~= nil and railTop ~= nil and tableBottom <= railTop,
            "the last table row does not collide with the progress rail",
            "table bottom=" .. tostring(tableBottom) .. " rail top=" .. tostring(railTop))

        -- The column headers line up with the columns below them: the header
        -- widget's x in the frame must equal the row's own column x.
        --
        -- The order mirrors RankBrowser's COLUMNS table -- the same order the
        -- row's font strings are created in.
        local COLUMN_KEYS = { "rank", "name", "spec", "level", "gs", "ilvl", "seen" }
        local misaligned = {}
        local rowOne = rows[1]
        for index, key in ipairs(COLUMN_KEYS) do
            local header = (frame.headerWidgets or {})[index]
            local column = rowOne and rowOne[key .. "Text"]
            local headerPoint = header and header.__point
            local columnPoint = column and column.__point
            local rowPoint = rowOne and rowOne.__point
            if headerPoint and columnPoint and rowPoint then
                if headerPoint.x ~= rowPoint.x + columnPoint.x then
                    misaligned[#misaligned + 1] = key
                end
            else
                misaligned[#misaligned + 1] = key .. " (unreadable)"
            end
        end
        check(#misaligned == 0,
            "the column headers line up with the columns below them",
            table.concat(misaligned, ", "))

        -- The plain column headers (rank, name, spec) and the sortable ones
        -- (level, GearScore, iLvl, last seen) must share ONE line. The
        -- sortable ones are Buttons whose text is centred in a 20px box; the
        -- plain ones are FontStrings. If the two do not line up, the header
        -- row reads as two misaligned rows.
        local sortableTop, sortableBottom
        for index, key in ipairs(COLUMN_KEYS) do
            if key == "level" or key == "gs" or key == "ilvl" or key == "seen" then
                local top, bottom = verticalRange((frame.headerWidgets or {})[index])
                if top then
                    if not sortableTop or top < sortableTop then sortableTop = top end
                    if not sortableBottom or bottom > sortableBottom then sortableBottom = bottom end
                end
            end
        end
        local offLine = {}
        for index, key in ipairs(COLUMN_KEYS) do
            if key == "rank" or key == "name" or key == "spec" then
                local top, bottom = verticalRange((frame.headerWidgets or {})[index])
                if top and (top < sortableTop or bottom > sortableBottom) then
                    offLine[#offLine + 1] = key
                end
            end
        end
        check(#offLine == 0,
            "the plain column headers share the sortable headers' line",
            table.concat(offLine, ", "))

        -- The row's ICONS are anchored to their column, not to a fixed
        -- offset. The spec icon used to be anchored 246px from the row's left
        -- edge while the spec TEXT began at 232 -- so the icon was drawn ON
        -- TOP of the first characters of the spec name.
        local row = rows[1]
        if row ~= nil and row.specIconTexture and row.specText then
            local iconRight = row.specIconTexture.__point
                and row.specIconTexture.__point.x or nil
            local textLeft = row.specText.__point and row.specText.__point.x or nil
            check(iconRight ~= nil and textLeft ~= nil and iconRight < textLeft,
                "the spec icon is anchored clear of the spec text",
                "icon right=" .. tostring(iconRight) .. " text left=" .. tostring(textLeft))
        end
        if row ~= nil and row.classIconTexture and row.nameText then
            local iconRight = row.classIconTexture.__point
                and row.classIconTexture.__point.x or nil
            local textLeft = row.nameText.__point and row.nameText.__point.x or nil
            check(iconRight ~= nil and textLeft ~= nil and iconRight < textLeft,
                "the class icon is anchored clear of the player name",
                "icon right=" .. tostring(iconRight) .. " text left=" .. tostring(textLeft))
        end
    end

    -- No other shown top-level frame still covers the browser: the sweep sees
    -- every UIParent child the harness models (browser, escape listener; the
    -- gear panel now lives under the browser).
    local STRATA_RANK = {
        BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4,
        DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8,
    }
    local browserRank = STRATA_RANK[frame:GetFrameStrata()] or 0
    local cover = nil
    for _, child in ipairs(childrenOf(_G.UIParent)) do
        if child ~= frame and child ~= panel
            and type(child.IsShown) == "function" and child:IsShown() then
            local childRank = STRATA_RANK[
                (type(child.GetFrameStrata) == "function"
                    and child:GetFrameStrata()) or ""] or 0
            if childRank > browserRank then
                cover = child
            end
        end
    end
    check(cover == nil,
        "no other shown top-level frame covers the browser",
        cover and tostring(cover.__name))
end

-- ---------------------------------------------------------------------------
-- 22. Gear empty state tells the truth; IDs never render as zero
-- ---------------------------------------------------------------------------
ensureBrowserOpen()
stage5Reset()
do
    -- A zero-ID session cell is not an item: it must fall through to the
    -- empty state, never render as "item:0", never fabricate entries.
    namespace.Scanner = {
        GetRemote = function(guid)
            if guid == "Player-9-96Z" then
                return { revision = { slots = {
                    [1] = { itemID = { value = 0 } },
                } } }
            end
            if guid == "Player-9-96W" then
                return { revision = { slots = {
                    [1] = { itemID = { status = "pending" } },
                } } }
            end
            return nil
        end,
    }
    check(RankBrowser.ShowGear({ guid = "Player-9-96Z", name = "ZeroID" }) == true,
        "gear panel opens for a zero-ID session cell")
    local zeroJoined = gearPanelText()
    check(zeroJoined ~= nil
        and zeroJoined:find("item:0", 1, true) == nil,
        "a zero item ID never renders",
        tostring(zeroJoined and zeroJoined:sub(1, 160)))
    check(zeroJoined ~= nil
        and zeroJoined:find("unavailable for this player", 1, true) ~= nil,
        "a session with no renderable gear states unavailability, not blank",
        tostring(zeroJoined and zeroJoined:sub(1, 200)))
    check(zeroJoined ~= nil
        and zeroJoined:find("Scan now", 1, true) ~= nil,
        "the unknown state carries a Scan hint",
        tostring(zeroJoined and zeroJoined:sub(1, 200)))

    -- A pending session cell (scan in flight) is the same unknown state.
    check(RankBrowser.ShowGear({ guid = "Player-9-96W", name = "Pending" }) == true,
        "gear panel opens for a pending session cell")
    local pendingJoined = gearPanelText()
    check(pendingJoined ~= nil
        and pendingJoined:find("unavailable for this player", 1, true) ~= nil
        and pendingJoined:find("Scan now", 1, true) ~= nil,
        "a pending session cell states unavailability with a Scan hint",
        tostring(pendingJoined and pendingJoined:sub(1, 200)))

    -- A persisted "1=0" pair drops at render; the surviving real ID renders
    -- dimmed with its Last-synced note (persisted leg, not unknown).
    RankDB.StoreGear("Player-9-96P0", _G.time() - 100, "1=0,5=444001")
    check(RankBrowser.ShowGear({ guid = "Player-9-96P0", name = "PersistedZero" }) == true,
        "gear panel opens for persisted gear containing a zero pair")
    local persistedJoined = gearPanelText()
    check(persistedJoined ~= nil
        and persistedJoined:find("item:0", 1, true) == nil,
        "a persisted zero ID never renders",
        tostring(persistedJoined and persistedJoined:sub(1, 160)))
    check(persistedJoined ~= nil
        and persistedJoined:find("item:444001", 1, true) ~= nil
        and persistedJoined:find("Last synced", 1, true) ~= nil,
        "the surviving persisted ID renders with its age note",
        tostring(persistedJoined and persistedJoined:sub(1, 200)))
    namespace.Scanner = nil

    -- The never-scanned text is unchanged (older sections own the exact
    -- string; re-asserted so this section stands alone).
    check(RankBrowser.ShowGear({ guid = "Player-9-96N", name = "NeverEver" }) == true,
        "gear panel opens for a never-scanned player")
    check(gearPanelText() ~= nil
        and gearPanelText():find("has not been scanned", 1, true) ~= nil,
        "a never-scanned player keeps the not-scanned note",
        tostring(gearPanelText() and gearPanelText():sub(1, 120)))
end

-- ---------------------------------------------------------------------------
-- 23. Browser grade color uses the per-client tooltip bracket (Era 200)
-- ---------------------------------------------------------------------------
ensureBrowserOpen()
stage5Reset()
do
    -- Hand derivation from main-addon gearscore.lua (BRACKET_SIZE = 200 on
    -- Era, GS_Quality bands (i*200, (i+1)*200], MAX_SCORE = 1400):
    --   1400 -> (1200, 1400], 7th band, Artifact (0.92, 0.10, 0.10)
    --    690 -> (600, 800], 4th band, Superior (0.12, 0.40, 0.83)
    -- The same 1400 in the TBC 400 domain is (1200, 1600], 4th band, Superior
    -- blue (0.12, 0.40, 0.83) -- same band index, different domain: the
    -- routing is per-client, not a constant.
    local BANDS = {
        { 0.50, 0.50, 0.50 }, { 1.00, 1.00, 1.00 }, { 0.12, 0.81, 0.04 },
        { 0.12, 0.40, 0.83 }, { 0.63, 0.20, 0.83 }, { 1.00, 0.63, 0.00 },
        { 0.92, 0.10, 0.10 },
    }
    local function qualityWith(bracket)
        return function(score)
            local s = tonumber(score) or 0
            local max = bracket * 7
            if s > max then s = max end
            for i = 0, 6 do
                if s > i * bracket and s <= (i + 1) * bracket then
                    local band = BANDS[i + 1]
                    return band[1], band[2], band[3]
                end
            end
            return 0.50, 0.50, 0.50
        end
    end

    RankDB.StoreRecord({
        guid = "Player-9-961400", name = "EraWhale", faction = "Alliance",
        class = "WARRIOR", gs = 1400, ilvl = 60, timestamp = now - 10,
    })
    namespace.TacoTipAdapter = {
        GetEquipmentScoreColor = qualityWith(200),
    }
    RankBrowser.ScrollToTop()
    check(rows[1] and rows[1].nameText:GetText() == "EraWhale",
        "the seeded 1400 entry leads the board",
        rows[1] and rows[1].nameText:GetText())
    do
        local r, g, b = colorOf(rows[1].gsText)
        check(near(r, 0.92) and near(g, 0.10) and near(b, 0.10),
            "1400 on Era grades Artifact red (200 domain, 7th band)",
            "got " .. tostring(r) .. "," .. tostring(g) .. "," .. tostring(b))
    end
    do
        -- Aardvark (690) sits two rows down in second place behind the whale.
        local second = rows[2]
        check(second and second.gsText:GetText() == "690",
            "the second row is the 690 entry",
            second and second.gsText:GetText())
        if second then
            local r, g, b = colorOf(second.gsText)
            check(near(r, 0.12) and near(g, 0.40) and near(b, 0.83),
                "690 on Era grades Superior blue (200 domain, 4th band)",
                "got " .. tostring(r) .. "," .. tostring(g) .. "," .. tostring(b))
        end
    end

    namespace.TacoTipAdapter = {
        GetEquipmentScoreColor = qualityWith(400),
    }
    RankBrowser.UpdateUI()
    do
        local r, g, b = colorOf(rows[1].gsText)
        check(near(r, 0.12) and near(g, 0.40) and near(b, 0.83),
            "1400 on TBC grades Superior blue (400 domain, 4th band)",
            "got " .. tostring(r) .. "," .. tostring(g) .. "," .. tostring(b))
    end

    -- No adapter (offline harness, incompatible TacoTip): the relative
    -- view-best scale is unchanged, so every earlier fixture holds as-is.
    namespace.TacoTipAdapter = nil
    RankBrowser.ScrollToTop()
    do
        local r, g, b = colorOf(rows[1].gsText)
        check(near(r, 0.64) and near(g, 0.21) and near(b, 0.93),
            "without an adapter the relative view-best scale is unchanged",
            "got " .. tostring(r) .. "," .. tostring(g) .. "," .. tostring(b))
    end
end

-- ---------------------------------------------------------------------------
-- A name that carries WoW markup renders as text, never as colour
-- ---------------------------------------------------------------------------
--
-- The wire carries a remote player's name and guild. A FontString renders
-- `|cff00ff00` as a colour, so a name that carried one could repaint
-- another player's leaderboard row, their row tooltip and their gear-panel
-- title -- the row's own class colour included. The stored text is
-- sanitised, so no escape character ever reaches a FontString.
--
-- Revert map: use sanitizeString instead of sanitizeDisplayString for the
-- name and the guild in RankDB.lua -> the stored name keeps its escape
-- character and the rendered row carries a colour escape again.
do
    local injected = "|cff00ff00"
    local spoofGuid = "Player-9-980"
    RankDB.StoreRecord({
        guid = spoofGuid,
        name = "Spoof" .. injected .. "er",
        class = "MAGE", classID = 8, gs = 123, ilvl = 45,
        guild = "Evil" .. injected .. "Guild",
        timestamp = now - 1,
    })
    local stored = RankDB.GetRecord(spoofGuid)
    check(stored ~= nil and type(stored.name) == "string"
        and stored.name:find("|", 1, true) == nil,
        "a name carrying WoW markup is stored without the escape character",
        "name=" .. tostring(stored and stored.name))
    check(stored ~= nil and type(stored.guild) == "string"
        and stored.guild:find("|", 1, true) == nil,
        "a guild carrying WoW markup is stored without the escape character",
        "guild=" .. tostring(stored and stored.guild))

    -- The RENDER: the row, the row tooltip and the gear panel title are the
    -- three surfaces a remote name reaches.
    searchBox:SetText("Spoof")
    searchBox.Fire("OnTextChanged", searchBox)
    local spoofRow = rows[1]
    local rowText = spoofRow and spoofRow.nameText:GetText() or ""
    check(spoofRow ~= nil and spoofRow.entry ~= nil
        and spoofRow.entry.guid == spoofGuid,
        "the spoofed record reaches the leaderboard",
        "row=" .. tostring(rowText))
    check(rowText:find("|", 1, true) == nil,
        "the leaderboard row cannot carry a colour escape",
        "row=" .. tostring(rowText))
    check(rowText == "Spoofer",
        "the leaderboard row shows the name as plain text",
        "row=" .. tostring(rowText))

    if spoofRow then
        spoofRow.Fire("OnEnter")
        -- The add-on's own rows carry ITS colour codes, so the check is on
        -- the two lines the remote name reaches: the name line and the
        -- guild line. Neither may carry an escape character.
        local nameLine = tooltipLines[1] or ""
        local guildLine = ""
        for _, line in ipairs(tooltipLines) do
            if type(line) == "string" and line:find("Evil", 1, true) ~= nil then
                guildLine = line
            end
        end
        check(nameLine == "Spoofer" and nameLine:find("|", 1, true) == nil,
            "the row tooltip shows the name as plain text",
            "line=" .. tostring(nameLine))
        check(guildLine ~= "" and guildLine:find("|", 1, true) == nil,
            "the row tooltip shows the guild as plain text",
            "line=" .. tostring(guildLine))
        spoofRow.Fire("OnLeave")
    end

    check(RankBrowser.ShowGear({ guid = spoofGuid, name = stored and stored.name }) == true,
        "the gear panel opens for the spoofed record")
    local gearJoined = gearPanelText() or ""
    -- The title is the panel's first font string; the rows that follow carry
    -- the add-on's own colour codes, so the title is read on its own.
    local gearTitle = gearJoined:match("^([^|]*)") or ""
    check(gearTitle:find("Spoofer", 1, true) ~= nil
        and gearTitle:find("|", 1, true) == nil,
        "the gear panel title cannot carry a colour escape",
        "title=" .. tostring(gearTitle))

    searchBox:SetText("")
    searchBox.Fire("OnTextChanged", searchBox)
    RankBrowser.ScrollToTop()
end

-- ---------------------------------------------------------------------------
-- 17. Final silent-failure audit: the gear panel, the footer buttons and the
--     missing database
-- ---------------------------------------------------------------------------
--
-- Three findings of the final silent-failure audit, all about the browser
-- window.
--
-- (a) The gear panel is closed WITH the browser. The panel is a TOPLEVEL
--     child of the browser, so the engine would hide it with its parent --
--     but the add-on does not depend on that rule: the browser's hide branch
--     closes the panel EXPLICITLY. Before the fix, RankBrowser.CloseGear had
--     NO callers at all.
--
-- (b) A rebuild hides the panel before the frame swap and re-renders it
--     afterwards, so the panel is never on screen carrying the rows it drew
--     for the frame that was just discarded.
--
-- (c) The footer's two buttons must not share pixels: "Top" (80 wide) used
--     to sit at 122px from the right edge and "My Rank" (90 wide) at 34px,
--     which left a 2px overlap.
--
-- (d) A missing rank database must not leave a bare window: headers, an
--     empty table and no explanation read as a broken leaderboard.

-- (a) The gear panel closes with the browser.
do
    local panel = findGearPanel()
    if panel == nil then
        -- The panel has not been created yet in this run; open it once.
        RankBrowser.ShowGear({ guid = "Player-9-970", name = "PanelClose" })
        panel = findGearPanel()
    end
    check(panel ~= nil, "the gear panel exists", tostring(panel))

    -- The browser has to be OPEN for the toggle to take its hide branch.
    local current = RankBrowser.CreateUI()
    if current and not current:IsShown() then
        RankBrowser.Toggle()
    end
    check(current and current:IsShown() == true,
        "the browser is open before the gear-panel close test")

    check(RankBrowser.ShowGear({ guid = "Player-9-970", name = "PanelClose" }) == true,
        "the gear panel opens for the close test")
    check(panel and panel:IsShown() == true,
        "the gear panel is showing before the browser closes")

    RankBrowser.Toggle()
    check(current and current:IsShown() == false,
        "the browser is closed")
    check(panel and panel:IsShown() == false,
        "closing the browser closes the gear panel with it",
        "panel shown=" .. tostring(panel and panel:IsShown()))

    -- Put the browser back the way the rest of the suite expects it.
    RankBrowser.Toggle()
end

-- (b) A rebuild leaves no panel showing stale gear.
do
    local current = RankBrowser.CreateUI()
    if current and not current:IsShown() then
        RankBrowser.Toggle()
    end
    -- A player with PERSISTED gear: the panel renders the stored item ids.
    RankDB.StoreGear("Player-9-971", now - 120, "1=111222")
    check(RankBrowser.ShowGear({ guid = "Player-9-971", name = "StaleCheck" }) == true,
        "the gear panel opens on the persisted-gear entry")
    local panel = findGearPanel()
    check(panel ~= nil and panel:IsShown() == true,
        "the gear panel is showing before the rebuild")
    local before = gearPanelText() or ""
    check(before:find("item:111222", 1, true) ~= nil,
        "the panel shows the persisted item before the rebuild", before)

    -- The stored gear changes, then the browser is rebuilt. A panel left
    -- alone across the rebuild would still show the OLD item.
    RankDB.StoreGear("Player-9-971", now - 60, "1=333444")
    local rebuilt = RankBrowser.RebuildUI()
    check(rebuilt ~= nil, "the rebuild produced a browser frame")

    local after = gearPanelText() or ""
    check(after:find("item:333444", 1, true) ~= nil,
        "the rebuilt panel shows the CURRENT item", after)
    check(after:find("item:111222", 1, true) == nil,
        "the rebuilt panel does not show stale gear", after)
    local panelAfter = findGearPanel()
    check(panelAfter ~= nil and panelAfter:IsShown() == true,
        "the gear panel is still open after the rebuild (it was re-rendered)")
    check(panelAfter ~= nil and panelAfter:GetParent() == rebuilt,
        "the gear panel belongs to the NEW browser frame after the rebuild",
        "parent=" .. tostring(panelAfter and panelAfter:GetParent()))
end

-- (c) The two footer buttons must not overlap.
do
    local current = RankBrowser.CreateUI()
    local top, me
    for _, child in ipairs(childrenOf(current, "Button")) do
        local label = child:GetText()
        if type(label) == "string" then
            if label:find("Top", 1, true) ~= nil then
                top = child
            elseif label:find("My Rank", 1, true) ~= nil then
                me = child
            end
        end
    end
    check(top ~= nil and me ~= nil,
        "the footer's Top and My Rank buttons exist",
        "top=" .. tostring(top) .. " me=" .. tostring(me))

    if top and me then
        -- The span of a button measured LEFTWARDS from the frame's right
        -- edge: the button's BOTTOMRIGHT is anchored x pixels to the left of
        -- the frame's BOTTOMRIGHT (so x is negative), and the button is
        -- `width` wide.
        local function span(button)
            local _, _, _, x = button:GetPoint()
            local width = button:GetWidth()
            local fromRight = -x
            return fromRight, fromRight + width
        end
        local topNear, topFar = span(top)
        local meNear, meFar = span(me)
        local overlap = topNear < meFar and meNear < topFar
        check(overlap == false,
            "the two footer buttons' hit rects do not overlap",
            ("top=[%s,%s] me=[%s,%s]"):format(
                tostring(topNear), tostring(topFar),
                tostring(meNear), tostring(meFar)))
        check(topNear >= meFar,
            "the two footer buttons have a gutter between them",
            ("top=%s meFar=%s"):format(tostring(topNear), tostring(meFar)))
    end
end

-- (d) A missing rank database shows the empty state, not a bare window.
do
    local current = RankBrowser.CreateUI()
    if current and not current:IsShown() then
        RankBrowser.Toggle()
    end
    local state = current and current.emptyStateText
    check(state ~= nil, "the browser carries an empty-state line", tostring(state))
    if state then
        -- Start from a KNOWN state: the empty state is hidden, so a check
        -- that it appears afterwards can only be satisfied by the missing
        -- database publishing it.
        state:Hide()
        local savedDB = namespace.RankDB
        namespace.RankDB = {}
        local ok = pcall(RankBrowser.UpdateUI)
        namespace.RankDB = savedDB
        check(ok == true, "UpdateUI survives a missing rank database")
        check(state:IsShown() == true,
            "a missing rank database shows the empty state rather than a bare window",
            "shown=" .. tostring(state:IsShown()))
        check(state:GetText():find("rank database is unavailable", 1, true) ~= nil,
            "the empty state names the missing rank database",
            state:GetText())
        -- The window goes back to its normal state.
        state:Hide()
        pcall(RankBrowser.UpdateUI)
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
    local passBefore, failBefore = PASS, FAIL
    local failuresBefore = #failures
    local captured = {}
    local savedOut = out
    out = function(line) captured[#captured + 1] = tostring(line) end
    -- pcall'd: with the guard ABSENT this call does not merely pass -- it
    -- concatenates a boolean label and raises. The probe must survive that so
    -- the pin can report the difference instead of taking the harness down
    -- with it.
    local probeOK, returned = pcall(check, "deliberately swapped check() call", true)
    out = savedOut
    local loud = table.concat(captured, "\n"):find("SWAPPED CHECK ARGUMENTS", 1, true) ~= nil
    local wasRecorded = (#failures == failuresBefore + 1)
    local wasNotPassed = (PASS == passBefore and FAIL == failBefore + 1)
    -- Undo the deliberate failure: the point being proven is that a swapped
    -- call is rejected, not that this harness should fail.
    for i = #failures, failuresBefore + 1, -1 do failures[i] = nil end
    PASS, FAIL = passBefore, failBefore
    check(probeOK == true and returned == false and wasRecorded and wasNotPassed and loud,
        "a swapped check(condition, label) call is rejected loudly, never counted as a pass",
        "probeOK=" .. tostring(probeOK) .. " returned=" .. tostring(returned)
            .. " recorded=" .. tostring(wasRecorded)
            .. " notPassed=" .. tostring(wasNotPassed) .. " loud=" .. tostring(loud))
end

out(("%d checks, %d failed"):format(PASS + FAIL, FAIL))
for _, f in ipairs(failures) do
    out("  failed: " .. f)
end

if FAIL > 0 then
    os.exit(1)
end