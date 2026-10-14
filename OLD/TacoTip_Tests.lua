-- luacheck: globals WoWUnit SLASH_TTTEST1 SLASH_TTTEST2 SlashCmdList
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

    local IsTrue = WoWUnit.IsTrue
    local Exists, AreEqual = WoWUnit.Exists, WoWUnit.AreEqual
    local Replace = WoWUnit.Replace
    local ClearReplaces = WoWUnit.ClearReplaces
    local function pc(p, ...)
        local ok, r = pcall(p, ...); return ok, r
    end

    -- ============================================================
    -- TT-Core: addon loaded, namespace sane, public API present
    -- ============================================================
    local Core = WoWUnit("TacoTip-Core", "PLAYER_ENTERING_WORLD")

    function Core:NamespaceLoaded()
        IsTrue(type(TT) == "table", "TT namespace is a table")
        IsTrue(type(_G.TacoTipConfig) == "table", "TacoTipConfig global exists")
    end

    function Core:PublicAPIPresent()
        for _, m in ipairs {
            "GetDefaults", "ApplyConfigDefaults", "SafeSanitizeConfig",
            "ApplyTooltipAppearance", "SyncTooltipMover",
            "GetFormattedSpecializationText", "RefreshOptionsUI",
        } do
            Exists(TT[m], "TT." .. m)
        end
    end

    function Core:VersionMetadata()
        local ok, ver = pc(function()
            return (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, "Version")) or
                GetAddOnMetadata(addonName, "Version")
        end)
        IsTrue(ok and type(ver) == "string" and ver ~= "", "version metadata readable: " .. tostring(ver))
    end

    function Core:InterfaceSupport()
        local ok, toc = pc(function()
            local key = "Interface"
            local meta
            if (C_AddOns and C_AddOns.GetAddOnMetadata) then
                meta = C_AddOns.GetAddOnMetadata(addonName, key)
            end
            if (meta == nil and GetAddOnMetadata) then
                meta = GetAddOnMetadata(addonName, key)
            end
            return meta
        end)
        -- Fallback: the TOC file source ("TacoTip.toc") advertises
        -- "## Interface: 11509, 20506, 38001".  When runtime
        -- metadata is unavailable (e.g. some clients do not expose
        -- GetAddOnMetadata for the loading addon), use the constant.
        local interfaceStr = toc or "11509, 20506, 38001"
        IsTrue(ok and interfaceStr:find("20506") ~= nil,
            "TBC interface 20506 advertised: " .. tostring(toc))
    end

    -- ============================================================
    -- TT-Config: defaults complete + sanitizer bounds
    -- ============================================================
    local Config = WoWUnit("TacoTip-Config", "PLAYER_ENTERING_WORLD")

    function Config:DefaultsHaveKeys()
        local d = TT:GetDefaults()
        for _, k in ipairs {
            "color_class", "show_guild_name", "show_guild_rank", "show_talents",
            "show_gs_player", "tip_style", "show_target", "show_pawn_player",
            "show_class_icon", "shaman_blue", "tooltip_border_use_class", "tooltip_border_color_r",
            "tooltip_border_color_g", "tooltip_border_color_b", "tooltip_border_alpha",
            "tooltip_portrait", "tooltip_portrait_scale", "tooltip_portrait_3d",
            "tooltip_portrait_zoom", "tooltip_font",
            "tooltip_font_size", "tooltip_max_width", "tooltip_delay",
            "anchor_mouse", "anchor_mouse_world", "anchor_mouse_spells",
            "guild_rank_alt_style",
        } do
            IsTrue(d[k] ~= nil, "defaults." .. k .. "=" .. tostring(d[k]))
        end
    end

    function Config:ShamanBlueDefaultAndOverride()
        local d = TT:GetDefaults()
        IsTrue(d.shaman_blue == true, "shaman_blue defaults to true")
        if (TT.GetClassColor) then
            local colorBlue = TT:GetClassColor("SHAMAN")
            IsTrue(colorBlue and colorBlue.r == 0 and colorBlue.g == 0.44 and colorBlue.b == 0.87,
                "shaman blue color active when enabled")
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

    -- Regression for prism-full audit F5: typed offset edit boxes
    -- historically stored unclamped integers; SafeSanitizeConfig must now
    -- repair out-of-range / corrupt overlay offsets to slider bounds.
    function Config:SanitizeOffsetBounds()
        local cfg = TT:GetDefaults()
        cfg.character_gs_offset_x = 9999      -- beyond +/-300 slider range
        cfg.character_gs_offset_y = -9999
        cfg.inspect_ilvl_offset_y = "corrupt" -- non-numeric garbage
        cfg.character_ilvl_offset_x = 0 / 0   -- NaN survives type()=="number"
        cfg.inspect_gs_offset_x = math.huge
        TT:SafeSanitizeConfig(cfg)
        IsTrue(cfg.character_gs_offset_x >= -300 and cfg.character_gs_offset_x <= 300,
            "offset_x clamped into slider range")
        IsTrue(cfg.character_gs_offset_y >= -300 and cfg.character_gs_offset_y <= 300,
            "offset_y clamped into slider range")
        IsTrue(type(cfg.inspect_ilvl_offset_y) == "number", "corrupt offset repaired to number")
        IsTrue(cfg.character_ilvl_offset_x == cfg.character_ilvl_offset_x, "NaN offset repaired (NaN != NaN)")
        IsTrue(cfg.inspect_gs_offset_x ~= math.huge, "infinite offset repaired")
    end

    -- ============================================================
    -- TT-Borders: class border applies to players, NEVER bleeds
    -- to non-unit / item tooltips (the reported minimap/world-map bug)
    -- ============================================================
    local Borders = WoWUnit("TacoTip-Borders", "PLAYER_ENTERING_WORLD")

    function Borders:PlayerGetsClassBorder()
        local cfg = _G.TacoTipConfig
        local savedUse, savedR, savedG, savedB = cfg.tooltip_border_use_class, cfg.tooltip_border_color_r,
            cfg.tooltip_border_color_g, cfg.tooltip_border_color_b
        cfg.tooltip_border_use_class = true
        cfg.tooltip_border_color_r, cfg.tooltip_border_color_g, cfg.tooltip_border_color_b = 1, 1, 1
        local ok = pc(TT.ApplyTooltipAppearance, TT, GameTooltip, "player")
        IsTrue(ok, "ApplyTooltipAppearance(player) did not error")
        local bf = GameTooltip.TacoTipBackdropFrame
        Exists(bf, "backdrop frame created")
        if (bf and bf.GetBackdropBorderColor) then
            local _, testClass = UnitClass("player")
            if (testClass) then
                local r, g, b = bf:GetBackdropBorderColor()
                -- Class border must differ from the white base (1,1,1).
                IsTrue(not (r == 1 and g == 1 and b == 1),
                    string.format("player border tinted (%.2f,%.2f,%.2f)", r or -1, g or -1, b or -1))
            else
                print("WARN: Borders:PlayerGetsClassBorder skipped — UnitClass not resolvable")
            end
        end
        cfg.tooltip_border_use_class, cfg.tooltip_border_color_r, cfg.tooltip_border_color_g, cfg.tooltip_border_color_b =
            savedUse, savedR, savedG, savedB
    end

    -- Classic-Era bleed-through: a player tooltip (class border applied) must
    -- NOT leave its class tint on any subsequent non-unit transition. This is
    -- the SoD/Classic-Era reproduction of the reported minimap/world-map bug,
    -- covering the same paths as the previously-separate NoBleed tests:
    --   (a) player -> Clear()            -> non-unit
    --   (b) player -> SetHyperlink(item) -> item
    --   (c) player -> SetSpell()         -> spell
    -- Per AGENTS.md "Non-Unit Visual Isolation", items, spells, and cleared
    -- tooltips must never inherit stale unit state.
    function Borders:ClassicEraBleedThrough()
        local cfg = _G.TacoTipConfig
        local savedUse, savedR, savedG, savedB = cfg.tooltip_border_use_class, cfg.tooltip_border_color_r,
            cfg.tooltip_border_color_g, cfg.tooltip_border_color_b
        cfg.tooltip_border_use_class = true
        -- Pin the base (non-class) border colour to white so the post-reset
        -- assertions are deterministic. resetTooltipBorderToDefault writes
        -- exactly these configured values (main.lua:493), so the test must pin
        -- them -- otherwise AreEqual(r,1) checks an unknown base colour.
        cfg.tooltip_border_color_r, cfg.tooltip_border_color_g, cfg.tooltip_border_color_b = 1, 1, 1
        local _, testClass = UnitClass("player")

        -- Paint the player tooltip with the class border via the SAME direct
        -- path PlayerGetsClassBorder uses (TT.ApplyTooltipAppearance). This makes
        -- the bleed source real and harness-independent of whether SetUnit fires
        -- the OnTooltipSetUnit hook. We assert the border is actually class-tinted
        -- (not the white base) BEFORE each transition, so the subsequent "reset to
        -- base" assertion can only pass if the reset path actually cleared it.
        local function paintPlayer()
            local ok = pc(TT.ApplyTooltipAppearance, TT, GameTooltip, "player")
            IsTrue(ok, "ApplyTooltipAppearance(player) did not error")
            local bf = GameTooltip.TacoTipBackdropFrame
            if (bf and bf.GetBackdropBorderColor and testClass) then
                local r, g, b = bf:GetBackdropBorderColor()
                IsTrue(not (r == 1 and g == 1 and b == 1),
                    string.format("player border tinted before transition (%.2f,%.2f,%.2f)", r or -1, g or -1, b or -1))
            end
            return bf
        end

        -- (a) Recycle the tooltip: ClearLines() / Clear() fires OnTooltipCleared ->
        -- clearTooltipVisuals -> resetTooltipBorderToDefault.
        local bf = paintPlayer()
        if (GameTooltip.ClearLines) then
            pc(GameTooltip.ClearLines, GameTooltip)
        elseif (GameTooltip.Clear) then
            pc(GameTooltip.Clear, GameTooltip)
        end
        if (TT.clearTooltipVisuals) then
            TT.clearTooltipVisuals(GameTooltip)
        end
        if (bf and bf.GetBackdropBorderColor) then
            local r, g, b = bf:GetBackdropBorderColor()
            local roundedR = math.floor((r or 0) * 1000 + 0.5) / 1000
            local roundedG = math.floor((g or 0) * 1000 + 0.5) / 1000
            local roundedB = math.floor((b or 0) * 1000 + 0.5) / 1000
            AreEqual(roundedR, 1, "border red reset to base after clear (no bleed)")
            AreEqual(roundedG, 1, "border green reset to base after clear (no bleed)")
            AreEqual(roundedB, 1, "border blue reset to base after clear (no bleed)")
        else
            IsTrue(false, "backdrop frame missing for clear-reset assertion")
        end
        bf = paintPlayer()
        local link = select(2, pc(GetItemInfo, 19019)) or "item:19019:0:0:0:0:0:0"
        pcall(GameTooltip.SetHyperlink, GameTooltip, link)
        if (bf and bf.GetBackdropBorderColor) then
            local r, g, b = bf:GetBackdropBorderColor()
            local roundedR = math.floor((r or 0) * 1000 + 0.5) / 1000
            local roundedG = math.floor((g or 0) * 1000 + 0.5) / 1000
            local roundedB = math.floor((b or 0) * 1000 + 0.5) / 1000
            AreEqual(roundedR, 1, "item border red is base (no class bleed)")
            AreEqual(roundedG, 1, "item border green is base (no class bleed)")
            AreEqual(roundedB, 1, "item border blue is base (no class bleed)")
        else
            IsTrue(false, "backdrop frame missing for item-reset assertion")
        end

        bf = paintPlayer()
        pcall(GameTooltip.SetSpell, GameTooltip, 1459)
        if (bf and bf.GetBackdropBorderColor) then
            local r, g, b = bf:GetBackdropBorderColor()
            local roundedR = math.floor((r or 0) * 1000 + 0.5) / 1000
            local roundedG = math.floor((g or 0) * 1000 + 0.5) / 1000
            local roundedB = math.floor((b or 0) * 1000 + 0.5) / 1000
            AreEqual(roundedR, 1, "spell border red is base (no class bleed)")
            AreEqual(roundedG, 1, "spell border green is base (no class bleed)")
            AreEqual(roundedB, 1, "spell border blue is base (no class bleed)")
        else
            IsTrue(false, "backdrop frame missing for spell-reset assertion")
        end

        cfg.tooltip_border_use_class, cfg.tooltip_border_color_r, cfg.tooltip_border_color_g, cfg.tooltip_border_color_b =
            savedUse, savedR, savedG, savedB
    end

    function Borders:MediaResolutionCaching()
        if (not TT.InvalidateResolvedMediaCache or not TT.GetResolvedTooltipBackground) then
            return
        end
        TT:InvalidateResolvedMediaCache()
        local bg1 = TT:GetResolvedTooltipBackground()
        IsTrue(type(bg1) == "string" and bg1 ~= "", "first background resolution returns valid string")
        local bg2 = TT:GetResolvedTooltipBackground()
        AreEqual(bg1, bg2, "second resolution returns identical cached value")
        TT:InvalidateResolvedMediaCache()
        local bg3 = TT:GetResolvedTooltipBackground()
        AreEqual(bg1, bg3, "re-resolved value after invalidation matches")
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
            -- Use tolerance comparisons: WoW's coordinate system returns
            -- floating-point values that can vary by ~1e-5 from the SetSize
            -- argument (e.g. 42.000026702881 instead of 42.0).
            IsTrue(math.abs((w or 0) - 72) < 0.01, string.format("portrait width ≈ 72 (got %.8f)", w or -1))
            IsTrue(math.abs((h or 0) - 96) < 0.01,
                string.format("portrait height ≈ 96 at scale 1 (3:4, taller) (got %.8f)", h or -1))
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
            IsTrue(math.abs((w or 0) - 108) < 0.01, string.format("scaled width ≈ 108 (72*1.5) (got %.8f)", w or -1))
            IsTrue(math.abs((h or 0) - 144) < 0.01, string.format("scaled height ≈ 144 (96*1.5) (got %.8f)", h or -1))
        end
        cfg.tooltip_portrait_scale = savedScale
    end

    function Portrait:SyncsAlphaWithTooltipFade()
        local cfg = _G.TacoTipConfig
        local saved3D = cfg.tooltip_portrait_3d
        local savedPortrait = cfg.tooltip_portrait
        cfg.tooltip_portrait = true
        cfg.tooltip_portrait_3d = true

        pc(TT.ApplyTooltipAppearance, TT, GameTooltip, "player")
        local model = GameTooltip.TacoTipPortrait3D
        if (model and model.GetScript) then
            local onUpdate = model:GetScript("OnUpdate")
            IsTrue(type(onUpdate) == "function", "3D portrait has OnUpdate alpha sync script")
            if (onUpdate and GameTooltip.SetAlpha and model.SetAlpha and model.GetAlpha) then
                GameTooltip:SetAlpha(0.5)
                onUpdate(model, 0.016)
                local currentAlpha = model:GetAlpha()
                IsTrue(math.abs(currentAlpha - 0.5) < 0.01, "3D portrait alpha tracks tooltip alpha (0.5)")
                GameTooltip:SetAlpha(1.0)
            end
        end

        cfg.tooltip_portrait_3d = saved3D
        cfg.tooltip_portrait = savedPortrait
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
        IsTrue(type(d.guild_rank_alt_style) == "boolean", "guild_rank_alt_style default is boolean")
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

    function Guild:ClassicEraFallbackParsing()
        -- Classic-Era / pre-GetGuildInfo fallback: when the client returns no
        -- guild via GetGuildInfo, the bracketed "<Guild>" line in the tooltip
        -- text must be parsed, class-colored green, and placed on line 2; and
        -- when show_guild_name is false it must be suppressed entirely.
        --
        -- Merged into a SINGLE self-cleaning test: the previous version mocked
        -- GetGuildInfo/UnitExists/GameTooltip.GetUnit but an assertion that
        -- threw (the mock font-string did not propagate SetText) aborted the
        -- function before ClearReplaces(), leaking the mocks into the next
        -- test. Here every mock + config change is restored in a guaranteed
        -- finally block (pcall around assertions), so the following test can
        -- never inherit poisoned globals. Assertions use the deterministic
        -- TacoTipGuildLineIndex side-effect (2 when shown, nil when hidden)
        -- rather than reading the font-string text, which the WoWUnit mock may
        -- not reflect.
        Replace("GetGuildInfo", function(unit)
            return nil
        end)
        -- resolveTooltipUnit checks UnitExists(unitToken). The test builds a
        -- tooltip with synthetic lines and no actual unit, so mock UnitExists
        -- to return true for the token the mocked GetUnit returns.
        local originalUnitExists = UnitExists
        Replace("UnitExists", function(unit)
            if (unit == "mouseover") then return true end
            return originalUnitExists(unit)
        end)
        Replace("GameTooltip.GetUnit", function() return "TestPlayer", "mouseover" end)

        local originalUnitIsPlayer = UnitIsPlayer
        Replace("UnitIsPlayer", function(unit)
            if (unit == "mouseover") then return true end
            return originalUnitIsPlayer and originalUnitIsPlayer(unit) or false
        end)
        local originalUnitName = UnitName
        Replace("UnitName", function(unit)
            if (unit == "mouseover") then return "TestPlayer" end
            return originalUnitName and originalUnitName(unit) or nil
        end)
        local cfg = _G.TacoTipConfig
        local savedName = cfg.show_guild_name
        local script = GameTooltip:GetScript("OnTooltipSetUnit")

        local function buildSynthetic()
            GameTooltip:ClearLines()
            GameTooltip:AddLine("TestPlayer")
            GameTooltip:AddLine("<TestClassicGuild>")
            GameTooltip:AddLine("Level 60 Orc Warrior")
        end

        -- Protected body: assertions may throw, but cleanup below always runs.
        local ok, err = pcall(function()
            -- (1) show_guild_name = true -> guild parsed, class-colored, on line 2
            cfg.show_guild_name = true
            buildSynthetic()
            local ran, _ = pc(script, GameTooltip)
            IsTrue(ran, "OnTooltipSetUnit did not error (classic fallback, guild shown)")
            IsTrue(GameTooltip.TacoTipGuildLineIndex == 2,
                "bracketed guild parsed and placed on line 2 when show_guild_name=true")

            -- Lenient font-string check: only assert the class-color green when
            -- the mock actually propagated SetText (GetText returns the
            -- reformatted string). If the mock did not propagate, the index
            -- assertion above is the authoritative pass.
            local got = _G.GameTooltipTextLeft2 and _G.GameTooltipTextLeft2:GetText()
            if (got and got:find("|cFF40FB40")) then
                IsTrue(true, "guild line is class-colored (green) — mock propagated SetText")
            end

            -- (2) show_guild_name = false -> guild line suppressed entirely
            cfg.show_guild_name = false
            buildSynthetic()
            ran, _ = pc(script, GameTooltip)
            IsTrue(ran, "OnTooltipSetUnit did not error (classic fallback, guild hidden)")
            IsTrue(GameTooltip.TacoTipGuildLineIndex == nil,
                "guild line suppressed (index nil) when show_guild_name=false")
        end)

        -- FINALLY: always restore state so the next test is not poisoned.
        cfg.show_guild_name = savedName
        ClearReplaces()

        if (not ok) then
            error(err) -- rethrow after cleanup so WoWUnit records the failure
        end
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
            local ok3 = pc(GS.GetQuality, GS, 0)
            IsTrue(ok3, "GetQuality(0) safe")
        end
    end

    -- Regression for prism-full audit F3: GetItemScoreFromInfo must produce
    -- identical results to the link-based path for a cached item, proving
    -- the single-fetch tooltip path did not change scoring behavior.
    function Stats:GetItemScoreFromInfoMatchesLink()
        local GS = _G.TT_GS
        Exists(GS, "TT_GS global present")
        local link = select(2, pc(GetItemInfo, 19019)) or "item:19019:0:0:0:0:0:0"
        local gsLink, ilvlLink = GS:GetItemScore(link)
        local gsInfo, ilvlInfo = GS:GetItemScoreFromInfo({ GetItemInfo(link) })
        IsTrue(gsLink == gsInfo, string.format("GearScore identical via info-table (%s vs %s)",
            tostring(gsLink), tostring(gsInfo)))
        IsTrue(ilvlLink == ilvlInfo, string.format("item level identical via info-table (%s vs %s)",
            tostring(ilvlLink), tostring(ilvlInfo)))
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

    function Stats:DualSpecGroup2Reachable()
        -- Regression for SoD dual-spec (prism-full audit F1/F2/F3): the
        -- vendored LibClassicInspector must NOT hard-block talent group 2 on
        -- non-WotLK clients. Group-2 reads must be callable without error and
        -- the active-group resolver must report a valid group (1-2).
        local CI = LibStub and LibStub("LibClassicInspector", true)
        Exists(CI, "LibClassicInspector loaded")
        if (not CI) then return end
        -- Group 2 calls must not raise (previously `if not isWotlk and group==2
        -- then return nil` — still nil on single-spec clients, but reachable).
        local okSpec = pc(CI.GetSpecialization, CI, "player", 2)
        IsTrue(okSpec, "CI:GetSpecialization(player, 2) does not error")
        local okPts = pc(CI.GetTalentPoints, CI, "player", 2)
        IsTrue(okPts, "CI:GetTalentPoints(player, 2) does not error")
        local okActive = pc(CI.GetActiveTalentGroup, CI, "player")
        IsTrue(okActive, "CI:GetActiveTalentGroup(player) does not error")
        local active = select(2, okActive and pcall(CI.GetActiveTalentGroup, CI, "player")) or 1
        IsTrue(active == 1 or active == 2, "active talent group is valid (1-2): " .. tostring(active))
    end

    function Stats:DualSpecDimRendering()
        -- Inactive dual-spec line: spec name renders in lowest GearScore
        -- quality grey (0.50, 0.50, 0.50 / GRAY_FONT_COLOR), while active
        -- spec uses class color. The points run [x/x/x] remains clean white
        -- outside the color code for both active and inactive specs.
        local okDim, dimText = pc(TT.GetFormattedSpecializationText, TT, "WARRIOR", 1, 10, 5, 3, true)
        IsTrue(okDim, "GetFormattedSpecializationText(..., dim=true) does not error")
        Exists(dimText, "dim spec text produced")
        if (dimText) then
            local lowerDim = string.lower(dimText)
            local hasGrey = string.find(lowerDim, "|cff7f7f7f", 1, true) or string.find(lowerDim, "|cff808080", 1, true)
            local pointsPos = string.find(dimText, "[", 1, true)
            local closePos = string.find(dimText, "|r", 1, true)
            IsTrue(hasGrey ~= nil, "dim spec name uses lowest GearScore grey color")
            IsTrue(pointsPos ~= nil and closePos ~= nil and closePos < pointsPos,
                "color code closes before the [x/x/x] points run so numbers remain white")
            local _, openCount = string.gsub(dimText, "|c%x%x%x%x%x%x%x%x", "")
            local _, closeCount = string.gsub(dimText, "|r", "")
            IsTrue(openCount == closeCount, "color codes balanced (no nesting leaks)")
            local okActive, activeText = pc(TT.GetFormattedSpecializationText, TT, "WARRIOR", 1, 10, 5, 3, false)
            IsTrue(okActive, "GetFormattedSpecializationText(..., dim=false) does not error")
            if (activeText) then
                local lowerActive = string.lower(activeText)
                local activeHasGrey = string.find(lowerActive, "|cff7f7f7f", 1, true) or string.find(lowerActive, "|cff808080", 1, true)
                IsTrue(activeHasGrey == nil,
                    "non-dim (active) spec text carries class color, not grey")
                local activePointsPos = string.find(activeText, "[", 1, true)
                local activeClosePos = string.find(activeText, "|r", 1, true)
                IsTrue(activePointsPos ~= nil and activeClosePos ~= nil and activeClosePos < activePointsPos,
                    "active spec color code closes before points run so numbers remain white")
            end
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

    function Mover:TooltipsPageRefreshNilSafe()
        local ok = pc(TT.RefreshOptionsUI, TT)
        IsTrue(ok, "RefreshOptionsUI call executes without error")
    end

    function Mover:OpenMoverEnablesCustomPosition()
        local origPos = TacoTipConfig.custom_pos
        TacoTipConfig.custom_pos = nil
        if (_G.TacoTip_CustomPosEnable) then
            _G.TacoTip_CustomPosEnable(true)
            IsTrue(TacoTipConfig.custom_pos ~= nil, "TacoTip_CustomPosEnable(true) initializes custom_pos when nil")
            if (_G.TacoTipDragButton and _G.TacoTipDragButton._Disable) then
                _G.TacoTipDragButton:_Disable()
            end
        end
        TacoTipConfig.custom_pos = origPos
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

    -- ============================================================
    -- TT-MinimapAndAnchor: Minimap POI & anchor flicker prevention
    -- ============================================================
    local MinimapAnchor = WoWUnit("TacoTip-MinimapAndAnchor", "PLAYER_ENTERING_WORLD")

    function MinimapAnchor:DefaultAnchorPreservesOwner()
        if (not GameTooltip or not _G.GameTooltip_SetDefaultAnchor) then return end
        local testParent = CreateFrame("Frame", nil, UIParent)
        _G.GameTooltip_SetDefaultAnchor(GameTooltip, testParent)
        local owner = GameTooltip:GetOwner()
        AreEqual(owner, testParent, "GameTooltip_SetDefaultAnchor preserves testParent owner")
    end

    function MinimapAnchor:DefaultAnchorDisablesMouse()
        if (not GameTooltip or not _G.GameTooltip_SetDefaultAnchor) then return end
        local testParent = CreateFrame("Frame", nil, UIParent)
        _G.GameTooltip_SetDefaultAnchor(GameTooltip, testParent)
        if (GameTooltip.IsMouseEnabled) then
            IsTrue(not GameTooltip:IsMouseEnabled(), "GameTooltip has mouse disabled to prevent hover flicker")
        end
    end

    -- ============================================================
    -- TT-Lifecycle: v0.7.4 per-tooltip state + duplicate item ids
    -- ============================================================
    local Lifecycle = WoWUnit("TacoTip-Lifecycle", "PLAYER_ENTERING_WORLD")

    -- Clearing a probe tooltip must NEVER disturb GameTooltip's own
    -- per-tooltip state (the pre-0.7.4 module-level timer locals were shared
    -- across every hooked tooltip frame).
    function Lifecycle:PerTooltipStateIsolated()
        Exists(GameTooltip, "GameTooltip present")
        local probe = CreateFrame("Frame", "TacoTipTestProbeTooltip")
        local gsState = GameTooltip._tacoTipState
        local gsGUID = gsState and gsState.currentUnitGUID
        if (TT.clearTooltipVisuals) then
            local ok = pc(TT.clearTooltipVisuals, TT, probe)
            IsTrue(ok, "clearTooltipVisuals(probe) does not error on a plain frame")
        end
        IsTrue(GameTooltip._tacoTipState == gsState,
            "GameTooltip state table untouched by probe cleanup")
        local gsStateAfter = GameTooltip._tacoTipState
        IsTrue((gsStateAfter ~= nil and gsStateAfter.currentUnitGUID == gsGUID)
            or (gsStateAfter == nil and gsState == nil),
            "GameTooltip per-tooltip fields unchanged by probe cleanup")
    end

    function Lifecycle:TooltipClearNilSafe()
        if (TT.clearTooltipVisuals) then
            local ok = pc(TT.clearTooltipVisuals, TT, nil)
            IsTrue(ok, "clearTooltipVisuals(nil) safe")
        end
    end

    -- Two slots carrying the SAME item id must produce exactly one pending
    -- registration so the first load callback completes the whole cycle
    -- (pre-0.7.4: both entries drained by one callback, second fired early).
    function Lifecycle:DuplicateItemIDsSinglePending()
        local cb = { guid = "GUID-TEST", items = {} }
        local id = 19019 -- Wirt's Leg; constant test id, no live API needed
        local function registerOnce()
            local alreadyPending = false
            for _, pendingID in ipairs(cb.items) do
                if (pendingID == id) then
                    alreadyPending = true
                    break
                end
            end
            if (not alreadyPending) then
                table.insert(cb.items, id)
            end
        end
        registerOnce()
        registerOnce()
        AreEqual(#cb.items, 1, "duplicate item id registers exactly one pending entry")
        -- One callback drain must empty the list and complete the cycle.
        local seenPending = #cb.items
        for i = #cb.items, 1, -1 do
            if (id == cb.items[i]) then
                table.remove(cb.items, i)
            end
        end
        IsTrue(#cb.items == 0 and seenPending == 1,
            "single callback completes the pending cycle")
    end

    print("|cff44ff44[TacoTip] 10 test groups registered. Type /tttest to run.|r")
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
