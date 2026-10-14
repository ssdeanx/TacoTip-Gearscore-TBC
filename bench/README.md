# the bench

The shared workspace. Findings live here so the next session — or the next desk —
does not have to rediscover them. Nothing on the bench is shipped to players; it
exists so that decisions leave a trail.

Read [`CAIRN.md`](../CAIRN.md) first, then whatever the desk journal points at.

## what lives here

| path | what |
|---|---|
| `audits/` | dated, evidence-linked deep dives. One file per subject; a new audit supersedes an old one instead of quietly editing it |
| `OPEN-ITEMS.md` | the living register of unresolved risk — owner desk + closing condition per item |
| `templates/` | the shells a new artifact starts from |

Once a finding becomes *code or a rule*, it moves out of the bench: the fix goes
into the repo, the durable rule goes into `AGENTS.md`, the narrative goes into
`memory-bank/` + `CHANGELOG.md`, and the bench entry becomes a pointer.

## the status vocabulary

Write down which one you mean, every time:

- **VERIFIED** — reproduced in this workshop, and the artifact says how
  (command run, `file:line`, harness counts, the client and the screen you saw it
  on).
- **ASSUMED** — believed, not yet reproduced, plus what would falsify it.
- **UNKNOWN** — not known. Say so instead of guessing: an honest gap is far
  cheaper than a wrong fact baked into code, tests, or the changelog.

Blizzard behaviour is only **VERIFIED** against `/home/sam/wow-ui-source`, with
branch + path + line. Never against memory, a forum post, or a generated summary.

## labels

Every artifact opens with:

    subject · date · author (desk) · commit the claims are anchored to · status

Line numbers drift. Anchor claims to the commit (`git rev-parse --short HEAD`)
and re-measure counts (`wc -l`, `grep -c`) rather than trusting a number copied
from a document written earlier.

## how to add something

1. Start from `templates/` — or copy the shape of the closest audit.
2. Name it `YYYY-MM-DD-<subject>.md`.
3. Put evidence against every claim, and keep an explicit `Unknowns` section.
4. Link it from the desk journal that produced it, and from a row in
   `OPEN-ITEMS.md` if anything is left open.
5. If it contradicts an older artifact, say which one it supersedes. Do not
   silently edit the old one — the contradiction itself is information.

## da bench index

- [`audits/2026-10-14-main-addon-architecture.md`](audits/2026-10-14-main-addon-architecture.md)
  — how TacoTip itself works end to end: load order, module contracts, tooltip
  pipeline, gates, verification map, unknowns.
- [`audits/2026-10-14-extras-companion.md`](audits/2026-10-14-extras-companion.md)
  — how `TacoTip_Extras` installs *beside* TacoTip: the adapter boundary, the
  capability contract, and what it does when the other half is missing or old.
- [`audits/2026-10-14-wow-ui-source-api-verification.md`](audits/2026-10-14-wow-ui-source-api-verification.md)
  — how to settle any Blizzard API question against the FrameXML mirror, worked
  examples included.
- [`OPEN-ITEMS.md`](OPEN-ITEMS.md) — what is still unresolved.
