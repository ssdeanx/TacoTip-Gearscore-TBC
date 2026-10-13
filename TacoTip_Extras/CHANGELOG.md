# Changelog — TacoTip Extras

All notable changes to TacoTip Extras are documented in this file.

| Version | Date | Summary |
| :--- | :--- | :--- |
| `1.2.0` | `2026-10-13` | Authorship unified on AcidBomb across LICENSE, TOC metadata, and both in-game credit strings. The login banner now prints "TacoTip Extras" rather than the retired "TacoTip GS Enhancer". | Leaderboard browser upgraded: click-to-sort columns, per-row hover tooltips, specialization icons, Escape-to-close fixed for the Classic family, `/tt lb`, and a labelling pass. |
| `1.1.0` | `2026-10-13` | Leaderboard browser rebuilt: whole-realm ranking with no faction split, opens centred on your own rank, `▲ Top` / `▼ My Rank` navigation, class filter and live search, and a modernized row treatment (class colour bar, podium rank badges, hover highlight, `YOU` marker). Adds a focused offline harness that drives the browser and asserts what it rendered. |
| `1.0.2` | `2026-10-13` | Polish release: renamed the player-tooltip rank label to `Gearscore Rank:`, restyled it to match the add-on's brand palette, recolored Average iLvl values from class colors to GearScore quality colors across tooltips, equipment windows and the server browser, and fixed the leaderboard window not opening from the Options button / slash commands on all clients. |
| `1.0.1` | `2026-10-12` | Server-wide GearScore Rank Browser & P2P Sync Engine (HonorSpy style) in background channel `ttgssync` + GUILD/PARTY/RAID fallbacks, interactive Leaderboard UI (`/tt ranks`, `/ttrank`, `/ttleaderboard`), player tooltip rank line (`Rank: #X (#Y Class)`), and remote inspect equipment scanning deadlock fix across Retail and WoW Forever. |
| `1.0.0` | `2026-10-11` | Initial release of TacoTip Extras companion addon. Full equipment and enhancement auditing, modern retail engine compatibility (variable-length bonus ID item links, 16-slot average item level, CharacterModelScene support), Detailed display mode default, and 100% zero-warning static analysis. |

---

## [Unreleased]

### Fixed

- Escape-close of the GearScore browser no longer raises
  `Cannot assign script handler for 'OnEscapePressed'` on Retail: a bare Frame has
  no `OnEscapePressed` script type, so the assignment is now pcall-guarded while
  the `UISpecialFrames` route keeps the key working.
- Retail no longer reports "Equipment data unavailable": equipped links on Retail are
  coloured with the named escape `|cnIQx` instead of the legacy `|cAARRGGBB` color code,
  so `Scoring.extractPayload` now extracts the payload by its `item:[^|]+` signature
  rather than anchoring on the legacy color code. Classic links are unaffected.

### Changed

- The "Open Server Leaderboard" button in the Options panel moved to the top-right of
  the panel so it is easier to reach.

## [1.2.0] — 2026-10-13

> Column sorting, hover detail, and a genuine Classic-family Escape key.

### Changed

- **Authorship made consistent.** `LICENSE`, the credits section, the TOC
  metadata and both in-game credit strings now name **AcidBomb (Pilsung)**.
  There were two independent credit sites -- the login banner in `Core.lua` and
  the Options panel footer in `Options.lua` -- and correcting only the first
  left the two disagreeing on screen.
- The login banner prints **TacoTip Extras**. It previously printed the retired
  name "TacoTip GS Enhancer", which disagreed with the TOC title, the saved
  variables and this documentation.

### Added

- **Click-to-sort.** `GEARSCORE`, `iLVL` and `LAST SEEN` headers are buttons. The
  active column carries a brand underline, and a readout line states the current
  order so it is never guesswork.
- **Per-row hover tooltips.** Name, spec, GearScore, Average iLvl, realm rank and
  last-seen, with the score values in their quality colours. Rows stay terse
  because the detail lives on hover instead of crowding six columns.
- **Specialization icons** beside the spec text, from the record the sync engine
  already carries. Rendered defensively — a client that cannot resolve the icon
  loses a 14px gap and nothing else.
- **`/tt lb`** added to the slash aliases.

### Changed

- The `SEEN` column is now `LAST SEEN`, widened to fit.

### Fixed

- **Escape now closes the browser on Classic Era, TBC Anniversary and Titanforge.**
  It previously registered `KEY_ESCAPE`, which appears **zero times** in Classic
  Era's FrameXML: the call compiles, does not raise, and never fires. Classic
  dispatches Escape through the `OnEscapePressed` frame script and the
  engine-recognised `UISpecialFrames` list, and both are now the primary route.
  `KEY_ESCAPE` is kept only as an extra for Retail and WoW Forever.

---

## [1.1.0] — 2026-10-13

> Leaderboard browser rebuilt around one idea: you open it to see **where you
> are**, so it should put you there, and give you a way to find anyone else.

### Added

- **Opens on your own rank.** The window scrolls to your position and centres
  you on the middle visible row, on every open — from the Options button, any
  slash command, or a reopen after closing. It honours the active class filter
  and search, so the jump targets your row *within the current view*.
- **`▼ My Rank`** button re-centres you at any time, and **`▲ Top`** jumps back
  to `#1`.
- **Class filter** dropdown (`All Classes` plus all thirteen classes), sitting
  beside the search box. Selection is reflected in the dropdown label.
- **`YOU` marker** and a brand-purple highlight on your own row, so you can see
  at a glance which row is you.
- **Modernized row treatment:** a thin class-colour bar down the left edge,
  gold/silver/bronze podium badges for `#1`–`#3`, zebra striping, hover
  highlight, muted spec and last-seen columns, and right-aligned numerics.
- **Empty state** message when the current filters match nobody.
- **`Tests/harness/rankbrowser_test.lua`**, a focused offline suite that drives
  the browser and asserts the rendered result — which ranks, which names, which
  colours, and which scroll offset. Wired into `run_all.sh` on all three
  interpreters.

### Changed

- **Ranking is whole-server.** The Alliance / Horde / All Realm tabs are gone;
  the leaderboard always ranks the entire realm. A faction filter only ever hid
  the players you wanted to compare yourself against.
- The browser window is larger (720x520) and shows 12 rows instead of 10.

### Fixed

- The scrollbar thumb and the row offset are now moved together. Previously the
  rows jumped while the scrollbar stayed at the top, because
  `FauxScrollFrame_SetOffset` only assigns `frame.offset` while
  `FauxScrollFrame_Update` reads the *thumb*. Both are now driven through
  `FauxScrollFrame_OnVerticalScroll`, the only documented path that writes both.

### Verified

Classic Era, TBC Anniversary, Titanforge, Retail and WoW Forever. Every template
and API used by the browser (`BackdropTemplate`, `UIPanelButtonTemplate`,
`UIPanelCloseButton`, `InputBoxTemplate`, `FauxScrollFrameTemplate`,
`UIDropDownMenuTemplate`) was confirmed present on each branch, and the
Classic and Mainline `UIDropDownMenu_Initialize` / `UIDropDownMenu_AddButton`
signatures were compared directly.

---

## [1.0.2] — 2026-10-13

> Polish and publication-readiness release focused on tooltip readability, consistent
> GearScore coloring, and a reliable leaderboard window.

### Changed

- The player-tooltip server-rank label is now `Gearscore Rank:` (was `Rank:`) and
  is drawn in the add-on's brand purple instead of plain white, so it matches the
  other labeled rows.
- Average iLvl values no longer inherit the hovered player's class color; they
  now use the same GearScore quality color as the Current GS value. Applies to
  the Minimal, Compact and Detailed tooltip modes, both Character and Inspect
  equipment windows, and the server leaderboard's iLvl column.
- The server leaderboard window is raised to the `DIALOG` strata and re-anchored
  on show so it reliably appears above the Options panel when opened from either
  the Options button or a slash command.

### Fixed

- The Options `Open Server Leaderboard` button and the `/tt ranks`, `/ttrank`,
  `/ttleaderboard`, `/tt rank` and `/tt leaderboard` slash commands now open the
  window on every supported client.

---

## [1.0.1] — 2026-10-12

> Major feature and maintenance release introducing the Server-Wide GearScore Rank Browser & P2P Sync Engine
> alongside remote inspection deadlock fixes across Retail and WoW Forever.

### Added

- **Server-Wide GearScore Rank Browser & P2P Sync Engine (HonorSpy Style):**
  - **`RankDB.lua` Database & Indexing Subsystem:**
    - High-performance, dirty-flag-cached ranking engine for player GearScores.
    - Caches separate sorted lists for `all`, `alliance`, `horde`, and per-class tables (`byClass`).
    - $O(1)$ player lookup table (`rankIndexByGUID`) providing instantaneous overall rank, faction rank, class rank, and total tracked count.
    - Automatic 60-day stale record pruning (`PruneStaleRecords`) and strict 5,000 player capacity cap with lowest-GS eviction.
    - Strict validation rejecting empty GUIDs, invalid names, negative or out-of-bounds GearScores (> 15,000), with last-write-wins timestamp arbitration.
  - **`RankSync.lua` Peer-to-Peer Synchronization Engine:**
    - Dedicated hidden background chat channel `ttgssync` with automatic `ChatFrame_RemoveChannelGroup` silencing to ensure zero chat frame clutter.
    - Fallback broadcasts over `GUILD`, `PARTY`, and `RAID` addon channels (`TTGS_SYNC` prefix).
    - Compact semicolon-delimited wire protocol: `R;<guid>;<name>;<faction>;<classID>;<specName>;<gs>;<ilvl>;<timestamp>`.
    - Token-bucket rate limiter (1 packet per 1.5s, burst capacity of 3) to prevent chat disconnects and combat frame drops.
  - **`RankBrowser.lua` Interactive Leaderboard Window:**
    - 580×440 standalone UI frame (`TacoTipRankFrame`) accessible via `/tt ranks`, `/ttrank`, `/ttleaderboard`, or the Options panel button.
    - 3 faction tabs: `[All Realm]`, `[Alliance]`, `[Horde]`.
    - Live substring search editbox for instant player filtering.
    - Smooth scrolling with Blizzard `FauxScrollFrame` and 10 reusable row frames.
    - Visual polish: Gold (#1), Silver (#2), and Bronze (#3) medal coloring, class-colored player names, formatted GearScore quality colors, and relative timestamps ("2h ago", "3d ago").
    - Personal standing footer banner summarizing player's own Overall, Faction, and Class ranks.
  - **Tooltip Rank Display & Toggle:**
    - Appends clean rank standing line `|cFFFFFFFFRank: |r#X (#Y Class)` (e.g. `Rank: #14 (#2 Warrior)`) to player tooltips across Minimal, Compact, and Detailed modes.
    - Fully configurable via Options checkbox `Show server leaderboard rank` (`tooltip.show_server_rank`).

### Fixed

- **Remote Inspection "Scanning Equipment..." Deadlock:**
  - Resolved issue where right-clicking and inspecting another player left the inspect frame permanently showing `"Scanning equipment..."`.
  - Relaxed the guard in `Scanner.HandleInventoryReady` to `(isInspect ~= nil and isInspect ~= true)` so callbacks with omitted `isInspect` parameters (e.g. from `LibForeverInspector`) are processed instead of dropped.
  - Added `_G.InspectFrame.unit` resolution in `resolveRemoteUnit` so players inspected from chat, guild roster, or friends list (who are not currently targeted or under mouseover) cleanly resolve their unit token.
  - In `Scanner.captureSlot`, added fallback item ID extraction from the native item link (`"item:(%d+)"`) when `GetInventoryItemID` returns `nil` on remote units, preventing false contradiction errors during remote scans.
- **Offline Test Matrix:**
  - Added comprehensive test suites in `Tests/harness/load_test.lua` asserting RankDB validation, storage, sorting, class filtering, pruning, RankSync wire serialization/deserialization, tooltip rank rendering/toggling, and UI creation across all 36 client matrix runs.

---

## [1.0.0] — 2026-10-11

> Initial standalone release of TacoTip Extras, providing non-invasive equipment audit and enhancement
> display directly integrated with TacoTip and LibForeverInspector.

### Added

- **Detailed Equipment Summaries:**
  Inspect and Character frame displays showing per-slot item level, gem sockets, enchantments, and missing enhancement alerts.
- **Universal Multi-Client Architecture:**
  Full support for Classic Era / SoD (`11509`), TBC Anniversary (`20506`), WotLK Titanforge (`38002`), WoW Forever (`16001`), and Retail (`120100`).
- **Retail & Forever Modern Hardening:**
  Modern unit resolution with `TooltipUtil.GetDisplayedUnit` and `TooltipDataProcessor.AddTooltipPostCall`, modern paperdoll layout support (`CharacterModelScene`), variable-length bonus ID item link parsing, and retail 16-slot average item level divisor.
- **Detailed Mode Default:**
  Fresh installations and unconfigured profiles default to **Detailed** mode for both player tooltips and equipment displays.
- **Quality Gates:**
  100% zero-warning compliance across all 11 files under `luacheck`.
