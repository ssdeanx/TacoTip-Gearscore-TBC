# Tech Context

## Runtime

- Lua addon for World of Warcraft Classic-family clients only.
- Supported interface versions: `11508`, `20505`, `30405`, `38001`.
- `30405` (Wrath Classic) is carried forward on trust from prior releases; its API surface is **unverified** (no WotLK FrameXML branch exists in the local `wow-ui-source` reference to diff against).
- Saved variable: `TacoTipConfig`.

## Bundled libraries and manifests

- `Libs/LibStub/LibStub.lua` + `LibStub.toc` — core library registry.
- `Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua` + `CallbackHandler-1.0.xml` — callback registry support.
- `Libs/LibDetours-1.0/LibDetours-1.0.lua` + `LibDetours-1.0.toc` — secure hook / detour helper.
- `Libs/LibClassicInspector/LibClassicInspector.lua` + `LibClassicInspector.toc` + `API.txt` — inspection API and reference docs.

## Mandatory runtime dependencies

- `LibStub`
- `LibClassicInspector`
- `LibDetours-1.0`
- `CallbackHandler-1.0` via `LibClassicInspector`

## Optional runtime dependency

- Pawn support, detected via `PawnClassicLastUpdatedVersion >= 2.0538` **OR** presence of Pawn's public API (`PawnGetItemData` / `PawnGetSingleValueFromItem` / `PawnGetScaleColor`). The API-presence fallback is required because SoD-era Pawn does not expose `PawnClassicLastUpdatedVersion`.

## Configuration defaults

Defaults returned by `TT:GetDefaults()`:

- `color_class = true`
- `show_titles = true`
- `show_guild_name = true`
- `show_guild_rank = false`
- `show_talents = true`
- `show_gs_player = true`
- `show_gs_character = true`
- `show_gs_items = false`
- `show_gs_items_hs = false`
- `show_avg_ilvl = true`
- `hide_in_combat = false`
- `show_item_level = true`
- `tip_style = 2`
- `show_target = true`
- `show_pawn_player = false`
- `show_team = false`
- `show_pvp_icon = false`
- `guild_rank_alt_style = false`
- `show_hp_bar = true`
- `show_power_bar = false`
- `instant_fade = false`
- `anchor_mouse = false`
- `anchor_mouse_world = true`
- `anchor_mouse_spells = false`
- `inspect_gs_offset_x = 0`
- `inspect_gs_offset_y = 0`
- `inspect_ilvl_offset_x = 0`
- `inspect_ilvl_offset_y = 0`
- `character_gs_offset_x = 0`
- `character_gs_offset_y = 0`
- `character_ilvl_offset_x = 0`
- `character_ilvl_offset_y = 0`
- `unlock_info_position = false`
- `show_achievement_points = false`
- `tooltip_border_edge_size = 16`

## APIs used

- `GameTooltip`, `ShoppingTooltip1`, `ShoppingTooltip2`, and `ItemRefTooltip` hooks.
- `GameTooltip_SetDefaultAnchor` override via `hooksecurefunc`.
- `CreateFrame`, `SetScript`, `RegisterEvent`, `Settings` / legacy interface options registration.
- Unit, faction, class, power, map, and combat APIs (`UnitClass`, `UnitGUID`, `UnitIsPlayer`, `UnitFactionGroup`, `UnitPower`, `UnitPowerMax`, `GetBestMapForUnit`, etc.).
- Item APIs and async item-load callbacks (`GetItemInfo`, `ContinueOnItemLoad`, `RequestLoadItemDataByID`).
- `C_Timer.NewTicker` for the power bar refresh loop when available.

## Caveats

- Wide and mini tooltip layouts: the LIVE tooltip still expands hybrid styles (2/4) on Shift via `main.lua`; the OPTIONS PREVIEW is settings-only and shows each style's default layout (no `IsShiftKeyDown` dependency).
- Some data may not be available until inspection or item cache finishes, so refresh callbacks matter.
- `LibClassicInspector/API.txt` is reference material; the `.lua` file is the source of truth.
- Pawn support remains optional and should never be assumed in code paths or docs.
