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

local NUM_ROWS = 12
local ROW_HEIGHT = 26
local FRAME_WIDTH = 720
local FRAME_HEIGHT = 520
local ROW_WIDTH = 660
local ROW_LEFT = 18
local ROW_TOP = -104
local HEADER_TOP = -82
local CONTROL_TOP = -46

local BRAND_R, BRAND_G, BRAND_B = 0.60, 0.46, 0.82
local MUTED_R, MUTED_G, MUTED_B = 0.62, 0.62, 0.66
local TEXT_R, TEXT_G, TEXT_B = 0.90, 0.90, 0.92

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
    { key = "rank", x = 8, width = 36, justify = "LEFT", label = "LB_COL_RANK", fallback = "RANK", template = "GameFontHighlightSmall" },
    { key = "name", x = 48, width = 200, justify = "LEFT", label = "LB_COL_PLAYER", fallback = "PLAYER", template = "GameFontNormal" },
    { key = "spec", x = 252, width = 150, justify = "LEFT", label = "LB_COL_SPECCLASS", fallback = "SPEC / CLASS", template = "GameFontHighlightSmall" },
    { key = "gs", x = 406, width = 64, justify = "RIGHT", label = "LB_COL_GS", fallback = "GEARSCORE", template = "GameFontHighlight" },
    { key = "ilvl", x = 482, width = 56, justify = "RIGHT", label = "LB_COL_ILVL", fallback = "iLVL", template = "GameFontHighlightSmall" },
    { key = "seen", x = 550, width = 76, justify = "RIGHT", label = "LB_COL_LASTSEEN", fallback = "LAST SEEN", template = "GameFontDisableSmall" },
}

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
-- is gone. Filtering is by class and by search text only.
local currentClass = "ALL"
local currentSearch = ""

local jumpToPlayerPending = false

local rankFrame = nil
local escapeFrame = nil
local rowFrames = {}
local tabHighlight = nil
local classFilterButton = nil
local emptyStateText = nil
local sortHint = nil

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------

local function getClassColor(class)
    return CLASS_COLORS[class] or DEFAULT_CLASS_COLOR
end

local function formatRelativeTime(timestamp)
    if not timestamp or timestamp <= 0 then return L["TIME_UNKNOWN"] or "Unknown" end
    local now = time and time() or 0
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
        pcall(_G.FauxScrollFrame_OnVerticalScroll, scrollFrame, offset * ROW_HEIGHT, ROW_HEIGHT, nil)
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
    seen = "SORT_SEEN_DESC",
}
local SORTABLE_COLUMNS = { "gs", "ilvl", "seen" }
local currentSort = "gs"

-- UTF-8 triangles, spelled as bytes because Lua 5.1 has no \u{} escapes.
local ARROW_DOWN = "\226\152\148"
local ARROW_UP = "\226\152\145"

local function sortEntries(data, mode)
    local arr = {}
    for i = 1, #data do
        arr[i] = data[i]
    end
    if mode == "ilvl" then
        table.sort(arr, function(a, b)
            local ai, bi = tonumber(a.ilvl) or 0, tonumber(b.ilvl) or 0
            if ai ~= bi then return ai > bi end
            local ag, bg = tonumber(a.gs) or 0, tonumber(b.gs) or 0
            if ag ~= bg then return ag > bg end
            return (a.name or "") < (b.name or "")
        end)
    elseif mode == "seen" then
        table.sort(arr, function(a, b)
            local at, bt = tonumber(a.timestamp) or 0, tonumber(b.timestamp) or 0
            if at ~= bt then return at > bt end
            local ag, bg = tonumber(a.gs) or 0, tonumber(b.gs) or 0
            if ag ~= bg then return ag > bg end
            return (a.name or "") < (b.name or "")
        end)
    end
    if mode == "gs" then
        table.sort(arr, function(a, b)
            local ag, bg = tonumber(a.gs) or 0, tonumber(b.gs) or 0
            if ag ~= bg then return ag > bg end
            local ai, bi = tonumber(a.ilvl) or 0, tonumber(b.ilvl) or 0
            if ai ~= bi then return ai > bi end
            return (a.name or "") < (b.name or "")
        end)
    end
    return arr
end

-- guid -> GearScore rank within the current filter set.
local function buildGearScoreRanks(data)
    local byGS = sortEntries(data, "gs")
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

    local c = getClassColor(entry.class)
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

    local specName = entry.specName
    if type(specName) ~= "string" or specName == "" then
        specName = entry.class or ""
    end
    add(specName ~= "" and specName or L["LB_TIP_UNKNOWNSPEC"], MUTED_R, MUTED_G, MUTED_B)

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
    local alpha = 0
    if row.hovered then
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
-- Scanner.lua stores specIcon from C_SpecializationInfo.GetTalentInfo(...).icon,
-- which is a FILEID, not a path -- that API has no Lua definition on any branch,
-- so it is C-backed, and .icon comes back numeric on the modern clients. Whether
-- a modern talent fileID resolves against Classic's own texture set is NOT
-- guaranteed, so this is entirely defensive: a missing icon must cost the row a
-- 14px gap, never an error and never a broken-looking box.
local function applySpecIcon(row, entry)
    local tex = row.specIconTexture
    if not tex then return end

    local icon = entry.specIcon
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
    local c = getClassColor(entry.class)
    row.nameText:SetText(entry.name or L["LB_TIP_UNKNOWN"])
    row.nameText:SetTextColor(c[1], c[2], c[3])
    row.classBar:SetColorTexture(c[1], c[2], c[3], 0.85)

    -- Spec, muted so it reads as secondary to the name.
    local specName = entry.specName
    if type(specName) ~= "string" or specName == "" then
        specName = entry.class or ""
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

    -- Last seen, muted.
    row.seenText:SetText(formatRelativeTime(entry.timestamp))
    row.seenText:SetTextColor(MUTED_R, MUTED_G, MUTED_B)

    applySpecIcon(row, entry)

    -- "YOU" marker on the player's own row.
    if row.youTag then
        row.youTag:SetShown(row.isPlayer)
    end

    applyRowOverlay(row)
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
function RankBrowser.StartScan()
    local scanner = namespace.Scanner
    if type(scanner) ~= "table" then
        return false
    end
    if type(scanner.BeginGeneration) == "function" then
        scanner.BeginGeneration("leaderboard")
    elseif type(scanner.RunGeneration) == "function" then
        scanner.RunGeneration()
    else
        return false
    end
    RankBrowser.RefreshProgress()
    return true
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
    f.scanning = progress.active == true
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
-- translated into. Verified present on classic_era, classic_era anniversary,
-- titanforge, forever and live.
local SLOT_ROWS = {
    { slot = 1,  global = "INVTYPE_HEAD",            fallback = "Head" },
    { slot = 2,  global = "INVTYPE_NECK",            fallback = "Neck" },
    { slot = 3,  global = "INVTYPE_SHOULDER",        fallback = "Shoulder" },
    { slot = 15, global = "INVTYPE_CLOAK",           fallback = "Back" },
    { slot = 5,  global = "INVTYPE_CHEST",           fallback = "Chest" },
    { slot = 9,  global = "INVTYPE_WRIST",           fallback = "Wrist" },
    { slot = 10, global = "INVTYPE_HANDS",           fallback = "Hands" },
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
local function slotValueText(slot)
    if type(slot) ~= "table" then
        return nil
    end
    if slot.state == "confirmed-empty" then
        return nil
    end
    local link = slot.nativeLink
    if type(link) == "table" and type(link.value) == "string" and link.value ~= "" then
        return link.value
    end
    local itemID = slot.itemID
    if type(itemID) == "table" and type(itemID.value) == "number" then
        return "|cffffffffitem:" .. tostring(itemID.value) .. "|r"
    end
    return nil
end

function RankBrowser.CloseGear()
    if gearFrame then
        gearFrame:Hide()
    end
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
        local f = g.CreateFrame("Frame", "TacoTipGearPanel", g.UIParent or nil)
        f:SetSize(400, 470)
        f:SetPoint("CENTER", 0, 0)
        f:SetFrameStrata("DIALOG")
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
            row:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -46 - (index - 1) * 22)
            row:SetWidth(360)
            row:SetJustifyH("LEFT")
            f.rows[index] = row
        end

        local note = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        note:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 18, 16)
        note:SetWidth(360)
        note:SetJustifyH("LEFT")
        f.note = note

        -- Escape closes it, the same three-route registration the browser uses.
        RankBrowser.RegisterEscapeClose(f)
        gearFrame = f
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

    local anyItem = false
    for index = 1, #SLOT_ROWS do
        local spec = SLOT_ROWS[index]
        local value = type(slots) == "table" and slotValueText(slots[spec.slot]) or nil
        if value then
            anyItem = true
            gearFrame.rows[index]:SetText(slotLabel(spec) .. ":  " .. value)
        else
            gearFrame.rows[index]:SetText("|cff808080" .. slotLabel(spec) .. "|r")
        end
    end

    if not anyItem then
        gearFrame.note:SetText(L["GEAR_NOT_SCANNED"]
            or "This player has not been scanned yet, so no gear is available.")
    else
        gearFrame.note:SetText("")
    end

    gearFrame:Show()
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

function RankBrowser.UpdateUI()
    if not rankFrame or not rankFrame:IsShown() then return end

    local db = namespace.RankDB
    if not db or type(db.GetLeaderboard) ~= "function" then return end

    local data, totalCount = db.GetLeaderboard(nil, "All", currentClass, currentSearch)
    data = data or {}
    totalCount = totalCount or 0

    -- The GearScore-rank map is built from the GearScore order regardless of
    -- how the list is currently sorted, so the `#` column always means the same
    -- thing.
    local gsRanks = buildGearScoreRanks(data)
    local view = (currentSort == "gs") and data or sortEntries(data, currentSort)

    -- Best-in-view, so a colour means "how good is this HERE". Computed from
    -- the whole filtered set, not the visible page, so scrolling does not
    -- re-colour the same player. `totalCount` is the pool the percentile rank
    -- is measured against.
    viewBestGS, viewBestILVL, viewTotal = 0, 0, totalCount
    for index = 1, #data do
        local entry = data[index]
        if type(entry) == "table" then
            local gs = tonumber(entry.gs)
            local ilvl = tonumber(entry.ilvl)
            if gs and gs > viewBestGS then viewBestGS = gs end
            if ilvl and ilvl > viewBestILVL then viewBestILVL = ilvl end
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
        else
            offset = 0
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
        _G.FauxScrollFrame_Update(scrollFrame, totalCount, NUM_ROWS, ROW_HEIGHT)
    end

    local myGUID = getPlayerGUID()

    for i = 1, NUM_ROWS do
        local index = offset + i
        local row = rowFrames[i]
        if row then
            local entry = view[index]
            if entry then
                renderRow(row, entry, index, gsRanks[entry.guid], myGUID)
            else
                row.isPlayer = false
                row.entry = nil
                row:Hide()
            end
        end
    end

    if emptyStateText then
        emptyStateText:SetShown(totalCount == 0)
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
end

-- ---------------------------------------------------------------------------
-- Row construction
-- ---------------------------------------------------------------------------

local function createRow(parent, index)
    local g = _G
    local row = g.CreateFrame("Button", nil, parent)
    row:SetSize(ROW_WIDTH, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", ROW_LEFT, ROW_TOP - (index - 1) * ROW_HEIGHT)
    row.isPlayer = false
    row.hovered = false

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
    classBar:SetSize(3, ROW_HEIGHT)
    classBar:SetColorTexture(1, 1, 1, 0.85)
    row.classBar = classBar

    -- Specialization icon, immediately left of the spec text.
    local specIconTexture = row:CreateTexture(nil, "ARTWORK")
    specIconTexture:SetPoint("RIGHT", row, "LEFT", 246, 0)
    specIconTexture:SetSize(14, 14)
    specIconTexture:Hide()
    row.specIconTexture = specIconTexture

    for _, col in ipairs(COLUMNS) do
        local fs = row:CreateFontString(nil, "ARTWORK", col.template)
        fs:SetPoint("LEFT", row, "LEFT", col.x, 0)
        fs:SetWidth(col.width)
        fs:SetJustifyH(col.justify)
        row[col.key .. "Text"] = fs
    end

    -- "YOU" marker on the player's row.
    local youTag = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    youTag:SetPoint("LEFT", row, "LEFT", 626, 0)
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
        local arrow = (currentSort == "seen") and ARROW_UP or ARROW_DOWN
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

    local ok, f = pcall(g.CreateFrame, "Frame", "TacoTipRankFrame", g.UIParent, "BackdropTemplate")
    if not ok or type(f) ~= "table" then
        ok, f = pcall(g.CreateFrame, "Frame", "TacoTipRankFrame", g.UIParent)
    end
    if not ok or type(f) ~= "table" then return nil end
    f:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    f:SetPoint("CENTER", g.UIParent, "CENTER", 0, 0)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)

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

    -- Title.
    local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOP", f, "TOP", 0, -14)
    title:SetText(L["LB_TITLE"] or "TacoTip GearScore Leaderboard")

    local close = g.CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)

    -- Whole-server scope. There is deliberately NO Alliance/Horde split: the
    -- leaderboard ranks the entire realm, and a faction filter would only ever
    -- hide the players you want to compare yourself against.
    local scopeLabel = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    scopeLabel:SetPoint("TOPLEFT", f, "TOPLEFT", ROW_LEFT, CONTROL_TOP)
    scopeLabel:SetText(L["LB_REALM"] or "Whole Realm")

    -- Active-scope underline, sitting under the scope label.
    tabHighlight = f:CreateTexture(nil, "ARTWORK")
    tabHighlight:SetColorTexture(BRAND_R, BRAND_G, BRAND_B, 0.9)
    tabHighlight:SetHeight(2)
    tabHighlight:SetPoint("BOTTOMLEFT", scopeLabel, "BOTTOMLEFT", 0, -3)
    tabHighlight:SetPoint("BOTTOMRIGHT", scopeLabel, "BOTTOMRIGHT", 0, -3)

    -- Search box (right of the control row).
    local search = g.CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    search:SetSize(180, 22)
    search:SetPoint("TOPRIGHT", f, "TOPRIGHT", -40, CONTROL_TOP)
    if search.SetAutoFocus then
        search:SetAutoFocus(false)
    end
    search:SetScript("OnTextChanged", function(self)
        currentSearch = self:GetText() or ""
        RankBrowser.UpdateUI()
    end)
    local searchLabel = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    searchLabel:SetPoint("RIGHT", search, "LEFT", -8, 0)
    searchLabel:SetText(L["LB_SEARCH"] or "Search:")

    -- Class filter dropdown, between the tabs and the search box.
    local classDD = g.CreateFrame("Frame", "TacoTipRankClassFilter", f, "UIDropDownMenuTemplate")
    classDD:SetPoint("RIGHT", searchLabel, "LEFT", -24, 0)
    classFilterButton = classDD
    if type(g.UIDropDownMenu_Initialize) == "function" and type(g.UIDropDownMenu_AddButton) == "function" then
        -- Canonical UIDropDownMenu pattern: build a FRESH info table per entry
        -- and hand it straight to AddButton. Building an info.list and then
        -- looping AddButton over it double-adds every entry, because AddButton
        -- is what appends to the menu.
        g.UIDropDownMenu_Initialize(classDD, function()
            local function entryFor(text, value)
                return {
                    text = text,
                    func = function()
                        currentClass = value
                        refreshClassFilterLabel()
                        RankBrowser.UpdateUI()
                    end,
                }
            end
            g.UIDropDownMenu_AddButton(entryFor(L["LB_FILTER_ALL"] or "All Classes", "ALL"))
            for _, className in ipairs(CLASS_ORDER) do
                g.UIDropDownMenu_AddButton(entryFor(className, className))
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
            header:SetPoint("TOPLEFT", f, "TOPLEFT", ROW_LEFT + col.x, HEADER_TOP + 4)
            header:SetText(L[col.label] or col.fallback or col.label)
            header:SetScript("OnClick", function()
                currentSort = col.key
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
            header:SetPoint("TOPLEFT", f, "TOPLEFT", ROW_LEFT + col.x, HEADER_TOP)
            header:SetWidth(col.width)
            header:SetJustifyH(col.justify)
            header:SetText(L[col.label] or col.fallback or col.label)
        end
        col.header = header
    end

    -- One-line sort readout, created before the first refresh so the initial
    -- state renders correctly without a special-case call.
    sortHint = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    sortHint:SetPoint("TOPLEFT", f, "TOPLEFT", ROW_LEFT, ROW_TOP + 26)
    refreshSortHeaders()

    -- Thin separator under the header.
    local separator = f:CreateTexture(nil, "ARTWORK")
    separator:SetPoint("TOPLEFT", f, "TOPLEFT", ROW_LEFT, ROW_TOP + 8)
    separator:SetPoint("TOPRIGHT", f, "TOPRIGHT", -40, ROW_TOP + 8)
    separator:SetHeight(1)
    separator:SetColorTexture(1, 1, 1, 0.15)

    -- FauxScrollFrame hosting the virtual rows.
    local sf = g.CreateFrame("ScrollFrame", "TacoTipRankScrollFrame", f, "FauxScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", f, "TOPLEFT", ROW_LEFT, ROW_TOP)
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -40, 44)
    sf:SetScript("OnVerticalScroll", function(self, ofs)
        if type(g.FauxScrollFrame_OnVerticalScroll) == "function" then
            g.FauxScrollFrame_OnVerticalScroll(self, ofs, ROW_HEIGHT, RankBrowser.UpdateUI)
        end
    end)
    f.scrollFrame = sf

    -- Rows.
    for i = 1, NUM_ROWS do
        rowFrames[i] = createRow(f, i)
    end

    -- Empty-state message, shown only when the current filters match nobody.
    emptyStateText = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    emptyStateText:SetPoint("TOP", sf, "TOP", 0, -80)
    emptyStateText:SetText(L["LB_EMPTY_FILTERS"] or "No players match the current filters.")
    emptyStateText:SetTextColor(MUTED_R, MUTED_G, MUTED_B)
    emptyStateText:Hide()

    -- Footer: personal standing (left) and navigation buttons (right).
    local footer = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    footer:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", ROW_LEFT, 14)
    footer:SetText(L["LB_LOADING"] or "Loading rankings...")
    f.footerText = footer

    local topButton = g.CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    topButton:SetSize(80, 22)
    topButton:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -122, 12)
    topButton:SetText(L["LB_TOP"] or "Top")
    topButton:SetScript("OnClick", function()
        RankBrowser.ScrollToTop()
    end)

    local meButton = g.CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    meButton:SetSize(90, 22)
    meButton:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -34, 12)
    meButton:SetText(L["LB_MY_RANK_ARROW"] or "My Rank")
    meButton:SetScript("OnClick", function()
        RankBrowser.TrackToPlayer()
    end)

    -- Scan entry point. The Options page carries the same control and both call
    -- RankBrowser.StartScan / read RankBrowser.RefreshProgress, so the two
    -- surfaces cannot disagree about whether a scan is running.
    local scanButton = g.CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    scanButton:SetSize(100, 22)
    scanButton:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -222, 12)
    scanButton:SetText(L["LB_SCAN"] or "Scan now")
    scanButton:SetScript("OnClick", function()
        RankBrowser.StartScan()
    end)
    f.scanButton = scanButton

    -- Progress bar, above the footer row. Hidden when idle so the window does
    -- not carry a dead grey rail at all times.
    local bar = g.CreateFrame("StatusBar", nil, f)
    bar:SetSize(ROW_WIDTH, 12)
    bar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", ROW_LEFT, 36)
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

    -- Every open lands on the player's own rank.
    f:SetScript("OnShow", function()
        jumpToPlayerPending = true
        RankBrowser.UpdateUI()
        RankBrowser.RefreshProgress()
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
function RankBrowser.RegisterEscapeClose(frame)
    if escapeFrame or type(frame) ~= "table" then return end
    escapeFrame = frame

    -- Closes the TOPMOST window first. The gear panel opens over the browser, so
    -- Escape must dismiss it and leave the leaderboard up -- closing both at
    -- once would throw away the scroll position the player was reading.
    local function closeIfShown()
        local panel = gearFrame
        if panel and panel:IsShown() then
            panel:Hide()
            return true
        end
        local f = rankFrame
        if f and f:IsShown() then
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
        f:Hide()
    else
        jumpToPlayerPending = true
        if f.SetFrameStrata then
            pcall(f.SetFrameStrata, f, "DIALOG")
        end
        if f.SetFrameLevel then
            pcall(f.SetFrameLevel, f, 100)
        end
        if f.Raise then
            pcall(f.Raise, f)
        end
        f:Show()
        -- OnShow already refreshed at the new offset; this is a safety net for
        -- any client where Show does not fire OnShow synchronously.
        RankBrowser.UpdateUI()
    end
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
rawset(g, "SLASH_TACOTIPRANKS4", "/tt lb")
rawset(g, "SLASH_TACOTIPRANKS5", "/tt rank")
rawset(g, "SLASH_TACOTIPRANKS6", "/tt ranks")
rawset(g, "SLASH_TACOTIPRANKS7", "/tt leaderboard")
local slashCmdList = rawget(g, "SlashCmdList")
if type(slashCmdList) == "table" then
    slashCmdList["TACOTIPRANKS"] = function()
        RankBrowser.Toggle()
    end
end