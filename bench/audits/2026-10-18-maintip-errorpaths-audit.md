# Silent Failure Hunt: Main TacoTip addon — v0.8.4

**Placement note:** the reviewing session had no file-write and no shell tools; this report is filed verbatim from its inline handoff by the orchestrator. All claims are source-reads, labelled per CAIRN. `Tests/harness/run_all.sh` 54/54 claims are UNVERIFIED in that session.

**Files reviewed:** 13 (5 root Lua + `LibForeverInspector.lua` + `LibDetours-1.0.lua` + 6 harness files + `textures.lua`/`textures.txt` + `run_all.sh` + `README.md` + CHANGELOG 0.8.3/0.8.4). **Error-handling/fallback locations:** ~92. **Suspicious patterns:** 24. **Disposition:** 4 confirmed defects (CRITICAL), 11 requiring justification (HIGH), 9 justified exceptions (0 hidden).

## Critical Issues — Must Fix

### C1: Queue overflow drops the oldest inspect without counting it — CONFIRMED DEFECT

`Libs/LibForeverInspector/LibForeverInspector.lua:4874-4877`. `if (#queue >= 25) then table.remove(queue, 1) end` — the evicted guid, frequency, and whether it was the current target are all unrecorded; `DoInspect` returns `true` regardless. In a 40-raid + target + mouseover burst the queue is permanently full and the oldest (often the looked-at target) is discarded every insert, with no loading indicator and no diag counter. **Fix:** count the eviction (`inspectStats.queueDropped += 1`, optionally last evicted guid/age), surface in `GetInspectStats` + diag, or reject the insert instead of silently replacing. VERIFIED by source read.

### C2: Every clock falls back to `0` — a missing `GetTime` wedges cooldowns, throttles and freshness permanently — CONFIRMED DEFECT

`gearscore.lua:111`, `LibForeverInspector.lua:3786/3857/4208/4248/4362`, `main.lua:3742`. All clocks read constant `0` when `GetTime` is absent: item-data throttle latches after the first request per itemID (tooltips stay blank until reload); `inspectRejected` never expires (once-refused unit blacklisted for the session); `isCacheFresh` misreads. None surfaces in diag. **Fix:** single `clockAvailable` probe at load, `problems[]` entry, fail-open (skip throttle/cooldown) rather than fail-wedged; never memoise `0`. VERIFIED — identical `or 0` shape at all sites; `reportSilentFailures` (main:3476-3568) does not check `GetTime`.

### C3: Pawn late-load is a permanent silent amputation — CONFIRMED DEFECT

`pawn.lua:11-16`, `options.lua:11-16`. File-scope `isPawnLoaded` probe runs once; no `ADDON_LOADED` re-check. Enabling/installing Pawn after TacoTip loaded = zero Pawn scores for the session, diag silent, harness never exercises the early-return. **Fix:** defer the gate to call time or listen for `ADDON_LOADED`; diag `problems[]` entry distinguishing "Pawn late" from "no scale". VERIFIED — no `RegisterEvent("ADDON_LOADED")` in `pawn.lua`.

### C4: File-scope aborts precede diagnosability — CONFIRMED DEFECT

`main.lua:7-9` (`assert(LibStub…)`), `LibForeverInspector.lua:103` (bare `GetBuildInfo()`). `TT.LOAD_STAGE` is set at line 35 — after the asserts — so a load failure leaves no stage, no `LOAD_OK=false`, no diag; the mover's "not ready — /reload" branch then misadvises. **Fix:** move `TT` + `LOAD_STAGE="begin"` above all asserts/extern calls; soft aborts instead of asserts; guard `GetBuildInfo` with a `type` check defaulting to family-unknown. VERIFIED — line order read.

## High Severity Issues (requires justification each — see inline needs)

- **H1:** `scan skipped (range)` counts three different failures as one distance (`LibForeverInspector.lua:5004-5007, 5122-5143`; comment 5037-5045 documents the merge as intentional). Fix: split into `scanSkippedDistance` + `scanFaults`. Needs: confirm no consumer depends on the merged number.
- **H2:** `DoInspect` reports `true` for "queued", not "requested" (`:4860-4879`; tooltip caller discards even that boolean at `main.lua:1717`). Fix: tri-state/second value, or `false` when full. Needs: contract decision.
- **H3:** `safeCall` dedups by message — bursts and second defects invisible (`main.lua:246-266`; no `pipelineErrorsSuppressed` count). Fix: bounded top-5 ring + counts beside `lastTooltipError`. Needs: confirm cold-path allocation satisfies the hot-path budget (`main.lua:3331-3339`).
- **H4:** Unknown-unit talent defaults assert unprovided knowledge — `lib:5421` (nil guid → 1), `:5430` (fallback 1), `:5272` (`cached.specIndex or 1`). Survivors of the fixed spec-1 invention; the fix's own rationale convicts them. Return nil for unknown; gate points readout on data presence. CONFIRMED DEFECT (kept HIGH per rubric).
- **H5:** Absent `C_Timer` silently disables the entire inspect engine (`:5167-5177`; else branch is nothing; no `problems[]` entry). Fix: record `lib.tickersInstalled=false` + diag problem. Needs: confirm any client with legitimately late `C_Timer`.
- **H6:** Not-ready GearScore/Pawn read as absent with no pending state (`gearscore.lua:405-412, 570-574`; `pawn.lua:141-144, 207-209`). Tooltip shows no GS line identically for "never inspected" / "streaming" / "throttled". Fix: "pending" third state or `gsPendingHidden` counter. Needs: UX decision (loading row vs counter-only).
- **H7:** Options registration failures swallowed; panel just never appears (`options.lua:533/555/568/599` pcall booleans; `applyScanSetting` no counter/print). Fix: narrow pcall, log err, diag entry; checkbox reflects actual `lib.scanEnabled`. Needs: chat-print vs diag-only UX call.
- **H8:** Item path without `Item` object API fires a request it can never repaint from (`main.lua:2605-2661`; failure discarded, no counter). Fix: `itemRefreshFireAndForget` counter; bounded one-shot re-render if platform allows. Needs: confirm any supported client actually lacks `Item.CreateFromItemLink`.
- **H9:** Blizzard guild-frame guard swallows without counting (`main.lua:3180-3186`). Fix: `TT.ev.inspectGuildGuardCaught` + diag line. Trivially safe; needs explicit owner acceptance.
- **H10:** Single pending slot + 3s watchdog loses attribution under burst (`:4901-4911`, `pendingRefusal` lifecycle). Fix: per-request timestamps or bounded in-flight set; `maxQueueWait`/`avgQueueWait` stats. Needs: live timing data.
- **H11:** `last inspect-call error` vs `probe errors suppressed` double-count and stale-read (`:4354-4359`, `main.lua:3441-3443`). Fix: document overlap in label, clear/timestamp `lastError`, or split `rejectedRaise`/`rejectedAsync`. Needs: decide what the operator triages on.

## Medium Severity Issues

- **M1:** `tooltipIsMouseover` maps engine failure to `false` (`main.lua:1040-1060`) — silently disables instant-fade hiding; keep default, add counter + diag.
- **M2:** All `resolveTooltipUnit` failures collapse to one `nil` (`main.lua:981-1032`) — per-cause counters or last-cause value.
- **M3:** Tooltip width-cap fails silently (`main.lua:83-92, 108/115`) — JUSTIFIED EXCEPTION (per-render cosmetic, retried next render).
- **M4:** Portrait `pcall`s discard failures (`main.lua:1219-1231, 1523`) — `TT.ev.portraitSetFailed` + diag (cold path).
- **M5:** `RegisterUnitEvent` failures discarded (`main.lua:2345-2347`) — bar silently frozen; diag checks API presence but not registration.
- **M6:** Media-resolver fallbacks partially diagnosed — border diagnosed, font/bar/background silent (`options.lua:937-972` vs `main.lua:3506-3528`). CONFIRMED minor.
- **M7:** Russian MONK/DEMONHUNTER/EVOKER names are German/English placeholders (`LibForeverInspector.lua:327-329`) — confidently-wrong-but-plausible localisation; loc table preferred over English. CONFIRMED minor.
- **M8:** Harness `WM` catch-all hands every unknown method as no-op (`tooltip_test.lua:120` + equivalents) — any *new* widget-method probe invisible to suite; `C_Timer` no-ops mean deferred bodies untested. Fix: deny-by-default strict run or manual ticker drive.
- **M9:** `playerClass` latched at file scope (`main.lua:228`) — nil at load corrupts HunterScore gate for the session. Needs in-game load-order capture.
- **M10:** Unknown family silently inherits the 1000 bracket (`gearscore.lua:147-155`) — `IsUnknown` flagged in diag yet ignored in bracket selection. CONFIRMED minor.

## Justified exceptions J1–J9 (recorded, accepted)

`handlePipelineError` single-report + `safeCall` containment; `callLabeled` re-raise; `TacoTip_GSCallback` guard + routing; instant-fade guarded reads; Classic-Era suppressor window; `GetSpecialization` nil-guid→nil; removed `GetItemLinkByID` arm; retained-but-unreachable `UnitDistance`; M3 width-cap skip.

## Positive findings

`callLabeled`; `LOAD_STAGE` + `reportSilentFailures`; portrait teardown accounting relabel; probe-guard discipline with arity-sensitive tests; harness mock-honesty notes.

## Verdict: CRITICAL ISSUES

C1–C4 each independently cause silent wrong-or-absent behaviour with nominal diagnostics. Fix C1–C4 and adopt the cold-path counter pattern and the diag regains its 0.8.4 claim: every silent degradation the addon chooses is also one the operator can see.

**Limitations:** no harness run (no shell — 54/54 UNVERIFIED here); no in-game client (timing/ordering/`UnitClass`-at-load/`C_Timer` availability ASSUMED); file:line pins may shift after formatting. No source modified; no test executed.
