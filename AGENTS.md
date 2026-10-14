# AGENTS.md — TacoTip

## Precedence

**When anything in this file contradicts the repo, the repo wins.** Record the
disagreement in `bench/OPEN-ITEMS.md` and fix this file.

A false instruction is followed just as reliably as a true one, so a wrong claim
here gets executed with confidence rather than ignored.

**The rule exempts derivable facts only.** The five-client table and the FrameXML
traps below are *not* derivable from this repo — that knowledge lives in an
external mirror — so there the mirror wins and verification is required.

**Keep this file to invariants, traps and reasoning. Do not put current state,
defect lists, row numbers, line numbers, file counts or version numbers in it** —
they go stale, and a stale claim in this file is followed rather than checked.
Current facts live in `CHANGELOG.md` and `bench/OPEN-ITEMS.md`; name the symbol
and let the reader grep it.

## What this is

A WoW tooltip enhancement — GearScore, item level, talents and specializations,
class colours, a 3D portrait and a health/power bar — running unchanged across
five clients. One codebase, one release, no per-client forks.

The hard part is not the feature set. It is that the five clients do not agree
on how a tooltip is built, and every compatibility bug in this project traces
back to an assumption that one of them was the standard.

## Where a session starts

1. **`CAIRN.md`** — the operating disposition. Evidence vocabulary (**VERIFIED** /
   **ASSUMED** / **UNKNOWN**; label every claim you write down), the workshop map,
   and the precedence ladder for when sources disagree. A decision needing a rung
   below the third is a hands-up.
2. **`bench/OPEN-ITEMS.md`** — the register of what is **not** resolved: one row
   per item with an owning desk, a risk, and a closing condition. Read it before
   starting, not only before calling work done. Rows are **closed, never deleted**;
   closing means reproducing the condition, writing the evidence into the owning
   desk's journal, *then* setting the status.
3. **Your desk's journal** — `desks/tacotip`, `desks/extras`, `desks/api-verification`,
   `desks/release`. Newest entry at the top, append-only; a correction is a *new*
   entry saying what it supersedes. A desk is created, never overwritten.

**Write the journal entry before the session ends**, including a session that
produced nothing but a dead end. It is the only memory that survives.

Then per task: `bench/audits/` for the architecture map and the API-verification
procedure, `bench/README.md` for bench conventions.

**Working with other sessions:** another desk's files are not yours — leave a note
in *their* journal rather than editing them. Overlapping claims are a hands-up, not
a race. One desk, one focus. A version bump touches every file that carries a
version string; nothing machine-pins TacoTip's, so check all of them before and
after.

Anything known to be broken lives in `bench/OPEN-ITEMS.md` — **not here**. If you
find a defect, add a row rather than writing it into this file, because a claim
here gets followed whether or not it is still true.

## The five clients

| Client | `WOW_PROJECT_ID` | Interface | FrameXML template chain to `NineSlice` |
| :--- | :--- | :--- | :--- |
| Classic Era | 2 (`WOW_PROJECT_CLASSIC`) | 11509 | `GameTooltipTemplate` → `TooltipBackdropTemplate` |
| TBC Anniversary | 5 (`WOW_PROJECT_BURNING_CRUSADE_CLASSIC`) | 20506 | same as Classic Era |
| WotLK Titanforge | 11 (`WOW_PROJECT_WRATH_CLASSIC`) | 38002 | same as Classic Era |
| WoW Forever | 1 (`WOW_PROJECT_MAINLINE`) | 16001 | `SharedTooltipTemplate` → `SharedTooltipArtTemplate` |
| Retail | 1 (`WOW_PROJECT_MAINLINE`) | 120100 | same as WoW Forever |

Two things fall out of this table and both have cost real time:

- **Forever and Retail share a project ID.** Only the interface band separates
  them — Forever is the sole client in 16000–19999, so the split is
  `isForever = MAINLINE and 16000 <= interface < 20000`.
- **The two template chains differ below the shared result.** All five end up with
  a `NineSlice` child, but `GameTooltipTemplate` carries `mixin="GameTooltipMixin"`
  on the Classic branches and `mixin="GameTooltipDataMixin"` on mainline, and only
  the Classic chain inherits `TooltipBackdropTemplate`. So the tooltip *itself*
  exposes `SetBackdropColor` / `SetBackdropBorderColor` on Classic and **not** on
  Forever or Retail.

**Never call those methods on the tooltip.** Write to the `TacoTipBackdropFrame`
overlay the addon creates itself with the `BackdropTemplate` template — `Backdrop.xml`
is loaded by all five, so that works everywhere.

## Reaching a client's source

`/home/sam/wow-ui-source`, one branch per client. Always `origin/`-qualified; the
local names alone are not branches, and reading one returns nothing.

| | |
| :--- | :--- |
| Classic Era | `git grep -n "PATTERN" origin/classic_era` |
| TBC Anniversary | `origin/classic_anniversary` |
| WotLK Titanforge | `origin/classic_titan` |
| WoW Forever | `origin/forever` |
| Retail | `origin/live` |

Two traps: `origin/forever` exists only as a remote ref, so a bare `forever`
silently returns nothing and looks like an absence. And `git grep` counts *call
sites*, not definitions — **a hit proves Blizzard uses a name, never what an
argument means, and never that it exists on the branch you are reading.** Confirm
with `git show`, or read the XML element.

## Reading Blizzard's XML

`inherits` is transitive and runs through every template, so "does this frame have
method X" is answered by walking the chain to the root and checking `mixin=` at
each level — not by grepping for the method. Prefer
`git show origin/<branch>:<path>` and read the element.

Grepping `<On[A-Za-z]+>` is **not** sufficient for script names. It only matches
self-closing tags and silently misses every `<OnHide function="...">` form, which
produces a table of scripts that looks plausible and is wrong. Match `<On` and read
the element.

## Load order

`main.lua` is **last in the toc**, and `TacoTip_CustomPosEnable` is defined at its
very end. An error before that point kills the mover *and* every feature defined
after it — and the symptom is deceptive, because `options.lua` loads earlier and
keeps working, so the player sees a stock tooltip with a fully functional options
panel.

`main.lua` records `TT.LOAD_STAGE` at ten points and sets `TT.LOAD_OK` at the end:

```
core → backdrop-mixin → unit-hook → item-hooks → tooltip-hooks
     → visual-clearing → anchor-hook → status-bar → mover-defined → complete
```

`/tacotip diag` reports the last stage reached. **When a feature is missing on one
client, run the diagnostic before reading code** — it names the stage in one
command instead of bisecting the file.

## Tests

```bash
bash Tests/harness/run_all.sh
```

Five clients × both `GetBuildInfo` layouts × both settings registration paths ×
both Pawn states, plus permutations that blank a Blizzard global to prove the
file-scope hooks are guarded. Exits non-zero and names the failing invocation. Read
the count from its output rather than trusting one written down anywhere.

In game: `Tests/TacoTipTests.toc` → `/tttest`. Covers what mocks cannot — Pawn's
real chat-write behaviour, frame timing, async model loads, alpha.

### A green suite has lied five times

Each of these shipped broken with the full suite passing. Keep the shape when you
add to this list: name the test, what it asserted, what was actually true.

- **`load_test` mocks Classic as having no `NineSlice`.** The FrameXML contradicts
  it, so **the suite cannot catch a border regression on Classic** and a green run
  does not mean the border works there.
- **The recycle test asserted the opposite contract** (a non-unit recycle
  *preserves* the model), so it passed while the portrait blinked.
- **The portrait test drove the unit hook**, which early-returns when the tooltip
  has no lines — true in the mock, never in game — so it never reached the code it
  claimed to test.
- **The mock handed every widget every method**, hiding that a `Texture` is a
  `Region` and has no `SetFrameLevel`.
- **`portraitHide` counted teardowns, not `Hide()` calls** — it sat inside a guard
  the hide did not. Lifting the hide out of that guard, the exact shape of the bug,
  left both tests named for it green on all five clients.

Every fix is reverted to confirm the test **fails**, then restored. A test that has
only ever passed is not evidence. Prefer asserting observable behaviour over
implementation shape: a contract written down wrongly gets encoded into a test and
then protects itself.

Note that `TooltipDataProcessor` existing proves nothing about TBC or Titanforge —
both define it, but neither mixes `TooltipDataHandlerMixin` in, so registered
postcalls never fire. `dataPipelineActive` tests `IsTooltipType` /
`GetPrimaryTooltipData`, which come from the mixin itself.

## Working rules

Each rule names a failure that actually happened. When you add one, record the
outcome too — rationale with no outcome hands the next session an unvalidated
premise to extend.

- **Do not infer an API surface from a loose grep.** Read the element or the
  definition. *Shipped a fix for the wrong bug twice: `OnShow`/`OnHide` (missed by
  a self-closing-tag pattern) and `GameTooltip:UpdateTooltip` (grepped as a call
  site; it is an optional hook Blizzard guards for and defines nowhere).*
- **Change one thing, then get a command that shows it working.** *Two of this
  release's fixes were found by reverting a correct-looking change and watching
  the suite stay green — which is what exposed the wrong contract.*
- **If a test fails for the wrong reason, fix the test, not the code** — and say so
  in the changelog. *`local ok, err = _G.NotifyInspect, unit` assigns instead of
  calling, so the suite stayed green with the fix deleted.*
- **Record wrong turns in the changelog, not just the final state.** *The
  `CanInspect(unit, true)` entry is still there describing itself as the fix,
  immediately followed by its correction. Editing it out would leave a reader
  finding the correction with no way to know what it corrects.*
- **Never call `tooltip:GetUnit()` unguarded**, and never assume a global is
  declared: `GetQuestDifficultyColor`, `IsEquippableItem` and `GetTalentTabInfo`
  are CVar-gated or deprecation shims that can be nil. Prefer
  `C_Item.IsEquippableItem`; resolve the others per call. *An unguarded raise
  aborts the render and the wrapper that catches it swallows the error — the
  feature is silently absent with nothing logged. This is why `/tacotip diag`
  exists.*
- **An item load completing is not a unit change.** `TacoTip_GSCallback` re-enters
  the pipeline via `SetUnit` for the *same* character. Guard state changes on the
  unit's GUID, and keep teardown and visibility in the same branch. *Same insight
  as the Classic unresolved path: nothing proved the character changed, so nothing
  may be torn down.*
- **The `## Interface:` line decides whether the addon loads at all.** *Titanforge
  was listed as `38001` against a real `38002` and the addon simply did not load —
  no error, no warning.*
- **Version bump:** `.toc`, `main.lua` `addOnVersion`, `options.lua`, `README.md`,
  `CHANGELOG.md` and `MEMORY.md` together. Do not write the current number here —
  read it from `TacoTip.toc`.
- **The toc filename must equal the addon folder name**, and exactly one `.toc`
  may ship. *A second, byte-identical `.toc` made WoW load the whole addon twice on
  every client and register the tooltip hooks twice.*

## Traps that outlive the bug that taught them

These are recorded here rather than in `CHANGELOG.md` because the *shape* of each
mistake recurs; the specific incident is in the changelog and the desk journals.

- **`CanInspect`'s second argument is `showError`, not a range flag.** Passing
  `true` asks the engine to *display* a message, and `CanInspect` never tested
  distance. A "range gate" that was written by reading a call site and inferring
  what the argument meant — it made the very popup it was written to prevent. The
  distance gate on the Classic family is `CheckInteractDistance(unit, 1)`, applied
  where `NotifyInspect` is actually called. **The transferable half: a call site
  proves a name is used; it says nothing about what an argument means.**
- **`isClassic` is not "build major is 1".** Classic Era's `GetBuildInfo()` puts
  `nil` in that slot, so the obvious check misclassifies the real Classic Era
  client and routes it into the modern branch. Identify clients from
  `WOW_PROJECT_ID`; use the interface number only to split Forever from Retail.
- **A promise made in a comment is a contract.** `clearTooltipVisuals`'s
  `retainModel` argument is documented as "the caller re-shows the portrait" — so
  the caller that asks to retain *must* re-show. That comment existed while the
  only caller did not, and the portrait stayed hidden for the rest of the show.
- **Structurally unreachable code still gets reasoned about.** The runtime range
  discovery read distance from an API documented on none of the five clients, so
  it never ran, and everything it was meant to prevent still happened.
- **A unit that cannot be identified has not changed.** On the Classic family the
  tooltip hook discards its arguments, so the GUID fallback that rescues this case
  does not exist there at all. "Nothing proved the character changed" must mean
  *tear nothing down*.

## Where things stand

Deliberately empty. Read `CHANGELOG.md` for what this release changed and what is
still outstanding, and `bench/OPEN-ITEMS.md` for what is unresolved and who owns
it. Do not copy either into this file — that is the failure mode the Precedence
section exists to prevent.
