# Prior Tooltip Save — Journal

## 2026-10-22 — Desk opened
- **Purpose:** Read-only reverse-engineering of how the PRIOR WORKING version
  (`/home/sam/TacoTip/`, v0.8.3) implemented GameTooltip position
  save/restore, so the operator can compare against the broken v0.8.4
  in this repo.
- **Scope:** `/home/sam/TacoTip/` (read-only, never edit) — main.lua,
  options.lua, TacoTip.toc. Output goes to
  `bench/findings/prior-tooltip-save-mechanism.md` in this repo only.
- **Context:** Operator plays TBC Anniversary (classic_anniversary, Interface
  20506). Prior tree's single `TacoTip.toc` declares
  `Interface: 11509, 20506, 38002, 16001, 120105` — multi-client, covers
  TBC Anniversary. Version 0.8.3 (the last known good). SavedVariables:
  `TacoTipConfig`.
- **Next step:** Map the save/restore contract end to end (default-anchor
  post-hook, drag button OnDragStop, gates), quote with file:line, write
  findings, emit `done` signal.

## 2026-10-22 — [signal:done] Prior save/restore mechanism fully documented
- **Worked on:** Read all of `/home/sam/TacoTip/` (v0.8.3, single TOC
  `Interface: 11509, 20506, 38002, 16001, 120105` — covers the operator's
  TBC Anniversary 20506). Mapped save + restore end to end with file:line
  quotes; cross-checked the client trigger on `origin/classic_anniversary`
  (`UnitFrame.lua:452` calls `GameTooltip_SetDefaultAnchor` immediately
  before `SetUnit` on every hover; `GameTooltip.lua:109` is the bottom-right
  reset the post-hook overwrites).
- **Current state:** Findings on the bench at
  `bench/findings/prior-tooltip-save-mechanism.md`, incl. a factual
  0.8.3-vs-0.8.4 appendix (0.8.4 added `isManagedAnchorTarget` skip gates +
  `runUntainted`/`pcall` wrapper + a second apply site
  `applyCustomTooltipAnchor` at main.lua:2009; the save shape and handle
  anchor are unchanged).
- **Key contract:** 0.8.3 applies `custom_pos` on EVERY
  `GameTooltip_SetDefaultAnchor` call (gates: `anchor_mouse_spells` spell
  early-return, `anchor_mouse` precedence, `custom_pos ~= nil` presence —
  NO unit/content gate). Save = `GetLeft()/GetBottom()` →
  `{BOTTOMLEFT, BOTTOMLEFT, x, y}`; restore = tooltip `SetPoint`-ed to the
  persistent `TacoTipDragButton` handle.
- **Next step:** None from this desk — done signal emitted; operator/other
  desks compare against the current repo's gated hook
  (`main.lua:4064-4073`) before any revert decision.

## 2026-10-22 — [signal:done] Amendment: full cache-spined trace replaces the first write-up
- **Worked on:** Operator amendment — rewrote
  `bench/findings/prior-tooltip-save-mechanism.md` (727 lines) as a TRACE:
  §0 files+load order, §1 cache (`tooltip._tacoTipState`, main.lua:165-198;
  sole unit write 1630; readers R1-R7; clears 1327-1340 + `currentUnitGUID`
  NEVER cleared, main.lua:3370-3371), §2 first-hover 9 hops, §3 exhaustive
  writer table for `custom_pos`/`custom_anchor` (main/options/gearscore),
  §4 re-hover + 0.2s `UpdateTooltip` loop (`TOOLTIP_UPDATE_TIME = 0.2`) +
  GSCallback/INVENTORY_READY content-only re-drives, §5 reset/decay, §6
  contract, §7 0.8.4 delta.
- **Current state:** Trace answers the operator's hypothesis directly: in
  0.8.3 the saved-position re-apply NEVER passes through the cached unit —
  position and `_tacoTipState` are disjoint states; only mover-mode
  `ShowExample` (main.lua:1633-1644) re-anchors on a unit decision. The
  cached-unit coupling first exists in 0.8.4
  (`isManagedAnchorTarget` gate + `applyCustomTooltipAnchor` at main.lua:2009).
- **Verification:** prior tree still 0 files modified since session start;
  only writes were this desk + the bench file.
- **Next step:** None — done signal re-emitted (2026-10-22T19:11:39Z).
