---
name: wow-unit-tester
description: Best practices for writing and validating TacoTip WoW harness tests, including mocking load-captured globals such as C_Map, harness-specific string helpers, TooltipDataProcessor post-call records, and red-green proof with TACOTIP_MAIN_OVERRIDE or a gate flip.
whenToUse: Use when creating or modifying WoWUnit harness tests in Tests/harness, especially Forever tooltip pins, C_Map mocks, post-call assertions, or red-green validation.
---

# WoW Unit Tester Skill

Use this skill when writing or modifying WoWUnit harness tests for TacoTip in `Tests/harness/`, including `forever_tooltip_test.lua` and `tooltip_test.lua`.

## Steps

1. **Avoid static-analysis warnings when mocking globals.**
   - Never use `-- luacheck: ignore` for field mutations on globals.
   - Mock a method with dynamic table access, then restore it:
     ```lua
     local originalGetUnit = GameTooltip.GetUnit
     GameTooltip["GetUnit"] = function() return "TestPlayer", "mouseover" end
     -- teardown
     GameTooltip["GetUnit"] = originalGetUnit
     ```

2. **Mock top-level global functions with WoWUnit.**
   ```lua
   Replace("GetGuildInfo", function(unit)
       if (unit == "player") then return "TestGuild", "Rank 5", 5 end
       return nil
   end)
   ```
   Always call `ClearReplaces()` at the end of the test.

3. **Use the local `pc` pcall wrapper for risky UI calls.**
   ```lua
   local ok = pc(GameTooltip.SetUnit, GameTooltip, "player")
   IsTrue(ok, "SetUnit(player) did not error")
   ```

4. **Assert UI state by invoking hooks and inspecting rendered lines.**
   ```lua
   local script = GameTooltip:GetScript("OnTooltipSetUnit")
   local ok = pc(script, GameTooltip)
   ```
   Inspect global text lines such as `_G.GameTooltipTextLeft2` to verify rendered output.

5. **Mock a global that main.lua captured at load time using mutable indirection.**
   - Define the table field before `main.lua` loads so the captured function reads mutable state instead of a fixed value:
     ```lua
     REALG.C_Map = {
         GetBestMapForUnit = function(u)
             return REALG.__bestMapForUnit and REALG.__bestMapForUnit(u) or nil
         end,
         GetMapInfo = function(id)
             return REALG.__mapInfo and REALG.__mapInfo(id) or nil
         end,
     }
     ```
   - After load, change answers per unit by assigning the state functions, not by replacing the table field:
     ```lua
     local ZONE_MAP = { player = 84, party1 = 84 }
     REALG.__bestMapForUnit = function(u) return ZONE_MAP[u] end
     REALG.__mapInfo = function(mapID)
         if (mapID == 84) then return { name = "Elwynn Forest" } end
         return nil
     end
     ```
   - Simulate "client cannot answer" by setting `REALG.__bestMapForUnit = nil`.
   - Save and restore `REALG.__bestMapForUnit` and `REALG.__mapInfo` around the pin.

6. **Extract and call `TooltipDataProcessor` post-call functions by their record shape.**
   - Registered records are `{ typ = ..., fn = ... }`.
   - Assign the function itself, then call it directly:
     ```lua
     local itemPost
     for _, rec in STD.ipairs(POSTCALLS) do
         if (rec.typ == REALG.Enum.TooltipDataType.Item) then itemPost = rec.fn end
     end
     local okLoot = STD.pcall(itemPost, GT, { hyperlink = GEAR_LINK })
     ```
   - Do not write `itemPost.fn`; `rec.fn` is already the function.
   - When using a whole record, call `POSTCALLS[1].fn(GT, payload)`.

7. **Use the string helper that exists in the harness being edited.**
   - Forever harness pins use `STD.string.find` and `STD.string.gsub`.
   - Shared harness pins use `string.find` and `string.gsub` (or `STD.string.*` where `STD` is in scope).
   - `STD.gsub` is not defined in either harness.

8. **Prove a new Forever pin red, then green.**
   - Forever harness supports override environment variables for throwaway copies only:
     ```bash
     git show HEAD:main.lua > /tmp/main_old.lua
     TACOTIP_MAIN_OVERRIDE=/tmp/main_old.lua lua5.1 Tests/harness/forever_tooltip_test.lua
     lua5.1 Tests/harness/forever_tooltip_test.lua
     rm -f /tmp/main_old.lua
     unset TACOTIP_MAIN_OVERRIDE
     ```
     The first run must show the new pin `FAIL`; the second must show `PASS`.
   - The shared harness has no override support. For a cross-client Forever-only gate, use a documented gate flip on a throwaway copy of `main.lua`:
     ```bash
     cp main.lua /tmp/main_gate_flip.lua
     # temporarily change only the throwaway copy, e.g. isForever and UnitIsPlayer(...) -> UnitIsPlayer(...)
     # run the targeted shared harness command against that throwaway copy's logic as appropriate
     rm -f /tmp/main_gate_flip.lua
     ```
   - Gates must always load the shipped tree. Do not leave `TACOTIP_MAIN_OVERRIDE`, `TACOTIP_LIB_OVERRIDE`, a temporary override file, or an edited gate in the shipped tree.

## Pitfalls

- `REALG.C_Map` field replacement after `main.lua` has loaded does not change what the addon calls; use `REALG.__bestMapForUnit` indirection instead.
- `STD.gsub` does not exist; use `STD.string.gsub` in Forever pins or `string.gsub` in shared pins.
- `itemPost` extracted from `POSTCALLS` is already `rec.fn`; calling `itemPost.fn` fails with "attempt to index ... (a function value)".
- A red-green proof that edits the shipped gate or leaves an override env var invalidates the acceptance run.
- Restore every mocked global, map state function, owner, and unit in teardown to avoid cross-pin state pollution.

## Verification

```bash
luacheck main.lua Tests/harness/forever_tooltip_test.lua Tests/harness/tooltip_test.lua
lua5.1 Tests/harness/forever_tooltip_test.lua
lua5.1 Tests/harness/tooltip_test.lua 1 16001 FOREVER pipeline
bash Tests/harness/run_all.sh
```

Confirm the Forever pins pass, the shared Forever tooltip harness passes, and no temporary override or edited gate remains in the shipped tree.
