# Changelog — TacoTip Extras

All notable changes to TacoTip Extras are documented in this file.

| Version | Date | Summary |
| :--- | :--- | :--- |
| `1.2.3` | `2026-10-18` | **A shorter label, the class icon where space is tight, and a leaderboard rebuilt from the window up.** The tooltip rank line's label is now `GS Rank:` in every tooltip mode and in all eleven locale files, replacing the long `Gearscore Rank:` and its translations. Detailed and Minimal are otherwise unchanged: the class name inside the brackets still keeps its class colour, between white brackets, with the class-rank number in its ranking colour. Compact replaces that class name with the player's normal class icon — a fixed 14x14 `|A:<atlas>:14:14|a` resolved through `GetClassAtlas`, with no class-colour tint — and degrades to the class name if the client cannot resolve the atlas, so the bracket never loses its content. The tooltip now starts in **Detailed** mode on a fresh install (an existing install keeps the mode it saved), and the Extras gains its own **Shaman Blue** option, on by default, so the Shaman class name reads blue in the tooltip, in the character and inspect summary and in the leaderboard row instead of Classic Era's pink — with TacoTip's own Shaman Blue setting still governing it whenever TacoTip is installed. The leaderboard window is **rebuilt as a 900-pixel-wide stack of bands** — title, filter row, summary strip, sort readout, column headers, table, progress rail, footer — showing sixteen players at once, so the "Sorted by" readout no longer sits on the column headers and no two bands can be given the same space; and the **gear panel** that opens on a row click is **opaque again**, because it was created as a plain frame with no template and therefore had no backdrop at all. Retail's interface target advances to 12.1.5 (`120105`). Record timestamps, age cutoffs and last-seen labels now read server time (`GetServerTime`) instead of the local system clock, while the 30-second re-sync throttle stays on monotonic client uptime. The harness now asserts the compact icon markup, the Detailed class colour, and the degraded path. The rank-sync wire path now answers on the transport a query arrived on, never confuses a refused send with delivery, and the leaderboard explains its empty, sorted and unranked states. A final silent-failure audit closes nine more paths where the add-on looked like it was working and was not: the gear panel is closed with the browser and re-rendered after a rebuild instead of showing stale gear, a raising scorer is counted and reported rather than leaving the old verdict in place, the footer's two buttons no longer overlap, the mode dropdown and two leaderboard strings are localized, the options hit rects are re-measured on every refresh, two buttons say which module is missing, a missing rank database says so, and unticking every tooltip field no longer loses the tooltip mode. |
| `1.2.2` | `2026-10-14` | **The rank line reads the way the leaderboard reads.** The tooltip rank line drew its numbers from the raw percentile quality bands, so the best rank in the game rendered purple — purple is the top of the *quality* scale, not the top of a *standing* — while the leaderboard's `#` column badged the same standing gold. The scale now lives in one place, `Scoring.RankColor(rank, total)`, and both surfaces resolve through it: the podium keeps gold/silver/bronze, anyone else inside the top 5% of the pool reads gold, and the rest take the quality bands. The `[` `]` around the class rank are drawn white instead of borrowing the number's colour, so they read as punctuation. `Scoring.RankColor` also corrects an inverted top-5% test inherited from the leaderboard's original `getRankColor` — it compared `place / total >= 0.95`, which painted the *bottom* 5% of a pool gold and the top 5% by percentile; the podium cases happened to hide it, because `#1` matched the separate rank-1 branch first. |
| `1.2.1` | `2026-10-13` | **Sync now asks.** Until this release a client only received what other clients happened to broadcast — which is when their own gear changed — so a fresh install stayed empty until enough people re-geared near it. There is now a query/response protocol (`Q` asks, `S` returns the sender's own record, `T` a short digest of their best), flood-controlled by a 20-second per-client respond interval and a 1–4s random jitter, and sized against the 255-byte addon-message limit. **Click a leaderboard row to open a gear panel** for that player, rendering the cached per-slot items as real item links so the client supplies quality colour and hover tooltips. Slot labels use Blizzard's own `INVTYPE_*` strings, so the panel is translated into languages this add-on has never been translated into. Sync no longer discards records with an empty field: the deserializer used `gmatch("([^;]+)")`, which skips empty fields and therefore rejected every record whose `specName` or `faction` was blank — a routine case, and a silent one. Eleven-language localization (deDE, esES, esMX, frFR, itIT, koKR, ptBR, ruRU, zhCN, zhTW over an enUS source of truth) wired through every user-facing string, following TacoTip's own language setting. Minimap button now opens the leaderboard on left-click and settings on right-click. Options' "Open Server Leaderboard" moved off the description text to the top-right. Rank numbers are coloured by percentile through `Scoring.QualityColor` — a function the leaderboard had always called and that did not exist, so every GearScore and iLvl value had rendered white. Tooltip rank line reads `[#2 Warrior]` with the ranking number coloured by standing and the class name in its class colour. A scan button on both the leaderboard header and the Options page drives one shared scan, with a progress rail fed by the new `Scanner.GetProgress()`. Per-realm capacity raised to 20000 records, measured at ~5.3 MB of SavedVariables. Sync re-driven on login, reload, instance transitions and open-world zoning, throttled to once per 30 seconds. Cross-client hardening folded into this release: legacy `GetAddOnMetadata` fallback in `Core.GetVersion`, guarded `BackdropTemplate`/`KEY_ESCAPE` browser setup, UTF-8-safe truncation and capacity enforcement in `RankDB`, explicit `gs` sorting, lowercase/uppercase equip-location normalization, nil-safe metric-row inserts, guarded adapter color access, and tooltip `AddLine` wrap flag. |
| `1.2.0` | `2026-10-13` | Authorship unified on AcidBomb across LICENSE, TOC metadata, and both in-game credit strings. The login banner now prints "TacoTip Extras" rather than the retired "TacoTip GS Enhancer". | Leaderboard browser upgraded: click-to-sort columns, per-row hover tooltips, specialization icons, Escape-to-close fixed for the Classic family, `/tt lb`, and a labelling pass. |
| `1.1.0` | `2026-10-13` | Leaderboard browser rebuilt: whole-realm ranking with no faction split, opens centred on your own rank, `▲ Top` / `▼ My Rank` navigation, class filter and live search, and a modernized row treatment (class colour bar, podium rank badges, hover highlight, `YOU` marker). Adds a focused offline harness that drives the browser and asserts what it rendered. |
| `1.0.2` | `2026-10-13` | Polish release: renamed the player-tooltip rank label to `Gearscore Rank:`, restyled it to match the add-on's brand palette, recolored Average iLvl values from class colors to GearScore quality colors across tooltips, equipment windows and the server browser, and fixed the leaderboard window not opening from the Options button / slash commands on all clients. |
| `1.0.1` | `2026-10-12` | Server-wide GearScore Rank Browser & P2P Sync Engine (HonorSpy style) in background channel `ttgssync` + GUILD/PARTY/RAID fallbacks, interactive Leaderboard UI (`/tt ranks`, `/ttrank`, `/ttleaderboard`), player tooltip rank line (`Rank: #X (#Y Class)`), and remote inspect equipment scanning deadlock fix across Retail and WoW Forever. |
| `1.0.0` | `2026-10-11` | Initial release of TacoTip Extras companion addon. Full equipment and enhancement auditing, modern retail engine compatibility (variable-length bonus ID item links, 16-slot average item level, CharacterModelScene support), Detailed display mode default, and 100% zero-warning static analysis. |

## [1.2.3] — 2026-10-18

> The rank line says the same thing in less space — and in Compact, it says
> "warrior" without spending eight characters on the word. Alongside it: the
> sync wire answers on the transport a query arrived on instead of a channel
> Classic clients cannot carry, and the leaderboard starts explaining its
> empty, sorted and unranked states out loud.

### Changed

- **The tooltip rank label is `GS Rank:` in every mode and every locale.** The
  long `Gearscore Rank:` label (and its translated equivalents) is gone from
  Minimal, Compact and Detailed alike. The locale files carry the shortened
  label: `GS-Rang:` (deDE), `Rango GS:` (esES / esMX), `Rang GS :` (frFR),
  `Posizione GS:` (itIT), `Posição GS:` (ptBR), `Ранг GS:` (ruRU), `GS 순위:`
  (koKR) and `GS 排名：` (zhCN / zhTW).
- **Detailed and Minimal are otherwise untouched.** The class name inside the
  brackets still renders in its class colour, between white brackets, with the
  class-rank number in its ranking colour. No icon was added to either mode.
- **Compact replaces the class name with the player's class icon.** The compact
  line shows the player's normal class icon: a fixed 14x14 `|A:<atlas>:14:14|a`
  built from `GetClassAtlas(classFile)`, drawn with no class-colour tint,
  where `classFile` is the second return of `UnitClass(unit)`; it deliberately
  does not reuse the player-name line's configurable icon size. If the client
  does not expose `GetClassAtlas`, the call raises, or the atlas or class token
  comes back empty, the line degrades to the class name exactly as before —
  never to an empty bracket and never to a raised error.

### Two operator requests: Detailed by default, and a Shaman Blue option

- **The tooltip now starts in Detailed mode instead of Compact.** A fresh
  install opens on Detailed, so the enhancement rows the Extras exists to show
  — Current GS, Unenhanced GS, Potential GS, Delta, Completion and Average
  iLvl, each on its own labelled row — are visible straight away. Compact
  still shows up to two summary rows and is still one dropdown click away.
  **An existing install keeps whatever mode it saved.** The saved mode is a
  plain value with no record of whether the player ever chose it, so "Compact"
  cannot be told apart from an old default that was written once and never
  touched; overwriting it would throw away a deliberate choice. To move an
  existing install onto Detailed, open the Extras options page and either pick
  Detailed in the "Tooltip mode" dropdown, or press "Reset enhancer settings",
  which puts every setting back to its default.
- **"Shaman Blue" now applies to the Extras as well as to TacoTip.** Classic
  Era paints the Shaman class colour pink, so the class name in the tooltip,
  in the character and inspect windows, and in the leaderboard read pink while
  TacoTip's own class name read blue. The Extras now has its own "Shaman Blue"
  option, on by default, and all three of those places use the same blue and
  the same rule. When TacoTip is installed its own "Shaman Blue" setting
  applies too: turning it off there turns the blue off in the Extras as well,
  so the class colour is the same in both add-ons. A TacoTip that is not
  installed, or whose value cannot be read, leaves the Extras' own setting in
  charge.

### The gear panel is opaque again, and the leaderboard window has room

- **The gear panel is no longer transparent.** Clicking a leaderboard row
  opened the player's gear panel with no background at all, so its text was
  unreadable over whatever was behind it. The panel was created as a plain
  frame with no template, and a plain frame in the real client has no
  `SetBackdrop` at all — so the `if f.SetBackdrop then` guard around the
  backdrop quietly skipped it. The panel is now created with the
  `BackdropTemplate`, which is the template that actually carries the
  backdrop API, with the mixin applied by hand as a fallback. **The gear panel
  is therefore the one surface that carries the 0.9-dark
  `UI-DialogBox-Background-Dark` backdrop and its border.** The leaderboard
  *window* does not: it is created with `ButtonFrameTemplate`, whose
  inheritance chain carries no `BackdropTemplateMixin` and therefore no
  `SetBackdrop`/`SetBackdropColor` at all — `PortraitFrameTemplate` →
  `PortraitFrameTemplateNoCloseButton` → `PortraitFrameBaseTemplate`, whose
  mixins are `PortraitFrameMixin` / `PortraitFrameTemplateMixin`
  (`SharedUIPanelTemplates.xml:387`, `:440`, `:545`, `:708` on the Classic
  family; the same file carries no `BackdropTemplateMixin` anywhere on live
  and forever either), so the window paints its own background texture
  instead. The gear panel is thus a dark dialog of its own, not a
  continuation of the window's frame.
  The gear panel keeps its own 400x470 size; enlarging the window does not
  stretch it.
- **The leaderboard window is bigger, and the sort readout no longer sits on
  the column headers.** The window is now 900 wide and considerably taller
  than it was, and it shows sixteen players at once instead of twelve, so the
  list no longer has to be scrolled to reach the players who matter. The
  player-name and spec/class columns are wider with it.
- **The window's content is a clean vertical stack, and every part of it has
  its own space.** The "Sorted by GEARSCORE" readout had been anchored at the
  same height as the sortable column headers — the two were drawn on top of
  each other — and the readout also crowded the summary strip above it, while
  the filter row ran into the headers and the footer crowded the progress
  rail. The window is now laid out as a stack of bands — title, filter row,
  summary strip, sort readout, column headers, table, progress rail, footer —
  and the window's height is the sum of those bands, so no two of them can
  ever be given the same space. The column headers sit on their own row and
  line up with the columns below them, and the last row of the table stops
  short of the progress rail.
- **The spec icon no longer covers the spec name.** The small spec icon in
  each row was anchored to a fixed offset that put it on top of the first
  characters of the spec text. It is now anchored to the spec column itself,
  the same way the class icon is anchored to the name column, so the two
  cannot overlap however the columns are sized.

### The options page lays out in two clean columns

- **A long option label no longer runs into the next column.** The tooltip
  options page is two columns of checkboxes, and the long "Restrict Potential,
  Completion, and warnings to level 70" label had no width limit, so it ran
  straight through the "Show server leaderboard rank" control beside it. Every
  label is now capped to the width of its own column and wraps inside it, so
  the two columns of labels line up and neither reaches the other.
- **No option can steal another's click.** Each checkbox's clickable area used
  to be stretched a flat 240 or 500 pixels to the right, which reached across
  the gap between the columns — so a left-hand option's clickable region, and
  the highlight the client draws over it, landed on the right-hand column's
  control. The clickable area is now the option's own label and nothing
  beyond it, which is what it was always meant to cover.
- **"Comfortable rows" now shows whether it is on.** It was the one checkbox
  the page never refreshed, so a profile that had the setting on came up with
  the box looking off.

### The first click on the leaderboard now opens it

- **The leaderboard window is hidden when it is created, so the first click
  opens it.** The game leaves a newly created frame on screen — the window
  templates do not hide it, which is why Blizzard's own panels carry
  `hidden="true"` on the frame itself — so the leaderboard was appearing the
  moment it was built, and the first click then *closed* it instead of
  opening it. The window is now hidden as soon as it is created, and the
  first click opens it as it should.
- **The gear panel is hidden the same way**, so it is never on screen between
  being created and being filled in.
- **The offline harness now models the client.** It used to create every frame
  hidden, which the game does not do — and because the leaderboard's open and
  close both branch on whether the window is showing, the harness and the game
  disagreed about what the very first click did, and a "the first click does
  nothing" bug could not be caught. The harness now creates frames the way the
  game does, and asserts that the first click opens the leaderboard and the
  second closes it.

### Fixed

- **The Character and Inspect equipment summaries are back.** They are a
  documented feature of this add-on — the README says so — and on every client
  they had been dead since they were written, silently. The cause was an
  unguarded `HookScript` on the paper-doll frame for a script that frame does
  not declare: `Frame:HookScript` raises "bad argument #2 to 'HookScript'"
  when the frame does not declare the script (the same failure that aborted
  the **main** add-on's whole Retail load in 0.7.8), the raise unwound the
  whole bind, and the equipment module never finished initializing. Nothing
  told the player: the leaderboard, the tooltips and the options all kept
  working, and the only trace was one line in the `/ttgsdebug` ledger. The
  hooks are now installed **only on frames that declare the script**, and every
  skip and every failure is counted and named in the debug surface.
  The summaries also had a **second** fault: they were refreshed from the
  paper doll, which carries no `hidden` attribute and is therefore shown from
  the moment the client creates it — its `OnShow` fired long before this
  add-on loaded, so a hook on it could never fire again. They are refreshed
  from the **character pane** and the **inspect pane** now, which are hidden at
  creation and fire their `OnShow` once per open. The main add-on made the
  same correction in 0.8.4; the Extras had not.
- **The harness now models the client's own frame script sets** instead of
  giving every frame every script. The blanket model could not see an
  unguarded hook on a frame that declares no such script — the exact class of
  defect the house's first lesson is about ("a mock must reproduce what the
  client LACKS"). The four frames the Extras hooks (the paper doll, the
  inspect paper doll, the character pane, the inspect pane) now carry the
  script sets the client actually gives them, and the pins go red on the old
  code: restoring the unguarded `OnSizeChanged` hook fails the initialization
  check, and moving the refresh back onto the paper doll fails the
  live-trigger check.
- **Every callback this add-on registers on a Blizzard frame now runs inside
  `securecall`**, the engine's containment primitive. Addon code inside a
  Blizzard frame's script chain taints that frame, and the taint reaches the
  game menu, where the Logout/Quit button is refused and the player cannot
  log out. `securecall` is present on every supported client (Blizzard
  captures it as a local: `Blizzard_FrameXML/SharedPetBattleTemplates.lua:5`
  `local securecall = securecall;`) and is probed once at load, so a client
  that ever refused addon code to call it degrades to the direct call instead
  of raising on every tooltip event.
- **Record timestamps now come from the server clock, not the local system
  clock.** Every age comparison, last-seen label and incoming-record bound used
  Lua's `time()`, which reads the player's machine clock — a clock that can be
  unset, skewed or simply wrong. A client whose clock ran behind could stamp
  records in the past and have them pruned immediately; one whose clock ran
  ahead could stamp them in the future, where last-write-wins would then reject
  every honest record that arrived later. The six call sites this change
  converted, and what each one actually measures:

  - `RankDB.lua:233` (`ValidateRecord`) bounds an incoming timestamp to
    `now + 300` and otherwise stamps the record with the current time.
  - `RankDB.lua:454` (`BuildSortedIndices`) computes the `MAX_AGE_SECONDS`
    cutoff that decides which records enter the sorted leaderboard.
  - `RankDB.lua:648` (`PruneStaleRecords`) computes the age cutoff used by
    pruning.
  - `RankBrowser.lua:379` (`formatRelativeTime`) computes the `LAST SEEN`
    difference behind "2 hr ago".
  - `Scanner.lua:266` (`queueRankSync`) stamps a record captured by an
    inspection with the moment it was scanned.
  - `RankSync.lua:1344` (`syncNow`) is deliberately different. It is the
    30-second re-sync throttle: a purely in-session elapsed-time comparison
    (`now - lastSyncAt`) whose value is never persisted. That site now uses the
    existing `getClock()` helper — `GetTime()`, client uptime — rather than
    epoch time, because a throttle has no calendar meaning and uptime cannot be
    moved by a server-time correction. The other five use the guarded
    `GetServerTime and GetServerTime() or 0` (Scanner reads the global through
    `rawget` first), matching the add-on's existing nil-guard style.

- **Stored timestamps remain valid; no migration is needed.** Records already
  in SavedVariables were written as Unix epoch seconds, and `GetServerTime()`
  returns the same epoch scale. Old and new timestamps are therefore directly
  comparable, so age pruning, last-write-wins and last-seen ordering keep their
  existing meaning.

- **`GetServerTime` is available on all five supported clients.** Verified
  against `wow-ui-source`: the three Classic branches call it in
  `Interface/AddOns/Blizzard_Communities/Classic/CommunitiesTicketManagerDialog.lua:67`
  (`origin/classic_era`, `origin/classic_anniversary`, `origin/classic_titan`),
  and `origin/forever` and `origin/live` document it in
  `Interface/AddOns/Blizzard_APIDocumentationGenerated/SystemTimeDocumentation.lua:30`.
  The guarded form keeps a client without the global (or a harness that has not
  mocked it) from raising.

### Client support

- **Retail interface target advanced to 12.1.5 (`120105`).** The TOC
  `## Interface:` list and the harness client model now agree. No other client
  target changed.

### Verified

The harness asserts the compact icon markup (`|A:classicon-WARRIOR:14:14|a`),
that the icon is not colour-wrapped and closes directly into the white bracket,
that the bare word `Warrior` is absent from the compact line, that a Detailed
render keeps `Warrior` in `RAID_CLASS_COLORS.WARRIOR` and contains no icon, and
that a render with `GetClassAtlas` removed falls back to the class name. The
harness now provides `GetServerTime` from `os.time`, the same source as its
existing `time` mock, in both `load_test.lua` (the five-client load matrix) and
`rankbrowser_test.lua` (the browser driver), so the pre-existing time-based
expectations still exercise the new call instead of falling through its nil
guard. Every application-level harness invocation passes on Lua 5.1, Lua 5.4 and
LuaJIT: 42 invocations, 42 passed.

### Sync delivery correctness (Stage 1)

The rank-sync wire path was rebuilt to match the storage-expansion audit's
Stage 1 list (§6.2): eight ways a send could vanish while looking identical to
a delivery. The whole protocol now threads `CHAT_MSG_ADDON`'s real context
(arg3 channel/chat type, arg4 sender — argument order per Blizzard's generated
docs, `ChatInfoDocumentation.lua:617-628`) instead of reading only the payload.

- **Answers travel the query's own transport.** A GUILD query is answered on
  GUILD, a PARTY/RAID/INSTANCE_CHAT query on the same, and a CHANNEL query on
  the channel only while the state machine says it carries. The pre-Stage-1
  code answered every query on CHANNEL, so guild- and party-askers were heard
  only by whoever was also in the sync channel.
- **A refused send is counted and retried, never confused with delivery.**
  `rawSend` reads the `SendAddonMessageResult` value — verified identical on
  all five supported client branches
  (`ChatConstantsDocumentation.lua:151-163` classic_era, `:154-166` forever:
  Success=0, AddonMessageThrottle=3, InvalidChannel=7, ChannelThrottle=8, among
  others) — and the classic-family legacy global's nil return, which counts as
  `sendNoInfo` rather than an error. A throttle refusal leaves the item queued
  with no token spent, so the message goes out on the next window; the
  pre-Stage-1 code popped the item and the message was lost forever.
- **The hidden channel has a proof state machine.** A joined channel id is no
  longer treated as "carries": a one-line probe (`P;<n>`, ignored by peers)
  is sent before the channel is trusted, `InvalidChannel` or sustained
  throttle strikes mark it dead and every send site stops aiming at it
  (including a digest or broadcast mid-flight), and a dead channel re-probes
  on its own after 120 seconds. More transports ride the same bucket: group
  broadcasts pick INSTANCE_CHAT inside a raid/pvp/arena instance instead of
  RAID, where the raid channel is partitioned.
- **A dead-transport query is a counted silent skip.** When a query's own
  transport cannot carry an answer (a dead or unjoined channel, or a query
  naming a group the client is no longer in), nothing is sent on any
  transport and the `answerNoTransport` outcome bucket counts it for
  `/ttgsdebug`. There is no whisper path anywhere: a background sync must
  never print user-visible chat noise, so dead-transport queries stay
  observable without sending anything — not even an answer to a WHISPER
  query, which would itself be a user-visible whisper event.
- **A 240-byte enqueue door.** An addon message dies at 255 bytes engine-side
  and the audit measured 319-byte digests against Stage-2 field plans
  (§3.2), so enqueue refuses anything over 240 instead of queueing an
  unsendable item ahead of real traffic. An over-long two-record digest pair
  splits into two single-record messages — the split initially dropped the
  second member entirely, which the harness check caught, so both halves
  travel. Inbound request ids are clamped to eight characters at the door;
  outgoing ids are fixed-width six, so no id rides a response whole.
- **Send-outcome counters are visible in `/ttgsdebug`** — send buckets
  (success/no-info/throttle/channel-throttle/invalid-channel/error/other),
  requeued count, probe count, the one-per-session self re-broadcast, the
  counted silent skips (dead-transport answers, version rejects,
  foreign-realm scan skips), and the channel state/id/strike counters as a
  snapshot.
- **The first-login hole is closed.** A broadcast that runs while the channel
  cannot carry arms a once-per-session memory; the moment the probe proves
  the channel carries, the local record goes out on it exactly once — peers
  who log in later finally learn about players who never re-geared.

The offline harness pins every one of these: same-transport answers, refused-send
counting and re-queue, probe/dead/re-probe timings, the once-per-session
re-broadcast, counted silent skips on dead-transport and WHISPER queries with
zero sends asserted on every transport, the 240-byte door and the two-single
split, and the eight-character inbound id cap — each failing against the
pre-Stage-1 behavior it exists to guard. Suite total unchanged in invocations,
green on Lua 5.1, Lua 5.4 and LuaJIT: 42 invocations, 42 passed;
`LINT=1` luacheck reports 0 warnings / 0 errors.

### Leaderboard feedback (browser Tier A)

- **The empty window says why it is empty.** The single empty-state line now
  distinguishes the situations it ran together. No records in the database
  reads `LB_EMPTY` ("No records yet. Scores sync while you play."); filters
  matching nobody keep the no-match message; a realm database holding only
  your own character reads `LB_ONLY_YOU`. All ten non-English locales
  translated these keys long ago — `LB_EMPTY`, `LB_ONLY_YOU` and
  `LB_NOT_ESTABLISHED` were simply never read until now.
- **Clicking the active sort header flips its direction.** Every column still
  opens descending — the order it always shipped with — and a repeat click on
  the same header reverses it; switching columns resets to descending. The
  "Sorted by" hint reports the direction the list actually faces, and the `#`
  column stays the GearScore rank in either direction, never a row position.
- **Row tooltips end with "Click to view gear"** — the `LB_TIP_CLICK_GEAR`
  key, translated in all eleven locales — so opening the gear panel is
  stated rather than discovered by accident.
- **"My Rank" tells you when there is nothing to jump to.** It used to land
  silently on row 1 for a character with no record, which read as a broken
  button. The footer now shows the previously dead `LB_NOT_ESTABLISHED` key
  ("Not ranked yet") in the brand colour, restored after a couple of seconds
  where timers exist (with a stale-token guard so a late timer cannot wipe a
  newer notice); a successful jump clears it, and a client without `C_Timer`
  simply keeps the note until the next repaint instead of erroring.
- **Class names are localized** in the class-filter dropdown and in the Spec
  column (`L["CLASS_"..token] or token`): "Mage", not "MAGE". Every locale
  now also carries `CLASS_EVOKER` — deDE "Rufer", frFR "Évocateur", esES/esMX
  "Evocador", itIT "Evocatore", koKR "기원사", ptBR "Evocador", ruRU
  "Пробудитель", zhCN "唤魔师", zhTW "喚能師" — so no class falls back to its
  raw token. Dropdown entries also carry the canonical
  UIDropDownMenu `value` field, so a selection is trackable apart from its
  displayed language.
- **A finished scan says so.** When the scanner's progress edge goes
  active→inactive, the browser shows "Scan complete - N players tracked"
  above the progress bar — N is the pool size the footer reports, so the two
  lines cannot disagree — through the `LB_SCAN_COMPLETE` key, translated in
  all eleven locales, and plays `SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON`
  behind `PlaySound`/`SOUNDKIT` guards: a client without the sound system
  degrades to the text alone, never an error. The line hides itself after a
  few seconds where timers exist, and the next scan clears it.
- **The sort arrows are arrows.** The sort-hint triangles shipped as
  `\226\152\148` / `\226\152\145` — codepoints U+2614 ☔ and U+2611 ☑, a byte
  slip of the intended triangles that said "UTF-8 triangles" in the comment
  above them and escaped every surviving review because the sort assertions
  are byte-agnostic. They now carry `\226\150\188` / `\226\150\178` (`▼` / `▲`),
  matching `LB_TOP` / `LB_MY_RANK_ARROW` in `enUS` — the ten translated locale
  files still carry a third byte sequence (`\226\152\160`) for `LB_TOP`, which
  is a separate defect from the sort hint and is not fixed here.

The focused leaderboard harness grew from 80 to 136 checks at the time, and the
later Stage-3/4 display pins and the Batch-7 label pins grew it further. It loads
`Locale/enUS.lua` before the browser, mirroring TOC order, so it pins resolved
strings rather than tokens: the three empty-state texts; the direction flip
and its hint arrow with the `#`-column invariant re-checked in both
directions; the tooltip hint; My-Rank-with-no-record with and without
`C_Timer`; the localized dropdown and Spec-column names with the localized
EVOKER name; and the scan-complete edge — status text, pool count, exactly one
sound per edge, and the guarded no-sound and no-timer degradations. The
engine-resolved spec name/icon/colour from numeric ids, the stored fallbacks,
the silent engine-absence path, and the faction-line omission are pinned
alongside, and the main harness pins the locale layer: TOC ships 11 locale
files, no locale defines a key enUS does not, translations preserve `%d`/`%s`
counts, and each translation differs from English on the probe keys.

### Storage hygiene (Stage 2)

- **A once-per-session login sweep walks every realm key.** The first
  `PLAYER_ENTERING_WORLD` handler that actually runs schedules
  `RankDB.PruneAllRealms` through `C_Timer.After(0)` — deferred out of the
  loading screen — with the once-arm set by the first callback that
  executes, and a client whose `C_Timer` callback never executes retries on
  the next rise instead of burning the once (audit §6.2 Stage 2 item 1). The
  pass prunes stale rows under the existing 60-day / `MAX_CAPACITY` rules,
  then deletes realm keys it emptied and any non-table junk key it finds.
- **Capping is amortized bookkeeping, not a full-table scan per insert** (the
  audit measured 21.5 ms/insert at the cap — item 2). A per-realm row
  counter, seeded lazily once per session with a single `pairs()` walk,
  decides when the cap bites, and a lazily built smallest-first heap of
  `{timestamp, guid}` candidates picks the evictee: oldest timestamp first,
  guid as the tiebreak, and the popped candidate is validated against the
  live row before it leaves — a forward-replaced row re-files with its live
  timestamp instead of evicting newer data, and a row that already left
  through a prune or purge is skipped. The visible contract is untouched:
  exactly `MAX_CAPACITY` rows at the cap, evictions strictly
  oldest-timestamp-first, and the reported count always equals the visible
  set.
- **New rows write the render keys and stop writing the dead weight (item 3).**
  `classID` and `specID` are stored as floored non-negative numbers (0 when
  unknown; `specID` capped at 9999, so the validator-max row has a true
  maximum) — they are what the browser derives the class token, colours and
  spec identity from at render — while `source` and `specIcon` stay unwritten
  (audit §2.2 dead weight). Reads stay tolerant: pre-hygiene rows keep every
  field they carry, keep ranking, and fall back to their stored class and
  spec-name strings where the ids are absent; inbound records carrying the
  dead fields are still accepted, the values simply ignored.
- **Records know no realm; everything files locally (item 4).** The wire
  carries no realm (Classic/Forever traffic is single-realm; only Retail is
  multi-realm, and realm-on-the-wire churned the tests for nothing), and
  inbound sync records file under the receiver's own realm table through the
  default routing — no wire realm is parsed, no record arrives with one, and
  no explicit-realm routing redirects anything. Per-realm DB keying is
  unchanged (the tables, the login prune and the cap all still work
  per-realm), and `StoreRecord`'s explicit realm argument still names a table
  for direct callers. The scan-time gate is unchanged too: a scanned player
  the client positively identifies as foreign (`UnitIsSameServer` == false
  through a `UnitTokenFromGUID` unit) skips the store, counted as
  `scanForeignRealm` for `/ttgsdebug`; anything undecidable still files,
  keeping the existing behaviour. Faction is storage-only and optional
  alongside it: only a positive Alliance/Horde verdict from the local scan
  (`UnitFactionGroup`) is kept, anything else stores as nil, and the row
  tooltip renders the faction line only when present.
- **`SAVED_VARIABLES_TOO_LARGE` finally gets a reaction (item 5; event
  payload per AddOnsDocumentation.lua:389 classic / :412 live).** For our
  own add-on name only, an aggressive prune runs — 7 days / `MAX_CAPACITY
  /2` (`PruneAggressive`) — deleting realm keys it empties, and it re-arms
  on every occurrence, because the failing write must stop being too large
  before the NEXT logout.

The load harness pins all five items with 39 named checks — the login
prune's window, key deletion (emptied realms and non-table junk keys) and
once-per-session arm; the cap's oldest-first eviction (timestamp ties break
by guid), forward-replace re-file and the count identity
through replacements, re-crossings and a wholesale prune; the versioned
wire stride with its old-format refusals and counted version rejects, the
local filing of every inbound record and the counted foreign-realm skips;
the render-key writes with legacy-row tolerance; and the `TOO_LARGE`
window, foreign-add-on refusal and re-armability — each failing against the
pre-Stage-2 behavior it exists to guard. Suite green on
Lua 5.1, Lua 5.4 and LuaJIT: 42 invocations, 42 passed, 403 checks on the
flagship era profile (414 on retail/forever); `LINT=1` luacheck reports
0 warnings / 0 errors.

### Wire diet (versioned stride)

Pre-release, once: the stride is versioned and the wire is on a diet.

- **One versioned stride: `R;1;guid;name;classID;gs;ilvl;timestamp;specID`.**
  Nine fields under an explicit `1` token. A record that does not carry this
  client's version — the ten-field pre-Stage-2 stride, the eleven-field
  Stage-2 stride, or any unknown future token — is refused cleanly, never
  raised, and counted as `versionReject` for `/ttgsdebug`. There are no
  compat shims: the wire is pre-release, so old payloads simply do not parse.
- **Off the wire: faction, realm, the class-name string, the spec-name
  string, and the whisper path.** Faction is storage-only and optional
  (a positive Alliance/Horde verdict from the local scan, nil otherwise);
  the realm never leaves the sender because inbound records always file
  under the receiver's own realm; the class token derives from `classID` at
  ingest through a static id→token map, so the string would be redundant
  bytes in every record. And the whisper fallback the Stage-1 work shipped
  is deleted end to end — send path, sender resolver, request ring, call
  site, debug counters, harness pins and this changelog's old subsection —
  replaced by the counted silent skip above.
- **Spec rides as a numeric id, empty when unknown.** The icon and the
  localized name derive at render through the engine's
  `GetSpecializationInfoByID` (a global on all five branches, verified in
  `SharedXML/UnitUtil.lua` on each), feature-detected with a pcall so a
  client without it degrades silently to the stored spec name, then the
  localized class name. No German client ever publishes "Elementar" to an
  English leaderboard again.
- **Measured savings (real serializer, standalone):** a typical record
  drops from 75 to 48 bytes (-36%), an S frame from 84 to 57; a
  validator-max record drops from 400 to 227 bytes, so even the largest
  sanitized row now fits the 240-byte door as a 236-byte S instead of being
  refused at enqueue. A two-record digest pair lands near 109 bytes —
  comfortably inside the door that used to need the split.
- **Storage reads stay tolerant of legacy rows.** Pre-hygiene rows keep
  every field they carry and rank through the same bookkeeping; the browser
  prefers the ids and falls back to the stored strings line by line — the
  faction line renders only when present, the spec column resolves
  engine → stored → localized class, and a missing icon hides the texture
  instead of drawing a broken box.

The harness pins the diet directly: the exact nine-field layout asserted
byte-for-byte, class-token derivation from `classID`, numeric `specID`
round-trips, faction/realm/spec-name absence on the wire, old-stride and
unknown-version refusals with their counted bucket, local filing of every
inbound record, and the render fallbacks (engine-resolved name/icon/colour,
stored fallbacks, silent engine absence, faction-line omission) in the
focused browser suite — each failing against the pre-diet behavior it
exists to guard.

### Cheap expanded fields (Stage 3)

Pre-release, once: the versioned stride grows from 9 to 13 fields.

- **One versioned stride: `R;2;guid;name;classID;gs;ilvl;timestamp;specID;guild;level;pvpRank;arena`.**
  Four fields appended and the version bumped from diet `"1"` — the
  version-gate refusal both ends already enforce (`versionReject`) makes this
  a clean break, never a dual-stride negotiation. Any diet-`"1"` payload is
  now refused and counted exactly like the older strides before it.
- **Guild is the expensive field, so it is capped, not just carried.**
  Sanitized like every other string field (a `";"` would shift the stride),
  hard-truncated to 24 chars, `""` when unknown — never `"Unknown"`-filled,
  which would be 7 bytes of noise a filter then has to special-case. Empty
  guild is data (unguilded), not absence: the positional parser keeps empty
  fields. Typical record ≈85 bytes (diet ≈70); a two-record digest pair lands
  near 180, inside the 240-byte door that needed the split. Validator-max
  rows (64-char name, 24-char guild, 128-char guid) still exceed the door even
  singly — handled, not prevented: the Stage-1 split degrades a fat pair into
  singles and the enqueue door refuses anything still over 240, counted as
  `enqueueOversize`. No new size path was added around either one.
- **Spec rides the existing numeric `specID` — no new wire field for it.**
  Stage 3 fills it honestly at capture (the engine's group-aware
  `C_SpecializationInfo.GetSpecialization` form, then
  `GetInspectSpecialization` for inspect targets, both pcall-guarded) and
  keeps localizing it at render through `GetSpecializationInfoByID`.
  Classic-family clients resolve nothing useful here, so the positive-number
  value test stores `0` rather than inventing an encoding (open question Q3
  stays open). Never derived by string-matching the localized name.
- **PvP is a per-client snapshot with the record's own timestamp.**
  Classic Era fills `pvpRank` with the honor rank number when honor data is
  already present at scan-complete time (never stalls the scan); TBC/Wrath
  fills `arena` with the best inspectable rating across brackets (max of team
  and teamless paths) under the same presence gate. Retail/Forever wire both
  fields `0`, always, detected by the modern rated-inspect surface
  (`C_PaperDollInfo.GetInspectRatedBGData`) rather than by client identity —
  and the browser never renders synced PvP there. No separate PvP timestamp:
  the 60-day prune bounds its worst age, and it rides the record on change
  only, never in the digest preference.
- **Storage stays inside the §6.3 budget.** Per-record growth over the diet
  shape is ≈75–105 bytes file-side (field names plus values) against the
  ≈6 MiB `ranks` target; no new machinery (count cap, age prune, aggressive
  prune all unchanged). Old rows default additively (`""`/`0`), render
  blanks, and converge on refresh-or-prune — never a rewrite pass.
- **Browser: guild text filter, level column + sort, advisory PvP lines.**
  A second text input beside the search box narrows on guild substring
  (case-insensitive plain find); no level filter control, only the column
  (narrow, blank when unknown) with flips through the existing sortable-column
  machinery while `#` stays the GearScore rank both ways. The row tooltip
  gains the guild line and the PvP lines (Era/TBC/Wrath: engine-localized
  rank name or raw number, raw arena best — muted, never styled as
  authoritative as GS). No guild column: the control row is already full, and
  the filter plus the tooltip carry the visibility.

The harness pins all of it with twenty-eight named checks — the R2 thirteen-field
round-trip, the diet-`"1"` refusal with its counted bucket against R2
acceptance, the typical-pair-inside-240 and the validator-max
split-or-refuse (both failing pre-Stage-3 on the missing guild, not the
size), guild truncation with empty-stays-empty, the R2-fed specID-0
fallback and nonzero localization through the real wire, persistence plus
60-day pruning of the new fields, old-row blank defaults, the guild filter
narrowing beside the surviving unguilded rows, the level column with its
sort flip and `#` invariant, the modern-surface suppression of synced
arena beside the classic-surface render, and the `/ttgsdebug` snapshot
still enumerating after the stride change — each failing against the
pre-Stage-3 behavior it exists to guard. Suite green on
Lua 5.1, Lua 5.4 and LuaJIT; `LINT=1` luacheck reports 0 warnings / 0 errors.

### Gear on demand (Stage 4)

Pre-release, additive: gear travels only when asked for, never in the record.

- **One query, one-or-more answers: `G;<ver>;<reqID>;<guid>` asks,
  `D;<ver>;<reqID>;<guid>;<t>;<seq>/<of>;<blob>` answers.** The version sits
  in field 2 like every other type, so the diet's `versionReject` gate
  covers gear with no new version bucket; the request id echoes at eight
  characters like every other response. `<t>` is the sender's server-time
  stamp for the gear — the dedup clock (older `D` never overwrites, equal-`t`
  fills only missing slots, a missing `t` stamps 0, which never overwrites an
  existing row but still files when nothing is stored yet).
  The blob packs `slot=itemID` pairs in `REQUIRED_SLOTS` order, empty slots
  omitted, IDs only: a typical full set rides one `D` near 150–195 bytes
  (~45–90 bytes of door headroom past the ~49-byte head), and a
  validator-long answer chunks at pair boundaries, greediest-first, each
  chunk with full framing inside 240.
  `of` caps at 4 (a full set needs at most two); anything past it is refused
  and counted, never truncated. No links, enchants, gems, names or stats ever
  ride; no compression (measured 57% on the blob alone — not worth a new
  dependency against a door plus chunking that already bounds the worst
  case).
- **Same transport, counted silence, no whisper anywhere.** A `D` answers
  only through the existing `answerForQuery` (GUILD→GUILD, PARTY→PARTY,
  CHANNEL only while the probe says it carries); a dead transport reuses the
  counted `answerNoTransport` skip — the failure the dead-channel check pins
  with zero sends asserted on every transport. Old clients ignore `G`/`D`
  by first byte, like the probe before them; no compat shim, the wire is
  pre-release.
- **Session truth answers; persistence is a bounded fallback.**
  The owner answers from the live `Scanner` revision, a peer only from a
  fresh remote entry — missing, pending, unavailable or expired sends
  nothing and counts `gearNoData`, never a guess. The receiver files every
  chunk into `TacoTipExtrasDB.gear` (`[realm][guid] = {t, ids}`), created
  lazily, capped at 2,000 rows per realm plus the same 60-day age prune as
  ranks (~0.3 MiB, inside the 0.5 MiB gear budget; the aggressive
  `SAVED_VARIABLES_TOO_LARGE` pass arrives as 7 days / 1,000 rows, so gear
  halves before ranks do). Count eviction is a plain pairs-count at prune
  time — no heap, no coupling to the rank bookkeeping — and the owner's own
  guid is exempt from it (re-persisted on every own scan) but never from the
  age prune. Emptied realm keys are deleted, never orphaned.
- **One G storm cannot starve rank sync.** Gear shares the bucket, the queue
  and the token spend — no second bucket, no direct enqueue from the query
  path. Flood control is per sender (a 64-entry ring, same 20-second value
  as the query gate: a repeat from the same sender inside the window
  coalesces and counts `gearCoalesced`, a different sender is never
  suppressed by another's); the shared query gate is deliberately not armed
  by gear answers, so rank `S`/`T` keeps its FIFO priority. When one `G`
  triggers both, the own-record `S` enqueues before any `D` chunk. A full
  queue drops the gear answer's `S` and every `D` chunk (counted at the door
  bucket), never the probe and never by evicting older traffic.
- **The panel renders fresh, then persisted, then honest.**
  A fresh session entry renders exactly as before; otherwise persisted IDs
  render dimmed (`|cff808080`) as `item:<id>` literals with a "Last synced
  … (item IDs only)" note — English with the existing relative-time
  fallback, zero new locale keys — and only when neither exists does the
  `GEAR_NOT_SCANNED` note appear. The session leg resolves names at display
  through the existing async item path where the client offers it; the
  persisted leg renders `item:<id>` literals only, never names from storage;
  no GS is ever recomputed from synced IDs.

The harness pins all of it with thirty-nine named checks — the owned-guid
single-`D` on GUILD with its byte shape and `S`-before-`D` order, the PARTY
same-transport answer, the dead-channel counted skip with no whisper on any
transport, the unknown-version refusal on both types, the unknown-guid
`gearNoData` and empty-guid `gearBadGuid` silences, the validator-long
`1/2 + 2/2` split with disjoint ordered halves under the door, the
four-chunk-cap refusal, the stale-`D` preservation beside the newer-`D`
merge, the storm sequence (the query's `S` first, every `D` emitted, the
digest surviving, nothing refused, distinct senders uncoalesced) with the
same-sender triple yielding one `D`, the eight-character `G`-id echo, the
cap/local-exempt/realm-scoping prune, the age prune with orphan-key
deletion, the aggressive halving beside surviving ranks, the same-`t`
chunk-merge reassembly, the five gear buckets beside the surviving old ones
in `/ttgsdebug`, and the panel's three precedence legs with the
`D`-ingest-without-rescan render — each failing against the pre-Stage-4
behavior it exists to guard. Suite green on
Lua 5.1, Lua 5.4 and LuaJIT; `LINT=1` luacheck reports 0 warnings / 0 errors.

### Browser widgets and visuals (Stage 5)

Pre-release, display-only: zero wire bytes — no stride field, no `G`/`D`
grammar change, no version bump, no `RECORD_FIELDS`/`WIRE_VERSION` touch —
and zero persisted bytes per row.

- **Search becomes standard and debounced.** The filter box builds on the
  `SearchBoxTemplate` affordance (magnifier, clear button, instruction text)
  with the current `InputBoxTemplate` construction as the fallback, and
  keystrokes flush through one 0.2 s `C_Timer` debounce instead of a full
  re-sort per keystroke; without `C_Timer` the search renders synchronously,
  exactly as before.
- **Icons and colour resolve at render.** The class dropdown carries a class
  icon per entry and each row name gains a 14px class atlas beside it (the
  existing 14px spec-icon pattern), both through a guarded `GetClassAtlas`
  that hides on failure; the class-colour bar and name colour are untouched.
  The hard-coded colour table is now the last fallback behind
  `CUSTOM_CLASS_COLORS` (type-guarded community convention, never a
  dependency) and the live `RAID_CLASS_COLORS`. Rows highlight with the
  standard `UI-QuestTitleHighlight` texture behind the brand overlay.
- **The browser explains itself.** A muted strip under the control row
  reports pool size, top GearScore and realm-average GearScore from rows
  already in hand (hidden while loading and on an empty pool); rows stamped
  at or after the browser opened carry a 2px brand tick, so sync progress
  reads without re-reading the scan bar.
- **Chrome, density, tooltip line.** The window builds on
  `ButtonFrameTemplate` with the hand-rolled DialogFrame backdrop as the
  pixel-identical fallback (no template child ever assumed); a "Comfortable
  rows" checkbox rebuilds the list at 32px rows (default stays 26px, one
  boolean in the existing settings table). The gear panel appends the slot's
  item level plus enchant/socket dots when rendering from a live session
  revision — resolved at display through `C_Item.GetItemInfo`, never
  persisted, never synced; persisted gear keeps its dimmed ID literals with
  the last-synced note. The unit tooltip gains one trailing muted line, "Rank
  synced: \<relative\>" (only for rows older than the session), covered by
  the render change gate. The earlier "Gear: N/17 slots" count line is gone:
  removed from the tooltip, the locale table, and the harness pins, which now
  assert its absence. `Up`/`Down` moves an entry-anchored focus ring, `Enter` opens that
  row's gear; empty lists no-op.
- **Browser layering, gear empty-state, Era grading.** The leaderboard opens above the Settings canvas (`FULLSCREEN_DIALOG` + top-level, re-applied on rebuild/reopen, still below hover tooltips); the gear panel is a child of the browser at a higher level with a matched opaque backdrop, so it can never slip behind the rows. A panel with no usable gear now says so (`Gear data is unavailable for this player right now. Press Scan now in the leaderboard, then try again.`) instead of rendering blank or `item:0`. Browser grade colors route through the adapter's per-client bracket first (Era 1400 reads Artifact red in the 200 domain, TBC 1400 Superior blue in the 400 domain), falling back to the old relative scale with no adapter.
- **Not shipped.** Virtualized scrolling (`HybridScrollFrame`) stays out by
  default: no measurement shows the fixed-12 list dropping frames, and sort
  cost dominates either way. It ships only on measured realm need.

The harness pins it with seventeen named checks — the search template and
its fallback, class icons with atlas degradation, hover texture with the
player overlay intact, the colour chain with a non-table `CUSTOM` guard,
debounce flush-vs-keystroke with the no-timer sync path, the strip's
empty/pool/top/average states with the `#` invariant, fresh ticks for
session-new rows only, the Stage-3 level/guild `#` invariant across the
direction flip, ButtonFrame construction with fallback rows, the density
rebuild at both heights, session iLvl suffix beside persisted literals with
uncached and unscanned states, session-only dots, the `D`-ingest panel
refresh, tooltip freshness line in every data state, keyboard focus
with entry-anchored re-sort survival, and the `GetDebugState` shape identity
proving display-only stayed display-only — the virtualized-list check
recorded NOT-APPLICABLE with the realm-evidence link. Suite green on
Lua 5.1, Lua 5.4 and LuaJIT; `LINT=1` luacheck reports 0 warnings / 0 errors.

### Batch 7 — the gear panel's hand row named a client global that does not exist

- **The hand slot's label was English in every client and every language.**
  The gear panel labels each row with the CLIENT's own `INVTYPE_*` string, so
  the panel reads in the player's language without this add-on being
  translated. The hand row named `INVTYPE_HANDS` — a name that exists in
  **NONE** of the five supported clients, so that one row always fell back to
  the English literal, in every language, while every other row was localized.

  Verified in the FrameXML mirror (`wow-ui-source`) on all five branches:
  `INVTYPE_HANDS` matches nowhere on `origin/classic_era`,
  `origin/classic_anniversary`, `origin/classic_titan`, `origin/forever` or
  `origin/live`, while `INVTYPE_HAND` is present on every one of them —
  `Interface/AddOns/Blizzard_EncounterJournal/Cata/Blizzard_EncounterJournal.lua:126`
  on classic_era / classic_anniversary / classic_titan / live, and
  `Interface/AddOns/Blizzard_EncounterJournal/Mainline/Blizzard_EncounterJournal.lua:176`
  on forever. The row now names `INVTYPE_HAND` and falls back to `"Hand"`. The
  back slot keeps `INVTYPE_CLOAK`, which exists on all five branches (English
  string "Back"). The comment above the table now cites the five branch names
  and the file:line, replacing the old "classic_era anniversary / titanforge"
  wording.

- **The label path is now pinned.** `RankBrowser.GetSlotRows()` exposes the
  17 slot rows read-only (debug only — no display or behaviour change), and
  the harness defines the client's 15 distinct `INVTYPE_*` globals with
  marker values that are deliberately not a real language: this harness must
  never invent a translation. Three things are asserted — the client's global
  is used when it is present, the English fallback is used when it is absent,
  and every one of the 17 rows names a global the client actually publishes,
  so a typo in one name fails the suite instead of degrading that one row to
  English with nothing to show for it. Revert-to-fail proven on Lua 5.1, Lua
  5.4 and LuaJIT (5 checks red with `INVTYPE_HANDS` restored).

### Mirror citations are now branch-qualified (comments only)

- The strata comment above the browser's placement constants cited two
  branches. `GameMenuFrame` is `toplevel="true" frameStrata="DIALOG"` on
  **all five** branches
  (`Interface/AddOns/Blizzard_GameMenu/Shared/GameMenuFrame.xml:4`, and
  `:7` on `origin/forever`, whose file carries an extra button template), and
  `SettingsPanel` is `toplevel="true" frameStrata="HIGH"` on **all five**
  (`Interface/AddOns/Blizzard_Settings_Shared/Blizzard_SettingsPanel.xml:4` in
  every branch). The ordering chain the comment derives from them is
  unchanged. Comments only — no behaviour change.

### The harness could pass a call it should have rejected (harness-only)

- The MAIN harnesses call `check(name, cond, detail)`; these harnesses call
  `check(cond, label, detail)`. The call shape is identical, so a MAIN-style
  call copied in here is read the other way round — the string name lands in
  the condition slot, where it is truthy, and the call passes **silently**.
  Both `check()` implementations now detect the swapped order (first argument
  a string AND second argument a boolean — a shape no legitimate call has) and
  fail loudly, naming the swap and the shape this harness uses. Pinned by a
  deliberately swapped call that must be rejected and must never count as a
  pass; revert-to-fail proven on Lua 5.1, Lua 5.4 and LuaJIT in both
  harnesses.

### Release packaging and licence notes

- **`THIRD_PARTY_NOTICES.md` described a product that no longer exists.** It
  named "TacoTip GearScore Enhancer", credited the TacoTip dependency to
  `kebabstorm` at version 0.1.4 targeting TacoTip 0.5.1, and linked the slug
  `tacotip-gearscore-talents` rather than the `tacotip-gearscore` the READMEs
  use. The file now names the product **TacoTip Extras** at **1.2.3**, states
  the enforced minimum TacoTip version — **0.8.0**, from
  `MINIMUM_TACOTIP_VERSION` at `TacoTip_Extras/TacoTipAdapter.lua:44` — uses
  the project URL the READMEs use, and carries the same GearScoreTBCClassic
  attribution as the main add-on's notices, with the full required MIT text
  kept verbatim. `LibForeverInspector`, which this add-on reaches through
  TacoTip and does not bundle, is recorded as **UNKNOWN** for both license and
  author — the repository's established posture for a bundled file that states
  neither, not a new claim.
- **The package had no packaging rules and no verification path.** The
  repository root's `.gitattributes` keeps `/TacoTip_Extras/**` out of the
  TacoTip archive — a TacoTip package must never carry a second `.toc` — but
  the Extras subtree itself had none, so a naive package would have shipped
  `Tests/`, the luacheck config and the marketing PNGs. `TacoTip_Extras/.gitattributes`
  now excludes `/Tests/**`, `/.luacheckrc` and the PNGs and keeps `tt-2.tga`,
  which the TOC's `## IconTexture` points at. `Tools/verify_release_extras.sh`
  builds the Extras archive and asserts exactly one `.toc`, the 23 runtime
  `.lua` the TOC lists, all 11 `Locale/*.lua`, the icon, and
  README/CHANGELOG/LICENSE/THIRD_PARTY_NOTICES — and nothing else.
- **Verified:** `bash Tools/verify_release_extras.sh` → **PASS** — 29 files
  from HEAD, one `.toc`, 23 TOC-listed runtime files, 11 locales, the icon, the
  four documents, nothing else. `bash TacoTip_Extras/Tests/harness/run_all.sh`
  → **42 invocations: 42 passed, 0 failed**.

### Publish-readiness fixes (companion review)

Six defects the final review raised on the companion, all fixed in this
section. Each is pinned in the offline harness and each pin was reverted to
confirm it fails, then restored.

- **The level-70 rule is now the user's setting, not a hard-wired default.**
  `Scoring.Evaluate(revision, policy)` takes a policy, and **no production call
  site passed one**, so the scorer's own internal default — "restricted to
  level 70" — applied to every player on every client
  (`Scoring.lua:687-737`). The Options checkbox only flipped the *render*
  gate, so unchecking it made Potential GS / Delta / Completion read
  "Unavailable" instead of showing a value; on Classic Era and WoW Forever
  (level cap 60) the three metrics never appeared for anybody at all.
  `Core.GetEnhancementPolicy()` (`Core.lua:377-406`) is now the single place
  that reads the setting and hands it to the scorer, both scan call sites pass
  it (`Scanner.lua:801`, `Scanner.lua:994`), a **nil** policy is an explicit
  failure with a named reason instead of a silent restriction
  (`Scoring.lua:687-706`), and the result records the policy it was computed
  under (`Scoring.lua:772`). Changing the setting re-evaluates the cached
  *revision* — no rescan, no re-inspection — through `Scanner.Reevaluate()`
  (`Scanner.lua:1150-1192`, `Cache.lua:299-337`), driven by the checkbox
  handler (`Options.lua:1199-1225`). The shipped default (on) still restricts
  to level 70.
- **A TacoTip upgrade no longer locks the tooltip takeover forever.** The
  recovery journal's identity *was* the capability fingerprint, and the
  fingerprint contains the TacoTip version (`TacoTipAdapter.lua:573-593` in
  the pre-fix file), so upgrading TacoTip changed the fingerprint, the journal
  left on disk stopped matching, and the adapter latched a conflict that was
  never cleared — `conflictLocked` was set in five places and reset in none.
  Because `/reload` does not fire `PLAYER_LOGOUT`, the journal stayed on disk
  and the Extras tooltip surface stayed dead across every reload, while the
  main add-on's `show_gs_player` (which Extras had forced to `false`) was
  never restored. The journal's identity is now stable — surface, managed
  key and a schema number (`TacoTipAdapter.lua:97`, `:1679-1712`) — with the
  fingerprint kept as a diagnostic only. The recovery is **restorative**: if
  the setting still holds the value Extras forced, the original value is
  restored, the journal is cleared and the takeover resumes
  (`TacoTipAdapter.lua:1726-1795`); a setting the user changed themselves is
  left alone and the takeover is refused. A conflict is re-evaluated whenever
  the configuration is re-read (`TacoTipAdapter.lua:1844-1866`), and the
  reason is stated in chat exactly once per session
  (`TacoTipAdapter.lua:1647-1672`) so the state is never silent.
- **The persisted gear table is capped at insert, not only at the next
  prune.** `TacoTipExtrasDB.gear` had a documented 2,000-row-per-realm cap
  that only the prune pass enforced (login, or the
  `SAVED_VARIABLES_TOO_LARGE` response), so between two prunes the table grew
  without bound — every inbound answer added a row — in the very file the
  client writes synchronously at logout. The cap is now enforced at insert,
  with the same amortized count and lazy oldest-first heap the rank table
  uses (`RankDB.lua:766-802`, `:985-1060`).
- **Inbound queries are rate limited.** A query is a broadcast: every client
  on the channel heard it and answered it through a jittered timer, one timer
  per inbound payload, with nothing downstream but the send queue's own
  50-message cap — which bounds the *messages*, not the *timers*. A fixed
  window now admits 64 queries per 10 seconds and refuses the rest before any
  timer is scheduled (`RankSync.lua:755-790`, `:1292`, `:1335`), counting each
  refusal in the debug state (`/ttgsdebug`).
- **A remote name can no longer repaint the leaderboard.** The wire carried
  names and guilds with their WoW markup intact, so a remote name containing
  `|cff00ff00` could repaint another player's row, their row tooltip and
  their gear-panel title. The stored text is now sanitised
  (`RankDB.lua:254-272`): the markup and the escape character are removed, so
  what is rendered is the name's own text. The wire format is unchanged.
- **The bundled inspector no longer takes a shared library name by force.**
  It published an alias under the name the original library used, which
  displaced a real `LibClassicInspector` another add-on had already registered
  and downgraded the minor recorded for it
  (`Libs/LibForeverInspector/LibForeverInspector.lua:18-48`). The alias is now
  claimed only when the name is free, or when the entry already there is the
  same library. TacoTip resolves the inspector under its own name, so nothing
  else changed.

**Verified:** `bash TacoTip_Extras/Tests/harness/run_all.sh` → **42
invocations: 42 passed, 0 failed** on Lua 5.1, Lua 5.4 and LuaJIT (14
invocations each: the five-client load matrix, seven variants, and the two
focused leaderboard runs). `cd TacoTip_Extras && luacheck .` → **0 warnings /
0 errors in 26 files**. Every pin above was reverted to fail and restored to
pass; the main add-on's own harness (which loads the bundled inspector) still
reports **70 invocations: 70 passed, 0 failed**.

### The last three HIGHs, the socket capacity, and the release status

The final pre-publish hunt (`bench/audits/2026-10-19-final-hunter.md`) raised
three HIGHs, one socket defect and a handful of cheap ones. All are closed
here. Every pin below was reverted to fail and restored to pass.

- **The ten non-English locales had their format specifiers stripped.** The
  `%` byte was missing from every conversion specifier in `LB_SORTED_BY`,
  `LB_FOOTER_NO_RANK` and `LB_FOOTER_STANDING` in
  `Locale/{deDE,esES,esMX,frFR,itIT,koKR,ptBR,ruRU,zhCN,zhTW}.lua:14,15,20`
  — so `string.format` returned the format string unchanged and the
  leaderboard footer rendered the player's own standing as a literal `#d`,
  with the sort readout as `s s`. The specifiers are restored to enUS's shape
  (`Locale/enUS.lua:211,255-257`), each language keeping its own wording
  around them. The harness now compares the **ordered sequence** of conversion
  specifiers in every locale against enUS's sequence for the same key
  (`Tests/harness/load_test.lua:1683`) and renders the ruRU footer with real
  numbers (`:1698`) — the old check compared the translation against itself
  (`count()` closed over `value`), which is why it stayed green through the
  whole defect. `SORT_LEVEL_DESC` is now present in every locale too
  (`:229`), so the non-English sort readout names its own column.

- **The tooltip driver's `rendering` latch can no longer be stranded.** It was
  set on entry to the render and cleared only on four *normal* returns, so any
  raise in between left it true for the rest of the session and the Extras
  tooltip surface stopped rendering — with no error, no counter and no way
  back short of `/reload`. The latch now lives in a wrapper that xpcalls the
  render body and releases it on every path, including the raising one
  (`Tooltips.lua:1398`; the body is `:1333`). The failure is counted, the
  message is recorded, and the repeat count and the last few suppressed
  messages are kept in a bounded ring — the same shape as the main add-on's
  `handlePipelineError`, mirrored rather than copied (`Tooltips.lua:92-158`).
  The counters ride on `Tooltips.GetDriverState()` (`:1557`).

- **`/ttgsdebug` now prints every diagnostic counter.** They were all
  reachable only from the test harness — the code comments said "surfaced in
  GetDebugState below", and `GetDebugState` was read by nothing outside the
  harness. A counter no user can see is a counter that cannot be acted on: the
  render-latch wedge, a swallowed rank-record raise, a row-tooltip
  truncation, a score-colour fallback and a module that never started were
  all invisible. `/ttgsdebug` now prints a **surfaces** block
  (`Core.lua:730-784`): driver mode, renders, rows and poll ticks; the render
  errors; the rank-record errors; the row-tooltip errors; the score-colour
  fallbacks with their last reason; the cache and scanner listener errors; the
  refused records and the queue evictions; and the initialize-failure list.
  The harness asserts on the **printed text**, against each counter's own
  accessor value (`Tests/harness/load_test.lua:4779`, `:4815`, `:4838`), so
  the surface cannot rot again.

- **The socket capacity comes from the documented API, and the cross-check now
  runs both ways.** The capacity used to be the SUM of the stat table's
  `EMPTY_SOCKET*` values, read out of `GetItemStats`. Those key names are
  ENGINE-side — the FrameXML mirror carries the UI source and the generated
  API documentation, not the engine's stat table — so the mirror could
  neither confirm the names nor say whether the values count socket **slots**
  or socket **empties**. The only evidence for them was the harness's own
  client mock, and that mock wrote a **fixed** `EMPTY_SOCKET1`,
  `EMPTY_SOCKET2`, `EMPTY_SOCKET3` triple for **every** link. A fixed triple
  is not a socket count: it is the same three slots for every item, so a
  one-socket item published **two** empty sockets where the truth is zero, a
  sockless item published **three** where the truth is zero, and the published
  Potential GS, Delta and Completion came out **above what the item
  justified**.

  **Where the number comes from now.** `C_Item.GetItemNumSockets(itemInfo)`,
  in the call shape Blizzard itself uses.
  `Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua:854`
  on `origin/live` (`:876` on `origin/forever`, `:586` on `origin/classic_era`
  and on the same line of `origin/classic_anniversary` and
  `origin/classic_titan`) documents one `itemInfo` argument and one
  `socketCount` return. The generated docs name the argument `itemInfo` — an
  opaque item handle — and do not say how to build one from a link;
  **Blizzard's own code settles that**:
  `Interface/AddOns/Blizzard_UIPanels_Game/Mainline/PaperDollFrame.lua:1728`
  feeds `GetInventoryItemLink("player", ...)` into `SetItem`, and `:2775`
  passes that link **straight** into `C_Item.GetItemNumSockets(item)`. The
  link **is** the `itemInfo` argument, and the add-on already holds it
  (`Scanner.lua:514-552`, `readSocketCapacity`). The sibling API
  `C_Item.GetItemGemID(itemInfo, index)` (`ItemDocumentation.lua:512` on
  `origin/live`, `:534` on `origin/forever`, `:321` on `origin/classic_era`)
  is indexed from **one** over the socket positions — `PaperDollFrame.lua:2777-2780`
  loops `for index, slot in ipairs(self.Slots)` and reads
  `C_Item.GetItemGemID(item, index)` — and it is deliberately **not** used to
  publish a number here, because it answers for the item *template* while the
  add-on's gems come from the **equipped** item's link.

  **The cross-check is bidirectional.** The item's own gem list — parsed from
  the equipped item's link — is still the cross-check, and `Scoring`'s
  `readSocketEvidence` (`Scoring.lua:538-600`) now rejects a capacity that
  contradicts it in **either** direction: **too small** (the capacity cannot
  hold a gem the link reports — the *contradictory*
  `socket-gem-mismatch-N`) and **too large** (the capacity exceeds the three
  gem positions an item link carries — the *contradictory*
  `socket-capacity-exceeds-gem-list`). The old cross-check only ever
  rejected the first, so a count above what the item's gems could account for
  was used as read and could publish a number above what the item justifies.
  A capacity that contradicts the item's gems in either direction now renders
  the socket-based metrics **unavailable, never a number**.

  **The Classic clients are untouched.** The scope gate is still
  `GetItemStats` — a MAINLINE-FAMILY API, documented on `origin/live` and
  `origin/forever` and absent from the whole `Interface` tree of
  `classic_era`, `classic_anniversary` and `classic_titan` — so **Classic
  Era, TBC Anniversary and Titanforge keep their shipped degradation**: the
  empty-socket count, the completion percentage and the potential total are
  omitted rather than guessed. `C_Item.GetItemNumSockets` is documented on
  the Classic branches too, and the gate deliberately **does not** widen to
  it: the Classic clients' behaviour is a published, documented contract, and
  widening it would change published numbers on clients that cannot be
  tested before publish. The harness models that API on **every** client, so
  the Classic degradation is proved to be the **gate's** doing and not an
  accident of the model (`Tests/harness/load_test.lua:2753`, `:2762`).

  **What the numbers are now.** On **Retail and WoW Forever** the capacity is
  the item's own socket count rather than a fixed three, so the empty-socket
  count, Completion and Potential GS change **again** for any item whose
  socket count is not three: a one-socket item with one gem publishes
  **zero** empty sockets where the fixed triple published two, and a
  sockless item publishes **zero** where the fixed triple published three.
  The metrics remain subject to the level-70 display rule, which hides them
  below level 70 while it is on. On the three Classic clients nothing
  changes: the socket path stays absent.

  **What is still unconfirmed.** The mirror confirms the API's *presence*,
  its *argument shape* and its *return shape*; it does not say what a live
  client returns for an item whose template data is not loaded, so the read
  is `pcall`-guarded and a failed or non-integer answer is withheld
  (`socket-capacity-unavailable` / `socket-capacity-invalid`) rather than
  guessed. The `GetItemGemID` per-socket semantics for an equipped link are
  **not** confirmed from the mirror either, which is exactly why they are
  not used to publish a number.

- **The Options panel no longer shows the raw socket-mismatch code.** The
  *too small* branch of the cross-check reports a DYNAMIC reason code — the
  socket position that contradicts the capacity is part of the code itself
  (`socket-gem-mismatch-2`) — so no exact-key label table can hold it, and
  the panel rendered the raw code to the player. The label lookup is now a
  small resolver (`Options.lua:320`): an exact key in `ENHANCEMENT_REASONS`
  still wins, and a code matching the family pattern
  (`Options.lua:314`) resolves to the family sentence, so a new index needs
  no new map entry. The panel reads **"the item's socket count and its gem
  list disagree"**. The index is an internal socket position and is not
  something a player can act on, so the family carries **no digit** and
  **no raw code** in the player-facing line (`Options.lua:1102`); the raw code
  stays exactly where it was — the diagnostic-slot blocker line, which shows it
  for every reason, mapped or not. No other reason changes shape: the
  harness pins a reason outside the family to the exact line it rendered
  before (`Tests/harness/load_test.lua:3272`).

- **The silent counters now count, and the silent failures now speak.**
  A raising listener in the cache or the scanner's fan-out is counted with
  its message (`Cache.lua:111`, `Scanner.lua:165`; accessors at `Cache.lua:346`
  and `Scanner.lua:1309`) — the entry or the state had already been mutated
  when the listener raised, so the update was being lost with nothing said.
  A record the validator refuses is counted with the reason, on both the
  digest and the single-record arm (`RankSync.lua:1278`, `:1307`), where the
  version mismatch on the very same path was already counted. The 50-message
  send-queue cap now counts the eviction and names the kind of message it
  dropped (`RankSync.lua:496`). An incompatible TacoTip is recorded as an
  initialization failure with one chat line naming the adapter's internal
  reason — it refuses by *returning* `false`, which no `pcall` can see
  (`Core.lua:856`, `:907`, `:931`) — and a module that is present but not
  callable is recorded the same way (`Core.lua:880`).

- **The release status in the README was wrong.** The CurseForge listing
  exists and serves **1.2.2**; the front matter said `status: unreleased`,
  pointed `project_url` at the stale `/preview` form, and claimed the add-on
  was "not maintained by the TacoTip author" — stale since 1.2.0 unified the
  authorship on AcidBomb. `README.md:19`, `:25`, `:33`, `:35` and `:190` now
  say `status: released`, point at the live listing, drop that claim, and
  record that the listing exists and serves 1.2.2 while **1.2.3 ships
  alongside TacoTip 0.8.4**. No publication date is claimed for 1.2.3.

**Verified:** `bash TacoTip_Extras/Tests/harness/run_all.sh` → **42
invocations: 42 passed, 0 failed** on Lua 5.1, Lua 5.4 and LuaJIT; the
five-client load matrix and the seven variants run on each interpreter, plus
the two focused leaderboard runs (496 checks on Classic Era, 528 on Retail).
`cd TacoTip_Extras && luacheck .` → **0 warnings / 0 errors in 26 files**.
`bash Tools/verify_release_extras.sh` → **PASS**. Every pin above was
reverted to fail and restored to pass — the locale pin on a stripped `%`, the
latch pin on a stranded latch, and the socket pins on five separate
mutations: the capacity source put back on the stat-table sum (five pins red,
and the Classic clients unchanged), the cross-check's too-large branch
removed, the cross-check's too-small branch removed, the socket accounting
counting every socket as filled, and the `GetItemStats` scope gate removed
(the Classic degradation pin goes red, which is the proof that the gate is
the gate).

---

### Silent-failure audit: nine findings, all fixed

The final silent-failure audit of the 1.2.3 tree returned two findings rated
MEDIUM and seven rated LOW. Every one of them was a path where the add-on
*looked* like it was working and was not. All nine are fixed below, and each
fix is pinned by the offline harness.

#### The gear panel is closed with the browser, and a rebuild cannot leave it
#### showing stale gear

- **Closing the leaderboard now closes the gear panel with it.**
  `RankBrowser.CloseGear` existed and had **no callers at all**. The panel is
  a `SetToplevel(true)` child of the browser, so its visibility rested on an
  engine rule this add-on did not depend on. The browser's hide branch, the
  rebuild and the Escape handler now all go through the one close function,
  so the panel's fate is decided by the add-on and not by frame ordering.
- **A rebuild re-renders the panel from live data.** `RebuildUI` discards the
  browser frame; a panel left open across that swap kept showing the rows it
  had drawn for the frame that no longer existed. The panel is now closed
  before the frame swap and re-rendered after the re-parenting, so what it
  shows afterwards is read again from the Scanner cache and the RankDB gear
  table.

#### A raising scorer is counted and surfaced

- **The level-70 toggle can no longer silently do nothing.** The gate is part
  of the *scored* result, so changing it has to re-run the scorer over the
  cached revision. A scorer that raised left the cached verdict — computed
  under the **old** policy — exactly where it was, and the caller discarded
  even the `pcall`'s boolean: the checkbox flipped, the setting was written,
  the metrics kept the old verdict, and nothing said so. `Scanner.Reevaluate`
  now captures the failure, **counts** it, prints **one line naming it**, and
  returns how many evaluations failed, so the caller stops discarding the
  outcome. The counter is in the `/ttgsdebug` surfaces block
  (`scanner-reevaluate-errors=`).

#### The rest

- **The footer's two buttons no longer overlap.** "Top" (80 wide, anchored
  122 px from the right edge) and "My Rank" (90 wide, anchored 34 px) shared
  2 px of pixels, so which of them a click at that strip reached was a
  matter of frame order. "Top" now sits at 126 px, which leaves a 2 px
  gutter.
- **The tooltip-mode dropdown reads in the player's language.** It was the
  one control the player reads the mode from, and it carried the English
  literals — "Disabled", "Minimal", "Compact", "Detailed" — in every locale.
  The labels now come from the `MODE_*` keys every locale already carries.
  The Character & Inspect summary dropdown, which shares the same words, was
  localized the same way.
- **`LB_COL_LEVEL` and `LB_STAT_STRIP` are translated.** The leaderboard's
  LEVEL column header and its summary strip are read by the live UI in every
  locale, and ten of the eleven locale files did not define them, so those
  two surfaces read English everywhere except enUS. They are now translated
  in all ten, with no English copied into any of them. A new key,
  `LB_DB_UNAVAILABLE`, carries the "the rank database is unavailable" message
  the browser shows when the database is missing.
- **The checkbox hit rect is re-measured on every refresh.** It was measured
  once, at creation: a FontString measured before its font is loaded
  measures zero, so the label stopped being clickable, and a language change
  rewrote the label's text without the measurement being redone. The label
  is now re-read from the locale and re-measured on each refresh, and the
  label's own width is the floor, so an unmeasurable label keeps a clickable
  region instead of losing one.
- **Two Options buttons now say which surface is missing.** "Open Server
  Leaderboard" and "Scan now" guarded their calls and returned in silence, so
  a click did nothing at all with no word anywhere. Both now print one line
  naming the missing module.
- **A missing rank database shows the empty state.** The browser's
  `UpdateUI` returned early when the database was absent, so the window had
  headers, an empty table and no explanation at all. The empty state is now
  published before that return, and it names the missing database.
- **Unticking every tooltip field no longer loses the mode.** The mode was
  forced to "Disabled" on every normalise and nothing remembered what it
  had been, so re-ticking one field left the mode "Disabled" and the tooltip
  showed nothing until the player picked a mode by hand. The rule now lives
  in **one** place (`Core.ApplyTooltipFieldModeRule`, used by the Options
  page and by the settings normalise) and is **recoverable**: the mode the
  player had is remembered and restored as soon as a field comes back. An
  *explicit* "Disabled" the player chose is never mistaken for a forced one.
  The alternative — leaving the mode alone and letting the render gate cope
  with an empty field set — was rejected: the render gate would draw no rows,
  but the add-on would keep holding the player's GearScore, which is the
  half of "Disabled" that matters.

**Verified:** every one of the nine pins was reverted to fail on a copy and
restored to pass. The reds are recorded in the desk journal for the
`fix-extras-final-review` desk.

### Extras maintenance pass

A maintainability audit of both add-ons produced a ranked list of findings.
The Extras side of it is landed here. The items a player can SEE come first;
the rest are internal and change nothing on screen.

- **The "Top" button shows the right triangle in every language.** Ten of the
  eleven locale files spelled the button's ▲ as the wrong bytes, so it read
  "☐ Top" in German, Spanish (both), French, Italian, Korean, Brazilian
  Portuguese, Russian and both Chinese files. The button now shows ▲
  everywhere, and "▼ My Rank" — its sibling on the same row, which was
  already correct — is pinned too, so neither can drift again. The
  triangles are spelled as bytes because Lua 5.1 has no `\u{}` escape, and a
  byte typo does not raise: it renders the wrong character, and every other
  locale check (key present, non-empty, right script, different from
  English) passed with the wrong glyph in place.
- **The localization claim is now honest.** The README said "eleven-locale
  UI", and the Extras does ship eleven locales — but the Options page's
  integration and enhancement status lines, the forty-seven reason sentences
  they expand into, the "Reset summary positions" button label, the "How
  these scores work" heading, the equipment windows' "Drag" handle and the
  gear panel's "Last synced …" note are still written in English in the
  source. The README now names exactly what IS translated and lists those
  strings as a known limitation. Localizing them is a separate translation
  pass, not a code change.
- **Thirty-eight locale keys that nothing ever read are gone.** The `OPT_*`
  and `SECTION_*` families, the `INTEGRATION_*` and `REMOTE_*` status
  strings, the Options page's tab labels and the old `BLANK`, `LB_MY_RANK`
  and `LB_TIP_CLASSRANK` keys were translated into all eleven languages and
  then never read by a single code path — the text they were written for is
  hardcoded English in the sources. They have been removed from all eleven
  files. The harness now proves two things that were previously invisible:
  every locale file defines the *identical* key set (so a locale can no
  longer quietly lose a translation and read English instead), and every
  remaining key is read somewhere in the add-on.
- **Five keys enUS defined and the other ten locales did not are now
  translated.** The guild column label, the PvP rank and arena lines in a
  row's hover tooltip, the "rank synced" line and the "gear data is
  unavailable" note had been added to the English file alone, so they read
  English in every other language. They are now translated in all ten.
- **Escape closes the gear panel and leaves the leaderboard up, and the
  source now says so.** The gear panel used to call the escape registration
  as if it had "the same three-route registration the browser uses", while
  the registration had already been taken by the browser and the call did
  nothing. The call is gone and the comment now describes the real
  mechanism: the browser owns the escape routes, and its handler closes the
  gear panel first and the browser second. The panel is also no longer put
  into the engine's special-frames list, where the engine could have hidden
  it and taken the browser down with it. The behaviour a player sees is
  unchanged, and is now pinned.
- **The class colour is resolved in one place.** The tooltip, the
  character/inspect summary and the leaderboard row each ran their own copy
  of the colour chain, and the copies had already drifted: the leaderboard
  took any numeric colour a community add-on published, while the other two
  refused one outside 0..1. The chain now lives in `Core.GetClassColor`;
  each surface keeps its own acceptance rule and its own fallback, so **no
  colour changes on screen** — a class the client does not know still reads
  the leaderboard's own colour in the row and neutral grey in the tooltip,
  exactly as before.
- **The gear panel's row geometry is named instead of repeated.** The row
  positions and the two enhancement dots on each row used the same
  arithmetic written out twice, twelve lines apart, with the panel's own
  sizes as loose numbers in the middle of the construction. Every value is
  now a named constant and both the rows and the dots are computed from the
  same one. **Every pixel is unchanged.**
- **Two identical functions became one.** The "fresh profile" and "migrated
  profile" equipment-summary defaults were byte-identical under two names
  that promised a distinction the bodies did not make. There is one
  function and one set of defaults: Detailed, Unenhanced GS off, positions
  locked.
- **The harness models the client's template title.** The client publishes
  the ButtonFrame template's own title as `TacoTipRankFrameTitleText`, and
  the add-on reuses it and draws no title of its own — which collapses the
  window's 34-pixel title band to zero. The harness never modelled that
  global, so it graded a window one title band taller than the real client
  ever produces. The mock now publishes it, and the collapsed band is
  pinned. The mirror citations for all five client branches are in the
  harness.

**Verified:** the Extras harness passes 42/42 invocations across lua5.1,
lua5.4 and luajit, `luacheck` reports 0 warnings and 0 errors across 26
files, and `Tools/verify_release_extras.sh` passes. The new pins — the
triangle bytes, the identical key sets, the every-key-is-read rule, the
shared colour chain, the collapsed title band and the Escape behaviour —
were each reverted to fail and restored to pass.

### The debug snapshot is reachable from the main add-on

- **The `/ttgsdebug` snapshot is published on a plain global.**
  `_G.TacoTipExtrasPrintDebugSnapshot` is the same function object the
  `/ttgsdebug` command invokes — identity, not a copy — so the two can never
  drift apart. The client's slash-command table is a proxy that is emptied
  immediately before a command is dispatched (`ChatFrameSetup.lua:3-11` proxies
  it, `ChatFrameUtil.lua`'s `ImportListToHash` moves every handler into the
  proxy and wipes the real table, and `ChatFrameEditBox.lua:245, 257` imports
  and dispatches in that order), so another add-on cannot read this handler
  back out of `SlashCmdList`; the main add-on's `/tt` calls this global
  instead. **What the snapshot prints is unchanged**, and `/ttgsdebug` still
  works on its own.

---

### Final hardening pass — the bounded callbacks and the counted options actions

Defensive only. No feature, no refactor, no rename, and **no behaviour change
for a valid state**: every change below fires only where the add-on previously
did something silently.

- **Every callback the Extras registers on a Blizzard frame or on a Blizzard
  function is now bounded.** Eleven callbacks were registered raw: the
  character pane's `OnShow` / `OnHide` / `OnSizeChanged`
  (`TacoTip_Extras/Frames.lua:1335`), the inspect pane's four frame hooks
  (`Frames.lua:1384`) and the three `hooksecurefunc` post-hooks on
  `InspectFrame_Show` / `InspectFrame_UnitChanged` / `InspectSwitchTabs`
  (`Frames.lua:1401`). A raise inside a `HookScript` handler or a
  `hooksecurefunc` post-hook does **not** stay inside this add-on: it
  unwinds through the **client's own** frame script, so the rest of
  Blizzard's handler for that frame never runs — the character or inspect
  pane is left half drawn, with nothing in the add-on's own diagnostics.
  Each callback is now wrapped, the raise is caught at the boundary, counted
  (`TT.ev` → `Frames.GetDebugState().hookCallbackErrors`) and named
  (`lastHookCallbackError`).
- **The Options page no longer has silent no-ops.** "Comfortable rows" and
  "Shaman Blue" wrote their setting and then **discarded the result** of
  `RankBrowser.RebuildUI`, so a raising rebuild left the player with a ticked
  box, an unchanged window, and no message and no count. The result is
  captured now; a failure is counted
  (`Options.GetDebugState().actionFailures`), the reason is kept, and the
  player is told in one plain chat line. The same boundary now covers the
  "Open Server Leaderboard" and "Scan now" buttons, the "Reset enhancer
  settings", "Restore TacoTip settings" and "Reset summary positions"
  buttons — every one of them used to be able to do nothing at all, or to
  abort with a raise that was never counted.
- **`/ttgsdebug` prints the new counters** in the surfaces block:
  `frame-hook-errors=` with `last-frame-hook-error=`, and
  `options-action-failures=` with `last-options-action-failure=`. A counter
  no user can see is a counter that cannot be acted on.
- **Pins** (all revert-to-fail proven on copies; the working tree was never
  reverted): `TacoTip_Extras/Tests/harness/load_test.lua` — an injected
  raise inside the character pane's `OnSizeChanged` hook reaches the hooked
  callback, does **not** escape into the client, is counted, and has its
  error named; a raising `RankBrowser.RebuildUI` does not escape the
  checkbox, is counted, is named, and produces the one chat line the player
  reads; the `/ttgsdebug surfaces` block prints both new counters with
  their live values and both new "last reason" companions.


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
