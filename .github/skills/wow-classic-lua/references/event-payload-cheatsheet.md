# WoW Classic / TBC Event Payload Cheatsheet

Use this file for high-risk payload parsing.
Goal: reduce wrong-index bugs and Retail-assumption mistakes.

## ASCII parsing flow

```ascii
+-----------------------+
| Incoming event        |
+-----------------------+
           |
           v
+-----------------------+
| Identify family       |
+-----------------------+
   |        |        |
   |        |        +--> AUTOREPEAT -> mode signal -> state/cooldown cross-check -> reset decision
   |        +-----------> UNIT_SPELLCAST_* -> gate unit -> cast/channel split -> name fallback
   +--------------------> CLEU -> shared prefix -> subevent branch -> tail parse
```

## 1) `COMBAT_LOG_EVENT_UNFILTERED`

Authoritative source:

```lua
local timestamp, subevent, hideCaster,
      sourceGUID, sourceName, sourceFlags, sourceRaidFlags,
      destGUID, destName, destFlags, destRaidFlags = CombatLogGetCurrentEventInfo()
```

Shared-prefix rule:

- The first 11 values above are the common prefix.
- Additional values depend on `subevent`.
- Never assume one fixed tail shape for all subevents.

### ASCII CLEU layout

```ascii
[1..11] shared fields
    1 timestamp
    2 subevent
    3 hideCaster
    4..7 source block
    8..11 dest block

[12..N] subevent-specific tail
    SWING_*  -> swing-specific values
    SPELL_*  -> spellId/spellName/school + result-specific values
```

### White-hit timing (swing)

Commonly used subevents:

- `SWING_DAMAGE`
- `SWING_MISSED`

Safe pattern:

```lua
local _, subevent, _, sourceGUID = CombatLogGetCurrentEventInfo()
if subevent == "SWING_DAMAGE" or subevent == "SWING_MISSED" then
    -- update swing state
end
```

### Spell-hit timing

Commonly used subevents:

- `SPELL_DAMAGE`
- `SPELL_MISSED`
- `SPELL_CAST_START`
- `SPELL_CAST_SUCCESS`

Safe pattern:

- Branch by subevent first.
- Only read spell fields for spell subevents.
- Use defensive extraction (`select`) if you only need specific tail values.

## 2) `UNIT_SPELLCAST_*` family

Important practical note:

- Exact argument shape can differ by event and branch/build.
- Do not hard-assume Retail payload shape.

Common events:

- `UNIT_SPELLCAST_START`
- `UNIT_SPELLCAST_STOP`
- `UNIT_SPELLCAST_DELAYED`
- `UNIT_SPELLCAST_INTERRUPTED`
- `UNIT_SPELLCAST_SUCCEEDED`
- `UNIT_SPELLCAST_CHANNEL_START`
- `UNIT_SPELLCAST_CHANNEL_UPDATE`
- `UNIT_SPELLCAST_CHANNEL_STOP`

Safe parser pattern:

```lua
frame:SetScript("OnEvent", function(_, event, unit, castToken, spellToken)
    if unit ~= "player" then
        return
    end

    -- Keep spell-name fallback if spell token is absent/unstable.
    local castName = nil
    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_DELAYED" then
        castName = UnitCastingInfo("player")
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
        castName = UnitChannelInfo("player")
    end
end)
```

### ASCII cast/channel split

```ascii
+------------------------------------------+
| UNIT_SPELLCAST_START / DELAYED           |
| -> UnitCastingInfo("player")             |
+------------------------------------------+
| UNIT_SPELLCAST_CHANNEL_START / UPDATE    |
| -> UnitChannelInfo("player")             |
+------------------------------------------+
Never merge these paths blindly.
```

## 3) Auto-repeat events

Events:

- `START_AUTOREPEAT_SPELL`
- `STOP_AUTOREPEAT_SPELL`

Payload behavior:

- No event payload args to parse for spell identity.

Safe handling:

- Treat as mode-toggle signals, not final authoritative cycle outcome.
- Cross-check with current repeat state/cooldown context before resetting timers.

### ASCII autorepeat guard

```ascii
STOP_AUTOREPEAT_SPELL
   |
   +-- Is repeat actually off right now?
       |
       +-- yes -> allow reset/fade
       +-- no  -> keep cycle alive, wait for stronger signal
```

## 4) Target/weapon speed update events

Common events:

- `UNIT_ATTACK_SPEED`
- `PLAYER_TARGET_CHANGED`

Safe handling:

- `UNIT_ATTACK_SPEED` provides a `unit` arg; gate to relevant units.
- On target swap, reset/reseed enemy helper state from `UnitGUID("target")` and
  current target speed APIs as needed.

## 5) Minimal anti-footgun rules

- Parse by event first, fields second.
- Keep cast and channel logic separate.
- Prefer helper wrappers for uncertain payloads.
- Avoid binding unused locals from CLEU tails.
- If behavior regresses only on one branch, inspect payloads directly instead of
  guessing.
