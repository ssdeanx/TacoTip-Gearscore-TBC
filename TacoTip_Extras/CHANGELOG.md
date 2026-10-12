# Changelog — TacoTip Extras

All notable changes to TacoTip Extras are documented in this file.

| Version | Date | Summary |
| :--- | :--- | :--- |
| `1.0.1` | `2026-10-12` | Fix remote inspect equipment scanning deadlock on Retail and WoW Forever: accepted omitted `isInspect` in `Scanner.HandleInventoryReady`, added `_G.InspectFrame.unit` fallback matching in `resolveRemoteUnit`, and extracted numeric item IDs from native links when `GetInventoryItemID` returns nil on remote items. |
| `1.0.0` | `2026-10-11` | Initial release of TacoTip Extras companion addon. Full equipment and enhancement auditing, modern retail engine compatibility (variable-length bonus ID item links, 16-slot average item level, CharacterModelScene support), Detailed display mode default, and 100% zero-warning static analysis. |

---

## [1.0.1] — 2026-10-12

> Maintenance and bugfix update resolving remote inspection deadlocks when inspecting other players
> across Retail and WoW Forever.

### Fixed

- **Remote Inspection "Scanning Equipment..." Deadlock:**
  Resolved issue where right-clicking and inspecting another player left the inspect frame permanently showing `"Scanning equipment..."`.
  - Relaxed the guard in `Scanner.HandleInventoryReady` to `(isInspect ~= nil and isInspect ~= true)` so callbacks with omitted `isInspect` parameters (e.g. from `LibForeverInspector`) are processed instead of dropped.
  - Added `_G.InspectFrame.unit` resolution in `resolveRemoteUnit` so players inspected from chat, guild roster, or friends list (who are not currently targeted or under mouseover) cleanly resolve their unit token.
  - In `Scanner.captureSlot`, added fallback item ID extraction from the native item link (`"item:(%d+)"`) when `GetInventoryItemID` returns `nil` on remote units, preventing false contradiction errors during remote scans.
- **Offline Test Matrix:**
  Added comprehensive test cases in `Tests/harness/load_test.lua` asserting omitted `isInspect`, explicit `isInspect = true`, `InspectFrame.unit` fallback resolution, rejection of `isInspect = false`, and cache completion across all supported client profiles.

---

## [1.0.0] — 2026-10-11

> Initial standalone release of TacoTip Extras, providing non-invasive equipment audit and enhancement
> display directly integrated with TacoTip and LibForeverInspector.

### Added

- **Detailed Equipment Summaries:**
  Inspect and Character frame displays showing per-slot item level, gem sockets, enchantments, and missing enhancement alerts.
- **Universal Multi-Client Architecture:**
  Full support for Classic Era / SoD (`11509`), TBC Anniversary (`20506`), WotLK Titanforge (`38002`), WoW Forever (`16001`), and Retail (`120100`).
- **Retail & Forever Modern Hardening:**
  Modern unit resolution with `TooltipUtil.GetDisplayedUnit` and `TooltipDataProcessor.AddTooltipPostCall`, modern paperdoll layout support (`CharacterModelScene`), variable-length bonus ID item link parsing, and retail 16-slot average item level divisor.
- **Detailed Mode Default:**
  Fresh installations and unconfigured profiles default to **Detailed** mode for both player tooltips and equipment displays.
- **Quality Gates:**
  100% zero-warning compliance across all 11 files under `luacheck`.
