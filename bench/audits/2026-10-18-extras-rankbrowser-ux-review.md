# TacoTip_Extras RankBrowser — UI/UX review (read-only audit)

Date: 2026-10-18
Scope: read-only analysis of the server leaderboard window (`TacoTip_Extras/RankBrowser.lua`),
its tests, entry points, screenshots, and branch-verified Blizzard widget candidates.
Only this report file was written. Evidence labels per `CAIRN.md`: VERIFIED / ASSUMED / UNKNOWN.

Blizzard branch mapping used (matches the operator's brief; repo TOC confirms the five
interfaces — `TacoTip_Extras.toc:1` = `11509, 20506, 38002, 16001, 120105`, VERIFIED):

| branch | client | interface |
|---|---|---|
| origin/classic_era | Classic Era | 11509 |
| origin/classic_anniversary | TBC Anniversary | 20506 |
| origin/classic_titan | Titanforge | 38002 |
| origin/forever | WoW Forever | 16001 |
| origin/live | Retail | 120105 |

Harness state at time of review (run just now, both green):
`lua5.1 rankbrowser_test.lua` → 80 checks, 0 failed; `lua5.1 load_test.lua classic_era ok` → 270 checks, 0 failed (VERIFIED).

Libs situation (checked against TOCs, as instructed): the vendored `Libs/` tree at the repo
root is loaded only by the **main** `TacoTip.toc:11-14` (LibStub, CallbackHandler, LibDetours,
LibForeverInspector). `TacoTip_Extras.toc` (lines 11–34) loads **no** library files (VERIFIED).
Any proposal below that implies "add a library" is forbidden for Extras.

---

## 1. Current inventory (all VERIFIED from source unless noted)

### 1.1 Widget tree — main window `TacoTipRankFrame`

Created lazily in `RankBrowser.CreateUI` (`RankBrowser.lua:911-1181`); 720×520, centered,
movable, clamped (`RankBrowser.lua:22-31`, `921-928`), strata DIALOG raised on Toggle
(`RankBrowser.lua:1272-1280`).

| widget | how | cite |
|---|---|---|
| Backdrop | `BackdropTemplate` via pcall, fallback bare Frame; `SetBackdrop` DialogFrame skin guarded | `RankBrowser.lua:916-939` |
| Title | `GameFontNormalLarge` FontString, `LB_TITLE` | `RankBrowser.lua:942-944`; key `enUS.lua:197` |
| Close | `UIPanelCloseButton` | `RankBrowser.lua:946-947` |
| Scope label "Whole Realm" + brand underline | FontString `GameFontHighlightSmall` + 2px brand texture | `RankBrowser.lua:952-961` |
| Search | `InputBoxTemplate` EditBox 180×22, live `OnTextChanged` filter | `RankBrowser.lua:964-976` |
| Class filter | `UIDropDownMenuTemplate` (`TacoTipRankClassFilter`), 14 entries (All + 13 classes from `CLASS_ORDER`) | `RankBrowser.lua:979-1004`, order `73-77` |
| Column headers | sortable columns (`gs`, `ilvl`, `seen`) are `UIPanelButtonTemplate` buttons with brand-underline highlight; `rank`/`name`/`spec` are `GameFontDisableSmall`/plain FontStrings; built from the shared `COLUMNS` table | `COLUMNS` `45-52`; build `1009-1058` |
| Sort hint | one-line "Sorted by %s ▲/▼" FontString (`GameFontDisableSmall`), UTF-8 arrows spelled as bytes | `RankBrowser.lua:219-220`, `895-901`, `1063-1065` |
| Separator | 1px white 0.15 texture | `RankBrowser.lua:1068-1072` |
| List | `FauxScrollFrameTemplate` ScrollFrame; 12 fixed row Buttons (`NUM_ROWS=12`, `ROW_HEIGHT=26`) | `RankBrowser.lua:1075-1088`; `OnVerticalScroll` → `FauxScrollFrame_OnVerticalScroll` `1078-1082` |
| Row internals | zebra BACKGROUND stripe (white 0.05 / black 0.15); hover/player overlay texture (brand); 3px class-colour bar; 14px spec icon texture (hidden when absent); 6 column FontStrings from `COLUMNS` templates; "YOU" FontString tag at x=626 | `createRow` `RankBrowser.lua:797-875` |
| Empty state | one FontString `LB_EMPTY_FILTERS`, shown iff `totalCount == 0` | `RankBrowser.lua:1091-1095`, `767-769` |
| Footer standing | `GameFontNormal` FontString: overall/faction/class rank + pool size, or `LB_FOOTER_NO_RANK` | `RankBrowser.lua:1098-1101`, `773-790` |
| Top button | `UIPanelButtonTemplate`, label `LB_TOP` ("◤ Top") | `RankBrowser.lua:1103-1109`; `enUS.lua:208` |
| My Rank button | `UIPanelButtonTemplate`, label `LB_MY_RANK_ARROW` ("◣ My Rank") | `RankBrowser.lua:1111-1117`; `enUS.lua:209` |
| Scan button | `UIPanelButtonTemplate`, `LB_SCAN` / `LB_SCAN_BUSY` toggled by progress | `RankBrowser.lua:1122-1129`, `484-488` |
| Progress bar | `StatusBar` `UI-StatusBar` texture, brand purple, 12px, hidden when idle; text "done / total" | `RankBrowser.lua:1133-1153`, `454-490` |

### 1.2 Widget tree — gear panel `TacoTipGearPanel` (row click)

400×470 DIALOG, DialogFrame backdrop (guarded), movable, title `GEAR_TITLE`, `UIPanelCloseButton`,
17 slot FontStrings (from `SLOT_ROWS`, labels from client `INVTYPE_*` globals), one note
FontString (`RankBrowser.lua:559-659`). Item links are rendered **as item links** so the client
supplies quality colour and hover tooltip (`RankBrowser.lua:535-551`, `638-648`); the
"not scanned yet" note replaces 17 blank lines (`RankBrowser.lua:627-655`).

### 1.3 Interactions

- Drag-move both windows (`RankBrowser.lua:923-927`, `587-591`).
- Row hover: overlay alpha 0.10 + `GameTooltip` detail (name/spec/GS/iLvl/GS-rank/last-seen/faction),
  `SetOwner(row, "ANCHOR_RIGHT")`, never sets a unit (`RankBrowser.lua:278-324`, `856-865`).
- Row click: opens gear panel for that row's own `entry` (index-safe) (`RankBrowser.lua:870-872`).
- Sort headers: click sets `currentSort` and scrolls to top; hover previews the underline
  (`RankBrowser.lua:1021-1035`). No direction toggle — `seen` is the only ascending sort and it
  is hard-coded (`RankBrowser.lua:896`).
- Search: filters on every keystroke (`RankBrowser.lua:970-973`).
- Class dropdown: drives `currentClass`, updates label, re-renders (`RankBrowser.lua:987-1002`).
- Top / My Rank / Scan via real OnClick handlers (`RankBrowser.lua:1103-1129`); My Rank
  re-centres on the player's row in the **current** view (`RankBrowser.lua:676-683`, `728-737`).
- Escape closes the **topmost** window (gear panel before browser) through three routes:
  `OnEscapePressed`, `UISpecialFrames`, `KEY_ESCAPE` event — documented per client family in
  `RankBrowser.lua:1183-1263`.
- Open entry points: slash commands `/ttrank`, `/ttranks`, `/ttleaderboard`, `/tt lb|rank|ranks|leaderboard`
  (`RankBrowser.lua:1296-1307`); minimap **left-click** opens the browser, right-click opens Options
  (`Minimap.lua:128-147`); Options "Open Server Leaderboard" button
  (`Options.lua:1253-1264`); minimap hover tooltip documents all three (`Minimap.lua:149-165`).
- Every open re-centres on the player (`OnShow` sets `jumpToPlayerPending`, `RankBrowser.lua:1156-1160`).

### 1.4 Visual treatment

- Brand purple 0.60/0.46/0.82; muted 0.62; text 0.90 (`RankBrowser.lua:32-34`).
- `#` column coloured by `Scoring.RankColor` (podium gold/silver/bronze + percentile bands),
  muted fallback (`RankBrowser.lua:145-154`; scale `Scoring.lua:993`).
- GS and iLvl share the quality colour of value ÷ best-in-view (`RankBrowser.lua:127-140`,
  `705-718`; `Scoring.lua:932`).
- Name in class colour from a hard-coded `CLASS_COLORS` table incl. retail-only classes, grey
  default (`RankBrowser.lua:54-69`), echoed by the 3px class bar (`RankBrowser.lua:391`).
- Spec and last-seen muted; player row gets a 0.18 brand overlay and a "YOU" tag
  (`RankBrowser.lua:330-341`, `415-418`).
- The `#` column is always the **GearScore rank**, independent of display sort
  (`RankBrowser.lua:206-267`, pinned by `rankbrowser_test.lua:821-830`).

### 1.5 Feedback states

| state | behaviour | cite |
|---|---|---|
| Scan running | progress bar shows, `done/total` text, button reads "Scanning..." | `RankBrowser.lua:454-490` |
| Scan idle | bar hidden (no dead rail); button reads "Scan now" | `RankBrowser.lua:471-475`, `484-488` |
| Scan completes | bar stays full until Scanner reports inactive, then hides — no sound, no flash, no "done" text | `RankBrowser.lua:449-453`, `472-475` (behaviour verified; absence of confirmation is VERIFIED by reading) |
| Filters match nobody | all rows hide + one message `LB_EMPTY_FILTERS` | `RankBrowser.lua:767-769`, `1091-1095` |
| Whole DB empty | same single message ("No players match the current filters.") — **no distinct first-run state**, even though `LB_EMPTY` and `LB_ONLY_YOU` are translated in all 10 shipped locales | `enUS.lua:202-205`; only `LB_EMPTY_FILTERS` consumed (`RankBrowser.lua:1093`, grep VERIFIED) |
| Player unranked | footer switches to muted `LB_FOOTER_NO_RANK`; My Rank silently falls back to offset 0 | `RankBrowser.lua:784-789`, `728-736` |
| Gear not scanned | note line replaces empty rows | `RankBrowser.lua:650-655` |
| Missing spec icon | texture hidden, row keeps spacing | `RankBrowser.lua:351-373`, pinned by `rankbrowser_test.lua:896-906` |
| Row hover detail | GameTooltip with 4–7 lines | `RankBrowser.lua:278-317`, pinned by `rankbrowser_test.lua:876-890` |
| Loading (first open) | footer initialises to `LB_LOADING` until first UpdateUI paints | `RankBrowser.lua:1098-1101` |

Dead locale keys for this surface (translated everywhere, consumed nowhere in RankBrowser —
grep VERIFIED): `LB_EMPTY`, `LB_NOT_ESTABLISHED`, `LB_ONLY_YOU`, `LB_SCAN_IDLE`,
`LB_TIP_CLASSRANK` (`enUS.lua:202-205, 213, 235`).

### 1.6 Screenshots (all inspected)

`1.png` and `5.png` are the **detailed** and **compact unit tooltips** for the same shaman —
not the leaderboard window. `2.png`/`3.png`/`4.png`/`7.png` are further detailed tooltips
(warrior, druid, warrior, paladin); `6.png` is a compact tooltip (warrior). `tt-2.png` is the
TacoTip `/tt` logo image (matches the `## IconTexture` tga of `TacoTip_Extras.toc:9`).
**No screenshot shows the leaderboard browser window itself** — the visual inventory above
comes from source only. UNKNOWN: what the browser looks like in game today; a real capture
would be the cheapest way to double-check spacing claims (e.g. the `sortHint` line sitting
between header and rows at `ROW_TOP + 26`).

---

## 2. Gaps and opportunities (ranked by impact / effort / regression risk)

Each item: exact change → Blizzard widget/pattern (branch-verified) → fallback → degradation →
harness validation. Harness references: `rankbrowser_test.lua` builds its own stricter mock
environment (real IsShown, template whitelist at lines 305-313, dropdown shims 328-339,
FauxScrollFrame shims 288-301); `load_test.lua` loads the real TOC order with a per-client mock.

### G1 — First-run vs no-match empty state (impact HIGH, effort LOW, risk LOW)

- **Change**: when `totalCount == 0` **and** no filters are active, show `LB_EMPTY`
  ("No records yet. Scores sync while you play."); when `totalCount == 0` with class/search
  active, keep `LB_EMPTY_FILTERS`; when the DB holds only the player, use `LB_ONLY_YOU`
  (exists at `enUS.lua:203-205`, already translated in all 10 other locales, currently dead).
- **Blizzard widget**: none needed — plain FontString, same as today
  (`RankBrowser.lua:1091-1095`).
- **Fallback / degradation**: none required; worst case a wrong message between the two
  translated strings.
- **Harness validation**: `rankbrowser_test.lua` already stubs `RankDB.GetLeaderboard` to
  `{}, 0` (`rankbrowser_test.lua:912-921`); extend that section to assert the shown text is
  the "no records" string when `currentClass == "ALL" and currentSearch == ""`, and the
  "filters" string after setting the search box (the harness can already drive
  `searchBox.Fire("OnTextChanged")`, `rankbrowser_test.lua:707-728`). Locale fallbacks are
  already covered by load_test's "every enUS key resolves" and partial-locale checks
  (`load_test.lua:1562-1567`, `1927-1934`). **New locale keys: none** — reuse existing keys,
  so no 11-file sync is needed.

### G2 — Sort direction toggle (impact MED-HIGH, effort LOW, risk LOW)

- **Change**: clicking the already-active column flips ascending/descending (today `currentSort`
  is one-way and the arrow direction is derived from a single hard-coded exception
  `currentSort == "seen"` → `ARROW_UP`, `RankBrowser.lua:896`). Store `sortAsc` beside
  `currentSort` (`RankBrowser.lua:216`) and render the arrow from it.
- **Blizzard widget**: none — the header is already a Button (`RankBrowser.lua:1017`); the
  ▲/▼ glyphs are already shipped strings (`RankBrowser.lua:219-220`).
- **Fallback**: n/a. **Degradation**: if `sortAsc` state were lost, behaviour degrades to
  exactly today's one-way sort.
- **Harness validation**: the harness already finds header buttons by label and fires their
  real OnClick (`rankbrowser_test.lua:773-855`); add: click `iLVL` twice, assert the rendered
  ilvl order flips and the sort-hint FontString text flips its arrow. Also assert the `#`
  column invariant survives both directions (the existing pinned invariant at
  `rankbrowser_test.lua:821-830` is the regression guard).

### G3 — SearchBoxTemplate for the search field (impact MED, effort LOW, risk LOW)

- **Change**: create the search EditBox with `SearchBoxTemplate` instead of bare
  `InputBoxTemplate` (`RankBrowser.lua:964`). Gains the magnifier icon
  (`common-search-magnifyingglass`), a clear (×) button, and instruction text — the standard
  Blizzard search affordance.
- **Branch-verified**: defined on **all five** branches —
  `origin/classic_era:Interface/AddOns/Blizzard_SharedXML/Shared/InputBox/InputBoxTemplates.xml:29`
  (inherits `InputBoxInstructionsTemplate`, default instruction "SEARCH"); identically at line
  **206** on `origin/forever` and `origin/live` (same path); template-name grep counts 48/48/47/85/70
  files across classic_era/anniversary/titan/forever/live. Loaded by the classic family via the
  per-family SharedXML TOC (e.g. `origin/classic_era:…/Blizzard_SharedXML_Vanilla.toc` loads the
  Shared InputBox files — VERIFIED via family TOC listing; the addon's own InputBox usage proves
  SharedXML is loaded at runtime on all clients).
- **Fallback**: keep the pcall-CreateFrame pattern the file already uses; on template failure
  fall back to the current `InputBoxTemplate` construction (`RankBrowser.lua:964-969` style).
- **Degradation**: no clear button / no magnifier — identical to today.
- **Harness validation**: add `"SearchBoxTemplate"` to the whitelist at
  `rankbrowser_test.lua:305-313` (the mock errors on unknown templates by design,
  `319-324`); the existing search assertions (`rankbrowser_test.lua:707-728`) keep working
  unchanged because they drive `SetText`/`OnTextChanged`, which the template only augments.
  Note the mock has no `ClearButtonMixin`; if the browser wires the clear button explicitly,
  the mock needs a no-op `HookScript`-safe path or the wiring must use `SetScript` on the
  created child (mock supports `SetScript`, `rankbrowser_test.lua:108`).

### G4 — Localized class names in the dropdown and Spec column (impact MED, effort LOW, risk LOW)

- **Change**: the class dropdown entries and the Spec-column fallback render the raw token
  (`CLASS_ORDER` values like "MAGE" are handed to `UIDropDownMenu_AddButton` directly,
  `RankBrowser.lua:999-1001`; the row fallback shows `entry.class` raw,
  `RankBrowser.lua:394-397`). The addon already ships localized names: `CLASS_WARRIOR`…
  `CLASS_DEATHKNIGHT`, `CLASS_UNKNOWN` (`enUS.lua:262-274`). Resolve
  `L["CLASS_" .. className] or className` at render time (same live-`L` pattern as the
  headers, `RankBrowser.lua:39-44`). **Gap**: there is no `CLASS_EVOKER` key though
  `CLASS_ORDER` contains EVOKER (`RankBrowser.lua:76`) — either add the key to enUS first
  (then the other 10 locales can lag; partial fallback is load-tested,
  `load_test.lua:1927-1934`) or keep the `or className` fallback.
- **Constraint from the repo's own tests**: locale parity is one-directional — "no locale
  defines a key enUS does not" (`load_test.lua:1569-1584`), and format-spec safety is checked
  (`load_test.lua:1586-1608`). Adding `CLASS_EVOKER` to enUS only is legal; adding it to a
  translation before enUS fails the suite.
- **Blizzard widget**: none. Fallback: raw token (today's behaviour). Degradation: none.
- **Harness validation**: `rankbrowser_test.lua` loads RankBrowser **without** the Locale files
  (only RankDB/RankBrowser/Scoring, `rankbrowser_test.lua:355-360`), so it exercises the
  English fallbacks; assert the dropdown entry text is the resolved name in the load_test run
  where `TACOEXTRAS_LOCALE` is real (or extend rankbrowser_test to load `Locale/enUS.lua`
  first and assert `dropdownEntries[i].text == "Mage"`). The existing count assertion
  (`#dropdownEntries == 14`, `rankbrowser_test.lua:675-676`) stays valid.

### G5 — Class icons in the dropdown and next to row names via `GetClassAtlas` (impact MED, effort MED, risk LOW)

- **Change**: give each class-dropdown entry an icon, and optionally add a 14px class icon to
  the name cell (row already has a 14px spec-icon texture pattern to copy,
  `RankBrowser.lua:828-833`). Icon source: `GetClassAtlas(className)` → `"classicon-<CLASS>"`.
- **Branch-verified**: `function GetClassAtlas` is defined at
  `Interface/AddOns/Blizzard_SharedXML/SharedConstants.lua:44` on **all five** branches
  (identical body, VERIFIED by reading classic_era/forever/live and grepping
  anniversary/titan). `UIDropDownMenu` supports `info.icon` on classic
  (`origin/classic_era:…/Blizzard_SharedXML/Classic/UIDropDownMenu.lua:293` doc, applied at
  `444-446`) and on mainline
  (`origin/live:…/Blizzard_SharedXML/Mainline/UIDropDownMenu.lua:327`; same line on
  origin/forever). Texture `SetAtlas` is a C-region method used pervasively in FrameXML
  (157 files on classic_era, e.g. `origin/classic_era:…/Blizzard_SharedXML/Blizzard_RadialWheel.lua:112`).
- **Fallback**: `pcall(tex.SetAtlas, tex, GetClassAtlas and GetClassAtlas(class) or nil)`; if
  it fails, `SetTexture` with the class-colour bar already present — i.e. exactly today's look.
  The repo already treats `GetClassAtlas` as a five-branch fact (`load_test.lua:810-812` models it).
- **Degradation**: missing atlas → hide the icon (same defensive shape as `applySpecIcon`,
  `RankBrowser.lua:351-373`, which the harness already pins at `rankbrowser_test.lua:896-906`).
- **Harness validation**: mock `GetClassAtlas` is already installed by load_test
  (`load_test.lua:812`); rankbrowser_test needs a `_G.GetClassAtlas` stub plus an assertion
  that `SetTexture/SetAtlas` was called with `classicon-MAGE` for a known row (the mock records
  `__texture`, `rankbrowser_test.lua:169-170`). For dropdown icons, assert `entry.icon` on the
  recorded `dropdownEntries` (`rankbrowser_test.lua:333-335`).

### G6 — Distinct "scan finished" feedback (impact MED, effort LOW, risk LOW)

- **Change**: when a scan transitions active→inactive, flash a short status line ("Scan
  complete — N players tracked") near the progress bar and optionally play a click sound. The
  polling infrastructure already exists (0.25s OnUpdate while `f.scanning`,
  `RankBrowser.lua:1166-1176`); remember the previous `f.scanning` value inside
  `RefreshProgress` (`RankBrowser.lua:454-490`) to detect the edge.
- **Blizzard widget/pattern**: `PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)` — the
  pattern Blizzard's own AddonList uses (`origin/classic_era:…/Blizzard_AddOnList/AddonList.lua:278`).
  `SOUNDKIT` is defined on all five branches (`…/Blizzard_SharedXML/<Family>/SoundKitConstants.lua:2` —
  Vanilla+TBC on the three classic branches, Mainline on forever/live; VERIFIED per branch grep).
  Guard anyway: `if type(PlaySound) == "function" and type(SOUNDKIT) == "table" then`.
- **Fallback**: no sound, text-only confirmation. **Degradation**: no edge detected → today's
  silent hide.
- **Harness validation**: rankbrowser_test has no `PlaySound`/`SOUNDKIT`; either install the
  guard-friendly absence (proves the no-sound path) or add a recorder and assert one play on
  the completion edge. Drive `namespace.Scanner` with a stub `GetProgress` returning
  `{active=true, percent=50, done=5, total=10}` then `{active=false, percent=100, done=10, total=10}`
  and assert the status text appears (`RankBrowser.RefreshProgress` is a public function,
  `RankBrowser.lua:454`).

### G7 — Row hover polish: Blizzard highlight texture + "click for gear" hint (impact MED, effort LOW, risk LOW)

- **Change**: (a) replace the flat hover overlay with Blizzard's list-highlight texture
  `Interface\QuestFrame\UI-QuestTitleHighlight` via `Button:SetHighlightTexture(tex, "ADD")`
  while keeping the brand overlay for the player row; (b) append one muted line to the row
  tooltip: "Click to view gear" (new enUS key, then optional translations).
- **Branch-verified**: `UI-QuestTitleHighlight` is referenced by Blizzard UI on all five
  branches (19 files classic_era / 18 forever / 17 live — VERIFIED by grep; same texture path
  family as the addon's existing minimap highlight
  `Interface\Minimap\UI-Minimap-ZoomButton-Highlight`, `Minimap.lua:16`).
- **Fallback**: if `SetHighlightTexture` is absent (mock no-ops it today,
  `rankbrowser_test.lua:217`), keep the current overlay-only hover — visually identical to now.
- **Degradation**: none. **Harness validation**: the tooltip test already asserts ≥4 lines and
  content substrings (`rankbrowser_test.lua:880-885`); add one substring check for the hint.
  Overlay-alpha assertions for the player row (`rankbrowser_test.lua:562-563`) are unaffected.

### G8 — My Rank when the player is not in the database (impact MED, effort LOW, risk LOW)

- **Change**: `TrackToPlayer` currently sets a pending flag and, if the player is absent,
  `UpdateUI` silently lands on offset 0 (`RankBrowser.lua:728-736`). Show a transient footer
  note (reuse `LB_NOT_ESTABLISHED`, `enUS.lua:204`) or flash the footer for ~2s when the jump
  cannot find the player.
- **Widget**: none. Fallback: today's silent jump. Degradation: none.
- **Harness validation**: delete the player record via `RankDB` (or stub GetLeaderboard),
  fire the My Rank button (pattern `rankbrowser_test.lua:613-620`), assert offset == 0 and the
  footer/flash text. (Check `RankDB` for a delete/prune API first — UNKNOWN at time of
  writing; stubbing `GetLeaderboard` as `rankbrowser_test.lua:912-913` does is sufficient.)

### G9 — Window chrome upgrade: `PortraitFrameTemplate` / `ButtonFrameTemplate` (impact MED-HIGH, effort MED, risk MED)

- **Change**: replace the hand-rolled DialogFrame backdrop (`RankBrowser.lua:930-939`) with
  Blizzard's standard panel chrome: `ButtonFrameTemplate` (portrait frame + `$parentTitle` +
  `$parentInset` + bottom button bar for Top/My Rank/Scan) — this is how Blizzard windows
  present a title, close button and inset content area.
- **Branch-verified**: `ButtonFrameTemplate` defined on all five branches —
  `origin/classic_era:…/Blizzard_SharedXML/Classic/SharedUIPanelTemplates.xml:708`
  (inherits `PortraitFrameTemplate` at `:545`; inset `InsetFrameTemplate` at `:683`);
  `origin/live:…/Mainline/SharedUIPanelTemplates.xml:684` (portrait at `:658`, inset `:389`);
  identical file:lines verified on origin/forever; grep counts 84/84/84/110/100 usage files
  across the five branches. The addon already depends on sibling templates from the same XML
  (`UIPanelCloseButton` classic_era `:188`, `UIPanelButtonTemplate` classic_era `:348`).
- **Fallback**: keep the current construction behind the same pcall the file already uses for
  `BackdropTemplate` (`RankBrowser.lua:916-920`); on failure, build the old backdrop window.
- **Degradation**: no portrait, no inset — today's look. Strata/movable/escape behaviour is
  independent of chrome and must be kept as-is (`RankBrowser.lua:923-928`, `1203-1263`).
- **Harness validation**: add the template names to `rankbrowser_test.lua:305-313`; assert the
  frame's `__template` is `ButtonFrameTemplate` when created with it, that the title/close
  children exist, and that **every existing behaviour assertion still passes unchanged** —
  that is the real acceptance bar (rows, escape, jump, sort, filters, footer are all
  template-agnostic today). Run all five `load_test.lua <client>` arms: CreateUI must not raise
  on any client (`load_test.lua` "load every TOC file" + sub-initializer sections).
  Risk note: geometry constants (`ROW_TOP`, `HEADER_TOP`, footer y) all shift to fit the inset;
  the harness does not assert geometry, so an in-game screenshot check is still required —
  UNKNOWN until someone opens it on a real client.

### G10 — Virtualized list via `HybridScrollFrame` (impact HIGH for large realms, effort HIGH, risk MED-HIGH) — tier C

- **Change**: replace the 12 fixed rows + FauxScrollFrame with `HybridScrollFrameTemplate`
  and `HybridScrollFrame_CreateButtons` so the window can scale to hundreds of rows with a
  native scrollbar and no manual offset maths.
- **Branch-verified**: template defined on all five branches at
  `…/Blizzard_SharedXML/HybridScrollFrame.xml:178` (identical file:line classic_era → live);
  `HybridScrollFrame_CreateButtons` at `…/Blizzard_SharedXML/HybridScrollFrame.lua:226` on all
  five; real Classic usage e.g. `origin/classic_era:…/Blizzard_Channels/ChannelRoster.xml` and
  `Blizzard_AchievementUI` (Cata variant) — so the template is exercised by Blizzard's own UI
  on the Classic client family, not just Retail.
- **Fallback**: none needed (present everywhere); but keep the FauxScrollFrame path reachable
  behind a construction-time pcall as with every other template in this file.
- **Degradation**: construction failure → current FauxScrollFrame window.
- **Harness validation**: **this is the expensive part.** The focused harness finds rows by
  scanning children for `rankText` (`rankbrowser_test.lua:433-439`) and hard-codes 12 rows and
  the centring maths (`rankbrowser_test.lua:376-377`); a pooled-button implementation must keep
  `row.entry`, `row.gsRank`, `row.isPlayer`, `rankText/nameText/...` fields on each pooled
  button or the harness (and its 80 pinned behaviours) must be reworked. Recommend only after
  G1–G8 land and only with the harness updated in the same change.

### G11 — `ScrollBox` / `ScrollUtil` modernization (effort HIGH, risk HIGH) — tier C, discouraged for 1.2.x

`ScrollUtil`/`ScrollBox.lua` exist on all five branches
(`…/Blizzard_SharedXML/Shared/Scroll/ScrollUtil.lua`, `ScrollBox.lua` — VERIFIED per-branch),
but the API surface differs between classic and mainline FrameXML usage patterns; adopting it
buys nothing over HybridScrollFrame for a 12-row virtual list and would rewrite the exact
thumb/offset invariants the harness exists to protect (`rankbrowser_test.lua:22-25`,
`553-558`). See do-not list.

### G12 — Class colours from `RAID_CLASS_COLORS` instead of the hard-coded table (effort LOW-MED, risk LOW-MED) — tier B

The hard-coded `CLASS_COLORS` (`RankBrowser.lua:54-69`) duplicates client data and misses
player-installed class-colour addons. `RAID_CLASS_COLORS` is present on all five branches
(34–36 usage files each; the addon's own dependency TacoTip reads it and load_test models it
at `load_test.lua:850-854`). Resolution order: `CUSTOM_CLASS_COLORS` → `RAID_CLASS_COLORS` →
the existing hard table → grey. Keep the hard table as final fallback so the colour assertions
in `rankbrowser_test.lua:754-759` still have a defined answer when the mock omits a class.
Harness: load_test already seeds WARRIOR/MAGE; extend the seed or assert the fallback grey.

### G13 — Debounced search (effort LOW, risk LOW) — tier B

`OnTextChanged` calls `UpdateUI` on every keystroke (`RankBrowser.lua:970-973`), which sorts
the whole filtered set (`RankBrowser.lua:703`) each time. A 0.2s debounce via `C_Timer.After`
(modelled in load_test at `load_test.lua:779-782`) keeps typing smooth on big realms.
Harness: rankbrowser_test's mock env has no `C_Timer` — add a synchronous stub and assert the
filtered render still lands (existing assertions `rankbrowser_test.lua:707-728` become
"fire OnTextChanged, run pending timer, then assert").

---

## 3. Do-not list

1. **Do not add any library to `TacoTip_Extras`.** The root `Libs/` is loaded only by
   `TacoTip.toc:11-14`; `TacoTip_Extras.toc` loads none of it (VERIFIED). LibDBIcon/LDetours
   etc. are out of scope for this surface.
2. **Do not make `KEY_ESCAPE` the only close route.** Classic FrameXML never dispatches it;
   the three-route registration and its comment are the load-bearing design
   (`RankBrowser.lua:1183-1263`); the focused harness models exactly this per-family split
   (`rankbrowser_test.lua:256-283`, `469-506`).
3. **Do not un-guard `SetBackdrop` / template CreateFrame calls.** Every template adoption must
   keep the pcall + fallback shape (`RankBrowser.lua:916-920`, `930`); `BackdropTemplate` is on
   all five branches (`…/Blizzard_SharedXML/Backdrop.xml:5`) but a renamed template on one
   future client must not kill the window.
4. **Do not per-client fork `RankBrowser.lua`.** The repo's pattern is capability guards + shared
   behaviour, and the user's standing preference is consistent behaviour across all five
   clients. Client-specific UI belongs in data (locale, atlas availability), not branches.
5. **Do not add new locale keys to any file before enUS.** Load-test fails any locale defining
   a key enUS does not (`load_test.lua:1569-1584`) and checks format-specifier parity
   (`load_test.lua:1586-1608`) and script contamination (`load_test.lua:1745-1783`). Prefer
   reusing the five already-translated dead keys (`enUS.lua:202-205, 213, 235`) over inventing
   keys.
6. **Do not rely on `OnTooltipSetUnit`/`OnTooltipSetItem` for browser tooltips.** Those scripts
   exist only on the Classic GameTooltip (the whole driver split in `load_test.lua:2033-2136`);
   the row tooltip's SetOwner/AddLine approach (`RankBrowser.lua:278-317`) is the portable one
   and must stay.
7. **Do not adopt `ScrollBox`/`ScrollUtil` or the `DropdownButton`/Menu API in the 1.2.x line.**
   Both exist on all five branches (VERIFIED: `Blizzard_Menu/DropdownButton.xml:3`,
   `MenuUtil.lua:34` — Blizzard_Menu is `LoadFirst: 1`, not LoadOnDemand, on classic_era), but
   the current UIDropDownMenu is proven by the running suite (`rankbrowser_test.lua:660-704`)
   and loaded by the family TOCs (`origin/classic_era:…/Blizzard_SharedXML_Vanilla.toc:166-169`).
   Swapping dropdown stacks is medium-risk churn with zero user-visible win over G4/G5.
8. **Do not delete the FauxScrollFrame offset discipline.** `scrollToOffset` exists because
   `FauxScrollFrame_SetOffset` desyncs the thumb (`RankBrowser.lua:186-200`,
   `FauxScrollFrame_OnVerticalScroll` defined at `…/SecureScrollTemplates.lua:227` on all five
   branches); the harness pins thumb==offset (`rankbrowser_test.lua:553-558`).
9. **Do not special-case Retail-only classes or widgets in shared render paths.** EVOKER rows
   already degrade to the grey default colour (`RankBrowser.lua:69`); keep that shape for any
   new class-bound asset (icons, colours).
10. **Do not ship a template adoption without extending the harness template whitelist.**
    `rankbrowser_test.lua:305-313` errors on any unknown template by design
    (`319-324`) — that is a feature: it turns "silently different widget" into a red test.

---

## 4. Tiered backlog

Client coverage for every item below: all five clients (11509/20506/38002/16001/120105) unless
noted. Effort: S < half-day, M 1–2 days, L multi-day. Risk: L/M/H = low/med/high chance of
regressing a pinned behaviour.

### Tier A — quick wins, compatible with 1.2.x

| # | item | coverage | effort | risk | validation |
|---|---|---|---|---|---|
| A1 | G1 distinct empty states using existing translated keys | all five | S | L | extend rankbrowser_test §8 (`:912-921`) with two text assertions |
| A2 | G2 sort direction toggle on repeat header click | all five | S | L | drive header OnClick twice (`:806-855` pattern), assert order + hint arrow flip; `#`-column invariant re-checked |
| A3 | G7(b) "Click to view gear" hint line in row tooltip | all five | S | L | one substring assertion in §6 (`:880-885`); new enUS key added first |
| A4 | G8 My-Rank-with-no-record feedback | all five | S | L | stub GetLeaderboard, fire My Rank, assert footer text + offset 0 |
| A5 | G4 localized class names via `L["CLASS_"..x] or x` | all five | S | L | dropdown-entry text assertion (load enUS in harness or assert in load_test) |
| A6 | G6 scan-complete edge feedback (text, sound behind guard) | all five (SOUNDKIT verified per branch) | S-M | L | stub `Scanner.GetProgress` active→inactive, assert status text; PlaySound guard exercised by absence |

### Tier B — medium upgrades

| # | item | coverage | effort | risk | validation |
|---|---|---|---|---|---|
| B1 | G3 SearchBoxTemplate (pcall + InputBoxTemplate fallback) | all five (template defs verified) | S-M | L | whitelist + existing search assertions (`:707-728`) |
| B2 | G5 class icons: `GetClassAtlas` + `SetAtlas`, dropdown `info.icon` | all five (defs verified) | M | L | mock records SetAtlas arg; dropdown entries carry `.icon`; missing-icon hide path already pinned (`:896-906`) |
| B3 | G7(a) UI-QuestTitleHighlight row hover | all five (usage verified) | S-M | L | overlay-alpha player-row assertions unchanged; hover look is in-game check |
| B4 | G12 RAID_CLASS_COLORS resolution chain with hard-table fallback | all five | M | M | colour assertions `:754-759` must still pass with partial mock; add fallback-grey case |
| B5 | G13 debounced search (C_Timer) | all five (mocked at load_test `:779-782`) | S-M | L | synchronous timer stub; existing filter assertions after flush |
| B6 | G9 ButtonFrameTemplate chrome (keep backdrop fallback) | all five (defs verified, same file:lines classic→mainline family split) | M | M | whitelist + template-name assert + full existing suite green + all five load_test arms + **in-game screenshot** (geometry is untestable in harness — UNKNOWN until seen) |

### Tier C — larger redesign (post-1.2.x candidates)

| # | item | coverage | effort | risk | validation |
|---|---|---|---|---|---|
| C1 | G10 HybridScrollFrame virtualization (pooled rows, native scrollbar) | all five (template + CreateButtons verified, Blizzard Classic usage verified) | L | H | harness row-discovery contract (`:433-439`) must be redesigned with the change; all 80 pinned checks re-homed; keep FauxScrollFrame fallback behind pcall |
| C2 | G11 ScrollBox/ScrollUtil | all five but API drift between families | L | H | not recommended; would invalidate the offset/thumb invariants the harness protects |
| C3 | New dropdown stack (`DropdownButton` + MenuUtil) replacing UIDropDownMenu | all five (verified present, Blizzard_Menu LoadFirst) | M | H | dropdown-driven assertions (`:660-704`) rewritten; gains little over A5+B2 — do only with a compelling visual reason |
| C4 | Real browser screenshot set (the operator asked for leaderboard visuals; none of the 7 screenshots show it) | n/a | S | L | capture `/tt lb` on at least classic_era + one mainline client after each tier lands; attach to bench |

---

## 5. Uncertainty markers

- **UNKNOWN**: real-client appearance of the browser (no screenshot exists; all visual claims
  above are source-derived). Spacing collisions (e.g. sortHint vs headers, YOU tag vs last-seen
  column at x=626) are arithmetically plausible but unconfirmed on screen.
- **UNKNOWN**: whether `RankDB` exposes a delete/prune API for the G8 harness path; stubbing
  `GetLeaderboard` sidesteps it.
- **ASSUMED**: `common-search-magnifyingglass` atlas renders identically on Classic Era (the
  template XML referencing it is the same file loaded by that client, so absence would break
  Blizzard's own search boxes first — low risk, would verify by opening the AddonList search).
- **ASSUMED**: `SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON` exists in every family's
  SoundKitConstants.lua (the SOUNDKIT table itself is verified per branch at file line 2;
  the specific constant was read on classic_era only — guard the lookup, as G6 prescribes).
