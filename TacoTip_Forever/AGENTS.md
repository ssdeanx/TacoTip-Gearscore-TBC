# AGENTS.md — TacoTip

## What this is

A WoW tooltip enhancement — GearScore, item level, talents and specializations,
class colours, a 3D portrait and a health/power bar — running unchanged across
five clients. One codebase, one release, no per-client forks.

The hard part is not the feature set. It is that the five clients do not agree
on how a tooltip is built, and every compatibility bug in this project traces
back to an assumption that one of them was the standard.

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
- **The two template chains differ below the shared result.** All five end up
  with a `NineSlice` child, but `GameTooltipTemplate` carries
  `mixin="GameTooltipMixin"` on the Classic branches and
  `mixin="GameTooltipDataMixin"` on mainline, and only the Classic chain
  inherits `TooltipBackdropTemplate`. So the tooltip *itself* exposes
  `SetBackdropColor` / `SetBackdropBorderColor` on Classic and **not** on
  Forever or Retail.

**Never call those methods on the tooltip.** Write to the
`TacoTipBackdropFrame` overlay the addon creates itself with the
`BackdropTemplate` template — `Backdrop.xml` is loaded by all five, so that
works everywhere.

## Reaching a client's source

`/home/sam/wow-ui-source`, one branch per client. Always `origin/`-qualified;
the local names alone are not branches, and reading one returns nothing.

| | |
| :--- | :--- |
| Classic Era | `git grep -n "PATTERN" origin/classic_era` |
| TBC Anniversary | `origin/classic_anniversary` |
| WotLK Titanforge | `origin/classic_titan` |
| WoW Forever | `origin/forever` |
| Retail | `origin/live` |

Two traps: `origin/forever` exists only as a remote ref, so a bare `forever`
silently returns nothing and looks like an absence. And `git grep` counts
*call sites*, not definitions — a hit proves Blizzard uses a name, never that
it exists on the branch you are reading. Confirm with `git show`, or read the
XML element.

## Reading Blizzard's XML

`inherits` is transitive and runs through every template, so "does this frame
have method X" is answered by walking the chain to the root and checking
`mixin=` at each level — not by grepping for the method. Prefer
`git show origin/<branch>:<path>` and read the element.

Grepping `<On[A-Za-z]+>` is **not** sufficient for script names. It only matches
self-closing tags and silently misses every `<OnHide function="...">` form,
which produces a table of scripts that looks plausible and is wrong. Match
`<On` and read the element.

## Layout

```
main.lua       3259  tooltip pipeline, portrait, borders, hooks
options.lua    2671  settings UI, both registration APIs
textures.lua    640  SharedMedia resolution, font filtering
gearscore.lua   527  score + item level
pawn.lua        223  Pawn scale colour
Libs/LibForeverInspector.lua   client detection, talent/spec data
```

`main.lua` is last in the toc, and `TacoTip_CustomPosEnable` is defined at line
3013 of 3259 — an error before that line kills the mover as well as every
feature after it, and the symptom is a tooltip that looks completely stock. The
file records `TT.LOAD_STAGE` at ten points and sets `TT.LOAD_OK` at the end:

```
core → backdrop-mixin → unit-hook → item-hooks → tooltip-hooks
     → visual-clearing → anchor-hook → status-bar → mover-defined → complete
```

`/tacotip diag` reports the last stage reached. **When a feature is missing on
one client, run the diagnostic before reading code** — it names the stage in one
command instead of bisecting 3000 lines.

## Tests

```
bash Tests/harness/run_all.sh
```

51 invocations: five clients × both `GetBuildInfo` layouts × both settings
registration paths × both Pawn states, plus permutations that blank a Blizzard
global to prove the file-scope hooks are guarded. Exits non-zero and names the
failing invocation.

In game: `Tests/TacoTipTests.toc` → `/tttest`. Three harnesses cover what
mocks cannot: Pawn's real chat-write behaviour, frame timing, async model
loads, alpha.

### A green suite has lied four times

Not hypothetically — in this release, each of these shipped broken with 50/50
passing:

- **`load_test` mocks Classic as having no `NineSlice`.** The FrameXML
  contradicts it. So **the suite cannot catch a border regression on Classic**,
  and "50/50" does not mean the border works there. This is the top item in the
  changelog's *Still outstanding* list.
- **The recycle test asserted the opposite contract** (that a non-unit recycle
  *preserves* the model), so it passed while the portrait was blinking on
  screen.
- **The portrait test drove the unit hook**, which early-returns when the
  tooltip has no lines — true in the mock, never true in game, so it never
  reached the code it claimed to test.
- **The mock handed every widget every method**, hiding that a `Texture` is a
  `Region` and has no `SetFrameLevel`.

Every fix is reverted to confirm the test **fails**, then restored. A test that
has only ever passed is not evidence.

Prefer asserting observable behaviour over implementation shape. A contract
written down wrongly will be encoded into a test and will then protect itself.
Note that `TooltipDataProcessor` existing proves nothing about TBC or
Titanforge: both define it, but neither mixes `TooltipDataHandlerMixin` in, so
registered postcalls never fire. `dataPipelineActive` tests
`IsTooltipType` / `GetPrimaryTooltipData`, which come from the mixin itself.

## Working rules

- **Do not infer an API surface from a loose grep.** Read the element, or read
  the definition. An inferred table that looked reasonable was wrong twice in
  this release — once for `OnShow`/`OnHide` (missed by a self-closing-tag
  pattern) and once for `GameTooltip:UpdateTooltip` (grepped as a call site;
  it is an optional hook Blizzard guards for and defines nowhere).
- **Change one thing, then get a command that shows it working.** Reverting to
  confirm a test bites is the fastest honest check available.
- **If a test fails for the wrong reason, fix the test, not the code** — and
  say so in the changelog.
- **Record wrong turns in the changelog**, not just the final state. The next
  person will otherwise repeat them.
- **Never call `tooltip:GetUnit()` unguarded**, and never assume a global is
  declared: `GetQuestDifficultyColor`, `IsEquippableItem` and
  `GetTalentTabInfo` are all CVar-gated or deprecation shims that can be nil.
  Prefer `C_Item.IsEquippableItem`; resolve the others per call.
- **An item load completing is not a unit change.** `TacoTip_GSCallback` re-enters
  the pipeline via `SetUnit` for the *same* character. Guard state changes on
  the unit's GUID, and keep teardown and visibility in the same branch.
- **The `## Interface:` line decides whether the addon loads at all.** Titanforge
  was listed as `38001` (3.80.1) against a real 3.80.2 and did not load.
- **Version bump:** `.toc`, `main.lua` `addOnVersion`, `options.lua`, `README.md`
  and `CHANGELOG.md` together. Current: **0.7.8**, unreleased.
- **The toc filename must equal the addon folder name.** WoW requires it. The
  folder is `TacoTip_Forever/`; the toc is `TacoTip.toc` so the packaged addon
  installs as `TacoTip` and takes over the existing addon's identity.

## Current state

Portrait blink and stray spec icon are fixed but the icon fix is **incomplete**
— the modern overlay still duplicates the inline icon, and `hasDualSpec` still
claims dual spec on single-spec modern clients. Portrait alpha is still slaved
to the tooltip's, and the portrait is still re-anchored every render. The
`load_test` mock is still wrong. **None of the portrait work has been confirmed
in a live client.** See `CHANGELOG.md` → *Still outstanding*.

## Inspector regression coverage

`Tests/harness/inspect_test.lua` loads the real library for all five profiles.
Preserve manual-inspect priority, bounded GUID queues/retries and independent
inventory/talent timestamps. Run the suite against the original implementation
to confirm regressions fail. Offline success does not establish live-client timing.
