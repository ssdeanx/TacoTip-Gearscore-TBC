# Blizzard FrameXML Compatibility & Forever Secrecy Rules

## 1. FrameXML Source Mapping

All client API research references the read-only local mirror at `/home/sam/wow-ui-source` (`origin/`-qualified branches) and `wago.tools` for unmirrored DB2 tables:

| Client Family | Interface | Branch in `/home/sam/wow-ui-source` | Notes |
| :--- | :--- | :--- | :--- |
| **Classic Era / SoD** | `11509` | `origin/classic_era` | Classic talent globals (`Blizzard_DeprecatedSpecialization`), `CheckInteractDistance` + `CanInspect` |
| **TBC Anniversary** | `20506` | `origin/classic_anniversary` | `C_SpecializationInfo.GetTalentInfo` query struct, backdrop mixins |
| **WotLK Titanforge** | `38002` | `origin/classic_titan` | Classic talent API + Wrath trees, `wowlua-ls` has no Titanforge flavor |
| **WoW Forever (Camelot)** | `16001` | `origin/forever` | `WOW_PROJECT_CAMELOT = 18` (**not** `MAINLINE`), `Camelot` UI, secrecy engine |
| **Retail** | `120105` | `origin/live` | Modern TooltipDataProcessor, Dragonflight/TWW traits, Achievement row |

---

## 2. WoW Forever (`16001` / Camelot) Identity & APIs

- **Project Identity:** `Blizzard_ProjectConstants/Camelot/ProjectConstants.lua` defines `WOW_PROJECT_CAMELOT = 18; WOW_PROJECT_ID = WOW_PROJECT_CAMELOT;`. `LibForeverInspector` checks `WOW_PROJECT_CAMELOT` first and keeps the `16000–19999` interface band as fallback.
- **Talents (`Camelot`):** Forever specializations are class-level; trees are `C_Traits` node groups (`INSPECT_TRAIT_CONFIG_ID = -1`, gated by `C_Traits.HasValidInspectData()`). Never feed classic `spec_table`/`talents_table` data into Forever paths; gate all Forever changes on `isForever` / `CI:IsForever()`.
- **Zone Row:** Uses `C_Map.GetBestMapForUnit(unit)` (works for `player`/`target`/`party`/`raid` only) + `C_Map.GetMapInfo(mapID).name` and client `ZONE` label; excludes nameplates, focus, pets, and target-of-target.
- **Native Loot Tooltip Passthrough:** `GameTooltip:SetLootItem` / `SetLootRollItem` uses secure delegates (`LootFrame.lua` rebuilds on `OnUpdate` with secret line data). TacoTip must not add rows, restyle, or re-font loot tooltips on Forever.

---

## 3. Forever Secret Values — Boundary Rules

- **`SecretArguments = "AllowedWhenUntainted"`:** Addon code is always tainted, so passing a secret token to `UnitExists`, `UnitIsPlayer`, `UnitIsConnected`, `UnitIsDeadOrGhost`, `UnitInParty`, `UnitGroupRolesAssigned`, `UnitIsSameServer`, `UnitDistanceSquared`, `UnitFactionGroup`, etc. raises immediately. Route every `Unit*` call through `LibForeverInspector` / `TT` `safe*` helpers (`safeUnitExists`, `safeUnitGUID`, `safeUnitIsUnit`, etc.).
- **Nil & Secrecy Checks:** `type(v)` never throws on secrets and returns the underlying Lua type, so nil checks use `type(v) == "nil"` **before** comparisons (`==`/`~=`/`<`/`>` or arithmetic `%`). Strong secret guard: `local ok, isSec = pcall(issecretvalue, v); if (not ok or isSec == true) then return true end`.
- **Table Access Guard (`canaccesstable`):** Never index tooltip data tables (`data.lines`, `data.guid`, `data.type`) without first checking `TT.tooltipDataReadable(data)` (`pcall(canaccesstable, data)` returning `true`).
- **StatusBar Sink (`UnitPowerMax`/`UnitPower`):** Test `type(v) ~= "nil"` before passing values directly to `SetMinMaxValues`/`SetValue`, or check secrecy before comparing/formatting.
- **Restricted Contexts & World Map Pins:** Do not hook/mutate World Map pin tooltip formatting during combat lockdown, instances, encounters, or active `C_RestrictedActions.IsAddOnRestrictionActive` (`Combat`, `Encounter`, `ChallengeMode`, `PvPMatch`, `Map`) — gated by `TT.CanStyleWorldMapTooltip`. Never register `COMBAT_LOG_EVENT_UNFILTERED` on Forever.
- **Testing Restrictions Locally:** Force restriction CVars in-game (non-persistent): `addonCombatRestrictionsForced`, `addonEncounterRestrictionsForced`, `addonMapRestrictionsForced`.

---

## 4. Inspect-Range Policy by Family

- **Classic Era / TBC Anniversary / Titanforge:** Unconditionally require `CanInspect(unit)` **AND** `CheckInteractDistance(unit, 1)` (distance-first ordering + `NEARBY_ASK_YARDS` 20/40 + `pcall(NotifyInspect)` learned ceiling). Never bypass failed distance checks with a cache grace window.
- **WoW Forever / Retail:** Keep the `CanInspect(unit)` **OR** `CheckInteractDistance(unit, 1)` either-signal rule.
- Always call `CanInspect(unit)` with **one argument** (omitting `showError`).
- `xpcall` supports extra args in WoW Lua (shimmed in offline `Tests/harness/` for stock Lua 5.1).
