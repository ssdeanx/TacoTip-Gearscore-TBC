# WoW Classic / TBC Class Quickmaps

Use this file to jump directly to likely behavior ownership by class/feature.

## ASCII class routing map

```ascii
+----------------------------+
| Class issue reported       |
+----------------------------+
| Hunter ranged/cast window  | -> State + UI + ClassMods
| Shaman weave/breakpoints   | -> Weaving + ClassMods + UI
| Paladin twist overlays     | -> ClassMods + UI
| Rogue helper cues          | -> ClassMods + UI + Config
| Warrior utility helpers    | -> ClassMods + UI + Config
| Druid form/swing helpers   | -> ClassMods + UI + Config
+----------------------------+
```

## Hunter quickmap

- Start in: `SuperSwingTimer_State.lua`
- Then inspect: `SuperSwingTimer_UI.lua`, `SuperSwingTimer_ClassMods.lua`
- High-risk areas:
  - auto-repeat transitions
  - cooldown resync timing
  - cast vs channel handling
  - late window / helper visibility

## Shaman quickmap

- Start in: `SuperSwingTimer_Weaving.lua`
- Then inspect: `SuperSwingTimer_ClassMods.lua`, `SuperSwingTimer_UI.lua`
- High-risk areas:
  - cast progress source
  - breakpoint marker anchoring
  - spell-family icon/tint swaps
  - interruption cleanup

## Paladin quickmap

- Start in: `SuperSwingTimer_ClassMods.lua`
- Then inspect: `SuperSwingTimer_UI.lua`
- High-risk areas:
  - twist zone layer/alpha
  - reseal/judgement marker alignment
  - overlay visibility timing

## Rogue quickmap

- Start in: `SuperSwingTimer_ClassMods.lua`
- Then inspect: `SuperSwingTimer_UI.lua`, `SuperSwingTimer_Config.lua`
- High-risk areas:
  - helper bar anchoring/visibility
  - state polling cadence
  - compact helper layout collisions

## Warrior quickmap

- Start in: `SuperSwingTimer_ClassMods.lua`
- Then inspect: `SuperSwingTimer_Config.lua`, `SuperSwingTimer_UI.lua`
- High-risk areas:
  - next-attack/tank helper timing
  - helper bar dimensions/toggles

## Druid quickmap

- Start in: `SuperSwingTimer_ClassMods.lua`
- Then inspect: `SuperSwingTimer_Config.lua`, `SuperSwingTimer_UI.lua`
- High-risk areas:
  - form-dependent helper behavior
  - queue overlays and visibility rules

## Cross-class quick rule

If behavior reproduces on multiple classes, check shared state/render first
(`State.lua` / `UI.lua`) before class modules.
