# fix-extras-hunter — Journal

## 2026-10-19 — Desk opened
- **Purpose:** Close the remaining publish-blocking findings from the final hunter
  audit (`bench/audits/2026-10-19-final-hunter.md`) on **TacoTip Extras v1.2.3**:
  the three open HIGHs (H-1 locale specifiers, H-2 render latch, H-3 unreachable
  diagnostics), the socket-capacity prefix (M-4 in the item list), the cheap
  MEDIUM/LOW counters, and the Extras README/CHANGELOG release-status claims.
- **Scope:** `TacoTip_Extras/` ONLY — code, `Tests/harness/`, `README.md`,
  `CHANGELOG.md`. **NOT** the main add-on's code, README, CHANGELOG,
  `.gitattributes` or `Tools/` (another lane owns those). No commit, no staging.
- **Baseline measured (not assumed):**
  - `bash TacoTip_Extras/Tests/harness/run_all.sh` → `TOTAL 42 invocations: 42 passed, 0 failed`
    (lua5.1 / lua5.4 / luajit, 14 invocations each).
  - `cd TacoTip_Extras && luacheck .` → `Total: 0 warnings / 0 errors in 26 files`.
  - `bash Tools/verify_release_extras.sh` → `verify_release_extras: PASS`.
- **Prior context read (bench-read):** `desks/fix-extras-publish` closed H-4
  (recovery-journal lock) and the six earlier publish fixes; it explicitly left
  the socket-capacity defect OUT of scope and recorded it as an operator
  decision. This lane is that decision, taken.
- **Next step:** item 1 — restore the stripped format specifiers in the ten
  non-English Extras locales, and make the harness's existing (vacuous)
  specifier check compare the ORDERED SPECIFIER SEQUENCE against enUS.

## 2026-10-19 — Items 1, 2, 3 and 5 implemented and pinned
- **Item 1 (H-1, locale specifiers):** the harness's existing specifier check
  (`load_test.lua:1641-1663`) was **vacuous**: `count()` closed over `value`,
  so both sides of the comparison were the translation and the check could
  never fail — it passed while all ten non-English locales shipped a footer
  with every `%` stripped off. Replaced with an ORDERED SPECIFIER-SEQUENCE
  comparison against enUS (`load_test.lua:1641-1707`), plus a ruRU render pin.
  Locale fixes: the three stripped keys in each of the ten files
  (`Locale/{deDE,esES,esMX,frFR,itIT,koKR,ptBR,ruRU,zhCN,zhTW}.lua:14,15,20`),
  each language keeping its own wording. `SORT_LEVEL_DESC` added to all ten
  (L-5) at line 229.
- **Item 2 (H-2, render latch):** `Tooltips.lua` — the latch now lives in a
  wrapper (`renderPlayerTooltip`) that xpcalls the body
  (`renderPlayerTooltipBody`) and ALWAYS releases it; the failing render
  drops its binding but does NOT disarm the poll. Counters: `renderErrors`,
  `renderErrorsSuppressed`, `lastRenderError`, a bounded ring — the same shape
  as the main add-on's `handlePipelineError`, mirrored not copied.
  `Tooltips.GetDriverState()` now carries them.
- **Item 3 (H-3, unreachable diagnostics):** `/ttgsdebug` prints a
  `/ttgsdebug surfaces` block: driver mode/renders/rows/poll ticks,
  render errors, rank-record errors, row-tooltip errors, score-colour
  fallbacks + last reason, cache/scanner listener errors, records rejected,
  queue evictions, and the initialize-failure list.
- **Item 5:** M-3 `Cache.lua` + `Scanner.lua` listener fan-out counters;
  M-5 `RankSync.lua` rejected-record counter + last reason; M-6 send-queue
  eviction counter + evicted kind; M-7 `Core.lua` records a refusing
  `Adapter.Initialize` with ONE chat line naming the adapter's internal
  reason; L-6 `Core.lua` records a non-callable module as an initialization
  failure.
- **Mirror evidence (item 4, socket keys):** the FrameXML mirror at
  `/home/sam/wow-ui-source` has **zero** occurrences of `EMPTY_SOCKET` (any
  case, any branch) — the stat-table key names are engine-side and are NOT
  in the mirror. `GetItemStats` IS documented on
  `origin/live:Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua:982`
  and `origin/forever:.../ItemDocumentation.lua:1004`, and is **absent** from
  `origin/classic_era`, `origin/classic_anniversary` and
  `origin/classic_titan` (zero hits). So the mirror cannot settle the key
  names: fall back to the harness mock's `EMPTY_SOCKET1/2/3`
  (`load_test.lua:1028-1030`), and make the match tolerant of the digit
  suffix.
- **Revert-to-fail evidence so far:** item 1 (one `%` stripped from ruRU) and
  item 2 (the latch no longer cleared on the raising path) — both quoted in
  the final message.
- **Current state:** `bash TacoTip_Extras/Tests/harness/run_all.sh` → 42/42
  on lua5.1/5.4/luajit; `cd TacoTip_Extras && luacheck .` → 0 warnings / 0
  errors in 26 files.
- **Next step:** item 4 — fix the socket-capacity prefix, then prove the
  revert, then items 6-7 (README + CHANGELOG).

## 2026-10-20 — Items 4, 6, 7 done; the whole revert matrix re-run; lane closed
- **Item 4 (socket capacity):** `Scanner.lua:61-81` — `SOCKET_PREFIX` is now
  `"EMPTY_SOCKET"` (no trailing underscore), matched as a PREFIX so the digit
  suffix is tolerated, and the remainder must be empty or digits so an
  unrelated key cannot be counted as a socket. The key test is at
  `Scanner.lua:535`.
  **The published numbers change on Retail and WoW Forever**: the capacity is
  no longer 0, the socket evidence no longer contradicts the parsed gem list,
  and Potential GS / Delta / Completion are computed instead of suppressed by
  `socket-gem-mismatch-1`. The three Classic clients have no `GetItemStats`,
  so their socket path stays absent and their three metrics stay unavailable —
  that degradation was already documented in the Extras README.
- **Item 6 (README):** `README.md:19` project_url → the live listing, `:25`
  `status: released`, `:33` the body link, `:35` the "not maintained by the
  TacoTip author" claim dropped (stale since 1.2.0 unified the authorship on
  AcidBomb), `:190` the "Not yet released" bullet rewritten: the listing
  exists and serves 1.2.2, and 1.2.3 ships alongside TacoTip 0.8.4. No
  publication date is claimed for 1.2.3.
- **Item 7 (CHANGELOG):** one new subsection in the existing `[1.2.3]` section
  (`CHANGELOG.md:730`), "The last three HIGHs, the socket capacity, and the
  release status" — items 1-6 with file:lines, the mirror evidence, the metric
  status on Retail/Forever and on the Classic family, and the validation
  totals. No version bump; earlier sections untouched.
- **Revert matrix (every fix reverted to red, then restored to green).** The
  matrix lives in `/tmp/opencode/revert-matrix.txt`; each probe restores the
  file and verifies the restore by sha256.
  - item 1 — one `%` stripped from ruRU → the sequence pin and the ruRU render
    pin both red.
  - item 2 — the latch not cleared on the raising path → "the surface renders
    again after a raising render" red, plus the 11 downstream pins that
    depend on a live tooltip.
  - item 3 — the `/ttgsdebug surfaces` block removed → the three surfaces
    pins red.
  - item 4 — `SOCKET_PREFIX` back to `"EMPTY_SOCKET_"` → 2 of 14 invocations
    red (the two Mainline clients; the Classic three have no `GetItemStats`
    and were unaffected).
  - item 5 M-3 (Cache and Scanner fan-out back to a bare pcall) → red.
  - item 5 M-5 (the refused-record count removed from both arms) → red.
  - item 5 M-6 (the send-queue eviction back to a silent `table.remove`) →
    red.
  - item 5 M-7 (a refusing `Adapter.Initialize` no longer recorded) → red.
  - item 5 L-6 (a non-callable module no longer recorded) → red.
- **Validation on the restored tree:** `bash TacoTip_Extras/Tests/harness/run_all.sh`
  → **42 invocations: 42 passed, 0 failed** on lua5.1 / lua5.4 / luajit;
  `cd TacoTip_Extras && luacheck .` → **0 warnings / 0 errors in 26 files**;
  `bash Tools/verify_release_extras.sh` → **PASS**; the MAIN add-on's own
  harness (untouched by this lane) → **70 invocations: 70 passed, 0 failed**.
- **Deviations:** items 6 and 7 are documentation — they carry no behavioural
  pin, and the release verifier checks file presence, not README prose.
  Everything else in the item list is pinned and revert-proven.
- **Next step:** the operator to decide on the two things this lane could not
  settle from the tree: (a) the stat-table key names could not be confirmed
  against the engine, only against the harness's client mock; (b) the socket
  capacity is read as the SUM of the `EMPTY_SOCKET*` values, which assumes
  those values count socket SLOTS rather than empty sockets — the mock cannot
  distinguish the two, and a live client could.

## 2026-10-20 — [signal:done] The last three HIGHs, the socket capacity, and the release status
- Items 1-7 of the final-hunter list are closed on TacoTip Extras v1.2.3:
  the ten locales' format specifiers, the tooltip render latch, the
  unreachable diagnostics, the socket-capacity prefix, the five cheap
  counters, and the README/CHANGELOG release-status claims.
- 42/42 on lua5.1/5.4/luajit; luacheck 0/0 in 26 files; the release
  verifier PASS. Ten revert probes, each red then restored green.
- Desk path: `desks/fix-extras-hunter/`. Signal:
  `.signals/2026-10-20T01-40-00Z-done.json`.
