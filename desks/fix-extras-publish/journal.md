# fix-extras-publish — Journal

## 2026-10-19 — Desk opened
- **Purpose:** Fix the publish-blocking findings the final arbiter review raised on
  **TacoTip Extras v1.2.3** (the companion add-on), plus the three cheap security
  hardenings from the paladin review. Publish-bound, five clients.
- **Scope:** `TacoTip_Extras/` ONLY (code, tests, README, CHANGELOG) plus the one
  shared bundled library file explicitly assigned by the parent task
  (`Libs/LibForeverInspector/LibForeverInspector.lua`, item 6).
  **NOT** the main add-on's code, README, CHANGELOG, `.gitattributes` or `Tools/`
  — another lane owns those. Item 7 (main-side config sanitizer allowlist) is
  explicitly out of scope and was NOT implemented.
- **Baseline measured (not assumed):**
  - `bash TacoTip_Extras/Tests/harness/run_all.sh` → `TOTAL 42 invocations: 42 passed, 0 failed`
    (lua5.1 / lua5.4 / luajit, 14 invocations each).
  - `cd TacoTip_Extras && luacheck .` → `Total: 0 warnings / 0 errors in 26 files`.
- **Note:** the parent task referenced `bench/audits/2026-10-19-final-arbiter-audit.md`,
  which does NOT exist in this tree. The available arbiter-era artifacts are
  `bench/audits/2026-10-19-publish-readiness-hunter.md` and `desks/publish-hunter`;
  the item list in the task itself is the authoritative spec.

## 2026-10-19 — Items 1-6 + 8 implemented, pinned, revert-proven
- **Worked on:** all six assigned fixes plus the CHANGELOG/README work. Every fix
  is pinned in the EXISTING harness files (no new harness file, no new invocation
  pattern, the 42-invocation count is unchanged) and every pin was reverted to
  fail and restored to pass.
- **Per item (file:lines):**
  1. Level-70 gate is the user's setting — `Scoring.lua:687-737` (nil policy is an
     explicit failure), `Scoring.lua:753-772` (the result records its policy),
     `Core.lua:377-406` (`Core.GetEnhancementPolicy`), `Scanner.lua:50-73` + `:801`
     + `:994` (both call sites pass the policy), `Scanner.lua:1150-1192`
     (`Scanner.Reevaluate`), `Cache.lua:299-337` (`Cache.ReevaluateAll`),
     `Options.lua:1199-1222` (the checkbox re-evaluates), `Tooltips.lua:430-457`
     (the render gate reads the same accessor).
  2. Recovery journal — `TacoTipAdapter.lua:97` (schema), `:1641-1669` (the
     one-shot chat notice + `noteConflict`), `:1671-1706` (the stable identity),
     `:1708-1773` (the restorative recovery), `:1844-1866` (the
     `conflictLocked` reset when the configuration is re-read).
  3. Gear insert-time cap — `RankDB.lua:766-802` (the amortized count + heap),
     `:985-1060` (the eviction), `:1002` (the cap test). The prune path now
     forgets the bookkeeping (`RankDB.lua:1010-1024`).
  4. Inbound flood door — `RankSync.lua:755-790` (the window),
     `:1292` + `:1335` (the two call sites), `:1362-1363` (the published
     limits), `Core.lua` (the counter is printed by `/ttgsdebug`).
  5. Markup sanitisation — `RankDB.lua:254-272` (`sanitizeDisplayString`),
     applied to the name, guild, class and spec name. The wire format is
     unchanged.
  6. Inspector alias — `Libs/LibForeverInspector/LibForeverInspector.lua:18-48`:
     the alias is claimed only when the name is free, or when the entry already
     there is the same library.
- **Revert-to-fail evidence (quoted red, then restored green):** every item above
  was reverted one at a time; see the final message for the quoted failures.
- **Current state:** `bash TacoTip_Extras/Tests/harness/run_all.sh` → 42/42 on
  lua5.1/lua5.4/luajit; `cd TacoTip_Extras && luacheck .` → 0 warnings / 0 errors
  in 26 files; the MAIN add-on's own harness (which loads the bundled inspector)
  → 70/70; `bash Tools/verify_release_extras.sh` → PASS.
- **Next step:** the operator to decide on the out-of-scope defect below.

## 2026-10-19 — OUT OF SCOPE: the socket capacity is always 0 (found, not fixed)
- **Worked on:** traced why the three enhancement metrics still cannot appear on
  Retail and WoW Forever even with the level-70 rule off.
- **Finding:** `Scanner.lua:25` declares `SOCKET_PREFIX = "EMPTY_SOCKET_"` (WITH a
  trailing underscore) and `readSocketCapacity` (`Scanner.lua:435-476`) counts the
  stat-table keys that start with that prefix. The client publishes
  `EMPTY_SOCKET1` / `EMPTY_SOCKET2` / `EMPTY_SOCKET3` (no underscore before the
  digit — the harness's own mock uses exactly those names, `load_test.lua:1028-1030`),
  so NO key ever matches: the capacity is always 0, the socket cell is
  `{capacity = 0, gemIDs = {}}`, and Scoring's socket cross-check
  (`Scoring.lua:538`) then reports `socket-gem-mismatch-1` — a CONTRADICTORY
  status. The potential/delta/completion metrics are therefore blocked on the two
  clients that have `GetItemStats`, whatever the level-70 setting says.
- **Why it was NOT fixed here:** it is not one of the six assigned findings, it
  changes the published Potential GS / Delta / Completion numbers on two
  clients, and the correct capacity rule (how many sockets the item HAS vs how
  many are EMPTY) needs evidence from a live client that the FrameXML mirror
  cannot give (the API is engine-side and the generated docs do not list the
  stat-table fields). Fixing it on a guess would change user-visible numbers.
- **Next step:** operator decision — assign it, or accept the Classic/Retail
  degrade as documented.
- **Also noted:** the pinned harness comment at `load_test.lua:5856-5857` records
  this, so the next reader does not have to rediscover it.

## 2026-10-19 — Revert matrix re-run end to end, tree restored, final validation
- **Worked on:** re-ran all nine revert probes in one scripted pass (each: apply
  the revert → capture the red → restore → capture the green), then re-ran the
  whole validation set on the restored tree.
- **Red counts captured:** 1a nil policy → 3 red; 1b no policy at the scanner →
  3 red; 1c no re-evaluation → 5 red; 2a fingerprint as a lock → 3 red; 2b the
  user's change overwritten → 3 red; 3 no insert-time gear cap → 3 red; 4 no
  inbound door → 3 red; 5 no markup sanitisation → 7 red; 6 the alias taken by
  force → 2 red. Every green restored to `0 failed`.
- **Incident (and its fix):** the first pass of the matrix was piped into
  `head`, and the script was killed by SIGPIPE mid-way — leaving the
  item-6 revert applied in the tree, and (on the next run) re-backing up that
  dirty state. Caught by the final validation, repaired by re-applying the
  alias guard, and re-proven: the tree now passes 42/42, luacheck 0/0, the main
  harness 70/70 and the release verifier PASS. **Lesson: never pipe a mutating
  script into `head`** — it truncates the run, not the output.
- **Current state:** final validation on the restored tree —
  `bash TacoTip_Extras/Tests/harness/run_all.sh` → **42 invocations: 42 passed,
  0 failed** on lua5.1 / lua5.4 / luajit; `cd TacoTip_Extras && luacheck .` →
  **0 warnings / 0 errors in 26 files**; `bash Tests/harness/run_all.sh` (the
  MAIN add-on, which loads the bundled inspector) → **70 invocations: 70
  passed, 0 failed**; `bash Tools/verify_release_extras.sh` → **PASS**.
- **Next step:** the operator to decide on the out-of-scope socket-capacity
  defect recorded above.
