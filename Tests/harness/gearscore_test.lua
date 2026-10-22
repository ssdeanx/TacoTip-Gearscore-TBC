-- Drives the REAL gearscore.lua against a mocked inventory and asserts the
-- NUMBERS it produces.
--
-- Usage: lua5.1 gearscore_test.lua <projectId> <iface> <label> <family>
--
-- WHY THIS FILE EXISTS. Every GearScore assertion in the addon until now was a
-- "does not throw": tacoTip_Forever_Tests calls GetScore(nil) and checks only
-- that it returns, and tooltip_test io.write's the number it never checks. Both
-- bugs this file covers shipped green through that:
--
--   * TitanGrip was structurally unreachable. A 2H occupies BOTH slot 16 and
--     slot 17, so `mainHandLink and offHandLink` could only be true for a
--     main/off pair, and a 2H main hand is never in an offhand. TitanGrip was
--     therefore provably always 1.0 and every 2H overcounted by its full score
--     (measured: +311 GS on a TBC-bracket ilvl-200 2H). Reading the guard is
--     not enough -- it looks like a reasonable sanity check. Only enumerating
--     the reachable inventory states shows the assignment is dead.
--   * The item colour band was computed from the slot-mod-FREE base while the
--     displayed score included SlotMOD, so the colour never described the
--     number printed beside it.
--
-- Every expectation below is a hand-derived literal, NOT a re-run of the
-- production formula. Deriving them from the code under test would make these
-- assertions unable to fail for the reason they exist -- the exact defect this
-- suite has shipped repeatedly.

local _hp = ((arg and arg[0]) or "Tests/harness/gearscore_test.lua"):gsub("\\", "/")
local _hd = _hp:match("^(.*)/[^/]*$") or "."
local ROOT = dofile(_hd .. "/root.lua") .. "/"

local projectId, iface, label = tonumber(arg[1]), tonumber(arg[2]), arg[3]
local family = arg[4] or "tbc"

-- gearscore.lua picks its bracket from the client family, and BRACKET_SIZE only
-- feeds the colour bands -- per-item scores are bracket-independent, which the
-- same expected literals on every client prove.
local EXPECTED_BRACKET = {
    classicEra = 200, tbc = 400, titanforge = 1000, forever = 200, retail = 1000,
    -- M10: an unrecognised family keeps the 1000 default. Pinned by its own
    -- run (see run_all.sh) so a future change to the unknown default fails
    -- loudly in-harness instead of silently re-bracketing.
    unknown = 1000,
}

-- NOTE: unlike the other harnesses this one never touches the real _G. It
-- builds a private env table and runs gearscore.lua inside it, so the harness's
-- own globals survive and nothing here can be perturbed by -- or perturb -- a
-- chunk that loads another addon file. See sandboxedChunk below.

-- `unpack` is a global in Lua 5.1 (what WoW ships) and `table.unpack` from 5.2.
-- Resolved before the sandbox table so both interpreters get a real callable.
local unpack = unpack or table.unpack

local STD = {
    os = os, string = string, pairs = pairs, ipairs = ipairs, type = type,
    pcall = pcall, tonumber = tonumber, tostring = tostring, select = select,
    rawget = rawget, rawset = rawset, setmetatable = setmetatable,
    getmetatable = getmetatable, unpack = unpack, assert = assert, error = error,
    math = math, table = table, loadfile = loadfile, print = print, io = io,
}

local checks = {}
local function check(name, cond, detail)
    checks[#checks + 1] = { name, cond and true or false, detail }
end

-- ---- mocked inventory -------------------------------------------------------

local SELF_GUID = "Player-1-000000AA"
local OTHER_GUID = "Player-1-000000BB"

-- Counts raw per-ID item-data requests so the 2.0s throttle (section 7) is
-- observable. The module captures the raw function at load, so the counter
-- has to live in the mock itself, not in a post-load wrapper.
local rawItemRequests = 0

local ITEMS = {}   -- link -> GetItemInfo result table
local INV = {}     -- slot -> link

local nextID = 50000
local function defItem(rarity, ilvl, equipLoc)
    nextID = nextID + 1
    local link = "|cffffffff|Hitem:" .. nextID .. "|h[TacoTip Test Item]|h|r"
    ITEMS[link] = {
        name = "TacoTip Test Item", link = link, rarity = rarity, ilvl = ilvl,
        equipLoc = equipLoc,
    }
    return link
end

-- Returns the 11 values the real (legacy-shaped) GetItemInfo returns, exactly
-- as tooltip_test.lua and settings_test.lua mock it, and is aliased onto
-- C_Item.GetItemInfo the same way. The module resolves
-- `(_G.C_Item and _G.C_Item.GetItemInfo) or _G.GetItemInfo` and destructures
-- MULTIPLE returns inside TT_GS:GetItemScore, so a mock returning a single
-- table silently scores every item 0 -- that would be a mock bug reading as a
-- product bug, so it is called out here.
local function itemInfo(link)
    local it = ITEMS[link]
    if (not it) then return nil end
    return it.name, it.link, it.rarity, it.ilvl, 1, "Armor", "Cloth", 1,
        it.equipLoc, "Interface\\Icons\\INV_Misc_Spyglass_01", 0
end

-- The table shape scoreFromItemInfo indexes: what main.lua builds with
-- `{ getItemInfoFn(itemLink) }`.
local function infoFor(link)
    return { itemInfo(link) }
end

-- ---- sandbox ----------------------------------------------------------------

local CACHE_TIME = 1234567

-- Chat output of the sandboxed add-on, captured so the slash-command pins
-- below can assert WHICH branch the handler took (the fallback prints the
-- help block; the mover branches print their own line).
local printed = {}

local function buildEnv()
    local env = {}
    env._G = env
    for k, v in STD.pairs(STD) do env[k] = v end

    -- GetTime, not time(): the library stamps cache entries with uptime
    -- seconds (verified on all five clients), and this harness previously
    -- supplied only `time`, so the real timestamp path was never exercised.
    env.GetTime = function() return CACHE_TIME end
    env.time = STD.os.time
    env.strlower = STD.string.lower
    env.print = function(...)
        printed[#printed + 1] = STD.table.concat({ ... }, " ")
    end
    env.CreateFrame = function()
    -- `securecall` -- the engine's taint-containment global, present on every
    -- supported client (Blizzard captures it as a local the same way it captures
    -- `forceinsecure`: Blizzard_FrameXML/SharedPetBattleTemplates.lua:5
    -- `local securecall = securecall;`). The mock counts the calls that went
    -- through it, so a taint pin can tell "addon code ran inside a Blizzard
    -- frame's script chain" from "it ran contained".
    env.securecall = function(fn, ...)
        env.__secureCalls = (env.__secureCalls or 0) + 1
        return fn(...)
    end
        return { RegisterEvent = function() end, SetScript = function() end }
    end
    env.GetBuildInfo = function()
        return "1.15.9", "69722", "date", iface, "us", "release"
    end
    env.WOW_PROJECT_MAINLINE = 1
    env.WOW_PROJECT_CLASSIC = 2
    env.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
    env.WOW_PROJECT_WRATH_CLASSIC = 11
    env.WOW_PROJECT_ID = projectId

    env.C_PlayerInfo = {
        GUIDIsPlayer = function(g)
            return type(g) == "string" and string.find(g, "Player-", 1, true) == 1
        end,
    }
    env.GetItemInfo = itemInfo
    env.C_Item = {
        GetItemInfo = itemInfo,
        RequestLoadItemDataByID = function()
            rawItemRequests = rawItemRequests + 1
        end,
    }
    env.UnitIsPlayer = function(u) return u == SELF_GUID or u == OTHER_GUID end
    env.UnitGUID = function(u) if u == "player" then return SELF_GUID end return nil end
    env.GetPlayerInfoByGUID = function() return true, "Tester", "WARRIOR" end

    -- LibStub / LibForeverInspector mocks. GetLastCacheTime MUST be non-zero or
    -- GetScore returns 0,0 for anyone but the player -- a mock returning 0
    -- here would make every score assertion below vacuously pass on 0.
    local CI = {}
    local isClassic = (family == "classicEra")
    local isTBC = (family == "tbc")
    local isWotlk = (family == "titanforge")
    local isForever = (family == "forever")
    function CI:IsClassic() return isClassic end
    function CI:IsTBC() return isTBC end
    function CI:IsWotlk() return isWotlk end
    function CI:IsForever() return isForever end
    function CI:IsRetail() return (family == "retail") end
    function CI:IsUnknown() return (family == "unknown") end
    function CI:GetLastCacheTime() return CACHE_TIME, CACHE_TIME end
    -- NOTE the signature: `self` is IMPLICIT in a colon definition. Writing an
    -- extra `_` parameter for it shifts every real argument one place left --
    -- `guid` then receives the SLOT and `slot` is always nil, so the guard below
    -- returns nil for every call and GetScore silently scores 0 for every item.
    -- That is what made all eight value assertions report "got 0" while the
    -- per-item assertions (which bypass this mock) passed. Prove it if you
    -- touch it: `lua5.1 -e 'local t={} function t:m(a,b) print(a,b) end t:m(1,2)'`
    -- prints `1  2`, not `table: 0x..  1`.
    function CI:GetInventoryItemMixin(unitorguid, slot)
        if (not slot) then return nil end
        local link = INV[slot]
        if (not link) then return nil end
        return {
            IsItemDataCached = function() return true end,
            GetItemLink = function() return link end,
            GetItemID = function() return tonumber(string.match(link, "item:(%d+)")) end,
            ContinueOnItemLoad = function() end,
        }
    end

    local libs = {
        ["LibForeverInspector"] = CI,
        ["LibDetours-1.0"] = { Hook = function() end },
    }
    local stub = setmetatable({}, {
        __call = function(_, name, silent)
            local lib = libs[name]
            if (not lib and not silent) then
                error("Cannot find a library instance of " .. tostring(name) .. ".", 2)
            end
            return lib
        end,
    })
    function stub:GetLibrary(name, silent) return self(name, silent) end
    function stub:NewLibrary(name) libs[name] = libs[name] or {}; return libs[name], 1 end
    function stub:IterateLibraries()
        local n = 0
        for _ in STD.pairs(libs) do n = n + 1 end
        return n
    end
    env.LibStub = stub

    return env
end

-- setfenv is the 5.1/LuaJIT route and both it and loadstring were removed in
-- 5.2, where load(src, name, "t", env) takes the env directly. The source is
-- read rather than loadfile'd only because the env must be attached to the
-- chunk before it runs -- the equivalent of what load_test.lua does with
-- loadfile + a plain call, except that here the real _G is left untouched.
local function sandboxedChunk(path, env)
    local fh = assert(io.open(path, "rb"), "cannot open " .. path)
    local src = fh:read("*a")
    fh:close()
    if (STD.setfenv and STD.loadstring) then
        local chunk = assert(STD.loadstring(src, "@" .. path))
        STD.setfenv(chunk, env)
        return chunk
    end
    return assert(STD.load(src, "@" .. path, "t", env))
end

STD.setfenv = setfenv
STD.loadstring = loadstring
STD.load = load

local env = buildEnv()
local ok, err = pcall(sandboxedChunk(ROOT .. "gearscore.lua", env), "TacoTip_Forever")
if (not ok) then
    STD.io.write("GEARSCORE LOAD FAIL  " .. tostring(err) .. "\n")
    STD.os.exit(1)
end

local GS = env.TT_GS
local floor = math.floor
local ITEM_BAND_SCALE = 11.25  -- the named constant in gearscore.lua

check("gearscore.lua loaded and published TT_GS", GS ~= nil)
if (not GS) then
    STD.io.write("*** FAILURES ***\n")
    STD.os.exit(1)
end

local bracket = GS.BRACKET_SIZE
check("bracket for " .. label .. " = " .. tostring(EXPECTED_BRACKET[family]),
    bracket == EXPECTED_BRACKET[family], "got " .. tostring(bracket))

local function scoreOf(link)
    return GS:GetItemScore(link)
end

local function totalOf(who)
    return GS:GetScore(who or SELF_GUID, false)
end

-- ============================================================================
-- 1. Titan Grip. Hand-derived per-item scores for ilvl 200, rarity 4:
--
--      base = (200 - 91.45) / 0.65 = 167      (GS_Formula.A, rarity 4)
--      Scale = 1.8618, QualityScale = 1
--      SlotMOD 1.0000 -> 167 * 1.8618              = 310.9206 -> 310
--      SlotMOD 0.7500 -> 167 * 0.75   * 1.8618     = 233.1904 -> 233
--      SlotMOD 0.5625 -> 167 * 0.5625 * 1.8618     = 174.8928 -> 174
--      SlotMOD 0.3164 -> 167 * 0.3164 * 1.8618     =  98.3752 ->  98
--      SlotMOD 2.0000 -> 167 * 2.0    * 1.8618     = 621.8412 -> 621  (2H)
-- ============================================================================

local HEAD = defItem(4, 200, "INVTYPE_HEAD")
local LEGS = defItem(4, 200, "INVTYPE_LEGS")
local TWOH = defItem(4, 200, "INVTYPE_2HWEAPON")

check("ilvl 200 rare head scores 310", scoreOf(HEAD) == 310, "got " .. tostring(scoreOf(HEAD)))
check("ilvl 200 rare legs scores 310", scoreOf(LEGS) == 310, "got " .. tostring(scoreOf(LEGS)))
check("ilvl 200 rare 2H scores 621", scoreOf(TWOH) == 621, "got " .. tostring(scoreOf(TWOH)))

-- 2H-only character, TBC bracket: head + legs + full 2H (621) = 1241.
-- A standalone 2H weapon occupies slot 16 with slot 17 empty and must count at
-- full weight (SlotMOD 2.000) so weapon budget matches 1H + shield (310 + 310).
INV = { [1] = HEAD, [7] = LEGS, [16] = TWOH }
local twohTotal = totalOf()
check("2H character scores 1241 (head+legs+621)", twohTotal == 1241,
    "got " .. tostring(twohTotal) .. " (expected 1241)")

INV = { [1] = HEAD, [7] = LEGS }
local bareTotal = totalOf()
check("same character without the weapon scores 620", bareTotal == 620,
    "got " .. tostring(bareTotal))

check("2H contributes full 621 points",
    twohTotal == bareTotal + 621,
    "delta " .. tostring(twohTotal - bareTotal))

-- Titan's Grip dual-wield: 2H main hand AND 2H off hand.
-- Each 2H weapon receives 0.5 TitanGrip scaling: 310.5 + 310.5 = 621 weapon points.
local TWOH_OFF = defItem(4, 200, "INVTYPE_2HWEAPON")
INV = { [1] = HEAD, [7] = LEGS, [16] = TWOH, [17] = TWOH_OFF }
local tgTotal = totalOf()
check("Titan's Grip dual 2H character scores 1241 (head+legs+(621*0.5)*2)", tgTotal == 1241,
    "got " .. tostring(tgTotal) .. " (expected 1241)")

local ONEH = defItem(4, 200, "INVTYPE_WEAPONMAINHAND")
local OFFH = defItem(4, 200, "INVTYPE_WEAPONOFFHAND")
local SHIELD = defItem(4, 200, "INVTYPE_SHIELD")

local OFFHAND_STATES = {
    { name = "no offhand", link = nil, contrib = 0 },
    { name = "1H offhand", link = OFFH, contrib = 310 },
    { name = "shield", link = SHIELD, contrib = 310 },
}

-- main hand x the offhand states that are legal alongside it.
local WEAPON_STATES = {
    { name = "no weapon", main = nil, contrib = 0, offs = OFFHAND_STATES },
    { name = "1H main hand", main = ONEH, contrib = 310, offs = OFFHAND_STATES },
    { name = "2H main hand (solo)", main = TWOH, contrib = 621,
      offs = { { name = "no offhand", link = nil, contrib = 0 } } },
    { name = "2H main hand (Titan's Grip 2H)", main = TWOH, contrib = 621 * 0.5,
      offs = { { name = "2H offhand", link = TWOH_OFF, contrib = 621 * 0.5 } } },
    { name = "2H main hand (Titan's Grip 1H)", main = TWOH, contrib = floor(621 * 0.5),
      offs = { { name = "1H offhand", link = OFFH, contrib = 310 } } },
}

local matrixBad, matrixTried = nil, 0
for _, m in STD.ipairs(WEAPON_STATES) do
    for _, o in STD.ipairs(m.offs) do
        local inv = { [1] = HEAD, [7] = LEGS }
        if (m.main) then inv[16] = m.main end
        if (o.link) then inv[17] = o.link end
        INV = inv
        local got = totalOf()
        local want = floor(620 + m.contrib + o.contrib)
        matrixTried = matrixTried + 1
        if (got ~= want) then
            matrixBad = matrixBad or string.format("%s + %s: got %s want %d", m.name, o.name,
                tostring(got), want)
        end
    end
end
check("all " .. matrixTried .. " reachable weapon states score correctly",
    matrixBad == nil, matrixBad or "")

-- ============================================================================
-- 2. Item colour band must be a pure function of the score actually printed.
--
--    band input = score * 11.25, bucketed by GetQuality as
--    (i*BRACKET, (i+1)*BRACKET] and clamped above MAX_SCORE = 7*BRACKET.
--    The literals below are derived from the hand-computed scores:
--      head    310 * 11.25 = 3487.5
--      ranged   98 * 11.25 = 1102.5
--      trinket 174 * 11.25 = 1957.5
--      2H      621 * 11.25 = 6986.25
-- ============================================================================

local HEAD_ILVL200_LABEL    = { [200] = "Artifact", [400] = "Artifact", [1000] = "Superior" }
local RANGED_ILVL200_LABEL  = { [200] = "Legendary", [400] = "Uncommon", [1000] = "Common" }
local TRINKET_ILVL200_LABEL = { [200] = "Artifact", [400] = "Epic",     [1000] = "Common" }
local TWOH_ILVL200_LABEL    = { [200] = "Artifact", [400] = "Artifact", [1000] = "Artifact" }

local RANGED = defItem(4, 200, "INVTYPE_RANGED")
local TRINKET = defItem(4, 200, "INVTYPE_TRINKET")
local NECK = defItem(4, 200, "INVTYPE_NECK")
local FEET = defItem(4, 200, "INVTYPE_FEET")

-- Broad sweep: every slot at several item levels and rarities, including the
-- ones that land on a clamp. The invariant is checked against the score the
-- module returned, so it holds on all three brackets by construction.
local bandCases = {
    { link = HEAD,    slot = "head" },
    { link = TWOH,    slot = "2H" },
    { link = RANGED,  slot = "ranged" },
    { link = TRINKET, slot = "trinket" },
    { link = NECK,    slot = "neck" },
    { link = FEET,    slot = "feet" },
    { link = defItem(4, 115, "INVTYPE_HEAD"),   slot = "ilvl115 head" },
    { link = defItem(4, 115, "INVTYPE_RANGED"), slot = "ilvl115 ranged" },
    { link = defItem(3, 100, "INVTYPE_TRINKET"), slot = "ilvl100 uncomm trinket" },
    { link = defItem(2, 80,  "INVTYPE_FINGER"),  slot = "ilvl80 comm finger" },
    { link = defItem(4, 187, "INVTYPE_SHIELD"),  slot = "ilvl187 shield" },
    { link = defItem(5, 200, "INVTYPE_WAIST"),   slot = "epic waist" },
}

local bandBad = nil
local bandCount = 0
for _, c in STD.ipairs(bandCases) do
    local s, _, r, g, b, loc = GS:GetItemScoreFromInfo(infoFor(c.link))
    bandCount = bandCount + 1
    local wr, wg, wb, wlabel = GS:GetQuality(s * ITEM_BAND_SCALE)
    if (r ~= wr or g ~= wg or b ~= wb) then
        bandBad = bandBad or string.format("%s (ilvl %s score %s): colour %s/%s/%s label-of-own-score %s",
            c.slot, tostring(ITEMS[c.link].ilvl), tostring(s),
            tostring(r), tostring(g), tostring(b), tostring(wlabel))
    end
    if (loc ~= ITEMS[c.link].equipLoc) then
        bandBad = bandBad or string.format("%s: equipLoc %s want %s", c.slot, tostring(loc),
            tostring(ITEMS[c.link].equipLoc))
    end
end
check("colour == GetQuality(score * 11.25) for all " .. bandCount .. " items",
    bandBad == nil, bandBad or "")

-- Hand-derived band labels. These bite where the old slot-mod-free band did
-- not: the old band fed 310*11.25 for every one of these items regardless of
-- slot, so ranged/trinket/neck all wore the HEAD's colour.
local function labelOf(link)
    local s, _, r, g, b = GS:GetItemScoreFromInfo(infoFor(link))
    local _, _, _, wl = GS:GetQuality(s * ITEM_BAND_SCALE)
    return wl, r, g, b, s
end

local rl = labelOf(RANGED)
check("ilvl 200 ranged band = " .. tostring(RANGED_ILVL200_LABEL[bracket]),
    rl == RANGED_ILVL200_LABEL[bracket], "got " .. tostring(rl) .. " (score 98 -> band 1102.5)")
local tl = labelOf(TRINKET)
check("ilvl 200 trinket band = " .. tostring(TRINKET_ILVL200_LABEL[bracket]),
    tl == TRINKET_ILVL200_LABEL[bracket], "got " .. tostring(tl) .. " (score 174 -> band 1957.5)")
local hl = labelOf(HEAD)
check("ilvl 200 head band = " .. tostring(HEAD_ILVL200_LABEL[bracket]),
    hl == HEAD_ILVL200_LABEL[bracket], "got " .. tostring(hl) .. " (score 310 -> band 3487.5)")
local twohl = labelOf(TWOH)
check("ilvl 200 2H band = " .. tostring(TWOH_ILVL200_LABEL[bracket]),
    twohl == TWOH_ILVL200_LABEL[bracket], "got " .. tostring(twohl) .. " (score 621 -> band 6986.25)")

-- ============================================================================
-- 3. A GearScore VALUE assertion. The suite had none anywhere, which is why
--    both defects above shipped green.
--
--    Every item is ilvl 200 / rarity 4, so each score is
--    floor(167 * SlotMOD * 1.8618) with 167 = (200 - 91.45) / 0.65:
--
--      SlotMOD 1.0000 -> 310   head, chest, legs, 1H main hand, shield
--      SlotMOD 0.7500 -> 233   shoulder, waist, feet, hands
--      SlotMOD 0.5625 -> 174   wrists, fingers, trinkets, cloak
--      SlotMOD 0.3164 ->  98   ranged
--      SlotMOD 2.0000 -> 621   2H main hand
--
--    Armour and accessories, 13 slots:
--      310 + 233 + 310 + 233 + 310 + 233            = 1629
--      174 + 233 + 174 + 174 + 174 + 174 + 174      = 1277
--      1629 + 1277                                  = 2906
--
--    SET A -- 1H main hand + shield (15 equipped slots + ranged):
--      2906 + 310 + 310 + 98 = 3624, TitanGrip 1, floor -> 3624.
--      This is the CONTROL: a one-handed main hand is not a 2H, so the Titan
--      Grip fix must not move this number at all.
--
--    SET B -- 2H main hand, no offhand (a 2H occupies slot 17, so "2H +
--    shield" cannot exist; the first version of this block built exactly that
--    and scored 3469, which is 3624.5 - 155 -- the shield counted at half.
--    That was a wrong EXPECTATION, not a wrong score, and pasting 3469 in
--    would have frozen an impossible inventory as gospel):
--      2906 + (621 * 0.5) + 98 = 3314.5, floor once at the end -> 3314.
--      Before the TitanGrip fix this set scored 2906 + 621 + 98 = 3625.
-- ============================================================================

local ARMOUR_AND_ACC = {
    { 1, "INVTYPE_HEAD" }, { 3, "INVTYPE_SHOULDER" }, { 5, "INVTYPE_CHEST" },
    { 6, "INVTYPE_WAIST" }, { 7, "INVTYPE_LEGS" }, { 8, "INVTYPE_FEET" },
    { 9, "INVTYPE_WRIST" }, { 10, "INVTYPE_HAND" }, { 11, "INVTYPE_FINGER" },
    { 12, "INVTYPE_FINGER" }, { 13, "INVTYPE_TRINKET" }, { 14, "INVTYPE_TRINKET" },
    { 15, "INVTYPE_CLOAK" },
}

INV = {}
for _, e in STD.ipairs(ARMOUR_AND_ACC) do INV[e[1]] = defItem(4, 200, e[2]) end
INV[16] = defItem(4, 200, "INVTYPE_WEAPONMAINHAND")
INV[17] = defItem(4, 200, "INVTYPE_SHIELD")
INV[18] = defItem(4, 200, "INVTYPE_RANGED")
local setA, setAILvl = totalOf()
check("SET A (1H + shield) totals 3624", setA == 3624, "got " .. tostring(setA))
check("SET A average item level 200", setAILvl == 200, "got " .. tostring(setAILvl))

INV = {}
for _, e in STD.ipairs(ARMOUR_AND_ACC) do INV[e[1]] = defItem(4, 200, e[2]) end
INV[16] = defItem(4, 200, "INVTYPE_2HWEAPON")
INV[18] = defItem(4, 200, "INVTYPE_RANGED")
local setB, setBILvl = totalOf()
check("SET B (2H, no offhand) totals 3625", setB == 3625, "got " .. tostring(setB))
check("SET B average item level 200", setBILvl == 200, "got " .. tostring(setBILvl))
check("SET B matches SET A (1H+shield) parity (3625 vs 3624)",
    math.abs(setB - setA) <= 1, "delta " .. tostring(setB - setA))

-- ============================================================================
-- 4. The low-slot guard: an item must be coloured like ITS OWN score, never
--    like a head's. Same item level, same rarity, same band formula -- the only
--    difference is the slot it occupies, which is exactly what the old code
--    threw away.
-- ============================================================================

local hs, _, hr, hg, hb = GS:GetItemScoreFromInfo(infoFor(HEAD))
local rs, _, rr, rg, rb = GS:GetItemScoreFromInfo(infoFor(RANGED))
check("the low-slot pair really scored 310 / 98",
    hs == 310 and rs == 98, "head " .. tostring(hs) .. " ranged " .. tostring(rs))
local hwr, hwg, hwb = GS:GetQuality(310 * ITEM_BAND_SCALE)
local rwr, rwg, rwb = GS:GetQuality(98 * ITEM_BAND_SCALE)
-- Each item must wear the band of the score it displays. The second clause is
-- the one that bites: pre-fix BOTH items were banded from the slot-mod-free
-- base, so they came back byte-identical and this fails.
check("ranged wears its OWN score's band, never a head's",
    rr == rwr and rg == rwg and rb == rwb
        and not (hr == rr and hg == rg and hb == rb),
    string.format("ranged %s/%s/%s own-band %s/%s/%s head %s/%s/%s",
        tostring(rr), tostring(rg), tostring(rb), tostring(rwr), tostring(rwg), tostring(rwb),
        tostring(hr), tostring(hg), tostring(hb)))
check("head wears its OWN score's band",
    hr == hwr and hg == hwg and hb == hwb,
    string.format("head %s/%s/%s want %s/%s/%s", tostring(hr), tostring(hg), tostring(hb),
        tostring(hwr), tostring(hwg), tostring(hwb)))

-- ============================================================================
-- 5. GetScore's cache gate, so the score assertions above cannot pass on an
--    all-zero mock. totalOf returns (score, averageItemLevel) -- unpacking the
--    SECOND value as the score is what made this read "got 200": 200 was the
--    average item level, not a GearScore.
-- ============================================================================

CACHE_TIME = 0
local cachedScore, cachedILvl = totalOf(OTHER_GUID)
check("an uncached inspected character scores 0,0",
    cachedScore == 0 and cachedILvl == 0,
    "got " .. tostring(cachedScore) .. "/" .. tostring(cachedILvl))
CACHE_TIME = 1234567
local otherScore, otherILvl = totalOf(OTHER_GUID)
check("the same inspected character scores the same as the player",
    otherScore == setB and otherILvl == setBILvl,
    "got " .. tostring(otherScore) .. "/" .. tostring(otherILvl)
        .. " want " .. tostring(setB) .. "/" .. tostring(setBILvl))

-- ============================================================================
-- 6. Hunter weapon scaling & nil-safety resilience
-- ============================================================================

local hTwohScore = GS:GetItemHunterScore(TWOH)
check("hunter 2H melee weapon scaled by 0.3164 (621 -> 196)",
    hTwohScore == 196, "got " .. tostring(hTwohScore))

local hRangedScore = GS:GetItemHunterScore(RANGED)
check("hunter ranged weapon scaled by 5.3224 (98 -> 521)",
    hRangedScore == 521, "got " .. tostring(hRangedScore))

local hHeadScore = GS:GetItemHunterScore(HEAD)
check("hunter non-weapon item unscaled (310)",
    hHeadScore == 310, "got " .. tostring(hHeadScore))

local nilScore = GS:GetItemScore(nil)
check("GetItemScore(nil) returns 0 safely", nilScore == 0, "got " .. tostring(nilScore))

local nilInfoScore = GS:GetItemScoreFromInfo(nil)
check("GetItemScoreFromInfo(nil) returns 0 safely", nilInfoScore == 0, "got " .. tostring(nilInfoScore))

local nilHunterScore = GS:GetItemHunterScore(nil)
check("GetItemHunterScore(nil) returns 0 safely", nilHunterScore == 0, "got " .. tostring(nilHunterScore))

-- ============================================================================
-- 7. The 2.0s per-item item-data throttle. Two rapid requests for one itemID
--    cost one raw call; past the window the same ID requests again. Without
--    the throttle every hover re-requests every uncached item.
-- ============================================================================

-- NOTE: dot calls, not colons. RequestLoadItemDataByID is a plain function
-- stored on TT_GS; a colon call would pass the module table as the itemID and
-- every assertion below would pin the same single throttle slot.
rawItemRequests = 0
GS.RequestLoadItemDataByID(424242)
check("first item-data request passes through",
    rawItemRequests == 1, "rawCalls=" .. tostring(rawItemRequests))
GS.RequestLoadItemDataByID(424242)
check("a rapid second request for the same item is throttled",
    rawItemRequests == 1, "rawCalls=" .. tostring(rawItemRequests))
-- A different itemID is a different throttle slot, not a bypass.
GS.RequestLoadItemDataByID(424243)
check("...while a different itemID gets its own slot",
    rawItemRequests == 2, "rawCalls=" .. tostring(rawItemRequests))
CACHE_TIME = CACHE_TIME + 3
GS.RequestLoadItemDataByID(424242)
check("...and the window expiring re-requests",
    rawItemRequests == 3, "rawCalls=" .. tostring(rawItemRequests))

-- ============================================================================
-- 8. The bootstrap slash handler and the TacoTip Extras.
--
-- gearscore.lua registers the EARLY "/tt" handler; options.lua replaces it
-- with the final one when it loads, so in a full add-on load the bootstrap
-- handler only survives when options.lua failed to load. This sandbox loads
-- gearscore.lua alone, which makes the bootstrap handler the LIVE handler
-- here -- and it is the handler that has to forward the Extras' leaderboard
-- sub-commands, because WoW's slash dispatch takes the FIRST matching
-- prefix and the order of the global scan is not specified. Without the
-- forwarding, "/tt lb" opened TacoTip's options panel instead of the
-- Extras' leaderboard.
--
-- In this sandbox TT.OpenOptionsPanel does not exist (options.lua is not
-- loaded), so the options-panel fallback is observable as the help block the
-- bootstrap handler prints instead of opening a panel.
-- ============================================================================

local function runSlash(msg)
    for i = #printed, 1, -1 do printed[i] = nil end
    local slash = rawget(env, "SlashCmdList")
    local handler = rawget(slash, "TACOTIP")
    if (type(handler) ~= "function") then return nil, nil end
    handler(msg)
    return #printed, STD.table.concat(printed, "\n")
end

local function printedContains(text)
    for i = 1, #printed do
        if (STD.string.find(printed[i], text, 1, true)) then return true end
    end
    return false
end

do
    local slash = rawget(env, "SlashCmdList")
    check("the bootstrap slash handler is registered",
        type(rawget(slash, "TACOTIP")) == "function")

    -- The Extras registers SlashCmdList.TACOTIPRANKS. Installed here as the
    -- stand-in for the companion add-on.
    local calls = 0
    local realRanks = rawget(slash, "TACOTIPRANKS")
    slash.TACOTIPRANKS = function() calls = calls + 1 end

    for _, word in ipairs({ "lb", "rank", "ranks", "leaderboard" }) do
        calls = 0
        runSlash(word)
        check('"/tt ' .. word .. '" reaches the TacoTip Extras handler',
            calls == 1, "calls=" .. tostring(calls))
        check('"/tt ' .. word .. '" does NOT fall back to the options panel',
            not printedContains("Slash commands are loaded."))
    end

    -- Mixed case and padding are normalised like every other sub-command.
    calls = 0
    runSlash("  LB  ")
    check('"/tt LB" (mixed case, padded) also reaches the Extras handler',
        calls == 1, "calls=" .. tostring(calls))

    -- The other sub-commands are untouched.
    for _, word in ipairs({ "save", "custom" }) do
        calls = 0
        runSlash(word)
        check('"/tt ' .. word .. '" is NOT forwarded to the Extras',
            calls == 0, "calls=" .. tostring(calls))
    end

    -- No Extras loaded: the fallback is exactly the old behaviour.
    slash.TACOTIPRANKS = realRanks
    calls = 0
    runSlash("lb")
    check('with no Extras handler, "/tt lb" falls back to the options panel',
        printedContains("Slash commands are loaded."))
    check("...and no handler was called", calls == 0, "calls=" .. tostring(calls))

    -- A non-function entry is treated as absent, not called.
    slash.TACOTIPRANKS = "not a function"
    runSlash("lb")
    check('an Extras entry that is not a function falls back to the options panel',
        printedContains("Slash commands are loaded."))

    -- "/tt" alone still takes the options-panel fallback.
    runSlash("")
    check('"/tt" alone still takes the options-panel fallback',
        printedContains("Slash commands are loaded."))

    -- M2: the "gs" word asks the Extras for its OPTIONS category, and it must
    -- NOT be answered by the diagnostic snapshot.
    --
    -- The resolver used to fall back to the published debug-snapshot function
    -- (and then to the debug slash entry) when the options entry was absent,
    -- so a MISSING options entry answered "/tt gs" with a telemetry dump
    -- instead of the options the player asked for -- the wrong surface,
    -- silently, with no way to tell it apart from the real thing. With no
    -- options entry there is nothing to forward to, so the word falls through
    -- to TacoTip's own options panel, which is what the player gets when the
    -- Extras is not installed at all.
    --
    -- Both debug surfaces are installed here (the published global AND the
    -- slash entry), because the resolver used to reach for either one.
    do
        local debugCalls = 0
        local realDebugEntry = rawget(slash, "TTEXTRASDEBUG")
        local realPublished = rawget(env, "TacoTipExtrasPrintDebugSnapshot")
        slash.TTEXTRASDEBUG = function() debugCalls = debugCalls + 1 end
        rawset(env, "TacoTipExtrasPrintDebugSnapshot", function() debugCalls = debugCalls + 1 end)

        -- No TTEXTRAS entry: the Extras' options category is not registered.
        debugCalls = 0
        runSlash("gs")
        check('"/tt gs" does NOT fall back to the debug snapshot',
            debugCalls == 0, "debugCalls=" .. tostring(debugCalls))
        check('"/tt gs" with no Extras options entry falls back to the options panel',
            printedContains("Slash commands are loaded."))

        -- The debug surface itself is untouched: "/tt gsdebug" still reaches
        -- the diagnostic snapshot, which is what that word is for.
        debugCalls = 0
        runSlash("gsdebug")
        check('"/tt gsdebug" still reaches the diagnostic snapshot',
            debugCalls == 1, "debugCalls=" .. tostring(debugCalls))

        slash.TTEXTRASDEBUG = realDebugEntry
        if (realPublished) then
            rawset(env, "TacoTipExtrasPrintDebugSnapshot", realPublished)
        else
            rawset(env, "TacoTipExtrasPrintDebugSnapshot", nil)
        end
    end

    -- A raise inside the Extras handler is COUNTED and reported (the house
    -- rule for a discarded pcall result: count it and say so), and the player
    -- is NOT also shown the options panel -- they asked for the Extras.
    do
        local ns = env.TacoTip_Forever
        local before = (ns and ns.ev and ns.ev.extrasForwardFailed) or 0
        local savedRanks = rawget(slash, "TACOTIPRANKS")
        slash.TACOTIPRANKS = function() error("PIN_EXTRAS_RAISE") end
        runSlash("lb")
        local after = (ns and ns.ev and ns.ev.extrasForwardFailed) or 0
        check("a raise inside the Extras handler is counted",
            after == before + 1,
            "before=" .. tostring(before) .. " after=" .. tostring(after))
        check("...and it is reported to the player",
            printedContains("could not run"))
        check("...and the options panel is NOT opened as well",
            not printedContains("Slash commands are loaded."))
        slash.TACOTIPRANKS = savedRanks
    end
end

-- ---- report -----------------------------------------------------------------

local fails = 0
for _, c in STD.ipairs(checks) do
    if (not c[2]) then
        fails = fails + 1
        STD.io.write(string.format("    FAIL %-50s %s\n", c[1], tostring(c[3] or "")))
    end
end
STD.io.write(string.format("%-12s %-10s bracket=%-5d %s\n", tostring(label), family,
    bracket, (fails == 0) and ("ALL " .. #checks .. " PASS")
        or (fails .. "/" .. #checks .. " FAILED")))
STD.os.exit(fails == 0 and 0 or 1)
