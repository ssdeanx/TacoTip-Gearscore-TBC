# Silent Failure Hunt: Publish-readiness (MAIN + Extras, Classic Era)

**Placement note:** reviewing session had file-write and shell tools unavailable; this report is filed verbatim from its inline handoff by the orchestrator. Harness totals quoted from batch journals + run_all.sh source-reads, not re-run.

**Reviewing:** working tree at `/home/sam/TacoTip-Gearscore-TBC` — MAIN (`main.lua`, `options.lua`, `gearscore.lua`, `pawn.lua`, `textures.lua`, `Libs/LibForeverInspector/LibForeverInspector.lua`, `Libs/LibDetours-1.0/LibDetours-1.0.lua`, `Libs/LibDBIcon-1.0/`, `TacoTip.toc` 0.8.4) AND Extras (`RankBrowser.lua`, `Frames.lua`, `Scoring.lua`, `Tooltips.lua`, `RankDB.lua`, `RankSync.lua`, `Scanner.lua`, `Core.lua`, `TacoTipAdapter.lua`, `Locale/enUS.lua` + 10 locales, `TacoTip_Extras.toc` 1.2.3), plus `CHANGELOG.md`, both `Tests/harness/run_all.sh`, `Tests/harness/taint_test.lua`.

Bench-read first (from source, trust nothing): `desks/fix-main-batch1` … `fix-main-batch5`, `desks/stage6-reaudit`, `bench/audits/2026-10-18-maintip-batch123-reaudit.md`, `2026-10-18-maintip-errorpaths/security/architecture/test-sufficiency` audits, `stage34/stage2+diet/stage1+tierA/stage5-oracle`, `five-client checklist`, `stage4-gear-on-demand brief`, `stage5-plus-widgets brief`, `extras-rank-system/storage-expansion/rankbrowser-ux` reviews, `desks/extras-publish`, `section5-widgets`, `stage6-*` journals.

**Files reviewed:** 28 source + 8 bench + 7 desks. **Error-handling/fallback locations reviewed:** ~115 (MAIN ~65, Extras ~50). **Suspicious patterns:** 18 (4 HIGH, 6 MEDIUM, 5 LOW, 3 smells). **Disposition:** 0 new CRITICAL, 4 HIGH (2 confirmed, 2 requires-justification), 6 MEDIUM, 5 LOW, 4 justified exceptions.

## Verdict: NEEDS FIXES

Not publish-blocking on the reported quit defect (verified fixed, no new CRITICAL), but do not call publish-ready: H-NEW1 re-opens the same taint class (mover-shown + menu-open mutation path with zero pins), H-NEW2 leaves the settings-load leg undiagnosed, H-NEW3 leaves public-API chat spam live, H-NEW4 leaves an unguarded raise inside the secure anchor hook.

## Critical — none confirmed

Quit-block root cause eliminated: zero `DetourHook` on `GameTooltip` in shipped Lua; `FadeOut` identity preserved via `SecureHook` with `Hide`-after-fade (`main.lua:3995-4003`, `options.lua:429-436`); toggle/default unchanged.

## HIGH

### H-NEW1 (CONFIRMED): mover ticker + OnShow/OnHide hooks call ShowExample with no GameMenu/StaticPopup guard
`main.lua:4202-4231` (tick + `onMoverGameTooltipShow/Hide` + `ScriptHook OnShow/OnHide`), `main.lua:4279-4301` (`ShowExample` body). `ShowExample` mutates shared `GameTooltip` (`SetOwner/ClearAllPoints/SetPoint/SetUnit/Show`) from a 1s ticker + `OnShow` + `OnHide` post-hooks whenever the mover is shown, regardless of `GameMenuFrame:IsShown()` or any `StaticPopupN:IsShown()`. Quit-fix guarded only the drag `OnUpdate` (`main.lua:4248-4254`) and the right-click confirm (`main.lua:4171-4184`). Reachability needs mover-shown + tooltip-show-while-menu-open (narrower than the old always-on detour), but same taint class; the 11 `taint_test` pins never drive ticker/Show/Hide-hooks with menu shown (diag lie); `CHANGELOG:66` claims a "mover tick guard" that does not exist.
**Fix:** one `isSecureMenuBusy()` helper (`GameMenuFrame.IsShown` OR any `StaticPopup1-4.IsShown`, `pcall`-guarded), early-return in `onMoverTick`, `onMoverGameTooltipShow/Hide`, and `ShowExample` itself. Pin: mover-shown + menu-shown + ticker-fire + `GameTooltip:Show()` → `SetOwner/SetPoint` count 0; revert-to-fail by removing the guard.

### H-NEW2 (CONFIRMED, carries H7-residual (a)): options LoadAddOn + registration pcall booleans unrecorded
`options.lua:668-677` (`pcall(LoadAddOn,"Blizzard_Settings*")` ×4), `:697` (`pcall(Settings.RegisterCanvasLayoutSubcategory)`), `:772-774` (`pcall(LoadAddOn,"Blizzard_OptionsUI/InterfaceOptions")`), `:533/555/568/599`-family booleans. Any failure leaves the options panel missing with zero diag.
**Fix:** count + last-error (`TT.ev.optionsLoadFailures`, `lastOptionsLoadError`), surface in `reportSilentFailures` problems[].

### H-NEW3 (REQUIRES JUSTIFICATION): public TT_PAWN:GetItemScore with nil scaleName guesses "MrRobot:"/"Classic:" — VgerCore.Fail chat-spam path
`pawn.lua:132-153` (esp. `:137-144`). `PawnGetSingleValueFromItem` on an unknown scale name routes through `VgerCore.Fail → DEFAULT_CHAT_FRAME` (documented `pawn.lua:72-78`); `pcall` cannot suppress it. Internal `GetScore` path is safe (proven `pawnLoadedScaleName`, `pawn.lua:218`); any external `TT_PAWN` consumer passing nil re-opens chat spam per tooltip render. Retail (no `Classic` lib) / Classic (no `MrRobot` lib) affected.
**Fix:** `if not scaleName then return 0 end` (resolve-then-call) + pin; or publish a contract statement that no caller passes nil.

### H-NEW4 (REQUIRES JUSTIFICATION, downgraded from CRITICAL): anchor-hook spell/action branch does unguarded parent:GetParent()
`main.lua:3088-3090` vs guarded unit probe `:3043-3076`. `local parentparent = parent and parent:GetParent()` is RAW; a parent without `GetParent` (or whose `GetParent` raises) raises inside a `hooksecurefunc` post-hook running for every tooltip, aborting the remainder — unit tooltips below fall through to default placement with no diag.
**Fix:** mirror the guarded idiom (`type(parent.GetParent)=="function"` + `pcall`), or hoist `isManagedAnchorTarget` first. Pin: parent without `GetParent`, `anchor_mouse_spells=true` → no raise, falls to unit gate.

## MEDIUM

- **M-NEW1:** `Adapter.GetEquipmentScoreColor` / `GetCurrentScoreColor` fail silent to grey/relative with no operator-visible signal (`TacoTipAdapter.lua:2081-2122`; consumers `RankBrowser.lua:389-409`, `Frames.lua:290-302`, `Tooltips.lua:794-802`). Fix: fallback counter + surface in Extras debug state, or log first fallback per session.
- **M-NEW2:** `isManagedAnchorTarget` silently treats battle-pet/mouseover-less/exotic owners as unmanaged (`main.lua:3033-3078`). Fix: split counter (`anchorSkippedMenu` vs `anchorSkippedUnresolved`) or debug-log first unresolved unit token per session.
- **M-NEW3:** `LibDBIcon` minimap tooltip untouched by quit-fix — separate `GameTooltip` identity, same mutation class (`Libs/LibDBIcon-1.0/LibDBIcon-1.0.lua:21,80,111`). Requires one-line pin or acceptance comment (own frame, `ANCHOR_NONE`, never touched by instant-fade hook targeting `GameTooltip` only).
- **M-NEW4:** `StaticPopup` pool enumerated as exactly 1–4 — correct today, brittle without comment/pin (`main.lua:4171-4184`). Fix: `local MAX_STATIC_POPUP_DIALOGS = 4` + FrameXML-citing comment + harness pin. Zero behavior change.
- **M-NEW5:** `Tooltips.GetRankExtraLines` swallows `RankDB.GetRecord` raises behind two `pcall`s with no diag (`TacoTip_Extras/Tooltips.lua:746-772`). Fix: count `rankRecordErrors` in `GetDebugState`, or document intentional display-only suppression.
- **M-NEW6:** `RankBrowser` row-tooltip `pcall`s silently truncate the hover card (`RankBrowser.lua:583-649`). Fix: validate `entry` numerics once before `ClearLines`, or count `rowTooltipErrors` in debug state.

## LOW

- **L-NEW1:** ruRU MONK/DEMONHUNTER/EVOKER spec names remain German/English placeholders (carries M7, VERIFIED untouched; `LibForeverInspector.lua:345-347`). Fix needs a translator — do NOT invent Russian; fall back to English with a comment if operator approves.
- **L-NEW2:** gear-panel `cached ~= nil` vs `GEAR_NOT_SCANNED` hinges on in-memory `Scanner.GetRemote` — relog flips the message with no data change (`RankBrowser.lua:1287-1408`). Accepted UX candidate, needs explicit sign-off.
- **L-NEW3:** magic numbers without names (strata pair, 100/200 levels, 0.9 alpha, 0.2s debounce, 26/32 geometry). Traceability only; behavior verified correct.
- **L-NEW4:** `pawn.lua` `2.0538/2.0` literals lack provenance comment (Batch-5 N3 homing verified). Comment-only.
- **L-NEW5:** tooltip freshness (`tooltipSessionStart`) vs browser session clock are independent module locals, both `GetServerTime`-derived. Document the two-session definition or unify.

## Smells (non-blocking)

1. Dead-removal residue — CLEAN (zero `gearDenominator`/`countRevisionItems`/`N/17`/`LB_TIP_GEAR_DEPTH`/`DetourHook`-on-GameTooltip in shipped Lua; orphan-locale invariant holds).
2. Comment/behavior drift — `CHANGELOG:66` claims "mover tick guards"; the tick has no guard. Fix code or correct changelog.
3. Overly broad `pcall`s catalogued (M-NEW5, M-NEW6, H-NEW4-spell-branch, `showRowTooltip`, adapter probes) — each needs a counter or acceptance note.
4. Inverted/dual clock conditions (`main.lua:179-180`, `lib:70-80`, `gearscore.lua:106` disagree on whether `C_Timer.After` is required; all fail-open). Unify or document.

## Full trace: four live-reported paths on Classic Era

- **(i) GameMenu→quit, instant_fade ON/OFF × mover shown/hidden:** ON + mover hidden HOLDS (genuine FadeOut + post-hook Hide, menu owners passthrough). ON + mover shown: FadeOut leg holds but ticker/OnShow/OnHide → ShowExample mutates GameTooltip behind menu (H-NEW1). OFF HOLDS (SecureUnhook → nop). LibDBIcon HOLDS (own frame).
- **(ii) Browser over Settings → gear click → scan-missing:** layering HOLDS (`applyTopmost` FULLSCREEN_DIALOG/100; gear child 200, backdrop 0.9); empty-state HOLDS (`GEAR_DATA_UNAVAILABLE` vs `GEAR_NOT_SCANNED`, no `item:0`); scan-in-flight renders literal, documented.
- **(iii) Era 1400 grading:** tooltip `TT_GS:GetQuality` Era-200 → 1400 ∈ (1200,1400] = 7th band Artifact (0.92,0.10,0.10); browser adapter-first → same; no-adapter relative fallback preserved. HOLDS (visibility gap = M-NEW1).
- **(iv) Freshness line old/fresh/no-record:** `GetRankExtraLines` gates hold in all three modes; gear line absent. HOLDS (observability caveat M-NEW5).

## Frozen invariants: all HOLD

Era range gate (20/40, index 1, ordering, probe guard, ceiling, timings); raw formula literals byte-stable; TOCs 0.8.4/1.2.3; interfaces 11509/20506/38002/16001/120105 both TOCs; wire R;2 13-field + G/D grammar, no new SV shape; enUS-only keys all fallback-commented; Retail hold@1000 as decided.

## Disposition deltas

C1–C4 FIXED-hold; N1 hold-as-decided; N2/N3 FIXED-hold; H1 FIXED-hold; H2 STILL OPEN (tri-state undecided, operator decision owed); H3–H6 FIXED-hold; H7 PARTIAL → residual now H-NEW2; H8–H11 FIXED-hold; M1/M2/M4/M5/M6/M9/M10 FIXED-hold (spot-verified); M3 justified-hold; M7 STILL OPEN → now L-NEW1; M8 deferred-carried. Batch123 observations (b)(c)(e)(f) carried, benign.

## Audited justified exceptions (4)

M3 width-cap skip; `GetActiveTalentGroup or 1` highlight default; C4 loud-assert boundary; L-NEW2 session-vs-persisted wording (flagged for sign-off).

## Positive findings

DetourHook-on-GameTooltip gone; FadeOut identity via SecureHook; anchor menu passthrough with pcall-guarded probing; clock fail-open consistent; spec-nil on both consumers; Extras removal hygiene exemplary; SV/wire/TOC/frozen-gate invariants hold.

## Summary

CRITICAL 0; HIGH 4 (fix or formally accept); MEDIUM 6 (M-NEW1 visibility first); LOW 5 (opportunistic). Unresolved justification cases: 2 (H-NEW3 external-caller contract, M-NEW3 LibDBIcon note). Carry-overs: H2 tri-state, M7/L-NEW1 ruRU, M8 harness, in-game Retail-spread screenshot + five-client confirmations.
