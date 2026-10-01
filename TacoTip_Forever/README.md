# TacoTip [path: /home/sam/TacoTip-Gearscore-TBC/TacoTip_Forever]

TacoTip is a character, item and guild tooltip enhancement that runs on **every**
World of Warcraft engine family from one build — no per-client downloads, no
"which version do I install" question:

| Client | Interface |
| :--- | :--- |
| **Classic Era / Season of Discovery (SoD)** | `11509` |
| **The Burning Crusade Classic Anniversary** | `20506` |
| **WotLK Titanforge** | `38002` |
| **WoW Forever** | `16001` |
| **Retail / Live (The War Within & Midnight)** | `110002`, `110100`, `110200`, `120000`, `120100` |

> **This release replaces the previous Classic-only TacoTip.** It is the same
> addon, continued — your existing configuration carries over, and the GearScore
> numbers you are used to are unchanged on the Classic clients. What is new is
> that the identical build now also works on WoW Forever and Retail.

---

## What's New in 0.7.8

**This is the first cross-engine release.** Highlights; full detail in
[CHANGELOG.md](CHANGELOG.md):

- **One build, five client families.** The addon previously loaded twice, failed
  to load on Titanforge, and silently fell back to stock Blizzard tooltips on
  TBC Anniversary and Titanforge. All fixed.
- **Retail and WoW Forever now actually work.** Two file-scope defects left those
  clients running *half* the addon — an unguarded `OnTooltipSetUnit` hook that
  raised before the rest of `main.lua` could load, and an invalid
  `CreateFrame("Texture", ...)` call. Neither is visible on the Classic family,
  which is why it only ever surfaced on modern clients.
- **GearScore bracket corrected on WoW Forever.** Forever is a Classic-like
  client (level cap 60) and had been inheriting Retail's 1000 bracket, inflating
  every score 5x and flattening the quality colour ramp into a single band.
- **The 3D portrait stopped blinking.** It was being destroyed and reloaded
  roughly twice a second while hovering a unit frame. `PlayerModel:SetUnit` loads
  asynchronously, so every teardown produced a visible flash.
- **A stray specialization icon no longer appears on the wrong character.**
  Retail / WoW Forever only; the Classic icon path was never affected.
- **Pawn no longer spams your chat frame.** The scale library is resolved per
  client rather than guessed. The old guess spammed
  *ScaleName must be the name of an existing scale* on every character tooltip —
  the one defect `pcall` could not silence, because Pawn reports it by writing
  to the chat frame.
- **`/tacotip diag`** so a partial load is diagnosable instead of reporting
  "try /reload".

- **Classic Era / Season of Discovery (SoD)**: Interface `11509`
- **The Burning Crusade (TBC) Classic Anniversary**: Interface `20506`
- **WotLK Titanforge**: Interface `38002`
- **WoW Forever**: Interface `16001`
- **Retail / Live (The War Within & Midnight)**: Interfaces `110002`, `110100`, `110200`, `120000`, `120100`

## Key Features & Architecture

1. **Multi-Engine Client Detection:**
   - Powered by `LibForeverInspector` with runtime client gates: `IsClassic()`, `IsTBC()`, `IsWotlk()`, `IsForever()`, and `IsRetail()`, plus `IsUnknown()`.
   - Identity is resolved from `WOW_PROJECT_ID` (distinct per Classic client) with the interface version used only to separate WoW Forever from Retail, which share `WOW_PROJECT_MAINLINE`.
   - The interface number is read from whichever `GetBuildInfo()` return slot is numeric, so detection does not depend on the return layout, which is only documented for Retail and Forever.
   - Exposes `CI.family` (`classicEra` / `tbc` / `titanforge` / `forever` / `retail` / `unknown`) and a `CI.caps` capability snapshot.
   - An unrecognised client resolves to `family == "unknown"` rather than silently inheriting a default.
   - Backward-compatible alias `LibStub("LibClassicInspector")` provided for existing modules, registered with a minor version.

2. **Adaptive GearScore & Item Level Engine:**
   - Client-aware quality bracket sizing: **200 for Classic Era and WoW Forever, 400 for TBC, 1000 for Titanforge and Retail**.
   - WoW Forever is a Classic-like client (level cap 60, no level scaling) and previously inherited the 1000 default, which inflated every score 5x and collapsed the colour ramp into a single band.
   - The bracket is a pure mapping: `GS_Quality` is keyed off `BRACKET_SIZE` at load and item level passes through raw, so each client gets the correct colour ramp with no formula change.
   - Dynamic `C_Item.GetItemInfo` and `GetItemInfo` resolution with instant caching.
   - Support for Retail / Live stat calculations and item comparison.

3. **Pawn Integration:**
   - The scale library is **resolved per client, never hardcoded.** Pawn's `Pawn.toc` gates its two providers by game type — `AskMrRobot.lua` is `[AllowLoadGameType mainline]` (`"MrRobot"`, Retail + WoW Forever) and `ClassicHawsJon.lua` is `[AllowLoadGameType classic]` (`"Classic"`, Vanilla/TBC/Wrath) — so exactly one exists per client and the correct prefix differs between them.
   - Resolution reads Pawn's own globals, `PawnScaleProviders` and `PawnCommon.Scales`, and is completely silent. Pawn's own API **cannot** be asked: `PawnIsScaleVisible` and `PawnGetScaleColor` report an unknown name through `VgerCore.Fail`, which does not raise a Lua error but writes straight to `DEFAULT_CHAT_FRAME`, so `pcall` cannot suppress it. `PawnGetScaleColor` is therefore only ever called with a name already proven to exist in `PawnCommon.Scales`; when none matches, the colour is skipped.
   - Score lookups go through `PawnGetSingleValueFromItem`, which answers `0` for an unknown name and never calls `VgerCore.Fail`, so both libraries are tried and the score works on every client.
   - Version detection supporting modern `PawnLastUpdatedVersion` and legacy `PawnClassicLastUpdatedVersion`.

4. **Zero-Allocation Tooltip Pipeline:**
   - Static pooled record buffers (`pooledLinesToAdd`, `pooledTooltipText`, `pooledPlayerText`) eliminating garbage collection pressure on high-frequency mouseovers.
   - Integer-floored color formatting (`makeColorCode`) strictly preventing Lua 5.3+ float representation errors.
   - Dynamic visual clearing (`clearTooltipVisuals`) isolating non-unit tooltips (items, spells, map POIs) from stale unit overlays.
   - Tooltip hooking selects on whether the tooltip **actually runs the data pipeline** (probing `IsTooltipType` / `GetPrimaryTooltipData`, which come from `TooltipDataHandlerMixin`), not on whether `TooltipDataProcessor` merely exists. TBC Anniversary and Titanforge define the processor but do not mix in the handler, so a presence-only test registered a callback that never fired and both clients showed stock Blizzard tooltips.
   - Both hook paths are registered as insurance; the duplicate is inert because Blizzard's pipeline-client tooltips do not fire `OnTooltipSetUnit` / `OnTooltipSetItem`.
   - `tooltip_max_width` is implemented by capping the line `FontString` widths, since `GameTooltip` has no `SetMaximumWidth` on any supported client.

5. **Universal Options UI:**
   - Supports modern `Settings.RegisterCanvasLayoutCategory` and legacy `InterfaceOptions_AddCategory`.
   - Client-adaptive toggles (e.g. Achievement Points toggle dynamically enabled on Titanforge, Retail, and Forever; cleanly hidden on Classic Era / TBC).

6. **Talents & Specializations:**
   - Per-client talent data that does **not** depend on the `loadDeprecationFallbacks` CVar:
     - **Classic Era / TBC Anniversary / Titanforge** — points are the sum of each talent's `rank` within a tab, read via `C_SpecializationInfo.GetTalentInfo` (query form `specializationIndex` + `talentIndex`, which is what `Vanilla\TalentFrameBase.lua` uses on all three). This is the algorithm from the known-good Classic addon.
     - **WoW Forever / Retail** — per-specialization `pointsSpent` + `previewPointsSpent` from `C_SpecializationInfo.GetSpecializationInfo`, which has an identical 7-argument signature and 10-value return on all five clients.
   - **Dual specialization** is gated by `hasDualSpec` (`isWotlk or isTBC or (C_SpecializationInfo ~= nil) or (_G.GetNumTalentGroups ~= nil)`), so it is available on Classic Era, TBC Anniversary and Titanforge and refused where unsupported. The definition matches the known-good Classic addon, with the last term read through `_G` so it is nil-safe.
   - Per-group data throughout: `GetTalentPoints` / `GetSpecialization` accept a group, the inspect cache holds `talentPoints[group][tab]` and `specIndexByGroup[group]`, and the modern resolver uses `GetSpecialization(isInspect, isPet, groupIndex, 1)` — the only group-aware form, since `GetInspectSpecialization(unit)` takes just a unit and cannot tell group 1 from group 2.
   - `GetActiveTalentGroup` resolves the real active group for self **and** inspected units, so the greyed specialization is always the inactive one.
   - `GetSpecialization` returns a 1-based **index**, not a specID. The modern clients previously returned `GetSpecialization()` (an ID such as `72`), which made `spec_table[class][72]` nil and removed the entire specialization line on Retail and Forever.
   - Icons resolve per client. On Classic they come from a **static talent table** ported verbatim from `LibClassicInspector` (~1840 records) as **numeric fileIDs**, inlined with `tostring()` because a `|T` escape accepts a fileID as well as a texture path. Each expansion selects its own set: Classic Era 18 talents in Warrior tab 1 (Vanilla), TBC Anniversary 23 (TBC), Titanforge 31 (WotLK, Death Knight included). On Retail/Forever they come from `GetTalentInfo` using the **tier/column** query form `[Family]\TalentFrameBase.lua` uses, drawn with a `Texture` overlay since a fileID cannot go in a `|T` escape.

7. **Localization:**
   - Every `Locale/*.lua` registers its table into `TACOTIP_LOCALES` under its own code; `enUS.lua` is the single selector and exposes `TacoTipApplyLocale()`.
   - Resolution order: `TacoTipConfig.locale_override` (always wins) → **WotLK Titanforge, pinned to `zhCN`** → the client language when a table ships for it → English. Titanforge is the Chinese build of WotLK, so it is pinned rather than trusting `GetLocale()`. English is both the default and the per-key fallback every other language layers over.
   - Selection is re-applied on `ADDON_LOADED`, because addon files run *before* WoW populates `SavedVariables`, so `TacoTipConfig.locale_override` is unreadable during file execution.
   - `TacoTipApplyLocale` mutates `TACOTIP_LOCALE` in place so the `local L` bindings in `main.lua` / `gearscore.lua` / `options.lua` observe the override.
   - `enGB` maps onto `enUS`. Per-client font filtering hides CJK fonts on non-CJK clients and drops third-party Details fonts.
   - Specialization names come from the library's built-in table on the Classic family, and from the client's own localized `GetSpecializationInfo` on Retail and Forever. The previous per-locale `TACOTIP_SPEC_NAMES` / `TACOTIP_SPEC_ICONS` lookups were removed: nothing ever wrote those globals, so they were always nil and the comments claiming they honoured the language override were false.

---

## Directory Structure

```text
TacoTip_Forever/
├── Libs/
│   ├── LibStub/
│   ├── CallbackHandler-1.0/
│   ├── LibForeverInspector/
│   └── LibDetours-1.0/
├── Locale/
│   ├── enUS.lua (Source of Truth)
│   ├── deDE.lua, esES.lua, esMX.lua, frFR.lua, itIT.lua,
│   └── koKR.lua, ptBR.lua, ruRU.lua, zhCN.lua, zhTW.lua
├── textures.lua
├── gearscore.lua
├── pawn.lua
├── options.lua
├── main.lua
├── TacoTip.toc
└── Tests/                     (not shipped — opt-in)
    ├── TacoTip_Forever_Tests.lua
    ├── TacoTipTests.toc
    └── harness/               plain-Lua verification, no game client needed
        ├── detect_test.lua, locale_test.lua, font_test.lua,
        ├── load_test.lua, options_test.lua, tooltip_test.lua,
        └── talent_check.lua
```

**The `.toc` filename must match the addon folder name** — that is a hard
requirement of the loader, not a convention. This addon is shipped as
`TacoTip/TacoTip.toc`, replacing the previous Classic-only `TacoTip`. Nothing in
the code depends on the name: `main.lua` takes its table from
`_G[addOnName]` (`...`), so the folder name only ever has to match the `.toc`.

Only `TacoTip.toc` is shipped, and there must be exactly one. An earlier revision
carried a second, byte-identical `.toc`; because WoW loads *every* `.toc` in an
addon folder, that executed the whole addon twice on every client and
registered the tooltip hooks twice.

---

## Troubleshooting

If something looks inert, run this first:

```
/tacotip diag
```

It reports the version, whether `main.lua` finished loading, the last load stage
reached, the detected client family and interface, the type of each key global
(`TacoTip_CustomPosEnable`, `TT.ApplyTooltipAppearance`, `TT.OpenOptionsPanel`,
`TT.RefreshOptionsUI`, `TT.SyncTooltipMover`), the GearScore bracket and the active
locale.

`load OK: NO` means `main.lua` raised an error while loading. `main.lua` is the
last file in the toc and defines the tooltip mover at its very end, so a partial
load leaves the options frame fully working while the mover, the tooltip pipeline
and the overlays are all silently missing. The reported stage names the region to
look at. **A reload does not fix this** — install a Lua error handler (BugSack or
Swatter) and read the error it captures.

Other slash commands: `/tacotip` opens the options, `/tacotip custom` shows the
tooltip mover, `/tacotip save` saves the current mover position, `/tacotip default`
clears the custom position, `/tacotip anchor <corner>` sets the anchor.

---

## Verification & Testing

- **Luacheck Static Analysis:**

  ```bash
  luacheck TacoTip_Forever/
  # Result: 0 warnings / 0 errors
  ```

  Note this is a weak gate for cross-client work: `read_globals` pre-declares the
  API surface, so luacheck is structurally incapable of detecting an API that is
  missing on a given client.

- **Offline harness (no game client required).** Loads the real addon files
  against a mocked WoW environment — see `Tests/harness/README.md`:

  ```bash
  lua5.1 Tests/harness/detect_test.lua   # client detection, all 5 families
  lua5.1 Tests/harness/locale_test.lua   # locale registry, selection, override, Titanforge pin
  lua5.1 Tests/harness/font_test.lua     # per-client font filtering
  lua5.1 Tests/harness/load_test.lua 2 11509 slot4 classicEra 200 ERA

  lua5.1 Tests/harness/options_test.lua 2 11509 ERA
  lua5.1 Tests/harness/settings_test.lua 2 11509 CLASSIC_ERA legacy settings pawn
  lua5.1 Tests/harness/tooltip_test.lua 2 11509 CLASSIC_ERA
  lua5.1 Tests/harness/tooltip_test.lua 1 120100 RETAIL pipeline
  lua5.1 Tests/harness/talent_check.lua 11 38002 TITANFORGE
  ```

  The load harness runs each client under **both** plausible `GetBuildInfo()`
  return layouts, so nothing depends on which slot carries the interface number
  on the Classic clients — a question the Blizzard source does not settle.

  To run the whole matrix (50 invocations across all five clients, both
  registration paths and both Pawn states):

  ```bash
  bash TacoTip_Forever/Tests/harness/run_all.sh
  ```

  `options_test` builds all four options pages on every client and under every
  capability permutation (no `Settings` namespace, no `ColorPickerFrame`, no
  LibSharedMedia, and all three missing at once), which is what covers the
  legacy `InterfaceOptions_AddCategory` path and optional-dependency
  degradation. `tooltip_test` asserts the enhancement pipeline actually emits
  GearScore / iLvl / specialization lines, through both the script hooks used on
  the Classic family and the `TooltipDataProcessor` post-calls used on Retail
  and WoW Forever, and asserts the **dual-spec readout per group** with inline
  `|T` talent icons and correct active/inactive colouring. `talent_check` verifies
  the ported static talent table resolves real icons for each expansion.

  > **On mock-derived assertions.** A mock cannot settle Blizzard's exact shim
  > return shapes, so asserting numbers the mock itself invented only proves the
  > mock agrees with itself. The talent tests therefore assert the
  > version-independent invariant instead: **ranks are small integers, icon
  > values are 6-digit fileIDs, and the rendered readout must be the former and
  > never the latter.** That is precisely the bug this release fixes, and it is
  > now caught by a check that cannot be satisfied by a self-consistent mock.

- **WoWUnit In-Game Test Suite (opt-in).** Copy `Tests/` to
  `Interface/AddOns/TacoTipTests/`, enable it alongside the addon, then
  type `/tttest`. 11 suites:
  - `TacoTip-Core`
  - `TacoTip-Config`
  - `TacoTip-Borders`
  - `TacoTip-Portrait`
  - `TacoTip-Guild`
  - `TacoTip-Stats`
  - `TacoTip-Mover`
  - `TacoTip-Modules`
  - `TacoTip-MinimapAndAnchor`
  - `TacoTip-Lifecycle`
  - `TacoTip-Client` (detection, alias, locale registry, override including the
    Titanforge `zhCN` pin, font filter, and cross-engine talent point / spec
    index / active-group invariants)


## Inspection scheduling

Background tooltip inspections use a GUID-keyed queue (20 players maximum).
Requests wait during combat or while the standard inspect window is open, and
resume automatically. Requests share a 2-second delay with other inspect callers;
missing or partial responses retry up to 3 times with a 5-second timeout, then
back off for 10 seconds. A temporarily missing or uninspectable player stays
queued for up to 15 seconds after the scheduler first detects the problem,
without blocking other players; expiry also starts a 10-second cooldown.
Every background attempt first checks inspect interaction distance. A distant
player is deferred without calling `CanInspect`/`NotifyInspect`; unavailable or
restricted range information is also deferred. General UI errors are not filtered.
Complete inventory and talent data are cached for 10
seconds, with at most 500 cached players. Inventory change events refresh items
without replacing talent data from another inspection. Requests follow players
across target, mouseover, focus, party and raid tokens; this does not scan entire
groups automatically.

For live verification, open a nearby player's inspect window, move the mouse
between other players, then close the window and keep a tooltip open. Check that
gear loads, queued tooltips recover without another hover, and combat/target
changes do not produce wrong-player gear or Lua errors.
