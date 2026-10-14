```
   _____               ______                  _
  |_   _|             |  ____|                | |
    | | |__   __ _  __| |__ ___  __ _ _ __ ___| | _____ _   _
    | | '_ \ / _` |/ _`\___ \ \/ _` | '_ ` _ \| |/ / _ \ | | |
    | | | | | (_| | (_|____) |> (_| | | | | | |   <|  __/ |_| |
    |_|_| |_|\__, |\__,_|_____/ \__,_|_| |_| |_|_|\_\___|\__,_|
             __/ |
            |___/          companion add-on for TacoTip
```

```yaml
name: TacoTip Extras
version: 1.2.2
author: AcidBomb
maintainer: AcidBomb (Pilsung)
license: MIT  # see LICENSE
curseforge_id: 1741092
project_url: https://www.curseforge.com/wow/addons/tacotip-extras/preview
tacotip_url: https://www.curseforge.com/wow/addons/tacotip-gearscore
requires: [TacoTip]
clients: [Classic Era / SoD, TBC Anniversary, WotLK Titanforge, WoW Forever, Retail]
interfaces: ["11509", "20506", "38002", "16001", "120100"]
tags: [tacotip, gearscore, leaderboard, ranking, p2p, audit, inspect, enhancements, companion]
status: unreleased
updated: 2026-10-13
```


**TacoTip Extras** is an optional companion add-on for [TacoTip](https://www.curseforge.com/wow/addons/tacotip-gearscore). It adds enhancement-aware GearScore information to genuine player tooltips and to summaries in the Character and Inspect equipment windows. TacoTip stays separately installed and keeps providing everything else it does.

- **TacoTip** — <https://www.curseforge.com/wow/addons/tacotip-gearscore> (required dependency)
- **TacoTip Extras** — <https://www.curseforge.com/wow/addons/tacotip-extras/preview> (this add-on)

TacoTip Extras is a **separate project from TacoTip**. It has its own repository and its own CurseForge listing, to follow. It is not a fork of TacoTip, not maintained by the TacoTip author, and it implies no endorsement by either.

**Version:** 1.2.2
**Author:** AcidBomb (Pilsung)

## Requirements

TacoTip Extras **requires TacoTip**. It declares `## Dependencies: TacoTip`, so TacoTip loads first and nothing here works without it. It resolves inspection data via `LibForeverInspector`. TacoTip is not bundled, modified, redistributed or forked.

Supported clients — the same set TacoTip supports, declared identically in the TOC:

| Client | Interface |
| :--- | :--- |
| Classic Era | 11509 |
| TBC Anniversary | 20506 |
| WotLK Titanforge | 38002 |
| WoW Forever | 16001 |
| Retail | 120100 |

## Installation

Drop the `TacoTip_Extras` folder into `Interface/AddOns/`. The TOC filename must match the folder name (`TacoTip_Extras.toc`) or the client will not load the add-on at all.

## Features

- Server-wide GearScore Leaderboard & P2P Sync Engine (HonorSpy style) with dedicated background channel `ttgssync` and GUILD/PARTY/RAID broadcast fallbacks.
- Interactive Leaderboard window (`/tt lb`, `/ttrank`, `/ttranks`, `/ttleaderboard`, `/tt rank`, `/tt ranks`, `/tt leaderboard`) covering the **whole realm**, opening centred on your own rank, with class filtering, live search, `▲ Top` / `▼ My Rank` navigation, and personal rank standing.
- Automatic tooltip rank display (`Gearscore Rank: #14 [#2 Warrior]`) on player hover.
- Current GS, Potential GS, Delta, Completion, Average iLvl, and optional Unenhanced GS for player tooltips.
- Extras-owned Basic and Detailed summaries for the local Character window and remote player Inspect windows.
- One shared equipment-summary mode with separately saved Character and Inspect positions.
- Locked-by-default movement using a small handle that appears only while positions are unlocked.
- Local, friendly remote, and permitted enemy remote player support with fail-closed non-player rejection.
- Native Options integration, `/ttgs`, a movable minimap shortcut, and reversible TacoTip coexistence.

## Metrics

- **Current GS** is the player's present and primary GearScore in this add-on. It combines equipped-item GearScore with supported bonuses from installed permanent enchants and gems. Temporary weapon effects do not count.
- **Potential GS** adds only confirmed missing eligible permanent enchants and confirmed empty sockets to Current GS. It is not a best-in-slot estimate and does not select or recommend optimal enchants or gems.
- **Delta** is Potential GS minus Current GS. It represents only the confirmed missing enhancement potential included by this add-on.
- **Completion** is the share of confirmed eligible permanent-enchant and socket opportunities that are filled. It measures enhancement completion, not character, equipment, or raid readiness.
- **Average iLvl** is the average item level across the add-on's fixed TBC equipment-slot model. Enchants and gems do not affect it.
- **Unenhanced GS** is an optional comparison using the same equipped items with only the installed permanent-enchant and gem bonuses counted by this add-on removed. It is not the player's present GearScore.

Potential GS, Delta, and Completion appear only when their required item and socket evidence is conclusive. Unavailable or unknown information is never represented as zero.

## Player-tooltip modes

- **Disabled:** shows no add-on rows and safely releases the TacoTip player-GearScore takeover.
- **Minimal:** shows the shortest enabled summary, prioritizing Current GS and Average iLvl. It omits Unenhanced GS.
- **Compact:** shows up to two concise rows using `GS` for Current GS, optional Average iLvl, useful positive Delta, and Completion when available. It omits Potential GS, Unenhanced GS, and the completion fraction.
- **Detailed:** shows each enabled, available metric on a separately labelled row in this relative order: Current GS, Potential GS, Delta, Completion, Average iLvl, then Unenhanced GS when explicitly enabled.

## Server-Wide GearScore Leaderboard & P2P Sync

TacoTip Extras features a decentralized, HonorSpy-style peer-to-peer sync engine that continuously aggregates player GearScores across your realm:

- **Interactive Leaderboard Window:** Access via `/tt lb`, `/ttrank`, `/ttranks`, `/ttleaderboard`, `/tt rank`, `/tt ranks`, `/tt leaderboard`, or via the **Open Server Leaderboard** button in Options.
  - Ranks the **whole realm**. There is no Alliance/Horde split — a faction filter would only hide the players you want to compare yourself against.
  - **Opens on your own rank.** The window scrolls to your position and centres you on the middle visible row every time it opens, honouring the active class filter and search.
  - **`▼ My Rank`** re-centres you at any time; **`▲ Top`** jumps back to `#1`.
  - **Sort** by clicking the `GEARSCORE`, `iLVL` or `LAST SEEN` headers. The active column is underlined and the current order is stated on screen. The `#` column always stays the **GearScore rank**, whichever way the list is sorted, so sorting never makes standing look like it moved.
  - **Hover any row** for full detail: spec, GearScore, Average iLvl, realm rank and last-seen.
  - **Escape closes the browser**, on every supported client.
  - Filter by class from the **class dropdown**, or type a name fragment into the search box for live filtering.
  - Your own row carries a **highlight and a `YOU` marker**, so you can see at a glance which row is you.
  - **Click any row** to open a **gear panel** for that player: their 17 equipped slots, each rendered as a real item link so the game supplies quality colour and hover tooltips. Slot labels use Blizzard's own `INVTYPE_*` strings, so the panel is translated in every language the client ships. Players not scanned this session show a plain explanation rather than blank rows.
  - Top players get percentile-coloured rank numbers: `#1` is the top band because it *is* the highest GearScore. The class-rank number in the tooltip line uses the same scale against the class pool.
  - Every row has a thin class-colour bar, hover highlighting, and muted spec / last-seen columns.
  - Footer banner shows your character's personal Overall, Faction, and Class ranks.
- **Tooltip Rank Display:**
  - Renders a rank line on player tooltips: `Gearscore Rank: #14 [#2 Warrior]`, with the numbers coloured by percentile and the class name in its class colour.
  - Can be toggled on/off in the Options panel (`Show server leaderboard rank`).
- **Silent Background Sync:**
  - Automatically exchanges inspection records over the hidden chat channel `ttgssync` with fallback broadcasts to `GUILD`, `PARTY`, and `RAID`.
  - **Asks for data instead of only listening.** A client that has just logged in sends a `Q` query; peers answer with `S` (their own current record) and `T` (a short digest of the best records they hold). Without this a fresh install stayed empty until enough players happened to re-gear near it.
  - **Flood-controlled on both sides.** Each client answers at most one query per 20 seconds, and answers are jittered by a random 1–4 seconds so a group logging in together does not answer in the same instant. Responses are sized against the 255-byte addon-message limit.
  - Re-driven on login, `/reload`, instance transitions and open-world zone changes, throttled to one round per 30 seconds.
  - Channel output is silenced from chat windows with zero chat clutter.
  - Rate-limited with a token bucket (1 msg / 1.5s, burst max 3) to prevent disconnects.
  - Stale data is automatically pruned after 60 days, with a 20,000 player capacity cap (measured at ~5.3 MB of SavedVariables).

## Character and Inspect summaries

The Character and Inspect windows share one summary-mode setting:

- **Disabled:** shows no add-on equipment summary and leaves TacoTip's native Character/Inspect GearScore and iLvl presentation in control.
- **Basic:** shows exactly `Current GS` and `Average iLvl`, with no heading or additional metrics.
- **Detailed:** shows available rows in this relative order: Current GS, Potential GS, Delta, Completion, Average iLvl, and optional Unenhanced GS last.

When Potential GS, Delta, and Completion are blocked but independently complete metrics remain usable, Detailed consolidates those enhancement rows into `Enhancement analysis: Unavailable`. A coherent scan in progress shows `Scanning equipment...`; when no usable result is available, the summary shows `Equipment data unavailable`. A successfully rendered Inspect result remains visible while the same player's Inspect window stays open, but stale cached data is not reused after the Inspect context is closed or changes. Invalid and non-player contexts show no summary, and remote results are bound to the current inspected player so an earlier player's values are cleared immediately.

The equipment-window Unenhanced preference is separate from the tooltip's `baseGS` preference. It is off by default and affects Detailed equipment summaries only.

Summary positions are locked by default. **Unlock summary positions** reveals a small drag handle and subtle outline on each currently visible summary. Only the handle receives the mouse; summary text remains mouse-disabled. Character and Inspect positions move and persist independently, use parent-relative offsets, and are clamped inside their respective safe equipment-window areas.

While Basic or Detailed is active and the exact TacoTip object contract is valid, the add-on temporarily hides TacoTip's native Character/Inspect score FontStrings and mover buttons through an in-memory visibility lease. It does not change TacoTip anchors, offsets, mover preferences, `show_gs_character`, or `show_avg_ilvl`. On release, the re-hide guard is disabled first and TacoTip's own refresh path restores its current saved presentation. No equipment visibility state is written to the recovery journal.

## Usage and settings

Open the settings through any of these routes:

- `/ttgs`
- left-click the minimap button
- Esc → Options → Add-Ons → TacoTip Extras

The main category retains tooltip, scoring-policy, minimap, restore, and reset controls. Its **Equipment Windows** child category contains the shared summary mode, the optional Detailed Unenhanced comparison, the lock/unlock control, and **Reset summary positions**. `/ttgs` and the minimap shortcut open the main category.

The category is registered through `Settings.RegisterCanvasLayoutCategory` with
`Equipment Windows` as a `RegisterCanvasLayoutSubcategory` beneath it. When
`Settings` is absent the same panel is registered through the legacy
`InterfaceOptions_AddCategory`, with `childFrame.parent` set to TacoTip's own
category name for the main page and to this add-on's main page for the equipment
page, so the nesting is the same on both APIs. The main page is therefore a
child of TacoTip's category rather than a second top-level entry.

The minimap button can be dragged around the minimap. Left-click opens the add-on category, closes it when that exact category is active, or switches to it from another Settings category. `/ttgs` always opens or switches; it never closes Settings.

**Enable add-on** is the master output switch. Disabling it retains child preferences, hides add-on output, and releases every active TacoTip lease. **Restore TacoTip settings** remains a tooltip-only action: it disables and releases only the player-tooltip takeover and its `show_gs_player` recovery record. It does not change or suspend the equipment summary, its mode, or its positions.

A fresh profile starts with both player tooltips and equipment summaries in Detailed mode, Unenhanced GS off, positions locked, and both saved positions unset.

**Reset add-on settings** uses the fresh-profile defaults; **Reset summary positions** clears only the two equipment positions.

## Saved variables

Preferences are stored in `TacoTipExtrasDB`, **and so is the leaderboard**. Realm standings are written to `TacoTipExtrasDB.ranks[<realm>]`, keyed by GUID, so the board survives logging out: WoW saves the table on exit and loads it at login, and the sync engine then refreshes it against whoever else is online. A record carries name, faction, class, spec, GearScore, average item level and a timestamp — roughly 276 bytes each, which is where the 20,000-record cap and its ~5.3 MB figure come from.

Before 1.0.0 the add-on stored preferences in `TacoTipGearScoreEnhancerDB`; that name is retired and old tables are ignored rather than migrated, so a pre-1.0.0 profile starts from defaults on first load after upgrading. Nothing errors on the missing table.

Per-slot equipment detail, scanner revisions and cache entries remain **session-only** — they are what the gear panel reads, which is why the panel can only show players scanned since you logged in.

## Known limitations

- **Not yet released.** 1.0.0 is a relaunch under new packaging; the CurseForge listing does not exist yet.
- **The adapter gates on capability, not on a version number.** It enforces a minimum TacoTip version of `0.8.0` and then probes the functions it actually calls. It deliberately does **not** compare the inspector's version: `LibForeverInspector` registers the `LibClassicInspector` alias at minor 2 and defines no `Version()` method at all, so any equality check against a published version could never pass. A minimum version is still enforced, so an older TacoTip is still refused.
- **`GetItemStats` is a Mainline-family API and is absent from the three Classic clients.** It is documented in `Blizzard_APIDocumentationGenerated/ItemDocumentation.lua` on `origin/live` (Retail) *and* on `origin/forever`, and appears nowhere in the `Interface` tree of `classic_era`, `classic_anniversary` or `classic_titan`. **Classic Era and TBC Anniversary therefore take the degraded socket path**: the gem count still scores, because it comes from the item link, but the *empty* socket count, the completion percentage and the potential total are omitted rather than guessed. Retail and WoW Forever take the full socket path. The add-on feature-detects the function rather than branching on a client name, so the two Classic clients and the forced-`nostats` test variant all exercise the same degrade path.
- Remote Potential GS and Completion may be unavailable when native inspection data is not conclusive.
- Per-slot enhancement markers, item-level or score overlays beside equipment slots, and enhancement details in item tooltips are not included.
- **The base GearScore comes from `TT_GS`, not from this add-on.** Enchant (x1.05) and gem (+5 per socket) bonuses are computed here as *deltas* on top of TacoTip's number. An earlier revision carried its own copy of the formula and it was wrong above ilvl 120, where TacoTip switches to formula table A: a `HEAD` at ilvl 200 scored 310 in TacoTip and 269 in the copy.
- Current GS and Potential GS follow defined compatibility rules; they do not identify the best enhancement choices.

## Verification

The offline harness loads every file in the TOC, in TOC order, against a mocked client:

```bash
bash TacoTip_Extras/Tests/harness/run_all.sh
```

It runs under `lua5.1`, `lua5.4` and `luajit` and exits non-zero if any invocation fails.

Twelve scenarios per interpreter: five clients, then seven variants that each pin
a different branch of the compatibility code.

Every scenario asserts **which driver branch the client takes**, not merely that
it loads. `GameTooltip` declares `OnTooltipSetUnit` on the Classic family and on
Mainline only in an XML *schema*, so the two families take different code paths
and "did not raise" is not evidence either path works.

| Client | `WOW_PROJECT_*` constants the branch defines | `GameTooltip` declares `OnTooltipSetUnit` | Driver | `GetItemStats` |
| :--- | :--- | :--- | :--- | :--- |
| Classic Era 11509 | all six, `WOW_PROJECT_ID = 2` | yes | `unit-hook` | absent |
| TBC Anniversary 20506 | all six, `WOW_PROJECT_ID = 5` | yes | `unit-hook` | absent |
| Titanforge 38002 | all six, `WOW_PROJECT_ID = 11` | yes | `unit-hook` | absent |
| WoW Forever 16001 | `MAINLINE`, `CLASSIC` only | no | `poll` | **present** |
| Retail 120100 | `MAINLINE`, `CLASSIC` only | no | `poll` | **present** |

### The two tooltip drivers

- **`unit-hook` (Classic family).** `Blizzard_GameTooltip/Classic/GameTooltip.xml`
  declares `<OnTooltipSetUnit function="GameTooltip_OnTooltipSetUnit" />` at line
  22, plus `OnTooltipSetItem`, `OnTooltipSetSpell`, `OnHide`, `OnUpdate` and
  `OnShow`. The declared script drives the render.
- **`poll` (Retail, WoW Forever).** On `origin/live` and `origin/forever` the only
  occurrence of `OnTooltipSetUnit` or `OnTooltipSetItem` anywhere in `Interface`
  is `Blizzard_SharedXML/UI.xsd`, an XML schema listing the script names a frame
  may declare. `Blizzard_GameTooltip/Mainline/GameTooltip.xml` declares neither;
  the non-virtual `<GameTooltip name="GameTooltip">` adds `OnShow` and
  `<OnUpdate function="GameTooltip_OnUpdate"/>`. So the render is driven by an
  `OnUpdate` poll, which is armed by `OnShow` and disarmed by `OnHide` and
  `OnTooltipCleared`.

The poll is gated on `HasScript("OnTooltipSetUnit")`, **not** on "the other hook
failed". On a client that declares the script the poll is never hooked at all,
so there is no state in which both drivers are live and one render could be
applied twice.

WoW Forever and Retail define only `WOW_PROJECT_MAINLINE` and
`WOW_PROJECT_CLASSIC`. On `origin/forever` the single `Blizzard_FrameXMLBase.toc`
excludes the `[Family]` constants files on `camelot` and the two survivors come
from the separately-toc'd `Blizzard_ProjectConstants/ProjectConstants.lua`; on
`origin/live` it is the same file. The Classic clients each load their own
`Blizzard_FrameXMLBase_<Family>.toc`, and the per-family `Constants.lua` defines
all six **and** assigns `WOW_PROJECT_ID`. Supplying the Burning Crusade or Wrath
constant on camelot is a known trap in this project: it makes `WOW_PROJECT_ID ==
WOW_PROJECT_BC_CLASSIC` evaluate as `nil == nil`, i.e. **true**, and silently
mis-detects the client. Every scenario asserts both directions — no constant the
branch does not define, and none it does.

The client model is written down **twice** in the harness, once as the model and
once as an independent oracle transcribed from the FrameXML evidence above. A
harness that only compared the model against itself had Retail modelled as
having no `GetItemStats` and as a Classic-family tooltip, and stayed green.

| Variant | Expected verdict | Why it exists |
| :--- | :--- | :--- |
| `ok` on all five | `supported = true`, `reason = nil` | the real world |
| `devname` | `supported = true` | TacoTip's private table is published as `TacoTip_Forever`, `_G.TacoTip` is `nil` |
| `older` | `tacotip-version-unsupported` | TacoTip `0.7.0`, below the `0.8.0` minimum |
| `nocaps` | `inspector-capability-unsupported` | inspector missing `GetInventoryItemMixin`, still no `Version()` |
| `nostats` | `supported = true`, sockets degraded | `GetItemStats` forced absent; run on Classic Era, Forever **and** Retail |
| `nosettings` | `supported = true`, legacy options path | `Settings` removed; `Options` must fall back to `InterfaceOptions_AddCategory` with `childFrame.parent` wiring |

`Settings.RegisterCanvasLayoutCategory` is present on all five clients, so
`nosettings` is not reachable on a real install. It exists because
`Options.Initialize` used to `return false` when `Settings` was missing — the
same fail-closed shape as the hook bugs fixed in this add-on: no options panel,
no message, every setting unreachable — and an arm that is never reached is an
arm that ships untested.

### What the driver scenarios assert

Each scenario drives the real add-on end to end: a real local scan through the
real `Scanner`, a real `GameTooltip`, the real driver script. Nothing reaches
into module internals to fake a result.

- the driver each client takes, and which scripts were hooked
- the poll is **not even hooked** on the Classic family, and its body never
  executes a tick there
- the first tick renders rows; five unchanged ticks render nothing and add
  nothing
- the change gate is **not vacuous**: an externally added line forces a re-render
- hiding drops the binding; on Mainline it also disarms the poll, and a hidden
  or cleared tooltip costs no work at all
- `Clear()` disarms the poll through `OnTooltipCleared` (which the Classic
  `GameTooltip` does not declare, so the harness states that rather than
  pretending the guarantee transfers)
- the surface renders again after show → hide → clear → re-show
- an item tooltip adds no rows and drops the player binding

Every one of those assertions has been reverted to confirm it fails.

### What the adapter gates on

TacoTip's private table is published as `_G[addOnName]`, and `addOnName` is the
add-on's own TOC name -- `"TacoTip"` once packaged, `"TacoTip_Forever"` in a
development tree. The adapter therefore resolves it rather than hardcoding it:
the packaged name first, then a scan of every loaded add-on's private table
duck-typed on two or more of `ApplyTooltipAppearance` / `RefreshOptionsUI` /
`RefreshCharacterFrame` / `RefreshInspectFrame`, then a plain global sweep. More
than one match is reported as ambiguous and never guessed at. `TT_GS`, `TT_PAWN`,
`TacoTipConfig`, `TACOTIP_LOCALE` and `TacoTip_GSCallback` are real globals and
are used directly.

| Probed on | Capability | Called by |
| :--- | :--- | :--- |
| inspector | `RegisterCallback` | `Adapter.RegisterInventoryReady`, scanner refresh |
| inspector | `UnregisterCallback` | paired teardown |
| inspector | `PlayerGUIDToUnitToken` | `Scanner`, `Adapter` |
| inspector | `GetInventoryItemMixin` | `TT_GS:GetScore` |
| inspector | `GetLastCacheTime` | `TT_GS:GetScore`, remote readiness |
| TacoTip table | `GetDefaults` | identifies the private table |
| TacoTip table | `Refresh/InitCharacterFrame`, `Refresh/InitInspectFrame` | equipment surfaces |

`Adapter.GetCapabilityReport()` returns every probe and its result, so a refusal
can be argued with instead of guessed at.

## Credits and license

TacoTip Extras is written and maintained by **AcidBomb (Pilsung)** and is released under the MIT License — see [LICENSE](LICENSE), © 2026 AcidBomb.

TacoTip is a required external dependency; it is not bundled, modified, redistributed or forked, and this project does not imply endorsement by TacoTip or its author.
