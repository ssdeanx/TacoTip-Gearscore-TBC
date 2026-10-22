# Stage 3 + Stage 4 oracle audit

- **Date:** 2026-10-18
- **Desk:** `audit-stage34` (read-only; no production edits)
- **Spec:** `bench/audits/2026-10-18-stage3-cheap-fields-brief.md` (§0–§8) +
  `bench/audits/2026-10-18-stage4-gear-on-demand-brief.md` (§0–§9)
- **Tree as read:** `WIRE_VERSION="2"` (`RankSync.lua:169`), `RECORD_FIELDS=13`
  (`RankSync.lua:206`), `GEAR_MAX_CHUNKS=4` / `GEAR_RING_BOUND=64`
  (`RankSync.lua:822-823`), `GEAR_MAX_ENTRIES=2000` (`RankDB.lua:46`),
  `REQUIRED_SLOTS` 17 members (`Scanner.lua:14-17`), 5 new enUS keys, zero
  non-enUS keys. Suite: `TOTAL 42 invocations: 42 passed, 0 failed`
  (lua5.1/5.4/luajit); `LINT=1 → 0 warnings / 0 errors in 26 files` (re-ran
  both myself `[V]`).
- **Evidence labels (CAIRN.md):** `[V]` VERIFIED (read in source or produced by
  a command I ran), `[A]` ASSUMED (says what would verify), `[U]` UNKNOWN.
- **Concurrent tree:** `desks/fix-oracle-findings/journal.md` contains only its
  opened entry (scope declared, items A/B/C not yet specified, zero
  implementation entries). All working-tree modifications are the
  section3/section4 writer-desks' uncommitted work; **no fixer hunk was live at
  read time, so no Stage-3/4 finding is absorbed into one.** Re-checked
  immediately before writing (§9).

## Verdict

**Both stages land. No merge blocker in either.** Every brief MUST is
implemented, every deviation I found was already journaled by the
implementer with a reason, and every open question is still open (defaults
followed, nothing silently guessed). Findings are follow-ups, ranked §8 —
the sharpest is a missing future-t clamp on gear ingest (F1, hostile-only
today since no production code sends `G` yet).

---

## 1. Stage 3 (cheap expanded fields) — MUST-by-MUST

| Brief MUST | Landed | Where |
|---|---|---|
| 13-field `R;2` stride, version bump, 4-site edit | yes | `RankSync.lua:169-196` serialize, `:206` `RECORD_FIELDS=13`, `:237-269` deserialize, `:1148-1172` `recordFromParts`, `:1186-1198` stride loop |
| Old stride refused + counted `versionReject`, never inferred | yes | `:243-248`, `:1152-1154`; harness `"old version is refused and counted, R2 accepted"` |
| Guild sanitize + 24-truncate, `""` never `"Unknown"` | yes | `RankDB.lua:286` (`sanitizeString(record.guild, 24) or ""`); harness `"guild truncates to 24, empty stays empty"` |
| Level `>= 1` else 0 (absorbs `-1`) | yes | `Scanner.lua:152-158`, `:364-378` (`isNonnegativeInteger(-1)` is false → blocked cell → 0) `[V]` |
| Numeric `specID` capture, never name-matched | yes | `Scanner.lua:166-185` (group-aware `GetSpecialization` + `GetInspectSpecialization`, positive-number test, else 0) |
| PvP per-client snapshot; Retail/Forever wire 0 always, detected by API presence not identity | yes | `Scanner.lua:192-196` (`modernRatedSurfacePresent`), `:204-264` (honor-presence gate, no `INSPECT_HONOR_UPDATE` wait) |
| Browser: guild text filter (optional-positional 5th arg), level column + sort, no level filter, no guild column | yes | `RankDB.lua:584-636` (nil/blank = unchanged behavior); `RankBrowser.lua:49` column, `:303-306` sortable, `:345-346` sort; tooltip guild `:434`, PvP `:438-443` |
| Render-side Retail suppression (not just absent) | yes | `RankBrowser.lua:166-170` returns nil,nil when `C_PaperDollInfo.GetInspectRatedBGData` exists — hostile nonzero on modern renders nothing `[V]` |
| enUS-only keys, parity invariant | yes | 5 keys (`LB_GUILD`, `LB_COL_LEVEL`, `SORT_LEVEL_DESC`, `LB_TIP_PVP_RANK`, `LB_TIP_ARENA`); all other locales 0 of 5; harness `"no locale defines a key enUS does not"` green `[V]` |
| Additive migration, no rewrite, budget machinery untouched | yes | `RankDB.lua:283-289` defaults; `MAX_CAPACITY`/prune paths unchanged |
| §7 must-not-touch (no G/D, no gear table, no compression, no whisper, no locale/TOC/README) | yes | `grep WHISPER RankSync.lua` → 0; no `G;`/`D;` send sites outside Stage-4 hunks; no `gear[` outside Stage-4 hunks |

**Deviation from brief §3.3 (journaled, safe):** the browser resolves `specID`
via `GetSpecializationInfoByID` single call (`RankBrowser.lua:136-150`,
feature-detected + pcall) instead of the brief's `GetSpecializationInfoForClassID`
loop + library reverse lookup. The section3 journal records "ByID resolver
kept". Functionally equivalent-or-better (direct, localized at render, zero
locale keys). ByID-as-global presence: the era checkout shows Blizzard's own
`SharedXML/UnitUtil.lua:50,60,69` calling it as a bare global (supports era);
the other four branches are inherited from the brief-desk's table, not
re-verified here — and non-presence degrades to the class fallback by
construction, so this is not a correctness risk.

## 2. Stage 4 (gear on demand) — MUST-by-MUST

| Brief MUST | Landed | Where |
|---|---|---|
| `G;<ver>;<id>;<guid>` / `D;<ver>;<id>;<guid>;<t>;<seq>/<of>;<blob>`, version in field 2, one gate | yes | dispatch `RankSync.lua:1250-1283`; G gate `:1258-1261`, D gate via `parseGearMessage` `:1002-1005`, both `versionReject` |
| 8-char id clamp on echo | yes | `:1059`, `:1262`; harness `"request-id clamp on G echo"` |
| Sparse `slot=itemID`, `REQUIRED_SLOTS` order, omit empties, IDs only | yes | `BuildGearBlob` `:850-882`; `ParseGearIDs` `:720-744` (strict per-pair, first-wins) |
| Greedy pair-boundary chunker, `of ≤ 4`, refusal counted | yes | `chunkGearRun` `:891-911`; harness `"oversize single-D sequences into 1/2 + 2/2"` pins disjoint ordered halves ≤240 |
| Two-tier cache: owner live / peer fresh-only, else `gearNoData` | yes | `respondToGear` `:1075-1103`; `GetFreshRemote` (not `GetRemote`) for peers |
| Shared bucket/queue/tokens, no second bucket, no direct Enqueue of chunks | yes | `enqueueGearChunk` `:977-990` → `processQueue`; full queue drops chunk + `enqueueOversize` |
| Per-sender 20s coalescing ring bound 64, distinct senders never coalesced | yes | `:937-971`; harness same-sender triple → 1 D + 2 `gearCoalesced`; 4 distinct → 4 Ds |
| Shared `lastRespondAt` NOT armed by gear (starvation §6.9) | yes | `respondToGear` never touches `lastRespondAt`; harness `"starvation-freedom"` ×3 |
| S-before-D within one G | yes | `:1110` before `:1126-1132`; harness `"a G-triggered S is enqueued before its D"` |
| Dedup: older→`gearStale`, equal-t→fill-gaps, newer→slot-merge, missing t→0 | yes | `RankDB.StoreGear` `:801-854`; harness stale/newer/same-t-merge checks |
| Bounded persisted gear: lazy, 2000/realm, 60d age, same-pass prune, 3rd return, local exempt from count only, orphan keys deleted | yes | `:689-935`, `PruneAllRealms` `:948-995` (returns `removedTotal, realmsDeleted, gearRemoved`); `Core.lua:184-185` uses `pcall` without returns — additive, no caller breakage `[V]` |
| Aggressive `7d/1000` (gear halves before ranks) | yes | `:913-935` (`cap/10`), `:1003-1005`; harness `gearCount==1000`, ranks survive |
| Panel precedence fresh > persisted(dim + age) > not-scanned; literal-only; no GS recompute; no `NotifyInspect` | yes | `RankBrowser.ShowGear` `:872-951`; zero new locale keys `[V]` |
| §8 must-not-touch (no stride change, no schema, no dead-field revival, no link sync, no compression, no 32/300 retune, no `REQUIRED_SLOTS` change, no whisper, no locale/TOC/README) | yes | all frozen values unchanged; `WHISPER` count 0; Stage 4 adds zero locale keys |
| `GetGear` never creates realm tables | yes | `:748-769` pure read; journaled |

**Journaled deviations (all with reasons, all accepted):** D carries sender `t`
(brief §1.1 sketch omitted it; §3 dedup needs it — typical single-D is
therefore ~150–195 B, not ~140–180; re-measured §5); new `gearRefused` bucket
(no existing bucket fits `of>4`); per-sender (not global) 20s gate (§4.2 vs
§6.9 — sharing `lastRespondAt` as a drop would let a G storm suppress rank
answers); literal-only persisted render (Q3 unverified); deferred click→G;
`GetGear` probe-orphan avoidance; `RankDB.GEAR_SLOTS` + parity pin
(harness `"Scanner.REQUIRED_SLOTS and RankDB.GEAR_SLOTS carry one canonical
order"`); equal-t no-new-slots → `"unchanged"` uncounted.

## 3. Open questions — all still open

S3 Q1–Q8 and S4 Q1–Q8: verified none closed by code. Defaults hold:
blank-guild fallback (Q1), `>= 1` level test (Q2), classic `specID=0` (Q3),
column-only level (Q4), single-best arena (Q5/S4Q1), no self-rating display —
the brief's MAY declined, journaled (S3Q6), same-transport absorption (S3Q7,
S4Q4, S4Q5), 2000 cap + `of≤4` as constants (S4Q6/Q7), read-only G (S4Q2),
literal-only panel (S4Q3). The one wording risk is S4Q4's "files under the
local realm only if that guid is already a rank row": the code files gear
regardless of rank-row presence (gear-only rows, never phantom standings) —
consistent with the brief's parenthetical once parsed, but the sentence can
be misread as a condition that was never implemented. Not a code issue.

## 4. Hole-by-hole

- **H1 validator-max R2 single refused at door — counted, observable, no
  silent drop?** YES `[V]`. `Enqueue` refuses `#msg > 240` + counts
  `enqueueOversize` (`RankSync.lua:480-482`); the validator-max harness check
  asserts `overAfter > overBefore` with `maxWorst ≤ 240`. Observable via
  `GetDebugState`. Nuance (pre-existing, all messages): `Enqueue` returns
  nothing, so the caller cannot know — counted but not reacted to. Not
  Stage-3-specific. Observation only.
- **H2 `gearRefused` (`of>4`) reachable by honest sets?** NO — proved
  unfailable `[V]` by arithmetic against the real framing: worst head =
  `4 + 9 + 129 + 11 + 4 = 157` (8-char id, 128-char guid, 10-digit stamp,
  `4/4;`), budget `83`; worst pair `~13` (2-digit slot + 10-digit id) →
  ≥6 pairs/chunk → 17 pairs ≤ 3 chunks < 4. `of>4` fires only on hostile
  injection (`parseGearMessage` `:1017-1021`, counted). The harness pins it
  via direct `5/9` injection — the honest-unfailable property itself is
  arithmetic, not harness-pinned; recorded here.
- **H3 per-sender 20s ring bound 64 — oldest-evicted re-request livelock?**
  NO livelock `[V]` (`:937-953`). Eviction only causes one duplicate answer
  for the evicted sender; rate is still bounded by the token bucket
  (1/1.5 s) and queue cap 50. Degradation is graceful (bounded extra
  traffic), not a loop. Untested at 65+ senders in-harness (only 4 used) —
  in-game-only.
- **H4 dedup mixed-t reassembly corruption?** No corruption; one theoretical
  gap `[V]` (`RankDB.lua:819-854`): newer-t merge keeps unmentioned stored
  slots, but a stale-t chunk is dropped whole — so interleaved answers
  (A1 t=100 stored, B1 t=101 merged, A2 t=100 dropped) can leave A2's slots
  unfetched until the next answer. Requires interleaved chunked answers
  (chunking needs validator-long guids) — adversarial-rare. Gap, never wrong
  data. F4.
- **H5 persisted-render literal-only — stale misread as fresh?** The specified
  signal (dim `|cff808080` + `"Last synced <age> (item IDs only)"`,
  `t=0` → `"Synced gear (item IDs only)"`) is implemented exactly
  (`RankBrowser.lua:923-943). Two qualifications: (a) the panel's session leg
  uses `GetRemote`, not `GetFreshRemote` (`:863-866`) — an *expired* session
  entry with renderable slots suppresses the persisted dim leg and renders
  undimmed. Pre-existing (session path "renders exactly as before"), not a
  Stage-4 regression. F5. (b) Sufficiency of dim+age is a UX judgment for the
  five-client pass — in-game-only.
- **H6 retail self-rating never from sync — render or absent?** ENFORCED IN
  RENDER `[V]` (`pvpLinesOf` `:166-170` returns nil,nil on the modern rated
  surface; capture side also zeroes). Hostile nonzero on modern renders
  nothing. Both sides pinned by the paired harness checks.
- **H7 guild 24-trunc collisions?** Filter is consistent over stored
  (truncated) data — no false negatives within what is stored. Lossless iff
  the WoW guild-name cap is 24 (brief Q8). `[A]` — close in game; if sampling
  shows longer real names, raise to 31 and re-run §1.2 per the brief.
- **H8 classic `UnitLevel` -1/boss in the level cell?** Handled `[V]`:
  `-1` fails `isNonnegativeInteger` → blocked cell → `captureLevelNumber`
  returns 0 → cell renders `""` (`RankBrowser.lua:575-576`). Old rows (no
  level) render blank, never `"0"` (harness `"old rows without new fields
  read blanks"`).

## 5. Byte / storage math (re-derived against the real serializer `[V]`)

Probed with the exact `SerializeRecord` field order/empties (lua5.1):

| Case | Journal/brief claim | Measured | Door |
|---|---|---|---|
| Typical R (22-guid, 8-name, 12-guild) | ≈85 (brief) / 89 (journal) | **80** | — |
| Bare R (minimal) | 58 (journal) | **24**; realistic-bare (22-guid, short name, empties) ≈ 58–60 | — |
| Validator-max R (128-guid, 64-name, 24-guild) | 260 (journal) | **259** | single `S;`+record **268 > 240 → refused+counted** ✓ |
| `T` + 2 typical | ≈180 (brief) / 188 (journal) | **170 ≤ 240** ✓ (~70 headroom) | ✓ |
| `T` + 2 validator-max | ≈270+/split-or-refuse (brief) | **528 → split to singles → each refused+counted** ✓ | ✓ |
| Full 17-pair D, 22-char guid | ~140–180 (brief) / ~150–195 (journal) | **174–191** (5/6-digit ids), head **47** (~49 claimed) ✓ | ✓ |
| Validator-max-guid full D | ~306 → chunk (brief) | **~300+ → 2–3 chunks** ✓ | ✓ |
| `RECORD_FIELDS` | 13 | **13** fields on the wire ✓ | — |

**Verdict: VERIFIED in mechanism.** Every door assertion holds with the
claimed headroom; exact journal digits (89/58/188) are illustrative of a
slightly different typical-value choice, not harness-pinned (no check
asserts `==`). Storage `5.3–5.9 MiB @ 20k` is model arithmetic (field names
+ quotes dominate file-side), **ASSUMED per CAIRN** — what would verify: a
20k-row SavedVariables file in game. Prune behavior (the enforceable half)
is harness-pinned, including local-exempt-with-oldest-local (the cap test
seeds local at `testNow-3000`, oldest of all — the exemption is meaningfully
exercised `[V]`).

## 6. CHANGELOG accuracy (the two new subsections vs code)

Stage-3 subsection: accurate claim-by-claim (stride, door, split-or-refuse,
spec capture/render, PvP snapshot, budget, browser, twelve checks, green
suite). Two nits: (a) "TBC/Wrath fills arena … (team path, then teamless)" —
the code takes the **max of both** team and teamless paths under one presence
gate (`Scanner.lua:242-259`), not a fallback; (b) the render path is
`GetSpecializationInfoByID`, which the subsection names correctly (matches
code, not the brief's ForClassID loop — good).

Stage-4 subsection: accurate claim-by-claim (framing, `t` dedup, blob,
chunking, `of≤4`, same-transport, session-truth, 2000/60d/aggressive,
per-sender ring, S-before-D, panel precedence, seventeen checks, green
suite). Three corrections: (a) **"never evicting older traffic" is untrue of
the S leg** — `enqueueOwnRecord` uses plain `Enqueue`, which evicts oldest at
cap-50; only the D-chunk leg (`enqueueGearChunk`) drops instead of evicting.
Unreachable today (no production G sender), but the sentence overclaims. F2.
(b) **"Names resolve at display through the existing async item path"**
overstates the persisted leg, which is literal-only by journaled design
(no `GetItemInfo` hookup, Q3 open) — true of the session leg only. F3.
(c) "a missing `t` stamps 0 and never overwrites" — 0 *does* write when
nothing is stored (code comment is precise; subsection sentence is not). Nit.

## 7. Tests — do they assert what they claim, do they fail pre-fix?

12 stage-3 + 19 stage-4 named behaviors all present and green. Spot-verified
non-vacuity (each fails pre-fix, usually via a `guildSeen`-style conjunct or
trivially via absent `G`/`D` handling): R2 round-trip, diet-refusal counting,
typical-pair `≤240` + `guildSeen`, validator-max split-or-refuse counting,
guild 24-cap + empty-stays-empty, persist + 60d prune, old-row blanks,
guild-filter narrowing, level column + sort + `#` invariant, modern-hide /
classic-show PvP pair, `/ttgsdebug` enumeration (fails pre-fix via the R2-row
guild conjunct — a pure regression guard otherwise, correctly so), G-owned
single-D + GUILD + `≤240` + sparse run + S-before-D + ingest-stores, PARTY
same-transport, dead-channel zero-sends + `answerNoTransport` + no-WHISPER,
version gates, `gearNoData`/`gearBadGuid`, 1/2+2/2 disjoint ordered halves,
`of`-cap, stale/newer-merge, same-t merge-reassembly, starvation ×3 +
per-sender triple, id clamp, 2000-cap/local-exempt/realm-scope,
age-prune + gear orphan-key deletion (`GearAgeB == nil` asserted `[V]`),
aggressive 1000-vs-ranks, debug-bucket enumeration, panel three legs,
D-ingest-without-rescan. The same-t merge test and the local-is-oldest cap
test are genuinely well-designed. One test-smell note: check 17 seeds its D
with `t = now + 50` (future) — passes, but bakes in tolerance of future
timestamps (see F1).

## 8. Findings (severity-ranked)

- **F1 (medium-low): gear ingest has no future-`t` clamp — a far-future `t`
  makes a gear row nearly immortal and un-overwritable.** `StoreGear`
  (`RankDB.lua:809-812`) floors `t` but never upper-bounds it (rank
  `timestamp` is clamped to `now + 300` in `ValidateRecord`, `:255`). A
  `D` with `t ≫ now`: (i) all later honest `D`s read `stale` and drop;
  (ii) the age prune (`pruneGearRealm`, `:881`) never collects it
  (`stamp < cutoff` false forever); (iii) count eviction takes it last.
  Threat model today: hostile peer on the same transport (no production
  code sends `G`, so honest traffic can never do this). One-line fix when
  wanted: clamp gear `t` exactly like record `timestamp`. In-game
  verification: none possible offline; needs a hostile-injection pass or
  the clamp.
- **F2 (low): S leg of a G answer can evict queued traffic at cap-50.**
  `enqueueOwnRecord → RankSync.Enqueue` evicts oldest when full
  (`RankSync.lua:484-486`); only `enqueueGearChunk` drops. Brief §4.5 and
  the CHANGELOG ("never evicting older traffic") describe the chunk leg.
  Unreachable without a G sender; when click→G lands, re-check whether the
  S leg should also drop-instead-of-evict inside the 20s window.
- **F3 (low, changelog-only): "Names resolve at display through the existing
  async item path"** — persisted leg renders `item:<id>` literals only
  (journaled Q3 default). True of session leg; misleading for persisted.
  One-sentence fix in the subsection.
- **F4 (very low, theoretical): mixed-`t` interleave leaves a slot gap**
  (H4). No wrong data, self-heals on next answer. Consider only if chunked
  answers become common (they need validator-long guids).
- **F5 (very low, pre-existing): panel session leg ignores freshness.**
  `ShowGear` uses `GetRemote`, not `GetFreshRemote` — an expired session
  entry renders undimmed and suppresses the persisted leg. Stage 4 did not
  introduce it ("renders exactly as before"); note for the panel's next
  touch.
- **F6 (nit): `mapGearRun` keeps LAST per slot, `ParseGearIDs` keeps FIRST.**
  Inputs are canonical on both paths (no dupes possible), so unreachable —
  but the two functions disagree about the invariant. One-word comment or
  shared helper when nearby.
- **F7 (nit, changelog-only): arena "team path, then teamless"** is max-of-both
  (§6b). **"missing `t` … never overwrites"** writes when empty (§6c).

## 9. Carry-forward + concurrency (as read 2026-10-18T15:37Z)

- `fix-oracle-findings`: journal opened, scope declared
  (`Tests/harness/*`, `RankBrowser` comments, `RankDB.sanitizeID`,
  `CHANGELOG` ref fixes), items A/B/C **not yet specified**, zero file
  hunks. Nothing to overlap; Stage-3/4 findings stand unabsorbed.
- Prior-oracle carryovers (stage-1/2 + diet audits): the writer journals
  cite them as reconciled baselines (diet stride, whisper deletion,
  `versionReject`, `answerNoTransport`); nothing in §3/§4 re-opens them.
- In-game-only additions (need a client, cannot close offline): S3 Q1
  remote-guild resolution, Q2 `-1` semantics per client, Q3 classic spec
  content, Q8 guild-length distribution; S4 Q2 inspect-on-G latency, Q3
  numeric-`GetItemInfo` form, Q4 cross-realm delivery, Q5 CHANNEL on
  Anniversary/Titanforge; H3 65+-sender ring behavior; H5 dim+age sufficiency;
  H7 24-cap losslessness; the G responder's first live answer (no production
  sender exists yet — the whole request path is currently harness-only).

## Outcome ratings (issued as signals alongside this report)

- **Stage 3: quality 4, effort_to_merge minimal.** Faithful brief
  implementation, all deviations journaled, suite green, findings are nits
  (F7) plus inherited in-game questions.
- **Stage 4: quality 4, effort_to_merge minimal.** Faithful brief
  implementation with harder machinery (chunker, ring, dedup, prune) all
  pinned; F1–F3 are follow-ups, none blocks merge.
