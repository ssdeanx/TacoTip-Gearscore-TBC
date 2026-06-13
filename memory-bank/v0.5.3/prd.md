# PRD — v0.5.3

## Problem Statement
TacoTip v0.5.2 fixed the core NineSlice border rendering issue, but the addon still has gaps compared to established tooltip addons (TipTac, TinyTooltip) in three areas:
1. The tooltip mover UI feels clunky — the tooltip doesn't follow the green drag button in real-time during a drag
2. The options panel has 4 pages but the Positioning page carries only 6 controls, while the Root page has behavioral toggles that would be more discoverable alongside the tooltip content they affect
3. Several high-value, low-effort tooltip enhancements are missing (NPC classification, mouse offset sliders, fade control, creature type, sell price)

## Goals
- Real-time tooltip following during mover drag (jank-free, no 1-second poll delay)
- Reduce settings pages from 4 to 3 by merging Root behavioral toggles into Tooltips and merging Positioning anchors into Character & Inspect
- Add NPC classification display to unit tooltips (Elite/Rare/Boss markers)
- Add X/Y offset sliders for mouse-anchor mode
- Replace binary instant_fade with a fade delay slider
- Add opt-in 3D portrait via `PlayerModel:SetUnit()`
- Verify all new controls work in the options preview

## Non-goals
- Complete aura/buff/debuff system (TipTac's ~2000-line module) — defer to v0.6.0+
- RatingBuster stat breakdowns — standalone addon territory
- Layout presets/templates
- Item count cross-character (Bagnon territory)
- Mythic+ integration (not applicable to Classic/TBC)

## User Stories

### Story 1: "Jenna the Raider"
*Role: Raid leader, TBC Hardcore raider*
"As a raid leader, I need to quickly identify mob difficulty when scouting. I want to see Elite/Rare/Boss markers on tooltip level lines so I know what we're pulling without targeting and checking the nameplate color."
- **Acceptance:** NPC classification text (Elite, Rare, Rare Elite, Boss) displayed on tooltip level line with colored prefix
- **Config key:** `show_classification` (bool, default true)
- **References:** `UnitClassification(unit)` API; TipTac Reborn prefix pattern (`+Rare`, `++Elite`, `++Boss`)

### Story 2: "Marcus the Mover"
*Role: UI tweaker, altoholic*
"I use the custom mover to position my tooltip in a specific screen corner. But when I drag the green button, the tooltip stays frozen until I release. It feels broken. I want to see my tooltip slide across the screen as I drag, like every other draggable UI element in WoW."
- **Acceptance:** During mover drag (`OnDragStart`), an `OnUpdate` handler re-applies `SetPoint()` on GameTooltip to the drag button's current position every frame. On `OnDragStop`, position is saved and `OnUpdate` is cleared.
- **Config key:** None (behavioral change to existing `custom_pos` flow)
- **References:** `CreateMover` pattern at `main.lua:1101-1130`; `GameTooltip_SetDefaultAnchor` hook at `main.lua:1029-1067`

### Story 3: "Priya the Perfectionist"
*Role: UI customization enthusiast*
"The options panel has too many pages. I open Positioning to change my tooltip anchor, but the language dropdown and combat toggle are on a different page. I want fewer clicks to find what I need."
- **Acceptance:** Options reduced from 4 pages to 3. Root behavioral toggles (`hide_in_combat`, `instant_fade`, `UberTooltips`, `chatClassColor`, `show_achievement_points`) moved to Tooltips page. Redundant `tip_style` dropdown removed from Root. Language dropdown on Tooltips or General. Positioning anchors merged into Character & Inspect (renamed to "Positioning & Overlays").
- **Config key:** No new config — purely UI reorganization
- **References:** Current page inventory in options.lua builders

### Story 4: "Dmitri the Theorycrafter"
*Role: Class disc theory writer*
"I want to see item ID and sell price on gear tooltips without installing two extra addons. When I'm theorycrafting gear sets, knowing the item ID helps me look it up on Wowhead, and sell price helps me vendor-manage during runs."
- **Acceptance:** Item ID shown on item tooltips (optional toggle). Item sell price shown on item tooltips (optional toggle). Both use `GetItemInfo(itemLink)` from the tooltip's GetItem() call.
- **Config key:** `show_item_id` (bool, default false), `show_sell_price` (bool, default true)
- **References:** `GameTooltip:HookScript("OnTooltipSetItem", ...)` at `main.lua:943-950`

### Story 5: "Aisha the Leveler"
*Role: Casual leveler, hunter main*
"I'm leveling a hunter and I want to know what creature type I'm fighting — Humanoid, Beast, Undead — it matters for my tracking and traps. Also, some mobs are Elite and I need to know before I pull."
- **Acceptance:** Creature type displayed in unit tooltip (optional line). NPC classification marker on level line (shared with Story 1).
- **Config key:** `show_creature_type` (bool, default true)
- **References:** `UnitCreatureType(unit)` API

### Story 6: "Olaf the Accessibility User"
*Role: Player with visual processing sensitivity*
"The default tooltip fade is too fast and the default tooltip size is too small. I want to slow down the fade delay and increase the tooltip scale without installing a separate addon."
- **Acceptance:** Fade delay slider (0-2.0s, replace binary `instant_fade`). Tooltip scale slider (50-150%).
- **Config key:** `fade_delay` (number, default 0, range 0-2.0), `tooltip_scale` (number, default 1.0, range 0.5-1.5)
- **References:** `GameTooltip:SetFadeDuration(value)` API

### Story 7: "Chen the Collector"
*Role: Transmog/mount collector*
"I want to see the 3D model of players and NPCs in the tooltip, not just a flat 2D icon. Old TacoTip showed live 3D models and I miss that. Please add it back as an option."
- **Acceptance:** New "Show 3D portrait" checkbox in Tooltips → Portrait & text section. When enabled, replaces `SetPortraitTexture()` with a `PlayerModel` frame calling `SetUnit(unit)`. Frame size matches the existing portrait scale slider.
- **Config key:** `tooltip_portrait_3d` (bool, default false)
- **References:** `PlayerModel:SetUnit(unit)` on 2.5.5; `SetPortraitZoom(1)`; current portrait code at `main.lua:472-471`

### Story 8: "Sam the Streamer"
*Role: Content creator, multi-boxer*
"When I play on my wide monitor, the default mouse-anchor puts the tooltip right on my cursor, covering what I'm looking at. I need X/Y offset controls to nudge the tooltip away from my cursor."
- **Acceptance:** X offset slider and Y offset slider for mouse-anchor mode in the Positioning section. Config keys `anchor_mouse_offset_x` and `anchor_mouse_offset_y` (range -200 to 200).
- **Config key:** `anchor_mouse_offset_x` (int, default 0, range -200 to 200), `anchor_mouse_offset_y` (int, default 0, range -200 to 200)
- **References:** `CreateMouseAnchor()` at `main.lua:1013-1027`; TinyTooltip's offset implementation

## Success Criteria
1. Dragging the green mover button shows the GameTooltip following in real-time without perceivable delay (Feature A)
2. Options panel reduced from 4 pages to 3, with no loss of existing controls (Feature B)
3. NPC classification displayed on all non-player unit tooltips with class colors (Feature D.1)
4. Fade delay slider replaces instant_fade checkbox without breaking existing user configs (Feature D.3)
5. Item ID and sell price visible on item tooltips when toggled on (Feature D.5/D.6)
6. 3D portrait renders correctly on 2.5.5 without error (Feature C)
7. All new controls have proper locale strings in enUS.lua (Feature D)
8. Options preview respects border thickness slider from v0.5.2 (Feature E)

## Constraints
- Must work on Classic Era / TBC Anniversary / Wrath Classic (interfaces 11508, 20505, 30405)
- 3D portrait (Feature C) must fall back gracefully to 2D if `PlayerModel` is unavailable or returns errors
- All new features must use safeCall wrappers (v0.5.2 pattern)
- No new bundled library dependencies
- X/Y anchor offsets must work with both `anchor_mouse` and `anchor_mouse_world` modes
