# section1-delivery — Journal

## 2026-10-18 — Desk opened
- **Purpose:** Section 1 — Stage 1 delivery correctness for RankSync (TacoTip_Extras).
- **Scope:** `TacoTip_Extras/RankSync.lua`, `TacoTip_Extras/Core.lua` (/ttgsdebug only),
  `TacoTip_Extras/Tests/harness/load_test.lua`, `TacoTip_Extras/CHANGELOG.md`.
  Strictly out of scope: RankBrowser.lua, Locale/, Tooltips.lua, rankbrowser_test.lua,
  README, TOC files, bench/, anything outside the four files above.
- **Task source:** `bench/audits/2026-10-18-extras-rank-storage-expansion.md` §6.2 Stage 1
  (read fully, plus §3.1–3.3/§1 for measured failure cases) and the earlier review
  (`...-rank-system-review.md` §3.6, B3) for the first-login hole.
- **Baseline (before any edit):** `bash TacoTop_Extras/Tests/harness/run_all.sh` →
  `TOTAL 42 invocations: 42 passed, 0 failed` (lua5.1, lua5.4, luajit). Reproduced
  separately below.
- **Key verified API facts (source: /home/sam/wow-ui-source, all five branches):
  `SendAddonMessageResult` enum identical everywhere: Success=0, AddonMessageThrottle=3,
  InvalidChannel=7, ChannelThrottle=8 (classic_era ChatConstantsDocumentation.lua:151-163;
  same lines on anniversary/titan/live; forever :154-166). `C_ChatInfo.SendAddonMessage`
  returns `result` non-nilable (ChatInfoDocumentation.lua:358-372 on classic_era).
  warcraft.wiki.gg/wiki/C_ChatInfo.SendAddonMessage: WHISPER "Prints a 'Player is
  offline.' system message if the target is offline"; per-prefix allowance 10, refilled
  1/s; whispers outside instanced content are exempt from that allowance.
- **Design decisions made so far:** see the final desk report; everything is
  implemented in RankSync.lua (rawSend outcome capture + counters, channelSendTarget
  dead/probe state machine, same-channel answers + gated whisper fallback, 240-byte
  enqueue guard, 8-char id cap, INSTANCE_CHAT via groupChatType, re-resolve channelID
  to nil when the join is not effective, post-join re-broadcast of the local record
  armed whenever a record broadcast runs while the channel cannot carry).
- **Next step:** implement the edits; add the harness block; run suites; emit signals.

## 2026-10-18 — Implementation + green suite (checkpoint)

- **Signals:** checkpoint at `desks/section1-delivery/.signals/2026-10-18T12:54:16Z.json`
  (run_id stage1, subtype checkpoint).
- **Outcome:** `bash TacoTip_Extras/Tests/harness/run_all.sh` →
  `TOTAL 42 invocations: 42 passed, 0 failed` (lua5.1, lua5.4, luajit);
  `LINT=1` → luacheck `Total: 0 warnings / 0 errors in 26 files`, exit=0. Quote: real output.
- **Debugging trail worth keeping:** first failing run exposed three independent
  causes, each self-confessed by the checks' own details.
  (1) Lua's 200-live-locals main-chunk limit — the phase locals all stay in
  scope inside the protocol do-block, and earlier blocks already land the chunk
  near the ceiling; fix: run the block as a closure
  (`local runQueryProtocol = (function() ... end); runQueryProtocol()`, NOT a
  bare `(function...)()` — the `(` after an expression statement is the classic
  ambiguous-syntax error, and the closure must be declared BELOW `drain` since
  its body calls it).
  (2) Phase starvation: probe-success self-flush fires inside phase A (first
  drain = `[P;1, Q, R;<guid>]` — the arm was set by the previous block's
  QueueInspectRecord broadcast while the channel could not carry; correct per
  design), so the phase-B flush expectation was overtaken; leftover queue items
  then starved later phases through the token bucket (seen as `S;abc123`
  arriving during the fat phase, tagged GUILD). Fix: per-phase isolation sweeps
  (`isolationSweep`: tick, inert `;-flush` Enqueue to poke processQueue, drain).
  (3) REAL implementation bug the checks caught: the over-long digest pair
  enqueue emitted `head..first` only — the second record was dropped. Fixed in
  respondToQuery: both singles enqueue.
- **Harness shape:** 16 new named checks, all failing on pre-Stage-1 behavior
  (counters absent, no probe, CHANNEL-only answers, no whisper path, whole-id
  echo, queued-oversize); phase B removed; whisper-shape assert compares the
  9-byte prefix `S;wfall1;`.

## 2026-10-18 — Done

- **Signals:** done at `desks/section1-delivery/.signals/2026-10-18T12:55:00Z.json`
  (run_id stage1, subtype done).
- **Final validation (quoted from real runs):**
  `bash TacoTip_Extras/Tests/harness/run_all.sh` →
  `TOTAL 42 invocations: 42 passed, 0 failed`;
  `LINT=1 bash TacoTip_Extras/Tests/harness/run_all.sh` →
  `Total: 0 warnings / 0 errors in 26 files`, `luacheck exit=0`.
- **Scope kept:** RankSync.lua (972 lines), Core.lua (/ttgsdebug only),
  TacoTip_Extras/Tests/harness/load_test.lua (protocol block as a closure),
  TacoTip_Extras/CHANGELOG.md. Nothing staged or committed; the pre-existing
  uncommitted v1.2.3 + browser work from the other desk is untouched.
