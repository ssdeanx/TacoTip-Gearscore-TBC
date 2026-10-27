# v0.8.8 readiness audit — cache, portrait, and /tt diag (2026-10-26)

**Desk:** `audit-v088-readiness`. **Scope:** TacoTip core only — `main.lua`, `options.lua`, `gearscore.lua`, `Libs/LibForeverInspector/LibForeverInspector.lua`, `Tests/`, packaging. `TacoTip_Extras/**` is out of scope except where its harness reports a core defect.
**Method:** read-only. No production file edited, nothing staged or committed. Evidence labels follow `CAIRN.md`: **VERIFIED** = traced in this tree / reproduced by a command; **ASSUMED** = stated with the verifier; **UNKNOWN** = not established. The operator's in-game observation outranks all of this.

---

## 1. Current gate state (all VERIFIED by running the command today)

| gate | result | detail |
| :--- | :--- | :--- |
| `bash Tests/harness/run_all.sh` | **PASS 71/71** | also PASS 71/71 under `LUA=lua5.4` and `LUA=luajit` |
| `bash TacoTip_Extras/Tests/harness/run_all.sh` | **FAIL 6/42** | 36 failed invocations, 6 distinct failed checks (§6) |
| `luacheck .` | **FAIL 85 warnings / 0 errors in 102 files** | every warning is in newly vendored `Libs/`; authored files are **0/0 in 42 files** |
| `bash Tools/verify_release.sh --worktree` | **FAIL 1 check** | "expected exactly one .toc"; 7 found (49-file archive) |
| `bash Tools/verify_release_extras.sh --worktree` | **PASS** | — |

This matches the workspace's existing "open red-state" document (2026-10-25); the red state is unchanged, and the documented "0 warnings / 88 files" gate is no longer literally true (the 14 new vendored files account for the delta: 88 + 14 = 102).

The production code itself is healthy against the offline matrix: 0.8.7 loads, renders, scores, and passes taint/quit-block pins on all five client profiles, under all three interpreters. The failures are packaging, lint scope, and test drift — plus the runtime defects below, which the suites do not pin.

---

## 2. GearScore / average-iLvl cache — data model and lifecycle

**One store:** `lib.cache[guid]` (`LibForeverInspector.lua:52`), written only at `:3758`, in memory only, never evicted, never persisted. There is **no cached `gearScore` / `avgItemLevel`** — those are recomputed from item links on every tooltip call.

| field | written | read by |
| :--- | :--- | :--- |
| `items[1..18]` (links) | `:3681` | `GetInventoryItemMixin:5229-5231` → `gearscore.lua:523-569` |
| `time` (GetTime uptime) | `:3693` | `isCacheFresh:3913`, `GetLastCacheTime:5207`, dead diag `:3484` |
| `stale` | `:3880` only | `isCacheFresh:3913`, `GetInspectStats:437` |
| `incomplete` | `:3697` | **only** `GetInspectStats:438` |
| `retryCount` | `:3698` | `:3692/3698` only |
| `specName/specIcon/specIndex/talentPoints/specIndexByGroup/activeGroup/achievements` | `:3734-3754` | spec/talent/achievement getters `:5243-5453` |
| `specID` | `:3734` | **nothing** |

**Lifecycle:** render → `CI:DoInspect(unit)` (`main.lua:1725-1732`) → freshness early-return (`:4907-4910`) or queue/request (`:4929-4930`, `requestInspect:4341-4433`, one-arg `CanInspect` preserved) → `INSPECT_READY` resolves the unit from pending/InspectFrame/target/mouseover (`:3798-3815`) → `cacheUnitData` (`:3664-3762`) → `INVENTORY_READY` + `TALENTS_READY` (`:3760-3761`) → `main.lua:3885-3917` re-renders via `GameTooltip:SetUnit` (one rebuild per GUID per 100 ms) → `GearScore:GetScore(guid, true)` (`main.lua:2141`, `gearscore.lua:405-574`) scores the links. Item data itself is the client's `GetItemInfo` cache; TacoTip caches no item stats, only the slot→link map, and registers `ContinueOnItemLoad` when a link's item data is not cached (`gearscore.lua:443-561`).

The prior lane's cache plan (`docs/superpowers/plans/2026-10-24-v087-cache-and-hover-improvements.md`, Task 2) is **entirely unchecked**; these defects are its subject matter and remain unlanded.

### Cache findings

**C1 — HIGH — a partial re-inspect is served as FRESH.** `cacheUnitData` clears `.stale` at `:3668` and, on the incomplete path (`:3692-3698`), never clears the previous `.time`. A gear-change refresh whose links have not arrived therefore keeps the old timestamp; `isCacheFresh:3912-3915` says fresh, `DoInspect` early-returns at `:4907-4910`, `GetLastCacheTime` returns the old stamp, and `gearscore.lua:409-412` only treats `0` as "no data" — the mixed old/new table is scored and printed. First-ever inspect is safe (`time` nil → GS 0); the re-inspect path is the vulnerable one. Contradicts `CHANGELOG.md` 0.8.4 and `workshop.md` "do not cache incomplete inspect gear". **VERIFIED (code).**

**C2 — HIGH — emptied slots are never cleared.** `:3676-3690` writes a link only when the client returns one; the `elseif (not data.items[slot])` arm only records the missing-equipment signal. When a slot becomes empty, the old link survives; `gearscore.lua:523-569` keeps scoring it and `:570-571` counts its iLvl. Unequip a ring and its score remains until /reload (or until C1/C3 re-stamps a "fresh" partial). **VERIFIED (code).**

**C3 — HIGH — the 4-retry cutoff finalizes partial data as complete.** `:3692-3695`: once `retryCount >= 4` (~1 s at 250 ms) it stamps `time = now` and clears `incomplete` even while `anyMissingEquipped` is true, caching a 13-of-16-slot score for 300 s. Worse, `retryCount` is per cache **entry**, not per inspection (reset only at `:3695`), so a new `INSPECT_READY` can begin already exhausted and finalize on its first call. **VERIFIED (code).**

**C4 — HIGH/UNKNOWN — "nil link + nil texture" is treated as an empty slot** (`:3680-3690`), overwriting `.time` with a fresh stamp while keeping the old links. This is a second "partial looks fresh" route that survives C1/C3. Reachability is **UNKNOWN**: the documented race is texture-present/link-nil; whether any client returns nil for both on an equipped slot mid-inspect is unverified.

**C5 — MEDIUM — out-of-range gear swaps never mark stale.** `UNIT_INVENTORY_CHANGED` puts `isCloseEnoughToAsk(unit)` in the outer condition (`:3869-3884`), so `.stale` is set only for units already inside the ask radius. At 30 yd a raid member's swap is invisible and the old score is served as fresh for up to 300 s. Dropping the gate must also add a cheap skip in the 0.5 s tick, or the 0.8.7 tick cost returns. **VERIFIED (code).**

**C6 — MEDIUM — no eviction.** One entry per inspected GUID, unbounded for the session; no cap, TTL eviction, or logout handler. In a hub session this grows by one player per inspected GUID. `GetInspectStats` walks the whole table, but only on `/tt diag`. **VERIFIED.**

**C7 — MEDIUM — an incomplete entry that can never resolve has no terminal state.** The retry only re-runs while the unit still resolves by token/GUID (`:3700-3712`); otherwise the entry stays `incomplete` (with no time, or with C1's old time) forever, and every 0.5 s tick re-tests it for target/queue/40 raid units. **VERIFIED (code).**

**C8 — MEDIUM — spec can be fabricated for a record with no spec data.** Spec fields are written only when a spec/talent API answers (`:3721-3748`), but the record still gets items+time; `GetSpecialization` then falls back to `cached.specIndex or 1` (`:5293`) and `GetTalentPoints` returns 0/0/0, so the tooltip can render "Arms [0/0/0]" for a unit whose spec was never read. This is the Retail/Forever secret-restricted case; classic-family talent APIs answer. `detect_test.lua:1125-1128` deliberately pins the fallback value, so any change must move that pin. **VERIFIED (code).** (Reported only; it is a design decision, not a one-line fix.)

**C9 — LOW.** `specID` is write-only; `inspectStats.ready` counts incomplete retries so "ready" ≠ "complete"; `.stale` is consulted only by `isCacheFresh` (readers serve stale data indistinguishably); `0` is overloaded as "no GetTime" for freshness but as "no data" in `GetLastCacheTime` (unreachable on the five supported clients); the item-request throttle `TT_GS._itemRequestTime` (`gearscore.lua:102-118`) is never pruned; and heirlooms are scored at ilvl 187.05 then returned as ilvl 0 while still counting toward the average denominator (`gearscore.lua:288-313, 540-541`), so heirloom gear raises GS and lowers the printed iLvl. `gearscore.lua` is an invariant — report only.

---

## 3. Portrait cache — what is real, what is unpinned

Portrait creation is `ensureTooltipPortrait` (`main.lua:742-775`); 3D caches on `TacoTipPortrait3D.tacoTipModelKey = UnitGUID(unit)` (`:1240-1250`) and is torn down only on a proven unit change (`:1507-1543`); the 2D fallback repaints via `SetPortraitTexture` on every render (`:1263-1266`). The side is cached per tooltip in `state.portraitSide` / `state.portraitAnchored` (`:1184-1219`), keyed on portrait scale and invert flag. This core design is sound and the last two releases' blink/bleed fixes are intact (pinned at `tooltip_test.lua:3149-3210, 3442-3480`).

**P1 — HIGH (decision needed).** The invariant and the 2026-10-21 geometry audit name `getPortraitSideRightEdge` as the only sanctioned reader; **that function does not exist in the tree**. The side is decided from `tooltip:GetRight()` inside the render (`:1192-1194`) — the read the audit classified as the operator's off-screen defect. The pins for the sanctioned-reader design are **commented out** ("Reverted on 2026-10-23 (unmerged experimental prototype)", `tooltip_test.lua:2253-2256 … 2525`), and `load_test.lua:1404-1407` omits `:GetRight(` from its geometry tripwire. So the suite is green with the disputed read present. Either the audit must be marked superseded and the dead pins deleted, or the defect is unmitigated — an operator call, not another code change.

**P2 — MEDIUM.** The side cache key omits `tooltip_scale` (applied at `:1091-1092`), tooltip width, and UI-scale changes; with no `UI_SCALE_CHANGED`/display-size observer in core, the side can freeze until the next clear. **VERIFIED (code); impact ASSUMED.**

**P3 — MEDIUM.** The 2D path has no unit key and is entirely unpinned (no test sets `tooltip_portrait_3d=false`); the 3D path re-issues `SetPortraitZoom`, `SetAlpha(1)` and `Show()` every render while the client re-drives unit tooltips at `TOOLTIP_UPDATE_TIME` (0.2 s) plus every GearScore item completion. Cost **ASSUMED** (unmeasured); sites **VERIFIED**.

**P4 — MEDIUM/UNKNOWN.** The classic `GameTooltip` declares no `OnShow`, so the non-unit clear layer never installs there (`:2816-2820`), and `OnHide`/`OnTooltipCleared` return early during a unit-frame periodic update (`:2807-2831`). A unit-frame hover followed by non-item/non-spell tooltip content can therefore retain the previous portrait. Mechanism **VERIFIED**; player-visible bleed **ASSUMED** — needs one in-game quest/text-tooltip check on classic_anniversary.

**P5 — LOW/coverage.** `portraitHide` and `portraitDestroy` increment in the same branch, so diag's "teardowns N (destroys: M)" always prints N==M; `portraitSetFailed` is never printed; the state doc says `"LEFT"|"RIGHT"` while values are lowercase; the zoom default is 0.75 in `options.lua:97` but `or 0.7` in three fallbacks; the in-game WoWUnit suite still pins 72×96 / 108×144 (`Tests/TacoTip_Forever_Tests.lua:313-315, 329-330`) against production's 66×88 / 99×132 — test lag, not a production bug.

---

## 4. `/tt diag` and the "unresolved unit" on classic_anniversary

**Verdict: a false positive in the diagnostic, not a shipped-behaviour defect.** The working tooltip, the green suite, and the code trace agree; the operator's TBC observation is real but the line it raised over-reports.

- The problem line is `main.lua:3704-3706`: "Unit resolution failed N time(s) (last cause: '…')". `resolveTooltipUnitFailed` is written at exactly two places: the render path `:1620` and the GearScore item-load callback `:1332`. The counter is **cumulative since /reload and never reset**.
- A normal client-driven unit render resolves: the passed token exists (`:1012-1016`), or `GetOwner().unit` covers unit-frame hovers (`:1043-1048`), or `IsUnit("mouseover")` covers 3D world hovers (`:1056-1061`). `classic_era` and `classic_anniversary` are content-identical for the tooltip/unit-frame scripts (CRLF-only diff), `TooltipUtil` is absent on **both** (mainline-only TOC gate), and TBC's `TooltipDataProcessor` cannot fire because the classic template mixes in `GameTooltipMixin` only — so TBC uses the same script hook with `data == nil` that Era does.
- The callback path has **no unit argument** and does not check that the tooltip still shows that unit. A GearScore item-load completion that lands after the cursor moved (bag, another player, or a hidden tooltip) increments the counter as `gs-callback-no-unit`. That is normal churn. The older cause `unresolved-unit` requires `GetUnit` to have returned a *name* for a stale token; whether that happened in the operator's run is **UNKNOWN** without the exact line, but either cause is reported as a "problem" with no time window and no denominator.
- Era-clean / TBC-dirty is therefore **session history, not client behaviour**: a cold TBC item cache produces more `ContinueOnItemLoad` completions; one landing after the tooltip moved is enough to leave the line up for the rest of the session. A single `unresolved-unit` render can stick the same way.
- The harness **pins the false positive**: `tooltip_test.lua:4050-4069` drives `TacoTip_GSCallback`, asserts `resolveTooltipUnitFailed +1`, and calls that "unresolvable unit counts a resolve failure". Any fix must move this pin.

**D1 fix shape (not applied):** count callback misses in a separate `TT.ev.gsCallbackNoUnit`; count render misses only while `tooltip:IsShown()`; report "failed N of M unit renders"; print the callback misses as a neutral line beside the existing "unit resolves" line. Pins: M2 asserts `gsCallbackNoUnit +1` **and** `resolveTooltipUnitFailed` unchanged; a sibling pin drives a genuinely unresolved shown render; `load_test.lua:1215-1291` proves `gsCallbackNoUnit=3, failed=0` still reports "none detected".

**D2 — HIGH — the 0.8.7 cache block is dead code.** `reportActiveUnitContext` guards on `type(CI.GetUnitData) == "function"` (`:3480`) and reads `cached.gearScore / avgItemLevel / specialization` (`:3487-3490`). The library has **no `GetUnitData`** anywhere (whole-tree grep; the public cache surface is listed in §2), and those three fields are never written. So the changelog's "prints cached inspection data state (age, stale, incomplete, GS, iLvl, spec)" never runs. Recommended: add a public `GetUnitData(unitorguid)` that returns the cache record (the plan's Task 2 scope), or rewrite the block on `GetInspectStats` + `GetLastCacheTime` + the getters.

**D3 — HIGH — the portrait line is always "Disabled".** `:3530-3537` reads `cfg.show_avatar` / `cfg.avatar_3d`; the real keys are `tooltip_portrait` / `tooltip_portrait_3d` (defaults `options.lua:93-97`). Nothing writes the old names, so `/tt diag` reports "portrait mode: Disabled" for every user, including the default portrait-on install, and never prints the zoom. Fix the two key names and add a pin.

**D4 — LOW.** `portraitHide`/`portraitDestroy` are equal by construction; `portraitSetFailed` is write-only; `totalErrorsCaught` and `resolveTooltipUnitFailed` are session-cumulative, so one transient makes every later diag report a problem; the "problem" list never says "since /reload".

---

## 5. Packaging, lint, and cross-addon compatibility

**G1 — main verifier FAIL (VERIFIED).** `Tools/verify_release.sh --worktree` fails its single-`.toc` check because the archive now contains 7 TOCs (LibRangeCheck ×4, LibRangeCheck/LibStub, LibSharedMedia, TacoTip). The intended rule is "exactly one .toc **at the package root**"; the check greps the whole listing (`Tools/verify_release.sh:139-149`). Recommended: scope the check to root (matches intent, keeps library metadata), or export-ignore every unloaded library. Do not delete library files before checking licenses/loaders.

**G2 — luacheck scope (VERIFIED).** 85 warnings / 0 errors in 102 files; all warnings are in the 13 newly vendored files (LibDBIcon, LibRangeCheck, LibSharedMedia and their nested CallbackHandler/LibStub/tests). Authored files are 0/0 in 42. Recommended: exclude `Libs/` (or the three unloaded libraries) from lint and reword the gate to "authored files zero-warning", or update the top-level gate. Do not rewrite third-party code.

**G3 — extras harness FAIL (VERIFIED).** 6 distinct failed checks, repeated per variant: (a) TOC `## Interface` includes `120107`, the assertion still expects `…, 120105` — test drift, update the assertion; (b) `LB_SCAN`/`LB_SCAN_BUSY` are unused because the scan button is deliberately "Disabled Temporarily" (`RankBrowser.lua:1285, 2703`) — retire the unused-key assertion for those two, never re-enable scan; (c) `LibClassicInspector` alias is displaced and its minor downgraded — a **real** cross-addon defect, see G4; (d+e) the scan control tests assert a scan starts, but scan is intentionally disabled — retire/comment those two with the blocked-feature note, do not "fix" by enabling.

**G4 — the bundled inspector takes the `LibClassicInspector` alias by force (VERIFIED).** `LibForeverInspector.lua:18-32` writes `LibStub.libs["LibClassicInspector"] = lib` and `minors[...] = 2` unconditionally. A real LibClassicInspector already loaded at minor 18 is displaced and relabelled. The Extras harness proves it (`TacoTip_Extras/Tests/harness/load_test.lua:8945-9111`); the two assertions are red. Fix: publish the alias only when the name is free (or already points at this library), which still satisfies the "name free → alias published" half (minor 2) and keeps the convenience.

**G5 — vendored-library provenance (VERIFIED).** `LibDBIcon-1.0`, `LibRangeCheck-2.0`, `LibSharedMedia-3.0` were added in `4209bdc`; none is referenced by `main.lua`/`options.lua`/`TacoTip.toc` (LibSharedMedia is only resolved optionally via `LibStub(..., true)`, and the vendored copy is never loaded). `.gitattributes` export-ignores only LibDataBroker and LibDBIcon, so LibRangeCheck and LibSharedMedia **do ship**, and `THIRD_PARTY_NOTICES.md` lists none of the three. Recommendation: export-ignore every unloaded library (and keep the notices honest), or load LibSharedMedia deliberately and add its notice. The current state is both dead weight and a licensing/provenance gap.

**G6 — docs drift (VERIFIED).** `AGENTS.md`/`workshop.md` still say "0 warnings in 88 files"; `workshop.md` names `getPortraitSideRightEdge` as the only sanctioned reader although it does not exist; the cache plan is unchecked; `README.md` says `status: released` while the operator's last recorded state (2026-10-25) says 0.8.7 is not released. Confirm the release state before touching the version or README.

---

## 6. Test coverage gaps that matter for 0.8.8

Unpinned today: the 250 ms retry, the retry cutoff and per-entry budget (C1-C3), slot clearing on unequip (C2), stale marking on `UNIT_INVENTORY_CHANGED` in/out of range (C5), cache growth/eviction (C6), unreachable incomplete entries (C7), the fabricated-spec record's tooltip effect (C8), the 2D portrait path, `tooltip_scale`/UI-scale side invalidation, the diag "cached data" and "portrait mode" blocks, and a tripwire that the render contains no `GetRight` read. Every GearScore harness test replaces `GetInventoryItemMixin` with a mock, so the library cache path itself is only exercised by the INSPECT_READY test, not asserted.

`gearscore_test.lua:474-480` narrates SET B as 3314 (halving a lone 2H) while `:505` asserts 3625 — which is what the code produces, because Titan's Grip needs BOTH links (`gearscore.lua:501-511`). The comment is stale and would mislead a formula "fix".

---

## 7. Suggested 0.8.8 order (no work authorised by this report)

1. **Restore gate truth without behaviour change:** scope the verifier's TOC rule to root; fix the luacheck gate/exclusions; align the extras assertions (120107, orphan locale keys, disabled scan) and comment them as blocked-feature; complete `.gitattributes`/notices for the vendored libs.
2. **Fix G4** (alias only when free) with the harness pin already written.
3. **Cache correctness (plan Task 2, with the plan's warnings):** clear emptied slots; gate `isCacheFresh` **and** `GetLastCacheTime` on `.incomplete`; do not simply nil `time` — keep a `lastCompleteTime` so a gear refresh does not blink the GS row off; reset `retryCount` on a fresh inspect and remove the 4-retry finalize; move staleness outside the distance gate plus a cheap tick skip; add the 512-entry eviction with an in-flight guard; add `GetUnitData` or rewrite the diag block. One revert-to-fail pin per item.
4. **Diagnostics:** split the GS-callback miss counter, gate the render counter on `IsShown`, report "N of M renders", fix the two phantom config keys, print `portraitSetFailed`, and state the since-/reload window on cumulative lines.
5. **Portrait decision:** either restore `getPortraitSideRightEdge` and its pins, or mark the geometry audit superseded and delete the dead commented tests; fix the in-game 72×96 pins either way.
6. Re-run all five gates on the operator's two branches, then ask for the in-game pass on classic_anniversary (portrait side at the screen edge; quest/text tooltip after a unit hover; `/tt diag` after a cold hover-and-move-away).

**Hands-up:** P1 (sanctioned portrait reader) is a direct contradiction between two in-tree records; the operator must choose the contract before a lane touches it. **Assumption to confirm:** the exact `/tt diag` cause string the operator saw (`unresolved-unit` vs `gs-callback-no-unit`) — it changes which path is proven but not the false-positive verdict.

---

*Artifacts: this file; desk journal `desks/audit-v088-readiness/journal.md`; done signal `desks/audit-v088-readiness/.signals/`. No production file was modified; `git status` shows only the desk and the pre-existing untracked `luacheck_report.txt`/`.dsh-progress/`.*
