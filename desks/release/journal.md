# release — Journal

## 2026-10-14 (2) — Version split resolved; the in-game suite was unloadable; AGENTS.md corrected

- **Done — `OPEN-ITEMS.md` row 3 closed.** The `0.8.4` row existed **in the summary table with no body section at all**; its content described real fixes, so it was folded into `0.8.3` rather than deleted. All six version-bearing files now read `0.8.3`.
- **Done — a live defect, found by an audit of the register itself.** `Tests/TacoTipTests.toc` declared `## Dependencies: TacoTip_Forever` — an addon folder that does not exist — and the suite asserted `_G.TacoTip_Forever` in four places, while the packaged addon is `TacoTip`. **The in-game WoWUnit suite could not load for anyone following the README's own instructions.** Dependency and the four namespace reads corrected to `TacoTip`. This is the coverage mocks cannot provide (Pawn's real chat-write behaviour, frame timing, async model loads, alpha), so it had been unavailable since the suite was written. Logged as row 15, `WATCH` — fixed but **unverified in a live client**.
- **Done — `OPEN-ITEMS.md` row 9 closed, and it was wrong.** The row claimed "no test in either harness exercises a Pawn-present client" and asked for one. `settings_test.lua` mocks `PawnClassicLastUpdatedVersion` / `PawnGetScaleColor` and calls `TT_PAWN:GetScore` twice; `load_test.lua` does the same and asserts `TT_PAWN` loaded rather than returning early. Ten of twenty `settings_test` invocations run Pawn-present. Verified by reading the harnesses, not by trusting the row.
- **Done — `OPEN-ITEMS.md` row 10 closed.** `AGENTS.md`'s structural claims now match the tree: the line-count block and the `TacoTip_Forever/` folder name are gone, the invocation count is 54, four false portrait claims are struck with the code that disproves each, and the `CanInspect(unit, true)` "range gate" it recommended has been reversed. **Every bare `file:line` citation was removed** and replaced with the symbol name — line numbers rot on every commit, and four of the five that were there had already gone stale within the same session.
- **Open (new rows):** row 12 — the workshop (`CAIRN.md`, `desks/`, `bench/`, `memory-bank/`) is **untracked by git**, so two sessions cannot diff or merge it, which undercuts the whole coordination scheme. Row 13 — **three different version-bump lists** exist across this repo. Row 14 — nothing machine-pins TacoTip's own version the way the Extras harness pins Extras', which is the direct cause of row 3 having gone undetected.
- **Next step:** `git add` the workshop and decide whether it ships in the zip (row 1) or is excluded. That is the highest-leverage item here and it is a one-line decision.

## 2026-10-14 — Desk opened

- **Purpose:** own the act of shipping. Which files version together, what the
  `.toc` metadata promises, what the client matrix is, what actually ends up inside
  the zip, and what a mistake costs. `TacoTip` is at ~110k installs and
  `TacoTip_Extras` is a second, separately-installed CurseForge project; every
  release decision has an audience of strangers.
- **Scope:** `.toc` files for both add-ons, version strings across the repo, the
  packaging contents, the `OLD/` copy, `CHANGELOG.md` rows, and the interface-ID
  matrix.
- **Sibling desks:** `tacotip` and `extras` own the code; `api-verification` owns
  the client-API truth; this desk owns how all of it reaches players.

### The version contract (VERIFIED, project rule)

A version bump is one act across several files, never a single edit:

- `TacoTip.toc` (`## Version:`) — what the client shows
- `main.lua` (`addOnVersion`) and `options.lua` — what the options page and
  diagnostics show
- `README.md`, `CHANGELOG.md`, `MEMORY.md`, `AGENTS.md`
- for the companion: `TacoTip_Extras.toc`, its `README.md`, its `CHANGELOG.md`,
  and the pin in `TacoTip_Extras/Tests/harness/load_test.lua`

The harness pins the Extras version, so a missed copy fails the suite rather than
shipping a lie. Nothing equivalent pins TacoTip's own version — that is a gap worth
closing (see `bench/OPEN-ITEMS.md`).

### State at desk opening

- `TacoTip.toc` = **0.8.3**; `CHANGELOG.md` already carries a **0.8.4** row
  describing the Classic Era event-path + range work. That split is deliberate:
  the operator bumps after the in-game pass. Tracked as open item 3.
- `TacoTip_Extras.toc` = **1.2.2** (the rank-colour fix), bumped everywhere.
- Client matrix claimed by both add-ons: `11509` (Classic Era), `20506` (TBC
  Anniversary), `38002` (Titanforge/Wrath), `16001` (WoW Forever), `120100`
  (Retail). `30405` is deprecated and must not come back.
- CurseForge projects: TacoTip `1555962`, TacoTip Extras `1741092`.

### Packaging risk (the important part of this desk)

The add-on root is also the development workshop, so it contains things that must
never ship: `desks/`, `bench/`, `CAIRN.md`, `docs/`, `OLD/`, `Tests/`,
`memory-bank/`, `*.png`, `.github/`, `.omg/`, `.omo/`, `.serena/`. **`OLD/` even
contains a second, stale `TacoTip.toc` and a full copy of the add-on.** A zip built
by globbing the folder would ship two add-ons and a pile of workshop files.

- Closing condition: a release where the shipped zip's own file listing is checked
  and pasted into this journal. Open items 1 and 2.
- Until then: build packages from an explicit file list, never from `zip -r .`.

### Also standing

- `5bc83b7`'s message and its diff disagree (it removed the `OLD/TacoTip_Forever/`
  copies, not the live `pawn.lua` / `textures.lua`). Recorded as open item 4 so a
  future session does not act on the message.
- Commit messages here are written by sessions; treat them as claims, not facts.

### Next step

Wait for the in-game pass, then: bump `TacoTip` to `0.8.4` across the six files,
verify the Extras zip contains only runtime files, and record the zip listing here.
