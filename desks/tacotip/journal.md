# tacotip — Journal

## 2026-10-14 (3) — Classic portrait destroy/hide/re-anchor, root-caused and fixed; plus the `CanInspect` wrong turn reversed

- **Done — the Classic-only portrait defect.** `onTooltipSetUnit` resolves its unit in three steps, and the third — `resolveUnitTokenFromGUID(data.guid)` — is the safety net for exactly the case `GetUnit()` fails. It is **structurally unreachable on the Classic family**: the `OnTooltipSetUnit` script hook is registered as `function(tooltip, ...) handleTooltipSetUnit(tooltip) end` and drops its varargs, so `data` is `nil` on every Classic render. Retail and WoW Forever get real `data` from `TooltipDataProcessor.AddTooltipPostCall` and never reach the branch.
  Consequences, all Classic-only: `incomingGUID` always `nil` → `keepModel` always `false` → the unresolved branch hid the portrait **and** reset `portraitSide`/`portraitAnchored` (the re-anchor) every render → then `return`ed, skipping `ApplyTooltipAppearance`, which holds the only `portrait:Show()` in the file. **Nothing re-showed it.**
  Fix: pass `keepModel = not changeUnproven`, where `changeUnproven` means *no guid, or it matches what is already rendered*. A guid that is present **and different** still tears down correctly.
- **Evidence (VERIFIED):** removing the fix turns the new assertion `an unresolvable render does NOT leave the 3D portrait hidden` red on **Classic Era, TBC Anniversary and Titanforge only** — Forever and Retail stay green because they take the guid-compare keep path. That is the proof it is Classic-specific, not an assertion that it is.
- **Done — a counter that could not see its own call.** `TT.ev.portraitHide` sits *inside* `if (not retainModel)`, so it counted **teardowns, not `Hide()` calls**. Lifting `Hide()` out of its guard — the exact shape of this bug — left the two pre-existing tests green on all five clients. Added `TT.ev.portraitModelHidden` on every hide; relabelled the diag counters so each matches what it counts.
- **Done — `CanInspect(unit, true)` reverted.** It was added as a "range gate" on the belief the second argument was a range flag. It is `showError`. The call was asking the engine to *display* a message — the very popup it was written to prevent. Now the one-argument form. **Not confirmed as the popup's cause**; it was demonstrably wrong on its own terms.
- **Evidence:** `bash Tests/harness/run_all.sh` → **54/54, exit 0**. `luacheck main.lua` → **0 warnings, 0 errors**. Both run directly, not reported by a lane.
- **Open:** popup origin **still unattributed** — the error capture exists and is wired into `/tacotip diag`, but has not been run in a client. `currentUnitGUID` is never cleared, so the guid-change teardown fires on the first render of any unit after `/reload` and on every A→B→A (churn on *every* client). `NEARBY_ASK_YARDS` (20/40) is still not set from measurement. None of the portrait work is confirmed in a live client.
- **Next step:** `/reload`, reproduce the error, `/tacotip diag`, paste the attribution block back. A `notify` line with `distance` in 20–28 while `interactDistance` is `true` proves the pre-filter sits below the server's refusal point and can be raised.

## 2026-10-14 (2) — The "annoying red error" is NOT TacoTip; plus a diag false alarm fixed

- **Verdict (VERIFIED):** the error in the Classic Era screenshots is
  `Frame:RegisterEvent(): Attempt to register unknown event
  "INPUT_DEVICE_INTERFACE_TRANSITION"` — **third-party, from FojjiCore.**
  Evidence, in order of strength:
  1. The string exists in **exactly one** file across the whole installed
     `_classic_era_/Interface/AddOns` tree: `FojjiCore/Locale.lua:57`.
     It is absent from this repo and from the installed `TacoTip` + `TacoTip_Extras`.
  2. The event is documented on `origin/forever`
     (`Blizzard_APIDocumentationGenerated/InputDocumentation.lua`,
     `Blizzard_SharedXML/InputUtil.lua`) and is **absent** from `origin/classic_era`,
     `origin/classic_anniversary` and `origin/classic_titan` — so registering it on
     Classic Era must raise.
  3. Every one of the 22 event strings TacoTip registers was verified present in
     the `classic_era` API docs — TacoTip cannot produce this error class.
  4. **BugGrabber's saved log** (`WTF/.../SavedVariables/!BugGrabber.lua`) records
     58 errors back to 07-12: the `INPUT_DEVICE` one is 10-14 13:18 ×3 (newest in
     the log), and **every TacoTip-attributed entry is from 07-12 … 08-13** — none
     in September or October. The installed build (0.8.3 + the event-path fix,
     confirmed present at `LibForeverInspector.lua:3681/4170`) is clean.
  5. `FojjiCore` files are dated **10-14 11:06**, ~2h before the first error —
     that is the "it didnt do this be4": the third-party add-on was updated this
     morning, not TacoTip.
- **Not ours to fix** (hold scope): FojjiCore is a third-party Wago add-on in the
  *game* folder, not this repo. Register as `bench/OPEN-ITEMS.md` row 11 with the
  closing condition on the operator's BugSack.
- **Fixed (in-repo, real bug):** `/tacotip diag` raised a false **PROBLEMS**
  alarm on the three Classic-family clients — `elseif (not (IsRetail() or
  IsForever()))` is true *by design* on Classic Era, so a perfectly healthy client
  reported `client detected as NEITHER Retail nor WoW Forever (interface 11509,
  project nil)`. Now flags only `CI:IsUnknown()` (family resolved to nothing).
  Both of the operator's complaints were visible in one screenshot, which is why
  this one is ours and the other is not.
- **Test:** `load_test` now captures `/tacotip diag`'s *printed text* (the
  existing spy only counted calls) and asserts the false alarm string never
  appears. Revert-to-fail proven: restored the old condition → Classic Era run
  exits 1 with `FAIL /tacotip diag raises no client-detection false alarm`.
- **Limits:** the new check is negative-only (asserts absence); no client in the
  matrix resolves to `unknown`, so the positive branch — "does it still flag a
  genuinely unresolvable family?" — is uncovered. Documented rather than papered
  over.
- **Evidence:** `Tests/harness/run_all.sh` 54/54; Extras 42/42; `luacheck` clean
  on `main.lua` + `load_test.lua`.
- **Next step:** operator updates/disables FojjiCore, confirms BugSack is clean,
  then runs the in-game checklist (items 1–3 below) so `0.8.4` can ship.

## 2026-10-14 — Desk opened

- **Purpose:** keep the core add-on (`TacoTip`) correct *in the game*, not just in
  the harness: the inspect → GearScore/iLvl → tooltip pipeline, options UI,
  localization, media, and the performance rules that keep all of it cheap.
- **Scope:** the add-on's own files at this repo root (`TacoTip.toc`, `main.lua`,
  `gearscore.lua`, `pawn.lua`, `textures.lua`, `options.lua`, `Locale/`, `Libs/`)
  plus `Tests/harness/`. The companion add-on has its own desk (`extras`); the
  Blizzard-API questions go to `api-verification`; packaging and versioning go to
  `release`.
- **Next step:** the in-game Classic Era pass below. It is the only gate left on
  the work described here, and the version bump waits on it.

### State of the work as the desk opens (all in the working tree, uncommitted)

- **Classic Era "out of range" sound + red text — fixed at the root.** The
  symptom was not a range error. `Libs/LibForeverInspector/LibForeverInspector.lua`
  referenced `isCloseEnoughToAsk` from the file-scope `OnEvent` handler while it
  was declared as a `local` further down the file, so the reference compiled as a
  *global* lookup and every player target and every player hover raised
  `attempt to call global 'isCloseEnoughToAsk' (a nil value)` — red text, error
  sound, handler aborted before it could inspect anything. Fixed with a forward
  declaration above the handler; the definition is now an assignment, matching
  the file's existing `local requestInspect` pattern.
- **Hardening that came with it:** `requestInspect` re-checks
  `CheckInteractDistance(unit, 1)` for the Classic family immediately before
  `NotifyInspect` (Classic Era's *published* `CanInspect(targetGUID)` signature
  takes the unit alone, so the range flag Blizzard itself passes there is not a
  documented contract). Mainline keeps the either-signal policy. The dead
  `OUT_OF_RANGE_RECHECK_YARDS` constant is gone.
- **Test gap closed:** `Tests/harness/detect_test.lua` now retains frame scripts
  through its `CreateFrame` mock and fires the real `PLAYER_TARGET_CHANGED` /
  `UPDATE_MOUSEOVER_UNIT` handler on Classic Era / TBC Anniversary / Titanforge.
  Revert-to-fail proven: the shipped shape turns 3 checks red (exit 1) with the
  exact nil-call error.
- **TacoTip Extras `1.2.2`:** rank colours resolve through one
  `Scoring.RankColor(rank, total)` shared by the leaderboard `#` column and the
  tooltip rank line (podium medals → gold for the rest of the top 5% → quality
  bands); the tooltip's `[` `]` are drawn white instead of inheriting the
  number's colour; an inverted top-5% test inherited from `RankBrowser` was
  fixed (it painted the *bottom* 5% gold). Bumped in the `.toc`, `README.md`,
  `CHANGELOG.md` and the harness pin.
- **Version deliberately still `0.8.3`.** `CHANGELOG.md` already carries a
  `0.8.4` row describing this work; the operator bumps everything together once
  the in-game pass is green.

### Verification (run both, from the addon root)

    bash Tests/harness/run_all.sh                  # 54 invocations
    bash TacoTip_Extras/Tests/harness/run_all.sh   # 42 invocations, lua5.1 + lua5.4 + luajit

Last run: 54/54 and 42/42, `luacheck` clean on every changed file. (The one
remaining warning, `table.unpack` in each harness, is pre-existing and
deliberate — it keeps those scripts honest under Lua 5.4.)

### The in-game pass this desk is waiting on (Classic Era)

1. Target a player who is far away, and hover them: expect **no** red text and
   **no** error sound.
2. Walk into range, or hover someone nearby: expect GearScore + iLvl to fill in.
   Coverage should look *better* than before, because the handler used to die
   before it could ask.
3. Extras: hover a ranked player and read the bottom line — `Rank: #N [#M Class]`
   with white brackets, and `#1` gold when the player really is #1.
4. If green: bump to `0.8.4` across `.toc`, `main.lua`, `options.lua`,
   `README.md`, `MEMORY.md` and `AGENTS.md` — the project rule is all at once,
   never one alone.

### Invariants that already cost a session

- A `local` is in scope only from its declaration onward. Anything a file-scope
  handler touches must be forward-declared, or it raises at runtime as a nil
  global — and the harness cannot see it unless a test fires the real handler.
- On the Classic family the distance signal is `CheckInteractDistance(unit, 1)`;
  `CanInspect` alone does not carry range. `NotifyInspect` has exactly one call
  site, and the gate lives there.
- Harness assertions over colours/floats format with `("%.2f"):format(...)`,
  never `tostring(...)` — Lua 5.3+ renders integral floats as `1.0`.

## 2026-10-14 (4) — CAIRN.md ↔ AGENTS.md alignment, verified clean

- **Done.** Both files read against each other and against the repo; bloat\n  removed.
- **CAIRN.md 256? no:** 132 lines. Workshop map now leads with `AGENTS.md`\n  (it was missing entirely). `memory-bank/` relabelled legacy with its (verified)\n  file dates. Four currently-missing paths named explicitly so nobody chases\n  them. Harness counts removed from prose (run the loop, read output).
- **AGENTS.md 256 lines.** Remaining structure: precedence (3 rules of fact),\n  what this is, where a session starts (5 steps), five-client table, source\n  access, XML notes, load order, tests + the 5 lies, working rules (9), the\n  5 durable traps, deliberately-empty \"where things stand\". Inline precedence\n  ladder dropped — it is CAIRN.md's job and duplicated here.
- **No stale refs:** zero `row N`, zero `file:line`, zero version numbers, zero\n  feature-defect claims left in either doc. `## Where things stand` now just\n  points at CHANGELOG + OPEN-ITEMS.
- **Suite 54/54 exits 0; luacheck clean** — unchanged by the doc edits.
- **Open follow-up:** nothing new. User owns: `/reload`, reproduce, `/tacotip diag`.
