---
name: wow-unit-tester
description: Best practices for writing and validating TacoTip WoW harness tests, including mocking load-captured globals such as C_Map, harness-specific string helpers, TooltipDataProcessor post-call records, one-shot InitInspectFrame verification, targeted main.lua revert discipline without git, and red-green proof.
whenToUse: Use when creating or modifying WoWUnit harness tests in Tests/harness, especially Forever tooltip pins, C_Map mocks, post-call assertions, InitInspectFrame one-shot behavior, pane frame mocks, unauthorized main.lua revert work, or red-green validation.
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

8. **Require test-driven verification for code changes.**
   - Run the smallest relevant harness before editing behavior; the failing pin defines the expected behavior.
   - Fix production code to satisfy the test. Do not weaken, bypass, or rewrite tests merely to match old code.
   - For a new Forever pin, prove red, then green:
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

9. **Keep `InitInspectFrame` one-shot until `pcall` succeeds.**
   - `TT:InitInspectFrame()` must not clear `TT.InitInspectFrame` before `guardBlizzardInspectGuildFrame()` or before hook installation. It installs hooks and returns `true` only after success:
     ```lua
     function TT:InitInspectFrame()
         guardBlizzardInspectGuildFrame()
         InspectPaperDollFrame:HookScript("OnShow", TT.RefreshInspectFrame)
         InspectFrame:HookScript("OnHide", function()
             InspectGearScore:Hide()
             InspectAvgItemLvl:Hide()
         end)
         return true
     end
     ```
   - Both caller arms must call it through `pcall` and clear the one-shot only when the boolean result is `true`:
     ```lua
     if (type(TT.InitInspectFrame) == "function" and InspectModelFrame and InspectPaperDollFrame) then
         local okInit, didInit = pcall(TT.InitInspectFrame, TT)
         if (okInit and didInit == true) then
             TT.InitInspectFrame = nil
         end
     end
     ```
   - `RefreshInspectFrame` may invoke the captured one-shot, but must clear it only after that call returns `true`:
     ```lua
     local initInspectFrame = TT.InitInspectFrame
     if (type(initInspectFrame) == "function") then
         if (not initInspectFrame(TT)) then
             return
         end
         TT.InitInspectFrame = nil
     end
     ```
   - Tests that exercise the install path must re-arm `TT.InitInspectFrame` with the saved one-shot before invoking the `ADDON_LOADED` handler, because a previously successful run has consumed it.
   - The pane mock must return a frame object from `CreateFrame`, and that object must expose `HookScript`:
     ```lua
     f.CreateFrame = function(_, kind, name, parent)
         local frame = newFrame(kind, name, parent)
         frame.HookScript = function(self, eventName, handler)
             self.__hooks = self.__hooks or {}
             self.__hooks[eventName] = handler
             return self
         end
         return frame
     end
     ```
   - Pane anchor-hook presence tests require data fields such as `parent.action`, `parent.spellId`, and `owner.unit` to read `nil`, not no-op functions:
     ```lua
     local absentDataFields = { action = true, spellId = true, unit = true }
     setmetatable(frame, {
         __index = function(_, key)
             if (absentDataFields[key]) then return nil end
             -- other mock fields
         end,
     })
     ```

10. **Restore unauthorized `main.lua` edits without git.**
    - Never use `git checkout`, `git reset`, `git revert`, or a broad file rewrite to undo an unauthorized change.
    - Read the exact changed hunks with line ranges before editing.
    - Edit only the changed lines, preserving all unrelated code.
    - Restore the one-shot contract: no self-clear at function entry, `pcall` plus boolean check in both init arms, and clearing only after success.
    - Verify against tests, not against old files or memory.
    - Report the restored locations and their restored behavior.

## Pitfalls

- `REALG.C_Map` field replacement after `main.lua` has loaded does not change what the addon calls; use `REALG.__bestMapForUnit` indirection instead.
- `STD.gsub` does not exist; use `STD.string.gsub` in Forever pins or `string.gsub` in shared pins.
- `itemPost` extracted from `POSTCALLS` is already `rec.fn`; calling `itemPost.fn` fails with "attempt to index ... (a function value)".
- A red-green proof that edits the shipped gate or leaves an override env var invalidates the acceptance run.
- Restore every mocked global, map state function, owner, and unit in teardown to avoid cross-pin state pollution.
- Do not clear `TT.InitInspectFrame` at function entry; a failed first attempt must remain callable.
- Do not treat `pcall` success as initialization success unless the returned boolean is `true`.
- Do not mock pane data fields as no-op functions; anchor hook presence tests treat functions as truthy.
- `CreateFrame` must return an object exposing `HookScript`; otherwise init fails with "attempt to call method 'HookScript' (a nil value)".
- `lsp_diagnostics` may fail because no language server is configured for `main.lua`; use `wowlua_ls` against the changed file or tests, and do not treat that tool failure as a code diagnostic.
- For unauthorized `main.lua` edits, do not use any git restore command; read exact hunks and hand-edit only the changed lines, then verify with tests.

## Verification

```bash
wowlua_ls check main.lua
luacheck main.lua Tests/harness/forever_tooltip_test.lua Tests/harness/tooltip_test.lua
lua5.1 Tests/harness/batch8_pane_test.lua 2 11509 CLASSIC_ERA
lua5.1 Tests/harness/forever_tooltip_test.lua
lua5.1 Tests/harness/tooltip_test.lua 1 16001 FOREVER pipeline
bash Tests/harness/run_all.sh
```

Confirm the changed file has no new `wowlua_ls` diagnostics, all 9 batch8 pane checks pass, Forever pins pass, the shared Forever tooltip harness passes, no guild-guard regressions occur, and no temporary override or edited gate remains in the shipped tree. Confirm `InitInspectFrame` remains callable after a failed registration attempt.
