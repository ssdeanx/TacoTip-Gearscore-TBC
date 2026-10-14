-- luacheck: globals WoWUnit SLASH_TTTEST1 SLASH_TTTEST2 SlashCmdList
---@diagnostic disable: undefined-global
-- ============================================================
-- File role: WoWUnit in-game test suite for TacoTip Forever
-- Target: Universal Cross-Client (Classic Era, TBC, WotLK, Forever, Retail)
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
        -- "## Interface: 11509, 20506, 38002, 16001, 110002, 110100, 110200, 120000, 120100".
        -- One entry per supported client family: Classic Era, TBC Anniversary,
        -- WotLK Titanforge (38002, NOT 38001), WoW Forever, and Retail.
        local interfaceStr = toc or "11509, 20506, 38002, 16001, 110002"
        IsTrue(ok and (interfaceStr:find("11509") ~= nil and interfaceStr:find("20506") ~= nil and
                       interfaceStr:find("38002") ~= nil and interfaceStr:find("16001") ~= nil and
                       interfaceStr:find("110002") ~= nil),
            "Universal cross-engine interfaces advertised: " .. tostring(toc or interfaceStr))
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

    -- Non-Unit Visual Isolation: a player tooltip (class border applied) must
    -- NOT leave its class tint on any subsequent non-unit transition:
    --   (a) player -> Clear()            -> non-unit
    --   (b) player -> SetHyperlink(item) -> item
    --   (c) player -> SetSpell()         -> spell
    -- Items, spells, and cleared tooltips must never inherit stale unit state.
    function Borders:NonUnitVisualIsolation()
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
                onUpdate(model, 0.05)
                local currentAlpha = model:GetAlpha()
                IsTrue(math.abs(currentAlpha - 0.5) < 0.01, "3D portrait alpha tracks tooltip alpha (0.5)")
                GameTooltip:SetAlpha(1.0)
            end
        end

        cfg.tooltip_portrait_3d = saved3D
        cfg.tooltip_portrait = savedPortrait
    end

    -- ============================================================
    -- TT-Guild: GetGuildInfo path
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

    function Guild:TooltipTextFallbackParsing()
        -- Tooltip text fallback: when the client returns no
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
            GameTooltip:AddLine("<TestGuild>")
            GameTooltip:AddLine("Level 60 Orc Warrior")
        end

        -- Protected body: assertions may throw, but cleanup below always runs.
        local ok, err = pcall(function()
            -- (1) show_guild_name = true -> guild parsed, class-colored, on line 2
            cfg.show_guild_name = true
            buildSynthetic()
            local ran, _ = pc(script, GameTooltip)
            IsTrue(ran, "OnTooltipSetUnit did not error (fallback, guild shown)")
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
            IsTrue(ran, "OnTooltipSetUnit did not error (fallback, guild hidden)")
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

    function Stats:ForeverInspectorPresent()
        local CI = LibStub and LibStub("LibForeverInspector", true)
        Exists(CI, "LibForeverInspector loaded")
        if (CI) then
            local ok = pc(CI.GetSpecializationName, CI, "WARRIOR", 1, true)
            IsTrue(ok, "CI:GetSpecializationName safe")
        end
    end

    function Stats:InspectorMultiEngineDetection()
        local CI = LibStub and LibStub("LibForeverInspector", true)
        Exists(CI, "LibForeverInspector loaded")
        if (CI) then
            for _, m in ipairs({ "IsClassic", "IsTBC", "IsWotlk", "IsForever", "IsRetail" }) do
                Exists(CI[m], "CI." .. m)
                local ok, isEngine = pc(CI[m], CI)
                IsTrue(ok and type(isEngine) == "boolean", m .. " returns boolean")
            end
        end
    end

    function Stats:LibClassicInspectorAlias()
        if (LibStub) then
            local CI = LibStub("LibForeverInspector", true)
            local alias = LibStub("LibClassicInspector", true)
            IsTrue(alias ~= nil and alias == CI, "LibClassicInspector alias resolves to LibForeverInspector")
        end
    end

    function Stats:GearScoreMultiEngineQuality()
        local GS = _G.TT_GS
        Exists(GS, "TT_GS present")
        if (GS) then
            IsTrue(type(GS.BRACKET_SIZE) == "number" and GS.BRACKET_SIZE > 0, "BRACKET_SIZE is positive")
            local r, g, b = GS:GetQuality(0)
            IsTrue(r and g and b, "GetQuality(0) returns color")
            -- Use the real ceiling. A hardcoded 7000 is 1000*7, which is only the
            -- ceiling for the 1000-bracket clients; on Classic Era the max is
            -- 1400 and on TBC 2800. The old literal passed only because
            -- GetQuality clamps, so it asserted against the wrong bound.
            IsTrue(type(GS.MAX_SCORE) == "number" and GS.MAX_SCORE > 0, "MAX_SCORE is positive")
            local rMax, gMax, bMax = GS:GetQuality(GS.MAX_SCORE)
            IsTrue(rMax and gMax and bMax, "GetQuality(MAX_SCORE) returns color")
            -- The bracket must agree with the detected client family.
            local ci = LibStub and LibStub("LibForeverInspector", true)
            if (ci) then
                local expected
                if ci:IsClassic() then expected = 200
                elseif ci:IsTBC() then expected = 400
                elseif ci:IsForever() then expected = 200
                else expected = 1000 end
                IsTrue(GS.BRACKET_SIZE == expected,
                    string.format("BRACKET_SIZE %d matches family %s (expected %d)",
                        GS.BRACKET_SIZE, tostring(ci.family), expected))
            end
        end
    end

    -- Pawn rejects an unknown scale by RAISING ("ScaleName must be the name of
    -- an existing scale, and is case-sensitive."); it does not return false. So
    -- an unguarded probe with a name Pawn lacks escapes TT_PAWN:GetScore, escapes
    -- onTooltipSetUnit, and is printed to the chat frame by the tooltip
    -- pipeline's error handler, once per player tooltip render and once per unit
    -- frame refresh. Pawn's real behaviour cannot be mocked, so this has to be
    -- asserted in game.
    --
    -- The previous version of this test passed scale-looking STRINGS as the
    -- unitorguid argument. getPlayerGUID rejected them, so GetScore returned at
    -- its early-out and none of the scale-name code ran: it asserted nothing.
    function Stats:PawnScaleNameContract()
        local Pawn = _G.TT_PAWN
        Exists(Pawn, "TT_PAWN present")
        if (not (Pawn and Pawn.GetScore)) then return end

        local guid = UnitGUID("player")
        IsTrue((type(guid) == "string") and (#guid > 0), "player GUID available")

        local seen, probed = {}, 0
        local realScaleColor = _G.PawnGetScaleColor
        local realIsVisible = _G.PawnIsScaleVisible
        if (type(realScaleColor) == "function") then
            _G.PawnGetScaleColor = function(name, ...)
                seen[#seen + 1] = name
                return realScaleColor(name, ...)
            end
        end
        if (type(realIsVisible) == "function") then
            _G.PawnIsScaleVisible = function(...)
                probed = probed + 1
                return realIsVisible(...)
            end
        end

        local ok = pc(Pawn.GetScore, Pawn, guid, false)
        IsTrue(ok, "Pawn:GetScore(player) does not error")
        IsTrue(probed == 0, "Pawn scale visibility is never probed (probed " .. probed .. "x)")

        -- The causal invariant, and the only one that matters: every name handed
        -- to PawnGetScaleColor must already exist in PawnCommon.Scales, the exact
        -- table Pawn looks the name up in. A name that is absent makes Pawn call
        -- VgerCore.Fail, which prints straight to the chat frame -- not an error,
        -- so pcall cannot suppress it. Pawn's two providers are gated by game type
        -- in Pawn.toc, so the correct library differs between clients.
        local scales = _G.PawnCommon and _G.PawnCommon.Scales
        local offender
        for _, name in ipairs(seen) do
            if (not (scales and scales[name])) then
                offender = tostring(name)
                break
            end
        end
        IsTrue((offender == nil),
            "every Pawn scale name exists in PawnCommon.Scales (offender: "
                .. tostring(offender) .. ")")

        -- Guards the check above against passing vacuously.
        IsTrue(#seen > 0, "a Pawn scale name was actually requested (seen=" .. #seen .. ")")

        if (type(realScaleColor) == "function") then _G.PawnGetScaleColor = realScaleColor end
        if (type(realIsVisible) == "function") then _G.PawnIsScaleVisible = realIsVisible end
    end

    function Stats:SpecializationReachable()
        local CI = LibStub and LibStub("LibForeverInspector", true)
        Exists(CI, "LibForeverInspector loaded")
        if (not CI) then return end
        local okSpec = pc(CI.GetSpecialization, CI, "player", 1)
        IsTrue(okSpec, "CI:GetSpecialization(player, 1) does not error")
        local okPts = pc(CI.GetTalentPoints, CI, "player", 1)
        IsTrue(okPts, "CI:GetTalentPoints(player, 1) does not error")
        local okActive = pc(CI.GetActiveTalentGroup, CI, "player")
        IsTrue(okActive, "CI:GetActiveTalentGroup(player) does not error")
        local active = select(2, okActive and pcall(CI.GetActiveTalentGroup, CI, "player")) or 1
        IsTrue(active >= 1, "active talent group is valid: " .. tostring(active))
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

    function Modules:InspectorMultiEngineGating()
        local ci = LibStub and LibStub("LibForeverInspector", true)
        Exists(ci, "LibForeverInspector loaded")
        if (ci) then
            IsTrue(type(ci.IsRetail) == "function", "IsRetail method exists")
            IsTrue(type(ci.IsForever) == "function", "IsForever method exists")
            IsTrue(type(ci.IsClassic) == "function", "IsClassic method exists")
            IsTrue(type(ci.IsTBC) == "function", "IsTBC method exists")
            IsTrue(type(ci.IsWotlk) == "function", "IsWotlk method exists")
            IsTrue(type(ci:IsRetail()) == "boolean", "IsRetail returns boolean")
            IsTrue(type(ci:IsForever()) == "boolean", "IsForever returns boolean")
        end
    end

    function Modules:InspectorTalentsCrossEnginePoints()
        local ci = LibStub and LibStub("LibForeverInspector", true)
        if (ci) then
            local p1, p2, p3 = ci:GetTalentPoints("player", 1)
            IsTrue(type(p1) == "number" and type(p2) == "number" and type(p3) == "number",
                "GetTalentPoints returns numeric point values")

            -- Invariant, not a magic number: talent points are small integers,
            -- while the icon fileIDs that once leaked into this slot are 6
            -- digits. Only checking "is a number" passed while the tooltip was
            -- printing [132164/132222/132215].
            local plausible = true
            for _, v in ipairs({ p1, p2, p3 }) do
                if (v < 0 or v > 200) then plausible = false end
            end
            IsTrue(plausible, "talent points are small integers, not icon fileIDs",
                string.format("got %s/%s/%s", tostring(p1), tostring(p2), tostring(p3)))

            -- Group 2 must be handled, not silently dropped or aliased to
            -- group 1. The old inspect cache hardcoded group 1, which is why an
            -- inspected dual-spec'd player showed the wrong active spec.
            local q1, q2, q3 = ci:GetTalentPoints("player", 2)
            IsTrue(type(q1) == "number" and type(q2) == "number" and type(q3) == "number",
                "GetTalentPoints returns numeric point values for group 2")
        end
    end

    function Modules:InspectorTalentsSpecIndexIsAnIndex()
        local ci = LibStub and LibStub("LibForeverInspector", true)
        if (not ci) then return end
        -- Must be a 1-based tab/spec index (1..3), NOT a specID such as 71/72.
        -- Returning a specID made spec_table[class][id] nil, which removed the
        -- whole specialization line on Retail and WoW Forever.
        for group = 1, 2 do
            local ok, idx = pcall(ci.GetSpecialization, ci, "player", group)
            if (ok and type(idx) == "number") then
                IsTrue(idx >= 1 and idx <= 3,
                    string.format("GetSpecialization(player, %d) is a 1-based index", group),
                    "got " .. tostring(idx))
            end
        end
    end

    function Modules:InspectorTalentsActiveGroupResolves()
        local ci = LibStub and LibStub("LibForeverInspector", true)
        if (not ci) then return end
        -- The tooltip greys whichever group is NOT active, so this must be 1 or
        -- 2. It used to return 1 unconditionally for inspected units, pinning
        -- the greyed specialization regardless of the real active group.
        local ok, g = pcall(ci.GetActiveTalentGroup, ci, "player")
        IsTrue(ok and g == 1 or g == 2, "GetActiveTalentGroup returns 1 or 2",
            tostring(g))
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

    -- ========================================================================
    -- Cross-client detection + locale. Neither had any coverage, which is how
    -- the dead locale registry and the mis-detected Classic families shipped.
    -- ========================================================================
    local Client = WoWUnit("TacoTip-Client", "PLAYER_ENTERING_WORLD")

    -- The single most useful in-game assertion: if this fails, main.lua raised an
    -- error while loading and every feature defined after that point -- the
    -- tooltip hooks, the mover, the overlays -- is silently absent while the
    -- options frame keeps working. LOAD_STAGE names the region to look at.
    function Client:LoadCompleted()
        local tt = _G.TacoTip_Forever
        Exists(tt, "TacoTip_Forever namespace present")
        if (not tt) then return end
        IsTrue(tt.LOAD_OK == true,
            "main.lua loaded to completion (stage=" .. tostring(tt.LOAD_STAGE) .. ")")
        IsTrue(_G.TacoTip_CustomPosEnable ~= nil, "TacoTip_CustomPosEnable defined")
        IsTrue(type(tt.PrintDiagnostics) == "function", "TT.PrintDiagnostics present")
    end

    -- Backdrop template contract. Retail and WoW Forever use
    -- SharedTooltipArtTemplate, which has a NineSlice child and does NOT mix in
    -- BackdropTemplateMixin, so GameTooltip has no SetBackdrop even though it
    -- renders correctly. The Classic family has neither, and keeps the legacy
    -- SetBackdrop fallback.
    function Client:BackdropTemplateContract()
        local ci = LibStub and LibStub("LibForeverInspector", true)
        if (not ci or not _G.TacoTip_Forever or not _G.GameTooltip) then return end
        if (ci:IsRetail() or ci:IsForever()) then
            IsTrue(_G.GameTooltip.NineSlice ~= nil, "modern tooltip has a NineSlice child")
            IsTrue(_G.GameTooltip.SetBackdrop == nil,
                "BackdropTemplateMixin is not grafted onto a NineSlice tooltip")
        else
            IsTrue(_G.GameTooltip.NineSlice == nil, "Classic tooltip has no NineSlice child")
            IsTrue(type(_G.GameTooltip.SetBackdrop) == "function",
                "Classic tooltip keeps the legacy SetBackdrop fallback")
        end
    end

    -- Tooltip delivery path. Retail and WoW Forever dropped OnTooltipSetUnit,
    -- OnTooltipSetItem and OnTooltipSetSpell from their tooltip template, so the
    -- addon must NOT hook them there -- an unguarded HookScript raises at file
    -- scope and silently kills everything defined after it. The Classic family
    -- still declares all three, and the script hooks are the live path there.
    function Client:TooltipDeliveryPath()
        local ci = LibStub and LibStub("LibForeverInspector", true)
        local gt = _G.GameTooltip
        if (not ci or not gt or not gt.HasScript) then return end
        local modern = ci:IsRetail() or ci:IsForever()
        IsTrue(gt:HasScript("OnTooltipSetUnit") == (not modern),
            "OnTooltipSetUnit exists iff this is a Classic client")
        IsTrue(gt:HasScript("OnTooltipSetItem") == (not modern),
            "OnTooltipSetItem exists iff this is a Classic client")
        local hooked = _G.TacoTip_Forever and _G.TacoTip_Forever.HookedTooltipScripts
        IsTrue(type(hooked) == "table", "TT.HookedTooltipScripts recorded")
        if (hooked) then
            IsTrue(hooked.Unit ~= nil, "a unit tooltip delivery path was installed")
            IsTrue(hooked.Item ~= nil, "an item tooltip delivery path was installed")
            if (modern) then
                IsTrue(hooked.Unit == "postcall", "modern clients deliver units by post-call")
                IsTrue(hooked.Item == "postcall", "modern clients deliver items by post-call")
            end
        end
    end

    -- CreateFrame rejects widget types. "Texture" is a WIDGET type created with
    -- frame:CreateTexture(); the spec-icon overlay used CreateFrame("Texture"),
    -- which threw on every unit tooltip on the two clients that use that overlay.
    function Client:WidgetTypesAreNotFrameTypes()
        local ok, err = pcall(CreateFrame, "Texture", nil, _G.UIParent)
        IsTrue(not ok, "CreateFrame('Texture') is rejected by the client")
        IsTrue(tostring(err):find("Unknown frame type") ~= nil,
            "and the error names the frame type: " .. tostring(err))
    end

    -- Texture is a Region on Retail and WoW Forever, not a Frame, so the frame
    -- level / strata methods do not exist on it there. The specialisation-icon
    -- overlay called SetFrameLevel and raised "attempt to call a nil value" on
    -- every unit tooltip. On the Classic family a Texture does inherit Frame, so
    -- the same call is valid there. This test pins that split so a future edit
    -- cannot reintroduce the assumption silently.
    function Client:TextureIsARegion()
        local ci = LibStub and LibStub("LibForeverInspector", true)
        if (not ci or not _G.UIParent) then return end
        local modern = ci:IsRetail() or ci:IsForever()
        local tex = _G.UIParent:CreateTexture(nil, "ARTWORK")
        -- Region methods: present on every client.
        IsTrue(type(tex.SetSize) == "function", "Texture has SetSize")
        IsTrue(type(tex.SetPoint) == "function", "Texture has SetPoint")
        IsTrue(type(tex.SetTexture) == "function", "Texture has SetTexture")
        IsTrue(type(tex.ClearAllPoints) == "function", "Texture has ClearAllPoints")
        IsTrue(type(tex.Hide) == "function", "Texture has Hide")
        IsTrue(type(tex.Show) == "function", "Texture has Show")
        if (modern) then
            IsTrue(tex.SetFrameLevel == nil,
                "modern Texture has no SetFrameLevel (it is a Region)")
            IsTrue(tex.SetFrameStrata == nil,
                "modern Texture has no SetFrameStrata (it is a Region)")
        else
            IsTrue(type(tex.SetFrameLevel) == "function",
                "Classic Texture inherits Frame and does have SetFrameLevel")
        end
    end

    -- CharacterModelFrame is a CLASSIC-ONLY frame. The Classic family nests a
    -- PlayerModel by that name inside PaperDollFrame; Retail removed it and
    -- keeps only PaperDollFrame. The addon used to index the missing global on
    -- every options refresh, which threw whenever the options frame was opened
    -- while the character pane was shown. The overlay font strings must be
    -- parented to whichever host exists, so the feature works on both rather
    -- than merely avoiding the crash.
    function Client:CharacterFrameHostExists()
        local ci = LibStub and LibStub("LibForeverInspector", true)
        if (not ci) then return end
        local modern = ci:IsRetail() or ci:IsForever()
        if (modern) then
            IsTrue(_G.CharacterModelFrame == nil,
                "modern client has no CharacterModelFrame")
            IsTrue(_G.PaperDollFrame ~= nil,
                "modern client still has PaperDollFrame to host the overlay")
        else
            IsTrue(_G.CharacterModelFrame ~= nil,
                "Classic client has CharacterModelFrame")
            IsTrue(_G.PaperDollFrame ~= nil, "Classic client has PaperDollFrame")
        end
        -- Whichever host the addon resolves must exist, or the overlay is skipped.
        IsTrue((_G.CharacterModelFrame or _G.PaperDollFrame) ~= nil,
            "an overlay host frame is always available")
    end

    function Client:DetectionResolves()
        local ci = LibStub and LibStub("LibForeverInspector", true)
        Exists(ci, "LibForeverInspector present")
        if (not ci) then return end

        IsTrue(type(ci.family) == "string" and ci.family ~= "",
            "family is set: " .. tostring(ci.family))

        -- Exactly one family flag must be true. Before the detection rewrite a
        -- client could satisfy none of them (or two at once), and every
        -- consumer silently took a default.
        local flags = { "IsClassic", "IsTBC", "IsWotlk", "IsForever", "IsRetail" }
        local set = 0
        for _, f in ipairs(flags) do
            if ci[f](ci) then set = set + 1 end
        end
        if (ci:IsUnknown()) then
            IsTrue(set == 0, "unknown client sets no family flag (set=" .. set .. ")")
        else
            IsTrue(set == 1, "exactly one family flag set (got " .. set .. ")")
        end

        IsTrue(type(ci.interfaceVersion) == "number" and ci.interfaceVersion > 0,
            "interfaceVersion resolved: " .. tostring(ci.interfaceVersion))
        IsTrue(type(ci.IsUnknown) == "function", "IsUnknown available")
        Exists(ci.caps, "caps table present")
    end

    function Client:LegacyAliasResolves()
        local viaModern = LibStub("LibForeverInspector", true)
        local viaAlias, aliasMinor = LibStub("LibClassicInspector", true)
        IsTrue(viaAlias == viaModern, "LibClassicInspector aliases LibForeverInspector")
        IsTrue(aliasMinor ~= nil, "alias carries a minor version: " .. tostring(aliasMinor))
    end

    function Client:LocaleRegistryComplete()
        local locales = _G.TACOTIP_LOCALES
        Exists(locales, "TACOTIP_LOCALES present")
        if (not locales) then return end
        for _, code in ipairs({ "enUS", "deDE", "esES", "esMX", "frFR", "itIT",
                                "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }) do
            Exists(locales[code], "locale registered: " .. code)
        end
    end

    function Client:LocaleIsFullyPopulated()
        local L = _G.TACOTIP_LOCALE
        Exists(L, "TACOTIP_LOCALE present")
        if (not L) then return end
        local n = 0
        for _ in pairs(L) do n = n + 1 end
        IsTrue(n >= 251, "locale has the full key set (got " .. n .. ", expected >= 251)")

        -- The selected language must be one we actually ship, and must match
        -- the client locale when no override is saved.
        local active = _G.TACOTIP_ACTIVE_LOCALE
        IsTrue(type(active) == "string", "active locale recorded: " .. tostring(active))
        if (type(active) == "string") then
            local known = false
            for _, code in ipairs({ "enUS", "deDE", "esES", "esMX", "frFR", "itIT",
                                    "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }) do
                if (code == active) then known = true end
            end
            IsTrue(known, "active locale is a shipped locale: " .. tostring(active))
            if (not (TacoTipConfig and TacoTipConfig.locale_override)) then
                local client = GetLocale()
                if (client == "enGB") then client = "enUS" end
                IsTrue(active == client,
                    "active locale follows the client locale (" .. active .. " vs " .. client .. ")")
            end
        end
    end

    function Client:LocaleOverrideIsHonoured()
        if (not _G.TacoTipApplyLocale) then
            IsTrue(false, "TacoTipApplyLocale missing")
            return
        end
        local saved = TacoTipConfig and TacoTipConfig.locale_override
        local probe = "deDE"
        if (GetLocale() == "deDE") then probe = "enUS" end
        if (TacoTipConfig) then TacoTipConfig.locale_override = probe end
        local ok = pc(_G.TacoTipApplyLocale)
        IsTrue(ok, "TacoTipApplyLocale runs with an override set")
        if (ok) then
            IsTrue(_G.TACOTIP_ACTIVE_LOCALE == probe,
                "override applied: expected " .. probe .. ", got " .. tostring(_G.TACOTIP_ACTIVE_LOCALE))
        end
        if (TacoTipConfig) then TacoTipConfig.locale_override = saved end
        if (_G.TacoTipApplyLocale) then pc(_G.TacoTipApplyLocale) end
    end

    function Client:FontListIsClientFiltered()
        local TTt = _G[addonName] or TT
        if (not (TTt and TTt.builtinTooltipFonts)) then return end
        local isCJK = (GetLocale() == "zhCN" or GetLocale() == "zhTW")
        local cjk, details = 0, 0
        for _, e in ipairs(TTt.builtinTooltipFonts) do
            if (e.value and e.value:find("Fonts\\ZY", 1, true)) then cjk = cjk + 1 end
            if (e.value and e.value:find("FNT_Details_", 1, true)) then details = details + 1 end
        end
        IsTrue(details == 0, "no third-party Details fonts in the built-in list")
        if (isCJK) then
            IsTrue(cjk > 0, "CJK fonts offered on a CJK client")
        else
            IsTrue(cjk == 0, "CJK fonts hidden on a non-CJK client (got " .. cjk .. ")")
        end
    end

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
if (SlashCmdList) then
    rawset(SlashCmdList, "TTTEST", function()
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
    end)
end

if (TT) then
    TT.RegisterTacoTipTests = RegisterTacoTipTests
end

if (CreateFrame) then
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
end
