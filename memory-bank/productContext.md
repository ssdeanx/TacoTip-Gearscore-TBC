# Product Context

## Problem

The original TacoTip experience broke on Classic-era branches, but players still want tooltip augmentation and inspection data in those clients. TacoTip Remix restores that functionality and keeps the UX familiar while adapting to the current Classic UI APIs.

## Product goals

- Improve tooltip readability and usefulness without changing the underlying WoW gameplay flow.
- Surface inspection data quickly: talents, GearScore, average item level, and optional Pawn scores.
- Make tooltip placement easy to control with custom anchoring and mover tools.
- Preserve lightweight behavior and compatibility with Classic-era clients.

## Feature inventory

- Unit tooltip styles: full, compact, and mini-style variants.
- Target display and faction/team indicators.
- Class coloring, title handling, and guild name/rank formatting.
- Talents and specialization display via `LibClassicInspector`.
- GearScore and average item level display for units and items.
- Optional Pawn score display when Pawn is present.
- Health bar / power bar display under the tooltip.
- Character and inspect frame GearScore / iLvl overlays.
- Slash commands for options, custom positioning, reset, help, and anchor modes.

## Bundled vs optional

- Bundled: LibStub, CallbackHandler-1.0, LibDetours-1.0, LibClassicInspector.
- Optional: Pawn support.

## Success looks like

- Tooltips render with the expected data and no errors on supported Classic clients.
- Users can move and anchor tooltips without editing Lua.
- Inspect and character frames stay readable and correctly positioned.
