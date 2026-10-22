# Audit — TacoTip_Extras rank system: mechanics, persistence, sync, and a hardening path

- **Date:** 2026-10-18
- **Desk:** operator-requested read-only audit (subagent session)
- **Scope:** `TacoTip_Extras/RankDB.lua`, `RankSync.lua`, `Cache.lua`, `Scanner.lua`,
  `Core.lua`, `Scoring.lua`, `TacoTipAdapter.lua` (score feed), `RankBrowser.lua`,
  `Tooltips.lua`, both harness files, `README.md`, `CHANGELOG.md`,
  `TacoTip_Extras.toc`; Blizzard API claims checked against
  `/home/sam/wow-ui-source` on `origin/classic_era`, `origin/classic_anniversary`,
  `origin/classic_titan`, `origin/forever`, `origin/live`.
- **Revision read:** working tree at `HEAD 0395d99`, with the uncommitted v1.2.3
  edits (README/CHANGELOG/TOC/load_test/Tooltips only — none touch the ranking
  code; `git status --porcelain` in scope section). All ranking files
  (`RankDB.lua`, `RankSync.lua`, `Scanner.lua`, `Core.lua`, `Cache.lua`,
  `Scoring.lua`, `RankBrowser.lua`) are unmodified vs HEAD.
- **Evidence labels (CAIRN.md):** `[V]` VERIFIED (read in the source or produced by
  a command I ran), `[A]` ASSUMED (say what would verify), `[U]` UNKNOWN.
- **Harness state at audit time:** `bash TacoTip_Extras/Tests/harness/run_all.sh`
  → `TOTAL 42 invocations: 42 passed, 0 failed` on lua5.1, lua5.4, luajit `[V]`.
- **Measurements** were made by loading the real `RankDB.lua`/`RankSync.lua` in a
  scratch harness under `/tmp/opencode` (not part of the repo); the scripts and
  numbers are reproducible from the transcript. No repo file was modified except
  this report.

---

## 0. Executive summary

The ranking math, validation and UI are in good shape — the harness pins them and
is green on 42 invocations. The weaknesses are not in *how ranks are computed*
but in three places:

1. **The storage engine's per-insert cost grows with the database.**
   `StoreRecord` rebuilds a full `{guid,timestamp}` table of every record on
   **every** call, and once at the 20,000 cap it also fully sorts it
   (`RankDB.lua:175-189`). Measured (Lua 5.1): **1.4 ms/insert at 5k records,
   3.3 ms at 10k, 23.2 ms at 20k**, plus an **~88 ms full index rebuild** on the
   first read after any dirtying store `[V]`.
2. **The advertised 60-day prune never runs.** `PruneStaleRecords` has no caller
   outside the tests (`RankDB.lua:389-424`; grep in §2.6), so stale rows stay in
   storage; only the index hides them, and the only deletion path that ever runs
   is the at-cap eviction in `StoreRecord`. README (`README.md:115`) and CHANGELOG
   (`CHANGELOG.md:191`) say "automatically pruned".
3. **The query/response protocol is only half-fallback.** Queries go out on
   PARTY/RAID, GUILD **and** CHANNEL, but every `S`/`T` answer is sent to the
   private channel only (`RankSync.lua:318-319, 338-339`). A peer that answered a
   GUILD query is inaudible if it is not in `ttgssync`. Responses also echo an
   unbounded inbound request id, and nothing checks the serialized size against
   the 255-byte budget the add-on itself asserts (`RankSync.lua:424-431`).

Everything else in the report is the evidence for those statements, the
structured pros/cons, and a ranked improvement path.

---

## 1. Mechanics — what the ranking is and how it is computed

### 1.1 Data flow (top to bottom)

`[V]` The ranking pipeline is **Scanner → RankSync → RankDB → consumers**, and it
does not involve `TacoTipAdapter.lua` at all: `grep -c "RankDB\|RankSync"
TacoTipAdapter.lua` = `0`. The adapter supplies scores only, via `_G.TT_GS` used
by `Scoring.baseScoreFromTacoTip` (`Scoring.lua:389-445`).

- **Record production.** A completed local scan calls
  `queueRankSync(playerGUID, "player", classToken, result, "self")`
  (`Scanner.lua:617-620`); a completed remote inspection calls the same with
  `"inspect"` (`Scanner.lua:786-789`). `queueRankSync` extracts gearScore
  (`Scanner.lua:120-127`), average item level (`129-133`), name/faction/class/spec
  (`136-171`), timestamp (`173-175`) and hands the record to
  `RankSync.QueueInspectRecord` (`Scanner.lua:176-188`).
- **Store + broadcast.** `QueueInspectRecord` stores the record, and — only when
  `StoreRecord` returns truthy — broadcasts it (`RankSync.lua:202-210`). Note the
  record broadcast is the **raw** record, not the sanitized copy returned by
  `ValidateRecord` (§3.4).
- **Inbound.** `CHAT_MSG_ADDON` → `handlePayload` (`RankSync.lua:512-516`,
  `411-442`), dispatched by leading type character:
  `R` = one unsolicited record, `Q` = query, `S` = sender's own record, `T` =
  digest of the sender's best records (`RankSync.lua:221-230`).

### 1.2 Rank computation (`RankDB.lua`)

`[V]` There is no accumulated score or Elo: **rank = position in a sorted list**.
`BuildSortedIndices(realm)` (`RankDB.lua:207-287`):

1. If `dirtyFlags[realm]` is false and both caches exist, return the cache
   (`210-212`). Otherwise rebuild.
2. Walk the per-realm table once, keeping only records whose
   `timestamp >= now - 60 days` (`219-237`). Records older than the window are
   skipped from ranks but **stay in the table**.
3. Build four index families: `all`, `alliance`, `horde`, `byClass[classToken]`
   (`222-244`). Faction "Unknown" appears in `all` and `byClass` but in no faction
   list (`225-229`).
4. Sort each list with `sortComparator` (`194-205`): `gs` desc, then `ilvl` desc,
   then `timestamp` desc, then `name` asc. Total, deterministic order.
5. Build `lookups[guid] = {overallRank, factionRank, classRank}` by walking the
   sorted lists (`246-272`), then cache both and clear the dirty flag
   (`282-284`).

`GetPlayerRank(guid, realm)` returns `overallRank, factionRank, classRank,
indices.total` (`RankDB.lua:289-301`); consumers are the tooltip rank row
(`Tooltips.lua:618`) and the browser footer (`RankBrowser.lua:773-782`).
`GetLeaderboard(realm, tab, classFilter, searchQuery)` (`347-387`) returns the
cached list itself when unfiltered (`364-366`) or a fresh filtered copy
(`368-386`); search is plain (non-pattern) substring, case-lowered
(`376-379`). `GetTopRecords(limit)` clamps `limit` to 10 and takes from the
age-filtered `"All"` list (`328-345`).

### 1.3 Dirty flags, indices, and when they pay

`[V]` `dirtyFlags[realmKey]` is set by `StoreRecord` (`RankDB.lua:170`),
`PruneStaleRecords` (`419-421`) and `PurgeDatabase` (`433`). It is cleared only by
a rebuild (`284`). Cached values are in module locals: `dirtyFlags`,
`cachedIndices`, `cachedLookups` (`RankDB.lua:33-35`).

Measured cost of the rebuild and of the cached lookup at 20,000 records:
`cold BuildSortedIndices 20000: 0.088 s`; `rebuild after one store: 0.086 s`;
`100 cached GetPlayerRank: 0.0000 s` `[V]`. So lookups are effectively free
until anything dirties the realm — any sync record, any equipment change, or the
first read after one (a tooltip hover, a leaderboard open, or `GetTopRecords`
answering a query) — at which point that read pays a full multi-list sort of up
to 20k entries.

### 1.4 Consumers

- **Tooltip rank row** (`Tooltips.lua:595-695`): renders
  `GS Rank: #N [#M Class]`; color via `Scoring.RankColor(rank, total)`
  (`Tooltips.lua:644-656`; `Scoring.lua:993-1016`), Compact swaps the class name
  for a 14px atlas icon with degradation to the name (`Tooltips.lua:671-689`).
- **Leaderboard** (`RankBrowser.lua:689-791`): fetches the filtered list
  (`695`), builds a **per-view** GearScore rank map from the filtered data
  (`buildGearScoreRanks(data)`, `702`, definition `257-267`), sorts a copy for
  display (`222-254`), and computes best-in-view for colouring (`709-718`).
  `NUM_ROWS = 12` (`RankBrowser.lua:22`).
- **Gear panel** (`RankBrowser.lua:557-659`) reads the session-only `Cache`
  via `Scanner.GetRemote` (`630-631`); nothing about per-slot gear is persisted
  (`Cache.lua:10-14`, 32 entries, 300 s freshness).

`[V]` **Rank semantics differ between surfaces under filters.** The tooltip and
footer use `GetPlayerRank` (realm-wide), but the browser's `#` column is built
from the *filtered* list (`RankBrowser.lua:695, 702`), so with a class filter on,
your row's `#` is your rank among that class while the footer still says
`#N Overall`. The harness pins the unfiltered case only
(`rankbrowser_test.lua:825`, `"the # column matches each row's own GearScore rank
after sorting by iLVL"`, under `currentClass = "ALL"`).

### 1.5 Session caches (not the rank DB)

`[V]` `Cache.lua` is a per-GUID LRU for equipment revisions/results used by the
gear panel: `MAX_ENTRIES = 32` (`10`), `FRESHNESS_SECONDS = 300` (`14`), eviction
on overflow (`114-144`), expiry to `"stale"` on read (`146-157`). It is
in-memory only. `Scanner.currentState` and pending item bookkeeping are likewise
session-only (`Scanner.lua:32-39`).

---

## 2. Persistence — exact SavedVariables shape, sizing, caps, pruning

### 2.1 Shape

`[V]` TOC declares `## SavedVariables: TacoTipExtrasDB`
(`TacoTip_Extras.toc:9`). The root is created on first use
(`RankDB.lua:58-72`) and normalised by `Core.initializeDatabase`
(`Core.lua:279-326`), which sets `root.schema = 2` (`Core.lua:322`) and is
asserted by the harness (`load_test.lua:2436-2438`).

```
TacoTipExtrasDB = {
  schema   = 2,                       -- Core.lua:322
  settings = { ... },                 -- Core.lua:309-323 (tooltip, minimap, equipmentDisplay…)
  ranks = {                           -- RankDB.getDB, RankDB.lua:58-72
    [realmKey] = {                    -- GetNormalizedRealmName() | GetRealmName() | "DefaultRealm"
      [guid] = {                      -- RankDB.ValidateRecord, RankDB.lua:141-153
        guid, name, faction, class, classID, specName, specIcon,
        gs, ilvl, timestamp, source
      },
      ...
    },
    ...
  },
}
```

`realmKey` resolution is `GetNormalizedRealmName` first, then `GetRealmName`,
then `"DefaultRealm"` (`RankDB.lua:37-56`). Both are documented API on all five
branches (`PlayerScriptDocumentation.lua`, e.g. `origin/live:540-546`) `[V]`.

### 2.2 Record fields, bounds and actual use

`[V]` From `ValidateRecord` (`RankDB.lua:104-154`):

| field | bound applied | notes / downstream use |
|---|---|---|
| `guid` | string, control/`;` stripped, ≤128, non-empty | table key **and** duplicated field (`169`) |
| `name` | ≤64 | display |
| `faction` | ≤16, then ∈ {Alliance, Horde, Unknown} | faction rank lists + display |
| `class` | ≤32, free string | class lists, filter, name colour |
| `classID` | 1..32 or 0 | **never read outside RankDB/RankSync** (grep) |
| `specName` | ≤64, may be `""` | display; empty is legitimate (test-pinned) |
| `specIcon` | **string or number, unbounded**, type-checked only (`136-139`) | gear-row icon; **not carried on the wire** |
| `gs` | 1..15000, integer-rounded | sort key |
| `ilvl` | 1..1500, rounded to 0.1 | second sort key |
| `timestamp` | 0..`now+300`, defaults to `now` | staleness, arbitration, LAST SEEN |
| `source` | ≤16, default `"sync"` | **never read outside RankDB/RankSync** (grep) |

### 2.3 Per-record size arithmetic

The repo asserts `~276 bytes/record` measured as WoW writes SavedVariables
(`RankDB.lua:10-19`, `README.md:161`). The exact serializer format (key quoting,
indentation, ordering) is engine-side and not in the UI source — `[U]` — so the
following is arithmetic under the stated assumption `[A]` (verification: look at
an actual `WTF/.../TacoTipExtrasDB.lua` after a session):

Value characters per record, typical vs validator-maximum:

| item | typical | validator max |
|---|---|---|
| guid stored twice (key + field) | ~42 | 256 |
| name | 6 | 64 |
| faction | 7 | 8 |
| class | 7 | 32 |
| classID | 2 | 2 |
| specName | 9 | 64 |
| specIcon | 0–24 | **unbounded** |
| gs | 4 | 5 |
| ilvl | 5 | 6 |
| timestamp | 10 | 10 |
| source | 4–7 | 16 |
| **values only** | **~120** | **463 + specIcon** |

Plus per-field key names (`["guid"] = …` is 4 + len(key) + 3 chars), quotes,
commas, braces and indentation. ~276 is plausible for typical rows; it is **not a
ceiling**. The capacity is a count (`MAX_CAPACITY = 20000`, `RankDB.lua:25`), not
a byte budget, and `specIcon` plus the 128-char guid arm mean a hostile or
future-version peer can store records several times the quoted size. So
`20000 × 276 ≈ 5.3 MiB` (the repo's figure is consistent in MiB —
`20000×276 = 5,520,000 B = 5.26 MiB` `[V]` arithmetic) is a typical-case
estimate, not an enforced maximum.

### 2.4 Arbitration rules

`[V]` `StoreRecord` (`RankDB.lua:156-192`):

1. Validate; reject with an error string if invalid (`157-160`).
2. Resolve the realm table (`162`), read any existing record (`163`).
3. **Last-write-wins by timestamp:** if the existing record's timestamp is
   strictly greater, return `true, "up-to-date"` without storing (`165-167`).
   Equal timestamps overwrite. There is no source priority and no tie-break.
4. Store the sanitized record and set the dirty flag (`169-170`).
5. Capacity: build `capacityEntries` with **one sub-table for every record in
   the realm** (`175-181`); if over 20,000, sort by timestamp asc and delete the
   oldest overflow (`182-189`). This runs on **every** insert, at every size.

Harness pins the semantics at low volume: `"RankDB.StoreRecord enforces
last-write-wins (rejects older timestamp)"` (`load_test.lua:2938`),
`"…updates record when newer timestamp arrives"` (`2952`).

### 2.5 Caps and cost

`[V]` `MAX_CAPACITY = 20000` (`RankDB.lua:25`), advertised in `README.md:115`.
Measured insert cost at increasing sizes (Lua 5.1, scratch harness):

```
n= 1000  StoreRecord x100 =   0.027 s  (0.27 ms each)
n= 5000  StoreRecord x100 =   0.140 s  (1.40 ms each)
n=10000  StoreRecord x100 =   0.330 s  (3.30 ms each)
n=20000  StoreRecord x100 =   2.318 s  (23.18 ms each)
```

The superlinear jump at the cap is the eviction sort running on every insert
(`RankDB.lua:182-189`). Real triggers for a single `StoreRecord`: every local
equipment change (`Core.lua:801-807` → scan → `Scanner.lua:617-620`), every
remote inspection completion (`Scanner.lua:786-789`), and every inbound `R`, `S`
and `T` record (`RankSync.lua:414-420, 385-404`).

### 2.6 Pruning: defined, tested, never invoked

`[V]` `PruneStaleRecords(realm, maxAgeDays=60, maxCapacity=20000)` deletes by age
then by capacity (`RankDB.lua:389-424`). `grep -rn "PruneStaleRecords"` over the
repo finds: its definition, the test call (`load_test.lua:3012`, label
`"RankDB.PruneStaleRecords evicts record older than 60 days"`), the README and
CHANGELOG claims, and design docs. **No production caller exists.**
`PurgeDatabase` (`RankDB.lua:426-437`) likewise has no caller outside its
definition. Consequences:

- The file never shrinks from pruning: no production code path deletes an
  aged record. Stale records are excluded from `all`/faction/class lists by the
  60-day cutoff in `BuildSortedIndices` (`RankDB.lua:219-220`), but they remain
  in the table and keep counting toward the cap; the only deletions that ever
  run are the at-cap eviction in `StoreRecord` (`RankDB.lua:182-189`).
  `GetRecord` reads the table directly (`310-320`), so a stale record is still
  returned by the sync engine's `mine` path if it is the requester's own.
- Old realm keys from a realm transfer are never cleaned either: nothing iterates
  `TacoTipExtrasDB.ranks`; `getDB` touches only the current realm key, and the cap
  is per realm (`RankDB.lua:58-72, 25`).
- README `"Stale data is automatically pruned after 60 days"` (`README.md:115`)
  and CHANGELOG `"Automatic 60-day stale record pruning"` (`CHANGELOG.md:191`)
  disagree with the code; per CAIRN precedence the code wins.

### 2.7 Schema migration

`[V]` Settings carry `schema = 2`; ranks carry no version of their own. A
`schema > 2` client copies the whole persisted root (ranks included) into a
runtime table for settings fallback (`Core.lua:289-302`) but rank writes still go
to `_G.TacoTipExtrasDB` (`RankDB.lua:58-72`), so that copy is not the live DB.
Pre-1.0.0 `TacoTipGearScoreEnhancerDB` is ignored, never read (`Core.lua:280-284`
comment; harness `load_test.lua:1962-1964`) `[V]`.

---

## 3. Sync — channels, protocol, sizes, flood control, triggers

### 3.1 Channels and fallbacks

`[V]` `PREFIX = "TACO_GS_SYNC"`, channel `ttgssync` (`RankSync.lua:10-11`).
Prefix registration: `C_ChatInfo.RegisterAddonMessagePrefix` with a fallback to
the legacy global, both `pcall`ed (`33-40`). Channel join: `JoinChannelByName`,
then `GetChannelName` to cache a numeric id; chat suppression is attempted
through `ChatFrame_RemoveChannelGroup` on `ChatFrame1..10` (`42-69`).

Blizzard-source checks:

- `C_ChatInfo.SendAddonMessage` exists and is documented on **all five** branches
  (`ChatInfoDocumentation.lua`; e.g. `origin/classic_era:358-374`,
  `origin/live:516-532`) `[V]`.
- `C_Timer.After` exists on all five (`UITimerDocumentation.lua`, `Name = "After"`
  in `Functions`) `[V]`.
- `CHAT_MSG_ADDON` delivers `prefix, text, channel, sender, …` identically on all
  five (payload compared on `classic_era:615-627`, `classic_titan:615-627`,
  `live:803-816`) `[V]`. The handler reads `arg1`/`arg2` only
  (`RankSync.lua:512-516`) — it discards `arg3` (`channel`), which matters in §5.
- The engine throttles and can refuse sends: `SendAddonMessageResult` enumerates
  `InvalidMessage`, `AddonMessageThrottle`, `TargetRequired`, `InvalidChannel`,
  `ChannelThrottle` on all five branches (e.g. `origin/live`
  `ChatConstantsDocumentation.lua:151-163`) `[V]`. The add-on ignores the return
  value — `rawSend` wraps the call in `pcall` and discards results
  (`RankSync.lua:137-145`).
- `JoinChannelByName`, `GetChannelName` and `ChatFrame_RemoveChannelGroup` do not
  appear anywhere in the UI source (grep, all five branches) `[V]`; they are
  engine-provided legacy globals and the code guards every use (`RankSync.lua:44,
  57-68`) `[A]` (verification: game client).
- The **255-byte addon-message limit** that the codebase and its tests assert
  (`RankSync.lua:230`, `load_test.lua:3226`) is **not** documented in the client
  source I could search `[U]`; `InvalidMessage` exists but no length constant.
  All size arithmetic below is against that asserted limit `[A]`.

### 3.2 Message types and payloads

`[V]` The wire formats are positional and `;`-delimited:

| type | payload | producer | consumer |
|---|---|---|---|
| `R` | `R;guid;name;faction;classID;class;specName;gs;ilvl;timestamp` — exactly 10 fields | `SerializeRecord` (`RankSync.lua:71-86`) | `DeserializeRecord` (`117-135`) |
| `Q` | `Q;<requestId>` | `RequestSync` (`292-296`) | `handlePayload` (`423-436`) |
| `S` | `S;<requestId>;<R payload>` | `respondToQuery` (`316-321`) | `ingestRecords` from index 3 (`385-404`) |
| `T` | `T;<requestId>;<R payload>;<R payload>` (0–2 records) | `respondToQuery` (`327-343`) | same |

`splitFields` (`103-115`) deliberately keeps empty fields; the comment records
the measured regression this fixes, and the harness pins it:
`"an empty specName does not discard the record"` (`load_test.lua:3073`),
`"an empty specName round-trips as empty, not as the next field"` (`3076`),
`"two consecutive empty fields round-trip"` (`3102`). The 10-field stride is
pinned by `"the SECOND record of a T message is ingested"` (`3280`) and
`"a single-record T message is ingested"` (`3291`). Malformed payloads are
asserted non-raising (`3296-3304`, `"no malformed payload raises"`).

### 3.3 Worst-case sizes vs the asserted 255-byte limit

Measured with the repo's own `RankSync.SerializeRecord` `[V]`:

| case | bytes |
|---|---|
| typical record (realistic guild name/spec/GUID) | **73** |
| validator-max fields (`guid 128`, `name 64`, `class 32`, `specName 64`, …) | **327** |
| validator-max fields with a 10-char GUID | **209** |
| `T;abcd;` + two 209-byte records | **426** |
| `T;abcd;` + two 253-byte `R` payloads (each under the 255 budget) | **514** |
| `S;` + 240-char request id + 73-byte record | **316** |

Arithmetic for a single `R`: `2 + |guid| + |name| + |faction| + |classID| +
|class| + |specName| + |gs| + |ilvl| + |timestamp| + 9 separators`. At validator
maxima **excluding** the guid this is `191 + 9 + 2 = 202`, so **any GUID over 53
characters pushes one record over 255**. Real GUIDs are ~21 chars, and the sizes
the tests exercise are small — the harness only asserts
`"no response exceeds the 255-byte addon message limit"` over the short seeded
answer (`load_test.lua:3220-3228`) `[V]`.

The sharp end is not a single oversized record (the engine would reject an
inbound one, so it can't be relayed) — it is these three:

1. **The request id is echoed unbounded.** `handlePayload` captures
   `^Q;([^;]+)` with no length cap (`RankSync.lua:424`) and `respondToQuery`
   concatenates it into `S;…` and `T;…` (`318, 334`). A query with a long id —
   which the peer could legitimately send if its own `makeRequestId` or a
   future version changed — makes every answer oversized and silently dropped.
2. **Two individually-sendable records can make an unsendable `T`.** Each record
   can be ≤255 inbound; `T` concatenates two plus `T;<id>;` with no size check
   (`331-337`).
3. **`GetTopRecords` returns whatever is stored**, and stored records may carry
   validation-maximum names/specs (up to 64 chars each) that the digest then
   re-serializes (`RankSync.lua:327-343`; `RankDB.lua:328-345`).

`rawSend` discards the send result (`RankSync.lua:137-145`), so all three
failure modes are silent: the message is counted as sent and the queue moves on.

### 3.4 Sanitization asymmetry (store vs wire)

`[V]` `QueueInspectRecord` validates+stores, then broadcasts the **original**
argument (`RankSync.lua:202-210`), so the wire copy can differ from the stored
copy (different truncation). For scanner-produced records the fields come from
bounded Blizzard APIs, so this is currently benign; it is still a public-API
inconsistency (`SerializeRecord` itself performs no sanitization and would pass a
`;` inside a field straight into the delimiter stream; `SerializeRecord` has no
caller-side re-validation).

### 3.5 Rate limiting and flood control

`[V]` Four independent controls:

- **Token bucket:** 1 message per 1.5 s, burst 3 (`RankSync.lua:12-13, 147-161`);
  refill is `floor(elapsed/1.5)` and the remainder is discarded (`150-154`), so
  the effective rate sits slightly under 1/1.5 s.
- **Queue cap 50, dropping the oldest** (`163-167`).
- **Response interval 20 s per client** (`245, 298-303`), and a 1–4 s random
  jitter before any answer (`246, 427-434`, driven through `C_Timer.After` when
  available).
- **Re-sync throttle 30 s** for the automatic triggers, bypassable only by the
  explicit `SyncNow(true)` user/refresh path (`484-507`).

The harness pins two of these: `"a second query inside the respond interval is
not answered"` (`load_test.lua:3234`) and the 255-byte assertion above.
The engine's own `AddonMessageThrottle`/`ChannelThrottle` (`ChatConstants`,
§3.1) is an additional, invisible gate because results are discarded.

One asymmetry: `lastRespondAt` is set **before** the code knows whether it has
anything to send (`RankSync.lua:299-303` vs `313-343`), so a client with no own
record and an empty digest still silences itself for 20 s.

### 3.6 When sync runs

`[V]` Triggers, in login order:

1. `PLAYER_LOGIN` → `registerPrefix()` only (`RankSync.lua:517-518`), so inbound
   messages are not dropped while the world loads.
2. `PLAYER_ENTERING_WORLD` (login, `/reload`, instance transitions) and
   `ZONE_CHANGED_NEW_AREA` (open-world) → `syncNow()` (`519-522`), throttled 30 s,
   then `C_Timer.After(4.0, joinThenQuery)` (`499-505, 450-465`): join the channel,
   resolve `channelID`, send `Q`.
3. Any completed scan — local or remote — stores and broadcasts `R`
   (`Scanner.lua:617-620, 786-789`; `RankSync.lua:202-210`), one copy each to
   group (`PARTY`/`RAID`), `GUILD` and `CHANNEL` when available (`176-200`).
4. Inbound `Q` → jittered `respondToQuery` → `S` plus up to two `T` messages
   (4 records max), **channel only** (`298-345`).
5. A user refresh: the leaderboard scan button / options control →
   `Scanner.BeginGeneration` (`RankBrowser.lua:433-447`); `RankSync.SyncNow(true)`
   is the force bypass the tests use (`load_test.lua:3204-3211`, label `"a resync
   sends a Q query"`).

**Login-order gap** `[V]`: Core's `eventFrame` is created at load (`Core.lua:16`)
before RankSync's `syncFrame` (`RankSync.lua:20`) and the TOC loads `Core.lua`
before `RankSync.lua`, so on `PLAYER_ENTERING_WORLD` the scan is scheduled first
and runs on the next `OnUpdate` (`Core.lua:643-668`), while the channel join is
delayed 4 s (`RankSync.lua:501-505`). `channelID` is a load-time `nil`
(`RankSync.lua:18`) that only `joinSyncChannel` sets (`55-69`). Therefore **the
login/zone-in `R` broadcast is sent before the channel exists** and goes only to
GUILD/PARTY — a solo, guildless player's first broadcast goes nowhere at all.
The own record still reaches peers indirectly, by answering their `Q`s, or on
the next equipment change after the channel is joined.

---

## 4. Structured pros/cons

### 4.1 Correctness / data integrity

**Pros**

- `[V]` Deterministic total order (`gs, ilvl, timestamp, name`), so equal-GS
  records never flip arbitrarily (`RankDB.lua:194-205`).
- `[V]` Strict validation: non-finite/negative/over-cap numbers rejected,
  control characters and `;` stripped, UTF-8-safe truncation (`74-102, 104-154`);
  test-pinned (`load_test.lua:2869-2904`).
- `[V]` Last-write-wins by timestamp is test-pinned (`2938, 2952`).
- `[V]` Empty-field parsing fixed and pinned (`3073-3108`); the stride bug class
  is explicitly pinned (`3271-3293`).
- `[V]` Malformed input cannot raise the protocol handler (`3296-3304`).

**Cons**

- `[V]` Advertised pruning is unreachable code (§2.6).
- `[V]` No authenticity: any client on the prefix can store any record for any
  GUID, including impersonating your own character; the only defense is
  timestamp arbitration (already-stored records can be overwritten with a
  timestamp up to `now+300`, `RankDB.lua:126`).
- `[V]` No realm attribution: the record schema and wire format have no realm
  field, and `StoreRecord` files every inbound record under the **local** realm
  key (`RankDB.lua:162`; wire `RankSync.lua:73-85`). Cross-realm PARTY/GUILD
  members (possible on the modern pair; engine membership not checked here `[U]`)
  would appear in the local realm board.
- `[V]` `GetRecord` bypasses the 60-day cutoff (`RankDB.lua:310-320`), so
  "freshness" is not one rule across call sites.
- `[V]` Filtered `#` in the browser is view-local while the footer/tooltip are
  realm-wide (§1.4) — two standings shown at once that disagree.
- `[V]` A missing or non-numeric timestamp becomes `now` (`RankDB.lua:126`),
  i.e. "unknown freshness" is stored as "fresh". Inbound `R` payloads always
  supply a value (the deserializer requires 10 fields and defaults to `0`,
  `RankSync.lua:132`), so this arm is reachable through direct API callers;
  the Scanner always passes `time()` (`Scanner.lua:173-175`).

### 4.2 Scalability

**Pros**

- `[V]` Dirty-flag caching collapses bursts of writes into one rebuild
  (`RankDB.lua:210-212, 282-284`); cached lookups measured ~0 µs
  (`100 cached GetPlayerRank: 0.0000 s`).
- `[V]` Index lists are assembled once per realm per dirty cycle, not per query.

**Cons**

- `[V]` `StoreRecord` is O(n) in all cases and O(n log n) at the cap — measured
  1.4 ms → 23.2 ms per insert from 5k → 20k records, plus an ~88 ms rebuild on
  the first read after each dirtying store.
- `[V]` At the cap, **every** insert sorts the whole realm table
  (`RankDB.lua:182-189`), then every later read re-sorts every index (up to
  4 list families over 20k entries).
- `[V]` Memory duplication: the persisted table plus up to 4 sorted views
  (`all`, `alliance`, `horde`, per-class) and a `lookups` table keyed per GUID
  (`246-284`). All are reference copies, but the lookups table is one table per
  GUID.
- `[V]` There is no byte budget and no global cap across realm keys (§2.3, §2.5).
- `[V]` Inbound sync storms multiply the cost: a `T` message stores up to two
  records (`RankSync.lua:385-404`), each paying the O(n) path.

### 4.3 Bandwidth / rate risk

**Pros**

- `[V]` Four independent flood controls (§3.5), sized against the asserted
  message limit; digest capped at 4 records (`RankSync.lua:327-345`); one
  message per response part.
- `[V]` Responses are only sent when there is data to send and only after a
  jittered delay.

**Cons**

- `[V]` `SendAddonMessage` result discarded → engine throttle/refusals invisible
  (`RankSync.lua:137-145`).
- `[V]` Unbounded request-id echo and no serializer-side size check (§3.3).
- `[V]` Three copies of every record broadcast (group + guild + channel,
  `176-200`), and no coalescing of back-to-back gear changes: a 17-slot re-equip
  burst enqueues up to 3 messages per completed scan.
- `[V]` Response path uses CHANNEL only, while queries advertise three channels
  (§3.6 case 4) — the fallbacks are a one-way street.

### 4.4 Failure handling

**Pros**

- `[V]` Every Blizzard call is feature-detected and/or `pcall`ed; the module
  loads when something is absent (`RankSync.lua:22-40, 137-145`;
  `Scanner.lua:90-93`).
- `[V]` Sub-initializers are individually guarded so one failure degrades one
  surface instead of the add-on (`Core.lua:696-714`).
- `[V]` Malformed protocol input is quiet and non-raising, test-pinned.

**Cons**

- `[V]` No observability: no counters for sends, drops, queue evictions, or
  throttles; `/ttgsdebug` prints only the local scan (`Core.lua:593-628, 634-641`).
- `[V]` `channelID` is resolved once at join and never re-resolved; nothing
  handles leaving the channel, a failed rejoin, or `InvalidChannel` responses
  (`RankSync.lua:55-69`; no `CHANNEL_UI_UPDATE`/channel event registration).
- `[V]` `SAVED_VARIABLES_TOO_LARGE` exists on all five branches
  (`AddOnsDocumentation.lua`, `LiteralName = "SAVED_VARIABLES_TOO_LARGE"`, e.g.
  `origin/live:410-418`) and the add-on **does not register for it** (grep, zero
  hits). If the file ever exceeds the engine's (undocumented `[U]`) threshold,
  the add-on is told and ignores it.
- `[A]` In `respondToQuery`, a `Q` arriving over GUILD/PARTY when no channel is
  joined enqueues `S`/`T` with `target = nil` (`RankSync.lua:318-319, 338-339`);
  the engine's `TargetRequired`/`InvalidChannel` results exist (§3.1), and the
  result is discarded, so this is silent loss.

### 4.5 Maintainability

**Pros**

- `[V]` Clear module split; protocol internals published for tests
  (`RankSync.HandlePayload`, `SyncNow`, `SYNC_THROTTLE_SECONDS` —
  `RankSync.lua:444-445, 509-510`); honest measured-rationale comments.
- `[V]` Two harnesses: a load/matrix suite and a behaviour suite that drives the
  real browser (`rankbrowser_test.lua:1-31`); both run on three interpreters.

**Cons**

- `[V]` Documentation drift: pruning "automatic" (`README.md:115`,
  `CHANGELOG.md:191`), 5,000 cap "lowest-GS eviction" (`CHANGELOG.md:191`) vs
  20,000 and oldest-timestamp eviction (`RankDB.lua:25, 182-189`), prefix
  `TTGS_SYNC` (`CHANGELOG.md:195`) vs `TACO_GS_SYNC` (`RankSync.lua:10`), and the
  design doc's `D;Count;MaxTimestamp` handshake and faction tabs
  (`docs/superpowers/specs/2026-10-12-gearscore-server-rank-browser-and-sync-design.md`)
  that the shipped code does not implement `[V]`.
- `[V]` Wire format has no version marker; the deliberate field-order
  duplication (`RankSync.lua:347-352`) means any field added later breaks the
  10-stride ingestion on older clients.
- `[V]` Dead weight in every stored record: `classID` and `source` are written
  but never read anywhere (grep); `specIcon` is stored and rendered as the
  leaderboard row's spec icon (`RankBrowser.lua:351-371`, called `413`) but is
  not carried on the wire, so every peer always loses it.
- `[V]` Harness coverage gaps (grep): no test for capacity eviction
  (`MAX_CAPACITY` appears nowhere in tests), no `GetTopRecords` clamp test, no
  test that the index excludes >60-day records, no realm-isolation test, no
  oversize-payload test, and `PruneStaleRecords` is asserted only by direct call
  — i.e. the test proves the function works, not that anything runs it.

### 4.6 First-login experience

**Pros**

- `[V]` A fresh install seeds quickly: query at +4 s, peers answer `S` (their own
  record) plus up to 4 digest records, so the top of the ladder appears without
  walking the realm; the local player's own record is stored immediately at
  first scan (`Scanner.lua:617-620`).
- `[V]` Prefix registration on `PLAYER_LOGIN` means no inbound messages are lost
  during world load (`RankSync.lua:517-518`).
- `[V]` Empty-board state and "not scanned" gear-panel state are explicit rather
  than blank (`RankBrowser.lua:1090-1095`; `RankBrowser.lua:650-655`).

**Cons**

- `[V]` First broadcast misses the channel (§3.6) — guildless/solo peers learn
  nothing of you until you answer their query or change gear.
- `[V]` The board renders on open/interaction only; there is no subscription to
  the DB, so records arriving while the window is open do not appear until the
  user interacts (`RankBrowser.lua:1156-1176`; no `RankDB` notify API exists).
- `[V]` The first read after login with a dirty DB pays the full rebuild; if the
  first read happens while answering a query (`GetTopRecords` → rebuild) that is
  a ~88 ms hitch at 20k records `[V]`.
- `[V]` A `schema>2` future client clones the entire ranks table into memory
  (`Core.lua:293-301`), doubling peak load-time memory for a fallback path.

---

## 5. Improvement brainstorm (ranked by impact/effort/risk)

Verification column names the repo's own harness unless stated. The harness has a
real event dispatcher (`load_test.lua:1977-1995`, `fireEvent`) and the protocol
block already captures every send (`3151-3172`), so all of these are testable
without the game.

### 5.1 DO — ordered by (impact ÷ effort)

**B1. Answer queries on the channel the query arrived on. (impact high / effort low / risk low)**
- *What changes:* thread `CHAT_MSG_ADDON`'s third argument (payload field
  `channel`, `RankSync.lua:512-516`) into `handlePayload`/`respondToQuery`, and
  send `S`/`T` with the same chat type the `Q` arrived on (GUILD/PARTY/RAID/
  CHANNEL), falling back to CHANNEL. Today every answer goes channel-only
  (`318-319, 338-339`). `[A]` The payload field is defined as a cstring named
  `channel` (`ChatInfoDocumentation.lua`); that its runtime value is the delivery
  chat type is assumed (verification: log arg3 on each branch in game).
- *Migration:* none; no saved-data change.
- *All five clients:* pure Lua; `CHAT_MSG_ADDON` payloads are identical on all
  five (verified §3.1).
- *Verification:* extend the protocol block with a check that a `Q` dispatched
  with `arg3 = "GUILD"` produces at least one send whose `chatType == "GUILD"`
  (the existing `sent` capture already records `chatType`); a further check that a
  channel-sourced `Q` still answers on CHANNEL. Fails before the change.

**B2. Bound every outbound payload before it is enqueued. (impact high / effort low / risk low)**
- *What changes:* in `respondToQuery`, reject/truncate a `requestId` longer than
  a small cap (e.g. 16), and add a serializer-side guard: if
  `#payload > BUDGET` (e.g. 240 minus the envelope), drop optional fields in a
  fixed order (`specName`, `class`, truncate `name`) or skip that record in the
  digest; `Enqueue` could also refuse oversize messages outright so the failure
  is visible in code rather than silently at the engine.
- *Migration:* none.
- *All five:* pure Lua.
- *Verification:* new checks using the real serializer: a validator-max record
  serializes to ≤ the budget (or is deliberately rejected), and a
  `Q;` with a 240-char id produces no message longer than 255. Fails now
  (measured 327-byte record, 316-byte `S`).

**B3. Make the login `R` broadcast wait for the channel, or send it again after join. (impact medium-high / effort low / risk low)**
- *What changes:* after `joinThenQuery` succeeds, re-broadcast the local record
  once (or defer the first broadcast until `channelID` is known). One message,
  uses the existing throttle/queue.
- *Migration:* none.
- *All five:* pure Lua.
- *Verification:* drive `PLAYER_ENTERING_WORLD` → `OnUpdate` scan → `C_Timer.After`
  → assert `S`/`R` for the harness player is sent with a CHANNEL target after
  join; today the login burst contains no CHANNEL send.

**B4. Amortized capacity accounting, replacing the per-insert full scan. (impact high / effort medium / risk medium)**
- *What changes:* maintain `recordCount` per realm and evict in batches (e.g.
  allow `cap + 5%` slack, then one sorted sweep down to cap), or keep a cheap
  running oldest-timestamp and only scan when over cap. Contract stays: no more
  than `MAX_CAPACITY` visible records, oldest timestamps evicted first.
- *Migration:* counters rebuilt lazily on first access (`#` over `pairs` once);
  no saved-data change.
- *All five:* pure Lua.
- *Verification:* new checks — after storing `MAX_CAPACITY + k` synthetic records
  the leaderboard returns exactly `MAX_CAPACITY` and the k oldest timestamps are
  gone; eviction does not depend on GS. (Timing assertions stay out of the
  suite; the harness asserts semantics, the scratch benchmark stays the
  performance evidence.)

**B5. Invoke `PruneStaleRecords` once per session for every stored realm. (impact medium / effort low / risk low)**
- *What changes:* on first `PLAYER_ENTERING_WORLD`/`PLAYER_LOGIN` after load, walk
  `TacoTipExtrasDB.ranks` and prune each realm (60 days), deleting empty realm
  tables; expose it as an explicit `RankDB.PruneAll` so it is testable without
  the event path.
- *Migration:* deletes only records the UI already hides; shrinks the file.
  Existing files are otherwise untouched.
- *All five:* pure Lua.
- *Verification:* seed stale + fresh records in two realms, fire the login event
  through `fireEvent`, assert stale gone, fresh kept, empty realm key removed,
  and the test count unchanged for records inside the window. Makes
  `README.md:115` true.

**B6. Harness coverage for the five untested contracts. (impact high / effort medium / risk none)**
- *What changes/tests:* capacity eviction, `GetTopRecords` clamp at 10,
  60-day exclusion in `BuildSortedIndices`, realm isolation (two realm keys),
  oversize-payload budget. All five currently absent (grep evidence, §4.5).
- *Migration:* none. *All five:* none. *Verification:* the checks themselves;
  each should be shown to fail against the current code where it pins a gap.

**B7. Send-result observability and channel re-resolution. (impact medium / effort low-medium / risk low)**
- *What changes:* capture `SendAddonMessage`'s result in `rawSend` and count
  `Success`/`Throttle`/`InvalidChannel`; re-resolve `channelID` on failure or on a
  channel/zone event; surface the counters in `/ttgsdebug` (or a `/ttgssync`
  status command) and in Options.
- *Migration:* none (runtime counters, not saved).
- *All five:* `C_ChatInfo.SendAddonMessage` exists on all five; the classic
  branches expose the same result enum (§3.1) `[V]`; legacy global fallback
  already handled.
- *Verification:* protocol block already stubs `SendAddonMessage`; make the stub
  return `AddonMessageThrottle` and assert the counter increments and the message
  is retried/queued rather than dropped.

**B8. Coalesce local broadcasts. (impact low-medium / effort low / risk low)**
- *What changes:* debounce `BroadcastRecord` per GUID (e.g. 5 s) so a burst of
  gear swaps produces one `R`, not one per event; optionally skip the third copy
  when the first two cover the same audience (not knowable; keep 3 but debounced).
- *Migration:* none. *All five:* pure Lua.
- *Verification:* count sends for two scans of the same GUID 1 s apart — expect
  one broadcast, not two; today the scanner has no debounce
  (`RankSync.lua:202-210`).

**B9. Protocol version marker + realm field (with compat shim). (impact medium / effort medium-high / risk medium)**
- *What changes:* a versioned record type (e.g. `V2;realm;R;…`) sent when peers
  advertise it, old `R` otherwise; store `record.realm` and route inbound records
  to the sender's realm table when present.
- *Migration:* existing stored records lack `realm`; treat missing as local.
  New `schema` bump not required for ranks (root schema is settings-only).
- *All five:* pure Lua; no client difference.
- *Verification:* round-trip tests for both old and new payloads plus a mixed
  T stride test; assert a cross-realm-tagged record lands in the sender's realm
  key and the local board is unpolluted.

**B10. Debounce/defer the index rebuild. (impact low-medium / effort low / risk medium)**
- *What changes:* when dirty, defer the rebuild to the next frame/`C_Timer.After(0)`
  and coalesce concurrent requests, so a sync burst costs one rebuild instead of
  one per read; `GetPlayerRank`/`GetLeaderboard` would need a synchronous path for
  correctness (deferring must never return a stale index as if fresh).
- *Migration:* none. *All five:* `C_Timer.After` verified on all five.
- *Verification:* assert that N stores followed by M reads produce the same
  sorted result as before (functional), and use an exposed rebuild counter to
  assert rebuilds ≤ stores' burst count.

**B11. Byte-budgeted database. (impact low-medium / effort medium / risk medium)**
- *What changes:* enforce a byte estimate (or a max record-size clamp) in
  addition to the count cap, so "5.3 MB" is an actual ceiling; evict oldest until
  under budget.
- *Migration:* could evict records earlier than today on huge DBs; announce in
  CHANGELOG. *All five:* pure Lua.
- *Verification:* store synthetic large records and assert the estimated size
  stays under the budget and the freshest survive.

### 5.2 DON'T

- **Don't raise `MAX_CAPACITY` again.** The cap is a count, so raising it does not
  bound bytes, and it doubles the per-insert cost that is already measured at
  23 ms (B4). `README.md:161` already frames 5.3 MB as a login/latency trade.
- **Don't add more fallback channels or message copies.** Coverage is already
  three channels per record; the gap is symmetry (B1), not reach.
- **Don't sync per-slot equipment / item links / specIcon.** The wire budget is
  the binding constraint and the cache is deliberately session-only
  (`README.md:165`); item links would blow the record size for a surface that
  already degrades honestly.
- **Don't add compression.** Typical records measure 73 bytes; the limit is
  per-message, not total, and a compressor would not remove the one real
  failure mode (two large records in one `T`).
- **Don't switch to `SendAddonMessageLogged`.** Blizzard documents it as
  "Intended for plain text payloads; logged and throttled" (`ChatInfoDocumentation`,
  `SendAddonMessageLogged`) `[V]` — the opposite of what a silent background
  sync needs.
- **Don't attempt cross-realm leaderboards with this protocol.** There is no
  realm identity today (B9 is the prerequisite), and the UI is explicitly
  whole-realm (`README.md:93`).
- **Don't store per-record duplicates of `classID`/`source` in new work.** They
  are read by nothing (grep, §2.2); keeping them costs bytes on both sides of the
  wire.

---

## 6. Recommendation — the best way to improve it

**Do the delivery-and-lifecycle hardening, in this order: B1 → B2 → B3 → B4 → B5 → B6.**
Rationale, grounded in the measurements:

- The ranking math, validation and UI are the parts that already hold ("done
  means it holds"): 42/42 harness invocations, deterministic order, pinned
  arbitration. New features would sit on top of three measurable weaknesses.
- The weaknesses are (a) one-way fallbacks — the protocol's own stated feature
  quietly doesn't work for guild/party-only peers; (b) unbounded sizes on the
  answer path — the one place where the protocol can silently lose exactly the
  messages it exists to carry; (c) a store whose cost per insert is measured to
  grow from 1.4 ms to 23 ms and whose advertised 60-day prune never runs.
- These are also the cheapest to prove, because the harness already captures
  sends and dispatches events; none of them requires the game, a new API, or a
  saved-data migration.

**Smallest concrete first step:** thread the `CHAT_MSG_ADDON` channel argument
into `handlePayload` and have `respondToQuery` answer on that same chat type
(§5.1 B1), with one new harness check: *a `Q` whose channel is `"GUILD"` must
produce an `S` whose `chatType` is `"GUILD"`.* It is a handful of lines in one
file, needs no schema change, is exercised by the existing protocol block
(`load_test.lua:3140-3308`), and turns the documented GUILD/PARTY fallback from
advertising into behaviour.

Second step immediately after: B2 (request-id cap + serializer size guard) and
B3 (post-join re-broadcast), which together close the two remaining "silently
lost on the wire" paths and the first-login hole. Then B4/B5/B6 as one storage
increment, since they share the same harness additions.

---

## Appendix A — Verification runs performed

1. `bash TacoTip_Extras/Tests/harness/run_all.sh` → 42/42 passed (lua5.1, lua5.4,
   luajit) `[V]`.
2. Scratch harness `/tmp/opencode/rank_measure.lua` (loads the repo's real
   `RankDB.lua`/`RankSync.lua`):
   - wire sizes: typical 73 B; validator-max 327 B; max fields with a 10-char
     GUID 209 B; `T` + two max-ish 426 B; `S` + 240-char request id + typical
     316 B `[V]`.
   - validation bounds actually applied to a 200/200/200/5000-char input:
     guid 128, name 64, class 32, specName 64, specIcon **5000 kept** `[V]`.
   - `StoreRecord` × 100 at n = 1k/5k/10k/20k: 0.27/1.40/3.30/23.18 ms each `[V]`.
3. Scratch harness `/tmp/opencode/rank_build_measure.lua`: cold
   `BuildSortedIndices` at 20k = 0.088 s; rebuild after one store = 0.086 s;
   100 cached `GetPlayerRank` = 0.0000 s `[V]`.
4. Client-source checks (all `origin/`-qualified): `SendAddonMessage` present on
   all five (`ChatInfoDocumentation.lua`); `SendAddonMessageResult` enum with
   `AddonMessageThrottle`/`ChannelThrottle` on all five
   (`ChatConstantsDocumentation.lua`); `C_Timer.After` on all five
   (`UITimerDocumentation.lua`); `CHAT_MSG_ADDON` payload identical on
   `classic_era`/`classic_titan`/`live`; `GetNormalizedRealmName` cstring on all
   five; `SAVED_VARIABLES_TOO_LARGE` on all five; `GetItemStats` absent on the
   three Classic branches, present on `forever`/`live`; `JoinChannelByName`,
   `GetChannelName`, `ChatFrame_RemoveChannelGroup` absent from the UI source on
   all five `[V]`.

## Appendix B — Open questions (labeled, not answered)

- `[U]` The exact engine SavedVariables serialization format and the resulting
  per-record byte count — inspect a real `TacoTipExtrasDB.lua` to replace the
  276-byte assumption (§2.3).
- `[U]` The precise 255-byte semantics (message only vs prefix included) and
  whether the engine rejects or truncates — `InvalidMessage` exists but no length
  constant is documented (§3.1).
- `[U]` Whether cross-realm PARTY/GUILD addon messages reach a client on each
  supported branch; if so, the missing realm field is a live contamination path,
  not a theoretical one (§4.1).
- `[U]` Whether the client echoes a client's own addon messages back to it; if
  it does, every `Q` also triggers the sender's own jittered answer (wasted
  traffic only).
- `[U]` Custom-channel membership caps and whether `ttgssync` can fill on a large
  realm (`JoinChannelByName`/`GetChannelName` are undocumented in the UI source).
- `[A]` `ChatFrame_RemoveChannelGroup` suppressing channel text as the comment
  claims — function not in the UI source; guarded, so worst case is chat clutter.
