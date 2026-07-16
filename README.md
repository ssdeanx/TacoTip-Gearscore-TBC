# TacoTip Gearscore TBC

TacoTip Gearscore TBC is a revived fork of TacoTip for Classic-era World of Warcraft.
The original addon stopped working for TBC Classic, so this fork exists to make it work again, keep the useful features alive, and give the project room for future improvements.

> This description is written in Markdown for the CurseForge project page.

## 简体中文 / 繁體中文

- 支持客户端 / 支援用戶端：`1.15.8`、`2.5.5 (20505)`、`3.4.5 (30405)`、`3.80.1 (Titanforge)`
- 主要功能 / 主要功能：提示增强、GearScore、平均装等 / 平均物品等級、天赋 / 專精、角色与观察面板信息
- 打开设置 / 開啟設定：`/tacotip` 或 `/taco`
- 语言 / 語言：默认跟随客户端语言，未翻译内容会自动回退到英文；主页面也提供语言下拉选单 / 下拉選單。

## At a glance

| Field | Details |
| --- | --- |
| Addon | TacoTip Gearscore TBC |
| Status | Release-ready public build |
| Main purpose | Tooltip enhancement, inspection data, and character UI polish |
| Supported clients | Classic Era / Vanilla, Burning Crusade Classic Anniversary, Wrath Classic, Titanforge / 3.80.1 |
| Installation | Copy the `TacoTip` folder into `Interface/AddOns` |
| Dependencies | Required libraries are bundled; Pawn support is optional |
| Public version | `v0.6.0` |

## Why TacoTip Gearscore TBC exists

| Original TacoTip | TacoTip Gearscore TBC |
| --- | --- |
| Broke on TBC Classic | Restored to working order for Classic-era clients |
| Had no clear revival path | Clean fork with updated Blizzard API wiring |
| Was mainly useful historically | Kept alive for current Classic players |
| Left little room for growth | Built to support future polish and new features |

## What it does

| Area | Features |
| --- | --- |
| Tooltips | Full / Compact / Mini styles, live preview, hostile mob difficulty colors, target display, custom positioning, mouse anchoring, spell anchoring, portrait/font/theme controls |
| Player inspection data | GearScore, average item level, specialization names with per-spec icons, optional Pawn scores, glyph data, achievement data on Wrath |
| Character and inspect frames | GearScore and iLvl display with movable labels plus numeric X/Y offset controls |
| Quality of life | Instant fade, titles, guild names/ranks, PvP/team icons, class-tinted tooltip styling, saved anchor-aware mover reset |
| Integrations | Pawn support when installed, optional SharedMedia support for fonts/textures, plus bundled Classic inspection libraries |

## Current feature highlights

- Tooltip borders now render correctly: class-colored borders use Blizzard's native backdrop system instead of a stretched overlay, so the `UI-Tooltip-Border` texture displays as a proper sliced corner/edge border, and late tooltip refreshes now keep the class tint instead of falling back to gray.
- Dual-spec players now see both specializations in compact tooltip styles, with the inactive spec dimmed to 60% opacity.
- Class icon moved from inline text to a positioned badge at the top-right corner of the tooltip, with configurable size (8–32px) in the options panel.
- PVP icon now only appears on player units that are actually flagged for PVP, not on PVP-flagged NPCs.
- Hostile NPC levels in tooltips now use Blizzard difficulty coloring again, so gray / green / yellow / orange / red difficulty is visible at a glance.
- Specialization lines now use class-colored spec names and per-spec icons derived from `LibClassicInspector` talent data.
- Compact player tooltips now show a separate `iLvl` line under GearScore so users can see both values without switching to the wide layout.
- The live tooltip preview in the options panel now sits in a dedicated right-side column instead of covering the controls.
- The tooltip mover reset flow now preserves the selected custom anchor instead of wiping it.
- Long options pages now support proper mouse-wheel scrolling and correct content height instead of visually dead scrollbars.

## What's new in v0.6.0

This release focuses on a fully settings-driven options preview and Season of Discovery correctness:

- **Options preview is now 100% settings-driven.** The Tooltips-page preview reflects the selected style's default layout and updates instantly when you change any setting — class color, portrait, bars, fonts, textures, borders, alpha, and every content toggle. No keypress required. The live in-game tooltip still expands hybrid styles on Shift; the preview shows the default layout.
- **Both tooltips share one source of truth.** Every setting feeds the preview example *and* your live tooltip, because both read the same config. What you see in the preview is what you get in the game.
- **Preview shows a fixed max-level ROGUE example** (named AcidBomb) so it always looks identical regardless of your own character's class.
- **SoD portrait + class-border fixes.** The 3D portrait now renders for players *and* enemies (no leftover model), and class-tinted borders no longer bleed onto enemy tooltips.
- **Pawn works on SoD again.** The load gate now accepts Pawn's public API, and the specialization lookup falls back to the primary spec because SoD runes replace talent trees.

Full history is in `CHANGELOG.md`.

## How TacoTip compares

| Area | What you get |
| --- | --- |
| Tooltip styles | Full / Compact / Mini, live preview, hostile-mob difficulty colors, custom positioning, mouse + spell anchoring |
| Player data | GearScore, average item level, dual-spec names with per-spec icons, optional Pawn scores, glyph + achievement data (Wrath) |
| Character & Inspect frames | GearScore / iLvl overlays with movable labels and X/Y offset controls |
| Quality of life | Instant fade, titles, guild names/ranks, PvP/team icons, class-tinted styling, saved-anchor-aware mover reset |
| Integrations | Pawn (when installed), optional SharedMedia fonts/textures, bundled Classic inspection libraries |

## Tooltip details

TacoTip can add or customize all of the following on supported Classic-family clients:

- class-colored player names
- player titles
- guild names and optional guild-rank formatting
- target display
- faction/team icons and PvP icon handling
- talents / specialization display with class-colored names and spec icons
- GearScore and average item level
- optional Pawn score display when Pawn is installed and up to date
- item level, item GearScore, and HunterScore on item tooltips
- optional portrait display and portrait scaling
- configurable tooltip background, border, fonts, text size, and bar textures

Tooltip layouts behave as follows:

- **Full / wide** styles show the richer two-column style details, including combined GearScore + iLvl presentation.
- **Compact** styles keep the tooltip shorter while still showing key player data.
- **Mini** styles condense GearScore / iLvl / Pawn into a terse summary line.
- Player talent/spec lines now use colored spec names and icons instead of plain white text.
- Hostile non-player unit level numbers now follow Blizzard's own difficulty-color logic so the tooltip conveys XP relevance and danger more clearly.

## Supported game versions

| Client family | Interface |
| --- | --- |
| Classic Era / Vanilla | `11508` |
| Season of Discovery (SoD) | `11508` (same patch `1.15.8` as Classic Era) |
| Burning Crusade Classic Anniversary | `20505` |
| Wrath Classic | `30405` *(carried forward, API unverified — no WotLK reference branch available)* |
| Titanforge / 3.80.1-style Wrath-family clients | `38001` |
| Retail | Not supported |

TBC Classic Anniversary patch `2.5.5` uses interface `20505`, which is the target version this fork now validates against.

TacoTip is also compatible with Chinese Titanforge / private-server clients that report a Wrath-family `3.80.1` build, because the addon runtime accepts build major `3` and the Classic-era code paths remain enabled.

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

| Locale code | Language |
| --- | --- |
| `enUS` | English |
| `deDE` | Deutsch |
| `esES` | Español (España) |
| `esMX` | Español (Latinoamérica) |
| `frFR` | Français |
| `itIT` | Italiano |
| `koKR` | 한국어 |
| `ptBR` | Português (Brasil) |
| `ruRU` | Русский |
| `zhCN` | 简体中文 |
| `zhTW` | 繁體中文 |

Current localization work included in this build:

- aligned every shipped locale file with the modern options UI keys from `enUS.lua`
- updated the visible welcome/help ownership string to `AcidBomb (Pilsung)` across all locales
- preserved client-locale default behavior with manual override support from the root options page
- kept English fallback behavior for any future untranslated keys

## Installation

1. Download the latest release.
2. Extract the `TacoTip` folder into your World of Warcraft `Interface/AddOns` folder.
3. Reload the UI or restart the game.
4. Use `/tacotip` or `/taco` to configure the addon.

## Notes

| Item | Details |
| --- | --- |
| Optional Pawn support | Enabled automatically when Pawn is installed |
| Optional SharedMedia support | Used automatically when compatible fonts/textures are registered |
| Saved settings | Stored through `TacoTipConfig` (auto-repaired on load if corrupt) |
| Future direction | More polish, compatibility work, and quality-of-life features beyond `v0.5.9` |
| Feedback | Use project comments or the issue tracker |

## Known Issues

- **Pawn on Season of Discovery (fixed in 0.5.9):** SoD-era Pawn does not expose `PawnClassicLastUpdatedVersion`, so the previous version-only load gate disabled Pawn entirely on SoD. The gate now also accepts Pawn's public API presence, and the spec lookup falls back to the primary spec because SoD runes replace talent trees (`GetSpecialization` can return `nil`). Pawn scores now display on SoD players. On TBC/Wrath where Pawn is ready immediately, scores show instantly. Pawn's own init-time "scale colors" message (if any) is logged by Pawn, not TacoTip, and is wrapped in `pcall` so it cannot crash a tooltip.
- **Options preview is settings-driven and expands on Shift (fixed in 0.5.9):** Every setting (style, class color, portrait, bars, fonts, textures, borders, alpha, and all content toggles) drives the preview directly with no keypress, and every setting feeds both the preview example AND your live in-game tooltip since both read the same config. The preview shows a fixed max-level ROGUE example (named AcidBomb) so it always looks the same regardless of your class. Hybrid styles (2/4) show their compact default and expand to full while Shift is held — exactly like the live tooltip.

If you enjoy TacoTip Gearscore TBC, please leave feedback and a rating on CurseForge.
