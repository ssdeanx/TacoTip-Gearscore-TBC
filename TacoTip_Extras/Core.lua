local addonName, namespace = ...

if type(namespace) ~= "table" then
    return
end

local Core = {}
namespace.Core = Core

-- Taint containment.
--
-- `securecall` is the engine's own containment primitive and Blizzard uses it
-- for exactly this shape:
--   - Blizzard_BuffFrame/BuffFrame.lua:991
--     `securecall(self.UpdateDuration, self, self.timeLeft); -- Taint issue
--      with SecondsToTimeAbbrev`
--   - Blizzard_CatalogShop/Blizzard_CatalogShop_Outbound.lua:17
--     `securecall("GameTooltip_Hide");`
--
-- It is an engine global on every supported client; Blizzard captures it as
-- a local the same way it captures `forceinsecure`
-- (Blizzard_FrameXML/SharedPetBattleTemplates.lua:5
-- `local securecall = securecall;`).
--
-- WHY THIS ADD-ON NEEDS IT. Every callback this add-on registers on a
-- BLIZZARD frame -- the shared GameTooltip's scripts, the character and
-- inspect panes, the `InspectFrame_Show` / `InspectFrame_UnitChanged` /
-- `InspectSwitchTabs` post-hooks -- runs as addon code inside that frame's
-- script chain, and the client taints the frame when that happens. The
-- tainted unit frame or inspect frame is a child of UIParent, and the taint
-- reaches the game menu, where the Logout/Quit button (whose callback is the
-- engine function, so a reporter can only name it 'UNKNOWN()') is refused
-- with ADDON_ACTION_FORBIDDEN. The player cannot log out.
--
-- A `hooksecurefunc` post-hook does not replace the hooked function, but its
-- BODY still runs as addon code inside the caller's script chain, so the
-- post-hooks need this as much as the raw HookScript handlers do.
local secureCallFn = nil
if (type(securecall) == "function") then
    -- Probed once at load, for the same reason as main.lua's copy: the probe
    -- proves the engine actually runs a function through `securecall` from
    -- this add-on's context, so a build that ever refused addon code to call
    -- it degrades to the direct call instead of raising on every tooltip
    -- event.
    local probeOk, probeRan = pcall(securecall, function() return 2 end)
    if (probeOk and probeRan and probeRan == 2) then
        secureCallFn = securecall
    end
end

--- Runs a function so that it cannot taint the frame whose script chain it
--- executes in. The fallback (no securecall on this client) keeps the
--- add-on working; it only drops the taint guard.
function Core.RunUntainted(fn, ...)
    if (secureCallFn) then
        return secureCallFn(fn, ...)
    end
    return fn(...)
end

local REQUIRED_SLOTS = {
    1, 2, 3, 5, 6, 7, 8, 9, 10,
    11, 12, 13, 14, 15, 16, 17, 18,
}

local DEBUG_PREFIX = "[TTGSE DEV]"
local eventFrame = CreateFrame("Frame")
local initialized = false
local scheduledGeneration
local database
local futureDatabaseSchema = false
local DEFAULT_MINIMAP_ANGLE = 225
local MAX_EQUIPMENT_POSITION_OFFSET = 4096
local WELCOME_DELAY_SECONDS = 3.1
local welcomeScheduled = false
local welcomePrinted = false

local WELCOME_NAME = "|cffd4a84bTacoTip|r |cffbcc3ccExtras|r"
local WELCOME_CREDIT = "|cffbcc3ccv%s - AcidBomb|r"
local WELCOME_PUN = "|cffd4a84bMay your upgrades be spicy!|r"

local VALID_TOOLTIP_MODES = {
    Disabled = true,
    Minimal = true,
    Compact = true,
    Detailed = true,
}

-- The tooltip mode a FRESH install starts on.
--
-- Changed from "Compact" to "Detailed" on the operator's request (a Classic Era
-- test session): Compact shows at most two summary rows, and the enhancement
-- metrics the Extras exists to show are hidden behind them.
--
-- WHY THERE IS NO MIGRATION FOR EXISTING INSTALLS.
--
-- The saved mode is a plain string in `settings.tooltip.mode`. Nothing in the
-- settings table records whether the USER chose it or whether it is simply the
-- old default that was written once and never touched. "Compact" is therefore
-- ambiguous: it may be an untouched old default, or a deliberate choice.
--
-- Two levers were considered and both are wrong:
--
--   - Overriding a saved "Compact" would silently overwrite a deliberate
--     choice. The user asked for a new DEFAULT, not for their saved setting
--     to be thrown away.
--   - Bumping `schema` would be a migration, but `initializeDatabase` treats
--     `schema > 2` as a FUTURE schema it does not understand and force-sets
--     `equipmentDisplay.mode = "Disabled"`, which breaks the character and
--     inspect windows. A schema bump is not a free lever here.
--
-- So the saved mode is left exactly as the user left it, and an existing
-- install reaches Detailed through the Options panel: the "Reset enhancer
-- settings" button (Core.ResetSettings) restores every default, and the
-- "Tooltip mode" dropdown selects Detailed directly.
local DEFAULT_TOOLTIP_MODE = "Detailed"

local VALID_EQUIPMENT_DISPLAY_MODES = {
    Disabled = true,
    Basic = true,
    Detailed = true,
}

-- The tooltip fields the mode rule below is about. Kept here, next to the
-- mode table, so the rule and the mode cannot drift apart.
local TOOLTIP_FIELD_KEYS = {
    "gearScore",
    "baseGS",
    "potentialGS",
    "delta",
    "averageItemLevel",
    "completion",
}

-- The empty-field rule.
--
-- "Disabled" is the add-on's "I render nothing and I am not holding the
-- player's GearScore" state. An EMPTY field set has to mean the same thing:
-- with no field enabled there is nothing to render, and leaving the mode
-- alone would leave the add-on holding the player's GearScore while drawing
-- no rows -- which is exactly the state "Disabled" exists to prevent.
--
-- So the mode IS forced to "Disabled" while no field is enabled. What changed
-- is that the forcing is RECOVERABLE:
--
--   * it happens only when the mode was not already "Disabled", so an
--     explicit "Disabled" the player chose is never mistaken for a forced
--     one, and is never overwritten;
--   * the mode the player had is REMEMBERED, and restored as soon as a
--     field comes back.
--
-- It used to be forced on EVERY normalise, so the mode was lost for good:
-- re-ticking one field left the mode "Disabled" and the tooltip stayed dark
-- until the player picked a mode by hand.
--
-- The second alternative -- leave the mode alone and let the render gate
-- handle an empty field set -- was rejected: the render gate draws no rows
-- for an empty field set, but the add-on would KEEP the player's GearScore,
-- which is the half of "Disabled" that matters.
local function applyTooltipFieldModeRule(tooltipSettings)
    if type(tooltipSettings) ~= "table" then
        return nil
    end
    local fields = tooltipSettings.fields
    if type(fields) ~= "table" then
        return tooltipSettings.mode
    end

    local anyField = false
    for _, key in ipairs(TOOLTIP_FIELD_KEYS) do
        if fields[key] == true then
            anyField = true
            break
        end
    end

    if anyField then
        -- A field is enabled again: bring back the mode the empty set had
        -- forced off, if there was one.
        if tooltipSettings.modeDisabledByEmptyFields == true then
            local restore = tooltipSettings.modeBeforeEmptyFields
            if VALID_TOOLTIP_MODES[restore] and restore ~= "Disabled" then
                tooltipSettings.mode = restore
            end
            tooltipSettings.modeDisabledByEmptyFields = nil
            tooltipSettings.modeBeforeEmptyFields = nil
        end
        return tooltipSettings.mode
    end

    if tooltipSettings.mode ~= "Disabled" then
        if VALID_TOOLTIP_MODES[tooltipSettings.mode] then
            tooltipSettings.modeBeforeEmptyFields = tooltipSettings.mode
        end
        tooltipSettings.mode = "Disabled"
        tooltipSettings.modeDisabledByEmptyFields = true
    end
    return tooltipSettings.mode
end

local function defaultBoolean(target, key, value)
    if type(target[key]) ~= "boolean" then
        target[key] = value
    end
end

local function isFiniteNumber(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function copyTable(value, seen)
    if type(value) ~= "table" then
        return value
    end
    seen = seen or {}
    if seen[value] then
        return seen[value]
    end
    local result = {}
    seen[value] = result
    for key, entry in pairs(value) do
        result[copyTable(key, seen)] = copyTable(entry, seen)
    end
    return result
end

local function normalizeEquipmentPosition(value)
    if type(value) ~= "table"
        or not isFiniteNumber(value.x)
        or not isFiniteNumber(value.y)
        or math.abs(value.x) > MAX_EQUIPMENT_POSITION_OFFSET
        or math.abs(value.y) > MAX_EQUIPMENT_POSITION_OFFSET then
        return nil
    end
    return {
        x = value.x,
        y = value.y,
    }
end

-- The equipment-summary defaults a fresh profile starts from.
--
-- ONE function, because there is ONE set of defaults. This used to be two
-- byte-identical functions -- setFreshEquipmentDisplayDefaults and
-- setMigratedEquipmentDisplayDefaults -- whose names promised a distinction
-- the bodies did not make: both wrote exactly the same three values. The
-- names invited a reader to believe a migrated profile got something
-- different, and it never did. The two CALL SITES are still distinct (a
-- fresh database and a migrated one take different branches), and both call
-- this one function.
local function setEquipmentDisplayDefaults(runtime)
    runtime.equipmentDisplay = {
        mode = "Detailed",
        showUnenhanced = false,
        locked = true,
    }
end

function Core.GetVersion()
    local addOns = _G.C_AddOns
    if type(addOns) == "table"
        and type(addOns.GetAddOnMetadata) == "function" then
        local ok, value = pcall(
            addOns.GetAddOnMetadata,
            addonName,
            "Version"
        )
        if ok
            and type(value) == "string"
            and string.match(value, "^%d+%.%d+%.%d+$") then
            return value
        end
    end

    local getMeta = rawget(_G, "GetAddOnMetadata")
    if type(getMeta) == "function" then
        local ok, value = pcall(getMeta, addonName, "Version")
        if ok
            and type(value) == "string"
            and string.match(value, "^%d+%.%d+%.%d+$") then
            return value
        end
    end
    return nil
end

-- WHICH FAMILY IS THIS CLIENT?
--
-- Classic family (Classic Era, TBC, Wrath) vs the mainline pair (Retail and WoW
-- Forever), from the vendored library's project identity. Returns true for
-- classic, false for mainline, nil when it cannot be decided -- callers must
-- treat nil as "unknown", never as either side.
--
-- This is the reliable split: WOW_PROJECT_ID is distinct for the three classic
-- projects, while Retail and WoW Forever share WOW_PROJECT_MAINLINE
-- (Libs/LibForeverInspector/LibForeverInspector.lua:106-117). The library
-- exposes exactly that as IsClassic/IsTBC/IsWotlk, and the main add-on uses the
-- same three methods for its classic-family check (main.lua:969).
function Core.IsClassicFamilyClient()
    local adapter = namespace.TacoTipAdapter
    if type(adapter) ~= "table"
        or type(adapter.GetInspector) ~= "function" then
        return nil
    end
    local ok, inspector = pcall(adapter.GetInspector)
    if not ok or type(inspector) ~= "table" then
        return nil
    end
    for _, method in ipairs({ "IsClassic", "IsTBC", "IsWotlk" }) do
        local ask = inspector[method]
        if type(ask) == "function" then
            local answered, result = pcall(ask, inspector)
            if answered and result == true then
                return true
            end
        end
    end
    -- IsClassic is the method every library shape defines. If it answered and
    -- none of the classic-family methods matched, this is the mainline pair.
    if type(inspector.IsClassic) == "function" then
        return false
    end
    return nil
end

-- THE PvP WIRE RULE'S MARKER.
--
-- Retail and WoW Forever never render inspected PvP data -- both fields are
-- zeroed on the wire -- while the classic family shows the honor rank and the
-- arena rating. The split is decided by client FAMILY, not by a capability
-- probe: a classic client can expose the modern rated-BG API as a stub, and a
-- stub would make it look modern and silently lose the honor-rank line.
--
-- The capability probe survives only as the fallback for a client whose
-- identity cannot be read (the harness's inspector shape, or an adapter that
-- declined) -- which is exactly the behaviour before this change.
function Core.UsesModernPvPSurface()
    local classic = Core.IsClassicFamilyClient()
    if classic ~= nil then
        return not classic
    end
    local paperDoll = rawget(_G, "C_PaperDollInfo")
    return type(paperDoll) == "table"
        and type(paperDoll.GetInspectRatedBGData) == "function"
end

local function welcomeCompatibilityValid()
    local adapter = namespace.TacoTipAdapter
    if type(adapter) ~= "table"
        or type(adapter.GetCompatibility) ~= "function" then
        return false
    end
    local compatibilityOK, supported = pcall(adapter.GetCompatibility)
    if not compatibilityOK or supported ~= true then
        return false
    end
    if type(adapter.GetInternalReason) == "function" then
        local reasonOK, reason = pcall(adapter.GetInternalReason)
        if not reasonOK or (type(reason) == "string" and reason ~= "") then
            return false
        end
    end
    return true
end

local function scheduleOneShot(delay, callback)
    local timer = _G.C_Timer
    if not isFiniteNumber(delay)
        or delay < 0
        or type(callback) ~= "function"
        or type(timer) ~= "table"
        or type(timer.After) ~= "function" then
        return false
    end
    return pcall(timer.After, delay, callback)
end

-- Storage hygiene, stage 2 of the storage-expansion audit (§6.2 item 1): the
-- 60-day prune existed for a whole release but nothing ever INVOKED it, so
-- rows only ever left the database through capacity eviction. It now runs
-- once per session over every realm we know, deferred off the loading screen,
-- and takes realm tables whose last row the prune removed with it.
--
-- "Once" is armed by the FIRST deferred callback that actually runs, not at
-- scheduling time, for two reasons: PLAYER_ENTERING_WORLD also fires on every
-- instance enter/exit (a loading burst can raise it several times, and each
-- raise must not re-walk the database), and a client without a usable
-- C_Timer schedules a callback that never executes -- arming there would
-- retire the prune for the whole session. Retrying on the next
-- PLAYER_ENTERING_WORLD is the self-healing path.
local loginPruneDone = false
local function scheduleLoginPrune()
    return scheduleOneShot(0, function()
        if loginPruneDone then
            return
        end
        loginPruneDone = true
        local ranks = namespace.RankDB
        if type(ranks) == "table"
            and type(ranks.PruneAllRealms) == "function" then
            pcall(ranks.PruneAllRealms)
        end
    end)
end

local function scheduleWelcome(runtimeSettings, initializationSucceeded)
    if welcomeScheduled
        or initializationSucceeded ~= true
        or type(runtimeSettings) ~= "table"
        or runtimeSettings.enabled ~= true then
        return false
    end

    welcomeScheduled = true
    local scheduledOK = scheduleOneShot(WELCOME_DELAY_SECONDS, function()
        if welcomePrinted
            or runtimeSettings.enabled ~= true
            or not welcomeCompatibilityValid() then
            return
        end
        local chat = _G.DEFAULT_CHAT_FRAME
        if type(chat) ~= "table" or type(chat.AddMessage) ~= "function" then
            return
        end
        local version = Core.GetVersion()
        if not version then
            return
        end
        local message = WELCOME_NAME .. " "
            .. string.format(WELCOME_CREDIT, version)
            .. " loaded. " .. WELCOME_PUN
        welcomePrinted = true
        pcall(chat.AddMessage, chat, message)
    end)
    if not scheduledOK then
        welcomeScheduled = false
    end
    return scheduledOK
end

local function normalizeSettings(runtime)
    defaultBoolean(runtime, "enabled", true)
    -- The Shaman Blue switch. It lives at the top level of the settings table,
    -- NOT under `tooltip`, because the class colour it governs is painted in
    -- three places: the unit tooltip, the character/inspect summary frame and
    -- the leaderboard row. Default ON, matching the main add-on's own default
    -- (options.lua: `shaman_blue = true`).
    defaultBoolean(runtime, "shamanBlue", true)
    if type(runtime.tooltip) ~= "table" then
        runtime.tooltip = {}
    end

    local tooltipSettings = runtime.tooltip
    if not VALID_TOOLTIP_MODES[tooltipSettings.mode] then
        -- The DEFAULT tooltip mode. Detailed is what the operator asked for:
        -- Compact hides the enhancement rows behind a two-line summary, and
        -- the whole point of the Extras is those rows.
        --
        -- This only fires when the mode is MISSING or invalid, so it is a
        -- fresh-install default and nothing else. An install that already
        -- saved a mode keeps it -- see the note on DEFAULT_TOOLTIP_MODE
        -- below for why no migration is safe here.
        tooltipSettings.mode = DEFAULT_TOOLTIP_MODE
    end
    defaultBoolean(tooltipSettings, "shiftToDetailed", true)
    defaultBoolean(
        tooltipSettings,
        "restrictEnhancementMetricsToLevel70",
        true
    )
    defaultBoolean(tooltipSettings, "warningColors", true)
    -- TWO spellings of one setting, and both are shipped on purpose.
    --
    -- `show_server_rank` is the ORIGINAL key: it matches the main add-on's own
    -- snake_case setting (TacoTip's options.lua writes `show_server_rank`).
    -- `showServerRank` is the camelCase spelling the Extras' internal
    -- settings snapshot uses (Tooltips.lua publishes `into.showServerRank`).
    --
    -- They are two names for ONE switch, so a reader who finds only one of
    -- them in the settings table should not conclude the other is a separate
    -- option. The value is read as "OFF if EITHER says false" (Tooltips.lua
    -- serverRankEnabled, Options.lua:2138), so turning either off turns the
    -- switch off, and neither spelling can be left behind at the old value
    -- while the other says otherwise. Both are defaulted here so a profile
    -- that has only one of them still normalises.
    defaultBoolean(tooltipSettings, "show_server_rank", true)
    defaultBoolean(tooltipSettings, "showServerRank", true)
    if type(tooltipSettings.fields) ~= "table" then
        tooltipSettings.fields = {}
    end

    local fields = tooltipSettings.fields
    defaultBoolean(fields, "gearScore", true)
    defaultBoolean(fields, "baseGS", false)
    defaultBoolean(fields, "potentialGS", true)
    defaultBoolean(fields, "delta", true)
    defaultBoolean(fields, "averageItemLevel", true)
    defaultBoolean(fields, "completion", true)
    -- The empty-field rule. It used to live inline here as an unconditional
    -- `mode = "Disabled"`, which lost the player's mode for good; it now
    -- lives in ONE place (applyTooltipFieldModeRule) so the Options page
    -- and this normalise cannot disagree, and it is RECOVERABLE -- the mode
    -- the player had is remembered and restored when a field comes back.
    applyTooltipFieldModeRule(tooltipSettings)

    if type(runtime.minimap) ~= "table" then
        runtime.minimap = {}
    end
    defaultBoolean(runtime.minimap, "show", true)
    if not isFiniteNumber(runtime.minimap.angle) then
        runtime.minimap.angle = DEFAULT_MINIMAP_ANGLE
    else
        runtime.minimap.angle = runtime.minimap.angle % 360
    end

    local equipmentSource = type(runtime.equipmentDisplay) == "table"
        and runtime.equipmentDisplay
        or {}
    local showUnenhanced = false
    if type(equipmentSource.showUnenhanced) == "boolean" then
        showUnenhanced = equipmentSource.showUnenhanced
    end
    local locked = true
    if type(equipmentSource.locked) == "boolean" then
        locked = equipmentSource.locked
    end
    local equipmentDisplay = {
        mode = VALID_EQUIPMENT_DISPLAY_MODES[equipmentSource.mode]
            and equipmentSource.mode
            or "Detailed",
        showUnenhanced = showUnenhanced,
        locked = locked,
        characterPosition = normalizeEquipmentPosition(
            equipmentSource.characterPosition
        ),
        inspectPosition = normalizeEquipmentPosition(
            equipmentSource.inspectPosition
        ),
    }

    if futureDatabaseSchema then
        equipmentDisplay.mode = "Disabled"
    end
    runtime.equipmentDisplay = equipmentDisplay

    return runtime
end

local function initializeDatabase()
    -- SavedVariables is TacoTipExtrasDB (was TacoTipGearScoreEnhancerDB before the
    -- 1.0.0 relaunch). A pre-1.0.0 install therefore arrives here with no table at
    -- all, so the `type(...) ~= "table"` arm below is the LOAD-BEARING path, not a
    -- defensive afterthought: an absent DB must initialise cleanly and must not
    -- throw. A stale TacoTipGearScoreEnhancerDB is simply ignored and never read.
    local persistedRoot = _G.TacoTipExtrasDB
    local freshDatabase = type(persistedRoot) ~= "table"
        or next(persistedRoot) == nil

    futureDatabaseSchema = type(persistedRoot) == "table"
        and type(persistedRoot.schema) == "number"
        and persistedRoot.schema > 2

    if futureDatabaseSchema then
        local runtimeRoot = copyTable(persistedRoot)
        if type(runtimeRoot.settings) ~= "table" then
            runtimeRoot.settings = {}
        end
        normalizeSettings(runtimeRoot.settings)
        runtimeRoot.settings.equipmentDisplay.mode = "Disabled"
        database = runtimeRoot
        return runtimeRoot
    end

    local root = persistedRoot
    if freshDatabase then
        root = {}
        _G.TacoTipExtrasDB = root
    end
    if type(root.settings) ~= "table" then
        root.settings = {}
    end

    if freshDatabase then
        setEquipmentDisplayDefaults(root.settings)
    elseif root.schema == 1 then
        setEquipmentDisplayDefaults(root.settings)
    elseif root.schema ~= 2
        or type(root.settings.equipmentDisplay) ~= "table" then
        setEquipmentDisplayDefaults(root.settings)
    end

    root.schema = 2
    normalizeSettings(root.settings)
    database = root
    return root
end

function Core.GetSettings()
    local root = database or initializeDatabase()
    return root.settings
end

-- Apply the empty-field mode rule to the LIVE settings table.
--
-- The Options page owns the moment a field is ticked or unticked, and the
-- rule has to run there -- not only on a normalise, which does not happen
-- when a checkbox changes. The rule itself lives with the mode table above,
-- so there is exactly ONE implementation of it: the Options page and the
-- normalise cannot drift apart.
--
-- Returns the mode in effect afterwards.
function Core.ApplyTooltipFieldModeRule()
    local runtime = database and database.settings or nil
    local tooltip = type(runtime) == "table" and runtime.tooltip or nil
    if type(tooltip) ~= "table" then
        return nil
    end
    return applyTooltipFieldModeRule(tooltip)
end

-- The scoring policy, as the scorer consumes it.
--
-- Scoring.Evaluate(revision, policy) reads `restrictEnhancementMetricsToLevel70`
-- from the policy it is handed. Until now NO call site handed it one, so the
-- scorer's own internal default ("restricted to level 70") applied to every
-- player on every client. The Options checkbox only flipped the RENDER gate, so
-- unchecking it made Potential GS / Delta / Completion read "Unavailable"
-- instead of showing a value -- and on Classic Era and WoW Forever (level cap
-- 60) the three metrics never appeared for anybody at all.
--
-- This is the ONE place that reads the user's setting and hands it to the
-- scorer, so the checkbox and the scorer cannot drift apart again. The value
-- is read from the same live settings table the checkbox writes to
-- (Core.GetSettings() is the table Options holds), and a missing or
-- non-boolean value falls back to the shipped default (restricted), which is
-- what normalizeSettings already guarantees.
function Core.GetEnhancementPolicy()
    -- Read the module's own settings table rather than Core.GetSettings():
    -- GetSettings() INITIALIALISES the database when it has not been
    -- initialised yet, and a policy read must never have that side effect
    -- (it is read from a tooltip render and from a scan, both of which can
    -- run before -- or without -- the add-on's own initialisation).
    --
    -- Before initialisation there is no settings table, and the shipped
    -- default (restricted) is what the add-on would use anyway.
    local runtime = database and database.settings or nil
    local tooltip = type(runtime) == "table" and runtime.tooltip or nil
    local restrict = true
    if type(tooltip) == "table"
        and type(tooltip.restrictEnhancementMetricsToLevel70) == "boolean" then
        restrict = tooltip.restrictEnhancementMetricsToLevel70
    end
    return {
        restrictEnhancementMetricsToLevel70 = restrict,
    }
end

-- ---------------------------------------------------------------------------
-- The Shaman Blue rule
-- ---------------------------------------------------------------------------
--
-- The same rule the main add-on already applies (main.lua: SHAMAN_BLUE_COLOR
-- and getClassColor), reproduced here so the Extras' class name matches the
-- one TacoTip paints.
--
-- THE CROSS-ADD-ON MAPPING, because the ONE setting has THREE names and a
-- reader looking for any one of them has to find the other two:
--
--   main add-on (TacoTip)   TacoTipConfig["shaman_blue"]          snake_case
--   Extras add-on           TacoTipExtrasDB.settings["shamanBlue"]  camelCase
--   locale files            "HELP_SHAMANBLUE_HEADING"                the label
--
-- The locale key is the OPTIONS-PAGE LABEL and nothing else -- it is not read
-- by the rule below. The label used to be carried by "OPT_SHAMAN_BLUE", which
-- is the third name this mapping is usually remembered by; that key was never
-- read by the Options page (it resolves its labels through the HELP_ family
-- above) and was removed from all eleven locale files with the other dead
-- keys, so the live spelling is the HELP_ one.
--
-- The RULE reads the Extras' own `shamanBlue` and the main add-on's
-- `shaman_blue`, and only an explicit boolean `false` in EITHER turns it off.
--
-- WHY IT EXISTS. Classic Era's own client colour for the Shaman is PINK --
-- verified in the client source, not guessed:
--
--   origin/classic_era  Interface/AddOns/Blizzard_SharedXML/Vanilla/ClassColors.lua:9
--       ["SHAMAN"] = CreateColor(0.96, 0.55, 0.73)      <- pink
--   origin/classic_era  Interface/AddOns/Blizzard_SharedXML/TBC/ClassColors.lua:9
--       ["SHAMAN"] = CreateColor(0.0, 0.44, 0.87)        <- blue
--
-- (Classic Era loads the Vanilla one: Blizzard_SharedXML_Vanilla.toc:17.)
-- The blue is the TBC/Wrath Shaman colour and is the colour the main add-on
-- uses, so a player sees ONE colour for their class across both add-ons.
--
-- These are the SAME numbers as the main add-on's, deliberately: r 0.0,
-- g 0.44, b 0.87.
local SHAMAN_BLUE_COLOR = { r = 0.0, g = 0.44, b = 0.87 }

-- Whether the Shaman-blue rule is in force.
--
-- ON only when BOTH the Extras' own setting AND the main add-on's setting
-- allow it, so a player who turns "Shaman Blue" off in TacoTip does not get
-- pink in one add-on and blue in the other.
--
-- The main add-on's value is read DEFENSIVELY. Only an explicit boolean
-- `false` suppresses the rule. A missing TacoTipConfig (TacoTip not loaded),
-- a nil value, or a non-boolean (a corrupted SavedVariables file can hold
-- anything) all degrade to the Extras' own setting instead of silently
-- switching the colour off -- an unreadable value is not a decision.
--
-- The Extras' own value is read from `database.settings` rather than through
-- Core.GetSettings(), for the same reason Core.GetEnhancementPolicy does it:
-- a colour read happens during a tooltip render, and it must never have the
-- side effect of initialising the database.
function Core.IsShamanBlueEnabled()
    local runtime = database and database.settings or nil
    local own = true
    if type(runtime) == "table" and type(runtime.shamanBlue) == "boolean" then
        own = runtime.shamanBlue
    end
    if not own then
        return false
    end
    local config = rawget(_G, "TacoTipConfig")
    if type(config) == "table" and config.shaman_blue == false then
        return false
    end
    return true
end

-- The class-colour override for a class token, or nil when the rule does not
-- apply.
--
-- The OVERRIDE half of the class colour, for the Shaman only. The whole chain
-- is Core.GetClassColor below; this is the one rule in it that is not about
-- where a colour comes from.
--
-- Returns r, g, b or nil. A nil return means "carry on with the chain".
function Core.GetClassColorOverride(classToken)
    if classToken ~= "SHAMAN" then
        return nil
    end
    if not Core.IsShamanBlueEnabled() then
        return nil
    end
    return SHAMAN_BLUE_COLOR.r, SHAMAN_BLUE_COLOR.g, SHAMAN_BLUE_COLOR.b
end

-- The class-colour chain, in ONE place.
--
-- ONE resolver, three surfaces: the unit tooltip (Tooltips.playerClassColor),
-- the character/inspect summary frame (Frames.classColor) and the leaderboard
-- row (RankBrowser.getClassColor). They must not be able to disagree -- a
-- player whose tooltip says blue and whose leaderboard row says pink is a
-- bug report waiting to happen.
--
-- Each surface ran its OWN copy of the chain, and the copies had already
-- drifted:
--
--   Tooltips.lua / Frames.lua  accepted a community colour only when it was
--       three finite numbers in 0..1, and fell back to neutral grey.
--   RankBrowser.lua            accepted a community colour whenever r, g and b
--       were three numbers of ANY value, and fell back to its own hardcoded
--       13-entry class table before the neutral default.
--
-- So a class the CLIENT does not know (a class the client's own colour
-- tables do not carry) read gold in the leaderboard and grey in the tooltip.
--
-- This function owns the chain -- WHERE a colour comes from -- so the
-- surfaces cannot disagree about that any more. It deliberately does NOT own
-- the two rules on which the surfaces still differ, because the visible
-- output must not change:
--
--   * how a candidate colour is judged  -> options.accept
--   * what to do when nothing is found   -> the caller's OWN fallback
--
-- The leaderboard passes a permissive numeric accept and keeps its hardcoded
-- table; the tooltip and the frame pass the 0..1 range accept and keep
-- neutral grey. This is a refactor, not a behaviour change.
--
-- options.accept(r, g, b) -> boolean decides whether a candidate colour is
-- usable. It defaults to the PERMISSIVE rule (any three numbers), which is
-- the leaderboard's own, so a caller that passes no options cannot
-- accidentally tighten it.
--
-- Returns r, g, b on success, or nil when the chain found nothing usable.
function Core.GetClassColor(classToken, options)
    if type(classToken) ~= "string" or classToken == "" then
        return nil
    end
    options = type(options) == "table" and options or nil
    local accept = options and options.accept or nil

    local function usable(red, green, blue)
        if type(accept) == "function" then
            return accept(red, green, blue) == true
        end
        return type(red) == "number"
            and type(green) == "number"
            and type(blue) == "number"
    end

    -- 1. The Shaman-blue override. It comes FIRST, before the client's own
    --    colour tables, so a Shaman reads blue on Classic Era (whose client
    --    colour is pink).
    local overrideRed, overrideGreen, overrideBlue =
        Core.GetClassColorOverride(classToken)
    if usable(overrideRed, overrideGreen, overrideBlue) then
        return overrideRed, overrideGreen, overrideBlue
    end

    -- 2. CUSTOM_CLASS_COLORS. A community convention, never a Blizzard API,
    --    so it sits behind a type-guard and is never a dependency -- a
    --    non-table value there must never raise.
    local custom = rawget(_G, "CUSTOM_CLASS_COLORS")
    if type(custom) == "table" then
        local entry = custom[classToken]
        if type(entry) == "table" then
            local red, green, blue = entry.r, entry.g, entry.b
            if usable(red, green, blue) then
                return red, green, blue
            end
        end
    end

    -- 3. RAID_CLASS_COLORS. The client's own table.
    local raid = rawget(_G, "RAID_CLASS_COLORS")
    if type(raid) == "table" then
        local entry = raid[classToken]
        if type(entry) == "table" then
            local red, green, blue = entry.r, entry.g, entry.b
            if usable(red, green, blue) then
                return red, green, blue
            end
        end
    end

    -- Nothing found. The caller applies its OWN fallback: neutral grey for the
    -- tooltip and the frame, the leaderboard's own table for the row.
    return nil
end

function Core.ApplySettings()
    local runtime = normalizeSettings(Core.GetSettings())
    if namespace.Tooltips and type(namespace.Tooltips.ApplySettings) == "function" then
        namespace.Tooltips.ApplySettings()
    end
    if namespace.Minimap and type(namespace.Minimap.ApplySettings) == "function" then
        namespace.Minimap.ApplySettings()
    end
    if namespace.Frames and type(namespace.Frames.ApplySettings) == "function" then
        namespace.Frames.ApplySettings()
    end
    if namespace.Options and type(namespace.Options.Refresh) == "function" then
        namespace.Options.Refresh()
    end
    return runtime
end

function Core.ApplyEquipmentSettings()
    local runtime = normalizeSettings(Core.GetSettings())
    if namespace.Frames and type(namespace.Frames.ApplySettings) == "function" then
        namespace.Frames.ApplySettings()
    end
    if namespace.Options and type(namespace.Options.Refresh) == "function" then
        namespace.Options.Refresh()
    end
    return runtime.equipmentDisplay
end

function Core.ResetSettings()
    local runtime = Core.GetSettings()
    for key in pairs(runtime) do
        runtime[key] = nil
    end
    setEquipmentDisplayDefaults(runtime)
    normalizeSettings(runtime)
    if namespace.Frames and type(namespace.Frames.ResetPositions) == "function" then
        namespace.Frames.ResetPositions()
    end
    Core.ApplySettings()
    return runtime
end

function Core.ResetEquipmentPositions()
    local runtime = Core.GetSettings()
    local equipmentDisplay = type(runtime) == "table"
        and runtime.equipmentDisplay
        or nil
    if type(equipmentDisplay) ~= "table" then
        return false
    end
    equipmentDisplay.characterPosition = nil
    equipmentDisplay.inspectPosition = nil
    if namespace.Frames and type(namespace.Frames.ResetPositions) == "function" then
        namespace.Frames.ResetPositions()
    end
    Core.ApplyEquipmentSettings()
    return true
end

function Core.RestoreTacoTipSettings()
    local runtime = Core.GetSettings()
    runtime.tooltip.mode = "Disabled"
    if namespace.Tooltips and type(namespace.Tooltips.ApplySettings) == "function" then
        namespace.Tooltips.ApplySettings()
    elseif namespace.TacoTipAdapter
        and type(namespace.TacoTipAdapter.SetTooltipSurfaceEnabled) == "function" then
        namespace.TacoTipAdapter.SetTooltipSurfaceEnabled(false)
    end
    if namespace.Options and type(namespace.Options.Refresh) == "function" then
        namespace.Options.Refresh()
    end
    return namespace.TacoTipAdapter
        and type(namespace.TacoTipAdapter.IsTooltipSurfaceActive) == "function"
        and not namespace.TacoTipAdapter.IsTooltipSurfaceActive()
end

-- The library's INVENTORY_READY consumer.
--
-- This is the add-on's boundary with the shared inspect engine, and the engine
-- releases its pending inspect slot only AFTER the consumer callbacks have
-- run. So a raise here escapes into the library's dispatch, the release is
-- skipped, and the engine stops issuing inspects: no unit scores again until
-- the client is reloaded. One add-on's error must not cost every add-on's
-- tooltip.
--
-- So the call is guarded. The failure is COUNTED with its message kept, one
-- chat line goes out so it is never silent, and the counter is printed by
-- /ex debug (see printDebugSnapshot).
local consumerErrors = 0
local lastConsumerError = nil
local announcedConsumerErrors = {}

local function recordConsumerError(err)
    consumerErrors = consumerErrors + 1
    lastConsumerError = tostring(err)
    local message = tostring(err)
    if not announcedConsumerErrors[message] then
        announcedConsumerErrors[message] = true
        if type(_G.DEFAULT_CHAT_FRAME) == "table"
            and type(_G.DEFAULT_CHAT_FRAME.AddMessage) == "function" then
            pcall(_G.DEFAULT_CHAT_FRAME.AddMessage, _G.DEFAULT_CHAT_FRAME,
                "|cffff5555TacoTip Extras:|r the scan callback failed: " .. message
                .. " (the inspect engine keeps running; the count is in /ex debug)")
        end
    end
end

local function onInventoryReady(event, guid, isInspect, unit)
    if namespace.Scanner
        and type(namespace.Scanner.HandleInventoryReady) == "function" then
        local ok, result = pcall(
            namespace.Scanner.HandleInventoryReady,
            event,
            guid,
            isInspect,
            unit
        )
        if not ok then
            recordConsumerError(result)
            return false
        end
        return result
    end
end

local function addChatLine(message)
    if DEFAULT_CHAT_FRAME and type(DEFAULT_CHAT_FRAME.AddMessage) == "function" then
        DEFAULT_CHAT_FRAME:AddMessage(DEBUG_PREFIX .. " " .. message)
    end
end

local function cellValue(cell)
    if type(cell) == "table" and cell.status == "complete" then
        return cell.value, true
    end
    return nil, false
end

local function formatNumber(value)
    if type(value) ~= "number" then
        return "unknown"
    end
    if value % 1 == 0 then
        return string.format("%d", value)
    end
    return string.format("%.2f", value)
end

local function metricText(label, metric)
    local status = type(metric) == "table" and metric.status or "unknown"
    if status == "complete" and type(metric.value) == "number" then
        return label .. "=complete:" .. formatNumber(metric.value)
    end
    return label .. "=" .. tostring(status)
end

local function rawSlot(revision, slotID)
    if type(revision) == "table" and type(revision.slots) == "table" then
        return revision.slots[slotID]
    end
    return nil
end

local function rawState(slot)
    if type(slot) == "table" and slot.state == "occupied" then
        return "occupied"
    end
    if type(slot) == "table" and slot.state == "confirmed-empty" then
        return "confirmed-empty"
    end
    return "unknown/pending"
end

local function countRawStates(revision)
    local occupied = 0
    local empty = 0
    local unknown = 0
    for _, slotID in ipairs(REQUIRED_SLOTS) do
        local state = rawState(rawSlot(revision, slotID))
        if state == "occupied" then
            occupied = occupied + 1
        elseif state == "confirmed-empty" then
            empty = empty + 1
        else
            unknown = unknown + 1
        end
    end
    return occupied, empty, unknown
end

local function permanentState(slot)
    local enchantID, known = cellValue(slot and slot.permanentEnchantID)
    if not known or type(enchantID) ~= "number" then
        return "unknown"
    end
    return enchantID > 0 and "present" or "absent"
end

local function installedGemCount(slot)
    local gemIDs, known = cellValue(slot and slot.scoreGemIDs)
    if not known or type(gemIDs) ~= "table" then
        return "unknown"
    end

    local count = 0
    for index = 1, 3 do
        if type(gemIDs[index]) == "number" and gemIDs[index] > 0 then
            count = count + 1
        end
    end
    return tostring(count)
end

local function socketCapacity(slot)
    local sockets, known = cellValue(slot and slot.sockets)
    if known and type(sockets) == "table" and type(sockets.capacity) == "number" then
        return formatNumber(sockets.capacity)
    end
    return "unknown"
end

local function temporaryState(slot)
    local active, known = cellValue(slot and slot.temporaryWeaponEffect)
    if known and type(active) == "boolean" then
        return tostring(active)
    end
    return "unknown"
end

local function weaponText(label, slot)
    local state = rawState(slot)
    if state == "confirmed-empty" then
        return label .. " item=confirmed-empty enchant=absent gems=0 sockets=0 temporary=false"
    end
    if state ~= "occupied" then
        return label .. " item=unknown enchant=unknown gems=unknown sockets=unknown temporary=unknown"
    end

    local itemID, itemKnown = cellValue(slot.itemID)
    return label
        .. " item=" .. (itemKnown and formatNumber(itemID) or "unknown")
        .. " enchant=" .. permanentState(slot)
        .. " gems=" .. installedGemCount(slot)
        .. " sockets=" .. socketCapacity(slot)
        .. " temporary=" .. temporaryState(slot)
end

local function slotText(slotID, slot)
    local state = rawState(slot)
    local line = "slot=" .. slotID .. " state=" .. state
    if state ~= "occupied" then
        return line
    end

    local itemID, itemKnown = cellValue(slot.itemID)
    local equipLoc, equipKnown = cellValue(slot.equipLoc)
    local scoringLevel, scoringKnown = cellValue(slot.scoringItemLevel)
    local effectiveLevel, effectiveKnown = cellValue(slot.effectiveItemLevel)
    return line
        .. " item=" .. (itemKnown and formatNumber(itemID) or "unknown")
        .. " equip=" .. (equipKnown and tostring(equipLoc) or "unknown")
        .. " score-ilvl=" .. (scoringKnown and formatNumber(scoringLevel) or "unknown")
        .. " avg-ilvl=" .. (effectiveKnown and formatNumber(effectiveLevel) or "unknown")
        .. " enchant=" .. permanentState(slot)
        .. " gems=" .. installedGemCount(slot)
        .. " sockets=" .. socketCapacity(slot)
end

local function completionText(metric)
    local status = type(metric) == "table" and metric.status or "unknown"
    local value = status == "complete" and metric.value or nil
    if type(value) ~= "table" then
        return "completion=" .. tostring(status)
            .. " filled=unknown total=unknown percent=unknown category=unknown"
    end

    local percent = type(value.displayPercent) == "number"
        and formatNumber(value.displayPercent) or "n/a"
    return "completion=complete"
        .. " filled=" .. formatNumber(value.filled)
        .. " total=" .. formatNumber(value.opportunities)
        .. " percent=" .. percent
        .. " category=" .. tostring(value.category or "unknown")
end

local function averageText(metric)
    local status = type(metric) == "table" and metric.status or "unknown"
    local value = status == "complete" and metric.value or nil
    if type(value) ~= "table" then
        return "Average iLvl=" .. tostring(status) .. " raw=unknown display=unknown"
    end
    local raw = type(value.raw) == "number" and string.format("%.4f", value.raw)
        or "unknown"
    return "Average iLvl=complete raw=" .. raw
        .. " display=" .. formatNumber(value.display)
end

local function printDebugSnapshot()
    local scanner = namespace.Scanner
    local state = scanner and scanner.GetCurrent and scanner.GetCurrent() or nil
    state = type(state) == "table" and state or { status = "unavailable", generation = 0 }

    local revision = state.revision
    local result = type(state.result) == "table" and state.result or nil
    local metrics = result and result.metrics or {}
    local occupied, empty, unknown = countRawStates(revision)
    local pendingCount = type(state.pendingItemCount) == "number"
        and state.pendingItemCount or 0

    addChatLine("/ex debug local snapshot")
    -- The family split the PvP wire rule depends on. It is printed because it
    -- is otherwise invisible: `Core.UsesModernPvPSurface` decides from the
    -- library's project identity, and a client whose identity cannot be read
    -- falls back to the rated-BG capability probe. "unknown" therefore means
    -- "the fallback decided", not "no data".
    do
        local classicFamily = Core.IsClassicFamilyClient()
        local familyText = classicFamily == nil and "unknown"
            or (classicFamily and "classic" or "mainline")
        addChatLine(
            "client-family=" .. familyText
            .. " pvp-surface=" .. (Core.UsesModernPvPSurface() and "modern" or "classic")
        )
    end
    addChatLine(
        "state=" .. tostring(state.status or "unknown")
        .. " generation=" .. tostring(state.generation or 0)
        .. " reason=" .. tostring(state.reason or "none")
        .. " occupied=" .. occupied
        .. " confirmed-empty=" .. empty
        .. " unknown/pending=" .. unknown
        .. " pending-item-ids=" .. pendingCount
    )
    addChatLine(
        metricText("Unenhanced GS", metrics.baseGS) .. " "
        .. metricText("Current GS", metrics.gearScore) .. " "
        .. metricText("Potential GS", metrics.potentialGS) .. " "
        .. metricText("Delta", metrics.delta)
    )
    addChatLine(completionText(metrics.completion) .. " "
        .. averageText(metrics.averageItemLevel))
    addChatLine(weaponText("main-hand", rawSlot(revision, 16)))
    addChatLine(weaponText("off-hand", rawSlot(revision, 17)))
    local function outcomeCount(counts, name)
        return tostring((counts and counts[name]) or 0)
    end

    for _, slotID in ipairs(REQUIRED_SLOTS) do
        addChatLine(slotText(slotID, rawSlot(revision, slotID)))
    end
    -- RankSync delivery telemetry (rawSend outcome buckets, the channel
    -- probe/dead state machine, queue pressure, counted skips). Every
    -- counter starts live only once it has fired, so absent keys read 0.
    local rankSync = namespace.RankSync
    local syncState = nil
    local counts = nil
    if rankSync and type(rankSync.GetDebugState) == "function" then
        syncState = rankSync.GetDebugState()
        counts = syncState.outcomes
        addChatLine("/ex debug rank sync")
        addChatLine("channel=" .. tostring(syncState.channelState)
            .. "(" .. tostring(syncState.channelId) .. ")"
            .. " channel-failures=" .. tostring(syncState.channelFailures)
            .. " token-bucket=" .. tostring(syncState.tokenBucket)
            .. " queue=" .. tostring(syncState.queueDepth)
            .. " self-broadcast-pending=" .. tostring(syncState.selfBroadcastPending))
        addChatLine("sends success=" .. outcomeCount(counts, "sendSuccess")
            .. " no-info=" .. outcomeCount(counts, "sendNoInfo")
            .. " addon-throttle=" .. outcomeCount(counts, "sendThrottle")
            .. " channel-throttle=" .. outcomeCount(counts, "sendChannelThrottle")
            .. " invalid-channel=" .. outcomeCount(counts, "sendInvalidChannel")
            .. " other=" .. outcomeCount(counts, "sendOther")
            .. " error=" .. outcomeCount(counts, "sendError")
            .. " requeued=" .. outcomeCount(counts, "requeued")
            .. " oversize-dropped=" .. outcomeCount(counts, "enqueueOversize")
            .. " probes=" .. outcomeCount(counts, "probes")
            .. " self-rebroadcast=" .. outcomeCount(counts, "selfRebroadcast"))
        addChatLine("skipped no-transport=" .. outcomeCount(counts, "answerNoTransport")
            .. " version-rejected=" .. outcomeCount(counts, "versionReject")
            .. " foreign-realm=" .. outcomeCount(counts, "scanForeignRealm")
            .. " inbound-rate-limited=" .. outcomeCount(counts, "inboundRateLimited"))
    end

    -- The surfaces block (final hunter H-3).
    --
    -- EVERY diagnostic counter in this add-on used to be reachable only from
    -- the test harness. The code comments even said "surfaced in GetDebugState
    -- below" -- and GetDebugState was read by nothing outside the harness. A
    -- counter no user can see is a counter that cannot be acted on: the
    -- render-latch wedge, a swallowed rank-record raise, a row-tooltip
    -- truncation, a score-colour fallback, a module that never started and a
    -- peer record that was refused were ALL invisible.
    --
    -- Printed, not merely exposed, so the surface cannot rot again: the
    -- harness asserts on the TEXT of these lines, not on an accessor.
    local tooltips = namespace.Tooltips
    local driver = (tooltips and type(tooltips.GetDriverState) == "function")
        and tooltips.GetDriverState() or nil
    local tooltipDebug = (tooltips and type(tooltips.GetDebugState) == "function")
        and tooltips.GetDebugState() or nil
    local browser = namespace.RankBrowser
    local browserDebug = (browser and type(browser.GetDebugState) == "function")
        and browser.GetDebugState() or nil
    local cache = namespace.Cache
    local cacheDebug = (cache and type(cache.GetDebugState) == "function")
        and cache.GetDebugState() or nil
    local scannerDebug = (scanner and type(scanner.GetDebugState) == "function")
        and scanner.GetDebugState() or nil
    local frames = namespace.Frames
    local framesDebug = (frames and type(frames.GetDebugState) == "function")
        and frames.GetDebugState() or nil
    local options = namespace.Options
    local optionsDebug = (options and type(options.GetDebugState) == "function")
        and options.GetDebugState() or nil

    addChatLine("/ex debug surfaces")
    addChatLine("driver mode=" .. tostring(driver and driver.mode)
        .. " renders=" .. tostring(driver and driver.renders)
        .. " rows=" .. tostring(driver and driver.rows)
        .. " poll-ticks=" .. tostring(driver and driver.pollTicks)
        .. " poll-work-ticks=" .. tostring(driver and driver.pollWorkTicks))
    addChatLine("render-errors=" .. tostring(driver and driver.renderErrors)
        .. " render-errors-suppressed=" .. tostring(driver and driver.renderErrorsSuppressed)
        .. " last-render-error=" .. tostring(driver and driver.lastRenderError))
    addChatLine("rank-record-errors=" .. tostring(tooltipDebug and tooltipDebug.rankRecordErrors)
        .. " last-rank-record-error=" .. tostring(tooltipDebug and tooltipDebug.lastRankRecordError))
    addChatLine("row-tooltip-errors=" .. tostring(browserDebug and browserDebug.rowTooltipErrors)
        .. " last-row-tooltip-error=" .. tostring(browserDebug and browserDebug.lastRowTooltipError))
    addChatLine("score-colour-fallbacks=" .. tostring(tooltipDebug and tooltipDebug.scoreColorFallbacks)
        .. " last-score-colour-reason=" .. tostring(tooltipDebug and tooltipDebug.lastScoreColorReason))
    addChatLine("cache-listener-errors=" .. tostring(cacheDebug and cacheDebug.listenerErrors)
        .. " last-cache-listener-error=" .. tostring(cacheDebug and cacheDebug.lastListenerError))
    addChatLine("scanner-listener-errors=" .. tostring(scannerDebug and scannerDebug.listenerErrors)
        .. " last-scanner-listener-error=" .. tostring(scannerDebug and scannerDebug.lastListenerError))
    addChatLine("scanner-capture-errors=" .. tostring(scannerDebug and scannerDebug.captureErrors)
        .. " last-scanner-capture-error=" .. tostring(scannerDebug and scannerDebug.lastCaptureError))
    -- The library-callback ledger (the guarded INVENTORY_READY consumer) and
    -- the ENGINE's own ledger for the same boundary.
    --
    -- The engine's counter is the one that matters for "the tooltip stopped
    -- showing scores": a raise inside the inspect-ready handler used to leave
    -- the library's pending inspect slot set, and the queue then issued no
    -- further inspect at all until the client was reloaded.
    addChatLine("inventory-ready-errors=" .. tostring(Core.GetConsumerErrors())
        .. " last-inventory-ready-error=" .. tostring(Core.GetLastConsumerError()))
    local engineStats = nil
    local inspector = namespace.TacoTipAdapter
        and type(namespace.TacoTipAdapter.GetInspector) == "function"
        and namespace.TacoTipAdapter.GetInspector() or nil
    if inspector and type(inspector.GetInspectStats) == "function" then
        local ok, stats = pcall(inspector.GetInspectStats, inspector)
        if ok and type(stats) == "table" then
            engineStats = stats
        end
    end
    addChatLine("inspect-ready-errors=" .. tostring(engineStats and engineStats.inspectReadyErrors)
        .. " last-inspect-ready-error=" .. tostring(engineStats and engineStats.lastInspectReadyError))
    addChatLine("scanner-reevaluate-errors=" .. tostring(scannerDebug and scannerDebug.reevaluateErrors)
        .. " last-scanner-reevaluate-error=" .. tostring(scannerDebug and scannerDebug.lastReevaluateError))
    addChatLine("records-rejected=" .. outcomeCount(counts, "recordRejected")
        .. " last-record-rejected-reason="
        .. tostring(syncState and syncState.lastRecordRejectedReason))
    addChatLine("queue-evicted=" .. outcomeCount(counts, "queueEvicted")
        .. " last-evicted-kind=" .. tostring(syncState and syncState.lastEvictedKind))
    local initializeFailures = Core.GetInitializeFailures()
    local initializeDetails = Core.GetInitializeFailureDetails()
    addChatLine("initialize-failures=" .. tostring(#initializeFailures)
        .. " [" .. table.concat(initializeDetails, " | ") .. "]")
    -- The bounded-callback boundary (final hardening pass). Every callback
    -- this add-on registers on a Blizzard frame or on a Blizzard function is
    -- wrapped, so a raise inside one cannot unwind through the client's own
    -- frame script. These counters are what the player (or the operator) sees
    -- when a surface stops working.
    addChatLine("frame-hook-errors=" .. tostring(framesDebug and framesDebug.hookCallbackErrors)
        .. " last-frame-hook-error=" .. tostring(framesDebug and framesDebug.lastHookCallbackError))
    -- The hooks this add-on did NOT install, and the ones that refused to
    -- install. A hook that is skipped is silent by nature -- the frame simply
    -- does not refresh -- so the count and the reason have to be visible
    -- here, or the surface is "working" and doing nothing.
    addChatLine("frame-hooks-skipped=" .. tostring(framesDebug and framesDebug.hookSkipped)
        .. " frame-hooks-failed=" .. tostring(framesDebug and framesDebug.hookFailed)
        .. " last-frame-hook-failure=" .. tostring(framesDebug and framesDebug.lastHookFailure))
    addChatLine("options-action-failures=" .. tostring(optionsDebug and optionsDebug.actionFailures)
        .. " last-options-action-failure=" .. tostring(optionsDebug and optionsDebug.lastActionFailure))
end

-- The debug snapshot, published on a plain global.
--
-- Slash commands have ONE home now: Options.lua's registerSlashCommand owns
-- /ex, /extras and /tte, and the `debug` argument runs this publisher. This
-- file used to declare SLASH_TTEXTRASDEBUG1 = "/ttgsdebug" as well -- that
-- went with the /tt prefix, so there is no second registration to drift.
--
-- WHY a plain global is still needed: the main add-on CANNOT read a handler
-- back out of SlashCmdList. The client's SlashCmdList is a PROXY table --
-- ChatFrameSetup.lua:3-11 proxies it, ChatFrameUtil.lua's ImportListToHash
-- moves every handler into getmetatable(list).__index and then WIPES the real
-- table (:732/:735 on the Classic branches, :809/:812 on forever/live) --
-- which happens immediately BEFORE the handler is dispatched
-- (ChatFrameEditBox.lua:245, 257, 259). So a rawget at dispatch time is ALWAYS
-- nil on all five clients. TacoTip calls this global directly instead.
--
-- The global is published ONCE, and only when it is not already a function; a
-- second load of this file therefore cannot repoint it at a new closure.
local function publishDebugSnapshot()
    if type(rawget(_G, "TacoTipExtrasPrintDebugSnapshot")) ~= "function" then
        rawset(_G, "TacoTipExtrasPrintDebugSnapshot", printDebugSnapshot)
    end
end

local function runScheduledScan(self)
    self:SetScript("OnUpdate", nil)

    local generation = scheduledGeneration
    scheduledGeneration = nil
    if generation and namespace.Scanner then
        namespace.Scanner.RunGeneration(generation)
    end
end

local function scheduleLocalScan(reason)
    local scanner = namespace.Scanner
    if scheduledGeneration
        or type(scanner) ~= "table"
        or type(scanner.BeginGeneration) ~= "function"
        or type(scanner.RunGeneration) ~= "function" then
        return false
    end

    scheduledGeneration = scanner.BeginGeneration(reason)
    if not scheduledGeneration then
        return false
    end
    eventFrame:SetScript("OnUpdate", runScheduledScan)
    return true
end

function Core.RequestLocalScan(reason)
    if type(reason) ~= "string" or reason == "" then
        reason = "equipment-window"
    end
    return scheduleLocalScan(reason)
end

function Core.ScheduleEquipmentExpiry(delay, callback)
    return scheduleOneShot(delay, callback)
end

-- One raise must not cost the user every feature after it.
--
-- This function used to call its sub-initializers bare. Options.attachHelp
-- hooked OnEnter/OnLeave on a plain Frame, which raises "bad argument #2 to
-- 'HookScript'" on EVERY supported client, and that raise propagated out of the
-- ADDON_LOADED handler: the minimap button, the welcome line and every later
-- step were silently skipped and the user was left with an add-on that appeared
-- to half work and reported nothing.
--
-- guarded() turns any single failure into a recorded one. The add-on then loads
-- with that ONE surface off, prints the reason once, and every other surface
-- still comes up -- which is the difference between a broken add-on and a
-- degraded one.
local initializeFailures = {}
local initializeFailureDetails = {}

-- Record one initialization failure: the label is kept for the existing
-- Core.GetInitializeFailures() contract, the DETAIL (the reason) is kept
-- beside it, and ONE chat line goes out so the failure is never silent.
local function recordInitializeFailure(label, reason)
    initializeFailures[#initializeFailures + 1] = label
    initializeFailureDetails[#initializeFailureDetails + 1] =
        tostring(label) .. ": " .. tostring(reason)
    if type(_G.DEFAULT_CHAT_FRAME) == "table"
        and type(_G.DEFAULT_CHAT_FRAME.AddMessage) == "function" then
        pcall(_G.DEFAULT_CHAT_FRAME.AddMessage, _G.DEFAULT_CHAT_FRAME,
            "|cffff5555TacoTip Extras:|r " .. label .. " failed to start: "
            .. tostring(reason))
    end
end

-- guarded() turns any single failure into a recorded one. The add-on then loads
-- with that ONE surface off, prints the reason once, and every other surface
-- still comes up -- which is the difference between a broken add-on and a
-- degraded one.
--
-- It returns TWO values: whether the initializer succeeded, and whether it
-- already RECORDED a failure. The second value is what lets the caller tell
-- "raised" (recorded here) from "returned false" (not a raise, so not
-- visible to a pcall -- the M-7 case, where an incompatible TacoTip is
-- refused on purpose and the user is told nothing at all).
local function guarded(label, fn, ...)
    if type(fn) ~= "function" then
        -- L-6: a module that is missing, or present but not callable, is an
        -- initialization failure like any other. It used to return false
        -- silently, so a whole surface could be absent with nothing on
        -- record and nothing said.
        recordInitializeFailure(label, "module not available")
        return false, true
    end
    local results = { pcall(fn, ...) }
    local ok = results[1]
    if ok then
        return results[2] ~= false, false
    end
    recordInitializeFailure(label, tostring(results[2]))
    return false, true
end

function Core.GetInitializeFailures()
    return initializeFailures
end

-- The same list with the reason attached, for /ex debug.
function Core.GetInitializeFailureDetails()
    return initializeFailureDetails
end

-- The library-callback failure ledger (the guarded consumer above).
--
-- Read by /ex debug. The count is the only trace of a raise that was
-- PREVENTED rather than fixed, so it has to exist and it has to be printed.
function Core.GetConsumerErrors()
    return consumerErrors
end

function Core.GetLastConsumerError()
    return lastConsumerError
end

-- The adapter's own reason for refusing the surface. Named in the chat line
-- so an incompatible TacoTip produces OUTPUT (M-7) instead of silence.
local function adapterInternalReason(adapter)
    if not adapter or type(adapter.GetInternalReason) ~= "function" then
        return "incompatible TacoTip"
    end
    local ok, reason = pcall(adapter.GetInternalReason)
    if ok and type(reason) == "string" and reason ~= "" then
        return reason
    end
    return "incompatible TacoTip"
end

local function initialize(self)
    if initialized or not namespace.Scanner then
        return
    end

    initialized = true
    local root = initializeDatabase()
    local adapter = namespace.TacoTipAdapter
    local adapterReady = false
    if adapter and type(adapter.Initialize) == "function" then
        local adapterOK, adapterRecorded = guarded("TacoTipAdapter", adapter.Initialize, root)
        adapterReady = adapterOK == true
        if not adapterReady and not adapterRecorded then
            -- M-7: an incompatible TacoTip is a RETURN VALUE, not a raise, so
            -- guarded() cannot see it. The surface is refused on purpose --
            -- that is the fail-closed contract, and it is not a bug -- but a
            -- refused surface with no output at all is indistinguishable
            -- from a broken add-on. Record it, and say why, once.
            recordInitializeFailure("TacoTipAdapter", adapterInternalReason(adapter))
        end
    end

    local library
    if adapter and type(adapter.GetInspector) == "function" then
        library = adapter.GetInspector()
    end
    guarded("Scanner", namespace.Scanner.Initialize, library)
    local callbackReady = false
    if adapter and type(adapter.RegisterInventoryReady) == "function" then
        callbackReady = guarded(
            "InspectorCallback",
            adapter.RegisterInventoryReady,
            onInventoryReady
        ) == true
    end
    guarded("DebugSnapshot", publishDebugSnapshot)
    guarded("EventRegistration", function()
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
        self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        self:RegisterEvent("UNIT_INVENTORY_CHANGED")
        self:RegisterEvent("ITEM_DATA_LOAD_RESULT")
        self:RegisterEvent("MODIFIER_STATE_CHANGED")
        self:RegisterEvent("PLAYER_LOGOUT")
        -- SAVED_VARIABLES_TOO_LARGE carries the failing add-on's name as its
        -- payload (AddOnsDocumentation.lua:389 classic / :412 live), and the
        -- response prune is registered separately: a client build that
        -- refuses this event must lose only this registration, not the
        -- whole block the guarded pcall above protects.
        pcall(function()
            self:RegisterEvent("SAVED_VARIABLES_TOO_LARGE")
        end)
    end)
    local tooltipsReady = guarded(
        "Tooltips",
        namespace.Tooltips and namespace.Tooltips.Initialize,
        root.settings
    )
    guarded("Frames", namespace.Frames and namespace.Frames.Initialize, root.settings)
    local optionsReady = guarded(
        "Options",
        namespace.Options and namespace.Options.Initialize,
        root.settings
    )
    local minimapReady = guarded(
        "Minimap",
        namespace.Minimap and namespace.Minimap.Initialize,
        root.settings
    )
    scheduleWelcome(
        root.settings,
        adapterReady and callbackReady
        and tooltipsReady and optionsReady and minimapReady
    )
end

local function onEvent(self, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == addonName then
            self:UnregisterEvent("ADDON_LOADED")
            initialize(self)
        end
        return
    end

    if event == "SAVED_VARIABLES_TOO_LARGE" then
        -- The payload is the add-on whose write failed (addOnName,
        -- non-nilable; AddOnsDocumentation.lua:389 classic / :412 live).
        -- Whatever needs to stop being too large has to stop before the NEXT
        -- logout, so the race with further gear updates is accepted: age
        -- under 7 days wins, nothing past half the normal capacity survives,
        -- and realm tables emptied by that shake-up are deleted.
        local tooLargeAddon = ...
        if tooLargeAddon == addonName and namespace.RankDB
            and type(namespace.RankDB.PruneAggressive) == "function" then
            pcall(namespace.RankDB.PruneAggressive)
        end
        return
    end

    if event == "PLAYER_LOGOUT" then
        if namespace.Tooltips and type(namespace.Tooltips.Shutdown) == "function" then
            namespace.Tooltips.Shutdown()
        end
        if namespace.Frames and type(namespace.Frames.Shutdown) == "function" then
            namespace.Frames.Shutdown()
        end
        if namespace.TacoTipAdapter
            and type(namespace.TacoTipAdapter.Shutdown) == "function" then
            namespace.TacoTipAdapter.Shutdown()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- The login prune rides the same event; it must never block the scan
        -- (and vice versa), so both are deferred independently.
        scheduleLoginPrune()
        scheduleLocalScan("entering-world")
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        scheduleLocalScan("equipment-changed")
    elseif event == "UNIT_INVENTORY_CHANGED" then
        local unit = ...
        if unit == "player" then
            scheduleLocalScan("inventory-changed")
        end
    elseif event == "ITEM_DATA_LOAD_RESULT" and namespace.Scanner then
        namespace.Scanner.HandleItemDataLoad(...)
    elseif event == "MODIFIER_STATE_CHANGED"
        and namespace.Tooltips
        and type(namespace.Tooltips.HandleModifierStateChanged) == "function" then
        namespace.Tooltips.HandleModifierStateChanged(...)
    end
end

eventFrame:SetScript("OnEvent", onEvent)
eventFrame:RegisterEvent("ADDON_LOADED")
