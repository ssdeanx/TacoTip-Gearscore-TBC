# stage6-errorpaths — Journal

## 2026-10-18 — Desk opened
- **Purpose:** silent-failure hunt over the MAIN TacoTip addon (pcall/xpcall/safeCall sites, fallbacks, retry/throttle paths, diag truthfulness, load-order fragility, mock-vs-game gaps).
- **Scope:** main.lua, options.lua, gearscore.lua, pawn.lua, textures.lua, LibForeverInspector, LibDetours, Tests/harness, README/CHANGELOG 0.8.3-0.8.4; ~92 handling locations reviewed.
- **Note:** reviewing session had read-only tools (no write/exec); journal, signals and bench report placed by the orchestrator from the lane's inline handoff.

## 2026-10-18 — [signal:done] Hunt complete: 4 confirmed CRITICAL, 11 HIGH (justification-needed), 9 justified exceptions
- **Criticals:** C1 queue overflow drops oldest inspect uncounted (LibForeverInspector.lua:4874-4877); C2 every clock falls back to 0, wedging cooldowns/throttles/freshness (gearscore.lua:111, lib multiple, main.lua:3742); C3 Pawn late-load permanent silent amputation (pawn.lua:11-16, options.lua:11-16); C4 file-scope aborts precede diagnosability (main.lua:7-9, lib:103).
- **Highs:** H1 merged scanSkippedDistance; H2 DoInspect true-means-queued; H3 safeCall dedup blindness; H4 unknown-talent `return 1` survivors; H5 absent C_Timer kills engine silently; H6 not-ready GS/Pawn read as absent; H7 options registration swallowed; H8 object-API-less item path fire-and-forget; H9 guild-guard uncounted; H10 single pending slot + watchdog attribution loss; H11 lastError/suppressed double-count.
- **Mediums:** M1–M10 (counters, resolver collapse, width cap J-exception, portrait discards, RegisterUnitEvent, media diag asymmetry, ruRU placeholder specs, WM catch-all, playerClass latch, unknown-bracket inheritance).
- **Report:** bench/audits/2026-10-18-maintip-errorpaths-audit.md (verbatim handoff).
- **Cross-cutting need:** operator call on cold-path diag allocation vs hot-path budget (main.lua:3331-3339).
