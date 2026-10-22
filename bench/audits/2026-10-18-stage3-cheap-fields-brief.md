# Stage 3 — cheap expanded fields: implementation-ready brief

- **Date:** 2026-10-18
- **Desk:** `stage3-prep` (bench-only authoring; no code touched)
- **Parent spec:** `bench/audits/2026-10-18-extras-rank-storage-expansion.md`
  §6.2 Stage 3 + §4 cheap fields + §6.3 perf budget + §6.4 all-client concerns,
  as corrected by `bench/audits/2026-10-18-stage1-and-tier-a-oracle-audit.md`
  (whisper fallback dropped: same-transport answers only, counted silent skip).
- **Evidence labels (CAIRN.md):** `[V]` VERIFIED (read in source or produced by a
  command I ran), `[A]` ASSUMED (says what would verify), `[U]` UNKNOWN.

---

## 0. Load-bearing assumption: the wire-diet stride lands first

This brief **assumes the section2b-wire-diet target shape lands exactly as
scoped**: wire record
`(version, guid, name, classID, gs, ilvl, timestamp, specID)` —
versioned stride, faction / realm / class-string / spec-name OFF the wire,
numeric `specID` ON the wire, inbound records filed under the LOCAL realm
(`desks/section2b-wire-diet/journal.md` purpose line `[V]`).

**Reconcile note (updated mid-authoring):** the diet desk landed while this
brief was being written — verified in the working tree before finalizing:
`local WIRE_VERSION = "1"` (`TacoTip_Extras/RankSync.lua:165`), 9-field
stride `R;<ver>;guid;name;classID;gs;ilvl;timestamp;specID`
(`TacoTip_Extras/RankSync.lua:167-180`, `RECORD_FIELDS = 9` at `:192`),
version-gated refusal (`DeserializeRecord`,
`TacoTip_Extras/RankSync.lua:223-229`; `recordFromParts`,
`TacoTip_Extras/RankSync.lua:754-762`, refusal counted as `versionReject`)
`[V]`.
**Reconcile-on-dispatch rule:** the Stage 3 implementer MUST still re-grep
`WIRE_VERSION`, `RECORD_FIELDS`, `SerializeRecord`, `recordFromParts`, and
`ingestRecords` before touching indices. If the diet shape moved again after
this brief, this brief's positional math moves with it — the byte budgets and
rules do not.

Consequences of the assumed shape that this brief relies on:

1. `specID` is **already on the wire** — Stage 3 adds spec *capture* and
   *render localization*, not a wire field for it.
2. There is **no realm on the wire** — guild filtering is implicitly
   within-realm (guild names are unique per realm), so no realm+guild
   composite key is needed.
3. `faction` and class-string are gone — the browser's class filter keeps
   working off the stored `class` DB field and numeric `classID`; nothing in
   Stage 3 re-adds them to the wire.
4. Any older stride version is refused, not inferred (same rule the diet
   enforces — `versionReject` at `TacoTip_Extras/RankSync.lua:223-229,754-762`).
   Stage 3 extends the versioned stride **once, pre-release** — never a
   second concurrent stride.

---

## 1. Proposed stride

### 1.1 The stride (13 `;`-separated fields, token + version included)

```
R;<ver>;guid;name;classID;gs;ilvl;timestamp;specID;guild;level;pvpRank;arena
```

Diet baseline (landed `[V]`): `R;<ver>;guid;name;classID;gs;ilvl;timestamp;specID`
with `WIRE_VERSION = "1"` (`TacoTip_Extras/RankSync.lua:165-180`) and
`RECORD_FIELDS = 9` (`TacoTip_Extras/RankSync.lua:192`). Stage 3 appends four
fields and bumps the version to `"2"` — the version-gate refusal both ends
already enforce (`TacoTip_Extras/RankSync.lua:223-229,754-762`) makes this a
clean break, never a dual-stride negotiation.

| # | field | type / rule | why |
|---|---|---|---|
| 1 | `R` | literal record marker (diet shape) | stride framing |
| 2 | `<ver>` | `"2"` (bump from diet `"1"`) | stride version; anything else refused + counted (`versionReject`) |
| 3 | `guid` | string ≤128, sanitized | identity (existing rule, `TacoTip_Extras/RankDB.lua:209` `ValidateRecord`) |
| 4 | `name` | string ≤64, sanitized | display (existing rule) |
| 5 | `classID` | number (diet shape) | class filter + spec localization key |
| 6 | `gs` | number | sort key |
| 7 | `ilvl` | number | second sort key |
| 8 | `timestamp` | number | arbitration + staleness |
| 9 | `specID` | number, `0` = unknown (diet shape; empty-on-wire when 0, `TacoTip_Extras/RankSync.lua:167-180`) | localized at render (§3.3); never a name on the wire |
| 10 | `guild` | string ≤**24**, sanitized, `""` = unknown | §1.3: the expensive one; hard cap |
| 11 | `level` | number, `0` = unknown | §2.2; `UnitLevel` already read at `TacoTip_Extras/Scanner.lua:199` |
| 12 | `pvpRank` | number, `0` = none/unknown | Classic Era honor rank only (§2.4) |
| 13 | `arena` | number, `0` = none/unknown | TBC/Wrath inspectable arena best only (§2.4); Retail/Forever always `0` on the wire |

`RECORD_FIELDS` becomes **13** (9 → 13). `SerializeRecord`
(`TacoTip_Extras/RankSync.lua:167`), `DeserializeRecord`
(`TacoTip_Extras/RankSync.lua:223-229`), `recordFromParts`
(`TacoTip_Extras/RankSync.lua:754-762`), and the ingest stride loop
(`TacoTip_Extras/RankSync.lua:788`, `index + RECORD_FIELDS - 1`) all move
together — they are deliberately duplicated, not shared (comment at
`TacoTip_Extras/RankSync.lua:183-192`), so a four-site edit is the
correct shape, not a refactor. `WIRE_VERSION` becomes `"2"`; the
`versionReject` counting stays as-is.

### 1.2 Byte cost per field × N records against the 240-byte door

Door: `MAX_PAYLOAD_BYTES = 240` enforced at enqueue
(`TacoTip_Extras/RankSync.lua:22`, `TacoTip_Extras/RankSync.lua:454-462`)
`[V]`. Engine limit behind it: 255 printable chars; Blizzard's own code
budgets 250 (`Blizzard_CooldownBroadcaster.lua:6` classic_era, `:8` live;
packed at `:25` / `:27`) `[V]`.

Typical-value arithmetic (separators counted):

| field(s) | typical chars | notes |
|---|---|---|
| `R` + `<ver>` | 3 | `R;1`-shaped framing (diet: `TacoTip_Extras/RankSync.lua:167-180`) |
| `guid` | 22 | e.g. `Player-1234-ABCDEF12` (19–24 observed) |
| `name` | 8 | typical; validator-max 64 |
| `classID` | 2 | `1`–`32` |
| `gs` | 4 | e.g. `3821` |
| `ilvl` | 3 | e.g. `125` |
| `timestamp` | 10 | server-time epoch |
| `specID` | 2 | `0`–`NNNN`; `0` is 1 char |
| `guild` | 12 typical / **24 hard-capped** | §1.3 |
| `level` | 2 | `1`–`80`/…; `0` is 1 char |
| `pvpRank` | 1–2 | single rank number; `0` is 1 char |
| `arena` | 4 typical / `0` when none | e.g. `2100`; `0` is 1 char |
| separators | 12 | one per gap (13 fields) |
| **record total** | **≈85 typical** | |

Framing:

| message | typical bytes | fits 240? |
|---|---|---|
| `R;<ver>;…` record alone | **≈85** | yes, 155 headroom |
| `S;<6-hex-id>;<record>` | **≈94** (`S;`+6+`;` = 9 framing) | yes |
| `T;<6-hex-id>;<rec>;<rec>` two typical | **≈180** (2+6+1+85+1+85) | yes, 60 headroom |
| `T` + two validator-max-shaped (64-char name, 24-char guild, 128-char guid) | **≈270+** | **no → digest-split fires** |

The last row is the point: validator-max rows still exceed the door, and that
is **handled, not prevented** — the Stage-1 split logic
(`TacoTip_Extras/RankSync.lua:706-740`, both-halves-travel incl. the
self-caught second-record fix) already degrades a fat pair into two singles,
and the enqueue door (`TacoTip_Extras/RankSync.lua:454-462`) refuses anything
still over 240 with a counted `enqueueOversize`. Stage 3 MUST NOT add a new
size path around these two — it only makes rows fatter inside them. Harness
must prove a `T` of two fully-expanded typical records stays ≤240 and a
validator-max pair still splits-or-refuses (§5).

### 1.3 Guild is the expensive field — truncation/cap rule

Measured precedent: adding guild alone moved the SavedVariables model
205 → 238 bytes/record (+33 at 20k = +0.6 MiB) `[V]` (expansion §2.3). On the
wire a 15-char guild is ~15 bytes — over 60% of the growth from diet shape
(≈70 wire bytes) to Stage-3 typical (≈85).

**Rule (normative for the implementer):**

1. Sanitize exactly like every other string field (strip `;` and controls —
   same `sanitizeString` path as `ValidateRecord`,
   `TacoTip_Extras/RankDB.lua:209`) `[V]`.
2. **Truncate to 24 chars** (`guild:sub(1,24)` post-sanitize; 24 covers every
   realistic guild name with margin and bounds the worst case at 24 wire
   bytes + the field's share of separators).
3. **Value-test:** store/transmit `""` when the result is empty, nil, or
   whitespace-only. Empty guild is data (unguilded), not absence — the
   positional parser keeps empty fields (`splitFields` keeps empties;
   comment + measured empty-spec case at `TacoTip_Extras/RankSync.lua:194-209`) `[V]`.
4. Never pad, never `"Unknown"`-fill: `"Unknown"` is 7 bytes of noise that a
   filter would then have to special-case. `""` renders as "—"/blank.

Wire worst case with the cap: 128 (guid) + 64 (name) + 24 (guild) + ~30
(numbers/token/version) + 12 separators ≈ **258 → refused/split by existing machinery**.
That is correct behavior — the cap bounds the *typical* cost; the door bounds
the *adversarial* cost. Do not raise the door for guild.

---

## 2. Scan-capture additions (per field)

All capture lands in `queueRankSync`
(`TacoTip_Extras/Scanner.lua:112`) `[V]`, which already receives
`(guid, unit, classToken, result, sourceTag)` and already reads `UnitLevel`
(`TacoTip_Extras/Scanner.lua:199`) for the revision `[V]`. Feature-detect
everything; gate nothing on client identity (repo rule, expansion §6.4.7).

### 2.1 Guild — `GetGuildInfo`, self at scan time

- **API:** `GetGuildInfo(unit)` → `guildName, rankName, rank`. Blizzard usage
  on all five branches, always with `"player"` in the sampled call sites:
  `Blizzard_CharacterFrame/Vanilla/PaperDollFrame.lua:95` on classic_era,
  classic_anniversary, classic_titan (`local guildName, title, rank =
  GetGuildInfo("player")`) `[V]`; `Blizzard_FrameXML/InstanceDifficulty.lua:219`
  (forever), `:216` (live) (`local guildName = GetGuildInfo("player")`) `[V]`.
- **Availability:** `"player"` on all five `[V]` (usage). Remote-unit form
  (`GetGuildInfo("target")`/inspect token) is `[A]` — no Blizzard call site
  sampled passes a non-player unit; the implementer verifies in game whether
  an inspect target's guild resolves. **Capture rule:** call
  `GetGuildInfo(unit)` pcall-guarded for the scanned `unit`; accept only a
  non-empty string first return; else `""`. For the local `"player"` scan this
  always resolves `[V]`; for remote inspects it resolves-or-blanks, never
  raises. Do NOT add a roster lookup or a second event registration to chase
  remote guilds — blank-until-next-scan is the specified degradation.
- **Value test + cap:** §1.3 rules 1–4. `ValidateRecord`
  (`TacoTip_Extras/RankDB.lua:209`) gains `guild = sanitizeString(record.guild,
  24) or ""` — additive, old rows default `""`.

### 2.2 Level — `UnitLevel`, already in hand

- **API:** `UnitLevel` documented on all five (`UnitDocumentation.lua:2817`
  classic_era, `:2474` forever, `:2385` live) `[V]`; already called in the
  scanner (`TacoTip_Extras/Scanner.lua:199`) `[V]`.
- **Capture rule:** reuse the existing read. Store the level only when
  `type(level) == "number" and level >= 1`; else `0` (unknown). The `-1`
  un-inspectable-unit case is `[A]` (audit §4.5) — the `>= 1` test absorbs it
  without branching on its meaning. No new Blizzard call, no new event.
- **Wire:** `tostring(level or 0)`; `0` parses back via `tonumber(...) or 0`.

### 2.3 Spec — numeric `specID` (diet wire field); Stage 3 = capture + render

- **No new wire field.** The diet stride already carries `specID`; Stage 3
  fills it honestly on every client and localizes it at render (§3.3).
- **Modern (Retail/Forever):** engine path exists —
  `C_SpecializationInfo` used by the vendored library
  (`Libs/LibForeverInspector/LibForeverInspector.lua:3219`,
  `pcall(C_SpecializationInfo.GetSpecialization, …)`) `[V]`, with `specID`
  threaded through (`:3182-3189`, `:3297`, `:3677`) `[V]`. The scanner today
  calls only `inspector.GetLocalizedSpecName`
  (`TacoTip_Extras/Scanner.lua:159-162`; implementation at
  `Libs/LibForeverInspector/LibForeverInspector.lua:5279`) `[V]`, which is why
  classic clients publish `""`. Capture rule: prefer a numeric specID source
  (library helper or new thin wrapper returning the id); fall back to `0`.
  Never derive the id by string-matching the localized name.
- **Classic Era / TBC Anniversary / Titanforge:** talent-tab path. The library
  wraps `GetTalentInfo` (`Libs/LibForeverInspector/LibForeverInspector.lua:3064-3068`)
  `[V]` with a per-class accessor (`:3003`, `GetTalentInfoByClass`) `[V]` and
  documents the deliberate `GetNumTalentTabs` non-capture (`:34-48`) `[V]`.
  Capture rule: dominant-tab = spec index for the class; resolve to the
  engine spec id via `GetSpecializationInfoForClassID(classID, index)`
  (documented on all five: `SpecializationSharedDocumentation.lua:10`)
  `[V]`; whether it returns TBC/Wrath tree names on those clients is `[A]`
  (expansion §4.4 — verify in game; if it returns nothing useful, store the
  tab index tagged distinctly from modern ids? NO — see open question Q3;
  default until answered: store `0` rather than invent an encoding).
- **Value test:** `specID` is `0` unless a positive numeric id resolved.
  `0` renders as the class token (existing fallback,
  `TacoTip_Extras/RankBrowser.lua:370-380,486-500`) `[V]`.

### 2.4 PvP snapshot — per-client, advisory, inspect-gated

Divergence is the whole story here; one rule per client family:

- **Classic Era (11509) — honor rank, inspectable `[V]`:**
  `Blizzard_InspectUI/Vanilla/InspectHonorFrame.lua` (gated
  `[AllowLoadGameType vanilla]`, TOC `:14-15`) requests-then-waits:
  `HasInspectHonorData` / `RequestInspectHonorData` (`:6-10` on the live copy
  of the same vanilla file; Classic-family `Classic/InspectPVPFrame.lua:17-18`
  identical) `[V]`; `GetInspectHonorData()` returns 12 values with
  `lifetimeRank` 12th (`:20` / Classic `:234`) `[V]`;
  `GetPVPRankInfo(lifetimeRank)` + `UnitPVPRank("target")` (`:41`, `:48`)
  `[V]`; progress `GetInspectPVPRankProgress()` (`:72`) `[V]`. Capture:
  `pvpRank = lifetimeRank` (the rank **number**, 0–14, 1–2 wire chars) when
  `HasInspectHonorData()` is already true at scan-complete time; else `0`.
  Do NOT stall the scan on `INSPECT_HONOR_UPDATE` — a follow-up scan fills it
  in. (Registering the event to trigger a re-store is optional polish, not
  Stage 3 scope; see §6 boundary.)
- **TBC Anniversary (20506) / Titanforge (38002) — arena best, inspectable
  `[V]`:** `Classic/InspectPVPFrame.lua` (gated `[AllowLoadGameType tbc,
  wrath, cata]`, TOC `:16-17`) `[V]`: team path `GetInspectArenaTeamData(i)`
  → `playerRating` (`:157`) `[V]`; teamless path `GetInspectArenaData(index)`
  → `rating` (`:66`) `[V]`; seasonal gate `GetCurrentArenaSeasonUsesTeams()`
  (`:34`) `[V]`; player-side `GetArenaTeam(i)` used by
  `Blizzard_UIPanels_Game/Classic/PVPFrameBase.lua:53,61,92` `[V]`. Capture:
  `arena` = max `playerRating`/`rating` across brackets when honor data is
  present; else `0`. Honor `lifetimeRank` also available (`:234`) — MAY also
  fill `pvpRank` on these two clients with the same value-test.
- **Retail (120105) / Forever (16001) — DO NOT SYNC.** `GetPersonalRatedInfo`
  is self-only (`Blizzard_PVPUI/Mainline/Blizzard_PVPUI.lua:1372,1623` on both
  branches; TOC `AllowLoadGameType: mainline`) `[V]`; own honor via
  `UnitHonor`/`UnitHonorLevel` (`Blizzard_ActionBar/Mainline/HonorBar.lua:8-10`
  live; `Blizzard_FrameXML/PVPHonorSystem.lua:177-180` forever) `[V]`.
  Wire rule: both fields `0`, always. Browser MAY show the *local player's
  own* rating from the local API with a "self" tag (display-only, §3.2) —
  never a synced value, never labeled as inspected.
- **Freshness:** PvP is a snapshot with the record's own timestamp — no
  separate timestamp field (bytes). Decays weekly in reality; the 60-day
  prune (`TacoTip_Extras/RankDB.lua:589`) bounds its worst age. Do not include
  PvP in the digest preference (digest = top-by-GS,
  `TacoTip_Extras/RankDB.lua:528` `GetTopRecords`) — it rides the record on
  change only.

### 2.5 What is deliberately NOT captured in Stage 3

Talent points per tab, achievements, professions, zone, item names/links,
enchants/gems — per expansion §4.5 verdicts (all `[V]` source-scoped). In
particular: **no `specIcon` revival** (unbounded string, dead on the wire
before — expansion §1 table row) and **no `classID`-as-display** (numeric key
only). Anything in this list arriving in a Stage-3 diff is out of scope on
sight.

---

## 3. Browser changes

File: `TacoTip_Extras/RankBrowser.lua` (columns `TacoTip_Extras/RankBrowser.lua:45-51`;
data fetch `TacoTip_Extras/RankBrowser.lua:890` via
`RankDB.GetLeaderboard(nil, "All", currentClass, currentSearch)`;
spec render `TacoTip_Extras/RankBrowser.lua:486-500`; empty states
`TacoTip_Extras/RankBrowser.lua:980-991`) `[V]`.

### 3.1 Guild filter

- **Control:** text input reusing the existing search-box pattern (live
  `OnTextChanged` → re-render; cf. search wiring). NOT a dropdown: a
  distinct-guild dropdown on a 20k realm is unbounded UI (hundreds of entries)
  and needs its own population/cap logic — text match is O(1) chrome.
- **Predicate:** guild substring, case-insensitive plain find — the same shape
  as the existing name search (`RankDB.GetLeaderboard`,
  `TacoTip_Extras/RankDB.lua:547`, `hasQuery`/`queryPattern` plain-find
  path) `[V]`. Signature becomes
  `GetLeaderboard(realm, tab, classFilter, searchQuery, guildFilter)` with
  `guildFilter` optional-positional (nil = unchanged behavior; every existing
  caller keeps working).
- **Empty-state interplay:** guild filter active + zero rows → the existing
  `LB_EMPTY_FILTERS` path (`TacoTip_Extras/RankBrowser.lua:980-991`) `[V]` —
  no new empty string needed.

### 3.2 Level column + filter

- **Column:** extend `COLUMNS` (`TacoTip_Extras/RankBrowser.lua:45-51`) with a
  narrow `level` column (width ≈36, RIGHT justify, new locale key + English
  fallback per the file's own `label`/`fallback` convention,
  `TacoTip_Extras/RankBrowser.lua:39-44`) `[V]`. Renders `""` (blank) when
  `level == 0` — old rows stay clean.
- **Filter:** minimum-level semantics is NOT specified here (open question Q4)
  — default recommendation: no level *filter* control in Stage 3, column only.
  Rationale: sort-by-level already answers "who is max-level nearby" via the
  existing sortable-column machinery (`SORTABLE_COLUMNS`,
  `TacoTip_Extras/RankBrowser.lua:262-268`) `[V]`; a filter control doubles
  the predicate surface for unproven demand.
- **Sort:** add `level` to the sortable set if trivially composable with
  `sortAsc` (`TacoTip_Extras/RankBrowser.lua:267-268`) `[V]`; keep the `#`
  GearScore-rank invariant (pinned by the `#`-column invariant checks,
  e.g. `rankbrowser_test.lua` ascending/descending assertions) `[V]`.

### 3.3 Localized spec token at render

- **Rule: store the id, localize at render** (expansion §4.4 verdict) `[V]`.
  Resolver (pcall-guarded, cached per session in a module-local table):
  1. `GetSpecializationInfoForClassID(classID, index)` loop over indices
     1..N, match first return (`id`) against stored `specID`
     (documented all five, `SpecializationSharedDocumentation.lua:10`) `[V]` —
     N is small (3–4); cache hit makes repeat rows free.
  2. Library `spec_table` (`Libs/LibForeverInspector/LibForeverInspector.lua:234`)
     `[V]` reverse lookup by id.
  3. Fallback chain (existing): `L["CLASS_" .. classToken] or classToken`
     (`TacoTip_Extras/RankBrowser.lua:486-500`) `[V]`; `specID == 0` skips
     straight to fallback.
- **No locale keys for spec names** — they come from the client API already
  localized. This keeps the locale-tier-a-keys desk untouched (parity rule:
  no locale defines a key enUS does not,
  `TacoTip_Extras/Tests/harness/load_test.lua:1575-1588`) `[V]`.
- **Column header keys** (`LB_COL_GUILD`, `LB_COL_LEVEL`, and any filter
  label) ARE new locale keys: enUS-first with per-key English fallback
  (`TacoExtrasApplyLocale`, `TacoTip_Extras/Locale/enUS.lua:318-355`) `[V]`,
  translations follow via the locale desk — never in the Stage-3 diff itself.

### 3.4 PvP display (advisory labeling)

- Era/TBC/Wrath rows: render `pvpRank` as the rank name via
  `GetPVPRankInfo` (pcall) or the raw number when the API is absent;
  `arena` as the raw rating number. Both muted/small — advisory data, never
  styled as authoritative as GS.
- Retail/Forever rows: synced `pvpRank`/`arena` are always `0` → render
  nothing from sync. The local player's own row MAY append the local
  `GetPersonalRatedInfo`/`UnitHonorLevel` value tagged "self" (display-only).
  Never render another player's self-reported rating — there is no verified
  data to render (expansion §4.3) `[V]`.

---

## 4. Storage growth vs the §6.3 budget

Budget (expansion §6.3): `MAX_CAPACITY = 20000`
(`TacoTip_Extras/RankDB.lua:25`) `[V]`; target ≈6 MiB `ranks`, ≤0.5 MiB gear
(Stage 4, untouched); `StoreRecord` amortized ≤0.5 ms; first-read rebuild
unchanged; wire record ≤113 B with new fields; send rate ≤1 msg/s.

SavedVariables model deltas (model from expansion §2.3, within ~10% of the
repo's own 276-byte claim `[V]`):

| shape | bytes/record (model) | 20,000 records |
|---|---|---|
| current minus dead fields (Stage 2) | 205 | 3.9 MiB |
| + guild (capped 24) | ≈238 | 4.5 MiB |
| + guild + level + specID + pvpRank + arena | **≈280–310** | **5.3–5.9 MiB** |
| budget | — | **≈6 MiB** |

Stage 3 lands **inside budget with margin** — provided the guild cap (§1.3)
holds and no further field is added without re-running this table. The
per-record growth over Stage 2 is ≈75–105 bytes file-side (field names +
quotes dominate: `["guild"]`, `["level"]`, `["specID"]`, `["pvpRank"]`,
`["arena"]`); wire-side only ≈14 typical bytes because the wire carries
values without keys.

Enforcement (no new machinery):

- Count cap unchanged: `MAX_CAPACITY` + amortized accounting
  (`TacoTip_Extras/RankDB.lua:25,276-392`) `[V]`; age prune unchanged
  (`PruneStaleRecords`, `TacoTip_Extras/RankDB.lua:589`; login sweep
  `PruneAllRealms`, `:635`; `Core.lua` scheduler `:175-181`) `[V]`.
- No byte budget for `ranks` (optional per expansion §2.2 — explicitly NOT
  recommended). If the file ever trips `SAVED_VARIABLES_TOO_LARGE`, the
  existing aggressive-prune path answers (`TacoTip_Extras/Core.lua:815-867`,
  `RankDB.PruneAggressive`, `TacoTip_Extras/RankDB.lua:687-694`) `[V]`.
- Old rows: additive migration — absent fields default (`""`/`0`), old rows
  render blanks, refreshed-or-pruned rows converge. Never a rewrite pass
  (expansion §2.5) `[V]`.

---

## 5. Per-client API verification (do this table, or do not ship)

Feature-detect everything; gate nothing on client identity. Status key:
**VERIFIED** = read in `/home/sam/wow-ui-source` on the named branch(es);
**ASSUMED** = needs the stated in-game check; **UNKNOWN** = open question.

| API | Era 11509 | Anniv 20506 | Titan 38002 | Forever 16001 | Retail 120105 | status |
|---|---|---|---|---|---|---|
| `GetGuildInfo("player")` | `PaperDollFrame.lua:95` | `PaperDollFrame.lua:95` | `PaperDollFrame.lua:95` | `InstanceDifficulty.lua:219` | `InstanceDifficulty.lua:216` | VERIFIED usage all five |
| `GetGuildInfo(unit)` non-player | — | — | — | — | — | ASSUMED — verify inspect-target returns in game; blank fallback covers failure |
| `UnitLevel` | `UnitDocumentation.lua:2817` | (same family docs) | (same family docs) | `UnitDocumentation.lua:2474` | `UnitDocumentation.lua:2385` | VERIFIED docs (Anniv/Titan: confirm same line when touching) |
| `GetSpecializationInfoForClassID` | `SpecializationSharedDocumentation.lua:10` | `:10` | `:10` | `:10` | `:10` | VERIFIED docs all five; TBC/Wrath return content ASSUMED (Q3) |
| `C_SpecializationInfo.GetSpecialization` (modern capture) | n/a (classic path) | n/a | n/a | via library `:3219` | via library `:3219` | VERIFIED library usage; classic branches use talent path |
| `GetTalentInfo` / `GetTalentInfoByClass` (classic capture) | library `:3064-3068` / `:3003` | same | same | n/a | n/a | VERIFIED library; engine presence classic-only per family |
| `RequestInspectHonorData` / `HasInspectHonorData` | `Classic/InspectPVPFrame.lua:17-18` (+ vanilla `:6-10` same shape on live copy) | same | same | `Mainline/InspectPVPFrame.lua` honor path | `Mainline/InspectPVPFrame.lua:72` + `Vanilla/InspectHonorFrame.lua:6-7` | VERIFIED usage |
| `GetInspectHonorData` (12 returns, `lifetimeRank` 12th) | `Classic/InspectPVPFrame.lua:234` | same | same | `Camelot+Mainline` `:110`/`:72` | `Mainline:72`, `Vanilla:20` | VERIFIED usage |
| `GetInspectArenaTeamData` → `playerRating` | `Classic/InspectPVPFrame.lua:145,157` | same | same | — (solo path `:95` `GetInspectArenaData`) | — (same) | VERIFIED: teams classic; solo-data modern |
| `GetInspectArenaData` (teamless) | `Classic/InspectPVPFrame.lua:66` | same | same | `Mainline/InspectPVPFrame.lua:95` | `Mainline/InspectPVPFrame.lua:95` | VERIFIED usage |
| `GetArenaTeam` (player-side) | `PVPFrameBase.lua:53,61,92` | (same file family) | (same file family) | — | — | VERIFIED Era; confirm Anniv/Titan same lines when touching |
| `GetPersonalRatedInfo` (self-only — NOT synced) | present but gated mainline | present but gated | present but gated | `PVPUI/Mainline:1372,1623` | `PVPUI/Mainline:1372,1623` | VERIFIED; display-self-only rule stands |
| `UnitHonor` / `UnitHonorLevel` (self-only) | — | — | — | `PVPHonorSystem.lua:177-180` | `HonorBar.lua:8-10` | VERIFIED; never synced |
| `INSPECT_HONOR_UPDATE` event | `Vanilla/InspectHonorFrame.lua:2,14` pattern | same family | same family | — | same pattern (live copy) | VERIFIED pattern; Stage 3 does not wait on it |
| `CHAT_MSG_ADDON` payload order | `ChatInfoDocumentation.lua:615-628` | (family-identical per prior audits) | (family-identical) | (family-identical) | `:803-816` | VERIFIED Era+Live; family-identical per §6.4.7 rule |
| `SendAddonMessageResult` enum | `:154,158,159` (0/3/7/8) | same | same | `:157,161,162` | `:154,158,159` | VERIFIED all five |
| `MAX_ADDON_MESSAGE_LENGTH = 250` | `CooldownBroadcaster.lua:6`, packed `:25` | (same file) | (same file) | (same file) | `:8`, packed `:27` | VERIFIED Era+Live; family file identical |

TOC coverage anchor: `TacoTip_Extras/TacoTip_Extras.toc:1`
(`11509, 20506, 38002, 16001, 120105`) `[V]`.

---

## 6. Harness checks to add (names + what each pins)

Harness shape assumed: protocol block closure `runQueryProtocol`
(`TacoTip_Extras/Tests/harness/load_test.lua:3179`), `drainSends`
(`:3251`), `fireEvent` (`:1981`), direct `RankSync.HandlePayload(payload,
chatType)` calls (`:3334`) `[V]`; browser suite at
`TacoTip_Extras/Tests/harness/rankbrowser_test.lua` (123 `check(` count at
read time) `[V]`. Every check below must FAIL on pre-Stage-3 code (new fields
absent → assertions on them cannot pass).

Wire/stride (load_test.lua, protocol block):

1. `"R2 round-trips all thirteen fields"` — build a full record via
   `SerializeRecord`, assert `DeserializeRecord` returns every field incl.
   `guild/level/pvpRank/arena/specID`; assert `splitFields` count == 13.
2. `"old version is refused and counted, R2 accepted"` — feed a diet-`"1"`
   payload, assert `stored == 0` and `versionReject` counted (existing
   refusal path, `TacoTip_Extras/RankSync.lua:223-229,754-762`); feed the
   `"2"` equivalent, assert stored.
   (Pre-release single-stride rule, §0.4.)
3. `"T with two fully-expanded typical records stays ≤240"` — two
   guild+level+pvp+arena records under one `T;<id>;`, assert every emitted
   message `#msg <= 240` (door: `TacoTip_Extras/RankSync.lua:454-462`).
4. `"validator-max pair still splits-or-refuses"` — two max-shaped records
   (64-char name, 24-char guild, 128-char guid); assert no emitted message
   exceeds 240 (split into singles per `:784-804`, or door-refused + counted).
5. `"guild truncates to 24, empty stays empty"` — 40-char guild input →
   stored 24; `""` round-trips as `""` (not shifted, not `"Unknown"`).
6. `"specID 0 renders class fallback, nonzero localizes"` — browser-level or
   resolver-level: `0` → class token path
   (`TacoTip_Extras/RankBrowser.lua:486-500`); known id → localized name via
   the resolver (mock `GetSpecializationInfoForClassID`).

Storage (load_test.lua, Stage-2 block area):

7. `"Stage-3 fields persist and prune like the rest"` — store expanded rows,
   assert `GetRecord` returns them; age one past 60 days, run
   `PruneStaleRecords` (`TacoTip_Extras/RankDB.lua:589`), assert gone while
   fresh expanded rows survive.
8. `"old rows without new fields read blanks"` — store a pre-Stage-3-shaped
   table directly, assert `ValidateRecord` defaults (`guild == ""`, numeric
   fields `0`) and the browser renders no "0"/"Unknown" noise.

Browser (rankbrowser_test.lua):

9. `"guild text filter narrows, empty guild rows survive unfiltered"` —
   alongside the existing class-filter tests; filtered view shows only
   matching guild; clearing restores; unguilded (`""`) rows render blank, not
   hidden, when no guild filter is active.
10. `"level column renders, sort flips, # invariant holds"` — level values in
    order both directions (existing `sortAsc` machinery,
    `TacoTip_Extras/RankBrowser.lua:267-268`); `#` still GearScore rank both
    ways (existing invariant pattern).
11. `"retail self-rating never comes from sync"` — seed a row with nonzero
    `arena` on a forever/live profile, assert the browser does NOT render it
    as inspected (either hidden or self-tag path only for the local player).

Debug (load_test.lua or Core-level):

12. `"/ttgsdebug surfaces Stage-3-visible state"` — extend the `GetDebugState`
    snapshot assertion pattern (`TacoTip_Extras/RankSync.lua:932`,
    `TacoTip_Extras/Core.lua:664-690`) only if new counters are added;
    otherwise assert the existing outcome keys still enumerate after the
    stride change (stride edits must not silently drop telemetry).

---

## 7. What Section 3 must NOT touch (Section 4 gear-on-demand surface)

Hard boundary — any of this in a Stage-3 diff is rejected on sight:

1. No `G`/`D` message types, no `recordFromParts`-adjacent gear parsing, no
   gear blob packing. (Stage 4 owns `G;<id>;<guid>` → `D;<id>;<guid>;<blob>`.)
2. No `gear[realmKey][guid]` table, no gear cap/LRU/age, no `t`-timestamp
   dedup. (`gear` is created lazily in Stage 4; expansion §6.2.)
3. No `C_Item.GetItemInfo` / `IsItemDataCachedByID` /
   `RequestLoadItemDataByID` / `ITEM_DATA_LOAD_RESULT` wiring beyond what
   `Scanner.lua` already has — the gear panel's async path is Stage 4's.
4. No item-ID capture changes in `Scanner.lua` (capture at
   `TacoTip_Extras/Scanner.lua:484-485`) and no `Cache.lua` tuning
   (`MAX_ENTRIES = 32`, 300 s at `TacoTip_Extras/Cache.lua:10-14`).
5. No compression (`C_EncodingUtil.*` or otherwise) — single expanded records
   measure 97% of raw (expansion §3.2); the door + split already handle size.
6. No root `schema` bump (`Core.lua` future-schema path) and no `rankSchema`
   semantics change beyond what Stage 2 defined — Stage 3 fields are additive
   under the existing version story.
7. No locale files (`Locale/*.lua` — owned by the locale-tier-a-keys desk;
   Stage 3 adds enUS keys only, translations follow through that lane).
8. No whisper-path resurrection — the oracle correction stands: same-transport
   answers only, nil-transport = counted silent skip
   (`answerForQuery`, `TacoTip_Extras/RankSync.lua:653`; `respondToQuery`,
   `TacoTip_Extras/RankSync.lua:665`, counted `answerNoTransport` at `:700-704`) `[V]`.
9. No `MAX_CAPACITY` change, no byte-budget enforcement, no index-rebuild
   redesign (§6.3 targets are held, not moved).
10. No `Tooltips.lua`, README, or TOC edits — behavior ships through the four
    files' existing seams (RankSync/RankDB/Scanner capture/RankBrowser
    render) plus harness + CHANGELOG.

---

## 8. Open questions (refuse to guess)

1. **[A] Remote-unit `GetGuildInfo`:** does `GetGuildInfo(unitToken)` return a
    guild for an inspect target on each client family, or only `"player"`?
    Verify in game; the blank-fallback absorbs either answer but the browser
    copy ("blank = unguilded-or-unknown") should say which.
2. **[A] `UnitLevel` `-1`:** confirm the un-inspectable `-1` return exists on
    the classic branches and that no client returns `nil` vs `0` in a way the
    `>= 1` test mishandles. Verify: `/dump UnitLevel("target")` on an
    out-of-range unit per client.
3. **[A] `GetSpecializationInfoForClassID` on TBC/Wrath content:** documented on
    all five (`SpecializationSharedDocumentation.lua:10`) `[V]`, but does it
    return TBC/Wrath talent-tree names on Anniversary/Titanforge, or only
    modern spec rows? If the latter, the classic capture path needs a decided
    encoding (tab-index namespaced per class) — NOT invented here; decide with
    the operator before writing it.
4. **[U] Level filter semantics:** column-only vs min-level filter control?
    This brief recommends column-only (§3.2); confirm demand before adding
    predicate surface.
5. **[U] `arena` single-best vs per-bracket:** this brief stores one number
    (best inspectable rating). If the operator wants 2v2/3v3/5v5 split, that
    is +2 wire fields (≈+10 bytes typical, ≈+12 SV-model bytes each) — still
    inside budget, but decide before the stride freezes, not after.
6. **[U] Retail/Forever self-rating display:** show local-player rating with a
    "self" tag (§3.4 MAY), or show nothing at all? One-line operator call; the
    wire rule (`0`, never synced) is unaffected either way.
7. **[U] `CHANNEL` on Anniversary/Titanforge** (expansion §8 carryover): does
    addon traffic on custom channels work there? Affects only the
    dead-channel-skip rate, not this stride — but the five-client checklist
    (companion file) must still close it.
8. **[U] Guild-name length distribution:** the 24-cap assumes no real guild
    name usefully exceeds 24 display chars. If in-game sampling shows longer
    common names, raise to 31 (realm-name parity) and re-run the §1.2 table —
    still inside budget, but the stride comment must record the new worst case.
