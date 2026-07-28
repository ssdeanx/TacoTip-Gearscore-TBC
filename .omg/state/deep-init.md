# Deep Initialization Summary (v0.6.6)

This repository, **TacoTip-Gearscore-TBC**, is a World of Warcraft Classic-family addon that calculates and displays GearScore, item level, and spec/talents on player/NPC/item tooltips and character/inspect frame overlays. The addon currently has 40,000+ monthly downloads on CurseForge.

## Core Addon Bootstrap & Architecture Boundaries

- **Runtime Environment:** Lua 5.1/WoW Classic interface versions (`11509`, `20506`, `38001`). Crucially, Retail WoW is unsupported.
- **Entry Point / Load Order:** Specified in [TacoTip.toc](file:///home/sam/TacoTip-Gearscore-TBC/TacoTip.toc):
  1. Libraries: `LibStub`, `CallbackHandler-1.0`, `LibDetours-1.0`, `LibClassicInspector`.
  2. Localization files: `Locale/*.lua`.
  3. Core components: `gearscore.lua`, `pawn.lua`, `textures.lua`, `options.lua`, `main.lua`, `TacoTip_Tests.lua`.
- **Globals Exposed / Shared Namespace:**
  - `TT`: Core namespace and helper functions.
  - `TT_GS`: GearScore engine global.
  - `TT_PAWN`: Pawn integration namespace.
  - `TacoTipConfig`: Addon configuration (saved variable).
  - `TACOTIP_LOCALE`: localization table.

## High-Risk Zones & Hotspots (v0.6.6 Release Focus)

1. **Classic Tooltip API Modernization (`docs/classic-tooltip-api-reference.md`):**
   - **`tooltip:GetLeftLine(i)`**: Replacing fragile `_G["GameTooltipTextLeft"..i]` string concatenations with native C++ line getters for speed and forward compatibility across arbitrary tooltip frame instances.
   - **`tooltip:GetOwner()`**: Bleed prevention guard to check if the tooltip owner is a unit frame before applying or clearing unit-specific overlays (portraits, health bars, class borders, guild lines).
   - **`tooltip:IsUnit(unit)`**: Streamlining tooltip unit validation guards.
   - **`tooltip:GetMinimumWidth()`**: Read-before-write logic for minimum tooltip width adjustments to avoid unnecessary layout recalcs.
2. **NineSlice Overlay vs. Pre-2.5.3 Backdrop Hooking:** On TBC Anniversary (2.5.3+), GameTooltip utilizes a sub-frame called `NineSlicePanel` for backdrop styling. Standard backdrop/border functions on the tooltip fail because NineSlice draws on top of them. The addon uses a separate child frame overlay at `FrameLevel(2)` to draw class-colored borders.
3. **Classic Era & SoD (Patch 1.15.8/1.15.9) Guild Parsing Fallback:** Legacy `GetGuildInfo` API behavior varies between client branches. TacoTip implements a fallback regex parser to extract `<Guild Name>` from player tooltip lines and safely cleans empty `<>` brackets when guild display is disabled.
4. **Asynchronous Inspection Pipeline:** Talent calculation relies on `LibClassicInspector` callbacks, which require inspection queries to complete. The addon hooks into these callbacks and dynamically redraws or refreshes tooltips upon completion.
5. **Pawn Integration Safety:** Pawn support is optional and client-version dependent; all Pawn API calls are wrapped in `pcall` guards.

## Dependency Hotspots

- `LibClassicInspector` handles talent/inspection logic.
- `LibDetours-1.0` detours hooking mechanisms securely.
- `WoWUnit` manages in-game testing.
