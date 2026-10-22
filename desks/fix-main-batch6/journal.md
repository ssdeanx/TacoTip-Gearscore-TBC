# fix-main-batch6 — Journal

## 2026-10-19 — Desk opened
- **Purpose:** Fix the 4 HIGH findings from bench/audits/2026-10-19-publish-readiness-hunter.md (H-NEW1–H-NEW4) plus 2 cheap hardening items (M-NEW4 loop-bound name, M-NEW1 Adapter fallback counter), MAIN addon only (+ Adapter/Tooltips debug-only counter). No commit, no staging. Every fix revert-to-fail proven in-harness.
- **Scope:** main.lua, options.lua, pawn.lua, Tests/harness/*.lua (pins ONLY), CHANGELOG.md (item-6 append ONLY), TacoTip_Extras/TacoTipAdapter.lua + TacoTip_Extras/Tooltips.lua (item-5 counter ONLY). NOT *.toc/versions, NOT README, NOT bench/, NOT other desks.
- **Constraints:** Era range gate FROZEN; raw formula UNTOUCHED; Retail HOLD at shared 1000; ruRU untouched (no invented strings).
- **Baseline:** `bash Tests/harness/run_all.sh` → 64/64 green (lua5.1; will re-verify all three interpreters at end). FrameXML evidence for dialog pool: Blizzard_StaticPopup_Game/GameDialog.xml:334-349 defines exactly StaticPopup1..4 (ids 1..4); no NUMDIALOGS constant in this mirror checkout.
- **Next step:** implement H-NEW1 (isSecureMenuBusy + MAX_STATIC_POPUP_DIALOGS + 4 early-returns + taint pins), H-NEW4 (spell-branch guard + pin), H-NEW3 (nil-scaleName early 0 + pawn pin), H-NEW2 (load-leg counters + problems[] + settings pin), item 5 (Adapter counter + Tooltips debug + loop-bound pin), CHANGELOG append. Then full validation + revert proofs.

## 2026-10-19 — H-NEW1 + M-NEW4 + H-NEW4 implemented + pinned (main.lua, taint_test.lua)
- **H-NEW1/M-NEW4:** `MAX_STATIC_POPUP_DIALOGS = 4` + `isSecureMenuBusy()` (`main.lua:4154-4174`; FrameXML cite `Blizzard_StaticPopup_Game/GameDialog.xml:334-349` exactly 4 frames). Early-returns in `onMoverTick`, both Show/Hide hooks, `ShowExample`; drag `OnUpdate` + right-click confirm routed through helper (superset: confirm now also skips on GameMenu, drag also on popups — stricter, safe).
- **H-NEW4:** `pcall`-guarded `parent:GetParent()` at both `isManagedAnchorTarget` and the spell branch (`main.lua:3037-3070,3099-3115`).
- **Mock findings (test-side only):** taint `C_Timer.NewTicker` now captures `func` (options_test precedent); `newFrame` absent-field dummy makes fresh frames read shown AND breaks `self.ticker:Cancel()` — seeded a cancellable ticker + explicit `Hide()` on GameMenu/StaticPopup fixtures; `TT.RefreshOptionsUI` stubbed for the mover block (dropdown globals absent in this mock). No production change for any of these.
- **Pins:** taint 11→32 checks, 32/32 ×5 clients. Reverts: guard no-op → 5/32 red (`setOwner=2`); bound+1 → 1/32 red; raw GetParent → 2/32 red. All restored identical (diff-verified), 32/32 again.

## 2026-10-19 — H-NEW3 + H-NEW2 + item 5 implemented + pinned
- **H-NEW3 (`pawn.lua:132-156`):** nil scaleName → `return 0` before any Pawn call. Pin `batch2_pawn_test.lua` §6: 25→28 checks, 28/28 ×3 interpreters. Revert (guessing path) → 1/28 red (`lookups=1`) ×3. Restored identical.
- **H-NEW2 (`options.lua:669-705,801-802`; `main.lua:3865-3874`):** `noteOptionsLoadFailure`/`optionsLoadAddOn` wrap all 6 probes → `TT.ev.optionsLoadFailures` + `TT.ev.lastOptionsLoadError` → problems[] entry. File-local `LoadAddOn` capture removed → call-time `_G.LoadAddOn` reads (enables forced-failure pin). Pin `settings_test.lua` nosettings runs: 70 checks ALL PASS ×3. Revert E1 (bare pcalls) → 3/70 red; E2 (no problems entry) → 1/70 red. Restored.
- **Item 5:** Adapter `scoreColorFallbacks`/`lastScoreColorReason` (`TacoTipAdapter.lua:2085-2147`) + `Adapter.GetDebugState` + `GetCapabilityReport` fields; `Tooltips.GetDebugState` (`Tooltips.lua:758-770`). Debug-only, returns unchanged. Ad-hoc probes (all 3 interpreters): 0→2 with reasons, report surfaced; revert (no counting) → probe rc=1 ×3, restored rc=0. Tooltips reflects adapter (0→1 `equipment-gate`).
- **Correction mid-task:** report fields first added to `captureCompatibility()` return (wrong table — probe showed nil); moved to `GetCapabilityReport`.
- **Observation (flagged, not deviated):** H-NEW2 problems[] entry is ungated per spec — Classic will always count the 4 Settings loads, Retail the 2 OptionsUI loads, in-game. Whether missing-addon loads raise or return falsy is unverifiable offline; either way counted + named. Operator may gate later.

## 2026-10-19 — CHANGELOG + full validation
- **CHANGELOG:** new `### Hunter re-audit fixes` under `[0.8.4]` (items 1–5 with file:lines); quit-fix paragraph extended one clause (helper now covers ticker/hooks/ShowExample/drag/confirm — claim now true). 0.8.3 and earlier untouched.
- **Validation:** `bash Tests/harness/run_all.sh` → 64/64 on lua5.1, lua5.4, luajit. luacheck 0/0 (main+options+pawn+gearscore+textures+lib; fixed 1 shadow warning `options.lua:673` by using the TT upvalue). Extras `run_all.sh` → 42/42 (no breakage). Extras luacheck 0/0.
- **Constraints:** range gate frozen (lib untouched by this desk; identifiers verified present); gearscore.lua untouched by this desk (formula + Retail-1000 hold intact); ruRU untouched; no *.toc/version/README/bench/other-desk touches; no staging (`git diff --cached` empty).
- **Explicitly unaddressed:** H2 tri-state, L-NEW1/M7, M8, M-NEW2/M-NEW3/M-NEW5/M-NEW6, L-NEW2, L-NEW3/L-NEW4/L-NEW5, O1–O10, proctor 8–10.
- **Next step:** operator review (publish-hunter verdict update + H-NEW2 gating decision).

## 2026-10-19 — Expansion opened (operator: get as many as we can)
- **Purpose:** Fix M-NEW2, M-NEW3, M-NEW5, M-NEW6, L-NEW3, L-NEW4, L-NEW5 from the same hunter audit. All zero-behavior-change (counters, comments, pins, docs only). Still OUT: H2, L-NEW1/M7, M8, L-NEW2, O1–O10, proctor 8–10.
- **Scope note:** production now also touches `TacoTip_Extras/RankBrowser.lua` (M-NEW6 validation+counter+debug, L-NEW3 comment, L-NEW5 clock doc). Pins: MAIN `Tests/harness/taint_test.lua` (M-NEW2, same file as batch6); Extras `TacoTip_Extras/Tests/harness/load_test.lua` (M-NEW5) + `rankbrowser_test.lua` (M-NEW6) — the files that already drive those exact code paths; no new harness patterns.
- **Next step:** implement 4 counters + 1 acceptance comment + 3 doc comments, pin all pinnable, revert-prove each, full validation.

## 2026-10-19 — Expansion done: M-NEW2/3/5/6 + L-NEW3/4/5, all pinned where pinnable
- **M-NEW2 (`main.lua`):** `isManagedAnchorTarget` returns skip kind (`addon`/`menu`/`unresolved` via `sawUnitSignal`); post-hook counts `anchorSkippedMenu`/`anchorSkippedUnresolved` (neutral tallies) + 2 diag lines in event counters (problems[] untouched). Pin `taint_test.lua` block (e): 37/37 ×5 clients. Revert (drop increments) → 2/37 red. Restored identical.
- **M-NEW3 (comment only, `main.lua`):** LibDBIcon acceptance note at the anchor-hook install. Verified by reading `LibDBIcon-1.0.lua:21` (own `LibDBIconTooltip` frame), `:80-83`/`:111-114` (`SetOwner ANCHOR_NONE` on itself). No pin (nothing to drive).
- **M-NEW5 (`Tooltips.lua`):** `rankRecordErrors`/`lastRankRecordError` at both `GetRecord` pcall sites + `GetDebugState`. Pin Extras `load_test.lua`: forced raise → lines empty + counter+1 + named. Revert (drop notes) → 2 checks red ×3 interpreters. Restored.
- **M-NEW6 (`RankBrowser.lua`):** numerics validation before `ClearLines` + `rowTooltipErrors`/`lastRowTooltipError` + `RankBrowser.GetDebugState`. Pin Extras `rankbrowser_test.lua`: corrupt hover → no raise, `clearCalls=0`, owner nil, counter+1. Revert (drop validation) → 4/257 red ×3 (raise + `clearCalls=1` + counter 0). Restored identical, 257/257 ×3.
- **L-NEW3/4/5 (comments only):** strata chain + 100/200 + 0.9 evidence (`GameMenuFrame.xml:4`, `SettingsPanel.xml:4` verified in mirror); Pawn floor provenance; two-session clock docs both ends.
- **CHANGELOG:** `### Hunter re-audit follow-ups` under `[0.8.4]` (7 bullets).
- **Validation:** main 64/64 ×3; Extras 42/42; main lint 0/0 (6 files); Extras Adapter/Tooltips 0/0. RankBrowser has 2 PRE-EXISTING luacheck warnings (`:372` bare `GetServerTime` in `formatRelativeTime` — untouched by this desk, left alone as out-of-scope).
- **Scope note:** Extras harness pins (`load_test.lua`, `rankbrowser_test.lua`) — those files already drive the exact code paths; no new harness patterns (before/after + save/restore idioms copied from adjacent blocks).
- **Constraints:** formula + Retail-1000 intact (gearscore untouched); range gate frozen (lib untouched by this desk); ruRU untouched; no toc/version/README/bench/other-desk touches; no staging.
- **Still OUT:** H2, L-NEW1/M7, M8, L-NEW2, O1–O10, proctor 8–10.
- **Next step:** operator review (publish-hunter verdict update + H-NEW2 gating decision from batch6 still open).
