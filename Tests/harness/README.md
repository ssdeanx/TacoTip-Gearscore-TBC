# Offline verification harness

Plain-Lua harnesses that load the real addon files against a mocked WoW
environment. They need no game client and no WoWUnit.

## Run everything

```bash
bash Tests/harness/run_all.sh
```

70 invocations across fifteen harness files and all five clients. Exits non-zero on
the first failing harness, and prints the failing invocation names.

The suite defaults to `lua5.1`, which is what WoW actually ships and therefore
the interpreter that matters. It is also measured green under `lua5.4`, as a
second opinion — override the interpreter with `LUA`:

```bash
LUA=lua5.4 bash Tests/harness/run_all.sh
```

Measured 2026-10-20 on this tree: **71/71 under `lua5.1`, 71/71 under
`lua5.4`, 71/71 under `luajit`.** Keep it that way — a 5.4 failure is either a real portability bug
in the addon or a broken mock, and both are worth knowing about. What the 5.4
run is *not* is a target: do not bend an assertion, an expected value, or a
`pcall` to make a 5.1-correct suite green on 5.4.

## Individual harnesses

Run from the addon root:

```bash
# client detection: family, bracket, mutual exclusivity, unknown-client handling
lua5.1 Tests/harness/detect_test.lua

# locale registry + selection + override, across all 11 locales
lua5.1 Tests/harness/locale_test.lua

# per-locale font filtering
lua5.1 Tests/harness/font_test.lua

# localized specialization names: the ruRU Monk / Demon Hunter / Evoker names
# are Blizzard's own Russian strings, not the German or English placeholders
lua5.1 Tests/harness/specname_test.lua

# full addon load, per client. args: <projectId> <iface> <slot4|slot7> <family> <bracket> <label> [pipeline]
lua5.1 Tests/harness/load_test.lua 2  11509 slot4 classicEra 200  ERA
lua5.1 Tests/harness/load_test.lua 5  20506 slot4 tbc        400  TBC
lua5.1 Tests/harness/load_test.lua 11 38002 slot4 titanforge 1000 TITANFORGE
lua5.1 Tests/harness/load_test.lua 1  16001 slot4 forever     200  FOREVER   pipeline
lua5.1 Tests/harness/load_test.lua 1  120105 slot4 retail    1000 RETAIL    pipeline

# options UI build + exercise. args: <projectId> <iface> <label> [pipeline] [legacy] [nosettings|nocolor|nosharedmedia]
lua5.1 Tests/harness/options_test.lua 2 11509 ERA
lua5.1 Tests/harness/options_test.lua 11 38002 TITANFORGE
lua5.1 Tests/harness/options_test.lua 1 120105 RETAIL pipeline
lua5.1 Tests/harness/options_test.lua 2 11509 ERA legacy nosettings
lua5.1 Tests/harness/options_test.lua 11 38002 TITANFORGE legacy nocolor nosharedmedia

# settings frame: every setting reachable, bound, persistent, resettable.
# args: <projectId> <iface> <label> <pipeline|legacy> <settings|nosettings> <pawn|nopawn> [debug]
# It drives the controls themselves rather than a hand-written mapping, so it runs
# as a 20-way matrix (5 clients x 2 registration paths x 2 Pawn states).
lua5.1 Tests/harness/settings_test.lua 2  11509 CLASSIC_ERA legacy settings pawn
lua5.1 Tests/harness/settings_test.lua 11 38002 TITANFORGE legacy settings pawn
lua5.1 Tests/harness/settings_test.lua 1  120105 RETAIL  pipeline settings pawn
lua5.1 Tests/harness/settings_test.lua 5  20506 TBC_ANNIV legacy nosettings nopawn

# main.lua tooltip pipeline, behavioural. args: <projectId> <iface> <label> [pipeline] [debug]
lua5.1 Tests/harness/tooltip_test.lua 2 11509 CLASSIC_ERA
lua5.1 Tests/harness/tooltip_test.lua 11 38002 TITANFORGE
lua5.1 Tests/harness/tooltip_test.lua 1 120105 RETAIL pipeline

# static talent table -> icon resolution, per expansion
lua5.1 Tests/harness/talent_check.lua 2 11509 CLASSIC_ERA
lua5.1 Tests/harness/talent_check.lua 5 20506 TBC_ANNIV
lua5.1 Tests/harness/talent_check.lua 11 38002 TITANFORGE

# batch 8: character / inspect pane refresh, instant-fade mode.
# args: <projectId> <iface> <label> [pipeline]
lua5.1 Tests/harness/batch8_pane_test.lua 2 11509 CLASSIC_ERA
lua5.1 Tests/harness/batch8_pane_test.lua 1 120105 RETAIL pipeline
```

## What each harness covers

| harness | asserts |
| --- | --- |
| `detect_test` | family + bracket per interface, flags mutually exclusive, Cata/Mists report unknown, `LibClassicInspector` alias |
| `locale_test` | 11 locales register, selection by client locale, `locale_override` wins, unknown falls back to enUS, key count |
| `specname_test` | the `ruRU` Monk / Demon Hunter / Evoker specialization names in `LibForeverInspector` are Blizzard's own Russian client strings, none of them appears anywhere in the `enUS` or the `deDE` list (the old German and English placeholders cannot come back), and the `enUS` and `deDE` tables are unchanged |
| `font_test` | CJK fonts hidden on non-CJK locales, Details fonts dropped everywhere |
| `load_test` | every file parses and loads, locale keys resolve, detected family/bracket match, pipeline-less clients register **zero** post-calls, and the **Pawn contract** holds on every client: `TT_PAWN` loaded, `GetScore(player)` does not raise, **nothing was written to the chat frame**, scale visibility is never probed, and every name passed to `PawnGetScaleColor` exists in that client's `PawnCommon.Scales` |
| `options_test` | all 4 option pages build, every widget/control/slider/swatch is created, `RefreshOptionsUI` and `OpenOptionsPanel` run, character + inspect overlays come up |
| `settings_test` | drives every control the build created and diffs `TacoTipConfig`, so it asserts **all 68 settings are reachable, each control writes only declared keys, values survive a save/load round-trip, out-of-range values are clamped, Reset configuration restores every default, and the correct registration API is used per client** — plus that the achievement-points and Pawn toggles are gated exactly where the feature is absent |
| `tooltip_test` | the enhancement pipeline produces GearScore / iLvl / spec lines for self, other player, hostile NPC and items; both delivery paths (script hook **and** data post-call); dual-spec point readouts per group with inline `\|T` talent icons, active group, and the "points are small integers, not fileIDs" invariant; the guild guard's install path (modern pair only, Classic family is a no-op), its **swallow**, and its two counting buckets; a raising `IsUnit` does not abort the unit render; a raising `SetWidth` / `DoInspect` is counted |
| `batch8_pane_test` | the character and inspect overlays repaint when their PANE opens (the frames that carry `hidden="true"` on every branch), exactly **one** inventory walk per pane open, the pending→ready transition repaints the open pane and a second callback does not walk again, the inspect refresh respects `InCombatLockdown()`, a raising character-pane refresh is counted and does not escape into the engine's item-load callback, and `/tacotip diag` prints the instant-fade mode in all three states |
| `talent_check` | the ported static talent table resolves real icon textures per expansion (Vanilla 18 / TBC 23 / WotLK 31 talents in Warrior tab 1) |

## Mocking notes worth keeping

These are properties of the mocks, not the addon. Changing them will silently
make every assertion in these files pass or fail for the wrong reason.

* `xpcall` **must** route errors to the handler. `main.lua` wraps every
  tooltip entry point in `safeCall`; a mock that swallows the error makes a
  crashing code path look like a clean early return.
* `table.wipe` must exist. Plain Lua 5.1 has no `table.wipe`, so without it
  every pooled-buffer path dies at its first `table.wipe`.
* `unpack` must be callable in the sandbox, on either interpreter. It is a
  global in Lua 5.1 but moved to `table.unpack` in 5.2, so each file that needs
  it resolves `local unpack = unpack or table.unpack` *before* the sandbox table
  is built. The `xpcall` trampolines unpack their saved varargs through it, and a
  nil there is close to silent: `safeCall` swallows the resulting error and the
  pipeline simply produces no lines, so a dozen assertions fail on an empty
  tooltip instead of naming the real cause. The addon itself must never use
  `table.unpack` — it does not exist in the 5.1 WoW runs — which is why
  `.luacheckrc` permits that field on `table` for the harnesses only.
* Read tooltip text through `GetLeftLine(i):GetText()`, never through the
  backing line records. In non-wide `tip_style` the addon *rewrites* existing
  lines with `left:SetText()` instead of appending, so record-based reads miss
  everything it wrote and `AddLine` call counts stay at zero.
* `CreateFontString` / `CreateTexture` must register the global name, or code
  that reads a well-known global (`PersonalGearScore`, …) sees nil.
* Assert one-shot initialisers by their *effect*, not by calling them.
  `TT:InitCharacterFrame` / `TT:InitInspectFrame` nil themselves out after
  running (`main.lua:2143`, `:2261`) because the normal refresh path invokes
  them.
* A pipeline client must have `GameTooltip.IsTooltipType` and
  `GetPrimaryTooltipData` — the addon probes for those to decide whether the
  data pipeline is live. Without them the post-calls are correctly not
  registered and the "pipeline" run silently exercises the legacy path instead.
* **Model the two talent surfaces separately.** The Classic family has
  `GetNumTalentTabs` and reads the icon from the library's **static** talent
  table (`CI:GetTalentInfoByClass`), with no `GetInspectSpecialization`; the
  modern clients have `GetSpecialization` / `GetInspectSpecialization` /
  `GetClassIDFromSpecID` / `GetNumSpecializationsForClassID`, a `Texture`
  overlay instead of a `|T` escape, and **no** `GetNumTalentTabs` at all.
  Giving both the same globals makes the modern talent path untested — which is
  how `GetTalentPoints` returned `0/0/0` on Retail and WoW Forever unnoticed.
* `locale_test.lua` needs a `LibStub` stub for `LibForeverInspector` to reach
  the Titanforge branch of the locale selector; it takes `family` for that.
* **Count assignment positions, not return positions, after `pcall`.** `pcall`
  prepends a boolean, so `local ok, _, _, _, points = pcall(f)` reads `f`'s
  *fourth* return. This is not theoretical: a `getTalentTabPoints` helper written
  this way read `icon` instead of `pointsSpent` and the tooltip printed icon
  fileIDs as talent points. The Classic path no longer reads points off a shim at
  all — it sums per-talent `rank` through `GetTalentInfo`, the way the working
  `LibClassicInspector` does. The model here keeps icon values 6-digit and ranks
  small so the two can never be confused again.
* **A mock that gives every widget every method hides every feature test built on
  one.** `GameTooltip` was handed `SetBackdrop` on all clients, so the guard
  `not GameTooltip.SetBackdrop` never fired anywhere and the `BackdropTemplateMixin`
  graft shipped to Retail unseen. Widget mocks now support `__absent`, a set of keys
  that must read as nil, and `load_test` uses it to model both real tooltip
  templates. This is the highest-leverage mock property to keep honest: any
  `if not frame.SomeMethod` in the addon is invisible until the mock reproduces the
  real absence. Note `__absent` must be read with `rawget` inside `__index`, or
  reading `t.__absent` recurses until the C stack overflows.
* **Model the client's real script set, and make `HookScript` throw.** The mock
  used to accept any script name, which is how `GameTooltip:HookScript("OnTooltipSetUnit", ...)`
  shipped: that script does not exist on Retail's tooltip template, and the real
  call raises at *file scope*, aborting the rest of `main.lua`. Widget mocks now
  carry a per-family `__scripts` table and `HasScript`, and `HookScript` raises
  *bad argument #2* for anything undeclared. Both `load_test` and `tooltip_test`
  assert which delivery path each family should end up on, rather than asserting
  the script hooks unconditionally.
* **A `CreateFrame` mock that accepts any string cannot catch a widget type passed
  as a frame type.** `CreateFrame("Texture", ...)` is invalid (`Texture` is created
  with `:CreateTexture()`), and the mock happily invented a frame. `tooltip_test`
  and `settings_test` now reject unknown frame types with the real
  *Unknown frame type* error. When adding a mock, ask what the real API *rejects*,
  not only what it returns.
* **A mock that gives every widget every method cannot catch a `Frame` method being
  called on a `Region`.** On Retail and WoW Forever a `Texture` is a `Region`, not
  a `Frame`, so `SetFrameLevel` / `GetFrameLevel` / `SetFrameStrata` /
  `GetFrameStrata` do not exist on it — in game, the specialisation-icon texture
  raised *attempt to call a nil value* on every unit tooltip while the
  `SetSize` / `SetPoint` on the two lines above it worked. `tooltip_test` now
  strips the frame-level pair from `Texture` and `FontString` widgets via
  `__absent`, which `__index` consults **before** the catch-all method table
  (consulted with `rawget`; reading it through `__index` would recurse). Only
  that split is removed, because it is the one the client actually demonstrated
  — a wider speculative removal is unverified and only manufactures failures.
  This is the general form of the rule above: a mock must reproduce what the real
  API *lacks*, not just what it returns.
* **A mock `hooksecurefunc` that never throws hides every unguarded file-scope
  hook.** The real one raises "attempt to hook a non-existent function" when the
  target global is absent, and an unguarded file-scope hook aborts the rest of
  the addon. `load_test`'s mock now raises, and takes an optional 8th argument
  naming a global to blank before load, so the guard is exercised rather than
  assumed. Same class as the `__absent` rule above: the mock has to reproduce the
  failure, not just the happy path.
* `settings_test` must sweep **every** widget, not just named ones.
  `createOptionsButton` is the one builder that does not default a global name
  (it matches the Classic reference), so "Reset configuration" is nameless and a
  named-only sweep never clicks it.
* Watch for the `a and b or true` trap when reading a control's enable state.
  A false middle term falls through to `or true`, so the "disabled" test passes
  for every control and the client-gating assertions silently pass for the wrong
  reason. Use a helper that returns `ctl:IsEnabled() ~= false` directly.
* The options UI **cascades**: a control is disabled while the setting it depends
  on is off. One pass therefore only reaches what is reachable from the default
  state, and "unreachable" means "its parent is off", not "unbound". Walk the
  dependency tree in rounds, re-opening the cascade before each control, or the
  sweep under-reports coverage.
* `onValueChanged` is declared `function(value)`, not `function(self, value)`.
  Calling it as a method writes the control itself into the config, and the next
  `string.format` on that value throws.
* `settings_test` finds the reset control by **behaviour**, not by label. Labels
  are localised, and Titanforge runs in Chinese, so an English string match finds
  nothing there. This also proves no second control silently wipes the config.
* A named frame must become a real global in the mock. `CreateFrame("Frame", "X")`
  defines `_G.X` in WoW; a mock that skips it makes every read of a well-known
  frame return nil.
* `ColorPickerFrame:SetupColorPickerAndShow` takes **one info table** and calls
  back through `info.swatchFunc` after reading `GetColorRGB()`. A positional mock
  never fires, and returning the *same* colour makes the swatch look like it binds
  to nothing.
* **Mock the API's rejections, not only its returns.** A mock that returns a
  benign value where the real API reports a problem hides the defect entirely.
  This has now bitten four times: `hooksecurefunc` was a no-op (hiding an
  unguarded `HookScript`); every widget got every method (hiding that a `Texture`
  is a `Region`); `CharacterModelFrame` was invented (hiding that Retail has no
  such frame); and Pawn's scale-name APIs returned `false` for an unknown scale
  where the real ones **print to chat**.
* **Mock the *channel* the real code writes to, not just an exception.** Pawn's
  `VgerCore.Fail` calls `VgerCore.Message` → `DEFAULT_CHAT_FRAME:AddMessage`; it
  does not raise, so `pcall` cannot suppress it. `load_test`'s Pawn mock therefore
  *writes to chat* rather than throwing, and the assertion is "nothing reached the
  chat frame". An exception-throwing mock would let the same bug pass by being
  swallowed by `pcall`.
* **Mock per-client API gating, not a merged union.** Pawn's `Pawn.toc` gates its
  two scale providers by game type (`AskMrRobot.lua` = mainline, so `"MrRobot"`;
  `ClassicHawsJon.lua` = classic, so `"Classic"`), so exactly one exists per
  client. `load_test` keys the mock off `pipeline`, which selects Retail and WoW
  Forever. Registering *both* providers everywhere would let the
  `MrRobot`-first bug and the `Classic`-only fix each pass on the client where
  they are wrong.
* **Mock a module's load gate too, or it never runs.** `pawn.lua` returns early
  unless a Pawn version global or the Pawn API exists. Only `settings_test` mocked
  any of them, so `load_test`, `options_test` and `tooltip_test` each loaded the
  file and fell straight out of it — the entire Pawn score path was untested for
  the whole release. `load_test` now mocks Pawn on all five families.
* **Do not assert talent-point numbers that the mock itself invented.** The
  exact return shape of Blizzard's `GetTalentTabInfo` shim varies with the
  `loadDeprecationFallbacks` CVar and a mock cannot settle it — asserting such
  numbers only proves the mock agrees with itself. What *is* asserted is the
  version-independent invariant: ranks are small integers, icon values are
  6-digit fileIDs, and the rendered readout must be the former and never the
  latter.

`slot4` vs `slot7` selects which `GetBuildInfo()` return position carries the
interface version. That is documented on Retail and WoW Forever but NOT on the
Classic branches, so both layouts are exercised to prove detection does not
depend on the answer.

`pipeline` models a client whose GameTooltip mixes in
`TooltipDataHandlerMixin` (Retail, Forever). Without it the harness models the
Classic-family tooltips, which do not -- the case that used to register a
post-call that never fired.

## The client source of truth: `wow-ui-source`

Every claim in this repository about what a client does -- which API exists on
which family, what a frame's `hidden` attribute is, what a namespace function
returns -- is checkable against Blizzard's own FrameXML, and the checkout lives
next to this repo:

    /home/sam/wow-ui-source

It is a git checkout with one branch per client family:

| branch | client |
| :--- | :--- |
| `origin/classic_era` | Classic Era / SoD (`11509`) |
| `origin/classic_anniversary` | TBC Anniversary (`20506`) |
| `origin/classic_titan` | WotLK Titanforge (`38002`) |
| `origin/forever` | WoW Forever (`16001`) |
| `origin/live` | Retail (`120105`) |

Read it without checking anything out (the working tree may be on any branch,
and it is never modified):

    git -C /home/sam/wow-ui-source show origin/classic_era:Interface/AddOns/Blizzard_GameTooltip/Classic/GameTooltip.lua
    git -C /home/sam/wow-ui-source grep -n 'FadeOut' origin/live -- '*.lua'

Two rules for using it, both learned the hard way:

* **A universal claim needs all five branches.** "Exactly four `StaticPopup`
  frames" or "no `GameTooltip.FadeOut` on the Classic family" is only evidence
  when every branch has been checked. One branch is an anecdote. Cite the
  branch list, or the claim is not evidence.
* **Absence of a consumer is not absence of an API.** `CanInspect` has no
  upstream consumer in the classic tree and is absent from the generated API
  docs -- but that does not make it nonexistent. Proof of absence is a
  whole-tree sweep plus the generated docs, not a grep that found no callers.

The mirror is also how a *mock* is checked: a mock's return arity and order
should match the client's, and the table below is the record of the ones that
were found wrong. It is kept here, rather than in a reviewer's head, because
every one of these was invisible to the suite -- the suite was green while the
mock and the client disagreed.

**The table is now executable.** `Tests/harness/mock_contract.lua` holds the
same facts as a data-driven contract -- per API: how many values the CLIENT
publishes, how many the mock is expected to publish, and the branch-qualified
mirror citation that established it -- and every harness that owns a contract
API measures its mock and fails when the two disagree. The table below is the
readable copy of that file; the contract is the authority.

The contract lives in the MAIN add-on's harness tree and is the single source
of truth for **both** add-ons: the Extras harnesses load it from
`ROOT .. "/../Tests/harness/mock_contract.lua"` (loaded loudly -- a missing
file raises rather than the assertion quietly disappearing) and assert their
own mocks against it. The Extras `rankbrowser_test.lua` pins the two Extras
arities (`GetSpecializationInfoByID`, `FauxScrollFrame_Update`); the Extras
`load_test.lua` pins `UnitClass`.

**A contract assertion must run where the mock is INSTALLED.** `options_test.lua`
had a block of assertions that landed after the results tally, so they were
recorded and never counted -- a revert proof caught it (the suite stayed green
with the production change removed). An assertion that cannot fail is not a
test.

## Mock fidelity table

| API | client (verified in the mirror) | mock | status |
| :--- | :--- | :--- | :--- |
| `GetClassAtlas(classFile)` | `SharedConstants.lua:44` -- `("classicon-%s"):format(className)`, no lowercasing | `load_test`, `rankbrowser_test` | exact |
| `C_Item.GetItemInfo(id)` | `ItemButtonTemplate.lua:187` -- `itemName, itemLink, itemQuality, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount, itemEquipLoc, itemTexture, ...` (19 values) | `gearscore_test` (11 values) | exact for every position the addon reads (#2 link, #3 quality, #4 level, #9 equip location) |
| `TooltipUtil.GetDisplayedUnit(tooltip)` | `TooltipUtil.lua:40` -- `name, unit, guid` | `tooltip_test` | exact |
| `GameTooltip:GetUnit()` | `Blizzard_PTRFeedback_Tooltips.lua:87` destructures **two** -- `name, unit` | `tooltip_test` (Classic path) | **was returning a third GUID value** -- the engine never returns one; the production branch reading it was unreachable in the real client |
| `Settings.RegisterCanvasLayoutCategory(frame, name)` | `Blizzard_Settings.lua:161` -- a plain function on a namespace table, called with a dot | `settings_test` | exact |
| `Settings.RegisterCanvasLayoutSubcategory(parent, frame, name)` | `Blizzard_Settings.lua:165` | `settings_test` | exact |
| `Settings.RegisterAddOnCategory(category)` | `Blizzard_Settings.lua:133` | `settings_test` | exact |
| `Settings.*` (same three) | as above | `options_test` | **was modelled with a phantom `self`** -- the first real argument landed in a dummy, and the recording table was never asserted on |
| `FauxScrollFrame_GetOffset` / `_SetOffset` | `SecureScrollTemplates.lua:236/:241` | `rankbrowser_test` | exact |
| `FauxScrollFrame_OnVerticalScroll` | `SecureScrollTemplates.lua:227` -- 4 params, `math.floor((value / itemHeight) + 0.5)` | `rankbrowser_test` | exact, including the rounding |
| `FauxScrollFrame_Update` | `SecureScrollTemplates.lua:158` -- the function body ends at **:224** with `return showScrollBar;` (**one** value: 1 or nil) on **all five** branches | `rankbrowser_test` | exact. An audit recorded this API as returning NOTHING and the mock as "returning a value the real function never returns"; the mirror says the opposite on both counts -- the function body ends at :224, not :222 -- so the CONTRACT was corrected and the mock left alone. Changing the mock to the audited shape would have made it LESS faithful. |
| `UnitClass(unit)` | `UnitUtil.lua:81` (live/forever) -- `localizedClassName, classToken, classID` (**3**); `InspectPaperDollFrame.lua:10` (Classic family) -- **2** | every MAIN harness, plus both Extras harnesses | **was one shape for five clients** (2 everywhere). Now per-family: 3 on the modern pair, 2 on the Classic family. The addon reads only #1/#2 today, so the gap was latent, not live. |
| `GetSpecializationInfoByID(id)` | `ClubFinder.lua:599` -- **7** values | `tooltip_test`, `detect_test`, `fileguard_test`, and the Extras `rankbrowser_test` | **was 4** (and 0 in two MAIN harnesses). The addon reads #2 (name) and #4 (icon) only; #5+ were latent gaps. |
| `GetPlayerInfoByGUID(guid)` | `ChatFrameUtil.lua:1007` -- #2 is `englishClass` | `gearscore_test`, `pawn_test` | exact |
| `CheckInteractDistance(unit, dist)` | `UnitPopupSharedUtils.lua:194` -- boolean first | `detect_test` | exact |
| `StaticPopup_Show(which, text1, text2, data, insertedFrame, customOnHide)` | `StaticPopup.lua:278` | no-op mock | compatible; the dialog's own behaviour is in-game only |
| `ItemMixin` method set | `Blizzard_ObjectAPI/Classic/Item.lua` -- `GetItemID`, `GetItemLink`, `IsItemDataCached`, `ContinueOnItemLoad`, ... | `gearscore_test`, `batch2_pawn_test` | a safe subset; no invented method |
| `C_Item.GetItemInfoInstant(link)` | `Blizzard_AuctionHouseSharedTemplates.lua:366` -- **the itemID is the FIRST return** | `tooltip_test` (returns the item ID); the other harnesses mock only the bare global | **was mocked as `nil` in every harness** -- accidentally faithful to the broken production read; the production read is namespace-first now and `tooltip_test` pins the ID (see the `main.lua` cold-path item request) |
| `GetItemInfoInstant` (bare global) | exists only as a `Blizzard_DeprecatedItemScript` alias on the three Classic branches; **absent on `forever` and `live`** | n/a | the production read was namespace-first after the fix |
| `C_PaperDollInfo.GetInspectGuildInfo(unit)` | `PaperDollInfoDocumentation.lua:95` (live) / `:104` (forever) -- **4** values: achievement points, member count, guild name, realm name | `tooltip_test` | exact. The **fourth** (the realm name) is nil for a player with no guild -- the precondition of Blizzard's own `InspectGuildFrame` defect, and the fact the guild guard reads to tell that defect from any other error. Pinned by the contract. |

`C_Item.GetItemInfoInstant`'s return order is the one to remember: itemID
first, and `select(4, ...)` is the equip slot (`CatalogShop_SharedUtil.lua:927`).
The addon reads the first; a future caller reading a name from it will be
reading a number.

