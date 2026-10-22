# fix-extras-silent-failures — Journal

## 2026-10-20 — Desk opened
- **Purpose:** the TacoTip **Extras** side of the final silent-failure audit
  (2 MEDIUM + 7 LOW findings) of the 1.2.3 tree. Every finding was a path
  where the add-on *looked* like it was working and was not.
- **Scope:** `TacoTip_Extras/RankBrowser.lua`, `TacoTip_Extras/Scanner.lua`,
  `TacoTip_Extras/Options.lua`, `TacoTip_Extras/Core.lua` (only the empty-field
  mode rule named by finding 9 and the `/ttgsdebug` counter line named by
  finding 2), `TacoTip_Extras/Locale/*.lua` (all 11),
  `TacoTip_Extras/CHANGELOG.md`, and the Extras harness
  (`Tests/harness/load_test.lua`, `Tests/harness/rankbrowser_test.lua`).
  **NOT** the main add-on's code — another lane owns the main side. No commit,
  no staging.
- **Baseline measured (not assumed):** Extras harness `TOTAL 42 invocations:
  42 passed, 0 failed` (lua5.1 / lua5.4 / luajit, 14 invocations each);
  `cd TacoTip_Extras && luacheck .` → `Total: 0 warnings / 0 errors in 26
  files`; `bash Tools/verify_release_extras.sh` → `verify_release_extras:
  PASS`; the MAIN add-on's harness → `TOTAL 71 invocations: 71 passed, 0
  failed`.

## 2026-10-20 — DEVIATION: the named audit file does not exist
- The task named `bench/audits/2026-10-20-final-hunter2.md` as the source of
  the findings. **That file is not on disk** — `bench/audits/` holds 22 files
  and none of them is it (`2026-10-20-pre-publish-test-window.md` is the only
  2026-10-20 audit present). The sibling `desks/publish-hunter/` desk carries
  a `.signals/hunter2.json`, so `hunter2` is the RUN ID, not a file.
- The nine findings were therefore taken **verbatim from the task text**,
  which enumerates all of them with file:line citations. Nothing was
  inferred. The desk journal records the line numbers as they stand AFTER
  this lane's edits.

## 2026-10-20 — The nine findings, fixed and pinned

### 1. MEDIUM — the gear panel was never closed with the browser
- `RankBrowser.lua:1286` — `local gearEntry = nil`, the entry the panel is
  currently showing.
- `RankBrowser.lua:1461` — `RankBrowser.CloseGear()` now also clears
  `gearEntry`, so a panel the player dismissed is never resurrected.
- `RankBrowser.lua:2757` — the Escape handler's panel branch goes through
  `CloseGear()` (it used to call `gearFrame:Hide()` directly).
- `RankBrowser.lua:2763` — the Escape handler's BROWSER branch closes the
  panel with it.
- `RankBrowser.lua:2819` — `RankBrowser.Toggle()`'s hide branch calls
  `RankBrowser.CloseGear()` before `f:Hide()`.
- `RankBrowser.lua:2850-2851` — `RankBrowser.RebuildUI()` closes the panel
  BEFORE the frame swap (the panel's parent is about to be discarded).
- `RankBrowser.lua:2866-2870` — after `adoptGearParent()`, the panel is
  re-rendered from LIVE data with `RankBrowser.ShowGear(gearEntryBefore)`,
  so it can never show the rows the discarded frame carried.
- `RankBrowser.lua:1758-1760` — `ShowGear` records the entry it rendered.
- **Why:** `CloseGear` had **zero** callers. The panel is `SetToplevel(true)`,
  so its visibility rested on an engine rule the audit could not verify on the
  supported clients. The panel's fate is now decided by the add-on.

### 2. MEDIUM — a raising scorer was discarded, so the level-70 toggle could silently do nothing
- `Scanner.lua:1230-1256` — `reevaluateErrors` / `lastReevaluateError` and
  `recordReevaluateError(err, announce)`, which counts every failure and
  prints **ONE** line naming it (one line per re-evaluation, not per entry:
  a scorer that raises raises the same way for every cached entry).
- `Scanner.lua:1269-1325` — `Scanner.Reevaluate` now evaluates through ONE
  guarded local (`evaluate`), so both the local scan and every cached remote
  entry go through the same capture; the entry is LEFT ALONE on a raise
  rather than replaced with something that is not a result. The function
  returns **two** values: `replaced, failed`.
- `Scanner.lua:1389-1390` — the two counters are in `Scanner.GetDebugState()`.
- `Core.lua:987-988` — `/ttgsdebug` prints
  `scanner-reevaluate-errors=` / `last-scanner-reevaluate-error=`.
- `Options.lua:1505-1520` — the level-70 checkbox's caller now READS the
  result (`local ok, replaced, failed = pcall(scanner.Reevaluate)`) instead
  of discarding even the boolean, and says so when the re-evaluation failed.
- **Why:** a raise inside `Scoring.Evaluate` left the cached verdict —
  computed under the OLD policy — exactly where it was, while the checkbox
  flipped and the setting was written. `Cache.ReevaluateAll` swallowed the
  raise a second time, so the evaluator handed to it is now the guarded one.

### 3. LOW — the footer's two buttons overlapped by 2 px
- `RankBrowser.lua:2596-2602` — "Top" moved from `-122` to `-126`. It now
  occupies 126..206 measured leftwards from the frame's right edge, "My
  Rank" occupies 34..124, and "Scan now" occupies 222..322. Two 2 px
  gutters, no shared pixels.

### 4. LOW — the tooltip-mode dropdown was hard-coded English in every locale
- `Options.lua:220-231` — `MODE_CHOICES` and `EQUIPMENT_MODE_CHOICES` carry
  the locale KEY beside the English literal.
- `Options.lua:235-259` — `choiceText(choice)` resolves `L[key]` with the
  literal as the fallback; `modeText(choices, value)` resolves a mode VALUE.
- `Options.lua:959`, `:1082` — both dropdowns build their MENU items from
  `choiceText(choice)`.
- `Options.lua:2174`, `:2181` — both dropdowns LABEL themselves with the
  locale's word.
- **Scope note:** the finding's line range (`Options.lua:212-223`) covers
  BOTH mode tables, and the locale keys it cites (`ruRU.lua:29-33`) include
  `MODE_BASIC`, which only the Character & Inspect dropdown uses. Both
  dropdowns are localized; leaving one of them in English would have been a
  half-fix of the same defect.

### 5. LOW — three live UI keys were missing from 10 of the 11 locale files
- **CHECKED FIRST, as instructed:** `HELP_COMFORTABLEROWS_HEADING` and
  `HELP_COMFORTABLEROWS_1` **already exist in all eleven** files (added by
  the `fix-extras-final-review` lane) — nothing to do there.
- `LB_COL_LEVEL` and `LB_STAT_STRIP` were missing from the ten non-enUS
  files and are now present in all eleven, with REAL translations
  (`STUFE`/`NIVEL`/`NIVEAU`/`LIVELLO`/`NÍVEL`/`레벨`/`УР.`/`等级`/`等級`,
  and a translated three-`%d` summary strip in each).
- `Locale/*.lua` — one new key in all eleven files:
  `LB_DB_UNAVAILABLE`, the "the rank database is unavailable" message item 8
  needs. It is a new key rather than a reuse of `LB_EMPTY` because "no
  records yet" is a different statement from "the database is missing".

### 6. LOW — the checkbox hit-rect expansion was measured once, at creation
- `Options.lua:787-822` — `applyCheckboxHitRect(check, label, cap)`: the
  expansion is the label's measured text width, capped at the label's
  column, and the **label's own width is the floor** used when the client
  cannot measure the text at all (a FontString measured before its font is
  loaded measures zero).
- `Options.lua:824-838` — `refreshCheckboxLabel(check)` re-reads the label
  from the locale and re-measures.
- `Options.lua:879`, `:1031` — both checkbox builders use the shared helper.
- `Options.lua:383-385` — `checkboxes` / `equipmentCheckboxes`, the
  checkboxes kept apart from the rest of `controls` (the dropdown, the
  action buttons and the status lines are not checkboxes, and reading
  `optionLabel` off them recorded a widget-method miss in the harness).
- `Options.lua:2160-2166` — `Options.Refresh` re-labels and re-measures every
  checkbox on both pages.
- **Scope note:** the equipment page carried the identical defect
  (`Options.lua:909-922` before this change) and is fixed by the same
  helper.

### 7. LOW — two Options action buttons did nothing, silently
- `Options.lua:1416-1425` — `printOptionsLine(message)`, worded and coloured
  like `Core.lua`'s `recordInitializeFailure`.
- `Options.lua:1614-1624` — "Open Server Leaderboard" now says
  `RankBrowser.Toggle is missing`.
- `Options.lua:1655-1665` — "Scan now" now says `RankBrowser.StartScan is
  missing`.

### 8. LOW — the browser could be shown with no explanation at all
- `RankBrowser.lua:1829-1838` — `publishEmptyState(text)`, ONE helper, so
  the "no database" path and the "no records" path cannot disagree about
  how the state is published.
- `RankBrowser.lua:1843-1850` — `UpdateUI` publishes the empty state
  **before** returning when `RankDB.GetLeaderboard` is missing.
- `RankBrowser.lua:1981-1988` — the existing empty-state block now goes
  through the same helper.

### 9. LOW — unticking every tooltip field lost the mode for good
- **CHOSEN: the FIRST of the two options the finding offered** — force the
  mode only when it was not already "Disabled", and REMEMBER the mode the
  player had so re-ticking a field restores it.
- **Why, and why not the second:** "Disabled" is the add-on's "I render
  nothing and I am not holding the player's GearScore" state. An empty field
  set has to mean the same thing, and the render gate alone does NOT give
  that: with the mode left alone the render gate draws no rows, but the
  add-on would KEEP the player's GearScore — the half of "Disabled" that
  matters. So the mode is still forced; what changed is that the forcing is
  RECOVERABLE, and that it lives in ONE place.
- `Core.lua:109-153` — `applyTooltipFieldModeRule(tooltipSettings)`: with no
  field enabled it remembers the mode and forces "Disabled" (flagged with
  `modeDisabledByEmptyFields`); with a field enabled it restores the
  remembered mode. An EXPLICIT "Disabled" the player chose is never mistaken
  for a forced one and is never overwritten.
- `Core.lua:375-380` — `normalizeSettings` calls the rule (the unconditional
  `mode = "Disabled"` is gone).
- `Core.lua:488-495` — `Core.ApplyTooltipFieldModeRule()` applies it to the
  LIVE settings table, so the Options page and the normalise cannot drift.
- `Options.lua:894-902` — `applyEmptyFieldModeRule()`.
- `Options.lua:905-913` — the field checkbox calls it after writing the
  field.
- `Options.lua:925-940` — `setMode` records the EXPLICIT pick first, so the
  rule remembers the mode the player just chose.
- `Options.lua:635-637` — the local copy of the rule (and the local field
  list it needed) is GONE. Two copies of one rule is how the two drifted.

## 2026-10-20 — Pins added
- `Tests/harness/load_test.lua:8441-8790` — the new
  `-- final silent-failure audit --` section: items 2, 4, 5, 6, 7 and 9.
  It also extends the mock so a dropdown's MENU can be inspected at all:
  `UIDropDownMenu_Initialize` now RECORDS its initializer and
  `UIDropDownMenu_CreateInfo` / `UIDropDownMenu_AddButton` are modelled
  (`load_test.lua:370-381`, `:1121-1140`) — without that, the list behind
  the closed control was unreachable and a menu that translates three of its
  four words would have passed.
- `Tests/harness/rankbrowser_test.lua:3424-3560` — the new section 17:
  items 1 (a and b), 3 and 8. `findGearPanel` was made a RECURSIVE search
  from the UIParent (`rankbrowser_test.lua:1814-1837`), because
  `RebuildUI` discards the browser frame and the panel follows it — a search
  that only looked at the ORIGINAL browser's children would have stopped
  finding the panel after the first rebuild, which is exactly when the
  panel's lifetime matters.

## 2026-10-20 — Revert-to-fail (quoted reds, on COPIES in /tmp/opencode/reverts)
The working tree was **never** reverted: a copy of the tree was made, the
one change was undone in the copy, and the copy's harness was run. Every
item goes red, and the red is quoted.

1. **Item 1** (the `CloseGear` call removed from `Toggle`'s hide branch and
   from `RebuildUI`): `FAIL closing the browser closes the gear panel with it
   [panel shown=true]` / `FAIL the rebuilt panel shows the CURRENT item
   [... item:111222|r ...]` / `FAIL the rebuilt panel does not show stale gear
   [... item:111222|r ...]` — `328 checks, 3 failed`.
2. **Item 2** (the guarded evaluator and the two counters removed from
   `Scanner`, the `/ttgsdebug` line removed from `Core`): `FAIL a raising
   scorer is COUNTED` / `FAIL the counted failure NAMES the failure` /
   `FAIL the caller is told the re-evaluation failed (the result is not
   discarded)` / `FAIL a raising scorer is SURFACED: one line names the
   failure` / `FAIL /ttgsdebug prints the re-evaluation failure counter` —
   `610 checks, 5 FAILED`.
3. **Item 3** (`topButton` put back to `-122`): `FAIL the two footer buttons'
   hit rects do not overlap [top=[122,202] me=[34,124]]` / `FAIL the two
   footer buttons have a gutter between them [top=122 meFar=124]` —
   `328 checks, 2 failed`.
4. **Item 4** (`info.text = choice.text` and the raw `mode` put back):
   `FAIL the tooltip-mode control labels itself in the player's language` /
   `FAIL the tooltip-mode MENU is in the player's language` / `FAIL every
   tooltip-mode menu item is in the player's language` — `610 checks, 3
   FAILED`.
5. **Item 5** (`LB_COL_LEVEL` and `LB_STAT_STRIP` stripped from the ten
   non-enUS files): `FAIL every shipped locale defines the leaderboard level
   column and the summary strip [deDE:LB_COL_LEVEL, deDE:LB_STAT_STRIP, ...,
   zhTW:LB_STAT_STRIP]` / `FAIL the Russian summary strip renders the three
   numbers it is given` — `610 checks, 2 FAILED`.
6. **Item 6** (the refresh-time re-label / re-measure removed):
   `FAIL a refresh re-reads the checkbox label from the locale` / `FAIL the
   hit-rect expansion is RECOMPUTED on refresh (it follows the label)` —
   `610 checks, 2 FAILED`.
7. **Item 7** (the two `printOptionsLine` calls removed): `FAIL a missing
   leaderboard module produces a message naming the missing surface` /
   `FAIL a missing scan module produces a message naming the missing
   surface` — `610 checks, 2 FAILED`.
8. **Item 8** (the empty-state publish put back to a bare `return`):
   `FAIL a missing rank database shows the empty state rather than a bare
   window [shown=false]` / `FAIL the empty state names the missing rank
   database [No players match the current filters.]` — `328 checks, 2
   failed`.
9. **Item 9** (the remember/restore removed and the unconditional
   `mode = "Disabled"` put back): `FAIL re-ticking a field after all were
   unticked restores a usable mode` / `FAIL re-ticking a field restores the
   mode the player had` — `610 checks, 2 FAILED`.

## 2026-10-20 — Validation (all four commands, quoted)
- `bash TacoTip_Extras/Tests/harness/run_all.sh` → **`TOTAL 42 invocations:
  42 passed, 0 failed`** (lua5.1, lua5.4, luajit — 14 invocations each: the
  twelve-client load matrix and the two focused leaderboard runs).
- `cd TacoTip_Extras && luacheck .` → **`Total: 0 warnings / 0 errors in 26
  files`**.
- `bash Tools/verify_release_extras.sh` → **`verify_release_extras: PASS`**.
- `bash Tests/harness/run_all.sh` (the MAIN add-on, untouched by this lane)
  → **`TOTAL 71 invocations: 71 passed, 0 failed`** — green, with the other
  lane's `specname_test.lua` in the tree.

## 2026-10-20 — CHANGELOG
- `TacoTip_Extras/CHANGELOG.md:1028-1121` — a new subsection, "Silent-failure
  audit: nine findings, all fixed", inside the existing `[1.2.3]` section. No
  version bump: the TOC still says `## Version: 1.2.3`, and the `[1.2.2]`
  and earlier sections are untouched.
- `TacoTip_Extras/CHANGELOG.md:7` — the `1.2.3` summary row gained one
  clause naming the nine fixes.

## 2026-10-20 — State
- No commit, no staging. The working tree carries the changes.
- The MAIN add-on's code, the root `CHANGELOG.md`, `Tools/` and `Libs/` were
  NOT touched by this lane.
- Next: the operator's in-game pass (the gear panel's close/rebuild path and
  the localized dropdowns are the two that are only observable on a client).

## 2026-10-20 — [signal:done] Nine silent-failure findings fixed and pinned
- Extras harness 42/42 on lua5.1/lua5.4/luajit; luacheck 0/0 in 26 files;
  `Tools/verify_release_extras.sh` PASS; the MAIN harness 71/71 (green,
  untouched by this lane). Every one of the nine pins was reverted to fail on
  a copy and quoted. No commit, no staging.
