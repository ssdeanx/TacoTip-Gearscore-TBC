# Main-Tip Blizzard API Opportunities — 2026-10-18

**Desk:** stage6-api-scan · **run_id:** stage6-api-scan-20261018-a
**Scope:** MAIN addon only — `main.lua`, `options.lua`, `gearscore.lua`, `pawn.lua`,
`textures.lua`, `Libs/LibForeverInspector/` (TacoTip_Extras explicitly out of scope).
**Method:** read-only. Current surface mapped by grepping every `C_*/Unit*/Item*/Tooltip*/Settings`
call in the addon; each candidate checked against the UI mirror at
`/home/sam/wow-ui-source` on all five branches (`origin/live`, `origin/forever`,
`origin/classic_era`, `origin/classic_anniversary`, `origin/classic_titan`) with
branch-qualified `file:line` evidence. A `gh_grep.searchGitHub` corroboration pass was
used only for adoption-pattern sanity (results advisory, not cited as evidence).
**CAIRN legend:** VERIFIED = re-grepped file:line in this session ·
ASSUMED = reasonable inference, flagged · UNKNOWN = could not verify, pitched nothing on it.

## 1. Current API surface (per file)

**`main.lua`** (4039 lines) — C-namespaces used: `C_AddOns.GetAddOnMetadata` (:3),
`C_Timer.{NewTicker,NewTimer,After}` (:146-148, all ` _G`-gated), `C_Map.GetBestMapForUnit`
(:149), `C_Item.{GetItemLinkByGUID, IsEquippableItem, GetItemInfo, RequestLoadItemDataByID}`
(:154, :2504, :2532, :2546, :2622 — every one nil-guarded + `pcall`), `Item.CreateFromItemLink`
+ `ItemMixin:{IsItemDataCached, ContinueWithCancelOnItemLoad, ContinueOnItemLoad}` (:2606-2661).
Tooltip: `TooltipDataProcessor.AddTooltipPostCall` for `Enum.TooltipDataType.Unit` (:2479)
and `.Item` (:2667) behind a `dataPipelineActive()` mixin gate (:2412, :2666 — required
because TBC/Titanforge define the global without a firing pipeline, :2398-2403);
`TooltipUtil.{GetDisplayedUnit, GetDisplayedItem}` guarded `pcall` (:988, :2494);
legacy `OnTooltipSetUnit`/`OnTooltipSetItem` script hooks as fallback (:2487, :2671);
`hooksecurefunc("GameTooltip_SetDefaultAnchor")` guarded (:2937). Units:
`UnitClass/UnitIsPlayer/UnitLevel/UnitRace/UnitGUID/UnitName/UnitIsUnit/UnitGroupRolesAssigned/UnitPVPName/UnitFactionGroup/UnitPower*`
plus `GetGuildInfo`, `GetQuestDifficultyColor` (deliberately uncached, :222-226),
`UnitIsSameServer` guarded (:1943). Events registered: `UPDATE_MOUSEOVER_UNIT`,
`PLAYER_EQUIPMENT_CHANGED`, `MODIFIER_STATE_CHANGED`, `UNIT_TARGET`, `ADDON_LOADED`
(:3675, :3766-3769); power-bar sub-frame adds `UNIT_POWER_UPDATE/UNIT_MAXPOWER/UNIT_DISPLAYPOWER`
(:2349-2351). Frames: `PaperDollFrame`/`CharacterModelFrame` host (:3034),
`InspectPaperDollFrame/InspectModelFrame/InspectFrame` overlay (:3189-3232).
Commented-out (not used): `C_PaperDollInfo.GetInspectGuildInfo` (:3162).

**`Libs/LibForeverInspector/LibForeverInspector.lua`** (5447 lines) — inspect engine.
Uses: `C_PlayerInfo.GUIDIsPlayer` (:3030), full `C_SpecializationInfo` suite
(`GetTalentInfo` :3074, `GetActiveSpecGroup` :3148, `GetSpecializationInfo` :3179,
`GetSpecialization` :3200, `GetInspectSpecialization` :3230/3664/5285/5304, plus
`GetClassIDFromSpecID`, `GetNumSpecializationsForClassID` :3244-3251 — all gated, with
`specializationInspect` capability flag at :228), `Item.CreateFromItemLink` (:3531,
capability flag :227), `GetInventoryItemLink("player", slot)` (:3632, :5202),
`C_Timer.After` (:3551, :3790, :4584), `NotifyInspect` via `requestNotifyInspect`
(:4353, guarded by `CanInspect`+`CheckInteractDistance` probe chain :3872-3996, :4281-4329).
Events: `INSPECT_READY`, `PLAYER_TARGET_CHANGED`, `UPDATE_MOUSEOVER_UNIT`,
`GROUP_ROSTER_UPDATE`, `UNIT_INVENTORY_CHANGED` (:3830-3834).
Deliberately NOT used: `CanInspect(unit, true)` two-arg form (:4389-4405 — documented as
harmful), bare-global `RequestLoadItemDataByID` (:4114-4117 — does not exist).

**`gearscore.lua`** — `C_PlayerInfo.GUIDIsPlayer` w/ fallback (:100),
`C_Item.RequestLoadItemDataByID` raw (:101), `C_Item.GetItemInfo or GetItemInfo` (:119-121).
**`pawn.lua`** — same GUID pattern (:28), `C_Item.RequestLoadItemDataByID` (:29); rest is
Pawn-third-party API (`PawnGetItemData`, `PawnCommon.Scales`), not Blizzard surface.
**`options.lua`** — `C_AddOns.GetAddOnMetadata` (:3-5); Settings dual-path:
`Settings.{RegisterCanvasLayoutCategory, RegisterAddOnCategory, RegisterCanvasLayoutSubcategory, OpenToCategory}`
gated (:511-541, :627-635) with `InterfaceOptions_AddCategory` legacy fallback (:551-589,
:638-642); CVars read directly: `UberTooltips`, `chatClassColorOverride` (:1882-1908);
color picker dual-pathed `SetupColorPickerAndShow` vs classic `swatchFunc` (:1550-1594).
**`textures.lua`** — no Blizzard API calls (static texture table; minimap entry at :212-213
is a texture path, not a button).

## 2. Ranked opportunities (impact × safety)

### O1 — `C_Item.IsItemDataCachedByID(itemID)` before building the ItemMixin object · OPTIMIZATION · risk: safe
Replaces: `Item.CreateFromItemLink` + `pcall(item.IsItemDataCached)` per hover
(`main.lua:2606-2630`; same shape in `LibForeverInspector.lua:3531-3532`).
Evidence VERIFIED all-five: documented in `Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua`
— live:1483, forever:1520, era:909, anniversary:909, titan:909; called with a bare itemID by Blizzard's own code on live
(`Blizzard_ArtifactUI/Blizzard_ArtifactPerks.lua:355`) and era
(`Blizzard_ObjectAPI/Classic/Item.lua:218`). Takes `ItemInfo` (itemID form proven by
the ArtifactPerks call site); returns `bool`.
Fallback: keep the existing ItemMixin path when `C_Item.IsItemDataCachedByID` is nil —
one `and`-gate, zero behavior change. Saves one mixin allocation + two pcall round-trips
on the hot hover path; output identical.
Adoption-safe: 112k users, pure short-circuit; failure mode is "falls through to today's code".

### O2 — `C_Item.GetDetailedItemLevelInfo(itemLink)` for the item-ilvl line · ROBUSTNESS · risk: safe
Replaces/augments: `itemInfo[4]` from `GetItemInfo` (`main.lua:2551-2555`) with the
upgrade-aware actual level (first return `actualItemLevel`; signature verified at
`ItemDocumentation.lua` live + era `GetDetailedItemLevelInfo` blocks).
Evidence VERIFIED all-five: documented on every branch (live:332, era:197,
anniversary:197, titan:197, forever:354); Blizzard call sites pass a bare itemLink on
live (`Blizzard_TutorialServices:263,314,328`, `Blizzard_WeeklyRewards.lua:645,648`) and
era (`Blizzard_ObjectAPI/Classic/Item.lua:174`). `MayReturnNothing` is declared, so the
call must be `or`-chained back to `itemInfo[4]`.
Fallback: `local ilvl = C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(link) or itemInfo[4]`.
Same line, fewer wrong numbers on titanforged/upgraded items. No new capability, no new events.

### O3 — Listen `GET_ITEM_INFO_RECEIVED` for the no-object fallback path · ROBUSTNESS · risk: contained
Fixes: `scheduleItemTooltipRefresh` no-object arm (`main.lua:2611-2624`) fires
`RequestLoadItemDataByID` and leaves repaint to "the caller's next natural refresh" —
a blank ilvl/GS line until the user re-hovers.
Evidence VERIFIED all-five: event documented in `ItemDocumentation.lua` on every branch
(live, forever, era, anniversary, titan each carry `LiteralName = "GET_ITEM_INFO_RECEIVED"`).
Fallback: if the event ever stops firing, behavior equals today (no regression — the
current path is already "hope for a refresh").
Contained (not safe): handler must match `itemID` payload to `state.currentItemLink`
and respect the existing `generation` guard (`main.lua:2632-2644` pattern) or a late
event repaints the wrong tooltip. Reuse the cancelable-handle discipline already in place.

### O4 — `UnitTokenFromGUID(guid)` as primary unit resolver · ROBUSTNESS · risk: safe
Replaces: the six-token hand chain (`player/mouseover/target/pet/focus/owner.unit`,
`main.lua:961-980`), which returns nil for party/raid/arena/boss/nameplate guids.
Evidence VERIFIED all-five: engine global consumed by Blizzard's own
`Blizzard_SharedXMLGame/Tooltip/TooltipUtil.lua:38` (`local unit = guid and
UnitTokenFromGUID(guid)`) identically on live:34ff, forever, era, anniversary, titan
(each branch: 2 referencing files). It is also exactly what `TooltipUtil.GetDisplayedUnit`
— already trusted behind `pcall` at `main.lua:988-990` — uses internally.
Fallback: `pcall(UnitTokenFromGUID...)` → nil → existing manual chain, untouched.
Strictly more resolutions, zero removed behavior.

### O5 — `TooltipDataProcessor.AddTooltipPreCall` / `AddLine{Pre,Post}Call` · ENHANCEMENT · risk: contained
Enables: targeted line surgery (e.g. recolor/annotate a single Blizzard line by
`lineType`) instead of the current full `text[]` rescrape, and pre-positioning work
before Blizzard fills lines.
Evidence VERIFIED all-five: defined in `Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua:195,203,207`
on live, era, titan, anniversary (:195/:207), forever (:195/:207).
Contained (not safe): same TBC/Titanforge dead-pipeline hazard documented at
`main.lua:2398-2403` — MUST reuse the `dataPipelineActive()` mixin gate, and line-type
enums need per-branch confirmation before use (line-type coverage NOT verified here).
Fallback: today's PostCall + script-hook dual registration stays primary.

### O6 — `C_PaperDollInfo.GetInspectGuildInfo(unit)` for the inspect overlay · ENHANCEMENT · risk: contained
Enables: achievement-points / member-count / realm lines on the inspect frame
(`main.lua:3189-3232` overlay currently shows GS + avg ilvl only). The exact call is
already sketched in a comment at `main.lua:3162`.
Evidence VERIFIED all-five: `Name = "GetInspectGuildInfo"` in
`PaperDollInfoDocumentation.lua` on live, era, anniversary, forever, titan (1 hit each).
Contained: returns inspect-cache data — nil until `INSPECT_READY` for that unit; line
must be conditional on non-nil returns (lib already tracks inspect readiness).
Fallback: omit the line (today's overlay). No change to the mouseover guild line, which
correctly stays on the `GetGuildInfo` global (`main.lua:1853-1854` — the PaperDoll
variant carries no rank name and needs inspect data, so it is NOT a replacement there).

### O7 — Declarative settings (`Settings.RegisterAddOnSetting` + `CreateCheckbox/Slider` initializers) · ENHANCEMENT · risk: contained
Enables: native Settings search integration and less bespoke widget code in
`options.lua` (37 `C_/Settings` references today, all imperative `CreateFrame` panels).
Evidence: `RegisterAddOnSetting`, `RegisterProxySetting`, `CreateCheckbox/Slider(+Initializer)`
VERIFIED in `Blizzard_Settings_Shared/Blizzard_Settings.lua` on live AND era
(`RegisterProxySetting` at era `Blizzard_Settings_Shared/Blizzard_Settings.lua:177`;
`RegisterAddOnSetting` count 1× in the Shared file on anniversary, forever, titan).
ASSUMED (host risk): era/anniversary/titan ship only the `Blizzard_SettingsDefinitions_*`
+ `Shared` dirs (no top-level `Blizzard_Settings` panel addon, unlike live/forever) —
whether the canvas host loads on those clients needs one in-game
`/dump Settings.RegisterAddOnCategory` per classic client before migrating.
Fallback: keep the imperative panels + legacy `InterfaceOptions_AddCategory` path
(`options.lua:551-589`) behind the existing capability gate. Large rewrite — propose as
phased (new settings via declarative, old panels untouched until proven).

### O8 — `AddonCompartmentFrame:RegisterAddon` entry · ENHANCEMENT · risk: safe
Enables: one-click settings access from the minimap compartment (addon currently has NO
minimap presence at all — `textures.lua:212-213` is a texture path; `TacoTipDragButton`
is a screen anchor, `main.lua:3779-3796`).
Evidence VERIFIED family-gated: `Interface/AddOns/Blizzard_Minimap/Mainline/AddonCompartment.xml`
exists on live and forever; zero `AddonCompartmentFrame` files on era/anniversary/titan.
Fallback: slash command + Interface Options entry already exist — compartment is purely
additive behind `if AddonCompartmentFrame then`. Safe, retail/forever-only value.

### O9 — `C_Item.GetItemStats / GetItemStatDelta` (stat-breakdown lines) · ENHANCEMENT · risk: contained
Enables: optional per-stat tooltip lines without parsing links by hand.
Evidence VERIFIED live-only: documented in live `ItemDocumentation.lua`, ABSENT from era
docs (see §4 delta) — classic-family presence UNKNOWN, so family-gate required.
Contained: stat tables are locale/format-sensitive; value is also questionable because
neither GearScore nor the ilvl line consumes stats. Ranked last among enhancements —
only worth it with a concrete user-facing line spec.

### O10 — `C_SpecializationInfo.GetSpecIDs / GetClassIDFromSpecID` (thin the CLASS_IDS/spec tables) · OPTIMIZATION · risk: contained
Replaces: hand-maintained `CLASS_IDS` + `spec_table_localized` in the lib
(`LibForeverInspector.lua:5320-5332` already prefers global
`GetSpecializationInfoForClassID` when present).
Evidence VERIFIED live-only: `SpecializationInfoDocumentation.lua` carries `GetSpecIDs`,
`GetClassIDFromSpecID`, `GetInspectSelectedPvpTalent` on live; era docs carry only the
8-function subset (no `GetInspectSpecialization`, no `GetClassIDFromSpecID` — era's own
`Blizzard_InspectUI/Mists/InspectTalentFrame.lua:161` instead calls a bare GLOBAL
`GetInspectSpecialization(INSPECTED_UNIT)`).
Contained: spec-index semantics differ per family (classic talent trees vs spec IDs);
any adoption needs the lib's existing per-family capability flags, not a blind swap.

## 3. Rejected / unverifiable (do NOT pitch)

- **R1 — Any `C_Inspect.*` replacement for `NotifyInspect`.** VERIFIED ABSENT: `C_Inspect`
  has 0 hits on all five branches. `CanInspect` + `NotifyInspect` + `CheckInteractDistance`
  probe chain stays. No alternative exists.
- **R2 — `C_Item.GetItemLinkByGUID` on classic: CONFLICTING evidence → UNKNOWN.**
  Era `ItemDocumentation.lua` does NOT document it, yet era's own
  `Blizzard_SharedXMLGame/Tooltip/TooltipUtil.lua:14` calls
  `C_Item.GetItemLinkByGUID(tooltipData.guid)`. Either callable-but-undocumented or dead
  code on era. Settles with one in-game check: `/dump C_Item.GetItemLinkByGUID` on an
  era client. Until then the addon's skip-on-classic stance (`main.lua:2502-2507`,
  already `C_Item and C_Item.GetItemLinkByGUID`-gated + `pcall`) is correct and unchanged.
- **R3 — "Rely on TooltipUtil everywhere."** VERIFIED unsafe: every branch's
  `Blizzard_SharedXMLGame.toc:8` loads `Tooltip\TooltipUtil.lua` as
  `[AllowLoadGameType mainline]` only, and `TooltipDataHandler.lua` is
  `[ExcludeLoadGameType vanilla]` on live/era/anniversary/titan (no tag only on forever).
  The addon's guarded `TooltipUtil and …` + legacy-hook fallback is the correct shape;
  no change proposed.
- **R4 — Mythic+ rating line (`C_PlayerInfo.GetPlayerMythicPlusRatingSummary`).**
  Documented live-only, takes `playerToken` (self only) — cannot enrich OTHER players'
  tooltips, which is the addon's whole job. Weak value, scope creep. Rejected.
- **R5 — Aura / combat-log enrichment (`C_UnitAuras.*`, `C_CombatLog`, `UNIT_AURA`).**
  APIs exist on all branches (`UnitAuraDocumentation.lua`: `GetAuraDataByIndex`,
  `GetAuraDataByAuraInstanceID` on live AND era; `UnitAura` compat shim kept at
  live `Blizzard_Deprecated/Classic/Deprecated_1_15_8.lua:10`), but no user-facing line
  in this tooltip addon needs aura data. Rejected as scope without a spec.
- **R6 — `C_PaperDollInfo.GetMinItemLevel` as avg-ilvl source.** Wrong API: no-arg
  transmog-collection minimum (era `PaperDollInfoDocumentation.lua` block), not a unit's
  equipped average. Rejected.
- **R7 — `C_Item.GetItemLocation` / ItemLocation mixins.** Live-docs-only
  (absent era docs); addon works from itemLINKS, never bag slots — no call site would
  consume it. Rejected.
- **R8 — `C_Timer` refinements.** None found: `C_Timer` is engine-provided (no Lua
  declaration anywhere in the mirror); the addon already gates and uses
  After/NewTimer/NewTicker. No-op.
- **R9 — NAME_PLATE_UNIT_ADDED vs enumeration + any other OPEN-ITEMS deferred item.**
  UNVERIFIABLE: `bench/OPEN-ITEMS.md` does not exist (repo-wide `*OPEN*` search:
  no hits outside `.git`; `bench/` contains only `audits/` + `README.md`). Separately,
  neither `main.lua` nor `TacoTip_Extras/*.lua` contains ANY `NAME_PLATE`,
  `C_NamePlate`, or `EnumerateFrames` reference — there is no in-scope code this item
  could attach to. Settles when the owning desk re-files OPEN-ITEMS (or confirms the
  nameplate workstream lives elsewhere).
- **Already-handled (no proposal):** `C_AddOns` (used, docs identical live/era),
  `C_Map.GetBestMapForUnit` (used; no superior alternative found),
  `C_PlayerInfo.GUIDIsPlayer` (used w/ fallback), `C_SpecializationInfo` core suite
  (used, fully gated), `ItemMixin` Continue APIs (used; `ContinueOnItemLoad` +
  `ContinueWithCancelOnItemLoad` VERIFIED in `Blizzard_ObjectAPI/Mainline/Item.lua:330,336`
  and `Classic/Item.lua:233,242`), color picker dual path, `GetCVar(UberTooltips/
  chatClassColorOverride)` reads (no `GetCVarBool` migration needed — same cost),
  `GetTotalAchievementPoints` global (no namespaced equivalent in
  `AchievementInfoDocumentation.lua` on live or era — Blizzard's own AchievementUI calls
  the same global).

## 4. C_Item doc delta (live vs era, for the record)

Live-doc-only (family-gate anything built on these): `GetItemIDByGUID`,
`GetItemLinkByGUID`, `GetItemLocation`, `GetItemStats`, `GetItemStatDelta`,
`GetItemCooldown`, `GetItemUpgradeInfo`, `IsItemGUIDInInventory`,
`IsItemSpecificToPlayerClass`, `IsDressableItemByID`, transmog/track-jump/match APIs,
`ITEM_CHANGED`-family events. Era-doc-only: nothing of note (`IsDressableItem` alias).
Full sorted diff was produced from `ItemDocumentation.lua` on both branches this session.

## 5. Validation

No code to run (read-only task). Every branch-qualified citation above was re-grepped
via `git grep`/`git show <branch>:<path>` immediately before writing; line numbers are
mirror-current. In-game checks still required before ANY adoption: R2's one-liner on era,
O7's `/dump Settings.RegisterAddOnCategory` on era/anniversary/titan, and the standard
five-client hover/inspect pass (per project memory: 42/42 harness green is not a
substitute for client testing). No production files touched; this report is the only
artifact plus the desk journal/signals.
