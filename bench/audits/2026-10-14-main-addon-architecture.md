# TacoTip (core add-on) — architecture audit

- **subject:** how the main add-on works end to end: load order, module contracts,
  the inspect → tooltip pipeline, the scoring model, and the invariants that are
  load-bearing
- **date:** 2026-10-14
- **author:** `tacotip` desk
- **anchored to:** `5bc83b7` with a dirty working tree (the 2026-10-14 event-path
  and range fixes are uncommitted; line numbers were read from the dirty tree and
  are accurate for it)
- **status:** VERIFIED throughout unless a line says otherwise; see *unknowns*
- **supersedes:** nothing

## why this exists

A session arriving cold has to be able to change this add-on **without breaking
five client families**. This is the map: what loads, in what order, what each file
owns, where the data comes from, and which rules are load-bearing rather than
stylistic.

## scope

**In:** `TacoTip.toc`, `main.lua`, `gearscore.lua`, `pawn.lua`, `textures.lua`,
`options.lua`, `Locale/`, `Libs/`, `Tests/harness/`.

**Out (deliberately):** the companion add-on (its own audit), packaging and
versioning (`release` desk), Blizzard-API questions (`api-verification` desk),
options-page-by-page layout, and in-game behaviour that only the operator can
observe.

## the system

### Load order — `TacoTip.toc` (VERIFIED)

    1  Libs/LibStub                      5  Locale/deDE … zhTW (10 locales)
    2  Libs/CallbackHandler-1.0          6  Locale/enUS          ← last of the locales
    3  Libs/LibDetours-1.0               7  gearscore.lua
    4  Libs/LibForeverInspector          8  pawn.lua → textures.lua → options.lua → main.lua

`enUS` is last **because it defines and runs the merge**:
`_G.TacoTipApplyLocale()` is defined at `Locale/enUS.lua:340` and called at
`:377`; every other locale file registers its table first, and the merge fills
`_G.TACOTIP_LOCALE` (239 keys in `Locale/enUS.lua`, which is the source of truth).
`main.lua` is last because it hooks frames and consumes what all of the above
published. `pawn.lua` is listed before `textures.lua` in the file, and its own
first act is to **return early** unless Pawn is usable.

### Client families (VERIFIED)

Five clients are claimed: `11509` Classic Era, `20506` TBC Anniversary, `38002`
Titanforge/Wrath, `16001` WoW Forever, `120100` Retail. Family detection lives in
the bundled inspector (`LibForeverInspector`: `lib.family`,
`lib:IsClassic/IsTBC/IsWotlk/IsForever/IsRetail/IsUnknown`), pinned by
`detect_test.lua` against a scenario matrix that includes a Forever client
reporting `WOW_PROJECT_MAINLINE` and the real "camelot" constant set.

The family changes real behaviour in at least three places:

| where | classic family | mainline (Forever/Retail) |
|---|---|---|
| item-level bracket (`gearscore.lua:147-157`) | 200 (Classic Era), 400 (TBC) | 200 (Forever), 1000 (Rest/unknown) |
| inspect range gate (`lib:CanInspect`) | `CanInspect` **and** `CheckInteractDistance(unit, 1)` | either signal suffices |
| tooltip driver (`main.lua`) | tooltip frames declare `OnTooltipSetUnit` → hook it | frames declare neither → `TooltipDataProcessor.AddTooltipPostCall`, else a portable `OnUpdate` driver |

`MAX_SCORE = BRACKET_SIZE * 7` (`gearscore.lua:157`).

### Module contracts (VERIFIED, by reading the surfaces)

- **`gearscore.lua`** (575 lines) — owns scoring. Surfaces: `TT_GS.BRACKET_SIZE`,
  `TT_GS.MAX_SCORE`, `TT_GS:GetQuality(score)` (returns `r, g, b, label` from the
  `GS_Quality` band table), `TT_GS:GetItemScore(itemLink)`,
  `GetItemScoreFromInfo`, `GetItemHunterScore`, and the one everyone reads:
  `TT_GS:GetScore(unitorguid, useCallback)` (`:405`). Item-data loading is
  throttled through a local `RequestLoadItemDataByID` (`:103`).
- **`pawn.lua`** (227 lines) — optional by construction: it returns at file scope
  unless Pawn is present and usable (`PawnClassicLastUpdatedVersion >= 2.0538`,
  `PawnLastUpdatedVersion >= 2.0`, or the API trio `PawnGetItemData` /
  `PawnGetSingleValueFromItem` / `PawnGetScaleColor`). Exposes `TT_PAWN`.
- **`textures.lua`** (472 lines) — the built-in media lists
  (`TT.builtinTooltipFonts`, statusbar textures, backgrounds, borders) that the
  options page and the optional SharedMedia integration draw from.
- **`options.lua`** (2851 lines) — `DEFAULTS`, a repair pass that re-fills
  partially-corrupt config keys on every load, the **dual-path** registration
  (modern `Settings.RegisterCanvasLayoutCategory` + `RegisterCanvasLayoutSubcategory`
  when present, legacy `InterfaceOptions_AddCategory` otherwise), three child
  pages (Tooltips / Positioning / Character & Inspect), slash commands, and the
  language selector that writes `TacoTipConfig.locale_override`.
- **`main.lua`** (3845 lines) — the renderer: tooltip driver, appearance, per-unit
  line building, character/inspect frames, power bar, tooltip mover, diagnostics
  (`TT:PrintDiagnostics`).
- **`Locale/`** (11 files) — copy-merge fallback described above.
- **`Libs/`** — `LibStub`, `CallbackHandler-1.0`, `LibDetours-1.0`,
  `LibForeverInspector` (which also registers the legacy `LibClassicInspector`
  alias at minor 2).

### The inspect → tooltip pipeline (VERIFIED)

1. The tooltip hook fires (post-call on mainline, `OnTooltipSetUnit` on classic),
   resolves the unit, and calls the inspector's `DoInspect` inside a `pcall`
   (`main.lua:1594`).
2. `LibForeverInspector` decides whether to ask at all — distance pre-filter,
   per-GUID cooldown, learned range ceiling, `canInspect` — then sends
   `NotifyInspect` from exactly **one** call site.
3. `INSPECT_READY` fills the per-GUID cache and fires `INVENTORY_READY` /
   `TALENTS_READY`. `main.lua` subscribes to both (`main.lua:3576-3577`).
4. On render, lines are built from the cache into **pooled buffers**
   (`pooledLinesToAdd`, `pooledTooltipText`) and appearance is applied per show
   (`TT:ApplyTooltipAppearance`, `main.lua:1028`).

### Scoring model (VERIFIED, surfaces only)

`TT_GS:GetQuality(score)` walks `i * BRACKET_SIZE < score <= (i+1) * BRACKET_SIZE`
for `i = 0..6` and returns the band's colour and label; anything outside falls back
to grey/"Trash". Item score inputs are item level, equip location and rarity
(`scoreFromItemValues`, `gearscore.lua:267`) — the weights themselves were **not**
audited here, and `gearscore_test.lua` pins values rather than the formula.

## gates & invariants

Each of these is load-bearing: violating one has already produced a bug.

1. **`HasScript` before every `HookScript`** (`main.lua:2317-2350`). Retail and
   Forever tooltips declare neither `OnTooltipSetUnit` nor `OnTooltipSetItem`;
   hooking unconditionally threw at *file scope* and aborted the rest of
   `main.lua`. Evidence: the comment block is the incident report; the helper
   attempts every frame rather than short-circuiting.
2. **Forward-declare anything the file-scope `OnEvent` handler references.** A
   `local` is only in scope from its declaration onward, so a reference above it
   compiles as a *global* lookup — `LibForeverInspector` raised
   `attempt to call global 'isCloseEnoughToAsk'` on every player target and hover
   until 2026-10-14. Evidence: reproduction + the new `detect_test` event-path
   cases.
3. **The classic family gates on distance, mainline does not.** `lib:CanInspect`
   requires both signals on the classic family; `detect_test.lua` pins both
   halves per family.
4. **`NotifyInspect` has one call site, and the gate lives there.** Callers may
   not bypass `requestInspect`; the in-flight fix added the classic
   `CheckInteractDistance` re-check at that choke point.
5. **The tooltip hot path allocates nothing per hover** — pooled line buffers and
   cached media resolution (`TT:InvalidateResolvedMediaCache` is the invalidation
   hook, not a rebuild-per-hover).
6. **Non-unit tooltips must not inherit unit visuals**: `clearTooltipVisuals` is
   nil-safe (`tooltip.GetName`) and resets portraits/models/borders on every
   show/clear transition.
7. **Level colour is a rule, not a preference**: friendly players render white;
   `GetQuestDifficultyColor` applies only to units you can attack.
8. **Event handlers return early when their surface is hidden** (power bar,
   `UNIT_TARGET`).

## verification map

| area | covered by |
|---|---|
| loads on all five clients, two `GetBuildInfo` layouts | `load_test` (10 invocations) + the missing-global robustness cases |
| family detection, invariants, range gates, the real event path | `detect_test` |
| options registration (modern, legacy, no colour picker) | `options_test` (7) |
| settings reachability/binding/persistence | `settings_test` (20) |
| GearScore *values* | `gearscore_test` (3 clients) |
| tooltip pipeline | `tooltip_test` (5 clients) |
| locales, textures, fonts, talent table | `locale_test`, `textures_test`, `font_test`, `talent_check` |
| in-game truth | the desk checklists (operator run) |

Total: 54 invocations, `bash Tests/harness/run_all.sh`.

## unknowns

- **Pawn's path is untested** (open item 9): no harness case loads `pawn.lua` with
  a mocked Pawn, so "Pawn works" rests on its version/API gate alone.
- **`dataPipelineActive(GameTooltip)` per client** was not traced in this audit;
  the code hedge (both drivers registered, `handleTooltipSetUnit` idempotent) is
  what makes the question non-blocking.
- **`LibDetours-1.0`'s runtime role** was not followed; it is a bundled library
  and may be unused by the current code path.
- **Item-score weights** are out of scope above; `gearscore_test` pins values, not
  the formula.
- Whether the injected `TacoTipConfig.locale_override` path survives a locale
  *removal* was not tested.

## how to keep this honest

    cd /home/sam/TacoTip-Gearscore-TBC
    git rev-parse --short HEAD
    wc -l main.lua gearscore.lua options.lua textures.lua pawn.lua
    grep -c '\["' Locale/enUS.lua
    bash Tests/harness/run_all.sh
