# Release 0.9.1 — Journal

## 2026-11-04 — Desk opened
- **Purpose:** Ship TacoTip v0.9.1 — version bump (Task A) plus the operator-approved safe
  set (Task B: R-1 queue-drop counters, T-1 one-arg CanInspect pin, T-2 queue-mechanics pins,
  T-3 migration pins, M-5 comment fix, P-2 separator constant).
- **Scope:** TacoTip root only (toc, main.lua, options.lua, Libs/LibForeverInspector, README,
  CHANGELOG, Tests/harness). TacoTip_Extras touched ONLY in Tests/harness/load_test.lua if (and
  only if) its :8852 version string mocks core's version — never its runtime files.
- **Invariants loaded:** workshop.md read in full; era range gate, gearscore formula, retail
  bracket, R;2 wire format, saved-var shapes, ONE-arg CanInspect, no invented translations,
  PlaySound boundary, container exclusion, no state-changing git — all respected.
- **Next step:** Read bench leads (0.9.1-relevant audits), then Task A version bump.

## 2026-11-04 — Bench leads + Task A code edits
- **Bench leads read:** inspect-and-guild-line-history (guild guard IsLoad-bearing),
  session-retrospective (revert-to-fail discipline), 2026-10-26 v0.8.8 readiness (diag
  collector structure; several findings superseded — 0.9.0 shipped since; treat as leads).
- **VERIFIED (read):** ADDON_LOADED migration path main.lua:4538-4561 — conf_version bumped
  → first_login fires once, clears ONLY exact legacy {TOPLEFT,TOPLEFT,0,0}, sanitize path
  :4552-4561 clears nil-shaped custom_pos each load. settings_test loads main into REALG
  (TT=TacoTip_Forever, TT.frame + GetScript available, C_Timer.After mock runs fn sync).
  CURRENT TRUTH: settings_test custom_pos-sanitize block (1263-1333) is a commented-out
  2026-10-23 revert — ApplyConfigDefaults does NOT sanitize custom_pos; only the live
  ADDON_LOADED sanitize does. B4 pins must drive the handler.
- **Edits made (Task A code):** TacoTip.toc:2 → 0.9.1; main.lua:3 fallback → "0.9.1";
  options.lua:3 fallback → "0.9.1"; Tests/harness/load_test.lua:1145-1146 pin + message →
  0.9.1; :1586 minimal-facts pin → "version: 0.9.1".
- **Decision (journaled):** TacoTip_Extras/Tests/harness/load_test.lua:8852 mock returns
  "0.9.0" for the UPGRADED-TacoTip scenario against a 0.8.0 fingerprint — nothing asserts
  the literal; scenario semantics hold for 0.9.1 but the brief's "unrelated → leave it"
  branch applies → Extras untouched.
- **Next step:** README What's-New + CHANGELOG section, then Task B1 (LibForeverInspector
  counters).

## 2026-11-04 — Task A README + What's-New (backfill)
- README.md: frontmatter `version: 0.9.1`, `updated: 2026-11-04`; new "What's New in
  v0.9.1" section added ABOVE the v0.9.0 section. Claims are additive-only and honest
  (queue-drop counters in `/tacotip diag`, one-arg CanInspect pin, migration/sanitize
  pins, comment corrections, separator constant) — no "fixed" language; the diag
  counters are described as new visibility, not as a behaviour change.

## 2026-11-04 — Task B1 counters (backfill)
- Libs/LibForeverInspector/LibForeverInspector.lua: inspectStats base table (~:412-428)
  gained `queueOverflowDrops = 0` and `queueDrainedDrops = 0` with the "additive
  observability, nothing reads them" comment; overflow counter increments at the
  `#queue >= 25` cap BEFORE `table.remove(queue, 1)` (:5115-5117); drain-shed counter
  increments in the tick's queue loop for entries that came off the queue and were
  not served (:5203-5205). main.lua collectInspectSection gained two diagRows after
  the requests/timeouts row: "queue overflow drops" and "queue drain drops" (info).
- Verified by read: no gate/timing logic reads either counter (local grep for both
  names shows only the three sites above and the diag row).

## 2026-11-04 — Task B2 one-arg CanInspect pin (backfill)
- Tests/harness/detect_test.lua (~:302-351): strict CanInspect mock RAISES on
  `select("#", ...) ~= 1`; pin asserts the observable consequences
  (`gateOk == answered and calls == 1 and raised == "(never)"`) because the raise is
  swallowed by probeCanInspect's pcall. GREEN 4 clients (era/TBC/forever/retail) x 3
  interpreters.
- RED proven on copy /tmp/opencode/releasetest-red (pcall(api, unit) -> pcall(api,
  unit, true)): all four client pins failed with raised="-> 2 arguments".

## 2026-11-04 — Task B3 queue-mechanics pins
- SCOPE DECISION: the watchdog window (documented 3s, strict `>`, timeouts == 1) and
  the throttle ordering were ALREADY pinned by detect_test.lua's ciB scenario
  (stepped 0.5s ticks, releasedAt > 2.5, timeouts == 1) — duplicating them would be
  a second pin on one behaviour without a new fact, so B3 pins the four mechanics
  that had NO pin: cap-25 oldest-drop + overflow counter, mouseover
  insert-before-top priority, re-hover bump-to-tail (mouseover-only condition),
  and the drain-shed counter.
- Tests/harness/detect_test.lua: new section inside the queue-mechanics do-block
  (after the ciC late-answer checks), reusing its build() helper; runs on TBC
  Anniversary 20506 (operator's target) + Classic Era 11509; observations are
  public-surface only: sequence received by a counting NotifyInspect mock,
  GetInspectStats().queueLength, and the two drop counters (queue itself is
  file-local). Way how: first DoInspect issues directly (pending slot), later
  calls queue behind it — the burst path; drain is tail-first (LIFO) so the served
  sequence IS the drain order.
- 6 checks per client, all GREEN (lua5.1/lua5.4/luajit):
  cap overflow counted ONCE at 26th enqueue (overflow=1 len=25 notifies=1);
  cap dropped the OLDEST (order=n0,n26,n25); served entries don't count as shed
  (drained=0); mouseover keeps the tail through later requests
  (order=n0,mouseover,n2,n1); re-hover bumps current hover to tail
  (order=n0,mouseover,focus — B's guid only resolves via the focus-token fallback);
  departed unit shed + counted (drained=1 order=n0,NA len=0 notifies=2).
- HONEST CAUGHT-ERROR: first (c) design mis-read the bump condition as applying to
  ALL re-hovers; the pin FAILED in the real tree (order=n0,mouseover,n2,n1) — the
  code should have been trusted first, the pin was then re-derived from the actual
  condition `unit == "mouseover" and i < #queue` (:5107). The pin caught ME, not a
  product bug — recorded so the mechanics stay sourced, not assumed.
- RED proven on copy /tmp/opencode/releasetest-red2 with one mutation at a time
  (lua5.1): M1 `table.remove(queue, 1)` -> `table.remove(queue, #queue)` kills
  "cap dropped the OLDEST" (order=n0,n26,n24); M2 plain append kills "hover
  priority" (order=n0,n2,n1,mouseover); M3 bump condition -> `if (false)` kills
  "re-hover bumps" (order=n0,focus,mouseover); M4 shed counter no-increment kills
  "shed ... counted" (drained=0). Each mutant fails exactly its own pin on both
  clients; copy restored + re-run ALL PASS. Fresh /tmp/opencode/releasetest-red2
  kept for B4 red demo, will be deleted at lane end.
- Next: Task B4 migration/sanitize pins in settings_test.lua (drive the live
  ADDON_LOADED handler, not the commented-out 2026-10-23 revert block).

## 2026-11-04 — Task B4 ADDON_LOADED migration/sanitize pins
- Tests/harness/settings_test.lua: new do-block inserted AFTER the commented-out
  2026-10-23 revert block, BEFORE "Registration shape". Drives the LIVE handler:
  TT.frame:GetScript("OnEvent") pcall'd as handler(frame, "ADDON_LOADED",
  "TacoTip_Forever") (same pattern as taint_test); TacoTipConfig swapped for
  literal SavedVariables tables and restored; "runs clean" asserted as an ERRORS
  delta because safeCall logs raises; conf_version expectations derived from the
  suite's own C_AddOns mock (no global GetAddOnMetadata in the harness, so
  main.lua resolved "0.7.8" through it) instead of a hardcoded literal.
- 7 scenarios: version-mock sanity + (a-1) upgrade clears exact legacy
  {TOPLEFT,TOPLEFT,0,0} + bumps conf_version; (a-2) upgrade keeps a real dragged
  position; (a-3) same-version load does NOT re-clear the legacy dot (the
  first_login gate); (b) sanitize clears nil-offsets and non-table shapes AND a
  valid position survives (per-load, same version).
- GREEN: all 20 run_all permutations (5 clients x settings/nosettings x
  pawn/nopawn) on lua5.1; TBC_ANNIV all 4 perms also on lua5.4 and luajit;
  luacheck clean on both touched harness files.
- RED proven on copy /tmp/opencode/releasetest-red2 (lua5.1), one mutation per
  run: M-A never-matching migration clears -> fails "legacy default dot is
  cleared" (1/62); M-B unconditional first_login -> fails "same-version ... NOT
  re-cleared" (1/62); M-C sanitize condition -> if(false) fails "nil-offsets"
  + "non-table" (2/62, controls stay green); M-D sanitize -> if(p) clears
  everything, fails all three SURVIVAL controls (3/62). First M-B/M-C/M-D runs
  were silent: M-B sed missed the indented line (anchor ^local), M-C/M-D
  crashed the load with a grep that swallowed the output — corrected patterns,
  re-run, attributed clean. Copy restored after each mutant, main.lua reverted,
  suite re-ran green.

## 2026-11-04 — Lane resumed (after usage-limit stop): B5, B6, CHANGELOG, README
- **B5 VERIFIED (read):** the suppressor install gate is lib:4940
  `if (not (isClassic or isTBC))`, and tests/harness/taint_test.lua:497-507 pins
  "Classic Era / TBC: inspect error suppressor is installed" against "NOT installed"
  on the other three. Rewrote both stale comments — lib:4643-4647 (mechanism note)
  and lib:4928-4939 (installer note) — to state Classic Era + TBC Anniversary only.
  Comment-only: zero code change, nothing outside those two comment blocks touched.
- **B6 VERIFIED (read):** both inline sites (main.lua:2349/2463 before the edit) were
  the identical string; hoisted `local SEPARATOR_LINE = "|cFF444444" ..
  string.rep("-", 30) .. "|r"` at main.lua:140 next to the pre-formatted constants
  and used it at main.lua:2350 and :2464. The runtime string is byte-identical (same
  concatenation, evaluated once at load instead of per render).
- **CHANGELOG:** 0.9.1 summary row at :7 and section at :25-48, directly above 0.9.0,
  matching existing style. Content is additive-only: two diag counters (visibility
  only), one-arg CanInspect pin, queue-mechanics pins, migration/sanitize pins, two
  comment corrections, hoisted separator, version bump. No "fixed" claims.
- **README review:** the v0.9.1 section overclaimed two things and was corrected:
  it credited the watchdog/throttle pin (pre-existing, not added in 0.9.1) and said
  "an in-source comment" (there are two, in Libs/LibForeverInspector). Also fixed
  the "shedds" typo and the "constants table" wording. The 130,000+ banner untouched.

## 2026-11-04 — Validation gate (final tree)
- `luacheck .` → 0 warnings / 0 errors in 87 files.
- `bash Tests/harness/run_all.sh` → 71/71 on lua5.1; `LUA=lua5.4` → 71/71;
  `LUA=luajit` → 71/71.
- `bash TacoTip_Extras/Tests/harness/run_all.sh` (default matrix) → 42/42 across
  lua5.1 / lua5.4 / luajit.
- `bash Tools/verify_release.sh --worktree` → PASS (version 0.9.1 consistent);
  `bash Tools/verify_release_extras.sh --worktree` → PASS. Both re-run after the
  last CHANGELOG edit.
- Residual `0.9.0`: CHANGELOG :8 + :52 and README :62 are the historical 0.9.0
  entry (expected); AGENTS.md:8 is workshop doc (not shipped); Tests/harness/
  load_test.lua:1148,1150 are historical check-label prefixes, not version pins;
  TacoTip_Extras/Tests/harness/load_test.lua:8852 is the 0.8.0-fingerprint mock
  fixture the previous lane deliberately left. No shipped file claims 0.9.0 as
  current; the version pins are 0.9.1 (load_test :1145-1146, :1586).
- conf_version first-login path re-confirmed against B4 pins: settings_test
  :1729-1766 — (a-1) upgrade clears the exact legacy dot and bumps conf_version,
  (a-2) a real dragged position survives, (a-3) same-version does NOT re-clear.
  No config reset.
- **Caveat:** every pin is pinned in the harness, not observed in game.

## 2026-11-04 — Cleanup
- Deleted /tmp/opencode/releasetest-red and /tmp/opencode/releasetest-red2 (the
  B2/B3/B4 red-proof copies). This lane created no new copies: B5 is comment-only
  and B6 is a same-bytes constant, and it added no new pin.

## 2026-11-04 — [signal:done] Release 0.9.1 ready for review
- Tree green: luacheck 0/0 (87 files), main 71×3, extras 42/42, both verifiers PASS.
- Files changed this lane: Libs/LibForeverInspector/LibForeverInspector.lua
  (:4643-4647, :4928-4939), main.lua (:140 constant; :2350 and :2464 uses),
  CHANGELOG.md (:7 row, :25-48 section), README.md (:56-58). Prior-lane work is
  already in the tree (toc/main/options version, B1 counters, B2/B3/B4 pins).
- Handoff: no behavior change; the diag counters are visibility only. The operator's
  in-game observation is the only acceptance for anything visual.
