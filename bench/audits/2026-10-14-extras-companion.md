# TacoTip_Extras (companion add-on) — architecture audit

- **subject:** how `TacoTip_Extras` ships as a *separate* add-on that people
  install alongside TacoTip, what it reads across the boundary, and how it behaves
  when the other half is absent, old, or incapable
- **date:** 2026-10-14
- **author:** `extras` desk
- **anchored to:** `5bc83b7` with a dirty working tree (Extras `1.2.2` is
  uncommitted; line numbers are accurate for that tree)
- **status:** VERIFIED unless a line says otherwise
- **supersedes:** nothing

## why this exists

Users install one of these add-ons and not the other, upgrade them at different
times, and play on five different clients. Three things must therefore be true at
all times: the companion must load cleanly when TacoTip is missing or old, it must
never corrupt TacoTip's state, and it must not be able to spam the network.

## scope

**In:** `TacoTip_Extras.toc` and the 13 runtime files, the adapter boundary, the
rank database and sync protocol, and the harness that covers them.

**Out:** the core add-on (own audit), packaging/versioning (`release` desk), and
in-game behaviour (operator-run checklists).

## the system

### It is a separate add-on, by construction (VERIFIED)

| fact | evidence |
|---|---|
| its own folder, its own `.toc` | `TacoTip_Extras/` |
| its own CurseForge project | `## X-Curse-Project-ID: 1741092` |
| its own SavedVariables | `## SavedVariables: TacoTipExtrasDB` |
| **hard** dependency on TacoTip | `## Dependencies: TacoTip` — the client will not load Extras without TacoTip |
| same five clients | `## Interface: 11509, 20506, 38002, 16001, 120100` |
| its own 11 locales | `Locale/` in the add-on, following TacoTip's language setting |

So "install Extras to get the extra things" means: both add-ons installed, and the
extra surfaces are the server leaderboard, the peer-to-peer rank database, the
click-through gear panel, and the rank line on player tooltips.

### Load order (`TacoTip_Extras.toc`, VERIFIED)

    11 locales (deDE … zhTW, then enUS) → Core → Scoring → Cache → RankDB →
    RankSync → Scanner → TacoTipAdapter → Tooltips → Frames → RankBrowser →
    Minimap → Options

Every file starts with `local _, namespace = ...` and **returns early** when a
module it needs is not yet in `namespace`. The comment at the top of each file
names what it needs; the guard makes the `.toc` order enforceable rather than
hopeful.

### Module responsibilities (VERIFIED, surfaces)

- **`Core`** — add-on identity/version (`Core.GetVersion`), settings read/apply,
  reset, and "restore TacoTip settings" passthroughs. Fans `ApplySettings` out to
  Tooltips / Minimap / Frames / Options.
- **`Scoring`** — scoring and colour maths: `QualityColor(fraction)`,
  `RankFraction(rank, total)`, `ScoreFraction`, `RankColor(rank, total)` (the
  shared ranking scale added in 1.2.2), plus item-link parsing for the gear panel.
- **`Cache`** — bounded item cache (`MAX_ENTRIES = 32`).
- **`RankDB`** — the rank database: validation, last-write-wins storage, per-realm
  capacity (`MAX_CAPACITY = 20000`, measured at ~5.3 MB of SavedVariables), prune
  cycle, and `GetPlayerRank(guid)` → overall/faction/class/total.
- **`RankSync`** — the wire: channel `ttgssync` (joined silently), add-on-message
  prefix `TACO_GS_SYNC`, a compact delimited protocol, a 20 s per-client respond
  interval with 1–4 s jitter, and a hard refusal to send anything that would break
  the 255-byte add-on-message cap.
- **`Scanner`** — remote gear inspection sweep with progress reporting.
- **`TacoTipAdapter`** — the boundary (below).
- **`Tooltips`** — the rank line, drawn through the leased tooltip surface.
- **`Frames`** — the gear panel opened from a leaderboard row.
- **`RankBrowser`** — the leaderboard UI (`/tt ranks`, `/tt rank`, `/ttranks`, …),
  with the `#` column, filters, search and its own focused harness.
- **`Minimap`** — the button (left-click leaderboard, right-click settings).
- **`Options`** — its own settings page, registered through the same dual path as
  TacoTip's (modern `Settings.*` when present, else `InterfaceOptions_AddCategory`).

### The adapter boundary (VERIFIED — this is the heart of the audit)

`TacoTipAdapter` must work against TacoTip versions it was not built with, so it
refuses a TacoTip that cannot do the work rather than trusting a version string:

- **Minimum version** `{ 0, 8, 0 }`, *and* a **capability probe** of the exact
  functions this add-on (and `TT_GS:GetScore` on its behalf) calls:
  `RegisterCallback`, `UnregisterCallback`, `PlayerGUIDToUnitToken`,
  `GetInventoryItemMixin`, `GetLastCacheTime`. A version string cannot distinguish
  "the API I need is gone" from "the counter moved".
- **The private TacoTip table is resolved, never assumed**: pass 1
  `_G["TacoTip_Forever"]`, pass 2 `_G["TacoTip"]` (skipped when it is our own
  name), pass 3 a scan of every loaded add-on's private table. More than one match
  is *reported*, never guessed at. It also carries duck-type markers used only to
  *find* the table (`GetDefaults` plus `ApplyTooltipAppearance`,
  `RefreshOptionsUI`, `RefreshCharacterFrame`, `RefreshInspectFrame`) — never to
  gate on, so TacoTip may rename them freely.
- **Global reads are explicit**: `TT_GS`, `TT_PAWN`, `TacoTipConfig`,
  `TACOTIP_LOCALE`, `TacoTip_GSCallback`. Anything not in that list crosses
  through the adapter.
- **The tooltip surface is leased, not owned**: a managed key `show_gs_player` and
  a surface name `tooltip`, with `SetTooltipSurfaceEnabled` and a stored lease
  (config-table identity is re-checked before writing) so Extras can never leave
  TacoTip's config in a state it did not choose.

### Degradation ladder (VERIFIED against the `.toc` and the adapter)

| state of TacoTip | what happens |
|---|---|
| not installed / disabled | **Extras does not load at all** — hard `## Dependencies:` |
| loaded, older than `0.8.0` or missing a probed function | Extras loads; the adapter reports unsupported with a reason string; surfaces stay off; nothing raises |
| loaded and capable | surfaces enabled; the rank line, gear panel and leaderboard work |

## gates & invariants

1. **Never assume TacoTip's table name.** The packaged name is `TacoTip`; the
   development tree used `TacoTip_Forever`. Resolution is a scan, not a constant.
2. **Never gate on a marker method** you do not call. Markers find the table;
   probes gate the work.
3. **Load order is enforced at load time** by the per-file `namespace` guards.
4. **Nothing goes on the wire above 255 bytes** — the sync layer refuses rather
   than truncating.
5. **One response per 20 s per client, plus jitter** — the flood control that
   keeps a capital city from turning into a broadcast storm.
6. **Bounded storage**: 20000 records per realm, with eviction; the cap is
   measured, not guessed.

## verification map

| area | covered by |
|---|---|
| loads on all five clients, and under six variants (dev name, old TacoTip, missing capabilities, no stats, no settings) | `TacoTip_Extras/Tests/harness/load_test.lua` |
| leaderboard behaviour (scroll, filters, sorting, colours, own row) | `TacoTip_Extras/Tests/harness/rankbrowser_test.lua` (classic + retail) |
| TOC pins (name = folder, version, dependencies, SavedVariables) | `load_test.lua` |
| rank colour scale values | `load_test.lua` (`Scoring.RankColor` assertions) |
| in-game: rank line, leaderboard colours, old-TacoTip behaviour | the desk checklist (operator) |

Total: 42 invocations across `lua5.1`, `lua5.4` and `luajit`.
`bash TacoTip_Extras/Tests/harness/run_all.sh`.

## unknowns

- **Sync behaviour between real clients** is not covered offline: the harness
  proves single-client protocol handling, not two clients discovering each other.
- **The gear panel's layout** and the **minimap button** interactions were not
  audited here.
- **`classic_titan` / Wrath differences** in the add-on-message and settings APIs
  Extras uses were not verified in this audit (see the api-verification playbook).
- The dev-tree name path (`TacoTip_Forever`) cannot resolve in this repo, since no
  such add-on is installed here — see `bench/OPEN-ITEMS.md` item 5.

## how to keep this honest

    cd /home/sam/TacoTip-Gearscore-TBC
    bash TacoTip_Extras/Tests/harness/run_all.sh
    luacheck TacoTip_Extras/*.lua TacoTip_Extras/Tests/harness/load_test.lua
    grep -n "MINIMUM_TACOTIP_VERSION\|INSPECTOR_CAPABILITIES" TacoTip_Extras/TacoTipAdapter.lua
    grep -n "MAX_CAPACITY\|RESPOND_INTERVAL" TacoTip_Extras/RankDB.lua TacoTip_Extras/RankSync.lua
