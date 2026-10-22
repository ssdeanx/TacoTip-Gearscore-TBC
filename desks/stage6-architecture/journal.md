# stage6-architecture — Journal

## 2026-10-18 — Desk opened
- **Purpose:** architecture/correctness review of the MAIN TacoTip addon tree at v0.8.4 (delivery paths, data flow, detection, formula, options, dead code, patch hazards).
- **Scope:** main.lua, gearscore.lua, pawn.lua, textures.lua, options.lua, Libs/LibForeverInspector/, Tests/harness docs; five clients 11509/20506/38002/16001/120105.
- **Note:** reviewing session had read-only tools (no write/exec); journal, signals and bench report placed by the orchestrator from the lane's inline handoff.

## 2026-10-18 — [signal:done] Review complete: 0 critical/blocker, 2 major, 5 minor, 4 info
- **Verdict:** tree in unusually good shape; no merge-blocking defect. Majors: (1) Retail scores saturate the shared 1000-bracket — endgame renders Artifact-red (gearscore.lua:147-160; design decision needed); (2) inspected-unit spec falls back to 1 on the nil-contract path (LibForeverInspector.lua:5268-5272).
- **Minors:** gsCallbackPending single-slot drop; Pawn throttle bypass; unreachable branches/duplicated helpers; sanitizer string gaps (custom_anchor, media paths); GetScore per-slot GetItemInfo re-resolution.
- **Infos:** unknown-family bracket inheritance; dual registration fail-safe (cleared); modern talent mock-surface dependency; coalesce tradeoff (cleared).
- **Report:** bench/audits/2026-10-18-maintip-architecture-review.md (verbatim handoff).
- **Handoff:** live-client eyes list (Retail color ramp, restricted-unit spec, Era range hover, TBC/Titanforge double-render + dual-spec, mover/reset/style/deprecation-fallback checks).
