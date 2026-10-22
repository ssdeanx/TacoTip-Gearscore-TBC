# publish-hunter — Journal

## 2026-10-19 — Desk opened
- **Purpose:** hunter deep audit for publish readiness (MAIN + Extras, Classic Era): code smells, full trace of the four live-reported paths, hidden failures, hardening list.
- **Scope:** all shipped Lua both addons + both harnesses; baseline from fix-main-batch1–5, stage6-reaudit, prior maintip audits (bench-read).
- **Note:** reviewing session had no write/exec tools; journal, signal and bench report placed by the orchestrator from the inline handoff.

## 2026-10-19 — [signal:done] Audit complete: NEEDS FIXES (0 CRITICAL, 4 HIGH, 6 MEDIUM, 5 LOW, 3 smells)
- **H-NEW1 CONFIRMED:** mover ticker + OnShow/OnHide → ShowExample mutates GameTooltip behind menu; quit-fix guarded only drag OnUpdate + right-click confirm. Same taint class, narrower reachability; CHANGELOG:66 tick-guard claim is wrong. Fix: isSecureMenuBusy() + early-returns + pins.
- **H-NEW2 CONFIRMED (H7 residual):** options LoadAddOn ×6 + registration booleans uncounted; panel can be silently absent. Fix: counters + problems[] entry.
- **H-NEW3 JUSTIFY-or-FIX:** public GetItemScore nil-scaleName guesses MrRobot:/Classic: → VgerCore.Fail chat spam for external callers. Fix: return 0 on nil + pin, or contract statement.
- **H-NEW4 JUSTIFY-or-FIX:** spell-branch raw parent:GetParent() can abort the secure anchor hook. Fix: guarded idiom + pin.
- **Frozen invariants all HOLD** (range gate, formula, TOCs, interfaces, wire, SV, enUS fallback, Retail hold).
- **Disposition:** prior FIXEDs hold; H2/M7/M8 carried; observations benign.
- **Report:** bench/audits/2026-10-19-publish-readiness-hunter.md (verbatim handoff).
