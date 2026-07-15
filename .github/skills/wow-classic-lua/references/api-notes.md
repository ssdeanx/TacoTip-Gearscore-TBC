# WoW Classic Lua Quick Notes

This file is the fast-entry checklist.
Use the other reference files for the full details.

## ASCII quick-start map

```ascii
+-----------------------+
| Need answer fast?     |
+-----------------------+
| API behavior/timing   | -> api-core.md
| UI/widgets/layers     | -> ui-frames-and-widgets.md
| XML/templates/FrameXML| -> framexml-and-xml.md
| runtime taint/perf/SV | -> runtime-safety.md
| branch differences    | -> compatibility-matrix.md
| event parsing details | -> event-payload-cheatsheet.md
| in-game test steps    | -> verification-playbooks.md
| operator triage route | -> operator-cheatsheet.md
| class ownership map   | -> class-quickmaps.md
| first 5 min incident  | -> incident-first-5-minutes.md
+-----------------------+
```

## Start here

- API and timing details: `api-core.md`
- `CreateFrame`, widgets, layers, and handlers: `ui-frames-and-widgets.md`
- XML, templates, and Blizzard source: `framexml-and-xml.md`
- current external links: `research-links.md`
- current repo architecture: `superswingtimer.md`
- live incident routing: `operator-cheatsheet.md`
- class-specific jump map: `class-quickmaps.md`
- bug triage first five minutes: `incident-first-5-minutes.md`

## Fast rules

- Confirm Classic/TBC API signatures before relying on memory.
- Keep white-hit timing, cast timing, channel timing, and UI drawing separate.
- Use `OnUpdate` for live bar motion; use `C_Timer` for one-shot or low-frequency work.
- Reuse frames where possible.
- Keep draw-layer decisions explicit.
- Treat cached latency as predictive math, not as a reason to rewrite every base timestamp.

## Most-used APIs

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

## Most-used UI entry points

- `CreateFrame()`
- `Frame:SetScript()`
- `Frame:RegisterEvent()`
- `Frame:CreateTexture()`
- `Frame:CreateFontString()`
- `StatusBar:SetStatusBarTexture()`
- `LayeredRegion:SetDrawLayer()`

## Common gotchas

- `GetSpellCooldown()` is not always immediately updated on the same cast-success frame.
- `UnitCastingInfo()` and `UnitChannelInfo()` are related, but not interchangeable.
- `OnUpdate` stops when the frame or its parent is hidden.
- A visible frame can still have an invisible region because of alpha, anchors, draw layer, or frame strata.
