# fix-main-hunter — Journal

## 2026-10-19 — Desk opened
- **Purpose:** Close the MAIN-addon findings from the final silent-failure hunter audit (`bench/audits/2026-10-19-final-hunter.md`): M-1 (unguarded + discarded `tooltip:IsUnit`), M-2 (guild-guard pcall broader than its comment claims, mis-counting), L-1 (discarded `pcall(SetWidth)`), L-3 (discarded `pcall(CI.DoInspect)`), L-4 (unguarded `TT:RefreshCharacterFrame()` from the global GS-callback path), plus the CHANGELOG subsection.
- **Scope:** `main.lua`, `Tests/harness/*` (pins only — NO new harness patterns), `CHANGELOG.md` (the `## [0.8.4]` section only), `desks/fix-main-hunter/`. **NOT** `TacoTip_Extras/` (another lane owns it), NOT `Locale/`, NOT `*.toc`/versions, NOT the user-facing `README.md`, NOT `.gitattributes`, NOT `Tools/`, NOT `gearscore.lua`, NOT `options.lua`, NOT `bench/`, NOT other desks.
- **Constraints:** Classic Era inspect range gate FROZEN (`NEARBY_ASK_YARDS` 20/40, `INSPECT_INTERACT_DISTANCE_INDEX` 1, distance-first ordering, probe guard, learned ceiling, all timings); raw GearScore formula UNTOUCHED; Retail bracket stays at the shared 1000; no two-argument `CanInspect` anywhere; no commit, no staging.
- **Baselines (re-run before the first edit, 2026-10-19):** MAIN `bash Tests/harness/run_all.sh` = **70/70** on lua5.1, **70/70** on lua5.4, **70/70** on luajit; `luacheck .` from the repo root = **0 warnings / 0 errors in 87 files**; `bash Tools/verify_release.sh` = **PASS**.
- **Bench-read:** `bench/audits/2026-10-19-final-hunter.md` (M-1, M-2, L-1, L-3, L-4); desks `final-hunter` (no journal file — its content is the bench audit) and `fix-main-batch8` (the harness conventions: pins ride the existing harnesses, one `batchN_*_test.lua` per batch, the mock-contract rule "a contract assertion must run where the mock is INSTALLED", and the mock-fidelity rule "a mock must reproduce what the real API LACKS, not just what it returns").
- **Next step:** implement the five code fixes, pin each one revert-to-fail, then the CHANGELOG subsection and the full re-validation.

## 2026-10-19 — Mirror evidence (the guild guard, all five branches)

Read from `/home/sam/wow-ui-source` (read-only), one branch per family.

**Where the global `InspectGuildFrame_Update` exists** (`git grep -n "function InspectGuildFrame_Update" origin/<branch>`):
- `origin/live`: `Interface/AddOns/Blizzard_InspectUI/Mainline/InspectGuildFrame.lua:17` — the Mainline variant, which carries the unguarded realm line at `:22`: `InspectGuildFrame.guildRealmName:SetFormattedText(INSPECT_GUILD_REALM, guildRealmName)`.
- `origin/forever`: **two** variants define it — `Mainline/InspectGuildFrame.lua:17` (realm line at `:18`/`:22`) and `Camelot/InspectGuildFrame.lua:17` (no realm line; the guild NAME is the nil the block formats).
- `origin/classic_era`, `origin/classic_anniversary`, `origin/classic_titan`: **NO global at all.** The Classic family reaches the same frame through `Cata/InspectGuildFrame.lua`, which defines `InspectGuildFrameMixin:Update()` — a mixin METHOD. `git grep -n "function InspectGuildFrame_Update" origin/classic_era` returns nothing on all three.

**The install path.** `Blizzard_InspectUI.toc` carries `## LoadOnDemand: 1` on `origin/live` and `origin/forever`, so the global does not exist when TacoTip loads. The addon installs the guard from the `ADDON_LOADED` handler, in the `addon == "Blizzard_InspectUI"` branch of `onEvent` — i.e. when the player first opens the inspect pane. **That path was not touched by this lane**, and it is now PINNED (below): the guard installs on the modern pair and is a no-op on the Classic family.

**The classification data.** `C_PaperDollInfo.GetInspectGuildInfo(unit)` publishes **four** values — achievement points, member count, guild name, realm name (`Blizzard_APIDocumentationGenerated/PaperDollInfoDocumentation.lua:95` on `origin/live`, `:104` on `origin/forever`). The fourth (the realm name) is nil for a player with no guild, which is the precondition of Blizzard's own defect.

## 2026-10-19 — IMPLEMENTATION

### M-1 — the unguarded, discarded `tooltip:IsUnit(unit)` (`main.lua:1139-1170`)
- The call is **gone**; the arm is now a plain `return unit`.
- **Why removed and not implemented as a rejection:** the answer was discarded (both branches returned `unit`), so no caller can depend on it. Implementing "refuse a unit the tooltip is not about" would CHANGE THE RESULT for a valid state: every caller passes a unit the tooltip is already about — `onTooltipSetUnit` passes the token it just read from `tooltip:GetUnit()`, `ApplyTooltipAppearance` passes an already-resolved unit. The GetUnit→IsUnit disagreement chain the file describes is handled where it actually arises (the GetUnit arm), with a pcall-guarded `IsUnit`, the same idiom as `tooltipIsMouseover`.
- Reachability note (checked before changing anything): the dead call is only reachable from the callers that PASS a unit — `onTooltipSetUnit` and `ApplyTooltipAppearance`. `TacoTip_GSCallback` calls `resolveTooltipUnit(GameTooltip)` with NO unit, so it takes the TooltipUtil/GetUnit arms; the audit's "called from TacoTip_GSCallback" is about the call site of `resolveTooltipUnit` being unguarded, not about this specific branch.
- Result unchanged for every valid state; a raising `IsUnit` no longer aborts the render.

### M-2 — the guild guard (`main.lua:3728-3803`)
- **The swallow is untouched and unconditional**: `pcall(update, ...)` swallows in BOTH buckets, the install path is untouched, `_tacoTipInspectGuildGuarded` is untouched, the `ADDON_LOADED` hook is untouched, and `isKnownGuildRealmDefect()` is pcall-guarded so a failure inside it falls into the "other" bucket and never escapes.
- Only the COUNTING changed: `inspectGuildGuardCaught` (the known guild case) vs `inspectUpdateErrors` + `lastInspectUpdateError` (anything else, with its message). Both are printed by `/tacotip diag` (`main.lua:4044-4054`).
- The classification asks the CLIENT'S OWN DATA, not the error text: the wording of a C-API argument error varies by client and locale, and a text match would file an unrelated raise under a cause we had not proved. If the probe cannot run, the error goes to the honest bucket — a case that cannot be proved is not a case that may be claimed.
- The comment no longer claims the wrapper is "deliberately narrow": it now says what it actually does.

### L-1 — the discarded width-cap pcall (`main.lua:95-154`)
- The failure is counted (`tooltipMaxWidthFailed`).
- **A counter, not `callLabeled`:** `callLabeled` RE-RAISES with the call site named, which would abort the whole enhancement — the tooltip render runs inside `safeCall`, so the raise would be caught at the top and the tooltip would lose every line it had built. A cosmetic width cap that fails must not cost the player the GearScore line. The file's own idiom for a discarded widget call is the counter (`portraitSetFailed`, the discarded portrait `SetUnit`).
- The memo (`_tacoTipMaxWidth`) is still written on failure, so the hot path does not re-issue a call that will keep raising; the count says how often.

### L-3 — the discarded inspect-trigger pcall (`main.lua:2025-2037`)
- Counted as `inspectTriggerFailed`, beside the other cold-path counters. The library counts its own notifies and refusals; a raise in the CALLER's copy of the trigger was lost.

### L-4 — the unguarded character-pane refresh (`main.lua:1544-1573`)
- `pcall(TT.RefreshCharacterFrame, TT)`; on failure it counts `characterPaneRefreshFailed` and returns false (the function's boolean return, which the caller ignores).
- The pending→ready budget is spent either way, so a failed repaint is not retried on every item-load callback that follows.
- **Other call sites of the same method, left alone (out of scope, recorded here):** `main.lua:3570` (the `CharacterFrame` OnShow adapter — an engine script handler), `main.lua:4254` (`PLAYER_EQUIPMENT_CHANGED`, inside the `safeCall(onEvent)` boundary) and `main.lua:4367` (the `ADDON_LOADED` path). The audit named only the GS-callback path; the other three are inside boundaries that already handle a raise.

### CHANGELOG
- One subsection, `### Final hunter fixes — five discarded failures (M-1, M-2, L-1, L-3, L-4)`, inside the existing `## [0.8.4]` section. No version bump; `0.8.3` and earlier untouched; the chronicler's re-pointed citations left as they are.
- **The user-facing `README.md` needs NO change** for these five items: every one of them is internal robustness or diagnostic counting. Nothing about the rendered tooltip, the options, the colours, the stored data or the player's workflow changed, and no new setting, no new line and no new command was added. `/tacotip diag` gains five lines, and `README.md` does not document the diagnostic's counter list.

## 2026-10-19 — PINS

`Tests/harness/tooltip_test.lua` (no new harness file; the pins ride the harnesses that already own the mock environments — the file's own convention):
- **the guild guard's install path** — fires `ADDON_LOADED` with `addon == "Blizzard_InspectUI"`: the guard installs on the modern pair (the global is replaced by the guard, the latch is set) and is a **no-op on the Classic family** (no global to wrap, no latch).
- **the swallow** — the guildless-inspect error does **not** escape: `pcall(InspectGuildFrame_Update)` returns true.
- **the two-bucket split** — the guildless case counts in `inspectGuildGuardCaught` and NOT in `inspectUpdateErrors`; a DIFFERENT error counts in `inspectUpdateErrors` with its message and NOT in the guild bucket.
- **M-1** — a raising `IsUnit` does not abort the unit render: the error sink stays empty and the render ran on past the unit resolution (the class colour is stored a few steps later, so it is only set when the render got that far).
- **L-1** — a raising `SetWidth` counts a width-cap failure.
- **L-3** — a raising `DoInspect` counts a trigger failure.
- **the new diagnostic lines** — `inspect guild guard caught`, `inspect update errors (other)`, `tooltip width cap failures`, `inspect trigger failures`, `character pane refresh failures`.

`Tests/harness/batch8_pane_test.lua` (the character-pane harness already owns the pane's OnShow hook):
- **L-4** — a raising character-pane refresh does not escape into the item-load callback, and is counted.

`Tests/harness/mock_contract.lua`:
- The new `C_PaperDollInfo.GetInspectGuildInfo` mock is pinned against the client's **four** published values (`PaperDollInfoDocumentation.lua:95` live / `:104` forever), with the branch-qualified citation. `Tests/harness/README.md` carries the readable copy and the new coverage lines.

Check counts: `tooltip_test` 171 → **183** (Classic family) and 172 → **191** (modern pair); `batch8_pane_test` 27 → **29**. The suite's invocation count is unchanged at **70** — no new harness file, no new runner line.

## 2026-10-19 — Validation (all green, all three interpreters)
- MAIN `bash Tests/harness/run_all.sh`: **70/70** on lua5.1, **70/70** on lua5.4, **70/70** on luajit.
- `luacheck .` from the repo root: **0 warnings / 0 errors in 87 files** (the four files this lane touched are 0/0 on their own).
- `bash Tools/verify_release.sh`: **PASS**.
- Revert-to-fail proofs, each applied to an ISOLATED COPY (`/tmp/opencode/revertproof`, the working tree was never mutated) and each quoting the red:

| # | reverted | red |
|---|---|---|
| M-1 | the unguarded `tooltip:IsUnit(unit)` restored in `resolveTooltipUnit` | `2/191 FAILED` — "a raising IsUnit does not abort the unit render errors=1" and "...the render ran on past the unit resolution classColour=nil" |
| M-2 | the OLD single-bucket wrapper restored (everything counted as a guild-guard catch) | `2/191 FAILED` — "...counts in the honest bucket, NOT in the guild bucket other=0 caught=2" and "...the honest bucket keeps the message last=nil" |
| L-1 | the discarded `pcall(SetWidth)` result restored | `1/191 FAILED` — "a raising SetWidth counts a width-cap failure tooltipMaxWidthFailed=0" |
| L-3 | the discarded `pcall(CI.DoInspect)` result restored | `1/191 FAILED` — "a raising inspect trigger counts a trigger failure inspectTriggerFailed=0" |
| L-4 | the unguarded `TT:RefreshCharacterFrame()` restored | `2/29 FAILED` — "a raising character-pane refresh does not escape into the item-load callback (... HUNTER_PIN_L4_PANE_REFRESH)" and "...and is counted (characterPaneRefreshFailed=0)" |

Note on the M-2 proof: the SWALLOW checks stay GREEN under the old wrapper — they must, because the swallow is what the old code already did. The proof shows the pins detect the COUNTING change, and the swallow is preserved on both sides.

## 2026-10-19 — Constraint compliance
- **Range gate FROZEN** — `Libs/LibForeverInspector/LibForeverInspector.lua` was NOT touched by this lane (mtime 23:50, before this session's first edit at 23:55). `INSPECT_INTERACT_DISTANCE_INDEX = 1` (`:411`), `NEARBY_ASK_YARDS = isClassic and 20 or 40` (`:429`), the squared-distance ceiling (`:4974`), the distance-first ordering and the probe guard all unchanged.
- **Raw GearScore formula UNTOUCHED** — `gearscore.lua` not modified (mtime 2026-10-18 14:38). The Retail bracket still holds at the shared 1000 (`BRACKET_SIZE = 1000`, `gearscore.lua:179`, with the unknown family on the same default at `:193`), and `gearscore_test.lua` pins it.
- **No two-argument `CanInspect` anywhere** — the only live call is the one-argument `pcall(api, unit)`; the two-argument form appears only in comments describing Blizzard's own `InspectFrame_Show` call.
- **Files this lane touched** (mtime check): `main.lua`, `CHANGELOG.md`, `Tests/harness/tooltip_test.lua`, `Tests/harness/batch8_pane_test.lua`, `Tests/harness/mock_contract.lua`, `Tests/harness/README.md`, `desks/fix-main-hunter/`. **Not touched:** `TacoTip_Extras/` (another lane), `Locale/`, `*.toc`, versions, the user-facing `README.md`, `.gitattributes`, `Tools/`, `gearscore.lua`, `options.lua`, `Libs/`, `bench/`, other desks. `bench/audits/2026-10-19-pre-publish-in-game-checklist.md` and `desks/fix-extras-hunter/journal.md` changed during this session — **another lane's** work, not this one's.
- **No commit, no staging** (`git diff --cached` empty).

## 2026-10-19 — [signal:done] Final hunter lane complete
- **Worked on:** M-1 (the discarded unguarded `IsUnit`), M-2 (the guild guard's honest counting, swallow untouched), L-1 (the discarded width cap), L-3 (the discarded inspect trigger), L-4 (the unguarded character-pane refresh), the pins for all five, the mock-contract entry, and the CHANGELOG subsection.
- **Current state:** all five implemented, pinned and revert-proven; MAIN **70/70** on lua5.1 / lua5.4 / luajit; lint 0/0 in 87 files; `Tools/verify_release.sh` PASS. No commit, no staging. The user-facing README needs no change.
- **Next step:** operator review. **Open, not addressed here:** L-2 (`gsCallbackPending` is one slot — a second nested guid overwrites the first, so the "no work is lost" claim is false) and L-5/L-6 (Extras-side, another lane's). Also recorded but not changed: the three other `TT:RefreshCharacterFrame()` call sites (`main.lua:3570`, `:4254`, `:4367`) and the unguarded `tooltip:GetOwner()` reads at `main.lua:1121`/`:1191`, none of which the audit raised.
