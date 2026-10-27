# Desk: diag-enterprise — Journal

## 2026-10-26 — Desk opened

- **Purpose:** Turn `/tt diag` into an enterprise support artifact for the TacoTip main addon: one side-effect-free collector (`TT:CollectDiagnostics`) and a renderer (`TT:PrintDiagnostics`), verdict first, stable section ids/order, deterministic map rendering, per-section resilience, session uptime, rate context, and structural pins.
- **Scope:** `main.lua` (diag block + `TT.loadTime`), `options.lua` (pcall around dispatch), `Tests/harness/load_test.lua` (structural pins), desk/report artifacts. Nothing else.
- **Rollback point:** `desks/diag-enterprise/main.lua.snapshot` (copy taken before the first edit).
- **Hard do-not-touch:** portrait render path, scan code, `gearscore.lua`, `TacoTip_Extras/**`, interface list (120105, no 120107), locale files, no state-changing git, Lua 5.1 only.
- **Next step:** read the current diag/test blocks, then implement collect/render.

## 2026-10-26 — [signal:done] structured /tt diag landed; all gates green

- **Confirmed smells (VERIFIED by reading the pre-change tree):** (a) reportEventCounters returned before the inspect-frame block when no events existed; (b) teardowns by reason rendered from `pairs()`; (c) `portraitSetFailed`, `anchorSpellBypass`, `anchorNonUnitBypass` were recorded but never reported, and `gsCallbackNoUnit` only appeared folded into one row; (d) section headers were printed inside reporters and row labels faked nesting with leading spaces; (e) no verdict and no session uptime; (f) no per-section resilience; (g) problems were never cross-checked against counters (portraitSetFailed, zero renders, last inspect-call error); (h) tests were substring-only. **New smells found:** `InspectFrame.unit` could print a function address (nondeterministic); numeric telemetry fields were formatted with %d/%.1f without tonumber; the cached-unit GS row called `GearScore.GetScore`, which can request item data (a side effect).
- **Architecture:** `TT:CollectDiagnostics()` returns a plain table (version, uptime, verdict, ordered sections, problems); `TT:PrintDiagnostics()` only renders it. Sections: environment, active-unit, tooltip, inspect, events, inspect-frame, errors, problems. Each row is {label, value, status in ok/info/warn/error}. Verdict is the first printed line. Every section is pcall'd in collection and rendering; collection failure prints four minimal facts; options.lua wraps the dispatch in pcall. Teardown map sorted count-desc/key-asc. Rates only when the denominator is nonzero. Error rows capped at 10, problems at 12, with explicit "...and N more".
- **Preserved:** banner, `|cff59f0dcTacoTip:|r` prefix, all test-pinned substrings (`gs-callback-misses=3`, `portrait mode: 2D Icon`, `cached data: yes`, `GearScore / iLvl:`, `none detected (system healthy)`, the stall/timeout/error texts), and every existing counter/label word. Only leading-space padding was removed.
- **Tests:** 24 structural pins in `Tests/harness/load_test.lua`, executed by every existing load_test invocation (12 per interpreter matrix cell) — collector contract, section ids/order, row contract, healthy/N verdicts, teardown determinism, inspect-frame with no events, portraitSetFailed/anchor/gs-callback rows, rates, uptime, zero-render warning, section failure containment, collection fallback, render fallback, error-history cap/truncation, load-failure problem. Invocation count stays 71.
- **Gates:** main 71/71 on lua5.1, lua5.4, luajit; `luacheck .` 0 warnings / 0 errors in 87 files; `verify_release --worktree` PASS (27 files); `verify_release_extras --worktree` PASS; `git diff --check` CLEAN.
- **Untouched:** portrait render path, scan code, `gearscore.lua`, `TacoTip_Extras/**`, interface list (120105), locale files. No new counters on hot paths; `TT.loadTime` is one load-time assignment.
- **Residual risk:** `CollectDiagnostics` calls `CI:GetInspectStats` twice (problems + inspect section) and recomputes GS only when every cached link's item data is already in the client cache; on a cold cache it prints "pending item data" rather than requesting. The report is ~61 lines for the healthy sample, at the target ceiling.

## 2026-10-26 — Lead review: one real bug found and fixed after the done signal

- **Found in review:** the inspect-frame row used the "and value or unknown" idiom. Because false is falsy, a HIDDEN InspectFrame -- the normal state -- printed unknown instead of false. Confirmed against the captured sample (InspectFrame shown: unknown while the fixture IsShown() returned false).
- **Fix:** branch on the pcall result, then pass the boolean. Two Lead pins added in Tests/harness/load_test.lua: a hidden frame reports false, and InspectFrame.unit reports the unit string rather than a function address. The helper parameter was renamed so it does not shadow the file-level label.
- **Also in this review:** CHANGELOG.md gained a 0.8.8 diagnostics bullet and the README 0.8.8 bullet was rewritten to describe the structured report.
- **Re-verified by the Lead after these edits:** main harness 71/71 on lua5.1 / lua5.4 / luajit; luacheck . 0 warnings / 0 errors in 87 files; package verifiers PASS; git diff --check clean.

