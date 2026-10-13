# TacoTip-Gearscore-TBC — Enterprise Project Memory

> **Version:** `0.8.2` | **CurseForge ID:** `1555962` | **Supported Interfaces:** `11509` (Classic Era / SoD), `20506` (TBC Anniversary), `38002` (WotLK Titanforge), `16001` (WoW Forever), `120100` (Retail)  
> **Repository:** `ssdeanx/TacoTip-Gearscore-TBC` | **Maintainer:** Pilsung (AcidBomb) | **Architecture:** Five-client cross-engine, single build

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
| **Localization Engine** | [localization_system.md](file:///.omg/memory/localization_system.md) | 100% parity across all 11 locales (263/263 keys), format specifier safety, runtime locale override. |
| **Quality & Verification Gates** | [verification_gates.md](file:///.omg/memory/verification_gates.md) | Strict zero-warning static analysis gate (`luacheck .`), WoWUnit automated test suite (`TacoTip_Tests.lua`), multi-client runner mocks. |

---

## 3. Active Rule Packs (`.omg/rules/`)

- [01-zero-warning-luacheck.md](file:///.omg/rules/01-zero-warning-luacheck.md) — Zero tolerance for warnings/errors across all files; dynamic global indexing.
- [02-framexml-api-discipline.md](file:///.omg/rules/02-framexml-api-discipline.md) — Research `/home/sam/wow-ui-source` before modifying API calls; no Retail bleed.
- [03-non-unit-visual-isolation.md](file:///.omg/rules/03-non-unit-visual-isolation.md) — Synchronous visual purging (`clearTooltipVisuals`) across all non-unit/map hover transitions.
- [04-dual-spec-inspect-handling.md](file:///.omg/rules/04-dual-spec-inspect-handling.md) — Multi-client dual-spec detection, query struct fallbacks, nil-safe arithmetic, zero-alpha prefix alignment.
- [05-locale-parity-standards.md](file:///.omg/rules/05-locale-parity-standards.md) — Strict 263-key coverage across all 11 languages with matched format tokens.
- [06-version-release-bumping.md](file:///.omg/rules/06-version-release-bumping.md) — Synchronous 6-point version bump protocol (`TOC`, `main`, `options`, `README`, `CHANGELOG`, `AGENTS`).

---

## 4. Key Architectural Constants & Globals

- **Namespaces:** `_G.TT` (core addon object), `_G.TT_GS` (GearScore engine), `_G.TT_PAWN` (Pawn bridge), `_G.TacoTipConfig` (SavedVariables), `_G.TACOTIP_LOCALE` (active translation dictionary).
- **Supported Interface IDs:**
  - `11509`: Classic Era 1.15.x / Season of Discovery
  - `20506`: TBC Classic Anniversary 2.5.6
  - `38001`: Titanforge Chinese Wrath Client
- **Default Visual Dimensions:**
  - 3D Portrait: `66 × 88` (3:4 ratio, clean integer scaling at all stops: 33x44, 66x88, 99x132, 132x176)
  - Tooltip Border Edge Size: `14px` default (`Tooltip enlarged` texture)
- **High-Frequency Performance Buffers:**
  - Zero-allocation pooled tables: `pooledLinesToAdd`, `pooledTooltipText` in `main.lua`
  - Lazy SharedMedia resolution cache with `TT:InvalidateResolvedMediaCache()` in `options.lua`
  - Throttled 3D portrait model sync: 20Hz (0.05s) using `self:GetParent():GetAlpha()`

---

## 5. Companion Addon & GearScore Engine Subsystems

- **TacoTip_Extras (1.0.1):** Standalone companion addon located at `TacoTip_Extras/`. Strictly depends on `TacoTip` (`## Dependencies: TacoTip`). Integrates directly with `LibForeverInspector` for non-invasive gear and gem/enchant auditing, and provides a server-wide GearScore Leaderboard & P2P Sync Engine (HonorSpy style).
  - **RankDB Subsystem (`RankDB.lua`):** Dirty-flag-cached storage with separate sorted tables for `all`, `alliance`, `horde`, and `byClass`. Provides $O(1)$ player rank lookups via `rankIndexByGUID` index. Automatic 60-day prune cycle (`PruneStaleRecords`) and 5,000 player capacity cap with lowest-GS eviction. Strict record validation and last-write-wins timestamp arbitration.
  - **RankSync Subsystem (`RankSync.lua`):** Peer-to-peer sync engine using hidden background channel `ttgssync` (silenced via `ChatFrame_RemoveChannelGroup`) with fallback broadcasts over `GUILD`, `PARTY`, and `RAID`. Compact `R;` delimited wire protocol. Token-bucket rate limiter (1 pkt / 1.5s, max burst 3).
  - **RankBrowser Subsystem (`RankBrowser.lua`):** Standalone 580×440 leaderboard frame (`TacoTipRankFrame`) accessible via `/tt ranks`, `/ttrank`, `/ttleaderboard`, or Options button. Features 3 faction tabs (`[All Realm]`, `[Alliance]`, `[Horde]`), live substring search editbox, FauxScrollFrame with 10 reusable row frames, top-3 medal colors, and personal rank standing footer banner.
  - **Tooltip Rank Display:** Renders `|cFFFFFFFFRank: |r#X (#Y Class)` on player tooltips, toggleable via `show_server_rank` in Options.
  - **Retail & Forever Client Compatibility:** Unit resolution supports `TooltipUtil.GetDisplayedUnit`, `TooltipDataProcessor.AddTooltipPostCall`, and 3-value `GetUnit()` returns (`name, unit, guid`). Equipment host parenting falls back gracefully to `CharacterModelScene` and `PaperDollFrame` when `CharacterModelFrame` is absent. `Scoring.ParseEquippedLink` supports variable-length modern item links with bonus IDs. Average item level divisor dynamically checks client type (16 slots on Retail without ranged slot, 17 slots on Classic/TBC/Titanforge/Forever).
  - **Remote Inspection & Event Binding:** `Scanner.HandleInventoryReady` accepts `isInspect` as true or nil (defensive against varying inspector libraries) and resolves remote unit tokens via `_G.InspectFrame.unit` when the inspected player is not targeted/focused. `LibForeverInspector` fires `("INVENTORY_READY", guid, true, unit)` and checks `InspectFrame.unit` in `PlayerGUIDToUnitToken`. Safe item ID extraction from item links prevents contradiction failures on remote units with uncached IDs.
  - **Display Modes Default:** Fresh installations and unconfigured profiles default to **Detailed** mode for all display surfaces (both player tooltips and character/inspect equipment summaries).
- **GearScore Engine Rules (`gearscore.lua`):**
  - Standalone 2H weapons retain `SlotMOD = 2.0` (weight 2.0x, balancing with 1H+Shield at 1241 vs 1240).
  - Titan's Grip dampening factor `0.5` strictly gated to active dual-wielding (`mainHandLink and offHandLink`).
  - Hunter weapon scaling: Melee slots at `0.3164x`, Ranged slots at `5.3224x`.
  - Item quality color bands: scaled by `ITEM_BAND_SCALE` (11.25) across all engine brackets.
