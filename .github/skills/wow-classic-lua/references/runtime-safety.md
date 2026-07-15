# WoW Classic / TBC Runtime Safety Reference

Use this file when the issue smells like taint, combat-lockdown restrictions,
secure frame behavior, SavedVariables lifecycle timing, or performance pressure.

## ASCII runtime-safety triage map

```ascii
Bug observed
  |
  +-- only in combat?
  |      -> taint/protected-action audit first
  +-- only after reload?
  |      -> SavedVariables init/migration order
  +-- only under load?
         -> OnUpdate/perf guardrails
```

## 1) Secure/protected behavior and combat lockdown

Practical rules:

- Assume protected action paths are restricted in combat.
- Avoid changing protected attributes during combat.
- If a change works out of combat but fails in combat, suspect secure/taint
  issues first.
- Keep timer bars and config UI fully non-secure where possible.
- Avoid unnecessary coupling between combat-critical logic and optional UI
  helpers.

Symptoms that often indicate taint/combat-lockdown issues:

- clicks or actions silently blocked only in combat
- Blizzard action UI behaving oddly after addon UI changes
- behavior recovers after `/reload` but breaks again when specific UI paths run

## 2) SavedVariables lifecycle

Use this event flow intentionally:

- `ADDON_LOADED` for initializing your addon's SavedVariables table
- `PLAYER_LOGIN` for final setup that needs the full UI environment

ASCII lifecycle:

```ascii
ADDON_LOADED
  |
  v
defaults + migration
  |
  v
PLAYER_LOGIN
  |
  v
frame/setup paths needing full UI
```

Practical rules:

- Guard every new key with defaults and migration logic.
- Keep migration idempotent (safe to run once per login without double-applying).
- Do not assume config panel widgets exist at SavedVariables init time.

## 3) Performance guardrails

- Prefer event-driven updates for state transitions.
- Use `OnUpdate` only for motion that genuinely needs frame-by-frame updates.
- Throttle non-critical `OnUpdate` work.
- Avoid allocating large temporary tables inside hot loops.
- Reuse frames and texture regions instead of creating replacements repeatedly.

A good pattern:

- state changes on events
- rendering reads state each frame only when a visible timer is active
- hide/disable per-frame handlers when idle

ASCII perf pattern:

```ascii
Event changes state
  |
  v
Active timer?
  |
  +-- yes -> lightweight OnUpdate render
  +-- no  -> stay event-driven
  |
  v
Idle state -> disable OnUpdate
```

## 4) Timing accuracy guardrails

- Keep one clock domain for stored timer timestamps.
- Use latency as predictive offset math, not as a replacement clock.
- Avoid UI-only fallback code mutating authoritative combat state.
- Verify cast vs channel handling before reusing spell timing code.

## 5) Debug flow for "works except in combat" bugs

1. Reproduce with minimal UI interaction.
2. Disable optional helper overlays and test core timer path first.
3. Confirm whether the break starts exactly on combat entry.
4. Audit recent secure-frame interaction and protected-attribute changes.
5. Re-enable helpers one by one to find the taint trigger.

## 6) SuperSwingTimer-specific reminders

- Keep state in `SuperSwingTimer_State.lua` and rendering in
  `SuperSwingTimer_UI.lua`.
- Keep class-specific behavior isolated in `SuperSwingTimer_ClassMods.lua`.
- When adding visible config features, update defaults + migration + UI apply +
  config rows together.
- Validate in-game with `/sst`, combat entry/exit, and lock/unlock drag flow.
