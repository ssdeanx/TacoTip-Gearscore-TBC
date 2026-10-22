local addOnName = ...
local addOnVersion = (GetAddOnMetadata and GetAddOnMetadata(addOnName, "Version")) or
    (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addOnName, "Version")) or "0.8.4"
local addOnTitle = (GetAddOnMetadata and GetAddOnMetadata(addOnName, "Title")) or
    (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addOnName, "Title")) or addOnName
local tinsert = tinsert or table.insert

--- Runs a function so that it cannot taint the frame whose script chain it
--- executes in.
---
--- `securecall` is the engine's own containment primitive; Blizzard uses it
--- for exactly this shape -- `Blizzard_BuffFrame/BuffFrame.lua:991`
--- `securecall(self.UpdateDuration, self, self.timeLeft); -- Taint issue with
--- SecondsToTimeAbbrev`, and `Blizzard_CatalogShop_Outbound.lua:17`
--- `securecall("GameTooltip_Hide");`. It is an engine global on every
--- supported client (`Blizzard_FrameXML/SharedPetBattleTemplates.lua:5`
--- `local securecall = securecall;`).
---
--- Why the options panel needs it: the hover tooltips below write to the
--- SHARED GameTooltip (`SetOwner`, `ClearLines`, `SetText`, `Show`). The
--- shared tooltip is the frame the game menu's own buttons anchor to, and
--- addon code that mutates it from inside a Blizzard frame's script chain
--- taints that chain -- the taint then reaches the game menu and the
--- Logout/Quit button is refused (ADDON_ACTION_FORBIDDEN). See main.lua's
--- runUntainted for the full argument.
local secureCallFn = nil
if (type(securecall) == "function") then
    -- Probed once at load, for the same reason as main.lua's copy: the probe
    -- proves the engine actually runs a function through `securecall` from
    -- this add-on's context, so a build that ever refused addon code to call
    -- it degrades to the direct call instead of raising on every hover.
    local probeRan = false
    local probeOk = pcall(securecall, function() probeRan = true end)
    if (probeOk and probeRan) then
        secureCallFn = securecall
    end
end

local function runUntainted(fn, ...)
    if (secureCallFn) then
        return secureCallFn(fn, ...)
    end
    return fn(...)
end



-- Forward declaration: assigned below once TT exists. applyScanSetting (and
-- the registration helpers) call it at runtime, never at load.
local recordOptionsRegFailure



-- Late-load re-evaluation (hunter C3): no file-scope snapshot is kept here.
-- Refresh reads the LIVE state so a Pawn installed/enabled after TacoTip
-- enables the checkbox without a /reload. Routes to the single home
-- (TT_PAWN.IsAvailable, pawn.lua -- Batch 5 N3); the inline probe below runs
-- only when pawn.lua itself is absent (an invalid state) and keeps the same
-- shape, with the same tonumber guard so a string-typed version global
-- cannot raise here either.
local function isPawnAvailableNow()
    local pawn = rawget(_G, "TT_PAWN")
    local probe = pawn and pawn.IsAvailable
    if (type(probe) == "function") then
        return probe()
    end
    local classicVer = rawget(_G, "PawnClassicLastUpdatedVersion")
    local retailVer = rawget(_G, "PawnLastUpdatedVersion")
    local apiPresent = type(_G.PawnGetItemData) == "function" and
        type(_G.PawnGetSingleValueFromItem) == "function" and
        type(_G.PawnGetScaleColor) == "function"
    local classicNum = tonumber(classicVer)
    local retailNum = tonumber(retailVer)
    return (classicNum and classicNum >= 2.0538) or (retailNum and retailNum >= 2.0) or
        apiPresent
end

local Detours = LibStub("LibDetours-1.0")
local CI = LibStub("LibForeverInspector")

-- The proximity scan (GearScore collection for nearby players) is toggled
-- through LibForeverInspector's public SetScanEnabled / scanEnabled API.
-- Returns true when the library accepted the new state, false otherwise.
-- Failures are recorded for /tacotip diag (problems[]) with a one-shot chat
-- line -- a panel that just never appears is the exact silence hunter H7
-- exists to end. Never prints on success.
local function applyScanSetting(enabled)
    if (type(LibStub) ~= "function" and type(LibStub) ~= "table") then
        recordOptionsRegFailure("scan apply (no LibStub)", nil)
        return false
    end
    local ok, inspector = pcall(LibStub, "LibForeverInspector", true)
    if (not ok or type(inspector) ~= "table") then
        recordOptionsRegFailure("scan apply (no inspector)", ok and nil or inspector)
        return false
    end
    if (type(inspector.SetScanEnabled) ~= "function") then
        recordOptionsRegFailure("scan apply (no SetScanEnabled)", nil)
        return false
    end
    -- Narrow pcall: only the setter itself is guarded, so a raise names the
    -- apply rather than the whole options panel, and the error is logged
    -- instead of swallowed.
    local okApply, errApply = pcall(inspector.SetScanEnabled, inspector, enabled and true or false)
    if (not okApply) then
        recordOptionsRegFailure("scan apply", errApply)
        return false
    end
    return true
end

local L = _G.TACOTIP_LOCALE
local TT = _G[addOnName]

if (not TT) then
    TT = {}
    rawset(_G, addOnName, TT)
end

-- Options-side failure ledger for hunter H7. Registration and scan-apply
-- failures are recorded here (deduped, one chat line per distinct failure)
-- and surfaced by main.lua's /tacotip diag problems[] -- the panel reads the
-- shared TT table, never a setter, so reporting cannot perturb the UI.
recordOptionsRegFailure = function(which, err)
    TT.optionsRegErrors = TT.optionsRegErrors or {}
    local entry = "options registration failed: " .. tostring(which)
    if (err ~= nil) then
        entry = entry .. " (" .. tostring(err) .. ")"
    end
    for _, e in ipairs(TT.optionsRegErrors) do
        if (e == entry) then
            return
        end
    end
    TT.optionsRegErrors[#TT.optionsRegErrors + 1] = entry
    print("|cff59f0dcTacoTip:|r " .. entry)
end

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
    show_power_bar = false,
    shaman_blue = true,
    tooltip_border_use_class = true,
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
    -- Off by default: a spell/action-button tooltip must respect the saved
    -- custom tooltip position unless the user opts into mouse anchoring.
    -- When this was true, the SetDefaultAnchor hook returned early for spell
    -- owners and the saved position was never applied to them.
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
    show_honor_rank = false,
    show_ilvl_inline = false,
    show_realm = false,
    show_role_icon = true,
    show_separators = false,
    -- Proximity scan: inspect in-range players automatically so GearScore is
    -- collected without hovering. Named "scan" because the runtime scan
    -- diagnostics in main.lua already use that name (settings_test.lua requires
    -- a declared key to appear in a runtime file); nil/absent means enabled,
    -- matching the library default.
    scan = true,
    tooltip_delay = 0,
    tooltip_max_width = 0,
    custom_anchor = "TOPLEFT",
}

function TT:GetDefaults()
    local copy = {}
    for k, v in pairs(DEFAULTS) do
        copy[k] = v
    end
    return copy
end

-- The portrait zoom's ONE source of truth.
--
-- The shipped default lives in DEFAULTS, but two other places repeated a
-- DIFFERENT literal (0.7) as their fallback: the slider's displayed value
-- and the render path in main.lua. With no saved zoom value the slider
-- therefore showed 70 while the portrait was rendered at 75 -- the number
-- the player saw was not the number they got.
--
-- These two fields are the single source both consumers read:
--   TT.TooltipPortraitZoomDefault -- the value to use when none is saved.
--   TT.TooltipPortraitZoomRange   -- the bounds the slider and the
--                                    sanitiser enforce (min, max).
--
-- The RANGE is unchanged: 0.3 to 1.0, exactly what the slider (30-100) and
-- the sanitiser have always expressed. The zoom is applied exactly as the
-- player set it -- no cap, no clamp.
TT.TooltipPortraitZoomDefault = DEFAULTS.tooltip_portrait_zoom
TT.TooltipPortraitZoomRange = {
    min = 0.3,
    max = 1.0,
}

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

-- Media allowlist backing for SafeSanitizeConfig. Mirrors the two sources the
-- choice lists are built from (see TT:GetTooltipFontChoices and siblings):
-- the builtin tables in textures.lua plus the LibSharedMedia registry when it
-- is present. Accepts a path or a display name, like the render-time resolver
-- (resolveConfiguredMediaValue) does. It cannot reuse the choice getters:
-- they are defined further down this file and do not exist yet when the first
-- load sanitizes.
local mediaBuiltinTableName = {
    tooltip_font = "builtinTooltipFonts",
    tooltip_bar_texture = "builtinStatusBarTextures",
    tooltip_background_texture = "builtinTooltipBackgrounds",
    tooltip_border_texture = "builtinTooltipBorders",
}
local mediaSharedMediaType = {
    tooltip_font = "font",
    tooltip_bar_texture = "statusbar",
    tooltip_background_texture = "background",
    tooltip_border_texture = "border",
}

local function isKnownMediaValue(settingKey, value)
    if (type(value) ~= "string" or value == "") then
        return false
    end
    local builtins = TT[mediaBuiltinTableName[settingKey]]
    if (type(builtins) == "table") then
        for _, entry in ipairs(builtins) do
            if (entry.value == value or entry.text == value) then
                return true
            end
        end
    end
    if (LibStub) then
        local okLib, media = pcall(LibStub, "LibSharedMedia-3.0", true)
        if (okLib and type(media) == "table") then
            local mediaType = mediaSharedMediaType[settingKey]
            if (type(media.HashTable) == "function") then
                local okTable, registered = pcall(media.HashTable, media, mediaType)
                if (okTable and type(registered) == "table") then
                    for name, path in pairs(registered) do
                        if (path == value or name == value) then
                            return true
                        end
                    end
                end
            elseif (type(media.List) == "function" and type(media.Fetch) == "function") then
                local okList, handles = pcall(media.List, media, mediaType)
                if (okList and type(handles) == "table") then
                    for _, handle in ipairs(handles) do
                        if (handle == value) then
                            return true
                        end
                        local okFetch, path = pcall(media.Fetch, media, mediaType, handle, true)
                        if (okFetch and path == value) then
                            return true
                        end
                    end
                end
            end
        end
    end
    return false
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

    -- The corrupt-saved-data ledger (final hardening pass).
    --
    -- A hand-edited TacoTipConfig must fail CLOSED (every repair below resets
    -- the key to its shipped default) and RECOVER to the defaults (it does).
    -- What it did not do was SAY so: a player whose settings had been repaired
    -- had no way to learn that one of their options had been silently reset.
    -- The number of repaired settings is counted and the first one is named;
    -- /tacotip diag reports both.
    --
    -- The count is from the LAST pass, not a running total: the sanitiser runs
    -- at load and again when the options page is built, and a corrupt key is
    -- repaired ONCE -- the second pass finds it already correct. A running
    -- total would therefore count the same repair twice.
    local repaired = 0
    local firstRepair = nil
    local function repair(key)
        repaired = repaired + 1
        if (not firstRepair) then
            firstRepair = tostring(key)
        end
    end

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
        "tooltip_background_use_class", "tooltip_portrait", "tooltip_portrait_3d",
        "tooltip_portrait_invert_side",
        "instant_fade", "anchor_mouse", "anchor_mouse_world",
        "anchor_mouse_spells", "unlock_info_position", "show_achievement_points",
        "show_honor_rank", "show_ilvl_inline", "show_realm",
        "show_role_icon", "show_separators", "scan"
    }
    for _, key in ipairs(booleanKeys) do
        local val = config[key]
        if (val ~= nil and type(val) ~= "boolean") then
            repair(key)
            config[key] = defaults[key]
        end
    end

    -- Sanitise numeric slider/range keys so out-of-bounds values from
    -- corruption or old versions do not cause layout or logic issues.
    if (type(config.class_icon_size) ~= "number" or config.class_icon_size < 8 or config.class_icon_size > 32) then
        repair("class_icon_size")
        config.class_icon_size = defaults.class_icon_size
    end
    if (type(config.tooltip_portrait_scale) ~= "number" or config.tooltip_portrait_scale < 0.5 or config.tooltip_portrait_scale > 2) then
        repair("tooltip_portrait_scale")
        config.tooltip_portrait_scale = defaults.tooltip_portrait_scale
    end
    if (type(config.tooltip_portrait_zoom) ~= "number"
            or config.tooltip_portrait_zoom < TT.TooltipPortraitZoomRange.min
            or config.tooltip_portrait_zoom > TT.TooltipPortraitZoomRange.max) then
        repair("tooltip_portrait_zoom")
        config.tooltip_portrait_zoom = TT.TooltipPortraitZoomDefault
    end
    if (type(config.tooltip_font_size) ~= "number" or config.tooltip_font_size < 8 or config.tooltip_font_size > 20) then
        repair("tooltip_font_size")
        config.tooltip_font_size = defaults.tooltip_font_size
    end
    if (type(config.tooltip_border_edge_size) ~= "number" or config.tooltip_border_edge_size < 4 or config.tooltip_border_edge_size > 48) then
        repair("tooltip_border_edge_size")
        config.tooltip_border_edge_size = defaults.tooltip_border_edge_size
    end
    if (type(config.tooltip_border_alpha) ~= "number" or config.tooltip_border_alpha < 0 or config.tooltip_border_alpha > 1) then
        repair("tooltip_border_alpha")
        config.tooltip_border_alpha = defaults.tooltip_border_alpha
    end
    if (type(config.tooltip_background_alpha) ~= "number" or config.tooltip_background_alpha < 0 or config.tooltip_background_alpha > 1) then
        repair("tooltip_background_alpha")
        config.tooltip_background_alpha = defaults.tooltip_background_alpha
    end
    if (type(config.tip_style) ~= "number" or config.tip_style < 1 or config.tip_style > 5) then
        repair("tip_style")
        config.tip_style = defaults.tip_style
    end


    if (type(config.tooltip_delay) ~= "number" or config.tooltip_delay < 0 or config.tooltip_delay > 5) then
        repair("tooltip_delay")
        config.tooltip_delay = defaults.tooltip_delay
    end
    if (type(config.tooltip_max_width) ~= "number" or config.tooltip_max_width < 0 or config.tooltip_max_width > 500) then
        repair("tooltip_max_width")
        config.tooltip_max_width = defaults.tooltip_max_width
    end
    if (config.tooltip_border_texture == "Tooltip enlarged" or config.tooltip_border_texture == nil) then
        repair("tooltip_border_texture")
        config.tooltip_border_texture = defaults.tooltip_border_texture
    end
    -- Fixed-string allowlists for the remaining free-text keys. The slash path
    -- only ever writes the five cycled literals for custom_anchor
    -- (options.lua:441-459), but a hand-edited SavedVariables value bypasses
    -- it and reaches tooltip:SetPoint, which raises from a hooksecurefunc
    -- post-hook (main.lua:2916-2917). Reset anything else to the default.
    -- Media keys are validated against the same two sources the choice lists
    -- are built from (builtin tables + LibSharedMedia registry), so a value
    -- the UI could have offered always survives; anything else resets,
    -- matching the render-time fallback instead of diverging from it.
    if (config.custom_anchor ~= "TOPLEFT" and config.custom_anchor ~= "TOPRIGHT"
            and config.custom_anchor ~= "BOTTOMLEFT" and config.custom_anchor ~= "BOTTOMRIGHT"
            and config.custom_anchor ~= "CENTER") then
        repair("custom_anchor")
        config.custom_anchor = defaults.custom_anchor
    end
    -- custom_pos shape: the drag-stop write (main.lua onDragButtonDragStop) is
    -- the only in-addon writer and always writes {point, point, number,
    -- number}, but an old GetPoint-bug save can carry nils and a hand-edited
    -- SavedVariables value bypasses every writer. Either shape reaches
    -- tooltip:SetPoint unvalidated (syncTooltipMoverPosition is raw), which
    -- raises -- from a hooksecurefunc post-hook that swallows it and leaves
    -- the tooltip anchorless. Repair to nil (absent = Blizzard placement),
    -- never to a guessed position.
    local pos = config.custom_pos
    if (pos ~= nil) then
        local posOk = type(pos) == "table"
            and (pos[1] == "TOPLEFT" or pos[1] == "TOPRIGHT"
                or pos[1] == "BOTTOMLEFT" or pos[1] == "BOTTOMRIGHT"
                or pos[1] == "CENTER")
            and (pos[2] == "TOPLEFT" or pos[2] == "TOPRIGHT"
                or pos[2] == "BOTTOMLEFT" or pos[2] == "BOTTOMRIGHT"
                or pos[2] == "CENTER")
            and type(pos[3]) == "number" and type(pos[4]) == "number"
        if (not posOk) then
            repair("custom_pos")
            config.custom_pos = nil
        end
    end
    for _, mediaKey in ipairs({
        "tooltip_font", "tooltip_bar_texture",
        "tooltip_background_texture", "tooltip_border_texture",
    }) do
        if (not isKnownMediaValue(mediaKey, config[mediaKey])) then
            repair(mediaKey)
            config[mediaKey] = defaults[mediaKey]
        end
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
            repair(key)
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
            repair(key)
            config[key] = defaults[key]
        end
    end

    -- Publish the ledger. Read-only for the config itself: nothing above
    -- changes behaviour, this only counts what was changed.
    TT.ev = TT.ev or {}
    TT.ev.configRepairs = repaired
    TT.ev.lastConfigRepair = firstRepair
end

-- Whether this client can do an instant fade at all.
--
-- GameTooltip.FadeOut is an ENGINE method: it has no Lua definition on any
-- branch (a whole-tree sweep of origin/classic_era,
-- origin/classic_anniversary, origin/classic_titan, origin/forever and
-- origin/live finds none, and it is absent from the generated API docs on all
-- five), so "no Lua definition" is not evidence that it does not exist. The
-- evidence that it DOES exist on every supported client is Blizzard's own
-- call sites:
--   origin/classic_era, origin/classic_anniversary, origin/classic_titan:
--     Interface/AddOns/Blizzard_UnitFrame/Classic/UnitFrame.lua:447
--       GameTooltip:FadeOut();   (in UnitFrame_OnLeave)
--   origin/forever:
--     Interface/AddOns/Blizzard_UnitFrame/Mainline/UnitFrame.lua:393
--   origin/live:
--     Interface/AddOns/Blizzard_UnitFrame/Mainline/UnitFrame.lua:386
-- and on the Classic family UnitFrame_OnLeave is wired to the OnLeave of
-- PlayerFrame.xml:374 and TargetFrame.xml:380 -- so the call runs every time
-- the mouse leaves the player or target frame. If the method did not exist
-- there, every unit frame would raise on mouse-out.
--
-- So the check below is a RUNTIME capability probe, not a client-family
-- table: on a client that genuinely has no GameTooltip.FadeOut the option has
-- nothing to act on, so it is offered but DISABLED and explained, rather than
-- left settable and silently inert. On every supported client the method is
-- present and nothing changes.
local function instantFadeSupported()
    return (GameTooltip and type(GameTooltip.FadeOut) == "function") and true or false
end

local function updateInstantFadeState(enabled)
    if (TT.frame) then
        if (enabled) then
            TT.frame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
        else
            TT.frame:UnregisterEvent("UPDATE_MOUSEOVER_UNIT")
        end
    end
    if (not instantFadeSupported()) then
        -- The client cannot fade instantly. Recorded as "unsupported" so
        -- /tacotip diag says the client CANNOT do it, not merely that the
        -- option is off.
        TT.InstantFadeMode = "unsupported"
        return
    end
    if (enabled) then
        -- Secure post-hook, never a method replacement (see main.lua
        -- GameMenu-quit taint fix). Preserves GameTooltip.FadeOut identity;
        -- Hide-after-fade reads as instant. Toggle and default (off) unchanged.
        Detours:SecureHook(TT, GameTooltip, "FadeOut", function(tooltipFrame)
            -- runUntainted: a hooksecurefunc post-hook does not replace the
            -- hooked function, but its BODY still runs as addon code inside the
            -- caller's script chain -- here the unit frame's OnLeave
            -- (Blizzard_UnitFrame/Classic/UnitFrame.lua:447
            -- `GameTooltip:FadeOut();`). Uncontained, that taints the unit
            -- frame, and the taint reaches the game menu. main.lua's twin of
            -- this hook carries the same guard.
            return runUntainted(safeCall, function()
                if (TacoTipConfig and TacoTipConfig.instant_fade and tooltipFrame) then
                    tooltipFrame:Hide()
                end
            end)
        end)
        TT.InstantFadeMode = "secure-hook"
    else
        Detours:SecureUnhook(TT, GameTooltip, "FadeOut")
        TT.InstantFadeMode = "standard-fade"
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
    -- Keep the live inspector in step with the restored default (enabled), so
    -- the checkbox and the running scan cannot disagree after a reset.
    applyScanSetting(TacoTipConfig.scan ~= false)
    -- Invalidated here, at the choke point, because the two reset routes do NOT
    -- agree: the reset button goes on to call RefreshOptionsUI -> modernGetConfig
    -- (which invalidates), while /tacotip reset only refreshes the root page. So
    -- the memoised font/bar/background/border stayed applied for the rest of the
    -- session after a slash-command reset.
    if (TT.InvalidateResolvedMediaCache) then
        TT:InvalidateResolvedMediaCache()
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
    -- Push the saved proximity-scan preference to the live inspector now.
    -- options.lua loads after the library but before main.lua, so this is what
    -- makes "off" survive a /reload instead of reverting to the library's own
    -- default. nil (a configuration saved before this option existed) means
    -- enabled, which leaves existing installs unchanged.
    applyScanSetting(TacoTipConfig.scan ~= false)
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
            -- The confirmation used to print ONLY when there was nothing to
            -- disable, and stayed silent in the case where a custom position
            -- really was cleared -- so the message was exactly inverted
            -- relative to the effect. The text describes the RESULTING state,
            -- so it is true either way: print it once, after the reset. This
            -- also matches the bootstrap handler in gearscore.lua, which has
            -- always printed it unconditionally.
            --
            -- The mover call is protected and counted: a raising _Disable used
            -- to abort the whole command before the configuration was reset,
            -- leaving the position custom and saying nothing.
            if (TacoTipDragButton and TacoTipDragButton._Disable) then
                if (not pcall(TacoTipDragButton._Disable, TacoTipDragButton, true)) then
                    TT.ev = TT.ev or {}
                    TT.ev.moverDisableFailed = (TT.ev.moverDisableFailed or 0) + 1
                    print("|cff59f0dcTacoTip:|r The tooltip mover could not be disabled.")
                end
            end
            TacoTipConfig.custom_pos = nil
            print("|cff59f0dcTacoTip:|r " .. L["Custom tooltip position disabled."])
        elseif (cmd == "reset") then
            resetCfg()
            if (optionsFrame and optionsFrame:IsShown() and optionsFrame.Refresh) then
                optionsFrame:Refresh()
            end
            print("|cff59f0dcTacoTip:|r " .. L["Configuration has been reset to default."])
        elseif (cmd == "save") then
            if (TacoTipDragButton and TacoTipDragButton.IsShown and TacoTipDragButton:IsShown()) then
                -- The save call is protected and counted: a raising _Save used
                -- to abort the command with the position silently unsaved.
                if (not pcall(TacoTipDragButton._Save, TacoTipDragButton)) then
                    TT.ev = TT.ev or {}
                    TT.ev.moverSaveFailed = (TT.ev.moverSaveFailed or 0) + 1
                    print("|cff59f0dcTacoTip:|r The tooltip position could not be saved.")
                end
            else
                -- The command was typed and NOTHING happened. Say so, in the
                -- same words the bootstrap handler in gearscore.lua uses, so
                -- the command is not a dead end. Counted, and surfaced in
                -- /tacotip diag.
                TT.ev = TT.ev or {}
                TT.ev.moverSaveSkipped = (TT.ev.moverSaveSkipped or 0) + 1
                print("|cff59f0dcTacoTip:|r Tooltip mover is not currently shown.")
            end
        elseif (cmd == "help") then
            print("|cff59f0dcTacoTip:|r /tacotip - open TacoTip options")
            print("|cff59f0dcTacoTip:|r /tacotip custom - show the tooltip mover")
            print("|cff59f0dcTacoTip:|r /tacotip reset - reset TacoTip settings")
            print("|cff59f0dcTacoTip:|r " .. L["TEXT_HELP_ANCHOR"])
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
        elseif (cmd == "diag" or cmd == "diagnostics") then
            -- Load report. Exists because the mover and the tooltip pipeline are
            -- both defined at the very end of main.lua, so a single load-time
            -- error disables them while leaving the options frame fully
            -- functional -- a state that is otherwise impossible to explain from
            -- the UI. See TT:PrintDiagnostics in main.lua.
            if (TT and TT.PrintDiagnostics) then
                TT:PrintDiagnostics()
            else
                print("|cff59f0dcTacoTip:|r main.lua did not finish loading, so diagnostics are unavailable.")
                print("|cff59f0dcTacoTip:|r Enable a Lua error handler (BugSack/Swatter) and /reload.")
            end
        elseif (TT and TT.ForwardExtrasSlashCommand and TT.ForwardExtrasSlashCommand(cmd)) then
            -- TacoTip Extras owns the leaderboard sub-commands ("/tt lb" and
            -- friends). Forwarded BEFORE the options-panel fallback, so the
            -- leaderboard opens instead of the settings page. The resolver
            -- lives in gearscore.lua (one implementation, shared with the
            -- bootstrap handler) and returns false when the Extras is not
            -- loaded, which leaves the behaviour below exactly as it was.
            return
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

-- Options load-leg ledger (hunter H-NEW2): the six LoadAddOn probes below
-- used to vanish on failure, leaving the options panel missing with zero
-- diag. Failures are counted (TT.ev.optionsLoadFailures) with the last
-- error kept (TT.ev.lastOptionsLoadError) and surfaced in
-- reportSilentFailures problems[]. _G.LoadAddOn is read at call time, never
-- captured, so a late loader (and the harness forced-failure pin) is seen.
local function noteOptionsLoadFailure(which, ok, result)
    if (ok and result) then
        return true
    end
    if (TT) then
        TT.ev = TT.ev or {}
        TT.ev.optionsLoadFailures = (TT.ev.optionsLoadFailures or 0) + 1
        local why = (not ok) and tostring(result) or "returned falsy"
        TT.ev.lastOptionsLoadError = "LoadAddOn " .. tostring(which) .. " (" .. why .. ")"
    end
    return false
end

-- Which of the six LoadAddOn targets exist on which client family.
--
-- A target that does not exist on the detected client is NOT APPLICABLE: it
-- can only fail, and counting that failure would put a false "options load
-- failures" entry in /tacotip diag for an addon that was never meant to be on
-- that client. A target that IS applicable and fails to load is a real
-- failure: it still counts and still surfaces.
--
-- Mirror evidence (branch-qualified; the `Interface/AddOns/` directory
-- listing of each branch, `git ls-tree -d origin/<branch>:Interface/AddOns`):
--   origin/classic_era, origin/classic_anniversary, origin/classic_titan:
--     Blizzard_Settings                    ABSENT
--     Blizzard_Settings_Shared             PRESENT
--     Blizzard_SettingsDefinitions         ABSENT
--     Blizzard_SettingsDefinitions_Shared  PRESENT
--     Blizzard_OptionsUI                   ABSENT
--     Blizzard_InterfaceOptions            ABSENT
--   origin/forever, origin/live:
--     Blizzard_Settings                    PRESENT
--     Blizzard_Settings_Shared             PRESENT
--     Blizzard_SettingsDefinitions         ABSENT
--     Blizzard_SettingsDefinitions_Shared  PRESENT
--     Blizzard_OptionsUI                   ABSENT
--     Blizzard_InterfaceOptions            ABSENT
--
-- The family is "unknown" on a client the library could not identify. There
-- every target is treated as applicable, so a genuine failure is reported
-- rather than silently swallowed.
local OPTIONS_LOAD_ABSENT_ON = {
    ["Blizzard_Settings"] = {
        classicEra = true, tbc = true, titanforge = true,
    },
    ["Blizzard_Settings_Shared"] = {},
    ["Blizzard_SettingsDefinitions"] = {
        classicEra = true, tbc = true, titanforge = true, forever = true, retail = true,
    },
    ["Blizzard_SettingsDefinitions_Shared"] = {},
    ["Blizzard_OptionsUI"] = {
        classicEra = true, tbc = true, titanforge = true, forever = true, retail = true,
    },
    ["Blizzard_InterfaceOptions"] = {
        classicEra = true, tbc = true, titanforge = true, forever = true, retail = true,
    },
}

local function optionsLoadTargetApplicable(which)
    local family = CI and CI.family or nil
    if (not family or family == "unknown") then
        return true
    end
    local absent = OPTIONS_LOAD_ABSENT_ON[which]
    if (not absent) then
        return true
    end
    return not absent[family]
end

local function optionsLoadAddOn(which)
    if (not optionsLoadTargetApplicable(which)) then
        -- Not applicable on this client: not a failure, and not worth a call.
        return true
    end
    local loadFn = _G.LoadAddOn
    if (not loadFn) then
        return noteOptionsLoadFailure(which, true, nil)
    end
    local ok, result = pcall(loadFn, which)
    return noteOptionsLoadFailure(which, ok, result)
end

local function ensureSettingsUI()
    if (_G.Settings and _G.Settings.RegisterCanvasLayoutCategory and _G.Settings.RegisterAddOnCategory) then
        return true
    end
    if (_G.LoadAddOn) then
        -- "Blizzard_Settings" / "Blizzard_SettingsDefinitions" only exist on
        -- the modern pair. The Classic clients (and Forever) ship
        -- Blizzard_Settings_Shared and Blizzard_SettingsDefinitions_Shared
        -- instead, and all of these are already non-LoadOnDemand, so this is
        -- belt-and-braces rather than a hard requirement.
        --
        -- Which of the six targets is even ATTEMPTED is decided by
        -- OPTIONS_LOAD_ABSENT_ON above: a target that does not exist on this
        -- client is skipped, not attempted and counted as a failure.
        optionsLoadAddOn("Blizzard_Settings")
        optionsLoadAddOn("Blizzard_Settings_Shared")
        optionsLoadAddOn("Blizzard_SettingsDefinitions")
        optionsLoadAddOn("Blizzard_SettingsDefinitions_Shared")
    end
    return _G.Settings and _G.Settings.RegisterCanvasLayoutCategory and _G.Settings.RegisterAddOnCategory
end

local function registerSettingsSubcategories()
    if (settingsSubcategoriesRegistered or not addOnOptionsCategory or not _G.Settings or not _G.Settings.RegisterCanvasLayoutSubcategory) then
        return settingsSubcategoriesRegistered
    end

    -- Narrow pcalls (hunter H7): one guard per subcategory so a raise names
    -- the failing child instead of swallowing all three into one boolean.
    local specs = {
        { key = "tooltips", page = optionsPages.tooltips },
        { key = "positioning", page = optionsPages.positioning },
        { key = "characterInspect", page = optionsPages.characterInspect },
    }
    local allOk = true
    for _, spec in ipairs(specs) do
        if (not modernSubcategories[spec.key]) then
            local okSub, sub = pcall(_G.Settings.RegisterCanvasLayoutSubcategory,
                addOnOptionsCategory, spec.page, spec.page.name)
            if (okSub and sub) then
                modernSubcategories[spec.key] = sub
            else
                allOk = false
                if (not okSub) then
                    recordOptionsRegFailure("settings subcategory " .. spec.key, sub)
                end
            end
        end
    end

    if (allOk and modernSubcategories.tooltips and modernSubcategories.positioning and
        modernSubcategories.characterInspect) then
        settingsSubcategoriesRegistered = true
    end
    return settingsSubcategoriesRegistered
end

local function registerLegacyChildCategories()
    if (legacyChildCategoriesRegistered or not InterfaceOptions_AddCategory) then
        return legacyChildCategoriesRegistered
    end

    -- Narrow pcalls (hunter H7): one guard per child page.
    local specs = {
        { key = "tooltips", page = optionsPages.tooltips },
        { key = "positioning", page = optionsPages.positioning },
        { key = "characterInspect", page = optionsPages.characterInspect },
    }
    local allOk = true
    for _, spec in ipairs(specs) do
        local okChild, errChild = pcall(InterfaceOptions_AddCategory, spec.page)
        if (not okChild) then
            allOk = false
            recordOptionsRegFailure("legacy child " .. spec.key, errChild)
        end
    end

    if (allOk) then
        legacyChildCategoriesRegistered = true
    end
    return legacyChildCategoriesRegistered
end

local function registerOptionsCategory()
    local registeredAny = false

    -- Narrow pcalls (hunter H7): the settings probe, the category pair and
    -- the legacy pair are guarded separately so a raise names the step.
    local okEnsure, canSettings = pcall(ensureSettingsUI)
    if (not okEnsure) then
        recordOptionsRegFailure("settings UI probe", canSettings)
        canSettings = false
    end
    if (not settingsCategoryRegistered and canSettings) then
        local okCat, errCat = pcall(function()
            addOnOptionsCategory = addOnOptionsCategory or
                _G.Settings.RegisterCanvasLayoutCategory(optionsFrame, optionsFrame.name)
            if (addOnOptionsCategory) then
                _G.Settings.RegisterAddOnCategory(addOnOptionsCategory)
                settingsCategoryRegistered = true
                registeredAny = true
            end
        end)
        if (not okCat) then
            recordOptionsRegFailure("settings category", errCat)
        end
    end

    if (settingsCategoryRegistered) then
        registerSettingsSubcategories()
    end

    if (not InterfaceOptions_AddCategory and _G.LoadAddOn) then
        optionsLoadAddOn("Blizzard_OptionsUI")
        optionsLoadAddOn("Blizzard_InterfaceOptions")
    end

    if (not legacyCategoryRegistered and InterfaceOptions_AddCategory) then
        local okLeg, errLeg = pcall(InterfaceOptions_AddCategory, optionsFrame)
        if (not okLeg) then
            recordOptionsRegFailure("legacy category", errLeg)
        else
            legacyCategoryRegistered = true
            registeredAny = true
        end
    end

    if (legacyCategoryRegistered) then
        registerLegacyChildCategories()
    end

    return registeredAny or settingsCategoryRegistered or legacyCategoryRegistered
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

-- Record one failed attempt to open the options panel.
--
-- The three protected calls below used to DISCARD their results, so a raising
-- one aborted the open with nothing said and nothing counted: the player
-- typed /tacotip, no panel appeared, and the add-on could not say why. The
-- result is captured, the failure is counted, and the player is told in one
-- plain chat line. The counter and the last error are surfaced by
-- /tacotip diag.
local function noteOptionsPanelFailure(which, err)
    TT.ev = TT.ev or {}
    TT.ev.optionsPanelOpenFailed = (TT.ev.optionsPanelOpenFailed or 0) + 1
    TT.ev.lastOptionsPanelError = tostring(which) .. ": " .. tostring(err)
    print("|cff59f0dcTacoTip:|r The options panel could not be opened ("
        .. tostring(which) .. ").")
end

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
        -- The fallback (open by NAME) discarded its result, so a raising call
        -- aborted the open with no panel and no message.
        local ok, err = pcall(_G.Settings.OpenToCategory, optionsFrame.name)
        if (not ok) then
            noteOptionsPanelFailure("Settings.OpenToCategory", err)
        end
        return
    end
    if (legacyCategoryRegistered and InterfaceOptionsFrame_OpenToCategory) then
        -- The Show call is a convenience: OpenToCategory shows the panel
        -- itself, so its failure is counted but does not by itself mean the
        -- panel failed to open.
        if (_G.InterfaceOptionsFrame_Show) then
            local showOK, showErr = pcall(_G.InterfaceOptionsFrame_Show)
            if (not showOK) then
                TT.ev = TT.ev or {}
                TT.ev.optionsPanelShowFailed = (TT.ev.optionsPanelShowFailed or 0) + 1
                TT.ev.lastOptionsPanelError = "InterfaceOptionsFrame_Show: "
                    .. tostring(showErr)
            end
        end
        local ok, err = pcall(InterfaceOptionsFrame_OpenToCategory, optionsFrame)
        if (not ok) then
            noteOptionsPanelFailure("InterfaceOptionsFrame_OpenToCategory", err)
        end
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

function TT:GetResolvedTooltipFont()
    if (not cachedResolvedFont) then
        cachedResolvedFont = resolveConfiguredMediaValue(self:GetTooltipFontChoices(),
            TacoTipConfig and TacoTipConfig.tooltip_font,
            "Fonts\\FRIZQT__.TTF")
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
    -- Absent or out-of-range setting: the SHIPPED default, which is the single
    -- source of truth in DEFAULTS above. It was a literal 16 here, which
    -- disagreed with the default the profile actually resolves to (20) and with
    -- the description string the player reads.
    return DEFAULTS.tooltip_border_edge_size
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
    -- runUntainted: this writes to the SHARED GameTooltip from inside the
    -- options panel's own frame script chain. Containment keeps the shared
    -- tooltip -- the frame the game menu's buttons anchor to -- free of the
    -- taint this write would otherwise carry. The payload is called through
    -- safeCall so a raise is still REPORTED (geterrorhandler) instead of
    -- being swallowed by the containment.
    return runUntainted(safeCall, function()
        GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        if (title and title ~= "") then
            GameTooltip:SetText(title, 1, 0.82, 0)
            GameTooltip:AddLine(text, 1, 1, 1, true)
        else
            GameTooltip:SetText(text, 1, 1, 1, 1)
        end
        GameTooltip:Show()
    end)
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
            return runUntainted(safeCall, function()
                GameTooltip:Hide()
            end)
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

    pickerFrame = frame
    return pickerFrame
end

local function toggleMediaPicker(dropDown)
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
        if (type(val) == "string" and val:len() > 0) then
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

    local btnName = globalName .. "Button"
    local arrowButton = _G[btnName]
    if (arrowButton) then
        arrowButton:SetScript("OnClick", function()
            toggleMediaPicker(dropDown)
        end)
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

local function buildRootPage()
    if (modernOptionsState.pages.rootBuilt) then
        return
    end

    local panel = optionsFrame
    local controls = modernOptionsState.controls
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(addOnTitle .. " v" .. addOnVersion)

    local description = createWrappedText(panel, "GameFontHighlightSmall", 620,
        L["OPTIONS_ROOT_DESCRIPTION"] or L["TEXT_OPT_DESC"])
    description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)

    local quickActions = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    quickActions:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -18)
    quickActions:SetText(L["OPTIONS_ROOT_QUICK_ACTIONS"] or "Quick Actions")

    local openMoverButton = createOptionsButton(panel, nil, L["OPTIONS_OPEN_TOOLTIP_MOVER"] or L["Mover"], 180, 24,
        function()
            showTooltipMover()
        end,
        L["OPTIONS_OPEN_TOOLTIP_MOVER_DESC"] or
        "Show the live tooltip mover so you can drag and save a custom tooltip position.")
    openMoverButton:SetPoint("TOPLEFT", quickActions, "BOTTOMLEFT", 0, -8)

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
            L["OPTIONS_ROOT_PAGE_HINT"] or "Use the child pages in the AddOns tree to configure TacoTip.",
            "|cff59f0dc•|r " .. string.format(L["OPTIONS_STATUS_LANGUAGE"] or "Addon language: %s.", localeSummary),
            "|cff59f0dc•|r " .. tooltipMode,
            "|cff59f0dc•|r " ..
            (TacoTipConfig.show_gs_character and (L["OPTIONS_STATUS_CHARACTER_GS_ON"] or "Character and inspect GearScore overlays are enabled.") or (L["OPTIONS_STATUS_CHARACTER_GS_OFF"] or "Character and inspect GearScore overlays are disabled.")),
            "|cff59f0dc•|r " ..
            (TacoTipConfig.show_avg_ilvl and (L["OPTIONS_STATUS_CHARACTER_ILVL_ON"] or "Average item level overlays are enabled.") or (L["OPTIONS_STATUS_CHARACTER_ILVL_OFF"] or "Average item level overlays are disabled.")),
            "|cff59f0dc•|r " ..
            (TacoTipConfig.unlock_info_position and (L["OPTIONS_STATUS_OVERLAYS_UNLOCKED"] or "Overlay drag movers are unlocked.") or (L["OPTIONS_STATUS_OVERLAYS_LOCKED"] or "Overlay drag movers are locked."))
        }
        return table.concat(lines, "\n")
    end

    controls.rootStyleChoice = createOptionsDropdown(panel, nil, L["Tooltip Style"],
        L["OPTIONS_TOOLTIP_STYLE_DESC"] or
        "Choose how much detail TacoTip shows by default.",
        modernStyleOptions, function(value)
            TacoTipConfig.tip_style = value
            if (TT and TT.RefreshOptionsUI) then
                TT:RefreshOptionsUI()
            end
        end)
    controls.rootStyleChoice.label:SetPoint("TOPLEFT", openMoverButton, "BOTTOMLEFT", 0, -18)
    controls.rootStyleChoice:SetPoint("TOPLEFT", controls.rootStyleChoice.label, "BOTTOMLEFT", -16, -2)
    if (controls.rootStyleChoice.description) then
        controls.rootStyleChoice.description:ClearAllPoints()
        controls.rootStyleChoice.description:SetPoint("TOPLEFT", controls.rootStyleChoice, "BOTTOMLEFT", 20, -2)
    end

    local styleBottom = controls.rootStyleChoice.description or controls.rootStyleChoice
    modernOptionsState.rootSummary = createWrappedText(panel, "GameFontHighlightSmall", 620, getRootSummaryText())
    modernOptionsState.rootSummary:SetPoint("TOPLEFT", styleBottom, "BOTTOMLEFT",
        controls.rootStyleChoice.description and -20 or 0, -12)

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
    controls.rootLanguage.label:SetPoint("TOPLEFT", modernOptionsState.rootSummary, "BOTTOMLEFT", 0, -16)
    controls.rootLanguage:SetPoint("TOPLEFT", controls.rootLanguage.label, "BOTTOMLEFT", -16, -2)
    if (controls.rootLanguage.description) then
        controls.rootLanguage.description:ClearAllPoints()
        controls.rootLanguage.description:SetPoint("TOPLEFT", controls.rootLanguage, "BOTTOMLEFT", 20, -2)
    end

    local behaviorHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    local langBottom = controls.rootLanguage.description or controls.rootLanguage
    behaviorHeader:SetPoint("TOPLEFT", langBottom, "BOTTOMLEFT", controls.rootLanguage.description and -20 or 0, -16)
    behaviorHeader:SetText(L["OPTIONS_ROOT_BEHAVIOR_HEADER"] or "Behavior & client settings")

    controls.rootHideInCombat = createOptionsCheckbox(panel, nil,
        L["OPTIONS_HIDE_IN_COMBAT_LABEL"] or "Suppress inspection details in combat",
        L["OPTIONS_HIDE_IN_COMBAT_DESC"] or
        "Skips TacoTip's talents and GearScore-style player additions while you are in combat.", function(_, value)
            TacoTipConfig.hide_in_combat = value
        end)
    controls.rootHideInCombat:SetPoint("TOPLEFT", behaviorHeader, "BOTTOMLEFT", -2, -8)

    controls.rootUberTips = createOptionsCheckbox(panel, nil, L["Enhanced Tooltips"], L["TEXT_OPT_UBERTIPS"],
        function(_, value)
            SetCVar("UberTooltips", value and "1" or "0")
        end)
    controls.rootUberTips:SetPoint("TOPLEFT", behaviorHeader, "BOTTOMLEFT", 310, -8)

    controls.rootChatClassColors = createOptionsCheckbox(panel, nil, L["Chat Class Colors"],
        L["Color names by class in chat windows"], function(_, value)
            SetCVar("chatClassColorOverride", value and "0" or "1")
        end)
    controls.rootChatClassColors:SetPoint("TOPLEFT", controls.rootHideInCombat, "BOTTOMLEFT", 0, -8)

    controls.rootShowAchievementPoints = createOptionsCheckbox(panel, nil, L["Show Achievement Points"],
        L["OPTIONS_ACHIEVEMENT_DESC"] or "Display player's total achievement points.",
        function(_, value)
            TacoTipConfig.show_achievement_points = value
        end)
    controls.rootShowAchievementPoints:SetPoint("TOPLEFT", controls.rootUberTips, "BOTTOMLEFT", 0, -8)

    panel.Refresh = function()
        modernOptionsState.rootSummary:SetText(getRootSummaryText())
        controls.rootLanguage:SetValues(buildLocaleDropdownChoices())
        controls.rootLanguage:SetValue(getSavedLocaleOverride() or CLIENT_DEFAULT_LOCALE_VALUE)
        controls.rootStyleChoice:SetValue(TacoTipConfig.tip_style or 2)
        controls.rootHideInCombat:SetChecked(TacoTipConfig.hide_in_combat)
        controls.rootUberTips:SetChecked(GetCVar("UberTooltips") == "1")
        controls.rootChatClassColors:SetChecked(GetCVar("chatClassColorOverride") == "0")
        local hasAchievements = CI and
            ((CI.IsWotlk and CI:IsWotlk()) or (CI.IsRetail and CI:IsRetail()) or (CI.IsForever and CI:IsForever()))
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
        L["OPTIONS_TOOLTIPS_PAGE_DESC"] or "Tune the information TacoTip adds to player and item tooltips.", 360)
    builder:AddAnchor(header, 24)
    if (headerDesc) then
        builder:AddAnchor(headerDesc, headerDesc:GetStringHeight() + 8)
    end

    local controls = modernOptionsState.controls
    controls.styleChoice = createOptionsDropdown(content, nil, L["Tooltip Style"],
        L["OPTIONS_TOOLTIP_STYLE_DESC"] or
        "Choose how much detail TacoTip shows by default.",
        modernStyleOptions, function(value)
            TacoTipConfig.tip_style = value
        end)
    builder.y = builder.y - layoutDropdownControl(content, controls.styleChoice, builder.y, 12)

    local unitHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    unitHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 16, builder.y)
    unitHeader:SetText(L["OPTIONS_SECTION_UNIT_TOOLTIPS"] or "Unit tooltip content")
    builder.y = builder.y - 24

    controls.useClassColors = createOptionsCheckbox(content, nil, L["Class Color"], L["Color class names in tooltips"],
        function(_, value)
            TacoTipConfig.color_class = value
        end)
    controls.useClassColors:SetPoint("TOPLEFT", content, "TOPLEFT", 14, builder.y)
    controls.shamanBlue = createOptionsCheckbox(content, nil, L["OPTIONS_SHAMAN_BLUE"] or "Shaman Blue",
        L["OPTIONS_SHAMAN_BLUE_DESC"] or "Use blue instead of pink for Shaman class color.",
        function(_, value)
            TacoTipConfig.shaman_blue = value
        end)
    controls.shamanBlue:SetPoint("TOPLEFT", content, "TOPLEFT", 234, builder.y)
    builder.y = builder.y - 30

    controls.showTitles = createOptionsCheckbox(content, nil, L["Title"], L["Show player's title in tooltips"],
        function(_, value)
            TacoTipConfig.show_titles = value
        end)
    controls.showTitles:SetPoint("TOPLEFT", content, "TOPLEFT", 14, builder.y)
    controls.showGuildNames = createOptionsCheckbox(content, nil, L["Guild Name"], L["Show guild name in tooltips"],
        function(_, value)
            TacoTipConfig.show_guild_name = value
            modernGetConfig()
        end)
    controls.showGuildNames:SetPoint("TOPLEFT", content, "TOPLEFT", 234, builder.y)
    builder.y = builder.y - 30

    controls.showGuildRanks = createOptionsCheckbox(content, nil, L["Guild Rank"], L["Show guild rank in tooltips"],
        function(_, value)
            TacoTipConfig.show_guild_rank = value
            modernGetConfig()
        end)
    controls.showGuildRanks:SetPoint("TOPLEFT", content, "TOPLEFT", 14, builder.y)
    builder.y = builder.y - 30

    controls.guildRankStyleChoice = createOptionsDropdown(content, nil, L["Style"],
        L["OPTIONS_GUILD_STYLE_DESC"] or
        "Choose how TacoTip formats guild rank when both guild name and guild rank are shown.", {
            { value = 1, text = string.format(L["OPTIONS_GUILD_STYLE_ONE"] or L["FORMAT_GUILD_RANK_1"], L["Guild"], L["Rank"]) },
            { value = 2, text = L["OPTIONS_GUILD_STYLE_TWO"] or string.format("<%s> (%s)", L["Guild"], L["Rank"]) }
        }, function(value)
            TacoTipConfig.guild_rank_alt_style = (value == 2)
        end)
    builder.y = builder.y - layoutDropdownControl(content, controls.guildRankStyleChoice, builder.y)

    controls.showTalents = createOptionsCheckbox(content, nil, L["Talents"],
        L["Show talents and specialization in tooltips"],
        function(_, value)
            TacoTipConfig.show_talents = value
        end)
    controls.showTalents:SetPoint("TOPLEFT", content, "TOPLEFT", 14, builder.y)
    controls.showTarget = createOptionsCheckbox(content, nil, L["Target"], L["Show unit's target in tooltips"],
        function(_, value)
            TacoTipConfig.show_target = value
        end)
    controls.showTarget:SetPoint("TOPLEFT", content, "TOPLEFT", 234, builder.y)
    builder.y = builder.y - 30

    controls.gearScorePlayer = createOptionsCheckbox(content, nil, L["OPTIONS_SHOW_PLAYER_GS"] or "Show player GearScore",
        L["OPTIONS_SHOW_PLAYER_GS_DESC"] or
        "Adds GearScore to player tooltips. Wide and mini layouts also show average item level on that line.",
        function(_, value)
            TacoTipConfig.show_gs_player = value
        end)
    controls.gearScorePlayer:SetPoint("TOPLEFT", content, "TOPLEFT", 14, builder.y)
    controls.pawnScorePlayer = createOptionsCheckbox(content, nil, L["OPTIONS_SHOW_PLAYER_PAWN"] or "Show Pawn scores",
        L["OPTIONS_SHOW_PLAYER_PAWN_DESC"] or
        "Adds Pawn scores for inspected players when Pawn is installed. This may add extra item-cache work.",
        function(_, value)
            TacoTipConfig.show_pawn_player = value
        end)
    controls.pawnScorePlayer:SetPoint("TOPLEFT", content, "TOPLEFT", 234, builder.y)
    builder.y = builder.y - 30

    -- The only user-facing control for the background proximity scan, which
    -- issues inspection requests on its own. Wired to the library's public
    -- setter so unchecking it actually stops the requests instead of only
    -- hiding a checkbox.
    controls.scanNearby = createOptionsCheckbox(content, nil,
        "Scan nearby players",
        "Automatically inspect in-range players near you so their GearScore is collected without hovering over each one.",
        function(self, value)
            TacoTipConfig.scan = value
            local ok = applyScanSetting(value)
            -- The checkbox follows the library, not the request (hunter H7):
            -- on success the apply moved lib.scanEnabled to value, so reflect
            -- it; on failure the scan did not move and Refresh reconciles.
            if (ok and self and self.SetChecked) then
                local okLib, lib = pcall(LibStub, "LibForeverInspector", true)
                if (okLib and type(lib) == "table" and type(lib.scanEnabled) == "boolean") then
                    self:SetChecked(lib.scanEnabled)
                end
            end
        end)
    controls.scanNearby:SetPoint("TOPLEFT", content, "TOPLEFT", 14, builder.y)
    builder.y = builder.y - 30

    controls.showTeam = createOptionsCheckbox(content, nil, L["Faction Icon"],
        L["Show player's faction icon (Horde/Alliance) in tooltips"],
        function(_, value)
            TacoTipConfig.show_team = value
        end)
    controls.showTeam:SetPoint("TOPLEFT", content, "TOPLEFT", 14, builder.y)
    controls.showClassIcon = createOptionsCheckbox(content, nil, L["Class Icon"] or "Class Icon",
        "Show class icon badge at the top-right corner of player tooltips.",
        function(_, value)
            TacoTipConfig.show_class_icon = value
        end)
    controls.showClassIcon:SetPoint("TOPLEFT", content, "TOPLEFT", 234, builder.y)
    builder.y = builder.y - 30

    controls.classColoredBorderToggle = createOptionsCheckbox(content, nil,
        L["OPTIONS_BORDER_CLASS_COLOR"] or "Use class-colored border",
        L["OPTIONS_BORDER_CLASS_COLOR_DESC"] or
        "Tint the tooltip border with the player's class color when the tooltip is showing a player unit.",
        function(_, value)
            TacoTipConfig.tooltip_border_use_class = value
        end)
    controls.classColoredBorderToggle:SetPoint("TOPLEFT", content, "TOPLEFT", 14, builder.y)
    builder.y = builder.y - 30

    controls.showPVPIcon = createOptionsCheckbox(content, nil, L["PVP Icon"],
        L["Show player's pvp flag status as icon instead of text"],
        function(_, value)
            TacoTipConfig.show_pvp_icon = value
        end)
    controls.showPVPIcon:SetPoint("TOPLEFT", content, "TOPLEFT", 14, builder.y)
    controls.showHealthBar = createOptionsCheckbox(content, nil, L["Health Bar"],
        L["Show unit's health bar under tooltip"],
        function(_, value)
            TacoTipConfig.show_hp_bar = value
        end)
    controls.showHealthBar:SetPoint("TOPLEFT", content, "TOPLEFT", 234, builder.y)
    builder.y = builder.y - 30

    controls.showHonorRank = createOptionsCheckbox(content, nil, L["OPTIONS_SHOW_HONOR_RANK"] or "Show honor rank",
        L["OPTIONS_SHOW_HONOR_RANK_DESC"] or "Show the player's PvP rank title (Knight, Centurion, etc.) on the tooltip.",
        function(_, value)
            TacoTipConfig.show_honor_rank = value
        end)
    controls.showHonorRank:SetPoint("TOPLEFT", content, "TOPLEFT", 14, builder.y)
    controls.showRoleIcon = createOptionsCheckbox(content, nil, L["OPTIONS_SHOW_ROLE_ICON"] or "Show group role icon",
        L["OPTIONS_SHOW_ROLE_ICON_DESC"] or
        "Show Tank/Healer/DPS role icons on the name line for party and raid members.", function(_, value)
            TacoTipConfig.show_role_icon = value
        end)
    controls.showRoleIcon:SetPoint("TOPLEFT", content, "TOPLEFT", 234, builder.y)
    builder.y = builder.y - 30

    controls.showRealm = createOptionsCheckbox(content, nil, L["OPTIONS_SHOW_REALM"] or "Show realm",
        L["OPTIONS_SHOW_REALM_DESC"] or "Show the realm name for players from other servers (cross-realm).",
        function(_, value)
            TacoTipConfig.show_realm = value
        end)
    controls.showRealm:SetPoint("TOPLEFT", content, "TOPLEFT", 14, builder.y)
    controls.showIlvlInline = createOptionsCheckbox(content, nil, L["OPTIONS_SHOW_ILVL_INLINE"] or "iLvl on name line",
        L["OPTIONS_SHOW_ILVL_INLINE_DESC"] or
        "Show average item level next to the player's name instead of on a separate line.", function(_, value)
            TacoTipConfig.show_ilvl_inline = value
        end)
    controls.showIlvlInline:SetPoint("TOPLEFT", content, "TOPLEFT", 234, builder.y)
    builder.y = builder.y - 30

    controls.showPowerBar = createOptionsCheckbox(content, nil, L["Power Bar"], L["Show unit's power bar under tooltip"],
        function(_, value)
            TacoTipConfig.show_power_bar = value
            -- Live sync: apply the power bar visibility change to the current tooltip immediately
            if (GameTooltip and GameTooltip:IsShown() and TT.ApplyTooltipAppearance
                    and type(GameTooltip.GetUnit) == "function") then
                local ok, _, unit = pcall(GameTooltip.GetUnit, GameTooltip)
                if (ok and unit) then
                    TT:ApplyTooltipAppearance(GameTooltip, unit)
                end
            end
        end)
    controls.showPowerBar:SetPoint("TOPLEFT", content, "TOPLEFT", 14, builder.y)
    builder.y = builder.y - 42

    local itemHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    itemHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 16, builder.y)
    itemHeader:SetText(L["OPTIONS_SECTION_ITEM_TOOLTIPS"] or "Item tooltip data")
    builder.y = builder.y - 24

    controls.showItemLevel = createOptionsCheckbox(content, nil, L["Show Item Level"],
        L["Display item level in the tooltip for certain items."],
        function(_, value) TacoTipConfig.show_item_level = value end)
    controls.showItemLevel:SetPoint("TOPLEFT", content, "TOPLEFT", 14, builder.y)
    controls.gearScoreItems = createOptionsCheckbox(content, nil, L["Show Item GearScore"],
        L["Show GearScore in item tooltips"],
        function(_, value)
            TacoTipConfig.show_gs_items = value
            modernGetConfig()
        end)
    controls.gearScoreItems:SetPoint("TOPLEFT", content, "TOPLEFT", 234, builder.y)
    builder.y = builder.y - 30

    controls.hunterScoreItems = createOptionsCheckbox(content, nil, L["HunterScore"],
        L["OPTIONS_HUNTERSCORE_DESC"] or
        "Always show HunterScore when item GearScore is enabled. Without this, TacoTip still shows it for Hunters, when inspecting a Hunter, or while a modifier key is held.",
        function(_, value) TacoTipConfig.show_gs_items_hs = value end)
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

    controls.tooltipBackgroundUseClass = createOptionsCheckbox(content, nil,
        L["OPTIONS_BACKGROUND_CLASS_COLOR"] or "Use class-colored background tint",
        L["OPTIONS_BACKGROUND_CLASS_COLOR_DESC"] or
        "Adds a subtle class-colored tint behind player tooltips. Use the alpha slider to keep it understated.",
        function(_, value)
            TacoTipConfig.tooltip_background_use_class = value
        end)
    controls.tooltipBackgroundUseClass:SetPoint("TOPLEFT", content, "TOPLEFT", 234, builder.y)
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
    controls.tooltipBackgroundColor:SetPoint("TOPLEFT", content, "TOPLEFT", 236, builder.y)
    builder.y = builder.y - 118

    controls.tooltipBorderAlpha = createOptionsSlider(content, nil, L["OPTIONS_BORDER_ALPHA"] or "Border alpha",
        L["OPTIONS_BORDER_ALPHA_DESC"] or
        "Adjust how strong the tooltip border tint appears. Lower values keep class coloring subtle.", function(value)
            TacoTipConfig.tooltip_border_alpha = value / 100
        end, 0, 100, 1)
    controls.tooltipBorderAlpha:SetPoint("TOPLEFT", content, "TOPLEFT", 4, builder.y)
    controls.tooltipBorderAlpha.valueText:SetPoint("LEFT", controls.tooltipBorderAlpha, "RIGHT", 8, 0)

    controls.tooltipBorderEdgeSize = createOptionsSlider(content, nil,
        L["OPTIONS_TOOLTIP_BORDER_THICKNESS"] or "Border thickness",
        L["OPTIONS_TOOLTIP_BORDER_THICKNESS_DESC"] or
        "Control how thick the tooltip border appears. Higher values create a wider, more prominent border edge. Default is 20px.",
        function(value)
            TacoTipConfig.tooltip_border_edge_size = value
        end, 4, 48, 1)
    controls.tooltipBorderEdgeSize:SetPoint("TOPLEFT", content, "TOPLEFT", 214, builder.y)
    controls.tooltipBorderEdgeSize.valueText:SetPoint("LEFT", controls.tooltipBorderEdgeSize, "RIGHT", 8, 0)
    builder.y = builder.y - 56

    controls.tooltipBackgroundAlpha = createOptionsSlider(content, nil,
        L["OPTIONS_BACKGROUND_ALPHA"] or "Background alpha",
        L["OPTIONS_BACKGROUND_ALPHA_DESC"] or
        "Adjust how strong the tooltip background tint appears. Lower values keep the tooltip readable.", function(value)
            TacoTipConfig.tooltip_background_alpha = value / 100
        end, 0, 100, 1)
    controls.tooltipBackgroundAlpha:SetPoint("TOPLEFT", content, "TOPLEFT", 4, builder.y)
    controls.tooltipBackgroundAlpha.valueText:SetPoint("LEFT", controls.tooltipBackgroundAlpha, "RIGHT", 8, 0)
    builder.y = builder.y - 56

    controls.tooltipBackgroundTextureChoice = createOptionsDropdown(content, nil,
        L["OPTIONS_TOOLTIP_BACKGROUND_TEXTURE"] or "Tooltip background texture",
        L["OPTIONS_TOOLTIP_BACKGROUND_TEXTURE_DESC"] or
        "Choose the tooltip background texture. SharedMedia background packs are picked up automatically and Blizzard tooltip texture remains the fallback.",
        TT:GetTooltipBackgroundChoices(), function(value)
            TacoTipConfig.tooltip_background_texture = value
            modernGetConfig()
        end)
    builder.y = builder.y - layoutDropdownControl(content, controls.tooltipBackgroundTextureChoice, builder.y)

    controls.tooltipBorderTextureChoice = createOptionsDropdown(content, nil,
        L["OPTIONS_TOOLTIP_BORDER_TEXTURE"] or "Tooltip border texture",
        L["OPTIONS_TOOLTIP_BORDER_TEXTURE_DESC"] or
        "Choose the tooltip border texture. SharedMedia border packs are picked up automatically and Blizzard tooltip border remains the fallback.",
        TT:GetTooltipBorderChoices(), function(value)
            TacoTipConfig.tooltip_border_texture = value
            modernGetConfig()
        end)
    builder.y = builder.y - layoutDropdownControl(content, controls.tooltipBorderTextureChoice, builder.y)

    controls.showSeparators = createOptionsCheckbox(content, nil,
        L["OPTIONS_SHOW_SEPARATORS"] or "Show section separators",
        L["OPTIONS_SHOW_SEPARATORS_DESC"] or
        "Add thin horizontal lines between logical sections of the tooltip for visual clarity.", function(_, value)
            TacoTipConfig.show_separators = value
        end)
    controls.showSeparators:SetPoint("TOPLEFT", content, "TOPLEFT", 14, builder.y)

    controls.tooltipMaxWidth = createOptionsSlider(content, nil, L["OPTIONS_TOOLTIP_MAX_WIDTH"] or "Tooltip max width",
        L["OPTIONS_TOOLTIP_MAX_WIDTH_DESC"] or
        "Set a maximum width for the tooltip to prevent it from becoming too wide with long names or guild titles. Set to 0 for the default limit (320).",
        function(value)
            TacoTipConfig.tooltip_max_width = value
        end, 0, 500, 10)
    controls.tooltipMaxWidth:SetPoint("TOPLEFT", content, "TOPLEFT", 214, builder.y)
    controls.tooltipMaxWidth.valueText:SetPoint("LEFT", controls.tooltipMaxWidth, "RIGHT", 8, 0)
    builder.y = builder.y - 56

    local portraitTextHeader = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    portraitTextHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 16, builder.y)
    portraitTextHeader:SetText(L["OPTIONS_SECTION_TEXT_AND_PORTRAIT"] or "Portrait & text")
    builder.y = builder.y - 24

    controls.tooltipPortrait = createOptionsCheckbox(content, nil, L["OPTIONS_TOOLTIP_PORTRAIT"] or "Show unit portrait",
        L["OPTIONS_TOOLTIP_PORTRAIT_DESC"] or "Show a small portrait texture next to player and NPC unit tooltips.",
        function(_, value)
            TacoTipConfig.tooltip_portrait = value
            modernGetConfig()
        end)
    controls.tooltipPortrait:SetPoint("TOPLEFT", content, "TOPLEFT", 14, builder.y)
    builder.y = builder.y - 34

    controls.tooltipPortraitScale = createOptionsSlider(content, nil,
        L["OPTIONS_TOOLTIP_PORTRAIT_SCALE"] or "Portrait scale",
        L["OPTIONS_TOOLTIP_PORTRAIT_SCALE_DESC"] or "Scale the portrait shown next to unit tooltips.", function(value)
            TacoTipConfig.tooltip_portrait_scale = value / 100
        end, 50, 200, 5)
    controls.tooltipPortraitScale:SetPoint("TOPLEFT", content, "TOPLEFT", 4, builder.y)
    controls.tooltipPortraitScale.valueText:SetPoint("LEFT", controls.tooltipPortraitScale, "RIGHT", 8, 0)
    builder.y = builder.y - 56

    controls.tooltipPortrait3D = createOptionsCheckbox(content, nil,
        L["OPTIONS_TOOLTIP_PORTRAIT_3D"] or "Show 3D portrait",
        L["OPTIONS_TOOLTIP_PORTRAIT_3D_DESC"] or "Use a live 3D model instead of a 2D portrait texture.",
        function(_, value)
            TacoTipConfig.tooltip_portrait_3d = value
            modernGetConfig()
        end)
    controls.tooltipPortrait3D:SetPoint("TOPLEFT", content, "TOPLEFT", 14, builder.y)
    builder.y = builder.y - 34

    controls.tooltipPortraitInvertSide = createOptionsCheckbox(content, nil,
        L["OPTIONS_TOOLTIP_PORTRAIT_INVERT_SIDE"] or "Invert portrait side",
        L["OPTIONS_TOOLTIP_PORTRAIT_INVERT_SIDE_DESC"] or
        "Swap the portrait to the opposite side of the tooltip.",
        function(_, value)
            TacoTipConfig.tooltip_portrait_invert_side = value
            modernGetConfig()
        end)
    controls.tooltipPortraitInvertSide:SetPoint("TOPLEFT", content, "TOPLEFT", 14, builder.y)
    builder.y = builder.y - 34

    -- The zoom's RANGE is unchanged: 30-100 on the slider, which is 0.30 to
    -- 1.00 -- and it is read from the ONE source of truth
    -- (TT.TooltipPortraitZoomRange), so the slider and the sanitiser can
    -- never drift apart. The zoom is applied exactly as the player set it:
    -- no cap, no clamp, no changed bound.
    --
    -- The DESCRIPTION states the range's meaning, so the top of the range is
    -- not a surprise: higher is closer, and the top is a face close-up. The
    -- localized string already says "lower is further, higher is closer" in
    -- every shipped locale; this is the English fallback for a client whose
    -- locale table has no such key.
    controls.tooltipPortraitZoom = createOptionsSlider(content, nil, L["OPTIONS_PORTRAIT_ZOOM"] or "Portrait zoom",
        L["OPTIONS_PORTRAIT_ZOOM_DESC"] or
        "Controls how close the 3D portrait model appears. Higher values zoom in on the character's face; the top of the range is a face close-up.",
        function(value)
            TacoTipConfig.tooltip_portrait_zoom = value / 100
        end,
        math.floor(TT.TooltipPortraitZoomRange.min * 100),
        math.floor(TT.TooltipPortraitZoomRange.max * 100), 5)
    controls.tooltipPortraitZoom:SetPoint("TOPLEFT", content, "TOPLEFT", 4, builder.y)
    controls.tooltipPortraitZoom.valueText:SetPoint("LEFT", controls.tooltipPortraitZoom, "RIGHT", 8, 0)
    builder.y = builder.y - 56

    controls.classIconSize = createOptionsSlider(content, nil, "Class icon size",
        "Size of the class icon badge shown at the top-right corner of player tooltips.", function(value)
            TacoTipConfig.class_icon_size = value
        end, 8, 32, 1)
    controls.classIconSize:SetPoint("TOPLEFT", content, "TOPLEFT", 4, builder.y)
    controls.classIconSize.valueText:SetPoint("LEFT", controls.classIconSize, "RIGHT", 8, 0)
    builder.y = builder.y - 56

    controls.tooltipFontChoice = createOptionsDropdown(content, nil, L["OPTIONS_TOOLTIP_FONT"] or "Tooltip font",
        L["OPTIONS_TOOLTIP_FONT_DESC"] or
        "Choose the font used by tooltip text. SharedMedia fonts are included automatically when available.",
        TT:GetTooltipFontChoices(), function(value)
            TacoTipConfig.tooltip_font = value
            modernGetConfig()
        end)
    builder.y = builder.y - layoutDropdownControl(content, controls.tooltipFontChoice, builder.y)

    controls.tooltipFontSize = createOptionsSlider(content, nil, L["OPTIONS_TOOLTIP_FONT_SIZE"] or "Tooltip text size",
        L["OPTIONS_TOOLTIP_FONT_SIZE_DESC"] or
        "Change the size of the tooltip text without affecting the rest of the UI.", function(value)
            TacoTipConfig.tooltip_font_size = value
        end, 8, 20, 1)
    controls.tooltipFontSize:SetPoint("TOPLEFT", content, "TOPLEFT", 4, builder.y)
    controls.tooltipFontSize.valueText:SetPoint("LEFT", controls.tooltipFontSize, "RIGHT", 8, 0)
    builder.y = builder.y - 56

    local barHeader = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    barHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 16, builder.y)
    barHeader:SetText(L["OPTIONS_SECTION_BAR_MEDIA"] or "Tooltip bars")
    builder.y = builder.y - 24

    controls.tooltipBarTextureChoice = createOptionsDropdown(content, nil,
        L["OPTIONS_STATUSBAR_TEXTURE"] or "Health & power bar texture",
        L["OPTIONS_STATUSBAR_TEXTURE_DESC"] or
        "Use one texture for both the health bar and the power bar. The dropdown previews each texture as a bar instead of an icon.",
        TT:GetTooltipStatusBarTextureChoices(), function(value)
            TacoTipConfig.tooltip_bar_texture = value
            modernGetConfig()
        end)
    builder.y = builder.y - layoutDropdownControl(content, controls.tooltipBarTextureChoice, builder.y, 14)

    builder:Finalize(64)

    -- NOTE: do NOT assign panel:SetScript("OnShow") here. The load-tail
    -- wrappers near the bottom of this file install safeCall-wrapped OnShow
    -- handlers for every page; assigning inside the builder silently
    -- replaced them once the page was built (order-dependent overwrite).
    -- The wrapper already invokes panel:Refresh(), which is all this
    -- handler did.
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
        controls.shamanBlue:SetChecked(TacoTipConfig.shaman_blue ~= false)
        controls.showTitles:SetChecked(TacoTipConfig.show_titles)
        controls.showGuildNames:SetChecked(TacoTipConfig.show_guild_name)
        if (controls.showGuildRanks) then
            controls.showGuildRanks:SetChecked(TacoTipConfig.show_guild_rank)
            controls.showGuildRanks:SetDisabled(not TacoTipConfig.show_guild_name)
        end
        controls.guildRankStyleChoice:SetValue(TacoTipConfig.guild_rank_alt_style and 2 or 1)
        controls.guildRankStyleChoice:SetDisabled(not (TacoTipConfig.show_guild_name and TacoTipConfig.show_guild_rank))
        controls.showTalents:SetChecked(TacoTipConfig.show_talents)
        controls.showTarget:SetChecked(TacoTipConfig.show_target)
        controls.gearScorePlayer:SetChecked(TacoTipConfig.show_gs_player)
        controls.pawnScorePlayer:SetChecked(TacoTipConfig.show_pawn_player)
        local pawnNow = isPawnAvailableNow()
        controls.pawnScorePlayer:SetDisabled(not pawnNow)
        controls.pawnScorePlayer.label:SetText(pawnNow and (L["OPTIONS_SHOW_PLAYER_PAWN"] or "Show Pawn scores") or
            ((L["OPTIONS_SHOW_PLAYER_PAWN"] or "Show Pawn scores") .. " (" .. L["requires Pawn"] .. ")"))
        -- nil/absent means enabled, mirroring the library's own default.
        -- The checkbox follows the LIBRARY state, not just the config
        -- (hunter H7): if an apply failed or the library appeared late the
        -- two can disagree, and the control must show what actually scans.
        do
            local okLib, lib = pcall(LibStub, "LibForeverInspector", true)
            local actual = (okLib and type(lib) == "table" and type(lib.scanEnabled) == "boolean")
                and lib.scanEnabled or (TacoTipConfig.scan ~= false)
            controls.scanNearby:SetChecked(actual)
        end
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
        controls.tooltipBorderColor:SetColor(TacoTipConfig.tooltip_border_color_r or 1,
            TacoTipConfig.tooltip_border_color_g or 1, TacoTipConfig.tooltip_border_color_b or 1)
        controls.tooltipBackgroundColor:SetColor(TacoTipConfig.tooltip_background_color_r or 0,
            TacoTipConfig.tooltip_background_color_g or 0, TacoTipConfig.tooltip_background_color_b or 0)
        controls.tooltipBorderAlpha:SetValueSilently(math.floor((TacoTipConfig.tooltip_border_alpha or 1) * 100 + 0.5))
        -- The slider only has authority when the selected border does not carry
        -- its own edge size. The three themed 256x32 borders declare 32, so the
        -- player's stored value was being shown on an enabled slider that then
        -- did nothing when dragged.
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
        controls.tooltipPortrait:SetChecked(TacoTipConfig.tooltip_portrait)
        controls.tooltipPortraitScale:SetValueSilently(math.floor((TacoTipConfig.tooltip_portrait_scale or 1) * 100 + 0.5))
        controls.tooltipPortraitScale:SetDisabled(not TacoTipConfig.tooltip_portrait)
        controls.tooltipPortrait3D:SetChecked(TacoTipConfig.tooltip_portrait_3d)
        controls.tooltipPortraitInvertSide:SetChecked(TacoTipConfig.tooltip_portrait_invert_side)
        controls.tooltipPortrait3D:SetDisabled(not TacoTipConfig.tooltip_portrait)
        -- The slider shows the value the portrait is rendered with: the saved
        -- value, or the ONE default (options.lua's DEFAULTS, published as
        -- TT.TooltipPortraitZoomDefault) when there is none. It used to
        -- repeat a different literal (0.7) here, so with no saved value the
        -- slider read 70 while the portrait was rendered at 75.
        controls.tooltipPortraitZoom:SetValueSilently(math.floor(
            (TacoTipConfig.tooltip_portrait_zoom or TT.TooltipPortraitZoomDefault) * 100 + 0.5))
        controls.tooltipPortraitZoom:SetDisabled(not TacoTipConfig.tooltip_portrait)
        controls.classIconSize:SetValueSilently(TacoTipConfig.class_icon_size or 20)
        controls.tooltipFontChoice:SetValue(TT:GetResolvedTooltipFont())
        controls.tooltipFontSize:SetValueSilently(TacoTipConfig.tooltip_font_size or 12)
        controls.tooltipBarTextureChoice:SetValue(TT:GetResolvedTooltipStatusBarTexture())
        controls.showHonorRank:SetChecked(TacoTipConfig.show_honor_rank)
        controls.showRoleIcon:SetChecked(TacoTipConfig.show_role_icon)
        controls.showRealm:SetChecked(TacoTipConfig.show_realm)
        controls.showIlvlInline:SetChecked(TacoTipConfig.show_ilvl_inline)
        controls.showSeparators:SetChecked(TacoTipConfig.show_separators)
        controls.tooltipMaxWidth:SetValueSilently(TacoTipConfig.tooltip_max_width or 0)
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

    -- A client with no GameTooltip.FadeOut cannot do an instant fade at all.
    -- The option is then offered, DISABLED, and explained -- an option that is
    -- settable and silently inert is worse than one that says why it cannot
    -- be used. The probe is a runtime capability check (see
    -- instantFadeSupported), so on every supported client -- which all have the
    -- method -- nothing here changes.
    --
    -- The explanation is a plain English literal, NOT a locale-table lookup:
    -- the Locale files are not touched by this change, and the harness asserts
    -- that every locale key the source uses exists in the locale table. It is
    -- shown only on a client where the feature cannot work at all.
    if (not instantFadeSupported()) then
        local why = createWrappedText(content, "GameFontHighlightSmall", 560,
            "Not available on this client: it has no instant-fade API, so this option cannot be used.")
        why:SetPoint("TOPLEFT", content, "TOPLEFT", 34, builder.y + 16)
        controls.instantFade.description = why
        controls.instantFade:SetDisabled(true)
        builder.y = builder.y - 22
    end

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
