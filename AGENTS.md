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
  - `Advanced`
- Registration supports both:
  - modern `Settings.RegisterCanvasLayoutCategory` + `RegisterCanvasLayoutSubcategory`
  - legacy `InterfaceOptions_AddCategory` with `childFrame.parent = rootFrame.name`
- The new builder path is the active UI. The legacy single-canvas `OnShow` block remains in the file only as bypassed fallback code.
- The root options category now uses the addon's display title from `TacoTip.toc`, so the Blizzard AddOns tree entry should read `TacoTip Gearscore TBC`.

## Runtime sync notes

- `main.lua` calls `TT.RefreshOptionsUI()` after tooltip mover and overlay drag/save actions so the options controls stay synchronized.
- Tooltip preview and positioning controls intentionally reuse the existing config keys instead of introducing a new settings model.
- Optional SharedMedia integration is now supported for tooltip fonts and statusbar textures when `LibSharedMedia-3.0` is present.
- Optional SharedMedia integration is now supported for tooltip fonts, statusbar textures, background textures, and border textures when `LibSharedMedia-3.0` is present.
- Tooltip appearance settings now include portrait display, font choice/size, shared health+power bar textures, selectable tooltip background/border media, and class-tinted border/background styling with adjustable alpha.
- Media selectors currently stay as single dropdown lists with expanded Blizzard default choices, wider in-list texture strip previews, hover-help on custom widgets, and a live preview note rather than nested menus.
- The Tooltips page also includes Blizzard color-picker-backed border/background swatches plus mouse-wheel support on reusable scroll frames and sliders.

## UI visualization context

- `memory-bank/visualizationContext.md` stores ASCII and Mermaid snapshots of the intended options layout so future sessions can compare code changes against the planned UI structure.

## Localization/docs

- New settings copy ships in `Locale/enUS.lua` first.
- Other locales inherit English through the existing fallback merge until translated.
- Keep `README.md`, `CHANGELOG.md`, and `memory-bank/*.md` aligned with future options changes.
