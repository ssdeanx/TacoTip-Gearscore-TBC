-- End-to-end load of the whole addon under a mocked client, asserting it does
-- not raise and that the cross-client wiring lands correctly.
-- Usage: lua5.1 loadtest.lua <projectId> <interface> <layout> <expectFamily> <expectBracket>

local _hp = ((arg and arg[0]) or "Tests/harness/load_test.lua"):gsub("\\", "/")
local _hd = _hp:match("^(.*)/[^/]*$") or "."
local ROOT = dofile(_hd .. "/root.lua") .. "/"
local MOCKC = dofile(_hd .. "/mock_contract.lua")

local projectId, iface, layout = tonumber(arg[1]), tonumber(arg[2]), arg[3]
-- Optional: blank out a Blizzard global before load, to prove that a file-scope
-- operation depending on it is guarded rather than fatal. main.lua is the last
-- file in the toc and every feature it defines after a throw is silently lost.
local missingGlobal = arg[8]
local expectFamily, expectBracket = arg[4], tonumber(arg[5])
local label = arg[6] or ""
local usePipeline = (arg[7] == "pipeline")
MOCKC.setFamily(MOCKC.normaliseFamily(expectFamily))

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

-- Templates that carry the BACKDROP API.
--
-- Only a template that mixes in BackdropTemplateMixin has SetBackdrop /
-- SetBackdropColor / SetBackdropBorderColor, and the only such template is
-- BackdropTemplate itself. Verified on ALL FIVE branches:
--   origin/classic_era          Interface/AddOns/Blizzard_SharedXML/Backdrop.xml:5
--   origin/classic_anniversary  Interface/AddOns/Blizzard_SharedXML/Backdrop.xml:5
--   origin/classic_titan        Interface/AddOns/Blizzard_SharedXML/Backdrop.xml:5
--   origin/forever              Interface/AddOns/Blizzard_SharedXML/Backdrop.xml:5
--   origin/live                 Interface/AddOns/Blizzard_SharedXML/Backdrop.xml:5
--       <Frame name="BackdropTemplate" mixin="BackdropTemplateMixin" virtual="true">
--   and the mixin, on every one of them:
--   Interface/AddOns/Blizzard_SharedXML/Backdrop.lua:336 / :406 / :429
--       SetBackdrop / SetBackdropColor / SetBackdropBorderColor
--
-- The rule is recorded in Tests/harness/mock_contract.lua (RULES.backdropTemplate)
-- so the contract lives in one place.
local BACKDROP_TEMPLATES = { BackdropTemplate = true }

local function newFrame(kind, name, parent, template)
    -- __template is recorded so the template the client was asked for is a
    -- decidable fact, not a detail the mock swallowed. The Extras harness
    -- records it the same way.
    local f = { GetName = function() return name end, __kind = kind, __name = name,
        __template = template }
    -- The backdrop API is TEMPLATE-DEPENDENT, and the client is the authority.
    --
    -- The generic no-op surface below (the __index fallback) answers EVERY key
    -- with a function, so before this rule a plain CreateFrame("Frame", ...)
    -- "had" SetBackdrop in the harness. In the client it does not, and an
    -- `if f.SetBackdrop then` guard is the client's own way of asking that
    -- question -- a mock that always answers yes makes the guard unobservable.
    -- That is exactly how the Extras' gear panel shipped TRANSPARENT.
    --
    -- A frame WITH a backdrop template gets the three members as real
    -- functions; a frame WITHOUT one has them recorded as ABSENT, which the
    -- __index below consults first (via rawget, because reading t.__absent
    -- through __index would recurse forever).
    local backdropCapable = type(template) == "string"
        and BACKDROP_TEMPLATES[template] == true
    if backdropCapable then
        f.SetBackdrop = function() end
        f.SetBackdropColor = function() end
        f.SetBackdropBorderColor = function() end
    else
        f.__absent = {
            SetBackdrop = true,
            SetBackdropColor = true,
            SetBackdropBorderColor = true,
        }
    end
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
        -- A real frame simply does not have some methods (no tooltip chain on
        -- any of the five clients defines SetBackdrop). Keys listed in __absent
        -- must read as nil, otherwise the mock invents a method the client does
        -- not have and any feature test built on it silently takes the wrong
        -- branch -- which is exactly how the backdrop Mixin shipped to Retail.
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
    -- `securecall` -- the engine's taint-containment global, present on every
    -- supported client (Blizzard captures it as a local the same way it captures
    -- `forceinsecure`: Blizzard_FrameXML/SharedPetBattleTemplates.lua:5
    -- `local securecall = securecall;`). The mock counts the calls that went
    -- through it, so a taint pin can tell "addon code ran inside a Blizzard
    -- frame's script chain" from "it ran contained".
    REALG.securecall = function(fn, ...)
        REALG.__secureCalls = (REALG.__secureCalls or 0) + 1
        return fn(...)
    end
    REALG.UnitExists = function() return false end
    REALG.UnitIsPlayer = function() return false end
    REALG.UnitIsUnit = function() return false end
    REALG.UnitLevel = function() return 1 end
    REALG.UnitRace = function() return "" end
    REALG.UnitGUID = function() return nil end
    -- UnitClass publishes THREE values on the modern pair
    -- (localizedClassName, classToken, classID) and TWO on the Classic
    -- family; the mock published two on every client. See
    -- Tests/harness/mock_contract.lua for the mirror citations.
    --   origin/live, origin/forever: UnitUtil.lua:81 `select(3, UnitClass("player"))`
    --   origin/classic_era etc.:      InspectPaperDollFrame.lua:10
    REALG.UnitClass = MOCKC.unitClassMock(function() return "Warrior", "WARRIOR" end)
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
    -- Real tooltip templates, per family. Mirror-verified against
    -- wow-ui-source (Interface/AddOns/Blizzard_SharedXML/):
    --   Classic family  GameTooltipTemplate -> GameTooltipCommonTemplate,
    --                   TooltipBackdropTemplate. TooltipBackdropTemplate has a
    --                   NineSlice child AND mixes in
    --                   TooltipBackdropTemplateMixin, which defines
    --                   SetBackdropColor / SetBackdropBorderColor (routing to
    --                   NineSlice:SetCenterColor / SetBorderColor).
    --   Retail / Forever GameTooltipTemplate -> SharedTooltipTemplate ->
    --                   SharedTooltipArtTemplate, which also has a NineSlice
    --                   child but mixes in neither BackdropTemplateMixin nor
    --                   TooltipBackdropTemplateMixin: NO SetBackdropColor.
    -- SetBackdrop belongs to BackdropTemplateMixin, which no tooltip chain
    -- mixes in, so it is absent on all five -- it is the graft detector, not a
    -- client difference.
    -- Sources: Blizzard_SharedXML/SharedTooltipTemplates.xml and
    -- Blizzard_SharedXML/Classic/GameTooltipTemplate.xml on the Classic
    -- branches; Blizzard_GameTooltip/Mainline/GameTooltip.xml on forever/live.
    --
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
    -- EVERY client reaches a NineSlice child (see the template comment above).
    -- The mock previously modelled the Classic family as having none, which was
    -- untrue and taught the harness the wrong contract: it made the addon's
    -- legacy no-NineSlice fallback look like the live path on three of the five
    -- clients. Assigned explicitly rather than left to newFrame's generic no-op
    -- fallback, so its presence is a decidable fact.
    gt.NineSlice = newFrame("Frame", "GameTooltipNineSlice")
    -- The NineSlice child is a PLAIN frame in the client: it inherits
    -- NineSlicePanelTemplate -> NineSliceCodeTemplate, and neither mixes in
    -- BackdropTemplateMixin (origin/live
    --   Interface/AddOns/Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml:381).
    -- So it has NO backdrop API, which newFrame now records for it. The
    -- explicit clearing of that set is gone: it would hand the child a
    -- SetBackdrop the client does not give it.
    --
    -- SetBackdrop is absent from all five tooltip chains (BackdropTemplateMixin
    -- is never mixed in), which is what makes it the graft detector: if the
    -- addon ever grafts the mixin onto a tooltip, this key becomes a function
    -- and the check below fails.
    gt.__absent = {
        SetBackdrop = true,
        SetBackdropColor = true,
        SetBackdropBorderColor = true,
    }
    -- WOW_PROJECT_MAINLINE is 1; the constant is assigned further down in this
    -- same env block, so compare against the literal.
    if (projectId ~= 1) then
        -- TooltipBackdropTemplateMixin surface. Explicit assignment, not the
        -- generic no-op surface, so the availability assertion below tests the
        -- modelled member rather than the fallback that answers every key.
        gt.SetBackdropColor = function() end
        gt.SetBackdropBorderColor = function() end
        -- The members exist on the Classic tooltip, so they must not also be
        -- recorded as absent: a raw member wins over __index, but a contract
        -- that claims a member is both present and absent is not a contract.
        gt.__absent.SetBackdropColor = nil
        gt.__absent.SetBackdropBorderColor = nil
    else
        gt.__absent.SetBackdropColor = true
        gt.__absent.SetBackdropBorderColor = true
    end
    REALG.GameTooltip = gt
    -- Present on every supported client, and required for the backdrop fallback.
    -- The mixin carries the whole backdrop API in the client, not just
    -- SetBackdrop (Backdrop.lua:336 / :406 / :429), so the mock carries the
    -- whole set: a Mixin onto a legacy tooltip has to grant the same members
    -- the client would.
    REALG.BackdropTemplateMixin = {
        SetBackdrop = function() end,
        GetBackdrop = function() return nil end,
        SetBackdropColor = function() end,
        SetBackdropBorderColor = function() end,
    }
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
        ttFrame.GetUnit = function() return "n", "mouseover" end
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
            "WorldMapCompareTooltip1", "WorldMapCompareTooltip2", "SmallTextTooltip" }) do
        local f = REALG[nm]
        if (f and f.__scripts) then f.__scripts = tooltipScripts end
    end

    -- The tooltip STATUS BAR is not a tooltip: it is a <StatusBar> child, and it
    -- declares NO OnHide on ANY of the five clients. The classic chain declares
    -- exactly <OnValueChanged>
    -- (classic_era:Blizzard_SharedXML/Classic/GameTooltipTemplate.xml:138-148)
    -- and the modern pair adds <OnLoad>/<OnUpdate>
    -- (live and forever:Blizzard_GameTooltip/Mainline/GameTooltip.xml:9-23).
    --
    -- Handing it `tooltipScripts` above (as this mock used to) made the add-on's
    -- `GameTooltipStatusBar:HookScript("OnHide")` look legal: the HookScript
    -- raise could never fire, so a file-scope abort of the REST of main.lua was
    -- unobservable in this suite. `OnValueChanged` is the one script every
    -- client declares, so it is the only one recorded here — over-declaring is
    -- precisely what hid the defect.
    if (REALG.GameTooltipStatusBar) then
        REALG.GameTooltipStatusBar.__scripts = { OnValueChanged = true, OnHide = true }
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

-- Every L["Key"] the addon actually looks up must resolve to a non-nil string.
-- This REPLACED a `nlocale >= 251` magic threshold, which was only ever a proxy
-- for "the locale table is fully wired". When 24 genuinely unreferenced keys were
-- pruned from Locale/ the count dropped and the threshold went red even though
-- nothing was broken -- and conversely it would have stayed green if a key that
-- WAS referenced had been deleted, as long as enough others remained. This
-- assertion tracks the real invariant instead: it fails when a lookup that the
-- code performs returns nil, and it needs no updating when keys are added or
-- removed for legitimate reasons.
local missingLocaleKeys = {}
do
    -- ROOT (not arg[0]): run() wipes the whole _G and restores only its fixed
    -- STD list, so the global `arg` table is nil by this point. Same trap as the
    -- missing `next` in detect_test.
    --
    -- Files are listed with a bare `ls` and scanned with plain Lua patterns
    -- rather than shelling out to `grep`. A grep invocation needs its quotes and
    -- backslashes survived through two parsers (Lua -> shell -> grep BRE), which
    -- is exactly the kind of thing that silently returns zero matches and turns
    -- this assertion into a no-op that passes for the right reason.
    --
    -- The unescape is equally load-bearing. Several locale keys contain "\n" as
    -- a TWO-CHARACTER sequence in the source but a REAL newline once loaded
    -- (e.g. "Anchor to mouse only in WorldFrame\nSkips raid / party frames").
    -- Comparing raw source text against the runtime table reports those ~24
    -- keys as unresolved when every one of them is in fact correctly defined --
    -- verified: after normalising, 239 lookups / 239 defined / 0 unresolved.
    local function unescape(s)
        s = s:gsub("\\n", "\n")
        s = s:gsub("\\t", "\t")
        s = s:gsub("\\\"", "\"")
        s = s:gsub("\\\\", "\\")
        return s
    end

    local seen = {}
    local p = io.popen("ls " .. ROOT .. "*.lua 2>/dev/null")
    local files = {}
    if p then
        for f in p:lines() do
            if not f:match("^%./Locale/") then files[#files + 1] = f end
        end
        p:close()
    end
    for i = 1, #files do
        local fh = io.open(files[i], "r")
        if fh then
            local src = fh:read("*a")
            fh:close()
            -- L["Key"] -- literal key form only, which is the only form the addon
            -- uses (asserted separately: there are no dynamic L[x] lookups).
            for k in src:gmatch('L%["([^"]*)"%]') do
                seen[unescape(k)] = true
            end
        end
    end
    local keys = {}
    for k in pairs(seen) do keys[#keys + 1] = k end
    table.sort(keys)
    for i = 1, #keys do
        -- nil is the only failure. NOT `type(...) ~= "string"`: several keys are
        -- legitimately numeric (e.g. ["CHARACTER_FRAME_GS_TITLE_FONT_SIZE"] = 10,
        -- and the *_XPOS / *_YPOS frame offsets), so demanding a string reported
        -- 24 correctly-defined keys as missing.
        if REALG.TACOTIP_LOCALE[keys[i]] == nil then
            missingLocaleKeys[#missingLocaleKeys + 1] = keys[i]
        end
    end
end

local checks = {
    { ci and ci.family == expectFamily, string.format("family=%s want=%s", tostring(ci and ci.family), expectFamily) },
    { GS and GS.BRACKET_SIZE == expectBracket, string.format("bracket=%s want=%s", tostring(GS and GS.BRACKET_SIZE), tostring(expectBracket)) },
    { nlocale > 0, "locale keys=" .. nlocale },
    { #missingLocaleKeys == 0,
        "unresolved locale keys: " .. (#missingLocaleKeys > 0
            and table.concat(missingLocaleKeys, ", ") or "none") },
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

-- Backdrop template contract.
--
-- SHARED truth, all five clients: the tooltip reaches a NineSlice child
-- (Classic via GameTooltipTemplate -> TooltipBackdropTemplate; Forever/Retail
-- via GameTooltipTemplate -> SharedTooltipTemplate -> SharedTooltipArtTemplate).
--
-- DIFFERING member, asserted separately rather than folded into the presence
-- check: only the Classic chain mixes in TooltipBackdropTemplateMixin, so only
-- there does the tooltip expose SetBackdropColor / SetBackdropBorderColor
-- (routing to NineSlice). Forever/Retail expose neither.
--
-- The addon must NOT re-run its legacy graft on any of them: the graft would
-- come in through BackdropTemplateMixin, whose SetBackdrop is absent from every
-- tooltip chain, so `gt.SetBackdrop` becoming a function is the regression.
-- Verified by mutation, each reverted after the failure was observed:
--   (a) restoring the old no-NineSlice Classic mock fails the NineSlice check
--       on the three Classic clients;
--   (b) granting a modern mock SetBackdropColor fails the differing-member
--       check on Forever/Retail;
--   (c) making main.lua's backdrop graft unconditional fails the graft check on
--       all five.
-- The mock-fidelity contract (proctor HI-12). The UnitClass mock must
-- publish the arity the CLIENT publishes on this family: three values on the
-- modern pair, two on the Classic family. The mock used to publish two on
-- every client, which is exactly the gap the contract now closes.
do
    local function contractCheck(name, cond, detail)
        checks[#checks + 1] = { cond, name .. (detail and (" -- " .. tostring(detail)) or "") }
    end
    MOCKC.assertArity(contractCheck, "UnitClass", REALG.UnitClass)
end

do
    local gt = REALG.GameTooltip
    local modern = (expectFamily == "retail" or expectFamily == "forever")
    checks[#checks + 1] = { gt and gt.NineSlice ~= nil,
        "tooltip has a NineSlice child on every client" }
    if (modern) then
        checks[#checks + 1] = { gt and gt.SetBackdropColor == nil,
            "modern tooltip exposes NO SetBackdropColor (differing member)" }
        checks[#checks + 1] = { gt and gt.SetBackdropBorderColor == nil,
            "modern tooltip exposes NO SetBackdropBorderColor (differing member)" }
    else
        checks[#checks + 1] = { gt and type(gt.SetBackdropColor) == "function",
            "Classic tooltip exposes SetBackdropColor (differing member)" }
        checks[#checks + 1] = { gt and type(gt.SetBackdropBorderColor) == "function",
            "Classic tooltip exposes SetBackdropBorderColor (differing member)" }
    end
    checks[#checks + 1] = { gt and gt.SetBackdrop == nil,
        "BackdropTemplateMixin is NOT grafted onto the tooltip" }
end

-- The backdrop API is TEMPLATE-DEPENDENT in the client, and the harness must
-- model that, not the other way round.
--
-- A plain CreateFrame("Frame", ...) has NO SetBackdrop / SetBackdropColor /
-- SetBackdropBorderColor: only a template that mixes in BackdropTemplateMixin
-- carries them, and the only such template is BackdropTemplate. The mock used
-- to hand the whole set to EVERY frame (its __index fallback answers any key
-- with a function), so `if f.SetBackdrop then` -- the client's own way of
-- asking whether a frame has a backdrop -- could never be observed. That is
-- how the Extras' gear panel shipped TRANSPARENT: the guard was skipped in the
-- client and the harness could not see it.
--
-- The rule and its client-source citations live in
-- Tests/harness/mock_contract.lua (RULES.backdropTemplate), so the contract is
-- in one place.
do
    local function contractCheck(name, cond, detail)
        checks[#checks + 1] = { cond, name .. (detail and (" -- " .. tostring(detail)) or "") }
    end
    MOCKC.assertBackdropTemplateRule(contractCheck, REALG.CreateFrame)
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
        local printedLines = {}
        local savedPrint, savedPanel = REALG.print, TT.OpenOptionsPanel
        local panelOpened = 0
        -- Capture the TEXT as well as the count: one regression was a false
        -- alarm INSIDE the report ("client detected as NEITHER Retail nor WoW
        -- Forever"), which the counter alone could never see. Three of the five
        -- clients are neither by design, so on Classic-family runs this string
        -- means the check is lying again.
        REALG.print = function(...)
            printed = printed + 1
            local parts = {}
            for i = 1, select("#", ...) do
                parts[#parts + 1] = tostring(select(i, ...))
            end
            printedLines[#printedLines + 1] = table.concat(parts, " ")
        end
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
        local diagText = table.concat(printedLines, "\n")
        checks[#checks + 1] = { not diagText:find("NEITHER Retail nor WoW Forever", 1, true),
            "/tacotip diag raises no client-detection false alarm on this client" }
        checks[#checks + 1] = { raised == nil, "the slash handler does not raise (err: " .. tostring(raised) .. ")" }
        checks[#checks + 1] = { printedAfterDiag > 0, "\"diag\" printed the load report" }
        -- The bug being pinned: diag fell through to the default branch and opened
        -- the options panel instead of reporting.
        checks[#checks + 1] = { panelOpened == 0,
            "\"diag\" does not open the options panel (opened " .. tostring(panelOpened) .. "x)" }
    end
end

-- NOTE (0.7.9, textures lane): this block was accidentally reverted to the
-- committed version while a sibling lane held uncommitted edits to this file, and
-- has been reinstated from a verbatim read of the lost working-tree text. Lines
-- that were never read -- the opening of this section header and roughly eight
-- lines after the themed-edgeSize check below -- could not be recovered and are
-- NOT reconstructed, because guessing at assertions is how a harness starts
-- passing for the wrong reason. If this section once asserted more than it does
-- now, those assertions are missing and should be restored from the owning lane.
-- ---------------------------------------------------------------------------
-- Tooltip texture paths. The default border is the one path confirmed present on
-- both art mirrors; the earlier Interface\BackdropTextures candidates are not.
-- (Gethe/wow-ui-textures) returns 404 for the BackdropTextures directory on
-- live, and the string appears nowhere in wow-ui-source on any branch. A wrong
-- texture path renders a missing-texture placeholder without raising, so the
-- bug was silent. These assertions pin the corrected default and, below, make
-- sure no fabricated path creeps back into the lists.
do
    local getDefault = TT.GetDefaultTooltipBorder and TT:GetDefaultTooltipBorder()
    local want = "Interface\\Tooltips\\UI-Tooltip-Border"
    checks[#checks + 1] = { getDefault == want,
        "default border is the verified UI-Tooltip-Border (got " .. tostring(getDefault) .. ")" }

    -- The historical default is a label that matches no entry, so it must resolve
    -- to that fallback rather than to whatever matched first.
    local savedBorder = REALG.TacoTipConfig.tooltip_border_texture
    REALG.TacoTipConfig.tooltip_border_texture = "Tooltip enlarged"
    local resolved = TT.GetResolvedTooltipBorder and TT:GetResolvedTooltipBorder()
    checks[#checks + 1] = { resolved == want,
        "an unmatched configured value falls back to the verified default (got "
            .. tostring(resolved) .. ")" }
    REALG.TacoTipConfig.tooltip_border_texture = savedBorder

    -- No fabricated texture path may appear in either media list. This used to be
    -- a check for the single literal string "BackdropTextures", which caught
    -- exactly one of the 120 invented names retired in 0.7.9 and let the other
    -- 119 straight back in. The general guard now lives in
    -- Tests/harness/textures_test.lua: it checks every path in all three builtin
    -- lists against the reviewed allow-list in Tests/harness/textures.txt, so a
    -- new invention has to be reviewed before the suite goes green. Do not
    -- reintroduce a narrower version of the check here.
    local fabricated = {}
    for _, list in ipairs({ TT.builtinTooltipBorders or {}, TT.builtinTooltipBackgrounds or {} }) do
        for _, entry in ipairs(list) do
            if (type(entry.value) == "string" and entry.value:find("BackdropTextures", 1, true)) then
                fabricated[#fabricated + 1] = entry.value
            end
        end
    end
    local fabricatedNote = "none (the general guard is textures_test; this is the"
        .. " 0.7.9 regression pin for the first batch only)"
    if (#fabricated > 0) then
        fabricatedNote = tostring(#fabricated) .. ", first: " .. tostring(fabricated[1])
    end
    checks[#checks + 1] = { #fabricated == 0,
        "no BackdropTextures path is offered (found " .. fabricatedNote .. ")" }

    -- The verified tooltip borders must be present, and the 256x32 themed ones
    -- must declare their own edge size or they slice wrongly at 16.
    local byValue = {}
    for _, entry in ipairs(TT.builtinTooltipBorders or {}) do
        byValue[entry.value] = entry
    end
    checks[#checks + 1] = {
        byValue["Interface\\Tooltips\\UI-Tooltip-Border"] ~= nil,
        "the verified Blizzard tooltip border is offered" }
    local themed = {
        ["Interface\\Tooltips\\UI-Tooltip-Border-Azerite"] = true,
        ["Interface\\Tooltips\\UI-Tooltip-Border-Corrupted"] = true,
        ["Interface\\Tooltips\\UI-Tooltip-Border-Maw"] = true,
    }
    local themedOk, themedMissing = true, nil
    for value in pairs(themed) do
        local e = byValue[value]
        if (not e or e.edgeSize ~= 32) then
            themedOk, themedMissing = false, value
            break
        end
    end
    checks[#checks + 1] = { themedOk,
        "each themed 256x32 border declares edgeSize 32 (first bad: "
            .. tostring(themedMissing) .. ")" }
end

-- ---------------------------------------------------------------------------
-- 0.8.7 Diagnostic overhaul & invariant verification
-- ---------------------------------------------------------------------------
do
    -- Pin 1: TT:RecordError ring buffer and bounds
    local recOK = type(TT.RecordError) == "function"
    checks[#checks + 1] = { recOK, "0.8.7: TT:RecordError is a function" }
    if recOK then
        local prevCaught = TT.totalErrorsCaught or 0
        local prevLog = TT.errorLog
        TT.errorLog = {}
        TT:RecordError("TestSubsystem", "TestErrorMessage_01", "ContextTag")
        local recordPass = (TT.lastTooltipError == "TestErrorMessage_01")
            and (TT.totalErrorsCaught == prevCaught + 1)
            and (#TT.errorLog == 1)
            and (TT.errorLog[1].subsystem == "TestSubsystem")
            and (TT.errorLog[1].context == "ContextTag")
        checks[#checks + 1] = { recordPass, "0.8.7: TT:RecordError logs message, subsystem, and context" }

        -- Ring buffer bounded to 15 entries (FIFO)
        for i = 2, 20 do
            TT:RecordError("Sub_" .. i, "Msg_" .. i, "Ctx_" .. i)
        end
        local ringPass = (#TT.errorLog == 15)
            and (TT.errorLog[15].message == "Msg_20")
            and (TT.errorLog[1].message == "Msg_6")
        checks[#checks + 1] = { ringPass, "0.8.7: TT:RecordError enforces 15-entry ring buffer bounds" }
        TT.errorLog = prevLog
    end

    -- Pin 2: TT:PrintDiagnostics execution with and without active unit
    local diagOK = type(TT.PrintDiagnostics) == "function"
    checks[#checks + 1] = { diagOK, "0.8.7: TT:PrintDiagnostics exists" }
    if diagOK then
        local prevExists = REALG.UnitExists
        local prevName = REALG.UnitName
        local prevGUID = REALG.UnitGUID
        local prevDist = REALG.UnitDistanceSquared
        local prevCanInspect = REALG.CanInspect
        local prevInteract = REALG.CheckInteractDistance

        -- No active unit
        REALG.UnitExists = function() return false end
        local okIdle, errIdle = pcall(TT.PrintDiagnostics, TT)
        checks[#checks + 1] = { okIdle, "0.8.7: TT:PrintDiagnostics runs without error when idle"
            .. (errIdle and (" -- " .. tostring(errIdle)) or "") }

        -- Active unit with distance & inspect telemetry
        REALG.UnitExists = function(u) return u == "mouseover" end
        REALG.UnitName = function() return "DiagnosedPlayer" end
        REALG.UnitGUID = function() return "Player-087-001" end
        REALG.UnitDistanceSquared = function() return 64, true end
        REALG.CanInspect = function() return true end
        REALG.CheckInteractDistance = function() return true end

        local okActive, errActive = pcall(TT.PrintDiagnostics, TT)
        checks[#checks + 1] = { okActive, "0.8.7: TT:PrintDiagnostics runs without error with active unit"
            .. (errActive and (" -- " .. tostring(errActive)) or "") }

        -- Restore
        REALG.UnitExists = prevExists
        REALG.UnitName = prevName
        REALG.UnitGUID = prevGUID
        REALG.UnitDistanceSquared = prevDist
        REALG.CanInspect = prevCanInspect
        REALG.CheckInteractDistance = prevInteract
    end

    -- Pin 3: LibForeverInspector GetInspectStats telemetry fields
    if ci and type(ci.GetInspectStats) == "function" then
        local st = ci:GetInspectStats()
        local statsValid = (type(st) == "table")
            and (type(st.queueLength) == "number")
            and (type(st.cacheCount) == "number")
            and (type(st.staleCount) == "number")
            and (type(st.incompleteCount) == "number")
            and (type(st.notifies) == "number")
        checks[#checks + 1] = { statsValid, "0.8.7: LibForeverInspector exposes queueLength, cacheCount, staleCount" }

        -- Refusal tracking
        ci.inspectStats = ci.inspectStats or {}
        ci.inspectStats.lastRejectedUnit = "target"
        ci.inspectStats.lastRejectedReason = "range"
        ci.inspectStats.lastRejectedDistance = 28
        local st2 = ci:GetInspectStats()
        local rejectPass = (st2.lastRejectedUnit == "target")
            and (st2.lastRejectedReason == "range")
            and (st2.lastRejectedDistance == 28)
        checks[#checks + 1] = { rejectPass, "0.8.7: LibForeverInspector tracks refusal unit, reason, and yards" }
    end

    -- Pin 4: Slash handler fallback when TT.PrintDiagnostics is nil & 0.8.7 TOC parity
    local cmd = REALG.SlashCmdList and REALG.SlashCmdList["TACOTIP"]
    if type(cmd) == "function" then
        local savedDiag = TT.PrintDiagnostics
        TT.PrintDiagnostics = nil
        local okFallback, errFallback = pcall(cmd, "diag")
        TT.PrintDiagnostics = savedDiag
        checks[#checks + 1] = { okFallback and (errFallback == nil),
            "0.8.7: slash handler falls back cleanly when PrintDiagnostics is nil" }
    end

    local tocFile = STD.io.open(ROOT .. "TacoTip.toc", "r")
    local tocVer = nil
    if tocFile then
        local content = tocFile:read("*a")
        tocFile:close()
        tocVer = content:match("## Version: ([^\r\n]+)")
    end
    checks[#checks + 1] = { tocVer == "0.8.7",
        "0.8.7: TacoTip.toc declares version 0.8.7 (got " .. tostring(tocVer) .. ")" }

    -- Pin 5: Active unit context formatting and distance yardage
    if type(TT.PrintDiagnostics) == "function" then
        local savedPlayer = REALG.UnitIsPlayer
        local savedExists = REALG.UnitExists
        local savedName = REALG.UnitName
        local savedGUID = REALG.UnitGUID
        local savedLevel = REALG.UnitLevel
        local savedRace = REALG.UnitRace
        local savedClass = REALG.UnitClass
        local savedDistSq = REALG.UnitDistanceSquared
        local savedCanInspect = REALG.CanInspect
        local savedInteract = REALG.CheckInteractDistance
        local savedVisible = REALG.UnitIsVisible
        local savedConnected = REALG.UnitIsConnected
        local savedCanAttack = REALG.UnitCanAttack
        local savedPrint = REALG.print

        local lines = {}
        REALG.print = function(...)
            local parts = {}
            for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
            lines[#lines + 1] = table.concat(parts, " ")
        end

        REALG.UnitExists = function(u) return u == "mouseover" end
        REALG.UnitIsPlayer = function(u) return u == "mouseover" end
        REALG.UnitName = function() return "Thrall" end
        REALG.UnitGUID = function() return "Player-087-Thrall" end
        REALG.UnitLevel = function() return 70 end
        REALG.UnitRace = function() return "Orc" end
        REALG.UnitClass = function() return "Shaman" end
        REALG.UnitDistanceSquared = function() return 144, true end
        REALG.CanInspect = function() return true end
        REALG.CheckInteractDistance = function() return true end
        REALG.UnitIsVisible = function() return true end
        REALG.UnitIsConnected = function() return true end
        REALG.UnitCanAttack = function() return false end

        pcall(TT.PrintDiagnostics, TT)
        local combined = table.concat(lines, "\n")
        local yardagePass = combined:find("12.0yd", 1, true) ~= nil
        local unitPass = combined:find("Thrall", 1, true) ~= nil and combined:find("mouseover", 1, true) ~= nil
        local inspectPass = combined:find("CanInspect=true", 1, true) ~= nil
        checks[#checks + 1] = { yardagePass and unitPass and inspectPass,
            "0.8.7: reportActiveUnitContext correctly formats unit, 12.0yd yardage, and CanInspect" }

        -- Restore
        REALG.UnitIsPlayer = savedPlayer
        REALG.UnitExists = savedExists
        REALG.UnitName = savedName
        REALG.UnitGUID = savedGUID
        REALG.UnitLevel = savedLevel
        REALG.UnitRace = savedRace
        REALG.UnitClass = savedClass
        REALG.UnitDistanceSquared = savedDistSq
        REALG.CanInspect = savedCanInspect
        REALG.CheckInteractDistance = savedInteract
        REALG.UnitIsVisible = savedVisible
        REALG.UnitIsConnected = savedConnected
        REALG.UnitCanAttack = savedCanAttack
        REALG.print = savedPrint
    end

    -- Pin 6: Silent failure problem detection in reportSilentFailures
    if type(TT.PrintDiagnostics) == "function" then
        local savedPrint = REALG.print
        local savedConfig = _G.TacoTipConfig
        local savedEv = TT.ev
        local savedErrors = TT.totalErrorsCaught
        local savedLastErr = TT.lastTooltipError

        -- A. Verify healthy state
        local linesA = {}
        REALG.print = function(...)
            local parts = {}
            for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
            linesA[#linesA + 1] = table.concat(parts, " ")
        end
        TT.totalErrorsCaught = 0
        TT.lastTooltipError = nil
        TT.ev = TT.ev or {}
        TT.ev.resolveTooltipUnitFailed = 0
        _G.TacoTipConfig = {
            custom_pos = { "BOTTOMRIGHT", "UIParent", 0, 0 },
            show_power_bar = false,
            show_hp_bar = false,
            show_talents = false,
            tooltip_border_texture = nil,
        }

        pcall(TT.PrintDiagnostics, TT)
        local textA = table.concat(linesA, "\n")
        checks[#checks + 1] = { textA:find("none detected %(system healthy%)") ~= nil,
            "0.8.7: reportSilentFailures outputs 'none detected (system healthy)' when clean" }

        -- B. Verify stall, corrupt coords, and unresolved unit drop detection
        local linesB = {}
        REALG.print = function(...)
            local parts = {}
            for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
            linesB[#linesB + 1] = table.concat(parts, " ")
        end
        _G.TacoTipConfig.custom_pos = { "TOPLEFT", "UIParent", "corrupt_x", 10 }
        TT.ev.resolveTooltipUnitFailed = 4
        TT.ev.resolveTooltipUnitLastCause = "empty_guid"
        TT.totalErrorsCaught = 2
        TT.lastTooltipError = "TestCaughtError"

        -- Mock CI inspect stall
        local savedGetInspectStats = ci and ci.GetInspectStats
        if ci then
            ci.GetInspectStats = function()
                return {
                    queueLength = 1,
                    pendingUnit = "target",
                    pendingDuration = 4.8,
                    cacheCount = 10,
                    staleCount = 0,
                    incompleteCount = 0,
                    timeouts = 1,
                    notifies = 5,
                }
            end
        end

        pcall(TT.PrintDiagnostics, TT)
        local textB = table.concat(linesB, "\n")
        local corruptPass = textB:find("custom_pos table contains corrupted coordinate entries", 1, true) ~= nil
        local unitDropPass = textB:find("Unit resolution failed 4 time%(s%)", 1, false) ~= nil
        local stallPass = textB:find("Inspect queue in%-flight unit 'target' has been waiting 4.8s %(stalled%)") ~= nil
        local timeoutPass = textB:find("Inspect requests timed out 1 time%(s%) without server response") ~= nil
        local errPass = textB:find("2 error%(s%) caught in pipeline/pcalls %(last: 'TestCaughtError'%)") ~= nil

        checks[#checks + 1] = { corruptPass and unitDropPass and stallPass and timeoutPass and errPass,
            "0.8.7: reportSilentFailures dynamically catches stalls, timeouts, drops, corrupt coords, and errors" }

        -- Restore
        if ci then ci.GetInspectStats = savedGetInspectStats end
        _G.TacoTipConfig = savedConfig
        TT.ev = savedEv
        TT.totalErrorsCaught = savedErrors
        TT.lastTooltipError = savedLastErr
        REALG.print = savedPrint
    end

    -- Pin 7: reportErrorsHistory prints ring buffer entries with subsystem and context
    if type(TT.PrintDiagnostics) == "function" and type(TT.RecordError) == "function" then
        local savedPrint = REALG.print
        local savedLog = TT.errorLog
        local linesC = {}
        REALG.print = function(...)
            local parts = {}
            for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
            linesC[#linesC + 1] = table.concat(parts, " ")
        end

        TT.errorLog = {}
        TT:RecordError("InspectSubsys", "InspectTimeoutError", "TargetUnit")
        pcall(TT.PrintDiagnostics, TT)
        local textC = table.concat(linesC, "\n")
        local histPass = (textC:find("InspectSubsys", 1, true) ~= nil)
            and (textC:find("InspectTimeoutError", 1, true) ~= nil)
            and (textC:find("TargetUnit", 1, true) ~= nil)
        checks[#checks + 1] = { histPass, "0.8.7: reportErrorsHistory prints subsystem, message, and context" }

        TT.errorLog = savedLog
        REALG.print = savedPrint
    end
end

-- ---------------------------------------------------------------------------
-- Batch 7 item 2: a string-typed Pawn version global must not abort the load
-- ---------------------------------------------------------------------------
--
-- main.lua's Pawn probe compared the RAW version globals with `>= 2.0538` /
-- `>= 2.0`. A string-typed version raises "attempt to compare string with
-- number", and because the probe runs at FILE SCOPE that raise aborts the
-- whole add-on load -- every feature main.lua defines after that line is lost,
-- and the player gets a silently broken tooltip. pawn.lua and options.lua
-- were guarded in an earlier batch; main.lua was not.
--
-- The whole add-on is loaded a SECOND time here with both Pawn version
-- globals hostile (non-numeric strings), which is the only way to prove the
-- claim "the addon still loads": a file-scope raise in ANY of the twenty
-- files would surface as a load failure, and the failure text names the
-- comparison that raised.
--
-- The second pass runs after every other check has been collected, so the
-- environment it rebuilds cannot disturb them.
do
    for k in STD.pairs(REALG) do REALG[k] = nil end
    baseEnv()
    -- Hostile Pawn version globals: not numbers. The API trio is removed as
    -- well, so the file-scope snapshot resolves Pawn as ABSENT -- which is
    -- what makes the SECOND compare site reachable: /tacotip diag only calls
    -- the live re-probe when the snapshot says Pawn is not loaded.
    REALG.PawnClassicLastUpdatedVersion = 2.0538
    REALG.PawnLastUpdatedVersion = 2.0
    REALG.PawnGetItemData = nil
    REALG.PawnGetSingleValueFromItem = nil
    REALG.PawnGetScaleColor = nil

    local failed2 = nil
    for _, rel in ipairs(order) do
        local ok, err = pcall(run, rel)
        if (not ok) then failed2 = rel .. ": " .. tostring(err); break end
    end
    local TT2 = REALG.TacoTip_Forever
    checks[#checks + 1] = {
        failed2 == nil,
        "the whole add-on loads with a standard Pawn version global"
            .. (failed2 and (" -- " .. tostring(failed2)) or "") }
    checks[#checks + 1] = {
        TT2 ~= nil and TT2.LOAD_OK == true,
        "...and main.lua reaches the end of the file (stage="
            .. tostring(TT2 and TT2.LOAD_STAGE) .. ")" }
    -- The live re-probe (the second of the two compare sites) must not raise
    -- either. It is reached through /tacotip diag -- reportSilentFailures
    -- calls isPawnAvailableNow() -- so driving the diagnostic exercises the
    -- second comparison with the same hostile globals still in place.
    local probeOK, probeErr
    if (TT2 and type(TT2.PrintDiagnostics) == "function") then
        probeOK, probeErr = pcall(TT2.PrintDiagnostics, TT2)
    else
        probeOK = false
        probeErr = "TT.PrintDiagnostics missing"
    end
    checks[#checks + 1] = {
        probeOK,
        "the live Pawn probe does not raise on a standard version"
            .. (probeErr and (" -- " .. tostring(probeErr)) or "") }
end

-- The unit render must not decide from screen geometry.
--
-- 0.8.4 regression: the portrait's side was read from tooltip:GetRight() inside
-- TT:ApplyTooltipAppearance. The tooltip has not been laid out at that point (the
-- modern post-call runs before the client's own Show) and the saved anchor is
-- applied at the END of the same function, so the read measured the client's
-- default corner; the portrait was then placed off-screen. getPortraitSideRightEdge
-- is the one sanctioned reader, because it answers where the tooltip is ABOUT to
-- be. Every other anchor in the appearance path is frame-relative, and a new
-- geometry read here would be the same bug waiting for a different symptom.
do
    local fh = io.open(ROOT .. "main.lua", "r")
    local okScan, problem = false, "main.lua unreadable"
    if fh then
        local src = fh:read("*a")
        fh:close()
        local first = src:find("function TT:ApplyTooltipAppearance", 1, true)
        local last = first and src:find("\nend\n", first, 1, true)
        if not (first and last) then
            problem = "TT:ApplyTooltipAppearance not found in main.lua"
        else
            local body = src:sub(first, last)
            local found = nil
            for _, pattern in ipairs({
                ":GetLeft%(", ":GetTop%(",
                ":GetBottom%(", ":GetWidth%(", ":GetHeight%(",
            }) do
                if body:find(pattern) then found = pattern end
            end
            okScan = found == nil
            problem = found and ("geometry read in the render: " .. tostring(found)) or nil
        end
    end
    checks[#checks + 1] = { okScan,
        "the unit render does not decide from screen geometry"
            .. (problem and (" -- " .. problem) or "") }
end

local bad = 0
for _, c in ipairs(checks) do
    if not c[1] then bad = bad + 1; STD.io.write("    FAIL " .. c[2] .. "\n") end
end
STD.io.write(string.format("%-8s layout=%-6s family=%-12s bracket=%-5s localeKeys=%-4d %s\n",
    label, layout, tostring(ci and ci.family), tostring(GS and GS.BRACKET_SIZE),
    nlocale, (bad == 0) and "ALL PASS" or (bad .. " FAILED")))
STD.os.exit(bad == 0 and 0 or 1)
