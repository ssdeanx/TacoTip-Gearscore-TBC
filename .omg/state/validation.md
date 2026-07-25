# Validation Plan & Commands (v0.6.2)

This document lists the static analysis, in-game test runner commands, and manual verification procedures for validating **TacoTip-Gearscore-TBC**.

## Static Analysis / Linting Gate

The project uses `luacheck` to enforce code quality. To run static analysis:

```bash
luacheck .
```

### Constraints:
- Core runtime files (`main.lua`, `options.lua`, `gearscore.lua`, `pawn.lua`, `textures.lua`, and `Libs/LibClassicInspector/LibClassicInspector.lua`) **must pass with zero warnings**.
- Test suite file (`TacoTip_Tests.lua`) contains mock setup and accesses global WoWUnit APIs; some warnings are allowed here (e.g. mutating read-only fields for mock purposes, referencing undefined global `WoWUnit`). Do not bypass using broad `-- luacheck: ignore` comments in runtime files.

## Automated / Semi-Automated Testing

### 1. In-game Test Runner
The addon includes a test suite in [TacoTip_Tests.lua](file:///home/sam/TacoTip-Gearscore-TBC/TacoTip_Tests.lua) built for `WoWUnit`.
- **Command to run in-game:** `/tttest` (or `/tacotest` alias)
- **What it checks:**
  - Core namespace structure (`TT` and its public API).
  - Config defaults, initialization, and sanitization.
  - Tooltip border and background color application logic.
  - Talents string parsing and specialization lookup.
  - Item level calculations and bracket mappings.
  - **Guild Parsing Fallback (New in v0.6.2):** Validates fallback parsing of bracketed guild names (e.g., `<Guild Name>`) when `GetGuildInfo` returns `nil` for other players on patch 1.15.8 (Classic Era/SoD) clients. Also verifies that disabling the guild display setting removes the line cleanly without leaving empty `<>` brackets.

## Manual Verification Checklist

Whenever changes are made to tooltips or configurations:

1. **Option Panel Controls:**
   - Command: `/tacotip` or escape menu → Options → AddOns → TacoTip Gearscore TBC.
   - Verify category page opening works without breaking layout.
   - Verify changing settings (e.g., toggling power bars or borders) updates both the settings preview and the live tooltip reactively.

2. **Tooltip Layouts & Visuals:**
   - Hover player units: Verify class border (if enabled), specialization name + icon, guild rank, GearScore, and average item level render correctly.
   - Hover NPC units: Verify levels are correctly difficulty-colored using `GetQuestDifficultyColor(level)`.
   - Hover items: Verify GearScore, item level, and Pawn values (if Pawn is loaded) appear.

3. **Anchoring & Mover Handle:**
   - Unlock anchoring in settings, drag the green mover handle, and confirm tooltips anchor properly to the selected anchor points.
   - Click "Reset Position" in options and verify the mover handle and saved position reset to the selected corner's default.

4. **Multi-Client Check:**
   - Test compatibility against Classic Era/SoD on patch `1.15.8` (two different versions on the same client engine), TBC Anniversary on `2.5.5` / `2.5.6` (`20505`), and Wrath Classic/Titanforge (`38001`) clients.
