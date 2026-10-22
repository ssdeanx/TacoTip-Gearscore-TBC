# Silent Failure Hunt: FINAL pre-publish — TacoTip v0.8.4 + TacoTip Extras v1.2.3

**Placement note:** the reviewing session had no file-write and no shell tool; filed by the orchestrator from its inline handoff (desk `final-hunter`, agent `final-hunter`, run_id `finalhunter`). Harness totals (70/70 main, 42/42 Extras, luacheck 0/0 across 87 + 26 files) are the orchestrator's verified state, not re-run by the reviewer. The FrameXML mirror was permission-denied to that session, so mirror-cited client claims are marked unverified-in-session.

**Scope:** whole shipped tree, both addons. 43 shipped files read in full + 11 locale files. **210** error-handling/fallback locations enumerated by sweep; **118 individually traced**. **20 suspicious patterns.** Disposition: **17 confirmed defects** (4 HIGH, 7 MEDIUM, 6 LOW), 0 requires-justification, 9 audited justified exceptions.

## HIGH

**H-1 — Extras non-English locales have their format specifiers stripped → the leaderboard footer renders the player's standing as a literal `#d`.** `TacoTip_Extras/Locale/{deDE,esES,esMX,frFR,itIT,koKR,ptBR,ruRU,zhCN,zhTW}.lua:14,15,20`; rendered at `RankBrowser.lua:1714-1731` and `:1860-1880`.
- ruRU as shipped: `["LB_FOOTER_STANDING"] = "Ваше место: #d общий | #d фракция | #d класс  -  d игроков"`, `["LB_FOOTER_NO_RANK"] = "d игроков - рейтинга пока нет"`, `["LB_SORTED_BY"] = "Сортировка: s s"`. enUS has `#%d … #%d … #%d … %d …`, `%d players tracked…`, `Sorted by %s %s`.
- The `%` byte is missing from every conversion specifier in these **three keys in all ten** non-English Extras locales (identical line numbers 14/15/20). `string.format` with a specifier-less format string ignores its arguments and returns the literal — no error, no warning. The per-key English fallback fills only **absent** keys, so a present-but-corrupted entry defeats the fallback.
- Impact: the player's own overall / faction / class ranks and the pool size render as a literal `d`; the sort readout renders `s s`. Every other format-bearing key in the same files is intact (`LB_TIP_GS`, `LB_TIP_ILVL`, `LB_TIP_RANK`, `LB_TIP_LASTSEEN`, `LB_SCAN_COMPLETE`, `TIME_MIN_AGO`, `SCAN_PROGRESS`), and the **main** addon's locales are intact — the corruption is confined to the Extras locale set.
- Why the suite is green: `Tests/harness/locale_test.lua` pins key counts and the 11-locale registry only, never format-specifier shape.
- Fix: restore the specifiers in all ten files, and add a harness pin asserting every locale's specifier **sequence** equals enUS's.

**H-2 — the Extras tooltip driver's `rendering` latch has no error boundary → one raise wedges the surface permanently.** `TacoTip_Extras/Tooltips.lua:1244-1306` (latch set `:1248`, cleared only on four normal returns `:1253/:1268/:1287/:1304`), called unwrapped at `:1404`, `:1460`, `:1618`.
- Any raise between set and clear leaves `rendering = true` forever; `:1245` then refuses every later render for the session. No `finally`, no `xpcall`, no reset path.
- Real trigger paths: `makeRows` → `getRankRow` → `RankDB.GetPlayerRank` → `table.sort` comparing `a.timestamp > b.timestamp` (raises on a non-numeric timestamp — the index filters `gs` by type but **not** `timestamp`); `string.format` paths; `target:AddLine` (raw engine call); `Cache.Get` → `clone` recursion.
- Impact: the Extras tooltip rows stop appearing for the whole session — no error, no counter, no recovery short of `/reload`. The main addon has exactly this boundary (`main.lua:400-402` `safeCall` + `handlePipelineError` at `:365-398`); the Extras has none.
- Fix: `xpcall` the body with a handler that always clears the latch, counts the failure and records the message.

**H-3 — every Extras diagnostic counter is reachable only from the test harness.** Counters at `Tooltips.lua:778-792` (`GetDebugState`), `:1450-1461` (`GetDriverState`), `RankBrowser.lua:616-622`, `TacoTipAdapter.lua:2142-2147` / `:2170-2203`, `Core.lua:777-779` (`GetInitializeFailures`). The only user-facing diagnostic, `/ttgsdebug` (`Core.lua:621-689`), prints the scanner snapshot and `RankSync.GetDebugState()` — nothing else; a tree-wide grep finds those accessors **only inside the test harness**.
- Impact: the counters added for M-NEW1 (score-colour fallback), M-NEW5 (rank-record error) and M-NEW6 (row-tooltip truncation) are undeliverable; the H-2 wedge is undetectable; a module that failed to start is invisible. The code comments assert the opposite ("surfaced in GetDebugState below") — a diag lie.
- Fix: print a surfaces block in `/ttgsdebug` (driver mode, renders/rows, poll ticks, rank-record errors, row-tooltip errors, score-colour fallbacks + last reason, initialize failures) and/or surface it in the Extras Options panel; pin the printed output.

**H-4 — recovery-journal mismatch permanently locks the Extras surface and leaves TacoTip's `show_gs_player` forced off.** `TacoTip_Extras/TacoTipAdapter.lua:1613-1657` (mismatch branch `:1628-1638`), `:1659-1664` (`conflictLocked` never cleared), `:1729-1774` (lease + journal write `:1758-1762`).
- The fingerprint embeds the TacoTip version, the gate verdict and the Pawn flags (`:573-593`); the journal is cleared only on a clean release, so a crash or force-quit leaves it; any of those inputs changing between sessions makes the fingerprints differ → `conflictLocked = true` → `acquireLease` false forever, and `config[MANAGED_KEY]` (`show_gs_player`) is never restored even though `record.originalValue` is right there.
- Recovery requires deleting `TacoTipExtrasDB`; the only trace is an Options-page reason string. **Fixed in the `fix-extras-publish` lane** (stable journal identity, restorative mismatch path, `conflictLocked` reset, one-shot chat notice).

## MEDIUM

- **M-1** `main.lua:1117-1123` — `tooltip:IsUnit(unit)` is called **unguarded** and its result **discarded** (both branches return `unit`), violating the file's own invariant at `:1209-1213`. Two-line fix.
- **M-2** `main.lua:3664-3679` — the guild-guard pcall wraps the **whole** `InspectGuildFrame_Update` while the comment claims it is "deliberately narrow"; unrelated errors are swallowed and mis-counted as a guild-guard catch.
- **M-3** `TacoTip_Extras/Cache.lua:103-107`, `Scanner.lua:70-80` — `pcall(listener, …)` with **no counter**; the cache entry was already mutated, so a raising listener loses the update permanently and silently.
- **M-4** `TacoTip_Extras/Frames.lua:1411-1447`, `Core.lua:847-904` — neither event handler is wrapped, contradicting the addon's own doctrine at `Core.lua:742-754`.
- **M-5** `TacoTip_Extras/RankSync.lua:1225-1232` — a record failing `RankDB.ValidateRecord` is dropped with **no counter** (the version mismatch on the same path is counted), so a peer that never appears is undiagnosable.
- **M-6** `TacoTip_Extras/RankSync.lua:484-486` — the 50-message send cap silently evicts the oldest queued message with no counter (the library's analogous queue counts its drops).
- **M-7** `TacoTip_Extras/Core.lua:757-775, 790-792, 840-844` — an incompatible TacoTip produces **zero output**: `Adapter.Initialize` returns `false` (a return value, not a raise), which `guarded()` does not record, and the welcome line is skipped.

## LOW

L-1 `main.lua:120,127` — `pcall(SetWidth)` result discarded (the same file has `callLabeled` for this). · L-2 `main.lua:1540-1544, 1565-1569` — `gsCallbackPending` is one slot; a second nested guid overwrites the first ("no work is lost" is false). · L-3 `main.lua:1966-1970` — `pcall(CI.DoInspect, …)` result discarded, no counter. · L-4 `main.lua:1512` — `TT:RefreshCharacterFrame()` called unguarded from the global GS-callback path. · L-5 `RankBrowser.lua:1875-1878` + `Locale/enUS.lua:229` — `SORT_LEVEL_DESC` exists only in enUS, so the non-English sort readout names no column; `LB_SORTED_BY` has no English fallback. · L-6 `Core.lua:757-760` — a missing module is not recorded as an initialization failure.

## Audited justified exceptions (9)

`handlePipelineError` once-per-message dedup with a bounded ring; the `safeCall` boundary + `safeCall(onEvent)`; the Era-only probe guard (an engine UI error on a different frame cannot be suppressed by pcall — counted and used to learn the range); clock fail-open (never memoises 0; `problems[]` entry); not-ready score → the line is omitted, not shown as 0 (counted); LibDetours loud asserts; LibDBIcon registration asserts (its own tooltip frame, outside both quit-fix hooks); the guild-guard's intent (Blizzard's defect) — **scope** recorded as M-2; the level-70 metric suppression as explicit user-visible policy.

## Positive findings

Era inspect range gate complete and self-consistent (distance-first in **both** `lib:CanInspect` and `requestInspectImpl`; probe guard as the single choke point; squared-distance ceiling; state-based out-of-range mark; all timings fail-open). The main addon's load failure is a fact, not a silence (`TT.LOAD_STAGE`/`LOAD_OK` reported by diag). The error pipeline is exemplary (`callLabeled` re-raises with the call site named; the GS-callback guard is provably always unlatched; every cold-path failure has its own counter). The instant-fade path is clean (no `DetourHook` on `GameTooltip`; capability probe records "unsupported"; one `isSecureMenuBusy()` helper guards every mover path). The Extras wire is defensible (position-based splitting preserving empty fields; 240-byte door enforced at enqueue; a version token in every message type; every refusal bucketed). The whisper path is genuinely deleted (zero `SendChatMessage` in the shipped tree). The Extras adapter fails **closed**: an incompatible TacoTip has the surface refused and TacoTip's own GearScore restored.

## Frozen invariants — all INTACT (source-read)

Era range gate (20/40, index 1, distance-first ordering, probe guard, squared ceiling, learned range, all timings) · raw GearScore formula literals · Retail bracket held at the shared 1000 · TOC versions 0.8.4 / 1.2.3 · interface list in both TOCs · wire format R;2 + G/D · SavedVariables shapes (note: the Extras root carries two extra runtime keys, `gear` and `tacoTipRecovery`) · no two-argument `CanInspect` (the only two-arg use in the tree is a harness pin) · no invented Russian strings (the RU strings are real translations — but the Extras file's specifiers are corrupted, H-1) · the whisper path stays deleted.

## Verdict

**PUBLISH VERDICT: DO NOT SHIP** at the time of this audit — H-1 (locale format corruption, 10 locales), H-2 (render latch), H-3 (unreachable diagnostics) and H-4 (recovery-journal lock) were open. H-4 was closed by the `fix-extras-publish` lane; H-1, H-2 and H-3 are the remaining HIGHs, each with a fix sketch above.
