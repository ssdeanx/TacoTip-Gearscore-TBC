# WoW Classic / TBC Operator Cheatsheet

Use this file in live coding/debug sessions when you need fast, high-signal
routing in under 60 seconds.

## ASCII fast route

```ascii
+-------------------------------+
| Problem type?                 |
+-------------------------------+
| API/event correctness         | -> api-core.md + event-payload-cheatsheet.md
| Branch/client variance        | -> compatibility-matrix.md
| UI/widget/layer behavior      | -> ui-frames-and-widgets.md
| XML/template confusion        | -> framexml-and-xml.md
| Combat-only / taint symptoms  | -> runtime-safety.md
| In-game verification steps    | -> verification-playbooks.md
| Repo architecture navigation  | -> superswingtimer.md
+-------------------------------+
```

## Top APIs (high-frequency)

- `CombatLogGetCurrentEventInfo()`
- `UnitAttackSpeed()`
- `UnitRangedDamage()`
- `GetMeleeHaste()`
- `UnitSpellHaste()`
- `UnitCastingInfo()`
- `UnitChannelInfo()`
- `GetSpellCooldown()`
- `GetNetStats()`
- `GetTimePreciseSec()` / `GetTime()`

## Top event families (high-risk)

- `COMBAT_LOG_EVENT_UNFILTERED`
- `UNIT_SPELLCAST_*`
- `START_AUTOREPEAT_SPELL` / `STOP_AUTOREPEAT_SPELL`
- `UNIT_ATTACK_SPEED`
- `PLAYER_TARGET_CHANGED`

## Most common failure patterns

- Cooldown value used too early on cast-success frame
- Cast/channel logic merged incorrectly
- Hard-coded payload index assumptions across branches
- UI region exists but hidden by layer/alpha/anchor/parent visibility
- Optional overlay logic mutates authoritative timer state
- Combat-only breakage from secure/protected path constraints

## 30-second triage checklist

- [ ] Which event family is failing?
- [ ] Is this branch/client variance or logic regression?
- [ ] Is failure combat-only?
- [ ] Is authoritative state wrong, or only rendering wrong?
- [ ] Which single file owns this subsystem?

## File-level routing (SuperSwingTimer)

- bootstrap/events/migration: `SuperSwingTimer.lua`
- constants/defaults/tuning: `SuperSwingTimer_Constants.lua`
- authoritative state/timer logic: `SuperSwingTimer_State.lua`
- shaman weave math/tracking: `SuperSwingTimer_Weaving.lua`
- rendering/apply/visibility: `SuperSwingTimer_UI.lua`
- class-specific behavior: `SuperSwingTimer_ClassMods.lua`
- `/sst` config UI controls: `SuperSwingTimer_Config.lua`

## First edit rule

Make the smallest edit in the file that owns the failing subsystem; avoid
cross-module quick fixes until root cause is confirmed.
