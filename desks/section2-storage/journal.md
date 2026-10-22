# desk: section2-storage

Run id: **stage2** — Stage 2 storage hygiene (audit `bench/audits/2026-10-18-extras-rank-storage-expansion.md` §6.2), fixture set TacoTip_Extras.

---

## 2026-10-18 — [signal:done] Stage 2 complete, review-ready

- All five §6.2 Stage 2 items landed and validated; no commit, no staging (working tree stays uncommitted user work).
- Final suite: `bash TacoTip_Extras/Tests/harness/run_all.sh` = 42 invocations, 42 passed on lua5.1 / lua5.4 / luajit — 325 checks flagship era profile, 336 retail/forever, 0 failed everywhere; `LINT=1` luacheck 0 warnings / 0 errors (26 files).
- TEMP diagnostics stripped: every `BISECT`/`PRDBG`/`STUBTEST` line removed from load_test.lua and RankDB.lua; `git` diff shows no leftover prints in production files.
- Stage-1 protocol re-verified: 16 protocol checks green in every profile invocation; explicit wire measurement (standalone, real RankSync.lua on all three interpreters) — realm-tagged 11-field R = 94 bytes → S/T frames 105 B (under the 240 door); maximal sanitized fields R = 400 → S/T 411 B → refused at enqueue exactly as pre-Stage-2; ten-field payload refused, eleven accepted; realm and legacy fields round-trip.
- Tooltips killers repaired before green: the block's second PEW fire leaves the scanner pending (gen 2) — a bounded OnUpdate pump after the last fire completes it; the TOO_LARGE deleted-key check now precedes any GetRecord (getDB resurrects emptied realm keys on read); the "keeps a realm that still holds rows" check reads the row count, not the key presence.
- luacheck's one warning (deliberately-empty skip branch, RankDB.lua:356) removed by restructuring the evict-loop branch flat→nested, zero behavior change.
- CHANGELOG: `### Storage hygiene (Stage 2)` inserted immediately after the Tier A block and before the `---` — the only touched subsection.

## 2026-10-18 — [signal:checkpoint] suite reached green
- 42/42 invocations ×3 interpreters; luacheck 0/0 after the empty-branch restructure; signals JSON in `desks/section2-storage/.signals/`.

## 2026-10-18 — resume: production edits landed, test-block repairs first

All five §6.2 Stage 2 items are already landed in production code and parse clean on lua5.1/lua5.4/luajit:

1. `Core.lua` — `scheduleLoginPrune()` deferred via `scheduleOneShot(0, cb)`; once-arm (`loginPruneDone`) set by the first EXECUTED callback, so a client without usable `C_Timer` retries on the next `PLAYER_ENTERING_WORLD`; PEW branch calls it ahead of `scheduleLocalScan("entering-world")`.
2. `RankDB.lua` — amortized capacity bookkeeping (`entryCount[realmKey]` seeded once per session immediately before the write; lazy `oldestHeap[realmKey]` min-heap of `{ts, guid}`); `StoreRecord` enforces ≤ `MAX_CAPACITY` with oldest-timestamp-first eviction; `PruneStaleRecords` sets `entryCount = min(#remaining, cap)` and nils the heap; `PruneAllRealms(60, 20000)` + realm-key deletion of emptied/dead keys; `PruneAggressive()` = `PruneAllRealms(7, MAX_CAPACITY/2)` (constants `AGGRESSIVE_MAX_AGE_DAYS=7`, `AGGRESSIVE_MAX_CAPACITY=10000`); `PurgeDatabase` drops bookkeeping.
3. `RankDB.ValidateRecord` — stops writing `classID`/`source`/`specIcon`, reads stay tolerant, adds `realm` (nil ⇒ local realm, existing rows never re-filed — §2.5 migration).
4. `RankSync.lua` — wire stride 11 (`RECORD_FIELDS = 11`, serializer appends realm as field 11 empty-when-absent, deserializer strictly refuses a 10-field payload), `recordFromParts` parses field 11, per-realm routing (`getDB(realm or clean.realm)` — direct `realm` arg wins), scan-time gate `recordIsSameRealm` + `countOutcome("scanForeignRealm")` (only a positive `UnitIsSameServer == false` verdict skips; everything undecidable files — failed exactly like the harness defaults behave).
5. `Core.lua` — `SAVED_VARIABLES_TOO_LARGE` registered in its own pcall; handler fires `PruneAggressive` only when the payload addon name matches ours.

API verification (wow-ui-source): `UnitTokenFromGUID` documented on all five branches (UnitDocumentation.lua :1925 era/anniv/titan, :3296 forever, :3186 live); `UnitIsSameServer` documented on forever :2350 / live :2261 — hence feature-detect, never client-identity gating.

Baseline before Stage 2: `bash TacoTip_Extras/Tests/harness/run_all.sh` = 42/42 invocations green.

Session progress this resume:

- Stage-2 scenario block confirmed present in `Tests/harness/load_test.lua` (after `runQueryProtocol()`, before the Tooltips do-block; runs inside one closure — `runStage2` — for the chunk local budget).
- Repairs just applied: replaced the two inline-IIFE `evictShaped` detail contractions with a single `goneRows` local (`#goneRows == 10 and not evictShaped[10]` semantics, detail now prints the exact evicted row indexes); fixed the "rewrow" typo in the count-identity message; replaced the undefined `tosthingFiledCheck()` reference with a real filed-detail (`RankDB.GetRecord("Player-41-F1") == nil`); wired the previously-dead `gateBefore`/`gateAfter` snapshots into a real check that `scanForeignRealm` was counted between them (GetDebugState returns a snapshot COPY in RankSync.lua:998, so the before/after comparison is sound).
- One deeper repair: the forward-replace case (RebornZero) ran AFTER `PruneStaleRecords(capRealm, 60, 19998)` had torn down the oldest-heap, so neither the re-file branch (StoreRecord stale-candidate re-push) nor a genuine crossing stood behind the "cross after forward-replace" assertions — row 11 had already left the table via the handle. Reordered: forward-replace + J11 crossing now run while the heap is live (re-file branch truly exercised — stale candidate re-files, row 11 evicts on its own timestamp), then J12 crossing asserts the next-oldest-live eviction, THEN the wholesale-prune identity check runs last. All cap-semantics checks remain the preserved pre-Stage-2 contract, per the block header.
- load_test.lua parse-checked OK on lua5.1 / lua5.4 / luajit.

Next:

- `bash TacoTip_Extras/Tests/harness/run_all.sh` to green ×3 interpreters; `LINT=1` luacheck 0 warnings/0 errors.
- Re-run every Stage-1 protocol check explicitly (240-byte enqueue door with 11-field S/T payloads + new realm sizes, split digest, 8-char id cap, throttle requeue, whisper pins, probe/dead/reprobe) — the door must not weaken.
- CHANGELOG `### Storage hygiene (Stage 2)` inserted after the Tier A block, before the `---`.
- Checkpoint signal, done signal, final report.

No production code touched this resume; only the harness scenario block was repaired.
