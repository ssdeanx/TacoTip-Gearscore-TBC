-- textures.lua expects `local addOnName = ...`; feed it a vararg and read the
-- table back out of the global it writes.
--
-- The built-in list is no longer filtered at file scope: the filter needs the
-- EFFECTIVE display language (client alphabet, or a non-roman locale override),
-- and SavedVariables are empty while addon files load. The test calls the same
-- runtime filter options.lua calls.
local _hp = ((arg and arg[0]) or "Tests/harness/font_test.lua"):gsub("\\", "/")
local _hd = _hp:match("^(.*)/[^/]*$") or "."
local src = dofile(_hd .. "/root.lua") .. "/textures.lua"
local okAll = true
for _, loc in ipairs{"enUS","deDE","ruRU","koKR","zhCN","zhTW"} do
  _G.GetLocale = function() return loc end
  _G.TacoTipForever = nil
  local chunk = assert(loadfile(src))
  chunk("TacoTipForever")
  local TT = _G.TacoTipForever
  local list = TT.builtinTooltipFonts
  if (TT.filterBuiltinTooltipFonts) then
    list = TT.filterBuiltinTooltipFonts(TT.builtinTooltipFonts, loc)
  end
  local n, cjk, det, bad = 0, 0, 0, 0
  for _, e in ipairs(list) do
    n = n + 1
    local lower = e.value:lower()
    local isCJKFont = lower:find("fonts\\zy", 1, true) ~= nil
      or lower:find("arkai", 1, true) ~= nil
      or lower:find("blei00d", 1, true) ~= nil
    local isCyrFont = lower:find("frizqt___cyr", 1, true) ~= nil
    -- TacoTip's own faces live under Media\Fonts\ and are claimed per script by
    -- SCRIPT_FONTS: Cyrillic on ruRU, Hangul on koKR, CJK on zhCN/zhTW. Each
    -- one IS a usable face for its language, and none of them is offered on a
    -- roman client (they would just replace the player's UI face).
    local isBundled = lower:find("\\media\\fonts\\", 1, true) ~= nil
    if isCJKFont then cjk = cjk + 1 end
    if e.value:find("FNT_Details_", 1, true) then det = det + 1 end
    -- Every built-in choice must be able to draw the client's script. A
    -- roman-only face on a non-roman client is the "squares" bug, and the
    -- choice persists in SavedVariables, so it must never be offered.
    local usable
    if loc == "ruRU" then
      usable = isCyrFont or lower:find("arialn", 1, true) ~= nil
        or lower:find("2002", 1, true) ~= nil
        or lower:find("k_pagetext", 1, true) ~= nil
        or lower:find("notosans-regular", 1, true) ~= nil
    elseif loc == "koKR" then
      usable = lower:find("2002", 1, true) ~= nil
        or lower:find("k_pagetext", 1, true) ~= nil
        or lower:find("nanumgothic-regular", 1, true) ~= nil
    elseif loc == "zhCN" or loc == "zhTW" then
      usable = isCJKFont or lower:find("wenquanyimicrohei", 1, true) ~= nil
    else
      usable = not isCJKFont and not isCyrFont and not isBundled
    end
    if not usable then bad = bad + 1 end
  end
  local expectCJK = (loc == "zhCN" or loc == "zhTW") and 1 or 0
  local ok = (cjk == expectCJK and det == 0 and bad == 0)
  if not ok then okAll = false end
  print(string.format("locale=%-5s fonts=%-3d cjk=%d (want %d) details=%d unrenderable=%d  %s",
    loc, n, cjk, expectCJK, det, bad, ok and "PASS" or "FAIL"))
end

-- ---------------------------------------------------------------------------
-- The per-line pick (TT.GetScriptFontPath)
--
-- The reported defect: a Russian guild name on a roman client rendered one
-- missing-glyph box per character while every other line read normally, because
-- one face was applied to the whole tooltip. The pick must move ONLY a line
-- whose text the current face cannot draw, onto the bundled face for that
-- script -- and it must never override a SharedMedia face, which is the
-- player's own explicit choice.
-- ---------------------------------------------------------------------------
  local pickOk = true
  local function pin(name, cond, detail)
    if not cond then pickOk = false end
    print(string.format("%-72s %s   %s", name, cond and "PASS" or "FAIL", detail or ""))
  end

  _G.GetLocale = function() return "enUS" end
  _G.TacoTipForever = nil
  local pchunk = assert(loadfile(src))
  pchunk("TacoTipForever")
  local PT = _G.TacoTipForever
  local bundled = PT.bundledTooltipFonts or {}
  local ROMAN = "Fonts\\FRIZQT__.TTF"
  local CYR = "Fonts\\FRIZQT___CYR.TTF"
  local RU = "Кровь и Пепел"
  local CN = "公会名称"
  local KR = "가나다한글"

  pin("pick: the three bundled faces are registered per language",
    type(bundled.ruRU) == "string" and type(bundled.koKR) == "string"
      and type(bundled.zhCN) == "string" and type(bundled.zhTW) == "string"
      and bundled.zhCN == bundled.zhTW,
    tostring(bundled.ruRU) .. " | " .. tostring(bundled.koKR))

  local function pick(base, text) return PT.GetScriptFontPath(base, text) end

  pin("pick: roman face + Cyrillic text -> bundled Cyrillic face",
    pick(ROMAN, RU) == bundled.ruRU, tostring(pick(ROMAN, RU)))
  pin("pick: roman face + Chinese text -> bundled Chinese face",
    pick(ROMAN, CN) == bundled.zhCN, tostring(pick(ROMAN, CN)))
  pin("pick: roman face + Hangul text -> bundled Korean face",
    pick(ROMAN, KR) == bundled.koKR, tostring(pick(ROMAN, KR)))
  pin("pick: roman face + Latin text is untouched",
    pick(ROMAN, "Level 60 Undead Paladin |cFF40FB40<Guild>|r") == ROMAN)
  pin("pick: Cyrillic client face + Cyrillic text stays on the client face",
    pick(CYR, RU) == CYR, tostring(pick(CYR, RU)))
  pin("pick: Cyrillic client face + Chinese text -> bundled Chinese face",
    pick(CYR, CN) == bundled.zhCN, tostring(pick(CYR, CN)))
  pin("pick: Korean client face + Cyrillic text -> bundled Cyrillic face",
    pick(bundled.koKR, RU) == bundled.ruRU, tostring(pick(bundled.koKR, RU)))
  pin("pick: bundled Chinese face already draws Hangul, so it is kept",
    pick(bundled.zhCN, KR) == bundled.zhCN, tostring(pick(bundled.zhCN, KR)))
  pin("pick: a SharedMedia face is the player's pick and is never overridden",
    pick("Interface\\AddOns\\SharedMedia\\Fonts\\SomeFont.ttf", RU)
      == "Interface\\AddOns\\SharedMedia\\Fonts\\SomeFont.ttf")
  pin("pick: nil/empty text keeps the resolved face",
    pick(ROMAN, nil) == ROMAN and pick(ROMAN, "") == ROMAN)

  local masks = PT.SCRIPT_MASKS or {}
  local detected = PT.DetectScripts and PT.DetectScripts(RU) or 0
  pin("detector: Cyrillic text detects the Cyrillic mask",
    detected == masks.CYRILLIC, "mask=" .. tostring(detected))
  pin("detector: Chinese text detects the CJK mask",
    PT.DetectScripts and PT.DetectScripts(CN) == masks.CJK)
  pin("detector: Hangul text detects the Hangul mask",
    PT.DetectScripts and PT.DetectScripts(KR) == masks.HANGUL)
  pin("detector: ASCII text detects nothing",
    PT.DetectScripts and PT.DetectScripts("GearScore: 685") == 0)

  -- The restricted path: a tooltip whose text may not be read is re-fonted from
  -- the MASK the same unit recorded while it was readable. A mask is a number,
  -- so that pass never touches a secret value.
  local pickMask = PT.PickScriptFont
  pin("mask pick: mask 0 keeps the resolved face",
    pickMask and pickMask(ROMAN, 0) == ROMAN)
  pin("mask pick: the Cyrillic mask on a roman face -> bundled Cyrillic face",
    pickMask and pickMask(ROMAN, masks.CYRILLIC) == bundled.ruRU)
  pin("mask pick: the CJK mask on a Cyrillic face -> bundled Chinese face",
    pickMask and pickMask(CYR, masks.CJK) == bundled.zhCN)
  pin("mask pick: a face that already draws the script is kept",
    pickMask and pickMask(bundled.zhCN, masks.HANGUL) == bundled.zhCN)
  pin("mask pick: a nil mask is not a script",
    pickMask and pickMask(ROMAN, nil) == ROMAN)

  if not pickOk then okAll = false end

if (not okAll) then
  print("FONT FAILURES PRESENT")
  os.exit(1)
end
print("ALL FONT PASS")
