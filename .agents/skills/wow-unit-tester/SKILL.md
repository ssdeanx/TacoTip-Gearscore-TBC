---
name: wow-unit-tester
description: Best practices for writing and validating TacoTip WoW harness tests — run the full gate matrix (main harness 75/75, `luacheck .` 0/0, Extras harness 42/42, both `--worktree` release verifiers and `wowlua_ls check .`), call tooltip_test.lua with its canonical `<mockArity> <interface> <family>` arguments, read the harness SetPoint append behaviour when pinning anchors, prove updated pins catch removed behaviour with a temporary-reintroduction red proof, mock and restore client-state globals, verify pins on all five clients, sync CHANGELOG/README and the desk journal, plus mocking load-captured globals such as C_Map, harness-specific string helpers, TooltipDataProcessor post-call records, one-shot InitInspectFrame verification, and targeted main.lua revert discipline without git.
whenToUse: Use when creating or modifying WoWUnit harness tests in Tests/harness, when a harness suite goes red after a code edit, when a behavior change removed code and its pins must be proven to catch a regression via temporary reintroduction, when running the complete gate matrix (main harness, luacheck, Extras harness, both release verifiers, the wowlua_ls LSP gate), when adding a tooltip_test geometry or anchor pin (power bar, health bar, appended rows), when a pin fails on all five clients, when mocking C_Map or other load-captured globals, asserting post-call records, exercising InitInspectFrame one-shot behaviour, fixing pane frame mocks, restoring unauthorized main.lua edits without git, or syncing CHANGELOG/README/desk journal after a behavior change.
---

# WoW Unit Tester Skill

Use this skill when writing or modifying WoWUnit harness tests for TacoTip in `Tests/harness/`, including `forever_tooltip_test.lua` and `tooltip_test.lua`, and whenever a code edit needs the harness gate.

## Steps

1. **Gate every TacoTip code edit with the full matrix — do not hand back a red tree.**
   ```bash
   cd /home/sam/TacoTip-Gearscore-TBC
   bash Tests/harness/run_all.sh 2>&1 | tail -4
   luacheck . 2>&1 | tail -2
   bash TacoTip_Extras/Tests/harness/run_all.sh 2>&1 | tail -4
   bash Tools/verify_release.sh --worktree 2>&1 | tail -2
   bash Tools/verify_release_extras.sh --worktree 2>&1 | tail -2
   timeout 240 wowlua_ls check . 2>&1 | tail -3
   ```

   | gate | command | green means |
   | :--- | :--- | :--- |
   | main harness | `bash Tests/harness/run_all.sh` | `TOTAL 75 invocations: 75 passed, 0 failed` |
   | linter | `luacheck .` | `Total: 0 warnings / 0 errors in N files` |
   | Extras harness | `bash TacoTip_Extras/Tests/harness/run_all.sh` | `TOTAL 42 invocations: 42 passed, 0 failed` |
   | root package | `bash Tools/verify_release.sh --worktree` | `verify_release: PASS` |
   | Extras package | `bash Tools/verify_release_extras.sh --worktree` | `verify_release_extras: PASS` |
   | LSP | `wowlua_ls check .` | exit 0, no `[ERROR ...]` lines |

   The LSP takes the **repository root as a directory**, so the invocation is `wowlua_ls check .` from `/home/sam/TacoTip-Gearscore-TBC`; it exits 1 on any diagnostic. Long gates (main harness, LSP) should run as a background job so progress is visible:
   ```bash
   node "$DSH_PROGRESS_CLI" run --task main-harness -- bash Tests/harness/run_all.sh
   node "$DSH_PROGRESS_CLI" run --task wowlua -- bash -c 'wowlua_ls check . 2>&1 | tail -3'
   ```
   If any gate is red, isolate the failing family (step 3), diagnose from the harness source (steps 4-5), then fix the pin or the production code (step 6), prove it (step 2), and re-run the whole matrix. Report the actual counts — 75/75, 0/0, 42/42, both `PASS` and the LSP exit code — never "all gates pass" without them. The Extras harness, both verifiers and the LSP gate are part of the matrix; skipping them is an incomplete run.

2. **Prove the updated pins catch the removed behaviour — temporary reintroduction, then restore (red-green).**
   When the change *removed* code (e.g. the v1.0.7 FOREVER per-appended-row bottom-pad reserve `wideBottomPad += linesToAddCount * (fontSize + 2)`), a green pin is not enough: show it goes red against the old behaviour, then restore the shipped tree before the gate matrix.
   ```bash
   cd /home/sam/TacoTip-Gearscore-TBC
   cp main.lua /tmp/main_fixed.lua        # backup of the SHIPPED file, before any edit
   # now re-insert ONLY the removed behaviour into main.lua, marked NOT SHIPPED:
   #   -- RED-PROOF TEMPORARY RESERVE (not shipped)
   lua5.1 Tests/harness/tooltip_test.lua 1 16001 FOREVER pipeline 2>&1 | tail -5
   ```
   The run must fail with the concrete diagnostic of the pin that guards the behaviour, e.g.
   ```
   FAIL v1.0.4 wide_style: default 12pt applies base bottom padding bottom=18
   FAIL v1.0.4 wide_style: 16pt font scales bottom padding to base bottom=24
   FAIL v1.0.4 wide_style: OnShow restores bottom padding after Blizzard ClearPadding ...
   ```
   (4 pins red, `bottom=18 expectedBottom=4`). Quote that output as the proof. Then restore and re-green:
   ```bash
   cp /tmp/main_fixed.lua main.lua && rm -f /tmp/main_fixed.lua
   lua5.1 Tests/harness/tooltip_test.lua 1 16001 FOREVER pipeline 2>&1 | tail -1   # ALL 248 PASS
   git diff --stat -- main.lua            # only the intended fix; no red-proof block left
   ```
   Only after the shipped file is restored and the targeted harness is green again do you start the matrix in step 1. Never run the full gates with the buggy block still in the tree.

3. **Invoke `tooltip_test.lua` with the canonical arguments, never a bare family.**
   `Tests/harness/run_all.sh:153-157` invokes it as `<mockArity> <interface> <family> [pipeline]`:

   | family | invocation |
   | :--- | :--- |
   | CLASSIC_ERA | `lua5.1 Tests/harness/tooltip_test.lua 2 11509 CLASSIC_ERA` |
   | TBC_ANNIV | `lua5.1 Tests/harness/tooltip_test.lua 5 20506 TBC_ANNIV` |
   | TITANFORGE | `lua5.1 Tests/harness/tooltip_test.lua 11 38002 TITANFORGE` |
   | FOREVER | `lua5.1 Tests/harness/tooltip_test.lua 1 16001 FOREVER pipeline` |
   | RETAIL | `lua5.1 Tests/harness/tooltip_test.lua 1 120105 RETAIL pipeline` |

   Confirm the exact argv before running by grepping the driver:
   ```bash
   grep -n 'tooltip_test' Tests/harness/run_all.sh
   ```
   A bare `... tooltip_test.lua FOREVER` dies with `bad argument #2 to '?' (string expected, got nil)` — that is a wrong invocation, not a product failure.

4. **Read the harness `SetPoint`/`GetPoint` mock before trusting an anchor pin.**
   Locate both mocks and read the block:
   ```bash
   grep -n 'w.SetPoint = function\|w.GetPoint = function\|SetPoint = function' Tests/harness/tooltip_test.lua | head -5
   ```
   The harness `SetPoint` mock **appends** an anchor entry; it does not replace the previous one (the live engine replaces). Index 1 is therefore the creation-time anchor, not the current layout. Any pin that anchors a frame and then reads anchor index 1 is reading stale state.

5. **Read the most recent `TOPLEFT` anchor, not the creation-time one.**
   Scan the recorded anchors and keep the last `TOPLEFT` (adapt the exact indices/return shape to the `GetPoint` mock found in step 4 — it is index-driven):
   ```lua
   local bar = REALG.TacoTipPowerBar
   local function anchorY()
       if (not bar or type(bar.GetPoint) ~= "function") then return nil end
       -- The harness SetPoint APPENDS (the engine replaces), so the first
       -- entry is the creation-time anchor: keep the latest TOPLEFT.
       local y
       for i = 1, 8 do
           local ok, p, _rel, _rp, _ox, oy = pcall(bar.GetPoint, bar, i)
           if (not ok or p == nil) then break end
           if (p == "TOPLEFT") then y = oy end
       end
       return y
   end
   ```
   TODO: verify the mock's real return arity at the line found in step 4 before shipping the loop.

6. **Update a failing pin to the intended behaviour instead of reverting the code.**
   - When a geometry pin fails because the behaviour intentionally changed, split the pin into the cases that now exist rather than restoring old code. Example (v1.0.7 FOREVER wide pad): one check for *no power bar → base pad only* and one for *power bar on → appended Pawn/iLvl rows fit inside the border*. The base wide pad stays unconditional; the row reserve applies only while the bar is drawn.
   - Do not weaken, delete, or blindly retune an assertion to make it pass. Prove the expectation from the code path you changed, and prove the split pin catches the old code (step 2).
   - If a pin fails on **all five clients at once**, suspect the pin/harness (steps 4-5) before the addon — a shared mock mechanic is the usual cause.
   - Check whether the committed code was already correct before "fixing" it: `git diff --stat -- main.lua` (empty output = tree matches the commit).

7. **Mock and restore client-state globals around a pin.**
   Save, override, then restore every global and config field the pin touched:
   ```lua
   local CFG = REALG.TacoTipConfig
   local prevShowPower = CFG.show_power_bar
   CFG.show_power_bar = true
   local savedUnitPowerMax = REALG.UnitPowerMax
   rawset(REALG, "UnitPowerMax", function() return 100 end)
   -- ... run the checks ...
   rawset(REALG, "UnitPowerMax", savedUnitPowerMax)
   CFG.show_power_bar = prevShowPower
   ```
   Use `rawset(REALG, ...)` for globals so luacheck does not flag an unexpected field (`REALG = _G` is defined at the top of `tooltip_test.lua`). Read `CFG` fresh (`REALG.TacoTipConfig`) at the point of use rather than caching it once.

8. **Clear luacheck warnings by renaming, never by ignoring.**
   A re-used local name in a copied pin raises `shadowing definition of variable 'x' on line N`. Rename the new local (`basePad` → `geoBasePad`) and re-run `luacheck <file>`. Never add `-- luacheck: ignore` or disable a check to pass the gate.

9. **Verify a new pin on all five clients, then the full suite.**
   ```bash
   for c in "2 11509 CLASSIC_ERA" "5 20506 TBC_ANNIV" "11 38002 TITANFORGE" "1 16001 FOREVER pipeline" "1 120105 RETAIL pipeline"; do
       printf '%-28s ' "$c"
       lua5.1 Tests/harness/tooltip_test.lua $c 2>&1 | grep -c 'FAIL'
   done
   ```
   Every line must print `0`. Then run the gates from step 1 again (`luacheck .` → 0 warnings, `run_all.sh` → 75/75). Confirm the new checks appear on every family, not only FOREVER.

10. **Avoid static-analysis warnings when mocking globals.**
    - Never use `-- luacheck: ignore` for field mutations on globals.
    - Mock a method with dynamic table access, then restore it:
      ```lua
      local originalGetUnit = GameTooltip.GetUnit
      GameTooltip["GetUnit"] = function() return "TestPlayer", "mouseover" end
      -- teardown
      GameTooltip["GetUnit"] = originalGetUnit
      ```

11. **Mock top-level global functions with WoWUnit.**
    ```lua
    Replace("GetGuildInfo", function(unit)
        if (unit == "player") then return "TestGuild", "Rank 5", 5 end
        return nil
    end)
    ```
    Always call `ClearReplaces()` at the end of the test.

12. **Use the local `pc` pcall wrapper for risky UI calls.**
    ```lua
    local ok = pc(GameTooltip.SetUnit, GameTooltip, "player")
    IsTrue(ok, "SetUnit(player) did not error")
    ```

13. **Assert UI state by invoking hooks and inspecting rendered lines.**
    ```lua
    local script = GameTooltip:GetScript("OnTooltipSetUnit")
    local ok = pc(script, GameTooltip)
    ```
    Inspect global text lines such as `_G.GameTooltipTextLeft2` to verify rendered output.

14. **Mock a global that main.lua captured at load time using mutable indirection.**
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

15. **Extract and call `TooltipDataProcessor` post-call functions by their record shape.**
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

16. **Use the string helper that exists in the harness being edited.**
    - Forever harness pins use `STD.string.find` and `STD.string.gsub`.
    - Shared harness pins use `string.find` and `string.gsub` (or `STD.string.*` where `STD` is in scope).
    - `STD.gsub` is not defined in either harness.

17. **Require test-driven verification for code changes.**
    - Run the smallest relevant harness before editing behavior; the failing pin defines the expected behavior.
    - Fix production code to satisfy the test. Do not weaken, bypass, or rewrite tests merely to match old code.
    - For a new Forever pin that describes behaviour the tree does not yet have, prove red, then green:
      ```bash
      git show HEAD:main.lua > /tmp/main_old.lua
      TACOTIP_MAIN_OVERRIDE=/tmp/main_old.lua lua5.1 Tests/harness/forever_tooltip_test.lua
      lua5.1 Tests/harness/forever_tooltip_test.lua
      rm -f /tmp/main_old.lua
      unset TACOTIP_MAIN_OVERRIDE
      ```
      The first run must show the new pin `FAIL`; the second must show `PASS`.
    - For behaviour that was *removed* (code taken out of the shipped tree), use the backup-and-reintroduce proof in step 2 instead; the shipped `main.lua` is the only file that changes, and it is restored from the `cp` backup.
    - The shared harness has no override support. For a cross-client Forever-only gate, use a documented gate flip on a throwaway copy of `main.lua`:
      ```bash
      cp main.lua /tmp/main_gate_flip.lua
      # temporarily change only the throwaway copy, e.g. isForever and UnitIsPlayer(...) -> UnitIsPlayer(...)
      # run the targeted shared harness command against that throwaway copy's logic as appropriate
      rm -f /tmp/main_gate_flip.lua
      ```
    - Gates must always load the shipped tree. Do not leave `TACOTIP_MAIN_OVERRIDE`, `TACOTIP_LIB_OVERRIDE`, a temporary override file, a red-proof block, or an edited gate in the shipped tree.

18. **Keep `InitInspectFrame` one-shot until `pcall` succeeds.**
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

19. **Restore unauthorized `main.lua` edits without git.**
    - Never use `git checkout`, `git reset`, `git revert`, or a broad file rewrite to undo an unauthorized change.
    - Read the exact changed hunks with line ranges before editing.
    - Edit only the changed lines, preserving all unrelated code.
    - Restore the one-shot contract: no self-clear at function entry, `pcall` plus boolean check in both init arms, and clearing only after success.
    - Verify against tests, not against old files or memory.
    - Report the restored locations and their restored behavior.

20. **Sync the docs and the desk journal to the behaviour change.**
    - Grep for every doc claim that describes the removed behaviour before writing anything:
      ```bash
      grep -n "count-driven bottom pad\|count-driven pad\|rows below the border" CHANGELOG.md README.md
      ```
    - Rewrite only those claims in `CHANGELOG.md` and `README.md` so they describe the shipped behaviour; do not restyle unrelated sections.
    - Grep the code for stale comments or constants that still name the removed mechanism, and clean up only the leftovers your change orphaned:
      ```bash
      grep -n "linesToAddCount \*\|fontSize + 2" main.lua options.lua | head
      ```
    - Both verifiers only check file presence, so doc drift will not fail them — the grep is the gate.
    - Append a desk journal entry (most recently active desk under `desks/*/journal.md`) recording symptom, fix, the red-proof numbers, and the next step; note that nothing is committed (the operator commits on request).
    - Re-run `bash Tools/verify_release.sh --worktree` and `bash Tools/verify_release_extras.sh --worktree` after the doc edits, since README/CHANGELOG ship in both packages.

## Pitfalls

- A code edit handed back without the gate matrix is unfinished: `luacheck .` 0 warnings, `run_all.sh` 75/75, Extras 42/42, both verifiers `PASS`, and the LSP exit code all have to be seen on the tree you are shipping — report the numbers, not "all green".
- `wowlua_ls check main.lua` fails with `[ERROR wowlua_ls::cli::check] Not a directory: /home/sam/TacoTip-Gearscore-TBC/main.lua`. The headless check takes a **directory**: run `wowlua_ls check .` from the repo root (and never bake the `Not a directory` failure into the report as a code diagnostic).
- `lsp_diagnostics` may fail because no language server is configured for `main.lua`; the project gate is `wowlua_ls check .` on the repository root, and that tool failure is not a code diagnostic.
- `lua5.1 Tests/harness/tooltip_test.lua FOREVER` fails with `bad argument #2 to '?' (string expected, got nil)`; the family is the third argument — use the canonical `<mockArity> <interface> <family> [pipeline]` form from step 3, read out of `run_all.sh`.
- A red proof without a `cp` backup, or full gates run while the reintroduced buggy block is still in `main.lua`, invalidates the acceptance run: back up first, restore from the backup, confirm the targeted harness is green again, then start the matrix.
- A "red proof" that edits the shipped gate, leaves `TACOTIP_MAIN_OVERRIDE` exported, or leaves `/tmp/main_fixed.lua` as the loaded source proves nothing about the shipped tree.
- A red proof with only a summary line is not proof: quote the concrete failing pin text (`bottom=18 expectedBottom=4`), including how many pins went red.
- The harness `SetPoint` mock appends anchors instead of replacing them, so the creation-time anchor sits at index 1. A power-bar pin that reads the first anchor reports the wrong `y` and fails on every client until it reads the latest `TOPLEFT`.
- A pin that goes red on all five clients at once is almost always a harness/mock assumption, not five simultaneous addon defects — inspect the mock before touching `main.lua`.
- Do not "fix" a red geometry pin by reverting the intended behaviour change; split it into the no-bar and bar-on cases. Check `git diff --stat -- main.lua` first — if it is empty, the committed code is what the pin must describe.
- `CFG.show_power_bar` and `REALG.UnitPowerMax` left overridden leak into later pins; restore both in teardown, and use `rawset(REALG, ...)`/dynamic indexing so luacheck stays quiet.
- Re-using a local name in a copied pin raises a luacheck shadowing warning; rename it (`basePad` → `geoBasePad`) rather than suppressing the warning.
- `REALG.C_Map` field replacement after `main.lua` has loaded does not change what the addon calls; use `REALG.__bestMapForUnit` indirection instead.
- `STD.gsub` does not exist; use `STD.string.gsub` in Forever pins or `string.gsub` in shared pins.
- `itemPost` extracted from `POSTCALLS` is already `rec.fn`; calling `itemPost.fn` fails with "attempt to index ... (a function value)".
- Leaving `CHANGELOG.md`/`README.md` describing the removed mechanism is unfinished work, and the verifiers will not catch it — they only check that the files exist.
- Restore every mocked global, map state function, owner, and unit in teardown to avoid cross-pin state pollution.
- Do not clear `TT.InitInspectFrame` at function entry; a failed first attempt must remain callable.
- Do not treat `pcall` success as initialization success unless the returned boolean is `true`.
- Do not mock pane data fields as no-op functions; anchor hook presence tests treat functions as truthy.
- `CreateFrame` must return an object exposing `HookScript`; otherwise init fails with "attempt to call method 'HookScript' (a nil value)".
- For unauthorized `main.lua` edits, do not use any git restore command; read exact hunks and hand-edit only the changed lines, then verify with tests.

## Verification

```bash
cd /home/sam/TacoTip-Gearscore-TBC

# 1. red proof on the shipped tree (backup, reintroduce, red, restore, green)
cp main.lua /tmp/main_fixed.lua
# ... re-insert the removed behaviour, marked NOT SHIPPED ...
lua5.1 Tests/harness/tooltip_test.lua 1 16001 FOREVER pipeline 2>&1 | tail -5   # FAIL, bottom=18 expectedBottom=4
cp /tmp/main_fixed.lua main.lua && rm -f /tmp/main_fixed.lua
lua5.1 Tests/harness/tooltip_test.lua 1 16001 FOREVER pipeline 2>&1 | tail -1   # ALL 248 PASS
git diff --stat -- main.lua            # only the intended fix

# 2. full gate matrix
timeout 240 wowlua_ls check . 2>&1 | tail -3    # exit 0, no [ERROR] lines
luacheck .                                      # 0 warnings / 0 errors
luacheck main.lua Tests/harness/forever_tooltip_test.lua Tests/harness/tooltip_test.lua
lua5.1 Tests/harness/batch8_pane_test.lua 2 11509 CLASSIC_ERA
lua5.1 Tests/harness/forever_tooltip_test.lua
lua5.1 Tests/harness/tooltip_test.lua 1 16001 FOREVER pipeline
lua5.1 Tests/harness/tooltip_test.lua 1 120105 RETAIL pipeline
bash Tests/harness/run_all.sh                   # TOTAL 75 invocations: 75 passed, 0 failed
bash TacoTip_Extras/Tests/harness/run_all.sh    # TOTAL 42 invocations: 42 passed, 0 failed
bash Tools/verify_release.sh --worktree         # verify_release: PASS
bash Tools/verify_release_extras.sh --worktree  # verify_release_extras: PASS

# 3. doc sync leftovers
grep -n "count-driven bottom pad\|count-driven pad\|rows below the border" CHANGELOG.md README.md
grep -n "linesToAddCount \*\|fontSize + 2" main.lua options.lua | head
```

Confirm the red proof quoted a concrete failing pin and the shipped file was restored and green again before the matrix; the repo-wide `luacheck .` run is 0 warnings / 0 errors; the main harness is 75/75 and Extras 42/42; both `--worktree` verifiers print `PASS`; `wowlua_ls check .` exits 0 with no diagnostics (and `wowlua_ls check <file>.lua` is never used); all 9 batch8 pane checks pass; Forever pins and the shared FOREVER tooltip harness pass with no guild-guard regressions; CHANGELOG/README no longer describe the removed behaviour and the desk journal records the change; and no temporary override, red-proof block, `/tmp` backup, or edited gate remains in the shipped tree. Confirm `InitInspectFrame` remains callable after a failed registration attempt.
