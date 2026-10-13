# Architecture & Dual-Engine Foundation

## 1. Runtime Load Order & TOC Sequencing

TacoTip loads modules in strict dependency sequence defined in `TacoTip.toc`:

1. **Libraries (Bundled):**
   - `Libs/LibStub/LibStub.lua` — Lightweight library loader
   - `Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua` — Event dispatcher for libraries
   - `Libs/LibDetours-1.0/LibDetours-1.0.lua` — Safe function hook/unhook manager
   - `Libs/LibClassicInspector/LibClassicInspector.lua` — Talent/equipment inspection engine

2. **Localization:**
   - `Locale/enUS.lua` — Source of truth (263 base keys)
   - `Locale/*.lua` — 10 translated languages inheriting fallback from `enUS`

3. **Core Subsystems:**
   - `gearscore.lua` — Formula evaluation, equipment slot mapping, quality colors (`TT_GS`)
   - `pawn.lua` — Scale calculation bridge, spec matching (`TT_PAWN`)
   - `textures.lua` — Built-in backdrop & border media definitions
   - `options.lua` — Dual-canvas settings registration, widget factory, SavedVariables sanitization
   - `main.lua` — Core tooltip hooks, rendering pipeline, mover UI, character/inspect overlays

4. **Test Suite:**
   - `TacoTip_Tests.lua` — Optional `/tttest` test runner containing 9 test suites

---

## 2. Global Namespacing

To prevent namespace pollution and avoid global conflicts with other addons or Blizzard code:

- `TT`: Main addon table containing helper methods, anchor sync, and public API.
- `TT_GS`: Self-contained GearScore calculation module.
- `TT_PAWN`: Optional Pawn scale evaluation bridge.
- `TacoTipConfig`: Single persisted table in SavedVariables.
- `TACOTIP_LOCALE`: Resolved dictionary of localized strings.
- **Rule:** Never introduce new top-level `_G` globals without explicit architectural necessity.
