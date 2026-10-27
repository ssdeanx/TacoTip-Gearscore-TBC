# AGENTS.md

start here. the detail lives in the linked files — read them before your first
edit. this file is an index, not a second copy.

## what this repo is

two addons, one repo: **TacoTip** (root, v0.8.8) and **TacoTip Extras**
(`TacoTip_Extras/`, v1.2.3), for five client families (era 11509, tbc
20506, titanforge 38002, forever 16001, retail 120105). the root doubles as
the workshop — `desks/`, `bench/`, `Tools/`, `OLD/` are not shipped.

## read these first

| file | holds |
| :--- | :--- |
| `CAIRN.md` | evidence labels and the precedence ladder — how a claim is judged |
| `workshop.md` | the invariants, the client facts that bite, how to run a lane, the wago.tools recipe, package verification |
| `hands-up.md` | signal types, when to escalate, the problems seen in practice |
| `bench/audits/2026-10-20-inspect-and-guild-line-history.md` | the 0.7.9–0.8.3 inspect-frame and guild-line traps, and what is load-bearing now |
| `bench/audits/2026-10-20-session-retrospective.md` | last release: what went wrong and what now prevents it |

## the short version

- **one lane, one complete task**, and use the four skills every time
  (`@desk-open`, `@desk-journal`, `@bench-read`, `@signal-write`); the desk's
  `done` signal is the hand-off — `workshop.md` → "how to run a lane".
- **client truth**: `/home/sam/wow-ui-source`, read-only and
  `origin/`-qualified; client strings the mirror cannot carry: wago.tools;
  the operator's in-game observation outranks both — `workshop.md` and
  `CAIRN.md`.
- **the invariants** — the era range gate, the gearscore formula, the retail
  bracket, the wire format, the saved-variable shapes, the one-argument
  `CanInspect`, no invented translations — are listed once, in `workshop.md`
  → "the invariants". read them before editing.

## commands

    bash Tests/harness/run_all.sh                   # main, 71 × 3 interpreters
    bash TacoTip_Extras/Tests/harness/run_all.sh    # extras, 42 × 3 interpreters
    luacheck .                                     # 0 warnings / 0 errors
    bash Tools/verify_release.sh --worktree         # tacoTip package, must PASS
    bash Tools/verify_release_extras.sh --worktree  # extras package, must PASS

`--worktree` validates the tree you ship; the default validates a commit you
are probably not shipping.

## do not

- no state-changing git — nothing is staged or committed by design; the two
  verifiers are the only permitted git use.
- no browsing from a lane. no hash-based verification — read the code and run
  the suites.
- no new files unless asked. no locale key without a sourced translation.
- do not edit `gearscore.lua` except to guard an existing call.
- never report "done" with a red tree.
