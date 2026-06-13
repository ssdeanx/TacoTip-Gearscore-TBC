# System Patterns

## Module split

- `main.lua`: runtime bootstrap, tooltip hooks, refresh callbacks, mover and anchoring logic, and item tooltip handling.
- `options.lua`: defaults, config bootstrap, settings panel, UI controls, and preview tooltip rendering.
- `gearscore.lua`: GearScore and item-level calculations plus item quality coloring.
- `pawn.lua`: optional Pawn integration and score lookup logic.
- `Locale/*.lua`: localized strings and labels.
- `Libs/*`: bundled support libraries and inspection engine.

## Runtime patterns

- Client gate: `GetBuildInfo()` major-version check; return early outside Classic families.
- Library gate: assert required libs before continuing.
- Shared globals: `TT`, `TT_GS`, `TT_PAWN`, `TacoTipConfig`, `TACOTIP_LOCALE`.
- Tooltip hooks: `GameTooltip:HookScript("OnTooltipSetUnit")`, `GameTooltip:HookScript("OnTooltipSetItem")`, plus Shopping and ItemRef tooltip hooks.
- Anchor override: `hooksecurefunc("GameTooltip_SetDefaultAnchor", ...)`.
- Late-refresh pattern: repaint after cached item data or Pawn data becomes available.
- Slash command bootstrap: `gearscore.lua` seeds the shared `/tacotip` handler early; later modules respect the existing `SlashCmdList.TACOTIP` guard.
- **Backdrop child-frame overlay (2.5.3+):** On TBC Anniversary 2.5.3+, GameTooltip uses a NineSlicePanel sub-frame for its backdrop. Direct `SetBackdrop`/`SetBackdropBorderColor` on the tooltip parent has no visual effect because NineSlice renders on top. The pattern is `getOrCreateBackdropFrame` in `main.lua`, which creates a separate `BackdropTemplate` child frame at `FrameLevel(2)` (above NineSlice, below text content). NineSlice stays visible for the default background; the overlay draws only the colored border edge via `SetBackdrop({edgeFile = ...})` + `SetBackdropBorderColor`. Border thickness is configurable via `TacoTipConfig.tooltip_border_edge_size` (default 16, range 4–48). Pre-2.5.3 clients use the original full-backdrop path unchanged.
- **`safeCall` error capture:** All GameTooltip script hooks, event handlers, and callback shims are wrapped in `xpcall(..., geterrorhandler(), ...)` so errors flow through Blizzard's error handler to BugSack/!Swatter instead of silently breaking tooltips.

## Wiring map

```mermaid
graph TD
 LibStub --> CallbackHandler[CallbackHandler-1.0]
 LibStub --> LibDetours[LibDetours-1.0]
 LibStub --> LCI[LibClassicInspector]
 CallbackHandler --> LCI
 LibDetours --> LCI

 LCI --> GearScore[gearscore.lua]
 LCI --> Pawn[pawn.lua]
 LCI --> Options[options.lua]
 LCI --> Main[main.lua]

 LibDetours --> GearScore
 LibDetours --> Pawn
 LibDetours --> Options
 LibDetours --> Main

 GearScore --> TT_GS
 Pawn --> TT_PAWN
 Options --> TacoTipConfig
 Options --> OpenOptionsPanel
 Main --> GameTooltipHooks
 Main --> TT_GS
 Main --> TT_PAWN
```

## Design notes to preserve

- `TacoTip.toc` must keep the library load order before the feature modules.
- The addon’s runtime depends on globals created by earlier files; changing order can break startup.
- Optional Pawn support should stay conditional rather than becoming a hard requirement.
- Tooltip layout behavior depends on config flags such as `tip_style`, `show_target`, `show_gs_player`, `show_pawn_player`, and the anchor settings.
