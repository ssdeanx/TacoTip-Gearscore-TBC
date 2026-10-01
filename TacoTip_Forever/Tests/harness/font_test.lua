-- textures.lua expects `local addOnName = ...`; feed it a vararg and read the
-- table back out of the global it writes.
local src = (os.getenv("TACOTIP_TEST_ROOT") or ".") .. "/textures.lua"
for _, loc in ipairs{"enUS","deDE","ruRU","zhCN","zhTW"} do
  _G.GetLocale = function() return loc end
  _G.TacoTipForever = nil
  local chunk = assert(loadfile(src))
  chunk("TacoTipForever")
  local TT = _G.TacoTipForever
  local n, cjk, det = 0, 0, 0
  for _, e in ipairs(TT.builtinTooltipFonts) do
    n = n + 1
    if e.value:find("Fonts\\ZY",1,true) then cjk = cjk + 1 end
    if e.value:find("FNT_Details_",1,true) then det = det + 1 end
  end
  local expectCJK = (loc == "zhCN" or loc == "zhTW") and 6 or 0
  print(string.format("locale=%-5s fonts=%-3d cjk=%d (want %d) details=%d (want 0)  %s",
    loc, n, cjk, expectCJK, det,
    (cjk == expectCJK and det == 0) and "PASS" or "FAIL"))
end
