# Dual-Spec & Talent Inspection

## 1. Multi-Client Specialization Engines

`Libs/LibForeverInspector/LibForeverInspector.lua` isolates two completely separate talent APIs:

1. **Classic Family (`classic_era` 11509, `classic_anniversary` 20506, `classic_titan` 38002):**
   - Uses `GetNumTalentTabs`, `GetTalentTabInfo`, `GetTalentInfo`, and `GetActiveTalentGroup` (with `C_SpecializationInfo.GetTalentInfo` query-struct fallback where globals are deprecated).
   - `hasDualSpec` detects TBC/WotLK/SoD dual-spec capability; registers `PLAYER_TALENT_UPDATE` and `ACTIVE_TALENT_GROUP_CHANGED`.
   - Arithmetic on `select(5, GetTalentInfo(...))` must guard `or 0`.

2. **WoW Forever (`16001` / Camelot) & Retail (`120105`):**
   - Classic talent tables (`spec_table` / `talents_table`) do not apply to Camelot.
   - Forever (`isForever` / `CI:IsForever()`) uses a separate branch in `main.lua` leaving the existing Classic/Retail `show_talents and not isForever` block unchanged:
     - Active config (`Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID = -1`, gated on `C_Traits.HasValidInspectData()`) resolves tree IDs via `C_Traits.GetGroupDisplayInfoByTreeID(treeID)` and points via `C_Traits.GetGroupCurrencyInfo(configID, groupIDs)`.
     - Inactive spec group (when `GetNumSpecGroups() > 1`) is queried via `C_SpecializationInfo.GetTalentInfo` (`isInspect = true`, `target = unit`, `groupIndex`) and drawn only if the client responds.

---

## 2. Rendering & Alignment Rules (`main.lua`)

- **Active vs Secondary Spec:** Active spec displays class-colored name with white `[points]`; secondary (inactive) spec displays grey (`0.50, 0.50, 0.50`) with white `[points]`, rendered only when distinct (`spec2 ~= nil and spec2 ~= spec1`).
- **Zero-Alpha Prefix Alignment:** Secondary talent lines in Compact/Standard layout prepend an invisible localized label (`|c00000000<L["Talents"]>: |r`) so secondary icons align horizontally beneath the primary icon across all fonts and locales.
