---
name: TacoTip
version: 0.8.4
author: AcidBomb
maintainer: AcidBomb (Pilsung)
license: MIT  # see LICENSE; bundled Libs/ keep their own terms
curseforge_id: 1555962
project_url: https://www.curseforge.com/wow/addons/tacotip-gearscore
clients: [Classic Era / SoD, TBC Anniversary, WotLK Titanforge, WoW Forever, Retail]
interfaces: ["11509", "20506", "38002", "16001", "120105"]
tags: [tooltip, gearscore, gear-score, 3d-portrait, class-colors, talents, pawn, inspect, enhancement, cross-engine]
optional_dependencies: [LibStub, CallbackHandler-1.0, LibDetours-1.0, Pawn, LibSharedMedia-3.0, SharedMedia]
optional: [WoWUnit]
status: released
updated: 2026-10-20
---

# TacoTip | Gearscore & iLvL

TacoTip is a character, item and guild tooltip enhancement that runs on **every** World of Warcraft engine family from one build — no per-client downloads, no "which version do I install" question:

*   **CurseForge** — [https://www.curseforge.com/wow/addons/tacotip-gearscore](https://www.curseforge.com/wow/addons/tacotip-gearscore) (this add-on)
*   **<span style="color:#e67e23"><span style="text-decoration:underline">Companion Add-on</span></span>** — [TacoTip Extras](https://www.curseforge.com/wow/addons/tacotip-extras) ![TacoTip Extras](https://media.forgecdn.net/attachments/2065/485/2-png.png) — a separate add-on with its own CurseForge listing, published alongside this one

| Client | Interface |
| :--- | :--- |
| **Classic Era / Season of Discovery (SoD)** | `11509` |
| **The Burning Crusade Classic Anniversary** | `20506` |
| **WotLK Titanforge** | `38002` |
| **WoW Forever** | `16001` |
| **Retail / Live (Midnight)** | `120105` |

> **This release replaces the previous Classic-only TacoTip.** It is the same
> addon, continued — your existing configuration carries over, and the GearScore
> numbers you are used to are unchanged on the Classic clients. What is new is
> that the identical build now also works on WoW Forever and Retail.

**Dependencies.** `TacoTip.toc:9` declares `## OptionalDependencies: LibStub,
CallbackHandler-1.0, LibDetours-1.0, Pawn, LibSharedMedia-3.0, SharedMedia`, and
the front matter above lists the same six under `optional_dependencies:` to
match. Three of them — `LibStub`, `CallbackHandler-1.0` and `LibDetours-1.0` —
are **bundled** under `Libs/` and are therefore always present; the add-on
stops loading with a named stage if one of them is somehow missing
(`main.lua:21-30`). The other three — `Pawn`, `LibSharedMedia-3.0` and
`SharedMedia` — are genuinely optional, and every feature that uses them
degrades when they are absent.

---

## What's New in 0.8.4

Background scanning you can switch off, specs you can trust, and failures that speak up instead of going quiet — the scoring numbers themselves are untouched.

- **"Scan nearby players" checkbox** on the Tooltips options page. Leave it on to keep collecting GearScore for players around you; turn it off to stop background requests. Hovering and targeting keep working either way, and the box always shows what is really scanning.
- **No more wrong spec on players you haven't inspected yet.** An uninspected player used to show the first spec for their class until real data arrived. Now the spec line stays off until the inspect completes.
- **Pawn keeps working when you install or turn it on mid-session.** The Pawn option becomes available right away with no reload needed to see it. Scores start showing after the next reload, and /tacotip diag tells you if you are in between.
- **Hunter scoring no longer stays off for a whole session.** If your class wasn't readable at the moment the addon loaded, HunterScore used to stay disabled until you reloaded. Now it checks your class each time it is needed.
- **The power bar keeps updating.** If its preferred setup fails it uses a simpler one instead, so mana, rage, energy and the rest keep moving.
- **Broken panels and options speak up instead of going blank.** If a settings page can't open or a toggle doesn't take, you get a one-line chat message naming it, and it is listed under problems in /tacotip diag.
- **A saved tooltip position now applies to every unit, not just unit frames.** Hovering a player out in the world could leave the tooltip at the bottom-right corner, because the client positions the tooltip *before* it tells it which unit it is showing; your saved position is now applied once the unit is known. If a drag can't be read the previous position is kept instead of being silently replaced, and **"Anchor Spells to Mouse" is now off by default** so spell tooltips respect the saved position too.
- **Tooltips survive rough edges instead of dropping.** Fast mouse-outs no longer lose the tooltip on slow-to-load setups, a background score refresh that hits an error is reported instead of leaving a stale card, and stopping very early while loading names where it stopped in diag.
- **/tacotip diag tells more of the truth you actually meet.** Dropped background requests when the queue overflows, scores held back while item details are still loading, why a unit couldn't be resolved, and how long ago the last inspect problem happened.
- **Small polish: the player-name line is 1px smaller,** and the supported interface band is exactly 11509, 20506, 38002, 16001, 120105.
- **The score on your character and inspect panes is correct the moment you open them.** Both panes could keep showing "0" instead of your real GearScore and item level, because the refresh they relied on never fired. They refresh now, and they refresh again as soon as your own gear finishes loading.
- **The instant-fade option says so when your client can't do it.** On a client without the instant-fade API the option is greyed out and says why, instead of accepting a setting that does nothing, and /tacotip diag now tells you which fade path is in use.
- **You can log out again.** On Classic Era the game's own **Exit Game** and **Log Out** buttons could be refused by the client: the click did nothing and the screen filled with `ADDON_ACTION_FORBIDDEN`. The add-on no longer takes over the sound function the client itself uses, and every add-on callback that runs inside the client's own frames is now contained, so the menu's buttons behave like the client's own.

Full detail is in [CHANGELOG.md](CHANGELOG.md).

## What's New in 0.8.3

Proactive GearScore collection for everyone standing near you, the fix for the repeating "Not in Range" popup, and the portrait fix that only ever showed up on the Classic clients.

- **The repeating "Not in Range" popup is addressed, on every client.** `NotifyInspect` is a *server* request, and a refused inspect puts the red text and sound up through the client's own UI error path. What the FrameXML mirror shows is that path — `UIErrorsFrame` consuming `UI_ERROR_MESSAGE` and speaking it via `C_Sound.PlayVocalErrorSound` — and it does **not** show which call produces it, so the fix covers both candidates rather than guessing. Four separate causes, each independently sufficient to keep it going: distance was measured with `UnitDistance`, which **exists on none of the five supported clients**, so the whole range-learning mechanism was unreachable code; the "don't re-ask" memory was a 10-second *timer* rather than a *state*, so a unit that stayed far was re-asked forever; Classic Era was **misclassified as a modern client** (below), which routed it into the one range policy that permits an out-of-range request; and a refusal no longer lifts just because the unit is merely *still within* 20 yards — it lifts when the unit has actually moved **closer** than it was at the refusal. On Classic Era the refusal is also swallowed inside a short window around the addon's own probes, recorded, and used to learn that client's real range — see the CHANGELOG for exactly what is verified and what is assumed.
- **Classic Era was being detected as a modern client.** Detection required a build-major of `1`, but Classic Era's `GetBuildInfo()` puts `nil` in that slot and the build number in a later one, so Classic Era fell into the "either signal is enough" branch — the only policy that lets an out-of-range inspect through. Identity now comes from `WOW_PROJECT_ID` alone, which is genuinely distinct per Classic client.
- **The 3D portrait no longer disappears and stays gone on the Classic clients.** On a render where the tooltip could not resolve its unit, the portrait was hidden, re-anchored, and **never restored** — the branch that shows it again was never reached. The cause is structural: the Classic script hook discards its arguments, so the GUID fallback that rescues this case simply does not exist on that family. Retail and WoW Forever were never affected.
- **Proximity world scan.** Every ~2 seconds the library walks the visible nameplates, distance-gates each player with the rule that is correct for your client, and inspects the ones in range — so GearScore and item level for someone standing next to you are already cached when you hover them. One inspect request per tick, skipped in combat, and never re-requested while the data is still fresh.
- **Correct range handling on all five clients.** Classic Era / SoD / TBC / Titanforge require *both* `CanInspect` and `CheckInteractDistance(unit, 1)`; Retail and WoW Forever accept either. A single shared constant now drives the range index everywhere.
- **No more queue deadlocks.** If an inspect request never comes back, a watchdog releases the pending slot after 3 seconds instead of stalling every other player behind it.
- **Boundary flicker now costs a skipped inspect instead of an error popup.** An earlier grace period that let a recently-inspected unit through a *failed* distance check was removed: it re-introduced the exact "Not in Range" it was meant to prevent.
- **Cache timestamps come from `GetTime()` (uptime) instead of `time()` (wall clock)**, so a system clock change can no longer make fresh data look expired. The clock read is guarded so a missing API degrades instead of silently killing the inspect pipeline.
- **The unit `Level` label is no longer hardcoded English** on any client — it was the one label bypassing the locale system, so it read `Level` in Korean, Russian and Chinese too.
- **`/tacotip diag` now reports the inspect engine:** notify count, inspects completed, watchdog timeouts, refusals recorded, probe errors suppressed (and separately the spoken and sound halves of what the guard swallowed), the learned maximum range for this client, scan-enqueued, scan-via-fallback and scan-skipped-by-range, plus separate counters for portrait `Hide()` calls versus full teardowns.

> **One correction worth reading.** An earlier revision of this release added `CanInspect(unit, true)` as a range gate, on the belief that the second argument was a range flag. **It is not — it is `showError`.** That call was asking the engine to *display* a message, so the fix for the popup was itself a source of one. It has been reverted, and the full reasoning is in [CHANGELOG.md](CHANGELOG.md) rather than edited away.

Full detail, including the tests that were wrong rather than the addon, is in [CHANGELOG.md](CHANGELOG.md).

---

## What's New in 0.8.2

- **Classic range gate restored:** Classic Era / SoD / TBC / Titanforge require both `CanInspect` and `CheckInteractDistance(unit, 1)`; Retail / Forever still accept either.
- **GearScore / iLvl no longer vanish:** gear-change events mark cached data stale rather than erasing it, so values stay on screen until fresh data replaces them.
- **The tooltip name is 2pt larger than body text.** Previously one size was applied to every line, which flattened the name — the player's on a unit tooltip, the item's on an item tooltip — to body size.
- **Smaller 3D portrait:** the base is now `66 x 88` (was `72 x 96`). Still an exact 3:4 ratio, and still exact integers at every scale stop — `33x44`, `66x88`, `99x132`, `132x176`.
- **New `Invert portrait side` option** (default off) to pin the portrait to the other side of the tooltip.

---

## What's New in 0.8.1

Inspection engine performance, proactive pre-caching, and remote inspect responsiveness. Full detail in [CHANGELOG.md](CHANGELOG.md):

- **Proactive Target Pre-caching (`PLAYER_TARGET_CHANGED`):** Selecting or tab-targeting any inspectable player immediately triggers background inspection, pre-caching their equipment, talents, specialization, and GearScore before you hover over their model or open the inspect window.
- **Eager Mouseover Triggering (`UPDATE_MOUSEOVER_UNIT`):** Sweeping over player models in the 3D game world begins the inspection query immediately without waiting for tooltip layout passes.
- **Group Member Roster Scanning (`GROUP_ROSTER_UPDATE`):** Party and raid member inspections are triggered dynamically on group roster updates.
- **Instant Unit Inventory Refresh (`UNIT_INVENTORY_CHANGED`):** When an inspected player swaps equipment, their cache entry is invalidated and re-inspected immediately.
- **Optimized Throttling & Adaptive Queue Timer:** `INSPECT_DELAY` is `0.4s` on Retail / WoW Forever and `1.0s` on the Classic family. The queue ticker runs at `0.5s` and dispatches the next item promptly on `INSPECT_READY`, so an idle queue does not wait a full tick.
- **Target Prioritization in Queue:** Actively targeted players are prioritized ahead of background group polling.
- **Range handling that matches each client:** the Classic family (Classic Era / SoD / TBC Anniversary / Titanforge) requires **both** `CanInspect` and `CheckInteractDistance(unit, 1)`, and reads the distance signal *first* so a unit the cheap gate rejects is never asked about; Retail and WoW Forever accept either signal. The index is a single shared constant, and the yardage is not hardcoded — it is learned from the client's own refusals (`/tacotip diag` → `learned max range`).
- **"Scanning Equipment..." Deadlock Resolution:** Corrected `LibForeverInspector` `INVENTORY_READY` callback dispatch to pass `(guid, true, unit)`, resolved non-targeted unit tokens via `InspectFrame.unit`, and safely parsed item IDs from links when `GetInventoryItemID` returns nil on remote items.

---

## What's New in 0.8.0

GearScore correctness. This is the first release whose test suite asserts a GearScore **value** rather
than only that scoring does not throw — which is precisely why both bugs below shipped green in 0.7.9.
Full detail in [CHANGELOG.md](CHANGELOG.md):

- **Two-handed weapon math & Titan's Grip correctness.** Standalone 2H weapons (`INVTYPE_2HWEAPON`) occupy slot 16 with slot 17 empty and retain full 2.0x weight (`SlotMOD = 2.0`) so weapon gear budget balances with 1H + Shield wielders (`3625` vs `3624` total at ilvl 200). Titan's Grip dampening (`0.5`) is strictly applied when dual-wielding alongside an offhand weapon or shield (`mainHandLink and offHandLink`), maintaining exact balance for dual 2H Fury Warriors.
- **Asynchronous item loading resilience & nil-safety.** `GetItemInfo` is guarded against nil arguments, and uncached items cleanly return zeroed scalar scores while triggering `C_Item.RequestLoadItemDataByID` without arithmetic or indexing errors.
- **Hunter weapon scaling parity.** Unified Hunter melee (`0.3164x`) and ranged (`5.3224x`) multipliers between character total scoring and single-item tooltip evaluation.
- **An item's tooltip colour now matches the GearScore printed beside it.** The colour band was computed from the slot-mod-free base while the displayed score included the slot modifier, so a 2H and a head of identical item level wore the same colour while showing different numbers. The band is now a pure function of the score shown. **This is the only user-visible colour change in 0.8.0.** Low-slot-mod items shift band: trinket / neck / finger / wrist / cloak (0.5625), shoulder / waist / feet / hands (0.75) and ranged / thrown (0.3164) now colour like the slot they occupy instead of like a head.
- **New `Tests/harness/gearscore_test.lua`**, the first harness to assert numeric scores: per-item score literals, solo 2H full weight, Titan's Grip dual 2H half-weight, an exhaustive enumeration of reachable weapon states, item colour-band consistency across slots and item levels, and Hunter weapon scaling.

---

## What's New in 0.7.9

Portrait, inspect, unit-frame hover, and border correctness across all five client families. Full detail in
[CHANGELOG.md](CHANGELOG.md):

- **Stationary hover on PlayerFrame & TargetFrame no longer flickers or destroys on Retail.**
  In modern Blizzard FrameXML, `UnitFrame_UpdateTooltip` refreshes every 0.2s by calling `SetOwner`
  and `ClearLines`. TacoTip previously treated these transient internal 200ms refreshes as genuine
  tooltip dismissals, tearing down and rebuilding the 3D portrait, power bar, and border overlay
  5 times per second. Fixed with `isUnitFramePeriodicUpdate`, keeping stationary unit-frame hovers
  completely stable with zero model reloads, zero un-anchoring, and zero flicker.
- **Right-click inspect no longer strips gear from the paperdoll on Retail and WoW Forever.**
  `LibForeverInspector` previously called `ClearInspectPlayer()` inside `INSPECT_READY`, which purged
  the inspected unit before Blizzard's `InspectPaperDollItemSlotButton_Update` could read equipment links.
  Fixed by deferring clear until `InspectFrame_OnHide`, adding party/raid member fallback resolution, and
  protecting `InspectGuildFrame_Update` from crashing on guildless inspected players.
- **The 3D portrait stopped strobing on Retail and WoW Forever.** The modern
  client fires tooltip post-calls *before* its own `Show()`, which caused the frame to run against
  unrendered dimensions and re-anchor on every tick. The portrait now anchors once per hover epoch,
  survives item load callbacks, and smoothly flips between screen edges when near display boundaries.
- **Default border set to official Blizzard tooltip border (`Interface\Tooltips\UI-Tooltip-Border`).**
  Replaces previous unverified defaults and ensures native Blizzard appearance across all clients.
  Expanded the border options with verified native Blizzard FrameXML borders (`UI-DialogBox-Border`,
  `UI-DialogBox-Gold-Border`, `UI-Achievement-WoodBorder`, `UI-Party-Border`, `UI-Toast-Border`,
  `TextPanel-Border`, `UI-SliderBar-Border`, `UI-Arena-Border`, `UI-TutorialFrame-CalloutGlow`),
  and removed the non-texture placeholder `None`.
- **`/tt diag` reports problems an error handler cannot see.** BugSack and
  BugGrabber only see *raised* errors. The costliest defects here were the
  opposite: no error, a plausible tooltip, and a feature quietly absent or
  pointed at the wrong thing. It now lists those — ambiguous client detection, a
  border setting that matches nothing, a feature enabled with its backing API
  missing, no delivery path hooked — plus event counters for call frequency.
- **100% Localization parity across all 11 languages.** All 11 shipped locales
  (`enUS`, `deDE`, `esES`, `esMX`, `frFR`, `itIT`, `koKR`, `ptBR`, `ruRU`, `zhCN`, `zhTW`)
  contain 100% key coverage (239/239 keys) with verified syntax and matching `%s`/`%d` format tokens.
- **The power bar is off by default.** Enable it in settings; its colours are
  correct for mana, rage, energy and every other power type on all five clients.

Supported clients:

- **Classic Era / Season of Discovery (SoD)**: Interface `11509`
- **The Burning Crusade (TBC) Classic Anniversary**: Interface `20506`
- **WotLK Titanforge**: Interface `38002`
- **WoW Forever**: Interface `16001`
- **Retail / Live (Midnight)**: Interface `120105`

## Key Features & Architecture

1. **Multi-Engine Client Detection:**
   - Powered by `LibForeverInspector` with runtime client gates: `IsClassic()`, `IsTBC()`, `IsWotlk()`, `IsForever()`, and `IsRetail()`, plus `IsUnknown()`.
   - Identity is resolved from `WOW_PROJECT_ID` (distinct per Classic client) with the interface version used only to separate WoW Forever from Retail, which share `WOW_PROJECT_MAINLINE`.
   - The interface number is read from whichever `GetBuildInfo()` return slot is numeric, so detection does not depend on the return layout, which is only documented for Retail and Forever.
   - Exposes `CI.family` (`classicEra` / `tbc` / `titanforge` / `forever` / `retail` / `unknown`) and a `CI.caps` capability snapshot.
   - An unrecognised client resolves to `family == "unknown"` rather than silently inheriting a default.
   - Backward-compatible alias `LibStub("LibClassicInspector")` provided for existing modules, registered with a minor version.

2. **Adaptive GearScore & Item Level Engine:**
   - Client-aware quality bracket sizing: **200 for Classic Era and WoW Forever, 400 for TBC, 1000 for Titanforge and Retail (Retail: operator hold pending live data)**.
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
   - **Dual specialization** is gated by `hasDualSpec`, which is `isClassic or isTBC or isWotlk` — a *family* test, so it is true on Classic Era, TBC Anniversary and Titanforge and false on WoW Forever and Retail by construction. (An earlier four-term predicate, `(isWotlk or isTBC or (C_SpecializationInfo ~= nil) or (_G.GetNumTalentGroups ~= nil))`, was true on *every* client and so offered dual-spec readout where none exists. That over-claim is the one that shipped.)
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
TacoTip/
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
        ├── run_all.sh              the whole matrix — 70 invocations
        ├── root.lua                shared harness helpers
        ├── mock_contract.lua       the mock-fidelity contract table
        ├── textures.txt            the reviewed texture-path allow-list
        ├── detect_test.lua, locale_test.lua, font_test.lua,
        ├── textures_test.lua, load_test.lua, options_test.lua,
        ├── settings_test.lua, fileguard_test.lua, batch2_pawn_test.lua,
        ├── batch4_clock_test.lua, batch8_pane_test.lua, gearscore_test.lua,
        ├── tooltip_test.lua, taint_test.lua, talent_check.lua
```

The `Libs/` list above is the four libraries the add-on actually loads
(`TacoTip.toc:11-14`). Two further directories are vendored in the working
tree — `Libs/LibDataBroker-1.1/` and `Libs/LibDBIcon-1.0/` — but **neither is
loaded and neither ships**; see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for why, and do not add them
to the TOC without settling their licence first.

The `harness/` list is the **fifteen harness files** the suite runs, plus two
support modules (`root.lua`, `mock_contract.lua`), the runner and the texture
allow-list. `bash Tests/harness/run_all.sh` runs them 70 times across all five
clients.

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

```bash
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

Other slash commands:

- `/tacotip` opens the options.
- `/tacotip custom` shows the tooltip mover.
- `/tacotip save` saves the current mover position.
- `/tacotip default` clears the custom position.
- `/tacotip anchor <corner>` sets the anchor.
- **`/tt lb` opens the TacoTip Extras leaderboard.** The companion
  [TacoTip Extras](https://www.curseforge.com/wow/addons/tacotip-extras) add-on
  owns the leaderboard sub-commands, and `/tt` forwards the word to it. With the
  Extras not installed, `/tt lb` falls back to opening the options page.

---

## Verification & Testing

- **Luacheck Static Analysis:**

  ```bash
  luacheck .
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
  lua5.1 Tests/harness/tooltip_test.lua 1 120105 RETAIL pipeline
  lua5.1 Tests/harness/talent_check.lua 11 38002 TITANFORGE
  ```

  The load harness runs each client under **both** plausible `GetBuildInfo()`
  return layouts, so nothing depends on which slot carries the interface number
  on the Classic clients — a question the Blizzard source does not settle.

  To run the whole matrix (70 invocations across all five clients, both
  registration paths and both Pawn states):

  ```bash
  bash Tests/harness/run_all.sh
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

- **Release packaging (build-time).** Two read-only scripts build the package
  each add-on would ship and check it is runtime files only. Both print the
  archive's file listing, print `PASS`/`FAIL` per check, and exit non-zero on
  failure:

  ```bash
  Tools/verify_release.sh          # the TacoTip package  — 27 files
  Tools/verify_release_extras.sh   # the TacoTip Extras package — 29 files
  ```

  `Tools/verify_release.sh` builds the TacoTip archive with
  `git archive --worktree-attributes HEAD`, filtered by the export-ignore rules
  in `.gitattributes`, and checks there is exactly one `.toc`, that no workshop
  directory or document shipped, and that every remaining file is on the
  runtime allowlist. `Tools/verify_release_extras.sh` builds the companion
  archive from the `TacoTip_Extras/` subtree, where
  `TacoTip_Extras/.gitattributes` says what is not runtime, and checks the
  package holds the runtime `.lua` files the TOC lists, all 11 `Locale/*.lua`,
  the `tt-2.tga` the TOC's `## IconTexture` points at, the four documents, and
  nothing else. Neither script writes to the repository.

---

## License and credits

TacoTip is licensed under the **MIT License**. The full text ships in
[LICENSE](LICENSE).

Bundled libraries under `Libs/` keep their **own** licenses and are **not**
covered by TacoTip's MIT terms — MIT permission does not extend to them:

| Library | License | Author / credits | Bundled header |
| :--- | :--- | :--- | :--- |
| `LibStub` | Public Domain | Kaelten, Cladhaire, ckknight, Mikk, Ammo, Nevcairiel, joshborke | `Libs/LibStub/LibStub.lua` |
| `CallbackHandler-1.0` | UNKNOWN | UNKNOWN | `Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua` |
| `LibDetours-1.0` | UNKNOWN | kebabstorm | `Libs/LibDetours-1.0/LibDetours-1.0.lua` |
| `LibForeverInspector` | UNKNOWN | UNKNOWN | `Libs/LibForeverInspector/LibForeverInspector.lua` |

`UNKNOWN` means the bundled file itself states no licence and no author — it
is not a claim that the work is unlicensed, and it is not a claim that TacoTip
holds any right in it. Nothing here is asserted from memory or from an
upstream listing.

This table is reproduced from
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), which is the **single source
of truth** for every licence and author claim in this package: it records the
file and line each row was read from, and it explains what each `UNKNOWN`
entry would take to resolve.

GearScore scoring behavior derives from GearScoreTBCClassic. The retained
attribution, the original and fork copyright lines, and the full required MIT
notice are reproduced in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) — this package ships that
notice itself, so the attribution does not depend on a document it does not
contain.

Author and maintainer: **AcidBomb (Pilsung)**.
