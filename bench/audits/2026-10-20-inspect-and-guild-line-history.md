# The right-click inspect frame and the guild line — 0.7.9 to 0.8.3

a history worth keeping, because the same trap keeps coming back. it is
recorded here once; `workshop.md` → "the invariants" points at it.

## what the player saw

- **right-click → Inspect on Retail crashed.** opening the inspect frame
  threw, and the frame died half-drawn.
- **inspecting a player with no guild rendered a blank inspect frame.**
- **another addon's tooltip line was erased** by ours on the next hover.

## the causes, and what is load-bearing now

**1 — Blizzard's own defect in the guild block of the inspect frame.**
`InspectGuildFrame_Update` (verified on `origin/live`,
`Blizzard_InspectUI/Mainline/InspectGuildFrame.lua:22`) formats the realm
name unguarded:

```lua
InspectGuildFrame.guildRealmName:SetFormattedText(INSPECT_GUILD_REALM, guildRealmName)
```

`guildRealmName` is nil for a player with no guild, `SetFormattedText` raises
on nil, and the frame dies mid-update. **this is Blizzard's bug, not ours** —
vanilla Retail does it too — but we inspect on hover, so we hit it constantly.

**the guard is load-bearing.** `main.lua:3941-3952` wraps
`_G.InspectGuildFrame_Update` so the known guildless-inspect error is
swallowed and the inspect survives. do not remove it, and do not narrow the
swallow to "only that one error" without keeping a catch-all underneath: the
error text varies by client and locale, so the classification asks the
client's own data (`C_PaperDollInfo.GetInspectGuildInfo`) instead of matching
a string. the two-bucket split (the guild case, and everything else with its
message) exists so a *different* error is never mislabelled as the guild one.

**install path matters.** the global only exists on live and forever, and
only after `Blizzard_InspectUI` — a **LoadOnDemand** addon — has loaded. the
guard therefore installs from the `ADDON_LOADED` handler for
`Blizzard_InspectUI`, and is a **no-op on the classic family**, which reaches
the same frame through `InspectGuildFrameMixin:Update()` (that branch guards
every value it formats). pins cover: the install path (modern pair installs,
classic is a no-op), the swallow (the guildless error does not escape to the
caller), and the two-bucket split.

**2 — our own line-index bookkeeping erased other addons' lines.** we write
the guild and level lines at fixed positions (index 2 and 3) and blank those
indices on the next clear. any addon that adds a line — Baganator's tracked
item amount, Details' item level — shifts every index after it, so the
remembered index then points at *their* line and the blank destroys it.

**the ownership proof is load-bearing.** `main.lua:615-628` blanks a line
**only if the text it finds there is still the text we wrote**
(`TacoTipGuildLineText`), and `main.lua:2392` records what we wrote. do not
blank by index alone. this is also why the guild line and the level line
carry their own remembered text.

**3 — right-click inspect stripped the paperdoll on Retail and WoW Forever**
(0.7.9): `InspectPaperDollItemSlotButton_Update` read a nil
`GetInventoryItemTexture`. the paperdoll code guards that path now.

## the trap that keeps coming back

a `OnShow` hook on the wrong frame. `PaperDollFrame` and
`InspectPaperDollFrame` carry **no `hidden` attribute** on any branch, so
their `OnShow` **never fires**; `CharacterFrame` and `InspectFrame` are hidden
by default, so theirs does. a hook that never fires looks exactly like a
working one until the thing it was supposed to refresh goes stale — which is
how the character pane ended up showing `0` for a score that had been
computed for an hour. see `workshop.md` → "what the client actually does".

## the other half of that era: the out-of-range popup

0.8.1 re-introduced it (asking for an out-of-range inspect), 0.8.2 fixed it
by requiring `CheckInteractDistance(unit, 1)` alongside `CanInspect`, and
0.8.3 removed the `CanInspect(unit, true)` call that made the *engine*
display the message. the range gate is an invariant — see `workshop.md`.
