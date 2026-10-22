# fix-main-batch1 — Journal

## 2026-10-18 — Desk opened
- **Purpose:** Batch 1 of the Stage-6 fix wave on the MAIN TacoTip addon (NOT Extras): 4 small revert-pinned robustness fixes — (1) sanitizer allowlists, (2) spec-nil fallback, (3) queue-drop counter, (4) file-scope soft aborts.
- **Scope:** main.lua (item 4 + diag for item 3 ONLY), options.lua (item 1 ONLY), Libs/LibForeverInspector/LibForeverInspector.lua (items 2-4 ONLY), Tests/harness/*.lua (pins ONLY).
- **Constraints:** no commit/staging; zero behavior change for valid states; every fix revert-to-fail proven in-harness; no new harness patterns.
- **Next step:** baseline 54/54 confirmed on lua5.1; implement items 1-4 + pins, revert-prove each, full suite green on lua5.1/5.4/luajit + lint clean.

## 2026-10-18 — Batch 1 complete, all four fixes revert-proven
- **Item 1 (options.lua SafeSanitizeConfig):** `custom_anchor` allowlisted to the five cycled literals (TOPLEFT/TOPRIGHT/BOTTOMLEFT/BOTTOMRIGHT/CENTER, matching slash path); `tooltip_font`/`tooltip_bar_texture`/`tooltip_background_texture`/`tooltip_border_texture` validated against builtin tables + LibSharedMedia registry (same sources as choice lists), reset to defaults otherwise. Choice getters NOT used (defined below first-load call site). Existing "Tooltip enlarged" precedent kept.
- **Item 2 (lib spec-nil):** `GetSpecialization` tail returns nil-able `cached.specIndex`; `GetActiveTalentGroup` nil-guid → nil, unknown/dataless record → nil, group-1 default only when `specIndexByGroup`/`talentPoints` show a resolved group. Callers already nil-gate (`if (spec1)`, `or 1` at main.lua:2060).
- **Item 3 (queue-drop):** eviction counted (`inspectStats.queueDropped`, init 0) + `lastQueueDropGuid`/`lastQueueDropAge` (via new `enqueuedAt` on entries); surfaced in `/tacotip diag` counters section + last-drop line. Eviction logic untouched.
- **Item 4 (soft aborts):** main.lua TT + `LOAD_STAGE="begin"` moved above all asserts/extern calls; three asserts → `return` with stages begin/libs; removed duplicate LOAD_STAGE/LOAD_OK reset; lib `GetBuildInfo()` guarded by `type` check, default `interfaceVersion=0` → family unknown.
- **Pins:** settings_test.lua sanitize block (5 garbage→default + 2 survive positive controls); detect_test.lua spec/group block (7 checks) + queue block (4 checks); new fileguard_test.lua (11 checks) + run_all.sh entry (54→55 invocations).
- **Revert evidence (all red-then-green):** item1: 5/52 FAILED (BOGUS-ANCHOR etc.); item2: specless→spec=1 + 3× group=1 FAIL; item3: queueDropped=0 + nil guid/age FAIL; item4: raises at main.lua:21/22 + lib:107 FAIL. Each restored to green.
- **Validation:** 55/55 on lua5.1, lua5.4, luajit; luacheck shipped files 0/0 (baseline 0/0); harness-file delta is +1 warning of a pre-existing class (fileguard `table.unpack`, same as detect_test:21, required for 5.4 runs).
- **Deviations:** suite count 54→55 (new pin file); Tests/harness/README.md count left stale for orchestrator (docs out of scope). No commit/staging; no Extras/toc/version/README/CHANGELOG touches.
- **Next step:** orchestrator review; doc updates + in-game confirmations owned elsewhere.
