# cairn

the trail markers that say: someone was here, and they were honest.

Read this before touching anything in this workshop. It is the operating
disposition, not a style guide.

## the workshop

| path | what it is |
|---|---|
| `AGENTS.md` | the entry point. an agent reads this before anything else; it holds the invariants and the traps that are not derivable from the code |
| `CAIRN.md` | this file — disposition, map, and the rules of evidence |
| `desks/` | one desk per workstream; each owns a `journal.md`, which is its memory. Start at `desks/README.md` |
| `bench/` | the shared workspace: audits, open items, one template. Start at `bench/README.md` |
| repo root | the shipped addon itself — `TacoTip.toc`, `main.lua`, `gearscore.lua`, `pawn.lua`, `textures.lua`, `options.lua`, `Locale/`, `Libs/` |
| `TacoTip_Extras/` | the companion addon: separate install, separate SavedVariables, hard-depends on TacoTip |
| `Tests/harness/` · `TacoTip_Extras/Tests/harness/` | the offline harnesses — the real addon files against a mocked client |
| `memory-bank/` | legacy long-running context. **not part of the read path** — see below |
| `/home/sam/wow-ui-source` | the Blizzard FrameXML mirror. The only acceptable source for API claims |

### named here but does not exist (do not chase)

- `memory-bank/memory-bank-instructions.md` (missing) and the stale
  `copilot-rules.md` / `productContext.md` / `projectBrief.md` from 2026-07.
- `desks/*/.signals/` — empty. `desks/README.md` describes a `signal-write`
  skill that also does not exist.
- `memory-bank/archive/` — named in `OPEN-ITEMS.md`, absent.
- `bench/templates/` — only `AUDIT.md`; no journal/open-item templates.

### memory-bank is not a read path

referenced by `.github/copilot-instructions.md`, which points at an instructions
file that was never created; the head is current, the tail is 0.4.8-era. treat it
as archive. use `CHANGELOG.md` and `bench/OPEN-ITEMS.md` instead.

## evidence or it didn't happen

Every claim carries one of three words, and you write down which one:

- **VERIFIED** — reproduced here, and the artifact says how: the command, the
  `file:line`, the harness counts, the client and the screen you saw it on.
- **ASSUMED** — believed but not reproduced; say what would falsify it.
- **UNKNOWN** — not known. Write the gap down. A guess that reaches a changelog
  line is worse than an admitted gap.

Blizzard API behaviour is only VERIFIED against `/home/sam/wow-ui-source`, with
branch + path + line — see
`bench/audits/2026-10-14-wow-ui-source-api-verification.md`.

**A commit message is not evidence.** `5bc83b7` says it deleted `pawn.lua`,
`textures.lua`, `tt.png` and `tt.tga`; the diff deleted the
`OLD/TacoTip_Forever/` *copies*, and every one of those files is still present
and still loaded by `TacoTip.toc`. Read the diff, not the summary.

**A green harness is not the game.** It proves the mocked contracts hold. Every
user-visible change also carries an in-game checklist on its desk, and the desk
does not call the work done until that comes back.

## the verification loop

    bash Tests/harness/run_all.sh                  # TacoTip, five clients
    bash TacoTip_Extras/Tests/harness/run_all.sh   # Extras, lua5.1/5.4/luajit
    luacheck <the files you touched>

**read the invocation counts from that output. do not write them down here** —
they have already gone stale twice in this repo, and a count in prose is a number
nobody re-checks.

New behaviour lands with a test that FAILS on the old code. Mutation is the
proof: revert the fix, watch the assertion go red, restore it. Every fix from
2026-10-14 was proven that way, including the `OnEvent` nil call, the Classic
range pre-filter, and the Classic portrait teardown — that last one turned red on
exactly the three Classic clients and stayed green on the modern pair, which is
what proved it was Classic-specific rather than merely suspected to be.

**also prove the test can fail for the right reason.** Three probes in this repo
passed *with the fix deleted*, because a mock answered the same way to both the
old and the new call. A revert that stays green means the test is not measuring
what it claims.

## when two sources disagree

1. the game (in-game behaviour, on the client in question)
2. `/home/sam/wow-ui-source` — Blizzard's own code
3. the code in this repo
4. the harnesses — they encode the contracts
5. `CHANGELOG.md`, `memory-bank/`, this file
6. anything a session said in chat

If a decision needs a rung below the third one, that is a hands-up.

## how a desk stands

- **stop is a valid finish.** don't force a result when the evidence
  says stop. "this doesn't work" is a finding, not a failure.
- **"done" means it holds.** if you'd bet your desk on it, ship it.
  if not, say what's uncertain and why.
- **hold scope.** touch only what the task needs. if you find something
  outside scope, note it and move on — don't chase it.
- **never go silent, never bluff.** partial + honest > complete + wrong.
  if you're stuck, say so. if you're unsure, say that too.
- **equal standing.** you can say "that's the wrong question." you can
  disagree with another desk. you answer to evidence, not hierarchy.

## the bench

the shared workspace. leave your work where others can find it. label it —
subject, date, desk, the commit your claims are anchored to, and a status per
section. if it supersedes earlier work, say so rather than editing it.

## hands-up

when two desks disagree and can't settle it against external facts,
that's a hands-up. it goes to the operator. this is the system
working, not failing.

## standing risk

`TacoTip` ships to roughly 110k installs; `TacoTip_Extras` is a separate install
with its own CurseForge project. A change that is merely "probably fine" is not
fine here — the blast radius is other people's game sessions. The live register
of what is unresolved is `bench/OPEN-ITEMS.md`.

**this workshop is untracked by git.** `CAIRN.md`, `desks/` and `bench/` are all
uncommitted. every rule in this file about desks coordinating, bench artifacts
being reviewable, and history being preserved assumes git can see them, and
right now it cannot. two sessions working at once cannot diff or merge any of it.

**`OLD/` is a second, stale copy of the addon** with its own `.toc` at a lower
version. anything that globs the repo for `.lua` or `.toc` can package it, or a
client can pick up its manifest. see `OPEN-ITEMS.md`.
