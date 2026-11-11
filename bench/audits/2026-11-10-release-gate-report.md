# Release gate run — 2026-11-10 (task t14)

Run by: `gate-runner` (task t14, attempt 1, attempt_id `994da1cd-c300-4e71-b394-38f9c7466e83`)
Run at: 2026-11-10T22:47–22:51-05:00

## Tree under test

- `HEAD` = `bf08e71` (working tree, not a commit). The gates ran on the working tree because
  the audit's corrections live there; both package verifiers were run with `--worktree` for that reason.
- Working-tree deltas present during the run (from `git status --porcelain`):

  ```
   M .wowluarc.json
   M AGENTS.md
   M CHANGELOG.md
   M Libs/LibForeverInspector/LibForeverInspector.lua
   M README.md
   M TacoTip_Extras/CHANGELOG.md
   M TacoTip_Extras/Core.lua
   M TacoTip_Extras/Frames.lua
   M TacoTip_Extras/README.md
   M TacoTip_Extras/RankBrowser.lua
   M TacoTip_Extras/Scanner.lua
   M Tests/harness/run_all.sh
   M gearscore.lua
   M main.lua
   M options.lua
   M pawn.lua
   M workshop.md
  ?? Tests/harness/contract_pins_test.lua
  ?? bench/audits/2026-11-10-api-contract-ledger.md
  ?? bench/audits/2026-11-10-api-contract-review.md
  ```

- The contract changes under audit are in `Libs/LibForeverInspector/LibForeverInspector.lua`,
  `main.lua`, `options.lua`, `gearscore.lua`, `pawn.lua`; `Tests/harness/contract_pins_test.lua`
  and the `Tests/harness/run_all.sh` registration are t13's pins. `TacoTip_Extras` is out of
  scope for the audit but its suite is gate 4.

Tool versions used:

```
Luacheck: 1.2.0 / Lua: PUC-Rio Lua 5.4
Lua 5.1.5  Copyright (C) 1994-2012 Lua.org, PUC-Rio
LuaJIT 2.1.1794214635 -- Copyright (C) 2005-2026 Mike Pall
wowlua_ls: /home/sam/wowlua-ls/target/release/wowlua_ls (reports --version 0.0.0)
```

## Verdict summary

| # | Gate | Command | Literal result | Verdict |
|---|------|---------|----------------|---------|
| 1 | luacheck | `luacheck .` | `Total: 0 warnings / 0 errors in 91 files` (exit 0) | **PASS** |
| 2 | main harness, Lua 5.1 | `bash Tests/harness/run_all.sh` | `TOTAL 75 invocations: 75 passed, 0 failed` (exit 0) | **PASS** |
| 3 | main harness, LuaJIT | `LUA=luajit bash Tests/harness/run_all.sh` | `TOTAL 75 invocations: 75 passed, 0 failed` (exit 0) | **PASS** |
| 4 | Extras harness | `bash TacoTip_Extras/Tests/harness/run_all.sh` | `TOTAL 42 invocations: 42 passed, 0 failed` (exit 0) | **PASS** |
| 5 | main package verifier | `bash Tools/verify_release.sh --worktree` | `verify_release: PASS` (exit 0) | **PASS** |
| 6 | Extras package verifier | `bash Tools/verify_release_extras.sh --worktree` | `verify_release_extras: PASS` (exit 0) | **PASS** |
| 7 | wowlua_ls | `/home/sam/wowlua-ls/target/release/wowlua_ls check .` | `551 warnings`, **0 `error[...]` lines, 0 `secret` lines** (exit 1 on warnings, pre-existing) | **PASS** (0 errors / 0 secret findings) |
| 8 | no silenced diagnostics added | `git diff -U0 -- <5 files> \| grep -E '^\+.*diagnostic disable'` | no output (grep exit 1); two pre-existing LFI suppressions unchanged | **PASS** |

All eight gates pass. The tree is publishable under the gate definitions of task t14:
warnings-only exit 1 from `wowlua_ls` is the pre-existing baseline (551 warnings), and
gate 7's criterion is 0 errors and 0 secret-value findings, which is what it produced.

## Gate 1 — `luacheck .`

Command: `luacheck .` — exit **0**.

Literal output (tail; all 91 checked files printed `OK`, including the new pin file):

```
Checking Tests/harness/contract_pins_test.lua     OK
...
Checking textures.lua                             OK

Total: 0 warnings / 0 errors in 91 files
```

91 `OK` lines = 91 files checked, one of them `Tests/harness/contract_pins_test.lua`.
PASS: 0 warnings / 0 errors.

## Gate 2 — main harness, default interpreter (Lua 5.1.5)

Command: `bash Tests/harness/run_all.sh` — exit **0**.

Literal output (head and tail; 75 `ok` lines, 0 `FAIL` lines):

```
== client detection ==
  ok    detect_test
...
  ok    contract_pins_test
...
  ok    talent_check TITANFORGE

-------------------------------------------------------------
TOTAL 75 invocations: 75 passed, 0 failed
-------------------------------------------------------------
```

PASS: 75/75, 0 failed. (`contract_pins_test` is the new t13 harness and it ran here — the
suite was 74 invocations before t13, 75 now.)

## Gate 3 — main harness, LuaJIT

Command: `LUA=luajit bash Tests/harness/run_all.sh` — exit **0**.

Literal output (tail; 75 `ok` lines, 0 `FAIL` lines):

```
  ok    talent_check TITANFORGE

-------------------------------------------------------------
TOTAL 75 invocations: 75 passed, 0 failed
-------------------------------------------------------------
```

Interpreter actually selected by the script: `luajit -v` → `LuaJIT 2.1.1794214635`.
`contract_pins_test` also `ok` here (line 84 of the captured log).
PASS: 75/75, 0 failed under LuaJIT.

## Gate 4 — Extras harness

Command: `bash TacoTip_Extras/Tests/harness/run_all.sh` — exit **0**.

Literal output (head and tail; 42 `ok` lines, 0 `FAIL` lines):

```
== lua5.1 (Lua 5.1.5  Copyright (C) 1994-2012 Lua.org, PUC-Rio) ==
  ok    classic_era ok
...
  ok    leaderboard behaviour (retail)

-------------------------------------------------------------
TOTAL 42 invocations: 42 passed, 0 failed
-------------------------------------------------------------
```

PASS: 42/42, no regression. Extras' own modified files (Core/Frames/RankBrowser/Scanner) are
included in this run, so the pre-existing Extras secret-handling state is green in the harness.

## Gate 5 — `Tools/verify_release.sh --worktree`

Command: `bash Tools/verify_release.sh --worktree` — exit **0**.

Literal output (archive list elided between markers; all check lines quoted):

```
TacoTip release archive — 28 files from the working tree
...
PASS  single .toc: TacoTip.toc
PASS  no workshop directories (desks/ bench/ docs/ Tests/ OLD/ TacoTip_Extras/ Tools/)
PASS  no workshop documents (hands-up.md workshop.md)
PASS  runtime files only (root *.lua, Locale/*.lua, Libs/*, TacoTip.toc, tt.tga, README/CHANGELOG/LICENSE/THIRD_PARTY_NOTICES)
PASS  version 1.0.0 is consistent (TOC, main.lua, options.lua, README)
PASS  TOC advertises all five interfaces (11509, 20506, 38002, 16001, 120105)
PASS  SavedVariables declares TacoTipConfig
PASS  icon target exists (logo.tga)

verify_release: PASS
```

PASS: every check line PASS, final line `verify_release: PASS`.

## Gate 6 — `Tools/verify_release_extras.sh --worktree`

Command: `bash Tools/verify_release_extras.sh --worktree` — exit **0**.

Literal output (archive list elided; all check lines quoted):

```
TacoTip Extras release archive — 29 files from the working tree
  (attributes read from the working tree)
...
PASS  single .toc: TacoTip_Extras.toc
PASS  all 23 TOC-listed runtime files are present
PASS  no .lua outside the TOC's runtime list
PASS  all 11 Locale/*.lua files are present
PASS  TOC's ## IconTexture target is present (tt-2.tga)
PASS  README/CHANGELOG/LICENSE/THIRD_PARTY_NOTICES and the TOC are all present
PASS  no non-runtime files in the package
PASS  no Tests/, .luacheckrc, .gitattributes or PNG in the package
PASS  TacoTip_Extras/.gitattributes declares every non-runtime rule

verify_release_extras: PASS
```

PASS: every check line PASS, final line `verify_release_extras: PASS`.

## Gate 7 — `wowlua_ls check .`

Command (the short name does not resolve in this shell — `which wowlua_ls` → no output; the
absolute binary the task permits was used):

```
/home/sam/wowlua-ls/target/release/wowlua_ls check .
```

Exit code **1** — expected and documented in the task: the tool exits 1 on ANY diagnostic and
the pre-work tree already had 551 warnings. The gate criterion is 0 errors and 0
secret-value findings.

Literal output (summary block, quoted verbatim):

```
Checked 42 files (53,700 lines) in 0.5s (4 library files skipped)

  Functions:     2,349 (1,594 annotated)
  Classes:       1
  Type coverage: 70.1% of symbols resolved

  551 warnings (1 hints hidden, use --severity hint)
```

Derived counts from the same captured output (checked mechanically, not eyeballed):

```
$ grep -oE '(error|warning|hint|info)\[' output | sort | uniq -c
    551 warning[

$ grep -ic 'error'  output   -> 0
$ grep -ic 'secret' output   -> 0

diagnostic-code histogram:
    252 [need-check-nil]
    211 [undefined-global]
     57 [undefined-field]
      8 [unbalanced-assignments]
       7 [type-mismatch]
       6 [create-global]
       5 [redundant-parameter]
       5 [cannot-call]
```

- **0 errors.** No `error[...]` line exists, and the tool prints a separate `N errors` summary
  line when errors exist — a control against a throwaway directory with a syntax error produced
  exactly that shape (`syntax.lua:2:1: error[syntax] expected ')'` … `3 errors`). The absence
  of both here is therefore meaningful, not an artifact of the summary only counting warnings.
- **0 secret-value findings.** Two independent reasons:
  1. no line in the output contains `secret` (a secret diagnostic would read e.g.
     `warning[secret-comparison]` or `error[secret-argument]`);
  2. `.wowluarc.json` in this tree escalates the six secret diagnostics to `error` severity
     (`secret-arithmetic`, `secret-comparison`, `secret-condition`, `secret-table-key`,
     `secret-access`, `secret-argument`), so the observed `0 errors` already implies
     `0 secret-*` findings.
- The warning count is unchanged from the pre-work baseline recorded in t11's note
  ("551 pre-existing warnings … 0 errors, 0 secret-* diagnostics"): this audit introduced no
  new `wowlua_ls` diagnostic. `Tests/` is in the tool's `ignore` list, so the new pin file is
  covered by luacheck (gate 1), not by this gate.

PASS: 0 errors, 0 secret-value findings.

## Gate 8 — no diagnostics silenced by this work

Command (verbatim from the task):

```
git diff -U0 -- main.lua options.lua gearscore.lua pawn.lua Libs/LibForeverInspector/LibForeverInspector.lua \
  | grep -E '^\+.*diagnostic disable'
```

Literal output: **empty**; grep exit status **1** (no match). No added line in the audit's diff
contains `diagnostic disable`.

Controls from the same tree:

```
$ git show HEAD:Libs/LibForeverInspector/LibForeverInspector.lua | grep -n 'diagnostic disable'
3222:    ---@diagnostic disable-next-line: redundant-parameter
4575:---@diagnostic disable: redundant-parameter

$ grep -rn 'diagnostic disable' main.lua gearscore.lua pawn.lua options.lua textures.lua Libs/LibForeverInspector/
Libs/LibForeverInspector/LibForeverInspector.lua:3224:    ---@diagnostic disable-next-line: redundant-parameter
Libs/LibForeverInspector/LibForeverInspector.lua:4591:---@diagnostic disable: redundant-parameter
```

The two remaining suppressions are the pre-existing LFI `redundant-parameter` directives the
task calls out (HEAD lines 3222/4575; the working-tree line numbers differ only because of
earlier edits in that file). They are unchanged by this audit: they do not appear as added
lines, and that is exactly what the diff test checks. Per-file counts in the working tree:
`main.lua 0`, `gearscore.lua 0`, `pawn.lua 0`, `options.lua 0`, `textures.lua 0`, and the new
`Tests/harness/contract_pins_test.lua 0`.

PASS: this work added no `diagnostic disable`.

## Scope / hygiene

- Only this report file was written by this task (under `bench/audits/`).
- No source file was edited; no state-changing git command was run. `git status` after the run
  is identical to the tree description above (the two verifiers are the permitted git use and
  left no artifacts in the tree).
- Raw command output was captured during the run into a scratch directory outside the repo
  (`/tmp/gates-t14/`); the literal lines needed for this report are quoted above.

## Bottom line

**All 8 gates PASS on `HEAD=bf08e71` + working tree as of 2026-11-10 22:51 -05:00.**
The only non-zero exit in the set is `wowlua_ls`'s exit 1, caused solely by the 551 pre-existing
warnings; its criterion (0 errors, 0 secret-value findings) is met, and the `--worktree`
package verifiers both end in `PASS`.
