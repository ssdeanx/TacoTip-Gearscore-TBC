# Five-client on-client test checklist — branches 11509 / 20506 / 38002 / 16001 / 120105

- **Date:** 2026-10-18
- **Desk:** `stage3-prep` (bench-only authoring; no code touched)
- **Sources compiled:** oracle in-game-only items
  (`bench/audits/2026-10-18-stage1-and-tier-a-oracle-audit.md` §5, 7 items) `[V]`,
  browser Tier-A UI pass (empty states, sort toggle, My-Rank, scan feedback,
  tooltip hint; oracle §4.1 pins at `rankbrowser_test.lua:975,1021,1028,1043,1075,1139`)
  `[V]`, wire-diet verification (`/ttgsdebug` counters, dead-channel skip, no
  whisper sends ever, byte sizes).
- **Branch map (TOC-verified, `TacoTip_Extras/TacoTip_Extras.toc:1`):**
  11509 = Classic Era · 20506 = TBC Anniversary · 38002 = Titanforge ·
  16001 = WoW Forever · 120105 = Retail `[V]`.
- **How to use:** work top-to-bottom (cold-login → guild → party/raid →
  instance → channel → browser → debug counters). Each row marks
  **SOLO** (one client suffices) or **2+** (two online clients required).
  Result cells are blank — fill per client: `pass / fail + note`.

Setup (every client): install the exact working-tree build under test on all
participating clients; `/ttgsdebug` is the instrument
(`TacoTip_Extras/Core.lua:664-690`, snapshot `RankSync.GetDebugState`,
`TacoTip_Extras/RankSync.lua:932`) `[V]`. Outcome buckets of interest:
`sends success/no-info/addon-throttle/channel-throttle/invalid-channel/other/error`,
`requeued`, `oversize-dropped`, `probes`, `self-rebroadcast`, whisper buckets
(expected all-zero after the whisper-drop lands), `scanForeignRealm`.

> **Whisper-drop status (updated mid-authoring):** the oracle BLOCKER has
> landed in the working tree — `respondToQuery(requestId, chatType, _sender)`
> (`TacoTip_Extras/RankSync.lua:665`), nil-transport answers take a counted
> `answerNoTransport` skip (`:693-702`), and the harness pins zero-whisper
> sends (`load_test.lua:3586-3626`). **[W]** rows below are therefore live
> assertions, not blocked items.

---

## 1. Cold login (SOLO unless noted)

| # | step | expect | 11509 | 20506 | 38002 | 16001 | 120105 |
|---|---|---|---|---|---|---|---|
| 1.1 | Fresh login, open chat log, run `/ttgsdebug` | no Lua errors on login; counters start at zero/absent keys read 0 (`Core.lua:664-690`) | | | | | |
| 1.2 | Wait ~10 s (join + 4 s deferred query + jitter) | one `Q` leaves on an available transport; no `InvalidChannel` storm | | | | | |
| 1.3 | Solo + guildless: first broadcast goes nowhere usable | nothing sent on CHANNEL while unjoined, OR channel-probe path taken; **no error, no chat spam** | | | | | |
| 1.4 | After channel join resolves | local record self-rebroadcasts **exactly once** (`self-rebroadcast == 1`; `RankSync` self-broadcast-once rule) | | | | | |
| 1.5 | `/reload`, wait again | no second self-rebroadcast for the same session state; `self-rebroadcast` does not climb per reload beyond one per join-proof | | | | | |
| 1.6 | Oracle item 4 — channel-join timing: slow join | force resync after a cold login on each client; exactly one resync lands even if the first `Q` was skipped while the channel id was nil | | | | | |
| 1.7 | Oracle item 6 — `GetServerTime` on Era | rank timestamps advance sanely; no epoch skew vs wall clock (stale rows do not vanish instantly, fresh rows do not read future-dated) | | | | | |

## 2. Guild scope (2+ — two guildmates online)

| # | step | expect | 11509 | 20506 | 38002 | 16001 | 120105 |
|---|---|---|---|---|---|---|---|
| 2.1 | A queries (`/ttgsdebug` resync), B online same guild | B's `S` answer arrives on **GUILD** (`answerForQuery` GUILD arm, `RankSync.lua:653`) and A's board gains B | | | | | |
| 2.2 | Leave-guild control (one client leaves) | no answer is sent to the ex-guild scope (gate suppresses = safe direction: missed answer, never wrong-scope answer) | | | | | |
| 2.3 | Guild chat stays clean | no system messages, no visible addon chatter from sync traffic | | | | | |

## 3. Party / raid (2+ — grouped, outside instances)

| # | step | expect | 11509 | 20506 | 38002 | 16001 | 120105 |
|---|---|---|---|---|---|---|---|
| 3.1 | Party of 2, resync | answers ride **PARTY** (never CHANNEL fallback); both boards converge | | | | | |
| 3.2 | Raid group (or raid-convert where available) | answers ride **RAID** (`answerForQuery` RAID arm); digest `T` pairs arrive whole | | | | | |
| 3.3 | Oracle gap — RAID/WHISPER arms are harness-untested | explicitly confirm a RAID-sourced `Q` produces a RAID `S` on each client (harness pins only GUILD/PARTY) | | | | | |

## 4. Instance (2+ — grouped INSIDE dungeon / BG / arena)

| # | step | expect | 11509 | 20506 | 38002 | 16001 | 120105 |
|---|---|---|---|---|---|---|---|
| 4.1 | Oracle item 3 — enter instance grouped, resync | traffic uses **INSTANCE_CHAT** (group-chat selection inside instances); peer board updates | | | | | |
| 4.2 | Instance answers stay in-instance | no PARTY-leak duplicates, no cross-instance bleed | | | | | |

## 5. Channel transport + probe state machine (SOLO for dead-channel; 2+ for live-channel)

| # | step | expect | 11509 | 20506 | 38002 | 16001 | 120105 |
|---|---|---|---|---|---|---|---|
| 5.1 | Oracle item 1 — Era CHANNEL result: `/ttgsdebug` after fresh login + resync | record `sendInvalidChannel` vs `sendNoInfo`: on 11509 the CHANNEL probe must show dead (`InvalidChannel(7)`) or legacy-nil (`sendNoInfo`); EITHER is acceptable, log which | | | | | |
| 5.2 | Oracle item 2 — Anniversary/Titanforge CHANNEL | same probe on 20506 + 38002: does `SendAddonMessage("CHANNEL")` succeed or die? Log result per branch — closes expansion §8 `[U]` | | | | | |
| 5.3 | Oracle item 5 — throttle tuning on Classic | spam resyncs; `sendThrottle`/`sendChannelThrottle` counted, messages requeued (not lost); channel NOT marked dead by transient throttles (3-strike probe rule only) | | | | | |
| 5.4 | Dead-channel skip, counted **[W]** (2+) | with CHANNEL dead, a channel-scoped query yields **zero sends on any transport** + counted `answerNoTransport` skip (`RankSync.lua:693-702`); digest path already skips | | | | | |
| 5.5 | **No whisper sends ever [W]** (2+) | across the whole pass: WHISPER send count stays zero; **no "Player is offline." system message** from sync traffic on any client | | | | | |
| 5.6 | Re-probe after 120 s (SOLO) | dead channel re-probes after the re-probe gate; on success state returns to active and pending self-broadcast flushes once (no duplicate) | | | | | |

## 6. Browser Tier-A UI (SOLO; 6.7 needs 2+)

| # | step | expect | 11509 | 20506 | 38002 | 16001 | 120105 |
|---|---|---|---|---|---|---|---|
| 6.1 | Empty DB, no filters (`/tt lb`) | first-run line (`LB_EMPTY`, `enUS.lua:202`) — NOT the filters line | | | | | |
| 6.2 | Type a match-nothing search | no-match line (`LB_EMPTY_FILTERS`, `enUS.lua:203`); clearing restores rows | | | | | |
| 6.3 | Sort toggle: click iLVL header twice | order flips, sort-hint arrow flips; `#` column still GearScore rank **both** directions | | | | | |
| 6.4 | Click My Rank with no local record | lands row 1 + `LB_NOT_ESTABLISHED` notice (`enUS.lua:204`); notice restores after ~2 s | | | | | |
| 6.5 | Run a scan to completion | status line (`LB_SCAN_COMPLETE`, `enUS.lua:244`) + pool count + exactly-once sound; no-sound path when sound API absent | | | | | |
| 6.6 | Hover any row | tooltip ends with the gear hint (`LB_TIP_CLICK_GEAR`, `enUS.lua:239`); click row opens the gear panel (or honest "not scanned" note) | | | | | |
| 6.7 | Class names localized (2+: cross-locale pair if possible) | dropdown + Spec column show localized names (`L["CLASS_"..x]`, `RankBrowser.lua:429-438`); EVOKER falls back to raw token where untranslated | | | | | |

## 7. Wire-diet + debug counters (SOLO tallies; 7.3 needs 2+)

| # | step | expect | 11509 | 20506 | 38002 | 16001 | 120105 |
|---|---|---|---|---|---|---|---|
| 7.1 | `/ttgsdebug` full line present | `sends success/no-info/throttle…`, `requeued`, `oversize-dropped`, `probes`, `self-rebroadcast` all print; absent keys read 0 | | | | | |
| 7.2 | Byte sizes: resync + inspect burst | typical `S` ≈ diet shape + new fields stays **≤240**; any validator-max-shaped row is split-or-refused, never silently truncated on the wire | | | | | |
| 7.3 | Digest integrity (2+) | `T` pairs ingest as whole records on the receiver (both halves land; no shifted fields from empty guild/spec) | | | | | |
| 7.4 | Request-id cap | long-id query produces responses with clamped id (≤8 echoed) and no message over 240 | | | | | |
| 7.5 | Throttle requeue | throttled send is requeued ahead of newer traffic (no loss, no reorder past the requeued item) | | | | | |

---

## Sign-off

| client | tester | date | build/rev | blockers |
|---|---|---|---|---|
| 11509 Era | | | | |
| 20506 Anniversary | | | | |
| 38002 Titanforge | | | | |
| 16001 Forever | | | | |
| 120105 Retail | | | | |

Carry-forwards (do NOT close on this pass — record and move on): CHANNEL-on-Anniversary/Titanforge verdict (§5.2), remote-`GetGuildInfo` behavior, `GetSpecializationInfoForClassID` content on TBC/Wrath, any `[W]` row while the whisper-drop is unlanded.
