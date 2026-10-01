-- Simulate WoW's load environment for the locale layer.
local D = (os.getenv("TACOTIP_TEST_ROOT") or ".") .. "/Locale/"
local results = {}
-- family, when given, stands in for LibForeverInspector. The locale selector
-- pins WotLK Titanforge to Simplified Chinese, and that branch is unreachable
-- without a stub, so it needs one.
local function scenario(clientLocale, override, family)
  -- fresh env
  _G.TACOTIP_LOCALES, _G.TACOTIP_LOCALE, _G.TACOTIP_ACTIVE_LOCALE = nil, nil, nil
  _G.GetLocale = function() return clientLocale end
  _G.TacoTipConfig = override and { locale_override = override } or {}
  if (family) then
    _G.LibStub = function(name)
      if (name == "LibForeverInspector") then
        return { IsWotlk = function(self) return family == "titanforge" end }
      end
    end
  else
    _G.LibStub = nil
  end
  for _, f in ipairs{"deDE","esES","esMX","frFR","itIT","koKR","ptBR","ruRU","zhCN","zhTW","enUS"} do
    local chunk = assert(loadfile(D .. f .. ".lua"))
    chunk()
  end
  return _G.TACOTIP_LOCALE, _G.TACOTIP_ACTIVE_LOCALE
end
local function probe(name, clientLocale, override, expectKey, expectVal, family)
  local L, active = scenario(clientLocale, override, family)
  local n = 0; for _ in pairs(L) do n = n + 1 end
  local got = L[expectKey]
  local ok = (got == expectVal)
  results[#results+1] = string.format("%-34s active=%-6s keys=%-4d %s=%-22s %s",
    name, tostring(active), n, expectKey, tostring(got), ok and "PASS" or ("FAIL exp="..tostring(expectVal)))
  return ok
end
local allok = true
allok = probe("deDE client",        "deDE", nil,   "Player", "Spieler") and allok
allok = probe("esES client",        "esES", nil,   "Player", "Jugador") and allok
allok = probe("frFR client",        "frFR", nil,   "Player", "Joueur") and allok
allok = probe("ruRU client",        "ruRU", nil,   "Player", "Игрок") and allok
allok = probe("zhCN client",        "zhCN", nil,   "Player", "玩家") and allok
allok = probe("zhTW client",        "zhTW", nil,   "Player", "玩家") and allok
allok = probe("enUS client",        "enUS", nil,   "Player", "Player") and allok
allok = probe("enGB -> enUS",       "enGB", nil,   "Player", "Player") and allok
allok = probe("ptBR client",        "ptBR", nil,   "Player", "Jogador") and allok
allok = probe("itIT client",        "itIT", nil,   "Player", "Giocatore") and allok
allok = probe("koKR client",        "koKR", nil,   "Player", "플레이어") and allok
allok = probe("esMX client",        "esMX", nil,   "Player", "Jugador") and allok
-- override wins over client locale
allok = probe("deDE client, enUS override", "deDE", "enUS", "Player", "Player") and allok
allok = probe("enUS client, deDE override", "enUS", "deDE", "Player", "Spieler") and allok
allok = probe("enUS client, zhCN override", "enUS", "zhCN", "Player", "玩家") and allok
-- unknown locale falls back to English
allok = probe("unknown locale",     "xxXX", nil,   "Player", "Player") and allok
-- Titanforge is pinned to Simplified Chinese regardless of what GetLocale()
-- reports, because it is the Chinese build of WotLK.
allok = probe("titanforge, enUS client",  "enUS", nil, "Player", "玩家", "titanforge") and allok
allok = probe("titanforge, deDE client",  "deDE", nil, "Player", "玩家", "titanforge") and allok
allok = probe("titanforge, zhTW client",  "zhTW", nil, "Player", "玩家", "titanforge") and allok
-- ...but an explicit override still wins on Titanforge.
allok = probe("titanforge, enUS override", "enUS", "enUS", "Player", "Player", "titanforge") and allok
allok = probe("titanforge, deDE override", "enUS", "deDE", "Player", "Spieler", "titanforge") and allok
-- The other four clients are NOT pinned: they follow the client language.
allok = probe("classicEra, deDE client",   "deDE", nil, "Player", "Spieler", "classicEra") and allok
allok = probe("tbc, enUS client",          "enUS", nil, "Player", "Player",  "tbc") and allok
allok = probe("retail, ruRU client",       "ruRU", nil, "Player", "Игрок",   "retail") and allok
allok = probe("forever, frFR client",      "frFR", nil, "Player", "Joueur",  "forever") and allok
-- all 11 registered
local _, _ = scenario("enUS", nil)
local cnt = 0; for _ in pairs(_G.TACOTIP_LOCALES) do cnt = cnt + 1 end
results[#results+1] = string.format("%-34s registered_locales=%d %s", "registry", cnt, cnt==11 and "PASS" or "FAIL")
if cnt ~= 11 then allok = false end
print(table.concat(results, "\n"))
print("\n" .. (allok and "ALL PASS" or "FAILURES PRESENT"))
