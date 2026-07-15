# WoW Classic / TBC Compatibility Matrix

Use this file when you need branch-safe implementation choices.
It is intentionally practical, not exhaustive.

## How to use this matrix

- Treat this as a decision aid for coding, not a guarantee of every return value
  on every branch build.
- When in doubt, prefer wrappers and defensive unpacking.
- Verify uncertain items quickly on the active client build.

## ASCII decision map

```ascii
Need API behavior? -> Is it listed as Stable?
  |
  +-- YES: use normal path + targeted test
  |
  +-- NO/Watch:
      1) use wrapper/fallback extraction
      2) avoid hard-coded return indexes
      3) verify in active client branch
      4) keep branch-specific behavior isolated
```

Legend:

- **Stable**: behavior is generally consistent for addon work.
- **Watch**: behavior/signature details can vary by branch/build.

## Core timing APIs

| API | Classic Era / Anniversary | TBC Anniversary | Guidance |
| --- | --- | --- | --- |
| `CombatLogGetCurrentEventInfo()` | Stable | Stable | Use as authoritative CLEU source; unpack only needed fields. |
| `UnitAttackSpeed(unit)` | Stable for `"player"`, `"target"` | Stable for `"player"`, `"target"` | Use for MH/OH speed truth source. |
| `UnitRangedDamage(unit)` | Stable for player ranged speed | Stable for player ranged speed | Use first return (`speed`) for ranged cycle math. |
| `GetMeleeHaste()` | Stable | Stable | Good input for haste-aware melee adjustments. |
| `UnitSpellHaste(unit)` | Available on current Anniversary branches | Available on current Anniversary branches | Keep a fallback strategy if older assumptions are in legacy code. |
| `GetSpellCooldown(spell)` | Stable with update-lag caveat | Stable with update-lag caveat | Do not assume immediate update on the same cast-success frame. |
| `GetNetStats()` | Stable | Stable | Use `latencyWorld` for combat timing cushions. |

## Cast/channel APIs

| API | Classic Era / Anniversary | TBC Anniversary | Guidance |
| --- | --- | --- | --- |
| `UnitCastingInfo(unit)` | **Watch** (token fields can differ) | **Watch** (token fields can differ) | Keep spell-name fallback path; do not assume stable spellID presence in all code paths. |
| `UnitChannelInfo(unit)` | **Watch** (shape similar but not identical) | **Watch** (shape similar but not identical) | Handle channels separately; do not reuse cast-only assumptions blindly. |

## Event payload families to treat carefully

| Event family | Risk | Safe approach |
| --- | --- | --- |
| `COMBAT_LOG_EVENT_UNFILTERED` | variable-length payload by subevent | Parse shared prefix + subevent-specific fields only. |
| `UNIT_SPELLCAST_*` | arg shape can vary by branch/build and event | Use wrapper/helper extraction; rely on spell name fallback if token missing. |
| `START_AUTOREPEAT_SPELL` / `STOP_AUTOREPEAT_SPELL` | no payload, can be transient/noisy | Cross-check with current spell state/cooldown context before hard resets. |

## UI/tooling compatibility notes

| Topic | Guidance |
| --- | --- |
| Custom settings UI | Prefer Lua-first custom config panels for Classic/TBC compatibility. |
| Dropdowns | Use `UIDropDownMenu*` helpers for Classic-style config selectors. |
| Templates | Verify template existence/behavior on the target branch before depending on it. |
| Draw layering | Keep layer + sublayer explicit (`SetDrawLayer`) for reproducible overlap behavior. |

## Recommended wrapper strategy (strongly advised)

Create/addon-level wrappers for:

- cast/channel token extraction
- spell-name resolution (`GetSpellInfo` or branch-safe helper)
- time source (`GetTimePreciseSec` + alignment strategy)
- latency cache refresh and conversion to seconds

This keeps branch differences localized and reduces churn when API behavior shifts.

## ASCII wrapper architecture

```ascii
+-------------------------+
| Events / APIs           |
+-------------------------+
            |
            v
+-------------------------+
| Branch-safe wrappers    |
| - cast/channel normalize|
| - spell-name fallback   |
| - time-source normalize |
| - latency normalize     |
+-------------------------+
            |
            v
+-------------------------+
| Core state logic        |
+-------------------------+
            |
            v
+-------------------------+
| UI rendering            |
+-------------------------+
```

## Quick branch-safe coding checklist

- [ ] Did I avoid hard-coding an uncertain return index?
- [ ] Did I keep spell-name fallback when token/ID may be absent?
- [ ] Did I keep cast vs channel handling separate?
- [ ] Did I avoid relying on same-frame cooldown freshness?
- [ ] Did I test the behavior in the active client branch?
