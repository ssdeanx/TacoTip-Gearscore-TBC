# WoW Classic / TBC API Core Reference

Use this file when the task touches combat timing, casts, cooldowns, auras, or
latency-sensitive logic.

## ASCII timing model map

```ascii
+-------------------------+
| Combat events / APIs    |
+-------------------------+
| CLEU + attack speed     |
| cast/channel APIs       |
| cooldown hints          |
| latency sampling        |
+-------------------------+
            |
            v
+-------------------------+
| State timestamps        |
| (single clock domain)   |
+-------------------------+
            |
            v
+-------------------------+
| Predictive overlays     |
| (latency cushions)      |
+-------------------------+
            |
            v
+-------------------------+
| UI rendering            |
+-------------------------+
```

## Verified starting points

All API signatures below are confirmed against the local Blizzard FrameXML
mirror at `/home/sam/wow-ui-source/` (use the `classic_anniversary` branch for
this project). Read the exact doc with:
`git -C /home/sam/wow-ui-source show classic_anniversary:Interface/AddOns/Blizzard_APIDocumentationGenerated/API_<Name>.lua`

- Combat log: `CombatLogGetCurrentEventInfo()` — `Blizzard_APIDocumentationGenerated/API_CombatLogGetCurrentEventInfo.lua`
- Melee speed: `UnitAttackSpeed(unit)` — `Blizzard_APIDocumentationGenerated/API_UnitAttackSpeed.lua`
- Ranged speed: `UnitRangedDamage(unit)` — `Blizzard_APIDocumentationGenerated/API_UnitRangedDamage.lua`
- Casting: `UnitCastingInfo(unit)` — `Blizzard_APIDocumentationGenerated/API_UnitCastingInfo.lua`
- Channeling: `UnitChannelInfo(unit)` — `Blizzard_APIDocumentationGenerated/API_UnitChannelInfo.lua`
- Spell haste: `UnitSpellHaste(unit)` / `GetMeleeHaste()` — `Blizzard_APIDocumentationGenerated/API_UnitSpellHaste.lua`
- Cooldowns: `GetSpellCooldown(spell)` — `Blizzard_APIDocumentationGenerated/API_GetSpellCooldown.lua`
- Latency: `GetNetStats()` — `Blizzard_APIDocumentationGenerated/API_GetNetStats.lua`

## Combat log

### `CombatLogGetCurrentEventInfo()`

- Returns the current `COMBAT_LOG_EVENT_UNFILTERED` payload.
- The payload is variable-length.
- The shared leading fields are followed by event-specific extras.
- For swing logic, `SWING_DAMAGE` and `SWING_MISSED` are the usual white-hit
  anchors.
- Do not blindly unpack more values than you need.

Example pattern:

```lua
local timestamp, subevent, _, sourceGUID, _, _, _, destGUID = CombatLogGetCurrentEventInfo()

if subevent == "SWING_DAMAGE" or subevent == "SWING_MISSED" then
    -- handle white-hit timing here
end
```

## Swing-speed APIs

### `UnitAttackSpeed(unit)`

- Returns `mainSpeed, offSpeed`.
- The local Blizzard source explicitly verifies `"player"` and `"target"` usage.
- This should usually be treated as the current melee-speed truth source.

### `UnitRangedDamage(unit)`

- Returns `speed, minDamage, maxDamage, posBuff, negBuff, percent`.
- The first return is the ranged attack speed.
- The function is mainly relevant to `player` and sometimes `pet`; do not assume
  arbitrary units are valid.

### `GetMeleeHaste()` / `UnitSpellHaste(unit)`

- `GetMeleeHaste()` is useful for melee timing adjustments.
- `UnitSpellHaste("player")` is the spell-haste-aware path for cast breakpoint
  math.
- The local Blizzard source notes `UnitSpellHaste` was added for Classic in 1.15.3, so keep
  fallback thinking available for older-era assumptions.

## Casting and channels

### `UnitCastingInfo(unit)`

- Use for cast-time spells.
- Returns cast start/end timestamps in milliseconds.
- The local Blizzard source notes `notInterruptible` may be `nil`.
- Spell identity can vary across clients; name-based fallback remains useful.
- Do not use it as the only source of truth for channels.

Typical returns include:

- `name`
- `displayName`
- `textureID`
- `startTimeMs`
- `endTimeMs`
- `isTradeskill`
- `castID`
- `notInterruptible`
- `spellID` or equivalent spell token, depending on branch behavior

### `UnitChannelInfo(unit)`

- Use for channels such as Volley-style behavior.
- Has a similar shape to `UnitCastingInfo()` but not identical field semantics.
- Always verify the exact return positions before reusing cast-only code.

## Cooldowns and GCD-aware logic

### `GetSpellCooldown(spell)`

- Returns `startTime, duration, enabled, modRate`.
- The local Blizzard source notes cooldown values may not be updated immediately on the same
  `UNIT_SPELLCAST_SUCCEEDED` frame.
- Spell `61304` is the common GCD probe when you need the global cooldown.
- Good for reactive start/resync hints, but not always the only authoritative
  state source.

### ASCII cooldown caveat

```ascii
Cast success
  |
  v
[same frame] cooldown may still look old
  |
  v
[next frame(s)] cooldown usually reflects update
```

## Latency and clocking

### `GetNetStats()`

- Returns `bandwidthIn, bandwidthOut, latencyHome, latencyWorld`.
- `latencyWorld` is usually the gameplay-relevant value for combat timing.
- Cache it and refresh it while latency-sensitive bars are active.

### `GetTimePreciseSec()` and `GetTime()`

- Use one clock domain consistently.
- `GetTimePreciseSec()` is ideal for frame-accurate motion.
- `GetTime()` is still valid if the addon already uses it consistently.
- Do not mix clock domains carelessly, especially when cached timestamps are
  compared over multiple frames.

## Practical Classic/TBC rules

- White-hit timing, cast timing, and channel timing are separate domains.
- Predictive windows can use latency cushions; authoritative swing timestamps
  should usually stay on the addon's actual clock.
- A cooldown start event is not the same thing as a hit-landed event.
- If the client does not provide a stable spell ID in an event path, keep a
  spell-name fallback.
- Verify target-unit support on any API before using it for enemy helpers.
