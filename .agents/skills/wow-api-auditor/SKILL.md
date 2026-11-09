---
name: wow-api-auditor
description: Verifies Blizzard WoW API signatures, generated-documentation entries, presence, secret-value annotations, secret-value power-bar handling for UnitPowerMax and UnitPower, combat-restricted aura tooltip passthrough rules, nested generated-doc blocks via awk Name-to-close range reads, and Forever ClassTalentsFrame/PlayerSpells inspect paths across Classic Era, Anniversary, Titan, Forever, and Live clients using read-only origin/<branch> reads of the local FrameXML checkout.
whenToUse: Use when you need to confirm an API's signature, generated-documentation entry, availability, secret annotation, or aura tooltip passthrough behavior differs across WoW client families; to trace Forever inspect/trait-config paths (ClassTalentsFrame RefreshConfigID, PlayerSpells inspectUnit, INSPECT_TRAIT_CONFIG_ID/TraitConsts, TraitConfigInfo); when grep -A truncates or returns no output for nested documentation blocks and an awk Name-to-close range read is needed; to audit addon code for unsafe secret/combat handling and direct protected-function calls (CanInspect, CheckInteractDistance); to fix or audit the tooltip power bar that shows when UnitPowerMax/UnitPower are secret values on Forever/Live; or when luacheck reports W113 for issecretvalue, without mutating the checkout.
---

# WoW API Auditor Skill

Use this skill whenever you need to verify how a Blizzard API function works, what its signature is, whether it is present or behaves differently across the five supported client families (Classic Era, Anniversary, Titan, Forever, Live), whether it carries secret-value or combat-restriction annotations, whether addon code safely handles secret/combat aura tooltip text and protected Blizzard functions, or whether a power-bar gate is secret-safe when UnitPowerMax/UnitPower are secret values on Forever/Live.

## Steps

1. **Locate the source repo (read-only).** The official Blizzard FrameXML checkout is at `/home/sam/wow-ui-source`. Never modify its working tree; all reads below use remote refs. Confirm cleanliness first:
   ```bash
   git -C /home/sam/wow-ui-source status --short
   ```

2. **Fix the branch set (five branches only).** Use these exact refs; do not substitute `origin/classic` or `origin/mainline`:
   - Classic Era: `origin/classic_era`
   - Anniversary: `origin/classic_anniversary`
   - Titan: `origin/classic_titan`
   - Forever: `origin/forever`
   - Live: `origin/live`

3. **Verify presence/absence across all five branches.** For an API name `API_NAME` (for example `NotifyInspect`), run a presence check against generated documentation on every branch:
   ```bash
   cd /home/sam/wow-ui-source
   for b in origin/classic_era origin/classic_anniversary origin/classic_titan origin/forever origin/live; do
     printf "%-28s " "$b"
     if git grep -q 'Name = "API_NAME"' "$b" -- '*Documentation.lua'; then echo PRESENT; else echo ABSENT; fi
   done
   ```

4. **Capture the exact documentation file path per branch.** For each branch where the API is present, record the path reported by `git grep -l` (strip the leading `<ref>:`):
   ```bash
   cd /home/sam/wow-ui-source
   for b in origin/classic_era origin/classic_anniversary origin/classic_titan origin/forever origin/live; do
     echo "== $b"
     git grep -l 'Name = "API_NAME"' "$b" -- '*Documentation.lua' | sed "s#^$b:##" || echo ABSENT
   done
   ```
   Cite these paths verbatim in the final report (e.g. `Interface/AddOns/Blizzard_APIDocumentationGenerated/PlayerScriptDocumentation.lua`).

5. **Read the signature block without checkout.** Use `git show <ref>:<path>` piped to `grep -A` (the block usually spans 20-30 lines):
   ```bash
   cd /home/sam/wow-ui-source
   git show origin/<branch>:Interface/AddOns/Blizzard_APIDocumentationGenerated/<DocFile>.lua \
     | grep -A24 'Name = "API_NAME"'
   ```
   Repeat for each branch; note argument/return differences (Nilable, Type, etc.).

5a. **Nested generated-doc extraction with awk range reads.** `grep -A` often truncates or returns no output for nested structures in `SpecializationInfoDocumentation.lua`, `SharedTraitsDocumentation.lua`, and `TraitConstantsDocumentation.lua`. Use `git show ... | awk` from the `Name = "..."` line to the matching close brace. Pick the close pattern that matches the nesting level (`/^\t\t},$/` for a function/structure entry, `/^ },$/` for the trailing block):
   ```bash
   cd /home/sam/wow-ui-source
   # Generic fallback when grep -A returns no output or truncates:
   git show origin/<branch>:Interface/AddOns/Blizzard_APIDocumentationGenerated/<DocFile>.lua \
     | awk '/Name = "API_NAME"/,/^\t\t},$/ {print}'

   # SpecializationInfo (Forever): full GetSpecialization, TalentInfoQuery, TalentInfoResult
   git show origin/forever:Interface/AddOns/Blizzard_APIDocumentationGenerated/SpecializationInfoDocumentation.lua \
     | awk '/Name = "GetSpecialization"/,/^\t\t},$/ {print}'
   git show origin/forever:Interface/AddOns/Blizzard_APIDocumentationGenerated/SpecializationInfoDocumentation.lua \
     | awk '/Name = "TalentInfoQuery"/,/^\t\t},$/ {print}'
   git show origin/forever:Interface/AddOns/Blizzard_APIDocumentationGenerated/SpecializationInfoDocumentation.lua \
     | awk '/Name = "TalentInfoResult"/,/^\t\t},$/ {print}'

   # SharedTraits (Forever): config list and nested TraitConfigInfo
   git show origin/forever:Interface/AddOns/Blizzard_APIDocumentationGenerated/SharedTraitsDocumentation.lua \
     | awk '/Name = "GetConfigsByType"/,/^\t\t},$/ {print}'
   git show origin/forever:Interface/AddOns/Blizzard_APIDocumentationGenerated/SharedTraitsDocumentation.lua \
     | awk '/Name = "TraitConfigInfo"/,/^ },$/ {print}'
   # Call sites excluding generated documentation
   git grep -n 'GetConfigsByType\|GetConfigIDsBySpecID' origin/forever -- '*.lua' | grep -v Documentation
   ```
   GetConfigsByType records SecretArguments AllowedWhenUntainted, and the call-site grep names Blizzard_ClassTalentsFrame.lua:802 calling GetConfigIDsBySpecID. Report the full argument/return/field list from the awk output, not a truncated `grep -A` excerpt. `GetConfigsByType` takes `configType` and returns `configIDs`; `TraitConfigInfo` includes `ID`, `type`, `name`, `treeIDs`, and `usesSharedActionBars`. Copy every field Name verbatim and never normalize or rename fields: TalentInfoQuery lists groupIndex, isInspect, and tier. If you think you see talentGroup in the query, you are misreading the block, so re-extract with the awk range above and report what the output actually shows.

6. **Read implementation or call sites via `git show` / `git grep` on the ref.** Determine the client-specific source path first (paths differ by family), then read a section:
   ```bash
   cd /home/sam/wow-ui-source
   # Example: Item.lua differs by family
   git show origin/classic_era:Interface/AddOns/Blizzard_ObjectAPI/Classic/Item.lua | sed -n '260,285p'
   git show origin/forever:Interface/AddOns/Blizzard_ObjectAPI/Mainline/Item.lua | sed -n '1,60p'
   ```
   For unknown paths, locate them without checkout:
   ```bash
   git ls-tree -r --name-only origin/<branch> | grep -i '<FileName>'
   ```
   For cross-branch call-site searches:
   ```bash
   git grep -n 'API_NAME' origin/<branch> -- '*.lua'
   ```

6a. **Forever inspect/trait-config read chain.** Use read-only `git show`/`git grep` on `origin/forever` only (never Classic/Retail refs) to trace the inspect talent path:
   ```bash
   cd /home/sam/wow-ui-source

   # ClassTalentsFrame RefreshConfigID / inspect load path
   echo "=== ClassTalentsFrame RefreshConfigID ==="
   git show origin/forever:Interface/AddOns/Blizzard_PlayerSpells/ClassTalents/Blizzard_ClassTalentsFrame.lua | sed -n '875,905p'

   # PlayerSpells inspect setup
   echo "=== PlayerSpells inspect setup ==="
   git show origin/forever:Interface/AddOns/Blizzard_PlayerSpells/Blizzard_PlayerSpellsFrame.lua | grep -n -B6 -A25 "inspectUnit ="

   # INSPECT_TRAIT_CONFIG_ID definition and usages
   echo "=== INSPECT_TRAIT_CONFIG_ID occurrences ==="
   git grep -n "INSPECT_TRAIT_CONFIG_ID\|VIEW_TRAIT_CONFIG_ID" origin/forever -- '*.lua' | head -20

   # TraitConsts filtering (constants surface; excludes Constants.TraitConsts call sites)
   echo "=== TraitConsts in Constants ==="
   git grep -rn "TraitConsts" origin/forever -- '*.lua' | grep -v "Constants.TraitConsts" | head -10

   # TraitConsts documentation block
   echo "=== TraitConstantsDocumentation TraitConsts ==="
   git grep -n -A30 'Name = "TraitConsts"' origin/forever -- '*Documentation.lua'

   # TraitConfigInfo structure
   echo "=== TraitConfigInfo ==="
   git show origin/forever:Interface/AddOns/Blizzard_APIDocumentationGenerated/SharedTraitsDocumentation.lua \
     | awk '/Name = "TraitConfigInfo"/,/^ },$/ {print}'
   ```
   Expected findings: `INSPECT_TRAIT_CONFIG_ID = -1` in `TraitConstantsDocumentation.lua` at line 352; `Blizzard_ClassTalentsFrame.lua:887` calls `self:SetConfigID(Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID, forceUpdate)` inside `RefreshConfigID`; `PlayerSpellsFrame.lua` sets `self.inspectUnit` and drives `GetInspectSpecialization`. Cite these paths/lines verbatim.

7. **Parallel branch comparison.** Run the same `git show ... | sed` / `grep -A` extraction for all five branches and compare outputs side by side; record behavioural deltas (e.g. an API absent on some branches, extra parameters, different return shapes). Do not rely on one branch as representative of the others.

8. **Apply findings.** Use only exact signatures and paths verified above in codebase modifications. Do not guess parameters from wikis, which are often outdated. Report a table: branch -> PRESENT/ABSENT, documentation file path, signature/notes.

9. **Audit secret-value annotations.** For any API whose combat or restriction behavior matters, read the same generated documentation block and capture every annotation line, not only arguments and returns:
   ```bash
   cd /home/sam/wow-ui-source
   git show origin/<branch>:Interface/AddOns/Blizzard_APIDocumentationGenerated/<DocFile>.lua \
     | grep -A30 'Name = "API_NAME"' \
     | grep -E 'Secret|Requires|Protected|NeverSecret|MayReturnNothing|SecureHooksAllowed'
   ```
   Record at least these annotations when present: `SecretWhenUnitAuraRestricted`, `SecretArguments`, `RequiresUnitAuraAccess`, `NeverSecret`, `SecureHooksAllowed`, and any other `Secret...` key. Treat these annotations as part of the API contract and cite the exact branch/path where each was found.

10. **Audit combat-restricted aura tooltip data.** Verify `C_TooltipInfo.GetUnitAura` on Forever and Live (it is absent on Classic Era, Anniversary, and Titan in this checkout):
    ```bash
    cd /home/sam/wow-ui-source
    for b in origin/forever origin/live; do
      echo "== $b"
      git show "$b":Interface/AddOns/Blizzard_APIDocumentationGenerated/TooltipInfoDocumentation.lua \
        | grep -A18 'Name = "GetUnitAura"'
    done
    ```
    The documentation reports `SecretWhenUnitAuraRestricted = true` and `SecretArguments = "AllowedWhenUntainted"`. Therefore, in combat the returned `TooltipData` text is a secret value. Audit rule: forward that text untouched; never compare it, lowercase it, search it, concatenate it for diagnostics, use it as a table key, cache/serialize it, or otherwise string-process it. Presence/absence must still be reported per branch (ABSENT on the Classic families).

11. **Audit direct protected-function calls.** Search addon Lua for direct calls to Blizzard protected/restricted functions such as `CanInspect` and `CheckInteractDistance`:
    ```bash
    grep -RInE 'CanInspect|CheckInteractDistance' --include='*.lua' .
    ```
    Run the grep from the addon repo root and paste each grep line verbatim into the report table (file:line, function, call form, client-family guard or skip). Never use placeholder text such as grep hits recorded verbatim in audit and never submit a table with no file:line entries; if grep returns no hits, state explicitly no hits with the command and working directory, and if the output is unavailable, re-run this step before reporting. A generic guard description without a tied call does not count as verified. A call is acceptable only when it is either guarded by a client-aware predicate (for example Forever/Retail skip or library guard) or intentionally limited to Classic clients. Do not leave an unguarded direct call on Forever or Retail.

12. **Audit unsafe tooltip predicates.** Search addon tooltip code for string operations on aura tooltip text:
    ```bash
    grep -RInE 'string\.(lower|upper|find|match|gsub|format)|text ==|== ""' --include='*.lua' .
    ```
    Any comparison or string processing of secret aura tooltip text is unsafe in combat. The required pattern is: validate type, test the secret/access state, and only then run the original detection logic inside a protected call:
    ```lua
    if (type(text) ~= "string") then
        return false
    end
    if (issecretvalue(text) or not canaccessvalue(text)) then
        -- Combat-restricted/secret: forward untouched; do not compare or process.
        return false
    end
    local ok, lowered = pcall(string.lower, text)
    if (not ok or type(lowered) ~= "string") then
        return false
    end
    -- Existing foreign-row detection runs here, unchanged, for ordinary text.
    ```
    This preserves the existing foreign-row detection behavior for ordinary non-secret text because the guard only short-circuits secret or inaccessible values; all other values follow the original path.

13. **Audit `/tt diag` distance reporting.** Locate the diagnostic implementation (search for `collectActiveUnitSection` or `CheckInteractDistance`). On Forever and Retail, do not invoke `CheckInteractDistance` directly; report it as protected/not applicable for that client. On Classic Era, Anniversary, and Titan, call it and report the resulting distance. Required shape:
    ```lua
    if (isForever or isRetail) then
        diagRow(s, "distance", "n/a (protected on this client)", "info")
    else
        local interactDist = fnCheckInteractDistance(activeUnit, 1)
        diagRow(s, "distance", tostring(interactDist), "info")
    end
    ```
    Verify that no `ADDON_ACTION_BLOCKED` error occurs during `/tt diag` on any client.

14. **Audit the secret-value power bar (UnitPowerMax/UnitPower) and gate on issecretvalue — Forever/Live pattern.** Use this when the tooltip power bar must show on Forever/Retail while UnitPowerMax/UnitPower are secret values, without breaking Classic Era.

    a. **Trace power APIs across all five branches.** List which power APIs exist per branch:
       ```bash
       cd /home/sam/wow-ui-source
       for b in origin/classic_era origin/classic_anniversary origin/classic_titan origin/forever origin/live; do
         echo "== $b"
         git grep -l 'Name = "UnitPowerMax"' "$b" -- '*Documentation.lua'
       done
       ```
       Also trace `UnitPower`, `UnitPowerType`, `UnitHealth`, and `UnitHealthMax` the same way. Record the exact documentation path per branch (for UnitPower* this is `Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua`).

    b. **Verify SecretWhen annotations across branches.** Read the full block for each power API on Forever and Live, and on Classic families for contrast:
       ```bash
       cd /home/sam/wow-ui-source
       git show origin/forever:Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua | grep -A24 'Name = "UnitPowerMax"'
       git show origin/live:Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua | grep -A24 'Name = "UnitPowerMax"'
       git show origin/forever:Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua | grep -A24 'Name = "UnitPower"'
       ```
       Expect `SecretWhenUnitPowerRestricted = true` and `SecretArguments = "AllowedWhenUntainted"` on Forever/Live. Check the StatusBar contract the same way so you know whether secret values may be passed through:
       ```bash
       git show origin/forever:Interface/AddOns/Blizzard_APIDocumentationGenerated/SimpleStatusBarAPIDocumentation.lua | grep -A24 'Name = "SetValue"'
       git show origin/live:Interface/AddOns/Blizzard_APIDocumentationGenerated/SimpleStatusBarAPIDocumentation.lua | grep -A24 'Name = "SetMinMaxValues"'
       ```
       Report the annotations with branch and path; these are the root cause of any comparison crash/taint on Forever/Live.

    c. **Audit addon code for unsafe power comparisons.** Search for direct comparisons or arithmetic on power values before any secret check:
       ```bash
       grep -RInE 'UnitPowerMax|UnitPower\(' --include='*.lua' .
       grep -RInE 'maxPower *[><]=?|UnitPowerMax\(unit\) *>' --include='*.lua' .
       ```
       Flag any `UnitPowerMax(unit) > 0`, arithmetic, string conversion, logging, or table-key use on the value. Root cause pattern from evidence: the show gate compared a secret `UnitPowerMax` with `> 0`, which is unsafe on Forever/Live.

    d. **Implement the secret-safe helper, declare the global, and pass values uncompared to StatusBar.**
       Declare the Blizzard client global in the luacheck config that holds globals — never via `_G.issecretvalue` and never by defining your own global `issecretvalue`:
       ```lua
       read_globals = {
           -- existing entries...
           "issecretvalue",
       }
       ```
       In `.luacheckrc` add `"issecretvalue",` to the existing `read_globals` table (inspect with `grep -n 'read_globals.*issecretvalue' .luacheckrc` first). Then use `issecretvalue` directly. Short-circuit on secret before any comparison; the non-secret path keeps the existing `> 0` check and Classic behavior:
       ```lua
       local function tooltipUnitHasVisiblePower(unit)
           local maxPower = UnitPowerMax(unit)
           if (type(issecretvalue) == "function" and issecretvalue(maxPower)) then
               return true
           end
           return maxPower ~= nil and maxPower > 0
       end
       ```
       Pass secret values through to StatusBar without comparing, converting, or logging them. The StatusBar setters accept secret arguments (see step 14b); do not drop a secret value because it cannot be compared:
       ```lua
       bar:SetMinMaxValues(0, maxPower)
       bar:SetValue(curPower)
       ```
       Here `maxPower`/`curPower` are the raw values returned by `UnitPowerMax`/`UnitPower`, forwarded uncompared.

    e. **Pin with secret mocks and mutant red proof, then run the gates.** In `Tests/harness/tooltip_test.lua`, pin secret behavior: mock `issecretvalue` so secret sentinel values return true, assert the show gate returns true for secret `UnitPowerMax` and that the secret values reach the StatusBar setters without comparison. Then prove the pins bite with a mutant: temporarily replace the helper with `return UnitPowerMax(unit) > 0` and re-run — the FOREVER/RETAIL secret pins must fail (red). Restore the helper and re-run green. Record both runs. Run and expect exit 0:
       ```bash
       lua5.1 Tests/harness/tooltip_test.lua 1 16001 FOREVER pipeline
       lua5.1 Tests/harness/tooltip_test.lua 1 120105 RETAIL pipeline
       lua5.1 Tests/harness/tooltip_test.lua 2 11509 CLASSIC_ERA
       luacheck . -- expect Total: 0 warnings / 0 errors
       ```
       A bare `luacheck main.lua Tests/harness/tooltip_test.lua --codes` must not show `W113 accessing undefined variable 'issecretvalue'`; if it does, the `read_globals` declaration is missing — fix the declaration, do not reach for `_G.`.

## Pitfalls

- **Never run `git checkout`.** It mutates the working tree and invalidates parallel branch reads. Always use `origin/<branch>:path` or `git grep <ref>`.
- **Branch-name drift.** This playbook uses `origin/live`, not `origin/mainline`, and the five named branches only. `origin/classic` is not part of this playbook.
- **Path drift by family.** `Item.lua` lives under `.../Classic/Item.lua` on classic_era/anniversary/titan but `.../Mainline/Item.lua` on forever/live. Verify with `git ls-tree` when unsure; do not assume a single path.
- **`git grep <ref>` syntax.** The ref must precede the `--` pathspec: `git grep -n 'PAT' origin/<branch> -- '*Documentation.lua'`. Reversing them fails or searches the working tree.
- **Generated docs are branch-specific.** A documentation file present on one branch may be absent or differently named on another; cite the path actually returned for that branch.
- **Absence is a result.** Report ABSENT explicitly per branch; never infer presence from another branch. `C_TooltipInfo.GetUnitAura` is absent on the Classic families.
- **Signature blocks are multi-line.** Use `-A20` or more; truncating hides Returns/Arguments and annotation differences.
- **`grep -A` can return no output or truncate nested docs.** For nested `SpecializationInfoDocumentation`, `SharedTraitsDocumentation`, and `TraitConstantsDocumentation` blocks, use the awk Name-to-close range reads in step 5a and cite the full block.
- **No placeholder audit tables.** A protected-call audit with placeholder text and no file:line entries, or a generic guard claim untied to any call, is a failed audit even when the prose sounds correct. If grep output is unavailable, re-run step 11 until every hit has a concrete file:line and a tied guard or skip.
- **Never paraphrase documentation field names.** Report groupIndex, tier, and all other field Names exactly as the awk output spells them; normalizing them to talentGroup or moving tier out of the query corrupts the contract.
- **Forever inspect paths are client-specific.** Use `Blizzard_PlayerSpells/ClassTalents/Blizzard_ClassTalentsFrame.lua` and `Blizzard_PlayerSpells/Blizzard_PlayerSpellsFrame.lua` on `origin/forever`; do not substitute Classic or Retail paths or refs.
- **Working tree may sit on classic_era.** Local files reflect only that branch; never treat them as evidence for other branches.
- **Secret text is not comparable.** Expressions such as `text == ""`, `text == nil` only after a type check, `string.lower(text)`, `string.find`, concatenation, logging, or table-key use can crash or taint in combat. Guard with `issecretvalue`/`canaccessvalue` before any operation.
- **pcall is not a substitute for a secret guard.** Use the guard first; use `pcall` as defense in depth around the original string operation.
- **Do not forward transformed secret text.** If a value is secret or inaccessible, pass the original value through unchanged; do not normalize, trim, or annotate it.
- **Protected calls are client-specific.** `CanInspect` and `CheckInteractDistance` restrictions differ between Classic families and Forever/Retail. Do not assume a function safe on one client is safe on another.
- **Do not call protected functions from diagnostics on restricted clients.** On Forever/Retail, report them as protected/not applicable instead of invoking them.
- **Do not weaken foreign-row detection.** The secret guard must short-circuit only secret or inaccessible values; ordinary text must still run the existing detection logic.
- **Do not dodge luacheck W113 with `_G.issecretvalue`.** W113 means `issecretvalue` is missing from `.luacheckrc` `read_globals`. Declare it there and call it directly; `_G.` indirection hides the missing declaration and draws user corrections.
- **Do not define a global `issecretvalue` yourself.** It is a Blizzard client global, not something the add-on creates. Declaring it in `read_globals` is the only correct fix.
- **Do not compare `UnitPowerMax` with `> 0` before checking secrecy.** On Forever/Live the value is secret when the unit's power is restricted (`SecretWhenUnitPowerRestricted`); the comparison itself is unsafe. Check `issecretvalue` first and return true for secret values.
- **Do not drop secret power values before StatusBar.** `SetMinMaxValues`/`SetValue` accept secret arguments. Pass the raw values through uncompared — comparing, converting to a number/string, or logging them first breaks the Forever/Live path.
- **Do not ship a power-bar gate without a secret-mock pin and mutant proof.** If a `UnitPowerMax > 0` mutant does not fail the pins, the pins do not cover the secret path.

## Verification

- `git -C /home/sam/wow-ui-source status --short` is empty (working tree untouched).
- The report covers all five branches with an explicit PRESENT/ABSENT value each.
- Every PRESENT branch cites the exact `Interface/AddOns/...Documentation.lua` path returned by `git grep -l`.
- No `git checkout` (or other state-changing git) command was executed.
- Signatures and annotations applied to code match the generated documentation blocks read from `origin/<branch>:path`.
- `C_TooltipInfo.GetUnitAura` is reported with `SecretWhenUnitAuraRestricted = true` where present, and ABSENT on Classic Era, Anniversary, and Titan.
- Secret aura tooltip text is documented as forward-only: untouched, never compared or string-processed.
- Every direct `CanInspect`/`CheckInteractDistance` call is listed with a concrete file:line from the step 11 grep and a client-aware guard or skip tied to that call, with no placeholder text and no table lacking file:line entries.
- `/tt diag` reports distance on Classic clients and does not invoke `CheckInteractDistance` directly on Forever or Retail.
- No `ADDON_ACTION_BLOCKED` error occurs during `/tt diag`.
- Unsafe tooltip predicates are identified and corrected with an `issecretvalue`/`canaccessvalue` guard plus `pcall` before any string operation, while preserving ordinary-text foreign-row detection.
- `issecretvalue` is declared in `.luacheckrc` `read_globals` and used directly (not via `_G.issecretvalue`, not self-defined); `luacheck` reports 0 warnings / 0 errors and no W113 for `issecretvalue`.
- The power-bar show gate returns true for secret `UnitPowerMax` without arithmetic/comparison on the secret value, and the secret values are passed uncompared to StatusBar `SetMinMaxValues`/`SetValue`.
- Tooltip harness passes for FOREVER and RETAIL with secret-value pins, a `UnitPowerMax > 0` mutant fails those pins (red), and the restored helper returns to green.
- Nested `SpecializationInfoDocumentation` and `SharedTraitsDocumentation` blocks are extracted with awk Name-to-close ranges and report full fields verbatim, including TalentInfoQuery groupIndex, isInspect, and tier and TalentInfoResult fields.
- The Forever inspect chain cites `TraitConstantsDocumentation.lua:352` (`INSPECT_TRAIT_CONFIG_ID = -1`) and `Blizzard_ClassTalentsFrame.lua:887` (`SetConfigID(...INSPECT_TRAIT_CONFIG_ID...)`).
