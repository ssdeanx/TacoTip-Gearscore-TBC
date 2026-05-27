
local addOnName = ...
local addOnVersion = (GetAddOnMetadata and GetAddOnMetadata(addOnName, "Version")) or (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addOnName, "Version")) or "0.4.8"
local addOnTitle = (GetAddOnMetadata and GetAddOnMetadata(addOnName, "Title")) or (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addOnName, "Title")) or addOnName
local LoadAddOn = _G.LoadAddOn

local interfaceVersion = select(4, GetBuildInfo()) or 0
local clientBuildMajor = math.floor(interfaceVersion / 10000)
-- load only on the Classic-era client families TacoTip supports (Vanilla/TBC/Wrath)
if (clientBuildMajor < 1 or clientBuildMajor > 3) then
    return
end

assert(LibStub, "TacoTip requires LibStub")
assert(LibStub:GetLibrary("LibClassicInspector", true), "TacoTip requires LibClassicInspector")
assert(LibStub:GetLibrary("LibDetours-1.0", true), "TacoTip requires LibDetours-1.0")
--assert(LibStub:GetLibrary("LibClassicGearScore", true), "TacoTip requires LibClassicGearScore")

local isPawnLoaded = _G.PawnClassicLastUpdatedVersion and _G.PawnClassicLastUpdatedVersion >= 2.0538

local Detours = LibStub("LibDetours-1.0")
local CI = LibStub("LibClassicInspector")

local GearScore = _G.TT_GS
local L = _G.TACOTIP_LOCALE
local TT = _G[addOnName]

if (not TT) then
    TT = {}
    rawset(_G, addOnName, TT)
end

local HORDE_ICON = "|TInterface\\TargetingFrame\\UI-PVP-HORDE:16:16:-2:0:64:64:0:38:0:38|t"
local PVP_FLAG_ICON = "|TInterface\\GossipFrame\\BattleMasterGossipIcon:0|t"

function TT:GetDefaults()
    return {
        color_class = true,
        show_titles = true,
        show_guild_name = true,
        show_guild_rank = false,
        show_talents = true,
        show_gs_player = true,
        show_gs_character = true,
        show_gs_items = false,
        show_gs_items_hs = false,
        show_avg_ilvl = true,
        hide_in_combat = false,
        show_item_level = true,
        tip_style = 2,
        show_target = true,
        show_pawn_player = false,
        show_team = false,
        show_pvp_icon = false,
        guild_rank_alt_style = false,
        show_hp_bar = true,
        show_power_bar = false,
        instant_fade = false,
        anchor_mouse = false,
        anchor_mouse_world = true,
        anchor_mouse_spells = false,
        inspect_gs_offset_x = 0,
        inspect_gs_offset_y = 0,
        inspect_ilvl_offset_x = 0,
        inspect_ilvl_offset_y = 0,
        character_gs_offset_x = 0,
        character_gs_offset_y = 0,
        character_ilvl_offset_x = 0,
        character_ilvl_offset_y = 0,
        unlock_info_position = false,
        show_achievement_points = false
        --conf_version = addOnVersion,
        --custom_pos = nil,
        --custom_anchor = nil,
    }
end

function TT:ApplyConfigDefaults(config)
    if (not config) then
        return
    end
    for k, v in pairs(self:GetDefaults()) do
        if (config[k] == nil) then
            config[k] = v
        end
    end
end

local function updateInstantFadeState(enabled)
    if (TT.frame) then
        if (enabled) then
            TT.frame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
        else
            TT.frame:UnregisterEvent("UPDATE_MOUSEOVER_UNIT")
        end
    end
    if (enabled) then
        Detours:DetourHook(TT, GameTooltip, "FadeOut", function(tooltipFrame)
            tooltipFrame:Hide()
        end)
    else
        Detours:DetourUnhook(TT, GameTooltip, "FadeOut")
    end
end

local function setButtonEnabled(button, enabled)
    if (not button) then
        return
    end
    if (enabled) then
        button:Enable()
    else
        button:Disable()
    end
end

local function resetCfg()
    local hadConfig = TacoTipConfig and true or false
    if (TacoTipDragButton) then
        TacoTipDragButton:_Disable()
    end
    if (TacoTipConfig and TacoTipConfig.instant_fade) then
        updateInstantFadeState(false)
    end
    if (TacoTipPowerBar and TacoTipPowerBar.updateTicker) then
        TacoTipPowerBar.updateTicker:Cancel()
        TacoTipPowerBar.updateTicker = nil
    end
    if (TacoTipPowerBar) then
        TacoTipPowerBar:Hide()
    end
    TacoTipConfig = TT:GetDefaults()
    if (hadConfig) then
        TacoTipConfig.conf_version = addOnVersion
    end
    if (PersonalGearScore and PersonalGearScore.RefreshPosition) then
        PersonalGearScore:RefreshPosition()
    end
    if (PersonalGearScoreText and PersonalGearScoreText.RefreshPosition) then
        PersonalGearScoreText:RefreshPosition()
    end
    if (PersonalAvgItemLvl and PersonalAvgItemLvl.RefreshPosition) then
        PersonalAvgItemLvl:RefreshPosition()
    end
    if (PersonalAvgItemLvlText and PersonalAvgItemLvlText.RefreshPosition) then
        PersonalAvgItemLvlText:RefreshPosition()
    end
    if (InspectGearScore and InspectGearScore.RefreshPosition) then
        InspectGearScore:RefreshPosition()
    end
    if (InspectGearScoreText and InspectGearScoreText.RefreshPosition) then
        InspectGearScoreText:RefreshPosition()
    end
    if (InspectAvgItemLvl and InspectAvgItemLvl.RefreshPosition) then
        InspectAvgItemLvl:RefreshPosition()
    end
    if (InspectAvgItemLvlText and InspectAvgItemLvlText.RefreshPosition) then
        InspectAvgItemLvlText:RefreshPosition()
    end
    if (TT.RefreshCharacterFrame and PaperDollFrame and PaperDollFrame:IsShown()) then
        TT:RefreshCharacterFrame()
    end
    if (TT.RefreshInspectFrame and InspectFrame and InspectFrame:IsShown()) then
        TT:RefreshInspectFrame()
    end
    --SetCVar("showItemLevel", "1")
end

if not TacoTipConfig then
    resetCfg()
else
    TT:ApplyConfigDefaults(TacoTipConfig)
end

local optionsFrame
local openOptionsPanel

local function showTooltipMover()
    if (TacoTip_CustomPosEnable) then
        TacoTip_CustomPosEnable(true)
    else
        print("|cff59f0dcTacoTip:|r Tooltip mover is not ready yet. Try /reload.")
    end
end

local function registerSlashCommands()
    local slashCmdList = rawget(_G, "SlashCmdList")
    if (not slashCmdList) then
        slashCmdList = {}
        rawset(_G, "SlashCmdList", slashCmdList)
    end

    SLASH_TACOTIP1 = "/tacotip"
    SLASH_TACOTIP2 = "/tooltip"
    SLASH_TACOTIP3 = "/tip"
    SLASH_TACOTIP4 = "/tt"
    SLASH_TACOTIP5 = "/gs"
    SLASH_TACOTIP6 = "/gearscore"
    SLASH_TACOTIP7 = "/taco"

    -- The options module owns the final slash handler and intentionally
    -- replaces the early bootstrap command registered by GearScore.
    rawset(slashCmdList, "TACOTIP", function(msg)
        local cmd = strlower((msg or "")):gsub("^%s+", ""):gsub("%s+$", "")

        if (cmd == "custom" or cmd == "unlock" or cmd == "move" or cmd == "mover") then
            showTooltipMover()
        elseif (cmd == "default") then
            if (not TacoTipConfig.custom_pos) then
                print("|cff59f0dcTacoTip:|r "..L["Custom tooltip position disabled."])
            end
            if (TacoTipDragButton) then
                TacoTipDragButton:_Disable()
            end
            TacoTipConfig.custom_pos = nil
            TacoTipConfig.custom_anchor = nil
        elseif (cmd == "reset") then
            resetCfg()
            if (optionsFrame and optionsFrame:IsShown() and optionsFrame.Refresh) then
                optionsFrame:Refresh()
            end
            print("|cff59f0dcTacoTip:|r "..L["Configuration has been reset to default."])
        elseif (cmd == "save") then
            if (TacoTipDragButton and TacoTipDragButton:IsShown()) then
                TacoTipDragButton:_Save()
            end
        elseif (cmd == "help") then
            print("|cff59f0dcTacoTip:|r /tacotip - open TacoTip options")
            print("|cff59f0dcTacoTip:|r /tacotip custom - show the tooltip mover")
            print("|cff59f0dcTacoTip:|r /tacotip reset - reset TacoTip settings")
            print("|cff59f0dcTacoTip:|r "..L["TEXT_HELP_ANCHOR"])
        elseif (strfind(cmd, "anchor")) then
            if (strfind(cmd, "topleft")) then
                TacoTipConfig.custom_anchor = "TOPLEFT"
                print("|cff59f0dcTacoTip:|r "..L["Custom position anchor set"]..": 'TOPLEFT'")
            elseif (strfind(cmd, "topright")) then
                TacoTipConfig.custom_anchor = "TOPRIGHT"
                print("|cff59f0dcTacoTip:|r "..L["Custom position anchor set"]..": 'TOPRIGHT'")
            elseif (strfind(cmd, "bottomleft")) then
                TacoTipConfig.custom_anchor = "BOTTOMLEFT"
                print("|cff59f0dcTacoTip:|r "..L["Custom position anchor set"]..": 'BOTTOMLEFT'")
            elseif (strfind(cmd, "bottomright")) then
                TacoTipConfig.custom_anchor = "BOTTOMRIGHT"
                print("|cff59f0dcTacoTip:|r "..L["Custom position anchor set"]..": 'BOTTOMRIGHT'")
            elseif (strfind(cmd, "center")) then
                TacoTipConfig.custom_anchor = "CENTER"
                print("|cff59f0dcTacoTip:|r "..L["Custom position anchor set"]..": 'CENTER'")
            else
                print("|cff59f0dcTacoTip:|r "..L["TEXT_HELP_ANCHOR"])
            end
        else
            if (openOptionsPanel) then
                openOptionsPanel()
            else
                print("|cff59f0dcTacoTip:|r /tacotip custom - show the tooltip mover")
            end
        end
    end)
end

registerSlashCommands()

-- main frame
optionsFrame = CreateFrame("Frame","TacoTipOptions")
optionsFrame.name = addOnTitle
local addOnOptionsCategory
local legacyCategoryRegistered = false
local settingsCategoryRegistered = false

local function ensureSettingsUI()
    if (_G.Settings and _G.Settings.RegisterCanvasLayoutCategory and _G.Settings.RegisterAddOnCategory) then
        return true
    end
    if (LoadAddOn) then
        pcall(LoadAddOn, "Blizzard_Settings")
        pcall(LoadAddOn, "Blizzard_SettingsDefinitions")
    end
    return _G.Settings and _G.Settings.RegisterCanvasLayoutCategory and _G.Settings.RegisterAddOnCategory
end

local function registerOptionsCategory()
    local registeredAny = false

    local ok = pcall(function()
        if (not settingsCategoryRegistered and ensureSettingsUI()) then
            addOnOptionsCategory = addOnOptionsCategory or _G.Settings.RegisterCanvasLayoutCategory(optionsFrame, optionsFrame.name)
            if (addOnOptionsCategory) then
                _G.Settings.RegisterAddOnCategory(addOnOptionsCategory)
                settingsCategoryRegistered = true
                registeredAny = true
            end
        end

        if (not InterfaceOptions_AddCategory and LoadAddOn) then
            pcall(LoadAddOn, "Blizzard_OptionsUI")
            pcall(LoadAddOn, "Blizzard_InterfaceOptions")
        end

        if (not legacyCategoryRegistered and InterfaceOptions_AddCategory) then
            InterfaceOptions_AddCategory(optionsFrame)
            legacyCategoryRegistered = true
            registeredAny = true
        end
    end)

    return ok and (registeredAny or settingsCategoryRegistered or legacyCategoryRegistered) or false
end

local optionsBootstrapFrame = CreateFrame("Frame")
optionsBootstrapFrame:RegisterEvent("PLAYER_LOGIN")
optionsBootstrapFrame:RegisterEvent("ADDON_LOADED")
optionsBootstrapFrame:SetScript("OnEvent", function(self, event)
    registerOptionsCategory()

    if (event == "PLAYER_LOGIN") then
        self:UnregisterEvent("PLAYER_LOGIN")
    end

    if (settingsCategoryRegistered) then
        self:UnregisterEvent("ADDON_LOADED")
        self:SetScript("OnEvent", nil)
    end
end)

registerOptionsCategory()

optionsFrame:Hide()

openOptionsPanel = function()
    registerOptionsCategory()
    if (settingsCategoryRegistered and _G.Settings and _G.Settings.OpenToCategory and addOnOptionsCategory) then
        local categoryID = addOnOptionsCategory.GetID and addOnOptionsCategory:GetID() or addOnOptionsCategory.ID
        if (categoryID) then
            local opened = pcall(_G.Settings.OpenToCategory, categoryID)
            if (opened) then
                return
            end
        end
        pcall(_G.Settings.OpenToCategory, optionsFrame.name)
        return
    end
    if (legacyCategoryRegistered and InterfaceOptionsFrame_OpenToCategory) then
        InterfaceOptionsFrame_OpenToCategory(optionsFrame)
        InterfaceOptionsFrame_OpenToCategory(optionsFrame)
        return
    end
    print("|cff59f0dcTacoTip:|r Options panel is unavailable on this client. Use /tacotip custom to move the tooltip.")
end

TT.OpenOptionsPanel = openOptionsPanel

optionsFrame:SetScript("OnShow", function(panel)
    local options = {}
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(addOnName .. " v" .. addOnVersion)

    local descriptionText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    descriptionText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    descriptionText:SetText(L["TEXT_OPT_DESC"])

    local function newCheckbox(name, label, tooltipDescription, onClick)
        local check = CreateFrame("CheckButton", "TacoTipOptCheckBox" .. name, panel, "InterfaceOptionsCheckButtonTemplate")
        check:SetScript("OnClick", function(self)
            local tick = self:GetChecked()
            onClick(self, tick and true or false)
        end)
        check.SetDisabled = function(self, disable)
            if disable then
                self:Disable()
                _G[self:GetName() .. 'Text']:SetFontObject('GameFontDisable')
            else
                self:Enable()
                _G[self:GetName() .. 'Text']:SetFontObject('GameFontHighlight')
            end
        end
        check.label = _G[check:GetName() .. "Text"]
        check.label:SetText(label)
        if (tooltipDescription) then
            check.tooltipText = label
            check.tooltipRequirement = tooltipDescription
        end
        return check
    end

    local function newDropDown(name, values, callback)
        local dropDown = CreateFrame("Frame", "TacoTipOptDropDown" .. name, panel, "UIDropDownMenuTemplate")
        UIDropDownMenu_Initialize(dropDown, function(dropdownFrame, level, menuList)
            for i,selection in ipairs(values) do
                local info = UIDropDownMenu_CreateInfo()
                local text, desc = unpack(selection)
                info.text, info.checked, info.value = text, dropdownFrame.selectedValue == i, i
                info.func = function(menuButton)
                    dropdownFrame:SetValue(menuButton.value)
                    callback(menuButton.value)
                end
                if(desc) then
                    info.tooltipTitle = text
                    info.tooltipText = desc
                    info.tooltipOnButton = 1
                end
                UIDropDownMenu_AddButton(info)
            end
        end)
        dropDown.SetValue = function(dropdownValue, value)
            dropdownValue.selectedValue = value
            UIDropDownMenu_SetSelectedValue(dropdownValue, value)
            UIDropDownMenu_SetText(dropdownValue, values[value][1])
        end
        return dropDown
    end

    local function newRadioButton(name, label, tooltipDescription, onClick)
        local check = CreateFrame("CheckButton", "TacoTipOptRadioButton" .. name, panel, "InterfaceOptionsCheckButtonTemplate, UIRadioButtonTemplate")
        check:SetScript("OnClick", function(self)
            if(not self:GetChecked()) then
                self:SetChecked(true)
            end
            onClick(self, true)
        end)
        check.SetDisabled = function(self, disable)
            if disable then
                self:Disable()
                _G[self:GetName() .. 'Text']:SetFontObject('GameFontDisable')
            else
                self:Enable()
                _G[self:GetName() .. 'Text']:SetFontObject('GameFontHighlight')
            end
        end
        check.label = _G[check:GetName() .. "Text"]
        check.label:SetText(label)
        if (tooltipDescription) then
            check.tooltipText = label
            check.tooltipRequirement = tooltipDescription
        end
        return check
    end


    options.exampleTooltip = CreateFrame("GameTooltip", "TacoTipOptExampleTooltip", panel, "GameTooltipTemplate")
    options.exampleTooltipHealthBar = CreateFrame("StatusBar", "TacoTipOptExampleTooltipStatusBar", options.exampleTooltip)
    options.exampleTooltipHealthBar:SetSize(0, 8)
    options.exampleTooltipHealthBar:SetPoint("TOPLEFT", options.exampleTooltip, "BOTTOMLEFT", 2, -1)
    options.exampleTooltipHealthBar:SetPoint("TOPRIGHT", options.exampleTooltip, "BOTTOMRIGHT", -2, -1)
    options.exampleTooltipHealthBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-TargetingFrame-BarFill")
    options.exampleTooltipHealthBar:SetStatusBarColor(0, 1, 0)
    options.exampleTooltipPowerBar = CreateFrame("StatusBar", "TacoTipOptExampleTooltipPowerBar", options.exampleTooltip)
    options.exampleTooltipPowerBar:SetSize(0, 8)
    options.exampleTooltipPowerBar:SetPoint("TOPLEFT", options.exampleTooltip, "BOTTOMLEFT", 2, -9)
    options.exampleTooltipPowerBar:SetPoint("TOPRIGHT", options.exampleTooltip, "BOTTOMRIGHT", -2, -9)
    options.exampleTooltipPowerBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-TargetingFrame-BarFill")
    options.exampleTooltipPowerBar:SetStatusBarColor(1, 1, 0)
    local function showExampleTooltip()
        options.exampleTooltip:SetOwner(panel, "ANCHOR_NONE")
        options.exampleTooltip:ClearLines()
        options.exampleTooltip:ClearAllPoints()
        options.exampleTooltip:SetPoint("TOPLEFT", descriptionText, "TOPLEFT", 340, 0)
        local classc = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)["ROGUE"]
        local name_r = TacoTipConfig.color_class and classc and classc.r or 0
        local name_g = TacoTipConfig.color_class and classc and classc.g or 0.6
        local name_b = TacoTipConfig.color_class and classc and classc.b or 0.1
        local playerTitle = TacoTipConfig.show_titles and L[" the Kingslayer"] or ""
        options.exampleTooltip:AddLine(string.format("|cFF%02x%02x%02xKebabstorm%s %s%s|r", name_r*255, name_g*255, name_b*255, playerTitle, (TacoTipConfig.show_team and (HORDE_ICON.." ") or ""), (TacoTipConfig.show_pvp_icon and PVP_FLAG_ICON or "")))
        if (TacoTipConfig.show_guild_name) then
            if (TacoTipConfig.show_guild_rank) then
                if (TacoTipConfig.guild_rank_alt_style) then
                    options.exampleTooltip:AddLine("|cFF40FB40<Drunken Wrath> (Officer)|r")
                else
                    options.exampleTooltip:AddLine(string.format("|cFF40FB40"..L["FORMAT_GUILD_RANK_1"].."|r", "Officer", "Drunken Wrath"))
                end
            else
                options.exampleTooltip:AddLine("|cFF40FB40<Drunken Wrath>|r")
            end
        end
        if (TacoTipConfig.color_class) then
            options.exampleTooltip:AddLine(string.format("%s 80 %s |cFF%02x%02x%02x%s|r (%s)", L["Level"], L["Undead"], name_r*255, name_g*255, name_b*255, LOCALIZED_CLASS_NAMES_MALE["ROGUE"], L["Player"]), 1, 1, 1)
        else
            options.exampleTooltip:AddLine(string.format("%s 80 %s %s (%s)", L["Level"], L["Undead"], LOCALIZED_CLASS_NAMES_MALE["ROGUE"], L["Player"]), 1, 1, 1)
        end

        if (not TacoTipConfig.show_pvp_icon) then
            options.exampleTooltip:AddLine("PvP", 1, 1, 1)
        end

        local wide_style = (TacoTipConfig.tip_style == 1 or ((TacoTipConfig.tip_style == 2 or TacoTipConfig.tip_style == 4) and IsShiftKeyDown()))
        local mini_style = (not wide_style and (TacoTipConfig.tip_style == 4 or TacoTipConfig.tip_style == 5))

        if (TacoTipConfig.show_target) then
            if (wide_style) then
                options.exampleTooltip:AddDoubleLine(L["Target"]..":", L["None"], NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, GRAY_FONT_COLOR.r, GRAY_FONT_COLOR.g, GRAY_FONT_COLOR.b)
            else
                options.exampleTooltip:AddLine(L["Target"]..": |cFF808080"..L["None"].."|r")
            end
        end
        if (TacoTipConfig.show_talents) then
            if (wide_style) then
                options.exampleTooltip:AddDoubleLine(L["Talents"]..":", CI:GetSpecializationName("ROGUE", 1, true).." [51/18/2]", NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
                options.exampleTooltip:AddDoubleLine(" ", CI:GetSpecializationName("ROGUE", 3, true).." [14/3/54]", NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, GRAY_FONT_COLOR.r, GRAY_FONT_COLOR.g, GRAY_FONT_COLOR.b)
            else
                options.exampleTooltip:AddLine(L["Talents"]..":|cFFFFFFFF "..CI:GetSpecializationName("ROGUE", 1, true).." [51/18/2]")
            end
        end
        local miniText = ""
        if (TacoTipConfig.show_gs_player) then
            local gs_r, gs_g, gs_b = GearScore:GetQuality(6054)
            if (wide_style) then
                options.exampleTooltip:AddDoubleLine("GearScore: 6054", "(iLvl: 264)", gs_r, gs_g, gs_b, gs_r, gs_g, gs_b)
            elseif (mini_style) then
                miniText = string.format("|cFF%02x%02x%02xGS: 6054  L: 264|r  ", gs_r*255, gs_g*255, gs_b*255)
            else
                options.exampleTooltip:AddLine("GearScore: 6054", gs_r, gs_g, gs_b)
            end
        end
        if (isPawnLoaded and TacoTipConfig.show_pawn_player) then
            local specColor = PawnGetScaleColor("\"Classic\":ROGUE1", true) or "|cffffffff"
            if (wide_style) then
                options.exampleTooltip:AddDoubleLine(string.format("Pawn: %s1234.56|r", specColor), string.format("%s(%s)|r", specColor, CI:GetSpecializationName("ROGUE", 1, true)), 1, 1, 1, 1, 1, 1)
            elseif (mini_style) then
                miniText = miniText .. string.format("P: %s1234.5|r", specColor)
            else
                options.exampleTooltip:AddLine(string.format("Pawn: %s1234.56 (%s)|r", specColor, CI:GetSpecializationName("ROGUE", 1, true)), 1, 1, 1)
            end
        end
        if (miniText ~= "") then
            options.exampleTooltip:AddLine(miniText, 1, 1, 1)
        end
        options.exampleTooltip:Show()
        if (TacoTipConfig.show_hp_bar) then
            options.exampleTooltipHealthBar:Show()
            options.exampleTooltipPowerBar:SetPoint("TOPLEFT", options.exampleTooltip, "BOTTOMLEFT", 2, -9)
            options.exampleTooltipPowerBar:SetPoint("TOPRIGHT", options.exampleTooltip, "BOTTOMRIGHT", -2, -9)
        else
            options.exampleTooltipHealthBar:Hide()
            options.exampleTooltipPowerBar:SetPoint("TOPLEFT", options.exampleTooltip, "BOTTOMLEFT", 2, -1)
            options.exampleTooltipPowerBar:SetPoint("TOPRIGHT", options.exampleTooltip, "BOTTOMRIGHT", -2, -1)
        end
        if (TacoTipConfig.show_power_bar) then
            options.exampleTooltipPowerBar:Show()
        else
            options.exampleTooltipPowerBar:Hide()
        end
    end
    options.exampleTooltip:SetScript("OnEvent", function() showExampleTooltip() end)


    local generalText = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    generalText:SetPoint("TOPLEFT", descriptionText, "BOTTOMLEFT", 0, -18)
    generalText:SetText(L["Unit Tooltips"])

    options.useClassColors = newCheckbox(
        "ClassColors",
        L["Class Color"],
        L["Color class names in tooltips"],
        function(self, value)
            TacoTipConfig.color_class = value
            showExampleTooltip()
        end)
    options.useClassColors:SetPoint("TOPLEFT", generalText, "BOTTOMLEFT", -2, -4)

    options.showTitles = newCheckbox(
        "ShowTitles",
        L["Title"],
        L["Show player's title in tooltips"],
        function(self, value)
            TacoTipConfig.show_titles = value
            showExampleTooltip()
        end)
    options.showTitles:SetPoint("TOPLEFT", generalText, "BOTTOMLEFT", 140, -4)

    options.showGuildNames = newCheckbox(
        "GuildNames",
        L["Guild Name"],
        L["Show guild name in tooltips"],
        function(self, value)
            TacoTipConfig.show_guild_name = value
            options.showGuildRanks:SetDisabled(not value)
            if (value) then
                options.guildRankStyle1:SetDisabled(not TacoTipConfig.show_guild_rank)
                options.guildRankStyle2:SetDisabled(not TacoTipConfig.show_guild_rank)
            else
                options.guildRankStyle1:SetDisabled(true)
                options.guildRankStyle2:SetDisabled(true)
            end
            showExampleTooltip()
        end)
    options.showGuildNames:SetPoint("TOPLEFT", generalText, "BOTTOMLEFT", -2, -32)

    options.showGuildRanks = newCheckbox(
        "GuildRanks",
        L["Guild Rank"],
        L["Show guild rank in tooltips"],
        function(self, value)
            TacoTipConfig.show_guild_rank = value
            options.guildRankStyle1:SetDisabled(not value)
            options.guildRankStyle2:SetDisabled(not value)
            showExampleTooltip()
        end)
    options.showGuildRanks:SetPoint("TOPLEFT", generalText, "BOTTOMLEFT", 140, -32)
    options.showGuildRanks:SetHitRectInsets(0, -80, 0, 0)

    options.guildRankStyle1 = newRadioButton(
        "GuildRankStyle1",
        L["Style"].." 1",
        string.format(L["FORMAT_GUILD_RANK_1"], L["Rank"], L["Guild"]),
        function(self, value)
            options.guildRankStyle2:SetChecked(false)
            TacoTipConfig.guild_rank_alt_style = false
            showExampleTooltip()
        end)
    options.guildRankStyle1.label:SetText("1")
    options.guildRankStyle1:SetPoint("TOPLEFT", generalText, "BOTTOMLEFT", 248, -36)
    options.guildRankStyle1:SetHitRectInsets(0, -16, 0, 0)

    options.guildRankStyle2 = newRadioButton(
        "GuildRankStyle2",
        L["Style"].." 2",
        string.format("<%s> (%s)", L["Guild"], L["Rank"]),
        function(self, value)
            options.guildRankStyle1:SetChecked(false)
            TacoTipConfig.guild_rank_alt_style = true
            showExampleTooltip()
        end)
    options.guildRankStyle2.label:SetText("2")
    options.guildRankStyle2:SetPoint("TOPLEFT", generalText, "BOTTOMLEFT", 280, -36)
    options.guildRankStyle2:SetHitRectInsets(0, -16, 0, 0)

    local rankstylehint = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    rankstylehint:SetPoint("TOPLEFT", generalText, "BOTTOMLEFT", 264, -23)
    rankstylehint:SetText(L["Style"])

    options.showTalents = newCheckbox(
        "Talents",
        L["Talents"],
        L["Show talents and specialization in tooltips"],
        function(self, value)
            TacoTipConfig.show_talents = value
            showExampleTooltip()
        end)
    options.showTalents:SetPoint("TOPLEFT", generalText, "BOTTOMLEFT", -2, -60)

    options.gearScorePlayer = newCheckbox(
        "GearScorePlayer",
        "GearScore",
        L["Show player's GearScore in tooltips"],
        function(self, value)
            TacoTipConfig.show_gs_player = value
            showExampleTooltip()
        end)
    options.gearScorePlayer:SetPoint("TOPLEFT", generalText, "BOTTOMLEFT", 140, -60)

    options.pawnScorePlayer = newCheckbox(
        "PawnScorePlayer",
        "PawnScore",
        L["Show player's PawnScore in tooltips (may affect performance)"],
        function(self, value)
            TacoTipConfig.show_pawn_player = value
            showExampleTooltip()
        end)
    options.pawnScorePlayer:SetPoint("TOPLEFT", generalText, "BOTTOMLEFT", 140, -88)

    options.showTarget = newCheckbox(
        "ShowTarget",
        L["Target"],
        L["Show unit's target in tooltips"],
        function(self, value)
            TacoTipConfig.show_target = value
            showExampleTooltip()
        end)
    options.showTarget:SetPoint("TOPLEFT", generalText, "BOTTOMLEFT", -2, -88)

    options.showTeam = newCheckbox(
        "ShowTeam",
        L["Faction Icon"],
        L["Show player's faction icon (Horde/Alliance) in tooltips"],
        function(self, value)
            TacoTipConfig.show_team = value
            showExampleTooltip()
        end)
    options.showTeam:SetPoint("TOPLEFT", generalText, "BOTTOMLEFT", -2, -116)

    options.showPVPIcon = newCheckbox(
        "ShowPVPIcon",
        L["PVP Icon"],
        L["Show player's pvp flag status as icon instead of text"],
        function(self, value)
            TacoTipConfig.show_pvp_icon = value
            showExampleTooltip()
        end)
    options.showPVPIcon:SetPoint("TOPLEFT", generalText, "BOTTOMLEFT", 140, -116)

    options.showHealthBar = newCheckbox(
        "ShowHealthBar",
        L["Health Bar"],
        L["Show unit's health bar under tooltip"],
        function(self, value)
            TacoTipConfig.show_hp_bar = value
            showExampleTooltip()
        end)
    options.showHealthBar:SetPoint("TOPLEFT", generalText, "BOTTOMLEFT", -2, -144)

    options.showPowerBar = newCheckbox(
        "ShowPowerBar",
        L["Power Bar"],
        L["Show unit's power bar under tooltip"],
        function(self, value)
            TacoTipConfig.show_power_bar = value
            if (TacoTipPowerBar) then
                if (not value and TacoTipPowerBar.updateTicker) then
                    TacoTipPowerBar.updateTicker:Cancel()
                    TacoTipPowerBar.updateTicker = nil
                end
                if (not value) then
                    TacoTipPowerBar:Hide()
                end
            end
            showExampleTooltip()
        end)
    options.showPowerBar:SetPoint("TOPLEFT", generalText, "BOTTOMLEFT", 140, -144)


    local characterFrameText = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    characterFrameText:SetPoint("TOPLEFT", descriptionText, "BOTTOMLEFT", 0, -216)
    characterFrameText:SetText(L["Character Frame"])

    local function refreshLockPositionToggle()
        if (options.lockCharacterInfoPosition) then
            options.lockCharacterInfoPosition:SetDisabled(not (TacoTipConfig.show_gs_character or TacoTipConfig.show_avg_ilvl))
        end
    end

    options.gearScoreCharacter = newCheckbox(
        "GearScoreCharacter",
        "GearScore",
        L["Show GearScore in character frame"],
        function(self, value)
            TacoTipConfig.show_gs_character = value
            refreshLockPositionToggle()
            if (PaperDollFrame and PaperDollFrame:IsShown()) then
                TT:RefreshCharacterFrame()
            end
            if (InspectFrame and InspectFrame:IsShown()) then
                TT:RefreshInspectFrame()
            end
        end)
    options.gearScoreCharacter:SetPoint("TOPLEFT", characterFrameText, "BOTTOMLEFT", -2, -4)

    options.averageItemLevel = newCheckbox(
        "AverageItemLevel",
        L["Average iLvl"],
        L["Show Average Item Level in character frame"],
        function(self, value)
            TacoTipConfig.show_avg_ilvl = value
            refreshLockPositionToggle()
            if (PaperDollFrame and PaperDollFrame:IsShown()) then
                TT:RefreshCharacterFrame()
            end
            if (InspectFrame and InspectFrame:IsShown()) then
                TT:RefreshInspectFrame()
            end
        end)
    options.averageItemLevel:SetPoint("TOPLEFT", characterFrameText, "BOTTOMLEFT", 140, -4)

    options.lockCharacterInfoPosition = newCheckbox(
        "LockCharacterInfoPosition",
        L["Lock Position"],
        L["Lock GearScore and Average Item Level positions in character frame"],
        function(self, value)
            TacoTipConfig.unlock_info_position = not value
            if (PaperDollFrame and PaperDollFrame:IsShown()) then
                TT:RefreshCharacterFrame()
            end
            if (InspectFrame and InspectFrame:IsShown()) then
                TT:RefreshInspectFrame()
            end
        end)
    options.lockCharacterInfoPosition:SetPoint("TOPLEFT", characterFrameText, "BOTTOMLEFT", -2, -32)


    local extraText = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    extraText:SetPoint("TOPLEFT", descriptionText, "BOTTOMLEFT", 0, -302)
    extraText:SetText(L["Extra"])

    options.showItemLevel = newCheckbox(
        "ShowItemLevel",
        L["Show Item Level"],
        L["Display item level in the tooltip for certain items."],
        function(self, value)
            TacoTipConfig.show_item_level = value
        end)
    options.showItemLevel:SetPoint("TOPLEFT", extraText, "BOTTOMLEFT", -2, -4)

    options.gearScoreItems = newCheckbox(
        "GearScoreItems",
        L["Show Item GearScore"],
        L["Show GearScore in item tooltips"],
        function(self, value)
            TacoTipConfig.show_gs_items = value
            options.hunterScoreItems:SetDisabled(not value)
        end)
    options.gearScoreItems:SetPoint("TOPLEFT", extraText, "BOTTOMLEFT", -2, -32)

    options.hunterScoreItems = newCheckbox(
        "HunterScoreItems",
        L["HunterScore"],
        L["Always show HunterScore in item tooltips"],
        function(self, value)
            TacoTipConfig.show_gs_items_hs = value
        end)
    options.hunterScoreItems:SetPoint("TOPLEFT", extraText, "BOTTOMLEFT", 140, -32)

    options.uberTips = newCheckbox(
        "UberTips",
        L["Enhanced Tooltips"],
        L["TEXT_OPT_UBERTIPS"],
        function(self, value)
            SetCVar("UberTooltips", value and "1" or "0")
        end)
    options.uberTips:SetPoint("TOPLEFT", extraText, "BOTTOMLEFT", -2, -60)

    options.hideInCombat = newCheckbox(
        "HideInCombat",
        L["Disable In Combat"],
        L["Disable gearscore & talents in combat"],
        function(self, value)
            TacoTipConfig.hide_in_combat = value
        end)
    options.hideInCombat:SetPoint("TOPLEFT", extraText, "BOTTOMLEFT", -2, -88)

    options.chatClassColors = newCheckbox(
        "ChatClassColors",
        L["Chat Class Colors"],
        L["Color names by class in chat windows"],
        function(self, value)
            SetCVar("chatClassColorOverride", value and "0" or "1")
        end)
    options.chatClassColors:SetPoint("TOPLEFT", extraText, "BOTTOMLEFT", -2, -116)

    options.customPosition = newCheckbox(
        "CustomPosition",
        L["Custom Tooltip Position"],
        L["Set a custom position for tooltips"],
        function(self, value)
            options.anchorMouse:SetDisabled(value)
            if (value) then
                TacoTipConfig.anchor_mouse = false
                setButtonEnabled(options.moverBtn, true)
                TacoTip_CustomPosEnable(false)
            else
                setButtonEnabled(options.moverBtn, false)
                if (TacoTipDragButton) then
                    TacoTipDragButton:_Disable()
                end
                TacoTipConfig.custom_pos = nil
                TacoTipConfig.custom_anchor = nil
            end
        end)
    options.customPosition:SetPoint("TOPLEFT", extraText, "BOTTOMLEFT", 188, -4)

    options.moverBtn = CreateFrame("Button", "TacoTipOptButtonMover", panel, "UIPanelButtonTemplate")
    options.moverBtn:SetText(L["Mover"])
    options.moverBtn:SetWidth(80)
    options.moverBtn:SetHeight(20)
    options.moverBtn:SetPoint("TOPLEFT", extraText, "BOTTOMLEFT", 374, -5)
    options.moverBtn:SetScript("OnClick", function()
        TacoTip_CustomPosEnable(true)
    end)

    options.anchorMouse = newCheckbox(
        "AnchorMouse",
        L["Anchor to Mouse"],
        L["Anchor tooltips to mouse cursor"],
        function(self, value)
            options.anchorMouseWorld:SetDisabled(not value)
            options.customPosition:SetDisabled(value)
            TacoTipConfig.anchor_mouse = value
            if (value) then
                setButtonEnabled(options.moverBtn, false)
                if (TacoTipDragButton) then
                    TacoTipDragButton:_Disable()
                end
                TacoTipConfig.custom_pos = nil
                TacoTipConfig.custom_anchor = nil
            end
        end)
    options.anchorMouse:SetPoint("TOPLEFT", extraText, "BOTTOMLEFT", 188, -32)

    options.anchorMouseWorld = newCheckbox(
        "AnchorMouseWorld",
        L["Only in WorldFrame"],
        L["Anchor to mouse only in WorldFrame\nSkips raid / party frames"],
        function(self, value)
            TacoTipConfig.anchor_mouse_world = value
        end)
    options.anchorMouseWorld:SetPoint("TOPLEFT", extraText, "BOTTOMLEFT", 374, -32)

    options.instantFade = newCheckbox(
        "InstantFade",
        L["Instant Fade"],
        L["Fade out unit tooltips instantly"],
        function(self, value)
            TacoTipConfig.instant_fade = value
            updateInstantFadeState(value)
        end)
    options.instantFade:SetPoint("TOPLEFT", extraText, "BOTTOMLEFT", 188, -60)

    options.anchorMouseSpells = newCheckbox(
        "AnchorMouseSpells",
        L["Anchor Spells to Mouse"],
        L["Anchor spell tooltips to mouse cursor"],
        function(self, value)
            TacoTipConfig.anchor_mouse_spells = value
        end)
    options.anchorMouseSpells:SetPoint("TOPLEFT", extraText, "BOTTOMLEFT", 188, -88)

    options.showAchievementPoints = newCheckbox(
        "ShowAchievementPoints",
        L["Show Achievement Points"],
        L["Show total achievement points in tooltips"],
        function(self, value)
            TacoTipConfig.show_achievement_points = value
        end)
    options.showAchievementPoints:SetPoint("TOPLEFT", extraText, "BOTTOMLEFT", 188, -116)

    local styleText = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    styleText:SetPoint("TOPLEFT", descriptionText, "BOTTOMLEFT", 341, -154)
    styleText:SetText(L["Tooltip Style"])

    local dropdown_values = {
        {L["FULL"], L["Always FULL"]},
        {L["COMPACT/FULL"], L["Default COMPACT, hold SHIFT for FULL"]},
        {L["COMPACT"], L["Always COMPACT"]},
        {L["MINI/FULL"], L["Default MINI, hold SHIFT for FULL"]},
        {L["MINI"], L["Always MINI"]}
    }
    options.styleChoice = newDropDown(
        "StyleChoice",
        dropdown_values,
        function(value)
            TacoTipConfig.tip_style = value
            showExampleTooltip()
        end)
    options.styleChoice:SetPoint("TOPLEFT", styleText, "BOTTOMLEFT", -20, -4)
    options.styleChoice:SetValue(TacoTipConfig.tip_style)

    local althint1 = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    althint1:SetPoint("TOPLEFT", styleText, "BOTTOMLEFT", -61, -48)
    althint1:SetText(L["FULL"])
    local althint2 = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    althint2:SetPoint("TOPLEFT", althint1, "BOTTOMLEFT", 0, 0)
    althint2:SetText(L["COMPACT"])
    local althint3 = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    althint3:SetPoint("TOPLEFT", althint2, "BOTTOMLEFT", 0, 0)
    althint3:SetText(L["MINI"])
    local althint4 = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    althint4:SetPoint("TOPLEFT", styleText, "BOTTOMLEFT", 3, -48)
    althint4:SetText(L["Wide, Dual Spec, GearScore, Average iLvl"])
    local althint5 = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    althint5:SetPoint("TOPLEFT", althint4, "BOTTOMLEFT", 0, 0)
    althint5:SetText(L["Narrow, Active Spec, GearScore"])
    local althint6 = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    althint6:SetPoint("TOPLEFT", althint5, "BOTTOMLEFT", 0, 0)
    althint6:SetText(L["Narrow, Active Spec, GearScore, Average iLvl"])


    local function getConfig()
        options.useClassColors:SetChecked(TacoTipConfig.color_class)
        options.showTitles:SetChecked(TacoTipConfig.show_titles)
        options.showGuildNames:SetChecked(TacoTipConfig.show_guild_name)
        options.showGuildRanks:SetChecked(TacoTipConfig.show_guild_rank)
        options.showTalents:SetChecked(TacoTipConfig.show_talents)
        options.gearScorePlayer:SetChecked(TacoTipConfig.show_gs_player)
        options.gearScoreCharacter:SetChecked(TacoTipConfig.show_gs_character)
        options.gearScoreItems:SetChecked(TacoTipConfig.show_gs_items)
        options.hunterScoreItems:SetChecked(TacoTipConfig.show_gs_items_hs)
        options.hunterScoreItems:SetDisabled(not TacoTipConfig.show_gs_items)
        options.averageItemLevel:SetChecked(TacoTipConfig.show_avg_ilvl)
        options.showItemLevel:SetChecked(TacoTipConfig.show_item_level)
        options.hideInCombat:SetChecked(TacoTipConfig.hide_in_combat)
        options.uberTips:SetChecked(GetCVar("UberTooltips") == "1")
        options.showTarget:SetChecked(TacoTipConfig.show_target)
        options.styleChoice:SetValue(TacoTipConfig.tip_style)
        options.showGuildRanks:SetDisabled(not TacoTipConfig.show_guild_name)
        options.customPosition:SetChecked(TacoTipConfig.custom_pos and true or false)
        options.customPosition:SetDisabled(TacoTipConfig.anchor_mouse)
        setButtonEnabled(options.moverBtn, TacoTipConfig.custom_pos and true or false)
        options.pawnScorePlayer:SetDisabled(not isPawnLoaded)
        options.pawnScorePlayer:SetChecked(TacoTipConfig.show_pawn_player)
        options.pawnScorePlayer.label:SetText(isPawnLoaded and "PawnScore" or "PawnScore ("..L["requires Pawn"]..")")
        options.showTeam:SetChecked(TacoTipConfig.show_team)
        options.showPVPIcon:SetChecked(TacoTipConfig.show_pvp_icon)
        options.guildRankStyle1:SetChecked(not TacoTipConfig.guild_rank_alt_style)
        options.guildRankStyle2:SetChecked(TacoTipConfig.guild_rank_alt_style)
        options.guildRankStyle1:SetDisabled(not TacoTipConfig.show_guild_rank)
        options.guildRankStyle2:SetDisabled(not TacoTipConfig.show_guild_rank)
        options.showHealthBar:SetChecked(TacoTipConfig.show_hp_bar)
        options.showPowerBar:SetChecked(TacoTipConfig.show_power_bar)
        options.instantFade:SetChecked(TacoTipConfig.instant_fade)
        options.chatClassColors:SetChecked(GetCVar("chatClassColorOverride") == "0")
        options.anchorMouse:SetChecked(TacoTipConfig.anchor_mouse)
        options.anchorMouse:SetDisabled(TacoTipConfig.custom_pos and true or false)
        options.anchorMouseWorld:SetChecked(TacoTipConfig.anchor_mouse_world)
        options.anchorMouseWorld:SetDisabled(not TacoTipConfig.anchor_mouse)
        options.anchorMouseSpells:SetChecked(TacoTipConfig.anchor_mouse_spells)
        options.lockCharacterInfoPosition:SetChecked(not TacoTipConfig.unlock_info_position)
        refreshLockPositionToggle()
        if (CI:IsWotlk()) then
            options.showAchievementPoints:SetChecked(TacoTipConfig.show_achievement_points)
            options.showAchievementPoints:SetDisabled(false)
        else
            TacoTipConfig.show_achievement_points = false
            options.showAchievementPoints:SetChecked(false)
            options.showAchievementPoints:SetDisabled(true)
        end
    end

    panel.Refresh = function()
        getConfig()
        showExampleTooltip()
    end

    local resetcfg = CreateFrame("Button", "TacoTipOptButtonResetCfg", panel, "UIPanelButtonTemplate")
    resetcfg:SetText(L["Reset configuration"])
    resetcfg:SetWidth(177)
    resetcfg:SetHeight(24)
    resetcfg:SetPoint("TOPLEFT", extraText, "BOTTOMLEFT", 0, -152)
    resetcfg:SetScript("OnClick", function()
        resetCfg()
        panel:Refresh()
    end)

    getConfig()
    options.exampleTooltip:RegisterEvent("MODIFIER_STATE_CHANGED")
    showExampleTooltip()

    panel:SetScript("OnShow", function()
        getConfig()
        options.exampleTooltip:RegisterEvent("MODIFIER_STATE_CHANGED")
        showExampleTooltip()
    end)
    panel:SetScript("OnHide", function()
        options.exampleTooltip:UnregisterEvent("MODIFIER_STATE_CHANGED")
    end)
end)

