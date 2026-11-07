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
    elseif loc == "koKR" then
      usable = lower:find("2002", 1, true) ~= nil
        or lower:find("k_pagetext", 1, true) ~= nil
    elseif loc == "zhCN" or loc == "zhTW" then
      usable = isCJKFont
    else
      usable = not isCJKFont and not isCyrFont
    end
    if not usable then bad = bad + 1 end
  end
  local expectCJK = (loc == "zhCN" or loc == "zhTW") and 1 or 0
  local ok = (cjk == expectCJK and det == 0 and bad == 0)
  if not ok then okAll = false end
  print(string.format("locale=%-5s fonts=%-3d cjk=%d (want %d) details=%d unrenderable=%d  %s",
    loc, n, cjk, expectCJK, det, bad, ok and "PASS" or "FAIL"))
end
if (not okAll) then
  print("FONT FAILURES PRESENT")
  os.exit(1)
end
print("ALL FONT PASS")
