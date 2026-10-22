# Stage 4 — gear on demand: implementation-ready brief

- **Date:** 2026-10-18
- **Desk:** `stage4-prep` (bench-only authoring; no code touched)
- **Parent spec:** `bench/audits/2026-10-18-extras-rank-storage-expansion.md`
  §6.2 Stage 4 + §5 gear payload design + §6.3 budget + §6.4 all-client
  concerns, as corrected by `bench/audits/2026-10-18-stage1-and-tier-a-oracle-audit.md`
  (same-transport answers only, no whisper path ever, counted outcomes for
  every failure) and built on `bench/audits/2026-10-18-stage3-cheap-fields-brief.md`
  (the stride this stage extends).
- **Evidence labels (CAIRN.md):** `[V]` VERIFIED (read in source or produced
  by a command I ran), `[A]` ASSUMED (says what would verify), `[U]` UNKNOWN.
- **Run:** run_id `stage4prep-01`, agent_name `stage4-prep`.

---

## 0. Load-bearing assumption: the Stage-3 stride lands first

This brief **assumes the Stage-3 stride lands exactly as briefed**:
`R;<ver>;guid;name;classID;gs;ilvl;timestamp;specID;guild;level;pvpRank;arena`
— 13 `;`-separated fields, `WIRE_VERSION = "2"`, `RECORD_FIELDS = 13`,
guild hard-capped at 24 chars (`bench/audits/2026-10-18-stage3-cheap-fields-brief.md`
§1.1–§1.3) `[V]` (brief-read).

**Reconciled landed wire code (tree as read, before Stage 3):**
`local WIRE_VERSION = "1"` (`TacoTip_Extras/RankSync.lua:165`),
`function RankSync.SerializeRecord` (`TacoTip_Extras/RankSync.lua:167`),
`local RECORD_FIELDS = 9` (`TacoTip_Extras/RankSync.lua:192`),
version-gated refusal in `DeserializeRecord`
(`TacoTip_Extras/RankSync.lua:223`, gate at `:229`, counted
`versionReject` at `:233`), duplicated gate in `recordFromParts`
(`TacoTip_Extras/RankSync.lua:754`, gate at `:758`, counted at `:759`),
fixed-stride ingest (`TacoTip_Extras/RankSync.lua:784`, stride loop at
`:788`, advance at `:800`), same-transport `answerForQuery`
(`TacoTip_Extras/RankSync.lua:653`), `respondToQuery`
(`TacoTip_Extras/RankSync.lua:665`) with counted silent skip
`answerNoTransport` (`TacoTip_Extras/RankSync.lua:700-701`),
240-byte door (`TacoTip_Extras/RankSync.lua:22`,
`TacoTip_Extras/RankSync.lua:454`, refuse-and-count at `:459-461`),
two-record digest split into two singles
(`TacoTip_Extras/RankSync.lua:719-737`, comment at `:728-732`) `[V]`.

**Reconcile-on-dispatch rule:** the Stage-4 implementer MUST re-grep
`WIRE_VERSION`, `RECORD_FIELDS`, `SerializeRecord`, `recordFromParts`,
`ingestRecords`, `answerForQuery`, and `Enqueue` before touching indices.
If Stage 3 moved the stride (e.g. version is not `"2"` or the field count
is not 13), this brief's positional math moves with it — the byte budgets,
transport rules, and cache rules do not.

**Still moving (concurrency note):** writer desks are live on
`TacoTip_Extras/RankSync.lua`, `TacoTip_Extras/RankDB.lua`,
`TacoTip_Extras/Tests/harness/`, and `TacoTip_Extras/CHANGELOG.md`
(wire diet finishing, Stage-3 implementer pending). This file is new so
there is no merge conflict; the implementer re-verifies the seven symbols
above at dispatch because the diet/Stage-3 hunks touch exactly those lines.

---

## 1. Request/response flow

### 1.1 Message types (new, additive — no change to R/Q/S/T)

```
G;<reqID>;<guid>                  query:  "send me gear for <guid>"
D;<reqID>;<guid>;<seq>/<of>;<blob> answer: one or more chunks (usually one)
```

- `reqID` reuses the existing request-id rules: outbound fixed-width 6 hex
  (`RankSync.lua:606-614` comment + `makeRequestId`), inbound clamped to 8
  at the door (Stage-1 pattern; cf. `respondToQuery` second gate). New `G`
  parsing MUST apply the same `:sub(1,8)` clamp before echoing — a
  hundreds-of-bytes `G` id must never ride the `D` answer byte-for-byte.
- `guid` is the target character's GUID (same sanitization as the record
  `guid`: `RankDB.ValidateRecord` string ≤128,
  `TacoTip_Extras/RankDB.lua:209`, `:214`) `[V]`. Empty or unsanitary guid
  → counted drop, no send (new bucket `gearBadGuid`, §1.4).
- `seq/of` is `1/1` for the common single-chunk answer; multi-chunk only
  when the single blob would breach the door (§2.3). `of` ≤ 4 (hard cap;
  more than four chunks is refused + counted — a full 17-slot ID set never
  needs more than two, so four is headroom, not a tuning knob).
- `blob` is the §2 encoding. Empty blob is never sent: a responder with no
  gear for the guid sends nothing (counted `gearNoData`, §1.4), exactly
  like the harness-era "unknown GUID produces nothing" rule (expansion
  §6.2 Stage 4) — silence with a counter, not an empty message.

### 1.2 Same-transport-only (oracle correction is load-bearing)

- `G` arrives with `(chatType, sender)` from `CHAT_MSG_ADDON` payload order
  `prefix, text, channel, sender` (classic_era
  `ChatInfoDocumentation.lua:615-628` `[V]`, live `:803-816` `[V]`; handler
  threads `arg3/arg4` at `TacoTip_Extras/RankSync.lua:954-957`) `[V]`.
- `D` answers **only** via `answerForQuery(chatType)`
  (`TacoTip_Extras/RankSync.lua:653`): GUILD→GUILD, PARTY/RAID/
  INSTANCE_CHAT→same, CHANNEL→CHANNEL only while
  `channelSendTarget()` is non-nil. Nil transport → counted
  `answerNoTransport` skip (`TacoTip_Extras/RankSync.lua:700-701`) `[V]` —
  **reuse that bucket for gear** (new code paths call the same
  `answerForQuery`; do not invent `gearNoTransport`).
- **No whisper path ever.** There is no whisper send, whisper queue, or
  whisper fallback anywhere in the landed code
  (`respondToQuery` signature carries `_sender` unused,
  `TacoTip_Extras/RankSync.lua:665`) `[V]`, per the oracle BLOCKER
  (§1: "no whisper path at all"). A `G` that arrives on WHISPER is answered
  on WHISPER only if `answerForQuery` returns it (same-transport); a `G`
  whose transport is dead is skipped + counted, never rerouted. Any
  `Enqueue(..., "WHISPER", ...)` in a Stage-4 diff is rejected on sight.
- `G`/`D` payloads whose first byte is not `R/Q/S/T/G/D/P` are ignored by
  `handlePayload` peers (probe-inert rule; `P` precedent at
  `RankSync.lua:396-410`) `[V]` — old clients (pre-Stage-4) drop `G`/`D`
  silently without breaking `R/Q/S/T` ingest. No compat shim: the wire is
  pre-release (diet rule).

### 1.3 Version gating (reuse the diet's gate, do not invent a second one)

- `G`/`D` carry the **same** `WIRE_VERSION` as `R` (Stage-3 `"2"` assumed).
  Form: `G;<ver>;<reqID>;<guid>` and
  `D;<ver>;<reqID>;<guid>;<seq>/<of>;<blob>` — the version sits in the same
  ordinal position (field 2) so one gate covers all types.
- Unknown version → refused + counted `versionReject` (the exact buckets at
  `TacoTip_Extras/RankSync.lua:233` and `:759`) `[V]`. Do not add
  `gearVersionReject`: the existing counter already answers
  "/ttgsdebug shows version pressure" and keeps `GetDebugState`
  (`TacoTip_Extras/RankSync.lua:932`) shape-stable.
- Stride discipline from Stage 3 holds: any future gear-field change ships
  under a NEW version token, never by reusing the `D` shape with different
  fields (diet comment at `TacoTip_Extras/RankSync.lua:187-191`) `[V]`.

### 1.4 Counted outcomes (every failure path names a bucket)

Reuse existing buckets where they exist; add only gear-specific ones:

| event | bucket | precedent |
|---|---|---|
| `D` chunk refused at enqueue (>240) | `enqueueOversize` (existing, `RankSync.lua:459-461`) | digest door `[V]` |
| dead-transport gear answer skipped | `answerNoTransport` (existing, `:700-701`) | S/digest skip `[V]` |
| unknown wire version on `G`/`D` | `versionReject` (existing, `:233`/`:759`) | diet gate `[V]` |
| `G` for unknown guid / no data held | `gearNoData` (NEW) | expansion "unknown GUID produces nothing" |
| `G` with empty/unsanitary guid | `gearBadGuid` (NEW) | record guid rule (`RankDB.lua:214`) |
| stale `D` ignored (older `t` than stored) | `gearStale` (NEW) | §3 dedup rule |
| `G` duplicate-coalesced (§4) | `gearCoalesced` (NEW) | throttle fairness |
| `D` chunk stored | `gearStored` (NEW) | proves the path in `/ttgsdebug` |
| send results for `D` | existing `sendSuccess`/`sendThrottle`/`sendNoInfo`/… via `rawSend` (`RankSync.lua:278-317`) | Stage-1 item 3 `[V]` |

All buckets surface through the existing `GetDebugState` snapshot
(`TacoTip_Extras/RankSync.lua:932`) with no shape change — the debug
contract Stage 1 established (oracle §2.3) stays intact.

---

## 2. Per-slot encoding design + byte math against the 240-byte door

### 2.1 What rides (and what never does)

- **Rides:** numeric itemIDs only, one per equipped slot, in a sparse
  `slot=itemID` comma-run. Source of truth is the Scanner revision:
  `captureSlot` reads `GetInventoryItemID(unit, slotID)` +
  `GetInventoryItemLink(unit, slotID)` (`TacoTip_Extras/Scanner.lua:476`,
  raw reads at `:484-485`) `[V]`, with link-extracted fallback when the ID
  API returns nil; the completed revision's per-slot `itemID.value` is what
  the owner serializes.
- **Never rides:** full links, enchants, gems, suffixes, names, stats.
  A native link is ~80–150 bytes/slot (expansion §2.4) `[V]` — two slots of
  links already evict a record. Enchant/gem detail is session-only by
  design (expansion §2.4 verdict; Stage-3 §2.5 exclusion). Item *names* are
  never persisted, never synced — resolved at display via
  `C_Item.GetItemInfo` (async-aware, existing `ITEM_DATA_LOAD_RESULT`
  path, `TacoTip_Extras/Scanner.lua:91-92,311-345`) `[V]`.
- **Which slots:** exactly the 17 `REQUIRED_SLOTS`
  (`TacoTip_Extras/Scanner.lua:14-17`: `1,2,3,5,6,7,8,9,10,11,12,13,14,15,16,17,18`)
  `[V]` — shirt (4) and tabard (19) excluded, matching the scorer input.
  The browser panel renders the same 17 (`TacoTip_Extras/RankBrowser.lua:667`
  `SLOT_ROWS`, 17 rows over slots 1,2,3,15,5,9,10,6,7,8,11,12,13,14,16,17,18)
  `[V]`, so wire order and panel order share one canonical list; the blob
  uses `REQUIRED_SLOTS` order, not panel order.

### 2.2 Encoding (normative)

```
blob := slot "=" itemID ("," slot "=" itemID)*
slot := decimal slotID (1..18, only members of REQUIRED_SLOTS)
itemID := decimal positive integer (no leading zeros; tonumber-validated)
```

- Omit empty slots entirely (no `5=` placeholders). Omit `itemID <= 0`.
  Order MUST be ascending `REQUIRED_SLOTS` order so chunk splits (§2.3) are
  deterministic and dedup comparisons are string-stable.
- Separators: `,` between pairs, `=` inside a pair, `;` framing the message.
  Sanitizer strips `;` and controls exactly like `ValidateRecord`
  (`TacoTip_Extras/RankDB.lua:209` `sanitizeString` path) — a `;` inside a
  blob is a parse error, not data.
- Example (typical): `1=12345,2=23456,3=34567,5=45678,6=56789,7=67890`
  (6 pairs shown; a full set continues through slot 18).

### 2.3 Byte math (separators counted, worst cases bounded)

Door: `MAX_PAYLOAD_BYTES = 240` (`TacoTip_Extras/RankSync.lua:22`) `[V]`;
engine limit 255, Blizzard budgets 250
(`Blizzard_CooldownBroadcaster.lua:6` classic_era `[V]`, `:8` live `[V]`).

| component | typical | worst |
|---|---|---|
| `D;<ver>;` framing | 4 (`D;2;`) | 4 |
| `<reqID>;` | 7 (6 hex + `;`) | 9 (8-char clamp + `;`) |
| `<guid>;` | 23 (22-char guid + `;`, e.g. `Player-1234-ABCDEF12`) | 129 (128-char validator-max + `;`) |
| `<seq>/<of>;` | 4 (`1/1;`) | 4 (`4/4;`) |
| per pair `slot=itemID,` | ~9 (`12=123456,` — 2-digit slot + `=` + 6-digit id + `,`) | ~10 |
| full 17-pair blob | **~102–144** (measured gear-blob range, expansion §3.2/Appendix A `[V]`) | ~170 (17 × 10) |
| **single-`D` total** | **~140–180** | ~306 (validator-max guid + full blob) |

Consequences:

1. **Typical gear fits in one `D` with ~60–100 bytes of headroom.**
   `D;2;<6hex>;<22-guid>;1/1;<~120-blob>` ≈ 140–160 ≤ 240 `[V]` arithmetic.
   The common case is one query → one answer, same as `S`.
2. **Validator-max guids do NOT fit — handled, not prevented.**
   129 (guid) + 9 (id framing) + 4 + 4 + 170 ≈ 306 > 240. The door
   (`TacoTip_Extras/RankSync.lua:459-461`) refuses it with
   `enqueueOversize` `[V]` — but a gear answer, unlike a digest pair, has a
   shorter form (fewer pairs per message), so refusal without splitting
   would drop gear for exactly the longest-named players. Hence sequencing:
3. **Sequencing: EXTEND the digest-split machinery, do not reuse it
   verbatim.** The digest split (paired→two-singles,
   `TacoTip_Extras/RankSync.lua:725-737`) `[V]` works because a `T` is two
   independent records. A gear blob is one ordered run, so the extension is:
   chunk the *pair-run* at pair boundaries, greediest-first, each chunk +
   full framing ≤ 240; emit `D;<ver>;<id>;<guid>;<seq>/<of>;<chunk>` with
   `of` = chunk count (≤4). Chunking is by pairs, never mid-pair; a single
   pair always fits (max ~10 + framing ≪ 240), so the loop always makes
   progress. Reassembly is order-independent (pairs carry their slot), but
   `seq/of` still rides so the receiver can count `gearStale` vs partial
   delivery and so `/ttgsdebug` can distinguish "1/2 stored, 2/2 throttled"
   from "both stored".
4. **No compression.** Single-record compression measured 97% of raw, gear
   blob 57%, 40-record batch 16% (expansion §3.2/Appendix A) `[V]`.
   A 150-byte `D` compresses to ~85 + encode overhead — not worth a new
   dependency or a `C_EncodingUtil` callability gamble on classic branches
   (expansion §4 open question `[A]`). The door + chunking already bounds
   the worst case.

---

## 3. Cache design (session truth + bounded persistence)

Two tiers, deliberately different lifecycles (expansion §2.4 `[V]`):

### 3.1 Tier 1 — session truth (exists today, Stage 4 reads it, does not retune it)

- `Cache.lua`: `MAX_ENTRIES = 32` (`TacoTip_Extras/Cache.lua:10`),
  `FRESHNESS_SECONDS = 300` (`TacoTip_Extras/Cache.lua:14`),
  `PublishComplete` (`:210`), `PublishUnavailable` (`:238`),
  `IsCurrentGeneration` (`:258`), `Get` (`:263`) `[V]`.
- Owner answers from `Scanner.GetCurrent()`
  (`TacoTip_Extras/Scanner.lua:910`) `[V]`; peers answer only from a
  *fresh* session entry (`Scanner.GetFreshRemote(guid)` /
  `Scanner.GetRemote(guid)`, `TacoTip_Extras/Scanner.lua:971,975`) `[V]`.
  A peer whose entry is missing, `pending`, `unavailable`, or
  freshness-expired sends nothing + counts `gearNoData` — never a guess,
  never a stale blob.
- **Do not retune 32/300.** The library's `CACHE_REFRESH_DELAY = 300`
  matches it (expansion §1: "peers keep gear for at most 32 characters for
  300 s", `Cache.lua:10-14`) `[V]`; changing either side desynchronizes
  freshness semantics the tooltip already depends on.

### 3.2 Tier 2 — bounded persisted gear (new, Stage 4 creates it lazily)

```
TacoTipExtrasDB.gear = {
  [realmKey] = {
    [guid] = { t = <server-time>, ids = "1=123,5=456,..." },  -- sparse §2.2 run
  },
}
```

- **Created lazily** (absent table = no gear; nothing migrates, nothing
  rewrites — expansion §6.2 Stage-4 migration rule `[V]` logic).
- **Cap: 2,000 entries realm-scoped + age.** Not 20,000: gear at 20k is
  +2.0–2.8 MiB (expansion §4.1/§2.3 measured) `[V]`; 2,000 × ~150 bytes ≈
  **0.3 MiB**, inside the ≤0.5 MiB gear budget (expansion §6.3) `[V]`.
  Eviction: oldest-`t`-first (same "oldest timestamp first" semantics as
  `RankDB` cap enforcement, `TacoTip_Extras/RankDB.lua:322-340`) `[V]`,
  plus the 60-day age prune (`MAX_AGE_SECONDS`,
  `TacoTip_Extras/RankDB.lua:26`) applied to `gear` in the same
  `PruneAllRealms` pass (`TacoTip_Extras/RankDB.lua:649`) that already
  deletes emptied realm keys — gear rows die with their realm table, never
  orphaned.
- **Cap interplay with the amortized engine:** reuse the *semantics*, not
  the *structures*. `RankDB`'s `entryCount` + lazy `oldestHeap`
  (`TacoTip_Extras/RankDB.lua:44-62`) `[V]` exists because 20k rows make
  per-insert scans cost 21.5 ms. A 2,000-row gear table does not need a
  heap: a pairs-count at prune time (the `PruneStaleRecords` shape,
  `TacoTip_Extras/RankDB.lua:591-594`) `[V]` is O(2k) once per login, not
  O(20k) per insert. Do NOT thread gear rows through `entryCount`/
  `oldestHeap` — that couples two lifecycles with different caps and
  breaks the "visible set never exceeds MAX_CAPACITY" invariant the
  Stage-2 checks pin.
- **Dedup:** store iff `incoming.t > stored.t` (server-time epoch, same
  clock as record `timestamp`, `TacoTip_Extras/RankDB.lua:231`) `[V]`; older
  `D` → counted `gearStale`, no write. Equal `t` → first wins (no flap).
  Missing `t` → treated as 0 (never overwrites).
- **Local character always kept:** the owner's own guid is exempt from
  count-eviction (it is re-persisted on every own scan via `queueRankSync`,
  `TacoTip_Extras/Scanner.lua:112`) `[V]`; age-prune still applies (a
  60-day-absent local row is correctly dead).
- **`SAVED_VARIABLES_TOO_LARGE`:** the existing aggressive-prune path
  (`RankDB.PruneAggressive`, `TacoTip_Extras/RankDB.lua:695-696`,
  constants at `:692-693`: 7 days / 10,000 rows) `[V]` extends to gear as
  `PruneAllRealms(7, 1000)` on the gear table — gear halves before ranks
  do, because standings outrank item IDs.

---

## 4. Throttle interplay (one gear request must never starve rank sync)

Existing machinery (all `[V]` in the landed code):

- Token bucket 1 msg / 1.5 s, burst 3 (`THROTTLE_INTERVAL`,
  `TacoTip_Extras/RankSync.lua:12`, `MAX_BURST` at `:13`, refill at
  `:424-426`; queue cap 50, oldest-evicted at `Enqueue`) `[V]`.
- Probe machine: `probing/active/dead`, 120 s re-probe, 3-strike kill
  (`TacoTip_Extras/RankSync.lua:47-55`) `[V]`.
- Response gate: at most one `Q`-answer per 20 s + 1–4 s jitter
  (`RESPOND_INTERVAL`, `TacoTip_Extras/RankSync.lua:600`,
  `RESPOND_JITTER_MIN/MAX` at `:601`; gate at `:667`) `[V]`.

Gear rules (additive, no retuning of the above):

1. **Gear shares the bucket and the queue — no second bucket.**
   A second token pool doubles the real send rate past the 1 msg/s design
   (expansion §3.3 throttle: 10-per-prefix + 1/s refill; classic 1.13.4
   more severe) `[V]`. `D` chunks enqueue through the same `Enqueue`
   (door + FIFO-50 + `processQueue` token spend,
   `TacoTip_Extras/RankSync.lua:421-452`) `[V]`.
2. **Gear answers ride the same 20 s response gate.** `respondToQuery`
   already returns early inside the window (`:667`) `[V]`; the `G` handler
   MUST NOT bypass it with a direct `Enqueue`. Effect: a `G` storm during a
   login burst produces at most one gear answer per 20 s per client — the
   same flood control that protects `S`/`T` (comment at `:587-599`) `[V]`.
3. **Per-sender fairness: coalesce, don't queue.** Track
   `lastGearAnswerAt[senderGuid or senderName]` (module-local, session-only,
   bounded ring of 64 like the deleted whisper ring — size precedent only).
   A second `G` from the same sender while one is already queued-or-recent
   (<20 s) is coalesced: counted `gearCoalesced`, no second enqueue.
   Different senders are NOT coalesced against each other (one requester
   cannot suppress another's), but the 20 s gate + jitter serializes them.
   Starvation-freedom follows from FIFO + no-bypass: a `D` chunk never
   jumps ahead of an already-queued `S`/`T`, and a throttled `D` requeues
   without spending a token (existing `requeued` path at `:433-440`) `[V]`.
4. **Priority within the gate: `S` before `D` before `T`-tail.**
   When one `G` triggers both an `S` (own record, existing) and a `D`
   (gear), enqueue `S` first — standings seed before item detail. Digest
   `T` already follows `S` (`:706-741`) `[V]`; `D` slots between them.
5. **Probe traffic is never evicted by gear:** the probe-bypass rule
   (`enqueueChannelProbe` refuses to evict, `RankSync.lua:400-410`) `[V]`
   extends to gear chunks — a full queue (50) drops the *gear chunk*
   (counted `enqueueOversize`-adjacent `gearDroppedFull`, or reuse
   `enqueueOversize`), never the probe. Channel-liveness proof outranks
   item detail.

---

## 5. Per-client inspect API verification (do this table, or do not ship)

Feature-detect everything; gate nothing on client identity (repo rule,
expansion §6.4.7). Status key: **VERIFIED** = read in
`/home/sam/wow-ui-source` on the named branch(es); **ASSUMED** = needs the
stated in-game check; **UNKNOWN** = open question (§8).

Stage 4 touches ONE new inspect trigger (none, if the implementer follows
this brief — gear capture already exists) and reuses the Scanner+library
pipeline. Every call below is either (a) already called by the current
Scanner/library and Stage 4 only reads its output, or (b) called at display
time. The table marks which.

| API | Era 11509 | Anniv 20506 | Titan 38002 | Forever 16001 | Retail 120105 | status |
|---|---|---|---|---|---|---|
| `GetInventoryItemID(unit, slot)` — capture (`Scanner.lua:484`) | `FrameXML/Wrath/EquipmentManager.lua:88` (player use) `[V]`; `InspectPaperDollItemSlotButton_Update` path via `GetInventoryItemID(unit,…)` on Mainline `:170` live | same family file | same family file | `Mainline/InspectPaperDollFrame.lua:244` `[V]` | `Mainline/InspectPaperDollFrame.lua:170` `[V]` | VERIFIED usage all five; remote-unit reads via Scanner `captureSlot` already shipped `[V]` (`Scanner.lua:476`) |
| `GetInventoryItemLink(unit, slot)` — capture (`Scanner.lua:485`) | `Classic/InspectPaperDollFrame_Shared.lua:119` `[V]` | same file/line (family-identical) `[V]` | same file/line `[V]` | `Mainline/InspectPaperDollFrame.lua:261` (`SocketDisplay:SetItem(GetInventoryItemLink…)`) + `:210,220` `[V]` | `Mainline/InspectPaperDollFrame.lua:187` + `:136,146` `[V]` | VERIFIED all five |
| `CanInspect(unit)` — gate (`lib:CanInspect`, `LibForeverInspector.lua:3872`) | `PlayerScriptDocumentation.lua:54` `[V]` | `:54` `[V]` | `:54` `[V]` | `:53` `[V]` | `:55` `[V]` | VERIFIED docs all five; classic popup-on-refusal ordering handled by library (comment at `:3891-3910` classic-first) `[V]` |
| `NotifyInspect(unit)` — request (`TBC/Blizzard_InspectUI.lua:12,75`) | `TBC/Blizzard_InspectUI.lua:12` + `:75` `[V]`; `Vanilla/Blizzard_InspectUI.lua:6,61` `[V]` | same files `[V]` | same files `[V]` | `Camelot/Blizzard_InspectUI.lua:44,126` + `Mainline/Blizzard_InspectUI.lua:12,79` `[V]` | `Mainline/Blizzard_InspectUI.lua:12,79` + `TBC/Blizzard_InspectUI.lua:12,75` + `Vanilla/Blizzard_InspectUI.lua:6,61` `[V]` | VERIFIED all five |
| `INSPECT_READY` — async answer | `Classic/InspectPaperDollFrame_Shared.lua:5` (register) + `:26` (guid gate) `[V]`; `PaperDollInfoDocumentation.lua:175` literal `[V]` | same `[V]` | same `[V]` | `PaperDollInfoDocumentation.lua:352` literal `[V]`; `Camelot/Blizzard_InspectUI.lua:58,88` `[V]` | `PaperDollInfoDocumentation.lua:343` literal `[V]`; `Mainline/Blizzard_InspectUI.lua:26,38` `[V]` | VERIFIED all five |
| `CheckInteractDistance` — range probe (library) | `PlayerScriptDocumentation.lua:101` `[V]` | same `[V]` | same `[V]` | `:113` `[V]` | `:105` `[V]` | VERIFIED docs all five |
| `C_Item.IsItemDataCachedByID` — display/cache check (`Scanner.lua:317`) | `ItemDocumentation.lua:909` `[V]` | `:909` `[V]` | `:909` `[V]` | `:1520` `[V]` | `:1483` `[V]` | VERIFIED docs all five |
| `C_Item.RequestLoadItemDataByID` — async fill (`Scanner.lua:92`) | `ItemDocumentation.lua:1025` `[V]` | `:1025` `[V]` | `:1025` `[V]` | `:1710` `[V]` | `:1673` `[V]` | VERIFIED docs all five |
| `C_Item.GetItemInfo` — name resolve at display (`Scanner.lua:345`) | `ItemDocumentation.lua:393` (`MayReturnNothing = true`, 18 returns) `[V]` | `:393` `[V]` | `:393` `[V]` | `:626` `[V]` | argument/return shape per family docs `[V]` (grep `GetItemInfo` hits; exact live line varies by doc revision — re-confirm at touch time) | VERIFIED classic×3 + forever; live VERIFIED by name-hit, line re-confirm (see reconcile rule) |
| `ITEM_DATA_LOAD_RESULT` — async completion | `ItemDocumentation.lua:1130` `[V]` | (family-identical — confirm at touch) | (family-identical — confirm at touch) | (confirm at touch) | `ItemDocumentation.lua:1819` `[V]` | VERIFIED era + live; others ASSUMED family-identical |
| `GetItemStats` — socket capacity ONLY (mainline path, `Scanner.lua:245`) | absent (grep: no `GetItemStats` in classic_era generated docs) `[V]` | ASSUMED absent (same family) | ASSUMED absent (same family) | documented (`ItemDocumentation.lua:982` on live; forever per Scanner comment) `[V]` | `ItemDocumentation.lua:982` `[V]` | VERIFIED absent-era / present-live; Stage 4 does not call it (Scanner already feature-detects) |
| `CHAT_MSG_ADDON` payload order | `ChatInfoDocumentation.lua:615-628` (`prefix,text,channel,sender`) `[V]` | family-identical per prior audits | family-identical | family-identical | `ChatInfoDocumentation.lua:803-816` `[V]` | VERIFIED era + live; family-identical per §6.4.7 rule |
| `SendAddonMessageResult` enum (0/3/7/8) | `ChatConstantsDocumentation.lua:151-159` `[V]` | same `[V]` | same `[V]` | `:154-162` (offset by extra entries) `[V]` | `:151-159` `[V]` | VERIFIED all five |
| `MAX_ADDON_MESSAGE_LENGTH = 250` | `Blizzard_CooldownBroadcaster.lua:6` `[V]` | same file (confirm line at touch) | same file (confirm line at touch) | same file (confirm line at touch) | `:8` `[V]` | VERIFIED era + live; budget uses 240 regardless |

TOC coverage anchor: `TacoTip_Extras/TacoTip_Extras.toc:1`
(`11509, 20506, 38002, 16001, 120105`) — re-confirm at dispatch (Stage-3
brief §5 anchor) `[V]` (brief-read; re-grep, one line).

In-game checks that stay ASSUMED (cannot be closed offline):
remote-unit `GetInventoryItemID/Link` freshness timing per family
(INSPECT_READY latency, out-of-range units); numeric-ID
`C_Item.GetItemInfo(itemID)` vs link-form acceptance (docs type the arg as
`ItemInfo`); whether `CHANNEL` carries on Anniversary/Titanforge
(expansion §8 `[U]`, affects only dead-channel skip rate, not the `D`
design — same-transport rule already absorbs it).

---

## 6. Harness checks to add (names + what each pins)

Harness shape assumed: protocol block closure, `drainSends`, `fireEvent`,
direct `RankSync.HandlePayload(payload, chatType)` calls, browser suite
`rankbrowser_test.lua` (Stage-3 brief §6 shape `[V]` brief-read). Every
check below MUST fail on pre-Stage-4 code (no `G`/`D` handling → zero
`D` sends, zero gear buckets, gear table absent).

Wire/protocol (`load_test.lua`, protocol block):

1. `"G for owned guid yields one D on same transport"` — seed own record +
   own gear (`Scanner.GetCurrent`-shaped stub or direct gear-table seed);
   `HandlePayload("G;<ver>;<id>;<ownGuid>", "GUILD")` → `drainSends()` →
   exactly one `D;<ver>;<id>;<ownGuid>;1/1;<blob>` with
   `chatType == "GUILD"`, `#msg <= 240`, `gearStored` counted.
2. `"G on PARTY answers PARTY, never CHANNEL"` — same as (1) with
   `"PARTY"`; assert `chatType == "PARTY"` and zero `CHANNEL` sends
   (same-transport rule, oracle §2.1 gap pattern).
3. `"dead-channel G is a counted skip, no whisper"` — channel dead
   (probe-killed or id nil); `HandlePayload("G;…", "CHANNEL")` → zero sends
   on ANY transport + `answerNoTransport` incremented (reuse, not a new
   bucket). Fails pre-fix code that guesses a broadcast; pins the
   no-whisper invariant by asserting the send log contains no `WHISPER`.
4. `"unknown version G/D refused and counted"` — `G;9;…` (or whatever is
   not the landed `WIRE_VERSION`) → zero sends + `versionReject`
   incremented; `D;9;…` → `gearStored == 0` and `versionReject`
   incremented (diet-gate reuse, `RankSync.lua:233,759`).
5. `"G for unknown guid sends nothing, counts gearNoData"` — fresh guid
   with no session entry and no persisted gear → zero sends +
   `gearNoData == 1`.
6. `"oversize single-D sequences into 1/2 + 2/2, both under the door"` —
   seed a validator-max-shaped gear set (longest plausible guid +
   17 pairs) whose single-`D` exceeds 240; assert two `D` chunks
   `1/2` + `2/2`, every `#msg <= 240`, slot-sets disjoint, union ==
   full set, each chunk pair-ordered. Fails on code that refuses without
   splitting (the Stage-1 fat-digest bug pattern,
   `RankSync.lua:728-737`).
7. `"four-chunk cap refuses the fifth"` — synthetic blob requiring >4
   chunks (or direct `of > 4` injection) → refused + counted, no send.
   Pins the `of ≤ 4` bound.
8. `"stale D never overwrites newer gear"` — store `t=200` gear, ingest
   `D` with `t=100` same guid → stored `ids` unchanged +
   `gearStale == 1`; ingest `t=300` → stored + `gearStored == 1`.
9. `"starvation-freedom: G storm does not suppress S/T"` — enqueue a rank
   `Q` answer sequence, then N `G`s from distinct senders inside one 20 s
   window; drain with throttled ticks: assert the `S` for the `Q` still
   emits first (priority §4.4), all `D`s eventually emit across ticks,
   no `enqueueOversize` for rank traffic caused by gear, and
   `gearCoalesced >= N - served`. Then: same sender × 3 rapid `G`s →
   exactly one `D` + `gearCoalesced == 2` (per-sender coalescing).
10. `"request-id clamp on G echo"` — `G` with 240-char id → any `D`
    emitted has `#msg <= 240` and echoed id length ≤ 8 (Stage-1 id-cap
    pattern, `RankSync.lua:679,831`).

Storage (`load_test.lua`, Stage-2 block area):

11. `"gear table caps at 2000, local exempt, realm-scoped"` — seed
    2,000 + k gear rows in one realm + local guid; run the gear-prune
    entry point → count == 2,000, local present, oldest-`t` evicted first;
    second realm untouched (per-realm keying, `RankDB` precedent).
12. `"gear age-prune matches rank age semantics"` — one row past 60 days,
    one fresh; run `PruneAllRealms`-equivalent → stale gone, fresh kept,
    emptied realm key deleted (no orphans).
13. `"gear aggressive-prune halves before ranks"` — trip the
    `SAVED_VARIABLES_TOO_LARGE` path (or direct aggressive entry) →
    gear count ≤ 1,000 while rank count ≤ 10,000
    (`RankDB.lua:692-696` constants) `[V]`.

Browser (`rankbrowser_test.lua`):

14. `"gear panel renders cached IDs, uncached shows not-scanned"` —
    entry with `Cache`-shaped revision → `ShowGear` rows contain
    `item:<id>` text (`slotValueText`,
    `TacoTip_Extras/RankBrowser.lua:701`) `[V]`; entry with no cache →
    `GEAR_NOT_SCANNED` note (`TacoTip_Extras/RankBrowser.lua:817`) `[V]`,
    never blank rows mistaken for data.
15. `"D ingest updates panel without rescan"` — ingest a `D` for a guid
    with no session cache but with persisted gear → `ShowGear` reflects the
    new IDs (proves the persisted→render path, §7).

Debug:

16. `"GetDebugState exposes gear buckets alongside existing ones"` —
    extend the snapshot assertion pattern (`RankSync.GetDebugState`,
    `TacoTip_Extras/RankSync.lua:932`) to include the five new
    `gear*` keys once they fire; assert pre-existing keys
    (`answerNoTransport`, `versionReject`, `enqueueOversize`) still
    enumerate after the `G`/`D` edit (stride edits must not drop
    telemetry — Stage-3 brief §6.12 pattern).

---

## 7. Browser / gear-panel display notes

Current panel (`TacoTip_Extras/RankBrowser.lua:659-823`) `[V]`:

- Slot labels from the client (`SLOT_ROWS` globals + fallback,
  `:667-687`; `slotLabel`, `:689`) `[V]` — already localized, no locale
  keys needed for gear rows.
- Values from the **session cache only**: `Scanner.GetRemote(guid)` →
  `cached.revision.slots` → `slotValueText` (`:725-823`, link-preferred at
  `:701-719`) `[V]`; no-cache → `GEAR_NOT_SCANNED` note (`:817-818`) `[V]`.
- Click affordance already shipped (Tier A: `LB_TIP_CLICK_GEAR`,
  `RankBrowser.lua:399` + `rankbrowser_test.lua:975`) `[V]` brief-read.

Stage-4 display rules:

1. **Render precedence: fresh session > persisted gear > not-scanned.**
   `GetFreshRemote` hit → render links/IDs from the revision (existing
   path, unchanged). Else persisted `gear[realm][guid]` hit → render
   `item:<id>` per slot (muted/disabled colour to signal staleness —
   reuse the `|cff808080` dim the panel already uses for empty slots at
   `:812`) with the note line extended to "last synced <age>" (age from
   `t`; no new locale key — English + existing fallback pattern, Stage-3
   brief §3.3 rule). Else → existing `GEAR_NOT_SCANNED`.
2. **Resolve names at display, never persist them.** Persisted `ids` are
   numbers; the panel resolves via `C_Item.GetItemInfo` async-aware
   (existing `IsItemDataCachedByID` + `RequestLoadItemDataByID` +
   `ITEM_DATA_LOAD_RESULT` path, `Scanner.lua:311-345`) `[V]`. Uncached ID
   → render `item:<id>` literal (existing `slotValueText` fallback at
   `RankBrowser.lua:711-713`) `[V]`, never a spinner that blocks the panel.
3. **Fresh pull affordance:** clicking a row with only persisted (or no)
   gear sends `G` for that guid on the current transport (rate-limited by
   §4: coalesced per sender, 20 s gate) and re-renders on `D` ingest via
   the existing `Cache`/listener notify (`Cache.lua:publishState` →
   listeners) — no modal wait, no "loading…" row state. The panel is
   read-only w.r.t. inspection: it MUST NOT call `NotifyInspect` itself
   (inspection stays in Scanner/library; §8 Q2).
4. **No GS recompute from synced gear.** Synced IDs feed the panel only.
   Rank (`gs`/`ilvl`) continues to come from the `R` record — recomputing
   score from a partial or stale ID set would fork standings from the
   owner's authoritative `Scoring.Evaluate` (`Scanner.lua:598-614`) `[V]`.

---

## 8. What Section 4 must NOT touch (rejected on sight)

1. No `R/Q/S/T` stride change beyond the assumed Stage-3 13-field shape —
   no new record field, no second stride, no dual-protocol support (diet
   rule, `RankSync.lua:187-191`).
2. No root `schema` bump and no `rankSchema` semantics change beyond what
   Stage 2/3 defined (`Core.lua` future-schema path; expansion §2.2).
3. No `classID`/`source`/`specIcon` revival on the wire or in new writes
   (dead fields, expansion §2.2; Stage-3 §2.5 exclusion).
4. No full-link / enchant / gem / suffix / name persistence or sync —
   session-only by measurement (expansion §2.4, §3.2: single record 97%).
5. No compression (`C_EncodingUtil.*` or vendored) for `D` — §2.3.4 rules
   it out by measurement, not preference.
6. No `MAX_CAPACITY` change, no rank-index redesign, no per-insert
   full-table scan (amortized engine stands,
   `TacoTip_Extras/RankDB.lua:44-62`).
7. No `Cache.lua` 32/300 retune (`TacoTip_Extras/Cache.lua:10,14`) and no
   `REQUIRED_SLOTS` change (`TacoTip_Extras/Scanner.lua:14-17`) — the
   scorer input and the session lifecycle are frozen inputs to this stage.
8. No whisper send/queue/fallback in any form (oracle BLOCKER). No
   `Enqueue(..., "WHISPER", ...)` string anywhere in the diff.
9. No locale files (`Locale/*.lua` — owned by the locale desk; Stage 4
   adds zero locale keys: slot labels are client globals, ages render
   English-with-fallback like Stage 3 §3.3).
10. No `Tooltips.lua`, README, or TOC edits — behavior ships through
    `RankSync` (G/D) + `RankDB` (gear table + prune) + `Scanner`
    (owner/peer read, no new trigger) + `RankBrowser` (render precedence)
    + harness + CHANGELOG.

---

## 9. Open questions (refuse to guess)

1. **`[U]` `arena` single-best vs per-bracket (Stage-3 Q5 carryover):**
   if Stage 3 ships per-bracket arena, does any gear-adjacent display
   (e.g. "PvP set" hint) need the split? Default: no — gear answers carry
   no PvP context. Decide before the Stage-3 stride freezes, not here.
2. **`[A]` Should `G` trigger an active `NotifyInspect` of a nearby unit,
   or only read already-held data?** This brief specifies read-only
   (owner current + fresh peer cache; else `gearNoData`). An inspect-on-`G`
   mode would need `CanInspect` + range + `INSPECT_READY` round-trip
   budgeting per requester and risks inspect-throttle spam the library
   guards exist to prevent (`LibForeverInspector.lua:3872-3910`,
   `INSPECT_DELAY`/`INSPECT_PENDING_TIMEOUT`). Verify in game whether
   on-demand inspect latency is usable before ever adding it — default is
   NOT to add it.
3. **`[A]` Numeric-ID `C_Item.GetItemInfo(itemID)`:** docs type the arg as
   `ItemInfo` (`ItemDocumentation.lua:393` classic_era `[V]`); by-ID entry
   points exist (`:909`/`:1025` classic_era `[V]`) but the numeric-ID call
   form is unverified in game. If it rejects numerics, the panel keeps the
   `item:<id>` literal + link-form resolution path (expansion §4.1
   fallback) — verify with `/dump C_Item.GetItemInfo(12345)` per client.
4. **`[U]` Cross-realm `G`/`D` delivery:** whether addon messages cross
   realms on each branch is still unknown (expansion §8 `[U]`). The gear
   table is realm-keyed so the answer is moot for storage; the
   same-realm inspect gate (`recordIsSameRealm` precedent) is NOT
   re-applied to gear reads (a `D` for a guid files under the local realm
   only if that guid is already a rank row — else it persists gear-only,
   never a phantom standing). Confirm cross-realm delivery in game to
   decide whether a realm check on `G` is worth the code.
5. **`[U]` `CHANNEL` on Anniversary/Titanforge** (expansion §8 carryover):
   affects only the dead-channel skip rate. The `D` design already absorbs
   either answer (same-transport + counted skip). Close via the
   five-client checklist, not this diff.
6. **`[U]` Gear-table exact cap (2,000):** 2,000 ≈ 0.3 MiB is derived from
   the §2.3 model (within ~10% of the repo's 276-byte claim, expansion
   §2.3 `[V]`), not from live realm data. If in-game sampling shows the
   working set (own + regularly-inspected) exceeds 2,000, raise to 3,000
   (≈0.45 MiB, still inside 0.5 MiB) — but re-run the §2.3-equivalent
   table and record the new worst case in the stride comment. Do not raise
   past 3,000 without operator sign-off.
7. **`[U]` `D` chunk `of` cap (4):** a 17-pair ID set needs at most 2;
   4 is headroom for longer future IDs. If itemIDs grow past 7 digits
   broadly (Retail inflation), re-run §2.3 math — the cap is a constant,
   not a negotiation.
8. **`[A]` Retail/Forever self-only ratings interplay:** none — gear
   carries no rating. Stated only to prevent scope creep: any "show PvP
   gear" request is a new brief, not a Stage-4 hunk.
