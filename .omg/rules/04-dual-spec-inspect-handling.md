---
description: Dual-spec talent inspection, caching, Forever trait resolution, and layout formatting standards
globs: ["main.lua", "Libs/LibForeverInspector/*.lua"]
---

# Rule 04: Dual-Spec Talent Inspection & Formatting

- **Classic vs Camelot Separation:**
  - Classic Era (`11509`), TBC Anniversary (`20506`), and Titanforge (`38002`) use `GetNumTalentTabs`/`GetTalentInfo`/`GetActiveTalentGroup` (with `C_SpecializationInfo.GetTalentInfo` struct fallback in `LibForeverInspector.lua`). Never cross classic `spec_table`/`talents_table` data into Forever.
  - WoW Forever (`16001`) uses its own `show_talents and isForever` branch via `C_Traits.HasValidInspectData()`, `Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID = -1`, `C_Traits.GetGroupDisplayInfoByTreeID`, `C_Traits.GetGroupCurrencyInfo`, and `C_SpecializationInfo.GetTalentInfo` for inactive spec groups when `GetNumSpecGroups() > 1`.
- **Dynamic Event Handling:** Register `PLAYER_TALENT_UPDATE` and `ACTIVE_TALENT_GROUP_CHANGED` on dual-spec clients so respecs and swaps refresh tooltips live.
- **Zero-Alpha Vertical Alignment:** Prepend localized invisible `|c00000000%s: |r` (`L["Talents"] .. ": "`) before secondary talent specs in compact/standard mode so icons align vertically beneath the primary spec.
- **Arithmetic Nil Guards:** Always guard `select(5, GetTalentInfo(...))` with `or 0`.
