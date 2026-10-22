local _, namespace = ...

if type(namespace) ~= "table" then
    return
end

local RankBrowser = {}
namespace.RankBrowser = RankBrowser

-- Bound at file scope. TacoExtrasApplyLocale MUTATES this table rather than
-- replacing it, so the reference stays live across a language change.
--
-- The COLUMNS and SORTS tables below store locale KEYS rather than display text
-- because they are built at load time, before a language can change. Everything
-- that reads them resolves through L at render time.
local L = _G.TACOEXTRAS_LOCALE or {}

-- ---------------------------------------------------------------------------
-- Layout constants
-- ---------------------------------------------------------------------------

local NUM_ROWS = 16
local ROW_HEIGHT = 26
-- The leaderboard window is bigger than it was, at the operator's request (a
-- Classic Era test session): the window was too small for the text it carries,
-- and the list had to be scrolled to reach the players who matter.
local FRAME_WIDTH = 900
local ROW_WIDTH = 820
local ROW_LEFT = 18

-- The window's vertical layout is a STACK of BANDS, and every band owns its
-- own vertical space. The frame's height is the SUM of the bands, and the
-- band offsets are derived from that same sum by walking back up the stack --
-- so the two are the same number by construction, and a change to the frame's
-- size (or to the number of rows) can never put two bands on top of each
-- other.
--
--   title      the window title
--   filter     scope label, class filter, guild box, search box
--   stat       the summary strip: pool size, top GS, average GS
--   hint       the sort readout, on a line of its own
--   header     the column headers
--   table      the rows
--   progress   the scan progress rail and its completion line
--   footer     the standing line, Top / My Rank / Scan now
--
-- The old layout gave the sort readout a y of `rowTop() + 26`, which is the y
-- the sortable column-header buttons occupy, so it was drawn straight through
-- the header row; the stat strip sat two pixels above it, and the filter row
-- ran into the headers. Each of those was a band with no space of its own.
local BAND_TITLE    = 34
local BAND_FILTER   = 30
local BAND_STAT     = 18
local BAND_HINT     = 18
local BAND_HEADER   = 24
local BAND_PROGRESS = 32
local BAND_FOOTER   = 30
local BAND_PADDING  = 10
-- The rail that shares the progress band with the completion line that
-- appears above it when a scan ends.
local PROGRESS_BAR_HEIGHT = 12

local BRAND_R, BRAND_G, BRAND_B = 0.60, 0.46, 0.82
local MUTED_R, MUTED_G, MUTED_B = 0.62, 0.62, 0.66
local TEXT_R, TEXT_G, TEXT_B = 0.90, 0.90, 0.92

-- Always-on-top placement. Live defect on Classic Era: the browser opened
-- BEHIND the Settings menu (and its gear panel opened behind the browser).
--
-- Evidence (Gethe/wow-ui-source mirror), verified on ALL FIVE branches:
--   origin/classic_era          Interface/AddOns/Blizzard_GameMenu/Shared/GameMenuFrame.xml:4
--   origin/classic_anniversary  Interface/AddOns/Blizzard_GameMenu/Shared/GameMenuFrame.xml:4
--   origin/classic_titan        Interface/AddOns/Blizzard_GameMenu/Shared/GameMenuFrame.xml:4
--   origin/live                 Interface/AddOns/Blizzard_GameMenu/Shared/GameMenuFrame.xml:4
--   origin/forever              Interface/AddOns/Blizzard_GameMenu/Shared/GameMenuFrame.xml:7
-- each declares <Frame name="GameMenuFrame" ... toplevel="true" frameStrata="DIALOG">.
-- And:
--   origin/classic_era          Interface/AddOns/Blizzard_Settings_Shared/Blizzard_SettingsPanel.xml:4
--   origin/classic_anniversary  Interface/AddOns/Blizzard_Settings_Shared/Blizzard_SettingsPanel.xml:4
--   origin/classic_titan        Interface/AddOns/Blizzard_Settings_Shared/Blizzard_SettingsPanel.xml:4
--   origin/forever              Interface/AddOns/Blizzard_Settings_Shared/Blizzard_SettingsPanel.xml:4
--   origin/live                 Interface/AddOns/Blizzard_Settings_Shared/Blizzard_SettingsPanel.xml:4
-- each declares <Frame name="SettingsPanel" ... toplevel="true" ... frameStrata="HIGH">.
-- So the ordering chain is DIALOG < HIGH < FULLSCREEN_DIALOG < TOOLTIP: the browser
-- and its gear panel sit one strata above DIALOG (which beats both offenders)
-- while staying below TOOLTIP (row hover tooltips still render above).
--
-- Hunter L-NEW3 (traceability): the levels are headroom, not magic.
-- BROWSER_LEVEL 100 sits comfortably above any Blizzard content sharing
-- FULLSCREEN_DIALOG (mirrors the main addon's 0..100 frame-level clamp,
-- where 100 is "comfortably above the deepest Blizzard panel"); GEAR_LEVEL
-- 200 keeps the gear panel -- a CHILD of the browser -- above the browser's
-- own rows at every level the rows can take. PANEL_BACKDROP_ALPHA 0.9 is
-- the legibility choice (near-opaque dark backdrop, readable on all five
-- clients; verified in the publish re-audit trace, browser-over-Settings
-- leg). The gear panel is a CHILD of the browser (same strata, higher
-- level) so it can never slip behind the rows again.
local BROWSER_STRATA = "FULLSCREEN_DIALOG"
local BROWSER_LEVEL = 100
local GEAR_STRATA = "FULLSCREEN_DIALOG"
local GEAR_LEVEL = 200

-- Panel backdrop alpha, one value for both panels so they match exactly.
-- Browser and gear both paint Interface\DialogFrame\UI-DialogBox-Background-Dark
-- at 0.9 black: opaque-readable on all five clients.
local PANEL_BACKDROP_ALPHA = 0.9

-- The gear panel's geometry, in ONE place.
--
-- The panel's rows and the two enhancement dots on each row used to carry the
-- same arithmetic written out twice -- "-46 - (index - 1) * 22" for the row
-- and again, twelve lines below, for the dots -- and the panel's own sizes
-- were literal numbers in the middle of the construction. A change to the
-- row pitch had to be made in two places, and one of them could be missed.
--
-- Every value here is the SAME number the literals were. This is a rename, not
-- a redraw: the panel is pixel-identical.
local GEAR_PANEL_WIDTH = 400
local GEAR_PANEL_HEIGHT = 470

-- The row block: left inset from the panel's left edge, the first row's
-- distance DOWN from the panel's top edge, and the pitch between rows.
local GEAR_ROW_LEFT = 18
local GEAR_ROW_TOP = 46
local GEAR_ROW_STEP = 22
local GEAR_ROW_WIDTH = 318

-- The two enhancement dots on each row (enchant, then sockets): their x
-- offsets from the panel's left edge, their size, and how far they hang
-- BELOW the row they belong to.
local GEAR_DOT_ENCHANT_X = 344
local GEAR_DOT_SOCKET_X = 356
local GEAR_DOT_SIZE = 8
local GEAR_DOT_DROP = 7

-- The note under the rows.
local GEAR_NOTE_WIDTH = 360
local GEAR_NOTE_LEFT = 18
local GEAR_NOTE_BOTTOM = 16

-- The y of a slot row, relative to the panel's top edge (negative is DOWN).
--
-- ONE function for the rows and the dots, so the two can never disagree about
-- where a row is.
local function gearRowTop(index)
    return -(GEAR_ROW_TOP + (index - 1) * GEAR_ROW_STEP)
end

-- Column geometry, shared by the row renderer and the header strip so the two
-- can never drift apart. x is the offset from the row's left edge; numeric
-- columns are LEFT-anchored with a RIGHT justify so their digits line up.
-- Columns. `label` is a LOCALE KEY and `fallback` is the English text.
--
-- The key alone is not enough: `L[key] or key` renders the literal string
-- "LB_COL_GS" when the locale table is missing, which is exactly what a test
-- harness that loads this file without Locale/ gets. The fallback keeps the
-- header readable in that case and in game.
local COLUMNS = {
    { key = "rank", x = 8, width = 40, justify = "LEFT", label = "LB_COL_RANK", fallback = "RANK", template = "GameFontHighlightSmall" },
    { key = "name", x = 56, width = 232, justify = "LEFT", label = "LB_COL_PLAYER", fallback = "PLAYER", template = "GameFontNormal" },
    { key = "spec", x = 296, width = 184, justify = "LEFT", label = "LB_COL_SPECCLASS", fallback = "SPEC / CLASS", template = "GameFontHighlightSmall" },
    { key = "level", x = 488, width = 40, justify = "RIGHT", label = "LB_COL_LEVEL", fallback = "LEVEL", template = "GameFontHighlightSmall" },
    { key = "gs", x = 536, width = 70, justify = "RIGHT", label = "LB_COL_GS", fallback = "GEARSCORE", template = "GameFontHighlight" },
    { key = "ilvl", x = 614, width = 58, justify = "RIGHT", label = "LB_COL_ILVL", fallback = "iLVL", template = "GameFontHighlightSmall" },
    { key = "seen", x = 680, width = 76, justify = "RIGHT", label = "LB_COL_LASTSEEN", fallback = "LAST SEEN", template = "GameFontDisableSmall" },
}

-- Column lookup by key, so the row's ICONS are placed relative to the column
-- they belong to instead of to a hardcoded offset.
--
-- The spec icon used to be anchored 246px from the row's left edge while the
-- spec TEXT began at 232 -- so the icon was drawn ON TOP of the first
-- characters of the spec name. Deriving the icon's anchor from the column
-- table makes that overlap impossible, and keeps it impossible when the
-- columns are resized again.
local COLUMN_BY_KEY = {}
for _, col in ipairs(COLUMNS) do
    COLUMN_BY_KEY[col.key] = col
end

-- The gap between a column's text and the icon that belongs to it.
local ICON_GAP = 8

local CLASS_COLORS = {
    ["WARRIOR"] = { 0.78, 0.61, 0.43 },
    ["PALADIN"] = { 0.96, 0.55, 0.73 },
    ["HUNTER"] = { 0.67, 0.83, 0.45 },
    ["ROGUE"] = { 1.00, 0.96, 0.41 },
    ["PRIEST"] = { 1.00, 1.00, 1.00 },
    ["DEATHKNIGHT"] = { 0.77, 0.12, 0.23 },
    ["SHAMAN"] = { 0.00, 0.44, 0.87 },
    ["MAGE"] = { 0.41, 0.80, 0.94 },
    ["WARLOCK"] = { 0.58, 0.51, 0.79 },
    ["MONK"] = { 0.00, 1.00, 0.59 },
    ["DRUID"] = { 1.00, 0.49, 0.04 },
    ["DEMONHUNTER"] = { 0.64, 0.19, 0.79 },
    ["EVOKER"] = { 0.20, 0.58, 0.50 },
}
local DEFAULT_CLASS_COLOR = { 0.80, 0.80, 0.80 }

-- Fixed, deterministic class order for the filter dropdown so the list never
-- depends on whatever happens to be in the database.
local CLASS_ORDER = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
    "SHAMAN", "MAGE", "WARLOCK", "DRUID",
    "DEATHKNIGHT", "MONK", "DEMONHUNTER", "EVOKER",
}

-- The leaderboard is whole-realm: there is no faction scope, so `currentTab`
-- is gone. Filtering is by class, by search text, and (Stage 3) by guild
-- substring -- all three compose in RankDB.GetLeaderboard.
local currentClass = "ALL"
local currentSearch = ""
local currentGuild = ""

local jumpToPlayerPending = false

local rankFrame = nil
local escapeFrame = nil
local rowFrames = {}
local tabHighlight = nil
local classFilterButton = nil
local emptyStateText = nil
local sortHint = nil
local statStrip = nil -- W6 summary strip (realm-at-a-glance header)

-- Stage 5 layout inputs, resolved once per CreateUI so the inset math is
-- parameterized in exactly one place (W10 chrome + W11 density):
-- `currentRowHeight` is 26 compact / 32 comfortable; `chromePad` is 28 under
-- ButtonFrameTemplate (title band) and 0 on the fallback DialogFrame build.
local currentRowHeight = ROW_HEIGHT
local chromePad = 0

-- The band tops, as distances DOWN from the top of the content area. Filled
-- in by CreateUI from layoutBands; the accessors below read them.
--
-- The content area starts BELOW the chrome band (the template's own title),
-- so every accessor subtracts chromePad to get a frame-relative y.
local bandTitle = 0
local bandFilter = 0
local bandStat = 0
local bandHint = 0
local bandHeader = 0
local bandTable = 0
-- The frame's own title, when the chrome template provides one, and the
-- table band's height (the rows, exactly). Filled in by applyBandLayout.
local providedTitle = nil
local templateTitle = false
local tableBandHeight = 0

-- W7 fresh-row session clock (epoch, GetServerTime-style guarded read like
-- RankDB). Rows stamped at or after the browser opened tick; everything older
-- renders exactly as before. 0 means "no session yet" and ticks nothing.
-- Hunter L-NEW5: independent of the unit tooltip's tooltipSessionStart
-- (Tooltips.lua) by design -- each surface defines "this session" as its own
-- first successful guarded GetServerTime read (here at browser open via
-- markSessionStart, there at tooltip-surface Initialize). Same server epoch,
-- same 0-means-none convention; staleness is always relative to the surface
-- that renders it.
local browserSessionStart = 0

-- W5 debounce: one scheduled flush per keystroke burst, not one render per
-- keystroke. False while no flush is scheduled; without C_Timer the search
-- renders synchronously, exactly as before.
local searchFlushPending = false

-- W9 keyboard focus: the focused ENTRY (identity, never a row index -- the
-- index-based handler is the exact bug the click handler avoids) plus the last
-- rendered view it is anchored against.
local lastView = {}
local focusedEntry = nil

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------

-- Widget-method probe that stays silent on the offline harness.
--
-- load_test counts every __index miss as a "widget-method miss" signal, so
-- probing `frame.SomeMethod` directly on a client that lacks it records a
-- miss even when the probe is the correct guarded behaviour. rawget skips
-- __index on table mocks (no miss, no metamethod) and raises on userdata
-- (real frames) -- where the guarded direct read below then applies. Plain
-- tables without the key (the focused harness) simply lack it.
local function widgetMethod(obj, name)
    if type(obj) ~= "table" or type(name) ~= "string" or name == "" then
        return nil
    end
    local okRaw, method = pcall(rawget, obj, name)
    if okRaw then
        if type(method) == "function" then
            return method
        end
        return nil
    end
    local okIdx, direct = pcall(function() return obj[name] end)
    if okIdx and type(direct) == "function" then
        return direct
    end
    return nil
end

local function rowHeight()
    return currentRowHeight
end

-- Raise a top-level window above the Blizzard settings surfaces (item: browser
-- behind Settings menu). Guarded per call like the rest of this file: a
-- client lacking one method still gets the others, never a raise.
local function applyTopmost(frame, strata, level)
    if type(frame) ~= "table" then
        return
    end
    if type(frame.SetFrameStrata) == "function" then
        pcall(frame.SetFrameStrata, frame, strata)
    end
    if type(frame.SetFrameLevel) == "function" then
        pcall(frame.SetFrameLevel, frame, level)
    end
    if type(frame.SetToplevel) == "function" then
        pcall(frame.SetToplevel, frame, true)
    end
end

-- Lay the bands out inside a content area of the given height, and return the
-- band tops as distances DOWN from the top of that area.
--
-- The tops are derived from the height by walking UP the same stack the
-- height was summed from, so the two are the same number by construction:
-- no band can be given space another band already has.
--
-- `rowsBandHeight` is the table band's own height -- the rows, exactly --
-- and `titleBandHeight` is zero when the frame's chrome already provides the
-- title, so the title band is not paid for twice.
local function layoutBands(contentHeight, rowsBandHeight, titleBandHeight)
    local tops = {}
    local cursor = contentHeight - BAND_PADDING
    local function take(bandHeight)
        cursor = cursor - bandHeight
        return cursor
    end
    tops.footer = take(BAND_FOOTER)
    tops.progress = take(BAND_PROGRESS)
    tops.table = take(rowsBandHeight)
    tops.header = take(BAND_HEADER)
    tops.hint = take(BAND_HINT)
    tops.stat = take(BAND_STAT)
    tops.filter = take(BAND_FILTER)
    tops.title = take(titleBandHeight)
    return tops
end

-- Size the frame and place the bands.
--
-- Its own function rather than a block inside CreateUI: Lua 5.1 caps a
-- function at 60 upvalues and CreateUI is already at the ceiling, so the
-- layout arithmetic lives here instead of in the caller.
local function applyBandLayout(frame)
    local title = rawget(_G, "TacoTipRankFrameTitleText")
    local hasTemplateTitle = type(title) == "table"
        and type(title.SetText) == "function"
    -- The title band is only paid for when this add-on draws the title
    -- itself; the template's own title already owns the chrome band.
    local titleBandHeight = hasTemplateTitle and 0 or BAND_TITLE
    local rowsBandHeight = NUM_ROWS * currentRowHeight
    local contentHeight = titleBandHeight + BAND_FILTER + BAND_STAT + BAND_HINT
        + BAND_HEADER + rowsBandHeight + BAND_PROGRESS + BAND_FOOTER
        + BAND_PADDING
    local tops = layoutBands(contentHeight, rowsBandHeight, titleBandHeight)
    bandTitle, bandFilter, bandStat = tops.title, tops.filter, tops.stat
    bandHint, bandHeader, bandTable = tops.hint, tops.header, tops.table
    frame:SetSize(FRAME_WIDTH, chromePad + contentHeight)
    providedTitle = title
    templateTitle = hasTemplateTitle
    tableBandHeight = rowsBandHeight
end

-- The height of the window's own title band, in pixels.
--
-- Read-only accessor for the harness. Read-only, no display or behaviour
-- change. It exists so the harness can pin the one property that decides
-- whether the title band is paid for at all: 0 when the client's own
-- ButtonFrameTemplate title is present (the template already owns the chrome
-- band, so the add-on draws no title of its own), and BAND_TITLE when the
-- add-on has to draw the title itself.
function RankBrowser.GetTitleBandHeight()
    return templateTitle and 0 or BAND_TITLE
end

-- The frame-relative y of a band top. The content area starts BELOW the
-- chrome band (the template's own title), so every accessor adds chromePad to
-- the distance and negates it.
local function bandY(distanceDown)
    return -(distanceDown + chromePad)
end

local function titleTop()
    return bandY(bandTitle)
end

local function rowTop()
    return bandY(bandTable)
end

local function controlTop()
    return bandY(bandFilter)
end

-- The stat strip's band.
local function statTop()
    return bandY(bandStat)
end

-- The sort readout's OWN band. Separate from the stat strip above it and from
-- the column headers below it, so it can never be drawn on either.
local function hintTop()
    return bandY(bandHint)
end

local function headerTop()
    return bandY(bandHeader)
end

-- The bands that are anchored to the frame's BOTTOM edge, read from the other
-- end of the same stack. Each is a distance UP from the frame's bottom.
local function footerBottom()
    return BAND_PADDING
end

local function progressBottom()
    return BAND_PADDING + BAND_FOOTER
end

local function tableBottom()
    return BAND_PADDING + BAND_FOOTER + BAND_PROGRESS
end

local function markSessionStart()
    local clock = rawget(_G, "GetServerTime")
    if type(clock) == "function" then
        local okClock, nowClock = pcall(clock)
        if okClock and type(nowClock) == "number" then
            browserSessionStart = nowClock
            return
        end
    end
    browserSessionStart = 0
end

-- The leaderboard's OWN colour rules.
--
-- The CHAIN lives in Core (Core.GetClassColor) so this row, the unit tooltip
-- and the character/inspect frame cannot drift apart about WHERE a colour
-- comes from. What stays here is the leaderboard's own two rules, and they
-- are deliberately NOT the tooltip's:
--
--   * PERMISSIVE_COLOR accepts any three NUMBERS. The tooltip and the frame
--     range-check a community colour and refuse one outside 0..1; the
--     leaderboard has always taken a community colour at its word.
--   * the fallback is the leaderboard's OWN 13-entry table above, then the
--     neutral default. A class the CLIENT's own colour tables do not carry
--     therefore reads the leaderboard's own colour here, where the tooltip
--     reads neutral grey.
--
-- Both are preserved exactly. This is a refactor, not a behaviour change.
local PERMISSIVE_COLOR = function(red, green, blue)
    return type(red) == "number"
        and type(green) == "number"
        and type(blue) == "number"
end

local function getClassColor(class)
    local core = namespace.Core
    if type(core) == "table"
        and type(core.GetClassColor) == "function" then
        local red, green, blue = core.GetClassColor(class, {
            accept = PERMISSIVE_COLOR,
        })
        if PERMISSIVE_COLOR(red, green, blue) then
            return { red, green, blue }
        end
    end
    -- Core owns the chain; the fallback below is the leaderboard's own.
    return CLASS_COLORS[class] or DEFAULT_CLASS_COLOR
end

-- Numeric class id back to the file token, the inverse of Scanner's
-- CLASS_IDS. The wire carries classID (canonical, language-independent), so
-- render prefers it and falls back to the stored string for legacy rows.
-- Static pure Lua: no client API, no branching, identical on all five.
local CLASS_FILE_BY_ID = {
    [1] = "WARRIOR", [2] = "PALADIN", [3] = "HUNTER", [4] = "ROGUE",
    [5] = "PRIEST", [6] = "DEATHKNIGHT", [7] = "SHAMAN", [8] = "MAGE",
    [9] = "WARLOCK", [10] = "MONK", [11] = "DRUID", [12] = "DEMONHUNTER",
    [13] = "EVOKER",
}

local function classTokenOf(entry)
    if type(entry) == "table" then
        local id = tonumber(entry.classID)
        if id and CLASS_FILE_BY_ID[id] then
            return CLASS_FILE_BY_ID[id]
        end
        local stored = entry.class
        if type(stored) == "string" and stored ~= "" then
            return stored
        end
    end
    return "UNKNOWN"
end

-- Class atlas at render (W2): resolved through the client's GetClassAtlas,
-- never stored, never synced. Nil when the client cannot resolve (or has no
-- such API) -- the callers degrade to the class-colour-bar-only look.
local function classAtlasOf(classToken)
    if type(classToken) ~= "string"
        or classToken == ""
        or classToken == "UNKNOWN" then
        return nil
    end
    local getAtlas = rawget(_G, "GetClassAtlas")
    if type(getAtlas) ~= "function" then
        return nil
    end
    local ok, atlas = pcall(getAtlas, classToken)
    if ok and type(atlas) == "string" and atlas ~= "" then
        return atlas
    end
    return nil
end

-- Spec identity from the numeric specID the wire carries. Resolved through
-- the engine's GetSpecializationInfoByID (a global on all five branches --
-- Blizzard's own SharedXML/UnitUtil.lua calls it as such on every one), so
-- the name is localized at render instead of at sync. Feature-detected with
-- a pcall: a client without the global (or a harness that has not mocked it)
-- degrades silently to the stored specName/class fallbacks below.
local function specDisplayOf(entry)
    if type(entry) == "table" then
        local specID = tonumber(entry.specID)
        if specID and specID > 0 then
            local byID = rawget(_G, "GetSpecializationInfoByID")
            if type(byID) == "function" then
                local ok, _, name, _, icon = pcall(byID, specID)
                if ok and type(name) == "string" and name ~= "" then
                    return name, icon
                end
            end
        end
    end
    return nil, nil
end

-- PvP snapshot display (Stage 3, advisory only, muted like all advisory data).
--
-- Retail/Forever never render synced PvP: their wire rule is both fields 0
-- always, so a nonzero value there is never inspected data. The family split is
-- Core's (`Core.UsesModernPvPSurface` -- identity first, rated-BG capability
-- only as the fallback), the same single implementation the scanner uses; a
-- classic client that exposes the modern API as a stub must not look modern,
-- or the honor rank silently disappears. Era/TBC/Wrath render the honor rank
-- name (engine-localized via GetPVPRankInfo, raw number when the API is absent)
-- and the raw arena best. The local player's own rating is never shown: there is
-- no verified data to show (no self-rating display; the wire rule stands
-- regardless).
local function modernPvPSurface()
    local core = namespace.Core
    if type(core) == "table"
        and type(core.UsesModernPvPSurface) == "function" then
        return core.UsesModernPvPSurface() == true
    end
    local paperDoll = rawget(_G, "C_PaperDollInfo")
    return type(paperDoll) == "table"
        and type(paperDoll.GetInspectRatedBGData) == "function"
end

local function pvpLinesOf(entry)
    if type(entry) ~= "table" then
        return nil, nil
    end
    if modernPvPSurface() then
        return nil, nil
    end
    local rankLine, arenaLine = nil, nil
    local pvpRank = tonumber(entry.pvpRank)
    if pvpRank and pvpRank > 0 then
        local name = nil
        local byRank = rawget(_G, "GetPVPRankInfo")
        if type(byRank) == "function" then
            local ok, rankName = pcall(byRank, pvpRank)
            if ok and type(rankName) == "string" and rankName ~= "" then
                name = rankName
            end
        end
        rankLine = string.format(L["LB_TIP_PVP_RANK"] or "PvP rank: %s",
            name or tostring(pvpRank))
    end
    local arena = tonumber(entry.arena)
    if arena and arena > 0 then
        arenaLine = string.format(L["LB_TIP_ARENA"] or "Arena best: %d", arena)
    end
    return rankLine, arenaLine
end

local function formatRelativeTime(timestamp)
    if not timestamp or timestamp <= 0 then return L["TIME_UNKNOWN"] or "Unknown" end
    local now = GetServerTime and GetServerTime() or 0
    local diff = now - timestamp
    if diff < 60 then return L["TIME_JUST_NOW"] or "Just now" end
    if diff < 3600 then
        return string.format(L["TIME_MIN_AGO"] or "%d min ago", math.floor(diff / 60))
    end
    if diff < 86400 then
        return string.format(L["TIME_HOUR_AGO"] or "%d hr ago", math.floor(diff / 3600))
    end
    local days = math.floor(diff / 86400)
    if days == 1 then return L["TIME_YESTERDAY"] or "Yesterday" end
    return string.format(L["TIME_DAY_AGO"] or "%d d ago", days)
end

-- Colour by where the value sits in the CURRENT view, not by its raw number.
-- A raw GearScore has no absolute meaning across clients -- 450 is excellent on
-- Classic Era and ordinary on Retail -- so the best score in view is the 1.0
-- end of the scale. `best` is supplied by the renderer; without it there is
-- nothing to compare against and the value stays muted.
local viewBestGS = 0
local viewBestILVL = 0
local viewTotal = 0

local function getGSQualityColor(score, best)
    -- Absolute first: the tooltip grades through TT_GS:GetQuality (Era 200,
    -- TBC 400, Titanforge/Retail 1000 -- main-addon owned, never reimplemented
    -- here), so the browser asks the same source through the adapter and the
    -- two can never drift apart again. Hand derivation for the reported case:
    -- 1400 in the Era 200 domain is (1200, 1400], i.e. the 7th band, Artifact
    -- (0.92, 0.10, 0.10) -- not the shared-1000 Common white, and not the old
    -- relative-view purple. Without an adapter (offline harness, incompatible
    -- TacoTip) the relative view-best scale below is the fallback, so every
    -- existing offline fixture renders exactly as before.
    local adapter = namespace.TacoTipAdapter
    if type(adapter) == "table"
        and type(adapter.GetEquipmentScoreColor) == "function" then
        local ok, r, g, b = pcall(adapter.GetEquipmentScoreColor, score)
        if ok and r and g and b then
            return r, g, b
        end
    end
    local scoring = namespace.Scoring
    local value, top = tonumber(score), tonumber(best)
    if scoring and type(scoring.QualityColor) == "function"
        and value and top and top > 0 and value > 0 then
        local fraction = value / top
        if fraction > 1 then fraction = 1 end
        local r, g, b = scoring.QualityColor(fraction)
        if r and g and b then
            return r, g, b
        end
    end
    return 0.62, 0.62, 0.62
end

-- The `#` column. The scale itself lives in Scoring.RankColor so the leaderboard
-- and the tooltip rank line cannot drift apart again; all this adds is the muted
-- fallback for a standing the database cannot answer.
local function getRankColor(index, total)
    local scoring = namespace.Scoring
    if scoring and type(scoring.RankColor) == "function" then
        local r, g, b = scoring.RankColor(index, total)
        if r and g and b then
            return r, g, b
        end
    end
    return MUTED_R, MUTED_G, MUTED_B
end

local function getPlayerGUID()
    local unitGUID = _G.UnitGUID
    if type(unitGUID) ~= "function" then
        return nil
    end
    local ok, guid = pcall(unitGUID, "player")
    if ok and type(guid) == "string" and guid ~= "" then
        return guid
    end
    return nil
end

-- Locate the player's row in the CURRENT view. Used by the jump logic and by
-- "My Rank"; the GearScore rank map is authoritative for the `#` column.
local function findPlayerRowIndex(data)
    local myGUID = getPlayerGUID()
    if not myGUID or type(data) ~= "table" then return nil end
    for i = 1, #data do
        local entry = data[i]
        if type(entry) == "table" and entry.guid == myGUID then
            return i
        end
    end
    return nil
end

local function getMaxOffset(totalCount)
    return math.max(0, (totalCount or 0) - NUM_ROWS)
end

-- Move the FauxScrollFrame to a row offset and move its scrollbar thumb with it.
--
-- FauxScrollFrame_SetOffset only assigns frame.offset; it does NOT touch the
-- thumb, and FauxScrollFrame_Update reads the thumb, not frame.offset. Setting
-- offset alone therefore moves the rows while leaving the scrollbar at the top
-- -- visible desync. FauxScrollFrame_OnVerticalScroll is the only documented
-- path that writes both (scrollbar value + frame.offset), so use it.
local function scrollToOffset(scrollFrame, offset)
    if not scrollFrame then return end
    if type(_G.FauxScrollFrame_OnVerticalScroll) == "function" then
        pcall(_G.FauxScrollFrame_OnVerticalScroll, scrollFrame, offset * rowHeight(), rowHeight(), nil)
    else
        scrollFrame.offset = offset
    end
end

-- ---------------------------------------------------------------------------
-- Sorting
-- ---------------------------------------------------------------------------
--
-- The `#` column is ALWAYS the GearScore rank, whatever the list is sorted by.
-- That is deliberate: a leaderboard whose rank numbers reorder the moment you
-- sort by iLvl reads as though standing itself had changed. So the display
-- order is chosen here, and a GearScore-rank lookup is built alongside it.
local SORTS = {
    gs = "SORT_GS_DESC",
    ilvl = "SORT_ILVL_DESC",
    level = "SORT_LEVEL_DESC",
    seen = "SORT_SEEN_DESC",
}
local SORTABLE_COLUMNS = { "gs", "ilvl", "level", "seen" }
-- `sortAsc` is the DIRECTION half of the sort state (A2/G2). Clicking a
-- different column resets it to that column's default -- descending, the order
-- every column ships with; clicking the ACTIVE column flips it. The `#` column
-- is unaffected either way: it is always the GearScore rank, never a position.
local currentSort = "gs"
local sortAsc = false

-- UTF-8 triangles, spelled as bytes because Lua 5.1 has no \u{} escapes.
local ARROW_DOWN = "\226\150\188"
local ARROW_UP = "\226\150\178"

-- Sort a copy of `data` for one column in one direction.
--
-- Each column's ordering is written ONCE as a signed difference on the
-- descending ("bigger first") axis, so `asc` reverses the list with a single
-- comparison flip instead of a second set of inverted comparators. The name
-- tie-break stays alphabetical in BOTH directions -- reversing it would make
-- equal-score rows swap places when the player flips direction, which reads
-- as jitter rather than as a reversal. An unknown `mode` returns the copy
-- unsorted, exactly as the old fall-through did.
local function sortEntries(data, mode, asc)
    local arr = {}
    for i = 1, #data do
        arr[i] = data[i]
    end
    if mode ~= "gs" and mode ~= "ilvl" and mode ~= "level" and mode ~= "seen" then
        return arr
    end

    -- Returns the descending-axis difference, or nil when the sortable keys
    -- tie and only the name decides.
    local function compare(a, b)
        local ka, kb
        if mode == "ilvl" then
            ka, kb = tonumber(a.ilvl) or 0, tonumber(b.ilvl) or 0
            if ka ~= kb then return kb - ka end
            ka, kb = tonumber(a.gs) or 0, tonumber(b.gs) or 0
            if ka ~= kb then return kb - ka end
        elseif mode == "level" then
            ka, kb = tonumber(a.level) or 0, tonumber(b.level) or 0
            if ka ~= kb then return kb - ka end
            ka, kb = tonumber(a.gs) or 0, tonumber(b.gs) or 0
            if ka ~= kb then return kb - ka end
        elseif mode == "seen" then
            ka, kb = tonumber(a.timestamp) or 0, tonumber(b.timestamp) or 0
            if ka ~= kb then return kb - ka end
            ka, kb = tonumber(a.gs) or 0, tonumber(b.gs) or 0
            if ka ~= kb then return kb - ka end
        else
            ka, kb = tonumber(a.gs) or 0, tonumber(b.gs) or 0
            if ka ~= kb then return kb - ka end
            ka, kb = tonumber(a.ilvl) or 0, tonumber(b.ilvl) or 0
            if ka ~= kb then return kb - ka end
        end
        return nil
    end

    table.sort(arr, function(a, b)
        local d = compare(a, b)
        if d == nil then
            local an, bn = a.name or "", b.name or ""
            if an == bn then return false end
            return an < bn
        end
        if asc then return d > 0 end
        return d < 0
    end)
    return arr
end

-- guid -> GearScore rank within the current filter set.
--
-- Always DESCENDING -- rank 1 is the highest GearScore -- whatever direction
-- the display list currently happens to face (`sortAsc` never reaches here).
local function buildGearScoreRanks(data)
    local byGS = sortEntries(data, "gs", false)
    local ranks = {}
    for i = 1, #byGS do
        local guid = byGS[i].guid
        if guid and ranks[guid] == nil then
            ranks[guid] = i
        end
    end
    return ranks
end

-- ---------------------------------------------------------------------------
-- Row tooltip
-- ---------------------------------------------------------------------------

-- Hunter M-NEW6: row-tooltip record failures were swallowed mid-card (a
-- non-numeric entry field raises string.format OUTSIDE the per-line pcalls,
-- truncating the hover with no diag). Validated once BEFORE ClearLines: a
-- corrupt entry counts here and returns with the tooltip untouched instead
-- of clearing the card and then raising halfway. Surfaced in
-- GetDebugState below; the valid path is byte-identical.
local rowTooltipErrors = 0
local lastRowTooltipError = nil
local function noteRowTooltipError(err)
    rowTooltipErrors = rowTooltipErrors + 1
    lastRowTooltipError = tostring(err)
end

-- Debug accessor for the M-NEW6 counter above (debug ONLY). Read-only: no
-- display or behaviour change.
function RankBrowser.GetDebugState()
    return {
        rowTooltipErrors = rowTooltipErrors,
        lastRowTooltipError = lastRowTooltipError,
    }
end

-- A leaderboard row is deliberately terse: six narrow columns have no room for
-- spec, quality label and standing all at once. Hover carries the detail.
--
-- The shared GameTooltip is safe here: Tooltips.lua's OnUpdate poll returns
-- early when the tooltip has no unit, and nothing below ever sets one.
local function showRowTooltip(row, entry)
    local tip = _G.GameTooltip
    if not row or not entry or type(tip) ~= "table" or type(tip.SetOwner) ~= "function" then
        return
    end

    -- Hunter M-NEW6: validate numerics once, BEFORE ClearLines (see above).
    -- nil means "unknown" and renders as 0 below; a non-numeric non-nil
    -- value would raise string.format mid-card.
    if ((entry.gs ~= nil and type(entry.gs) ~= "number")
            or (entry.ilvl ~= nil and type(entry.ilvl) ~= "number")
            or (entry.timestamp ~= nil and type(entry.timestamp) ~= "number")
            or (row.gsRank ~= nil and type(row.gsRank) ~= "number")) then
        noteRowTooltipError("non-numeric row-tooltip field")
        return
    end

    local c = getClassColor(classTokenOf(entry))
    pcall(tip.SetOwner, tip, row, "ANCHOR_RIGHT")
    if type(tip.ClearLines) == "function" then
        pcall(tip.ClearLines, tip)
    end

    local function add(text, r, g, b)
        if text then
            pcall(tip.AddLine, tip, text, r, g, b)
        end
    end

    add(entry.name or L["LB_TIP_UNKNOWN"], c[1], c[2], c[3])

    local resolvedName = specDisplayOf(entry)
    local specName = resolvedName
    if type(specName) ~= "string" or specName == "" then
        specName = entry.specName
    end
    if type(specName) ~= "string" or specName == "" then
        specName = classTokenOf(entry)
    end
    add(specName ~= "" and specName or L["LB_TIP_UNKNOWNSPEC"], MUTED_R, MUTED_G, MUTED_B)

    -- Guild renders as its own muted line when known. "" is
    -- unguilded-or-unknown and renders nothing -- never "Unknown".
    if type(entry.guild) == "string" and entry.guild ~= "" then
        add(entry.guild, MUTED_R, MUTED_G, MUTED_B)
    end

    local pvpRankLine, arenaLine = pvpLinesOf(entry)
    if pvpRankLine then
        add(pvpRankLine, MUTED_R, MUTED_G, MUTED_B)
    end
    if arenaLine then
        add(arenaLine, MUTED_R, MUTED_G, MUTED_B)
    end

    local gr, gg, gb = getGSQualityColor(entry.gs, viewBestGS)
    add(string.format(L["LB_TIP_GS"] or "GearScore: %d", entry.gs or 0), gr, gg, gb)

    local ir, ig, ib = getGSQualityColor(entry.ilvl, viewBestILVL)
    add(string.format(L["LB_TIP_ILVL"] or "Average iLvl: %.1f", entry.ilvl or 0), ir, ig, ib)

    if row.gsRank then
        add(string.format(L["LB_TIP_RANK"] or "GearScore rank: %d", row.gsRank), TEXT_R, TEXT_G, TEXT_B)
    end
    add(string.format(L["LB_TIP_LASTSEEN"] or "Last seen: %s", formatRelativeTime(entry.timestamp)), MUTED_R, MUTED_G, MUTED_B)
    if type(entry.faction) == "string" and entry.faction ~= "" then
        add(entry.faction, MUTED_R, MUTED_G, MUTED_B)
    end
    -- The row's click affordance, stated (A3/G7b): clicking opens the gear
    -- panel, and a tooltip that never mentions it leaves the feature to be
    -- discovered by accident.
    add(L["LB_TIP_CLICK_GEAR"] or "Click to view gear", MUTED_R, MUTED_G, MUTED_B)
end

local function hideRowTooltip()
    local tip = _G.GameTooltip
    if type(tip) == "table" and type(tip.Hide) == "function" then
        pcall(tip.Hide, tip)
    end
end

-- ---------------------------------------------------------------------------
-- Row rendering
-- ---------------------------------------------------------------------------

local function applyRowOverlay(row)
    if not row then return end
    -- W9 focus ring reuses the player-row treatment (brand overlay at the
    -- player-row alpha): the list has one highlight language, not two.
    local alpha = 0
    if row.focused then
        alpha = 0.18
    elseif row.hovered then
        alpha = 0.10
    elseif row.isPlayer then
        alpha = 0.18
    end
    if row.overlay then
        row.overlay:SetAlpha(alpha)
    end
end

-- Show the specialization icon when one is known.
--
-- Two sources: a numeric specID resolves through the engine
-- (GetSpecializationInfoByID, localized at render), and legacy rows carry a
-- stored texture path instead (Scanner stored specIcon from
-- C_SpecializationInfo.GetTalentInfo(...).icon, a FILEID on modern clients).
-- Whether a modern talent fileID resolves against Classic's own texture set
-- is NOT guaranteed, so this is entirely defensive: a missing icon must cost
-- the row a 14px gap, never an error and never a broken-looking box.
local function applySpecIcon(row, entry)
    local tex = row.specIconTexture
    if not tex then return end

    -- A numeric specID resolves through the engine (localized name's icon);
    -- legacy rows carry a stored texture path instead. Either may be absent,
    -- and absence hides the texture -- never an error, never an empty box.
    local _, resolvedIcon = specDisplayOf(entry)
    local icon = resolvedIcon or entry.specIcon
    local usable = (type(icon) == "string" and icon ~= "")
        or (type(icon) == "number" and icon ~= 0)

    if not usable then
        tex:Hide()
        row.hasSpecIcon = false
        return
    end

    local ok = pcall(tex.SetTexture, tex, icon)
    if ok then
        tex:Show()
        row.hasSpecIcon = true
    else
        tex:Hide()
        row.hasSpecIcon = false
    end
end

-- Class icon beside the row name (W2). Same defensive shape as applySpecIcon:
-- the atlas resolves at render through GetClassAtlas, is applied through a
-- guarded SetAtlas, and absence hides the texture -- never an error, never a
-- broken-looking box. The class-colour bar and name colour are untouched.
local function applyClassIcon(row, entry)
    local tex = row.classIconTexture
    if not tex then return end
    local atlas = classAtlasOf(classTokenOf(entry))
    if not atlas then
        tex:Hide()
        row.hasClassIcon = false
        return
    end
    local setAtlas = widgetMethod(tex, "SetAtlas")
    local ok = type(setAtlas) == "function" and pcall(setAtlas, tex, atlas)
    if ok then
        tex:Show()
        row.hasClassIcon = true
    else
        tex:Hide()
        row.hasClassIcon = false
    end
end

local function renderRow(row, entry, index, gsRank, myGUID)
    row.isPlayer = (myGUID ~= nil and entry.guid == myGUID)
    row.gsRank = gsRank
    row.entry = entry
    row:Show()

    -- Rank. This is the GEARSCORE rank, not the row's position, so it does not
    -- shuffle when the list is re-sorted by iLvl or last-seen.
    local rr, rg, rb = getRankColor(gsRank or index, viewTotal)
    row.rankText:SetText("#" .. tostring(gsRank or index))
    row.rankText:SetTextColor(rr, rg, rb)

    -- Name in class colour, plus a thin class bar down the left edge.
    local c = getClassColor(classTokenOf(entry))
    row.nameText:SetText(entry.name or L["LB_TIP_UNKNOWN"])
    row.nameText:SetTextColor(c[1], c[2], c[3])
    row.classBar:SetColorTexture(c[1], c[2], c[3], 0.85)

    -- Spec, muted so it reads as secondary to the name. A numeric specID
    -- resolves through the engine first (localized at render); with no
    -- specID, fall back to the stored specName, then the LOCALIZED class
    -- name -- a class the locale table has not caught up with (EVOKER) must
    -- still read as itself rather than as blank (A5/G4).
    local specName = specDisplayOf(entry)
    if type(specName) ~= "string" or specName == "" then
        specName = entry.specName
    end
    if type(specName) ~= "string" or specName == "" then
        local classToken = classTokenOf(entry)
        if classToken == "UNKNOWN" then
            -- No class info at all: blank, exactly as before.
            specName = (type(entry.class) == "string" and entry.class ~= "")
                and entry.class or ""
        else
            specName = L["CLASS_" .. classToken] or classToken
        end
    end
    row.specText:SetText(specName)
    row.specText:SetTextColor(MUTED_R, MUTED_G, MUTED_B)

    -- GearScore and iLvl share the score's quality colour.
    local gs = entry.gs or 0
    local gr, gg, gb = getGSQualityColor(gs, viewBestGS)
    row.gsText:SetText(tostring(gs))
    row.gsText:SetTextColor(gr, gg, gb)
    row.ilvlText:SetText(string.format("%.1f", entry.ilvl or 0))
    row.ilvlText:SetTextColor(gr, gg, gb)

    -- Level renders blank when unknown (0) -- old rows stay clean.
    local level = tonumber(entry.level)
    row.levelText:SetText((level and level > 0) and tostring(level) or "")
    row.levelText:SetTextColor(MUTED_R, MUTED_G, MUTED_B)

    -- Last seen, muted.
    row.seenText:SetText(formatRelativeTime(entry.timestamp))
    row.seenText:SetTextColor(MUTED_R, MUTED_G, MUTED_B)

    applySpecIcon(row, entry)
    applyClassIcon(row, entry)

    -- W7 fresh-row tick: stamped at or after the browser opened, i.e. synced
    -- while watched. All older: no marker (normal, not an error). Far-future
    -- skew ticks rather than raising -- worst case one extra tick.
    local fresh = browserSessionStart > 0
        and (tonumber(entry.timestamp) or 0) >= browserSessionStart
    if row.freshTick then
        if fresh then
            row.freshTick:Show()
        else
            row.freshTick:Hide()
        end
    end

    -- "YOU" marker on the player's own row.
    if row.youTag then
        row.youTag:SetShown(row.isPlayer)
    end

    applyRowOverlay(row)
end

-- W9 keyboard focus movement. The focus tracks an ENTRY (identity by guid),
-- never a row index: after a re-sort the same row position is a different
-- player, so index-based focus would open the wrong gear panel -- the classic
-- bug the click handler avoids by keeping its own entry.
local function refreshFocusFlags()
    for i = 1, NUM_ROWS do
        local row = rowFrames[i]
        if row then
            row.focused = (focusedEntry ~= nil
                and row.entry ~= nil
                and type(row.entry) == "table"
                and row.entry.guid == focusedEntry.guid)
            if row:IsShown() then
                applyRowOverlay(row)
            end
        end
    end
end

local function moveFocus(delta)
    local view = lastView
    if type(view) ~= "table" or #view == 0 then
        return
    end
    local index = nil
    if focusedEntry then
        for i = 1, #view do
            if type(view[i]) == "table" and view[i].guid == focusedEntry.guid then
                index = i
                break
            end
        end
    end
    if not index then
        index = delta > 0 and 1 or #view
    else
        index = math.min(#view, math.max(1, index + delta))
    end
    local entry = view[index]
    if type(entry) == "table" then
        focusedEntry = entry
    end
    -- Keep the focused row on screen, centred like the jump logic.
    local f = rankFrame
    local sf = f and f.scrollFrame or nil
    if sf then
        local offset = 0
        if type(_G.FauxScrollFrame_GetOffset) == "function" then
            offset = _G.FauxScrollFrame_GetOffset(sf) or 0
        end
        if index < offset + 1 or index > offset + NUM_ROWS then
            scrollToOffset(sf, math.min(getMaxOffset(#view),
                math.max(0, index - math.floor(NUM_ROWS / 2))))
        end
    end
    RankBrowser.UpdateUI()
end

-- ---------------------------------------------------------------------------
-- Public: scroll control
-- ---------------------------------------------------------------------------

-- Start an equipment scan from any surface that offers the control.
--
-- Guarded rather than assumed: the Scanner can be absent when its file fails to
-- load, and a button must never raise for that. Returns whether a scan was
-- actually started so a caller can tell the difference between "started" and
-- "nothing happened".
--
-- ONE home for "start a scan". This used to call scanner.BeginGeneration
-- DIRECTLY, which bumped the generation and left the scanner in "pending" --
-- and never called scanner.RunGeneration, so the capture the button promises
-- never ran and the scanner stayed "pending" for the rest of the session: the
-- progress bar spun, and the surfaces that render from the scanner state had
-- no score to show. It also STEALED a scan that was already scheduled: the
-- scheduled run carried the older generation, RunGeneration refused it
-- (targetGeneration ~= generation), and that scan was lost too.
--
-- Core.RequestLocalScan is the one home: it begins the generation AND
-- schedules the run on the next OnUpdate tick, and it refuses to begin a
-- second generation while one is already pending. So the generation is bumped
-- exactly once per scan, and a scan that is started actually runs.
function RankBrowser.StartScan()
    local core = namespace.Core
    if type(core) ~= "table" or type(core.RequestLocalScan) ~= "function" then
        -- No home for "start a scan": say so rather than leaving the button a
        -- dead end. The Scanner is not called directly any more -- that was
        -- the second implementation of this action, and the two could drift
        -- (and did).
        if type(_G.DEFAULT_CHAT_FRAME) == "table"
            and type(_G.DEFAULT_CHAT_FRAME.AddMessage) == "function" then
            pcall(_G.DEFAULT_CHAT_FRAME.AddMessage, _G.DEFAULT_CHAT_FRAME,
                "|cffff5555TacoTip Extras:|r the scan is unavailable: "
                    .. "Core.RequestLocalScan is missing.")
        end
        return false
    end
    local ok, started = pcall(core.RequestLocalScan, "leaderboard")
    if not ok then
        return false
    end
    RankBrowser.RefreshProgress()
    return started == true
end

-- How long the "scan complete" line stays up where timers exist. Any longer
-- and it stops being feedback and starts being chrome.
local SCAN_STATUS_SECONDS = 5

-- The scan's active->inactive edge (A6/G6), in two parts: a short status line
-- near the progress bar, and the same click sound Blizzard's own windows play
-- on a completed toggle (AddonList does it on classic_era). Both are
-- defensive: the sound sits behind a PlaySound/SOUNDKIT guard, and the status
-- line renders through LB_SCAN_COMPLETE (eleven-locale key) with an English
-- fallback, so a missing translation degrades to English, never to silence.
local function announceScanComplete()
    local f = rankFrame
    if not f then
        return
    end

    if type(f.scanStatus) == "table" then
        -- "Players tracked", not scan slots: the same pool size the footer
        -- reports, so the two lines can never disagree about realm coverage.
        local total = 0
        local db = namespace.RankDB
        if type(db) == "table" and type(db.GetLeaderboard) == "function" then
            local _, count = db.GetLeaderboard(nil, "All", "ALL", "")
            total = tonumber(count) or 0
        end
        f.scanStatus:SetText(string.format(
            L["LB_SCAN_COMPLETE"] or "Scan complete - %d players tracked", total))
        f.scanStatus:Show()

        -- Flash, then get out of the way -- where a timer exists. Without one
        -- the line persists until the next scan: extra information, never an
        -- error. The token stops a stale timer from wiping a newer line.
        f.scanStatusToken = (f.scanStatusToken or 0) + 1
        local token = f.scanStatusToken
        local timer = _G.C_Timer
        if type(timer) == "table" and type(timer.After) == "function" then
            timer.After(SCAN_STATUS_SECONDS, function()
                if f.scanStatusToken == token and type(f.scanStatus) == "table" then
                    f.scanStatus:Hide()
                end
            end)
        end
    end

    if type(_G.PlaySound) == "function" and type(_G.SOUNDKIT) == "table" then
        local sound = _G.SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
        if sound ~= nil then
            pcall(_G.PlaySound, sound)
        end
    end
end

-- Paint the progress bar from Scanner.GetProgress.
--
-- Hidden when there is nothing to show, so the window carries no dead rail when
-- idle. Kept visible and full at 100% until the scan reports inactive, because
-- hiding it the instant it fills reads as "the scan failed".
function RankBrowser.RefreshProgress()
    local f = rankFrame
    if not f or type(f.progressBar) ~= "table" then
        return false
    end
    local scanner = namespace.Scanner
    if type(scanner) ~= "table" or type(scanner.GetProgress) ~= "function" then
        f.progressBar:Hide()
        f.scanning = false
        return false
    end
    local progress = scanner.GetProgress()
    if type(progress) ~= "table" then
        f.progressBar:Hide()
        f.scanning = false
        return false
    end
    local wasScanning = f.scanning
    f.scanning = progress.active == true
    if f.scanning then
        -- A fresh scan supersedes any completion line from the last one.
        if type(f.scanStatus) == "table" then
            f.scanStatus:Hide()
        end
    elseif wasScanning then
        -- The active->inactive edge. The OnUpdate poll stops with f.scanning,
        -- so this is the only moment that can report the finish -- say so here
        -- rather than letting the bar vanish in silence (A6/G6).
        announceScanComplete()
    end
    if progress.percent <= 0 and not f.scanning then
        f.progressBar:Hide()
        return true
    end
    f.progressBar:Show()
    f.progressBar:SetValue(progress.percent)
    if type(f.progressBar.text) == "table" then
        f.progressBar.text:SetText(string.format(
            L["SCAN_PROGRESS"] or "%d / %d",
            progress.done or 0,
            progress.total or 0))
    end
    if f.scanButton and type(f.scanButton.SetText) == "function" then
        f.scanButton:SetText(f.scanning
            and (L["LB_SCAN_BUSY"] or "Scanning...")
            or (L["LB_SCAN"] or "Scan now"))
    end
    return true
end

-- ---------------------------------------------------------------------------
-- Gear panel
-- ---------------------------------------------------------------------------
--
-- Slot labels come from the CLIENT, not from our locale files: Blizzard's
-- INVTYPE_* strings are already translated in every language the game ships, so
-- using them means the panel is localized in locales this add-on has never been
-- translated into.
--
-- Verified present on ALL FIVE branches of the FrameXML mirror
-- (wow-ui-source), branch names as they exist there:
--   origin/classic_era, origin/classic_anniversary, origin/classic_titan,
--   origin/forever, origin/live
-- The hand slot reads INVTYPE_HAND -- the name the client actually publishes.
-- INVTYPE_HANDS exists in NONE of the five branches, so a row bound to it fell
-- back to the English literal in every client and every language, which is
-- exactly what the client string is supposed to prevent. Evidence:
--   origin/classic_era          Interface/AddOns/Blizzard_EncounterJournal/Cata/Blizzard_EncounterJournal.lua:126
--   origin/classic_anniversary  Interface/AddOns/Blizzard_EncounterJournal/Cata/Blizzard_EncounterJournal.lua:126
--   origin/classic_titan        Interface/AddOns/Blizzard_EncounterJournal/Cata/Blizzard_EncounterJournal.lua:126
--   origin/live                 Interface/AddOns/Blizzard_EncounterJournal/Cata/Blizzard_EncounterJournal.lua:126
--   origin/forever              Interface/AddOns/Blizzard_EncounterJournal/Mainline/Blizzard_EncounterJournal.lua:176
-- (each line reads `[Enum.ItemSlotFilterType.Hand] = INVTYPE_HAND`).
-- The back slot keeps INVTYPE_CLOAK, which exists on all five branches
-- (Cata/Blizzard_EncounterJournal.lua:123; Mainline/Blizzard_EncounterJournal.lua:173
-- on origin/forever and origin/live) and whose English string is "Back".
local SLOT_ROWS = {
    { slot = 1,  global = "INVTYPE_HEAD",            fallback = "Head" },
    { slot = 2,  global = "INVTYPE_NECK",            fallback = "Neck" },
    { slot = 3,  global = "INVTYPE_SHOULDER",        fallback = "Shoulder" },
    { slot = 15, global = "INVTYPE_CLOAK",           fallback = "Back" },
    { slot = 5,  global = "INVTYPE_CHEST",           fallback = "Chest" },
    { slot = 9,  global = "INVTYPE_WRIST",           fallback = "Wrist" },
    { slot = 10, global = "INVTYPE_HAND",            fallback = "Hand" },
    { slot = 6,  global = "INVTYPE_WAIST",           fallback = "Waist" },
    { slot = 7,  global = "INVTYPE_LEGS",            fallback = "Legs" },
    { slot = 8,  global = "INVTYPE_FEET",            fallback = "Feet" },
    { slot = 11, global = "INVTYPE_FINGER",          fallback = "Finger" },
    { slot = 12, global = "INVTYPE_FINGER",          fallback = "Finger" },
    { slot = 13, global = "INVTYPE_TRINKET",         fallback = "Trinket" },
    { slot = 14, global = "INVTYPE_TRINKET",         fallback = "Trinket" },
    { slot = 16, global = "INVTYPE_WEAPONMAINHAND",  fallback = "Main Hand" },
    { slot = 17, global = "INVTYPE_WEAPONOFFHAND",   fallback = "Off Hand" },
    { slot = 18, global = "INVTYPE_RANGED",          fallback = "Ranged" },
}

local gearFrame

-- The entry the gear panel is currently showing.
--
-- Kept so a rebuild can re-render the panel from LIVE data: the panel's rows
-- belong to the browser frame they were drawn for, and a rebuild discards that
-- frame. Re-rendering the same entry re-reads the Scanner cache and the RankDB
-- gear table, so what the panel shows afterwards is current rather than a copy
-- of what the discarded frame carried.
local gearEntry = nil

-- Debug accessor for the slot-label table above (Batch 7). Read-only, no
-- display or behaviour change.
--
-- It exists so the harness can pin EVERY global name in this table. A typo in
-- one row's global name is otherwise invisible: the row silently falls back to
-- its English literal -- which is precisely the defect this table carried
-- (INVTYPE_HANDS, a name no client publishes, so the Hands row read "Hands"
-- in every client and every language).
function RankBrowser.GetSlotRows()
    local rows = {}
    for i = 1, #SLOT_ROWS do
        local row = SLOT_ROWS[i]
        rows[i] = { slot = row.slot, global = row.global, fallback = row.fallback }
    end
    return rows
end

local function slotLabel(row)
    local g = _G
    local text = rawget(g, row.global)
    if type(text) == "string" and text ~= "" then
        return text
    end
    return row.fallback
end

-- The item link is rendered AS A LINK rather than as a name, so the client
-- supplies the quality colour and the hover tooltip for free. Re-implementing
-- either would be a second source of truth that drifts from the game's.
--
-- W8 session-data richness: when the panel renders from the SESSION cache,
-- each row appends the slot's item level plus two completeness dots (enchant
-- present, sockets filled). The iLvl resolves at display through
-- C_Item.GetItemInfo -- never persisted, never synced -- and an uncached ID
-- keeps today's literal with no suffix, no spinner, no blocking. A numeric-ID
-- call form the client rejects degrades the same way (suffix path stays
-- dark, literal carries the panel).
local function sessionItemLevel(itemID)
    if type(itemID) ~= "number"
        or itemID <= 0
        or itemID ~= math.floor(itemID) then
        return nil
    end
    local itemAPI = rawget(_G, "C_Item")
    if type(itemAPI) ~= "table" or type(itemAPI.GetItemInfo) ~= "function" then
        return nil
    end
    local ok, _, _, _, itemLevel = pcall(itemAPI.GetItemInfo, itemID)
    if ok and type(itemLevel) == "number" and itemLevel > 0 then
        return math.floor(itemLevel)
    end
    -- Prime the cache for the next open; this open renders the literal.
    if type(itemAPI.RequestLoadItemDataByID) == "function" then
        pcall(itemAPI.RequestLoadItemDataByID, itemID)
    end
    return nil
end

local function slotValueText(slot, withILvl)
    if type(slot) ~= "table" then
        return nil
    end
    if slot.state == "confirmed-empty" then
        return nil
    end
    local itemIDValue = nil
    local cell = slot.itemID
    -- Zero is not an item: an unscored/unknown cell must fall through to the
    -- empty-state note, never render as "item:0".
    if type(cell) == "table" and type(cell.value) == "number"
        and cell.value > 0 then
        itemIDValue = cell.value
    end
    local link = slot.nativeLink
    if type(link) == "table" and type(link.value) == "string" and link.value ~= "" then
        if withILvl and itemIDValue then
            local ilvl = sessionItemLevel(itemIDValue)
            if ilvl then
                return link.value .. "  |cff9e9e9e(" .. tostring(ilvl) .. ")|r"
            end
        end
        return link.value
    end
    if itemIDValue then
        local text = "|cffffffffitem:" .. tostring(itemIDValue) .. "|r"
        if withILvl then
            local ilvl = sessionItemLevel(itemIDValue)
            if ilvl then
                return text .. "  |cff9e9e9e(" .. tostring(ilvl) .. ")|r"
            end
        end
        return text
    end
    return nil
end

-- W8 enhancement dots from the session revision cells: enchant present
-- (permanentEnchantID complete and nonzero) and sockets filled (capacity > 0
-- with every socket holding a gem). Session-only by design -- never from
-- persisted gear.ids strings, which carry no enchant or gem data.
local function slotDots(slot)
    if type(slot) ~= "table" then
        return false, false
    end
    local enchanted = false
    local ench = slot.permanentEnchantID
    if type(ench) == "table" and ench.status == "complete"
        and type(ench.value) == "number" and ench.value ~= 0 then
        enchanted = true
    end
    local socketed = false
    local socks = slot.sockets
    if type(socks) == "table" and socks.status == "complete"
        and type(socks.value) == "table" then
        local cap = tonumber(socks.value.capacity) or 0
        local gems = socks.value.gemIDs
        if cap > 0 and type(gems) == "table" then
            socketed = true
            for i = 1, cap do
                if tonumber(gems[i]) == nil or tonumber(gems[i]) == 0 then
                    socketed = false
                    break
                end
            end
        end
    end
    return enchanted, socketed
end

-- Re-adopt the live browser as the gear panel's parent. RebuildUI discards
-- the browser frame; a panel left parented to the discarded frame hides with
-- it even though it is still "shown". Guarded: without the methods the panel
-- keeps whatever parent it has, exactly as before.
local function adoptGearParent()
    if not gearFrame then
        return
    end
    local want = rankFrame or _G.UIParent or nil
    if want == nil then
        return
    end
    local have = nil
    if type(gearFrame.GetParent) == "function" then
        local ok, parent = pcall(gearFrame.GetParent, gearFrame)
        if ok then
            have = parent
        end
    end
    if have == want then
        return
    end
    if type(gearFrame.SetParent) == "function" then
        pcall(gearFrame.SetParent, gearFrame, want)
    end
    if type(gearFrame.ClearAllPoints) == "function" then
        pcall(gearFrame.ClearAllPoints, gearFrame)
    end
    if type(gearFrame.SetPoint) == "function" then
        pcall(gearFrame.SetPoint, gearFrame, "CENTER", 0, 0)
    end
end

-- Close the gear panel.
--
-- This is the ONE place the panel is closed, and it is called from every route
-- that closes the browser: the toggle's hide branch, the rebuild and the
-- Escape handler. It used to have NO caller at all, which left the panel's
-- visibility resting on an engine rule this add-on does not depend on (the
-- panel is a TOPLEVEL child, so a hiding parent would normally take it down
-- with it) -- a rule the audit could not verify on the supported clients.
--
-- Closing it also forgets WHICH entry it was showing, so a panel the player
-- has dismissed is never resurrected by a later rebuild.
function RankBrowser.CloseGear()
    gearEntry = nil
    if gearFrame then
        gearFrame:Hide()
    end
end

-- A frame that can actually carry a backdrop.
--
-- THE BUG THIS EXISTS TO FIX (operator's Classic Era screenshot): the gear
-- panel was created as a PLAIN frame -- `CreateFrame("Frame",
-- "TacoTipGearPanel", parent)`, with NO template -- so in the real client it
-- had no SetBackdrop at all. The `if f.SetBackdrop then` guard below SKIPPED
-- the backdrop, the panel rendered TRANSPARENT, and its text was unreadable
-- over whatever was behind it.
--
-- Only a template that mixes in BackdropTemplateMixin carries the API.
-- Verified in the client source on ALL FIVE branches:
--
--   origin/classic_era          Interface/AddOns/Blizzard_SharedXML/Backdrop.xml:5
--   origin/classic_anniversary  Interface/AddOns/Blizzard_SharedXML/Backdrop.xml:5
--   origin/classic_titan        Interface/AddOns/Blizzard_SharedXML/Backdrop.xml:5
--   origin/forever              Interface/AddOns/Blizzard_SharedXML/Backdrop.xml:5
--   origin/live                 Interface/AddOns/Blizzard_SharedXML/Backdrop.xml:5
--       <Frame name="BackdropTemplate" mixin="BackdropTemplateMixin" virtual="true">
--   and the mixin itself, on every one of those branches:
--   Interface/AddOns/Blizzard_SharedXML/Backdrop.lua:336
--       function BackdropTemplateMixin:SetBackdrop(backdropInfo)
--       :354  function BackdropTemplateMixin:GetBackdrop()
--       :406  function BackdropTemplateMixin:SetBackdropColor(r, g, b, a)
--
-- ButtonFrameTemplate does NOT: it inherits PortraitFrameTemplate ->
-- PortraitFrameTemplateNoCloseButton -> PortraitFrameBaseTemplate, whose
-- mixins are PortraitFrameMixin / PortraitFrameTemplateMixin
-- (SharedUIPanelTemplates.xml:387, :440, :674) -- it paints its own background
-- TEXTURE instead. That is why the BROWSER frame looks right and the gear
-- panel did not.
--
-- The Mixin is the belt to the template's braces, and it is the same shape
-- the main add-on's tooltip path uses (main.lua getOrCreateBackdropFrame):
-- if the template was unavailable for any reason, mix the API in by hand.
local function createBackdropFrame(name, parent)
    local g = _G
    local ok, f = pcall(g.CreateFrame, "Frame", name, parent, "BackdropTemplate")
    if not ok or type(f) ~= "table" then
        ok, f = pcall(g.CreateFrame, "Frame", name, parent)
    end
    if not ok or type(f) ~= "table" then
        return nil
    end
    if not f.SetBackdrop then
        local mixin = rawget(g, "BackdropTemplateMixin")
        local mix = rawget(g, "Mixin")
        if type(mixin) == "table" and type(mix) == "function" then
            pcall(mix, f, mixin)
        end
    end
    return f
end

function RankBrowser.ShowGear(entry)
    if type(entry) ~= "table" then
        return false
    end
    local g = _G
    if type(g.CreateFrame) ~= "function" then
        return false
    end

    if not gearFrame then
        local parent = rankFrame or g.UIParent or nil
        -- A BACKDROP-CAPABLE frame. A plain one has no SetBackdrop in the
        -- client, so the backdrop below was silently skipped and the panel
        -- rendered transparent.
        local f = createBackdropFrame("TacoTipGearPanel", parent)
        if not f then
            return false
        end
        -- Same reason as the browser window: a created frame is VISIBLE in the
        -- client, and this panel is shown by ShowGear when it is ready. Hide it
        -- here so it is never on screen between its creation and its content.
        if type(f.Hide) == "function" then
            pcall(f.Hide, f)
        end
        f:SetSize(GEAR_PANEL_WIDTH, GEAR_PANEL_HEIGHT)
        f:SetPoint("CENTER", 0, 0)
        -- Child of the browser, same strata, higher level: above the rows,
        -- above the Settings canvas, below the hover tooltip.
        applyTopmost(f, GEAR_STRATA, GEAR_LEVEL)
        if type(f.SetClampedToScreen) == "function" then
            f:SetClampedToScreen(true)
        end
        if f.SetBackdrop then
            f:SetBackdrop({
                bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                tile = true, tileSize = 32, edgeSize = 24,
                insets = { left = 8, right = 8, top = 8, bottom = 8 },
            })
        end
        -- Same explicit alpha as the browser panel (PANEL_BACKDROP_ALPHA):
        -- the texture default rendered near-transparent on this panel.
        if type(f.SetBackdropColor) == "function" then
            f:SetBackdropColor(0, 0, 0, PANEL_BACKDROP_ALPHA)
        end
        if type(f.EnableMouse) == "function" then
            f:EnableMouse(true)
        end
        if type(f.SetMovable) == "function" then
            f:SetMovable(true)
            f:RegisterForDrag("LeftButton")
            f:SetScript("OnDragStart", f.StartMoving)
            f:SetScript("OnDragStop", f.StopMovingOrSizing)
        end

        local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -16)
        f.title = title

        local close = g.CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
        f.close = close

        f.rows = {}
        for index = 1, #SLOT_ROWS do
            local row = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            row:SetPoint("TOPLEFT", f, "TOPLEFT", GEAR_ROW_LEFT, gearRowTop(index))
            row:SetWidth(GEAR_ROW_WIDTH)
            row:SetJustifyH("LEFT")
            f.rows[index] = row
        end

        -- W8 enhancement dots: two 8px textures per slot row (enchant, then
        -- sockets), reusing the class-bar creation shape. Session-only: they
        -- hide whenever the row does not render from a live revision.
        --
        -- The dots hang off the SAME gearRowTop the row above uses, so a row
        -- and its dots can never end up on different lines.
        f.dotEnchant = {}
        f.dotSocket = {}
        for index = 1, #SLOT_ROWS do
            local dotY = gearRowTop(index) - GEAR_DOT_DROP
            local de = f:CreateTexture(nil, "ARTWORK")
            de:SetPoint("TOPLEFT", f, "TOPLEFT", GEAR_DOT_ENCHANT_X, dotY)
            de:SetSize(GEAR_DOT_SIZE, GEAR_DOT_SIZE)
            de:SetColorTexture(0.83, 0.66, 0.29, 1)
            de:Hide()
            f.dotEnchant[index] = de
            local ds = f:CreateTexture(nil, "ARTWORK")
            ds:SetPoint("TOPLEFT", f, "TOPLEFT", GEAR_DOT_SOCKET_X, dotY)
            ds:SetSize(GEAR_DOT_SIZE, GEAR_DOT_SIZE)
            ds:SetColorTexture(0.35, 0.82, 0.48, 1)
            ds:Hide()
            f.dotSocket[index] = ds
        end

        local note = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        note:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", GEAR_NOTE_LEFT, GEAR_NOTE_BOTTOM)
        note:SetWidth(GEAR_NOTE_WIDTH)
        note:SetJustifyH("LEFT")
        f.note = note

        -- Escape closes this panel -- through the BROWSER's escape handler,
        -- not through a registration of its own.
        --
        -- RegisterEscapeClose registers ONE escape owner: the FIRST frame
        -- that asks for it. The browser asks first (CreateUI, at the end of
        -- building the window), and the panel is created by the browser's own
        -- row handlers, so the owner is always the browser by the time this
        -- panel exists.
        --
        -- The panel does not need a registration of its own: the owner's
        -- handler closes the gear panel FIRST and leaves the browser up, and
        -- only closes the browser when no panel is open
        -- (RankBrowser.RegisterEscapeClose's closeIfShown).
        --
        -- Registering the panel here would be a no-op -- the owner is already
        -- set -- AND it would put the panel into UISpecialFrames, where the
        -- engine would hide the panel behind the owner's handler and take the
        -- browser down with it. So the panel is deliberately NOT registered.
        gearFrame = f
    else
        adoptGearParent()
    end

    local name = entry.name or L["LB_TIP_UNKNOWN"] or "Unknown"
    gearFrame.title:SetText(string.format(L["GEAR_TITLE"] or "%s's Gear", name))

    -- The Scanner cache is in-memory only, so a player scanned in a previous
    -- session has no gear to show. That is stated rather than shown as empty
    -- rows, because eleven blank lines read as a bug.
    local scanner = namespace.Scanner
    local cached = type(scanner) == "table"
        and type(scanner.GetRemote) == "function"
        and scanner.GetRemote(entry.guid)
        or nil
    local slots = type(cached) == "table"
        and type(cached.revision) == "table"
        and cached.revision.slots
        or nil

    -- Render precedence: fresh session > persisted gear > not-scanned.
    -- Session truth comes from the Scanner cache (in-memory only). When it
    -- has nothing renderable, the bounded RankDB gear table -- filled by D
    -- ingest and by the owner's own scans -- renders instead, dimmed with an
    -- age note so staleness reads as staleness, never as a live inspect.
    -- Persisted rows carry IDs only (never names, links, enchants or gems);
    -- an unresolvable ID renders the same item:<id> literal the
    -- session-missing path uses, never a spinner. Synced IDs feed the panel
    -- only: no GS is ever recomputed from them.
    local persistedMap, persistedT = nil, 0
    local sessionShown = (function()
        if type(slots) ~= "table" then
            return false
        end
        for index = 1, #SLOT_ROWS do
            if slotValueText(slots[SLOT_ROWS[index].slot]) then
                return true
            end
        end
        return false
    end)()
    if not sessionShown then
        local db = namespace.RankDB
        if type(db) == "table"
            and type(db.GetGear) == "function"
            and type(db.ParseGearIDs) == "function" then
            local row = db.GetGear(entry.guid)
            if type(row) == "table" and type(row.ids) == "string" then
                local ordered = db.ParseGearIDs(row.ids)
                if ordered then
                    persistedMap = {}
                    for _, pair in ipairs(ordered) do
                        local slotText, itemText = pair:match("^(%d+)=(%d+)$")
                        local slotID = tonumber(slotText)
                        local itemID = tonumber(itemText)
                        -- Zero is not an item (stored rows predate the
                        -- positive-ID rule): skip, never render "item:0".
                        if slotID and slotID > 0 and itemID and itemID > 0 then
                            persistedMap[slotID] = itemText
                        end
                    end
                    persistedT = tonumber(row.t) or 0
                end
            end
        end
    end

    local function setDot(tex, show, red, green, blue)
        if type(tex) ~= "table" then return end
        if show then
            if type(tex.SetColorTexture) == "function" then
                tex:SetColorTexture(red, green, blue, 1)
            end
            if type(tex.Show) == "function" then
                tex:Show()
            end
        else
            if type(tex.Hide) == "function" then
                tex:Hide()
            end
        end
    end

    local anyItem, anyPersisted = false, false
    for index = 1, #SLOT_ROWS do
        local spec = SLOT_ROWS[index]
        local slot = type(slots) == "table" and slots[spec.slot] or nil
        local value = slot and slotValueText(slot, true) or nil
        if value then
            anyItem = true
            gearFrame.rows[index]:SetText(slotLabel(spec) .. ":  " .. value)
            -- W8: suffix + dots render only from a live revision, never from
            -- persisted IDs (which carry no iLvl, enchant or gem data).
            local enchanted, socketed = slotDots(slot)
            setDot(gearFrame.dotEnchant[index], enchanted, 0.83, 0.66, 0.29)
            setDot(gearFrame.dotSocket[index], socketed, 0.35, 0.82, 0.48)
        elseif persistedMap and persistedMap[spec.slot] then
            anyPersisted = true
            gearFrame.rows[index]:SetText("|cff808080" .. slotLabel(spec)
                .. ":  item:" .. persistedMap[spec.slot] .. "|r")
            setDot(gearFrame.dotEnchant[index], false)
            setDot(gearFrame.dotSocket[index], false)
        else
            gearFrame.rows[index]:SetText("|cff808080" .. slotLabel(spec) .. "|r")
            setDot(gearFrame.dotEnchant[index], false)
            setDot(gearFrame.dotSocket[index], false)
        end
    end

    if anyItem then
        gearFrame.note:SetText("")
    elseif anyPersisted then
        -- English literal with the existing relative-time fallback: Stage 4
        -- adds zero locale keys, and slot labels already localize through
        -- the client globals.
        if persistedT > 0 then
            gearFrame.note:SetText("Last synced "
                .. formatRelativeTime(persistedT) .. " (item IDs only)")
        else
            gearFrame.note:SetText("Synced gear (item IDs only)")
        end
    elseif cached ~= nil then
        -- The session saw this player but yielded no renderable gear (scan in
        -- flight, failed, or uncached) and nothing persisted exists. That is
        -- "unavailable right now", not "never scanned" -- the old text claimed
        -- the latter and read as a verdict on the player.
        gearFrame.note:SetText(L["GEAR_DATA_UNAVAILABLE"]
            or "Gear data is unavailable for this player right now. Press Scan now in the leaderboard, then try again.")
    else
        gearFrame.note:SetText(L["GEAR_NOT_SCANNED"]
            or "This player has not been scanned yet, so no gear is available.")
    end

    gearFrame:Show()
    -- Remember WHICH entry the panel is showing, so a rebuild can re-render
    -- it from live data instead of leaving the old rows on screen.
    gearEntry = entry
    return true
end

function RankBrowser.ScrollToTop()
    local f = rankFrame
    if not f then
        RankBrowser.Toggle()
        return
    end
    if not f:IsShown() then
        RankBrowser.Toggle()
        return
    end
    jumpToPlayerPending = false
    scrollToOffset(f.scrollFrame, 0)
    RankBrowser.UpdateUI()
end

function RankBrowser.TrackToPlayer()
    jumpToPlayerPending = true
    if rankFrame and rankFrame:IsShown() then
        RankBrowser.UpdateUI()
    else
        RankBrowser.Toggle()
    end
end

-- ---------------------------------------------------------------------------
-- Public: render
-- ---------------------------------------------------------------------------

-- "My Rank" feedback (A4/G8).
--
-- Jumping to a player the database does not hold lands on row 1, which reads
-- as the button doing nothing. The footer states why instead -- but only for
-- as long as the note is news: where timers exist it restores itself after a
-- couple of seconds, and a successful jump clears it outright. `token`
-- invalidates a pending restore when a newer notice supersedes the old one, so
-- a stale timer can never wipe a fresh note.
local footerNotice = nil
local footerNoticeToken = 0

local function setFooterNotice(text)
    footerNotice = text
    footerNoticeToken = footerNoticeToken + 1
    if text == nil then
        return
    end
    local token = footerNoticeToken
    local timer = _G.C_Timer
    if type(timer) == "table" and type(timer.After) == "function" then
        timer.After(2, function()
            if token == footerNoticeToken then
                footerNotice = nil
                RankBrowser.UpdateUI()
            end
        end)
    end
end

-- Publish the empty state: the line under the list that says why the list
-- holds no rows.
--
-- ONE helper, so the "no database" path and the "no records" path cannot
-- disagree about how the state is published -- and so the "no database" path
-- can publish it at all, which it could not when the state was written out
-- inline at the END of UpdateUI: the early return for a missing database
-- skipped it, and the window was left with headers, an empty table and no
-- explanation at all.
local function publishEmptyState(text)
    if not emptyStateText then
        return false
    end
    emptyStateText:SetText(text)
    emptyStateText:SetShown(true)
    return true
end

function RankBrowser.UpdateUI()
    if not rankFrame or not rankFrame:IsShown() then return end

    local db = namespace.RankDB
    if not db or type(db.GetLeaderboard) ~= "function" then
        -- A bare window is not an answer. The database is missing, so the
        -- list cannot be filled, and the player is told WHICH thing is
        -- missing instead of being left with an empty table that reads as
        -- "nobody is ranked".
        publishEmptyState(L["LB_DB_UNAVAILABLE"]
            or "The rank database is unavailable, so no rankings can be shown.")
        return
    end

    local data, totalCount = db.GetLeaderboard(nil, "All", currentClass, currentSearch, currentGuild)
    data = data or {}
    totalCount = totalCount or 0

    -- The GearScore-rank map is built from the GearScore order regardless of
    -- how the list is currently sorted, so the `#` column always means the same
    -- thing.
    local gsRanks = buildGearScoreRanks(data)
    -- The display order follows the current column AND direction (A2/G2).
    -- GearScore-descending is what RankDB already hands back, so the common
    -- case passes that array straight through.
    local view
    if currentSort == "gs" and not sortAsc then
        view = data
    else
        view = sortEntries(data, currentSort, sortAsc)
    end

    -- Best-in-view, so a colour means "how good is this HERE". Computed from
    -- the whole filtered set, not the visible page, so scrolling does not
    -- re-colour the same player. `totalCount` is the pool the percentile rank
    -- is measured against.
    viewBestGS, viewBestILVL, viewTotal = 0, 0, totalCount
    local viewSumGS = 0
    for index = 1, #data do
        local entry = data[index]
        if type(entry) == "table" then
            local gs = tonumber(entry.gs)
            local ilvl = tonumber(entry.ilvl)
            if gs and gs > viewBestGS then viewBestGS = gs end
            if ilvl and ilvl > viewBestILVL then viewBestILVL = ilvl end
            if gs then viewSumGS = viewSumGS + gs end
        end
    end

    -- W6 summary strip: pool size, top GS, realm-average GS over the fetched
    -- view (one piggybacked linear pass, no stored aggregate). Pool 0 stays
    -- hidden -- the empty state speaks; the strip never reports "0 players".
    if statStrip then
        if totalCount == 0 then
            statStrip:Hide()
        else
            local avg = (#data > 0) and math.floor(viewSumGS / #data + 0.5) or 0
            statStrip:SetText(string.format(
                L["LB_STAT_STRIP"] or "%d players | Top %d | Avg %d",
                totalCount, viewBestGS, avg))
            statStrip:Show()
        end
    end

    local scrollFrame = rankFrame.scrollFrame
    local maxOffset = getMaxOffset(totalCount)

    -- Consume the jump request exactly once.
    local jumpNow = jumpToPlayerPending
    jumpToPlayerPending = false

    local offset
    if jumpNow then
        -- Jump by the player's position in the CURRENT view, so "open on my
        -- rank" lands on the player regardless of the sort last chosen.
        local playerIndex = findPlayerRowIndex(view)
        if playerIndex then
            offset = math.min(maxOffset, math.max(0, playerIndex - math.floor(NUM_ROWS / 2)))
            setFooterNotice(nil)
        else
            -- The player is not in this view -- no record at all, or filtered
            -- out. Landing silently on row 1 looks like a broken button, so
            -- the footer says why instead, transiently (A4/G8).
            offset = 0
            setFooterNotice(L["LB_NOT_ESTABLISHED"] or "Not ranked yet")
        end
        scrollToOffset(scrollFrame, offset)
    else
        offset = 0
        if scrollFrame and type(_G.FauxScrollFrame_GetOffset) == "function" then
            offset = _G.FauxScrollFrame_GetOffset(scrollFrame)
        end
        offset = math.min(math.max(0, offset), maxOffset)
    end

    if scrollFrame and type(_G.FauxScrollFrame_Update) == "function" then
        _G.FauxScrollFrame_Update(scrollFrame, totalCount, NUM_ROWS, rowHeight())
    end

    local myGUID = getPlayerGUID()

    -- W9 focus anchor: the last rendered view is what keyboard movement walks,
    -- and a re-sort re-anchors the focused ENTRY by guid (or clears it when
    -- the entry left the view) -- never a stale row index.
    lastView = view
    if focusedEntry then
        local found = nil
        for i = 1, #view do
            if type(view[i]) == "table" and view[i].guid == focusedEntry.guid then
                found = view[i]
                break
            end
        end
        focusedEntry = found
    end

    for i = 1, NUM_ROWS do
        local index = offset + i
        local row = rowFrames[i]
        if row then
            local entry = view[index]
            if entry then
                renderRow(row, entry, index, gsRanks[entry.guid], myGUID)
            else
                row.isPlayer = false
                row.focused = false
                row.entry = nil
                row:Hide()
            end
        end
    end
    refreshFocusFlags()

    -- State line under the list. First-run and no-match are different stories
    -- and now say different things; a database holding only the player gets
    -- its own line, because "nobody is ranked but you" otherwise reads as
    -- broken (A1/G1). All three strings already ship translated in every
    -- locale -- only the choice among them is new.
    if emptyStateText then
        if totalCount == 0 then
            local filtersActive = currentClass ~= "ALL" or currentSearch ~= ""
                or currentGuild ~= ""
            if filtersActive then
                publishEmptyState(L["LB_EMPTY_FILTERS"] or "No players match the current filters.")
            else
                publishEmptyState(L["LB_EMPTY"] or "No records yet. Scores sync while you play.")
            end
        elseif totalCount == 1 and currentClass == "ALL" and currentSearch == ""
            and myGUID ~= nil and type(view[1]) == "table" and view[1].guid == myGUID then
            publishEmptyState(L["LB_ONLY_YOU"] or "Only your own character is registered on this realm so far.")
        else
            emptyStateText:Hide()
        end
    end

    -- Footer: the player's personal standing plus the size of the pool.
    -- GetPlayerRank returns four values, not a table.
    if rankFrame.footerText and type(db.GetPlayerRank) == "function" then
        local ovRank, fRank, cRank, totalTracked
        if myGUID then
            ovRank, fRank, cRank, totalTracked = db.GetPlayerRank(myGUID)
        end
        if ovRank then
            rankFrame.footerText:SetText(string.format(
                L["LB_FOOTER_STANDING"]
                    or "Your Standing: #%d Overall | #%d Faction | #%d Class  -  %d players tracked",
                ovRank, fRank or ovRank, cRank or ovRank, totalTracked or 0))
            rankFrame.footerText:SetTextColor(TEXT_R, TEXT_G, TEXT_B)
        else
            rankFrame.footerText:SetText(string.format(
                L["LB_FOOTER_NO_RANK"] or "%d players tracked - you have no ranking yet",
                totalTracked or totalCount))
            rankFrame.footerText:SetTextColor(MUTED_R, MUTED_G, MUTED_B)
        end
    end

    -- A transient "My Rank" note overrides the standing line for its beat
    -- (A4/G8). Brand-coloured so it reads as feedback rather than as the
    -- standing line it replaces.
    if footerNotice and rankFrame.footerText then
        rankFrame.footerText:SetText(footerNotice)
        rankFrame.footerText:SetTextColor(BRAND_R, BRAND_G, BRAND_B)
    end
end

-- ---------------------------------------------------------------------------
-- Row construction
-- ---------------------------------------------------------------------------

local function createRow(parent, index)
    local g = _G
    local row = g.CreateFrame("Button", nil, parent)
    row:SetSize(ROW_WIDTH, rowHeight())
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", ROW_LEFT, rowTop() - (index - 1) * rowHeight())
    row.isPlayer = false
    row.hovered = false
    row.focused = false

    -- Blizzard list highlight (W3): the standard QuestTitleHighlight texture
    -- behind the brand overlay. Guarded: without the method the overlay-only
    -- hover below is visually identical to today.
    local setHighlight = widgetMethod(row, "SetHighlightTexture")
    if type(setHighlight) == "function" then
        pcall(setHighlight, row, "Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    end

    -- Zebra stripe.
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    if index % 2 == 0 then
        bg:SetColorTexture(1, 1, 1, 0.05)
    else
        bg:SetColorTexture(0, 0, 0, 0.15)
    end

    -- Hover / "you are here" overlay, drawn above the stripe.
    local overlay = row:CreateTexture(nil, "BACKGROUND")
    overlay:SetAllPoints()
    overlay:SetColorTexture(BRAND_R, BRAND_G, BRAND_B, 1)
    overlay:SetAlpha(0)
    row.overlay = overlay

    -- Thin class-colour bar down the left edge.
    local classBar = row:CreateTexture(nil, "ARTWORK")
    classBar:SetPoint("LEFT", row, "LEFT", 0, 0)
    classBar:SetSize(3, rowHeight())
    classBar:SetColorTexture(1, 1, 1, 0.85)
    row.classBar = classBar

    -- Specialization icon, immediately left of the spec text.
    --
    -- Anchored to the SPEC COLUMN, not to a fixed offset: the spec text
    -- starts at the column's x, so the icon's right edge sits ICON_GAP to the
    -- left of it and the two can never overlap.
    local specColumn = COLUMN_BY_KEY["spec"]
    local specIconTexture = row:CreateTexture(nil, "ARTWORK")
    specIconTexture:SetPoint(
        "RIGHT",
        row,
        "LEFT",
        specColumn.x - ICON_GAP,
        0
    )
    specIconTexture:SetSize(14, 14)
    specIconTexture:Hide()
    row.specIconTexture = specIconTexture

    -- Class icon beside the row name (W2): same 14px treatment as the spec
    -- icon, resolved at render through GetClassAtlas. Hidden until then.
    local nameColumn = COLUMN_BY_KEY["name"]
    local classIconTexture = row:CreateTexture(nil, "ARTWORK")
    classIconTexture:SetPoint(
        "RIGHT",
        row,
        "LEFT",
        nameColumn.x - ICON_GAP,
        0
    )
    classIconTexture:SetSize(14, 14)
    classIconTexture:Hide()
    row.classIconTexture = classIconTexture
    row.hasClassIcon = false

    -- Fresh-row tick (W7): a 2px brand-colour edge reusing the tab
    -- highlight's colour approach. Paint-only, never stored, never sorted on.
    local freshTick = row:CreateTexture(nil, "ARTWORK")
    freshTick:SetPoint("LEFT", row, "LEFT", 0, 0)
    freshTick:SetSize(2, rowHeight())
    freshTick:SetColorTexture(BRAND_R, BRAND_G, BRAND_B, 0.9)
    freshTick:Hide()
    row.freshTick = freshTick

    for _, col in ipairs(COLUMNS) do
        local fs = row:CreateFontString(nil, "ARTWORK", col.template)
        fs:SetPoint("LEFT", row, "LEFT", col.x, 0)
        fs:SetWidth(col.width)
        fs:SetJustifyH(col.justify)
        row[col.key .. "Text"] = fs
    end

    -- "YOU" marker on the player's row.
    --
    -- Anchored to the ROW's right edge, so it stays clear of the last column
    -- however wide the columns get.
    local youTag = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    youTag:SetPoint("LEFT", row, "LEFT", ROW_WIDTH - 36, 0)
    youTag:SetWidth(32)
    youTag:SetJustifyH("CENTER")
    youTag:SetText(L["LB_YOU"] or "YOU")
    youTag:SetTextColor(BRAND_R, BRAND_G, BRAND_B)
    youTag:Hide()
    row.youTag = youTag

    -- Hover: highlight plus the detail tooltip.
    -- SetScript, not HookScript -- these are fresh rows with no template
    -- scripts, and HookScript raises on an undeclared script.
    row:SetScript("OnEnter", function(self)
        self.hovered = true
        applyRowOverlay(self)
        showRowTooltip(self, self.entry)
    end)
    row:SetScript("OnLeave", function(self)
        self.hovered = false
        applyRowOverlay(self)
        hideRowTooltip()
    end)

    -- Click opens the gear panel. The row keeps its own entry, so the handler
    -- needs no lookup and cannot open the wrong player after a re-sort -- the
    -- classic bug with index-based handlers.
    row:SetScript("OnClick", function(self)
        return RankBrowser.ShowGear(self.entry)
    end)

    return row
end

-- ---------------------------------------------------------------------------
-- UI construction
-- ---------------------------------------------------------------------------

-- Sort indicator: a brand underline beneath whichever column is active, plus a
-- one-line readout so the active order is never guesswork. Declared at module
-- scope (not inside CreateUI) so it is a local, not a stray global.
local function refreshSortHeaders()
    for _, col in ipairs(COLUMNS) do
        local header = col.header
        if header and header.sortHighlight then
            if currentSort == col.key then
                header.sortHighlight:Show()
            else
                header.sortHighlight:Hide()
            end
        end
    end
    if sortHint then
        -- The arrow reports the DIRECTION, not the column (A2/G2): it used to
        -- hard-code "up" for last-seen while the list below it sorted down.
        local arrow = sortAsc and ARROW_UP or ARROW_DOWN
        sortHint:SetText(string.format(
            L["LB_SORTED_BY"] or "Sorted by %s %s",
            SORTS[currentSort] and (L[SORTS[currentSort]] or "") or "",
            arrow))
    end
end

local function refreshClassFilterLabel()
    if not classFilterButton then return end
    if type(_G.UIDropDownMenu_SetText) == "function" then
        _G.UIDropDownMenu_SetText(classFilterButton, currentClass == "ALL" and (L["LB_FILTER_ALL"] or "All Classes") or currentClass)
    end
end

function RankBrowser.CreateUI()
    if rankFrame then return rankFrame end
    local g = _G
    if type(g.CreateFrame) ~= "function" then return nil end

    -- W10 ButtonFrame chrome: standard panel frame (portrait/inset on the
    -- Classic family, ButtonFrameBase on Mainline) with the hand-rolled
    -- DialogFrame backdrop as the pixel-identical fallback. Family inheritance
    -- differs, so no child ($parentTitle/$parentInset) is ever assumed --
    -- everything below resolves post-create behind nil-guards.
    local templateOK = false
    local ok, f = pcall(g.CreateFrame, "Frame", "TacoTipRankFrame", g.UIParent, "ButtonFrameTemplate")
    if ok and type(f) == "table" then
        templateOK = true
    else
        ok, f = pcall(g.CreateFrame, "Frame", "TacoTipRankFrame", g.UIParent, "BackdropTemplate")
    end
    if not ok or type(f) ~= "table" then
        ok, f = pcall(g.CreateFrame, "Frame", "TacoTipRankFrame", g.UIParent)
    end
    if not ok or type(f) ~= "table" then return nil end

    -- The client's CreateFrame leaves a NEW frame VISIBLE, and no template
    -- hides it.
    --
    -- Blizzard's own panels carry `hidden="true"` on the FRAME, never on the
    -- template -- origin/classic_era
    --   Interface/AddOns/Blizzard_AddOnList/AddonList.xml:120
    --     <Frame name="AddonList" enableMouse="true" inherits="ButtonFrameTemplate"
    --             mixin="AddonListMixin" hidden="true">
    --   Interface/AddOns/Blizzard_UIPanels_Game/Blizzard_GameMenu.xml
    --     (GameMenuFrame, likewise hidden="true" on the frame)
    -- and Blizzard's code creates frames and then HIDES them explicitly --
    -- origin/classic_era
    --   Interface/AddOns/Blizzard_Calendar/Classic/Blizzard_Calendar.lua
    --     eventButton = CreateFrame("Button", eventButtonPrefix..i, button,
    --         "CalendarDayEventButtonTemplate");
    --     ...
    --     eventButton:Hide();
    --
    -- So a browser window created with ButtonFrameTemplate would be ON SCREEN
    -- from the moment it was created, and the FIRST toggle would HIDE it
    -- instead of showing it. The window is opened by a toggle, so it is hidden
    -- here, explicitly, rather than relying on a default the client does not
    -- have.
    if type(f.Hide) == "function" then
        pcall(f.Hide, f)
    end

    -- W11 density constrains the W10 geometry rework: the setting is read once
    -- per construction so the inset math below is parameterized once. Default
    -- OFF keeps today's geometry; a non-boolean value repairs to compact.
    --
    -- It is read BEFORE the frame is sized, because the table band's height
    -- is the rows and the rows' height depends on it.
    do
        local comfortable = false
        local core = namespace.Core
        local getSettings = type(core) == "table" and core.GetSettings or nil
        if type(getSettings) == "function" then
            local okSettings, live = pcall(getSettings)
            if okSettings and type(live) == "table" and live.comfortableRows == true then
                comfortable = true
            end
        end
        currentRowHeight = comfortable and 32 or ROW_HEIGHT
    end
    chromePad = templateOK and 28 or 0

    -- The frame's height is the sum of the bands, and the band offsets come
    -- from the same sum -- so a band can never be given space another band
    -- already has, and the table band is exactly the rows.
    applyBandLayout(f)
    f:SetPoint("CENTER", g.UIParent, "CENTER", 0, 0)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    -- Above the Blizzard settings surfaces (GameMenu DIALOG-toplevel on
    -- Classic, SettingsPanel HIGH-toplevel on Mainline): applied here so the
    -- RebuildUI path gets it too, not only Toggle.
    applyTopmost(f, BROWSER_STRATA, BROWSER_LEVEL)

    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true,
            tileSize = 32,
            edgeSize = 24,
            insets = { left = 8, right = 8, top = 8, bottom = 8 },
        })
    end
    -- Explicit alpha matching the gear panel (PANEL_BACKDROP_ALPHA), so the
    -- two panels read as one surface.
    if type(f.SetBackdropColor) == "function" then
        f:SetBackdropColor(0, 0, 0, PANEL_BACKDROP_ALPHA)
    end

    -- Title. When the ButtonFrame template already provides its own title
    -- text, reuse it (set the text, create nothing); otherwise build ours in
    -- the title band.
    if templateTitle then
        providedTitle:SetText(L["LB_TITLE"] or "TacoTip GearScore Leaderboard")
    else
        local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", f, "TOPLEFT", ROW_LEFT, titleTop())
        title:SetText(L["LB_TITLE"] or "TacoTip GearScore Leaderboard")
    end

    -- Same for the close button: the template's own wins when present.
    if type(rawget(g, "TacoTipRankFrameCloseButton")) ~= "table" then
        local close = g.CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    end

    -- Whole-server scope. There is deliberately NO Alliance/Horde split: the
    -- leaderboard ranks the entire realm, and a faction filter would only ever
    -- hide the players you want to compare yourself against.
    local scopeLabel = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    scopeLabel:SetPoint("TOPLEFT", f, "TOPLEFT", ROW_LEFT, controlTop())
    scopeLabel:SetText(L["LB_REALM"] or "Whole Realm")

    -- Active-scope underline, sitting under the scope label.
    tabHighlight = f:CreateTexture(nil, "ARTWORK")
    tabHighlight:SetColorTexture(BRAND_R, BRAND_G, BRAND_B, 0.9)
    tabHighlight:SetHeight(2)
    tabHighlight:SetPoint("BOTTOMLEFT", scopeLabel, "BOTTOMLEFT", 0, -3)
    tabHighlight:SetPoint("BOTTOMRIGHT", scopeLabel, "BOTTOMRIGHT", 0, -3)

    -- W6 summary strip: one muted line under the control row answering "how
    -- big is this board" (pool size, top GS, realm-average GS), recomputed per
    -- render from rows already in hand. Hidden until the first UpdateUI paint
    -- (the footer carries LB_LOADING before that) and whenever the pool is
    -- empty (the empty state speaks; the strip stays silent).
    statStrip = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    statStrip:SetPoint("TOPLEFT", f, "TOPLEFT", ROW_LEFT, statTop())
    statStrip:SetText("")
    statStrip:SetTextColor(MUTED_R, MUTED_G, MUTED_B)
    statStrip:Hide()
    f.statStrip = statStrip

    -- Search box (right of the control row). W1 SearchBoxTemplate: the
    -- standard search affordance (magnifier, clear button, instruction text),
    -- with the current InputBoxTemplate construction as the fallback.
    local search
    local okSearch, searchFrame = pcall(g.CreateFrame, "EditBox", nil, f, "SearchBoxTemplate")
    if okSearch and type(searchFrame) == "table" then
        search = searchFrame
    else
        -- Same three-level shape as the W10 chrome above: InputBox fallback,
        -- then a plain EditBox last resort. Both-templates-absent must degrade,
        -- never raise -- total failure refuses construction like line 1704.
        okSearch, searchFrame = pcall(g.CreateFrame, "EditBox", nil, f, "InputBoxTemplate")
        if okSearch and type(searchFrame) == "table" then
            search = searchFrame
        else
            okSearch, searchFrame = pcall(g.CreateFrame, "EditBox", nil, f)
            if not okSearch or type(searchFrame) ~= "table" then return nil end
            search = searchFrame
        end
    end
    search:SetSize(130, 22)
    search:SetPoint("TOPRIGHT", f, "TOPRIGHT", -40, controlTop())
    if search.SetAutoFocus then
        search:SetAutoFocus(false)
    end
    -- W5 debounce: one 0.2s C_Timer flush per keystroke burst instead of a
    -- full re-sort per keystroke on 20k-row realms. Guarded: without C_Timer
    -- the search renders synchronously, exactly today's behaviour.
    local function flushSearch()
        searchFlushPending = false
        RankBrowser.UpdateUI()
    end
    search:SetScript("OnTextChanged", function(self)
        currentSearch = self:GetText() or ""
        local timer = _G.C_Timer
        if type(timer) == "table" and type(timer.After) == "function" then
            if not searchFlushPending then
                searchFlushPending = true
                timer.After(0.2, flushSearch)
            end
        else
            RankBrowser.UpdateUI()
        end
    end)
    local searchLabel = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    searchLabel:SetPoint("RIGHT", search, "LEFT", -8, 0)
    searchLabel:SetText(L["LB_SEARCH"] or "Search:")

    -- Guild text filter (Stage 3), between the class dropdown and the search
    -- box. A second text input reusing the search-box pattern (live
    -- OnTextChanged -> re-render). NOT a dropdown: a distinct-guild dropdown
    -- on a 20k realm is unbounded chrome. Guild names are unique per realm,
    -- so no realm+guild composite key is needed. Same m2 fallback shape as
    -- the search box above: InputBox, then a plain EditBox last resort.
    local guildSearch
    do
        local okGuild, guildFrame = pcall(g.CreateFrame, "EditBox", nil, f, "InputBoxTemplate")
        if okGuild and type(guildFrame) == "table" then
            guildSearch = guildFrame
        else
            okGuild, guildFrame = pcall(g.CreateFrame, "EditBox", nil, f)
            if not okGuild or type(guildFrame) ~= "table" then return nil end
            guildSearch = guildFrame
        end
    end
    guildSearch:SetSize(130, 22)
    guildSearch:SetPoint("RIGHT", searchLabel, "LEFT", -8, 0)
    if guildSearch.SetAutoFocus then
        guildSearch:SetAutoFocus(false)
    end
    guildSearch:SetScript("OnTextChanged", function(self)
        currentGuild = self:GetText() or ""
        RankBrowser.UpdateUI()
    end)
    local guildLabel = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    guildLabel:SetPoint("RIGHT", guildSearch, "LEFT", -8, 0)
    guildLabel:SetText(L["LB_GUILD"] or "Guild:")

    -- Class filter dropdown, between the tabs and the guild filter box.
    local classDD = g.CreateFrame("Frame", "TacoTipRankClassFilter", f, "UIDropDownMenuTemplate")
    classDD:SetPoint("RIGHT", guildLabel, "LEFT", -24, 0)
    classFilterButton = classDD
    if type(g.UIDropDownMenu_Initialize) == "function" and type(g.UIDropDownMenu_AddButton) == "function" then
        -- Canonical UIDropDownMenu pattern: build a FRESH info table per entry
        -- and hand it straight to AddButton. Building an info.list and then
        -- looping AddButton over it double-adds every entry, because AddButton
        -- is what appends to the menu.
        g.UIDropDownMenu_Initialize(classDD, function()
            local function entryFor(text, value)
                -- W2 dropdown icons: the class atlas beside each entry,
                -- resolved at menu build through GetClassAtlas. Nil when the
                -- client cannot resolve -- the menu then reads exactly as
                -- before, text only.
                local icon = nil
                if value ~= "ALL" then
                    icon = classAtlasOf(value)
                end
                return {
                    text = text,
                    -- The canonical UIDropDownMenu `value`, kept alongside the
                    -- localized text so a selection can be tracked (and
                    -- tested) without depending on which language is showing.
                    value = value,
                    icon = icon,
                    func = function()
                        currentClass = value
                        refreshClassFilterLabel()
                        RankBrowser.UpdateUI()
                    end,
                }
            end
            g.UIDropDownMenu_AddButton(entryFor(L["LB_FILTER_ALL"] or "All Classes", "ALL"))
            for _, className in ipairs(CLASS_ORDER) do
                -- Localized class name, raw token as a defensive fallback: every
                -- CLASS_ key exists in enUS now (EVOKER included), so the `or`
                -- branch is unpinned by the harness — it stays so a future
                -- class token can never render as a blank (A5/G4).
                g.UIDropDownMenu_AddButton(entryFor(L["CLASS_" .. className] or className, className))
            end
        end, nil, nil)
    end
    refreshClassFilterLabel()

    -- Column header strip, built from the same COLUMNS table as the rows so the two
    -- can never drift apart. Sortable columns are Buttons laid exactly over
    -- their label; the rest stay plain text.
    for _, col in ipairs(COLUMNS) do
        local isSortable = false
        for _, key in ipairs(SORTABLE_COLUMNS) do
            if key == col.key then isSortable = true end
        end

        local header
        if isSortable then
            header = g.CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
            header:SetSize(col.width, 20)
            -- The header band is 24 tall and the button is 20, so the button
            -- sits 2px down from the band's top. The plain-text headers below
            -- are placed so their TEXT lines up with the button's text.
            header:SetPoint("TOPLEFT", f, "TOPLEFT", ROW_LEFT + col.x, headerTop() - 2)
            header:SetText(L[col.label] or col.fallback or col.label)
            header:SetScript("OnClick", function()
                if currentSort == col.key then
                    -- Repeat click on the ACTIVE column flips the direction
                    -- instead of re-applying the same one-way sort (A2/G2).
                    sortAsc = not sortAsc
                else
                    currentSort = col.key
                    -- Every column's default order is descending, the order
                    -- it ships with.
                    sortAsc = false
                end
                refreshSortHeaders()
                RankBrowser.ScrollToTop()
            end)
            header:SetScript("OnEnter", function()
                if header.sortHighlight then
                    header.sortHighlight:Show()
                end
            end)
            header:SetScript("OnLeave", function()
                if header.sortHighlight and currentSort ~= col.key then
                    header.sortHighlight:Hide()
                end
            end)

            -- Brand underline marking the active sort column.
            --
            -- Built HERE, inside the branch that knows this is a Button, and
            -- NOT in a later pass keyed on `header.SetSize`. FontStrings
            -- inherit REGION, which defines SetSize, so a SetSize test does not
            -- discriminate: a FontString header passed that guard and then
            -- raised on CreateTexture. Sortability is the only honest test.
            local underline = header:CreateTexture(nil, "ARTWORK")
            underline:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, -1)
            underline:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, -1)
            underline:SetHeight(2)
            underline:SetColorTexture(BRAND_R, BRAND_G, BRAND_B, 0.9)
            underline:Hide()
            header.sortHighlight = underline
        else
            header = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
            -- Aligned with the sortable buttons' text, not with their top: the
            -- button's text sits in the middle of its 20px box, so the plain
            -- header is 6px below the band's top.
            header:SetPoint("TOPLEFT", f, "TOPLEFT", ROW_LEFT + col.x, headerTop() - 6)
            header:SetWidth(col.width)
            header:SetJustifyH(col.justify)
            header:SetText(L[col.label] or col.fallback or col.label)
        end
        col.header = header
        f.headerWidgets = f.headerWidgets or {}
        f.headerWidgets[#f.headerWidgets + 1] = header
    end

    -- One-line sort readout, created before the first refresh so the initial
    -- state renders correctly without a special-case call.
    --
    -- It sits in its OWN band (hintTop), between the stat strip above it and
    -- the column headers below it. It used to sit at `rowTop() + 26`, which is
    -- the y the sortable header buttons occupy -- the readout was drawn
    -- straight through the header row.
    sortHint = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    sortHint:SetPoint("TOPLEFT", f, "TOPLEFT", ROW_LEFT, hintTop())
    -- Exposed on the frame like statStrip / footerText / progressBar, so the
    -- harness can read the band the readout actually sits in.
    f.sortHint = sortHint
    refreshSortHeaders()

    -- Thin separator, at the BOTTOM of the header band -- inside the band
    -- that owns it, not floating between the headers and the rows.
    local separator = f:CreateTexture(nil, "ARTWORK")
    separator:SetPoint("TOPLEFT", f, "TOPLEFT", ROW_LEFT, headerTop() - BAND_HEADER + 1)
    separator:SetPoint("TOPRIGHT", f, "TOPRIGHT", -40, headerTop() - BAND_HEADER + 1)
    separator:SetHeight(1)
    separator:SetColorTexture(1, 1, 1, 0.15)

    -- FauxScrollFrame hosting the virtual rows. It spans the TABLE band
    -- exactly -- the rows and nothing else -- so the last row's bottom meets
    -- the progress band's top and cannot collide with the progress rail.
    local sf = g.CreateFrame("ScrollFrame", "TacoTipRankScrollFrame", f, "FauxScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", f, "TOPLEFT", ROW_LEFT, rowTop())
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -40, tableBottom())
    sf:SetScript("OnVerticalScroll", function(self, ofs)
        if type(g.FauxScrollFrame_OnVerticalScroll) == "function" then
            g.FauxScrollFrame_OnVerticalScroll(self, ofs, rowHeight(), RankBrowser.UpdateUI)
        end
    end)
    f.scrollFrame = sf

    -- Rows.
    for i = 1, NUM_ROWS do
        rowFrames[i] = createRow(f, i)
    end

    -- State line under the list: first-run, no-match or only-you (A1/G1; the
    -- message is chosen per render in UpdateUI). Exposed on the frame like
    -- footerText/progressBar so the harness can read the state it renders.
    emptyStateText = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    emptyStateText:SetPoint("TOP", sf, "TOP", 0, -math.floor(tableBandHeight / 2))
    emptyStateText:SetText(L["LB_EMPTY_FILTERS"] or "No players match the current filters.")
    emptyStateText:SetTextColor(MUTED_R, MUTED_G, MUTED_B)
    emptyStateText:Hide()
    f.emptyStateText = emptyStateText

    -- Footer band: personal standing (left) and navigation buttons (right).
    -- Both are anchored to the band's own bottom, so the band owns them and
    -- nothing else can land in the same space.
    local footer = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    footer:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", ROW_LEFT, footerBottom() + 4)
    footer:SetText(L["LB_LOADING"] or "Loading rankings...")
    f.footerText = footer

    -- Footer buttons, measured from the frame's RIGHT edge.
    --
    -- The three buttons sit in the footer's right-hand corner, and their hit
    -- rects are what the player clicks, so they must not overlap. They used
    -- to: "Top" (80 wide) was anchored 122px from the right, so it occupied
    -- 122..202, and "My Rank" (90 wide) was anchored 34px from the right, so
    -- it occupied 34..124 -- a 2px overlap on 122..124. The two buttons
    -- therefore shared a strip of pixels, and which of them a click at that
    -- strip reached was a matter of frame order.
    --
    -- "Top" now sits at 126, which leaves a 2px gutter between it and "My
    -- Rank" (124) and a 16px gutter before "Scan now" (222).
    local topButton = g.CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    topButton:SetSize(80, 22)
    topButton:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -126, footerBottom())
    topButton:SetText(L["LB_TOP"] or "Top")
    topButton:SetScript("OnClick", function()
        RankBrowser.ScrollToTop()
    end)

    local meButton = g.CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    meButton:SetSize(90, 22)
    meButton:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -34, footerBottom())
    meButton:SetText(L["LB_MY_RANK_ARROW"] or "My Rank")
    meButton:SetScript("OnClick", function()
        RankBrowser.TrackToPlayer()
    end)

    -- Scan entry point. The Options page carries the same control and both call
    -- RankBrowser.StartScan / read RankBrowser.RefreshProgress, so the two
    -- surfaces cannot disagree about whether a scan is running.
    local scanButton = g.CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    scanButton:SetSize(100, 22)
    scanButton:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -222, footerBottom())
    scanButton:SetText(L["LB_SCAN"] or "Scan now")
    scanButton:SetScript("OnClick", function()
        RankBrowser.StartScan()
    end)
    f.scanButton = scanButton

    -- Progress band: the scan rail, and the completion line that appears
    -- above it when a scan ends. Hidden when idle so the window does not
    -- carry a dead grey rail at all times.
    --
    -- The rail sits at the band's bottom and the completion line above it,
    -- with the band's own slack between the two and the table above.
    local bar = g.CreateFrame("StatusBar", nil, f)
    bar:SetSize(ROW_WIDTH, PROGRESS_BAR_HEIGHT)
    bar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", ROW_LEFT, progressBottom())
    -- SetStatusBarTexture is a real StatusBar method, but a guarded call costs
    -- nothing and this window must never fail to open because one method was
    -- absent -- the same rule the rest of this file follows for frame methods.
    if type(bar.SetStatusBarTexture) == "function" then
        bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    end
    if type(bar.SetStatusBarColor) == "function" then
        bar:SetStatusBarColor(0.66, 0.48, 0.86)
    end
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:Hide()
    f.progressBar = bar

    local progressText = bar:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    progressText:SetPoint("LEFT", bar, "LEFT", 2, 0)
    progressText:SetText("")
    bar.text = progressText

    -- Completion line, in the progress band just above the rail and clear of
    -- the footer row and of every row the list can draw. Hidden except on the
    -- scan's active->inactive edge; see announceScanComplete (A6/G6).
    local scanStatus = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    scanStatus:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", ROW_LEFT,
        progressBottom() + PROGRESS_BAR_HEIGHT + 4)
    scanStatus:SetText("")
    scanStatus:Hide()
    f.scanStatus = scanStatus

    -- Every open lands on the player's own rank.
    f:SetScript("OnShow", function()
        markSessionStart()
        jumpToPlayerPending = true
        RankBrowser.UpdateUI()
        RankBrowser.RefreshProgress()
    end)

    -- W9 keyboard navigation: Up/Down moves a focus ring across the visible
    -- rows (entry-anchored, never index-based), Enter opens the focused row's
    -- gear panel. The frame takes keyboard input behind a capability guard;
    -- arrow/Enter handling swallows propagation only while handling those
    -- keys, so chat keys are never stolen. Empty list: keys no-op, no error.
    local enableKeyboard = widgetMethod(f, "EnableKeyboard")
    if type(enableKeyboard) == "function" then
        pcall(enableKeyboard, f, true)
    end
    f:SetScript("OnKeyDown", function(_, key)
        if not f:IsShown() then
            return
        end
        if key == "Up" then
            moveFocus(-1)
        elseif key == "Down" then
            moveFocus(1)
        elseif key == "Enter" then
            if focusedEntry then
                RankBrowser.ShowGear(focusedEntry)
            end
        else
            return
        end
        local swallow = widgetMethod(f, "SetPropagateKeyboardInput")
        if type(swallow) == "function" then
            pcall(swallow, f, false)
        end
    end)

    -- Poll progress ONLY while a scan runs. An always-on OnUpdate on a window
    -- that stays open would cost frame time for a bar that is not moving, so
    -- the handler returns immediately unless RefreshProgress reports a scan in
    -- flight.
    f:SetScript("OnUpdate", function(self, elapsed)
        if not self.scanning then
            return
        end
        self.progressAccum = (self.progressAccum or 0) + (elapsed or 0)
        if self.progressAccum < 0.25 then
            return
        end
        self.progressAccum = 0
        RankBrowser.RefreshProgress()
    end)

    rankFrame = f
    RankBrowser.RegisterEscapeClose(g.CreateFrame("Frame", "TacoTipRankEscFrame"))
    return f
end

-- Escape closes the browser, the way every other Blizzard dialog does. A window
-- you can only dismiss with the mouse corner is a window people report as
-- "stuck open".
--
-- PORTABILITY NOTE, and the reason this function registers three routes.
-- Escape is dispatched DIFFERENTLY across the supported clients:
--
--   classic_era / anniversary / titanforge   Blizzard's own FrameXML uses the
--       `OnEscapePressed` FRAME SCRIPT (73 occurrences on classic_era) and the
--       engine-recognised global `UISpecialFrames`. `KEY_ESCAPE` is used ZERO
--       times in Classic Era's FrameXML -- registering for it compiles, does
--       not raise, and NEVER fires. That is a silent failure on exactly the
--       two clients this add-on primarily targets.
--
--   live / forever                            KEY_ESCAPE is present (3 uses on
--       origin/live) alongside the same two mechanisms.
--
-- The two mechanisms common to ALL five clients are used as the primary route;
-- KEY_ESCAPE is kept only as an extra for the modern pair. Registering all
-- three costs nothing and guarantees the key works everywhere.
--
-- ONE owner, not one per frame. The FIRST frame that asks owns the escape
-- routes and every later caller is refused, because the routes are a single
-- dispatch point: two owners would mean the panel and the browser closing
-- together, which is exactly what the player must not get (the panel closes
-- first and the leaderboard stays up).
--
-- The gear panel therefore does NOT register itself -- see the note at its
-- creation in ShowGear. It is closed by THIS handler, which checks for the
-- panel first.
function RankBrowser.RegisterEscapeClose(frame)
    if escapeFrame or type(frame) ~= "table" then return end
    escapeFrame = frame

    -- Closes the TOPMOST window first. The gear panel opens over the browser, so
    -- Escape must dismiss it and leave the leaderboard up -- closing both at
    -- once would throw away the scroll position the player was reading.
    local function closeIfShown()
        local panel = gearFrame
        if panel and panel:IsShown() then
            -- Closed through the ONE close route, so the panel's tracked entry
            -- is cleared with it and a later rebuild cannot resurrect it.
            RankBrowser.CloseGear()
            return true
        end
        local f = rankFrame
        if f and f:IsShown() then
            -- Closing the browser closes the gear panel with it.
            RankBrowser.CloseGear()
            f:Hide()
            return true
        end
        return false
    end

    -- Primary: the frame-script form. It fires wherever the client's frame
    -- machinery declares it as supported; on some clients a bare Frame has
    -- no OnEscapePressed script type, so the assignment is guarded.
    if type(frame.SetScript) == "function" then
        pcall(frame.SetScript, frame, "OnEscapePressed", closeIfShown)
    end

    -- Primary: the engine-recognised special-frames list. Defined on all five
    -- branches; an entry may be a frame or a frame NAME.
    local special = rawget(_G, "UISpecialFrames")
    if type(special) == "table" and rankFrame then
        local frameName = rankFrame:GetName()
        if type(frameName) == "string" and frameName ~= "" then
            local already = false
            for _, entry in ipairs(special) do
                if entry == frameName or entry == rankFrame then
                    already = true
                    break
                end
            end
            if not already then
                special[#special + 1] = frameName
            end
        end
    end

    -- Belt-and-braces: the modern event. Harmless where it never fires.
    local registered = false
    if type(frame.RegisterEvent) == "function" then
        local ok = pcall(frame.RegisterEvent, frame, "KEY_ESCAPE")
        registered = ok == true
    end
    if type(frame.SetScript) == "function" then
        frame:SetScript("OnEvent", function(_, event)
            if registered and event == "KEY_ESCAPE" then
                closeIfShown()
            end
        end)
    end
end

function RankBrowser.Toggle()
    local f = RankBrowser.CreateUI()
    if not f then return end
    if f:IsShown() then
        -- Closing the browser closes the gear panel with it. The panel is a
        -- TOPLEVEL child of the browser, so the engine would normally take it
        -- down with its parent -- but "would" is a rule this add-on does not
        -- depend on, so the panel is closed EXPLICITLY here.
        RankBrowser.CloseGear()
        f:Hide()
    else
        markSessionStart()
        jumpToPlayerPending = true
        applyTopmost(f, BROWSER_STRATA, BROWSER_LEVEL)
        if f.Raise then
            pcall(f.Raise, f)
        end
        f:Show()
        -- OnShow already refreshed at the new offset; this is a safety net for
        -- any client where Show does not fire OnShow synchronously.
        RankBrowser.UpdateUI()
    end
end

-- Rebuild the browser window from the current settings (W11 density toggle).
-- The frame and all row widgets are reconstructed; filters, sort and jump
-- state are module-level and survive, so the rebuilt list shows the same
-- content at the new row height.
function RankBrowser.RebuildUI()
    local wasShown = rankFrame and rankFrame:IsShown()
    -- The gear panel is closed BEFORE the frame swap and re-rendered AFTER the
    -- re-parenting.
    --
    -- Its parent is about to be discarded, so a panel left open across the
    -- swap keeps showing the rows it drew for the OLD frame -- stale gear for
    -- a player whose data may have changed since. Closing it first and
    -- re-rendering it from live data afterwards means the panel is never on
    -- screen carrying data from a frame that no longer exists.
    local gearWasShown = gearFrame ~= nil and gearFrame:IsShown() == true
    local gearEntryBefore = gearEntry
    RankBrowser.CloseGear()
    if rankFrame and type(rankFrame.Hide) == "function" then
        pcall(rankFrame.Hide, rankFrame)
    end
    rankFrame = nil
    rowFrames = {}
    tabHighlight = nil
    classFilterButton = nil
    emptyStateText = nil
    sortHint = nil
    statStrip = nil
    focusedEntry = nil
    lastView = {}
    searchFlushPending = false
    local f = RankBrowser.CreateUI()
    -- The browser frame is new even when it stays hidden: the gear panel must
    -- follow it regardless.
    adoptGearParent()
    -- Re-render the panel now that it belongs to the new frame. ShowGear
    -- re-reads the Scanner cache and the RankDB gear table, so the panel
    -- shows CURRENT data rather than the rows the discarded frame carried.
    if gearWasShown and type(gearEntryBefore) == "table" then
        RankBrowser.ShowGear(gearEntryBefore)
    end
    if f and wasShown then
        markSessionStart()
        jumpToPlayerPending = true
        applyTopmost(f, BROWSER_STRATA, BROWSER_LEVEL)
        if type(f.Show) == "function" then
            pcall(f.Show, f)
        end
        RankBrowser.UpdateUI()
    end
    return f
end

-- Slash commands.
--
-- SLASH_<NAME>1 and SlashCmdList.<NAME> are ONE declaration: Blizzard pairs
-- them by name, so both halves must be written or neither fires. They are
-- written through rawset/_G rather than bare assignment so the declaration and
-- the registration cannot drift apart -- Core.lua and Options.lua used to
-- spell the same pair two different ways in two files.
local g = _G
rawset(g, "SLASH_TACOTIPRANKS1", "/ttrank")
rawset(g, "SLASH_TACOTIPRANKS2", "/ttranks")
rawset(g, "SLASH_TACOTIPRANKS3", "/ttleaderboard")
--
-- The four MULTI-WORD aliases below are registered but NEVER dispatched.
--
-- The client only ever looks at the FIRST whitespace-delimited token of what
-- was typed: ChatFrameEditBox.lua:222 does
--     strmatch(text, "^(/[^%s]+)")
-- so "/tt lb" is looked up as "/tt", never as "/tt lb". The command hash the
-- client builds (ChatFrameUtil.lua:717-736) keys on the uppercased alias
-- string, so "/tt lb" is stored there as "/TT LB", but no client ever queries
-- that key -- not on classic_era, not on classic_anniversary, not on
-- classic_titan, not on forever, not on live.
--
-- They are kept because they are harmless and because the main add-on's own
-- "/tt" forwarding is what actually makes "/tt lb" work in practice. Do NOT
-- read them as working entry points: the working ones are the single-token
-- aliases above plus the main add-on's "/tt" forwarding.
rawset(g, "SLASH_TACOTIPRANKS4", "/tt lb")
rawset(g, "SLASH_TACOTIPRANKS5", "/tt rank")
rawset(g, "SLASH_TACOTIPRANKS6", "/tt ranks")
rawset(g, "SLASH_TACOTIPRANKS7", "/tt leaderboard")
--
-- The toggle the slash handler runs, published on a plain global as well.
--
-- The main add-on CANNOT read this handler back out of SlashCmdList: the
-- client's SlashCmdList is a PROXY table. ChatFrameSetup.lua:3-4 does
-- `setmetatable(list, { __index = {} })` and line 11 applies it to
-- `_G.SlashCmdList`, and ChatFrameUtil.lua's ImportListToHash (line 717)
-- moves every registered handler into getmetatable(list).__index (line 732)
-- and then WIPES the real table (line 735) -- which happens immediately
-- BEFORE the handler is dispatched (ChatFrameEditBox.lua:245, 257, 259). So a
-- rawget(SlashCmdList, "TACOTIPRANKS") at dispatch time returns nil on every
-- one of the five supported clients.
--
-- So the SAME function is published here on a well-named plain global, which
-- the main add-on can call directly and never touch the client's slash
-- registry internals. It is the same function OBJECT the slash handler
-- invokes -- identity, not a copy -- so the two can never drift apart.
--
-- The lookup of RankBrowser.Toggle happens at CALL time, so a later
-- replacement of the module function is still honoured.
local function toggleLeaderboard()
    return RankBrowser.Toggle()
end
rawset(g, "TacoTipExtrasToggleLeaderboard", toggleLeaderboard)

local slashCmdList = rawget(g, "SlashCmdList")
if type(slashCmdList) == "table" then
    slashCmdList["TACOTIPRANKS"] = toggleLeaderboard
end