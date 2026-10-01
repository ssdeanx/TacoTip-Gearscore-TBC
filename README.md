# TacoTip - Gearscore & iLvl | TBC - Era - SoD |

TacoTip is a fully-featured tooltip enhancement and character inspection addon for World of Warcraft: Classic. It restores and polishes classic TacoTip features while adding modern UI and quality-of-life improvements for current players across Titanforge Wrath, TBC Anniversary, Classic Era, and Season of Discovery.

The original addon stopped working for TBC Classic, so this fork exists to make it work again, keep the useful features alive, and give the project room for future improvements.

> This description is written in Markdown for the CurseForge project page.

## 简体中文 / 繁體中文

- 支持客户端 / 支援用戶端：`1.15.9 (11509)`、`2.5.6 (20506)`、`3.80.1 (Titanforge)`
- 主要功能 / 主要功能：提示增强、GearScore、平均装等 / 平均物品等級、双天赋 / 雙專精、公会阶级 / 公會階級（`<Guild> Rank`）、放大 3D 角色头像、萨满职业蓝、角色与观察面板信息
- 打开设置 / 開啟設定：`/tacotip` 或 `/taco`
- 语言 / 語言：默认跟随客户端语言，全 11 种语言 100% 完整翻译（261/261 文本键）；主页面也提供语言下拉选单 / 下拉選單。

## At a glance

| Field | Details |
| --- | --- |
| Addon | TacoTip - Gearscore & iLvl TBC - Era - SoD |
| Status | Release-ready public build |
| Main purpose | Tooltip enhancement, inspection data, and character UI polish |
| Supported clients | Classic Era / Vanilla (`11509`), Season of Discovery (`11509`), TBC Classic Anniversary (`20506`), Titanforge (`38001`) |
| Installation | Copy the `TacoTip` folder into `Interface/AddOns` |
| Dependencies | Required libraries are bundled; Pawn support is optional |
| Public version | `v0.7.7` |

## Why TTacoTip - Gearscore & iLvl | TBC - Era - SoD | exists

| Original TacoTip | TacoTip - Gearscore & iLvl | TBC - Era - SoD | |
| --- | --- |
| Broke on TBC Classic | Restored to working order for Classic-era clients |
| Had no clear revival path | Clean fork with updated Blizzard API wiring |
| Was mainly useful historically | Kept alive for current Classic players |
| Left little room for growth | Built to support future polish and new features |

## What it does

| Area | Features |
| --- | --- |
| Tooltips | Full / Compact / Mini styles, hostile mob difficulty colors, target display, custom positioning, mouse anchoring, spell anchoring, portrait/font/theme controls |
| Player inspection data | GearScore, average item level, specialization names with per-spec icons, optional Pawn scores, glyph data, achievement data on Wrath |
| Character and inspect frames | GearScore and iLvl display with movable labels plus numeric X/Y offset controls |
| Quality of life | Instant fade, titles, guild names/ranks, PvP/team icons, class-tinted tooltip styling, saved anchor-aware mover reset |
| Integrations | Pawn support when installed, optional SharedMedia support for fonts/textures, plus bundled Classic inspection libraries |

## Current feature highlights

| Feature Highlight | Details |
| --- | --- |
| **Enlarged 3D Character Portrait** | Live 3D character portrait enlarged to **72×96** (width 72px, height 96px), maintaining an exact 3:4 aspect ratio with crisp integer pixel dimensions across all scale stops (50%–200%). |
| **`<Guild> Rank` Default Style** | Guild rank display enabled by default (`show_guild_rank = true`) with `<GuildName> RankName` formatting (`guild_rank_alt_style = true`). |
| **Custom Dropdown Media Picker** | Scrollable modal popup UI (`TacoTipMediaPickerFrame`) with statusbar texture strip previews, real 9-slice sliced borders, scrollbar, and ESC/click-outside auto-dismiss. |
| **Shaman Blue Default Color** | Shamans render in Shaman Blue (`#0070DE`) on Classic Era / SoD by default, with an options checkbox to switch to Classic pink if preferred. |
| **Tooltips Borders & Slicing** | Class-colored borders use Blizzard's native backdrop system, displaying proper sliced corner/edge borders with customizable edge size (default 14px). |
| **Dual-Spec Support (Era, SoD & TBC Anniversary)** | Both active and secondary talent specs display on inspection (inactive spec dimmed at 60% opacity) across Classic Era, Season of Discovery, TBC Classic Anniversary, and WotLK. |
| **Hostile Level Colors** | Hostile NPC levels in tooltips use Blizzard difficulty coloring (gray / green / yellow / orange / red) for instant danger assessment. |
| **Compact Tooltip `iLvl` Line** | Compact player tooltips show a separate `iLvl` line under GearScore so users can see both values without switching to wide layout. |
| **Smart Mover Positioning** | Green mover handle defaults to `TOPLEFT` corner; dragging continuously re-anchors the live tooltip on screen in real-time. |

## What's new in v0.7.7 (Latest Update)

| Fix / Change | Description |
| --- | --- |
| **Hot-Path Zero-Allocation Migration** | Converted all 38 tooltip line insertion points in `onTooltipSetUnit` from dynamic table allocations (`{ ... }`) to static record pooling (`addLineDouble` / `addLineSingle`). Replaced player line allocations with `wipe(pooledPlayerText)`. Eliminated all `unpack(v)` operations in tooltip line rendering. |
| **Dynamic 3D Portrait Screen-Edge Flipping** | During `ApplyTooltipAppearance`, dynamically calculates tooltip right boundary against screen width (`UIParent:GetRight()` / `_G["GetScreenWidth"]()`). If anchored near the right edge of the screen, the portrait automatically flips to the left (`TOPRIGHT -> TOPLEFT (-8, 0)`), preventing the enlarged 3D model viewport from clipping off-screen. |
| **Mouse Anchor OnUpdate Idle Gating** | Added `(not TacoTipConfig.anchor_mouse or not GameTooltip or not GameTooltip:IsShown())` early-return check to `TacoTipMouseAnchor's` `OnUpdate` handler, eliminating 144–240Hz cursor position queries, UI scale math, and point mutations when tooltips are hidden. |
| **Extended Non-Unit Visual Clearing** | Registered `ItemRefShoppingTooltip1`, `ItemRefShoppingTooltip2`, `WorldMapCompareTooltip1`, and `WorldMapCompareTooltip2` into `registerTooltipVisualClearing` to isolate comparison tooltips from inheriting stale unit states or borders. |
| **Padding Cleanup Fallback** | Added `elseif (tooltip.SetPadding) then tooltip:SetPadding(0, 0, 0, 0) end` fallback to `clearTooltipVisuals` for clients without `ClearPadding()`. |

## What's new in v0.7.6 (Recent v0.7.x Update)

| Fix / Change | Description |
| --- | --- |
| **Enlarged 3D Character Portrait** | Base dimensions increased to **72×96** (+20% size increase, strictly maintaining exact 3:4 aspect ratio). Scales cleanly without sub-pixel blurring at 50% (36×48), 100% (72×96), 150% (108×144), and 200% (144×192). |
| **Zero-Allocation Hover Pipeline** | Mouseover unit tooltips now use static pooled buffer tables (`pooledLinesToAdd`, `pooledTooltipText`) and zero-allocation item value calculations, eliminating table creation garbage-collection spikes during high-frequency mouseovers. |
| **SharedMedia Resolution Caching** | Media resolution results (backgrounds, borders, statusbars, fonts) are now lazily cached and invalidated only on configuration updates or new media registration, replacing heavy per-hover $O(N \log N)$ table sorts with instant $O(1)$ lookups. |
| **PowerBar Event Hardening** | `TacoTipPowerBar` event handling is strictly gated to when the power bar is shown, and unit events are cleanly unregistered when the ticker stops, eliminating event churn during raid combat. |
| **Tooltip Hook Deduplication** | Removed duplicate lifecycle hooks on `GameTooltip` for `OnTooltipCleared` and `OnHide` already handled by `registerTooltipVisualClearing`. |
| **`UNIT_TARGET` Gate** | Target change events return immediately in 1ns when `GameTooltip` is hidden or target line display is disabled. |
| **Portrait 20Hz Throttling** | 3D portrait `OnUpdate` alpha synchronization is throttled to 20Hz (0.05s) using parent alpha caching instead of querying the model every single engine frame. |
| **Pure White Friendly Levels** | Friendly player level numbers render in clean white text (`\|cFFFFFFFF`) to maintain distinct contrast with hostile difficulty colors. |

## What's new in v0.7.5 (Recent v0.7.x Update)

| Fix / Change | Description |
| --- | --- |
| **Dual-Spec Active/Inactive Rendering** | The inactive spec now renders in its class color at ~60% alpha, so you can see at a glance which talent spec is currently active. (Previously the dim wrapper was silently defeated by the line's own class-color code and both specs rendered identically.) Active spec keeps full class color. |
| **Modifier-Key Rebuild Gate** | Shift/other modifier presses no longer force a full tooltip rebuild unless a player tooltip is on screen and the selected tooltip style actually uses the shift toggle (styles 2/4). |
| **Idle Mouse-Anchor Skip** | The mouse-anchor frame stops reading the cursor every frame while mouse anchoring is disabled in options. |
| **Item Tooltip Feature Gate** | With both item level and item GearScore disabled, item tooltips skip all item-data fetching. |
| **Options Config Integrity** | Non-Wrath clients no longer rewrite the saved `show_achievement_points` preference to `false`; your preference survives switching between clients. |
| **Pawn Scoring Allocation** | The Pawn scale name is built once per scoring pass instead of once per equipped item. |

## What's new in v0.7.4 (Recent v0.7.x Update)

| Fix / Change | Description |
| --- | --- |
| **Per-Tooltip Lifecycle State** | Every deferred timer (delayed tooltip, border re-applies, instant fade), generation counter and pending item-load handle now live on each tooltip frame instead of shared module-level locals — one tooltip's clear/hide can no longer cancel or stale-out another tooltip's pending work, and the power bar only clears with GameTooltip. |
| **Uncached Item Retry** | Hovering an equippable item that Blizzard hasn't cached yet now requests its data and repaints when the load lands (generation + exact-link guarded, cancelled on clear/hide), instead of leaving the tooltip without an ilvl/GearScore line until a second hover. |
| **Duplicate Equipped Items** | Two identical item ids (e.g. matching rings) no longer drain the pending-callback list early — registration is deduped at every Gearscore/Pawn callback site. |
| **Inspect Hot-Path** | `getOrCreateItemMixin` hoisted to module scope in LibClassicInspector — no per-slot closure allocation on the player-hover GearScore scan. |

## What's new in v0.7.3 (Recent v0.7.x Updates)

| Feature / Fix | Description |
| --- | --- |
| **Single-Fetch Item Tooltips** | Item tooltips now perform exactly one `GetItemInfo` call per hover; ilvl, GearScore, and HunterScore all share that fetch through the new `TT_GS:GetItemScoreFromInfo` entry point. |
| **ItemMixin Memoization** | `LibClassicInspector` reuses one `ItemMixin` per inspected slot (keyed by item identity so gear changes rebuild) instead of allocating ~19 fresh mixins on every player hover. |
| **Overlay Offset Clamping** | Typed X/Y offset fields now clamp to the ±300 slider range, and `SafeSanitizeConfig` repairs out-of-range or corrupt saved offsets (including NaN/infinite values) on every load. |
| **Options OnShow Lifecycle Fix** | Page builders no longer assign `panel:SetScript("OnShow")`; the load-time safeCall-wrapped handlers own the slot, removing an order-dependent overwrite seam. |
| **Library Hardening** | Talent getters return nil past a tab's real talent count instead of erroring, the event dispatcher logs-and-continues on unhandled events, and achievement validity probes use Blizzard's documented 14th `isStatistic` return. |
| **Accurate Backdrop Comments** | Corrected stale "pre-2.5.3" notes: NineSlice-equipped tooltips are verified present on all supported clients; backdrop handling is runtime-detected, not build-gated. |
| **New Regression Tests** | Added `SanitizeOffsetBounds` and `GetItemScoreFromInfoMatchesLink` WoWUnit tests (run with `/tttest`). |

## What's new in v0.7.1

| Feature / Fix | Description |
| --- | --- |
| **Removed Obsolete Preview Tooltip & Dead Code** | Fully excised the broken floating options preview tooltip and over 40 redundant preview update hooks. Options UI controls now update addon settings with zero unnecessary overhead. |
| **Options UI & Layout Cleanup** | Streamlined options lifecycle handlers, eliminated stale references, and updated tooltip descriptions across all 11 locale files. |
| **Zero Static Analysis Warnings** | Passed 100% clean `luacheck` static analysis across all 21 addon files with 0 warnings and 0 errors. |

## What's new in v0.7.0

| Feature / Fix | Description |
| --- | --- |
| **Minimap & World Map Flicker Fix** | Completely eliminated tooltip flickering when hovering Minimap POIs, quest pins, trainer blips, tracking icons, and World Map nodes by disabling mouse interception on `GameTooltip` and preserving caller frame ownership in `GameTooltip_SetDefaultAnchor`. |
| **Accurate Unit Resolution** | `UPDATE_MOUSEOVER_UNIT` and event handlers validate `tooltip:IsUnit()` to ensure non-unit map tooltips are never falsely hidden or overwritten with stale unit data. |
| **Enlarged 3D Player Portrait** | Increased base 3D portrait dimensions to **60×80** (width 60px, height 80px) to match full multi-line tooltip height. |
| **Updated Feature Defaults** | Enabled Guild Rank (`<Guild> Rank`), Item GearScore, Faction Icon, Group Role Icon, and Shaman Blue by default. |
| **Default Tooltip Border** | Set default border texture to `"Tooltip enlarged"` (`14px` edge size) with dynamic LibSharedMedia-3.0 resolution. |
| **Mover Drag & TOPLEFT Default** | Mover handle defaults to `TOPLEFT`; live drag re-anchoring keeps `GameTooltip` continuously attached during drag. |
| **Scrollable Media Picker** | Upgraded media dropdowns to a fixed-height scrollable modal popup UI (`TacoTipMediaPickerFrame`). |
| **100% Locale Parity** | Native translations across all 11 locale files with key parity across 263 localized strings. |

## How TacoTip compares

| Area | What you get |
| --- | --- |
| Tooltip styles | Full / Compact / Mini, hostile-mob difficulty colors, custom positioning, mouse + spell anchoring |
| Player data | GearScore, average item level, dual-spec names with per-spec icons, optional Pawn scores, glyph + achievement data (Wrath) |
| Character & Inspect frames | GearScore / iLvl overlays with movable labels and X/Y offset controls |
| Quality of life | Instant fade, titles, guild names/ranks, PvP/team icons, class-tinted styling, saved-anchor-aware mover reset |
| Integrations | Pawn (when installed), optional SharedMedia fonts/textures, bundled Classic inspection libraries |

## Tooltip details

| Element / Capability | Features & Formatting |
| --- | --- |
| **Player Names & Titles** | Class-colored player names with full player titles. |
| **Guild & Rank Display** | Guild tag with default `<GuildName> RankName` formatting (`show_guild_rank = true`). |
| **Target Display** | Target unit name displayed directly on player tooltips. |
| **Badges & Icons** | Faction emblems (Alliance/Horde), PvP flag icons, and party/raid group role badges (Tank/Healer/DPS). |
| **Talents & Specs** | Class-colored spec names accompanied by per-spec icon badges derived from `LibClassicInspector`. |
| **GearScore & iLvl** | Real-time GearScore calculation and average item level display across 7 quality color tiers. |
| **Item Tooltips** | Item level, item GearScore, and HunterScore displayed on item tooltips. |
| **3D Portrait** | Live 3D character portrait enlarged to **60×80** (exact 3:4 aspect ratio). |
| **Media Customization** | Custom statusbar textures, background textures, border textures, edge thickness, fonts, and alpha. |

Tooltip layouts behave as follows:

- **Full / wide** styles show the richer two-column style details, including combined GearScore + iLvl presentation.
- **Compact** styles keep the tooltip shorter while still showing key player data.
- **Mini** styles condense GearScore / iLvl / Pawn into a terse summary line.
- Player talent/spec lines now use colored spec names and icons instead of plain white text.
- Hostile non-player unit level numbers now follow Blizzard's own difficulty-color logic so the tooltip conveys XP relevance and danger more clearly.

## Supported game versions

| Client family | Interface |
| --- | --- |
| Classic Era / Vanilla | `11509` |
| Season of Discovery (SoD) | `11509` (same patch `1.15.9` as Classic Era) |
| Burning Crusade Classic Anniversary | `20506` |
| Titanforge / 3.80.1-style Wrath-family clients | `38001` |
| Retail | Not supported |

TBC Classic Anniversary patch `2.5.6` uses interface `20506`, which is the target version this fork now validates against.

TacoTip is also compatible with Chinese Titanforge `3.80.1` build, because the addon runtime accepts build major `3` and the Classic-era code paths remain enabled.

## Slash commands

| Command | Result |
| --- | --- |
| `/tacotip` | Open the options panel |
| `/taco` | Open the options panel |
| `/tooltip` / `/tip` / `/tt` / `/gs` / `/gearscore` | Short aliases for the main command |
| `/tacotip custom` / `/tacotip move` / `/tacotip unlock` | Show the tooltip mover |
| `/tacotip save` | Save the current mover position |
| `/tacotip default` | Clear the saved custom position while leaving the chosen anchor available for later reuse |
| `/tacotip reset` | Reset TacoTip settings |
| `/tacotip help` | Print command help |
| `/tacotip anchor <mode>` | Set the custom anchor (`topleft`, `topright`, `bottomleft`, `bottomright`, `center`) |

## Options UI layout

TacoTip Gearscore TBC now uses a parent category with focused child pages in the Blizzard AddOns/options tree.
The AddOns list entry uses the addon title from `TacoTip.toc`, so it appears as **`TacoTip Gearscore TBC`** in the Blizzard options tree.

| Page | What lives there |
| --- | --- |
| `TacoTip` | Landing page, quick actions, status summary, and compact behavior/client toggles |
| `Tooltips` | Tooltip style, unit-tooltip content, item-tooltip data, visual customization, live preview |
| `Positioning` | Mouse anchoring, spell anchoring, saved custom position, custom anchor dropdown, mover workflow |
| `Character & Inspect` | Character/inspect overlay toggles, unlock movers, numeric offset fields, sliders, manual overlay tuning |

The root `TacoTip` page now also includes a language dropdown that follows the client locale by default and lets players save a different TacoTip language for the next `/reload`.

The `Tooltips` page also includes:

- guild-rank style selection
- class-tinted border/background options with alpha control
- border/background color swatches backed by the Blizzard color picker
- tooltip background and border texture selection with automatic SharedMedia pickup and Blizzard fallback
- optional unit portrait display and portrait scaling
- tooltip font selection with Blizzard fonts plus optional SharedMedia support
- tooltip text-size control
- shared health/power bar texture selection with wide single-dropdown strip previews
- scroll-wheel support on long pages and slider widgets
- clearer titled subsections and hover-help on custom widgets
- immediate preview refresh when supported media/font selections change

The root `TacoTip` page now also carries the lightweight behavior/client toggles that used to live on a separate sparse Advanced page:

- suppress inspection-style tooltip additions in combat
- Blizzard `UberTooltips` toggle
- chat class color CVar toggle
- Wrath-only achievement points toggle

## Positioning workflow

- Use the **Positioning** page to choose between Blizzard default placement, mouse anchoring, or a saved custom tooltip position.
- **Anchor Spells to Mouse** applies the cursor-anchor behavior specifically to spell and action-button tooltips.
- When custom positioning is enabled, the **Open Tooltip Mover** button shows the live mover.
- Use the custom anchor dropdown to choose `TOPLEFT`, `TOPRIGHT`, `BOTTOMLEFT`, `BOTTOMRIGHT`, or `CENTER`.
- Resetting the mover position now snaps back to the selected anchor corner instead of silently clearing the chosen anchor.
- The green mover handle and the actual tooltip anchor now stay synchronized when the custom anchor changes.
- Use the **Character & Inspect** page to fine-tune overlay offsets with numeric fields and sliders, or unlock the overlay movers for manual drag placement.

## Character & Inspect workflow

- Toggle GearScore overlays and average item level overlays independently.
- Use the numeric X/Y fields for precise placement.
- Use the sliders for quick visual tuning.
- Unlock overlay movers if you want to drag the labels directly on the paper doll / inspect frames.

## SharedMedia and built-in media support

When `LibSharedMedia-3.0` is present, TacoTip can automatically pick up additional:

- fonts
- statusbar textures
- background textures
- border textures

If no SharedMedia pack is installed, TacoTip still exposes expanded Blizzard fallback choices for fonts, bar textures, tooltip backgrounds, and tooltip borders.

## Localization status

- New settings strings are authored in `Locale/enUS.lua` first.
- All shipped locale files now include the current options UI coverage used by the modern settings pages.
- The root options page includes a single language dropdown. By default TacoTip follows the current client locale, but players can save another supported locale and apply it on the next `/reload`.
- If a future key is missing in a locale, TacoTip still falls back to English through the existing merge behavior.

## Available languages

| Locale code | Language | Coverage |
| --- | --- | --- |
| `enUS` | English | Source of Truth (100%) |
| `deDE` | Deutsch | 100% Complete |
| `esES` | Español (España) | 100% Complete |
| `esMX` | Español (Latinoamérica) | 100% Complete |
| `frFR` | Français | 100% Complete |
| `itIT` | Italiano | 100% Complete |
| `koKR` | 한국어 | 100% Complete |
| `ptBR` | Português (Brasil) | 100% Complete |
| `ruRU` | Русский | 100% Complete |
| `zhCN` | 简体中文 | 100% Complete |
| `zhTW` | 繁體中文 | 100% Complete |

Current localization work included in this build:

- 100% key parity across all 11 locale files with 263 localized strings per language
- updated the visible welcome/help ownership string to `AcidBomb (Pilsung)` across all locales
- preserved client-locale default behavior with manual override support from the root options page
- kept English fallback behavior for any future untranslated keys

## Installation

1. Download the latest release.
2. Extract the `TacoTip` folder into your World of Warcraft `Interface/AddOns` folder.
3. Reload the UI or restart the game.
4. Use `/tacotip`, `/tt`, or `/taco` to configure the addon.

## Notes

| Item | Details |
| --- | --- |
| Optional Pawn support | Enabled automatically when Pawn is installed |
| Optional SharedMedia support | Used automatically when compatible fonts/textures are registered |
| Saved settings | Stored through `TacoTipConfig` (auto-repaired on load if corrupt) |
| Future direction | More polish, compatibility work, and quality-of-life features beyond `v0.7.0` |
| Feedback | Use project comments or the issue tracker |

## Release Stability & Quality Assurance

- **Zero Unhandled Lua Errors:** Full static code analysis gate (`luacheck .`) passes with 0 warnings and 0 errors across all 21 source files.
- **Automated Test Suite:** Comprehensive `WoWUnit` test framework (`TacoTip_Tests.lua`) verifies core GearScore calculations, tooltip line getters, dual-spec detection, and media resolution across Classic Era and TBC Anniversary environments.
- **Media Fallback Guarding:** All LibSharedMedia textures, fonts, and borders safely fall back to Blizzard defaults if dynamic media is missing or unregistered.

If you enjoy TacoTip Gearscore TBC, please leave feedback and a rating on CurseForge.

The universal build is in `TacoTip_Forever/`. Its [inspection scheduling](TacoTip_Forever/README.md#inspection-scheduling) restores queued requests and manual-inspect priority.
