# AGENTS

## Repo overview

- WoW Classic-family addon only (`11508`, `20505`, `30405`); retail is unsupported.
- Core runtime files load in this order: `gearscore.lua`, `pawn.lua`, `options.lua`, `main.lua` after bundled libs.
- Shared globals: `TT`, `TT_GS`, `TT_PAWN`, `TacoTipConfig`, `TACOTIP_LOCALE`.

## Current options UI architecture

- `options.lua` now registers a parent `TacoTip` category with child pages:
  - `Tooltips`
  - `Positioning`
  - `Character & Inspect`
- The sparse `Advanced` child page is no longer registered in the active UI; its small set of behavior/client toggles now lives on the root/general page instead.
- Registration supports both:
  - modern `Settings.RegisterCanvasLayoutCategory` + `RegisterCanvasLayoutSubcategory`
  - legacy `InterfaceOptions_AddCategory` with `childFrame.parent = rootFrame.name`
- The new builder path is the active UI. The legacy single-canvas `OnShow` block remains in the file only as bypassed fallback code.
- The root options category now uses the addon's display title from `TacoTip.toc`, so the Blizzard AddOns tree entry should read `TacoTip Gearscore TBC`.
- The Tooltips page now uses a real right-side preview column, narrower left-side scroll content, and plain selected dropdown titles while keeping Blizzard popup menus for long media lists.
- Scrollable child pages now proxy mouse-wheel input through their parent/content frames, and the page builder now counts manual spacing when computing scroll height so long pages actually scroll instead of cutting off.

## Runtime sync notes

- `main.lua` calls `TT.RefreshOptionsUI()` after tooltip mover and overlay drag/save actions so the options controls stay synchronized.
- `main.lua` now also exposes `TT:SyncTooltipMover()` so the options panel can re-anchor the green mover handle after custom-anchor changes and position resets.
- The tooltip mover reset flow now keeps the selected custom anchor and resets the saved position back to that anchor's screen corner instead of silently clearing the anchor.
- Hostile NPC level numbers now use Blizzard difficulty coloring via `GetQuestDifficultyColor(level)` so gray/green/yellow/orange/red difficulty is visible directly in TacoTip tooltips again.
- Specialization lines now render with class-colored spec names plus per-spec icons derived from `LibClassicInspector` talent data instead of plain white text.
- Tooltip preview and positioning controls intentionally reuse the existing config keys instead of introducing a new settings model.
- Optional SharedMedia integration is now supported for tooltip fonts and statusbar textures when `LibSharedMedia-3.0` is present.
- Optional SharedMedia integration is now supported for tooltip fonts, statusbar textures, background textures, and border textures when `LibSharedMedia-3.0` is present.
- Tooltip appearance settings now include portrait display, font choice/size, shared health+power bar textures, selectable tooltip background/border media, and class-tinted border/background styling with adjustable alpha.
- Media selectors currently stay as single dropdown lists with expanded Blizzard default choices, wider in-list texture strip previews, hover-help on custom widgets, and a live preview note rather than nested menus.
- The Tooltips page also includes Blizzard color-picker-backed border/background swatches plus mouse-wheel support on reusable scroll frames and sliders.
- Compact player tooltips now add a separate `iLvl` line under GearScore so average item level is visible even outside the wide layout.

## UI visualization context

- `memory-bank/visualizationContext.md` stores ASCII and Mermaid snapshots of the intended options layout so future sessions can compare code changes against the planned UI structure.

## Localization/docs

- New settings copy ships in `Locale/enUS.lua` first.
- Other locales inherit English through the existing fallback merge until translated.
- Keep `README.md`, `CHANGELOG.md`, and `memory-bank/*.md` aligned with future options changes.
