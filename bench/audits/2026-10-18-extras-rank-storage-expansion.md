# TacoTip_Extras — how to store and sync the ranking data, and which expanded data is real

- **Date:** 2026-10-18
- **Desk:** operator-requested read-only analysis (subagent session), extending the
  prior pass.
- **Relationship to the existing review:** this report **extends**
  `bench/audits/2026-10-18-extras-rank-system-review.md` (same day, same
  add-on). It re-verifies that review's key claims against the source itself
  (§1), then answers the operator's new questions: storage (§2), sync (§3),
  expanded-data feasibility (§4), competitor research (§5), and a staged
  recommended architecture (§6). It supersedes nothing in the earlier file; it
  corrects two of its evidence labels and one of its open questions.
- **Revision read:** working tree at `HEAD 0395d99` plus the uncommitted v1.2.3
  edits. All files cited here are the working-tree versions.
- **Evidence labels (CAIRN.md):** `[V]` VERIFIED (read in the source or produced
  by a command I ran), `[A]` ASSUMED (say what would verify), `[U]` UNKNOWN.
- **Harness state at this audit time:**
  `bash TacoTip_Extras/Tests/harness/run_all.sh` →
  `TOTAL 42 invocations: 42 passed, 0 failed` on lua5.1, lua5.4, luajit `[V]`.
- **Client source:** `/home/sam/wow-ui-source`, `origin/`-qualified branches:
  `classic_era` 1.15.9.70003, `classic_anniversary` 2.5.6.70006,
  `classic_titan` 3.80.2.70315, `forever` 1.60.1.70374, `live` 12.1.5.70391 `[V]`.
- **Measurements** in §2.3/§3.2/Appendix A were produced by a scratch harness
  under `/tmp/opencode/rankx` that loads the repo's real `RankDB.lua` /
  `RankSync.lua` and the upstream `LibDeflate.lua`; nothing in the repo was
  modified except this file.

---

## 0. Executive summary

The earlier review's three headline findings hold under re-measurement (§1).
This pass adds what the operator asked for, and the answer is dominated by four
facts that were not in the earlier file:

1. **The custom channel `ttgssync` does not work on Classic Era.** Blizzard
   removed the `CHANNEL` chat type from `C_ChatInfo.SendAddonMessage` on Classic
   in patch 1.13.3 ("This will prevent addons from communicating over custom,
   player-created chat channels"), keeping PARTY, RAID, GUILD and WHISPER. The
   add-on's primary transport is CHANNEL (`RankSync.lua:11,197-199,272-274`) and
   it never reads the send result (`RankSync.lua:137-145`), so on Classic Era
   the channel path fails silently and the only live transports are GUILD and
   PARTY/RAID. `[V]` for the Blizzard post; `[A]` that Anniversary/Titanforge
   inherited the restriction (verification: log `SendAddonMessage`'s result in
   game on each client).
2. **The wire limit is now citable.** Blizzard's own `Blizzard_CooldownBroadcaster`
   defines `MAX_ADDON_MESSAGE_LENGTH = 250` and packs rows against it on all five
   branches `[V]`; the community API reference states 255 characters, printable,
   no NUL `[V-URL]`. The earlier review's `[U]` on this can be closed.
3. **Expanded data splits cleanly into "cheap row fields" and "expensive gear".**
   Measured: a typical record serialises to 76 bytes; adding guild + spec + PvP
   takes it to 113; adding 17 item IDs takes the same record to 258 — **over the
   message limit**, so gear can never ride in a normal record. Compression of a
   single record is pointless (97% of raw); it only pays on batches (40 records →
   16%) `[V]`.
4. **Gear should be self-published on demand, not gossiped.** Only the owner of a
   character reliably holds its current gear: peers keep gear for at most 32
   characters for 300 s (`Cache.lua:10-14`). So a gear query can only be answered
   by the owner (from `Scanner.GetCurrent().revision`, `Scanner.lua:910-912`) or
   by a peer that happened to scan the target minutes ago.

The recommended architecture (§6) is staged: fix delivery first (answers on the
query's own channel, send-result checking, size guard), then storage hygiene
(prune actually runs, dead fields stop being written, realm attribution), then
the cheap expanded fields (guild, level, spec token, PvP), then on-demand gear.

---

## 1. Re-verification of the earlier review

Every claim below was re-derived from source; measurements were re-run.

| Earlier claim | Status | Evidence |
|---|---|---|
| `StoreRecord` cost grows with DB size; 23 ms/insert at 20k | **Confirmed** | `RankDB.lua:175-189`; re-measured **21.5 ms/insert at 20k** (100 inserts = 2.151 s) `[V]` |
| Cold index rebuild ~88 ms at 20k | **Confirmed** | re-measured **0.101 s** `[V]` |
| `PruneStaleRecords` has no production caller | **Confirmed** | grep: definition `RankDB.lua:389`, test call `load_test.lua:3012`, README/CHANGELOG claims, nothing else `[V]` |
| Answers are channel-only while queries advertise 3 channels | **Confirmed** | `RankSync.lua:318-319,338-339` vs `260-275` `[V]` |
| Request id echoed unbounded; no serializer-side size check | **Confirmed** | `RankSync.lua:424`, `331-337`; `Enqueue` checks only non-empty (`163-174`) `[V]` |
| Validator-max record is 327 bytes | **Confirmed** | re-measured 327 `[V]` |
| `classID` / `source` are written but never read outside RankDB/RankSync | **Confirmed** | grep over `TacoTip_Extras/*.lua` `[V]` |
| `specIcon` is stored but never on the wire | **Confirmed** | `SerializeRecord` `RankSync.lua:71-86` has no specIcon; renderer reads `entry.specIcon` `RankBrowser.lua:351-373` `[V]` |
| 42/42 harness invocations green | **Confirmed** | re-run §meta `[V]` |
| **Correction 1:** "255-byte limit not documented in client source `[U]`" | **Closed** | `Blizzard_CooldownBroadcaster.lua:6` (classic_era/anniversary/titan), `:8` (forever/live): `MAX_ADDON_MESSAGE_LENGTH = 250`, packed against at `:25-27`; Warcraft Wiki states 255 characters `[V]` |
| **Correction 2:** "cross-realm records file under the local realm" | **Confirmed as a live path, with a latent hook** | `StoreRecord` routes by `realm or record.realm` (`RankDB.lua:162`) but the wire format carries no realm and `ValidateRecord` drops unknown fields (`104-154`) `[V]`. Blizzard's UnitPopup uses `UnitIsSameServer` on all five branches (`UnitPopupSharedButtonMixins.lua:2310` on live, `:2272` on classic_era; `UnitPopupSharedUtils.lua:60`), so a same-realm gate exists for scan-time `[V]` |
| **Correction 3 (new finding):** the transport the earlier review assumed works everywhere does not work on Classic Era | **New** | Kaivax, 2019-12-09 (URL below) `[V]`; code paths `RankSync.lua:11,55-69,197-199,272-274` `[V]` |

Additional state verified for this report:

- `Scanner` already captures `itemID` and the full `nativeLink` per occupied slot
  (`Scanner.lua:451-455, 484-494`) and keeps them session-only in `Cache`
  (`Cache.lua:10-14`); the gear panel reads exactly that cache
  (`RankBrowser.lua:628-636`) `[V]`.
- The local player's own completed scan is readable at any time via
  `Scanner.GetCurrent()` (`Scanner.lua:910-912`, state set at `598-620`) `[V]`.
- `CHAT_MSG_ADDON` delivers `prefix, text, channel, sender, …` on all five
  branches (`ChatInfoDocumentation.lua:615-628` classic_era, `:803-816` live)
  and `RankSync.onEvent` reads only `arg1`/`arg2` (`RankSync.lua:512-516`) `[V]`.
- `C_Item.GetItemInfo` is documented with 18 returns and `MayReturnNothing = true`
  on all five branches (`ItemDocumentation.lua:393` classic_era/anniversary/titan,
  `:626` forever, `:604` live); by-ID entry points exist
  (`IsItemDataCachedByID` `:909` classic / `:1483` live;
  `RequestLoadItemDataByID` `:1025` classic / `:1673` live) `[V]`.
- `SAVED_VARIABLES_TOO_LARGE` exists on all five (`AddOnsDocumentation.lua:389`
  classic branches, `:412` live/forever) and is not registered by the add-on
  (grep) `[V]`. No byte threshold is documented anywhere in the client source
  `[V]`.

---

## 2. Q1 — The best way to store the data

### 2.1 What the current shape is (verified)

```
TacoTipExtrasDB = {                       -- TacoTip_Extras.toc:8
  schema = 2,                             -- Core.lua:322 (settings only)
  settings = { ... },
  ranks = {                               -- RankDB.lua:58-72
    [realmKey] = {                        -- RankDB.lua:37-56
      [guid] = { guid, name, faction, class, classID, specName,
                 specIcon, gs, ilvl, timestamp, source }   -- RankDB.lua:141-153
    }
  }
}
```

`realmKey` = `GetNormalizedRealmName` → `GetRealmName` → `"DefaultRealm"`
(`RankDB.lua:37-56`); both functions are documented on all five branches
(`PlayerScriptDocumentation.lua:294` classic_era, `:540` live, `:651` forever) `[V]`.

### 2.2 Recommended shape (v2)

Keep the realm→GUID rank store. Split it from the gear store, and stop writing
fields nobody reads:

```
TacoTipExtrasDB = {
  schema     = 2,                 -- DO NOT bump: Core.lua:289-302 treats >2 as a
                                  -- future schema and force-disables equipment
                                  -- display; root schema is settings-scoped
  rankSchema = 2,                 -- NEW: ranks/gear shape version (absent = 1)
  settings   = { ... },
  ranks = {
    [realmKey] = {
      [guid] = {
        name, faction, class,
        spec,                     -- NEW: spec token/id (see §4.4); legacy specName kept for old rows
        gs, ilvl, timestamp,
        realm,                    -- NEW: normalized realm (absent = local)
        guild,                    -- NEW: optional, value-tested (see §4.2)
        level,                    -- NEW: optional (see §4.5)
        pvpRank, arena,           -- NEW: optional, per-client (see §4.3)
      }                           -- classID / source / specIcon: NOT written any more
    }
  },
  gear = {                        -- NEW, separate cap and lifecycle
    [realmKey] = {
      [guid] = { t = <timestamp>, ids = "1=123,2=456,16=789" }  -- order-packed, empty omitted
    }
  },
}
```

Why each choice:

- **`rankSchema` separate from `schema`.** `Core.initializeDatabase` branches on
  `persistedRoot.schema > 2` and, when true, copies the *whole* root (ranks
  included) into a runtime table and disables the equipment display
  (`Core.lua:289-302`). Bumping the root schema for a ranks change would
  therefore change equipment behaviour and double peak load-time memory. A
  separate key is zero-risk `[V]`.
- **Drop `classID`, `source`, `specIcon` from new writes.** They are dead
  (grep, §1) and cost ~45 bytes/record in my SavedVariables model
  (250 → 205 bytes) `[V]`. `specIcon` is additionally unbounded
  (`RankDB.lua:136-139`) and only ever populated on Retail/Forever.
- **`realm` on the record.** `StoreRecord` already prefers `record.realm` when
  the explicit argument is absent (`RankDB.lua:162`), so routing support exists;
  what is missing is parsing it on the wire and persisting it through
  `ValidateRecord`. Add it, and file inbound records under the sender's realm;
  treat a missing realm as local (all existing rows) `[V]`.
- **`gear` as a side table.** Gear is the only field that would blow the budget:
  measured +161 bytes/record in the SV model (310 → 471), i.e. **+3.1 MiB at
  20k** — 9.0 MiB total `[V]`. A separate table with its own cap (recommend
  2,000 entries ≈ 0.4 MiB) and LRU eviction keeps the rank store bounded and
  lets the feature degrade without touching standings.
- **Per-realm keying stays.** Do not introduce a global key; the UI is
  whole-realm by design (`README.md:93`, `RankBrowser.lua:949-954`) and the
  browser filters assume one realm `[V]`.

### 2.3 Size budget (measured model)

SavedVariables are written by the client as Lua source with per-field keys,
quotes, tabs and `-- [n]` comments (format illustrated by the AllTheThings
maintainer in the Blizzard forum thread cited in §5) `[V-URL]`. My model renders
the same shape and counts bytes; it lands within ~10% of the repo's own
276-byte claim (`README.md:161`), which is a good cross-check:

| record shape | bytes/record (model) | 20,000 records |
|---|---:|---:|
| current fields | 250 | **4.8 MiB** |
| current minus `classID`/`source` | 205 | 3.9 MiB |
| + guild | 238 | 4.5 MiB |
| + guild + spec token + pvp rank + arena | 310 | **5.9 MiB** |
| + 17 gear item IDs | 471 | **9.0 MiB** |

**Recommended budget:** keep `MAX_CAPACITY = 20000` (`RankDB.lua:25`), target
≈6 MiB for `ranks`, ≤0.5 MiB for `gear`, and enforce the *gear* cap by count +
age. A byte budget for `ranks` is optional; if added, enforce it at prune time
(one pass), never per insert.

### 2.4 What belongs in persisted storage vs session cache

| data | where | why |
|---|---|---|
| identity, gs, ilvl, timestamp | persist (`ranks`) | the ranking exists to survive logout; `README.md:161` `[V]` |
| guild, level, spec token, PvP snapshot | persist, value-tested | each is ≤20 bytes and changes rarely `[V]` (measured) |
| gear item IDs | persist **only** for a bounded set (own character + last N scanned), otherwise on demand | 2.0-2.8 MiB at 20k otherwise `[V]` |
| full item links, enchants, gems, scan revisions, freshness | session only (`Cache.lua`) | a native link is ~80-150 bytes/slot; the panel is explicitly session-only (`README.md:165`, `Cache.lua:10-14`) `[V]` |
| item names | never persist | localized per client and ~2× the size of IDs; resolve at display via `C_Item.GetItemInfo` `[V]` (docs) |
| runtime counters (sends, drops, throttles) | session only | no value across logout |

### 2.5 Migration impact on existing saved data

- **No rewrite required.** New fields are additive; every reader already tolerates
  missing fields (`ValidateRecord` defaults at `RankDB.lua:124-152`; the browser
  falls back to class when `specName` is empty, `RankBrowser.lua:394-398`) `[V]`.
- **Dead fields disappear lazily.** Old rows keep `classID`/`source`/`specIcon`
  until the next store for that GUID or until the 60-day prune removes them.
  That is acceptable; a one-time rewrite pass at login is not worth the risk
  (and `PruneStaleRecords` already walks the table when wired).
- **`realm`:** never re-file existing rows; absent means local.
- **`gear`:** created on first use; absent changes nothing.
- **Downgrade:** an older client reading `rankSchema = 2` will keep working
  because it ignores unknown keys; it will simply not read `gear`. Root
  `schema` stays 2, so the older client does not take the future-schema path `[V]`.
- **Realm transfers:** the old realm key stays behind. The wired prune should
  also delete realm tables that have no record inside the age window; today
  nothing ever iterates `TacoTipExtrasDB.ranks` (grep) `[V]`.

---

## 3. Q2 — The best way to sync it

### 3.1 Transports, per client (the decisive table)

| chatType | Retail / Forever | Classic Era | TBC Anniv. / Titanforge | source |
|---|---|---|---|---|
| PARTY / RAID | ✔ | ✔ | ✔ | wiki; used today `RankSync.lua:184-188` `[V]` |
| INSTANCE_CHAT | ✔ | ✔ | ✔ | wiki `[V-URL]`; not used by the add-on today |
| GUILD | ✔ | ✔ | ✔ | wiki; used today `RankSync.lua:190-194` `[V]` |
| WHISPER | ✔ | ✔ | ✔ | wiki; **not used today**; `sender` is in the event payload `[V]` |
| CHANNEL | ✔ | **✘ removed in 1.13.3** | `[A]` likely also removed | Kaivax post `[V]`; code uses it as the primary path `RankSync.lua:11,197-199,272-274` `[V]` |
| SAY / YELL | ✘ | ✔ (heavily throttled) | `[A]` | wiki `[V-URL]` |

Consequences, in order of importance:

1. **CHANNEL must stop being the answer path.** Today `S`/`T` go to CHANNEL only
   (`RankSync.lua:318-319,338-339`). On Classic Era that is a dead end even
   before the earlier review's "answer on the query's channel" fix. The correct
   rule is: **answer on the channel the query arrived on** (GUILD → GUILD,
   PARTY → PARTY, RAID → RAID, CHANNEL → CHANNEL only where it works), with
   WHISPER to the `sender` as the fallback when no channel target is available.
   The `sender` field is delivered (`ChatInfoDocumentation.lua:622` classic_era)
   and simply discarded (`RankSync.lua:512-516`) `[V]`.
2. **WHISPER is the only targeted, silent transport that works on all five.**
   It also bypasses the per-prefix throttle outside instanced content
   (wiki §"Message throttling") `[V-URL]`. Caveat: whispering an offline player
   prints a system message (wiki) `[V-URL]`, which would leak chat clutter into
   a background sync; use it as a fallback, not the default answer path `[A]`.
3. **INSTANCE_CHAT is free coverage.** In dungeons/BGs the add-on currently
   falls back to PARTY (`RankSync.lua:184-188`) where INSTANCE_CHAT is the
   intended channel; adding it is a one-line change `[V]` (wiki) `[V-URL]`.

### 3.2 Message sizes vs the limit (measured)

Limit: 255 characters (wiki; printable, no NUL) `[V-URL]`; Blizzard's own code
budgets 250 (`Blizzard_CooldownBroadcaster.lua:6`/`:8`) `[V]`. The repo asserts
255 in its own tests (`load_test.lua:3220-3228`) `[V]`. **Recommend an internal
budget of 240** to leave room for the prefix and any future envelope.

| payload | bytes | fits? |
|---|---:|---|
| typical `R` today | 76 | yes |
| validator-max `R` (128-char guid etc.) | 327 | **no** |
| `R` + guild + spec + pvp + arena | 113 | yes |
| `R` + all of the above + 17 item IDs | **258** | **no** |
| gear blob alone (17 IDs, order-packed) | 102-144 | yes |
| `T;id;` + two expanded records | 232 | yes |
| `T;id;` + two validator-max records | 660 | **no** |

Rules that follow:

- **Never put gear in the record.** Gear must be its own message.
- **Two records per `T` remains viable** only with a size check; add the guard
  the earlier review asked for (B2) before extending the record.
- **Request ids must be capped** (re-measured: `S;` + a 240-char id + a 76-byte
  record = **319 bytes**) `[V]`.
- **Compression: not for single records.** Measured with LibDeflate on the
  actual shapes: one expanded record 98 → 95 encoded bytes (97%, no gain); a
  17-ID gear blob 144 → 82 (57%); a 40-record batch 3733 → 583 (16%) `[V]`.
  Compress only if a batch ever needs to move.
- If compression is ever wanted, **`C_EncodingUtil.CompressString` /
  `DecompressString` / `SerializeCBOR` are documented on all five branches**
  (`EncodingUtilDocumentation.lua:11/59/134` classic_era,
  `:11/62/142` forever/live) and Blizzard's own `Blizzard_CooldownViewer` uses
  them on all five (`CooldownViewerSettingsDataStoreSerialization.lua:232-244`
  classic_era, `:269-281` live) `[V]` — no LibDeflate vendoring needed `[A]`
  that the C namespace is callable from third-party code on the classic
  branches (feature-detect; verify in game).

### 3.3 Query/response vs broadcast — what can realistically travel

Keep the current model; do not adopt HonorSpy's whole-database gossip:

- **Broadcast only what changes and what is tiny:** a record (76-113 B) on gear
  change / scan completion. Today each record is sent up to 3× (group + guild +
  channel, `RankSync.lua:176-200`) `[V]`; with CHANNEL dead on Classic and
  GUILD/PARTY the only live paths, the third copy is wasted work there.
- **Query → answer:** `Q` (short id) → `S` (own record) + up to two `T`
  messages (4 digest records) (`RankSync.lua:298-345`) `[V]`. This is the right
  shape: it seeds a fresh install in one round trip.
- **Gear on demand only:** new `G;<id>;<guid>` → `D;<id>;<guid>;<blob>`, one
  message, answered by the owner first. A peer answers only if its session
  cache holds that GUID fresh.
- **Do not mirror.** 20,000 records × 310 B ≈ 6.2 MB; at 240 B/message that is
  ~26,000 messages, ~7.2 hours at the documented 1 message/second refill
  (and the send queue holds 50, `RankSync.lua:163-167`) `[V]` arithmetic. The
  current digest approach is the only one that fits the transport.
- **Throttle:** the wiki documents a 10-message allowance per prefix, refilled
  at 1/s, and warns that too much simultaneous traffic across prefixes can
  disconnect the client; Classic got a *more severe* throttle in 1.13.4 `[V-URL]`.
  The add-on's token bucket is 1 msg / 1.5 s, burst 3 (`RankSync.lua:12-13,
  147-161`) — conservative and fine, **provided the result is checked**
  (today it is discarded, `RankSync.lua:137-145`) `[V]`.
- **Versioning:** the record stride is duplicated deliberately
  (`RankSync.lua:347-352, 374-375`) and ingestion advances a fixed 10 fields
  (`385-404`) `[V]`. Any new field changes the stride, so either (a) carry the
  new fields as a separate message type, or (b) version the record token
  (`R2;…` with an explicit stride) — and because the add-on is **unreleased**
  (`README.md:169`), (b) can be done once, now, without dual-protocol support.
  Rule for the future: never reuse a token with a different stride.

### 3.4 What the wire can and cannot carry (one-line answers)

| data | can it travel? | how |
|---|---|---|
| identity + gs + ilvl + timestamp | yes, today | `R`, 76 B |
| realm, guild, level | yes | trailing record fields, ≤+25 B |
| spec | yes, **as a token/id, not a localized name** | ~2-4 B |
| PvP rank (Classic Era), arena ratings (TBC/Titanforge) | yes, snapshot | ≤+20 B |
| Retail/Forever arena rating | **no** (self-only API) | display only, label "self-reported" |
| 17 gear item IDs | yes, but **only as its own message** | `D`, 102-144 B |
| item names | no | resolve locally at display |
| full links / enchants / gems | no | session cache only |
| the whole database | no | 26k messages ≈ 7 h |

---

## 4. Q3 — Expanded data, feature by feature

For each feature: which Blizzard API returns it, on which of the five clients
(per-branch evidence), storage cost per record, and sync verdict.

### 4.1 Item IDs (and names) per equipped slot

- **APIs.** `GetInventoryItemID(unit, slot)` and `GetInventoryItemLink(unit,
  slot)`. Blizzard's own inspect UI calls them per branch:
  `classic_era Interface/AddOns/Blizzard_InspectUI/Classic/InspectPaperDollFrame_Shared.lua:119`
  (`GetInventoryItemLink(InspectFrame.unit, …)`),
  `live Interface/AddOns/Blizzard_InspectUI/Mainline/InspectPaperDollFrame.lua:136,146,170`
  (both, plus `GetInventoryItemID`), same shape on `forever`
  (`…/Mainline/InspectPaperDollFrame.lua:210,220`), `classic_anniversary` and
  `classic_titan` (`…/Classic/InspectPaperDollFrame_Shared.lua:119`) `[V]`.
  `GetInventoryItemID` is additionally used by `FrameXML/Wrath/EquipmentManager.lua:88`
  on the three classic branches `[V]`.
- **Availability:** all five, for inspected players and for group members `[V]`
  (Blizzard usage). The add-on already captures both values for every occupied
  slot (`Scanner.lua:451-455, 484-494`) `[V]`.
- **Storage cost:** 17 slots × ~6 chars = **102-144 bytes/record** (measured
  blob 144 bytes with explicit slot prefixes; 102 if packed in slot order with
  empty slots omitted) `[V]`. At 20k that is +2.0-2.8 MiB.
- **Names:** `C_Item.GetItemInfo(itemInfo)` is documented on all five with 18
  returns and `MayReturnNothing = true` (`ItemDocumentation.lua:393`
  classic_era/anniversary/titan, `:626` forever, `:604` live) `[V]`. It is
  asynchronous when uncached; the add-on already has the retry path
  (`C_Item.IsItemDataCachedByID` + `C_Item.RequestLoadItemDataByID` +
  `ITEM_DATA_LOAD_RESULT`, `Scanner.lua:90-93, 310-324`) `[V]`. Passing a
  numeric ID is `[A]` (the docs type the argument as `ItemInfo`; by-ID entry
  points exist, but verify in game) — the safe pattern is to store IDs and
  resolve names at display time, never persist names.
- **Sync verdict: on-demand / bounded-persist only.** A record + gear is 258
  bytes measured — over the limit — so gear travels in its own `D` message,
  answered by the owner first (only the owner reliably has current gear;
  peers keep 32 GUIDs for 300 s, `Cache.lua:10-14`) `[V]`. Persisting gear for
  all 20k records costs 9.0 MiB (§2.3) `[V]`; persist it only for a bounded
  set, or not at all.

### 4.2 Guild name (and guild filtering)

- **API.** `GetGuildInfo(unit)` → `guildName, rankName, rank` (return order
  confirmed by Blizzard usage: `classic_era Blizzard_CharacterFrame/Vanilla/PaperDollFrame.lua:95`
  `local guildName, title, rank = GetGuildInfo("player")`;
  `live Blizzard_UIPanels_Game/Mainline/TabardFrame.lua:91`
  `local guildName, rankName, rank = GetGuildInfo("player")`; also used on
  `forever`, `classic_anniversary`, `classic_titan` — e.g.
  `Blizzard_FrameXML/Mainline/AlertFrameSystems.lua:345` on live,
  `:338` on classic_era) `[V]`.
- **Availability:** `"player"` on all five `[V]`. **Remote units are `[A]`**:
  every Blizzard call site I found uses `"player"` (grep, all five branches);
  the engine's unit-token form is not exercised by Blizzard UI, so verify in
  game that `GetGuildInfo(unit)`/`GetGuildInfo("target")` returns data for an
  inspect target. Fallback if it does not: leave guild blank and rely on the
  guild roster path for guildmates only.
- **Storage cost:** +20-33 bytes/record (measured: 205 → 238 with guild alone;
  the field name `["guild"]` plus a ~15-char value) `[V]`. At 20k: +0.6 MiB.
- **Sync verdict: viable in the record.** ≤~25 bytes of a 240-byte budget, no
  chunking. The browser filter is a UI change only (`RankBrowser.lua:979-1003`
  already builds a dropdown; a guild filter needs a populated dropdown or a
  text filter, plus a matching predicate in `GetLeaderboard`,
  `RankDB.lua:368-386`) `[V]`. Guild names are not unique across realms —
  store the realm with them (§2.2) or filter by `guild` alone within the
  realm board `[A]`.

### 4.3 PvP: arena rating (TBC / Retail) and Classic Era rank/honor

Per client, because this is the feature with the most client divergence:

- **Classic Era 11509 — VERIFIED, inspectable.** `Blizzard_InspectUI/Vanilla/InspectHonorFrame.lua`
  calls `RequestInspectHonorData()` / `HasInspectHonorData()` (`:35,39`), then
  `GetInspectHonorData()` (12 returns: session/week/lifetime HK and honor,
  last-week standing, `lifetimeRank`, `:41`), `GetPVPRankInfo(UnitPVPRank("target"))`
  (`:48`), and `GetInspectPVPRankProgress()` (`:72`) `[V]`. The file loads only
  for vanilla: `Blizzard_InspectUI_Classic.toc`
  `Vanilla\InspectHonorFrame.lua [AllowLoadGameType vanilla]` `[V]`.
  Note the data is **request-then-event**: `INSPECT_HONOR_UPDATE` fires after
  `RequestInspectHonorData`, so the add-on must call it and wait (the same
  pattern HonorSpy uses) `[V]`.
- **TBC Anniversary 20506 and Titanforge 38002 — VERIFIED, inspectable arena
  teams.** `Blizzard_InspectUI/Classic/InspectPVPFrame.lua` (loaded
  `[AllowLoadGameType tbc, wrath, cata]`, per the same TOC) calls
  `GetInspectArenaTeamData(i)` and reads
  `teamName, teamSize, teamRating, teamPlayed, teamWins, playerPlayed, playerRating, …`
  (`:145,157`), and `GetInspectHonorData()` (`:234`) `[V]`. Guarded by
  `GetCurrentArenaSeasonUsesTeams()`; the teamless path uses
  `GetInspectArenaData(index)` (`:66`) `[V]`. Player-side `GetArenaTeam(index)`
  is used by `Blizzard_UIPanels_Game/Classic/PVPFrameBase.lua:53,61,92`
  (loaded `[AllowLoadGameType tbc, wrath, cata, mists]`) `[V]`.
  Classic Era *documents* an `ArenaTeam` namespace (`ArenaTeamDocumentation.lua`
  is in the branch's docs TOC) but no arena content exists and the inspect file
  is not loaded for vanilla — **documentation presence is not availability**;
  do not show arena fields on Classic Era `[V]` for the TOC gate, `[A]` for the
  "no arena content" claim.
- **Retail 120105 / Forever 16001 — self-only.** `GetPersonalRatedInfo(bracketIndex)`
  (returns rating, seasonBest, weeklyBest, played, won, …) is used by
  `Blizzard_PVPUI/Mainline/Blizzard_PVPUI.lua:1372,1623`, and that file's TOC is
  `AllowLoadGameType: mainline` (`Blizzard_PVPUI_Mainline.toc:7`), i.e. it does
  **not** load on the classic branches `[V]`. Own honor: `UnitHonor("player")` /
  `UnitHonorLevel("player")` (`live Blizzard_ActionBar/Mainline/HonorBar.lua:8-15`;
  `forever Blizzard_FrameXML/PVPHonorSystem.lua:177-189`) `[V]`; documented on
  both (`UnitDocumentation.lua:1484` live, `:1558` forever) `[V]`. There is no
  inspect API for another player's rated rating that I could find in the source
  (grep: no `GetInspect…Rated…`) `[V]` (absence of evidence, source-scoped).
- **Storage cost:** Classic Era rank + progress ≈ 8-12 bytes; arena per bracket
  ≈ 6-8 bytes × 3 brackets ≈ 20 bytes `[V]` (model: +30 bytes for
  `pvpRank` + `arena` together).
- **Sync verdict:** viable as a **snapshot with its own timestamp**, but treat
  it as advisory: honor/arena data decays weekly and only updates when the
  add-on re-inspects the player (`RequestInspectHonorData`). Do not include it
  in the digest; send it with the record on change. Retail/Forever ratings are
  **not sync-viable as verified data** — self-reported only; label them as
  such if shown `[A]`.

### 4.4 Specialization

- **Retail/Forever:** `C_SpecializationInfo.GetSpecializationInfo(specIndex,
  isInspect, isPet, inspectTarget, gender, groupIndex, classID)` — used by
  Blizzard at `live/forever Blizzard_CooldownViewer/CooldownViewerUtil.lua:73`
  and in `Blizzard_CharacterFrame/Cata/PaperDollFrame.lua:539,545` `[V]`.
  The repo's inspector already resolves localized spec name + icon for these
  two only: `LibForeverInspector.lua:5279-5295` ("Returns nil on the Classic
  family, which has no equivalent") and `:3664-3691` (modern branch stores
  `specName`/`specIcon`; the classic branch stores only talent points) `[V]`.
- **Classic Era / TBC Anniversary / Titanforge:** the modern spec API is not
  loaded — on the classic branches every `C_SpecializationInfo.GetSpecializationInfo`
  call site sits in a `[AllowLoadGameType cata, mists]` file
  (`Blizzard_CharacterFrame.toc`, verified) `[V]`. The classic path is talent
  tabs: `GetNumTalentTabs`/`GetTalentInfo` (`LibForeverInspector.lua:3313-3340`)
  `[V]`. A localized name is still possible on all five via
  `GetSpecializationInfoForClassID(classID, index, sex)` — documented on all
  five (`SpecializationSharedDocumentation.lua:10`) and called by
  `Blizzard_ClassMenu/Blizzard_ClassMenu.lua` (`:115` on classic_era/live,
  `:110` on forever), whose TOC has **no
  game-type gate** `[V]`; whether it returns the TBC/Wrath talent-tree names on
  those clients is `[A]` (verify in game).
- **Current behaviour:** because `Scanner.queueRankSync` calls only
  `GetLocalizedSpecName` (`Scanner.lua:159-164`) `[V]`, `specName` is `""` on
  the three classic clients (the rank row then renders the class token,
  `RankBrowser.lua:394-398`) `[V]`.
- **Storage cost:** a spec token/id ≈ 2-4 bytes; a localized name ≈ 10-20 bytes.
- **Sync verdict: viable, but send a token, not a name.** `specName` is a free
  string (`RankDB.lua:135`) and is sent on the wire (`RankSync.lua:80`) `[V]`,
  so today a German client publishes "Elementar" to an English client's
  leaderboard. Store a spec id/token and localize at render (via
  `GetSpecializationInfoForClassID` or the library's `spec_table`,
  `LibForeverInspector.lua:232-247`) `[V]`.

### 4.5 Other cheap fields worth considering (brainstorm, ranked)

| field | API / evidence | cost | verdict |
|---|---|---|---|
| level | `UnitLevel` (`Scanner.lua:199-210` already reads it for the revision) `[V]` | ~2-3 B | **worth it**; enables a level filter; caveat: `-1` for un-inspected units `[A]` |
| guild rank | 3rd return of `GetGuildInfo` `[V]` | ~2 B | cheap once guild is stored; low value |
| honor kills (week/lifetime) | `GetInspectHonorData` returns `[V]` | ~8 B | only with the PvP block, Classic/TBC/Wrath |
| gear revision timestamp | local scan time, `Scanner.lua:173-175` `[V]` | ~10 B | **worth it** for `D` dedup ("is your gear newer than mine?") |
| talent points per tab | library already builds them (`LibForeverInspector.lua:3682`) `[V]` | 3-12 B | not worth syncing (classic-only, unstable) |
| achievements | `GetComparisonAchievementPoints` (WotLK/Retail only, library `:3694-3698`) `[V]` | 3-5 B | no: client-limited and off-theme |
| professions / zone | no inspect API found for classic `[V]` (source-scoped absence) | — | no |
| full item links / enchant + gem detail | available session-only `[V]` | ~2 KB/record | **no**: blows both budgets; the panel already states "not scanned" honestly (`RankBrowser.lua:650-655`) `[V]` |

---

## 5. Q4 — Competitor research

Distinguish **addon behaviour verifiable from source/docs** from **forum claims**.

### 5.1 HonorSpy (the direct ancestor of this design)

- **Source-verified** (`kakysha/HonorSpy`, branch `classic`):
  - Storage: `HonorSpyDB.factionrealm.currentStandings[playerName]` keyed by
    **`Name-Realm`** (`utils.lua: getFullUnitName` strips spaces from the realm;
    `honorspy.lua: store_player` rejects names without `-`). This is the
    realm-attribution fix this add-on lacks `[V-URL]`.
  - Sync: AceComm + AceSerializer + **LibDeflate** with a 4-hex length prefix
    for integrity (`honorspy.lua: prefixMessage` / `prepareMessageForComms`),
    broadcast on RAID/INSTANCE_CHAT/GUILD **and YELL** on death (`broadcast`),
    i.e. whole-DB gossip — the model this report rejects for size reasons `[V-URL]`.
  - Scan gate: `C_PlayerInfo.UnitIsSameServer(PlayerLocation:CreateFromUnit(unitID))`
    before inspecting — the same-realm gate I recommend adopting
    (`UnitIsSameServer` is used by Blizzard UI on all five branches: e.g.
    `UnitPopupSharedButtonMixins.lua:2310` live, `:2272` classic_era) `[V]`.
  - Ranking model: 14 pool-percentage brackets + RP formula (`GetBrackets`,
    `Estimate`), i.e. it estimates standing from a collected pool `[V-URL]`.
  - **Status: dead by Blizzard's own change.** The repo README says the Classic
    Era ranking rework made progress independent of other players' honor/rank,
    "which makes honorspy purposeless and outdated" `[V-URL]`. That is a
    caution against copying a pool-estimation model: rank here is a simple
    sorted position (`RankDB.lua:194-205`) and should stay that way `[V]`.

### 5.2 TradeSkillMaster (the scale reference)

- TSM's add-on source is not public. Its support site hosts the SavedVariables
  guidance (`support.tradeskillmaster.com`; the article surfaced in search
  describes the file under the `_retail_`/`_classic_`/`_classicera_`
  SavedVariables folder as `TradeSkillMaster` — `[A]`, search-surfaced
  description, not read on-page), and the third-party Linux TSM app documents
  that it "downloads auction data, and writes `AppData.lua` for the TSM addon"
  (<https://github.com/exceptionptr/tsm-app-linux>) `[V-URL]`.
- **Forum claim (not source-verified):** a Blizzard forum thread has a forum
  participant stating TSM's databases are "in the 100+ megabyte range" and that
  TSM staggers DB processing over frames rather than doing it in one `[V-URL]`.
  Treat as a claim; it does not change this add-on's 5-6 MiB design, but the
  *pattern* (do heavy DB work after login, spread over frames, not during load)
  is consistent with what `RankDB` already does via dirty flags `[A]`.
- The same thread's opening post documents the **SavedVariables file format**
  (human-readable Lua with per-index comments and tabulation) and that
  minifying it shortened AllTheThings' load time — evidence for the size model
  in §2.3, and for treating file size as a login-time cost, not just disk `[V-URL]`.

### 5.3 Libraries and generic write-ups (what the ecosystem actually does)

- **LibDeflate** (`SafeteeWoW/LibDeflate`, README + source): pure-Lua
  DEFLATE/zlib; benchmark ratio 3.68 at level 5 on a 132 KB WeakAuras string,
  compress+decompress ~145 ms in Lua 5.1; the README explicitly warns it is for
  small files and should not be used on multi-MB data. It also provides
  `EncodeForWoWAddonChannel` because compressed bytes are not printable and
  must contain no NUL `[V-URL]`. My own measurement on this add-on's shapes:
  single record 97%, gear blob 57%, 40-record batch 16% `[V]` (§3.2).
- **LibSerialize** (README): serializes arbitrary values, is "best paired with
  LibDeflate", and warns that if you skip compression the required channel
  encoding "will likely inflate the size … by a considerable amount"; also
  offers an async mode "to prevent locking the game while processing" `[V-URL]`.
- **AceComm** (WowAce page): "allows you to send messages of unlimited length …
  automatically split the messages into multiple parts and rebuild them on the
  receiving end"; prefix max 16 characters; uses ChatThrottleLib for throttling;
  `SendCommMessage` takes a distribution and target and a per-chunk callback `[V-URL]`.
- **ChatThrottleLib** (WowAce): exists specifically to keep add-on traffic
  "from exceeding the output rate limit in WoW that otherwise causes players to
  disconnect"; the wiki's `SendAddonMessage` page tells authors to use it or
  AceComm "otherwise you will blow up the server" `[V-URL]`.
- **Warcraft Wiki `C_ChatInfo.SendAddonMessage`** — the single most useful
  reference for this design: 255-character messages, no NUL; prefix ≤16 chars;
  chat-type support matrix (CHANNEL ✘ Classic, WHISPER ✔ both, SAY/YELL
  Classic-only); per-prefix allowance 10 messages, +1/s, disconnect risk; the
  Classic patch notes (1.13.3 removed CHANNEL, 1.13.4 tightened throttling) `[V-URL]`.
- **Blizzard's own add-on code is the best in-repo precedent:** 
  `Blizzard_CooldownBroadcaster` packs rows greedily against
  `MAX_ADDON_MESSAGE_LENGTH = 250` on all five branches (`:6`/`:8`, `:25-27`) `[V]`,
  and `Blizzard_CooldownViewer` uses `C_EncodingUtil.SerializeCBOR` +
  `CompressString` + `EncodeBase64` for persisted settings on all five
  (`CooldownViewerSettingsDataStoreSerialization.lua:232-244` classic_era) `[V]`.
- **Other ranking add-ons:** searches surfaced WotLK-era "coolstats"-style
  addons and parse-score overlays, but nothing with a verifiable storage/sync
  design beyond HonorSpy `[V]` (search results; not audited). No
  GearScore-lineage add-on I could find persists a synced realm database —
  original GearScore computed locally `[A]` (recollection; not verified).

---

## 6. Q5 — Recommended architecture ("the best way"), staged

### 6.1 The architecture in one paragraph

Keep the realm→GUID rank table as the durable store, but make it *small,
attributed and pruned*: identity + score + a handful of ≤20-byte optionals,
realm-tagged, dead fields dropped, 60-day prune actually invoked, capacity
enforced without a full-table scan per insert. Keep gear in a separate,
capped, on-demand table — or don't persist it at all and answer gear queries
live from the owner. On the wire, answer on the channel the query arrived on
(with WHISPER as the portable fallback), treat CHANNEL as optional rather than
primary, cap every message at 240 bytes before enqueue, check send results, and
keep the query/own-record/digest model rather than mirroring the database.

### 6.2 Stages

**Stage 1 — delivery correctness (no storage change).**
1. Thread `CHAT_MSG_ADDON`'s channel (`arg3`) and sender (`arg4`) into
   `handlePayload`/`respondToQuery`; answer `S`/`T` on the same chat type, with
   WHISPER to `sender` as the fallback when no channel target exists
   (`RankSync.lua:512-516, 318-319, 338-339`) `[V]`.
2. Stop sending CHANNEL-first on Classic: either feature-detect it (send once,
   check the result, mark dead) or gate it behind a working probe; add
   INSTANCE_CHAT alongside PARTY/RAID `[V]` (wiki).
3. Capture `SendAddonMessage`'s result in `rawSend`; count
   `Success`/`AddonMessageThrottle`/`InvalidChannel`/`ChannelThrottle`; expose
   in `/ttgsdebug` (`RankSync.lua:137-145`, `Core.lua:593-628`) `[V]`.
4. Cap the request id (≤8 chars) and add an enqueue-time size guard at 240
   bytes; drop optional fields or skip the record instead of enqueueing a
   message that cannot be sent `[V]` (re-measured 327-byte record and 319-byte
   `S`).
5. Re-broadcast the local record once after the channel join (fixes the
   first-login hole) `[V]` (earlier review §3.6).
- *Migration:* none. *All five:* pure Lua + the wiki-verified chat types.
- *Verify:* the harness captures every send (`load_test.lua:3148-3172`) and has
  a real event dispatcher (`fireEvent`, `load_test.lua:1981-1999`); add checks
  "a `Q` with channel `GUILD` produces a send with `chatType == "GUILD"`",
  "a 240-char request id produces no message longer than 240", "a throttled
  send is counted and re-queued". Each fails on the current code `[V]`.

**Stage 2 — storage hygiene (additive, no rewrite).**
1. Wire `PruneStaleRecords` into a once-per-session login pass over
   `TacoTipExtrasDB.ranks` (defer with `C_Timer.After` to keep the loading
   screen clean), and delete empty/aged realm tables `[V]`.
2. Replace the per-insert full-table scan with an amortised count
   (`RankDB.lua:175-189`); keep the documented semantics (oldest timestamp
   first, ≤20,000 visible) `[V]` (measured 21.5 ms/insert at the cap).
3. Stop writing `classID`/`source`/`specIcon`; keep reading them if present `[V]`.
4. Add `realm` to `ValidateRecord` and the wire; file inbound records by
   `record.realm` (the routing hook already exists, `RankDB.lua:162`); gate
   scan-time records with `UnitIsSameServer` `[V]`.
5. Register for `SAVED_VARIABLES_TOO_LARGE` and, on it, prune aggressively
   (`AddOnsDocumentation.lua:389` classic / `:412` live) `[V]`.
- *Migration:* no rewrite; old rows keep dead fields until refreshed/pruned;
  absent `realm` = local; nothing is re-filed.
- *Verify:* seed stale+fresh rows in two realm keys, fire
  `PLAYER_ENTERING_WORLD`, assert the stale row and the empty realm key are
  gone; store `MAX_CAPACITY + k` synthetic records and assert the visible count
  is exactly `MAX_CAPACITY` and the k oldest timestamps are the ones evicted;
  assert a cross-realm-tagged `R` lands under its own realm key.

**Stage 3 — cheap expanded fields (row-level).**
1. Guild (`GetGuildInfo`, with the remote-unit caveat), level (`UnitLevel`),
   spec token (`GetSpecializationInfoForClassID`/talent tabs on Classic;
   `C_SpecializationInfo` on modern), PvP snapshot (per §4.3) — each stored
   only when it passes a value test.
2. Wire: extend the record stride once, pre-release, with an explicit version
   token and a single documented stride (`RankSync.lua:347-352, 374-375`) `[V]`.
3. Browser: guild filter + level column/filter; localize the spec token at
   render (`RankBrowser.lua:394-398, 979-1003`) `[V]`.
- *Migration:* additive; old records render blanks; no re-file.
- *Verify:* round-trip tests for the new stride and for the old payload; a
  guild-filtered leaderboard test alongside the existing class-filter tests
  (`rankbrowser_test.lua:671-704`) `[V]`; a `T` message with two expanded
  records stays ≤240 bytes.

**Stage 4 — gear on demand.**
1. New `G;<id>;<guid>` request and `D;<id>;<guid>;<blob>` answer; the owner
   answers from `Scanner.GetCurrent().revision` (`Scanner.lua:910-912`), peers
   only from a fresh session cache (`Cache.lua:10-14`) `[V]`.
2. Optional bounded persistence: `gear[realmKey][guid] = {t, ids}` capped at
   ~2,000 entries with LRU+age eviction; the local character always kept `[V]`.
3. Gear panel: render item IDs via `C_Item.GetItemInfo` (async-aware, the
   existing `ITEM_DATA_LOAD_RESULT` path) and fall back to the current
   "not scanned" note when the ID is uncached `[V]`.
- *Migration:* new table, created lazily; nothing else changes.
- *Verify:* a `G` for the harness player produces one `D` ≤240 bytes; a `G` for
  an unknown GUID produces nothing; the gear table stays under its cap when
  seeded with cap+k entries; a stale `D` (older `t`) does not overwrite newer
  gear.

### 6.3 Performance budget (measured, so the stages can be held to it)

| operation | today | target |
|---|---:|---:|
| `StoreRecord` at 20k | **21.5 ms/insert** `[V]` | ≤0.5 ms (amortised count) |
| first read after dirtying at 20k | **0.101 s** `[V]` | unchanged (one rebuild per burst is fine) |
| login with 20k rows | file load + first index | unchanged ±; prune deferred out of the loading screen |
| wire record | 76 B `[V]` | ≤113 B with the new fields |
| gear message | — | ≤144 B, one per request |
| send rate | 0.67 msg/s `[V]` | ≤1 msg/s, successes counted |

### 6.4 All-five-clients concerns, consolidated

1. **CHANNEL addon messages are removed on Classic Era** (Blizzard post) and
   likely on the other classic-family clients `[A]` — never depend on them.
2. **WHISPER works everywhere** but can print "Player is offline" `[V]` — fallback only.
3. **Spec is modern-only in the engine**; Classic needs the talent-tab path,
   which the vendored library already implements but the scanner does not call `[V]`.
4. **PvP differs by client**: rank/honor on Classic Era, arena teams on
   TBC/Wrath, self-only ratings on Retail/Forever `[V]`.
5. **`GetItemStats` is absent on the three classic branches** and already
   feature-detected (`README.md:171`, `Scanner.lua:238-247`) `[V]`.
6. **The channel response path must not assume `channelID` exists** — the
   join is asynchronous and `channelID` is resolved once (`RankSync.lua:55-69`) `[V]`.
7. **Feature-detect everything, gate nothing on client identity** — the repo's
   own stated rule (`README.md:171`) and the reason the harness can run all
   five clients offline `[V]`.

### 6.5 How each stage is verified with the repo's offline harness

- The harness loads the real TOC files against a mocked client for all five
  clients and two behaviour variants per interpreter (`run_all.sh:93-106`) `[V]`.
- It already (a) captures every `SendAddonMessage` call with `chatType` and
  `target` (`load_test.lua:3148-3155`), (b) runs `C_Timer.After` synchronously
  so the deferred answer path is reachable (`:3159-3163`), (c) dispatches real
  events to registered frames (`fireEvent`, `:1981-1999`), and (d) drives the
  real browser (`rankbrowser_test.lua`) `[V]`.
- Therefore every check named in §6.2 is expressible without the game; the
  remaining in-game-only items are the four `[A]`/`[U]` runtime questions in §8.

---

## 7. DO / DON'T

**DO**

1. Answer on the query's own channel; keep WHISPER as the portable fallback.
2. Cap and check every outbound message (240 bytes, request id ≤8); count send
   results.
3. Wire `PruneStaleRecords` to login and drop empty realm keys.
4. Make capacity accounting amortised; never raise `MAX_CAPACITY` again.
5. Add `realm` to the record and the wire; use `UnitIsSameServer` at scan time.
6. Store gear IDs separately, capped, on demand; resolve names at display.
7. Store a spec token and localize at render.
8. Persist guild/level/PvP only when non-empty; drop `classID`/`source`/`specIcon`.
9. Keep `rankSchema` separate from the root `schema`.
10. Verify each change with a harness check that fails before it.

**DON'T**

1. Don't rely on CHANNEL addon messages on Classic.
2. Don't mirror the database (measured: ~26k messages ≈ 7 h at 1 msg/s).
3. Don't compress single records (measured 97%); only batches pay.
4. Don't store item names or full links in SavedVariables.
5. Don't put gear in the record (measured 258 B — over the limit).
6. Don't bump the root `schema` for a ranks change.
7. Don't add fields to `R` without an explicit stride version.
8. Don't treat Retail arena ratings as verified data for other players.
9. Don't build a pool/bracket estimation model — Blizzard's rework killed it
   (HonorSpy's own README).
10. Don't add fallback copies of every record to every transport; fix the
    answer path instead.

---

## 8. Open questions (labeled, not answered)

- `[U]` Whether `CHANNEL` addon messages are also disabled on TBC Anniversary
   2.5.6 and Titanforge 3.80.2. Verify in game: call `SendAddonMessage` with
   `"CHANNEL"` and log the `SendAddonMessageResult` (the enum exists on all five,
   `ChatConstantsDocumentation.lua:154,159` classic_era) `[V]`.
- `[A]` `GetGuildInfo(unit)` for a non-player unit. Verify: inspect a target and
   log the three returns.
- `[A]` `C_Item.GetItemInfo(itemID)` with a numeric ID (docs type the argument
   as `ItemInfo`); verify in game, else use the cached-by-ID + link path.
- `[A]` `C_EncodingUtil.*` callable from add-ons on the classic branches
   (documented + used by Blizzard UI there, but not yet seen in a third-party
   context).
- `[U]` Whether addon messages cross realms on each branch; the realm field
   makes the answer moot for storage, but it decides whether the gate is even
   needed.
- `[U]` Whether `GetNormalizedRealmName` returns a space-stripped realm on all
   five (HonorSpy strips spaces manually; `utils.lua` `getFullUnitName`).
- `[U]` The exact engine SavedVariables serializer byte count; the §2.3 model
   is within 10% of the repo's own 276-byte figure, and the model's *deltas*
   are the numbers used for decisions.

---

## Appendix A — measurements performed

Scratch harness `/tmp/opencode/rankx/measure.lua` (loads the repo's real
`RankDB.lua`/`RankSync.lua`; LibDeflate 1.0.2 downloaded from its upstream repo
to the same scratch dir; Lua 5.1.5):

```
wire: typical record bytes                           76
wire: validator-max record bytes                     327
expanded: gear blob 17 item IDs (chars)              144
expanded wire: guild only                            91
expanded wire: guild+spec+pvp                        98
expanded wire: all + arena                           113
expanded wire: all fields + gear blob                258
compress: one expanded record (no gear) raw=98       encoded=95 (97%) in 0.2 ms
compress: gear blob only raw=144                     encoded=82 (57%) in 0.2 ms
compress: 40-record batch raw=3733                   encoded=583 (16%) in 1.0 ms
SV model: current record bytes                       250
SV model: current minus classID/source               205
SV model: + guild                                    238
SV model: + guild + spec + pvp + arena               310
SV model: + gear IDs (17 slots)                      471
SV model: 20k current                                4.8 MiB
SV model: 20k + guild + spec + pvp + arena           5.9 MiB
SV model: 20k + everything incl gear                 9.0 MiB
StoreRecord x100 at n=20000 (s)                      2.151 (21.51 ms each)
cold BuildSortedIndices at 20k (s)                   0.101
leaderboard size after cap enforcement               20000
```

Harness: `bash TacoTip_Extras/Tests/harness/run_all.sh` →
`TOTAL 42 invocations: 42 passed, 0 failed`.

Second scratch run `/tmp/opencode/rankx/verify_sizes.lua` (repo serializer):

```
R bytes:                                    76
S + 240-char id:                            319
expanded record (guild+spec+pvp+arena):     113
T;id; + two expanded:                       232
T;id; + two validator-max:                  660
```

## Appendix B — URLs cited

- Blizzard (Kaivax), 2019-12-09, WoW Classic 1.13.3 LUA API change (CHANNEL
  removed; PARTY/RAID/GUILD/WHISPER kept; SAY/YELL added):
  <https://us.forums.blizzard.com/en/wow/t/wow-classic-patch-1133-lua-api-change/384543>
- Warcraft Wiki, `C_ChatInfo.SendAddonMessage` (255 chars, prefix ≤16,
  chat-type matrix, throttle 10 + 1/s, disconnect warning, library
  recommendations): <https://warcraft.wiki.gg/wiki/API:C_ChatInfo.SendAddonMessage>
- HonorSpy source (storage keyed `Name-Realm`, LibDeflate+AceComm, whole-DB
  broadcast, `UnitIsSameServer` gate, bracket model):
  <https://github.com/kakysha/HonorSpy> (branch `classic`: `honorspy.lua`,
  `utils.lua`, `README.md`)
- LibDeflate README/source: <https://github.com/SafeteeWoW/LibDeflate>
- LibSerialize README: <https://github.com/rossnichols/LibSerialize>
- AceComm documentation (unlimited-length splitting, prefix max 16, throttle
  warning): <https://www.wowace.com/projects/ace3/pages/api/ace-comm-3-0>
- ChatThrottleLib overview: <https://www.wowace.com/projects/chatthrottlelib>
- Blizzard forum, "Option to Compress SavedVariables" (SavedVariables file
  format, minification/load-time experience, TSM "100+ MB" claim — forum
  claim): <https://us.forums.blizzard.com/en/wow/t/option-to-compress-savedvariables/1752880>
- TSM support site (AppData.lua / SavedVariables locations):
  <https://support.tradeskillmaster.com/> (articles on `AppData.lua` and
  add-on-manager conflicts)
- Third-party TSM app that documents writing `AppData.lua` for the add-on:
  <https://github.com/exceptionptr/tsm-app-linux>
