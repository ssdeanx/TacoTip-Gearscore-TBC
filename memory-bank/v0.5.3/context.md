# Feature Context

## Version
- Target: v0.5.3
- Baseline: v0.5.2 (NineSlice backdrop child-frame overlay, border thickness slider, safeCall hardening)

## Feature Descriptions

### Feature A: Tooltip Mover — Real-Time Follow During Drag
Currently the green tooltip mover button uses `StartMoving()` on drag but the GameTooltip stays frozen until `OnDragStop`, when `syncTooltipMoverPosition()` + `ShowExample()` re-anchors it. The 1-second ticker weakly masks this. TipTac and other addons prove real-time following is possible via `OnUpdate` during drag that continuously re-applies `SetPoint()` on the tooltip without calling `SetOwner()`.

- **References:**
  - Current mover code: `main.lua` line 1524 (`OnDragStart`), line 1457 (`OnDragStop`)
  - `CreateMover` (char overlay) already uses `OnUpdate` during drag: `main.lua` line 1101-1130
  - `GameTooltip_SetDefaultAnchor` hook: `main.lua` line 1029-1067

### Feature B: Settings UI Consolidation (4 pages → 3 pages)
Current pages: Root (general/behaviors), Tooltips (content + appearance + preview), Positioning (6 controls), Character & Inspect (overlay toggles + offset sliders). The Positioning page is very sparse. Proposal: merge Root behavioral toggles into Tooltips, merge Positioning anchors into Character & Inspect → **3 pages: General, Tooltips, Overlays & Positioning**.

- **Current inventory:**
  - Root page: `tip_style` (redundant with Tooltips), `locale_override`, `hide_in_combat`, `UberTooltips` CVar, `chatClassColorOverride` CVar, `show_achievement_points`, mover button, reset button, status text
  - Tooltips page: ~28 controls + live preview — already has scroll frame, can absorb ~6 more root items
  - Positioning page: 6 controls (4 checkboxes, 1 dropdown, 1 button)
  - Character & Inspect page: 3 checkboxes + 4 offset rows (8 edit boxes + 8 sliders)

### Feature C: Advanced Portrait / 3D Model Support
Current `SetPortraitTexture(portrait, unit)` provides a 2D snapshot. Research confirms `PlayerModel:SetUnit(unit)` + `SetPortraitZoom(1)` is available on 2.5.5 (retail 9.x engine). Adding an opt-in toggle for live 3D model instead of 2D texture. At ~36px tooltip size the visual gain is marginal, but users who want full player model embedding can enable it. `ModelScene` is also available but requires manual camera/lighting setup.

- **References:**
  - warcraft.wiki.gg/wiki/API_PlayerModel:SetUnit
  - warcraft.wiki.gg/wiki/API_SetPortraitTexture — current 2D API
  - `ModelScene` API requires custom camera/lighting — higher effort

### Feature D: Quick-Win Tooltip Enhancements (from competitor gap analysis)
Research compared TacoTip against TipTac Reborn, TinyTooltip, Midnight, ZaremTooltip, RatingBuster, and SpellTooltips. High-priority missing features:

1. **NPC classification display** (Elite/Rare/Boss markers on level line) — `UnitClassification(unit)`
2. **X/Y offset sliders for mouse anchor** — `anchor_mouse_offset_x/y` config keys
3. **Fade delay slider** — replace binary `instant_fade` with `fade_delay` slider (0-2s)
4. **Creature type display** (Humanoid, Beast, etc) — `UnitCreatureType(unit)`
5. **Item sell price in item tooltips** — `GetItemInfo(link)` sell price
6. **Item ID on tooltips** — from item link parsing
7. **Tooltip scale slider** — `GameTooltip:SetScale(value)` range 50-150%
8. **Reaction/faction coloring for NPC borders** — `UnitReaction(unit, "player")` colors

- **References:**
  - TipTac Reborn: https://www.curseforge.com/wow/addons/tiptac-reborn
  - TinyTooltip: https://www.curseforge.com/wow/addons/tinytooltip
  - TinyTooltipClassic GitHub: https://github.com/theTyke/TinyTooltipClassic
  - Midnight: https://www.curseforge.com/wow/addons/midnight-tooltip
  - Vendor Price: https://www.wowinterface.com/downloads/info24922
  - SpellTooltips (TBC): https://github.com/lfspeers/SpellTooltips

### Feature E: Border Thickness Integration into Options Preview
The border thickness slider (`tooltip_border_edge_size`) was added in v0.5.2 to `applyTooltipBackdrop` in `main.lua` and the Tooltips page in `options.lua`. The options preview (`modernShowExampleTooltip`) should be verified to properly reflect thickness changes. Currently the preview calls `TT:ApplyTooltipAppearance(tooltip, "player")` which routes through `applyTooltipBackdrop` — so thickness SHOULD work in preview. Verify on target client.

## Feature Goals
1. Smooth real-time tooltip follow during drag (Feature A)
2. Cleaner options navigation with fewer pages (Feature B)
3. Opt-in 3D portrait via PlayerModel (Feature C)
4. Close feature gap with TipTac/TinyTooltip on the most requested items (Feature D)
5. Verified that v0.5.2 border thickness works in preview (Feature E)

## Feature Dependencies
- Feature A depends on the existing `GameTooltip_SetDefaultAnchor` hook and `TacoTipDragButton` infrastructure — no new dependencies
- Feature B depends on `options.lua` page builder — no new dependencies, just reorganization
- Feature C depends on `PlayerModel:SetUnit()` being available on 2.5.5 — confirmed yes
- Feature D depends on standard Blizzard APIs (`UnitClassification`, `UnitCreatureType`, `UnitReaction`, `GetItemInfo`) — all available on Classic

## Open Questions
- Can `GameTooltip:SetPoint()` during drag cause flicker or event issues? (Feature A)
- Should Feature C be behind a "Show 3D portrait" toggle or replace 2D entirely?
- For Feature D, which quick-wins should ship in v0.5.3 vs defer to v0.6.0?
- Does border thickness slider need a reset-to-default button in the options UI?
