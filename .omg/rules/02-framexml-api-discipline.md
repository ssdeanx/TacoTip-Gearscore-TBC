---
description: FrameXML research, WoW Classic/Forever API signature verification, and secrecy guard discipline
globs: ["*.lua", "Libs/**/*.lua"]
---

# Rule 02: FrameXML API & Forever Secrecy Discipline

- **Research First:** Always inspect `/home/sam/wow-ui-source` (`origin/` branches) before modifying client-specific API calls:
  - `origin/classic_era` (`11509`), `origin/classic_anniversary` (`20506`), `origin/classic_titan` (`38002`), `origin/forever` (`16001` Camelot, `WOW_PROJECT_CAMELOT = 18`), and `origin/live` (`120105`).
- **Strict Engine Isolation:** Never bleed Forever/Retail `C_Traits` or `TooltipDataProcessor` assumptions into Classic branches; gate Forever changes strictly on `isForever` / `CI:IsForever()`.
- **Secret Value Boundaries (Forever `16001`):**
  - Never pass a possibly-secret value to `SecretArguments = "AllowedWhenUntainted"` functions (`UnitExists`, `UnitIsPlayer`, `UnitIsConnected`, `UnitIsDeadOrGhost`, `UnitInParty`, `UnitGroupRolesAssigned`, `UnitIsSameServer`, `UnitDistanceSquared`, `UnitFactionGroup`). Route through `LibForeverInspector` / `TT.safe*` helpers.
  - Use `type(v) == "nil"` before comparisons (`==`/`~=`/`<`/`>`/`%`) and apply the strong `issecretvalue` check (`if (not ok or isSec == true)`).
  - Never index tooltip data tables without `TT.tooltipDataReadable(data)` (`canaccesstable`).
  - Leave Forever native loot-window tooltips (`SetLootItem` / `SetLootRollItem`) untouched, and skip World Map unit-pin styling whenever in combat, instance, encounter, or active Forever restrictions (`TT.CanStyleWorldMapTooltip()`).
