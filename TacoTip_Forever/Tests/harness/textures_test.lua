-- Permanent guard for the built-in texture-path lists in textures.lua.
--
-- WHY THIS EXISTS
--
-- In 0.7.9 an audit of all 191 entries in TT.builtinTooltipBorders,
-- TT.builtinTooltipBackgrounds and TT.builtinStatusBarTextures found 92 that
-- do not exist on any client: their parent directory is present in the
-- Gethe/wow-ui-textures art mirror but the file is absent from it, and no
-- wow-ui-source branch mentions the name either. They were inventions shaped
-- like Blizzard's naming convention -- LootFrame-Border, MailFrame-Background,
-- SpellbookBorder, OptionsFrame-Background, the five Raid-Bar-<power>-Fill
-- entries. A wrong texture path is the worst kind of bug here: Texture:
-- SetTexture silently no-ops on a missing file, so nothing raises, nothing
-- logs, and the user gets a blank swatch and an invisible or solid-white
-- border. No harness that only RUNS the addon can ever catch it.
--
-- load_test.lua already had a guard for this, but it blocked the single
-- literal string "BackdropTextures" and therefore caught exactly one of the
-- 120 fabricated names. This test replaces that with an allow-list, so a new
-- invention has to be added to Tests/harness/textures.txt -- which is where
-- the review decision gets recorded -- before the suite will go green.
--
-- WHAT THIS DOES AND DOES NOT PROVE
--
-- It proves membership in the reviewed list. It cannot prove a file exists on
-- a real client: an offline Lua process has no client to ask. A path in
-- textures.txt can still be wrong for a client the mirror predates. What the
-- guard genuinely stops is the failure mode that actually happened -- a path
-- nobody ever looked at reaching the shipped dropdown.

local results, allok = {}, true

local function check(name, cond, detail)
    results[#results + 1] = string.format("%-62s %s", name,
        (cond and "PASS" or "FAIL") .. "   " .. (detail or ""))
    if not cond then allok = false end
end

-- Repo root, derived from this script's own path so the harness runs the same
-- whether it is invoked as `lua Tests/harness/textures_test.lua` from the addon
-- directory or with an absolute path from anywhere.
local scriptPath = ((arg and arg[0]) or "Tests/harness/textures_test.lua"):gsub("\\", "/")
local harnessDir = scriptPath:match("^(.*)/[^/]*$") or "."
local root = harnessDir:gsub("Tests/harness/?$", ""):gsub("/+$", "")
if root == "" then root = "." end
local TEXTURES_LUA = root .. "/textures.lua"
local ALLOW_LIST  = root .. "/Tests/harness/textures.txt"

-- Compare paths the way a reviewer reads them: separator- and case-insensitive.
-- textures.lua writes the separator doubled (Lua source) and at least one real
-- entry, Interface\CHARACTERFRAME\UI-Party-Border, is not case-canonical, so an
-- exact string compare would report those as unknown.
local function canon(path)
    return (tostring(path):gsub("\\", "/"):lower())
end

-- ---------------------------------------------------------------------------
-- Load the allow-list, keeping track of which reviewed class each path is in.
-- The class distinction IS the point of the file: a path nobody verified must
-- never sit in the same bucket as one that was found on disk.
-- ---------------------------------------------------------------------------
local allow, allowClass, counts = {}, {}, { VERIFIED = 0, SENTINEL = 0, UNVERIFIED = 0 }
local errors, orphans = {}, {}
local currentClass = nil

-- Class headers are matched strictly -- a comment line whose text after the
-- '#' begins with the class name followed by whitespace. Anything looser reads
-- the file's own explanatory prose as a section change and silently reclassifies
-- every path after it.
local CLASS_HEADER = {
    ["^#%s+VERIFIED%-PRESENT%s"] = "VERIFIED",
    ["^#%s+SENTINEL%s"]          = "SENTINEL",
    ["^#%s+UNVERIFIED%s"]        = "UNVERIFIED",
}

local fh = assert(io.open(ALLOW_LIST, "r"),
    "cannot read the reviewed allow-list " .. ALLOW_LIST .. " -- the guard cannot verify anything without it")
for line in fh:lines() do
    local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
    for pattern, class in pairs(CLASS_HEADER) do
        if trimmed:match(pattern) then currentClass = class end
    end
    if trimmed ~= "" and trimmed:sub(1, 1) ~= "#" then
        local key = canon(trimmed)
        if not currentClass then
            -- No class header preceded this path. That is what flattening the
            -- file into one list looks like, and it is reported below with a
            -- legible message rather than aborting here on an assert.
            orphans[#orphans + 1] = trimmed
        else
            if allowClass[key] then
                errors[#errors + 1] = "listed under more than one class: " .. trimmed
            end
            allow[key] = trimmed
            allowClass[key] = currentClass
            counts[currentClass] = counts[currentClass] + 1
        end
    end
end
fh:close()

check("allow-list is readable", true, ALLOW_LIST)

-- The two-class distinction must survive. If someone flattens the file to a
-- single bucket, the "unverified is not the same as verified" fact is lost and
-- the file silently becomes a list of things we made up. Orphaned paths (no
-- class header above them) are the same mistake in its rawest form.
table.sort(orphans)
check("allow-list keeps VERIFIED and UNVERIFIED apart",
    #errors == 0 and #orphans == 0 and counts.VERIFIED > 0 and counts.UNVERIFIED > 0,
    (function()
        local parts = { string.format("verified=%d unverified=%d sentinel=%d",
            counts.VERIFIED, counts.UNVERIFIED, counts.SENTINEL) }
        if #errors > 0 then
            parts[#parts + 1] = table.concat(errors, "; ")
        end
        if #orphans > 0 then
            parts[#parts + 1] = #orphans
                .. " path(s) under NO class header (first: " .. orphans[1] .. ")"
                .. " -- the file has been flattened into a single list"
        end
        return table.concat(parts, "; ")
    end)())

-- ---------------------------------------------------------------------------
-- Load the REAL textures.lua and read the three lists the addon ships.
-- ---------------------------------------------------------------------------
_G.GetLocale = function() return "enUS" end
_G.TacoTipForever = nil
local chunk = assert(loadfile(TEXTURES_LUA), "cannot load " .. TEXTURES_LUA)
chunk("TacoTipForever")
local TT = _G.TacoTipForever

local LISTS = {
    { name = "builtinStatusBarTextures",   list = TT.builtinStatusBarTextures },
    { name = "builtinTooltipBackgrounds",   list = TT.builtinTooltipBackgrounds },
    { name = "builtinTooltipBorders",       list = TT.builtinTooltipBorders },
}

local total, unknown, seen = 0, {}, {}
for _, spec in ipairs(LISTS) do
    assert(type(spec.list) == "table", spec.name .. " is not a table -- textures.lua failed to load")
    for _, entry in ipairs(spec.list) do
        local value = entry.value
        assert(type(value) == "string" and value ~= "",
            spec.name .. " has an entry with no path")
        total = total + 1
        local key = canon(value)
        if not allow[key] then
            unknown[#unknown + 1] = value .. "   (" .. spec.name .. ")"
        end
        seen[key] = true
    end
end

-- THE ASSERTION. Every shipped path must be on the reviewed list.
check("every shipped texture path is on the reviewed allow-list",
    #unknown == 0,
    (function()
        if #unknown == 0 then
            return string.format("%d paths across 3 lists, all reviewed", total)
        end
        local shown = {}
        for i = 1, math.min(#unknown, 8) do shown[#shown + 1] = unknown[i] end
        local note = string.format("%d of %d UNAUDITED:\n            %s",
            #unknown, total, table.concat(shown, "\n            "))
        if #unknown > 8 then note = note .. "\n            ... and " .. (#unknown - 8) .. " more" end
        return note
    end)())

-- Retiring an entry therefore means editing this file too. That is deliberate:
-- a path here that textures.lua no longer ships is either a half-done removal or
-- a decision that was reverted, and both are worth a loud failure.
local stale = {}
for key, raw in pairs(allow) do
    if not seen[key] then stale[#stale + 1] = raw end
end
table.sort(stale)
check("no stale entries left on the allow-list", #stale == 0,
    #stale == 0 and "allow-list and textures.lua agree exactly"
        or (#stale .. " listed but not shipped: " .. table.concat(stale, ", ")))

-- ---------------------------------------------------------------------------
-- The defaults must themselves be reviewed paths, or the guard is decorative:
-- a default is what a player gets before touching any dropdown.
-- ---------------------------------------------------------------------------
for _, fn in ipairs({ "GetDefaultTooltipBorder", "GetDefaultTooltipBackground" }) do
    local value = TT[fn] and TT[fn]()
    check("default from " .. fn .. " is on the allow-list",
        type(value) == "string" and allow[canon(value)] ~= nil,
        tostring(value))
end

-- Interface\None is not a border and must not be offered.
local hasNone = false
for _, entry in ipairs(TT.builtinTooltipBorders or {}) do
    if entry.value == "Interface\\None" then hasNone = true end
end
check("Interface\\None is not offered as a border", not hasNone,
    "fallback and sentinel removed")

-- The 0.7.9 prune. Named individually so a failure says WHICH fabrication
-- class came back rather than only counting them.
local RETIRED = {
    "Interface\\None",
    "Interface\\LootFrame\\LootFrame-Border",
    "Interface\\MailFrame\\MailFrame-Background",
    "Interface\\Spellbook\\SpellbookBorder",
    "Interface\\OptionsFrame\\OptionsFrame-Background",
    "Interface\\PvPFrame\\PvPFrame-Border",
    "Interface\\QuestFrame\\QuestFrameBorder",
    "Interface\\GMChat\\GM-BarFill",
    "Interface\\Garrison\\Garrison-Background",
    "Interface\\RaidFrame\\Raid-Bar-Mana-Fill",
    "Interface\\RaidFrame\\Raid-Bar-RunicPower-Fill",
    "Interface\\AddOns\\Details\\images\\border_1",
}
local back = {}
for _, value in ipairs(RETIRED) do
    for _, spec in ipairs(LISTS) do
        for _, entry in ipairs(spec.list) do
            if canon(entry.value) == canon(value) then back[#back + 1] = value end
        end
    end
end
check("refuted and third-party paths stay out of the lists", #back == 0,
    #back == 0 and (RETIRED[1] .. " and " .. (#RETIRED - 1) .. " others checked")
        or table.concat(back, ", "))

print(table.concat(results, "\n"))
print(string.format("\n%d paths shipped, %d reviewed (%d verified-present, %d unverified, %d sentinel)",
    total, counts.VERIFIED + counts.UNVERIFIED + counts.SENTINEL,
    counts.VERIFIED, counts.UNVERIFIED, counts.SENTINEL))
print("\n" .. (allok and "ALL PASS" or "*** FAILURES ***"))
os.exit(allok and 0 or 1)
