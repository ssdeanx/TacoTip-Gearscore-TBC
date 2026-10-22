# Audit Anchor Fix — Journal

## 2026-10-22 — Desk opened
- **Purpose:** Independent audit lane for the `fix-anchor-gate` fix in `main.lua`
  `onGameTooltipSetDefaultAnchor` (~4064-4081). Re-verify the fixer's claims:
  three-path trace vs 0.8.3 (`/home/sam/TacoTip/main.lua:2840-2842`), branch
  order, counters, dirty-hunk preservation, independent validation
  (harness/luacheck/verify_release), and a revert proof of the new pins.
- **Scope:** `/home/sam/TacoTip-Gearscore-TBC` (read-only for code), plus a
  throwaway copy under /tmp for the revert proof. Writes limited to this desk
  dir, one bench file (`bench/findings/audit-anchor-fix.md`), signal JSON.
- **Next step:** Read bench findings + workshop/hands-up/CAIRN rules, then run
  the code trace, validation, revert proof; write bench finding; emit signal.

## 2026-10-22 — Audit complete: PASS — fix-anchor-gate re-pin verified
- **Worked on:** Full independent audit of the `onGameTooltipSetDefaultAnchor`
  fix. Trace vs 0.8.3 (`/home/sam/TacoTip/main.lua:2835-2843`): hook re-pins
  unconditionally on every call when custom_pos set + anchor_mouse off
  (`main.lua:4078-4098`); ClearAllPoints precedes SetPoint; mouse/spell/nil
  modes and the bottom-right branch byte-shape-unchanged; counters tally
  without gating. Render-path early returns (2519/2623/2624) remain skippable
  but the 0.2s client re-drive (anchor-client-truth) now covers position every
  tick — no window. Diff additive-only: 8 hunks, 7 width/portrait = the
  recorded 23+/16- dirty state, fix hunk = -1/+9 at 4062→4069; only main.lua +
  tooltip_test.lua modified, no options/gearscore/.toc/Locale.
- **Current state:** Validation all green run by this desk: run_all 71/71 on
  lua5.1+lua5.4+luajit; luacheck 0 warnings/0 errors in 88 files;
  verify_release --worktree PASS. Revert proof on own /tmp copy (bare return
  restored, counters kept): both new pins RED on all five families
  ("...one point on the drag handle points=1 relIsHandle=false
  point=BOTTOMRIGHT/BOTTOMRIGHT" and "...re-pin still happened on that counted
  call relIsHandle=false"), exactly 2 failures each, copy deleted. Failure
  hunt: non-unit SetDefaultAnchor callers (ActionButton/SpellFlyout/panel
  frames, mirror grep) behave as in 0.8.3; taint containment is runUntainted,
  untouched. Cosmetic note: "anchor passthrough" diag labels now overstate for
  custom_pos-on (those calls re-pin; counters are classification tallies).
- **Artifact:** `bench/findings/audit-anchor-fix.md`.
- **Next step:** Operator's in-game hover on classic_anniversary is the only
  acceptance (save → leave → re-hover same unit and an item button). If a
  symptom survives, instrument `/tacotip diag` counters before any new fix.

## 2026-10-22 — [signal:done] audit PASS — fix-anchor-gate re-pin verified
- Bench: `bench/findings/audit-anchor-fix.md`. Validation green on this lane's
  own runs (71/71 x3 interpreters, luacheck 0/0, verify_release PASS); revert
  proof: both new pins RED on all five families on a reverted /tmp copy.
- In-game acceptance remains the operator's hover — "pinned in the harness,
  not observed in game".
