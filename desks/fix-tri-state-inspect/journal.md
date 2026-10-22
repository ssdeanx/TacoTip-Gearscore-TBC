# fix-tri-state-inspect — Journal

## 2026-10-20 — Desk opened
- **Purpose:** make the inspect queue's `lib:DoInspect` answer an explicit three-state (`false` = not inspected, `"queued"` = accepted but pending, `true` = data ready) and make the tooltip's inspect trigger key off it instead of discarding the answer.
- **Scope:** `Libs/LibForeverInspector/LibForeverInspector.lua` (the answer), `main.lua` (the one caller), `Tests/harness/detect_test.lua` + `Tests/harness/tooltip_test.lua` (pins), `CHANGELOG.md` (one bullet in the existing `## [0.8.4]` section). `TacoTip_Extras/` read-only; no `.toc`/version/README/bench changes.
- **Next step:** verify the state machine before → after, and the revert-to-fail proofs for each pin.

## 2026-10-20 — The three-state contract landed
- **Worked on:** `lib:DoInspect` now answers `false` (not inspected) / `"queued"` (accepted, pending) / `true` (data ready) and **publishes** the names as `lib.inspectStates` (`LibForeverInspector.lua:4987-5106`). The tooltip trigger reads the answer instead of discarding it and records it on `tooltip._tacoTipState.inspectState` (`main.lua:36-52`, `:2056-2107`); the record is cleared when a different unit is rendered (`:2034-2040`).
- **Why the names are published:** the caller compares against `CI.inspectStates`, so the contract has ONE home. A library that publishes none answers with the old plain boolean, where `true` meant "accepted" — that answer is treated as pending, never ready (`main.lua:2097-2104`).
- **State machine before → after:** refused → `false` → `false` (unchanged); fresh cache → `true` → `true` (unchanged); request dispatched → `true` → **`"queued"`**; unit enqueued → `true` → **`"queued"`**; unit already queued → `true` → **`"queued"`**; request refused → `false` → `false` (unchanged). The library's OWN consumers (`scanCandidate` `:5274-5278`, `scanResolvedUnit` `:5337-5352`) read the answer for TRUTHINESS only, so they are byte-for-byte unaffected.
- **Current state:** green everywhere. `bash Tests/harness/run_all.sh` → 71/71 on lua5.1, lua5.4 and luajit; `luacheck .` → 0 warnings / 0 errors in 88 files; `bash Tools/verify_release.sh` → PASS; `bash TacoTip_Extras/Tests/harness/run_all.sh` → 42/42 (Extras never calls `DoInspect` — it only registers the library's callback through `Adapter.GetInspector`).
- **Revert-to-fail (on copies under `/tmp/opencode`, never in the tree):** library reverted to the plain boolean → 3 reds in `detect_test` ("an accepted unit is PENDING", "a unit that waits its turn is PENDING too", "a unit that is already queued is still PENDING"); caller reverted to the discarded result → 5 reds in `tooltip_test` on ALL five clients; published names removed → 1 red in `detect_test` + 4 reds in `tooltip_test` (the caller then mis-files `"queued"` as refused and `true` as pending).
- **Also learned (not a dead end, but a note):** the harness's `run()` reloads LibStub, so each `run()` is a FRESH library instance — `lib.clockAvailable` and the family flags are per-`run()`, not per-process. A pin that needs a clock must pass `GetTime` in ITS OWN env.
- **Observation for another lane (not touched, out of scope):** `Tests/harness/README.md:12` still says "70 invocations" while the runner now runs 71 (a concurrent desk added `specname_test.lua`). Not this desk's file.
- **Next step:** none — the contract change is complete and verified. If a later change makes the caller ACT on the recorded state, the pins already prove the pending/ready split holds.

## 2026-10-20 — [signal:done] the three-state contract is landed and verified
- Library: `lib:DoInspect` answers `false` / `"queued"` / `true` and publishes the names (`lib.inspectStates`).
- Caller: the tooltip's inspect trigger reads the answer and records it per tooltip; a queued unit is pending, never ready.
- Pins: 7 new library checks (`detect_test`) + 10 new caller checks (`tooltip_test`, run on all five clients) with three revert-to-fail proofs.
- Verified: 71/71 on lua5.1/5.4/luajit, luacheck 0/0 in 88 files, verify_release PASS, Extras 42/42.
- Signal: `desks/fix-tri-state-inspect/.signals/2026-10-20T15-57-00Z.json`.
