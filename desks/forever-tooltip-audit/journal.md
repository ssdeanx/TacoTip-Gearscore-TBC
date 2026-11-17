# forever-tooltip-audit — Journal

## 2026-11-05 — Desk opened: WoW Forever unit-tooltip regression

- **Purpose:** read-only root-cause audit of the WoW Forever (16001) unit tooltip after GearScore/item data becomes cached: the layout switches to the 5th style option (MINI) instead of the default COMPACT/FULL (2), the Pawn line disappears after item data returns, and a Talents line renders on Forever where it must be gated off.
- **Scope:** TacoTip root add-on only. `TacoTip_Extras` is a separate add-on and out of scope. Other client families must not be affected. No add-on code edits until the operator approves.
- **Operator evidence:** `forever1.png` = WoW Forever, broken. `1.png` = Classic Anniversary, working reference. The change happens after item data returns. Style is on the 5th option; COMPACT/FULL is the default; selecting FULL does not change the rendered result. No other add-ons are involved; the client has no native GearScore/iLvl display.
- **Lanes dispatched (3, read-only, general subagents):** tooltip render/delivery (`main.lua`), inspect/cache (`Libs/LibForeverInspector`, `gearscore.lua`, `pawn.lua`), client truth (`/home/sam/wow-ui-source`, `origin/forever`).

### Returned evidence

- Forever is Mainline-family: `TooltipDataProcessor` post-call, `TooltipDataHandlerMixin`, no `OnTooltipSetUnit`/`OnTooltipSetItem` scripts, NineSlice present, `SetBackdrop` absent.
- Style values: 1 FULL, 2 COMPACT/FULL, 3 COMPACT, 4 MINI/FULL, 5 MINI (`options.lua:1747-1753`); default is 2 (`options.lua:68`); style read at `main.lua:2063-2064`; mini inline block at `main.lua:2508-2555`.
- The Talents block is gated only by `TacoTipConfig.show_talents` (`main.lua:2354`); there is no client-family gate.
- GearScore renders only when `gearscore > 0` (`main.lua:2502`); Pawn only when `pawnScore > 0` (`main.lua:2542`).
- `TacoTip_GSCallback` clears the GearScore retry ladder and score memo, then re-drives the tooltip (`main.lua:1566-1604`).
- `TT_PAWN:GetScore` hard-returns 0 until `CI:GetLastCacheTime(guid)` is non-zero (`pawn.lua:141-144`).

### Open

- Why `tip_style` is 5 when the default is 2, and why selecting FULL does not change the rendered layout. The render lane is tracing every `tip_style` read/write, the saved-variable load, sanitize, and every dropdown writer.
- The exact producer of the `Gear score 0 · item level 4` text. The returned lanes did not find that literal in the working tree; the operator states it is the mini group. The operator's in-game observation is primary; settle it from the mini branch and runtime state, not by asserting absence.

### Audit verdict — 2026-11-05

- **Dropdown write path is proven clean.** `createOptionsDropdown` always names the frame (`options.lua:1355-1356`), and on `origin/forever` `UIDropDownMenu_SetSelectedValue` → `UIDropDownMenu_Refresh` → `UIDropDownMenu_SetText` dereference only template children that exist (`UIDropDownMenu.lua:948-954, 823-908, 1404-1407`; template children at `UIDropDownMenuTemplates.xml:187-189, 216-224`). The row click calls `SetValue` before the handler (`options.lua:1336-1342`). No source-visible raise can skip `TacoTipConfig.tip_style = value`. R5 is disproven.
- **Style is inert by construction for 2/3/4/5 until a score row exists.** `mini_style` is used only inside `if (gearscore > 0)` and `if (pawnScore > 0)` (`main.lua:2064, 2502-2508, 2542-2548`). COMPACT/FULL, COMPACT, MINI/FULL and MINI produce the same base layout when no score row is built. Only FULL (1) changes the unconditional branches.
- **The options handlers never re-render the visible tooltip** (`options.lua:1832-1835`, `2037-2039`; `RefreshOptionsUI` only rebuilds widgets). An ownerless world hover has no periodic rebuild; a unit-frame hover does (0.2 s). A style change is therefore not applied to the tooltip already on screen.
- **The renderer preserves every pre-existing client row.** It captures all rows (`main.lua:2071-2074`), re-emits every non-empty one (`2579-2588`), and only blanks rows past its own count (`2651-2663`). A client-supplied score row survives untouched; TacoTip never owns or removes it. This is the fifth-line defect, not a client attribution.
- **The Talents line has no client-family gate.** The only gate is `TacoTipConfig.show_talents` (`main.lua:2354`); the line is emitted at `2412`/`2436`, and the formatter suppresses only the `[p1/p2/p3]` suffix (`785-790`).
- **Pawn disappearance has two code-proven candidates.** (a) `TacoTip_GSCallback` clears the retry ladder and memo then re-renders (`main.lua:1566-1594`); Pawn is called with `not needGsScore` (`2528`), so with GearScore enabled it registers no item callbacks. (b) `cacheUnitData` commits `data.items = staged` and stamps `data.time` when links are nil and `GetInventoryItemTexture` is also nil (`LibForeverInspector.lua:3770-3796`), making an empty/partial snapshot fresh for 300 s; both scorers then return 0.
- **Forever spec path leaks Classic logic.** `cacheUnitData` builds `specIndexByGroup` with the Classic talent-tab helper even on the modern branch (`LibForeverInspector.lua:3861-3862` → `3635-3652` → `3144-3152`), and `getModernSpecData` treats `C_SpecializationInfo.GetSpecialization` as a specID when it returns an index (`3255-3275`; Blizzard usage `Blizzard_HeirloomCollection.lua:26-33`). Pawn then scores on `spec 1` (`pawn.lua:147`).
- **UNKNOWN (runtime):** the loaded `tip_style` value and whether a click reaches the handler on the operator's install; the exact producer of the preserved client score row. Neither changes the code-proven defects above.

### Next step

- Present the verdict to the operator. No code changes until approval. When approved: write the extensive Forever-only test lane first, every pin revert-proven, then the Forever-gated fix. Other client families untouched.

## 2026-11-05 — Implementation lane (0.9.2): Forever tooltip parity

- **Operator order (verbatim, top rung):** Forever must render like classic `1.png` with the SOLE exception of NO Talents (no line, spec text, or icon; fully gated); coloring preserved; Target line kept; style selection must switch the layout; stale extra score row gone; Pawn persists after item data; version bumped to 0.9.2 with full changelog; classic tests untouched (all new coverage in the Forever test file); other families byte-identical in behavior.
- **Production (`main.lua`, all hunks Forever-gated, verified by `git diff` line-by-line):**
  - Talents block requires `not isForever` + overlay icon cleared on Forever.
  - Header-row drop on Forever, scoped to player units (addon rebuilds every dropped player row; NPC client rows preserved).
  - `TT:RefreshOpenUnitTooltip()` (Forever-only; returns false elsewhere) wired into both style dropdowns in `options.lua`.
  - `refreshUnitTooltip` keeps the single common `UpdateTooltip` path (the stale-row fix lives in the handler drop; the exactly-once drive accounting the suite pins is preserved). Verified in-game-plausible: the operator's symptom (tooltip changes after GSCallback, which drives UpdateTooltip) proves the handler re-runs on that path.
- **Production (`Libs/LibForeverInspector`):** `getModernSpecData` reads the group-aware answer as an INDEX (verified: generated docs on `origin/forever` return `specializationIndex`; `GetInspectSpecialization` returns the specID); `talentPoints`/`specIndexByGroup` from modern data on Forever; all-empty Forever reads stay incomplete with no `.time` stamp.
- **Tests:** NEW `Tests/harness/forever_tooltip_test.lua` (33 pins) + `run_all.sh` registration. No classic test file modified; the two `load_test.lua` version literals moved 0.9.1→0.9.2 as version-bump mechanics. Red/green: old-main throwaway → Talents pins red + re-render entry missing (26/30); old-lib throwaway → Pawn/empty-guard/spec pins red (26/33); tree → 33/33 on lua5.1, lua5.4, luajit.
- **Honeypot found while pinning (harness-only, production innocent):** the mock's `SetUnit`/`UpdateTooltip` first did NOT repopulate client rows, so refresh renders read the addon's own previous output (ownership-proof blanks → early return; double colorize on re-entry). Fixed in the mock by re-seeding the client's header rows per unit (engine-faithful), not in production.
- **Red-tree disclosure:** two pre-existing `tooltip_test FOREVER` pins assert the banned Talents-on-Forever readout (`21/0/0`); they fail by operator order and the shared file cannot be edited per the lane boundary. Everything else green. Operator disposition needed (retire/re-scope those two pins).
- **Docs:** `CHANGELOG.md` [0.9.2] (full), `README.md` What's New 0.9.2 + frontmatter 0.9.2/2026-11-05, `TacoTip.toc` + lua fallbacks 0.9.2, `workshop.md` index-vs-ID client fact, `hands-up.md` operator-overruled-pins failure mode.

## 2026-11-05 — Extension + test-truthfulness pass (0.9.2)

- **Operator corrections honored, no guessing:** (1) no bare "Item Level" row exists in the unit path (sole producer is the ITEM tooltip at `main.lua:3002`, out of scope) -- the vacuous absence half-pin was cut, replaced with a positive pin on TacoTip's own color-coded `iLvl: |c...` line; (2) style 4 is mini-without-shift BY CODE (`mini_style` includes `tip_style == 4`; shift flips it) on every client -- the pin now asserts that shared semantic instead of my wrong guess; (3) the idempotence pin asserted against a harness-only state (re-render with no client refresh, which the engine never produces) -- replaced with refresh-stability (identical entry renders byte-identical), the engine-faithful property; (4) two Lua-pattern slips fixed and audited file-wide (`%X`->`%x` with 8 hex digits, `%[88%]` in plain-find, `[^\n]`/`{10,}` regex-isms removed).
- **Guildless + no-target + own-tooltip covered:** P12 guildless player (no guild line, level at row 2, scores intact); P8 NPC gains the targetless "Target: None" pin; P13 own tooltip (no Target line, no inspect, live scores). No more everyone-has-a-guild assumption.
- **Detector self-proof:** doubled-color purity check now runs after every render, and two meta-pins prove the detector pattern itself fires on doubled input and passes clean input (the meta red caught my own 6-vs-8 hex miscount before any gate ran).
- **Counts:** 71/71 on lua5.1, lua5.4, luajit. Red/green on throwaways: old main 62/66 (4 red: all Talents pins + re-render entry); old lib 61/71 (10 red: Pawn x4 incl. mini/group, empty-guard x3, spec, recovery, guildless-Pawn). Every red traces to a fixed defect.
- **Unchanged:** production hunks (still exactly the Forever-gated set), the two overruled `tooltip_test FOREVER` pins (awaiting operator disposition -- the shared file was not touched).

## 2026-11-05 — NPC gate removed per operator order

- The `UnitIsPlayer` gate on the Forever header drop was my own un-ordered addition. Removed; `main.lua:2127` is back to exactly `if (isForever) then`. Player-tooltip execution is identical with or without it. CHANGELOG scoping sentence corrected to match the tree.

## 2026-11-05 — Operator-found row producer (unverified, operator-reported)
- Operator reports the extra `Gear score N · item level M` row comes from an addon named "Fojii" (their spelling). Not verified from the repo side.
- Implication carried over: TacoTip must own/remove that foreign row on Forever rather than preserve it.

## 2026-11-17 — v1.0.7 wide-style row reserve removed (operator in-game report)

- **Symptom:** operator screenshot, Forever, `tip_style = 1` (Wide), power bar on: four rows
  (Target, Talents, GearScore, Pawn), then a ~4-row blank band inside the border; the bar hangs
  off the frame's bottom edge, so the gap is obvious. Compact / Compact+Shift is tight.
- **Cause:** 67efbb8 added `wideBottomPad += linesToAddCount * (fontSize + 2)` for Forever,
  premised on the client measuring the box before the post-call appends. In game the rows ARE
  in the measured height by layout time (`ProcessLines -> post-calls -> Show`,
  `TooltipDataHandler.lua:292-300`, plus the guarded `Show()` refit), so the pad double-counted
  them. The v1.0.7 "geometry pin" was arithmetic over the mock's recorded SetPadding values
  (the mock has no height model), so it could not catch this.
- **Change:** reserve removed; the 4px base pad (scaled by `tooltip_font_size`) stays on every
  family. `padOkForFamily` now requires the exact base everywhere; the FOREVER pin asserts
  "appended rows add no bottom reserve". Red proof: with the reserve re-inserted the FOREVER
  tooltip run showed 4 FAIL (new pin: appended=1 bottom=18 expectedBottom=4); restored tree
  is 248/248 PASS.
- **Gates:** run_all 75/75, Extras 42/42, luacheck 0/0 in 70 files, both `--worktree`
  verifiers PASS, `wowlua_ls` 69 warnings (documented baseline unchanged).
- **Docs:** CHANGELOG 1.0.7 summary row + wide bullet and the README v1.0.7 paragraph corrected;
  not committed (operator commits on request).
- **Next:** operator re-checks Wide in game with the power bar on. If a row still renders
  outside the border, it is not the pad -- reproduce with a client-faithful height model.
