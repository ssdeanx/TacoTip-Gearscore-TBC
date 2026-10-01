# TacoTip-Gearscore-TBC — Enterprise Project Memory

> **Version:** `0.7.7` | **CurseForge ID:** `1555962` | **Supported Interfaces:** `11509` (Classic Era / SoD), `20506` (TBC Anniversary), `38001` (Titanforge)  
> **Repository:** `ssdeanx/TacoTip-Gearscore-TBC` | **Maintainer:** Pilsung (AcidBomb) | **Architecture:** Multi-Client Classic Dual-Engine

---

## 1. Executive Summary & Core Mission

TacoTip Gearscore TBC is an enterprise-grade World of Warcraft Classic addon providing tooltip enhancement, GearScore computation, average item level calculation, specialization and talent inspection (including dual-spec support), Pawn score integration, class-colored backdrops/borders, and enlarged 3D character portraits.

---

## 2. Topic Knowledge Base (`.omg/memory/`)

| Topic Area | Document | Focus & High-Signal Scope |
| :--- | :--- | :--- |
| **Architecture & Load Order** | [architecture.md](file:///.omg/memory/architecture.md) | Dual-engine runtime order (`gearscore` → `pawn` → `textures` → `options` → `main`), shared globals (`TT`, `TT_GS`, `TT_PAWN`, `TacoTipConfig`), clean namespacing. |
| **Blizzard API Compatibility** | [blizzard_api_compat.md](file:///.omg/memory/blizzard_api_compat.md) | FrameXML branch auditing against `/home/sam/wow-ui-source` (`origin/classic_anniversary` & `origin/classic_era`), `C_SpecializationInfo` fallbacks, client ID gates. |
| **Dual Spec & Inspection** | [dual_spec_inspect.md](file:///.omg/memory/dual_spec_inspect.md) | `LibClassicInspector` runtime integration, TBC Anniversary / SoD dual-spec resolution, dynamic spec update events, zero-alpha tooltip alignment. |
| **Tooltip Lifecycle & Visuals** | [tooltip_lifecycle.md](file:///.omg/memory/tooltip_lifecycle.md) | `clearTooltipVisuals` non-unit isolation, 3D portrait `OnUpdate` alpha sync (20Hz), `ClearModel` GPU purging, deferred timer generation counters (`_borderDeferralGen`). |
| **Options UI & Configuration** | [options_ui_system.md](file:///.omg/memory/options_ui_system.md) | Dual modern Canvas (`Settings.RegisterCanvasLayoutCategory`) + legacy `InterfaceOptions` fallback, SavedVariables migration, modal media picker, media resolution caching. |
| **Localization Engine** | [localization_system.md](file:///.omg/memory/localization_system.md) | 100% parity across all 11 locales (261/261 keys), format specifier safety, runtime locale override. |
| **Quality & Verification Gates** | [verification_gates.md](file:///.omg/memory/verification_gates.md) | Strict zero-warning static analysis gate (`luacheck .`), WoWUnit automated test suite (`TacoTip_Tests.lua`), multi-client runner mocks. |

---

## 3. Active Rule Packs (`.omg/rules/`)

- [01-zero-warning-luacheck.md](file:///.omg/rules/01-zero-warning-luacheck.md) — Zero tolerance for warnings/errors across all files; dynamic global indexing.
- [02-framexml-api-discipline.md](file:///.omg/rules/02-framexml-api-discipline.md) — Research `/home/sam/wow-ui-source` before modifying API calls; no Retail bleed.
- [03-non-unit-visual-isolation.md](file:///.omg/rules/03-non-unit-visual-isolation.md) — Synchronous visual purging (`clearTooltipVisuals`) across all non-unit/map hover transitions.
- [04-dual-spec-inspect-handling.md](file:///.omg/rules/04-dual-spec-inspect-handling.md) — Multi-client dual-spec detection, query struct fallbacks, nil-safe arithmetic, zero-alpha prefix alignment.
- [05-locale-parity-standards.md](file:///.omg/rules/05-locale-parity-standards.md) — Strict 261-key coverage across all 11 languages with matched format tokens.
- [06-version-release-bumping.md](file:///.omg/rules/06-version-release-bumping.md) — Synchronous 6-point version bump protocol (`TOC`, `main`, `options`, `README`, `CHANGELOG`, `AGENTS`).

---

## 4. Key Architectural Constants & Globals

- **Namespaces:** `_G.TT` (core addon object), `_G.TT_GS` (GearScore engine), `_G.TT_PAWN` (Pawn bridge), `_G.TacoTipConfig` (SavedVariables), `_G.TACOTIP_LOCALE` (active translation dictionary).
- **Supported Interface IDs:**
  - `11509`: Classic Era 1.15.x / Season of Discovery
  - `20506`: TBC Classic Anniversary 2.5.6
  - `38001`: Titanforge Chinese Wrath Client
- **Default Visual Dimensions:**
  - 3D Portrait: `72 × 96` (3:4 ratio, clean integer scaling at all stops: 36x48, 72x96, 108x144, 144x192)
  - Tooltip Border Edge Size: `14px` default (`Tooltip enlarged` texture)
- **High-Frequency Performance Buffers:**
  - Zero-allocation pooled tables: `pooledLinesToAdd`, `pooledTooltipText` in `main.lua`
  - Lazy SharedMedia resolution cache with `TT:InvalidateResolvedMediaCache()` in `options.lua`
  - Throttled 3D portrait model sync: 20Hz (0.05s) using `self:GetParent():GetAlpha()`

## Universal inspector update

`TacoTip_Forever/Libs/LibForeverInspector/LibForeverInspector.lua` minor 3 restores bounded GUID queues with 15-second availability deferral, range checks before inspect APIs, manual-inspect priority and inventory-event refresh. See the nested changelog and `Tests/harness/inspect_test.lua`; TBC Anniversary user testing confirmed equipment eventually loads without hangs; other clients remain validated only by offline tests.
