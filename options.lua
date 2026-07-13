
local addOnName = ...
local addOnVersion = (GetAddOnMetadata and GetAddOnMetadata(addOnName, "Version")) or (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addOnName, "Version")) or "0.5.7"
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

-- Safe-call wrapper. Routes errors through Blizzard's geterrorhandler()
-- global so they are captured by error display addons (BugSack, !Swatter,
-- BugGrabber, etc.) instead of silently breaking the options panel.
local function safeCall(fn, ...)
    return xpcall(fn, geterrorhandler(), ...)
end

-- Clamp a frame level to the documented WoW range [0, 100]. 0 is the
-- lowest visible level within a strata, 100 is comfortably above the
-- deepest Blizzard panel we ever sit under.
local function clampFrameLevel(level)
    level = tonumber(level) or 0
    if (level < 0) then
        return 0
    end
    if (level > 100) then
        return 100
    end
    return math.floor(level + 0.5)
end

-- Clamp a SetAlpha value to the documented WoW range [0, 1]. Values
-- outside this range are silently ignored by the client and indicate
-- a bad computation upstream.
local function clampAlpha(value)
    value = tonumber(value)
    if (not value) then
        return 1
    end
    if (value < 0) then
        return 0
    end
    if (value > 1) then
        return 1
    end
    return value
end

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
        show_pawn_player = true,
        show_team = false,
        show_class_icon = true,
        class_icon_size = 20,
        show_pvp_icon = false,
        guild_rank_alt_style = false,
        show_hp_bar = true,
        show_power_bar = false,
        tooltip_border_use_class = true,
        tooltip_background_use_class = false,
        tooltip_border_color_r = 1,
        tooltip_border_color_g = 1,
        tooltip_border_color_b = 1,
        tooltip_border_alpha = 0.85,
        tooltip_background_color_r = 0,
        tooltip_background_color_g = 0,
        tooltip_background_color_b = 0,
        tooltip_background_alpha = 0.85,
        tooltip_background_texture = "Interface\\Tooltips\\UI-Tooltip-Background",
        tooltip_border_texture = "Interface\\Tooltips\\UI-Tooltip-Border",
        tooltip_border_edge_size = 16,
        tooltip_portrait = true,
        tooltip_portrait_scale = 1,
        tooltip_portrait_3d = true,
        tooltip_portrait_zoom = 0.7,
        show_elite_frame = true,
        tooltip_font = "Fonts\\FRIZQT__.TTF",
        tooltip_font_size = 12,
        tooltip_bar_texture = "Interface\\TargetingFrame\\UI-TargetingFrame-BarFill",
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
        locale_override = nil,
        unlock_info_position = false,
        show_achievement_points = false,
        guild_rank_style = 1,
        show_gs_delta = false,
        show_honor_rank = false,
        show_ilvl_inline = false,
        show_realm = false,
        show_role_icon = false,
        show_separators = false,
        tooltip_delay = 0,
        tooltip_max_width = 0,
        --conf_version = addOnVersion,
        --custom_pos = nil,
        --custom_anchor = nil,
    }
end

function TT:ApplyConfigDefaults(config)
    if (not config or type(config) ~= "table") then
        return
    end
    for k, v in pairs(self:GetDefaults()) do
        if (config[k] == nil) then
            config[k] = v
        end
    end
    self:SafeSanitizeConfig(config)
end

-- Validates and repairs common saved-variable corruption patterns that can
-- cause the tooltip to break silently (wrong types, out-of-range values).
-- Called after defaults are applied every load, so even partially-corrupt
-- configs are repaired without requiring the user to delete SavedVariables.
function TT:SafeSanitizeConfig(config)
    if (not config or type(config) ~= "table") then
        return
    end

    local defaults = self:GetDefaults()

    -- Type-check known boolean keys and reset to default if they are not
    -- actually a boolean.  WoW's saved-variable system sometimes serialises
    -- "true"/"false" strings instead of real booleans.
    local booleanKeys = {
        "color_class", "show_titles", "show_guild_name", "show_guild_rank",
        "show_talents", "show_gs_player", "show_gs_character", "show_gs_items",
        "show_gs_items_hs", "show_avg_ilvl", "hide_in_combat", "show_item_level",
        "tip_style", "show_target", "show_pawn_player", "show_team",
        "show_class_icon", "show_pvp_icon", "guild_rank_alt_style",
        "show_hp_bar", "show_power_bar", "tooltip_border_use_class",
        "tooltip_background_use_class", "tooltip_portrait", "tooltip_portrait_3d",
        "show_elite_frame", "instant_fade", "anchor_mouse", "anchor_mouse_world",
        "anchor_mouse_spells", "unlock_info_position", "show_achievement_points",
        "show_gs_delta", "show_honor_rank", "show_ilvl_inline", "show_realm",
        "show_role_icon", "show_separators"
    }
    for _, key in ipairs(booleanKeys) do
        local val = config[key]
        if (val ~= nil and type(val) ~= "boolean") then
            config[key] = defaults[key]
        end
    end

    -- Sanitise numeric slider/range keys so out-of-bounds values from
    -- corruption or old versions do not cause layout or logic issues.
    if (type(config.class_icon_size) ~= "number" or config.class_icon_size < 8 or config.class_icon_size > 32) then
        config.class_icon_size = defaults.class_icon_size
    end
    if (type(config.tooltip_portrait_scale) ~= "number" or config.tooltip_portrait_scale < 0.5 or config.tooltip_portrait_scale > 2) then
        config.tooltip_portrait_scale = defaults.tooltip_portrait_scale
    end
    if (type(config.tooltip_portrait_zoom) ~= "number" or config.tooltip_portrait_zoom < 0.3 or config.tooltip_portrait_zoom > 1) then
        config.tooltip_portrait_zoom = defaults.tooltip_portrait_zoom
    end
    if (type(config.tooltip_font_size) ~= "number" or config.tooltip_font_size < 8 or config.tooltip_font_size > 20) then
        config.tooltip_font_size = defaults.tooltip_font_size
    end
    if (type(config.tooltip_border_edge_size) ~= "number" or config.tooltip_border_edge_size < 4 or config.tooltip_border_edge_size > 48) then
        config.tooltip_border_edge_size = defaults.tooltip_border_edge_size
    end
    if (type(config.tooltip_border_alpha) ~= "number" or config.tooltip_border_alpha < 0 or config.tooltip_border_alpha > 1) then
        config.tooltip_border_alpha = defaults.tooltip_border_alpha
    end
    if (type(config.tooltip_background_alpha) ~= "number" or config.tooltip_background_alpha < 0 or config.tooltip_background_alpha > 1) then
        config.tooltip_background_alpha = defaults.tooltip_background_alpha
    end
    if (type(config.tip_style) ~= "number" or config.tip_style < 1 or config.tip_style > 5) then
        config.tip_style = defaults.tip_style
    end
    if (type(config.tooltip_delay) ~= "number" or config.tooltip_delay < 0 or config.tooltip_delay > 5) then
        config.tooltip_delay = defaults.tooltip_delay
    end
    if (type(config.tooltip_max_width) ~= "number" or config.tooltip_max_width < 0 or config.tooltip_max_width > 500) then
        config.tooltip_max_width = defaults.tooltip_max_width
    end
    if (type(config.guild_rank_style) ~= "number" or config.guild_rank_style < 1 or config.guild_rank_style > 2) then
        config.guild_rank_style = defaults.guild_rank_style
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

if not TacoTipConfig or type(TacoTipConfig) ~= "table" then
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
                TacoTipDragButton:_Disable(true)
            end
            TacoTipConfig.custom_pos = nil
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
optionsFrame.name = addOnTitle or "TacoTip Gearscore TBC"
optionsFrame:SetSize(640, 400)
local optionsPages = {
    root = optionsFrame,
    tooltips = CreateFrame("Frame", "TacoTipOptionsTooltips"),
    positioning = CreateFrame("Frame", "TacoTipOptionsPositioning"),
    characterInspect = CreateFrame("Frame", "TacoTipOptionsCharacterInspect")
}

optionsPages.tooltips.name = L["OPTIONS_PAGE_TOOLTIPS"] or "Tooltips"
optionsPages.positioning.name = L["OPTIONS_PAGE_POSITIONING"] or "Positioning"
optionsPages.characterInspect.name = L["OPTIONS_PAGE_CHARACTER_INSPECT"] or "Character & Inspect"

optionsPages.tooltips.parent = optionsFrame.name
optionsPages.positioning.parent = optionsFrame.name
optionsPages.characterInspect.parent = optionsFrame.name

local addOnOptionsCategory
local modernSubcategories = {}
local legacyCategoryRegistered = false
local legacyChildCategoriesRegistered = false
local settingsCategoryRegistered = false
local settingsSubcategoriesRegistered = false

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

local function registerSettingsSubcategories()
    if (settingsSubcategoriesRegistered or not addOnOptionsCategory or not _G.Settings or not _G.Settings.RegisterCanvasLayoutSubcategory) then
        return settingsSubcategoriesRegistered
    end

    local ok = pcall(function()
        modernSubcategories.tooltips = modernSubcategories.tooltips or _G.Settings.RegisterCanvasLayoutSubcategory(addOnOptionsCategory, optionsPages.tooltips, optionsPages.tooltips.name)
        modernSubcategories.positioning = modernSubcategories.positioning or _G.Settings.RegisterCanvasLayoutSubcategory(addOnOptionsCategory, optionsPages.positioning, optionsPages.positioning.name)
        modernSubcategories.characterInspect = modernSubcategories.characterInspect or _G.Settings.RegisterCanvasLayoutSubcategory(addOnOptionsCategory, optionsPages.characterInspect, optionsPages.characterInspect.name)
    end)

    settingsSubcategoriesRegistered = ok and modernSubcategories.tooltips and modernSubcategories.positioning and modernSubcategories.characterInspect and true or settingsSubcategoriesRegistered
    return settingsSubcategoriesRegistered
end

local function registerLegacyChildCategories()
    if (legacyChildCategoriesRegistered or not InterfaceOptions_AddCategory) then
        return legacyChildCategoriesRegistered
    end

    local ok = pcall(function()
        InterfaceOptions_AddCategory(optionsPages.tooltips)
        InterfaceOptions_AddCategory(optionsPages.positioning)
        InterfaceOptions_AddCategory(optionsPages.characterInspect)
    end)

    legacyChildCategoriesRegistered = ok and true or legacyChildCategoriesRegistered
    return legacyChildCategoriesRegistered
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

        if (settingsCategoryRegistered) then
            registerSettingsSubcategories()
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

        if (legacyCategoryRegistered) then
            registerLegacyChildCategories()
        end
    end)

    return ok and (registeredAny or settingsCategoryRegistered or legacyCategoryRegistered) or false
end

local optionsBootstrapFrame = CreateFrame("Frame")
optionsBootstrapFrame:RegisterEvent("PLAYER_LOGIN")
optionsBootstrapFrame:RegisterEvent("ADDON_LOADED")
local function onOptionsBootstrap(self, event)
    registerOptionsCategory()

    if (event == "PLAYER_LOGIN") then
        self:UnregisterEvent("PLAYER_LOGIN")
    end

    if (settingsCategoryRegistered) then
        self:UnregisterEvent("ADDON_LOADED")
        self:SetScript("OnEvent", nil)
    end
end
optionsBootstrapFrame:SetScript("OnEvent", function(self, event, ...)
    return safeCall(onOptionsBootstrap, self, event, ...)
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
        if (_G.InterfaceOptionsFrame_Show) then
            pcall(_G.InterfaceOptionsFrame_Show)
        end
        pcall(InterfaceOptionsFrame_OpenToCategory, optionsFrame)
        pcall(InterfaceOptionsFrame_OpenToCategory, optionsFrame)
        return
    end
    print("|cff59f0dcTacoTip:|r Options panel is unavailable on this client. Use /tacotip custom to move the tooltip.")
end

TT.OpenOptionsPanel = openOptionsPanel

local MODERN_OPTION_SLIDER_MIN = -300
local MODERN_OPTION_SLIDER_MAX = 300
local MODERN_OPTION_SLIDER_STEP = 1

local modernOptionsState = {
    built = false,
    controls = {},
    pages = {},
    rootSummary = nil,
    preview = nil,
    previewHealthBar = nil,
    previewPowerBar = nil,
    previewAnchor = nil,
    offsetEditors = {},
    offsetSliders = {}
}

local modernGetConfig
local modernRefreshLockPositionToggle
local modernShowExampleTooltip
local modernWidgetId = 0
local CLIENT_DEFAULT_LOCALE_VALUE = "__client__"

local supportedLocaleEntries = {
    { code = "enUS", text = "English" },
    { code = "deDE", text = "Deutsch" },
    { code = "esES", text = "Español (España)" },
    { code = "esMX", text = "Español (Latinoamérica)" },
    { code = "frFR", text = "Français" },
    { code = "itIT", text = "Italiano" },
    { code = "koKR", text = "한국어" },
    { code = "ptBR", text = "Português (Brasil)" },
    { code = "ruRU", text = "Русский" },
    { code = "zhCN", text = "简体中文" },
    { code = "zhTW", text = "繁體中文" }
}

local function nextModernWidgetName(prefix)
    modernWidgetId = modernWidgetId + 1
    return string.format("TacoTipModern%s%d", prefix, modernWidgetId)
end

local function getSavedLocaleOverride()
    if (TacoTipConfig and TacoTipConfig.locale_override and TacoTipConfig.locale_override ~= "") then
        return TacoTipConfig.locale_override
    end
    return nil
end

local function getLocaleDisplayName(localeCode)
    for _, entry in ipairs(supportedLocaleEntries) do
        if (entry.code == localeCode) then
            return entry.text
        end
    end
    if (localeCode == "enGB") then
        return "English"
    end
    return localeCode or "English"
end

local function buildLocaleDropdownChoices()
    local clientLocaleName = getLocaleDisplayName(GetLocale() or "enUS")
    local choices = {
        {
            value = CLIENT_DEFAULT_LOCALE_VALUE,
            text = string.format(L["OPTIONS_LANGUAGE_CLIENT_DEFAULT"] or "Client default (%s)", clientLocaleName),
            selectedText = string.format(L["OPTIONS_LANGUAGE_CLIENT_DEFAULT"] or "Client default (%s)", clientLocaleName)
        }
    }

    for _, entry in ipairs(supportedLocaleEntries) do
        table.insert(choices, {
            value = entry.code,
            text = entry.text,
            selectedText = entry.text
        })
    end

    return choices
end

local function getSharedMediaLibrary()
    if (LibStub) then
        return LibStub("LibSharedMedia-3.0", true)
    end
    return nil
end

local function sortMediaChoices(choices)
    table.sort(choices, function(a, b)
        return tostring(a.text) < tostring(b.text)
    end)
    return choices
end

local function buildTexturePreviewText(texturePath, label)
    if (not texturePath or texturePath == "" or texturePath == "Interface\\None") then
        return label
    end
    return string.format("|T%s:132:14:0:0|t %s", texturePath, label)
end

function TT:GetTooltipFontChoices()
    local media = getSharedMediaLibrary()
    local seen = {}
    local choices = {}

    for _, entry in ipairs(TT.builtinTooltipFonts) do
        seen[entry.value] = true
        table.insert(choices, { value = entry.value, text = entry.text })
    end

    if (media and media.HashTable) then
        local fontTable = media:HashTable("font") or {}
        for name, path in pairs(fontTable) do
            if (path and not seen[path]) then
                seen[path] = true
                table.insert(choices, { value = path, text = name })
            end
        end
    elseif (media and media.List and media.Fetch) then
        local fontList = media:List("font") or {}
        for _, handle in ipairs(fontList) do
            local path = media:Fetch("font", handle, true)
            if (path and not seen[path]) then
                seen[path] = true
                table.insert(choices, { value = path, text = handle })
            end
        end
    end

    return sortMediaChoices(choices)
end

function TT:GetTooltipStatusBarTextureChoices()
    local media = getSharedMediaLibrary()
    local seen = {}
    local choices = {}

    for _, entry in ipairs(TT.builtinStatusBarTextures) do
        seen[entry.value] = true
        table.insert(choices, { value = entry.value, text = entry.text, menuText = buildTexturePreviewText(entry.value, entry.text) })
    end

    if (media and media.HashTable) then
        local textureTable = media:HashTable("statusbar") or {}
        for name, path in pairs(textureTable) do
            if (path and not seen[path]) then
                seen[path] = true
                table.insert(choices, { value = path, text = name, menuText = buildTexturePreviewText(path, name) })
            end
        end
    end

    return sortMediaChoices(choices)
end

function TT:GetTooltipBackgroundChoices()
    local media = getSharedMediaLibrary()
    local seen = {}
    local choices = {}

    for _, entry in ipairs(TT.builtinTooltipBackgrounds) do
        seen[entry.value] = true
        table.insert(choices, { value = entry.value, text = entry.text, menuText = buildTexturePreviewText(entry.value, entry.text) })
    end

    if (media and media.HashTable) then
        local backgroundTable = media:HashTable("background") or {}
        for name, path in pairs(backgroundTable) do
            if (path and not seen[path]) then
                seen[path] = true
                table.insert(choices, { value = path, text = name, menuText = buildTexturePreviewText(path, name) })
            end
        end
    end

    return sortMediaChoices(choices)
end

function TT:GetTooltipBorderChoices()
    local media = getSharedMediaLibrary()
    local seen = {}
    local choices = {}

    for _, entry in ipairs(TT.builtinTooltipBorders) do
        seen[entry.value] = true
        table.insert(choices, { value = entry.value, text = entry.text, menuText = buildTexturePreviewText(entry.value, entry.text) })
    end

    if (media and media.HashTable) then
        local borderTable = media:HashTable("border") or {}
        for name, path in pairs(borderTable) do
            if (path and not seen[path]) then
                seen[path] = true
                table.insert(choices, { value = path, text = name, menuText = buildTexturePreviewText(path, name) })
            end
        end
    end

    return sortMediaChoices(choices)
end

local function resolveConfiguredMediaValue(choices, configuredValue, fallbackValue)
    if (configuredValue) then
        for _, entry in ipairs(choices) do
            if (entry.value == configuredValue) then
                return configuredValue
            end
        end
    end
    return fallbackValue
end

function TT:GetResolvedTooltipFont()
    return resolveConfiguredMediaValue(self:GetTooltipFontChoices(), TacoTipConfig and TacoTipConfig.tooltip_font, "Fonts\\FRIZQT__.TTF")
end

function TT:GetResolvedTooltipStatusBarTexture()
    return resolveConfiguredMediaValue(self:GetTooltipStatusBarTextureChoices(), TacoTipConfig and TacoTipConfig.tooltip_bar_texture, "Interface\\TargetingFrame\\UI-TargetingFrame-BarFill")
end

function TT:GetResolvedTooltipBackground()
    return resolveConfiguredMediaValue(self:GetTooltipBackgroundChoices(), TacoTipConfig and TacoTipConfig.tooltip_background_texture, "Interface\\Tooltips\\UI-Tooltip-Background")
end

function TT:GetResolvedTooltipBorder()
    return resolveConfiguredMediaValue(self:GetTooltipBorderChoices(), TacoTipConfig and TacoTipConfig.tooltip_border_texture, "Interface\\Tooltips\\UI-Tooltip-Border")
end

local function setFontState(fontString, enabled, enabledFont)
    if (not fontString) then
        return
    end
    fontString:SetFontObject(enabled and (enabledFont or "GameFontHighlight") or "GameFontDisable")
end

local function setDropDownEnabled(dropDown, enabled)
    if (not dropDown) then
        return
    end
    if (enabled) then
        _G.UIDropDownMenu_EnableDropDown(dropDown)
    else
        _G.UIDropDownMenu_DisableDropDown(dropDown)
    end
    setFontState(dropDown.label, enabled, "GameFontNormal")
    setFontState(dropDown.description, enabled, "GameFontHighlightSmall")
end

local function showHoverTooltip(frame, title, text)
    if (not frame or not text or text == "") then
        return
    end
    GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    if (title and title ~= "") then
        GameTooltip:SetText(title, 1, 0.82, 0)
        GameTooltip:AddLine(text, 1, 1, 1, true)
    else
        GameTooltip:SetText(text, 1, 1, 1, true)
    end
    GameTooltip:Show()
end

local function attachHoverTooltip(frame, title, text)
    if (not frame or not text or text == "") then
        return
    end
    if (frame.EnableMouse) then
        frame:EnableMouse(true)
    end
    frame:SetScript("OnEnter", function(self)
        showHoverTooltip(self, title, text)
    end)
    frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

local function createWrappedText(parent, fontObject, width, text)
    local label = parent:CreateFontString(nil, "ARTWORK", fontObject)
    label:SetJustifyH("LEFT")
    label:SetJustifyV("TOP")
    label:SetWidth(width)
    label:SetText(text)
    return label
end

local function createSectionHeader(parent, text, description, width)
    local header = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    header:SetJustifyH("LEFT")
    header:SetText(text)

    local desc
    if (description and description ~= "") then
        desc = createWrappedText(parent, "GameFontHighlightSmall", width, description)
    end

    return header, desc
end

local function createOptionsCheckbox(parent, globalName, label, tooltipDescription, onClick)
    globalName = globalName or nextModernWidgetName("Check")
    local check = CreateFrame("CheckButton", globalName, parent, "InterfaceOptionsCheckButtonTemplate")
    check.label = _G[check:GetName() .. "Text"]
    check.label:SetText(label)
    if (tooltipDescription and tooltipDescription ~= "") then
        check.tooltipText = label
        check.tooltipRequirement = tooltipDescription
    end
    check:SetScript("OnClick", function(self)
        onClick(self, self:GetChecked() and true or false)
    end)
    check.SetDisabled = function(self, disabled)
        if (disabled) then
            self:Disable()
        else
            self:Enable()
        end
        setFontState(self.label, not disabled)
    end
    return check
end

local function createOptionsButton(parent, globalName, text, width, height, onClick, tooltipDescription)
    local button = CreateFrame("Button", globalName, parent, "UIPanelButtonTemplate")
    button:SetSize(width, height)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    attachHoverTooltip(button, text, tooltipDescription)
    return button
end

local function createOptionsDropdown(parent, globalName, label, description, values, onValueChanged)
    globalName = globalName or nextModernWidgetName("Dropdown")
    local dropDown = CreateFrame("Frame", globalName, parent, "UIDropDownMenuTemplate")
    local parentStrata = (parent and parent.GetFrameStrata and parent:GetFrameStrata()) or "MEDIUM"
    dropDown:SetFrameStrata(parentStrata)
    dropDown:SetFrameLevel(clampFrameLevel((parent and parent.GetFrameLevel and parent:GetFrameLevel() or 0) + 8))
    if (dropDown.EnableMouse) then
        dropDown:EnableMouse(true)
    end
    dropDown.values = values or {}
    dropDown.label = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    dropDown.label:SetJustifyH("LEFT")
    dropDown.label:SetText(label or "")
    dropDown.description = description and createWrappedText(parent, "GameFontHighlightSmall", 280, description) or nil

    _G.UIDropDownMenu_SetWidth(dropDown, 240)
    _G.UIDropDownMenu_Initialize(dropDown, function(frame, level, menuList)
        local function buildItems()
            for _, option in ipairs(frame.values or values or {}) do
                local info = _G.UIDropDownMenu_CreateInfo()
                info.text = option.menuText or option.text or ""
                info.value = option.value
                info.checked = (frame.selectedValue == option.value)
                info.func = function(button)
                    local function applyChoice()
                        frame:SetValue(button.value)
                        if (onValueChanged) then
                            onValueChanged(button.value)
                        end
                    end
                    safeCall(applyChoice)
                end
                if (option.tooltip) then
                    info.tooltipTitle = option.text
                    info.tooltipText = option.tooltip
                    info.tooltipOnButton = 1
                end
                _G.UIDropDownMenu_AddButton(info)
            end
        end
        safeCall(buildItems)
    end)

    dropDown.SetValues = function(self, newValues)
        self.values = newValues or {}
    end

    dropDown.SetValue = function(self, value)
        self.selectedValue = value
        _G.UIDropDownMenu_SetSelectedValue(self, value)
        for _, option in ipairs(self.values or values or {}) do
            if (option.value == value) then
                _G.UIDropDownMenu_SetText(self, option.selectedText or option.text or option.menuText or "")
                return
            end
        end
        local firstValue = (self.values or values or {})[1]
        _G.UIDropDownMenu_SetText(self, firstValue and (firstValue.selectedText or firstValue.text or firstValue.menuText) or "")
    end

    dropDown.SetDisabled = function(self, disabled)
        setDropDownEnabled(self, not disabled)
    end

    attachHoverTooltip(dropDown, label, description)
    attachHoverTooltip(dropDown.label, label, description)
    attachHoverTooltip(dropDown.description, label, description)

    return dropDown
end

local function createOptionsEditBox(parent, globalName, width, onCommit, tooltipTitle, tooltipDescription)
    local editBox = CreateFrame("EditBox", globalName, parent, "InputBoxTemplate")
    editBox:SetAutoFocus(false)
    editBox:SetSize(width, 24)
    editBox:SetMaxLetters(8)
    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        if (self.lastValue ~= nil) then
            self:SetText(tostring(self.lastValue))
        end
    end)
    editBox:SetScript("OnEnterPressed", function(self)
        local value = tonumber(self:GetText())
        if (value ~= nil) then
            value = math.floor(value + (value < 0 and -0.5 or 0.5))
            self.lastValue = value
            onCommit(value)
        else
            self:SetText(tostring(self.lastValue or 0))
        end
        self:ClearFocus()
    end)
    editBox:SetScript("OnEditFocusLost", function(self)
        local value = tonumber(self:GetText())
        if (value ~= nil) then
            value = math.floor(value + (value < 0 and -0.5 or 0.5))
            self.lastValue = value
            onCommit(value)
        else
            self:SetText(tostring(self.lastValue or 0))
        end
    end)
    editBox.SetDisabled = function(self, disabled)
        if (disabled) then
            self:Disable()
        else
            self:Enable()
        end
    end
    attachHoverTooltip(editBox, tooltipTitle, tooltipDescription)
    return editBox
end

local function createOptionsSlider(parent, globalName, label, tooltipDescription, onValueChanged, minValue, maxValue, step)
    globalName = globalName or nextModernWidgetName("Slider")
    local slider = CreateFrame("Slider", globalName, parent, "OptionsSliderTemplate")
    minValue = minValue or MODERN_OPTION_SLIDER_MIN
    maxValue = maxValue or MODERN_OPTION_SLIDER_MAX
    step = step or MODERN_OPTION_SLIDER_STEP
    slider:SetMinMaxValues(minValue, maxValue)
    slider:SetValueStep(step)
    if (slider.SetObeyStepOnDrag) then
        slider:SetObeyStepOnDrag(true)
    end
    slider:SetWidth(180)
    slider:EnableMouseWheel(true)
    slider.label = _G[slider:GetName() .. "Text"]
    slider.low = _G[slider:GetName() .. "Low"]
    slider.high = _G[slider:GetName() .. "High"]
    slider.label:SetText(label)
    slider.low:SetText(tostring(minValue))
    slider.high:SetText(tostring(maxValue))
    slider.valueText = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + (value < 0 and -0.5 or 0.5))
        self.valueText:SetText(tostring(value))
        if (not self._refreshing) then
            onValueChanged(value)
        end
    end)
    slider:SetScript("OnMouseWheel", function(self, delta)
        if (not self:IsEnabled()) then
            return
        end
        local currentValue = self:GetValue()
        local stepValue = self:GetValueStep() or step or 1
        local nextValue = currentValue + (delta * stepValue)
        local minSliderValue, maxSliderValue = self:GetMinMaxValues()
        if (nextValue < minSliderValue) then
            nextValue = minSliderValue
        elseif (nextValue > maxSliderValue) then
            nextValue = maxSliderValue
        end
        self:SetValue(nextValue)
    end)
    slider.SetDisabled = function(self, disabled)
        if (disabled) then
            self:Disable()
        else
            self:Enable()
        end
        setFontState(self.label, not disabled, "GameFontNormal")
        setFontState(self.valueText, not disabled, "GameFontHighlightSmall")
    end
    slider.SetValueSilently = function(self, value)
        self._refreshing = true
        self:SetValue(value)
        self._refreshing = false
        self.valueText:SetText(tostring(value))
    end
    attachHoverTooltip(slider, label, tooltipDescription)
    attachHoverTooltip(slider.label, label, tooltipDescription)
    attachHoverTooltip(slider.valueText, label, tooltipDescription)
    return slider
end

local function openClassicColorPicker(initialR, initialG, initialB, onChanged)
    local colorPickerFrame = _G.ColorPickerFrame
    if (not colorPickerFrame) then
        return
    end

    local originalR, originalG, originalB = initialR or 1, initialG or 1, initialB or 1
    local function applyCurrentColor()
        local r, g, b = colorPickerFrame:GetColorRGB()
        onChanged(r, g, b)
    end

    local function cancelColor()
        onChanged(originalR, originalG, originalB)
    end

    if (colorPickerFrame.SetupColorPickerAndShow) then
        colorPickerFrame:SetupColorPickerAndShow({
            r = originalR,
            g = originalG,
            b = originalB,
            hasOpacity = false,
            swatchFunc = applyCurrentColor,
            cancelFunc = cancelColor
        })
        return
    end

    pcall(rawset, colorPickerFrame, "hasOpacity", false)
    pcall(rawset, colorPickerFrame, "opacity", 1)
    pcall(rawset, colorPickerFrame, "func", applyCurrentColor)
    pcall(rawset, colorPickerFrame, "opacityFunc", nil)
    pcall(rawset, colorPickerFrame, "cancelFunc", cancelColor)
    colorPickerFrame:SetColorRGB(originalR, originalG, originalB)
    colorPickerFrame:Hide()
    colorPickerFrame:Show()
end

local function createColorSwatchControl(parent, globalName, label, description, onColorChanged)
    globalName = globalName or nextModernWidgetName("Color")

    local control = CreateFrame("Frame", globalName, parent)
    control:SetSize(196, 72)

    control.label = control:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    control.label:SetPoint("TOPLEFT", control, "TOPLEFT", 0, 0)
    control.label:SetJustifyH("LEFT")
    control.label:SetText(label)

    control.button = CreateFrame("Button", nil, control, "UIPanelButtonTemplate")
    control.button:SetSize(102, 22)
    control.button:SetPoint("TOPLEFT", control.label, "BOTTOMLEFT", 0, -4)
    control.button:SetText(L["OPTIONS_PICK_COLOR"] or "Choose color")

    control.swatchBorder = control:CreateTexture(nil, "BORDER")
    control.swatchBorder:SetTexture("Interface\\Buttons\\WHITE8X8")
    control.swatchBorder:SetVertexColor(0, 0, 0, 1)
    control.swatchBorder:SetSize(26, 26)
    control.swatchBorder:SetPoint("LEFT", control.button, "RIGHT", 8, 0)

    control.swatch = control:CreateTexture(nil, "ARTWORK")
    control.swatch:SetTexture("Interface\\Buttons\\WHITE8X8")
    control.swatch:SetSize(20, 20)
    control.swatch:SetPoint("CENTER", control.swatchBorder, "CENTER", 0, 0)

    control.description = createWrappedText(control, "GameFontHighlightSmall", 196, description or "")
    control.description:SetPoint("TOPLEFT", control.button, "BOTTOMLEFT", 0, -4)

    control.SetColor = function(self, r, g, b)
        self.r, self.g, self.b = r or 1, g or 1, b or 1
        if (self.swatch.SetColorTexture) then
            self.swatch:SetColorTexture(self.r, self.g, self.b, 1)
        else
            self.swatch:SetVertexColor(self.r, self.g, self.b, 1)
        end
    end

    control.SetDisabled = function(self, disabled)
        if (disabled) then
            self.button:Disable()
        else
            self.button:Enable()
        end
        setFontState(self.label, not disabled, "GameFontNormal")
        setFontState(self.description, not disabled, "GameFontHighlightSmall")
    end

    control.button:SetScript("OnClick", function()
        openClassicColorPicker(control.r, control.g, control.b, function(r, g, b)
            control:SetColor(r, g, b)
            onColorChanged(r, g, b)
        end)
    end)

    attachHoverTooltip(control.button, label, description)
    attachHoverTooltip(control.label, label, description)
    attachHoverTooltip(control.description, label, description)

    return control
end

local function createScrollPage(frame)
    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -12)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 12)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetPoint("TOPLEFT")
    content:SetSize(1, 1)
    scrollFrame:SetScrollChild(content)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnSizeChanged", function(self, width)
        content:SetWidth((width or self:GetWidth()) - 24)
    end)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local stepValue = 32
        local nextOffset = self:GetVerticalScroll() - (delta * stepValue)
        local maxOffset = self:GetVerticalScrollRange() or 0
        if (nextOffset < 0) then
            nextOffset = 0
        elseif (nextOffset > maxOffset) then
            nextOffset = maxOffset
        end
        self:SetVerticalScroll(nextOffset)
    end)

    local function proxyWheel(_, delta)
        scrollFrame:GetScript("OnMouseWheel")(scrollFrame, delta)
    end

    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", proxyWheel)
    content:EnableMouseWheel(true)
    content:SetScript("OnMouseWheel", proxyWheel)

    return scrollFrame, content
end

local function createPageBuilder(parent, startX, startY)
    local builder = {
        parent = parent,
        x = startX or 16,
        y = startY or -16,
        maxBottom = 0
    }

    function builder:AddSpacing(amount)
        self.y = self.y - amount
    end

    function builder:AddAnchor(frame, height, offsetX)
        frame:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.x + (offsetX or 0), self.y)
        self.y = self.y - height
        if (-self.y > self.maxBottom) then
            self.maxBottom = -self.y
        end
    end

    function builder:Finalize(padding)
        local usedBottom = math.max(self.maxBottom, -self.y)
        self.parent:SetHeight(usedBottom + (padding or 48))
    end

    return builder
end

local function layoutDropdownControl(parent, control, topY, widthPadding)
    control.label:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, topY)
    control:SetPoint("TOPLEFT", control.label, "BOTTOMLEFT", -16, -2)

    local consumedHeight = 46
    if (control.description) then
        control.description:SetPoint("TOPLEFT", control, "BOTTOMLEFT", 20, -2)
        consumedHeight = consumedHeight + control.description:GetStringHeight() + 8
    end

    return consumedHeight + (widthPadding or 8)
end

local modernAnchorOptions = {
    { value = "TOPLEFT", text = L["OPTIONS_ANCHOR_TOPLEFT"] or "Top Left", tooltip = L["OPTIONS_ANCHOR_TOPLEFT_DESC"] },
    { value = "TOPRIGHT", text = L["OPTIONS_ANCHOR_TOPRIGHT"] or "Top Right", tooltip = L["OPTIONS_ANCHOR_TOPRIGHT_DESC"] },
    { value = "BOTTOMLEFT", text = L["OPTIONS_ANCHOR_BOTTOMLEFT"] or "Bottom Left", tooltip = L["OPTIONS_ANCHOR_BOTTOMLEFT_DESC"] },
    { value = "BOTTOMRIGHT", text = L["OPTIONS_ANCHOR_BOTTOMRIGHT"] or "Bottom Right", tooltip = L["OPTIONS_ANCHOR_BOTTOMRIGHT_DESC"] },
    { value = "CENTER", text = L["OPTIONS_ANCHOR_CENTER"] or "Center", tooltip = L["OPTIONS_ANCHOR_CENTER_DESC"] }
}

local modernStyleOptions = {
    { value = 1, text = L["FULL"], tooltip = L["Always FULL"] },
    { value = 2, text = L["COMPACT/FULL"], tooltip = L["Default COMPACT, hold SHIFT for FULL"] },
    { value = 3, text = L["COMPACT"], tooltip = L["Always COMPACT"] },
    { value = 4, text = L["MINI/FULL"], tooltip = L["Default MINI, hold SHIFT for FULL"] },
    { value = 5, text = L["MINI"], tooltip = L["Always MINI"] }
}

local function refreshOverlayPositions()
    if (PersonalGearScore and PersonalGearScore.RefreshPosition) then PersonalGearScore:RefreshPosition() end
    if (PersonalGearScoreText and PersonalGearScoreText.RefreshPosition) then PersonalGearScoreText:RefreshPosition() end
    if (PersonalAvgItemLvl and PersonalAvgItemLvl.RefreshPosition) then PersonalAvgItemLvl:RefreshPosition() end
    if (PersonalAvgItemLvlText and PersonalAvgItemLvlText.RefreshPosition) then PersonalAvgItemLvlText:RefreshPosition() end
    if (InspectGearScore and InspectGearScore.RefreshPosition) then InspectGearScore:RefreshPosition() end
    if (InspectGearScoreText and InspectGearScoreText.RefreshPosition) then InspectGearScoreText:RefreshPosition() end
    if (InspectAvgItemLvl and InspectAvgItemLvl.RefreshPosition) then InspectAvgItemLvl:RefreshPosition() end
    if (InspectAvgItemLvlText and InspectAvgItemLvlText.RefreshPosition) then InspectAvgItemLvlText:RefreshPosition() end
    if (TT.RefreshCharacterFrame and PaperDollFrame and PaperDollFrame:IsShown()) then TT:RefreshCharacterFrame() end
    if (TT.RefreshInspectFrame and InspectFrame and InspectFrame:IsShown()) then TT:RefreshInspectFrame() end
end

modernShowExampleTooltip = function()
    local tooltip = modernOptionsState.preview
    local previewAnchor = modernOptionsState.previewAnchor
    if (not tooltip or not previewAnchor) then
        return
    end

    tooltip:SetOwner(previewAnchor, "ANCHOR_NONE")
    tooltip:ClearLines()
    tooltip:ClearAllPoints()
    tooltip:SetPoint("TOPLEFT", previewAnchor, "TOPLEFT", 0, 0)

    local classc = CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS["ROGUE"] or RAID_CLASS_COLORS["ROGUE"]
    local name_r = TacoTipConfig.color_class and classc and classc.r or 0
    local name_g = TacoTipConfig.color_class and classc and classc.g or 0.6
    local name_b = TacoTipConfig.color_class and classc and classc.b or 0.1
    local playerTitle = TacoTipConfig.show_titles and L[" the Kingslayer"] or ""
    local iconSuffix = ""
    if (TacoTipConfig.show_team) then
        iconSuffix = iconSuffix .. " " .. HORDE_ICON
    end
    if (TacoTipConfig.show_pvp_icon) then
        iconSuffix = iconSuffix .. " " .. PVP_FLAG_ICON
    end
    tooltip:AddLine(string.format("|cFF%02x%02x%02xAcidBomb%s%s|r", name_r*255, name_g*255, name_b*255, playerTitle, iconSuffix))

    if (TacoTipConfig.show_guild_name) then
        if (TacoTipConfig.show_guild_rank) then
            if (TacoTipConfig.guild_rank_alt_style) then
                tooltip:AddLine("|cFF40FB40<Drunken Wrath> (Officer)|r")
            else
                tooltip:AddLine(string.format("|cFF40FB40"..L["FORMAT_GUILD_RANK_1"].."|r", "Officer", "Drunken Wrath"))
            end
        else
            tooltip:AddLine("|cFF40FB40<Drunken Wrath>|r")
        end
    end

    if (TacoTipConfig.color_class) then
        tooltip:AddLine(string.format("%s 80 %s |cFF%02x%02x%02x%s|r (%s)", L["Level"], L["Undead"], name_r*255, name_g*255, name_b*255, LOCALIZED_CLASS_NAMES_MALE["ROGUE"], L["Player"]), 1, 1, 1)
    else
        tooltip:AddLine(string.format("%s 80 %s %s (%s)", L["Level"], L["Undead"], LOCALIZED_CLASS_NAMES_MALE["ROGUE"], L["Player"]), 1, 1, 1)
    end

    if (not TacoTipConfig.show_pvp_icon) then
        tooltip:AddLine("PvP", 1, 1, 1)
    end

    local wideStyle = (TacoTipConfig.tip_style == 1 or ((TacoTipConfig.tip_style == 2 or TacoTipConfig.tip_style == 4) and IsShiftKeyDown()))
    local miniStyle = (not wideStyle and (TacoTipConfig.tip_style == 4 or TacoTipConfig.tip_style == 5))

    if (TacoTipConfig.show_target) then
        if (wideStyle) then
            tooltip:AddDoubleLine(L["Target"]..":", L["None"], NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, GRAY_FONT_COLOR.r, GRAY_FONT_COLOR.g, GRAY_FONT_COLOR.b)
        else
            tooltip:AddLine(L["Target"]..": |cFF808080"..L["None"].."|r")
        end
    end

    if (TacoTipConfig.show_talents) then
        local primarySpecText = (TT.GetFormattedSpecializationText and TT:GetFormattedSpecializationText("ROGUE", 1, 51, 18, 2)) or (CI:GetSpecializationName("ROGUE", 1, true).." [51/18/2]")
        local secondarySpecText = (TT.GetFormattedSpecializationText and TT:GetFormattedSpecializationText("ROGUE", 3, 14, 3, 54)) or (CI:GetSpecializationName("ROGUE", 3, true).." [14/3/54]")
        if (wideStyle) then
            tooltip:AddDoubleLine(L["Talents"]..":", primarySpecText, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, 1, 1, 1)
            tooltip:AddDoubleLine(" ", secondarySpecText, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, 1, 1, 1)
        else
            tooltip:AddLine(L["Talents"]..": "..primarySpecText)
        end
    end

    local miniText = ""
    if (TacoTipConfig.show_gs_player) then
        local gs_r, gs_g, gs_b = GearScore:GetQuality(6054)
        if (wideStyle) then
            tooltip:AddDoubleLine("GearScore: 6054", "(iLvl: 264)", gs_r, gs_g, gs_b, gs_r, gs_g, gs_b)
        elseif (miniStyle) then
            miniText = string.format("|cFF%02x%02x%02xGS: 6054  L: 264|r  ", gs_r*255, gs_g*255, gs_b*255)
        else
            tooltip:AddLine("GearScore: 6054", gs_r, gs_g, gs_b)
            tooltip:AddLine("iLvl: 264", gs_r, gs_g, gs_b)
        end
    end

    if (isPawnLoaded and TacoTipConfig.show_pawn_player) then
        local pcOk, pcResult = pcall(PawnGetScaleColor, "\"Classic\":ROGUE1", true)
        local specColor = pcOk and pcResult or "|cffffffff"
        if (wideStyle) then
            tooltip:AddDoubleLine(string.format("Pawn: %s1234.56|r", specColor), string.format("%s(%s)|r", specColor, CI:GetSpecializationName("ROGUE", 1, true)), 1, 1, 1, 1, 1, 1)
        elseif (miniStyle) then
            miniText = miniText .. string.format("P: %s1234.5|r", specColor)
        else
            tooltip:AddLine(string.format("Pawn: %s1234.56 (%s)|r", specColor, CI:GetSpecializationName("ROGUE", 1, true)), 1, 1, 1)
        end
    end

    if (miniText ~= "") then
        tooltip:AddLine(miniText, 1, 1, 1)
    end

    tooltip:Show()

    if (TT and TT.ApplyTooltipAppearance) then
        TT:ApplyTooltipAppearance(tooltip, "player")
    end

    if (modernOptionsState.previewHealthBar) then
        local barTexture = TacoTipConfig.tooltip_bar_texture or "Interface\\TargetingFrame\\UI-TargetingFrame-BarFill"
        modernOptionsState.previewHealthBar:SetStatusBarTexture(barTexture)
        modernOptionsState.previewPowerBar:SetStatusBarTexture(barTexture)
        if (TacoTipConfig.show_hp_bar) then
            modernOptionsState.previewHealthBar:Show()
            modernOptionsState.previewPowerBar:SetPoint("TOPLEFT", tooltip, "BOTTOMLEFT", 2, -9)
            modernOptionsState.previewPowerBar:SetPoint("TOPRIGHT", tooltip, "BOTTOMRIGHT", -2, -9)
        else
            modernOptionsState.previewHealthBar:Hide()
            modernOptionsState.previewPowerBar:SetPoint("TOPLEFT", tooltip, "BOTTOMLEFT", 2, -1)
            modernOptionsState.previewPowerBar:SetPoint("TOPRIGHT", tooltip, "BOTTOMRIGHT", -2, -1)
        end

        if (TacoTipConfig.show_power_bar) then
            modernOptionsState.previewPowerBar:Show()
        else
            modernOptionsState.previewPowerBar:Hide()
        end
    end
end

local function buildRootPage()
    if (modernOptionsState.pages.rootBuilt) then
        return
    end

    local panel = optionsFrame
    local controls = modernOptionsState.controls
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(addOnTitle .. " v" .. addOnVersion)

    local description = createWrappedText(panel, "GameFontHighlightSmall", 620, L["OPTIONS_ROOT_DESCRIPTION"] or L["TEXT_OPT_DESC"])
    description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)

    local quickActions = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    quickActions:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -18)
    quickActions:SetText(L["OPTIONS_ROOT_QUICK_ACTIONS"] or "Quick Actions")

    local openMoverButton = createOptionsButton(panel, nil, L["OPTIONS_OPEN_TOOLTIP_MOVER"] or L["Mover"], 180, 24, function()
        showTooltipMover()
    end, L["OPTIONS_OPEN_TOOLTIP_MOVER_DESC"] or "Show the live tooltip mover so you can drag and save a custom tooltip position.")
    openMoverButton:SetPoint("TOPLEFT", quickActions, "BOTTOMLEFT", 0, -8)

    local resetButton = createOptionsButton(panel, nil, L["Reset configuration"], 180, 24, function()
        resetCfg()
        if (TT.RefreshOptionsUI) then
            TT:RefreshOptionsUI()
        end
    end, L["OPTIONS_RESET_CONFIGURATION_DESC"] or "Restore TacoTip settings to their defaults, including tooltip appearance and overlay positions.")
    resetButton:SetPoint("LEFT", openMoverButton, "RIGHT", 12, 0)

    controls.rootStyleChoice = createOptionsDropdown(panel, nil, L["Tooltip Style"], L["OPTIONS_TOOLTIP_STYLE_DESC"] or "Choose how much detail TacoTip shows by default. Hold Shift on hybrid styles to preview the expanded view.", modernStyleOptions, function(value)
        TacoTipConfig.tip_style = value
        if (TT and TT.RefreshOptionsUI) then
            TT:RefreshOptionsUI()
        end
    end)
    controls.rootStyleChoice.label:SetPoint("TOPLEFT", openMoverButton, "BOTTOMLEFT", 0, -18)
    controls.rootStyleChoice:SetPoint("TOPLEFT", controls.rootStyleChoice.label, "BOTTOMLEFT", -16, -2)
    if (controls.rootStyleChoice.description) then
        controls.rootStyleChoice.description:ClearAllPoints()
        controls.rootStyleChoice.description:SetPoint("TOPLEFT", controls.rootStyleChoice.label, "BOTTOMLEFT", 0, -44)
    end

    modernOptionsState.rootSummary = createWrappedText(panel, "GameFontHighlightSmall", 620, "")
    modernOptionsState.rootSummary:SetPoint("TOPLEFT", controls.rootStyleChoice, "BOTTOMLEFT", 16, -12)

    controls.rootLanguage = createOptionsDropdown(panel, nil, L["OPTIONS_LANGUAGE_LABEL"] or "Addon language", L["OPTIONS_LANGUAGE_DESC"] or "Use your game client's locale by default, or choose another supported TacoTip locale. Reload the UI after changing this setting.", buildLocaleDropdownChoices(), function(value)
        if (value == CLIENT_DEFAULT_LOCALE_VALUE) then
            TacoTipConfig.locale_override = nil
        else
            TacoTipConfig.locale_override = value
        end
        print("|cff59f0dcTacoTip:|r " .. (L["OPTIONS_LANGUAGE_RELOAD_HINT"] or "Language preference saved. Reload the UI to apply it."))
        if (TT.RefreshOptionsUI) then
            TT:RefreshOptionsUI()
        end
    end)
    controls.rootLanguage.label:SetPoint("TOPLEFT", modernOptionsState.rootSummary, "BOTTOMLEFT", 0, -18)
    controls.rootLanguage:SetPoint("TOPLEFT", controls.rootLanguage.label, "BOTTOMLEFT", -16, -2)
    if (controls.rootLanguage.description) then
        controls.rootLanguage.description:ClearAllPoints()
        controls.rootLanguage.description:SetPoint("TOPLEFT", controls.rootLanguage.label, "BOTTOMLEFT", 0, -44)
    end

    local behaviorHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    if (controls.rootLanguage.description) then
        behaviorHeader:SetPoint("TOPLEFT", controls.rootLanguage.description, "BOTTOMLEFT", 0, -14)
    else
        behaviorHeader:SetPoint("TOPLEFT", controls.rootLanguage, "BOTTOMLEFT", 16, -14)
    end
    behaviorHeader:SetText(L["OPTIONS_ROOT_BEHAVIOR_HEADER"] or "Behavior & client settings")

    controls.rootHideInCombat = createOptionsCheckbox(panel, nil, L["OPTIONS_HIDE_IN_COMBAT_LABEL"] or "Suppress inspection details in combat", L["OPTIONS_HIDE_IN_COMBAT_DESC"] or "Skips TacoTip's talents and GearScore-style player additions while you are in combat.", function(_, value)
        TacoTipConfig.hide_in_combat = value
    end)
    controls.rootHideInCombat:SetPoint("TOPLEFT", behaviorHeader, "BOTTOMLEFT", -2, -8)

    controls.rootUberTips = createOptionsCheckbox(panel, nil, L["Enhanced Tooltips"], L["TEXT_OPT_UBERTIPS"], function(_, value)
        SetCVar("UberTooltips", value and "1" or "0")
    end)
    controls.rootUberTips:SetPoint("TOPLEFT", behaviorHeader, "BOTTOMLEFT", 310, -8)

    controls.rootChatClassColors = createOptionsCheckbox(panel, nil, L["Chat Class Colors"], L["Color names by class in chat windows"], function(_, value)
        SetCVar("chatClassColorOverride", value and "0" or "1")
    end)
    controls.rootChatClassColors:SetPoint("TOPLEFT", controls.rootHideInCombat, "BOTTOMLEFT", 0, -8)

    controls.rootShowAchievementPoints = createOptionsCheckbox(panel, nil, L["Show Achievement Points"], L["OPTIONS_ACHIEVEMENT_DESC"] or "Only available on Wrath Classic clients where achievement data exists.", function(_, value)
        TacoTipConfig.show_achievement_points = value
    end)
    controls.rootShowAchievementPoints:SetPoint("TOPLEFT", controls.rootUberTips, "BOTTOMLEFT", 0, -8)

    panel.Refresh = function()
        local tooltipMode = TacoTipConfig.anchor_mouse and (L["OPTIONS_STATUS_MOUSE_ANCHOR"] or "Anchored to the mouse cursor") or (TacoTipConfig.custom_pos and (L["OPTIONS_STATUS_CUSTOM_POSITION"] or "Using a saved custom tooltip position") or (L["OPTIONS_STATUS_DEFAULT_POSITION"] or "Using Blizzard default tooltip placement"))
        local localeSummary = getSavedLocaleOverride() and getLocaleDisplayName(getSavedLocaleOverride()) or string.format(L["OPTIONS_LANGUAGE_CLIENT_DEFAULT"] or "Client default (%s)", getLocaleDisplayName(GetLocale() or "enUS"))
        local lines = {
            L["OPTIONS_ROOT_PAGE_HINT"] or "Use the child pages in the AddOns tree to configure TacoTip.",
            "• " .. string.format(L["OPTIONS_STATUS_LANGUAGE"] or "Addon language: %s.", localeSummary),
            "• " .. tooltipMode,
            "• " .. (TacoTipConfig.show_gs_character and (L["OPTIONS_STATUS_CHARACTER_GS_ON"] or "Character and inspect GearScore overlays are enabled") or (L["OPTIONS_STATUS_CHARACTER_GS_OFF"] or "Character and inspect GearScore overlays are disabled")),
            "• " .. (TacoTipConfig.show_avg_ilvl and (L["OPTIONS_STATUS_CHARACTER_ILVL_ON"] or "Average item level overlays are enabled") or (L["OPTIONS_STATUS_CHARACTER_ILVL_OFF"] or "Average item level overlays are disabled")),
            "• " .. (TacoTipConfig.unlock_info_position and (L["OPTIONS_STATUS_OVERLAYS_UNLOCKED"] or "Overlay drag movers are unlocked") or (L["OPTIONS_STATUS_OVERLAYS_LOCKED"] or "Overlay drag movers are locked"))
        }
        modernOptionsState.rootSummary:SetText(table.concat(lines, "\n"))
        controls.rootLanguage:SetValues(buildLocaleDropdownChoices())
        controls.rootLanguage:SetValue(getSavedLocaleOverride() or CLIENT_DEFAULT_LOCALE_VALUE)
        controls.rootStyleChoice:SetValue(TacoTipConfig.tip_style or 2)
        controls.rootHideInCombat:SetChecked(TacoTipConfig.hide_in_combat)
        controls.rootUberTips:SetChecked(GetCVar("UberTooltips") == "1")
        controls.rootChatClassColors:SetChecked(GetCVar("chatClassColorOverride") == "0")
        if (CI:IsWotlk()) then
            controls.rootShowAchievementPoints:SetChecked(TacoTipConfig.show_achievement_points)
            controls.rootShowAchievementPoints:SetDisabled(false)
        else
            TacoTipConfig.show_achievement_points = false
            controls.rootShowAchievementPoints:SetChecked(false)
            controls.rootShowAchievementPoints:SetDisabled(true)
        end
    end

    modernOptionsState.pages.rootBuilt = true
end

local function buildTooltipsPage()
    if (modernOptionsState.pages.tooltipsBuilt) then
        return
    end

    local panel = optionsPages.tooltips
    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -12)
    scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, 12)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local stepValue = 32
        local nextOffset = self:GetVerticalScroll() - (delta * stepValue)
        local maxOffset = self:GetVerticalScrollRange() or 0
        if (nextOffset < 0) then
            nextOffset = 0
        elseif (nextOffset > maxOffset) then
            nextOffset = maxOffset
        end
        self:SetVerticalScroll(nextOffset)
    end)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetPoint("TOPLEFT")
    content:SetSize(1, 1)
    scrollFrame:SetScrollChild(content)
    scrollFrame:SetScript("OnSizeChanged", function(self, width)
        content:SetWidth((width or self:GetWidth()) - 24)
    end)

    local function proxyTooltipsWheel(_, delta)
        scrollFrame:GetScript("OnMouseWheel")(scrollFrame, delta)
    end

    panel:EnableMouseWheel(true)
    panel:SetScript("OnMouseWheel", proxyTooltipsWheel)
    content:EnableMouseWheel(true)
    content:SetScript("OnMouseWheel", proxyTooltipsWheel)

    local builder = createPageBuilder(content, 16, -16)
    local header, headerDesc = createSectionHeader(content, L["OPTIONS_PAGE_TOOLTIPS"] or "Tooltips", L["OPTIONS_TOOLTIPS_PAGE_DESC"] or "Tune the information TacoTip adds to player and item tooltips.", 360)
    builder:AddAnchor(header, 24)
    if (headerDesc) then
        builder:AddAnchor(headerDesc, headerDesc:GetStringHeight() + 8)
    end

    local controls = modernOptionsState.controls
    controls.styleChoice = createOptionsDropdown(content, nil, L["Tooltip Style"], L["OPTIONS_TOOLTIP_STYLE_DESC"] or "Choose how much detail TacoTip shows by default. Hold Shift on hybrid styles to preview the expanded view.", modernStyleOptions, function(value)
        TacoTipConfig.tip_style = value
        modernShowExampleTooltip()
    end)
    builder.y = builder.y - layoutDropdownControl(content, controls.styleChoice, builder.y, 12)

    local unitHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    unitHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 16, builder.y)
    unitHeader:SetText(L["OPTIONS_SECTION_UNIT_TOOLTIPS"] or "Unit tooltip content")
    builder.y = builder.y - 24

    controls.useClassColors = createOptionsCheckbox(content, nil, L["Class Color"], L["Color class names in tooltips"], function(_, value) TacoTipConfig.color_class = value; modernShowExampleTooltip() end)
    controls.useClassColors:SetPoint("TOPLEFT", content, "TOPLEFT", 14, builder.y)
    controls.showTitles = createOptionsCheckbox(content, nil, L["Title"], L["Show player's title in tooltips"], function(_, value) TacoTipConfig.show_titles = value; modernShowExampleTooltip() end)
    controls.showTitles:SetPoint("TOPLEFT", content, "TOPLEFT", 234, builder.y)
    builder.y = builder.y - 30

    controls.showGuildNames = createOptionsCheckbox(content, nil, L["Guild Name"], L["Show guild name in tooltips"], function(_, value) TacoTipConfig.show_guild_name = value; modernGetConfig(); modernShowExampleTooltip() end)
    controls.showGuildNames:SetPoint("TOPLEFT", content, "TOPLEFT", 14, builder.y)
    controls.showGuildRanks = createOptionsCheckbox(content, nil, L["Guild Rank"], L["Show guild rank in tooltips"], function(_, value) TacoTipConfig.show_guild_rank = value; modernGetConfig(); modernShowExampleTooltip() end)
    controls.showGuildRanks:SetPoint("TOPLEFT", content, "TOPLEFT", 234, builder.y)
    builder.y = builder.y - 30

    controls.guildRankStyleChoice = createOptionsDropdown(content, nil, L["Style"], L["OPTIONS_GUILD_STYLE_DESC"] or "Choose how TacoTip formats guild rank when both guild name and guild rank are shown.", {
        { value = 1, text = string.format(L["OPTIONS_GUILD_STYLE_ONE"] or L["FORMAT_GUILD_RANK_1"], L["Rank"], L["Guild"]) },
        { value = 2, text = L["OPTIONS_GUILD_STYLE_TWO"] or string.format("<%s> (%s)", L["Guild"], L["Rank"]) }
    }, function(value)
        TacoTipConfig.guild_rank_alt_style = (value == 2)
        modernShowExampleTooltip()
    end)
    builder.y = builder.y - layoutDropdownControl(content, controls.guildRankStyleChoice, builder.y)

    controls.showTalents = createOptionsCheckbox(content, nil, L["Talents"], L["Show talents and specialization in tooltips"], function(_, value) TacoTipConfig.show_talents = value; modernShowExampleTooltip() end)
    controls.showTalents:SetPoint("TOPLEFT", content, "TOPLEFT", 14, builder.y)
    controls.showTarget = createOptionsCheckbox(content, nil, L["Target"], L["Show unit's target in tooltips"], function(_, value) TacoTipConfig.show_target = value; modernShowExampleTooltip() end)
    controls.showTarget:SetPoint("TOPLEFT", content, "TOPLEFT", 234, builder.y)
    builder.y = builder.y - 30

    controls.gearScorePlayer = createOptionsCheckbox(content, nil, L["OPTIONS_SHOW_PLAYER_GS"] or "Show player GearScore", L["OPTIONS_SHOW_PLAYER_GS_DESC"] or "Adds GearScore to player tooltips. Wide and mini layouts also show average item level on that line.", function(_, value) TacoTipConfig.show_gs_player = value; modernShowExampleTooltip() end)
    controls.gearScorePlayer:SetPoint("TOPLEFT", content, "TOPLEFT", 14, builder.y)
    controls.pawnScorePlayer = createOptionsCheckbox(content, nil, L["OPTIONS_SHOW_PLAYER_PAWN"] or "Show Pawn scores", L["OPTIONS_SHOW_PLAYER_PAWN_DESC"] or "Adds Pawn scores for inspected players when Pawn is installed. This may add extra item-cache work.", function(_, value) TacoTipConfig.show_pawn_player = value; modernShowExampleTooltip() end)
    controls.pawnScorePlayer:SetPoint("TOPLEFT", content, "TOPLEFT", 234, builder.y)
    builder.y = builder.y - 30

    controls.showTeam = createOptionsCheckbox(content, nil, L["Faction Icon"], L["Show player's faction icon (Horde/Alliance) in tooltips"], function(_, value) TacoTipConfig.show_team = value; modernShowExampleTooltip() end)
    controls.showTeam:SetPoint("TOPLEFT", content, "TOPLEFT", 14, builder.y)
    controls.showClassIcon = createOptionsCheckbox(content, nil, L["Class Icon"] or "Class Icon", "Show class icon badge at the top-right corner of player tooltips.", function(_, value) TacoTipConfig.show_class_icon = value; modernShowExampleTooltip() end)
    controls.showClassIcon:SetPoint("TOPLEFT", content, "TOPLEFT", 234, builder.y)
    builder.y = builder.y - 30

    controls.classColoredBorderToggle = createOptionsCheckbox(content, nil, L["OPTIONS_BORDER_CLASS_COLOR"] or "Use class-colored border", L["OPTIONS_BORDER_CLASS_COLOR_DESC"] or "Tint the tooltip border with the player's class color when the tooltip is showing a player unit.", function(_, value)
        TacoTipConfig.tooltip_border_use_class = value
        modernShowExampleTooltip()
    end)
    controls.classColoredBorderToggle:SetPoint("TOPLEFT", content, "TOPLEFT", 14, builder.y)
    builder.y = builder.y - 30

    controls.showPVPIcon = createOptionsCheckbox(content, nil, L["PVP Icon"], L["Show player's pvp flag status as icon instead of text"], function(_, value) TacoTipConfig.show_pvp_icon = value; modernShowExampleTooltip() end)
    controls.showPVPIcon:SetPoint("TOPLEFT", content, "TOPLEFT", 14, builder.y)
    controls.showHealthBar = createOptionsCheckbox(content, nil, L["Health Bar"], L["Show unit's health bar under tooltip"], function(_, value) TacoTipConfig.show_hp_bar = value; modernShowExampleTooltip() end)
    controls.showHealthBar:SetPoint("TOPLEFT", content, "TOPLEFT", 234, builder.y)
    builder.y = builder.y - 30

    controls.showHonorRank = createOptionsCheckbox(content, nil, L["OPTIONS_SHOW_HONOR_RANK"] or "Show honor rank", L["OPTIONS_SHOW_HONOR_RANK_DESC"] or "Show the player's PvP rank title (Knight, Centurion, etc.) on the tooltip.", function(_, value)
        TacoTipConfig.show_honor_rank = value
        modernShowExampleTooltip()
    end)
    controls.showHonorRank:SetPoint("TOPLEFT", content, "TOPLEFT", 14, builder.y)
    controls.showRoleIcon = createOptionsCheckbox(content, nil, L["OPTIONS_SHOW_ROLE_ICON"] or "Show group role icon", L["OPTIONS_SHOW_ROLE_ICON_DESC"] or "Show Tank/Healer/DPS role icons on the name line for party and raid members.", function(_, value)
        TacoTipConfig.show_role_icon = value
        modernShowExampleTooltip()
    end)
    controls.showRoleIcon:SetPoint("TOPLEFT", content, "TOPLEFT", 234, builder.y)
    builder.y = builder.y - 30

    controls.showRealm = createOptionsCheckbox(content, nil, L["OPTIONS_SHOW_REALM"] or "Show realm", L["OPTIONS_SHOW_REALM_DESC"] or "Show the realm name for players from other servers (cross-realm).", function(_, value)
        TacoTipConfig.show_realm = value
        modernShowExampleTooltip()
    end)
    controls.showRealm:SetPoint("TOPLEFT", content, "TOPLEFT", 14, builder.y)
    controls.showIlvlInline = createOptionsCheckbox(content, nil, L["OPTIONS_SHOW_ILVL_INLINE"] or "iLvl on name line", L["OPTIONS_SHOW_ILVL_INLINE_DESC"] or "Show average item level next to the player's name instead of on a separate line.", function(_, value)
        TacoTipConfig.show_ilvl_inline = value
        modernShowExampleTooltip()
    end)
    controls.showIlvlInline:SetPoint("TOPLEFT", content, "TOPLEFT", 234, builder.y)
    builder.y = builder.y - 30

    controls.showGSDelta = createOptionsCheckbox(content, nil, L["OPTIONS_SHOW_GS_DELTA"] or "GearScore change indicator", L["OPTIONS_SHOW_GS_DELTA_DESC"] or "Show a delta indicator (▲/▼) next to GearScore when it changed since the last time you saw that player.", function(_, value)
        TacoTipConfig.show_gs_delta = value
        modernShowExampleTooltip()
    end)
    controls.showGSDelta:SetPoint("TOPLEFT", content, "TOPLEFT", 14, builder.y)
    builder.y = builder.y - 30

    controls.showPowerBar = createOptionsCheckbox(content, nil, L["Power Bar"], L["Show unit's power bar under tooltip"], function(_, value) TacoTipConfig.show_power_bar = value; modernShowExampleTooltip() end)
    controls.showPowerBar:SetPoint("TOPLEFT", content, "TOPLEFT", 14, builder.y)
    builder.y = builder.y - 42

    local itemHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    itemHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 16, builder.y)
    itemHeader:SetText(L["OPTIONS_SECTION_ITEM_TOOLTIPS"] or "Item tooltip data")
    builder.y = builder.y - 24

    controls.showItemLevel = createOptionsCheckbox(content, nil, L["Show Item Level"], L["Display item level in the tooltip for certain items."], function(_, value) TacoTipConfig.show_item_level = value end)
    controls.showItemLevel:SetPoint("TOPLEFT", content, "TOPLEFT", 14, builder.y)
    controls.gearScoreItems = createOptionsCheckbox(content, nil, L["Show Item GearScore"], L["Show GearScore in item tooltips"], function(_, value) TacoTipConfig.show_gs_items = value; modernGetConfig() end)
    controls.gearScoreItems:SetPoint("TOPLEFT", content, "TOPLEFT", 234, builder.y)
    builder.y = builder.y - 30

    controls.hunterScoreItems = createOptionsCheckbox(content, nil, L["HunterScore"], L["OPTIONS_HUNTERSCORE_DESC"] or "Always show HunterScore when item GearScore is enabled. Without this, TacoTip still shows it for Hunters, when inspecting a Hunter, or while a modifier key is held.", function(_, value) TacoTipConfig.show_gs_items_hs = value end)
    controls.hunterScoreItems:SetPoint("TOPLEFT", content, "TOPLEFT", 14, builder.y)
    builder.y = builder.y - 42

    local visualHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    visualHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 16, builder.y)
    visualHeader:SetText(L["OPTIONS_SECTION_VISUAL_STYLE"] or "Visual style")
    builder.y = builder.y - 24

    local backdropHeader = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    backdropHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 16, builder.y)
    backdropHeader:SetText(L["OPTIONS_SECTION_BACKDROP_MEDIA"] or "Backdrop colors & textures")
    builder.y = builder.y - 24

    controls.tooltipBackgroundUseClass = createOptionsCheckbox(content, nil, L["OPTIONS_BACKGROUND_CLASS_COLOR"] or "Use class-colored background tint", L["OPTIONS_BACKGROUND_CLASS_COLOR_DESC"] or "Adds a subtle class-colored tint behind player tooltips. Use the alpha slider to keep it understated.", function(_, value)
        TacoTipConfig.tooltip_background_use_class = value
        modernShowExampleTooltip()
    end)
    controls.tooltipBackgroundUseClass:SetPoint("TOPLEFT", content, "TOPLEFT", 234, builder.y)
    builder.y = builder.y - 34

    controls.tooltipBorderColor = createColorSwatchControl(content, nil, L["OPTIONS_TOOLTIP_BORDER_COLOR"] or "Border color", L["OPTIONS_TOOLTIP_BORDER_COLOR_DESC"] or "Pick the base tooltip border color. If class-colored borders are enabled, that class tint overrides this on player tooltips.", function(r, g, b)
        TacoTipConfig.tooltip_border_color_r = r
        TacoTipConfig.tooltip_border_color_g = g
        TacoTipConfig.tooltip_border_color_b = b
        modernShowExampleTooltip()
    end)
    controls.tooltipBorderColor:SetPoint("TOPLEFT", content, "TOPLEFT", 16, builder.y)

    controls.tooltipBackgroundColor = createColorSwatchControl(content, nil, L["OPTIONS_TOOLTIP_BACKGROUND_COLOR"] or "Background color", L["OPTIONS_TOOLTIP_BACKGROUND_COLOR_DESC"] or "Pick the base tooltip background color. If class-colored backgrounds are enabled, that class tint overrides this on player tooltips.", function(r, g, b)
        TacoTipConfig.tooltip_background_color_r = r
        TacoTipConfig.tooltip_background_color_g = g
        TacoTipConfig.tooltip_background_color_b = b
        modernShowExampleTooltip()
    end)
    controls.tooltipBackgroundColor:SetPoint("TOPLEFT", content, "TOPLEFT", 236, builder.y)
    builder.y = builder.y - 118

    controls.tooltipBorderAlpha = createOptionsSlider(content, nil, L["OPTIONS_BORDER_ALPHA"] or "Border alpha", L["OPTIONS_BORDER_ALPHA_DESC"] or "Adjust how strong the tooltip border tint appears. Lower values keep class coloring subtle.", function(value)
        TacoTipConfig.tooltip_border_alpha = value / 100
        modernShowExampleTooltip()
    end, 0, 100, 1)
    controls.tooltipBorderAlpha:SetPoint("TOPLEFT", content, "TOPLEFT", 4, builder.y)
    controls.tooltipBorderAlpha.valueText:SetPoint("LEFT", controls.tooltipBorderAlpha, "RIGHT", 8, 0)

    controls.tooltipBorderEdgeSize = createOptionsSlider(content, nil, L["OPTIONS_TOOLTIP_BORDER_THICKNESS"] or "Border thickness", L["OPTIONS_TOOLTIP_BORDER_THICKNESS_DESC"] or "Control how thick the tooltip border appears. Higher values create a wider, more prominent border edge. Default is 16px.", function(value)
        TacoTipConfig.tooltip_border_edge_size = value
        modernShowExampleTooltip()
    end, 4, 48, 1)
    controls.tooltipBorderEdgeSize:SetPoint("TOPLEFT", content, "TOPLEFT", 214, builder.y)
    controls.tooltipBorderEdgeSize.valueText:SetPoint("LEFT", controls.tooltipBorderEdgeSize, "RIGHT", 8, 0)
    builder.y = builder.y - 56

    controls.tooltipBackgroundAlpha = createOptionsSlider(content, nil, L["OPTIONS_BACKGROUND_ALPHA"] or "Background alpha", L["OPTIONS_BACKGROUND_ALPHA_DESC"] or "Adjust how strong the tooltip background tint appears. Lower values keep the tooltip readable.", function(value)
        TacoTipConfig.tooltip_background_alpha = value / 100
        modernShowExampleTooltip()
    end, 0, 100, 1)
    controls.tooltipBackgroundAlpha:SetPoint("TOPLEFT", content, "TOPLEFT", 4, builder.y)
    controls.tooltipBackgroundAlpha.valueText:SetPoint("LEFT", controls.tooltipBackgroundAlpha, "RIGHT", 8, 0)
    builder.y = builder.y - 56

    controls.tooltipBackgroundTextureChoice = createOptionsDropdown(content, nil, L["OPTIONS_TOOLTIP_BACKGROUND_TEXTURE"] or "Tooltip background texture", L["OPTIONS_TOOLTIP_BACKGROUND_TEXTURE_DESC"] or "Choose the tooltip background texture. SharedMedia background packs are picked up automatically and Blizzard tooltip texture remains the fallback.", TT:GetTooltipBackgroundChoices(), function(value)
        TacoTipConfig.tooltip_background_texture = value
        modernGetConfig()
        modernShowExampleTooltip()
    end)
    builder.y = builder.y - layoutDropdownControl(content, controls.tooltipBackgroundTextureChoice, builder.y)

    controls.tooltipBorderTextureChoice = createOptionsDropdown(content, nil, L["OPTIONS_TOOLTIP_BORDER_TEXTURE"] or "Tooltip border texture", L["OPTIONS_TOOLTIP_BORDER_TEXTURE_DESC"] or "Choose the tooltip border texture. SharedMedia border packs are picked up automatically and Blizzard tooltip border remains the fallback.", TT:GetTooltipBorderChoices(), function(value)
        TacoTipConfig.tooltip_border_texture = value
        modernGetConfig()
        modernShowExampleTooltip()
    end)
    builder.y = builder.y - layoutDropdownControl(content, controls.tooltipBorderTextureChoice, builder.y)

    controls.showSeparators = createOptionsCheckbox(content, nil, L["OPTIONS_SHOW_SEPARATORS"] or "Show section separators", L["OPTIONS_SHOW_SEPARATORS_DESC"] or "Add thin horizontal lines between logical sections of the tooltip for visual clarity.", function(_, value)
        TacoTipConfig.show_separators = value
        modernShowExampleTooltip()
    end)
    controls.showSeparators:SetPoint("TOPLEFT", content, "TOPLEFT", 14, builder.y)

    controls.tooltipMaxWidth = createOptionsSlider(content, nil, L["OPTIONS_TOOLTIP_MAX_WIDTH"] or "Tooltip max width", L["OPTIONS_TOOLTIP_MAX_WIDTH_DESC"] or "Set a maximum width for the tooltip to prevent it from becoming too wide with long names or guild titles. Set to 0 for no limit.", function(value)
        TacoTipConfig.tooltip_max_width = value
        modernShowExampleTooltip()
    end, 0, 500, 10)
    controls.tooltipMaxWidth:SetPoint("TOPLEFT", content, "TOPLEFT", 214, builder.y)
    controls.tooltipMaxWidth.valueText:SetPoint("LEFT", controls.tooltipMaxWidth, "RIGHT", 8, 0)
    builder.y = builder.y - 56

    local portraitTextHeader = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    portraitTextHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 16, builder.y)
    portraitTextHeader:SetText(L["OPTIONS_SECTION_TEXT_AND_PORTRAIT"] or "Portrait & text")
    builder.y = builder.y - 24

    controls.tooltipPortrait = createOptionsCheckbox(content, nil, L["OPTIONS_TOOLTIP_PORTRAIT"] or "Show unit portrait", L["OPTIONS_TOOLTIP_PORTRAIT_DESC"] or "Show a small portrait texture next to player and NPC unit tooltips.", function(_, value)
        TacoTipConfig.tooltip_portrait = value
        modernGetConfig()
        modernShowExampleTooltip()
    end)
    controls.tooltipPortrait:SetPoint("TOPLEFT", content, "TOPLEFT", 14, builder.y)
    builder.y = builder.y - 34

    controls.tooltipPortraitScale = createOptionsSlider(content, nil, L["OPTIONS_TOOLTIP_PORTRAIT_SCALE"] or "Portrait scale", L["OPTIONS_TOOLTIP_PORTRAIT_SCALE_DESC"] or "Scale the portrait shown next to unit tooltips.", function(value)
        TacoTipConfig.tooltip_portrait_scale = value / 100
        modernShowExampleTooltip()
    end, 50, 200, 5)
    controls.tooltipPortraitScale:SetPoint("TOPLEFT", content, "TOPLEFT", 4, builder.y)
    controls.tooltipPortraitScale.valueText:SetPoint("LEFT", controls.tooltipPortraitScale, "RIGHT", 8, 0)
    builder.y = builder.y - 56

    controls.tooltipPortrait3D = createOptionsCheckbox(content, nil, L["OPTIONS_TOOLTIP_PORTRAIT_3D"] or "Show 3D portrait", L["OPTIONS_TOOLTIP_PORTRAIT_3D_DESC"] or "Use a live 3D model instead of a 2D portrait texture.", function(_, value)
        TacoTipConfig.tooltip_portrait_3d = value
        modernGetConfig()
        modernShowExampleTooltip()
    end)
    controls.tooltipPortrait3D:SetPoint("TOPLEFT", content, "TOPLEFT", 14, builder.y)
    builder.y = builder.y - 34

    controls.tooltipPortraitZoom = createOptionsSlider(content, nil, L["OPTIONS_PORTRAIT_ZOOM"] or "Portrait zoom", L["OPTIONS_PORTRAIT_ZOOM_DESC"] or "Controls how close the 3D portrait model appears. Higher values zoom in on the character's face.", function(value)
        TacoTipConfig.tooltip_portrait_zoom = value / 100
        modernShowExampleTooltip()
    end, 30, 100, 5)
    controls.tooltipPortraitZoom:SetPoint("TOPLEFT", content, "TOPLEFT", 4, builder.y)
    controls.tooltipPortraitZoom.valueText:SetPoint("LEFT", controls.tooltipPortraitZoom, "RIGHT", 8, 0)
    builder.y = builder.y - 56

    controls.showEliteFrame = createOptionsCheckbox(content, nil, L["OPTIONS_SHOW_ELITE_FRAME"] or "Show elite indicator", L["OPTIONS_SHOW_ELITE_FRAME_DESC"] or "Show the Elite, Rare, or Boss dragon border overlay on the portrait for non-player NPCs.", function(_, value)
        TacoTipConfig.show_elite_frame = value
        modernShowExampleTooltip()
    end)
    controls.showEliteFrame:SetPoint("TOPLEFT", content, "TOPLEFT", 14, builder.y)
    builder.y = builder.y - 34

    controls.classIconSize = createOptionsSlider(content, nil, "Class icon size", "Size of the class icon badge shown at the top-right corner of player tooltips.", function(value)
        TacoTipConfig.class_icon_size = value
        modernShowExampleTooltip()
    end, 8, 32, 1)
    controls.classIconSize:SetPoint("TOPLEFT", content, "TOPLEFT", 4, builder.y)
    controls.classIconSize.valueText:SetPoint("LEFT", controls.classIconSize, "RIGHT", 8, 0)
    builder.y = builder.y - 56

    controls.tooltipFontChoice = createOptionsDropdown(content, nil, L["OPTIONS_TOOLTIP_FONT"] or "Tooltip font", L["OPTIONS_TOOLTIP_FONT_DESC"] or "Choose the font used by tooltip text. SharedMedia fonts are included automatically when available.", TT:GetTooltipFontChoices(), function(value)
        TacoTipConfig.tooltip_font = value
        modernGetConfig()
        modernShowExampleTooltip()
    end)
    builder.y = builder.y - layoutDropdownControl(content, controls.tooltipFontChoice, builder.y)

    controls.tooltipFontSize = createOptionsSlider(content, nil, L["OPTIONS_TOOLTIP_FONT_SIZE"] or "Tooltip text size", L["OPTIONS_TOOLTIP_FONT_SIZE_DESC"] or "Change the size of the tooltip text without affecting the rest of the UI.", function(value)
        TacoTipConfig.tooltip_font_size = value
        modernShowExampleTooltip()
    end, 8, 20, 1)
    controls.tooltipFontSize:SetPoint("TOPLEFT", content, "TOPLEFT", 4, builder.y)
    controls.tooltipFontSize.valueText:SetPoint("LEFT", controls.tooltipFontSize, "RIGHT", 8, 0)
    builder.y = builder.y - 56

    local barHeader = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    barHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 16, builder.y)
    barHeader:SetText(L["OPTIONS_SECTION_BAR_MEDIA"] or "Tooltip bars")
    builder.y = builder.y - 24

    controls.tooltipBarTextureChoice = createOptionsDropdown(content, nil, L["OPTIONS_STATUSBAR_TEXTURE"] or "Health & power bar texture", L["OPTIONS_STATUSBAR_TEXTURE_DESC"] or "Use one texture for both the health bar and the power bar. The dropdown previews each texture as a bar instead of an icon.", TT:GetTooltipStatusBarTextureChoices(), function(value)
        TacoTipConfig.tooltip_bar_texture = value
        modernGetConfig()
        modernShowExampleTooltip()
    end)
    builder.y = builder.y - layoutDropdownControl(content, controls.tooltipBarTextureChoice, builder.y, 14)

    builder:Finalize(128)

    -- Preview pane floats to the right of the Blizzard Settings panel.
    -- Parented to UIParent so it is never clipped by the Settings frame
    -- hierarchy; strata FULLSCREEN_DIALOG ensures it renders above.
    local previewPane = CreateFrame("Frame", nil, UIParent)
    previewPane:SetFrameStrata("FULLSCREEN_DIALOG")
    previewPane:SetFrameLevel(100)
    previewPane:SetWidth(250)
    previewPane:Hide()

    -- Position the preview to the right of the tooltips page on first build.
    -- The preview is not shown here — it only appears via OnShow/OnHide on
    -- the tooltips page, so it's never visible on other pages.
    do
        local panelW = panel:GetWidth() or 640
        local panelH = panel:GetHeight() or 400
        previewPane:ClearAllPoints()
        previewPane:SetPoint("TOPLEFT", panel, "TOPRIGHT", 15, 0)
        previewPane:SetPoint("BOTTOMLEFT", panel, "TOPRIGHT", 265, -panelH)
    end
    modernOptionsState.previewPane = previewPane

    local previewTitle = previewPane:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    previewTitle:SetPoint("TOPLEFT", previewPane, "TOPLEFT", 0, 0)
    previewTitle:SetPoint("TOPRIGHT", previewPane, "TOPRIGHT", 0, 0)
    previewTitle:SetJustifyH("LEFT")
    previewTitle:SetText(L["OPTIONS_PREVIEW_HEADER"] or "Live Preview")

    local previewHelp = previewPane:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    previewHelp:SetPoint("TOPLEFT", previewTitle, "BOTTOMLEFT", 0, -4)
    previewHelp:SetPoint("TOPRIGHT", previewPane, "TOPRIGHT", 0, -4)
    previewHelp:SetJustifyH("LEFT")
    previewHelp:SetText(L["OPTIONS_PREVIEW_HELP"] or "Hover controls for more info. Appearance changes update this preview immediately.")

    modernOptionsState.previewAnchor = CreateFrame("Frame", nil, previewPane)
    modernOptionsState.previewAnchor:SetPoint("TOPLEFT", previewHelp, "BOTTOMLEFT", 0, -8)
    modernOptionsState.previewAnchor:SetPoint("TOPRIGHT", previewPane, "TOPRIGHT", 0, 0)
    modernOptionsState.previewAnchor:SetHeight(220)

    modernOptionsState.preview = CreateFrame("GameTooltip", "TacoTipModernPreviewTooltip", previewPane, "GameTooltipTemplate")
    modernOptionsState.previewHealthBar = CreateFrame("StatusBar", nil, modernOptionsState.preview)
    modernOptionsState.previewHealthBar:SetSize(0, 8)
    modernOptionsState.previewHealthBar:SetPoint("TOPLEFT", modernOptionsState.preview, "BOTTOMLEFT", 2, -1)
    modernOptionsState.previewHealthBar:SetPoint("TOPRIGHT", modernOptionsState.preview, "BOTTOMRIGHT", -2, -1)
    modernOptionsState.previewHealthBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-TargetingFrame-BarFill")
    modernOptionsState.previewHealthBar:SetStatusBarColor(0, 1, 0)
    modernOptionsState.previewPowerBar = CreateFrame("StatusBar", nil, modernOptionsState.preview)
    modernOptionsState.previewPowerBar:SetSize(0, 8)
    modernOptionsState.previewPowerBar:SetPoint("TOPLEFT", modernOptionsState.preview, "BOTTOMLEFT", 2, -9)
    modernOptionsState.previewPowerBar:SetPoint("TOPRIGHT", modernOptionsState.preview, "BOTTOMRIGHT", -2, -9)
    modernOptionsState.previewPowerBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-TargetingFrame-BarFill")
    modernOptionsState.previewPowerBar:SetStatusBarColor(1, 1, 0)
    modernOptionsState.preview:SetScript("OnEvent", function() modernShowExampleTooltip() end)

    panel:SetScript("OnShow", function()
        -- Reposition the floating preview to the right of the panel
        -- each time the page is shown (panel may have been resized).
        local pp = modernOptionsState.previewPane
        if (pp) then
            local panelW = panel:GetWidth() or 640
            local panelH = panel:GetHeight() or 400
            pp:ClearAllPoints()
            pp:SetPoint("TOPLEFT", panel, "TOPRIGHT", 15, 0)
            pp:SetPoint("BOTTOMLEFT", panel, "TOPRIGHT", 265, -panelH)
            pp:Show()
        end
        if (modernOptionsState.preview) then
            modernOptionsState.preview:RegisterEvent("MODIFIER_STATE_CHANGED")
        end
        if (panel.Refresh) then panel:Refresh() end
    end)
    panel:SetScript("OnHide", function()
        local pp = modernOptionsState.previewPane
        if (pp) then
            pp:Hide()
        end
        if (modernOptionsState.preview) then
            modernOptionsState.preview:UnregisterEvent("MODIFIER_STATE_CHANGED")
        end
    end)

    panel.Refresh = function()
        controls.tooltipFontChoice:SetValues(TT:GetTooltipFontChoices())
        controls.tooltipBarTextureChoice:SetValues(TT:GetTooltipStatusBarTextureChoices())
        controls.tooltipBackgroundTextureChoice:SetValues(TT:GetTooltipBackgroundChoices())
        controls.tooltipBorderTextureChoice:SetValues(TT:GetTooltipBorderChoices())
        controls.styleChoice:SetValue(TacoTipConfig.tip_style)
        controls.useClassColors:SetChecked(TacoTipConfig.color_class)
        controls.showTitles:SetChecked(TacoTipConfig.show_titles)
        controls.showGuildNames:SetChecked(TacoTipConfig.show_guild_name)
        controls.showGuildRanks:SetChecked(TacoTipConfig.show_guild_rank)
        controls.showGuildRanks:SetDisabled(not TacoTipConfig.show_guild_name)
        controls.guildRankStyleChoice:SetValue(TacoTipConfig.guild_rank_alt_style and 2 or 1)
        controls.guildRankStyleChoice:SetDisabled(not (TacoTipConfig.show_guild_name and TacoTipConfig.show_guild_rank))
        controls.showTalents:SetChecked(TacoTipConfig.show_talents)
        controls.showTarget:SetChecked(TacoTipConfig.show_target)
        controls.gearScorePlayer:SetChecked(TacoTipConfig.show_gs_player)
        controls.pawnScorePlayer:SetChecked(TacoTipConfig.show_pawn_player)
        controls.pawnScorePlayer:SetDisabled(not isPawnLoaded)
        controls.pawnScorePlayer.label:SetText(isPawnLoaded and (L["OPTIONS_SHOW_PLAYER_PAWN"] or "Show Pawn scores") or ((L["OPTIONS_SHOW_PLAYER_PAWN"] or "Show Pawn scores").." ("..L["requires Pawn"]..")"))
        controls.showTeam:SetChecked(TacoTipConfig.show_team)
        controls.showClassIcon:SetChecked(TacoTipConfig.show_class_icon)
        controls.classColoredBorderToggle:SetChecked(TacoTipConfig.tooltip_border_use_class)
        controls.showPVPIcon:SetChecked(TacoTipConfig.show_pvp_icon)
        controls.showHealthBar:SetChecked(TacoTipConfig.show_hp_bar)
        controls.showPowerBar:SetChecked(TacoTipConfig.show_power_bar)
        controls.showItemLevel:SetChecked(TacoTipConfig.show_item_level)
        controls.gearScoreItems:SetChecked(TacoTipConfig.show_gs_items)
        controls.hunterScoreItems:SetChecked(TacoTipConfig.show_gs_items_hs)
        controls.hunterScoreItems:SetDisabled(not TacoTipConfig.show_gs_items)
        controls.tooltipBackgroundUseClass:SetChecked(TacoTipConfig.tooltip_background_use_class)
        controls.tooltipBorderColor:SetColor(TacoTipConfig.tooltip_border_color_r or 1, TacoTipConfig.tooltip_border_color_g or 1, TacoTipConfig.tooltip_border_color_b or 1)
        controls.tooltipBackgroundColor:SetColor(TacoTipConfig.tooltip_background_color_r or 0, TacoTipConfig.tooltip_background_color_g or 0, TacoTipConfig.tooltip_background_color_b or 0)
        controls.tooltipBorderAlpha:SetValueSilently(math.floor((TacoTipConfig.tooltip_border_alpha or 1) * 100 + 0.5))
        controls.tooltipBorderEdgeSize:SetValueSilently(TacoTipConfig.tooltip_border_edge_size or 16)
        controls.tooltipBackgroundAlpha:SetValueSilently(math.floor((TacoTipConfig.tooltip_background_alpha or 0.85) * 100 + 0.5))
        controls.tooltipBackgroundTextureChoice:SetValue(TT:GetResolvedTooltipBackground())
        controls.tooltipBorderTextureChoice:SetValue(TT:GetResolvedTooltipBorder())
        controls.tooltipPortrait:SetChecked(TacoTipConfig.tooltip_portrait)
        controls.tooltipPortraitScale:SetValueSilently(math.floor((TacoTipConfig.tooltip_portrait_scale or 1) * 100 + 0.5))
        controls.tooltipPortraitScale:SetDisabled(not TacoTipConfig.tooltip_portrait)
        controls.tooltipPortrait3D:SetChecked(TacoTipConfig.tooltip_portrait_3d)
        controls.tooltipPortrait3D:SetDisabled(not TacoTipConfig.tooltip_portrait)
        controls.tooltipPortraitZoom:SetValueSilently(math.floor((TacoTipConfig.tooltip_portrait_zoom or 0.7) * 100 + 0.5))
        controls.tooltipPortraitZoom:SetDisabled(not TacoTipConfig.tooltip_portrait)
        controls.showEliteFrame:SetChecked(TacoTipConfig.show_elite_frame)
        controls.showEliteFrame:SetDisabled(not TacoTipConfig.tooltip_portrait)
        controls.classIconSize:SetValueSilently(TacoTipConfig.class_icon_size or 20)
        controls.tooltipFontChoice:SetValue(TT:GetResolvedTooltipFont())
        controls.tooltipFontSize:SetValueSilently(TacoTipConfig.tooltip_font_size or 12)
        controls.tooltipBarTextureChoice:SetValue(TT:GetResolvedTooltipStatusBarTexture())
        controls.showHonorRank:SetChecked(TacoTipConfig.show_honor_rank)
        controls.showRoleIcon:SetChecked(TacoTipConfig.show_role_icon)
        controls.showRealm:SetChecked(TacoTipConfig.show_realm)
        controls.showIlvlInline:SetChecked(TacoTipConfig.show_ilvl_inline)
        controls.showGSDelta:SetChecked(TacoTipConfig.show_gs_delta)
        controls.showSeparators:SetChecked(TacoTipConfig.show_separators)
        controls.tooltipMaxWidth:SetValueSilently(TacoTipConfig.tooltip_max_width or 0)
        modernShowExampleTooltip()
    end

    modernOptionsState.pages.tooltipsBuilt = true
end

local function setOffsetValue(key, value)
    TacoTipConfig[key] = value

    local editBox = modernOptionsState.offsetEditors[key]
    if (editBox) then
        editBox.lastValue = value
        editBox:SetText(tostring(value))
    end

    local slider = modernOptionsState.offsetSliders[key]
    if (slider) then
        slider:SetValueSilently(value)
    end

    refreshOverlayPositions()
end

local function setOffsetControlEnabled(key, enabled)
    local editBox = modernOptionsState.offsetEditors[key]
    local slider = modernOptionsState.offsetSliders[key]
    if (editBox and editBox.SetDisabled) then editBox:SetDisabled(not enabled) end
    if (slider and slider.SetDisabled) then slider:SetDisabled(not enabled) end
end

local function buildPositioningPage()
    if (modernOptionsState.pages.positioningBuilt) then
        return
    end

    local panel = optionsPages.positioning
    local _, content = createScrollPage(panel)
    local builder = createPageBuilder(content, 16, -16)
    local controls = modernOptionsState.controls

    local header, headerDesc = createSectionHeader(content, L["OPTIONS_PAGE_POSITIONING"] or "Positioning", L["OPTIONS_POSITIONING_PAGE_DESC"] or "Choose how TacoTip places the main tooltip and how its mover workflow behaves.", 520)
    builder:AddAnchor(header, 24)
    if (headerDesc) then builder:AddAnchor(headerDesc, headerDesc:GetStringHeight() + 8) end

    local modeHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    modeHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 16, builder.y)
    modeHeader:SetText(L["OPTIONS_SECTION_TOOLTIP_POSITION"] or "Tooltip position mode")
    builder.y = builder.y - 24

    controls.customPosition = createOptionsCheckbox(content, "TacoTipOptCheckBoxCustomPosition", L["Custom Tooltip Position"], L["OPTIONS_CUSTOM_POSITION_DESC"] or "Save and reuse a custom on-screen tooltip location.", function(_, value)
        local anchor = TacoTipConfig.custom_anchor or "TOPLEFT"
        TacoTipConfig.custom_pos = value and (TacoTipConfig.custom_pos or {anchor, anchor, 0, 0}) or nil
        if (value) then
            TacoTipConfig.anchor_mouse = false
            if (TacoTip_CustomPosEnable) then TacoTip_CustomPosEnable(false) end
        else
            if (TacoTipDragButton) then TacoTipDragButton:_Disable(true) end
        end
        if (TT.SyncTooltipMover) then TT:SyncTooltipMover() end
        modernGetConfig()
    end)
    controls.customPosition:SetPoint("TOPLEFT", content, "TOPLEFT", 14, builder.y)

    controls.anchorMouse = createOptionsCheckbox(content, "TacoTipOptCheckBoxAnchorMouse", L["Anchor to Mouse"], L["Anchor tooltips to mouse cursor"], function(_, value)
        TacoTipConfig.anchor_mouse = value
        if (value) then
            TacoTipConfig.custom_pos = nil
            if (TacoTipDragButton) then TacoTipDragButton:_Disable(true) end
        end
        modernGetConfig()
    end)
    controls.anchorMouse:SetPoint("TOPLEFT", content, "TOPLEFT", 274, builder.y)
    builder.y = builder.y - 30

    controls.anchorMouseWorld = createOptionsCheckbox(content, "TacoTipOptCheckBoxAnchorMouseWorld", L["Only in WorldFrame"], L["Anchor to mouse only in WorldFrame\nSkips raid / party frames"], function(_, value)
        TacoTipConfig.anchor_mouse_world = value
    end)
    controls.anchorMouseWorld:SetPoint("TOPLEFT", content, "TOPLEFT", 14, builder.y)

    controls.anchorMouseSpells = createOptionsCheckbox(content, nil, L["Anchor Spells to Mouse"], L["OPTIONS_ANCHOR_MOUSE_SPELLS_DESC"] or "Anchor spell and action-button tooltips to the mouse cursor instead of the saved tooltip position.", function(_, value)
        TacoTipConfig.anchor_mouse_spells = value
    end)
    controls.anchorMouseSpells:SetPoint("TOPLEFT", content, "TOPLEFT", 274, builder.y)
    builder.y = builder.y - 38

    controls.customAnchor = createOptionsDropdown(content, nil, L["OPTIONS_CUSTOM_ANCHOR_LABEL"] or "Custom tooltip anchor", L["OPTIONS_CUSTOM_ANCHOR_DESC"] or "Choose which point of the saved tooltip position acts as the attachment anchor.", modernAnchorOptions, function(value)
        TacoTipConfig.custom_anchor = value
        if (TT.SyncTooltipMover) then TT:SyncTooltipMover() end
        if (TacoTipDragButton and TacoTipDragButton.IsShown and TacoTipDragButton:IsShown()) then
            TacoTipDragButton:ShowExample()
        end
    end)
    controls.customAnchor.label:SetPoint("TOPLEFT", content, "TOPLEFT", 16, builder.y)
    controls.customAnchor:SetPoint("TOPLEFT", controls.customAnchor.label, "BOTTOMLEFT", -16, -2)
    if (controls.customAnchor.description) then
        controls.customAnchor.description:SetPoint("TOPLEFT", controls.customAnchor, "BOTTOMLEFT", 20, -2)
    end

    controls.moverBtn = createOptionsButton(content, "TacoTipOptButtonMover", L["OPTIONS_OPEN_TOOLTIP_MOVER"] or L["Mover"], 180, 22, function()
        showTooltipMover()
    end, L["OPTIONS_OPEN_TOOLTIP_MOVER_DESC"] or "Show the live tooltip mover so you can drag and save a custom tooltip position.")
    controls.moverBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 274, builder.y - 4)
    builder.y = builder.y - 78

    local behaviorHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    behaviorHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 16, builder.y)
    behaviorHeader:SetText(L["OPTIONS_SECTION_TOOLTIP_BEHAVIOR"] or "Tooltip behavior")
    builder.y = builder.y - 24

    controls.instantFade = createOptionsCheckbox(content, nil, L["Instant Fade"], L["Fade out unit tooltips instantly"], function(_, value)
        TacoTipConfig.instant_fade = value
        updateInstantFadeState(value)
    end)
    controls.instantFade:SetPoint("TOPLEFT", content, "TOPLEFT", 14, builder.y)
    builder.y = builder.y - 38

    controls.tooltipDelay = createOptionsSlider(content, nil, L["OPTIONS_TOOLTIP_DELAY"] or "Tooltip delay (ms)", L["OPTIONS_TOOLTIP_DELAY_DESC"] or "Add a short delay before the tooltip appears to prevent flicker when quickly moving the mouse. 0 = no delay.", function(value)
        TacoTipConfig.tooltip_delay = value / 1000
    end, 0, 1000, 50)
    controls.tooltipDelay:SetPoint("TOPLEFT", content, "TOPLEFT", 4, builder.y)
    controls.tooltipDelay.valueText:SetPoint("LEFT", controls.tooltipDelay, "RIGHT", 8, 0)
    builder.y = builder.y - 56

    builder:Finalize(64)

    panel.Refresh = function()
        local hasCustomPos = TacoTipConfig.custom_pos and true or false
        controls.customPosition:SetChecked(hasCustomPos)
        controls.anchorMouse:SetChecked(TacoTipConfig.anchor_mouse)
        controls.anchorMouseWorld:SetChecked(TacoTipConfig.anchor_mouse_world)
        controls.anchorMouseSpells:SetChecked(TacoTipConfig.anchor_mouse_spells)
        controls.instantFade:SetChecked(TacoTipConfig.instant_fade)
        controls.customAnchor:SetValue(TacoTipConfig.custom_anchor or "TOPLEFT")
        controls.customPosition:SetDisabled(TacoTipConfig.anchor_mouse)
        controls.anchorMouse:SetDisabled(hasCustomPos)
        controls.anchorMouseWorld:SetDisabled(not TacoTipConfig.anchor_mouse)
        controls.customAnchor:SetDisabled(not hasCustomPos)
        setButtonEnabled(controls.moverBtn, hasCustomPos)
        controls.tooltipDelay:SetValueSilently(math.floor((TacoTipConfig.tooltip_delay or 0) * 1000 + 0.5))
    end

    panel:SetScript("OnShow", function()
        if (panel.Refresh) then panel:Refresh() end
    end)

    modernOptionsState.pages.positioningBuilt = true
end

local function createOffsetControlRow(parent, builder, titleText, keyX, keyY)
    local label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, builder.y)
    label:SetText(titleText)

    local xLabel = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    xLabel:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -8)
    xLabel:SetText("X")

    local xEdit = createOptionsEditBox(parent, nil, 52, function(value) setOffsetValue(keyX, value) end, titleText .. " X", L["OPTIONS_OFFSET_EDIT_DESC"] or "Type a precise pixel offset and press Enter to apply it.")
    xEdit:SetPoint("LEFT", xLabel, "RIGHT", 10, 0)
    modernOptionsState.offsetEditors[keyX] = xEdit

    local xSlider = createOptionsSlider(parent, nil, titleText .. " X", L["OPTIONS_OFFSET_SLIDER_DESC"] or "Drag to fine-tune this offset. The numeric field stays synchronized.", function(value) setOffsetValue(keyX, value) end)
    xSlider.label:SetText("")
    xSlider:SetPoint("TOPLEFT", xEdit, "TOPRIGHT", 18, 0)
    xSlider.valueText:SetPoint("LEFT", xSlider, "RIGHT", 8, 0)
    modernOptionsState.offsetSliders[keyX] = xSlider

    local yLabel = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    yLabel:SetPoint("TOPLEFT", xLabel, "BOTTOMLEFT", 0, -30)
    yLabel:SetText("Y")

    local yEdit = createOptionsEditBox(parent, nil, 52, function(value) setOffsetValue(keyY, value) end, titleText .. " Y", L["OPTIONS_OFFSET_EDIT_DESC"] or "Type a precise pixel offset and press Enter to apply it.")
    yEdit:SetPoint("LEFT", yLabel, "RIGHT", 10, 0)
    modernOptionsState.offsetEditors[keyY] = yEdit

    local ySlider = createOptionsSlider(parent, nil, titleText .. " Y", L["OPTIONS_OFFSET_SLIDER_DESC"] or "Drag to fine-tune this offset. The numeric field stays synchronized.", function(value) setOffsetValue(keyY, value) end)
    ySlider.label:SetText("")
    ySlider:SetPoint("TOPLEFT", yEdit, "TOPRIGHT", 18, 0)
    ySlider.valueText:SetPoint("LEFT", ySlider, "RIGHT", 8, 0)
    modernOptionsState.offsetSliders[keyY] = ySlider

    builder.y = builder.y - 118

    return {
        label = label,
        xLabel = xLabel,
        yLabel = yLabel,
        xEdit = xEdit,
        yEdit = yEdit,
        xSlider = xSlider,
        ySlider = ySlider,
        keys = { keyX, keyY }
    }
end

local function buildCharacterInspectPage()
    if (modernOptionsState.pages.characterInspectBuilt) then
        return
    end

    local panel = optionsPages.characterInspect
    local _, content = createScrollPage(panel)
    local builder = createPageBuilder(content, 16, -16)
    local controls = modernOptionsState.controls

    local header, headerDesc = createSectionHeader(content, L["OPTIONS_PAGE_CHARACTER_INSPECT"] or "Character & Inspect", L["OPTIONS_CHARACTER_PAGE_DESC"] or "Control the character-frame and inspect-frame overlay labels, plus their precise offsets.", 520)
    builder:AddAnchor(header, 24)
    if (headerDesc) then builder:AddAnchor(headerDesc, headerDesc:GetStringHeight() + 8) end

    controls.gearScoreCharacter = createOptionsCheckbox(content, nil, L["OPTIONS_CHARACTER_GS_LABEL"] or "Show GearScore overlays", L["OPTIONS_CHARACTER_GS_DESC"] or "Show GearScore on both the character frame and inspect frame.", function(_, value)
        TacoTipConfig.show_gs_character = value
        refreshOverlayPositions()
        modernGetConfig()
    end)
    controls.gearScoreCharacter:SetPoint("TOPLEFT", content, "TOPLEFT", 14, builder.y)

    controls.averageItemLevel = createOptionsCheckbox(content, nil, L["OPTIONS_CHARACTER_ILVL_LABEL"] or "Show average item level overlays", L["OPTIONS_CHARACTER_ILVL_DESC"] or "Show average item level on both the character frame and inspect frame.", function(_, value)
        TacoTipConfig.show_avg_ilvl = value
        refreshOverlayPositions()
        modernGetConfig()
    end)
    controls.averageItemLevel:SetPoint("TOPLEFT", content, "TOPLEFT", 274, builder.y)
    builder.y = builder.y - 30

    controls.unlockInfoPosition = createOptionsCheckbox(content, nil, L["OPTIONS_UNLOCK_OVERLAYS_LABEL"] or "Enable manual overlay movers", L["OPTIONS_UNLOCK_OVERLAYS_DESC"] or "Show drag handles on the frame overlays so you can position them manually in addition to using the numeric offsets below.", function(_, value)
        TacoTipConfig.unlock_info_position = value
        refreshOverlayPositions()
        modernGetConfig()
    end)
    controls.unlockInfoPosition:SetPoint("TOPLEFT", content, "TOPLEFT", 14, builder.y)
    builder.y = builder.y - 42

    modernOptionsState.characterGsRow = createOffsetControlRow(content, builder, L["OPTIONS_CHARACTER_GS_OFFSETS"] or "Character GearScore offsets", "character_gs_offset_x", "character_gs_offset_y")
    modernOptionsState.characterIlvlRow = createOffsetControlRow(content, builder, L["OPTIONS_CHARACTER_ILVL_OFFSETS"] or "Character iLvl offsets", "character_ilvl_offset_x", "character_ilvl_offset_y")
    modernOptionsState.inspectGsRow = createOffsetControlRow(content, builder, L["OPTIONS_INSPECT_GS_OFFSETS"] or "Inspect GearScore offsets", "inspect_gs_offset_x", "inspect_gs_offset_y")
    modernOptionsState.inspectIlvlRow = createOffsetControlRow(content, builder, L["OPTIONS_INSPECT_ILVL_OFFSETS"] or "Inspect iLvl offsets", "inspect_ilvl_offset_x", "inspect_ilvl_offset_y")

    builder:Finalize(80)

    modernRefreshLockPositionToggle = function()
        if (controls.unlockInfoPosition) then
            controls.unlockInfoPosition:SetDisabled(not (TacoTipConfig.show_gs_character or TacoTipConfig.show_avg_ilvl))
        end

        setOffsetControlEnabled("character_gs_offset_x", TacoTipConfig.show_gs_character)
        setOffsetControlEnabled("character_gs_offset_y", TacoTipConfig.show_gs_character)
        setOffsetControlEnabled("inspect_gs_offset_x", TacoTipConfig.show_gs_character)
        setOffsetControlEnabled("inspect_gs_offset_y", TacoTipConfig.show_gs_character)
        setOffsetControlEnabled("character_ilvl_offset_x", TacoTipConfig.show_avg_ilvl)
        setOffsetControlEnabled("character_ilvl_offset_y", TacoTipConfig.show_avg_ilvl)
        setOffsetControlEnabled("inspect_ilvl_offset_x", TacoTipConfig.show_avg_ilvl)
        setOffsetControlEnabled("inspect_ilvl_offset_y", TacoTipConfig.show_avg_ilvl)
    end

    panel.Refresh = function()
        controls.gearScoreCharacter:SetChecked(TacoTipConfig.show_gs_character)
        controls.averageItemLevel:SetChecked(TacoTipConfig.show_avg_ilvl)
        controls.unlockInfoPosition:SetChecked(TacoTipConfig.unlock_info_position)

        setOffsetValue("character_gs_offset_x", TacoTipConfig.character_gs_offset_x or 0)
        setOffsetValue("character_gs_offset_y", TacoTipConfig.character_gs_offset_y or 0)
        setOffsetValue("character_ilvl_offset_x", TacoTipConfig.character_ilvl_offset_x or 0)
        setOffsetValue("character_ilvl_offset_y", TacoTipConfig.character_ilvl_offset_y or 0)
        setOffsetValue("inspect_gs_offset_x", TacoTipConfig.inspect_gs_offset_x or 0)
        setOffsetValue("inspect_gs_offset_y", TacoTipConfig.inspect_gs_offset_y or 0)
        setOffsetValue("inspect_ilvl_offset_x", TacoTipConfig.inspect_ilvl_offset_x or 0)
        setOffsetValue("inspect_ilvl_offset_y", TacoTipConfig.inspect_ilvl_offset_y or 0)

        modernRefreshLockPositionToggle()
    end

    panel:SetScript("OnShow", function()
        if (panel.Refresh) then panel:Refresh() end
    end)

    modernOptionsState.pages.characterInspectBuilt = true
end

modernGetConfig = function()
    if (modernOptionsState.pages.rootBuilt and optionsFrame.Refresh) then
        optionsFrame:Refresh()
    end
    if (modernOptionsState.pages.tooltipsBuilt and optionsPages.tooltips.Refresh) then
        optionsPages.tooltips:Refresh()
    end
    if (modernOptionsState.pages.positioningBuilt and optionsPages.positioning.Refresh) then
        optionsPages.positioning:Refresh()
    end
    if (modernOptionsState.pages.characterInspectBuilt and optionsPages.characterInspect.Refresh) then
        optionsPages.characterInspect:Refresh()
    end
end

local function ensureModernOptionsBuilt()
    if (modernOptionsState.built) then
        return
    end
    -- Set a minimum content size for child pages so they display
    -- correctly even in narrow Blizzard Settings canvases.
    optionsPages.tooltips:SetSize(640, 400)
    optionsPages.positioning:SetSize(640, 400)
    optionsPages.characterInspect:SetSize(640, 400)

    buildRootPage()
    buildTooltipsPage()
    buildPositioningPage()
    buildCharacterInspectPage()
    modernOptionsState.built = true
end

TT.RefreshOptionsUI = function(self)
    ensureModernOptionsBuilt()
    modernGetConfig()
    modernShowExampleTooltip()
end

local function onPageShow(panel)
    ensureModernOptionsBuilt()
    -- Show the floating preview pane when the tooltips page is opened.
    -- Other child pages (positioning, characterInspect) do not show it.
    if (panel == optionsPages.tooltips) then
        local pp = modernOptionsState.previewPane
        if (pp and not pp:IsShown()) then
            local panelW = panel:GetWidth() or 640
            local panelH = panel:GetHeight() or 400
            pp:ClearAllPoints()
            pp:SetPoint("TOPLEFT", panel, "TOPRIGHT", 15, 0)
            pp:SetPoint("BOTTOMLEFT", panel, "TOPRIGHT", 265, -panelH)
            pp:Show()
        end
    end
    if (panel and panel.Refresh) then panel:Refresh() end
end
local function onOptionsFrameShow(panel)
    ensureModernOptionsBuilt()
    modernGetConfig()
    modernShowExampleTooltip()
end
optionsPages.tooltips:SetScript("OnShow", function(panel, ...)
    return safeCall(onPageShow, panel, ...)
end)
optionsPages.positioning:SetScript("OnShow", function(panel, ...)
    return safeCall(onPageShow, panel, ...)
end)
optionsPages.characterInspect:SetScript("OnShow", function(panel, ...)
    return safeCall(onPageShow, panel, ...)
end)
optionsFrame:SetScript("OnShow", function(panel, ...)
    return safeCall(onOptionsFrameShow, panel, ...)
end)

