# Changelog

All notable changes to TacoTip Gearscore TBC will be documented in this file.

| Version | Date | Summary |
| --- | --- | --- |
| `0.5.2` | `2026-06-02` | NineSlice class-border overlay fix (separate BackdropTemplate child frame), getClassColor/GetUnit hardening, spec dedup guard, safeCall error capture, dropdown audit |
| `0.5.1` | `2026-06-01` | Live class-border tint fix, dead-code cleanup, and production audit pass |
| `0.5.0` | `2026-05-31` | Tooltip border fix, dual-spec display, positioned class icon, PVP icon fix, default toggles |
| `0.4.9` | `2026-05-28` | Release polish: final locale sync, maintainer text update, language list/docs refresh, and release metadata bump |
| `0.4.8` | `2026-05-28` | First public upload: compatibility restoration, modern options UI, tooltip polish, and localization pass |
| `0.0.1` | `2026-05-18` | Internal revival baseline before packaging |

## [0.5.2] - 2026-06-02

### Fixed - 0.5.2

- **TBC Anniversary 2.5.5 class-colored tooltip border fix (root cause):** The 2.5.3 Consolidated UI Changes moved tooltip backdrops from GameTooltip to a NineSlicePanel sub-frame. NineSlice renders its own built-in grey border that covers any backdrop applied to the tooltip parent, so `SetBackdropBorderColor` had no visible effect. The fix replaces speculative `NineSlice:SetBorderColor()` / `NineSlice:SetCenterColor()` / `BackdropTemplateMixin`-on-NineSlice calls with a **separate `BackdropTemplate` child-frame overlay** (`getOrCreateBackdropFrame`). On 2.5.3+ the NineSlice stays visible for the default background; the overlay frame sits at `FrameLevel(2)` (above NineSlice, below text) and draws only the colored border edge via `SetBackdrop({edgeFile = ...})` + `SetBackdropBorderColor`. On pre-2.5.3 clients the original full-backdrop path is preserved unchanged.
- **`getClassColor` safe-pattern rewrite:** guards both `CUSTOM_CLASS_COLORS` and `RAID_CLASS_COLORS` against nil before indexing. The old one-liner `(CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[class]` could throw if `RAID_CLASS_COLORS` was nil and the `or` fell through.
- **`resolveTooltipUnit` pcall guard:** wraps `tooltip:GetUnit()` in `pcall` so a single `GetUnit` error cannot crash the entire tooltip render path.
- **NineSlice re-show guard:** `getOrCreateBackdropFrame` re-hides NineSlice on every cached lookup in case Blizzard or another addon re-shows it between tooltip reuse cycles.
- **Defensive class-border follow-up:** a `C_Timer.After(0.05, ...)` re-applies the class-tinted border in case Blizzard refreshes the tooltip frame after `OnTooltipSetUnit` completes, and an `OnShow` hook re-applies it on re-show (deferred to next frame so Blizzard's own setup runs first).
- Player tooltips could print the same specialization twice when both dual-spec slots resolved to the same tree (TBC Anniversary inspect data races, or a player who accidentally picked the same tree in both slots). Both `active == 1` and `active == 2` branches now only render the inactive line when `spec1 ~= spec2`.
- The class icon badge was anchored at `(-4, -2)` from the tooltip's `TOPRIGHT`, hugging the corner with no breathing room. Moved to `(-10, -8)` and bumped the default size from 16 to 20 so the icon sits visibly inside the tooltip.
- Changed the default tooltip border backup color from gray (`0.5/0.5/0.5`) to white (`1/1/1`) at 85% alpha (`0.85`), so non-player or uncached tooltips show a clean light border instead of a dull gray one. Class-colored borders remain the primary mechanism when `tooltip_border_use_class` is enabled and the unit is a player.

### Added - 0.5.2

- Added `getOrCreateBackdropFrame` — creates a `BackdropTemplate` child frame overlay for 2.5.3+ NineSlice tooltips, returning the cached frame on subsequent calls. The NineSlice stays visible for the default background; the overlay only draws the colored border edge.
- Added `safeCall` helper in `main.lua` that wraps hook bodies in `xpcall(..., geterrorhandler(), ...)`. Any error in TacoTip's hooks now flows through Blizzard's error handler, so it is captured by **BugSack**, **!Swatter**, and **BugGrabber** instead of being silently swallowed or crashing the GameTooltip.
- Added `clampFrameLevel` (clamps to `[0, 100]`) and `clampAlpha` (clamps to `[0, 1]`) helpers in `options.lua` so the dropdown popup and any future widget builder cannot push frame levels or alpha values outside their documented WoW ranges.
- Added a top-level "Use class-colored border" checkbox on the Tooltips options page (right under the "Show class icon" row) so the toggle is discoverable without scrolling to the "Backdrop colors & textures" section. The old duplicate checkbox in that section was removed; both previously referred to the same `tooltip_border_use_class` config key, so existing user settings are preserved.
- Added `applyTooltipBackdrop` split: the `isBorderOnly` branch sets only `edgeFile` (no `bgFile`, no `SetBackdropColor`) for 2.5.3+ overlays, while the pre-2.5.3 branch keeps the original full-backdrop behavior.

### Changed - 0.5.2

- Refactored the four large hook entry points in `main.lua` to named local functions and registered them through thin `safeCall` wrappers:
  - `GameTooltip:OnTooltipSetUnit`
  - `GameTooltip:OnTooltipSetItem` (and the `ShoppingTooltip1/2` + `ItemRefTooltip` copies)
  - `GameTooltip:OnTooltipCleared`
  - `GameTooltip:OnShow` (re-applies class border on re-show)
- Wrapped the main event frame's `OnEvent` handler and the two `CI.RegisterCallback` shims (`INVENTORY_READY`, `TALENTS_READY`) with `safeCall`.
- Wrapped the `Detours:DetourHook` callback for the `instant_fade` `GameTooltip:FadeOut` override.
- Wrapped the `Detours:ScriptHook` callbacks for `GameTooltip:OnShow` / `OnHide` inside `TacoTip_CustomPosEnable` (the custom-position mover).
- Wrapped every `TacoTipDragButton` script: `OnDragStop`, `OnClick`, `OnShow`, `OnHide`, plus the `NewTicker` callback used by the live mover example.
- Wrapped the options panel's bootstrap `OnEvent` and the four page `OnShow` handlers (`tooltips`, `positioning`, `characterInspect`, root `optionsFrame`) in `options.lua`.

### Hardened - 0.5.2

- `createOptionsDropdown` now:
  - Inherits a validated `parent:GetFrameStrata()` (falls back to `"MEDIUM"` if missing) and a clamped `SetFrameLevel` (no negative levels, capped at 100).
  - Wraps both the `UIDropDownMenu_Initialize` callback body and the per-button `info.func` (the user choice handler) in `safeCall`, so a bad media/font/texture choice in the options panel can never break the dropdown popup.
  - Defends against `option.text`, `option.menuText`, or `option.value` being `nil` (uses `""` and `or` chains) so a single malformed option can't throw mid-popup.

### Notes - 0.5.2

- Version metadata bumped to `0.5.2` in `TacoTip.toc`, `main.lua`, and `options.lua`.
- The speculative `NineSlice:SetBorderColor()` / `NineSlice:SetCenterColor()` / `BackdropTemplateMixin`-on-NineSlice calls from earlier versions of this patch have been removed. All border/backdrop operations now go through a standard `BackdropTemplate` child frame using the same API that works on pre-2.5.3 clients, avoiding any dependency on undocumented NineSlicePanel widget methods.

## [0.5.1] - 2026-06-01

### Fixed - 0.5.1

- Fixed a late tooltip appearance repaint path in `main.lua` by resolving the live tooltip unit inside `TT:ApplyTooltipAppearance()`, so player tooltips no longer fall back to the configured gray border when a later refresh omits the unit token.

### Changed - 0.5.1

- Bumped packaged addon version metadata to `0.5.1` in `TacoTip.toc`, `main.lua`, and `options.lua`.
- Audited the active modern options UI paths and confirmed the current pages still rely on Blizzard `UIPanelScrollFrameTemplate` scroll frames and `UIDropDownMenuTemplate` dropdowns.
- Audited slash-command ownership and intentionally left the current low-risk three-stage structure in place: bootstrap aliases in `gearscore.lua`, the full `/tacotip` handler in `options.lua`, and a defensive fallback in `main.lua`.

### Cleaned Up - 0.5.1

- Removed the unused duplicate `getClassIconMarkup` helper from `options.lua`.
- Removed the inert local `Advanced` page frame stub from `options.lua`; the active UI still consists of the root page plus `Tooltips`, `Positioning`, and `Character & Inspect`.

### Notes - 0.5.1

- No dropdown or scrollbar behavior rewrites were applied in this pass because the active code paths already use Blizzard's standard menu/scroll templates; widget interaction still needs final in-game smoke validation on the target client.

## [0.5.0] - 2026-05-31

### Fixed - 0.5.0

- Fixed tooltip border rendering: replaced broken stretched overlay with native backdrop `edgeFile`/`edgeSize` so the `UI-Tooltip-Border` texture renders as a proper sliced corner/edge border instead of stretching across the entire tooltip surface.
- Fixed class-colored borders: borders now tint correctly via `SetBackdropBorderColor` on the properly rendered sliced border instead of `SetVertexColor` on a stretched overlay.
- Fixed dual-spec display in compact/narrow tooltip style: the inactive specialization was being skipped entirely due to incorrect `elseif` conditions. Both specs now always display.
- Fixed PVP icon: now only shows on player units that are actually PVP-flagged, not on PVP-flagged NPCs.
- Fixed `ensureTooltipBorderOverlay` memory: removed orphaned overlay texture code.

### Added - 0.5.0

- Positioned class icon badge: moved from inline text (first line) to a dedicated atlas texture at the top-right corner of the tooltip with configurable size.
- New `Class icon size` slider in the Tooltips → Portrait & text options section (range 8–32px, default 16px).
- Inactive specialization now displays with 60% alpha fade (`|c99ffffff`) to visually distinguish it from the active spec.

### Changed - 0.5.0

- Class icon is now **enabled by default** (`show_class_icon = true`).
- Pawn score display is now **enabled by default** (`show_pawn_player = true`).
- Bumped packaged addon version to `0.5.0`.

### Notes - 0.5.0

- The options preview tooltip now reflects the positioned class icon and dual-spec display.
- Border render path is now aligned with standard Blizzard backdrop practices.

## [0.4.9] - 2026-05-28

### Added - 0.4.9

- Added an explicit available-languages table to the public README so players can quickly see every shipped locale.
- Added release documentation that clearly explains the root-page language dropdown, client-default locale behavior, and English fallback behavior.
- Added explicit Titanforge / `3.80.1` interface documentation to the supported-version table.

### Changed - 0.4.9

- Bumped the packaged addon version to `0.4.9` in the release manifest and Lua fallback metadata.
- Updated the README and release-facing project copy to match the release-ready public package instead of the earlier first-upload wording.
- Updated the options preview placeholder name from the old maintainer branding to `AcidBomb` for consistency with the current packaged addon metadata.

### Localization - 0.4.9

- Updated `TEXT_HELP_WELCOME` in every shipped locale file so each locale keeps its own language while using the current maintainer name `AcidBomb (Pilsung)`.
- Kept the locale packs aligned with the modern options UI keys shipped in `Locale/enUS.lua`.
- Preserved the default behavior where TacoTip follows the client locale unless players choose a different addon language from the root options page.

### Notes - 0.4.9

- The root options page continues to use a single Blizzard dropdown for language selection.
- Long options pages continue to use mouse-wheel-enabled scroll frames and content-height sizing from the rebuilt page builder.
- This is the intended release tag for the current public package.

## [0.4.8] - 2026-05-28

### Added - 0.4.8

- Rebuilt TacoTip into a polished Blizzard options experience with a parent category plus focused `Tooltips`, `Positioning`, and `Character & Inspect` child pages.
- Added a live tooltip preview inside the options UI so visual changes can be checked immediately without leaving the panel.
- Added tooltip appearance customization for background textures, border textures, border/background colors, alpha values, tooltip fonts, text size, portrait display, portrait scale, and shared health/power bar textures.
- Added a custom-anchor dropdown, refined mover workflow, and numeric/slider overlay offset controls for character and inspect frames.
- Added explicit compatibility notes for Chinese Titanforge / 3.80.1-style Wrath-family clients, which are covered by the build-family runtime gate.
- Restored Blizzard-style hostile mob difficulty coloring on tooltip level lines using `GetQuestDifficultyColor(level)`.
- Added class-colored specialization names with per-spec icons sourced from `LibClassicInspector` talent data.
- Added a separate compact-layout `iLvl` line under GearScore so players can see both values outside the wide layout.
- Expanded the built-in Blizzard font list exposed by the tooltip font dropdown.
- Added Blizzard color-picker-backed border/background swatches and stronger single-dropdown texture-strip previews.
- Added optional SharedMedia pickup for tooltip fonts, statusbar textures, background textures, and border textures.

### Changed - 0.4.8

- Updated the addon's Blizzard AddOns tree entry to use the full metadata title `TacoTip Gearscore TBC`.
- Moved the low-density behavior/client toggles onto the root TacoTip page and stopped using a sparse standalone Advanced page in the active UI flow.
- Merged the low-density Advanced/client toggles into the root TacoTip page and stopped registering the sparse Advanced child page in the active options UI.
- Moved the live tooltip preview into a dedicated right-side column on the Tooltips page.
- Switched collapsed dropdown labels back to plain selected text while keeping Blizzard popup-menu previews for long texture/media lists.
- Updated tooltip media/font dropdown callbacks so a full options refresh runs before the preview is redrawn.
- Improved mover behavior so reset snaps back to the selected anchor corner and `/tacotip default` clears only the saved custom position, not the chosen anchor.
- Updated the final slash-command ownership so `options.lua` provides the complete `/tacotip` command set.
- Extended the options/media/localization copy in `Locale/enUS.lua` to cover the redesigned UI and newer tooltip appearance features.

### Fixed - 0.4.8

- Hardened `LibClassicInspector` load-time ticker and detour setup so missing client globals no longer abort addon startup on TBC Anniversary.
- Fixed `LibDetours-1.0` unhook handling by defining the missing `nop` helper and guarding hook/detour targets before installing them.
- Removed broad luacheck exclusions and cleaned bundled library warnings in `LibStub`, `CallbackHandler-1.0`, and `LibDetours-1.0`.
- Guarded `options.lua` reset flows so overlay `RefreshPosition()` calls do not explode when frames are not ready.
- Bound `main.lua`'s `tinsert` usage to `table.insert` so the tooltip path no longer depends on a possibly-missing global alias.
- Fixed page-builder scroll height so manual layout spacing contributes to the scrollable content size instead of cutting off the bottom of long pages.
- Fixed mouse-wheel behavior on the reusable scroll-page builder and the modern Tooltips page so users no longer need to drag the scrollbar thumb manually.
- Fixed Character & Inspect offset-row overlap by hiding duplicate slider-template titles and increasing row spacing.
- Fixed the green mover handle / tooltip anchor mismatch by keeping the mover re-synced with the selected custom anchor.
- Fixed compact tooltip information density by restoring visible average item level below GearScore.
- Fixed hostile mob level readability by restoring Blizzard difficulty colors instead of leaving non-player hostile levels white.
- Fixed specialization readability by replacing plain white talent-tree names with colored names and real icons.

### Localization - 0.4.8

- Completed first-pass translation tables for the previously empty `Locale/esMX.lua`, `Locale/frFR.lua`, `Locale/itIT.lua`, `Locale/ptBR.lua`, and `Locale/zhTW.lua` files.
- Added missing `HunterScore` strings and other missing high-visibility entries to the populated locale files.
- Performed wording cleanup on the locale packs so the translated helper text reads more naturally.
- Expanded the Chinese locale files with the newest options UI labels and help text used by the modern settings pages.

### Notes - 0.4.8

- This is the first upload-ready public package for the revived TacoTip Gearscore TBC fork.
- It includes both the compatibility restoration work and the later polish/follow-up fixes, so the first uploaded build already reflects the modernized options UI, tooltip upgrades, mover fixes, and locale pass.

## [0.0.1] - 2026-05-18

### Added - 0.0.1

- Initial internal revival of TacoTip Gearscore TBC as a working fork target.
- Restored Classic-era support after the original addon stopped working for TBC Classic.
- Updated Blizzard API wiring for the current Classic flavor families.
- Rebuilt the options panel, mover flow, and slash-command entry points.
- Added a CurseForge-ready Markdown README and changelog.

### Fixed - 0.0.1

- LibClassicInspector load order and helper wiring.
- Bundled library TOCs and multi-flavor interface metadata.
- Tooltip mover, custom anchor, and options bootstrap wiring.
- Luacheck warnings in `LibClassicInspector.lua`.

### Notes - 0.0.1

- This fork exists to keep TacoTip working again and to leave room for future features.
