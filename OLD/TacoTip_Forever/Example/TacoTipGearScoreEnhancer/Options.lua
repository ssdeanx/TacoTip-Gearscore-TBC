local addonName, namespace = ...

if type(namespace) ~= "table" then
    return
end

local Options = {}
namespace.Options = Options

local CATEGORY_NAME = "TacoTip GS Enhancer"
local EQUIPMENT_CATEGORY_NAME = "Equipment Windows"
local ICON_PATH = "Interface\\AddOns\\TacoTipGearScoreEnhancer\\icons\\GS-icon"
local SUCCESS_RED, SUCCESS_GREEN, SUCCESS_BLUE = 0.45, 0.82, 0.55
local NEUTRAL_RED, NEUTRAL_GREEN, NEUTRAL_BLUE = 0.58, 0.56, 0.64
local WARNING_RED, WARNING_GREEN, WARNING_BLUE = 0.95, 0.72, 0.30
local FOOTER_RED, FOOTER_GREEN, FOOTER_BLUE = 0.55, 0.52, 0.62

local INTRO_TEXT = "A TacoTip companion that adds enhancement-aware GearScore, "
    .. "Average iLvl, and Completion to player tooltips."

local SCORE_EXPLANATION = [[Current GS is the player’s present GearScore in this addon and the headline value shown in Compact mode. Use Current GS when referring to the player’s current GearScore. It includes equipped items plus supported bonuses from installed permanent enchants and gems.

Unenhanced GS is an optional comparison using the same equipment with only those counted installed bonuses removed. It shows how much those enhancements already contribute; it is not the player’s current GearScore.

Potential GS adds only confirmed missing eligible permanent enchants and confirmed empty sockets to Current GS. Delta is the increase from Current GS to Potential GS, while Completion shows the share of confirmed enhancement opportunities already filled.

Potential GS and Completion do not rate best-in-slot gear, recommend specific enhancements, or measure raid readiness. Incomplete remote data is shown as unavailable, never as zero.]]

local HELP = {
    Enabled = {
        heading = "Enable addon",
        lines = {
            "Enables or disables all TacoTip GS Enhancer output. When disabled, the addon releases its player GearScore takeover and safely restores the TacoTip setting it manages.",
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
            "Restores TacoTip GS Enhancer settings to their defaults, including tooltip preferences and minimap visibility and position.",
            "It does not reset TacoTip or delete or modify player data, because no player data is persisted.",
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
    { value = "Minimal", text = "Minimal" },
    { value = "Compact", text = "Compact" },
    { value = "Detailed", text = "Detailed" },
}

local EQUIPMENT_MODE_CHOICES = {
    { value = "Disabled", text = "Disabled" },
    { value = "Basic", text = "Basic" },
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
    [1] = true, [2] = true, [3] = true, [5] = true, [6] = true,
    [7] = true, [8] = true, [9] = true, [10] = true, [11] = true,
    [12] = true, [13] = true, [14] = true, [15] = true,
    [16] = true, [17] = true, [18] = true,
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
local equipmentCategory
local initialized = false
local slashHandler
local controls = {}
local equipmentControls = {}
local activeHelpOwner

local function versionCredit()
    local core = namespace.Core
    if type(core) == "table" and type(core.GetVersion) == "function" then
        local ok, value = pcall(core.GetVersion)
        if ok and type(value) == "string" then
            return "v" .. value .. " - NS"
        end
    end
    return "v? - NS"
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
    tooltip:SetText(help.heading, 1, 1, 1)
    for _, line in ipairs(help.lines) do
        tooltip:AddLine(line, 0.82, 0.82, 0.82, true)
    end
    activeHelpOwner = owner
    tooltip:Show()
end

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
    if type(owner.HookScript) == "function" then
        owner:HookScript("OnEnter", onEnter)
        owner:HookScript("OnLeave", onLeave)
    else
        owner:SetScript("OnEnter", onEnter)
        owner:SetScript("OnLeave", onLeave)
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
    label:SetText(text)
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
    label:SetText("Tooltip mode")
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
    label:SetText(text)
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
    label:SetText("Character & Inspect summary")
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

local function createActionButton(name, text, x, callback, helpKey)
    local button = CreateFrame("Button", name, panel, "UIPanelButtonTemplate")
    button:SetSize(210, 24)
    button:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -350)
    button:SetText(text)
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
    fieldsTitle:SetText("Tooltip fields")
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

    local explanationTitle = panel:CreateFontString(
        nil,
        "ARTWORK",
        "GameFontNormal"
    )
    explanationTitle:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -388)
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
    _G.SLASH_TTGSE1 = "/ttgs"
    _G.SlashCmdList.TTGSE = slashHandler
    return true
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
    local api = _G.Settings
    if type(api) ~= "table"
        or type(api.RegisterCanvasLayoutCategory) ~= "function"
        or type(api.RegisterCanvasLayoutSubcategory) ~= "function"
        or type(api.RegisterAddOnCategory) ~= "function"
        or type(api.OpenToCategory) ~= "function" then
        return false
    end

    local registerOK, registeredCategory = pcall(
        api.RegisterCanvasLayoutCategory,
        panel,
        CATEGORY_NAME
    )
    if not registerOK or type(registeredCategory) ~= "table" then
        return false
    end
    local subcategoryOK, registeredEquipmentCategory = pcall(
        api.RegisterCanvasLayoutSubcategory,
        registeredCategory,
        equipmentPanel,
        EQUIPMENT_CATEGORY_NAME
    )
    if not subcategoryOK or type(registeredEquipmentCategory) ~= "table" then
        return false
    end
    local addOK = pcall(api.RegisterAddOnCategory, registeredCategory)
    local addEquipmentOK = pcall(
        api.RegisterAddOnCategory,
        registeredEquipmentCategory
    )
    if not addOK or not addEquipmentOK then
        return false
    end

    category = registeredCategory
    equipmentCategory = registeredEquipmentCategory
    initialized = true
    registerSlashCommand()
    Options.Refresh()
    return true
end

function Options.Open()
    local api = _G.Settings
    if not initialized
        or type(api) ~= "table"
        or type(api.OpenToCategory) ~= "function"
        or type(category) ~= "table" then
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
