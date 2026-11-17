# Tooltip Lifecycle, Non-Latin Script Fonts & Visual Isolation

## 1. Non-Unit Visual Isolation (`clearTooltipVisuals`)

- `clearTooltipVisuals(tooltip)` resets unit state on `OnHide`, `OnTooltipCleared`, `OnTooltipSetSpell`, `OnTooltipSetItem`, `onTooltipShow` (non-player), and top of `onTooltipSetUnit`:
  - Increments `tooltip._borderDeferralGen` and cancels pending border/class deferral timers.
  - Hides 2D portrait (`TacoTipPortrait`) and clears 3D portrait (`Hide()`, `pcall(ClearModel)`, `SetAlpha(1)`).
  - Hides `TacoTipPowerBar`, stops power-bar ticker, resets custom padding, and disables mouse capture (`GameTooltip:EnableMouse(false)` inside `GameTooltip_SetDefaultAnchor`).

---

## 2. Non-Latin Script Font Fallback (`ru` / `cn` / `ko` / `tw`)

Western clients (`enUS` with `FRIZQT__.TTF`, `Expressway`, `Roboto`, `MORPHEUS`, `SKURRI`) lack Cyrillic, CJK, and Hangul glyphs, causing `□□□` boxes in Wide/Compact/Mini tooltips, `Target:` rows, `/who`, `FriendsTooltip`, and World Map player pins.

- **`textures.lua` (`TT.PickScriptFont` & `TT.GetScriptFontPath`):**
  - `detectScripts(text)` detects Cyrillic (including Cyrillic Supplement `\212[\128-\175]`), Simplified/Traditional CJK (including Radicals/Compat/Fullwidth/Ext-B), and Hangul (Jamo + Syllables).
  - Normalizes `/` vs `\` font paths and checks `FACE_SCRIPT_COVERAGE` (so Blizzard system fonts missing scripts resolve straight to bundled fallbacks in `Media/Fonts/`: `NotoSans-Regular.ttf` for Cyrillic, `WenQuanYiMicroHei.ttf` for Chinese, `NanumGothic-Regular.ttf` for Korean).
- **`main.lua` Font Application Pipeline (`TT.ApplyFontIfNeeded`, `TT.ApplyTooltipFonts`):**
  - Checks the Region's live `GetFont()`, picks script fallback if missing coverage, retries bundled script font if `SetFont` returns `false`, and skips Forever loot tooltips (`GetLootItem`).
  - Wired into:
    - Unit tooltips (`onTooltipSetUnit` + remembered line font masks + `onTooltipShow` re-verification across `Wide`, `Compact`, `Mini`, and `Target:` rows)
    - Spell & non-unit tooltips (`OnTooltipSetSpell`, `WhoList`, Guild/Social)
    - **`FriendsTooltip`:** Hooks `FriendsFrameTooltip_SetLine` + `FriendsTooltip` `OnShow` (and `Blizzard_FriendsFrame` `ADDON_LOADED`) across `Header`, `NoteText`, `BroadcastText`, `LastOnline`, `OtherGameAccounts`, `GameAccount1..5Name/Info`, `GameAccountMany`.
    - **World Map Unit Pins:** Hooks `UnitPositionFrameMixin.UpdateUnitTooltips` (plus `Blizzard_WorldMap` / `Blizzard_SharedMapDataProviders` `ADDON_LOADED`), **strictly gated** by `TT.CanStyleWorldMapTooltip()` so tooltips are never touched during combat lockdown, instances, encounters, or active Forever restrictions.

---

## 3. Performance & High-Frequency Hygiene

- Preallocated line tables (`pooledLinesToAdd`, `pooledLineRecords`, `pooledPlayerText`) eliminate per-hover table garbage.
- `TacoTipMouseAnchor` exits immediately in `OnUpdate` when hidden or mouse-anchoring is disabled.
- 3D portrait alpha sync runs at 20Hz (`0.05s`) via parent alpha; right-edge screen detection flips portrait anchor side dynamically when `ApplyTooltipAppearance` runs post-layout.
