# stage6-tests — Journal

## 2026-10-18 — Desk opened
- **Purpose:** test-sufficiency review of the MAIN TacoTip addon Tests/ (offline harness + in-game suite) at v0.8.4: behavioral coverage, regression risk, high-value gaps, green-for-wrong-reason audit.
- **Scope:** run_all.sh, root.lua, README, detect/load/tooltip/settings/options/gearscore/textures/locale/font/talent tests, in-game TacoTip_Forever_Tests.lua.
- **Note:** reviewing session had read-only tools (no write/exec); journal, signals and bench report placed by the orchestrator from the lane's inline handoff.

## 2026-10-18 — [signal:done] Coverage verdict: ADEQUATE (not GOOD) — top-10 gaps ranked, vacuity verdicts per file
- **Important (7-8):** 0.8.4 instant-fade shim guard unpinned; 0.8.4 GSCallback terminal-error surfacing unpinned; 0.8.4 scan-toggle wiring unpinned; in-game portrait alpha test contradicts production; Baganator positive control absent (documented necessity).
- **Moderate (5-6):** in-game magic counts stale (251/40 vs 239/66); item-data 2.0s throttle unpinned; portrait accounting guards likely vacuous; remote group-2 active-group narrow.
- **Vacuity:** main.lua WEAK on 0.8.4 paths / STRONG on pipeline+teardown; options/pawn STRONG except scan wiring; gearscore STRONG except throttle; textures STRONG; LibForeverInspector STRONG (only yardage values deliberately unpinned).
- **Report:** bench/audits/2026-10-18-maintip-test-sufficiency.md (verbatim handoff).
