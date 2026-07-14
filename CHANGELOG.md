# Changelog

All notable changes to TacoTip Gearscore TBC will be documented in this file.

| Version | Date | Summary |
| --- | --- | --- |
|| `0.5.9` | `2026-07-14` | SoD fixes: 3D portrait for players AND enemies (no bleed), class-color border no longer bleeds to enemies, Pawn loads on SoD (rune→spec + API-presence gate) |
| `0.5.7` | `2026-07-12` | Cross-client hardening: pcall guards on PawnGetScaleColor + SetPortraitTexture, LibClassicInspector nameplate field fix |
| `0.5.6` | `2026-07-11` | Fix: portrait bleed-through on non-unit tooltips |
| `0.5.5` | `2026-06-24` | Hotfix: `clearTooltipVisuals` forward-reference crash when triggered by other addons (BugSack error on Bartender4/LoonBestInSlot tooltip events) |
| `0.5.4` | `2026-06-24` | Tooltip contamination fix (class border on non-player tooltips), settings-leak fix (item tooltips no longer get portrait/class icon), minimap flicker fix, options UI sizing fix, floating preview pane, config corruption sanitizer, class-borders only for player units |
| `0.5.3` | `2026-06-14` | Real-time mover, 3D PlayerModel portrait, elite/rare/boss atlas portrait overlay, right-click camera passthrough |
| `0.5.2` | `2026-06-02` | NineSlice class-border overlay fix (separate BackdropTemplate child frame), getClassColor/GetUnit hardening, spec dedup guard, safeCall error capture, dropdown audit |
| `0.5.1` | `2026-06-01` | Live class-border tint fix, dead-code cleanup, and production audit pass |
| `0.5.0` | `2026-05-31` | Tooltip border fix, dual-spec display, positioned class icon, PVP icon fix, default toggles |
| `0.4.9` | `2026-05-28` | Release polish: final locale sync, maintainer text update, language list/docs refresh, and release metadata bump |
| `0.4.8` | `2026-05-28` | First public upload: compatibility restoration, modern options UI, tooltip polish, and localization pass |
| `0.0.1` | `2026-05-18` | Internal revival baseline before packaging |

## [0.5.9] - 2026-07-14

### Fixed - 0.5.9

- **3D portrait bleed on enemy units (SoD / Classic Era):** The 3D `PlayerModel` portrait was gated to player units only, so hovering an enemy/NPC after a player left the previous player's 3D model visible (the 2D `SetPortraitTexture` fallback is a no-op on a `Model` frame). The 3D path now calls `SetUnit(unit)` for **any** unit (players and enemies both render on a PlayerModel) and `pcall(ClearModel)` first so the prior mesh is flushed. 3D stays on by default for everyone. 2D `SetPortraitTexture` is now used only when 3D model creation fails.
- **Class-color border bleed to enemies:** `storeTooltipPlayerClassColor` returned the **stale** cached class color when no unit was resolvable, so an enemy tooltip could inherit a previous player's class color. It now **clears** the cached color for any non-player / unresolvable unit, so class-tinted borders apply only to players.
- **Pawn non-functional on SoD:** SoD-era Pawn does not expose `PawnClassicLastUpdatedVersion`, so the old version-only load gate made `pawn.lua` return early and `TT_PAWN:GetScore` was never called → no Pawn line. The load gate now also accepts Pawn's public API presence (`PawnGetItemData` / `PawnGetSingleValueFromItem` / `PawnGetScaleColor` all functions) as proof of load. The spec lookup falls back to the primary spec (`or 1`) because SoD runes replace talent trees and `LibClassicInspector:GetSpecialization` can return `nil` — previously this produced a malformed scale name (`"Classic":CLASS..nil`) and a 0 score.

### Changed - 0.5.9

- **Preview is settings-driven and also expands on Shift (matching the live tooltip):** The Tooltips-page preview now reflects the selected `tip_style` exactly as the live tooltip does — hybrid styles (2/4) show their compact default and expand to full while Shift is held, via a `MODIFIER_STATE_CHANGED` handler registered on the Tooltips page `OnShow` (unregistered on `OnHide`). Every other setting (class color, portrait, bars, fonts, textures, borders, alpha, content toggles) drives the preview directly with no keypress. The preview and the live tooltip both read the same `TacoTipConfig.*` keys, so a setting change updates both.
- **Preview visibility scoped to the Tooltips page only:** The floating preview pane shows when the Tooltips child page opens (`OnShow`) and hides on close (`OnHide`); the Positioning and Character/Inspect pages never show it.
- **Every tooltip setting feeds BOTH tooltips:** Verified mechanically that `modernShowExampleTooltip` (preview) and the live `onTooltipSetUnit` → `TT:ApplyTooltipAppearance` path read the same `TacoTipConfig.*` keys. All 43 preview-affecting controls write their key and immediately call `modernShowExampleTooltip()`; the live tooltip re-applies appearance on every unit show. So toggling any setting (style, class color, portrait, bars, fonts, textures, borders, alpha, etc.) updates both the example and the real tooltip.
- **Preview class-color consistency (P2):** The preview is a fixed ROGUE mannequin (named AcidBomb). Added `TT:ApplyPreviewClassOverride(tooltip, "ROGUE")` so the class-tinted border/background match the mock identity instead of inheriting the real player's class color (previously a Paladin would see ROGUE text with a Paladin border).
- **Preview resource cleanup (P6):** Added `clearPreviewVisuals()` called on the Tooltips page `OnHide` — clears the 3D portrait model (`ClearModel`) and hides portrait/elite/class-color state so the preview does not hold a mounted model in memory while hidden.
- **Preview power-bar geometry (P3):** When the health bar is hidden, the power bar now tucks directly under the tooltip (1px gap) instead of leaving an 8px dead stub.

### Notes - 0.5.9

- Version metadata bumped to `0.5.9` in `TacoTip.toc`, `main.lua`, and `options.lua`.
- SoD and Classic Era share patch `1.15.8` → both target interface `11508`. SoD-specific breakage is the rune/talent divergence in `LibClassicInspector`, not a client-version difference; no separate SoD client handling is required.
- The `## Interface:` list (`11508, 20505, 30405, 38001`) is unchanged. `30405` (Wrath Classic) is retained but **unverified** — there is no WotLK FrameXML branch in `wow-ui-source` to validate its API surface against, so it is currently carried forward on trust from prior releases rather than confirmed.

## [0.5.8] - 2026-07-13

### Fixed - 0.5.8

- **Green dot mover starts at TOPLEFT instead of BOTTOMRIGHT:** The green dot now defaults to the bottom-right corner of the screen. Its starting position is decoupled from `custom_anchor` (which controls tooltip-vs-dot relationship). Existing saved positions at the old default (`TOPLEFT, TOPLEFT, 0, 0`) auto-migrate to the new BOTTOMRIGHT default on version upgrade.
- **Drag-stop crash on mover:** `GetPoint()` after `StopMovingOrSizing()` returns nil anchors, corrupting `custom_pos` and crashing on the next `SetPoint`. Replaced with `GetLeft()/GetBottom()` relative to UIParent's BOTTOMLEFT origin (the WoW screen coordinate origin).
- **Corrupted `custom_pos` from old crash:** The nil-anchor bug could store `{nil, nil, nil, nil}` in SavedVariables. Added a load-time sanitizer that validates the 4 entries and a creation-time guard, so corrupted data cannot crash `SetPoint` on next login.
- **"Anchor family connection" crash on mover middle-click:** `ShowExample` called `GameTooltip_SetDefaultAnchor` while the tooltip was already anchored to the drag button (a UIParent child) — creating a circular anchor family. When `custom_pos` is set, `ShowExample` now anchors directly to the drag button instead of going through Blizzard's default anchor function.
- **`ShowExample` nil crash on nameplate hover:** `onTooltipSetUnit` called `TacoTipDragButton:ShowExample()` without a nil check. Added guard matching the existing pattern in `syncTooltipMoverPosition`.
- **`SetMaxWidth` crash on SoD Classic Era:** The preview GameTooltip doesn't have `SetMaxWidth` in Classic Era. Guarded with a nil check before calling — SoD skips, TBC/Wrath works normally.
- **`class_icon_size` slider had no effect:** `getClassIconMarkup()` hardcoded `14:14` for the class icon atlas size instead of reading `TacoTipConfig.class_icon_size`. The slider now correctly controls the rendered icon size on the name line.
- **Green dot invisible after unlock:** `SetFrameStrata("DIALOG")` silently falls back to `"MEDIUM"` on Classic Era / SoD, hiding the dot behind everything. Reverted to `"TOOLTIP"` (frame level 999 retained) which works on every client.

### Added - 0.5.8

- **Options preview now reflects all tooltip content toggles:** The live preview on the Tooltips page now reads `show_class_icon`, `show_honor_rank`, `show_role_icon`, `show_realm`, `show_separators`, `tooltip_max_width`, and `show_ilvl_inline` — so every toggle on the page is visible in the preview immediately.
- **Preview values updated for SoD (level 60):** The mock character now shows level 60, GearScore 2517, iLvl 79, Pawn 456.78, and 51-point talent specs (Combat 20/31/0, Subtlety 5/0/46) matching Classic Era / SoD endgame instead of Wrath-level 80 data.
- **`modernShowExampleTooltip` wrapped in error protection:** The preview function now uses `xpcall` with `geterrorhandler()` so a single callback error cannot freeze the options panel. Also calls `Hide()` before `Show()` for clean re-layout on every refresh.

### Hardened - 0.5.8

- **All option controls audited for config-key wiring:** Traced every checkbox, dropdown, color swatch, and slider on the Tooltips page to confirm each writes its config key AND each key is consumed by both the real tooltip render path (`main.lua`) and the options preview (`modernShowExampleTooltip`). No orphaned or phantom controls remain.

### Notes - 0.5.8

- Version metadata bumped to `0.5.8` in `TacoTip.toc`, `main.lua`, and `options.lua`.
- The class icon size default is `20` (unchanged from 0.5.7); the old hardcoded `14` was below the slider range minimum of `8`.
- Users who saved a custom dot position with non-default offsets or a non-TOPLEFT anchor are NOT migrated — only exact matches of the old default `{"TOPLEFT","TOPLEFT",0,0}` are cleared to pick up the new BOTTOMRIGHT position.
- Pawn errors on SoD (`Can't get scale colors until Pawn is initialized`) are logged by Pawn's own initialization, not TacoTip. The addon wraps every `PawnGetScaleColor` call in `pcall` so no TacoTip code path crashes, but Pawn's own error handler may still surface the message in BugSack on first login each session.
- **Pawn scores now work on SoD:** Pawn's scale data loads 2–3 seconds after login on Season of Discovery. Instead of calling `PawnGetScaleColor` immediately (which triggers a chat-spamming error), the module now defers its first probe by 3 seconds (retrying once at 8s if needed) before marking Pawn as ready. Pawn scores display normally on TBC/Wrath where Pawn is ready instantly. No errors, no chat spam.

## [0.5.7] - 2026-07-12

### Fixed - 0.5.7

- **Pawn "scale colors" error on Season of Discovery (SoD):** `PawnGetScaleColor` throws "can't get scale colors until pawn is initialized" when called before Pawn's scale data is ready — the Classic Era client (SoD) fires tooltip events before Pawn finishes initializing. Wrapped the call in `pcall` so the error is caught silently and the tooltip renders without interruption. No behavioral change on TBC/Wrath where Pawn is always initialized before the first tooltip event.
- **SetPortraitTexture crash on non-player units with 3D portrait mode:** When 3D portrait mode was enabled but the target was an NPC/mob, `SetPortraitTexture` received a `PlayerModel` frame instead of a `Texture` and threw. Wrapped in `pcall` — portrait silently skips for non-player units when 3D mode is on. Fixes SoD crash; TBC/Wrath silently tolerated the mismatch.
- **LibClassicInspector nameplate GUID lookup crash (TBC Anniversary):** `PlayerGUIDToUnitToken` used `nameplate.namePlateUnitToken` but the TBC Anniversary API exposes `nameplate.unitToken`. The nil field caused `UnitGUID(nil)` to throw ~5000 times per session. Fixed to read `nameplate.unitToken or nameplate.namePlateUnitToken` with a `GetNamePlates()` existence guard. SoD Classic Era also benefits from the guard.

### Notes - 0.5.7

- Version metadata bumped to `0.5.7` in `TacoTip.toc`, `main.lua`, and `options.lua`.

## [0.5.6] - 2026-07-11

### Fixed - 0.5.6

- **Portrait bleed-through on non-unit tooltips (F1/F2/F3):** When a unit was targeted and the user hovered over other Blizzard UI elements (character pane items, buffs, action bars, UI menus, options hover-help), the unit's portrait persisted on GameTooltip. Root cause: the portrait was only hidden via `OnTooltipCleared`, but the TBC Anniversary client can transition tooltip content through paths that skip this event (`OnShow` without a preceding `Clear()`, `OnTooltipSetUnit` with an invalid unit, `ClearLines()` + `Show()` in addon code). Three defensive layers added:
  - `onTooltipShow` now calls `clearTooltipVisuals(tooltip)` in its early-return path (when no class color is cached), covering all Show-based transitions including `showHoverTooltip` in the options panel.
  - `onTooltipSetUnit`'s invalid-unit branch now also calls `clearTooltipVisuals(tooltip)` alongside the existing `clearTooltipPlayerClassColor`.
  - A new `GameTooltip:HookScript("OnTooltipSetSpell", ...)` handler calls `clearTooltipVisuals` when buff/spell content is displayed, catching the direct spell-tooltip path.

### Notes - 0.5.6

- Version metadata bumped to `0.5.6` in `TacoTip.toc`, `main.lua`, and `options.lua`.

## [0.5.5] - 2026-06-24

### Fixed - 0.5.5

- **`clearTooltipVisuals` forward-reference crash (BugSack):** The `itemToolTipHook` function at line 1070 attempted to call `clearTooltipVisuals(self)` before the local function was defined later in the file. Lua locales are not hoisted, so when other addons (Bartender4, LoonBestInSlot) triggered the item-tooltip hook via their own tooltip interactions, the nil reference crashed with "attempt to call global 'clearTooltipVisuals' (a nil value)". The function definition now precedes its call site.

### Notes - 0.5.5

- Version metadata bumped to `0.5.5` in `TacoTip.toc`, `main.lua`, and `options.lua`.

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
