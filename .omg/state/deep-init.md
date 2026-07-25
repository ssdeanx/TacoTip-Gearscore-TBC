# Deep Initialization Summary (v0.6.2)

This repository, **TacoTip-Gearscore-TBC**, is a World of Warcraft Classic-family addon that calculates and displays GearScore, item level, and spec/talents on player/NPC/item tooltips and character/inspect frame overlays.

## Core Addon Bootstrap & Architecture Boundaries
- **Runtime Environment:** Lua 5.1/WoW Classic interface versions (`11508`, `20505`, `30405`, `38001`). Crucially, Retail WoW is unsupported.
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

## High-Risk Zones & Hotspots (v0.6.2 Update)
1. **NineSlice Overlay vs. Pre-2.5.3 Backdrop Hooking:** On TBC Anniversary (2.5.3+), GameTooltip utilizes a sub-frame called `NineSlicePanel` for backdrop styling. Standard backdrop/border functions on the tooltip fail because NineSlice draws on top of them. The addon uses a separate child frame overlay at `FrameLevel(2)` to draw class-colored borders.
2. **Classic Era & SoD (Patch 1.15.8) Guild Parsing Fallback:** On patch 1.15.8 (which runs both Classic Era and Season of Discovery as two different versions of the game), the legacy `GetGuildInfo` API is restricted to the local player character (`"player"`), returning `nil` when queried for other players (like `"mouseover"`). TacoTip implements a fallback regex parser to extract `<Guild Name>` from the player tooltip lines. When guild display is disabled, it must completely overwrite the line with `""` to avoid leaving empty `<>` brackets. On TBC Anniversary (patch 2.5.5 / 2.5.6), `GetGuildInfo` works natively for other players and requires no fallback.
3. **API Parameter Mapping & Redundancies:** In `LibClassicInspector`, calling `GetTalentInfo` requires strict parameter alignment (specifically the position of the `group` parameter to prevent pulling pet talents). Similarly, `CanInspect` has been cleaned of redundant parameters.
4. **Asynchronous Inspection Pipeline:** Talent calculation relies on `LibClassicInspector` callbacks, which require inspection queries to complete. The addon hooks into these callbacks and dynamically redraws or refreshes tooltips when inspection completes, handling potential race conditions where units are cached or gone.
5. **Pawn Integration:** Pawn support is optional and highly client-version dependent. All Pawn API calls must be wrapped in `pcall` (such as `PawnGetSingleValueFromItem` which is now protected in v0.6.2).

## Dependency Hotspots
- `LibClassicInspector` handles talent/inspection logic.
- `LibDetours-1.0` detours hooking mechanisms securely.
- `WoWUnit` manages in-game testing.
