# tooltip-addon-compat — Journal

## 2026-10-22 — Desk opened
- **Purpose:** Research lane — compatibility of TacoTip's `onGameTooltipSetDefaultAnchor` re-pin with other GameTooltip-using addons. Produce sourced finding only; no code edits.
- **Scope:** bench finding `bench/findings/tooltip-addon-compat.md`: (1) official GameTooltip_SetDefaultAnchor / SetOwner contract from docs, (2) real-world hook patterns in public addon repos, (3) ranked hazards in current main.lua hook + render path, (4) precise pass-through contract for the fix.
- **Next step:** Read main.lua hook (4028-4108) + render call (2009); web-research docs; gh_grep addon examples; write finding; emit done signal.
