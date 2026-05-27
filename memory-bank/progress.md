# Progress

## 2026-05-27 - widget polish and color-wheel pass

- Widened the single media dropdown previews so statusbar/background/border choices read more like real texture strips instead of icon-sized samples.
- Added reusable color-swatch controls in `options.lua` for tooltip border and background colors, backed by the Blizzard color picker.
- Kept alpha as dedicated sliders and wired the new RGB config values into `main.lua` so live tooltips and the preview both honor them.
- Added mouse-wheel behavior to scroll pages and sliders for better in-game usability.
- Updated `Locale/enUS.lua` with new subsection labels, color-control strings, and clearer preview/dropdown copy.
- Re-ran targeted diagnostics on `options.lua`, `main.lua`, and `Locale/enUS.lua`; all are clean.
- Updated the options root category to use the full addon title (`TacoTip Gearscore TBC`) from metadata.
- Added a persistent visualization context file with ASCII and Mermaid layout maps for future polish passes.

## 2026-05-27 - professional options UI implementation

- Refactored `options.lua` into a parent-category settings shell with child pages for `Tooltips`, `Positioning`, `Character & Inspect`, and `Advanced`.
- Preserved the dual registration/opening strategy: modern `Settings.RegisterCanvasLayoutCategory` / `RegisterCanvasLayoutSubcategory` when available, legacy `InterfaceOptions_AddCategory` + parented child panels otherwise.
- Added the new tooltip preview surface, custom-anchor dropdown, clearer tooltip mover actions, and overlay offset editors/sliders for character and inspect frames.
- Added `TT.RefreshOptionsUI()` wiring in `main.lua` so tooltip mover and overlay drag changes refresh the new options controls.
- Expanded the Tooltips page with guild-rank style selection, class-tinted border/background controls with alpha, portrait toggle/scale, tooltip font dropdown, tooltip text-size slider, and shared health/power bar texture selection with optional SharedMedia-backed discovery.
- Extended SharedMedia-backed discovery to tooltip background and border textures as well, with runtime application and Blizzard fallback behavior.
- Kept the media selectors as single dropdown lists while widening the controls, adding hover-help to custom widgets, adding clearer live-preview guidance, and expanding the built-in Blizzard media lists.
- Removed the unwanted external-data option/strings so no extra unsupported feature remains in the addon.
- Added enUS-first labels/help text for the redesigned UI and updated README/changelog to match the new settings structure.
- Re-ran targeted diagnostics on `options.lua`, `main.lua`, and `Locale/enUS.lua`; all are clean.

## 2026-05-27

- Audited `Locale/` against `Locale/enUS.lua` and completed the missing entries in the populated locale files.
- Patched `Locale/deDE.lua`, `Locale/esES.lua`, `Locale/koKR.lua`, `Locale/ruRU.lua`, and `Locale/zhCN.lua` to add the missing `HunterScore` strings; also translated the blank `Always FULL` entries in German and Spanish.
- Confirmed that `Locale/esMX.lua`, `Locale/frFR.lua`, `Locale/itIT.lua`, `Locale/ptBR.lua`, and `Locale/zhTW.lua` are empty locale stubs rather than partially translated files.
- Populated the five empty locale stubs with complete first-pass translation tables and verified the file tails close cleanly with the locale table terminator.
- Replaced the English `HunterScore` label/description with localized equivalents in all locale packs.
- Polished the high-visibility helper text and style labels across the locale files for more natural phrasing in each language.

- Inspected the addon manifest, README, main modules, and bundled libraries.
- Confirmed the core wiring: LibStub → CallbackHandler-1.0 / LibDetours-1.0 / LibClassicInspector, then TacoTip modules.
- Captured the Classic-era client gate, optional Pawn integration, tooltip hook flow, and options/UI bootstrap behavior.
- Drafted and saved a detailed implementation plan in `/memories/session/plan.md`.
- Implemented the TBC Anniversary startup hardening pass in `LibClassicInspector.lua` and `LibDetours-1.0.lua`.
- Fixed the final slash-command ownership so `options.lua` now overrides the bootstrap `/tacotip` handler with the full command set.
- Removed the broad bundled-lib luacheck exclusions and cleaned the main library warnings in `LibStub.lua`, `CallbackHandler-1.0.lua`, and `LibDetours-1.0.lua`.
- Updated version/docs tracking to `0.4.8` across `TacoTip.toc`, README, changelog, and the `LibClassicInspector` API header.
- Re-ran targeted diagnostics on the edited library/runtime/docs files; all checked files are now clean.
- Hardened `options.lua` reset handling by guarding every `RefreshPosition()` call with method existence checks.
- Bound `main.lua`'s `tinsert` usage to `table.insert` so the tooltip path no longer depends on a possibly-missing global alias.
- Researched TBC/Classic-friendly options UI patterns on the web and confirmed TacoTip can use Blizzard widget templates like `InterfaceOptionsCheckButtonTemplate`, `UIDropDownMenuTemplate`, `UIPanelButtonTemplate`, `InputBoxTemplate`, and `UIPanelScrollFrameTemplate` for a richer config screen.
- Confirmed the correct add-on menu registration strategy is to keep the existing dual-path approach: use `Settings.RegisterCanvasLayoutCategory` when available, otherwise register with `InterfaceOptions_AddCategory`.
- Confirmed legacy `InterfaceOptionsFrame_OpenToCategory` behavior can still need `InterfaceOptionsFrame_Show()` and occasional scroll-to-category workarounds on Classic-family clients.

### Status

- Memory bank implementation: updated with the Anniversary runtime and lint cleanup work
- Next step: upgrade `options.lua` into a fuller tabbed/sectioned configuration UI and tighten the options-menu open behavior for Classic/TBC clients
