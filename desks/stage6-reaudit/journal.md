# stage6-reaudit — Journal

## 2026-10-18 — Desk opened
- **Purpose:** re-audit the MAIN TacoTip addon after fix Batches 1–3: prove no new silent-failure paths, no broken previously-fixed paths; verify right-click inspect crash fixes still hold; recompute Retail bracket math against operator-corrected ilvl 350–400.
- **Scope:** batch desks fix-main-batch1/2/3 (journals + signals bench-read), prior four maintip audits, right-click paths (ClearInspectPlayer removal, InspectFrame.unit fallback, guild guard), bracket block, frozen invariants.
- **Note:** reviewing session had no write/exec tools; journal, signal and bench report placed by the orchestrator from the inline handoff.

## 2026-10-18 — [signal:done] Re-audit complete: NEEDS FIXES (no new CRITICAL)
- **N1 HIGH:** Retail 3000 miscalibrated for ilvl 350–400 (8832→Uncommon, 10542→Superior; 0.57 band span). Correct: BRACKET_SIZE=2000 (8832→Epic, 10542→Legendary, matching Era/TBC placement). Fix + three pin-site updates required.
- **N2 MEDIUM:** pawn.lua:182 `or 1` bypasses Batch-1 spec-nil fix on the Pawn consumer. Sketch provided.
- **C2 carried STILL OPEN** (never assigned): clock-or-0 wedges persist.
- **Right-click inspect HOLDS:** all four 0.7.9 mechanisms present, unweakened, batch diffs clean of those lines; gaps are harness-pinning only, in-game checks named.
- **Frozen invariants re-confirmed:** Era gate, timings, raw formula, M7 untouched, no Extras/toc/version touches.
- **Report:** bench/audits/2026-10-18-maintip-batch123-reaudit.md (verbatim handoff).
