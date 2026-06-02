# Progress

## 2026-06-01 - 0.5.1 production audit follow-up

- Fixed the live class-colored tooltip border regression in `main.lua` by resolving the current tooltip unit inside `TT:ApplyTooltipAppearance()`, which keeps later appearance refreshes from repainting player borders gray.
- Removed the unused duplicate `getClassIconMarkup` helper and the inert local `Advanced` page stub from `options.lua`; targeted diagnostics on `main.lua` and `options.lua` are clean.
- Audited slash-command ownership and left the current low-risk structure in place: `gearscore.lua` still provides the bootstrap aliases, `options.lua` owns the full `/tacotip` handler, and `main.lua` keeps a defensive fallback on `ADDON_LOADED`.
- Audited the active modern options UI code paths and confirmed the current dropdown/scroll behavior still routes through Blizzard `UIDropDownMenuTemplate`, `UIPanelScrollFrameTemplate`, builder height finalization, and mouse-wheel scroll proxy hooks.
- Bumped packaged/public version metadata and release docs to `0.5.1`.

## 2026-05-28 - 0.4.9 release prep finalized

- Updated `TacoTip.toc`, `main.lua`, and `options.lua` to `0.4.9` for the release build.
- Refreshed `README.md` with the new public version, supported-client wording, language-dropdown notes, and a table of all available locales.
- Added the `0.4.9` release section to `CHANGELOG.md` and corrected the localization note so it reflects translated per-locale welcome strings instead of an English-only sentence.
- Updated the tooltip preview placeholder name in `options.lua` from `Kebabstorm` to `AcidBomb`.
- Updated `TEXT_HELP_WELCOME` in every shipped locale file so the text stays localized while using `AcidBomb (Pilsung)` as the maintainer name.
- Re-ran targeted diagnostics on the release docs, manifest, runtime files, and all locale files; every checked file is clean.

## 2026-05-28 - full locale coverage and language selector verification

- Replaced the placeholder modern settings strings with translated `OPTIONS_*` blocks in `deDE`, `esES`, `esMX`, `frFR`, `itIT`, `koKR`, `ptBR`, `ruRU`, `zhCN`, and `zhTW`.
- Confirmed every locale file now contains the language-selector strings, so the root-page language dropdown has localized labels/help text across the full shipped locale set.
- Updated the README supported-clients summary to explicitly include Titanforge.
- Re-ran targeted diagnostics on the edited locale files, `README.md`, and `options.lua`; all checked files are clean.
- Verified from `options.lua` that the saved language dropdown exists and that mouse-wheel scroll proxy hooks are present for the relevant options pages.

## 2026-05-28 - TOC interface metadata sync

- Re-checked the `Locale/` directory contents while auditing the repo state for the user's follow-up.
- Verified from Warcraft Wiki TOC documentation that the target client versions map to `11508`, `20505`, `30405`, and `38001`, and that comma-delimited interface values are valid.
- Updated all four `.toc` files in the repo (`TacoTip.toc`, `LibClassicInspector.toc`, `LibStub.toc`, `LibDetours-1.0.toc`) to use the same interface list: `11508, 20505, 30405, 38001`.

## 2026-05-28 - Titanforge locale support

- Verified the existing build-family gate already covers `3.80.1`-style Wrath-family Titanforge clients.
- Added an explicit Titanforge compatibility note to `README.md` and `CHANGELOG.md` so the first upload documentation matches the supported target audience.
- Expanded `Locale/zhCN.lua` and `Locale/zhTW.lua` with the newest options UI labels/help text for the modern settings pages.
- Re-checked the Chinese locale file tails to confirm they now close cleanly after the added strings.

## 2026-05-28 - scroll/layout and compact ilvl follow-up

- Fixed the page-builder scroll-height bug in `options.lua` so manual layout spacing contributes to content height and long settings pages no longer cut off early.
- Added mouse-wheel proxying for the reusable scroll-page builder and the Tooltips page so scrolling works from the page area instead of only the scrollbar thumb.
- Cleaned the Character & Inspect offset rows by hiding the redundant slider-template labels and increasing row spacing.
- Expanded the built-in Blizzard font choices and forced tooltip media/font dropdown callbacks through a full options refresh before redrawing the preview.
- Added a standalone compact `iLvl` line under GearScore in `main.lua` and updated the modern preview sample to match.
- Re-ran targeted diagnostics on `options.lua` and `main.lua`; both are clean.

## 2026-05-28 - hostile level colors and spec icons

- Researched WoW mob difficulty coloring on warcraft.wiki.gg and confirmed TacoTip should rely on `GetQuestDifficultyColor(level)` for hostile target level coloring.
- Patched `main.lua` so hostile non-player unit levels are recolored in-place on the tooltip's level line instead of staying white.
- Added cached specialization icon lookup in `main.lua` using `LibClassicInspector` talent data and applied the new icon + class-colored spec-name formatting to player talent lines.
- Updated the modern options preview in `options.lua` so the talents sample matches the live tooltip formatting.
- Re-ran targeted diagnostics on `main.lua` and `options.lua`; both are clean.

## 2026-05-28 - options stability follow-up

- Removed the active `Advanced` child page registration and moved its small behavior/client toggles onto the root/general page.
- Reworked the Tooltips page shell so the live preview sits in a dedicated right-side pane instead of floating over the settings column.
- Switched collapsed dropdown text back to clean selected labels while keeping Blizzard popup menu previews for the long media lists.
- Added dynamic width sizing to the Tooltips scroll content and replaced several fixed dropdown spacing blocks with measured spacing.
- Added mover sync/reset helpers in `main.lua` so anchor changes and reset-position flows keep the green mover aligned with the saved custom anchor.
- Re-ran targeted diagnostics on `options.lua`, `main.lua`, and `Locale/enUS.lua`; all are clean.

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
