--[[

    LibForeverInspector
    Universal multi-engine inspection & specialization library
    Supports: Classic Era / SoD (1.15.x), TBC Anniversary (2.5.x),
              WotLK (3.4.x / 3.80.x), WoW Forever (1.60.x), and Retail (11.x / 12.x)

    Requires: LibStub, CallbackHandler-1.0
--]]

local MAJOR, MINOR = "LibForeverInspector", 3
assert(LibStub, "LibForeverInspector requires LibStub")
assert(LibStub:GetLibrary("CallbackHandler-1.0", true), "LibForeverInspector requires CallbackHandler-1.0")

local lib = LibStub:NewLibrary(MAJOR, MINOR)
if (not lib) then return end

-- Alias registration so legacy and modern callers can resolve the inspector.
-- Registered unconditionally and with a minor version: the previous
-- `if not stubLibs[...]` guard meant that after a version bump in the same Lua
-- state the alias kept pointing at the OLD table while `lib` was the new one,
-- and minors["LibClassicInspector"] stayed nil for any caller that reads it.
if (type(LibStub) == "table") then
    local stubLibs = rawget(LibStub, "libs")
    local stubMinors = rawget(LibStub, "minors")
    if (type(stubLibs) == "table") then
        stubLibs["LibClassicInspector"] = lib
    end
    if (type(stubMinors) == "table") then
        stubMinors["LibClassicInspector"] = MINOR
    end
end

-- NOTE: GetNumTalentTabs is deliberately NOT captured into a file-scope local.
-- It is a deprecation shim created by Blizzard_DeprecatedSpecialization, whose
-- every family variant begins
--   if not GetCVarBool("loadDeprecationFallbacks") then return end
-- so it may not exist yet when this library loads, and a local latched to nil
-- can never recover. It is resolved at call time instead.
--
-- GetTalentTabInfo is the sibling shim and used to be resolved the same way. It
-- is no longer read at all: the Classic talent path now sums per-talent `rank`
-- through GetTalentInfo, exactly as the working LibClassicInspector does, which
-- is independent of whether that CVar is set.
local function getNumTalentTabs()
    return _G.GetNumTalentTabs
end

lib.callbacks = lib.callbacks or LibStub("CallbackHandler-1.0"):New(lib)
lib.cache = lib.cache or {}

local frame = lib.frame or CreateFrame("Frame")
lib.frame = frame

--------------------------------------------------------------------------
-- Client family detection
--------------------------------------------------------------------------
-- Two independent signals, because neither is sufficient alone.
--
-- 1. WOW_PROJECT_ID. Defined per client and mutually distinct:
--      WOW_PROJECT_MAINLINE                 = 1  (Retail live AND WoW Forever)
--      WOW_PROJECT_CLASSIC                  = 2  (Classic Era / SoD)
--      WOW_PROJECT_BURNING_CRUSADE_CLASSIC  = 5  (TBC Anniversary)
--      WOW_PROJECT_WRATH_CLASSIC            = 11 (WotLK Titanforge)
--    On the Classic clients it is a Lua global assigned by
--    Blizzard_FrameXMLBase/<Family>/Constants.lua; on Retail/Forever it is
--    engine/BNet-defined. It cannot degenerate to `nil == nil` because
--    WOW_PROJECT_MAINLINE is 1 on every client, so the retail test is safe.
--    It cannot, however, separate Forever from Retail -- both are MAINLINE.
--
-- 2. The interface version, to split the MAINLINE family. Retail and Forever
--    BOTH document the 4th GetBuildInfo return as interfaceVersion
--    (Blizzard_APIDocumentationGenerated/BuildDocumentation.lua), so that slot is
--    reliable for exactly the two clients that need it. The three Classic
--    branches omit GetBuildInfo from their generated docs entirely and Blizzard's
--    own Classic code reads select(7, GetBuildInfo()) for its build number, so
--    slot 4's type there is not established. Reading both slots and taking
--    whichever is numeric removes the dependency on that unverified layout.
local _, _, _, ret4, _, _, ret7 = GetBuildInfo()
local interfaceVersion = 0
if (type(ret4) == "number") then
    interfaceVersion = ret4
elseif (type(ret7) == "number") then
    interfaceVersion = ret7
end
local clientBuildMajor = math.floor(interfaceVersion / 10000)

local WOW_PROJECT_ID = rawget(_G, "WOW_PROJECT_ID")
local WOW_PROJECT_MAINLINE = rawget(_G, "WOW_PROJECT_MAINLINE") or 1
local WOW_PROJECT_CLASSIC = rawget(_G, "WOW_PROJECT_CLASSIC")
local WOW_PROJECT_BC_CLASSIC = rawget(_G, "WOW_PROJECT_BURNING_CRUSADE_CLASSIC")
local WOW_PROJECT_WRATH_CLASSIC = rawget(_G, "WOW_PROJECT_WRATH_CLASSIC")

local isMainline = (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE)

-- Forever is the only client in the 16000-19999 interface band. Retail 1.6-1.8
-- used four-digit interfaces (1600/1700/1800) and Retail jumped to 10900 at
-- 1.9.0, so nothing else lands here.
local isForever = isMainline and (interfaceVersion >= 16000 and interfaceVersion < 20000)
local isRetail = isMainline and not isForever

local isClassic = (WOW_PROJECT_ID == WOW_PROJECT_CLASSIC)
local isTBC = (WOW_PROJECT_ID == WOW_PROJECT_BC_CLASSIC)
local isWotlk = (WOW_PROJECT_ID == WOW_PROJECT_WRATH_CLASSIC)

-- Fallbacks for when WOW_PROJECT_ID is unavailable or unrecognised (it is
-- engine-defined on WoW Forever, so it is not verifiable from source there).
-- These only fill gaps; a client already identified above is never reclassified.
if (not (isClassic or isTBC or isWotlk or isForever or isRetail)) then
    if (interfaceVersion >= 16000 and interfaceVersion < 20000) then
        isForever, isRetail = true, false
    elseif (clientBuildMajor == 1) then
        isClassic = true
    elseif (clientBuildMajor == 2) then
        isTBC = true
    elseif (clientBuildMajor == 3) then
        isWotlk = true
    elseif (clientBuildMajor >= 10) then
        isRetail = true
    end
end

local family
if isClassic then
    family = "classicEra"
elseif isTBC then
    family = "tbc"
elseif isWotlk then
    family = "titanforge"
elseif isForever then
    family = "forever"
elseif isRetail then
    family = "retail"
else
    family = "unknown"
end

lib.family = family
lib.interfaceVersion = interfaceVersion

-- Per-tab talent count cap, from the known-good LibClassicInspector.
local MAX_TALENTS_PER_TAB = 31

function lib:IsRetail()
    return isRetail
end

function lib:IsForever()
    return isForever
end

function lib:IsClassic()
    return isClassic
end

function lib:IsTBC()
    return isTBC
end

function lib:IsWotlk()
    return isWotlk
end

-- True when the client matched none of the known families. Consumers that pick
-- a default (e.g. a GearScore bracket) should check this rather than silently
-- inheriting a fallback value for a client nobody has looked at.
function lib:IsUnknown()
    return (family == "unknown")
end

-- Coarse capability snapshot, resolved once, for consumers that need to branch
-- on behaviour rather than on client identity.
lib.caps = {
    dataPipeline = (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall) and true or false,
    tooltipUtil = (TooltipUtil ~= nil) and true or false,
    cItemNamespace = (C_Item ~= nil) and true or false,
    legacyItemObject = (_G.Item and _G.Item.CreateFromItemLink) and true or false,
    specializationInspect = (C_SpecializationInfo and C_SpecializationInfo.GetInspectSpecialization) and true or false,
    talentTabs = (getNumTalentTabs() ~= nil) and true or false,
    settingsPanel = (_G.Settings and _G.Settings.RegisterCanvasLayoutCategory) and true or false,
    colorPicker = (_G.ColorPickerFrame ~= nil) and true or false,
}

lib.spec_table = lib.spec_table or {
    ["WARRIOR"] = { "Arms", "Fury", "Protection" },
    ["PALADIN"] = { "Holy", "Protection", "Retribution" },
    ["HUNTER"] = { "Beast Mastery", "Marksmanship", "Survival" },
    ["ROGUE"] = { "Assassination", "Combat", "Subtlety" },
    ["PRIEST"] = { "Discipline", "Holy", "Shadow" },
    ["DEATHKNIGHT"] = { "Blood", "Frost", "Unholy" },
    ["SHAMAN"] = { "Elemental", "Enhancement", "Restoration" },
    ["MAGE"] = { "Arcane", "Fire", "Frost" },
    ["WARLOCK"] = { "Affliction", "Demonology", "Destruction" },
    ["DRUID"] = { "Balance", "Feral Combat", "Restoration" },
    ["MONK"] = { "Brewmaster", "Mistweaver", "Windwalker" },
    ["DEMONHUNTER"] = { "Havoc", "Vengeance" },
    ["EVOKER"] = { "Devastation", "Preservation", "Augmentation" },
}


---------------------------------------------------------------------------
-- Static talent and glyph data
---------------------------------------------------------------------------
-- Ported verbatim from LibClassicInspector, which is the known-good Classic
-- implementation. This is what makes the specialization icon work: the icon is
-- NOT read from a live API on the Classic clients, it comes from this static
-- table, so the rendering is deterministic and needs no live specialization
-- data at all.
--
-- The earlier rewrite of this library dropped the table along with
-- GetTalentInfoByClass, so main.lua's icon lookup silently returned nothing on
-- every client. main.lua is unchanged; the data is restored here instead.
--
-- Glyphs are included because they share the same isWotlk-gated block and
-- lib.glyph_r_tbl is built from them.
-- playerClass is only needed to build glyph_r_tbl inside the WotLK block below.
-- The working lib read it at file scope; here it is resolved lazily so the
-- library has no load-order dependency on UnitClass.
local oldminor = MINOR

if (isWotlk) then
    if (oldminor < 16) then
        lib.glyphs_table = nil
        lib.glyph_r_tbl = nil
    end
    lib.tracked_achievements = lib.tracked_achievements or {}
    lib.glyphs_table = lib.glyphs_table or {
        ["WARRIOR"] = {
            [1] = {
                [1] = 58353,  -- Glyph of Taunt
                [2] = 58355,  -- Glyph of Rapid Charge
                [3] = 58356,  -- Glyph of Resonating Power
                [4] = 58357,  -- Glyph of Heroic Strike
                [5] = 58364,  -- Glyph of Revenge
                [6] = 58365,  -- Glyph of Barbaric Insults
                [7] = 58366,  -- Glyph of Cleaving
                [8] = 58367,  -- Glyph of Execution
                [9] = 58368,  -- Glyph of Mortal Strike
                [10] = 58369, -- Glyph of Bloodthirst
                [11] = 58370, -- Glyph of Whirlwind
                [12] = 58372, -- Glyph of Hamstring
                [13] = 58375, -- Glyph of Blocking
                [14] = 58376, -- Glyph of Last Stand
                [15] = 58377, -- Glyph of Intervene
                [16] = 58382, -- Glyph of Victory Rush
                [17] = 58384, -- Glyph of Sweeping Strikes
                [18] = 58385, -- Glyph of Rending
                [19] = 58386, -- Glyph of Overpower
                [20] = 58387, -- Glyph of Sunder Armor
                [21] = 58388, -- Glyph of Devastate
                [22] = 63324, -- Glyph of Bladestorm
                [23] = 63325, -- Glyph of Shockwave
                [24] = 63326, -- Glyph of Vigilance
                [25] = 63327, -- Glyph of Enraged Regeneration
                [26] = 63328, -- Glyph of Spell Reflection
                [27] = 63329  -- Glyph of Shield Wall
            },
            [2] = {
                [1] = 58095, -- Glyph of Battle
                [2] = 58096, -- Glyph of Bloodrage
                [3] = 58097, -- Glyph of Charge
                [4] = 58098, -- Glyph of Thunder Clap
                [5] = 58099, -- Glyph of Mocking Blow
                [6] = 58104, -- Glyph of Enduring Victory
                [7] = 68164, -- Glyph of Command
                [8] = 414812 -- Glyph of Shattering Throw
            },
        },
        ["PALADIN"] = {
            [1] = {
                [1] = 54922,  -- Glyph of Judgement
                [2] = 54923,  -- Glyph of Hammer of Justice
                [3] = 54924,  -- Glyph of Spiritual Attunement
                [4] = 54925,  -- Glyph of Seal of Command
                [5] = 54926,  -- Glyph of Hammer of Wrath
                [6] = 54927,  -- Glyph of Crusader Strike
                [7] = 54928,  -- Glyph of Consecration
                [8] = 54929,  -- Glyph of Righteous Defense
                [9] = 54930,  -- Glyph of Avenger's Shield
                [10] = 54931, -- Glyph of Turn Evil
                [11] = 54934, -- Glyph of Exorcism
                [12] = 54935, -- Glyph of Cleansing
                [13] = 54936, -- Glyph of Flash of Light
                [14] = 54937, -- Glyph of Holy Light
                [15] = 54938, -- Glyph of Avenging Wrath
                [16] = 54939, -- Glyph of Divinity
                [17] = 54940, -- Glyph of Seal of Wisdom
                [18] = 54943, -- Glyph of Seal of Light
                [19] = 56414, -- Glyph of Seal of Righteousness
                [20] = 56416, -- Glyph of Seal of Vengeance
                [21] = 56420, -- Glyph of Holy Wrath
                [22] = 63218, -- Glyph of Beacon of Light
                [23] = 63219, -- Glyph of Hammer of the Righteous
                [24] = 63220, -- Glyph of Divine Storm
                [25] = 63222, -- Glyph of Shield of Righteousness
                [26] = 63223, -- Glyph of Divine Plea
                [27] = 63224, -- Glyph of Holy Shock
                [28] = 63225, -- Glyph of Salvation
                [29] = 405004 -- Glyph of Reckoning
            },
            [2] = {
                [1] = 57937, -- Glyph of Blessing of Kings
                [2] = 57947, -- Glyph of Sense Undead
                [3] = 57954, -- Glyph of the Wise
                [4] = 57955, -- Glyph of Lay on Hands
                [5] = 57958, -- Glyph of Blessing of Might
                [6] = 57979  -- Glyph of Blessing of Wisdom
            },
        },
        ["HUNTER"] = {
            [1] = {
                [1] = 56824,  -- Glyph of Aimed Shot
                [2] = 56826,  -- Glyph of Steady Shot
                [3] = 56828,  -- Glyph of Rapid Fire
                [4] = 56829,  -- Glyph of Hunter's Mark
                [5] = 56830,  -- Glyph of Bestial Wrath
                [6] = 56832,  -- Glyph of Serpent Sting
                [7] = 56833,  -- Glyph of Mending
                [8] = 56836,  -- Glyph of Multi-Shot
                [9] = 56838,  -- Glyph of Volley
                [10] = 56841, -- Glyph of Arcane Shot
                [11] = 56842, -- Glyph of Trueshot Aura
                [12] = 56844, -- Glyph of Disengage
                [13] = 56845, -- Glyph of Freezing Trap
                [14] = 56846, -- Glyph of Immolation Trap
                [15] = 56847, -- Glyph of Frost Trap
                [16] = 56848, -- Glyph of Wyvern Sting
                [17] = 56849, -- Glyph of Snake Trap
                [18] = 56850, -- Glyph of Deterrence
                [19] = 56851, -- Glyph of Aspect of the Viper
                [20] = 56856, -- Glyph of the Hawk
                [21] = 56857, -- Glyph of the Beast
                [22] = 63065, -- Glyph of Chimera Shot
                [23] = 63066, -- Glyph of Explosive Shot
                [24] = 63067, -- Glyph of Kill Shot
                [25] = 63068, -- Glyph of Explosive Trap
                [26] = 63069, -- Glyph of Scatter Shot
                [27] = 63086  -- Glyph of Raptor Strike
            },
            [2] = {
                [1] = 57866, -- Glyph of Revive Pet
                [2] = 57870, -- Glyph of Mend Pet
                [3] = 57900, -- Glyph of Possessed Strength
                [4] = 57902, -- Glyph of Scare Beast
                [5] = 57903, -- Glyph of Feign Death
                [6] = 57904  -- Glyph of the Pack
            },
        },
        ["ROGUE"] = {
            [1] = {
                [1] = 56798,  -- Glyph of Sap
                [2] = 56799,  -- Glyph of Evasion
                [3] = 56800,  -- Glyph of Backstab
                [4] = 56801,  -- Glyph of Rupture
                [5] = 56802,  -- Glyph of Eviscerate
                [6] = 56803,  -- Glyph of Expose Armor
                [7] = 56804,  -- Glyph of Feint
                [8] = 56805,  -- Glyph of Vigor
                [9] = 56806,  -- Glyph of Deadly Throw
                [10] = 56807, -- Glyph of Hemorrhage
                [11] = 56808, -- Glyph of Adrenaline Rush
                [12] = 56809, -- Glyph of Gouge
                [13] = 56810, -- Glyph of Slice and Dice
                [14] = 56811, -- Glyph of Sprint
                [15] = 56812, -- Glyph of Garrote
                [16] = 56813, -- Glyph of Ambush
                [17] = 56814, -- Glyph of Ghostly Strike
                [18] = 56818, -- Glyph of Blade Flurry
                [19] = 56819, -- Glyph of Preparation
                [20] = 56820, -- Glyph of Crippling Poison
                [21] = 56821, -- Glyph of Sinister Strike
                [22] = 63269, -- Glyph of Cloak of Shadows
                [23] = 63249, -- Glyph of Hunger of Blood
                [24] = 63252, -- Glyph of Killing Spree
                [25] = 63253, -- Glyph of Shadow Dance
                [26] = 63254, -- Glyph of Fan of Knives
                [27] = 63256, -- Glyph of Tricks of the Trade
                [28] = 63268, -- Glyph of Mutilate
                [29] = 64199  -- Glyph of Envenom
            },
            [2] = {
                [1] = 58017, -- Glyph of Pick Pocket
                [2] = 58027, -- Glyph of Pick Lock
                [3] = 58032, -- Glyph of Distract
                [4] = 58033, -- Glyph of Safe Fall
                [5] = 58038, -- Glyph of Vanish
                [6] = 58039  -- Glyph of Blurred Speed
            },
        },
        ["PRIEST"] = {
            [1] = {
                [1] = 55672,  -- Glyph of Power Word: Shield
                [2] = 55673,  -- Glyph of Lightwell
                [3] = 55674,  -- Glyph of Renew
                [4] = 55675,  -- Glyph of Circle of Healing
                [5] = 55676,  -- Glyph of Psychic Scream
                [6] = 55677,  -- Glyph of Dispel Magic
                [7] = 55678,  -- Glyph of Fear Ward
                [8] = 55679,  -- Glyph of Flash Heal
                [9] = 55680,  -- Glyph of Prayer of Healing
                [10] = 55681, -- Glyph of Shadow Word: Pain
                [11] = 55682, -- Glyph of Shadow Word: Death
                [12] = 55683, -- Glyph of Holy Nova
                [13] = 55684, -- Glyph of Fade
                [14] = 55685, -- Glyph of Spirit of Redemption
                [15] = 55686, -- Glyph of Inner Fire
                [16] = 55687, -- Glyph of Mind Flay
                [17] = 55688, -- Glyph of Mind Control
                [18] = 55689, -- Glyph of Shadow
                [19] = 55690, -- Glyph of Scourge Imprisonment
                [20] = 55691, -- Glyph of Mass Dispel
                [21] = 55692, -- Glyph of Smite
                [22] = 63229, -- Glyph of Dispersion
                [23] = 63231, -- Glyph of Guardian Spirit
                [24] = 63235, -- Glyph of Penance
                [25] = 63237, -- Glyph of Mind Sear
                [26] = 63246, -- Glyph of Hymn of Hope
                [27] = 63248  -- Glyph of Pain Suppression
            },
            [2] = {
                [1] = 57985, -- Glyph of Fading
                [2] = 57986, -- Glyph of Shackle Undead
                [3] = 57987, -- Glyph of Levitate
                [4] = 58009, -- Glyph of Fortitude
                [5] = 58015, -- Glyph of Shadow Protection
                [6] = 58228  -- Glyph of Shadowfiend
            },
        },
        ["DEATHKNIGHT"] = {
            [1] = {
                [1] = 58613,  -- Glyph of Dark Command
                [2] = 58616,  -- Glyph of Heart Strike
                [3] = 58618,  -- Glyph of Strangulate
                [4] = 58620,  -- Glyph of Chains of Ice
                [5] = 58623,  -- Glyph of Anti-Magic Shell
                [6] = 58625,  -- Glyph of Icebound Fortitude
                [7] = 58629,  -- Glyph of Death and Decay
                [8] = 58631,  -- Glyph of Icy Touch
                [9] = 58635,  -- Glyph of Unbreakable Armor
                [10] = 58642, -- Glyph of Scourge Strike
                [11] = 58647, -- Glyph of Frost Strike
                [12] = 58657, -- Glyph of Plague Strike
                [13] = 58669, -- Glyph of Rune Strike
                [14] = 58671, -- Glyph of Obliterate
                [15] = 58673, -- Glyph of Bone Shield
                [16] = 58676, -- Glyph of Vampiric Blood
                [17] = 58686, -- Glyph of the Ghoul
                [18] = 59327, -- Glyph of Rune Tap
                [19] = 59332, -- Glyph of Blood Strike
                [20] = 59336, -- Glyph of Death Strike
                [21] = 62259, -- Glyph of Death Grip
                [22] = 63330, -- Glyph of Dancing Rune Weapon
                [23] = 63331, -- Glyph of Hungering Cold
                [24] = 63332, -- Glyph of Unholy Blight
                [25] = 63333, -- Glyph of Dark Death
                [26] = 63334, -- Glyph of Disease
                [27] = 63335  -- Glyph of Howling Blast
            },
            [2] = {
                [1] = 58640, -- Glyph of Blood Tap
                [2] = 58677, -- Glyph of Death's Embrace
                [3] = 58680, -- Glyph of Horn of Winter
                [4] = 59307, -- Glyph of Corpse Explosion
                [5] = 59309, -- Glyph of Pestilence
                [6] = 60200  -- Glyph of Raise Dead
            },
        },
        ["SHAMAN"] = {
            [1] = {
                [1] = 55436,  -- Glyph of Water Mastery
                [2] = 55437,  -- Glyph of Chain Heal
                [3] = 55438,  -- Glyph of Lesser Healing Wave
                [4] = 55439,  -- Glyph of Earthliving Weapon
                [5] = 55440,  -- Glyph of Healing Wave
                [6] = 55441,  -- Glyph of Mana Tide
                [7] = 55442,  -- Glyph of Shocking
                [8] = 55443,  -- Glyph of Frost Shock
                [9] = 55444,  -- Glyph of Lava Lash
                [10] = 55445, -- Glyph of Windfury Weapon
                [11] = 55446, -- Glyph of Stormstrike
                [12] = 55447, -- Glyph of Flame Shock
                [13] = 55448, -- Glyph of Lightning Shield
                [14] = 55449, -- Glyph of Chain Lightning
                [15] = 55450, -- Glyph of Fire Nova
                [16] = 55451, -- Glyph of Flametongue Weapon
                [17] = 55452, -- Glyph of Elemental Mastery
                [18] = 55453, -- Glyph of Lightning Bolt
                [19] = 55454, -- Glyph of Lava
                [20] = 55455, -- Glyph of Fire Elemental Totem
                [21] = 55456, -- Glyph of Healing Stream Totem
                [22] = 63270, -- Glyph of Thunder
                [23] = 63271, -- Glyph of Feral Spirit
                [24] = 63273, -- Glyph of Riptide
                [25] = 63279, -- Glyph of Earth Shield
                [26] = 63280, -- Glyph of Totem of Wrath
                [27] = 63291, -- Glyph of Hex
                [28] = 63298  -- Glyph of Stoneclaw Totem
            },
            [2] = {
                [1] = 58055, -- Glyph of Water Breathing
                [2] = 58057, -- Glyph of Water Walking
                [3] = 58058, -- Glyph of Astral Recall
                [4] = 58059, -- Glyph of Renewed Life
                [5] = 58063, -- Glyph of Water Shield
                [6] = 59289, -- Glyph of Ghost Wolf
                [7] = 62132  -- Glyph of Thunderstorm
            },
        },
        ["MAGE"] = {
            [1] = {
                [1] = 56360,  -- Glyph of Arcane Explosion
                [2] = 56363,  -- Glyph of Arcane Missiles
                [3] = 56364,  -- Glyph of Remove Curse
                [4] = 56365,  -- Glyph of Blink
                [5] = 56366,  -- Glyph of Invisibility
                [6] = 56367,  -- Glyph of Mana Gem
                [7] = 56368,  -- Glyph of Fireball
                [8] = 56369,  -- Glyph of Fire Blast
                [9] = 56370,  -- Glyph of Frostbolt
                [10] = 56371, -- Glyph of Scorch
                [11] = 56372, -- Glyph of Ice Block
                [12] = 56373, -- Glyph of Water Elemental
                [13] = 56374, -- Glyph of Icy Veins
                [14] = 56375, -- Glyph of Polymorph
                [15] = 56376, -- Glyph of Frost Nova
                [16] = 56377, -- Glyph of Ice Lance
                [17] = 56380, -- Glyph of Evocation
                [18] = 56381, -- Glyph of Arcane Power
                [19] = 56382, -- Glyph of Molten Armor
                [20] = 56383, -- Glyph of Mage Armor
                [21] = 56384, -- Glyph of Ice Armor
                [22] = 61205, -- Glyph of Frostfire
                [23] = 62210, -- Glyph of Arcane Blast
                [24] = 63090, -- Glyph of Deep Freeze
                [25] = 63091, -- Glyph of Living Bomb
                [26] = 63092, -- Glyph of Arcane Barrage
                [27] = 63093, -- Glyph of Mirror Image
                [28] = 63095, -- Glyph of Ice Barrier
                [29] = 70937  -- Glyph of Eternal Water
            },
            [2] = {
                [1] = 52648, -- Glyph of the Penguin
                [2] = 57924, -- Glyph of Arcane Intellect
                [3] = 57925, -- Glyph of Slow Fall
                [4] = 57926, -- Glyph of Fire Ward
                [5] = 57927, -- Glyph of Frost Ward
                [6] = 57928, -- Glyph of Frost Armor
                [7] = 62126  -- Glyph of Blast Wave
            },
        },
        ["WARLOCK"] = {
            [1] = {
                [1] = 56216,  -- Glyph of Siphon Life
                [2] = 56217,  -- Glyph of Howl of Terror
                [3] = 56218,  -- Glyph of Corruption
                [4] = 56224,  -- Glyph of Healthstone
                [5] = 56226,  -- Glyph of Searing Pain
                [6] = 56228,  -- Glyph of Immolate
                [7] = 56229,  -- Glyph of Shadowburn
                [8] = 56231,  -- Glyph of Soulstone
                [9] = 56232,  -- Glyph of Death Coil
                [10] = 56233, -- Glyph of Unstable Affliction
                [11] = 56235, -- Glyph of Conflagrate
                [12] = 56238, -- Glyph of Health Funnel
                [13] = 56240, -- Glyph of Shadow Bolt
                [14] = 56241, -- Glyph of Curse of Agony
                [15] = 56242, -- Glyph of Incinerate
                [16] = 56244, -- Glyph of Fear
                [17] = 56246, -- Glyph of Felguard
                [18] = 56247, -- Glyph of Voidwalker
                [19] = 56248, -- Glyph of Imp
                [20] = 56249, -- Glyph of Felhunter
                [21] = 56250, -- Glyph of Succubus
                [22] = 63302, -- Glyph of Haunt
                [23] = 63303, -- Glyph of Metamorphosis
                [24] = 63304, -- Glyph of Chaos Bolt
                [25] = 63309, -- Glyph of Demonic Circle
                [26] = 63310, -- Glyph of Shadowflame
                [27] = 63312, -- Glyph of Soul Link
                [28] = 63320, -- Glyph of Life Tap
                [29] = 70947  -- Glyph of Quick Decay
            },
            [2] = {
                [1] = 58070, -- Glyph of Drain Soul
                [2] = 58079, -- Glyph of Unending Breath
                [3] = 58080, -- Glyph of Curse of Exhausion
                [4] = 58081, -- Glyph of Kilrogg
                [5] = 58094, -- Glyph of Souls
                [6] = 58107  -- Glyph of Subjugate Demon
            },
        },
        ["DRUID"] = {
            [1] = {
                [1] = 54733,  -- Glyph of Rebirth
                [2] = 54743,  -- Glyph of Regrowth
                [3] = 54754,  -- Glyph of Rejuvenation
                [4] = 54756,  -- Glyph of Wrath
                [5] = 54760,  -- Glyph of Entangling Roots
                [6] = 54810,  -- Glyph of Frenzied Regeneration
                [7] = 54811,  -- Glyph of Maul
                [8] = 54812,  -- Glyph of Growling
                [9] = 54813,  -- Glyph of Mangle
                [10] = 54815, -- Glyph of Shred
                [11] = 54818, -- Glyph of Rip
                [12] = 54821, -- Glyph of Rake
                [13] = 54824, -- Glyph of Swiftmend
                [14] = 54825, -- Glyph of Healing Touch
                [15] = 54826, -- Glyph of Lifebloom
                [16] = 54828, -- Glyph of Starfall
                [17] = 54829, -- Glyph of Moonfire
                [18] = 54830, -- Glyph of Insect Swarm
                [19] = 54831, -- Glyph of Hurricane
                [20] = 54832, -- Glyph of Innervate
                [21] = 54845, -- Glyph of Starfire
                [22] = 62080, -- Glyph of Focus
                [23] = 62969, -- Glyph of Berserk
                [24] = 62970, -- Glyph of Wild Growth
                [25] = 62971, -- Glyph of Nourish
                [26] = 63055, -- Glyph of Savage Roar
                [27] = 63056, -- Glyph of Monsoon
                [28] = 63057, -- Glyph of Barkskin
                [29] = 65243, -- Glyph of Survival Instincts
                [30] = 67598, -- Glyph of Claw
                [31] = 71013, -- Glyph of Rapid Rejuvenation
                [32] = 413895 -- Glyph of Omen of Clarity
            },
            [2] = {
                [1] = 57855, -- Glyph of the Wild
                [2] = 57856, -- Glyph of Aquatic Form
                [3] = 57857, -- Glyph of Unburdened Rebirth
                [4] = 57858, -- Glyph of Challenging Roar
                [5] = 57862, -- Glyph of Thorns
                [6] = 59219, -- Glyph of Dash
                [7] = 62135  -- Glyph of Typhoon
            },
        }
    }
    if (not lib.glyph_r_tbl) then
        local playerClass = UnitClass and select(2, UnitClass("player")) or nil
        lib.glyph_r_tbl = {}
        if (playerClass and lib.glyphs_table[playerClass]) then
            for k, v in pairs(lib.glyphs_table[playerClass][1]) do
                lib.glyph_r_tbl[v] = k
            end
            for k, v in pairs(lib.glyphs_table[playerClass][2]) do
                lib.glyph_r_tbl[v] = k
            end
        end
    end
    lib.talents_table = lib.talents_table or {
        ["HUNTER"] = {
            [1] = {
                [26] = { ["name"] = "Kindred Spirits", ["tier"] = 10, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 236202 },
                [25] = { ["name"] = "Longevity", ["tier"] = 9, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 236186 },
                [24] = { ["isExceptional"] = 1, ["name"] = "Beast Mastery", ["tier"] = 11, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 236175 },
                [23] = { ["name"] = "Aspect Mastery", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 236172 },
                [22] = { ["name"] = "Cobra Strikes", ["tier"] = 9, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 236177 },
                [21] = { ["name"] = "Invigoration", ["tier"] = 8, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 236184 },
                [20] = { ["name"] = "The Beast Within", ["tier"] = 9, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132166 },
                [19] = { ["name"] = "Serpent's Swiftness", ["tier"] = 8, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 132209 },
                [18] = { ["name"] = "Catlike Reflexes", ["tier"] = 7, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 132167 },
                [9] = { ["name"] = "Bestial Discipline", ["tier"] = 5, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 136006 },
                [1] = { ["name"] = "Improved Aspect of the Monkey", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 132159 },
                [15] = { ["name"] = "Improved Revive Pet", ["tier"] = 2, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 132163 },
                [3] = { ["name"] = "Pathfinding", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 132242 },
                [2] = { ["name"] = "Improved Aspect of the Hawk", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136076 },
                [5] = { ["isExceptional"] = 1, ["name"] = "Bestial Wrath", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132127 },
                [4] = { ["name"] = "Improved Mend Pet", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 132179 },
                [7] = { ["name"] = "Spirit Bond", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 132121 },
                [6] = { ["isExceptional"] = 1, ["name"] = "Intimidation", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132111 },
                [14] = { ["name"] = "Focused Fire", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 132210 },
                [8] = { ["name"] = "Endurance Training", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136080 },
                [16] = { ["name"] = "Animal Handler", ["tier"] = 6, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 132158 },
                [17] = { ["name"] = "Ferocious Inspiration", ["tier"] = 7, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 132173 },
                [13] = { ["name"] = "Frenzy", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 134296 },
                [12] = { ["name"] = "Unleashed Fury", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 132091 },
                [11] = { ["name"] = "Thick Hide", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 134355 },
                [10] = { ["name"] = "Ferocity", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 134297 },
            },
            [2] = {
                [27] = { ["name"] = "Focused Aim", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 236179 },
                [26] = { ["isExceptional"] = 1, ["name"] = "Chimera Shot", ["tier"] = 11, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 236176 },
                [25] = { ["name"] = "Marked for Death", ["tier"] = 10, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 236173 },
                [24] = { ["name"] = "Improved Steady Shot", ["tier"] = 9, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 236182 },
                [23] = { ["name"] = "Wild Quiver", ["tier"] = 9, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 236204 },
                [22] = { ["name"] = "Rapid Recuperation", ["tier"] = 8, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 236201 },
                [21] = { ["name"] = "Piercing Shots", ["tier"] = 7, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 236198 },
                [20] = { ["name"] = "Improved Barrage", ["tier"] = 7, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 132330 },
                [19] = { ["name"] = "Rapid Killing", ["tier"] = 3, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 132205 },
                [18] = { ["name"] = "Go for the Throat", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 132174 },
                [9] = { ["name"] = "Mortal Shots", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 132271 },
                [1] = { ["name"] = "Improved Concussive Shot", ["tier"] = 1, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135860 },
                [15] = { ["name"] = "Careful Aim", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 132217 },
                [3] = { ["name"] = "Improved Hunter's Mark", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 132212 },
                [2] = { ["name"] = "Efficiency", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135865 },
                [5] = { ["isExceptional"] = 1, ["name"] = "Aimed Shot", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 135130 },
                [4] = { ["name"] = "Lethal Shots", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 132312 },
                [7] = { ["name"] = "Barrage", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 132330 },
                [6] = { ["name"] = "Improved Arcane Shot", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 132218 },
                [14] = { ["name"] = "Combat Experience", ["tier"] = 6, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 132168 },
                [8] = { ["name"] = "Improved Stings", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 132204 },
                [16] = { ["name"] = "Master Marksman", ["tier"] = 8, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 132177 },
                [17] = { ["isExceptional"] = 1, ["name"] = "Silencing Shot", ["tier"] = 9, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132323 },
                [13] = { ["name"] = "Ranged Weapon Specialization", ["tier"] = 6, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 135615 },
                [12] = { ["isExceptional"] = 1, ["name"] = "Trueshot Aura", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132329 },
                [11] = { ["isExceptional"] = 1, ["name"] = "Readiness", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132206 },
                [10] = { ["name"] = "Concussive Barrage", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135753 },
            },
            [3] = {
                [22] = { ["name"] = "Noxious Stings", ["tier"] = 8, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 236200 },
                [27] = { ["name"] = "Hunter vs. Wild", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 236180 },
                [26] = { ["isExceptional"] = 1, ["name"] = "Explosive Shot", ["tier"] = 11, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 236178 },
                [25] = { ["name"] = "Hunting Party", ["tier"] = 10, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 236181 },
                [24] = { ["name"] = "Sniper Training", ["tier"] = 9, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 236187 },
                [23] = { ["name"] = "Point of No Escape", ["tier"] = 9, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 236199 },
                [28] = { ["name"] = "T.N.T.", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 133713 },
                [21] = { ["name"] = "Hawk Eye", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 132327 },
                [20] = { ["isExceptional"] = 1, ["name"] = "Scatter Shot", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132153 },
                [19] = { ["name"] = "Master Tactician", ["tier"] = 8, ["id"] = 0, ["column"] = 1, ["maxRank"] = 5, ["texture"] = 132178 },
                [18] = { ["name"] = "Expose Weakness", ["tier"] = 7, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 132295 },
                [9] = { ["name"] = "Killer Instinct", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 135881 },
                [1] = { ["name"] = "Lightning Reflexes", ["tier"] = 6, ["id"] = 0, ["column"] = 1, ["maxRank"] = 5, ["texture"] = 136047 },
                [15] = { ["name"] = "Resourcefulness", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 132207 },
                [3] = { ["name"] = "Trap Mastery", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 132149 },
                [2] = { ["name"] = "Entrapment", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 136100 },
                [5] = { ["name"] = "Survival Tactics", ["tier"] = 3, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 132293 },
                [4] = { ["name"] = "Lock and Load", ["tier"] = 4, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 236185 },
                [7] = { ["name"] = "Deflection", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 132269 },
                [6] = { ["name"] = "Surefooted", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 132219 },
                [14] = { ["name"] = "Improved Tracking", ["tier"] = 1, ["id"] = 0, ["column"] = 1, ["maxRank"] = 5, ["texture"] = 236183 },
                [8] = { ["isExceptional"] = 1, ["name"] = "Counterattack", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 132336 },
                [16] = { ["name"] = "Survival Instincts", ["tier"] = 2, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 132214 },
                [17] = { ["name"] = "Thrill of the Hunt", ["tier"] = 7, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 132216 },
                [13] = { ["name"] = "Survivalist", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 5, ["texture"] = 136223 },
                [12] = { ["name"] = "Savage Strikes", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 132277 },
                [11] = { ["isExceptional"] = 1, ["name"] = "Wyvern Sting", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135125 },
                [10] = { ["isExceptional"] = 1, ["name"] = "Black Arrow", ["tier"] = 9, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136181 },
            },
        },
        ["WARRIOR"] = {
            [1] = {
                [31] = { ["name"] = "Juggernaut", ["tier"] = 8, ["id"] = 0, ["column"] = 1, ["maxRank"] = 1, ["texture"] = 132335 },
                [30] = { ["name"] = "Improved Slam", ["tier"] = 7, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 132340 },
                [21] = { ["name"] = "Second Wind", ["tier"] = 7, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 132175 },
                [22] = { ["name"] = "Blood Frenzy", ["tier"] = 9, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 132334 },
                [27] = { ["isExceptional"] = 1, ["name"] = "Bladestorm", ["tier"] = 11, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 236303 },
                [26] = { ["name"] = "Strength of Arms", ["tier"] = 7, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 132349 },
                [25] = { ["name"] = "Unrelenting Assault", ["tier"] = 8, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 236317 },
                [24] = { ["name"] = "Trauma", ["tier"] = 6, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 236305 },
                [23] = { ["name"] = "Improved Mortal Strike", ["tier"] = 8, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 132355 },
                [28] = { ["name"] = "Wrecking Crew", ["tier"] = 10, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 132364 },
                [29] = { ["name"] = "Taste for Blood", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 236276 },
                [20] = { ["name"] = "Sudden Death", ["tier"] = 9, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 132346 },
                [19] = { ["isExceptional"] = 1, ["name"] = "Endless Rage", ["tier"] = 9, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132344 },
                [18] = { ["name"] = "Impale", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 132312 },
                [9] = { ["name"] = "Deflection", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 132269 },
                [1] = { ["name"] = "Deep Wounds", ["tier"] = 3, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 132090 },
                [15] = { ["name"] = "Two-Handed Weapon Specialization", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 132400 },
                [3] = { ["name"] = "Improved Heroic Strike", ["tier"] = 1, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 132282 },
                [2] = { ["name"] = "Sword Specialization", ["tier"] = 5, ["id"] = 0, ["column"] = 4, ["maxRank"] = 5, ["texture"] = 135328 },
                [5] = { ["name"] = "Improved Charge", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 132337 },
                [4] = { ["name"] = "Mace Specialization", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 133476 },
                [7] = { ["name"] = "Tactical Mastery", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 136031 },
                [6] = { ["name"] = "Improved Rend", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 132155 },
                [14] = { ["isExceptional"] = 1, ["name"] = "Mortal Strike", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132355 },
                [8] = { ["name"] = "Improved Hamstring", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 132316 },
                [16] = { ["isExceptional"] = 1, ["name"] = "Anger Management", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135881 },
                [17] = { ["name"] = "Iron Will", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 135995 },
                [13] = { ["name"] = "Weapon Mastery", ["tier"] = 6, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 132367 },
                [12] = { ["isExceptional"] = 1, ["name"] = "Sweeping Strikes", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132306 },
                [11] = { ["name"] = "Poleaxe Specialization", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 5, ["texture"] = 132397 },
                [10] = { ["name"] = "Improved Overpower", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135275 },
            },
            [2] = {
                [27] = { ["name"] = "Armored to the Teeth", ["tier"] = 1, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 135053 },
                [26] = { ["name"] = "Unending Fury", ["tier"] = 10, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 236310 },
                [25] = { ["isExceptional"] = 1, ["name"] = "Heroic Fury", ["tier"] = 9, ["id"] = 0, ["column"] = 1, ["maxRank"] = 1, ["texture"] = 236171 },
                [24] = { ["name"] = "Titan's Grip", ["tier"] = 11, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 236316 },
                [23] = { ["name"] = "Bloodsurge", ["tier"] = 9, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 236306 },
                [22] = { ["name"] = "Furious Attacks", ["tier"] = 8, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 236308 },
                [21] = { ["name"] = "Intensify Rage", ["tier"] = 7, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 132344 },
                [20] = { ["isExceptional"] = 1, ["name"] = "Rampage", ["tier"] = 9, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132352 },
                [19] = { ["name"] = "Improved Berserker Stance", ["tier"] = 8, ["id"] = 0, ["column"] = 4, ["maxRank"] = 5, ["texture"] = 132275 },
                [18] = { ["name"] = "Precision", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 132222 },
                [9] = { ["isExceptional"] = 1, ["name"] = "Death Wish", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136146 },
                [1] = { ["name"] = "Commanding Presence", ["tier"] = 3, ["id"] = 0, ["column"] = 4, ["maxRank"] = 5, ["texture"] = 136035 },
                [15] = { ["name"] = "Improved Intercept", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 132307 },
                [3] = { ["name"] = "Flurry", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 132152 },
                [2] = { ["name"] = "Enrage", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136224 },
                [5] = { ["name"] = "Booming Voice", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 136075 },
                [4] = { ["name"] = "Cruelty", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 132292 },
                [7] = { ["isExceptional"] = 1, ["name"] = "Piercing Howl", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136147 },
                [6] = { ["name"] = "Unbridled Wrath", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136097 },
                [14] = { ["name"] = "Improved Execute", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 135358 },
                [8] = { ["name"] = "Improved Demoralizing Shout", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 132366 },
                [16] = { ["name"] = "Dual Wield Specialization", ["tier"] = 4, ["id"] = 0, ["column"] = 1, ["maxRank"] = 5, ["texture"] = 132147 },
                [17] = { ["name"] = "Improved Whirlwind", ["tier"] = 7, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 132369 },
                [13] = { ["name"] = "Improved Berserker Rage", ["tier"] = 6, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136009 },
                [12] = { ["name"] = "Blood Craze", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 136218 },
                [11] = { ["isExceptional"] = 1, ["name"] = "Bloodthirst", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136012 },
                [10] = { ["name"] = "Improved Cleave", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 132338 },
            },
            [3] = {
                [27] = { ["name"] = "Improved Spell Reflection", ["tier"] = 4, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 132361 },
                [26] = { ["name"] = "Damage Shield", ["tier"] = 10, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 134976 },
                [25] = { ["name"] = "Warbringer", ["tier"] = 9, ["id"] = 0, ["column"] = 1, ["maxRank"] = 1, ["texture"] = 236319 },
                [24] = { ["name"] = "Critical Block", ["tier"] = 9, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 236307 },
                [23] = { ["isExceptional"] = 1, ["name"] = "Shockwave", ["tier"] = 11, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 236312 },
                [22] = { ["name"] = "Sword and Board", ["tier"] = 10, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 236315 },
                [21] = { ["name"] = "Safeguard", ["tier"] = 8, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 236311 },
                [20] = { ["isExceptional"] = 1, ["name"] = "Devastate", ["tier"] = 9, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135291 },
                [19] = { ["name"] = "Focused Rage", ["tier"] = 7, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 132345 },
                [18] = { ["name"] = "Shield Mastery", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 132360 },
                [9] = { ["name"] = "Gag Order", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 132357 },
                [1] = { ["name"] = "Anticipation", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136056 },
                [15] = { ["name"] = "Shield Specialization", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 134952 },
                [3] = { ["name"] = "Improved Thunder Clap", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 132326 },
                [2] = { ["name"] = "Toughness", ["tier"] = 3, ["id"] = 0, ["column"] = 4, ["maxRank"] = 5, ["texture"] = 135892 },
                [5] = { ["name"] = "Incite", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 236309 },
                [4] = { ["name"] = "Improved Bloodrage", ["tier"] = 1, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 132277 },
                [7] = { ["name"] = "Improved Revenge", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 132353 },
                [6] = { ["name"] = "Puncture", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 132363 },
                [14] = { ["name"] = "One-Handed Weapon Specialization", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135321 },
                [8] = { ["isExceptional"] = 1, ["name"] = "Vigilance", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 236318 },
                [16] = { ["name"] = "Improved Defensive Stance", ["tier"] = 7, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 132341 },
                [17] = { ["name"] = "Vitality", ["tier"] = 8, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 133123 },
                [13] = { ["isExceptional"] = 1, ["name"] = "Last Stand", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 1, ["texture"] = 135871 },
                [12] = { ["isExceptional"] = 1, ["name"] = "Concussion Blow", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132325 },
                [11] = { ["name"] = "Improved Disarm", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 132343 },
                [10] = { ["name"] = "Improved Disciplines", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 132362 },
            },
        },
        ["PALADIN"] = {
            [1] = {
                [26] = { ["name"] = "Judgements of the Pure", ["tier"] = 9, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 236256 },
                [25] = { ["name"] = "Blessed Hands", ["tier"] = 4, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 236248 },
                [24] = { ["name"] = "Infusion of Light", ["tier"] = 10, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 236254 },
                [23] = { ["isExceptional"] = 1, ["name"] = "Beacon of Light", ["tier"] = 11, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 236247 },
                [22] = { ["name"] = "Enlightened Judgements", ["tier"] = 10, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 236251 },
                [21] = { ["name"] = "Sacred Cleansing", ["tier"] = 8, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 236261 },
                [20] = { ["isExceptional"] = 1, ["name"] = "Divine Illumination", ["tier"] = 9, ["id"] = 0, ["column"] = 1, ["maxRank"] = 1, ["texture"] = 135895 },
                [19] = { ["name"] = "Holy Guidance", ["tier"] = 8, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135921 },
                [18] = { ["name"] = "Light's Grace", ["tier"] = 7, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 135931 },
                [9] = { ["name"] = "Illumination", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 135913 },
                [1] = { ["name"] = "Spiritual Focus", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 135736 },
                [15] = { ["name"] = "Pure of Heart", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135948 },
                [3] = { ["isExceptional"] = 1, ["name"] = "Aura Mastery", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 1, ["texture"] = 135872 },
                [2] = { ["isExceptional"] = 1, ["name"] = "Divine Favor", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135915 },
                [5] = { ["name"] = "Healing Light", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 135920 },
                [4] = { ["name"] = "Improved Lay on Hands", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 135928 },
                [7] = { ["name"] = "Divine Intellect", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136090 },
                [6] = { ["name"] = "Improved Blessing of Wisdom", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 135970 },
                [14] = { ["name"] = "Unyielding Faith", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 135984 },
                [8] = { ["name"] = "Improved Concentration Aura", ["tier"] = 4, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 135933 },
                [16] = { ["name"] = "Purifying Power", ["tier"] = 6, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135950 },
                [17] = { ["name"] = "Blessed Life", ["tier"] = 7, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 135876 },
                [13] = { ["name"] = "Holy Power", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135938 },
                [12] = { ["isExceptional"] = 1, ["name"] = "Holy Shock", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135972 },
                [11] = { ["name"] = "Sanctified Light", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 135917 },
                [10] = { ["name"] = "Seals of the Pure", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 132325 },
            },
            [2] = {
                [26] = { ["name"] = "Spiritual Attunement", ["tier"] = 7, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135958 },
                [25] = { ["name"] = "Divine Guardian", ["tier"] = 4, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 253400 },
                [24] = { ["isExceptional"] = 1, ["name"] = "Divine Sacrifice", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 1, ["texture"] = 253400 },
                [23] = { ["name"] = "Shield of the Templar", ["tier"] = 10, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 236264 },
                [22] = { ["name"] = "Judgements of the Just", ["tier"] = 10, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 236259 },
                [21] = { ["isExceptional"] = 1, ["name"] = "Hammer of the Righteous", ["tier"] = 11, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 236253 },
                [20] = { ["name"] = "Touched by the Light", ["tier"] = 9, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 236267 },
                [19] = { ["name"] = "Guarded by the Light", ["tier"] = 9, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 236252 },
                [18] = { ["name"] = "Divine Strength", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 132154 },
                [9] = { ["name"] = "Divinity", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 135883 },
                [1] = { ["name"] = "Redoubt", ["tier"] = 8, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 132110 },
                [15] = { ["name"] = "Ardent Defender", ["tier"] = 7, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 135870 },
                [3] = { ["name"] = "Toughness", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135892 },
                [2] = { ["name"] = "Improved Devotion Aura", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 135893 },
                [5] = { ["name"] = "Reckoning", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135882 },
                [4] = { ["name"] = "Guardian's Favor", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 135964 },
                [7] = { ["isExceptional"] = 1, ["name"] = "Holy Shield", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135880 },
                [6] = { ["name"] = "One-Handed Weapon Specialization", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 135321 },
                [14] = { ["name"] = "Sacred Duty", ["tier"] = 6, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135896 },
                [8] = { ["isExceptional"] = 1, ["name"] = "Blessing of Sanctuary", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136051 },
                [16] = { ["name"] = "Combat Expertise", ["tier"] = 8, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 135986 },
                [17] = { ["isExceptional"] = 1, ["name"] = "Avenger's Shield", ["tier"] = 9, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135874 },
                [13] = { ["name"] = "Stoicism", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 135978 },
                [12] = { ["name"] = "Anticipation", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135994 },
                [11] = { ["name"] = "Improved Hammer of Justice", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 135963 },
                [10] = { ["name"] = "Improved Righteous Fury", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 135962 },
            },
            [3] = {
                [26] = { ["name"] = "Sheath of Light", ["tier"] = 9, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 236263 },
                [25] = { ["name"] = "The Art of War", ["tier"] = 7, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 236246 },
                [24] = { ["isExceptional"] = 1, ["name"] = "Divine Storm", ["tier"] = 11, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 236250 },
                [23] = { ["name"] = "Righteous Vengeance", ["tier"] = 10, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 236260 },
                [22] = { ["name"] = "Swift Retribution", ["tier"] = 9, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 236266 },
                [21] = { ["name"] = "Sanctified Wrath", ["tier"] = 8, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 236262 },
                [20] = { ["isExceptional"] = 1, ["name"] = "Crusader Strike", ["tier"] = 9, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135891 },
                [19] = { ["name"] = "Sanctity of Battle", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 135924 },
                [18] = { ["name"] = "Fanaticism", ["tier"] = 8, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 135905 },
                [9] = { ["isExceptional"] = 1, ["name"] = "Seal of Command", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 132347 },
                [1] = { ["name"] = "Improved Blessing of Might", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 135906 },
                [15] = { ["name"] = "Sanctified Retribution", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 135934 },
                [3] = { ["name"] = "Deflection", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 132269 },
                [2] = { ["name"] = "Vengeance", ["tier"] = 6, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 132275 },
                [5] = { ["name"] = "Two-Handed Weapon Specialization", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 133041 },
                [4] = { ["name"] = "Benediction", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135863 },
                [7] = { ["isExceptional"] = 1, ["name"] = "Repentance", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135942 },
                [6] = { ["name"] = "Conviction", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 135957 },
                [14] = { ["name"] = "Crusade", ["tier"] = 4, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 135889 },
                [8] = { ["name"] = "Heart of the Crusader", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 135924 },
                [16] = { ["name"] = "Divine Purpose", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 135897 },
                [17] = { ["name"] = "Judgements of the Wise", ["tier"] = 7, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 236257 },
                [13] = { ["name"] = "Pursuit of Justice", ["tier"] = 3, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 135937 },
                [12] = { ["name"] = "Vindication", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135985 },
                [11] = { ["name"] = "Eye for an Eye", ["tier"] = 4, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135904 },
                [10] = { ["name"] = "Improved Judgements", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135959 },
            },
        },
        ["MAGE"] = {
            [1] = {
                [10] = { ["isExceptional"] = 1, ["name"] = "Presence of Mind", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136031 },
                [11] = { ["isExceptional"] = 1, ["name"] = "Arcane Power", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136048 },
                [12] = { ["name"] = "Improved Counterspell", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 135856 },
                [13] = { ["name"] = "Arcane Instability", ["tier"] = 6, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 136222 },
                [17] = { ["name"] = "Arcane Potency", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 135732 },
                [16] = { ["name"] = "Improved Blink", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135736 },
                [8] = { ["name"] = "Arcane Shielding", ["tier"] = 4, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136153 },
                [14] = { ["name"] = "Arcane Meditation", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 136208 },
                [28] = { ["name"] = "Missile Barrage", ["tier"] = 9, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 236221 },
                [29] = { ["isExceptional"] = 1, ["name"] = "Focus Magic", ["tier"] = 3, ["id"] = 0, ["column"] = 4, ["maxRank"] = 1, ["texture"] = 135754 },
                [21] = { ["isExceptional"] = 1, ["name"] = "Slow", ["tier"] = 9, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136091 },
                [9] = { ["name"] = "Arcane Fortitude", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 135733 },
                [4] = { ["name"] = "Arcane Mind", ["tier"] = 5, ["id"] = 0, ["column"] = 4, ["maxRank"] = 5, ["texture"] = 136129 },
                [5] = { ["name"] = "Arcane Stability", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136096 },
                [1] = { ["name"] = "Arcane Subtlety", ["tier"] = 1, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135894 },
                [15] = { ["name"] = "Magic Absorption", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 136011 },
                [3] = { ["name"] = "Arcane Focus", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 135892 },
                [2] = { ["name"] = "Arcane Concentration", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136170 },
                [19] = { ["name"] = "Arcane Empowerment", ["tier"] = 7, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 136096 },
                [18] = { ["name"] = "Prismatic Cloak", ["tier"] = 6, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 135752 },
                [7] = { ["name"] = "Magic Attunement", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136006 },
                [6] = { ["name"] = "Spell Impact", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 136116 },
                [25] = { ["name"] = "Student of the Mind", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 236225 },
                [24] = { ["name"] = "Incanter's Absorption", ["tier"] = 7, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 236219 },
                [27] = { ["isExceptional"] = 1, ["name"] = "Arcane Barrage", ["tier"] = 11, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 236205 },
                [26] = { ["name"] = "Netherwind Presence", ["tier"] = 10, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 236222 },
                [20] = { ["name"] = "Mind Mastery", ["tier"] = 8, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135740 },
                [30] = { ["name"] = "Torment the Weak", ["tier"] = 4, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 236226 },
                [22] = { ["name"] = "Spell Power", ["tier"] = 10, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 135734 },
                [23] = { ["name"] = "Arcane Flows", ["tier"] = 8, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 236223 },
            },
            [2] = {
                [10] = { ["isExceptional"] = 1, ["name"] = "Blast Wave", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 135903 },
                [11] = { ["name"] = "Critical Mass", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 136115 },
                [12] = { ["name"] = "Ignite", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 5, ["texture"] = 135818 },
                [13] = { ["name"] = "Fire Power", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135817 },
                [17] = { ["name"] = "Playing with Fire", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 135823 },
                [16] = { ["name"] = "Master of Elements", ["tier"] = 4, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 135820 },
                [28] = { ["name"] = "Burning Determination", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 135829 },
                [8] = { ["name"] = "Impact", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 135821 },
                [14] = { ["isExceptional"] = 1, ["name"] = "Combustion", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135824 },
                [9] = { ["name"] = "World in Flames", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 236228 },
                [15] = { ["name"] = "Incineration", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 135813 },
                [4] = { ["name"] = "Improved Fireball", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135812 },
                [1] = { ["name"] = "Burning Soul", ["tier"] = 3, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 135805 },
                [5] = { ["name"] = "Improved Fire Blast", ["tier"] = 1, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135807 },
                [3] = { ["name"] = "Improved Scorch", ["tier"] = 4, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 135827 },
                [2] = { ["name"] = "Molten Shields", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 135806 },
                [19] = { ["name"] = "Molten Fury", ["tier"] = 7, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 135822 },
                [18] = { ["name"] = "Blazing Speed", ["tier"] = 6, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135788 },
                [7] = { ["isExceptional"] = 1, ["name"] = "Pyroblast", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 135808 },
                [6] = { ["name"] = "Flame Throwing", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135815 },
                [25] = { ["name"] = "Hot Streak", ["tier"] = 9, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 236218 },
                [24] = { ["name"] = "Firestarter", ["tier"] = 9, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 236216 },
                [27] = { ["isExceptional"] = 1, ["name"] = "Living Bomb", ["tier"] = 11, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 236220 },
                [26] = { ["name"] = "Burnout", ["tier"] = 10, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 236207 },
                [20] = { ["name"] = "Pyromaniac", ["tier"] = 7, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 135789 },
                [21] = { ["name"] = "Empowered Fire", ["tier"] = 8, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 135812 },
                [22] = { ["isExceptional"] = 1, ["name"] = "Dragon's Breath", ["tier"] = 9, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 134153 },
                [23] = { ["name"] = "Fiery Payback", ["tier"] = 8, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 236215 },
            },
            [3] = {
                [10] = { ["name"] = "Winter's Chill", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 135836 },
                [11] = { ["isExceptional"] = 1, ["name"] = "Icy Veins", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135838 },
                [12] = { ["name"] = "Frost Warding", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 135850 },
                [13] = { ["isExceptional"] = 1, ["name"] = "Ice Barrier", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135988 },
                [17] = { ["name"] = "Precision", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 135989 },
                [16] = { ["name"] = "Arctic Reach", ["tier"] = 4, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136141 },
                [28] = { ["name"] = "Shattered Barrier", ["tier"] = 7, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 236224 },
                [8] = { ["name"] = "Frost Channeling", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 135860 },
                [14] = { ["isExceptional"] = 1, ["name"] = "Cold Snap", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135865 },
                [9] = { ["name"] = "Shatter", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 135849 },
                [15] = { ["name"] = "Ice Shards", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 135855 },
                [4] = { ["name"] = "Ice Floes", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 135854 },
                [1] = { ["name"] = "Improved Frostbolt", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 135846 },
                [5] = { ["name"] = "Improved Blizzard", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 135857 },
                [3] = { ["name"] = "Piercing Ice", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 135845 },
                [2] = { ["name"] = "Frostbite", ["tier"] = 1, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 135842 },
                [19] = { ["name"] = "Cold as Ice", ["tier"] = 6, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 236209 },
                [18] = { ["name"] = "Frozen Core", ["tier"] = 5, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 135851 },
                [7] = { ["name"] = "Permafrost", ["tier"] = 2, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 135864 },
                [6] = { ["name"] = "Improved Cone of Cold", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 135852 },
                [25] = { ["name"] = "Enduring Winter", ["tier"] = 9, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 135862 },
                [24] = { ["name"] = "Brain Freeze", ["tier"] = 9, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 236206 },
                [27] = { ["isExceptional"] = 1, ["name"] = "Deep Freeze", ["tier"] = 11, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 236214 },
                [26] = { ["name"] = "Chilled to the Bone", ["tier"] = 10, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 236208 },
                [20] = { ["name"] = "Arctic Winds", ["tier"] = 7, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135833 },
                [21] = { ["name"] = "Empowered Frostbolt", ["tier"] = 8, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 135846 },
                [22] = { ["isExceptional"] = 1, ["name"] = "Summon Water Elemental", ["tier"] = 9, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135862 },
                [23] = { ["name"] = "Fingers of Frost", ["tier"] = 8, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 236227 },
            },
        },
        ["PRIEST"] = {
            [1] = {
                [22] = { ["name"] = "Divine Aegis", ["tier"] = 9, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 237539 },
                [27] = { ["name"] = "Renewed Hope", ["tier"] = 8, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135923 },
                [26] = { ["name"] = "Grace", ["tier"] = 9, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 237543 },
                [25] = { ["name"] = "Twin Disciplines", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135969 },
                [24] = { ["isExceptional"] = 1, ["name"] = "Penance", ["tier"] = 11, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 237545 },
                [23] = { ["name"] = "Rapture", ["tier"] = 8, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 237548 },
                [28] = { ["name"] = "Reflective Shield", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135940 },
                [21] = { ["name"] = "Aspiration", ["tier"] = 8, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 237537 },
                [20] = { ["name"] = "Focused Will", ["tier"] = 7, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 135737 },
                [19] = { ["isExceptional"] = 1, ["name"] = "Pain Suppression", ["tier"] = 9, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135936 },
                [18] = { ["name"] = "Improved Flash Heal", ["tier"] = 7, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 135886 },
                [9] = { ["isExceptional"] = 1, ["name"] = "Inner Focus", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135863 },
                [1] = { ["name"] = "Martyrdom", ["tier"] = 2, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 136107 },
                [15] = { ["name"] = "Absolution", ["tier"] = 4, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 135868 },
                [3] = { ["name"] = "Mental Agility", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 132156 },
                [2] = { ["isExceptional"] = 1, ["name"] = "Power Infusion", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135939 },
                [5] = { ["name"] = "Improved Power Word: Shield", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 135940 },
                [4] = { ["name"] = "Unbreakable Will", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 135995 },
                [7] = { ["name"] = "Improved Inner Fire", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 135926 },
                [6] = { ["name"] = "Improved Power Word: Fortitude", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 135987 },
                [14] = { ["name"] = "Borrowed Time", ["tier"] = 10, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 237538 },
                [8] = { ["name"] = "Meditation", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 136090 },
                [16] = { ["name"] = "Focused Power", ["tier"] = 6, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136158 },
                [17] = { ["name"] = "Enlightenment", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 135740 },
                [13] = { ["name"] = "Mental Strength", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136031 },
                [12] = { ["name"] = "Silent Resolve", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 136053 },
                [11] = { ["isExceptional"] = 1, ["name"] = "Soul Warding", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 135948 },
                [10] = { ["name"] = "Improved Mana Burn", ["tier"] = 4, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 136170 },
            },
            [2] = {
                [27] = { ["name"] = "Body and Soul", ["tier"] = 8, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135982 },
                [26] = { ["isExceptional"] = 1, ["name"] = "Guardian Spirit", ["tier"] = 11, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 237542 },
                [25] = { ["name"] = "Divine Providence", ["tier"] = 10, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 237541 },
                [24] = { ["name"] = "Serendipity", ["tier"] = 8, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 237549 },
                [23] = { ["name"] = "Test of Faith", ["tier"] = 9, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 237550 },
                [22] = { ["name"] = "Empowered Renew", ["tier"] = 9, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 236254 },
                [21] = { ["isExceptional"] = 1, ["name"] = "Circle of Healing", ["tier"] = 9, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135887 },
                [20] = { ["name"] = "Holy Concentration", ["tier"] = 7, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 135905 },
                [19] = { ["name"] = "Empowered Healing", ["tier"] = 8, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 135913 },
                [18] = { ["name"] = "Surge of Light", ["tier"] = 6, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135981 },
                [9] = { ["name"] = "Spell Warding", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 135976 },
                [1] = { ["name"] = "Inspiration", ["tier"] = 3, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 135928 },
                [15] = { ["name"] = "Blessed Recovery", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 135877 },
                [3] = { ["name"] = "Spiritual Guidance", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135977 },
                [2] = { ["name"] = "Holy Specialization", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135967 },
                [5] = { ["name"] = "Spiritual Healing", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136057 },
                [4] = { ["name"] = "Searing Light", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 135973 },
                [7] = { ["name"] = "Improved Healing", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 135916 },
                [6] = { ["name"] = "Improved Renew", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 135953 },
                [14] = { ["name"] = "Holy Reach", ["tier"] = 4, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135949 },
                [8] = { ["name"] = "Healing Focus", ["tier"] = 1, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135918 },
                [16] = { ["isExceptional"] = 1, ["name"] = "Lightwell", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135980 },
                [17] = { ["name"] = "Blessed Resilience", ["tier"] = 7, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 135878 },
                [13] = { ["isExceptional"] = 1, ["name"] = "Spirit of Redemption", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132864 },
                [12] = { ["name"] = "Divine Fury", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135971 },
                [11] = { ["isExceptional"] = 1, ["name"] = "Desperate Prayer", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 1, ["texture"] = 135954 },
                [10] = { ["name"] = "Healing Prayers", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135943 },
            },
            [3] = {
                [27] = { ["name"] = "Improved Devouring Plague", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 252996 },
                [26] = { ["name"] = "Improved Spirit Tap", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 136188 },
                [25] = { ["isExceptional"] = 1, ["name"] = "Dispersion", ["tier"] = 11, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 237563 },
                [24] = { ["name"] = "Pain and Suffering", ["tier"] = 9, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 237567 },
                [23] = { ["isExceptional"] = 1, ["name"] = "Psychic Horror", ["tier"] = 9, ["id"] = 0, ["column"] = 1, ["maxRank"] = 1, ["texture"] = 237568 },
                [22] = { ["name"] = "Twisted Faith", ["tier"] = 10, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 237566 },
                [21] = { ["name"] = "Improved Shadowform", ["tier"] = 8, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136221 },
                [20] = { ["name"] = "Misery", ["tier"] = 8, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 136176 },
                [19] = { ["name"] = "Mind Melt", ["tier"] = 6, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 237569 },
                [18] = { ["isExceptional"] = 1, ["name"] = "Vampiric Touch", ["tier"] = 9, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135978 },
                [9] = { ["isExceptional"] = 1, ["name"] = "Vampiric Embrace", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136230 },
                [1] = { ["name"] = "Shadow Weaving", ["tier"] = 4, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 136123 },
                [15] = { ["name"] = "Improved Vampiric Embrace", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 136165 },
                [3] = { ["name"] = "Shadow Focus", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 136126 },
                [2] = { ["name"] = "Darkness", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136223 },
                [5] = { ["name"] = "Shadow Affinity", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 136205 },
                [4] = { ["name"] = "Spirit Tap", ["tier"] = 1, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 136188 },
                [7] = { ["name"] = "Improved Shadow Word: Pain", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 136207 },
                [6] = { ["name"] = "Improved Mind Blast", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136224 },
                [14] = { ["name"] = "Shadow Reach", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 136130 },
                [8] = { ["name"] = "Veiled Shadows", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 135994 },
                [16] = { ["name"] = "Focused Mind", ["tier"] = 5, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 136035 },
                [17] = { ["name"] = "Shadow Power", ["tier"] = 7, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136204 },
                [13] = { ["name"] = "Improved Psychic Scream", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136184 },
                [12] = { ["isExceptional"] = 1, ["name"] = "Silence", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 1, ["texture"] = 136164 },
                [11] = { ["isExceptional"] = 1, ["name"] = "Shadowform", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136200 },
                [10] = { ["isExceptional"] = 1, ["name"] = "Mind Flay", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 136208 },
            },
        },
        ["WARLOCK"] = {
            [1] = {
                [22] = { ["name"] = "Improved Felhunter", ["tier"] = 6, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136217 },
                [27] = { ["name"] = "Improved Fear", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136183 },
                [26] = { ["isExceptional"] = 1, ["name"] = "Haunt", ["tier"] = 11, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 236298 },
                [25] = { ["name"] = "Eradication", ["tier"] = 7, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 236295 },
                [24] = { ["name"] = "Everlasting Affliction", ["tier"] = 10, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 236296 },
                [23] = { ["name"] = "Death's Embrace", ["tier"] = 9, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 237557 },
                [28] = { ["name"] = "Pandemic", ["tier"] = 9, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 136227 },
                [21] = { ["name"] = "Empowered Corruption", ["tier"] = 4, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 136118 },
                [20] = { ["name"] = "Shadow Embrace", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 5, ["texture"] = 136198 },
                [19] = { ["isExceptional"] = 1, ["name"] = "Unstable Affliction", ["tier"] = 9, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136228 },
                [18] = { ["name"] = "Contagion", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136180 },
                [9] = { ["isExceptional"] = 1, ["name"] = "Dark Pact", ["tier"] = 7, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 136141 },
                [1] = { ["name"] = "Fel Concentration", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 136157 },
                [15] = { ["name"] = "Improved Curse of Agony", ["tier"] = 1, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136139 },
                [3] = { ["name"] = "Improved Corruption", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136118 },
                [2] = { ["name"] = "Nightfall", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 136223 },
                [5] = { ["name"] = "Suppression", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 136230 },
                [4] = { ["name"] = "Soul Siphon", ["tier"] = 2, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 136169 },
                [7] = { ["name"] = "Improved Life Tap", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 136126 },
                [6] = { ["name"] = "Improved Curse of Weakness", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136138 },
                [14] = { ["name"] = "Improved Drain Soul", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 136163 },
                [8] = { ["name"] = "Grim Reach", ["tier"] = 4, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136127 },
                [16] = { ["name"] = "Malediction", ["tier"] = 8, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 136137 },
                [17] = { ["name"] = "Improved Howl of Terror", ["tier"] = 8, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136147 },
                [13] = { ["isExceptional"] = 1, ["name"] = "Curse of Exhaustion", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 136162 },
                [12] = { ["isExceptional"] = 1, ["name"] = "Amplify Curse", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 136132 },
                [11] = { ["name"] = "Shadow Mastery", ["tier"] = 6, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136195 },
                [10] = { ["isExceptional"] = 1, ["name"] = "Siphon Life", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136188 },
            },
            [2] = {
                [27] = { ["name"] = "Decimation", ["tier"] = 8, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 135808 },
                [26] = { ["isExceptional"] = 1, ["name"] = "Metamorphosis", ["tier"] = 11, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 237558 },
                [25] = { ["name"] = "Demonic Pact", ["tier"] = 10, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 237562 },
                [24] = { ["name"] = "Nemesis", ["tier"] = 9, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 237561 },
                [23] = { ["name"] = "Fel Synergy", ["tier"] = 1, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 237564 },
                [22] = { ["name"] = "Improved Demonic Tactics", ["tier"] = 9, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 236299 },
                [21] = { ["isExceptional"] = 1, ["name"] = "Demonic Empowerment", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 236292 },
                [20] = { ["name"] = "Demonic Resilience", ["tier"] = 7, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 136149 },
                [19] = { ["name"] = "Demonic Tactics", ["tier"] = 8, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136150 },
                [18] = { ["isExceptional"] = 1, ["name"] = "Summon Felguard", ["tier"] = 9, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136216 },
                [9] = { ["name"] = "Improved Sayaad", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 136220 },
                [1] = { ["name"] = "Improved Healthstone", ["tier"] = 1, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135230 },
                [15] = { ["isExceptional"] = 1, ["name"] = "Soul Link", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136160 },
                [3] = { ["name"] = "Demonic Embrace", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 136172 },
                [2] = { ["name"] = "Improved Imp", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 136218 },
                [5] = { ["name"] = "Demonic Brutality", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 136221 },
                [4] = { ["name"] = "Improved Health Funnel", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136168 },
                [7] = { ["name"] = "Master Summoner", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 136164 },
                [6] = { ["isExceptional"] = 1, ["name"] = "Fel Domination", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 136082 },
                [14] = { ["isExceptional"] = 1, ["name"] = "Mana Feed", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 1, ["texture"] = 136171 },
                [8] = { ["name"] = "Fel Vitality", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 135932 },
                [16] = { ["name"] = "Molten Core", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 236301 },
                [17] = { ["name"] = "Demonic Aegis", ["tier"] = 3, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 136185 },
                [13] = { ["name"] = "Demonic Knowledge", ["tier"] = 7, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 136165 },
                [12] = { ["name"] = "Unholy Power", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136206 },
                [11] = { ["name"] = "Master Conjuror", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 132386 },
                [10] = { ["name"] = "Master Demonologist", ["tier"] = 6, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136203 },
            },
            [3] = {
                [26] = { ["name"] = "Empowered Imp", ["tier"] = 9, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 236294 },
                [25] = { ["isExceptional"] = 1, ["name"] = "Chaos Bolt", ["tier"] = 11, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 236291 },
                [24] = { ["name"] = "Fire and Brimstone", ["tier"] = 10, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 236297 },
                [23] = { ["name"] = "Improved Soul Leech", ["tier"] = 8, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 236300 },
                [22] = { ["name"] = "Backdraft", ["tier"] = 9, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 236290 },
                [21] = { ["name"] = "Molten Skin", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 132221 },
                [20] = { ["name"] = "Backlash", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 135823 },
                [19] = { ["name"] = "Nether Protection", ["tier"] = 6, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 136178 },
                [18] = { ["name"] = "Soul Leech", ["tier"] = 7, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 136214 },
                [9] = { ["name"] = "Ruin", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136207 },
                [1] = { ["name"] = "Cataclysm", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 135831 },
                [15] = { ["name"] = "Pyroclasm", ["tier"] = 7, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 135830 },
                [3] = { ["name"] = "Improved Shadow Bolt", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136197 },
                [2] = { ["name"] = "Bane", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136146 },
                [5] = { ["isExceptional"] = 1, ["name"] = "Shadowburn", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136191 },
                [4] = { ["name"] = "Improved Immolate", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 135817 },
                [7] = { ["name"] = "Improved Searing Pain", ["tier"] = 4, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 135827 },
                [6] = { ["name"] = "Destructive Reach", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 136133 },
                [14] = { ["name"] = "Intensity", ["tier"] = 4, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135819 },
                [8] = { ["name"] = "Emberstorm", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135826 },
                [16] = { ["isExceptional"] = 1, ["name"] = "Shadowfury", ["tier"] = 9, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136201 },
                [17] = { ["name"] = "Shadow and Flame", ["tier"] = 8, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136196 },
                [13] = { ["name"] = "Demonic Power", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135809 },
                [12] = { ["name"] = "Aftermath", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135805 },
                [11] = { ["name"] = "Devastation", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 135813 },
                [10] = { ["isExceptional"] = 1, ["name"] = "Conflagrate", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135807 },
            },
        },
        ["ROGUE"] = {
            [1] = {
                [27] = { ["isExceptional"] = 1, ["name"] = "Hunger For Blood", ["tier"] = 11, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 236276 },
                [26] = { ["name"] = "Cut to the Chase", ["tier"] = 10, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 236269 },
                [25] = { ["name"] = "Focused Attacks", ["tier"] = 8, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 236274 },
                [24] = { ["name"] = "Blood Spatter", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 236268 },
                [23] = { ["name"] = "Turn the Tables", ["tier"] = 9, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 236284 },
                [22] = { ["name"] = "Deadly Brew", ["tier"] = 7, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 236270 },
                [21] = { ["name"] = "Quick Recovery", ["tier"] = 5, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 132301 },
                [20] = { ["name"] = "Deadened Nerves", ["tier"] = 7, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 132286 },
                [19] = { ["name"] = "Fleet Footed", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 132296 },
                [18] = { ["isExceptional"] = 1, ["name"] = "Mutilate", ["tier"] = 9, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132304 },
                [9] = { ["name"] = "Improved Expose Armor", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 132354 },
                [1] = { ["name"] = "Improved Poisons", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 132273 },
                [15] = { ["name"] = "Vile Poisons", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 132293 },
                [3] = { ["name"] = "Malice", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 132277 },
                [2] = { ["name"] = "Lethality", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 132109 },
                [5] = { ["name"] = "Ruthlessness", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 132122 },
                [4] = { ["name"] = "Remorseless Attacks", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 132151 },
                [7] = { ["name"] = "Improved Eviscerate", ["tier"] = 1, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 132292 },
                [6] = { ["name"] = "Murder", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 136147 },
                [14] = { ["name"] = "Vigor", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 1, ["texture"] = 136023 },
                [8] = { ["name"] = "Puncturing Wounds", ["tier"] = 2, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 132090 },
                [16] = { ["name"] = "Master Poisoner", ["tier"] = 9, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 132108 },
                [17] = { ["name"] = "Find Weakness", ["tier"] = 8, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 132295 },
                [13] = { ["name"] = "Seal Fate", ["tier"] = 6, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136130 },
                [12] = { ["isExceptional"] = 1, ["name"] = "Overkill", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132205 },
                [11] = { ["isExceptional"] = 1, ["name"] = "Cold Blood", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135988 },
                [10] = { ["name"] = "Improved Kidney Shot", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 132298 },
            },
            [2] = {
                [22] = { ["name"] = "Combat Potency", ["tier"] = 8, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135673 },
                [27] = { ["name"] = "Prey on the Weak", ["tier"] = 10, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 236278 },
                [26] = { ["name"] = "Savage Combat", ["tier"] = 9, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 132100 },
                [25] = { ["name"] = "Unfair Advantage", ["tier"] = 9, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 236285 },
                [24] = { ["name"] = "Throwing Specialization", ["tier"] = 8, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 236282 },
                [23] = { ["name"] = "Improved Slice and Dice", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 132306 },
                [28] = { ["isExceptional"] = 1, ["name"] = "Killing Spree", ["tier"] = 11, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 236277 },
                [21] = { ["isExceptional"] = 1, ["name"] = "Surprise Attacks", ["tier"] = 9, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132308 },
                [20] = { ["name"] = "Nerves of Steel", ["tier"] = 7, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 132300 },
                [19] = { ["name"] = "Blade Twisting", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 132283 },
                [18] = { ["name"] = "Vitality", ["tier"] = 7, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 132353 },
                [9] = { ["isExceptional"] = 1, ["name"] = "Adrenaline Rush", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136206 },
                [1] = { ["name"] = "Precision", ["tier"] = 2, ["id"] = 0, ["column"] = 4, ["maxRank"] = 5, ["texture"] = 132222 },
                [15] = { ["isExceptional"] = 1, ["name"] = "Riposte", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132336 },
                [3] = { ["name"] = "Mace Specialization", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 5, ["texture"] = 133476 },
                [2] = { ["name"] = "Close Quarters Combat", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135641 },
                [5] = { ["name"] = "Deflection", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 132269 },
                [4] = { ["name"] = "Lightning Reflexes", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 136047 },
                [7] = { ["name"] = "Improved Gouge", ["tier"] = 1, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 132155 },
                [6] = { ["name"] = "Improved Sinister Strike", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 136189 },
                [14] = { ["name"] = "Hack and Slash", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135328 },
                [8] = { ["name"] = "Endurance", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136205 },
                [16] = { ["name"] = "Aggression", ["tier"] = 4, ["id"] = 0, ["column"] = 4, ["maxRank"] = 5, ["texture"] = 132275 },
                [17] = { ["name"] = "Weapon Expertise", ["tier"] = 6, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 135882 },
                [13] = { ["isExceptional"] = 1, ["name"] = "Blade Flurry", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132350 },
                [12] = { ["name"] = "Improved Sprint", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 132307 },
                [11] = { ["name"] = "Dual Wield Specialization", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 132147 },
                [10] = { ["name"] = "Improved Kick", ["tier"] = 4, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 132219 },
            },
            [3] = {
                [22] = { ["name"] = "Cheat Death", ["tier"] = 7, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 132285 },
                [27] = { ["isExceptional"] = 1, ["name"] = "Shadow Dance", ["tier"] = 11, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 236279 },
                [26] = { ["name"] = "Slaughter from the Shadows", ["tier"] = 10, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 236280 },
                [25] = { ["name"] = "Filthy Tricks", ["tier"] = 9, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 236287 },
                [24] = { ["name"] = "Honor Among Thieves", ["tier"] = 9, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 236275 },
                [23] = { ["name"] = "Waylay", ["tier"] = 8, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 236286 },
                [28] = { ["name"] = "Relentless Strikes", ["tier"] = 1, ["id"] = 0, ["column"] = 1, ["maxRank"] = 5, ["texture"] = 132340 },
                [21] = { ["isExceptional"] = 1, ["name"] = "Shadowstep", ["tier"] = 9, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132303 },
                [20] = { ["name"] = "Master of Subtlety", ["tier"] = 6, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 132299 },
                [19] = { ["name"] = "Sinister Calling", ["tier"] = 8, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 132305 },
                [18] = { ["name"] = "Enveloping Shadows", ["tier"] = 7, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 132291 },
                [9] = { ["name"] = "Dirty Deeds", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 136220 },
                [1] = { ["name"] = "Master of Deception", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 136129 },
                [15] = { ["name"] = "Sleight of Hand", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 132294 },
                [3] = { ["name"] = "Initiative", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 136159 },
                [2] = { ["name"] = "Camouflage", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 132320 },
                [5] = { ["name"] = "Elusiveness", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135994 },
                [4] = { ["name"] = "Setup", ["tier"] = 4, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 136056 },
                [7] = { ["name"] = "Dirty Tricks", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 132310 },
                [6] = { ["name"] = "Opportunity", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 132366 },
                [14] = { ["name"] = "Serrated Blades", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 135315 },
                [8] = { ["name"] = "Improved Ambush", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 132282 },
                [16] = { ["name"] = "Heightened Senses", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 132089 },
                [17] = { ["name"] = "Deadliness", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135540 },
                [13] = { ["isExceptional"] = 1, ["name"] = "Hemorrhage", ["tier"] = 5, ["id"] = 0, ["column"] = 4, ["maxRank"] = 1, ["texture"] = 136168 },
                [12] = { ["isExceptional"] = 1, ["name"] = "Premeditation", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136183 },
                [11] = { ["isExceptional"] = 1, ["name"] = "Ghostly Strike", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136136 },
                [10] = { ["isExceptional"] = 1, ["name"] = "Preparation", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136121 },
            },
        },
        ["DRUID"] = {
            [1] = {
                [22] = { ["name"] = "Eclipse", ["tier"] = 9, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 236151 },
                [27] = { ["name"] = "Improved Insect Swarm", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 136045 },
                [26] = { ["name"] = "Genesis", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135730 },
                [25] = { ["name"] = "Earth and Moon", ["tier"] = 10, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 236150 },
                [24] = { ["isExceptional"] = 1, ["name"] = "Starfall", ["tier"] = 11, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 236168 },
                [23] = { ["name"] = "Gale Winds", ["tier"] = 9, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 236154 },
                [28] = { ["name"] = "Nature's Splendor", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 136060 },
                [21] = { ["isExceptional"] = 1, ["name"] = "Typhoon", ["tier"] = 9, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 236170 },
                [20] = { ["name"] = "Owlkin Frenzy", ["tier"] = 8, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 236163 },
                [19] = { ["name"] = "Improved Moonkin Form", ["tier"] = 7, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 236156 },
                [18] = { ["name"] = "Nature's Majesty", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 135138 },
                [9] = { ["name"] = "Moonfury", ["tier"] = 6, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 136057 },
                [1] = { ["name"] = "Starlight Wrath", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136006 },
                [15] = { ["name"] = "Improved Faerie Fire", ["tier"] = 7, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 136033 },
                [3] = { ["name"] = "Nature's Reach", ["tier"] = 3, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 136065 },
                [2] = { ["name"] = "Improved Moonfire", ["tier"] = 2, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 136096 },
                [5] = { ["name"] = "Moonglow", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 136087 },
                [4] = { ["name"] = "Brambles", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 136104 },
                [7] = { ["isExceptional"] = 1, ["name"] = "Insect Swarm", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136045 },
                [6] = { ["name"] = "Celestial Focus", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 135753 },
                [14] = { ["name"] = "Dreamstate", ["tier"] = 6, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 132123 },
                [8] = { ["name"] = "Nature's Grace", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 136062 },
                [16] = { ["name"] = "Wrath of Cenarius", ["tier"] = 8, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 132146 },
                [17] = { ["isExceptional"] = 1, ["name"] = "Force of Nature", ["tier"] = 9, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 132129 },
                [13] = { ["name"] = "Balance of Power", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 132113 },
                [12] = { ["name"] = "Lunar Guidance", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 132132 },
                [11] = { ["isExceptional"] = 1, ["name"] = "Moonkin Form", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136036 },
                [10] = { ["name"] = "Vengeance", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136075 },
            },
            [2] = {
                [30] = { ["name"] = "Primal Gore", ["tier"] = 10, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 132140 },
                [21] = { ["name"] = "Improved Leader of the Pack", ["tier"] = 7, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 136112 },
                [22] = { ["name"] = "Primal Precision", ["tier"] = 4, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 236165 },
                [27] = { ["isExceptional"] = 1, ["name"] = "Berserk", ["tier"] = 11, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 236149 },
                [26] = { ["name"] = "King of the Jungle", ["tier"] = 9, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 236159 },
                [25] = { ["name"] = "Improved Mangle", ["tier"] = 9, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 132135 },
                [24] = { ["name"] = "Infected Wounds", ["tier"] = 8, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 236158 },
                [23] = { ["name"] = "Rend and Tear", ["tier"] = 10, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 236164 },
                [28] = { ["name"] = "Protector of the Pack", ["tier"] = 8, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 132117 },
                [29] = { ["name"] = "Natural Reaction", ["tier"] = 6, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 132091 },
                [20] = { ["name"] = "Mangle", ["tier"] = 9, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132135 },
                [19] = { ["name"] = "Predatory Instincts", ["tier"] = 8, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 132138 },
                [18] = { ["name"] = "Survival of the Fittest", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 132126 },
                [9] = { ["name"] = "Predatory Strikes", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 132185 },
                [1] = { ["name"] = "Thick Hide", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 134355 },
                [15] = { ["isExceptional"] = 1, ["name"] = "Survival Instincts", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 236169 },
                [3] = { ["name"] = "Ferocity", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 132190 },
                [2] = { ["name"] = "Feral Aggression", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 132121 },
                [5] = { ["name"] = "Sharpened Claws", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 134297 },
                [4] = { ["name"] = "Brutal Impact", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 132114 },
                [7] = { ["name"] = "Primal Fury", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 132278 },
                [6] = { ["name"] = "Feral Instinct", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 132089 },
                [14] = { ["isExceptional"] = 1, ["name"] = "Leader of the Pack", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136112 },
                [8] = { ["name"] = "Shredding Attacks", ["tier"] = 4, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136231 },
                [16] = { ["name"] = "Nurturing Instinct", ["tier"] = 5, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 132130 },
                [17] = { ["name"] = "Primal Tenacity", ["tier"] = 7, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 132139 },
                [13] = { ["name"] = "Heart of the Wild", ["tier"] = 6, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 135879 },
                [12] = { ["name"] = "Feral Swiftness", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136095 },
                [11] = { ["name"] = "Savage Fury", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 132141 },
                [10] = { ["name"] = "Feral Charge", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 132183 },
            },
            [3] = {
                [27] = { ["name"] = "Improved Barkskin", ["tier"] = 10, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136097 },
                [26] = { ["name"] = "Improved Tree of Life", ["tier"] = 9, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 236157 },
                [25] = { ["name"] = "Revitalize", ["tier"] = 9, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 236166 },
                [24] = { ["name"] = "Living Seed", ["tier"] = 8, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 236155 },
                [23] = { ["isExceptional"] = 1, ["name"] = "Wild Growth", ["tier"] = 11, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 236153 },
                [22] = { ["name"] = "Gift of the Earthmother", ["tier"] = 10, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 236160 },
                [21] = { ["name"] = "Master Shapeshifter", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 236161 },
                [20] = { ["name"] = "Living Spirit", ["tier"] = 7, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 136037 },
                [19] = { ["isExceptional"] = 1, ["name"] = "Tree of Life", ["tier"] = 9, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132145 },
                [18] = { ["name"] = "Natural Perfection", ["tier"] = 7, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 132137 },
                [9] = { ["name"] = "Intensity", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 135863 },
                [1] = { ["name"] = "Improved Mark of the Wild", ["tier"] = 1, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136078 },
                [15] = { ["isExceptional"] = 1, ["name"] = "Swiftmend", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 134914 },
                [3] = { ["name"] = "Nature's Focus", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 136042 },
                [2] = { ["name"] = "Furor", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135881 },
                [5] = { ["name"] = "Nature's Bounty", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136085 },
                [4] = { ["name"] = "Naturalist", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 5, ["texture"] = 136041 },
                [7] = { ["name"] = "Omen of Clarity", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136017 },
                [6] = { ["name"] = "Natural Shapeshifter", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 136116 },
                [14] = { ["name"] = "Tranquil Spirit", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 135900 },
                [8] = { ["name"] = "Gift of Nature", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136074 },
                [16] = { ["name"] = "Empowered Touch", ["tier"] = 6, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 132125 },
                [17] = { ["name"] = "Empowered Rejuvenation", ["tier"] = 8, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 132124 },
                [13] = { ["name"] = "Improved Tranquility", ["tier"] = 5, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 136107 },
                [12] = { ["name"] = "Subtlety", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 132150 },
                [11] = { ["isExceptional"] = 1, ["name"] = "Nature's Swiftness", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 1, ["texture"] = 136076 },
                [10] = { ["name"] = "Improved Rejuvenation", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 136081 },
            },
        },
        ["DEATHKNIGHT"] = {
            [1] = {
                [22] = { ["name"] = "Spell Deflection", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 237531 },
                [27] = { ["name"] = "Two-Handed Weapon Specialization", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 135378 },
                [26] = { ["name"] = "Abomination's Might", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 236310 },
                [25] = { ["name"] = "Death Rune Mastery", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 135372 },
                [24] = { ["name"] = "Blood Gorged", ["tier"] = 10, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136080 },
                [23] = { ["isExceptional"] = 1, ["name"] = "Vampiric Blood", ["tier"] = 8, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 136168 },
                [28] = { ["name"] = "Improved Death Strike", ["tier"] = 8, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 237517 },
                [21] = { ["name"] = "Blade Barrier", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 132330 },
                [20] = { ["name"] = "Bloody Strikes", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 135772 },
                [19] = { ["isExceptional"] = 1, ["name"] = "Dancing Rune Weapon", ["tier"] = 11, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135277 },
                [18] = { ["name"] = "Bloodworms", ["tier"] = 7, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 136211 },
                [9] = { ["name"] = "Scent of Blood", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 132284 },
                [1] = { ["name"] = "Improved Blood Presence", ["tier"] = 7, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 135770 },
                [15] = { ["isExceptional"] = 1, ["name"] = "Heart Strike", ["tier"] = 9, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135675 },
                [3] = { ["name"] = "Butchery", ["tier"] = 1, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 132455 },
                [2] = { ["name"] = "Bladed Armor", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 5, ["texture"] = 135067 },
                [5] = { ["name"] = "Improved Rune Tap", ["tier"] = 4, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 237529 },
                [4] = { ["isExceptional"] = 1, ["name"] = "Rune Tap", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 1, ["texture"] = 237529 },
                [7] = { ["name"] = "Bloody Vengeance", ["tier"] = 6, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 132090 },
                [6] = { ["name"] = "Dark Conviction", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 237518 },
                [14] = { ["name"] = "Sudden Doom", ["tier"] = 8, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 136181 },
                [8] = { ["name"] = "Subversion", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 237533 },
                [16] = { ["name"] = "Might of Mograine", ["tier"] = 9, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 135771 },
                [17] = { ["name"] = "Will of the Necropolis", ["tier"] = 9, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 132094 },
                [13] = { ["isExceptional"] = 1, ["name"] = "Unholy Frenzy", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 237512 },
                [12] = { ["name"] = "Vendetta", ["tier"] = 4, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 237536 },
                [11] = { ["name"] = "Veteran of the Third War", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 136005 },
                [10] = { ["isExceptional"] = 1, ["name"] = "Mark of Blood", ["tier"] = 5, ["id"] = 0, ["column"] = 4, ["maxRank"] = 1, ["texture"] = 132205 },
            },
            [2] = {
                [21] = { ["name"] = "Guile of Gorefiend", ["tier"] = 9, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 132373 },
                [22] = { ["name"] = "Icy Talons", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 5, ["texture"] = 252994 },
                [27] = { ["name"] = "Improved Icy Talons", ["tier"] = 6, ["id"] = 0, ["column"] = 1, ["maxRank"] = 1, ["texture"] = 252994 },
                [26] = { ["isExceptional"] = 1, ["name"] = "Lichborne", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136187 },
                [25] = { ["name"] = "Blood of the North", ["tier"] = 8, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 135714 },
                [24] = { ["name"] = "Annihilation", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 135609 },
                [23] = { ["name"] = "Killing Machine", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 135305 },
                [28] = { ["name"] = "Chilblains", ["tier"] = 7, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 135864 },
                [29] = { ["name"] = "Threat of Thassarian", ["tier"] = 8, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 132148 },
                [20] = { ["name"] = "Icy Reach", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 135859 },
                [19] = { ["name"] = "Improved Icy Touch", ["tier"] = 1, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 237526 },
                [18] = { ["name"] = "Glacier Rot", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 136083 },
                [9] = { ["name"] = "Frigid Dreadplate", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 132734 },
                [1] = { ["name"] = "Toughness", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135892 },
                [15] = { ["name"] = "Runic Power Mastery", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 135728 },
                [3] = { ["name"] = "Black Ice", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136141 },
                [2] = { ["name"] = "Endless Winter", ["tier"] = 4, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 136223 },
                [5] = { ["isExceptional"] = 1, ["name"] = "Unbreakable Armor", ["tier"] = 8, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 132388 },
                [4] = { ["isExceptional"] = 1, ["name"] = "Frost Strike", ["tier"] = 9, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 237520 },
                [7] = { ["name"] = "Chill of the Grave", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 135849 },
                [6] = { ["isExceptional"] = 1, ["name"] = "Deathchill", ["tier"] = 5, ["id"] = 0, ["column"] = 4, ["maxRank"] = 1, ["texture"] = 136213 },
                [14] = { ["isExceptional"] = 1, ["name"] = "Hungering Cold", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135152 },
                [8] = { ["isExceptional"] = 1, ["name"] = "Howling Blast", ["tier"] = 11, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135833 },
                [16] = { ["name"] = "Nerves of Cold Steel", ["tier"] = 2, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 132147 },
                [17] = { ["name"] = "Improved Frost Presence", ["tier"] = 7, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 135773 },
                [13] = { ["name"] = "Tundra Stalker", ["tier"] = 10, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136107 },
                [12] = { ["name"] = "Acclimation", ["tier"] = 9, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 135791 },
                [11] = { ["name"] = "Merciless Combat", ["tier"] = 6, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 135294 },
                [10] = { ["name"] = "Rime", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 135840 },
            },
            [3] = {
                [31] = { ["name"] = "Desolation", ["tier"] = 7, ["id"] = 0, ["column"] = 1, ["maxRank"] = 5, ["texture"] = 136224 },
                [30] = { ["name"] = "Desecration", ["tier"] = 6, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136199 },
                [21] = { ["name"] = "On a Pale Horse", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 237534 },
                [22] = { ["name"] = "Ebon Plaguebringer", ["tier"] = 9, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 132095 },
                [27] = { ["name"] = "Anticipation", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136056 },
                [26] = { ["isExceptional"] = 1, ["name"] = "Scourge Strike", ["tier"] = 9, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 237530 },
                [25] = { ["isExceptional"] = 1, ["name"] = "Ghoul Frenzy", ["tier"] = 7, ["id"] = 0, ["column"] = 4, ["maxRank"] = 1, ["texture"] = 132152 },
                [24] = { ["name"] = "Vicious Strikes", ["tier"] = 1, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135774 },
                [23] = { ["name"] = "Necrosis", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 135695 },
                [28] = { ["isExceptional"] = 1, ["name"] = "Anti-Magic Zone", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 237510 },
                [29] = { ["name"] = "Night of the Dead", ["tier"] = 4, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 237511 },
                [20] = { ["name"] = "Rage of Rivendare", ["tier"] = 10, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 135564 },
                [19] = { ["name"] = "Unholy Command", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 237532 },
                [18] = { ["name"] = "Improved Unholy Presence", ["tier"] = 7, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 135775 },
                [9] = { ["isExceptional"] = 1, ["name"] = "Summon Gargoyle", ["tier"] = 11, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132182 },
                [1] = { ["name"] = "Virulence", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 136126 },
                [15] = { ["name"] = "Outbreak", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 136182 },
                [3] = { ["name"] = "Ravenous Dead", ["tier"] = 2, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 237524 },
                [2] = { ["name"] = "Morbidity", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 136144 },
                [5] = { ["name"] = "Epidemic", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136207 },
                [4] = { ["name"] = "Crypt Fever", ["tier"] = 8, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 136066 },
                [7] = { ["isExceptional"] = 1, ["name"] = "Corpse Explosion", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 132099 },
                [6] = { ["name"] = "Master of Ghouls", ["tier"] = 6, ["id"] = 0, ["column"] = 4, ["maxRank"] = 1, ["texture"] = 136119 },
                [14] = { ["isExceptional"] = 1, ["name"] = "Bone Shield", ["tier"] = 8, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 132728 },
                [8] = { ["isExceptional"] = 1, ["name"] = "Unholy Blight", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 1, ["texture"] = 136132 },
                [16] = { ["name"] = "Magic Suppression", ["tier"] = 6, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 136120 },
                [17] = { ["name"] = "Dirge", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 136194 },
                [13] = { ["name"] = "Impurity", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136196 },
                [12] = { ["name"] = "Blood-Caked Blade", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 132109 },
                [11] = { ["name"] = "Wandering Plague", ["tier"] = 9, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 136127 },
                [10] = { ["name"] = "Reaping", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 136195 },
            },
        },
        ["SHAMAN"] = {
            [1] = {
                [25] = { ["name"] = "Booming Echoes", ["tier"] = 8, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135782 },
                [24] = { ["name"] = "Shamanism", ["tier"] = 10, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136234 },
                [23] = { ["isExceptional"] = 1, ["name"] = "Thunderstorm", ["tier"] = 11, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 237589 },
                [22] = { ["name"] = "Storm, Earth and Fire", ["tier"] = 7, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 237588 },
                [21] = { ["name"] = "Lava Flows", ["tier"] = 9, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 237583 },
                [20] = { ["name"] = "Astral Shift", ["tier"] = 9, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 237572 },
                [19] = { ["name"] = "Elemental Oath", ["tier"] = 8, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 237576 },
                [18] = { ["isExceptional"] = 1, ["name"] = "Totem of Wrath", ["tier"] = 9, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135829 },
                [9] = { ["name"] = "Reverberation", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 5, ["texture"] = 135850 },
                [1] = { ["name"] = "Call of Flame", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 135817 },
                [15] = { ["name"] = "Unrelenting Storm", ["tier"] = 5, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 136111 },
                [3] = { ["name"] = "Concussion", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135807 },
                [2] = { ["name"] = "Call of Thunder", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136014 },
                [5] = { ["name"] = "Elemental Fury", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135830 },
                [4] = { ["name"] = "Convection", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136116 },
                [7] = { ["isExceptional"] = 1, ["name"] = "Elemental Mastery", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136115 },
                [6] = { ["name"] = "Improved Fire Nova", ["tier"] = 4, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135824 },
                [14] = { ["name"] = "Elemental Devastation", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 135791 },
                [8] = { ["isExceptional"] = 1, ["name"] = "Elemental Focus", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136170 },
                [16] = { ["name"] = "Elemental Precision", ["tier"] = 6, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 136028 },
                [17] = { ["name"] = "Lightning Overload", ["tier"] = 8, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 136050 },
                [13] = { ["name"] = "Eye of the Storm", ["tier"] = 4, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 136213 },
                [12] = { ["name"] = "Elemental Reach", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136099 },
                [11] = { ["name"] = "Elemental Warding", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 136094 },
                [10] = { ["name"] = "Lightning Mastery", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135990 },
            },
            [2] = {
                [21] = { ["name"] = "Improved Stormstrike", ["tier"] = 8, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 237581 },
                [22] = { ["name"] = "Static Shock", ["tier"] = 8, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 237587 },
                [27] = { ["name"] = "Earth's Grasp", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 136097 },
                [26] = { ["name"] = "Mental Dexterity", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 136012 },
                [25] = { ["isExceptional"] = 1, ["name"] = "Feral Spirit", ["tier"] = 11, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 237577 },
                [24] = { ["name"] = "Maelstrom Weapon", ["tier"] = 10, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 237584 },
                [23] = { ["name"] = "Earthen Power", ["tier"] = 9, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 136024 },
                [28] = { ["isExceptional"] = 1, ["name"] = "Lava Lash", ["tier"] = 8, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 236289 },
                [29] = { ["name"] = "Frozen Power", ["tier"] = 6, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 135776 },
                [20] = { ["isExceptional"] = 1, ["name"] = "Shamanistic Rage", ["tier"] = 9, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136088 },
                [19] = { ["name"] = "Dual Wield Specialization", ["tier"] = 7, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 132148 },
                [18] = { ["name"] = "Mental Quickness", ["tier"] = 9, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 136055 },
                [9] = { ["name"] = "Ancestral Knowledge", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136162 },
                [1] = { ["name"] = "Anticipation", ["tier"] = 3, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 136056 },
                [15] = { ["name"] = "Improved Windfury Totem", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136114 },
                [3] = { ["name"] = "Improved Ghost Wolf", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 136095 },
                [2] = { ["name"] = "Flurry", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 132152 },
                [5] = { ["name"] = "Guardian Totems", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136098 },
                [4] = { ["name"] = "Improved Shields", ["tier"] = 2, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 136051 },
                [7] = { ["name"] = "Elemental Weapons", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 135814 },
                [6] = { ["name"] = "Enhancing Totems", ["tier"] = 1, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 136023 },
                [14] = { ["name"] = "Weapon Mastery", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 132215 },
                [8] = { ["name"] = "Thundering Strikes", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 132325 },
                [16] = { ["name"] = "Unleashed Rage", ["tier"] = 6, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 136110 },
                [17] = { ["name"] = "Dual Wield", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132147 },
                [13] = { ["isExceptional"] = 1, ["name"] = "Stormstrike", ["tier"] = 7, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 132314 },
                [12] = { ["isExceptional"] = 1, ["name"] = "Shamanistic Focus", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 136027 },
                [11] = { ["name"] = "Spirit Weapons", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132269 },
                [10] = { ["name"] = "Toughness", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135892 },
            },
            [3] = {
                [26] = { ["isExceptional"] = 1, ["name"] = "Cleanse Spirit", ["tier"] = 7, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 236288 },
                [25] = { ["isExceptional"] = 1, ["name"] = "Riptide", ["tier"] = 11, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 252995 },
                [24] = { ["name"] = "Tidal Waves", ["tier"] = 10, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 237590 },
                [23] = { ["name"] = "Ancestral Awakening", ["tier"] = 9, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 237571 },
                [22] = { ["name"] = "Blessing of the Eternals", ["tier"] = 8, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 237573 },
                [21] = { ["name"] = "Improved Earth Shield", ["tier"] = 9, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 136089 },
                [20] = { ["name"] = "Nature's Guardian", ["tier"] = 7, ["id"] = 0, ["column"] = 1, ["maxRank"] = 5, ["texture"] = 136060 },
                [19] = { ["isExceptional"] = 1, ["name"] = "Earth Shield", ["tier"] = 9, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136089 },
                [18] = { ["name"] = "Improved Chain Heal", ["tier"] = 8, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 136042 },
                [9] = { ["isExceptional"] = 1, ["name"] = "Nature's Swiftness", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 136076 },
                [1] = { ["name"] = "Ancestral Healing", ["tier"] = 3, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 136109 },
                [15] = { ["name"] = "Healing Way", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 136044 },
                [3] = { ["name"] = "Improved Water Shield", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 132315 },
                [2] = { ["isExceptional"] = 1, ["name"] = "Tidal Force", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 135845 },
                [5] = { ["name"] = "Healing Focus", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 136043 },
                [4] = { ["name"] = "Improved Healing Wave", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136052 },
                [7] = { ["name"] = "Improved Reincarnation", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136080 },
                [6] = { ["name"] = "Restorative Totems", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 136053 },
                [14] = { ["name"] = "Healing Grace", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 136041 },
                [8] = { ["isExceptional"] = 1, ["name"] = "Mana Tide Totem", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135861 },
                [16] = { ["name"] = "Focused Mind", ["tier"] = 5, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 136035 },
                [17] = { ["name"] = "Nature's Blessing", ["tier"] = 8, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 136059 },
                [13] = { ["name"] = "Totemic Focus", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136057 },
                [12] = { ["name"] = "Tidal Mastery", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136107 },
                [11] = { ["name"] = "Tidal Focus", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135859 },
                [10] = { ["name"] = "Purification", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135865 },
            },
        },
    }
elseif (isTBC) then
    lib.talents_table = lib.talents_table or {
        ["HUNTER"] = {
            [1] = {
                [21] = { ["name"] = "The Beast Within", ["tier"] = 9, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132166 },
                [20] = { ["name"] = "Serpent's Swiftness", ["tier"] = 8, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 132209 },
                [19] = { ["name"] = "Catlike Reflexes", ["tier"] = 7, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 132167 },
                [18] = { ["isExceptional"] = 1, ["name"] = "Bestial Wrath", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132127 },
                [9] = { ["name"] = "Unleashed Fury", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 132091 },
                [1] = { ["name"] = "Improved Aspect of the Hawk", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136076 },
                [15] = { ["name"] = "Animal Handler", ["tier"] = 6, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 132158 },
                [3] = { ["name"] = "Focused Fire", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 132210 },
                [2] = { ["name"] = "Endurance Training", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136080 },
                [5] = { ["name"] = "Thick Hide", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 134355 },
                [4] = { ["name"] = "Improved Aspect of the Monkey", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 132159 },
                [7] = { ["name"] = "Pathfinding", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 132242 },
                [6] = { ["name"] = "Improved Revive Pet", ["tier"] = 2, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 132163 },
                [14] = { ["name"] = "Bestial Discipline", ["tier"] = 5, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 136006 },
                [8] = { ["name"] = "Bestial Swiftness", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132120 },
                [16] = { ["name"] = "Frenzy", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 134296 },
                [17] = { ["name"] = "Ferocious Inspiration", ["tier"] = 7, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 132173 },
                [13] = { ["isExceptional"] = 1, ["name"] = "Intimidation", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132111 },
                [12] = { ["name"] = "Spirit Bond", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 132121 },
                [11] = { ["name"] = "Ferocity", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 134297 },
                [10] = { ["name"] = "Improved Mend Pet", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 132179 },
            },
            [2] = {
                [20] = { ["isExceptional"] = 1, ["name"] = "Silencing Shot", ["tier"] = 9, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132323 },
                [19] = { ["name"] = "Master Marksman", ["tier"] = 8, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 132177 },
                [18] = { ["name"] = "Improved Barrage", ["tier"] = 7, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 132330 },
                [9] = { ["name"] = "Improved Stings", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 132204 },
                [1] = { ["name"] = "Improved Concussive Shot", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 135860 },
                [15] = { ["name"] = "Ranged Weapon Specialization", ["tier"] = 6, ["id"] = 0, ["column"] = 4, ["maxRank"] = 5, ["texture"] = 135615 },
                [3] = { ["name"] = "Improved Hunter's Mark", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 132212 },
                [2] = { ["name"] = "Lethal Shots", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 132312 },
                [5] = { ["name"] = "Go for the Throat", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 132174 },
                [4] = { ["name"] = "Efficiency", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135865 },
                [7] = { ["isExceptional"] = 1, ["name"] = "Aimed Shot", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 135130 },
                [6] = { ["name"] = "Improved Arcane Shot", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 132218 },
                [14] = { ["name"] = "Combat Experience", ["tier"] = 6, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 132168 },
                [8] = { ["name"] = "Rapid Killing", ["tier"] = 3, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 132205 },
                [16] = { ["name"] = "Careful Aim", ["tier"] = 7, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 132217 },
                [17] = { ["isExceptional"] = 1, ["name"] = "Trueshot Aura", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132329 },
                [13] = { ["name"] = "Barrage", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 132330 },
                [12] = { ["isExceptional"] = 1, ["name"] = "Scatter Shot", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132153 },
                [11] = { ["name"] = "Concussive Barrage", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 135753 },
                [10] = { ["name"] = "Mortal Shots", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 132271 },
            },
            [3] = {
                [23] = { ["isExceptional"] = 1, ["name"] = "Readiness", ["tier"] = 9, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132206 },
                [22] = { ["name"] = "Master Tactician", ["tier"] = 8, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 132178 },
                [21] = { ["name"] = "Expose Weakness", ["tier"] = 7, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 132295 },
                [20] = { ["isExceptional"] = 1, ["name"] = "Wyvern Sting", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135125 },
                [19] = { ["name"] = "Thrill of the Hunt", ["tier"] = 7, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 132216 },
                [18] = { ["name"] = "Lightning Reflexes", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136047 },
                [9] = { ["name"] = "Survivalist", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136223 },
                [1] = { ["name"] = "Monster Slaying", ["tier"] = 1, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 134154 },
                [15] = { ["name"] = "Killer Instinct", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 135881 },
                [3] = { ["name"] = "Hawk Eye", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 132327 },
                [2] = { ["name"] = "Humanoid Slaying", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 135942 },
                [5] = { ["name"] = "Entrapment", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 136100 },
                [4] = { ["name"] = "Savage Strikes", ["tier"] = 1, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 132277 },
                [7] = { ["name"] = "Improved Wing Clip", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 132309 },
                [6] = { ["name"] = "Deflection", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 132269 },
                [14] = { ["name"] = "Survival Instincts", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 132214 },
                [8] = { ["name"] = "Clever Traps", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136106 },
                [16] = { ["isExceptional"] = 1, ["name"] = "Counterattack", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 132336 },
                [17] = { ["name"] = "Resourcefulness", ["tier"] = 6, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 132207 },
                [13] = { ["name"] = "Improved Feign Death", ["tier"] = 4, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 132293 },
                [12] = { ["name"] = "Surefooted", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 132219 },
                [11] = { ["name"] = "Trap Mastery", ["tier"] = 4, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 132149 },
                [10] = { ["isExceptional"] = 1, ["name"] = "Deterrence", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 132369 },
            },
        },
        ["WARRIOR"] = {
            [1] = {
                [23] = { ["isExceptional"] = 1, ["name"] = "Endless Rage", ["tier"] = 9, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132344 },
                [22] = { ["name"] = "Improved Mortal Strike", ["tier"] = 8, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 132355 },
                [21] = { ["name"] = "Second Wind", ["tier"] = 7, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 132175 },
                [20] = { ["isExceptional"] = 1, ["name"] = "Mortal Strike", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132355 },
                [19] = { ["name"] = "Blood Frenzy", ["tier"] = 7, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 132334 },
                [18] = { ["name"] = "Improved Disciplines", ["tier"] = 6, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 132346 },
                [9] = { ["name"] = "Deep Wounds", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 132090 },
                [1] = { ["name"] = "Improved Heroic Strike", ["tier"] = 1, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 132282 },
                [15] = { ["name"] = "Sword Specialization", ["tier"] = 5, ["id"] = 0, ["column"] = 4, ["maxRank"] = 5, ["texture"] = 135328 },
                [3] = { ["name"] = "Improved Rend", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 132155 },
                [2] = { ["name"] = "Deflection", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 132269 },
                [5] = { ["name"] = "Iron Will", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 135995 },
                [4] = { ["name"] = "Improved Charge", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 132337 },
                [7] = { ["name"] = "Improved Overpower", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135275 },
                [6] = { ["name"] = "Improved Thunder Clap", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 132326 },
                [14] = { ["name"] = "Mace Specialization", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 133476 },
                [8] = { ["isExceptional"] = 1, ["name"] = "Anger Management", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135881 },
                [16] = { ["name"] = "Improved Intercept", ["tier"] = 6, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 132307 },
                [17] = { ["name"] = "Improved Hamstring", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 132316 },
                [13] = { ["isExceptional"] = 1, ["name"] = "Death Wish", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136146 },
                [12] = { ["name"] = "Poleaxe Specialization", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 5, ["texture"] = 132397 },
                [11] = { ["name"] = "Impale", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 132312 },
                [10] = { ["name"] = "Two-Handed Weapon Specialization", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 132400 },
            },
            [2] = {
                [21] = { ["isExceptional"] = 1, ["name"] = "Rampage", ["tier"] = 9, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132352 },
                [20] = { ["name"] = "Improved Berserker Stance", ["tier"] = 8, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 132275 },
                [19] = { ["name"] = "Improved Whirlwind", ["tier"] = 7, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 132369 },
                [18] = { ["isExceptional"] = 1, ["name"] = "Bloodthirst", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136012 },
                [9] = { ["name"] = "Dual Wield Specialization", ["tier"] = 4, ["id"] = 0, ["column"] = 1, ["maxRank"] = 5, ["texture"] = 132147 },
                [1] = { ["name"] = "Booming Voice", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136075 },
                [15] = { ["name"] = "Improved Berserker Rage", ["tier"] = 6, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136009 },
                [3] = { ["name"] = "Improved Demoralizing Shout", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 132366 },
                [2] = { ["name"] = "Cruelty", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 132292 },
                [5] = { ["name"] = "Improved Cleave", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 132338 },
                [4] = { ["name"] = "Unbridled Wrath", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136097 },
                [7] = { ["name"] = "Blood Craze", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 136218 },
                [6] = { ["isExceptional"] = 1, ["name"] = "Piercing Howl", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136147 },
                [14] = { ["name"] = "Weapon Mastery", ["tier"] = 5, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 132367 },
                [8] = { ["name"] = "Commanding Presence", ["tier"] = 3, ["id"] = 0, ["column"] = 4, ["maxRank"] = 5, ["texture"] = 136035 },
                [16] = { ["name"] = "Flurry", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 132152 },
                [17] = { ["name"] = "Precision", ["tier"] = 7, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 132222 },
                [13] = { ["isExceptional"] = 1, ["name"] = "Sweeping Strikes", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132306 },
                [12] = { ["name"] = "Improved Slam", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 132340 },
                [11] = { ["name"] = "Enrage", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136224 },
                [10] = { ["name"] = "Improved Execute", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 135358 },
            },
            [3] = {
                [22] = { ["isExceptional"] = 1, ["name"] = "Devastate", ["tier"] = 9, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135291 },
                [21] = { ["name"] = "Vitality", ["tier"] = 8, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 133123 },
                [20] = { ["name"] = "Focused Rage", ["tier"] = 7, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 132345 },
                [19] = { ["isExceptional"] = 1, ["name"] = "Shield Slam", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 134951 },
                [18] = { ["name"] = "Improved Defensive Stance", ["tier"] = 7, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 132341 },
                [9] = { ["name"] = "Defiance", ["tier"] = 3, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 132347 },
                [1] = { ["name"] = "Improved Bloodrage", ["tier"] = 1, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 132277 },
                [15] = { ["name"] = "Improved Shield Bash", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 132357 },
                [3] = { ["name"] = "Anticipation", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136056 },
                [2] = { ["name"] = "Tactical Mastery", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 136031 },
                [5] = { ["name"] = "Toughness", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135892 },
                [4] = { ["name"] = "Shield Specialization", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 134952 },
                [7] = { ["name"] = "Improved Shield Block", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132110 },
                [6] = { ["isExceptional"] = 1, ["name"] = "Last Stand", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 1, ["texture"] = 135871 },
                [14] = { ["isExceptional"] = 1, ["name"] = "Concussion Blow", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132325 },
                [8] = { ["name"] = "Improved Revenge", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 132353 },
                [16] = { ["name"] = "Shield Mastery", ["tier"] = 6, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 132360 },
                [17] = { ["name"] = "One-Handed Weapon Specialization", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135321 },
                [13] = { ["name"] = "Improved Shield Wall", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 132362 },
                [12] = { ["name"] = "Improved Taunt", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 136080 },
                [11] = { ["name"] = "Improved Disarm", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 132343 },
                [10] = { ["name"] = "Improved Sunder Armor", ["tier"] = 4, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 132363 },
            },
        },
        ["PALADIN"] = {
            [1] = {
                [20] = { ["isExceptional"] = 1, ["name"] = "Divine Illumination", ["tier"] = 9, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135895 },
                [19] = { ["name"] = "Holy Guidance", ["tier"] = 8, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 135921 },
                [18] = { ["name"] = "Blessed Life", ["tier"] = 7, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 135876 },
                [9] = { ["name"] = "Illumination", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 135913 },
                [1] = { ["name"] = "Divine Strength", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 132154 },
                [15] = { ["name"] = "Holy Power", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135938 },
                [3] = { ["name"] = "Spiritual Focus", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 135736 },
                [2] = { ["name"] = "Divine Intellect", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136090 },
                [5] = { ["name"] = "Healing Light", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 135920 },
                [4] = { ["name"] = "Improved Seal of Righteousness", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 132325 },
                [7] = { ["name"] = "Improved Lay on Hands", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 135928 },
                [6] = { ["isExceptional"] = 1, ["name"] = "Aura Mastery", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135872 },
                [14] = { ["name"] = "Purifying Power", ["tier"] = 6, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135950 },
                [8] = { ["name"] = "Unyielding Faith", ["tier"] = 3, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 135984 },
                [16] = { ["name"] = "Light's Grace", ["tier"] = 7, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 135931 },
                [17] = { ["isExceptional"] = 1, ["name"] = "Holy Shock", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135972 },
                [13] = { ["name"] = "Sanctified Light", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 135917 },
                [12] = { ["isExceptional"] = 1, ["name"] = "Divine Favor", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135915 },
                [11] = { ["name"] = "Pure of Heart", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 135948 },
                [10] = { ["name"] = "Improved Blessing of Wisdom", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 135970 },
            },
            [2] = {
                [22] = { ["isExceptional"] = 1, ["name"] = "Avenger's Shield", ["tier"] = 9, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135874 },
                [21] = { ["name"] = "Combat Expertise", ["tier"] = 8, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135986 },
                [20] = { ["name"] = "Ardent Defender", ["tier"] = 7, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135870 },
                [19] = { ["isExceptional"] = 1, ["name"] = "Holy Shield", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135880 },
                [18] = { ["name"] = "Improved Holy Shield", ["tier"] = 7, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135880 },
                [9] = { ["name"] = "Anticipation", ["tier"] = 3, ["id"] = 0, ["column"] = 4, ["maxRank"] = 5, ["texture"] = 135994 },
                [1] = { ["name"] = "Improved Devotion Aura", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 135893 },
                [15] = { ["name"] = "Reckoning", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135882 },
                [3] = { ["name"] = "Precision", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 132282 },
                [2] = { ["name"] = "Redoubt", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 132110 },
                [5] = { ["name"] = "Toughness", ["tier"] = 2, ["id"] = 0, ["column"] = 4, ["maxRank"] = 5, ["texture"] = 135892 },
                [4] = { ["name"] = "Guardian's Favor", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 135964 },
                [7] = { ["name"] = "Improved Righteous Fury", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 135962 },
                [6] = { ["isExceptional"] = 1, ["name"] = "Blessing of Kings", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 1, ["texture"] = 135995 },
                [14] = { ["isExceptional"] = 1, ["name"] = "Blessing of Sanctuary", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136051 },
                [8] = { ["name"] = "Shield Specialization", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 134952 },
                [16] = { ["name"] = "Sacred Duty", ["tier"] = 6, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135896 },
                [17] = { ["name"] = "One-Handed Weapon Specialization", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135321 },
                [13] = { ["name"] = "Spell Warding", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135925 },
                [12] = { ["name"] = "Improved Concentration Aura", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 135933 },
                [11] = { ["name"] = "Improved Hammer of Justice", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 135963 },
                [10] = { ["name"] = "Stoicism", ["tier"] = 4, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135978 },
            },
            [3] = {
                [22] = { ["isExceptional"] = 1, ["name"] = "Crusader Strike", ["tier"] = 9, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135891 },
                [21] = { ["name"] = "Fanaticism", ["tier"] = 8, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 135905 },
                [20] = { ["name"] = "Divine Purpose", ["tier"] = 7, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 135897 },
                [19] = { ["isExceptional"] = 1, ["name"] = "Repentance", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135942 },
                [18] = { ["name"] = "Sanctified Seals", ["tier"] = 7, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 135924 },
                [9] = { ["name"] = "Pursuit of Justice", ["tier"] = 3, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 135937 },
                [1] = { ["name"] = "Improved Blessing of Might", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 135906 },
                [15] = { ["name"] = "Improved Sanctity Aura", ["tier"] = 5, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 135934 },
                [3] = { ["name"] = "Improved Judgement", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135959 },
                [2] = { ["name"] = "Benediction", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135863 },
                [5] = { ["name"] = "Deflection", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 132269 },
                [4] = { ["name"] = "Improved Seal of the Crusader", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 135924 },
                [7] = { ["name"] = "Conviction", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 135957 },
                [6] = { ["name"] = "Vindication", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 135985 },
                [14] = { ["isExceptional"] = 1, ["name"] = "Sanctity Aura", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 135934 },
                [8] = { ["isExceptional"] = 1, ["name"] = "Seal of Command", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 132347 },
                [16] = { ["name"] = "Vengeance", ["tier"] = 6, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 132275 },
                [17] = { ["name"] = "Sanctified Judgement", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 135959 },
                [13] = { ["name"] = "Two-Handed Weapon Specialization", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 133041 },
                [12] = { ["name"] = "Crusade", ["tier"] = 4, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 135889 },
                [11] = { ["name"] = "Improved Retribution Aura", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 135873 },
                [10] = { ["name"] = "Eye for an Eye", ["tier"] = 4, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135904 },
            },
        },
        ["MAGE"] = {
            [1] = {
                [23] = { ["isExceptional"] = 1, ["name"] = "Slow", ["tier"] = 9, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136091 },
                [22] = { ["name"] = "Mind Mastery", ["tier"] = 8, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 135740 },
                [21] = { ["name"] = "Spell Power", ["tier"] = 7, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 135734 },
                [20] = { ["isExceptional"] = 1, ["name"] = "Arcane Power", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136048 },
                [19] = { ["name"] = "Empowered Arcane Missiles", ["tier"] = 7, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 136096 },
                [18] = { ["name"] = "Arcane Potency", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 135732 },
                [9] = { ["isExceptional"] = 1, ["name"] = "Arcane Fortitude", ["tier"] = 3, ["id"] = 0, ["column"] = 4, ["maxRank"] = 1, ["texture"] = 135733 },
                [1] = { ["name"] = "Arcane Subtlety", ["tier"] = 1, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135894 },
                [15] = { ["name"] = "Arcane Mind", ["tier"] = 5, ["id"] = 0, ["column"] = 4, ["maxRank"] = 5, ["texture"] = 136129 },
                [3] = { ["name"] = "Improved Arcane Missiles", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136096 },
                [2] = { ["name"] = "Arcane Focus", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 135892 },
                [5] = { ["name"] = "Magic Absorption", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136011 },
                [4] = { ["name"] = "Wand Specialization", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135463 },
                [7] = { ["name"] = "Magic Attunement", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136006 },
                [6] = { ["name"] = "Arcane Concentration", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136170 },
                [14] = { ["isExceptional"] = 1, ["name"] = "Presence of Mind", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136031 },
                [8] = { ["name"] = "Arcane Impact", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 136116 },
                [16] = { ["name"] = "Prismatic Cloak", ["tier"] = 6, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135752 },
                [17] = { ["name"] = "Arcane Instability", ["tier"] = 6, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 136222 },
                [13] = { ["name"] = "Improved Blink", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135736 },
                [12] = { ["name"] = "Arcane Meditation", ["tier"] = 4, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 136208 },
                [11] = { ["name"] = "Improved Counterspell", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 135856 },
                [10] = { ["name"] = "Improved Mana Shield", ["tier"] = 4, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136153 },
            },
            [2] = {
                [22] = { ["isExceptional"] = 1, ["name"] = "Dragon's Breath", ["tier"] = 9, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 134153 },
                [21] = { ["name"] = "Empowered Fireball", ["tier"] = 8, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135812 },
                [20] = { ["name"] = "Molten Fury", ["tier"] = 7, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 135822 },
                [19] = { ["isExceptional"] = 1, ["name"] = "Combustion", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135824 },
                [18] = { ["name"] = "Pyromaniac", ["tier"] = 7, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 135789 },
                [9] = { ["name"] = "Burning Soul", ["tier"] = 3, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 135805 },
                [1] = { ["name"] = "Improved Fireball", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 135812 },
                [15] = { ["isExceptional"] = 1, ["name"] = "Blast Wave", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 135903 },
                [3] = { ["name"] = "Ignite", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 5, ["texture"] = 135818 },
                [2] = { ["name"] = "Impact", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135821 },
                [5] = { ["name"] = "Improved Fire Blast", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 135807 },
                [4] = { ["name"] = "Flame Throwing", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 135815 },
                [7] = { ["name"] = "Improved Flamestrike", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 135826 },
                [6] = { ["name"] = "Incineration", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135813 },
                [14] = { ["name"] = "Critical Mass", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 136115 },
                [8] = { ["isExceptional"] = 1, ["name"] = "Pyroblast", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 135808 },
                [16] = { ["name"] = "Blazing Speed", ["tier"] = 6, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135788 },
                [17] = { ["name"] = "Fire Power", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135817 },
                [13] = { ["name"] = "Playing with Fire", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 135823 },
                [12] = { ["name"] = "Master of Elements", ["tier"] = 4, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 135820 },
                [11] = { ["name"] = "Molten Shields", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 135806 },
                [10] = { ["name"] = "Improved Scorch", ["tier"] = 4, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 135827 },
            },
            [3] = {
                [22] = { ["isExceptional"] = 1, ["name"] = "Summon Water Elemental", ["tier"] = 9, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135862 },
                [21] = { ["name"] = "Empowered Frostbolt", ["tier"] = 8, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 135846 },
                [20] = { ["name"] = "Arctic Winds", ["tier"] = 7, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135833 },
                [19] = { ["isExceptional"] = 1, ["name"] = "Ice Barrier", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135988 },
                [18] = { ["name"] = "Winter's Chill", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135836 },
                [9] = { ["isExceptional"] = 1, ["name"] = "Icy Veins", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135838 },
                [1] = { ["name"] = "Frost Warding", ["tier"] = 1, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135850 },
                [15] = { ["isExceptional"] = 1, ["name"] = "Cold Snap", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135865 },
                [3] = { ["name"] = "Elemental Precision", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 135989 },
                [2] = { ["name"] = "Improved Frostbolt", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 135846 },
                [5] = { ["name"] = "Frostbite", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 135842 },
                [4] = { ["name"] = "Ice Shards", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 5, ["texture"] = 135855 },
                [7] = { ["name"] = "Permafrost", ["tier"] = 2, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 135864 },
                [6] = { ["name"] = "Improved Frost Nova", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 135840 },
                [14] = { ["name"] = "Frozen Core", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 135851 },
                [8] = { ["name"] = "Piercing Ice", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 135845 },
                [16] = { ["name"] = "Improved Cone of Cold", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 135852 },
                [17] = { ["name"] = "Ice Floes", ["tier"] = 6, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135854 },
                [13] = { ["name"] = "Shatter", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135849 },
                [12] = { ["name"] = "Frost Channeling", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 135860 },
                [11] = { ["name"] = "Arctic Reach", ["tier"] = 4, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136141 },
                [10] = { ["name"] = "Improved Blizzard", ["tier"] = 3, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 135857 },
            },
        },
        ["PRIEST"] = {
            [1] = {
                [22] = { ["isExceptional"] = 1, ["name"] = "Pain Suppression", ["tier"] = 9, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135936 },
                [21] = { ["name"] = "Enlightenment", ["tier"] = 8, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 135740 },
                [20] = { ["name"] = "Reflective Shield", ["tier"] = 7, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135940 },
                [19] = { ["isExceptional"] = 1, ["name"] = "Power Infusion", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135939 },
                [18] = { ["name"] = "Focused Will", ["tier"] = 7, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 135737 },
                [9] = { ["name"] = "Meditation", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 136090 },
                [1] = { ["name"] = "Unbreakable Will", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 135995 },
                [15] = { ["name"] = "Improved Divine Spirit", ["tier"] = 5, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 135898 },
                [3] = { ["name"] = "Silent Resolve", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 5, ["texture"] = 136053 },
                [2] = { ["name"] = "Wand Specialization", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135463 },
                [5] = { ["name"] = "Improved Power Word: Shield", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 135940 },
                [4] = { ["name"] = "Improved Power Word: Fortitude", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 135987 },
                [7] = { ["name"] = "Absolution", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 135868 },
                [6] = { ["name"] = "Martyrdom", ["tier"] = 2, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 136107 },
                [14] = { ["isExceptional"] = 1, ["name"] = "Divine Spirit", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 135898 },
                [8] = { ["isExceptional"] = 1, ["name"] = "Inner Focus", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135863 },
                [16] = { ["name"] = "Focused Power", ["tier"] = 6, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136158 },
                [17] = { ["name"] = "Force of Will", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136092 },
                [13] = { ["name"] = "Mental Strength", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136031 },
                [12] = { ["name"] = "Improved Mana Burn", ["tier"] = 4, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 136170 },
                [11] = { ["name"] = "Mental Agility", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 132156 },
                [10] = { ["name"] = "Improved Inner Fire", ["tier"] = 4, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 135926 },
            },
            [2] = {
                [21] = { ["isExceptional"] = 1, ["name"] = "Circle of Healing", ["tier"] = 9, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135887 },
                [20] = { ["name"] = "Empowered Healing", ["tier"] = 8, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 135913 },
                [19] = { ["name"] = "Blessed Resilience", ["tier"] = 7, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 135878 },
                [18] = { ["isExceptional"] = 1, ["name"] = "Lightwell", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135980 },
                [9] = { ["name"] = "Holy Reach", ["tier"] = 4, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135949 },
                [1] = { ["name"] = "Healing Focus", ["tier"] = 1, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135918 },
                [15] = { ["name"] = "Surge of Light", ["tier"] = 6, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135981 },
                [3] = { ["name"] = "Holy Specialization", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135967 },
                [2] = { ["name"] = "Improved Renew", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 135953 },
                [5] = { ["name"] = "Divine Fury", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135971 },
                [4] = { ["name"] = "Spell Warding", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 135976 },
                [7] = { ["name"] = "Blessed Recovery", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 135877 },
                [6] = { ["isExceptional"] = 1, ["name"] = "Holy Nova", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 1, ["texture"] = 135922 },
                [14] = { ["name"] = "Spiritual Guidance", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135977 },
                [8] = { ["name"] = "Inspiration", ["tier"] = 3, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 135928 },
                [16] = { ["name"] = "Spiritual Healing", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136057 },
                [17] = { ["name"] = "Holy Concentration", ["tier"] = 7, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 135905 },
                [13] = { ["isExceptional"] = 1, ["name"] = "Spirit of Redemption", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132864 },
                [12] = { ["name"] = "Healing Prayers", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135943 },
                [11] = { ["name"] = "Searing Light", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 135973 },
                [10] = { ["name"] = "Improved Healing", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 135916 },
            },
            [3] = {
                [21] = { ["isExceptional"] = 1, ["name"] = "Vampiric Touch", ["tier"] = 9, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135978 },
                [20] = { ["name"] = "Misery", ["tier"] = 8, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136176 },
                [19] = { ["name"] = "Shadow Power", ["tier"] = 7, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136204 },
                [18] = { ["isExceptional"] = 1, ["name"] = "Shadowform", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136200 },
                [9] = { ["name"] = "Improved Fade", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 135994 },
                [1] = { ["name"] = "Spirit Tap", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136188 },
                [15] = { ["name"] = "Focused Mind", ["tier"] = 5, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 136035 },
                [3] = { ["name"] = "Shadow Affinity", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 136205 },
                [2] = { ["name"] = "Blackout", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136160 },
                [5] = { ["name"] = "Shadow Focus", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136126 },
                [4] = { ["name"] = "Improved Shadow Word: Pain", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 136207 },
                [7] = { ["name"] = "Improved Mind Blast", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136224 },
                [6] = { ["name"] = "Improved Psychic Scream", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136184 },
                [14] = { ["name"] = "Improved Vampiric Embrace", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 136165 },
                [8] = { ["isExceptional"] = 1, ["name"] = "Mind Flay", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 136208 },
                [16] = { ["name"] = "Shadow Resilience", ["tier"] = 6, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136162 },
                [17] = { ["name"] = "Darkness", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136223 },
                [13] = { ["isExceptional"] = 1, ["name"] = "Vampiric Embrace", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136230 },
                [12] = { ["isExceptional"] = 1, ["name"] = "Silence", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 1, ["texture"] = 136164 },
                [11] = { ["name"] = "Shadow Weaving", ["tier"] = 4, ["id"] = 0, ["column"] = 4, ["maxRank"] = 5, ["texture"] = 136123 },
                [10] = { ["name"] = "Shadow Reach", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 136130 },
            },
        },
        ["WARLOCK"] = {
            [1] = {
                [21] = { ["isExceptional"] = 1, ["name"] = "Unstable Affliction", ["tier"] = 9, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136228 },
                [20] = { ["name"] = "Malediction", ["tier"] = 8, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 136137 },
                [19] = { ["name"] = "Improved Howl of Terror", ["tier"] = 8, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136147 },
                [18] = { ["isExceptional"] = 1, ["name"] = "Dark Pact", ["tier"] = 7, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 136141 },
                [9] = { ["isExceptional"] = 1, ["name"] = "Amplify Curse", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 136132 },
                [1] = { ["name"] = "Suppression", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136230 },
                [15] = { ["isExceptional"] = 1, ["name"] = "Curse of Exhaustion", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 136162 },
                [3] = { ["name"] = "Improved Curse of Weakness", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136138 },
                [2] = { ["name"] = "Improved Corruption", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136118 },
                [5] = { ["name"] = "Improved Life Tap", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 136126 },
                [4] = { ["name"] = "Improved Drain Soul", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 136163 },
                [7] = { ["name"] = "Improved Curse of Agony", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136139 },
                [6] = { ["name"] = "Soul Siphon", ["tier"] = 2, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 136169 },
                [14] = { ["isExceptional"] = 1, ["name"] = "Siphon Life", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136188 },
                [8] = { ["name"] = "Fel Concentration", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136157 },
                [16] = { ["name"] = "Shadow Mastery", ["tier"] = 6, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136195 },
                [17] = { ["name"] = "Contagion", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136180 },
                [13] = { ["name"] = "Shadow Embrace", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 5, ["texture"] = 136198 },
                [12] = { ["name"] = "Empowered Corruption", ["tier"] = 4, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 136118 },
                [11] = { ["name"] = "Nightfall", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 136223 },
                [10] = { ["name"] = "Grim Reach", ["tier"] = 4, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136127 },
            },
            [2] = {
                [22] = { ["isExceptional"] = 1, ["name"] = "Summon Felguard", ["tier"] = 9, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136216 },
                [21] = { ["name"] = "Demonic Tactics", ["tier"] = 8, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136150 },
                [20] = { ["name"] = "Demonic Knowledge", ["tier"] = 7, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 136165 },
                [19] = { ["isExceptional"] = 1, ["name"] = "Soul Link", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136160 },
                [18] = { ["name"] = "Demonic Resilience", ["tier"] = 7, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 136149 },
                [9] = { ["name"] = "Fel Stamina", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 136121 },
                [1] = { ["name"] = "Improved Healthstone", ["tier"] = 1, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135230 },
                [15] = { ["name"] = "Master Conjuror", ["tier"] = 5, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 132386 },
                [3] = { ["name"] = "Demonic Embrace", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136172 },
                [2] = { ["name"] = "Improved Imp", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 136218 },
                [5] = { ["name"] = "Improved Voidwalker", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 136221 },
                [4] = { ["name"] = "Improved Health Funnel", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136168 },
                [7] = { ["name"] = "Improved Sayaad", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 4352493 },
                [6] = { ["name"] = "Fel Intellect", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 135932 },
                [14] = { ["isExceptional"] = 1, ["name"] = "Demonic Sacrifice", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136184 },
                [8] = { ["isExceptional"] = 1, ["name"] = "Fel Domination", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136082 },
                [16] = { ["name"] = "Mana Feed", ["tier"] = 6, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 136171 },
                [17] = { ["name"] = "Master Demonologist", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136203 },
                [13] = { ["name"] = "Improved Enslave Demon", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136154 },
                [12] = { ["name"] = "Unholy Power", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136206 },
                [11] = { ["name"] = "Master Summoner", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 136164 },
                [10] = { ["name"] = "Demonic Aegis", ["tier"] = 3, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 136185 },
            },
            [3] = {
                [21] = { ["isExceptional"] = 1, ["name"] = "Shadowfury", ["tier"] = 9, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136201 },
                [20] = { ["name"] = "Shadow and Flame", ["tier"] = 8, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136196 },
                [19] = { ["name"] = "Soul Leech", ["tier"] = 7, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 136214 },
                [18] = { ["isExceptional"] = 1, ["name"] = "Conflagrate", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135807 },
                [9] = { ["name"] = "Intensity", ["tier"] = 4, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135819 },
                [1] = { ["name"] = "Improved Shadow Bolt", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136197 },
                [15] = { ["name"] = "Nether Protection", ["tier"] = 6, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 136178 },
                [3] = { ["name"] = "Bane", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136146 },
                [2] = { ["name"] = "Cataclysm", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135831 },
                [5] = { ["name"] = "Improved Firebolt", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135809 },
                [4] = { ["name"] = "Aftermath", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135805 },
                [7] = { ["name"] = "Devastation", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135813 },
                [6] = { ["name"] = "Improved Lash of Pain", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 136136 },
                [14] = { ["name"] = "Ruin", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 136207 },
                [8] = { ["isExceptional"] = 1, ["name"] = "Shadowburn", ["tier"] = 3, ["id"] = 0, ["column"] = 4, ["maxRank"] = 1, ["texture"] = 136191 },
                [16] = { ["name"] = "Emberstorm", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135826 },
                [17] = { ["name"] = "Backlash", ["tier"] = 7, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 135823 },
                [13] = { ["name"] = "Improved Immolate", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 135817 },
                [12] = { ["name"] = "Pyroclasm", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135830 },
                [11] = { ["name"] = "Improved Searing Pain", ["tier"] = 4, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 135827 },
                [10] = { ["name"] = "Destructive Reach", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 136133 },
            },
        },
        ["SHAMAN"] = {
            [1] = {
                [20] = { ["isExceptional"] = 1, ["name"] = "Totem of Wrath", ["tier"] = 9, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135829 },
                [19] = { ["name"] = "Lightning Overload", ["tier"] = 8, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136050 },
                [18] = { ["name"] = "Elemental Shields", ["tier"] = 7, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 136030 },
                [9] = { ["name"] = "Improved Fire Totems", ["tier"] = 4, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135824 },
                [1] = { ["name"] = "Convection", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136116 },
                [15] = { ["name"] = "Elemental Precision", ["tier"] = 6, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 136028 },
                [3] = { ["name"] = "Earth's Grasp", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136097 },
                [2] = { ["name"] = "Concussion", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135807 },
                [5] = { ["name"] = "Call of Flame", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 135817 },
                [4] = { ["name"] = "Elemental Warding", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 136094 },
                [7] = { ["name"] = "Reverberation", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 135850 },
                [6] = { ["isExceptional"] = 1, ["name"] = "Elemental Focus", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 1, ["texture"] = 136170 },
                [14] = { ["name"] = "Unrelenting Storm", ["tier"] = 5, ["id"] = 0, ["column"] = 4, ["maxRank"] = 5, ["texture"] = 136111 },
                [8] = { ["name"] = "Call of Thunder", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136014 },
                [16] = { ["name"] = "Lightning Mastery", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135990 },
                [17] = { ["isExceptional"] = 1, ["name"] = "Elemental Mastery", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136115 },
                [13] = { ["name"] = "Elemental Fury", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135830 },
                [12] = { ["name"] = "Storm Reach", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136099 },
                [11] = { ["name"] = "Elemental Devastation", ["tier"] = 4, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 135791 },
                [10] = { ["name"] = "Eye of the Storm", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 136213 },
            },
            [2] = {
                [21] = { ["isExceptional"] = 1, ["name"] = "Shamanistic Rage", ["tier"] = 9, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136088 },
                [20] = { ["name"] = "Unleashed Rage", ["tier"] = 8, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136110 },
                [19] = { ["isExceptional"] = 1, ["name"] = "Stormstrike", ["tier"] = 7, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 132314 },
                [18] = { ["name"] = "Dual Wield", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132147 },
                [9] = { ["name"] = "Anticipation", ["tier"] = 3, ["id"] = 0, ["column"] = 4, ["maxRank"] = 5, ["texture"] = 136056 },
                [1] = { ["name"] = "Ancestral Knowledge", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136162 },
                [15] = { ["name"] = "Mental Quickness", ["tier"] = 6, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 136055 },
                [3] = { ["name"] = "Guardian Totems", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136098 },
                [2] = { ["name"] = "Shield Specialization", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 134952 },
                [5] = { ["name"] = "Improved Ghost Wolf", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 136095 },
                [4] = { ["name"] = "Thundering Strikes", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 132325 },
                [7] = { ["name"] = "Enhancing Totems", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136023 },
                [6] = { ["name"] = "Improved Lightning Shield", ["tier"] = 2, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 136051 },
                [14] = { ["name"] = "Elemental Weapons", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 135814 },
                [8] = { ["name"] = "Shamanistic Focus", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 136027 },
                [16] = { ["name"] = "Weapon Mastery", ["tier"] = 6, ["id"] = 0, ["column"] = 4, ["maxRank"] = 5, ["texture"] = 132215 },
                [17] = { ["name"] = "Dual Wield Specialization", ["tier"] = 7, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 132148 },
                [13] = { ["name"] = "Spirit Weapons", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132269 },
                [12] = { ["name"] = "Improved Weapon Totems", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135792 },
                [11] = { ["name"] = "Toughness", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135892 },
                [10] = { ["name"] = "Flurry", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 132152 },
            },
            [3] = {
                [20] = { ["isExceptional"] = 1, ["name"] = "Earth Shield", ["tier"] = 9, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136089 },
                [19] = { ["name"] = "Improved Chain Heal", ["tier"] = 8, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 136042 },
                [18] = { ["name"] = "Nature's Blessing", ["tier"] = 8, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 136059 },
                [9] = { ["name"] = "Healing Grace", ["tier"] = 3, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 136041 },
                [1] = { ["name"] = "Improved Healing Wave", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136052 },
                [15] = { ["name"] = "Purification", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135865 },
                [3] = { ["name"] = "Improved Reincarnation", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136080 },
                [2] = { ["name"] = "Tidal Focus", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135859 },
                [5] = { ["name"] = "Totemic Focus", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136057 },
                [4] = { ["name"] = "Ancestral Healing", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 136109 },
                [7] = { ["name"] = "Healing Focus", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136043 },
                [6] = { ["name"] = "Nature's Guidance", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 135860 },
                [14] = { ["name"] = "Focused Mind", ["tier"] = 5, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 136035 },
                [8] = { ["name"] = "Totemic Mastery", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 136069 },
                [16] = { ["isExceptional"] = 1, ["name"] = "Mana Tide Totem", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135861 },
                [17] = { ["name"] = "Nature's Guardian", ["tier"] = 7, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136060 },
                [13] = { ["isExceptional"] = 1, ["name"] = "Nature's Swiftness", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 136076 },
                [12] = { ["name"] = "Healing Way", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 136044 },
                [11] = { ["name"] = "Tidal Mastery", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136107 },
                [10] = { ["name"] = "Restorative Totems", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136053 },
            },
        },
        ["DRUID"] = {
            [1] = {
                [21] = { ["isExceptional"] = 1, ["name"] = "Force of Nature", ["tier"] = 9, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132129 },
                [20] = { ["name"] = "Wrath of Cenarius", ["tier"] = 8, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 132146 },
                [19] = { ["name"] = "Improved Faerie Fire", ["tier"] = 7, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 136033 },
                [18] = { ["isExceptional"] = 1, ["name"] = "Moonkin Form", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136036 },
                [9] = { ["name"] = "Nature's Reach", ["tier"] = 3, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 136065 },
                [1] = { ["name"] = "Starlight Wrath", ["tier"] = 1, ["id"] = 0, ["column"] = 1, ["maxRank"] = 5, ["texture"] = 136006 },
                [15] = { ["name"] = "Moonfury", ["tier"] = 6, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136057 },
                [3] = { ["name"] = "Improved Nature's Grasp", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 4, ["texture"] = 136063 },
                [2] = { ["isExceptional"] = 1, ["name"] = "Nature's Grasp", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136063 },
                [5] = { ["name"] = "Focused Starlight", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 135138 },
                [4] = { ["name"] = "Control of Nature", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 136100 },
                [7] = { ["name"] = "Brambles", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 136104 },
                [6] = { ["name"] = "Improved Moonfire", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 136096 },
                [14] = { ["name"] = "Moonglow", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 136087 },
                [8] = { ["isExceptional"] = 1, ["name"] = "Insect Swarm", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 136045 },
                [16] = { ["name"] = "Balance of Power", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 132113 },
                [17] = { ["name"] = "Dreamstate", ["tier"] = 7, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 132123 },
                [13] = { ["name"] = "Nature's Grace", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136062 },
                [12] = { ["name"] = "Lunar Guidance", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 132132 },
                [11] = { ["name"] = "Celestial Focus", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 135753 },
                [10] = { ["name"] = "Vengeance", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136075 },
            },
            [2] = {
                [21] = { ["name"] = "Mangle", ["tier"] = 9, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132135 },
                [20] = { ["name"] = "Predatory Instincts", ["tier"] = 8, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 132138 },
                [19] = { ["name"] = "Improved Leader of the Pack", ["tier"] = 7, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 136112 },
                [18] = { ["isExceptional"] = 1, ["name"] = "Leader of the Pack", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136112 },
                [9] = { ["name"] = "Shredding Attacks", ["tier"] = 4, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136231 },
                [1] = { ["name"] = "Ferocity", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 132190 },
                [15] = { ["name"] = "Heart of the Wild", ["tier"] = 6, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 135879 },
                [3] = { ["name"] = "Feral Instinct", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 132089 },
                [2] = { ["name"] = "Feral Aggression", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 132121 },
                [5] = { ["name"] = "Thick Hide", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 134355 },
                [4] = { ["name"] = "Brutal Impact", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 132114 },
                [7] = { ["isExceptional"] = 1, ["name"] = "Feral Charge", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132183 },
                [6] = { ["name"] = "Feral Swiftness", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136095 },
                [14] = { ["name"] = "Nurturing Instinct", ["tier"] = 5, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 132130 },
                [8] = { ["name"] = "Sharpened Claws", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 134297 },
                [16] = { ["name"] = "Survival of the Fittest", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 132126 },
                [17] = { ["name"] = "Primal Tenacity", ["tier"] = 7, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 132139 },
                [13] = { ["isExceptional"] = 1, ["name"] = "Faerie Fire (Feral)", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 136033 },
                [12] = { ["name"] = "Savage Fury", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 132141 },
                [11] = { ["name"] = "Primal Fury", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 132278 },
                [10] = { ["name"] = "Predatory Strikes", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 132185 },
            },
            [3] = {
                [20] = { ["isExceptional"] = 1, ["name"] = "Tree of Life", ["tier"] = 9, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132145 },
                [19] = { ["name"] = "Empowered Rejuvenation", ["tier"] = 8, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 132124 },
                [18] = { ["name"] = "Natural Perfection", ["tier"] = 7, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 132137 },
                [9] = { ["name"] = "Tranquil Spirit", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 135900 },
                [1] = { ["name"] = "Improved Mark of the Wild", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136078 },
                [15] = { ["name"] = "Improved Regrowth", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136085 },
                [3] = { ["name"] = "Naturalist", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 5, ["texture"] = 136041 },
                [2] = { ["name"] = "Furor", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135881 },
                [5] = { ["name"] = "Natural Shapeshifter", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 136116 },
                [4] = { ["name"] = "Nature's Focus", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136042 },
                [7] = { ["name"] = "Subtlety", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 132150 },
                [6] = { ["name"] = "Intensity", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 135863 },
                [14] = { ["name"] = "Empowered Touch", ["tier"] = 6, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 132125 },
                [8] = { ["isExceptional"] = 1, ["name"] = "Omen of Clarity", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 136017 },
                [16] = { ["name"] = "Living Spirit", ["tier"] = 7, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 136037 },
                [17] = { ["isExceptional"] = 1, ["name"] = "Swiftmend", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 134914 },
                [13] = { ["name"] = "Improved Tranquility", ["tier"] = 5, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 136107 },
                [12] = { ["name"] = "Gift of Nature", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136074 },
                [11] = { ["isExceptional"] = 1, ["name"] = "Nature's Swiftness", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 1, ["texture"] = 136076 },
                [10] = { ["name"] = "Improved Rejuvenation", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 136081 },
            },
        },
        ["ROGUE"] = {
            [1] = {
                [21] = { ["isExceptional"] = 1, ["name"] = "Mutilate", ["tier"] = 9, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132304 },
                [20] = { ["name"] = "Find Weakness", ["tier"] = 8, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 132295 },
                [19] = { ["name"] = "Deadened Nerves", ["tier"] = 7, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 132286 },
                [18] = { ["name"] = "Vigor", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136023 },
                [9] = { ["name"] = "Lethality", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 132109 },
                [1] = { ["name"] = "Improved Eviscerate", ["tier"] = 1, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 132292 },
                [15] = { ["name"] = "Quick Recovery", ["tier"] = 5, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 132301 },
                [3] = { ["name"] = "Malice", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 132277 },
                [2] = { ["name"] = "Remorseless Attacks", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 132151 },
                [5] = { ["name"] = "Murder", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 136147 },
                [4] = { ["name"] = "Ruthlessness", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 132122 },
                [7] = { ["isExceptional"] = 1, ["name"] = "Relentless Strikes", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 1, ["texture"] = 132340 },
                [6] = { ["name"] = "Puncturing Wounds", ["tier"] = 2, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 132090 },
                [14] = { ["name"] = "Improved Kidney Shot", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 132298 },
                [8] = { ["name"] = "Improved Expose Armor", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 132354 },
                [16] = { ["name"] = "Seal Fate", ["tier"] = 6, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136130 },
                [17] = { ["name"] = "Master Poisoner", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 132108 },
                [13] = { ["isExceptional"] = 1, ["name"] = "Cold Blood", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135988 },
                [12] = { ["name"] = "Fleet Footed", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 132296 },
                [11] = { ["name"] = "Improved Poisons", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 132273 },
                [10] = { ["name"] = "Vile Poisons", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 132293 },
            },
            [2] = {
                [24] = { ["isExceptional"] = 1, ["name"] = "Surprise Attacks", ["tier"] = 9, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132308 },
                [23] = { ["name"] = "Combat Potency", ["tier"] = 8, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135673 },
                [22] = { ["name"] = "Nerves of Steel", ["tier"] = 7, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 132300 },
                [21] = { ["isExceptional"] = 1, ["name"] = "Adrenaline Rush", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136206 },
                [20] = { ["name"] = "Vitality", ["tier"] = 7, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 132353 },
                [19] = { ["name"] = "Aggression", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 132275 },
                [18] = { ["name"] = "Weapon Expertise", ["tier"] = 6, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 135882 },
                [9] = { ["name"] = "Improved Sprint", ["tier"] = 3, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 132307 },
                [1] = { ["name"] = "Improved Gouge", ["tier"] = 1, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 132155 },
                [15] = { ["name"] = "Sword Specialization", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135328 },
                [3] = { ["name"] = "Lightning Reflexes", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136047 },
                [2] = { ["name"] = "Improved Sinister Strike", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 136189 },
                [5] = { ["name"] = "Deflection", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 132269 },
                [4] = { ["name"] = "Improved Slice and Dice", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 132306 },
                [7] = { ["name"] = "Endurance", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136205 },
                [6] = { ["name"] = "Precision", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 132222 },
                [14] = { ["isExceptional"] = 1, ["name"] = "Blade Flurry", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132350 },
                [8] = { ["isExceptional"] = 1, ["name"] = "Riposte", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132336 },
                [16] = { ["name"] = "Fist Weapon Specialization", ["tier"] = 5, ["id"] = 0, ["column"] = 4, ["maxRank"] = 5, ["texture"] = 132938 },
                [17] = { ["name"] = "Blade Twisting", ["tier"] = 6, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 132283 },
                [13] = { ["name"] = "Mace Specialization", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 5, ["texture"] = 133476 },
                [12] = { ["name"] = "Dual Wield Specialization", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 132147 },
                [11] = { ["name"] = "Dagger Specialization", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 135641 },
                [10] = { ["name"] = "Improved Kick", ["tier"] = 4, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 132219 },
            },
            [3] = {
                [22] = { ["isExceptional"] = 1, ["name"] = "Shadowstep", ["tier"] = 9, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132303 },
                [21] = { ["name"] = "Sinister Calling", ["tier"] = 8, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 132305 },
                [20] = { ["name"] = "Cheat Death", ["tier"] = 7, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 132285 },
                [19] = { ["isExceptional"] = 1, ["name"] = "Premeditation", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136183 },
                [18] = { ["name"] = "Enveloping Shadows", ["tier"] = 7, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 132291 },
                [9] = { ["name"] = "Setup", ["tier"] = 4, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 136056 },
                [1] = { ["name"] = "Master of Deception", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136129 },
                [15] = { ["isExceptional"] = 1, ["name"] = "Hemorrhage", ["tier"] = 5, ["id"] = 0, ["column"] = 4, ["maxRank"] = 1, ["texture"] = 136168 },
                [3] = { ["name"] = "Sleight of Hand", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 132294 },
                [2] = { ["name"] = "Opportunity", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 132366 },
                [5] = { ["name"] = "Camouflage", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 132320 },
                [4] = { ["name"] = "Dirty Tricks", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 132310 },
                [7] = { ["isExceptional"] = 1, ["name"] = "Ghostly Strike", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136136 },
                [6] = { ["name"] = "Initiative", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 136159 },
                [14] = { ["name"] = "Dirty Deeds", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 136220 },
                [8] = { ["name"] = "Improved Ambush", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 132282 },
                [16] = { ["name"] = "Master of Subtlety", ["tier"] = 6, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 132299 },
                [17] = { ["name"] = "Deadliness", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135540 },
                [13] = { ["isExceptional"] = 1, ["name"] = "Preparation", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136121 },
                [12] = { ["name"] = "Heightened Senses", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 132089 },
                [11] = { ["name"] = "Serrated Blades", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 135315 },
                [10] = { ["name"] = "Elusiveness", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 135994 },
            },
        },
        ["DEATHKNIGHT"] = {
            [1] = {},
            [2] = {},
            [3] = {},
        },
    }
elseif (isClassic) then
    lib.talents_table = lib.talents_table or {
        ["HUNTER"] = {
            [1] = {
                [1] = { ["name"] = "Improved Aspect of the Hawk", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136076 },
                [15] = { ["name"] = "Frenzy", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 134296 },
                [3] = { ["name"] = "Improved Eyes of the Beast", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 132150 },
                [2] = { ["name"] = "Endurance Training", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136080 },
                [5] = { ["name"] = "Thick Hide", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 134355 },
                [4] = { ["name"] = "Improved Aspect of the Monkey", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 132159 },
                [7] = { ["name"] = "Pathfinding", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 132242 },
                [6] = { ["name"] = "Improved Revive Pet", ["tier"] = 2, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 132163 },
                [9] = { ["name"] = "Unleashed Fury", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 132091 },
                [8] = { ["name"] = "Bestial Swiftness", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132120 },
                [16] = { ["isExceptional"] = 1, ["name"] = "Bestial Wrath", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132127 },
                [14] = { ["name"] = "Bestial Discipline", ["tier"] = 5, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 136006 },
                [13] = { ["isExceptional"] = 1, ["name"] = "Intimidation", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132111 },
                [12] = { ["name"] = "Spirit Bond", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 132121 },
                [11] = { ["name"] = "Ferocity", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 134297 },
                [10] = { ["name"] = "Improved Mend Pet", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 132179 },
            },
            [2] = {
                [1] = { ["name"] = "Improved Concussive Shot", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 135860 },
                [3] = { ["name"] = "Improved Hunter's Mark", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 132212 },
                [2] = { ["name"] = "Efficiency", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135865 },
                [5] = { ["isExceptional"] = 1, ["name"] = "Aimed Shot", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 1, ["texture"] = 135130 },
                [4] = { ["name"] = "Lethal Shots", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 132312 },
                [7] = { ["name"] = "Hawk Eye", ["tier"] = 3, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 132327 },
                [6] = { ["name"] = "Improved Arcane Shot", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 132218 },
                [9] = { ["name"] = "Mortal Shots", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 132271 },
                [8] = { ["name"] = "Improved Serpent Sting", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 132204 },
                [14] = { ["isExceptional"] = 1, ["name"] = "Trueshot Aura", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132329 },
                [13] = { ["name"] = "Ranged Weapon Specialization", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135615 },
                [12] = { ["name"] = "Improved Scorpid Sting", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 132169 },
                [11] = { ["name"] = "Barrage", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 132330 },
                [10] = { ["isExceptional"] = 1, ["name"] = "Scatter Shot", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 1, ["texture"] = 132153 },
            },
            [3] = {
                [1] = { ["name"] = "Monster Slaying", ["tier"] = 1, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 134154 },
                [15] = { ["name"] = "Lightning Reflexes", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136047 },
                [3] = { ["name"] = "Deflection", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 132269 },
                [2] = { ["name"] = "Humanoid Slaying", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 135942 },
                [5] = { ["name"] = "Savage Strikes", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 132277 },
                [4] = { ["name"] = "Entrapment", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 5, ["texture"] = 136100 },
                [7] = { ["name"] = "Clever Traps", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136106 },
                [6] = { ["name"] = "Improved Wing Clip", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 132309 },
                [9] = { ["isExceptional"] = 1, ["name"] = "Deterrence", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 132369 },
                [8] = { ["name"] = "Survivalist", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136223 },
                [16] = { ["isExceptional"] = 1, ["name"] = "Wyvern Sting", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135125 },
                [14] = { ["isExceptional"] = 1, ["name"] = "Counterattack", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 132336 },
                [13] = { ["name"] = "Killer Instinct", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 135881 },
                [12] = { ["name"] = "Improved Feign Death", ["tier"] = 4, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 132293 },
                [11] = { ["name"] = "Surefooted", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 132219 },
                [10] = { ["name"] = "Trap Mastery", ["tier"] = 4, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 132149 },
            },
        },
        ["WARRIOR"] = {
            [1] = {
                [4] = { ["name"] = "Improved Charge", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 132337 },
                [14] = { ["name"] = "Mace Specialization", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 133476 },
                [1] = { ["name"] = "Improved Heroic Strike", ["tier"] = 1, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 132282 },
                [8] = { ["isExceptional"] = 1, ["name"] = "Anger Management", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135881 },
                [3] = { ["name"] = "Improved Rend", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 132155 },
                [2] = { ["name"] = "Deflection", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 132269 },
                [5] = { ["name"] = "Tactical Mastery", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136031 },
                [18] = { ["isExceptional"] = 1, ["name"] = "Mortal Strike", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132355 },
                [7] = { ["name"] = "Improved Overpower", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135275 },
                [6] = { ["name"] = "Improved Thunder Clap", ["tier"] = 2, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 132326 },
                [9] = { ["name"] = "Deep Wounds", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 132090 },
                [15] = { ["name"] = "Sword Specialization", ["tier"] = 5, ["id"] = 0, ["column"] = 4, ["maxRank"] = 5, ["texture"] = 135328 },
                [16] = { ["name"] = "Polearm Specialization", ["tier"] = 6, ["id"] = 0, ["column"] = 1, ["maxRank"] = 5, ["texture"] = 135562 },
                [17] = { ["name"] = "Improved Hamstring", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 132316 },
                [13] = { ["isExceptional"] = 1, ["name"] = "Sweeping Strikes", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132306 },
                [12] = { ["name"] = "Axe Specialization", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 5, ["texture"] = 132397 },
                [11] = { ["name"] = "Impale", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 132312 },
                [10] = { ["name"] = "Two-Handed Weapon Specialization", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 132400 },
            },
            [2] = {
                [14] = { ["name"] = "Improved Intercept", ["tier"] = 5, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 132307 },
                [1] = { ["name"] = "Booming Voice", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136075 },
                [8] = { ["name"] = "Improved Battle Shout", ["tier"] = 3, ["id"] = 0, ["column"] = 4, ["maxRank"] = 5, ["texture"] = 132333 },
                [3] = { ["name"] = "Improved Demoralizing Shout", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 132366 },
                [2] = { ["name"] = "Cruelty", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 132292 },
                [5] = { ["name"] = "Improved Cleave", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 132338 },
                [4] = { ["name"] = "Unbridled Wrath", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136097 },
                [7] = { ["name"] = "Blood Craze", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 136218 },
                [6] = { ["isExceptional"] = 1, ["name"] = "Piercing Howl", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136147 },
                [9] = { ["name"] = "Dual Wield Specialization", ["tier"] = 4, ["id"] = 0, ["column"] = 1, ["maxRank"] = 5, ["texture"] = 132147 },
                [15] = { ["name"] = "Improved Berserker Rage", ["tier"] = 6, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136009 },
                [16] = { ["name"] = "Flurry", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 132152 },
                [17] = { ["isExceptional"] = 1, ["name"] = "Bloodthirst", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136012 },
                [13] = { ["isExceptional"] = 1, ["name"] = "Death Wish", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136146 },
                [12] = { ["name"] = "Improved Slam", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 5, ["texture"] = 132340 },
                [11] = { ["name"] = "Enrage", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136224 },
                [10] = { ["name"] = "Improved Execute", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 135358 },
            },
            [3] = {
                [14] = { ["isExceptional"] = 1, ["name"] = "Concussion Blow", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132325 },
                [1] = { ["name"] = "Shield Specialization", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 134952 },
                [8] = { ["name"] = "Improved Revenge", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 132353 },
                [3] = { ["name"] = "Improved Bloodrage", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 132277 },
                [2] = { ["name"] = "Anticipation", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136056 },
                [5] = { ["name"] = "Iron Will", ["tier"] = 2, ["id"] = 0, ["column"] = 4, ["maxRank"] = 5, ["texture"] = 135995 },
                [4] = { ["name"] = "Toughness", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135892 },
                [7] = { ["name"] = "Improved Shield Block", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 132110 },
                [6] = { ["isExceptional"] = 1, ["name"] = "Last Stand", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 1, ["texture"] = 135871 },
                [9] = { ["name"] = "Defiance", ["tier"] = 3, ["id"] = 0, ["column"] = 4, ["maxRank"] = 5, ["texture"] = 132347 },
                [15] = { ["name"] = "Improved Shield Bash", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 132357 },
                [16] = { ["name"] = "One-Handed Weapon Specialization", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135321 },
                [17] = { ["isExceptional"] = 1, ["name"] = "Shield Slam", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 134951 },
                [13] = { ["name"] = "Improved Shield Wall", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 132362 },
                [12] = { ["name"] = "Improved Taunt", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 136080 },
                [11] = { ["name"] = "Improved Disarm", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 132343 },
                [10] = { ["name"] = "Improved Sunder Armor", ["tier"] = 4, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 132363 },
            },
        },
        ["PALADIN"] = {
            [1] = {
                [1] = { ["name"] = "Divine Strength", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 132154 },
                [3] = { ["name"] = "Spiritual Focus", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 135736 },
                [2] = { ["name"] = "Divine Intellect", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136090 },
                [5] = { ["name"] = "Healing Light", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 135920 },
                [4] = { ["name"] = "Improved Seal of Righteousness", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 132325 },
                [7] = { ["name"] = "Improved Lay on Hands", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 135928 },
                [6] = { ["isExceptional"] = 1, ["name"] = "Consecration", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135926 },
                [9] = { ["name"] = "Illumination", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 135913 },
                [8] = { ["name"] = "Unyielding Faith", ["tier"] = 3, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 135984 },
                [14] = { ["isExceptional"] = 1, ["name"] = "Holy Shock", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135972 },
                [13] = { ["name"] = "Holy Power", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135938 },
                [12] = { ["name"] = "Lasting Judgement", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 135917 },
                [11] = { ["isExceptional"] = 1, ["name"] = "Divine Favor", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135915 },
                [10] = { ["name"] = "Improved Blessing of Wisdom", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 135970 },
            },
            [2] = {
                [1] = { ["name"] = "Improved Devotion Aura", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 135893 },
                [3] = { ["name"] = "Precision", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 132282 },
                [2] = { ["name"] = "Redoubt", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 132110 },
                [5] = { ["name"] = "Toughness", ["tier"] = 2, ["id"] = 0, ["column"] = 4, ["maxRank"] = 5, ["texture"] = 135892 },
                [4] = { ["name"] = "Guardian's Favor", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 135964 },
                [7] = { ["name"] = "Improved Righteous Fury", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 135962 },
                [6] = { ["isExceptional"] = 1, ["name"] = "Blessing of Kings", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 1, ["texture"] = 135995 },
                [9] = { ["name"] = "Anticipation", ["tier"] = 3, ["id"] = 0, ["column"] = 4, ["maxRank"] = 5, ["texture"] = 135994 },
                [8] = { ["name"] = "Shield Specialization", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 134952 },
                [15] = { ["isExceptional"] = 1, ["name"] = "Holy Shield", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135880 },
                [14] = { ["name"] = "One-Handed Weapon Specialization", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135321 },
                [13] = { ["name"] = "Reckoning", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135882 },
                [12] = { ["isExceptional"] = 1, ["name"] = "Blessing of Sanctuary", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136051 },
                [11] = { ["name"] = "Improved Concentration Aura", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 135933 },
                [10] = { ["name"] = "Improved Hammer of Justice", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 135963 },
            },
            [3] = {
                [1] = { ["name"] = "Improved Blessing of Might", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 135906 },
                [3] = { ["name"] = "Improved Judgement", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135959 },
                [2] = { ["name"] = "Benediction", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135863 },
                [5] = { ["name"] = "Deflection", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 132269 },
                [4] = { ["name"] = "Improved Seal of the Crusader", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 135924 },
                [7] = { ["name"] = "Conviction", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 135957 },
                [6] = { ["name"] = "Vindication", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 135985 },
                [9] = { ["name"] = "Pursuit of Justice", ["tier"] = 3, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 135937 },
                [8] = { ["isExceptional"] = 1, ["name"] = "Seal of Command", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 132347 },
                [15] = { ["isExceptional"] = 1, ["name"] = "Repentance", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135942 },
                [14] = { ["name"] = "Vengeance", ["tier"] = 6, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 132275 },
                [13] = { ["isExceptional"] = 1, ["name"] = "Sanctity Aura", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 135934 },
                [12] = { ["name"] = "Two-Handed Weapon Specialization", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 133041 },
                [11] = { ["name"] = "Improved Retribution Aura", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 135873 },
                [10] = { ["name"] = "Eye for an Eye", ["tier"] = 4, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135904 },
            },
        },
        ["MAGE"] = {
            [1] = {
                [1] = { ["name"] = "Arcane Subtlety", ["tier"] = 1, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135894 },
                [15] = { ["name"] = "Arcane Instability", ["tier"] = 6, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 136222 },
                [3] = { ["name"] = "Improved Arcane Missiles", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136096 },
                [2] = { ["name"] = "Arcane Focus", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 135892 },
                [5] = { ["name"] = "Magic Absorption", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136011 },
                [4] = { ["name"] = "Wand Specialization", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135463 },
                [7] = { ["name"] = "Magic Attunement", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136006 },
                [6] = { ["name"] = "Arcane Concentration", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136170 },
                [9] = { ["isExceptional"] = 1, ["name"] = "Arcane Resilience", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 135733 },
                [8] = { ["name"] = "Improved Arcane Explosion", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 136116 },
                [16] = { ["isExceptional"] = 1, ["name"] = "Arcane Power", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136048 },
                [14] = { ["name"] = "Arcane Mind", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136129 },
                [13] = { ["isExceptional"] = 1, ["name"] = "Presence of Mind", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136031 },
                [12] = { ["name"] = "Arcane Meditation", ["tier"] = 4, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 136208 },
                [11] = { ["name"] = "Improved Counterspell", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 135856 },
                [10] = { ["name"] = "Improved Mana Shield", ["tier"] = 4, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136153 },
            },
            [2] = {
                [1] = { ["name"] = "Improved Fireball", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 135812 },
                [15] = { ["name"] = "Fire Power", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135817 },
                [3] = { ["name"] = "Ignite", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 5, ["texture"] = 135818 },
                [2] = { ["name"] = "Impact", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135821 },
                [5] = { ["name"] = "Improved Fire Blast", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 135807 },
                [4] = { ["name"] = "Flame Throwing", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 135815 },
                [7] = { ["name"] = "Improved Flamestrike", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 135826 },
                [6] = { ["name"] = "Incinerate", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135813 },
                [9] = { ["name"] = "Burning Soul", ["tier"] = 3, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 135805 },
                [8] = { ["isExceptional"] = 1, ["name"] = "Pyroblast", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 135808 },
                [16] = { ["isExceptional"] = 1, ["name"] = "Combustion", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135824 },
                [14] = { ["isExceptional"] = 1, ["name"] = "Blast Wave", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 135903 },
                [13] = { ["name"] = "Critical Mass", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 136115 },
                [12] = { ["name"] = "Master of Elements", ["tier"] = 4, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 135820 },
                [11] = { ["name"] = "Improved Fire Ward", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 135806 },
                [10] = { ["name"] = "Improved Scorch", ["tier"] = 4, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 135827 },
            },
            [3] = {
                [9] = { ["isExceptional"] = 1, ["name"] = "Cold Snap", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135865 },
                [1] = { ["name"] = "Frost Warding", ["tier"] = 1, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135850 },
                [15] = { ["name"] = "Improved Cone of Cold", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 135852 },
                [3] = { ["name"] = "Elemental Precision", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 135989 },
                [2] = { ["name"] = "Improved Frostbolt", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 135846 },
                [5] = { ["name"] = "Frostbite", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 135842 },
                [4] = { ["name"] = "Ice Shards", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 5, ["texture"] = 135855 },
                [7] = { ["name"] = "Permafrost", ["tier"] = 2, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 135864 },
                [6] = { ["name"] = "Improved Frost Nova", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 135840 },
                [14] = { ["isExceptional"] = 1, ["name"] = "Ice Block", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135841 },
                [8] = { ["name"] = "Piercing Ice", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 135845 },
                [16] = { ["name"] = "Winter's Chill", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135836 },
                [17] = { ["isExceptional"] = 1, ["name"] = "Ice Barrier", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135988 },
                [13] = { ["name"] = "Shatter", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135849 },
                [12] = { ["name"] = "Frost Channeling", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 135860 },
                [11] = { ["name"] = "Arctic Reach", ["tier"] = 4, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136141 },
                [10] = { ["name"] = "Improved Blizzard", ["tier"] = 3, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 135857 },
            },
        },
        ["PRIEST"] = {
            [1] = {
                [1] = { ["name"] = "Unbreakable Will", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 135995 },
                [3] = { ["name"] = "Silent Resolve", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 5, ["texture"] = 136053 },
                [2] = { ["name"] = "Wand Specialization", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135463 },
                [5] = { ["name"] = "Improved Power Word: Shield", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 135940 },
                [4] = { ["name"] = "Improved Power Word: Fortitude", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 135987 },
                [7] = { ["isExceptional"] = 1, ["name"] = "Inner Focus", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135863 },
                [6] = { ["name"] = "Martyrdom", ["tier"] = 2, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 136107 },
                [9] = { ["name"] = "Improved Inner Fire", ["tier"] = 4, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 135926 },
                [8] = { ["name"] = "Meditation", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 136090 },
                [15] = { ["isExceptional"] = 1, ["name"] = "Power Infusion", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135939 },
                [14] = { ["name"] = "Force of Will", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136092 },
                [13] = { ["isExceptional"] = 1, ["name"] = "Divine Spirit", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 135898 },
                [12] = { ["name"] = "Mental Strength", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136031 },
                [11] = { ["name"] = "Improved Mana Burn", ["tier"] = 4, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 136170 },
                [10] = { ["name"] = "Mental Agility", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 132156 },
            },
            [2] = {
                [1] = { ["name"] = "Healing Focus", ["tier"] = 1, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135918 },
                [15] = { ["name"] = "Spiritual Healing", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136057 },
                [3] = { ["name"] = "Holy Specialization", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135967 },
                [2] = { ["name"] = "Improved Renew", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 135953 },
                [5] = { ["name"] = "Divine Fury", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135971 },
                [4] = { ["name"] = "Spell Warding", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 135976 },
                [7] = { ["name"] = "Blessed Recovery", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 135877 },
                [6] = { ["isExceptional"] = 1, ["name"] = "Holy Nova", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 1, ["texture"] = 135922 },
                [9] = { ["name"] = "Holy Reach", ["tier"] = 4, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135949 },
                [8] = { ["name"] = "Inspiration", ["tier"] = 3, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 135928 },
                [16] = { ["isExceptional"] = 1, ["name"] = "Lightwell", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135980 },
                [14] = { ["name"] = "Spiritual Guidance", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135977 },
                [13] = { ["isExceptional"] = 1, ["name"] = "Spirit of Redemption", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132864 },
                [12] = { ["name"] = "Improved Prayer of Healing", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135943 },
                [11] = { ["name"] = "Searing Light", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 135973 },
                [10] = { ["name"] = "Improved Healing", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 135916 },
            },
            [3] = {
                [1] = { ["name"] = "Spirit Tap", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136188 },
                [15] = { ["name"] = "Darkness", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136223 },
                [3] = { ["name"] = "Shadow Affinity", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 136205 },
                [2] = { ["name"] = "Blackout", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136160 },
                [5] = { ["name"] = "Shadow Focus", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136126 },
                [4] = { ["name"] = "Improved Shadow Word: Pain", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 136207 },
                [7] = { ["name"] = "Improved Mind Blast", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136224 },
                [6] = { ["name"] = "Improved Psychic Scream", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136184 },
                [9] = { ["name"] = "Improved Fade", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 135994 },
                [8] = { ["isExceptional"] = 1, ["name"] = "Mind Flay", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 136208 },
                [16] = { ["isExceptional"] = 1, ["name"] = "Shadowform", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136200 },
                [14] = { ["name"] = "Improved Vampiric Embrace", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 136165 },
                [13] = { ["isExceptional"] = 1, ["name"] = "Vampiric Embrace", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136230 },
                [12] = { ["isExceptional"] = 1, ["name"] = "Silence", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 1, ["texture"] = 136164 },
                [11] = { ["name"] = "Shadow Weaving", ["tier"] = 4, ["id"] = 0, ["column"] = 4, ["maxRank"] = 5, ["texture"] = 136123 },
                [10] = { ["name"] = "Shadow Reach", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 136130 },
            },
        },
        ["WARLOCK"] = {
            [1] = {
                [14] = { ["isExceptional"] = 1, ["name"] = "Curse of Exhaustion", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 136162 },
                [1] = { ["name"] = "Suppression", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136230 },
                [8] = { ["name"] = "Fel Concentration", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136157 },
                [3] = { ["name"] = "Improved Curse of Weakness", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 136138 },
                [2] = { ["name"] = "Improved Corruption", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136118 },
                [5] = { ["name"] = "Improved Life Tap", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 136126 },
                [4] = { ["name"] = "Improved Drain Soul", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 136163 },
                [7] = { ["name"] = "Improved Curse of Agony", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 136139 },
                [6] = { ["name"] = "Improved Drain Life", ["tier"] = 2, ["id"] = 0, ["column"] = 4, ["maxRank"] = 5, ["texture"] = 136169 },
                [9] = { ["isExceptional"] = 1, ["name"] = "Amplify Curse", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 136132 },
                [15] = { ["name"] = "Improved Curse of Exhaustion", ["tier"] = 5, ["id"] = 0, ["column"] = 4, ["maxRank"] = 4, ["texture"] = 136162 },
                [16] = { ["name"] = "Shadow Mastery", ["tier"] = 6, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136195 },
                [17] = { ["isExceptional"] = 1, ["name"] = "Dark Pact", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136141 },
                [13] = { ["isExceptional"] = 1, ["name"] = "Siphon Life", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136188 },
                [12] = { ["name"] = "Improved Drain Mana", ["tier"] = 4, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 136208 },
                [11] = { ["name"] = "Nightfall", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 136223 },
                [10] = { ["name"] = "Grim Reach", ["tier"] = 4, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136127 },
            },
            [2] = {
                [14] = { ["name"] = "Improved Firestone", ["tier"] = 5, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 132386 },
                [1] = { ["name"] = "Improved Healthstone", ["tier"] = 1, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135230 },
                [8] = { ["isExceptional"] = 1, ["name"] = "Fel Domination", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136082 },
                [3] = { ["name"] = "Demonic Embrace", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136172 },
                [2] = { ["name"] = "Improved Imp", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 136218 },
                [5] = { ["name"] = "Improved Voidwalker", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 136221 },
                [4] = { ["name"] = "Improved Health Funnel", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136168 },
                [7] = { ["name"] = "Improved Sayaad", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 4352493 },
                [6] = { ["name"] = "Fel Intellect", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135932 },
                [9] = { ["name"] = "Fel Stamina", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136121 },
                [15] = { ["name"] = "Master Demonologist", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136203 },
                [16] = { ["isExceptional"] = 1, ["name"] = "Soul Link", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136160 },
                [17] = { ["name"] = "Improved Spellstone", ["tier"] = 7, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 134131 },
                [13] = { ["isExceptional"] = 1, ["name"] = "Demonic Sacrifice", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136184 },
                [12] = { ["name"] = "Improved Enslave Demon", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 5, ["texture"] = 136154 },
                [11] = { ["name"] = "Unholy Power", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136206 },
                [10] = { ["name"] = "Master Summoner", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 136164 },
            },
            [3] = {
                [1] = { ["name"] = "Improved Shadow Bolt", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136197 },
                [8] = { ["isExceptional"] = 1, ["name"] = "Shadowburn", ["tier"] = 3, ["id"] = 0, ["column"] = 4, ["maxRank"] = 1, ["texture"] = 136191 },
                [3] = { ["name"] = "Bane", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136146 },
                [2] = { ["name"] = "Cataclysm", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135831 },
                [5] = { ["name"] = "Improved Firebolt", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135809 },
                [4] = { ["name"] = "Aftermath", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135805 },
                [7] = { ["name"] = "Devastation", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135813 },
                [6] = { ["name"] = "Improved Lash of Pain", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 136136 },
                [9] = { ["name"] = "Intensity", ["tier"] = 4, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135819 },
                [15] = { ["name"] = "Emberstorm", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135826 },
                [16] = { ["isExceptional"] = 1, ["name"] = "Conflagrate", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135807 },
                [14] = { ["name"] = "Ruin", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 136207 },
                [13] = { ["name"] = "Improved Immolate", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 135817 },
                [12] = { ["name"] = "Pyroclasm", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135830 },
                [11] = { ["name"] = "Improved Searing Pain", ["tier"] = 4, ["id"] = 0, ["column"] = 4, ["maxRank"] = 5, ["texture"] = 135827 },
                [10] = { ["name"] = "Destructive Reach", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 136133 },
            },
        },
        ["ROGUE"] = {
            [1] = {
                [1] = { ["name"] = "Improved Eviscerate", ["tier"] = 1, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 132292 },
                [3] = { ["name"] = "Malice", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 132277 },
                [2] = { ["name"] = "Remorseless Attacks", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 132151 },
                [5] = { ["name"] = "Murder", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 136147 },
                [4] = { ["name"] = "Ruthlessness", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 132122 },
                [7] = { ["isExceptional"] = 1, ["name"] = "Relentless Strikes", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 1, ["texture"] = 132340 },
                [6] = { ["name"] = "Improved Slice and Dice", ["tier"] = 2, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 132306 },
                [9] = { ["name"] = "Lethality", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 132109 },
                [8] = { ["name"] = "Improved Expose Armor", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 132354 },
                [15] = { ["name"] = "Vigor", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136023 },
                [14] = { ["name"] = "Seal Fate", ["tier"] = 6, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136130 },
                [13] = { ["name"] = "Improved Kidney Shot", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 132298 },
                [12] = { ["isExceptional"] = 1, ["name"] = "Cold Blood", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135988 },
                [11] = { ["name"] = "Improved Poisons", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 132273 },
                [10] = { ["name"] = "Vile Poisons", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 132293 },
            },
            [2] = {
                [19] = { ["isExceptional"] = 1, ["name"] = "Adrenaline Rush", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136206 },
                [18] = { ["name"] = "Aggression", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 132275 },
                [9] = { ["name"] = "Improved Sprint", ["tier"] = 3, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 132307 },
                [1] = { ["name"] = "Improved Gouge", ["tier"] = 1, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 132155 },
                [15] = { ["name"] = "Sword Specialization", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135328 },
                [3] = { ["name"] = "Lightning Reflexes", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136047 },
                [2] = { ["name"] = "Improved Sinister Strike", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 136189 },
                [5] = { ["name"] = "Deflection", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 132269 },
                [4] = { ["name"] = "Improved Backstab", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 132090 },
                [7] = { ["name"] = "Endurance", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136205 },
                [6] = { ["name"] = "Precision", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 132222 },
                [14] = { ["isExceptional"] = 1, ["name"] = "Blade Flurry", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132350 },
                [8] = { ["isExceptional"] = 1, ["name"] = "Riposte", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132336 },
                [16] = { ["name"] = "Fist Weapon Specialization", ["tier"] = 5, ["id"] = 0, ["column"] = 4, ["maxRank"] = 5, ["texture"] = 132938 },
                [17] = { ["name"] = "Weapon Expertise", ["tier"] = 6, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 135882 },
                [13] = { ["name"] = "Mace Specialization", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 5, ["texture"] = 133476 },
                [12] = { ["name"] = "Dual Wield Specialization", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 132147 },
                [11] = { ["name"] = "Dagger Specialization", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 135641 },
                [10] = { ["name"] = "Improved Kick", ["tier"] = 4, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 132219 },
            },
            [3] = {
                [9] = { ["name"] = "Setup", ["tier"] = 4, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 136056 },
                [1] = { ["name"] = "Master of Deception", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136129 },
                [15] = { ["isExceptional"] = 1, ["name"] = "Hemorrhage", ["tier"] = 5, ["id"] = 0, ["column"] = 4, ["maxRank"] = 1, ["texture"] = 136168 },
                [3] = { ["name"] = "Sleight of Hand", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 132294 },
                [2] = { ["name"] = "Opportunity", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 132366 },
                [5] = { ["name"] = "Camouflage", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 132320 },
                [4] = { ["name"] = "Elusiveness", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 135994 },
                [7] = { ["isExceptional"] = 1, ["name"] = "Ghostly Strike", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136136 },
                [6] = { ["name"] = "Initiative", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 136159 },
                [14] = { ["name"] = "Dirty Deeds", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 136220 },
                [8] = { ["name"] = "Improved Ambush", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 132282 },
                [16] = { ["name"] = "Deadliness", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135540 },
                [17] = { ["isExceptional"] = 1, ["name"] = "Premeditation", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136183 },
                [13] = { ["isExceptional"] = 1, ["name"] = "Preparation", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136121 },
                [12] = { ["name"] = "Heightened Senses", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 132089 },
                [11] = { ["name"] = "Serrated Blades", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 135315 },
                [10] = { ["name"] = "Improved Sap", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 132310 },
            },
        },
        ["DRUID"] = {
            [1] = {
                [1] = { ["name"] = "Improved Wrath", ["tier"] = 1, ["id"] = 0, ["column"] = 1, ["maxRank"] = 5, ["texture"] = 136006 },
                [15] = { ["name"] = "Moonfury", ["tier"] = 6, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136057 },
                [3] = { ["name"] = "Improved Nature's Grasp", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 4, ["texture"] = 136063 },
                [2] = { ["isExceptional"] = 1, ["name"] = "Nature's Grasp", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136063 },
                [5] = { ["name"] = "Improved Moonfire", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136096 },
                [4] = { ["name"] = "Improved Entangling Roots", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 136100 },
                [7] = { ["name"] = "Natural Shapeshifter", ["tier"] = 2, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 136116 },
                [6] = { ["name"] = "Natural Weapons", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135138 },
                [9] = { ["isExceptional"] = 1, ["name"] = "Omen of Clarity", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 136017 },
                [8] = { ["name"] = "Improved Thorns", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 136104 },
                [16] = { ["isExceptional"] = 1, ["name"] = "Moonkin Form", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136036 },
                [14] = { ["name"] = "Moonglow", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 136087 },
                [13] = { ["name"] = "Nature's Grace", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136062 },
                [12] = { ["name"] = "Improved Starfire", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135753 },
                [11] = { ["name"] = "Vengeance", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136075 },
                [10] = { ["name"] = "Nature's Reach", ["tier"] = 3, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 136065 },
            },
            [2] = {
                [1] = { ["name"] = "Ferocity", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 132190 },
                [15] = { ["name"] = "Heart of the Wild", ["tier"] = 6, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 135879 },
                [3] = { ["name"] = "Feral Instinct", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 5, ["texture"] = 132089 },
                [2] = { ["name"] = "Feral Aggression", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 132121 },
                [5] = { ["name"] = "Thick Hide", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 134355 },
                [4] = { ["name"] = "Brutal Impact", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 2, ["texture"] = 132114 },
                [7] = { ["isExceptional"] = 1, ["name"] = "Feral Charge", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 132183 },
                [6] = { ["name"] = "Feline Swiftness", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136095 },
                [9] = { ["name"] = "Improved Shred", ["tier"] = 4, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136231 },
                [8] = { ["name"] = "Sharpened Claws", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 134297 },
                [16] = { ["isExceptional"] = 1, ["name"] = "Leader of the Pack", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136112 },
                [14] = { ["isExceptional"] = 1, ["name"] = "Faerie Fire (Feral)", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 136033 },
                [13] = { ["name"] = "Savage Fury", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 132141 },
                [12] = { ["name"] = "Primal Fury", ["tier"] = 4, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 132278 },
                [11] = { ["name"] = "Blood Frenzy", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 132152 },
                [10] = { ["name"] = "Predatory Strikes", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 132185 },
            },
            [3] = {
                [1] = { ["name"] = "Improved Mark of the Wild", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136078 },
                [3] = { ["name"] = "Improved Healing Touch", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 5, ["texture"] = 136041 },
                [2] = { ["name"] = "Furor", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135881 },
                [5] = { ["name"] = "Improved Enrage", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 132126 },
                [4] = { ["name"] = "Nature's Focus", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136042 },
                [7] = { ["isExceptional"] = 1, ["name"] = "Insect Swarm", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 136045 },
                [6] = { ["name"] = "Reflection", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 135863 },
                [9] = { ["name"] = "Tranquil Spirit", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 135900 },
                [8] = { ["name"] = "Subtlety", ["tier"] = 3, ["id"] = 0, ["column"] = 4, ["maxRank"] = 5, ["texture"] = 132150 },
                [15] = { ["isExceptional"] = 1, ["name"] = "Swiftmend", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 134914 },
                [14] = { ["name"] = "Improved Regrowth", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136085 },
                [13] = { ["name"] = "Improved Tranquility", ["tier"] = 5, ["id"] = 0, ["column"] = 4, ["maxRank"] = 2, ["texture"] = 136107 },
                [12] = { ["name"] = "Gift of Nature", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136074 },
                [11] = { ["isExceptional"] = 1, ["name"] = "Nature's Swiftness", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 1, ["texture"] = 136076 },
                [10] = { ["name"] = "Improved Rejuvenation", ["tier"] = 4, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 136081 },
            },
        },
        ["SHAMAN"] = {
            [1] = {
                [1] = { ["name"] = "Convection", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136116 },
                [3] = { ["name"] = "Earth's Grasp", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136097 },
                [2] = { ["name"] = "Concussion", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135807 },
                [5] = { ["name"] = "Call of Flame", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 3, ["texture"] = 135817 },
                [4] = { ["name"] = "Elemental Warding", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 136094 },
                [7] = { ["name"] = "Reverberation", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 135850 },
                [6] = { ["isExceptional"] = 1, ["name"] = "Elemental Focus", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 1, ["texture"] = 136170 },
                [9] = { ["name"] = "Improved Fire Totems", ["tier"] = 4, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135824 },
                [8] = { ["name"] = "Call of Thunder", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136014 },
                [15] = { ["isExceptional"] = 1, ["name"] = "Elemental Mastery", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 136115 },
                [14] = { ["name"] = "Lightning Mastery", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135990 },
                [13] = { ["name"] = "Elemental Fury", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135830 },
                [12] = { ["name"] = "Storm Reach", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136099 },
                [11] = { ["name"] = "Elemental Devastation", ["tier"] = 4, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 135791 },
                [10] = { ["name"] = "Eye of the Storm", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 136032 },
            },
            [2] = {
                [1] = { ["name"] = "Ancestral Knowledge", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136162 },
                [8] = { ["name"] = "Two-Handed Axes and Maces", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 132401 },
                [3] = { ["name"] = "Guardian Totems", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136098 },
                [2] = { ["name"] = "Shield Specialization", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 134952 },
                [5] = { ["name"] = "Improved Ghost Wolf", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 2, ["texture"] = 136095 },
                [4] = { ["name"] = "Thundering Strikes", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 132325 },
                [7] = { ["name"] = "Enhancing Totems", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136023 },
                [6] = { ["name"] = "Improved Lightning Shield", ["tier"] = 2, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 136051 },
                [9] = { ["name"] = "Anticipation", ["tier"] = 3, ["id"] = 0, ["column"] = 4, ["maxRank"] = 5, ["texture"] = 136056 },
                [15] = { ["name"] = "Weapon Mastery", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 132215 },
                [16] = { ["isExceptional"] = 1, ["name"] = "Stormstrike", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135963 },
                [14] = { ["name"] = "Parry", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 132269 },
                [13] = { ["name"] = "Elemental Weapons", ["tier"] = 5, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 135814 },
                [12] = { ["name"] = "Improved Weapon Totems", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 135792 },
                [11] = { ["name"] = "Toughness", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135892 },
                [10] = { ["name"] = "Flurry", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 132152 },
            },
            [3] = {
                [1] = { ["name"] = "Improved Healing Wave", ["tier"] = 1, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136052 },
                [3] = { ["name"] = "Improved Reincarnation", ["tier"] = 2, ["id"] = 0, ["column"] = 1, ["maxRank"] = 2, ["texture"] = 136080 },
                [2] = { ["name"] = "Tidal Focus", ["tier"] = 1, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135859 },
                [5] = { ["name"] = "Totemic Focus", ["tier"] = 2, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136057 },
                [4] = { ["name"] = "Ancestral Healing", ["tier"] = 2, ["id"] = 0, ["column"] = 2, ["maxRank"] = 3, ["texture"] = 136109 },
                [7] = { ["name"] = "Healing Focus", ["tier"] = 3, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136043 },
                [6] = { ["name"] = "Nature's Guidance", ["tier"] = 3, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 135860 },
                [9] = { ["name"] = "Healing Grace", ["tier"] = 3, ["id"] = 0, ["column"] = 4, ["maxRank"] = 3, ["texture"] = 136041 },
                [8] = { ["name"] = "Totemic Mastery", ["tier"] = 3, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 136069 },
                [15] = { ["isExceptional"] = 1, ["name"] = "Mana Tide Totem", ["tier"] = 7, ["id"] = 0, ["column"] = 2, ["maxRank"] = 1, ["texture"] = 135861 },
                [14] = { ["name"] = "Purification", ["tier"] = 6, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 135865 },
                [13] = { ["isExceptional"] = 1, ["name"] = "Nature's Swiftness", ["tier"] = 5, ["id"] = 0, ["column"] = 3, ["maxRank"] = 1, ["texture"] = 136076 },
                [12] = { ["name"] = "Healing Way", ["tier"] = 5, ["id"] = 0, ["column"] = 1, ["maxRank"] = 3, ["texture"] = 136044 },
                [11] = { ["name"] = "Tidal Mastery", ["tier"] = 4, ["id"] = 0, ["column"] = 3, ["maxRank"] = 5, ["texture"] = 136107 },
                [10] = { ["name"] = "Restorative Totems", ["tier"] = 4, ["id"] = 0, ["column"] = 2, ["maxRank"] = 5, ["texture"] = 136053 },
            },
        },
        ["DEATHKNIGHT"] = {
            [1] = {},
            [2] = {},
            [3] = {},
        },
    }
end

local talents_table = lib.talents_table
-- glyphs_table / glyph_r_tbl are published on `lib` above (the Glyph APIs were
-- not part of this port) but kept as locals so the ported block is self-contained.

--------------------------------------------------------------------------
-- ClassicInspector:GetNumTalentsByClass(class, tabIndex)
--
--  Parameters
--     @string class               - english class name in uppercase e.g. "WARRIOR"
--     @number tabIndex            - talent tab index (1-3)
--
--  Returns
--     @number numTalents          - number of talents in tab
--
function lib:GetNumTalentsByClass(class, tabIndex)
    assert(
        class == "WARRIOR" or class == "PALADIN" or class == "HUNTER" or class == "ROGUE" or class == "PRIEST" or
        class == "SHAMAN" or
        class == "MAGE" or class == "WARLOCK" or class == "DRUID" or (isWotlk and class == "DEATHKNIGHT"),
        "invalid class")
    local n = tonumber(tabIndex) or 0
    assert(n > 0 and n < 4, "tabIndex is not a valid number (1-3)")
    return #talents_table[class][tabIndex]
end

--------------------------------------------------------------------------
-- ClassicInspector:GetTalentInfoByClass(class, tabIndex, talentIndex)
--
--  Parameters
--     @string class               - english class name in uppercase e.g. "WARRIOR"
--     @number tabIndex            - talent tab index (1-3)
--     @number talentIndex         - ranging from 1 to GetNumTalents(tabIndex). counted from left to right, top to bottom.
--
--  Returns
--     @string name                - name of the talent
--     @number iconTexture         - fileID of icon texture
--     @number tier                - the row/tier that the talent sits on
--     @number column              - the column that the talent sits on
--     @number rank                - always 0
--     @number maxRank             - the maximum amount of talent points for a talent
--     @number isExceptional       - 1 if the talent is the ultimate talent, e.g. Lightwell, otherwise returns nil
--     @number available           - always 1
--     @number talentID            - talent ID
--
function lib:GetTalentInfoByClass(class, tabIndex, talentIndex)
    assert(
        class == "WARRIOR" or class == "PALADIN" or class == "HUNTER" or class == "ROGUE" or class == "PRIEST" or
        class == "SHAMAN" or
        class == "MAGE" or class == "WARLOCK" or class == "DRUID" or (isWotlk and class == "DEATHKNIGHT"),
        "invalid class")
    tabIndex = tonumber(tabIndex) or 0
    assert(tabIndex > 0 and tabIndex < 4, "tabIndex is not a valid number (1-3)")
    talentIndex = tonumber(talentIndex) or 0
    assert(talentIndex > 0 and talentIndex <= MAX_TALENTS_PER_TAB, "talentIndex is not a valid number")
    -- Guard the per-tab bound: MAX_TALENTS_PER_TAB caps every class, but
    -- individual tabs hold fewer talents. Indexing past a tab's real count
    -- previously raised "attempt to index a nil value" (raw talent.name).
    local talent = talents_table[class][tabIndex][talentIndex]
    if (not talent) then
        return nil
    end
    return talent.name, talent.texture, talent.tier, talent.column, 0, talent.maxRank, talent.isExceptional,
        talent.available, talent.id
end

local function getPlayerGUID(arg)
    if (not arg) then return nil end
    if (type(arg) == "string") then
        if (string.find(arg, "Player-", 1, true) == 1) then
            return arg
        end
        if (C_PlayerInfo and C_PlayerInfo.GUIDIsPlayer and C_PlayerInfo.GUIDIsPlayer(arg)) then
            return arg
        end
    end
    if (UnitIsPlayer and UnitIsPlayer(arg)) then
        return UnitGUID(arg)
    end
    return nil
end

-- Talent points, Classic family (Classic Era, TBC Anniversary, Titanforge).
--
-- Ported from the working LibClassicInspector. That library does NOT read
-- pointsSpent off a shim; it sums each talent's `rank`, which is the same
-- total pointsSpent reports but is read through a path that is stable across
-- the loadDeprecationFallbacks CVar being on or off:
--
--   talents[tab] += select(5, GetTalentInfo(tab, talent, isInspect, isPet, group))
--
-- The earlier port of this file replaced that with a getTalentTabPoints helper
-- that read the wrong return slots (pcall prepends a boolean, shifting every
-- position by one), so it captured `icon` instead of the point total and the
-- tooltip printed icon fileIDs such as [132164/132222/132215] as talent points.
-- That helper is gone; there is now exactly one Classic talent path and it is
-- the one from the working addon.
--
-- GetTalentInfo returns:
--   name, icon, tier, column, rank, maxRank, isExceptional, available, talentID
-- so `rank` is position 5.

local rawGetTalentInfo = _G.GetTalentInfo

local function GetTalentInfo(tabIndex, talentIndex, isInspect, isPet, groupIndex)
    if (rawGetTalentInfo) then
        local ok, a, b, c, d, e, f, g, h, i = pcall(rawGetTalentInfo, tabIndex, talentIndex,
            isInspect, isPet, groupIndex)
        if (ok) then
            return a, b, c, d, e, f, g, h, i
        end
    end
    if (C_SpecializationInfo and C_SpecializationInfo.GetTalentInfo) then
        local query = {
            specializationIndex = tabIndex,
            talentIndex = talentIndex,
            isInspect = isInspect and true or false,
            isPet = isPet and true or false,
            groupIndex = groupIndex or 1,
        }
        local ok, info = pcall(C_SpecializationInfo.GetTalentInfo, query)
        if (ok and info) then
            return info.name, info.icon, info.tier, info.column, info.rank, info.maxRank,
                info.isExceptional, info.available, info.talentID
        end
    end
    return nil, nil, nil, nil, 0, 0, nil, nil, nil
end

-- Dual specialization = the client has more than one talent GROUP for a
-- character. TBC Anniversary, WotLK and SoD / Classic Era do; Retail and WoW
-- Forever do not -- a character has exactly one specialization there, and
-- GetSpecialization(..., 2) simply echoes group 1, which produced a second
-- identical specialization line and a second icon.
--
-- The port carried the Classic-only library's predicate over verbatim:
--     isWotlk or isTBC or (C_SpecializationInfo ~= nil) or (GetNumTalentGroups ~= nil)
-- Every one of those terms is true on modern -- C_SpecializationInfo is
-- referenced on all five branches, and GetNumTalentGroups exists on Retail too --
-- so the port claimed dual spec everywhere. It was correct for a library that
-- only ever ran on the Classic family, and wrong the moment the port added
-- modern. The family flags are the honest test: they are what actually
-- distinguishes "two talent groups" from "one".
local hasDualSpec = isClassic or isTBC or isWotlk

local function getNumTalents(tabIndex, isInspect, isPet)
    if (_G.GetNumTalents) then
        local ok, n = pcall(_G.GetNumTalents, tabIndex, isInspect, isPet)
        if (ok and type(n) == "number" and n > 0) then
            return n
        end
    end
    return 0
end

-- Total points invested in one talent tab, by summing each talent's rank.
-- This is the same number GetSpecializationInfo reports as pointsSpent, so the
-- [p1/p2/p3] readout is identical either way.
local function getTalentTabPoints(tabIndex, isInspect, isPet, groupIndex)
    local total = 0
    local numTalents = getNumTalents(tabIndex, isInspect, isPet)
    if (numTalents > MAX_TALENTS_PER_TAB) then
        numTalents = MAX_TALENTS_PER_TAB
    end
    for j = 1, numTalents do
        local _, _, _, _, rank = GetTalentInfo(tabIndex, j, isInspect, isPet, groupIndex)
        if (type(rank) == "number") then
            total = total + rank
        end
    end
    return total
end

-- Points for all three tabs of one group, as an indexed table.
local function getTabPointsForGroup(isInspect, isPet, groupIndex)
    return {
        getTalentTabPoints(1, isInspect, isPet, groupIndex),
        getTalentTabPoints(2, isInspect, isPet, groupIndex),
        getTalentTabPoints(3, isInspect, isPet, groupIndex),
    }
end

-- Which specialization group is currently active. `isInspect` selects the
-- inspected unit's group rather than the player's.
-- Ported from the working LibClassicInspector (GetActiveSpecGroupFor).
local function GetActiveSpecGroupFor(isInspect)
    if (C_SpecializationInfo and C_SpecializationInfo.GetActiveSpecGroup) then
        local ok, g = pcall(C_SpecializationInfo.GetActiveSpecGroup, isInspect and true or false, false)
        if (ok and type(g) == "number" and g > 0) then
            return g
        end
    end
    if (_G.GetActiveTalentGroup) then
        local ok, g = pcall(_G.GetActiveTalentGroup, isInspect and true or false, nil)
        if (ok and type(g) == "number" and g > 0) then
            return g
        end
    end
    return 1
end

---------------------------------------------------------------------------
-- Modern (Retail / WoW Forever) specialization + talent points
---------------------------------------------------------------------------
-- Retail and WoW Forever have no GetNumTalentTabs at all, so the talent-tab
-- path above cannot run there. They do, however, expose everything needed:
-- C_SpecializationInfo.GetSpecializationInfo has the SAME 7-argument signature
-- and the SAME 10-value return on live, forever and titanforge, with
-- pointsSpent at position 7 and previewPointsSpent at position 9. So the
-- equivalent of "points in tab N" is "points spent in specialization N".
--
-- Blizzard's own inspect form is the reference:
--   C_SpecializationInfo.GetSpecializationInfo(specIndex, isInspect, isPet,
--       inspectTarget, gender, groupIndex, classID)
-- (CooldownViewerUtil.lua:73 on live).

local function getModernSpecInfo(specIndex, isInspect, isPet, inspectTarget, sex, groupIndex, classID)
    if (not (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo)) then
        return nil
    end
    local ok, specID, name, _, icon, _, _, pointsSpent, _, previewPointsSpent =
        pcall(C_SpecializationInfo.GetSpecializationInfo, specIndex, isInspect, isPet,
            inspectTarget, sex, groupIndex, classID)
    if (not ok) then
        return nil
    end
    return {
        specID = specID,
        name = name,
        icon = icon,
        points = (tonumber(pointsSpent) or 0) + (tonumber(previewPointsSpent) or 0),
    }
end

-- Resolves a live unit's specialization data on the modern API.
-- Returns specIndex (1-based, the form GetSpecializationName indexes by),
-- specID, the engine's localized name/icon, and points[1..n].
local function getModernSpecData(unit, groupIndex)
    if (not (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization)) then
        return nil
    end
    if (not unit or not UnitExists or not UnitExists(unit)) then
        return nil
    end

    local isSelf = (unit == "player")
    groupIndex = groupIndex or 1

    -- C_SpecializationInfo.GetSpecialization(isInspect, isPet, specGroupIndex,
    -- specializationIndex) is the only group-aware form. GetInspectSpecialization
    -- takes just a unit and therefore cannot tell group 1 from group 2, which is
    -- why inspecting a dual-spec'd player used to report the same spec for both.
    local activeSpecID
    local specOk, specId = pcall(C_SpecializationInfo.GetSpecialization, not isSelf, false, groupIndex, 1)
    if (specOk) then activeSpecID = specId end

    -- Fallbacks for clients where the group-aware call returns nothing.
    if ((type(activeSpecID) ~= "number" or activeSpecID <= 0) and isSelf) then
        if (_G.GetSpecialization) then
            local gOk, gId = pcall(_G.GetSpecialization, false, nil, groupIndex)
            if (gOk and type(gId) == "number" and gId > 0) then activeSpecID = gId end
        end
    end
    if ((type(activeSpecID) ~= "number" or activeSpecID <= 0)
            and C_SpecializationInfo.GetInspectSpecialization) then
        -- Secret-restricted on Retail (SecretWhenUnitIdentityRestricted), which
        -- is why this has always been pcall'd.
        local iOk, iId = pcall(C_SpecializationInfo.GetInspectSpecialization, unit)
        if (iOk and type(iId) == "number" and iId > 0) then activeSpecID = iId end
    end
    if (type(activeSpecID) ~= "number" or activeSpecID <= 0) then
        return nil
    end

    -- classID is required for the inspect form. Reverse-derive it from the spec
    -- rather than parsing a class token, so no client-version-specific class
    -- token table is needed.
    local classID
    if (C_SpecializationInfo.GetClassIDFromSpecID) then
        local ok, id = pcall(C_SpecializationInfo.GetClassIDFromSpecID, activeSpecID)
        if (ok) then classID = id end
    end

    local specCount = 3
    if (classID and C_SpecializationInfo.GetNumSpecializationsForClassID) then
        local ok, n = pcall(C_SpecializationInfo.GetNumSpecializationsForClassID, classID)
        if (ok and type(n) == "number" and n > 0) then
            specCount = n
        end
    end

    local sex = _G.UnitSex and _G.UnitSex(unit) or nil
    local points = {}
    local specIndex, specName, specIcon
    for i = 1, specCount do
        local info = getModernSpecInfo(i, not isSelf, false, isSelf and nil or unit, sex,
            groupIndex, classID)
        if (info) then
            points[i] = info.points
            if (info.specID == activeSpecID) then
                specIndex = i
                specName = info.name
                specIcon = info.icon
            end
        end
    end

    if (not specIndex) then
        -- Active spec not in the enumerated range: fall back to the spec with
        -- the most points invested, which is the same rule the talent-tab path
        -- uses to pick a tab.
        local maxPts = -1
        for i = 1, specCount do
            local p = points[i] or 0
            if (p > maxPts) then
                maxPts = p
                specIndex = i
            end
        end
        if (not specIndex) then return nil end
    end

    if (not specName and C_SpecializationInfo.GetSpecializationInfo and specIndex) then
        local info = getModernSpecInfo(specIndex, not isSelf, false, isSelf and nil or unit, sex,
            groupIndex, classID)
        specName = info and info.name
        specIcon = info and info.icon
    end

    return {
        specIndex = specIndex,
        specID = activeSpecID,
        specName = specName,
        specIcon = specIcon,
        points = points,
        specCount = specCount,
    }
end

---------------------------------------------------------------------------
-- Specialization icon
---------------------------------------------------------------------------
-- C_SpecializationInfo.GetTalentInfo has an identical signature and an
-- identical TalentInfoResult on all five clients, and TalentInfoResult.icon is
-- a fileID everywhere, which is why the result is drawn with a Texture rather
-- than a |T escape (|T accepts only a texture path or an atlas).
--
-- What differs is the QUERY. Two forms ship, selected by the FrameXML toc:
--
--   Form A -- Classic Era (Blizzard_FrameXML_Vanilla), TBC Anniversary
--             (Blizzard_FrameXML_TBC) and Titanforge (wrath) all load
--             Vanilla\TalentFrameBase.lua, which queries by talent index:
--                 Vanilla/TalentFrameBase.lua
--                   talentInfoQuery.specializationIndex = selectedTab
--                   talentInfoQuery.talentIndex = i        -- 1..MAX_NUM_TALENT_S
--                   talentInfoQuery.isInspect / isPet / groupIndex
--
--   Form B -- Retail and WoW Forever load [Family]\TalentFrameBase.lua
--             (Mainline\), which queries by tier and column:
--                 Mainline/TalentFrameBase.lua
--                   talentInfoQuery.tier = tier
--                   talentInfoQuery.column = column
--                   talentInfoQuery.groupIndex / isInspect / target
--
-- The preferred form is chosen by family, and the other is tried only if the
-- first yields nothing, so a wrong guess about the client degrades to a slower
-- lookup rather than a missing icon.

local MAX_LINEAR_TALENTS = 40 -- Vanilla/TalentFrameBase.lua: MAX_NUM_TALENTS
local MAX_GRID_TIERS = 20
local MAX_GRID_COLUMNS = 5
-- Hard ceiling on GetTalentInfo calls per resolution, so a client that answers
-- every query can never turn a tooltip hover into a long pcall loop.
local MAX_ICON_QUERIES = 120

local function queryTalentIcon(specIndex, groupIndex, isInspect, target)
    if (not (C_SpecializationInfo and C_SpecializationInfo.GetTalentInfo)) then
        return nil, false
    end

    local budget = MAX_ICON_QUERIES
    local bestIcon, bestTier = nil, -1

    local function consider(info)
        if (type(info) ~= "table" or type(info.icon) == "nil") then
            return
        end
        if (info.icon == 0 or info.icon == "") then
            return
        end
        -- Signature/exceptional talent is the most recognisable stand-in for a
        -- specialization, so it wins outright; otherwise prefer the deepest tier.
        if (info.isExceptional) then
            bestIcon, bestTier = info.icon, math.huge
        elseif ((tonumber(info.tier) or 0) > bestTier) then
            bestIcon, bestTier = info.icon, tonumber(info.tier) or 0
        end
    end

    local function run(query)
        if (budget <= 0) then return end
        budget = budget - 1
        local ok, info = pcall(C_SpecializationInfo.GetTalentInfo, query)
        if (ok) then
            consider(info)
        end
    end

    -- Form A: by linear talent index.
    local function linearPass()
        local count = MAX_LINEAR_TALENTS
        if (_G.GetNumTalents) then
            local ok, n = pcall(_G.GetNumTalents, specIndex, isInspect, false)
            if (ok and type(n) == "number" and n > 0 and n < count) then
                count = n
            end
        end
        for i = 1, count do
            run({
                specializationIndex = specIndex,
                talentIndex = i,
                isInspect = isInspect and true or false,
                isPet = false,
                groupIndex = groupIndex,
            })
        end
    end

    -- Form B: by tier and column.
    local function gridPass()
        for tier = 1, MAX_GRID_TIERS do
            local rowHit = false
            for column = 1, MAX_GRID_COLUMNS do
                local before = bestIcon
                run({
                    tier = tier,
                    column = column,
                    groupIndex = groupIndex,
                    isInspect = isInspect and true or false,
                    target = target,
                    specializationIndex = specIndex,
                })
                if (bestIcon ~= before) then
                    rowHit = true
                end
            end
            -- A fully empty tier means we are past the end of the tree; a
            -- partially filled one is normal (trees are not rectangles).
            if (budget <= 0) then return end
            if (not rowHit and tier > 2) then return end
        end
    end

    local preferLinear = (isClassic or isTBC or isWotlk)
    if (preferLinear) then
        linearPass()
        if (not bestIcon) then gridPass() end
    else
        gridPass()
        if (not bestIcon) then linearPass() end
    end

    return bestIcon, bestIcon ~= nil
end

local specializationIconCache = {}

-- Returns a Texture-ready icon for a specialization, or nil. MODERN CLIENTS
-- ONLY (Retail / WoW Forever).
--
-- Named GetModernSpecializationIcon, not GetSpecializationIcon: the latter is a
-- pre-existing stub further down this file that unconditionally returns nil, and
-- defining this one under the same name silently overwrote (or was overwritten
-- by) it depending on order.
--
-- Deliberately does not participate in the Classic path: the Classic icon
-- lookup in main.lua is the original, known-working one and is left untouched.
-- This exists purely because the two modern clients need a query form the
-- Classic code does not have.
--
--   specIndex  1-based specialization index (NOT a specID)
--   groupIndex spec group, 1 or 2
--   isInspect  true when reading another unit
--   target     that unit token, required for the grid query form
function lib:GetModernSpecializationIcon(specIndex, groupIndex, isInspect, target)
    -- Hard gate: never let this run on the Classic family.
    if (not (isRetail or isForever)) then
        return nil
    end
    if (not specIndex) then
        return nil
    end
    groupIndex = groupIndex or 1
    local key = table.concat({
        tostring(specIndex), tostring(groupIndex),
        isInspect and "i" or "s", tostring(target),
    }, "|")

    local cached = specializationIconCache[key]
    if (cached ~= nil) then
        -- `false` is the cached "no icon" answer; any other value is the icon.
        return cached or nil
    end

    local icon = queryTalentIcon(specIndex, groupIndex, isInspect, target)

    -- The fallback below is ONLY valid for the local player.
    --
    -- C_SpecializationInfo.GetSpecializationInfo is called here with no unit
    -- argument, so it always answers for the LOCAL player's spec at
    -- specIndex. Running it for an inspect target therefore painted the
    -- hovering player's own spec icon onto someone else -- reported as a
    -- "stray" icon, e.g. a warrior's arms appearing while hovering other
    -- characters. It only ever fires when the grid pass found nothing, which
    -- for an inspect target is the normal state for a player you have not
    -- inspected yet.
    --
    -- For an inspect target the honest answer is no icon. Returning the local
    -- player's icon is worse than returning nothing, because it is confidently
    -- wrong.
    if (icon == nil and not isInspect
            and C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo) then
        local ok, _, _, _, specIcon = pcall(C_SpecializationInfo.GetSpecializationInfo, specIndex)
        if (ok and (type(specIcon) == "number" or type(specIcon) == "string") and specIcon ~= 0) then
            icon = specIcon
        end
    end

    if (isInspect and icon == nil) then
        -- No talent data for this unit yet. Do NOT cache the miss: caching
        -- `false` here would make "no icon" stick for the rest of the session,
        -- so the icon would never appear even after their talents stream in and
        -- the answer becomes knowable. Skipping the write makes the next hover
        -- re-query, which is the only point at which the data can have changed.
        return nil
    end

    specializationIconCache[key] = icon or false
    return icon
end

function lib:InvalidateModernSpecializationIconCache()
    specializationIconCache = {}
end

local function createItemWrapper(link)
    if (not link) then return nil end
    if (_G.Item and _G.Item.CreateFromItemLink) then
        local ok, item = pcall(_G.Item.CreateFromItemLink, _G.Item, link)
        if (ok and item) then
            return item
        end
    end
    local itemID = tonumber(string.match(link, "item:(%d+)"))
    return {
        IsItemDataCached = function()
            return GetItemInfo(link) ~= nil
        end,
        GetItemLink = function()
            return link
        end,
        GetItemID = function()
            return itemID
        end,
        ContinueOnItemLoad = function(self, cb)
            if (self:IsItemDataCached()) then
                cb()
            elseif (C_Timer and C_Timer.After) then
                C_Timer.After(0.2, cb)
            end
        end,
        -- Must match ItemMixin's contract: same as ContinueOnItemLoad but
        -- returns a cancel function. main.lua repaints an uncached item tooltip
        -- through this, so without it the repaint is never registered at all on
        -- the fallback path -- pcall(item.ContinueWithCancelOnItemLoad, ...) sees
        -- a nil callee and silently declines.
        ContinueWithCancelOnItemLoad = function(self, cb)
            if (self:IsItemDataCached()) then
                cb()
                return function() end
            elseif (C_Timer and C_Timer.After) then
                local live = true
                C_Timer.After(0.2, function()
                    if (live) then
                        cb()
                    end
                end)
                return function()
                    live = false
                end
            end
            return function() end
        end,
    }
end

-- Builds talentPoints[group][tabIndex] for every group the client supports.
-- The old cache only ever stored group 1, so inspecting a dual-spec'd player
-- returned group 1's data for group 2 as well and the inactive spec could never
-- be distinguished from the active one.
local function buildGroupTalentPoints(isInspect, unit)
    local out = {}
    local groups = hasDualSpec and 2 or 1
    for g = 1, groups do
        out[g] = {
            getTalentTabPoints(1, isInspect, false, g),
            getTalentTabPoints(2, isInspect, false, g),
            getTalentTabPoints(3, isInspect, false, g),
        }
    end
    return out
end

-- specIndexByGroup[group] = the tab with the most points in that group.
local function buildSpecIndexByGroup(unit)
    local out = {}
    local groups = hasDualSpec and 2 or 1
    for g = 1, groups do
        local pts = getTabPointsForGroup(true, false, g)
        local maxPts, topTab = -1, 1
        for t = 1, 3 do
            local p = pts[t] or 0
            if (p > maxPts) then
                maxPts = p
                topTab = t
            end
        end
        out[g] = topTab
    end
    return out
end

-- Inspect requests share a single client channel with Blizzard and other addons.
local INSPECT_INTERVAL, INSPECT_TIMEOUT, REFRESH_INTERVAL = 2, 5, 10
local DEFER_TIMEOUT = 15
local MAX_ATTEMPTS, MAX_QUEUE, MAX_CACHE = 3, 20, 500
local queue, cacheOrder = {}, {}
local unitHints = {"target", "mouseover", "focus"}
local pending, externalGUID, externalUntil
local nextInspectTime, processing, sending = 0, false, false
for guid in pairs(lib.cache) do cacheOrder[#cacheOrder + 1] = guid end

local function plain(value)
    return not (_G.issecretvalue and _G.issecretvalue(value))
end

local function unitGUID(unit)
    if (not unit or not plain(unit)) then return nil end
    local ok, guid = pcall(UnitGUID, unit)
    if (ok and plain(guid) and type(guid) == "string") then return guid end
end

local function findUnit(guid, hint)
    if (hint and unitGUID(hint) == guid) then return hint end
    if (InspectFrame and unitGUID(InspectFrame.unit) == guid) then return InspectFrame.unit end
    for _, unit in ipairs(unitHints) do
        if (unitGUID(unit) == guid) then return unit end
    end
    for i = 1, 4 do
        local unit = "party" .. i
        if (unitGUID(unit) == guid) then return unit end
    end
    for i = 1, 40 do
        local unit = "raid" .. i
        if (unitGUID(unit) == guid) then return unit end
    end
end

local function cacheEntry(guid)
    local data = lib.cache[guid]
    if (not data) then
        data = {}
        lib.cache[guid] = data
        cacheOrder[#cacheOrder + 1] = guid
    end
    while (#cacheOrder > MAX_CACHE) do
        lib.cache[table.remove(cacheOrder, 1)] = nil
    end
    return data
end

local function fresh(guid)
    local data = lib.cache[guid]
    return data and data.inventoryTime and data.inventoryTime > 0
        and data.talentTime and time() - data.talentTime < REFRESH_INTERVAL
        and time() - data.inventoryTime < REFRESH_INTERVAL
end

local function cacheInventory(unit, guid)
    local data = cacheEntry(guid)
    local items, anyItem, complete = {}, false, true
    local getTexture = _G.GetInventoryItemTexture
    for slot = 1, 18 do
        local link = GetInventoryItemLink(unit, slot)
        if (not plain(link)) then return false end
        items[slot] = link
        if (link) then
            anyItem = true
        elseif (getTexture) then
            local texture = getTexture(unit, slot)
            if (not plain(texture)) then return false end
            -- Occupied slot whose link has not arrived yet, not an empty slot.
            if (texture) then complete = false end
        end
    end
    complete = complete and anyItem
    data.items = data.items or {}
    if (complete) then
        data.items = items
    else
        -- An empty/partial response must not erase previously loaded equipment.
        for slot, link in pairs(items) do data.items[slot] = link end
    end
    data.inventoryTime = complete and time() or 0
    data.time = data.inventoryTime -- Preserve the original cache field for consumers.
    return complete
end

local function cacheUnitData(unit, guid)
    local complete = cacheInventory(unit, guid)
    local data = cacheEntry(guid)
    -- Modern specialization API (Retail & Forever)
    -- pcall'd: Retail documents GetInspectSpecialization as
    -- SecretWhenUnitIdentityRestricted, and this runs straight from the
    -- INSPECT_READY handler. An uncaught throw here would abort cacheUnitData
    -- before it fires the INVENTORY_READY / TALENTS_READY callbacks below, so
    -- the tooltip's spec and achievement lines would silently never populate.
    if (C_SpecializationInfo and C_SpecializationInfo.GetInspectSpecialization) then
        -- Retail & WoW Forever. getModernSpecData handles the pcall for
        -- GetInspectSpecialization (Retail marks it secret-restricted, and this
        -- runs straight from the INSPECT_READY handler -- an uncaught throw
        -- would abort cacheUnitData before it fires the callbacks below, so the
        -- tooltip's spec and talent lines would silently never populate).
        --
        -- It also supplies the real specIndex. The old code hardcoded 1, which
        -- happened to be right for a class whose first spec is active and wrong
        -- for every other case, and it left data.talentPoints unset so the
        -- [p1/p2/p3] readout was always 0/0/0 here.
        local modern = getModernSpecData(unit, 1)
        if (modern) then
            data.specID = modern.specID
            data.specName = modern.specName
            data.specIcon = modern.specIcon
            data.specIndex = modern.specIndex
            -- Cached per group: talentPoints[group][tabIndex].
            data.talentPoints = buildGroupTalentPoints(true, unit)
            data.specIndexByGroup = buildSpecIndexByGroup(unit)
            data.activeGroup = GetActiveSpecGroupFor(true)
        end
    elseif (getNumTalentTabs() or _G.GetNumTalents) then
        -- Classic Era, SoD, TBC Anniversary, WotLK talent tabs
        data.talentPoints = buildGroupTalentPoints(true, unit)
        data.specIndexByGroup = buildSpecIndexByGroup(unit)
        data.activeGroup = GetActiveSpecGroupFor(true)
    end

    -- Achievements (WotLK / Retail)
    if (GetComparisonAchievementPoints) then
        local ok, pts = pcall(GetComparisonAchievementPoints)
        if (ok and pts and pts > 0) then
            data.achievements = pts
        end
    end

    data.talentTime = time()
    lib.callbacks:Fire("INVENTORY_READY", guid)
    lib.callbacks:Fire("TALENTS_READY", guid)
    return complete
end

local function enqueue(request)
    for _, entry in ipairs(queue) do
        if (entry.guid == request.guid) then return end
    end
    if (#queue >= MAX_QUEUE) then table.remove(queue, 1) end
    queue[#queue + 1] = request
end

local function retry(request)
    if (request.attempts < MAX_ATTEMPTS) then
        enqueue(request)
    else
        cacheEntry(request.guid).retryAfter = GetTime() + REFRESH_INTERVAL
    end
end

local function pumpQueue()
    if (processing or InCombatLockdown() or (InspectFrame and InspectFrame:IsShown())) then return end
    local now = GetTime()
    if (pending) then
        if (now < pending.sent + INSPECT_TIMEOUT) then return end
        local request = pending
        pending = nil
        retry(request)
    end
    if (now < nextInspectTime or (externalUntil and now < externalUntil)) then return end
    externalGUID, externalUntil = nil, nil
    for _ = 1, #queue do
        local request = table.remove(queue, 1)
        local unit = findUnit(request.guid, request.unit)
        if (not fresh(request.guid)) then
            local ok, allowed = false, false
            -- CanInspect can report UI errors; pcall cannot suppress those.
            -- Check distance first on every attempt, including queued retries.
            if (unit and type(CheckInteractDistance) == "function") then
                local rangeOK, inRange = pcall(CheckInteractDistance, unit, 1)
                if (rangeOK and plain(inRange) and inRange) then
                    ok, allowed = pcall(CanInspect, unit)
                end
            end
            if (ok and plain(allowed) and allowed) then
                request.deferUntil = nil
                request.unit, request.sent = unit, now
                request.attempts = request.attempts + 1
                pending = request
                nextInspectTime = now + INSPECT_INTERVAL
                sending = true
                local sent = pcall(NotifyInspect, unit)
                sending = false
                if (not sent) then
                    pending = nil
                    retry(request)
                end
                return
            end
            -- Keep transiently unavailable GUIDs, but let other players proceed.
            -- Repeated hovers must not extend this deadline indefinitely.
            request.deferUntil = request.deferUntil or (now + DEFER_TIMEOUT)
            if (now < request.deferUntil) then
                enqueue(request)
            else
                cacheEntry(request.guid).retryAfter = now + REFRESH_INTERVAL
            end
        end
    end
end

-- An external request supersedes our channel ownership, but not our queued work.
if (hooksecurefunc and type(_G.NotifyInspect) == "function") then
    hooksecurefunc("NotifyInspect", function(unit)
        local now = GetTime()
        nextInspectTime = now + INSPECT_INTERVAL
        if (not sending) then
            if (pending) then
                local request = pending
                pending = nil
                retry(request)
            end
            externalGUID, externalUntil = unitGUID(unit), now + INSPECT_TIMEOUT
        end
    end)
end

function lib:DoInspect(unitOrGUID)
    if (not unitOrGUID or not plain(unitOrGUID) or type(_G.NotifyInspect) ~= "function"
            or type(CanInspect) ~= "function") then return false end
    local guid = unitGUID(unitOrGUID)
    if (not guid and type(unitOrGUID) == "string" and unitOrGUID:find("Player-", 1, true) == 1) then
        guid = unitOrGUID
    end
    if (not guid or guid == unitGUID("player") or fresh(guid)) then return false end
    local data = lib.cache[guid]
    if (data and data.retryAfter and GetTime() < data.retryAfter) then return false end
    if (pending and pending.guid == guid) then return true end
    local unit = findUnit(guid, unitOrGUID)
    if (not unit or not UnitIsPlayer(unit)) then return false end
    enqueue({guid = guid, unit = unit, attempts = 0})
    pumpQueue()
    return true
end

frame:SetScript("OnEvent", function(_, event, value)
    if (not plain(value)) then return end
    if (event == "INSPECT_READY") then
        -- All supported clients send a GUID. Never infer it from a mutable token.
        local guid = value
        if (type(guid) ~= "string" or guid == unitGUID("player")) then return end
        local unit = findUnit(guid, pending and pending.unit)
        if (externalGUID == guid) then externalGUID, externalUntil = nil, nil end
        if (not unit) then return end
        processing = true
        local ok, complete = pcall(cacheUnitData, unit, guid)
        processing = false
        if (pending and pending.guid == guid) then
            local request = pending
            pending = nil
            if (not ok or not complete) then retry(request) end
        end
        if (not ok) then geterrorhandler()(complete) end
    elseif (event == "UNIT_INVENTORY_CHANGED") then
        local guid = unitGUID(value)
        if (not guid or guid == unitGUID("player") or not lib.cache[guid]) then return end
        -- Inventory updates do not carry talent ownership. Do not read another
        -- inspected player's talents through this event.
        processing = true
        local ok, err = pcall(function()
            cacheInventory(value, guid)
            lib.callbacks:Fire("INVENTORY_READY", guid)
        end)
        processing = false
        if (not ok) then geterrorhandler()(err) end
    end
    -- Do not ClearInspectPlayer: Blizzard and other listeners still need the data.
end)
frame:RegisterEvent("INSPECT_READY")
frame:RegisterEvent("UNIT_INVENTORY_CHANGED")

-- One scheduler for queued requests and timeouts, including clients without C_Timer.
local elapsedSinceTick = 0
frame:SetScript("OnUpdate", function(_, elapsed)
    elapsedSinceTick = elapsedSinceTick + elapsed
    if (elapsedSinceTick >= 1) then
        elapsedSinceTick = 0
        pumpQueue()
    end
end)

function lib:GetLastCacheTime(unitorguid)
    local guid = getPlayerGUID(unitorguid)
    if (guid and guid == UnitGUID("player")) then
        return time(), time()
    end
    local cached = guid and lib.cache[guid]
    if (cached) then
        return cached.talentTime or 0, cached.inventoryTime or 0
    end
    return 0, 0
end

function lib:GetInventoryItemMixin(unitorguid, slot)
    local guid = getPlayerGUID(unitorguid)
    if (not guid or not slot) then return nil end
    local link
    if (guid == UnitGUID("player")) then
        if (C_Item and C_Item.GetInventoryItemLink) then
            link = C_Item.GetInventoryItemLink("player", slot)
        elseif (GetInventoryItemLink) then
            link = GetInventoryItemLink("player", slot)
        end
    else
        local cached = lib.cache[guid]
        link = cached and cached.items and cached.items[slot]
    end
    if (link) then
        return createItemWrapper(link)
    end
    return nil
end

-- Returns a 1-based specialization INDEX, which is what every consumer indexes
-- lib.spec_table with. Note this is NOT the specialization ID: on the modern
-- clients the old code returned GetSpecialization() (an ID such as 71) here,
-- so lib.spec_table[class][71] was nil and the whole specialization line
-- silently disappeared on Retail and WoW Forever.
function lib:GetSpecialization(unitorguid, groupIndex)
    local guid = getPlayerGUID(unitorguid)
    if (not guid) then return nil end
    groupIndex = groupIndex or 1

    if (groupIndex == 2 and not hasDualSpec) then
        return nil
    end

    if (guid == UnitGUID("player")) then
        if (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) then
            local modern = getModernSpecData("player", groupIndex)
            if (modern) then
                return modern.specIndex
            end
        end
        -- Classic family: the tab with the most points invested in this group.
        local pts = getTabPointsForGroup(false, false, groupIndex)
        local maxPts, topTab = -1, 1
        for t = 1, 3 do
            local p = pts[t] or 0
            if (p > maxPts) then
                maxPts = p
                topTab = t
            end
        end
        return topTab
    end
    local cached = lib.cache[guid]
    if (not cached) then return 1 end
    local byGroup = cached.specIndexByGroup
    if (byGroup and byGroup[groupIndex]) then
        return byGroup[groupIndex]
    end
    return cached.specIndex or 1
end

-- Engine-provided, already-localized specialization name for a unit.
-- Prefers this over the built-in English spec_table so the spec line follows
-- the client's language on Retail and WoW Forever. Returns nil on the Classic
-- family, which has no equivalent, and nil whenever the unit has no spec.
function lib:GetLocalizedSpecName(unitorguid, groupIndex)
    local guid = getPlayerGUID(unitorguid)
    if (not guid) then return nil end
    groupIndex = groupIndex or 1

    if (guid == UnitGUID("player")) then
        if (C_SpecializationInfo and C_SpecializationInfo.GetInspectSpecialization) then
            local modern = getModernSpecData("player", groupIndex)
            if (modern) then
                return modern.specName
            end
        end
        return nil
    end
    local cached = lib.cache[guid]
    return cached and cached.specName or nil
end

-- Icon that goes with GetLocalizedSpecName, for the same reason.
function lib:GetLocalizedSpecIcon(unitorguid, groupIndex)
    local guid = getPlayerGUID(unitorguid)
    if (not guid) then return nil end
    groupIndex = groupIndex or 1

    if (guid == UnitGUID("player")) then
        if (C_SpecializationInfo and C_SpecializationInfo.GetInspectSpecialization) then
            local modern = getModernSpecData("player", groupIndex)
            if (modern) then
                return modern.specIcon
            end
        end
        return nil
    end
    local cached = lib.cache[guid]
    return cached and cached.specIcon or nil
end

function lib:GetSpecializationName(class, specIndex, localized)
    if (not class or not specIndex) then return nil end
    -- Note: this used to consult _G.TACOTIP_SPEC_NAMES first, on the premise
    -- that a per-locale table would override the built-in English one. Nothing
    -- ever wrote that global, so the lookup was always nil. The built-in table
    -- is now the single source; a locale override would need its own mechanism.
    local defaultTable = lib.spec_table and lib.spec_table[class]
    if (defaultTable and defaultTable[specIndex]) then
        return defaultTable[specIndex]
    end
    return nil
end

-- Always returned nil: it consulted _G.TACOTIP_SPEC_ICONS, which nothing ever
-- wrote. main.lua's getSpecializationIcon does the real work (built-in icon
-- table plus a per-class atlas), so this accessor is kept only as a stub for
-- API compatibility and reports the absence honestly.
function lib:GetSpecializationIcon(class, specIndex)
    return nil
end

-- Per-specialization points spent, as three return values.
--
-- Classic family: one value per talent tab.
-- Retail / Forever: one value per specialization, from GetSpecializationInfo's
-- pointsSpent + previewPointsSpent. This used to return 0/0/0 unconditionally
-- on those two clients, because the only implementation was the talent-tab
-- loop and GetNumTalentTabs does not exist there. That also suppressed the
-- readout entirely, because formatSpecializationText hides "[p1/p2/p3]" when
-- all three are zero on a non-Classic client.
function lib:GetTalentPoints(unitorguid, groupIndex)
    local guid = getPlayerGUID(unitorguid)
    if (not guid) then return 0, 0, 0 end
    groupIndex = groupIndex or 1
    if (groupIndex == 2 and not hasDualSpec) then
        return 0, 0, 0
    end

    if (guid == UnitGUID("player")) then
        if (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) then
            local modern = getModernSpecData("player", groupIndex)
            if (modern) then
                local pts = modern.points
                return pts[1] or 0, pts[2] or 0, pts[3] or 0
            end
        end
        local pts = getTabPointsForGroup(false, false, groupIndex)
        return pts[1] or 0, pts[2] or 0, pts[3] or 0
    end

    local cached = lib.cache[guid]
    local byGroup = cached and cached.talentPoints
    if (byGroup and type(byGroup[groupIndex]) == "table") then
        local pts = byGroup[groupIndex]
        return pts[1] or 0, pts[2] or 0, pts[3] or 0
    end
    -- Flat per-tab array from a cache written before the per-group shape.
    if (byGroup and type(byGroup[1]) == "number") then
        return byGroup[1] or 0, byGroup[2] or 0, byGroup[3] or 0
    end
    return 0, 0, 0
end

-- Which specialization group is active. The tooltip colours the active group's
-- specialization and greys the other one, so this has to be right for inspected
-- units too -- it used to return 1 unconditionally for them, which marked
-- group 1 as active even when the inspected player was on group 2.
function lib:GetActiveTalentGroup(unitorguid)
    local guid = getPlayerGUID(unitorguid)
    if (not guid) then return 1 end
    if (guid == UnitGUID("player")) then
        return GetActiveSpecGroupFor(false)
    end
    local cached = lib.cache[guid]
    local g = cached and cached.activeGroup
    if (type(g) == "number" and g > 0) then
        return g
    end
    return 1
end

function lib:GetTotalAchievementPoints(unitorguid)
    local guid = getPlayerGUID(unitorguid)
    if (guid and guid == UnitGUID("player") and GetTotalAchievementPoints) then
        return GetTotalAchievementPoints()
    end
    local cached = guid and lib.cache[guid]
    if (cached and cached.achievements) then
        return cached.achievements
    end
    if (GetComparisonAchievementPoints) then
        local ok, pts = pcall(GetComparisonAchievementPoints)
        if (ok and pts and pts > 0) then return pts end
    end
    return nil
end
