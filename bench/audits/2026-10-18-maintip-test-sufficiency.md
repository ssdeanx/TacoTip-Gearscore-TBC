# Test Coverage Analysis: MAIN TacoTip addon Tests/ — v0.8.4

**Placement note:** reviewing session had no file-write and no execution tools; this report is filed verbatim from its inline handoff. Vacuity/revert-to-fail claims assessed by reading, not by running mutations. `wow-ui-source` mirror claims taken from repo comments/CHANGELOG at face value unless noted.

**Test files inspected (12):** `run_all.sh`, `root.lua`, `README.md`, `detect_test.lua`, `load_test.lua`, `tooltip_test.lua`, `settings_test.lua`, `options_test.lua`, `gearscore_test.lua`, `textures_test.lua`, `locale_test.lua`/`font_test.lua`/`talent_check.lua` (summaries), `Tests/TacoTip_Forever_Tests.lua` (in-game, 1222 lines). **Test surfaces:** offline mocked five-client matrix / contract / in-game WoWUnit. No execution performed.

**Overall Assessment: ADEQUATE** — core scoring, detection, range-gating, backdrop/delivery, and portrait-teardown behavior would catch most regressions; but 0.8.4's own changes, Baganator's positive half, and in-game staleness leave real holes. Not GOOD because unpinned 0.8.4 paths are silent-failure paths by definition. No 9–10 gaps established.

## Coverage mapping (changed behavior → test → status → missing scenario)

- tooltip pipeline → `tooltip_test.lua` + in-game TT-Stats/TT-Borders → Direct → instant-fade shim throw; GSCallback terminal-error report; owned-line clear positive.
- portrait lifecycle → `tooltip_test.lua` same-unit/OnCleared/OnHide/orphan-GUID + double observation → Direct → 0.8.4 `IsShown`/`tacoTipModelKey` gates (mock never false/nil).
- instant-fade pcall guard (0.8.4) → none found → No coverage → raising shims must not drop branch.
- GSCallback terminal surfacing (0.8.4) → `tooltip_test.lua:2121-2142` (re-entrancy only) → Partial → throwing UpdateTooltip/SetUnit must reach `handlePipelineError`.
- Baganator line-ownership → `tooltip_test.lua:2696-2729` negative only → Partial → owned line still blanked (positive absent by documented mock limit).
- settings/registration (66 settings, cascade, clamp, reset, Settings-vs-legacy, Pawn) → `settings_test.lua` 20-way + `options_test.lua` + Pawn chat-silence → Direct → `scan` toggle wiring/default/persistence/hover-unaffected (0.8.4).
- gearscore values → `gearscore_test.lua` hand-derived literals + in-game nil-safe → Direct → `RequestLoadItemDataByID` 2.0s throttle (no pin).
- pawn provider + chat contract + load gate → `load_test.lua:672-730` + in-game `PawnScaleNameContract` → Direct → real multi-Pawn-version drift (assumed untestable offline).
- textures allow-list + default + edgeSize + no-fabrication → `textures_test.lua` + `load_test.lua:827-892` + edgeSize/media-cache → Direct → none material.
- detection/family/bracket/mutual-exclusion/unknown → `detect_test.lua` matrix + in-game `DetectionResolves` → Direct → none material.
- range/scan/watchdog/GetTime/cache/tickers/roster/pcall/learned-limit/probe-guard → `detect_test.lua` → Direct → yardage values deliberately unpinned (awaiting measured `learned max range`).
- 0.8.4 portrait accounting → Hide counting (indirect) → Weak → guard-removal likely stays green.
- frame timing/async/alpha/sound/chat/combat/InspectFrame-real → in-game only → Partial → stale/missing pins (see gaps).

## Important gaps (7–8)

1. **0.8.4 instant-fade shim guard unpinned (8/10).** `main.lua:1040-1060, 3707, 3717`. No `instant_fade` string in any offline harness — VERIFIED by grep. Raising shims silently kill the fade branch, every hover on the affected client. Test: offline, `instant_fade=true`, raising `GetUnit`/`IsUnit`; assert branch survives; revert-to-fail by removing pcall.
2. **0.8.4 GSCallback terminal-failure surfacing unpinned (8/10).** `main.lua:1304-1312`. `tooltip_test.lua:2121` pins only re-entrancy with non-throwing UpdateTooltip — VERIFIED. Deleting the error arm stays green (vacuity). Test: stub throwing; assert `handlePipelineError`/diag fires and guard unlatches.
3. **0.8.4 `scan` toggle wiring unpinned (7/10).** `options.lua:21,138,197,2060` + library plumbing. `detect_test` pins `SetScanEnabled(false)` stops scan — VERIFIED — but not config key, default, reload/reset survival, or hover-unaffected. Test: flip control → config flips; reload/reset preserves; library records call; hover still issues while scan disabled.
4. **Baganator positive control missing (7/10).** Negative pinned and biting one way; positive deliberately absent (mock `__text` reads back as table). Regression into under-clearing stays green offline. Test: in-game positive control (shown-then-cleared pair with foreign line present); do not force an offline assertion the mock cannot observe.
5. **In-game portrait alpha test contradicts production (7/10).** `TacoTip_Forever_Tests.lua:335-358` requires the `OnUpdate` alpha-slave removed in 0.7.9 — VERIFIED by reading both. Replace with current contract (no `OnUpdate`, alpha pinned 1).

## Moderate gaps (5–6)

6. **In-game locale/count thresholds stale (6/10).** `TacoTip_Forever_Tests.lua:1060` (`>=251`) vs offline 239; `ConfigHasAllDefaults >=40` vs 66. Mirror offline invariants (resolve-every-lookup; reachability) instead of magic counts.
7. **Item-data 2.0s throttle unpinned (6/10).** `gearscore_test` never drives rapid-refresh collect counting — VERIFIED by grep. Count per-ID requests across rapid renders; assert ≤1 per 2s; revert by removing throttle.
8. **Portrait accounting guards likely vacuous (5/10).** Mock always shown/loaded — ASSUMED (needs revert run). Hidden-frame + unloaded-model cases asserting no counter moves.
9. **Remote group-2 active-group narrow (5/10).** `detect_test` covers player-side; missing remote-GUID `activeGroup=2` grey-side flip.

## Lower observations (1–4)

- `root.lua` corrupted-copy grading has no self-test (4/10, dev-only, CI-dependent).
- `INSPECT_RENDER_COALESCE` pair-drop only implicit (3/10, optional).
- `conf_version`/NaN/Inf corners in-game only (2/10, skip).
- Power-bar fallback colour behavioural half kept; allocation half interpreter-dependent by design (2/10, no action).

## Test quality issues

- `TacoTip_Forever_Tests.lua:335-358` asserts removed implementation (7/10) — replace.
- Magic counts `1060,758` brittle (6/10) — port offline invariants.
- Baganator half-pair honest but one-sided (6/10 as gap, not criticism).
- GC check `tooltip_test.lua:1790-1797` interpreter-sensitive with honest escape; lua5.1 is the grading interpreter (2/10, no action).

## Vacuity verdicts per file

- `main.lua` — WEAK on 0.8.4 paths (instant-fade, GSCallback-error, teardown-accounting would stay green if stubbed); STRONG on pipeline/portrait-teardown/Baganator-negative.
- `options.lua`/`pawn.lua` — STRONG (66-setting matrix, chat-channel Pawn contract with vacuity guard); WEAK only on new `scan` wiring.
- `gearscore.lua` — STRONG (hand-derived values bite; throttle the one hole).
- `textures.lua` — STRONG.
- `LibForeverInspector` — STRONG (arity-sensitive showError pin bites both directions; probe-guard/sound-latch/retry/classification revert-proven; only yardage values deliberately unpinned).
- **Wrong-turn catalog:** showError PINNED+BITES; portrait-blink PINNED+BITES; Baganator HALF-PINNED; corrupted-copy INFRASTRUCTURE-ONLY; xpcall-varargs PINNED; unpack-nil PINNED+BITES; GC-threshold PINNED with honest luajit-vacuous leg; next()-nil PINNED+BITES.

## Recommended priority

1. Pin 0.8.4 instant-fade shim throw. 2. Pin GSCallback terminal-error surfacing. 3. Pin `scan` wiring. 4. Repair in-game portrait alpha test. 5. Baganator positive in-game. 6. Replace in-game magic counts. 7. Pin throttle. 8. Portrait-accounting cases (optional). 9. Remote group-2 (optional). 10. Corrupted-copy self-test (CI-dependent).

**Limitations:** no execution (totals quoted: 54 offline, 42 Extras — not verified here); vacuity by reading; no file writes; mirror claims ASSUMED; real-client timing/async/sound/chat/combat beyond mocks UNKNOWN.
