# Oracle audit — Stage 1 delivery correctness + browser Tier A (read-only)

- **Date:** 2026-10-18
- **Desk:** `audit-stage1` (read-only audit; no production edits made)
- **Spec:** `bench/audits/2026-10-18-extras-rank-storage-expansion.md` §6.2 Stage 1 (+ §3.1–3.3 context)
- **Revision read:** working tree with section1-delivery (Stage 1), section2-storage (Stage 2),
  and tier-a-browser (Tier A) all landed, uncommitted. **The wire-diet desk
  (`section2b-wire-diet`) was live concurrently** — at read time its journal states intent
  only (redesign stride once, pre-release); `git diff` shows RankSync.lua still on the
  11-field `realm`-last stride (`RECORD_FIELDS = 11`, RankSync.lua:176), i.e. **no stride
  hunk had landed while I read**. Stage-1 delivery-path findings below therefore stand
  and do not overlap a stride hunk. If the stride changes after this report, re-check
  only the stride-dependent assertions (digest-split sizes, 10-vs-11 refusal); the
  transport/state-machine findings are stride-independent.
- **Evidence labels (CAIRN.md):** `[V]` VERIFIED (read in source or produced by a command
  I ran), `[A]` ASSUMED (say what would verify), `[U]` UNKNOWN.
- **Harness state at this audit:** `bash TacoTip_Extras/Tests/harness/run_all.sh` →
  `TOTAL 42 invocations: 42 passed, 0 failed` on lua5.1/lua5.4/luajit `[V]` (re-ran);
  `LINT=1` → `Total: 0 warnings / 0 errors in 26 files`, `luacheck exit=0` `[V]` (re-ran).

---

## 0. Verdict

**Stage 1 delivery: CONDITIONAL FAIL — one blocker.** The implementation is otherwise
coherent and well-pinned (same-transport answers, probe state machine, counted outcomes,
240-byte door with digest-split, throttled-send requeue, 8-char id cap, once-per-session
re-broadcast, INSTANCE_CHAT alongside PARTY/RAID). But it ships the **gated whisper
fallback the operator explicitly dropped**: responses must use only the same chat type as
the query, with no whisper path at all. `RankSync.lua` still sends on `WHISPER`
(RankSync.lua:721-737), the harness still pins three whisper checks (load_test.lua:3554-3627),
`/ttgsdebug` still surfaces five whisper counters (Core.lua:685-689), and the CHANGELOG
still documents the fallback (CHANGELOG.md:139-149). Any whisper send risks the exact
user-visible failure the gate was built to avoid ("Player is offline." system message).
Remove the whisper path entirely — code, tests, debug lines, changelog — before merge.

**Browser Tier A + orchestrator merges: PASS with minors.** Every Tier A changelog claim
checked matches code and is pinned by a test that actually asserts the behavior
(empty states, direction flip with `#`-invariant in both directions, tooltip hint,
My-Rank notice with timer restore, localized class names + EVOKER fallback + `value`
selection, scan-complete edge with pool count + single sound + guards, arrow-byte fix).
Minors: one stale code comment, stale changelog line-number refs, two check-count drifts.

---

## 1. BLOCKER — the whisper fallback must go (correction: no whisper path at all)

The task correction is unambiguous: *"responses must only use the same chat type as the
query, with no whisper path at all. Verify this: any whisper-channel send, whisper queue,
or 'Player is offline.'-prone path is a BLOCKER finding."* The tree still contains all three:

| surface | location | what it does |
|---|---|---|
| whisper send | `RankSync.lua:721-737` (`maybeWhisperAnswer` → `Enqueue(..., "WHISPER", sender)`) | sends `S;<id>;<payload>` on WHISPER |
| sender resolution | `RankSync.lua:678-705` (`resolveSenderUnit`, 84-token sweep) + `whisperedRequests` ring `RankSync.lua:709-719` | supporting machinery, ~60 lines |
| fallback call site | `RankSync.lua:755-772` (`respondToQuery`: `answerType==nil` → `maybeWhisperAnswer`) | the only consumer of the nil-transport case |
| WHISPER answer arm | `RankSync.lua:638-639` (`answerForQuery` returns `{"WHISPER", sender}` for WHISPER queries) | a WHISPER-*query* answered on WHISPER is same-transport and stays; the *fallback* is what must go — but note the arm and the fallback share the `"WHISPER"` chat-type string, so delete carefully |
| debug surface | `Core.lua:685-689` (five whisper counters) + `RankSync.lua:998-1011` (`GetDebugState` ships them) | must shrink with the code |
| harness pins | `load_test.lua:3554-3627` (3 checks: exactly-one-whisper, unresolvable skip, offline skip) | must be rewritten, not just deleted (see §3.5) |
| changelog | `TacoTip_Extras/CHANGELOG.md:139-149` ("gated whisper fallback" subsection) + `:167-172` ("whisper pins" in the harness paragraph) | must be rewritten to state the dropped fallback and the counted silent skip |

Why this is a blocker and not a preference: the operator's correction exists because a
background sync must never print chat-system noise. The gate (`UnitExists` + base-name
match + `UnitIsConnected`, RankSync.lua:688-701) reduces but does not eliminate the
risk — connected-at-answer-time does not mean connected-at-delivery, and every whisper
is a user-visible chat event on all five clients `[V]` (spec §3.1 table; wiki). `[A]`
that no other whisper send exists: grep for `"WHISPER"` in `TacoTip_Extras/*.lua` returns
only the sites above — verify with `grep -rn '"WHISPER"' TacoTip_Extras/` before merge.

**Required replacement (strategy, not code):** when `answerForQuery` returns nil (dead /
unjoined channel, or not-in-group/guild for that transport), the S must be a **counted
silent skip** (new outcome bucket, e.g. `answerNoTransport`), not an uncounted drop —
otherwise the fix trades a noisy fallback for a silent hole (§3.5). The digest already
skips correctly (`if ... and answerType`, RankSync.lua:784). The three harness whisper
pins become: (i) dead-channel query → zero sends on any transport + `answerNoTransport`
counted; (ii)/(iii) collapse into the same skip (sender resolution becomes irrelevant —
delete `resolveSenderUnit`, the token tables, and the 64-entry ring with it).

---

## 2. Stage 1 item-by-item (spec §6.2 Stage 1, items 1–5)

### 2.1 Item 1 — arg3/arg4 threading + same-transport answers — IMPLEMENTED, PARTLY PINNED (major gap)

- **Implemented `[V]`:** `onEvent` reads `arg3` (channel) / `arg4` (sender) per
  `ChatInfoDocumentation.lua` payload order (prefix, text, channel, sender — verified on
  live `:803-816` and classic_era `:615-628` `[V]`) and threads both into `handlePayload`
  (RankSync.lua:1020-1030). `answerForQuery` (RankSync.lua:630-642) maps
  GUILD→GUILD (gated on `IsInGuild`), PARTY/RAID/INSTANCE_CHAT→same (gated on `IsInGroup`),
  CHANNEL→CHANNEL (gated on `channelSendTarget`), WHISPER→WHISPER. Pre-Stage-1 code
  answered everything on CHANNEL (spec §1 table, `RankSync.lua:318-319,338-339` pre-edit) `[V]`.
- **Pinned for 2 of 6 transports (major gap):** harness asserts GUILD transport
  (load_test.lua:3317-3331) and PARTY transport (load_test.lua:3469-3483). **No check
  answers a Q on RAID, INSTANCE_CHAT, CHANNEL-while-active, or WHISPER** — the
  `answerForQuery` arms at RankSync.lua:636-639 execute in production but never in the
  harness. A typo in any of those three arms passes the suite. Each missing arm needs
  one `HandlePayload("Q;…", <chatType>)` → `drainSends()` → `chatType ==` assertion.
- **End-to-end threading unpinned:** the harness calls `RankSync.HandlePayload(payload,
  chatType, sender)` directly (load_test.lua:3311 etc.) and **never fires `CHAT_MSG_ADDON`
  through `fireEvent`** (only `ADDON_LOADED` and `PLAYER_ENTERING_WORLD` go through
  `fireEvent`, load_test.lua:2002/2186/3757). A regression swapping arg3/arg4 in `onEvent`
  (RankSync.lua:1020-1023) passes every check. One `fireEvent("CHAT_MSG_ADDON", PREFIX,
  "Q;…", "GUILD", "Someone")` check closes it.

### 2.2 Item 2 — channel proof state machine + INSTANCE_CHAT — IMPLEMENTED, GAPS NOTED

- **Implemented `[V]`:** probe (`P;<n>`, peers ignore non-R/Q/S/T first bytes via
  `handlePayload`, RankSync.lua:374-388), `InvalidChannel`→dead (RankSync.lua:358-361),
  sustained-throttle→dead after 3 strikes (RankSync.lua:362-367), 120 s re-probe gate
  (RankSync.lua:347-397), every send site routes through `channelSendTarget`
  (RankSync.lua:136-140; broadcast RankSync.lua:472/604, answer RankSync.lua:632).
  Join re-resolves id to nil instead of layering on stale (RankSync.lua:116-131).
  `INSTANCE_CHAT` selected inside raid/pvp/arena instances (RankSync.lua:297-322) `[V]`.
- **Pinned `[V]`:** InvalidChannel→dead (load_test.lua:3541-3552), re-probe withheld then
  re-probed to active (load_test.lua:3629-3669), once-per-session re-broadcast exactly once
  (load_test.lua:3670-3675; `flushSelfBroadcast` RankSync.lua:328-343; arm on
  channel-incapable broadcast RankSync.lua:477-479).
- **Gaps:**
  1. **INSTANCE_CHAT never exercised (major):** harness pins `IsInInstance → false`
     (load_test.lua:3193) for the whole protocol block. `groupChatType`'s
     `INSTANCE_CHAT` return (RankSync.lua:318-319) and the `INSTANCE_CHAT` answer arm
     (RankSync.lua:636) never fire. Needs one phase with `IsInRaid → true`,
     `IsInInstance → (true, "raid")` asserting broadcast + answer ride `INSTANCE_CHAT`.
  2. **Sustained-throttle dead-marking unpinned (minor):** only a single throttle→requeue
     is pinned (load_test.lua:3508-3536); the 3-strike path (RankSync.lua:362-367) never
     fires (probe outcomes `sendSuccess`/`sendNoInfo`→active also never fire directly —
     active is reached via the re-probe phase with `sendResultValue = 0`, which does
     exercise `noteProbeOutcome` success `[V]`).
  3. **Probe queue-bypass unpinned (minor):** `enqueueChannelProbe` refuses to evict when
     the queue is full (RankSync.lua:381) — no check fills the queue to 50 and probes.
     Related limbo: if the queue is full the probe is dropped but state stays `probing`
     with no in-flight probe; recovery waits for the next `syncNow`. In-game-only
     (queue-full-for-minutes is unlikely), but a one-line note in the state machine
     comment would help the next reader.
  4. **Single-`InvalidChannel`-from-any-real-send kills the channel (in-game checklist):**
     RankSync.lua:424-427 marks dead on any real send's `InvalidChannel`. On live a
     transient bad id (rejoined channel, id changed, re-resolve not yet run) suppresses
     the channel for 120 s. Re-resolve runs on every `syncNow` (RankSync.lua:926-942),
     so recovery is bounded — but the 120 s suppression after one transient refusal is
     only provable in game (real `SendAddonMessageResult` values per client family).

### 2.3 Item 3 — counted send outcomes + `/ttgsdebug` — IMPLEMENTED, TWO BUCKETS UNPINNED

- **Implemented `[V]`:** `rawSend` buckets Success→`sendSuccess`, Throttle(3)→`sendThrottle`,
  InvalidChannel(7)→`sendInvalidChannel`, ChannelThrottle(8)→`sendChannelThrottle`,
  nil (classic-family legacy global)→`sendNoInfo`, else→`sendOther`, pcall failure /
  no API→`sendError` (RankSync.lua:256-295). Enum values verified identical on all five
  branches `[V]` (live/classic_era/classic_anniversary/classic_titan `:151-159`,
  forever `:154-162`; `SendAddonMessage` returns non-nilable `SendAddonMessageResult`,
  live `ChatInfoDocumentation.lua:516-541` `[V]`). Throttle keeps the item queued with no
  token spent (RankSync.lua:411-418) — the pre-Stage-1 pop-and-lose is gone `[V]`.
  `/ttgsdebug` prints channel state/id/failures, token bucket, queue depth,
  self-broadcast pending, and all buckets (Core.lua:664-690) `[V]`.
- **Pinned `[V]`:** `sendThrottle` + `requeued` counted (load_test.lua:3515-3521),
  requeued item delivered on next tick ahead of newer traffic (load_test.lua:3526-3536).
- **Unpinned (major):** the **legacy-global path** (RankSync.lua:267-273) and the
  **`sendNoInfo` bucket** never fire — the harness always mocks
  `C_ChatInfo.SendAddonMessage` (load_test.lua:3180-3185) and never the bare
  `SendAddonMessage` global, nor a nil result. If Classic Era calls the legacy global
  (the audit's `[A]`), the most-deployed branch's most-common outcome is the least-tested.
  Needs one phase with `C_ChatInfo=nil`, legacy `SendAddonMessage` stubbed, asserting
  `sendNoInfo` increments and the probe goes `active` (RankSync.lua:354 treats no-info as proof).
- **Unpinned (minor):** `sendOther`, `sendError`, `sendChannelThrottle`,
  `enqueueOversize` buckets never fire (no >240 direct-`Enqueue` check; the fat-digest and
  long-id phases stay under the door by split/clamp, so the refusal path itself is
  untested). `GetDebugState` snapshot is asserted; the **`/ttgsdebug` print lines are
  never asserted** (no harness captures `addChatLine`/chat output) — a renamed bucket key
  in Core.lua vs RankSync.lua would pass silently.

### 2.4 Item 4 — 240-byte door + digest-split + id cap — IMPLEMENTED AND PINNED `[V]`

- Door refuses `> MAX_PAYLOAD_BYTES` at enqueue with `enqueueOversize` count
  (RankSync.lua:432-450) `[V]`; over-long two-record digest splits into two singles,
  both directions (RankSync.lua:791-809 — including the stage-1 self-caught fix where the
  second record was dropped) `[V]`; inbound ids clamped to 8 at the door
  (RankSync.lua:898) and second-gated in `respondToQuery` (RankSync.lua:753); outbound ids
  fixed-width 6 (`%04x%02x`, RankSync.lua:589-592) `[V]`.
- Pinned: door (load_test.lua:3450-3452), split-both-halves-travel (load_test.lua:3465-3468),
  PARTY transport on the fat phase (load_test.lua:3481-3483), 240-char id → ≤240 total
  (load_test.lua:3501-3503) and 8-char echo (`sub(11,11)==";"`, load_test.lua:3504-3506) `[V]`.
- Minor: outbound 6-hex shape never asserted (only inbound clamp); the 255-byte pre-existing
  check (load_test.lua:3339-3341) overlaps the 240 door without conflict. Changelog says
  "16 new named checks" — the Stage-1 additions block holds **14** `check(` calls
  (load_test.lua:3419-3676); 16 only if the two pre-existing transport/size checks are
  counted. Count drift, not a behavior gap.

### 2.5 Item 5 — once-per-session re-broadcast after channel join — IMPLEMENTED AND PINNED `[V]`

Arm when broadcast runs channel-incapable (RankSync.lua:477-479), flush once when probe
proves the channel (RankSync.lua:353-357 → 328-343), `selfBroadcastDone` guard prevents
reruns (load_test.lua:3670-3675 asserts `selfRebroadcast == 1` and zero reruns) `[V]`.
Edge: `BroadcastRecord` on a live channel sets `selfBroadcastDone = true`
(RankSync.lua:474-476), so a later die-and-reprove cycle does not re-broadcast — correct
per "once-per-session" and pinned by `reprobeReruns == 0` `[V]`.

---

## 3. Holes hunted in the treat-visitors-as-native design

1. **Silent-skip accounting after the whisper drop (major, fix with §1):** today every
   nil-transport answer funnels to `maybeWhisperAnswer`, which *counts* each outcome
   (`whisperSent/NoSender/Unresolved/Offline/Repeat`, RankSync.lua:722-734). Deleting the
   fallback without adding an `answerNoTransport`-style bucket turns dead-channel queries
   into fully silent non-answers — worse observability than the current code. The digest
   path already skips silently-by-design (RankSync.lua:784); the S path must count.
2. **Same-transport answers cannot leak cross-scope `[V]`:** PARTY/RAID/GUILD/CHANNEL
   messages only reach members, so answering on the query's transport is inherently scoped
   — no cross-realm or cross-group leak is constructible from `answerForQuery`. The
   `IsInGuild`/`IsInGroup` gates (RankSync.lua:635/637) only suppress answers after leaving
   the scope, which is the safe direction (a missed answer, never a wrong one).
3. **No-token-spent requeue is sound `[V]`:** `processQueue` breaks without popping and
   without decrementing on throttle (RankSync.lua:411-418); the harness proves the
   requeued item precedes newer traffic (load_test.lua:3526-3536). Strike counting only
   on probes (RankSync.lua:365) means real-traffic throttles never kill the channel —
   deliberate and correct, since throttles are transient by documentation.
4. **InvalidChannel recovery on live vs Classic (in-game checklist):** code treats one
   `InvalidChannel` as proof-of-dead on every branch (RankSync.lua:358-361, 424-427).
   Correct on Classic Era (addon traffic removed 1.13.3); on live a transient bad id could
   cost 120 s of channel use. Recovery path (re-probe → active → self-broadcast already
   consumed → no duplicate) is coherent in code but only provable with real
   `SendAddonMessageResult` values per client family.

---

## 4. Secondary scope — browser Tier A + orchestrator merges: PASS with minors

### 4.1 Claim-by-claim (CHANGELOG.md:175-228 vs code + tests) — all hold `[V]`

| claim | code | test pin |
|---|---|---|
| three empty states (`LB_EMPTY` / filters / `LB_ONLY_YOU`) | RankBrowser.lua:918-929 | rankbrowser_test.lua:1020-1050 (exact-string asserts) |
| direction flip, `#` stays GearScore rank both directions | RankBrowser.lua:216-284 (`sortAsc`), `:833-843` | rankbrowser_test.lua:886-930 (ascending order + arrow flip + `#` invariant both directions) |
| tooltip ends "Click to view gear" (`LB_TIP_CLICK_GEAR`, enUS + per-key fallback) | RankBrowser.lua:348; enUS.lua:239 | rankbrowser_test.lua:975 (`joined:find("Click to view gear")`) |
| My-Rank with no record → row 1 + `LB_NOT_ESTABLISHED`, timer restore, no-timer degrade | RankBrowser.lua:876-882 | rankbrowser_test.lua:1060-1100 (offset 0, notice text, 2 s schedule, restore, `C_Timer=nil` absence path) |
| localized class names + EVOKER raw-token fallback + `value` selection | RankBrowser.lua:433, 1177-1182 | rankbrowser_test.lua:690-730 (`entry.value` matching, "Mage", EVOKER, Spec-column "Mage") |
| scan-complete edge: text + pool count + exactly-once sound + guards | RankBrowser.lua:499-539 | rankbrowser_test.lua:1104-1160 ("Scan complete", "36 players tracked", `playedSounds==1`, no-sound absence path) |
| arrow-byte fix `\226\150\188`/`\226\150\178` | RankBrowser.lua:224-225 | byte-agnostic by design: `hintArrow` compares last tokens (rankbrowser_test.lua:838-841), so the fix is pinned behaviorally, not byte-literally — the changelog's "escaped every review because assertions are byte-agnostic" is accurate `[V]` |
| 80→122 checks | `grep -c "check(" rankbrowser_test.lua` → **123** | off-by-one count drift (minor, §4.2.3) |
| non-English locales carry old keys | deDE/frFR/zhCN `:200-204` carry `LB_EMPTY/LB_EMPTY_FILTERS/LB_NOT_ESTABLISHED/LB_ONLY_YOU/LB_FILTER_ALL` `[V]`; `LB_TIP_CLICK_GEAR`/`LB_SCAN_COMPLETE` only in enUS (grep: no other locale) with per-key English fallback in `TacoExtrasApplyLocale` (enUS.lua:341-346) `[V]` | fallback itself unpinned by a locale test (minor — the code path is 6 lines, but a partial-locale test would be cheap) |

### 4.2 Minors

1. **Stale comment (minor):** RankBrowser.lua:497-498 says the scan-complete line "carries
   no locale key yet … ships English until [eleven-file sync] can happen" — but
   `LB_SCAN_COMPLETE` exists (enUS.lua:244) and is used with fallback (RankBrowser.lua:515).
   The orchestrator's keying made the comment false. One-line comment fix.
2. **Stale changelog line refs (minor):** `RankDB.lua:125/219/393` → actual
   `RankDB.lua:230-231` (`ValidateRecord` bound), `:407-408` (`BuildSortedIndices` cutoff),
   `:581-582` (`PruneStaleRecords` cutoff); `RankSync.lua:897` (`syncNow`) → actual
   `RankSync.lua:969-993`. Stage 2 moved the code; the refs point at heap/sort code now.
   `RankBrowser.lua:104` and `Scanner.lua:173` are still correct `[V]`.
3. **Check-count drifts (minor):** "16 new named checks" (§2.4: actually 14 in-block);
   "80→122" (§4.1: actually 123 `check(` occurrences). Cosmetic; do not re-count precisely,
   just soften to "≈" or recount once.
4. **No dead keys found `[V]`:** `LB_TIP_CLICK_GEAR` and `LB_SCAN_COMPLETE` are both read
   (RankBrowser.lua:348/515) and defined (enUS.lua:239/244); every `L["…"]` Tier A read has
   a same-file English fallback. No assertion pins a behavior its name doesn't claim —
   each sampled check asserts the literal string/behavior in its label.

### 4.3 Out of scope, untouched as instructed

The "Storage hygiene (Stage 2)" CHANGELOG subsection (CHANGELOG.md:230-287) was **not
checked** — the wire-diet desk owns that file concurrently. All Tier A findings above are
stride-independent.

---

## 5. In-game-only test checklist (operator's client pass)

These cannot be settled offline; each needs a real client and is labeled:

1. **`[U]` Real `SendAddonMessageResult` values per family.** Does Classic Era return
   `InvalidChannel(7)` on CHANNEL, or does the legacy global (nil result) fire instead?
   Log `GetDebugState().outcomes` after `/ttgsdebug` on each of the five branches after a
   fresh login + one `/ttgsdebug` resync. Decides whether the probe ever sees 7 on Era.
2. **`[U]` CHANNEL addon traffic on Anniversary/Titanforge.** Spec §8 open question stands:
   `SendAddonMessage` on `"CHANNEL"` + log result (enum exists on all five,
   `ChatConstantsDocumentation.lua:151-163` classic / `:154-166` forever `[V]`).
3. **`[U]` `INSTANCE_CHAT` delivery inside raid/pvp/arena instances.** Group up, enter,
   force resync, confirm the peer's board updates (harness never exercises this path, §2.2.1).
4. **`[U]` Channel-join timing.** `joinSyncChannel` resolves `GetChannelName`
   synchronously + one 4 s retry (RankSync.lua:110-143, 923-943). On a slow join the id is
   nil and the first `RequestSync` is skipped silently — confirm one resync lands after a
   cold login on each client.
5. **`[U]` Throttle-strike tuning on Classic.** 1.13.4 tightened throttling; the 3-strike
   / 120 s constants (RankSync.lua:53-54) are reasonable but unmeasured against real
   `AddonMessageThrottle(3)` / `ChannelThrottle(8)` rates.
6. **`[A]` `GetServerTime` on Era.** Global exists (called by Blizzard's own
   `CommunitiesTicketManagerDialog.lua:67,87` on classic_era `[V]`); the guarded form
   (`GetServerTime and … or 0`, RankDB.lua:230 etc.) degrades safely regardless. Confirm
   no epoch skew vs `time()` on Era.
7. **`[A]` Whisper-path deletion.** After §1 lands: dead-channel query → zero sends on any
   transport + new skip bucket counted in `/ttgsdebug`; no "Player is offline." ever
   surfaces from sync traffic. (The current gate's offline-skip behavior is deleted with it.)

---

## 6. Files live at read time (concurrency note)

`RankSync.lua` (1044 lines, 11-field stride intact), `Core.lua` (debug block
`:660-690`), `load_test.lua` (protocol block `:3143-3693`, Stage-2 block after),
`RankBrowser.lua` (Tier A hunks + `\226\150\188`/`\226\150\178` at `:224-225` +
`LB_SCAN_COMPLETE` wiring at `:499-539`), `Locale/enUS.lua` (`:239`,`:244`),
`rankbrowser_test.lua` (123 checks), `CHANGELOG.md` (`[1.2.3]` Stage-1 `:109-173`,
Tier A `:175-228`, Stage 2 `:230-287`). Wire-diet journal showed intent-only, no stride
edits landed mid-read (stride grep clean). Stage-1 findings stand unless a later stride
hunk touches the digest-split sizes.

---

## 7. Outcome ratings (emitted per signal-write)

- **section1-delivery:** quality_rating **2** — all five Stage-1 items implemented
  coherently with genuine self-caught fixes, but the headline correction (drop the whisper
  fallback) is unimplemented; plus untested INSTANCE_CHAT/legacy-nil/end-to-end-event paths.
  effort_to_merge **moderate** (delete ~110 whisper lines + rewire skip counting + rewrite
  3 harness pins + debug + changelog). Issues in signal JSON.
- **tier-a-browser:** quality_rating **4** — claims match code, pins assert what they name,
  orchestrator merges correct (arrow bytes, `LB_SCAN_COMPLETE` keying). effort_to_merge
  **minimal**. Issues: stale comment, stale changelog line refs, count drifts.
