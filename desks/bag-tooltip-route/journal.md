# Bag Tooltip Route — Journal

## 2026-10-22 — Desk opened
- **Purpose:** Answer, with sources (web docs + local mirror file:line), how bag item
  hovers route the GameTooltip in classic-era clients, and why an unconditional
  post-hook re-pin of `GameTooltip_SetDefaultAnchor` (custom_pos set → ClearAllPoints +
  SetPoint to the addon drag handle) makes the bag tooltip VANISH on
  classic_anniversary while paperdoll (character-pane) item hovers still work.
- **Scope:** Research only. Read-only on the repo except this desk dir and ONE bench
  file `bench/findings/bag-tooltip-route.md`. No edits to main.lua or tests (another
  lane owns them).
- **Sources priority:** (1) wowpedia.wiki.gg / warcraft.wiki.gg + wago.tools via
  websearch/webfetch; (2) local mirror `/home/sam/wow-ui-source` —
  `origin/classic_anniversary` first, `origin/classic_era` second, exact file:line;
  (3) this repo's main.lua hook ~4028-4108 and isManagedAnchorTarget gate ~3931-4026
  for the vanish mechanism only.
- **Next step:** Run the four source passes, write
  `bench/findings/bag-tooltip-route.md`, append journal entry, emit `done` signal
  (or `hands-up` if sources contradict).
