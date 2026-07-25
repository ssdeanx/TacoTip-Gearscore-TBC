---
name: wow-unit-tester
description: Best practices for writing robust, zero-warning WoWUnit tests for TacoTip, including how to mock Blizzard globals securely and assert UI states.
---

# WoW Unit Tester Skill

Use this skill when you need to write or modify tests in `TacoTip_Tests.lua` using the `WoWUnit` framework.

## Instructions

1. **Avoid Static Analysis Warnings:**
   - **Never** use `-- luacheck: ignore` for field mutations on globals.
   - If you need to mock a global object's method (e.g., `GameTooltip.GetUnit`), use dynamic table access:
     ```lua
     local originalGetUnit = GameTooltip.GetUnit
     GameTooltip["GetUnit"] = function() return "TestPlayer", "mouseover" end
     ```
   - Always restore the original method in the teardown phase of your test to prevent global state pollution.

2. **Mocking Functions with WoWUnit:**
   - If mocking a top-level global function (e.g., `GetGuildInfo`), use `WoWUnit.Replace`:
     ```lua
     Replace("GetGuildInfo", function(unit)
         if (unit == "player") then return "TestGuild", "Rank 5", 5 end
         return nil
     end)
     ```
   - Always call `ClearReplaces()` at the end of the test.

3. **Safe Execution (pcall):**
   - Because you are testing against mock UI states, runtime errors can halt the test suite. Use the local `pc` (pcall) wrapper when invoking core UI methods that might fail if the mock environment is incomplete:
     ```lua
     local ok = pc(GameTooltip.SetUnit, GameTooltip, "player")
     IsTrue(ok, "SetUnit(player) did not error")
     ```

4. **Asserting UI States:**
   - Wait for or trigger the appropriate hooks. If testing Tooltips, you often need to manually invoke the hook script if it isn't automatically triggered in the headless environment:
     ```lua
     local script = GameTooltip:GetScript("OnTooltipSetUnit")
     local ok = pc(script, GameTooltip)
     ```
   - Inspect the global text lines (e.g., `_G.GameTooltipTextLeft2`) to verify the rendered output.
