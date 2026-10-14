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

local MODE_CHOICES = {
    { value = "Disabled", text = "Disabled" },
    { value = "Minimal",  text = "Minimal" },
    { value = "Compact",  text = "Compact" },
    { value = "Detailed", text = "Detailed" },
}

local EQUIPMENT_MODE_CHOICES = {
    { value = "Disabled", text = "Disabled" },
    { value = "Basic",    text = "Basic" },
    { value = "Detailed", text = "Detailed" },
}

local FIELD_KEYS = {
    "gearScore",
    "baseGS",
    "potentialGS",
    "delta",
    "averageItemLevel",
    "completion",
}

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
    ["socket-order-unverified-above-three"] = "installed socket ordering is unverified",
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

local settings
local panel
local category
local equipmentPanel
local initialized = false
local registrationMode = "none"
local slashHandler
local controls = {}
local equipmentControls = {}
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

local function allTooltipFieldsDisabled()
    local fields = fieldSettings()
    if not fields then
        return true
    end
    for _, key in ipairs(FIELD_KEYS) do
        if fields[key] == true then
            return false
        end
    end
    return true
end

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

local function createCheckbox(id, text, x, y, callback, helpWidth)
    local name = addonName .. "Option" .. id
    local check = CreateFrame(
        "CheckButton",
        name,
        panel,
        "InterfaceOptionsCheckButtonTemplate"
    )
    check:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)

    local label = check:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("LEFT", check, "RIGHT", 2, 1)
    -- The label comes from the locale, keyed by the SAME id the help popup uses.
    -- Label and help heading are the same words, so deriving both from one place
    -- is what stops them drifting apart; `text` stays as the English fallback.
    label:SetText(helpHeading(id) or text)
    check.optionLabel = label
    check:SetScript("OnClick", function(self)
        callback(self:GetChecked() == true)
    end)
    if type(check.SetHitRectInsets) == "function" then
        check:SetHitRectInsets(0, -(helpWidth or 240), 0, 0)
    end
    attachHelp(check, id)
    controls[id] = check
    return check
end

local function createFieldCheckbox(id, text, key, x, y)
    return createCheckbox(id, text, x, y, function(value)
        local fields = fieldSettings()
        if not fields then
            return
        end
        fields[key] = value
        if allTooltipFieldsDisabled() then
            tooltipSettings().mode = "Disabled"
        end
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
            tooltip.mode = value
            if value ~= "Disabled" and allTooltipFieldsDisabled() then
                tooltip.mode = "Disabled"
            end
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
            info.text = choice.text
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
    label:SetPoint("LEFT", check, "RIGHT", 2, 1)
    -- The label comes from the locale, keyed by the SAME id the help popup uses.
    -- Label and help heading are the same words, so deriving both from one place
    -- is what stops them drifting apart; `text` stays as the English fallback.
    label:SetText(helpHeading(id) or text)
    check.optionLabel = label
    check:SetScript("OnClick", function(self)
        callback(self:GetChecked() == true)
    end)
    if type(check.SetHitRectInsets) == "function" then
        check:SetHitRectInsets(0, -500, 0, 0)
    end
    attachHelp(check, id)
    equipmentControls[id] = check
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
            info.text = choice.text
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
    if type(frames) == "table" and type(frames.ResetPositions) == "function" then
        frames.ResetPositions()
    end
    applyEquipmentSettings()
    return true
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
    local safeReason = type(reason) == "string" and ENHANCEMENT_REASONS[reason] or nil
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
    return safeStatus, safeReason, blocker, reasonCode
end

local function refreshStatus()
    local integrationText = controls.integrationStatus
    local remoteText = controls.remoteStatus
    local blockerText = controls.blockerStatus
    if not integrationText or not remoteText or not blockerText then
        return
    end

    local compatible, integration = safeIntegrationStatus()
    local remoteStatus, remoteReason, blocker, reasonCode = safeEnhancementStatus()
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
        if reasonCode then
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
    local core = namespace.Core
    if type(core) ~= "table" or type(core.ResetSettings) ~= "function" then
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
end

local function restoreTacoTipSettings()
    local core = namespace.Core
    if type(core) ~= "table"
        or type(core.RestoreTacoTipSettings) ~= "function" then
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
                applyTooltipSettings()
            end
        end,
        500
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
        end,
        500
    )
    createCheckbox("ShowMinimap", "Show minimap button", 16, -318, function(value)
        local minimap = minimapSettings()
        if minimap then
            minimap.show = value
            applyMinimapSettings()
        end
    end, 500)

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
        end,
        240
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
            if namespace.RankBrowser and type(namespace.RankBrowser.Toggle) == "function" then
                namespace.RankBrowser.Toggle()
            end
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
                browser.StartScan()
            end
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

    local mode = tooltip and tooltip.mode or "Disabled"
    if controls.mode then
        UIDropDownMenu_SetSelectedValue(controls.mode, mode)
        UIDropDownMenu_SetText(controls.mode, mode)
    end
    local equipmentMode = equipmentDisplay and equipmentDisplay.mode or "Disabled"
    if equipmentControls.mode then
        UIDropDownMenu_SetSelectedValue(equipmentControls.mode, equipmentMode)
        UIDropDownMenu_SetText(equipmentControls.mode, equipmentMode)
    end
    refreshStatus()
    return true
end
