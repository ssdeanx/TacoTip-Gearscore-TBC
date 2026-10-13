# Verification Gates & Testing Protocol

## 1. Zero-Warning Luacheck Gate

- **Command:** `luacheck .`
- **Standard:** 0 warnings / 0 errors across all 21 repository files.
- **Rule:** Never use `-- luacheck: ignore` inline comments to suppress warnings. Use dynamic table indexing (e.g. `_G["WorldMapTooltip"]`, `GameTooltip["Method"]`) or local caching.

---

## 2. WoWUnit Test Suite (`TacoTip_Tests.lua`)

- **Invocation:** `/tttest` in-game or via local Lua runner mocks.
- **Suites Registered (9 total):**
  1. `TacoTip-Core`: Namespace loading, public API presence, version metadata, interface IDs.
  2. `TacoTip-Config`: Default keys, Shaman Blue override, boolean sanitization, numeric bounds.
  3. `TacoTip-Borders`: Class-color border painting, non-unit border isolation, SharedMedia resolution caching.
  4. `TacoTip-Portrait`: 3:4 aspect ratio (`66x88`), integer scaling (50%–200%), `OnUpdate` alpha sync tracking.
  5. `TacoTip-Guild`: Fallback parser regex, `<Guild> Rank` format, hide suppression.
  6. `TacoTip-Stats`: Nil-safe GearScore / Pawn calculations, `LibClassicInspector` presence, dual-spec reachability.
  7. `TacoTip-Mover`: Mover handle sync, options UI refresh nil-safety, custom position initialization.
  8. `TacoTip-Modules`: Dependent global exposure, default configuration parity.
  9. `TacoTip-MinimapAndAnchor`: Frame ownership preservation, mouse disablement on `GameTooltip_SetDefaultAnchor`.

---

## 3. Mock Teardown Discipline

In tests, every global mock (e.g. `GetGuildInfo`, `UnitExists`, `GameTooltip.GetUnit`) must be cleaned up in a guaranteed teardown (`pcall` wrapper with `ClearReplaces()`) so subsequent test runs are never polluted.
