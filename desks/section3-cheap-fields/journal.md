# section3-cheap-fields — Journal

## 2026-10-18 — Desk opened
- **Purpose:** Implement Stage 3 cheap expanded fields per bench/audits/2026-10-18-stage3-cheap-fields-brief.md (13-field R;2 stride: +guild/level/pvpRank/arena) on the landed diet baseline (WIRE_VERSION="1", RECORD_FIELDS=9).
- **Scope:** RankDB.lua, RankSync.lua, Scanner.lua, RankBrowser.lua, Locale/enUS.lua (header keys ONLY), Tests/harness/load_test.lua, Tests/harness/rankbrowser_test.lua, CHANGELOG.md (append-only). NOT Tooltips.lua, README, TOC, other Locale files, bench/, other desks.
- **Context (bench-read):** section2b-wire-diet (diet stride landed, whisper deleted, versionReject counted); section2-storage (Stage 2 hygiene); stage3-prep (the brief + reconcile rule); locale-tier-a-keys (parity invariant: no non-enUS key without enUS; CLASS_EVOKER now in all 11).
- **Concurrency:** Oracle desk (audit-stage2) is READING my files — few decisive writes per file, every file self-consistent after each write.
- **Next step:** reconcile diet shape vs tree (done, no drift — see entry below), then implement.

## 2026-10-18 — Reconcile: no drift from the brief's §0 assumption
- **Verified in tree before touching indices:** `WIRE_VERSION="1"` (RankSync.lua:165), stride `R;<ver>;guid;name;classID;gs;ilvl;timestamp;specID` (:167-180), `RECORD_FIELDS=9` (:192), version-gated refusal + counted `versionReject` in `DeserializeRecord` (:223-229) and `recordFromParts` (:754-762), stride loop `index + RECORD_FIELDS - 1` (:788), whisper deleted end-to-end (only counted `answerNoTransport` at :700-704 remains), `CLASS_EVOKER` in all 11 locales, CHANGELOG [1.2.3] final through Wire-diet. Baseline suite: 42/42 green, LINT 0/0 (quoted from run).
- **Next step:** implement per brief.

## 2026-10-18 — [signal:checkpoint] Stage 3 implemented, suite green
- **Worked on:** 13-field `R;2` stride (RankSync: version bump, Serialize/Deserialize/recordFromParts/guild-level-pvp-arena, `RECORD_FIELDS` 13); RankDB ValidateRecord + `GetLeaderboard(realm,tab,class,search,guildFilter)`; Scanner capture (guild sanitized+24-cap, level>=1, numeric specID via group-aware engine form + GetInspectSpecialization fallback, Era-honor/TBC-arena snapshot gated on honor-data presence, modern rated surface forces 0/0); RankBrowser (level column + sort, guild text filter, guild+PvP tooltip lines, modern-gated PvP); enUS-only keys (LB_COL_LEVEL, LB_GUILD, SORT_LEVEL_DESC, LB_TIP_PVP_RANK, LB_TIP_ARENA); 12 named harness checks (7 load_test + 5 rankbrowser incl. R2-fed render); CHANGELOG Stage-3 subsection appended.
- **Validation:** `bash TacoTip_Extras/Tests/harness/run_all.sh` → `TOTAL 42 invocations: 42 passed, 0 failed` (lua5.1/5.4/luajit); `LINT=1` → `Total: 0 warnings / 0 errors in 26 files`. load_test 344 checks / rankbrowser 157 checks, 0 failed. Real-serializer bytes: typical 89, bare 58, validator-max 260 (single 269 > 240 door → refused), T+2 typical 188 ≤ 240.
- **Current state:** all production + test + changelog edits complete, suite green. Deviations journaled (ByID resolver kept, no guild column, no self-rating display, no new counters, specID-already-stored budget note, classic-UnitLevel [A]). No commit, no staging.
- **Next step:** operator review; Oracle desk reconciliation; in-game pass for the 8 open questions (all still open).

## 2026-10-18 — [signal:done] Stage 3 complete, review-ready
- Suite green quoted above; desk path `desks/section3-cheap-fields/`, signals in `.signals/` (run_id stage3). No commit, no staging.
