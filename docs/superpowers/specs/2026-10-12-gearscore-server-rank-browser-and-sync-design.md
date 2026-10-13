# Specification: GearScore Server Rank Browser & Sync Engine (HonorSpy Style)

- **Date:** 2026-10-12
- **Module:** `TacoTip_Extras`
- **Target Environments:** Classic Era (`11509`), TBC Anniversary (`20506`), WotLK Titanforge (`38002`), WoW Forever (`16001`), Retail Live (`120100`).
- **Status:** Approved by User, Ready for Implementation Planning

---

## 1. Overview & Objective

Provide a server-wide GearScore leaderboard and peer-to-peer sync engine inside `TacoTip_Extras`, inspired by the classic `HonorSpy` addon architecture.

The system will:
1. Automatically record players' GearScore, average item level, class, spec, and faction when they are inspected or targeted.
2. Silently sync records across players via a dedicated background communication channel (`ttgssync`), as well as through group (`PARTY`, `RAID`) and `GUILD` addon messaging.
3. Offer an interactive, Blizzard-styled **Rank Browser** window (`/tt ranks`) with search, class filtering, and tabbed leaderboards (`[My Faction]`, `[Opposite Faction]`, `[All Realm]`).
4. Display a player's server and class ranking directly on their tooltip (e.g. `Rank: #14 (#2 Warrior)`), fully configurable.

---

## 2. Architecture & Components

```
┌────────────────────────────────────────────────────────┐
│                   TacoTip_Extras                       │
├──────────────────────────┬─────────────────────────────┤
│   RankSync.lua           │   RankDB.lua                │
│   • Channel: ttgssync    │   • Storage: SavedVariables │
│   • Prefix: TACO_GS_SYNC │   • Dirty-flag re-indexing  │
│   • Token-bucket throttle│   • 60-day prune lifecycle  │
│   • Delta digest sync    │   • O(1) rank lookups       │
├──────────────────────────┼─────────────────────────────┤
│   RankBrowser.lua        │   Tooltips.lua Hook         │
│   • UI Frame (/tt ranks) │   • Optional rank line:     │
│   • Faction tabs & search│     "Rank: #14 (#2 Warrior)"│
│   • FauxScrollFrame grid │   • Options toggle          │
└──────────────────────────┴─────────────────────────────┘
```

---

## 3. Data Model & Storage (`RankDB.lua`)

Stored under `TacoTipExtrasDB.ranks`:
```lua
TacoTipExtrasDB.ranks = {
    [realmName] = {
        [playerGUID] = {
            name = "PlayerName",
            faction = "Alliance",     -- "Alliance" or "Horde"
            class = "WARRIOR",        -- Uppercase class file token
            classID = 1,              -- Numeric class ID (1-13)
            specName = "Protection",  -- Spec name
            specIcon = 132341,        -- Spec fileID or texture path
            gs = 4120,                -- GearScore
            ilvl = 226.4,             -- Average equipped item level
            timestamp = 1760295300,   -- Unix epoch time of last inspect/update
            source = "inspect",       -- "self", "inspect", or "sync"
        }
    }
}
```

### Data Hygiene & Pruning
- **Active Threshold:** 60 days. Entries older than 60 days without an update are excluded from rank calculation.
- **Maximum Cap:** 5,000 players per realm. If capacity is exceeded, oldest inactive records are evicted.
- **Sanitization:** Non-numeric scores, impossible GearScore values (> 12,000), or future timestamps (> `time() + 300`) are immediately rejected.

---

## 4. Gossip & Synchronization Protocol (`RankSync.lua`)

### Protocol Details
- **Addon Message Prefix:** `TACO_GS_SYNC` (registered via `C_ChatInfo.RegisterAddonMessagePrefix`).
- **Transport Channels:**
  1. `CHANNEL`: Joins custom channel `ttgssync` automatically. Hidden from chat windows (`ChatFrame_RemoveChannelGroup`).
  2. `GUILD`: Broadcasts to guild members running TacoTip Extras.
  3. `PARTY` / `RAID`: Broadcasts to group members during instances and raids.

### Wire Payload Formats
1. **Single Record Broadcast (`R`)**:
   ```text
   R;<GUID>;<Name>;<Faction>;<ClassID>;<SpecID>;<GS>;<iLvl>;<Timestamp>
   ```
   Example:
   ```text
   R;Player-4372-01A2;Pilsung;Alliance;1;73;4210;226.5;1760295300
   ```
2. **Delta Digest Handshake (`D`)**:
   Sent on joining a group or guild:
   ```text
   D;<Count>;<MaxTimestamp>
   ```
   Peers only respond with entries newer than `MaxTimestamp`.

### Rate Limiting & Safety
- **Token Bucket Throttle:** Outgoing transmission is limited to 1 message every 1.5 seconds with a maximum burst of 3 packets, preventing chat throttling or client disconnects.
- **Conflict Resolution:** Last-Write-Wins based on strictly greater `timestamp`.

---

## 5. Leaderboard Calculation & Sorting

- **Dirty-Flag Sorting:** Sorting is only triggered on-demand (when opening the UI or when new batches arrive while the UI is open).
- **Sort Priority:**
  1. `GearScore` (Descending)
  2. `Average Item Level` (Descending)
  3. `Timestamp` (Descending)
- **Lookup Map:**
  Generates `rankLookup[guid] = { overallRank, factionRank, classRank }` for constant-time $O(1)$ queries by tooltip rendering routines.

---

## 6. User Interface (`RankBrowser.lua`)

### Frame Details
- **Title:** `TacoTip GearScore Leaderboard`
- **Slash Commands:** `/tt ranks`, `/ttrank`, `/tt leaderboard`
- **Header Elements:**
  - Realm Name & Total Players Count
  - Sync Status Indicator (Green/Yellow pulse)
- **Top Faction Tabs:**
  - `[My Faction]` (Default)
  - `[Opposite Faction]`
  - `[All Realm]`
- **Filter Bar:**
  - Class filter dropdown (`All Classes` + 13 classes)
  - Search box (live substring matching against player name or guild)
  - "Force Sync" button
- **Leaderboard Table (FauxScrollFrame):**
  - Columns:
    - `#` (Rank position with top 3 medal highlights)
    - `Name` (Character name)
    - `Class & Spec` (Class colored name + Spec icon)
    - `GearScore` (Quality tier colored)
    - `iLvl` (Average item level)
    - `Last Seen` (Relative time e.g. "Today", "3d ago")
- **Footer:**
  - Your Standing: `Your Rank: #14 Alliance (#2 Warrior)`

---

## 7. Tooltip Integration (`Tooltips.lua`)

- When hovering any cached player, adds an optional rank line directly below GearScore & iLvl:
  ```text
  Rank: #14 (#2 Warrior)
  ```
- **Styling:** Clean white prefix `|cFFFFFFFFRank: |r` with highlight gold or tier colored numbers.
- **Config Option:** `TacoTipExtrasConfig.show_server_rank` (Default: `true`).

---

## 8. Verification & Test Plan

1. **Unit Tests (`load_test.lua` in `TacoTip_Extras`):**
   - Assert `RankDB` record storage, sanitization, and sorting order.
   - Assert packet serialization and deserialization across all fields.
   - Assert rank lookup math ($O(1)$ resolution).
   - Assert 60-day prune logic and maximum capacity capping.
2. **Static Analysis:**
   - 0 `luacheck` warnings across all new and updated files.
3. **Execution Harness:**
   - Run across `lua5.1`, `lua5.4`, and `luajit`.
