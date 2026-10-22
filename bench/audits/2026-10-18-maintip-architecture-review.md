# Architecture / Correctness Review — TacoTip main addon (v0.8.4)

**Placement note:** the reviewing session had no file-write and no command-execution tools, so this report is filed verbatim from its inline handoff by the orchestrator. `Tests/harness/run_all.sh` was not re-run by the reviewer (no shell); 54-invocation green is cited from `Tests/harness/README.md` (2026-10-11), not re-verified.

**Scope:** `main.lua` (~3900 lines), `gearscore.lua` (575), `pawn.lua`, `textures.lua`, `options.lua`, `Libs/LibForeverInspector/` (~5400 lines), `Tests/harness/` docs — five-client delivery, data-flow integrity, client detection, formula fidelity, options cascade, dead code, patch hazards. ~2500 lines inspected directly, remainder via structural grep.

**Findings:** 0 critical/blocker, 2 important/major, 5 minor, 4 info. The tree is in unusually good shape for a five-client addon. No merge-blocking defect found.

## Strengths

1. **Delivery-path discrimination is sound. [VERIFIED]** `dataPipelineActive` (`main.lua:2408-2414`) probes for the mixin's *own* methods (`IsTooltipType`/`GetPrimaryTooltipData`), not merely `TooltipDataProcessor` — which correctly excludes TBC Anniversary and Titanforge, where `AddTooltipPostCall` exists but never fires. Dual registration with `HasScript` guards (`main.lua:2434-2487`, `2664-2676`) means a mis-probed client degrades to at most a duplicate no-op, never to silence.
2. **Producer/consumer arities match on the inspect callback contract. [VERIFIED]** `LibForeverInspector.lua:3703` fires `Fire("INVENTORY_READY", guid, true, unit)`; `CallbackHandler-1.0.lua:27-34,69` dispatches as `method(eventname, ...)`; the function-ref registration (`:126-137`) passes through unwrapped, so `onEvent(f, "INVENTORY_READY", guid, true, unit)` binds correctly (`main.lua:3730`). An earlier suspicion of a `guid=true` mixup was traced into the dispatcher source and withdrawn.
3. **Async-load lifecycle converges and is re-entrancy guarded. [VERIFIED]** `itemcacheCB` drains backward, dedupes identical item IDs across slots, latches `completed`. `TacoTip_GSCallback` (`main.lua:1287-1319`) drops same-guid nesting and defers cross-guid nesting. Stale cache is served by design while `UNIT_INVENTORY_CHANGED` marks `.stale` and re-inspects — `GetScore` never blanks the tooltip to zero during refresh.
4. **GearScore formula matches upstream 3.1.x faithfully. [VERIFIED]** `SlotMOD` table, `Scale 1.8618`, A/B/C tables, `QualityScale` rarity remaps, TitanGrip 0.5 dual-2H handling (`gearscore.lua:496-518`, loop skips slot 4 once) reproduce the reference formula.
5. **Config hardening is real, not decorative. [VERIFIED]** `SafeSanitizeConfig` covers every boolean, numeric slider, color channel (`options.lua:185-269`), plus the `custom_pos` nil-entry crash and mover-position migration.
6. **Next-patch tripwires exist where they should. [VERIFIED]** The `GameTooltip.SetBackdrop` diagnostic (`main.lua:3550-3558`), no-path-hooked check, `IsUnknown` flagging, `C_Timer`/namespace nil-guards, both-slots `GetBuildInfo` reads.

## Findings

### 1. [Major] Retail scores saturate the shared 1000-bracket — every endgame character renders Artifact-red

`gearscore.lua:147-160, 206-214, 227-241`. `BRACKET_SIZE` falls through to 1000 for Titanforge *and* Retail. The formula is iLvl-linear, so a Retail character at iLvl ~650 scores ~17k+ against `MAX_SCORE = 7000`. `GetQuality` clamps everything above max to Artifact — color loses all discrimination on the two newest clients. Upstream fidelity is the reason (upstream never modeled Retail iLvl): design debt, not a typo. **Recommendation:** per-family bracket or normalize the displayed total into the band domain before `GetQuality`, raw formula untouched; pin in `detect_test`/`tooltip_test` like the Era/Forever 200 split. That live Retail totals exceed 7000 is ASSUMED from the formula — verify with one in-game character-frame screenshot per client.

### 2. [Major] Inspected-unit spec falls back to `1` ("confidently wrong") on exactly the path built to return nil

`Libs/LibForeverInspector/LibForeverInspector.lua:5268-5272`. `GetSpecialization` implements the nil-instead-of-1 contract for units with no data (`:5251-5266`), but the tail fallback `return cached.specIndex or 1` violates it: a cache record that *exists* yet carries no `specIndex` (modern client where `GetInspectSpecialization` was restricted/absent) renders spec index 1 with 0/0/0 instead of no spec line. `GetActiveTalentGroup`'s unconditional `return 1` (`:5430`) compounds it. **Recommendation:** return `cached.specIndex` (nil when absent); `main.lua`'s existing `if (spec1)` gate hides the line. That `getModernSpecData` returns nil for restricted units is ASSUMED from the file's own comments — needs live-client eyes on a restricted unit.

### 3. [Minor] Single-slot `gsCallbackPending` silently drops one unit's repaint under triple-guid pileup

`main.lua:1284-1318`. Three interleaved GUID callbacks while one body runs: the middle GUID is overwritten and never re-driven. Negligible in practice (async completions vs synchronous render). **Recommendation:** small deduped queue, or annotate as intentionally lossy with the reachability reasoning.

### 4. [Minor] Pawn item-load requests bypass the 2-second per-item throttle gearscore uses

`pawn.lua:29, 199-201` vs `gearscore.lua:101-118`. Same trust boundary, two disciplines. **Recommendation:** route Pawn's request through the same throttled helper.

### 5. [Minor] Unreachable defensive branches accumulate

`pawn.lua:91-112` (MrRobot-first guess — sole caller always passes a proven name), `LibForeverInspector.lua:4060-4067` (`UnitDistance` — keep, well-labeled), duplicated `itemcacheCB`/GUID/throttle helpers across `gearscore.lua`/`pawn.lua`. **Recommendation:** share one helper; consider deleting the Pawn guess branch since its only effect if reached is the chat-spam bug.

### 6. [Minor] Sanitizer allowlist gaps: `custom_anchor` and media-path strings unvalidated

`options.lua:72-146, 175-269`. Every boolean/numeric/color key clamped — VERIFIED. But `custom_anchor`, `tooltip_font`, bar/background/border textures accept any string. **Recommendation:** whitelist `custom_anchor` against the five cycled values; reset unknown media strings to defaults (match the `"Tooltip enlarged"` precedent at `options.lua:240`).

### 7. [Minor] `GetScore` re-resolves `GetItemInfo` per slot instead of reusing one fetch

`gearscore.lua:352-357, 514-528` vs the file's own one-call contract (`:262-265`). ~19 redundant cached lookups per unit render. **Recommendation:** hoist one `GetItemInfo` table per link per render and thread it through `GetItemScoreFromInfo`.

### 8. [Info] Unknown-family clients silently inherit the WotLK bracket

`gearscore.lua:147-157`. The inspector reports `unknown` and diag flags it, but bracket selection defaults unknown to 1000 with no remark. **Recommendation:** when the next family is announced, add project constant + bracket + dual-spec flag together; optionally assert `not IsUnknown` in the bracket block so a future unknown fails loudly in-harness.

### 9. [Info] Dual registration is fail-safe in both directions — no dead-or-dangling path found

`main.lua:2478-2487, 2666-2676, 2855-2858`. Every registered path can fire on at least one client; every in-game delivery mechanism has a registered consumer. VERIFIED.

### 10. [Info] Modern talent readout depends on the harness modeling two talent surfaces separately

`main.lua:2031-2060`, `LibForeverInspector.lua:3580-3615`, `Tests/harness/README.md:122-140`. The harness README records this as a must-keep mock property — flagged because any future mock edit unifying the surfaces silently un-tests Retail talents.

### 11. [Info] `INSPECT_RENDER_COALESCE` (0.1s) trades one dropped genuine update for suppressing every double-render

`main.lua:138-145, 3741-3750`. The inspect pipeline's own throttle (0.4–1.0s delay, 0.5s tick) makes the dropping window unreachable in practice. VERIFIED by reading both throttle sites.

## Recommendations

1. **Retail bracket decision** (Finding 1) is the one design conversation worth having before any "Retail polish" milestone.
2. **Unify the small duplicated helpers** (`itemcacheCB`, GUID resolution, throttle) into one home.
3. **Extend `SafeSanitizeConfig`** to the three unvalidated string classes — five lines, zero behavior change for valid configs.
4. **Do not "fix" the re-entrancy guards** without a reproduction — needs a harness timing test first.

## What needs live-client eyes (ranked)

1. **Retail + Forever:** character-frame GS color on a high-iLvl character (Finding 1); spec line on a restricted/never-inspected unit (Finding 2).
2. **Classic Era:** hover a player walking out of range (inspect-error suppression path).
3. **TBC/Titanforge:** no post-call double-render; dual-spec group-2 readout on an inspected dual-spec player.
4. **Any one client:** mover drag → `/reload` → persistence; `/tacotip reset`; shift-toggle `tip_style`; `loadDeprecationFallbacks=0` item hover.
