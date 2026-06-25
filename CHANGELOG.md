# Changelog

All notable changes to TacoTip Gearscore TBC will be documented in this file.

| Version | Date | Summary |
| --- | --- | --- |
| `0.5.4` | `2026-06-24` | Tooltip contamination fix (class border on non-player tooltips), settings-leak fix (item tooltips no longer get portrait/class icon), minimap flicker fix, options UI sizing fix, floating preview pane, config corruption sanitizer, class-borders only for player units |
| `0.5.3` | `2026-06-14` | Real-time mover, 3D PlayerModel portrait, elite/rare/boss atlas portrait overlay, right-click camera passthrough |
| `0.5.2` | `2026-06-02` | NineSlice class-border overlay fix (separate BackdropTemplate child frame), getClassColor/GetUnit hardening, spec dedup guard, safeCall error capture, dropdown audit |
| `0.5.1` | `2026-06-01` | Live class-border tint fix, dead-code cleanup, and production audit pass |
| `0.5.0` | `2026-05-31` | Tooltip border fix, dual-spec display, positioned class icon, PVP icon fix, default toggles |
| `0.4.9` | `2026-05-28` | Release polish: final locale sync, maintainer text update, language list/docs refresh, and release metadata bump |
| `0.4.8` | `2026-05-28` | First public upload: compatibility restoration, modern options UI, tooltip polish, and localization pass |
| `0.0.1` | `2026-05-18` | Internal revival baseline before packaging |

## [0.5.4] - 2026-06-24

### Added - 0.5.4

- **Class icon inline on name line:** The class icon badge has moved from the top-right corner of the tooltip to an inline position on the name line, following the player's name, PvP flag, and faction icon. The icon uses atlas-based inline markup (`|A:...|a`) consistent with the existing faction and PvP flag icons.
- **Rectangular portrait default:** The 2D/3D portrait now defaults to 38×52 pixels (was 36×36 square) — barely wider, noticeably taller — with scale multiplier applied proportionally. Elite/rare/boss dragon border overlays use the same `portraitW` variable for sizing.
- **Configurable 3D portrait zoom:** New slider under Tooltips → Portrait & text (range 0.3–1.0, step 0.05, default 0.7). Previously hardcoded at 0.6.
- **8 optional tooltip QoL features** (all off by default, toggleable in options):

  | Feature | Config Key | Description |
  |---|---|---|
  | **Honor rank display** | `show_honor_rank` | Shows the player's PvP rank title (Knight, Centurion, etc.) via `UnitPVPName()` |
  | **Group role icon** | `show_role_icon` | Appends Tank/Healer/DPS role icons on the name line for party/raid members |
  | **iLvl on name line** | `show_ilvl_inline` | Shows average item level next to the player's name instead of on a separate line |
  | **Realm display** | `show_realm` | Shows realm name for cross-realm players (`UnitIsSameServer`) |
  | **GS change indicator** | `show_gs_delta` | Tracks GearScore per GUID; shows ▲/▼ with delta value when score changed since last seen |
  | **Section separators** | `show_separators` | Adds thin horizontal lines between logical tooltip sections |
  | **Tooltip max-width** | `tooltip_max_width` | Configurable maximum width (0–500px) to prevent wide names/guilds from expanding the tooltip |
  | **Tooltip delay** | `tooltip_delay` | Configurable 0–1000ms debounce before tooltip populates, cancels on hide/clear, bypassed during combat |

- **GS history tracking:** New `TacoTipGSHistory` saved variable stores the last-known GearScore per GUID across sessions. Used by the GS delta feature.
- **Options UI controls:** 7 new checkboxes/sliders across the Tooltips and Positioning pages, all disabled-safe and refresh-synced with the live preview.
- **16 new locale strings** in `Locale/enUS.lua` covering all new control labels, descriptions, and inline display text.
- **Config corruption sanitizer:** `TT:SafeSanitizeConfig()` validates every boolean and numeric config key against its expected type and range on every load, silently repairing corruption caused by abrupt shutdown or disk errors. Players who previously had to delete SavedVariables will now have their config repaired automatically.

### Fixed - 0.5.4

- **Tooltip contamination (class border, portrait, class icon on non-player tooltips):** `itemToolTipHook` no longer calls `TT:ApplyTooltipAppearance(self)`, which previously applied unit-specific effects (class-colored border/background, portrait, elite frame) to item tooltips on GameTooltip, ShoppingTooltips, and ItemRefTooltip. Item tooltips now only receive cosmetic styling (fonts, backdrop texture, border texture) with base config colours — no class tints, portrait, or elite overlays.
- **Settings leakage to all tooltips (Bug 3):** `itemToolTipHook` now independently applies only `applyTooltipFonts`, `applyTooltipBackdrop`, and `applyTooltipBorderOverlay` with the user's configured base border/background colours, skipping class color, portrait, bar texture, and elite-frame code that was inherited from `ApplyTooltipAppearance`.
- **Class border flicker on minimap/main map icons (Bug 4):** `onTooltipShow` now checks `resolveTooltipUnit(tooltip)` before re-applying the class-tinted border. Map icons, items, and other non-unit tooltips never inherit a stale `TacoTipPlayerClassColor` from a prior player hover, eliminating the one-frame-delay border change that caused visible flicker.
- **Class-coloured borders on non-player tooltips (Bug 1):** The `onTooltipShow` guard (`if not unit or not UnitIsPlayer(unit) then return end`) ensures the `CAfter(0, ...)` class-border follow-up only fires when the tooltip genuinely holds a player unit.
- **ShoppingTooltip / ItemRefTooltip stale state:** Added `OnTooltipCleared` hooks to ShoppingTooltip1, ShoppingTooltip2, and ItemRefTooltip so `TacoTipPlayerClassColor` and portrait textures are properly cleaned when those frames are dismissed.
- **Mover-mode backdrop persistence:** When the tooltip mover is active and the cursor moves to a non-player unit, `ApplyTooltipAppearance` is now called before the early return in `onTooltipSetUnit`, preventing the previous player's backdrop/border from persisting on the NPC tooltip.
- **Options UI cut off on the right (Bug 2):** `optionsFrame` and all three child pages now have `SetSize(640, 400)` so the modern Settings canvas allocates enough width. The Tooltips page scroll frame right offset was reduced from `-270` to `-30` after the preview was moved outside.
- **Saved-variable corruption protection:** All boolean config keys are type-checked and repaired on load (string "true"/"false" becomes real boolean). All numeric keys are range-validated. Previously a corrupt `tip_style`, `tooltip_delay`, or alpha value could silently break tooltip rendering.

### Changed - 0.5.4

- Portrait zoom default changed from hardcoded `0.6` to config-driven `0.7` (via `TacoTipConfig.tooltip_portrait_zoom`).
- Portrait sizing default changed from 36×36 to 38×52 (at 1.0 scale).
- Tooltip icons on the name line now use inline `|A:` atlas markup for class icon, consistent with the existing faction/PvP icon markup.
- The tooltip delay timer is cancelled on `OnTooltipCleared` and `OnHide` to prevent stale tooltips from appearing after the cursor moves.
- **Preview pane moved outside the Settings box:** The Tooltips page live-preview now floats as a separate frame parented to `UIParent` with `FULLSCREEN_DIALOG` strata, positioned to the right of the panel. The scroll content takes the full panel width (no longer reserved space for an inline preview). Preview visibility is managed by the tooltips page OnShow/OnHide handlers.
- **Class-colored borders are now applied to player units only.** All non-player tooltips (items, spells, buffs, NPCs, map icons) use base border/background colours regardless of the `tooltip_border_use_class` and `tooltip_background_use_class` settings.

### Hardened - 0.5.4

- `TT:SafeSanitizeConfig()` runs after `ApplyConfigDefaults` on every load and reset, detecting and repairing 19 boolean keys and 9 numeric keys against their expected types and valid ranges.

### Notes - 0.5.4

- All 8 new features from the initial 0.5.4 pass are **off by default** to preserve the existing user experience. Players opt in via the options panel.
- GS history is stored globally as `TacoTipGSHistory` (separate from `TacoTipConfig`) so it persists across config resets.
- The tooltip delay bypasses itself during combat (`InCombatLockdown()`) to avoid frame-delay issues.
- Role icon textures target TBC Classic paths (`Interface\\GroupFrame\\UI-Group-{Tank,Healer,DPS}Icon`).
- Version metadata bumped to `0.5.4` in `TacoTip.toc`, `main.lua`, and `options.lua`.

## [0.5.3] - 2026-06-14

### Added - 0.5.3

- **Real-time tooltip mover:** The green mover button (TacoTipDragButton) now follows the GameTooltip in real-time during drag via an OnUpdate handler that re-anchors the tooltip each frame. The handler is properly cleared on drag stop and wrapped in safeCall.
- **3D portrait (PlayerModel):** Unit portraits now support a live, rotatable 3D model via `PlayerModel:SetUnit(unit)` instead of a static 2D `SetPortraitTexture` snapshot. Config key `tooltip_portrait_3d` (default: enabled). Falls back to 2D texture if PlayerModel is unavailable on the client.
- **Elite/rare/boss dragon border overlay:** When viewing non-player NPC tooltips with portrait enabled, TacoTip now draws the correct Blizzard atlas-based portrait overlays — gold dragon for elite, silver dragon with wings for rare-elite, gold dragon with wings for worldboss, and a star icon for rare. Uses the same atlas names as Blizzard's own `BossPortraitFrameTexture`: `UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold`, `ui-hud-unitframe-target-portraiton-boss-rare-silver`, `UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold-Winged`, and `UnitFrame-Target-PortraitOn-Boss-Rare-Star`. Config key `show_elite_frame` (default: enabled).
- **Options UI:** Two new checkboxes under Tooltips → Portrait & text — "Show 3D portrait" and "Show elite indicator", both greyed out when the main portrait toggle is off.
- **Locale strings:** New keys `OPTIONS_TOOLTIP_PORTRAIT_3D`, `OPTIONS_TOOLTIP_PORTRAIT_3D_DESC`, `OPTIONS_SHOW_ELITE_FRAME`, `OPTIONS_SHOW_ELITE_FRAME_DESC` in all shipped locale files (English fallback for untranslated locales).

### Changed - 0.5.3

- `tooltip_portrait` config default changed from `false` to `true` so the new 3D portrait is visible out of the box.
- `tooltip_portrait_3d` config default changed from `false` to `true`.
- `show_elite_frame` config default set to `true`.
- **Right-click passthrough:** GameTooltip now has `EnableMouse(false)` when a custom saved position is active, so right-clicks pass through to the world frame for camera rotation. Mouse is re-enabled in mouse-anchor and default positioning modes so item links remain clickable.

### Hardened - 0.5.3

- `ensureTooltipPortrait` now uses `pcall(CreateFrame, "PlayerModel", nil, ...)` so a missing PlayerModel widget type cannot crash the addon.
- All 3D PlayerModel methods (`SetUnit`, `SetPortraitZoom`) are called via `pcall` so a missing API on older clients is silently ignored.
- The elite-frame `SetAtlas` calls are wrapped in `pcall` in case an atlas name does not resolve on a given client.
- The `OnDragStart` mover handler is now wrapped in `safeCall` (was previously unprotected).

### Notes - 0.5.3

- Version metadata bumped to `0.5.3` in `TacoTip.toc`, `main.lua`, and `options.lua`.
- The 3D portrait uses `PlayerModel:SetUnit(unit)` with `SetPortraitZoom(0.6)` — the same 0.6 zoom value Blizzard uses for QuestNPCFrame, GuildNews, and TutorialFrame portrait models.
- Locale files for non-English languages use English fallback for the four new keys until translations are contributed.

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
