# SuperSwingTimer Project Reference

Use this file when working inside the current repo or when you want a concrete
example architecture for a Classic/TBC swing-timer addon.

## ASCII architecture map

```ascii
+-------------------------------+
| SuperSwingTimer.lua            |
| bootstrap / events             |
+-------------------------------+
| Constants  | State  | Weaving |
| ClassMods  | UI     | Config  |
+-------------------------------+
```

## Project overview

SuperSwingTimer is a World of Warcraft Classic/TBC addon focused on swing timer
tracking and class-specific combat timing helpers.

It currently covers:

- melee MH/OH timers
- hunter ranged timing and Auto Shot helpers
- shaman weave timing / breakpoint helpers
- paladin seal-twist timing visuals
- rogue timing helpers
- warrior next-attack / utility helpers
- druid form-related swing helpers
- a custom `/sst` config panel with live preview

## Core file map

- `SuperSwingTimer.lua`
  - addon bootstrap
  - SavedVariables migration
  - slash commands
  - event registration
  - startup / init flow
- `SuperSwingTimer_Constants.lua`
  - spell IDs
  - class config
  - default SavedVariables
  - tuning constants
- `SuperSwingTimer_State.lua`
  - timer state
  - combat-log parsing
  - spellcast detection
  - latency refresh helpers
- `SuperSwingTimer_Weaving.lua`
  - shaman spell catalog
  - breakpoint math
  - cast tracking
- `SuperSwingTimer_UI.lua`
  - bar creation
  - textures, colors, spark, overlays
  - drag handling
  - show/hide and runtime apply functions
- `SuperSwingTimer_ClassMods.lua`
  - class-specific overlays and hooks
  - isolated per-class behavior
- `SuperSwingTimer_Config.lua`
  - `/sst` settings panel
  - quick controls
  - live preview and config rows

## Architecture rules already proven in this repo

- Keep core timer math in state, not in the UI module.
- Keep class-specific logic isolated in `SuperSwingTimer_ClassMods.lua`.
- Keep config creation and refresh logic in `SuperSwingTimer_Config.lua`.
- Keep visible runtime apply functions in `SuperSwingTimer_UI.lua`.
- Keep static spell / defaults / tuning values in `SuperSwingTimer_Constants.lua`.

## Timing model conventions

- Live bar motion uses `OnUpdate`.
- `C_Timer` is reserved for one-shot or low-frequency work.
- The addon prefers a `GetTimePreciseSec()` path aligned back to `GetTime()` via
  helper logic instead of mixing clocks ad hoc.
- Cached latency is used for predictive windows such as safe-stop or weave math,
  not as a blanket rewrite of authoritative swing timestamps.
- Main-hand, off-hand, ranged, and enemy timing should remain logically
  independent.

## API conventions used by this addon

- `CombatLogGetCurrentEventInfo()` for combat-log white-hit events
- `UnitAttackSpeed()` for melee speed
- `UnitRangedDamage()` for ranged speed
- `GetMeleeHaste()` and `UnitSpellHaste()` for haste-aware timing
- `UnitCastingInfo()` and `UnitChannelInfo()` for cast/channel windows
- `GetSpellCooldown()` for cooldown-based timing hints
- `GetNetStats()` for latency cache refresh

## UI conventions used by this addon

- Custom bars are built with `CreateFrame()` and `StatusBar`.
- Overlays and markers are separate texture regions, not hacked into the fill.
- Draw layer matters for sparks, helper zones, and breakpoint markers.
- The config panel is a custom scrollable Classic/TBC-safe panel.
- The project prefers live preview behavior for color, texture, size, and
  visibility changes.

## Project rules when adding a new setting

Update all of these together:

1. `ns.DB_DEFAULTS`
2. SavedVariables migration in `SuperSwingTimer.lua`
3. Runtime apply function in `SuperSwingTimer_UI.lua`
4. Config controls in `SuperSwingTimer_Config.lua`
5. Documentation such as `README.md`
6. Addon metadata in `SuperSwingTimer.toc`

ASCII setting-change pipeline:

```ascii
DB default
  |
  v
migration
  |
  v
runtime apply
  |
  v
config control
  |
  v
docs
  |
  v
toc/version
```

## Current doc files worth checking

- `docs/APIS.md`
- `docs/UI.md`
- `docs/FrameXML.md`
- `docs/Widgets.md`
- `docs/swingtimer.md`
- `docs/paladintwistbar.md`
- `README.md`
- `AGENTS.md`

## Transferable patterns for other addons

- Separate state, rendering, config, and class/feature modules.
- Keep per-frame updates localized and narrow.
- Put helper overlays on dedicated texture regions or overlay frames.
- Favor explicit draw-layer decisions over trying to fix overlap with ad hoc
  alpha tweaks.
- Use scrollable config panels for larger option sets.
- Keep fallback wrappers for APIs that vary slightly across Classic/TBC clients.

## Current feature highlights

- Hunter support includes Auto Shot timing helpers and cast-window logic.
- Shaman support includes live weave-breakpoint helpers.
- Paladin support includes seal-twist timing visuals.
- Rogue support includes compact helper cues instead of bloated secondary bars.
- Warrior and druid support keep class-specific helpers isolated from the shared
  timer core.

## Practical warning

SuperSwingTimer is a strong reference project, but it is still specialized.
When reusing ideas in another addon, copy the architectural pattern first, not
the exact combat assumptions.
