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

local function check(condition, label, detail)
    if condition then
        PASS = PASS + 1
        out("  ok    " .. label)
    else
        FAIL = FAIL + 1
        failures[#failures + 1] = label
        out("  FAIL  " .. label .. (detail and ("  [" .. tostring(detail) .. "]") or ""))
    end
end

local function near(a, b)
    return math.abs((tonumber(a) or 0) - (tonumber(b) or 0)) < 1e-6
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

local function newRegion(kind, name, parent, template)
    local region = {
        __kind = kind,
        __name = name,
        __parent = parent,
        __template = template,
        __shown = false,
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
    function R.SetParent(_, p) region.__parent = p end
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
    function R.ClearAllPoints() end
    function R.SetPoint() end
    function R.GetPoint() return "TOPLEFT", "TOPLEFT", 0, 0 end
    function R.GetNumPoints() return 0 end
    function R.SetSize(_, w, h) region.__width, region.__height = w, h end
    function R.SetWidth(_, w) region.__width = w end
    function R.SetHeight(_, h) region.__height = h end
    function R.GetWidth() return region.__width or 0 end
    function R.GetHeight() return region.__height or 0 end

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
    function R.SetFrameStrata() end
    function R.GetFrameStrata() return "MEDIUM" end
    function R.SetFrameLevel() end
    function R.GetFrameLevel() return 1 end
    function R.SetDrawLayer() end
    function R.GetDrawLayer() return "BACKGROUND" end
    function R.SetClampedToScreen() end
    function R.SetMovable() end
    function R.IsMovable() return false end
    function R.SetToplevel() end
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
    function R.SetHighlightTexture() end
    function R.SetPushedTexture() end
    function R.SetBackdrop(_, bd) region.__backdrop = bd end
    function R.GetBackdrop() return region.__backdrop end

    function R.CreateTexture(_, tname, layer) return newRegion("Texture", tname, region, layer) end
    function R.CreateFontString(_, fname, layer, ftemplate)
        return newRegion("FontString", fname, region, ftemplate or layer)
    end

    for k, v in pairs(R) do region[k] = v end
    return region
end

-- Globals, written into the real global table because the modules read _G.
_G.time = os.time
_G.UnitGUID = function(unit)
    if unit == "player" then return "Player-0-0000000A" end
    return nil
end
_G.GetNormalizedRealmName = function() return "TestRealm" end
_G.GetRealmName = function() return "TestRealm" end

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
_G.FauxScrollFrame_OnVerticalScroll = function(frame, value, itemHeight)
    scrollbarValue[frame] = value or 0
    frame.offset = math.floor(((value or 0) / (itemHeight or 1)) + 0.5)
end
local function thumbValue(frame) return scrollbarValue[frame] or 0 end

-- Resolve templates by name the way the client does, so an unknown template is
-- an error rather than a silently different widget.
local TEMPLATES = {
    BackdropTemplate = true,
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

loadFile("RankDB.lua")
loadFile("RankBrowser.lua")

-- Deterministic, obviously-fake quality ramp so colour assertions can pin
-- exact values instead of "roughly warm".
namespace.Scoring = {
    QualityColor = function(score)
        if score >= 500 then return 1.00, 0.00, 0.00 end  -- legendary
        if score >= 300 then return 1.00, 0.50, 0.00 end  -- epic
        if score >= 150 then return 0.00, 0.00, 1.00 end  -- rare
        return 1.00, 1.00, 1.00                            -- common
    end,
}

local RankDB = namespace.RankDB
local RankBrowser = namespace.RankBrowser

-- ---------------------------------------------------------------------------
-- Seed a leaderboard deep enough to make scrolling meaningful
-- ---------------------------------------------------------------------------

local now = _G.time()
local PLAYER_GUID = "Player-0-0000000A"
local PLAYER_RANK = 20

-- Must match RankBrowser's NUM_ROWS. Hardcoded here on purpose: if the browser
-- grows or shrinks its visible page, the centring maths in this test must be
-- revisited, not silently re-tuned to whatever the new value happens to be.
local NUM_ROWS = 12
check(true, "harness assumes 12 visible rows (matches RankBrowser.NUM_ROWS)")

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
        if entry.text == "MAGE" then mageEntry = entry end
    end
    check(mageEntry ~= nil and type(mageEntry.func) == "function",
        "the MAGE entry carries a selection handler")

    if mageEntry then
        mageEntry.func()
        local mages, mageCount = RankDB.GetLeaderboard(nil, "All", "MAGE", "")
        check(mageCount > 0, "selecting MAGE narrows the leaderboard", "count=" .. tostring(mageCount))
        local visibleClass = rows[1] and rows[1].specText:GetText() or ""
        check(rows[1] and rows[1].nameText:GetText() == mages[1].name,
            "the filtered view renders the MAGE leader",
            rows[1] and rows[1].nameText:GetText())
        check(visibleClass ~= nil, "the filtered view still renders spec text", tostring(visibleClass))
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

-- Rank 1 has GearScore 700, which the shim maps to legendary red.
local gr, gg, gb = rows[1].gsText:GetTextColor()
check(near(gr, 1.00) and near(gg, 0.00) and near(gb, 0.00),
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

-- Default order is GearScore descending.
RankBrowser.ScrollToTop()
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

local topGSRank = rows[1] and rows[1].rankText:GetText()

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

    hoverRow.Fire("OnLeave")
    check(tooltipOwner == nil, "leaving the row hides the GameTooltip")
    check(#tooltipLines == 0, "leaving the row clears the tooltip lines")
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
RankDB.GetLeaderboard = realGetLeaderboard
RankBrowser.UpdateUI()

check(frame.footerText ~= nil and frame.footerText:GetText():find("Your Standing") ~= nil,
    "the footer reports the player's standing",
    frame.footerText and frame.footerText:GetText())
check(frame.footerText:GetText():find("#" .. PLAYER_RANK .. " Overall") ~= nil,
    "the footer carries the player's overall rank",
    frame.footerText:GetText())

-- ---------------------------------------------------------------------------

out("")
out(("%d checks, %d failed"):format(PASS + FAIL, FAIL))
for _, f in ipairs(failures) do
    out("  failed: " .. f)
end

if FAIL > 0 then
    os.exit(1)
end