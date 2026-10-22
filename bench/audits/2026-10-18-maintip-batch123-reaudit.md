# Silent Failure Hunt: Main TacoTip addon — Batches 1–3 re-audit (stage6-reaudit, run_id "reaudit1")

**Placement note:** reviewing session had no file-write and no shell tools; this report is filed verbatim from its inline handoff by the orchestrator. Harness invocation count VERIFIED by reading run_all.sh = 58; totals quoted from batch journals, not re-run.

**Reviewing:** working-tree state after fix-main-batch1/2/3. **Files reviewed:** 13 + 4 journals + 4 signals + run_all.sh. **Error-handling locations:** ~60. **Suspicious patterns:** 9. **Disposition:** 0 new CRITICAL, 1 new HIGH, 1 new MEDIUM, 7 observations/justified.

## Verdict: NEEDS FIXES (no new CRITICAL; one HIGH miscalibration, one MEDIUM bypass, four pre-existing carryovers)

No batch introduced a new critical silent-failure path, and no previously-fixed path was broken on its fixed consumer. But Batch 3 calibrated the Retail bracket against a wrong assumption (operator-corrected: Retail ilvl is 350–400, not ~650) and bakes it into production + pins (HIGH), and Batch 1's spec-nil fix is bypassed on the Pawn consumer (MEDIUM). C2 (CRITICAL) was never assigned to any batch and is STILL OPEN — carried, not regressed.

## Critical disposition: C1–C4

- **C1 (queue-drop uncounted) → FIXED.** Counted (`queueDropped`, `lastQueueDropGuid/Age`); diag lines; revert-proven pins.
- **C2 (clocks fall back to 0) → STILL OPEN (carried, not regressed).** All `or 0` sites unchanged; wedges persist. Requires Batch 4: load-time clock probe + problems[] entry + fail-open.
- **C3 (Pawn late-load) → FIXED.** Call-time gate, live probe, diag problem; pins in batch2_pawn_test + settings + tooltip. Residuals → N3 (LOW).
- **C4 (file-scope aborts) → FIXED with noted boundary.** `gearscore.lua:10-12` / `pawn.lua:21-23` hard asserts still precede main in toc order — but can only fire when LibStub exists and a bundled lib fetch fails (LOUD, not silent). Accepted; fileguard_test pins the main.lua leg.

## New findings

**N1 [HIGH]: Retail `BRACKET_SIZE=3000` miscalibrated against ilvl 350–400.** `gearscore.lua:175-196` (+ pin sites run_all.sh:69, gearscore_test.lua:38, TacoTip_Forever_Tests.lua:646). Math (Table A, rarity 4: `floor((ilvl−91.45)/0.65 × SlotMOD × 1.8618)`): ilvl 350 → 16-item set **8832** → band (6000,9000] = Uncommon; ilvl 400 → **10542** → band (9000,12000] = Superior. With 3000-bands the entire current tier spans 0.57 of one band (green/blue mirror of the bug Batch 3 fixed). With **BRACKET_SIZE=2000** (MAX 14000): 8832 → (8000,10000] = Epic; 10542 → (10000,12000] = Legendary — matching Era (≈Legendary) and TBC (≈Epic) endgame placement. **Required fix:** 3000→2000 + three pin-site updates + comments; keep explicit unknown-1000 branch. In-game Retail colour-spread screenshot still required. Classic Era 200 / TBC 400 / Forever 200 / Titanforge-default 1000 VERIFIED behavior-identical (M10 FIXED).

**N2 [MEDIUM]: Batch-1 spec-nil fix bypassed on the Pawn path — `pawn.lua:182` `or 1`.** Re-invents spec 1 where the lib now returns nil; resolves a proven scale and returns score + spec-1 name for unknown-spec units. Main path nil-gated (FIXED); Pawn consumer preserves pre-batch behavior (PARTIAL, not a regression). Fix: `local spec = CI:GetSpecialization(guid); if (not (spec and class)) then return 0,"","|cffffffff" end`, mirroring main's gate.

**N3 [LOW]: duplicated Pawn probe + unguarded version compare** (`pawn.lua:8-14`, `options.lua:20-28`). Fix: `tonumber()` + single home.

**Observations (Batch-4 candidates):** (a) `options.lua:749-752` LoadAddOn pcalls unrecorded; (b) sanitizer repairs uncounted; (c) ring is first-5-appends not top-5; (d) M5 absent-leg falls back with no count (justified); (e) ticker-cancel pcalls swallowed (benign); (f) pre-existing NaN/GetOwner/GetUnit/glyph items; (g) `options.lua:95` xpcall unguarded (pre-existing, loud).

## H1–H11 / M-set disposition delta

FIXED: H1, H3, H5, H6, H7 (residual (a)), H8, H9, H10, H11, M1, M2, M4, M5 (residual (d)), M6, M9, M10. PARTIAL: H4 (main fixed; pawn leg = N2). STILL OPEN: H2 (tri-state never decided), C2, M7 (ruRU VERIFIED untouched), M8 (deferred). Justified: M3, main `or 1` highlight default.

## Right-click inspect verdict: HOLDS

1. No `ClearInspectPlayer` in INSPECT_READY (zero production call sites). 2. `InspectFrame.unit` fallback at both sites (lib:3767-3769, :4058-4061). 3. Guild-guard pcall narrowed + counted (main.lua:3301-3316), PINNED. 4. Non-targeted resolution three-layer + queue/grace/watchdog PINNED. No batch touches these lines. Harness gaps (no client): ClearInspectPlayer-absence, unit fallback, token-mapping pins — in-game checks: (i) sequential two-player inspect; (ii) right-click-inspect non-target party/raid member; (iii) force guild-frame error, diag shows guard count ≥1.

## Frozen invariants: RE-CONFIRMED

Era gate 20/40, index 1, distance-first ordering, probe guard, learned ceiling, timings all consistent. Raw formula literals VERIFIED. textures.lua untouched. toc 0.8.4 unchanged. No Extras markers. CHANGELOG Batch 1–3 section exists (docs-desk owned).

**Bottom line:** safe to keep — but do not call Batches 1–3 done: fix N1 (HIGH, numbers above), N2 (MEDIUM, sketch above), carry C2/H2/M7/M8 into Batch 4.
