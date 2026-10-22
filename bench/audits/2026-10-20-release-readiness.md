# Release readiness — TacoTip 0.8.4 + TacoTip Extras 1.2.3 (2026-10-20)

Publish-bound. 112k CurseForge downloads, ~10k active users per upload, five clients (11509 Era, 20506 TBC, 38002 Titanforge, 16001 Forever, 120105 Retail).

**Operator rule that governs this release:** publishing is a one-shot ~100 GB download. There is **no in-game test before publish** — Classic Era is the only pre-upload test client, and Retail/Forever/TBC/Titanforge ship on **offline proof** (harness pins + branch-qualified FrameXML citations). If Era is clean, upload.

---

## 1. What this release contains

**TacoTip 0.8.4** — the Era "Not in Range" popup fix and the 0.7.9 inspect work, plus a Stage-6 hardening wave: config sanitizer allowlists; uninspected units show no spec line instead of a wrong one; queue-overflow and cold-path failure telemetry in `/tacotip diag`; file-scope soft aborts that name their stage; Pawn late-load detection; options-load ledger; the Game Menu quit-block taint fix; character/inspect pane refresh; the clock-missing fail-open; the `/tt lb` forwarding; the tri-state inspect contract; the Russian specialization names.

**TacoTip Extras 1.2.3** — Stages 1–5 plus the publish wave: the rank-sync wire rebuilt (same-transport answers, versioned stride, G/D gear on demand, counted outcomes, no whisper path); the browser rebuilt as a 900 px band-stack with an opaque gear panel; per-client grading; Detailed by default; Shaman Blue; the socket capacity read from the documented `C_Item.GetItemNumSockets` with a bidirectional cross-check; the Extras' diagnostics now reachable from `/ttgsdebug`.

## 2. Final review verdicts

| Reviewer | Verdict | Notes |
| :--- | :--- | :--- |
| paladin (security) | **SHIP** | 0 CRITICAL, 0 HIGH. Main transmits nothing; the Extras wire is exactly 13 documented fields; no code-execution or injection surface; no taint on a secure path. |
| arbiter (publish readiness) | **DO NOT SHIP → 1 blocking fix applied** | The one blocker: `/tt lb` never reached the Extras in the real client (`rawget` on a proxy table the client empties before dispatch). Fixed by the final main lane. |
| hunter (silent failures) | **DO NOT SHIP → 3 blocking fixes applied** | Discarded pcall result in the forwarder; `/ttgs`/`/ttgsdebug` shadowed by the main `/tt`; the gear panel never explicitly closed with the browser. All three fixed. |
| janitor (smells) | **SHIP with 5 HIGH first** | All five landed: the "Default is 16px" lie (real default 20), the ☐ glyph shipped as ▲ in ten locales, 38 dead locale keys + an honest localization claim, the escape-registration comment that wasn't true, and the main harness granting every widget method. |

## 3. The three lessons that actually cost users time — now permanently prevented

1. **A mock must reproduce what the real API LACKS.** Three user-visible defects were invisible because the harness disagreed with the client: the transparent gear panel (a plain frame has no `SetBackdrop`), the browser that closed on first click (created frames are visible by default), and the `/tt lb` forwarder (the client wipes `SlashCmdList` before dispatch). Each is now modelled faithfully, and each pin goes RED on the old code.
2. **The client's slash dispatch is deterministic, not a race.** It splits at the first whitespace and looks up only that token, so `/tt lb` is dispatched as `/TT` with the argument `lb`. The owner of `/TT` must forward the argument itself.
3. **A dead hook is worse than none.** `PaperDollFrame`/`InspectPaperDollFrame` carry no `hidden` attribute, so an `OnShow` hook on them never fires — the character/inspect panes were refreshing on login and on gear changes only.

## 4. Accepted risks (deliberate, documented)

| Risk | Why accepted |
| :--- | :--- |
| Retail colour band held at the shared `1000` | Operator decision; live totals unmeasured; the score itself is unchanged. One screenshot decides it later. |
| Extras Options status lines stay English | 47 reason sentences × 11 locales is a release's worth of translation. The dead keys were deleted and the README claim narrowed instead. |
| The three Classic clients have no socket metrics | They have no `GetItemStats`; the metrics are omitted, never guessed. |
| The Extras' `/tt lb` multi-word aliases are unreachable | The client dispatches one token; the real entry points are the single-token aliases and the main add-on's forwarding. |
| `H2` tri-state shipped with the operator-approved contract | `DoInspect` now returns `false` / `"queued"` / `true` and the caller keys off all three; the player's visible output is unchanged. |

## 5. Frozen invariants (verified at every gate)

Era range gate (20 yd pre-filter, `CheckInteractDistance` index 1, distance-first ordering, probe guard, squared-distance ceiling, all timings fail-open) · the raw GearScore formula literals · Retail bracket at the shared 1000 · TOC versions 0.8.4 / 1.2.3 · interface list in both TOCs · wire `R;2` + `G`/`D` · SavedVariables shapes · no two-argument `CanInspect` · no invented Russian strings · the Extras whisper path deleted.

## 6. Packaging

Both packages are verified by scripts that can check either the last commit or the working tree: `Tools/verify_release.sh` and `Tools/verify_release_extras.sh`, each with a `--worktree` mode. The main archive is 27 files, the Extras archive 29; no workshop document, test file, lint config or PNG can reach either.

## 7. The pre-upload test

`bench/audits/2026-10-20-pre-publish-test-window.md` — four time-boxed blocks (Extras → main → diagnostics → sweep), each step written as "do X → expect Y", with a table of exactly what to send back per symptom. Capture diagnostics **before** any `/reload`: a reload clears the counters that prove what happened.

## 8. After the upload (watch list, not blockers)

Retail right-click Inspect on a guildless player · Retail uncached-item data arriving within ~1 s · the Retail colour band · `/tt lb` in a non-English client · the footer's "▲ Top" glyph in a non-English client · Escape with the gear panel open · the mode dropdown in a non-English client.

**Forward-looking (not a defect today):** the client's `ChrSpecialization` table (wago.tools, build 12.1.7) already carries a **third Demon Hunter spec** — `0 Истребление, 1 Месть, 2 Пожиратель` ("Devourer") — while the add-on knows two (`Havoc`, `Vengeance`). If that spec becomes obtainable in a future build, a player on it would show an unknown spec line until the spec tables gain the third entry (all 12 locale tables, index-aligned). The Russian tables deliberately keep the same shape as the English one, so this is a single coordinated change when the spec ships.
