# Active Context

## 2026-09-21 - TacoTip Forever: Universal Cross-Client Architecture & Test Hardening

- **Universal Multi-Engine Client Support:** Unified `TacoTip_Forever/` to run across all World of Warcraft engine families:
  - Classic Era & Season of Discovery (`11509`)
  - TBC Classic Anniversary (`20506`, `20507`)
  - WotLK Classic & Titanforge (`38001`, `30405`)
  - WoW Forever (`16001`)
  - Retail / Live (`110002` – `120100`)
- **LibForeverInspector:** Added multi-engine runtime gates (`IsClassic`, `IsTBC`, `IsWotlk`, `IsForever`, `IsRetail`), backward-compatibility alias for `LibClassicInspector`, full spec & icon tables, and nil-safe `C_Item.GetInventoryItemLink` delegation.
- **Adaptive GearScore Engine:** Client-aware bracket sizing (200 Era, 400 TBC, 1000 WotLK/Forever/Retail) and dynamic `C_Item.GetItemInfo` resolution.
- **Cross-Engine Pawn Bridge:** Dynamically resolves scale prefixes (`MrRobot:` fallback to `Classic:`) and version variables.
- **Tooltip Pipeline Hardening:** Eliminated Lua 5.3+ float formatting crashes via floored `makeColorCode(r, g, b)`, normalized `getClassColor` calling conventions, and guarded group/raid API invocations.
- **Verification & Zero-Warning Gate:** Passed `luacheck TacoTip_Forever/` with 0 warnings / 0 errors across all 21 files; all 153 WoWUnit test assertions passing cleanly in the test harness.
- **3D Portrait Dynamic Screen-Edge Flipping:** In `ApplyTooltipAppearance`, dynamically calculates tooltip right boundary against screen width (`UIParent:GetRight()` / `_G["GetScreenWidth"]()`). When the tooltip is anchored near the right screen edge, the portrait automatically flips to the left side (`TOPRIGHT -> TOPLEFT (-8, 0)`), preventing the enlarged model from rendering off-screen.
- **Mouse Anchor OnUpdate Idle Gating:** Added `(not TacoTipConfig.anchor_mouse or not GameTooltip or not GameTooltip:IsShown())` early-return check to `TacoTipMouseAnchor:SetScript("OnUpdate")`, eliminating 144–240Hz cursor position queries, scale calculations, and frame point mutations when the tooltip is hidden.
- **Extended Non-Unit Visual Clearing:** Hooked `ItemRefShoppingTooltip1`, `ItemRefShoppingTooltip2`, `WorldMapCompareTooltip1`, and `WorldMapCompareTooltip2` into `registerTooltipVisualClearing` to ensure comparison tooltips never inherit unit-specific borders or state.
- **Padding Cleanup Fallback:** Added `elseif (tooltip.SetPadding) then tooltip:SetPadding(0, 0, 0, 0) end` fallback to `clearTooltipVisuals` for clients lacking `ClearPadding()`.
- **Quality Gate Verification:** Passed static analysis via `luacheck .` with 0 warnings / 0 errors across all 42 files; verified syntax on Lua 5.1.

## 2026-09-13 - v0.7.6: Enterprise Audit, 3D Portrait Resizing & Zero-Allocation Pipeline

- **3D Portrait Resizing:** Increased base 3D model viewport dimensions from `60x80` to `72x96` (+20% size increase, strictly maintaining exact 3:4 aspect ratio with integer dimensions at 50/100/150/200% scale). Throttled model `OnUpdate` alpha synchronization to 20Hz (0.05s) using parent frame alpha caching.
- **Zero-Allocation Hover Pipeline:** Implemented static buffer pooling (`pooledLinesToAdd`, `pooledTooltipText` in `main.lua`) and zero-allocation scalar extraction in `gearscore.lua` (`scoreFromItemValues`), eliminating transient table creation and GC spikes during rapid mouseover scans.
- **SharedMedia Resolution Caching:** Added lazy caching layer in `options.lua` with invalidation hooks (`TT:InvalidateResolvedMediaCache`), converting heavy $O(N \log N)$ sorting and dropdown rebuilding into instant $O(1)$ table reads on every unit hover.
- **Lifecycle & Event Hardening:** Gated `TacoTipPowerBar:OnEvent` to `IsShown()` and dynamically unregistered events on ticker halt; deduplicated `GameTooltip` `OnTooltipCleared`/`OnHide` hooks in `main.lua`; gated `UNIT_TARGET` processing behind `GameTooltip:IsShown()` and `show_target`.
- **Friendly Level Coloring:** Enforced clean white `|cFFFFFFFF` rendering for friendly player levels.
- **Verification & Tests:** Updated and added tests in `TacoTip_Tests.lua` (`Portrait:DefaultSizeIs34Ratio`, `Portrait:ScaledSizeKeepsRatio`, `Borders:MediaResolutionCaching`). Passed `luacheck .` with 0 warnings across all 21 files.
- **Version Bump:** Bumped version to `0.7.6` across manifests, runtime, and documentation.

## 2026-09-11 - v0.7.5: Dual-Spec Lowest GearScore Grey Styling & Hot-Path Gates (Prism-Full Audit)

- **Dual-Spec Active/Inactive Rendering Fix:** Inactive spec name renders in lowest GearScore quality grey (`0.50, 0.50, 0.50` / `GRAY_FONT_COLOR` / `GS_Quality[BRACKET_SIZE]`), active spec name renders in its class color, and talent point numbers `[x/x/x]` render in clean white outside the color code for both specs. Compact mode preserves the invisible zero-alpha `|c00000000%s: |r` alignment prefix. New WoWUnit test `Stats:DualSpecDimRendering`. Non-unit visual isolation verified with `clearTooltipVisuals` across all clear/hide/show transitions.
- **MODIFIER_STATE_CHANGED Gate:** full `SetUnit` rebuild only when a player tooltip is shown AND `tip_style` is 2/4 (the shift-sensitive styles).
- **Mouse-Anchor Idle Skip:** `TacoTipMouseAnchor` OnUpdate returns immediately while `anchor_mouse` is disabled.
- **Item Hook Feature Gate:** `IsEquippableItem`/`GetItemInfo`/pending-load skipped when both `show_item_level` and `show_gs_items` are off.
- **Pawn Scale-Name Reuse:** scale name built once per `TT_PAWN:GetScore` pass, threaded through `GetItemScore`.
- **Options Config Integrity:** non-Wrath `Refresh` no longer force-writes `show_achievement_points = false` into saved config (render stays `CI:IsWotlk()`-gated).
- **Version Bump:** Bumped version to `0.7.5` across `TacoTip.toc`, `main.lua`, `options.lua`, `README.md`, `CHANGELOG.md`, `AGENTS.md`, and memory bank.

## 2026-08-27 - v0.7.3: Performance & Hardening Pass (Prism-Full Audit)

- **Single-Fetch Item Tooltips:** Item tooltip hook performs exactly one `GetItemInfo` call per hover; new `TT_GS:GetItemScoreFromInfo(info)` entry point is shared by the ilvl line, GearScore and HunterScore. `GetItemScore(link)` / `GetItemHunterScore(link, info?)` remain backward compatible.
- **ItemMixin Memoization:** `LibClassicInspector:GetInventoryItemMixin` reuses one `ItemMixin` per (cached user, slot), keyed by item identity so gear swaps rebuild; entries die with their cache user on FIFO eviction.
- **Overlay Offset Clamping:** `setOffsetValue` clamps typed edit-box input to ±300 (`MODERN_OPTION_SLIDER_MIN/MAX`); `SafeSanitizeConfig` repairs out-of-range/corrupt saved offsets (strings, NaN, ±infinity) to defaults on every load.
- **Options OnShow Lifecycle Fix:** Page builders no longer assign `panel:SetScript("OnShow")`; load-tail safeCall wrappers own that slot and already call `panel:Refresh()` (removes order-dependent overwrite).
- **Library Hardening:** `GetTalentInfoByClass` and both branches of `GetTalentInfo` return nil past a tab's real talent count; event dispatcher logs-and-continues on unhandled events; achievement probes use the documented 14th `isStatistic` return; `addCacheUser` now returns the created user table (fixes nil-cache crash in `GetInventoryItemMixin` player branch on fresh login).
- **Backdrop Comment Accuracy:** Stale "pre-2.5.3" notes corrected — NineSlice detection is runtime-based (`tooltip.NineSlice`) and verified present on all supported clients.
- **New Regression Tests:** `Config:SanitizeOffsetBounds` and `Stats:GetItemScoreFromInfoMatchesLink` WoWUnit tests (`/tttest`).
- **Version Bump:** Bumped version to `0.7.3` across `TacoTip.toc`, `main.lua`, `options.lua`, `README.md`, `CHANGELOG.md`, `AGENTS.md`, and memory bank.

## 2026-08-21 - v0.7.2: TBC Classic Anniversary Dual-Spec Resolution & API Hardening

- **TBC Anniversary Dual-Spec Resolution:** Fixed premature load-time capability check in `LibClassicInspector` that permanently blocked talent group 2 on TBC Anniversary clients.
- **`C_SpecializationInfo` API Fallback:** Added wrapper fallback around `GetTalentInfo` with `C_SpecializationInfo.GetTalentInfo(query)` support across TBC Anniversary and SoD/Classic Era.
- **Dynamic Spec Update Events:** Registered `PLAYER_TALENT_UPDATE` and `ACTIVE_TALENT_GROUP_CHANGED` on all dual-spec clients.
- **Talent Point Summation Nil-Safety:** Added `or 0` guards for `select(5, GetTalentInfo(...))` across all talent aggregation routines.
- **Version Bump:** Bumped version to `0.7.2` across `TacoTip.toc`, `main.lua`, `options.lua`, `README.md`, `CHANGELOG.md`, `AGENTS.md`, and memory bank.

## 2026-08-20 - v0.7.1: Excision of Obsolete Preview Tooltip & Release Preparation

- **Excised Obsolete Floating Preview Tooltip:** Removed `modernShowExampleTooltip`, `previewPane`, `previewHealthBar`, `previewPowerBar`, `previewAnchor`, `positionPreviewTopRight`, `clearPreviewVisuals`, and `TT:ApplyPreviewClassOverride`.
- **Streamlined Options UI:** Removed over 40 redundant `modernShowExampleTooltip()` calls across all widget callbacks in `options.lua`. Options controls directly write config with zero unnecessary overhead.
- **Locale Polish:** Cleaned up descriptions and removed dead `OPTIONS_PREVIEW_HEADER` and `OPTIONS_PREVIEW_HELP` across all 11 locale files (`enUS`, `deDE`, `esES`, `esMX`, `frFR`, `itIT`, `koKR`, `ptBR`, `ruRU`, `zhCN`, `zhTW`).
- **Static Analysis & Testing:** Passed `luacheck .` with 0 warnings / 0 errors across all 21 files.
- **Version Bump:** Bumped version to `0.7.1` across `TacoTip.toc`, `main.lua`, `options.lua`, `README.md`, `CHANGELOG.md`, `AGENTS.md`, and memory bank.

## 2026-07-19 - v0.6.2: Classic Era/SoD Guild Display & API Hardening

- **Classic Era/SoD Guild Display Fallback:** Restructured the guild text display when `GetGuildInfo` returns nil (due to API restrictions on other player units on patch 1.15.8 Classic Era/SoD clients) by parsing `<Guild Name>` directly from the tooltip text lines.
- **Overwriting/Hiding Disabled Guilds:** Ensured disabled guild display completely overwrites/clears the guild line, preventing empty `<>` brackets from displaying.
- **GetTalentInfo Parameter Mapping:** Fixed a talent querying bug where `group` was being mapped to `isPet` instead of the 5th parameter.
- **CanInspect redundant parameter warning:** Removed the redundant boolean argument from the call to `CanInspect` inside `LibClassicInspector`.
- **Unit Tests:** Added `Guild:ClassicEraFallbackParsing` unit test to verify brackets fallback extraction and hiding.
- **Version Bumps:** Bumped addon version to `0.6.2` across manifests, runtime, and documentation.

## 2026-07-17 - v0.6.1: Audit Correctness Fixes

- **Config Sanitizer (`tip_style`):** Fixed a bug where `tip_style` was incorrectly included in `booleanKeys`, forcing it to default to `2` on reload.
- **GetQuality Green/Blue Swap:** Corrected copy-paste error swapping green and blue channels in GearScore quality coloring.
- **CAfter Border Bleed Guard:** Added `clearTooltipPlayerClassColor` to the non-unit tooltip branch inside `onTooltipShow`.
- **Power Bar Cleanup:** Hiding the power bar and stopping its update ticker inside the centralized `clearTooltipVisuals` function.
- **Color Range Validation:** Added float range checks to color channels during config sanitization.

## 2026-07-15 - v0.6.0: WoWUnit Test Suite Integration & Visual Fixes

- **WoWUnit Test Suite:** Integrated a standalone test runner (`/tttest`) to run modular assertions (core namespace, configs, borders, and specs).
- **3D Portrait Frame Size:** Resized the 3D model viewport to 42×56 (3:4 ratio).
- **Border Bleed Fixes:** Hardened OnShow/OnHide script hooks to prevent border bleeding onto minimap or world map icons.

## 2026-06-12 - v0.5.2: NineSlice class-border overlay fix & border thickness slider

- **Root cause fixed:** The 2.5.3 Consolidated UI Changes moved tooltip backdrops from GameTooltip to a NineSlicePanel sub-frame. NineSlice renders its own built-in grey border that covers any backdrop applied to the tooltip parent, so `SetBackdropBorderColor` had no visible effect. The fix replaces all speculative `NineSlice:SetBorderColor()` / `NineSlice:SetCenterColor()` / `BackdropTemplateMixin`-on-NineSlice calls with a **separate `BackdropTemplate` child-frame overlay** (`getOrCreateBackdropFrame` / `applyTooltipBackdrop`). On 2.5.3+ the NineSlice stays visible for the default background; the overlay frame sits at `FrameLevel(2)` (above NineSlice, below text) and draws only the colored border edge via `SetBackdrop({edgeFile = ...})` + `SetBackdropBorderColor`.
- **`getClassColor` safe-pattern rewrite:** guards both `CUSTOM_CLASS_COLORS` and `RAID_CLASS_COLORS` against nil before indexing. The old one-liner `(CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[class]` could throw if `RAID_CLASS_COLORS` was nil and the `or` fell through.
- **`resolveTooltipUnit` pcall guard:** wraps `tooltip:GetUnit()` in `pcall` so a single `GetUnit` error cannot crash the entire tooltip render path.
- **`safeCall` error capture on all hooks:** all GameTooltip script hooks, event handlers, and callback shims are wrapped in `xpcall(..., geterrorhandler(), ...)` so errors are captured by BugSack/!Swatter instead of silently breaking tooltips.
- **Defensive class-border follow-up:** a `C_Timer.After(0.05, ...)` re-applies the class-tinted border in case Blizzard refreshes the tooltip frame after `OnTooltipSetUnit` completes, and an `OnShow` hook re-applies it on re-show (deferred to next frame so Blizzard's own setup runs first).
- **Dual-spec dedup:** Both `active == 1` and `active == 2` branches now skip rendering the inactive spec when `spec1 == spec2`, preventing the same tree being printed twice.
- **Class icon reposition:** moved anchor from `(-4, -2)` to `(-10, -8)` and default size from 16 to 20 for better visual breathing room.
- **Border thickness slider:** added `createOptionsSlider` for `tooltip_border_edge_size` (range 4–48px, default 14) in the Tooltips page's "Backdrop colors & textures" section, wired into both the 2.5.3+ border-only path and the pre-2.5.3 fallback path in `applyTooltipBackdrop`.
- **New config key:** `TacoTipConfig.tooltip_border_edge_size` (default `14`)
- **Packaged/release metadata and docs now aligned on `0.5.2`.**

## 2026-05-28 - 0.4.9 release prep finalized

- Bumped the packaged/public addon version to `0.4.9` in `TacoTip.toc` plus the Lua fallback metadata in `main.lua` and `options.lua`.
- Updated `README.md` with the `0.4.9` public version, a release-ready summary, an explicit available-languages table, and clearer language-dropdown / fallback behavior notes.
- Added a `0.4.9` changelog entry covering release polish, locale sync, maintainer-name cleanup, and the supported-version documentation refresh.
- Updated the tooltip preview placeholder name from `Kebabstorm` to `AcidBomb` for consistency with the current packaged addon metadata.
- Corrected `TEXT_HELP_WELCOME` in every shipped locale so each locale keeps its own language while using the new maintainer name `AcidBomb (Pilsung)`.
- Re-verified that `options.lua` still uses a single Blizzard dropdown for the root language selector and keeps mouse-wheel-enabled scroll hooks on the long options pages.

## 2026-07-14 - 0.5.9 preview/settings reactivity pass

- Removed the `IsShiftKeyDown()` dependency from the Tooltips-page preview's *base* layout (`options.lua`): the preview now reflects the selected `tip_style` exactly like the live tooltip — hybrid styles (2/4) show their compact default and expand to full on Shift via a `MODIFIER_STATE_CHANGED` handler on the Tooltips page `OnShow` (unregistered `OnHide`). All other settings drive both the preview and the live tooltip with no keypress. The preview is a FIXED ROGUE mannequin (named AcidBomb) and shows on the Tooltips child page `OnShow`, hides on `OnHide`.
- Verified mechanically that all 43 preview-affecting controls write their `TacoTipConfig.*` key and immediately call `modernShowExampleTooltip()`; the live tooltip applies the same keys via `onTooltipSetUnit` → `TT:ApplyTooltipAppearance`. So every setting feeds BOTH tooltips.
- Added `TT:ApplyPreviewClassOverride(tooltip, "ROGUE")` (main.lua) so the preview's class-tinted border/background match the ROGUE mannequin instead of the real player's class.
- Added `clearPreviewVisuals()` (options.lua) on page `OnHide` to release the 3D portrait model; fixed power-bar geometry when the HP bar is hidden.
- Docs updated: CHANGELOG `0.5.9`, README, AGENTS runtime notes, memory-bank techContext/activeContext. Locale files already carried the preview keys; no new strings introduced.

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

- The addon supports Classic Era / TBC Classic Anniversary / Wrath Classic only (`Interface` 11508 / 20505 / 30405). `30405` is carried forward unverified (no WotLK reference branch to validate against).
- `TacoTip.toc` loads bundled libs first, then `gearscore.lua`, `pawn.lua`, `options.lua`, and `main.lua`.
- Core runtime modules share globals: `TT`, `TT_GS`, `TT_PAWN`, `TacoTipConfig`, and `TACOTIP_LOCALE`.
- Pawn support is optional and gated by `PawnClassicLastUpdatedVersion >= 2.0538` **OR** presence of Pawn's public API (`PawnGetItemData` / `PawnGetSingleValueFromItem` / `PawnGetScaleColor`). SoD-era Pawn lacks the version global, so the API-presence fallback is what enables Pawn on SoD.
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

## Universal inspection restoration

Work is scoped to `TacoTip_Forever/`: bounded GUID queue with temporary-unavailability recovery and range guards, inventory-event refresh and client-specific regression coverage. See the nested changelog; TBC Anniversary user testing confirmed equipment eventually loads without hangs. Other clients have offline coverage only.
