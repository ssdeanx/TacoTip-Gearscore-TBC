-- Pins the RUSSIAN specialization names in LibForeverInspector.
--
-- WHY THIS EXISTS. The ruRU block of `spec_table_localized` carried the
-- GERMAN Monk names ("Braumeister", "Nebelwirker", "Windläufer") and the
-- ENGLISH Demon Hunter and Evoker names ("Havoc", "Vengeance",
-- "Devastation", ...) -- placeholders that were never translated, so a
-- Russian client displayed German and English text where the game itself
-- says otherwise.
--
-- The expected names below are Blizzard's OWN Russian client strings, taken
-- from Blizzard's Russian class pages:
--   https://worldofwarcraft.blizzard.com/ru-ru/game/classes/monk
--   https://worldofwarcraft.blizzard.com/ru-ru/game/classes/demon-hunter
--   https://worldofwarcraft.blizzard.com/ru-ru/game/classes/evoker
-- (Monk: Хмелевар / Ткач туманов / Танцующий с ветром -- Demon Hunter:
-- Истребление / Месть -- Evoker: Опустошитель / Хранитель / Насыщатель.)
--
-- CROSS-CHECKED 2026-10-20 -- every name against THREE independent Russian
-- sources, all fetched:
--   1. Blizzard's own Russian class pages (the three URLs above);
--   2. Wowhead's Russian locale, one page per spec, whose heading carries the
--      client's own class+spec name --
--        www.wowhead.com/ru/talent-calc/monk/brewmaster
--            -> "Калькулятор талантов Монах «Хмелевар» Midnight"
--        www.wowhead.com/ru/talent-calc/monk/mistweaver
--            -> "Калькулятор талантов Монах «Ткач туманов» Midnight"
--        www.wowhead.com/ru/talent-calc/monk/windwalker
--            -> "Калькулятор талантов Монах «Танцующий с ветром» Midnight"
--        www.wowhead.com/ru/talent-calc/demon-hunter/havoc
--            -> "Калькулятор талантов Охотник на демонов «Истребление» Midnight"
--        www.wowhead.com/ru/talent-calc/demon-hunter/vengeance
--            -> "Калькулятор талантов Охотник на демонов «Месть» Midnight"
--        www.wowhead.com/ru/talent-calc/evoker/devastation
--            -> "Калькулятор талантов Пробудитель «Опустошитель» Midnight"
--        www.wowhead.com/ru/talent-calc/evoker/preservation
--            -> "Калькулятор талантов Пробудитель «Хранитель» Midnight"
--        www.wowhead.com/ru/talent-calc/evoker/augmentation
--            -> "Калькулятор талантов Пробудитель «Насыщатель» Midnight"
--   3. The CLIENT's own strings -- wago.tools' DB2 table ChrSpecialization,
--      build 12.1.7.70424, locale ruRU, Name_lang column, at OrderIndex 0/1/2:
--        ClassID 10 MONK        Хмелевар / Ткач туманов / Танцующий с ветром
--        ClassID 12 DEMONHUNTER Истребление / Месть / Пожиратель
--        ClassID 13 EVOKER      Опустошитель / Хранитель / Насыщатель
--      (the same build's ChrClasses table gives Монах, Охотник на демонов,
--      Пробудитель -- the class names this repository's own ruRU locale
--      already uses.)
--
-- The ORDER matters and is the client's own OrderIndex -- and the English
-- table's order too (Brewmaster, Mistweaver, Windwalker; Havoc, Vengeance;
-- Devastation, Preservation, Augmentation): GetSpecializationName reads this
-- table BY INDEX.
--
-- The Demon Hunter's THIRD spec, "Пожиратель" (Devourer), is deliberately
-- NOT here: it is the Midnight (retail 11.2) addition at OrderIndex 2, it
-- does not exist on the classic clients this add-on serves, and
-- lib.spec_table has no third ENGLISH entry for it -- the two tables are kept
-- the same shape. The pin therefore asserts TWO Demon Hunter names, not
-- three.
--
-- The pin is threefold:
--   1. the ruRU table carries EXACTLY those strings;
--   2. every ruRU value DIFFERS from the enUS value and from the deDE value
--      at the same index -- so the placeholders cannot come back;
--   3. the enUS and the deDE tables are still their own values, so the fix
--      cannot bleed into another locale.
--
-- The library builds `spec_table_localized` ONCE (`lib.spec_table_localized
-- or { ... }`), so each locale needs a FRESH LibStub registry -- see loadFor.

local _hp = ((arg and arg[0]) or "Tests/harness/specname_test.lua"):gsub("\\", "/")
local _hd = _hp:match("^(.*)/[^/]*$") or "."
local ROOT = dofile(_hd .. "/root.lua") .. "/"
local LIB = ROOT .. "Libs/"

local results, allok = {}, true
local function check(name, cond, detail)
    results[#results + 1] = string.format("%-54s %-6s %s", name, cond and "PASS" or "FAIL", detail or "")
    if not cond then allok = false end
end

local REALG = _G

-- Minimal environment every client shares. Only what the library touches at
-- FILE scope is needed here: the family probe, the capability probe and the
-- frame it creates. Nothing else runs at load.
local function baseEnv()
    REALG._G = REALG
    REALG.CreateFrame = function()
        return { RegisterEvent = function() end, SetScript = function() end }
    end
    REALG.GetTime = function() return 0 end
    REALG.C_Timer = { After = function() end }
    REALG.GetBuildInfo = function() return "1.15.9", "69722", "date", 11509, "us", "release" end
    REALG.WOW_PROJECT_ID = 2
    REALG.WOW_PROJECT_CLASSIC = 2
    REALG.GetItemInfo = function() end
    REALG.UnitGUID = function() return nil end
    REALG.UnitIsPlayer = function() return false end
    REALG.GetNamePlates = function() return {} end
    REALG.CanInspect = function() return false end
    REALG.NotifyInspect = function() return true end
    REALG.InCombatLockdown = function() return false end
    REALG.C_Item = { GetInventoryItemLink = function() end }
    REALG.C_SpecializationInfo = { GetSpecializationInfo = function() end }
    REALG.GetSpecializationInfoByID = function() return nil, nil, nil, nil, nil, nil, nil end
end

local function loadFor(locale)
    -- A fresh LibStub registry per locale. `lib.spec_table_localized` is
    -- built once per library table (`... or { ... }`), so loading a second
    -- locale into the same registry would keep the FIRST locale's table and
    -- every assertion below would grade the wrong strings.
    REALG.LibStub = nil
    REALG.GetLocale = function() return locale end
    assert(loadfile(LIB .. "LibStub/LibStub.lua"))()
    assert(loadfile(LIB .. "CallbackHandler-1.0/CallbackHandler-1.0.lua"))()
    assert(loadfile(LIB .. "LibDetours-1.0/LibDetours-1.0.lua"))()
    assert(loadfile(LIB .. "LibForeverInspector/LibForeverInspector.lua"))()
    local lib = LibStub("LibForeverInspector")
    assert(lib, "LibForeverInspector did not register")
    return lib
end

-- Blizzard's own Russian client strings.
local RU = {
    MONK = { "Хмелевар", "Ткач туманов", "Танцующий с ветром" },
    DEMONHUNTER = { "Истребление", "Месть" },
    EVOKER = { "Опустошитель", "Хранитель", "Насыщатель" },
}
-- The English values the ruRU table must NOT fall back to.
local EN = {
    MONK = { "Brewmaster", "Mistweaver", "Windwalker" },
    DEMONHUNTER = { "Havoc", "Vengeance" },
    EVOKER = { "Devastation", "Preservation", "Augmentation" },
}
-- The German values that used to sit in the ruRU block.
local DE = {
    MONK = { "Braumeister", "Nebelwirker", "Windläufer" },
    DEMONHUNTER = { "Verwüstung", "Rachsucht" },
    EVOKER = { "Verheerung", "Bewahrung", "Verstärkung" },
}
local CLASSES = { "MONK", "DEMONHUNTER", "EVOKER" }

local function sameList(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    if #a ~= #b then return false end
    for i = 1, #a do if a[i] ~= b[i] then return false end end
    return true
end

local function listOf(t)
    local out = {}
    for i = 1, #(t or {}) do out[i] = t[i] end
    return table.concat(out, ", ")
end

-- Index-independent: no value of `got` may appear anywhere in `ref`. An
-- index-wise comparison would read a nil slot as "different" and pass on a
-- table with a different length.
local function noOverlap(got, ref)
    if type(got) ~= "table" or type(ref) ~= "table" then return false end
    for i = 1, #got do
        for j = 1, #ref do
            if got[i] == ref[j] then return false end
        end
    end
    return true
end

baseEnv()
local ru = loadFor("ruRU").spec_table_localized
local en = loadFor("enUS").spec_table_localized
local de = loadFor("deDE").spec_table_localized

for _, class in ipairs(CLASSES) do
    local got = ru and ru[class]
    check("ruRU " .. class .. " is Blizzard's Russian name", sameList(got, RU[class]),
        listOf(got) .. "  expected  " .. listOf(RU[class]))
    check("ruRU " .. class .. " is not the English placeholder",
        noOverlap(got, EN[class]),
        listOf(got) .. "  !=  " .. listOf(EN[class]))
    check("ruRU " .. class .. " is not the German placeholder",
        noOverlap(got, DE[class]),
        listOf(got) .. "  !=  " .. listOf(DE[class]))
    check("enUS " .. class .. " is unchanged", sameList(en and en[class], EN[class]),
        listOf(en and en[class]) .. "  expected  " .. listOf(EN[class]))
    check("deDE " .. class .. " is unchanged", sameList(de and de[class], DE[class]),
        listOf(de and de[class]) .. "  expected  " .. listOf(DE[class]))
end

print(table.concat(results, "\n"))
print("\n" .. (allok and "ALL PASS" or "FAILURES PRESENT"))
if not allok then os.exit(1) end
