---@diagnostic disable: undefined-global
-- ============================================================
-- File role: WoWUnit in-game test suite for TacoTip Gearscore TBC
-- Depends on: WoWUnit addon (optional, skipped cleanly)
-- Target: TBC Anniversary 2.5.5-2.5.6 (also Classic Era / SoD 1.15.8, Wrath 3.4.x)
-- Run: /tttest  (alias /tacotest)
-- ============================================================
local addonName = ...
local TT = _G[addonName]

local function RegisterTacoTipTests()
    if (not WoWUnit) then return end
    if (not TT) then
        print("|cffff4444[TacoTip-Tests] TT namespace missing; aborting.|r")
        return
    end

    local IsTrue, IsFalse = WoWUnit.IsTrue, WoWUnit.IsFalse
    local Exists, AreEqual = WoWUnit.Exists, WoWUnit.AreEqual
    local Replace = WoWUnit.Replace
    local ClearReplaces = WoWUnit.ClearReplaces
    local function pc(p, ...) local ok, r = pcall(p, ...); return ok, r end

    -- ============================================================
    -- TT-Core: addon loaded, namespace sane, public API present
    -- ============================================================
    local Core = WoWUnit("TacoTip-Core", "PLAYER_ENTERING_WORLD")

    function Core:NamespaceLoaded()
        IsTrue(type(TT) == "table", "TT namespace is a table")
        IsTrue(type(_G.TacoTipConfig) == "table", "TacoTipConfig global exists")
    end
    function Core:PublicAPIPresent()
        for _, m in ipairs{
            "GetDefaults", "ApplyConfigDefaults", "SafeSanitizeConfig",
            "ApplyTooltipAppearance", "SyncTooltipMover",
            "GetFormattedSpecializationText", "RefreshOptionsUI",
        } do
            Exists(TT[m], "TT." .. m)
        end
    end
    function Core:VersionMetadata()
        local ok, ver = pc(function() return (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, "Version")) or GetAddOnMetadata(addonName, "Version") end)
        IsTrue(ok and type(ver) == "string" and ver ~= "", "version metadata readable: " .. tostring(ver))
    end
    function Core:InterfaceSupport()
        local ok, toc = pc(function()
            return (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, "Interface"))
                or GetAddOnMetadata(addonName, "Interface")
        end)
        IsTrue(ok and toc and toc:find("20505") ~= nil, "TBC interface 20505 advertised: " .. tostring(toc))
    end

    -- ============================================================
    -- TT-Config: defaults complete + sanitizer bounds
    -- ============================================================
    local Config = WoWUnit("TacoTip-Config", "PLAYER_ENTERING_WORLD")

    function Config:DefaultsHaveKeys()
        local d = TT:GetDefaults()
        for _, k in ipairs{
            "color_class", "show_guild_name", "show_guild_rank", "show_talents",
            "show_gs_player", "tip_style", "show_target", "show_pawn_player",
            "show_class_icon", "tooltip_border_use_class", "tooltip_border_color_r",
            "tooltip_border_color_g", "tooltip_border_color_b", "tooltip_border_alpha",
            "tooltip_portrait", "tooltip_portrait_scale", "tooltip_portrait_3d",
            "tooltip_portrait_zoom", "show_elite_frame", "tooltip_font",
            "tooltip_font_size", "tooltip_max_width", "tooltip_delay",
            "anchor_mouse", "anchor_mouse_world", "anchor_mouse_spells",
            "custom_pos", "custom_anchor", "guild_rank_style",
        } do
            IsTrue(d[k] ~= nil, "defaults." .. k .. "=" .. tostring(d[k]))
        end
    end
    function Config:ApplyDefaultsFillsMissing()
        local cfg = { color_class = true }
        TT:ApplyConfigDefaults(cfg)
        IsTrue(cfg.show_guild_name == true, "missing key filled from defaults")
        IsTrue(type(cfg.tooltip_border_color_r) == "number", "numeric default applied")
    end
    function Config:SanitizeCoercesBooleans()
        local cfg = TT:GetDefaults()
        cfg.color_class = "true" -- corrupted string form
        TT:SafeSanitizeConfig(cfg)
        IsTrue(cfg.color_class == true, "string-boolean repaired to real boolean")
    end
    function Config:SanitizeBounds()
        local cfg = TT:GetDefaults()
        cfg.class_icon_size = 999
        cfg.tooltip_portrait_scale = -5
        cfg.tooltip_portrait_zoom = 99
        cfg.tooltip_font_size = 0
        cfg.tooltip_border_alpha = 2
        cfg.tip_style = 42
        TT:SafeSanitizeConfig(cfg)
        IsTrue(cfg.class_icon_size <= 32 and cfg.class_icon_size >= 8, "class_icon_size clamped")
        IsTrue(cfg.tooltip_portrait_scale <= 2 and cfg.tooltip_portrait_scale >= 0.5, "portrait_scale clamped")
        IsTrue(cfg.tooltip_portrait_zoom <= 1 and cfg.tooltip_portrait_zoom >= 0.3, "portrait_zoom clamped")
        IsTrue(cfg.tooltip_font_size <= 20 and cfg.tooltip_font_size >= 8, "font_size clamped")
        IsTrue(cfg.tooltip_border_alpha <= 1 and cfg.tooltip_border_alpha >= 0, "border_alpha clamped")
        IsTrue(cfg.tip_style >= 1 and cfg.tip_style <= 5, "tip_style clamped")
    end

    -- ============================================================
    -- TT-Borders: class border applies to players, NEVER bleeds
    -- to non-unit / item tooltips (the reported minimap/world-map bug)
    -- ============================================================
    local Borders = WoWUnit("TacoTip-Borders", "PLAYER_ENTERING_WORLD")

    function Borders:PlayerGetsClassBorder()
        local cfg = _G.TacoTipConfig
        local savedUse, savedR, savedG, savedB = cfg.tooltip_border_use_class, cfg.tooltip_border_color_r, cfg.tooltip_border_color_g, cfg.tooltip_border_color_b
        cfg.tooltip_border_use_class = true
        cfg.tooltip_border_color_r, cfg.tooltip_border_color_g, cfg.tooltip_border_color_b = 1, 1, 1
        local ok = pc(TT.ApplyTooltipAppearance, TT, GameTooltip, "player")
        IsTrue(ok, "ApplyTooltipAppearance(player) did not error")
        local bf = GameTooltip.TacoTipBackdropFrame
        Exists(bf, "backdrop frame created")
        if (bf and bf.GetBackdropBorderColor) then
            local r, g, b = bf:GetBackdropBorderColor()
            -- Class border must differ from the white base (1,1,1).
            IsTrue(not (r == 1 and g == 1 and b == 1), string.format("player border tinted (%.2f,%.2f,%.2f)", r or -1, g or -1, b or -1))
        end
        cfg.tooltip_border_use_class, cfg.tooltip_border_color_r, cfg.tooltip_border_color_g, cfg.tooltip_border_color_b = savedUse, savedR, savedG, savedB
    end
    function Borders:NoBleedToNonUnitTooltip()
        local cfg = _G.TacoTipConfig
        local savedUse = cfg.tooltip_border_use_class
        cfg.tooltip_border_use_class = true
        -- First paint a player tooltip (class border applied).
        pc(TT.ApplyTooltipAppearance, TT, GameTooltip, "player")
        -- Recycle the tooltip the way the game does when you stop hovering a
        -- unit: Clear() fires OnTooltipCleared -> clearTooltipVisuals ->
        -- resetTooltipBorderToDefault. The class color must NOT persist.
        pc(GameTooltip.Clear, GameTooltip)
        local bf = GameTooltip.TacoTipBackdropFrame
        if (bf and bf.GetBackdropBorderColor) then
            local r, g, b = bf:GetBackdropBorderColor()
            AreEqual(r, 1, "border red reset to base after clear")
            AreEqual(g, 1, "border green reset to base after clear")
            AreEqual(b, 1, "border blue reset to base after clear")
        else
            IsTrue(false, "backdrop frame missing for reset assertion")
        end
        cfg.tooltip_border_use_class = savedUse
    end
    function Borders:NoBleedToItemTooltip()
        local cfg = _G.TacoTipConfig
        local savedUse = cfg.tooltip_border_use_class
        cfg.tooltip_border_use_class = true
        pc(TT.ApplyTooltipAppearance, TT, GameTooltip, "player")
        -- Item tooltips route through itemToolTipHook -> applyTooltipBorderOverlay(base).
        -- Use a real item link so the OnTooltipSetItem hook fires.
        local link = select(2, pc(GetItemInfo, 19019)) or "item:19019:0:0:0:0:0:0"
        pcall(GameTooltip.SetHyperlink, GameTooltip, link)
        local bf = GameTooltip.TacoTipBackdropFrame
        if (bf and bf.GetBackdropBorderColor) then
            local r, g, b = bf:GetBackdropBorderColor()
            AreEqual(r, 1, "item border red is base (no class bleed)")
            AreEqual(g, 1, "item border green is base (no class bleed)")
            AreEqual(b, 1, "item border blue is base (no class bleed)")
        end
        cfg.tooltip_border_use_class = savedUse
    end

    -- ============================================================
    -- TT-Portrait: 3:4 (taller than wide) sizing, slightly larger
    -- ============================================================
    local Portrait = WoWUnit("TacoTip-Portrait", "PLAYER_ENTERING_WORLD")

    function Portrait:DefaultSizeIs34Ratio()
        local cfg = _G.TacoTipConfig
        local savedScale = cfg.tooltip_portrait_scale
        cfg.tooltip_portrait_scale = 1
        pc(TT.ApplyTooltipAppearance, TT, GameTooltip, "player")
        local f = GameTooltip.TacoTipPortrait3D or GameTooltip.TacoTipPortrait
        Exists(f, "portrait frame created")
        if (f and f.GetWidth and f.GetHeight) then
            local w, h = f:GetWidth(), f:GetHeight()
            AreEqual(w, 42, "portrait width = 42 at scale 1")
            AreEqual(h, 56, "portrait height = 56 at scale 1 (3:4, taller)")
            IsTrue(h > w, "portrait is taller than wide (3:4)")
        end
        cfg.tooltip_portrait_scale = savedScale
    end
    function Portrait:ScaledSizeKeepsRatio()
        local cfg = _G.TacoTipConfig
        local savedScale = cfg.tooltip_portrait_scale
        cfg.tooltip_portrait_scale = 1.5
        pc(TT.ApplyTooltipAppearance, TT, GameTooltip, "player")
        local f = GameTooltip.TacoTipPortrait3D or GameTooltip.TacoTipPortrait
        if (f and f.GetWidth and f.GetHeight) then
            local w, h = f:GetWidth(), f:GetHeight()
            AreEqual(w, 63, "scaled width = 42*1.5")
            AreEqual(h, 84, "scaled height = 56*1.5")
        end
        cfg.tooltip_portrait_scale = savedScale
    end

    -- ============================================================
    -- TT-Guild: GetGuildInfo path (TBC works; SoD known-broken, noted)
    -- ============================================================
    local Guild = WoWUnit("TacoTip-Guild", "PLAYER_ENTERING_WORLD")

    function Guild:MockEngages()
        -- GetGuildInfo is NOT cached into a local in main.lua, so Replace works.
        Replace("GetGuildInfo", function(unit)
            if (unit == "player") then return "TestGuild", "Rank 5", 5 end
            return nil
        end)
        local name, rank = GetGuildInfo("player")
        AreEqual(name, "TestGuild", "GetGuildInfo mock returns guild name")
        AreEqual(rank, "Rank 5", "GetGuildInfo mock returns guild rank")
        ClearReplaces()
    end
    function Guild:ConfigDefaultsShowGuild()
        local d = TT:GetDefaults()
        IsTrue(d.show_guild_name == true, "guild name shown by default")
        IsTrue(type(d.guild_rank_style) == "number", "guild_rank_style default is numeric")
    end
    function Guild:RenderPathDoesNotError()
        -- End-to-end: mock guild, paint player tooltip, confirm no error and
        -- the guild line is present when the client populates it synchronously.
        Replace("GetGuildInfo", function(unit)
            if (unit == "player") then return "TestGuild", "Rank 5", 5 end
            return nil
        end)
        local cfg = _G.TacoTipConfig
        local savedName = cfg.show_guild_name
        cfg.show_guild_name = true
        local ok = pc(GameTooltip.SetUnit, GameTooltip, "player")
        IsTrue(ok, "SetUnit(player) did not error")
        -- The default UI populates text[2] (guild/race/class) before
        -- OnTooltipSetUnit runs; read it if available.
        local line2 = _G.GameTooltipTextLeft2 and _G.GameTooltipTextLeft2:GetText()
        if (line2 and line2 ~= "") then
            IsTrue(line2:find("TestGuild") ~= nil, "guild name rendered into tooltip line")
        end
        cfg.show_guild_name = savedName
        ClearReplaces()
    end

    -- ============================================================
    -- TT-Stats: GearScore, Pawn, talents nil-safe
    -- ============================================================
    local Stats = WoWUnit("TacoTip-Stats", "PLAYER_ENTERING_WORLD")

    function Stats:GearScoreNilSafe()
        local GS = _G.TT_GS
        Exists(GS, "TT_GS global present")
        if (GS) then
            local ok = pc(GS.GetScore, GS, nil, true)
            IsTrue(ok, "GetScore(nil) safe")
            local ok2 = pc(GS.GetItemScore, GS, nil)
            IsTrue(ok2, "GetItemScore(nil) safe")
            local ok3, r, g, b = pc(GS.GetQuality, GS, 0)
            IsTrue(ok3, "GetQuality(0) safe")
        end
    end
    function Stats:PawnNilSafe()
        local Pawn = _G.TT_PAWN
        Exists(Pawn, "TT_PAWN global present")
        if (Pawn and Pawn.GetScore) then
            local ok = pc(Pawn.GetScore, Pawn, nil, false)
            IsTrue(ok, "Pawn GetScore(nil) safe")
        end
    end
    function Stats:SpecializationNilSafe()
        local ok, txt = pc(TT.GetFormattedSpecializationText, TT, nil, nil, nil, nil, nil)
        IsTrue(ok, "GetFormattedSpecializationText(nil...) safe")
        IsTrue(txt == nil, "nil inputs yield nil spec text")
    end
    function Stats:ClassicInspectorPresent()
        local CI = LibStub and LibStub("LibClassicInspector", true)
        Exists(CI, "LibClassicInspector loaded")
        if (CI) then
            local ok = pc(CI.GetSpecializationName, CI, "WARRIOR", 1, true)
            IsTrue(ok, "CI:GetSpecializationName safe")
        end
    end

    -- ============================================================
    -- TT-Mover: tooltip mover sync is callable and nil-safe
    -- ============================================================
    local Mover = WoWUnit("TacoTip-Mover", "PLAYER_ENTERING_WORLD")

    function Mover:SyncTooltipMoverNilSafe()
        local ok = pc(TT.SyncTooltipMover, TT, nil)
        IsTrue(ok, "SyncTooltipMover(nil) safe")
    end
    function Mover:RefreshOptionsUINilSafe()
        local ok = pc(TT.RefreshOptionsUI, TT)
        IsTrue(ok, "RefreshOptionsUI() safe")
    end

    -- ============================================================
    -- TT-Modules: dependent modules loaded
    -- ============================================================
    local Modules = WoWUnit("TacoTip-Modules", "PLAYER_ENTERING_WORLD")

    function Modules:DependentGlobals()
        Exists(_G.TT_GS, "gearscore.lua exposed TT_GS")
        Exists(_G.TT_PAWN, "pawn.lua exposed TT_PAWN")
        Exists(_G.TACOTIP_LOCALE, "locale table loaded")
    end
    function Modules:ConfigHasAllDefaults()
        local d = TT:GetDefaults()
        local count = 0
        for _ in pairs(d) do count = count + 1 end
        IsTrue(count >= 40, "defaults table has full key set (" .. count .. ")")
    end

    print("|cff44ff44[TacoTip] 8 test groups registered. Type /tttest to run.|r")
end

SLASH_TTTEST1 = "/tttest"
SLASH_TTTEST2 = "/tacotest"
SlashCmdList["TTTEST"] = function()
    if (not WoWUnit) then
        print("|cffff4444[TacoTip] WoWUnit not installed — tests skipped.|r")
        return
    end
    local n = 0
    for _, g in ipairs(WoWUnit.children or {}) do
        if (g.name and g.name:match("^TacoTip%-")) then
            local ok, err = pcall(g)
            if (not ok) then
                geterrorhandler()(err)
                print("|cffff4444[TacoTip] " .. tostring(err) .. "|r")
            else
                n = n + 1
            end
        end
    end
    print("|cff44ff44[TacoTip] Ran " .. n .. " groups.|r")
end

local f = CreateFrame("Frame")
f:SetScript("OnUpdate", function(s)
    s:SetScript("OnUpdate", nil)
    if (WoWUnit) then
        local ok, err = pcall(RegisterTacoTipTests)
        if (not ok) then
            geterrorhandler()(err)
            print("|cffff4444[TacoTip] test registration failed: " .. tostring(err) .. "|r")
        end
    else
        print("|cffff4444[TacoTip] WoWUnit not found — tests disabled.|r")
    end
end)
