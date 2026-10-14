# extras — Journal

## 2026-10-14 — Desk opened

- **Purpose:** own `TacoTip_Extras` — the companion add-on people install *beside*
  TacoTip to get the server leaderboard, P2P sync, the gear panel and the rank
  line. This desk owns everything under `TacoTip_Extras/`, plus the questions that
  only exist because it ships separately: what it may assume about TacoTip, what it
  does when TacoTip is absent or too old, and what its own release contract is.
- **Scope:** `TacoTip_Extras/` in full (13 runtime files, 11 locales, its own
  harness), the boundary in `TacoTip_Extras/TacoTipAdapter.lua`, and the
  `## Dependencies:` / SavedVariables contract in `TacoTip_Extras.toc`.
- **Sibling desks:** `tacotip` owns the core add-on; `release` owns packaging and
  versioning for both; `api-verification` settles Blizzard behaviour.

### What this add-on is (VERIFIED against this tree)

- A **separate install**: its own folder, its own `.toc`, its own CurseForge
  project (`X-Curse-Project-ID: 1741092`), its own SavedVariables
  (`TacoTipExtrasDB`), and `## Dependencies: TacoTip` — a *hard* dependency, so
  Blizzard will not load it at all unless TacoTip is present.
- It does not fork TacoTip and shares no tables with it. It reads TacoTip through
  a capability-checked adapter and **leases** the tooltip surface (managed key
  `show_gs_player`, surface name `tooltip`) instead of owning it.
- Five clients are claimed in the `.toc`: `11509`, `20506`, `38002`, `16001`,
  `120100` — the same five as TacoTip.

### The boundary, as it actually works (VERIFIED)

- `TacoTipAdapter` refuses a TacoTip that cannot do the work: minimum version
  `{ 0, 8, 0 }` **plus** a probe of the exact functions this add-on and
  `TT_GS:GetScore` call — `RegisterCallback`, `UnregisterCallback`,
  `PlayerGUIDToUnitToken`, `GetInventoryItemMixin`, `GetLastCacheTime`. A version
  string cannot tell "the API I need is gone" from "the counter moved"; a missing
  function can.
- The private TacoTip table is **resolved, not assumed**: `_G["TacoTip_Forever"]`,
  then `_G["TacoTip"]`, then a scan of loaded add-ons — and more than one match is
  *reported*, never guessed at. `TT_GS`, `TT_PAWN`, `TacoTipConfig`,
  `TACOTIP_LOCALE` and `TacoTip_GSCallback` are true globals and are read
  directly.
- Every module loads as `local _, namespace = ...` and **returns early** when the
  module it depends on is not already in the namespace — the `.toc` load order is
  enforced at load time, not documented and hoped for.

### State at desk opening

- Version `1.2.2` in the `.toc`, `README.md`, `CHANGELOG.md` and the harness pin.
- Rank colours resolve through one `Scoring.RankColor(rank, total)`, shared by the
  leaderboard's `#` column and the tooltip rank line; the tooltip brackets are
  white; the inverted top-5% test inherited from `RankBrowser.getRankColor` is
  corrected (it painted the *bottom* 5% gold). All harness-verified — the in-game
  check is item 8 in `bench/OPEN-ITEMS.md`.
- Limits worth knowing before touching the DB: `RankDB.MAX_CAPACITY = 20000`
  records per realm (~5.3 MB of SavedVariables, measured), plus a prune cycle.
  `RankSync` uses channel `ttgssync`, prefix `TACO_GS_SYNC`, a 20 s per-client
  respond interval with 1–4 s jitter, and refuses payloads that would exceed the
  255-byte addon-message cap.

### The in-game pass this desk is waiting on (Classic Era first)

1. Hover a ranked player: `Rank: #N [#M Class]` — **white** brackets, `#1`
   **gold**, class name in its class colour.
2. Hover an unranked player: no rank line at all, not an empty one.
3. Open the leaderboard (`/tt ranks`): `#1` reads gold and the *bottom* of the
   list reads muted, not gold.
4. With TacoTip **disabled**, the client must refuse to load Extras at all — the
   `.toc` declares a hard `## Dependencies: TacoTip`, so that is the correct
   behaviour and *not* a Lua error. The interesting case is the other one: an
   **old but present** TacoTip must leave Extras loaded, silent, and reporting
   "unsupported" rather than raising.

### Open / next

- Close `bench/OPEN-ITEMS.md` items 5 (dev-tree name resolution evidence), 7 (the
  minimum-version decision) and 8 (the in-game pass above).
- The bracket-colour assertions already run under all three interpreters; the
  colour *values* are pinned with `("%.2f"):format(...)`, never `tostring(...)`,
  because Lua 5.3+ stringifies integral floats as `1.0`.

### Evidence

    bash TacoTip_Extras/Tests/harness/run_all.sh      # 42 invocations, 3 interpreters
    luacheck TacoTip_Extras/*.lua TacoTip_Extras/Tests/harness/load_test.lua

Last run: 42/42 green, `luacheck` clean (one pre-existing `table.unpack` warning
in the harness, kept deliberately for Lua 5.4).
