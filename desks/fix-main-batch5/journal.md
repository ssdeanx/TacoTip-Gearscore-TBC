# fix-main-batch5 — Journal

## 2026-10-18 — Desk opened
- **Purpose:** Batch 5 final pre-publish hardening (MAIN addon ONLY): (1) Retail bracket hold at 1000 — remove Retail special-case, keep explicit unknown-1000; (2) N3 pawn probe hygiene — single home for 2.0538/2.0 thresholds + tonumber guard; (3) doc touch-ups (harness README counts, README stale path/args); CHANGELOG Batch-5 append.
- **Scope:** gearscore.lua (item 1 ONLY), pawn.lua + options.lua (item 2 ONLY), Tests/harness/*.lua + Tests/TacoTip_Forever_Tests.lua (pins ONLY), CHANGELOG.md (Batch-5 append ONLY), README.md (Retail bracket lines + item-3 bits ONLY), Tests/harness/README.md (counts ONLY). NOT Extras, NOT *.toc/versions, NOT bench/, NOT other desks.
- **Constraints:** Era range gate FROZEN; raw formula UNTOUCHED; Retail HOLD AT 1000 per operator.
- **Next step:** read run_all.sh + conventions end-to-end, baseline 59 green, then implement.

## 2026-10-18 — Baseline + workshop protocol
- **Bench-read:** fix-main-batch4, stage6-reaudit, main-publish-docs journals + re-audit N1/N3 deltas. **Read `run_all.sh` end-to-end** (34 static `run` lines expand to 59 invocations via slot loops + file-scope matrix). No new harness patterns used (all pins appended to existing files).
- **Baseline (pre-change):** 59/59 green on lua5.1, lua5.4 AND luajit.

## 2026-10-18 — Item 1 hand-math (operator live max ~345, 1000 domain)
- Table A rarity 4: base=(345-91.45)/0.65=390.0769; x1.8618: SlotMOD 1.0→**726**, 0.75→**544**, 0.5625→**408** (lua5.1-verified floors).
- Re-audit reference set (5x1.0 + 4x0.75 + 7x0.5625, same set that gave 8832@350 / 10542@400 — recomputation reproduces both exactly): total = 5*726+4*544+7*408 = **8662**.
- 1000 domain ceiling MAX=7000: 8662 > 7000 so GetQuality **clamps to Artifact**. Plain meaning (no spin): holding 1000 keeps Retail at constant Artifact-red across the whole live tier — zero band spread, the top-end mirror of the collapse Batches 3/4 fixed. Accepted deliberately pending one live screenshot; any future bracket must place ~8.7k mid-ramp (2000 did: Epic).
- **Next step:** implement hold + pins with revert proofs.

## 2026-10-18 — Item 1 done (Retail hold at 1000)
- **Production (`gearscore.lua:162-194`):** Retail special-case branch removed (2 lines); Retail rejoins the `1000` default line; explicit unknown-`1000` branch kept byte-identical. Batch-3/4 calibration paragraphs replaced with a HOLD note (live ~345 → ~8.7k > 7000 ceiling → constant Artifact; raw scores/iLvl untouched). Formula tables untouched.
- **Pins:** run_all.sh:69,100 + comment 124-125 (retail literals 1000); gearscore_test.lua:38 + :363-366 (restored HEAD 3-column 1000-band tables, `[2000]` column deleted); TacoTip_Forever_Tests.lua:646 (`expected = 1000`, explicit line kept per M10 explicit-default philosophy); **detect_test.lua:159,173 as 4th site** (downstream mirror + scenario 2000→1000 — Batch-4 deviation precedent; without it the suite would pin 1000 and 2000 for Retail simultaneously).
- **Revert proof (production 2000 restored, temp):** `gearscore_test RETAIL` → `bracket=2000 5/35 FAILED` (`bracket for RETAIL = 1000 got 2000`; head/ranged/trinket/2H band nils); `load_test RETAIL` → `FAIL bracket=2000 want=1000`. Restored → ALL green.
- **Why explicit `= 1000` lines kept in test files** (not HEAD fallthrough): M10 philosophy — named defaults fail loudly and diff as one literal; behavior-identical (suite green proves it).

## 2026-10-18 — Item 2 done (N3 pawn probe hygiene, TT_PAWN home)
- **Why TT_PAWN, not TT_GS:** the knowledge is pawn-domain (Pawn's version-global contract + API fallback); homing it in the gearscore module would repeat the arbiter-#4/#5 mistake in reverse. `TT_PAWN.IsAvailable` already exists as the live probe — zero new machinery, one implementation, two call sites. toc order (gearscore→pawn→options) + runtime-only calls make it safe.
- **Edits:** `pawn.lua:15-29` (threshold constants + `pawnVersionAtLeast` tonumber guard, both consumers route via `IsAvailable`); `options.lua:24-39` (routes to `TT_PAWN.IsAvailable` at call time; same-shaped tonumber-guarded fallback for the pawn-missing invalid state only — behavior-identical for numeric input, fail-safe otherwise).
- **Pin:** `batch2_pawn_test.lua` §5 (5 checks: "2.0" no-raise+available, "2.0.1-beta" no-raise+absent, garbage+API→available). 20→25 checks.
- **Revert proof (unguarded compare restored, temp):** `5/25 FAILED` on **all three** interpreters — `FAIL string-typed retail version does not raise  err=./pawn.lua:27: attempt to compare number with string` (same for the other 4; even the numeric string raises — all interpreters refuse string>=number ordering). Restored → 25/25 on all three.

## 2026-10-18 — Items 3-4 done (docs + CHANGELOG)
- **Harness README (counts ONLY):** 54→59 invocations, six→thirteen files (14 .lua minus root.lua helper), 54/54→59/59 x3. Path prefixes (lines 9,20) left stale — out of scope, noted.
- **Main README:** Retail lines rewritten as hold (spread claim withdrawn, constant-Artifact stated plainly); Testing 58→59; `TacoTip_Forever/` prefix dropped (verified: no such dir; siblings use addon-root-relative). `load_test` example (line 310) verified byte-matching run_all.sh:65 for slot4 → no edit.
- **CHANGELOG:** `### Batch 5` appended under `## [Unreleased]` (items 1-3 with file:lines; Batch 3/4 Retail paragraphs kept as history, Batch 5 records superseding decision). Table row + 0.8.4 and earlier untouched (row's "Batches 1–4" phrasing stays true as history).
- **Out of scope, unaddressed:** H2, M7, M8, O1–O10, proctor gaps 8–10, Tests/harness/README path prefixes, run_all.sh header usage line, CHANGELOG Unreleased table-row refresh (append-only constraint). Candidate spotted but NOT implemented: `detect_test` bracket mirror duplicates the production mapping without consuming it (self-consistent, never red on production drift) — same class as the N1 pins but one indirection away; left for operator.

## 2026-10-18 — [signal:done] Batch 5 complete, validation quoted below
- **Suite:** 59/59 green on lua5.1, lua5.4, luajit (post-change). Shipped lint 0 warnings / 0 errors (gearscore+pawn+options+main+lib).
- **Range-gate compliance:** main.lua + lib untouched by this batch (no diff lines possible); probe-guard/ordering/ceiling/timings unchanged (only clockAvailable-adjacent branches exist from Batch 4, untouched).
- **Formula compliance:** GS_Formula/SlotMOD/Scale/QualityScale/TitanGrip/Hunter literals untouched (edit regions: bracket comments+branch, probe thresholds only).
- **Bracket-hold compliance:** no IsRetail branch in production; `grep 2000` in *.lua hits only interface numbers/clocks; retail==1000 in gearscore_test, detect_test, Forever tests, run_all args.
- **No commit, no staging** (`git diff --cached` empty). No Extras/toc/bench/other-desk touches.
