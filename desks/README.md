# desks

One desk per workstream. A desk is a peer, not a sub-agent: it owns a slice of the
work, keeps its own memory, and may disagree — with another desk or with the
operator — as long as it brings evidence.

## the standing desks

| desk | focus | journal |
|---|---|---|
| `tacotip` | the core add-on: inspect pipeline, GearScore/iLvl, tooltip rendering, options, localization, media | [`tacotip/journal.md`](tacotip/journal.md) |
| `extras` | `TacoTip_Extras` as a separate installable: the adapter boundary, rank DB + P2P sync, leaderboard, gear panel, its own options | [`extras/journal.md`](extras/journal.md) |
| `api-verification` | Blizzard API truth: what actually exists and how it behaves on each client family, evidenced from `/home/sam/wow-ui-source` | [`api-verification/journal.md`](api-verification/journal.md) |
| `release` | versioning, packaging, `.toc` metadata, the client matrix, and the blast radius of ~110k installs | [`release/journal.md`](release/journal.md) |

## the shape of a desk

    desks/<name>/
      journal.md     # the memory of the desk — read first, written last
      .signals/      # machine-readable status

A desk is created, never overwritten. If `desks/<name>/journal.md` already
exists, the desk is **live**: sit at it — read the journal and continue — instead
of opening a second one. A genuine fresh start needs a new name or an archive.

## the journal

Newest entry **at the top**. Append-only: never rewrite an older entry. A
correction is a *new* entry that says what it supersedes, and why.

```markdown
## <YYYY-MM-DD> — <what happened>

- **Done:** what changed, or what was learned.
- **Evidence:** the command output, `file:line`, harness counts, the client you
  saw it on. Label claims VERIFIED / ASSUMED / UNKNOWN, per `CAIRN.md`.
- **Open:** what is unfinished, and which `bench/OPEN-ITEMS.md` row tracks it.
- **Next step:** the first thing the next session should do.
```

Write enough that someone starting from zero finds the way: the desks opened on
2026-10-14 seeded their journals with the current state, the exact in-game
checklist, and the invariants that already cost a session.

## sitting down, standing up

- **Sit:** read `journal.md` (newest entry first), then `../CAIRN.md`, then
  whatever the journal points at on the bench.
- **Work:** change as little as the job needs. Something outside scope? Write it
  into `bench/OPEN-ITEMS.md` and move on — do not chase it.
- **Stand up:** write the journal entry *before* the session ends, including a
  session that produced nothing but a dead end. A dead end is a finding.

## signals

`.signals/*.json` is the machine-readable half of the journal — `hands-up`,
`blocked`, `done`, `checkpoint`. Emit them with the workshop's `signal-write`
skill so the shape stays consistent. A signal with no journal entry behind it is
noise.

## boundaries

- Need something in another desk's area? Leave a note in *their* journal; do not
  edit their files from your desk.
- Overlapping claims are a hands-up, not a race.
- One desk, one focus. A second focus is a second desk.
