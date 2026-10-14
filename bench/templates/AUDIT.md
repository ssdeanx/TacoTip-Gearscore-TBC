# <subject> — audit

- **subject:** <what this covers>
- **date:** YYYY-MM-DD
- **author:** <desk>
- **anchored to:** `<short sha>` — and state whether the working tree was dirty
- **status:** per section (`VERIFIED` / `ASSUMED` / `UNKNOWN`) — never one blanket
  label across a whole document
- **supersedes:** <path, or "nothing">

## why this exists

<the question this answers, in one or two sentences. If it answers nothing, it is
not an audit>

## scope

<in scope — and deliberately out of scope. The second list is what keeps the
document honest>

## the system

<how it actually works. Every claim carries a `file:line` reference, tied to the
commit named above>

## gates & invariants

<the rules holding the system together and what breaks when one is violated. Each
rule needs evidence that it is real: a harness case, a reproduction, or a
Blizzard call site>

## verification map

<which harness invocation, test, or in-game check covers which claim. Where a
claim has no cover, say so and move it to unknowns>

## unknowns

<every `ASSUMED` and `UNKNOWN`, each with what would resolve or falsify it>

## how to keep this honest

<the exact commands a future session should re-run to confirm this document still
describes the code: `wc -l`, `grep -c`, both `run_all.sh` invocations, and any
reproduction used above>
