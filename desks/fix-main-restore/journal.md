# fix-main-restore — Journal

## 2026-10-20 — Desk opened
- **Purpose:** Restore `gearscore.lua` and `options.lua` to their pre-slash-move state (the slash-command surface moves BACK to `gearscore.lua`), keeping every good post-move change, and leave the tree GREEN.
- **Scope:** The MAIN add-on only — `gearscore.lua`, `options.lua`, `main.lua`, `Tests/harness/*.lua` (pins only), `CHANGELOG.md`. NOT `TacoTip_Extras/`. No commit, no staging.
- **Operator decision:** A previous lane moved the whole slash surface (the `SLASH_TACOTIP1..7` declarations, `registerBootstrapSlash()`, the Extras-forward resolver) out of `gearscore.lua` into `options.lua`. The operator wants it back the way it was: `gearscore.lua` owns the slash block again, `options.lua` keeps only its richer ten-command handler, and the resolver lives in `gearscore.lua` again, published as `TT.ForwardExtrasSlashCommand` and called by `options.lua`'s handler.
- **Context read before starting:** `bench/audits/2026-10-20-release-readiness.md` (publish-bound; Era is the only pre-upload test client, the other four ship on offline proof) and `bench/audits/2026-10-20-pre-publish-test-window.md` (Block A step 5 pins `/tt lb` → leaderboard, `/tt` alone → options panel).
- **Next step:** Finish the pins (zoom fallback/slider agreement, zoom raise counter in diag, Extras-forward counters in diag, the `"options"` target never falling back to the debug snapshot), add the `## [0.8.4]` CHANGELOG bullet, then run the five validation commands and emit the `done` signal.

## 2026-10-20 — Pre-move text recovered; restore applied
- **Where the pre-move text came from:** my own revert-proof copies under `/tmp/opencode` —
  `/tmp/opencode/gearscore.lua.bak` (819 lines, the exact pre-move `gearscore.lua`) and
  `/tmp/opencode/options.lua.bak` (3267 lines, the exact pre-move `options.lua`). Both still exist.
  The desk journal of the earlier lane (`desks/fix-main-slash-forwarding/journal.md`) corroborates the
  structure but the byte-exact source was the `.bak` files.
- **Restored:** `gearscore.lua` = `/tmp/opencode/gearscore.lua.bak` VERBATIM (819 lines), then re-applied
  the two post-move fixes inside the resolver: the M2 rule (the `"options"` target no longer falls back
  to the debug snapshot) and the "THE PROXY'S OWN KEY" documentation paragraph that explains why a
  proxy read must use the LIST KEY name.
- **Restored:** `options.lua` = the pre-move file + the zoom work only. The 209-line moved-in block
  (the "Companion add-on slash forwarding" header, `EXTRAS_COMMAND_TARGETS`, `proxySlashEntry`,
  `resolveExtrasHandler`, `reportExtrasForwardFailure`, `TT.ForwardExtrasSlashCommand`) was removed;
  the pre-move comment on `registerSlashCommands` ("The options module owns the final slash handler and
  intentionally replaces the early bootstrap command registered by GearScore.") is back. Verified:
  `diff /tmp/opencode/options.lua.bak options.lua` shows ONLY the four zoom hunks.
- **Kept from the post-move work:** the whole zoom work (`TT.TooltipPortraitZoomDefault` /
  `TT.TooltipPortraitZoomRange`, the two former `or 0.7` fallbacks now resolving to the one default,
  the slider range 30-100, the sanitiser bound 0.3-1.0 with NO clamp of a saved value), the
  `SetPortraitZoom` raise counter (`TT.ev.portraitZoomFailed`), the `extrasForwardFailed` counter,
  the M1 diag surfacing in `main.lua`, and the "THE PROXY'S OWN KEY" doc paragraph.
- **Current state:** `bash Tests/harness/run_all.sh` = 71/71 green on lua5.1 (the five
  `gearscore_test` invocations pass again now that `gearscore.lua` owns the bootstrap handler).
- **Next step:** Add the pins, the CHANGELOG bullet, run the full five-command validation, emit `done`.

## 2026-10-20 — Pins added, revert-red proven, tree green

**Pins added (all in the existing harness files, none deleted or weakened):**

- `Tests/harness/gearscore_test.lua` (+8 checks, 57 total): the `"gs"` target never falls back to the
  debug snapshot (both debug surfaces installed — the published global and the `TTEXTRASDEBUG` entry);
  `/tt gs` with no options entry falls back to TacoTip's own options panel; `/tt gsdebug` still reaches
  the diagnostic snapshot; a raising Extras handler is COUNTED (`TT.ev.extrasForwardFailed`), reported
  to the player, and does NOT also open the options panel.
- `Tests/harness/options_test.lua` (+10 checks, 86 total): the zoom slider is reachable; the ONE
  default is `0.75`; the range is 0.3-1.0; the slider's displayed value for no saved zoom (75), a saved
  zoom (50) and an out-of-range saved zoom (75); an out-of-range saved zoom is REPLACED by the default,
  not clamped; a raising Extras handler is counted; `/tacotip diag` reports the Extras-forward failures
  with the last command and the last error.
- `Tests/harness/tooltip_test.lua` (+15 checks, 209 total): the options UI is built in that harness (the
  dropdown surface installed for the block and taken away again) so the zoom slider exists; the slider's
  displayed value EQUALS the value passed to `SetPortraitZoom` for all three cases (default, saved,
  out-of-range saved); the portrait's zoom is the expected one; a raising `SetPortraitZoom` counts a zoom
  failure and the count is rendered by `/tacotip diag` as `portrait zoom failures: N`.

**Revert-to-fail proven on lua5.1, each on a COPY of the tree under `/tmp/opencode/mut` (the tree itself
was never mutated):** the M2 debug-snapshot fallback restored → 2 checks red (`gearscore_test`); the
slider fallback back to `or 0.7` → 1 red (`options_test`) + 1 red (`tooltip_test`); the render fallback
back to `0.7` → 2 red (`tooltip_test`); the zoom raise counter dropped → 2 red (`tooltip_test`); the
M1 Extras-forward diagnostic line dropped → 2 red (`options_test`).

**A mock limitation found and worked around (not a product bug):** `main.lua` captures `UnitExists` at
file scope (`main.lua:373`), and `options_test.lua`'s mock answers `false` for every unit — so the
tooltip unit never resolves there and the portrait branch cannot run in that harness. The portrait half
of the slider/portrait agreement therefore lives in `tooltip_test.lua`, which drives the real pipeline;
the slider half is pinned in both harnesses.

**CHANGELOG:** one bullet added to the existing `## [0.8.4]` section (new subsection "Border thickness,
portrait zoom and the Extras-forward ledger"). No version bump, no existing section rewritten.

**Validation (all five commands, quoted in the final message):** `Tests/harness/run_all.sh` 71/71 on
lua5.1, lua5.4 and luajit; `TacoTip_Extras/Tests/harness/run_all.sh` 14/14 on all three;
`luacheck .` → 0 warnings / 0 errors in 88 files; `Tools/verify_release.sh --worktree` → PASS (27
files); `Tools/verify_release_extras.sh --worktree` → PASS (29 files).

**Files changed by this desk:** `gearscore.lua`, `options.lua`, `CHANGELOG.md`,
`Tests/harness/gearscore_test.lua`, `Tests/harness/options_test.lua`, `Tests/harness/tooltip_test.lua`,
plus this desk (`desks/fix-main-restore/`). `main.lua` was NOT changed — the M1 diag surfacing and the
zoom raise counter were already in place and survived the restore. Nothing staged, nothing committed,
`TacoTip_Extras/` untouched.

- **Next step:** The tree is GREEN and publishable. The `done` signal is at
  `desks/fix-main-restore/.signals/2026-10-20T00-00-00Z-restore.json`.

