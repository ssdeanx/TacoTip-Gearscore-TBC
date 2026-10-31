--[[

    TacoTip Extras Localization: enUS / enGB

    Source of truth. Every other locale registers into
    _G.TACOEXTRAS_LOCALES[code]; none of them writes _G.TACOEXTRAS_LOCALE
    directly. TacoExtrasApplyLocale() (bottom of this file) is the single place
    that decides which one is live.

    Every English value below is a VERBATIM copy of the string the code used to
    hardcode, so a key's value is checkable against the source. That is not
    cosmetic: the first draft of this file was built by grepping, and it captured
    "My Rank" where the code actually renders "▼ My Rank", and "You" where the
    code renders "YOU". A locale system whose source of truth disagrees with the
    code silently rewrites the UI the first time it is enabled.

--]]

local defaults = {
    ["CATEGORY_NAME"] = "TacoTip Extras",
    ["EQUIPMENT_CATEGORY_NAME"] = "Equipment Windows",

    ["INTRO"] =
    "A TacoTip companion that adds enhancement-aware GearScore, Average iLvl, and Completion to player tooltips.",

    ["SCORE_EXPLANATION"] =
    "Current GS is the players present GearScore in this addon and the headline value shown in Compact mode. Use Current GS when referring to the players current GearScore. It includes equipped items plus supported bonuses from installed permanent enchants and gems.\n\nUnenhanced GS is an optional comparison using the same equipment with only those counted installed bonuses removed. It shows how much those enhancements already contribute; it is not the player’s current GearScore.\n\nPotential GS adds only confirmed missing eligible permanent enchants and confirmed empty sockets to Current GS. Delta is the increase from Current GS to Potential GS, while Completion shows the share of confirmed enhancement opportunities already filled.\n\nPotential GS and Completion do not rate best-in-slot gear, recommend specific enhancements, or measure raid readiness. Incomplete remote data is shown as unavailable, never as zero.",

    ["MODE_DISABLED"] = "Disabled",
    ["MODE_MINIMAL"] = "Minimal",
    ["MODE_COMPACT"] = "Compact",
    ["MODE_DETAILED"] = "Detailed",
    ["MODE_BASIC"] = "Basic",

    ["CURRENT_GS"] = "Current GS",
    ["UNENHANCED_GS"] = "Unenhanced GS",
    ["POTENTIAL_GS"] = "Potential GS",
    ["DELTA"] = "Delta",
    ["AVERAGE_ILVL"] = "Average iLvl",
    ["COMPLETION"] = "Completion",
    ["COMPLETE"] = "Complete",
    ["ENHANCEMENT_ANALYSIS"] = "Enhancement analysis",
    ["UNAVAILABLE"] = "Unavailable",

    ["TOOLTIP_LABEL_ENHANCEMENT"] = "Enhancement analysis:",
    ["TOOLTIP_LABEL_COMPLETION"] = "Completion:",
    ["TOOLTIP_LABEL_RANK"] = "GS Rank:",

    ["HELP_ENABLED_HEADING"] = "Enable addon",
    ["HELP_ENABLED_1"] =
    "Enables or disables all TacoTip Extras output. When disabled, the addon releases its player GearScore takeover and safely restores the TacoTip setting it manages.",

    ["HELP_MODE_HEADING"] = "Tooltip mode",
    ["HELP_MODE_1"] = "Disabled: Shows no enhancer rows and releases the TacoTip player GearScore takeover.",
    ["HELP_MODE_2"] = "Minimal: Shows the shortest enabled summary, prioritizing Current GS and Average iLvl.",
    ["HELP_MODE_3"] = "Compact: Shows up to two concise rows with Current GS, Average iLvl, useful Delta, and Completion when available.",
    ["HELP_MODE_4"] = "Detailed: Shows each enabled metric on a separately labelled row.",

    ["HELP_SHIFTDETAILED_HEADING"] = "Shift for Detailed",
    ["HELP_SHIFTDETAILED_1"] =
    "Temporarily shows Detailed output while Shift is held in Minimal or Compact mode. Detailed and Disabled modes are unchanged.",

    ["HELP_FIELDS_HEADING"] = "Tooltip fields",
    ["HELP_FIELDS_1"] =
    "Choose which metrics the enhancer may display. The selected mode and data availability can still omit an enabled metric.",

    ["HELP_GEARSCORE_HEADING"] = "Show Current GS",
    ["HELP_GEARSCORE_1"] =
    "Shows the player’s present GearScore and the headline GS value used in Compact mode. It combines the equipped-item score with supported bonuses from installed permanent enchants and gems; temporary weapon effects are not included.",

    ["HELP_BASEGS_HEADING"] = "Show Unenhanced GS",
    ["HELP_BASEGS_1"] =
    "Shows the same equipped items with only the counted bonuses from installed permanent enchants and gems removed. It is an optional comparison for seeing what those enhancements contribute, not the player’s current GearScore.",

    ["HELP_POTENTIALGS_HEADING"] = "Show Potential GS",
    ["HELP_POTENTIALGS_1"] =
    "Shows Current GS after adding only confirmed missing eligible permanent enchants and confirmed empty sockets. It appears only when enough confirmed data is available and does not recommend specific enchants or gems.",

    ["HELP_DELTA_HEADING"] = "Show Delta",
    ["HELP_DELTA_1"] =
    "Shows the confirmed difference between Potential GS and Current GS. It represents the additional score available from confirmed missing enhancements, not a comparison with Unenhanced GS.",

    ["HELP_AVERAGEITEMLEVEL_HEADING"] = "Show Average iLvl",
    ["HELP_AVERAGEITEMLEVEL_1"] =
    "Shows the average item level of equipped gear included in the addon's fixed equipment-slot model.",

    ["HELP_COMPLETION_HEADING"] = "Show Completion",
    ["HELP_COMPLETION_1"] =
    "Shows the share of confirmed eligible permanent-enchant and socket opportunities that are filled. It measures enhancement completion, not best-in-slot gear or raid readiness.",

    ["HELP_RESTRICTLEVEL70_HEADING"] = "Restrict Potential, Completion, and warnings to level 70",
    ["HELP_RESTRICTLEVEL70_1"] =
    "Hides Potential GS, Delta, Completion, and related warnings below level 70. Current GS, Unenhanced GS, and Average iLvl may still appear.",

    ["HELP_WARNINGCOLORS_HEADING"] = "Completion warning colours",
    ["HELP_WARNINGCOLORS_1"] =
    "Colours Completion using the addon's established thresholds. When disabled, Completion remains visible in a neutral colour.",

    ["HELP_SHOWMINIMAP_HEADING"] = "Show minimap button",
    ["HELP_SHOWMINIMAP_1"] =
    "Shows or hides the movable minimap shortcut. Left-click opens or closes the enhancer Options page, and dragging moves the button.",

    ["HELP_SHOWSERVERRANK_HEADING"] = "Show server leaderboard rank",
    ["HELP_SHOWSERVERRANK_1"] =
    "Displays the player's server GearScore ranking and class standing on tooltips when available from the background sync engine.",

    ["HELP_COMFORTABLEROWS_HEADING"] = "Comfortable rows",
    ["HELP_COMFORTABLEROWS_1"] =
    "Grows the leaderboard rows for larger text. The list shows the same players in the same order with taller rows.",

    -- Shaman Blue. The class colour is painted in the unit tooltip, the
    -- character/inspect summary frame and the leaderboard row. Other locales
    -- fall back to English through the per-key fallback in
    -- TacoExtrasApplyLocale until translated.
    ["HELP_SHAMANBLUE_HEADING"] = "Shaman Blue",
    ["HELP_SHAMANBLUE_1"] =
    "Shows the Shaman class name in blue instead of pink. Classic Era paints the Shaman class colour pink, so this matches the colour TacoTip itself uses.",
    ["HELP_SHAMANBLUE_2"] =
    "When TacoTip is installed, its own Shaman Blue setting also applies: turning it off there turns the blue off here as well, so the class colour is the same in both add-ons.",

    ["HELP_OPENLEADERBOARD_HEADING"] = "Open Server Leaderboard",
    ["HELP_OPENLEADERBOARD_1"] =
    "Opens the TacoTip GearScore Server Leaderboard window (/ex ranks) to browse realm-wide standings.",

    ["HELP_RESTORE_HEADING"] = "Restore TacoTip settings",
    ["HELP_RESTORE_1"] =
    "Disables enhancer tooltip output and safely restores only the TacoTip player GearScore setting previously leased.",
    ["HELP_RESTORE_2"] =
    "It does not reset other TacoTip options or your remaining enhancer preferences.",

    ["HELP_RESET_HEADING"] = "Reset enhancer settings",
    ["HELP_RESET_1"] =
    "Restores TacoTip Extras settings to their defaults, including tooltip preferences and minimap visibility and position.",
    ["HELP_RESET_2"] =
    "It does not reset TacoTip. It also does not touch the saved leaderboard: realm standings live in TacoTipExtrasDB and survive this reset.",

    ["HELP_INTEGRATIONSTATUS_HEADING"] = "TacoTip integration",
    ["HELP_INTEGRATIONSTATUS_1"] =
    "Compatible means the exact required TacoTip version and capabilities were detected. If incompatible, the enhancer remains fail-closed and does not take over TacoTip player GearScore output.",

    ["HELP_REMOTESTATUS_HEADING"] = "Remote enhancement analysis",
    ["HELP_REMOTESTATUS_1"] =
    "Remote Potential, Delta, and Completion depend on conclusive inspection data. Complete is successful; unavailable does not mean zero, while pending, suppressed, and not observed are neutral states.",

    ["HELP_BLOCKERSTATUS_HEADING"] = "Remote enhancement blocker",
    ["HELP_BLOCKERSTATUS_1"] =
    "Shows the current reason remote enhancement analysis is unavailable. This diagnostic is temporary and is not stored as player history.",

    ["HELP_EQUIPMENTMODE_HEADING"] = "Character & Inspect summary",
    ["HELP_EQUIPMENTMODE_1"] =
    "Choose what the enhancer shows in both equipment windows. Disabled restores TacoTip's native GearScore and iLvl display. Basic shows Current GS and Average iLvl. Detailed adds conclusive enhancement metrics.",

    ["HELP_EQUIPMENTSHOWUNENHANCED_HEADING"] = "Show Unenhanced GS in Detailed",
    ["HELP_EQUIPMENTSHOWUNENHANCED_1"] =
    "Shows the same equipment before bonuses this addon counts from installed permanent enchants and gems. It is a comparison value, not the main score.",

    ["HELP_EQUIPMENTUNLOCKPOSITIONS_HEADING"] = "Unlock summary positions",
    ["HELP_EQUIPMENTUNLOCKPOSITIONS_1"] =
    "Shows a drag handle in each equipment window. Character and Inspect keep independent positions.",

    ["HELP_EQUIPMENTRESETPOSITIONS_HEADING"] = "Reset summary positions",
    ["HELP_EQUIPMENTRESETPOSITIONS_1"] =
    "Restores both summary blocks to their tested default positions without changing other settings.",

    ["HELP_SCANNOW_HEADING"] = "Scan now",
    ["HELP_SCANNOW_1"] =
    "Runs a scan pass immediately. Only players the game lets you inspect can be scanned, so the number reached depends on what is in range, in your group, or visible on a nameplate.",

    ["MINIMAP_HINT"] = "TacoTip Extras",
    ["MINIMAP_HINT_LEFT"] = "Left-click: leaderboard",
    ["MINIMAP_HINT_RIGHT"] = "Right-click: settings",
    ["MINIMAP_HINT_DRAG"] = "Drag to move",

    ["LB_TITLE"] = "TacoTip GearScore Leaderboard",
    ["LB_REALM"] = "Whole Realm",
    ["LB_SEARCH"] = "Search:",
    ["LB_GUILD"] = "Guild:",
    ["LB_YOU"] = "YOU",
    ["LB_LOADING"] = "Loading rankings...",
    ["LB_EMPTY"] = "No records yet. Scores sync while you play.",
    ["LB_EMPTY_FILTERS"] = "No players match the current filters.",
    ["LB_DB_UNAVAILABLE"] = "The rank database is unavailable, so no rankings can be shown.",
    ["LB_NOT_ESTABLISHED"] = "Not ranked yet",
    ["LB_ONLY_YOU"] = "Only your own character is registered on this realm so far.",
    ["LB_FILTER_ALL"] = "All Classes",
    ["LB_TOP"] = "\226\150\178 Top",
    ["LB_MY_RANK_ARROW"] = "\226\150\188 My Rank",
    ["LB_SORTED_BY"] = "Sorted by %s %s",
    ["LB_SCAN"] = "Scan now",
    ["LB_SCAN_BUSY"] = "Scanning...",

    -- Column headers. Uppercase in English because they sit above the data as a
    -- header row; a translation may choose its own casing.
    ["LB_COL_RANK"] = "RANK",
    ["LB_COL_PLAYER"] = "PLAYER",
    ["LB_COL_SPECCLASS"] = "SPEC / CLASS",
    ["LB_COL_GS"] = "GEARSCORE",
    ["LB_COL_ILVL"] = "iLVL",
    ["LB_COL_LEVEL"] = "LEVEL",
    ["LB_COL_LASTSEEN"] = "LAST SEEN",

    -- Sort dropdown labels. These double as the "Sorted by X" suffix.
    ["SORT_GS_DESC"] = "GEARSCORE",
    ["SORT_ILVL_DESC"] = "iLVL",
    ["SORT_LEVEL_DESC"] = "LEVEL",
    ["SORT_SEEN_DESC"] = "LAST SEEN",

    -- Row hover tooltip.
    ["LB_TIP_UNKNOWN"] = "Unknown",
    ["LB_TIP_UNKNOWNSPEC"] = "Unknown spec",
    ["LB_TIP_GS"] = "GearScore: %d",
    ["LB_TIP_ILVL"] = "Average iLvl: %.1f",
    ["LB_TIP_PVP_RANK"] = "PvP rank: %s",
    ["LB_TIP_ARENA"] = "Arena best: %d",
    ["LB_TIP_RANK"] = "GearScore rank: #%d",
    ["LB_TIP_LASTSEEN"] = "Last seen: %s",
    -- Stage 5 trailing unit-tooltip lines. Other locales fall back to English
    -- through the per-key fallback in TacoExtrasApplyLocale until translated.
    ["LB_TIP_RANK_SYNCED"] = "Rank synced: %s",
    -- The row's click affordance. Other locales fall back to English through
    -- the per-key fallback in TacoExtrasApplyLocale until translated.
    ["LB_TIP_CLICK_GEAR"] = "Click to view gear",

    -- Announced when a scan's progress edge goes active->inactive. Other
    -- locales fall back to English through the per-key fallback in
    -- TacoExtrasApplyLocale until translated.
    ["LB_SCAN_COMPLETE"] = "Scan complete - %d players tracked",

    -- Footer standing line.
    ["LB_FOOTER_STANDING"] =
    "Your Standing: #%d Overall | #%d Faction | #%d Class  -  %d players tracked",
    ["LB_FOOTER_NO_RANK"] = "%d players tracked - you have no ranking yet",

    -- W6 summary strip (realm-at-a-glance header). Other locales fall back to
    -- English through the per-key fallback in TacoExtrasApplyLocale.
    ["LB_STAT_STRIP"] = "%d players | Top %d | Avg %d",

    ["TIME_UNKNOWN"] = "Unknown",
    ["TIME_JUST_NOW"] = "Just now",
    ["TIME_MIN_AGO"] = "%d min ago",
    ["TIME_HOUR_AGO"] = "%d hr ago",
    ["TIME_YESTERDAY"] = "Yesterday",
    ["TIME_DAY_AGO"] = "%d d ago",

    ["GEAR_TITLE"] = "%s's Gear",
    ["GEAR_NOT_SCANNED"] = "This player has not been scanned yet, so no gear is available.",
    -- Unknown-state hint: the session saw the player but yielded no gear and
    -- nothing persisted exists. Other locales fall back to English through
    -- the per-key fallback in TacoExtrasApplyLocale until translated.
    ["GEAR_DATA_UNAVAILABLE"] = "Gear data is unavailable for this player right now. Press Scan now in the leaderboard, then try again.",
    ["GEAR_NO_OPPORTUNITIES"] = "no eligible opportunities",
    ["GEAR_UNAVAILABLE"] = "Equipment data unavailable",
    ["GEAR_SCANNING"] = "Scanning equipment...",

    ["SCAN_PROGRESS"] = "%d / %d",

    ["CLASS_DEATHKNIGHT"] = "Death Knight",
    ["CLASS_DEMONHUNTER"] = "Demon Hunter",
    ["CLASS_DRUID"] = "Druid",
    ["CLASS_EVOKER"] = "Evoker",
    ["CLASS_HUNTER"] = "Hunter",
    ["CLASS_MAGE"] = "Mage",
    ["CLASS_MONK"] = "Monk",
    ["CLASS_PALADIN"] = "Paladin",
    ["CLASS_PRIEST"] = "Priest",
    ["CLASS_ROGUE"] = "Rogue",
    ["CLASS_SHAMAN"] = "Shaman",
    ["CLASS_WARLOCK"] = "Warlock",
    ["CLASS_WARRIOR"] = "Warrior",
    ["CLASS_UNKNOWN"] = "Unknown",
}

-- ---------------------------------------------------------------------------
-- Locale selection
-- ---------------------------------------------------------------------------

-- Extras FOLLOWS TacoTip rather than choosing for itself.
--
-- ## Dependencies: TacoTip means TacoTip loads FIRST, so by the time this file
-- runs TacoTipConfig.locale_override is already populated with SavedVariables --
-- which is not true of TacoTip's own locale files, hence the extra call from
-- gearscore.lua there. Reading it here is the whole reason this works.
--
-- Fallback when TacoTip is absent or says nothing: the client language, then
-- English.
local function pickLocale()
    local requested = _G.TACOTIP_ACTIVE_LOCALE
    if type(requested) == "string" and requested ~= "" then
        return requested
    end
    if type(_G.TacoTipConfig) == "table"
        and type(_G.TacoTipConfig.locale_override) == "string"
        and _G.TacoTipConfig.locale_override ~= "" then
        return _G.TacoTipConfig.locale_override
    end
    if type(_G.GetLocale) == "function" then
        return _G.GetLocale()
    end
    return "enUS"
end

-- MUTATES _G.TACOEXTRAS_LOCALE in place rather than replacing it. Options.lua
-- binds `local L = _G.TACOEXTRAS_LOCALE` at file scope, so replacing the table
-- would leave that local pointing at a stale copy and switching language would
-- appear to do nothing.
function _G.TacoExtrasApplyLocale()
    local locales = _G.TACOEXTRAS_LOCALES or {}

    local requested = pickLocale()
    -- English is the source of truth for both enUS and enGB.
    if requested == "enGB" then
        requested = "enUS"
    end

    local pick = requested
    local base = locales[pick] or locales["enUS"] or defaults

    local target = _G.TACOEXTRAS_LOCALE
    if type(target) ~= "table" then
        target = {}
        _G.TACOEXTRAS_LOCALE = target
    end
    for key in pairs(target) do
        target[key] = nil
    end
    for key, value in pairs(base) do
        target[key] = value
    end
    -- Key by key, not table by table: a partial translation falls back per key.
    for key, value in pairs(defaults) do
        if target[key] == nil then
            target[key] = value
        end
    end

    _G.TACOEXTRAS_ACTIVE_LOCALE = base == defaults and "enUS" or pick
    return target
end

_G.TACOEXTRAS_LOCALES = _G.TACOEXTRAS_LOCALES or {}
_G.TACOEXTRAS_LOCALES["enUS"] = defaults

_G.TacoExtrasApplyLocale()
