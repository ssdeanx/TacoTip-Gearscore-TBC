--[[

    TacoTip GearScore module
    for WoW Forever & Retail

--]]

local addOnName = ...

assert(LibStub, "TacoTip requires LibStub")
assert(LibStub:GetLibrary("LibForeverInspector", true), "TacoTip requires LibForeverInspector")
assert(LibStub:GetLibrary("LibDetours-1.0", true), "TacoTip requires LibDetours-1.0")

local CI = LibStub("LibForeverInspector")
local TT = _G[addOnName]
local L = _G.TACOTIP_LOCALE

if (not TT) then
    TT = {}
    rawset(_G, addOnName, TT)
end

-- ---------------------------------------------------------------------------
-- Companion add-on slash forwarding
-- ---------------------------------------------------------------------------
-- TacoTip Extras registers its own slash commands, and six of them live
-- under this add-on's "/tt" alias: "/tt lb", "/tt rank", "/tt ranks",
-- "/tt leaderboard", "/tt gs" and "/tt gsdebug" (plus the unambiguous
-- "/ttrank", "/ttranks", "/ttleaderboard", "/ttgs" and "/ttgsdebug", which
-- the Extras registers itself and which nothing here touches).
--
-- HOW THE CLIENT DISPATCHES (the reason this forwarding exists at all).
-- The client is deterministic, NOT a race over prefixes. It splits the typed
-- text at the FIRST whitespace and looks up ONLY that token:
--
--   origin/classic_era, origin/classic_anniversary, origin/classic_titan,
--   origin/forever, origin/live --
--   Interface/AddOns/Blizzard_ChatFrameBase/Shared/ChatFrameEditBox.lua:222
--       local command = strmatch(text, "^(/[^%s]+)") or "";
--   ... :230  command = strupper(command);
--   ... :257  if ( hash_SlashCmdList[command] ) then
--   ... :259      hash_SlashCmdList[command](strtrim(msg), self);
--
-- so "/tt lb" is dispatched as the command "/TT" with the ARGUMENT "lb", and
-- the owner of "/TT" -- this add-on -- must forward that argument itself. The
-- Extras' own "/tt lb" alias can never fire, because the client never looks
-- up a two-word alias. (Its single-token aliases "/ttrank" and friends are
-- separate commands and are untouched.)
--
-- WHY THE RAWGET IN THE OLD RESOLVER NEVER FIRED. The client's SlashCmdList
-- is a PROXY table and the client empties it immediately before dispatching:
--
--   Interface/AddOns/Blizzard_ChatFrameBase/Shared/ChatFrameSetup.lua:3-11
--       setmetatable(list, { __index = {} })   -- applied to _G.SlashCmdList
--   Interface/AddOns/Blizzard_ChatFrameBase/Shared/ChatFrameUtil.lua:717-736
--       ImportListToHash: every registered handler is moved into
--       getmetatable(list).__index (line 732) and the REAL table is then
--       WIPED (line 735, securecallfunction(tWipe, list))
--   ChatFrameEditBox.lua:245 imports, :257/:259 dispatches
--
-- so at dispatch time the real table is EMPTY and rawget(SlashCmdList,
-- "TACOTIPRANKS") is nil on every client -- the old resolver looked there
-- and therefore never forwarded, and "/tt lb" opened the OPTIONS panel.
--
-- THE PROXY'S OWN KEY. The client's ImportListToHash copies a handler into
-- the proxy table under the LIST KEY it is iterating (ChatFrameUtil.lua:732,
--   proxyTable[k] = v
-- where k is the SlashCmdList key, e.g. "TACOTIPRANKS"), while the DISPATCH
-- hash is keyed by the uppercased alias (ChatFrameUtil.lua:720-725,
--   local tag = strupper(_G["SLASH_"..k..i]); hash[tag] = v
-- -- "/TT"). So a proxy read must use the LIST KEY NAME, never the
-- uppercased alias. The reads below use the key names.
--
-- Defensive by construction, because the Extras may be absent, half-loaded or
-- broken: SlashCmdList may not exist, the entry may be missing or may not be
-- a function, and the Extras handler itself may raise. The call is pcall'd,
-- so a broken Extras can never break "/tt" -- it only means the leaderboard
-- does not open. A raise is COUNTED and reported (see below), because a
-- silently swallowed raise is how a broken Extras looks like a missing one.
--
-- ONE implementation, published on the namespace so the final slash handler
-- (options.lua, which replaces the bootstrap handler below) shares it instead
-- of repeating the lookup.
--
-- The words this add-on forwards, and which Extras surface each one means:
--   lb / rank / ranks / leaderboard -> the server leaderboard toggle ("/ttrank")
--   gs                          -> the Extras' options category ("/ttgs")
--   gsdebug                      -> the Extras' diagnostic snapshot ("/ttgsdebug")
--
-- Neither "gs" nor "gsdebug" is a command of this add-on's own set
-- (custom|unlock|move|mover|save|default|reset|help|anchor|diag|diagnostics),
-- so forwarding them cannot steal any behaviour of this add-on.
--
-- The RESOLUTION ORDER for each word, and why:
--
--   1. The Extras' published plain global. A plain global survives the client's
--      wipe of the slash registry, and it is the SAME function object the
--      Extras' own slash entry invokes (identity, not a copy), so the two
--      cannot drift apart.
--        _G.TacoTipExtrasToggleLeaderboard  (TacoTip_Extras/RankBrowser.lua:3017)
--        _G.TacoTipExtrasPrintDebugSnapshot (TacoTip_Extras/Core.lua:1163-1165)
--   2. A PROXY-AWARE read of the Extras' slash entry, for an Extras build
--      that does not publish the global yet.
--   3. The other Extras slash entry, so a word still reaches the Extras when
--      only one of the two entries was registered.
local EXTRAS_COMMAND_TARGETS = {
    lb = "leaderboard",
    rank = "leaderboard",
    ranks = "leaderboard",
    leaderboard = "leaderboard",
    gs = "options",
    gsdebug = "debug",
}

-- A PROXY-AWARE read of one slash entry.
--
-- The client's SlashCmdList is a proxy table whose __index holds the handlers
-- the client imported out of the real table, so NORMAL indexing finds them
-- and a rawget does not. Both reads are tried, because the client's __index is
-- a plain table on all five supported branches but the explicit read is what
-- documents the mechanism.
local function proxySlashEntry(key)
    local slashCmdList = rawget(_G, "SlashCmdList")
    if (type(slashCmdList) ~= "table") then
        return nil
    end
    local handler = slashCmdList[key]
    if (type(handler) == "function") then
        return handler
    end
    local meta = getmetatable(slashCmdList)
    local index = meta and rawget(meta, "__index")
    if (type(index) == "table") then
        handler = rawget(index, key)
        if (type(handler) == "function") then
            return handler
        end
    end
    return nil
end

-- The Extras' handler for one forwarded word, or nil when the Extras cannot
-- serve it.
local function resolveExtrasHandler(cmd)
    local target = EXTRAS_COMMAND_TARGETS[cmd]
    if (not target) then
        return nil
    end
    if (target == "leaderboard") then
        local published = rawget(_G, "TacoTipExtrasToggleLeaderboard")
        if (type(published) == "function") then
            return published
        end
        return proxySlashEntry("TACOTIPRANKS")
    end
    if (target == "debug") then
        -- The Extras' diagnostic surface: its published global first, then its
        -- own slash entry.
        local published = rawget(_G, "TacoTipExtrasPrintDebugSnapshot")
        if (type(published) == "function") then
            return published
        end
        return proxySlashEntry("TTEXTRASDEBUG")
    end
    -- The Extras' options category: ITS OWN SLASH ENTRY, and nothing else.
    --
    -- M2: this used to fall back to the published debug-snapshot function (and
    -- then to the debug slash entry), so a MISSING options entry answered
    -- "/tt gs" with a telemetry dump instead of the options the player asked
    -- for -- the wrong surface, silently, with no way to tell it apart from
    -- the real thing. The fallback is gone: with no options entry there is
    -- nothing to forward to, so the word falls through to TacoTip's own
    -- options panel, which is what the player gets when the Extras is not
    -- installed at all.
    return proxySlashEntry("TTEXTRAS")
end

-- Report a raise inside the Extras' handler.
--
-- The house rule for a discarded pcall result (see main.lua's
-- handlePipelineError): COUNT it and SAY so. A raise here used to be
-- swallowed entirely, which made a broken Extras indistinguishable from an
-- absent one. One actionable line, once per distinct message, so a repeated
-- failure cannot flood the chat frame; the counter counts every failure.
local function reportExtrasForwardFailure(cmd, message)
    TT.ev = TT.ev or {}
    TT.ev.extrasForwardFailed = (TT.ev.extrasForwardFailed or 0) + 1
    TT.ev.extrasForwardLastCommand = cmd
    TT.ev.extrasForwardLastError = message
    TT.ev.extrasForwardReported = TT.ev.extrasForwardReported or {}
    if (TT.ev.extrasForwardReported[message]) then
        return
    end
    TT.ev.extrasForwardReported[message] = true
    print("|cff59f0dcTacoTip:|r TacoTip Extras could not run \"" .. tostring(cmd) .. "\": "
        .. tostring(message) .. " -- run /tacotip diag for the full report.")
end

-- Returns true when the word was handed to the Extras, so the caller does
-- NOT fall through to the options panel.
--
-- A raise inside the Extras' handler is still "handled": the player asked
-- for the Extras, so the options panel is not opened as well. The failure is
-- counted and reported instead.
local function forwardExtrasSlashCommand(cmd)
    if (type(cmd) ~= "string" or cmd == "") then
        return false
    end
    local handler = resolveExtrasHandler(cmd)
    if (type(handler) ~= "function") then
        return false
    end
    local ok, err = pcall(handler)
    if (not ok) then
        reportExtrasForwardFailure(cmd, tostring(err))
    end
    return true
end

TT.ForwardExtrasSlashCommand = forwardExtrasSlashCommand

local function registerBootstrapSlash()
    local slashCmdList = rawget(_G, "SlashCmdList")
    if (not slashCmdList) then
        slashCmdList = {}
        rawset(_G, "SlashCmdList", slashCmdList)
    end
    if (slashCmdList.TACOTIP) then
        return
    end

    SLASH_TACOTIP1 = "/tacotip"
    SLASH_TACOTIP2 = "/tooltip"
    SLASH_TACOTIP3 = "/tip"
    SLASH_TACOTIP4 = "/tt"
    SLASH_TACOTIP5 = "/gs"
    SLASH_TACOTIP6 = "/gearscore"
    SLASH_TACOTIP7 = "/taco"

    rawset(slashCmdList, "TACOTIP", function(msg)
        local cmd = strlower((msg or "")):gsub("^%s+", ""):gsub("%s+$", "")

        if (cmd == "custom" or cmd == "unlock" or cmd == "move" or cmd == "mover") then
            if (TacoTip_CustomPosEnable) then
                TacoTip_CustomPosEnable(true)
            else
                print("|cff59f0dcTacoTip:|r Loaded, but the tooltip mover is not ready yet.")
            end
        elseif (cmd == "save") then
            if (TacoTipDragButton and TacoTipDragButton.IsShown and TacoTipDragButton:IsShown()) then
                TacoTipDragButton:_Save()
            else
                print("|cff59f0dcTacoTip:|r Tooltip mover is not currently shown.")
            end
        elseif (cmd == "default") then
            if (TacoTipDragButton and TacoTipDragButton._Disable) then
                TacoTipDragButton:_Disable(true)
            end
            if (TacoTipConfig) then
                TacoTipConfig.custom_pos = nil
            end
            print("|cff59f0dcTacoTip:|r " ..
                ((L and L["Custom tooltip position disabled."]) or "Custom tooltip position disabled."))
        elseif (forwardExtrasSlashCommand(cmd)) then
            -- Handed to TacoTip Extras (the server leaderboard). Nothing else
            -- to do here, and the options panel is deliberately NOT opened.
            return
        elseif (TT and TT.OpenOptionsPanel) then
            TT.OpenOptionsPanel()
        else
            print("|cff59f0dcTacoTip:|r Slash commands are loaded.")
            print("|cff59f0dcTacoTip:|r /tacotip custom - show the tooltip mover")
            print("|cff59f0dcTacoTip:|r /tacotip default - clear the custom tooltip position")
        end
    end)
end

registerBootstrapSlash()

-- Re-run locale selection once SavedVariables are readable.
--
-- The per-locale files cannot honour TacoTipConfig.locale_override themselves:
-- addon files execute BEFORE WoW populates SavedVariables, so TacoTipConfig is
-- still an empty table while Locale/*.lua runs and the selection necessarily
-- falls back to GetLocale(). Re-applying here -- after ADDON_LOADED, when the
-- override is actually readable -- is what makes the language dropdown do
-- anything. TacoTipApplyLocale mutates _G.TACOTIP_LOCALE in place, so the
-- `local L` bindings in this file, main.lua and options.lua pick the change up.
if (TacoTipConfig) then
    local localeLoader = CreateFrame("Frame")
    localeLoader:RegisterEvent("ADDON_LOADED")
    localeLoader:SetScript("OnEvent", function(_, _, addonName)
        if (addonName == addOnName and _G.TacoTipApplyLocale) then
            _G.TacoTipApplyLocale()
        end
    end)
end

local function fallbackGUIDIsPlayer(guid)
    return type(guid) == "string" and string.find(guid, "Player-", 1, true) == 1
end

local GUIDIsPlayer = (_G.C_PlayerInfo and _G.C_PlayerInfo.GUIDIsPlayer) or fallbackGUIDIsPlayer
local rawRequestLoadItemDataByID = _G.C_Item and _G.C_Item.RequestLoadItemDataByID
local ITEM_REQUEST_COOLDOWN = 2.0
-- C2 clock probe (load-time): without GetTime there is no monotonic timestamp,
-- so the 2s per-item throttle below is bypassed (fail-OPEN) instead of wedged
-- on a memoised 0. Never memoise 0 as a timestamp.
local clockAvailable = (type(GetTime) == "function")
local function RequestLoadItemDataByID(itemID)
    if (not rawRequestLoadItemDataByID or not itemID) then
        return
    end
    if (not clockAvailable) then
        pcall(rawRequestLoadItemDataByID, itemID)
        return
    end
    local TT_GS = rawget(_G, "TT_GS")
    if (TT_GS) then
        TT_GS._itemRequestTime = TT_GS._itemRequestTime or {}
        local last = TT_GS._itemRequestTime[itemID]
        local now = GetTime()
        if (last and now >= last and (now - last) < ITEM_REQUEST_COOLDOWN) then
            return
        end
        TT_GS._itemRequestTime[itemID] = now
    end
    pcall(rawRequestLoadItemDataByID, itemID)
end
local function GetItemInfo(...)
    if not ... then return nil end
    local fn = (_G.C_Item and _G.C_Item.GetItemInfo) or _G.GetItemInfo
    if fn then
        return fn(...)
    end
end
local floor = math.floor

_G.TT_GS = {}
local TT_GS = _G.TT_GS
TT_GS._itemRequestTime = TT_GS._itemRequestTime or {}
TT_GS.ClockAvailable = clockAvailable

-- Shared homes for the helpers pawn.lua also needs (arbiter #4/#5). Gearscore
-- loads before pawn (toc order), so pawn routes to these at call time via
-- rawget(_G, "TT_GS") -- one implementation, two call sites, no new throttle.
TT_GS.RequestLoadItemDataByID = RequestLoadItemDataByID
TT_GS.IsPlayerGUID = GUIDIsPlayer

-- Cold-path counter home (hunter H6): not-ready GearScore/Pawn reads as
-- absent. Both modules count here; diag surfaces the one number. No
-- loading-row UI change by design (operator-approved minimal option).
function TT_GS:CountPendingHidden()
    TT.ev = TT.ev or {}
    TT.ev.gsPendingHidden = (TT.ev.gsPendingHidden or 0) + 1
end

-- Quality bracket per client family.
--
-- This is purely a mapping: GS_Quality below is keyed off BRACKET_SIZE at load
-- time and scoreFromItemValues passes ItemLevel through raw, so selecting the
-- right bracket restores that client's colour ramp and leaves the iLvl average
-- untouched. No formula change is involved.
--
--   Classic Era / WoW Forever  200   level cap 60, Classic-like item levels
--   TBC Anniversary            400
--   Titanforge / Retail       1000   (Retail: operator hold, see below)
--
-- HOLD (Batch 5, operator decision -- live max ~345): Retail shares the 1000
-- default again. Batches 3/4 calibrated a Retail-only bracket (3000, then
-- 2000) against harness-derived totals, but live Retail totals are
-- unmeasured, and at the live band the reference set totals ~8.7k -- above
-- the 7000 ceiling, so the whole tier reads constant Artifact until a live
-- screenshot justifies a new value. The Retail special-case is removed; raw
-- scores and the iLvl average pass through untouched, so this hold changes
-- no number -- only the colour band a score falls into moves.
--
-- WoW Forever used to fall through to the 1000 default, which inflated every
-- score 5x and collapsed the whole ramp into the "Common" white band. It is
-- called out explicitly rather than left to a default so that an unrecognised
-- client is visible instead of silently inheriting a value.
local BRACKET_SIZE = 1000

if (CI.IsClassic and CI:IsClassic()) then
    BRACKET_SIZE = 200
elseif (CI.IsTBC and CI:IsTBC()) then
    BRACKET_SIZE = 400
elseif (CI.IsForever and CI:IsForever()) then
    BRACKET_SIZE = 200
elseif (CI.IsUnknown and CI:IsUnknown()) then
    -- Unknown family keeps the 1000 default (Titanforge-era behaviour); the
    -- unknown state is already flagged in /tacotip diag, and the harness pins
    -- the default explicitly so a future family fails loudly there instead of
    -- silently inheriting this value. This branch changes nothing: it names
    -- the default that used to be implicit.
    BRACKET_SIZE = 1000
end

local MAX_SCORE = BRACKET_SIZE * 7

TT_GS.BRACKET_SIZE = BRACKET_SIZE
TT_GS.MAX_SCORE = MAX_SCORE

local GS_ItemTypes = {
    ["INVTYPE_RELIC"] = { ["SlotMOD"] = 0.3164, ["ItemSlot"] = 18, ["Enchantable"] = false },
    ["INVTYPE_TRINKET"] = { ["SlotMOD"] = 0.5625, ["ItemSlot"] = 33, ["Enchantable"] = false },
    ["INVTYPE_2HWEAPON"] = { ["SlotMOD"] = 2.000, ["ItemSlot"] = 16, ["Enchantable"] = true },
    ["INVTYPE_WEAPONMAINHAND"] = { ["SlotMOD"] = 1.0000, ["ItemSlot"] = 16, ["Enchantable"] = true },
    ["INVTYPE_WEAPONOFFHAND"] = { ["SlotMOD"] = 1.0000, ["ItemSlot"] = 17, ["Enchantable"] = true },
    ["INVTYPE_RANGED"] = { ["SlotMOD"] = 0.3164, ["ItemSlot"] = 18, ["Enchantable"] = true },
    ["INVTYPE_THROWN"] = { ["SlotMOD"] = 0.3164, ["ItemSlot"] = 18, ["Enchantable"] = false },
    ["INVTYPE_RANGEDRIGHT"] = { ["SlotMOD"] = 0.3164, ["ItemSlot"] = 18, ["Enchantable"] = false },
    ["INVTYPE_SHIELD"] = { ["SlotMOD"] = 1.0000, ["ItemSlot"] = 17, ["Enchantable"] = true },
    ["INVTYPE_WEAPON"] = { ["SlotMOD"] = 1.0000, ["ItemSlot"] = 36, ["Enchantable"] = true },
    ["INVTYPE_HOLDABLE"] = { ["SlotMOD"] = 1.0000, ["ItemSlot"] = 17, ["Enchantable"] = false },
    ["INVTYPE_HEAD"] = { ["SlotMOD"] = 1.0000, ["ItemSlot"] = 1, ["Enchantable"] = true },
    ["INVTYPE_NECK"] = { ["SlotMOD"] = 0.5625, ["ItemSlot"] = 2, ["Enchantable"] = false },
    ["INVTYPE_SHOULDER"] = { ["SlotMOD"] = 0.7500, ["ItemSlot"] = 3, ["Enchantable"] = true },
    ["INVTYPE_CHEST"] = { ["SlotMOD"] = 1.0000, ["ItemSlot"] = 5, ["Enchantable"] = true },
    ["INVTYPE_ROBE"] = { ["SlotMOD"] = 1.0000, ["ItemSlot"] = 5, ["Enchantable"] = true },
    ["INVTYPE_WAIST"] = { ["SlotMOD"] = 0.7500, ["ItemSlot"] = 6, ["Enchantable"] = false },
    ["INVTYPE_LEGS"] = { ["SlotMOD"] = 1.0000, ["ItemSlot"] = 7, ["Enchantable"] = true },
    ["INVTYPE_FEET"] = { ["SlotMOD"] = 0.75, ["ItemSlot"] = 8, ["Enchantable"] = true },
    ["INVTYPE_WRIST"] = { ["SlotMOD"] = 0.5625, ["ItemSlot"] = 9, ["Enchantable"] = true },
    ["INVTYPE_HAND"] = { ["SlotMOD"] = 0.7500, ["ItemSlot"] = 10, ["Enchantable"] = true },
    ["INVTYPE_FINGER"] = { ["SlotMOD"] = 0.5625, ["ItemSlot"] = 31, ["Enchantable"] = false },
    ["INVTYPE_CLOAK"] = { ["SlotMOD"] = 0.5625, ["ItemSlot"] = 15, ["Enchantable"] = true },
    ["INVTYPE_BODY"] = { ["SlotMOD"] = 0, ["ItemSlot"] = 4, ["Enchantable"] = false },
}

local GS_Formula = {
    ["A"] = {
        [4] = { ["A"] = 91.4500, ["B"] = 0.6500 },
        [3] = { ["A"] = 81.3750, ["B"] = 0.8125 },
        [2] = { ["A"] = 73.0000, ["B"] = 1.0000 }
    },
    ["B"] = {
        [4] = { ["A"] = 26.0000, ["B"] = 1.2000 },
        [3] = { ["A"] = 0.7500, ["B"] = 1.8000 },
        [2] = { ["A"] = 8.0000, ["B"] = 2.0000 },
        [1] = { ["A"] = 0.0000, ["B"] = 2.2500 }
    },
    ["C"] = {
        [4] = { ["A"] = 0.2500, ["B"] = 1.6275 }
    },
}

local GS_Quality = {
    [BRACKET_SIZE]     = { r = 0.50, g = 0.50, b = 0.50, label = "Trash" },
    [BRACKET_SIZE * 2] = { r = 1.00, g = 1.00, b = 1.00, label = "Common" },
    [BRACKET_SIZE * 3] = { r = 0.12, g = 0.81, b = 0.04, label = "Uncommon" },
    [BRACKET_SIZE * 4] = { r = 0.12, g = 0.40, b = 0.83, label = "Superior" },
    [BRACKET_SIZE * 5] = { r = 0.63, g = 0.20, b = 0.83, label = "Epic" },
    [BRACKET_SIZE * 6] = { r = 1.00, g = 0.63, b = 0.00, label = "Legendary" },
    [BRACKET_SIZE * 7] = { r = 0.92, g = 0.10, b = 0.10, label = "Artifact" },
}

local function getPlayerGUID(arg)
    if (arg) then
        if (GUIDIsPlayer(arg)) then
            return arg
        elseif (UnitIsPlayer(arg)) then
            return UnitGUID(arg)
        end
    end
    return nil
end

TT_GS.ResolvePlayerGUID = getPlayerGUID

function TT_GS:GetQuality(ItemScore)
    ItemScore = tonumber(ItemScore)
    if (not ItemScore) then
        return 0.5, 0.5, 0.5, "Trash"
    end
    if (ItemScore > MAX_SCORE) then
        ItemScore = MAX_SCORE
    end
    for i = 0, 6 do
        if ((ItemScore > i * BRACKET_SIZE) and (ItemScore <= ((i + 1) * BRACKET_SIZE))) then
            local qColors = GS_Quality[(i + 1) * BRACKET_SIZE]
            return qColors.r, qColors.g, qColors.b, qColors.label
        end
    end
    return 0.5, 0.5, 0.5, "Trash"
end

-- Item colour band scale.
--
-- The colour of an ITEM tooltip must be a pure function of the number printed
-- beside it. It used not to be: the band was computed from the slot-mod-FREE
-- base -- the hardcoded `* 1` stood in for SlotMOD -- while the score shown to
-- the user multiplied that base by GS_ItemTypes[].SlotMOD. A 2H and a head of
-- identical item level therefore shared a colour while displaying different
-- scores, so the band never described the number next to it. Upstream GearScore
-- 3.1.20 decouples them the same way with 12.25; the constant change to 11.25
-- is ours, and the decoupling was carried over with it.
--
-- The ~11x rescale is kept deliberately. Applied to the raw score, a trinket at
-- a current item level would read as "Trash" -- the bands are sized for a
-- character total, and per-item scores are a different, smaller domain. Same
-- reason the character TOTAL in main.lua is passed to GetQuality unrescaled:
-- totals and items are separate domains and are NOT unified.
local ITEM_BAND_SCALE = 11.25

-- Resolves the raw item data GearScore needs from a pre-fetched GetItemInfo
-- result table. Callers that already hold the info (e.g. tooltip hooks) MUST
-- prefer TT_GS:GetItemScoreFromInfo so one hover performs exactly one
-- GetItemInfo call instead of one per scoring consumer.
-- @param info result of GetItemInfo(itemLink) (may be nil while uncached)
local function scoreFromItemValues(itemLinkOut, ItemRarity, ItemLevel, ItemEquipLoc, itemLinkFallback)
    if (not itemLinkOut and itemLinkFallback and RequestLoadItemDataByID) then
        local itemID = tonumber(string.match(itemLinkFallback, "item:(%d+)"))
        if (itemID) then
            pcall(RequestLoadItemDataByID, itemID)
        end
    end
    if (itemLinkOut and ItemRarity and ItemLevel and ItemEquipLoc and GS_ItemTypes[ItemEquipLoc]) then
        local Table
        local QualityScale = 1
        local GearScore
        local Scale = 1.8618
        if (ItemRarity == 5) then
            QualityScale = 1.3
            ItemRarity = 4
        elseif (ItemRarity == 1) then
            QualityScale = 0.005
            ItemRarity = 2
        elseif (ItemRarity == 0) then
            QualityScale = 0.005
            ItemRarity = 2
        elseif (ItemRarity == 7) then
            ItemRarity = 3
            ItemLevel = 187.05
        end
        if (ItemLevel < 100 and ItemRarity == 4) then
            Table = GS_Formula["C"]
        elseif (ItemLevel < 168 and ItemRarity == 4) then
            Table = GS_Formula["B"]
        elseif (ItemLevel < 148 and ItemRarity == 3) then
            Table = GS_Formula["B"]
        elseif (ItemLevel < 138 and ItemRarity == 2) then
            Table = GS_Formula["B"]
        elseif (ItemLevel <= 120) then
            Table = GS_Formula["B"]
        else
            Table = GS_Formula["A"]
        end
        if ((ItemRarity >= 2) and (ItemRarity <= 4)) then
            GearScore = floor(((ItemLevel - Table[ItemRarity].A) / Table[ItemRarity].B) *
                GS_ItemTypes[ItemEquipLoc].SlotMOD * Scale * QualityScale)
            -- Band from the score actually displayed, so the two can never
            -- disagree. Order matters: the clamp below rewrites GearScore, and
            -- the band is taken from the clamped value.
            local Red, Green, Blue = TT_GS:GetQuality(GearScore * ITEM_BAND_SCALE)
            if (ItemLevel == 187.05) then
                ItemLevel = 0
            end
            if (GearScore < 0) then
                GearScore = 0
                Red, Green, Blue = TT_GS:GetQuality(1)
            end
            return GearScore, ItemLevel, Red, Green, Blue, ItemEquipLoc
        end
    end
    return 0, 0, 0.1, 0.1, 0.1, 0
end

-- Resolves the raw item data GearScore needs from a pre-fetched GetItemInfo
-- result table. Callers that already hold the info (e.g. tooltip hooks) MUST
-- prefer TT_GS:GetItemScoreFromInfo so one hover performs exactly one
-- GetItemInfo call instead of one per scoring consumer.
-- @param info result of GetItemInfo(itemLink) (may be nil while uncached)
-- @return number gearScore, number itemLevel, number r, number g, number b, string|nil equipLoc
local function scoreFromItemInfo(info, itemLinkFallback)
    if (not info or type(info) ~= "table") then
        if (itemLinkFallback and RequestLoadItemDataByID) then
            local itemID = tonumber(string.match(itemLinkFallback, "item:(%d+)"))
            if (itemID) then
                pcall(RequestLoadItemDataByID, itemID)
            end
        end
        return 0, 0, 0.1, 0.1, 0.1, 0
    end
    return scoreFromItemValues(info[2], info[3], info[4], info[9], itemLinkFallback)
end

-- Public entry: score from a caller-provided GetItemInfo result table.
-- Performs no GetItemInfo call of its own; see scoreFromItemInfo.
function TT_GS:GetItemScoreFromInfo(info)
    return scoreFromItemInfo(info)
end

-- Public entry: score directly from an item link. Retained for callers
-- (frame overlays, tests) that do not already hold a GetItemInfo result.
function TT_GS:GetItemScore(ItemLink)
    if not (ItemLink) then
        return 0, 0, 0.1, 0.1, 0.1
    end
    local _, itemLinkOut, itemRarity, itemLevel, _, _, _, _, itemEquipLoc = GetItemInfo(ItemLink)
    return scoreFromItemValues(itemLinkOut, itemRarity, itemLevel, itemEquipLoc, ItemLink)
end

-- Hunter-adjusted score. Accepts an optional pre-fetched GetItemInfo table
-- so item-tooltip callers reuse one fetch across ilvl/GearScore/HunterScore.
function TT_GS:GetItemHunterScore(ItemLink, info)
    -- NOTE: no `info and A(...) or B(...)` shortcut here — and/or yields a
    -- single value, which would leave every score field after GearScore nil.
    local GearScore, ItemLevel, Red, Green, Blue, ItemEquipLoc
    if (info) then
        GearScore, ItemLevel, Red, Green, Blue, ItemEquipLoc = TT_GS:GetItemScoreFromInfo(info)
    else
        GearScore, ItemLevel, Red, Green, Blue, ItemEquipLoc = TT_GS:GetItemScore(ItemLink)
    end
    if (not GearScore or GearScore == 0) then
        return 0, ItemLevel or 0, Red or 0.1, Green or 0.1, Blue or 0.1, ItemEquipLoc
    end
    if ((ItemEquipLoc == "INVTYPE_2HWEAPON") or (ItemEquipLoc == "INVTYPE_WEAPONMAINHAND") or (ItemEquipLoc == "INVTYPE_WEAPONOFFHAND") or (ItemEquipLoc == "INVTYPE_WEAPON") or (ItemEquipLoc == "INVTYPE_HOLDABLE")) then
        GearScore = floor(GearScore * 0.3164)
    elseif ((ItemEquipLoc == "INVTYPE_RANGEDRIGHT") or (ItemEquipLoc == "INVTYPE_RANGED") or (ItemEquipLoc == "INVTYPE_THROWN")) then
        GearScore = floor(GearScore * 5.3224)
    end
    return GearScore, ItemLevel, Red, Green, Blue, ItemEquipLoc
end

local function itemcacheCB(tbl, id)
    if (not tbl or not tbl.items or tbl.completed) then
        return
    end
    -- Iterate backward: table.remove shifts later elements left, so a
    -- forward sweep would skip the element right after a removed match.
    for i = #tbl.items, 1, -1 do
        if (id == tbl.items[i]) then
            table.remove(tbl.items, i)
        end
    end
    -- Latch so a duplicate-slot registration for an already-drained list
    -- cannot fire TacoTip_GSCallback twice (two identical rings = two
    -- ContinueOnItemLoad closures for one pending id).
    if (#tbl.items == 0 and not tbl.completed) then
        tbl.completed = true
        if (TacoTip_GSCallback) then
            TacoTip_GSCallback(tbl.guid)
        end
    end
end

TT_GS.DrainItemCache = itemcacheCB


function TT_GS:GetScore(unitorguid, useCallback)
    local guid = getPlayerGUID(unitorguid)
    if (guid) then
        if (guid ~= UnitGUID("player")) then
            local _, invTime = CI:GetLastCacheTime(guid)
            if (invTime == 0) then
                return 0, 0
            end
        end

        local ppOk, _, PlayerEnglishClass = pcall(GetPlayerInfoByGUID, guid)
        if (not ppOk) then
            PlayerEnglishClass = ""
        end
        local GearScore = 0
        local ItemCount = 0
        local LevelTotal = 0
        local TitanGrip = 1
        local IsReady = true

        local mainHandItem = CI:GetInventoryItemMixin(guid, 16)
        local offHandItem = CI:GetInventoryItemMixin(guid, 17)
        local mainHandLink
        local offHandLink

        local cb_table

        if (useCallback) then
            cb_table = { ["guid"] = guid, ["items"] = {} }
        end

        if (mainHandItem) then
            if (mainHandItem:IsItemDataCached()) then
                mainHandLink = mainHandItem:GetItemLink()
            else
                IsReady = false
                local itemID = mainHandItem:GetItemID()
                if (itemID) then
                    if (useCallback) then
                        -- Dedupe on insert: identical item ids (e.g. two
                        -- identical rings) must not occupy two list slots,
                        -- or the first callback drains both matches and the
                        -- second slot's callback completes on a drained list.
                        local alreadyPending = false
                        for _, pendingID in ipairs(cb_table.items) do
                            if (pendingID == itemID) then
                                alreadyPending = true
                                break
                            end
                        end
                        if (not alreadyPending) then
                            table.insert(cb_table.items, itemID)
                        end
                        mainHandItem:ContinueOnItemLoad(function()
                            itemcacheCB(cb_table, itemID)
                        end)
                    elseif (RequestLoadItemDataByID) then
                        RequestLoadItemDataByID(itemID)
                    end
                end
            end
        end
        if (offHandItem) then
            if (offHandItem:IsItemDataCached()) then
                offHandLink = offHandItem:GetItemLink()
            else
                IsReady = false
                local itemID = offHandItem:GetItemID()
                if (itemID) then
                    if (useCallback) then
                        -- Same dedupe rule as the main-hand registration.
                        local alreadyPending = false
                        for _, pendingID in ipairs(cb_table.items) do
                            if (pendingID == itemID) then
                                alreadyPending = true
                                break
                            end
                        end
                        if (not alreadyPending) then
                            table.insert(cb_table.items, itemID)
                        end
                        offHandItem:ContinueOnItemLoad(function()
                            itemcacheCB(cb_table, itemID)
                        end)
                    elseif (RequestLoadItemDataByID) then
                        RequestLoadItemDataByID(itemID)
                    end
                end
            end
        end

        -- Titan Grip: In WotLK, Fury Warriors can dual-wield 2-handed weapons.
        -- When an offhand item is equipped alongside a 2H weapon (or both are 2H),
        -- each 2H weapon is scaled by 0.5 (reducing SlotMOD from 2.0 to 1.0) so
        -- dual-wielding 2H weapons balances with 1H dual wielders (1.0 + 1.0 = 2.0).
        -- Standalone 2H weapons (no offhand equipped) retain full 2.0x weight.
        local OffHandTitanGrip = 1
        if (mainHandLink and offHandLink) then
            local mhEquipLoc = select(9, GetItemInfo(mainHandLink))
            local ohEquipLoc = select(9, GetItemInfo(offHandLink))
            if (mhEquipLoc == "INVTYPE_2HWEAPON") then
                TitanGrip = 0.5
            end
            if (ohEquipLoc == "INVTYPE_2HWEAPON") then
                OffHandTitanGrip = 0.5
            end
        end

        if (offHandLink) then
            local TempScore, ItemLevel = TT_GS:GetItemScore(offHandLink)
            if (PlayerEnglishClass == "HUNTER") then
                TempScore = TempScore * 0.3164
            end
            GearScore = GearScore + TempScore * OffHandTitanGrip
            ItemCount = ItemCount + 1
            LevelTotal = LevelTotal + ItemLevel
        end

        for i = 1, 18 do
            if (i ~= 4) and (i ~= 17) then
                local item = CI:GetInventoryItemMixin(guid, i)
                if (item) then
                    if (item:IsItemDataCached()) then
                        local TempScore, ItemLevel = TT_GS:GetItemScore(item:GetItemLink())
                        if (PlayerEnglishClass == "HUNTER") then
                            if (i == 16) then
                                TempScore = TempScore * 0.3164
                            elseif (i == 18) then
                                TempScore = TempScore * 5.3224
                            end
                        end
                        if (i == 16) then
                            TempScore = TempScore * TitanGrip
                        end
                        GearScore = GearScore + TempScore
                        ItemCount = ItemCount + 1
                        LevelTotal = LevelTotal + ItemLevel
                    else
                        IsReady = false
                        local itemID = item:GetItemID()
                        if (itemID) then
                            if (useCallback) then
                                -- Same dedupe rule as the weapon-slot
                                -- registrations above.
                                local alreadyPending = false
                                for _, pendingID in ipairs(cb_table.items) do
                                    if (pendingID == itemID) then
                                        alreadyPending = true
                                        break
                                    end
                                end
                                if (not alreadyPending) then
                                    table.insert(cb_table.items, itemID)
                                end
                                item:ContinueOnItemLoad(function()
                                    itemcacheCB(cb_table, itemID)
                                end)
                            elseif (RequestLoadItemDataByID) then
                                RequestLoadItemDataByID(itemID)
                            end
                        end
                    end
                end
            end
        end
        if (IsReady and GearScore > 0 and ItemCount > 0) then
            return floor(GearScore), floor(LevelTotal / ItemCount)
        end
        -- Cold path only (hunter H6): the score is not ready -- items are still
        -- streaming or throttled -- so the tooltip reads this as absent. Count
        -- it (diag-surfaced) rather than adding a loading-row UI change.
        if (not IsReady) then
            TT_GS:CountPendingHidden()
        end
    end
    return 0, 0
end
