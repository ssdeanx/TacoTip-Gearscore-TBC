---
name: retail-compatibility
description: Architectural guidelines for supporting Live/Retail features in TacoTip while maintaining strict backward compatibility with the Classic family.
---

# Retail Compatibility Skill

Use this skill when developing features intended for Live (Retail) servers or when trying to merge cross-client compatibility into TacoTip.

## Instructions

1. **Strict Version Isolation:**
   - Retail APIs often differ significantly from Classic APIs (e.g., Tooltip APIs changed drastically in Dragonflight/The War Within).
   - Use the global constant `WOW_PROJECT_ID` to isolate execution paths.
   - Example:
     ```lua
     if WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then
         -- Retail specific logic (e.g., TooltipDataProcessor)
     else
         -- Classic Era, SoD, TBC Anniversary, Wrath logic (e.g., OnTooltipSetUnit)
     end
     ```

2. **Graceful Fallbacks:**
   - Do not assume that a function available in Retail exists in Classic. Always test for existence before calling if operating outside of a strict `WOW_PROJECT_ID` block.
   - Example:
     ```lua
     if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
         -- Modern modern tooltip parsing
     end
     ```

3. **Global Namespace Protection:**
   - If a Retail feature requires introducing a new file or subsystem, integrate it cleanly into the existing `TT` global object. Do not create new top-level globals for Retail-only data structures.

4. **Testing Retail Logic:**
   - Ensure you specify which client context a `WoWUnit` test is intended for. Mock `WOW_PROJECT_ID` if necessary within the test tear-up to validate the branching logic, and always restore it in the tear-down.
