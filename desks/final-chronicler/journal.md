# final-chronicler — Journal

## 2026-10-19 — Desk opened
- **Purpose:** final documentation-truth pass over both add-ons before publish.
  The CurseForge pages and the READMEs are what 112k users read.
- **Scope:** `README.md`, `CHANGELOG.md`, `TacoTip_Extras/README.md`,
  `TacoTip_Extras/CHANGELOG.md`, `Tests/harness/README.md`, this desk
  (`journal.md` + `.signals/`), and `bench/audits/2026-10-19-final-docs.md`.
- **Constraints:** no code, no tests, no TOC, no versions, no bench/ or desk
  writes outside my own desk and that one report. Code is frozen and verified
  by the caller (main harness 70/70, Extras 42/42, luacheck 0/0) — I did not
  re-run anything, so every claim below is file:line evidence, not a
  re-measurement.

## 2026-10-19 — Verification pass (code is truth)
- **The [0.8.4] changelog's line references were systematically stale.** The
  section was written on 2026-10-18 against the tree of that day (see
  `desks/main-publish-docs/journal.md:10-12`, which lists the same coordinates);
  the code has since moved. 61 references corrected. Behavioural claims in the
  same section re-checked and all hold.
- **One false claim found in the Extras [1.2.3] changelog:** "matching `LB_TOP` /
  `LB_MY_RANK_ARROW`, which always spelled them correctly" — the ten translated
  locale files carry `\226\152\160` (U+26A0 ⚠) for `LB_TOP`, not the ▲
  (`\226\150\178`) that `enUS` carries. Corrected in the changelog; the
  underlying code defect is a code change and is out of my lane — it is
  reported in the audit for the operator.
- **Counts:** `batch8_pane_test.lua` runs 26 checks, not 27 (27 `check(` hits,
  one is the definition). `Tests/harness/README.md` said 66 settings; the
  `DEFAULTS` table declares 68. Main `README.md` said 59 harness invocations;
  `run_all.sh` runs 70. Main `README.md` also still pointed at a
  `TacoTip_Forever/` folder and a `luacheck TacoTip_Forever/` command that no
  longer exist.
- **Everything in the two READMEs' player-facing claims held** — the scan
  checkbox, the no-wrong-spec gate, Pawn mid-session, the Hunter per-call
  class read, the power-bar fallback, the options-failure surfacing, the
  tooltip error paths, the diag lines, the 1px name line, the interface band,
  the character/inspect pane refresh, the instant-fade honesty, and on the
  Extras side the rank line, the 17-row `INVTYPE_*` gear panel, the leaderboard
  feature set, the shared scan button and the gear-panel empty state.
- **Left alone on purpose (ambiguous, or an operator's call, not the code's):**
  three player-facing phrasings in the main README ("Fast mouse-outs no longer
  lose the tooltip", "the player-name line is 1px smaller", "how long ago the
  last inspect problem happened") — each has a defensible reading, each is
  flagged in the audit with the exact recommended wording; the Extras README's
  "Not yet released … the CurseForge listing does not exist yet" against its
  own `curseforge_id` / preview links (a publish decision); and the front
  matter's `requires:` list, which names three **bundled** libraries that
  `TacoTip.toc` declares as `OptionalDependencies`.
- **Report:** `bench/audits/2026-10-19-final-docs.md` — every correction with
  before → after and the code evidence, and everything left alone with the
  reason.

## 2026-10-19 — [signal:done] Docs corrected
- `README.md`: tree root `TacoTip_Forever/` → `TacoTip/`; `luacheck
  TacoTip_Forever/` → `luacheck .`; 59 → 70 harness invocations; the
  "What's New in 0.8.4" pointer no longer advertises "file and line" (rule-5
  alignment; the changelog still carries the detail).
- `CHANGELOG.md`: 61 line references re-pointed at the final tree; the
  `batch8_pane_test` check count 27 → 26.
- `TacoTip_Extras/CHANGELOG.md`: the "six call sites" claim scoped to what the
  change converted; four stale file:line references re-pointed; the false
  "always spelled them correctly" claim corrected and the ⚠ defect named; the
  stale "163 at this revision" harness count removed.
- `TacoTip_Extras/README.md`: no factual drift found — left byte-identical.
- `Tests/harness/README.md`: 66 → 68 settings; the `C_Item.GetItemInfoInstant`
  mock-fidelity row brought back in line with the Batch-7 fix.
