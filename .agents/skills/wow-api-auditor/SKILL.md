---
name: wow-api-auditor
description: Verifies Blizzard WoW API signatures, generated-documentation entries, presence, secret-value annotations, and combat-restricted aura tooltip passthrough rules across Classic Era, Anniversary, Titan, Forever, and Live clients using read-only origin/<branch> reads of the local FrameXML checkout.
whenToUse: Use when you need to confirm an API's signature, generated-documentation entry, availability, secret annotation, or aura tooltip passthrough behavior differs across WoW client families, or to audit addon code for unsafe secret/combat handling and direct protected-function calls (CanInspect, CheckInteractDistance), without mutating the checkout.
---

# WoW API Auditor Skill

Use this skill whenever you need to verify how a Blizzard API function works, what its signature is, whether it is present or behaves differently across the five supported client families (Classic Era, Anniversary, Titan, Forever, Live), whether it carries secret-value or combat-restriction annotations, or whether addon code safely handles secret/combat aura tooltip text and protected Blizzard functions.

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
    For every hit, record file and line, the call form (`_G.`, local alias, or direct), and the client-family guard or skip. Report a table: file:line, function, client family behavior, guard/skip status. A call is acceptable only when it is either guarded by a client-aware predicate (for example Forever/Retail skip or library guard) or intentionally limited to Classic clients. Do not leave an unguarded direct call on Forever or Retail.

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

## Pitfalls

- **Never run `git checkout`.** It mutates the working tree and invalidates parallel branch reads. Always use `origin/<branch>:path` or `git grep <ref>`.
- **Branch-name drift.** This playbook uses `origin/live`, not `origin/mainline`, and the five named branches only. `origin/classic` is not part of this playbook.
- **Path drift by family.** `Item.lua` lives under `.../Classic/Item.lua` on classic_era/anniversary/titan but `.../Mainline/Item.lua` on forever/live. Verify with `git ls-tree` when unsure; do not assume a single path.
- **`git grep <ref>` syntax.** The ref must precede the `--` pathspec: `git grep -n 'PAT' origin/<branch> -- '*Documentation.lua'`. Reversing them fails or searches the working tree.
- **Generated docs are branch-specific.** A documentation file present on one branch may be absent or differently named on another; cite the path actually returned for that branch.
- **Absence is a result.** Report ABSENT explicitly per branch; never infer presence from another branch. `C_TooltipInfo.GetUnitAura` is absent on the Classic families.
- **Signature blocks are multi-line.** Use `-A20` or more; truncating hides Returns/Arguments and annotation differences.
- **Working tree may sit on classic_era.** Local files reflect only that branch; never treat them as evidence for other branches.
- **Secret text is not comparable.** Expressions such as `text == ""`, `text == nil` only after a type check, `string.lower(text)`, `string.find`, concatenation, logging, or table-key use can crash or taint in combat. Guard with `issecretvalue`/`canaccessvalue` before any operation.
- **pcall is not a substitute for a secret guard.** Use the guard first; use `pcall` as defense in depth around the original string operation.
- **Do not forward transformed secret text.** If a value is secret or inaccessible, pass the original value through unchanged; do not normalize, trim, or annotate it.
- **Protected calls are client-specific.** `CanInspect` and `CheckInteractDistance` restrictions differ between Classic families and Forever/Retail. Do not assume a function safe on one client is safe on another.
- **Do not call protected functions from diagnostics on restricted clients.** On Forever/Retail, report them as protected/not applicable instead of invoking them.
- **Do not weaken foreign-row detection.** The secret guard must short-circuit only secret or inaccessible values; ordinary text must still run the existing detection logic.

## Verification

- `git -C /home/sam/wow-ui-source status --short` is empty (working tree untouched).
- The report covers all five branches with an explicit PRESENT/ABSENT value each.
- Every PRESENT branch cites the exact `Interface/AddOns/...Documentation.lua` path returned by `git grep -l`.
- No `git checkout` (or other state-changing git) command was executed.
- Signatures and annotations applied to code match the generated documentation blocks read from `origin/<branch>:path`.
- `C_TooltipInfo.GetUnitAura` is reported with `SecretWhenUnitAuraRestricted = true` where present, and ABSENT on Classic Era, Anniversary, and Titan.
- Secret aura tooltip text is documented as forward-only: untouched, never compared or string-processed.
- Every direct `CanInspect`/`CheckInteractDistance` call is listed with file:line and a client-aware guard or skip.
- `/tt diag` reports distance on Classic clients and does not invoke `CheckInteractDistance` directly on Forever or Retail.
- No `ADDON_ACTION_BLOCKED` error occurs during `/tt diag`.
- Unsafe tooltip predicates are identified and corrected with an `issecretvalue`/`canaccessvalue` guard plus `pcall` before any string operation, while preserving ordinary-text foreign-row detection.
