# Active Context

## 2026-06-01 - 0.5.1 production audit follow-up

- `main.lua` now resolves the live tooltip unit inside `TT:ApplyTooltipAppearance()` before applying class-tinted backdrop colors, which fixes the reported player-border regression where later refreshes could revert the border back to gray.
- `options.lua` no longer carries the unused duplicate `getClassIconMarkup` helper or the inert local `Advanced` page frame stub; the active options UI remains the root page plus `Tooltips`, `Positioning`, and `Character & Inspect`.
- The current slash-command structure was re-audited and intentionally left intact for safety: bootstrap aliases in `gearscore.lua`, the full user-facing handler in `options.lua`, and a defensive fallback registration in `main.lua`.
- The active widget path still uses Blizzard `UIDropDownMenuTemplate` dropdowns, `UIPanelScrollFrameTemplate` scroll frames, measured page-height finalization, and mouse-wheel proxy hooks; no extra dropdown/scrollbar rewrites were justified from code inspection alone.
- Packaged/release metadata and docs are now aligned on `0.5.1`.

## 2026-05-28 - 0.4.9 release prep finalized

- Bumped the packaged/public addon version to `0.4.9` in `TacoTip.toc` plus the Lua fallback metadata in `main.lua` and `options.lua`.
- Updated `README.md` with the `0.4.9` public version, a release-ready summary, an explicit available-languages table, and clearer language-dropdown / fallback behavior notes.
- Added a `0.4.9` changelog entry covering release polish, locale sync, maintainer-name cleanup, and the supported-version documentation refresh.
- Updated the tooltip preview placeholder name from `Kebabstorm` to `AcidBomb` for consistency with the current packaged addon metadata.
- Corrected `TEXT_HELP_WELCOME` in every shipped locale so each locale keeps its own language while using the new maintainer name `AcidBomb (Pilsung)`.
- Re-verified that `options.lua` still uses a single Blizzard dropdown for the root language selector and keeps mouse-wheel-enabled scroll hooks on the long options pages.

## 2026-05-28 - full locale coverage and language selector verification

- Synced every shipped locale file in `Locale/` with the current modern options UI key set from `Locale/enUS.lua`, using translated `OPTIONS_*` strings instead of placeholder English copies.
- Confirmed all non-English locale gates still respect `TacoTipConfig.locale_override` first and then fall back to `GetLocale()`, so the saved addon-language dropdown can override the client locale on the next reload.
- Verified `options.lua` already contains the root-page language dropdown (`buildLocaleDropdownChoices`, `controls.rootLanguage`) and mouse-wheel scroll hooks for the reusable scroll pages and the Tooltips page.
- Updated `README.md` so the main supported-clients summary explicitly mentions Titanforge alongside the other supported Classic-family clients.

## 2026-05-28 - TOC interface metadata sync

- Audited the addon manifests after re-checking the `Locale/` folder contents and confirmed there are four `.toc` files in the repo that need matching interface metadata.
- Verified via Warcraft Wiki TOC docs that multi-value `## Interface:` entries support the requested Classic-family targets, including Titan Reforged `38001` alongside `11508`, `20505`, and `30405`.
- Updated `TacoTip.toc`, `LibClassicInspector.toc`, `LibStub.toc`, and `LibDetours-1.0.toc` so every manifest now advertises `11508, 20505, 30405, 38001` consistently.

## 2026-05-28 - Titanforge locale support

- Confirmed the addon runtime already accepts Wrath-family build major `3`, so Chinese Titanforge `3.80.1` clients are covered without changing the supported Classic-family runtime gate.
- Documented the Titanforge compatibility note in `README.md` and the changelog so the first public upload reflects the intended Chinese-server support.
- Added the newest options UI strings to `Locale/zhCN.lua` and `Locale/zhTW.lua` so the Chinese settings pages show localized labels/help text instead of falling back to English for the updated controls.

## 2026-05-28 - scroll/layout and compact ilvl follow-up

- Fixed the active options-page scroll math by making the page builder count manual `builder.y` spacing in the final content height, which restores real scrollbar ranges on long pages.
- `createScrollPage()` and the modern Tooltips page now proxy mouse-wheel input from the page frame/content to the scroll frame so users do not need to grab the scrollbar thumb to move long settings pages.
- Hid the duplicate slider-template titles in the Character & Inspect offset rows and increased row spacing so the X/Y offset controls stop overlapping their own labels.
- Expanded the built-in Blizzard font list for the tooltip-font dropdown and forced the media/font dropdown callbacks through a full modern refresh so resolved selections update immediately.
- Compact player tooltips now add a standalone `iLvl` line below GearScore, and the modern preview mirrors that compact layout.

## 2026-05-28 - hostile level colors and spec icons

- Web research confirmed the correct Classic/TBC/Wrath-safe way to color hostile mob levels is to use Blizzard's own `GetQuestDifficultyColor(level)` behavior, which follows the familiar gray/green/yellow/orange/red difficulty system relative to the player's level.
- `main.lua` now recolors the hostile NPC level token in the existing unit tooltip line so enemy mobs no longer stay white when they should indicate XP/difficulty.
- `main.lua` now formats specialization lines with class-colored spec names and per-spec icons derived from `LibClassicInspector:GetTalentInfoByClass()` data, with the same richer formatting exposed to the modern options preview.

## 2026-05-28 - options stability follow-up

- Trimmed the active AddOns tree back to `Tooltips`, `Positioning`, and `Character & Inspect`; the lightweight Advanced/client toggles now live on the root/general page instead of a separate child page.
- Tightened the Tooltips page layout by shrinking the left scroll area, moving the preview into a dedicated right-side column, and switching collapsed dropdown labels back to plain selected titles instead of texture-strip text.
- Added dynamic width handling to the Tooltips scroll content and replaced the worst fixed dropdown spacing with measured spacing so wrapped descriptions stop colliding with later controls.
- The mover runtime now exposes `TT:SyncTooltipMover()`, uses the selected anchor when re-pointing the tooltip, and keeps the chosen anchor when resetting the saved custom position.
- Right-click reset on the green mover now snaps back to the selected anchor corner instead of disabling custom positioning, and `/tacotip default` now clears only the saved position while preserving the chosen custom anchor.

## 2026-05-27 - widget polish and color-wheel pass

- Upgraded the professional options UI with stronger single-list media previews, including a wider statusbar/background/border strip shown directly in the dropdown entries and selected value text.
- Added mouse-wheel support to the reusable scroll frames and sliders so long pages and numeric tuning controls are easier to use in-game.
- Added dedicated tooltip border/background color controls that open the Blizzard color picker while keeping the existing alpha sliders as the intensity controls.
- `main.lua` now applies configurable base tooltip border/background RGB values, with class-color toggles still overriding player-unit tooltips when enabled.
- The Tooltips page now has clearer subsection structure (`Backdrop colors & textures`, `Portrait & text`, `Tooltip bars`) and more consistent hover-help coverage on labels/value widgets.
- The options root category now uses the addon title from `TacoTip.toc`, so the Blizzard AddOns tree should show `TacoTip Gearscore TBC` instead of the shorter internal folder name.
- Added `memory-bank/visualizationContext.md` with ASCII and Mermaid UI maps so future sessions can reason about intended page layout without guessing from code alone.

## 2026-05-27 - professional options UI shipped

- `options.lua` now registers TacoTip as a parent category with child pages for `Tooltips`, `Positioning`, `Character & Inspect`, and `Advanced` on both the modern `Settings` API path and the legacy `InterfaceOptions_AddCategory` path.
- The options runtime now boots a new multi-page builder layer instead of the old single-canvas `OnShow` block, while leaving the legacy code in place but bypassed.
- The new UI keeps the existing config keys and mover flows, adds a live tooltip preview, a custom-anchor dropdown, numeric/slider offset controls for character and inspect overlays, and a larger tooltip-style surface for portrait/font/theme/bar customization.
- `main.lua` now notifies the options UI after mover/drag/save interactions so the new controls stay synchronized with runtime placement changes.
- Tooltip appearance is now runtime-configurable: class-tinted border/background with adjustable alpha, optional portrait display and scale, font choice, tooltip text size, and shared statusbar textures.
- The current media UX stays on single dropdown lists; the options widgets now use wider dropdowns, hover-help on custom controls, a clearer live-preview note, and expanded Blizzard default font/background/border/statusbar coverage.
- The mistaken optional tooltip experiment was removed completely; there is currently no extra external-data feature left in the addon.
- Tooltip appearance media discovery now also includes SharedMedia-backed background and border textures with Blizzard tooltip assets as the fallback when no external pack is installed.
- New user-facing settings copy was added in `Locale/enUS.lua`; other locales will inherit English through the existing fallback merge until translated.

Current focus:

- Completed the populated locale pass in `Locale/deDE.lua`, `Locale/esES.lua`, `Locale/koKR.lua`, `Locale/ruRU.lua`, and `Locale/zhCN.lua` by filling the missing HunterScore entries and the blank `Always FULL` descriptions where applicable.
- Completed first-pass full translation tables for the previously empty `Locale/esMX.lua`, `Locale/frFR.lua`, `Locale/itIT.lua`, `Locale/ptBR.lua`, and `Locale/zhTW.lua` files.
- The new locale tables are complete and syntactically closed, but they should still be reviewed by a native speaker if you want polish beyond the first pass.
- Localized the `HunterScore` label and description in every locale so the tooltip option no longer falls back to English.
- Performed a final wording pass on the locale packs to smooth helper text, style labels, and other high-visibility strings so the translations read more naturally.

- Keep TacoTip loading cleanly on Burning Crusade Classic Anniversary `2.5.5` / `Interface 20505`.
- Preserve the verified Classic-era scope and the actual load order from `TacoTip.toc` while reducing bundled-lib warning noise.

What has been confirmed:

- The addon supports Classic Era / TBC Classic Anniversary / Wrath Classic only (`Interface` 11508 / 20505 / 30405).
- `TacoTip.toc` loads bundled libs first, then `gearscore.lua`, `pawn.lua`, `options.lua`, and `main.lua`.
- Core runtime modules share globals: `TT`, `TT_GS`, `TT_PAWN`, `TacoTipConfig`, and `TACOTIP_LOCALE`.
- Pawn support is optional and gated by `PawnClassicLastUpdatedVersion >= 2.0538`.
- The public patch reference for Burning Crusade Classic Anniversary `2.5.5` confirms `Interface .toc = 20505`.
- `options.lua` now intentionally overrides the bootstrap slash handler so the final `/tacotip` command set is owned by the options module.
- `LibClassicInspector.lua` now guards its load-time tickers and detours so missing client globals do not abort addon startup.
- `LibDetours-1.0.lua`, `LibStub.lua`, and `CallbackHandler-1.0.lua` were cleaned up so luacheck can inspect the bundled libs without broad folder exclusion.
- Targeted post-change diagnostics on the edited files are clean; the remaining verification step is an in-game TBC Anniversary smoke test.
- `options.lua` now guards every `RefreshPosition()` call in `resetCfg()`.
- `main.lua` now binds `tinsert` to `table.insert` so the tooltip target-display path is safer on clients with missing globals.
- Web research confirms the addon options panel can still be built as a normal `Frame` with named widget templates like `InterfaceOptionsCheckButtonTemplate`, `UIDropDownMenuTemplate`, `UIPanelButtonTemplate`, `InputBoxTemplate`, and `UIPanelScrollFrameTemplate`.
- Web research also confirms the safest cross-client options-menu strategy is dual-path registration: prefer `Settings.RegisterCanvasLayoutCategory` / `Settings.RegisterAddOnCategory` when present, otherwise fall back to `InterfaceOptions_AddCategory(panel)` and legacy open helpers.
- Legacy Interface Options opening in Classic-family clients can require `InterfaceOptionsFrame_Show()` plus `InterfaceOptionsFrame_OpenToCategory(panel)` and sometimes scroll assistance when the category is low in the addon list.

Current guidance for future sessions:

- Treat `README.md`, `TacoTip.toc`, `main.lua`, `options.lua`, `gearscore.lua`, `pawn.lua`, and `Libs/*` as source of truth.
- Keep updates small and consistent across the memory-bank files.
- If code and memory ever disagree, update the memory bank to match the code.
