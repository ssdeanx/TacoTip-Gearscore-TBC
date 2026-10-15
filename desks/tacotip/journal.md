# tacotip — Journal

## 2026-10-14 (7) — Two more audits (trace + pipeline); eleven defects fixed, six assertions mutation-proven

- **Audits.** Two read-only oracles, mirror-only for Blizzard claims: one tracing every thread between `LibForeverInspector` and the rest of the repo, one on the scan pipeline (per-client support, redundant work, wasted calls, state growth). Neither edited anything.
- **Verified negatives worth keeping:** no file outside the library calls `CanInspect` / `NotifyInspect` / `CheckInteractDistance` / `UnitDistanceSquared` or touches `UIErrorsFrame` — the probe guard cannot be bypassed, and the library is the only place the engine's inspect surface is touched. Every live caller of the library's public API matches the current definition's arity and return shape. Toc order satisfies every dependency; the library has no `_G` leaks and no dependency on `TT.*` / `TacoTipConfig`. No per-client classification disagreement on the five supported clients (`TacoTip_Extras/Scoring.lua` re-derives Forever-vs-Retail independently, with a different boundary, and coincides on all five — recorded, not changed).
- **Fixed (each with a revert-to-fail mutation):** the tick's freshness check now precedes the gate chain in all three priorities (a cached 40-man raid cost ~880 engine calls/s: `can=40 dist=40 distSq=40` → `0/0/0`); `DoInspect` likewise (the hottest path — every tooltip render); the tooltip's double rebuild per completed inspect is coalesced (`SetUnit calls=2` → `1`); the watchdog's documented 3s window now actually runs and counts (the old early branch fired at ~1.8s and left `timeouts` permanently 0); the pending slot is released only by its own answer (a foreign `INSPECT_READY` used to drop a request in flight: `ready 0 -> 0`); `GetSpecialization` no longer invents spec 1 for an uncached unit; the unresolved-unit portrait branch no longer inverts both halves of its contract (unproven = no-op, proven-different = teardown; previously a `Hide()`+`Show()` per Classic render and a stale mesh left visible for a proven change); `lib.inspectSuccessTime` deleted as write-only state with a comment describing a hysteresis that no longer existed; the sound-kit half of the guard now has a counter and `lastError` is labelled for what it is (only set on a *raise*, never by a refusal); `noteSuppressedRefusal`'s unused parameter removed.
- **Test integrity — the recurring failure mode of this repo, found twice more.** `tooltip_test`'s "hovering a player NEVER auto-inspects" was green because the mock leaves `InspectFrame` shown, so the library issued **zero** requests for the whole run; it would have passed with the request path deleted, and it only ran on the two pipeline clients. It now asserts the real contract — hovering DOES inspect, for the hovered unit, ≤1 request per five renders — on all five, through each client's own delivery. The orphan-GUID portrait assertion drove a *proven different* GUID and asserted the portrait stayed shown, i.e. it pinned the stale-mesh bug. Both corrected, both mutation-proven. The mock also gained a controllable clock (with no `GetTime` the library reads 0 for every timestamp, so its pacing gate can never open twice in a run — which is what made the hover block pass on one family and fail on the other).
- **Deferred, with rows in `bench/OPEN-ITEMS.md`:** the `GetScore` per-render memo (17 — the largest remaining saving, deliberately out of a release that is about to be tested), event-driven nameplate discovery (18), bounding `lib.cache` (19), and the unwired `SetScanEnabled` (20).
- **Verification:** main harness 54/54, Extras 42/42, `detect_test` on lua5.1/5.4/luajit, `luacheck` at its baseline (the two additions introduced no new warnings). Eight mutations run for the new assertions this pass, plus the nine from the guard work.
- **Still owed:** the live pass. Nothing here has run in a client — the operator's five-client test is the next step, and the two numbers to read are `probe errors suppressed` (should climb on Era) and `learned max range` (should settle).

## 2026-10-14 (6) — Correction: entry (5) overstated the mechanism; the guard rebuilt on mirror evidence after four audits

- **What entry (5) got wrong.** It recorded the mechanism as VERIFIED: "a refused `CanInspect(unit)` … the client answers the *query* by displaying the engine UI error". That is **ASSUMED**, not verified. Four mirror-only audits (explorer, two oracle passes, one full API inventory) agree on the split: the mirror shows the **sink** (`Blizzard_UIErrorsFrame/Classic/UIErrorsFrame.lua:140-146` — `AddMessage(message, r, g, b, 1.0, messageID)` then `GetGameMessageInfo` → `C_Sound.PlayVocalErrorSound`), and it shows Blizzard's own inspect procedure on every branch (`CanInspect(unit, true)` → `NotifyInspect(unit)`, no range check). It shows **no producer** for an inspect refusal in any Lua on any branch, and it cannot say whether the message arrives synchronously or by event dispatch. The evidence leans to event delivery: `UIErrorsFrame` consumes `UI_ERROR_MESSAGE` through `OnEvent`, and Blizzard's own suppression of these messages is event-level (`Blizzard_ChatFrameBase/Shared/SlashCommands.lua:1305-1310`).
- **Consequence that mattered most:** the first version of the guard only swallowed while our own call was on the stack. Under event delivery that arm is dead, and the ordinary hover — a refused query with no request outstanding — would still display. The audit called it "the worst possible outcome: half-works, sometimes".
- **Rebuilt (Era only):** a short **attribution window** (0.5s) armed by every probe, plus the outstanding-request window; the sink swallows an inspect refusal arriving either synchronously or inside a window, so the unanswered sync-vs-async question stops being load-bearing. Matching is by the `errorName` `GetGameMessageInfo` returns (never literal English; never `_G.ERR_*`, which appears nowhere in the mirror). It refuses to swallow when the message carries no `messageID` (SYSMSG), when `InspectFrame` is shown (the player's own `/inspect`), or outside a window.
- **Also fixed, each found by an audit rather than by the suite:** non-range refusals were teaching a range ceiling (a `ERR_INVALID_INSPECT_TARGET` at 5yd would have blocked every unit at 5yd+ for the session) — now only `ERR_OUT_OF_RANGE` teaches; the sound latches armed both ids, leaving one unconsumed that could eat an unrelated sound — now only the id the client actually plays, cleared on use and on the next frame; `pendingRefusal` was released by unrelated events — now only by the answer to our own request; and `requestInspectImpl` was still query-first, which the mirror-contradicted comments claimed otherwise.
- **Comment corrections (the audits' list):** "index 1 is used by NO button on any branch" is false — index 1 is the **achievement-comparison** button on Wrath/Retail; "CheckInteractDistance(unit,1) is what Blizzard's unit-popup buttons and its inspect flow consult" is false — the popup consults it only for buttons that declare a distance, and the inspect button is exempt; the "~28 yard" figure, the `NotifyInspect` "raises inside the call" claim, the `checkedDistance` reason, and "GetNumTalentTabs is a Blizzard_DeprecatedSpecialization shim" were all unsupported and are corrected.
- **Evidence.** `bash Tests/harness/run_all.sh` — 54/54, and `detect_test` passes under lua5.1/5.4/luajit; `luacheck` clean on the three changed files (one pre-existing documented warning in the harness). The guard now has tests for the async shape, the classification, the sound latches, the install retry, the `InspectFrame` guard and the unnamed case — **six mutations, each reverted and each turning the matching assertion red**.
- **Still open, and this is the honest state:** the producer is unattributed; the learned ceiling and the 20/40 pre-filter are placeholders until a client measures itself (`learned max range` in `/tacotip diag`); and none of it has been run in a live client. Do not read entry (5) as the last word — this one supersedes its mechanism paragraph.

- **The mechanism (VERIFIED — this repo plus the mirror).** On Classic Era a refused `CanInspect(unit)` is not silent: the client answers the *query* by displaying the engine UI error and playing the spoken error ("you're too far away"). The refusal arrives through `UI_ERROR_MESSAGE` → `UIErrorsFrame`, a different frame from the call stack, so no `pcall` could ever see it — and because `CanInspect` ran BEFORE the distance gate in both `lib:CanInspect` and `requestInspectImpl`, every gate the previous five releases wrapped around `NotifyInspect` was guarding the wrong call. That is why each of them read as "nothing changes".
- **Where the fix was hiding.** `OLD/Libs/LibClassicInspector/LibClassicInspector.lua:3329-3365` — the library this project replaced — detours `CanInspect`, arms on the one-argument form, and swallows `ERR_UNIT_NOT_FOUND` / `ERR_INVALID_INSPECT_TARGET` / `ERR_OUT_OF_RANGE` plus the vocal error. The rewrite dropped it. Mirror corroboration, all three classic branches byte-identical after line-ending normalisation: `Blizzard_UIErrorsFrame/Classic/UIErrorsFrame.lua:142-146` (`GetGameMessageInfo` → `C_Sound.PlayVocalErrorSound`), `Sound_EnableErrorSpeech` present, and the `LE_GAME_ERR_OUT_OF_RANGE` throttle entry commented out on classic while active on `live`.
- **Done, Classic Era only by design.** Gate reordered (distance first, so an out-of-range unit is never asked about); probe guard added (LibDetours detour on `UIErrorsFrame:AddMessage` and the sound APIs, armed only around the library's own three probes); and the swallowed refusal is fed to `noteInspectRejected`, which finally arms the per-unit cooldown, the state-based out-of-range mark and the per-family learned ceiling that existed but was starved of input. TBC Anniversary (`WOW_PROJECT_BURNING_CRUSADE_CLASSIC`, 5), Titanforge (`WOW_PROJECT_WRATH_CLASSIC`, 11), Forever and Retail are unchanged, and asserted so: guard not installed, query-first order, the unit is still requested.
- **Also removed.** The temporary attribution scaffolding — `lib.errorLog`, the `NotifyInspect` wrapper, the `UI_ERROR_MESSAGE` filter, the `hooksecurefunc` capture and the `/tacotip diag` attribution section. It could observe but never suppress (a `hooksecurefunc` cannot change a call), which is exactly why the operator saw "nothing changes" while the counters climbed.
- **Evidence.** `bash Tests/harness/run_all.sh` → 54/54; `TacoTip_Extras` → 42/42; `luacheck` clean on the three changed files (the single harness warning is the documented `unpack` one). Five mutations each turned the suite red and were restored: installer unscoped (four clients fail), Era reverted to query-first, recording removed (**601 re-probes** over ten simulated minutes — the reported spam, reproduced), over-broad swallow (unrelated and player-requested messages eaten), voice latch removed.
- **Open / limits.** Nothing has been run in a live client. The engine's real inspect limit per client is C-side and still unmeasured — but the client now measures itself and `/tacotip diag` prints it as `learned max range`; the next release should set `NEARBY_ASK_YARDS` from that number instead of the 20/40 assumption. The `load_test` Classic `NineSlice` mock and the never-cleared `currentUnitGUID` remain as they were.

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
