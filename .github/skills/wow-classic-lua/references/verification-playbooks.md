# WoW Classic / TBC Verification Playbooks

Use these after edits to quickly confirm real in-game behavior.

## ASCII test ladder

```ascii
1) Global smoke test
   |
   v
2) Subsystem playbook (swing / hunter / shaman / config / taint)
   |
   v
3) Reproduce regression with minimal scenario
   |
   v
4) Capture triage template details
   |
   v
5) Patch + re-run ladder
```

## Global smoke test (run after any UI/state change)

1. `/reload`
2. Open config (`/sst`) and ensure panel opens cleanly.
3. Toggle one display setting and confirm live preview updates.
4. Enter combat and confirm bars/helpers follow combat visibility rules.
5. Leave combat and confirm idle/hide reset behavior.
6. Lock/unlock bars, drag, relock, `/reload`, and confirm anchor persistence.

## A) Swing timing playbook (MH/OH/ranged)

Use when touching timer math, haste handling, or reset logic.

Checklist:

- [ ] MH starts on first valid white swing event.
- [ ] OH is independent and does not restart incorrectly from MH events.
- [ ] Ranged cycle timing remains independent from melee timers.
- [ ] End-of-swing behavior does not show stale full bars.
- [ ] Latency-sensitive overlays move, but base swing timestamps stay stable.

Quick visual:

```ascii
White swing event
   |
   v
Timer seed
   |
   v
OnUpdate fill
   |
   v
Swing land -> timer end/reset
```

## B) Hunter ranged playbook

Use when touching auto-repeat, hidden window, or cast-window helpers.

Checklist:

- [ ] `START_AUTOREPEAT_SPELL` starts expected ranged behavior.
- [ ] Transient `STOP_AUTOREPEAT_SPELL` does not instantly nuke a valid cycle.
- [ ] Cooldown hints resync cleanly without forcing premature cycle resets.
- [ ] Steady/Aimed helper behavior matches current cast/channel state.
- [ ] Mounting or long movement does not create looped fake cycles.

Quick visual:

```ascii
Auto-repeat ON
   |
   v
Ranged cycle active
   |
   v
Transient stop?
   |
   v
Verify true state -> keep/reset
```

## C) Shaman weave playbook

Use when touching weave markers, cast timing, or spell-family visuals.

Checklist:

- [ ] Fixed markers stay at intended safe breakpoint.
- [ ] Moving icon/spark follows live cast progress.
- [ ] Spell-family icon/tint changes correctly (LB/CL/HW/LHW/CH as configured).
- [ ] Cast interruption/stop restores default weave visuals cleanly.
- [ ] Minimal mode and weave toggle both suppress visuals correctly.

Quick visual:

```ascii
Cast start
   |
   +-- fixed breakpoint markers remain
   +-- moving icon tracks cast progress
   +-- cast end/interrupt restores default visuals
```

## D) Config/UI layering playbook

Use when touching `/sst`, dropdowns, sliders, texture rows, or overlay layers.

Checklist:

- [ ] No overlapping rows/headers in expanded sections.
- [ ] Sliders and numeric boxes stay aligned after collapse/expand.
- [ ] Dropdown selection updates saved values and live preview.
- [ ] Color pickers open and apply alpha-aware values.
- [ ] Spark/marker layers remain readable over bar fills.

Quick visual:

```ascii
Row layout pass
   |
   v
Control alignment
   |
   v
Live preview
   |
   v
Layer readability check
```

## E) Combat-lockdown/taint playbook

Use when behavior fails only during combat.

Checklist:

- [ ] Out-of-combat behavior works as expected.
- [ ] In-combat behavior failure reproduces consistently.
- [ ] No protected attribute changes are attempted in combat.
- [ ] Optional helper overlays are disabled one-by-one to isolate taint trigger.
- [ ] Core timer logic remains functional even if optional overlays are off.

Quick visual:

```ascii
Works OOC?
   |
   +-- yes -> breaks in combat?
             |
             +-- yes -> inspect protected changes/taint first
```

## Fast bug triage template

When reporting verification results, include:

- class/spec tested
- zone/target context
- event path touched (e.g., CLEU swing, spellcast, auto-repeat)
- expected vs actual behavior
- whether issue is combat-only
- whether `/reload` temporarily clears it

This gives enough signal to fix most regressions quickly.
