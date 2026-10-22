# fix-anchor-gate — Journal

## 2026-10-22 — Desk opened
- **Purpose:** FIX lane for the operator-verified re-hover tooltip anchor defect.
  Ranked cause #1 (bench `current-tooltip-save-regression.md`): hop B2 —
  `onGameTooltipSetDefaultAnchor`'s `isManagedAnchorTarget` gate skips the
  `custom_pos` re-pin on empty live tooltip residue (the re-hover shape), leaving
  the client's BOTTOMRIGHT park live for the whole hover. 0.8.3
  (`bench/findings/prior-tooltip-save-mechanism.md`) re-pinned unconditionally.
- **Scope:** this repo only. Edit surface: `onGameTooltipSetDefaultAnchor` in
  `main.lua` (~4028-4100) + pins in `Tests/harness/tooltip_test.lua`.
  Hook registration (`runUntainted` wrapper) unchanged; render-time
  `applyCustomTooltipAnchor` call at ~2009 left in place; no other files.
  Tree is DIRTY with uncommitted width/portrait-edge hunks in `main.lua` and
  `Tests/harness/tooltip_test.lua` — they must survive.
- **Evidence authority (read, not re-derived):**
  `bench/findings/prior-tooltip-save-mechanism.md`,
  `bench/findings/current-tooltip-save-regression.md`,
  `bench/findings/anchor-client-truth.md`.
- **Next step:** apply the ungated-custom_pos fix, pin re-hover shape in the
  harness, mutation-proof per pin on a copy, full suite + luacheck +
  verify_release, journal + `done` signal ("pinned in the harness, not
  observed in game").

## 2026-10-22 — [signal:done] custom_pos re-pin ungated in the SetDefaultAnchor hook; re-hover pins added
- **Worked on:** `onGameTooltipSetDefaultAnchor` (main.lua:4064-4081). The
  `isManagedAnchorTarget` skip now counts (menu/unresolved) and returns early
  ONLY when `anchor_mouse` is on or `custom_pos` is nil; with `custom_pos` set
  and the cursor path off, the skip falls through to the existing
  `ClearAllPoints` + `SetPoint(anchorPoint, TacoTipDragButton, anchorPoint)`
  at 4095-4098 — the 0.8.3 idiom, on EVERY call. Hook registration
  (`runUntainted`) untouched; render-time `applyCustomTooltipAnchor` call
  untouched; anchor_mouse_spells / anchor_mouse / two-bar branches untouched.
- **Pinned in `Tests/harness/tooltip_test.lua`** (new block before the fails
  tally, all 5 families): (A) re-hover shape — empty residue (`GetUnit` nil,
  `IsUnit` false, no owner.unit, `TooltipUtil.GetDisplayedUnit` nil on
  pipeline) + `custom_pos` set + seeded client BOTTOMRIGHT park → the hook
  ends with exactly ONE point relative to the raw `TacoTipDragButton` frame at
  the saved anchor; (B) the menu-skip counter still tallies AND the re-pin
  still happens on that counted call. Per-pin residue reset.
- **Mutation proof** (copy at /tmp/opencode/anchor-gate-mut, fix reverted to
  the unconditional gate `return`, new pins kept): TBC_ANNIV + CLASSIC_ERA →
  `FAIL re-hover with empty residue ... relIsHandle=false point=BOTTOMRIGHT/BOTTOMRIGHT`
  and `FAIL ...and the re-pin still happened ... relIsHandle=false` (2/249
  FAILED both branches) — the seeded client park survives, i.e. the defect
  itself. Copy deleted after.
- **Validation:** `run_all.sh` TOTAL 71 invocations: 71 passed, 0 failed;
  `luacheck .` 0 warnings / 0 errors in 88 files;
  `Tools/verify_release.sh --worktree` PASS. Pre-existing dirty width/portrait
  hunks in main.lua and tooltip_test.lua preserved (diff is additive).
- **Reporting:** pinned in the harness, NOT observed in game. The operator's
  next hover on classic_anniversary (then classic_era) is the only acceptance.
- **Next step:** operator in-game observation. If the re-hover still smears,
  next diagnostic is `/tacotip diag` counters (`anchorSkippedMenu`,
  `anchorSkippedUnresolved`, `anchorHookFailed`) — the gate still tallies.

## 2026-10-22 — [signal:accepted] operator confirmed in game
- Operator: "gj it works!!" — the re-hover position defect is observed fixed on classic_anniversary (his play branch). This is the acceptance hands-up.md names: in-game hover, not the harness. Harness pin claim upgraded from "pinned, not observed" to observed.
- Shipped as `dad58ec` on origin/main (with `dea3fcb` width/portrait and `61451d2` docs). Desk closed.
