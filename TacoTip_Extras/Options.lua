local addonName, namespace = ...

if type(namespace) ~= "table" then
    return
end

local Options = {}
namespace.Options = Options

-- Bound at file scope. TacoExtrasApplyLocale MUTATES this table rather than
-- replacing it, so the reference stays live across a language change.
local L = _G.TACOEXTRAS_LOCALE or {}

-- The add-on title and the settings-page titles come straight from the locale.
-- CATEGORY_NAME is what the settings list shows, so it is the most visible
-- string in the file.
local CATEGORY_NAME = L["CATEGORY_NAME"] or "TacoTip Extras"
local EQUIPMENT_CATEGORY_NAME = L["EQUIPMENT_CATEGORY_NAME"] or "Equipment Windows"
local ICON_PATH = "Interface\\AddOns\\TacoTip_Extras\\tt-2"
local SUCCESS_RED, SUCCESS_GREEN, SUCCESS_BLUE = 0.45, 0.82, 0.55
local NEUTRAL_RED, NEUTRAL_GREEN, NEUTRAL_BLUE = 0.58, 0.56, 0.64
local WARNING_RED, WARNING_GREEN, WARNING_BLUE = 0.95, 0.72, 0.30
local FOOTER_RED, FOOTER_GREEN, FOOTER_BLUE = 0.55, 0.52, 0.62

local INTRO_TEXT = L["INTRO"]
    or (
        "A TacoTip companion that adds enhancement-aware GearScore, "
        .. "Average iLvl, and Completion to player tooltips."
    )

local SCORE_EXPLANATION = L["SCORE_EXPLANATION"]
    or [[Current GS is the players present GearScore in this addon and the headline value shown in Compact mode. Use Current GS when referring to the players current GearScore. It includes equipped items plus supported bonuses from installed permanent enchants and gems.

Unenhanced GS is an optional comparison using the same equipment with only those counted installed bonuses removed. It shows how much those enhancements already contribute; it is not the player’s current GearScore.

Potential GS adds only confirmed missing eligible permanent enchants and confirmed empty sockets to Current GS. Delta is the increase from Current GS to Potential GS, while Completion shows the share of confirmed enhancement opportunities already filled.

Potential GS and Completion do not rate best-in-slot gear, recommend specific enhancements, or measure raid readiness. Incomplete remote data is shown as unavailable, never as zero.]]

-- ---------------------------------------------------------------------------
-- The counted action-failure boundary
-- ---------------------------------------------------------------------------
--
-- A button or a checkbox that changes something and then calls into another
-- module is a SILENT NO-OP when that call raises: the box is ticked, the
-- setting is written, and the surface the setting governs keeps the old
-- rendering -- with nothing said and nothing counted. Two checkboxes did
-- exactly that ("Comfortable rows" and "Shaman Blue" both discarded the
-- result of RankBrowser.RebuildUI), and three action buttons called into
-- Core and RankBrowser with no guard at all.
--
-- So every call's RESULT is captured here. A failure is counted, the reason
-- is kept, and the player is told in one plain chat line naming the problem
-- -- the same shape as printOptionsLine and as the main add-on's counters.
-- The counter and the last reason are surfaced by /ttgsdebug (Core.lua's
-- surfaces block).
--
-- The forward declaration of printOptionsLine lives here because the
-- boundary is declared before the function itself (see the assignment
-- further down this file).
local printOptionsLine

local actionFailures = 0
local lastActionFailure = nil

-- Record one failed options-page action: count it, keep the reason, and say
-- it once in the chat frame.
local function noteActionFailure(reason, err, message)
    actionFailures = actionFailures + 1
    lastActionFailure = reason .. ": " .. tostring(err)
    printOptionsLine(message
        or (tostring(reason) .. " failed; nothing was changed."))
end

-- Run one options-page action so that a raise can never be a silent no-op.
--
-- Returns the action's own result on success and false on a raise.
local function runOptionsAction(reason, fn)
    local ok, result = pcall(fn)
    if not ok then
        noteActionFailure(reason, result)
        return false
    end
    return result
end

-- Rebuild the leaderboard after a setting that changes its rendering.
--
-- Returns true when the rebuild happened, false when it failed or the module
-- is absent. The caller never has to guess.
local function rebuildLeaderboard(reason)
    local browser = namespace.RankBrowser
    if type(browser) ~= "table" or type(browser.RebuildUI) ~= "function" then
        return false
    end
    local ok, err = pcall(browser.RebuildUI)
    if ok then
        return true
    end
    noteActionFailure(reason, err,
        "the server leaderboard could not be rebuilt after \""
            .. tostring(reason)
            .. "\" was changed; the window still shows the old layout.")
    return false
end

-- Run one leaderboard action on behalf of an options-page button.
--
-- The action buttons used to call straight into RankBrowser, so a raising
-- action left the player with a button that had been pressed and nothing to
-- show for it. The result is captured, counted and named here. The MISSING
-- module case keeps its own wording (the caller prints that one); only a
-- RAISE is handled here.
local function runBrowserAction(methodName, reason)
    local browser = namespace.RankBrowser
    if type(browser) ~= "table" or type(browser[methodName]) ~= "function" then
        return false
    end
    local ok, err = pcall(browser[methodName])
    if ok then
        return true
    end
    noteActionFailure(reason, err,
        "the server leaderboard could not complete \""
            .. tostring(reason)
            .. "\"; nothing was changed.")
    return false
end

-- The diagnostic snapshot /ttgsdebug reads. Same shape as the other modules'
-- GetDebugState accessors.
function Options.GetDebugState()
    return {
        actionFailures = actionFailures,
        lastActionFailure = lastActionFailure,
    }
end

local HELP = {
    Enabled = {
        heading = "Enable addon",
        lines = {
            "Enables or disables all TacoTip Extras output. When disabled, the addon releases its player GearScore takeover and safely restores the TacoTip setting it manages.",
        },
    },
    mode = {
        heading = "Tooltip mode",
        lines = {
            "Disabled: Shows no enhancer rows and releases the TacoTip player GearScore takeover.",
            "Minimal: Shows the shortest enabled summary, prioritizing Current GS and Average iLvl.",
            "Compact: Shows up to two concise rows with Current GS, Average iLvl, useful Delta, and Completion when available.",
            "Detailed: Shows each enabled metric on a separately labelled row.",
        },
    },
    ShiftDetailed = {
        heading = "Shift for Detailed",
        lines = {
            "Temporarily shows Detailed output while Shift is held in Minimal or Compact mode. Detailed and Disabled modes are unchanged.",
        },
    },
    fields = {
        heading = "Tooltip fields",
        lines = {
            "Choose which metrics the enhancer may display. The selected mode and data availability can still omit an enabled metric.",
        },
    },
    GearScore = {
        heading = "Show Current GS",
        lines = {
            "Shows the player’s present GearScore and the headline GS value used in Compact mode. It combines the equipped-item score with supported bonuses from installed permanent enchants and gems; temporary weapon effects are not included.",
        },
    },
    BaseGS = {
        heading = "Show Unenhanced GS",
        lines = {
            "Shows the same equipped items with only the counted bonuses from installed permanent enchants and gems removed. It is an optional comparison for seeing what those enhancements contribute, not the player’s current GearScore.",
        },
    },
    PotentialGS = {
        heading = "Show Potential GS",
        lines = {
            "Shows Current GS after adding only confirmed missing eligible permanent enchants and confirmed empty sockets. It appears only when enough confirmed data is available and does not recommend specific enchants or gems.",
        },
    },
    Delta = {
        heading = "Show Delta",
        lines = {
            "Shows the confirmed difference between Potential GS and Current GS. It represents the additional score available from confirmed missing enhancements, not a comparison with Unenhanced GS.",
        },
    },
    AverageItemLevel = {
        heading = "Show Average iLvl",
        lines = {
            "Shows the average item level of equipped gear included in the addon's fixed equipment-slot model.",
        },
    },
    Completion = {
        heading = "Show Completion",
        lines = {
            "Shows the share of confirmed eligible permanent-enchant and socket opportunities that are filled. It measures enhancement completion, not best-in-slot gear or raid readiness.",
        },
    },
    RestrictLevel70 = {
        heading = "Restrict Potential, Completion, and warnings to level 70",
        lines = {
            "Hides Potential GS, Delta, Completion, and related warnings below level 70. Current GS, Unenhanced GS, and Average iLvl may still appear.",
        },
    },
    WarningColors = {
        heading = "Completion warning colours",
        lines = {
            "Colours Completion using the addon's established thresholds. When disabled, Completion remains visible in a neutral colour.",
        },
    },
    ShowMinimap = {
        heading = "Show minimap button",
        lines = {
            "Shows or hides the movable minimap shortcut. Left-click opens or closes the enhancer Options page, and dragging moves the button.",
        },
    },
    ShowServerRank = {
        heading = "Show server leaderboard rank",
        lines = {
            "Displays the player's server GearScore ranking and class standing on tooltips when available from the background sync engine.",
        },
    },
    ComfortableRows = {
        heading = "Comfortable rows",
        lines = {
            "Grows the leaderboard rows for larger text. The list shows the same players in the same order with taller rows.",
        },
    },
    ShamanBlue = {
        heading = "Shaman Blue",
        lines = {
            "Shows the Shaman class name in blue instead of pink. Classic Era paints the Shaman class colour pink, so this matches the colour TacoTip itself uses.",
            "When TacoTip is installed, its own Shaman Blue setting also applies: turning it off there turns the blue off here as well, so the class colour is the same in both add-ons.",
        },
    },
    openLeaderboard = {
        heading = "Open Server Leaderboard",
        lines = {
            "Opens the TacoTip GearScore Server Leaderboard window (/tt ranks) to browse realm-wide standings.",
        },
    },
    scanNow = {
        heading = "Scan now",
        lines = {
            "Re-reads your own equipped items and republishes your GearScore to the realm. Use it after changing gear or enchants when you want your standing updated without waiting for the next sync.",
            "Only your own character is scanned. Other players are recorded as they are seen, and scanning them is not possible from here.",
        },
    },
    restore = {
        heading = "Restore TacoTip settings",
        lines = {
            "Disables enhancer tooltip output and safely restores only the TacoTip player GearScore setting previously leased.",
            "It does not reset other TacoTip options or your remaining enhancer preferences.",
        },
    },
    reset = {
        heading = "Reset enhancer settings",
        lines = {
            "Restores TacoTip Extras settings to their defaults, including tooltip preferences and minimap visibility and position.",
            "It does not reset TacoTip. It also does not touch the saved leaderboard: realm standings live in TacoTipExtrasDB and survive this reset.",
        },
    },
    integrationStatus = {
        heading = "TacoTip integration",
        lines = {
            "Compatible means the exact required TacoTip version and capabilities were detected. If incompatible, the enhancer remains fail-closed and does not take over TacoTip player GearScore output.",
        },
    },
    remoteStatus = {
        heading = "Remote enhancement analysis",
        lines = {
            "Remote Potential, Delta, and Completion depend on conclusive inspection data. Complete is successful; unavailable does not mean zero, while pending, suppressed, and not observed are neutral states.",
        },
    },
    blockerStatus = {
        heading = "Remote enhancement blocker",
        lines = {
            "Shows the current reason remote enhancement analysis is unavailable. This diagnostic is temporary and is not stored as player history.",
        },
    },
    equipmentMode = {
        heading = "Character & Inspect summary",
        lines = {
            "Choose what the enhancer shows in both equipment windows. Disabled restores TacoTip's native GearScore and iLvl display. Basic shows Current GS and Average iLvl. Detailed adds conclusive enhancement metrics.",
        },
    },
    EquipmentShowUnenhanced = {
        heading = "Show Unenhanced GS in Detailed",
        lines = {
            "Shows the same equipment before bonuses this addon counts from installed permanent enchants and gems. It is a comparison value, not the main score.",
        },
    },
    EquipmentUnlockPositions = {
        heading = "Unlock summary positions",
        lines = {
            "Shows a drag handle in each equipment window. Character and Inspect keep independent positions.",
        },
    },
    equipmentResetPositions = {
        heading = "Reset summary positions",
        lines = {
            "Restores both summary blocks to their tested default positions without changing other settings.",
        },
    },
}

-- The mode names, resolved through the LOCALE with the English literal as
-- the fallback -- the same shape every other control in this file uses
-- (L[key] or literal).
--
-- The dropdown used to carry the English literals in EVERY language: it was
-- the one control the player reads the mode from, and it read "Disabled",
-- "Minimal", "Compact" and "Detailed" in ruRU exactly as in enUS. Every
-- locale already carries MODE_* for these words.
local MODE_CHOICES = {
    { value = "Disabled", key = "MODE_DISABLED", text = "Disabled" },
    { value = "Minimal",  key = "MODE_MINIMAL",  text = "Minimal" },
    { value = "Compact",  key = "MODE_COMPACT",  text = "Compact" },
    { value = "Detailed", key = "MODE_DETAILED", text = "Detailed" },
}

local EQUIPMENT_MODE_CHOICES = {
    { value = "Disabled", key = "MODE_DISABLED", text = "Disabled" },
    { value = "Basic",    key = "MODE_BASIC",    text = "Basic" },
    { value = "Detailed", key = "MODE_DETAILED", text = "Detailed" },
}

-- The display text of one choice: the locale's word when the locale has one,
-- the English literal otherwise.
local function choiceText(choice)
    if type(choice) ~= "table" then
        return nil
    end
    local key = choice.key
    if type(key) == "string" then
        local localized = L[key]
        if type(localized) == "string" and localized ~= "" then
            return localized
        end
    end
    return choice.text
end

-- The display text of a mode VALUE, for the control that shows the mode in
-- effect. An unknown value is shown as it is: the mode is a stored string
-- and an unrecognised one is better shown than hidden.
local function modeText(choices, value)
    for _, choice in ipairs(choices) do
        if choice.value == value then
            return choiceText(choice)
        end
    end
    return value
end

local DIAGNOSTIC_SLOTS = {
    [1] = true,
    [2] = true,
    [3] = true,
    [5] = true,
    [6] = true,
    [7] = true,
    [8] = true,
    [9] = true,
    [10] = true,
    [11] = true,
    [12] = true,
    [13] = true,
    [14] = true,
    [15] = true,
    [16] = true,
    [17] = true,
    [18] = true,
}

local INTEGRATION_REASONS = {
    ["not-initialized"] = "not initialized",
    ["tacotip-not-loaded"] = "TacoTip is not loaded",
    ["tacotip-version-unsupported"] = "unsupported TacoTip version",
    ["tacotip-tooltip-capability-unsupported"] = "required TacoTip capability is unavailable",
    ["tacotip-config-capability-changed"] = "TacoTip configuration changed",
    ["tacotip-tooltip-capability-changed"] = "TacoTip tooltip capability changed",
    ["inspector-capability-unsupported"] = "inspection capability is unavailable",
    ["inspector-capability-changed"] = "inspection capability changed",
    ["inspector-callback-registration-failed"] = "inspection callback registration failed",
    ["tooltip-inspection-path-unsafe"] = "no safe existing remote inspection path",
    ["tooltip-lease-config-replaced"] = "TacoTip configuration was replaced",
    ["tooltip-lease-setting-conflict"] = "the leased TacoTip setting changed externally",
    ["recovery-journal-mismatch"] = "saved recovery information is incompatible",
    ["recovery-compatibility-unsupported"] = "saved recovery requires manual review",
    ["recovery-config-replaced"] = "TacoTip configuration changed during recovery",
    ["recovery-setting-conflict"] = "the recovered TacoTip setting changed externally",
}

local ENHANCEMENT_REASONS = {
    ["native-fields-conclusive"] = "required native fields are conclusive",
    ["native-enhancement-data-unavailable"] = "required native enhancement data is unavailable",
    ["enhancement-analysis-unavailable"] = "required enhancement data is unavailable",
    ["socket-capability-unavailable"] = "socket capability is unavailable",
    ["socket-capability"] = "socket capability is unavailable",
    ["socket-capacity-unavailable"] = "socket capacity is unavailable",
    ["socket-capacity-invalid"] = "socket capacity is invalid",
    -- The socket capacity comes from the documented socket-count API, and the
    -- item's own gem list is the cross-check against it. This is the TOO-LARGE
    -- branch of that cross-check: the reported capacity exceeds the gem
    -- positions the item's link carries, so the two cannot be reconciled and
    -- the socket-based metrics are withheld rather than published.
    --
    -- The socket-ordering label that used to sit here is GONE, and deliberately
    -- so: the capacity is no longer a sum of stat-table keys, so no code path
    -- produces that reason any more, and a label for it would be a label for a
    -- reason that can never occur.
    ["socket-capacity-exceeds-gem-list"] = "socket capacity exceeds the item's gem list",
    ["ranged-subtype-unverified"] = "ranged enchant eligibility is unverified",
    ["invalid-native-link"] = "the native item link is invalid",
    ["inventory-id-link-contradiction"] = "item identity evidence is contradictory",
    ["inventory-read-failed"] = "equipped item data could not be read",
    ["installed-socket-state-unavailable"] = "installed socket state is unavailable",
    ["permanent-enchant-state-unavailable"] = "permanent enchant state is unavailable",
    ["item-data-pending"] = "item data is pending",
    ["item-metadata-api-unavailable"] = "item metadata API is unavailable",
    ["item-cache-state-unavailable"] = "item cache state is unavailable",
    ["item-metadata-read-failed"] = "item metadata could not be read",
    ["remote-temporary-weapon-state-unavailable"] = "remote temporary effects are unobservable",
    ["temporary-weapon-state-unavailable"] = "temporary effects are unobservable",
    ["source-not-complete"] = "the current source revision is incomplete",
    ["level-policy"] = "hidden by the level policy",
}

-- The socket cross-check produces a DYNAMIC reason code: the socket position
-- that contradicts the capacity is part of the code itself
-- ("socket-gem-mismatch-2"), so no fixed table can hold one entry per index
-- and the panel used to show the raw code to the player.
--
-- The family is resolved by a documented PREFIX rule instead: an exact key in
-- ENHANCEMENT_REASONS always wins, and a code that matches the family pattern
-- resolves to the family sentence. A new index needs no new entry.
--
-- The index is IN the code, so this family's raw code is DIAGNOSTIC ONLY: the
-- player-facing line carries the sentence, and the raw code stays where it
-- belongs -- the diagnostic-slot blocker line, which shows the raw code for
-- every reason, mapped or not. No other reason changes shape.
local SOCKET_GEM_MISMATCH_PATTERN = "^socket%-gem%-mismatch%-%d+$"
local SOCKET_GEM_MISMATCH_LABEL =
    "the item's socket count and its gem list disagree"

-- Returns the player-facing label for a reason code -- nil when the code has
-- no label -- and whether the raw code itself is diagnostic only.
local function resolveEnhancementReason(reason)
    if type(reason) ~= "string" then
        return nil, false
    end
    local exact = ENHANCEMENT_REASONS[reason]
    if exact ~= nil then
        return exact, false
    end
    if string.match(reason, SOCKET_GEM_MISMATCH_PATTERN) then
        return SOCKET_GEM_MISMATCH_LABEL, true
    end
    return nil, false
end

local settings
local panel
local category
local equipmentPanel
local initialized = false
local registrationMode = "none"
local slashHandler
local controls = {}
local equipmentControls = {}
-- The CHECKBOXES, kept apart from the rest of the controls.
--
-- `controls` also holds the dropdown, the action buttons and the status
-- lines, and those are not checkboxes. Keeping the checkboxes in their own
-- list is what lets Options.Refresh re-label and re-measure exactly the
-- controls that carry a label -- no guessing from the table's contents.
local checkboxes = {}
local equipmentCheckboxes = {}
local activeHelpOwner

-- Author credit shown in the Options panel footer.
--
-- This is a SECOND credit site, independent of Core.lua's WELCOME_CREDIT. It was
-- missed when the login banner was corrected, so the banner and the options
-- footer disagreed about who wrote the add-on. Keep the two in sync.
local AUTHOR_CREDIT = "AcidBomb"

local function versionCredit()
    local core = namespace.Core
    if type(core) == "table" and type(core.GetVersion) == "function" then
        local ok, value = pcall(core.GetVersion)
        if ok and type(value) == "string" then
            return "v" .. value .. " - " .. AUTHOR_CREDIT
        end
    end
    return "v? - " .. AUTHOR_CREDIT
end

local function hideHelp(owner)
    if activeHelpOwner ~= owner then
        return
    end
    local tooltip = _G.GameTooltip
    if type(tooltip) == "table" and type(tooltip.Hide) == "function" then
        local owned = true
        if type(tooltip.IsOwned) == "function" then
            local ok, result = pcall(tooltip.IsOwned, tooltip, owner)
            owned = ok and result == true
        end
        if owned then
            tooltip:Hide()
            if type(tooltip.ClearLines) == "function" then
                tooltip:ClearLines()
            end
            if type(tooltip.ClearAllPoints) == "function" then
                tooltip:ClearAllPoints()
            end
        end
    end
    activeHelpOwner = nil
end

-- Resolve a HELP entry through the locale, falling back to the English text in
-- the table above.
--
-- The table stays the readable, English source of truth and the locale file
-- overrides it key by key, so a partially translated language shows translated
-- strings where it has them and English everywhere else. Keys are derived from
-- the table key: HELP_<KEY>_HEADING and HELP_<KEY>_<lineNumber>.
--
-- The same helper feeds the control labels, because a checkbox label and its
-- help heading are the same words -- that is what made them drift apart before.
local function localizedHelp(helpKey)
    local entry = HELP[helpKey]
    if type(entry) ~= "table" then
        return nil, nil
    end
    local upper = tostring(helpKey):upper()
    local heading = L["HELP_" .. upper .. "_HEADING"] or entry.heading
    local lines = {}
    local source = type(entry.lines) == "table" and entry.lines or {}
    for index = 1, #source do
        lines[index] = L[("HELP_%s_%d"):format(upper, index)] or source[index]
    end
    return heading, lines
end

local function helpHeading(helpKey)
    local heading = localizedHelp(helpKey)
    return heading
end

local function showHelp(owner, helpKey, anchorPolicy)
    local help = HELP[helpKey]
    local tooltip = _G.GameTooltip
    if type(help) ~= "table"
        or type(tooltip) ~= "table"
        or type(tooltip.SetOwner) ~= "function"
        or type(tooltip.SetText) ~= "function"
        or type(tooltip.AddLine) ~= "function"
        or type(tooltip.Show) ~= "function"
        or (anchorPolicy == "status"
            and (type(tooltip.ClearAllPoints) ~= "function"
                or type(tooltip.SetPoint) ~= "function")) then
        return
    end
    if activeHelpOwner and activeHelpOwner ~= owner then
        hideHelp(activeHelpOwner)
    end
    if type(tooltip.ClearLines) == "function" then
        tooltip:ClearLines()
    end
    if anchorPolicy == "status" then
        tooltip:SetOwner(owner, "ANCHOR_NONE")
        tooltip:ClearAllPoints()
        tooltip:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", 0, 6)
    else
        tooltip:SetOwner(owner, "ANCHOR_RIGHT")
    end
    local heading, lines = localizedHelp(helpKey)
    tooltip:SetText(heading or help.heading, 1, 1, 1)
    for _, line in ipairs(lines or help.lines) do
        tooltip:AddLine(line, 0.82, 0.82, 0.82, true)
    end
    activeHelpOwner = owner
    tooltip:Show()
end

-- Hooking a help popup onto a widget is where this add-on used to abort a load
-- on EVERY supported client, not just one family.
--
-- HookScript raises "bad argument #2 to 'HookScript'" when the frame does not
-- already declare that script. A base Frame declares only OnEvent, OnHide,
-- OnLoad, OnShow and OnUpdate -- confirmed by reading
-- Interface/AddOns/Blizzard_UIParent/Classic/UIParent.xml, the root of the
-- frame hierarchy, where <Frame name="UIParent"> declares exactly those five.
-- OnEnter and OnLive arrive from <Button>'s script definitions in
-- Blizzard_SharedXML/Shared/Button/UIButtonTemplate.xml, so a Button carries
-- them and a Frame does not.
--
-- createHelpRegion and createEquipmentHelpRegion build plain Frames and pass
-- them here, and createPanel reaches attachHelp at file scope, so this raised
-- before the equipment panel was even constructed. Core.initialize ran its
-- sub-initializers with no pcall, so the raise skipped every later step and the
-- user silently lost the minimap button and the welcome line.
--
-- The fix is the pattern TacoTip_Forever/main.lua already uses everywhere: ask
-- HasScript before hooking. A widget that declares neither script still gets
-- SetScript, which is safe on any frame.
local function attachHelp(owner, helpKey, anchorPolicy)
    if type(owner) ~= "table" or type(owner.SetScript) ~= "function" then
        return false
    end
    local function onEnter(self)
        showHelp(self, helpKey, anchorPolicy)
    end
    local function onLeave(self)
        hideHelp(self)
    end

    local hasScript = type(owner.HasScript) == "function" and owner.HasScript
    local hookedAny = false
    if type(owner.HookScript) == "function"
        and hasScript
        and owner:HasScript("OnEnter")
        and owner:HasScript("OnLeave") then
        local okEnter = pcall(owner.HookScript, owner, "OnEnter", onEnter)
        local okLeave = pcall(owner.HookScript, owner, "OnLeave", onLeave)
        hookedAny = okEnter and okLeave
    end
    if not hookedAny then
        -- SetScript replaces rather than chains, so only fall back when the hook
        -- did not take; on a Button that declares the scripts the hook above
        -- wins and the template's own handlers stay intact.
        pcall(owner.SetScript, owner, "OnEnter", onEnter)
        pcall(owner.SetScript, owner, "OnLeave", onLeave)
    end
    return true
end

local function createHelpRegion(id, x, y, width, height, helpKey)
    local region = CreateFrame("Frame", addonName .. "Help" .. id, panel)
    region:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
    region:SetSize(width, height)
    region:EnableMouse(true)
    attachHelp(region, helpKey)
    controls[id .. "Help"] = region
    return region
end

local function measuredTextDimension(fontString, method, fallback)
    local reader = type(fontString) == "table" and fontString[method] or nil
    if type(reader) == "function" then
        local ok, value = pcall(reader, fontString)
        if ok
            and type(value) == "number"
            and value == value
            and value > 0
            and value ~= math.huge then
            return math.ceil(value)
        end
    end
    return fallback
end

local function updateStatusHelpRegion(fontString, region)
    if type(region) ~= "table" or type(region.SetSize) ~= "function" then
        return false
    end
    region:SetSize(
        measuredTextDimension(fontString, "GetStringWidth", 1),
        measuredTextDimension(fontString, "GetStringHeight", 14)
    )
    return true
end

local function createStatusHelpRegion(id, fontString, helpKey)
    local region = CreateFrame("Frame", addonName .. "Help" .. id, panel)
    region:SetPoint("TOPLEFT", fontString, "TOPLEFT", 0, 0)
    region:SetSize(1, 14)
    region:EnableMouse(true)
    attachHelp(region, helpKey, "status")
    controls[id .. "Help"] = region
    return region
end

local function tooltipSettings()
    if type(settings) == "table" and type(settings.tooltip) == "table" then
        return settings.tooltip
    end
    return nil
end

local function fieldSettings()
    local tooltip = tooltipSettings()
    if tooltip and type(tooltip.fields) == "table" then
        return tooltip.fields
    end
    return nil
end

local function minimapSettings()
    if type(settings) == "table" and type(settings.minimap) == "table" then
        return settings.minimap
    end
    return nil
end

local function equipmentDisplaySettings()
    if type(settings) == "table"
        and type(settings.equipmentDisplay) == "table" then
        return settings.equipmentDisplay
    end
    return nil
end

local function adoptReturnedSettings(value)
    if type(value) ~= "table" then
        return
    end
    if type(value.tooltip) == "table" then
        settings = value
    elseif type(value.settings) == "table" then
        settings = value.settings
    end
end

-- The empty-field rule used to be implemented HERE as well as in Core's
-- normalise: a second copy of the same rule, which is how the two drifted
-- and how the mode was lost for good. The rule now lives in ONE place
-- (Core.ApplyTooltipFieldModeRule), so the local copy -- and the local
-- field list it needed -- are gone.

local function applyTooltipSettings()
    local tooltips = namespace.Tooltips
    if type(tooltips) == "table" and type(tooltips.ApplySettings) == "function" then
        tooltips.ApplySettings()
    elseif type(tooltips) == "table"
        and type(tooltips.RefreshVisible) == "function" then
        tooltips.RefreshVisible()
    end
    Options.Refresh()
end

local function applyMinimapSettings()
    local minimap = namespace.Minimap
    if type(minimap) == "table" and type(minimap.ApplySettings) == "function" then
        minimap.ApplySettings()
    end
    Options.Refresh()
end

local function applyEquipmentSettings()
    local core = namespace.Core
    if type(core) == "table"
        and type(core.ApplyEquipmentSettings) == "function" then
        core.ApplyEquipmentSettings()
        return
    elseif type(core) == "table" and type(core.ApplySettings) == "function" then
        core.ApplySettings()
        return
    end
    local frames = namespace.Frames
    if type(frames) == "table" and type(frames.ApplySettings) == "function" then
        frames.ApplySettings()
    end
    Options.Refresh()
end

local function applyAllSettings()
    local tooltips = namespace.Tooltips
    if type(tooltips) == "table" and type(tooltips.ApplySettings) == "function" then
        tooltips.ApplySettings()
    elseif type(tooltips) == "table"
        and type(tooltips.RefreshVisible) == "function" then
        tooltips.RefreshVisible()
    end
    local minimap = namespace.Minimap
    if type(minimap) == "table" and type(minimap.ApplySettings) == "function" then
        minimap.ApplySettings()
    end
    local frames = namespace.Frames
    if type(frames) == "table" and type(frames.ApplySettings) == "function" then
        frames.ApplySettings()
    end
    Options.Refresh()
end

local function setChecked(control, checked)
    if control and type(control.SetChecked) == "function" then
        control:SetChecked(checked == true)
    end
end

local function setControlEnabled(control, enabled)
    if type(control) ~= "table" then
        return
    end
    if enabled and type(control.Enable) == "function" then
        control:Enable()
    elseif not enabled and type(control.Disable) == "function" then
        control:Disable()
    end
    local label = control.optionLabel
    if type(label) == "table" and type(label.SetTextColor) == "function" then
        if enabled then
            label:SetTextColor(1, 1, 1)
        else
            label:SetTextColor(0.5, 0.5, 0.5)
        end
    end
end

-- The tooltip page is TWO COLUMNS of checkboxes, and the geometry between
-- them is what the operator's screenshot caught.
--
--   left column   x = 16
--   right column  x = 290
--
-- The right column starts at RIGHT_COLUMN_X, so a left-column label that
-- runs past it lands on the right column's control -- which is exactly what
-- "Restrict Potential, Completion, and warnings to level 70" did: it is one
-- long line with no width cap, so it ran straight through the "Show server
-- leaderboard rank" control and its label.
--
-- Every label is therefore capped to its COLUMN's width and wraps inside it,
-- so the two columns of labels line up and neither reaches the other.
local RIGHT_COLUMN_X = 290
local PANEL_CONTENT_RIGHT = 590
-- The check button's own size, from the template the client gives it:
--   origin/classic_era          Interface/AddOns/Blizzard_FrameXML/DeprecatedTemplates.xml:5-6
--   origin/classic_anniversary  Interface/AddOns/Blizzard_FrameXML/DeprecatedTemplates.xml:5-6
--   origin/classic_titan        Interface/AddOns/Blizzard_FrameXML/DeprecatedTemplates.xml:5-6
--   origin/forever              Interface/AddOns/Blizzard_FrameXML/DeprecatedTemplates.xml:5-6
--   origin/live                 Interface/AddOns/Blizzard_FrameXML/DeprecatedTemplates.xml:5-6
--       <CheckButton name="OptionsBaseCheckButtonTemplate" inherits="UICheckButtonTemplate" virtual="true">
--           <Size x="26" y="26"/>
local CHECKBOX_SIZE = 26
local LABEL_GAP = 2

-- The width a label may use, derived from the column its control is in.
local function columnLabelWidth(x)
    if x < RIGHT_COLUMN_X then
        return RIGHT_COLUMN_X - x - CHECKBOX_SIZE - LABEL_GAP
    end
    return PANEL_CONTENT_RIGHT - x - CHECKBOX_SIZE - LABEL_GAP
end

-- The hit rect covers the button AND its label, and nothing beyond.
--
-- It used to be a flat 240 or 500 pixels to the RIGHT, which reached
-- straight across the column gap: a left-column control's clickable
-- region -- and the button highlight the client draws over it -- landed on
-- the right column's control, which is what made the right column hard to
-- click and paint as a box. The expansion is now the LABEL's own width,
-- capped at the column, so it can never reach the next column.
--
-- The order of SetHitRectInsets' arguments is (left, right, top, bottom),
-- verified in the client source and not guessed:
--   origin/classic_era  Interface/AddOns/Blizzard_APIDocumentationGenerated/
--     SimpleFrameAPIDocumentation.lua:1150-1153
--       { Name = "left" }, { Name = "right" }, { Name = "top" }, { Name = "bottom" }
-- and Blizzard's own calls use the second argument as a RIGHT expansion:
--   origin/classic_era  Interface/AddOns/Blizzard_Calendar/Classic/
--     Blizzard_Calendar.lua:3799
--       self:SetHitRectInsets(0, -CalendarCreateEventAutoApproveCheckText:GetWidth(), 0, 0)
--
-- The expansion is RECOMPUTED, not measured once at creation. Two things
-- invalidate a measurement taken at creation:
--
--   * a FontString measured before its font is loaded measures ZERO, and a
--     label with no hit rect stops being clickable -- and the panel is
--     built long before the player opens it;
--   * a locale change rewrites the label's text in place
--     (TacoExtrasApplyLocale MUTATES the locale table), so the
--     measurement is stale the moment the language changes.
--
-- The label's own width is the FLOOR: when the client cannot measure the
-- text at all, the expansion falls back to the width the label already
-- has instead of collapsing to nothing.
local function applyCheckboxHitRect(check, label, cap)
    if type(check) ~= "table" or type(label) ~= "table" then
        return 0
    end
    local measured = 0
    if type(label.GetStringWidth) == "function" then
        local okWidth, width = pcall(label.GetStringWidth, label)
        if okWidth and type(width) == "number" and width > 0 then
            measured = width
        end
    end
    local own = 0
    if type(label.GetWidth) == "function" then
        local okOwn, width = pcall(label.GetWidth, label)
        if okOwn and type(width) == "number" and width > 0 then
            own = width
        end
    end
    local expansion = measured
    if expansion <= 0 then
        -- The floor: the label's own width, so an unmeasurable label keeps
        -- a clickable region instead of losing one.
        expansion = own
    end
    if expansion > cap then
        expansion = cap
    end
    if type(check.SetHitRectInsets) == "function" then
        check:SetHitRectInsets(0, -expansion, 0, 0)
    end
    return expansion
end

-- Re-set a checkbox's label from the locale and re-measure its hit rect.
--
-- Called from Options.Refresh, so the label always carries the CURRENT
-- language's words and the hit rect always matches them.
local function refreshCheckboxLabel(check)
    if type(check) ~= "table" then
        return
    end
    local label = check.optionLabel
    if type(label) ~= "table" then
        return
    end
    local text = check.optionHelpKey and helpHeading(check.optionHelpKey) or nil
    text = text or check.optionText
    if type(label.SetText) == "function" then
        label:SetText(text)
    end
    applyCheckboxHitRect(check, label, check.optionLabelWidth or 0)
end

local function createCheckbox(id, text, x, y, callback)
    local name = addonName .. "Option" .. id
    local check = CreateFrame(
        "CheckButton",
        name,
        panel,
        "InterfaceOptionsCheckButtonTemplate"
    )
    check:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)

    local label = check:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("LEFT", check, "RIGHT", LABEL_GAP, 1)
    -- The label comes from the locale, keyed by the SAME id the help popup uses.
    -- Label and help heading are the same words, so deriving both from one place
    -- is what stops them drifting apart; `text` stays as the English fallback.
    label:SetText(helpHeading(id) or text)
    -- The label is capped to its COLUMN and wraps inside it. Without the cap a
    -- long label ran across the column gap and into the next column's
    -- control; with it, the two columns of labels line up and a long label
    -- takes a second line instead of a second column.
    local labelWidth = columnLabelWidth(x)
    if type(label.SetWidth) == "function" then
        label:SetWidth(labelWidth)
    end
    if type(label.SetWordWrap) == "function" then
        label:SetWordWrap(true)
    end
    if type(label.SetJustifyH) == "function" then
        label:SetJustifyH("LEFT")
    end
    check.optionLabel = label
    -- What Options.Refresh needs to put the label back the way the locale
    -- says it should be, and to re-measure it.
    check.optionText = text
    check.optionHelpKey = id
    check.optionLabelWidth = labelWidth
    check:SetScript("OnClick", function(self)
        callback(self:GetChecked() == true)
    end)
    applyCheckboxHitRect(check, label, labelWidth)
    attachHelp(check, id)
    controls[id] = check
    checkboxes[#checkboxes + 1] = check
    return check
end

-- Apply the empty-field mode rule.
--
-- The rule lives in Core (one implementation, so the Options page and the
-- settings normalise cannot disagree). It forces the mode to "Disabled"
-- while no field is enabled -- and REMEMBERS the mode the player had, so
-- re-enabling a field restores it. The old code forced the mode here AND
-- in the normalise, and neither remembered anything, so unticking every
-- field lost the mode permanently.
local function applyEmptyFieldModeRule()
    local core = namespace.Core
    if type(core) == "table"
        and type(core.ApplyTooltipFieldModeRule) == "function" then
        return core.ApplyTooltipFieldModeRule()
    end
    return nil
end

local function createFieldCheckbox(id, text, key, x, y)
    return createCheckbox(id, text, x, y, function(value)
        local fields = fieldSettings()
        if not fields then
            return
        end
        fields[key] = value
        applyEmptyFieldModeRule()
        applyTooltipSettings()
    end)
end

local function setMode(value)
    local tooltip = tooltipSettings()
    if not tooltip then
        return
    end
    for _, choice in ipairs(MODE_CHOICES) do
        if choice.value == value then
            -- The EXPLICIT pick is recorded first, so the empty-field rule
            -- below remembers THIS mode (not the one it replaced) if no
            -- field is enabled.
            tooltip.mode = value
            if value == "Disabled" then
                -- An explicit "Disabled" is the player's own choice: it is
                -- not a forced state, so nothing is remembered and nothing
                -- is restored later.
                tooltip.modeDisabledByEmptyFields = nil
                tooltip.modeBeforeEmptyFields = nil
            end
            applyEmptyFieldModeRule()
            applyTooltipSettings()
            return
        end
    end
end

local function createModeDropdown()
    local label = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -108)
    label:SetText(helpHeading("mode") or "Tooltip mode")
    createHelpRegion("ModeLabel", 14, -104, 112, 22, "mode")

    local dropDown = CreateFrame(
        "Frame",
        addonName .. "TooltipModeDropdown",
        panel,
        "UIDropDownMenuTemplate"
    )
    dropDown:SetPoint("TOPLEFT", panel, "TOPLEFT", 132, -96)
    UIDropDownMenu_SetWidth(dropDown, 150)
    UIDropDownMenu_Initialize(dropDown, function(frame)
        for _, choice in ipairs(MODE_CHOICES) do
            local info = UIDropDownMenu_CreateInfo()
            -- The label comes from the locale, resolved at MENU-BUILD time --
            -- so the list a player opens reads in their language.
            info.text = choiceText(choice)
            info.value = choice.value
            info.checked = false
            info.func = function(item)
                local selected = item and item.value
                UIDropDownMenu_SetSelectedValue(frame, selected)
                setMode(selected)
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    attachHelp(dropDown, "mode")
    local dropDownButton = _G[addonName .. "TooltipModeDropdownButton"]
    if type(dropDownButton) == "table" then
        attachHelp(dropDownButton, "mode")
    end
    controls.mode = dropDown
end

local function createEquipmentHelpRegion(id, x, y, width, height, helpKey)
    local region = CreateFrame(
        "Frame",
        addonName .. "EquipmentHelp" .. id,
        equipmentPanel
    )
    region:SetPoint("TOPLEFT", equipmentPanel, "TOPLEFT", x, y)
    region:SetSize(width, height)
    region:EnableMouse(true)
    attachHelp(region, helpKey)
    equipmentControls[id .. "Help"] = region
    return region
end

local function createEquipmentCheckbox(id, text, y, callback)
    local check = CreateFrame(
        "CheckButton",
        addonName .. "Option" .. id,
        equipmentPanel,
        "InterfaceOptionsCheckButtonTemplate"
    )
    check:SetPoint("TOPLEFT", equipmentPanel, "TOPLEFT", 16, y)
    local label = check:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("LEFT", check, "RIGHT", LABEL_GAP, 1)
    -- The label comes from the locale, keyed by the SAME id the help popup uses.
    -- Label and help heading are the same words, so deriving both from one place
    -- is what stops them drifting apart; `text` stays as the English fallback.
    label:SetText(helpHeading(id) or text)
    -- Capped to the panel's content width and wrapped, on the same rule as the
    -- tooltip page's columns: a label may not run past the content, and the
    -- hit rect may not either.
    local labelWidth = PANEL_CONTENT_RIGHT - 16 - CHECKBOX_SIZE - LABEL_GAP
    if type(label.SetWidth) == "function" then
        label:SetWidth(labelWidth)
    end
    if type(label.SetWordWrap) == "function" then
        label:SetWordWrap(true)
    end
    if type(label.SetJustifyH) == "function" then
        label:SetJustifyH("LEFT")
    end
    check.optionLabel = label
    -- What Options.Refresh needs to put the label back the way the locale
    -- says it should be, and to re-measure it.
    check.optionText = text
    check.optionHelpKey = id
    check.optionLabelWidth = labelWidth
    check:SetScript("OnClick", function(self)
        callback(self:GetChecked() == true)
    end)
    -- The hit rect covers the button and its label, and nothing beyond --
    -- the same helper the tooltip page uses, so the two pages cannot drift
    -- apart and the measurement is refreshed the same way on both.
    applyCheckboxHitRect(check, label, labelWidth)
    attachHelp(check, id)
    equipmentControls[id] = check
    equipmentCheckboxes[#equipmentCheckboxes + 1] = check
    return check
end

local function setEquipmentMode(value)
    local equipmentDisplay = equipmentDisplaySettings()
    if not equipmentDisplay then
        return
    end
    for _, choice in ipairs(EQUIPMENT_MODE_CHOICES) do
        if choice.value == value then
            equipmentDisplay.mode = value
            applyEquipmentSettings()
            return
        end
    end
end

local function createEquipmentModeDropdown()
    local label = equipmentPanel:CreateFontString(
        nil,
        "ARTWORK",
        "GameFontNormal"
    )
    label:SetPoint("TOPLEFT", equipmentPanel, "TOPLEFT", 16, -62)
    label:SetText(helpHeading("equipmentMode") or "Character & Inspect summary")
    createEquipmentHelpRegion(
        "ModeLabel",
        14,
        -58,
        210,
        22,
        "equipmentMode"
    )

    local dropDown = CreateFrame(
        "Frame",
        addonName .. "EquipmentSummaryModeDropdown",
        equipmentPanel,
        "UIDropDownMenuTemplate"
    )
    dropDown:SetPoint("TOPLEFT", equipmentPanel, "TOPLEFT", 230, -50)
    UIDropDownMenu_SetWidth(dropDown, 150)
    UIDropDownMenu_Initialize(dropDown, function(frame)
        for _, choice in ipairs(EQUIPMENT_MODE_CHOICES) do
            local info = UIDropDownMenu_CreateInfo()
            -- The label comes from the locale, exactly as the tooltip-mode
            -- dropdown's does.
            info.text = choiceText(choice)
            info.value = choice.value
            info.checked = false
            info.func = function(item)
                local selected = item and item.value
                UIDropDownMenu_SetSelectedValue(frame, selected)
                setEquipmentMode(selected)
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    attachHelp(dropDown, "equipmentMode")
    local dropDownButton = _G[
    addonName .. "EquipmentSummaryModeDropdownButton"
    ]
    if type(dropDownButton) == "table" then
        attachHelp(dropDownButton, "equipmentMode")
    end
    equipmentControls.mode = dropDown
end

local function resetEquipmentPositions()
    -- The button's result was discarded, so a raise here left the player with
    -- a pressed button and no change and no message. The action is bounded and
    -- counted now (runOptionsAction).
    return runOptionsAction("reset the summary positions", function()
        local core = namespace.Core
        if type(core) == "table"
            and type(core.ResetEquipmentPositions) == "function" then
            local result = core.ResetEquipmentPositions()
            Options.Refresh()
            return result ~= false
        end

        local equipmentDisplay = equipmentDisplaySettings()
        if not equipmentDisplay then
            return false
        end
        equipmentDisplay.characterPosition = nil
        equipmentDisplay.inspectPosition = nil
        local frames = namespace.Frames
        if type(frames) == "table"
            and type(frames.ResetPositions) == "function" then
            frames.ResetPositions()
        end
        applyEquipmentSettings()
        return true
    end)
end

local function createEquipmentPanel()
    if equipmentPanel then
        return
    end

    equipmentPanel = CreateFrame(
        "Frame",
        addonName .. "EquipmentOptionsPanel"
    )
    equipmentPanel.name = EQUIPMENT_CATEGORY_NAME

    local title = equipmentPanel:CreateFontString(
        nil,
        "ARTWORK",
        "GameFontNormalLarge"
    )
    title:SetPoint("TOPLEFT", equipmentPanel, "TOPLEFT", 16, -18)
    title:SetText(EQUIPMENT_CATEGORY_NAME)
    title:SetTextColor(0.66, 0.48, 0.86)

    createEquipmentModeDropdown()
    createEquipmentCheckbox(
        "EquipmentShowUnenhanced",
        "Show Unenhanced GS in Detailed",
        -106,
        function(value)
            local equipmentDisplay = equipmentDisplaySettings()
            if equipmentDisplay then
                equipmentDisplay.showUnenhanced = value
                applyEquipmentSettings()
            end
        end
    )
    createEquipmentCheckbox(
        "EquipmentUnlockPositions",
        "Unlock summary positions",
        -140,
        function(value)
            local equipmentDisplay = equipmentDisplaySettings()
            if equipmentDisplay then
                equipmentDisplay.locked = not value
                applyEquipmentSettings()
            end
        end
    )

    local reset = CreateFrame(
        "Button",
        addonName .. "ResetEquipmentPositionsButton",
        equipmentPanel,
        "UIPanelButtonTemplate"
    )
    reset:SetSize(210, 24)
    reset:SetPoint("TOPLEFT", equipmentPanel, "TOPLEFT", 16, -184)
    reset:SetText("Reset summary positions")
    reset:SetScript("OnClick", resetEquipmentPositions)
    attachHelp(reset, "equipmentResetPositions")
    equipmentControls.resetPositions = reset

    equipmentPanel:SetScript("OnShow", Options.Refresh)
    equipmentPanel:SetScript("OnHide", function()
        if activeHelpOwner then
            hideHelp(activeHelpOwner)
        end
    end)
    equipmentPanel:Hide()
end

local function safeIntegrationStatus()
    local adapter = namespace.TacoTipAdapter
    if type(adapter) ~= "table" then
        return false, "not initialized"
    end

    local internalReason
    if type(adapter.GetInternalReason) == "function" then
        internalReason = adapter.GetInternalReason()
    end
    if type(internalReason) == "string" and internalReason ~= "" then
        return false, INTEGRATION_REASONS[internalReason] or "details unavailable"
    end

    if type(adapter.GetCompatibility) ~= "function" then
        return false, "not initialized"
    end
    local supported, reason = adapter.GetCompatibility()
    if supported == true then
        return true, "compatible"
    end
    return false, INTEGRATION_REASONS[reason] or "details unavailable"
end

local function normalizedEnhancementStatus(value)
    if value == true then
        return "complete"
    elseif value == false then
        return "unavailable"
    elseif type(value) ~= "string" then
        return "not observed"
    end

    local statuses = {
        available = "complete",
        complete = "complete",
        conclusive = "complete",
        unavailable = "unavailable",
        incomplete = "unavailable",
        pending = "pending",
        suppressed = "suppressed",
        unknown = "not observed",
        ["not-observed"] = "not observed",
    }
    return statuses[value] or "not observed"
end

local function safeEnhancementStatus()
    local tooltips = namespace.Tooltips
    if type(tooltips) ~= "table"
        or type(tooltips.GetEnhancementStatus) ~= "function" then
        return "not observed", nil
    end

    local ok, first, second, third, fourth, fifth =
        pcall(tooltips.GetEnhancementStatus)
    if not ok then
        return "not observed", nil
    end

    local status = first
    local reason = second
    local scope = third
    local slotID = fourth
    local itemID = fifth
    if type(first) == "table" then
        if first.available ~= nil then
            status = first.available
        else
            status = first.status or first.availability
        end
        reason = first.reason
        scope = first.scope
        slotID = first.slotID
        itemID = first.itemID
    end

    if scope ~= "remote" then
        return "not observed", nil, nil
    end
    local safeStatus = normalizedEnhancementStatus(status)
    local reasonCode
    if type(reason) == "string"
        and string.len(reason) <= 64
        and string.match(reason, "^[a-z0-9%-]+$") then
        reasonCode = reason
    end
    local safeReason, diagnosticOnly = resolveEnhancementReason(reason)
    local blocker
    if safeStatus == "unavailable"
        and DIAGNOSTIC_SLOTS[slotID] == true
        and reasonCode then
        blocker = { slotID = slotID, reason = reasonCode }
        if type(itemID) == "number"
            and itemID > 0
            and itemID % 1 == 0
            and itemID ~= math.huge then
            blocker.itemID = itemID
        end
    end
    return safeStatus, safeReason, blocker, reasonCode, diagnosticOnly
end

local function refreshStatus()
    local integrationText = controls.integrationStatus
    local remoteText = controls.remoteStatus
    local blockerText = controls.blockerStatus
    if not integrationText or not remoteText or not blockerText then
        return
    end

    local compatible, integration = safeIntegrationStatus()
    local remoteStatus, remoteReason, blocker, reasonCode, diagnosticOnly =
        safeEnhancementStatus()
    integrationText:SetText("TacoTip integration: " .. integration)
    updateStatusHelpRegion(integrationText, controls.IntegrationStatusHelp)
    if compatible then
        integrationText:SetTextColor(SUCCESS_RED, SUCCESS_GREEN, SUCCESS_BLUE)
    else
        integrationText:SetTextColor(WARNING_RED, WARNING_GREEN, WARNING_BLUE)
    end

    local remote = "Remote enhancement analysis: " .. remoteStatus
    if remoteReason and not blocker then
        remote = remote .. " (" .. remoteReason
        -- A diagnostic-only reason carries its index in the code, so the raw
        -- code stays out of the player-facing line and remains where it
        -- belongs: the diagnostic-slot blocker line below.
        if reasonCode and not diagnosticOnly then
            remote = remote .. "; " .. reasonCode
        end
        remote = remote .. ")"
    elseif reasonCode and not blocker then
        remote = remote .. " (" .. reasonCode .. ")"
    end
    remoteText:SetText(remote)
    updateStatusHelpRegion(remoteText, controls.RemoteStatusHelp)
    if remoteStatus == "complete" then
        remoteText:SetTextColor(SUCCESS_RED, SUCCESS_GREEN, SUCCESS_BLUE)
    elseif remoteStatus == "unavailable" then
        remoteText:SetTextColor(WARNING_RED, WARNING_GREEN, WARNING_BLUE)
    else
        remoteText:SetTextColor(NEUTRAL_RED, NEUTRAL_GREEN, NEUTRAL_BLUE)
    end

    if blocker then
        local detail = "Remote enhancement blocker: Slot "
            .. blocker.slotID .. " - " .. blocker.reason
        if blocker.itemID then
            detail = detail .. " - item " .. blocker.itemID
        end
        blockerText:SetText(detail)
        updateStatusHelpRegion(blockerText, controls.BlockerStatusHelp)
        blockerText:SetTextColor(WARNING_RED, WARNING_GREEN, WARNING_BLUE)
        blockerText:Show()
        if controls.BlockerStatusHelp then
            controls.BlockerStatusHelp:Show()
        end
    else
        if controls.BlockerStatusHelp then
            hideHelp(controls.BlockerStatusHelp)
            controls.BlockerStatusHelp:Hide()
        end
        blockerText:SetText("")
        updateStatusHelpRegion(blockerText, controls.BlockerStatusHelp)
        blockerText:Hide()
    end
end

local function resetEnhancerSettings()
    -- Bounded and counted: the button's result used to be discarded, so a
    -- raise left the player with a pressed button, no change and no message.
    return runOptionsAction("reset the enhancer settings", function()
        local core = namespace.Core
        if type(core) ~= "table" or type(core.ResetSettings) ~= "function" then
            noteActionFailure("reset the enhancer settings",
                "Core.ResetSettings is missing",
                "the enhancer settings could not be reset: Core.ResetSettings is missing.")
            return false
        end
        local result = core.ResetSettings()
        if result == false then
            Options.Refresh()
            return false
        end
        adoptReturnedSettings(result)
        Options.Refresh()
        return true
    end)
end

local function restoreTacoTipSettings()
    -- Bounded and counted, for the same reason as resetEnhancerSettings.
    return runOptionsAction("restore the TacoTip settings", function()
        local core = namespace.Core
        if type(core) ~= "table"
            or type(core.RestoreTacoTipSettings) ~= "function" then
            noteActionFailure("restore the TacoTip settings",
                "Core.RestoreTacoTipSettings is missing",
                "the TacoTip settings could not be restored: "
                    .. "Core.RestoreTacoTipSettings is missing.")
            return false
        end
        local result = core.RestoreTacoTipSettings()
        if result == false then
            Options.Refresh()
            return false
        end
        adoptReturnedSettings(result)
        Options.Refresh()
        return true
    end)
end

local function createActionButton(name, text, x, callback, helpKey, y)
    local button = CreateFrame("Button", name, panel, "UIPanelButtonTemplate")
    button:SetSize(210, 24)
    button:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y or -350)
    -- Same rule as the checkboxes: the label is the help heading, so a button
    -- and its help popup can never say different things.
    button:SetText(helpHeading(helpKey) or text)
    button:SetScript("OnClick", callback)
    attachHelp(button, helpKey)
    return button
end

-- Say one thing in the chat frame.
--
-- A button that does nothing is the worst kind of broken: the player clicks
-- it, nothing happens, and there is nothing to tell them why. The two
-- action buttons that call into another module used to guard their call and
-- RETURN, in silence -- so this helper is what they use to name the surface
-- that is missing.
--
-- The wording and the colour follow Core.lua's recordInitializeFailure, so
-- every "this surface is unavailable" line in the add-on reads the same.
--
-- This is an ASSIGNMENT, not a `local function`, because the counted
-- action-failure boundary further up needs to print through it and that
-- boundary is declared BEFORE this point in the file. The forward
-- declaration lives with the boundary.
printOptionsLine = function(message)
    if type(_G.DEFAULT_CHAT_FRAME) == "table"
        and type(_G.DEFAULT_CHAT_FRAME.AddMessage) == "function" then
        pcall(_G.DEFAULT_CHAT_FRAME.AddMessage, _G.DEFAULT_CHAT_FRAME,
            "|cffff5555TacoTip Extras:|r " .. tostring(message))
    end
end

local function createPanel()
    if panel then
        return
    end

    panel = CreateFrame("Frame", addonName .. "OptionsPanel")
    panel.name = CATEGORY_NAME

    local icon = panel:CreateTexture(nil, "ARTWORK")
    icon:SetSize(44, 44)
    icon:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
    icon:SetTexture(ICON_PATH)

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 70, -18)
    title:SetText(CATEGORY_NAME)
    title:SetTextColor(0.66, 0.48, 0.86)

    local description = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    description:SetPoint("TOPLEFT", panel, "TOPLEFT", 70, -44)
    description:SetWidth(520)
    description:SetJustifyH("LEFT")
    description:SetText(INTRO_TEXT)
    controls.description = description

    createCheckbox("Enabled", "Enable addon", 16, -78, function(value)
        if type(settings) == "table" then
            settings.enabled = value
            applyAllSettings()
        end
    end)

    createModeDropdown()

    createCheckbox("ShiftDetailed", "Shift for Detailed", 16, -132, function(value)
        local tooltip = tooltipSettings()
        if tooltip then
            tooltip.shiftToDetailed = value
            applyTooltipSettings()
        end
    end)

    local fieldsTitle = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fieldsTitle:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -162)
    fieldsTitle:SetText(helpHeading("fields") or "Tooltip fields")
    createHelpRegion("FieldsTitle", 14, -158, 112, 22, "fields")

    createFieldCheckbox("GearScore", "Show Current GS", "gearScore", 16, -184)
    createFieldCheckbox("BaseGS", "Show Unenhanced GS", "baseGS", 16, -210)
    createFieldCheckbox("PotentialGS", "Show Potential GS", "potentialGS", 16, -236)
    createFieldCheckbox("Delta", "Show Delta", "delta", 290, -184)
    createFieldCheckbox(
        "AverageItemLevel",
        "Show Average iLvl",
        "averageItemLevel",
        290,
        -210
    )
    createFieldCheckbox("Completion", "Show Completion", "completion", 290, -236)

    createCheckbox(
        "RestrictLevel70",
        "Restrict Potential, Completion, and warnings to level 70",
        16,
        -266,
        function(value)
            local tooltip = tooltipSettings()
            if tooltip then
                tooltip.restrictEnhancementMetricsToLevel70 = value
                -- The level-70 gate is baked into the SCORED result, so the
                -- cached result still answers the OLD setting. Re-evaluate it
                -- from the cached revision -- no rescan, no re-inspection --
                -- so the three enhancement metrics really do appear (or stop
                -- appearing) the moment the box is ticked.
                local scanner = namespace.Scanner
                if type(scanner) == "table"
                    and type(scanner.Reevaluate) == "function" then
                    -- The re-evaluation's OUTCOME is used, not discarded.
                    --
                    -- The bare pcall threw away even the boolean, so a
                    -- scorer that raised left the cached verdict computed
                    -- under the OLD policy in place, with the checkbox
                    -- flipped and the setting written and NOTHING saying
                    -- so. The re-evaluation now counts and reports its own
                    -- failures, and the count is read here so a failed
                    -- re-evaluation is never mistaken for a successful one.
                    local ok, replaced, failed = pcall(scanner.Reevaluate)
                    if not ok then
                        printOptionsLine(
                            "the score re-evaluation failed: " .. tostring(replaced))
                    elseif type(failed) == "number" and failed > 0 then
                        printOptionsLine("the score re-evaluation failed for "
                            .. tostring(failed)
                            .. " cached result(s); the metrics still show the previous result.")
                    end
                end
                applyTooltipSettings()
            end
        end
    )
    createCheckbox(
        "WarningColors",
        "Completion warning colours",
        16,
        -292,
        function(value)
            local tooltip = tooltipSettings()
            if tooltip then
                tooltip.warningColors = value
                applyTooltipSettings()
            end
        end
    )
    createCheckbox("ShowMinimap", "Show minimap button", 16, -318, function(value)
        local minimap = minimapSettings()
        if minimap then
            minimap.show = value
            applyMinimapSettings()
        end
    end)

    createCheckbox(
        "ShowServerRank",
        "Show server leaderboard rank",
        290,
        -266,
        function(value)
            local tooltip = tooltipSettings()
            if tooltip then
                tooltip.show_server_rank = value
                tooltip.showServerRank = value
                applyTooltipSettings()
            end
        end
    )

    -- W11 density: comfortable rows for the leaderboard. One boolean in the
    -- existing settings table (no new SavedVariables); the browser rebuilds
    -- at the new row height when it flips.
    createCheckbox(
        "ComfortableRows",
        "Comfortable rows",
        290,
        -292,
        function(value)
            if type(settings) == "table" then
                settings.comfortableRows = value == true
                rebuildLeaderboard("Comfortable rows")
            end
        end
    )

    -- Shaman Blue. The class colour is painted in three places -- the unit
    -- tooltip, the character/inspect summary frame and the leaderboard row --
    -- and all three read the SAME resolver in Core, so all three have to be
    -- repainted when the setting changes.
    createCheckbox(
        "ShamanBlue",
        "Shaman Blue",
        290,
        -318,
        function(value)
            if type(settings) == "table" then
                settings.shamanBlue = value == true
                applyAllSettings()
                rebuildLeaderboard("Shaman Blue")
            end
        end
    )

    -- Top-right of the page, on the title row.
    --
    -- It used to sit at (290, -44), which is ON TOP of the description text:
    -- the description is 520 wide starting at x=70, so it spans 70..590 and the
    -- button landed in the middle of that band. Overlapping the paragraph is
    -- both ugly and a poor click target, which is why it read as hard to hit.
    -- Moving it up clears the description entirely: the title is short and the
    -- button starts at 376, so nothing shares those pixels.
    controls.openLeaderboard = createActionButton(
        addonName .. "OpenLeaderboardButton",
        "Open Server Leaderboard",
        376,
        function()
            local browser = namespace.RankBrowser
            if type(browser) == "table" and type(browser.Toggle) == "function" then
                runBrowserAction("Toggle", "open the server leaderboard")
                return
            end
            -- The button was pressed and NOTHING happened. Say which module
            -- is missing, so the click is not a dead end.
            printOptionsLine(
                "the server leaderboard is unavailable: RankBrowser.Toggle is missing.")
        end,
        "openLeaderboard",
        -14
    )

    controls.restore = createActionButton(
        addonName .. "RestoreTacoTipButton",
        "Restore TacoTip settings",
        16,
        restoreTacoTipSettings,
        "restore"
    )
    controls.reset = createActionButton(
        addonName .. "ResetSettingsButton",
        "Reset enhancer settings",
        242,
        resetEnhancerSettings,
        "reset"
    )

    -- Scan control, mirroring the leaderboard header's.
    --
    -- Placed on its own row below Restore/Reset rather than beside them: two
    -- 210-wide buttons already span x=16..452 of a 590-wide page, so a third
    -- would run off the edge. It calls the same RankBrowser.StartScan the
    -- header does, so there is one implementation of "start a scan", not two
    -- that can drift.
    controls.scanNow = createActionButton(
        addonName .. "ScanNowButton",
        "Scan now",
        16,
        function()
            local browser = namespace.RankBrowser
            if type(browser) == "table" and type(browser.StartScan) == "function" then
                runBrowserAction("StartScan", "start a scan")
                return
            end
            -- The button was pressed and NOTHING happened. Say which module
            -- is missing, so the click is not a dead end.
            printOptionsLine(
                "the scan is unavailable: RankBrowser.StartScan is missing.")
        end,
        "scanNow",
        -384
    )

    -- Progress rail for the same scan. Both surfaces read
    -- RankBrowser.RefreshProgress, so they cannot show different numbers.
    local scanBar = CreateFrame("StatusBar", addonName .. "ScanBar", panel)
    scanBar:SetSize(436, 14)
    scanBar:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -414)
    if type(scanBar.SetStatusBarTexture) == "function" then
        scanBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    end
    if type(scanBar.SetStatusBarColor) == "function" then
        scanBar:SetStatusBarColor(0.66, 0.48, 0.86)
    end
    scanBar:SetMinMaxValues(0, 1)
    scanBar:SetValue(0)
    scanBar:Hide()
    controls.scanBar = scanBar

    -- Drive the rail from the same Scanner.GetProgress the browser uses. The
    -- poll is cheap and returns immediately when the page is hidden or there is
    -- no scan, so an open settings window does not cost frame time at idle.
    local scanAccum = 0
    panel:SetScript("OnUpdate", function(_, elapsed)
        if type(panel.IsShown) == "function" and not panel:IsShown() then
            return
        end
        scanAccum = scanAccum + (elapsed or 0)
        if scanAccum < 0.25 then
            return
        end
        scanAccum = 0
        local scanner = namespace.Scanner
        if type(scanner) ~= "table" or type(scanner.GetProgress) ~= "function" then
            scanBar:Hide()
            return
        end
        local progress = scanner.GetProgress()
        if type(progress) ~= "table"
            or (progress.percent <= 0 and not progress.active) then
            scanBar:Hide()
            return
        end
        scanBar:Show()
        scanBar:SetValue(progress.percent)
    end)

    local explanationTitle = panel:CreateFontString(
        nil,
        "ARTWORK",
        "GameFontNormal"
    )
    explanationTitle:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -416)
    explanationTitle:SetText("How these scores work")
    controls.scoreExplanationTitle = explanationTitle

    local previousExplanation = explanationTitle
    local explanationParagraphs = {}
    for paragraphText in string.gmatch(SCORE_EXPLANATION, "[^\n]+") do
        local paragraph = panel:CreateFontString(
            nil,
            "ARTWORK",
            "GameFontHighlightSmall"
        )
        paragraph:SetPoint(
            "TOPLEFT",
            previousExplanation,
            "BOTTOMLEFT",
            0,
            -6
        )
        paragraph:SetWidth(590)
        paragraph:SetJustifyH("LEFT")
        paragraph:SetText(paragraphText)
        explanationParagraphs[#explanationParagraphs + 1] = paragraph
        previousExplanation = paragraph
    end
    controls.scoreExplanationParagraphs = explanationParagraphs

    local integrationStatus = panel:CreateFontString(
        nil,
        "ARTWORK",
        "GameFontHighlightSmall"
    )
    integrationStatus:SetPoint(
        "TOPLEFT",
        previousExplanation,
        "BOTTOMLEFT",
        0,
        -12
    )
    integrationStatus:SetWidth(590)
    integrationStatus:SetJustifyH("LEFT")
    controls.integrationStatus = integrationStatus
    createStatusHelpRegion(
        "IntegrationStatus",
        integrationStatus,
        "integrationStatus"
    )

    local remoteStatus = panel:CreateFontString(
        nil,
        "ARTWORK",
        "GameFontHighlightSmall"
    )
    remoteStatus:SetPoint(
        "TOPLEFT",
        integrationStatus,
        "BOTTOMLEFT",
        0,
        -4
    )
    remoteStatus:SetWidth(590)
    remoteStatus:SetJustifyH("LEFT")
    controls.remoteStatus = remoteStatus
    createStatusHelpRegion("RemoteStatus", remoteStatus, "remoteStatus")

    local blockerStatus = panel:CreateFontString(
        nil,
        "ARTWORK",
        "GameFontHighlightSmall"
    )
    blockerStatus:SetPoint(
        "TOPLEFT",
        remoteStatus,
        "BOTTOMLEFT",
        0,
        -4
    )
    blockerStatus:SetWidth(590)
    blockerStatus:SetJustifyH("LEFT")
    controls.blockerStatus = blockerStatus
    local blockerHelp = createStatusHelpRegion(
        "BlockerStatus",
        blockerStatus,
        "blockerStatus"
    )
    blockerHelp:Hide()

    local footer = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    footer:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -18, 18)
    footer:SetText(versionCredit())
    footer:SetTextColor(FOOTER_RED, FOOTER_GREEN, FOOTER_BLUE)
    controls.footer = footer

    panel:SetScript("OnShow", Options.Refresh)
    panel:SetScript("OnHide", function()
        if activeHelpOwner then
            hideHelp(activeHelpOwner)
        end
    end)
    panel:Hide()
end

local function registerSlashCommand()
    if type(_G.SlashCmdList) ~= "table" then
        return false
    end
    if not slashHandler then
        slashHandler = function()
            Options.Open()
        end
    end
    -- SLASH_<NAME>1 and SlashCmdList.<NAME> are one pair. Write both through
    -- _G so the declaration and the registration cannot drift apart -- Core.lua
    -- used to spell this differently for the /ttgsdebug pair, with a bare
    -- global on one side.
    _G.SLASH_TTEXTRAS1 = "/ttgs"
    _G.SlashCmdList.TTEXTRAS = slashHandler
    return true
end

-- TacoTip's own options category NAME. A legacy child frame nests only when
-- `childFrame.parent` equals the `name` of the frame it should sit under, so
-- this string has to be the one TacoTip actually registered.
--
-- TacoTip_Forever/options.lua line 4 reads it from the add-on's own TOC
-- metadata and line 452 assigns it to its root options frame, so it is read
-- back from the same place rather than assumed. A wrong string here does not
-- raise -- it silently puts the page at the top level of the options list,
-- which is precisely the kind of defect that ships green.
local function tacoTipCategoryName()
    local addOns = _G.C_AddOns
    if type(addOns) == "table"
        and type(addOns.GetAddOnMetadata) == "function" then
        local ok, title = pcall(addOns.GetAddOnMetadata, "TacoTip", "Title")
        if ok and type(title) == "string" and title ~= "" then
            return title
        end
    end
    if type(_G.GetAddOnMetadata) == "function" then
        local ok, title = pcall(_G.GetAddOnMetadata, "TacoTip", "Title")
        if ok and type(title) == "string" and title ~= "" then
            return title
        end
    end
    return "TacoTip"
end

local function modernSettingsAvailable()
    local api = _G.Settings
    return type(api) == "table"
        and type(api.RegisterCanvasLayoutCategory) == "function"
        and type(api.RegisterCanvasLayoutSubcategory) == "function"
        and type(api.RegisterAddOnCategory) == "function"
        and type(api.OpenToCategory) == "function"
end

-- Modern path: one canvas category with one subcategory beneath it.
local function registerModernCategory()
    local api = _G.Settings
    local ok, registered = pcall(
        api.RegisterCanvasLayoutCategory,
        panel,
        CATEGORY_NAME
    )
    if not ok or type(registered) ~= "table" then
        return false
    end
    local subOK, registeredSub = pcall(
        api.RegisterCanvasLayoutSubcategory,
        registered,
        equipmentPanel,
        EQUIPMENT_CATEGORY_NAME
    )
    if not subOK or type(registeredSub) ~= "table" then
        return false
    end
    if not pcall(api.RegisterAddOnCategory, registered) then
        return false
    end
    if not pcall(api.RegisterAddOnCategory, registeredSub) then
        return false
    end
    category = registered
    return true
end

-- Legacy path, and the same shape TacoTip_Forever/options.lua uses: set
-- `page.parent` to the root frame's `name`, then hand each page to
-- InterfaceOptions_AddCategory, which nests it.
--
-- The equipment page is parented to THIS add-on's main page rather than to
-- TacoTip's root, which is what makes /ttgs open straight to the main category
-- while Esc still shows "Equipment Windows" indented one level under it.
local function registerLegacyCategory()
    local add = _G.InterfaceOptions_AddCategory
    if type(add) ~= "function" then
        return false
    end

    panel.parent = tacoTipCategoryName()
    equipmentPanel.parent = panel.name
    if not pcall(add, panel) then
        return false
    end
    if not pcall(add, equipmentPanel) then
        return false
    end
    category = panel
    return true
end

-- The legacy open path. InterfaceOptionsFrame_OpenToCategory(frame) is the
-- entry point that takes a FRAME; the frame's method takes a category id or
-- name, so the frame's own `name` is the fallback key.
local function openLegacyCategory()
    local opener = _G.InterfaceOptionsFrame_OpenToCategory
    if type(opener) == "function" then
        local ok, result = pcall(opener, category)
        if ok and result ~= false then
            return true
        end
    end
    local frame = _G.InterfaceOptionsFrame
    if type(frame) == "table" and type(frame.OpenToCategory) == "function" then
        local ok, result = pcall(
            frame.OpenToCategory, frame, category.name or category
        )
        return ok and result ~= false
    end
    return false
end

function Options.Initialize(runtimeSettings)
    if type(runtimeSettings) ~= "table" then
        return false
    end
    settings = runtimeSettings

    if initialized then
        registerSlashCommand()
        Options.Refresh()
        return true
    end

    createPanel()
    createEquipmentPanel()

    -- This function used to RETURN FALSE the moment Settings was missing,
    -- which is the same fail-closed shape as the hook bugs already fixed in
    -- this file: no options panel at all, no message anywhere, every setting
    -- unreachable, and Initialize's false is only ever consumed by a guarded()
    -- call in Core that prints one line.
    --
    -- Settings.RegisterCanvasLayoutCategory is in fact present on all five
    -- supported clients, so the legacy arm is a fallback rather than a live
    -- path -- but "not reachable today" is not a reason to refuse the panel,
    -- and the fallback is three lines.
    local registered = false
    if modernSettingsAvailable() then
        registered = registerModernCategory()
    end
    if not registered then
        registered = registerLegacyCategory()
    end

    if not registered then
        registrationMode = "none"
        return false
    end

    registrationMode = (category == panel) and "legacy" or "modern"
    initialized = true
    registerSlashCommand()
    Options.Refresh()
    return true
end

function Options.Open()
    if not initialized or type(category) ~= "table" then
        return false
    end

    if registrationMode == "legacy" then
        return openLegacyCategory()
    end

    local api = _G.Settings
    if type(api) ~= "table" or type(api.OpenToCategory) ~= "function" then
        return false
    end

    local target = category
    if type(category.GetID) == "function" then
        local idOK, categoryID = pcall(category.GetID, category)
        if idOK and categoryID ~= nil then
            target = categoryID
        end
    end
    local ok, result = pcall(api.OpenToCategory, target)
    return ok and result ~= false
end

local function categoryID(value)
    if type(value) ~= "table" or type(value.GetID) ~= "function" then
        return nil
    end
    local ok, id = pcall(value.GetID, value)
    if ok then
        return id
    end
    return nil
end

local function enhancerCategoryIsActive()
    if registrationMode == "legacy" then
        -- The legacy frame reports the CURRENT CATEGORY BY NAME, so the
        -- comparison has to be against the frame's `name` and not against the
        -- frame object the modern API hands back.
        local frame = _G.InterfaceOptionsFrame
        if type(frame) ~= "table"
            or type(frame.IsShown) ~= "function"
            or type(frame.GetCurrentCategory) ~= "function" then
            return false, frame
        end
        local shownOK, shown = pcall(frame.IsShown, frame)
        if not shownOK or shown ~= true then
            return false, frame
        end
        local currentOK, current = pcall(frame.GetCurrentCategory, frame)
        if not currentOK or current == nil then
            return false, frame
        end
        return current == category or current == category.name, frame
    end

    local settingsPanel = _G.SettingsPanel
    if not initialized
        or settingsPanel == nil
        or type(settingsPanel.IsShown) ~= "function"
        or type(settingsPanel.GetCurrentCategory) ~= "function" then
        return false, settingsPanel
    end

    local shownOK, shown = pcall(settingsPanel.IsShown, settingsPanel)
    if not shownOK or shown ~= true then
        return false, settingsPanel
    end
    local currentOK, current = pcall(
        settingsPanel.GetCurrentCategory,
        settingsPanel
    )
    if not currentOK or current == nil then
        return false, settingsPanel
    end
    if current == category then
        return true, settingsPanel
    end
    local currentID = categoryID(current)
    local registeredID = categoryID(category)
    return currentID ~= nil and currentID == registeredID, settingsPanel
end

function Options.Toggle()
    local active, settingsPanel = enhancerCategoryIsActive()
    if active then
        if settingsPanel and type(settingsPanel.Close) == "function" then
            local ok, result = pcall(settingsPanel.Close, settingsPanel, true)
            if ok then
                return result ~= false
            end
        end
        return Options.Open()
    end
    return Options.Open()
end

function Options.Refresh()
    if not panel or type(settings) ~= "table" then
        return false
    end

    local tooltip = tooltipSettings()
    local fields = fieldSettings()
    local minimap = minimapSettings()
    local equipmentDisplay = equipmentDisplaySettings()
    setChecked(controls.Enabled, settings.enabled)
    setChecked(controls.ShiftDetailed, tooltip and tooltip.shiftToDetailed)
    setChecked(controls.GearScore, fields and fields.gearScore)
    setChecked(controls.BaseGS, fields and fields.baseGS)
    setChecked(controls.PotentialGS, fields and fields.potentialGS)
    setChecked(controls.Delta, fields and fields.delta)
    setChecked(controls.AverageItemLevel, fields and fields.averageItemLevel)
    setChecked(controls.Completion, fields and fields.completion)
    setChecked(
        controls.RestrictLevel70,
        tooltip and tooltip.restrictEnhancementMetricsToLevel70
    )
    setChecked(controls.WarningColors, tooltip and tooltip.warningColors)
    setChecked(controls.ShowMinimap, minimap and minimap.show)
    -- Comfortable rows is a TOP-LEVEL setting (not under `tooltip`), and it
    -- was the one checkbox Options.Refresh never synced: the box kept
    -- whatever the player last clicked and never showed the saved value, so
    -- a profile that had it on came up looking off.
    local comfortableRows = false
    if type(settings) == "table" and type(settings.comfortableRows) == "boolean" then
        comfortableRows = settings.comfortableRows
    end
    setChecked(controls.ComfortableRows, comfortableRows)
    -- The Extras' OWN Shaman Blue setting is what this box shows. The main
    -- add-on's setting can veto it (Core.IsShamanBlueEnabled), and the help
    -- text says so -- the box stays editable so the Extras' own preference is
    -- always visible and always the user's to change.
    local shamanBlue = true
    if type(settings) == "table" and type(settings.shamanBlue) == "boolean" then
        shamanBlue = settings.shamanBlue
    end
    setChecked(controls.ShamanBlue, shamanBlue)
    local showRank = true
    if tooltip then
        if tooltip.show_server_rank == false or tooltip.showServerRank == false then
            showRank = false
        end
    end
    setChecked(controls.ShowServerRank, showRank)
    setChecked(
        equipmentControls.EquipmentShowUnenhanced,
        equipmentDisplay and equipmentDisplay.showUnenhanced
    )
    setControlEnabled(
        equipmentControls.EquipmentShowUnenhanced,
        equipmentDisplay and equipmentDisplay.mode == "Detailed"
    )
    setChecked(
        equipmentControls.EquipmentUnlockPositions,
        equipmentDisplay and not equipmentDisplay.locked
    )

    -- The labels are re-set from the locale and their hit rects re-measured on
    -- every refresh. The measurement used to be taken ONCE, at creation,
    -- and it went stale twice over: a FontString measured before its font
    -- is loaded measures ZERO (so the label stops being clickable), and a
    -- locale change rewrites the label's text in place (so the measured
    -- width no longer matches the words on screen).
    for _, control in ipairs(checkboxes) do
        refreshCheckboxLabel(control)
    end
    for _, control in ipairs(equipmentCheckboxes) do
        refreshCheckboxLabel(control)
    end

    local mode = tooltip and tooltip.mode or "Disabled"
    if controls.mode then
        UIDropDownMenu_SetSelectedValue(controls.mode, mode)
        -- The label is the LOCALE's word for the mode, not the stored value:
        -- the dropdown is the one control the player reads the mode from.
        UIDropDownMenu_SetText(controls.mode, modeText(MODE_CHOICES, mode))
    end
    local equipmentMode = equipmentDisplay and equipmentDisplay.mode or "Disabled"
    if equipmentControls.mode then
        UIDropDownMenu_SetSelectedValue(equipmentControls.mode, equipmentMode)
        UIDropDownMenu_SetText(
            equipmentControls.mode,
            modeText(EQUIPMENT_MODE_CHOICES, equipmentMode)
        )
    end
    refreshStatus()
    return true
end
