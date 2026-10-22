# Final Hardening — Journal

## 2026-10-20 — Desk opened
- **Purpose:** Final defensive hardening pass over TacoTip v0.8.4 (main) and TacoTip Extras v1.2.3 across five clients (11509 Era, 20506 TBC, 38002 Titanforge, 16001 Forever, 120105 Retail). Hunt silent no-ops, discarded protected-call results, per-client nil-deref risks, corrupt-saved-data resilience, malformed wire input, long-session growth/leaks, and raises inside hooked/secure callbacks.
- **Scope:** Repo `/home/sam/TacoTip-Gearscore-TBC`. Read-only FrameXML mirror at `/home/sam/wow-ui-source` for client facts. Defensive changes only — no features, no refactors, no renames, no behavior change for valid states.
- **Constraints:** Another lane (`fix-main-hunter`) owns `gearscore.lua`, `options.lua`, `main.lua`, `Tests/harness/*.lua`, `CHANGELOG.md` — analyze first, re-read before any edit, prefer current file state over notes. Never edit `gearscore.lua` except to add a guard around an existing call. Do not touch scoring formula, SlotMOD, Scale, QualityScale, ITEM_BAND_SCALE, A/B/C tables, Era inspect range gate, Retail bracket, wire format, SavedVariables shapes, `*.toc`, versions.
- **Next step:** Read the bench audits (2026-10-19 final-hunter, publish-readiness-hunter, main-addon-arbiter-audit, maintainability-audit, test-sufficiency-audit, release-readiness) and the desk journals of `fix-main-batch8`, `fix-extras-hunter`, `fix-extras-final-review`, `fix-extras-maintainability`, `fix-main-hunter`. Re-verify every finding against source before acting.

## 2026-10-20 — Bench read (leads only; every finding re-verified from source)

Read before touching anything: `bench/audits/2026-10-19-final-hunter.md`,
`bench/audits/2026-10-19-publish-readiness-hunter.md`,
`bench/audits/2026-10-19-main-addon-arbiter-audit.md`,
`bench/audits/2026-10-19-maintainability-audit.md`,
`bench/audits/2026-10-19-test-sufficiency-audit.md`,
`bench/audits/2026-10-20-release-readiness.md`
(`2026-07-20-release-readiness.md` is **not present** in `bench/audits/`), plus
the journals of `fix-main-batch8`, `fix-extras-hunter`,
`fix-extras-final-review`, `fix-extras-maintainability` and `fix-main-hunter`.

**What the reports said was ALREADY fixed, and was therefore not touched:**
the three Extras HIGHs (locale specifiers, the render latch, the unreachable
`/ttgsdebug` surfaces — `fix-extras-hunter`), the recovery-journal lock
(`fix-extras-publish`), the `/tt lb` forwarding (`fix-extras-final-review`),
the dead locale keys and the class-colour chain (`fix-extras-maintainability`),
and the main add-on's M-1 / M-2 / L-1 / L-3 / L-4 (`fix-main-hunter`).
The `fix-main-hunter` journal also recorded three `TT:RefreshCharacterFrame()`
call sites as **out of scope** — one of them is the CharacterFrame `OnShow`
adapter, which this pass picked up (see Y5 below).

## 2026-10-20 — Coordination with the restore lane

`fix-main-restore` was restoring the slash-command surface in
`gearscore.lua` / `options.lua` while this pass ran. The Extras-side work
below was done first (nobody else was touching `TacoTip_Extras/`); the
main-addon edits waited until
`desks/fix-main-restore/.signals/2026-10-20T00-00-00Z-restore.json`
(`subtype: "done"`) landed. Every main file was **re-read immediately
before** its edit and the change applied to the CURRENT content.

## 2026-10-20 — Extras side: what was hardened

### X1 — every callback registered on a Blizzard frame or function is bounded
`TacoTip_Extras/Frames.lua`. **Eleven** callbacks were registered raw: the
character pane's `OnShow` / `OnHide` / `OnSizeChanged` (`Frames.lua:1335`),
the inspect pane's four frame hooks (`Frames.lua:1384`) and the three
`hooksecurefunc` post-hooks on `InspectFrame_Show` /
`InspectFrame_UnitChanged` / `InspectSwitchTabs` (`Frames.lua:1401`).

*Why it matters (hunt #7):* a raise inside a `HookScript` handler or a
`hooksecurefunc` post-hook does **not** stay inside this add-on — it
unwinds through the **client's own** frame script, so the rest of
Blizzard's handler for that frame never runs. The character and inspect
panes are opened by the PLAYER, so the visible result is a half-drawn pane
with nothing in the add-on's diagnostics.

*What changed:* one `boundedCallback(label, fn)` wrapper (`Frames.lua:69`),
each registration wrapped, the raise caught at the boundary, counted
(`hookCallbackErrors`) and named (`lastHookCallbackError`). The wrapper
returns nothing: the four script types registered here (and the three
post-hooks) all ignore the handler's return value, and the hooks returned
nothing before. `Frames.GetDebugState()` publishes the snapshot.

*Also checked and already safe:* `Core.lua`'s and `Frames.lua`'s own
`OnEvent` handlers sit on the add-on's OWN frames, so a raise there aborts
the add-on's handler, not a Blizzard one — recorded below as not hardened.

### X2 — the Options page had five silent no-ops
`TacoTip_Extras/Options.lua`.

- "Comfortable rows" and "Shaman Blue" wrote their setting and then
  **discarded the result** of `RankBrowser.RebuildUI` — the house-rule
  violation, and a real no-op: a raising rebuild left the player with a
  ticked box, an unchanged window, no message and no count.
- The "Open Server Leaderboard" and "Scan now" buttons called straight into
  `RankBrowser` with no guard at all.
- "Reset enhancer settings", "Restore TacoTip settings" and "Reset summary
  positions" were wired to callbacks that could return `false` or raise
  without a word.

*What changed:* one counted boundary (`Options.lua:63-137`) — the result of
every call is captured, a failure is counted (`actionFailures`), the reason
is kept (`lastActionFailure`) and the player is told in **one plain chat
line** through the file's existing `printOptionsLine` helper.
`Options.GetDebugState()` publishes the snapshot. The `printOptionsLine`
helper became an assignment with a forward declaration because the boundary
is declared above it in the file — no behaviour change, the wording and the
colour are identical.

### X3 — `/ttgsdebug` prints the two new counters
`TacoTip_Extras/Core.lua` — the surfaces block now prints
`frame-hook-errors=` / `last-frame-hook-error=` and
`options-action-failures=` / `last-options-action-failure=`. A counter no
user can see is a counter that cannot be acted on.

## 2026-10-20 — Main side: what was hardened

### Y1 — `/tacotip save` was a silent no-op
`options.lua:700`. With the mover not open the command did **nothing** and
said **nothing**. It now prints the same line the bootstrap handler in
`gearscore.lua` has always used, and counts the refusal
(`TT.ev.moverSaveSkipped`). A raising `_Save` is caught, counted
(`TT.ev.moverSaveFailed`) and named — it used to abort the command.

### Y2 — `/tacotip default` confirmed the wrong case
`options.lua:673`. The confirmation printed only when there was **nothing**
to disable and stayed silent when a custom position really was cleared —
exactly inverted relative to the effect. The text describes the resulting
state, so it is true either way; it now prints once, after the reset. This
matches the bootstrap handler in `gearscore.lua`, which has always printed
it unconditionally. The mover's `_Disable` call is now bounded and counted
(`TT.ev.moverDisableFailed`) — a raise used to abort the command before the
configuration was reset.

### Y3 — the options panel's protected calls discarded their results
`options.lua:1062`. `openOptionsPanel` called `Settings.OpenToCategory`
(twice) and `InterfaceOptionsFrame_OpenToCategory` through `pcall` and threw
the result away. A raising call left the player with a typed command, **no
panel**, and no message and no count. The results are captured now
(`TT.ev.optionsPanelOpenFailed`, `TT.ev.optionsPanelShowFailed`, with the
last error kept) and the player is told in one plain chat line.

### Y4 — a corrupt `TacoTipConfig` was repaired in silence
`options.lua:316`. The sanitiser already failed closed and recovered to the
shipped defaults, but the repair was silent. The number of repaired settings
is now counted (`TT.ev.configRepairs`), the first one is named
(`TT.ev.lastConfigRepair`), and `/tacotip diag` reports both. The count is
from the **last** pass, not a running total — the sanitiser runs at load and
again when the options page is built, and a corrupt key is repaired once.
**A valid profile repairs nothing.**

### Y5 — the two pane `OnShow` hooks were unbounded
`main.lua:3778` (character pane) and `main.lua:4027` (inspect pane). Both
called their refresh **unguarded** from a `HookScript` handler on a Blizzard
frame — the hunt-#7 shape, on the two panes the player opens by hand. Both
are now bounded and counted (`TT.ev.characterPaneOnShowFailed`,
`TT.ev.inspectPaneOnShowFailed`, with the last error kept), on the same
idiom the item-load path already used (`main.lua:1646`).

*Already safe, checked and left alone:* the tooltip `OnTooltipCleared` /
`OnShow` / `OnHide` hooks and the item/spell hooks are inside the file's
`safeCall` boundary (`main.lua:3332-3354`, `:3396`); the
`GameTooltip_SetDefaultAnchor` post-hook's `parent:GetParent()` is already
type-checked and `pcall`-guarded (`main.lua:3458-3464`); the guild guard is
already split into two honest buckets.

## 2026-10-20 — Pins, and the revert reds (every fix proved on a COPY)

`bash Tests/harness/run_all.sh` **71/71** on lua5.1, lua5.4 and luajit;
`bash TacoTip_Extras/Tests/harness/run_all.sh` **42/42** on all three.

| # | reverted | red |
|---|---|---|
| X1 | `Frames.lua` hooks unwrapped (`boundedCallback` removed) | `3 FAILED` — "a raise inside a hooked callback does not escape into the client", "...is counted", "...the hooked callback's failure is named" |
| X2 | `Options.lua` discards the `RebuildUI` result again | `3 FAILED` — "a raising leaderboard rebuild is counted", "the failing options action is named", "the player is told in one chat line that the window was not rebuilt" |
| X3 | `Core.lua` stops printing the two new counters | `2 FAILED` — "/ttgsdebug prints every diagnostic counter with its live value", "/ttgsdebug prints the last reason beside each counter" |
| Y1 | `/tacotip save` silent again | `7 FAILED` — including "/tacotip save says so when the mover is not shown", "/tacotip save (mover not shown) is counted", "a raising mover save does not escape the slash command" |
| Y2 | `/tacotip default` prints only when nothing was cleared | `1 FAILED` — "/tacotip default confirms the reset when a custom position WAS set" |
| Y3 | `openOptionsPanel` discards the results again | `3 FAILED` — "a raising options-panel open is counted", "...is named to the player", "/tacotip diag reports the options-panel open failures" |
| Y4 | `main.lua` stops surfacing the new counters | `1 FAILED` — "/tacotip diag reports the skipped /tacotip save" |
| Y5 | the corrupt-config ledger is dropped | `4 FAILED` — "the saved-config sanitiser publishes its repair count", "a corrupt saved setting is counted as repaired", "...the first repaired setting is named", "/tacotip diag reports the corrupt saved settings that were repaired" |
| Y6 | the two pane `OnShow` hooks are unguarded again | `6 FAILED` — "a raising character-pane OnShow refresh does not escape into the client", "...and is counted", "...and the error is named", and the same three for the inspect pane |

Every revert was applied to an **isolated copy** under `/tmp/opencode/` and
the working tree was restored afterwards (each copy re-verified green).

## 2026-10-20 — Found but NOT hardened (numbered, with the reason)

1. **The Extras' own `OnEvent` handlers** (`Core.lua:1382`, `Frames.lua:1463`)
   are not wrapped. They sit on the add-on's OWN frames, so a raise aborts
   the add-on's handler and not a Blizzard one — the blast radius is the
   add-on, not the client. Not wrapped because the audit's own doctrine
   point (`Core.lua:742-754`) was already re-verified as satisfied for the
   paths that matter, and wrapping them would swallow errors the Extras
   deliberately surfaces.
2. **`TacoTip_Extras/RankSync.lua`'s `handlePayload`** is not wrapped
   (`RankSync.lua:1297`). A raise inside the inbound `CHAT_MSG_ADDON` path
   would escape into the event handler. The inbound parsing itself is well
   bounded (240-byte door at enqueue, the inbound rate window, the version
   token on every message, every refusal bucketed) and `StoreRecord`
   validates before storing, so the reachable raise is small — but it is not
   zero. Left alone: wrapping the whole dispatch would also wrap the
   counted refusal buckets and blur the counters the release depends on.
3. **`gearscore.lua`'s `TT_GS._itemRequestTime`** grows one entry per
   distinct item hovered, for the session (`gearscore.lua:326`). It is a
   number per item ID and it is bounded by the number of items the player
   has hovered, not by time, so it is small — but it is not pruned. Left
   alone deliberately: `gearscore.lua` is outside this pass's edit scope
   except for a guard around an existing call, and pruning the table is a
   behaviour change, not a guard.
4. **`main.lua:369` — `pcall(cancel)`** (cancelling a tooltip timer)
   discards its result. It is a cleanup path: the timer is being discarded
   anyway, so a raise there cannot leave a user-visible artefact. Left
   alone.
5. **`main.lua:3133` — `pcall(RequestLoadItemDataByID, itemID)`** discards
   its result. The call resolves to the shared throttle
   (`TT_GS.RequestLoadItemDataByID`), which swallows the raw call's own
   error internally, so a counter at this level would almost never move. The
   raw failure is counted nowhere today; fixing that properly means a
   counter inside `gearscore.lua`, which is outside this pass's edit scope
   except for a guard around an existing call.
6. **The `InspectFrame` `OnHide` handler** (`main.lua:4032`) reads the
   globals `InspectGearScore` / `InspectAvgItemLvl` without a nil check.
   They cannot be nil — the hook is registered inside `TT:InitInspectFrame`
   immediately after those globals are created — so a guard would be dead
   code. Left alone deliberately.
7. **The Extras' `TacoTipExtrasDB` corruption path** was re-verified rather
   than changed: `initializeDatabase` (`Core.lua:441`) already fails closed
   on a non-table root, a non-table `settings`, an out-of-range `schema` and
   a non-table `equipmentDisplay`, and `normalizeSettings` repairs every
   typed field. Nothing to harden; a counter would only add noise.
8. **The Extras' sync wire** was re-verified rather than changed: the
   payload is size-bounded at enqueue, the inbound window bounds the burst,
   the version token refuses every foreign build, the gear chunk count is
   capped at four, and every refusal is counted with a reason. No
   unbounded growth found.

## 2026-10-20 — Final validation (all five commands, quoted in the final message)

- `bash Tests/harness/run_all.sh` → **71/71** on lua5.1, lua5.4 and luajit.
- `bash TacoTip_Extras/Tests/harness/run_all.sh` → **42/42** on lua5.1,
  lua5.4 and luajit.
- `luacheck .` → **0 warnings / 0 errors in 88 files**.
- `bash Tools/verify_release.sh --worktree` → **PASS** (27 files).
- `bash Tools/verify_release_extras.sh --worktree` → **PASS** (29 files).

**Files changed by this desk:** `main.lua`, `options.lua`, `CHANGELOG.md`,
`Tests/harness/options_test.lua`, `Tests/harness/batch8_pane_test.lua`,
`TacoTip_Extras/Core.lua`, `TacoTip_Extras/Frames.lua`,
`TacoTip_Extras/Options.lua`, `TacoTip_Extras/CHANGELOG.md`,
`TacoTip_Extras/Tests/harness/load_test.lua`, plus this desk.

**NOT changed:** `gearscore.lua` (untouched — outside this pass's scope
except for a guard around an existing call, and no guard was needed),
`pawn.lua`, `textures.lua`, `Locale/**`, `*.toc`, the versions, the SavedVariables
shapes, the wire format, the raw GearScore formula, the Retail bracket, the
Era inspect range gate, `README.md`, `Tools/**`, `Libs/**`, `TacoTip_Extras/RankSync.lua`,
`TacoTip_Extras/RankDB.lua`, `TacoTip_Extras/Cache.lua`,
`TacoTip_Extras/Scanner.lua`, `TacoTip_Extras/Tooltips.lua`,
`TacoTip_Extras/RankBrowser.lua`, `TacoTip_Extras/Scoring.lua`,
`TacoTip_Extras/Minimap.lua`, `TacoTip_Extras/TacoTipAdapter.lua`.
Nothing staged, nothing committed.

## 2026-10-20 — [signal:done] Final hardening pass complete

- **Worked on:** the Extras' eleven unbounded Blizzard-frame / `hooksecurefunc`
  callbacks; the Extras' five silent Options-page no-ops; the `/ttgsdebug`
  surfaces block; the main add-on's `/tacotip save` silent no-op; the
  inverted `/tacotip default` confirmation; the options panel's three
  discarded protected-call results; the corrupt-`TacoTipConfig` ledger; and
  the two pane `OnShow` hooks.
- **Current state:** nine revert-to-fail proofs, each red then restored green
  on an isolated copy; MAIN **71/71** on lua5.1 / lua5.4 / luajit; Extras
  **42/42** on all three; `luacheck .` **0 warnings / 0 errors in 88 files**;
  `Tools/verify_release.sh --worktree` **PASS** (27 files);
  `Tools/verify_release_extras.sh --worktree` **PASS** (29 files). Nothing
  staged, nothing committed.
- **Eight items found and deliberately NOT hardened** are listed above with
  the reason for each; none of them is a user-visible silent failure in a
  valid state.
- **Desk path:** `desks/final-hardening/`. **Signal:**
  `.signals/2026-10-20T18-00-00Z-final-hardening.json`.
