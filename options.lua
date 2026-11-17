--[[

    TacoTip — Options & Dashboard UI module
    Based on original TacoTip by kebabstorm (https://www.curseforge.com/wow/addons/tacotip-gearscore-talents)
    Multi-engine extensions & dashboard by AcidBomb (MIT License)

--]]

local addOnName = ...
local addOnVersion = (GetAddOnMetadata and GetAddOnMetadata(addOnName, "Version")) or
    (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addOnName, "Version")) or "1.0.8"
local addOnTitle = (GetAddOnMetadata and GetAddOnMetadata(addOnName, "Title")) or
    (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addOnName, "Title")) or addOnName
local LoadAddOn = _G.LoadAddOn
local tinsert = tinsert or table.insert



local pawnApiPresent = type(_G.PawnGetItemData) == "function" and type(_G.PawnGetSingleValueFromItem) == "function" and
    type(_G.PawnGetScaleColor) == "function"
local pawnClassicVer = rawget(_G, "PawnClassicLastUpdatedVersion")
local pawnRetailVer = rawget(_G, "PawnLastUpdatedVersion")
local isPawnLoaded = (pawnClassicVer and pawnClassicVer >= 2.0538) or (pawnRetailVer and pawnRetailVer >= 2.0) or
    pawnApiPresent

local Detours = LibStub("LibDetours-1.0")
local CI = LibStub("LibForeverInspector")

local L = _G.TACOTIP_LOCALE
local TT = _G[addOnName]

if (not TT) then
    TT = {}
    rawset(_G, addOnName, TT)
end

-- Safe-call wrapper. Routes errors through Blizzard's geterrorhandler()
-- global so they are captured by error display addons (BugSack, !Swatter,
-- BugGrabber, etc.) instead of silently breaking the options panel.
local function safeCall(fn, ...)
    return xpcall(fn, geterrorhandler(), ...)
end

-- The player's GUID, as a value a comparison is allowed to consume.
--
-- UnitGUID is documented Nilable and SecretWhenUnitIdentityRestricted
-- (Blizzard_APIDocumentationGenerated/UnitDocumentation.lua at the pin), so the
-- result can arrive secret, and a secret value RAISES on `==` -- which is what
-- every reader here does with it. main.lua's TT.safeUnitGUID is the boundary
-- helper: pcall'd, type()-nil-tested and secrecy-tested, answering nil when the
-- value cannot be read, so these "is this me" checks simply find no match
-- instead of raising inside the options panel. options.lua never defines or
-- replaces the helper, and it loads BEFORE main.lua, so it is resolved at call
-- time rather than bound here; an absent helper means no highlight.
---@return string?
local function playerGUID()
    local safeGUID = TT and TT.safeUnitGUID
    if (type(safeGUID) ~= "function") then
        return nil
    end
    return safeGUID("player")
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

-- File-local so SafeSanitizeConfig and the options Refresh can read single
-- fields without allocating a 60-key table per call. GetDefaults hands out a
-- shallow COPY: resetCfg assigns its result straight to TacoTipConfig and then
-- writes conf_version into it, so a shared table would let a reset mutate the
-- defaults themselves.
local DEFAULTS = {
    color_class = true,
    show_titles = true,
    show_guild_name = true,
    show_guild_rank = true,
    show_talents = true,
    show_gs_player = true,
    show_gs_character = true,
    show_gs_items = true,
    show_gs_items_hs = false,
    show_avg_ilvl = true,
    hide_in_combat = false,
    combat_modifier = "NONE",
    show_item_level = true,
    tip_style = 2,
    show_target = true,
    show_pawn_player = true,
    show_team = true,
    show_class_icon = true,
    class_icon_size = 20,
    show_pvp_icon = false,
    guild_rank_alt_style = true,
    show_hp_bar = true,
    show_power_bar = true,
    shaman_blue = true,
    tooltip_border_use_class = true,
    tooltip_border_item_quality = true,
    tooltip_background_use_class = false,
    tooltip_border_color_r = 1,
    tooltip_border_color_g = 1,
    tooltip_border_color_b = 1,
    tooltip_border_alpha = 0.9,
    tooltip_background_color_r = 0,
    tooltip_background_color_g = 0,
    tooltip_background_color_b = 0,
    tooltip_background_alpha = 0.85,
    tooltip_background_texture = "Interface\\Tooltips\\UI-Tooltip-Background",
    tooltip_border_texture = "Interface\\Tooltips\\UI-Tooltip-Border",
    tooltip_border_edge_size = 20,
    tooltip_scale = 1,
    tooltip_portrait = true,
    tooltip_portrait_scale = 1,
    tooltip_portrait_3d = true,
    tooltip_portrait_invert_side = false,
    tooltip_portrait_zoom = 0.75,
    tooltip_font = "Fonts\\FRIZQT__.TTF",
    tooltip_font_size = 12,
    tooltip_bar_texture = "Interface\\TargetingFrame\\UI-TargetingFrame-BarFill",
    instant_fade = false,
    anchor_mouse = false,
    anchor_mouse_world = true,
    anchor_mouse_spells = true,
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
    show_honor_rank = false,
    show_ilvl_inline = false,
    show_realm = false,
    show_role_icon = true,
    show_separators = false,
    tooltip_delay = 0,
    tooltip_max_width = 0,
    custom_anchor = "TOPLEFT",
    progression_chat = true,
    progression_sound = true,
    show_minimap = true,
}

function TT:GetDefaults()
    local copy = {}
    for k, v in pairs(DEFAULTS) do
        copy[k] = v
    end
    return copy
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
    if (self.InvalidateResolvedMediaCache) then
        self:InvalidateResolvedMediaCache()
    end
end

-- Validates and repairs common saved-variable corruption patterns that can
-- cause the tooltip to break silently (wrong types, out-of-range values).
-- Called after defaults are applied every load, so even partially-corrupt
-- configs are repaired without requiring the user to delete SavedVariables.
function TT:SafeSanitizeConfig(config)
    if (not config or type(config) ~= "table") then
        return
    end

    local defaults = DEFAULTS

    -- Type-check known boolean keys and reset to default if they are not
    -- actually a boolean.  WoW's saved-variable system sometimes serialises
    -- "true"/"false" strings instead of real booleans.
    local booleanKeys = {
        "color_class", "show_titles", "show_guild_name", "show_guild_rank",
        "show_talents", "show_gs_player", "show_gs_character", "show_gs_items",
        "show_gs_items_hs", "show_avg_ilvl", "hide_in_combat", "show_item_level",
        "show_target", "show_pawn_player", "show_team",
        "show_class_icon", "show_pvp_icon", "guild_rank_alt_style",
        "show_hp_bar", "show_power_bar", "shaman_blue", "tooltip_border_use_class",
        "tooltip_border_item_quality",
        "tooltip_background_use_class", "tooltip_portrait", "tooltip_portrait_3d",
        "tooltip_portrait_invert_side",
        "instant_fade", "anchor_mouse", "anchor_mouse_world",
        "anchor_mouse_spells", "unlock_info_position", "show_achievement_points",
        "show_honor_rank", "show_ilvl_inline", "show_realm",
        "show_role_icon", "show_separators",
        "progression_chat", "progression_sound", "show_minimap"
    }
    for _, key in ipairs(booleanKeys) do
        local val = config[key]
        if (val ~= nil and type(val) ~= "boolean") then
            config[key] = defaults[key]
        end
    end

    if (config.combat_modifier ~= "NONE" and config.combat_modifier ~= "SHIFT"
            and config.combat_modifier ~= "CTRL" and config.combat_modifier ~= "ALT") then
        config.combat_modifier = defaults.combat_modifier
    end
    if (config.recentCache ~= nil and type(config.recentCache) ~= "table") then
        config.recentCache = nil
    end

    -- Sanitise numeric slider/range keys so out-of-bounds values from
    -- corruption or old versions do not cause layout or logic issues.
    if (type(config.class_icon_size) ~= "number" or config.class_icon_size < 8 or config.class_icon_size > 32) then
        config.class_icon_size = defaults.class_icon_size
    end
    if (type(config.tooltip_portrait_scale) ~= "number" or config.tooltip_portrait_scale < 0.5 or config.tooltip_portrait_scale > 2) then
        config.tooltip_portrait_scale = defaults.tooltip_portrait_scale
    end
    if (type(config.tooltip_scale) ~= "number" or config.tooltip_scale < 0.5 or config.tooltip_scale > 2) then
        config.tooltip_scale = defaults.tooltip_scale
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
    if (config.tooltip_border_texture == "Tooltip enlarged" or config.tooltip_border_texture == nil) then
        config.tooltip_border_texture = defaults.tooltip_border_texture
    end
    -- Character/inspect overlay offsets: typed edit boxes historically wrote
    -- unclamped integers; repair out-of-range or corrupt saved values to the
    -- same bounds the offset sliders enforce (options.lua MODERN_OPTION_SLIDER_*).
    for _, key in ipairs {
        "character_gs_offset_x", "character_gs_offset_y",
        "character_ilvl_offset_x", "character_ilvl_offset_y",
        "inspect_gs_offset_x", "inspect_gs_offset_y",
        "inspect_ilvl_offset_x", "inspect_ilvl_offset_y",
    } do
        local val = config[key]
        if (type(val) ~= "number" or val ~= val or val == math.huge or val == -math.huge
                or val < -300 or val > 300) then
            config[key] = defaults[key] or 0
        end
    end
    -- NOTE: guild_rank_style was removed in v0.6.x — migrated to guild_rank_alt_style.
    -- Old saved-values are silently ignored by the memoized default merge above.
    -- Color channel bounds (0-1 floats)
    for _, key in ipairs {
        "tooltip_border_color_r", "tooltip_border_color_g", "tooltip_border_color_b",
        "tooltip_background_color_r", "tooltip_background_color_g", "tooltip_background_color_b",
    } do
        local val = config[key]
        if (type(val) ~= "number" or val < 0 or val > 1) then
            config[key] = defaults[key]
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
        if (GameTooltip and type(GameTooltip.FadeOut) == "function") then
            Detours:SecureHook(TT, GameTooltip, "FadeOut", function(tooltipFrame)
                if (tooltipFrame and type(tooltipFrame.Hide) == "function") then
                    tooltipFrame:Hide()
                end
            end)
        end
    else
        Detours:SecureUnhook(TT, GameTooltip, "FadeOut")
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
    -- Invalidated here, at the choke point, because the two reset routes do NOT
    -- agree: the reset button goes on to call RefreshOptionsUI -> modernGetConfig
    -- (which invalidates), while /tacotip reset only refreshes the root page. So
    -- the memoised font/bar/background/border stayed applied for the rest of the
    -- session after a slash-command reset.
    if (TT.InvalidateResolvedMediaCache) then
        TT:InvalidateResolvedMediaCache()
    end
    if (TT.ApplyTooltipScale) then
        TT:ApplyTooltipScale()
    end
    if (TT.SetMinimapIconShown) then
        TacoTipConfig.minimap = { hide = false }
        TT:SetMinimapIconShown(true)
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
        -- This is not a timing problem. TacoTip_CustomPosEnable is defined at the
        -- very end of main.lua, the last file in the toc, so it can only be
        -- missing because loading raised an error before reaching it. Telling the
        -- user to /reload would be advice that cannot possibly help, so name the
        -- actual stage that was reached instead.
        print("|cff59f0dcTacoTip:|r Tooltip mover unavailable: main.lua stopped loading.")
        if (TT and TT.LOAD_STAGE) then
            print("|cff59f0dcTacoTip:|r Last stage reached: " .. tostring(TT.LOAD_STAGE))
        end
        print("|cff59f0dcTacoTip:|r Run /tacotip diag for the full report.")
    end
end

local dashboard

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
                print("|cff59f0dcTacoTip:|r " .. L["Custom tooltip position disabled."])
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
            print("|cff59f0dcTacoTip:|r " .. L["Configuration has been reset to default."])
        elseif (cmd == "save") then
            if (TacoTipDragButton and TacoTipDragButton:IsShown()) then
                TacoTipDragButton:_Save()
            end
        elseif (cmd == "help") then
            print("|cff59f0dcTacoTip:|r /tacotip - open TacoTip options")
            print("|cff59f0dcTacoTip:|r /tacotip minimap - toggle TacoTip minimap icon")
            print("|cff59f0dcTacoTip:|r /tacotip custom - show the tooltip mover")
            print("|cff59f0dcTacoTip:|r /tacotip reset - reset TacoTip settings")
            print("|cff59f0dcTacoTip:|r " .. L["TEXT_HELP_ANCHOR"])
        elseif (cmd == "minimap" or cmd == "icon") then
            local nextState = (TacoTipConfig.show_minimap == false)
            TacoTipConfig.show_minimap = nextState
            if (TT and TT.SetMinimapIconShown) then
                TT:SetMinimapIconShown(nextState)
            end
            if (optionsFrame and optionsFrame:IsShown() and optionsFrame.Refresh) then
                optionsFrame:Refresh()
            end
            if (dashboard and dashboard:IsShown() and dashboard.RefreshAll) then
                dashboard:RefreshAll()
            end
            print("|cff59f0dcTacoTip:|r Minimap button " .. (nextState and "shown." or "hidden."))
        elseif (strfind(cmd, "anchor")) then
            if (strfind(cmd, "topleft")) then
                TacoTipConfig.custom_anchor = "TOPLEFT"
                print("|cff59f0dcTacoTip:|r " .. L["Custom position anchor set"] .. ": 'TOPLEFT'")
            elseif (strfind(cmd, "topright")) then
                TacoTipConfig.custom_anchor = "TOPRIGHT"
                print("|cff59f0dcTacoTip:|r " .. L["Custom position anchor set"] .. ": 'TOPRIGHT'")
            elseif (strfind(cmd, "bottomleft")) then
                TacoTipConfig.custom_anchor = "BOTTOMLEFT"
                print("|cff59f0dcTacoTip:|r " .. L["Custom position anchor set"] .. ": 'BOTTOMLEFT'")
            elseif (strfind(cmd, "bottomright")) then
                TacoTipConfig.custom_anchor = "BOTTOMRIGHT"
                print("|cff59f0dcTacoTip:|r " .. L["Custom position anchor set"] .. ": 'BOTTOMRIGHT'")
            elseif (strfind(cmd, "center")) then
                TacoTipConfig.custom_anchor = "CENTER"
                print("|cff59f0dcTacoTip:|r " .. L["Custom position anchor set"] .. ": 'CENTER'")
            else
                print("|cff59f0dcTacoTip:|r " .. L["TEXT_HELP_ANCHOR"])
            end
        elseif (cmd == "lb" or cmd == "rank" or cmd == "ranks" or cmd == "leaderboard") then
            if (type(_G.TacoTipExtrasToggleLeaderboard) == "function") then
                _G.TacoTipExtrasToggleLeaderboard()
            else
                print("|cff59f0dcTacoTip:|r TacoTip Extras leaderboard is not available.")
            end
        elseif (cmd == "diag" or cmd == "diagnostics") then
            -- Load report. Exists because the mover and the tooltip pipeline are
            -- both defined at the very end of main.lua, so a single load-time
            -- error disables them while leaving the options frame fully
            -- functional -- a state that is otherwise impossible to explain from
            -- the UI. See TT:PrintDiagnostics in main.lua.
            if (TT and TT.PrintDiagnostics) then
                -- Last-resort containment: the collector and renderer each guard
                -- their own sections, but a broken diagnostics module must never
                -- take the slash command down with it.
                local ok, err = pcall(TT.PrintDiagnostics, TT)
                if (not ok) then
                    print("|cff59f0dcTacoTip:|r diagnostics failed: " .. tostring(err))
                    if (TT and TT.LOAD_STAGE) then
                        print("|cff59f0dcTacoTip:|r Last stage reached: " .. tostring(TT.LOAD_STAGE))
                    end
                    if (CI) then
                        print(string.format("|cff59f0dcTacoTip:|r Client family: %s, Interface: %s",
                            tostring(CI.family), tostring(CI.interfaceVersion)))
                    end
                end
            else
                print("|cff59f0dcTacoTip:|r main.lua did not finish loading, so diagnostics are unavailable.")
                if (TT and TT.LOAD_STAGE) then
                    print("|cff59f0dcTacoTip:|r Last stage reached: " .. tostring(TT.LOAD_STAGE))
                end
                if (CI) then
                    print(string.format("|cff59f0dcTacoTip:|r Client family: %s, Interface: %s", tostring(CI.family),
                        tostring(CI.interfaceVersion)))
                end
                print("|cff59f0dcTacoTip:|r Enable a Lua error handler (BugSack/Swatter) and /reload.")
            end
        elseif (cmd == "report" or cmd == "export") then
            if (TT and TT.ShowStandaloneDashboard) then
                pcall(TT.ShowStandaloneDashboard, TT, "diagnostics")
            end
            if (dashboard and dashboard.ExportDiagnostics) then
                pcall(dashboard.ExportDiagnostics, dashboard)
            end
        elseif (cmd == "discord" or cmd == "community") then
            print("|cff59f0dcTacoTip:|r Join the TacoTip Discord community: |cffffb81chttps://discord.gg/JuVJBwXqv|r")
            if (TT and TT.ShowStandaloneDashboard) then
                pcall(TT.ShowStandaloneDashboard, TT, "community")
            end
        elseif (cmd == "diag ui" or cmd == "diagui") then
            if (TT and TT.ShowStandaloneDashboard) then
                pcall(TT.ShowStandaloneDashboard, TT, "diagnostics")
            end
        else
            if (TT and TT.ToggleStandaloneDashboard) then
                pcall(TT.ToggleStandaloneDashboard, TT)
            elseif (openOptionsPanel) then
                openOptionsPanel()
            else
                print("|cff59f0dcTacoTip:|r /tacotip custom - show the tooltip mover")
            end
        end
    end)
end

registerSlashCommands()

-- main frame
optionsFrame = CreateFrame("Frame", "TacoTipOptions")
optionsFrame.name = addOnTitle or "TacoTip"
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
        -- "Blizzard_Settings" / "Blizzard_SettingsDefinitions" only exist on
        -- Retail. The Classic clients (and Forever) ship Blizzard_Settings_Shared
        -- and Blizzard_SettingsDefinitions_Shared instead, and all of these are
        -- already non-LoadOnDemand, so this is belt-and-braces rather than a
        -- hard requirement.
        pcall(LoadAddOn, "Blizzard_Settings")
        pcall(LoadAddOn, "Blizzard_Settings_Shared")
        pcall(LoadAddOn, "Blizzard_SettingsDefinitions")
        pcall(LoadAddOn, "Blizzard_SettingsDefinitions_Shared")
    end
    return _G.Settings and _G.Settings.RegisterCanvasLayoutCategory and _G.Settings.RegisterAddOnCategory
end

local function registerSettingsSubcategories()
    if (settingsSubcategoriesRegistered or not addOnOptionsCategory or not _G.Settings or not _G.Settings.RegisterCanvasLayoutSubcategory) then
        return settingsSubcategoriesRegistered
    end

    local ok = pcall(function()
        modernSubcategories.tooltips = modernSubcategories.tooltips or
            _G.Settings.RegisterCanvasLayoutSubcategory(addOnOptionsCategory, optionsPages.tooltips,
                optionsPages.tooltips.name)
        modernSubcategories.positioning = modernSubcategories.positioning or
            _G.Settings.RegisterCanvasLayoutSubcategory(addOnOptionsCategory, optionsPages.positioning,
                optionsPages.positioning.name)
        modernSubcategories.characterInspect = modernSubcategories.characterInspect or
            _G.Settings.RegisterCanvasLayoutSubcategory(addOnOptionsCategory, optionsPages.characterInspect,
                optionsPages.characterInspect.name)
    end)

    settingsSubcategoriesRegistered = ok and modernSubcategories.tooltips and modernSubcategories.positioning and
        modernSubcategories.characterInspect and true or settingsSubcategoriesRegistered
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
            addOnOptionsCategory = addOnOptionsCategory or
                _G.Settings.RegisterCanvasLayoutCategory(optionsFrame, optionsFrame.name)
            if (addOnOptionsCategory) then
                _G.Settings.RegisterAddOnCategory(addOnOptionsCategory)
                settingsCategoryRegistered = true
                registeredAny = true
            end
        end

        if (settingsCategoryRegistered) then
            registerSettingsSubcategories()
        end

        if (not settingsCategoryRegistered) then
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
    offsetEditors = {},
    offsetSliders = {}
}

local modernGetConfig
local modernRefreshLockPositionToggle
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
    if (not texturePath or texturePath == "") then
        return label
    end
    return string.format("|T%s:132:14:0:0|t %s", texturePath, label)
end

-- Choice lists are memoised alongside the resolved values. Only the resolved
-- values used to be, so every options-panel Refresh -- fired by ~16 different
-- controls, and by every hover in the Tooltips page -- reallocated ~207 tables
-- and re-sorted four lists. Safe to hand out the SAME instance: the consumers
-- (dropDown:SetValues, SetValue, toggleMediaPicker) only replace or read the
-- reference, and a SharedMedia registration invalidates through the same call.
local cachedFontChoices, cachedBarChoices, cachedBackgroundChoices, cachedBorderChoices

local function invalidateCachedChoiceLists()
    cachedFontChoices = nil
    cachedBarChoices = nil
    cachedBackgroundChoices = nil
    cachedBorderChoices = nil
end

function TT:GetTooltipFontChoices()
    if (cachedFontChoices) then
        return cachedFontChoices
    end
    local media = getSharedMediaLibrary()
    local seen = {}
    local choices = {}

    local displayLocale = (self.GetDisplayLocale and self:GetDisplayLocale())
        or ((type(GetLocale) == "function") and GetLocale() or "enUS")
    local builtins = TT.builtinTooltipFonts
    if (TT.filterBuiltinTooltipFonts) then
        builtins = TT.filterBuiltinTooltipFonts(builtins, displayLocale)
    end
    for _, entry in ipairs(builtins) do
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

    cachedFontChoices = sortMediaChoices(choices)
    return cachedFontChoices
end

function TT:GetTooltipStatusBarTextureChoices()
    if (cachedBarChoices) then
        return cachedBarChoices
    end
    local media = getSharedMediaLibrary()
    local seen = {}
    local choices = {}

    for _, entry in ipairs(TT.builtinStatusBarTextures) do
        seen[entry.value] = true
        table.insert(choices,
            { value = entry.value, text = entry.text, menuText = buildTexturePreviewText(entry.value, entry.text) })
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

    cachedBarChoices = sortMediaChoices(choices)
    return cachedBarChoices
end

function TT:GetTooltipBackgroundChoices()
    if (cachedBackgroundChoices) then
        return cachedBackgroundChoices
    end
    local media = getSharedMediaLibrary()
    local seen = {}
    local choices = {}

    for _, entry in ipairs(TT.builtinTooltipBackgrounds) do
        seen[entry.value] = true
        table.insert(choices,
            { value = entry.value, text = entry.text, menuText = buildTexturePreviewText(entry.value, entry.text) })
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

    cachedBackgroundChoices = sortMediaChoices(choices)
    return cachedBackgroundChoices
end

function TT:GetTooltipBorderChoices()
    if (cachedBorderChoices) then
        return cachedBorderChoices
    end
    local media = getSharedMediaLibrary()
    local seen = {}
    local choices = {}

    for _, entry in ipairs(TT.builtinTooltipBorders) do
        seen[entry.value] = true
        -- edgeSize is carried per entry. Verified tooltip borders are not all the
        -- same size -- UI-Tooltip-Border is 128x16 (slices at 16) while the themed
        -- Azerite / Corrupted / Maw borders are 256x32 (slices at 32) -- so one
        -- global edge size cannot draw all of them correctly.
        table.insert(choices,
            {
                value = entry.value,
                text = entry.text,
                edgeSize = entry.edgeSize,
                menuText = buildTexturePreviewText(entry.value, entry.text)
            })
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

    cachedBorderChoices = sortMediaChoices(choices)
    return cachedBorderChoices
end

local function resolveConfiguredMediaValue(choices, configuredValue, fallbackValue)
    if (configuredValue) then
        for _, entry in ipairs(choices) do
            if (entry.value == configuredValue or entry.text == configuredValue) then
                return entry.value
            end
        end
    end
    return fallbackValue
end

local cachedResolvedFont = nil
local cachedResolvedBar = nil
local cachedResolvedBackground = nil
local cachedResolvedBorder = nil

-- The declared edge size is a property of the border CHOICE, not of the player's
-- config, so it is cached against the resolved border path. It has to be: the
-- resolver is called from the backdrop signature check on every mouseover, and
-- an uncached lookup rebuilt and re-sorted the whole border list each time --
-- ~110 allocations per hover, on the frame the player is waiting for.
local cachedDeclaredEdgeSize, cachedDeclaredEdgeSizeFor = nil, nil

-- The resolved values depend on TacoTipConfig, so they are cleared by every
-- options interaction.
function TT:InvalidateResolvedTooltipValues()
    cachedResolvedFont = nil
    cachedResolvedBar = nil
    cachedResolvedBackground = nil
    cachedResolvedBorder = nil
    cachedDeclaredEdgeSize = nil
    cachedDeclaredEdgeSizeFor = nil
end

-- The FULL clear, for the one thing the choice lists actually depend on: a new
-- SharedMedia registration, which main.lua's RegisterCallback routes here. An
-- options interaction must NOT reach this -- the lists are derived from the
-- builtin tables and the media registry, neither of which changes when the
-- player moves a slider, so clearing them per interaction would rebuild and
-- re-sort all four lists on every click for nothing.
function TT:InvalidateResolvedMediaCache()
    TT:InvalidateResolvedTooltipValues()
    invalidateCachedChoiceLists()
end

-- The client swaps the FONT FILE per alphabet: FRIZQT__.TTF is the roman face,
-- FRIZQT___CYR.TTF carries Cyrillic, 2002.TTF Korean, ARKai_T.ttf Simplified
-- Chinese and blei00d.TTF Traditional Chinese (verified in the client source:
-- Blizzard_Fonts_Shared/Mainline/GameFonts.xml and Shared/Fonts.xml, every
-- FontFamily declares one <Member alphabet="..."> per file). Forcing the roman
-- file on a translated client is exactly what renders a missing-glyph box per
-- character -- the "I see squares sometime" report -- because SetFont with a
-- raw path bypasses the client's alphabet fallback.
local LOCALE_FONT_PATHS = {
    ruRU = "Fonts\\FRIZQT___CYR.TTF",
    koKR = "Fonts\\2002.TTF",
    zhCN = "Fonts\\ARKai_T.ttf",
    zhTW = "Fonts\\blei00d.TTF",
}

-- Font for the language actually being displayed.
--
-- applyTooltipFonts re-fonts the CLIENT's own lines too (name / race / level /
-- guild), and those are in the client language. So the client's alphabet wins
-- whenever it is non-roman: a zhCN client must keep its Chinese face even when
-- the addon language is overridden to Russian. Only a roman client (which loses
-- nothing, because the CYR/CJK faces also carry Latin) may follow a non-roman
-- addon language.
-- Accented Latin clients must not follow a Russian override onto the Cyrillic
-- face: FRIZQT___CYR has no é/ï/ö (LibSharedMedia's coverage table), so every
-- accented client line would be a box. FRIZQT is the safer face there; a
-- player who wants the override can still pick a font explicitly.
local ACCENTED_ROMAN_LOCALES = {
    deDE = true, frFR = true, esES = true, esMX = true, itIT = true, ptBR = true,
}
-- Override faces that cannot carry accented Latin. FRIZQT___CYR has partial
-- Latin (no é/ï/ö); bLEI00D does not cover the accented de/en/es/fr/it/pt set
-- (the Latin column of LibSharedMedia's coverage table) though it has basic
-- ASCII. 2002 (koKR) and ARKai (zhCN) do carry accented Latin, so those
-- overrides are safe.
local ACCENTED_UNSAFE_OVERRIDES = {
    ruRU = true,
    zhTW = true,
}

-- The locale whose script the picker and the default face must serve. The
-- client wins when it has a non-roman alphabet; otherwise an addon-language
-- override decides, except when the override face cannot carry accented Latin
-- (ruRU/zhTW): the accented-Latin client keeps its own face.
function TT:GetDisplayLocale()
    local client = (type(GetLocale) == "function") and GetLocale() or "enUS"
    if (LOCALE_FONT_PATHS[client]) then
        return client
    end
    local active = _G.TACOTIP_ACTIVE_LOCALE
    if (type(active) == "string" and LOCALE_FONT_PATHS[active]) then
        if (ACCENTED_ROMAN_LOCALES[client] and ACCENTED_UNSAFE_OVERRIDES[active]) then
            return client
        end
        return active
    end
    return client
end

function TT:GetLocaleFontPath()
    local displayLocale = self:GetDisplayLocale()
    return LOCALE_FONT_PATHS[displayLocale] or "Fonts\\FRIZQT__.TTF"
end

function TT:GetResolvedTooltipFont()
    if (not cachedResolvedFont) then
        local localeFont = self:GetLocaleFontPath()
        local configured = TacoTipConfig and TacoTipConfig.tooltip_font
        -- The shipped default is the roman face. Treat it as "client default"
        -- rather than as an explicit choice: on a Russian/Korean/Chinese
        -- client every character outside Latin would otherwise be a box. Any
        -- other saved selection is the player's explicit pick and is honoured.
        if (configured == nil or configured == "" or configured == "Fonts\\FRIZQT__.TTF") then
            configured = localeFont
        end
        cachedResolvedFont = resolveConfiguredMediaValue(self:GetTooltipFontChoices(),
            configured, localeFont)
    end
    return cachedResolvedFont
end

function TT:GetResolvedTooltipStatusBarTexture()
    if (not cachedResolvedBar) then
        cachedResolvedBar = resolveConfiguredMediaValue(self:GetTooltipStatusBarTextureChoices(),
            TacoTipConfig and TacoTipConfig.tooltip_bar_texture,
            "Interface\\TargetingFrame\\UI-TargetingFrame-BarFill")
    end
    return cachedResolvedBar
end

function TT:GetResolvedTooltipBackground()
    if (not cachedResolvedBackground) then
        cachedResolvedBackground = resolveConfiguredMediaValue(self:GetTooltipBackgroundChoices(),
            TacoTipConfig and TacoTipConfig.tooltip_background_texture,
            "Interface\\Tooltips\\UI-Tooltip-Background")
    end
    return cachedResolvedBackground
end

function TT:GetResolvedTooltipBorder()
    if (not cachedResolvedBorder) then
        cachedResolvedBorder = resolveConfiguredMediaValue(self:GetTooltipBorderChoices(),
            TacoTipConfig and TacoTipConfig.tooltip_border_texture,
            (TT.GetDefaultTooltipBorder and TT:GetDefaultTooltipBorder())
            or "Interface\\Tooltips\\UI-Tooltip-Border")
    end
    return cachedResolvedBorder
end

-- The edge size to actually draw with. A choice may declare its own (the themed
-- tooltip borders are 256x32 and need 32); otherwise the player's own setting is
-- used. Resolution lives here rather than at the draw site so the backdrop code
-- never has to know that a border can carry its own geometry.
function TT:GetResolvedTooltipBorderEdgeSize()
    local borderTexture = TT.GetResolvedTooltipBorder and TT:GetResolvedTooltipBorder()
    if (borderTexture) then
        if (borderTexture == cachedDeclaredEdgeSizeFor) then
            -- Same choice as last time, so the answer cannot have changed.
            -- Only a border that DECLARES a size is memoised; the config fallback
            -- below must stay live so the thickness slider keeps working.
            if (cachedDeclaredEdgeSize) then
                return cachedDeclaredEdgeSize
            end
        else
            local ok, choices = pcall(function() return TT:GetTooltipBorderChoices() end)
            if (ok and choices) then
                for _, entry in ipairs(choices) do
                    if (entry.value == borderTexture and entry.edgeSize) then
                        cachedDeclaredEdgeSize = entry.edgeSize
                        cachedDeclaredEdgeSizeFor = borderTexture
                        return entry.edgeSize
                    end
                end
            end
            cachedDeclaredEdgeSize, cachedDeclaredEdgeSizeFor = nil, borderTexture
        end
    end
    local configured = TacoTipConfig and TacoTipConfig.tooltip_border_edge_size
    if (type(configured) == "number" and configured >= 4 and configured <= 48) then
        -- The slider is integer-stepped, but a hand-edited SavedVariables value
        -- can carry a fraction and SetBackdrop edge sizes must be whole pixels.
        -- A per-entry edgeSize literal is already integral, so flooring here
        -- cannot change a declared size.
        return math.floor(configured)
    end
    return 16
end

-- The edge size a border choice declares for itself, or nil when it defers to
-- the player's setting. The options UI asks this so the thickness slider can
-- disable itself for the themed 256x32 borders, which slice at 32 and ignore it
-- entirely -- otherwise the control advertises authority it does not have.
function TT:GetDeclaredTooltipBorderEdgeSize()
    -- Prime the cache rather than duplicating the lookup: this is called from the
    -- options Refresh, which the resolver result is what we actually want to
    -- report on.
    TT:GetResolvedTooltipBorderEdgeSize()
    return cachedDeclaredEdgeSize
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
        GameTooltip:SetText(text, 1, 1, 1, 1)
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
    if (frame.SetScript) then
        frame:SetScript("OnEnter", function(self)
            showHoverTooltip(self, title, text)
        end)
        frame:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end
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
    check.label = _G[check:GetName() .. "Text"] or check:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    if (check.label and check.label.SetText) then
        check.label:SetText(label)
    end
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

local pickerFrame

local function getOrCreateMediaPickerFrame()
    if (pickerFrame) then
        return pickerFrame
    end

    local backdropTemplate = _G.BackdropTemplateMixin and "BackdropTemplate" or nil
    local frame = CreateFrame("Frame", "TacoTipMediaPickerFrame", UIParent, backdropTemplate)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(100)
    frame:SetSize(310, 300)
    if (frame.SetBackdrop) then
        frame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        frame:SetBackdropColor(0.06, 0.06, 0.08, 0.96)
        frame:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
    end
    frame:EnableMouse(true)
    frame:Hide()

    local title = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -8)
    title:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -28, -8)
    title:SetJustifyH("LEFT")
    title:SetHeight(16)
    frame.title = title

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
    closeBtn:SetSize(22, 22)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    local scrollFrame = CreateFrame("ScrollFrame", "TacoTipMediaPickerScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -28)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -28, 8)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(256, 100)
    scrollFrame:SetScrollChild(content)
    frame.scrollFrame = scrollFrame
    frame.content = content

    frame.buttons = {}

    local function onMouseWheel(_, delta)
        local current = scrollFrame:GetVerticalScroll()
        local maxScroll = scrollFrame:GetVerticalScrollRange()
        local step = 44
        if (delta > 0) then
            scrollFrame:SetVerticalScroll(math.max(0, current - step))
        else
            scrollFrame:SetVerticalScroll(math.min(maxScroll, current + step))
        end
    end
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", onMouseWheel)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", onMouseWheel)
    content:EnableMouseWheel(true)
    content:SetScript("OnMouseWheel", onMouseWheel)

    if (_G.UISpecialFrames) then
        tinsert(_G.UISpecialFrames, "TacoTipMediaPickerFrame")
    end

    frame:SetScript("OnUpdate", function(self)
        if (not self.activeDropDown or not self.activeDropDown:IsVisible()) then
            self:Hide()
        end
    end)
    frame:SetScript("OnHide", function(self)
        self.activeDropDown = nil
    end)

    pickerFrame = frame
    return pickerFrame
end

local function toggleMediaPicker(dropDown)
    if (not dropDown or dropDown.isDisabled or (dropDown.IsEnabled and not dropDown:IsEnabled())) then
        return
    end
    if (_G.CloseDropDownMenus) then
        _G.CloseDropDownMenus()
    end

    local frame = getOrCreateMediaPickerFrame()
    if (frame:IsShown() and frame.activeDropDown == dropDown) then
        frame:Hide()
        return
    end

    frame.activeDropDown = dropDown
    local labelText = dropDown.label and dropDown.label:GetText()
    frame.title:SetText((labelText and labelText ~= "") and labelText or "Select Option")

    local values = dropDown.values or {}
    local rowHeight = 22
    local totalHeight = #values * (rowHeight + 2)

    frame.content:SetHeight(math.max(totalHeight, 10))
    frame.scrollFrame:SetVerticalScroll(0)

    frame:ClearAllPoints()
    local _, y = dropDown:GetCenter()
    local screenHeight = (UIParent and UIParent:GetHeight()) or 768
    if (y and y < (screenHeight / 2)) then
        frame:SetPoint("BOTTOMLEFT", dropDown, "TOPLEFT", 16, 0)
    else
        frame:SetPoint("TOPLEFT", dropDown, "BOTTOMLEFT", 16, 0)
    end

    local backdropTemplate = _G.BackdropTemplateMixin and "BackdropTemplate" or nil
    local controls = modernOptionsState and modernOptionsState.controls

    for i, option in ipairs(values) do
        local btn = frame.buttons[i]
        if (not btn) then
            btn = CreateFrame("Button", nil, frame.content, backdropTemplate)
            btn:SetHeight(rowHeight)
            btn:SetPoint("LEFT", frame.content, "LEFT", 0, 0)
            btn:SetPoint("RIGHT", frame.content, "RIGHT", 0, 0)

            local bg = btn:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints(btn)
            btn.bg = bg

            local txt = btn:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            txt:SetPoint("LEFT", btn, "LEFT", 8, 0)
            txt:SetPoint("RIGHT", btn, "RIGHT", -24, 0)
            txt:SetJustifyH("LEFT")
            txt:SetShadowOffset(1, -1)
            txt:SetShadowColor(0, 0, 0, 1)
            btn.txt = txt

            local check = btn:CreateTexture(nil, "OVERLAY")
            check:SetSize(14, 14)
            check:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
            check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
            btn.check = check

            btn:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")

            btn:EnableMouseWheel(true)
            btn:SetScript("OnMouseWheel", function(_, delta)
                local current = frame.scrollFrame:GetVerticalScroll()
                local maxScroll = frame.scrollFrame:GetVerticalScrollRange()
                local step = 44
                if (delta > 0) then
                    frame.scrollFrame:SetVerticalScroll(math.max(0, current - step))
                else
                    frame.scrollFrame:SetVerticalScroll(math.min(maxScroll, current + step))
                end
            end)

            frame.buttons[i] = btn
        end

        btn:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, -((i - 1) * (rowHeight + 2)))
        btn:SetPoint("TOPRIGHT", frame.content, "TOPRIGHT", 0, -((i - 1) * (rowHeight + 2)))
        btn.option = option

        local val = option.value
        local isSelected = (val == dropDown.selectedValue)
        btn.check:SetShown(isSelected)

        local textureSet = false
        -- Texture preview is opt-in per dropdown. Font values are file paths
        -- too; feeding one to Texture:SetTexture makes the client draw an
        -- unloadable texture as a solid green block.
        if (dropDown.isTexturePicker and type(val) == "string" and val:len() > 0) then
            if (val:find("\\") or val:find("/")) then
                local isBorderChoice = (controls and dropDown == controls.tooltipBorderTextureChoice) or
                    (val:find("Border") or val:find("border") or val:find("Edge") or val:find("edge"))
                if (isBorderChoice and btn.SetBackdrop) then
                    btn.bg:SetTexture(nil)
                    btn:SetBackdrop({
                        edgeFile = val,
                        edgeSize = 10,
                        insets = { left = 2, right = 2, top = 2, bottom = 2 },
                    })
                    if (isSelected) then
                        btn:SetBackdropBorderColor(0.9, 0.75, 0.2, 1)
                    else
                        btn:SetBackdropBorderColor(0.7, 0.7, 0.75, 0.9)
                    end
                    textureSet = true
                else
                    if (btn.SetBackdrop) then btn:SetBackdrop(nil) end
                    btn.bg:SetTexture(val)
                    btn.bg:SetTexCoord(0, 1, 0, 1)
                    btn.bg:SetVertexColor(0.85, 0.85, 0.85, 0.8)
                    textureSet = true
                end
            end
        end

        if (not textureSet) then
            if (btn.SetBackdrop) then btn:SetBackdrop(nil) end
            btn.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
            if (isSelected) then
                btn.bg:SetVertexColor(0.2, 0.35, 0.55, 0.7)
            elseif (i % 2 == 0) then
                btn.bg:SetVertexColor(0.12, 0.12, 0.15, 0.6)
            else
                btn.bg:SetVertexColor(0.08, 0.08, 0.1, 0.6)
            end
        end

        if (dropDown.isFontPicker and type(val) == "string" and val ~= "") then
            -- Preview each font in its own face. A refused path falls back to
            -- the default row font instead of breaking the list.
            local okCall, applied = pcall(btn.txt.SetFont, btn.txt, val, 12, "")
            if (not okCall or applied == false) then
                btn.txt:SetFontObject("GameFontHighlightSmall")
            end
        else
            -- The row buttons are shared by every dropdown, so a font preview
            -- must not leak into the next picker.
            btn.txt:SetFontObject("GameFontHighlightSmall")
        end

        btn.txt:SetText(option.menuText or option.text or tostring(val or ""))

        btn:SetScript("OnClick", function()
            dropDown:SetValue(option.value)
            if (dropDown.onValueChanged) then
                safeCall(dropDown.onValueChanged, option.value)
            end
            frame:Hide()
        end)

        btn:Show()
    end

    for i = #values + 1, #frame.buttons do
        frame.buttons[i]:Hide()
    end

    frame:Show()
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
    dropDown.onValueChanged = onValueChanged
    local contentParent = parent or _G.UIParent
    dropDown.label = contentParent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    dropDown.label:SetJustifyH("LEFT")
    dropDown.label:SetText(label or "")
    dropDown.description = description and createWrappedText(contentParent, "GameFontHighlightSmall", 280, description) or nil

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

    local btnName = globalName .. "Button"
    local arrowButton = _G[btnName]
    if (arrowButton) then
        local function openPicker()
            toggleMediaPicker(dropDown)
        end
        -- The modern pair (Forever/Retail) activates the template arrow from
        -- DropDownMenuButtonMixin:OnMouseDown; the classic family uses the XML
        -- OnClick. Replace exactly the handler this client installed and clear
        -- the other, or one click opens the stock menu and the custom picker.
        local stockMouseDown = arrowButton.GetScript and arrowButton:GetScript("OnMouseDown")
        if (stockMouseDown) then
            arrowButton:SetScript("OnMouseDown", openPicker)
            arrowButton:SetScript("OnClick", nil)
        else
            arrowButton:SetScript("OnClick", openPicker)
            arrowButton:SetScript("OnMouseDown", nil)
        end
    end
    dropDown:SetScript("OnMouseDown", function()
        toggleMediaPicker(dropDown)
    end)

    dropDown.SetValues = function(self, newValues)
        self.values = newValues or {}
    end

    dropDown.SetValue = function(self, value)
        self.selectedValue = value
        _G.UIDropDownMenu_SetSelectedValue(self, value)
        for _, option in ipairs(self.values or values or {}) do
            if (option.value == value or option.text == value) then
                _G.UIDropDownMenu_SetText(self, option.selectedText or option.text or option.menuText or "")
                return
            end
        end
        local firstValue = (self.values or values or {})[1]
        _G.UIDropDownMenu_SetText(self,
            firstValue and (firstValue.selectedText or firstValue.text or firstValue.menuText) or "")
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

local function createOptionsSlider(parent, globalName, label, tooltipDescription, onValueChanged, minValue, maxValue,
                                   step)
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
    -- OptionsSliderTemplate provides Text/Low/High on every client we ship to,
    -- but a missing one would abort the whole page build (the caller is
    -- safeCall-wrapped, so the symptom is a silently blank options page that
    -- re-fails on every OnShow). Create fallbacks instead, matching what the
    -- checkbox builder at createOptionsCheckbox already does.
    local sname = slider:GetName()
    slider.label = _G[sname .. "Text"]
        or slider:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    slider.low = _G[sname .. "Low"]
        or slider:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    slider.high = _G[sname .. "High"]
        or slider:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
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

local function openColorPicker(initialR, initialG, initialB, onChanged)
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
    -- The Classic ColorPickerFrame.xml reads "swatchFunc", not "func"
    -- (Blizzard_FrameXML/Classic/ColorPickerFrame.xml:81-83). The previous
    -- rawsets used "func", so this fallback would have done nothing if it were
    -- ever reached. It is currently unreachable -- SetupColorPickerAndShow
    -- exists on all five clients, so the modern branch above always wins -- but
    -- it should be correct in case that changes.
    pcall(rawset, colorPickerFrame, "swatchFunc", applyCurrentColor)
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
        openColorPicker(control.r, control.g, control.b, function(r, g, b)
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
    { value = "TOPLEFT",     text = L["OPTIONS_ANCHOR_TOPLEFT"] or "Top Left",         tooltip = L["OPTIONS_ANCHOR_TOPLEFT_DESC"] },
    { value = "TOPRIGHT",    text = L["OPTIONS_ANCHOR_TOPRIGHT"] or "Top Right",       tooltip = L["OPTIONS_ANCHOR_TOPRIGHT_DESC"] },
    { value = "BOTTOMLEFT",  text = L["OPTIONS_ANCHOR_BOTTOMLEFT"] or "Bottom Left",   tooltip = L["OPTIONS_ANCHOR_BOTTOMLEFT_DESC"] },
    { value = "BOTTOMRIGHT", text = L["OPTIONS_ANCHOR_BOTTOMRIGHT"] or "Bottom Right", tooltip = L["OPTIONS_ANCHOR_BOTTOMRIGHT_DESC"] },
    { value = "CENTER",      text = L["OPTIONS_ANCHOR_CENTER"] or "Center",            tooltip = L["OPTIONS_ANCHOR_CENTER_DESC"] }
}

local modernStyleOptions = {
    { value = 1, text = L["FULL"],         tooltip = L["Always FULL"] },
    { value = 2, text = L["COMPACT/FULL"], tooltip = L["Default COMPACT, hold SHIFT for FULL"] },
    { value = 3, text = L["COMPACT"],      tooltip = L["Always COMPACT"] },
    { value = 4, text = L["MINI/FULL"],    tooltip = L["Default MINI, hold SHIFT for FULL"] },
    { value = 5, text = L["MINI"],         tooltip = L["Always MINI"] }
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

local DISCORD_INVITE_URL = "https://discord.gg/JuVJBwXqv"
local CURSEFORGE_URL = "https://www.curseforge.com/wow/addons/tacotip-gearscore"
local EXTRAS_URL = "https://www.curseforge.com/wow/addons/tacotip-extras"
local WHITE8X8 = "Interface\\Buttons\\WHITE8X8"
local LOGO_TEXTURE_PATH = "Interface\\AddOns\\" .. tostring(addOnName or "TacoTip") .. "\\logo.tga"

-- Enterprise dark theme palette derived from logo.png (Charcoal Slate, Taco Gold, Lime / Green-Yellow)
local DASH_THEME = {
    windowBg = { 0.105, 0.108, 0.112, 0.98 },
    headerBg = { 0.080, 0.082, 0.085, 1.00 },
    sidebarBg = { 0.090, 0.092, 0.095, 1.00 },
    cardBg = { 0.135, 0.138, 0.140, 0.96 },
    cardHoverBg = { 0.170, 0.178, 0.160, 0.98 },
    cardActiveBg = { 0.185, 0.190, 0.135, 0.98 },
    inputBg = { 0.065, 0.068, 0.070, 1.00 },
    borderSubtle = { 0.220, 0.225, 0.230, 1.00 },
    borderGold = { 1.000, 0.780, 0.120, 1.00 },
    borderEmerald = { 0.680, 0.860, 0.200, 1.00 },
    borderDiscord = { 0.380, 0.420, 0.460, 1.00 },
    borderAmber = { 0.920, 0.700, 0.140, 1.00 },
    borderCoral = { 0.906, 0.320, 0.240, 1.00 },
    gold = { 1.000, 0.780, 0.120 },
    emerald = { 0.680, 0.860, 0.200 },
    lime = { 0.720, 0.880, 0.180 },
    greenYellow = { 0.780, 0.900, 0.220 },
    cyan = { 0.750, 0.880, 0.250 },
    amber = { 0.920, 0.700, 0.140 },
    coral = { 0.906, 0.320, 0.240 },
    textPrimary = { 0.96, 0.97, 0.98 },
    textMuted = { 0.62, 0.65, 0.68 },
    textDisabled = { 0.40, 0.42, 0.44 },
}

local function paintFlatBox(frame, bg, border)
    if (not frame) then
        return
    end
    if (not frame._flatBg) then
        local tex = frame:CreateTexture(nil, "BACKGROUND")
        tex:SetTexture(WHITE8X8)
        tex:SetAllPoints(frame)
        frame._flatBg = tex
    end
    if (bg) then
        frame._flatBg:SetVertexColor(bg[1] or 0, bg[2] or 0, bg[3] or 0, bg[4] or 1)
    end
    if (border) then
        if (not frame._flatBorders) then
            local bTop = frame:CreateTexture(nil, "BORDER")
            bTop:SetTexture(WHITE8X8)
            bTop:SetHeight(1)
            bTop:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
            bTop:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)

            local bBot = frame:CreateTexture(nil, "BORDER")
            bBot:SetTexture(WHITE8X8)
            bBot:SetHeight(1)
            bBot:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
            bBot:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)

            local bLeft = frame:CreateTexture(nil, "BORDER")
            bLeft:SetTexture(WHITE8X8)
            bLeft:SetWidth(1)
            bLeft:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
            bLeft:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)

            local bRight = frame:CreateTexture(nil, "BORDER")
            bRight:SetTexture(WHITE8X8)
            bRight:SetWidth(1)
            bRight:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
            bRight:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)

            frame._flatBorders = { bTop, bBot, bLeft, bRight }
        end
        local br, bgC, bb, ba = border[1] or 0.2, border[2] or 0.2, border[3] or 0.25, border[4] or 1
        for _, bTex in ipairs(frame._flatBorders) do
            bTex:SetVertexColor(br, bgC, bb, ba)
        end
    end
    frame.SetFlatColors = function(self, nextBg, nextBorder)
        if (nextBg and self._flatBg) then
            self._flatBg:SetVertexColor(nextBg[1] or 0, nextBg[2] or 0, nextBg[3] or 0, nextBg[4] or 1)
        end
        if (nextBorder and self._flatBorders) then
            local r, g, b, a = nextBorder[1] or 0.2, nextBorder[2] or 0.2, nextBorder[3] or 0.25, nextBorder[4] or 1
            for _, bTex in ipairs(self._flatBorders) do
                bTex:SetVertexColor(r, g, b, a)
            end
        end
    end
end

-- Interactive Frame-based flat button. Using a Frame with OnMouseDown rather
-- than a Button on the Blizzard root canvas keeps the harness button-probe
-- walk untouched while providing crisp modern hover/click states in-game.
local function createFlatActionCard(parent, width, height, labelText, variant, onClick, tooltipTitle, tooltipDesc)
    local card = CreateFrame("Frame", nil, parent)
    card:SetSize(width, height)
    card:EnableMouse(true)

    local normalBg, hoverBg, normalBorder, hoverBorder
    if (variant == "emerald") then
        normalBg = { 0.16, 0.25, 0.10, 0.96 }
        hoverBg = { 0.22, 0.35, 0.14, 1.00 }
        normalBorder = DASH_THEME.borderEmerald
        hoverBorder = { 0.75, 0.92, 0.24, 1.00 }
    elseif (variant == "gold") then
        normalBg = { 0.26, 0.20, 0.06, 0.96 }
        hoverBg = { 0.36, 0.28, 0.08, 1.00 }
        normalBorder = DASH_THEME.borderGold
        hoverBorder = { 1.00, 0.84, 0.32, 1.00 }
    elseif (variant == "discord") then
        normalBg = { 0.15, 0.17, 0.21, 0.96 }
        hoverBg = { 0.20, 0.23, 0.28, 1.00 }
        normalBorder = DASH_THEME.borderDiscord
        hoverBorder = { 0.60, 0.68, 0.78, 1.00 }
    elseif (variant == "danger") then
        normalBg = { 0.16, 0.11, 0.11, 0.96 }
        hoverBg = { 0.26, 0.14, 0.12, 1.00 }
        normalBorder = DASH_THEME.borderSubtle
        hoverBorder = DASH_THEME.borderAmber
    else
        normalBg = { 0.135, 0.138, 0.140, 0.96 }
        hoverBg = { 0.180, 0.188, 0.170, 1.00 }
        normalBorder = DASH_THEME.borderSubtle
        hoverBorder = DASH_THEME.borderEmerald
    end

    paintFlatBox(card, normalBg, normalBorder)

    local txt = card:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    txt:SetPoint("LEFT", card, "LEFT", 8, 0)
    txt:SetPoint("RIGHT", card, "RIGHT", -8, 0)
    txt:SetJustifyH("CENTER")
    txt:SetText(labelText or "")
    card.text = txt

    card:SetScript("OnEnter", function(self)
        self:SetFlatColors(hoverBg, hoverBorder)
        if (tooltipDesc and tooltipDesc ~= "") then
            showHoverTooltip(self, tooltipTitle or labelText, tooltipDesc)
        end
    end)
    card:SetScript("OnLeave", function(self)
        self:SetFlatColors(normalBg, normalBorder)
        if (tooltipDesc and tooltipDesc ~= "") then
            GameTooltip:Hide()
        end
    end)
    card:SetScript("OnMouseDown", function(self)
        if (onClick) then
            safeCall(onClick, self)
        end
    end)

    return card
end

local function getClientFamilyDisplayLabel()
    if (not CI) then
        return "WoW"
    end
    local fam = tostring(CI.family or "")
    if (fam == "classic_era") then
        return "Classic Era (11509)"
    elseif (fam == "classic_anniversary") then
        return "TBC Anniversary (20506)"
    elseif (fam == "classic_titan") then
        return "WotLK Titanforge (38002)"
    elseif (fam == "forever") then
        return "WoW Forever (16001)"
    elseif (fam == "retail" or fam == "live") then
        return "Retail (120105)"
    end
    return fam ~= "" and fam or "WoW"
end

local function buildRootPage()
    if (modernOptionsState.pages.rootBuilt) then
        return
    end

    local panel = optionsFrame
    local controls = modernOptionsState.controls
    paintFlatBox(panel, DASH_THEME.windowBg, DASH_THEME.borderSubtle)

    -- Hero Banner Card (Logo + Version + 200k Milestone + Dashboard / Discord / Diag Launchers)
    local heroCard = CreateFrame("Frame", nil, panel)
    heroCard:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -12)
    heroCard:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -14, -12)
    heroCard:SetHeight(92)
    paintFlatBox(heroCard, DASH_THEME.headerBg, DASH_THEME.borderGold)

    local logoIcon = heroCard:CreateTexture(nil, "ARTWORK")
    logoIcon:SetSize(36, 36)
    logoIcon:SetPoint("TOPLEFT", heroCard, "TOPLEFT", 12, -12)
    logoIcon:SetTexture(LOGO_TEXTURE_PATH)

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", heroCard, "TOPLEFT", 56, -12)
    title:SetText("|cffffffffTACO|cffffb81cT|cff7be046I|cff2ecc71P|r  |cffb4e634" ..
    addOnTitle .. " v" .. addOnVersion .. "|r")

    local description = createWrappedText(panel, "GameFontHighlightSmall", 540,
        "|cffffd100200,000+ Downloads Milestone!|r Thank you to our community! " ..
        (L["OPTIONS_ROOT_DESCRIPTION"] or L["TEXT_OPT_DESC"] or ""))
    description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)

    local openDashCard = createFlatActionCard(heroCard, 195, 24,
        "|cffffd100Open TacoTip Dashboard (/tt)|r", "gold",
        function()
            if (TT and TT.ShowStandaloneDashboard) then
                TT:ShowStandaloneDashboard("general")
            end
        end,
        "TacoTip Settings Dashboard",
        "Open the full standalone TacoTip Settings window with 6 tabs, instant search, visual presets, and live diagnostics.")
    openDashCard:SetPoint("BOTTOMLEFT", heroCard, "BOTTOMLEFT", 12, 10)

    local openDiscordCard = createFlatActionCard(heroCard, 210, 24,
        "|cffb4e634Discord:|r |cffffffffdiscord.gg/JuVJBwXqv|r", "discord",
        function()
            print("|cffb4e634TacoTip:|r Join the TacoTip Discord community: |cffffd100" .. DISCORD_INVITE_URL .. "|r")
            if (TT and TT.ShowStandaloneDashboard) then
                TT:ShowStandaloneDashboard("community")
            end
        end,
        "Join TacoTip Discord Community",
        "Click to open the copyable Discord invite link (" .. DISCORD_INVITE_URL .. ") and community hub.")
    openDiscordCard:SetPoint("LEFT", openDashCard, "RIGHT", 8, 0)

    local openDiagCard = createFlatActionCard(heroCard, 155, 24,
        "|cffb4e634Live Diagnostics|r", "emerald",
        function()
            if (TT and TT.ShowStandaloneDashboard) then
                TT:ShowStandaloneDashboard("diagnostics")
            elseif (TT and TT.PrintDiagnostics) then
                TT:PrintDiagnostics()
            end
        end,
        "System Diagnostics & Bug Report",
        "Inspect live addon health, unit range status, inspect cache metrics, and copy a diagnostic report.")
    openDiagCard:SetPoint("LEFT", openDiscordCard, "RIGHT", 8, 0)

    local quickActions = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    quickActions:SetPoint("TOPLEFT", heroCard, "BOTTOMLEFT", 2, -12)
    quickActions:SetText(L["OPTIONS_ROOT_QUICK_ACTIONS"] or "Quick Actions")

    local openMoverButton = createOptionsButton(panel, nil, L["OPTIONS_OPEN_TOOLTIP_MOVER"] or L["Mover"], 180, 24,
        function()
            showTooltipMover()
        end,
        L["OPTIONS_OPEN_TOOLTIP_MOVER_DESC"] or
        "Show the live tooltip mover so you can drag and save a custom tooltip position.")
    openMoverButton:SetPoint("TOPLEFT", quickActions, "BOTTOMLEFT", 0, -6)

    local resetButton = createOptionsButton(panel, nil, L["Reset configuration"], 180, 24, function()
            resetCfg()
            if (TT.RefreshOptionsUI) then
                TT:RefreshOptionsUI()
            end
        end,
        L["OPTIONS_RESET_CONFIGURATION_DESC"] or
        "Restore TacoTip settings to their defaults, including tooltip appearance and overlay positions.")
    resetButton:SetPoint("LEFT", openMoverButton, "RIGHT", 12, 0)

    local function getRootSummaryText()
        local tooltipMode = TacoTipConfig.anchor_mouse and
            (L["OPTIONS_STATUS_MOUSE_ANCHOR"] or "Tooltips are anchored to the mouse cursor.") or
            (TacoTipConfig.custom_pos and (L["OPTIONS_STATUS_CUSTOM_POSITION"] or "Tooltips use your saved custom position.") or (L["OPTIONS_STATUS_DEFAULT_POSITION"] or "Tooltips use Blizzard's default placement."))
        local localeSummary = getSavedLocaleOverride() and getLocaleDisplayName(getSavedLocaleOverride()) or
            string.format(L["OPTIONS_LANGUAGE_CLIENT_DEFAULT"] or "Client default (%s)",
                getLocaleDisplayName(GetLocale() or "enUS"))
        local lines = {
            "|cffb4e634TacoTip Dashboard:|r Type |cffffd100/tt|r or click the button above for the full standalone dashboard.",
            "|cffb4e634•|r " .. string.format(L["OPTIONS_STATUS_LANGUAGE"] or "Addon language: %s.", localeSummary) ..
            "  |cffb4e634•|r " .. tooltipMode,
            "|cffb4e634•|r Discord: |cffffd100" .. DISCORD_INVITE_URL .. "|r"
        }
        return table.concat(lines, "\n")
    end

    controls.rootStyleChoice = createOptionsDropdown(panel, nil, L["Tooltip Style"],
        L["OPTIONS_TOOLTIP_STYLE_DESC"] or
        "Choose how much detail TacoTip shows by default.",
        modernStyleOptions, function(value)
            TacoTipConfig.tip_style = value
            if (TT and TT.RefreshOpenUnitTooltip) then
                TT:RefreshOpenUnitTooltip()
            end
            if (TT and TT.RefreshOptionsUI) then
                TT:RefreshOptionsUI()
            end
        end)
    controls.rootStyleChoice.label:SetPoint("TOPLEFT", openMoverButton, "BOTTOMLEFT", 0, -14)
    controls.rootStyleChoice:SetPoint("TOPLEFT", controls.rootStyleChoice.label, "BOTTOMLEFT", -16, -2)
    if (controls.rootStyleChoice.description) then
        controls.rootStyleChoice.description:ClearAllPoints()
        controls.rootStyleChoice.description:SetPoint("TOPLEFT", controls.rootStyleChoice, "BOTTOMLEFT", 20, -2)
    end

    local styleBottom = controls.rootStyleChoice.description or controls.rootStyleChoice

    -- Core Tooltip Settings Section
    local coreHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    coreHeader:SetPoint("TOPLEFT", styleBottom, "BOTTOMLEFT", controls.rootStyleChoice.description and -20 or 0, -12)
    coreHeader:SetText(L["OPTIONS_SECTION_UNIT_TOOLTIPS"] or "Unit tooltip content")

    controls.rootShowGsPlayer = createOptionsCheckbox(panel, nil,
        L["OPTIONS_SHOW_PLAYER_GS"] or "Show Player GearScore",
        L["OPTIONS_SHOW_PLAYER_GS_DESC"] or "Adds GearScore to player tooltips.",
        function(_, value)
            TacoTipConfig.show_gs_player = value
            modernGetConfig()
        end)
    controls.rootShowGsPlayer:SetPoint("TOPLEFT", coreHeader, "BOTTOMLEFT", -2, -6)

    controls.rootShowAvgIlvl = createOptionsCheckbox(panel, nil,
        L["OPTIONS_CHARACTER_ILVL_LABEL"] or "Show Average Item Level",
        L["OPTIONS_CHARACTER_ILVL_DESC"] or "Show average item level on tooltips and frames.",
        function(_, value)
            TacoTipConfig.show_avg_ilvl = value
            refreshOverlayPositions()
            modernGetConfig()
        end)
    controls.rootShowAvgIlvl:SetPoint("TOPLEFT", controls.rootShowGsPlayer, "BOTTOMLEFT", 0, -6)

    controls.rootShowTalents = createOptionsCheckbox(panel, nil,
        L["Talents"] or "Show Talents & Spec",
        L["Show talents and specialization in tooltips"],
        function(_, value)
            TacoTipConfig.show_talents = value
            modernGetConfig()
        end)
    controls.rootShowTalents:SetPoint("TOPLEFT", controls.rootShowAvgIlvl, "BOTTOMLEFT", 0, -6)

    controls.rootColorClass = createOptionsCheckbox(panel, nil,
        L["Class Color"] or "Class Color Names",
        L["Color class names in tooltips"],
        function(_, value)
            TacoTipConfig.color_class = value
            modernGetConfig()
        end)
    controls.rootColorClass:SetPoint("TOPLEFT", controls.rootShowTalents, "BOTTOMLEFT", 0, -6)

    controls.rootShowGuildName = createOptionsCheckbox(panel, nil,
        L["Guild Name"] or "Show Guild Name",
        L["Show guild name in tooltips"],
        function(_, value)
            TacoTipConfig.show_guild_name = value
            modernGetConfig()
        end)
    controls.rootShowGuildName:SetPoint("TOPLEFT", coreHeader, "BOTTOMLEFT", 310, -6)

    controls.rootShowHpBar = createOptionsCheckbox(panel, nil,
        L["Health Bar"] or "Show Health Bar",
        L["Show unit's health bar under tooltip"],
        function(_, value)
            TacoTipConfig.show_hp_bar = value
            modernGetConfig()
        end)
    controls.rootShowHpBar:SetPoint("TOPLEFT", controls.rootShowGuildName, "BOTTOMLEFT", 0, -6)

    controls.rootShowPowerBar = createOptionsCheckbox(panel, nil,
        L["Power Bar"] or "Show Power Bar",
        L["Show unit's power bar under tooltip"],
        function(_, value)
            TacoTipConfig.show_power_bar = value
            if (GameTooltip and GameTooltip:IsShown() and TT.ApplyTooltipAppearance
                    and type(GameTooltip.GetUnit) == "function") then
                local ok, _, unit = pcall(GameTooltip.GetUnit, GameTooltip)
                if (ok and unit) then
                    TT:ApplyTooltipAppearance(GameTooltip, unit)
                end
            end
            modernGetConfig()
        end)
    controls.rootShowPowerBar:SetPoint("TOPLEFT", controls.rootShowHpBar, "BOTTOMLEFT", 0, -6)

    controls.rootLanguage = createOptionsDropdown(panel, nil, L["OPTIONS_LANGUAGE_LABEL"] or "Addon language",
        L["OPTIONS_LANGUAGE_DESC"] or
        "Use your game client's locale by default, or choose another supported TacoTip locale. Reload the UI after changing this setting.",
        buildLocaleDropdownChoices(), function(value)
            if (value == CLIENT_DEFAULT_LOCALE_VALUE) then
                TacoTipConfig.locale_override = nil
            else
                TacoTipConfig.locale_override = value
            end
            print("|cff59f0dcTacoTip:|r " ..
                (L["OPTIONS_LANGUAGE_RELOAD_HINT"] or "Language preference saved. Reload the UI to apply it."))
            if (TT.RefreshOptionsUI) then
                TT:RefreshOptionsUI()
            end
        end)
    controls.rootLanguage.label:SetPoint("TOPLEFT", controls.rootColorClass, "BOTTOMLEFT", 2, -12)
    controls.rootLanguage:SetPoint("TOPLEFT", controls.rootLanguage.label, "BOTTOMLEFT", -16, -2)
    if (controls.rootLanguage.description) then
        controls.rootLanguage.description:ClearAllPoints()
        controls.rootLanguage.description:SetPoint("TOPLEFT", controls.rootLanguage, "BOTTOMLEFT", 20, -2)
    end

    local behaviorHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    local langBottom = controls.rootLanguage.description or controls.rootLanguage
    behaviorHeader:SetPoint("TOPLEFT", langBottom, "BOTTOMLEFT", controls.rootLanguage.description and -20 or 0, -12)
    behaviorHeader:SetText(L["OPTIONS_ROOT_BEHAVIOR_HEADER"] or "Behavior & client settings")

    controls.rootHideInCombat = createOptionsCheckbox(panel, nil,
        L["OPTIONS_HIDE_IN_COMBAT_LABEL"] or "Hide tooltips in combat",
        L["OPTIONS_HIDE_IN_COMBAT_DESC"] or
        "Hide unit tooltips while you are engaged in combat. Optionally hold a modifier key below to still show them.", function(_, value)
            TacoTipConfig.hide_in_combat = value
            if (controls.rootCombatModifier and controls.rootCombatModifier.SetDisabled) then
                controls.rootCombatModifier:SetDisabled(not value)
            end
            modernGetConfig()
        end)
    controls.rootHideInCombat:SetPoint("TOPLEFT", behaviorHeader, "BOTTOMLEFT", -2, -6)

    controls.rootUberTips = createOptionsCheckbox(panel, nil, L["Enhanced Tooltips"], L["TEXT_OPT_UBERTIPS"],
        function(_, value)
            SetCVar("UberTooltips", value and "1" or "0")
            modernGetConfig()
        end)
    controls.rootUberTips:SetPoint("TOPLEFT", behaviorHeader, "BOTTOMLEFT", 310, -6)

    controls.rootChatClassColors = createOptionsCheckbox(panel, nil, L["Chat Class Colors"],
        L["Color names by class in chat windows"], function(_, value)
            SetCVar("chatClassColorOverride", value and "0" or "1")
            modernGetConfig()
        end)
    controls.rootChatClassColors:SetPoint("TOPLEFT", controls.rootHideInCombat, "BOTTOMLEFT", 0, -6)

    controls.rootShowAchievementPoints = createOptionsCheckbox(panel, nil, L["Show Achievement Points"],
        L["OPTIONS_ACHIEVEMENT_DESC"] or "Display player's total achievement points.",
        function(_, value)
            TacoTipConfig.show_achievement_points = value
            modernGetConfig()
        end)
    controls.rootShowAchievementPoints:SetPoint("TOPLEFT", controls.rootUberTips, "BOTTOMLEFT", 0, -6)

    controls.rootCombatModifier = createOptionsDropdown(panel, nil,
        "Still Show Hidden Tips with Modifier",
        "Choose a modifier key (Shift, Ctrl, or Alt) to temporarily show unit tooltips while in combat.",
        {
            { value = "NONE", text = "None" },
            { value = "SHIFT", text = "Shift" },
            { value = "CTRL", text = "Ctrl" },
            { value = "ALT", text = "Alt" },
        },
        function(value)
            TacoTipConfig.combat_modifier = value
            modernGetConfig()
        end)
    controls.rootCombatModifier.label:SetPoint("TOPLEFT", controls.rootChatClassColors, "BOTTOMLEFT", 2, -10)
    controls.rootCombatModifier:SetPoint("TOPLEFT", controls.rootCombatModifier.label, "BOTTOMLEFT", -16, -2)
    if (controls.rootCombatModifier.description) then
        controls.rootCombatModifier.description:ClearAllPoints()
        controls.rootCombatModifier.description:SetPoint("TOPLEFT", controls.rootCombatModifier, "BOTTOMLEFT", 20, -2)
    end

    modernOptionsState.rootSummary = createWrappedText(panel, "GameFontHighlightSmall", 620, getRootSummaryText())
    modernOptionsState.rootSummary:SetPoint("TOPLEFT",
        controls.rootCombatModifier.description or controls.rootCombatModifier, "BOTTOMLEFT", -2, -10)

    panel.Refresh = function()
        modernOptionsState.rootSummary:SetText(getRootSummaryText())
        controls.rootLanguage:SetValues(buildLocaleDropdownChoices())
        controls.rootLanguage:SetValue(getSavedLocaleOverride() or CLIENT_DEFAULT_LOCALE_VALUE)
        controls.rootStyleChoice:SetValue(TacoTipConfig.tip_style or 2)
        if (controls.rootShowGsPlayer) then controls.rootShowGsPlayer:SetChecked(TacoTipConfig.show_gs_player) end
        if (controls.rootShowAvgIlvl) then controls.rootShowAvgIlvl:SetChecked(TacoTipConfig.show_avg_ilvl) end
        if (controls.rootShowTalents) then controls.rootShowTalents:SetChecked(TacoTipConfig.show_talents) end
        if (controls.rootColorClass) then controls.rootColorClass:SetChecked(TacoTipConfig.color_class) end
        if (controls.rootShowGuildName) then controls.rootShowGuildName:SetChecked(TacoTipConfig.show_guild_name) end
        if (controls.rootShowHpBar) then controls.rootShowHpBar:SetChecked(TacoTipConfig.show_hp_bar) end
        if (controls.rootShowPowerBar) then controls.rootShowPowerBar:SetChecked(TacoTipConfig.show_power_bar) end
        controls.rootHideInCombat:SetChecked(TacoTipConfig.hide_in_combat)
        if (controls.rootCombatModifier) then
            controls.rootCombatModifier:SetValue(TacoTipConfig.combat_modifier or "NONE")
            if (controls.rootCombatModifier.SetDisabled) then
                controls.rootCombatModifier:SetDisabled(not TacoTipConfig.hide_in_combat)
            end
        end
        controls.rootUberTips:SetChecked(GetCVar("UberTooltips") == "1")
        controls.rootChatClassColors:SetChecked(GetCVar("chatClassColorOverride") == "0")
        -- Achievements are Retail-only for now. WotLK Titanforge and WoW
        -- Forever also expose the APIs, but the operator wants the row there
        -- kept off until that is settled.
        local hasAchievements = CI and CI.IsRetail and CI:IsRetail() and true or false
        if (hasAchievements) then
            controls.rootShowAchievementPoints:SetChecked(TacoTipConfig.show_achievement_points)
            controls.rootShowAchievementPoints:SetDisabled(false)
        else
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
    local header, headerDesc = createSectionHeader(content, L["OPTIONS_PAGE_TOOLTIPS"] or "Tooltips",
        L["OPTIONS_TOOLTIPS_PAGE_DESC"] or "Tune the information TacoTip adds to player and item tooltips.", 560)
    builder:AddAnchor(header, 24)
    if (headerDesc) then
        builder:AddAnchor(headerDesc, headerDesc:GetStringHeight() + 10)
    end

    local controls = modernOptionsState.controls

    local function updateControlDependencies()
        local hasGuildName = TacoTipConfig.show_guild_name
        if (controls.showGuildRanks) then
            controls.showGuildRanks:SetDisabled(not hasGuildName)
        end
        if (controls.guildRankStyleChoice) then
            controls.guildRankStyleChoice:SetDisabled(not (hasGuildName and TacoTipConfig.show_guild_rank))
        end

        local hasGSItems = TacoTipConfig.show_gs_items
        if (controls.hunterScoreItems) then
            controls.hunterScoreItems:SetDisabled(not hasGSItems)
        end

        local hasPortrait = TacoTipConfig.tooltip_portrait
        if (controls.tooltipPortraitScale) then
            controls.tooltipPortraitScale:SetDisabled(not hasPortrait)
        end
        if (controls.tooltipPortrait3D) then
            controls.tooltipPortrait3D:SetDisabled(not hasPortrait)
        end
        if (controls.tooltipPortraitInvertSide) then
            controls.tooltipPortraitInvertSide:SetDisabled(not hasPortrait)
        end
        if (controls.tooltipPortraitZoom) then
            controls.tooltipPortraitZoom:SetDisabled(not (hasPortrait and TacoTipConfig.tooltip_portrait_3d))
        end

        local hasClassIcon = TacoTipConfig.show_class_icon
        if (controls.classIconSize) then
            controls.classIconSize:SetDisabled(not hasClassIcon)
        end
    end

    -- ========================================================================
    -- Section 1: Scaling, Presets & General Layout
    -- ========================================================================
    controls.tooltipScale = createOptionsSlider(content, nil,
        "Global tooltip scale",
        "Scale the entire tooltip (GameTooltip, compare tooltips, and item tooltips). Default is 100%.",
        function(value)
            TacoTipConfig.tooltip_scale = value / 100
            if (TT.ApplyTooltipScale) then
                TT:ApplyTooltipScale()
            end
        end, 50, 200, 5)
    controls.tooltipScale:SetPoint("TOPLEFT", content, "TOPLEFT", 16, builder.y)
    controls.tooltipScale.valueText:SetPoint("LEFT", controls.tooltipScale, "RIGHT", 8, 0)
    builder.y = builder.y - 56

    controls.tooltipPortraitScale = createOptionsSlider(content, nil,
        L["OPTIONS_TOOLTIP_PORTRAIT_SCALE"] or "Portrait scale",
        L["OPTIONS_TOOLTIP_PORTRAIT_SCALE_DESC"] or
        "Scale the portrait shown next to unit tooltips. Default is 100%.",
        function(value)
            TacoTipConfig.tooltip_portrait_scale = value / 100
        end, 50, 200, 5)
    controls.tooltipPortraitScale:SetPoint("TOPLEFT", content, "TOPLEFT", 16, builder.y)
    controls.tooltipPortraitScale.valueText:SetPoint("LEFT", controls.tooltipPortraitScale, "RIGHT", 8, 0)
    builder.y = builder.y - 56

    controls.styleChoice = createOptionsDropdown(content, nil, L["Tooltip Style"],
        L["OPTIONS_TOOLTIP_STYLE_DESC"] or "Choose how much detail TacoTip shows by default.",
        modernStyleOptions, function(value)
            TacoTipConfig.tip_style = value
            if (TT and TT.RefreshOpenUnitTooltip) then
                TT:RefreshOpenUnitTooltip()
            end
        end)
    builder.y = builder.y - layoutDropdownControl(content, controls.styleChoice, builder.y, 12)

    controls.tooltipFontChoice = createOptionsDropdown(content, nil, L["OPTIONS_TOOLTIP_FONT"] or "Tooltip font",
        L["OPTIONS_TOOLTIP_FONT_DESC"] or
        "Choose the font used by tooltip text. SharedMedia fonts are included automatically when available.",
        TT:GetTooltipFontChoices(), function(value)
            TacoTipConfig.tooltip_font = value
            modernGetConfig()
        end)
    controls.tooltipFontChoice.isFontPicker = true
    builder.y = builder.y - layoutDropdownControl(content, controls.tooltipFontChoice, builder.y, 12)

    controls.tooltipFontSize = createOptionsSlider(content, nil, L["OPTIONS_TOOLTIP_FONT_SIZE"] or "Tooltip text size",
        L["OPTIONS_TOOLTIP_FONT_SIZE_DESC"] or
        "Change the size of the tooltip text without affecting the rest of the UI.",
        function(value)
            TacoTipConfig.tooltip_font_size = value
        end, 8, 20, 1)
    controls.tooltipFontSize:SetPoint("TOPLEFT", content, "TOPLEFT", 16, builder.y)
    controls.tooltipFontSize.valueText:SetPoint("LEFT", controls.tooltipFontSize, "RIGHT", 8, 0)

    controls.tooltipMaxWidth = createOptionsSlider(content, nil, L["OPTIONS_TOOLTIP_MAX_WIDTH"] or "Tooltip max width",
        L["OPTIONS_TOOLTIP_MAX_WIDTH_DESC"] or
        "Set a maximum width for the tooltip to prevent it from becoming too wide with long names. Set to 0 for no limit.",
        function(value)
            TacoTipConfig.tooltip_max_width = value
        end, 0, 500, 10)
    controls.tooltipMaxWidth:SetPoint("TOPLEFT", content, "TOPLEFT", 260, builder.y)
    controls.tooltipMaxWidth.valueText:SetPoint("LEFT", controls.tooltipMaxWidth, "RIGHT", 8, 0)
    builder.y = builder.y - 56

    controls.showSeparators = createOptionsCheckbox(content, nil,
        L["OPTIONS_SHOW_SEPARATORS"] or "Show section separators",
        L["OPTIONS_SHOW_SEPARATORS_DESC"] or
        "Add thin horizontal lines between logical sections of the tooltip for visual clarity.",
        function(_, value)
            TacoTipConfig.show_separators = value
        end)
    controls.showSeparators:SetPoint("TOPLEFT", content, "TOPLEFT", 16, builder.y)

    controls.showMinimap = createOptionsCheckbox(content, nil,
        "Show minimap button",
        "Display a TacoTip minimap button via LibDBIcon for quick access to settings and diagnostics.",
        function(_, value)
            TacoTipConfig.show_minimap = value
            if (TT and TT.SetMinimapIconShown) then
                TT:SetMinimapIconShown(value)
            end
        end)
    controls.showMinimap:SetPoint("TOPLEFT", content, "TOPLEFT", 260, builder.y)
    builder.y = builder.y - 36

    -- ========================================================================
    -- Section 2: Player & Unit Content
    -- ========================================================================
    local unitHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    unitHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 16, builder.y)
    unitHeader:SetText(L["OPTIONS_SECTION_UNIT_TOOLTIPS"] or "Unit tooltip content")
    builder.y = builder.y - 24

    controls.useClassColors = createOptionsCheckbox(content, nil, L["Class Color"], L["Color class names in tooltips"],
        function(_, value)
            TacoTipConfig.color_class = value
        end)
    controls.useClassColors:SetPoint("TOPLEFT", content, "TOPLEFT", 16, builder.y)

    controls.shamanBlue = createOptionsCheckbox(content, nil, L["OPTIONS_SHAMAN_BLUE"] or "Shaman Blue",
        L["OPTIONS_SHAMAN_BLUE_DESC"] or "Use blue instead of pink for Shaman class color.",
        function(_, value)
            TacoTipConfig.shaman_blue = value
        end)
    controls.shamanBlue:SetPoint("TOPLEFT", content, "TOPLEFT", 260, builder.y)
    if (not (CI and CI.IsClassic and CI:IsClassic())) then
        controls.shamanBlue:Hide()
    end
    builder.y = builder.y - 30

    controls.showTitles = createOptionsCheckbox(content, nil, L["Title"], L["Show player's title in tooltips"],
        function(_, value)
            TacoTipConfig.show_titles = value
        end)
    controls.showTitles:SetPoint("TOPLEFT", content, "TOPLEFT", 16, builder.y)

    controls.showGuildNames = createOptionsCheckbox(content, nil, L["Guild Name"], L["Show guild name in tooltips"],
        function(_, value)
            TacoTipConfig.show_guild_name = value
            updateControlDependencies()
            modernGetConfig()
        end)
    controls.showGuildNames:SetPoint("TOPLEFT", content, "TOPLEFT", 260, builder.y)
    builder.y = builder.y - 30

    controls.showGuildRanks = createOptionsCheckbox(content, nil, L["Guild Rank"], L["Show guild rank in tooltips"],
        function(_, value)
            TacoTipConfig.show_guild_rank = value
            updateControlDependencies()
            modernGetConfig()
        end)
    controls.showGuildRanks:SetPoint("TOPLEFT", content, "TOPLEFT", 16, builder.y)

    controls.showRealm = createOptionsCheckbox(content, nil, L["OPTIONS_SHOW_REALM"] or "Show realm",
        L["OPTIONS_SHOW_REALM_DESC"] or "Show the realm name for players from other servers (cross-realm).",
        function(_, value)
            TacoTipConfig.show_realm = value
        end)
    controls.showRealm:SetPoint("TOPLEFT", content, "TOPLEFT", 260, builder.y)
    builder.y = builder.y - 30

    controls.guildRankStyleChoice = createOptionsDropdown(content, nil, L["Style"],
        L["OPTIONS_GUILD_STYLE_DESC"] or
        "Choose how TacoTip formats guild rank when both guild name and guild rank are shown.", {
            { value = 1, text = string.format(L["OPTIONS_GUILD_STYLE_ONE"] or L["FORMAT_GUILD_RANK_1"], L["Guild"], L["Rank"]) },
            { value = 2, text = L["OPTIONS_GUILD_STYLE_TWO"] or string.format("<%s> (%s)", L["Guild"], L["Rank"]) }
        }, function(value)
            TacoTipConfig.guild_rank_alt_style = (value == 2)
        end)
    builder.y = builder.y - layoutDropdownControl(content, controls.guildRankStyleChoice, builder.y, 8)

    controls.showTalents = createOptionsCheckbox(content, nil, L["Talents"],
        L["Show talents and specialization in tooltips"],
        function(_, value)
            TacoTipConfig.show_talents = value
        end)
    controls.showTalents:SetPoint("TOPLEFT", content, "TOPLEFT", 16, builder.y)

    controls.showTarget = createOptionsCheckbox(content, nil, L["Target"], L["Show unit's target in tooltips"],
        function(_, value)
            TacoTipConfig.show_target = value
        end)
    controls.showTarget:SetPoint("TOPLEFT", content, "TOPLEFT", 260, builder.y)
    builder.y = builder.y - 30

    controls.gearScorePlayer = createOptionsCheckbox(content, nil, L["OPTIONS_SHOW_PLAYER_GS"] or "Show player GearScore",
        L["OPTIONS_SHOW_PLAYER_GS_DESC"] or
        "Adds GearScore to player tooltips. Wide and mini layouts also show average item level on that line.",
        function(_, value)
            TacoTipConfig.show_gs_player = value
        end)
    controls.gearScorePlayer:SetPoint("TOPLEFT", content, "TOPLEFT", 16, builder.y)

    controls.showIlvlInline = createOptionsCheckbox(content, nil, L["OPTIONS_SHOW_ILVL_INLINE"] or "iLvl on name line",
        L["OPTIONS_SHOW_ILVL_INLINE_DESC"] or
        "Show average item level next to the player's name instead of on a separate line.",
        function(_, value)
            TacoTipConfig.show_ilvl_inline = value
        end)
    controls.showIlvlInline:SetPoint("TOPLEFT", content, "TOPLEFT", 260, builder.y)
    builder.y = builder.y - 30

    controls.pawnScorePlayer = createOptionsCheckbox(content, nil, L["OPTIONS_SHOW_PLAYER_PAWN"] or "Show Pawn scores",
        L["OPTIONS_SHOW_PLAYER_PAWN_DESC"] or
        "Adds Pawn scores for inspected players when Pawn is installed. This may add extra item-cache work.",
        function(_, value)
            TacoTipConfig.show_pawn_player = value
        end)
    controls.pawnScorePlayer:SetPoint("TOPLEFT", content, "TOPLEFT", 16, builder.y)

    controls.showRoleIcon = createOptionsCheckbox(content, nil, L["OPTIONS_SHOW_ROLE_ICON"] or "Show group role icon",
        L["OPTIONS_SHOW_ROLE_ICON_DESC"] or
        "Show Tank/Healer/DPS role icons on the name line for party and raid members.",
        function(_, value)
            TacoTipConfig.show_role_icon = value
        end)
    controls.showRoleIcon:SetPoint("TOPLEFT", content, "TOPLEFT", 260, builder.y)
    builder.y = builder.y - 30

    controls.showTeam = createOptionsCheckbox(content, nil, L["Faction Icon"],
        L["Show player's faction icon (Horde/Alliance) in tooltips"],
        function(_, value)
            TacoTipConfig.show_team = value
        end)
    controls.showTeam:SetPoint("TOPLEFT", content, "TOPLEFT", 16, builder.y)

    controls.showPVPIcon = createOptionsCheckbox(content, nil, L["PVP Icon"],
        L["Show player's pvp flag status as icon instead of text"],
        function(_, value)
            TacoTipConfig.show_pvp_icon = value
        end)
    controls.showPVPIcon:SetPoint("TOPLEFT", content, "TOPLEFT", 260, builder.y)
    builder.y = builder.y - 30

    controls.showHonorRank = createOptionsCheckbox(content, nil, L["OPTIONS_SHOW_HONOR_RANK"] or "Show honor rank",
        L["OPTIONS_SHOW_HONOR_RANK_DESC"] or "Show the player's PvP rank title (Knight, Centurion, etc.) on the tooltip.",
        function(_, value)
            TacoTipConfig.show_honor_rank = value
        end)
    controls.showHonorRank:SetPoint("TOPLEFT", content, "TOPLEFT", 16, builder.y)

    controls.showClassIcon = createOptionsCheckbox(content, nil, L["Class Icon"] or "Class Icon",
        "Show class icon badge at the top-right corner of player tooltips.",
        function(_, value)
            TacoTipConfig.show_class_icon = value
            updateControlDependencies()
        end)
    controls.showClassIcon:SetPoint("TOPLEFT", content, "TOPLEFT", 260, builder.y)
    builder.y = builder.y - 30

    controls.classIconSize = createOptionsSlider(content, nil, "Class icon size",
        "Size of the class icon badge shown at the top-right corner of player tooltips.",
        function(value)
            TacoTipConfig.class_icon_size = value
        end, 8, 32, 1)
    controls.classIconSize:SetPoint("TOPLEFT", content, "TOPLEFT", 260, builder.y)
    controls.classIconSize.valueText:SetPoint("LEFT", controls.classIconSize, "RIGHT", 8, 0)
    builder.y = builder.y - 56

    -- ========================================================================
    -- Section 3: Tooltip Status & Power Bars
    -- ========================================================================
    local barHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    barHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 16, builder.y)
    barHeader:SetText(L["OPTIONS_SECTION_BAR_MEDIA"] or "Tooltip bars")
    builder.y = builder.y - 24

    controls.showHealthBar = createOptionsCheckbox(content, nil, L["Health Bar"],
        L["Show unit's health bar under tooltip"],
        function(_, value)
            TacoTipConfig.show_hp_bar = value
        end)
    controls.showHealthBar:SetPoint("TOPLEFT", content, "TOPLEFT", 16, builder.y)

    controls.showPowerBar = createOptionsCheckbox(content, nil, L["Power Bar"],
        L["Show unit's power bar under tooltip"],
        function(_, value)
            TacoTipConfig.show_power_bar = value
            if (GameTooltip and GameTooltip:IsShown() and TT.ApplyTooltipAppearance
                    and type(GameTooltip.GetUnit) == "function") then
                local ok, _, unit = pcall(GameTooltip.GetUnit, GameTooltip)
                if (ok and unit) then
                    TT:ApplyTooltipAppearance(GameTooltip, unit)
                end
            end
        end)
    controls.showPowerBar:SetPoint("TOPLEFT", content, "TOPLEFT", 260, builder.y)
    builder.y = builder.y - 32

    controls.tooltipBarTextureChoice = createOptionsDropdown(content, nil,
        L["OPTIONS_STATUSBAR_TEXTURE"] or "Health & power bar texture",
        L["OPTIONS_STATUSBAR_TEXTURE_DESC"] or
        "Use one texture for both the health bar and the power bar. The dropdown previews each texture as a bar instead of an icon.",
        TT:GetTooltipStatusBarTextureChoices(), function(value)
            TacoTipConfig.tooltip_bar_texture = value
            modernGetConfig()
        end)
    controls.tooltipBarTextureChoice.isTexturePicker = true
    builder.y = builder.y - layoutDropdownControl(content, controls.tooltipBarTextureChoice, builder.y, 14)

    -- ========================================================================
    -- Section 4: Unit Portrait (2D / 3D)
    -- ========================================================================
    local portraitTextHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    portraitTextHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 16, builder.y)
    portraitTextHeader:SetText(L["OPTIONS_SECTION_TEXT_AND_PORTRAIT"] or "Character portrait")
    builder.y = builder.y - 24

    controls.tooltipPortrait = createOptionsCheckbox(content, nil, L["OPTIONS_TOOLTIP_PORTRAIT"] or "Show unit portrait",
        L["OPTIONS_TOOLTIP_PORTRAIT_DESC"] or "Show a small portrait texture next to player and NPC unit tooltips.",
        function(_, value)
            TacoTipConfig.tooltip_portrait = value
            updateControlDependencies()
            modernGetConfig()
        end)
    controls.tooltipPortrait:SetPoint("TOPLEFT", content, "TOPLEFT", 16, builder.y)
    builder.y = builder.y - 30

    controls.tooltipPortrait3D = createOptionsCheckbox(content, nil,
        L["OPTIONS_TOOLTIP_PORTRAIT_3D"] or "Show 3D portrait",
        L["OPTIONS_TOOLTIP_PORTRAIT_3D_DESC"] or "Use a live 3D model instead of a 2D portrait texture.",
        function(_, value)
            TacoTipConfig.tooltip_portrait_3d = value
            updateControlDependencies()
            modernGetConfig()
        end)
    controls.tooltipPortrait3D:SetPoint("TOPLEFT", content, "TOPLEFT", 16, builder.y)

    controls.tooltipPortraitInvertSide = createOptionsCheckbox(content, nil,
        L["OPTIONS_TOOLTIP_PORTRAIT_INVERT_SIDE"] or "Invert portrait side",
        L["OPTIONS_TOOLTIP_PORTRAIT_INVERT_SIDE_DESC"] or "Swap the portrait to the opposite side of the tooltip.",
        function(_, value)
            TacoTipConfig.tooltip_portrait_invert_side = value
            modernGetConfig()
        end)
    controls.tooltipPortraitInvertSide:SetPoint("TOPLEFT", content, "TOPLEFT", 260, builder.y)
    builder.y = builder.y - 34

    controls.tooltipPortraitZoom = createOptionsSlider(content, nil, L["OPTIONS_PORTRAIT_ZOOM"] or "Portrait zoom",
        L["OPTIONS_PORTRAIT_ZOOM_DESC"] or
        "Controls how close the 3D portrait model appears. Higher values zoom in on the character's face.",
        function(value)
            TacoTipConfig.tooltip_portrait_zoom = value / 100
        end, 30, 100, 5)
    controls.tooltipPortraitZoom:SetPoint("TOPLEFT", content, "TOPLEFT", 16, builder.y)
    controls.tooltipPortraitZoom.valueText:SetPoint("LEFT", controls.tooltipPortraitZoom, "RIGHT", 8, 0)
    builder.y = builder.y - 56

    -- ========================================================================
    -- Section 5: Item Tooltip Data
    -- ========================================================================
    local itemHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    itemHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 16, builder.y)
    itemHeader:SetText(L["OPTIONS_SECTION_ITEM_TOOLTIPS"] or "Item tooltip data")
    builder.y = builder.y - 24

    controls.showItemLevel = createOptionsCheckbox(content, nil, L["Show Item Level"],
        L["Display item level in the tooltip for certain items."],
        function(_, value) TacoTipConfig.show_item_level = value end)
    controls.showItemLevel:SetPoint("TOPLEFT", content, "TOPLEFT", 16, builder.y)

    controls.gearScoreItems = createOptionsCheckbox(content, nil, L["Show Item GearScore"],
        L["Show GearScore in item tooltips"],
        function(_, value)
            TacoTipConfig.show_gs_items = value
            updateControlDependencies()
            modernGetConfig()
        end)
    controls.gearScoreItems:SetPoint("TOPLEFT", content, "TOPLEFT", 260, builder.y)
    builder.y = builder.y - 30

    controls.hunterScoreItems = createOptionsCheckbox(content, nil, L["HunterScore"],
        L["OPTIONS_HUNTERSCORE_DESC"] or
        "Always show HunterScore when item GearScore is enabled. Without this, TacoTip still shows it for Hunters, when inspecting a Hunter, or while a modifier key is held.",
        function(_, value) TacoTipConfig.show_gs_items_hs = value end)
    controls.hunterScoreItems:SetPoint("TOPLEFT", content, "TOPLEFT", 260, builder.y)
    builder.y = builder.y - 36

    -- ========================================================================
    -- Section 6: Backdrop & Border Styling
    -- ========================================================================
    local visualHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    visualHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 16, builder.y)
    visualHeader:SetText(L["OPTIONS_SECTION_VISUAL_STYLE"] or "Backdrop & border styling")
    builder.y = builder.y - 24

    controls.classColoredBorderToggle = createOptionsCheckbox(content, nil,
        L["OPTIONS_BORDER_CLASS_COLOR"] or "Use class-colored border",
        L["OPTIONS_BORDER_CLASS_COLOR_DESC"] or
        "Tint the tooltip border with the player's class color when the tooltip is showing a player unit.",
        function(_, value)
            TacoTipConfig.tooltip_border_use_class = value
        end)
    controls.classColoredBorderToggle:SetPoint("TOPLEFT", content, "TOPLEFT", 16, builder.y)

    controls.tooltipBackgroundUseClass = createOptionsCheckbox(content, nil,
        L["OPTIONS_BACKGROUND_CLASS_COLOR"] or "Use class-colored background tint",
        L["OPTIONS_BACKGROUND_CLASS_COLOR_DESC"] or
        "Adds a subtle class-colored tint behind player tooltips. Use the alpha slider to keep it understated.",
        function(_, value)
            TacoTipConfig.tooltip_background_use_class = value
        end)
    controls.tooltipBackgroundUseClass:SetPoint("TOPLEFT", content, "TOPLEFT", 260, builder.y)
    builder.y = builder.y - 34

    controls.itemQualityBorderToggle = createOptionsCheckbox(content, nil,
        "Item Quality Border Color",
        "Color item tooltip borders by item rarity (green, blue, purple, etc.).",
        function(_, value)
            TacoTipConfig.tooltip_border_item_quality = value
        end)
    controls.itemQualityBorderToggle:SetPoint("TOPLEFT", content, "TOPLEFT", 16, builder.y)
    builder.y = builder.y - 34

    controls.tooltipBorderColor = createColorSwatchControl(content, nil,
        L["OPTIONS_TOOLTIP_BORDER_COLOR"] or "Border color",
        L["OPTIONS_TOOLTIP_BORDER_COLOR_DESC"] or
        "Pick the base tooltip border color. If class-colored borders are enabled, that class tint overrides this on player tooltips.",
        function(r, g, b)
            TacoTipConfig.tooltip_border_color_r = r
            TacoTipConfig.tooltip_border_color_g = g
            TacoTipConfig.tooltip_border_color_b = b
        end)
    controls.tooltipBorderColor:SetPoint("TOPLEFT", content, "TOPLEFT", 16, builder.y)

    controls.tooltipBackgroundColor = createColorSwatchControl(content, nil,
        L["OPTIONS_TOOLTIP_BACKGROUND_COLOR"] or "Background color",
        L["OPTIONS_TOOLTIP_BACKGROUND_COLOR_DESC"] or
        "Pick the base tooltip background color. If class-colored backgrounds are enabled, that class tint overrides this on player tooltips.",
        function(r, g, b)
            TacoTipConfig.tooltip_background_color_r = r
            TacoTipConfig.tooltip_background_color_g = g
            TacoTipConfig.tooltip_background_color_b = b
        end)
    controls.tooltipBackgroundColor:SetPoint("TOPLEFT", content, "TOPLEFT", 260, builder.y)
    builder.y = builder.y - 116

    controls.tooltipBorderEdgeSize = createOptionsSlider(content, nil,
        L["OPTIONS_TOOLTIP_BORDER_THICKNESS"] or "Border thickness",
        L["OPTIONS_TOOLTIP_BORDER_THICKNESS_DESC"] or
        "Control how thick the tooltip border appears. Higher values create a wider, more prominent border edge. Default is 16px.",
        function(value)
            TacoTipConfig.tooltip_border_edge_size = value
        end, 4, 48, 1)
    controls.tooltipBorderEdgeSize:SetPoint("TOPLEFT", content, "TOPLEFT", 16, builder.y)
    controls.tooltipBorderEdgeSize.valueText:SetPoint("LEFT", controls.tooltipBorderEdgeSize, "RIGHT", 8, 0)

    controls.tooltipBorderAlpha = createOptionsSlider(content, nil, L["OPTIONS_BORDER_ALPHA"] or "Border alpha",
        L["OPTIONS_BORDER_ALPHA_DESC"] or
        "Adjust how strong the tooltip border tint appears. Lower values keep class coloring subtle.",
        function(value)
            TacoTipConfig.tooltip_border_alpha = value / 100
        end, 0, 100, 1)
    controls.tooltipBorderAlpha:SetPoint("TOPLEFT", content, "TOPLEFT", 260, builder.y)
    controls.tooltipBorderAlpha.valueText:SetPoint("LEFT", controls.tooltipBorderAlpha, "RIGHT", 8, 0)
    builder.y = builder.y - 56

    controls.tooltipBackgroundAlpha = createOptionsSlider(content, nil,
        L["OPTIONS_BACKGROUND_ALPHA"] or "Background alpha",
        L["OPTIONS_BACKGROUND_ALPHA_DESC"] or
        "Adjust how strong the tooltip background tint appears. Lower values keep the tooltip readable.",
        function(value)
            TacoTipConfig.tooltip_background_alpha = value / 100
        end, 0, 100, 1)
    controls.tooltipBackgroundAlpha:SetPoint("TOPLEFT", content, "TOPLEFT", 16, builder.y)
    controls.tooltipBackgroundAlpha.valueText:SetPoint("LEFT", controls.tooltipBackgroundAlpha, "RIGHT", 8, 0)
    builder.y = builder.y - 56

    controls.tooltipBorderTextureChoice = createOptionsDropdown(content, nil,
        L["OPTIONS_TOOLTIP_BORDER_TEXTURE"] or "Tooltip border texture",
        L["OPTIONS_TOOLTIP_BORDER_TEXTURE_DESC"] or
        "Choose the tooltip border texture. SharedMedia border packs are picked up automatically and Blizzard tooltip border remains the fallback.",
        TT:GetTooltipBorderChoices(), function(value)
            TacoTipConfig.tooltip_border_texture = value
            modernGetConfig()
        end)
    controls.tooltipBorderTextureChoice.isTexturePicker = true
    builder.y = builder.y - layoutDropdownControl(content, controls.tooltipBorderTextureChoice, builder.y, 10)

    controls.tooltipBackgroundTextureChoice = createOptionsDropdown(content, nil,
        L["OPTIONS_TOOLTIP_BACKGROUND_TEXTURE"] or "Tooltip background texture",
        L["OPTIONS_TOOLTIP_BACKGROUND_TEXTURE_DESC"] or
        "Choose the tooltip background texture. SharedMedia background packs are picked up automatically and Blizzard tooltip texture remains the fallback.",
        TT:GetTooltipBackgroundChoices(), function(value)
            TacoTipConfig.tooltip_background_texture = value
            modernGetConfig()
        end)
    controls.tooltipBackgroundTextureChoice.isTexturePicker = true
    builder.y = builder.y - layoutDropdownControl(content, controls.tooltipBackgroundTextureChoice, builder.y, 14)

    builder:Finalize(64)

    panel:SetScript("OnHide", function()
        if (pickerFrame) then
            pickerFrame:Hide()
        end
    end)

    panel.Refresh = function()
        controls.tooltipFontChoice:SetValues(TT:GetTooltipFontChoices())
        controls.tooltipBarTextureChoice:SetValues(TT:GetTooltipStatusBarTextureChoices())
        controls.tooltipBackgroundTextureChoice:SetValues(TT:GetTooltipBackgroundChoices())
        controls.tooltipBorderTextureChoice:SetValues(TT:GetTooltipBorderChoices())
        controls.styleChoice:SetValue(TacoTipConfig.tip_style)
        controls.useClassColors:SetChecked(TacoTipConfig.color_class)
        if (controls.shamanBlue) then
            controls.shamanBlue:SetChecked(TacoTipConfig.shaman_blue ~= false)
        end
        controls.showTitles:SetChecked(TacoTipConfig.show_titles)
        controls.showGuildNames:SetChecked(TacoTipConfig.show_guild_name)
        controls.showGuildRanks:SetChecked(TacoTipConfig.show_guild_rank)
        controls.guildRankStyleChoice:SetValue(TacoTipConfig.guild_rank_alt_style and 2 or 1)
        controls.showTalents:SetChecked(TacoTipConfig.show_talents)
        controls.showTarget:SetChecked(TacoTipConfig.show_target)
        controls.gearScorePlayer:SetChecked(TacoTipConfig.show_gs_player)
        controls.pawnScorePlayer:SetChecked(TacoTipConfig.show_pawn_player)
        controls.pawnScorePlayer:SetDisabled(not isPawnLoaded)
        controls.pawnScorePlayer.label:SetText(isPawnLoaded and (L["OPTIONS_SHOW_PLAYER_PAWN"] or "Show Pawn scores") or
            ((L["OPTIONS_SHOW_PLAYER_PAWN"] or "Show Pawn scores") .. " (" .. L["requires Pawn"] .. ")"))
        controls.showTeam:SetChecked(TacoTipConfig.show_team)
        controls.showClassIcon:SetChecked(TacoTipConfig.show_class_icon)
        controls.classColoredBorderToggle:SetChecked(TacoTipConfig.tooltip_border_use_class)
        if (controls.itemQualityBorderToggle) then
            controls.itemQualityBorderToggle:SetChecked(TacoTipConfig.tooltip_border_item_quality ~= false)
        end
        controls.showPVPIcon:SetChecked(TacoTipConfig.show_pvp_icon)
        controls.showHealthBar:SetChecked(TacoTipConfig.show_hp_bar)
        controls.showPowerBar:SetChecked(TacoTipConfig.show_power_bar)
        controls.showItemLevel:SetChecked(TacoTipConfig.show_item_level)
        controls.gearScoreItems:SetChecked(TacoTipConfig.show_gs_items)
        controls.hunterScoreItems:SetChecked(TacoTipConfig.show_gs_items_hs)
        controls.tooltipBackgroundUseClass:SetChecked(TacoTipConfig.tooltip_background_use_class)
        controls.tooltipBorderColor:SetColor(TacoTipConfig.tooltip_border_color_r or 1,
            TacoTipConfig.tooltip_border_color_g or 1, TacoTipConfig.tooltip_border_color_b or 1)
        controls.tooltipBackgroundColor:SetColor(TacoTipConfig.tooltip_background_color_r or 0,
            TacoTipConfig.tooltip_background_color_g or 0, TacoTipConfig.tooltip_background_color_b or 0)
        controls.tooltipBorderAlpha:SetValueSilently(math.floor((TacoTipConfig.tooltip_border_alpha or 1) * 100 + 0.5))

        local declaredEdgeSize = TT.GetDeclaredTooltipBorderEdgeSize
            and TT:GetDeclaredTooltipBorderEdgeSize()
        controls.tooltipBorderEdgeSize:SetValueSilently(
            declaredEdgeSize or TacoTipConfig.tooltip_border_edge_size
            or DEFAULTS.tooltip_border_edge_size)
        if (controls.tooltipBorderEdgeSize.SetDisabled) then
            controls.tooltipBorderEdgeSize:SetDisabled(declaredEdgeSize ~= nil)
        end
        controls.tooltipBackgroundAlpha:SetValueSilently(math.floor((TacoTipConfig.tooltip_background_alpha or 0.85) *
            100 + 0.5))
        controls.tooltipBackgroundTextureChoice:SetValue(TT:GetResolvedTooltipBackground())
        controls.tooltipBorderTextureChoice:SetValue(TT:GetResolvedTooltipBorder())
        controls.tooltipScale:SetValueSilently(math.floor((TacoTipConfig.tooltip_scale or 1) * 100 + 0.5))
        controls.tooltipPortrait:SetChecked(TacoTipConfig.tooltip_portrait)
        controls.tooltipPortraitScale:SetValueSilently(math.floor((TacoTipConfig.tooltip_portrait_scale or 1) * 100 + 0.5))
        controls.tooltipPortrait3D:SetChecked(TacoTipConfig.tooltip_portrait_3d)
        controls.tooltipPortraitInvertSide:SetChecked(TacoTipConfig.tooltip_portrait_invert_side)
        controls.tooltipPortraitZoom:SetValueSilently(math.floor((TacoTipConfig.tooltip_portrait_zoom or 0.7) * 100 + 0.5))
        controls.classIconSize:SetValueSilently(TacoTipConfig.class_icon_size or 20)
        controls.tooltipFontChoice:SetValue(TT:GetResolvedTooltipFont())
        controls.tooltipFontSize:SetValueSilently(TacoTipConfig.tooltip_font_size or 12)
        controls.tooltipBarTextureChoice:SetValue(TT:GetResolvedTooltipStatusBarTexture())
        controls.showHonorRank:SetChecked(TacoTipConfig.show_honor_rank)
        controls.showRoleIcon:SetChecked(TacoTipConfig.show_role_icon)
        controls.showRealm:SetChecked(TacoTipConfig.show_realm)
        controls.showIlvlInline:SetChecked(TacoTipConfig.show_ilvl_inline)
        controls.showSeparators:SetChecked(TacoTipConfig.show_separators)
        controls.showMinimap:SetChecked(TacoTipConfig.show_minimap ~= false)
        controls.tooltipMaxWidth:SetValueSilently(TacoTipConfig.tooltip_max_width or 0)

        updateControlDependencies()
    end

    modernOptionsState.pages.tooltipsBuilt = true
end

local function setOffsetValue(key, value, silent)
    -- Clamp keyboard-entered offsets so a typo cannot push an overlay
    -- permanently offscreen (sliders are bounded by their range; these
    -- edit boxes previously stored any integer verbatim).
    value = math.floor(value + (value < 0 and -0.5 or 0.5))
    if (value < MODERN_OPTION_SLIDER_MIN) then
        value = MODERN_OPTION_SLIDER_MIN
    elseif (value > MODERN_OPTION_SLIDER_MAX) then
        value = MODERN_OPTION_SLIDER_MAX
    end
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

    -- `silent` is for the bulk refresh in the Character/Inspect page Refresh,
    -- which writes all eight offsets. Repositioning inside each of those made one
    -- refresh cost 8 x (8 RefreshPosition + a GearScore recompute), and the
    -- movers that call RefreshOptionsUI are parented to the paper doll -- so the
    -- IsShown guards passed exactly when the player was dragging one.
    -- `silent` is for the bulk refresh in the Character/Inspect page Refresh,
    -- which writes all eight offsets. Repositioning inside each of those made one
    -- refresh cost 8 x (8 RefreshPosition + a GearScore recompute), and the
    -- movers that call RefreshOptionsUI are parented to the paper doll -- so the
    -- IsShown guards passed exactly when the player was dragging one.
    if (not silent) then
        refreshOverlayPositions()
    end
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

    local header, headerDesc = createSectionHeader(content, L["OPTIONS_PAGE_POSITIONING"] or "Positioning",
        L["OPTIONS_POSITIONING_PAGE_DESC"] or
        "Choose how TacoTip places the main tooltip and how its mover workflow behaves.", 520)
    builder:AddAnchor(header, 24)
    if (headerDesc) then builder:AddAnchor(headerDesc, headerDesc:GetStringHeight() + 8) end

    local modeHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    modeHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 16, builder.y)
    modeHeader:SetText(L["OPTIONS_SECTION_TOOLTIP_POSITION"] or "Tooltip position mode")
    builder.y = builder.y - 24

    controls.customPosition = createOptionsCheckbox(content, "TacoTipOptCheckBoxCustomPosition",
        L["Custom Tooltip Position"],
        L["OPTIONS_CUSTOM_POSITION_DESC"] or "Save and reuse a custom on-screen tooltip location.", function(_, value)
            local anchor = TacoTipConfig.custom_anchor or "TOPLEFT"
            TacoTipConfig.custom_pos = value and (TacoTipConfig.custom_pos or { anchor, anchor, 0, 0 }) or nil
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

    controls.anchorMouse = createOptionsCheckbox(content, "TacoTipOptCheckBoxAnchorMouse", L["Anchor to Mouse"],
        L["Anchor tooltips to mouse cursor"], function(_, value)
            TacoTipConfig.anchor_mouse = value
            if (value) then
                TacoTipConfig.custom_pos = nil
                if (TacoTipDragButton) then TacoTipDragButton:_Disable(true) end
            end
            modernGetConfig()
        end)
    controls.anchorMouse:SetPoint("TOPLEFT", content, "TOPLEFT", 274, builder.y)
    builder.y = builder.y - 30

    controls.anchorMouseWorld = createOptionsCheckbox(content, "TacoTipOptCheckBoxAnchorMouseWorld",
        L["Only in WorldFrame"], L["Anchor to mouse only in WorldFrame\nSkips raid / party frames"], function(_, value)
            TacoTipConfig.anchor_mouse_world = value
        end)
    controls.anchorMouseWorld:SetPoint("TOPLEFT", content, "TOPLEFT", 14, builder.y)

    controls.anchorMouseSpells = createOptionsCheckbox(content, nil, L["Anchor Spells to Mouse"],
        L["OPTIONS_ANCHOR_MOUSE_SPELLS_DESC"] or
        "Anchor spell and action-button tooltips to the mouse cursor instead of the saved tooltip position.",
        function(_, value)
            TacoTipConfig.anchor_mouse_spells = value
        end)
    controls.anchorMouseSpells:SetPoint("TOPLEFT", content, "TOPLEFT", 274, builder.y)
    builder.y = builder.y - 38

    controls.customAnchor = createOptionsDropdown(content, nil,
        L["OPTIONS_CUSTOM_ANCHOR_LABEL"] or "Custom tooltip anchor",
        L["OPTIONS_CUSTOM_ANCHOR_DESC"] or
        "Choose which point of the saved tooltip position acts as the attachment anchor.", modernAnchorOptions,
        function(value)
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

    controls.moverBtn = createOptionsButton(content, "TacoTipOptButtonMover",
        L["OPTIONS_OPEN_TOOLTIP_MOVER"] or L["Mover"], 180, 22, function()
            showTooltipMover()
        end,
        L["OPTIONS_OPEN_TOOLTIP_MOVER_DESC"] or
        "Show the live tooltip mover so you can drag and save a custom tooltip position.")
    controls.moverBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 274, builder.y - 4)
    builder.y = builder.y - 78

    local behaviorHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    behaviorHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 16, builder.y)
    behaviorHeader:SetText(L["OPTIONS_SECTION_TOOLTIP_BEHAVIOR"] or "Tooltip behavior")
    builder.y = builder.y - 24

    controls.instantFade = createOptionsCheckbox(content, nil, L["Instant Fade"], L["Fade out unit tooltips instantly"],
        function(_, value)
            TacoTipConfig.instant_fade = value
            updateInstantFadeState(value)
        end)
    controls.instantFade:SetPoint("TOPLEFT", content, "TOPLEFT", 14, builder.y)
    builder.y = builder.y - 38

    controls.tooltipDelay = createOptionsSlider(content, nil, L["OPTIONS_TOOLTIP_DELAY"] or "Tooltip delay (ms)",
        L["OPTIONS_TOOLTIP_DELAY_DESC"] or
        "Add a short delay before the tooltip appears to prevent flicker when quickly moving the mouse. 0 = no delay.",
        function(value)
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
        setButtonEnabled(controls.moverBtn, true)
        controls.tooltipDelay:SetValueSilently(math.floor((TacoTipConfig.tooltip_delay or 0) * 1000 + 0.5))
    end

    -- NOTE: no panel:SetScript("OnShow") here — the load-tail safeCall
    -- wrappers own the OnShow slot and already call panel:Refresh().
    -- Assigning here would replace them after first build (F6 fix).

    modernOptionsState.pages.positioningBuilt = true
end

local function createOffsetControlRow(parent, builder, titleText, keyX, keyY)
    local label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, builder.y)
    label:SetText(titleText)

    local xLabel = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    xLabel:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -8)
    xLabel:SetText("X")

    local xEdit = createOptionsEditBox(parent, nil, 52, function(value) setOffsetValue(keyX, value) end,
        titleText .. " X", L["OPTIONS_OFFSET_EDIT_DESC"] or "Type a precise pixel offset and press Enter to apply it.")
    xEdit:SetPoint("LEFT", xLabel, "RIGHT", 10, 0)
    modernOptionsState.offsetEditors[keyX] = xEdit

    local xSlider = createOptionsSlider(parent, nil, titleText .. " X",
        L["OPTIONS_OFFSET_SLIDER_DESC"] or "Drag to fine-tune this offset. The numeric field stays synchronized.",
        function(value) setOffsetValue(keyX, value) end)
    xSlider.label:SetText("")
    xSlider:SetPoint("TOPLEFT", xEdit, "TOPRIGHT", 18, 0)
    xSlider.valueText:SetPoint("LEFT", xSlider, "RIGHT", 8, 0)
    modernOptionsState.offsetSliders[keyX] = xSlider

    local yLabel = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    yLabel:SetPoint("TOPLEFT", xLabel, "BOTTOMLEFT", 0, -30)
    yLabel:SetText("Y")

    local yEdit = createOptionsEditBox(parent, nil, 52, function(value) setOffsetValue(keyY, value) end,
        titleText .. " Y", L["OPTIONS_OFFSET_EDIT_DESC"] or "Type a precise pixel offset and press Enter to apply it.")
    yEdit:SetPoint("LEFT", yLabel, "RIGHT", 10, 0)
    modernOptionsState.offsetEditors[keyY] = yEdit

    local ySlider = createOptionsSlider(parent, nil, titleText .. " Y",
        L["OPTIONS_OFFSET_SLIDER_DESC"] or "Drag to fine-tune this offset. The numeric field stays synchronized.",
        function(value) setOffsetValue(keyY, value) end)
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

    local header, headerDesc = createSectionHeader(content, L["OPTIONS_PAGE_CHARACTER_INSPECT"] or "Character & Inspect",
        L["OPTIONS_CHARACTER_PAGE_DESC"] or
        "Control the character-frame and inspect-frame overlay labels, plus their precise offsets.", 520)
    builder:AddAnchor(header, 24)
    if (headerDesc) then builder:AddAnchor(headerDesc, headerDesc:GetStringHeight() + 8) end

    controls.gearScoreCharacter = createOptionsCheckbox(content, nil,
        L["OPTIONS_CHARACTER_GS_LABEL"] or "Show GearScore overlays",
        L["OPTIONS_CHARACTER_GS_DESC"] or "Show GearScore on both the character frame and inspect frame.",
        function(_, value)
            TacoTipConfig.show_gs_character = value
            refreshOverlayPositions()
            modernGetConfig()
        end)
    controls.gearScoreCharacter:SetPoint("TOPLEFT", content, "TOPLEFT", 14, builder.y)

    controls.averageItemLevel = createOptionsCheckbox(content, nil,
        L["OPTIONS_CHARACTER_ILVL_LABEL"] or "Show average item level overlays",
        L["OPTIONS_CHARACTER_ILVL_DESC"] or "Show average item level on both the character frame and inspect frame.",
        function(_, value)
            TacoTipConfig.show_avg_ilvl = value
            refreshOverlayPositions()
            modernGetConfig()
        end)
    controls.averageItemLevel:SetPoint("TOPLEFT", content, "TOPLEFT", 274, builder.y)
    builder.y = builder.y - 30

    controls.unlockInfoPosition = createOptionsCheckbox(content, nil,
        L["OPTIONS_UNLOCK_OVERLAYS_LABEL"] or "Enable manual overlay movers",
        L["OPTIONS_UNLOCK_OVERLAYS_DESC"] or
        "Show drag handles on the frame overlays so you can position them manually in addition to using the numeric offsets below.",
        function(_, value)
            TacoTipConfig.unlock_info_position = value
            refreshOverlayPositions()
            modernGetConfig()
        end)
    controls.unlockInfoPosition:SetPoint("TOPLEFT", content, "TOPLEFT", 14, builder.y)
    builder.y = builder.y - 30

    controls.progressionChat = createOptionsCheckbox(content, nil,
        "Progression chat alerts",
        "Print a private chat notification when gaining a gear level or unlocking a trophy.",
        function(_, value)
            TacoTipConfig.progression_chat = value
            modernGetConfig()
        end)
    controls.progressionChat:SetPoint("TOPLEFT", content, "TOPLEFT", 14, builder.y)

    controls.progressionSound = createOptionsCheckbox(content, nil,
        "Progression level-up fanfare",
        "Play a triumphant fanfare sound effect upon gaining a gear level.",
        function(_, value)
            TacoTipConfig.progression_sound = value
            modernGetConfig()
        end)
    controls.progressionSound:SetPoint("TOPLEFT", content, "TOPLEFT", 274, builder.y)
    builder.y = builder.y - 42

    modernOptionsState.characterGsRow = createOffsetControlRow(content, builder,
        L["OPTIONS_CHARACTER_GS_OFFSETS"] or "Character GearScore offsets", "character_gs_offset_x",
        "character_gs_offset_y")
    modernOptionsState.characterIlvlRow = createOffsetControlRow(content, builder,
        L["OPTIONS_CHARACTER_ILVL_OFFSETS"] or "Character iLvl offsets", "character_ilvl_offset_x",
        "character_ilvl_offset_y")
    modernOptionsState.inspectGsRow = createOffsetControlRow(content, builder,
        L["OPTIONS_INSPECT_GS_OFFSETS"] or "Inspect GearScore offsets", "inspect_gs_offset_x", "inspect_gs_offset_y")
    modernOptionsState.inspectIlvlRow = createOffsetControlRow(content, builder,
        L["OPTIONS_INSPECT_ILVL_OFFSETS"] or "Inspect iLvl offsets", "inspect_ilvl_offset_x", "inspect_ilvl_offset_y")

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
        if (controls.progressionChat) then controls.progressionChat:SetChecked(TacoTipConfig.progression_chat ~= false) end
        if (controls.progressionSound) then controls.progressionSound:SetChecked(TacoTipConfig.progression_sound ~= false) end

        setOffsetValue("character_gs_offset_x", TacoTipConfig.character_gs_offset_x or 0, true)
        setOffsetValue("character_gs_offset_y", TacoTipConfig.character_gs_offset_y or 0, true)
        setOffsetValue("character_ilvl_offset_x", TacoTipConfig.character_ilvl_offset_x or 0, true)
        setOffsetValue("character_ilvl_offset_y", TacoTipConfig.character_ilvl_offset_y or 0, true)
        setOffsetValue("inspect_gs_offset_x", TacoTipConfig.inspect_gs_offset_x or 0, true)
        setOffsetValue("inspect_gs_offset_y", TacoTipConfig.inspect_gs_offset_y or 0, true)
        setOffsetValue("inspect_ilvl_offset_x", TacoTipConfig.inspect_ilvl_offset_x or 0, true)
        setOffsetValue("inspect_ilvl_offset_y", TacoTipConfig.inspect_ilvl_offset_y or 0, true)
        -- Once for all eight, not eight times.
        refreshOverlayPositions()

        modernRefreshLockPositionToggle()
    end

    -- NOTE: no panel:SetScript("OnShow") here — the load-tail safeCall
    -- wrappers own the OnShow slot and already call panel:Refresh().
    -- Assigning here would replace them after first build (F6 fix).

    modernOptionsState.pages.characterInspectBuilt = true
end

modernGetConfig = function()
    -- Only the resolved VALUES: this runs on every options interaction, and the
    -- choice lists do not depend on the config, so rebuilding them here would
    -- undo their memoisation.
    if (TT.InvalidateResolvedTooltipValues) then
        TT:InvalidateResolvedTooltipValues()
    end
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

-- ============================================================================
-- Standalone dashboard (/tt): General / Diagnostics / Community tabs.
-- Built lazily on first show, so nothing here exists until the player asks.
-- Every setting stays on the Blizzard pages; "All Settings" opens them.
-- ============================================================================

local function buildDiagnosticsReport()
    local lines = { "TacoTip " .. tostring(addOnVersion) .. " | " .. getClientFamilyDisplayLabel() }
    if (not (TT and TT.CollectDiagnostics)) then
        lines[#lines + 1] = "Diagnostics unavailable: main.lua did not finish loading."
        if (TT and TT.LOAD_STAGE) then
            lines[#lines + 1] = "Last stage reached: " .. tostring(TT.LOAD_STAGE)
        end
        return table.concat(lines, "\n"), nil
    end
    local ok, diag = pcall(TT.CollectDiagnostics, TT)
    if (not ok or type(diag) ~= "table") then
        lines[#lines + 1] = "Diagnostics failed: " .. tostring(diag)
        return table.concat(lines, "\n"), nil
    end
    local verdict = diag.verdict or {}
    lines[#lines + 1] = "Verdict: " .. tostring(verdict.text or "UNKNOWN")
    for _, section in ipairs(diag.sections or {}) do
        lines[#lines + 1] = ""
        lines[#lines + 1] = "-- " .. tostring(section.title or section.id or "section") .. " --"
        for _, row in ipairs(section.rows or {}) do
            local suffix = (row.status == "warn" and " [warn]") or (row.status == "error" and " [error]") or ""
            lines[#lines + 1] = tostring(row.label or "?") .. ": " .. tostring(row.value) .. suffix
        end
        for _, note in ipairs(section.notes or {}) do
            lines[#lines + 1] = "note: " .. tostring(note)
        end
    end
    return table.concat(lines, "\n"), verdict
end

TT.FOREVER_GS_SECTIONS = {
    { label = "Leveling", minPct = 0.00, maxPct = 0.16, minGS = 0,    maxGS = 550,  r = 0.82, g = 0.84, b = 0.88, hex = "FFD1D5DB" },
    { label = "Pre-Raid", minPct = 0.16, maxPct = 0.34, minGS = 550,  maxGS = 800,  r = 0.12, g = 1.00, b = 0.00, hex = "FF1EFF00" },
    { label = "Tier 1",   minPct = 0.34, maxPct = 0.52, minGS = 800,  maxGS = 1000, r = 0.00, g = 0.44, b = 0.87, hex = "FF0070DD" },
    { label = "Tier 2",   minPct = 0.52, maxPct = 0.70, minGS = 1000, maxGS = 1180, r = 0.64, g = 0.21, b = 0.93, hex = "FFA335EE" },
    { label = "Tier 3",   minPct = 0.70, maxPct = 0.86, minGS = 1180, maxGS = 1300, r = 1.00, g = 0.50, b = 0.00, hex = "FFFF8000" },
    { label = "???",      minPct = 0.86, maxPct = 1.00, minGS = 1300, maxGS = 1500, r = 0.90, g = 0.80, b = 0.50, hex = "FFE6CC80" },
}

function TT:GetForeverProgressSection(score, dynamicCap)
    local s = tonumber(score) or 0
    local list = self.FOREVER_GS_SECTIONS
    for i = 1, #list do
        local sec = list[i]
        local topGS = (i == #list) and math.max(sec.maxGS, tonumber(dynamicCap) or sec.maxGS) or sec.maxGS
        if (s < topGS or i == #list) then
            local spanGS = math.max(1, topGS - sec.minGS)
            local frac = math.min(1, math.max(0, (s - sec.minGS) / spanGS))
            local ratio = sec.minPct + frac * (sec.maxPct - sec.minPct)
            return sec, ratio, i
        end
    end
    return list[1], 0, 1
end

local function createDashboard()
    local frame = CreateFrame("Frame", "TacoTipDashboard", UIParent)
    frame:SetSize(1000, 600)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    paintFlatBox(frame, DASH_THEME.windowBg, DASH_THEME.borderGold)
    frame:Hide()
    if (_G.UISpecialFrames) then
        tinsert(_G.UISpecialFrames, "TacoTipDashboard")
    end

    -- Top Header Bar (Height 54 to fit 48x48 icon comfortably)
    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
    header:SetHeight(54)
    paintFlatBox(header, DASH_THEME.headerBg)

    local logo = header:CreateTexture(nil, "ARTWORK")
    logo:SetSize(48, 48)
    logo:SetPoint("LEFT", header, "LEFT", 10, 0)
    logo:SetTexture(LOGO_TEXTURE_PATH)

    local title = header:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("LEFT", logo, "RIGHT", 12, 0)
    title:SetText("|cffffffffTACO|cffffb81cT|cff7be046I|cff2ecc71P|r  |cffb4e634" ..
        addOnVersion .. "|r · |cff9ba3ae" .. getClientFamilyDisplayLabel() .. "|r")

    local close = createFlatActionCard(header, 28, 24, "X", "danger", function() frame:Hide() end,
        "Close", "Close the dashboard (ESC also works).")
    close:SetPoint("RIGHT", header, "RIGHT", -10, 0)

    -- Header Overall GearScore Progression Tracking Bar (0 GS -> Client Max BiS Cap)
    local HEADER_PROG_MAX_PINS = 18
    local headerProg = CreateFrame("Button", nil, header)
    headerProg:SetPoint("LEFT", title, "RIGHT", 18, 0)
    headerProg:SetPoint("RIGHT", close, "LEFT", -16, 0)
    headerProg:SetHeight(44)
    headerProg:EnableMouse(true)

    local hProgLeft = headerProg:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hProgLeft:SetPoint("TOPLEFT", headerProg, "TOPLEFT", 2, -1)
    hProgLeft:SetJustifyH("LEFT")
    hProgLeft:SetText("|cffffd100GS Progress|r")

    local hProgRight = headerProg:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hProgRight:SetPoint("TOPRIGHT", headerProg, "TOPRIGHT", -2, -1)
    hProgRight:SetJustifyH("RIGHT")
    hProgRight:SetText("0 / 1400 GS (0%)")

    local hProgTrack = CreateFrame("Frame", nil, headerProg)
    hProgTrack:SetPoint("TOPLEFT", headerProg, "TOPLEFT", 0, -15)
    hProgTrack:SetPoint("TOPRIGHT", headerProg, "TOPRIGHT", 0, -15)
    hProgTrack:SetHeight(14)
    paintFlatBox(hProgTrack, { 0.05, 0.06, 0.08, 0.98 }, DASH_THEME.borderSubtle)

    local hProgStageBands = {}
    for b = 1, #TT.FOREVER_GS_SECTIONS do
        local band = hProgTrack:CreateTexture(nil, "BORDER")
        band:SetTexture(WHITE8X8)
        band:SetVertexColor(0.2, 0.2, 0.2, 0.08)
        band:Hide()
        hProgStageBands[b] = band
    end

    local hProgFill = hProgTrack:CreateTexture(nil, "ARTWORK")
    hProgFill:SetPoint("TOPLEFT", hProgTrack, "TOPLEFT", 1, -1)
    hProgFill:SetPoint("BOTTOMLEFT", hProgTrack, "BOTTOMLEFT", 1, 1)
    hProgFill:SetWidth(1)
    hProgFill:SetTexture(WHITE8X8)
    hProgFill:SetVertexColor(0.18, 0.72, 0.40, 0.92)
    hProgFill:Hide()

    local hProgCursor = hProgTrack:CreateTexture(nil, "OVERLAY")
    hProgCursor:SetSize(2, 14)
    hProgCursor:SetPoint("RIGHT", hProgFill, "RIGHT", 0, 0)
    hProgCursor:SetTexture(WHITE8X8)
    hProgCursor:SetVertexColor(1.0, 0.92, 0.45, 0.98)
    hProgCursor:Hide()

    local hProgPeak = hProgTrack:CreateTexture(nil, "OVERLAY")
    hProgPeak:SetSize(2, 14)
    hProgPeak:SetTexture(WHITE8X8)
    hProgPeak:SetVertexColor(1.0, 0.78, 0.12, 0.65)
    hProgPeak:Hide()

    local hProgBracketTicks = {}
    for b = 1, 6 do
        local div = hProgTrack:CreateTexture(nil, "OVERLAY")
        div:SetSize(1, 12)
        div:SetTexture(WHITE8X8)
        div:SetVertexColor(1, 1, 1, 0.18)
        hProgBracketTicks[b] = div
    end

    hProgTrack._foreverLabels = {}
    for b = 1, #TT.FOREVER_GS_SECTIONS do
        local fl = hProgTrack:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fl:SetJustifyH("CENTER")
        fl:SetText(TT.FOREVER_GS_SECTIONS[b].label)
        fl:Hide()
        hProgTrack._foreverLabels[b] = fl
    end

    local hProgMinLabel = headerProg:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hProgMinLabel:SetPoint("BOTTOMLEFT", headerProg, "BOTTOMLEFT", 2, 1)
    hProgMinLabel:SetText("0 GS")

    local hProgHintLabel = headerProg:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hProgHintLabel:SetPoint("BOTTOM", headerProg, "BOTTOM", 0, 1)
    hProgHintLabel:SetText("Hover ticks for snapshots · Click to view")

    local hProgMaxLabel = headerProg:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hProgMaxLabel:SetPoint("BOTTOMRIGHT", headerProg, "BOTTOMRIGHT", -2, 1)
    hProgMaxLabel:SetText("1400 GS Max")

    local hProgSnapTicks = {}
    for idx = 1, HEADER_PROG_MAX_PINS do
        local pin = CreateFrame("Button", nil, hProgTrack)
        pin:SetSize(9, 16)
        pin:SetFrameLevel(hProgTrack:GetFrameLevel() + 3)
        pin:EnableMouse(true)
        pin:Hide()

        local line = pin:CreateTexture(nil, "OVERLAY")
        line:SetSize(2, 14)
        line:SetPoint("CENTER", pin, "CENTER", 0, 0)
        line:SetTexture(WHITE8X8)
        line:SetVertexColor(0.35, 0.94, 0.86, 0.90)
        pin._line = line

        pin:SetScript("OnEnter", function(self)
            self._line:SetSize(3, 16)
            self._line:SetVertexColor(1.0, 0.84, 0.15, 1.0)
            local snap = self._snapData
            if (snap and GameTooltip) then
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOM", 0, -4)
                GameTooltip:ClearLines()
                local tierHex = snap.tierColorHex or "FFFFD100"
                GameTooltip:AddLine(string.format("Snapshot #%d · |c%sLv.%d %s|r",
                    self._snapIndex or 1, tierHex, snap.level or 1, snap.title or "Gear"), 1, 0.82, 0.1)
                local dateFn = _G.date
                if (snap.time and snap.time > 0) then
                    local dtStr = (type(dateFn) == "function")
                        and tostring(dateFn("%Y-%m-%d %H:%M", snap.time))
                        or tostring(snap.time)
                    GameTooltip:AddDoubleLine("Recorded:", dtStr, 0.65, 0.70, 0.78, 0.9, 0.9, 0.9)
                end
                local capVal = self._barCap or 1400
                local sGS = tonumber(snap.totalGS) or 0
                local pct = (capVal > 0) and math.floor((sGS / capVal) * 100 + 0.5) or 0
                GameTooltip:AddDoubleLine("GearScore:",
                    string.format("|cffffd100%d|r / %d GS (%d%%)", sGS, capVal, pct),
                    0.65, 0.70, 0.78, 1, 1, 1)
                if ((tonumber(snap.avgILvl) or 0) > 0) then
                    GameTooltip:AddDoubleLine("Avg Item Level:",
                        string.format("%d", math.floor(snap.avgILvl or 0)),
                        0.65, 0.70, 0.78, 1, 1, 1)
                end
                if (snap.equippedCount and snap.totalSlots) then
                    GameTooltip:AddDoubleLine("Equipped Slots:",
                        string.format("%d / %d", snap.equippedCount, snap.totalSlots),
                        0.65, 0.70, 0.78, 1, 1, 1)
                end
                if (snap.slotName or snap.newLink) then
                    local itemPart = snap.newLink or "Update"
                    local deltaTxt = (snap.deltaGS and snap.deltaGS ~= 0)
                        and string.format(" (%+d GS)", snap.deltaGS) or ""
                    GameTooltip:AddLine("Milestone: |cffffd100" .. tostring(snap.slotName or "Gear")
                        .. "|r " .. tostring(itemPart) .. "|cffb4e634" .. deltaTxt .. "|r", 1, 1, 1, true)
                end
                local curGS = self._currentScore or 0
                local diffNow = curGS - sGS
                local diffColor = (diffNow > 0) and "|cffb4e634" or (diffNow < 0 and "|cffff6b6b" or "|cff9ba3ae")
                GameTooltip:AddLine(string.format("Compared to Now: %s%+d GS|r", diffColor, diffNow), 0.85, 0.85, 0.85)
                GameTooltip:Show()
            end
        end)
        pin:SetScript("OnLeave", function(self)
            self._line:SetSize(2, 14)
            if (self._isPeak) then
                self._line:SetVertexColor(1.0, 0.82, 0.15, 0.95)
            else
                self._line:SetVertexColor(0.35, 0.94, 0.86, 0.90)
            end
            if (GameTooltip) then
                GameTooltip:Hide()
            end
        end)
        pin:SetScript("OnClick", function()
            if (frame.SelectTab) then
                frame:SelectTab("progression")
            end
        end)

        hProgSnapTicks[idx] = pin
    end

    headerProg:SetScript("OnEnter", function(self)
        if (hProgTrack.SetFlatColors) then
            hProgTrack:SetFlatColors(nil, DASH_THEME.borderGold)
        end
        if (GameTooltip) then
            local rec = TT and TT.GetPlayerProgression and TT:GetPlayerProgression() or {}
            local curGS = rec.currentScore or 0
            local peakGS = math.max(curGS, rec.peakScore or 0)
            local cap, bracketSize = 1400, 200
            if (TT and TT.GetGearScoreProgressCap) then
                cap, bracketSize = TT:GetGearScoreProgressCap(curGS, peakGS)
            end
            local lvl = (TT and TT.GetGearLevelInfo) and TT:GetGearLevelInfo(curGS) or { level = 1, title = "Novice" }
            local pct = (cap > 0) and math.min(100, math.floor((curGS / cap) * 100 + 0.5)) or 0
            local gsGlobal = rawget(_G, "TT_GS")
            local tierLabel = "Starter"
            local r, g, b = 1, 1, 1
            if (gsGlobal and gsGlobal.GetQuality) then
                local qr, qg, qb, qDesc = gsGlobal:GetQuality(curGS)
                r, g, b = qr or 1, qg or 1, qb or 1
                if (qDesc and qDesc ~= "") then
                    tierLabel = qDesc
                end
            end
            local remaining = math.max(0, cap - curGS)
            local snaps = self._snapCount or 0
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM", 0, -4)
            GameTooltip:ClearLines()
            GameTooltip:AddLine("Overall GearScore Progression", 1, 0.82, 0.1)
            GameTooltip:AddDoubleLine("Current / Best-in-Game Cap:",
                string.format("%d / %d GS (%d%%)", curGS, cap, pct), 0.7, 0.75, 0.82, r, g, b)
            GameTooltip:AddDoubleLine("Remaining to Max Cap:",
                string.format("%d GS", remaining), 0.7, 0.75, 0.82, 1, 1, 1)
            GameTooltip:AddDoubleLine("Quality Tier:",
                string.format("%s (%d GS/tier)", tierLabel, bracketSize), 0.7, 0.75, 0.82, r, g, b)
            GameTooltip:AddDoubleLine("Gear Level / Avg iLvl:",
                string.format("Lv.%d %s · iLvl %d", lvl.level or 1, lvl.title or "Novice",
                    math.floor(rec.avgItemLevel or 0)), 0.7, 0.75, 0.82, 1, 1, 1)
            if (CI and CI.IsForever and CI:IsForever() and TT and TT.GetForeverProgressSection) then
                local foreverCap = math.max(1500, peakGS)
                if (foreverCap > 1500) then
                    foreverCap = math.ceil(foreverCap / 200) * 200
                end
                local fSec, _, fIdx = TT:GetForeverProgressSection(curGS, foreverCap)
                local list = TT.FOREVER_GS_SECTIONS
                local rangeTxt = (list and fIdx == #list)
                    and string.format("%d+ GS", fSec.minGS)
                    or string.format("%d–%d GS", fSec.minGS, fSec.maxGS)
                GameTooltip:AddDoubleLine("Forever Progression Stage:",
                    string.format("|c%s%s|r (%s)", fSec.hex, fSec.label, rangeTxt),
                    0.7, 0.75, 0.82, 1, 1, 1)
                local nextSec = (list and type(fIdx) == "number") and list[fIdx + 1] or nil
                if (nextSec) then
                    GameTooltip:AddDoubleLine("Next Stage:",
                        string.format("+%d GS to |c%s%s|r (%d GS)",
                            math.max(0, nextSec.minGS - curGS), nextSec.hex, nextSec.label, nextSec.minGS),
                        0.7, 0.75, 0.82, 0.9, 0.9, 0.9)
                end
                GameTooltip:AddLine(
                    "Forever Stages: Leveling (0–550) · Pre-Raid (550–800) · Tier 1 (800–1000) · Tier 2 (1000–1180) · Tier 3 (1180–1300) · ??? (1300+)",
                    0.68, 0.76, 0.88, true)
            end
            GameTooltip:AddDoubleLine("All-Time Peak / Snapshots:",
                string.format("%d GS · %d pin(s)", peakGS, snaps), 0.7, 0.75, 0.82, 0.35, 0.94, 0.86)
            GameTooltip:AddLine("Hover any vertical cyan/gold line on the bar to inspect past snapshot stats. Click bar to open Progression.", 0.65, 0.7, 0.78, true)
            GameTooltip:Show()
        end
    end)
    headerProg:SetScript("OnLeave", function()
        if (hProgTrack.SetFlatColors) then
            hProgTrack:SetFlatColors(nil, DASH_THEME.borderSubtle)
        end
        if (GameTooltip) then
            GameTooltip:Hide()
        end
    end)
    headerProg:SetScript("OnClick", function()
        if (frame.SelectTab) then
            frame:SelectTab("progression")
        end
    end)

    frame.RefreshHeaderProgress = function()
        if (not (TT and TT.GetPlayerProgression and TT.GetGearLevelInfo)) then
            return
        end
        local rec = TT:GetPlayerProgression()
        local curGS = tonumber(rec.currentScore) or 0
        local peakGS = math.max(curGS, tonumber(rec.peakScore) or 0)
        local cap, bracketSize = 1400, 200
        if (TT.GetGearScoreProgressCap) then
            cap, bracketSize = TT:GetGearScoreProgressCap(curGS, peakGS)
        end
        local lvl = TT:GetGearLevelInfo(curGS)
        local isForeverBar = (CI and CI.IsForever and CI:IsForever() and TT.GetForeverProgressSection ~= nil) or false
        local fSec, fRatio, fIdx
        if (isForeverBar) then
            cap = math.max(1500, peakGS)
            if (cap > 1500) then
                cap = math.ceil(cap / 200) * 200
            end
            fSec, fRatio, fIdx = TT:GetForeverProgressSection(curGS, cap)
        end
        local tierHex = lvl.tierColorHex or "FFFFD100"
        local pct = (cap > 0) and math.min(100, math.max(0, math.floor((curGS / cap) * 100 + 0.5))) or 0

        if (isForeverBar and fSec) then
            hProgLeft:SetText(string.format("|cffffd100Overall Gear|r · |c%s%s|r · |c%sLv.%d %s|r",
                fSec.hex, fSec.label, tierHex, lvl.level or 1, lvl.title or "Novice"))
            hProgMaxLabel:SetText("Lvl · Pre · T1 · T2 · T3 · ???")
        else
            hProgLeft:SetText(string.format("|cffffd100Overall Gear|r · |c%sLv.%d %s|r",
                tierHex, lvl.level or 1, lvl.title or "Novice"))
            hProgMaxLabel:SetText(string.format("%d GS BiS Cap", cap))
        end
        hProgRight:SetText(string.format("|c%s%d|r / %d GS (|cffffd100%d%%|r)",
            tierHex, curGS, cap, pct))
        hProgMinLabel:SetText("0 GS")

        local trackW = (hProgTrack.GetWidth and hProgTrack:GetWidth()) or 0
        if (trackW < 100) then
            trackW = 470
        end
        local innerW = math.max(10, trackW - 2)
        local ratio = isForeverBar and fRatio or ((cap > 0) and math.min(1, math.max(0, curGS / cap)) or 0)
        if (curGS > 0) then
            local fillW = math.min(innerW, math.max(2, math.floor(innerW * ratio + 0.5)))
            hProgFill:SetWidth(fillW)
            hProgFill:Show()
            hProgCursor:Show()
        else
            hProgFill:SetWidth(1)
            hProgFill:Hide()
            hProgCursor:Hide()
        end

        local gsGlobal = rawget(_G, "TT_GS")
        local r, g, b = 0.18, 0.72, 0.40
        if (curGS > 0 and gsGlobal and gsGlobal.GetQuality) then
            local qr, qg, qb = gsGlobal:GetQuality(curGS)
            if (qr and qg and qb) then
                r, g, b = qr, qg, qb
            end
        elseif (curGS == 0) then
            r, g, b = 0.35, 0.38, 0.44
        end
        hProgFill:SetVertexColor(r, g, b, 0.88)

        if (peakGS > curGS and cap > 0) then
            local peakRatio = isForeverBar and select(2, TT:GetForeverProgressSection(peakGS, cap)) or math.min(1, peakGS / cap)
            local peakX = math.min(innerW - 1, math.max(1, math.floor(innerW * peakRatio + 0.5)))
            hProgPeak:ClearAllPoints()
            hProgPeak:SetPoint("LEFT", hProgTrack, "LEFT", peakX, 0)
            hProgPeak:Show()
        else
            hProgPeak:Hide()
        end

        local sections = TT.FOREVER_GS_SECTIONS
        if (isForeverBar and sections) then
            for idx = 1, #sections - 1 do
                local tick = hProgBracketTicks[idx]
                local sec = sections[idx]
                if (tick and sec) then
                    local divX = math.floor(innerW * sec.maxPct + 0.5)
                    tick:ClearAllPoints()
                    tick:SetPoint("LEFT", hProgTrack, "LEFT", divX, 0)
                    tick:SetVertexColor(0.95, 0.82, 0.32, 0.48)
                    tick:Show()
                elseif (tick) then
                    tick:Hide()
                end
            end
            for idx = #sections, #hProgBracketTicks do
                if (hProgBracketTicks[idx]) then
                    hProgBracketTicks[idx]:Hide()
                end
            end
            for idx = 1, #sections do
                local sec = sections[idx]
                local band = hProgStageBands[idx]
                if (band and sec) then
                    local x1 = 1 + math.floor(innerW * sec.minPct + 0.5)
                    local x2 = 1 + math.floor(innerW * sec.maxPct + 0.5)
                    band:ClearAllPoints()
                    band:SetPoint("TOPLEFT", hProgTrack, "TOPLEFT", x1, -1)
                    band:SetPoint("BOTTOMLEFT", hProgTrack, "BOTTOMLEFT", x1, 1)
                    band:SetWidth(math.max(1, x2 - x1))
                    band:SetVertexColor(sec.r or 0.5, sec.g or 0.5, sec.b or 0.5, (idx == fIdx) and 0.18 or 0.06)
                    band:Show()
                end
                local fl = hProgTrack._foreverLabels and hProgTrack._foreverLabels[idx]
                if (fl and sec) then
                    local midX = math.floor(innerW * ((sec.minPct + sec.maxPct) * 0.5) + 0.5)
                    fl:ClearAllPoints()
                    fl:SetPoint("CENTER", hProgTrack, "LEFT", midX, 0)
                    if (idx == fIdx) then
                        fl:SetText("|c" .. sec.hex .. sec.label .. "|r")
                    else
                        fl:SetText("|cff9aa3b2" .. sec.label .. "|r")
                    end
                    fl:Show()
                end
            end
        else
            for idx = 1, #hProgStageBands do
                if (hProgStageBands[idx]) then
                    hProgStageBands[idx]:Hide()
                end
            end
            for idx = 1, #(hProgTrack._foreverLabels or {}) do
                if (hProgTrack._foreverLabels[idx]) then
                    hProgTrack._foreverLabels[idx]:Hide()
                end
            end
            for bracketIdx = 1, 6 do
                local threshold = bracketIdx * bracketSize
                local tick = hProgBracketTicks[bracketIdx]
                if (tick and cap > 0 and threshold < cap) then
                    local divX = math.floor(innerW * (threshold / cap) + 0.5)
                    tick:ClearAllPoints()
                    tick:SetPoint("LEFT", hProgTrack, "LEFT", divX, 0)
                    tick:SetVertexColor(1, 1, 1, 0.14)
                    tick:Show()
                elseif (tick) then
                    tick:Hide()
                end
            end
        end

        local snaps = (TT.GetProgressionBarSnapshots and TT:GetProgressionBarSnapshots(HEADER_PROG_MAX_PINS)) or {}
        headerProg._snapCount = #snaps
        hProgHintLabel:SetText(#snaps > 0
            and string.format("%d snapshot(s) · Hover ticks for stats", #snaps)
            or "Hover bar for stats · Click to open Progression")
        for idx = 1, HEADER_PROG_MAX_PINS do
            local pin = hProgSnapTicks[idx]
            local snap = snaps[idx]
            if (pin and snap and cap > 0) then
                local sGS = tonumber(snap.totalGS) or 0
                local sRatio = isForeverBar and select(2, TT:GetForeverProgressSection(sGS, cap)) or math.min(1, math.max(0, sGS / cap))
                local pinX = math.min(innerW, math.max(1, math.floor(innerW * sRatio + 0.5)))
                pin._snapData = snap
                pin._snapIndex = idx
                pin._barCap = cap
                pin._currentScore = curGS
                pin._isPeak = (sGS >= peakGS and peakGS > 0)
                if (pin._isPeak) then
                    pin._line:SetVertexColor(1.0, 0.82, 0.15, 0.95)
                else
                    pin._line:SetVertexColor(0.35, 0.94, 0.86, 0.90)
                end
                pin:ClearAllPoints()
                pin:SetPoint("CENTER", hProgTrack, "LEFT", pinX, 0)
                pin:Show()
            elseif (pin) then
                pin._snapData = nil
                pin:Hide()
            end
        end
    end

    frame._headerProg = headerProg
    frame._headerProgTicks = hProgSnapTicks
    if (hProgTrack.SetScript) then
        hProgTrack:SetScript("OnSizeChanged", function()
            if (frame.IsShown and frame:IsShown() and frame.RefreshHeaderProgress) then
                frame:RefreshHeaderProgress()
            end
        end)
    end
    frame._headerProgFill = hProgFill
    frame._headerProgRightText = hProgRight

    -- Left Sidebar (Narrower: 155px wide, compact tab buttons)
    local sidebar = CreateFrame("Frame", nil, frame)
    sidebar:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    sidebar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 31)
    sidebar:SetWidth(155)
    paintFlatBox(sidebar, DASH_THEME.sidebarBg)

    -- Right Content Area (Extends down to bottom near sleek footer)
    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 14, -12)
    content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 36)

    -- Bottom Persistent Footer (Sleek: 30px height)
    local footer = CreateFrame("Frame", nil, frame)
    footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 1)
    footer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    footer:SetHeight(30)
    paintFlatBox(footer, DASH_THEME.headerBg)

    local hint = footer:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("LEFT", footer, "LEFT", 14, 0)
    hint:SetText("/tt · ESC to close")

    local moveCard = createFlatActionCard(footer, 125, 22, "Move Tooltip", "emerald", function()
        showTooltipMover()
    end, "Move Tooltip", "Show the live tooltip mover so you can drag and save a custom tooltip position.")
    moveCard:SetPoint("RIGHT", footer, "RIGHT", -12, 0)

    local DASH_CARD_W = 732

    local resetArmed = false
    local resetCard
    resetCard = createFlatActionCard(footer, 145, 22, "Reset Configuration", "danger", function(self)
        if (not resetArmed) then
            resetArmed = true
            self.text:SetText("|cffffd100Confirm Reset?|r")
            self:SetFlatColors({ 0.35, 0.12, 0.10, 1.0 }, DASH_THEME.borderAmber)
            if (type(_G.C_Timer) == "table" and type(_G.C_Timer.After) == "function") then
                pcall(_G.C_Timer.After, 4, function()
                    if (resetArmed and self and self.text) then
                        resetArmed = false
                        self.text:SetText("Reset Configuration")
                        self:SetFlatColors({ 0.16, 0.11, 0.11, 0.96 }, DASH_THEME.borderSubtle)
                    end
                end)
            end
            return
        end
        resetArmed = false
        self.text:SetText("Reset Configuration")
        self:SetFlatColors({ 0.16, 0.11, 0.11, 0.96 }, DASH_THEME.borderSubtle)
        resetCfg()
        if (TT.RefreshOptionsUI) then TT:RefreshOptionsUI() end
        if (frame.RefreshAll) then frame:RefreshAll() end
        print("|cff59f0dcTacoTip:|r Configuration restored to defaults.")
    end, "Reset Configuration", "Click once to arm, then click again to restore every TacoTip setting to its default.")
    resetCard:SetPoint("RIGHT", moveCard, "LEFT", -8, 0)
    resetCard:HookScript("OnLeave", function(self)
        if (resetArmed) then
            self:SetFlatColors({ 0.35, 0.12, 0.10, 1.0 }, DASH_THEME.borderAmber)
        end
    end)

    -- Sidebar Search Box (Matching narrower 155px sidebar)
    local searchBox = CreateFrame("EditBox", "TacoTipDashboardSearch", sidebar, "InputBoxTemplate")
    searchBox:SetSize(113, 22)
    searchBox:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 12, -10)
    searchBox:SetAutoFocus(false)
    searchBox:SetFontObject("GameFontHighlightSmall")

    local searchPlaceholder = searchBox:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    searchPlaceholder:SetPoint("LEFT", searchBox, "LEFT", 4, 0)
    searchPlaceholder:SetText("Search settings...")

    local searchClearBtn = createFlatActionCard(sidebar, 18, 18, "x", "plain", function()
        searchBox:SetText("")
        searchBox:ClearFocus()
    end, "Clear Search", "Reset the settings search filter.")
    searchClearBtn:SetPoint("LEFT", searchBox, "RIGHT", 2, 0)
    searchClearBtn:Hide()

    -- Shared floating picker menu for flat dropdown rows (avoids UIDropDownMenu taint)
    local pickerPopup = CreateFrame("Frame", nil, frame)
    pickerPopup:SetFrameStrata("FULLSCREEN_DIALOG")
    pickerPopup:SetFrameLevel(clampFrameLevel(frame:GetFrameLevel() + 20))
    pickerPopup:EnableMouse(true)
    pickerPopup:EnableMouseWheel(true)
    paintFlatBox(pickerPopup, DASH_THEME.headerBg, DASH_THEME.borderGold)
    pickerPopup:Hide()
    local pickerPopupRows = {}
    local pickerPopupChoices = {}
    local pickerPopupOffset = 0
    local pickerPopupMaxRows = 9
    local pickerPopupOnSelect = nil
    local pickerPopupSelected = nil

    local function renderPickerPopup()
        local total = #pickerPopupChoices
        local maxOffset = math.max(0, total - pickerPopupMaxRows)
        if (pickerPopupOffset > maxOffset) then pickerPopupOffset = maxOffset end
        if (pickerPopupOffset < 0) then pickerPopupOffset = 0 end
        local visible = math.min(total, pickerPopupMaxRows)
        local h = math.max(28, visible * 22 + 8)
        pickerPopup:SetSize(250, h)
        for i = 1, pickerPopupMaxRows do
            local row = pickerPopupRows[i]
            if (not row) then
                row = CreateFrame("Button", nil, pickerPopup)
                row:SetSize(238, 20)
                row:SetPoint("TOPLEFT", pickerPopup, "TOPLEFT", 6, -4 - (i - 1) * 22)
                paintFlatBox(row, DASH_THEME.cardBg, DASH_THEME.headerBg)
                local txt = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                txt:SetPoint("LEFT", row, "LEFT", 8, 0)
                txt:SetPoint("RIGHT", row, "RIGHT", -8, 0)
                txt:SetJustifyH("LEFT")
                row.txt = txt
                row:SetScript("OnEnter", function(self)
                    self:SetFlatColors(DASH_THEME.cardHoverBg, DASH_THEME.borderGold)
                end)
                row:SetScript("OnLeave", function(self)
                    local sel = (self._choice and self._choice.value == pickerPopupSelected)
                    self:SetFlatColors(sel and DASH_THEME.cardActiveBg or DASH_THEME.cardBg,
                        sel and DASH_THEME.borderGold or DASH_THEME.headerBg)
                end)
                row:SetScript("OnClick", function(self)
                    local ch = self._choice
                    pickerPopup:Hide()
                    if (ch and pickerPopupOnSelect) then
                        safeCall(pickerPopupOnSelect, ch.value, ch)
                    end
                end)
                pickerPopupRows[i] = row
            end
            local ch = pickerPopupChoices[pickerPopupOffset + i]
            if (ch) then
                row._choice = ch
                local sel = (ch.value == pickerPopupSelected)
                row.txt:SetText((sel and "|cffffd100► " or "") .. tostring(ch.text or ch.value or "") .. (sel and "|r" or ""))
                row:SetFlatColors(sel and DASH_THEME.cardActiveBg or DASH_THEME.cardBg,
                    sel and DASH_THEME.borderGold or DASH_THEME.headerBg)
                row:Show()
            else
                row._choice = nil
                row:Hide()
            end
        end
    end
    pickerPopup:SetScript("OnMouseWheel", function(_, delta)
        pickerPopupOffset = pickerPopupOffset - delta * 2
        renderPickerPopup()
    end)

    local function openFlatPickerMenu(anchorFrame, choices, selectedVal, onSelect)
        if (pickerPopup:IsShown() and pickerPopup._anchor == anchorFrame) then
            pickerPopup:Hide()
            return
        end
        pickerPopup._anchor = anchorFrame
        pickerPopupChoices = choices or {}
        pickerPopupSelected = selectedVal
        pickerPopupOnSelect = onSelect
        pickerPopupOffset = 0
        for idx, ch in ipairs(pickerPopupChoices) do
            if (ch.value == selectedVal) then
                pickerPopupOffset = math.max(0, idx - 4)
                break
            end
        end
        pickerPopup:ClearAllPoints()
        pickerPopup:SetPoint("TOPRIGHT", anchorFrame, "BOTTOMRIGHT", 0, -2)
        renderPickerPopup()
        pickerPopup:Show()
    end

    -- Helper: Pill Toggle Switch Card
    local function createPillToggle(parent, titleText, descText, initialVal, onToggle)
        local card = CreateFrame("Frame", nil, parent)
        card:SetSize(DASH_CARD_W, 42)
        card:EnableMouse(true)
        paintFlatBox(card, DASH_THEME.cardBg, DASH_THEME.borderSubtle)

        local t = card:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        t:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -6)
        t:SetText(titleText or "")

        local d = card:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        d:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -2)
        d:SetPoint("RIGHT", card, "RIGHT", -64, 0)
        d:SetJustifyH("LEFT")
        d:SetText(descText or "")

        local pill = CreateFrame("Frame", nil, card)
        pill:SetSize(38, 18)
        pill:SetPoint("RIGHT", card, "RIGHT", -14, 0)
        paintFlatBox(pill, { 0.16, 0.18, 0.18, 1 }, { 0.28, 0.30, 0.30, 1 })

        local knob = pill:CreateTexture(nil, "ARTWORK")
        knob:SetTexture(WHITE8X8)
        knob:SetSize(12, 12)

        local isChecked = initialVal and true or false
        local isDisabled = false
        local disabledReason = nil

        local function updatePill()
            if (isDisabled) then return end
            if (isChecked) then
                pill:SetFlatColors({ 0.70, 0.86, 0.20, 0.95 }, DASH_THEME.borderEmerald)
                knob:ClearAllPoints()
                knob:SetPoint("RIGHT", pill, "RIGHT", -3, 0)
                knob:SetVertexColor(0.10, 0.12, 0.08, 1)
            else
                pill:SetFlatColors({ 0.16, 0.18, 0.18, 1 }, { 0.28, 0.30, 0.30, 1 })
                knob:ClearAllPoints()
                knob:SetPoint("LEFT", pill, "LEFT", 3, 0)
                knob:SetVertexColor(0.60, 0.65, 0.60, 1)
            end
        end
        updatePill()

        card:SetScript("OnEnter", function(self)
            if (isDisabled) then
                if (disabledReason) then
                    showHoverTooltip(self, titleText, "|cffff8080" .. disabledReason .. "|r")
                end
                return
            end
            self:SetFlatColors(DASH_THEME.cardHoverBg, DASH_THEME.borderGold)
        end)
        card:SetScript("OnLeave", function(self)
            if (isDisabled) then
                if (disabledReason and GameTooltip) then GameTooltip:Hide() end
                return
            end
            self:SetFlatColors(DASH_THEME.cardBg, DASH_THEME.borderSubtle)
        end)
        card:SetScript("OnMouseDown", function()
            if (isDisabled) then return end
            isChecked = not isChecked
            updatePill()
            if (onToggle) then
                safeCall(onToggle, isChecked)
            end
        end)

        card.SetChecked = function(_, val)
            isChecked = val and true or false
            updatePill()
        end
        card.GetChecked = function() return isChecked end
        card.SetDisabled = function(_, disabled, reason)
            isDisabled = disabled and true or false
            disabledReason = reason
            if (isDisabled) then
                t:SetTextColor(DASH_THEME.textDisabled[1], DASH_THEME.textDisabled[2], DASH_THEME.textDisabled[3])
                d:SetTextColor(DASH_THEME.textDisabled[1], DASH_THEME.textDisabled[2], DASH_THEME.textDisabled[3])
                pill:SetFlatColors({ 0.12, 0.13, 0.14, 0.8 }, { 0.20, 0.22, 0.24, 0.8 })
                knob:SetVertexColor(0.35, 0.38, 0.40, 0.8)
            else
                t:SetTextColor(DASH_THEME.textPrimary[1], DASH_THEME.textPrimary[2], DASH_THEME.textPrimary[3])
                d:SetTextColor(DASH_THEME.textMuted[1], DASH_THEME.textMuted[2], DASH_THEME.textMuted[3])
                updatePill()
            end
        end
        card.searchText = strlower((titleText or "") .. " " .. (descText or ""))
        return card
    end

    -- Helper: Slider Card
    local function createDashboardSlider(parent, titleText, descText, minVal, maxVal, step, initialVal, onValueChange, formatVal)
        local card = CreateFrame("Frame", nil, parent)
        card:SetSize(DASH_CARD_W, 48)
        card:EnableMouse(true)
        paintFlatBox(card, DASH_THEME.cardBg, DASH_THEME.borderSubtle)

        local t = card:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        t:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -6)
        t:SetText(titleText or "")

        local d = card:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        d:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -2)
        d:SetPoint("RIGHT", card, "RIGHT", -190, 0)
        d:SetJustifyH("LEFT")
        d:SetText(descText or "")

        local valText = card:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        valText:SetPoint("RIGHT", card, "RIGHT", -14, 0)
        valText:SetJustifyH("RIGHT")

        local slider = CreateFrame("Slider", nil, card, "OptionsSliderTemplate")
        slider:SetSize(120, 14)
        slider:SetPoint("RIGHT", valText, "LEFT", -10, 0)
        slider:SetMinMaxValues(minVal, maxVal)
        slider:SetValueStep(step or 1)
        slider:EnableMouseWheel(true)
        if (slider.SetObeyStepOnDrag) then slider:SetObeyStepOnDrag(true) end

        local isDisabled = false
        local disabledReason = nil

        local function display(v)
            if (formatVal) then
                valText:SetText(formatVal(v))
            else
                valText:SetText(tostring(v))
            end
        end
        local current = initialVal or minVal
        display(current)
        slider._refreshing = true
        slider:SetValue(current)
        slider._refreshing = false

        slider:SetScript("OnValueChanged", function(self, val)
            val = math.floor((val / (step or 1)) + 0.5) * (step or 1)
            display(val)
            if (not self._refreshing and not isDisabled and onValueChange) then
                safeCall(onValueChange, val)
            end
        end)
        slider:SetScript("OnMouseWheel", function(self, delta)
            if (isDisabled) then return end
            local s = step or 1
            local nextV = math.max(minVal, math.min(maxVal, (self:GetValue() or minVal) + delta * s))
            self:SetValue(nextV)
        end)

        card:SetScript("OnEnter", function(self)
            if (isDisabled) then
                if (disabledReason) then
                    showHoverTooltip(self, titleText, "|cffff8080" .. disabledReason .. "|r")
                end
                return
            end
            self:SetFlatColors(DASH_THEME.cardHoverBg, DASH_THEME.borderGold)
        end)
        card:SetScript("OnLeave", function(self)
            if (isDisabled and disabledReason and GameTooltip) then
                GameTooltip:Hide()
            end
            self:SetFlatColors(DASH_THEME.cardBg, DASH_THEME.borderSubtle)
        end)

        card.SetValueSilently = function(_, v)
            slider._refreshing = true
            display(v)
            slider:SetValue(v)
            slider._refreshing = false
        end
        card.SetValue = function(_, v)
            card:SetValueSilently(v)
        end
        card.SetDisabled = function(_, disabled, reason)
            isDisabled = disabled and true or false
            disabledReason = reason
            if (isDisabled) then
                if (slider.Disable) then slider:Disable() end
                t:SetTextColor(DASH_THEME.textDisabled[1], DASH_THEME.textDisabled[2], DASH_THEME.textDisabled[3])
                d:SetTextColor(DASH_THEME.textDisabled[1], DASH_THEME.textDisabled[2], DASH_THEME.textDisabled[3])
                valText:SetTextColor(DASH_THEME.textDisabled[1], DASH_THEME.textDisabled[2], DASH_THEME.textDisabled[3])
                card:SetAlpha(0.55)
            else
                if (slider.Enable) then slider:Enable() end
                t:SetTextColor(DASH_THEME.textPrimary[1], DASH_THEME.textPrimary[2], DASH_THEME.textPrimary[3])
                d:SetTextColor(DASH_THEME.textMuted[1], DASH_THEME.textMuted[2], DASH_THEME.textMuted[3])
                valText:SetTextColor(DASH_THEME.textPrimary[1], DASH_THEME.textPrimary[2], DASH_THEME.textPrimary[3])
                card:SetAlpha(1.0)
            end
        end
        card.searchText = strlower((titleText or "") .. " " .. (descText or ""))
        return card
    end

    -- Helper: Segmented Pill Choice Row
    local function createFlatChoiceRow(parent, titleText, descText, choices, initialVal, onSelect, btnWidth)
        local card = CreateFrame("Frame", nil, parent)
        card:SetSize(DASH_CARD_W, 48)
        card:EnableMouse(true)
        paintFlatBox(card, DASH_THEME.cardBg, DASH_THEME.borderSubtle)

        local bw = btnWidth or 52
        local rightPad = #choices * (bw + 6) + 20

        local t = card:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        t:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -7)
        t:SetText(titleText or "")

        local d = card:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        d:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -2)
        d:SetPoint("RIGHT", card, "RIGHT", -rightPad, 0)
        d:SetJustifyH("LEFT")
        d:SetText(descText or "")

        ---@type any[]
        local choiceBtns = {}
        local isDisabled = false
        local disabledReason = nil
        local currentVal = initialVal

        local function refreshBtns()
            card:SetAlpha(isDisabled and 0.48 or 1.0)
            for _, btn in ipairs(choiceBtns) do
                local active = (currentVal == btn._val)
                if (active) then
                    btn:SetFlatColors(DASH_THEME.cardActiveBg, DASH_THEME.borderGold)
                    btn.txt:SetText("|cffffd100" .. btn._label .. "|r")
                else
                    btn:SetFlatColors(DASH_THEME.cardBg, DASH_THEME.borderSubtle)
                    btn.txt:SetText("|cffb0b8c4" .. btn._label .. "|r")
                end
            end
        end

        for idx = #choices, 1, -1 do
            local ch = choices[idx]
            ---@type any
            local btn = CreateFrame("Frame", nil, card)
            btn:SetSize(bw, 24)
            btn:EnableMouse(true)
            paintFlatBox(btn, DASH_THEME.cardBg, DASH_THEME.borderSubtle)
            if (idx == #choices) then
                btn:SetPoint("RIGHT", card, "RIGHT", -12, 0)
            else
                btn:SetPoint("RIGHT", choiceBtns[1], "LEFT", -6, 0)
            end
            local txt = btn:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            txt:SetPoint("CENTER", btn, "CENTER", 0, 0)
            btn.txt = txt
            btn._val = ch.value
            btn._label = ch.label
            btn:SetScript("OnEnter", ---@param self any
                function(self)
                    if (isDisabled) then return end
                    self:SetFlatColors(DASH_THEME.cardHoverBg, DASH_THEME.borderGold)
                end)
            btn:SetScript("OnLeave", function() refreshBtns() end)
            btn:SetScript("OnMouseDown", function()
                if (isDisabled) then return end
                currentVal = ch.value
                refreshBtns()
                if (onSelect) then safeCall(onSelect, ch.value) end
            end)
            table.insert(choiceBtns, 1, btn)
        end

        card:SetScript("OnEnter", function(self)
            if (isDisabled and disabledReason) then
                showHoverTooltip(self, titleText, "|cffff8080" .. disabledReason .. "|r")
            end
        end)
        card:SetScript("OnLeave", function()
            if (isDisabled and disabledReason and GameTooltip) then GameTooltip:Hide() end
        end)

        card.SetValue = function(_, val)
            currentVal = val
            refreshBtns()
        end
        card.SetDisabled = function(_, disabled, reason)
            isDisabled = disabled and true or false
            disabledReason = reason
            refreshBtns()
        end
        refreshBtns()
        card.searchText = strlower((titleText or "") .. " " .. (descText or ""))
        return card
    end

    -- Helper: Flat Dropdown / Cycle Picker Row
    local function createFlatPickerRow(parent, titleText, descText, getChoicesFn, getValFn, onSelect)
        local card = CreateFrame("Frame", nil, parent)
        card:SetSize(DASH_CARD_W, 46)
        card:EnableMouse(true)
        paintFlatBox(card, DASH_THEME.cardBg, DASH_THEME.borderSubtle)

        local t = card:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        t:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -7)
        t:SetText(titleText or "")

        local d = card:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        d:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -2)
        d:SetPoint("RIGHT", card, "RIGHT", -270, 0)
        d:SetJustifyH("LEFT")
        d:SetText(descText or "")

        local nextBtn = createFlatActionCard(card, 22, 24, ">", "plain")
        nextBtn:SetPoint("RIGHT", card, "RIGHT", -12, 0)

        local pickBtn = createFlatActionCard(card, 194, 24, "Default", "plain")
        pickBtn:SetPoint("RIGHT", nextBtn, "LEFT", -4, 0)

        local prevBtn = createFlatActionCard(card, 22, 24, "<", "plain")
        prevBtn:SetPoint("RIGHT", pickBtn, "LEFT", -4, 0)

        local isDisabled = false
        local function refreshValue()
            local choices = (getChoicesFn and getChoicesFn()) or {}
            local cur = getValFn and getValFn()
            local label = tostring(cur or "Default")
            for _, ch in ipairs(choices) do
                if (ch.value == cur) then
                    label = ch.text or ch.label or tostring(cur)
                    break
                end
            end
            pickBtn.text:SetText("|cffffd100" .. label .. "|r")
            card:SetAlpha(isDisabled and 0.48 or 1.0)
        end

        local function stepChoice(dir)
            if (isDisabled) then return end
            local choices = (getChoicesFn and getChoicesFn()) or {}
            if (#choices == 0) then return end
            local cur = getValFn and getValFn()
            local curIdx = 1
            for idx, ch in ipairs(choices) do
                if (ch.value == cur) then curIdx = idx; break end
            end
            local nextIdx = ((curIdx - 1 + dir) % #choices) + 1
            local chosen = choices[nextIdx]
            if (chosen and onSelect) then
                safeCall(onSelect, chosen.value, chosen)
                refreshValue()
            end
        end

        prevBtn:SetScript("OnMouseDown", function() stepChoice(-1) end)
        nextBtn:SetScript("OnMouseDown", function() stepChoice(1) end)
        pickBtn:SetScript("OnMouseDown", function(self)
            if (isDisabled) then return end
            local choices = (getChoicesFn and getChoicesFn()) or {}
            openFlatPickerMenu(self, choices, getValFn and getValFn(), function(val, ch)
                if (onSelect) then safeCall(onSelect, val, ch) end
                refreshValue()
            end)
        end)

        card.RefreshValue = function() refreshValue() end
        card.SetDisabled = function(_, disabled)
            isDisabled = disabled and true or false
            refreshValue()
        end
        refreshValue()
        card.searchText = strlower((titleText or "") .. " " .. (descText or ""))
        return card
    end

    -- Helper: Flat Color Swatch Row
    local function createFlatColorRow(parent, titleText, descText, getRGB, onColorChanged, defaultRGB)
        local card = CreateFrame("Frame", nil, parent)
        card:SetSize(DASH_CARD_W, 46)
        paintFlatBox(card, DASH_THEME.cardBg, DASH_THEME.borderSubtle)

        local t = card:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        t:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -7)
        t:SetText(titleText or "")

        local d = card:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        d:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -2)
        d:SetPoint("RIGHT", card, "RIGHT", -200, 0)
        d:SetJustifyH("LEFT")
        d:SetText(descText or "")

        local resetColorBtn = createFlatActionCard(card, 54, 24, "Reset", "plain", function()
            if (defaultRGB and onColorChanged) then
                safeCall(onColorChanged, defaultRGB[1], defaultRGB[2], defaultRGB[3])
            end
        end)
        resetColorBtn:SetPoint("RIGHT", card, "RIGHT", -12, 0)

        local pickColorBtn = createFlatActionCard(card, 86, 24, "Pick Color", "gold")
        pickColorBtn:SetPoint("RIGHT", resetColorBtn, "LEFT", -6, 0)

        local swatchBox = CreateFrame("Frame", nil, card)
        swatchBox:SetSize(24, 24)
        swatchBox:SetPoint("RIGHT", pickColorBtn, "LEFT", -8, 0)
        paintFlatBox(swatchBox, { 1, 1, 1, 1 }, DASH_THEME.borderGold)

        local function refreshSwatch()
            local r, g, b = 1, 1, 1
            if (getRGB) then r, g, b = getRGB() end
            swatchBox:SetFlatColors({ r or 1, g or 1, b or 1, 1 }, DASH_THEME.borderGold)
        end

        pickColorBtn:SetScript("OnMouseDown", function()
            local r, g, b = 1, 1, 1
            if (getRGB) then r, g, b = getRGB() end
            openColorPicker(r, g, b, function(nr, ng, nb)
                if (onColorChanged) then
                    safeCall(onColorChanged, nr, ng, nb)
                end
                refreshSwatch()
            end)
        end)

        card.RefreshColor = function() refreshSwatch() end
        refreshSwatch()
        card.searchText = strlower((titleText or "") .. " " .. (descText or ""))
        return card
    end

    -- Helper: Callout Notice Box
    local function createNoticeBox(parent, iconLabel, noticeText, isEmerald, customHeight)
        local box = CreateFrame("Frame", nil, parent)
        box:SetSize(DASH_CARD_W, customHeight or 34)
        local borderCol = isEmerald and DASH_THEME.borderEmerald or DASH_THEME.borderGold
        local bgCol = isEmerald and { 0.08, 0.22, 0.14, 0.95 } or { 0.22, 0.17, 0.06, 0.95 }
        paintFlatBox(box, bgCol, borderCol)

        local ic = box:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        ic:SetPoint("LEFT", box, "LEFT", 10, 0)
        ic:SetText(iconLabel or "|cffffd100[TIP]|r")

        local txt = box:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        txt:SetPoint("LEFT", ic, "RIGHT", 8, 0)
        txt:SetPoint("RIGHT", box, "RIGHT", -12, 0)
        txt:SetJustifyH("LEFT")
        txt:SetText(noticeText or "")
        return box
    end

    -- Navigation Structure
    local hasExtras = false
    if (type(rawget(_G, "TacoTipExtrasToggleLeaderboard")) == "function")
            or (type(rawget(_G, "TacoTipExtrasDB")) == "table") then
        hasExtras = true
    elseif (type(rawget(_G, "C_AddOns")) == "table" and type(_G.C_AddOns.IsAddOnLoaded) == "function") then
        local ok, loaded = pcall(_G.C_AddOns.IsAddOnLoaded, "TacoTip_Extras")
        if (ok and loaded) then hasExtras = true end
    elseif (type(rawget(_G, "IsAddOnLoaded")) == "function") then
        local ok, loaded = pcall(_G.IsAddOnLoaded, "TacoTip_Extras")
        if (ok and loaded) then hasExtras = true end
    end

    local tabs, tabButtons, tabLabels, tabScrollChildren, tabDefaultHeights = {}, {}, {}, {}, {}
    local tabLayoutEntries = {}
    local activeSectionByTab = {}
    local allSearchItems = {}
    local syncControls = {}
    local orderedCategoryIds = {
        "general", "units", "appearance", "portrait", "positioning", "character", "progression", "diagnostics", "community", "reset"
    }
    if (hasExtras) then
        tinsert(orderedCategoryIds, 8, "extras")
    end

    local applySearch
    local inSearchUpdate = false

    local function selectTab(id)
        if (pickerPopup and pickerPopup:IsShown()) then pickerPopup:Hide() end
        for tabId, tab in pairs(tabs) do
            tab:SetShown(tabId == id)
            local btn = tabButtons[tabId]
            if (btn) then
                btn:SetFlatColors(tabId == id and DASH_THEME.cardActiveBg or DASH_THEME.sidebarBg,
                    tabId == id and DASH_THEME.borderGold or DASH_THEME.sidebarBg)
            end
        end
        frame.activeTab = id
        if (applySearch and not inSearchUpdate) then
            applySearch()
        end
        if (id == "diagnostics" and frame.RefreshDiagnostics) then frame:RefreshDiagnostics() end
        if (id == "extras" and frame.RefreshEmbeddedLeaderboard) then frame:RefreshEmbeddedLeaderboard() end
        if (id == "progression" and frame.RefreshProgression) then frame:RefreshProgression() end
    end
    frame.SelectTab = function(_, id) if (tabs[id]) then selectTab(id) end end

    local function addTab(id, label, order, isBottom)
        local page = CreateFrame("Frame", nil, content)
        page:SetAllPoints(content)
        page:Hide()
        tabs[id] = page
        tabLabels[id] = label

        local yPos
        if (isBottom) then
            local bottomStart = hasExtras and -308 or -276
            yPos = bottomStart - (order - 1) * 32
        else
            yPos = -38 - (order - 1) * 32
        end
        local btn = createFlatActionCard(sidebar, 135, 28, label, "plain", function() selectTab(id) end)
        btn:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 10, yPos)
        tabButtons[id] = btn
        return page
    end

    -- Subtle sidebar divider line between category tabs and utility tabs
    local sideDiv = sidebar:CreateTexture(nil, "BORDER")
    sideDiv:SetTexture(WHITE8X8)
    sideDiv:SetSize(133, 1)
    sideDiv:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 11, hasExtras and -300 or -268)
    sideDiv:SetVertexColor(0.24, 0.28, 0.34, 0.8)

    local function createScrollCategory(id, label, titleText, descText, order, isBottom)
        local page = addTab(id, label, order, isBottom)
        local ph = page:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        ph:SetPoint("TOPLEFT", page, "TOPLEFT", 4, 0)
        ph:SetText("|cffffd100" .. titleText .. "|r")

        local pd = createWrappedText(page, "GameFontHighlightSmall", DASH_CARD_W, descText)
        pd:SetPoint("TOPLEFT", ph, "BOTTOMLEFT", 0, -4)

        local scroll, scrollChild = createScrollPage(page)
        scroll:ClearAllPoints()
        scroll:SetPoint("TOPLEFT", pd, "BOTTOMLEFT", 0, -8)
        scroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -18, 4)
        tabScrollChildren[id] = scrollChild
        tabLayoutEntries[id] = {}
        return page, scrollChild
    end

    local function registerRow(scrollChild, card, tabId, rowY, height, gap)
        local h = height or 42
        local g = gap or 8
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, rowY)
        card.tabId = tabId
        card.defaultY = rowY
        card._layoutHeight = h
        card._layoutGap = g
        card._scrollChild = scrollChild
        card._sectionHeader = activeSectionByTab[tabId]
        allSearchItems[#allSearchItems + 1] = card
        local list = tabLayoutEntries[tabId]
        if (list) then
            list[#list + 1] = { kind = "card", frame = card, defaultY = rowY, height = h, gap = g, section = activeSectionByTab[tabId] }
        end
        return rowY - h - g
    end

    local function registerStaticRow(scrollChild, card, tabId, rowY, height, gap)
        local h = height or 34
        local g = gap or 8
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, rowY)
        card.defaultY = rowY
        local list = tabLayoutEntries[tabId]
        if (list) then
            list[#list + 1] = { kind = "static", frame = card, defaultY = rowY, height = h, gap = g }
        end
        return rowY - h - g
    end

    local function addSectionHeader(scrollChild, headerText, curY, tabId)
        local h = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        h:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 6, curY - 4)
        h:SetText("|cffffd100" .. headerText .. "|r")
        h._defaultY = curY - 4
        if (tabId) then
            activeSectionByTab[tabId] = h
            local list = tabLayoutEntries[tabId]
            if (list) then
                list[#list + 1] = { kind = "header", frame = h, defaultY = curY - 4, height = 22, gap = 4 }
            end
        end
        return curY - 26
    end

    local function onSettingChanged()
        if (TT.RefreshOpenUnitTooltip) then TT:RefreshOpenUnitTooltip() end
        if (refreshOverlayPositions) then refreshOverlayPositions() end
        if (modernGetConfig) then modernGetConfig() end
    end

    -- ========================================================================
    -- Tab 1: General
    -- ========================================================================
    do
        local _, generalChild = createScrollCategory("general", "General", "General",
            "Choose your tooltip style, language, and core preferences.", 1)
        local gy = 0
        gy = addSectionHeader(generalChild, "Tooltip Style Presets", gy, "general")

        local styleGrid = CreateFrame("Frame", nil, generalChild)
        styleGrid:SetSize(DASH_CARD_W, 112)
        styleGrid.searchText = "tooltip style preset wide compact mini shift detail layout preview"

        local styleCards = {}
        local presets = {
            { value = 1, text = "Wide", sub = "Always full detail" },
            { value = 2, text = "Compact + Shift", sub = "Compact, SHIFT for full" },
            { value = 3, text = "Compact", sub = "Always compact" },
            { value = 4, text = "Mini + Shift", sub = "Mini, SHIFT for full" },
            { value = 5, text = "Mini", sub = "Always mini" },
        }

        local previewCard = CreateFrame("Frame", nil, styleGrid)
        previewCard:SetSize(238, 50)
        previewCard:SetPoint("TOPLEFT", styleGrid, "TOPLEFT", 2 * 247, -56)
        paintFlatBox(previewCard, DASH_THEME.headerBg, DASH_THEME.borderEmerald)

        local previewTitle = previewCard:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        previewTitle:SetPoint("TOPLEFT", previewCard, "TOPLEFT", 10, -7)
        previewTitle:SetText("|cffb4e634Active Layout Summary|r")

        local previewDesc = previewCard:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        previewDesc:SetPoint("TOPLEFT", previewTitle, "BOTTOMLEFT", 0, -3)
        previewDesc:SetPoint("RIGHT", previewCard, "RIGHT", -8, 0)
        previewDesc:SetJustifyH("LEFT")

        local function refreshStyleCards()
            local styleVal = TacoTipConfig.tip_style or 2
            for _, c in ipairs(styleCards) do
                local active = (styleVal == c.value)
                c.card:SetFlatColors(active and DASH_THEME.cardActiveBg or DASH_THEME.cardBg,
                    active and DASH_THEME.borderGold or DASH_THEME.borderSubtle)
                c.radio:SetText(active and "|cffffd100[X]|r" or "|cff5c6370[ ]|r")
            end
            local modeNames = { [1] = "Wide", [2] = "Compact+Shift", [3] = "Compact", [4] = "Mini+Shift", [5] = "Mini" }
            local parts = { "|cffffd100" .. (modeNames[styleVal] or "Custom") .. "|r" }
            if (TacoTipConfig.show_gs_player) then parts[#parts + 1] = "GS" end
            if (TacoTipConfig.show_talents) then parts[#parts + 1] = "Talents" end
            if (TacoTipConfig.show_guild_name) then parts[#parts + 1] = "Guild" end
            previewDesc:SetText(table.concat(parts, " · "))
        end
        frame._refreshStyleCards = refreshStyleCards

        for i, preset in ipairs(presets) do
            local card = CreateFrame("Frame", nil, styleGrid)
            card:SetSize(238, 50)
            card:EnableMouse(true)
            paintFlatBox(card, DASH_THEME.cardBg, DASH_THEME.borderSubtle)

            local rad = card:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            rad:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -8)
            rad:SetText("|cff5c6370[ ]|r")

            local lbl = card:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            lbl:SetPoint("LEFT", rad, "RIGHT", 6, 0)
            lbl:SetText(preset.text)

            local sub = card:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
            sub:SetPoint("TOPLEFT", rad, "BOTTOMLEFT", 0, -4)
            sub:SetPoint("RIGHT", card, "RIGHT", -8, 0)
            sub:SetJustifyH("LEFT")
            sub:SetText(preset.sub)

            card:SetScript("OnEnter", function(self)
                if (TacoTipConfig.tip_style ~= preset.value) then
                    self:SetFlatColors(DASH_THEME.cardHoverBg, DASH_THEME.borderGold)
                end
            end)
            card:SetScript("OnLeave", function(self)
                local active = (TacoTipConfig.tip_style == preset.value)
                self:SetFlatColors(active and DASH_THEME.cardActiveBg or DASH_THEME.cardBg,
                    active and DASH_THEME.borderGold or DASH_THEME.borderSubtle)
            end)
            card:SetScript("OnMouseDown", function()
                TacoTipConfig.tip_style = preset.value
                onSettingChanged()
                refreshStyleCards()
            end)

            local col = (i - 1) % 3
            local row = math.floor((i - 1) / 3)
            card:SetPoint("TOPLEFT", styleGrid, "TOPLEFT", col * 247, -row * 56)
            styleCards[i] = { value = preset.value, card = card, radio = rad }
        end
        gy = registerRow(generalChild, styleGrid, "general", gy, 112, 8)

        local noticeShift = createNoticeBox(generalChild, "|cffffd100[TIP]|r",
            "Holding SHIFT dynamically expands Compact and Mini tooltips to full Wide detail.")
        gy = registerStaticRow(generalChild, noticeShift, "general", gy, 34, 8)

        gy = addSectionHeader(generalChild, "Combat Hiding", gy, "general")

        syncControls.hide_in_combat = createPillToggle(generalChild, "Hide Tooltips in Combat",
            "Hide unit tooltips while you are engaged in combat. Enable to unlock the combat modifier key below.",
            TacoTipConfig.hide_in_combat, function(v)
                TacoTipConfig.hide_in_combat = v
                if (syncControls.combat_modifier and syncControls.combat_modifier.SetDisabled) then
                    syncControls.combat_modifier:SetDisabled(not v, "Enable 'Hide Tooltips in Combat' above to use a modifier reveal key.")
                end
                onSettingChanged()
            end)
        gy = registerRow(generalChild, syncControls.hide_in_combat, "general", gy)

        syncControls.combat_modifier = createFlatChoiceRow(generalChild,
            "Still Show Hidden Tips when Holding Modifier Key",
            "Hold this key in combat to temporarily reveal unit tooltips.",
            {
                { value = "NONE", label = "None" },
                { value = "SHIFT", label = "Shift" },
                { value = "CTRL", label = "Ctrl" },
                { value = "ALT", label = "Alt" },
            },
            TacoTipConfig.combat_modifier or "NONE",
            function(val)
                TacoTipConfig.combat_modifier = val
                onSettingChanged()
            end, 52)
        gy = registerRow(generalChild, syncControls.combat_modifier, "general", gy, 48)

        gy = addSectionHeader(generalChild, "Core Behavior", gy, "general")

        syncControls.show_separators = createPillToggle(generalChild, "Section Separators",
            "Draw thin divider lines between logical sections of the tooltip.", TacoTipConfig.show_separators, function(v)
                TacoTipConfig.show_separators = v
                onSettingChanged()
            end)
        gy = registerRow(generalChild, syncControls.show_separators, "general", gy)

        syncControls.instant_fade = createPillToggle(generalChild, "Instant Fade",
            "Fade out unit tooltips immediately when cursor leaves a unit.", TacoTipConfig.instant_fade, function(v)
                TacoTipConfig.instant_fade = v
                if (updateInstantFadeState) then updateInstantFadeState(v) end
                onSettingChanged()
            end)
        gy = registerRow(generalChild, syncControls.instant_fade, "general", gy)

        syncControls.show_minimap = createPillToggle(generalChild, "Show Minimap Button",
            "Display the LibDBIcon TacoTip button on your minimap for one-click settings and diagnostics.",
            TacoTipConfig.show_minimap ~= false, function(v)
                TacoTipConfig.show_minimap = v
                if (TT and TT.SetMinimapIconShown) then
                    TT:SetMinimapIconShown(v)
                end
                onSettingChanged()
            end)
        gy = registerRow(generalChild, syncControls.show_minimap, "general", gy)

        syncControls.tooltip_scale = createDashboardSlider(generalChild, "Tooltip Scale",
            "Adjust the overall scale of tooltips (50% to 200%).", 0.5, 2.0, 0.05,
            TacoTipConfig.tooltip_scale or 1.0, function(v)
                TacoTipConfig.tooltip_scale = v
                if (TT and TT.ApplyTooltipScale) then TT:ApplyTooltipScale() end
                onSettingChanged()
            end, function(v) return math.floor(v * 100 + 0.5) .. "%" end)
        gy = registerRow(generalChild, syncControls.tooltip_scale, "general", gy, 48)

        syncControls.tooltip_delay = createDashboardSlider(generalChild, "Tooltip Delay",
            "Delay in milliseconds before showing unit tooltips.", 0, 1000, 50,
            math.floor((TacoTipConfig.tooltip_delay or 0) * 1000 + 0.5), function(v)
                TacoTipConfig.tooltip_delay = v / 1000
                onSettingChanged()
            end, function(v) return tostring(v) .. " ms" end)
        gy = registerRow(generalChild, syncControls.tooltip_delay, "general", gy, 48)

        gy = addSectionHeader(generalChild, "Language & Client Tooltips", gy, "general")

        syncControls.locale_override = createFlatPickerRow(generalChild, "Addon Language",
            "Use client default or pick another supported TacoTip locale (/reload required).",
            buildLocaleDropdownChoices,
            function() return getSavedLocaleOverride() or CLIENT_DEFAULT_LOCALE_VALUE end,
            function(val)
                if (val == CLIENT_DEFAULT_LOCALE_VALUE) then
                    TacoTipConfig.locale_override = nil
                else
                    TacoTipConfig.locale_override = val
                end
                print("|cff59f0dcTacoTip:|r " ..
                    (L["OPTIONS_LANGUAGE_RELOAD_HINT"] or "Language preference saved. Reload the UI to apply it."))
                onSettingChanged()
            end)
        gy = registerRow(generalChild, syncControls.locale_override, "general", gy, 46)

        syncControls.uber_tooltips = createPillToggle(generalChild, "Enhanced Spell & Item Tooltips",
            "Toggle Blizzard's UberTooltips CVar for detailed spell and ability descriptions.",
            (GetCVar and GetCVar("UberTooltips") == "1") or false, function(v)
                if (SetCVar) then SetCVar("UberTooltips", v and "1" or "0") end
                onSettingChanged()
            end)
        gy = registerRow(generalChild, syncControls.uber_tooltips, "general", gy)

        syncControls.chat_class_colors = createPillToggle(generalChild, "Chat Class Colors",
            "Color player names by class inside Blizzard chat windows (chatClassColorOverride).",
            (GetCVar and GetCVar("chatClassColorOverride") == "0") or false, function(v)
                if (SetCVar) then SetCVar("chatClassColorOverride", v and "0" or "1") end
                onSettingChanged()
            end)
        gy = registerRow(generalChild, syncControls.chat_class_colors, "general", gy)

        local allCard = createFlatActionCard(generalChild, 240, 28, "All Settings (Blizzard panel)", "gold", function()
            frame:Hide()
            openOptionsPanel()
        end, "All Settings", "Open every TacoTip option in Esc > Options > AddOns.")
        gy = registerStaticRow(generalChild, allCard, "general", gy - 4, 32, 8)
        tabDefaultHeights.general = math.abs(gy) + 20
        generalChild:SetHeight(tabDefaultHeights.general)
    end

    -- ========================================================================
    -- Tab 2: Unit Content
    -- ========================================================================
    do
        local _, unitsChild = createScrollCategory("units", "Unit Content", "Unit Content",
            "Customize player, NPC, and pet details displayed on tooltips.", 2)
        local uy = 0
        uy = addSectionHeader(unitsChild, "Player & Guild Information", uy, "units")

        syncControls.show_guild_name = createPillToggle(unitsChild, "Show Guild Name",
            "Display guild name on player tooltips.", TacoTipConfig.show_guild_name, function(v)
                TacoTipConfig.show_guild_name = v
                if (frame.RefreshDependencyStates) then frame:RefreshDependencyStates() end
                onSettingChanged()
            end)
        uy = registerRow(unitsChild, syncControls.show_guild_name, "units", uy)

        syncControls.show_guild_rank = createPillToggle(unitsChild, "Show Guild Rank",
            "Display guild rank title alongside the guild name.", TacoTipConfig.show_guild_rank, function(v)
                TacoTipConfig.show_guild_rank = v
                if (frame.RefreshDependencyStates) then frame:RefreshDependencyStates() end
                onSettingChanged()
            end)
        uy = registerRow(unitsChild, syncControls.show_guild_rank, "units", uy)

        syncControls.guild_rank_alt_style = createPillToggle(unitsChild, "Detailed Guild Rank Format",
            "Display rank format as '<Guild> (<Rank>)' instead of '<Rank> of <Guild>'.", TacoTipConfig.guild_rank_alt_style, function(v)
                TacoTipConfig.guild_rank_alt_style = v
                onSettingChanged()
            end)
        uy = registerRow(unitsChild, syncControls.guild_rank_alt_style, "units", uy)

        syncControls.show_titles = createPillToggle(unitsChild, "Show Player Titles",
            "Display earned player titles in the name line.", TacoTipConfig.show_titles, function(v)
                TacoTipConfig.show_titles = v
                onSettingChanged()
            end)
        uy = registerRow(unitsChild, syncControls.show_titles, "units", uy)

        syncControls.show_realm = createPillToggle(unitsChild, "Show Realm Name",
            "Display server realm name for players from other connected servers.", TacoTipConfig.show_realm, function(v)
                TacoTipConfig.show_realm = v
                onSettingChanged()
            end)
        uy = registerRow(unitsChild, syncControls.show_realm, "units", uy)

        uy = addSectionHeader(unitsChild, "Targeting & Alignment", uy, "units")

        syncControls.show_target = createPillToggle(unitsChild, "Show Target",
            "Display who the inspected player or creature is currently targeting.", TacoTipConfig.show_target, function(v)
                TacoTipConfig.show_target = v
                onSettingChanged()
            end)
        uy = registerRow(unitsChild, syncControls.show_target, "units", uy)

        syncControls.show_team = createPillToggle(unitsChild, "Show Faction Name & Crest",
            "Display Horde or Alliance faction name and crest icon.", TacoTipConfig.show_team, function(v)
                TacoTipConfig.show_team = v
                onSettingChanged()
            end)
        uy = registerRow(unitsChild, syncControls.show_team, "units", uy)

        syncControls.show_pvp_icon = createPillToggle(unitsChild, "Show PvP Badge",
            "Display PvP rank or faction badge when flagged for PvP.", TacoTipConfig.show_pvp_icon, function(v)
                TacoTipConfig.show_pvp_icon = v
                onSettingChanged()
            end)
        uy = registerRow(unitsChild, syncControls.show_pvp_icon, "units", uy)

        syncControls.show_honor_rank = createPillToggle(unitsChild, "Show Classic Honor Rank",
            "Display Classic PvP rank title (e.g. Private, Grand Marshal).", TacoTipConfig.show_honor_rank, function(v)
                TacoTipConfig.show_honor_rank = v
                onSettingChanged()
            end)
        uy = registerRow(unitsChild, syncControls.show_honor_rank, "units", uy)

        uy = addSectionHeader(unitsChild, "Class Colors", uy, "units")

        syncControls.color_class = createPillToggle(unitsChild, "Class Colors",
            "Color player names, class names, and power bars by class color.", TacoTipConfig.color_class, function(v)
                TacoTipConfig.color_class = v
                onSettingChanged()
            end)
        uy = registerRow(unitsChild, syncControls.color_class, "units", uy)

        local isClassicEra = CI and CI.IsClassic and CI:IsClassic()
        if (isClassicEra) then
            syncControls.shaman_blue = createPillToggle(unitsChild, "Shaman Blue",
                "Use Shaman blue instead of pink for Shaman class colors.", TacoTipConfig.shaman_blue, function(v)
                    TacoTipConfig.shaman_blue = v
                    onSettingChanged()
                end)
            uy = registerRow(unitsChild, syncControls.shaman_blue, "units", uy)
        end
        tabDefaultHeights.units = math.abs(uy) + 20
        unitsChild:SetHeight(tabDefaultHeights.units)
    end

    -- ========================================================================
    -- Tab 3: Appearance & Bars
    -- ========================================================================
    do
        local _, appChild = createScrollCategory("appearance", "Appearance & Bars", "Appearance & Bars",
            "Customize health and power bars, textures, borders, colors, and typography.", 3)
        local ay = 0
        ay = addSectionHeader(appChild, "Status Bars & Texture", ay, "appearance")

        syncControls.show_hp_bar = createPillToggle(appChild, "Show Health Bar",
            "Display unit health status bar under the tooltip.", TacoTipConfig.show_hp_bar, function(v)
                TacoTipConfig.show_hp_bar = v
                onSettingChanged()
            end)
        ay = registerRow(appChild, syncControls.show_hp_bar, "appearance", ay)

        syncControls.show_power_bar = createPillToggle(appChild, "Show Power Bar",
            "Display mana, rage, energy, or focus bar under the health bar.", TacoTipConfig.show_power_bar, function(v)
                TacoTipConfig.show_power_bar = v
                onSettingChanged()
            end)
        ay = registerRow(appChild, syncControls.show_power_bar, "appearance", ay)

        syncControls.tooltip_bar_texture = createFlatPickerRow(appChild, "Health & Power Bar Texture",
            "Choose the bar fill texture (includes SharedMedia packs when available).",
            function() return TT:GetTooltipStatusBarTextureChoices() end,
            function() return TT:GetResolvedTooltipStatusBarTexture() end,
            function(val)
                TacoTipConfig.tooltip_bar_texture = val
                onSettingChanged()
            end)
        ay = registerRow(appChild, syncControls.tooltip_bar_texture, "appearance", ay, 46)

        ay = addSectionHeader(appChild, "Borders, Backdrop & Colors", ay, "appearance")

        syncControls.tooltip_border_use_class = createPillToggle(appChild, "Class-Colored Border",
            "Color the tooltip border according to the unit's class or NPC reaction.", TacoTipConfig.tooltip_border_use_class, function(v)
                TacoTipConfig.tooltip_border_use_class = v
                onSettingChanged()
            end)
        ay = registerRow(appChild, syncControls.tooltip_border_use_class, "appearance", ay)

        syncControls.tooltip_border_item_quality = createPillToggle(appChild, "Item Quality Border Color",
            "Color item tooltip borders by rarity (Uncommon green, Rare blue, Epic purple, etc.).",
            TacoTipConfig.tooltip_border_item_quality ~= false, function(v)
                TacoTipConfig.tooltip_border_item_quality = v
                onSettingChanged()
            end)
        ay = registerRow(appChild, syncControls.tooltip_border_item_quality, "appearance", ay)

        syncControls.tooltip_background_use_class = createPillToggle(appChild, "Class-Colored Background",
            "Tint the tooltip background according to the unit's class or NPC reaction.", TacoTipConfig.tooltip_background_use_class, function(v)
                TacoTipConfig.tooltip_background_use_class = v
                onSettingChanged()
            end)
        ay = registerRow(appChild, syncControls.tooltip_background_use_class, "appearance", ay)

        syncControls.tooltip_border_texture = createFlatPickerRow(appChild, "Tooltip Border Texture",
            "Pick the border artwork used around unit and item tooltips.",
            function() return TT:GetTooltipBorderChoices() end,
            function() return TT:GetResolvedTooltipBorder() end,
            function(val)
                TacoTipConfig.tooltip_border_texture = val
                if (frame.RefreshDependencyStates) then frame:RefreshDependencyStates() end
                onSettingChanged()
            end)
        ay = registerRow(appChild, syncControls.tooltip_border_texture, "appearance", ay, 46)

        syncControls.tooltip_background_texture = createFlatPickerRow(appChild, "Tooltip Background Texture",
            "Pick the backdrop texture rendered behind tooltips.",
            function() return TT:GetTooltipBackgroundChoices() end,
            function() return TT:GetResolvedTooltipBackground() end,
            function(val)
                TacoTipConfig.tooltip_background_texture = val
                onSettingChanged()
            end)
        ay = registerRow(appChild, syncControls.tooltip_background_texture, "appearance", ay, 46)

        syncControls.tooltip_border_color = createFlatColorRow(appChild, "Base Border Color",
            "Default border tint when class or item quality border coloring is not overriding it.",
            function()
                return TacoTipConfig.tooltip_border_color_r or 1,
                    TacoTipConfig.tooltip_border_color_g or 1,
                    TacoTipConfig.tooltip_border_color_b or 1
            end,
            function(r, g, b)
                TacoTipConfig.tooltip_border_color_r = r
                TacoTipConfig.tooltip_border_color_g = g
                TacoTipConfig.tooltip_border_color_b = b
                onSettingChanged()
            end, { 1, 1, 1 })
        ay = registerRow(appChild, syncControls.tooltip_border_color, "appearance", ay, 46)

        syncControls.tooltip_background_color = createFlatColorRow(appChild, "Base Background Color",
            "Default backdrop color when class-colored background tinting is disabled.",
            function()
                return TacoTipConfig.tooltip_background_color_r or 0,
                    TacoTipConfig.tooltip_background_color_g or 0,
                    TacoTipConfig.tooltip_background_color_b or 0
            end,
            function(r, g, b)
                TacoTipConfig.tooltip_background_color_r = r
                TacoTipConfig.tooltip_background_color_g = g
                TacoTipConfig.tooltip_background_color_b = b
                onSettingChanged()
            end, { 0, 0, 0 })
        ay = registerRow(appChild, syncControls.tooltip_background_color, "appearance", ay, 46)

        syncControls.tooltip_border_edge_size = createDashboardSlider(appChild, "Border Thickness",
            "Pixel thickness of the tooltip border edge (4 to 48 px; default 16 px).", 4, 48, 1,
            TacoTipConfig.tooltip_border_edge_size or DEFAULTS.tooltip_border_edge_size or 16, function(v)
                TacoTipConfig.tooltip_border_edge_size = v
                onSettingChanged()
            end, function(v) return tostring(v) .. " px" end)
        ay = registerRow(appChild, syncControls.tooltip_border_edge_size, "appearance", ay, 48)

        syncControls.tooltip_border_alpha = createDashboardSlider(appChild, "Border Opacity",
            "Adjust how strong the tooltip border tint appears.", 0, 100, 1,
            math.floor((TacoTipConfig.tooltip_border_alpha or 0.9) * 100 + 0.5), function(v)
                TacoTipConfig.tooltip_border_alpha = v / 100
                onSettingChanged()
            end, function(v) return tostring(v) .. "%" end)
        ay = registerRow(appChild, syncControls.tooltip_border_alpha, "appearance", ay, 48)

        syncControls.tooltip_background_alpha = createDashboardSlider(appChild, "Background Opacity",
            "Adjust backdrop opacity behind tooltips.", 0, 100, 1,
            math.floor((TacoTipConfig.tooltip_background_alpha or 0.85) * 100 + 0.5), function(v)
                TacoTipConfig.tooltip_background_alpha = v / 100
                onSettingChanged()
            end, function(v) return tostring(v) .. "%" end)
        ay = registerRow(appChild, syncControls.tooltip_background_alpha, "appearance", ay, 48)

        ay = addSectionHeader(appChild, "Typography & Dimensions", ay, "appearance")

        syncControls.tooltip_font = createFlatPickerRow(appChild, "Tooltip Font",
            "Choose the primary tooltip font face (automatic script fallback stays active).",
            function() return TT:GetTooltipFontChoices() end,
            function() return TT:GetResolvedTooltipFont() end,
            function(val)
                TacoTipConfig.tooltip_font = val
                onSettingChanged()
            end)
        ay = registerRow(appChild, syncControls.tooltip_font, "appearance", ay, 46)

        syncControls.tooltip_font_size = createDashboardSlider(appChild, "Tooltip Text Size",
            "Change text size across all tooltip lines (8 to 20 pt).", 8, 20, 1,
            TacoTipConfig.tooltip_font_size or 12, function(v)
                TacoTipConfig.tooltip_font_size = v
                onSettingChanged()
            end, function(v) return tostring(v) .. " pt" end)
        ay = registerRow(appChild, syncControls.tooltip_font_size, "appearance", ay, 48)

        syncControls.tooltip_max_width = createDashboardSlider(appChild, "Tooltip Maximum Width",
            "Cap tooltip width to prevent excessively wide text (0 = uncapped).", 0, 500, 10,
            TacoTipConfig.tooltip_max_width or 0, function(v)
                TacoTipConfig.tooltip_max_width = v
                onSettingChanged()
            end, function(v) return (v == 0 and "Uncapped") or (tostring(v) .. " px") end)
        ay = registerRow(appChild, syncControls.tooltip_max_width, "appearance", ay, 48)
        tabDefaultHeights.appearance = math.abs(ay) + 20
        appChild:SetHeight(tabDefaultHeights.appearance)
    end

    -- ========================================================================
    -- Tab 4: Portrait & Icons
    -- ========================================================================
    do
        local _, portChild = createScrollCategory("portrait", "Portrait & Icons", "Portrait & Icons",
            "Configure 3D character portraits, class badges, and specialization icons.", 4)
        local py = 0
        py = addSectionHeader(portChild, "Unit Portrait", py, "portrait")

        syncControls.tooltip_portrait = createPillToggle(portChild, "Show Unit Portrait",
            "Display a portrait frame attached to the tooltip for players and NPCs.", TacoTipConfig.tooltip_portrait, function(v)
                TacoTipConfig.tooltip_portrait = v
                if (frame.RefreshDependencyStates) then frame:RefreshDependencyStates() end
                onSettingChanged()
            end)
        py = registerRow(portChild, syncControls.tooltip_portrait, "portrait", py)

        syncControls.tooltip_portrait_3d = createPillToggle(portChild, "3D Animated Model",
            "Display an animated 3D character model instead of a flat 2D icon.", TacoTipConfig.tooltip_portrait_3d, function(v)
                TacoTipConfig.tooltip_portrait_3d = v
                if (frame.RefreshDependencyStates) then frame:RefreshDependencyStates() end
                onSettingChanged()
            end)
        py = registerRow(portChild, syncControls.tooltip_portrait_3d, "portrait", py)

        syncControls.tooltip_portrait_invert_side = createPillToggle(portChild, "Flip Portrait Side",
            "Position the portrait frame on the left side instead of the right.", TacoTipConfig.tooltip_portrait_invert_side, function(v)
                TacoTipConfig.tooltip_portrait_invert_side = v
                onSettingChanged()
            end)
        py = registerRow(portChild, syncControls.tooltip_portrait_invert_side, "portrait", py)

        py = addSectionHeader(portChild, "Portrait Sizing & Camera", py, "portrait")

        syncControls.tooltip_portrait_scale = createDashboardSlider(portChild, "Portrait Scale",
            "Scale the portrait frame size relative to the tooltip (50% to 200%).", 0.5, 2.0, 0.05,
            TacoTipConfig.tooltip_portrait_scale or 1.0, function(v)
                TacoTipConfig.tooltip_portrait_scale = v
                onSettingChanged()
            end, function(v) return math.floor(v * 100 + 0.5) .. "%" end)
        py = registerRow(portChild, syncControls.tooltip_portrait_scale, "portrait", py, 48)

        syncControls.tooltip_portrait_zoom = createDashboardSlider(portChild, "3D Camera Zoom",
            "Adjust the camera zoom level for 3D character models (30% to 100%).", 0.3, 1.0, 0.05,
            TacoTipConfig.tooltip_portrait_zoom or 0.7, function(v)
                TacoTipConfig.tooltip_portrait_zoom = v
                onSettingChanged()
            end, function(v) return math.floor(v * 100 + 0.5) .. "%" end)
        py = registerRow(portChild, syncControls.tooltip_portrait_zoom, "portrait", py, 48)

        py = addSectionHeader(portChild, "Badges & Icons", py, "portrait")

        syncControls.show_class_icon = createPillToggle(portChild, "Show Class Icon",
            "Display class badge next to player name.", TacoTipConfig.show_class_icon, function(v)
                TacoTipConfig.show_class_icon = v
                if (frame.RefreshDependencyStates) then frame:RefreshDependencyStates() end
                onSettingChanged()
            end)
        py = registerRow(portChild, syncControls.show_class_icon, "portrait", py)

        syncControls.show_role_icon = createPillToggle(portChild, "Show Dungeon Role Icon",
            "Display Tank, Healer, or Damage dungeon role badge.", TacoTipConfig.show_role_icon, function(v)
                TacoTipConfig.show_role_icon = v
                onSettingChanged()
            end)
        py = registerRow(portChild, syncControls.show_role_icon, "portrait", py)

        syncControls.class_icon_size = createDashboardSlider(portChild, "Class Icon Size",
            "Pixel size of class badges in tooltip headers (8 to 32 px).", 8, 32, 1,
            TacoTipConfig.class_icon_size or 20, function(v)
                TacoTipConfig.class_icon_size = v
                onSettingChanged()
            end, function(v) return tostring(v) .. " px" end)
        py = registerRow(portChild, syncControls.class_icon_size, "portrait", py, 48)
        tabDefaultHeights.portrait = math.abs(py) + 20
        portChild:SetHeight(tabDefaultHeights.portrait)
    end

    -- ========================================================================
    -- Tab 5: Positioning & Anchors
    -- ========================================================================
    do
        local _, posChild = createScrollCategory("positioning", "Positioning", "Positioning & Anchors",
            "Control where tooltips appear and configure custom anchors.", 5)
        local posy = 0

        local noticePos = createNoticeBox(posChild, "|cffffb81c[TIP]|r",
            "Click 'Launch Tooltip Mover' below or 'Move Tooltip' in the footer to drag and lock the tooltip anywhere.")
        posy = registerStaticRow(posChild, noticePos, "positioning", posy, 34, 8)

        local posStatusCard = CreateFrame("Frame", nil, posChild)
        posStatusCard:SetSize(DASH_CARD_W, 44)
        paintFlatBox(posStatusCard, DASH_THEME.headerBg, DASH_THEME.borderSubtle)

        local posCoordText = posStatusCard:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        posCoordText:SetPoint("LEFT", posStatusCard, "LEFT", 12, 0)
        posCoordText:SetPoint("RIGHT", posStatusCard, "RIGHT", -290, 0)
        posCoordText:SetJustifyH("LEFT")

        local launchMover = createFlatActionCard(posStatusCard, 155, 26, "Launch Tooltip Mover", "emerald", function()
            showTooltipMover()
        end, "Move Tooltip", "Show the live drag handle to position your tooltip on screen.")
        launchMover:SetPoint("RIGHT", posStatusCard, "RIGHT", -12, 0)

        local clearPosBtn = createFlatActionCard(posStatusCard, 110, 26, "Reset Position", "plain", function()
            TacoTipConfig.custom_pos = nil
            if (TacoTipDragButton) then TacoTipDragButton:_Disable(true) end
            if (TT.SyncTooltipMover) then TT:SyncTooltipMover() end
            onSettingChanged()
            if (frame.RefreshAll) then frame:RefreshAll() end
        end, "Reset Saved Position", "Clear saved custom tooltip coordinates and return to Blizzard default placement.")
        clearPosBtn:SetPoint("RIGHT", launchMover, "LEFT", -8, 0)

        frame._refreshPositionSummary = function()
            if (TacoTipConfig.anchor_mouse) then
                posCoordText:SetText("Active Mode: |cffffd100Mouse Cursor|r" ..
                    (TacoTipConfig.anchor_mouse_world and " (WorldFrame only)" or ""))
            elseif (type(TacoTipConfig.custom_pos) == "table") then
                local pt = tostring(TacoTipConfig.custom_pos[1] or TacoTipConfig.custom_anchor or "TOPLEFT")
                local ox = math.floor((tonumber(TacoTipConfig.custom_pos[3]) or 0) + 0.5)
                local oy = math.floor((tonumber(TacoTipConfig.custom_pos[4]) or 0) + 0.5)
                posCoordText:SetText(string.format("Active Mode: |cffb4e634Custom|r · Anchor %s (%d, %d)", pt, ox, oy))
            else
                posCoordText:SetText("Active Mode: |cff9ba3aeBlizzard Default Placement|r")
            end
        end
        frame._refreshPositionSummary()

        posy = registerStaticRow(posChild, posStatusCard, "positioning", posy, 44, 10)

        posy = addSectionHeader(posChild, "Anchor Modes", posy, "positioning")

        syncControls.custom_position = createPillToggle(posChild, "Custom Tooltip Position",
            "Unlock and place the tooltip at your saved custom coordinates (clears mouse anchor).",
            TacoTipConfig.custom_pos ~= nil, function(v)
                if (not v) then
                    TacoTipConfig.custom_pos = nil
                    if (TacoTipDragButton) then TacoTipDragButton:_Disable(true) end
                else
                    TacoTipConfig.anchor_mouse = false
                    if (not TacoTipConfig.custom_pos) then
                        TacoTipConfig.custom_pos = { "BOTTOMRIGHT", "BOTTOMRIGHT", -CONTAINER_OFFSET_X - 13, CONTAINER_OFFSET_Y }
                    end
                    if (TacoTip_CustomPosEnable) then TacoTip_CustomPosEnable(false) end
                end
                if (TT.SyncTooltipMover) then TT:SyncTooltipMover() end
                onSettingChanged()
                if (frame.RefreshAll) then frame:RefreshAll() end
            end)
        posy = registerRow(posChild, syncControls.custom_position, "positioning", posy)

        syncControls.custom_anchor = createFlatChoiceRow(posChild, "Custom Tooltip Anchor Corner",
            "Corner or center point used when anchoring a custom tooltip position.",
            {
                { value = "TOPLEFT", label = "Top-L" },
                { value = "TOPRIGHT", label = "Top-R" },
                { value = "BOTTOMLEFT", label = "Bot-L" },
                { value = "BOTTOMRIGHT", label = "Bot-R" },
                { value = "CENTER", label = "Center" },
            },
            TacoTipConfig.custom_anchor or "TOPLEFT",
            function(val)
                TacoTipConfig.custom_anchor = val
                if (TT.SyncTooltipMover) then TT:SyncTooltipMover() end
                if (TacoTipDragButton and TacoTipDragButton.IsShown and TacoTipDragButton:IsShown()) then
                    TacoTipDragButton:ShowExample()
                end
                onSettingChanged()
                if (frame._refreshPositionSummary) then frame._refreshPositionSummary() end
            end, 52)
        posy = registerRow(posChild, syncControls.custom_anchor, "positioning", posy, 48)

        syncControls.anchor_mouse = createPillToggle(posChild, "Anchor to Mouse Cursor",
            "Attach unit tooltips directly to your mouse pointer (clears custom position).",
            TacoTipConfig.anchor_mouse, function(v)
                TacoTipConfig.anchor_mouse = v
                if (v) then
                    TacoTipConfig.custom_pos = nil
                    if (TacoTipDragButton) then TacoTipDragButton:_Disable(true) end
                end
                onSettingChanged()
                if (frame.RefreshAll) then frame:RefreshAll() end
            end)
        posy = registerRow(posChild, syncControls.anchor_mouse, "positioning", posy)

        syncControls.anchor_mouse_world = createPillToggle(posChild, "Mouse Anchor World Units Only",
            "Anchor mouse only for units in the 3D world (keeps default anchor for frames).", TacoTipConfig.anchor_mouse_world, function(v)
                TacoTipConfig.anchor_mouse_world = v
                onSettingChanged()
                if (frame._refreshPositionSummary) then frame._refreshPositionSummary() end
            end)
        posy = registerRow(posChild, syncControls.anchor_mouse_world, "positioning", posy)

        syncControls.anchor_mouse_spells = createPillToggle(posChild, "Anchor Spells to Mouse",
            "Anchor action bar and spell tooltips to mouse cursor.", TacoTipConfig.anchor_mouse_spells, function(v)
                TacoTipConfig.anchor_mouse_spells = v
                onSettingChanged()
            end)
        posy = registerRow(posChild, syncControls.anchor_mouse_spells, "positioning", posy)
        tabDefaultHeights.positioning = math.abs(posy) + 20
        posChild:SetHeight(tabDefaultHeights.positioning)
    end

    -- ========================================================================
    -- Tab 6: Character & Inspect
    -- ========================================================================
    do
        local _, charChild = createScrollCategory("character", "Character & Inspect", "Character & Inspect",
            "Configure GearScore, Item Level, Talents, Pawn, and PaperDoll/Inspect overlays.", 6)
        local cy = 0

        local noticeChar = createNoticeBox(charChild, "|cffb4e634[READY]|r",
            "Real-time GearScore and talent inspection active with automatic throttling and caching.", true)
        cy = registerStaticRow(charChild, noticeChar, "character", cy, 34, 8)

        cy = addSectionHeader(charChild, "Unit Tooltip Gear & Talents", cy, "character")

        syncControls.show_gs_player = createPillToggle(charChild, "Show Player GearScore",
            "Display GearScore on player tooltips (Wide/Mini layouts include average iLvl).", TacoTipConfig.show_gs_player, function(v)
                TacoTipConfig.show_gs_player = v
                onSettingChanged()
            end)
        cy = registerRow(charChild, syncControls.show_gs_player, "character", cy)

        syncControls.show_ilvl_inline = createPillToggle(charChild, "Inline iLvl with GearScore",
            "Display player average iLvl next to the name line instead of on a separate line.", TacoTipConfig.show_ilvl_inline, function(v)
                TacoTipConfig.show_ilvl_inline = v
                onSettingChanged()
            end)
        cy = registerRow(charChild, syncControls.show_ilvl_inline, "character", cy)

        syncControls.show_talents = createPillToggle(charChild, "Show Talents & Specialization",
            "Display talent point distribution and active specialization.", TacoTipConfig.show_talents, function(v)
                TacoTipConfig.show_talents = v
                onSettingChanged()
            end)
        cy = registerRow(charChild, syncControls.show_talents, "character", cy)

        syncControls.show_pawn_player = createPillToggle(charChild, "Show Pawn Stat Weights",
            "Display Pawn scale scores on player tooltips (requires Pawn addon).", TacoTipConfig.show_pawn_player, function(v)
                TacoTipConfig.show_pawn_player = v
                onSettingChanged()
            end)
        cy = registerRow(charChild, syncControls.show_pawn_player, "character", cy)

        syncControls.show_achievement_points = createPillToggle(charChild, "Show Achievement Points",
            "Display total player achievement points (Retail clients only).", TacoTipConfig.show_achievement_points, function(v)
                TacoTipConfig.show_achievement_points = v
                onSettingChanged()
            end)
        cy = registerRow(charChild, syncControls.show_achievement_points, "character", cy)

        cy = addSectionHeader(charChild, "Item Tooltip Scores", cy, "character")

        syncControls.show_item_level = createPillToggle(charChild, "Show Item Level on Gear Tooltips",
            "Display individual item level (iLvl) on equipment item tooltips.", TacoTipConfig.show_item_level, function(v)
                TacoTipConfig.show_item_level = v
                onSettingChanged()
            end)
        cy = registerRow(charChild, syncControls.show_item_level, "character", cy)

        syncControls.show_gs_items = createPillToggle(charChild, "Show Item GearScore",
            "Display calculated GearScore on item tooltips.", TacoTipConfig.show_gs_items, function(v)
                TacoTipConfig.show_gs_items = v
                if (frame.RefreshDependencyStates) then frame:RefreshDependencyStates() end
                onSettingChanged()
            end)
        cy = registerRow(charChild, syncControls.show_gs_items, "character", cy)

        syncControls.show_gs_items_hs = createPillToggle(charChild, "HunterScore on Ranged Weapons",
            "Always display HunterScore formula weighting on ranged weapon tooltips.", TacoTipConfig.show_gs_items_hs, function(v)
                TacoTipConfig.show_gs_items_hs = v
                onSettingChanged()
            end)
        cy = registerRow(charChild, syncControls.show_gs_items_hs, "character", cy)

        cy = addSectionHeader(charChild, "PaperDoll & Inspect Frame Overlays", cy, "character")

        syncControls.show_gs_character = createPillToggle(charChild, "Show PaperDoll GearScore Overlays",
            "Display GearScore overlay text directly on Character and Inspect windows.", TacoTipConfig.show_gs_character, function(v)
                TacoTipConfig.show_gs_character = v
                if (frame.RefreshDependencyStates) then frame:RefreshDependencyStates() end
                onSettingChanged()
            end)
        cy = registerRow(charChild, syncControls.show_gs_character, "character", cy)

        syncControls.show_avg_ilvl = createPillToggle(charChild, "Show PaperDoll Average iLvl Overlays",
            "Display average item level overlay on Character and Inspect windows.", TacoTipConfig.show_avg_ilvl, function(v)
                TacoTipConfig.show_avg_ilvl = v
                if (frame.RefreshDependencyStates) then frame:RefreshDependencyStates() end
                onSettingChanged()
            end)
        cy = registerRow(charChild, syncControls.show_avg_ilvl, "character", cy)

        syncControls.unlock_info_position = createPillToggle(charChild, "Enable Manual Overlay Movers",
            "Show drag handles on Character/Inspect frame overlays to position them manually.", TacoTipConfig.unlock_info_position, function(v)
                TacoTipConfig.unlock_info_position = v
                onSettingChanged()
            end)
        cy = registerRow(charChild, syncControls.unlock_info_position, "character", cy)

        local function createOffsetNudgeRow(titleText, keyX, keyY)
            local card = CreateFrame("Frame", nil, charChild)
            card:SetSize(DASH_CARD_W, 44)
            paintFlatBox(card, DASH_THEME.cardBg, DASH_THEME.borderSubtle)

            local t = card:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            t:SetPoint("LEFT", card, "LEFT", 12, 0)
            t:SetText(titleText)

            local valTxt = card:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            valTxt:SetPoint("LEFT", card, "LEFT", 230, 0)
            valTxt:SetWidth(120)
            valTxt:SetJustifyH("LEFT")

            local isDisabled = false
            local function refreshVal()
                local x = tonumber(TacoTipConfig[keyX]) or 0
                local y = tonumber(TacoTipConfig[keyY]) or 0
                valTxt:SetText(string.format("X: |cffffd100%d|r  Y: |cffffd100%d|r", x, y))
                card:SetAlpha(isDisabled and 0.45 or 1.0)
            end

            local function nudge(k, delta)
                if (isDisabled) then return end
                local nextVal = (delta == nil) and 0 or ((tonumber(TacoTipConfig[k]) or 0) + delta)
                setOffsetValue(k, nextVal, false)
                refreshVal()
            end

            local resetO = createFlatActionCard(card, 46, 22, "Zero", "plain", function()
                if (isDisabled) then return end
                setOffsetValue(keyX, 0, true)
                setOffsetValue(keyY, 0, false)
                refreshVal()
            end)
            resetO:SetPoint("RIGHT", card, "RIGHT", -10, 0)

            local yPlus = createFlatActionCard(card, 32, 22, "Y+", "plain", function() nudge(keyY, 5) end)
            yPlus:SetPoint("RIGHT", resetO, "LEFT", -6, 0)
            local yMinus = createFlatActionCard(card, 32, 22, "Y-", "plain", function() nudge(keyY, -5) end)
            yMinus:SetPoint("RIGHT", yPlus, "LEFT", -4, 0)

            local xPlus = createFlatActionCard(card, 32, 22, "X+", "plain", function() nudge(keyX, 5) end)
            xPlus:SetPoint("RIGHT", yMinus, "LEFT", -8, 0)
            local xMinus = createFlatActionCard(card, 32, 22, "X-", "plain", function() nudge(keyX, -5) end)
            xMinus:SetPoint("RIGHT", xPlus, "LEFT", -4, 0)

            card.RefreshOffsets = refreshVal
            card.SetDisabled = function(_, dis)
                isDisabled = dis and true or false
                refreshVal()
            end
            refreshVal()
            card.searchText = strlower(titleText .. " offset x y position overlay")
            return card
        end

        syncControls.char_gs_offsets = createOffsetNudgeRow("Character GearScore Offset", "character_gs_offset_x", "character_gs_offset_y")
        cy = registerRow(charChild, syncControls.char_gs_offsets, "character", cy, 44)
        syncControls.char_ilvl_offsets = createOffsetNudgeRow("Character iLvl Offset", "character_ilvl_offset_x", "character_ilvl_offset_y")
        cy = registerRow(charChild, syncControls.char_ilvl_offsets, "character", cy, 44)
        syncControls.inspect_gs_offsets = createOffsetNudgeRow("Inspect GearScore Offset", "inspect_gs_offset_x", "inspect_gs_offset_y")
        cy = registerRow(charChild, syncControls.inspect_gs_offsets, "character", cy, 44)
        syncControls.inspect_ilvl_offsets = createOffsetNudgeRow("Inspect iLvl Offset", "inspect_ilvl_offset_x", "inspect_ilvl_offset_y")
        cy = registerRow(charChild, syncControls.inspect_ilvl_offsets, "character", cy, 44)

        tabDefaultHeights.character = math.abs(cy) + 20
        charChild:SetHeight(tabDefaultHeights.character)
    end

    -- ========================================================================
    -- Tab 7: Progression & Leveling
    -- ========================================================================
    local _, progChild = createScrollCategory("progression", "Progression", "Progression & Leveling",
        "Track your character's gear rank, milestone achievements, and equipment upgrade chronicle.", 7)
    local progy = 0

    -- Hero Progression Card
    local heroCard = CreateFrame("Frame", nil, progChild)
    heroCard:SetSize(DASH_CARD_W, 102)
    paintFlatBox(heroCard, DASH_THEME.cardBg, DASH_THEME.borderGold)
    heroCard.searchText = "progression level rank gearscore xp trophies chronicle mini game"

    local heroPortraitFrame = CreateFrame("Frame", nil, heroCard)
    heroPortraitFrame:SetSize(50, 50)
    heroPortraitFrame:SetPoint("TOPLEFT", heroCard, "TOPLEFT", 12, -10)
    paintFlatBox(heroPortraitFrame, DASH_THEME.headerBg, DASH_THEME.borderGold)

    local heroPortrait = heroPortraitFrame:CreateTexture(nil, "ARTWORK")
    heroPortrait:SetPoint("TOPLEFT", heroPortraitFrame, "TOPLEFT", 2, -2)
    heroPortrait:SetPoint("BOTTOMRIGHT", heroPortraitFrame, "BOTTOMRIGHT", -2, 2)
    if (heroPortrait.SetTexCoord) then
        heroPortrait:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    end
    if (_G.SetPortraitTexture) then
        pcall(_G.SetPortraitTexture, heroPortrait, "player")
    end
    if (not heroPortrait:GetTexture()) then
        heroPortrait:SetTexture(LOGO_TEXTURE_PATH)
    end

    local heroLevelText = heroCard:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    heroLevelText:SetPoint("TOPLEFT", heroPortraitFrame, "TOPRIGHT", 12, -1)
    heroLevelText:SetText("|cffffd100[LEVEL 1]|r Novice")

    local heroGSText = heroCard:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
    heroGSText:SetPoint("TOPRIGHT", heroCard, "TOPRIGHT", -14, -11)
    heroGSText:SetText("GearScore: |cffffffff0|r")

    local heroStatsText = heroCard:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    heroStatsText:SetPoint("TOPLEFT", heroLevelText, "BOTTOMLEFT", 0, -5)
    heroStatsText:SetText("Peak: |cffffd1000|r  •  Average iLvl: |cffffffff0|r  •  Upgrades: |cff59f0dc0|r  •  Trophies: |cffb4e6340/10|r")

    local heroNextText = heroCard:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    heroNextText:SetPoint("TOPRIGHT", heroGSText, "BOTTOMRIGHT", 0, -4)
    heroNextText:SetText("")

    local xpBarBg = CreateFrame("Frame", nil, heroCard)
    xpBarBg:SetPoint("BOTTOMLEFT", heroCard, "BOTTOMLEFT", 12, 10)
    xpBarBg:SetSize(708, 20)
    paintFlatBox(xpBarBg, { 0.06, 0.07, 0.09, 0.96 }, DASH_THEME.borderSubtle)

    local xpBarFill = xpBarBg:CreateTexture(nil, "ARTWORK")
    xpBarFill:SetPoint("TOPLEFT", xpBarBg, "TOPLEFT", 1, -1)
    xpBarFill:SetPoint("BOTTOMLEFT", xpBarBg, "BOTTOMLEFT", 1, 1)
    xpBarFill:SetWidth(1)
    xpBarFill:SetTexture(WHITE8X8)
    xpBarFill:SetVertexColor(0.18, 0.72, 0.40, 0.92)
    xpBarFill:Hide()

    local xpBarCursor = xpBarBg:CreateTexture(nil, "OVERLAY")
    xpBarCursor:SetSize(2, 18)
    xpBarCursor:SetPoint("RIGHT", xpBarFill, "RIGHT", 0, 0)
    xpBarCursor:SetTexture(WHITE8X8)
    xpBarCursor:SetVertexColor(1.0, 0.92, 0.45, 0.95)
    xpBarCursor:Hide()

    local xpBarText = xpBarBg:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    xpBarText:SetPoint("CENTER", xpBarBg, "CENTER", 0, 0)
    xpBarText:SetText("0 / 25 GS to Next Level (0%)")

    progy = registerRow(progChild, heroCard, "progression", progy, 102)

    -- Compact 3-Column Progression Summary Strip
    local milestoneCard = CreateFrame("Frame", nil, progChild)
    milestoneCard:SetSize(DASH_CARD_W, 44)
    paintFlatBox(milestoneCard, DASH_THEME.headerBg, DASH_THEME.borderSubtle)
    milestoneCard.searchText = "milestone stage tier next rank best upgrade equipped slots"

    local mSep1 = milestoneCard:CreateTexture(nil, "ARTWORK")
    mSep1:SetSize(1, 28)
    mSep1:SetPoint("LEFT", milestoneCard, "LEFT", 244, 0)
    mSep1:SetTexture(WHITE8X8)
    mSep1:SetVertexColor(0.24, 0.25, 0.28, 0.9)

    local mSep2 = milestoneCard:CreateTexture(nil, "ARTWORK")
    mSep2:SetSize(1, 28)
    mSep2:SetPoint("LEFT", milestoneCard, "LEFT", 488, 0)
    mSep2:SetTexture(WHITE8X8)
    mSep2:SetVertexColor(0.24, 0.25, 0.28, 0.9)

    local mCol1Label = milestoneCard:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    mCol1Label:SetPoint("TOPLEFT", milestoneCard, "TOPLEFT", 12, -7)
    mCol1Label:SetText("NEXT GEAR RANK")

    local mCol1Val = milestoneCard:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    mCol1Val:SetPoint("BOTTOMLEFT", milestoneCard, "BOTTOMLEFT", 12, 7)
    mCol1Val:SetWidth(220)
    mCol1Val:SetJustifyH("LEFT")
    mCol1Val:SetText("Lv.2 (+25 GS)")

    local mCol2Label = milestoneCard:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    mCol2Label:SetPoint("TOPLEFT", milestoneCard, "TOPLEFT", 256, -7)
    mCol2Label:SetText("PROGRESSION STAGE")

    local mCol2Val = milestoneCard:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    mCol2Val:SetPoint("BOTTOMLEFT", milestoneCard, "BOTTOMLEFT", 256, 7)
    mCol2Val:SetWidth(220)
    mCol2Val:SetJustifyH("LEFT")
    mCol2Val:SetText("Leveling")

    local mCol3Label = milestoneCard:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    mCol3Label:SetPoint("TOPLEFT", milestoneCard, "TOPLEFT", 500, -7)
    mCol3Label:SetText("BEST RECORDED GAIN")

    local mCol3Val = milestoneCard:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    mCol3Val:SetPoint("BOTTOMLEFT", milestoneCard, "BOTTOMLEFT", 500, 7)
    mCol3Val:SetWidth(220)
    mCol3Val:SetJustifyH("LEFT")
    mCol3Val:SetText("No upgrades logged yet")

    progy = registerRow(progChild, milestoneCard, "progression", progy, 44)

    -- Milestone Trophies Section
    progy = addSectionHeader(progChild, "Milestone Trophies & Achievements", progy, "progression")

    local trophyCard = CreateFrame("Frame", nil, progChild)
    trophyCard:SetSize(DASH_CARD_W, 126)
    paintFlatBox(trophyCard, DASH_THEME.cardBg, DASH_THEME.borderSubtle)
    trophyCard.searchText = "trophies achievements milestones rewards badges"

    local trophyButtons = {}
    local trophyDefs = (TT and TT.GetTrophyDefinitions and TT:GetTrophyDefinitions()) or {}

    local function getTrophyProgressHint(defId, rec, lvl)
        local curLvl = (lvl and lvl.level) or 1
        local histCount = (rec and rec.history and #rec.history) or 0
        if (defId == "level_10") then return string.format("Progress: Gear Level %d / 10", curLvl) end
        if (defId == "level_20") then return string.format("Progress: Gear Level %d / 20", curLvl) end
        if (defId == "level_30") then return string.format("Progress: Gear Level %d / 30", curLvl) end
        if (defId == "level_40") then return string.format("Progress: Gear Level %d / 40", curLvl) end
        if (defId == "level_50") then return string.format("Progress: Gear Level %d / 50", curLvl) end
        if (defId == "upgrade_hunter") then return string.format("Progress: %d / 25 upgrades recorded", histCount) end
        if (defId == "century_club") then return string.format("Progress: %d / 100 upgrades recorded", histCount) end
        return nil
    end

    for i, def in ipairs(trophyDefs) do
        local col = ((i - 1) % 5)
        local row = math.floor((i - 1) / 5)
        local x = 12 + col * (136 + 7)
        local y = -8 - row * (52 + 6)

        local tBtn = CreateFrame("Frame", nil, trophyCard)
        tBtn:SetSize(136, 52)
        tBtn:SetPoint("TOPLEFT", trophyCard, "TOPLEFT", x, y)
        paintFlatBox(tBtn, DASH_THEME.headerBg, DASH_THEME.borderSubtle)
        tBtn:EnableMouse(true)
        tBtn.def = def

        local tIcon = tBtn:CreateTexture(nil, "ARTWORK")
        tIcon:SetSize(24, 24)
        tIcon:SetPoint("TOPLEFT", tBtn, "TOPLEFT", 6, -6)
        tIcon:SetTexture(def.icon or "Interface\\Icons\\achievement_general")
        if (not tIcon:GetTexture()) then
            tIcon:SetTexture("Interface\\Icons\\achievement_general")
        end
        if (tIcon.SetTexCoord) then tIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
        if (tIcon.SetDesaturated) then tIcon:SetDesaturated(true) end
        if (tIcon.SetAlpha) then tIcon:SetAlpha(0.35) end
        tBtn.icon = tIcon

        local tName = tBtn:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        tName:SetPoint("TOPLEFT", tIcon, "TOPRIGHT", 6, 1)
        tName:SetPoint("RIGHT", tBtn, "RIGHT", -4, 0)
        tName:SetJustifyH("LEFT")
        tName:SetText(def.name)
        tBtn.name = tName

        local tStatus = tBtn:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        tStatus:SetPoint("TOPLEFT", tName, "BOTTOMLEFT", 0, -2)
        tStatus:SetPoint("RIGHT", tBtn, "RIGHT", -4, 0)
        tStatus:SetJustifyH("LEFT")
        tStatus:SetText("Locked")
        tBtn.status = tStatus

        tBtn:SetScript("OnEnter", function(self)
            self:SetFlatColors(DASH_THEME.cardActiveBg, DASH_THEME.borderGold)
            if (self.def) then
                local rec = TT and TT.GetPlayerProgression and TT:GetPlayerProgression()
                local tr = rec and rec.trophies and rec.trophies[self.def.id]
                local desc = self.def.desc or ""
                if (tr and tr.unlockedAt) then
                    local dateFn = _G.date
                    local dateStr = (type(dateFn) == "function") and tostring(dateFn("%Y-%m-%d %H:%M", tr.unlockedAt)) or tostring(tr.unlockedAt)
                    desc = desc .. "\n\n|cffb4e634✓ Unlocked: " .. dateStr .. "|r"
                    if (tr.score) then
                        desc = desc .. string.format("\n|cffffd100GearScore at unlock: %d|r", tr.score)
                    end
                else
                    local curLvl = (TT and TT.GetGearLevelInfo and rec) and TT:GetGearLevelInfo(rec.currentScore or 0) or nil
                    local progressHint = getTrophyProgressHint(self.def.id, rec, curLvl)
                    if (progressHint) then
                        desc = desc .. "\n\n|cff59f0dc" .. progressHint .. "|r"
                    end
                    desc = desc .. "\n|cff888888Status: Locked|r"
                end
                showHoverTooltip(self, "🏆 " .. self.def.name, desc)
            end
        end)
        tBtn:SetScript("OnLeave", function(self)
            local rec = TT and TT.GetPlayerProgression and TT:GetPlayerProgression()
            local tr = rec and rec.trophies and rec.trophies[self.def.id]
            if (tr) then
                self:SetFlatColors(DASH_THEME.headerBg, DASH_THEME.borderEmerald)
            else
                self:SetFlatColors(DASH_THEME.headerBg, DASH_THEME.borderSubtle)
            end
            if (GameTooltip) then
                GameTooltip:Hide()
            end
        end)

        trophyButtons[i] = tBtn
    end

    progy = registerRow(progChild, trophyCard, "progression", progy, 126)

    -- Equipment Upgrade Chronicle Section
    progy = addSectionHeader(progChild, "Equipment Upgrade Chronicle", progy, "progression")

    local chronicleContainer = CreateFrame("Frame", nil, progChild)
    chronicleContainer:SetSize(DASH_CARD_W, 260)
    paintFlatBox(chronicleContainer, DASH_THEME.cardBg, DASH_THEME.borderSubtle)
    chronicleContainer.searchText = "chronicle upgrade history equipment gear log items"

    local currentFilter = "all"
    local chronicleOffset = 0
    local visibleChronicleRows = 6
    local cachedHistoryList = {}

    local filterAllBtn = createFlatActionCard(chronicleContainer, 72, 22, "All Slots", "gold")
    filterAllBtn:SetPoint("TOPLEFT", chronicleContainer, "TOPLEFT", 10, -8)

    local filterWeaponsBtn = createFlatActionCard(chronicleContainer, 76, 22, "Weapons", "plain")
    filterWeaponsBtn:SetPoint("LEFT", filterAllBtn, "RIGHT", 6, 0)

    local filterArmorBtn = createFlatActionCard(chronicleContainer, 66, 22, "Armor", "plain")
    filterArmorBtn:SetPoint("LEFT", filterWeaponsBtn, "RIGHT", 6, 0)

    local filterAccBtn = createFlatActionCard(chronicleContainer, 88, 22, "Accessories", "plain")
    filterAccBtn:SetPoint("LEFT", filterArmorBtn, "RIGHT", 6, 0)

    local chronicleCountText = chronicleContainer:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    chronicleCountText:SetPoint("RIGHT", chronicleContainer, "RIGHT", -12, 0)
    chronicleCountText:SetPoint("CENTER", filterAllBtn, "CENTER", 0, 0)
    chronicleCountText:SetText("|cff9ba3ae0 upgrades recorded|r")

    -- Column Header Bar
    local colBar = CreateFrame("Frame", nil, chronicleContainer)
    colBar:SetSize(712, 20)
    colBar:SetPoint("TOPLEFT", chronicleContainer, "TOPLEFT", 10, -36)
    paintFlatBox(colBar, DASH_THEME.headerBg, DASH_THEME.borderSubtle)

    local cHeadTime = colBar:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    cHeadTime:SetPoint("LEFT", colBar, "LEFT", 8, 0)
    cHeadTime:SetText("|cffffd100Date/Time|r")

    local cHeadSlot = colBar:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    cHeadSlot:SetPoint("LEFT", colBar, "LEFT", 110, 0)
    cHeadSlot:SetText("|cffffd100Slot|r")

    local cHeadPath = colBar:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    cHeadPath:SetPoint("LEFT", colBar, "LEFT", 210, 0)
    cHeadPath:SetText("|cffffd100Equipment Upgrade Path|r")

    local cHeadDelta = colBar:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    cHeadDelta:SetPoint("RIGHT", colBar, "RIGHT", -20, 0)
    cHeadDelta:SetText("|cffffd100Delta|r")

    local chronicleEmptyText = chronicleContainer:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    chronicleEmptyText:SetPoint("CENTER", chronicleContainer, "CENTER", -6, -24)
    chronicleEmptyText:SetWidth(520)
    chronicleEmptyText:SetJustifyH("CENTER")
    chronicleEmptyText:SetText("No equipment upgrades recorded for this filter yet.\nEquip new gear or click 'Snapshot Current Gear' below.")
    chronicleEmptyText:Hide()

    -- 6 Rows
    local chronicleRows = {}
    for r = 1, visibleChronicleRows do
        local row = CreateFrame("Button", nil, chronicleContainer)
        row:SetSize(692, 26)
        row:SetPoint("TOPLEFT", chronicleContainer, "TOPLEFT", 10, -58 - (r - 1) * 28)

        local rbg = row:CreateTexture(nil, "BACKGROUND")
        rbg:SetAllPoints()
        if (r % 2 == 0) then
            rbg:SetColorTexture(1, 1, 1, 0.03)
        else
            rbg:SetColorTexture(0, 0, 0, 0.20)
        end
        row.bg = rbg

        local rTime = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        rTime:SetPoint("LEFT", row, "LEFT", 8, 0)
        rTime:SetWidth(96)
        rTime:SetJustifyH("LEFT")
        row.timeTxt = rTime

        local rSlot = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        rSlot:SetPoint("LEFT", row, "LEFT", 110, 0)
        rSlot:SetWidth(90)
        rSlot:SetJustifyH("LEFT")
        row.slotTxt = rSlot

        local rPath = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        rPath:SetPoint("LEFT", row, "LEFT", 210, 0)
        rPath:SetPoint("RIGHT", row, "RIGHT", -90, 0)
        rPath:SetJustifyH("LEFT")
        row.pathTxt = rPath

        local rDelta = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        rDelta:SetPoint("RIGHT", row, "RIGHT", -16, 0)
        rDelta:SetWidth(70)
        rDelta:SetJustifyH("RIGHT")
        row.deltaTxt = rDelta

        row:SetScript("OnEnter", function(self)
            self.bg:SetColorTexture(1.0, 0.78, 0.12, 0.15)
            if (self.entry and GameTooltip) then
                if (self.entry.newLink and type(GameTooltip.SetHyperlink) == "function") then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:ClearLines()
                    local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, self.entry.newLink)
                    if (ok) then
                        if (type(GameTooltip.AddLine) == "function") then
                            GameTooltip:AddLine(" ")
                            local dVal = self.entry.deltaGS or 0
                            local dStr = (dVal > 0) and string.format("|cffb4e634+%d GS|r", dVal)
                                or (dVal < 0 and string.format("|cffff4d4d%d GS|r", dVal) or "|cffffff00NEW|r")
                            GameTooltip:AddDoubleLine("TacoTip Upgrade Delta:", dStr, 0.7, 0.75, 0.82, 1, 1, 1)
                            if (self.entry.oldLink) then
                                GameTooltip:AddLine("Replaced: " .. tostring(self.entry.oldLink), 0.75, 0.78, 0.84, true)
                            end
                            GameTooltip:AddLine("Shift-Click row to link item in chat.", 0.55, 0.60, 0.68, true)
                        end
                        GameTooltip:Show()
                        return
                    end
                end
                showHoverTooltip(self, self.entry.slotName or "Equipment Upgrade",
                    string.format("Item: %s\nGearScore: %d (%+d GS)\niLvl: %d\n\nShift-Click row to link item in chat.",
                        self.entry.newLink or "Unknown",
                        self.entry.newGS or 0,
                        self.entry.deltaGS or 0,
                        self.entry.newILvl or 0))
            end
        end)
        row:SetScript("OnLeave", function(self)
            if (r % 2 == 0) then
                self.bg:SetColorTexture(1, 1, 1, 0.03)
            else
                self.bg:SetColorTexture(0, 0, 0, 0.20)
            end
            if (GameTooltip) then
                GameTooltip:Hide()
            end
        end)
        row:SetScript("OnClick", function(self)
            if (IsShiftKeyDown() and self.entry and self.entry.newLink) then
                local insertFn = _G.ChatEdit_InsertLink
                if (type(insertFn) == "function") then
                    pcall(insertFn, self.entry.newLink)
                end
            end
        end)

        chronicleRows[r] = row
    end

    -- Scrollbar for Chronicle
    local cScrollBar = CreateFrame("Slider", nil, chronicleContainer)
    cScrollBar:SetPoint("TOPRIGHT", chronicleContainer, "TOPRIGHT", -8, -58)
    cScrollBar:SetPoint("BOTTOMRIGHT", chronicleContainer, "BOTTOMRIGHT", -8, 12)
    cScrollBar:SetWidth(12)
    cScrollBar:SetOrientation("VERTICAL")
    cScrollBar:SetMinMaxValues(0, 0)
    cScrollBar:SetValue(0)
    cScrollBar:SetValueStep(1)
    paintFlatBox(cScrollBar, DASH_THEME.headerBg, DASH_THEME.borderSubtle)

    local cThumb = cScrollBar:CreateTexture(nil, "OVERLAY")
    cThumb:SetTexture(WHITE8X8)
    cThumb:SetSize(10, 24)
    cThumb:SetVertexColor(0.85, 0.65, 0.15, 0.8)
    cScrollBar:SetThumbTexture(cThumb)

    cScrollBar:SetScript("OnValueChanged", function(_, val)
        chronicleOffset = math.floor(val)
        if (frame.RefreshChronicleList) then
            frame:RefreshChronicleList()
        end
    end)

    chronicleContainer:EnableMouseWheel(true)
    chronicleContainer:SetScript("OnMouseWheel", function(_, delta)
        local cur = cScrollBar:GetValue()
        local minVal, maxVal = cScrollBar:GetMinMaxValues()
        if (delta > 0) then
            cScrollBar:SetValue(math.max(minVal, cur - 1))
        else
            cScrollBar:SetValue(math.min(maxVal, cur + 1))
        end
    end)

    progy = registerRow(progChild, chronicleContainer, "progression", progy, 260)

    -- Progression Preferences & Actions
    progy = addSectionHeader(progChild, "Progression Settings & Actions", progy, "progression")

    syncControls.progression_chat = createPillToggle(progChild, "Chat Level-Up & Trophy Alerts",
        "Print a private notification to your chat window whenever your gear rank levels up or you unlock a trophy.",
        TacoTipConfig.progression_chat ~= false, function(v)
            TacoTipConfig.progression_chat = v
            onSettingChanged()
        end)
    progy = registerRow(progChild, syncControls.progression_chat, "progression", progy)

    syncControls.progression_sound = createPillToggle(progChild, "Level-Up Sound Fanfare",
        "Play a triumphant fanfare sound effect upon gaining a gear level.",
        TacoTipConfig.progression_sound ~= false, function(v)
            TacoTipConfig.progression_sound = v
            onSettingChanged()
        end)
    progy = registerRow(progChild, syncControls.progression_sound, "progression", progy)

    -- Action bar with 3 buttons
    local progActionCard = CreateFrame("Frame", nil, progChild)
    progActionCard:SetSize(DASH_CARD_W, 48)
    paintFlatBox(progActionCard, DASH_THEME.cardBg, DASH_THEME.borderSubtle)
    progActionCard.searchText = "snapshot export reset clear progression gear history"

    local snapBtn = createFlatActionCard(progActionCard, 150, 26, "Snapshot Current Gear", "emerald", function()
        if (TT and TT.EvaluatePlayerEquipment) then
            TT:EvaluatePlayerEquipment(false, true)
            if (frame.RefreshProgression) then frame:RefreshProgression() end
            local rec = TT.GetPlayerProgression and TT:GetPlayerProgression()
            local count = rec and rec.history and #rec.history or 0
            print(string.format("|cFFFFB81C[TacoTip]|r |cFFB4E634Equipment snapshot evaluated! (%d item(s) in chronicle)|r", count))
        end
    end, "Snapshot Gear", "Immediately scan your currently equipped gear and log any upgrades.")
    snapBtn:SetPoint("LEFT", progActionCard, "LEFT", 12, 0)

    local exportProgBtn = createFlatActionCard(progActionCard, 140, 26, "Export Progress Log", "gold", function()
        if (TT and TT.ExportProgressionReport) then
            local rep = TT:ExportProgressionReport()
            if (frame.SelectTab) then
                frame:SelectTab("diagnostics")
            end
            local diagB = _G.TacoTipDashboardDiagScroll and _G.TacoTipDashboardDiagScroll:GetScrollChild()
            if (diagB and diagB.SetText) then
                diagB:SetText(rep)
                diagB:SetFocus()
                diagB:HighlightText()
                print("|cFFFFB81C[TacoTip]|r Progression log generated in Diagnostics tab. Press |cFFFFD100Ctrl+C|r to copy!")
            end
        end
    end, "Export Log", "Generate a markdown summary of your gear progression, trophies, and upgrades.")
    exportProgBtn:SetPoint("LEFT", snapBtn, "RIGHT", 10, 0)

    local resetConfirm = false
    local clearProgBtn = createFlatActionCard(progActionCard, 130, 26, "Clear History", "danger", function(self)
        if (not resetConfirm) then
            resetConfirm = true
            self.text:SetText("Confirm Reset?")
            self:SetFlatColors({ 0.35, 0.10, 0.10, 1.0 }, DASH_THEME.borderAmber)
        else
            resetConfirm = false
            self.text:SetText("Clear History")
            self:SetFlatColors(DASH_THEME.cardBg, DASH_THEME.borderSubtle)
            if (TT and TT.ClearPlayerProgression) then
                TT:ClearPlayerProgression()
                if (frame.RefreshProgression) then frame:RefreshProgression() end
                print("|cFFFFB81C[TacoTip]|r Progression chronicle cleared for this character.")
            end
        end
    end, "Reset History", "Clear the upgrade chronicle and trophy progress for this character.")
    clearProgBtn:SetPoint("LEFT", exportProgBtn, "RIGHT", 10, 0)

    progy = registerRow(progChild, progActionCard, "progression", progy, 48)
    tabDefaultHeights.progression = math.abs(progy) + 20
    progChild:SetHeight(tabDefaultHeights.progression)

    -- Filter and refresh helpers
    local function filterChronicle(list, filter)
        local out = {}
        for _, entry in ipairs(list) do
            local sID = entry.slotID
            local match = true
            if (filter == "weapons") then
                match = (sID == 16 or sID == 17 or sID == 18)
            elseif (filter == "armor") then
                match = (sID == 1 or sID == 3 or sID == 5 or sID == 6 or sID == 7 or sID == 8 or sID == 9 or sID == 10)
            elseif (filter == "acc") then
                match = (sID == 2 or sID == 11 or sID == 12 or sID == 13 or sID == 14 or sID == 15)
            end
            if (match) then
                out[#out + 1] = entry
            end
        end
        return out
    end

    local function updateFilterButtons(active)
        currentFilter = active
        chronicleOffset = 0
        local activeBg = DASH_THEME.cardActiveBg
        local idleBg = DASH_THEME.cardBg
        filterAllBtn:SetFlatColors(active == "all" and activeBg or idleBg, active == "all" and DASH_THEME.borderGold or DASH_THEME.borderSubtle)
        filterWeaponsBtn:SetFlatColors(active == "weapons" and activeBg or idleBg, active == "weapons" and DASH_THEME.borderGold or DASH_THEME.borderSubtle)
        filterArmorBtn:SetFlatColors(active == "armor" and activeBg or idleBg, active == "armor" and DASH_THEME.borderGold or DASH_THEME.borderSubtle)
        filterAccBtn:SetFlatColors(active == "acc" and activeBg or idleBg, active == "acc" and DASH_THEME.borderGold or DASH_THEME.borderSubtle)
        cScrollBar:SetValue(0)
        if (frame.RefreshProgression) then frame:RefreshProgression() end
    end

    filterAllBtn:SetScript("OnMouseDown", function() updateFilterButtons("all") end)
    filterWeaponsBtn:SetScript("OnMouseDown", function() updateFilterButtons("weapons") end)
    filterArmorBtn:SetScript("OnMouseDown", function() updateFilterButtons("armor") end)
    filterAccBtn:SetScript("OnMouseDown", function() updateFilterButtons("acc") end)

    frame.RefreshChronicleList = function()
        local total = #cachedHistoryList
        local maxOffset = math.max(0, total - visibleChronicleRows)
        if (chronicleOffset > maxOffset) then
            chronicleOffset = maxOffset
        end
        cScrollBar:SetMinMaxValues(0, maxOffset)
        if (maxOffset > 0) then
            local thumbH = math.max(20, math.min(120, math.floor(170 * (visibleChronicleRows / total))))
            cThumb:SetSize(10, thumbH)
            cThumb:SetVertexColor(0.85, 0.65, 0.15, 0.85)
        else
            cThumb:SetSize(10, 48)
            cThumb:SetVertexColor(0.45, 0.48, 0.54, 0.35)
        end
        if (total == 0) then
            chronicleEmptyText:Show()
        else
            chronicleEmptyText:Hide()
        end

        for r = 1, visibleChronicleRows do
            local idx = chronicleOffset + r
            local row = chronicleRows[r]
            local entry = cachedHistoryList[idx]
            if (entry and row) then
                row.entry = entry
                row:Show()
                local dateFn = _G.date
                local tStr = entry.time and ((type(dateFn) == "function") and dateFn("%m/%d %H:%M", entry.time) or tostring(entry.time)) or "--"
                row.timeTxt:SetText(tStr)
                row.slotTxt:SetText(string.format("|cffffd100%s|r", entry.slotName or "Slot"))

                local oldTxt = entry.oldLink or (entry.oldGS and entry.oldGS > 0 and ("GS " .. tostring(entry.oldGS)) or "None")
                local newTxt = entry.newLink or ("GS " .. tostring(entry.newGS or 0))
                row.pathTxt:SetText(string.format("%s |cff888888→|r %s", oldTxt, newTxt))

                local dGS = entry.deltaGS or 0
                if (dGS > 0) then
                    row.deltaTxt:SetText(string.format("|cffb4e634+%d GS|r", dGS))
                elseif (dGS < 0) then
                    row.deltaTxt:SetText(string.format("|cffff4d4d%d GS|r", dGS))
                else
                    row.deltaTxt:SetText("|cffffff00NEW|r")
                end
            elseif (row) then
                row.entry = nil
                row:Hide()
            end
        end
    end

    frame.RefreshProgression = function()
        if (not TT or not TT.GetPlayerProgression) then return end
        local rec = TT:GetPlayerProgression()
        local currentScore = rec.currentScore or 0
        local peakScore = math.max(currentScore, rec.peakScore or 0)
        local levelInfo = TT:GetGearLevelInfo(currentScore)

        -- Update Hero Card
        local tierHex = levelInfo.tierColorHex or "FFFFD100"
        heroLevelText:SetText(string.format("|c%s[LEVEL %d]|r %s", tierHex, levelInfo.level, levelInfo.title))
        heroGSText:SetText(string.format("GearScore: |c%s%s|r", tierHex, tostring(currentScore)))
        heroNextText:SetText(string.format("|cff9ba3aeNext Rank:|r |cffb4e634+%d GS|r", levelInfo.remaining or 0))

        local unlockedCount = 0
        for _ in pairs(rec.trophies) do unlockedCount = unlockedCount + 1 end
        heroStatsText:SetText(string.format("Peak: |cffffd100%d|r  •  Average iLvl: |cffffffff%d|r  •  Upgrades: |cff59f0dc%d|r  •  Trophies: |cffb4e634%d/%d|r",
            peakScore,
            math.floor(rec.avgItemLevel or 0),
            #rec.history,
            unlockedCount,
            #trophyDefs))

        -- Update XP bar using live track width (fallback 734 = 736 - 2)
        local pct = math.min(100, math.max(0, levelInfo.percent or 0))
        local xpTrackW = (xpBarBg.GetWidth and xpBarBg:GetWidth()) or 736
        if (xpTrackW < 100) then xpTrackW = 736 end
        local xpInnerW = math.max(10, xpTrackW - 2)
        if (pct > 0) then
            local fillW = math.min(xpInnerW, math.max(2, math.floor(xpInnerW * (pct / 100) + 0.5)))
            xpBarFill:SetWidth(fillW)
            xpBarFill:Show()
            xpBarCursor:Show()
        else
            xpBarFill:SetWidth(1)
            xpBarFill:Hide()
            xpBarCursor:Hide()
        end
        local gsGlobal = rawget(_G, "TT_GS")
        if (currentScore > 0 and gsGlobal and gsGlobal.GetQuality) then
            local qr, qg, qb = gsGlobal:GetQuality(currentScore)
            if (qr and qg and qb) then
                xpBarFill:SetVertexColor(qr, qg, qb, 0.86)
            end
        else
            xpBarFill:SetVertexColor(0.18, 0.72, 0.40, 0.90)
        end
        xpBarText:SetText(string.format("%d / %d GS to Level %d (%d%%)",
            levelInfo.progress, levelInfo.step, levelInfo.level + 1, pct))

        -- Update 3-Column Milestone Strip
        mCol1Val:SetText(string.format("|c%sLv.%d|r  |cff9ba3ae(%d GS left)|r",
            tierHex, (levelInfo.level or 1) + 1, levelInfo.remaining or 0))
        if (CI and CI.IsForever and CI:IsForever() and TT.GetForeverProgressSection) then
            local foreverCap = math.max(1500, peakScore)
            local fSec, _, fIdx = TT:GetForeverProgressSection(currentScore, foreverCap)
            local list = TT.FOREVER_GS_SECTIONS
            local nextSec = (list and type(fIdx) == "number") and list[fIdx + 1] or nil
            if (nextSec) then
                mCol2Val:SetText(string.format("|c%s%s|r → |c%s%s|r (+%d)",
                    fSec.hex, fSec.label, nextSec.hex, nextSec.label, math.max(0, nextSec.minGS - currentScore)))
            else
                mCol2Val:SetText(string.format("|c%s%s|r (%d+ GS)", fSec.hex, fSec.label, fSec.minGS))
            end
        else
            local tierLabel = "Starter"
            local qr, qg, qb = 1, 1, 1
            if (gsGlobal and gsGlobal.GetQuality) then
                local cr, cg, cb, qDesc = gsGlobal:GetQuality(currentScore)
                qr, qg, qb = cr or 1, cg or 1, cb or 1
                if (qDesc and qDesc ~= "") then tierLabel = qDesc end
            end
            local capVal, bSize
            if (TT.GetGearScoreProgressCap) then
                capVal, bSize = TT:GetGearScoreProgressCap(currentScore, peakScore)
            end
            capVal = capVal or 1400
            bSize = bSize or 200
            local nextBracket = math.min(capVal, (math.floor(currentScore / bSize) + 1) * bSize)
            mCol2Val:SetText(string.format("|cff%02x%02x%02x%s|r · Next: %d GS",
                math.floor(qr * 255), math.floor(qg * 255), math.floor(qb * 255), tierLabel, nextBracket))
        end
        local bestEntry = nil
        for _, h in ipairs(rec.history or {}) do
            if ((tonumber(h.deltaGS) or 0) > (bestEntry and (tonumber(bestEntry.deltaGS) or 0) or 0)) then
                bestEntry = h
            end
        end
        if (bestEntry) then
            mCol3Val:SetText(string.format("|cffb4e634+%d GS|r · %s",
                tonumber(bestEntry.deltaGS) or 0, tostring(bestEntry.slotName or "Upgrade")))
        elseif ((tonumber(rec.equippedCount) or 0) > 0) then
            mCol3Val:SetText(string.format("|cff59f0dc%d / %d|r scored slots",
                tonumber(rec.equippedCount) or 0, tonumber(rec.totalSlots) or 17))
        else
            mCol3Val:SetText("|cff888888No upgrades logged yet|r")
        end

        if (heroPortrait and _G.SetPortraitTexture) then
            pcall(_G.SetPortraitTexture, heroPortrait, "player")
        end

        -- Update Trophies
        for _, tBtn in ipairs(trophyButtons) do
            local def = tBtn.def
            if (def) then
                local tr = rec.trophies[def.id]
                if (tr) then
                    if (tBtn.icon and tBtn.icon.SetDesaturated) then tBtn.icon:SetDesaturated(false) end
                    if (tBtn.icon and tBtn.icon.SetAlpha) then tBtn.icon:SetAlpha(1.0) end
                    tBtn.name:SetText(string.format("|cffffd100%s|r", def.name))
                    tBtn.status:SetText("|cffb4e634UNLOCKED|r")
                    tBtn:SetFlatColors(DASH_THEME.headerBg, DASH_THEME.borderEmerald)
                else
                    if (tBtn.icon and tBtn.icon.SetDesaturated) then tBtn.icon:SetDesaturated(true) end
                    if (tBtn.icon and tBtn.icon.SetAlpha) then tBtn.icon:SetAlpha(0.35) end
                    tBtn.name:SetText(string.format("|cff888888%s|r", def.name))
                    tBtn.status:SetText("|cff666666Locked|r")
                    tBtn:SetFlatColors(DASH_THEME.headerBg, DASH_THEME.borderSubtle)
                end
            end
        end

        -- Update Chronicle
        cachedHistoryList = filterChronicle(rec.history or {}, currentFilter)
        chronicleCountText:SetText(string.format("|cff9ba3aeShowing %d of %d upgrades|r", #cachedHistoryList, #(rec.history or {})))
        frame:RefreshChronicleList()
    end

    TT.RefreshProgressionDashboard = function()
        if (frame:IsShown()) then
            if (frame.RefreshHeaderProgress) then
                frame:RefreshHeaderProgress()
            end
            if (frame.activeTab == "progression" and frame.RefreshProgression) then
                frame:RefreshProgression()
            end
        end
    end

    -- ========================================================================
    -- Tab 8: TacoTip Extras (Only when TacoTip_Extras is installed and loaded)
    -- ========================================================================
    if (hasExtras) then
        local _, extrasChild = createScrollCategory("extras", "Extras", "TacoTip Extras",
            "Server leaderboard, peer-to-peer sync, and advanced equipment auditing.", 8)
        local ey = 0

        local noticeExtras = createNoticeBox(extrasChild, "|cffb4e634[CONNECTED]|r",
            "TacoTip Extras is active. Peer-to-peer synchronization and server rankings are running.", true)
        ey = registerStaticRow(extrasChild, noticeExtras, "extras", ey, 34, 8)

        ey = addSectionHeader(extrasChild, "Leaderboard & Server Rankings", ey, "extras")

        -- ====================================================================
        -- Embedded Leaderboard Surface
        -- ====================================================================
        local lbContainer = CreateFrame("Frame", nil, extrasChild)
        lbContainer:SetSize(DASH_CARD_W, 372)
        paintFlatBox(lbContainer, DASH_THEME.cardBg, DASH_THEME.borderGold)
        lbContainer.searchText = "server leaderboard rankings gearscore ranks ex"

        local currentTab = "all"
        local searchQuery = ""
        local currentOffset = 0
        local visibleRowsCount = 10
        local cachedLeaderboardList = {}
        local syncStatusText
        local updateDashboardSyncProgress

        -- Toolbar (y = -8)
        local allBtn = createFlatActionCard(lbContainer, 80, 24, "All Realm", "gold")
        allBtn:SetPoint("TOPLEFT", lbContainer, "TOPLEFT", 10, -8)

        local allyBtn = createFlatActionCard(lbContainer, 75, 24, "Alliance", "plain")
        allyBtn:SetPoint("LEFT", allBtn, "RIGHT", 6, 0)

        local hordeBtn = createFlatActionCard(lbContainer, 70, 24, "Horde", "plain")
        hordeBtn:SetPoint("LEFT", allyBtn, "RIGHT", 6, 0)

        local lbSearch = CreateFrame("EditBox", nil, lbContainer, "InputBoxTemplate")
        lbSearch:SetSize(124, 20)
        lbSearch:SetPoint("LEFT", hordeBtn, "RIGHT", 14, 0)
        lbSearch:SetAutoFocus(false)
        lbSearch:SetFontObject("GameFontHighlightSmall")

        local lbSearchPlaceholder = lbSearch:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        lbSearchPlaceholder:SetPoint("LEFT", lbSearch, "LEFT", 4, 0)
        lbSearchPlaceholder:SetText("Filter player/guild...")

        local lbSearchClearBtn = createFlatActionCard(lbContainer, 18, 18, "x", "plain", function()
            lbSearch:SetText("")
            lbSearch:ClearFocus()
        end, "Clear Filter", "Reset player/guild search filter.")
        lbSearchClearBtn:SetPoint("LEFT", lbSearch, "RIGHT", 2, 0)
        lbSearchClearBtn:Hide()

        local syncQuickBtn = createFlatActionCard(lbContainer, 80, 24, "Sync Now", "emerald")
        syncQuickBtn:SetPoint("TOPRIGHT", lbContainer, "TOPRIGHT", -10, -8)

        local popupBtn = createFlatActionCard(lbContainer, 90, 24, "Open Popup", "plain")
        popupBtn:SetPoint("RIGHT", syncQuickBtn, "LEFT", -6, 0)

        -- Column Header Bar (y = -38, height 22)
        local tableHeader = CreateFrame("Frame", nil, lbContainer)
        tableHeader:SetPoint("TOPLEFT", lbContainer, "TOPLEFT", 10, -38)
        tableHeader:SetSize(712, 22)
        paintFlatBox(tableHeader, DASH_THEME.headerBg, DASH_THEME.borderSubtle)

        local colRank = tableHeader:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        colRank:SetPoint("LEFT", tableHeader, "LEFT", 8, 0)
        colRank:SetText("|cffffd100#|r")

        local colPlayer = tableHeader:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        colPlayer:SetPoint("LEFT", tableHeader, "LEFT", 42, 0)
        colPlayer:SetText("|cffffd100Player|r")

        local colGuild = tableHeader:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        colGuild:SetPoint("LEFT", tableHeader, "LEFT", 195, 0)
        colGuild:SetText("|cffffd100Guild|r")

        local colLvl = tableHeader:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        colLvl:SetPoint("LEFT", tableHeader, "LEFT", 335, 0)
        colLvl:SetText("|cffffd100Lvl|r")

        local colSpec = tableHeader:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        colSpec:SetPoint("LEFT", tableHeader, "LEFT", 375, 0)
        colSpec:SetText("|cffffd100Spec|r")

        local colILvl = tableHeader:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        colILvl:SetPoint("LEFT", tableHeader, "LEFT", 485, 0)
        colILvl:SetText("|cffffd100iLvl|r")

        local colGS = tableHeader:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        colGS:SetPoint("LEFT", tableHeader, "LEFT", 545, 0)
        colGS:SetText("|cffffd100GearScore|r")

        local lbEmptyText = lbContainer:CreateFontString(nil, "ARTWORK", "GameFontDisable")
        lbEmptyText:SetPoint("CENTER", lbContainer, "CENTER", -8, -12)
        lbEmptyText:SetWidth(520)
        lbEmptyText:SetJustifyH("CENTER")
        lbEmptyText:SetText("No ranked players recorded yet.\nInspect players in-world or trigger a peer sync.")
        lbEmptyText:Hide()

        -- 10 Rows
        local rows = {}
        for r = 1, visibleRowsCount do
            local row = CreateFrame("Button", nil, lbContainer)
            row:SetSize(692, 24)
            row:SetPoint("TOPLEFT", lbContainer, "TOPLEFT", 10, -62 - (r - 1) * 25)

            local rbg = row:CreateTexture(nil, "BACKGROUND")
            rbg:SetAllPoints()
            if (r % 2 == 0) then
                rbg:SetColorTexture(1, 1, 1, 0.03)
            else
                rbg:SetColorTexture(0, 0, 0, 0.20)
            end
            row.bg = rbg

            local classBar = row:CreateTexture(nil, "ARTWORK")
            classBar:SetPoint("LEFT", row, "LEFT", 0, 0)
            classBar:SetSize(3, 24)
            classBar:SetColorTexture(0.7, 0.7, 0.7, 1)
            row.classBar = classBar

            local rankTxt = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            rankTxt:SetPoint("LEFT", row, "LEFT", 8, 0)
            row.rankTxt = rankTxt

            local nameTxt = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            nameTxt:SetPoint("LEFT", row, "LEFT", 42, 0)
            nameTxt:SetWidth(148)
            nameTxt:SetJustifyH("LEFT")
            row.nameTxt = nameTxt

            local guildTxt = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
            guildTxt:SetPoint("LEFT", row, "LEFT", 195, 0)
            guildTxt:SetWidth(135)
            guildTxt:SetJustifyH("LEFT")
            row.guildTxt = guildTxt

            local lvlTxt = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
            lvlTxt:SetPoint("LEFT", row, "LEFT", 335, 0)
            row.lvlTxt = lvlTxt

            local specTxt = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            specTxt:SetPoint("LEFT", row, "LEFT", 375, 0)
            specTxt:SetWidth(105)
            specTxt:SetJustifyH("LEFT")
            row.specTxt = specTxt

            local ilvlTxt = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            ilvlTxt:SetPoint("LEFT", row, "LEFT", 485, 0)
            row.ilvlTxt = ilvlTxt

            local gsTxt = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            gsTxt:SetPoint("LEFT", row, "LEFT", 545, 0)
            row.gsTxt = gsTxt

            row:SetScript("OnEnter", function(self)
                self.bg:SetColorTexture(1.0, 0.78, 0.12, 0.15)
                if (self.entry) then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:ClearLines()
                    GameTooltip:AddLine(tostring(self.entry.name or "Unknown"), 1, 1, 1)
                    if (self.entry.guild and self.entry.guild ~= "") then
                        GameTooltip:AddLine("<" .. tostring(self.entry.guild) .. ">", 0.6, 0.8, 1)
                    end
                    GameTooltip:AddLine("GearScore: " .. tostring(self.entry.gs or 0), 1, 0.82, 0)
                    if (self.entry.ilvl and self.entry.ilvl > 0) then
                        GameTooltip:AddLine("Average iLvl: " .. tostring(self.entry.ilvl), 0.8, 0.8, 0.8)
                    end
                    GameTooltip:Show()
                end
            end)
            row:SetScript("OnLeave", function(self)
                if (r % 2 == 0) then
                    self.bg:SetColorTexture(1, 1, 1, 0.03)
                else
                    self.bg:SetColorTexture(0, 0, 0, 0.20)
                end
                GameTooltip:Hide()
            end)

            rows[r] = row
        end

        -- Scroll slider on right (vertical flat slider matching chronicle scrollbar)
        local scrollBar = CreateFrame("Slider", nil, lbContainer)
        scrollBar:SetPoint("TOPRIGHT", lbContainer, "TOPRIGHT", -10, -62)
        scrollBar:SetPoint("BOTTOMRIGHT", lbContainer, "BOTTOMRIGHT", -10, 61)
        scrollBar:SetWidth(12)
        scrollBar:SetOrientation("VERTICAL")
        scrollBar:SetMinMaxValues(0, 0)
        scrollBar:SetValue(0)
        scrollBar:SetValueStep(1)
        if (scrollBar.SetObeyStepOnDrag) then scrollBar:SetObeyStepOnDrag(true) end
        paintFlatBox(scrollBar, DASH_THEME.headerBg, DASH_THEME.borderSubtle)

        local sbThumb = scrollBar:CreateTexture(nil, "OVERLAY")
        sbThumb:SetTexture(WHITE8X8)
        sbThumb:SetSize(10, 28)
        sbThumb:SetVertexColor(0.87, 0.72, 0.20, 0.90)
        scrollBar:SetThumbTexture(sbThumb)

        -- Sync Progress Bar above status strip
        local lbSyncBar = CreateFrame("StatusBar", nil, lbContainer)
        lbSyncBar:SetPoint("BOTTOMLEFT", lbContainer, "BOTTOMLEFT", 12, 33)
        lbSyncBar:SetPoint("BOTTOMRIGHT", lbContainer, "BOTTOMRIGHT", -12, 33)
        lbSyncBar:SetHeight(16)
        paintFlatBox(lbSyncBar, DASH_THEME.headerBg, DASH_THEME.borderSubtle)
        if (lbSyncBar.SetStatusBarTexture) then
            lbSyncBar:SetStatusBarTexture(WHITE8X8)
        end
        if (lbSyncBar.SetStatusBarColor) then
            lbSyncBar:SetStatusBarColor(0.66, 0.48, 0.86, 0.85)
        end
        lbSyncBar:SetMinMaxValues(0, 1)
        lbSyncBar:SetValue(0)
        lbSyncBar:Hide()

        local lbSyncText = lbSyncBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbSyncText:SetPoint("LEFT", lbSyncBar, "LEFT", 6, 0)
        lbSyncText:SetText("")

        -- Bottom Status Strip
        local statusStrip = lbContainer:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        statusStrip:SetPoint("BOTTOMLEFT", lbContainer, "BOTTOMLEFT", 12, 10)
        statusStrip:SetText("Rankings loading...")

        local topBtn = createFlatActionCard(lbContainer, 50, 20, "Top", "plain", function()
            scrollBar:SetValue(0)
        end)
        topBtn:SetPoint("BOTTOMRIGHT", lbContainer, "BOTTOMRIGHT", -10, 8)

        local myRankBtn = createFlatActionCard(lbContainer, 70, 20, "My Rank", "gold", function()
            local myGUID = playerGUID()
            if (myGUID) then
                for idx, entry in ipairs(cachedLeaderboardList) do
                    if (entry.guid == myGUID) then
                        local targetOffset = math.max(0, idx - math.floor(visibleRowsCount / 2))
                        scrollBar:SetValue(targetOffset)
                        break
                    end
                end
            end
        end)
        myRankBtn:SetPoint("RIGHT", topBtn, "LEFT", -6, 0)

        local function getEntryClassColor(classToken)
            if (classToken == "SHAMAN" and (not TacoTipConfig or TacoTipConfig.shaman_blue ~= false)) then
                return 0.0, 0.44, 0.87
            end
            local colors = _G.CUSTOM_CLASS_COLORS or _G.RAID_CLASS_COLORS
            local c = colors and classToken and colors[classToken]
            if (c) then
                return c.r, c.g, c.b
            end
            return 0.82, 0.82, 0.82
        end

        local function getGsQualityColor(score)
            local s = tonumber(score)
            if (not s or s <= 0) then
                return 0.50, 0.50, 0.50
            end
            local gsModule = rawget(_G, "TT_GS")
            if (gsModule and type(gsModule.GetQuality) == "function") then
                local ok, r, g, b = pcall(gsModule.GetQuality, gsModule, s)
                if (ok and type(r) == "number") then
                    return r, g, b
                end
            end
            -- Client-aware GearScore range bands: Classic Era/Forever: 200, TBC: 400, Retail/Titanforge: 1000
            local bSize = 1000
            if (CI and ((CI.IsClassic and CI:IsClassic()) or (CI.IsForever and CI:IsForever()))) then
                bSize = 200
            elseif (CI and CI.IsTBC and CI:IsTBC()) then
                bSize = 400
            end
            if (s > bSize * 6) then return 0.92, 0.10, 0.10 -- Artifact
            elseif (s > bSize * 5) then return 1.00, 0.63, 0.00 -- Legendary
            elseif (s > bSize * 4) then return 0.63, 0.20, 0.83 -- Epic
            elseif (s > bSize * 3) then return 0.12, 0.40, 0.83 -- Superior
            elseif (s > bSize * 2) then return 0.12, 0.81, 0.04 -- Uncommon
            elseif (s > bSize) then return 1.00, 1.00, 1.00 -- Common
            end
            return 0.50, 0.50, 0.50 -- Trash
        end

        local function getRankRangeColor(rank, total)
            local rNum = tonumber(rank)
            if (not rNum) then return 0.62, 0.62, 0.62 end
            if (rNum == 1) then return 1.00, 0.84, 0.00 end -- #1 Gold medal
            if (rNum == 2) then return 0.75, 0.75, 0.75 end -- #2 Silver medal
            if (rNum == 3) then return 0.80, 0.50, 0.20 end -- #3 Bronze medal

            local tot = tonumber(total)
            if (tot and tot > 0) then
                local fraction = (tot - rNum + 1) / tot
                if (fraction >= 0.95) then
                    return 1.00, 0.84, 0.00 -- Top 5% Gold
                elseif (fraction >= 0.75) then
                    return 0.63, 0.20, 0.83 -- Top 25% Epic Purple
                elseif (fraction >= 0.50) then
                    return 0.12, 0.40, 0.83 -- Top 50% Superior Blue
                elseif (fraction >= 0.25) then
                    return 0.12, 0.81, 0.04 -- Top 75% Uncommon Green
                else
                    return 1.00, 1.00, 1.00 -- Common White
                end
            end
            return 0.62, 0.62, 0.62
        end

        local function updateRows()
            local total = #cachedLeaderboardList
            local maxScroll = math.max(0, total - visibleRowsCount)
            if (currentOffset > maxScroll) then currentOffset = maxScroll end
            if (currentOffset < 0) then currentOffset = 0 end
            scrollBar:SetMinMaxValues(0, maxScroll)
            if (sbThumb) then
                if (sbThumb.SetSize) then
                    local thumbH = total > visibleRowsCount
                        and math.max(22, math.min(120, math.floor(249 * (visibleRowsCount / total))))
                        or 28
                    sbThumb:SetSize(10, thumbH)
                end
                if (sbThumb.SetAlpha) then
                    sbThumb:SetAlpha(maxScroll > 0 and 0.95 or 0.25)
                end
            end

            local myGUID = playerGUID()
            for r = 1, visibleRowsCount do
                local entryIdx = currentOffset + r
                local entry = cachedLeaderboardList[entryIdx]
                local row = rows[r]
                if (entry) then
                    row.entry = entry
                    local rank = entry.rank or entryIdx
                    local rr, rg, rb = getRankRangeColor(rank, total)
                    row.rankTxt:SetText("#" .. tostring(rank))
                    row.rankTxt:SetTextColor(rr, rg, rb)

                    local cr, cg, cb = getEntryClassColor(entry.class)
                    row.classBar:SetColorTexture(cr, cg, cb, 0.9)

                    local pName = entry.name or "Unknown"
                    if (entry.guid == myGUID) then
                        pName = "|cffffd100► |r" .. pName
                    end
                    row.nameTxt:SetText(pName)
                    row.nameTxt:SetTextColor(cr, cg, cb)

                    row.guildTxt:SetText(entry.guild and entry.guild ~= "" and ("<" .. entry.guild .. ">") or "")
                    row.lvlTxt:SetText(tostring(entry.level or ""))

                    local specOrClass = entry.specName
                    if (not specOrClass or specOrClass == "" or specOrClass == "Unknown") then
                        specOrClass = entry.class or "--"
                    end
                    row.specTxt:SetText(specOrClass)

                    local gsVal = entry.gs or 0
                    local gr, gg, gb = getGsQualityColor(gsVal)
                    row.gsTxt:SetText(tostring(gsVal))
                    row.gsTxt:SetTextColor(gr, gg, gb)

                    local ilvlVal = entry.ilvl or 0
                    row.ilvlTxt:SetText(ilvlVal > 0 and tostring(ilvlVal) or "")
                    row.ilvlTxt:SetTextColor(gr, gg, gb)

                    row:Show()
                else
                    row.entry = nil
                    row:Hide()
                end
            end

            local realmName = _G.GetRealmName and _G.GetRealmName() or "Realm"
            local myRank = nil
            if (myGUID) then
                for idx, entry in ipairs(cachedLeaderboardList) do
                    if (entry.guid == myGUID) then
                        myRank = idx
                        break
                    end
                end
            end
            if (total == 0) then
                if (searchQuery and searchQuery ~= "") then
                    lbEmptyText:SetText(string.format("No players match \"%s\".\nClick 'x' next to the filter box to show all players.", tostring(searchQuery)))
                else
                    lbEmptyText:SetText("No ranked players recorded yet on " .. realmName .. ".\nInspect players in-world or trigger a peer sync.")
                end
                lbEmptyText:Show()
                statusStrip:SetText("|cff888888No matching players recorded on " .. realmName .. ".|r")
            elseif (myRank) then
                lbEmptyText:Hide()
                statusStrip:SetText(string.format("|cffb4e634Standing:|r Rank |cffffd100#%d|r of %d on %s", myRank, total, realmName))
            else
                lbEmptyText:Hide()
                statusStrip:SetText(string.format("|cff9ba3aeLeaderboard:|r %d player(s) tracked on %s", total, realmName))
            end
        end

        scrollBar:SetScript("OnValueChanged", function(_, val)
            currentOffset = math.floor(val + 0.5)
            updateRows()
        end)

        lbContainer:EnableMouseWheel(true)
        lbContainer:SetScript("OnMouseWheel", function(_, delta)
            local minV, maxV = scrollBar:GetMinMaxValues()
            local curV = scrollBar:GetValue()
            local nextV = math.max(minV, math.min(maxV, curV - delta * 2))
            scrollBar:SetValue(nextV)
        end)

        updateDashboardSyncProgress = function()
            local getProg = rawget(_G, "TacoTipExtrasGetSyncProgress")
            local prog = type(getProg) == "function" and getProg() or nil
            if (type(prog) ~= "table" or not prog.status or prog.status == "idle") then
                lbSyncBar:Hide()
                return
            end
            local pct = tonumber(prog.percent) or 0
            if (pct < 0) then
                pct = 0
            elseif (pct > 1) then
                pct = 1
            end
            if (prog.status == "syncing" and pct <= 0) then
                pct = 0.08
            elseif (prog.status == "complete" or prog.status == "failed") then
                pct = 1
            end

            local msg = tostring(prog.message or "")
            local label
            if (prog.status == "complete") then
                if (lbSyncBar.SetStatusBarColor) then
                    lbSyncBar:SetStatusBarColor(0.24, 0.78, 0.34, 0.85)
                end
                label = "Complete (100%)" .. (msg ~= "" and (" - " .. msg) or "")
                if (syncStatusText) then
                    syncStatusText:SetText("|cff40e060✓ " .. label .. "|r")
                end
            elseif (prog.status == "failed") then
                if (lbSyncBar.SetStatusBarColor) then
                    lbSyncBar:SetStatusBarColor(0.86, 0.24, 0.24, 0.85)
                end
                label = "Failed" .. (msg ~= "" and (" - " .. msg) or "")
                if (syncStatusText) then
                    syncStatusText:SetText("|cfff55555✗ " .. label .. "|r")
                end
            else
                if (lbSyncBar.SetStatusBarColor) then
                    lbSyncBar:SetStatusBarColor(0.66, 0.48, 0.86, 0.85)
                end
                label = string.format("Syncing (%d%%)%s", math.floor(pct * 100 + 0.5),
                    msg ~= "" and (" - " .. msg) or "")
                if (syncStatusText) then
                    syncStatusText:SetText("|cffcfa8ff" .. label .. "|r")
                end
            end

            lbSyncBar:SetValue(pct)
            lbSyncText:SetText(label)
            lbSyncBar:Show()
        end

        local function refreshLeaderboardData()
            if (frame and type(frame.IsShown) == "function" and not frame:IsShown()) then
                return
            end
            if (lbContainer and type(lbContainer.IsShown) == "function" and not lbContainer:IsShown()) then
                return
            end
            local rankDB = rawget(_G, "TacoTipExtrasRankDB")
            if (not rankDB or type(rankDB.GetLeaderboard) ~= "function") then
                cachedLeaderboardList = {}
                updateRows()
                updateDashboardSyncProgress()
                return
            end
            local rawList = rankDB.GetLeaderboard(nil, currentTab, "ALL", searchQuery, nil)
            cachedLeaderboardList = rawList or {}
            updateRows()
            updateDashboardSyncProgress()
        end

        local function setTab(tabName)
            currentTab = tabName
            allBtn:SetFlatColors(tabName == "all" and DASH_THEME.cardActiveBg or DASH_THEME.cardBg,
                tabName == "all" and DASH_THEME.borderGold or DASH_THEME.borderSubtle)
            allyBtn:SetFlatColors(tabName == "alliance" and DASH_THEME.cardActiveBg or DASH_THEME.cardBg,
                tabName == "alliance" and DASH_THEME.borderGold or DASH_THEME.borderSubtle)
            hordeBtn:SetFlatColors(tabName == "horde" and DASH_THEME.cardActiveBg or DASH_THEME.cardBg,
                tabName == "horde" and DASH_THEME.borderGold or DASH_THEME.borderSubtle)
            currentOffset = 0
            scrollBar:SetValue(0)
            refreshLeaderboardData()
        end

        allBtn:SetScript("OnMouseDown", function() setTab("all") end)
        allyBtn:SetScript("OnMouseDown", function() setTab("alliance") end)
        hordeBtn:SetScript("OnMouseDown", function() setTab("horde") end)

        lbSearch:SetScript("OnTextChanged", function(self)
            local q = self:GetText() or ""
            if (q == "") then
                lbSearchPlaceholder:Show()
                lbSearchClearBtn:Hide()
            else
                lbSearchPlaceholder:Hide()
                lbSearchClearBtn:Show()
            end
            searchQuery = q
            currentOffset = 0
            scrollBar:SetValue(0)
            refreshLeaderboardData()
        end)

        syncQuickBtn:SetScript("OnMouseDown", function()
            local syncNow = rawget(_G, "TacoTipExtrasSyncNow")
            if (type(syncNow) == "function") then
                pcall(syncNow, true)
            elseif (type(_G.SlashCmdList) == "table" and type(_G.SlashCmdList.TTGSSYNC) == "function") then
                pcall(_G.SlashCmdList.TTGSSYNC, "")
            end
            refreshLeaderboardData()
        end)

        popupBtn:SetScript("OnMouseDown", function()
            local toggle = rawget(_G, "TacoTipExtrasToggleLeaderboard")
            if (type(toggle) == "function") then
                pcall(toggle)
            elseif (type(_G.SlashCmdList) == "table" and type(_G.SlashCmdList.TACOTIPEXTRAS) == "function") then
                pcall(_G.SlashCmdList.TACOTIPEXTRAS, "ranks")
            end
        end)

        frame.RefreshEmbeddedLeaderboard = refreshLeaderboardData
        rawset(_G, "TacoTip_RefreshExtrasLeaderboardUI", refreshLeaderboardData)

        ey = registerRow(extrasChild, lbContainer, "extras", ey, 372)

        ey = addSectionHeader(extrasChild, "Peer-to-Peer Database Synchronization", ey, "extras")

        -- Action Card: Sync Now
        local syncCard = CreateFrame("Frame", nil, extrasChild)
        syncCard:SetSize(DASH_CARD_W, 56)
        paintFlatBox(syncCard, DASH_THEME.cardBg, DASH_THEME.borderSubtle)
        syncCard.searchText = "sync now database peer p2p ttgssync broadcast"

        local syncIcon = syncCard:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        syncIcon:SetPoint("LEFT", syncCard, "LEFT", 14, 0)
        syncIcon:SetText("|cffb4e634[P2P]|r")

        local syncTitle = syncCard:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        syncTitle:SetPoint("TOPLEFT", syncIcon, "TOPRIGHT", 10, 4)
        syncTitle:SetText("Sync Database Now (/ttgssync)")

        local syncDesc = syncCard:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        syncDesc:SetPoint("TOPLEFT", syncTitle, "BOTTOMLEFT", 0, -2)
        syncDesc:SetPoint("RIGHT", syncCard, "RIGHT", -120, 0)
        syncDesc:SetJustifyH("LEFT")
        syncDesc:SetText("Broadcast sync queries to guild, party, and background sync channel.")

        syncStatusText = extrasChild:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")

        local syncBtn = createFlatActionCard(syncCard, 100, 26, "Sync Now", "emerald", function()
            local syncNow = rawget(_G, "TacoTipExtrasSyncNow")
            if (type(syncNow) == "function") then
                pcall(syncNow, true)
            elseif (type(_G.SlashCmdList) == "table" and type(_G.SlashCmdList.TTGSSYNC) == "function") then
                pcall(_G.SlashCmdList.TTGSSYNC, "")
            end
            if (type(rawget(_G, "TacoTipExtrasGetSyncProgress")) == "function") then
                updateDashboardSyncProgress()
            else
                syncStatusText:SetText("|cffb4e634✓ Sync request broadcast to peers!|r")
            end
            if (frame.RefreshEmbeddedLeaderboard) then frame:RefreshEmbeddedLeaderboard() end
        end, "Sync Now", "Trigger an immediate peer-to-peer sync with guild, party, and sync channel.")
        syncBtn:SetPoint("RIGHT", syncCard, "RIGHT", -12, 0)

        ey = registerRow(extrasChild, syncCard, "extras", ey, 56)

        syncStatusText:SetPoint("TOPLEFT", syncCard, "BOTTOMLEFT", 6, -3)
        ey = ey - 18

        -- Action Card: Open Extras Settings
        local optCard = CreateFrame("Frame", nil, extrasChild)
        optCard:SetSize(DASH_CARD_W, 52)
        paintFlatBox(optCard, DASH_THEME.cardBg, DASH_THEME.borderSubtle)
        optCard.searchText = "extras settings options configuration ex tte"

        local optIcon = optCard:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        optIcon:SetPoint("LEFT", optCard, "LEFT", 14, 0)
        optIcon:SetText("|cff9ba3ae[CFG]|r")

        local optTitle = optCard:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        optTitle:SetPoint("TOPLEFT", optIcon, "TOPRIGHT", 10, 4)
        optTitle:SetText("Extras Settings Panel (/ex)")

        local optDesc = optCard:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        optDesc:SetPoint("TOPLEFT", optTitle, "BOTTOMLEFT", 0, -2)
        optDesc:SetPoint("RIGHT", optCard, "RIGHT", -120, 0)
        optDesc:SetJustifyH("LEFT")
        optDesc:SetText("Configure advanced tooltip formatting, minimap icon, and equipment auditing.")

        local optBtn = createFlatActionCard(optCard, 100, 26, "Open Config", "plain", function()
            local openOpt = rawget(_G, "TacoTipExtrasOpenOptions")
            if (type(openOpt) == "function") then
                pcall(openOpt)
            elseif (type(_G.SlashCmdList) == "table" and type(_G.SlashCmdList.TACOTIPEXTRAS) == "function") then
                pcall(_G.SlashCmdList.TACOTIPEXTRAS, "")
            end
        end, "Open Settings", "Open TacoTip Extras configuration panel.")
        optBtn:SetPoint("RIGHT", optCard, "RIGHT", -12, 0)

        ey = registerRow(extrasChild, optCard, "extras", ey, 52)

        ey = addSectionHeader(extrasChild, "Architecture & Privacy Notice", ey, "extras")

        local infoBox = createNoticeBox(extrasChild, "|cffffd100[INFO]|r",
            "No remote server or external database is used. All leaderboard rankings and gear records are synced peer-to-peer (P2P) in-game via WoW addon messages and saved directly to your local SavedVariables.", false, 50)
        ey = registerStaticRow(extrasChild, infoBox, "extras", ey, 50, 8)

        tabDefaultHeights.extras = math.abs(ey) + 20
        extrasChild:SetHeight(tabDefaultHeights.extras)
    end

    -- ========================================================================
    -- Tab 9: Diagnostics
    -- ========================================================================
    do
        local diag = addTab("diagnostics", "Diagnostics", 1, true)
        local dh = diag:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        dh:SetPoint("TOPLEFT", diag, "TOPLEFT", 0, 0)
        dh:SetText("|cffffd100System Diagnostics & Health Monitor|r")

        local verdictText = diag:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        verdictText:SetPoint("TOPLEFT", dh, "BOTTOMLEFT", 0, -6)

        local diagBoxFrame = CreateFrame("Frame", nil, diag)
        diagBoxFrame:SetPoint("TOPLEFT", verdictText, "BOTTOMLEFT", 0, -8)
        diagBoxFrame:SetPoint("BOTTOMRIGHT", diag, "BOTTOMRIGHT", -4, 38)
        paintFlatBox(diagBoxFrame, DASH_THEME.inputBg, DASH_THEME.borderSubtle)

        local diagScroll = CreateFrame("ScrollFrame", "TacoTipDashboardDiagScroll", diagBoxFrame, "UIPanelScrollFrameTemplate")
        diagScroll:SetPoint("TOPLEFT", diagBoxFrame, "TOPLEFT", 8, -8)
        diagScroll:SetPoint("BOTTOMRIGHT", diagBoxFrame, "BOTTOMRIGHT", -26, 8)
        diagScroll:EnableMouseWheel(true)
        diagScroll:SetScript("OnMouseWheel", function(self, delta)
            local step = 36
            local cur = self:GetVerticalScroll() or 0
            local maxV = self:GetVerticalScrollRange() or 0
            self:SetVerticalScroll(math.max(0, math.min(maxV, cur - delta * step)))
        end)

        local diagBox = CreateFrame("EditBox", nil, diagScroll)
        diagBox:SetMultiLine(true)
        diagBox:SetAutoFocus(false)
        diagBox:SetFontObject("GameFontHighlightSmall")
        diagBox:SetWidth(694)
        diagBox:EnableMouseWheel(true)
        diagBox:SetScript("OnMouseWheel", function(_, delta)
            diagScroll:GetScript("OnMouseWheel")(diagScroll, delta)
        end)
        diagBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        diagScroll:SetScrollChild(diagBox)

        local showingTraces = false
        local diagActionStatus = diag:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        diagActionStatus:SetPoint("BOTTOMRIGHT", diag, "BOTTOMRIGHT", -6, 10)
        diagActionStatus:SetJustifyH("RIGHT")
        diagActionStatus:SetText("")

        frame.RefreshDiagnostics = function()
            local report, verdict = buildDiagnosticsReport()
            local statusLabel
            if (not verdict) then
                statusLabel = "|cffff4d4d[UNAVAILABLE]|r Diagnostics engine failed"
            elseif (not verdict.healthy) then
                if (verdict.severity == "error") then
                    statusLabel = "|cffff4d4d[FAILURES DETECTED]|r " .. tostring(verdict.text or "Errors logged")
                else
                    statusLabel = "|cffffd100[WARNINGS LOGGED]|r " .. tostring(verdict.text or "Warnings detected")
                end
            else
                statusLabel = "|cffb4e634[HEALTHY]|r " .. tostring(verdict.text or "All systems nominal")
            end
            verdictText:SetText("Status: " .. statusLabel)

            if (showingTraces) then
                local traces = (TT and TT.FormatDiagnosticTraces) and TT:FormatDiagnosticTraces() or "No detailed traces available."
                diagBox:SetText(traces)
            else
                diagBox:SetText(report)
            end
        end

        frame.ExportDiagnostics = function()
            if (TT and TT.FormatDiagnosticExport) then
                local exp = TT:FormatDiagnosticExport()
                diagBox:SetText(exp)
                diagBox:SetFocus()
                diagBox:HighlightText()
                diagActionStatus:SetText("|cffb4e634Markdown selected (Ctrl+C)|r")
                print("|cff59f0dcTacoTip:|r Markdown diagnostic report generated & selected! Press |cffffd100Ctrl+C|r to copy.")
            end
        end

        local copyCard = createFlatActionCard(diag, 100, 26, "Select (Ctrl+C)", "emerald", function()
            diagBox:SetFocus()
            diagBox:HighlightText()
            diagActionStatus:SetText("|cffb4e634Text selected (Ctrl+C)|r")
        end, "Copy report", "Selects the whole report. Press Ctrl+C, then paste it into Discord or a bug report.")
        copyCard:SetPoint("BOTTOMLEFT", diag, "BOTTOMLEFT", 0, 4)

        local exportCard = createFlatActionCard(diag, 115, 26, "Export Markdown", "emerald", function()
            if (frame.ExportDiagnostics) then
                frame:ExportDiagnostics()
            end
        end, "Export Markdown", "Generate a clean Markdown diagnostic bundle ready for Discord or GitHub.")
        exportCard:SetPoint("LEFT", copyCard, "RIGHT", 6, 0)

        local refreshCard = createFlatActionCard(diag, 70, 26, "Refresh", "plain", function()
            frame:RefreshDiagnostics()
            diagActionStatus:SetText("|cff9ba3aeDiagnostics refreshed|r")
        end, "Refresh", "Re-run system diagnostics collection.")
        refreshCard:SetPoint("LEFT", exportCard, "RIGHT", 6, 0)

        local traceToggleCard
        traceToggleCard = createFlatActionCard(diag, 175, 26, "View Error & Warning Traces", "gold", function()
            showingTraces = not showingTraces
            if (showingTraces) then
                traceToggleCard.text:SetText("View Summary Report")
            else
                traceToggleCard.text:SetText("View Error & Warning Traces")
            end
            diagActionStatus:SetText("")
            frame:RefreshDiagnostics()
        end, "Toggle Traces", "Switch between the full diagnostic summary and detailed error/warning stack traces.")
        traceToggleCard:SetPoint("LEFT", refreshCard, "RIGHT", 6, 0)

        local clearCard = createFlatActionCard(diag, 85, 26, "Clear Logs", "danger", function()
            if (TT and TT.ClearDiagnosticLogs) then
                TT:ClearDiagnosticLogs()
            end
            frame:RefreshDiagnostics()
            diagActionStatus:SetText("|cffffd100Trace logs cleared|r")
        end, "Clear Logs", "Clear the in-memory error and warning trace logs.")
        clearCard:SetPoint("LEFT", traceToggleCard, "RIGHT", 6, 0)
    end

    -- ========================================================================
    -- Tab 10: Community Hub
    -- ========================================================================
    do
        local community = addTab("community", "Community", 2, true)
        local ch = community:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        ch:SetPoint("TOPLEFT", community, "TOPLEFT", 0, 0)
        ch:SetText("|cffffd100Community Hub & Credits|r")

        local cd = createWrappedText(community, "GameFontHighlightSmall", DASH_CARD_W,
            "|cffffd100200,000+ downloads|r - thank you for helping TacoTip grow! Click |cffffd100Select|r beside any link and press |cffffd100Ctrl+C|r to copy.")
        cd:SetPoint("TOPLEFT", ch, "BOTTOMLEFT", 0, -6)

        local function createCommunityLinkCard(anchor, offsetY, badgeText, titleText, url)
            local card = CreateFrame("Frame", nil, community)
            card:SetSize(DASH_CARD_W, 54)
            card:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, offsetY)
            paintFlatBox(card, DASH_THEME.cardBg, DASH_THEME.borderSubtle)

            local lbl = card:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            lbl:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -8)
            lbl:SetText(badgeText .. " " .. titleText)

            local edit = CreateFrame("EditBox", nil, card, "InputBoxTemplate")
            edit:SetAutoFocus(false)
            edit:SetSize(590, 22)
            edit:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 4, -4)
            edit:SetText(url)
            edit:SetFontObject("GameFontHighlightSmall")
            edit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
            edit:SetScript("OnTextChanged", function(self) if (self:GetText() ~= url) then self:SetText(url) end end)
            edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

            local selBtn = createFlatActionCard(card, 90, 22, "Select (Ctrl+C)", "gold", function()
                edit:SetFocus()
                edit:HighlightText()
            end)
            selBtn:SetPoint("RIGHT", card, "RIGHT", -12, -7)
            return card
        end

        local c1 = createCommunityLinkCard(cd, -12, "|cffffd100[DISCORD]|r", "Discord Community & Support", DISCORD_INVITE_URL)
        local c2 = createCommunityLinkCard(c1, -8, "|cffb4e634[CURSE]|r", "TacoTip on CurseForge", CURSEFORGE_URL)
        local c3 = createCommunityLinkCard(c2, -8, "|cff59f0dc[EXTRAS]|r", "TacoTip Extras Companion Addon", EXTRAS_URL)

        local cmdCard = CreateFrame("Frame", nil, community)
        cmdCard:SetSize(DASH_CARD_W, 74)
        cmdCard:SetPoint("TOPLEFT", c3, "BOTTOMLEFT", 0, -10)
        paintFlatBox(cmdCard, DASH_THEME.headerBg, DASH_THEME.borderSubtle)

        local cmdHead = cmdCard:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        cmdHead:SetPoint("TOPLEFT", cmdCard, "TOPLEFT", 12, -8)
        cmdHead:SetText("|cffffd100Slash Commands & Attribution|r")

        local cmdBody = createWrappedText(cmdCard, "GameFontHighlightSmall", DASH_CARD_W - 24,
            "|cffffd100/tt|r Dashboard  ·  |cffffd100/tt move|r Mover  ·  |cffffd100/tt diag|r Diagnostics  ·  |cffffd100/tacotip|r Options" ..
            (hasExtras and "  ·  |cffffd100/ex|r Extras" or "") ..
            "\n|cff9ba3aeTacoTip v" .. tostring(addOnVersion) .. " by AcidBomb — Original TacoTip lineage by kebabstorm (MIT License).|r")
        cmdBody:SetPoint("TOPLEFT", cmdHead, "BOTTOMLEFT", 0, -5)
    end

    -- ========================================================================
    -- Tab 11: Reset Defaults
    -- ========================================================================
    do
        local resetPage = addTab("reset", "Reset Defaults", 3, true)
        local rh = resetPage:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        rh:SetPoint("TOPLEFT", resetPage, "TOPLEFT", 0, 0)
        rh:SetText("|cffffd100Reset Configuration|r")

        local rd = createWrappedText(resetPage, "GameFontHighlightSmall", DASH_CARD_W,
            "Restore all TacoTip settings back to their default recommended values.")
        rd:SetPoint("TOPLEFT", rh, "BOTTOMLEFT", 0, -6)

        local rNotice = createNoticeBox(resetPage, "|cffff4d4d[RESET]|r",
            "Warning: This will restore all tooltip styles, colors, positioning offsets, and toggles back to defaults.")
        rNotice:SetPoint("TOPLEFT", rd, "BOTTOMLEFT", 0, -14)

        local rConfirm = resetPage:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        rConfirm:SetPoint("TOPLEFT", rNotice, "BOTTOMLEFT", 0, -16)
        rConfirm:SetText("Are you sure you want to reset all settings to defaults?")

        local rStatus = resetPage:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        rStatus:SetPoint("TOPLEFT", rConfirm, "BOTTOMLEFT", 0, -12)
        rStatus:SetText("")

        local rDoBtn = createFlatActionCard(resetPage, 220, 28, "Restore Defaults Now", "danger", function()
            resetCfg()
            if (TT.RefreshOptionsUI) then TT:RefreshOptionsUI() end
            if (frame.RefreshAll) then frame:RefreshAll() end
            rStatus:SetText("|cffb4e634✓ Configuration restored to defaults.|r")
        end, "Reset", "Restore all settings to default.")
        rDoBtn:SetPoint("TOPLEFT", rStatus, "BOTTOMLEFT", 0, -8)
    end

    -- Update dependency gating across toggles, sliders, pickers, and offset nudgers
    frame.RefreshDependencyStates = function()
        local hasGuild = TacoTipConfig.show_guild_name and true or false
        if (syncControls.show_guild_rank) then
            syncControls.show_guild_rank:SetDisabled(not hasGuild, "Enable 'Show Guild Name' above first.")
        end
        if (syncControls.guild_rank_alt_style) then
            syncControls.guild_rank_alt_style:SetDisabled(not (hasGuild and TacoTipConfig.show_guild_rank),
                "Requires both 'Show Guild Name' and 'Show Guild Rank'.")
        end

        local hasPortrait = TacoTipConfig.tooltip_portrait and true or false
        if (syncControls.tooltip_portrait_3d) then
            syncControls.tooltip_portrait_3d:SetDisabled(not hasPortrait, "Enable 'Show Unit Portrait' above first.")
        end
        if (syncControls.tooltip_portrait_invert_side) then
            syncControls.tooltip_portrait_invert_side:SetDisabled(not hasPortrait, "Enable 'Show Unit Portrait' above first.")
        end
        if (syncControls.tooltip_portrait_scale) then
            syncControls.tooltip_portrait_scale:SetDisabled(not hasPortrait, "Enable 'Show Unit Portrait' above first.")
        end
        if (syncControls.tooltip_portrait_zoom) then
            syncControls.tooltip_portrait_zoom:SetDisabled(not (hasPortrait and TacoTipConfig.tooltip_portrait_3d),
                "Requires both 'Show Unit Portrait' and '3D Animated Model'.")
        end

        if (syncControls.class_icon_size) then
            syncControls.class_icon_size:SetDisabled(not TacoTipConfig.show_class_icon, "Enable 'Show Class Icon' above first.")
        end

        if (syncControls.show_gs_items_hs) then
            syncControls.show_gs_items_hs:SetDisabled(not TacoTipConfig.show_gs_items, "Enable 'Show Item GearScore' above first.")
        end

        local hasCustomPos = TacoTipConfig.custom_pos ~= nil
        local anchorMouse = TacoTipConfig.anchor_mouse and true or false
        if (syncControls.custom_position) then
            syncControls.custom_position:SetDisabled(anchorMouse, "Disable 'Anchor to Mouse Cursor' first to use Custom Position.")
        end
        if (syncControls.custom_anchor) then
            syncControls.custom_anchor:SetDisabled(not hasCustomPos, "Enable 'Custom Tooltip Position' above first.")
        end
        if (syncControls.anchor_mouse) then
            syncControls.anchor_mouse:SetDisabled(hasCustomPos, "Disable 'Custom Tooltip Position' first to anchor to cursor.")
        end
        if (syncControls.anchor_mouse_world) then
            syncControls.anchor_mouse_world:SetDisabled(not anchorMouse, "Enable 'Anchor to Mouse Cursor' above first.")
        end

        local declaredEdge = TT and TT.GetDeclaredTooltipBorderEdgeSize and TT:GetDeclaredTooltipBorderEdgeSize() or nil
        if (syncControls.tooltip_border_edge_size) then
            syncControls.tooltip_border_edge_size:SetDisabled(declaredEdge ~= nil,
                "Selected border texture specifies its own fixed edge size.")
        end

        local hasCharGS = TacoTipConfig.show_gs_character and true or false
        local hasCharIlvl = TacoTipConfig.show_avg_ilvl and true or false
        if (syncControls.unlock_info_position) then
            syncControls.unlock_info_position:SetDisabled(not (hasCharGS or hasCharIlvl),
                "Enable Character GearScore or Average iLvl overlays above first.")
        end
        if (syncControls.char_gs_offsets) then syncControls.char_gs_offsets:SetDisabled(not hasCharGS) end
        if (syncControls.inspect_gs_offsets) then syncControls.inspect_gs_offsets:SetDisabled(not hasCharGS) end
        if (syncControls.char_ilvl_offsets) then syncControls.char_ilvl_offsets:SetDisabled(not hasCharIlvl) end
        if (syncControls.inspect_ilvl_offsets) then syncControls.inspect_ilvl_offsets:SetDisabled(not hasCharIlvl) end
    end

    -- Refresh all dashboard controls from TacoTipConfig
    frame.RefreshAll = function()
        if (frame._refreshStyleCards) then frame._refreshStyleCards() end
        for k, ctl in pairs(syncControls) do
            if (ctl.SetChecked and TacoTipConfig[k] ~= nil) then
                ctl:SetChecked(TacoTipConfig[k])
            end
        end
        if (syncControls.uber_tooltips and GetCVar) then
            syncControls.uber_tooltips:SetChecked(GetCVar("UberTooltips") == "1")
        end
        if (syncControls.chat_class_colors and GetCVar) then
            syncControls.chat_class_colors:SetChecked(GetCVar("chatClassColorOverride") == "0")
        end
        local hasAchievements = CI and CI.IsRetail and CI:IsRetail() and true or false
        if (syncControls.show_achievement_points) then
            if (hasAchievements) then
                syncControls.show_achievement_points:SetDisabled(false)
                syncControls.show_achievement_points:SetChecked(TacoTipConfig.show_achievement_points)
            else
                syncControls.show_achievement_points:SetDisabled(true, "Achievement point comparison is restricted to Retail clients.")
                syncControls.show_achievement_points:SetChecked(false)
            end
        end
        if (syncControls.show_pawn_player) then
            if (isPawnLoaded) then
                syncControls.show_pawn_player:SetDisabled(false)
                syncControls.show_pawn_player:SetChecked(TacoTipConfig.show_pawn_player)
            else
                syncControls.show_pawn_player:SetDisabled(true, "Pawn addon is not loaded or missing.")
                syncControls.show_pawn_player:SetChecked(false)
            end
        end
        if (syncControls.custom_position) then
            syncControls.custom_position:SetChecked(TacoTipConfig.custom_pos ~= nil)
        end
        if (syncControls.custom_anchor) then
            syncControls.custom_anchor:SetValue(TacoTipConfig.custom_anchor or "TOPLEFT")
        end
        if (syncControls.combat_modifier) then
            syncControls.combat_modifier:SetValue(TacoTipConfig.combat_modifier or "NONE")
            syncControls.combat_modifier:SetDisabled(not TacoTipConfig.hide_in_combat,
                "Enable 'Hide Tooltips in Combat' above to use a modifier reveal key.")
        end
        if (syncControls.tooltip_scale) then
            syncControls.tooltip_scale:SetValueSilently(TacoTipConfig.tooltip_scale or 1.0)
        end
        if (syncControls.tooltip_delay) then
            syncControls.tooltip_delay:SetValueSilently(math.floor((TacoTipConfig.tooltip_delay or 0) * 1000 + 0.5))
        end
        if (syncControls.tooltip_border_edge_size) then
            local declaredEdge = TT and TT.GetDeclaredTooltipBorderEdgeSize and TT:GetDeclaredTooltipBorderEdgeSize()
            syncControls.tooltip_border_edge_size:SetValueSilently(
                declaredEdge or TacoTipConfig.tooltip_border_edge_size or DEFAULTS.tooltip_border_edge_size or 16)
        end
        if (syncControls.tooltip_border_alpha) then
            syncControls.tooltip_border_alpha:SetValueSilently(math.floor((TacoTipConfig.tooltip_border_alpha or 0.9) * 100 + 0.5))
        end
        if (syncControls.tooltip_background_alpha) then
            syncControls.tooltip_background_alpha:SetValueSilently(math.floor((TacoTipConfig.tooltip_background_alpha or 0.85) * 100 + 0.5))
        end
        if (syncControls.tooltip_font_size) then
            syncControls.tooltip_font_size:SetValueSilently(TacoTipConfig.tooltip_font_size or 12)
        end
        if (syncControls.tooltip_max_width) then
            syncControls.tooltip_max_width:SetValueSilently(TacoTipConfig.tooltip_max_width or 0)
        end
        if (syncControls.tooltip_portrait_scale) then
            syncControls.tooltip_portrait_scale:SetValueSilently(TacoTipConfig.tooltip_portrait_scale or 1.0)
        end
        if (syncControls.tooltip_portrait_zoom) then
            syncControls.tooltip_portrait_zoom:SetValueSilently(TacoTipConfig.tooltip_portrait_zoom or 0.7)
        end
        if (syncControls.class_icon_size) then
            syncControls.class_icon_size:SetValueSilently(TacoTipConfig.class_icon_size or 20)
        end
        if (syncControls.locale_override) then syncControls.locale_override:RefreshValue() end
        if (syncControls.tooltip_bar_texture) then syncControls.tooltip_bar_texture:RefreshValue() end
        if (syncControls.tooltip_border_texture) then syncControls.tooltip_border_texture:RefreshValue() end
        if (syncControls.tooltip_background_texture) then syncControls.tooltip_background_texture:RefreshValue() end
        if (syncControls.tooltip_font) then syncControls.tooltip_font:RefreshValue() end
        if (syncControls.tooltip_border_color) then syncControls.tooltip_border_color:RefreshColor() end
        if (syncControls.tooltip_background_color) then syncControls.tooltip_background_color:RefreshColor() end
        if (syncControls.char_gs_offsets) then syncControls.char_gs_offsets:RefreshOffsets() end
        if (syncControls.char_ilvl_offsets) then syncControls.char_ilvl_offsets:RefreshOffsets() end
        if (syncControls.inspect_gs_offsets) then syncControls.inspect_gs_offsets:RefreshOffsets() end
        if (syncControls.inspect_ilvl_offsets) then syncControls.inspect_ilvl_offsets:RefreshOffsets() end
        if (frame._refreshPositionSummary) then frame._refreshPositionSummary() end
        if (frame.RefreshDependencyStates) then frame:RefreshDependencyStates() end
        if (frame.RefreshDiagnostics) then frame:RefreshDiagnostics() end
        if (frame.RefreshHeaderProgress) then frame:RefreshHeaderProgress() end
        if (frame.RefreshProgression and frame.activeTab == "progression") then frame:RefreshProgression() end
    end

    -- Real-time Search Filter Engine (with clean Y-reflow & section header folding)
    applySearch = function()
        inSearchUpdate = true
        if (pickerPopup and pickerPopup:IsShown()) then pickerPopup:Hide() end
        local query = strlower(searchBox:GetText() or "")
        query = query:match("^%s*(.-)%s*$") or ""
        if (query == "") then
            searchPlaceholder:Show()
            searchClearBtn:Hide()
            for tabId, entries in pairs(tabLayoutEntries) do
                local child = tabScrollChildren[tabId]
                for _, entry in ipairs(entries) do
                    if (entry.frame) then
                        entry.frame:Show()
                        if (child and entry.defaultY) then
                            entry.frame:ClearAllPoints()
                            entry.frame:SetPoint("TOPLEFT", child, "TOPLEFT",
                                entry.kind == "header" and 6 or 0, entry.defaultY)
                        end
                    end
                end
                if (child and tabDefaultHeights[tabId]) then
                    child:SetHeight(tabDefaultHeights[tabId])
                end
            end
            for tabId, btn in pairs(tabButtons) do
                btn.text:SetText(tabLabels[tabId] or tabId)
            end
        else
            searchPlaceholder:Hide()
            searchClearBtn:Show()
            local tabCounts = {}
            local matchSet = {}
            for _, item in ipairs(allSearchItems) do
                local matches = strfind(item.searchText or "", query, 1, true) ~= nil
                if (matches) then
                    matchSet[item] = true
                    tabCounts[item.tabId] = (tabCounts[item.tabId] or 0) + 1
                end
            end
            if ((tabCounts[frame.activeTab] or 0) == 0) then
                for _, tabId in ipairs(orderedCategoryIds) do
                    if ((tabCounts[tabId] or 0) > 0) then
                        selectTab(tabId)
                        break
                    end
                end
            end
            for tabId, entries in pairs(tabLayoutEntries) do
                local child = tabScrollChildren[tabId]
                local activeTab = (tabId == frame.activeTab)
                if (activeTab) then
                    local visibleHeaders = {}
                    for _, entry in ipairs(entries) do
                        if (entry.kind == "card" and entry.frame and matchSet[entry.frame] and entry.section) then
                            visibleHeaders[entry.section] = true
                        end
                    end
                    local curY = 0
                    for _, entry in ipairs(entries) do
                        local f = entry.frame
                        if (f) then
                            if (entry.kind == "header") then
                                if (visibleHeaders[f]) then
                                    f:ClearAllPoints()
                                    f:SetPoint("TOPLEFT", child, "TOPLEFT", 6, curY - 4)
                                    f:Show()
                                    curY = curY - 26
                                else
                                    f:Hide()
                                end
                            elseif (entry.kind == "card") then
                                if (matchSet[f]) then
                                    f:ClearAllPoints()
                                    f:SetPoint("TOPLEFT", child, "TOPLEFT", 0, curY)
                                    f:Show()
                                    curY = curY - (entry.height or 42) - (entry.gap or 8)
                                else
                                    f:Hide()
                                end
                            else
                                f:Hide()
                            end
                        end
                    end
                    if (child) then
                        child:SetHeight(math.max(120, math.abs(curY) + 20))
                    end
                else
                    for _, entry in ipairs(entries) do
                        if (entry.frame) then entry.frame:Hide() end
                    end
                end
            end
            for tabId, btn in pairs(tabButtons) do
                local count = tabCounts[tabId] or 0
                local base = tabLabels[tabId] or tabId
                if (count > 0) then
                    btn.text:SetText(base .. " |cffffb81c(" .. count .. ")|r")
                else
                    btn.text:SetText(base)
                end
            end
        end
        inSearchUpdate = false
    end

    searchBox:SetScript("OnTextChanged", function() applySearch() end)
    searchBox:SetScript("OnEditFocusGained", function() searchPlaceholder:Hide() end)
    searchBox:SetScript("OnEditFocusLost", function(self)
        if ((self:GetText() or "") == "") then searchPlaceholder:Show() end
    end)
    searchBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
        applySearch()
    end)

    frame:SetScript("OnShow", function(self)
        if (self.RefreshAll) then self:RefreshAll() end
    end)
    frame:SetScript("OnHide", function()
        if (pickerPopup and pickerPopup:IsShown()) then pickerPopup:Hide() end
    end)

    selectTab("general")
    return frame
end

function TT:ShowStandaloneDashboard(tab)
    if (not dashboard) then
        dashboard = createDashboard()
    end
    dashboard:Show()
    dashboard:SelectTab(tab or dashboard.activeTab or "general")
end

function TT:ToggleStandaloneDashboard()
    if (dashboard and dashboard:IsShown()) then
        dashboard:Hide()
    else
        TT:ShowStandaloneDashboard()
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
    if (dashboard and dashboard:IsShown() and dashboard.RefreshAll) then
        dashboard:RefreshAll()
    end
end

local function onPageShow(panel)
    ensureModernOptionsBuilt()
    if (panel and panel.Refresh) then panel:Refresh() end
end
local function onOptionsFrameShow(panel)
    ensureModernOptionsBuilt()
    modernGetConfig()
end

-- Retail / WoW Forever drive the canvas pages through three OPTIONAL frame
-- handlers, documented in Blizzard_Settings_Shared/Blizzard_ImplementationReadme.lua:
--
--   OnRefresh  called when the settings panel is shown
--   OnDefault  called when the panel's "restore defaults" is used
--   OnCommit   called when the panel's Apply is used
--
-- The addon previously relied on OnShow alone. OnShow fires when the canvas
-- frame becomes visible, but the Settings panel controls that visibility and
-- reuses an already-shown frame, so a page can be re-selected without OnShow
-- ever firing -- which leaves the controls showing stale values.
--
-- These are METHODS, not scripts. Blizzard calls `frame:OnRefresh()`,
-- `frame:OnDefault()` and `frame:OnCommit()` directly
-- (Blizzard_SettingsPanel.lua:8, :2, :557) and never SetScripts them, so they
-- must be assigned as function fields. SetScript("OnRefresh", ...) is rejected
-- by the C API with "bad argument #2 to 'SetScript'" -- these three names are
-- reserved canvas handlers, not script slots. OnShow is kept because the classic
-- InterfaceOptions_AddCategory path has no such handlers and relies on it.
local PAGES_WITH_REFRESH = { optionsPages.tooltips, optionsPages.positioning, optionsPages.characterInspect }
for _, page in ipairs(PAGES_WITH_REFRESH) do
    page:SetScript("OnShow", function(panel, ...)
        return safeCall(onPageShow, panel, ...)
    end)
    page.OnRefresh = onPageShow
    page.OnDefault = onPageShow
    page.OnCommit = onPageShow
end

optionsFrame:SetScript("OnShow", function(panel, ...)
    return safeCall(onOptionsFrameShow, panel, ...)
end)
optionsFrame.OnRefresh = onOptionsFrameShow
optionsFrame.OnDefault = onOptionsFrameShow
optionsFrame.OnCommit = onOptionsFrameShow
