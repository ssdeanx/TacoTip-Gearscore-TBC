# stage6-security — Journal

## 2026-10-18 — Desk opened
- **Purpose:** user-safety audit of the MAIN TacoTip addon (main.lua, options.lua, gearscore.lua, pawn.lua, textures.lua, Libs/) at v0.8.4; Extras explicitly out of scope except as a scope boundary.
- **Scope:** chat-frame writes, Pawn registry reads, SavedVariables sanitization, slash/options/item-link input handling, third-party file-scope surface, taint/combat paths, outbound traffic/privacy.
- **Note:** reviewing session had read-only tools (no write/exec); journal, signals and bench report placed by the orchestrator from the lane's inline handoff.

## 2026-10-18 — [signal:done] Audit complete: no blockers, no majors, 5 minors
- **Verdict:** safe to ship. All chat writes intentional + rate-limited (safeCall dedup main.lua:246-266); Pawn Fail-capable call registry-gated (pawn.lua:62-75,217-219); SV sanitized + allowlisted at sinks (options.lua:175-270,892-901); zero addon-message sends in main addon (per-file greps no-match); no secure frames hooked; no loadstring in shipped files.
- **Findings:** m1 custom_anchor SV allowlist gap (main.lua:2916-2917); m2 PawnGetSingleValueFromItem no-Fail assumption unverifiable from repo (pawn.lua:96-104); m3 raw untrusted strings in tooltip text (cosmetic-only); m4 suppressor nil-name fallback overbroad by design (LibForeverInspector.lua:4639-1648); m5 character-refresh missing combat guard, benign (main.lua:3086 vs 3239).
- **Report:** bench/audits/2026-10-18-maintip-security-audit.md (placed by orchestrator; body is the lane's verbatim handoff).
- **Handoff:** 4 in-game confirmations carry (Pawn silence ×2 clients, corrupt-SV, Era suppressor fidelity, combat movers). Harness run_all.sh not executed in the reviewing session — re-run on placement for the evidence stamp.
