---
description: Dual-spec talent inspection, caching, and layout formatting standards
globs: ["main.lua", "Libs/LibClassicInspector/*.lua"]
---

# Rule 04: Dual-Spec Talent Inspection & Formatting

- **Multi-Client Support:** Ensure dual-spec capability detection works across WotLK, TBC Classic Anniversary (`clientBuildMajor == 2`), and Season of Discovery (`clientBuildMajor == 1`).
- **Dynamic Event Handling:** Register `PLAYER_TALENT_UPDATE` and `ACTIVE_TALENT_GROUP_CHANGED` across all dual-spec clients so talent changes refresh tooltips dynamically.
- **Zero-Alpha Vertical Alignment:** When formatting secondary talent specs in compact/standard tooltip mode, use the localized invisible prefix `|c00000000%s: |r` matching `L["Talents"] .. ": "` so the secondary icon and spec name align directly under the primary icon.
- **Arithmetic Nil Guards:** Always guard `select(5, GetTalentInfo(...))` with `or 0` to prevent nil arithmetic errors on unallocated talent slots.


## Universal build inspection

- Apply the same inspection discipline to `TacoTip_Forever/Libs/LibForeverInspector/`: preserve per-client talent paths; do not read talents from inventory-only events.
- Defer background work while manual inspection is open. Never clear another listener's inspect data. Check interaction distance before background inspect APIs; do not globally suppress UI errors. Retain temporarily unavailable GUIDs with bounded deferral; test recovery, expiry and queue fairness with the real library.
