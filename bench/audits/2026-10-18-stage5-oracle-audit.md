# Stage 5 (browser widgets + visuals) oracle audit

- **Date:** 2026-10-18
- **Desk:** `audit-stage5` (read-only; no production edits — this report, the desk journal, and signal files are the only writes)
- **Spec:** `bench/audits/2026-10-18-stage5-plus-widgets-visuals-brief.md` (§§0–8, widgets W1–W12)
- **Tree as read:** `WIRE_VERSION = "2"` (`TacoTip_Extras/RankSync.lua:169`), `RECORD_FIELDS = 13` (`:206`), browser `NUM_ROWS = 12` / `ROW_HEIGHT = 26` (`TacoTip_Extras/RankBrowser.lua:22-23`), `GetDebugState` (`RankSync.lua:1374`, 7 keys). Suite re-run by this audit `[V]`: `TOTAL 42 invocations: 42 passed, 0 failed` (lua5.1/5.4/luajit); `LINT=1 → 0 warnings / 0 errors in 26 files`.
- **Evidence labels (CAIRN.md):** `[V]` VERIFIED (read in source or produced by a command I ran), `[A]` ASSUMED (says what would verify), `[U]` UNKNOWN.
- **Concurrent tree:** the working tree mixes uncommitted work from many desks (Stages 1–4, locale lanes, fixers). Section5-widgets' journal scopes itself to RankBrowser / Tooltips(lines) / Options(checkbox) / enUS(3 keys) / harness / CHANGELOG. Where the tree holds adjacent unattributed hunks, §8 names them instead of absorbing them.

## Verdict

**Stage 5 lands. No merge blocker.** Every brief MUST W1–W11 is implemented as specified, every journaled deviation has a reason I accept, all eight open questions are still open (W12 default-do-not-ship respected: zero virtualization code exists). The hard invariants hold exactly: **zero wire bytes, no new SavedVariables tables, no RankSync/RankDB schema change from Stage 5, W12 absent**. Findings are one major (unattributed tooltip-polish hunks needing an owner before sign-off — safe code, certification gap) plus minors and observations, ranked in §8.

---

## 1. Widget MUST-by-MUST (brief §1 vs code)

| Brief MUST | Landed | Where |
|---|---|---|
| W1 SearchBoxTemplate + InputBox fallback | yes | `RankBrowser.lua:1789-1794` (`pcall` SearchBox, fallback InputBox). One shape nit vs the Backdrop precedent: the fallback is a direct `CreateFrame`, not pcall-wrapped (M2). |
| W2 dropdown `info.icon` + name-cell atlas via `GetClassAtlas`, hide-on-failure | yes | dropdown `1853-1867` (`icon = classAtlasOf(value)`, nil for ALL/text-only); row `656-674` (`applyClassIcon`, guarded `SetAtlas` via `widgetMethod`, hide on failure); resolver `235-250` (non-string/UNKNOWN/no-API/pcall-fail → nil). |
| W3 QuestTitleHighlight behind brand overlay, player row intact | yes | `1550-1556` (`widgetMethod(row,"SetHighlightTexture")` + pcall, ADD); overlay alpha order `600-612` (focused/player 0.18 > hover 0.10). |
| W4 colour chain CUSTOM→RAID→hard→grey, CUSTOM type-guarded | yes | `179-205`: `rawget` + `type=="table"` on CUSTOM, per-channel number guards on the entry; same for RAID; falls to `CLASS_COLORS[class] or grey`. Hostile/non-table CUSTOM never raises `[V]` (harness seeds `"junk-string"`). |
| W5 0.2s `C_Timer.After` debounce, sync without `C_Timer` | yes | `1800-1818`: single-shot coalescing (`searchFlushPending` flag, one `After(0.2)` per burst, flush reads live `currentSearch`); no-timer leg calls `UpdateUI()` directly. No leak: at most one pending timer; stale-timer-after-rebuild renders current state once, harmless. |
| W6 strip pool/top/avg, hidden loading + empty | yes | `1399-1412`: one piggybacked linear pass over fetched rows; `totalCount==0 → Hide()`; created hidden `1778-1783` so no paint precedes first `UpdateUI` (loading covered by construction; footer carries `LB_LOADING`). `#` invariant re-checked with strip visible (harness). |
| W7 fresh tick `>= sessionStart`, paint-only | yes | `736-747` (`browserSessionStart > 0 and (tonumber(entry.timestamp) or 0) >= sessionStart`); session clock `167-177` (guarded `GetServerTime`, else 0 = tick nothing); tick widget `1597-1604` (2px brand, hidden default). Far-future skew ticks rather than raising — the brief's "worst case one extra tick" `[V]`. |
| W8 iLvl suffix + enchant/socket dots, session-only | yes | suffix `999-1018` (`sessionItemLevel`: non-numeric guard, `C_Item`/`GetItemInfo` guards, pcall 4-tuple unpack `_,_,_,itemLevel`, `>0` + floor; miss → `RequestLoadItemDataByID` prime + nil → literal); text `1020-1053` (link-or-`item:<id>` literal, suffix in muted tone, never a spinner); dots `1059-1086` (enchant complete+nonzero; sockets capacity>0 all-filled); dots widgets `1149-1165` (gold/green, hidden default); render loop `1254-1278` (suffix+dots only on live revision; persisted leg dim literals, dots forced hidden). |
| W9 Up/Down entry-anchored focus, Enter opens entry, empty no-op | yes | focus state `115-119` (entry identity + lastView); re-anchor `1451-1464` (guid match or clear — never stale index); `moveFocus` `776-813` (empty view → return; clamp; scroll-into-view; `UpdateUI`); `OnKeyDown` `2074-2093` (`IsShown` guard, Up/Down/Enter only, `SetPropagateKeyboardInput(false)` only while handling, behind `widgetMethod` guard). Enter on empty/re-sorted: `focusedEntry` nil → no-op `[V]` by reading. |
| W10 ButtonFrameTemplate + Backdrop fallback, no child assumed | yes | `1689-1704` (3-level: ButtonFrame → Backdrop → plain; `templateOK` flag); title `1742-1751` (reuse `$parentTitleText` if table, else build); close `1753-1757` (only if template lacks one); geometry via `chromePad` (`28`/`0`, single definition `:1721`) + `rowHeight()/rowTop()/controlTop()/headerTop()` (`:151-165`) — no hardcoded-28px survivors `[V]` (grep). |
| W11 density 26↔32, default compact, existing settings table | yes | read-once `1706-1720` (`Core.GetSettings` pcall, `comfortableRows == true` strict — absent/non-boolean → compact); `RebuildUI` `2226-2251` (teardown + rebuild, filters/sort/jump survive, focus cleared); Options checkbox + help `Options.lua:1251-1270` + `HELP 128-133` (boolean into existing `settings`, `pcall(RebuildUI)`). No new SV table `[V]` (grep: no `SavedVariables`/new root in Stage-5 files). |
| W12 virtualization | **absent, as required** | zero `HybridScrollFrame`/`ScrollBox`/virtual hits in Stage-5 files `[V]` (grep); harness records NOT-APPLICABLE with Q1 evidence (`rankbrowser_test.lua:2163-2166`). Default-do-not-ship respected. |

**Deviations** (section5 journal §13, all accepted): Core.lua untouched (reads `comfortableRows == true` directly — identical semantics to `defaultBoolean`); no `ITEM_DATA_LOAD_RESULT` wiring (suffixes appear on next open after priming — bounded, documented); W7 `>=` without the +300 clamp (skew ticks, never errors); W8 dots gold/green reuse tooltip tones; W6 wording `"%d players | Top %d | Avg %d"` (new enUS key, per-key fallback); tooltip lines in all three modes (brief §2.2 silent on mode — trailing in Minimal/Compact/Detailed is the consistent reading); 5b/5c production landed in one construction pass (slice gates remain check-based — accepted, checks are per-slice).

---

## 2. Hard invariants (all hold `[V]`)

- **Zero wire bytes:** `grep SerializeRecord/RECORD_FIELDS/WIRE_VERSION` across `RankBrowser.lua`, `Tooltips.lua`, `Options.lua`, `Locale/enUS.lua` → zero hits. Stage-5 symbols in the `RankSync.lua`/`RankDB.lua` uncommitted diff → zero hits (that diff's `guildFilter` hunk is Stage 3's). No `G;`/`D;` grammar, stride, version, or door touch anywhere in the Stage-5 hunks.
- **No new SavedVariables:** density is one boolean (`comfortableRows`) in the existing settings table (`Options.lua:1261`, read at `RankBrowser.lua:1715`); `grep SavedVariables|TacoTipExtrasDB =` in Stage-5 files → nothing new (one comment line only).
- **No RankSync/RankDB schema change from Stage 5:** reads only (`GetLeaderboard`, `GetPlayerRank`, `GetRecord`, `GetGear`, `ParseGearIDs`, `StoreGear` in harness, `HandlePayload` in harness, `GetDebugState` shape-identity check). No new counters — check 17 pins the verbatim 14-bucket `countOutcome` union plus top-level key identity.
- **W12 absent entirely** (see table). No `WHISPER` string in any Stage-5 file `[V]` (grep).

---

## 3. Hole-by-hole (the brief's hunt list)

- **H1 SearchBox fallback vs Backdrop precedent — SHAPE NIT (M2).** Backdrop wraps every level in pcall down to a plain frame; search wraps only the `SearchBoxTemplate` attempt — the `InputBoxTemplate` fallback is a bare `CreateFrame`. Both-missing raises instead of degrading. In-game risk nil (InputBoxTemplate predates Stage 5 on all five clients; brief verified SearchBoxTemplate ×5), harness covers fallback-half. One-line hardening available (wrap the fallback), not required for merge.
- **H2 Debounce flush — CLEAN.** Single-shot coalescing (`searchFlushPending`); rapid typing schedules once and flushes the latest `currentSearch` — no stale render, no timer accumulation. Post-`RebuildUI` stale fire renders current state once. `RebuildUI` resets the flag; a pre-rebuild timer firing post-rebuild is a single harmless `UpdateUI`.
- **H3 CUSTOM_CLASS_COLORS hostile values — CLEAN.** `type(custom)=="table"` gate + per-channel `type()==number` gates; string/nil/number CUSTOM, non-table entries, partial entries all degrade to RAID/hard/grey. Harness pins the `"junk-string"` case. (`getClassColor(nil)` would raise on `custom[nil]` — identical to the pre-existing `CLASS_COLORS[nil]` shape, no regression, not filed.)
- **H4 Keyboard Enter on empty/re-sorted — CLEAN.** Empty view: `moveFocus` early-returns, `focusedEntry` stays nil, Enter no-ops. Re-sort/filter-out: `UpdateUI` re-anchors by guid or clears to nil — Enter can never open a stale row. Harness pins empty-no-op + re-sort survival by entry identity (`Player-1-00000001` after iLvl re-sort).
- **H5 Density 26↔32 math — CLEAN.** Single-point parameterization (`currentRowHeight`, `chromePad`, four accessors); grep shows no other `28` consumer. Gear-panel 22px rows are a separate surface, correctly untouched (density is browser-only per brief). Harness pins 26 → 32 → 26 with identical content.
- **H6 Gear suffix prime loop — CLEAN (bounded by construction).** Miss → one `RequestLoadItemDataByID` + literal render; no timer retry, no `ITEM_DATA_LOAD_RESULT` wiring (journaled). Cost is ≤17 priming calls per panel open, client-throttled and idempotent — not a storm. Numeric-rejecting clients degrade to literals via the same path (Q3 open, in-game).
- **H7 Tooltip lines, three modes, confirmed-empty vs not-scanned — CLEAN per spec.** `GetRankExtraLines` (`Tooltips.lua:811-850`) in Minimal (`:897`), Compact (`:952`), Detailed (`:1162`); no-rank → neither line; fresh (`ts >= sessionStart`) or `ts==0` → no freshness line; gear `known==0` → no gear line, never a "no gear" message. Confirmed-empty and not-scanned both render silence — correct per brief §2.2 (absence of data is not data). Inputs flow through `captureRenderInputs` (`:1229-1234` rankTimestamp + gearSlots) so the change gate covers both lines `[V]`.
- **H8 Strip hidden-while-loading — CLEAN.** No explicit `loading` flag exists; the invariant holds structurally (strip created hidden, only `UpdateUI` shows it, `totalCount==0` hides it). Source of truth = "has painted a nonzero pool".

---

## 4. Tests — do the 17 checks assert what they name, do they fail pre-fix?

16 landed + W12 recorded NOT-APPLICABLE = 17 named `[V]` (sections at `rankbrowser_test.lua:1608/1916/2161`, check 16 in `load_test.lua:5415+`). Judged by reading (production files untouched per read-only scope — no spot-revert performed; noted explicitly so the claim is checkable, not overstated):

- Checks 1–7 assert Stage-5-only surfaces (`__template` tags, `__atlas`, `__highlightTexture`, seeded RAID colour, pending-timer no-render-yet, strip text/visibility, `freshTick` visibility) — nil/absent pre-fix, so each fails pre-fix by construction. Degradation halves (fallback template, hidden icons, hard-table colour, sync search, empty-strip-hide, all-old-no-ticks) pin today's look.
- Check 8 (Stage-3 regression guard) passes both sides by design — correctly so.
- Checks 10–11 assert `ButtonFrameTemplate` tag + fallback rows, 26/32/26 heights with identical content — fail pre-fix (no template tag, fixed 26).
- Check 13 asserts the `(213)` suffix beside `item:12345`, the uncached `item:99999` literal with no parens and no spinner, persisted literals + `Last synced`, and unscanned `has not been scanned` — fail pre-fix (no suffix path). Section5's journal records a live spot-revert (`if false and …` → suffix half FAILS, restored green), corroborating non-vacuity.
- Check 14 asserts dots shown/hidden per session cells and forced-hidden on persisted — fail pre-fix (no dot textures).
- Check 15 re-pins the Stage-4 `D`-ingest path under Stage-5 panel edits (guard against panel-edit regression).
- Check 16 (load_test) asserts old-row freshness line + muted colour, fresh-row silence, no-rank silence, `Gear: 2/17 slots` count-never-IDs from both revision and persisted — fail pre-fix (`GetRankExtraLines` absent; seam check first).
- Check 17 asserts top-level `GetDebugState` key identity + the verbatim 14-bucket outcome union — fails on any new Stage-5 counter.
- Check 9 (keyboard) asserts Down/Down/Up/Enter entry identity (`…000001/…000002/…000001`), empty-list no-op, and re-sort survival by guid — fail pre-fix (no `OnKeyDown` focus machinery).
- Suite re-run here: rankbrowser 221 checks / 0 failed implied by green `TOTAL 42/42`; `LINT=1` 0/0 `[V]`.

---

## 5. CHANGELOG accuracy (Stage-5 subsection vs code, claim-by-claim)

Accurate throughout: zero-wire/zero-persisted-bytes header (verified §2); search paragraph (template + fallback + 0.2s + sync leg — matches `1789-1818`); icons/colour paragraph (dropdown icons, 14px atlas, guarded `GetClassAtlas`, CUSTOM-guard→RAID→hard chain, QuestTitleHighlight — matches); strip/tick paragraph (pool/top/avg from rows in hand, hidden loading+empty, 2px brand tick — matches); chrome/density/gear/tooltip/keyboard paragraph (fallback chrome with no assumed child, 32/26 one-boolean, display-resolved iLvl with persisted dim literals + last-synced note, two trailing muted lines under the render gate, entry-anchored keys with empty no-op — matches; notably the persisted leg is correctly split as literal-only, avoiding the Stage-4 F3 overclaim); W12 non-ship with the sort-cost reason (matches code absence); harness paragraph (seventeen named incl. NOT-APPLICABLE virtualized check, suite + lint — matches this audit's rerun). **No correction needed.**

---

## 6. In-game-only additions (operator's single final pass)

Screenshots on one Classic + one Mainline client: 5a browser (search affordance, icons, strip, ticks), 5b chrome + density OFF vs ON, gear panel session vs persisted, tooltip trailing lines in all three modes. Carries, still open: Q2 portrait content; Q3 numeric-ID `GetItemInfo` per client; Q4 arrow-vs-chat per family (HasRestrictions on era); Q5 Classic remote enchant/gem cells; Q6 strip content (mean vs median); Q8 fresh-tick window; plus Stage-3/4 carries (guild-length distribution, G-responder first live answer, 65+-sender ring, dim+age sufficiency).

---

## 7. Carry-forward + concurrency

- Prior audits absorbed: stage1/2 + diet (transport rules, whisper deletion), stage34 (F1–F7 resolved per fix-stage34-followups journal; F5's `GetRemote`-vs-fresh note still stands for the panel's next touch — Stage 5 did not change the session leg's freshness source).
- Locale parity: enUS carries exactly the 3 Stage-5 keys (`LB_TIP_RANK_SYNCED`, `LB_TIP_GEAR_DEPTH`, `LB_STAT_STRIP`); all 10 other locales carry 0 of 3 — per-key English fallback, invariant holds `[V]`.
- Unresolved ownership (M1): the tooltip Compact 14px class-icon + short `GS Rank:` label hunks (`Tooltips.lua` `getRankRow` mode param + icon branch; `TOOLTIP_LABEL_RANK` shortened consistently in all 11 locale files) are harness-pinned (`load_test.lua:5217-5271` + label checks) yet unbriefed (§2.2 allows trailing lines only) and unjournaled by every desk I read (locale-tier-a-keys explicitly attributes the label edit to "another desk"). Safe code, certification gap — §8.

## 8. Findings (severity-ranked)

- **M1 (major, process — blocks clean sign-off, not the code): unattributed tooltip-polish hunks in the audited files.** Compact-mode 14px class icon (`|A:atlas:14:14|a`, no class tint, white-bracket close) + short `GS Rank:` label + `getRankRow(guid, unit, mode)` signature, with `TOOLTIP_LABEL_RANK` shortened in all 11 locales (consistent GS-forms, parity-safe). Harness-pinned and guarded (falls back to class name without `GetClassAtlas`), display-only, zero wire/storage — but unbriefed and unjournaled. Fix: one journal entry from the owning desk (most plausibly section5 as W2 spillover) claiming it, or a one-line brief addendum; then this finding closes with no code change.
- **m2 (minor): search fallback skips the Backdrop precedent's final pcall.** `RankBrowser.lua:1793` bare `CreateFrame(... "InputBoxTemplate")` — both-templates-missing raises. In-game nil risk; harden with a pcall + plain-EditBox last resort when nearby, or record as accepted.
- **m3 (minor, observation): suffix visibility lags one open behind priming.** No `ITEM_DATA_LOAD_RESULT` wiring (journaled Core.lua-scope call) — first open after sync primes, second shows suffixes. Documented behavior; wire the event path when Core scope allows.
- **m4 (observation, no action): `GetDebugState` shape-identity check pins the 14-bucket union verbatim** — future transport buckets must update check 17's allowlist alongside; the check comment already says so.

## Outcome ratings (issued as signals alongside this report)

- **Stage 5: quality 4, effort_to_merge minimal.** Faithful W1–W11 implementation, invariants exact, suite + lint green, changelog accurate; M1 needs an ownership entry, m2 an optional one-liner. Issues: `["unattributed tooltip-polish hunks (Compact icon + GS Rank label) need owning journal entry", "search fallback missing final pcall (shape nit)", "suffix lags one open behind priming (journaled, Core-scope followup)"]`.
