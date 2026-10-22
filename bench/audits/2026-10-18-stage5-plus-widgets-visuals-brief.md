# Stage 5+ — widgets, visuals, and polish: implementation-ready brief

- **Date:** 2026-10-18
- **Desk:** `stage5-prep` (bench-only authoring; no code touched)
- **Parent specs:**
  - `bench/audits/2026-10-18-extras-rankbrowser-ux-review.md` (Tier B/C backlog — the "more visuals/widgets" source; Tier A landed)
  - `bench/audits/2026-10-18-stage3-cheap-fields-brief.md` (13-field stride, guild/level/pvp rendering)
  - `bench/audits/2026-10-18-stage4-gear-on-demand-brief.md` (G/D wire, two-tier gear cache, panel render precedence)
  - `bench/audits/2026-10-18-stage1-and-tier-a-oracle-audit.md` (transport constraints: same-transport-only, no whisper path, counted outcomes)
- **Evidence labels (CAIRN.md):** `[V]` VERIFIED (read in source or produced by a command I ran), `[A]` ASSUMED (says what would verify), `[U]` UNKNOWN.
- **Run:** run_id `stage5prep-01`, agent_name `stage5-prep`.

---

## 0. Load-bearing assumption: Stages 3 and 4 land as briefed

This brief **assumes Stage 3 and Stage 4 land exactly as briefed**:

- **Stage 3:** stride `R;<ver>;guid;name;classID;gs;ilvl;timestamp;specID;guild;level;pvpRank;arena`, `WIRE_VERSION = "2"`, `RECORD_FIELDS = 13`, guild hard-capped at 24 chars, plus the browser column/filter/render additions (guild text filter, level column, localized spec token, advisory PvP display) `[V]` (brief-read).
- **Stage 4:** `G;<ver>;<reqID>;<guid>` / `D;<ver>;<reqID>;<guid>;<seq>/<of>;<blob>` same-transport version-gated gear answers, sparse `slot=itemID` encoding with pair-boundary chunking (`of` ≤ 4), two-tier cache (session 32/300 + persisted `gear[realm][guid]` capped at 2,000 rows), shared-bucket throttle with per-sender coalescing, and panel render precedence fresh-session > persisted > not-scanned `[V]` (brief-read).

**Reconciled landed tree state (before Stages 3/4, as read):**
`local WIRE_VERSION = "1"` (`TacoTip_Extras/RankSync.lua:165`),
`local RECORD_FIELDS = 9` (`TacoTip_Extras/RankSync.lua:192`),
240-byte door (`TacoTip_Extras/RankSync.lua:22`),
`RankSync.GetDebugState` (`TacoTip_Extras/RankSync.lua:932`),
`RankDB.MAX_CAPACITY = 20000` (`TacoTip_Extras/RankDB.lua:25`),
`RankDB.GetLeaderboard` (`TacoTip_Extras/RankDB.lua:549`),
`RankDB.GetTopRecords` (`TacoTip_Extras/RankDB.lua:530`),
browser `NUM_ROWS = 12` / `ROW_HEIGHT = 26` (`TacoTip_Extras/RankBrowser.lua:22-23`),
`COLUMNS` (`:45-51`), `CLASS_COLORS` (`:54-69`), `CLASS_ORDER` (`:73-77`),
`currentSort`/`sortAsc` (`:267-268`), `SLOT_ROWS` 17 rows (`:667`),
`slotValueText` (`:701`), `ShowGear` (`:725`), gear note (`:817-821`),
`UpdateUI` (`:884`), empty states (`:984-991`), `createRow` (`:1032`),
`CreateUI` (`:1148`), `Toggle` (`:1531`), slash commands (`:1562-1569`),
tooltip `makeRows` (`TacoTip_Extras/Tooltips.lua:697`),
`renderPlayerTooltip` (`TacoTip_Extras/Tooltips.lua:1097`),
Options `createCheckbox` (`TacoTip_Extras/Options.lua:636`),
"Open Server Leaderboard" button (`TacoTip_Extras/Options.lua:1255`),
Minimap click routing (`TacoTip_Extras/Minimap.lua:132-139,223`) `[V]`.

**Reconcile-on-dispatch rule:** the Stage-5 implementer MUST re-grep every `file:line` citation in §1 before touching code. Stages 3/4 move exactly the browser/panel lines this brief attaches to; if a cited line drifted, the attachment *shape* (function/field name) still holds — re-anchor by name, never by stale number.

**Wire-cost headline for the whole stage: zero.** §1 assigns every widget a data source from already-synced record fields, the session cache, client APIs resolved at render, or local settings. No widget adds, widens, or reinterprets a wire field, so the §1.2-style byte table of Stages 3/4 is inherited unchanged and the 240-byte door (`RankSync.lua:22`) is never re-opened. Any diff that touches `SerializeRecord`, `DeserializeRecord`, `recordFromParts`, `RECORD_FIELDS`, `WIRE_VERSION`, or the `G`/`D` grammar is out of Stage 5+ on sight (§5).

---

## 1. Widget inventory

Each item: purpose → attachment point → data source (with wire justification) → render path. Slice assignment in §6.

### W1 — SearchBoxTemplate for the search field (Tier B1 carryover)

- **Purpose:** standard Blizzard search affordance (magnifier, clear button, instruction text) on the existing filter box.
- **Attach:** `RankBrowser.CreateUI` search-box construction (`RankBrowser.lua:1201`, the `InputBoxTemplate` string) `[V]`.
- **Data source:** none (chrome only). Zero wire bytes.
- **Render path:** `pcall(CreateFrame, "EditBox", nil, f, "SearchBoxTemplate")`, fallback to current `InputBoxTemplate` construction on failure — the same pcall+fallback shape the file already uses for `BackdropTemplate` (`RankBrowser.lua:1153-1161`) `[V]`.
- **Verified:** template defined on all five branches — era `InputBoxTemplates.xml:29`, forever/live `:206`, anniversary/titan 10 `SearchBoxTemplate` hits each `[V]` (fresh `git show` this session). Note forever/live carry `mixin="NarrationSearchBoxMixin"` — harmless; the mock harness has no narration mixin, so the harness keeps driving `SetText`/`OnTextChanged` only.
- **Degradation:** no clear button / no magnifier = today's look.

### W2 — Class icons: dropdown `info.icon` + name-cell atlas (Tier B2 carryover)

- **Purpose:** 14px class icon per dropdown entry and beside the row name (mirrors the existing 14px spec-icon pattern).
- **Attach:** dropdown build (re-anchor by `UIDropDownMenu_AddButton`; UX-review cite `RankBrowser.lua:999-1001`) + `applySpecIcon` (`RankBrowser.lua:435-461`) as the copy pattern for the name-cell icon + `createRow` (`RankBrowser.lua:1032`) for the texture slot `[V]`.
- **Data source:** `entry.class` / `classID` (already on the wire, diet shape) resolved at render via `GetClassAtlas(className)` → `"classicon-<CLASS>"`. Zero wire bytes.
- **Render path:** `pcall(tex.SetAtlas, tex, GetClassAtlas and GetClassAtlas(class) or nil)`; on failure hide the icon — identical defensive shape to `applySpecIcon`, whose hide path the harness already pins `[V]`.
- **Verified:** `GetClassAtlas` at `SharedConstants.lua:44` on all five branches (identical body) `[V]` (fresh `git show` ×5 this session). `info.icon` documented + consumed on classic (`Classic/UIDropDownMenu.lua:293,444-446`) and mainline (`Mainline/UIDropDownMenu.lua:327`) `[V]` (fresh grep era+live).
- **Degradation:** missing atlas → today's class-colour-bar-only look (`row.classBar`, created `RankBrowser.lua:1057-1061`, painted `:479`).

### W3 — Row-hover highlight texture + click affordance (Tier B3 carryover; hint half already landed)

- **Purpose:** replace the flat hover overlay with Blizzard's list-highlight texture; the "Click to view gear" tooltip line already shipped in Tier A (`LB_TIP_CLICK_GEAR`, `RankBrowser.lua:399`, `enUS.lua:239`) and is NOT re-done here.
- **Attach:** `applyRowOverlay` (`RankBrowser.lua:413`) + row `OnEnter`/`OnLeave` wiring in `createRow` (`:1032`; re-anchor the hover scripts by name) `[V]`.
- **Data source:** none (chrome). Zero wire bytes.
- **Render path:** `row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")` behind a capability guard; keep the brand overlay for the player row (`RankBrowser.lua:413-433`) untouched.
- **Verified:** texture path referenced by Blizzard UI on era (`Classic/UIDropDownMenuTemplates.xml`) and live (AddonList, FloatingChatFrame, FriendsFrame) `[V]` (fresh grep); anniv/titan/forever ASSUMED family-identical (same texture path family as the addon's own minimap highlight `Minimap.lua:16`) `[A]`.
- **Degradation:** guard fails → current overlay-only hover, visually identical to now.

### W4 — Colour resolution chain (Tier B4 carryover)

- **Purpose:** replace the hard-coded `CLASS_COLORS` duplicate with live client data while keeping it as final fallback.
- **Attach:** `getClassColor` (`RankBrowser.lua:98`) `[V]`.
- **Data source:** none off-client. Resolution order: `CUSTOM_CLASS_COLORS` → `RAID_CLASS_COLORS` → existing `CLASS_COLORS` table (`:54-69`) → grey. Zero wire bytes.
- **Render path:** pure function change; every consumer (`renderRow` name colour `:475-479`, class bar `:479` / `:1057-1061`) inherits it.
- **Verified:** `RAID_CLASS_COLORS` consumed across Blizzard UI on era and live (`ColorUtil.lua`, `SharedConstants.lua`, `ClassColors.lua` hits on both) `[V]` (fresh grep). `CUSTOM_CLASS_COLORS` is a **community convention, not a Blizzard API** — zero hits in SharedXML on era/live `[V]` (fresh grep); therefore the chain MUST type-guard it (`type(...) == "table"`) and it sits first only as an addon-ecosystem courtesy, never as a dependency `[A]`.
- **Degradation:** both tables absent → today's hard-table colours; harness colour assertions keep passing with a partial mock.

### W5 — Debounced search (Tier B5 carryover)

- **Purpose:** stop re-sorting the whole filtered set on every keystroke on 20k-row realms.
- **Attach:** search `OnTextChanged` wiring (re-anchor by `OnTextChanged`; UX-review cite `RankBrowser.lua:970-973`) + `UpdateUI` (`:884`) as the flush target `[V]` shape.
- **Data source:** none (timing only). Zero wire bytes.
- **Render path:** 0.2 s `C_Timer.After` debounce behind `type(C_Timer) == "table"` guard; timer fires `UpdateUI`. `C_Timer` is already modeled in `load_test.lua` (Stage-3 brief §5 cite) `[V]` (brief-read).
- **Degradation:** no `C_Timer` → synchronous `UpdateUI`, exactly today's behaviour.

### W6 — Summary stat strip (NEW: realm-at-a-glance header)

- **Purpose:** one muted line under the scope label answering "how big is this board": pool size, top GS, realm-average GS. Today that information is scattered across the footer (`:1007-1013`) and the sort itself; the strip makes the browser's first paint informative even before scrolling.
- **Attach:** `CreateUI` between scope underline (`tabHighlight`, `:1194`) and the control row (`CONTROL_TOP = -46`, `:30`); text via a new `GameFontDisableSmall` FontString beside `sortHint` (`refreshSortHeaders`, `:1119`; arrow `:1133`) `[V]`.
- **Data source:** `RankDB.GetLeaderboard(...)` return (`:549`) already fetched in `UpdateUI` (`:884-905`): `totalCount`, max `gs` in view, arithmetic mean over the fetched view (NOT a new stored aggregate — recomputed per render from rows already in hand, so large-realm cost is one linear pass piggybacked on the existing sort). Zero wire bytes, zero new storage.
- **Render path:** plain FontString `SetText`; pool 0 → strip hides (no "0 players, top 0" noise — the Tier-A lesson: the empty state speaks via `LB_EMPTY`, `:986`, and the strip stays silent).
- **States:** loading → hidden until first `UpdateUI` paint (same rule as the footer, `:1357` `LB_LOADING` pattern); unranked player → unaffected (strip is realm-scoped, footer stays player-scoped).

### W7 — Fresh-row marker (NEW: "scanned while you watched")

- **Purpose:** rows whose `timestamp` is newer than the browser session start get a subtle marker (2px brand left-edge tick reusing `tabHighlight`'s colour texture approach, `:1194`), so active sync progress is visible without re-reading the scan bar.
- **Attach:** `renderRow` (`RankBrowser.lua:463`) + `applyRowOverlay` (`:413`); session start captured in `Toggle` (`:1531`) / `OnShow` (`:1422`) `[V]`.
- **Data source:** `entry.timestamp` (already on the wire since the diet stride) compared against a module-local `browserSessionStart` (epoch, `GetServerTime`-style guarded read like `RankDB.lua:230`). Zero wire bytes, zero new storage.
- **Render path:** tick texture `Show`/`Hide` per row; marker is paint-only, never stored, never sorted on.
- **States:** all timestamps old → no markers (normal); clock skew (future timestamps) → `timestamp <= sessionStart + 300` tolerance, else treated as fresh — never renders an error, worst case one extra tick.

### W8 — Gear-panel per-slot iLvl + enhancement dots (NEW: session-data richness)

- **Purpose:** when the panel renders from the **session cache** (Stage-4 precedence tier 1), each slot row appends the slot's item level and two completeness dots (enchant present, sockets filled) — the data the Scanner already captures but the panel currently discards (`slotValueText` returns link-or-ID only, `:701-719`).
- **Attach:** `slotValueText` (`:701`) for the iLvl suffix + `ShowGear` row loop (`:805-815`) for the dots `[V]`.
- **Data source:** (a) item level resolved **at display** via `C_Item.GetItemInfo(itemID)` → `itemLevel`, async-aware through the existing check/request/event path (`C_Item.IsItemDataCachedByID` / `RequestLoadItemDataByID`, `Scanner.lua:91-92,313-317`; `ITEM_DATA_LOAD_RESULT` completion in `Core.lua:812,895`) — never persisted, never synced (Stage-4 §7.2 rule inherited); (b) enchant/gem cells from the session `revision.slots` (`Scanner.lua:462-466` permanent enchant + gem IDs, `buildSocketCell` `:281-294`) — session-only by design (expansion §2.4), shown only when the rendered source is a live revision, never from persisted `gear.ids` strings. Zero wire bytes.
- **Render path:** uncached ID → keep today's literal `item:<id>` fallback (`:711-713`); uncached iLvl → no suffix (no spinner, no "…", panel never blocks on item-data load). Dots are two 8px textures reusing the class-bar creation shape (`:1057-1061`); absent data → dots hidden, row identical to today.
- **Verified:** `GetItemInfo` returns `itemLevel` (non-nilable number) on all five branches — era `:407`, live `:619`, anniv/titan/forever 2 `itemLevel` hits each `[V]` (fresh `git show` ×5). Numeric-ID call form stays `[A]` (Stage-4 Q3 carryover): if `C_Item.GetItemInfo(12345)` rejects numerics, the suffix path stays dark and the literal link path carries the panel — verify with `/dump C_Item.GetItemInfo(12345)` per client.
- **States:** persisted-only gear (Stage-4 tier 2) → IDs render as today, no iLvl suffix, no dots, note line gains "last synced <age>" per Stage-4 §7.1 (no new locale key); no-cache → existing `GEAR_NOT_SCANNED` (`:817-821`) unchanged.

### W9 — Keyboard navigation (NEW: arrows + Enter on the list)

- **Purpose:** `Up`/`Down` moves a focus ring across the 12 visible rows, `Enter` opens the focused row's gear panel — the list becomes usable without pixel-hunting rows.
- **Attach:** `createRow` (`RankBrowser.lua:1032`; re-anchor the hover scripts by name) for the focus-ring overlay (reuse `applyRowOverlay` shape, `:413`) + `CreateUI` frame-level `OnKeyDown` (`:1148` construction site) driving `scrollToOffset` (`:240`) and `ShowGear` (`:725`) `[V]` shape.
- **Data source:** none (input only; focused row reads `self.entry`, the same index-safe reference the click handler uses, `:1106`). Zero wire bytes.
- **Render path:** focus ring = brand overlay texture at player-row alpha (`:415-418`); `OnKeyDown` guarded by `frame:IsShown()` + `type(frame.SetPropagateKeyboardInput) == "function"` guard with `SetPropagateKeyboardInput(false)` only while handling arrows/Enter so chat keys are never swallowed.
- **Verified:** `SetPropagateKeyboardInput` documented on era AND live (`SimpleFrameAPIDocumentation.lua`, era `:1233`, `HasRestrictions = true`) `[V]` (fresh read); anniv/titan/forever ASSUMED present (shared doc family) `[A]` — and regardless, every call sits behind the `type(...) == "function"` guard with plain-`OnKeyDown` as the degradation (worst case: arrows also reach chat on one client family — verify in game per §7 Q4).
- **States:** empty list → keys no-op (no focus target, no error); gear panel open → `Escape` still closes topmost-first (existing three-route design, `RankBrowser.lua:1457-1524` — re-anchor, do not touch).

### W10 — ButtonFrameTemplate chrome (Tier B6 carryover)

- **Purpose:** replace the hand-rolled DialogFrame backdrop (`:1153-1165`) with Blizzard's standard panel chrome (portrait frame + inset + bottom button bar for Top/My Rank/Scan).
- **Attach:** `CreateUI` frame construction (`:1148-1152`) + footer/control geometry (`ROW_TOP :28`, `HEADER_TOP :29`, `CONTROL_TOP :30`, `FRAME_WIDTH/HEIGHT :24-25`) which all shift to fit the inset `[V]`.
- **Data source:** none. Zero wire bytes.
- **Render path:** `pcall(CreateFrame, "Frame", "TacoTipRankFrame", UIParent, "ButtonFrameTemplate")`, fallback to today's backdrop construction — same shape as the existing `BackdropTemplate` pcall (`:1153-1161`).
- **Verified:** template defined on all five — era `:708` + anniv `:708` (inherit `PortraitFrameTemplate`), titan `:580`, forever `:711` + live `:684` (inherit `ButtonFrameBaseTemplate`) `[V]` (fresh `git show` ×5). Family inheritance differs (classic `PortraitFrameTemplate` vs mainline `ButtonFrameBaseTemplate`) — construction MUST NOT assume which children (`$parentTitle`, `$parentInset`) exist; resolve-post-create with nil-guards.
- **Degradation:** construction failure → today's backdrop window, pixel-identical. Strata/movable/escape behaviour is chrome-independent and stays as-is.
- **Risk note:** geometry constants shift; the harness asserts no geometry, so **an in-game screenshot on ≥2 clients is the acceptance bar** (UNKNOWN until seen — Tier-C lesson from the review's C4).

### W11 — Density setting in Options (NEW: compact/comfortable rows)

- **Purpose:** a "Comfortable rows" checkbox in Options that grows `ROW_HEIGHT` 26 → 32 (fewer visible rows per paint, same `NUM_ROWS = 12` math) for large-font / accessibility needs.
- **Attach:** Options `createCheckbox` pattern (`Options.lua:636`) in the leaderboard section (`:1255` button site) + `CreateUI` row layout (`ROW_HEIGHT :23`, `ROW_TOP :28`) + `Core` settings normalize/persist (`Core.lua:225`) `[V]` shape.
- **Data source:** local `TacoTipExtrasDB` boolean (existing settings table — `normalizeSettings`, `Core.lua:225`; `defaultBoolean`, `Core.lua:44`). Zero wire bytes, **no new SavedVariables table** (a key inside the existing settings table; §5 storage rule satisfied by construction).
- **Render path:** `CreateUI` reads the setting once per construction; toggle triggers rebuild (`rankFrame = nil` + `CreateUI`). Default OFF = today's geometry, so every existing screenshot and harness expectation holds.
- **States:** setting missing (old SV) → `defaultBoolean` false → compact; no error path renders anything new.

### W12 — HybridScrollFrame virtualization (Tier C1 carryover, gated)

- **Purpose:** replace 12 fixed rows + FauxScrollFrame with pooled buttons + native scrollbar so 20k-row realms scroll without per-row construction cost.
- **Attach:** list construction + `OnVerticalScroll` (`RankBrowser.lua:1332-1334`) + `scrollToOffset` (`:240`) + `FauxScrollFrame_Update` call site (`:954-955`) `[V]`.
- **Data source:** none (presentation only). Zero wire bytes.
- **Render path:** `HybridScrollFrameTemplate` + `HybridScrollFrame_CreateButtons`, pooled buttons keeping the `row.entry / row.gsRank / row.isPlayer / rankText-nameText` field contract the harness discovers rows by.
- **Verified:** template at `HybridScrollFrame.xml:178` + `CreateButtons` on all five, with real Classic-family Blizzard usage (ChannelRoster, AchievementUI) `[V]` (brief-read from the UX review's per-branch verification — NOT re-verified this session; re-confirm at dispatch per §0).
- **Gated:** ships ONLY if 5a/5b are green AND realm-size sampling (§7 Q1) shows the fixed-12 window actually dropping frames; otherwise stays a documented non-ship. The fallback (current FauxScrollFrame) remains reachable behind the construction pcall either way.

---

## 2. Visuals pass

Applies to every widget in §1. Rule inherited from Tier A: **every state speaks** — no silent blank surface ships.

### 2.1 Browser

- **Brand system (reuse, do not reinvent):** brand purple `0.60/0.46/0.82`, muted `0.62`, text `0.90` (`RankBrowser.lua:32-34`) `[V]`; podium `#`-column colours from `Scoring.RankColor` (`getRankColor`, `:192`; scale `Scoring.lua:993` per review — re-anchor) with muted fallback; name in class colour (`getClassColor`, `:98` → W4 chain); spec/last-seen muted; player row 0.18 brand overlay + "YOU" tag (`:415-418`, `:1083`).
- **Iconography (reuse):** spec icons via existing `applySpecIcon` (`:435`) hide-on-absent shape; class icons via W2 (same shape); no new icon sets, no new texture files, no atlas beyond `GetClassAtlas` (client-supplied) and `UI-QuestTitleHighlight` (client-supplied).
- **Podium language:** `#` stays GearScore rank independent of display sort (pinned invariant — every new sortable surface re-checks it, §4). The W6 strip reports realm facts; it MUST NOT restyle the `#` column (rank colour scale is the standings authority).
- **States per new surface:**
  - W6 strip: loading → hidden (footer shows `LB_LOADING`, `:1357`); pool 0 → hidden (`LB_EMPTY` speaks, `:986`); normal → one muted line.
  - W7 ticks: no fresh rows → no ticks (not an error, not a message); skew → tolerance absorbs.
  - W9 focus: empty list → keys no-op; focus never persists across `UpdateUI` re-sorts without re-anchor to `entry` (index-based focus after a re-sort is the exact bug the click handler avoids — focus tracks `entry`, never row index).

### 2.2 Tooltip (unit tooltip surface, `Tooltips.lua`)

- **Scope is deliberately narrow:** Stage 5+ does NOT redesign the unit tooltip (`makeRows :697`, `renderPlayerTooltip :1097` — re-anchor). It adds two optional trailing lines behind the existing content, reusing the row-tooltip's muted-line pattern (`showRowTooltip`, `RankBrowser.lua:353-400`):
  1. Freshness line: "Rank synced <relative>" via the existing `formatRelativeTime` (`RankBrowser.lua:149`) shape, muted — only when the displayed rank row is older than the session (mirrors W7's data, no new source).
  2. Gear-depth line: "Gear: N/17 slots" when a session revision or persisted gear exists for the unit — count only, never IDs (IDs live in the gear panel).
- **States:** no rank row → neither line renders (tooltip identical to today); rank fresh → no freshness line (nothing to explain); gear unknown → no gear line (NOT a "no gear" message — absence of data is not data). No new locale keys beyond the two line formats (enUS-first per the parity rule, §5.9).
- **Driver safety:** both lines feed through `captureRenderInputs` (`Tooltips.lua:1041`) so the change gate (`renderInputsUnchanged`) covers them — a line whose inputs didn't change never repaints. The Classic `OnTooltipSetUnit` / Mainline poll driver split (`Tooltips.lua:48-51`) is untouched.

### 2.3 Gear panel (`ShowGear :725`, `SLOT_ROWS :667`, note `:817-821`)

- **Precedence (Stage-4 §7.1 inherited, restated so the implementer cannot invert it):** fresh session revision → links/IDs + W8 iLvl suffix + dots; persisted `gear.ids` → `item:<id>` literals, no suffix, no dots, note extended with "last synced <age>"; no data → `GEAR_NOT_SCANNED` (`:817-821`) unchanged.
- **Row treatment:** slot labels stay client-localized globals (`slotLabel`, `:689`); empty slots stay dim `|cff808080` (`:812`); iLvl suffix renders in the value's own muted tone, never in quality colour (quality colour belongs to links the client supplies, `slotValueText` comment `:697-700`).
- **States:** item-data pending (17 async `GetItemInfo` fills in flight) → suffixes appear as each resolves via the existing `ITEM_DATA_LOAD_RESULT` path; panel never shows spinners or row counts changing width — suffix area is fixed-width, empty until filled. Panel with zero cached IDs and zero persisted IDs → today's single note line, never 17 blank rows (the current `:627-655` note-replaces-blanks design per UX review — re-anchor).

---

## 3. Per-client rendering constraints

Feature-detect everything; gate nothing on client identity (repo rule). Fresh verifications were run this session with `git show <branch>:<path>`; everything else is brief-read from the UX review / Stage-3 / Stage-4 briefs.

| Capability | Era 11509 | Anniv 20506 | Titan 38002 | Forever 16001 | Retail 120105 | Status |
|---|---|---|---|---|---|---|
| `SearchBoxTemplate` (`InputBoxTemplates.xml`) | `:29` | 10 hits | 10 hits | `:206` (+Narration mixin) | `:206` (+Narration mixin) | VERIFIED (this session) |
| `GetClassAtlas` (`SharedConstants.lua`) | `:44` | `:44` | `:44` | `:44` | `:44` | VERIFIED (this session, identical body) |
| `UIDropDownMenu` `info.icon` | doc `:293`, use `:444-446` | family-identical (brief-read) | family-identical (brief-read) | doc present (brief-read) | doc `:327` | VERIFIED era+live; ASSUMED anniv/titan/forever |
| `UI-QuestTitleHighlight` texture | `Classic/UIDropDownMenuTemplates.xml` | ASSUMED | ASSUMED | ASSUMED | AddonList/FloatingChatFrame/FriendsFrame | VERIFIED era+live; ASSUMED rest |
| `ButtonFrameTemplate` | `:708` (via PortraitFrame) | `:708` | `:580` (line differs) | `:711` (via ButtonFrameBase) | `:684` (via ButtonFrameBase) | VERIFIED (this session — inheritance differs per family, guard children) |
| `HybridScrollFrameTemplate` | `:178` | `:178` | `:178` | `:178` | `:178` | VERIFIED (brief-read; re-confirm at dispatch) |
| `SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON` | 1 hit (Vanilla consts) | 1 hit | 1 hit | 1 hit (Mainline consts) | 1 hit | VERIFIED (this session) |
| `RAID_CLASS_COLORS` | ColorUtil/SharedConstants/ClassColors hits | ASSUMED (brief-read) | ASSUMED (brief-read) | brief-read | ClassColors/ColorUtil hits | VERIFIED era+live; ASSUMED rest |
| `CUSTOM_CLASS_COLORS` | absent (SharedXML-wide) | — | — | — | absent | VERIFIED absent: community convention only, type-guard mandatory |
| `C_Item.GetItemInfo` → `itemLevel` | `:407` | 2 hits | 2 hits | 2 hits | `:619` | VERIFIED (this session, non-nilable number) |
| `SetPropagateKeyboardInput` | doc `:1233` (HasRestrictions) | ASSUMED | ASSUMED | ASSUMED | documented | VERIFIED era+live; ASSUMED rest; always guarded |
| `C_Timer.After` | modeled in load_test | — | — | — | — | VERIFIED (brief-read) |
| `CHAT_MSG_ADDON` payload order | `:615-628` | family-identical (brief-read) | family-identical (brief-read) | family-identical (brief-read) | `:803-816` | VERIFIED era+live (transport rules unchanged by this stage) |

TOC coverage anchor: `TacoTip_Extras/TacoTip_Extras.toc:1` (`11509, 20506, 38002, 16001, 120105`) — re-confirm at dispatch (Stage-3 brief §5 anchor) `[V]` (brief-read).

Classic-family vs Retail-builder note: every template adoption in §1 uses the XML-template `CreateFrame(..., "<TemplateName>")` form that already works on all five clients today (`UIPanelCloseButton`, `FauxScrollFrameTemplate`, `InputBoxTemplate` all construct on every client per the green five-arm `load_test` runs). No Retail-XML-builder-only construct (`ScrollBox`, `DropdownButton`/MenuUtil, `ButtonFrameBaseTemplate` direct use) is adopted — W10 uses the shared `HybridScrollFrameTemplate`, explicitly NOT `ScrollBox` (UX-review do-not #7 inherited).

---

## 4. Harness checks to add (names + what each pins)

Harness shape assumed: `rankbrowser_test.lua` focused suite (template whitelist, dropdown shims, FauxScrollFrame shims, `check(` assertions) + `load_test.lua` five-client TOC-load arms `[V]` (brief-read). Every check below MUST fail on pre-Stage-5 code (new widget absent → assertion on it cannot pass). Each widget ships with a **no-render-on-missing-data** check and, where a client capability is involved, a **Classic-degradation** check (capability removed from the mock → today's look, suite still green).

Browser (`rankbrowser_test.lua`):

1. `"search box builds on SearchBoxTemplate, falls back without it"` — assert the search EditBox's `__template` is `SearchBoxTemplate` after whitelisting; delete the template from the mock → construction falls back to `InputBoxTemplate` and existing search assertions (`SetText`/`OnTextChanged` filter) still pass.
2. `"dropdown entries carry class icons, rows carry class atlas"` — mock `_G.GetClassAtlas` (record args); assert `dropdownEntries[i].icon == "classicon-MAGE"`-shaped and the name-cell texture received `SetAtlas("classicon-…")`; remove the mock → icons hidden, class-colour bar + names unchanged (degradation).
3. `"hover highlight texture set, player overlay intact"` — assert `SetHighlightTexture` called with the QuestTitleHighlight path; player-row overlay alpha assertions unchanged.
4. `"colour chain prefers RAID_CLASS_COLORS, falls back to hard table"` — seed mock `RAID_CLASS_COLORS` with a distinctive colour, assert the name renders it; remove the mock → hard-table colour; assert `CUSTOM_CLASS_COLORS` non-table (string/nil) never raises.
5. `"debounced search renders after flush, not on keystroke"` — synchronous `C_Timer` stub: fire `OnTextChanged`, assert no re-render yet; run pending timer, assert filtered render lands; `C_Timer = nil` → synchronous render (degradation).
6. `"summary strip hides on empty pool, shows pool/top/avg otherwise"` — `GetLeaderboard` stubbed `{}, 0` → strip hidden; seeded rows → text contains pool count and top GS; `#`-column invariant re-checked with the strip visible.
7. `"fresh-row tick only for session-new rows"` — seed one row newer and one older than the fake session start; assert tick visible on the new row only; all-old → zero ticks, no error.
8. `"level/guild columns (Stage 3) survive sortAsc flip with # invariant"` — regression guard owned by Stage 5 (not Stage 3): both directions, `#` still GearScore rank. Pins that Stage-3 column work composes with the landed direction toggle.
9. `"keyboard Down/Enter opens the focused row's gear"` — drive `OnKeyDown` with Down then Enter on a seeded list; assert `ShowGear` received the focused `entry` (identity, not index); empty list → keys no-op, no error; re-sort after focus → focus re-anchored to `entry`, never a stale index.
10. `"ButtonFrame chrome keeps every behaviour"` — template-name assert + **the whole existing suite green unchanged** (rows, escape, jump, sort, filters, footer) + all five `load_test` arms construct without raise. Geometry is NOT asserted (in-game screenshot gate, §6).
11. `"density toggle rebuilds rows, default is today's geometry"` — setting absent/false → `ROW_HEIGHT 26`; true → rebuilt rows at 32 with identical content assertions; toggle back → 26 again.
12. `"virtualized list keeps the row-discovery contract (gated)"` — only if W12 ships: pooled buttons expose `entry/gsRank/isPlayer/rankText/nameText`; all §4.1-style behaviour assertions re-homed; FauxScrollFrame-fallback construction path covered with the template removed from the mock.

Gear panel (`rankbrowser_test.lua`, gear section):

13. `"session revision renders iLvl suffix, persisted renders none"` — session-cache entry with revision → row text contains the mocked `itemLevel`; persisted-only entry → `item:<id>` literal, no suffix, note carries age; no-data → `GEAR_NOT_SCANNED`, never blank rows mistaken for data.
14. `"enhancement dots follow session cells only"` — revision with enchanted/socketed cells → dots shown; persisted-only → dots hidden; `GetItemInfo` uncached → suffix absent, link literal remains, no spinner state exists to assert.
15. `"D ingest updates the panel without rescan (Stage-4 path guard)"` — regression guard owned by Stage 5: ingest a `D` for an uncached guid → `ShowGear` reflects the new IDs (pins that Stage-4 display work survives Stage-5 panel edits).

Tooltip (`load_test.lua` or tooltip-level suite — whichever owns `renderPlayerTooltip` pins at dispatch):

16. `"freshness/gear lines render only with data"` — old rank row → freshness line present, muted; fresh row → absent; no rank → neither line; gear known → `N/17` count line; gear unknown → no gear line (never a "no gear" message).

Debug:

17. `"no new GetDebugState keys, existing keys enumerate"` — Stage 5 adds no counters (no new failure modes: no wire, no storage, no transport). Assert the `GetDebugState` snapshot shape is byte-identical before/after — the inverse of the Stage-3/4 telemetry checks, pinning that display-only work stays display-only.

---

## 5. Explicit non-goals (rejected on sight in any Stage-5 diff)

1. **No wire change.** No `R` stride field, no `G`/`D` grammar change, no version bump, no second stride, no `RECORD_FIELDS`/`WIRE_VERSION` touch. The 240-byte door is not re-opened, re-measured, or re-argued.
2. **Storage budget ceiling (§6.3 of the expansion spec) stands:** 20,000 rank rows ≈ 6 MiB, gear ≤ 0.5 MiB / 2,000 rows. Stage 5 adds **zero persisted bytes per row** (W6/W7 derive per render; W8 resolves at display; W11 is one boolean in the existing settings table). **No new SavedVariables tables** — and any future table would require the expansion §2.3-equivalent model table + migration math in-brief before code, which this brief does not contain because nothing needs it.
3. **No `MAX_CAPACITY`, prune, index, or amortized-engine change** (`RankDB.lua:25-62`, `:589-649` precedents stand).
4. **No `Cache.lua` 32/300 retune, no `REQUIRED_SLOTS` change** — session lifecycle and scorer input are frozen inputs (Stage-4 §8.7 inherited).
5. **No whisper send/queue/fallback in any form** (oracle BLOCKER, inherited). No `Enqueue(..., "WHISPER", ...)` string anywhere in the diff.
6. **No `ScrollBox`/`ScrollUtil`, no `DropdownButton`/MenuUtil stack** (UX-review do-not #7 inherited — verified present but API-drifted between families; gains nothing over W12/W2).
7. **No faction icons, no unit portraits, no "nearby-only" filter backed by new state.** Faction is not synced (diet removed it) and portraits need live units, not GUIDs — there is no verified data to render. A nearby filter on timestamp-recency alone is a heuristic that mislabels; if demanded, it arrives as its own brief with false-positive analysis, not as a Stage-5 hunk.
8. **No GS recompute from synced gear** (Stage-4 §7.4 inherited — standings come from the `R` record's authoritative score, never from partial ID sets).
9. **No locale files beyond enUS-first additions** (parity rule: no locale defines a key enUS does not; format-specifier parity; the locale-tier-a-keys lane owns translations — Stage-5 diffs add enUS keys only, and only the two tooltip line formats in §2.2 plus any W6/W8 user-visible strings that cannot reuse existing keys).
10. **No per-client forks in `RankBrowser.lua`.** Capability guards + shared behaviour (standing repo rule, UX-review do-not #4). Client differences live in data (atlas availability) and guards, never in branches.
11. **No library additions to `TacoTip_Extras`** (TOC loads no `Libs/` — UX-review §1 verified, inherited).
12. **No `Tooltips.lua` driver change** (Classic hook vs Mainline poll split stays), no `Minimap.lua` routing change, no slash-command change, no TOC interface-bump change, no README/CHANGELOG-structure change beyond the normal release-desk entries.

---

## 6. Implementable slices with entry/exit gates

### Slice 5a — Search, icons, colour, strip (all LOW risk)

**Contains:** W1 (SearchBoxTemplate), W2 (class icons), W3 (hover texture), W4 (colour chain), W5 (debounce), W6 (summary strip), W7 (fresh ticks).
**Entry gate:** Stages 3+4 landed + §0 re-grep clean (seven symbols: `WIRE_VERSION`, `RECORD_FIELDS`, `SerializeRecord`, `recordFromParts`, `answerForQuery`, `Enqueue`, `GetDebugState`); `run_all.sh` green at entry (record the invocation count — it moves as stages land).
**Work order:** W5 → W1 (search pair, same wiring) → W4 → W2 (colour before icons, icon fallback reads the chain) → W3 → W6 → W7 (paint-only last).
**Exit gate:** checks §4.1–7 green on lua5.1/5.4/luajit; `LINT=1` zero warnings; all five `load_test` arms green; no new locale key outside enUS; in-game screenshot of the browser on one Classic + one Mainline client attached to the bench (first-ever browser screenshots — review C4 inherited).

### Slice 5b — Chrome, gear richness, tooltip lines (MEDIUM risk, all display-only)

**Contains:** W10 (ButtonFrame chrome), W8 (gear iLvl + dots), §2.2 tooltip lines, W11 (density setting).
**Entry gate:** 5a exit green + screenshots reviewed (geometry surprises from 5a caught before chrome moves geometry again).
**Work order:** W11 → W10 (density constrains the chrome geometry rework — do the setting first so the inset math is parameterized once) → W8 → tooltip lines (independent, either end).
**Exit gate:** checks §4.8–11 + §4.13–16 green; §4.10's full-suite-unchanged bar is the real gate; fresh screenshots on the same two clients (chrome + density both ON and OFF); `GetDebugState` shape-identity check (§4.17) green — proves display-only stayed display-only.

### Slice 5c — List structure + keyboard (STRUCTURAL, gated on need)

**Contains:** W9 (keyboard nav), W12 (HybridScrollFrame virtualization, conditional).
**Entry gate:** 5b exit green + §7 Q1 answered with realm data (W12 ships ONLY on a YES) + Q4 answered in game (keyboard capture safe on the tested families).
**Work order:** W9 first (works on either list implementation; its entry-anchored focus contract constrains W12's pooled-button fields) → W12 only if gated in.
**Exit gate:** checks §4.9 + §4.12 green; full suite green with zero re-homed assertion weakened (any assertion that had to be loosened to fit virtualization is called out in the dispatch message as a weakening, not a pass); screenshots on two clients; if W12 stays out, §4.12 is recorded as NOT-APPLICABLE with the Q1 evidence linked, not silently dropped.

---

## 7. Open questions (refuse to guess)

1. **`[U]` Does W12 need to exist?** No measurement in hand shows the fixed-12 FauxScrollFrame list dropping frames or slowing opens on 20k-row realms — sort cost dominates paint cost, and sort is shared either way. Sample `/ttgsdebug`-adjacent timing (or a `/dump` of open latency) on a full realm before authorizing the highest-risk hunk in this brief. Default: do NOT ship W12.
2. **`[U]` ButtonFrame portrait content:** with no portrait unit to show (GUIDs, not units — §5.7), what fills the portrait seat — the `tt-2.png` logo image (repo root asset, matches the `## IconTexture` tga) or nothing (frameless inset)? One-line operator call; affects only W10's post-create child wiring.
3. **`[A]` Numeric-ID `C_Item.GetItemInfo(itemID)`** (Stage-4 Q3 carryover, load-bearing for W8): docs type the arg as `ItemInfo` on all five `[V]`; the numeric call form is unverified. Verify `/dump C_Item.GetItemInfo(12345)` per client. If it rejects numerics, W8's suffix path stays dark and the brief's W8 checks are rewritten to pin the literal-only panel — the widget degrades, it does not block.
4. **`[A]` Arrow-key capture vs chat on each family:** `SetPropagateKeyboardInput` is documented on era+live `[V]` but `HasRestrictions` on era; whether `OnKeyDown` arrows on a DIALOG-strata frame steal from an open chat edit box on each of the five clients is in-game-only. Verify with chat open + browser focused per client before W9 ships; if any family misbehaves, W9 ships Era-gated-OFF behind the capability probe (guard already specified) rather than as a regression.
5. **`[U]` Enchant/gem cell availability for *remote* revisions on Classic:** `buildSocketCell`/`readSocketCapacity` (`Scanner.lua:238-294`) document client-dependent socket behaviour `[V]` (source-read). W8 dots show only when cells are `complete`; if Classic remote revisions are systematically cell-blocked, dots will be session-owner-only in practice — acceptable, but the panel copy ("session data") must then say whose session. Verify by inspecting a remote target on Era/TBC and reading the revision cells.
6. **`[U]` Summary-strip content:** pool + top GS + mean is the proposal; median resists single-whale skew better but costs a second pass. Operator call after seeing the 5a screenshot — do not add median speculatively (it is a sort-adjacent computation the budget does not need).
7. **`[U]` `CHANNEL` on Anniversary/Titanforge** (expansion §8 carryover via Stages 3+4): affects only dead-channel skip rates, never any §1 widget (nothing here sends). Close via the five-client checklist, not this diff.
8. **`[U]` Fresh-tick window:** session-start comparison is the proposal; a fixed "last 15 min" window would mark rows fresh across browser re-opens but needs a wall-clock both ends agree on. Session-scoped is *honest* (it claims only "synced while you watched"). Changing it needs operator sign-off, not implementer taste.
