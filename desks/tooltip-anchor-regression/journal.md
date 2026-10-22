# Tooltip Anchor Regression — Journal

## 2026-10-20 — Desk opened
- **Purpose:** find and fix the 0.8.4 regression where the operator's SAVED tooltip
  position is lost and the tooltip falls back to the bottom-right corner of the
  screen. Release blocker: the operator is about to publish.
- **Scope:** `main.lua`, `options.lua`, and the harness files
  `Tests/harness/settings_test.lua`, `Tests/harness/load_test.lua`,
  `Tests/harness/options_test.lua`. NOT `Libs/**`, NOT `TacoTip_Extras/**`
  (a parallel lane owns those), NOT `gearscore.lua`/`pawn.lua`/`textures.lua`,
  NOT `Locale/*`, NOT the `.toc` files, NOT
  `Tests/harness/tooltip_test.lua`/`Tests/harness/detect_test.lua`.
- **Operator report:** Classic Era (11509). Tooltip stays where saved when
  hovering HIMSELF; when hovering ANOTHER player it sits in the bottom-right
  corner. Operator believes a Classic Era fallback was broken.
- **Next step:** read the config/anchor code path in `main.lua` + `options.lua`,
  diff against HEAD (0.8.3), confirm the cause and the self-vs-other asymmetry.
