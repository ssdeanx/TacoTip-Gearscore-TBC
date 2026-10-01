# Changelog — TacoTip

All notable changes to TacoTip are documented in this file.

## Unreleased — inspect queue restoration

- Restore bounded, GUID-keyed inspect requests in `LibForeverInspector`: up to
  20 queued players, a 2-second shared-channel delay, a 5-second response timeout,
  and at most 3 attempts before a 10-second cooldown. Queued requests resume after
  combat or manual inspection without another tooltip hover.
- Keep requests when their unit token temporarily disappears or `CanInspect`
  rejects/errors. Defer them for up to 15 seconds from the first unavailable
  queue check, rotating them behind other players; repeated hovers do not reset
  the deadline. Expired requests enter the same 10-second cooldown.
  Added five regression cases across all clients after review exposed this gap.
- Restore `CheckInteractDistance(unit, 1)` before each background `CanInspect`
  and `NotifyInspect` attempt. Out-of-range or unknown/restricted distance defers
  the request instead of repeatedly invoking APIs that can emit UI errors.
  Leave manual inspection and general UI error messages untouched. Regression
  tests model an `Out of Range` UI message rather than a caught Lua exception.
- Respect requests from Blizzard and other addons; never clear their shared
  inspect data. Resolve changing target/mouseover tokens by GUID, including party
  and raid units. No new automatic whole-group scanning is introduced.
- Refresh inventory on `UNIT_INVENTORY_CHANGED` without reading shared talent data.
  Empty/partial inventory does not become a fresh cache entry or erase old items;
  complete responses refresh the cache for 10 seconds. Keep separate talent and
  inventory timestamps and bound cache entries to 500 players.
- Keep the existing Classic/modern specialization paths. Increment the embedded
  library minor to 3; the addon release version is unchanged.
- Add asynchronous inspection regression tests for all five client profiles and
  make the offline harness portable (`TACOTIP_TEST_ROOT`, default current folder).
  The first local fix dropped throttled requests and treated an empty inventory
  as fresh for 30 seconds; these are now explicit regression cases.
- TBC Anniversary user testing confirmed that equipment loads progressively
  without hanging. Other clients have offline coverage only; their live behavior
  remains unverified. The later availability-deferral and range-guard fixes have offline coverage
  only. See `Tests/harness/README.md`.

| Version | Date | Summary |
| :--- | :--- | :--- |
| `0.7.8` | `2026-09-29` | **First cross-engine release, and the one that replaces the Classic-only addon.** Runs unchanged on all five client families — Classic Era / SoD, TBC Anniversary, WotLK Titanforge, WoW Forever and Retail. Rebuilt client detection, completed the localization registry, and corrected the WoW Forever GearScore bracket. Fixed the two defects that left Retail and WoW Forever running **half** the addon: an unguarded `HookScript("OnTooltipSetUnit", ...)` that raised at file scope because Retail's tooltip template does not declare that script, and `CreateFrame("Texture", ...)`, which is not a valid frame type, followed by `SetFrameLevel` on that texture — a `Frame` method that does not exist on a modern `Region`. Fixed the tooltip being loaded twice, the addon not loading on Titanforge, and stock Blizzard tooltips on TBC Anniversary and Titanforge. Fixed the tooltip backdrop mixin being grafted onto modern tooltips. Fixed the 3D portrait being destroyed and reloaded roughly twice a second while hovering a unit frame, and a stray specialization icon appearing on the wrong character. Resolved the Pawn scale library per client instead of guessing it, which had been spamming *ScaleName must be the name of an existing scale* on every character tooltip — the one defect `pcall` could not mask, because Pawn reports it by writing to the chat frame. Added `/tacotip diag` and an offline verification harness (50 invocations across all five clients). |
| `0.7.7` | `2026-09-21` | **Initial Universal Cross-Engine Release**: Complete 1:1 architectural port enabling TacoTip to run concurrently on WoW Forever (`16001`), Retail Live (`110002`–`120100`), WotLK Classic & Titanforge (`38001`), TBC Classic Anniversary (`20506`), and Classic Era / Season of Discovery (`11509`). Powered by `LibForeverInspector` with multi-client engine gating, adaptive quality brackets, universal Settings & ColorPicker API bridges, and zero-allocation tooltip pipeline. |

---

## [0.7.8] — 2026-09-29

> **This is the release that takes over the previous Classic-only TacoTip.** One
> addon, one version number, all five client families. `0.7.7` was never
> published.

### Fixed

- **The 3D portrait blinked while hovering a unit frame, on an unchanged
  character.** Reported in game as the portrait dropping and sliding back into
  frame roughly every half second, which is not how a genuine unit change
  behaves — and the same character blinking repeatedly is what identified it as
  a bug rather than the inherent cost of `PlayerModel`.

  **The model was never being reloaded.** `PlayerModel:SetUnit` loads a mesh
  asynchronously, so a genuine teardown-and-reload *would* be the obvious
  suspect, and the first fix went after it. That was wrong, and it is recorded
  here because the reasoning is the trap: the GUID-keyed cache on the portrait
  frame was working, `currentUnitGUID` was written once and never cleared, and
  for a same-character render nothing about the mesh needed to change.

  **What actually happened:** `Hide()` sat **outside** the destroy guard.

  ```lua
  if (tooltip.TacoTipPortrait3D) then
      tooltip.TacoTipPortrait3D:Hide()   -- ran for EVERY caller
      if (destroyModel) then ... end
  end
  ```

  A GearScore item load completes asynchronously and re-enters the whole tooltip
  pipeline through `TacoTip_GSCallback` → `GameTooltip:SetUnit` for the **same**
  character. `onTooltipSetUnit` correctly detected the unchanged GUID and asked
  to keep the model — but the frame was hidden regardless, and then re-shown by
  the next `ApplyTooltipAppearance`. The mesh never changed; the *frame* vanished
  and came back once per item that finished loading. With a `tooltip_delay` or
  the 0.05s border deferral in flight, the re-show lands after the hide, which is
  why it read as a drop and a slide rather than a flicker.

  **The fix:** `Hide()` moved inside the guard, and the third parameter was
  renamed `destroyModel` → `keepModel` so the default is the safe one — teardown.
  `onTooltipSetUnit` passes `(previousGUID ~= nil and previousGUID == guid)`,
  the same expression it already used, now meaning "keep" rather than "destroy".
  A same-unit re-render is now a complete no-op for the portrait.

  **A resident-model leak closed in the same pass.** Five call sites reach
  `clearTooltipVisuals` and only one passes the third argument, because only
  `onTooltipSetUnit` can compare GUIDs. The other four — `itemToolTipHook`, both
  non-unit branches of `onTooltipShow`, and a unit tooltip with no unit resolved
  — were hiding the frame while **keeping the model loaded**. Those are item,
  spell, quest and map-POI tooltips: there is no unit behind any of them, so a
  character model is meaningless and is now destroyed rather than left resident
  and merely invisible. A hidden frame still carries a loaded `PlayerModel`, and
  retained state is how this addon has bled one tooltip's visuals onto another.

  A genuine change of character still performs one asynchronous load. That brief
  blank on the first swap is inherent to `PlayerModel` and is **not** fixed here.

  **Two separate portrait defects are knowingly left in place**, since they are
  not the reported symptom and were not in scope: the portrait's alpha is still
  slaved to the tooltip's alpha in two places (once per render in
  `ApplyTooltipAppearance`, and continuously by the permanent 0.05s
  `onPortraitModelUpdate` poll), and the portrait is still re-anchored on every
  render via `ClearAllPoints()` + `SetPoint()` with its left/right side chosen by
  re-reading `tooltip:GetRight()` against screen width.

- **A stray specialization icon appeared on the wrong character** — the hovering
  player's own spec icon showing to the left of the tooltip on other people.
  Retail / WoW Forever only; the Classic family never used the overlay.

  Two independent causes, both fixed:

  1. **The library's icon lookup answered for the local player.** When the
     talent grid pass found nothing, `GetModernSpecializationIcon` fell back to
     `C_SpecializationInfo.GetSpecializationInfo(specIndex)` — called with **no
     unit argument**, so it always describes the *local* player. For anyone you
     have not inspected the grid pass always finds nothing, so the fallback
     always fired, which is why the stray icon showed up on other characters
     and looked reliable rather than intermittent. The fallback is now gated on
     `not isInspect`. An un-inspected unit correctly shows **no** icon rather
     than confidently showing the wrong player's.
  2. **The overlay was only cleared in one branch.** The clear sat in the `else`
     of the talent block, so a unit with no talent data never cleared it and
     the previous character's icon simply stayed on screen. The clear now runs
     first, unconditionally, in the talent block.

  A third, related defect: a miss for an inspect target was being written to the
  icon cache, which would have pinned "no icon" for the rest of the session and
  stopped the icon ever appearing, even after the target's talents streamed in.
  Misses for inspect targets are no longer cached, so the next hover re-queries.

  **Classic is provably unaffected.** `GetModernSpecializationIcon` opens with
  `if (not (isRetail or isForever)) then return nil end`, the Classic family
  never sets `useIconOverlay` so no overlay frame is ever created, and the
  Classic icon is inlined by `formatSpecializationText` from
  `GetLocalizedSpecIcon` — a different function this change never touches. A
  test now asserts the overlay frame is never created on a Classic client, which
  turns "should be safe" into "verified safe".

### Testing

A note on the earlier tests, because it is the general lesson: the pre-existing
portrait test drove the unit hook, which early-returns when the tooltip has no
text lines. That is true in the mock after the first render and never true in
game, so the hook path silently never reached the reload and the test passed
for the wrong reason. The tests here drive `ApplyTooltipAppearance` and
`clearTooltipVisuals` directly, which is what actually runs in a live client.

**The standing warning on this section.** A green harness did not mean the
portrait worked. The suite reported 50/50 while the portrait was visibly
blinking in game, twice, and the first fix was verified green while the blink
survived it. Nothing in a mocked environment can observe frame timing,
asynchronous model loads, or alpha interpolation. Treat the suite as necessary
and not sufficient: every portrait change is confirmed in a live client before
release.

Portrait tests, each verified to **fail** with the fix reverted rather than
merely passing:

- same-unit re-render through `ApplyTooltipAppearance` does not reload
- the same character via a *different* unit token does not reload (GUID-keyed)
- a real unit change *does* still reload
- **a non-unit tooltip tears the portrait down** — `ClearModel` runs and the
  frame is hidden, pinning the fix against a resident-model regression
- **`keepModel` does not destroy *or* hide** — the assertion that covers the
  actual defect. Reverting the fix fails it with `shown=false` on all five
  clients, which is the drop in isolation

The previous recycle test asserted the opposite contract — that a non-unit
recycle *preserves* the model — and had to be replaced rather than kept. It was
encoding the design mistake, so it passed while the portrait was still blinking.
That is the same failure mode this addon has hit before, and it is the reason
every one of these is reverted-to-fail before being accepted.

One test-harness bug worth recording: the new `keepModel` test initially failed
for the wrong reason. It zeroed its counter *before* calling
`ApplyTooltipAppearance`, which legitimately clears once after a teardown has
dropped the loaded-unit cache — so it was measuring the reload rather than the
recycle. The test was fixed, not the code.

A note on the earlier tests, because it is the general lesson: the pre-existing
portrait test drove the unit hook, which early-returns when the tooltip has no
text lines. That is true in the mock after the first render and never true in
game, so the hook path silently never reached the reload and the test passed
for the wrong reason. The tests here drive `ApplyTooltipAppearance` and
`clearTooltipVisuals` directly, which is what actually runs in a live client.

**The standing warning on this section.** A green harness did not mean the
portrait worked. The suite reported 50/50 while the portrait was visibly
blinking in game, twice, and the first fix was verified green while the blink
survived it. Nothing in a mocked environment can see frame timing, async model
loads, or alpha interpolation. Treat the suite as necessary and not sufficient:
every portrait change is confirmed in a live client before release.

Four specialization-icon assertions were added with the same discipline:

- an un-inspected target does **not** receive the local player's spec icon — the
  exact stray-icon defect, verified to fail with the fix reverted
- the local player's own icon still resolves, so the overlay still works for you
- a spec icon *does* appear once the target's talents are available, pinning the
  no-cache-on-miss behaviour
- the Classic family never creates the overlay frame at all

**This fix is incomplete and is not the whole stray-icon story.** The overlay
code was never reverted, so on Retail / WoW Forever the tooltip still draws
**two** icons for one specialization: the inline `|T` escape emitted by
`formatSpecializationText`, plus the overlay texture outside the tooltip's left
edge. The overlay was intended to *replace* the inline icon on modern — its own
comment says the Classic family keeps the icon inlined and modern does not — but
nothing ever suppressed the inline path, so modern draws both. Separately,
`hasDualSpec` is derived as `isWotlk or isTBC or (C_SpecializationInfo ~= nil)
or (GetNumTalentGroups ~= nil)`, and `C_SpecializationInfo` is not nil on
modern, so **a second spec line is rendered on clients that have one spec per
character**, each with its own inline icon. Both are still open and are the
likely cause of the "arms icon plus a second icon outside the edge" report.
Removing the overlay and correcting `hasDualSpec` for modern were scoped out of
this pass and have not been done.

### Corrected documentation

- **"Classic Era has no `NineSlice`" was false.** Classic Era *does* have a
  `NineSlice` child, reached by a different template chain rather than by its
  absence: `GameTooltip` inherits `GameTooltipTemplate`
  (`Blizzard_GameTooltip/Classic/GameTooltip.xml:13`), which inherits
  `GameTooltipCommonTemplate, TooltipBackdropTemplate`
  (`Blizzard_SharedXML/Classic/GameTooltipTemplate.xml:22`), and
  `TooltipBackdropTemplate` declares
  `<Frame parentKey="NineSlice" inherits="NineSlicePanelTemplate" useParentLevel="true"/>`
  at `Blizzard_SharedXML/SharedTooltipTemplates.xml:104-110`. WoW Forever and
  Retail reach the same child via `SharedTooltipTemplate` →
  `SharedTooltipArtTemplate` at `SharedTooltipTemplates.xml:19`. Only the
  `SetBackdrop` half of the original claim was correct: no supported client
  mixes `BackdropTemplateMixin` into the tooltip, so `GameTooltip.SetBackdrop`
  is nil on all five.
- **The two chains differ in a way that matters.** `GameTooltipTemplate` carries
  `mixin="GameTooltipMixin"` on the three Classic branches but
  `mixin="GameTooltipDataMixin"` on Forever and Retail, and only the Classic
  chain inherits `TooltipBackdropTemplate`. So the *tooltip itself* exposes
  `SetBackdropColor` / `SetBackdropBorderColor` on the Classic family but not
  on Forever or Retail. Border code must therefore never call those on the
  tooltip, and always writes to the `TacoTipBackdropFrame` overlay it creates
  from the `BackdropTemplate` template (`Blizzard_SharedXML/Backdrop.xml`,
  loaded by all five).

### Still outstanding

- **The stray specialization icon is only partly fixed — two causes remain**, as
  detailed above: the modern overlay was never removed, so it duplicates the
  inline icon, and `hasDualSpec` still claims dual spec on single-spec modern
  clients, adding a second spec line and a second icon.
- **The portrait's alpha is still slaved to the tooltip's alpha**, per render and
  via a permanent 0.05s `OnUpdate` poll, and the portrait is still re-anchored
  on every render. Both are separate defects, not the reported symptom, and were
  deliberately left alone.
- **`Tests/harness/load_test.lua` still models the Classic family as having no
  `NineSlice`** (lines 228, 248, 470), which the FrameXML contradicts — the
  Classic family reaches the same child through
  `GameTooltipTemplate` → `TooltipBackdropTemplate`, not by its absence. The
  suite therefore asserts a per-client contract that does not exist and **cannot
  catch a border regression on Classic**. This is the highest-priority follow-up
  before release.
- **The 3D portrait fix is unverified in a live client.** The static reasoning
  is solid and the tests bite, but frame timing, async model loads and alpha
  interpolation cannot be observed from a mocked environment — which is exactly
  how a green suite coexisted with a visible blink twice in this release.

### Critical

- **`GameTooltip:HookScript("OnTooltipSetUnit", ...)` was unguarded, and that
  raised at file scope on Retail.** `HookScript` errors with *bad argument #2 to
  'HookScript'* when the frame does not already declare that script. The Classic
  tooltip template declares `OnTooltipSetUnit`, `OnTooltipSetItem` and
  `OnTooltipSetSpell`; **Retail's does not** -- `SharedTooltipTemplate` on the
  live branch declares only `OnShow`, `OnHide`, `OnLoad`,
  `OnTooltipSetDefaultAnchor` and `OnTooltipCleared`. The old code hooked all three
  unconditionally, describing them as "registered as insurance ... the duplicate
  registration is inert". On Retail the insurance was not inert: it raised, and
  because `main.lua` is the **last** file in the toc, everything defined after that
  line never ran -- the item hooks, the visual clearing, the anchor hook, the
  overlays, and `TacoTip_CustomPosEnable`. That is the whole reported failure in
  one statement: the tooltip pipeline was dead, and the mover button said
  "not ready" because that function genuinely did not exist.
  Verified against `SharedTooltipTemplates.xml` on `live` and on all three Classic
  branches of `wow-ui-source`. All three hooks are now behind a `HasScript` guard,
  and `TT.HookedTooltipScripts` records which path each client ended up with
  (`postcall` on modern, the script hook on Classic).
- **`CreateFrame("Texture", nil, tooltip)` is not valid.** `Texture` is a *widget*
  type, created with `frame:CreateTexture()`; the real `CreateFrame` rejects it with
  *CreateFrame: Unknown frame type 'Texture'*. The specialisation-icon overlay used
  it, and that overlay is Retail/Forever-only (`useIconOverlay`), so the error fired
  on **every** unit tooltip on exactly the two clients that use it -- and because it
  happened inside the tooltip hook, it aborted the rest of the enhancement, so
  nothing at all was added. Classic never reached the line. Now
  `tooltip:CreateTexture(nil, "ARTWORK")`.
- **A `Texture` is a `Region`, not a `Frame`, on Retail and WoW Forever — so
  `SetFrameLevel` does not exist on it.** With the two defects above fixed the
  overlay got as far as its third line and then raised *attempt to call a nil
  value*, again on every unit tooltip and again aborting the rest of the
  enhancement. `SetSize` and `SetPoint`, on the two lines above it, are `Region`
  methods and worked; `SetFrameLevel` is a `Frame` method and the call is simply
  absent. On the Classic family a `Texture` does inherit `Frame`, so the call is
  valid there — which is why nothing in the codebase ever exercised the modern
  branch. Only `Texture` is affected: `Frame`, `Button` and `PlayerModel` are
  `Frame`s on every client, so the addon's other frame-level calls
  (`TacoTipPortrait3D`, `TacoTipBackdropFrame`, the mover and the drag button) are
  sound. The call is now guarded; on modern clients the texture keeps the
  `ARTWORK` draw layer `CreateTexture` already gave it, which is the Region-side
  equivalent. Swept every other texture and `FontString` in the addon for the
  same assumption — all of them use Region-level methods only.
- **`CharacterModelFrame` does not exist on Retail, and the character-pane
  GearScore / iLvl overlay indexed it unguarded.** The Classic family nests a
  `PlayerModel` named `CharacterModelFrame` inside `PaperDollFrame`
  (`Blizzard_CharacterFrame/{Vanilla,TBC,Wrath}/PaperDollFrame.xml`); Retail
  removed that model frame and keeps only `PaperDollFrame`
  (`Blizzard_UIPanels_Game/Mainline/PaperDollFrame.xml`) — there is no
  definition of `CharacterModelFrame` anywhere in the live FrameXML. Every
  character-pane refresh therefore raised *attempt to index global
  'CharacterModelFrame' (a nil value)*, and because `refreshOverlayPositions`
  calls `TT:RefreshCharacterFrame()` whenever `PaperDollFrame` is shown, **opening
  the options frame threw**. The font strings are now parented to
  `_G.CharacterModelFrame or _G.PaperDollFrame`, and both init and refresh return
  cleanly when neither exists. This makes the overlay *work* on Retail instead of
  only avoiding the crash; the startup guard was widened from
  `CharacterModelFrame and PaperDollFrame` to the resolved host, so the initial
  paint also runs there. Classic is unchanged — `CharacterModelFrame` exists and
  is still preferred. A sweep of every other Blizzard frame the addon touches
  (`PaperDollFrame`, `InspectFrame`, `InspectPaperDollFrame`, `InspectModelFrame`,
  `GameTooltipStatusBar`, `CharacterFrame`, `MerchantFrame`) found no further
  gaps: `GameTooltipStatusBar` is declared as `$parentStatusBar` in
  `GameTooltip.xml` and is already nil-guarded, and `RefreshInspectFrame` already
  guarded its own frames.
- **The 3D portrait was torn down and rebuilt on every asynchronous GearScore
  completion, so it visibly strobed.** This is the "something is not being reset
  and bleeding through" symptom, and it was neither re-entrancy nor a stale value.
  `itemcacheCB` fires `TacoTip_GSCallback` each time an item load *completes* —
  asynchronously, long after the drive that registered it returned, so no
  re-entrancy guard can see it. Each completion re-drove the tooltip for the
  **same** unit, and `clearTooltipVisuals` called `ClearModel()` on the
  `PlayerModel` every time, reloading it. A tooltip whose items are still
  streaming in therefore flickered for as long as loads kept arriving.
  `clearTooltipVisuals` now takes a `preserveModel` flag; `onTooltipSetUnit`
  resolves the unit's GUID *before* clearing so it can tell "the unit changed"
  from "the same unit is being re-rendered", and only the former tears the model
  down. Every other overlay still clears on every path. `tooltip_test` drives the
  same unit three times and asserts the model survives, then changes the unit and
  asserts it is cleared; reverting the guard reports `ClearModel calls=3`.
- **`TacoTip_GSCallback` could re-enter itself without bound, rebuilding the
  tooltip many times a second on a unit-frame hover.** `itemcacheCB` (and its
  Pawn twin) fire the callback once an item load completes; the callback re-drives
  the tooltip, which re-runs the whole pipeline — our unit post-call recomputes
  GearScore, which registers further item loads, which complete and call straight
  back in. Nothing bounded that nesting, so holding the mouse on a unit frame
  rebuilt the content endlessly: the tooltip appeared to reset over and over in
  the same spot, because the anchor never changed and only the content was being
  rebuilt. Re-entrancy is now guarded: a nested call for the guid already being
  serviced is satisfied by the call in progress and dropped, a nested call for a
  different guid is deferred and run once after unwinding, and the guard is
  cleared unconditionally through a `pcall` so a throw cannot leave it latched
  and silently kill every later callback. The non-nested case is unchanged.
  `tooltip_test` reproduces the loop by re-entering the callback from inside the
  drive: without the guard the pipeline is driven until the test's safety cap,
  with it exactly once.
- **A regression introduced while fixing the above: three Classic item tooltips
  stopped being hooked.** The first guarded version recorded the item hooks with a
  short-circuiting `or` chain over `GameTooltip`, `ShoppingTooltip1`,
  `ShoppingTooltip2` and `ItemRefTooltip`. On the Classic family `GameTooltip` is
  first *and* declares `OnTooltipSetItem`, so the chain stopped there and the
  other three were never hooked — a regression on the three clients that already
  worked, traded for a fix on the two that did not, and one that no diagnostic
  would have surfaced. `hookTooltipScripts` now attempts **every** frame in the
  list and records all successes, and `load_test` asserts each of the four by
  name on every Classic client; reintroducing the short-circuit now fails the
  harness on all three.
- **The harness used to invent `CharacterModelFrame` on every client**, including
  Retail, which is why an unguarded index of a frame that does not exist there
  passed. All four harnesses now blank it when the client is modern, matching the
  source; reverting the addon fix then fails Retail and WoW Forever and still
  passes TBC Anniversary.
- **`SetScript("OnRefresh"/"OnCommit"/"OnDefault", ...)` was wrong, and the game
  rejected it.** (Introduced earlier in this same pass, and caught before release —
  recorded here because the changelog should show what actually happened.) The Retail Settings panel invokes those three as **methods** --
  `frame:OnRefresh()`, `frame:OnDefault()`, `frame:OnCommit()` in
  `Blizzard_SettingsPanel.lua:8, :2, :557` -- and never `SetScript`s them; they are
  reserved canvas handler names, not script slots, so `SetScript` raises *bad
  argument #2 to 'SetScript'*. They are now assigned as function fields. The
  `OnShow` script is kept for the classic `InterfaceOptions_AddCategory` path, which
  has no such handlers.
- **Talent line was broken on the Classic family, confirmed in game.** On TBC Anniversary the tooltip rendered `Talents: Marksmanship [132164/132222/132215]` — those numbers are talent *icon* fileIDs, not points — with no talent icon, and only one specialization instead of two. Three separate causes, all in the library: the port introduced a `getTalentTabPoints` helper that read the wrong `pcall` return slots and captured `icon` as `pointsSpent`; the `|T` escape required a `string` and so dropped every numeric fileID; and the `hasDualSpec` gate was never ported. Because the points were garbage, both groups resolved to the same tab and the `spec2 ~= spec1` guard hid the second line entirely. All three are fixed and the Classic path now uses the known-good algorithm from the root addon — see [Talents and specializations](#talents-and-specializations).
- **Removed the duplicate `.toc`.** A second, byte-identical toc file shipped alongside the real one. WoW loads *every* `.toc` in an addon folder, so all 16 files executed twice on every client: tooltip hooks double-registered, lines duplicated, and `local addOnName = ...` split the `_G.TT` namespace in two. There is now exactly one toc, and it is named to match the folder it ships in.
- **Corrected `## Interface:` for Titanforge.** Titanforge is `3.80.2` → interface `38002`; the toc listed `38001` (3.80.1), so the addon did not load there at all. Also dropped the dead `110005` / `110007` entries and the README's deprecated `30405`.
- **Fixed tooltip hooks that registered but never fired on TBC Anniversary and Titanforge.** Both clients define `TooltipDataProcessor` and `Enum.TooltipDataType`, so the old presence-only test took the modern branch — but their `GameTooltip` mixes in `GameTooltipMixin` alone, never `TooltipDataHandlerMixin`, so `ProcessTooltipPostCalls` was never reached. Both clients showed stock Blizzard tooltips: no GearScore, spec lines, guild reformat, class colours, 3D portrait, power bar, or item iLvl / HunterScore. Hook selection now probes `IsTooltipType` / `GetPrimaryTooltipData` (which come from the mixin itself), and both paths are registered as insurance.
- **Locale: German was dead, and the language override never applied.** Nine locale files had a `GetLocale()` guard and bound `_G.TACOTIP_LOCALE`; `deDE` alone had been converted to the `TACOTIP_LOCALES` registry, which nothing reads, so German clients silently got English. All eleven now register into `TACOTIP_LOCALES` and `enUS.lua` is the single selector, re-applied on `ADDON_LOADED` — addon files run before WoW populates `SavedVariables`, so `locale_override` was unreadable at file scope. `TacoTipApplyLocale` mutates the table in place so the `local L` bindings in `main.lua` / `gearscore.lua` / `options.lua` observe the change. `enGB` maps onto `enUS`.

### Tooltip rendering
- **`BackdropTemplateMixin` was grafted onto the live `GameTooltip` on exactly the two clients that must not have had it.** The early fallback tested `not GameTooltip.SetBackdrop` to decide whether the tooltip needed the legacy backdrop mixin. That is the wrong signal. Retail and WoW Forever use `SharedTooltipArtTemplate`, which attaches a `NineSlice` child and does **not** mix in `BackdropTemplateMixin` — so `GameTooltip.SetBackdrop` is nil there even though the tooltip renders perfectly. The test therefore fired on Retail and Forever and installed 16 unused `backdropInfo`-based methods (`SetBackdrop`, `SetBackdropColor`, `SetBackdropBorderColor`, `ApplyBackdrop`, `ClearBackdrop`, …) onto the real tooltip, overriding the `NineSlice`-driven rendering the appearance code depends on. The condition now requires the **absence of `NineSlice`**, which is what the surrounding comment always said it meant, and which leaves the Classic family byte-identical: **Correction — Classic Era does have a `NineSlice` child.** It is reached by a different template chain than Retail's, not by its absence: `GameTooltip` inherits `GameTooltipTemplate` (`Blizzard_GameTooltip/Classic/GameTooltip.xml:13`), which inherits `GameTooltipCommonTemplate, TooltipBackdropTemplate` (`Blizzard_SharedXML/Classic/GameTooltipTemplate.xml:22`), and `TooltipBackdropTemplate` declares `<Frame parentKey="NineSlice" inherits="NineSlicePanelTemplate" useParentLevel="true"/>` at `Blizzard_SharedXML/SharedTooltipTemplates.xml:104-110`. WoW Forever and Retail reach the same child through `SharedTooltipTemplate` → `SharedTooltipArtTemplate` at `SharedTooltipTemplates.xml:19`. So the `not NineSlice` guard does not fire on Classic either, and the Classic family was **not** left relying on a legacy `SetBackdrop` fallback. Only the `SetBackdrop` half of the original claim was right: no supported client mixes `BackdropTemplateMixin` into the tooltip, so `GameTooltip.SetBackdrop` is nil on all five. The two chains differ in one further way worth recording — `GameTooltipTemplate` carries `mixin="GameTooltipMixin"` on the three Classic branches but `mixin="GameTooltipDataMixin"` on Forever and Retail, and only the Classic chain inherits `TooltipBackdropTemplate`, so the tooltip itself exposes `SetBackdropColor` / `SetBackdropBorderColor` on the Classic family but not on Forever or Retail. That asymmetry is why the border code must never call those methods on the tooltip and instead always writes to the `TacoTipBackdropFrame` overlay it creates itself with the `BackdropTemplate` template (`Blizzard_SharedXML/Backdrop.xml`, loaded by all five).
  - Verified against `Blizzard_SharedXML/SharedTooltipTemplates.xml` and `Backdrop.lua` on the `live` branch and the `classic_era` branch of `wow-ui-source`.
  - The offline harness could not see this at all: its mock hands **every** widget **every** method, so `GameTooltip.SetBackdrop` was always a function and the guard was never taken on any client.
  - **Correction — `load_test` does not model the real Classic template, and its "pins the contract both ways" claim is wrong.** It still asserts the Classic family has no `NineSlice` (`Tests/harness/load_test.lua:228`, `:248`, `:470`), which the FrameXML above contradicts. The guard therefore cannot fire on the Classic family in the harness either, but for a reason the mock gets wrong rather than right. The assertions are documented here as unverified against the real Classic template; correcting the mock is outstanding and is **not** done in this entry.



- **`CreateFrame("Texture", ...)` is not a valid call.** `Texture` is a *widget*
  type, created with `frame:CreateTexture()`; the real `CreateFrame` rejects the
  frame-type form with *CreateFrame: Unknown frame type 'Texture'*. Now
  `tooltip:CreateTexture(nil, "ARTWORK")`. See
  [Critical](#critical) for why this alone took out the whole Retail tooltip.

### Talents and specializations

- **Talent points on the Classic family were reading the wrong return value, and printed icon fileIDs as numbers.** The tooltip showed `[132164/132222/132215]` — those are talent *icon* fileIDs. The cause was a `getTalentTabPoints` helper introduced by this port that read the wrong slots out of `pcall`'s results: `pcall` prepends a boolean, so every position is shifted by one and the `icon` field landed in `pointsSpent`. That helper is **removed**. `LibForeverInspector` now computes Classic talent points the way the working `LibClassicInspector` does, by summing each talent's `rank`:
  `talents[tab] += select(5, GetTalentInfo(tab, talent, isInspect, isPet, group))`
  which is the same total `pointsSpent` reports, but is stable whether or not the `loadDeprecationFallbacks` CVar is set.
- **The specialization icon on the Classic family never rendered.** `main.lua` resolves it with `CI:GetTalentInfoByClass` — unchanged working code — but `LibForeverInspector` is a rewrite of `LibClassicInspector` and the rewrite dropped both `GetTalentInfoByClass` and the ~1840-entry static `talents_table` it reads. With the callee nil, `pcall` always failed and the lookup returned nil. The icon is **not** read from a live API on Classic; it comes from that static table. The table, `GetTalentInfoByClass`, `GetNumTalentsByClass` and the WotLK glyph data are ported verbatim. Per expansion: Classic Era 18 talents in Warrior tab 1 (Vanilla), TBC Anniversary 23 (TBC), Titanforge 31 (WotLK, Death Knight included) — each resolving real icon textures.
- **The `|T` icon escape dropped every fileID.** `formatSpecializationText` required `type(icon) == "string"` before inlining the icon, but the static table returns a *number*, so no icon ever appeared. The working addon formats it with `tostring()`, because a `|T` escape accepts a fileID as well as a texture path. Restored.
- **Dual specialization is now available on Classic Era, TBC Anniversary and Titanforge.** The `hasDualSpec` gate from the working library was never ported, so group 2 was attempted on every client without support. It is now defined identically (`isWotlk or isTBC or (C_SpecializationInfo ~= nil) or (_G.GetNumTalentGroups ~= nil)`, read through `_G` so it is nil-safe) and `GetSpecialization` / `GetTalentPoints` refuse group 2 where it is false. The wrong point values had also been making both groups resolve to the same tab, so the `spec2 ~= spec1` guard suppressed the second line entirely.
- **The inspect cache only ever held group 1.** `cacheUnitData` hardcoded group 1 (`getTalentTabPoints(t, true, false, 1)`), so inspecting a dual-spec'd player returned group 1's data for group 2 as well. It now builds `talentPoints[group][tab]` and `specIndexByGroup[group]` for every supported group.
- **`GetActiveTalentGroup` returned 1 for every inspected unit**, so the tooltip always coloured group 1 and greyed group 2 regardless of which group the inspected player was actually on. It now reads `GetActiveSpecGroupFor(true)` into `data.activeGroup` and returns that, so the greyed specialization is genuinely the inactive one.
- **Retail and WoW Forever now show talent points.** Neither has `GetNumTalentTabs`, so the talent-tab path cannot run there and `GetTalentPoints` returned `0/0/0`. `C_SpecializationInfo.GetSpecializationInfo` has the same 7-argument signature and 10-value return on all five clients, with `pointsSpent` at 7 and `previewPointsSpent` at 9, so per-specialization points are read from it.
- **The modern path is now group-aware.** It used `GetSpecialization()` for self and `GetInspectSpecialization(unit)` for others; the latter takes only a unit and so cannot distinguish group 1 from group 2. It now calls `GetSpecialization(isInspect, isPet, groupIndex, 1)`, the only group-aware form, with both old calls kept as fallbacks.
- **`GetSpecialization` returned a specID where callers expected a spec index** — an ID such as `72` where every consumer indexes `lib.spec_table[class][specIndex]`, so `spec_table.WARRIOR[72]` was nil and the whole specialization line silently disappeared on Retail and WoW Forever. It now returns the 1-based index.
- **Specialization icons on Retail and WoW Forever** come from `CI:GetModernSpecializationIcon` via `C_SpecializationInfo.GetTalentInfo`. The **query form** differs by FrameXML toc: Classic Era / TBC / Titanforge load `Vanilla\TalentFrameBase.lua` and query by `specializationIndex` + `talentIndex`, while Retail and WoW Forever load `[Family]\TalentFrameBase.lua` and query by `tier` + `column`. The modern resolver uses tier/column, falls back to linear, and is gated to Retail/Forever so Classic is untouched. `TalentInfoResult.icon` is a fileID, which `|T` cannot render, so it is drawn with a `Texture` overlay that is only created when there is an icon to draw.
- **Specialization names follow the client's language on Retail and WoW Forever** via `CI:GetLocalizedSpecName` / `CI:GetLocalizedSpecIcon`, resolved per spec group so the two dual-spec lines do not both wear group 1's name. The Classic family still uses the built-in table.
- `GetModernSpecializationIcon` is deliberately *not* named `GetSpecializationIcon`: the latter is a pre-existing stub in this library that always returns nil, and the two definitions silently overwrote each other.

### GearScore

- **WoW Forever now uses the 200 bracket.** It is a Classic-like client (level cap 60, no level scaling) but had no branch and inherited the 1000 default, inflating every score 5x and collapsing the whole colour ramp into the "Common" white band. No formula or colour change — the bracket is a pure mapping, so the Classic ramp and the iLvl average are preserved.
- Test no longer asserts against a hardcoded `GetQuality(7000)`; it uses `GS.MAX_SCORE`, and now also asserts the bracket agrees with the detected family.

### Client detection

- Rebuilt around `WOW_PROJECT_ID` (distinct per Classic client: 2 / 5 / 11) with the interface version used only to separate WoW Forever from Retail, which both report `WOW_PROJECT_MAINLINE`. The previous code derived everything from `select(4, GetBuildInfo())`, whose return layout is documented only for Retail and Forever.
- The interface number is now read from whichever `GetBuildInfo()` return slot is numeric, so detection does not depend on the unverified Classic layout. Covered by tests under both layouts.
- Added `CI.family`, `CI.IsUnknown()` and a `CI.caps` capability snapshot. An unrecognised client now resolves to `family == "unknown"` instead of silently inheriting a default — Cata and Mists previously matched no flag at all.
- `GetTalentTabInfo` / `GetNumTalentTabs` are no longer captured into file-scope locals. `GetTalentTabInfo` is a `loadDeprecationFallbacks`-gated deprecation shim, so a local latched to `nil` could never recover.
- Talent points now sum `pointsSpent + previewPointsSpent`, matching Blizzard's own `TalentFrameBase_Shared.lua`; reading only the former under-reported after a respec and could select the wrong specialisation tab.
- `pcall` added around `C_SpecializationInfo.GetInspectSpecialization` (Retail flags it secret-restricted) and `GetSpecializationInfoByID`; a throw previously aborted `cacheUnitData` before it fired `INVENTORY_READY` / `TALENTS_READY`.
- Removed the dead `_G.TACOTIP_SPEC_NAMES` / `_G.TACOTIP_SPEC_ICONS` lookups from `main.lua` and `LibForeverInspector`. Nothing ever wrote those globals, so they were always nil and specialization names always came from the library's built-in table — while the surrounding comments claimed they followed the language override. `GetSpecializationIcon` is kept as a stub that honestly reports it has no override to return.
- `NotifyInspect` is now guarded, matching its `CanInspect` / `ClearInspectPlayer` siblings.
- The `LibClassicInspector` alias is registered unconditionally and now carries a minor version, so a version bump re-points it instead of leaving callers on a stale table.

### Localization

- **English is now the explicit default, with WotLK Titanforge pinned to Simplified Chinese.** Resolution order is: `TacoTipConfig.locale_override` (always wins) → Titanforge → `zhCN` → the client language when a table is shipped for it → English. Titanforge is the Chinese build of WotLK, so its default is no longer whatever `GetLocale()` happens to report; English is both the default and the per-key fallback every other language is layered over. The other four clients still follow the client language as before.

### Tooltip mover handle

- **The green drag handle now starts on the tooltip's top-left corner, with the
  tooltip still in the bottom-left of the screen.** The handle's default screen
  position was the **bottom-right** corner, so on a fresh profile the handle
  rendered at the far end of the tooltip from the name — level with the
  "Drag to Move" instruction line — which is the opposite end from where you
  naturally grab it. The default is now `BOTTOMLEFT` of the screen, and it pairs
  with the existing `custom_anchor` default of `TOPLEFT`: the tooltip's TOPLEFT is
  pinned to the handle's TOPLEFT, so with the handle's BOTTOMLEFT on the screen's
  BOTTOMLEFT the tooltip occupies the strip directly above it. Both halves are
  pinned by `load_test` — through `TacoTip_CustomPosEnable` and
  `TT:SyncTooltipMover`, the real path rather than the local default function —
  and the test also proves a **saved** `custom_pos` is still honoured, which would
  otherwise be silently broken by changing the default. Reverting the default
  reports `got BOTTOMRIGHT/0/0`. Existing installs keep their saved position;
  *Reset* on the mover clears `custom_pos` and picks up the new default.

### Chat spam from the tooltip pipeline

- **Root cause of the repeated `ScaleName must be the name of an existing scale,
  and is case-sensitive.` — the Pawn scale library name does not follow the client,
  and the fix that looked safe could not work.**
  Pawn ships exactly two scale providers and `Pawn.toc` gates them by game type, so
  exactly one exists on any given client:

  | Provider file | `AllowLoadGameType` | Clients | Library name |
  | :--- | :--- | :--- | :--- |
  | `AskMrRobot.lua` | `mainline` | Retail, WoW Forever | `"MrRobot"` |
  | `ClassicHawsJon.lua` | `classic` | Vanilla, TBC, Wrath | `"Classic"` |

  The shipped code preferred `"MrRobot":CLASS..SPEC` and then asked
  `_G.PawnIsScaleVisible` whether that scale existed, falling back to `"Classic"`.
  On the **Classic family** that probe asked about a library Pawn does not have
  (`AskMrRobot.lua` is not loaded there), and on **Retail / WoW Forever** the
  fallback was never needed. That is the original report.

  Two facts about Pawn make this unfixable by probing, and both were verified in
  the installed `Pawn/` sources rather than assumed:

  1. `PawnIsScaleVisible` and `PawnGetScaleColor` report an unknown name through
     `VgerCore.Fail`, and **`VgerCore.Fail` does not raise a Lua error** —
     `VgerCore/VgerCore.lua:160` calls `VgerCore.Message`, which writes straight to
     `DEFAULT_CHAT_FRAME:AddMessage`. **`pcall` cannot suppress it.** So the old
     "probe, then fall back" logic printed one chat line per player tooltip render
     and per unit frame refresh *no matter how it was guarded*, which is why an
     earlier attempt that only wrapped the probe in `pcall` did not fix it.
  2. The scale name is `<CLASSNAME><specIndex>` — `Pawn.lua:5784` builds
     `ScaleInternalName = UnlocalizedClassName .. (SpecID or "")` — and
     `PawnGetScaleColor` looks the whole name up in the global `PawnCommon.Scales`.

  `PawnScaleProviders` and `PawnCommon` are both plain globals, so the same
  question is answered by **reading Pawn's own registries**, which is completely
  silent. `pawn.lua` now resolves the library from the provider Pawn actually
  registered *and* the scale actually present in `PawnCommon.Scales`, and calls
  `PawnGetScaleColor` only with a name proven to exist there — so the
  `VgerCore.Fail` branch is unreachable by construction. When nothing matches
  (Pawn still initialising, or no scale for that class/spec) the colour is simply
  skipped, which is cosmetic. `PawnIsScaleVisible` is no longer called at all.
- **The deferred Pawn readiness probe was itself a source of the spam and is
  gone.** It called `PawnGetScaleColor("\"Classic\":ROGUE1", true)` blindly, which
  on Retail — where Pawn has no `"Classic"` library at all — printed the ScaleName
  error to chat by itself, once at 3s and again at 8s. A prior revision of this
  fix "restored" a 3s/5s version of that probe from the Classic build, which
  carried the defect over with it; the silent registry lookup subsumes it
  entirely, so there is now no timer, no `_TacoTipPawnReady` flag, and no call to
  Pawn before its scales are known to exist. `PawnGetSingleValueFromItem` — which
  *never* calls `VgerCore.Fail`, it just answers `0` for an unknown name — is
  still free to try both libraries, so the score itself works on every client.
- **`safeCall` was printing every pipeline error to the chat frame.** It used
  `xpcall(fn, geterrorhandler(), ...)`, and `geterrorhandler()` *is* the chat
  reporter. A single C API argument error carries no Lua stack, so BugSack showed
  it with no trace — and because the pipeline runs many times a second on a unit
  frame, the same message was reprinted endlessly and buried the chat. The
  default handler still runs, but only **once per distinct message per session**,
  so a real defect stays visible and a per-frame repeat does not. The most recent
  message is recorded on `TT.lastTooltipError` and reported by `/tacotip diag`,
  which is the only way to identify an error that has no stack.
- **Every string-taking C call in the render path now names itself.** A C API
  argument error arrives with nothing identifying which call produced it, which
  forces a bisect through the whole pipeline. `callLabeled` re-raises with the
  call site attached, and is used for `SetFont` on tooltip lines, `SetBackdrop`
  on the backdrop frame, and `SetStatusBarTexture` on the health and power bars —
  so the single reported message now names the exact call instead of leaving a
  guess. This instrumentation is defence in depth, not the fix: an exhaustive
  sweep of every file including the bundled libraries confirms the addon calls
  `SetScale` nowhere, which is what first ruled out a widget scale and pointed at
  Pawn's own scale-name API above.

### Settings and options
- **Every one of the 66 settings is now verified reachable, bound, persistent and
  resettable** — see [Testing](#testing). The Classic options UI is otherwise
  unchanged.
- **The Retail Settings canvas handlers are methods, not scripts.** The panel calls
  `frame:OnRefresh()`, `frame:OnDefault()` and `frame:OnCommit()` directly
  (`Blizzard_SettingsPanel.lua:8, :2, :557`) and never `SetScript`s them; they are
  reserved canvas-handler names, not script slots, so `SetScript` on them raises
  *bad argument #2 to 'SetScript'*. They are assigned as function fields, with
  `OnShow` retained for the classic `InterfaceOptions_AddCategory` path, which has
  no such handlers.

### Crash and correctness fixes

- `main.lua` `onTooltipSetUnit` called `tooltip:GetUnit()` unguarded on its first line; on clients where that method is a shim over a namespace that may not be loaded, the throw was swallowed by the surrounding `safeCall` and silently dropped the entire unit tooltip. Now `pcall`ed. Same fix in `options.lua`'s Power Bar handler.
- `GetQuestDifficultyColor` was cached at file scope. On the Classic family it is a Lua global from a `LoadFirst` Blizzard addon, and TacoTip declares no `LoadFirst`, so it could latch `nil` for the session and permanently disable hostile level colouring. Now resolved per call.
- `IsEquippableItem` was called as a bare global. It is created by `Blizzard_DeprecatedItemScript`, which early-returns unless the `loadDeprecationFallbacks` CVar is set — with it off, every item hover raised and lost its iLvl / GearScore lines. Now prefers `C_Item.IsEquippableItem`.
- `resolveTooltipUnit` returned `"mouseover"` unconditionally as a last resort. On the four clients without `TooltipUtil` that is the only fallback, so a stale `GetUnit()` painted the wrong unit's colour, portrait and GearScore onto e.g. the target tooltip. Now only accepted when the tooltip genuinely is the mouseover tooltip. The `data.guid` fallback is likewise limited to `mouseover` / `target`: mapping an arbitrary GUID onto a unit token would be a guess, and declining leaves the tooltip untouched rather than mis-attributed.
- `tooltip_max_width` was a silent no-op on every client: `GameTooltip` has no `SetMaximumWidth` anywhere (on all five branches it belongs only to `BaseMenuDescriptionMixin` and Calendar). Reimplemented by capping the line `FontString` widths, which wraps long content while leaving short lines untouched.
- `registerTooltipVisualClearing` iterated with `ipairs` over a table containing guaranteed `nil`s, so every frame after the first hole silently lost its hooks. Now `pairs`.
- `UnitIsSameServer` is guarded, matching its neighbours.
- `wipe(...)` → `table.wipe(...)` (confirmed present on all five clients); the bare global is protected on 10.0+.
- Options: slider `Text` / `Low` / `High` lookups now fall back to `CreateFontString`, matching the checkbox builder — a miss previously aborted the whole page build into a silently blank options page. ColorPicker legacy fallback sets `swatchFunc` (what `ColorPickerFrame.xml` actually reads) instead of `func`. `LoadAddOn` list includes the real Classic addon names. Removed a duplicated `InterfaceOptionsFrame_OpenToCategory` call.
- `textures.lua`: CJK fonts are hidden on non-CJK clients (they silently fell back to the default font) and third-party Details fonts are dropped from the "Blizzard -" list. Media lists are filtered per client.
- `scheduleItemTooltipRefresh`'s no-object-API fallback called `RequestLoadItemDataByID` as a **bare global**. There is no such global on any of the five clients — the only real form is `C_Item.RequestLoadItemDataByID` (confirmed against `Blizzard_ObjectAPI` on every branch) — so the branch silently did nothing. It now uses the file-scope local that already resolves the namespaced form.
- Removed the `C_Item.GetItemLinkByID(data.id)` arm from `resolveTooltipItem`. It has **zero** call sites on any client, and there is no replacement: `C_Item.GetItemLink` takes an `ItemLocation`, not a bare itemID. The `data.hyperlink` arm above it is what the post-call actually supplies, so item resolution is unaffected.
- The item-wrapper fallback in `LibForeverInspector.createItemWrapper` implemented only `ContinueOnItemLoad`, but `main.lua` calls `ContinueWithCancelOnItemLoad`. A safety-net object that does not honour the interface of the object it stands in for is worse than none, so the wrapper now implements the cancelable form. The call site additionally falls back to the non-cancelable variant rather than dropping the repaint entirely. (The real `ItemMixin` provides `ContinueWithCancelOnItemLoad` on all five branches, so this only affected the fallback path.)
- `main.lua`'s `itemLoadCancel` field doc named `C_Item.ContinueWithCancelOnItemLoad`, which is not a `C_Item` function at all — it is an `ItemMixin` method. Corrected.

### Retail / Forever file-scope robustness

A Lua error at file scope in `main.lua` does not just disable one feature: it
disables everything defined after that line, because the rest of the chunk never
runs. Two file-scope operations depended on a global existing, and neither was
guarded.

- **`hooksecurefunc("GameTooltip_SetDefaultAnchor", ...)` was unguarded.**
  `hooksecurefunc` raises "attempt to hook a non-existent function" when its
  target is absent, and this call sits at file scope, so the whole addon would
  abort. The target *is* present on all five clients -- it is defined by
  `Blizzard_SharedXML/SharedTooltipTemplates.lua`, and that addon is not
  LoadOnDemand -- so this is hardening, not a fix. The hook is now a named
  function installed behind a `type(...) == "function"` test, and records
  `TT.HookedDefaultAnchor` so the diagnostic can report it. When the target is
  missing, only the spell-tooltip anchor side selection is lost; every other
  anchoring path is untouched.

- **Retail's Settings panel contract is now honoured in full.** The panel drives
  canvas pages through three optional frame handlers: `OnRefresh` when the panel
  is shown, `OnDefault` on restore-defaults, `OnCommit` on Apply. The addon only
  used `OnShow`, which fires when the canvas frame becomes visible -- but the
  panel owns that visibility and reuses an already-shown frame, so a page can be
  re-selected without `OnShow` ever firing and the controls keep showing stale
  values. All three are now implemented; see
  [Settings and options](#settings-and-options) for the method-vs-script detail,
  which cost one iteration to get right.

### Retail / Forever API audit

Every Blizzard global, frame method, event name and frame template the addon
touches was cross-checked against the `live` (12.1.0.69814) and `classic_era`
branches of `wow-ui-source`:

- **Event names** — all 10 (`ADDON_LOADED`, `INSPECT_READY`, `MODIFIER_STATE_CHANGED`,
  `PLAYER_EQUIPMENT_CHANGED`, `PLAYER_LOGIN`, `UNIT_DISPLAYPOWER`, `UNIT_MAXPOWER`,
  `UNIT_POWER_UPDATE`, `UNIT_TARGET`, `UPDATE_MOUSEOVER_UNIT`) are documented on
  live. An unknown event raises at `RegisterEvent`, so this mattered.
- **Frame templates** — all 8 (`InputBoxTemplate`, `InterfaceOptionsCheckButtonTemplate`,
  `OptionsSliderTemplate`, `UIDropDownMenuTemplate`, `UIPanelButtonTemplate`,
  `UIPanelCloseButton`, `UIPanelScrollFrameTemplate`, `BackdropTemplate`) are
  defined in live XML. An unknown template is a hard error in `CreateFrame`.
- **Namespaced-away APIs** — `GetActiveTalentGroup`, `GetSpecializationName` and
  `CUSTOM_CLASS_COLORS` are no longer called bare by Blizzard on live, and the
  library does not call them bare either: `GetActiveSpecGroupFor` prefers
  `C_SpecializationInfo.GetActiveSpecGroup` with a `_G.GetActiveTalentGroup`
  fallback, `lib:GetSpecializationName` reads only the built-in table, and the
  class-colour lookup is nil-guarded. All safe.
- **Secret-argument-gated APIs** — `SetTexture`, `SetAtlas`, `SetColorTexture`,
  `SetVertexColor`, `SetText`, `SetFormattedText`, `GetItemInfo`,
  `GetItemInfoInstant` and `SetClampedToScreen` are `AllowedWhenUntainted` on
  live. Every call site passes either a literal or a value from the addon's own
  tables, except the talent-icon `SetTexture`, which was already `pcall`-wrapped.
- **One correction to an earlier claim.** An intermediate sweep reported
  `main.lua`'s bare `GetItemInfo(itemLink)` as a Retail failure, on the grounds
  that Blizzard never calls it bare. That reasoning was wrong: the generated
  `ItemDocumentation.lua` documents `GetItemInfo`, `GetItemInfoInstant` and
  `IsEquippableItem` as **globals** with no enclosing namespace, and FrameXML
  cannot witness engine globals at all -- only FrameXML-defined ones. The bare
  global does exist. The call site is now resolved namespace-first and
  nil-guarded like the one in `gearscore.lua`, so a client exposing neither form
  degrades instead of aborting the hook, but this is hardening, not a fix.

### Load diagnostics

- **A single error in `main.lua` silently disabled the mover, the tooltip pipeline and the overlays, and the UI blamed `/reload`.** `main.lua` is the last file in the toc and ~2900 lines long, and it defines `TacoTip_CustomPosEnable` at the very end. `options.lua`, `gearscore.lua` and `main.lua` itself all call that global. If anything raised at file scope, every one of those call sites took its fallback branch — and the mover's message was *"Tooltip mover is not ready yet. Try /reload."* That advice cannot help, because the cause is a load-time error, not a timing one. This is the signature of the reported Retail failure, and it is now diagnosable instead of guessable:
  - `main.lua` records `TT.LOAD_STAGE` at nine points through its own load and sets `TT.LOAD_OK` at the end.
  - **`/tacotip diag`** prints the version, whether the load completed, the last stage reached, the detected family and interface, and the type of each key global (`TacoTip_CustomPosEnable`, `TT.ApplyTooltipAppearance`, `TT.OpenOptionsPanel`, `TT.RefreshOptionsUI`, `TT.SyncTooltipMover`) plus the GearScore bracket and active locale.
  - The mover's own message now names the stage reached instead of advising a reload that cannot help.
  - `/tacotip diag` also reports which widget surface the client presents — `NineSlice`, `SetBackdrop` and `HasScript("OnTooltipSetUnit")` — because those three facts select the tooltip code paths. Reporting them makes "looks wrong on client X" answerable without guesswork, and the reporting is read-only: running the diagnostic creates no widgets.
  - New in-game `Client:LoadCompleted` and `Client:BackdropTemplateContract` tests, and matching `load_test` assertions for all five clients, so a partial load can never again be invisible offline.

### Testing

- Test suite moved to `Tests/` with its own toc and removed from the shipping toc. A second toc in the addon root would have re-created the double-load.
- New `TacoTip-Client` in-game suite covering detection, flag exclusivity, the legacy alias, the locale registry, override handling and font filtering.
- New `Tests/harness/` — plain-Lua harnesses that load the real addon against a mocked environment, needing no game client: `detect_test.lua`, `locale_test.lua`, `font_test.lua`, `load_test.lua`, `options_test.lua`, `settings_test.lua`, `tooltip_test.lua`.
- New `Tests/harness/run_all.sh` runs the entire matrix in one command — **50 invocations** across all five clients, both `GetBuildInfo` slot layouts, both settings-registration paths, both Pawn states, and two permutations that blank a Blizzard global to prove the file-scope hooks are guarded rather than fatal. It prints the failing invocation names and exits non-zero, so "all harnesses pass" is a single command rather than a list to remember.
- `options_test.lua` builds all four options pages and exercises `RefreshOptionsUI` / `OpenOptionsPanel` on every client **and** every capability permutation: with and without the `Settings` namespace (modern vs legacy `InterfaceOptions_AddCategory` path), without `ColorPickerFrame`, and without LibSharedMedia — including the worst case with all three absent.
- `tooltip_test.lua` asserts the enhancement pipeline actually produces output — GearScore, iLvl and specialization lines for self, other player, hostile NPC and items — across both delivery paths: the `OnTooltipSetUnit` / `OnTooltipSetItem` script hooks used on the Classic family, and the `TooltipDataProcessor` post-calls used on Retail and WoW Forever, including the `data.guid` resolution branch.
- The in-game suite previously drove only the legacy `OnTooltipSetUnit` script path; the `TooltipDataProcessor` branch that Retail actually takes was never exercised, which is how the dead registration shipped.
- The harness now models the **Frame / Region split**: `Texture` and `FontString` widgets do not carry the frame-level methods, because on Retail and WoW Forever a `Texture` is a `Region` and `SetFrameLevel` / `GetFrameLevel` / `SetFrameStrata` / `GetFrameStrata` do not exist on it. Only that verified split is removed — a wider speculative removal would be unverified and would only manufacture false failures. The mock previously handed every widget every method, which is precisely why the `SetFrameLevel` call shipped. With the mock corrected, reverting the guard fails Retail and WoW Forever and still passes TBC Anniversary, matching the reported asymmetry exactly; the same property is asserted for the `HookScript` and `CreateFrame` guards.
- New in-game tests: `Client:TooltipDeliveryPath`, `Client:WidgetTypesAreNotFrameTypes`, `Client:TextureIsARegion` and `Client:CharacterFrameHostExists`. The last two pin the Region/Frame split and the Classic-only frame set per client, so those assumptions cannot be reintroduced silently.
- `Stats:PawnCrossEngineScales` asserted nothing. It passed scale-*looking* strings (`"Classic:WarriorArms"`, `"MrRobot:WarriorArms"`) as `GetScore`'s **guid** argument; `getPlayerGUID` rejected them, so `GetScore` returned at its early-out and the entire scale-name path — the code that shipped the defect — was never run. It asserted only that a nil-guarded early return does not throw, and its name claimed coverage of a "MrRobot" scale that was never actually exercised. Replaced by `Stats:PawnScaleNameContract`, which drives a real player GUID, wraps `PawnGetScaleColor` and `PawnIsScaleVisible` to observe them, and asserts `GetScore` does not raise, visibility is never probed, **every name handed to `PawnGetScaleColor` already exists in `PawnCommon.Scales`**, and that at least one call was actually made so the rest cannot pass vacuously. The existence check — not a hardcoded library name — is the invariant, because the correct name differs by client. Pawn's real behaviour cannot be mocked, so this one has to be asserted in game.
- The tooltip harness models the two talent surfaces **separately**: the Classic family gets `GetNumTalentTabs` and reads the icon from the library's **static** talent table (`CI:GetTalentInfoByClass`), with no `GetInspectSpecialization`; the modern clients get `GetSpecialization` / `GetInspectSpecialization` / `GetClassIDFromSpecID` / `GetNumSpecializationsForClassID`, a `Texture` overlay instead of a `|T` escape, and **no** `GetNumTalentTabs` at all. A single shared mock had been giving the modern clients talent tabs, so the modern talent path was never exercised and its zero output went unnoticed.
- The harness now models **real per-talent ranks** for a two-spec character (group 1 → tab 1 with 21 points, group 2 → tab 2 with 31 points) and asserts the rendered result per group on every client: `[21/0/0]` active and `[0/31/0]` inactive, each carrying an inline `|T` icon. Icon values in the model are deliberately 6-digit fileIDs while ranks are small integers, so the assertion "talent points are small integers, not fileIDs" is what catches a regression of the bug this release fixes.
- It also asserts the active group resolves to 1, that group 1 maps to tab 1 and group 2 to tab 2, and that the Classic family creates no `Texture` overlay, so its rendering path is provably unchanged.
- Two harness defects were found and fixed while doing this, both of which had been masking real gaps: it gave the modern clients talent tabs, so the modern talent path was never exercised; and it wrongly nil'd `GetTalentInfo` / `GetNumTalents` for Titanforge, which zeroed its talent points. Both APIs **do** exist on Titanforge — `GetTalentInfo` plus `TalentInfoQuery`/`TalentInfoResult` are in the generated `C_SpecializationInfo` docs for `classic_titan`, and `GetNumTalents` has 3 real call sites on every Classic branch.
- **`pawn.lua` was never actually executed by four of the five harnesses.** Its
  file-scope `isPawnLoaded` gate returns early unless a Pawn version global or the
  Pawn API exists, and only `settings_test.lua` mocked any of them — so
  `load_test.lua`, `options_test.lua` and `tooltip_test.lua` each loaded the file
  and immediately fell out of it. `load_test.lua` now mocks Pawn on every family.
- **`load_test.lua` now models Pawn's two gated providers per client** and records
  anything written to the chat frame, so the assertion is literally *"the chat frame
  stayed clean"*. Both wrong answers were reintroduced to prove the test bites, and
  each fails on exactly the clients it should: the original `"MrRobot"`-first probe
  fails on the **Classic** family, and a hardcoded `"Classic"` prefix — the fix that
  was shipped first and did not work — passes Classic and fails on **Retail and WoW
  Forever**. A companion check asserts the names actually reached
  `PawnGetScaleColor`, so the chat assertion cannot pass vacuously by never running.
- **The Pawn mock reproduces the *channel*, not an exception.** The real failure
  mode is a chat write, so the mock writes to chat rather than raising; an
  exception-throwing mock would let a bug pass by being swallowed by `pcall`.
- `load_test.lua`'s `C_Timer.After` change was reverted: with the Pawn probe
  removed no test needs to flush a deferred callback, and an unused queue would be
  dead code.
- **The Pawn mock reproduces the API's rejection, not just its returns.** The real
  scale APIs raise for an unknown name; a mock that returned `false` is precisely
  what let a shipped chat-spam defect pass a green suite. `C_Timer.After` in
  `load_test.lua` also had to start recording callbacks instead of discarding
  them, or `_TacoTipPawnReady` would stay `false`, the colour call would be
  skipped, and the scale-name assertion would pass vacuously. This is the fourth
  instance this release of a mock that modelled a return value where the real API
  rejects — after all-methods widgets hid the `Region`/`Frame` split, a no-op
  `hooksecurefunc` hid the unguarded `HookScript`, and mock-inventing
  `CharacterModelFrame` hid the missing frame on Retail.
- `locale_test.lua` covers the Titanforge pin: Titanforge resolves to `zhCN` whatever `GetLocale()` reports, an explicit override still wins on Titanforge, and the other four families continue to follow the client language. `load_test.lua`'s active-locale assertion is family-aware for the same reason.
- `Tests/harness/README.md` documents the mocking invariants that the assertions depend on, so a future mock change cannot silently make a whole file pass for the wrong reason.

#### Settings frame

`options_test.lua` only proved the pages *build*. It never asked whether the
controls were *bound*, so a control wired to the wrong key, a typo'd setting name,
or a setting with no control at all would pass. `settings_test.lua` closes that
gap without hand-maintaining a control-to-key mapping: it drives every control the
build created, diffs `TacoTipConfig` before and after, and asserts that the set of
settings the controls can reach is exactly the set `GetDefaults()` declares. It
runs 20 ways (5 clients × 2 registration paths × 2 Pawn states) and asserts:

- all **66** settings are reachable from a real control, and no control writes a
  key that is not a declared setting;
- every setting is read by at least one runtime file, so nothing is dead weight;
- values survive a save/load round-trip, a missing saved key is backfilled from
  the default, and an out-of-range saved value is clamped rather than accepted;
- **Reset configuration** restores every default (it is located by *behaviour*,
  because labels are localised and Titanforge runs in Chinese — an English string
  match finds nothing there);
- each client uses the right registration API: `Settings.RegisterCanvasLayoutCategory`
  + `RegisterAddOnCategory` + 3 subcategories + `OpenToCategory` on Retail and
  Forever, `InterfaceOptions_AddCategory` (root + 3 children) +
  `InterfaceOptionsFrame_OpenToCategory` on the Classic family, with the two paths
  also cross-checked in the opposite configuration;
- the achievement-points toggle is enabled on Titanforge / Retail / Forever and
  disabled on Classic Era / TBC, and the Pawn toggle is gated on Pawn being
  installed — both asserted from the **default** state, so the gating is verified
  where the user actually meets it;
- no control handler raises an error, and no control reaches the runtime error
  handler.

The options UI turns out to **cascade**: a control is disabled while the setting it
depends on is off, so a single sweep only reaches what is reachable from the
default state. The harness therefore walks the dependency tree in rounds, re-opening
the cascade before each control, with no parent/child table hardcoded. The settings
found gated in the default state are exactly the expected ones — the eight overlay
offsets, `show_gs_items_hs`, `show_guild_rank`, `tooltip_portrait_3d`, the portrait
scale and zoom, and `unlock_info_position`.

Writing it surfaced four defects in the harness itself, each of which had been
masking real coverage: the sweep only looked at *named* widgets, so the nameless
"Reset configuration" button was never clicked (`createOptionsButton` is the one
builder that does not default a global name, matching the Classic reference); the
enable-state test used the `a and b or true` trap, which is always true when the
middle term is false and so marked every disabled widget enabled; `onValueChanged`
was invoked as a method though it is declared `function(value)`, writing the
control itself into the config; and the mock `ColorPickerFrame` took positional
arguments where the real API takes one info table and calls back through
`swatchFunc`, so the colour swatches appeared to bind to nothing. Two further mock
gaps were needed for the buttons to work at all: named frames must become globals
(as they do in WoW) and `xpcall` must exist and route to its handler.

No addon source change was required.

### API audit

A usage-based sweep (not a doc-table lookup) of every UI, unit, item, timer and
namespace API the addon calls, counted against real call sites in each
Blizzard branch, found three genuine cross-client gaps and confirmed the rest:

- `GetNumTalentTabs` **does not exist on WoW Forever or Retail** (3 call-site
  files on each Classic branch, 0 on Forever/Retail). `cacheUnitData` and
  `GetSpecializationIndex` / `GetTalentPoints` all test it before calling, and
  the `elseif` is preceded by the `C_SpecializationInfo.GetInspectSpecialization`
  arm — which exists only on Forever/Retail (0 on the Classic branches). The
  two families therefore dispatch to complementary branches, and neither path
  can reach a missing function.
- `C_SpecializationInfo.GetInspectSpecialization` is modern-only; already
  `pcall`-guarded, because Retail marks it secret-restricted.
- `InterfaceOptions_AddCategory`, `InterfaceOptionsFrame_OpenToCategory` and
  `InterfaceOptionsFrame_Show` have **no** occurrences anywhere in the
  FrameXML source on any branch — they are engine-exposed, not shipped as
  FrameXML, so their presence cannot be confirmed from source either way. The
  legacy options path is therefore covered by the offline harness (which
  exercises it with the namespace absent) rather than by a source check.

---

## [0.7.7] — 2026-09-21

### Universal Cross-Engine Architecture

- **Multi-Engine Client Family Detection (`LibForeverInspector`):**
  - Added runtime engine detection routines: `IsRetail()`, `IsForever()`, `IsWotlk()`, `IsTBC()`, and `IsClassic()`.
  - Registered backward-compatible `LibClassicInspector` alias inside `LibStub` to preserve complete transparency for legacy modules.
  - Client Build Major detection distinguishes Classic Era (1), TBC (2), WotLK (3), WoW Forever (`interfaceVersion >= 16000`), and Retail (`clientBuildMajor >= 10` or `WOW_PROJECT_MAINLINE`).

- **Dynamic Tooltip Hooking Pipeline:**
  - Modern engines (Retail / Forever): Uses `TooltipDataProcessor.AddTooltipPostCall` for unit (`Enum.TooltipDataType.Unit`) and item (`Enum.TooltipDataType.Item`) processing.
  - Classic engines (Classic Era / TBC / WotLK): Uses secure script hooks `GameTooltip:HookScript("OnTooltipSetUnit")` and `OnTooltipSetItem`.
  - Unified unit resolution (`resolveTooltipUnit`) seamlessly handles `TooltipUtil.GetDisplayedUnit(tooltip)`, `tooltip:GetUnit()`, and GUID fallback matching.

- **Adaptive GearScore & Item Level Engine:**
  - Dynamic bracket sizing: 200 for Classic Era, 400 for TBC Anniversary, and 1000 for WotLK, WoW Forever, and Retail.
  - Safe `C_Item.GetItemInfo` / `GetItemInfo` dual-bridge resolution.
  - Uncached equippable item handling with `C_Item.ContinueWithCancelOnItemLoad` and `C_Item.RequestLoadItemDataByID`.

- **Pawn Universal Compatibility:**
  - Dynamic Pawn scale detection supporting modern `"MrRobot:"` scales and legacy `"Classic:"` scales.
  - Dual version gating accepting `PawnLastUpdatedVersion` (Retail/Forever), `PawnClassicLastUpdatedVersion` (Classic), and direct public function signatures.
  - Safe-guarded all score lookups against missing globals or unexpected return values.

- **Cross-Engine Talent Points Resolution:**
  - Audited Blizzard FrameXML UI source (`wow-ui-source`) across all client branches.
  - Implemented `getTalentTabPoints` in `LibForeverInspector` to automatically handle 3-return (1.12 legacy), 5-return (Classic Era / TBC Anniversary / WotLK), and 7-return (`C_SpecializationInfo.GetSpecializationInfo`) layouts without data truncation.
  - Implemented gender-correct specialization names via `UnitSex` and `GetSpecializationInfoByID`.

- **Universal Settings & ColorPicker UI:**
  - Dual settings registration supporting modern `Settings.RegisterCanvasLayoutCategory` / `Settings.RegisterCanvasLayoutSubcategory` and legacy `InterfaceOptions_AddCategory`.
  - Universal color picker bridging modern `ColorPickerFrame:SetupColorPickerAndShow(info)` and legacy `ColorPickerFrame:SetColorRGB(...)` / callback properties.

- **Zero-Allocation Tooltip Pipeline:**
  - Static record pooling via `addLineDouble(...)` and `addLineSingle(...)` with `wipe(pooledTooltipText)` and `wipe(pooledLinesToAdd)` eliminating memory pressure and GC spikes on high-frequency mouseovers.
  - Synchronous visual isolation (`clearTooltipVisuals`) resetting borders, portraits, models, and power bars on every non-unit transition.
  - Integer-floored color codes (`makeColorCode`) preventing float precision formatting issues in modern Lua.

- **Automated In-Game Testing (`/tttest`):**
  - Full 10-suite WoWUnit automated test suite verifying Core, Config, Borders, Portrait, Guild, Stats, Mover, Modules, MinimapAndAnchor, and Lifecycle invariants (162 tests passing).
