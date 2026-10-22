# stage6-api-scan — Journal

## 2026-10-18 — Desk opened
- **Purpose:** Read-only Blizzard API opportunity scan for the MAIN TacoTip addon (v0.8.4, 112k users). Find unused Blizzard APIs that could improve/enhance/optimize it, adoption-safe with fallback stories.
- **Scope:** main.lua, options.lua, gearscore.lua, pawn.lua, textures.lua, Libs/LibForeverInspector/ in /home/sam/TacoTip-Gearscore-TBC. Mirror: /home/sam/wow-ui-source (origin/live, origin/forever, origin/classic_era, origin/classic_anniversary, origin/classic_titan). No production edits.
- **Next step:** Map current API surface per file, hunt candidates per category, verify branch-qualified file:line evidence, write bench/audits/2026-10-18-maintip-api-opportunities.md.

## 2026-10-18 — [signal:checkpoint] scan complete, report filed
- **Worked on:** Mapped full C_/Unit/Item/Tooltip/Settings surface per file (main + lib + gearscore/pawn/options/textures); verified 10 ranked candidates + 9 rejections against all five mirror branches with file:line evidence; filed bench/audits/2026-10-18-maintip-api-opportunities.md.
- **Current state:** Report on bench. Top: O1 IsItemDataCachedByID + O2 GetDetailedItemLevelInfo (both VERIFIED all-five, safe). Rejected-as-unverifiable: R2 GetItemLinkByGUID-on-classic (conflicting mirror evidence; needs 1 in-game /dump on era), R9 OPEN-ITEMS cross-check (bench/OPEN-ITEMS.md does not exist repo-wide; no nameplate code in scope to attach it to).
- **Next step:** Owner review of ranked list; in-game settles (R2 era /dump, O7 Settings host check on classic clients) before any adoption proposal becomes a build task.

