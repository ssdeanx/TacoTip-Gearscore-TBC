# Changelog

All notable changes to TacoTip Gearscore TBC will be documented in this file.

| Version | Date | Summary |
| --- | --- | --- |
| `0.7.7` | `2026-09-18` | Enterprise performance hardening & hot-path zero-allocation pass: Converted all 38 `onTooltipSetUnit` line insertion points from dynamic table allocations to static record pooling (`addLineDouble` / `addLineSingle`). Replaced player line allocation with `wipe(pooledPlayerText)`. Eliminated all `unpack(v)` operations in line rendering. Dynamic 3D portrait screen-edge flipping preventing off-screen model clipping. Gated `TacoTipMouseAnchor` OnUpdate behind `GameTooltip:IsShown()`. Hooked comparison tooltips (`ItemRefShoppingTooltip1/2`, `WorldMapCompareTooltip1/2`) into `registerTooltipVisualClearing`. Added padding cleanup fallback. Zero luacheck warnings across all 42 files. |
| `0.7.6` | `2026-09-13` | Enterprise audit & performance pass: 3D portrait enlarged to `72x96` (strictly preserving 3:4 aspect ratio with integer dimensions at 50/100/150/200% scale). Zero-allocation hover pipeline (pooled buffer tables in `main.lua` and zero-alloc `scoreFromItemValues` in `gearscore.lua`). SharedMedia resolution caching (`TT:InvalidateResolvedMediaCache`) eliminating $O(N \log N)$ table sorts on hover. PowerBar event lifecycle hardened against combat event floods. Deduplicated redundant `GameTooltip` `OnTooltipCleared` and `OnHide` hooks. Gated `UNIT_TARGET` event processing. Throttled 3D portrait `OnUpdate` alpha sync to 20Hz. Pure white friendly player levels. New unit tests in `TacoTip_Tests.lua`. |
| `0.7.5` | `2026-09-11` | Dual-spec active/inactive rendering fixed: the inactive spec name renders in lowest GearScore quality grey (`0.50, 0.50, 0.50` / `GRAY_FONT_COLOR`), the active spec name renders in its class color, and talent point numbers `[x/x/x]` render in clean white for both specs. New `Stats:DualSpecDimRendering` regression test. Performance: `MODIFIER_STATE_CHANGED` re-render gated to shown tooltips on shift-sensitive styles (2/4), mouse-anchor `OnUpdate` no-ops while mouse anchoring is disabled, item tooltip hook skips `IsEquippableItem`/`GetItemInfo` when both item features are off, Pawn scale name built once per scoring pass. Options: non-Wrath clients no longer force-write `show_achievement_points = false` into saved config (render path stays WotLK-gated). |
| `0.7.4` | `2026-09-10` | Per-tooltip lifecycle state: every timer, generation counter, item-load handle and the power-bar cleanup are now owned per tooltip frame, so clear/hide of one tooltip can no longer cancel another's pending work. Cancellable item-data refresh on uncached equippable items via C_Item continuation (generation + link guarded, with a `C_Item.RequestLoadItemDataByID` fallback and delayed-tooltip timer hardening). Duplicate equipped-item id dedupe at every Gearscore/Pawn callback registration site. `getOrCreateItemMixin` hoisted to module scope in LibClassicInspector (no per-slot closure allocation on the inspect hot path). Three new WoWUnit regression tests. Zero luacheck warnings. |
| `0.7.3` | `2026-08-27` | Performance & hardening pass from prism-full audit: single `GetItemInfo` fetch per item tooltip (new `TT_GS:GetItemScoreFromInfo`, HunterScore reuses the fetch), memoized `ItemMixin` allocation in `LibClassicInspector:GetInventoryItemMixin` keyed by item identity, overlay offset clamping (edit-box writer plus `SafeSanitizeConfig` bounds incl. NaN/infinity repair), removed order-dependent options-page `OnShow` overwrites of safeCall wrappers, library hardening (`GetTalentInfoByClass`/`GetTalentInfo` nil-talent guard on both player and inspected branches, nil-safe event dispatcher, achievement validity probes moved to the documented 14th `isStatistic` return), stale "pre-2.5.3" backdrop comments corrected to runtime NineSlice detection, two new regression tests. |
| `0.7.2` | `2026-08-21` | Fix: TBC Classic Anniversary Dual-Spec Resolution. Resolved premature load-time `hasDualSpec` capability evaluation in `LibClassicInspector`, added `C_SpecializationInfo.GetTalentInfo` query fallback for TBC Anniversary & SoD, registered `PLAYER_TALENT_UPDATE` & `ACTIVE_TALENT_GROUP_CHANGED` dynamically across all dual-spec clients, and guarded talent point summation against nil ranks. |
| `0.7.1` | `2026-08-20` | Cleanup & Architecture Polish: Completely excised obsolete floating options preview tooltip (`modernShowExampleTooltip`, `previewPane`, `previewHealthBar`, `previewPowerBar`, `previewAnchor`) and dead helper methods across `options.lua` and `main.lua`. All option controls directly update configuration with 0 overhead. Cleaned up options page layout and descriptions across all 11 locale files. Zero luacheck warnings / zero errors across all 21 files. |
| `0.7.0` | `2026-08-14` | Fix: Minimap & World Map POI / pin / node tooltip flickering resolved. Disabled mouse capture on GameTooltip, preserved true caller frame ownership in GameTooltip_SetDefaultAnchor, and guarded UPDATE_MOUSEOVER_UNIT against falsely hiding non-unit tooltips. Tooltip border edge size default changed to 14px. Deferred border timers converted to cancellable C_Timer.NewTimer handles. |
| `0.6.9` | `2026-08-13` | Shaman Blue default toggle for Classic Era/SoD, Details BarBorder 3 default border with 18px edge size, custom scrollable media dropdown selector UI (Image 2 style), updated unit tests and localization. |
| `0.6.8` | `2026-08-11` | Fix: non-unit tooltip bleed-through & flicker resolved by converting deferred border timers to cancellable `C_Timer.NewTimer` handles and adding `GameTooltip:OnTooltipCleared` hook. Fix: all 4 WoWUnit tests passing (`DefaultsHaveKeys`, `ConfigDefaultsShowGuild`, `ClassicEraBleedThrough`, `ClassicEraFallbackParsing`). Removed `show_gs_delta` & `TacoTipGSHistory` tracking. |
| `0.6.7` | `2026-08-10` | Version metadata bumped to `0.6.7`. SoD / Classic Era dual-spec rendering fix, merged Classic-Era bleed-through regression test. |
| `0.6.6` | `2026-07-28` | Fix: power bar ticker leak on GameTooltip hide, PowerBarColor nil-guard defence-in-depth, guild_rank_style dead-key cleanup, fade-out callback stacking replaced with cancellable timer. Prism-full structural audit. Fix: 11 Lua Language Server `param-type-mismatch` warnings in `LibClassicInspector` by annotating a localized `GetTalentInfo` reference with Classic WoW parameters, and correcting the arguments passed to `GetNumTalents`/`GetTalentInfo` in `cacheUserTalents`. |
| `0.6.5` | `2026-07-27` | Fix: talent inspection rendering for other players via `LibClassicInspector:DoInspect` and fallback active talent group `or 1`. Fix: standardized Option C line formatting across `Level`, `Target:`, `Talents:`, `GearScore:`, `iLvl:`, and `Pawn:` lines with clean white label prefixes and inline-colored values right next to labels. Fix: multi-tooltip visual clearing across `GameTooltip`, `ShoppingTooltip1/2`, `ItemRefTooltip`, `WorldMapTooltip`, and `SmallTextTooltip`. |
| `0.6.4` | `2026-07-26` | Fix: guild fallback parser regex (`^<([^>]+)>%s*(.*)$`) to extract both guild name and rank from 2-line client tooltips (`<GuildName> Rank`). Fix: removed gold rank font color formatting so ranks display in clean white text after the green guild tag. Fix: Level/race/class line missing for guilded players on SoD/Classic Era by dynamically targeting line 3 for guilded players and line 2 for un-guilded players. Fix: UnitIsSameServer API signature argument warning. |
| `0.6.3` | `2026-07-25` | Fix: guild display format flipped from `"Rank of <Guild>"` to `"<Guild> Rank"` with guild first. Rank now uses gold highlight color instead of parentheses. All parentheses removed from both guild display styles. All locale files updated for the new format ordering. Fix: guild text bleed onto non-unit tooltips resolved by storing the guild line index on the tooltip frame and clearing it in clearTooltipVisuals (same pattern as the class-color border fix). Fix: level/race/class line missing for guilded players on SoD/Classic Era by re-deriving from API when the client omits it. Fix: ClassicEraFallbackParsing unit test was failing because UnitExists wasn't mocked. |
| `0.6.2` | `2026-07-19` | Fix: guild name/rank display and rank formatting on Classic Era and Season of Discovery (SoD) by implementing a fallback parser to extract the guild name from the tooltip lines when GetGuildInfo is restricted, and completely clearing the guild line when disabled to prevent empty <> brackets. Fix: redundant parameter CanInspect warning in LibClassicInspector. Fix: parameter-mapping bug in GetTalentInfo call. Added unit tests for fallback guild parsing and hiding. |
| `0.6.1` | `2026-07-17` | Config sanitizer fix (tip_style no longer forced to 2), GetQuality color channel swap fix, CAfter border bleed defense + generation-counter cancellation + direct backdrop reset, power bar cleanup, Pawn API pcall guard, portrait/visual leak fix on map POI tooltips (onTooltipShow → clearTooltipVisuals), elite frame portrait border removed (broken SetAtlas on TBC Classic), locale completion pass, test suite hardening (float tolerance, Interface metadata fallback, SetUnit-based bleed tests) |
| `0.6.0` | `2026-07-15` | Class-color border bleed-through fix on the shared GameTooltip (clear + non-player OnShow + spell paths), 3D portrait enlarged to 42×56 (3:4), standalone WoWUnit test suite (/tttest) added as optional dependency, inline test stub removed |
| `0.5.9` | `2026-07-14` | SoD fixes: 3D portrait for players AND enemies (no bleed), class-color border no longer bleeds to enemies, Pawn loads on SoD (rune→spec + API-presence gate) |
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

## [0.7.7] - 2026-09-18

### Performance & Memory Optimization - 0.7.7

- **Hot-Path Zero-Allocation `linesToAdd` Pipeline:**
  - Converted all 38 `tinsert(linesToAdd, { ... })` sites in `onTooltipSetUnit` to reusable static records via `addLineDouble(...)` (wide style) and `addLineSingle(...)` (compact / standard style).
  - Replaced player line allocation `local newText = {}` with static table reuse: `wipe(pooledPlayerText); local newText = pooledPlayerText`.
  - Eliminated all `unpack(v)` calls in tooltip line rendering, switching to direct index access (`v[1]`, `v[2]`, ...).
  - Validated zero GC table generation on repeated mouseover scans via standalone test harness.

- **Mouse Anchor Idle CPU Gating:**
  - Added early-return check `(not TacoTipConfig.anchor_mouse or not GameTooltip or not GameTooltip:IsShown())` to `TacoTipMouseAnchor`'s `OnUpdate` handler.
  - Halts 144–240Hz cursor position queries, UI scale division, and point mutations when tooltips are hidden.

### Visual & Layout Polish - 0.7.7

- **Dynamic 3D Portrait Screen-Edge Flipping:**
  - During `ApplyTooltipAppearance`, dynamically calculates tooltip right boundary against screen width (`UIParent:GetRight()` / `_G["GetScreenWidth"]()`).
  - When the actual tooltip itself touches or exceeds the right screen edge (`tooltipRight >= screenWidth`), the portrait flips to the left side (`TOPRIGHT -> TOPLEFT, -8, 0`).

- **Extended Non-Unit Visual Clearing:**
  - Registered `ItemRefShoppingTooltip1`, `ItemRefShoppingTooltip2`, `WorldMapCompareTooltip1`, and `WorldMapCompareTooltip2` into `registerTooltipVisualClearing` so comparison tooltips cleanly clear any inherited unit state.

- **Padding Cleanup Fallback:**
  - Added `elseif (tooltip.SetPadding) then tooltip:SetPadding(0, 0, 0, 0) end` fallback to `clearTooltipVisuals` for clients lacking `ClearPadding()`.

### Testing & Verification - 0.7.7

- **Static Analysis:**
  - Zero warnings, zero errors in `luacheck .` across all 42 files.

## [0.7.6] - 2026-09-13

### Visual & Layout - 0.7.6

- **3D Character Portrait Resizing (3:4 Aspect Ratio):**
  - Increased base 3D portrait dimensions in `main.lua` from `60x80` to `72x96` (+20% size increase).
  - Maintained an exact 3:4 aspect ratio (`72 / 96 = 0.75`), providing clean, non-fractional integer pixel scaling across all slider steps: 50% (`36x48`), 100% (`72x96`), 150% (`108x144`), and 200% (`144x192`).
  - Added unit test coverage in `TacoTip_Tests.lua` (`Portrait:DefaultSizeIs34Ratio` and `Portrait:ScaledSizeKeepsRatio`).
- **Friendly Player Level Color:**
  - Friendly player level numbers render in clean white text (`|cFFFFFFFF<Level>|r`), cleanly differentiating friendly units from hostile difficulty-colored units.

### Performance & Memory Optimization - 0.7.6

- **Zero-Allocation Hover Pipeline:**
  - Mouseover unit tooltips now use static pooled buffer tables (`pooledLinesToAdd` and `pooledTooltipText`) in `main.lua`, completely eliminating transient table creation and garbage-collection churn during rapid mouseovers.
  - Refactored item score calculations in `gearscore.lua` (`scoreFromItemValues`) to consume scalar returns directly instead of wrapping `GetItemInfo(...)` in intermediate tables.
- **SharedMedia Resolution Caching:**
  - Implemented a lazy caching layer in `options.lua` for resolved media paths (backgrounds, borders, statusbars, fonts).
  - Heavy $O(N \log N)$ sorting and formatting of dropdown choices are now avoided on every unit mouseover, reducing media resolution to instant $O(1)$ table reads.
  - Caches are automatically invalidated via `TT:InvalidateResolvedMediaCache()` on config updates (`ApplyConfigDefaults`, `modernGetConfig`) and when new media is dynamically registered by `LibSharedMedia-3.0`.
  - Added regression test `Borders:MediaResolutionCaching` in `TacoTip_Tests.lua`.
- **PowerBar Combat Event Hardening:**
  - Gated `TacoTipPowerBar:OnEvent` with `if not self:IsShown() then return end`, preventing combat power updates from triggering unit resolution while the power bar is hidden.
  - Power bar event listeners are dynamically unregistered when the update ticker stops.
- **Tooltip Lifecycle Hook Deduplication:**
  - Removed duplicate `GameTooltip` `OnTooltipCleared` and `OnHide` hooks in `main.lua` that were already managed cleanly by `registerTooltipVisualClearing`.
- **Target Event Gating:**
  - `UNIT_TARGET` event processing in `main.lua` now verifies `GameTooltip and GameTooltip:IsShown() and TacoTipConfig.show_target` before resolving unit references or evaluating unit equivalence.
- **3D Portrait 20Hz Throttling:**
  - Throttled 3D portrait model `OnUpdate` alpha synchronization to 20Hz (0.05s) using parent alpha caching (`self:GetParent():GetAlpha()`).

### Testing & Verification - 0.7.6

- Passed `luacheck .` with 0 warnings and 0 errors across all 21 files.
- Verified syntax with `luac -p` across `main.lua`, `options.lua`, `gearscore.lua`, and `TacoTip_Tests.lua`.

## [0.7.5] - 2026-09-11

### Fixed - 0.7.5

- **Dual-Spec Active/Inactive Rendering:**
  - The inactive spec line was previously wrapped in an outer dim code at the call sites, but `formatSpecializationText` emits its own class-color code internally; WoW color codes do not nest, and font strings do not support alpha dimming codes.
  - The formatter now colors the inactive spec name in lowest GearScore quality grey (`0.50, 0.50, 0.50` / `GRAY_FONT_COLOR`), while the active spec name keeps its class color. Talent numbers `[x/x/x]` are placed outside the colored name run, rendering in clean white text for both specs.
  - Compact mode's invisible zero-alpha `|c00000000%s: |r` alignment prefix is preserved; the icon keeps full alpha so spec icons stay readable.
- **Options Config Integrity:**
  - The root options page no longer force-writes `TacoTipConfig.show_achievement_points = false` on non-Wrath clients; the saved preference survives a later WotLK session. Display remains gated on `CI:IsWotlk()` in the tooltip render path, so a stale saved value can never display anything on Era/TBC.

### Performance - 0.7.5

- **`MODIFIER_STATE_CHANGED` Gate:** modifier key press/release no longer triggers a full `GameTooltip:SetUnit` rebuild unless a player tooltip is actually shown and the configured `tip_style` reads the shift key (styles 2/4). Styles 1/3/5 and hidden tooltips now skip the rebuild entirely.
- **Mouse-Anchor `OnUpdate` Idle Skip:** the persistent mouse-anchor frame skips cursor reads/repositioning while `anchor_mouse` is disabled instead of running every frame for the whole session.
- **Item Hook Feature Gate:** with both `show_item_level` and `show_gs_items` disabled, the item tooltip hook skips `IsEquippableItem`/`GetItemInfo` and the pending-load registration entirely.
- **Pawn Scale-Name Reuse:** `TT_PAWN:GetScore` builds the `"Classic":CLASS<spec>` scale name once per scoring pass and threads it through `TT_PAWN:GetItemScore`, instead of rebuilding the concat for each of up to 18 equipped slots.

### Testing - 0.7.5

- New WoWUnit test `Stats:DualSpecDimRendering`: dim output must contain lowest GearScore quality grey (`0.50, 0.50, 0.50` / `|cff7f7f7f` / `|cff808080`) on the spec name, the `|r` code must close before the `[x/x/x]` points run (leaving talent numbers clean white), color codes must be balanced (no nesting leaks), and the non-dim (active) variant must carry class color without grey. Run with `/tttest`.

## [0.7.4] - 2026-09-10

### Fixed - 0.7.4

- **Per-Tooltip Lifecycle State:**
  - Every deferred timer (delayed tooltip, class border re-apply, defensive border re-apply, instant fade) previously lived in a single module-level local shared by ALL hooked tooltips (`GameTooltip`, `ShoppingTooltip1/2`, `ItemRefTooltip`, `WorldMapTooltip`, `SmallTextTooltip`). Clearing or hiding one tooltip could cancel or stale-out another tooltip's pending appearance work.
  - All timers, the generation counter and the pending item-load cancel handle now live in a per-tooltip state table on the frame itself (`getTooltipState`), and each timer self-clears its slot on fire.
  - Power-bar cleanup is now scoped to `GameTooltip` only: clearing the world-map or shopping tooltip no longer hides the power bar under the main tooltip.
- **Uncached Item Retry:**
  - Hovering an equippable item whose data Blizzard has not cached yet now requests item data (`Item:CreateFromItemLink` + `ContinueWithCancelOnItemLoad`) and repaints the tooltip when the load lands; the continuation is stored per tooltip and cancelled on clear/hide so a stale load can never repaint a different item.
  - Clients without the C_Item object API fall back to `C_Item.RequestLoadItemDataByID` for the data request.
- **Duplicate Equipped Items:**
  - Two identical equipped item ids (e.g. matching rings) previously registered the id twice; the first load callback drained both pending entries and the second slot's callback completed the cycle prematurely. Registration is now deduped per id at all four callback sites (gearscore main-hand/off-hand/body, pawn).

### Testing - 0.7.4

- New WoWUnit group `TacoTip-Lifecycle`: per-tooltip state isolation (clearing a probe tooltip never touches `GameTooltip`'s state), duplicate-item single-pending-registration assertion, and nil-safe clear. Run with `/tttest`.

## [0.7.3] - 2026-08-27

### Performance - 0.7.3

- **Single `GetItemInfo` Fetch Per Item Tooltip:**
  - Item tooltips previously called `GetItemInfo` once for the ilvl line, again inside `TT_GS:GetItemScore`, and a third time inside `TT_GS:GetItemHunterScore` on every hover of every equippable item.
  - Added `TT_GS:GetItemScoreFromInfo(info)` which scores from an already-fetched `GetItemInfo` result table; the item tooltip hook now performs exactly one fetch shared by ilvl, GearScore and HunterScore.
  - `TT_GS:GetItemScore(link)` and `TT_GS:GetItemHunterScore(link, info?)` remain fully backward compatible for frame overlays and other callers.
- **Memoized `ItemMixin` Allocation in `LibClassicInspector`:**
  - `GetInventoryItemMixin` allocated a fresh `ItemMixin` per slot per call (~19 allocations on every player hover from GearScore + Pawn scoring loops).
  - Mixins are now memoized per cached user and slot, keyed by item identity so a gear change in the same slot rebuilds its mixin instead of returning stale data. Entries die with their cache user on FIFO eviction.
- **Overlay Offset Clamping:**
  - Typed offset edit boxes now clamp keyboard-entered values to the ±300 slider range (`setOffsetValue`), so a typo cannot push an overlay permanently offscreen.
  - `SafeSanitizeConfig` repairs out-of-range or corrupt saved offsets (including `"corrupt"` strings, NaN and ±infinity) back to defaults on every load.

### Fixed - 0.7.3

- **Options OnShow Lifecycle (order-dependent overwrite):**
  - Page builders no longer assign `panel:SetScript("OnShow")`; the load-tail safeCall-wrapped handlers own that slot and already invoke `panel:Refresh()`. Assigning inside the builder silently replaced them after first build.
- **Library Hardening (`LibClassicInspector`):**
  - `GetTalentInfoByClass` returns nil past a tab's real talent count instead of raising "attempt to index a nil value"; the same guard was applied to both the player and inspected-unit branches of `GetTalentInfo`.
  - The event dispatcher logs-and-continues via `geterrorhandler()` when a registered event has no matching handler method, keeping the frame alive instead of erroring on first fire.
  - Achievement validity probes use Blizzard's documented 14th `isStatistic` return instead of the undocumented 15th return that classic clients do not provide.
  - `addCacheUser` now returns the created user table so first-use callers (e.g. `GetInventoryItemMixin`) never operate on a nil cache entry.

### Documentation & Testing - 0.7.3

- **Accurate Backdrop Comments:** Corrected stale "pre-2.5.3" notes across `main.lua` and memory bank — NineSlice-equipped tooltips are verified present on all supported clients (Classic Era, TBC Anniversary, Wrath); backdrop handling is runtime-detected via `tooltip.NineSlice`, not build-gated.
- **New Regression Tests:** Added `SanitizeOffsetBounds` (offset repair incl. NaN/infinity) and `GetItemScoreFromInfoMatchesLink` (single-fetch path produces identical scoring to the link path) WoWUnit tests — run with `/tttest`.
- **Version metadata bumped to `0.7.3`** across `TacoTip.toc`, `main.lua`, `options.lua`, `README.md`, `CHANGELOG.md`, `AGENTS.md`, and memory bank.

## [0.7.2] - 2026-08-21

### Fixed - 0.7.2

- **TBC Classic Anniversary Dual-Spec Not Showing:**
  - Resolved an issue where `hasDualSpec` was evaluated only once at file-load time in `LibClassicInspector.lua`. On TBC Anniversary (`clientBuildMajor == 2`), `isWotlk` is false and `GetNumTalentGroups()` at addon boot returned 1, permanently setting `hasDualSpec = false` for the entire game session and hard-blocking secondary spec queries (`group == 2`).
  - Updated `hasDualSpec` to recognize TBC Classic Anniversary (`isTBC`), WotLK (`isWotlk`), and `C_SpecializationInfo` / `GetNumTalentGroups` (Season of Discovery & Classic Era).
- **`C_SpecializationInfo.GetTalentInfo` FrameXML Fallback:**
  - Added wrapper fallback around `GetTalentInfo` to construct `C_SpecializationInfo.GetTalentInfo` query structs when `_G.GetTalentInfo` deprecation fallbacks are disabled on TBC Anniversary and Classic Era/SoD clients.
- **Dynamic Talent Group Events:**
  - Registered `PLAYER_TALENT_UPDATE` and `ACTIVE_TALENT_GROUP_CHANGED` events on all dual-spec capable clients (TBC Anniversary, WotLK, and SoD/Classic Era) so spec switches and talent reallocations immediately trigger tooltip updates.
- **Talent Point Summation Nil-Safety:**
  - Added `or 0` guards to `select(5, GetTalentInfo(...))` across `GetSpecialization`, `GetTalentPoints`, `sendInfo`, and `GetTalentRanksTable` to prevent arithmetic nil errors on sparse talent trees.
- **Dual-Spec Talent Alignment in Compact/Standard Tooltip Mode:**
  - Resolved a visual misalignment where the secondary talent spec line was offset due to 6 hardcoded space characters. Replaced fixed spaces with an invisible zero-alpha prefix (`|c00000000%s:|r`) matching the exact pixel width of localized `Talents:`, guaranteeing pixel-perfect vertical alignment between primary and secondary talent icons across all fonts and languages.
- **3D Portrait Real-Time Alpha Fade Synchronization:**
  - Added continuous `OnUpdate` alpha tracking on `tooltip.TacoTipPortrait3D` that matches `GameTooltip:GetAlpha()` on every render frame, ensuring the 3D player portrait smoothly fades out in lockstep with the tooltip backdrop/text instead of abruptly vanishing.
- **3D Portrait Lifecycle & Reset Hardening:**
  - Added explicit `ClearModel()` and `SetAlpha(1.0)` restoration inside `clearTooltipVisuals` so 3D model meshes are purged from GPU memory and reset to full opacity when transitioning between units, map POIs, action bar spells, and UI elements.
- **Guarded `UPDATE_MOUSEOVER_UNIT` Event:**
  - Explicitly gated the `UPDATE_MOUSEOVER_UNIT` hide handler with `if (TacoTipConfig.instant_fade)` to ensure Blizzard's native smooth fade-out is never cut short when Instant Fade is disabled.

### Removed - 0.7.2

- **Excised Dead Elite Frame References:**
  - Removed orphaned `if (tooltip.TacoTipEliteFrame) then tooltip.TacoTipEliteFrame:Hide() end` checks and stale comments from `main.lua` following the removal of non-functional Retail atlas overlays in v0.6.1.

### Documentation & Localization - 0.7.2

- **100% Localization Parity:** Verified all 11 language locale files (`enUS`, `deDE`, `esES`, `esMX`, `frFR`, `itIT`, `koKR`, `ptBR`, `ruRU`, `zhCN`, `zhTW`) have 100% key coverage (261/261 keys per locale) and validated all format specifiers (`%s`, `%d`).
- **Static Analysis & Testing:** 0 warnings / 0 errors in `luacheck .` across all 21 files, with comprehensive test verification for dual-spec resolution and portrait alpha sync.
- **Version metadata bumped to `0.7.2`** across `TacoTip.toc`, `main.lua`, `options.lua`, `README.md`, `CHANGELOG.md`, `AGENTS.md`, and memory bank.

## [0.7.1] - 2026-08-20

### Removed - 0.7.1

- **Excised obsolete floating options preview tooltip and dead code:**
  - Removed `modernShowExampleTooltip`, `previewPane`, `previewHealthBar`, `previewPowerBar`, `previewAnchor`, `positionPreviewTopRight`, `clearPreviewVisuals`, and all unneeded preview keys from `modernOptionsState` in `options.lua`.
  - Removed `TT:ApplyPreviewClassOverride` in `main.lua`.
  - Removed over 40 redundant `modernShowExampleTooltip()` calls across widget change callbacks in `options.lua` — option toggles now cleanly apply directly to configuration with zero unnecessary UI overhead.
  - Removed dead preview string entries (`OPTIONS_PREVIEW_HEADER`, `OPTIONS_PREVIEW_HELP`) and updated options descriptions across all 11 locale files (`enUS`, `deDE`, `esES`, `esMX`, `frFR`, `itIT`, `koKR`, `ptBR`, `ruRU`, `zhCN`, `zhTW`).

### Changed - 0.7.1

- **Options UI Performance & Cleanliness:**
  - Streamlined `TT.RefreshOptionsUI`, `onPageShow`, `onOptionsFrameShow`, and page show handlers in `options.lua` to focus purely on building controls and syncing config state.
  - Full static analysis pass: `luacheck .` reports 0 warnings and 0 errors across all 21 files.
- **Version metadata bumped to `0.7.1`** across `TacoTip.toc`, `main.lua`, `options.lua`, `README.md`, `CHANGELOG.md`, and `AGENTS.md`.

## [0.7.0] - 2026-08-14

### Fixed - 0.7.0

- **Minimap & World Map tooltip flickering resolved:** Fixed rapid tooltip flickering when hovering over Minimap tracking icons, quest pins, trainer markers, resource nodes, and World Map pins across Classic Era, Season of Discovery, and TBC Classic Anniversary.
  - **Mouse interaction disabled on `GameTooltip`:** Replaced all `tooltip:EnableMouse(true)` calls inside `GameTooltip_SetDefaultAnchor` with `tooltip:EnableMouse(false)`. Prevents `GameTooltip` from capturing mouse focus and triggering continuous `OnLeave`/`OnEnter` event cycles with underlying map frames.
  - **Caller frame ownership preserved:** Removed destructive `tooltip:SetOwner(TacoTipMouseAnchor, ...)` and `tooltip:SetOwner(TacoTipDragButton, ...)` overrides from `GameTooltip_SetDefaultAnchor`. Preserving the original owner (e.g. `Minimap`, `WorldMapFrame`, `ActionButton`) prevents Blizzard's `UnitPositionFrameMixin:UpdateTooltips` and `GameTooltip_OnUpdate` from detecting an ownership mismatch and resetting/recreating tooltips every single frame.
  - **`UPDATE_MOUSEOVER_UNIT` guard:** Guarded tooltip hiding on `UPDATE_MOUSEOVER_UNIT` to strictly check `GameTooltip:IsUnit("mouseover")` so non-unit tooltips (Minimap POIs, World Map icons, spells, items) are never falsely cleared or hidden during mouse movements.
  - **`resolveTooltipUnit` strict check:** Enhanced `resolveTooltipUnit` to validate `tooltip:IsUnit(unit)` before returning unit tokens, ensuring stale unit data from prior player/NPC hovers is not returned when `GameTooltip` is displaying map POIs or other non-unit content.
- **Version metadata bumped to `0.7.0`** across `TacoTip.toc`, `main.lua`, `options.lua`, `README.md`, `CHANGELOG.md`, and `AGENTS.md`.
- **Test suite expansion:** Added `TT-MinimapAndAnchor` test group to `TacoTip_Tests.lua` verifying owner preservation and mouse disablement on `GameTooltip_SetDefaultAnchor`.

### Changed - 0.7.0

- **Tooltip border edge size default now `14px`:** `tooltip_border_edge_size` default changed from `18` to `14` (range 4–48 unchanged). Slider help text and `enUS` locale updated; the options refresh fallback now reads `TT:GetDefaults()` instead of a stale literal so defaults cannot drift again.
- **Deferred tooltip timers are now always cancellable `C_Timer.NewTimer`:** Removed the `C_Timer.After` fallback branches in the class-tinted border deferral (`onTooltipShow`) and the defensive backdrop re-apply (`ApplyTooltipAppearance`). Every deferred tooltip timer is now a cancellable handle owned by `borderDeferTimer` / `classBorderDeferTimer`, explicitly cancelled on every clear/show so a stale follow-up can never fire on a later non-unit tooltip or after rapid hover churn. The fade-out timer (`fadeTimer`) is now cancelled in the same central `clearTooltipVisuals` path, so all four deferred tooltip timers (`delayedTooltipTimer`, `borderDeferTimer`, `classBorderDeferTimer`, `fadeTimer`) reset cleanly together on every clear/show.

## [0.6.9] - 2026-08-13

### Added - 0.6.9

- **Shaman Blue default class color toggle on Classic Era / SoD:** Added `shaman_blue` setting (default `true`) so Shamans display in Blue (`#0070DE`) on Classic Era and Season of Discovery by default instead of Classic pink (`#F58CBA`). A "Shaman Blue" checkbox toggle is available on the Tooltips options page to switch back to pink if desired.
- **Details BarBorders in built-in border choices:** Added `Details BarBorder 1`, `Details BarBorder 2`, and `Details BarBorder 3` (`Interface\AddOns\Details\images\border_3`) to built-in border texture options so they are selectable even without Details! installed.
- **Custom scrollable media dropdown selector UI (Image 2 style):** Upgraded options panel dropdowns to use a custom scrollable modal popup selector frame (`TacoTipMediaPickerFrame`). Includes texture strip previews for statusbar, border, and background choices, sharp white text with black drop shadows, scrollbar, mouse-wheel scrolling, checkmarks on active selections, and auto-dismiss on click outside or ESC.
- **Real 9-slice border previews in media picker:** Border choices in `TacoTipMediaPickerFrame` render their real 9-slice sliced edge frames around each row item in the selection list.
- **Cross-client `BackdropTemplate` safety:** Guarded modal picker frame creation with `BackdropTemplateMixin and "BackdropTemplate" or nil` so pre-9.0 and custom client builds load without template lookup errors.

### Changed - 0.6.9

- **Version metadata bumped to `0.6.9`** across `TacoTip.toc`, `main.lua`, `options.lua`, `README.md`, `CHANGELOG.md`, and `AGENTS.md`.
- **Enlarged 3D portrait dimensions:** Increased base 3D player model portrait dimensions from 42×56 to **60×80** (width 60px, height 80px) to match full multi-line tooltip height while maintaining an exact 3:4 aspect ratio.
- **Default tooltip border texture:** Set default border texture to `Tooltip enlarged` with 20px edge size default. Registered `Tooltip enlarged` in built-in border choices and updated resolution matcher so SharedMedia border entries match by name as well as file path.
- **Default tooltip border thickness:** Updated default border edge size to 20px.
- **Updated Default Feature Toggles:** Enabled Guild Rank display (`show_guild_rank = true`) with `<Guild> Rank` format (`guild_rank_alt_style = true`), Item GearScore (`show_gs_items = true`), Faction Icon (`show_team = true`), and Group Role Icon (`show_role_icon = true`) by default.
- **100% Locale Parity & Native Translations:** Audited all 10 non-English locale files (`deDE`, `esES`, `esMX`, `frFR`, `itIT`, `koKR`, `ptBR`, `ruRU`, `zhCN`, `zhTW`) against `enUS.lua`. Added native translations for all 3D portrait, shaman blue, offset slider/edit, and rank keys so no option string remains untranslated.

### Fixed - 0.6.9

- **Live drag tooltip follow fix:** Fixed issue where dragging the green dot after resetting to defaults did not move the tooltip because `OnUpdate` returned early when `custom_pos` was uninitialized. The tooltip now continuously follows the green drag button on screen during drag.
- **Tooltip mover button state after default reset:** Fixed issue where clicking "Open Tooltip Mover" on the Positioning options subpage after resetting to defaults did nothing because the mover button was set to disabled. The mover button is now kept enabled so clicking it at any time automatically activates custom position mode and displays the green drag handle.
- **Test suite `GameTooltip.GetUnit` mock cleanup:** Replaced direct `GameTooltip["GetUnit"]` assignments in `TacoTip_Tests.lua` with framework `Replace("GameTooltip.GetUnit", ...)` and automatic teardown restoration.
- **Zero-warning audit:** Verified `luacheck .` produces 0 warnings across all production runtime files (`main.lua`, `options.lua`, `textures.lua`, `gearscore.lua`, `pawn.lua`, `Locale/*.lua`, and `TacoTip_Tests.lua`).

## [0.6.8] - 2026-08-11

### Removed - 0.6.8

- **GearScore change indicator (`show_gs_delta`):** The `+N`/`▼N` delta that appeared next to GearScore when a unit's score changed since the last time you saw them has been removed entirely. It relied on a `TacoTipGSHistory` global that tracked GearScore per GUID across sessions, and was the root cause of tooltip corruption/bugs on gear updates. Removed: the `show_gs_delta` config default and boolean-key sanitizer entry, the options checkbox + `SetChecked` wiring, the `TacoTipGSHistory` global, the delta computation block in `onTooltipSetUnit`, and the `OPTIONS_SHOW_GS_DELTA` / `OPTIONS_SHOW_GS_DELTA_DESC` locale strings from all 10 locale files. GearScore itself (and iLvl) is unaffected.

### Changed - 0.6.8

- Version metadata bumped to `0.6.8` in `TacoTip.toc`, `main.lua`, and `options.lua`.
- **Tooltips options page live Shift-expand preview fixed (prism-full F1):** The `MODIFIER_STATE_CHANGED` listener that drives the hybrid-style live expand-on-Shift preview was registered only inside the build-time page `OnShow` closure, so it did not activate until the page's second open. It is now registered unconditionally in the root `optionsPages.tooltips:OnShow` handler, active on the first open.
- **`REALM` i18n leak fixed (prism-full F2):** `options.lua` read `L["REALM"] or "Realm"` but only `enUS`/`deDE` defined the uppercase `REALM` key — non-English clients fell back to the literal English "Realm" in the realm line. Added translated `["REALM"]` entries to all 10 non-English locale files (deDE, esES, esMX, frFR, itIT, koKR, ptBR, ruRU, zhCN, zhTW), matching each locale's existing `Realm` translation.

### Fixed - 0.6.8

- **Non-unit tooltip bleed-through & flicker (CRITICAL):** `C_Timer.After` does not return a cancellable handle in the WoW API, so `cancelDeferredAppearance()` previously failed to cancel the two pending deferred border re-apply timers (`borderDeferTimer`, `classBorderDeferTimer`). Rapid tooltip recycling over map/minimap POIs, Questie objective icons, or action-bar buttons could let a stale class-colored border paint one frame late — the reported flicker. Both timers now use `C_Timer.NewTimer` (cancellable) with the existing generation-counter bailout, and are cancelled on every `clearTooltipVisuals` call.
- **`OnTooltipCleared` hook on GameTooltip:** Added an explicit `GameTooltip:HookScript("OnTooltipCleared")` handler so `clearTooltipVisuals` runs whenever lines are cleared on `GameTooltip`.
- **`TT.clearTooltipVisuals` exposed:** The central visual cleanser is now available on the `TT` namespace so the test suite can invoke it deterministically between transitions.
- **Title-strip nil guard:** `onTooltipSetUnit` now guards `string.find(text[1], name, 1, true)` against a nil `UnitName` return, preventing a Lua error on synthetic or unnamed units.
- **Line-2 early-return scoped to player units:** The `text[2]` early-return in `onTooltipSetUnit` is now gated on `UnitIsPlayer(tooltipUnit)`, so non-player units with a single line still proceed through the formatting path.
- **Test suite fixed (all WoWUnit tests green):** `DefaultsHaveKeys` / `ConfigDefaultsShowGuild` now assert `guild_rank_alt_style` (boolean) instead of the removed `guild_rank_style` key; `ClassicEraBleedThrough` clears via `ClearLines()` + `TT.clearTooltipVisuals`, re-fetches the backdrop frame at every transition, rounds float RGB to 3 decimals, and uses `AreEqual(actual, expected)` ordering; `ClassicEraFallbackParsing` mocks `UnitIsPlayer` and `UnitName` for the synthetic `mouseover` unit.

## [0.6.7] - 2026-08-10

### Changed - 0.6.7

- Version metadata bumped to `0.6.7` in `TacoTip.toc`, `main.lua`, `options.lua`, `README.md`, and `CHANGELOG.md`.

### Fixed - 0.6.7

- **SoD / Classic Era dual-spec not showing (prism-full audit F1/F2/F3):** `LibClassicInspector` hardcoded `if (not isWotlk and group == 2) then return nil` in `GetSpecialization`, `GetTalentPoints`, and `GetTalentInfo`, and forced the active talent group to `1` on all non-WotLK clients. On SoD (interface `11508`, `clientBuildMajor == 1`) this made both inspected and self dual-spec data unreachable — a player with an empty primary tree and an active secondary spec saw **no specs at all**, and a player with points in the primary tree saw the **wrong (inactive) spec**. Introduced a `hasDualSpec` capability flag derived from `GetNumTalentGroups()` / `C_SpecializationInfo.GetNumSpecGroups(false)` (SoD reports >1), replaced every `isWotlk`-style dual-spec guard with it, routed active-group resolution through a new `GetActiveSpecGroupFor(isInspect)` helper using the always-present `C_SpecializationInfo.GetActiveSpecGroup` API (the legacy `GetActiveTalentGroup` global is deprecation-gated and may be absent at runtime), and fixed `cacheUserTalents` / `INSPECT_READY` to cache both spec groups on dual-spec clients so inspected players' secondaries render too. `main.lua`'s existing `spec1/spec2`/`active==2` presentation branch now receives real data and needs no change.
- **Test suite: merged SoD/Classic-Era bleed-through tests:** Consolidated the two separate `Borders:NoBleedToNonUnitTooltip` and `Borders:NoBleedToItemTooltip` cases into a single `Borders:ClassicEraBleedThrough` test that asserts no class-border bleed on player → Clear(), player → item, and player → spell transitions (the spell path was previously untested, per AGENTS.md "Non-Unit Visual Isolation"). Added `Stats:DualSpecGroup2Reachable` regression test asserting group-2 talent reads and the active-group resolver return valid values on all clients. The `ClassicEraBleedThrough` test was hardened to pin the base border colour to white and to assert the class border is actually applied before each transition, so it fails when a bleed exists rather than passing trivially.

## [0.6.6] - 2026-07-28

### Fixed - 0.6.6

- **Power bar ticker leak on GameTooltip hide:** The `startPowerBarTicker` update ticker was not cancelled in the `GameTooltip:OnHide` hook — only `cancelDelayedTooltip()` was called. The ticker continued firing after the tooltip hid, consuming CPU until the next `clearTooltipVisuals`. Added `stopPowerBarTicker()` call to the `GameTooltip:OnHide` handler.
- **PowerBarColor nil-table defence-in-depth:** Changed the guard from `power and PowerBarColor[power]` to `PowerBarColor and PowerBarColor[power]` at `main.lua:1196`. The previous guard only protected against nil `power` but not against a nil `PowerBarColor` global, which is a core Blizzard table present on all clients but not explicitly guarded.
- **Dead `guild_rank_style` config key removed:** The numeric `guild_rank_style` default and its migration validation were removed from `TT:GetDefaults()` and `SafeSanitizeConfig`. The options UI has used boolean `guild_rank_alt_style` since v0.6.x; the old key was a persistent migration artifact. A comment documents the removal for future maintainers.
- **Fade-out callback stacking replaced with cancellable timer:** The `CAfter(0, ...)` in `UPDATE_MOUSEOVER_UNIT` (instant-fade mode) stacked callbacks on rapid mouse moves — each event scheduled a new callback with no cancel path. Replaced with a `C_Timer.NewTimer` + `cancelFadeTimer()` pattern matching the existing `delayedTooltipTimer` architecture. At most one pending callback exists at any time, cancelled and re-scheduled on every mouseover event.
- **Classic Tooltip API Modernization:** Refactored line queries across `main.lua` to use Blizzard's native C++ methods `tooltip:GetLeftLine(i)` and `tooltip:GetRightLine(i)` via `TT.GetTooltipLeftLine` and `TT.GetTooltipRightLine`. Replaced legacy string concatenations (`_G["GameTooltipTextLeft"..i]`) with direct line getters while maintaining test mock fallback support.
- **Read-Before-Write Layout Optimization:** Added `tooltip:GetMinimumWidth()` check before calling `SetMinimumWidth(0)` in `TT:ApplyTooltipAppearance` to prevent unnecessary C++ layout recalculation passes.
- **Power Bar Padding Encapsulation:** Integrated `tooltip:SetPadding(0, 10, 0, 0)` when `TacoTipPowerBar` is shown and `tooltip:ClearPadding()` in `clearTooltipVisuals` so tooltip backdrops cleanly encapsulate status bars.
- **Screen Boundary Protection:** Applied `tooltip:SetClampRectInsets(0, 0, 15, 15)` in `ApplyTooltipAppearance` to keep long player tooltips 100% visible on screen without edge clipping.
- **Zero-Flicker Async Inspection Refresh:** Updated `TacoTip_GSCallback` to refresh via `GameTooltip:UpdateTooltip()` when available instead of re-calling `SetUnit`, eliminating tooltip position jump on async inspect updates.
- **Unnamed Tooltip Support:** Removed strict global frame name dependencies in `applyTooltipFonts` and `onTooltipSetUnit` line read loops, enabling full font styling and line formatting support for third-party or unnamed tooltip frames.
- **Test Suite Coverage:** Added `Modules:LineAccessGetters` and `Modules:AdvancedTooltipAPIs` unit tests in `TacoTip_Tests.lua` verifying native line getter delegation and advanced C++ API calls.
- **LibClassicInspector param-type-mismatch fix:** Fixed 11 false-positive Lua Language Server diagnostic warnings on `GetTalentInfo` calls by using a localized, annotated reference for the Classic WoW API parameter signature, and corrected the internal parameter mapping for `GetNumTalents`/`GetTalentInfo` inside `cacheUserTalents`.

### Changed - 0.6.6

- **GS Quality Colors Rewired to WoW Item Quality Colors:** Replaced the custom `GS_Quality` interpolation gradient (which produced teal/cyan/magenta) with fixed RGB values matching Blizzard's `ITEM_QUALITY_COLORS[0..6]`. Color tiers now accurately reflect WoW item quality: gray → white → green → blue → purple → orange → red.
- **New 7th Red Tier Added:** Expanded `MAX_SCORE` from `BRACKET_SIZE*6-1` to `BRACKET_SIZE*7`, adding an Artifact (red) tier at the top end of the bracket. Requires ~iLvl 93+ full epic set to reach — unobtainable on Classic Era, accessible to SoD's best-geared characters. `GetQuality` now iterates 7 brackets instead of 6.

### Fixed - 0.6.6 (SoD / Classic Era dual-spec)

- **SoD / Classic Era dual-spec not showing (prism-full audit F1/F2/F3):** `LibClassicInspector` hardcoded `if (not isWotlk and group == 2) then return nil` in `GetSpecialization`, `GetTalentPoints`, and `GetTalentInfo`, and forced the active talent group to `1` on all non-WotLK clients. On SoD (interface `11508`, `clientBuildMajor == 1`) this made both inspected and self dual-spec data unreachable — a player with an empty primary tree and an active secondary spec saw **no specs at all**, and a player with points in the primary tree saw the **wrong (inactive) spec**. Introduced a `hasDualSpec` capability flag derived from `GetNumTalentGroups()` / `C_SpecializationInfo.GetNumSpecGroups(false)` (SoD reports >1), replaced every `isWotlk`-only dual-spec guard with it, routed active-group resolution through a new `GetActiveSpecGroupFor(isInspect)` helper using the always-present `C_SpecializationInfo.GetActiveSpecGroup` API (the legacy `GetActiveTalentGroup` global is deprecation-gated and may be absent at runtime), and fixed `cacheUserTalents` / `INSPECT_READY` to cache both spec groups on dual-spec clients so inspected players' secondaries render too. `main.lua`'s existing `spec1/spec2`/`active==2` presentation branch now receives real data and needs no change.
- **Test suite: merged SoD/Classic-Era bleed-through tests:** Consolidated the two separate `Borders:NoBleedToNonUnitTooltip` and `Borders:NoBleedToItemTooltip` cases into a single `Borders:ClassicEraBleedThrough` test that asserts no class-border bleed on player → Clear(), player → item, and player → spell transitions (the spell path was previously untested, per AGENTS.md "Non-Unit Visual Isolation"). Added `Stats:DualSpecGroup2Reachable` regression test asserting group-2 talent reads and the active-group resolver return valid values on all clients.

## [0.6.5] - 2026-07-26

### Fixed - 0.6.5

- **Automatic Player Inspection Trigger**: Added `pcall(CI.DoInspect, CI, tooltipUnit)` when hovering over player units. This automatically triggers `LibClassicInspector` to query talents and gear score for other players on mouseover, firing `"TALENTS_READY"` to display their specialization (`Talents: SpecName [XX/XX/XX]`) without requiring manual inspect window interaction.
- **Font Color Un-Bleeding & Scoping**: Wrapped static label prefixes (`Level`, `GearScore:`, `iLvl:`, `Target:`) in explicit white inline color codes (`|cFFFFFFFF`). This prevents Blizzard's `GameTooltip:AddLine` font defaults from applying gold or GearScore quality colors to static text labels.
- **Friendly Level Number Formatting**: Updated `getHostileDifficultyColor` to return `nil` for friendly player units (`not UnitCanAttack("player", unit)`). Friendly level numbers now render in clean white text (`|cFFFFFFFF`), reserving quest/mob difficulty colors strictly for hostile or attackable targets.
- **Non-Unit Tooltip Visual Isolation & Cleansing**: Hardened `clearTooltipGuildLine` and `clearTooltipLevelColorLine` with nil-safe `GetName` checks (`tooltip.GetName and tooltip:GetName()`). `clearTooltipVisuals` purges all unit-specific overlays (class borders, 2D/3D portraits, elite frames, power bars, guild/level line indexes) immediately on every show/clear transition path across `GameTooltip`, `ItemRefTooltip`, `ShoppingTooltip`, and `WorldMapTooltip`.

## [0.6.4] - 2026-07-26

### Fixed - 0.6.4

- **Guild Fallback Parser Regex Update**: Updated fallback pattern matching from `^<(.+)>$` to `^<([^>]+)>%s*(.*)$`. This allows TacoTip to extract both the guild name and rank from 2-line client tooltips (such as `<Mambas Milkers> Initiate`) when `GetGuildInfo` is restricted on Era/SoD.
- **Removed Gold Rank Color**: Removed `HIGHLIGHT_FONT_COLOR` (`|cffffd200` gold) rank formatting. Guild ranks now display in clean white text following the green class-colored guild tag (`<GuildName> Rank`).
- **Level Line Placement (Guilded & Un-guilded)**: Hardened level line placement to target line 3 for guilded players and line 2 for un-guilded players dynamically. Also added a `localizedRace` fallback guard so `Level <N> <Class>` always renders even if race data is temporarily missing.
- **API Warning**: Fixed `UnitIsSameServer` signature call to pass 1 argument instead of 2.

## [0.6.3] - 2026-07-25

### Fixed - 0.6.3

- **Level color bleed-through on recycled tooltips:** `colorizeUnitLevelLine` applied difficulty-colored level text to unit tooltips but had no cleanup in `clearTooltipVisuals`, causing colored text to persist on the shared GameTooltip when recycled for non-unit content (items, spells, map POIs). Added `clearTooltipLevelColorLine` which stores the line index on the tooltip frame during colorization and resets that font string during cleanup, matching the existing pattern used for guild lines and class-color borders.
- **Hostile-level color `UnitCanAttack` gate blocking friendly players:** `getHostileDifficultyColor` required `UnitCanAttack("player", unit)` which returns `false` for same-faction players, preventing their level numbers from getting difficulty colors. Removed the `UnitCanAttack` check — `GetQuestDifficultyColor` works for any unit's level regardless of hostility, so all players (friendly, enemy) and NPCs now get appropriate difficulty coloring.
- **Level line hardcoded to index 2, missing guilded players:** The level colorization assumed the level text was always on tooltip line 2. For players in guilds, line 2 contains `<Guild Name>` and the level text is on line 3. Added dynamic level line detection: checks if `text[2]` looks like a guild tag (`<...>`) and targets line 3 instead, with guards for missing or double-guild-tag edge cases.
- **Level/race/class line missing for guilded players on SoD/Classic Era:** On SoD (interface 11509) the Blizzard client does not emit a `"Level 60 Orc Warrior"` line for players in guilds — only name + `<GuildName>` appear. A previous attempt to add a fallback (commit `8c65ecc`) checked for the level line *after* `colorizeUnitLevelLine` had inserted color codes, so the `^Level %d+` pattern never matched and the fallback fired on every player (creating duplicate lines on TBC/Wrath). Fixed by snapshotting whether the level line exists **before** colorization modifies the text, and only re-deriving from `UnitLevel`/`UnitRace`/`UnitClass` when the line was genuinely absent from the original tooltip.
- **ClassicEraFallbackParsing unit test always failing:** The test overrode `GameTooltip.GetUnit` to return `"TestPlayer", "mouseover"` but did not mock `UnitExists`. `resolveTooltipUnit` called `UnitExists("mouseover")` which returned false (no real unit is hovered during tests), causing `onTooltipSetUnit` to bail out before the guild-from-brackets fallback ran. Added a `Replace("UnitExists", ...)` mock that returns true for `"mouseover"` and delegates to the real `UnitExists` for all other tokens.

## [0.6.2] - 2026-07-19

### Fixed - 0.6.2

- **Guild names/ranks not working on Classic Era & Season of Discovery (SoD):** The legacy `GetGuildInfo` API is restricted to `"player"` on Classic Era clients, returning `nil` for other players and preventing TacoTip from formatting or hiding guild names. Added a fallback parser that extracts the guild name from the bracketed tooltip text (e.g. `<Guild Name>`) when `GetGuildInfo` returns `nil`.
- **Empty brackets (`<>`) displayed when guild name is disabled:** On Classic Era clients, the default game tooltip contains bracketed guild names. Using `string.gsub` to remove only the guild name left empty `<>` brackets on the tooltip. Rewrote to completely overwrite the guild line to an empty string `""` when the setting is disabled, hiding it cleanly.
- **Redundant parameter warning in `LibClassicInspector`:** The VS Code Lua Language Server flagged `CanInspect(unit, false)` at `LibClassicInspector.lua:L3328` with a redundant-parameter warning because the API annotation only declares one parameter. Removed the redundant `false` argument since `showError` is optional and defaults to `false`.
- **`GetTalentInfo` parameter-mapping bug:** Corrected a parameter-mapping bug at `LibClassicInspector.lua:L3619` where `group` (a number) was being passed as `isPet` (the 4th parameter) instead of the 5th parameter (`group`). This caused dual-spec player talent queries to look up pet talents.

### Added - 0.6.2

- **Unit tests for Classic Era fallback guild parsing:** Added the `Guild:ClassicEraFallbackParsing()` test function in [TacoTip_Tests.lua](file:///home/sam/TacoTip-Gearscore-TBC/TacoTip_Tests.lua) to assert fallback extraction of guild names from brackets and verify that the line is cleanly hidden when the guild display setting is disabled.

## [0.6.1] - 2026-07-17

### Fixed - 0.6.1

- **`tip_style` silently forced to 2 on every load:** `tip_style` was accidentally listed in the booleanKeys sanitizer table, causing any non-default value (1, 3, 4, 5) to be reset to the default (2) on every config load. Removed from booleanKeys; the numeric range checker now handles it correctly.
- **GetQuality green/blue channel swap:** The Blue variable read from the Green table coefficients and vice versa, producing incorrect GearScore text colors (intended amber → purple). Fixed to read from the correct table keys.
- **CAfter border bleed on non-unit tooltips:** The `onTooltipShow` non-unit branch reset the border to default but did not clear the cached `TacoTipPlayerClassColor`, allowing any pending CAfter deferred callback to re-apply a stale class-colored border onto map icons, UI elements, and spell tooltips. Added `clearTooltipPlayerClassColor()` before the border reset.
- **Power bar not cleaned during tooltip transitions:** `clearTooltipVisuals()` hid portraits and the elite frame but did not hide `TacoTipPowerBar` or stop its update ticker. Power bars could persist onto spell/item tooltips through the `OnTooltipSetSpell` path. Added power bar cleanup to `clearTooltipVisuals()`.
- **Pawn API call unprotected:** `PawnGetSingleValueFromItem` at `pawn.lua:57` was the only Pawn API call without a `pcall` wrapper, risking silent abort of all tooltip enhancements on error. Wrapped in pcall matching the existing pattern.
- **Portrait/visual leak on map quest and non-unit tooltips via OnShow (CRITICAL):** The `onTooltipShow` non-player branch (map POI icons, items, spells, UI hover-help) previously called only `clearTooltipPlayerClassColor` + `resetTooltipBorderToDefault`, leaving the portrait, 3D portrait, elite frame, and power bar from a previous player hover visible on the recycled tooltip. This is the reported "tooltip glitching on map quests" bug — `ClearLines()` (used by map POI tooltips) does not fire `OnTooltipCleared`, so TacoTip's full cleanup never triggered. Changed to call `clearTooltipVisuals(tooltip)` which hides all player-specific visuals and bumps the border-deferral generation.
- **CAfter border re-application race across tooltip transitions:** The deferred `C_Timer.After(0.05, ...)` callback in `ApplyTooltipAppearance` could fire after the tooltip was recycled for different content (item, map POI, spell), re-applying a stale class-colored border. Introduced a generation counter (`tooltip._borderDeferralGen`) bumped every time `clearTooltipVisuals` runs. All deferred callbacks now capture the generation at scheduling time and bail out if it has changed, so a CAfter from a previous player hover cannot contaminate a recycled tooltip.
- **`resetTooltipBorderToDefault` silent skip via texture guard:** `applyTooltipBorderOverlay` checks the border texture and returns early without setting the color when the texture is nil, empty, or `"Interface\None"`. This caused `resetTooltipBorderToDefault` to silently skip the border reset, leaving the stale class color intact. Rewrote to write directly to the backdrop frame via `SetBackdropBorderColor`, bypassing the texture guard entirely. The border is now always reset to the configured base color on every tooltip recycle.
- **Elite frame portrait border overlay removed:** The `show_elite_frame` feature (dragon/star atlas overlays on the portrait for elite/rare/boss NPCs) used `SetAtlas` with Retail/Wrath-only atlas names that do not exist on TBC Classic (2.5.5). `SetAtlas` failed silently, causing no visual output while also creating orphaned texture frames. Removed the feature entirely — texture creation, atlas calls, show/hide logic, config key, and options UI checkbox.
- **Test float precision (portrait size assertions):** `AreEqual(w, 42)` in `DefaultSizeIs34Ratio` failed because `f:GetWidth()` returns 42.000026702881 in WoW's coordinate system. Changed to `IsTrue(math.abs(w - 42) < 0.01, ...)` with descriptive format strings. Same fix for `ScaledSizeKeepsRatio` (62.999969482422 vs 63).
- **Test Interface metadata fallback:** `GetAddOnMetadata(addonName, "Interface")` could return nil on some clients when the test runs before the metadata is resolved. Added a constant fallback `"11508, 20505, 30405, 38001"` derived from the TOC file so the test is not subject to runtime metadata availability.
- **Test portability (border bleed):** The `NoBleedToNonUnitTooltip` and `NoBleedToItemTooltip` tests are now protected by the generation-counter mechanism, preventing the deferred CAfter from re-applying a class border mid-assertion.
- **Redundant `clearTooltipPlayerClassColor` removed:** The `onTooltipSetUnit` invalid-unit branch called both `clearTooltipPlayerClassColor` and `clearTooltipVisuals`, but the latter already calls the former. Removed the standalone call.

### Changed - 0.6.1

- **Config sanitizer:** Added range validation (0–1) for `tooltip_border_color_r/g/b` and `tooltip_background_color_r/g/b` color channels.
- **GetPlayerInfoByGUID:** Wrapped in pcall for defense-in-depth against future client API changes.

### Added - 0.6.1

- **Live power bar refresh:** Toggling `show_power_bar` in the options panel now immediately applies the change to the current tooltip via `TT:ApplyTooltipAppearance`, instead of waiting for the next mouseover.
- **Locale completion:** Added 22 missing keys to all 10 non-English locale files (deDE, esES, esMX, frFR, itIT, koKR, ptBR, ruRU, zhCN, zhTW) with translations. Added 4 missing keys to enUS.lua (`REALM`, `RANK_TITLE`, `OPTIONS_OFFSET_EDIT_DESC`, `OPTIONS_OFFSET_SLIDER_DESC`).

### Notes - 0.6.1

- Audit and fixes by Sisyphus (Orchestrator mode) — generation-counter CAfter cancellation, portrait/visual leak on OnShow non-unit tooltip path, test float tolerance, Interface metadata fallback, redundant-call cleanup.
- Addon maintainer: AcidBomb (Pilsung).

### Fixed - 0.6.0

- **Class-color border bleed-through on the shared GameTooltip:** Added `resetTooltipBorderToDefault()` and wired it into `clearTooltipVisuals` (fires on `OnTooltipCleared`), the non-player branch of `onTooltipShow`, and the `OnTooltipSetSpell` handler. A class-tinted border from a previous player hover can no longer persist onto non-unit tooltips (items, spells, buffs, map POI icons). Class borders apply only to real player units.

### Changed - 0.6.0

- **3D portrait default size 38×52 → 42×56 (exact 3:4, taller than wide, ~10% larger):** Base portrait dimensions at scale 1.0 now render a proper 3:4 frame instead of the old near-square 38×52.

### Added - 0.6.0

- **Standalone WoWUnit test suite (`TacoTip_Tests.lua`):** 8 test groups (Core, Config, Borders, Portrait, Guild, Stats, Mover, Modules) covering config defaults/sanitizer, border no-bleed, portrait ratio, GearScore/Pawn/talent nil-safety, mover sync, and module load. Runs via `/tttest` (alias `/tacotip`). Registered as an optional dependency in `TacoTip.toc` and added to the load list. The inline `TT._Test` stub previously appended to `main.lua` was removed.

### Notes - 0.6.0

- Version metadata bumped to `0.6.0` in `TacoTip.toc`, `main.lua`, and `options.lua`.
- Guild display is intentionally left unchanged: it works on TBC Anniversary (2.5.5–2.5.6) and remains broken on Classic Era / SoD (1.15.8) — known, not in scope this release.
- Assisted by: Hermes (MoA) — model: nous:tencent/hy3:free. Addon maintainer: AcidBomb (Pilsung).

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
  | --- | --- | --- |
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

## Unreleased

Universal-build inspection fixes and validation are recorded in [TacoTip_Forever/CHANGELOG.md](TacoTip_Forever/CHANGELOG.md#unreleased--inspect-queue-restoration). The Classic-only root build is unchanged.
