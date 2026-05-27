# Project Brief

TacoTip Remix is a revived Classic-era fork of TacoTip for World of Warcraft. It keeps the addon useful on Classic Era, Burning Crusade Classic Anniversary, and Wrath Classic by enhancing unit and item tooltips, exposing inspection data, and polishing character and inspect presentation.

## What players get

- Richer unit tooltips: class colors, titles, guild info, talents, target data, and PvP/team icons.
- Item tooltip enhancements: item level, GearScore, and HunterScore where applicable.
- Character and inspect frame overlays: GearScore and average item level labels.
- Tooltip placement tools: mouse anchoring, custom positioning, and mover controls.
- Optional Pawn score display when Pawn is installed and recent enough.

## Supported environment

- Classic Era / Vanilla (`11508`)
- Burning Crusade Classic (`20505`) This is old version and not using the Anniversary client
- Wrath Classic (`30405`)
- Retail is intentionally unsupported

## Source of truth

- `README.md` for the user-facing summary
- `TacoTip.toc` for load order and dependencies
- `main.lua`, `options.lua`, `gearscore.lua`, `pawn.lua` for actual behavior
