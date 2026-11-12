# Desk: forever-item-tooltip-taint — Journal

## 2026-11-12 — Desk opened

- **Purpose:** trace the Forever/Camelot item-tooltip path end to end for the
  reported loss of the client's right-column segments (subclass + weapon
  speed), and remove the tooltip-info reads that can carry taint into
  `ProcessInfo`.
- **Scope:** `main.lua` item tooltip path, `gearscore.lua` `GetItemInfo`
  wrapper, `Tests/harness/forever_tooltip_test.lua`,
  `Tests/harness/contract_pins_test.lua`. Root add-on only.
- **Do-not-touch:** FojjiCore row block, `GameTooltip.AddLine`/`AddDoubleLine`,
  unit-tooltip renderer, loot-window tooltip (already native), custom_pos /
  mover, Extras scan.
- **Evidence file:** `bench/findings/2026-11-12-forever-item-tooltip-taint-trace.md`.
- **Next step:** gates (run_all ×3, luacheck, extras, both verifiers), then the
  residual item: decide whether to skip the whole item hook when the Forever
  payload is not provably readable.

## 2026-11-12 — [checkpoint] trace + fix + pins landed; gates running

- **Verified from `origin/forever`:** taint into `ProcessInfo` + secret line
  data = "tooltip displaying no lines" (GameTooltip.lua:994-1003); accessors are
  secure delegates that strip taint from supplied arguments
  (TooltipDataHandler.lua:489-505); `C_Item.GetItemInfo` is
  `MayReturnNothing` + `SecretArguments="AllowedWhenUntainted"`
  (ItemDocumentation.lua:626-640); `GameTooltip` has no `UpdateTooltip` method on
  this client (GameTooltip.lua:450-460), so the item-load repaint is a no-op.
- **Found:** four tooltip-info reads on every Forever item tooltip (two in the
  item post-call, two in `OnShow`). Fixed: payload-only resolution + OnShow item
  marker; `gearscore.lua` wrapper guarded + pcall + nil.
- **Pins:** FOREVER 144 → 154 (P20), CONTRACT 62 → 64 (H). Red-proven against
  `git show HEAD:` copies via `TACOTIP_MAIN_OVERRIDE` / `TACOTIP_GS_OVERRIDE`.
- **Next step:** run the gate matrix and record counts in the final journal
  entry.

## 2026-11-12 — [signal:done] gates measured green (one lane closed)

- **Changed:** `gearscore.lua` (secret-safe `GetItemInfo` choke point: below the
  strong guard, argument-tested, pcall'd, nil on refusal), `main.lua`
  (payload-only item resolution on Forever, OnShow item marker, repaint
  comment), `Tests/harness/forever_tooltip_test.lua` (P20, 10 pins),
  `Tests/harness/contract_pins_test.lua` (H, 2 pins). 4 files, +180/-14.
- **Measured:** run_all 75/75 on lua5.1, 75/75 lua5.4, 75/75 luajit; FOREVER
  154/154; CONTRACT 64/64; Extras 42/42 (luajit run 14/14); verify_release PASS;
  verify_release_extras PASS. luacheck: 2 warnings / 0 errors in 93 files, both
  pre-existing at HEAD in untouched Extras files (Scoring.lua:965 shadowing,
  TacoTipAdapter.lua:1663 empty if) — verified by linting `git show HEAD:`
  copies; main add-on and every changed file are clean.
- **Red proof:** `TACOTIP_MAIN_OVERRIDE` at HEAD fails 3 P-ITEM checks (reads=1,
  reads=2, secret link scores 100); `TACOTIP_GS_OVERRIDE` at HEAD fails the
  refusal check.
- **Not proven:** the operator cannot reproduce the missing right column, so no
  in-game confirmation exists. The trace removes the only source-visible
  mechanism (tooltip-info reads from tainted hooks) but does not prove that was
  the users' cause.
- **Next step:** if the report persists, skip the whole Forever item hook when
  `TT.tooltipDataReadable(data)` is false, and instrument a shipped counter for
  "item payload unreadable" so a user report can confirm it.

## 2026-11-12 — [checkpoint] item-path diagnostics counters landed

- **Added** to `TT.ev`: `itemHook` (item post-calls), `itemPayloadUnreadable`
  (payload table refused by `canaccesstable`), `itemPayloadMissing` (no payload),
  `itemSecretLink` (link arrived secret and was dropped), `itemNoLink`.
- **Report:** `/tt diag` tooltip section gains `item tooltip hooks` (renders /
  unreadable payload / no payload / secret link / no link, warn when any refusal
  counted) and `secret restrictions` (Combat/Encounter/ChallengeMode/PvPMatch/
  Map = on|off, from `C_RestrictedActions.IsAddOnRestrictionActive`, feature-
  detected, secret-safe). Two new problem entries name the refusal counts.
- **Pins:** P-ITEM grew 10 → 14 checks (counter increments, diag row, problem
  text). FOREVER pins 158/158; red on HEAD = 7 FAILs (151/158).
- **Gates:** run_all 75/75, verify_release PASS, luacheck 2 warnings / 0 errors
  in 91 files (both pre-existing Extras warnings).
- **Next step:** the remaining proposal list (row-count delta, per-API refusal
  tally, last-item fingerprint) awaits the operator's pick.

## 2026-11-12 — [checkpoint] the three diagnostics landed + warning total fixed

- **Row-count delta:** item hook records `itemRowsLastBefore/After`, warns (and
  counts `itemRowsRemoved`) when a hover ends with fewer lines than it started
  with, and reports `item row delta` in the tooltip section.
- **Per-API refusal tally:** `TT:NoteSecretRefusal(api)` counts refused
  AllowedWhenUntainted calls (`tooltip-data`, `item-link`, `IsEquippableItem`,
  `GetItemInfo`); report shows `secret refusals by API` sorted count-desc, and
  the problems section names the total.
- **Last item hover fingerprint:** `ev.lastItem` = id, rows we added, payload
  readable/unreadable/none, secret-link flag, restriction snapshot, timestamp.
  The restrictions snapshot moved to `TT:RestrictionSnapshot()` and is shared
  with the report row.
- **Not hiding errors/warnings:** `RecordWarning` now increments a lifetime
  `TT.totalWarnings` (log is capped at 30 and DROPS the oldest, so `#log` used
  to understate the session); the errors section shows
  `total warnings recorded: N (log holds M)` and the problem text says
  "N recorded (M kept in the log)". Section/collection/render failures were
  already surfaced as rows + problems (verified by reading the collector).
- **Pins:** P-ITEM 14 → 18 (tally, row delta + fingerprint, report rows,
  lifetime-vs-capped warning total). FOREVER pins 162/162. Red at HEAD: 11
  P-ITEM FAILs (151/162).
- **Gates:** run_all 75/75; verify_release PASS; luacheck 2 warnings / 0 errors
  in 91 files (both pre-existing in untouched Extras files).
