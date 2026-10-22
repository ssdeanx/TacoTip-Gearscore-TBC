# Oracle audit — Stage 2 storage hygiene + wire-diet amendment (read-only)

- **Date:** 2026-10-18
- **Desk:** `audit-stage2` (read-only; no production/test/changelog edits made)
- **Spec:** `bench/audits/2026-10-18-extras-rank-storage-expansion.md` §6.2 Stage 2 (+ §6.3 budget, §6.4 all-client) and §3 storage sections
- **Revision read:** working tree with section1-delivery (Stage 1), section2-storage (Stage 2),
  section2b-wire-diet (diet), tier-a-browser (Tier A) and locale-tier-a-keys all landed,
  uncommitted. **No Stage-3 hunks were live at read time** (`grep` for
  `guild`/`pvp`/`arena`/level-fields in `RankDB.lua`/`RankSync.lua` returns only
  prose/comments; the `section3-cheap-fields` desk does not exist yet). Stage-2/diet
  findings below stand with no Stage-3 overlap to name.
- **Evidence labels (CAIRN.md):** `[V]` VERIFIED (read in source or produced by a command
  I ran), `[A]` ASSUMED (say what would verify), `[U]` UNKNOWN.
- **Harness state at this audit:** `bash TacoTip_Extras/Tests/harness/run_all.sh` →
  `TOTAL 42 invocations: 42 passed, 0 failed` on lua5.1/lua5.4/luajit `[V]` (re-ran);
  `LINT=1` → `Total: 0 warnings / 0 errors in 26 files`, `luacheck exit=0` `[V]` (re-ran).
  Flagship `classic_era` profile: **334 checks, 0 failed**; `retail`/`forever`: **345**;
  `rankbrowser_test.lua`: **136 checks, 0 failed** `[V]` (ran each directly).

---

## 0. Verdict

**Stage 2 storage hygiene: PASS. Wire diet (versioned stride): PASS.** All five §6.2
Stage-2 items are implemented as specified and pinned by checks that fail on pre-Stage-2
behavior; the diet stride is exactly `R;1;guid;name;classID;gs;ilvl;timestamp;specID`
(`WIRE_VERSION="1"`, `RECORD_FIELDS=9`), old strides are refused + counted, and the
production tree contains **zero** `WHISPER` send sites. No blocker, no major in the new
work. Findings are minors (pin-precision ×2, untested-but-implemented corners, stale
changelog line-refs inherited from Stage 1 and worsened by the diet's line shifts,
byte-claim fixtures stated `ASSUMED`).

**Changelog accuracy: PASS with a minor.** Both subsections ("Storage hygiene (Stage 2)",
"Wire diet (versioned stride)") match code, and every Tier-A amendment claim checked
holds (eleven-locale `LB_*` parity, per-locale `CLASS_EVOKER` values, 136-count,
locale-layer paragraph). The only inaccuracy carried forward is stale `file:line` refs
in the older `[1.2.3] Fixed` clock section (§5.3).

**Stage-1 carry-forward:** the whisper **BLOCKER is resolved** by the diet (deleted end
to end, replaced by the counted skip the Stage-1 oracle prescribed). Four Stage-1
majors/minors are confirmed still open and still correctly described (§5); nothing was
re-audited beyond confirming open/closed status.

---

## 1. Stage 2 item-by-item (spec §6.2 Stage 2, items 1–5)

### The visible/ordering contract (what the engine must preserve)

The amortized cap keeps the **identical caller-visible contract** as the pre-Stage-2
per-insert scan it replaces:

1. The visible set never exceeds `MAX_CAPACITY` (20000) rows per realm.
2. Evictions take the **oldest timestamp first** (GUID as stable tiebreak).
3. The reported count (`entryCount[realmKey]`) **always equals the visible set**.
4. Age pruning (60-day default) is orthogonal and stays in `PruneStaleRecords`.
5. A forward-replace (same GUID, non-decreasing timestamp) never evicts newer data —
   the stale heap candidate re-files with the live timestamp instead.

The engine (`RankDB.lua:37-140`) preserves it: `entryCount` seeded once per session
with a single `pairs()` walk (`:298-304`), `+1` on a new GUID / `-1` per eviction
(`:311-313`, `:377`, `:385`); a lazily-built smallest-first heap (`ensureOldestHeap`,
`:123-140`) whose popped candidates are validated against the live row — absent means
already pruned (skip), mismatched timestamp means re-file (`:378-382`), match means
evict (`:384-385`); wholesale removals rewrite the bookkeeping exactly
(`PruneStaleRecords :632-633`, `PurgeDatabase :699-710` via `forgetRowBookkeeping`).
`[V]` by reading.

### 1.1 Item 1 — login prune — IMPLEMENTED AND PINNED `[V]`

- Deferred via `scheduleOneShot(0, cb)` (`Core.lua:176-188`); the once-arm
  (`loginPruneDone = true`) is set by the first **executed** callback, so a client whose
  `C_Timer` never fires retries on the next `PLAYER_ENTERING_WORLD` instead of burning
  the once. The PEW branch runs it ahead of the scan (`Core.lua:886-887`).
- `PruneAllRealms` (`RankDB.lua:649-687`) prunes each realm under the given limits, then
  deletes keys the prune emptied (`:678-682`, read off the exact `entryCount`) plus any
  non-table junk key (`:669-672`).
- Pinned: stale removed / fresh kept / realm-with-rows kept / emptied realm key deleted /
  once-per-session (`load_test.lua:3777-3795`). The key-deletion check correctly precedes
  any `GetRecord` on that realm (`getDB` resurrects emptied keys on read — the test
  comment at `:4048-4050` names the trap). `[V]`
- Untested corner (minor, §4.3): the non-table-junk deletion arm has no seeding check.

### 1.2 Item 2 — amortized cap — IMPLEMENTED AND PINNED `[V]`

- Pinned: first crossing evicts exactly row 0 (`load_test.lua:3839-3841`); ten crossings
  evict exactly rows 0–9 (`:3865-3871`); forward-replace re-files and the next-oldest
  evicts (`:3886-3896`); count identity `visible == rows == MAX_CAPACITY` through
  replacements, re-crossings and a wholesale prune (`:3903-3913`). The re-file branch is
  genuinely exercised (reordered ahead of the wholesale prune, per the storage journal).
  `[V]`
- Untested corner (minor, §4.3): timestamp ties never seeded, so the GUID-tiebreak arm
  (`heapLess`, `RankDB.lua:82-87`) executes in production but never in the harness.

### 1.3 Item 3 — dead-field write-stop, read tolerance — IMPLEMENTED AND PINNED `[V]`

- `ValidateRecord` (`RankDB.lua:209-276`) writes `classID`/`specID` (floored,
  non-negative, 0 when unknown, `:250-258`) and no longer writes `source`/`specIcon`
  (`:259-263`); `realm` is not written at all (diet: no realm anywhere). Reads stay
  tolerant: legacy rows keep every field they carry and keep ranking; inbound records
  carrying dead fields are accepted with the values ignored.
- Pinned: dead-carrying inbound accepted but dropped (`load_test.lua:4003-4014`);
  pre-hygiene row keeps ranking and keeps its dead fields (`:4027-4035`); legacy
  `classID` rides the wire and derives its token (`:4037-4040`). `[V]`

### 1.4 Item 4 — realm routing + scan gate — IMPLEMENTED AND PINNED `[V]`

- Inbound records file under the **local** realm through default routing (`StoreRecord`
  ignores `record.realm` entirely — `getDB(realm)` with `realm == nil`,
  `RankDB.lua:284-288`); the explicit-realm argument names a table only for direct
  callers. Per-realm keying, login prune and cap all still operate per-realm. `[V]`
- Scan gate (`RankSync.lua:525-549`): only a positive `UnitIsSameServer == false`
  verdict (via a `UnitTokenFromGUID` unit) skips; anything undecidable files, keeping
  prior behavior. The skip is counted (`scanForeignRealm`, `:556`) and surfaced in
  `/ttgsdebug` (`Core.lua:687`). `[V]`
- Pinned: every inbound shape files locally (`load_test.lua:3943-3963`), wire-filed rows
  carry no faction (`:3964-3968`), foreign scan does not file and the skip is counted
  (`:3984-3991`). `[V]`

### 1.5 Item 5 — TOO_LARGE — IMPLEMENTED AND PINNED `[V]`

- Handler registered in its own pcall (`Core.lua:857-870`); fires `PruneAggressive`
  (`RankDB.lua:695-697` = `PruneAllRealms(7, MAX_CAPACITY/2)`) **only** when the payload
  addon name is ours, with no once-guard so it re-arms on every occurrence (the failing
  write must stop being too large before the NEXT logout). `[V]`
- Pinned: deletes emptied realms, prunes past the 7-day window, keeps rows inside it,
  ignores foreign add-on names, re-arms (`load_test.lua:4051-4073`). `[V]`

---

## 2. Wire diet verification

| Requirement | Status | Evidence |
|---|---|---|
| Wire is exactly `R;1;guid;name;classID;gs;ilvl;timestamp;specID` | ✅ `[V]` | `WIRE_VERSION="1"` (`RankSync.lua:165`), `RECORD_FIELDS=9` (`:192`), serializer `:167-182`; harness asserts byte-for-byte (`load_test.lua:3931-3934`) |
| Unknown version → counted `versionReject`, never raised | ✅ `[V]` | `DeserializeRecord :229-234`, `recordFromParts :758-761`; 10-field, 11-field and unknown-token refusals + `+3` count check (`load_test.lua:3133-3142`) |
| Old 10-/11-field refused | ✅ `[V]` | Same checks; 11-field is the diet-specific pin (pre-diet code accepts it) |
| Faction/realm/class-string/spec-name off the wire | ✅ `[V]` | Serializer carries none; `DeserializeRecord` returns none (`:237-247` — only `class` derived); harness asserts absence (`load_test.lua:3070-3073`) |
| Zero whisper send sites | ✅ `[V]` | `grep '"WHISPER"' TacoTip_Extras/*.lua` returns only test assertions-that-absence plus changelog prose; `RankSync.lua` contains no `WHISPER` at all |
| `answerNoTransport` counted skip replaces fallback | ✅ `[V]` | `RankSync.lua:694-702`; three pins (dead-channel, unresolvable-sender, WHISPER-query) assert zero sends on **every** transport + `+1` count (`load_test.lua:3605-3648`) |
| classID/specID derived at render, graceful Classic degradation | ✅ `[V]` | `CLASS_FILE_BY_ID` + `classTokenOf` (`RankBrowser.lua:106-125`), `specDisplayOf` via engine `GetSpecializationInfoByID` behind pcall with stored-string fallbacks (`:133-147`, `:486-499`, tooltip `:373-381`, icon `:442-443`); engine path + silent-absence path both pinned (`rankbrowser_test.lua:1223-1284`) |
| Faction storage-only-optional + tooltip omission | ✅ `[V]` | Only `Alliance`/`Horde` kept, else nil (`RankDB.lua:238-241`); tooltip renders the line only when present (`RankBrowser.lua:393-395`); omission + presence both pinned (`rankbrowser_test.lua:1236-1255`) |
| Byte claims | ⚠️ `ASSUMED` (direction `[V]`) | See §2.1 |

### 2.1 Byte claims — ASSUMED with directional verification

The changelog's exact fixtures ("typical", "validator-max") are not in the tree, so the
numbers `75→48 B`, `S 84→57`, `400→227`, `S 236`, `T pair ~109` are `ASSUMED` as
stated. What I verified with a throwaway re-implementation of the exact serializer
logic: a short harness-style record serializes to **46 B** (claimed 48); my
bounds-max record to **228 B** (claimed 227) and **237 B** as `S` (claimed 236) —
**inside the 240-byte door either way**, so the load-bearing claim ("even the largest
sanitized row now fits the door instead of being refused at enqueue") holds `[V]`.
Direction and magnitude vs the old stride confirmed (old-style typical **66 B**,
bounds-max **345 B**; exact old fixtures unknown, hence the gap to claimed 75/400).
A two-record `T` with short fixtures lands at **90 B** — comfortably inside the door,
consistent with "near 109". The digest-split path is therefore nearly unreachable with
real diet records, but remains pinned by the artificially-fat digest phase. `[V]` suite
green; `[A]` exact-fixture reproduction.

### 2.2 Pin-precision note (minor)

Two refusal checks pass on pre-diet (Stage-2 11-field) code **in isolation**: the
10-field refusal (`load_test.lua:3133-3134` — both strides refuse a 10-field payload)
and the unknown-version refusal (`:3137-3138` — a 9-field `R;9;…` payload fails the
11-field count gate too). Diet-specificity of the group is carried by the paired
`versionReject +3` count check (`:3140-3142`, fails pre-diet — no such bucket) and the
11-field refusal (`:3135-3136`, pre-diet code accepts it). Recommend rewording the two
names to state they pin refusal *and* counting as a group, or folding them into the
count check's detail string. Minor: the behavior that matters is pinned where it
matters. No check name was found asserting something its body does not assert.

### 2.3 EVOKER + raw-token fallback

- The EVOKER check **does** assert the localized name: `evokerEntry.text == "Evoker"`
  (`rankbrowser_test.lua:705-707`, enUS loaded) `[V]`.
- The raw-token `or` fallbacks (`RankBrowser.lua:497` `or classToken`, `:1245`
  `or className`) are **defensive + unpinned**: with all eleven locales carrying every
  `CLASS_*` key, no test removes a key to force the fallback arm. Correctly harmless —
  noted for the record, not a gap worth a test on its own.

---

## 3. Changelog accuracy

### 3.1 "Storage hygiene (Stage 2)" (`CHANGELOG.md:236-300`) — accurate `[V]`

- Login sweep (deferred `C_Timer.After(0)`, once-arm by executed callback, retry on next
  rise, deletes emptied keys + junk keys): matches `Core.lua:176-188`,
  `RankDB.lua:649-687`. "34 named checks": exactly **34** `check(` calls in the Stage-2
  block (`load_test.lua:3729-4077`) `[V]`. "334 checks flagship era (345 retail/forever)":
  re-ran both profiles, exact `[V]`. `LINT 0/0` `[V]`.
- Cap paragraph (counter seeded once, lazy heap, oldest-first, re-file, stale-skip,
  count == visible set): matches `RankDB.lua:37-140,298-390` `[V]`.
- Render-keys paragraph (`classID`/`specID` floored, `source`/`specIcon` dropped,
  tolerance): matches `:209-276` `[V]`.
- Realm paragraph (no realm on wire, local filing, explicit-realm for direct callers,
  scan gate positive-false-only + counted, faction optional): matches
  `RankDB.lua:284-288`, `RankSync.lua:525-559`, `RankDB.lua:238-241` `[V]`.
- TOO_LARGE paragraph (7-day / half-cap, deletes emptied keys, re-arms, own-name-only):
  matches `RankDB.lua:695-697`, `Core.lua:857-870` `[V]`.

### 3.2 "Wire diet (versioned stride)" (`CHANGELOG.md:302-349`) — accurate, bytes `ASSUMED`

- Stride layout, refusal + `versionReject` counting, no compat shims: matches
  `RankSync.lua:165-247,754-773` `[V]`.
- Off-wire list (faction, realm, class-string, spec-name, whisper path deleted end to
  end): matches serializer + zero-`WHISPER` grep `[V]`.
- Spec-as-id + `GetSpecializationInfoByID` "global on all five branches, verified in
  `SharedXML/UnitUtil.lua`": confirmed the global is **called** in `UnitUtil.lua` on all
  five `origin/` branches (classic_era/anniversary/titan `:50,60,69`,
  forever/live `:51,61,70`) `[V]`; whether it returns classic talent-tree names for a
  numeric specID on classic branches is `[A]` — carried to the in-game checklist (§6.4).
- Storage-tolerance + browser-fallback paragraph: matches `RankDB.lua:209-276`,
  `RankBrowser.lua:373-381,442-443,486-499` and the 14 diet checks in
  `rankbrowser_test.lua:1199-1286` `[V]`.
- Savings numbers: `ASSUMED` per §2.1 (direction + door-fit `[V]`).

### 3.3 Tier-A amendments — all hold `[V]`

- "`LB` keys translated in all eleven locales": all 11 files carry `LB_TIP_CLICK_GEAR`
  and `LB_SCAN_COMPLETE` with non-English values (34 `LB_*` keys each — parity with
  enUS, so the Stage-1 "enUS-only + fallback" state has been superseded) `[V]`.
- "`CLASS_EVOKER` values per locale": deDE `Rufer`, frFR `Évocateur`, esES/esMX
  `Evocador`, itIT `Evocatore`, koKR `기원사`, ptBR `Evocador`, ruRU `Пробудитель`,
  zhCN `唤魔师`, zhTW `喚能師`, enUS `Evoker` — every value matches the changelog
  listing `[V]`.
- "80 → 136 checks": `rankbrowser_test.lua` runtime is exactly 136 `[V]` (static
  `grep -c 'check('` = 137 — one occurrence lives on a non-executed path; trivial
  static-vs-runtime drift, not a claim error).
- Locale-layer paragraph (11 files in TOC, no stray keys, `%d`/`%s` parity,
  differs-from-English): pinned at `load_test.lua:1558,1587,1611,1632`, suite green
  `[V]`.

---

## 4. Severity-ranked findings (new work only)

**No blockers. No majors.** All findings minor:

1. **(minor) Two diet refusal checks pass on pre-diet code in isolation** (§2.2) —
   10-field and unknown-version refusals; group-level diet-specificity holds via the
   `versionReject` count check and the 11-field refusal. Reword or fold; no behavior gap.
2. **(minor) Junk-realm-key deletion arm untested** — `RankDB.lua:669-672` (non-table
   junk under `ranks`) has no seeding check; every other `PruneAllRealms` arm is pinned.
3. **(minor) Heap GUID-tiebreak untested** — ties never seeded, so `heapLess`'s
   `guid` arm (`RankDB.lua:82-87`) never fires in the harness. Deterministic in code;
   one tied-timestamp pair would pin it.
4. **(minor) `specID` has no upper bound in `sanitizeID`** (`RankDB.lua:250-256`) — a
   giant numeric specID serializes long, but the 240-byte enqueue door catches it
   (counted `enqueueOversize`). Safe by defense-in-depth; capping at render-width
   would make validator-max a true maximum.
5. **(minor) Byte-claim fixtures not reproducible from the tree** (§2.1) — direction
   and door-fit verified; keep the numbers labeled measured-standalone or check in the
   throwaway fixture.
6. **(minor) EVOKER `or`-fallback unpinned** (§2.3) — defensive-only while all locales
   are complete; no action needed.

---

## 5. Stage-1 carry-forward (open/closed status only — no re-audit)

| Stage-1 oracle item | Status now |
|---|---|
| **BLOCKER §1: whisper fallback must go** | ✅ **RESOLVED** — zero `WHISPER` send sites; resolver + ring + call site + 5 debug counters deleted; 3 skip pins; changelog rewritten; `/ttgsdebug` carries `answerNoTransport` |
| §2.1 major: RAID / INSTANCE_CHAT / CHANNEL-active answer arms unpinned | ⏳ **STILL OPEN**, narrowed — WHISPER arm now pinned as skip; the other three transports still have no answer-path check |
| §2.1 major: end-to-end `CHAT_MSG_ADDON`→`handlePayload` threading unpinned | ⏳ **STILL OPEN** — no `fireEvent("CHAT_MSG_ADDON", …)` in `load_test.lua`; harness still calls `HandlePayload` directly |
| §2.2 major: INSTANCE_CHAT never exercised | ⏳ **STILL OPEN** — zero `INSTANCE_CHAT` occurrences in `load_test.lua` |
| §2.2 minor: sustained-throttle 3-strike dead-marking unpinned | ⏳ **STILL OPEN** — only single-throttle→requeue pinned |
| §2.2 minor: probe queue-bypass unpinned | ⏳ **STILL OPEN** |
| §2.3 major: legacy-global / `sendNoInfo` path unpinned | ⏳ **STILL OPEN** — harness always mocks `C_ChatInfo.SendAddonMessage` (`load_test.lua:3206`) |
| §2.3 minor: `sendOther`/`sendError`/`sendChannelThrottle`/`enqueueOversize` unpinned | ⏳ **STILL OPEN** — no direct >240 `Enqueue` check (comment-only mention `:3454`) |
| §2.3 minor: `/ttgsdebug` print lines never asserted | ⏳ **STILL OPEN** — buckets asserted via `GetDebugState`, not the printed lines |
| §2.4 minor: outbound 6-hex id shape never asserted | ⏳ **STILL OPEN** |
| §2.4 count drift ("16 new named checks") | ✅ **RESOLVED** — Stage-1 paragraph no longer claims a number |
| §3.1 silent-skip accounting | ✅ **RESOLVED** — `answerNoTransport` is exactly the prescribed fix |
| §4.1 Tier-A claims | ✅ **STAND** (re-verified where touched by diet: EVOKER, 136-count, locale layer) |
| §4.2.1 stale scan-complete comment | ⏳ **STILL OPEN** — `RankBrowser.lua:559-560` still says the status line "carries no locale key yet … ships English", but `LB_SCAN_COMPLETE` exists and is used at `:577` |
| §4.2.2 stale changelog line refs | ⏳ **STILL OPEN, worse** — `CHANGELOG.md:55-65` cites `RankDB.lua:125/219/393` (actual `209/409/591`), `RankBrowser.lua:104` (actual `149`), `RankSync.lua:897` (actual `902`); `Scanner.lua:173` now names `queueRankSync` but the code is `QueueInspectRecord` |
| §4.2.3 count drifts | ✅ **RESOLVED** — 34/34 exact, 136 runtime exact (137 static occurrences noted in §3.3) |
| §5 in-game items 1–6 (results per family, CHANNEL on Anniversary/Titan, INSTANCE_CHAT delivery, join timing, throttle tuning, GetServerTime skew) | ⏳ **CARRIED** to §6 |
| §5 item 7 (whisper-path deletion) | ✅ **RESOLVED offline** (zero-send assertions); "no offline message in game" trivially satisfied — no whisper sends exist |

All "still open" items above were confirmed by direct grep/read this session and are
described exactly as in the Stage-1 report.

---

## 6. Implemented-but-untested + in-game-only checklist additions

Implemented but never executed in any harness (all minor; production code read clean):

- Login-prune **deferral timing** itself — the harness installs a synchronous
  `C_Timer.After`, so `scheduleOneShot(0, …)` off-the-loading-screen behavior is
  structural-only offline; confirm one cold login per client shows no hitch.
- Junk-realm-key deletion (§4.2), heap tiebreak (§4.3), 3-strike throttle death,
  probe-at-full-queue, legacy-global `sendNoInfo`, `sendOther`/`sendError`/
  `sendChannelThrottle`/`enqueueOversize` buckets, `/ttgsdebug` print text, 6-hex
  outbound id shape, RAID/INSTANCE_CHAT/CHANNEL-active answers, end-to-end
  `CHAT_MSG_ADDON` threading, EVOKER `or`-fallback, TOO_LARGE eviction *order*.

New in-game-only items from Stage-2/diet scope (Stage-1 §5 items 1–6 carried, not
repeated):

1. `[A]` Numeric-`specID` render on classic branches — `GetSpecializationInfoByID` is
   called in `UnitUtil.lua` on all five, but whether it returns the TBC/Wrath talent
   names for a numeric id on Anniversary/Titan (vs nil → stored-fallback path) needs
   one lookup per classic client.
2. `[A]` `UnitIsSameServer` verdict values on Era for genuine cross-realm units —
   harness mocks `false`; confirm a real `false` (not nil/error) in a battleground.
3. `[U]` `GetNormalizedRealmName` space-stripping per branch (spec §8) — decides
   whether realm-keyed tables can ever fork on spaced realm names.
4. `[U]` Real `SendAddonMessageResult` values per family for the diet stride (door-fit
   now means fewer `enqueueOversize` by construction — confirm the success bucket
   dominates on each client after a resync).
5. Stage-3 brief open questions (2000-cap/level-filter demand, guild-24-cap rule,
   per-field scan capture) stay with the Stage-3 lane — flagged here only so the
   20000-cap semantics pinned above are not silently re-litigated there.

---

## 7. Files live at read time (concurrency note)

`RankDB.lua` (711 lines, diet shape), `RankSync.lua` (978 lines, 9-field stride),
`Core.lua` (debug `:674-688`, TOO_LARGE `:857-870`, prune `:176-188`),
`RankBrowser.lua` (diet hunks limited to `CLASS_FILE_BY_ID`/`classTokenOf`/
`specDisplayOf` + tooltip/spec-column/icon fallbacks + conditional faction line —
no other browser behavior touched), `load_test.lua` (Stage-2 block `:3728-4077`,
34 checks), `rankbrowser_test.lua` (137 static / 136 runtime, diet block
`:1199-1286`), `CHANGELOG.md` (Stage 1 `:109-173`, Tier A `:175-234`, Stage 2
`:236-300`, diet `:302-349`). No Stage-3 field, stride, or browser hunk present;
`section3-cheap-fields` has no desk yet — nothing to disentangle.

---

## 8. Outcome ratings (emitted per signal-write)

- **stage2 (storage desk):** quality_rating **4** — all five items implemented per spec
  with genuinely self-caught test repairs (deleted-key read trap, heap teardown
  ordering) and an exact 34/34 pin count; deductions for untested junk/tiebreak arms
  and inherited-stale line refs. effort_to_merge **minimal**. Issues: the §4 minors
  that touch Stage-2 scope (2, 3, 4) plus carried stale refs.
- **stage2b (diet desk):** quality_rating **4** — exact stride, refusal+counting,
  complete whisper deletion with zero send sites, render fallbacks pinned both
  directions; deductions for two isolation-level pin-precision notes, unpinned
  defensive fallback, and ASSUMED byte fixtures. effort_to_merge **minimal**. Issues:
  §4 minors (1, 5, 6).
