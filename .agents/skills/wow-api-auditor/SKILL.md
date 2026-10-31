---
name: wow-api-auditor
description: Verifies Blizzard WoW API signatures, documentation entries, and presence across Classic Era, Anniversary, Titan, Forever, and Live clients using read-only origin/<branch> reads of the local FrameXML checkout.
whenToUse: Use when you need to confirm an API's signature, generated-documentation entry, or availability differs across WoW client families without mutating the checkout.
---

# WoW API Auditor Skill

Use this skill whenever you need to verify how a Blizzard API function works, what its signature is, or whether it is present or behaves differently across the five supported client families (Classic Era, Anniversary, Titan, Forever, Live).

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

3. **Verify presence/absence across all five branches.** For an API name `API_NAME`, run a presence check against generated documentation on every branch:
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

## Pitfalls

- **Never run `git checkout`.** It mutates the working tree and invalidates parallel branch reads. Always use `origin/<branch>:path` or `git grep <ref>`.
- **Branch-name drift.** This playbook uses `origin/live`, not `origin/mainline`, and the five named branches only. `origin/classic` is not part of this playbook.
- **Path drift by family.** `Item.lua` lives under `.../Classic/Item.lua` on classic_era/anniversary/titan but `.../Mainline/Item.lua` on forever/live. Verify with `git ls-tree` when unsure; do not assume a single path.
- **`git grep <ref>` syntax.** The ref must precede the `--` pathspec: `git grep -n 'PAT' origin/<branch> -- '*Documentation.lua'`. Reversing them fails or searches the working tree.
- **Generated docs are branch-specific.** A documentation file present on one branch may be absent or differently named on another; cite the path actually returned for that branch.
- **Absence is a result.** Report ABSENT explicitly per branch; never infer presence from another branch.
- **Signature blocks are multi-line.** Use `-A20` or more; truncating hides Returns/Arguments differences.
- **Working tree may sit on classic_era.** Local files reflect only that branch; never treat them as evidence for other branches.

## Verification

- `git -C /home/sam/wow-ui-source status --short` is empty (working tree untouched).
- The report covers all five branches with an explicit PRESENT/ABSENT value each.
- Every PRESENT branch cites the exact `Interface/AddOns/...Documentation.lua` path returned by `git grep -l`.
- No `git checkout` (or other state-changing git) command was executed.
- Signatures applied to code match the generated documentation blocks read from `origin/<branch>:path`.
