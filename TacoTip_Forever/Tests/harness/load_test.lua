-- End-to-end load of the whole addon under a mocked client, asserting it does
-- not raise and that the cross-client wiring lands correctly.
-- Usage: lua5.1 loadtest.lua <projectId> <interface> <layout> <expectFamily> <expectBracket>

local ROOT = (os.getenv("TACOTIP_TEST_ROOT") or ".") .. "/"

local projectId, iface, layout = tonumber(arg[1]), tonumber(arg[2]), arg[3]
-- Optional: blank out a Blizzard global before load, to prove that a file-scope
-- operation depending on it is guarded rather than fatal. main.lua is the last
-- file in the toc and every feature it defines after a throw is silently lost.
local missingGlobal = arg[8]
local expectFamily, expectBracket = arg[4], tonumber(arg[5])
local label = arg[6] or ""
local usePipeline = (arg[7] == "pipeline")

local REALG = _G
local STD = { os=os, string=string, pairs=pairs, ipairs=ipairs, type=type, pcall=pcall,
    tonumber=tonumber, tostring=tostring, select=select, rawget=rawget, rawset=rawset,
    setmetatable=setmetatable, getmetatable=getmetatable, unpack=unpack, assert=assert,
    error=error, math=math, table=table, loadfile=loadfile, print=print, io=io,
    stringformat=string.format }

-- ---- mocked WoW environment ------------------------------------------------
local hookScriptCalls, postCallRegs, events = {}, {}, {}
local hookedGlobals = {}
-- Pawn call log, populated by the Pawn mock in baseEnv().
local PAWN = {}
local function newFrame(kind, name, parent, template)
    local f = { GetName = function() return name end, __kind = kind, __name = name }
    -- Scripts this frame declares. Which tooltip scripts exist is CLIENT-SPECIFIC:
    -- the Classic template declares OnTooltipSetUnit / OnTooltipSetItem /
    -- OnTooltipSetSpell, while Retail's SharedTooltipTemplate declares only
    -- OnShow, OnHide, OnLoad, OnTooltipSetDefaultAnchor and OnTooltipCleared.
    -- See SharedTooltipTemplates.xml on the live vs classic_era branches of
    -- wow-ui-source. Tooltip frames get the correct set per family below.
    f.__scripts = f.__scripts or { OnLoad = true, OnShow = true, OnHide = true,
        OnEvent = true, OnUpdate = true, OnSizeChanged = true, OnEnter = true, OnLeave = true }
    f.HasScript = function(self, n) return self.__scripts[n] == true end
    f.SetScript = function(self, n, fn)
        if (type(n) ~= "string" or n == "") then
            error("bad argument #2 to 'SetScript' (Usage: self:SetScript(scriptTypeName [, script]))", 2)
        end
        self.__scripts[n] = true
        self["__script_" .. n] = fn
        return true
    end
    -- Anchor state is tracked for real, so a test can read back where a frame was
    -- actually placed. The mover's default position is only observable this way;
    -- a mock with no-op anchors would report every position as "unset".
    f.__points = {}
    f.SetPoint = function(_, p, rel, rp, ox, oy)
        -- The real SetPoint resolves a frame argument to its NAME; GetPoint
        -- returns that name, and nil for an unnamed frame.
        local relName = rel
        if (type(rel) == "table" or type(rel) == "userdata") then
            relName = (rel.GetName and rel:GetName()) or nil
        end
        f.__points[#f.__points + 1] = { p, relName, rp, ox or 0, oy or 0 }
    end
    f.ClearAllPoints = function() f.__points = {} end
    f.GetNumPoints = function() return #f.__points end
    f.GetPoint = function(_, i)
        local q = f.__points[i or 1]
        if (not q) then return nil end
        return q[1], q[2], q[3], q[4], q[5]
    end
    local mt = {}
    mt.__index = function(t, k)
        if k == "SetScript" then return f.SetScript end
        if k == "HasScript" then return f.HasScript end
        if k == "HookScript" then return function(_, s, fn)
            -- The real HookScript raises "bad argument #2 to 'HookScript'" when the
            -- frame does not already declare that script. A permissive mock cannot
            -- catch an unguarded hook, and that is exactly how the Retail template
            -- change aborted main.lua at file scope.
            if (t.HasScript and not t:HasScript(s)) then
                error("bad argument #2 to 'HookScript' (Usage: self:HookScript(scriptTypeName, script))", 2)
            end
            hookScriptCalls[#hookScriptCalls + 1] = tostring(s)
            t["__hook_" .. tostring(s)] = fn end end
        if k == "GetScript" then return function(_, s) return t["__hook_" .. tostring(s)] or t["__script_" .. tostring(s)] end end
        if k == "RegisterEvent" then return function(_, e) events[#events + 1] = tostring(e) end end
        if k == "CreateFontString" then return function() return newFrame("FontString") end end
        if k == "CreateTexture" then return function() return newFrame("Texture") end end
        -- A real frame simply does not have some methods (Retail's GameTooltip has
        -- no SetBackdrop). Keys listed in __absent must read as nil, otherwise the
        -- mock invents a method the client does not have and any feature test
        -- built on it silently takes the wrong branch -- which is exactly how the
        -- backdrop Mixin shipped to Retail.
        -- rawget, and never for the internal fields themselves: reading t.__absent
        -- through __index would recurse forever.
        local absent = rawget(t, "__absent")
        if (absent and k ~= "__absent" and absent[k]) then return nil end
        -- generic no-op widget surface so load does not explode
        return function() return nil end
    end
    return setmetatable(f, mt)
end

local function baseEnv()
    REALG._G = REALG
    for k, v in STD.pairs(STD) do REALG[k] = v end
    REALG.time = STD.os.time
    REALG.CreateFrame = function(kind, name, parent, template) return newFrame(kind, name, parent, template) end
    REALG.print = function() end
    REALG.GetLocale = function() return "enUS" end
    REALG.InCombatLockdown = function() return false end
    REALG.UnitExists = function() return false end
    REALG.UnitIsPlayer = function() return false end
    REALG.UnitIsUnit = function() return false end
    REALG.UnitLevel = function() return 1 end
    REALG.UnitRace = function() return "" end
    REALG.UnitGUID = function() return nil end
    REALG.UnitClass = function() return "Warrior", "WARRIOR" end
    REALG.UnitName = function() return "Test" end
    REALG.UnitPower = function() return 0 end
    REALG.UnitPowerMax = function() return 100 end
    REALG.UnitPowerType = function() return 1 end
    REALG.UnitPVPName = function() return "" end
    REALG.UnitIsPVP = function() return false end
    REALG.UnitFactionGroup = function() return "Alliance" end
    REALG.UnitIsConnected = function() return false end
    REALG.UnitIsSameServer = function() return true end
    REALG.UnitGroupRolesAssigned = function() return "NONE" end
    REALG.UnitInParty = function() return false end
    REALG.UnitInRaid = function() return false end
    REALG.IsInGroup = function() return false end
    REALG.IsInRaid = function() return false end
    REALG.UnitCanAttack = function() return false end
    REALG.CanInspect = function() return false end
    REALG.NotifyInspect = function() end
    REALG.ClearInspectPlayer = function() end
    REALG.GetPlayerInfoByGUID = function() return true, "Warrior" end
    -- Pawn mock, faithful to how Pawn.toc gates its two scale providers:
    --     AskMrRobot.lua     [AllowLoadGameType mainline]   Retail, WoW Forever
    --     ClassicHawsJon.lua [AllowLoadGameType classic]   Vanilla, TBC, Wrath
    -- Exactly one provider exists per client, which `pipeline` selects (Retail and
    -- WoW Forever are the only mainline clients in the matrix).
    --
    -- Pawn reports an unknown scale via VgerCore.Fail, which does NOT error --
    -- it calls VgerCore.Message -> DEFAULT_CHAT_FRAME:AddMessage. So pcall
    -- cannot suppress it. The mock reproduces that by PRINTING rather than
    -- raising, so any test that passes cannot be passing because an exception
    -- was swallowed.
    PAWN.seenScales, PAWN.visibleQueries, PAWN.chatOutput = {}, {}, {}
    local provider = usePipeline and "MrRobot" or "Classic"
    local prefix = '"' .. provider .. '":'
    REALG.PawnScaleProviders = { [provider] = { Name = provider } }
    REALG.PawnCommon = { Scales = { [prefix .. "Warrior1"] = {}, [prefix .. "Warrior2"] = {} } }
    local function pawnChat(line)
        PAWN.chatOutput[#PAWN.chatOutput + 1] = line
        if REALG.DEFAULT_CHAT_FRAME then
            REALG.DEFAULT_CHAT_FRAME:AddMessage(line)
        else
            STD.io.write("CHAT> " .. tostring(line) .. "\n")
        end
    end
    REALG.PawnChatSink = pawnChat
    REALG.PawnClassicLastUpdatedVersion = 2.0538
    REALG.PawnLastUpdatedVersion = 2.1
    REALG.PawnGetItemData = function() return {} end
    -- PawnGetSingleValueFromItem never calls VgerCore.Fail; it just answers 0 for
    -- a name it does not have, so it is silent and safe to call speculatively.
    REALG.PawnGetSingleValueFromItem = function() return nil end
    REALG.PawnGetScaleColor = function(scaleName)
        PAWN.seenScales[#PAWN.seenScales + 1] = scaleName
        if (not (REALG.PawnCommon.Scales[scaleName])) then
            pawnChat("ERROR:  ScaleName must be the name of an existing scale, and is case-sensitive.")
            return "|cff0000ff"
        end
        return 1, 1, 1
    end
    REALG.PawnIsScaleVisible = function(scaleName)
        PAWN.visibleQueries[#PAWN.visibleQueries + 1] = scaleName
        if (not (REALG.PawnCommon.Scales[scaleName])) then
            pawnChat("ERROR:  ScaleName must be the name of an existing scale, and is case-sensitive.")
            return false
        end
        return true
    end
    REALG.GetGuildInfo = function() return nil end
    REALG.GetInventoryItemLink = function() return nil end
    REALG.GetItemInfo = function() return nil end
    REALG.GetItemInfoInstant = function() return nil end
    REALG.GetMouseFoci = function() return nil end
    REALG.GetMouseFocus = function() return nil end
    REALG.GetCursorPosition = function() return 0, 0 end
    REALG.GetScreenWidth = function() return 1920 end
    REALG.GetCVar = function() return "" end
    REALG.SetCVar = function() end
    REALG.GetClassAtlas = function() return nil end
    REALG.GetBuildInfo = layout == "slot4"
        and function() return "1.15.9", "69722", "d", iface, "us", "rel" end
        or  function() return "1.15.9", "69722", "d", nil, "versionType", "buildType", iface end
    REALG.RAID_CLASS_COLORS = { WARRIOR = { r = 1, g = .8, b = .5 } }
    REALG.CUSTOM_CLASS_COLORS = nil
    REALG.NORMAL_FONT_COLOR = { r = 1, g = 1, b = 1 }
    REALG.GRAY_FONT_COLOR = { r = .5, g = .5, b = .5 }
    REALG.HIGHLIGHT_FONT_COLOR = { r = 1, g = .82, b = 0 }
    REALG.PowerBarColor = {}
    REALG.GameFontNormal = "GameFontNormal"
    REALG.GameFontHighlight = "GameFontHighlight"
    REALG.GameFontNormalSmall = "GameFontNormalSmall"
    REALG.GameFontHighlightSmall = "GameFontHighlightSmall"
    REALG.GameFontDisable = "GameFontDisable"
    REALG.GameFontDisableSmall = "GameFontDisableSmall"
    REALG.GameFontNormalLarge = "GameFontNormalLarge"
    REALG.NumberFontNormal = "NumberFontNormal"
    REALG.ChatFontNormal = "ChatFontNormal"
    REALG.UIParent = newFrame("Frame", "UIParent")
    REALG.WorldFrame = newFrame("Frame", "WorldFrame")
    REALG.PaperDollFrame = newFrame("Frame", "PaperDollFrame")
    REALG.InspectFrame = newFrame("Frame", "InspectFrame")
    REALG.InspectPaperDollFrame = newFrame("Frame", "InspectPaperDollFrame")
    REALG.InspectModelFrame = newFrame("Frame", "InspectModelFrame")
    REALG.CharacterModelFrame = newFrame("PlayerModel", "CharacterModelFrame")

    -- CharacterModelFrame is a CLASSIC-ONLY frame: the Classic family nests a
    -- PlayerModel by that name inside PaperDollFrame, and Retail removed it (no
    -- definition anywhere in the live FrameXML) while keeping PaperDollFrame. The
    -- mock used to invent it on every client, which is how an unguarded
    -- index of a frame Retail does not have shipped: "attempt to index global
    -- 'CharacterModelFrame' (a nil value)" on every options refresh.
    if (usePipeline) then
        REALG.CharacterModelFrame = nil
    end
    -- Real tooltip templates, per family:
    --   Classic family  SharedTooltipTemplate, no NineSlice, no SetBackdrop
    --   Retail / Forever SharedTooltipArtTemplate, HAS a NineSlice child, and does
    --                   NOT mix in BackdropTemplateMixin -- so no SetBackdrop
    -- See Blizzard_SharedXML/SharedTooltipTemplates.xml on the live and
    -- classic_era branches of wow-ui-source.
    -- Tooltip frames the addon hooks, with the scripts their real template
    -- declares. Modern tooltips have NO OnTooltipSetUnit / OnTooltipSetItem /
    -- OnTooltipSetSpell; Classic tooltips have all three. Hooking one that does
    -- not exist is exactly what raised on Retail.
    local TOOLTIP_SCRIPTS_MODERN = { OnLoad = true, OnShow = true, OnHide = true,
        OnEvent = true, OnUpdate = true, OnTooltipCleared = true,
        OnTooltipSetDefaultAnchor = true, OnSizeChanged = true, OnEnter = true, OnLeave = true }
    local TOOLTIP_SCRIPTS_CLASSIC = { OnLoad = true, OnShow = true, OnHide = true,
        OnEvent = true, OnUpdate = true, OnTooltipCleared = true, OnSizeChanged = true,
        OnEnter = true, OnLeave = true,
        OnTooltipSetUnit = true, OnTooltipSetItem = true, OnTooltipSetSpell = true }
    local tooltipScripts = (projectId == 1) and TOOLTIP_SCRIPTS_MODERN or TOOLTIP_SCRIPTS_CLASSIC

    local gt = newFrame("GameTooltip", "GameTooltip")
    gt.__scripts = tooltipScripts
    -- Classic-family tooltip: no NineSlice, no SetBackdrop. Modern tooltip:
    -- NineSlice present, still no SetBackdrop. In BOTH cases SetBackdrop is
    -- absent -- that is the whole point, and the old feature test could not tell
    -- them apart.
    gt.__absent = {
        SetBackdrop = true, SetBackdropColor = true, SetBackdropBorderColor = true,
        NineSlice = true,
    }
    -- WOW_PROJECT_MAINLINE is 1; the constant is assigned further down in this
    -- same env block, so compare against the literal.
    if (projectId == 1) then
        gt.__absent.NineSlice = nil
        gt.NineSlice = newFrame("Frame", "GameTooltipNineSlice")
        gt.NineSlice.__absent = {}
    end
    REALG.GameTooltip = gt
    -- Present on every supported client, and required for the backdrop fallback.
    REALG.BackdropTemplateMixin = { SetBackdrop = function() end }
    REALG.Mixin = function(object, mixin)
        for k, v in pairs(mixin) do object[k] = v end
    end
    REALG.GameTooltipStatusBar = newFrame("StatusBar", "GameTooltipStatusBar")
    REALG.ItemRefTooltip = newFrame("GameTooltip", "ItemRefTooltip")
    REALG.ShoppingTooltip1 = newFrame("GameTooltip", "ShoppingTooltip1")
    REALG.ShoppingTooltip2 = newFrame("GameTooltip", "ShoppingTooltip2")
    REALG.ItemRefShoppingTooltip1 = newFrame("GameTooltip", "ItemRefShoppingTooltip1")
    REALG.ItemRefShoppingTooltip2 = newFrame("GameTooltip", "ItemRefShoppingTooltip2")
    REALG.TacoTipConfig = {}
    REALG.SlashCmdList = {}
    REALG.StaticPopupDialogs = {}
    REALG.StaticPopup_Show = function() end
    REALG.geterrorhandler = function() return function() end end
    -- The real hooksecurefunc THROWS when its target global does not exist
    -- ("attempt to hook a non-existent function"). A no-op mock cannot catch an
    -- unguarded file-scope hook, and an unguarded file-scope hook aborts the rest
    -- of main.lua -- which is precisely the failure being hunted.
    REALG.hooksecurefunc = function(a)
        local name = tostring(a)
        if (type(name) == "string" and type(rawget(REALG, name)) ~= "function") then
            error("hooksecurefunc: no such global '" .. name .. "'", 2)
        end
        hookedGlobals[name] = (hookedGlobals[name] or 0) + 1
    end
    REALG.strlower = string.lower
    REALG.strfind = string.find
    REALG.strrep = string.rep
    REALG.strsub = string.sub
    REALG.tinsert = table.insert
    REALG.tremove = table.remove
    REALG.wipe = table.wipe
    REALG.C_Timer = { After = function() end, NewTimer = function() return { Cancel = function() end } end,
                      NewTicker = function() return { Cancel = function() end } end }
    REALG.C_AddOns = { GetAddOnMetadata = function() return nil end, IsAddOnLoaded = function() return false end }
    REALG.C_Item = { GetItemInfo = function() return nil end, IsEquippableItem = function() return true end,
                     RequestLoadItemDataByID = function() end, ContinueWithCancelOnItemLoad = function() end,
                     GetInventoryItemLink = function() return nil end }
    REALG.C_PlayerInfo = { GUIDIsPlayer = function() return false end }
    REALG.C_Map = { GetBestMapForUnit = function() return nil end }
    REALG.C_SpecializationInfo = { GetSpecializationInfo = function() return nil end,
                                   GetInspectSpecialization = function() return nil end,
                                   GetActiveSpecGroup = function() return 1 end }
    REALG.Enum = { TooltipDataType = { Item = 0, Unit = 2 } }
    -- pipeline-less client: no TooltipDataProcessor, no TooltipUtil, no mixin
    if (usePipeline) then
        -- Retail / Forever shape: the data pipeline globals exist AND the
        -- GameTooltip actually mixes in TooltipDataHandlerMixin, so the
        -- post-call registration is the one that will fire.
        REALG.TooltipDataProcessor = {
            AddTooltipPostCall = function(typ, fn)
                postCallRegs[#postCallRegs + 1] = tostring(typ)
            end,
        }
        REALG.TooltipUtil = { GetDisplayedUnit = function() return "n", nil, nil end,
                              GetDisplayedItem = function() return "n", nil end }
        local ttFrame = REALG.GameTooltip
        ttFrame.IsTooltipType = function() return true end
        ttFrame.GetPrimaryTooltipData = function() return nil end
        ttFrame.GetUnit = function() return "n", "mouseover", nil end
    else
        REALG.TooltipDataProcessor = nil
        REALG.TooltipUtil = nil
    end

    -- Defined by Blizzard_SharedXML/SharedTooltipTemplates.lua on all five
    -- clients, and hooksecurefunc THROWS without it. The addon hooks it at file
    -- scope, so a harness that omits it silently takes the "target missing" path
    -- and never exercises the hook -- the same blind spot that let the backdrop
    -- Mixin ship to Retail.
    REALG.GameTooltip_SetDefaultAnchor = function(tooltip, parent) end
    if (missingGlobal) then
        -- Applied last, so it models "this Blizzard global does not exist on
        -- this client" rather than being overwritten by the model above.
        REALG[missingGlobal] = nil
    end
    for _, nm in ipairs({ "ShoppingTooltip1", "ShoppingTooltip2", "ItemRefTooltip",
            "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2", "WorldMapTooltip",
            "WorldMapCompareTooltip1", "WorldMapCompareTooltip2", "SmallTextTooltip",
            "GameTooltipStatusBar" }) do
        local f = REALG[nm]
        if (f and f.__scripts) then f.__scripts = tooltipScripts end
    end

    REALG.Item = nil
    REALG.Settings = nil
    REALG.InterfaceOptions_AddCategory = function() end
    REALG.InterfaceOptionsFrame_OpenToCategory = function() end
    REALG.InterfaceOptionsFrame_Show = function() end
    REALG.ColorPickerFrame = nil
    REALG.LibSharedMedia = nil
    REALG.UISpecialFrames = {}
    REALG.MultiBarBottomRight = newFrame("Frame", "MultiBarBottomRight")
    REALG.MultiBarLeft = newFrame("Frame", "MultiBarLeft")
    REALG.MultiBarRight = newFrame("Frame", "MultiBarRight")
    REALG.WOW_PROJECT_MAINLINE = 1
    REALG.WOW_PROJECT_CLASSIC = 2
    REALG.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
    REALG.WOW_PROJECT_WRATH_CLASSIC = 11
    REALG.WOW_PROJECT_CATACLYSM_CLASSIC = 14
    REALG.WOW_PROJECT_MISTS_CLASSIC = 19
    REALG.WOW_PROJECT_ID = projectId
    REALG.TacoTipConfig = {}
end

for k in STD.pairs(REALG) do REALG[k] = nil end
baseEnv()

local function run(rel)
    local chunk = assert(loadfile(ROOT .. rel))
    return chunk("TacoTip_Forever")
end

local order = {
    "Libs/LibStub/LibStub.lua",
    "Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua",
    "Libs/LibDetours-1.0/LibDetours-1.0.lua",
    "Libs/LibForeverInspector/LibForeverInspector.lua",
    "Locale/deDE.lua", "Locale/esES.lua", "Locale/esMX.lua", "Locale/frFR.lua",
    "Locale/itIT.lua", "Locale/koKR.lua", "Locale/ptBR.lua", "Locale/ruRU.lua",
    "Locale/zhCN.lua", "Locale/zhTW.lua", "Locale/enUS.lua",
    "gearscore.lua", "pawn.lua", "textures.lua", "options.lua", "main.lua",
}

local failed = nil
for _, rel in ipairs(order) do
    local ok, err = pcall(run, rel)
    if (not ok) then failed = rel .. ": " .. tostring(err); break end
end

if failed then
    STD.io.write(string.format("LOAD FAIL  family=%-12s %s\n", tostring(expectFamily), failed))
    STD.os.exit(1)
end

local ci = REALG.LibStub("LibForeverInspector", true)
local GS = REALG.TT_GS
local TT = REALG.TacoTip_Forever

local hookUnit = false
for _, s in ipairs(hookScriptCalls) do if s == "OnTooltipSetUnit" then hookUnit = true end end
local hookItem = false
for _, s in ipairs(hookScriptCalls) do if s == "OnTooltipSetItem" then hookItem = true end end
-- The recorder logs script names, not frames, so a count is how a double-hook
-- is detected. GameTooltip is the only frame that is hooked for the unit script,
-- so anything above one means the same script is being attached twice.
local hookUnitCount = 0
for _, s in ipairs(hookScriptCalls) do if s == "OnTooltipSetUnit" then hookUnitCount = hookUnitCount + 1 end end

local nlocale = 0
for _ in pairs(REALG.TACOTIP_LOCALE or {}) do nlocale = nlocale + 1 end

local checks = {
    { ci and ci.family == expectFamily, string.format("family=%s want=%s", tostring(ci and ci.family), expectFamily) },
    { GS and GS.BRACKET_SIZE == expectBracket, string.format("bracket=%s want=%s", tostring(GS and GS.BRACKET_SIZE), tostring(expectBracket)) },
    { nlocale >= 251, "locale keys=" .. nlocale },
    { REALG.TACOTIP_LOCALES and REALG.TACOTIP_LOCALES.deDE ~= nil, "deDE registered" },
    -- The mocked client reports enUS. Every family resolves to enUS from that
    -- EXCEPT Titanforge, which is pinned to Simplified Chinese because it is the
    -- Chinese build of WotLK.
    { REALG.TACOTIP_ACTIVE_LOCALE == (expectFamily == "titanforge" and "zhCN" or "enUS"),
        "active locale " .. tostring(REALG.TACOTIP_ACTIVE_LOCALE)
            .. " want " .. (expectFamily == "titanforge" and "zhCN" or "enUS") },
    { TT and type(TT.ApplyTooltipAppearance) == "function", "TT.ApplyTooltipAppearance present" },
    -- Load must run to completion. main.lua defines the tooltip mover only at its
    -- very end, so a partial load silently disables the mover and the whole
    -- pipeline while leaving the options frame working -- indistinguishable from
    -- "the button is broken" without this.
    { TT and TT.LOAD_OK == true,
        "main.lua loaded to completion (stage=" .. tostring(TT and TT.LOAD_STAGE) .. ")" },
    { _G.TacoTip_CustomPosEnable ~= nil, "TacoTip_CustomPosEnable defined" },
    -- Mover default geometry. The green drag handle must mark the tooltip's
    -- TOP-LEFT corner (default custom_anchor) while sitting in the screen's
    -- BOTTOM-LEFT, which is where the tooltip is anchored in practice. The
    -- default was BOTTOMRIGHT of the screen, and with a saved custom_anchor of
    -- BOTTOMRIGHT -- a value middle-click cycles to -- the handle rendered on
    -- the tooltip's bottom-right, level with the "Drag to Move" line, at the far
    -- end from the name. Both halves are pinned, because either one alone gives
    -- the wrong corner.
    { _G.TacoTipConfig and _G.TacoTipConfig.custom_anchor == "TOPLEFT",
        "default anchor marks the tooltip's TOPLEFT (got "
            .. tostring(_G.TacoTipConfig and _G.TacoTipConfig.custom_anchor) .. ")" },
    { TT and type(TT.PrintDiagnostics) == "function", "TT.PrintDiagnostics present" },
    { TT and TT.HookedDefaultAnchor == (not missingGlobal),
        "GameTooltip_SetDefaultAnchor hook guarded (missingGlobal="
            .. tostring(missingGlobal) .. ")" },
}

-- Backdrop template contract. The signal for "this tooltip needs the legacy
-- BackdropTemplateMixin" is the ABSENCE of NineSlice, not the absence of
-- SetBackdrop: Retail and WoW Forever use SharedTooltipArtTemplate, which has a
-- NineSlice child and does NOT mix in BackdropTemplateMixin, so GameTooltip has
-- no SetBackdrop even though it renders correctly. Testing SetBackdrop made the
-- Mixin run on exactly the two clients that must not have it.
do
    local gt = REALG.GameTooltip
    local modern = (expectFamily == "retail" or expectFamily == "forever")
    if (modern) then
        checks[#checks + 1] = { gt and gt.NineSlice ~= nil,
            "modern tooltip has a NineSlice child" }
        checks[#checks + 1] = { gt and gt.SetBackdrop == nil,
            "BackdropTemplateMixin is NOT grafted onto a NineSlice tooltip" }
    else
        checks[#checks + 1] = { gt and gt.NineSlice == nil,
            "Classic tooltip has no NineSlice child" }
        checks[#checks + 1] = { gt and type(gt.SetBackdrop) == "function",
            "Classic tooltip keeps the legacy SetBackdrop fallback" }
    end
end

-- The actual 1.3 fix: a client WITHOUT the data pipeline must register ZERO
-- post-calls. Previously the presence-only test registered one that nothing ever
-- invoked, so TBC and Titanforge showed stock Blizzard tooltips.
if (usePipeline) then
    checks[#checks + 1] = { #postCallRegs >= 2,
        "pipeline client registers unit+item post-calls (got " .. #postCallRegs .. ")" }
else
    checks[#checks + 1] = { #postCallRegs == 0,
        "pipeline-less client registers NO post-calls (got " .. #postCallRegs .. ")" }
end
-- Which delivery path is live is client-specific. The previous comment here --
-- "registered unconditionally as insurance" -- was the bug: on Retail and WoW
-- Forever those scripts DO NOT EXIST on the tooltip, so the insurance hook was
-- not inert, it raised at file scope and aborted main.lua.
if (usePipeline) then
    checks[#checks + 1] = { not hookUnit and not hookItem,
        "pipeline client installs no Classic tooltip script hooks" }
    checks[#checks + 1] = { TT and TT.HookedTooltipScripts
        and TT.HookedTooltipScripts.Unit == "postcall",
        "unit tooltip delivered by post-call" }
    checks[#checks + 1] = { TT and TT.HookedTooltipScripts
        and TT.HookedTooltipScripts.Item == "postcall",
        "item tooltip delivered by post-call" }
else
    checks[#checks + 1] = { hookUnit, "OnTooltipSetUnit script-hook registered" }
    checks[#checks + 1] = { hookItem, "OnTooltipSetItem script-hook registered" }
    -- ALL FOUR item frames must be hooked, not just the first one that succeeds.
    -- An earlier version of the guarded hook used a short-circuiting `or` chain,
    -- so on the Classic family -- where GameTooltip is first and does declare
    -- OnTooltipSetItem -- ShoppingTooltip1, ShoppingTooltip2 and ItemRefTooltip
    -- were silently never hooked. That regressed the three clients that already
    -- worked, so it is pinned here explicitly.
    local itemHooks = (TT and TT.HookedTooltipScripts and TT.HookedTooltipScripts.Item) or ""
    for _, want in ipairs({ "GameTooltip", "ShoppingTooltip1", "ShoppingTooltip2",
            "ItemRefTooltip" }) do
        checks[#checks + 1] = { itemHooks:find(want, 1, true) ~= nil,
            "item hook installed on " .. want .. " (got: " .. itemHooks .. ")" }
    end
    checks[#checks + 1] = { hookUnitCount == 1,
        "OnTooltipSetUnit hooked exactly once (got " .. tostring(hookUnitCount) .. ")" }
end

-- Mover default screen position, exercised through the real code path rather
-- than by reading the local default function: with no saved custom_pos,
-- syncTooltipMoverPosition must anchor the handle to the screen's BOTTOMLEFT.
-- Paired with the TOPLEFT default anchor, that places the handle on the
-- tooltip's top-left corner with the tooltip still in the bottom-left of the
-- screen. A saved custom_pos must still be honoured, or the setting is useless.
do
    local cfg = _G.TacoTipConfig
    local savedPos, savedAnchor = cfg and cfg.custom_pos, cfg and cfg.custom_anchor
    if (cfg and _G.TacoTip_CustomPosEnable and TT and TT.SyncTooltipMover) then
        local _, err = pcall(_G.TacoTip_CustomPosEnable, true)
        local btn = _G.TacoTipDragButton
        -- The handle is created before the example tooltip is drawn, so it
        -- exists even if the example-tooltip part of enabling raises on a
        -- partial mock. Surface the error so a real failure is not hidden.
        checks[#checks + 1] = { btn ~= nil, "mover handle created (enable err: "
            .. tostring(err) .. ")" }
        if (btn and btn.GetPoint) then
            -- A saved position wins.
            cfg.custom_pos = { "TOPLEFT", "TOPLEFT", 111, 222 }
            TT:SyncTooltipMover()
            local p, _, _, ox, oy = btn:GetPoint(1)
            checks[#checks + 1] = { p == "TOPLEFT" and ox == 111 and oy == 222,
                "saved mover position honoured (got " .. tostring(p) .. "/" .. tostring(ox)
                    .. "/" .. tostring(oy) .. ")" }
            -- With nothing saved, the default applies.
            cfg.custom_pos = nil
            TT:SyncTooltipMover()
            local dp, _, _, dx, dy = btn:GetPoint(1)
            checks[#checks + 1] = { dp == "BOTTOMRIGHT" and dx == 0 and dy == 0,
                "default mover position is the screen's BOTTOMRIGHT (got " .. tostring(dp)
                    .. "/" .. tostring(dx) .. "/" .. tostring(dy) .. ")" }
        end
        cfg.custom_pos, cfg.custom_anchor = savedPos, savedAnchor
    end
end

-- Pawn scale-name contract.
--
-- The invariant is NOT "use library X" -- it is "never hand a name Pawn lacks to
-- an API that shouts about it". Pawn's PawnIsScaleVisible and PawnGetScaleColor
-- report an unknown name through VgerCore.Fail, which does NOT error: it calls
-- VgerCore.Message -> DEFAULT_CHAT_FRAME:AddMessage. pcall cannot suppress that.
-- So any name Pawn does not have produces one chat line per tooltip render and
-- per unit frame refresh, which is the reported spam.
--
-- Pawn.toc gates its two providers by game type, so exactly one exists per client
-- and the correct one differs between the Classic family and Retail/WoW Forever.
-- The mock models that, and records anything written to chat, so the assertion
-- below is exactly "the chat frame stayed clean".
do
    local fn = (TT_PAWN and TT_PAWN.GetScore) or nil
    checks[#checks + 1] = { fn ~= nil, "TT_PAWN loaded (Pawn module did not return early)" }
    if (fn) then
        -- Play the part of a player hovering their own unit frame, which is the
        -- case that spams. The shared mocks report every unit as a non-player,
        -- so getPlayerGUID would return nil and the scale path would never run.
        local selfGUID = "Player-1-00000001"
        local savedIsPlayer = REALG.UnitIsPlayer
        local savedGUIDIsPlayer = REALG.C_PlayerInfo.GUIDIsPlayer
        local savedUnitGUID = REALG.UnitGUID
        REALG.UnitIsPlayer = function(u) return u == selfGUID end
        REALG.C_PlayerInfo.GUIDIsPlayer = function(g)
            return (type(g) == "string") and (g:find("Player-", 1, true) == 1)
        end
        -- Report the hovered unit as the player, so GetScore skips the
        -- "have we cached this player's inventory" early return.
        REALG.UnitGUID = function() return selfGUID end

        PAWN.seenScales, PAWN.visibleQueries, PAWN.chatOutput = {}, {}, {}
        local ok, res = pcall(fn, TT_PAWN, selfGUID, false)
        checks[#checks + 1] = { ok,
            "TT_PAWN:GetScore(player) did not raise (err: " .. tostring(res) .. ")" }

        -- The assertion that matters: nothing Pawn said went to chat.
        checks[#checks + 1] = { #PAWN.chatOutput == 0,
            "Pawn wrote nothing to the chat frame (" .. #PAWN.chatOutput
                .. " line(s): " .. tostring(PAWN.chatOutput[1]) .. ")" }
        checks[#checks + 1] = { #PAWN.visibleQueries == 0,
            "Pawn scale visibility is never probed (probed " .. #PAWN.visibleQueries .. "x)" }

        -- And the names we did pass must be ones this client actually has.
        local scales = REALG.PawnCommon and REALG.PawnCommon.Scales
        local unknown
        for _, s in ipairs(PAWN.seenScales) do
            if (not (scales and scales[s])) then unknown = tostring(s) break end
        end
        checks[#checks + 1] = { unknown == nil,
            "every Pawn scale name exists on this client (offender: " .. tostring(unknown) .. ")" }
        checks[#checks + 1] = { #PAWN.seenScales > 0,
            "Pawn colour was actually requested (proves the checks above are not vacuous)" }

        REALG.UnitIsPlayer, REALG.C_PlayerInfo.GUIDIsPlayer, REALG.UnitGUID =
            savedIsPlayer, savedGUIDIsPlayer, savedUnitGUID
    end
end

-- The slash command and its "diag" subcommand.
--
-- Slash commands already existed: gearscore.lua installs an early bootstrap
-- handler behind a guard, and options.lua deliberately replaces it with the final
-- one that owns custom / save / reset / help. TT:PrintDiagnostics existed too,
-- but nothing dispatched to it -- "/tacotip diag" fell through to the default
-- branch and opened the options panel instead, so the one function that names
-- the stage main.lua stopped at was unreachable from a slash command.
--
-- These assertions pin the whole route, because the failure mode is silent: a
-- misfiled key or a missing subcommand does not raise, it just does nothing.
do
    local cmd = REALG.SlashCmdList and REALG.SlashCmdList.TACOTIP
    checks[#checks + 1] = { type(cmd) == "function", "SlashCmdList.TACOTIP is registered" }

    -- All seven aliases, and specifically /tt and /tacotip. WoW dispatches on the
    -- GLOBAL-NAME prefix (SLASH_TACOTIP<n> -> SlashCmdList.TACOTIP), not the typed
    -- text, so the aliases only need the shared prefix -- but each must still be
    -- assigned, or the player gets "unknown command" from the chat frame.
    local ALIASES = { "/tacotip", "/tooltip", "/tip", "/tt", "/gs", "/gearscore", "/taco" }
    local missing
    for i, want in ipairs(ALIASES) do
        local got = REALG["SLASH_TACOTIP" .. i]
        if (got ~= want) then missing = "SLASH_TACOTIP" .. i .. "=" .. tostring(got) .. " want " .. want end
    end
    checks[#checks + 1] = { missing == nil, "all seven slash aliases registered (" .. tostring(missing) .. ")" }

    checks[#checks + 1] = { type(TT.PrintDiagnostics) == "function",
        "TT.PrintDiagnostics exists for the handler to call" }

    -- Drive it. "diag" must print the report and must NOT open the options panel;
    -- an unknown argument must also print rather than raise. printDiagnostics is
    -- read-only, so intercepting print here is safe and is the only way to observe
    -- that the branch was taken at all.
    if (type(cmd) == "function" and type(TT.PrintDiagnostics) == "function") then
        local printed, raised = 0, nil
        local savedPrint, savedPanel = REALG.print, TT.OpenOptionsPanel
        local panelOpened = 0
        REALG.print = function() printed = printed + 1 end
        TT.OpenOptionsPanel = function() panelOpened = panelOpened + 1 end
        -- Proxy so the handler's TT:PrintDiagnostics() resolves to the spy.
        local savedDiag = TT.PrintDiagnostics
        TT.PrintDiagnostics = function(self) printed = printed + 1; return savedDiag(self) end
        for _, arg in ipairs({ "diag", "diag ", "DIAG", "diagnostics" }) do
            local _, err = pcall(cmd, arg)
            if (raised == nil) then raised = err end
        end
        local printedAfterDiag = printed
        for _, arg in ipairs({ "nonsense", "", nil }) do
            local _, err = pcall(cmd, arg)
            if (raised == nil) then raised = err end
        end
        TT.PrintDiagnostics = savedDiag
        REALG.print, TT.OpenOptionsPanel = savedPrint, savedPanel
        checks[#checks + 1] = { raised == nil, "the slash handler does not raise (err: " .. tostring(raised) .. ")" }
        checks[#checks + 1] = { printedAfterDiag > 0, "\"diag\" printed the load report" }
        -- The bug being pinned: diag fell through to the default branch and opened
        -- the options panel instead of reporting.
        checks[#checks + 1] = { panelOpened == 0,
            "\"diag\" does not open the options panel (opened " .. tostring(panelOpened) .. "x)" }
    end
end

local bad = 0
for _, c in ipairs(checks) do
    if not c[1] then bad = bad + 1; STD.io.write("    FAIL " .. c[2] .. "\n") end
end
STD.io.write(string.format("%-8s layout=%-6s family=%-12s bracket=%-5s localeKeys=%-4d %s\n",
    label, layout, tostring(ci and ci.family), tostring(GS and GS.BRACKET_SIZE),
    nlocale, (bad == 0) and "ALL PASS" or (bad .. " FAILED")))
STD.os.exit(bad == 0 and 0 or 1)
