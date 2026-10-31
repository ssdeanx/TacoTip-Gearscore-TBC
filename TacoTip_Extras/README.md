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
version: 1.2.4
author: AcidBomb
maintainer: AcidBomb (Pilsung)
license: MIT  # see LICENSE
curseforge_id: 1741092
project_url: https://www.curseforge.com/wow/addons/tacotip-extras
tacotip_url: https://www.curseforge.com/wow/addons/tacotip-gearscore
requires: [TacoTip]
clients: [Classic Era / SoD, TBC Anniversary, WotLK Titanforge, WoW Forever, Retail]
interfaces: ["11509", "20506", "38002", "16001", "120105"]
tags: [tacotip, gearscore, leaderboard, ranking, p2p, audit, inspect, enhancements, companion]
status: released
updated: 2026-10-30
```


**TacoTip Extras** is an optional companion add-on for [TacoTip](https://www.curseforge.com/wow/addons/tacotip-gearscore). It adds enhancement-aware GearScore information to genuine player tooltips and to summaries in the Character and Inspect equipment windows. TacoTip stays separately installed and keeps providing everything else it does.

- **TacoTip** — <https://www.curseforge.com/wow/addons/tacotip-gearscore> (required dependency)
- **TacoTip Extras** — <https://www.curseforge.com/wow/addons/tacotip-extras> (this add-on)

TacoTip Extras is a **separate project from TacoTip**. It has its own repository and its own CurseForge listing. It is not a fork of TacoTip, and it implies no endorsement by either.

**Version:** 1.2.4
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
| Retail | 120105 |

## Installation

Drop the `TacoTip_Extras` folder into `Interface/AddOns/`. The TOC filename must match the folder name (`TacoTip_Extras.toc`) or the client will not load the add-on at all.

## Features

- Server-wide GearScore Leaderboard & P2P Sync Engine (HonorSpy style) with dedicated background channel `ttgssync` and GUILD/PARTY/RAID broadcast fallbacks.
- Interactive Leaderboard window (`/ex ranks`, also `/ex lb`, `/ex rank`, `/ex leaderboard`) covering the **whole realm**, opening centred on your own rank, with class and guild filtering, live search, a sortable level column, `▲ Top` / `▼ My Rank` navigation, keyboard navigation, a Comfortable-rows density option, and personal rank standing.
- The leaderboard header and the Options page carry the shared **Scan disabled** control. The realm scan is blocked until the crash it caused in the inspect engine is fixed; the button is greyed out and explains itself on hover. Gear inspection, the inspect-frame summary and tooltip scores are unaffected.
- Automatic tooltip rank display (`GS Rank: #14 [#2 Warrior]`) on player hover.
- Current GS, Potential GS, Delta, Completion, Average iLvl, and optional Unenhanced GS for player tooltips.
- Extras-owned Basic and Detailed summaries for the local Character window and remote player Inspect windows.
- One shared equipment-summary mode with separately saved Character and Inspect positions.
- Locked-by-default movement using a small handle that appears only while positions are unlocked.
- Local, friendly remote, and permitted enemy remote player support with fail-closed non-player rejection.
- Native Options integration, `/ex` (aliases `/extras`, `/tte`), a movable minimap shortcut (left-click: leaderboard, right-click: settings), an **eleven-locale** leaderboard window, Options page, tooltip and equipment-summary UI following TacoTip's language setting, and reversible TacoTip coexistence. The window's labels, column headers, sort dropdown, row tooltips, empty and scan states, the footer's standing line, the class names and the time-ago strings are translated, as are the Options page's control labels, help headings and help text, the mode names and the tooltip's metric labels. A few status and diagnostic strings are still English only — see **Known limitations**.

## Metrics

- **Current GS** is the player's present and primary GearScore in this add-on. It combines equipped-item GearScore with supported bonuses from installed permanent enchants and gems. Temporary weapon effects do not count.
- **Potential GS** adds only confirmed missing eligible permanent enchants and confirmed empty sockets to Current GS. It is not a best-in-slot estimate and does not select or recommend optimal enchants or gems.
- **Delta** is Potential GS minus Current GS. It represents only the confirmed missing enhancement potential included by this add-on.
- **Completion** is the share of confirmed eligible permanent-enchant and socket opportunities that are filled. It measures enhancement completion, not character, equipment, or raid readiness.
- **Average iLvl** is the average item level across the add-on's fixed TBC equipment-slot model. Enchants and gems do not affect it.
- **Unenhanced GS** is an optional comparison using the same equipped items with only the installed permanent-enchant and gem bonuses counted by this add-on removed. It is not the player's present GearScore.

Potential GS, Delta, and Completion appear only when their required item and socket evidence is conclusive. Unavailable or unknown information is never represented as zero.

**The level-70 rule.** Potential GS, Delta, and Completion are hidden for a character below level 70 while **Restrict Potential, Completion, and warnings to level 70** is on — which is the default. Turn that setting off and the same three values are computed and shown at any level: the numbers do not change, only whether you are shown them. The setting takes effect immediately; the values are recomputed from the gear that has already been read, so nothing is rescanned and no re-inspection happens. Current GS, Unenhanced GS, and Average iLvl are never affected by it.

## Player-tooltip modes

A new install starts on **Detailed**, so every enabled metric is on screen from
the first tooltip instead of behind a summary. An install that has already
saved a mode keeps it: pick another one in the Options page, or press **Reset
enhancer settings** to go back to the defaults.

- **Disabled:** shows no add-on rows and safely releases the TacoTip player-GearScore takeover.
- **Minimal:** shows the shortest enabled summary, prioritizing Current GS and Average iLvl. It omits Unenhanced GS.
- **Compact:** shows up to two concise rows using `GS` for Current GS, optional Average iLvl, useful positive Delta, and Completion when available. It omits Potential GS, Unenhanced GS, and the completion fraction.
- **Detailed:** shows each enabled, available metric on a separately labelled row in this relative order: Current GS, Potential GS, Delta, Completion, Average iLvl, then Unenhanced GS when explicitly enabled.

## Server-Wide GearScore Leaderboard & P2P Sync

TacoTip Extras features a decentralized, HonorSpy-style peer-to-peer sync engine that continuously aggregates player GearScores across your realm:

- **Interactive Leaderboard Window:** Access via `/ex ranks` (`/ex lb`, `/ex rank`, `/ex leaderboard` also work), or via the **Open Server Leaderboard** button in Options.
  - Ranks the **whole realm**. There is no Alliance/Horde split — a faction filter would only hide the players you want to compare yourself against.
  - **Shows sixteen players at once**, in a window wide enough for the name and spec columns to be read without crowding. The window's content is a clean vertical stack — title, filter row, summary strip, sort readout, column headers, table, progress rail, footer — and every part of it has its own space, so nothing is drawn on top of anything else.
  - **Opens on your own rank.** The window scrolls to your position and centres you on the middle visible row every time it opens, honouring the active filters and search.
  - **`▼ My Rank`** re-centres you at any time; **`▲ Top`** jumps back to `#1`.
  - **Sort** by clicking the `GEARSCORE`, `iLVL`, `LEVEL` or `LAST SEEN` headers. Clicking the active header reverses its direction; switching columns resets to descending. The active column is underlined and the current order is stated on screen, on a line of its own below the summary strip and clear of the column headers. The `#` column always stays the **GearScore rank**, whichever way the list is sorted, so sorting never makes standing look like it moved.
  - **Hover any row** for full detail: spec, GearScore, Average iLvl, realm rank, last-seen, guild where known, and advisory PvP lines (Era/TBC/Wrath only; never rendered from synced data on Retail/Forever).
  - **Escape closes the browser**, on every supported client.
  - Filter by class from the **class dropdown**, by guild substring from the guild box, or type a name fragment into the search box for live filtering.
  - A muted strip reports pool size, top GearScore and realm-average GearScore; rows first seen this session carry a fresh tick.
  - The footer's `Scan disabled` control is mirrored on the Options page; both are greyed out while the realm scan is blocked. `Up`/`Down` moves an entry-anchored focus ring, `Enter` opens that row's gear. A `Comfortable rows` checkbox rebuilds the list at 32px rows (default 26px).
  - Your own row carries a **highlight and a `YOU` marker**, so you can see at a glance which row is you.
  - **Click any row** to open a **gear panel** for that player: their 17 equipped slots, each rendered as a real item link so the game supplies quality colour and hover tooltips. The panel has its own dark background and border, so it stays readable over whatever is behind it. Slot labels use Blizzard's own `INVTYPE_*` strings, so the panel is translated in every language the client ships. A fresh session entry renders live links; otherwise persisted IDs render dimmed with a last-synced note; only when neither exists does the plain explanation appear rather than blank rows.
  - Top players get percentile-coloured rank numbers: `#1` is the top band because it *is* the highest GearScore. The class-rank number in the tooltip line uses the same scale against the class pool.
  - Every row has a thin class-colour bar, hover highlighting, and muted spec / last-seen columns.
  - Footer banner shows your character's personal Overall, Faction, and Class ranks.
- **Tooltip Rank Display:**
  - Renders a rank line on player tooltips: `GS Rank: #14 [#2 Warrior]`, with the numbers coloured by percentile. Detailed and Minimal show the class name in its class colour; Compact replaces the class name with the class icon, degrading to the class name where the client cannot resolve the atlas. The unit tooltip gains one trailing muted line, `Rank synced: <relative>` (rows older than the session).
  - Can be toggled on/off in the Options panel (`Show server leaderboard rank`).
- **Silent Background Sync:**
  - Automatically exchanges inspection records over the hidden chat channel `ttgssync` with fallback broadcasts to `GUILD`, `PARTY`, and `RAID` (`INSTANCE_CHAT` inside instances).
  - Records ride one versioned stride (`R;2;…`, 13 fields); gear travels only on demand (`G` asks, `D` answers in chunks inside the same 240-byte door).
  - **Asks for data instead of only listening.** A client that has just logged in sends a `Q` query; peers answer with `S` (their own current record) and `T` (a short digest of the best records they hold). Without this a fresh install stayed empty until enough players happened to re-gear near it.
  - **Flood-controlled on both sides.** Each client answers at most one query per 20 seconds, and answers are jittered by a random 1–4 seconds so a group logging in together does not answer in the same instant. Responses are sized against the 255-byte addon-message limit; enqueue refuses anything over 240 bytes.
  - Re-driven on login, `/reload`, instance transitions and open-world zone changes, throttled to one round per 30 seconds.
  - Channel output is silenced from chat windows with zero chat clutter.
  - Rate-limited with a token bucket (1 msg / 1.5s, burst max 3) to prevent disconnects.
  - Stale data is automatically pruned after 60 days, with a 20,000 player capacity cap (measured at ~5.3 MB of SavedVariables).

### What other players can see

The sync is not private and is not meant to be. This is exactly what leaves your client:

- **Your character is identified by a unique ID.** That ID travels with every record you send. It is the internal ID the game uses for your character, and it is what lets the leaderboard tell one character's record from another's.
- **Your record carries your name, class, specialization, guild, level, PvP rating, GearScore, average item level, and the time it was recorded.** Your realm is never sent — a record always files under the realm of the client that received it.
- **Inspecting another player shares that player too.** When you look at someone else's gear, a record for *them* is sent out as well, so the data about a person you inspected is shared with everyone on the channel, not only their own data.
- **The channel name and the message format are part of the shipped files.** Anyone who joins that channel can read the traffic on it, and anyone can write to it. Nothing is encrypted, and the channel name is not hidden.
- **Gear is shared on request only, and only as item IDs.** When the leaderboard asks another player for their gear, that player answers with the item IDs in their equipment slots — no item links, no enchant names, no gem names, and nothing else about that character.
- **The guild roster is not shared.** Only the guild name on your own record is.

Nothing you type in chat, and no setting other than the ones listed above, is sent.

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

- `/ex` (also `/extras`, `/tte`; always opens the main category and never closes Settings)
- right-click the minimap button (toggles settings)
- Esc → Options → Add-Ons → TacoTip Extras

Open the leaderboard via `/ex ranks` (or `/ex lb`), the **Open Server Leaderboard** button, or left-click on the minimap button.

The main category retains tooltip, scoring-policy, minimap, class-colour, restore, and reset controls. Its **Equipment Windows** child category contains the shared summary mode, the optional Detailed Unenhanced comparison, the lock/unlock control, and **Reset summary positions**. `/ex` and right-click open the main category; left-click toggles the leaderboard.

The category is registered through `Settings.RegisterCanvasLayoutCategory` with
`Equipment Windows` as a `RegisterCanvasLayoutSubcategory` beneath it. When
`Settings` is absent the same panel is registered through the legacy
`InterfaceOptions_AddCategory`, with `childFrame.parent` set to TacoTip's own
category name for the main page and to this add-on's main page for the equipment
page, so the nesting is the same on both APIs. The main page is therefore a
child of TacoTip's category rather than a second top-level entry.

The minimap button can be dragged around the minimap. Right-click toggles the add-on category, closing it when that exact category is active, or switching to it from another Settings category. Left-click toggles the leaderboard. `/ex` always opens; it never closes Settings.

**The diagnostic snapshot is published for TacoTip.** `/ex debug` prints the add-on's live counters — scan state, metric values, sync buckets, listener errors and initialization failures — to the chat frame, and it works on its own. The client's slash-command table is a proxy that is emptied before a command is dispatched, so another add-on cannot read this handler back out of it; the Extras therefore publishes the same function on the plain global `_G.TacoTipExtrasPrintDebugSnapshot`, which TacoTip calls directly. The slash handler and TacoTip both call that one global, so there is a single implementation and the printed content is unchanged.

**Enable add-on** is the master output switch. Disabling it retains child preferences, hides add-on output, and releases every active TacoTip lease. **Restore TacoTip settings** remains a tooltip-only action: it disables and releases only the player-tooltip takeover and its `show_gs_player` recovery record. It does not change or suspend the equipment summary, its mode, or its positions.

**Shaman Blue** shows the Shaman class name in blue instead of pink. Classic Era paints the Shaman class colour pink, so without this the class name in the tooltip, in the Character and Inspect windows, and in the leaderboard all read pink. The option is on by default, and those three places always agree with each other. If TacoTip is installed, its own Shaman Blue setting applies as well: turning it off there turns the blue off here too, so the class colour is the same in both add-ons.

The options page is laid out in two columns. Each option's label is kept inside its own column and wraps onto a second line when it is long, and each checkbox's clickable area covers the box and its own label and nothing else — so no option can be clicked in place of the one next to it.

A fresh profile starts with both player tooltips and equipment summaries in Detailed mode, Unenhanced GS off, Shaman Blue on, positions locked, and both saved positions unset.

**Reset add-on settings** uses the fresh-profile defaults; **Reset summary positions** clears only the two equipment positions.

## Saved variables

Preferences are stored in `TacoTipExtrasDB`, **and so is the leaderboard**. Realm standings are written to `TacoTipExtrasDB.ranks[<realm>]`, keyed by GUID, so the board survives logging out: WoW saves the table on exit and loads it at login, and the sync engine then refreshes it against whoever else is online. A record carries numeric class/spec IDs plus guild, level, PvP rank and arena alongside name, GearScore, average item level and a timestamp — roughly 276 bytes each at the diet shape, growing with the expanded fields, which is where the 20,000-record cap and its ~5.3 MB figure come from. Faction stays storage-only and optional; the realm never leaves the sender because inbound records always file under the receiver's own realm. Synced gear persists separately in `TacoTipExtrasDB.gear`, capped at 2,000 rows per realm under the same 60-day age prune (7 days / 1,000 rows on the aggressive pass).

Before 1.0.0 the add-on stored preferences in `TacoTipGearScoreEnhancerDB`; that name is retired and old tables are ignored rather than migrated, so a pre-1.0.0 profile starts from defaults on first load after upgrading. Nothing errors on the missing table.

Per-slot equipment detail renders live while a fresh scanner revision exists; persisted IDs back it with dimmed literals and a last-synced note, which is why the gear panel can show players scanned on an earlier session.

## Known limitations

- **Release status.** Version **1.2.4** is the current build in this repository; the CurseForge listing is the published distribution channel for the add-on.
- **The Options page's integration and enhancement status lines, and the gear panel's "Last synced" note, are still English only.** The three status lines under the Options page — "TacoTip integration: …", "Remote enhancement analysis: …" and "Remote enhancement blocker: Slot …" — and the forty-seven sentences they can expand into (the compatible / incompatible / not-loaded reasons and the remote complete / unavailable / pending / suppressed / not-observed reasons) are written in English in the source, as are the **Reset summary positions** button label, the **How these scores work** heading, the equipment windows' **Drag** handle label and the gear panel's **Last synced …** and **Synced gear (item IDs only)** notes. Everything else on those surfaces is translated. Localizing them is a separate translation pass, not a code change: the strings are hardcoded English today, and the locale keys that once existed for them were never read by any code path, so they have been removed rather than left as dead weight.
- **The level-70 restriction is a display rule.** While **Restrict Potential, Completion, and warnings to level 70** is on (the default), Potential GS, Delta, and Completion are not shown for a character below level 70 and the related warnings are held back; Current GS, Unenhanced GS, and Average iLvl still show. Turning the setting off shows the same three values at any level. On Classic Era, TBC Anniversary, and Titanforge those three metrics stay unavailable regardless of the setting, because the client does not expose the socket data they need (see the `GetItemStats` note below).
- **The socket count comes from the documented API, and a count that contradicts the item's own gems is withheld rather than published.** On Retail and WoW Forever the number of socket slots is read from `C_Item.GetItemNumSockets` — the socket-count API Blizzard's own character frame uses, which passes the raw item link straight into it (`PaperDollFrame.lua:2775`, fed by `GetInventoryItemLink` at `:1728`; documented at `Blizzard_APIDocumentationGenerated/ItemDocumentation.lua:854` on `origin/live`, `:876` on `origin/forever`). The add-on still cross-checks that count against the item's own gem list, parsed from the item link, and now in **both** directions: a count that is too small for the item's gems and a count that is too large for them both leave the socket-based metrics **unavailable rather than guessed** on that item.
- **The adapter gates on capability, not on a version number.** It enforces a minimum TacoTip version of `0.8.0` and then probes the functions it actually calls. It deliberately does **not** compare the inspector's version: `LibForeverInspector` registers the `LibClassicInspector` alias at minor 2 (only when that name is not already held by another library) and defines no `Version()` method at all, so any equality check against a published version could never pass. A minimum version is still enforced, so an older TacoTip is still refused.
- **`GetItemStats` is a Mainline-family API, is absent from the three Classic clients, and is what the socket path is gated on.** It is documented in `Blizzard_APIDocumentationGenerated/ItemDocumentation.lua` on `origin/live` (Retail) *and* on `origin/forever`, and appears nowhere in the `Interface` tree of `classic_era`, `classic_anniversary` or `classic_titan`. **Classic Era, TBC Anniversary and Titanforge therefore take the degraded socket path**: the gem count still scores, because it comes from the item link, but the *empty* socket count, the completion percentage and the potential total are omitted rather than guessed. Retail and WoW Forever take the full socket path. The add-on feature-detects the function rather than branching on a client name, so the three Classic clients and the forced-`nostats` test variant all exercise the same degrade path. The socket *count* itself does **not** come from `GetItemStats` — it comes from `C_Item.GetItemNumSockets` — and that API is documented on the Classic branches too; the gate deliberately does not widen to it, because the Classic clients' behaviour is a shipped, documented contract and widening it would change published numbers on clients that cannot be tested before publish.
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

Fourteen scenarios per interpreter — twelve load scenarios (five clients, then
seven variants that each pin a different branch of the compatibility code)
plus two leaderboard-behaviour runs that drive the browser and assert what it
rendered. Fourteen per interpreter across three interpreters is 42
invocations in total.

Every scenario asserts **which driver branch the client takes**, not merely that
it loads. `GameTooltip` declares `OnTooltipSetUnit` on the Classic family and on
Mainline only in an XML *schema*, so the two families take different code paths
and "did not raise" is not evidence either path works.

| Client | `WOW_PROJECT_*` constants the branch defines | `GameTooltip` declares `OnTooltipSetUnit` | Driver | `GetItemStats` (the socket path's gate) |
| :--- | :--- | :--- | :--- | :--- |
| Classic Era 11509 | all six, `WOW_PROJECT_ID = 2` | yes | `unit-hook` | absent |
| TBC Anniversary 20506 | all six, `WOW_PROJECT_ID = 5` | yes | `unit-hook` | absent |
| Titanforge 38002 | all six, `WOW_PROJECT_ID = 11` | yes | `unit-hook` | absent |
| WoW Forever 16001 | `MAINLINE`, `CLASSIC` only | no | `poll` | **present** |
| Retail 120105 | `MAINLINE`, `CLASSIC` only | no | `poll` | **present** |

`C_Item.GetItemNumSockets` — the API the socket *count* is read from — is
documented on all five branches, so the mock installs it on all five clients
too. The Classic degradation is therefore the **gate's** doing and not an
accident of the model: the harness proves it by removing the gate and watching
the Classic socket path come back.

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
