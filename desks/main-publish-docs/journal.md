# main-publish-docs — Journal

## 2026-10-18 — Desk opened
- **Purpose:** Document Stage-6 Batches 1–3 (as landed) in main `CHANGELOG.md` + `README.md`. Code truth is the landed tree; batch journals are leads only.
- **Scope:** `CHANGELOG.md` (new `Unreleased` section + table row; 0.8.4 untouched), `README.md` (user-visible behavior only + harness count 54→58), this desk's `journal.md` + `.signals/`.
- **Constraints:** no commit/staging; no code/tests/TOC/version/Extras/bench/THIRD_PARTY_NOTICES touches; no invented version number.
- **Next step:** verify every claim against code (done — see entry below), then edit.

## 2026-10-18 — Verification pass (code is truth, all VERIFIED)
- Batch 1: `SafeSanitizeConfig` allowlists (`options.lua:216-278`, `352-373`); spec-nil fallback (`LibForeverInspector.lua:5353-5377`, `5540-5554`; caller gates `main.lua:2117-2118`, `or 1` at `main.lua:2146`); queue-drop stats (`LibForeverInspector.lua:4927-4939`, diag `main.lua:3612-3616`); soft aborts + `LOAD_STAGE="begin"` (`main.lua:7-30`), `GetBuildInfo` guard (`LibForeverInspector.lua:107-117`).
- Batch 2: Pawn call-time gate (`pawn.lua:169-172`), snapshot + live probe (`pawn.lua:19,96-97`; `options.lua:2591-2595`; render gate `main.lua:139,2235`; diag `main.lua:3752-3754`); shared throttle (`gearscore.lua:102-118,135`; `pawn.lua:35-45`); `DrainItemCache` alias (`pawn.lua:143-166`); cold-path counters (`main.lua:307-313,1092-1101,1127,1137,1307,1316,3312`; diag `3518-3530,3807-3809`).
- Batch 3: Retail 3000 + explicit unknown-1000 (`gearscore.lua:175-196`); `tickersInstalled` + `ADDON_LOADED` retry (`LibForeverInspector.lua:3861-3867,5258-5280`; diag `main.lua:3769-3771`); `gsPendingHidden` shared home (`gearscore.lua:141-144,617-619`; `pawn.lua:248-251`; diag `main.lua:3520`); narrow pcalls + `optionsRegErrors` + scan-apply + checkbox-from-library (`options.lua:39-62,664-718,720-769,2233-2242,2600-2604`; diag `main.lua:3759-3763`); fire-and-forget + bounded repaint (`main.lua:2720-2750`; diag `3521`); watchdog grace + queue waits (`LibForeverInspector.lua:3722-3727,3782-3789,4964-4979,5014-5019`; diag `main.lua:3591-3597`); `lastErrorAt` (`LibForeverInspector.lua:4403`; diag `3589`); power-bar fallback + counter (`main.lua:2430-2451,3522`); 4-key media diag (`main.lua:3680-3716`); per-call class (`main.lua:254-260`; lib lazy glyph `875-886`); unknown-family diag (`main.lua:3662-3664`); in-game portrait contract (`Tests/TacoTip_Forever_Tests.lua:335-361`) + Baganator positive (`496-523`); harness total counted from `Tests/harness/run_all.sh` `run` lines = 58.
- Classic Era range gate confirmed untouched (`NEARBY_ASK_YARDS`, `INSPECT_INTERACT_DISTANCE_INDEX`, ordering) — no yardage claim written.
- Could NOT verify in-game (no client, no shell here): in-game suite results, live Retail totals above old 7000 ceiling (already flagged ASSUMED in code comment `gearscore.lua:164-169`). Harness total 58/58 quoted from batch-3 journal, not re-run here.

## 2026-10-18 — [signal:done] Docs written
- `CHANGELOG.md`: `Unreleased` table row + `## [Unreleased]` section (Batches 1–3, claim-by-claim with file:line). 0.8.4 and everything below untouched.
- `README.md`: new `What's New in Unreleased` (user-visible only: Retail colours, Pawn late-load, scan checkbox honesty, options-failure message, new diag lines) + harness count 54→58.
- Left stale on purpose (out of scope): `Tests/harness/README.md` count; `README.md` Testing `run_all.sh` path (`TacoTip_Forever/...` prefix) and `0.8.4`-era `51/51` line; `README.md` example `load_test` args.
