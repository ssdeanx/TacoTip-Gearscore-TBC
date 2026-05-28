# TacoTip Gearscore TBC

TacoTip Gearscore TBC is a revived fork of TacoTip for Classic-era World of Warcraft.
The original addon stopped working for TBC Classic, so this fork exists to make it work again, keep the useful features alive, and give the project room for future improvements.

> This description is written in Markdown for the CurseForge project page.

## At a glance

| Field | Details |
| --- | --- |
| Addon | TacoTip Gearscore TBC |
| Status | Active fork / public live release |
| Main purpose | Tooltip enhancement, inspection data, and character UI polish |
| Supported clients | Classic Era / Vanilla, Burning Crusade Classic Anniversary, Wrath Classic |
| Installation | Copy the `TacoTip` folder into `Interface/AddOns` |
| Dependencies | Required libraries are bundled; Pawn support is optional |
| Public version | `v0.4.8` |

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
| Tooltips | Full / Compact / Mini styles, live preview, custom positioning, mouse anchoring, spell anchoring, portrait/font/theme controls |
| Inspection | GearScore, average item level, talent data, glyph data, achievement data |
| Character and inspect frames | GearScore and iLvl display with movable labels plus numeric X/Y offset controls |
| Quality of life | Instant fade, titles, guild names/ranks, PvP/team icons, target display, optional class-tinted tooltip styling |
| Integrations | Pawn support when installed, plus bundled Classic inspection libraries |

## Supported game versions

| Client family | Interface |
| --- | --- |
| Classic Era / Vanilla | `11508` |
| Burning Crusade Classic Anniversary | `20505` |
| Wrath Classic | `30405` |
| Retail | Not supported |

TBC Classic Anniversary patch `2.5.5` uses interface `20505`, which is the target version this fork now validates against.

## Slash commands

| Command | Result |
| --- | --- |
| `/tacotip` | Open the options panel |
| `/taco` | Open the options panel |
| `/tooltip` / `/tip` / `/tt` / `/gs` / `/gearscore` | Short aliases for the main command |
| `/tacotip custom` / `/tacotip move` / `/tacotip unlock` | Show the tooltip mover |
| `/tacotip save` | Save the current mover position |
| `/tacotip default` | Disable custom positioning |
| `/tacotip reset` | Reset TacoTip settings |
| `/tacotip help` | Print command help |
| `/tacotip anchor <mode>` | Set the custom anchor (`topleft`, `topright`, `bottomleft`, `bottomright`, `center`) |

## Options UI layout

TacoTip Gearscore TBC now uses a parent category with focused child pages in the Blizzard AddOns/options tree.
The AddOns list entry uses the addon title from `TacoTip.toc`, so it appears as **`TacoTip Gearscore TBC`** in the Blizzard options tree.

| Page | What lives there |
| --- | --- |
| `TacoTip` | Landing page, quick actions, status summary, and compact behavior/client toggles |
| `Tooltips` | Tooltip style, unit-tooltip content, item-tooltip data, live preview |
| `Positioning` | Mouse anchoring, saved custom position, custom anchor dropdown, mover workflow |
| `Character & Inspect` | Character/inspect overlay toggles, unlock movers, numeric offset fields, sliders |

The `Tooltips` page also includes:

- guild-rank style selection
- class-tinted border/background options with alpha control
- border/background color swatches backed by the Blizzard color picker
- tooltip background and border texture selection with automatic SharedMedia pickup and Blizzard fallback
- optional unit portrait display and portrait scaling
- tooltip font selection with optional SharedMedia support
- tooltip text-size control
- shared health/power bar texture selection with wide single-dropdown strip previews
- scroll-wheel support on long pages and slider widgets
- clearer titled subsections and hover-help on custom widgets

## Positioning workflow

- Use the **Positioning** page to choose between Blizzard default placement, mouse anchoring, or a saved custom tooltip position.
- When custom positioning is enabled, the **Open Tooltip Mover** button shows the live mover.
- Use the custom anchor dropdown to choose `TOPLEFT`, `TOPRIGHT`, `BOTTOMLEFT`, `BOTTOMRIGHT`, or `CENTER`.
- Resetting the mover position now snaps back to the selected anchor corner instead of silently clearing the chosen anchor.
- Use the **Character & Inspect** page to fine-tune overlay offsets with numeric fields and sliders, or unlock the overlay movers for manual drag placement.

## Installation

1. Download the latest release.
2. Extract the `TacoTip` folder into your World of Warcraft `Interface/AddOns` folder.
3. Reload the UI or restart the game.
4. Use `/tacotip` or `/taco` to configure the addon.

## Notes

| Item | Details |
| --- | --- |
| Optional Pawn support | Enabled automatically when Pawn is installed |
| Saved settings | Stored through `TacoTipConfig` |
| Future direction | More polish, compatibility work, and quality-of-life features |
| Feedback | Use project comments or the issue tracker |

If you enjoy TacoTip Gearscore TBC, please leave feedback and a rating on CurseForge.
