# GearScore Server Rank Browser & Sync Implementation Plan

- **Goal:** Deliver a server-wide GearScore leaderboard and peer-to-peer sync engine inside `TacoTip_Extras` v1.0.1 (HonorSpy style).
- **Architecture Spec:** [docs/superpowers/specs/2026-10-12-gearscore-server-rank-browser-and-sync-design.md](file:///home/sam/TacoTip-Gearscore-TBC/docs/superpowers/specs/2026-10-12-gearscore-server-rank-browser-and-sync-design.md)
- **Target Environments:** Classic Era (`11509`), TBC Anniversary (`20506`), WotLK Titanforge (`38002`), WoW Forever (`16001`), Retail Live (`120100`).
- **Estimated Scope:** 5 modular tasks with test-driven validation and zero-warning gates.

---

## File Structure & Responsibilities

| File | Status | Responsibility |
| :--- | :--- | :--- |
| `TacoTip_Extras/RankDB.lua` | **New** | In-memory and persistent `TacoTipExtrasDB.ranks` storage, sanitization, dirty-flag sorting, $O(1)$ rank lookup table, 60-day prune, and capacity capping. |
| `TacoTip_Extras/RankSync.lua` | **New** | Peer-to-peer gossip protocol over hidden channel `ttgssync`, `GUILD`, and `PARTY`/`RAID`. Serializer/deserializer, token-bucket rate limiter, and anti-poisoning guards. |
| `TacoTip_Extras/RankBrowser.lua` | **New** | Blizzard-styled leaderboard window (`/tt ranks`), FauxScrollFrame row renderer, faction tabs (`[My Faction]`, `[Opposite]`, `[All Realm]`), class filters, live search, and top-3 medal badges. |
| `TacoTip_Extras/Tooltips.lua` | **Modify** | Hook to display optional `Rank: #14 (#2 Warrior)` line under GearScore/iLvl on cached player mouseovers. |
| `TacoTip_Extras/Options.lua` | **Modify** | Add `show_server_rank` toggle, "Open Leaderboard" button, and database reset controls. |
| `TacoTip_Extras/TacoTip_Extras.toc` | **Modify** | Load order registration for `RankDB.lua`, `RankSync.lua`, `RankBrowser.lua`, and version bump to `1.0.1`. |
| `TacoTip_Extras/CHANGELOG.md` | **Modify** | Complete release notes for v1.0.1. |
| `TacoTip_Extras/Tests/harness/load_test.lua` | **Modify** | Automated test suite covering storage, sorting, sync serialization, token-bucket throttling, and tooltip rank lines. |

---

## Tasks

### Task 1: RankDB — Storage, Sanitization, Dirty-Flag Sorting & $O(1)$ Rank Lookups

**Deliverables:**
- Create `TacoTip_Extras/RankDB.lua`.
- Add test cases to `TacoTip_Extras/Tests/harness/load_test.lua`.

**Steps:**
1. **Write failing unit tests** in `load_test.lua`:
   - `RankDB:SanitizationAndStorage`: asserts rejection of invalid GUIDs, non-numeric GearScores, values > 12,000, and future timestamps.
   - `RankDB:SortingOrder`: asserts sorted order descending by GearScore, then iLvl, then timestamp.
   - `RankDB:LookupMath`: asserts constant-time rank resolution (`overallRank`, `factionRank`, `classRank`).
   - `RankDB:PruneAndCap`: asserts eviction of records older than 60 days and cap enforcement at 5,000 records.
2. **Run tests** (`bash TacoTip_Extras/Tests/harness/run_all.sh`) to confirm failure.
3. **Implement `TacoTip_Extras/RankDB.lua`**:
   - Initialize `TacoTipExtrasDB.ranks` partitioned by realm name.
   - Implement `TacoTip_Extras.RankDB:StoreRecord(record)` with validation and last-write-wins timestamp check.
   - Implement dirty-flag sorted index builder `BuildSortedIndices()`.
   - Implement `TacoTip_Extras.RankDB:GetPlayerRank(guid, faction, class)`.
   - Implement `TacoTip_Extras.RankDB:PruneStaleRecords(maxAgeDays, maxCapacity)`.
4. **Register in TOC**: Add `RankDB.lua` to `TacoTip_Extras.toc`.
5. **Run tests** and verify 100% pass across `lua5.1`, `lua5.4`, and `luajit`.
6. **Run luacheck** (`luacheck TacoTip_Extras/RankDB.lua`) ensuring 0 warnings.

---

### Task 2: RankSync — P2P Gossip Protocol, Channel Management & Rate Limiting

**Deliverables:**
- Create `TacoTip_Extras/RankSync.lua`.
- Add unit tests in `load_test.lua`.

**Steps:**
1. **Write failing unit tests** in `load_test.lua`:
   - `RankSync:PacketSerialization`: asserts encoding/decoding of single record (`R`) and delta handshake (`D`).
   - `RankSync:TokenBucketThrottling`: asserts that queued messages obey the 1 packet per 1.5s rate limit and 3 burst limit.
   - `RankSync:IncomingPacketHandling`: asserts correct handoff to `RankDB:StoreRecord`.
2. **Run tests** to confirm failure.
3. **Implement `TacoTip_Extras/RankSync.lua`**:
   - Register addon message prefix `TACO_GS_SYNC` via `C_ChatInfo`.
   - Implement hidden background channel joiner for `ttgssync` with chat frame suppression (`ChatFrame_RemoveChannelGroup`).
   - Implement `SendRecord(record, channel, target)` with token-bucket queue.
   - Implement `CHAT_MSG_ADDON` / `CHAT_MSG_CHANNEL` dispatcher.
   - Connect `Scanner.lua` on successful inspect completion to queue a record broadcast.
4. **Register in TOC**: Add `RankSync.lua` to `TacoTip_Extras.toc`.
5. **Run tests** and verify passing assertions.
6. **Run luacheck** on `TacoTip_Extras/RankSync.lua` ensuring 0 warnings.

---

### Task 3: Tooltip & Scanner Integration

**Deliverables:**
- Update `TacoTip_Extras/Tooltips.lua` and `TacoTip_Extras/Scanner.lua`.
- Add unit tests in `load_test.lua`.

**Steps:**
1. **Write failing unit tests** in `load_test.lua`:
   - `Tooltips:ServerRankLine`: asserts that when a unit has a stored rank, the tooltip receives `|cFFFFFFFFRank: |r#X (#Y Class)` below GearScore.
   - `Tooltips:ServerRankToggle`: asserts that when `show_server_rank = false`, no rank line is injected.
2. **Run tests** to confirm failure.
3. **Implement modifications in `Tooltips.lua`**:
   - Read `TacoTip_Extras.RankDB:GetPlayerRank(guid, faction, class)`.
   - Format rank string with clean white prefix and tier/highlight coloring.
   - Inject immediately after average item level line.
4. **Connect inspect trigger in `Scanner.lua`**:
   - When local inspect or self-scan completes, pass profile to `RankDB:StoreRecord` and notify `RankSync:QueueBroadcast`.
5. **Run tests** and verify passing assertions.
6. **Run luacheck** on `Tooltips.lua` and `Scanner.lua` ensuring 0 warnings.

---

### Task 4: RankBrowser UI — Leaderboard Window & Controls

**Deliverables:**
- Create `TacoTip_Extras/RankBrowser.lua`.
- Update `TacoTip_Extras/Options.lua` and slash commands in `Core.lua`.

**Steps:**
1. **Implement `TacoTip_Extras/RankBrowser.lua`**:
   - Create standard Blizzard dialog frame `TacoTipRankFrame` (`600x480`).
   - Implement 3 top tabs: `[My Faction]`, `[Opposite Faction]`, `[All Realm]`.
   - Implement Filter Bar: class dropdown, search editbox, "Force Sync" button.
   - Implement FauxScrollFrame table with reusable row buttons.
   - Display columns: Rank `#`, `Name`, `Class & Spec` (colored with spec icon), `GearScore`, `iLvl`, `Last Seen`.
   - Highlight current player standing in the footer banner.
2. **Implement slash command handler**:
   - Register `/tt ranks`, `/ttrank`, `/tt leaderboard` to toggle `TacoTipRankFrame`.
3. **Add Options Controls**:
   - Checkbox: `Show Server Rank on Tooltip` (defaults to `true`).
   - Button: `Open Server Leaderboard` (opens `TacoTipRankFrame`).
   - Button: `Purge Database Cache`.
4. **Register in TOC**: Add `RankBrowser.lua` to `TacoTip_Extras.toc`.
5. **Run luacheck** on all touched files ensuring 0 warnings.

---

### Task 5: Version Bump, Verification & Documentation

**Deliverables:**
- Update `TacoTip_Extras.toc` to `## Version: 1.0.1`.
- Update `TacoTip_Extras/CHANGELOG.md` with full v1.0.1 release notes.
- Synchronously update `MEMORY.md`, `memory-bank/activeContext.md`, and `memory-bank/progress.md`.

**Steps:**
1. Bump version to `1.0.1` in `TacoTip_Extras.toc`.
2. Add v1.0.1 release notes to `TacoTip_Extras/CHANGELOG.md` and root `CHANGELOG.md`.
3. Run complete static analysis (`luacheck TacoTip_Extras/`).
4. Run complete test suites (`bash TacoTip_Extras/Tests/harness/run_all.sh` and `bash TacoTip_Forever/Tests/harness/run_all.sh`).
5. Verify 100% clean output across all interpreters.
